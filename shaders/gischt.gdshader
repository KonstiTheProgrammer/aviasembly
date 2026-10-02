shader_type spatial;
// GISCHT am Fuss der Wasserfaelle (scripts/Flussleben.gd, GPUParticles3D): weiche weisse
// Wolkenbaellchen, immer zur Kamera gedreht (wie Godots Partikel-Billboard), Deckung aus der
// Farbrampe der Partikel (COLOR.a). Die Sonnenseite etwas heller, die Gegenseite kuehl.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3 hell : source_color = vec3(0.97, 0.98, 1.0);
uniform vec3 kuehl : source_color = vec3(0.78, 0.86, 0.94);
global uniform vec3 sonne_dir;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 q = UV - 0.5;
	float r = length(q) * 2.0;
	// weiches Baellchen: zur Mitte dicht, Rand laeuft aus
	float deck = pow(1.0 - smoothstep(0.0, 1.0, r), 1.6);
	vec3 blick = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	float sonne = clamp(dot(-blick, normalize(sonne_dir)) * 0.5 + 0.5, 0.0, 1.0);
	ALBEDO = mix(kuehl, hell, 0.55 + 0.45 * sonne) * mix(1.0, 0.94, r);
	ALPHA = deck * COLOR.a;
}
