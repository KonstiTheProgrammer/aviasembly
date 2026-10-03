// FUNKENREGEN AM VULKAN — Zeichnen (siehe vulkan_funken_bahn.gdshader): weiche gluehende Punkte,
// zur Kamera gedreht, additiv und weit ueber Weiss (gluehen im Lichtglanz).
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

void vertex() {
	vec3 gr = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * gr.x, INV_VIEW_MATRIX[1] * gr.y,
		INV_VIEW_MATRIX[2] * gr.z, MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	ALBEDO = COLOR.rgb * 5.0;
	ALPHA = smoothstep(1.0, 0.15, r) * COLOR.a;
}
