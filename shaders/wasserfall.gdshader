shader_type spatial;
// WASSERFALL-VORHANG (scripts/Flussleben.gd, je Absturz ein Band ueber dem Wasserband).
// Weiss mit tuerkisen Bahnen, die nach unten laufen, die Raender wellig und durchsichtig —
// das undurchsichtige Wasserband darunter (wasser_kern, COLOR.a) ist schmaler und dunkler
// und scheint an den Raendern durch. So liest sich ein Fall als fallendes Wasser und nicht
// als weisse Platte mit geraden Kanten.
// UV  = (quer in m, m ab der Lippe entlang des Bandes)
// UV2 = (halbe Breite dieser Zeile in m, Laenge des Falls in m)
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D wellen_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 weiss : source_color = vec3(0.90, 0.94, 0.96);
uniform vec3 wasser : source_color = vec3(0.36, 0.70, 0.72);
uniform float tempo = 9.0;

void fragment() {
	float q = UV.x / max(UV2.x, 0.01);
	float y = UV.y;
	float l = UV2.y;
	float t = TIME;
	// Bahnen: weiche Wellenhoehe (B), quer ~2 m, laengs gestreckt, fallend
	// (Die Wellentextur hat ZEHN Wellen je Kachel: UV / 24 heisst Bahnen von ~2,4 m.)
	float s1 = texture(wellen_tex, vec2(UV.x / 24.0, (y - t * tempo) / 80.0)).b;
	float s2 = texture(wellen_tex, vec2(UV.x / 8.0 + 0.31, (y - t * tempo * 1.35) / 30.0)).b;
	float bahn = smoothstep(-0.02, 0.30, s1) * 0.70 + smoothstep(0.02, 0.32, s2) * 0.30;
	// feine helle Faeden (Zellnetz, laengs gestreckt)
	float faden = texture(wellen_tex, vec2(UV.x / 5.0 + 0.13, (y - t * tempo * 1.2) / 30.0)).a;
	vec3 col = mix(weiss, wasser, bahn * 0.78);
	col = mix(col, weiss * 1.05, faden * 0.45);
	// Lippe: die ersten Meter glasig und tuerkis, mit einem Glanzstreif
	float lippe = 1.0 - smoothstep(0.0, 1.8, y);
	col = mix(col, wasser * 1.05, lippe * 0.45);
	col += vec3(0.20) * smoothstep(0.2, 0.7, y) * (1.0 - smoothstep(0.7, 1.3, y));
	// Fuss: Weiss, wo es aufschlaegt
	col = mix(col, weiss * 1.06, smoothstep(l - 5.0, l, y) * 0.8);
	// WELLIGE RAENDER: der Rand wandert mit dem fallenden Wasser
	float rw = texture(wellen_tex, vec2((y - t * tempo) / 14.0, 0.27 + sign(q) * 0.21)).b;
	float rand = 0.80 + 0.14 * rw;
	float deck = 1.0 - smoothstep(rand - 0.18, rand + 0.04, abs(q));
	deck *= mix(0.70, 1.0, smoothstep(0.0, 1.2, y));
	deck *= 1.0 - bahn * 0.35;
	ALBEDO = col;
	ALPHA = clamp(deck, 0.0, 1.0) * 0.96;
	ROUGHNESS = 0.45;
	SPECULAR = 0.35;
	// Schattenseite nicht schwarz: etwas kuehles Eigenlicht
	EMISSION = col * vec3(0.20, 0.24, 0.30);
}
