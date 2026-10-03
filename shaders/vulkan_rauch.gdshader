// RAUCH AM VULKAN (scripts/Vulkanausbruch.gd), zwei Arten in einem Shader:
//   modus 0  QUELLEN: Fumarolen am Kraterrand (weisser Dampf) und Lavadampf ueber den heissen Stroemen
//            (blaugrau) — je Quelle ein Strang aus Ballen, die periodisch aufsteigen, aufquellen, im
//            Wind abziehen und ausduennen. Quellen in `quellen` (xyz, w = Staerke, negativ = Lavadampf).
//   modus 1  RAUCHSPUREN der Lavabomben: Ballen an der Stelle, an der die Bombe vor `tau` Sekunden war
//            (dieselbe Bahn wie vulkan_bomben, vulkan_ausbruch.gdshaderinc), steigen langsam, quellen
//            und vergehen. Junge Ballen gluehen orange (Feuerschweif).
// Tafeln zur Kamera, gemischt (nicht sortiert: der Rauch ist weich und dunkel, Fehler in der
// Reihenfolge sieht man kaum). Licht als Kugel aus der Tafel geschaetzt: Sonnenseite heller.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, world_vertex_coords;

#include "res://shaders/vulkan_ausbruch.gdshaderinc"

global uniform vec3 sonne_dir;
uniform int modus = 0;
uniform vec4 quellen[16];
uniform float periode = 16.0;
uniform vec3 dampf_farbe : source_color = vec3(0.74, 0.73, 0.71);
uniform vec3 lava_rauch : source_color = vec3(0.55, 0.57, 0.62);
// heller als Asche aussieht: der Dunst legt auf 1-2 km sein Blau darueber, dunkler wurde die Spur blau
uniform vec3 asche_farbe : source_color = vec3(0.36, 0.315, 0.28);
uniform float spur_abstand = 0.25;     // s zwischen zwei Ballen einer Spur

varying vec4 farbe;                   // rgb, Deckung
varying float gestreckt;              // Streckung der Tafel (1 = rund)
varying float glut;
varying float keim;

float rh(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float rrausch(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(rh(i), rh(i + vec2(1.0, 0.0)), f.x), mix(rh(i + vec2(0.0, 1.0)), rh(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 p = vec3(0.0);
	float s = 0.0;
	float a = 0.0;
	vec3 zug = vec3(0.0);                // Bewegung beim Entstehen (m je Ballenabstand): Spur streckt sich
	glut = 0.0;
	gestreckt = 1.0;
	keim = INSTANCE_CUSTOM.w;
	vec3 c = asche_farbe;
	if (modus == 0) {
		vec4 q = quellen[int(INSTANCE_CUSTOM.x)];
		float st = abs(q.w);
		float alter = fract(TIME / periode + INSTANCE_CUSTOM.y) * periode;
		float u = alter / periode;
		vec2 seit = (INSTANCE_CUSTOM.zw - 0.5) * 2.0;
		p = q.xyz + vec3(wind.x * alter * 4.5 + seit.x * 6.0 * u * st, alter * 5.5 * st,
			wind.y * alter * 4.5 + seit.y * 6.0 * u * st);
		s = mix(7.0, 46.0, sqrt(u)) * st;
		a = smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.30, 1.0, u)) * 0.18 * min(st, 1.0);
		c = q.w > 0.0 ? dampf_farbe : lava_rauch;
	} else if (stoss_alter < 60.0) {
		float b = INSTANCE_CUSTOM.x;
		float tau = INSTANCE_CUSTOM.y * spur_abstand;
		vec3 v0;
		float verzug;
		float gr;
		vb_start(b, v0, verzug, gr);
		float t = stoss_alter - verzug;
		float tl = vb_landung(v0);
		float alter = t - tau;
		if (alter > 0.0 && tau < tl) {
			p = vb_ort(v0, tau) + vec3(wind.x * alter * 5.0, alter * 2.2, wind.y * alter * 5.0);
			s = mix(3.5, 20.0, 1.0 - exp(-alter / 3.5)) * (gr / 6.0 + 0.5);
			// JUNGE BALLEN IN FLUGRICHTUNG GESTRECKT: bei 100 m/s liegen zwischen zwei Ballen 30 m —
			// rund gezeichnet war die Spur eine Perlenkette
			zug = vb_tempo(v0, tau) * spur_abstand;
			a = smoothstep(0.0, 0.25, alter) * (1.0 - smoothstep(3.0, 9.0, alter)) * 0.40;
			glut = 1.0 - smoothstep(0.05, 0.5, alter);
			// Junge Ballen nahe dem Schlot heller (Dampf), spaeter Asche
			c = mix(asche_farbe, asche_farbe * 1.9, INSTANCE_CUSTOM.z * 0.5);
		}
	}
	// Licht: Tafelmitte gegen die Sonne geneigt — aus Sicht der Kamera
	vec3 zur_kam = normalize(CAMERA_POSITION_WORLD - p);
	float zur_sonne = dot(sonne_dir, zur_kam) * 0.5 + 0.5;
	farbe = vec4(c * mix(0.55, 1.15, zur_sonne), a);
	float d = distance(CAMERA_POSITION_WORLD, p);
	// nah an der Kamera ausblenden (Durchfliegen ohne Wand vor der Linse); die duennen Spuren auch in
	// der Ferne (aus 8 km standen sie als blasse Splitter im Dunst)
	farbe.a *= smoothstep(s * 0.6, s * 2.0, d) * (1.0 - smoothstep(3500.0, 6500.0, d) * float(modus));
	vec3 rechts = INV_VIEW_MATRIX[0].xyz;
	vec3 oben = INV_VIEW_MATRIX[1].xyz;
	float dreh = keim * 6.2831853 + TIME * 0.05 * (keim - 0.5);
	vec2 ecke = mat2(vec2(cos(dreh), sin(dreh)), vec2(-sin(dreh), cos(dreh))) * VERTEX.xy;
	float streck = 1.0;
	vec3 zq = zug - zur_kam * dot(zug, zur_kam);
	float zl = length(zq);
	if (zl > s) {
		oben = zq / zl;
		rechts = normalize(cross(oben, zur_kam));
		streck = min(zl / (2.0 * s) + 1.0, 8.0);
		ecke = VERTEX.xy;
	}
	gestreckt = streck;
	VERTEX = p + (rechts * ecke.x + oben * ecke.y * streck) * s * 2.0 * step(0.002, a);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	// gestreckte Ballen als KAPSEL: Abstand zur Mittelstrecke in Halbmessern (rund gezeichnet perlte die
	// Spur wie eine Kette, als gestauchte Ellipse endete sie mit harter Kante — eine Leiter)
	float r = length(vec2(q.x, max(abs(q.y) * gestreckt - (gestreckt - 1.0), 0.0)));
	if (r > 1.0) {
		discard;
	}
	// EINE Rauschoktave: die Spuren ueberdecken sich vor der Kamera dutzendfach (mitten im Ausbruch
	// 3,5 ms in 4K mit zwei Oktaven je Bildpunkt)
	float n = rrausch(UV * 4.0 + keim * 17.0);
	float form = 1.0 - smoothstep(0.35 + 0.35 * n, 1.0, r);
	// Kugellicht: oben (Sonnenseite) heller, unten dunkler
	float kugel = 0.85 + 0.25 * (-q.y) * 0.5;
	vec3 c = farbe.rgb * kugel * (0.85 + 0.3 * n);
	c = mix(c, vec3(1.0, 0.45, 0.10) * 3.0, glut * (1.0 - smoothstep(0.0, 0.8, r)));
	ALBEDO = c;
	ALPHA = form * farbe.a;
}
