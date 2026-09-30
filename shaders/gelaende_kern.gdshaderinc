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

#ifdef FERN
uniform float senke_nah;
uniform float senke_fern;
uniform float senke_tief;
uniform float senke_bias;
uniform float bias_aus_a;
uniform float bias_aus_b;
#else
// GLUT AUS DEM ALPHAKANAL (Lavarinnen am Vulkan) — siehe TerrainWorld.setup. Die Schuerze
// hat keinen: dort traegt COLOR.a die Grundabsenkung.
const float GLUT = 2.2;
#endif

#include "res://shaders/palette.gdshaderinc"

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = mat3(MODEL_MATRIX) * NORMAL;
#ifdef FERN
	float d = distance(w_pos.xz, CAMERA_POSITION_WORLD.xz);
	// COLOR.a traegt, wie viel Grundabsenkung diese Stelle BRAUCHT (siehe Main._fern_kachel):
	// im Gebirge die volle, an flachen Kuesten fast keine.
	float s = senke_tief * (1.0 - smoothstep(senke_nah, senke_fern, d))
		+ senke_bias * COLOR.a * (1.0 - smoothstep(bias_aus_a, bias_aus_b, d));
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
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
#ifndef FERN
	EMISSION = srgb_linear(roh) * (1.0 - COLOR.a) * GLUT;
#endif
}

void light() {
	DIFFUSE_LIGHT += weiches_licht(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
}
