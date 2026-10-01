// GELAENDE: Chunks (gelaende.gdshader), Fernschuerze (gelaende_fern.gdshader, FERN),
// Felsboegen (Landmarks).
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

// FERNGRAS — die Wiese JENSEITS der echten Halme (Rechnung und Begruendung in fragment()).
uniform float ferngras = 1.0;         // 0 = aus (Messung/Vergleich)
// x = Radius, bis zu dem echte Halme um die Kamera stehen (m), y = wie voll (0..1; faellt
// mit der Hoehe ueber Grund, 0 = keine Halme). Setzt TerrainWorld._gras_nachfuehren.
global uniform vec2 gras_halme;
const float GRAS_UNTEN = -4.8;        // = TerrainWorld.SEA_Y + 1.2: darunter waechst nichts
const float FG_OBEN = 0.70;           // wie weit die Lichtnormale im Bueschel nach oben kippt
// Deckung der Wiese durch Bueschel bei Dichte 1: von oben gesehen (Grundflaeche, gemessen
// von tools/_gras_textur.gd) und je Kotangens des Blickwinkels (Seitenflaeche: flach
// angeschaut verdecken stehende Bueschel den Boden dahinter).
const float FG_DECK_OBEN = 0.047;
const float FG_DECK_SEITE = 0.12;
#ifndef FERN
// Bueschelkarte (tools/_gras_textur.gd): R Hoehe, G Gipfelhoehe, B Ton, A Rang.
uniform sampler2D gras_fern_tex : filter_linear_mipmap, repeat_enable;
const float FG_KACHEL = 48.0;         // = KACHEL in tools/_gras_textur.gd (m)
const float FG_HOEHE = 2.2;           // = H_MAX dort (m)
const float FG_TEXEL = 1024.0;        // = N dort
// Schnitthoehen (x FG_HOEHE). Sechs: mit vier fielen die Schnitte eines Bueschels schon bei
// 25 Grad Blickwinkel sichtbar auseinander. Gemessen (tools/_gelaende_zeit.gd, 4K MSAA 4x,
// beide Staffeln): im Mittel 0,06 ms, hoechstens 0,12 ms ueber offener Wiese.
const float FG_SCHICHT[6] = float[6](0.05, 0.12, 0.19, 0.27, 0.36, 0.46);
// ZWEITE STAFFEL: wo die Bueschel der ersten unter ~2 Bildpunkte fallen, uebernimmt dieselbe
// Karte FG_GROB-fach vergroessert — ein Fleck steht dann fuer eine Gruppe von Bueschel
// (wie die Fernfassung der Baeume fuer einen Baum). Dahinter bleibt die mittlere Farbe.
const float FG_GROB = 3.0;
#endif

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
// EINE STAFFEL BUESCHEL: sechs Schnitte der Karte, von unten nach oben uebereinandergelegt.
// uv = Bodenpunkt in Kacheln, weg = Versatz je Hoehe (wo der Sehstrahl ueber dem Boden
// laeuft), px = Texel je Bildpunkt. Rueckgabe: x Deckung, y Lage am Halm, z Ton.
vec3 fg_staffel(vec2 uv, vec2 weg, float px, float dichte) {
	float kante = 0.02 + 0.03 * px;
	float lod = log2(max(px, 1.0));
	vec3 e = vec3(0.0, 0.40, 0.5);
	for (int i = 0; i < 6; i++) {
		float h = FG_SCHICHT[i];
		vec4 s = textureLod(gras_fern_tex, uv + weg * h, lod);
		float a = smoothstep(h - kante, h + kante, s.r)
			* smoothstep(s.a - 0.04, s.a + 0.04, dichte);
		e = mix(e, vec3(1.0, 0.12 + 0.55 * clamp(h / max(s.g, 0.05), 0.0, 1.0), s.b), a);
	}
	return e;
}
#endif

varying vec3 w_pos;
varying vec3 w_nrm;
#ifdef FERN
// Die Schuerze kennt die Sperrflaechen nicht (Flugplaetze): aus ihrer Entfernung egal.
#define W_FREI 1.0
#else
// UV2.y = darf hier Gras wachsen (TerrainWorld._gras_frei: 0 auf Flugplatz, Ort, Halde).
// Netze ohne UV2 (Felsboegen) haben 0 — dort waechst auch keines.
varying float w_frei;
#define W_FREI w_frei
#endif

void vertex() {
#ifndef FERN
	float morph = smoothstep(0.0, 1.0, clamp((welt_zeit - erschienen) / MORPH_S, 0.0, 1.0));
	if (morph < 1.0) {
		VERTEX.y = mix(UV2.x, VERTEX.y, morph);
	}
	w_frei = UV2.y;
#endif
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = mat3(MODEL_MATRIX) * NORMAL;
#ifdef FERN
	float d = distance(w_pos.xz, CAMERA_POSITION_WORLD.xz);
	// COLOR.a traegt, wie viel Grundabsenkung diese Stelle BRAUCHT (siehe Main._fern_kachel):
	// im Gebirge die volle, an flachen Kuesten fast keine.
	float s = (senke_tief * (1.0 - smoothstep(senke_nah, senke_fern, d))
		+ senke_bias * COLOR.a * (1.0 - smoothstep(bias_aus_a, bias_aus_b, d)))
		* chunk_da(w_pos.xz);
	// COLOR.a == 0 markiert den Grundriss des Kavernenflugplatzes: dort wird die Absenkung
	// GEDECKELT, damit keine Zelle in der Halle landet (Main._fern_kachel).
	if (COLOR.a < 0.05 && w_pos.y > 220.0) {
		s = min(s, w_pos.y - 220.0);
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

	// --- FERNGRAS: die Wiese sieht aus der Ferne aus wie aus der Naehe ---------------------
	// Echte Grasbueschel stehen nur bis gras_halme.x um die Kamera (TerrainWorld.GRAS_FERN_R).
	// Dahinter lag der nackte Boden: glatt, ohne das satte Gruen der Halme und nach der
	// HANGNORMALE beleuchtet statt wie die Halme nach oben — die Wiese wechselte 100 m vor
	// dem Flugzeug sichtbar ihr Aussehen. Hier malt der Boden die Bueschel selbst, ohne ein
	// einziges Dreieck:
	//   * DIESELBEN BUESCHEL: Dichte nach der Regel der Grasmaske (TerrainWorld._gras_block:
	//     gruen, flach, frei), Abstand und Groesse wie der aeussere Halmring, Farbe Fuss ->
	//     Spitze wie in gras.gdshader.
	//   * STEHEND: die Bueschelkarte wird in sechs Hoehen geschnitten, jeder Schnitt dort
	//     abgetastet, wo der Sehstrahl in dieser Hoehe ueber dem Boden laeuft. Die Bueschel
	//     verdecken den Boden hinter sich und wandern beim Vorbeiflug gegen ihn wie echte.
	//   * WEITER WEG uebernimmt eine zweite, groebere Staffel (FG_GROB), und IN DER FERNE
	//     (oder wenn der Blick so flach ist, dass die Schnitte auseinanderfielen) bleibt die
	//     MITTLERE Farbe: Deckung aus Dichte und Blickwinkel. Kein Flimmern, kein Rauschkorn.
	//   * LICHT: wo Bueschel stehen, kippt die Normale nach oben, wie die Halme sie tragen.
	vec3 n_licht = n;
	float neig = sqrt(max(1.0 - n.y * n.y, 0.0)) / max(n.y, 0.05);
	float dichte = gruen * (1.0 - smoothstep(0.42, 0.75, neig)) * W_FREI
		* step(GRAS_UNTEN, w_pos.y);
#ifdef FERN
	// Die Schuerze traegt den Wald als FARBE (Main._fern_farbe): dort stehen Kronen, kein Gras.
	dichte *= smoothstep(0.24, 0.36, lum);
#endif
	float halme = gras_halme.y * (1.0 - smoothstep(gras_halme.x * 0.72, gras_halme.x,
		distance(w_pos.xz, CAMERA_POSITION_WORLD.xz)));
	float fg_an = (1.0 - halme) * ferngras;
#ifndef FERN
	// Ableitungen AUSSERHALB der Verzweigung (innen sind sie nicht definiert).
	vec2 fg_uv = w_pos.xz * (1.0 / FG_KACHEL);
	vec2 fg_dx = dFdx(fg_uv);
	vec2 fg_dy = dFdy(fg_uv);
#endif
	if (dichte * fg_an > 0.004) {
		vec3 v = (CAMERA_POSITION_WORLD - w_pos) / max(d, 0.001);
		float vn = clamp(dot(v, n), 0.08, 1.0);
		float kot = sqrt(1.0 - vn * vn) / vn;
		float deck = 1.0 - exp(-dichte * (FG_DECK_OBEN + FG_DECK_SEITE * kot));
		// Lage am Halm (0 Fuss .. 1 Spitze). Im Mittel UNTER der Mitte: ein Halm ist am Fuss
		// breit und laeuft spitz zu, die helle Spitze ist der kleinste Teil seiner Flaeche.
		float h_rel = 0.40;
		float ton = 0.5;
#ifndef FERN
		// SCHAERFE NACH DER SCHMALEN SEITE DES BILDPUNKTS. Flach angeschaut ist der Abdruck
		// eines Bildpunkts am Boden lang und schmal; nach der langen Seite gefiltert
		// verschwammen die Bueschel zu flachen Scheiben, gross wie Seerosenblaetter. Die
		// Flaeche des Abdrucks (Kreuzprodukt, dreht mit der Querlage nicht) und der
		// Blickwinkel geben beide Seiten; gefiltert wird hoechstens 4:1 gestreckt.
		float flaeche = abs(fg_dx.x * fg_dy.y - fg_dx.y * fg_dy.x);
		float px = max(sqrt(flaeche * vn), sqrt(flaeche / vn) * 0.25) * FG_TEXEL;
		float flach_aus = 1.0 - smoothstep(2.5, 6.0, kot);
		float m1 = (1.0 - smoothstep(3.0, 7.0, px)) * flach_aus;
		float m2 = smoothstep(3.0, 7.0, px) * (1.0 - smoothstep(3.0, 7.0, px / FG_GROB))
			* flach_aus;
		if (m1 + m2 > 0.01) {
			vec2 weg = v.xz * (FG_HOEHE / (vn * FG_KACHEL));
			vec3 st = vec3(0.0, 0.40, 0.5);
			if (m1 > 0.01) {
				st += (fg_staffel(fg_uv, weg, px, dichte) - vec3(0.0, 0.40, 0.5)) * m1;
			}
			if (m2 > 0.01) {
				st += (fg_staffel(fg_uv * (1.0 / FG_GROB) + vec2(0.37, 0.71), weg,
					px / FG_GROB, dichte) - vec3(0.0, 0.40, 0.5)) * m2;
			}
			float m = m1 + m2;
			deck = deck * (1.0 - m) + st.x;
			h_rel = st.y;
			ton = st.z;
		}
#endif
		vec3 halm = mix(gras, GRAS_SPITZE, (GRAS_SPITZE_MIN + GRAS_SPITZE_STREU * ton) * h_rel)
			* (0.92 + 0.16 * ton);
		float fg = deck * fg_an;
		c = mix(c, halm, fg);
		n_licht = normalize(mix(n, vec3(0.0, 1.0, 0.0), fg * FG_OBEN));
	}

	// --- Fels: Farbton aus der Rampe, Helligkeit bleibt ----------------------------------
	// NUR DER TON wird vereinheitlicht (dunkel = kuehles Blaugrau, hell = warmer Kalk). Die
	// Helligkeit bleibt die der Rohfarbe — sonst hoebe die Rampe den schwarzen Basalt am
	// Vulkan auf Mittelgrau. Dazu an steilen Flanken weiche, grosse Baenke.
	float fels = (1.0 - gruen) * (1.0 - schnee) * smoothstep(0.30, 0.70, steil);
	if (fels > 0.01) {
		vec2 wand = abs(n.x) > abs(n.z) ? w_pos.zy : w_pos.xy;
		// Weicher Kanal (G), nicht das Korn (R) — sonst stand wieder Rauschen auf der Wand.
		float bank = texture(boden_tex, vec2(wand.x * (1.0 / 420.0), wand.y * (1.0 / 90.0))).g - 0.5;
		float hell = lum * (1.0 + bank * 0.45 * k * (1.0 - smoothstep(1500.0, 5000.0, d)));
		vec3 ton = mix(FELS_TIEF, FELS_HELL, smoothstep(0.20, 0.75, lum) + verlauf * 0.25);
		vec3 stein = ton * (hell / max(dot(ton, vec3(0.2126, 0.7152, 0.0722)), 0.001));
		c = mix(c, stein, fels * 0.8);
	}

	// --- Schnee blauweiss -------------------------------------------------------------------
	c = mix(c, SCHNEE_C, schnee * 0.7);

	ALBEDO = srgb_linear(clamp(c, vec3(0.0), vec3(1.0)));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_licht, 0.0)).xyz);
#ifndef FERN
	EMISSION = srgb_linear(roh) * (1.0 - COLOR.a) * GLUT;
#endif
}

void light() {
	DIFFUSE_LIGHT += weiches_licht(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
}
