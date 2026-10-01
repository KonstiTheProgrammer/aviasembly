// PALETTE UND LICHT DES STILS ZELDA/GHIBLI — geteilt von Gelaende (gelaende_kern) und Gras
// (gras.gdshader), damit die Halme an ihrem Fuss exakt die Farbe des Bodens haben.
// Farben in sRGB; ALBEDO bekommt srgb_linear(...).

// STIL "SATT & KLAR" (2026-10-01, Nutzer: Berge "richtig milchig", Boden-Stil "ned so gut"
// — gewaehlt: glatte Farbflaechen ohne Texturen, aber dunkler, satter, kontrastreicher).
// Vorher (Zelda/Ghibli) war die Rampe bewusst gedeckt und hell: zusammen mit dem breiten
// weichen Licht und viel Dunst stand die Landschaft als Pastell da. Jetzt tiefe, satte
// Gruentoene (Farbton 150 -> 110 -> 88 Grad, Saettigung 0.6) — die Helligkeit kommt aus
// dem Licht (klares_licht), nicht aus der Farbe. Erster Anlauf mit Saettigung 0.7 stand
// ohne Dunst als Neonrasen da (im Bild 0.78-0.85).
const vec3 GRAS_TIEF = vec3(0.08, 0.23, 0.15);
const vec3 GRAS_MITTE = vec3(0.20, 0.39, 0.16);
const vec3 GRAS_HELL = vec3(0.40, 0.53, 0.22);
// Fels: kuehles Granitgrau -> helles warmes Grau. Nur der Farbton; die Helligkeit legt
// gelaende_kern fest (siehe dort). Erster Anlauf mit Graubraun (0.62/0.55/0.46)
// gab Schokoladenberge.
const vec3 FELS_TIEF = vec3(0.34, 0.36, 0.40);
const vec3 FELS_HELL = vec3(0.58, 0.57, 0.55);
const vec3 SCHNEE_C = vec3(0.93, 0.96, 1.00);
// HIMMELSFUELLUNG des Bodens (in klares_licht): mit dem klaren Licht bekamen von der Sonne
// abgewandte Flanken und Schlagschatten nur noch Umgebungslicht und standen schwarz da
// (unterstes Zehntel 3/255) — Godots ACES drueckt alles unter ~0.02 linear fast auf null
// (0.01 -> 9/255). Eine pauschale Emission (0.12) brachte 9/255 und haette, stark genug,
// auch die Sonnenseiten um ein Drittel aufgehellt; eine nach der Flaechenrichtung
// gerichtete (15/255) erreichte die Schlagschatten der Grate nicht. Jetzt im Licht: wo die
// Sonne NICHT ankommt (abgewandt oder im Schatten), fuellt kuehles Himmelslicht auf —
// dunkel, aber lesbar. Die Sonne erkennt das Licht an der Richtung (globale
// Shader-Variable sonne_dir, TerrainWorld.setze_sonne). Einheit wie Godots Licht
// (Energie x PI): flacher besonnter Boden bekommt ~0.97.
global uniform vec3 sonne_dir;
const vec3 HIMMEL_FUELL = vec3(0.36, 0.43, 0.55);

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
// Nur noch fuer Haeuser (haus.gdshader) — der Boden nutzt klares_licht.
vec3 weiches_licht(vec3 n, vec3 l, vec3 farbe, float att) {
	float w = smoothstep(-0.18, 0.72, dot(n, l));
	return farbe * att * w * (0.92 / PI);
}

// KLARES LICHT fuer alles, was den Boden bildet (Gelaende, Gras, Strassen — dieselbe
// Funktion, sonst laege eine Strasse am Hang anders im Licht als die Wiese daneben).
// Nahe an Lambert mit kurzem Uebergang: flacher Boden bekommt bei 26 Grad Sonnenhoehe
// 0.57, der Sonne zugewandte Haenge 1.08, abgewandte nichts. Das weiche Licht gab 0.71
// gegen 0.92 — Verhaeltnis 1.3, also kaum Relief; jetzt 1.9: jeder Hang hat eine Licht-
// und eine Schattenseite. l_welt = mat3(INV_VIEW_MATRIX) * LIGHT.
vec3 klares_licht(vec3 n, vec3 l, vec3 farbe, float att, vec3 l_welt) {
	float w = smoothstep(-0.06, 0.90, dot(n, l)) * 1.08;
	vec3 licht = farbe * att * w * (1.0 / PI);
	float sonne = step(0.995, dot(normalize(l_welt), sonne_dir));
	return licht + sonne * HIMMEL_FUELL * (1.0 - smoothstep(0.0, 0.45, att * w));
}
