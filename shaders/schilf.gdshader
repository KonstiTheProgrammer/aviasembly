shader_type spatial;
// SCHILF am Flussufer (scripts/Flussleben.gd). Wiegt im Wind wie die Graswiesen
// (gras.gdshader): Boeen laufen als Welle durch, dazu ein Zittern je Halm; die Auslenkung
// waechst mit dem Quadrat der Hoehe (UV.y = 0 am Fuss .. 1 an der Spitze). Die Normale ist
// zur Haelfte nach oben gezogen — sonst stuende die Rueckseite jedes Halms dunkel da.
render_mode cull_disabled;

#include "res://shaders/palette.gdshaderinc"

uniform vec2 wind_richtung = vec2(0.80, 0.60);

varying vec3 farbe;

void vertex() {
	vec3 wo = MODEL_MATRIX[3].xyz;
	float h = UV.y;
	float boe = 0.5 + 0.5 * sin(TIME * 0.9 - dot(wo.xz, wind_richtung) * 0.07);
	float zittern = sin(TIME * 2.3 + dot(wo.xz, vec2(0.37, 0.21)) + VERTEX.x * 4.0 + VERTEX.z * 3.0) * 0.5 + 0.5;
	vec2 aus = wind_richtung * (0.05 + 0.20 * boe + 0.07 * zittern) * h * h;
	mat3 m = mat3(MODEL_MATRIX);
	VERTEX += transpose(m) * vec3(aus.x, -0.05 * boe * h * h, aus.y) / max(dot(m[0], m[0]), 1e-4);
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.55));
	farbe = COLOR.rgb * (0.86 + 0.28 * INSTANCE_CUSTOM.r);
}

void fragment() {
	ALBEDO = farbe;
	// Rueckseite (cull_disabled): dieselbe Normale wie vorn, sonst dunkle Halme.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	EMISSION = ALBEDO * vec3(0.60, 0.72, 0.95) * 0.12;
}

void light() {
	DIFFUSE_LIGHT += klares_licht(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION, mat3(INV_VIEW_MATRIX) * LIGHT);
}
