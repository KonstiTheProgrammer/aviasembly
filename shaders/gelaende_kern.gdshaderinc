// GELAENDE: Chunks (gelaende.gdshader) und Fernschuerze (gelaende_fern.gdshader, FERN).
//
// VOM LOW-POLY-LOOK ZUM GELAENDE. Vorher: ein Dreieck = eine Farbe, flach schattiert — aus
// der Naehe glatte Farbplatten, aus der Hoehe ein Mosaik aus 8-m-Facetten, das jeden Hang
// wie gefaltetes Papier aussehen liess. Jetzt traegt das Netz glatte Normalen und Farben
// je Eckpunkt (TerrainWorld._make_chunk_data, Main._fern_kachel), und dieser Shader legt
// das dazu, was ein 8-m-Raster nicht kann:
//   * GROSSVARIATION (immer, auch Schuerze): zwei weiche Fleckenlagen, ~1,9 km und ~470 m
//     je Kachel, hellen/dunkeln und verschieben den Ton — Wiesen werden stellenweise
//     trockener, Waldboden dunkler. Aus der Hoehe bricht das die gleichmaessigen Flaechen.
//   * KORN + RELIEF (nah, bis ~1,4 km): zwei Kornlagen (38 m, 9 m) in Farbe und Normale.
//   * FELSBAENKE an steilen Flanken: das Korn laeuft dort gestreckt waagerecht (Schichtung),
//     auf der Ebene projiziert, die der Wand am naechsten liegt.
// Alles aus EINER Textur (boden_detail.res, tools/_boden_textur.gd), R = Korn, G = Flecken,
// BA = Ableitung des Korns. Die Textur ist gemipmapt: das Korn verschwindet in der Ferne
// von selbst, ein harter Schnitt an der Ausblendgrenze entsteht nicht.
//
// MATERIAL AUS DER FARBE. Der Shader kennt kein Biom — er liest aus der Vertexfarbe, wie
// "gruen" (Bewuchs) oder "weiss" (Schnee/Eis) die Stelle ist, und dosiert danach: Schnee
// bekommt kaum Korn, Bewuchs die Tonverschiebung ins Trockene, Fels die Baenke.


uniform sampler2D boden_tex : filter_linear_mipmap, repeat_enable;
uniform float detail_staerke = 1.0;   // 0 = aus (Messung/Vergleich)

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

vec3 srgb_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void fragment() {
	vec3 roh = COLOR.rgb;
	vec3 c = srgb_linear(roh);
	vec3 n = normalize(w_nrm);
	float d = distance(w_pos, CAMERA_POSITION_WORLD);
	float k = detail_staerke;

	// --- Material aus der Farbe (sRGB) -----------------------------------------------------
	float mx = max(roh.r, max(roh.g, roh.b));
	float mn = min(roh.r, min(roh.g, roh.b));
	float gruen = clamp((roh.g - max(roh.r, roh.b)) * 7.0, 0.0, 1.0);
	float schnee = smoothstep(0.70, 0.86, mn);
	float steil = 1.0 - smoothstep(0.58, 0.86, n.y);

	// Bewuchs etwas entsaettigt: die Palette war fuer flache Facetten gemacht und wirkt auf
	// glattem Gelaende mit Licht und Korn giftig-lindgruen.
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(lum), c, 1.0 - 0.26 * gruen * k) * (1.0 - 0.07 * gruen * k);

	// --- Grossvariation --------------------------------------------------------------------
	float f1 = texture(boden_tex, w_pos.xz * (1.0 / 1900.0)).g;
	float f2 = texture(boden_tex, w_pos.xz * (1.0 / 470.0) + vec2(0.37, 0.61)).g;
	float fleck = (f1 - 0.5) * 1.1 + (f2 - 0.5) * 0.7;          // etwa -0.6..0.6
	float grob = k * (1.0 - 0.75 * schnee);
	c *= 1.0 + fleck * 0.30 * grob;
	// Bewuchs: trockene Flecken gelblicher, feuchte satter/blaeulicher
	vec3 trocken = c * vec3(1.10, 1.03, 0.80);
	vec3 satt = c * vec3(0.84, 0.97, 0.94);
	c = mix(c, fleck > 0.0 ? trocken : satt, clamp(abs(fleck) * 1.4, 0.0, 1.0) * gruen * 0.55 * k);

	// --- Korn und Relief (nah) -------------------------------------------------------------
	// Auf der Ebene von oben projiziert (xz); an steilen Flanken wuerde das Korn dabei zu
	// senkrechten Kratzern gestreckt — dort kommt es aus der Wandebene (siehe unten).
	float nah = (1.0 - smoothstep(300.0, 1400.0, d)) * k;
	float flach = smoothstep(0.50, 0.78, n.y);
	vec2 wand = abs(n.x) > abs(n.z) ? w_pos.zy : w_pos.xy;
	vec3 quer = abs(n.x) > abs(n.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	if (nah > 0.001) {
		float nah2 = 1.0 - smoothstep(60.0, 380.0, d);
		float korn = 0.0;
		vec3 kipp = vec3(0.0);
		if (flach > 0.001) {
			vec4 t1 = texture(boden_tex, w_pos.xz * (1.0 / 38.0));
			vec4 t2 = texture(boden_tex, w_pos.xz * (1.0 / 9.0) + vec2(0.5, 0.25));
			korn += ((t1.r - 0.5) * 0.7 + (t2.r - 0.5) * 0.6 * nah2) * flach;
			vec2 g = (t1.ba - 0.5) * 0.55 + (t2.ba - 0.5) * 0.40 * nah2;
			kipp += vec3(-g.x, 0.0, -g.y) * flach;
		}
		if (flach < 0.999) {
			vec4 w1 = texture(boden_tex, wand * (1.0 / 38.0) + vec2(0.21, 0.4));
			vec4 w2 = texture(boden_tex, wand * (1.0 / 9.0) + vec2(0.7, 0.1));
			korn += ((w1.r - 0.5) * 0.7 + (w2.r - 0.5) * 0.6 * nah2) * (1.0 - flach);
			vec2 g = (w1.ba - 0.5) * 0.55 + (w2.ba - 0.5) * 0.40 * nah2;
			kipp -= (quer * g.x + vec3(0.0, 1.0, 0.0) * g.y) * (1.0 - flach);
		}
		float amp = mix(0.34, 0.10, schnee);
		c *= 1.0 + korn * amp * nah;
		n = normalize(n + kipp * mix(0.9, 0.35, schnee) * nah);
	}

	// --- Felsbaenke an steilen Flanken -----------------------------------------------------
	float fels = steil * (1.0 - gruen) * (1.0 - schnee * 0.7) * k;
	if (fels > 0.01) {
		float fern_fels = 1.0 - smoothstep(900.0, 3200.0, d);
		// Projektionsebene "wand": die senkrechte Ebene, die der Wand am naechsten liegt
		// Gestreckt, aber nicht zu stark: bei 12:1 lief das Korn als gebuerstetes Blech ueber
		// die Wand. 3:1 (grosse Baenke) und 2:1 (Fugen) liest sich als geschichteter Kalk.
		vec4 b1 = texture(boden_tex, vec2(wand.x * (1.0 / 96.0), wand.y * (1.0 / 30.0)));
		vec4 b2 = texture(boden_tex, vec2(wand.x * (1.0 / 22.0), wand.y * (1.0 / 11.0)) + 0.3);
		float bank = (b1.r - 0.5) * 1.0 + (b2.r - 0.5) * 0.5 * nah;
		c *= 1.0 + bank * 0.42 * fels * fern_fels;
		// Relief der Baenke: die Kante springt nach aussen, in der Wand liegt die Fuge
		vec2 bg = (b1.ba - 0.5) * 0.9 + (b2.ba - 0.5) * 0.5 * nah;
		n = normalize(n - (quer * bg.x + vec3(0.0, 1.0, 0.0) * bg.y) * 0.8 * fels * fern_fels);
	}

	ALBEDO = clamp(c, vec3(0.0), vec3(1.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = mix(0.95, 0.55, schnee);
	SPECULAR = mix(0.12, 0.35, schnee);
#ifndef FERN
	EMISSION = ALBEDO * (1.0 - COLOR.a) * GLUT;
#endif
}
