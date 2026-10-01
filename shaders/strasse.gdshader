// LANDSTRASSEN — Fahrbahnband (scripts/Strassen.gd). UV: u quer (0..1), v = Laufmeter.
// Stil Zelda/Ghibli wie das Gelaende (palette.gdshaderinc): klare Flaechen, weiches Licht.
//   Landstrasse: warmgrauer Asphalt, weisse Randlinien, gestrichelte Mittellinie.
//   Nebenstrasse (nur zwischen Doerfern): heller Schotterweg mit zwei Fahrspuren.
// Linien werden ueber fwidth ausgeblendet, sobald sie schmaler als ein Bildpunkt werden —
// sonst flimmern sie aus der Hoehe als Morsezeichen.
shader_type spatial;

#include "res://shaders/palette.gdshaderinc"

uniform bool neben = false;

// Derselbe Asphalt wie die Landstrassen-Art in shaders/stadtstrasse.gdshader: an der Zufahrt
// eines Orts geht das eine Band ins andere ueber.
const vec3 ASPHALT = vec3(0.35, 0.35, 0.37);
const vec3 LINIE = vec3(0.90, 0.89, 0.84);
const vec3 SCHOTTER = vec3(0.58, 0.53, 0.43);   // dunkler als reife Felder (0.66 verschwand darauf)
const vec3 SPUR = vec3(0.47, 0.42, 0.34);

// Weicher Streifen der halben Breite b um die Mitte m (in u), mit Kantenglaettung.
float streifen(float u, float m, float b) {
	float fw = max(fwidth(u), 1e-4);
	float sichtbar = clamp(b / fw - 0.3, 0.0, 1.0);
	return (1.0 - smoothstep(b - fw, b + fw, abs(u - m))) * sichtbar;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	vec3 c;
	if (neben) {
		c = SCHOTTER;
		float spur = max(streifen(u, 0.28, 0.07), streifen(u, 0.72, 0.07));
		c = mix(c, SPUR, spur * 0.8);
		// Grasnarbe in der Mitte und an den Raendern
		float narbe = max(streifen(u, 0.5, 0.05), max(streifen(u, 0.0, 0.05), streifen(u, 1.0, 0.05)));
		c = mix(c, GRAS_MITTE, narbe * 0.55);
	} else {
		c = ASPHALT;
		float rand = max(streifen(u, 0.06, 0.018), streifen(u, 0.94, 0.018));
		float strich = step(0.45, fract(v / 12.0));
		float mitte = streifen(u, 0.5, 0.016) * strich;
		c = mix(c, LINIE, max(rand, mitte));
		// Bankett: schmaler, hellerer Rand
		c = mix(c, SCHOTTER * 0.9, max(1.0 - smoothstep(0.0, 0.025, u), smoothstep(0.975, 1.0, u)));
	}
	ALBEDO = srgb_linear(c);
}

void light() {
	DIFFUSE_LIGHT += weiches_licht(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
}
