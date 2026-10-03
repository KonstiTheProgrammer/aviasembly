// LAVABOMBEN UND FEUERBALL (scripts/Vulkanausbruch.gd): bei jedem Ausbruch fliegen gluehende Brocken
// aus dem Schlot, ziehen im Flug einen Leuchtstreif hinter sich her (die Tafel ist in Flugrichtung
// gestreckt), schlagen auf Kraterwand und Flanken auf und gluehen dort noch eine Weile nach. Bahn,
// Aufschlag und Abkuehlung siehe vulkan_ausbruch.gdshaderinc. Je Instanz nur die Bombennummer
// (INSTANCE_CUSTOM.x); INSTANCE_CUSTOM.y > 0.5 = FEUERBALL ueber dem Schlot (die ersten zwei Sekunden).
// Die Lage der Instanz bleibt die Einheit — die Tafel setzt der Vertex-Shader in WELTKOORDINATEN.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords;

#include "res://shaders/vulkan_ausbruch.gdshaderinc"

uniform float nachgluehen = 16.0;     // s nach dem Aufschlag

varying vec3 farbe;
varying float deck;
varying float ball;
varying float ferne;

void vertex() {
	farbe = vec3(0.0);
	deck = 0.0;
	ball = INSTANCE_CUSTOM.y;
	ferne = 1.0;
	vec3 p = schlot;
	vec3 rechts = INV_VIEW_MATRIX[0].xyz;
	vec3 oben = INV_VIEW_MATRIX[1].xyz;
	float s = 0.0;
	float streck = 1.0;
	if (stoss_alter < 60.0) {
		if (ball > 0.5) {
			// FEUERBALL: quillt in zwei Sekunden aus dem Schlot auf und erlischt
			float a = stoss_alter - INSTANCE_CUSTOM.z * 0.35;
			float k = INSTANCE_CUSTOM.x;
			// aus dem Kessel ueber den Rand (im Kessel saehe man ihn nur von oben)
			p = schlot + vec3(cos(k * 6.28) * 70.0 * a, rand_tiefe * 0.7 + a * (150.0 + 90.0 * INSTANCE_CUSTOM.w),
				sin(k * 6.28) * 70.0 * a);
			deck = step(0.0, a) * exp(-max(a, 0.0) * 1.3);
			s = (90.0 + 240.0 * (1.0 - exp(-max(a, 0.0) * 1.3))) * step(0.0, a) * step(a, 3.5);
			farbe = mix(vec3(1.0, 0.30, 0.04), vec3(1.0, 0.80, 0.45), deck);
		} else {
			vec3 v0;
			float verzug;
			float gr;
			vb_start(INSTANCE_CUSTOM.x, v0, verzug, gr);
			float t = stoss_alter - verzug;
			float tl = vb_landung(v0);
			float tf = clamp(t, 0.0, tl);
			p = vb_ort(v0, tf);
			vec3 v = t < tl ? vb_tempo(v0, tf) : vec3(0.0);
			// ABKUEHLUNG: im Flug von Gelbweiss nach Orange, am Boden weiter nach Dunkelrot, dann aus
			float alter = max(t, 0.0);
			float am_boden = max(t - tl, 0.0);
			float hitze = (1.0 - smoothstep(0.0, 12.0, alter)) * 0.65 + 0.35;
			hitze *= 1.0 - smoothstep(0.0, nachgluehen, am_boden);
			// GESAETTIGT: mit Gelbweiss im Kern standen die Bomben additiv vor dem Himmel als weisse
			// Federn da
			farbe = mix(vec3(0.75, 0.05, 0.01), vec3(1.0, 0.28, 0.04), smoothstep(0.15, 0.55, hitze));
			farbe = mix(farbe, vec3(1.0, 0.52, 0.12), smoothstep(0.65, 1.0, hitze));
			deck = hitze * step(0.0, t) * (1.0 - step(tl + nachgluehen, t));
			// Tafel in Flugrichtung gestreckt (Bewegungsunschaerfe der hellen Brocken)
			vec3 zur_kam = normalize(CAMERA_POSITION_WORLD - p);
			vec3 vq = v - zur_kam * dot(v, zur_kam);
			float vl = length(vq);
			if (vl > 1.0) {
				oben = vq / vl;
				rechts = normalize(cross(oben, zur_kam));
				streck = 1.0 + min(vl * 0.02, 2.5);
			}
			s = gr * (0.6 + 0.4 * hitze) * step(0.001, deck);
			// Aus der Ferne nicht unter einen Bildpunkt fallen: das Leuchten waechst mit dem Abstand
			// ... aber nicht heller werden: sonst stand der Schwall aus 6 km als weisser Stern da
			ferne = max(1.0, distance(CAMERA_POSITION_WORLD, p) / 1300.0);
			s *= ferne;
		}
	}
	VERTEX = p + (rechts * VERTEX.x + oben * VERTEX.y * streck) * s * 2.0;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float kern = 1.0 - smoothstep(0.0, 0.45, r);
	float hof = 1.0 - smoothstep(0.2, 1.0, r);
	if (ball > 0.5) {
		hof = pow(hof, 1.6);
		ALBEDO = farbe * (hof * 1.6 + kern * 1.4) * deck;
	} else {
		ALBEDO = (farbe * hof * 1.7 + mix(farbe, vec3(1.0, 0.75, 0.45), 0.5) * kern * 1.6) * deck / (ferne * ferne);
	}
}
