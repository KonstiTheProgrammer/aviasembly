shader_type spatial;
// LEBEN AM FLUSS (scripts/Flussleben.gd): Stege, Boote, Muehle, Reiher, Enten, Seerosen.
// Licht wie die Haeuser (weiches_licht + kuehle Himmelsfuellung, shaders/haus.gdshader),
// Farbe = Vertexfarbe (linear). Dazu drei kleine Bewegungen, alle im Vertex-Shader — kein
// Skript, kein Knoten, der je Frame etwas tut:
//   schwimmen: schaukelt auf dem Wasser (Boote, Seerosen, Enten), Phase aus der Lage
//   kreisen:   dreht um `drehpunkt` (rad/s) — eine Entenfamilie paddelt im Kreis
//   drehen:    dreht um die lokale X-Achse durch `drehpunkt` (rad/s) — das Muehlrad
#include "res://shaders/palette.gdshaderinc"

uniform float schwimmen = 0.0;
uniform float kreisen = 0.0;
uniform float drehen = 0.0;
uniform vec3 drehpunkt = vec3(0.0);
uniform float rauheit = 0.85;
uniform float fuellung = 0.26;
const vec3 FUELL_TON = vec3(0.60, 0.72, 0.95);

void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;
	float phase = fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2832;
	if (kreisen != 0.0) {
		float a = TIME * kreisen + phase;
		float c = cos(a);
		float s = sin(a);
		vec3 v = VERTEX - drehpunkt;
		VERTEX = vec3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z) + drehpunkt;
		NORMAL = vec3(c * NORMAL.x + s * NORMAL.z, NORMAL.y, -s * NORMAL.x + c * NORMAL.z);
	}
	if (drehen != 0.0) {
		float a = TIME * drehen;
		float c = cos(a);
		float s = sin(a);
		vec3 v = VERTEX - drehpunkt;
		VERTEX = vec3(v.x, c * v.y - s * v.z, s * v.y + c * v.z) + drehpunkt;
		NORMAL = vec3(NORMAL.x, c * NORMAL.y - s * NORMAL.z, s * NORMAL.y + c * NORMAL.z);
	}
	if (schwimmen > 0.0) {
		float t = TIME * 1.3 + phase;
		VERTEX.y += (sin(t) * 0.045 + sin(t * 2.3) * 0.015) * schwimmen;
		VERTEX.y += VERTEX.x * sin(t * 0.8) * 0.035 * schwimmen;          // rollen
		VERTEX.y += VERTEX.z * sin(t * 0.6 + 1.0) * 0.012 * schwimmen;    // stampfen
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = rauheit;
	EMISSION = ALBEDO * FUELL_TON * fuellung;
}

void light() {
	DIFFUSE_LIGHT += weiches_licht(NORMAL, LIGHT, LIGHT_COLOR, ATTENUATION);
}
