// VULKANGESTEIN (2026-10-02, Nutzer: „der Vulkan schaut nicht gut aus, mach dass er richtig baba
// aussieht, vor allem Struktur und Material“). Vorher lief der Vulkan durch die allgemeine
// Felserkennung: geschichteter Sedimentfels (waagerechte Baenke — an einem Kegel aus Lava falsch)
// mit Moos auf den Simsen, darunter die Vertexfarben als Tarnmuster aus schwarzen Flecken, und
// aus der Ferne stand er dunkelblau da (dunkle Albedo + blaue Himmelsfuellung im Schatten).
// JETZT ein eigenes, gemaltes Material im Umkreis des Vulkans (vulkan_kreis, TerrainWorld):
//   * Grundton nach Lage: Kohlschwarzer Basalt, warmbraune Lavazungen, ROTE SCHLACKE in grossen
//     Feldern (Death Mountain), helle ASCHE-STREIFEN, die die Fallinie hinablaufen (radial um den
//     Gipfel, 70 m breit, 600 m lang) — die Rohfarbe der Haut gibt nur noch Asche/Basalt vor.
//   * Nah: BLOCKLAVA aus Zellen (Worley, 7 m und 2,4 m), jede Zelle ein eigener Ton, dunkle Fugen;
//     wo Glut liegt (COLOR.a < 1), leuchten die Fugen orange.
//   * In der Fernschuerze dieselben Toene ohne Zellen (Farbe passt an der Chunkgrenze).
// Gebraucht aus gelaende_kern: boden_tex, srgb_linear.
uniform vec4 vulkan_kreis = vec4(0.0, 0.0, -1.0, 0.0);   // x, z, Radius voll, Radius aus
uniform float vulkan_spitze = 900.0;                      // Gipfelhoehe (Asche oben heller)

const vec3 VK_KOHLE = vec3(0.125, 0.112, 0.108);
const vec3 VK_BRAUN = vec3(0.22, 0.165, 0.145);
const vec3 VK_SCHLACKE = vec3(0.37, 0.20, 0.15);
const vec3 VK_ASCHE = vec3(0.45, 0.42, 0.39);
const vec3 VK_GLUT = vec3(1.0, 0.36, 0.07);

float vk_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 15u)) * 2246822519u;
	h ^= h >> 13u;
	return float(h >> 8u) * (1.0 / 16777216.0);
}

// Worley: (F1, F2 - F1, Zufall der naechsten Zelle)
vec3 vk_zellen(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(vk_hash(i + g), vk_hash(i + g + vec2(31.0, 17.0)));
			vec2 r = g + 0.15 + o * 0.7 - f;
			float dd = dot(r, r);
			if (dd < f1) {
				f2 = f1;
				f1 = dd;
				id = vk_hash(i + g + vec2(7.0, 113.0));
			} else if (dd < f2) {
				f2 = dd;
			}
		}
	}
	return vec3(sqrt(f1), sqrt(f2) - sqrt(f1), id);
}

// Anteil Vulkangestein an wp (0 ausserhalb).
float vk_anteil(vec3 wp) {
	if (vulkan_kreis.z < 0.0) {
		return 0.0;
	}
	float rd = distance(wp.xz, vulkan_kreis.xy);
	return 1.0 - smoothstep(vulkan_kreis.z, vulkan_kreis.w, rd);
}

// Farbe (sRGB) des Gesteins; glow = zusaetzliches Leuchten (linear) in den Fugen.
vec3 vk_farbe(vec3 roh, vec3 wp, vec3 nrm, float d, float glut, out vec3 glow, out float fuge) {
	glow = vec3(0.0);
	fuge = 0.0;
	vec2 rel = wp.xz - vulkan_kreis.xy;
	float rd = length(rel);
	float ang = atan(rel.y, rel.x);
	// Asche-Streifen die Fallinie hinab: quer = Winkel mal FESTEM Radius (800 m), laengs = Abstand.
	// FALLE: mit der Bogenlaenge (Winkel mal Abstand) wanderte man auf einer Fallinie quer durch
	// die Textur — ueber den Kegel lagen Ringe, im Bild ein Hoehenlinien-Zebra. Die Streifen
	// werden so nach unten breiter, wie echte Aschenrinnen.
	// (Naht bei ang = +-PI: dort springt quer — die Textur kachelt mit 160 m, 800*TAU/160 = 31,4
	// Kacheln, also nicht ganz; der Sprung liegt im Norden auf der Rueckseite.)
	float quer = ang * 800.0;
	float streif = texture(boden_tex, vec2(quer / 160.0, rd / 4200.0) + vec2(0.31, 0.77)).g;
	streif = smoothstep(0.42, 0.70, streif);
	// nicht im Krater (dort liefen die Streifen als Speichen in die Mitte zusammen)
	float r_kegel = vulkan_kreis.z / 1.02;
	streif *= smoothstep(r_kegel * 0.27, r_kegel * 0.38, rd);
	// grosse Schlackenfelder
	float schlacke = texture(boden_tex, wp.xz / 1700.0 + vec2(0.63, 0.19)).g
		+ (texture(boden_tex, wp.xz / 520.0 + vec2(0.11, 0.45)).g - 0.5) * 0.5;
	schlacke = smoothstep(0.58, 0.80, schlacke);
	float lum = dot(roh, vec3(0.2126, 0.7152, 0.0722));
	// Basalt: kohlschwarz bis warmbraun. Die Rohfarbe nur schwach: die Rippen der Haut sind
	// heller, und voll genommen lagen ihre Grate als Hoehenlinien-Zebra auf der Flanke.
	// grosse weiche Flecken (in der Laenge der Fallinie abgetastet gab die Textur Ringe um den
	// Kegel, im Bild Hoehenlinien)
	float braun = texture(boden_tex, wp.xz / 1100.0 + vec2(0.52, 0.08)).g;
	vec3 c = mix(VK_KOHLE, VK_BRAUN, smoothstep(0.35, 0.70, braun) * 0.8);
	c = mix(c, VK_SCHLACKE, schlacke * mix(0.65, 0.35, smoothstep(1500.0, 4500.0, d)));
	// Asche: auf flacherem Grund und in den Streifen, oben am Kegel mehr
	float oben = smoothstep(vulkan_spitze * 0.45, vulkan_spitze * 0.95, wp.y);
	float flach = smoothstep(0.70, 0.92, nrm.y);
	// NICHT aus Neigung oder Rohhelligkeit: beide wechseln auf jeder kleinen Welle der Flanke,
	// und die Asche lag dann als Hoehenlinien-Zebra quer ueber dem Kegel. Nur der Aschenfuss
	// (sehr helle Rohfarbe, dort flach auslaufend) zaehlt noch.
	float asche = clamp(streif * (0.45 + 0.55 * oben) + smoothstep(0.48, 0.62, lum) * flach, 0.0, 1.0);
	c = mix(c, VK_ASCHE * (0.92 + 0.16 * streif), asche * 0.6);
#ifndef FERN
	if (d < 1100.0) {
		// Projektion nach Flaechenrichtung
		vec2 q = abs(nrm.y) > 0.75 ? wp.xz : (abs(nrm.x) > abs(nrm.z) ? vec2(wp.z, wp.y) : vec2(wp.x, wp.y));
		// BLOCKLAVA: grosse Bloecke (9 m) mit eigenem Ton und Kuppe, feine Bruchkanten nur als
		// schmale Fugen. Mit gleich starken dunklen Fugen auf zwei Massstaeben lag ein Netz wie
		// ein Spinnweb ueber dem Hang.
		// gestreckt (an Waenden laengs der Fallinie hoeher als breit): runde Zellen lasen sich als
		// Pflaster
		vec2 qs = abs(nrm.y) > 0.75 ? q / 9.0 : q / vec2(8.0, 12.0);
		vec3 z1 = vk_zellen(qs);
		float fw = length(fwidth(q)) / 9.0;
		float sicht = 1.0 - smoothstep(0.04, 0.14, fw);
		float f1 = 1.0 - smoothstep(0.012, 0.04 + fw, z1.y);
		float ton = 0.84 + 0.30 * z1.z;
		float kuppe = 1.0 - 0.22 * smoothstep(0.15, 0.95, z1.x);     // Block zur Mitte heller
		vec3 blk = c * ton * kuppe * (1.0 - 0.20 * f1);
		if (d < 260.0) {
			// Koernung (Schlackenbrocken), nur Helligkeit
			vec3 z2 = vk_zellen(q / 1.6 + 17.0);
			float fw2 = fw * 5.6;
			blk *= mix(1.0, 0.86 + 0.24 * z2.z, 1.0 - smoothstep(0.06, 0.25, fw2));
		}
		// nur auf dem Basalt; Asche bleibt feinkoernig und glatt
		float block_w = sicht * (1.0 - asche) * (1.0 - asche);
		c = mix(c, blk, block_w);
		fuge = f1 * block_w;
		glow = srgb_linear(VK_GLUT) * f1 * sicht * smoothstep(0.05, 0.6, glut) * 2.6;
	}
#endif
	return c;
}
