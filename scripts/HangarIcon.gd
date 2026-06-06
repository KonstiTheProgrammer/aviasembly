class_name HangarIcon
extends Control
## Selbst gezeichnete Vektor-Icons (Linien-Art, gleichmäßige Strichstärke, runde Enden).
## Ersetzt Emojis im UI. setup(kind, farbe) wählt das Motiv; gezeichnet in _draw().

var kind := ""
var col := Color(0.88, 0.92, 0.97)
var thick := 2.0

var _o := Vector2.ZERO      # Ursprung des Einheits-Quadrats (Pixel)
var _s := 1.0               # Kantenlänge des Einheits-Quadrats (Pixel)

func setup(k: String, c: Color, t := 2.0) -> HangarIcon:
	kind = k
	col = c
	thick = t
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	return self

func _ready() -> void:
	# Custom _draw wird bei Layout-Resize NICHT automatisch erneut aufgerufen -> selbst anstoßen,
	# sonst zeichnet das Icon einmal bei Größe 0 und bleibt unsichtbar.
	resized.connect(queue_redraw)
	queue_redraw()

# --- Zeichen-Helfer (Einheitskoordinaten 0..1, y nach unten) ---
func _u(x: float, y: float) -> Vector2:
	return _o + Vector2(x, y) * _s

func _poly(pts: Array, closed := false) -> void:
	var a := PackedVector2Array()
	for p in pts:
		a.append(_u(p.x, p.y))
	if closed:
		a.append(a[0])
	if a.size() >= 2:
		draw_polyline(a, col, thick, true)

func _line(x0: float, y0: float, x1: float, y1: float) -> void:
	draw_line(_u(x0, y0), _u(x1, y1), col, thick, true)

func _fill(pts: Array) -> void:
	var a := PackedVector2Array()
	for p in pts:
		a.append(_u(p.x, p.y))
	draw_colored_polygon(a, col)

func _arc(cx: float, cy: float, r: float, a0: float, a1: float) -> void:
	draw_arc(_u(cx, cy), r * _s, a0, a1, 40, col, thick, true)

func _ring(cx: float, cy: float, r: float) -> void:
	draw_arc(_u(cx, cy), r * _s, 0.0, TAU, 48, col, thick, true)

# Pfeilspitze bei (tx,ty), zeigt in Richtung (dx,dy).
func _arrow(tx: float, ty: float, dx: float, dy: float, sz := 0.15) -> void:
	var tip := _u(tx, ty)
	var d := Vector2(dx, dy).normalized()
	var back := tip - d * sz * _s
	var perp := Vector2(-d.y, d.x) * sz * 0.68 * _s
	draw_polyline(PackedVector2Array([back + perp, tip, back - perp]), col, thick, true)

func _draw() -> void:
	var n: float = minf(size.x, size.y)
	var pad: float = n * 0.15
	_s = n - 2.0 * pad
	_o = Vector2((size.x - _s) * 0.5, (size.y - _s) * 0.5)
	match kind:
		"move":
			_line(0.5, 0.1, 0.5, 0.9)
			_line(0.1, 0.5, 0.9, 0.5)
			_arrow(0.5, 0.08, 0, -1)
			_arrow(0.5, 0.92, 0, 1)
			_arrow(0.08, 0.5, -1, 0)
			_arrow(0.92, 0.5, 1, 0)
		"rotate":
			_arc(0.5, 0.5, 0.38, deg_to_rad(35), deg_to_rad(300))
			# Pfeilspitze am Bogenende (300°)
			var e := Vector2(cos(deg_to_rad(300)), sin(deg_to_rad(300)))
			_arrow(0.5 + e.x * 0.38, 0.5 + e.y * 0.38, -e.y, e.x)
		"scale":
			# Diagonaler Doppelpfeil + kleine Eckwinkel
			_line(0.28, 0.72, 0.72, 0.28)
			_arrow(0.74, 0.26, 1, -1)
			_arrow(0.26, 0.74, -1, 1)
			_poly([Vector2(0.12, 0.42), Vector2(0.12, 0.12), Vector2(0.42, 0.12)])
			_poly([Vector2(0.88, 0.58), Vector2(0.88, 0.88), Vector2(0.58, 0.88)])
		"ends":
			# Kasten in der Mitte, Pfeile an beiden Enden nach außen
			_poly([Vector2(0.4, 0.28), Vector2(0.6, 0.28), Vector2(0.6, 0.72), Vector2(0.4, 0.72)], true)
			_line(0.4, 0.5, 0.16, 0.5)
			_arrow(0.1, 0.5, -1, 0)
			_line(0.6, 0.5, 0.84, 0.5)
			_arrow(0.9, 0.5, 1, 0)
		"trash":
			_line(0.16, 0.27, 0.84, 0.27)
			_poly([Vector2(0.4, 0.27), Vector2(0.4, 0.16), Vector2(0.6, 0.16), Vector2(0.6, 0.27)])
			_poly([Vector2(0.26, 0.27), Vector2(0.31, 0.86), Vector2(0.69, 0.86), Vector2(0.74, 0.27)])
			_line(0.42, 0.4, 0.44, 0.74)
			_line(0.58, 0.4, 0.56, 0.74)
			_line(0.5, 0.4, 0.5, 0.74)
		"paint":
			# Pinsel: Stiel diagonal + Borstenkopf
			_line(0.82, 0.18, 0.5, 0.5)
			_poly([Vector2(0.5, 0.5), Vector2(0.34, 0.42), Vector2(0.24, 0.58), Vector2(0.42, 0.66)], true)
			_poly([Vector2(0.24, 0.58), Vector2(0.16, 0.82), Vector2(0.42, 0.66)])
		"undo":
			_arc(0.52, 0.55, 0.34, deg_to_rad(80), deg_to_rad(330))
			_arrow(0.18, 0.5, -0.4, -1)
		"redo":
			_arc(0.48, 0.55, 0.34, deg_to_rad(210), deg_to_rad(100))
			_arrow(0.82, 0.5, 0.4, -1)
		"target":
			_ring(0.5, 0.5, 0.34)
			_line(0.5, 0.04, 0.5, 0.24)
			_line(0.5, 0.76, 0.5, 0.96)
			_line(0.04, 0.5, 0.24, 0.5)
			_line(0.76, 0.5, 0.96, 0.5)
			draw_circle(_u(0.5, 0.5), thick * 1.1, col)
		"wind":
			_arc(0.62, 0.28, 0.12, deg_to_rad(-90), deg_to_rad(160))
			_line(0.12, 0.28, 0.6, 0.28)
			_line(0.12, 0.5, 0.78, 0.5)
			_arc(0.74, 0.72, 0.12, deg_to_rad(-90), deg_to_rad(160))
			_line(0.12, 0.72, 0.72, 0.72)
		"symmetry":
			for i in 5:
				var yy: float = 0.1 + float(i) * 0.2
				_line(0.5, yy, 0.5, yy + 0.1)
			_poly([Vector2(0.42, 0.28), Vector2(0.42, 0.72), Vector2(0.16, 0.5)], true)
			_poly([Vector2(0.58, 0.28), Vector2(0.58, 0.72), Vector2(0.84, 0.5)], true)
		"new":
			_line(0.5, 0.16, 0.5, 0.84)
			_line(0.16, 0.5, 0.84, 0.5)
		"save":
			_poly([Vector2(0.18, 0.18), Vector2(0.66, 0.18), Vector2(0.82, 0.34),
				Vector2(0.82, 0.82), Vector2(0.18, 0.82)], true)
			_poly([Vector2(0.34, 0.18), Vector2(0.34, 0.4), Vector2(0.6, 0.4), Vector2(0.6, 0.18)])
			_poly([Vector2(0.34, 0.82), Vector2(0.34, 0.58), Vector2(0.66, 0.58), Vector2(0.66, 0.82)])
		"load":
			_poly([Vector2(0.14, 0.34), Vector2(0.42, 0.34), Vector2(0.5, 0.44),
				Vector2(0.86, 0.44), Vector2(0.86, 0.8), Vector2(0.14, 0.8)], true)
		"play":
			_fill([Vector2(0.3, 0.18), Vector2(0.3, 0.82), Vector2(0.84, 0.5)])
		"duplicate":
			_poly([Vector2(0.34, 0.16), Vector2(0.84, 0.16), Vector2(0.84, 0.66), Vector2(0.34, 0.66)], true)
			_poly([Vector2(0.16, 0.34), Vector2(0.66, 0.34), Vector2(0.66, 0.84), Vector2(0.16, 0.84)], true)
		"chev_down":
			_poly([Vector2(0.26, 0.4), Vector2(0.5, 0.64), Vector2(0.74, 0.4)])
		"chev_right":
			_poly([Vector2(0.4, 0.26), Vector2(0.64, 0.5), Vector2(0.4, 0.74)])
		"stats":
			_line(0.14, 0.84, 0.86, 0.84)
			draw_rect(Rect2(_u(0.22, 0.6), Vector2(0.12 * _s, 0.24 * _s)), col, false, thick)
			draw_rect(Rect2(_u(0.44, 0.46), Vector2(0.12 * _s, 0.38 * _s)), col, false, thick)
			draw_rect(Rect2(_u(0.66, 0.3), Vector2(0.12 * _s, 0.54 * _s)), col, false, thick)
		"coin":
			_ring(0.5, 0.5, 0.36)
			_ring(0.5, 0.5, 0.2)
			_line(0.5, 0.16, 0.5, 0.34)
			_line(0.5, 0.66, 0.5, 0.84)
		"wrench":
			# Schraubenschlüssel: offener Ringkopf + diagonaler Stiel
			_arc(0.32, 0.32, 0.18, deg_to_rad(120), deg_to_rad(390))
			_line(0.42, 0.42, 0.82, 0.82)
			_line(0.82, 0.7, 0.82, 0.86)
			_line(0.7, 0.82, 0.86, 0.82)
		"plane":
			# Stilisiertes Flugzeug (Draufsicht)
			_poly([Vector2(0.5, 0.1), Vector2(0.58, 0.4), Vector2(0.9, 0.6), Vector2(0.58, 0.56),
				Vector2(0.56, 0.78), Vector2(0.66, 0.88), Vector2(0.5, 0.84), Vector2(0.34, 0.88),
				Vector2(0.44, 0.78), Vector2(0.42, 0.56), Vector2(0.1, 0.6), Vector2(0.42, 0.4)], true)
		"lock":
			_poly([Vector2(0.26, 0.46), Vector2(0.74, 0.46), Vector2(0.74, 0.84), Vector2(0.26, 0.84)], true)
			_arc(0.5, 0.46, 0.16, deg_to_rad(180), deg_to_rad(360))
			draw_circle(_u(0.5, 0.62), thick * 1.1, col)
		"dot":
			draw_circle(_u(0.5, 0.5), 0.32 * _s, col)
		"reset":
			_arc(0.5, 0.5, 0.34, deg_to_rad(70), deg_to_rad(340))
			_arrow(0.2, 0.42, -0.5, -1.0)
			draw_circle(_u(0.5, 0.5), thick * 1.0, col)
		"warn":
			_poly([Vector2(0.5, 0.14), Vector2(0.9, 0.84), Vector2(0.1, 0.84)], true)
			_line(0.5, 0.4, 0.5, 0.64)
			draw_circle(_u(0.5, 0.75), thick * 1.0, col)
		"check":
			_poly([Vector2(0.18, 0.54), Vector2(0.42, 0.76), Vector2(0.84, 0.28)])
		_:
			_ring(0.5, 0.5, 0.3)
