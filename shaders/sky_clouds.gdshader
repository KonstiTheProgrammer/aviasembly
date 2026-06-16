// Aviassembly-Himmel: satter Blau-Verlauf + Sonnenscheibe/-glow + fluffige
// prozedurale Kumuluswolken (fbm). Wolken auf eine virtuelle Ebene projiziert,
// sonnenseitig aufgehellt, mit dunklerer Unterseite -> Volumen-Eindruck.
shader_type sky;

uniform vec3 col_zenith  : source_color = vec3(0.10, 0.38, 0.80);
uniform vec3 col_mid     : source_color = vec3(0.42, 0.66, 0.93);
uniform vec3 col_horizon : source_color = vec3(0.85, 0.93, 0.99);
uniform vec3 sun_tint    : source_color = vec3(1.0, 0.96, 0.86);
uniform vec3 cloud_lit   : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 cloud_dark  : source_color = vec3(0.62, 0.69, 0.80);
uniform vec3 sun_dir = vec3(0.55, 0.62, 0.55);   // Richtung ZUR Sonne (von Main gesetzt)
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.46;
uniform float cloud_soft  : hint_range(0.01, 0.5) = 0.20;
uniform float cloud_scale = 2.2;
uniform float cloud_speed = 0.006;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.95;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i), b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0, amp = 0.5;
	for (int k = 0; k < 5; k++) { s += amp * vnoise(p); p = p * 2.03 + 7.1; amp *= 0.5; }
	return s;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	float up = clamp(dir.y, -1.0, 1.0);

	// --- Himmel-Verlauf (Horizont hell -> Mitte -> Zenit satt) ---
	vec3 sky_col = mix(col_horizon, col_mid, smoothstep(0.0, 0.32, up));
	sky_col = mix(sky_col, col_zenith, smoothstep(0.28, 0.9, up));

	// --- Sonne: Scheibe + weicher Glow ---
	float sdot = max(dot(dir, sd), 0.0);
	sky_col += sun_tint * pow(sdot, 4500.0) * 12.0;     // Scheibe
	sky_col += sun_tint * pow(sdot, 8.0) * 0.30;        // Glow

	// --- Wolken (nur über dem Horizont) ---
	if (dir.y > 0.015) {
		vec2 uv = (dir.xz / dir.y) * cloud_scale;
		uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.55);
		float n = fbm(uv);
		// zweite Oktave fürs Aufbrechen der Ränder
		n = n * 0.78 + fbm(uv * 2.7 + 4.0) * 0.22;
		float dens = smoothstep(cloud_cover, cloud_cover + cloud_soft, n);
		// zur Horizont-Linie ausblenden (Projektion wird dort extrem gestreckt)
		dens *= smoothstep(0.015, 0.18, dir.y);
		// Beleuchtung: dichtere Kerne dunkler unten, sonnenseitig heller
		float lit = mix(0.55, 1.0, smoothstep(0.35, 0.95, n)) ;
		lit += pow(sdot, 3.0) * 0.5;
		vec3 ccol = mix(cloud_dark, cloud_lit, clamp(lit, 0.0, 1.0));
		sky_col = mix(sky_col, ccol, dens * cloud_opacity);
	}

	COLOR = sky_col;
}
