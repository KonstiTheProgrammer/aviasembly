// Blueprint-Buehne fuer den Bau-Modus: dunkle Petrolflaeche mit feinem cyanfarbenem
// Raster, das mit der Entfernung weich verschwindet.
//
// BEWUSST BELEUCHTET — kein `unshaded`. Der Boden soll den Kontaktschatten des
// Flugzeugs annehmen; das kann eine unbeleuchtete Flaeche nicht. Rauheit steht hoch
// und SPECULAR niedrig, damit daraus kein Spiegel wird.
//
// MOIRE-SCHUTZ: In der Ferne fallen mehrere Rasterzellen auf ein Pixel, und das
// Raster faengt an zu flimmern. `raster` misst darum ueber fwidth, wie viele Pixel
// eine Zelle noch breit ist, und blendet die Linie unterhalb weniger Pixel aus.
// Dadurch bleibt das Bild auch bei flachem Blickwinkel und hoher Aufloesung ruhig —
// und zwar aufloesungsunabhaengig, weil fwidth in Bildschirmpixeln misst.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 grund_farbe : source_color = vec3(0.055, 0.150, 0.176);
uniform vec3 linien_farbe : source_color = vec3(0.42, 0.86, 0.92);
uniform float zelle = 1.0;                                  // Kantenlaenge feines Raster (m)
uniform float haupt_alle = 8.0;                             // jede n-te Linie ist Hauptlinie
uniform float fein_staerke : hint_range(0.0, 0.5) = 0.075;  // Vorgabe: 8-18 % Linienanteil
uniform float haupt_staerke : hint_range(0.0, 0.5) = 0.165;
uniform float fade_start = 12.0;
uniform float fade_ende = 58.0;
uniform float rauheit : hint_range(0.0, 1.0) = 0.94;
// KEINE RANDAUFLOESUNG HIER — und das ist eine bewusste Entscheidung, zweimal gegen die
// naheliegende Loesung. Die Bodenplatte war frueher 220 m gross, ihre Kante stand als
// harte Linie im Bild, und dagegen lief ein Environment-Nebel. Der ueberdeckte
// zwangslaeufig auch das Flugzeug — im Bau-Modus ausgerechnet das, was man ansehen will.
// Der erste Ersatzversuch war, die Platte in den Horizontton des Himmels auslaufen zu
// lassen. Gerendert bei 110 m Kameraabstand (dem Maximum im Bau-Modus) war das
// SCHLECHTER als der Nebel: der Himmel ist ein VERLAUF, eine feste Farbe trifft ihn nur
// auf einer einzigen Hoehe, und dazwischen stand ein heller Bogen quer durchs Bild.
// Jetzt ist die Platte einfach gross genug, dass ihre Kante nie ins Bild kommt (siehe
// ShowroomStage._baue_boden). Damit endet der Boden dort, wo ein Boden enden soll: am
// Horizont. Das kostet nichts — eine Flaeche bleibt eine Flaeche, egal wie gross.

varying vec3 wpos;


void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


// Kantengeglaettete Rasterlinie mit Ausblendung, sobald die Zelle zu klein wird.
float raster(vec2 p, float div) {
	vec2 c = p / div;
	vec2 w = fwidth(c);
	vec2 g = abs(fract(c - 0.5) - 0.5) / max(w, vec2(1e-5));
	float linie = 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
	float dichte = 1.0 / max(max(w.x, w.y), 1e-5);          // Pixel pro Zelle
	return linie * smoothstep(2.5, 7.0, dichte);
}


void fragment() {
	vec2 p = wpos.xz;
	float fein = raster(p, zelle);
	float haupt = raster(p, zelle * haupt_alle);
	// Ausblenden nach KAMERA-Abstand, nicht nach Weltmittelpunkt: sonst bliebe das
	// Raster beim Herausfahren stehen und riss eine harte Kante in den Hintergrund.
	float fade = 1.0 - smoothstep(fade_start, fade_ende, distance(wpos, CAMERA_POSITION_WORLD));
	float staerke = max(fein * fein_staerke, haupt * haupt_staerke) * fade;
	ALBEDO = mix(grund_farbe, linien_farbe, staerke);
	ROUGHNESS = rauheit;
	METALLIC = 0.0;
	SPECULAR = 0.12;
}
