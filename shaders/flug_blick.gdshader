// FLUG-BLICK: was das Auge des Piloten mit dem Bild macht — EIN Vollbild-Rechteck unter dem
// HUD (Main._blick_aufbauen), gesteuert von Main._blick_nachfuehren.
//
//   * SONNENBLENDUNG: ein weicher Schleier um die Sonne, der das halbe Bild aufhellt, wenn
//     man in sie hineinfliegt, dazu Linsenreflexe auf der Achse Sonne -> Bildmitte und ein
//     feiner waagerechter Lichtstreif. Ob die Sonne ueberhaupt sichtbar ist (vor der
//     Kamera, nicht hinter Berg oder Wolke), rechnet das Skript — hier kommt nur die
//     geglaettete Sichtbarkeit an, damit nichts springt.
//   * G-LAST: ab ~4,5 G zieht sich das Sichtfeld grau zusammen (Tunnelblick), bei
//     negativer Last faerbt es rot ein. Die Grenzen stehen im Skript.
//   * TEMPO: bei hoher Geschwindigkeit dunkeln die Raender leicht ab — das Auge fokussiert
//     nach vorn.
//
// KEIN SCREEN_TEXTURE: eine Bildkopie kostet in 4K rund eine Millisekunde (gemessen am
// Wasser, siehe wasser_kern.gdshaderinc). Alles hier ist Abdunkeln oder Addieren, und das
// geht mit vormultipliziertem Alpha in EINEM Zeichenaufruf:
//     Ergebnis = COLOR.rgb + Bild * (1 - COLOR.a)
// COLOR.rgb traegt also das Licht (Blendung, Reflexe) plus die Farbe des Schleiers, COLOR.a
// wie stark das darunterliegende Bild zurueckgenommen wird.
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

uniform vec2  sonne_uv = vec2(0.5, -1.0);   // Sonne im Bild (0..1), auch ausserhalb
uniform float sonne_sicht : hint_range(0.0, 1.0) = 0.0;
uniform vec3  sonne_farbe : source_color = vec3(1.0, 0.90, 0.72);
uniform float blendung = 0.30;              // Staerke des Schleiers
uniform float reflexe = 0.40;               // Staerke der Linsenreflexe
uniform float grau : hint_range(0.0, 1.0) = 0.0;   // G-Tunnelblick
uniform float rot  : hint_range(0.0, 1.0) = 0.0;   // negative G
uniform float tempo : hint_range(0.0, 1.0) = 0.0;
uniform float vignette = 0.16;              // Grundvignette (immer)

// Weiche Scheibe mit hellerem Rand — so sieht ein Reflex im Objektiv aus (Blendenform).
float reflex(vec2 p, vec2 c, float r) {
	float d = length(p - c) / r;
	float scheibe = 1.0 - smoothstep(0.75, 1.0, d);
	float ring = smoothstep(0.70, 0.92, d) * (1.0 - smoothstep(0.92, 1.0, d));
	return scheibe * 0.35 + ring * 0.65;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Seitenverhaeltnis, damit Kreise rund bleiben (1/SCREEN_PIXEL_SIZE = Bildgroesse).
	vec2 groesse = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 asp = vec2(groesse.x / groesse.y, 1.0);
	vec2 p = (uv - 0.5) * asp;
	vec2 s = (sonne_uv - 0.5) * asp;
	float r = length(p);

	// --- Abdunkeln: Grundvignette, Tempo, G -------------------------------------------
	float rand = length((uv - 0.5) * vec2(1.0, 0.82)) * 1.414;   // 0 Mitte, ~1 Ecke
	float dunkel = smoothstep(0.55, 1.25, rand) * (vignette + tempo * 0.22);
	// Tunnelblick: der dunkle Ring waechst mit der Last nach innen, bis nur ein Fleck in
	// der Mitte bleibt. Die Farbe ist ein kaltes Grau, kein Schwarz — so beschreiben es
	// Piloten (Farben verschwinden zuerst, dann das Umfeld).
	float tunnel = smoothstep(mix(1.10, 0.05, grau), mix(1.7, 0.50, grau), rand)
		* smoothstep(0.0, 0.35, grau);
	float rot_rand = smoothstep(mix(1.3, 0.2, rot), mix(2.0, 0.9, rot), rand) * rot;
	vec3 schleier_farbe = vec3(0.0);
	float a = dunkel;
	// Grau: das Bild wird nicht nur dunkler, es verliert auch Kontrast (halbe Deckung in
	// einem mittleren Grau statt voller Deckung in Schwarz).
	schleier_farbe += vec3(0.09, 0.095, 0.105) * tunnel;
	a = 1.0 - (1.0 - a) * (1.0 - tunnel * 0.97);
	schleier_farbe += vec3(0.42, 0.02, 0.02) * rot_rand;
	a = 1.0 - (1.0 - a) * (1.0 - rot_rand * 0.85);

	// --- Licht: Blendung und Reflexe ------------------------------------------------------
	vec3 licht = vec3(0.0);
	if (sonne_sicht > 0.001) {
		float ds = length(p - s);
		// Wie nah die Sonne an der Bildmitte steht: schaut man direkt hinein, blendet es
		// ueber das ganze Bild, am Bildrand nur noch um die Sonne herum.
		float mitte = 1.0 - smoothstep(0.0, 0.9, length(s));
		// Enger Hof um die Sonne + breiter, schwacher Schleier. Der breite Teil war anfangs
		// doppelt so stark und wusch die halbe Bildhaelfte weiss — Blendung soll man
		// spueren, nicht das Motiv verlieren.
		float schleier = exp(-ds * 4.5) * 0.30 + exp(-ds * 16.0) * 0.70;
		licht += sonne_farbe * schleier * blendung * (0.35 + 0.65 * mitte);
		licht += sonne_farbe * 0.035 * mitte * mitte * blendung;            // Streulicht
		// Waagerechter Lichtstreif durch die Sonne (anamorph, sehr fein).
		float streif = exp(-abs(p.y - s.y) * 180.0) * exp(-abs(p.x - s.x) * 1.6);
		licht += sonne_farbe * streif * 0.10 * blendung;
		// Reflexe liegen auf der Geraden Sonne -> Mitte -> gegenueber. Je Reflex ein Ort auf
		// dieser Geraden, eine Groesse und eine Farbe; sie wandern mit, wenn man die Nase
		// bewegt, und das macht sie glaubwuerdig. Sie entstehen im Objektiv: je naeher die
		// Sonne der Bildmitte, desto heller, weit draussen verschwinden sie.
		vec2 ach = -s;
		vec3 rf = vec3(0.0);
		rf += vec3(1.00, 0.85, 0.60) * reflex(p, s + ach * 0.30, 0.015) * 0.45;
		rf += vec3(0.35, 0.75, 0.70) * reflex(p, s + ach * 0.55, 0.030) * 0.35;
		rf += vec3(0.95, 0.55, 0.25) * reflex(p, s + ach * 1.25, 0.075) * 0.22;
		rf += vec3(0.55, 0.45, 0.95) * reflex(p, s + ach * 1.60, 0.045) * 0.28;
		rf += vec3(0.40, 0.85, 0.55) * reflex(p, s + ach * 2.10, 0.120) * 0.12;
		licht += rf * reflexe * (0.25 + 0.75 * mitte);
		licht *= sonne_sicht;
	}
	// Licht wird addiert, das Bild darunter aber nicht um das Licht zurueckgenommen.
	COLOR = vec4(schleier_farbe + licht * (1.0 - a), a);
}
