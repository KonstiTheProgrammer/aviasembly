extends Control
class_name FlightCheckPanel
## Grafische Flug-Info fürs Hangar-Panel: zeigt anschaulich, WO der Schwerpunkt liegt
## (relativ zum Auftriebspunkt) und WIE das Flugzeug fliegt (Stabilität, Schub/Gewicht,
## Flächenlast, Max-G) plus ein Verdict. Wird von Main per set_data() gefüttert.

var _d: Dictionary = {}
var _verdict := ""
var _vcol := Color(0.6, 1.0, 0.6)
var _font: Font

const C_COM := Color(1.0, 0.85, 0.15)     # Schwerpunkt (gelb)
const C_COL := Color(0.25, 0.72, 1.0)     # Auftriebspunkt (blau)
const C_GOOD := Color(0.40, 0.85, 0.45)
const C_WARN := Color(1.0, 0.82, 0.30)
const C_BAD := Color(0.95, 0.40, 0.35)
const C_DIM := Color(0.60, 0.63, 0.70)


func _ready() -> void:
	_font = get_theme_font("font", "Label")
	custom_minimum_size = Vector2(0, 286)


func set_data(stats: Dictionary, verdict: String, vcol: Color) -> void:
	_d = stats
	_verdict = verdict
	_vcol = vcol
	queue_redraw()


func _txt(s: String, pos: Vector2, col: Color, sz := 12, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	if _font == null:
		_font = get_theme_font("font", "Label")
	draw_string_outline(_font, pos, s, align, w, sz, 3, Color(0, 0, 0, 0.85))
	draw_string(_font, pos, s, align, w, sz, col)


# Ein beschrifteter Wert-Balken; gibt das nächste y zurück.
func _bar(y: float, label: String, frac: float, val_txt: String, col: Color) -> float:
	var w := size.x
	var bx := 96.0
	var bw := maxf(w - bx - 4.0, 20.0)
	_txt(label, Vector2(4, y + 12), Color(0.82, 0.88, 0.96), 12)
	draw_rect(Rect2(bx, y + 2, bw, 13), Color(1, 1, 1, 0.10), true)
	draw_rect(Rect2(bx, y + 2, bw * clampf(frac, 0.0, 1.0), 13), col, true)
	_txt(val_txt, Vector2(bx + 5, y + 12), Color(1, 1, 1), 11)
	return y + 21.0


func set_font(f: Font) -> void:
	if f != null:
		_font = f
		queue_redraw()


func _draw() -> void:
	if _font == null:
		_font = get_theme_font("font", "Label")
	var w := size.x
	if _d.is_empty():
		_txt("Bau etwas zusammen …", Vector2(4, 22), C_DIM, 13)
		return
	var y := 2.0

	# ---------- Balance: Schwerpunkt <-> Auftrieb ----------
	_txt("BALANCE", Vector2(4, y + 12), Color(0.62, 0.78, 0.98), 12)
	y += 24.0
	var ty := y + 14.0
	var lx := 16.0
	var rx := w - 16.0
	draw_line(Vector2(lx, ty), Vector2(rx, ty), Color(1, 1, 1, 0.22), 2.0)
	_txt("Nase", Vector2(lx - 4, ty + 24), C_DIM, 10)
	_txt("Heck", Vector2(rx, ty + 24), C_DIM, 10, HORIZONTAL_ALIGNMENT_RIGHT)

	var col_valid: bool = _d.get("col_valid", false)
	var comz: float = _d["com"].z
	var colz: float = (_d["col"].z if col_valid else comz)
	var zlo: float = _d.get("z_min", comz - 2.0)
	var zhi: float = _d.get("z_max", comz + 2.0)
	if zlo > zhi:
		zlo = comz - 2.0
		zhi = comz + 2.0
	zlo = minf(zlo, minf(comz, colz))
	zhi = maxf(zhi, maxf(comz, colz))
	var pad := maxf((zhi - zlo) * 0.18, 0.6)
	zlo -= pad
	zhi += pad
	var rng := maxf(zhi - zlo, 0.001)
	var x_com := lx + (rx - lx) * (comz - zlo) / rng
	var x_col := lx + (rx - lx) * (colz - zlo) / rng

	# Stabilitäts-Segment zwischen Schwerpunkt und Auftrieb
	if col_valid:
		var stable := colz > comz
		draw_line(Vector2(x_com, ty), Vector2(x_col, ty),
			(C_GOOD if stable else C_BAD), 5.0)

	# Auftriebspunkt (blau) + Pfeil nach oben (Auftrieb)
	if col_valid:
		draw_circle(Vector2(x_col, ty), 7.0, C_COL)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x_col, ty - 17), Vector2(x_col - 5, ty - 9), Vector2(x_col + 5, ty - 9)]), C_COL)
	# Schwerpunkt (gelb) + Gewichts-Dreieck nach unten
	draw_circle(Vector2(x_com, ty), 7.0, C_COM)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x_com - 5, ty + 9), Vector2(x_com + 5, ty + 9), Vector2(x_com, ty + 17)]), C_COM)

	# Legende
	_txt("Schwerpunkt", Vector2(lx - 4, ty + 38), C_COM, 10)
	if col_valid:
		_txt("Auftrieb", Vector2(rx, ty + 38), C_COL, 10, HORIZONTAL_ALIGNMENT_RIGHT)
	y = ty + 48.0

	# ---------- Stabilität ----------
	var stab_txt := "keine Flügel"
	var stab_frac := 0.0
	var stab_col := C_DIM
	if col_valid:
		var margin := colz - comz                       # >0 = stabil
		stab_frac = clampf(0.5 + (margin / maxf(zhi - zlo, 0.5)) * 2.6, 0.03, 1.0)
		if margin < -0.05:
			stab_txt = "instabil / kippelig"
			stab_col = C_BAD
		elif margin < 0.08:
			stab_txt = "agil / neutral"
			stab_col = C_WARN
		elif margin < 0.32:
			stab_txt = "stabil"
			stab_col = C_GOOD
		else:
			stab_txt = "sehr stabil (träge)"
			stab_col = C_COL
	y = _bar(y, "Stabilität", stab_frac, stab_txt, stab_col)

	# ---------- Schub / Gewicht ----------
	var tw: float = _d.get("tw", 0.0)
	var twc := (C_BAD if tw < 0.25 else (C_WARN if tw < 0.5 else C_GOOD))
	y = _bar(y, "Schub/Gew.", clampf(tw / 1.2, 0.0, 1.0), "%.2f" % tw, twc)

	# ---------- Flächenlast (agil <-> träge) ----------
	var area: float = _d.get("area", 0.0)
	var mass: float = _d.get("mass", 0.0)
	if area > 0.01:
		var wl := mass / area
		var wlc := (C_GOOD if wl < 45.0 else (C_WARN if wl < 90.0 else C_BAD))
		var wlt := ("agil" if wl < 45.0 else ("mittel" if wl < 90.0 else "träge"))
		y = _bar(y, "Flächenlast", clampf(wl / 140.0, 0.05, 1.0), "%d kg/m²  (%s)" % [int(wl), wlt], wlc)
	else:
		y = _bar(y, "Flächenlast", 0.0, "—", C_DIM)

	# ---------- Max-G ----------
	if _d.get("has_wings", false):
		var mg: float = _d.get("max_g", 0.0)
		var mgc := (C_BAD if mg < 3.0 else (C_WARN if mg < 6.0 else C_GOOD))
		y = _bar(y, "Max-G", clampf(mg / 9.0, 0.0, 1.0), "%.1f g" % mg, mgc)

	# ---------- Verdict ----------
	y += 6.0
	draw_circle(Vector2(10, y + 8), 5.0, _vcol)
	if _font == null:
		_font = get_theme_font("font", "Label")
	draw_multiline_string_outline(_font, Vector2(20, y + 12), _verdict,
		HORIZONTAL_ALIGNMENT_LEFT, maxf(w - 24.0, 40.0), 12, 4, 3, Color(0, 0, 0, 0.85))
	draw_multiline_string(_font, Vector2(20, y + 12), _verdict,
		HORIZONTAL_ALIGNMENT_LEFT, maxf(w - 24.0, 40.0), 12, 4, _vcol)
