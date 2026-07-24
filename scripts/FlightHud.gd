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
var gun_pos := Vector2.ZERO        # ballistischer Pipper (echter Treffpunkt der Kanonen)
var gun_vis := false

var _disp_heading := 0.0    # geglätteter Kurs (für sanftes Scrollen)
var _font: Font
const ACCENT := Color(0.35, 1.0, 0.5)        # HUD-Grün
const DIM := Color(0.75, 0.9, 1.0)
# --- Design-Sprache (Mockup): dunkle Panels, Cyan-Akzente, Gruen=positiv, Gold=Warn/Badge ---
const P_BG := Color(0.075, 0.095, 0.135, 0.88)
const P_BORDER := Color(0.72, 0.80, 0.92, 0.30)
const CYAN := Color(0.36, 0.78, 0.91)
const GREEN := Color(0.38, 0.92, 0.52)
const GOLD := Color(0.97, 0.80, 0.28)
const TXT := Color(0.94, 0.96, 1.0)
const MUT := Color(0.62, 0.70, 0.82)
var gear_text := "—"
var flaps_text := "AUS"
var steer_text := "normal"
var assist_text := "AN"
var mousefly_text := "AN"
var wings_text := "ok"
var badge_text := "SANDBOX"
var nav_text := ""
var ammo_text := ""
var weapon_groups: Array = []   # [{label, count}] — count -1 = unbegrenzt
var weapon_sel := -1            # ausgewählte Gruppe (Index)


func _panel_sb(radius: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = P_BG
	sb.set_corner_radius_all(int(radius))
	sb.border_color = P_BORDER
	sb.set_border_width_all(2)
	return sb


func _txt_r(pos: Vector2, w: float, t: String, fs: int, col: Color) -> void:
	draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_RIGHT, w, fs, col)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = preload("res://fonts/TitilliumWeb-SemiBold.ttf")   # crisp statt Default-Font
	if _font == null:
		_font = ThemeDB.fallback_font
	set_process(true)


func _process(delta: float) -> void:
	# Kurs sanft nachführen (kürzester Weg über die 0/360-Naht) -> flüssiges Scrollen.
	_disp_heading += wrapf(heading - _disp_heading, -180.0, 180.0) * clampf(delta * 10.0, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	_draw_status_panel()
	_draw_compass()
	_draw_modes()
	_draw_speed_box()
	_draw_alt_box()
	_draw_systems_panel()
	_draw_weapon_bar()
	_draw_reticle()
	_draw_lock()
	_draw_stall()
	_draw_minimap()


# --- FLUG-STATUS-Panel oben links (Mockup: Icons, rechtsbuendige Werte, Gruppen) ---
func _draw_status_panel() -> void:
	var u := size.y / 1080.0
	var w := 340.0 * u
	var rowh := 30.0 * u
	var rows: Array = [
		["Schub", "%d%%" % int(round(throttle * 100.0)), TXT],
		["Anstellwinkel", "%d°" % int(round(aoa)), TXT],
		["G-Kraft", "%.1f g" % gforce, (GOLD if gforce > 4.0 else TXT)],
		null,
		["Fahrwerk (G)", gear_text, (GREEN if gear_text.begins_with("ausgef") else GOLD)],
		["Klappen (F)", flaps_text, (TXT if flaps_text == "AUS" else CYAN)],
		["Steuerung (I)", steer_text, (TXT if steer_text == "normal" else GOLD)],
		null,
		["Assist (T)", assist_text, (GREEN if assist_text.begins_with("AN") else MUT)],
		["Maus-Flug (N)", mousefly_text, (GREEN if mousefly_text.begins_with("AN") else MUT)],
	]
	if wings_text != "ok":
		rows.append(["Flügel", wings_text, GOLD])
	if ammo_text != "":
		rows.append(["Munition", ammo_text, TXT])
	var head := 44.0 * u
	var pad := 14.0 * u
	var h := head + pad
	for r in rows:
		h += (10.0 * u) if r == null else rowh
	var rect := Rect2(Vector2(24.0 * u, 20.0 * u), Vector2(w, h))
	draw_style_box(_panel_sb(12.0 * u), rect)
	# Header: Titel cyan + gruener Punkt + Badge gold rechts
	var fs_h := int(19.0 * u)
	draw_string(_font, rect.position + Vector2(16.0 * u, 30.0 * u), "FLUG-STATUS",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_h, CYAN)
	draw_circle(rect.position + Vector2(w - 16.0 * u - _font.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(15.0 * u)).x - 16.0 * u, 24.0 * u), 5.0 * u, GREEN)
	_txt_r(rect.position + Vector2(0, 30.0 * u), w - 16.0 * u, badge_text, int(15.0 * u), GOLD)
	draw_line(rect.position + Vector2(12.0 * u, head), rect.position + Vector2(w - 12.0 * u, head), P_BORDER, 1.0)
	var y := rect.position.y + head + 22.0 * u
	for r in rows:
		if r == null:
			draw_line(Vector2(rect.position.x + 12.0 * u, y - 14.0 * u),
				Vector2(rect.position.x + w - 12.0 * u, y - 14.0 * u), Color(P_BORDER.r, P_BORDER.g, P_BORDER.b, 0.16), 1.0)
			y += 10.0 * u
			continue
		# kleines Icon: Raute
		var ic := Vector2(rect.position.x + 22.0 * u, y - 6.0 * u)
		draw_colored_polygon(PackedVector2Array([ic + Vector2(0, -4.5 * u), ic + Vector2(4.5 * u, 0),
			ic + Vector2(0, 4.5 * u), ic + Vector2(-4.5 * u, 0)]), Color(MUT.r, MUT.g, MUT.b, 0.75))
		draw_string(_font, Vector2(rect.position.x + 38.0 * u, y), String(r[0]),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(16.0 * u), MUT)
		_txt_r(Vector2(rect.position.x, y), w - 16.0 * u, String(r[1]), int(16.0 * u), r[2])
		y += rowh


# --- Systeme-Panel links (ueber der GESCHWINDIGKEIT-Box): Schub/Klappen/Fahrwerk ---
# (Auf Wunsch von der Bildschirmmitte an die Seite verlegt — unten Mitte sitzt die Waffenwahl.)
func _draw_systems_panel() -> void:
	var u := size.y / 1080.0
	var w := 230.0 * u
	var h := 148.0 * u
	var rect := Rect2(Vector2(40.0 * u, size.y - 210.0 * u - 46.0 * u - 12.0 * u - h), Vector2(w, h))
	draw_style_box(_panel_sb(12.0 * u), rect)
	var fs_l := int(14.0 * u)
	var fs_v := int(16.0 * u)
	var x0 := rect.position.x + 16.0 * u
	var wr := w - 16.0 * u
	# SCHUB (Wert rechts) + Fortschrittsbalken (Nachbrenner orange, Bremse rot)
	var y := rect.position.y + 30.0 * u
	draw_string(_font, Vector2(x0, y), "SCHUB", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_l, MUT)
	var thr_col: Color = CYAN if throttle <= 1.0 else Color(1.0, 0.55, 0.2)
	if throttle < 0.0:
		thr_col = Color(1.0, 0.45, 0.3)
	_txt_r(Vector2(rect.position.x, y), wr, "%d%%" % int(round(throttle * 100.0)), fs_v, TXT)
	var bar := Rect2(Vector2(x0, y + 12.0 * u), Vector2(w - 32.0 * u, 7.0 * u))
	draw_rect(bar, Color(1, 1, 1, 0.12))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(absf(throttle), 0.0, 1.0), bar.size.y)), thr_col)
	draw_line(rect.position + Vector2(12.0 * u, 66.0 * u), rect.position + Vector2(w - 12.0 * u, 66.0 * u),
		Color(P_BORDER.r, P_BORDER.g, P_BORDER.b, 0.16), 1.0)
	# KLAPPEN
	y = rect.position.y + 94.0 * u
	draw_string(_font, Vector2(x0, y), "KLAPPEN", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_l, MUT)
	_txt_r(rect.position + Vector2(0, 94.0 * u), wr, flaps_text, fs_v, TXT if flaps_text == "AUS" else CYAN)
	# FAHRWERK
	y = rect.position.y + 126.0 * u
	draw_string(_font, Vector2(x0, y), "FAHRWERK", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_l, MUT)
	var gt := gear_text.to_upper()
	_txt_r(rect.position + Vector2(0, 126.0 * u), wr, gt, fs_v, GREEN if gt.begins_with("AUSGEF") else GOLD)


# --- Waffenwahl unten Mitte: eine Pille je Gruppe, [1-4] direkt, V zyklisch ---
func _draw_weapon_bar() -> void:
	if weapon_groups.is_empty():
		return
	var u := size.y / 1080.0
	var h := 54.0 * u
	var fs := int(16.0 * u)
	var fs_k := int(13.0 * u)
	var fs_c := int(15.0 * u)
	var pad := 16.0 * u
	var gap := 10.0 * u
	var key_w := 22.0 * u
	# Breiten vorab messen -> Gesamtleiste zentrieren
	var widths: Array = []
	var total := 0.0
	for i in weapon_groups.size():
		var g: Dictionary = weapon_groups[i]
		var cnt: int = int(g.get("count", -1))
		var ct := "∞" if cnt < 0 else "× %d" % cnt
		var lw: float = _font.get_string_size(String(g.get("label", "?")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		var cw: float = _font.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_c).x
		var pw: float = pad + key_w + 10.0 * u + lw + 10.0 * u + cw + pad
		widths.append(pw)
		total += pw
	total += gap * float(weapon_groups.size() - 1)
	var x := size.x * 0.5 - total * 0.5
	var yb := size.y - h - 104.0 * u
	for i in weapon_groups.size():
		var g: Dictionary = weapon_groups[i]
		var pw: float = widths[i]
		var rect := Rect2(Vector2(x, yb), Vector2(pw, h))
		var sel := i == weapon_sel
		var sb := _panel_sb(12.0 * u)
		if sel:
			sb.bg_color = Color(0.10, 0.15, 0.21, 0.92)
			sb.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.85)
		draw_style_box(sb, rect)
		var cnt: int = int(g.get("count", -1))
		var empty := cnt == 0
		# Tasten-Kaestchen [1..4]
		var kb := Rect2(rect.position + Vector2(pad, h * 0.5 - 11.0 * u), Vector2(key_w, 22.0 * u))
		draw_rect(kb, Color(1, 1, 1, 0.10))
		draw_rect(kb, Color(1, 1, 1, 0.22), false, 1.0)
		draw_string(_font, Vector2(kb.position.x, kb.position.y + 16.0 * u), str(i + 1),
			HORIZONTAL_ALIGNMENT_CENTER, key_w, fs_k, MUT)
		# Label + Restmunition
		var lcol: Color = CYAN if sel else TXT
		var ccol := MUT
		if empty:
			lcol = Color(1.0, 0.45, 0.3, 0.75)
			ccol = Color(1.0, 0.45, 0.3, 0.75)
		var lx := rect.position.x + pad + key_w + 10.0 * u
		draw_string(_font, Vector2(lx, yb + h * 0.5 + 6.0 * u), String(g.get("label", "?")),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, lcol)
		var ct := "∞" if cnt < 0 else "× %d" % cnt
		_txt_r(Vector2(rect.position.x, yb + h * 0.5 + 6.0 * u), pw - pad, ct, fs_c, ccol)
		x += pw + gap


# --- Kompass-Leiste oben (scrollt mit dem Kurs) -----------------------------


func _draw_compass() -> void:
	var w := 560.0
	var h := 34.0
	var cx := size.x * 0.5
	var top := 16.0
	var u := size.y / 1080.0
	w *= u
	h = 40.0 * u
	top = 18.0 * u
	var bg := Rect2(cx - w * 0.5, top, w, h)
	draw_style_box(_panel_sb(h * 0.5), bg)
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
			var lab := _hdg_label(di)
			var lcol := CYAN if lab == "N" else Color(1, 1, 1, 0.95)
			draw_string(_font, Vector2(x - 18.0, top + h - 6.0), lab,
				HORIZONTAL_ALIGNMENT_CENTER, 36.0, int(15.0 * (size.y / 1080.0)), lcol)
	# Mittelzeiger (Dreieck nach unten) + exakte Kurszahl
	var tip := top + h + 2.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, tip + 8.0 * u), Vector2(cx - 7.0 * u, tip), Vector2(cx + 7.0 * u, tip)]), CYAN)
	var num := "%03d°" % int(round(fposmod(_disp_heading, 360.0)))
	var nbox := Rect2(cx - 44.0 * u, tip + 10.0 * u, 88.0 * u, 30.0 * u)
	draw_style_box(_panel_sb(8.0 * u), nbox)
	draw_string(_font, Vector2(nbox.position.x, nbox.position.y + 22.0 * u), num,
		HORIZONTAL_ALIGNMENT_CENTER, nbox.size.x, int(19.0 * u), CYAN)
	# NAV-Pille: naechster Flugplatz ("◆ HEIMAT 0.1 km")
	if nav_text != "":
		var fs_n := int(16.0 * u)
		var tw := _font.get_string_size(nav_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_n).x
		var pw := tw + 44.0 * u
		var pbox := Rect2(cx - pw * 0.5, nbox.end.y + 8.0 * u, pw, 30.0 * u)
		draw_style_box(_panel_sb(8.0 * u), pbox)
		var dc := pbox.position + Vector2(18.0 * u, 15.0 * u)
		draw_colored_polygon(PackedVector2Array([dc + Vector2(0, -6.0 * u), dc + Vector2(6.0 * u, 0),
			dc + Vector2(0, 6.0 * u), dc + Vector2(-6.0 * u, 0)]), GOLD)
		draw_string(_font, Vector2(pbox.position.x + 32.0 * u, pbox.position.y + 21.0 * u), nav_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_n, TXT)


func _hdg_label(di: int) -> String:
	match di:
		0: return "N"
		90: return "E"
		180: return "S"
		270: return "W"
	return str(di)


# --- GESCHWINDIGKEIT-Box unten links (Mockup: grosse Zahl, m/s, AoA) --------
func _draw_speed_box() -> void:
	var u := size.y / 1080.0
	var w := 230.0 * u
	var h := 210.0 * u
	var rect := Rect2(Vector2(40.0 * u, size.y - h - 46.0 * u), Vector2(w, h))
	draw_style_box(_panel_sb(12.0 * u), rect)
	draw_string(_font, rect.position + Vector2(0, 30.0 * u), "GESCHWINDIGKEIT",
		HORIZONTAL_ALIGNMENT_CENTER, w, int(15.0 * u), MUT)
	var spd_col: Color = Color(1, 0.45, 0.3) if stall else TXT
	var num := "%d" % int(round(speed_kmh))
	var fs_big := int(56.0 * u)
	var nw := _font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_big).x
	draw_string(_font, rect.position + Vector2(w * 0.5 - nw * 0.5 - 18.0 * u, 92.0 * u), num,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_big, spd_col)
	draw_string(_font, rect.position + Vector2(w * 0.5 + nw * 0.5 - 10.0 * u, 90.0 * u), "km/h",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(15.0 * u), MUT)
	draw_line(rect.position + Vector2(16.0 * u, 112.0 * u), rect.position + Vector2(w - 16.0 * u, 112.0 * u), Color(P_BORDER.r, P_BORDER.g, P_BORDER.b, 0.2), 1.0)
	draw_string(_font, rect.position + Vector2(0, 142.0 * u), "%d m/s" % int(round(speed_ms)),
		HORIZONTAL_ALIGNMENT_CENTER, w, int(21.0 * u), TXT)
	draw_line(rect.position + Vector2(16.0 * u, 160.0 * u), rect.position + Vector2(w - 16.0 * u, 160.0 * u), Color(P_BORDER.r, P_BORDER.g, P_BORDER.b, 0.2), 1.0)
	var aoa_col: Color = Color(1, 0.45, 0.3) if stall else (GOLD if aoa > 11.0 else MUT)
	draw_string(_font, rect.position + Vector2(0, 190.0 * u), "AoA %d°" % int(round(aoa)),
		HORIZONTAL_ALIGNMENT_CENTER, w, int(19.0 * u), aoa_col)

# --- HOEHE-Box unten rechts (Mockup: grosse Zahl, Steigen, G-Kraft) ---------
func _draw_alt_box() -> void:
	var u := size.y / 1080.0
	var w := 230.0 * u
	var h := 210.0 * u
	var rect := Rect2(Vector2(size.x - w - 40.0 * u, size.y - h - 46.0 * u), Vector2(w, h))
	draw_style_box(_panel_sb(12.0 * u), rect)
	draw_string(_font, rect.position + Vector2(0, 30.0 * u), "HÖHE",
		HORIZONTAL_ALIGNMENT_CENTER, w, int(15.0 * u), MUT)
	var num := "%d" % int(round(altitude))
	var fs_big := int(56.0 * u)
	var nw := _font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_big).x
	draw_string(_font, rect.position + Vector2(w * 0.5 - nw * 0.5 - 14.0 * u, 92.0 * u), num,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_big, TXT)
	draw_string(_font, rect.position + Vector2(w * 0.5 + nw * 0.5 - 2.0 * u, 90.0 * u), "m",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(15.0 * u), MUT)
	draw_line(rect.position + Vector2(16.0 * u, 112.0 * u), rect.position + Vector2(w - 16.0 * u, 112.0 * u), Color(P_BORDER.r, P_BORDER.g, P_BORDER.b, 0.2), 1.0)
	var cc: Color = CYAN if climb > 0.4 else (Color(1, 0.6, 0.3) if climb < -0.4 else MUT)
	var ctxt := "0.0" if absf(climb) <= 0.4 else ("%+.1f" % climb)
	draw_string(_font, rect.position + Vector2(0, 142.0 * u), "↕  %s m/s" % ctxt,
		HORIZONTAL_ALIGNMENT_CENTER, w, int(21.0 * u), cc)
	draw_line(rect.position + Vector2(16.0 * u, 160.0 * u), rect.position + Vector2(w - 16.0 * u, 160.0 * u), Color(P_BORDER.r, P_BORDER.g, P_BORDER.b, 0.2), 1.0)
	var gcol: Color = GOLD if gforce > 4.0 else CYAN
	draw_string(_font, rect.position + Vector2(0, 190.0 * u), "G-KRAFT  %.1f g" % gforce,
		HORIZONTAL_ALIGNMENT_CENTER, w, int(19.0 * u), gcol)

# --- Zielkreis / Fadenkreuz ------------------------------------------------
func _draw_reticle() -> void:
	if mouse_fly:
		if aim_vis:
			# NUR ein Kreis (kein Fadenkreuz): klein, dünn, durchsichtig, grau
			draw_arc(aim_pos, 18.0, 0.0, TAU, 56, Color(0.82, 0.84, 0.88, 0.5), 1.0, true)
		if nose_vis and not gun_vis:
			# kleine Raute = Nasenrichtung — NUR ohne Bord-Pipper (der zeigt die
			# Nase ohnehin, plus Ballistik; zwei gelbe Marker verwirrten nur)
			var n := nose_pos
			draw_polyline(PackedVector2Array([
				n + Vector2(0, -9), n + Vector2(9, 0), n + Vector2(0, 9), n + Vector2(-9, 0), n + Vector2(0, -9)]),
				Color(1.0, 0.88, 0.3, 0.95), 2.0)
	elif not gun_vis:
		# kein Geschütz an Bord: kleines statisches Kreuz als Orientierung (Bildmitte)
		var c := size * 0.5
		draw_arc(c, 8.0, 0.0, TAU, 32, Color(1, 1, 1, 0.6), 2.0, true)
		draw_line(c + Vector2(-14, 0), c + Vector2(-9, 0), Color(1, 1, 1, 0.6), 2.0)
		draw_line(c + Vector2(9, 0), c + Vector2(14, 0), Color(1, 1, 1, 0.6), 2.0)
		draw_line(c + Vector2(0, -14), c + Vector2(0, -9), Color(1, 1, 1, 0.6), 2.0)
		draw_circle(c, 1.5, Color(1, 1, 1, 0.7))
	# BALLISTISCHER PIPPER (beide Modi): feiner Kreis + Mittelpunkt, ruhig & clean —
	# dort schlagen die Kugeln ein (Eigenfahrt + Bullet-Drop, Referenz 400 m/Lock).
	if gun_vis:
		var g := gun_pos
		var oc := Color(0, 0, 0, 0.45)
		var gc := Color(1.0, 0.84, 0.25, 0.95)
		draw_arc(g, 10.0, 0.0, TAU, 48, oc, 2.8, true)   # dunkle Kontur dahinter
		draw_arc(g, 10.0, 0.0, TAU, 48, gc, 1.3, true)   # feiner gelber Ring
		draw_circle(g, 2.2, oc)
		draw_circle(g, 1.5, gc)


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
	var u := size.y / 1080.0
	var fs := int(14.0 * u)
	var fw: float = _font.get_string_size(mode_text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x + 26.0 * u
	var y := 172.0 * u   # unter Kompass + Kursbox + NAV-Pille
	var r := Rect2(size.x * 0.5 - fw * 0.5, y, fw, 26.0 * u)
	draw_style_box(_panel_sb(8.0 * u), r)
	draw_string(_font, Vector2(r.position.x, y + 19.0 * u), mode_text,
		HORIZONTAL_ALIGNMENT_CENTER, fw, fs, CYAN)


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


# ---------------------------------------------------------------------------
# CORNER-MINIMAP (immer sichtbar im Flug): spielerzentrierter Ausschnitt der
# Weltkarte (Textur kommt von Main, sobald der Karten-Thread fertig ist),
# Norden oben, eigene Marker in Reichweite. Versteckt sich, wenn die grosse
# M-Karte offen ist. Wird am Ende von _draw() aufgerufen.
# ---------------------------------------------------------------------------
var mini_tex: Texture2D = null
var mini_player: Node3D = null
var mini_airfields: Array = []
var mini_pois: Array = []
var big_map_open := false
const MINI_SPAN := 7000.0        # sichtbare Weltbreite (m)


func _draw_minimap() -> void:
	if mini_tex == null or big_map_open or mini_player == null or not is_instance_valid(mini_player):
		return
	var vs := size
	var ui := vs.y / 1080.0
	var s := floorf(170.0 * ui)
	var rect := Rect2(Vector2(vs.x - s - 40.0 * ui, vs.y - s - 286.0 * ui), Vector2(s, s))
	# Fenster (UV) um den Spieler, am Weltrand geklemmt
	var wr := WorldMap.WORLD_R
	var half := MINI_SPAN / (4.0 * wr)
	var pp := mini_player.global_position
	var c := Vector2(pp.x / wr * 0.5 + 0.5, pp.z / wr * 0.5 + 0.5)
	c = c.clamp(Vector2(half, half), Vector2(1.0 - half, 1.0 - half))
	var win_min := c - Vector2(half, half)
	var win_size := Vector2(half, half) * 2.0
	# Panel + Kartenausschnitt
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.065, 0.085, 0.85)
	sb.set_corner_radius_all(int(10.0 * ui))
	sb.border_color = Color(0.90, 0.93, 0.97, 0.55)
	sb.set_border_width_all(maxi(2, int(2.0 * ui)))
	draw_style_box(sb, rect.grow(6.0 * ui))
	var ts := Vector2(mini_tex.get_width(), mini_tex.get_height())
	draw_texture_rect_region(mini_tex, rect, Rect2(win_min * ts, win_size * ts))
	draw_rect(rect, Color(0, 0, 0, 0.5), false, 1.5 * ui)

	var to_px := func(w: Vector3) -> Vector2:
		var uv := Vector2(w.x / wr * 0.5 + 0.5, w.z / wr * 0.5 + 0.5)
		return rect.position + (uv - win_min) / win_size * rect.size
	# Marker in Reichweite
	for af in mini_airfields:
		var p: Vector2 = to_px.call(af["pos"])
		if rect.has_point(p):
			draw_rect(Rect2(p - Vector2(4.0 * ui, 4.0 * ui), Vector2(8.0 * ui, 8.0 * ui)), Color(0, 0, 0, 0.8))
			draw_rect(Rect2(p - Vector2(3.0 * ui, 3.0 * ui), Vector2(6.0 * ui, 6.0 * ui)), af.get("color", Color.WHITE))
	for poi in mini_pois:
		var p: Vector2 = to_px.call(poi["pos"])
		if rect.has_point(p):
			draw_circle(p, 3.2 * ui, poi.get("color", Color(0.95, 0.85, 0.3)))
	# Spieler-Pfeil (Blickrichtung), N-Kennung
	var p: Vector2 = to_px.call(pp)
	var fwd := -mini_player.global_transform.basis.z
	var a := atan2(fwd.x, fwd.z)
	var dirv := Vector2(sin(a), cos(a))
	var side := Vector2(-dirv.y, dirv.x)
	var L := 9.0 * ui
	var pts := PackedVector2Array([p + dirv * L, p - dirv * L * 0.55 + side * L * 0.62,
		p - dirv * L * 0.27, p - dirv * L * 0.55 - side * L * 0.62])
	draw_colored_polygon(pts, Color(1.0, 0.36, 0.22))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.9), 1.4 * ui)
	draw_string(_font, rect.position + Vector2(rect.size.x * 0.5 - 5.0 * ui, 16.0 * ui), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(14.0 * ui), Color(1, 1, 1, 0.9))
