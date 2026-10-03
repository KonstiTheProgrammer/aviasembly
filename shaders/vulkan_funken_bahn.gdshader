// LAVAFONTAENE AM VULKAN — Bahn (GPUParticles3D, Vulkanausbruch._funken_bauen): gluehende Brocken
// schiessen aus dem Schlot (Kegel um die Senkrechte), werden von Schwerkraft und Luft gebremst und
// fallen im Bogen zurueck; Farbe von Gelbweiss ueber Orange nach Dunkelrot, dann aus.
// IN STOESSEN (2026-10-03, „mach noch krasser“): die Zeit ist in Takte von 1,7 s geteilt, je Takt
// wuerfelt der Shader, ob und wie hoch der Schlot spritzt — eine Fontaene, die pumpt, statt eines
// gleichmaessigen Funkenregens. Ein Drittel der Brocken bildet den engen, hohen Strahl, der Rest
// spritzt breit. Beim Ausbruch (globale Shader-Variable vulkan_ausbruch, Sekunden seit dem letzten)
// fliegt alles, schneller und hoeher.
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
uniform float takt = 1.7;
global uniform float vulkan_ausbruch;

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
	float r6 = zufall(s + 5u);
	// STOSS dieses Takts: 0 = Pause, sonst Staerke
	float stoss = zufall(uint(floor(TIME / takt)) * 747796405u + 2891336453u);
	float kraft = smoothstep(0.30, 0.95, stoss);
	float boost = exp(-vulkan_ausbruch / 4.0);
	float aktiv = max(kraft, boost);
	bool strahl = r6 < 0.34;
	float gr = mix(groesse_min, groesse_max, r5 * r5);
	if (RESTART_POSITION) {
		float a = r1 * 6.2831853;
		float rr = sqrt(r2) * schlot_r * (strahl ? 0.4 : 1.0);
		TRANSFORM = mat4(vec4(gr, 0.0, 0.0, 0.0), vec4(0.0, gr, 0.0, 0.0), vec4(0.0, 0.0, gr, 0.0),
			vec4(cos(a) * rr, 0.0, sin(a) * rr, 1.0));
	}
	if (RESTART_VELOCITY) {
		float w = r3 * 6.2831853;
		float k = (strahl ? 0.16 : streu) * sqrt(r4);
		float tempo = mix(tempo_min, tempo_max, r1 * 0.5 + r5 * 0.5) * mix(0.75, 1.25, kraft) * (1.0 + 0.7 * boost);
		if (strahl) {
			tempo *= 1.25;
		}
		VELOCITY = vec3(sin(k) * cos(w), cos(k), sin(k) * sin(w)) * tempo;
	}
	if (RESTART_CUSTOM) {
		// x = Alter 0..1, y = Bremse, z = 1: dieser Brocken fliegt in diesem Takt nicht
		CUSTOM = vec4(0.0, 0.6 + 1.9 * r2, step(aktiv * 0.95 + 0.05, zufall(s + 6u)), 0.0);
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
	COLOR = vec4(c, (1.0 - smoothstep(0.55, 1.0, t)) * (1.0 - CUSTOM.z));
}
