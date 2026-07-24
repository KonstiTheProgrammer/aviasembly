## Wahrzeichen / POIs (Stufe-2-Map): Stadt mit Kirche + Leuchtturm.
## STATISCH, damit Spiel (Main) UND Render-Tool dieselbe Geometrie bauen.
## Reine Low-Poly-Box-/Pyramiden-Bauten (passend zum restlichen Welt-Stil).
class_name Landmarks
extends RefCounted

const HOUSE_GABLE := 0
const HOUSE_HIP := 1
const HOUSE_TOWNHOUSE := 2
const HOUSE_FLAT := 3
const HOUSE_CHALET := 4
const HOUSE_BARN := 5
const HOUSE_STYLE_COUNT := 6

static var _building_vertex_mat: StandardMaterial3D


static func _mat(c: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _emit(c: Color, e := 2.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


static func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


# Pyramiden-/Walmdach (4-seitige "Cylinder"-Pyramide, 45° gedreht über eine Box).
static func _roof(parent: Node3D, pos: Vector3, span: float, height: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.radial_segments = 4
	cm.top_radius = 0.0
	cm.bottom_radius = span * 0.72
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = Vector3(0, 45, 0)
	parent.add_child(mi)


static func _glow(parent: Node3D, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.6; s.height = 1.2; s.radial_segments = 8; s.rings = 4
	mi.mesh = s
	mi.position = pos
	mi.material_override = _emit(col)
	parent.add_child(mi)


static func _building_mat() -> StandardMaterial3D:
	if _building_vertex_mat == null:
		_building_vertex_mat = StandardMaterial3D.new()
		_building_vertex_mat.albedo_color = Color.WHITE
		_building_vertex_mat.vertex_color_use_as_albedo = true
		_building_vertex_mat.roughness = 0.88
		# Häuser sind geschlossene Meshes. CULL_DISABLED vermeidet aber, dass winzige
		# Fensterquads bei extremer Entfernung durch wechselnde Winding-Präzision flackern.
		_building_vertex_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _building_vertex_mat


static func _shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0.0, 1.0), clampf(c.g * f, 0.0, 1.0),
		clampf(c.b * f, 0.0, 1.0), c.a)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col); st.add_vertex(a)
	st.set_color(col); st.add_vertex(b)
	st.set_color(col); st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


static func _box_geo(st: SurfaceTool, center: Vector3, size: Vector3, col: Color) -> void:
	var x0 := center.x - size.x * 0.5
	var x1 := center.x + size.x * 0.5
	var y0 := center.y - size.y * 0.5
	var y1 := center.y + size.y * 0.5
	var z0 := center.z - size.z * 0.5
	var z1 := center.z + size.z * 0.5
	# Leicht unterschiedliche Helligkeit je Himmelsrichtung: lesbare Form schon aus 500 m.
	_quad(st, Vector3(x0,y0,z0), Vector3(x0,y1,z0), Vector3(x1,y1,z0), Vector3(x1,y0,z0), col)
	_quad(st, Vector3(x1,y0,z1), Vector3(x1,y1,z1), Vector3(x0,y1,z1), Vector3(x0,y0,z1), _shade(col, 0.90))
	_quad(st, Vector3(x0,y0,z1), Vector3(x0,y1,z1), Vector3(x0,y1,z0), Vector3(x0,y0,z0), _shade(col, 0.82))
	_quad(st, Vector3(x1,y0,z0), Vector3(x1,y1,z0), Vector3(x1,y1,z1), Vector3(x1,y0,z1), _shade(col, 0.95))
	_quad(st, Vector3(x0,y1,z0), Vector3(x0,y1,z1), Vector3(x1,y1,z1), Vector3(x1,y1,z0), _shade(col, 1.05))
	_quad(st, Vector3(x0,y0,z1), Vector3(x0,y0,z0), Vector3(x1,y0,z0), Vector3(x1,y0,z1), _shade(col, 0.72))


static func _panel_z(st: SurfaceTool, p: Vector3, size: Vector2, z: float, col: Color, front: bool) -> void:
	var x0 := p.x - size.x * 0.5
	var x1 := p.x + size.x * 0.5
	var y0 := p.y - size.y * 0.5
	var y1 := p.y + size.y * 0.5
	if front:
		_quad(st, Vector3(x0,y0,z), Vector3(x0,y1,z), Vector3(x1,y1,z), Vector3(x1,y0,z), col)
	else:
		_quad(st, Vector3(x1,y0,z), Vector3(x1,y1,z), Vector3(x0,y1,z), Vector3(x0,y0,z), col)


static func _panel_x(st: SurfaceTool, p: Vector3, size: Vector2, x: float, col: Color, right: bool) -> void:
	var z0 := p.z - size.x * 0.5
	var z1 := p.z + size.x * 0.5
	var y0 := p.y - size.y * 0.5
	var y1 := p.y + size.y * 0.5
	if right:
		_quad(st, Vector3(x,y0,z0), Vector3(x,y1,z0), Vector3(x,y1,z1), Vector3(x,y0,z1), col)
	else:
		_quad(st, Vector3(x,y0,z1), Vector3(x,y1,z1), Vector3(x,y1,z0), Vector3(x,y0,z0), col)


static func _gable_roof_geo(st: SurfaceTool, w: float, d: float, y: float, rh: float,
		roof_col: Color, gable_col: Color) -> void:
	var x := w * 0.56
	var z := d * 0.56
	var lf := Vector3(-x, y, -z)
	var lb := Vector3(-x, y, z)
	var rf := Vector3(x, y, -z)
	var rb := Vector3(x, y, z)
	var ridge_f := Vector3(0, y + rh, -z)
	var ridge_b := Vector3(0, y + rh, z)
	_quad(st, lf, lb, ridge_b, ridge_f, _shade(roof_col, 0.88))
	_quad(st, rb, rf, ridge_f, ridge_b, roof_col)
	_tri(st, lf, ridge_f, rf, _shade(gable_col, 0.94))
	_tri(st, rb, ridge_b, lb, _shade(gable_col, 0.86))


static func _hip_roof_geo(st: SurfaceTool, w: float, d: float, y: float, rh: float,
		roof_col: Color) -> void:
	var x := w * 0.56
	var z := d * 0.56
	var rz := maxf(z - x * 0.70, z * 0.16)
	var lf := Vector3(-x, y, -z)
	var lb := Vector3(-x, y, z)
	var rf := Vector3(x, y, -z)
	var rb := Vector3(x, y, z)
	var ridge_f := Vector3(0, y + rh, -rz)
	var ridge_b := Vector3(0, y + rh, rz)
	_quad(st, lf, lb, ridge_b, ridge_f, _shade(roof_col, 0.87))
	_quad(st, rb, rf, ridge_f, ridge_b, roof_col)
	_tri(st, lf, ridge_f, rf, _shade(roof_col, 0.78))
	_tri(st, rb, ridge_b, lb, _shade(roof_col, 0.93))


static func _gable_roof(parent: Node3D, pos: Vector3, w: float, d: float, height: float,
		roof_col: Color, gable_col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_gable_roof_geo(st, w, d, 0.0, height, roof_col, gable_col)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _building_mat()
	mi.position = pos
	parent.add_child(mi)


# Ein Haus = EIN leichtes ArrayMesh. Wände, Dach, wenige kontrastreiche Fenster/Türen,
# Fundament und Kamin teilen Vertex-Color-Material -> aus der Luft klar, aber draw-call-arm.
static func _house(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, walls: Array,
		roof_mat: Material, forced_style := -1, alpine := false) -> void:
	var style: int = forced_style
	if style < 0:
		if alpine:
			var ar := rng.randf()
			style = HOUSE_CHALET if ar < 0.56 else (HOUSE_GABLE if ar < 0.88 else HOUSE_BARN)
		else:
			var r := rng.randf()
			if r < 0.28: style = HOUSE_GABLE
			elif r < 0.52: style = HOUSE_HIP
			elif r < 0.69: style = HOUSE_TOWNHOUSE
			elif r < 0.82: style = HOUSE_FLAT
			elif r < 0.94: style = HOUSE_CHALET
			else: style = HOUSE_BARN

	var w := rng.randf_range(7.0, 11.5)
	var d := rng.randf_range(7.5, 12.0)
	var stories := 2 if rng.randf() < 0.36 else 1
	if style == HOUSE_TOWNHOUSE:
		w = rng.randf_range(6.0, 8.2); d = rng.randf_range(8.0, 11.0)
		stories = rng.randi_range(2, 3)
	elif style == HOUSE_FLAT:
		w = rng.randf_range(8.0, 13.5); d = rng.randf_range(8.0, 13.5)
		stories = rng.randi_range(2, 3)
	elif style == HOUSE_CHALET:
		w = rng.randf_range(8.5, 12.5); d = rng.randf_range(8.0, 11.5)
		stories = 2 if rng.randf() < 0.46 else 1
	elif style == HOUSE_BARN:
		w = rng.randf_range(10.0, 14.5); d = rng.randf_range(13.0, 18.0)
		stories = 1
	var floor_h := 3.35 if style in [HOUSE_TOWNHOUSE, HOUSE_FLAT] else 3.8
	var hgt: float = floor_h * float(stories)
	if style == HOUSE_BARN:
		hgt = rng.randf_range(4.5, 5.8)

	var wall_col: Color = walls[rng.randi() % walls.size()]
	if style == HOUSE_BARN:
		wall_col = Color(0.42, 0.29, 0.20).lerp(wall_col, 0.18)
	var roof_col := Color(0.42, 0.26, 0.21)
	if roof_mat is StandardMaterial3D:
		roof_col = (roof_mat as StandardMaterial3D).albedo_color
	var foundation := Color(0.30, 0.31, 0.30).lerp(_shade(wall_col, 0.58), 0.35)
	var trim := _shade(wall_col, 0.56 if style == HOUSE_CHALET else 0.70)
	var window := Color(0.12, 0.18, 0.23)
	if rng.randf() < 0.24:
		window = Color(0.82, 0.57, 0.25)   # wenige warme Fensterpunkte beleben die Stadt
	var door := Color(0.22, 0.14, 0.10) if style != HOUSE_FLAT else Color(0.12, 0.16, 0.18)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_geo(st, Vector3(0, 0.22, 0), Vector3(w * 1.035, 0.44, d * 1.035), foundation)
	_box_geo(st, Vector3(0, hgt * 0.5 + 0.18, 0), Vector3(w, hgt, d), wall_col)

	var roof_h := rng.randf_range(2.3, 3.4)
	if style == HOUSE_CHALET:
		roof_h = rng.randf_range(3.6, 5.0)
	elif style == HOUSE_BARN:
		roof_h = rng.randf_range(4.0, 5.6)
	elif style == HOUSE_TOWNHOUSE:
		roof_h = rng.randf_range(2.0, 2.8)
	if style == HOUSE_HIP:
		_hip_roof_geo(st, w, d, hgt + 0.18, roof_h, roof_col)
	elif style == HOUSE_FLAT:
		_box_geo(st, Vector3(0, hgt + 0.38, 0), Vector3(w * 1.04, 0.40, d * 1.04), roof_col)
		_box_geo(st, Vector3(w * 0.20, hgt + 0.80, d * 0.08),
			Vector3(w * 0.22, 0.85, d * 0.22), _shade(roof_col, 0.72))
	else:
		_gable_roof_geo(st, w, d, hgt + 0.18, roof_h, roof_col, wall_col)

	# Aus der Luft relevante Fassadenzeichen: pro Geschoss nur zwei Fenster,
	# dazu Seitenfenster. Alles sind Quads im selben Mesh, keine Extra-Nodes.
	if style == HOUSE_BARN:
		_panel_z(st, Vector3(0, hgt * 0.42, 0), Vector2(w * 0.46, hgt * 0.72),
			-d * 0.5 - 0.012, _shade(door, 0.84), true)
		_panel_z(st, Vector3(0, hgt * 0.83, 0), Vector2(w * 0.16, hgt * 0.16),
			-d * 0.5 - 0.018, window, true)
	else:
		for story_i in stories:
			var wy := 2.0 + float(story_i) * floor_h
			var wx := w * 0.23
			for sx in [-1.0, 1.0]:
				_panel_z(st, Vector3(sx * wx, wy, 0), Vector2(minf(1.45, w * 0.17), 1.25),
					-d * 0.5 - 0.012, window, true)
				_panel_z(st, Vector3(sx * wx, wy, 0), Vector2(minf(1.35, w * 0.16), 1.16),
					d * 0.5 + 0.012, _shade(window, 0.82), false)
			_panel_x(st, Vector3(0, wy, 0), Vector2(minf(1.45, d * 0.18), 1.22),
				w * 0.5 + 0.012, _shade(window, 0.92), true)
		_panel_z(st, Vector3(0, 1.35, 0), Vector2(minf(1.55, w * 0.19), 2.6),
			-d * 0.5 - 0.018, door, true)

	if style == HOUSE_CHALET:
		# Eine kräftige dunkle Balkonlinie liest man aus der Luft besser als zehn Geländerstäbe.
		_box_geo(st, Vector3(0, minf(hgt - 0.85, 4.9), -d * 0.5 - 0.48),
			Vector3(w * 1.08, 0.26, 0.95), trim)
		_box_geo(st, Vector3(0, hgt * 0.48, -d * 0.5 - 0.035),
			Vector3(w * 0.86, 0.28, 0.12), trim)
	elif style == HOUSE_TOWNHOUSE:
		_box_geo(st, Vector3(0, floor_h, -d * 0.5 - 0.035),
			Vector3(w * 0.96, 0.20, 0.10), trim)

	if style not in [HOUSE_FLAT, HOUSE_BARN] and rng.randf() < 0.70:
		_box_geo(st, Vector3(w * 0.24, hgt + roof_h * 0.58, d * 0.12),
			Vector3(0.66, maxf(1.6, roof_h * 0.72), 0.66), Color(0.31, 0.22, 0.18))

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _building_mat()
	mi.position = pos
	mi.rotation.y = float(rng.randi_range(0, 3)) * PI * 0.5 + rng.randf_range(-0.14, 0.14)
	mi.name = "Haus_Stil_%d" % style
	parent.add_child(mi)


# Stadt: kompakte, aus der Luft lesbare Straßenstruktur mit sechs Haus-Silhouetten
# + Kirche und freiem Kreuzplatz im Zentrum.
static func build_town(parent: Node3D, center: Vector3) -> void:
	var node := Node3D.new()
	node.position = center
	node.rotation.y = 0.35
	parent.add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC17B + int(center.x) * 13
	var walls := [Color(0.87, 0.83, 0.74), Color(0.80, 0.55, 0.42), Color(0.72, 0.74, 0.69),
		Color(0.86, 0.79, 0.62), Color(0.68, 0.64, 0.62), Color(0.78, 0.70, 0.66)]
	var roof_a := _mat(Color(0.47, 0.27, 0.22))   # Terrakotta
	var roof_b := _mat(Color(0.34, 0.36, 0.41))   # Schiefer
	var span := 6
	var spacing := 21.0
	for gx in range(-span, span + 1):
		for gz in range(-span, span + 1):
			var bx: float = float(gx) * spacing + rng.randf_range(-4.0, 4.0)
			var bz: float = float(gz) * spacing + rng.randf_range(-4.0, 4.0)
			if Vector2(bx, bz).length() > float(span) * spacing * 0.95:
				continue
			# Zwei erkennbare Hauptstraßen + Kirchplatz statt gleichmäßigem Punkteteppich.
			if (absf(bx) < 12.0 or absf(bz) < 12.0) and Vector2(bx, bz).length() < 86.0:
				continue
			if rng.randf() < 0.12:
				continue
			_house(node, Vector3(bx, 0, bz), rng, walls, roof_a if rng.randf() < 0.6 else roof_b)
	# Kirche im Zentrum
	var cwall := _mat(Color(0.90, 0.88, 0.82), 0.88)
	var croof := _mat(Color(0.36, 0.30, 0.44))
	_box(node, Vector3(0, 6.0, 0), Vector3(13, 12, 24), cwall)
	_gable_roof(node, Vector3(0, 12.0, 0), 15.0, 26.0, 6.0,
		croof.albedo_color, cwall.albedo_color)
	var church_glass := _mat(Color(0.16, 0.22, 0.30), 0.42)
	for sz in [-1.0, 1.0]:
		for zz in [-6.5, 0.0, 6.5]:
			_box(node, Vector3(sz * 6.53, 6.6, zz), Vector3(0.14, 3.4, 2.1), church_glass)
	_box(node, Vector3(0, 11.0, -15.0), Vector3(8, 22, 8), cwall)   # Turm
	_roof(node, Vector3(0, 25.0, -15.0), 8.0, 9.0, croof)           # Spitzdach
	_glow(node, Vector3(0, 30.0, -15.0), Color(0.95, 0.85, 0.4))    # Knauf


# Leuchtturm: konischer rot-weiß gebänderter Turm + Laternenhaus + Leuchtfeuer.
static func build_lighthouse(parent: Node3D, center: Vector3) -> void:
	var node := Node3D.new()
	node.position = center
	parent.add_child(node)
	var white := _mat(Color(0.94, 0.94, 0.96), 0.6)
	var red := _mat(Color(0.82, 0.22, 0.18), 0.6)
	var dark := _mat(Color(0.14, 0.15, 0.18), 0.4)
	var H := 19.0
	var segs := 5
	var y := 0.0
	for s in segs:
		var t0 := float(s) / float(segs)
		var t1 := float(s + 1) / float(segs)
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.bottom_radius = lerpf(3.0, 1.7, t0)
		cyl.top_radius = lerpf(3.0, 1.7, t1)
		cyl.height = H / float(segs)
		cyl.radial_segments = 18
		mi.mesh = cyl
		mi.material_override = white if s % 2 == 0 else red
		mi.position = Vector3(0, y + cyl.height * 0.5, 0)
		node.add_child(mi)
		y += cyl.height
	_box(node, Vector3(0, y + 0.3, 0), Vector3(5.2, 0.6, 5.2), red)   # Galerie
	var lant := MeshInstance3D.new()
	var lc := CylinderMesh.new()
	lc.bottom_radius = 1.9; lc.top_radius = 1.9; lc.height = 3.0; lc.radial_segments = 12
	lant.mesh = lc
	lant.material_override = dark
	lant.position = Vector3(0, y + 2.1, 0)
	node.add_child(lant)
	_glow(node, Vector3(0, y + 2.1, 0), Color(1.0, 0.92, 0.55))      # Leuchtfeuer
	_roof(node, Vector3(0, y + 4.4, 0), 4.6, 2.4, red)


# Bergdorf: kompaktes Stein-/Holz-Dorf mit STEILEN Dächern (alpin), kleiner als
# die Talstadt. y = Plateauhöhe (sitzt auf einer eingeebneten Bergterrasse).
static func build_village(parent: Node3D, center: Vector3) -> void:
	var node := Node3D.new()
	node.position = center
	node.rotation.y = -0.5
	parent.add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5A1B + int(center.x) * 7 + int(center.z)
	var walls := [Color(0.80, 0.75, 0.66), Color(0.72, 0.66, 0.58), Color(0.66, 0.60, 0.54),
		Color(0.78, 0.72, 0.62), Color(0.60, 0.56, 0.52)]
	var roof := _mat(Color(0.38, 0.30, 0.26))     # dunkles Holz/Schiefer
	var span := 4
	var spacing := 16.5
	for gx in range(-span, span + 1):
		for gz in range(-span, span + 1):
			var bx: float = float(gx) * spacing + rng.randf_range(-3.0, 3.0)
			var bz: float = float(gz) * spacing + rng.randf_range(-3.0, 3.0)
			if Vector2(bx, bz).length() > float(span) * spacing * 0.92:
				continue
			if Vector2(bx, bz).length() < 16.0 or rng.randf() < 0.16:
				continue
			_house(node, Vector3(bx, 0, bz), rng, walls, roof, -1, true)
	# kleine Kapelle mit Turm
	var chapel_wall := _mat(Color(0.84, 0.80, 0.72), 0.9)
	var chapel_roof := _mat(Color(0.34, 0.28, 0.30))
	_box(node, Vector3(0, 4.0, 0), Vector3(8, 8, 12), chapel_wall)
	_gable_roof(node, Vector3(0, 8.0, 0), 10.0, 14.0, 5.0,
		chapel_roof.albedo_color, chapel_wall.albedo_color)
	_box(node, Vector3(0, 8.0, -7.0), Vector3(4, 16, 4), chapel_wall)
	_roof(node, Vector3(0, 19.0, -7.0), 4.0, 6.0, _mat(Color(0.34, 0.28, 0.30)))


# Stein-Viadukt über ein Flusstal: Deck + Geländer + Pfeiler hinab zum Talgrund
# + Rundbögen zwischen den Pfeilern. center.y = Deck-Höhe, yaw = Ausrichtung.
static func build_bridge(parent: Node3D, center: Vector3, length: float, yaw: float) -> void:
	var node := Node3D.new()
	node.position = center
	node.rotation.y = yaw
	parent.add_child(node)
	var stone := _mat(Color(0.66, 0.63, 0.58), 0.9)
	var stone2 := _mat(Color(0.58, 0.55, 0.51), 0.9)
	var deck_y: float = center.y
	var W := 9.0
	# Fahrbahn + Geländer
	_box(node, Vector3(0, -0.8, 0), Vector3(length, 1.6, W), stone)
	for sx in [-1.0, 1.0]:
		_box(node, Vector3(0, 0.6, sx * (W * 0.5 - 0.4)), Vector3(length, 1.4, 0.6), stone2)
	# Pfeiler-Paare hinab bis zum Talgrund (Viadukt): von Deck (lokal 0) bis ~ -deck_y.
	var npier := 6
	for i in range(npier + 1):
		var x: float = lerpf(-length * 0.5, length * 0.5, float(i) / float(npier))
		# kürzere Pfeiler außen (Talränder höher), längste in der Mitte (überm Fluss)
		var f := 1.0 - absf(float(i) / float(npier) - 0.5) * 1.4
		var ph: float = deck_y * clampf(f, 0.30, 1.0)
		for sz in [-1.0, 1.0]:
			_box(node, Vector3(x, -ph * 0.5 - 0.8, sz * W * 0.32), Vector3(3.0, ph, 3.0), stone2)
		# Querstrebe oben am Pfeilerpaar (Andeutung Bogen/Joch)
		_box(node, Vector3(x, -2.2, 0), Vector3(3.0, 1.4, W * 0.7), stone2)


# Windrad: konischer Turm + Gondel + 3-Blatt-Rotor. Gibt den ROTOR-Pivot zurueck —
# Main dreht ihn in _process (die einzige bewegte Landmark, darum kein eigener Script).
static func build_windmill(parent: Node3D, pos: Vector3, face_yaw := 0.6) -> Node3D:
	var node := Node3D.new()
	node.position = pos
	node.rotation.y = face_yaw
	parent.add_child(node)
	var white := _mat(Color(0.92, 0.93, 0.95), 0.5)
	var gray := _mat(Color(0.55, 0.58, 0.62), 0.5)
	var H := 26.0
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = 1.3
	cyl.top_radius = 0.7
	cyl.height = H
	cyl.radial_segments = 10
	mi.mesh = cyl
	mi.position = Vector3(0, H * 0.5, 0)
	mi.material_override = white
	node.add_child(mi)
	_box(node, Vector3(0, H + 0.6, -0.4), Vector3(1.8, 1.8, 3.4), gray)   # Gondel
	var rotor := Node3D.new()
	rotor.position = Vector3(0, H + 0.6, -2.4)                            # Nabe vor der Gondel
	node.add_child(rotor)
	_box(rotor, Vector3.ZERO, Vector3(1.0, 1.0, 1.0), gray)               # Nabe
	for i in 3:
		var blade := Node3D.new()
		blade.rotation.z = i * TAU / 3.0
		rotor.add_child(blade)
		_box(blade, Vector3(0, 5.6, 0), Vector3(0.55, 11.0, 0.18), white)
	return rotor


# Segelschiff: Low-Poly-Rumpf + Bugkeil + Masten mit Segeln. Liegt auf dem Meer (SEA_Y).
static func build_ship(parent: Node3D, pos2: Vector2, heading := 0.0) -> void:
	var node := Node3D.new()
	node.position = Vector3(pos2.x, TerrainWorld.SEA_Y + 0.4, pos2.y)
	node.rotation.y = heading
	parent.add_child(node)
	var hullm := _mat(Color(0.34, 0.22, 0.14), 0.7)
	var deckm := _mat(Color(0.55, 0.42, 0.27), 0.8)
	var sailm := _mat(Color(0.93, 0.91, 0.85), 0.9)
	_box(node, Vector3(0, 1.2, 0), Vector3(6.0, 2.4, 20.0), hullm)        # Rumpf
	_box(node, Vector3(0, 2.55, 0), Vector3(5.4, 0.3, 19.0), deckm)       # Deck
	# Bugkeil (45° gedrehte Box als Spitze)
	var bow := Node3D.new()
	bow.position = Vector3(0, 1.2, -12.2)
	bow.rotation.y = PI * 0.25
	node.add_child(bow)
	_box(bow, Vector3.ZERO, Vector3(4.3, 2.4, 4.3), hullm)
	for mz in [-4.5, 4.0]:
		_box(node, Vector3(0, 8.0, mz), Vector3(0.5, 11.0, 0.5), deckm)   # Mast
		_box(node, Vector3(0, 8.6, mz + 0.6), Vector3(7.0, 6.4, 0.16), sailm)  # Segel
	_box(node, Vector3(0, 3.6, 8.2), Vector3(4.2, 2.0, 3.0), deckm)       # Achterhaus


# Halb versunkenes WRACK: gekraengter Rumpf, gebrochener Mast, rostig — Mystery-Landmark.
static func build_wreck(parent: Node3D, pos2: Vector2, heading := 0.8) -> void:
	var node := Node3D.new()
	node.position = Vector3(pos2.x, TerrainWorld.SEA_Y - 2.6, pos2.y)     # tief eingesunken
	node.rotation.y = heading
	node.rotation.z = 0.42                                                # Kraengung ~24°
	parent.add_child(node)
	var rust := _mat(Color(0.38, 0.22, 0.15), 0.95)
	var rust2 := _mat(Color(0.28, 0.17, 0.13), 0.95)
	_box(node, Vector3(0, 1.4, 0), Vector3(7.0, 2.8, 26.0), rust)         # Rumpf
	_box(node, Vector3(0, 3.1, -6.0), Vector3(6.2, 0.4, 12.0), rust2)     # Deckrest
	_box(node, Vector3(0, 4.4, 6.5), Vector3(5.0, 2.6, 5.0), rust2)       # Aufbau
	var mast := Node3D.new()
	mast.position = Vector3(0, 4.2, -3.0)
	mast.rotation.x = 0.9                                                 # abgeknickt
	node.add_child(mast)
	_box(mast, Vector3(0, 4.0, 0), Vector3(0.5, 8.0, 0.5), rust)
