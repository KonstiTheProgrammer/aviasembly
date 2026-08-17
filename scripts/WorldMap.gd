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

const WORLD_R := 22000.0       # halbe Kartenbreite in Weltmetern (Insel bis 20,4 km + Rand)
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


static func generate_image(t: TerrainWorld, size := 640, world_r := WORLD_R) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var sea := TerrainWorld.SEA_Y
	for py in size:
		var wz := (float(py) / float(size - 1) * 2.0 - 1.0) * world_r
		for px in size:
			var wx := (float(px) / float(size - 1) * 2.0 - 1.0) * world_r
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
			for ms in t.massifs:
				if String(ms.get("type", "")) == "vulkan" and h > 26.0 \
						and Vector2(wx - ms["pos"].x, wz - ms["pos"].z).length() < float(ms["r"]) * 1.05:
					c = Color(0.30, 0.24, 0.21)
			img.set_pixel(px, py, c)
	return img


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
func _try_label(f: Font, pos: Vector2, txt: String, fs: int, col: Color) -> void:
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var r := Rect2(pos - Vector2(0, fs * 0.8), Vector2(w, fs * 1.1))
	for other in _label_rects:
		if r.intersects(other):
			return
	_label_rects.append(r)
	_shadow_text(f, pos, txt, fs, col)


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

	# Flugplaetze: Quadrat mit Kontur + Label
	var fs_af := int(19.0 * ui)
	var msz := 7.0 * ui
	for af in _airfields:
		var p := _world_to_map(af["pos"])
		draw_rect(Rect2(p - Vector2(msz + 1.5 * ui, msz + 1.5 * ui), Vector2((msz + 1.5 * ui) * 2.0, (msz + 1.5 * ui) * 2.0)), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(p - Vector2(msz, msz), Vector2(msz * 2.0, msz * 2.0)), af.get("color", Color.WHITE))
		_shadow_text(F_SEMI, p + Vector2(msz + 6.0 * ui, fs_af * 0.36), String(af["name"]), fs_af, C_TEXT)
	# POIs: Punkt mit Kontur + Label
	var fs_poi := int(17.0 * ui)
	for poi in _pois:
		var p := _world_to_map(poi["pos"])
		if not _map_rect.grow(4.0).has_point(p):
			continue
		draw_circle(p, 6.5 * ui, Color(0, 0, 0, 0.8))
		draw_circle(p, 5.0 * ui, poi.get("color", Color(0.95, 0.85, 0.3)))
		_try_label(F_SEMI, p + Vector2(9.0 * ui, fs_poi * 0.36), String(poi["name"]), fs_poi, Color(0.92, 0.95, 1.0, 0.95))
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
