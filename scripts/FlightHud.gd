## FlightHud.gd — Fancy Jet-Style Primary-Flight-Display (Custom-Drawing).
## Animierte Kompass-Leiste, Bank-Bogen (Querlage), Pitch-Ladder + Horizont, Flight-Path-Marker,
## scrollende Speed-/Höhen-Tapes, Eck-Rahmen, pulsierende Ziel-Lock-Klammern — alles mit
## Phosphor-Glow (Doppel-Strich). Main füttert die Felder je Frame.
class_name FlightHud
extends Control

var heading := 0.0
var pitch := 0.0            # Grad, + = Nase oben
var roll := 0.0             # Grad, + = rechts gebankt
var speed_kmh := 0.0
var speed_ms := 0.0
var altitude := 0.0
var climb := 0.0
var throttle := 0.0
var gforce := 1.0
var stall := false
var mouse_fly := false
var aim_pos := Vector2.ZERO
var aim_vis := false
var nose_pos := Vector2.ZERO
var nose_vis := false
var fpm_pos := Vector2.ZERO
var fpm_vis := false
var targets: Array = []     # Bildschirmpositionen sichtbarer Ziele (Lock-Klammern)

var _disp_heading := 0.0
var _t := 0.0
var _font: Font
const ACCENT := Color(0.40, 1.0, 0.55)       # HUD-Phosphorgrün
const DIM := Color(0.7, 0.92, 1.0)
const WARN := Color(1.0, 0.4, 0.3)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	set_process(true)


func _process(delta: float) -> void:
	_disp_heading += wrapf(heading - _disp_heading, -180.0, 180.0) * clampf(delta * 10.0, 0.0, 1.0)
	_t += delta
	queue_redraw()


func _draw() -> void:
	_draw_corner_frame()
	_draw_compass()
	_draw_bank_arc()
	if mouse_fly:
		_draw_aim_circle()
	else:
		_draw_pitch_ladder()
		_draw_boresight(size * 0.5)
	_draw_fpm()
	_draw_speed_tape()
	_draw_alt_tape()
	_draw_target_locks()
	if stall:
		_draw_stall()


# --- Glow-Helfer (breiter blasser Strich + scharfer heller) ----------------
func _gline(a: Vector2, b: Vector2, c: Color, w := 2.0) -> void:
	draw_line(a, b, Color(c.r, c.g, c.b, c.a * 0.22), w + 3.0)
	draw_line(a, b, c, w)


func _garc(ctr: Vector2, r: float, c: Color, w := 2.0) -> void:
	draw_arc(ctr, r, 0.0, TAU, 56, Color(c.r, c.g, c.b, c.a * 0.22), w + 3.0, true)
	draw_arc(ctr, r, 0.0, TAU, 56, c, w, true)


func _txt(pos: Vector2, s: String, fs: int, c: Color, w := 80.0, al := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(_font, pos, s, al, w, fs, c)


# Geschlossener Polygonzug mit Glow (ohne PackedArray-Verkettung).
func _closed_poly(pts: PackedVector2Array, c: Color, w := 1.5) -> void:
	var n := pts.size()
	for i in n:
		_gline(pts[i], pts[(i + 1) % n], c, w)


# --- Eck-Rahmen (4 abgewinkelte Klammern) ----------------------------------
func _draw_corner_frame() -> void:
	var m := 26.0
	var L := 34.0
	var c := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55)
	var w := size.x
	var h := size.y
	for corner in [Vector2(m, m), Vector2(w - m, m), Vector2(m, h - m), Vector2(w - m, h - m)]:
		var sx: float = 1.0 if corner.x < w * 0.5 else -1.0
		var sy: float = 1.0 if corner.y < h * 0.5 else -1.0
		_gline(corner, corner + Vector2(L * sx, 0), c, 2.0)
		_gline(corner, corner + Vector2(0, L * sy), c, 2.0)


# --- Kompass oben (scrollt mit dem Kurs) -----------------------------------
func _draw_compass() -> void:
	var w := 560.0
	var h := 32.0
	var cx := size.x * 0.5
	var top := 14.0
	var bg := Rect2(cx - w * 0.5, top, w, h)
	draw_rect(bg, Color(0, 0, 0, 0.45))
	draw_rect(bg, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3), false, 1.5)
	var ppd := w / 120.0
	for off in range(-62, 63):
		var x := cx + float(off) * ppd
		if x < bg.position.x + 2.0 or x > bg.position.x + w - 2.0:
			continue
		var di := int(round(fposmod(_disp_heading + float(off), 360.0)))
		if di % 10 != 0:
			continue
		var major: bool = di % 30 == 0
		var tlen := (h * 0.5) if major else (h * 0.28)
		_gline(Vector2(x, top), Vector2(x, top + tlen), Color(1, 1, 1, 0.85 if major else 0.5), 2.0 if major else 1.0)
		if major:
			_txt(Vector2(x - 18.0, top + h - 4.0), _hdg_label(di), 13, Color(1, 1, 1, 0.95), 36.0, HORIZONTAL_ALIGNMENT_CENTER)
	var tip := top + h + 2.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, tip + 9.0), Vector2(cx - 8.0, tip), Vector2(cx + 8.0, tip)]), ACCENT)
	var nbox := Rect2(cx - 34.0, tip + 11.0, 68.0, 24.0)
	draw_rect(nbox, Color(0, 0, 0, 0.55))
	draw_rect(nbox, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.5), false, 1.5)
	_txt(Vector2(cx - 34.0, tip + 29.0), "%03d°" % int(round(fposmod(_disp_heading, 360.0))), 18, ACCENT, 68.0, HORIZONTAL_ALIGNMENT_CENTER)


func _hdg_label(di: int) -> String:
	match di:
		0: return "N"
		90: return "E"
		180: return "S"
		270: return "W"
	return str(di)


# --- Bank-Bogen (Querlage) am oberen Rand des Lage-Bereichs ----------------
func _draw_bank_arc() -> void:
	var c := size * 0.5
	var R := 150.0
	for ang in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var a := deg_to_rad(-90.0 + float(ang))
		var dir := Vector2(cos(a), sin(a))
		var major: bool = (ang % 30 == 0) or ang == 0
		var tl := (12.0 if major else 7.0)
		_gline(c + dir * R, c + dir * (R - tl), Color(1, 1, 1, 0.7), 2.0 if major else 1.0)
	# fixer Referenzzeiger (oben) + beweglicher Bank-Zeiger
	var top := c + Vector2(0, -R)
	draw_colored_polygon(PackedVector2Array([top, top + Vector2(-7, -10), top + Vector2(7, -10)]), Color(1, 1, 1, 0.85))
	var pa := deg_to_rad(-90.0 + roll)
	var pd := Vector2(cos(pa), sin(pa))
	var pp := c + pd * (R - 14.0)
	var tang := pd.orthogonal()
	draw_colored_polygon(PackedVector2Array([pp, pp + pd * 12.0 + tang * 7.0, pp + pd * 12.0 - tang * 7.0]), ACCENT)


# --- Pitch-Ladder + Horizont (rollt mit der Querlage) ----------------------
func _draw_pitch_ladder() -> void:
	var c := size * 0.5
	var ppd := 5.2
	draw_set_transform(c, deg_to_rad(roll), Vector2.ONE)   # gesamte Leiter um die Rolllage kippen
	for p in range(-80, 81, 10):
		var y := float(pitch - p) * ppd
		if absf(y) > 138.0:
			continue
		if p == 0:
			_ladder_line(y, 150.0, 0, 0)             # Horizont: lange durchgehende Linie
		else:
			_ladder_line(y, 92.0, 1 if p > 0 else -1, p)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# half = halbe Breite, dir = 0 Horizont / +1 oben / -1 unten, label = Pitch-Grad
func _ladder_line(y: float, half: float, dir: int, label: int) -> void:
	var gap := 26.0
	var c := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.92) if dir >= 0 else Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.7)
	if dir == 0:
		_gline(Vector2(-half, y), Vector2(-gap, y), c, 2.0)
		_gline(Vector2(gap, y), Vector2(half, y), c, 2.0)
		return
	# gestrichelt bei negativem Pitch, durchgezogen bei positivem
	var tick := 8.0 * float(dir)   # Endhäkchen Richtung Horizont
	for sgn in [-1.0, 1.0]:
		var s: float = sgn
		var x0: float = s * gap
		var x1: float = s * half
		if dir > 0:
			_gline(Vector2(x0, y), Vector2(x1, y), c, 2.0)
		else:
			# gestrichelt
			var n := 6
			for i in n:
				var a: float = x0 + (x1 - x0) * float(i) / float(n)
				var b: float = x0 + (x1 - x0) * (float(i) + 0.55) / float(n)
				_gline(Vector2(a, y), Vector2(b, y), c, 2.0)
		_gline(Vector2(x1, y), Vector2(x1, y + tick), c, 2.0)
		_txt(Vector2(x1 - s * 4.0 + (4.0 if s > 0.0 else -34.0), y + 5.0), str(label), 12, c, 30.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_boresight(c: Vector2) -> void:
	draw_circle(c, 3.0, ACCENT)
	_gline(c + Vector2(-24, 0), c + Vector2(-9, 0), ACCENT, 2.0)
	_gline(c + Vector2(9, 0), c + Vector2(24, 0), ACCENT, 2.0)
	_gline(c + Vector2(-9, 0), c + Vector2(-9, 5), ACCENT, 2.0)
	_gline(c + Vector2(9, 0), c + Vector2(9, 5), ACCENT, 2.0)


# --- Flight-Path-Marker (Geschwindigkeitsvektor) ---------------------------
func _draw_fpm() -> void:
	if not fpm_vis:
		return
	var p := fpm_pos
	_garc(p, 7.0, Color(1, 1, 1, 0.92), 2.0)
	_gline(p + Vector2(7, 0), p + Vector2(15, 0), Color(1, 1, 1, 0.92), 2.0)
	_gline(p + Vector2(-7, 0), p + Vector2(-15, 0), Color(1, 1, 1, 0.92), 2.0)
	_gline(p + Vector2(0, -7), p + Vector2(0, -13), Color(1, 1, 1, 0.92), 2.0)


# --- Speed-Tape links (scrollend) ------------------------------------------
func _draw_speed_tape() -> void:
	var x := 28.0
	var w := 58.0
	var th := 230.0
	var cy := size.y * 0.5
	var r := Rect2(x, cy - th * 0.5, w, th)
	draw_rect(r, Color(0, 0, 0, 0.4))
	var thr_col: Color = ACCENT if throttle >= 0.0 else WARN
	draw_rect(r, Color(thr_col.r, thr_col.g, thr_col.b, 0.45), false, 1.5)
	var ppu := th / 90.0     # ~90 km/h sichtbar
	var v0 := int(round(speed_kmh))
	for v in range(v0 - 50, v0 + 51):
		if v < 0 or v % 10 != 0:
			continue
		var y := cy + float(v0 - v) * ppu
		if y < r.position.y + 2.0 or y > r.position.y + th - 2.0:
			continue
		var major: bool = v % 50 == 0
		_gline(Vector2(x + w - (16.0 if major else 9.0), y), Vector2(x + w, y), Color(1, 1, 1, 0.6), 1.0)
		if major:
			_txt(Vector2(x + 4.0, y + 4.0), str(v), 11, DIM, 40.0)
	# aktueller Wert (Pointer-Box rechts an der Tape-Mitte)
	var pts := PackedVector2Array([
		Vector2(x + w, cy), Vector2(x + w + 10.0, cy - 13.0), Vector2(x + w + 70.0, cy - 13.0),
		Vector2(x + w + 70.0, cy + 13.0), Vector2(x + w + 10.0, cy + 13.0)])
	draw_colored_polygon(pts, Color(0, 0, 0, 0.7))
	_closed_poly(pts, Color(thr_col.r, thr_col.g, thr_col.b, 0.9), 1.5)
	var spd_col: Color = WARN if stall else Color(1, 1, 1)
	_txt(Vector2(x + w + 14.0, cy + 6.0), "%d" % v0, 20, spd_col, 60.0)
	_txt(Vector2(x + 2.0, cy - th * 0.5 - 6.0), "km/h", 12, DIM, w + 4.0, HORIZONTAL_ALIGNMENT_CENTER)
	_txt(Vector2(x + 2.0, cy + th * 0.5 + 16.0), "%d m/s" % int(round(speed_ms)), 12, DIM, w + 4.0, HORIZONTAL_ALIGNMENT_CENTER)


# --- Höhen-Tape rechts (scrollend) + Steig/G -------------------------------
func _draw_alt_tape() -> void:
	var w := 64.0
	var x := size.x - w - 28.0
	var th := 230.0
	var cy := size.y * 0.5
	var r := Rect2(x, cy - th * 0.5, w, th)
	draw_rect(r, Color(0, 0, 0, 0.4))
	draw_rect(r, Color(DIM.r, DIM.g, DIM.b, 0.4), false, 1.5)
	var ppu := th / 200.0    # ~200 m sichtbar
	var a0 := int(round(altitude))
	var step := 20
	var base := int(floor(float(a0 - 100) / float(step))) * step
	for i in range(0, 12):
		var av := base + i * step
		var y := cy + float(a0 - av) * ppu
		if y < r.position.y + 2.0 or y > r.position.y + th - 2.0:
			continue
		var major: bool = av % 100 == 0
		_gline(Vector2(x, y), Vector2(x + (16.0 if major else 9.0), y), Color(1, 1, 1, 0.6), 1.0)
		if major:
			_txt(Vector2(x + 18.0, y + 4.0), str(av), 11, DIM, 44.0)
	# aktueller Wert (Pointer-Box links an der Tape-Mitte)
	var pts := PackedVector2Array([
		Vector2(x, cy), Vector2(x - 10.0, cy - 13.0), Vector2(x - 74.0, cy - 13.0),
		Vector2(x - 74.0, cy + 13.0), Vector2(x - 10.0, cy + 13.0)])
	draw_colored_polygon(pts, Color(0, 0, 0, 0.7))
	_closed_poly(pts, Color(DIM.r, DIM.g, DIM.b, 0.9), 1.5)
	_txt(Vector2(x - 70.0, cy + 6.0), "%d" % a0, 20, Color(1, 1, 1), 60.0)
	_txt(Vector2(x, cy - th * 0.5 - 6.0), "ALT m", 12, DIM, w, HORIZONTAL_ALIGNMENT_CENTER)
	# Steigrate-Pfeil + G unten
	var arrow := "▲" if climb > 0.4 else ("▼" if climb < -0.4 else "■")
	var cc: Color = ACCENT if climb > 0.4 else (Color(1, 0.6, 0.3) if climb < -0.4 else DIM)
	_txt(Vector2(x - 6.0, cy + th * 0.5 + 16.0), "%s %+.1f" % [arrow, climb], 12, cc, w + 12.0, HORIZONTAL_ALIGNMENT_CENTER)
	_txt(Vector2(x - 6.0, cy + th * 0.5 + 32.0), "%.1f g" % gforce, 12, Color(1, 0.85, 0.4) if gforce > 4.0 else DIM, w + 12.0, HORIZONTAL_ALIGNMENT_CENTER)


# --- Ziel-Lock-Klammern (pulsierend) ---------------------------------------
func _draw_target_locks() -> void:
	var pulse := 4.0 * sin(_t * 7.0)
	for tp in targets:
		var p: Vector2 = tp
		var s := 16.0 + pulse
		var c := WARN
		# 4 Eck-Klammern um das Ziel
		for cx in [-1.0, 1.0]:
			for cy in [-1.0, 1.0]:
				var corner := p + Vector2(cx * s, cy * s)
				_gline(corner, corner + Vector2(-cx * 7.0, 0), c, 2.0)
				_gline(corner, corner + Vector2(0, -cy * 7.0), c, 2.0)


# --- Großer Zielkreis (Maus-Flug) ------------------------------------------
func _draw_aim_circle() -> void:
	if aim_vis:
		_garc(aim_pos, 26.0, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.95), 2.5)
		for a in [0.0, PI * 0.5, PI, PI * 1.5]:
			var dir := Vector2(cos(a), sin(a))
			_gline(aim_pos + dir * 26.0, aim_pos + dir * 33.0, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.9), 2.0)
		draw_circle(aim_pos, 2.5, ACCENT)
	if nose_vis:
		var n := nose_pos
		draw_polyline(PackedVector2Array([
			n + Vector2(0, -9), n + Vector2(9, 0), n + Vector2(0, 9), n + Vector2(-9, 0), n + Vector2(0, -9)]),
			Color(1.0, 0.88, 0.3, 0.95), 2.0)


# --- Stall-Warnung (blinkt) ------------------------------------------------
func _draw_stall() -> void:
	if int(_t * 4.0) % 2 != 0:
		return
	var c := size * 0.5 + Vector2(0, -170.0)
	_txt(Vector2(c.x - 90.0, c.y), "⚠ STALL ⚠", 22, WARN, 180.0, HORIZONTAL_ALIGNMENT_CENTER)
