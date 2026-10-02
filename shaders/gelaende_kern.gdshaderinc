// GELAENDE: Chunks (gelaende.gdshader), Fernschuerze (gelaende_fern.gdshader, FERN),
// Felsboegen (Landmarks).
//
// STAND 2026-10-01: "SATT & KLAR" (Nutzer: Berge "richtig milchig", Boden-Stil "ned so
// gut"). Glatte Farbflaechen wie unten beschrieben, aber tiefe satte Palette, dunkler Fels,
// klares Licht nahe Lambert (klares_licht) und Dunst erst zum Horizont (Main.NEBEL_ANFANG).
// Was unten ueber WEICHES LICHT und viel LUFT steht, ist die Vorgeschichte.
//
// LOOK: MODERN-STILISIERT (Richtung Zelda BotW / Ghibli), Wunsch des Nutzers. Die erste
// glatte Fassung legte Rauschkorn, Relief und Fleckenmuster ueber das Gelaende — das wirkte
// "billig und alt" (Flugsimulator von 2005). Dieser Stil erzaehlt Form nicht ueber
// Texturrauschen, sondern ueber drei Dinge:
//   * EINE BEGRENZTE PALETTE: alles Gruen laeuft ueber EINE Rampe (sattes Blaugruen im
//     Wald und in Senken -> Wiesengruen -> sonniges Gelbgruen), Fels ueber eine warm-graue
//     Rampe, Schnee blauweiss. Wo die Stelle auf der Rampe liegt, bestimmt die Helligkeit
//     der Rohfarbe aus _face_color (Waldboden dunkel, trockene Wiese hell) plus sehr grosse,
//     weiche Verlaeufe (km-Massstab) — keine Flecken im 100-m-Massstab.
//   * WEICHES, BREITES LICHT (light()): der Uebergang von Sonne zu Schatten ist weit und
//     gemalt (smoothstep statt Lambert), sonnige Flanken stehen flaechig hell, die
//     Schattenseite traegt das kuehle Himmelslicht — warm gegen kalt statt hell gegen dunkel.
//   * LUFT: die Tiefe macht der Dunst (Main: Nebel mit Himmelsfarbe und Sonnenstreuung).
// An steilen Felswaenden liegen weiche, grosse Baenke (Schichtung) — nur eine Lage, kein Korn.

uniform sampler2D boden_tex : filter_linear_mipmap, repeat_enable;
uniform float detail_staerke = 1.0;   // 0 = Verlaeufe/Baenke aus (Messung/Vergleich)

#ifdef FERN
uniform float senke_nah;
uniform float senke_fern;
uniform float senke_tief;
uniform float senke_bias;
uniform float bias_aus_a;
uniform float bias_aus_b;
// RUECKFALLEBENE: das feine Hoehenraster der Chunks (TerrainWorld._tiefe_tex, ringfoermig
// wie im Wasser-Shader) traegt TIEFE_LEER (20000) ueberall, wo KEIN Chunk steht. Nur wo
// einer steht, taucht die Schuerze ab. Fehlt einer — im Schnellflug kommen die Worker
// nicht hinterher —, bleibt die Schuerze an Ort und Stelle: grobes Gelaende statt eines
// 480 m tiefen Lochs.
uniform sampler2D tiefe_fein : filter_nearest, repeat_disable;
uniform int fein_n = 1152;
uniform bool fein_da = false;

// 1 = hier steht ein Chunk. Vier Proben 6 m um den Eckpunkt: ein Eckpunkt AUF einer
// Chunkgrenze (das 32- und das 64-m-Raster treffen sie genau) gilt nur als abgedeckt,
// wenn beide Seiten stehen — sonst stuende am Rand eine schraege Wand ins Loch.
float chunk_da(vec2 xz) {
	if (!fein_da) {
		return 1.0;
	}
	float n = float(fein_n);
	float m = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 o = vec2((i & 1) == 0 ? -6.0 : 6.0, (i & 2) == 0 ? -6.0 : 6.0);
		ivec2 a = ivec2(mod(floor((xz + o) / 8.0), n));
		m = max(m, texelFetch(tiefe_fein, a, 0).r);
	}
	return step(m, 9000.0);
}
#else
// GLUT AUS DEM ALPHAKANAL (Lavarinnen am Vulkan) — siehe TerrainWorld.setup. Die Schuerze
// hat keinen: dort traegt COLOR.a die Grundabsenkung.
const float GLUT = 2.2;
// WEICHES ERSCHEINEN (TerrainWorld.MORPH_S): ein gestreamter Chunk waechst aus der Hoehe
// der Fernschuerze (UV2.x, siehe _schuerzen_hoehen) in seine Form. Ohne gesetzten
// Zeitpunkt (Startbereich, Felsboegen ohne UV2) sofort voll.
global uniform float welt_zeit;
instance uniform float erschienen = -1000.0;
const float MORPH_S = 1.4;   // = TerrainWorld.MORPH_S
#endif

#include "res://shaders/palette.gdshaderinc"

#ifndef FERN
// --- BODENMATERIALIEN (2026-10-01, Nutzer: "schaut alles so billig aus, rueste es auf";
// gewaehlt: echte Texturen, selbst erzeugt). ZWEITE FASSUNG am selben Tag: die realistischen
// Texturen (Halme, Kiesel, Gesteinsschichten) passten nicht — gewuenscht ist "zelda-maessig"
// (BotW): GEMALTE Pinseltupfen, facettierter Fels, schwaches Relief, groessere Kacheln. ---
// Sechs kachelbare Materialien (tools/build_bodentexturen.py): Farbe als FAKTOR mit Mittel 1
// (die Palette und die Vertexfarben bleiben die Grundfarbe — Karte, Fernschuerze und Nahbereich
// passen weiter zusammen), Hoehe fuer das Ueberblenden, Normale und Hohlkehle fuer das Relief.
// In der Ferne mitteln die Mipmaps alles auf Faktor 1 und flache Normale — die Schuerze (FERN)
// tastet deshalb gar nicht erst ab.
uniform sampler2DArray mat_farbe : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray mat_normale : filter_linear_mipmap, repeat_enable;
uniform bool mat_da = false;

const float MAT_GRAS = 0.0;     // = TerrainWorld.BODEN_MATERIALIEN
const float MAT_WALD = 1.0;
const float MAT_ERDE = 2.0;
const float MAT_SAND = 3.0;
const float MAT_FELS = 4.0;
const float MAT_SCHNEE = 5.0;
// Weltmeter je Kachel (feiner Massstab). Der zweite Massstab ist KACHEL_GROSS-mal so gross
// und gedreht — zwei Kacheln mit irrationalem Verhaeltnis wiederholen sich nicht sichtbar.
const float KACHEL_GRAS = 4.5;
const float KACHEL_WALD = 5.0;
const float KACHEL_ERDE = 5.0;
const float KACHEL_SAND = 10.0;
// Fels 52 m (sieben Baenke, ~7 m im Mittel; der zweite Massstab 244 m). Mit 14 m lagen die
// Facetten der ersten Fassung an 100-m-Waenden wie Schuppenhaut, mit 34 m die Baenke als
// Nadelstreifen.
const float KACHEL_FELS = 52.0;
const float KACHEL_SCHNEE = 12.0;
const float KACHEL_GROSS = 4.7;
const mat2 DREH = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
// Staerke der Normalenstoerung. Im gemalten Zelda-Stil schwach (realistische Fassung: 0.9) —
// die Form erzaehlt das Licht, die Textur nur die Pinselstruktur.
const float RELIEF = 0.40;
// FELSRELIEF (2026-10-02, geschichteter Fels, tools/build_bodentexturen.py fels): das LICHT
// bekommt eine maessige Neigung (RELIEF_FELS) — mehr kippt die Cel-Rampe (klares_licht) jede
// Bankkante ganz in den blauen Schatten (im Versuch mit Facetten: dunkelblaue Flecken an jeder
// Wand). Dazu malt der Shader den Ton aus der Neigung zur Sonne (FACETTE_TON): Simse zur Sonne
// heller und warm, abgewandt dunkler und kuehl — nie schwarz, immer passend zum Sonnenstand.
// FACETTE_GROSS = Anteil des zweiten, grossen Massstabs an der Normale (Baenke von 30-60 m,
// sichtbar bis ~2 km, wo der kleine in den Mipmaps verschwunden ist).
const float RELIEF_FELS = 0.65;
const float FACETTE_TON = 0.55;
const float FACETTE_GROSS = 0.75;
// MOOS AUF SIMSEN: Felsflaechen, die (mit der Neigung der Baenke) nach oben zeigen, tragen
// Gruen wie die Klippen in BotW — die Simse werden zu gruenen Baendern.
// Nur wo auch die GEOMETRIE nicht senkrecht ist: an glatten Waenden lag sonst ein Flicken-
// teppich aus gruenen Flecken (im Versuch mit Facetten: jede fuer sich gruen oder grau).
const float MOOS_AB = 0.74;
const float MOOS_VOLL = 0.92;

// Von oben projiziert, zwei Massstaebe. rgb = Farbfaktor, a = Hoehe; stoer = Welt-
// Stoerung der Normale (x, z), ao = Hohlkehle.
vec4 mat_oben(vec2 xz, float ebene, float kachel, out vec3 stoer, out float ao) {
	vec2 uv1 = xz / kachel;
	vec2 uv2 = DREH * xz / (kachel * KACHEL_GROSS) + vec2(0.37, 0.71);
	vec4 f1 = texture(mat_farbe, vec3(uv1, ebene));
	vec4 f2 = texture(mat_farbe, vec3(uv2, ebene));
	vec4 n1 = texture(mat_normale, vec3(uv1, ebene));
	vec4 n2 = texture(mat_normale, vec3(uv2, ebene));
	// Der zweite Massstab ist gedreht: seine Normale zurueck in Weltrichtung drehen.
	vec2 d = (n1.xy * 2.0 - 1.0) + transpose(DREH) * (n2.xy * 2.0 - 1.0) * 0.7;
	stoer = vec3(d.x, 0.0, d.y);
	ao = n1.z * mix(1.0, n2.z, 0.6);
	return vec4(f1.rgb * 2.0 * mix(vec3(1.0), f2.rgb * 2.0, 0.65), mix(f1.a, f2.a, 0.4));
}

// TRIPLANAR fuer Fels: drei Projektionen nach der Flaechennormale gewichtet, die Zeilen der
// Textur laufen auf den Seitenflaechen mit der Hoehe — die Schichten liegen waagerecht. Die
// alte Felszeichnung kam aus Vertexfarben, die nur von (x, z) abhingen: an jeder Wand liefen
// sie als senkrechte Streifen durch ("gestreckt"). Zweiter, grosser Massstab nur in der Farbe.
vec4 mat_dreifach(vec3 p, vec3 nn, float ebene, float kachel, out vec3 stoer, out float ao) {
	vec3 w = pow(abs(nn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec4 acc = vec4(0.0);
	vec3 s = vec3(0.0);
	float a = 0.0;
	float summe = 0.0;
	float g = 1.0 / (kachel * KACHEL_GROSS);
	// GROSSE BAENKE: der zweite Massstab traegt seit der geschichteten Fassung des Felses
	// auch die NORMALE (vorher nur die Farbe) — aus 300 m bis 2 km sind die kleinen Baenke in
	// den Mipmaps verschwunden, dort gliedern die grossen (244 m Kachel) die Wand.
	if (w.x > 0.03) {
		vec2 uv = vec2(p.z, -p.y) / kachel;
		vec2 uv2 = vec2(p.z, -p.y) * g + vec2(0.31, 0.17);
		vec4 f = texture(mat_farbe, vec3(uv, ebene));
		vec4 f2 = texture(mat_farbe, vec3(uv2, ebene));
		vec4 m = texture(mat_normale, vec3(uv, ebene));
		vec4 m2 = texture(mat_normale, vec3(uv2, ebene));
		vec2 dd = (m.xy * 2.0 - 1.0) + (m2.xy * 2.0 - 1.0) * FACETTE_GROSS;
		s += w.x * vec3(0.0, -dd.y, dd.x);
		a += w.x * m.z * mix(1.0, m2.z, 0.5);
		acc += w.x * vec4(f.rgb * 2.0 * mix(vec3(1.0), f2.rgb * 2.0, 0.6), mix(f.a, f2.a, 0.35));
		summe += w.x;
	}
	if (w.y > 0.03) {
		vec2 uv = p.xz / kachel;
		vec2 uv2 = DREH * p.xz * g + vec2(0.53, 0.29);
		vec4 f = texture(mat_farbe, vec3(uv, ebene));
		vec4 f2 = texture(mat_farbe, vec3(uv2, ebene));
		vec4 m = texture(mat_normale, vec3(uv, ebene));
		vec4 m2 = texture(mat_normale, vec3(uv2, ebene));
		vec2 dd = (m.xy * 2.0 - 1.0) + transpose(DREH) * (m2.xy * 2.0 - 1.0) * FACETTE_GROSS;
		s += w.y * vec3(dd.x, 0.0, dd.y);
		a += w.y * m.z * mix(1.0, m2.z, 0.5);
		acc += w.y * vec4(f.rgb * 2.0 * mix(vec3(1.0), f2.rgb * 2.0, 0.6), mix(f.a, f2.a, 0.35));
		summe += w.y;
	}
	if (w.z > 0.03) {
		vec2 uv = vec2(p.x, -p.y) / kachel;
		vec2 uv2 = vec2(p.x, -p.y) * g + vec2(0.71, 0.43);
		vec4 f = texture(mat_farbe, vec3(uv, ebene));
		vec4 f2 = texture(mat_farbe, vec3(uv2, ebene));
		vec4 m = texture(mat_normale, vec3(uv, ebene));
		vec4 m2 = texture(mat_normale, vec3(uv2, ebene));
		vec2 dd = (m.xy * 2.0 - 1.0) + (m2.xy * 2.0 - 1.0) * FACETTE_GROSS;
		s += w.z * vec3(dd.x, -dd.y, 0.0);
		a += w.z * m.z * mix(1.0, m2.z, 0.5);
		acc += w.z * vec4(f.rgb * 2.0 * mix(vec3(1.0), f2.rgb * 2.0, 0.6), mix(f.a, f2.a, 0.35));
		summe += w.z;
	}
	stoer = s / summe;
	ao = a / summe;
	return acc / summe;
}
#endif

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
#ifndef FERN
	float morph = smoothstep(0.0, 1.0, clamp((welt_zeit - erschienen) / MORPH_S, 0.0, 1.0));
	if (morph < 1.0) {
		VERTEX.y = mix(UV2.x, VERTEX.y, morph);
	}
#endif
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = mat3(MODEL_MATRIX) * NORMAL;
#ifdef FERN
	float d = distance(w_pos.xz, CAMERA_POSITION_WORLD.xz);
	// COLOR.a traegt, wie viel Grundabsenkung diese Stelle BRAUCHT (siehe Main._fern_kachel):
	// im Gebirge die volle, an flachen Kuesten fast keine.
	float nah = 1.0 - smoothstep(senke_nah, senke_fern, d);
	float s = senke_tief * nah
		+ senke_bias * COLOR.a * (1.0 - smoothstep(bias_aus_a, bias_aus_b, d));
	// COLOR.a == 0 markiert den Grundriss des Kavernenflugplatzes (Main._fern_farbe). Dort
	// geht die Schuerze in der Naehe GANZ unter den Berg, unabhaengig von ihrer Hoehe.
	// FRUEHER: Zellen ueber 220 m parkten auf 220, die darunter sanken voll — und das
	// Dreieck zwischen einer geparkten und einer versenkten Ecke lief von 220 m steil auf
	// rund -300 m hinunter und kreuzte dabei die Halle. Am Talschluss steigt der Hang
	// gleich hinter dem Portal durch die 220 m, also stand dort eine graue Wand quer im
	// Stollen: vom Vorfeld sah man nicht in den Berg, von innen nicht hinaus. Ueber der
	// Roehre liegen die echten Chunks (bis VIEW_DIST 3,8 km), die Schuerze hat dort in der
	// Naehe nichts zu tun; in der Ferne (nah = 0) traegt sie wie ueberall die Silhouette.
	if (COLOR.a < 0.05) {
		s = (senke_tief + 2500.0) * nah;
	} else {
		s *= chunk_da(w_pos.xz);
	}
	VERTEX.y -= s;
	w_pos.y -= s;
#endif
}

void fragment() {
	vec3 roh = COLOR.rgb;
	vec3 n = normalize(w_nrm);
	float d = distance(w_pos, CAMERA_POSITION_WORLD);
	float k = detail_staerke;

	// --- Material aus der Rohfarbe (sRGB) --------------------------------------------------
	float mn = min(roh.r, min(roh.g, roh.b));
	float lum = dot(roh, vec3(0.2126, 0.7152, 0.0722));
	float gruen = clamp((roh.g - max(roh.r, roh.b)) * 7.0, 0.0, 1.0);
	float schnee = smoothstep(0.70, 0.86, mn);
	float steil = 1.0 - smoothstep(0.58, 0.86, n.y);

	// Sehr grosse, weiche Verlaeufe (5 km / 1,3 km) — Landschaftsmassstab, keine Flecken.
	float verlauf = VERLAUF(boden_tex, w_pos.xz) * k;

	vec3 c = roh;
	// --- Gruen auf die Rampe (gras_lage: palette.gdshaderinc, auch das Gras nutzt sie) ------
	vec3 gras = rampe(GRAS_TIEF, GRAS_MITTE, GRAS_HELL, gras_lage(lum, verlauf, w_pos.y));
	c = mix(c, gras, gruen * 0.88);
	c = mix(c, c * WIESEN_FLECKEN(boden_tex, w_pos.xz) * WIESEN_WIND(boden_tex, w_pos.xz), gruen * k);
#ifndef FERN
	// BODENBUCKEL (Kachel 34 m, Relief aus dem B/A-Kanal der Bodentextur): die glatten
	// 8-m-Dreiecke lassen Wiesen aus 100-500 m wie Plastik liegen; flache Buckel geben dem
	// Licht etwas zu tun. Nur im Gruenen und nur nah — in der Ferne mitteln die Mipmaps.
	if (gruen > 0.01 && d < 2500.0) {
		vec4 bt = texture(boden_tex, w_pos.xz * (1.0 / 34.0) + vec2(0.21, 0.83));
		n = normalize(n + vec3(bt.b - 0.5, 0.0, bt.a - 0.5) * 0.55 * gruen * k);
	}
#endif

	// --- Fels: Farbton aus der Rampe, Helligkeit dunkel gespreizt ------------------------
	// Der TON wird vereinheitlicht (dunkel = kuehles Granitgrau, hell = helles warmes Grau),
	// die Helligkeit folgt der Rohfarbe, etwas abgedunkelt (siehe unten) — der schwarze
	// Basalt am Vulkan bleibt dabei schwarz. Dazu an steilen Flanken weiche, grosse Baenke.
	float fels = (1.0 - gruen) * (1.0 - schnee) * smoothstep(0.30, 0.70, steil);
	if (fels > 0.01) {
		vec2 wand = abs(n.x) > abs(n.z) ? w_pos.zy : w_pos.xy;
		// Weicher Kanal (G), nicht das Korn (R) — sonst stand wieder Rauschen auf der Wand.
		float bank = texture(boden_tex, vec2(wand.x * (1.0 / 420.0), wand.y * (1.0 / 90.0))).g - 0.5;
		float hell = lum * (1.0 + bank * 0.45 * k * (1.0 - smoothstep(1500.0, 5000.0, d)));
		// SATT & KLAR: 15 % dunkler als die Rohhelligkeit (Basalt 0.10 bleibt schwarz, Grund-
		// fels 0.29, Sonnenseite 0.6). Das Milchige kam nicht von hier, sondern von der HELL-
		// BLAUEN Schattenseite (TerrainWorld._warm_kalt, jetzt dunkel-kuehl), dem breiten
		// weichen Licht und dem Dunst. Eine dunkle Skala (0.10..0.50) gab mit dem klaren Licht
		// schwarze Schattenseiten und Schokoladenberge.
		// MIT TEXTUREN: die Rohhelligkeit an Waenden haengt nur an (x, z) und laeuft deshalb
		// als senkrechte Streifen durch jede Wand; die Struktur liefert jetzt die Felstextur.
		// Zur Haelfte auf ein mittleres Grau gezogen (Basalt unter 0.2 bleibt schwarz, die
		// weissen Kalkwaende werden hellgrau statt weiss).
		// Gilt auch in der Fernschuerze (ohne Texturen), sonst stuende an der Chunkgrenze ein
		// Helligkeitssprung.
		if (hell > 0.2) {
			hell = mix(hell, 0.42, 0.45);
		}
		hell = hell * 0.85 + 0.02;
		vec3 ton = mix(FELS_TIEF, FELS_HELL, smoothstep(0.18, 0.62, hell) + verlauf * 0.25);
		vec3 stein = ton * (hell / max(dot(ton, vec3(0.2126, 0.7152, 0.0722)), 0.001));
		c = mix(c, stein, fels * 0.88);
	}

	// --- Schnee blauweiss -------------------------------------------------------------------
	c = mix(c, SCHNEE_C, schnee * 0.7);

	float hohl = 1.0;
#ifndef FERN
	// --- Bodenmaterialien ------------------------------------------------------------------
	// Erkennung aus der Rohfarbe: dunkles Gruen = Waldboden, Gruen und Stroh = Wiese, warm-hell
	// = Sand, warm-dunkel = Erde/Acker/Weg, Steiles und grauer Grund = Fels, Weiss = Schnee.
	// Was nichts davon ist (Lava, Asche, Sonderfarben), bleibt glatt.
	if (mat_da && d < 4200.0) {
		float mx = max(roh.r, max(roh.g, roh.b));
		float sat = (mx - mn) / max(mx, 0.001);
		float warm = smoothstep(-0.01, 0.04, roh.r - roh.g) * smoothstep(0.02, 0.08, roh.g - roh.b);
		float stroh = smoothstep(-0.10, 0.0, roh.g - roh.r) * smoothstep(0.15, 0.30, roh.g - roh.b)
			* (1.0 - gruen);
		float grau = (1.0 - smoothstep(0.08, 0.20, sat)) * smoothstep(0.08, 0.15, lum)
			* (1.0 - smoothstep(0.62, 0.72, lum)) * (1.0 - gruen);
		float w_schnee = schnee;
		float w_fels = max(fels, grau) * (1.0 - schnee);
		float w_wald = gruen * (1.0 - smoothstep(0.16, 0.30, lum)) * (1.0 - w_fels);
		float w_gras = max(gruen - w_wald, stroh) * (1.0 - w_fels) * (1.0 - schnee);
		float rest_w = (1.0 - w_fels) * (1.0 - schnee) * (1.0 - gruen) * (1.0 - stroh);
		float w_sand = warm * smoothstep(0.52, 0.66, lum) * rest_w;
		float w_erde = warm * (1.0 - smoothstep(0.52, 0.66, lum)) * rest_w;

		vec4 p_gras = vec4(1.0, 1.0, 1.0, 0.5), p_wald = p_gras, p_erde = p_gras,
			p_sand = p_gras, p_fels = p_gras, p_schnee = p_gras;
		vec3 s_gras = vec3(0.0), s_wald = vec3(0.0), s_erde = vec3(0.0), s_sand = vec3(0.0),
			s_fels = vec3(0.0), s_schnee = vec3(0.0);
		float a_gras = 1.0, a_wald = 1.0, a_erde = 1.0, a_sand = 1.0, a_fels = 1.0, a_schnee = 1.0;
		if (w_gras > 0.02) { p_gras = mat_oben(w_pos.xz, MAT_GRAS, KACHEL_GRAS, s_gras, a_gras); }
		if (w_wald > 0.02) { p_wald = mat_oben(w_pos.xz, MAT_WALD, KACHEL_WALD, s_wald, a_wald); }
		if (w_erde > 0.02) { p_erde = mat_oben(w_pos.xz, MAT_ERDE, KACHEL_ERDE, s_erde, a_erde); }
		if (w_sand > 0.02) { p_sand = mat_oben(w_pos.xz, MAT_SAND, KACHEL_SAND, s_sand, a_sand); }
		if (w_schnee > 0.02) { p_schnee = mat_oben(w_pos.xz, MAT_SCHNEE, KACHEL_SCHNEE, s_schnee, a_schnee); }
		if (w_fels > 0.02) {
			// VERBOGENE SCHICHTEN: die Baenke der Felstextur liegen sonst ueberall exakt
			// waagerecht und gleich hoch (Lineal). Ein weicher Versatz der Hoehe (+-26 m auf
			// ~700 m) und ein leichtes Einfallen je Gegend biegen und neigen sie.
			float biege = (texture(boden_tex, w_pos.xz * (1.0 / 1400.0) + vec2(0.61, 0.13)).g - 0.5) * 52.0
				+ (texture(boden_tex, w_pos.xz * (1.0 / 380.0) + vec2(0.27, 0.77)).g - 0.5) * 10.0;
			vec3 p_schicht = vec3(w_pos.x, w_pos.y + biege, w_pos.z);
			p_fels = mat_dreifach(p_schicht, n, MAT_FELS, KACHEL_FELS, s_fels, a_fels);
		}

		// UEBERBLENDEN NACH HOEHE: wo zwei Materialien sich teilen, gewinnt das hoehere —
		// Steine ragen aus der Wiese, Gras waechst in die Ritzen, statt dass beides als
		// Matsch ineinanderlaeuft.
		float h_gras = w_gras + p_gras.a * 0.6, h_wald = w_wald + p_wald.a * 0.6,
			h_erde = w_erde + p_erde.a * 0.6, h_sand = w_sand + p_sand.a * 0.6,
			h_fels = w_fels + p_fels.a * 0.6, h_schnee = w_schnee + p_schnee.a * 0.6;
		float hm = max(max(max(h_gras, h_wald), max(h_erde, h_sand)), max(h_fels, h_schnee)) - 0.3;
		float b_gras = w_gras > 0.02 ? max(h_gras - hm, 0.0) : 0.0;
		float b_wald = w_wald > 0.02 ? max(h_wald - hm, 0.0) : 0.0;
		float b_erde = w_erde > 0.02 ? max(h_erde - hm, 0.0) : 0.0;
		float b_sand = w_sand > 0.02 ? max(h_sand - hm, 0.0) : 0.0;
		float b_fels = w_fels > 0.02 ? max(h_fels - hm, 0.0) : 0.0;
		float b_schnee = w_schnee > 0.02 ? max(h_schnee - hm, 0.0) : 0.0;
		float bsum = b_gras + b_wald + b_erde + b_sand + b_fels + b_schnee;
		// Anteil, der von keinem Material abgedeckt ist (Sonderfarben), bleibt glatt.
		float abdeckung = clamp(w_gras + w_wald + w_erde + w_sand + w_fels + w_schnee, 0.0, 1.0) * k;
		if (bsum > 0.0001) {
			vec3 f = (p_gras.rgb * b_gras + p_wald.rgb * b_wald + p_erde.rgb * b_erde
				+ p_sand.rgb * b_sand + p_fels.rgb * b_fels + p_schnee.rgb * b_schnee) / bsum;
			vec3 st = (s_gras * b_gras + s_wald * b_wald + s_erde * b_erde + s_sand * b_sand
				+ s_fels * b_fels + s_schnee * b_schnee) / bsum;
			float ao = (a_gras * b_gras + a_wald * b_wald + a_erde * b_erde + a_sand * b_sand
				+ a_fels * b_fels + a_schnee * b_schnee) / bsum;
			c *= mix(vec3(1.0), f, abdeckung);
			// Fels mit eigener Relieftiefe (siehe RELIEF_FELS), alles andere wie bisher.
			float anteil_fels = b_fels / bsum;
			float n_geo_y = n.y;
			if (anteil_fels > 0.01) {
				float zur_sonne = dot(s_fels, sonne_dir) * FACETTE_TON;
				float ft = clamp(zur_sonne, -0.40, 0.40) * anteil_fels * abdeckung;
				c *= 1.0 + ft;
				c *= mix(vec3(1.0), ft > 0.0 ? vec3(1.04, 1.01, 0.95) : vec3(0.93, 0.97, 1.06),
					min(abs(ft) * 2.5, 1.0));
			}
			n = normalize(n + st * mix(RELIEF, RELIEF_FELS, anteil_fels) * abdeckung);
			hohl = mix(1.0, ao, 0.45 * abdeckung);
			// MOOS auf nach oben gewandten Simsen (und nur auf Fels; Schnee bleibt Schnee).
			if (anteil_fels > 0.01) {
				// Simse: die Geometrie plus die Neigung der Baenke nach oben
				float moos = smoothstep(MOOS_AB, MOOS_VOLL, n_geo_y + s_fels.y * 0.8)
					* smoothstep(0.30, 0.55, n_geo_y)
					* anteil_fels * abdeckung * (1.0 - schnee) * (0.55 + 0.45 * p_fels.a);
				vec3 moos_c = rampe(GRAS_TIEF, GRAS_MITTE, GRAS_HELL,
					clamp(0.30 + verlauf * 0.6 + (p_fels.a - 0.5) * 0.4, 0.0, 1.0));
				c = mix(c, moos_c, moos * 0.75);
			}
		}
	}
#endif

	ALBEDO = srgb_linear(clamp(c, vec3(0.0), vec3(1.0))) * hohl;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// Matter Boden: Godots Standard (Rauheit 0.5) legte unter flachem Blickwinkel eine
	// Himmelsspiegelung ueber das Gelaende — ein weiterer heller Schleier in der Ferne.
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
#ifndef FERN
	EMISSION = srgb_linear(roh) * (1.0 - COLOR.a) * GLUT;
#endif
}

void light() {
	DIFFUSE_LIGHT += klares_licht(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, mat3(INV_VIEW_MATRIX) * LIGHT);
}
