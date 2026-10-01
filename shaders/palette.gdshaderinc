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
// ZELDA (BotW): das Gruen eine Spur gelber und frischer als "satt & klar" (dort 110 Grad),
// die Tiefe bleibt (sonst wird es pastellig = "milchig").
const vec3 GRAS_TIEF = vec3(0.08, 0.24, 0.17);
const vec3 GRAS_MITTE = vec3(0.20, 0.42, 0.19);
const vec3 GRAS_HELL = vec3(0.36, 0.55, 0.25);
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

// WIESENFLECKEN (2026-10-01, "billig"): aus Flughoehe lag jede Wiese als gleichmaessige
// Flaeche da (Golfplatz) — die Grastextur (2,6-m-Kachel) sieht man erst unter ~30 m. Echte
// Wiesen sind im Bereich 20-250 m fleckig: trockene, hellere und satte, dunklere Stellen.
// Zwei Massstaebe des weichen G-Kanals (Kachel 240 m und 70 m). Gelaende UND Grashalme
// nutzen dasselbe Makro, sonst stuenden die Halme farblich neben ihrem Boden.
#define WIESEN_FLECKEN(tex, xz) mix(vec3(0.86, 0.90, 0.95), vec3(1.10, 1.07, 0.90), clamp((texture(tex, (xz) * (1.0 / 240.0) + vec2(0.13, 0.57)).g - 0.5) * 2.6 + (texture(tex, (xz) * (1.0 / 70.0) + vec2(0.71, 0.29)).g - 0.5) * 1.5 + 0.5, 0.0, 1.0))

// WINDWELLEN UEBER DEN WIESEN (2026-10-01, Zelda-Stil): breite, weiche Lichtbaender laufen mit
// dem Wind ueber das Gras — wie Boeen, die die Halme umlegen und ihre helle Seite zeigen.
// Quer zum Wind lang (620 m), laengs schmal (190 m), 8,5 m/s. Derselbe weiche G-Kanal, ein
// Abruf; Gelaende und Grashalme nutzen dasselbe Makro (sonst liefe die Welle am Halm vorbei).
#define WIESEN_WIND(tex, xz) (1.0 + (texture(tex, vec2(dot(xz, vec2(0.80, 0.60)) * (1.0 / 190.0) - TIME * 0.045, dot(xz, vec2(-0.60, 0.80)) * (1.0 / 620.0))).g - 0.5) * 0.36)

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

// CEL-LICHT IM STIL ZELDA BotW fuer alles, was den Boden bildet (Gelaende, Gras, Strassen —
// dieselbe Funktion, sonst laege eine Strasse am Hang anders im Licht als die Wiese daneben).
// Eine weiche, aber klar erkennbare Licht-/Schattenkante (Terminator ueber ~10 Grad), danach
// eine fast FLACHE Lichtseite mit leichtem Anstieg zur Sonne: flacher Boden 0.80, Sonnenhang
// 1.05, abgewandte Seite 0 + Himmelsfuellung. Vorher (klares_licht, nahe Lambert) lief das
// Licht ueber die ganze Flanke als Verlauf — das ist der realistische, nicht der gemalte Look.
// l_welt = mat3(INV_VIEW_MATRIX) * LIGHT.
vec3 klares_licht(vec3 n, vec3 l, vec3 farbe, float att, vec3 l_welt) {
	float ndl = dot(n, l);
	float w = smoothstep(-0.02, 0.16, ndl) * (0.74 + 0.31 * smoothstep(0.15, 0.95, ndl));
	vec3 licht = farbe * att * w * (1.0 / PI);
	float sonne = step(0.995, dot(normalize(l_welt), sonne_dir));
	return licht + sonne * HIMMEL_FUELL * (1.0 - smoothstep(0.0, 0.45, att * w));
}
