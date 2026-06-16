// Aviassembly-Wasser: tropischer Tiefen-Verlauf (türkise Untiefen -> tiefes Blau)
// über den Szenen-Tiefenpuffer, Schaumkante am Ufer, Fresnel-Himmelsspiegelung
// und ein sanftes Glitzern. Material ist transparent (Untiefen schimmern durch).
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform vec3 shallow_col : source_color = vec3(0.32, 0.86, 0.84);   // knalliges Türkis
uniform vec3 mid_col     : source_color = vec3(0.10, 0.56, 0.74);   // mittleres Lagunen-Blau
uniform vec3 deep_col    : source_color = vec3(0.02, 0.22, 0.46);   // tiefes Blau
uniform vec3 foam_col    : source_color = vec3(0.94, 0.99, 1.0);
uniform float depth_fade = 34.0;     // Tiefe (m), über die shallow -> deep blendet
uniform float foam_band  = 2.4;      // Schaum bei sehr geringer Wassertiefe
uniform float wave_amp   = 0.010;
uniform float wave_scale = 6.0;
uniform float wave_speed = 0.35;

float hash(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){ vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	float a=hash(i),b=hash(i+vec2(1,0)),c=hash(i+vec2(0,1)),d=hash(i+vec2(1,1));
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y); }

void fragment() {
	// --- Wassertiefe aus dem Tiefenpuffer ---
	float dz = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, dz);
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vpos.xyz /= vpos.w;
	float scene_d = -vpos.z;            // Entfernung Kamera -> Grund unter dem Wasser
	float surf_d  = -VERTEX.z;          // Entfernung Kamera -> Wasseroberfläche
	float water_col = max(scene_d - surf_d, 0.0);

	// --- Farbe: türkise Untiefen -> Lagunen-Blau -> tiefes Blau (zweistufig) ---
	float t = smoothstep(0.0, depth_fade, water_col);
	vec3 col = mix(shallow_col, mid_col, smoothstep(0.0, 0.45, t));
	col = mix(col, deep_col, smoothstep(0.45, 1.0, t));

	// --- Schaumkante am Ufer (ganz geringe Tiefe) ---
	float foam = 1.0 - smoothstep(0.0, foam_band, water_col);
	col = mix(col, foam_col, foam * 0.7);

	// --- sanfte Wellen-Normale (Glitzern) ---
	vec2 wuv = UV * wave_scale + TIME * wave_speed * vec2(0.6, 0.4);
	float n1 = vnoise(wuv);
	float n2 = vnoise(wuv * 1.9 - TIME * wave_speed * 0.5);
	NORMAL_MAP = vec3(0.5 + (n1 - 0.5) * wave_amp * 30.0,
	                  0.5 + (n2 - 0.5) * wave_amp * 30.0, 1.0);
	NORMAL_MAP_DEPTH = 0.6;

	ALBEDO = col;
	METALLIC = 0.25;
	ROUGHNESS = 0.06 + 0.05 * t;          // offenes Wasser etwas matter
	SPECULAR = 0.7;
	// Untiefen schimmern durch (transparenter), tiefes/Schaum-Wasser deckt
	ALPHA = clamp(mix(0.72, 0.98, t) + foam * 0.3, 0.0, 1.0);
}
