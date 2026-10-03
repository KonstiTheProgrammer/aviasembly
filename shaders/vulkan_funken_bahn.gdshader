// FUNKENREGEN AM VULKAN — Bahn (GPUParticles3D, Main._vulkan_glut): gluehende Brocken schiessen aus
// dem Schlot (Kegel um die Senkrechte), werden von Schwerkraft und Luft gebremst und fallen im Bogen
// zurueck; Farbe von Gelbweiss ueber Orange nach Dunkelrot, dann aus.
// EIGENER SHADER statt ParticleProcessMaterial: dessen Shader blieb hier beim Beenden stehen
// ("1 shaders of type ParticlesShaderRD were never freed", auch headless als DummyShader-Leck).
shader_type particles;

uniform float schlot_r = 40.0;          // Radius des Auswurfs (m)
uniform float tempo_min = 55.0;
uniform float tempo_max = 135.0;
uniform float streu = 0.58;             // halber Oeffnungswinkel (rad): Brocken fliegen bis ueber den Kraterrand
uniform vec3 schwere = vec3(6.0, -26.0, -1.0);
uniform float groesse_min = 3.5;
uniform float groesse_max = 11.0;

float zufall(uint n) {
	n = (n ^ 61u) ^ (n >> 16u);
	n *= 9u;
	n = n ^ (n >> 4u);
	n *= 668265261u;
	n = n ^ (n >> 15u);
	return float(n & 0xFFFFFFu) / 16777216.0;
}

void start() {
	uint s = NUMBER * 7919u + INDEX * 104729u + RANDOM_SEED;
	float r1 = zufall(s);
	float r2 = zufall(s + 1u);
	float r3 = zufall(s + 2u);
	float r4 = zufall(s + 3u);
	float r5 = zufall(s + 4u);
	float gr = mix(groesse_min, groesse_max, r5 * r5);
	if (RESTART_POSITION) {
		float a = r1 * 6.2831853;
		float rr = sqrt(r2) * schlot_r;
		TRANSFORM = mat4(vec4(gr, 0.0, 0.0, 0.0), vec4(0.0, gr, 0.0, 0.0), vec4(0.0, 0.0, gr, 0.0),
			vec4(cos(a) * rr, 0.0, sin(a) * rr, 1.0));
	}
	if (RESTART_VELOCITY) {
		float w = r3 * 6.2831853;
		float k = streu * sqrt(r4);
		VELOCITY = vec3(sin(k) * cos(w), cos(k), sin(k) * sin(w)) * mix(tempo_min, tempo_max, r1 * 0.5 + r5 * 0.5);
	}
	if (RESTART_CUSTOM) {
		CUSTOM = vec4(0.0, 0.6 + 1.9 * r2, 0.0, 0.0);      // x = Alter 0..1, y = Bremse
	}
	if (RESTART_COLOR) {
		COLOR = vec4(1.0, 0.85, 0.45, 1.0);
	}
}

void process() {
	VELOCITY += schwere * DELTA;
	VELOCITY *= max(1.0 - CUSTOM.y * 0.12 * DELTA, 0.0);
	CUSTOM.x = min(CUSTOM.x + DELTA / LIFETIME, 1.0);
	float t = CUSTOM.x;
	vec3 c = mix(vec3(1.0, 0.85, 0.45), vec3(1.0, 0.45, 0.08), smoothstep(0.0, 0.25, t));
	c = mix(c, vec3(0.75, 0.10, 0.02), smoothstep(0.25, 0.6, t));
	c = mix(c, vec3(0.25, 0.02, 0.0), smoothstep(0.6, 1.0, t));
	COLOR = vec4(c, 1.0 - smoothstep(0.55, 1.0, t));
}
