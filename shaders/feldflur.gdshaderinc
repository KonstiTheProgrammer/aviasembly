// FELDFLUR (2026-10-02): die Felder der Ebenen, gestochen scharf aus der Lage im Flurrahmen.
// Die TEILUNG ist dieselbe wie TerrainWorld._feld_teil (dort steht die Begruendung) — Hecken
// (Bewuchs), Grasmaske, Karte und Fernschuerze rechnen auf der CPU mit denselben Tabellen.
// Wer an der Teilung etwas aendert, aendert beide Stellen.
// Eingaben je Eckpunkt (TerrainWorld._feld_eckpunkte): UV = (U, V) in Metern im gedrehten Rahmen
// des Flurblocks (innerhalb eines Blocks linear in x/z, wird also exakt interpoliert),
// CUSTOM0 = (Feldstaerke, Abstand zur Flurblock-Grenze, Band, Gewann). Die Bodenfarbe der Chunks
// ist dort Wiese. Gebraucht aus gelaende_kern: boden_tex; den Wind reicht es herein.
//
// KOSTEN (tools/_gelaende_zeit.gd, 4K, Stellung "Flur 300 m"): erste Fassung mit dem 32-Bit-Hash je
// Pixel 5,4 ms. Der Shader ist latenzgebunden (gross, wenige Faeden je Kern): neun abhaengige
// Zugriffe kosteten 2,1 ms, neun unabhaengige 0,75. Daher (1) VORGERECHNETE TABELLEN als Texturen
// statt Hash, dicht gepackt (sieben Zugriffe in zwei Wellen), (2) Band/Gewann vom Eckpunkt, (3) das
// ganze FELD vom Eckpunkt (Vertex-Shader, feld_eckpunkt) — je Pixel wird nur noch in Dreiecken
// ueber einer Feldkante gesucht. Jetzt 2,4 ms aus 300 m, 1,15 aus 60 m, 0,5 in "Mittel 700 m".
uniform float feld_an = 1.0;     // 0 = Felder nicht zeichnen (Messung)
// Tabellen (TerrainWorld._feld_tabellen), Werte = feld_hash, float32 exakt:
uniform sampler2D feld_band : filter_nearest, repeat_disable;      // FT_NB x 1: (Grenze, Versatz, Kante, -)
uniform sampler2D feld_gewann : filter_nearest, repeat_disable;    // FT_NJ x FT_NB: (Grenze, Streifenzahl, Kante, -)
uniform sampler2D feld_breiten : filter_nearest, repeat_disable;   // FT_NJ x FT_NB: Summenbrueche c1..c4
uniform sampler2D feld_streifen : filter_nearest, repeat_disable;  // FT_NJ*5 x FT_NB: (geteilt, Teilung, Kantenarten, -)
uniform sampler2D feld_frucht : filter_nearest, repeat_disable;    // FT_NJ*5 x FT_NB: (Frucht, Schwelle) Teil 0, Teil 1

const int FT_NB = 52;      // = TerrainWorld.FT_NB
const int FT_NJ = 42;      // = TerrainWorld.FT_NJ
const float FELD_BAND = 300.0;
const float FELD_LANG = 400.0;
const float FELD_ZITTER = 0.36;
const float FELD_RAND_D = 10.0;
const vec3 FELD_HECKE_BODEN = vec3(0.19, 0.30, 0.16);
const vec3 FELD_ERDE = vec3(0.62, 0.52, 0.37);

vec4 feld_tb(int ib) {
	return texelFetch(feld_band, ivec2(clamp(ib, 0, FT_NB - 1), 0), 0);
}

vec4 feld_tg(int ib, int j) {
	return texelFetch(feld_gewann, ivec2(clamp(j, 0, FT_NJ - 1), clamp(ib, 0, FT_NB - 1)), 0);
}

vec4 feld_tw(int ib, int j) {
	return texelFetch(feld_breiten, ivec2(clamp(j, 0, FT_NJ - 1), clamp(ib, 0, FT_NB - 1)), 0);
}

float feld_grenze(int i, float h, float l) {
	return (float(i) + (h - 0.5) * (2.0 * FELD_ZITTER)) * l;
}

// halbe Breite je Kantenart: Furche, Rain, Feldweg, Hecke (TerrainWorld.FELD_HALB). Als Funktion
// statt Array: dynamisch indizierte Arrays landen auf der GPU im Speicher statt in Registern.
float feld_halb(int a) {
	return a == 0 ? 0.30 : (a == 1 ? 1.1 : (a == 2 ? 2.0 : 3.0));
}

int feld_gewann_kante(float r) {
	return r < 0.20 ? 2 : (r < 0.33 ? 3 : (r < 0.85 ? 1 : 0));
}

// Summengrenzen der Fruechte (TerrainWorld.FRUCHT_BIS)
int feld_frucht_aus(float h) {
	if (h < 0.04) { return 0; }      // Weide
	if (h < 0.22) { return 1; }      // Weizen
	if (h < 0.32) { return 2; }      // Gerste
	if (h < 0.40) { return 3; }      // Raps
	if (h < 0.50) { return 4; }      // Mais
	if (h < 0.62) { return 5; }      // junge Saat
	if (h < 0.74) { return 6; }      // gepfluegt
	if (h < 0.83) { return 7; }      // Stoppel mit Schwaden
	if (h < 0.92) { return 8; }      // Maehwiese
	if (h < 0.97) { return 9; }      // Kartoffeln
	return 10;                        // Sonnenblumen
}

struct FeldZelle {
	int frucht;
	float schwelle;
	float hell;
	vec4 d;        // Abstand zur Kante links, rechts, unten, oben (m)
	ivec4 art;     // deren Art (0 Furche, 1 Rain, 2 Weg, 3 Hecke) — nur gesetzt, wenn nah
	bool kante_nah;
	vec2 lage;     // im Feld: quer ab der linken Kante, laengs ab der unteren (m)
};

// Die Teilung WORTGLEICH zu TerrainWorld._feld_teil (dort aus denselben Tabellen).
// kante_bis: Kantenarten nur, wenn eine Kante naeher liegt.
// ij: Band und Gewann, wenn alle drei Eckpunkte des Dreiecks im selben liegen (sonst -1).
// WARUM: der Gelaende-Shader ist gross, die GPU haelt wenige Faeden je Kern und kann die Latenz
// eines Texturzugriffs kaum verstecken — gemessen kosteten neun voneinander abhaengige Zugriffe
// 2,1 ms in 4K, neun unabhaengige 0,75 ms. Mit Band und Gewann vom Eckpunkt (konvex: liegen alle
// drei Ecken darin, dann jeder Punkt dazwischen) fallen alle Zugriffe bis auf den letzten in eine
// Welle; die volle Suche laeuft nur in den wenigen Dreiecken ueber einer Gewanngrenze.
FeldZelle feld_teil(vec2 uv, float kante_bis, vec2 ij) {
	float u = uv.x;
	float v = uv.y;
	int ib;
	int js;
	vec4 tlo;
	vec4 thi;
	vec4 glo;
	vec4 ghi;
	float b0;
	float b1;
	float vb;
	float s0;
	float s1;
	if (ij.x >= 0.0) {
		ib = int(ij.x + 0.5);
		js = int(ij.y + 0.5);
		tlo = feld_tb(ib);
		thi = feld_tb(ib + 1);
		glo = feld_tg(ib, js);
		ghi = feld_tg(ib, js + 1);
		b0 = feld_grenze(ib, tlo.x, FELD_BAND);
		b1 = feld_grenze(ib + 1, thi.x, FELD_BAND);
		vb = v + tlo.y * FELD_LANG;
		s0 = feld_grenze(js, glo.x, FELD_LANG);
		s1 = feld_grenze(js + 1, ghi.x, FELD_LANG);
	} else {
	// Gewann quer (Band): Grenze i liegt in (i +- 0.36) * l, ein Schritt Korrektur reicht
	ib = int(floor(u / FELD_BAND));
	tlo = feld_tb(ib);
	thi = feld_tb(ib + 1);
	b0 = feld_grenze(ib, tlo.x, FELD_BAND);
	b1 = feld_grenze(ib + 1, thi.x, FELD_BAND);
	if (u < b0) {
		ib -= 1;
		thi = tlo;
		b1 = b0;
		tlo = feld_tb(ib);
		b0 = feld_grenze(ib, tlo.x, FELD_BAND);
	} else if (u >= b1) {
		ib += 1;
		tlo = thi;
		b0 = b1;
		thi = feld_tb(ib + 1);
		b1 = feld_grenze(ib + 1, thi.x, FELD_BAND);
	}
	// Gewann laengs, je Band versetzt
	vb = v + tlo.y * FELD_LANG;
	js = int(floor(vb / FELD_LANG));
	glo = feld_tg(ib, js);
	ghi = feld_tg(ib, js + 1);
	s0 = feld_grenze(js, glo.x, FELD_LANG);
	s1 = feld_grenze(js + 1, ghi.x, FELD_LANG);
	if (vb < s0) {
		js -= 1;
		ghi = glo;
		s1 = s0;
		glo = feld_tg(ib, js);
		s0 = feld_grenze(js, glo.x, FELD_LANG);
	} else if (vb >= s1) {
		js += 1;
		glo = ghi;
		s0 = s1;
		ghi = feld_tg(ib, js + 1);
		s1 = feld_grenze(js + 1, ghi.x, FELD_LANG);
	}
	}
	int n = 1 + int(glo.y * 5.0);
	// Streifen: Summenbrueche der Grenzen (TerrainWorld._feld_tabellen), Vergleich wie die Schleife
	// auf der CPU (x >= acc + w  <=>  Bruch >= c)
	vec4 cw = feld_tw(ib, js);
	float fr = (u - b0) / (b1 - b0);
	int k = 0;
	float c_lo = 0.0;
	float c_hi = n > 1 ? cw.x : 1.0;
	if (n > 1 && fr >= cw.x) { k = 1; c_lo = cw.x; c_hi = n > 2 ? cw.y : 1.0; }
	if (k == 1 && n > 2 && fr >= cw.y) { k = 2; c_lo = cw.y; c_hi = n > 3 ? cw.z : 1.0; }
	if (k == 2 && n > 3 && fr >= cw.z) { k = 3; c_lo = cw.z; c_hi = n > 4 ? cw.w : 1.0; }
	if (k == 3 && n > 4 && fr >= cw.w) { k = 4; c_lo = cw.w; c_hi = 1.0; }
	float x0 = b0 + c_lo * (b1 - b0);
	float x1 = b0 + c_hi * (b1 - b0);
	// zweite Welle: der Streifen selbst und seine Fruechte
	ivec2 sq = ivec2(clamp(js, 0, FT_NJ - 1) * 5 + k, clamp(ib, 0, FT_NB - 1));
	vec4 ts = texelFetch(feld_streifen, sq, 0);
	vec4 tf = texelFetch(feld_frucht, sq, 0);
	// Manche Streifen sind laengs noch einmal geteilt
	float y0 = s0;
	float y1 = s1;
	int teil = 0;
	bool geteilt = ts.x < 0.28;
	if (geteilt) {
		float ym = s0 + (s1 - s0) * (0.3 + 0.4 * ts.y);
		if (vb < ym) {
			y1 = ym;
		} else {
			y0 = ym;
			teil = 1;
		}
	}
	FeldZelle f;
	f.d = vec4(u - x0, x1 - u, vb - y0, y1 - vb);
	f.kante_nah = min(min(f.d.x, f.d.y), min(f.d.z, f.d.w)) < kante_bis;
	f.art = ivec4(1);
	if (f.kante_nah) {
		int arten = int(ts.z + 0.5);
		int teil_art = arten >> 4;
		f.art = ivec4(arten & 3, (arten >> 2) & 3,
			teil == 1 ? teil_art : feld_gewann_kante(glo.z),
			(geteilt && teil == 0) ? teil_art : feld_gewann_kante(ghi.z));
	}
	float fh = teil == 0 ? tf.x : tf.z;
	f.frucht = feld_frucht_aus(fh);
	f.schwelle = 0.15 + 0.7 * (teil == 0 ? tf.y : tf.w);
	f.hell = floor(fract(fh * 61.37) * 16.0) * (1.0 / 15.0);   // 4 Bit, siehe feld_eckpunkt
	f.lage = vec2(u - x0, vb - y0);
	return f;
}

// DAS FELD EINES ECKPUNKTS (im Vertex-Shader): Rechteck (x0, x1, y0, y1) in U/V und
// info = (Frucht + 16 * Kantenarten (8 Bit) + 4096 * Helligkeit (4 Bit), Schwelle).
// WARUM: liegt ein Dreieck ganz in einem Feld (gut 85 % der Dreiecke), braucht der Pixel keinen
// einzigen Tabellenzugriff — die Teilung je Pixel kostete selbst mit Band/Gewann vom Eckpunkt noch
// ~2 ms in 4K (Flur aus 300 m). Eckpunkte gibt es zwanzigmal weniger als Pixel.
void feld_eckpunkt(vec2 uv, vec2 ij, out vec4 rect, out vec2 info) {
	FeldZelle f = feld_teil(uv, 1.0e9, ij);
	rect = vec4(uv.x - f.d.x, uv.x + f.d.y, uv.y - f.d.z, uv.y + f.d.w);
	int arten = f.art.x + 4 * f.art.y + 16 * f.art.z + 64 * f.art.w;
	info = vec2(float(f.frucht + 16 * arten) + 4096.0 * floor(f.hell * 15.0 + 0.5), f.schwelle);
}

// Das Feld aus den Daten der Eckpunkte (alle drei gleich) — ohne Tabellenzugriff.
FeldZelle feld_aus_eckpunkt(vec2 uv, vec4 rect, vec2 info, float kante_bis) {
	FeldZelle f;
	f.d = vec4(uv.x - rect.x, rect.y - uv.x, uv.y - rect.z, rect.w - uv.y);
	f.lage = vec2(f.d.x, f.d.z);
	int code = int(info.x + 0.5);
	f.frucht = code & 15;
	int arten = (code >> 4) & 255;
	f.art = ivec4(arten & 3, (arten >> 2) & 3, (arten >> 4) & 3, (arten >> 6) & 3);
	f.hell = float(code >> 12) * (1.0 / 15.0);
	f.schwelle = info.y;
	f.kante_nah = min(min(f.d.x, f.d.y), min(f.d.z, f.d.w)) < kante_bis;
	return f;
}

// Linie der Breite b alle s Meter (Mitte bei x = s/2 + i*s): Deckung 0..1, geglaettet; wird sie
// schmaler als ein Pixel, geht sie in ihr Mittel b/s ueber (kein Flimmern, gleicher Farbton).
float feld_linie(float x, float s, float b, float fw) {
	float q = abs(fract(x / s) - 0.5) * s;
	float l = 1.0 - smoothstep(b * 0.5 - fw * 0.5, b * 0.5 + fw * 0.5, q);
	return mix(b / s, l, clamp(1.5 - fw / b, 0.0, 1.0));
}

// Weiche Welle 0..1 mit Periode p, in der Ferne 0.5.
float feld_welle(float x, float p, float fw) {
	return 0.5 + 0.5 * cos(x * (6.2831853 / p)) * (1.0 - smoothstep(0.3, 0.7, fw / p));
}

// Feldweg im Querschnitt: de = Abstand zur Mitte. Zwei Fahrspuren, Grasnarbe in der Mitte und
// am Rand.
vec3 feld_weg(float de, vec3 wiese, float aa) {
	float spur = 1.0 - smoothstep(0.30 - aa, 0.30 + aa, abs(de - 0.85));
	vec3 narbe = wiese * vec3(0.90, 0.88, 0.78) + vec3(0.04, 0.03, 0.0);
	return mix(narbe, FELD_ERDE, spur);
}

// Eine Kante auf die Farbe legen: Art a, Abstand de, Glaettung aa.
vec3 feld_kante(vec3 col, vec3 wiese, int a, float de, float aa, float akt) {
	float hw = feld_halb(a);
	float bed = 1.0 - smoothstep(hw - aa, hw + aa, de);
	if (bed <= 0.0) {
		return col;
	}
	if (a == 0) {
		// Furche zwischen zwei Fruechten: dunkle Linie (nur wo Acker ist)
		return col * (1.0 - 0.30 * bed * akt);
	} else if (a == 1) {
		return mix(col, wiese * vec3(1.03, 1.03, 0.95), bed);
	} else if (a == 2) {
		return mix(col, feld_weg(de, wiese, aa), bed);
	}
	return mix(col, FELD_HECKE_BODEN, bed * 0.85);
}

// Die Felder auf die Wiesenfarbe c malen. acker = wie viel davon Frucht ist (fuer Normale/AO).
vec3 feld_malen(vec3 c, vec2 uv, vec4 fd, vec4 rect, vec2 info, float wind, out float acker) {
	// Ableitungen gebuendelt: Meter je Pixel quer/laengs (UV sind Meter), Staerke, Grenzabstand
	vec4 fw4 = fwidth(vec4(uv, fd.xy));
	float fwx = max(fw4.x, 0.002);
	float fwy = max(fw4.y, 0.002);
	vec4 fwr = fwidth(rect);
	float kante_bis = 4.4 + 2.0 * max(fwx, fwy);
	// Alle drei Ecken im selben Feld (die Rechtecke weichen nur um Rundungsfehler ab): Feld vom
	// Eckpunkt. Sonst je Pixel — Band/Gewann vom Eckpunkt, wenn wenigstens die gleich sind.
	bool ein_feld = fwr.x + fwr.y + fwr.z + fwr.w < 0.05 && fwidth(info.x) < 0.5 && rect.y > rect.x;
	FeldZelle f;
	if (ein_feld) {
		f = feld_aus_eckpunkt(uv, rect, info, kante_bis);
	} else {
		bool gleich = fwidth(fd.z) + fwidth(fd.w) < 0.001 && fd.z >= 0.5;
		f = feld_teil(uv, kante_bis, gleich ? fd.zw : vec2(-1.0));
	}
	vec3 wiese = c;
	// EIN FELD GANZ ODER GAR NICHT: die Schwelle schneidet scharf (wie TerrainWorld._feld_wald —
	// darunter steht Wald bzw. Wiese). Weich ueberblendet lagen Baumgruppen in runden, verwaschenen
	// Wiesenflecken mitten im Acker.
	float fs_aa = max(fw4.z, 0.002);
	float akt = smoothstep(f.schwelle - fs_aa, f.schwelle + fs_aa, fd.x);
	// Flurblock-Grenze: Anger (kein Acker), in der Mitte ein Heckensaum
	float rand_aa = max(fw4.w, 0.05);
	akt *= smoothstep(FELD_RAND_D - rand_aa, FELD_RAND_D + rand_aa, fd.y);
	float x = f.lage.x;
	float y = f.lage.y;
	float hell = 0.94 + 0.12 * f.hell;
	vec3 frucht = wiese;
	bool hoch = false;           // stehende Frucht: Schattensaum an der Kante
	if (akt > 0.0) {
		if (f.frucht == 1) {
			// WEIZEN: Gold, Fahrgassen (zwei Spuren alle 20 m), Kornwogen
			frucht = vec3(0.84, 0.67, 0.30) * hell;
			float fg = feld_linie(x - 0.9, 20.0, 0.40, fwx) + feld_linie(x + 0.9, 20.0, 0.40, fwx);
			frucht = mix(frucht, vec3(0.58, 0.50, 0.25), fg * 0.85);
			frucht *= 1.0 + (wind - 1.0) * 1.7;
			frucht *= 1.0 - 0.07 * feld_welle(x, 0.9, fwx);
			hoch = true;
		} else if (f.frucht == 2) {
			// GERSTE: heller, seidig
			frucht = vec3(0.87, 0.77, 0.46) * hell;
			float fg = feld_linie(x - 0.9, 20.0, 0.40, fwx) + feld_linie(x + 0.9, 20.0, 0.40, fwx);
			frucht = mix(frucht, vec3(0.62, 0.58, 0.32), fg * 0.85);
			frucht *= 1.0 + (wind - 1.0) * 1.5;
			hoch = true;
		} else if (f.frucht == 3) {
			// RAPS in Bluete, Fahrgassen gruen (gedaempft: 0.92/0.80/0.18 stand als Neon-Zitrone da)
			frucht = vec3(0.86, 0.76, 0.24) * hell;
			float fg = feld_linie(x - 0.9, 24.0, 0.45, fwx) + feld_linie(x + 0.9, 24.0, 0.45, fwx);
			frucht = mix(frucht, vec3(0.42, 0.52, 0.16), fg * 0.9);
			frucht *= 1.0 + (wind - 1.0) * 0.8;
			hoch = true;
		} else if (f.frucht == 4) {
			// MAIS: dunkles Gruen in Reihen
			frucht = vec3(0.18, 0.40, 0.19) * hell;
			frucht = mix(frucht, vec3(0.10, 0.24, 0.12), 0.35 * feld_welle(x, 0.75, fwx));
			hoch = true;
		} else if (f.frucht == 5) {
			// JUNGE SAAT: dichte gruene Reihen, dazwischen etwas Erde (mit halb Erde stand sie oliv
			// da, und nah flimmerten rot-gruene Streifen)
			float r = feld_linie(x, 0.9, 0.62, fwx);
			frucht = mix(vec3(0.42, 0.40, 0.26), vec3(0.37, 0.53, 0.24), 0.45 + 0.55 * r) * hell;
		} else if (f.frucht == 6) {
			// GEPFLUEGT: Furchen
			frucht = vec3(0.47, 0.35, 0.25) * hell * (0.86 + 0.28 * feld_welle(x, 1.3, fwx));
		} else if (f.frucht == 7) {
			// STOPPEL mit Schwaden
			frucht = vec3(0.82, 0.73, 0.48) * hell;
			frucht = mix(frucht, vec3(0.69, 0.57, 0.32), feld_linie(x, 7.0, 1.6, fwx) * 0.9);
		} else if (f.frucht == 8) {
			// MAEHWIESE: helle und dunkle Bahnen
			frucht = wiese * mix(0.92, 1.08, feld_linie(x, 12.0, 6.0, fwx));
		} else if (f.frucht == 9) {
			// KARTOFFELN: dunkles Laub auf den Daemmen, schmale Furchen (mit halb Erde stand das
			// Feld als Khaki da)
			frucht = mix(vec3(0.30, 0.30, 0.20), vec3(0.24, 0.42, 0.19),
				0.3 + 0.7 * feld_linie(x, 0.75, 0.52, fwx)) * hell;
		} else if (f.frucht == 10) {
			// SONNENBLUMEN: Gelb mit dunklen Koepfen
			frucht = vec3(0.93, 0.71, 0.13) * hell;
			vec2 q = (fract(vec2(x, y) / 0.7) - 0.5) * 0.7;
			float kopf = 1.0 - smoothstep(0.10 - fwx, 0.10 + fwx, length(q));
			kopf = mix(0.064, kopf, clamp(1.5 - fwx / 0.2, 0.0, 1.0));
			frucht = mix(frucht, vec3(0.34, 0.22, 0.08), kopf);
			hoch = true;
		}
	}
	vec3 col = mix(wiese, frucht, akt);
	float dkante = 1.0e6;
	if (f.kante_nah) {
		dkante = min(min(f.d.x - feld_halb(f.art.x), f.d.y - feld_halb(f.art.y)),
			min(f.d.z - feld_halb(f.art.z), f.d.w - feld_halb(f.art.w)));
		// Stehende Frucht wirft einen schmalen Saum auf den Rain.
		if (hoch) {
			col *= mix(1.0, mix(0.84, 1.0, smoothstep(0.0, 1.2, dkante)), akt);
		}
		col = feld_kante(col, wiese, f.art.x, f.d.x, fwx, akt);
		col = feld_kante(col, wiese, f.art.y, f.d.y, fwx, akt);
		col = feld_kante(col, wiese, f.art.z, f.d.z, fwy, akt);
		col = feld_kante(col, wiese, f.art.w, f.d.w, fwy, akt);
	}
	// Heckensaum an der Flurblock-Grenze
	col = mix(col, FELD_HECKE_BODEN, (1.0 - smoothstep(3.0, 6.0, fd.y)) * 0.5);
	acker = akt * (1.0 - smoothstep(-0.5, 0.0, -dkante));
	return col;
}
