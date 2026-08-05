// Dezente dunkle Vignette an den Bildraendern. Liegt als ColorRect ueber der Szene,
// aber UNTER der Bedien-UI, damit Text und Buttons nicht abgedunkelt werden.
//
// Die Vignette folgt bewusst dem Seitenverhaeltnis (reines SCREEN_UV, keine
// Aspekt-Korrektur): auf 21:9 soll sie die Bildraender saeumen, nicht als Kreis in
// der Mitte stehen.
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float staerke : hint_range(0.0, 1.0) = 0.5;
uniform float radius : hint_range(0.1, 1.2) = 0.58;
uniform float weichheit : hint_range(0.05, 1.2) = 0.62;
uniform vec4 farbe : source_color = vec4(0.02, 0.055, 0.066, 1.0);


void fragment() {
	vec2 d = SCREEN_UV - vec2(0.5);
	float r = length(d) * 1.41421;               // 0 in der Mitte, 1 in den Ecken
	float v = smoothstep(radius, radius + weichheit, r) * staerke;
	COLOR = vec4(farbe.rgb, v);
}
