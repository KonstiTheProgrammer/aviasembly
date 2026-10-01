shader_type spatial;
// HAEUSER IM LICHT DER WELT (Stil Zelda/Ghibli). Die Bauten aus world_buildings*.glb trugen
// Godots Standardmaterial: hartes Lambert-Licht, Schattenseiten fast schwarz — neben dem
// gemalten Licht von Gelaende und Baeumen (weiches_licht) standen sie wie aus einem anderen
// Spiel in der Landschaft. CityBuilder tauscht deshalb jedes Material gegen dieses hier.
//
//  * Licht: derselbe weiche Uebergang wie Gelaende und Flora (palette.gdshaderinc).
//  * Farbe: Materialfarbe mal VERTEXFARBE — der gemalte Verlauf aus
//    tools/build_haeuser_blend.py (_verlauf: Waende unten dunkler, Daecher zum First heller).
//  * Schattenseite: kuehle Himmelsfuellung (EMISSION = Albedo x Blauton), kein Schwarz.
//  * FALLE: das Farb-Uniform darf NICHT `farbe` heissen — so heisst ein Parameter von
//    weiches_licht() im Include; mit gleichem Namen kam bei den Haeusern kein Sonnenlicht
//    mehr an (helle Waende fielen nicht auf, Daecher und die Burg standen schwarz da).
//  * Glas und Fenster (geringe Rauheit) spiegeln den Himmel ueber die Umgebung und bekommen
//    ein Sonnen-Glanzlicht; matte Flaechen keines.
#include "res://shaders/palette.gdshaderinc"

uniform vec3 haus_farbe : source_color = vec3(0.8, 0.8, 0.8);
uniform float rauheit : hint_range(0.0, 1.0) = 0.9;
uniform float metall : hint_range(0.0, 1.0) = 0.0;

// HIMMELSFUELLUNG: kuehles Streulicht, das auch die Schattenseite erreicht. Ohne sie standen
// abgewandte Waende und Dachflaechen fast schwarz da (das Umgebungslicht der Welt ist fuer
// senkrechte, dunkle Flaechen zu schwach) — gemalte Schatten sind blau, nicht schwarz.
uniform float fuellung = 0.26;
const vec3 FUELL_TON = vec3(0.60, 0.72, 0.95);

void fragment() {
	ALBEDO = haus_farbe * COLOR.rgb;
	ROUGHNESS = rauheit;
	METALLIC = metall;
	EMISSION = ALBEDO * FUELL_TON * fuellung * (1.0 - metall);
}

void light() {
	DIFFUSE_LIGHT += weiches_licht(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
	float glatt = 1.0 - ROUGHNESS;
	if (glatt > 0.5) {
		float nh = max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * pow(nh, 120.0) * glatt * 1.6;
	}
}
