// Aviassembly-Himmel: WEICH & DUNSTIG. Gedämpfter Blau-Verlauf zu milchig-pastell
// am Horizont, weiche Sonne mit warmem Halo, GROSSE soft-gemalte Kumuluswolken.
shader_type sky;

uniform vec3 col_zenith  : source_color = vec3(0.40, 0.55, 0.72);   // gedämpftes Stahlblau
uniform vec3 col_mid     : source_color = vec3(0.60, 0.70, 0.80);
uniform vec3 col_horizon : source_color = vec3(0.84, 0.84, 0.85);   // milchig-pastell (Dunst)
uniform vec3 sun_col     : source_color = vec3(1.0, 0.97, 0.90);
uniform vec3 sun_halo    : source_color = vec3(1.0, 0.86, 0.66);    // warmer Halo
uniform vec3 cloud_lit   : source_color = vec3(0.97, 0.97, 0.98);
uniform vec3 cloud_dark  : source_color = vec3(0.74, 0.77, 0.83);
uniform vec3 sun_dir = vec3(0.55, 0.62, 0.55);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.38;
uniform float cloud_soft  : hint_range(0.05, 0.6) = 0.34;   // weiche, breite Ränder
uniform float cloud_scale = 1.05;                            // GROSSE Wolken (niedrige Frequenz)
uniform float cloud_speed = 0.003;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.96;

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
	// nur 3 Oktaven + weiche Gewichtung -> große, blobbige, weiche Wolken
	float s = 0.0, amp = 0.6;
	for (int k = 0; k < 3; k++) { s += amp * vnoise(p); p = p * 2.0 + 5.3; amp *= 0.45; }
	return s;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	float up = clamp(dir.y, -1.0, 1.0);

	// --- gedämpfter Himmel-Verlauf, viel pastell am Horizont (Dunst) ---
	vec3 sky_col = mix(col_horizon, col_mid, smoothstep(-0.02, 0.40, up));
	sky_col = mix(sky_col, col_zenith, smoothstep(0.30, 0.95, up));

	// --- weiche Sonne: Scheibe + großer warmer Halo ---
	float sdot = max(dot(dir, sd), 0.0);
	sky_col += sun_col  * pow(sdot, 1800.0) * 8.0;     // weiche Scheibe
	sky_col += sun_halo * pow(sdot, 5.0) * 0.45;       // breiter warmer Halo

	// --- GROSSE weiche Wolken ---
	if (dir.y > 0.01) {
		// weiche Projektion (dir.y + Offset) -> weniger Horizont-Stauchung, Wolken
		// verteilen sich auch höher am Himmel statt nur als dünner Streifen.
		vec2 uv = (dir.xz / (dir.y + 0.22)) * cloud_scale;
		uv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.5);
		float n = fbm(uv);
		float dens = smoothstep(cloud_cover, cloud_cover + cloud_soft, n);
		dens *= smoothstep(0.01, 0.10, dir.y);          // nur ganz unten weich ausblenden
		// flache, weiche Beleuchtung (low contrast, gemalt)
		float lit = mix(0.7, 1.0, smoothstep(0.4, 0.9, n)) + pow(sdot, 4.0) * 0.3;
		vec3 ccol = mix(cloud_dark, cloud_lit, clamp(lit, 0.0, 1.0));
		// Wolken selbst leicht vom Dunst überzogen (verschmelzen mit dem Himmel)
		sky_col = mix(sky_col, ccol, dens * cloud_opacity);
	}

	COLOR = sky_col;
}
