// VULKANGESTEIN UND LAVA (2026-10-02/03, Nutzer: „der Vulkan schaut nicht gut aus“, nach der ersten
// Fassung: „schaut gar ned geil aus, da gehoert noch viel mehr Muehe rein“).
// ERSTE FASSUNG (verworfen): eigene Zellmuster (Worley) als Blocklava und Farbflecken — aus der
// Naehe Pflaster bzw. Spinnweb, aus der Ferne ein Faltenrock mit orangen Tarnflecken, die Lava
// blasse Linien. Ein fremder Stil neben dem gemalten Fels der Welt.
// JETZT:
//   * STRUKTUR aus den GEMALTEN MATERIALIEN DER WELT (gelaende_kern: Fels triplanar mit Relief,
//     Erde fuer Asche und Schutt) — der Vulkan gehoert damit zum selben Bild wie die Ketten.
//     Hier steht nur die GRUNDFARBE nach Zonen (vk_grund):
//       Basalt kohlschwarz bis braun · Grate heller (aus der Haut) · frische Stroeme schwarz ·
//       rote SCHLACKENKRONE am Gipfel · helle ASCHENRINNEN die Fallinie hinab · Aschenfuss.
//   * LAVA (vk_lava), wo die Haut Glut traegt (COLOR.a < 1): fliessend (Muster laeuft die Fallinie
//     hinab), heisser Kern gelbweiss, nach aussen orange und rot, am Rand dunkle Kruste mit
//     gluehenden Rissen; im Strom treiben dunkle Krustenschollen. Leuchtet weit ueber Weiss
//     (Lichtglanz). Im Krater ein Lavasee (ohne Fliessrichtung, zwei gegenlaeufige Lagen).
// Uniforms setzt TerrainWorld.vulkan_material_setzen (Chunks und Fernschuerze).
uniform vec4 vulkan_kreis = vec4(0.0, 0.0, -1.0, 0.0);   // x, z, Radius voll, Radius aus
uniform vec3 vulkan_mass = vec3(900.0, 240.0, 400.0);     // Gipfelhoehe, Fusshoehe, Kraterradius

// UMFANG der Abwicklung um den Kegel (quer = Winkel / TAU * Umfang). 5100 m ist ein ganzes
// Vielfaches aller Muster, die quer abgetastet werden (150, 34, 12,75 und 5,1 m) — sonst steht im
// Westen, wo der Winkel von -180 auf +180 Grad springt, eine senkrechte Naht im Hang.
const float VK_UMFANG = 5100.0;
const vec3 VK_KOHLE = vec3(0.115, 0.105, 0.105);
const vec3 VK_BRAUN = vec3(0.215, 0.170, 0.150);
const vec3 VK_FRISCH = vec3(0.060, 0.055, 0.058);         // junger, glasiger Strom
const vec3 VK_SCHLACKE = vec3(0.335, 0.165, 0.118);       // oxidierte Schlacke am Gipfel
const vec3 VK_ASCHE = vec3(0.400, 0.375, 0.350);
const vec3 VK_SCHWEFEL = vec3(0.620, 0.560, 0.260);
const vec3 VK_KRUSTE = vec3(0.070, 0.035, 0.030);
const vec3 VK_ROT = vec3(0.85, 0.07, 0.01);
const vec3 VK_ORANGE = vec3(1.00, 0.36, 0.03);
const vec3 VK_GELB = vec3(1.00, 0.78, 0.32);

float vk_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 15u)) * 2246822519u;
	h ^= h >> 13u;
	return float(h >> 8u) * (1.0 / 16777216.0);
}

// Worley: (F1, F2 - F1, Zufall der naechsten Zelle) — nur fuer die Schollen auf der Lava.
// perx: Periode in x (Zellen), damit die Schollen rund um den Kegel nahtlos schliessen.
vec3 vk_zellen(vec2 p, float perx) {
	vec2 i = floor(p);
	vec2 f = p - i;
	float f1 = 8.0;
	float f2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 ig = i + g;
			ig.x = mod(ig.x, perx);
			vec2 o = vec2(vk_hash(ig), vk_hash(ig + vec2(31.0, 17.0)));
			vec2 r = g + 0.15 + o * 0.7 - f;
			float dd = dot(r, r);
			if (dd < f1) {
				f2 = f1;
				f1 = dd;
				id = vk_hash(ig + vec2(7.0, 113.0));
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

// GRUNDFARBE (sRGB) vor den Materialtexturen. asche: 0..1.
// ZWEI Texturproben (dazu eine an der Kraterlippe): zuerst waren es sieben, und zusammen mit Fels-
// UND Erdtextur auf dem ganzen Kegel kostete das Material 2,1 ms in 4K (tools/_gelaende_zeit.gd,
// GZ_VULKAN=1). Mehrere Muster teilen sich jetzt eine Probe ueber verschiedene Kanaele (G = weiches
// Rauschen, B/A = dessen Relief — fuer Flecken gleich gut).
vec3 vk_grund(vec3 roh, vec3 wp, vec3 nrm, float d, out float asche) {
	vec2 rel = wp.xz - vulkan_kreis.xy;
	float rd = length(rel);
	float ang = atan(rel.y, rel.x);
	// quer = Winkel mal FESTEM Radius (812 m). FALLE: mit der Bogenlaenge (Winkel mal Abstand) wandert
	// man auf einer Fallinie quer durch die Textur — ueber dem Kegel lagen Ringe (Zebra).
	float quer = ang * (VK_UMFANG / 6.2831853);
	float t = clamp((wp.y - vulkan_mass.y) / max(vulkan_mass.x - vulkan_mass.y, 1.0), 0.0, 1.0);
	float lum = dot(roh, vec3(0.2126, 0.7152, 0.0722));
	vec4 gross4 = texture(boden_tex, wp.xz / 1100.0 + vec2(0.52, 0.08));
	float gross = gross4.g;
	vec4 lauf4 = texture(boden_tex, vec2(quer / 150.0, rd / 4200.0) + vec2(0.31, 0.77));
	float mittel = lauf4.a;      // kleine Abwechslung aus dem vierten Kanal statt einer eigenen Probe
	// Basalt: kohlschwarz bis warmbraun in grossen Flecken
	vec3 c = mix(VK_KOHLE, VK_BRAUN, smoothstep(0.35, 0.70, gross * 0.7 + mittel * 0.3));
	// Grate und anstehender Fels sind in der Haut heller (Basalt 0.03, Grat 0.31, Anstehendes
	// 0.48): dort helleres, graueres Gestein
	c = mix(c, c * 1.5 + vec3(0.025), smoothstep(0.14, 0.38, lum) * 0.6);
	// junge Stroeme in grossen Zungen: glasig dunkel
	c = mix(c, VK_FRISCH, smoothstep(0.58, 0.72, gross4.b) * 0.8);
	// SCHLACKENKRONE: zum Gipfel hin rot oxidiert, in Zungen auslaufend
	float krone = smoothstep(0.50, 0.92, t + (lauf4.b - 0.5) * 0.55);
	c = mix(c, VK_SCHLACKE * (0.85 + 0.3 * mittel), krone * 0.72);
	// ASCHENRINNEN die Fallinie hinab, nach unten breiter; nicht im Krater
	float streif = smoothstep(0.46, 0.72, lauf4.g) * smoothstep(vulkan_mass.z * 0.95, vulkan_mass.z * 1.3, rd);
	// Aschenfuss: unten und flach liegt Asche und Schutt
	float fuss = (1.0 - smoothstep(0.02, 0.22, t)) * smoothstep(0.80, 0.95, nrm.y);
	asche = clamp(streif * (0.35 + 0.45 * t) + fuss * 0.7, 0.0, 1.0);
	c = mix(c, VK_ASCHE * (0.90 + 0.2 * mittel), asche * 0.72);
	// Schwefel: weiche gelbe Schleier an der Kraterlippe (als kleine harte Flecken in der ganzen
	// Schuessel lag er wie ein Tarnmuster darin)
	float lippe = smoothstep(vulkan_mass.z * 0.78, vulkan_mass.z * 0.97, rd)
		* (1.0 - smoothstep(vulkan_mass.z * 1.02, vulkan_mass.z * 1.16, rd));
	if (lippe > 0.01) {
		float schwefel = smoothstep(0.50, 0.85, texture(boden_tex, wp.xz / 310.0 + vec2(0.4, 0.9)).g) * lippe;
		c = mix(c, VK_SCHWEFEL, schwefel * 0.22);
	}
	// IN DER FERNE heller und waermer: unter dem blauen Dunst (5 km: 17 %) stand der dunkle Kegel
	// sonst lila da
	float fern = smoothstep(2200.0, 6500.0, d);
	c = mix(c, c * vec3(1.55, 1.30, 1.08) + vec3(0.02, 0.01, 0.0), fern);
	return c;
}

// LAVA: deck = wie viel Albedo durch Kruste ersetzt wird, Rueckgabe = Leuchten (linear, HDR).
vec3 vk_lava(vec3 wp, float glut, float d, out float deck, out vec3 kruste) {
	deck = 0.0;
	kruste = VK_KRUSTE;
	vec2 rel = wp.xz - vulkan_kreis.xy;
	float rd = length(rel);
	if (glut < 0.01 && rd > vulkan_mass.z * 0.5) {
		return vec3(0.0);
	}
	float ang = atan(rel.y, rel.x);
	float quer = ang * (VK_UMFANG / 6.2831853);
	float see = 1.0 - smoothstep(vulkan_mass.z * 0.70, vulkan_mass.z * 0.95, rd);
	// DER LAVASEE gluehend bis ans Ufer (die Haut gibt dort nur ein Rissnetz vor): offene Schmelze
	// mit treibenden Schollen
	// (0.72 ueberstrahlte den ganzen See weiss — die Schollen und das Fliessen waren weg)
	float im_see = 1.0 - smoothstep(vulkan_mass.z * 0.43, vulkan_mass.z * 0.50, rd);
	glut = mix(glut, 0.42 + 0.20 * (1.0 - smoothstep(0.0, vulkan_mass.z * 0.30, rd)), im_see);
	// Fliessmuster: laeuft die Fallinie hinab (rd waechst nach unten); im See zwei gegenlaeufige Lagen
	float f1 = texture(boden_tex, vec2(quer / 34.0, rd / 60.0 - TIME * 0.040)).g;
	float f2 = texture(boden_tex, vec2(quer / 12.75 + 0.37, rd / 24.0 - TIME * 0.085)).g;
	float s1 = texture(boden_tex, wp.xz / 70.0 + vec2(TIME * 0.012, -TIME * 0.007)).g;
	float s2 = texture(boden_tex, wp.xz / 27.0 - vec2(TIME * 0.016, TIME * 0.010) + 0.5).g;
	float fl = mix(f1 * 0.62 + f2 * 0.38, s1 * 0.6 + s2 * 0.4, see);
	float m = glut * 1.35 + (fl - 0.5) * 0.55;
	deck = smoothstep(0.10, 0.26, m);
	float heiss = smoothstep(0.34, 0.86, m);
	vec3 e = VK_ROT * smoothstep(0.0, 0.35, heiss) * 1.4
		+ VK_ORANGE * smoothstep(0.25, 0.70, heiss) * 3.2
		+ VK_GELB * smoothstep(0.68, 1.0, heiss) * 3.4;
#ifndef FERN
	if (d < 1600.0) {
		// SCHOLLEN: dunkle Krustenplatten treiben auf dem Strom, dazwischen gluehende Risse
		// Strom: Zellen in der Abwicklung (1000 Zellen rundum, nahtlos); See: Weltlage
		bool im_strom = see < 0.5;
		vec2 zq = im_strom ? vec2(quer / 5.1 + 500.0, (rd - TIME * 2.2) / 9.0) : wp.xz / 7.0 + vec2(TIME * 0.05, 0.0);
		vec3 z = vk_zellen(zq, im_strom ? 1000.0 : 1.0e6);
		float fw = length(fwidth(zq));
		float sicht = 1.0 - smoothstep(0.10, 0.35, fw);
		float riss = 1.0 - smoothstep(0.03, 0.11 + fw, z.y);
		float platte = step(0.35, z.z) * (1.0 - riss);            // zwei Drittel der Zellen tragen Kruste
		// im heissen Kern loesen sich die Platten auf, am Rand schliessen sie sich
		float decke = platte * (1.0 - smoothstep(0.55, 0.95, heiss)) * sicht;
		e *= 1.0 - 0.80 * decke;
		// Kruste am Rand: Risse leuchten
		e += VK_ORANGE * riss * deck * (1.0 - heiss) * 2.2 * sicht;
		kruste = mix(VK_KRUSTE, VK_KRUSTE * 2.2 + vec3(0.03, 0.0, 0.0), z.z);
	}
#endif
	// Flackern (langsam, grossraeumig)
	e *= 0.88 + 0.12 * sin(TIME * 1.7 + rd * 0.02 + ang * 8.0);
	return srgb_linear(clamp(e / 6.0, vec3(0.0), vec3(1.0))) * 6.0 * deck;
}
