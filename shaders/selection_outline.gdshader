// Dezente helle Kontur um das ausgewaehlte Bauteil.
//
// TECHNIK: zweiter Materialpass mit Front-Culling. Die Geometrie waechst entlang
// ihrer Normalen nach aussen; weil nur die Rueckseiten gezeichnet werden, bleibt
// davon genau der Saum uebrig, der ueber die Silhouette hinausragt — das Teil selbst
// verdeckt den Rest.
//
// Das Wachstum passiert in BILDSCHIRMPIXELN, nicht in Weltmetern. Mit einem festen
// Weltmass waere der Rand bei herausgezoomter Kamera hauchduenn und beim Heranzoomen
// fingerdick; die Vorgabe verlangt aber konstante 2-4 px.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, depth_draw_never, blend_mix;

uniform vec4 kontur_farbe : source_color = vec4(0.867, 0.957, 0.918, 1.0);
uniform float pixel = 3.0;                       // Randstaerke in Bildschirmpixeln
uniform float staerke : hint_range(0.0, 1.0) = 1.0;   // fuer weiches Ein-/Ausblenden


void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip_n = PROJECTION_MATRIX * MODELVIEW_MATRIX
		* vec4(VERTEX + normalize(NORMAL) * 0.01, 1.0);
	vec2 a = clip.xy / max(clip.w, 1e-5);
	vec2 b = clip_n.xy / max(clip_n.w, 1e-5);
	vec2 richtung = b - a;
	// Entartete Normalen (Normale zeigt zur Kamera) wuerden hier NaN liefern.
	if (length(richtung) < 1e-6) {
		richtung = vec2(0.0);
	} else {
		richtung = normalize(richtung);
	}
	clip.xy += richtung * (pixel * 2.0 / VIEWPORT_SIZE) * clip.w;
	POSITION = clip;
}


void fragment() {
	ALBEDO = kontur_farbe.rgb;
	ALPHA = staerke * kontur_farbe.a;
}
