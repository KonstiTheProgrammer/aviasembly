## FlightHud.gd — Primary-Flight-Display per Custom-Drawing.
## Animierte Kompass-Leiste (0..360 + N/E/S/W) oben, Speed-Box links, Höhen-/Steig-Box rechts,
## und im Maus-Flug ein großer Zielkreis (statt Glyph). Main füttert die Felder je Frame.
class_name FlightHud
extends Control

var pitch := 0.0            # Nicklage in Grad (+ = Nase über Horizont)
var roll := 0.0             # Querlage in Grad (+ = rechte Tragfläche unten)
var heading := 0.0          # Kurs in Grad (0 = Nord)
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

var _disp_heading := 0.0    # geglätteter Kurs (für sanftes Scrollen)
var _font: Font
const ACCENT := Color(0.35, 1.0, 0.5)        # HUD-Grün
const DIM := Color(0.75, 0.9, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	set_process(true)


func _process(delta: float) -> void:
	# Kurs sanft nachführen (kürzester Weg über die 0/360-Naht) -> flüssiges Scrollen.
	_disp_heading += wrapf(heading - _disp_heading, -180.0, 180.0) * clampf(delta * 10.0, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	_draw_horizon()
	_draw_compass()
	_draw_speed_box()
	_draw_alt_box()
	_draw_reticle()


# --- Künstlicher Horizont: Pitch-Leiter (rollt/kippt mit) + Bank-Bogen + feste Waterline ---
func _draw_horizon() -> void:
	var c := size * 0.5
	var ppd := 5.6                       # Pixel pro Grad Nicklage
	var rot := -deg_to_rad(roll)         # Horizont kippt gegen die Querlage
	var hl := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.9)
	var hl_dim := Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55)
	# --- Leiter im gedrehten Rahmen um die Bildmitte ---
	draw_set_transform(c, rot, Vector2.ONE)
	var hy := pitch * ppd                 # Horizontlinie (0°)
	if absf(hy) < 220.0:
		draw_line(Vector2(-270, hy), Vector2(-40, hy), hl, 2.0, true)
		draw_line(Vector2(40, hy), Vector2(270, hy), hl, 2.0, true)
	for a in [-60, -50, -40, -30, -20, -10, 10, 20, 30, 40, 50, 60]:
		var ry := (pitch - float(a)) * ppd
		if absf(ry) > 165.0:
			continue
		var half := 64.0 if absi(a) % 30 == 0 else 42.0
		var gap := 26.0
		var down := 7.0 if a > 0 else -7.0      # Steig-Sprossen weisen nach unten, Sturz nach oben
		if a > 0:
			draw_line(Vector2(-half, ry), Vector2(-gap, ry), hl_dim, 1.5, true)
			draw_line(Vector2(-gap, ry), Vector2(-gap, ry + down), hl_dim, 1.5, true)
			draw_line(Vector2(half, ry), Vector2(gap, ry), hl_dim, 1.5, true)
			draw_line(Vector2(gap, ry), Vector2(gap, ry + down), hl_dim, 1.5, true)
		else:
			_dash(Vector2(-half, ry), Vector2(-gap, ry), hl_dim)
			draw_line(Vector2(-gap, ry), Vector2(-gap, ry + down), hl_dim, 1.5, true)
			_dash(Vector2(gap, ry), Vector2(half, ry), hl_dim)
			draw_line(Vector2(gap, ry), Vector2(gap, ry + down), hl_dim, 1.5, true)
		if absi(a) % 30 == 0:
			var lab := str(absf(a))
			draw_string(_font, Vector2(-half - 30.0, ry + 5.0), lab, HORIZONTAL_ALIGNMENT_RIGHT, 26.0, 12, hl_dim)
			draw_string(_font, Vector2(half + 4.0, ry + 5.0), lab, HORIZONTAL_ALIGNMENT_LEFT, 26.0, 12, hl_dim)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# --- Bank-Bogen oben (feste Skala) + beweglicher Zeiger ---
	var R := 156.0
	for b in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var ang := deg_to_rad(-90.0 + float(b))
		var dir := Vector2(cos(ang), sin(ang))
		var tl := 11.0 if (b == 0 or absf(b) == 30 or absf(b) == 60) else 6.0
		draw_line(c + dir * R, c + dir * (R - tl), hl_dim, 1.5, true)
	# Zeiger (Dreieck) an aktueller Querlage
	var pang := deg_to_rad(-90.0 + roll)
	var pd := Vector2(cos(pang), sin(pang))
	var pp := c + pd * (R - 12.0)
	var perp := Vector2(-pd.y, pd.x)
	draw_colored_polygon(PackedVector2Array([pp, pp - pd * 13.0 + perp * 7.0, pp - pd * 13.0 - perp * 7.0]), ACCENT)
	# --- Feste Waterline (Flugzeug-Referenz) ---
	draw_line(c + Vector2(-62, 0), c + Vector2(-26, 0), Color(1, 0.9, 0.3, 0.95), 2.5, true)
	draw_line(c + Vector2(-26, 0), c + Vector2(-26, 9), Color(1, 0.9, 0.3, 0.95), 2.5, true)
	draw_line(c + Vector2(62, 0), c + Vector2(26, 0), Color(1, 0.9, 0.3, 0.95), 2.5, true)
	draw_line(c + Vector2(26, 0), c + Vector2(26, 9), Color(1, 0.9, 0.3, 0.95), 2.5, true)
	draw_circle(c, 2.5, Color(1, 0.9, 0.3, 0.95))


func _dash(a: Vector2, b: Vector2, col: Color) -> void:
	var d := b - a
	var n := maxi(1, int(d.length() / 7.0))
	for i in n:
		if i % 2 == 0:
			draw_line(a + d * (float(i) / n), a + d * (float(i + 1) / n), col, 1.5, true)


# --- Kompass-Leiste oben (scrollt mit dem Kurs) -----------------------------
func _draw_compass() -> void:
	var w := 560.0
	var h := 34.0
	var cx := size.x * 0.5
	var top := 16.0
	var bg := Rect2(cx - w * 0.5, top, w, h)
	draw_rect(bg, Color(0, 0, 0, 0.5))
	draw_rect(bg, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35), false, 1.5)
	var ppd := w / 120.0          # 120° sichtbar
	var span := 62
	for off in range(-span, span + 1):
		var deg := _disp_heading + float(off)
		var x := cx + float(off) * ppd
		if x < bg.position.x + 2.0 or x > bg.position.x + w - 2.0:
			continue
		var di := int(round(fposmod(deg, 360.0)))
		if di % 10 != 0:
			continue
		var major: bool = di % 30 == 0
		var tlen := (h * 0.5) if major else (h * 0.28)
		draw_line(Vector2(x, top), Vector2(x, top + tlen), Color(1, 1, 1, 0.85 if major else 0.5), 2.0 if major else 1.0)
		if major:
			draw_string(_font, Vector2(x - 18.0, top + h - 4.0), _hdg_label(di),
				HORIZONTAL_ALIGNMENT_CENTER, 36.0, 13, Color(1, 1, 1, 0.95))
	# Mittelzeiger (Dreieck nach unten) + exakte Kurszahl
	var tip := top + h + 2.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, tip + 9.0), Vector2(cx - 8.0, tip), Vector2(cx + 8.0, tip)]), ACCENT)
	var num := "%03d°" % int(round(fposmod(_disp_heading, 360.0)))
	var nbox := Rect2(cx - 34.0, tip + 11.0, 68.0, 24.0)
	draw_rect(nbox, Color(0, 0, 0, 0.55))
	draw_rect(nbox, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.5), false, 1.5)
	draw_string(_font, Vector2(cx - 34.0, tip + 29.0), num, HORIZONTAL_ALIGNMENT_CENTER, 68.0, 18, ACCENT)


func _hdg_label(di: int) -> String:
	match di:
		0: return "N"
		90: return "E"
		180: return "S"
		270: return "W"
	return str(di)


# --- Speed-Box links (mittig) ----------------------------------------------
func _draw_speed_box() -> void:
	var bx := 22.0
	var by := size.y * 0.5
	var r := Rect2(bx, by - 30.0, 132.0, 60.0)
	draw_rect(r, Color(0, 0, 0, 0.5))
	var thr_col: Color = ACCENT if throttle >= 0.0 else Color(1, 0.5, 0.3)
	if throttle > 1.0:
		thr_col = Color(1.0, 0.42, 0.12)        # Nachbrenner: heißes Orange-Rot
	draw_rect(r, Color(thr_col.r, thr_col.g, thr_col.b, 0.5), false, 2.0)
	var spd_col: Color = Color(1, 0.45, 0.3) if stall else Color(1, 1, 1)
	draw_string(_font, Vector2(bx + 12.0, by + 4.0), "%d" % int(round(speed_kmh)),
		HORIZONTAL_ALIGNMENT_LEFT, 110.0, 30, spd_col)
	draw_string(_font, Vector2(bx + 12.0, by + 23.0), "km/h  ·  %d m/s" % int(round(speed_ms)),
		HORIZONTAL_ALIGNMENT_LEFT, 124.0, 12, DIM)
	# Schub-/Bremsbalken am linken Rand der Box (über 100 % = Nachbrenner-Zone)
	var bar := Rect2(bx - 8.0, by - 30.0, 5.0, 60.0)
	draw_rect(bar, Color(0, 0, 0, 0.5))
	if throttle >= 0.0:
		var norm := clampf(throttle, 0.0, 1.0)
		var fill_h := norm * 30.0
		draw_rect(Rect2(bx - 8.0, by - fill_h, 5.0, fill_h), thr_col)
		if throttle > 1.0:
			# Nachbrenner: pulsierender heller Kopf oben am vollen Balken
			var pulse := 0.6 + 0.4 * sin(float(Time.get_ticks_msec()) * 0.02)
			draw_rect(Rect2(bx - 8.0, by - 30.0, 5.0, 5.0), Color(1.0, 0.9, 0.4, pulse))
	else:
		var fill_n := absf(throttle) * 30.0
		draw_rect(Rect2(bx - 8.0, by, 5.0, fill_n), thr_col)


# --- Höhen-/Steig-Box rechts (mittig) --------------------------------------
func _draw_alt_box() -> void:
	var r := Rect2(size.x - 154.0, size.y * 0.5 - 30.0, 132.0, 60.0)
	draw_rect(r, Color(0, 0, 0, 0.5))
	draw_rect(r, Color(DIM.r, DIM.g, DIM.b, 0.45), false, 2.0)
	draw_string(_font, Vector2(r.position.x + 12.0, r.position.y + 34.0), "%d" % int(round(altitude)),
		HORIZONTAL_ALIGNMENT_LEFT, 110.0, 30, Color(1, 1, 1))
	var cc: Color = ACCENT if climb > 0.4 else (Color(1, 0.6, 0.3) if climb < -0.4 else DIM)
	var ax := r.position.x + 17.0
	var ay := r.position.y + 49.0
	if climb > 0.4:
		draw_colored_polygon(PackedVector2Array([Vector2(ax, ay - 5), Vector2(ax - 5, ay + 4), Vector2(ax + 5, ay + 4)]), cc)
	elif climb < -0.4:
		draw_colored_polygon(PackedVector2Array([Vector2(ax, ay + 5), Vector2(ax - 5, ay - 4), Vector2(ax + 5, ay - 4)]), cc)
	else:
		draw_rect(Rect2(ax - 4.0, ay - 4.0, 8.0, 8.0), cc, false, 1.5)
	draw_string(_font, Vector2(r.position.x + 30.0, r.position.y + 53.0), "m    %+.1f m/s" % climb,
		HORIZONTAL_ALIGNMENT_LEFT, 110.0, 12, cc)
	# G-Kraft kleiner darunter
	draw_string(_font, Vector2(r.position.x, r.position.y + 76.0), "%.1f g" % gforce,
		HORIZONTAL_ALIGNMENT_RIGHT, 130.0, 13, Color(1, 0.85, 0.4) if gforce > 4.0 else DIM)


# --- Zielkreis / Fadenkreuz ------------------------------------------------
func _draw_reticle() -> void:
	if mouse_fly:
		if aim_vis:
			# NUR ein Kreis (kein Fadenkreuz): klein, dünn, durchsichtig, grau
			draw_arc(aim_pos, 18.0, 0.0, TAU, 56, Color(0.82, 0.84, 0.88, 0.5), 1.0, true)
		if nose_vis:
			# kleine Raute = aktuelle Nasenrichtung
			var n := nose_pos
			draw_polyline(PackedVector2Array([
				n + Vector2(0, -9), n + Vector2(9, 0), n + Vector2(0, 9), n + Vector2(-9, 0), n + Vector2(0, -9)]),
				Color(1.0, 0.88, 0.3, 0.95), 2.0)
	# Sonst dient die feste Waterline des künstlichen Horizonts als Referenz (kein extra Fadenkreuz).
