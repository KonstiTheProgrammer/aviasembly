// BRUECKEN DER LANDSTRASSEN (scripts/Strassen.gd, _bruecke): Steinbogenbruecken und Viadukte.
// Farbe aus der Vertexfarbe (sRGB), COLOR.a = Anteil Quadermauerwerk (1 Mauer, 0 glatte Abdeckung).
// Das Mauerwerk kommt aus der Weltlage: Lagen 0,55 m, Quader 1,1 m, jede zweite Lage versetzt,
// Fugen dunkel, Ton je Quader. Projektion nach der Flaechenrichtung (Waende laufen mit der
// Hoehe, Untersichten in x/z). Licht wie das Gelaende (klares_licht, Himmelsfuellung im Schatten).
shader_type spatial;

#include "res://shaders/palette.gdshaderinc"

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = mat3(MODEL_MATRIX) * NORMAL;
}

float quader_hash(vec2 zelle) {
	uvec2 q = uvec2(ivec2(zelle) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 15u)) * 2246822519u;
	h ^= h >> 13u;
	return float(h >> 8u) * (1.0 / 16777216.0);
}

// Fuge der Breite b (m) an Zellgrenzen von x (Zellmass m), geglaettet; in der Ferne ihr Mittel.
float fuge(float x, float m, float b) {
	float fw = max(fwidth(x), 1.0e-4);
	float d = abs(fract(x / m + 0.5) - 0.5) * m;
	float l = 1.0 - smoothstep(b * 0.5 - fw * 0.5, b * 0.5 + fw * 0.5, d);
	return mix(b / m, l, clamp(1.5 - fw / b, 0.0, 1.0));
}

void fragment() {
	vec3 c = COLOR.rgb;
	float mauer = COLOR.a;
	vec3 n = normalize(w_nrm);
	vec2 q;
	if (abs(n.y) > 0.6) {
		q = w_pos.xz;
	} else if (abs(n.x) > abs(n.z)) {
		q = vec2(w_pos.z, w_pos.y);
	} else {
		q = vec2(w_pos.x, w_pos.y);
	}
	const float LAGE = 0.55;
	const float QUADER = 1.1;
	float reihe = floor(q.y / LAGE);
	float x = q.x + 0.5 * QUADER * mod(reihe, 2.0);
	vec2 zelle = vec2(floor(x / QUADER), reihe);
	float ton = 0.92 + 0.14 * quader_hash(zelle);
	float f = max(fuge(q.y, LAGE, 0.07), fuge(x, QUADER, 0.08));
	c *= mix(1.0, ton * mix(1.0, 0.70, f), mauer);
	ALBEDO = srgb_linear(clamp(c, vec3(0.0), vec3(1.0)));
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}

void light() {
	DIFFUSE_LIGHT += klares_licht(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, mat3(INV_VIEW_MATRIX) * LIGHT);
}
