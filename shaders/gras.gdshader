// GRASWIESEN — Zeichnen (siehe gras_bahn.gdshader fuer die Platzierung).
// Stil Zelda/Ghibli: der Halm hat am Fuss EXAKT die Farbe des Bodens darunter (dieselbe
// Rampe wie im Gelaende-Shader, Lage aus der Grasmaske) und wird zur Spitze heller und
// waermer. Die Normale zeigt senkrecht nach oben — die Halme werden wie der Boden
// beleuchtet und gehen dadurch nahtlos in ihn ueber, statt als dunkle Stoppeln davorzustehen.
// COLOR.r im Netz = Hoehe am Halm (0 Fuss .. 1 Spitze).
shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/palette.gdshaderinc"

uniform sampler2D boden_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 wind_richtung = vec2(0.80, 0.60);

varying vec3 farbe;

void vertex() {
	vec3 wo = MODEL_MATRIX[3].xyz;
	float h = COLOR.r;
	// WIND: langsame Boeen laufen als Wellen ueber die Wiese, darunter ein kleines Zittern.
	float boe = 0.5 + 0.5 * sin(TIME * 0.9 - dot(wo.xz, wind_richtung) * 0.07);
	float zittern = sin(TIME * 2.6 + dot(wo.xz, vec2(0.37, 0.21))) * 0.5 + 0.5;
	vec2 aus = wind_richtung * (0.10 + 0.32 * boe + 0.08 * zittern) * h * h;
	mat3 m = mat3(MODEL_MATRIX);
	VERTEX += transpose(m) * vec3(aus.x, -0.12 * boe * h * h, aus.y) / max(dot(m[0], m[0]), 1e-4);
	NORMAL = vec3(0.0, 1.0, 0.0);

	float t = gras_lage(INSTANCE_CUSTOM.x, VERLAUF(boden_tex, wo.xz), wo.y);
	vec3 fuss = rampe(GRAS_TIEF, GRAS_MITTE, GRAS_HELL, t);
	vec3 spitze = mix(fuss, GRAS_HELL * vec3(1.08, 1.08, 0.94), 0.30 + 0.25 * INSTANCE_CUSTOM.y);
	farbe = srgb_linear(mix(fuss, spitze, h)) * (0.92 + 0.16 * INSTANCE_CUSTOM.z);
}

void fragment() {
	ALBEDO = farbe;
	// Auch die RUECKSEITE des Halms (cull_disabled) zeigt nach oben — Godot kehrt die
	// Normale dort sonst um, und die halbe Wiese stuende dunkel da.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void light() {
	DIFFUSE_LIGHT += klares_licht(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, mat3(INV_VIEW_MATRIX) * LIGHT);
}
