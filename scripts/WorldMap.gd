class_name WorldMap
extends Control
## Die KARTE (Taste M im Flug): stilisierte Top-Down-Insel im SimplePlanes-Look.
##
## generate_image() sampelt terrain.height_at/biome_at direkt (KEINE Chunks noetig) und malt
## die Palette der Welt. Main generiert das Bild EINMAL beim Weltaufbau im Hintergrund-Thread.
##
## DESIGN-SPRACHE (crisp auf 1440p+): alle Masse skalieren mit Viewport-Hoehe (ui = vh/1080),
## Projekt-Font Titillium (Bold fuer Titel, SemiBold fuer Labels) statt Default-Font,
## gerundetes Panel (StyleBoxFlat) mit INTERNER Titelleiste (kollidiert nicht mehr mit dem
## HUD dahinter), kraeftiges Abdunkeln, 2-km-Grid, Massstabsbalken, Kompass-Buchstaben,
## Marker mit dunkler Kontur + Schattentext.

const WORLD_R := 34000.0       # halbe Kartenbreite (Sturmkap bis 32,1 km + Rand)
const F_BOLD := preload("res://fonts/TitilliumWeb-Bold.ttf")
const F_SEMI := preload("res://fonts/TitilliumWeb-SemiBold.ttf")

const C_PANEL := Color(0.055, 0.065, 0.085, 0.97)
const C_HEADER := Color(0.085, 0.10, 0.13, 1.0)
const C_BORDER := Color(0.90, 0.93, 0.97, 0.75)
const C_TEXT := Color(0.95, 0.97, 1.0)
const C_MUTED := Color(0.62, 0.68, 0.78)
const C_PLAYER := Color(1.0, 0.36, 0.22)

var _tex: ImageTexture
var _airfields: Array = []
var _pois: Array = []
var _player: Node3D = null
var _map_rect := Rect2()
# Zoom (Mausrad / +-): 1 = ganze Insel, gezoomt = spielerzentriert (geklemmt)
const ZOOMS := [1.0, 2.5, 6.0]
var _zoom_i := 0
var _win_min := Vector2.ZERO   # sichtbares Weltfenster in UV [0..1]
var _win_size := Vector2.ONE
var _label_rects: Array = []   # Label-Entzerrung (Overview-Cluster)


## Das Kartenbild. ZEILENWEISE PARALLEL ueber den WorkerThreadPool, wie die Fernschuerze.
##
## Vorher lief alles auf einem Thread: 512 x 512 Geländeproben, gemessen 6,6 s
## (tools/_karte_zeit.gd) — beim Spielstart, wenn auch Chunks, Schuerze und Stadt um
## die Kerne konkurrieren, spuerbar laenger, und so lange meldete M nur "Karte wird noch
## gezeichnet". height_at und biome_at sind rein lesend und laufen im Pool ohnehin schon
## (Fernschuerze, Chunk-Worker).
##
## HOHE PRIORITAET: beim Start rechnet die Fernschuerze gleichzeitig 577 Kacheln im
## selben Pool. Ohne Vorrang standen die Kartenzeilen hinter ihr an — gemessen 12,6 s,
## also LANGSAMER als der alte Einzelthread. Mit Vorrang ist die Karte in einem Bruchteil
## davon fertig, und die Schuerze verliert dabei nur diese Zeit.
##
## BITGLEICH ZUM ALTEN BILD: jede Zeile wird weiter ueber Image.set_pixel quantisiert,
## nicht von Hand in Bytes gerechnet — die Pruefsumme in _karte_zeit bleibt dieselbe.
static func generate_image(t: TerrainWorld, kante := 640, world_r := WORLD_R) -> Image:
	# Die Vulkane EINMAL heraussuchen statt fuer jeden der 262 144 Bildpunkte ueber alle
	# Massive zu laufen und dabei jedes Mal den Typ als String zu vergleichen.
	var vulkane: Array = []
	for ms in t.massifs:
		if String(ms.get("type", "")) == "vulkan":
			var mp: Vector3 = ms["pos"]
			vulkane.append([Vector2(mp.x, mp.z), float(ms["r"]) * 1.05])
	var zeilen: Array = []
	zeilen.resize(kante)
	var sperre := Mutex.new()
	var gid := WorkerThreadPool.add_group_task(func(py: int) -> void:
		var z := _zeile(t, py, kante, world_r, vulkane)
		sperre.lock()
		zeilen[py] = z
		sperre.unlock(), kante, -1, true, "Weltkarte")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var daten := PackedByteArray()
	for z in zeilen:
		daten.append_array(z)
	return Image.create_from_data(kante, kante, false, Image.FORMAT_RGB8, daten)


static func _zeile(t: TerrainWorld, py: int, kante: int, world_r: float,
		vulkane: Array) -> PackedByteArray:
	var reihe := Image.create(kante, 1, false, Image.FORMAT_RGB8)
	var wz := (float(py) / float(kante - 1) * 2.0 - 1.0) * world_r
	for px in kante:
		var wx := (float(px) / float(kante - 1) * 2.0 - 1.0) * world_r
		reihe.set_pixel(px, 0, _farbe(t, wx, wz, vulkane))
	return reihe.get_data()


static func _farbe(t: TerrainWorld, wx: float, wz: float, vulkane: Array) -> Color:
	var sea := TerrainWorld.SEA_Y
	var h := t.height_at(wx, wz)
	var c: Color
	if h < sea - 10.0:
		c = Color(0.10, 0.33, 0.60)                       # tiefer Ozean
	elif h < sea - 1.0:
		c = Color(0.10, 0.33, 0.60).lerp(Color(0.30, 0.76, 0.77),
			clampf((h - (sea - 10.0)) / 9.0, 0.0, 1.0))   # Untiefen -> Tuerkis
	elif h < sea + 1.6:
		c = Color(0.93, 0.85, 0.62)                        # Strand
	elif h > 188.0:
		c = Color(0.92, 0.93, 0.95)                        # Schnee
	elif h > 52.0:
		c = Color(0.45, 0.39, 0.33).lerp(Color(0.60, 0.55, 0.48),
			clampf((h - 52.0) / 120.0, 0.0, 1.0))          # Fels
	else:
		match t.biome_at(wx, wz):
			TerrainWorld.Biome.WUESTE:
				c = Color(0.89, 0.79, 0.55)
			TerrainWorld.Biome.HEIDE:
				c = Color(0.72, 0.65, 0.47)
			_:
				c = Color(0.42, 0.62, 0.30).lerp(Color(0.30, 0.50, 0.25),
					clampf(h / 52.0, 0.0, 1.0))            # Wiese, hoeher = dunkler
	if h > 26.0:
		for v in vulkane:
			if Vector2(wx, wz).distance_to(v[0]) < float(v[1]):
				# Dunkler als vorher (0.30/0.24/0.21), weil der Kegel im Gelaende kein
				# brauner Berg mehr ist, sondern schwarzer Basalt mit Rostflecken
				# (TerrainWorld.VULKAN_BASALT/_ROST). Die Karte muss dasselbe Zeichen
				# zeigen wie das Fenster, sonst sucht man am Boden einen Berg, den man
				# auf der Karte nicht wiedererkennt.
				c = Color(0.17, 0.135, 0.125)
	return c


func setup(map_img: Image, airfields: Array, pois: Array, player: Node3D) -> void:
	_tex = ImageTexture.create_from_image(map_img)
	_airfields = airfields
	_pois = pois
	_player = player
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func set_player(p: Node3D) -> void:
	_player = p


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()   # Spieler-Pfeil bewegt sich live


func _world_to_map(w: Vector3) -> Vector2:
	var uv := Vector2(w.x / WORLD_R * 0.5 + 0.5, w.z / WORLD_R * 0.5 + 0.5)
	return _map_rect.position + (uv - _win_min) / _win_size * _map_rect.size


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_i = mini(_zoom_i + 1, ZOOMS.size() - 1)
			get_viewport().set_input_as_handled()   # nicht an die Flug-Kamera durchreichen
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_i = maxi(_zoom_i - 1, 0)
			get_viewport().set_input_as_handled()


## Sichtfenster (UV) aus Zoom + Spielerposition bestimmen; am Weltrand geklemmt.
func _update_window() -> void:
	var z: float = ZOOMS[_zoom_i]
	var half := 0.5 / z
	var c := Vector2(0.5, 0.5)
	if z > 1.0 and _player != null and is_instance_valid(_player):
		var pp := _player.global_position
		c = Vector2(pp.x / WORLD_R * 0.5 + 0.5, pp.z / WORLD_R * 0.5 + 0.5)
	c = c.clamp(Vector2(half, half), Vector2(1.0 - half, 1.0 - half))
	_win_min = c - Vector2(half, half)
	_win_size = Vector2(half, half) * 2.0


## Label nur zeichnen, wenn es nicht mit einem bereits gezeichneten kollidiert (Marker bleibt).
## Einen Namen neben seinen Marker setzen: rechts, sonst links, oben, unten. Nur wenn die
## Stelle frei UND ganz in der Karte ist; sonst entfaellt der Name (Zoomen schafft Platz).
## `weitere` = zusaetzliche Hindernisse neben den gesetzten Namen und Platzmarkern.
func _name_setzen(p: Vector2, halb: float, txt: String, fs: int, col: Color, ui: float,
		weitere: Array) -> void:
	var w := F_SEMI.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var h := fs * 1.1
	var abstand := halb + 4.0 * ui
	var kandidaten := [
		Vector2(p.x + abstand, p.y - h * 0.5),            # rechts
		Vector2(p.x - abstand - w, p.y - h * 0.5),        # links
		Vector2(p.x - w * 0.5, p.y - abstand - h),        # oben
		Vector2(p.x - w * 0.5, p.y + abstand),            # unten
	]
	for ecke: Vector2 in kandidaten:
		var r := Rect2(ecke, Vector2(w, h))
		if not _map_rect.encloses(r):
			continue
		var frei := true
		for other in _label_rects + weitere:
			if r.intersects(other):
				frei = false
				break
		if frei:
			_label_rects.append(r)
			_shadow_text(F_SEMI, ecke + Vector2(0, fs * 0.8), txt, fs, col)
			return


func _shadow_text(f: Font, pos: Vector2, txt: String, fs: int, col: Color) -> void:
	draw_string(f, pos + Vector2(2, 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(0, 0, 0, 0.75))
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)


func _draw() -> void:
	if _tex == null:
		return
	var vs := get_viewport_rect().size
	var ui := vs.y / 1080.0                              # Skalierung: crisp auf 1440p/4K
	var s := floorf(minf(vs.y * 0.74, vs.x * 0.55))
	var head := floorf(52.0 * ui)
	var panel := Rect2(floorf((vs.x - s) * 0.5), floorf((vs.y - s - head) * 0.5),
		s, s + head)
	_map_rect = Rect2(panel.position + Vector2(0, head), Vector2(s, s)).grow(-floorf(10.0 * ui))
	_map_rect.position = _map_rect.position.floor()

	# Hintergrund kraeftig abdunkeln -> das HUD dahinter lenkt nicht mehr ab
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.05, 0.72))

	# Panel: gerundet + Rand + interne Titelleiste (keine Kollision mit dem Kompass-HUD)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.set_corner_radius_all(int(12.0 * ui))
	sb.border_color = C_BORDER
	sb.set_border_width_all(maxi(2, int(2.0 * ui)))
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = int(18.0 * ui)
	draw_style_box(sb, panel)
	var hb := StyleBoxFlat.new()
	hb.bg_color = C_HEADER
	hb.corner_radius_top_left = int(12.0 * ui)
	hb.corner_radius_top_right = int(12.0 * ui)
	draw_style_box(hb, Rect2(panel.position, Vector2(panel.size.x, head)))
	var fs_title := int(26.0 * ui)
	_shadow_text(F_BOLD, panel.position + Vector2(18.0 * ui, head * 0.5 + fs_title * 0.36), "KARTE", fs_title, C_TEXT)
	var hint := "Mausrad — Zoom  ·  M — schließen"
	var fs_hint := int(17.0 * ui)
	var hw := F_SEMI.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_hint).x
	_shadow_text(F_SEMI, panel.position + Vector2(panel.size.x - hw - 18.0 * ui, head * 0.5 + fs_hint * 0.36), hint, fs_hint, C_MUTED)

	# Karte (sichtbares Fenster je Zoom) + Grid + Kompass-Buchstaben
	_update_window()
	_label_rects.clear()
	var ts := Vector2(_tex.get_width(), _tex.get_height())
	draw_texture_rect_region(_tex, _map_rect, Rect2(_win_min * ts, _win_size * ts))
	var win_world := _win_size.x * WORLD_R * 2.0
	var grid_km := 5000.0 if _zoom_i == 0 else (2000.0 if _zoom_i == 1 else 1000.0)
	var step := _map_rect.size.x * (grid_km / win_world)
	var gx := _map_rect.position.x + step
	while gx < _map_rect.end.x - 1.0:
		draw_line(Vector2(gx, _map_rect.position.y), Vector2(gx, _map_rect.end.y), Color(1, 1, 1, 0.08), 1.0)
		gx += step
	var gy := _map_rect.position.y + step
	while gy < _map_rect.end.y - 1.0:
		draw_line(Vector2(_map_rect.position.x, gy), Vector2(_map_rect.end.x, gy), Color(1, 1, 1, 0.08), 1.0)
		gy += step
	draw_rect(_map_rect, Color(0, 0, 0, 0.55), false, maxf(1.0, 1.5 * ui))
	var fs_dir := int(22.0 * ui)
	_shadow_text(F_BOLD, Vector2(_map_rect.position.x + _map_rect.size.x * 0.5 - fs_dir * 0.3, _map_rect.position.y + fs_dir + 4.0 * ui), "N", fs_dir, C_TEXT)
	_shadow_text(F_BOLD, Vector2(_map_rect.position.x + _map_rect.size.x * 0.5 - fs_dir * 0.3, _map_rect.end.y - 8.0 * ui), "S", fs_dir, C_TEXT)
	_shadow_text(F_BOLD, Vector2(_map_rect.position.x + 8.0 * ui, _map_rect.position.y + _map_rect.size.y * 0.5 + fs_dir * 0.36), "W", fs_dir, C_TEXT)
	_shadow_text(F_BOLD, Vector2(_map_rect.end.x - fs_dir * 0.85, _map_rect.position.y + _map_rect.size.y * 0.5 + fs_dir * 0.36), "O", fs_dir, C_TEXT)

	# Massstabsbalken (2 km) unten links in der Karte
	var bar_y := _map_rect.end.y - 22.0 * ui
	var bar_x := _map_rect.position.x + 18.0 * ui
	draw_line(Vector2(bar_x, bar_y), Vector2(bar_x + step, bar_y), Color(0, 0, 0, 0.8), 6.0 * ui)
	draw_line(Vector2(bar_x, bar_y), Vector2(bar_x + step, bar_y), Color(1, 1, 1, 0.95), 3.0 * ui)
	_shadow_text(F_SEMI, Vector2(bar_x, bar_y - 8.0 * ui), "%d km" % int(grid_km / 1000.0), int(16.0 * ui), C_TEXT)

	# MARKER ZUERST, BESCHRIFTUNGEN DANACH — und beide durch die Entzerrung.
	#
	# Vorher liefen nur die POI-Namen ueber _try_label; die Flugplatznamen wurden direkt
	# gezeichnet und nirgends als belegt eingetragen. Im dichten Zentrum (NORDFELD,
	# OSTHAFEN, BERGPISTE, GROSSSTADT, Stadt, Canyon ...) lag deshalb Name ueber Name
	# (Screenshot tools/_flug_bilder.gd). Ausserdem wurden Flugplaetze NICHT auf den
	# Kartenausschnitt beschraenkt: beim Hineinzoomen standen die ausserhalb liegenden
	# ueber dem Panelrand und dem abgedunkelten Hintergrund.
	# Reihenfolge: alle Marker als belegte Flaeche eintragen (kein Name ueberdeckt einen
	# Punkt), dann Flugplatznamen (Vorrang), dann POI-Namen. Passt ein Name rechts nicht,
	# wird links, oben und unten probiert; passt er nirgends, entfaellt er — beim
	# Hineinzoomen hat er dann Platz.
	var fs_af := int(19.0 * ui)
	var msz := 7.0 * ui
	var fs_poi := int(17.0 * ui)
	var namen: Array = []     # [marker_pos, halbe_markergroesse, text, fs, farbe, ist_platz]
	var punkte: Array = []    # Rechtecke der POI-Punkte (nur fuer POI-Namen ein Hindernis)
	var sichtbar := _map_rect.grow(4.0)
	for af in _airfields:
		var p := _world_to_map(af["pos"])
		if not sichtbar.has_point(p):
			continue
		var ms := msz + 1.5 * ui
		draw_rect(Rect2(p - Vector2(ms, ms), Vector2(ms * 2.0, ms * 2.0)), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(p - Vector2(msz, msz), Vector2(msz * 2.0, msz * 2.0)), af.get("color", Color.WHITE))
		_label_rects.append(Rect2(p - Vector2(ms, ms), Vector2(ms * 2.0, ms * 2.0)))
		namen.append([p, ms, String(af["name"]), fs_af, C_TEXT, true])
	for poi in _pois:
		var p := _world_to_map(poi["pos"])
		if not sichtbar.has_point(p):
			continue
		draw_circle(p, 6.5 * ui, Color(0, 0, 0, 0.8))
		draw_circle(p, 5.0 * ui, poi.get("color", Color(0.95, 0.85, 0.3)))
		punkte.append(Rect2(p - Vector2(6.5 * ui, 6.5 * ui), Vector2(13.0 * ui, 13.0 * ui)))
		namen.append([p, 6.5 * ui, String(poi["name"]), fs_poi, Color(0.92, 0.95, 1.0, 0.95), false])
	# FLUGPLAETZE HABEN VORRANG: ihre Namen duerfen einen POI-Punkt streifen (zum Landen
	# sucht man den Platz, nicht das Windrad daneben), aber keinen anderen Namen und keinen
	# Platzmarker. POI-Namen muessen allem ausweichen.
	for n in namen:
		if n[5]:
			_name_setzen(n[0], n[1], n[2], n[3], n[4], ui, [])
	for n in namen:
		if not n[5]:
			_name_setzen(n[0], n[1], n[2], n[3], n[4], ui, punkte)
	# Spieler: grosser Pfeil mit weisser Kontur
	if _player != null and is_instance_valid(_player):
		var p := _world_to_map(_player.global_position)
		var fwd := -_player.global_transform.basis.z
		var a := atan2(fwd.x, fwd.z)
		var dirv := Vector2(sin(a), cos(a))
		var side := Vector2(-dirv.y, dirv.x)
		var L := 16.0 * ui
		var pts := PackedVector2Array([p + dirv * L, p - dirv * L * 0.55 + side * L * 0.62,
			p - dirv * L * 0.27, p - dirv * L * 0.55 - side * L * 0.62])
		draw_colored_polygon(pts, C_PLAYER)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.95), maxf(1.5, 2.0 * ui))


func toggle() -> void:
	visible = not visible
