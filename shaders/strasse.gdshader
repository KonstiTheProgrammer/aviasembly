// LANDSTRASSEN — Fahrbahnband (scripts/Strassen.gd). UV.x = Abstand von der Achse in METERN
// (+ links), UV.y = Laufmeter, UV2.x = halbe Fahrbahnbreite. Jenseits davon liegt das Bankett.
// Stil Zelda/Ghibli wie das Gelaende (palette.gdshaderinc): klare Flaechen, weiches Licht.
//   Landstrasse: warmgrauer Asphalt mit Flickstellen, abgefahrenen Spuren und rauem Rand,
//                weisse Randlinien, gestrichelte Mittellinie, Schotterbankett.
//   Nebenstrasse (nur zwischen Doerfern): heller Schotterweg mit zwei Fahrspuren, Grasnarbe.
// Linien und Muster blenden ueber fwidth in ihr Mittel, sobald sie schmaler als ein Bildpunkt
// werden — sonst flimmern sie aus der Hoehe als Morsezeichen.
shader_type spatial;

#include "res://shaders/palette.gdshaderinc"

uniform bool neben = false;

// Derselbe Asphalt wie die Landstrassen-Art in shaders/stadtstrasse.gdshader: an der Zufahrt
// eines Orts geht das eine Band ins andere ueber.
const vec3 ASPHALT = vec3(0.35, 0.35, 0.37);
const vec3 FLICKEN = vec3(0.27, 0.27, 0.29);
const vec3 LINIE = vec3(0.90, 0.89, 0.84);
const vec3 SCHOTTER = vec3(0.58, 0.53, 0.43);   // dunkler als reife Felder (0.66 verschwand darauf)
const vec3 SPUR = vec3(0.47, 0.42, 0.34);
const vec3 BANKETT = vec3(0.52, 0.49, 0.42);

float hash1(float n) {
	uint h = uint(int(n) + 1000000) * 2654435761u;
	h ^= h >> 15u;
	h *= 2246822519u;
	h ^= h >> 13u;
	return float(h >> 8u) * (1.0 / 16777216.0);
}

// Weicher Streifen der halben Breite b (m) um m, geglaettet; wird er schmaler als ein Bildpunkt,
// blendet er aus (eine einzelne Linie, kein Muster).
float streifen(float q, float m, float b) {
	float fw = max(fwidth(q), 1e-4);
	float sichtbar = clamp(b / fw - 0.3, 0.0, 1.0);
	return (1.0 - smoothstep(b - fw, b + fw, abs(q - m))) * sichtbar;
}

void fragment() {
	float q = UV.x;
	float v = UV.y;
	float hw = UV2.x;
	float aq = abs(q);
	float fwv = max(fwidth(v), 1e-4);
	vec3 c;
	if (neben) {
		c = SCHOTTER;
		float spur = max(streifen(q, hw * 0.45, 0.30), streifen(q, -hw * 0.45, 0.30));
		c = mix(c, SPUR, spur * 0.8);
		// Grasnarbe in der Mitte und am Rand, Rand geht ins Gras ueber
		float narbe = streifen(q, 0.0, 0.22);
		c = mix(c, GRAS_MITTE, narbe * 0.55);
		c = mix(c, GRAS_MITTE * 1.05, smoothstep(hw - 0.4, hw + 0.4, aq) * 0.85);
	} else {
		c = ASPHALT;
		// Ton laengs: lange, weiche Wellen (alter und neuer Belag)
		float abschnitt = floor(v / 37.0);
		float ton = mix(hash1(abschnitt), hash1(abschnitt + 1.0), smoothstep(0.0, 1.0, fract(v / 37.0)));
		c *= 0.93 + 0.12 * ton * clamp(1.5 - fwv / 6.0, 0.0, 1.0);
		// Flickstellen: dunklere Rechtecke auf einer Spur (jedes vierte 23-m-Stueck)
		float fz = floor(v / 23.0);
		float fh = hash1(fz * 7.0 + 3.0);
		if (fh < 0.25) {
			float v0 = fract(v / 23.0);
			float seite = hash1(fz * 7.0 + 5.0) < 0.5 ? -1.0 : 1.0;
			float laenge = 0.25 + 0.4 * hash1(fz * 7.0 + 6.0);
			float in_v = step(0.2, v0) * step(v0, 0.2 + laenge);
			float in_q = 1.0 - smoothstep(1.1, 1.3, abs(q - seite * hw * 0.5));
			c = mix(c, FLICKEN, in_v * in_q * 0.75 * clamp(1.5 - fwv / 3.0, 0.0, 1.0));
		}
		// Abgefahrene Spuren (je Fahrstreifen zwei) etwas heller, Rand rau und dunkler
		float spuren = streifen(aq, hw * 0.28, 0.35) + streifen(aq, hw * 0.72, 0.35);
		c *= 1.0 + 0.05 * spuren;
		c *= 1.0 - 0.10 * smoothstep(hw - 0.5, hw, aq);
		// Randlinien 0,12 m breit, 0,3 m vom Rand; Mittellinie gestrichelt (6 m Strich, 6 m Luecke)
		float rand = streifen(aq, hw - 0.36, 0.06);
		float strich = step(0.5, fract(v / 12.0));
		strich = mix(0.5, strich, clamp(1.5 - fwv / 4.0, 0.0, 1.0));
		float mitte = streifen(q, 0.0, 0.06) * strich;
		c = mix(c, LINIE, max(rand, mitte));
		// Bankett: Schotter, aussen etwas dunkler und erdiger (mit Gruen stand eine hellgruene Linie
		// neben der Wiese — deren Ton haengt am Gelaende-Shader und passt nie genau)
		float bank = smoothstep(hw - 0.02, hw + 0.02, aq);
		vec3 sch = mix(BANKETT, BANKETT * vec3(0.82, 0.84, 0.74), smoothstep(hw + 0.4, hw + 1.0, aq));
		c = mix(c, sch, bank);
	}
	ALBEDO = srgb_linear(c);
}

void light() {
	DIFFUSE_LIGHT += klares_licht(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, mat3(INV_VIEW_MATRIX) * LIGHT);
}
