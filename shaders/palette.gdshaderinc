// PALETTE UND LICHT DES STILS ZELDA/GHIBLI — geteilt von Gelaende (gelaende_kern) und Gras
// (gras.gdshader), damit die Halme an ihrem Fuss exakt die Farbe des Bodens haben.
// Farben in sRGB; ALBEDO bekommt srgb_linear(...).

// Bewusst gedeckt: warmes Sonnenlicht (1.7) und die Farbabstimmung legen noch viel drauf —
// mit hellerer Rampe stand die Wiese als grelles Lindgelb da (Spielzeug statt Landschaft).
const vec3 GRAS_TIEF = vec3(0.11, 0.28, 0.21);
const vec3 GRAS_MITTE = vec3(0.28, 0.46, 0.20);
const vec3 GRAS_HELL = vec3(0.50, 0.60, 0.26);
// HALMSPITZE (= GRAS_HELL * (1.08, 1.08, 0.94)). Ein Halm laeuft vom Fuss (Bodenfarbe) um
// GRAS_SPITZE_MIN + GRAS_SPITZE_STREU * Zufall auf diese Farbe zu. Das Ferngras im
// Gelaende-Shader rechnet mit denselben Werten — sonst passt die Wiese jenseits der
// Halme nicht zu der davor.
const vec3 GRAS_SPITZE = vec3(0.54, 0.648, 0.244);
const float GRAS_SPITZE_MIN = 0.30;
const float GRAS_SPITZE_STREU = 0.25;
const vec3 FELS_TIEF = vec3(0.38, 0.41, 0.43);
const vec3 FELS_HELL = vec3(0.80, 0.76, 0.68);
const vec3 SCHNEE_C = vec3(0.93, 0.96, 1.00);

vec3 srgb_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 rampe(vec3 a, vec3 b, vec3 c, float t) {
	return t < 0.5 ? mix(a, b, t * 2.0) : mix(b, c, t * 2.0 - 1.0);
}

// Sehr grosse, weiche Verlaeufe (5 km / 1,3 km) aus dem G-Kanal der Bodentextur.
#define VERLAUF(tex, xz) ((texture(tex, (xz) * (1.0 / 5200.0)).g - 0.5) * 0.8 + (texture(tex, (xz) * (1.0 / 1300.0) + vec2(0.37, 0.61)).g - 0.5) * 0.4)

// Lage auf der Gruen-Rampe: Helligkeit der Rohfarbe (Waldboden dunkel, trockene Wiese
// hell), grosser Verlauf, und Almen etwas heller und trockener als das Tiefland.
float gras_lage(float lum, float verlauf, float hoehe) {
	return clamp(smoothstep(0.20, 0.62, lum) + verlauf * 0.35
		+ smoothstep(300.0, 900.0, hoehe) * 0.12, 0.0, 1.0);
}

// WEICHES LICHT: breiter, gemalter Uebergang statt Lambert. Sonnenflanken stehen flaechig
// hell, der Terminator ist weich und liegt etwas hinter der Kante (Streulicht). Schatten
// (ATTENUATION) bleiben; die Schattenseite fuellt das kuehle Himmelslicht (Umgebung).
vec3 weiches_licht(vec3 n, vec3 l, vec3 farbe, float att) {
	float w = smoothstep(-0.18, 0.72, dot(n, l));
	return farbe * att * w * (0.92 / PI);
}
