// GRASWIESEN — Platzierung (Partikel-Shader). Jede Partikel ist ein Grasbueschel auf einem
// WELTFESTEN Raster um die Kamera: Zelle = floor(kamera / abstand) + Index. Rueckt die
// Kamera eine Zelle weiter, springt das Raster mit, aber jede Weltzelle bekommt immer
// dieselbe Lage, Drehung und Groesse (Hash der Zelle) — nichts schwimmt.
// Hoehe aus dem feinen Hoehenraster des Wassers (TerrainWorld._tiefe_tex, EXAKT die zwei
// Dreiecke je Zelle wie das Gelaendenetz), Dichte und Rampenlage aus der Grasmaske
// (TerrainWorld._gras_tex, R = Dichte, G = Helligkeit der Bodenfarbe). Beide ringfoermig
// adressiert wie in shaders/wasser_kern.gdshaderinc.
// Ausgeblendete Bueschel (keine Wiese, ausserhalb des Kreises, zu hoch) bekommen Groesse 0.
shader_type particles;
render_mode disable_velocity, disable_force;

uniform sampler2D tiefe_fein : filter_nearest, repeat_disable;
uniform sampler2D gras_maske : filter_nearest, repeat_disable;
uniform int fein_n = 1152;
uniform float fein_zelle = 8.0;
uniform vec3 kamera;
uniform float ueber_grund = 0.0;     // Kamerahoehe ueber Grund (von TerrainWorld)
uniform int seite = 150;             // Raster: seite x seite Bueschel
uniform float abstand = 0.7;         // m zwischen zwei Buescheln
uniform float r_innen = 0.0;         // Ring (Fernstufe): innen einblenden ...
uniform float r_aussen = 50.0;       // ... aussen ausblenden
uniform float groesse = 1.0;

float zufall(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float fein_hoehe(vec2 xz, out float gueltig) {
	vec2 g = xz / fein_zelle;
	vec2 i0 = floor(g);
	vec2 f = g - i0;
	float n = float(fein_n);
	ivec2 a = ivec2(mod(i0, n));
	ivec2 b = ivec2(mod(i0 + 1.0, n));
	float h00 = texelFetch(tiefe_fein, a, 0).r;
	float h10 = texelFetch(tiefe_fein, ivec2(b.x, a.y), 0).r;
	float h01 = texelFetch(tiefe_fein, ivec2(a.x, b.y), 0).r;
	float h11 = texelFetch(tiefe_fein, b, 0).r;
	gueltig = step(max(max(h00, h10), max(h01, h11)), 9000.0);
	return f.x > f.y ? h00 + f.x * (h10 - h00) + f.y * (h11 - h10)
	                 : h00 + f.y * (h01 - h00) + f.x * (h11 - h01);
}

// Partikel-Builtins (INDEX, TRANSFORM, CUSTOM) gibt es nur in start()/process() selbst.
void setzen(uint index, out mat4 tr, out vec4 cu) {
	int i = int(index);
	vec2 g = vec2(float(i % seite), float(i / seite));
	vec2 zelle = floor(kamera.xz / abstand) - float(seite / 2) + g;
	float z1 = zufall(zelle);
	float z2 = zufall(zelle + 17.31);
	float z3 = zufall(zelle + 41.73);
	vec2 p = (zelle + vec2(z1, z2)) * abstand;
	float d = distance(p, kamera.xz);
	float gueltig;
	float y = fein_hoehe(p, gueltig);
	vec2 m = texelFetch(gras_maske, ivec2(mod(floor(p / fein_zelle), float(fein_n))), 0).rg;
	float an = step(z3, m.r) * gueltig;
	float rand = (1.0 - smoothstep(r_aussen * 0.72, r_aussen, d))
		* smoothstep(r_innen * 0.8, r_innen * 1.1 + 0.001, d);
	float hoch = 1.0 - smoothstep(110.0, 240.0, ueber_grund);
	float s = groesse * (0.60 + 0.75 * z1 * z2) * an * rand * hoch;
	float a = z2 * 6.2832;
	vec3 x = vec3(cos(a), 0.0, -sin(a)) * s;
	vec3 z = vec3(sin(a), 0.0, cos(a)) * s;
	vec3 yv = vec3(0.0, s * (0.75 + 0.55 * z3), 0.0);
	tr = mat4(vec4(x, 0.0), vec4(yv, 0.0), vec4(z, 0.0), vec4(p.x, y - 0.04, p.y, 1.0));
	cu = vec4(m.g, z3, z1, 0.0);
}

void start() {
	setzen(INDEX, TRANSFORM, CUSTOM);
}

void process() {
	setzen(INDEX, TRANSFORM, CUSTOM);
}
