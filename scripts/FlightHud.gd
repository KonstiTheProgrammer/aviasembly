## FlightHud.gd — Primary-Flight-Display per Custom-Drawing.
## Animierte Kompass-Leiste (0..360 + N/E/S/W) oben, Speed-Box links, Höhen-/Steig-Box rechts,
## und im Maus-Flug ein großer Zielkreis (statt Glyph). Main füttert die Felder je Frame.
class_name FlightHud
extends Control

var heading := 0.0          # Kurs in Grad (0 = Nord)
var speed_kmh := 0.0
var speed_ms := 0.0
var altitude := 0.0
var climb := 0.0
var throttle := 0.0
var gforce := 1.0
var stall := false
var aoa := 0.0              # Anstellwinkel (Grad) — fürs PFD
var mode_text := ""         # aktive Sondermodi (Maus-Flug/Arcade/Invers) als Badge
var mouse_fly := false
var lock_pos := Vector2.ZERO       # erfasstes Lenkwaffen-Ziel
var lock_on := false
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
	_draw_compass()
	_draw_modes()
	_draw_speed_box()
	_draw_alt_box()
	_draw_reticle()
	_draw_lock()
	_draw_stall()


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
	# Anstellwinkel direkt unter der Speed-Box (rot ab Stall-Nähe)
	var aoa_col: Color = Color(1, 0.45, 0.3) if stall else (Color(1, 0.8, 0.35) if aoa > 11.0 else DIM)
	draw_string(_font, Vector2(bx + 12.0, by + 48.0), "AoA  %d°" % int(round(aoa)),
		HORIZONTAL_ALIGNMENT_LEFT, 124.0, 13, aoa_col)
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
	var arrow := "▲" if climb > 0.4 else ("▼" if climb < -0.4 else "■")
	var cc: Color = ACCENT if climb > 0.4 else (Color(1, 0.6, 0.3) if climb < -0.4 else DIM)
	draw_string(_font, Vector2(r.position.x + 12.0, r.position.y + 53.0), "m  %s %+.1f m/s" % [arrow, climb],
		HORIZONTAL_ALIGNMENT_LEFT, 124.0, 12, cc)
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
	else:
		# statisches kleines Fadenkreuz mittig
		var c := size * 0.5
		draw_arc(c, 8.0, 0.0, TAU, 32, Color(1, 1, 1, 0.6), 2.0, true)
		draw_line(c + Vector2(-14, 0), c + Vector2(-9, 0), Color(1, 1, 1, 0.6), 2.0)
		draw_line(c + Vector2(9, 0), c + Vector2(14, 0), Color(1, 1, 1, 0.6), 2.0)
		draw_line(c + Vector2(0, -14), c + Vector2(0, -9), Color(1, 1, 1, 0.6), 2.0)
		draw_circle(c, 1.5, Color(1, 1, 1, 0.7))


# --- Lenkwaffen-Lock: pulsierende Eck-Klammern auf dem erfassten Ziel -------
func _draw_lock() -> void:
	if not lock_on:
		return
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.012)
	var c := Color(1.0, 0.35, 0.3, 0.55 + 0.4 * pulse)
	var s := 16.0
	var arm := 7.0
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var cn := lock_pos + Vector2(sx * s, sy * s)
			draw_line(cn, cn - Vector2(sx * arm, 0), c, 2.0)
			draw_line(cn, cn - Vector2(0, sy * arm), c, 2.0)
	draw_string(_font, lock_pos + Vector2(-20.0, -s - 5.0), "LOCK",
		HORIZONTAL_ALIGNMENT_CENTER, 40.0, 11, c)


# --- Modus-Badge unter dem Kompass (nur aktive Sondermodi) ------------------
func _draw_modes() -> void:
	if mode_text == "":
		return
	var fw: float = _font.get_string_size(mode_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x + 22.0
	var y := 84.0
	var r := Rect2(size.x * 0.5 - fw * 0.5, y, fw, 22.0)
	draw_rect(r, Color(0, 0, 0, 0.5))
	draw_rect(r, Color(0.5, 0.85, 1.0, 0.55), false, 1.5)
	draw_string(_font, Vector2(r.position.x, y + 16.0), mode_text,
		HORIZONTAL_ALIGNMENT_CENTER, fw, 14, Color(0.6, 0.95, 1.0))


# --- Prominente Stall-Warnung (pulsierender Rahmen + Banner) ----------------
func _draw_stall() -> void:
	if not stall or speed_ms < 4.0:
		return
	var pulse := 0.5 + 0.5 * sin(float(Time.get_ticks_msec()) * 0.013)
	# roter Rahmen am Bildrand
	var edge := Color(1.0, 0.22, 0.18, 0.18 + 0.32 * pulse)
	var t := 10.0
	draw_rect(Rect2(0, 0, size.x, t), edge)
	draw_rect(Rect2(0, size.y - t, size.x, t), edge)
	draw_rect(Rect2(0, 0, t, size.y), edge)
	draw_rect(Rect2(size.x - t, 0, t, size.y), edge)
	# STALL-Banner über der Bildmitte
	var bw := 200.0
	var bx := size.x * 0.5 - bw * 0.5
	var by := size.y * 0.30
	draw_string(_font, Vector2(bx, by), "STALL",
		HORIZONTAL_ALIGNMENT_CENTER, bw, 30, Color(1.0, 0.3, 0.24, 0.65 + 0.35 * pulse))
