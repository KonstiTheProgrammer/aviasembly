class_name WorldMap
extends Control
## Die KARTE (Taste M im Flug): stilisierte Top-Down-Insel im SimplePlanes-Look.
##
## generate_image() sampelt terrain.height_at/biome_at direkt (KEINE Chunks noetig) und malt
## die Palette der Welt: tiefes Ozeanblau -> tuerkise Untiefen -> Sand -> Wiese/Wueste/Heide ->
## Fels -> Schnee; Vulkanflanken dunkler Basalt. Main generiert das Bild EINMAL beim Weltaufbau
## in einem Hintergrund-Thread (~100k Samples) und reicht es via set_map() rein.
## Das Overlay zeichnet darueber: Flugplaetze, POIs, Spieler-Pfeil (live), Kompass.

const WORLD_R := 8200.0        # halbe Kartenbreite in Weltmetern (Insel ~7.6 km + Rand)

var _tex: ImageTexture
var _airfields: Array = []     # [{name, pos, color}]
var _pois: Array = []          # [{name, pos, color}]
var _player: Node3D = null
var _panel_rect := Rect2()


static func generate_image(t: TerrainWorld, size := 320, world_r := WORLD_R) -> Image:
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
			# Vulkanflanken dunkel (wie im Gelaende)
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
	var u := (w.x / WORLD_R * 0.5 + 0.5)
	var v := (w.z / WORLD_R * 0.5 + 0.5)
	return _panel_rect.position + Vector2(u, v) * _panel_rect.size


func _draw() -> void:
	if _tex == null:
		return
	# Panel mittig, quadratisch, ~78 % der Bildschirmhoehe — SimplePlanes-clean.
	# Viewport-Groesse statt Control-size: robust auch ohne Layout-Pass (Anchors liefern
	# in manchen Einbett-Situationen 0x0 -> Karte kollabierte in die Ecke).
	var vs := get_viewport_rect().size
	var s := minf(vs.y * 0.78, vs.x * 0.6)
	var pos := Vector2((vs.x - s) * 0.5, (vs.y - s) * 0.5)
	_panel_rect = Rect2(pos, Vector2(s, s))
	# Abdunkeln + Rahmen + Karte
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.05, 0.08, 0.55))
	draw_rect(_panel_rect.grow(14.0), Color(0.10, 0.12, 0.16, 0.96))
	draw_texture_rect(_tex, _panel_rect, false)
	draw_rect(_panel_rect.grow(14.0), Color(0.85, 0.89, 0.95, 0.9), false, 2.0)
	# Titel + Kompass-N + Massstab
	var f := get_theme_default_font()
	var fs := 22
	draw_string(f, _panel_rect.position + Vector2(4, -22), "KARTE",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(0.95, 0.97, 1.0))
	draw_string(f, Vector2(_panel_rect.position.x + _panel_rect.size.x - 130, _panel_rect.position.y - 22),
		"M schließen", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.75, 0.80, 0.88))
	draw_string(f, _panel_rect.position + Vector2(_panel_rect.size.x * 0.5 - 6, 24), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color(1, 1, 1, 0.85))
	# Flugplaetze: Quadrat + Name
	for af in _airfields:
		var p := _world_to_map(af["pos"])
		var col: Color = af.get("color", Color.WHITE)
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), col)
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Color(0, 0, 0, 0.65), false, 1.5)
		draw_string(f, p + Vector2(8, 4), String(af["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color(1, 1, 1, 0.95))
	# POIs: Punkt + Name
	for poi in _pois:
		var p := _world_to_map(poi["pos"])
		draw_circle(p, 4.5, poi.get("color", Color(0.95, 0.85, 0.3)))
		draw_circle(p, 4.5, Color(0, 0, 0, 0.6), false, 1.2)
		draw_string(f, p + Vector2(7, 4), String(poi["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color(1, 1, 1, 0.9))
	# Spieler: Pfeil in Blickrichtung (Yaw aus -basis.z)
	if _player != null and is_instance_valid(_player):
		var p := _world_to_map(_player.global_position)
		var fwd := -_player.global_transform.basis.z
		var a := atan2(fwd.x, fwd.z)
		var dirv := Vector2(sin(a), cos(a))
		var side := Vector2(-dirv.y, dirv.x)
		var pts := PackedVector2Array([p + dirv * 11.0, p - dirv * 6.0 + side * 7.0,
			p - dirv * 3.0, p - dirv * 6.0 - side * 7.0])
		draw_colored_polygon(pts, Color(1.0, 0.36, 0.22))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.7), 1.5)


func toggle() -> void:
	visible = not visible
