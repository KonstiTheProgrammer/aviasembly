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


static func _cylinder(parent: Node3D, pos: Vector3, bottom_radius: float, top_radius: float,
		height: float, segments: int, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.bottom_radius = bottom_radius
	cyl.top_radius = top_radius
	cyl.height = height
	cyl.radial_segments = segments
	mi.mesh = cyl
	mi.position = pos
	mi.material_override = mat
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


# Luftschiff-Werft: 100-m-Zeppelinhalle mit gewölbtem Stahldach, offenem Portal,
# Werkstätten, Kesselhaus, Tanks, Gleisen, Ankermast und einem Zeppelin-Rohbau.
# Die großen, kontrastreichen Formen sind für 200–800 m Sichtweite optimiert.
static func build_airship_factory(parent: Node3D, center: Vector3, yaw := 0.0) -> void:
	var node := Node3D.new()
	node.name = "Luftschiff_Fabrik"
	node.position = center
	node.rotation.y = yaw
	parent.add_child(node)

	var steel := Color(0.39, 0.46, 0.50)
	var steel_light := Color(0.52, 0.59, 0.61)
	var steel_dark := Color(0.16, 0.20, 0.23)
	var portal := Color(0.025, 0.035, 0.045)
	var profile := [
		Vector2(-22.0, 0.0), Vector2(-22.0, 9.5), Vector2(-20.5, 15.0),
		Vector2(-16.5, 20.0), Vector2(-10.0, 24.0), Vector2(0.0, 26.0),
		Vector2(10.0, 24.0), Vector2(16.5, 20.0), Vector2(20.5, 15.0),
		Vector2(22.0, 9.5), Vector2(22.0, 0.0),
	]
	var front_z := -49.0
	var rear_z := 49.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Gewölbte Außenhaut; alternierende Paneelwerte geben der Halle Fernstruktur.
	for i in range(profile.size() - 1):
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		var col := steel_light if i % 3 == 1 else (steel if i % 3 == 0 else _shade(steel, 0.86))
		_quad(st, Vector3(p0.x,p0.y,front_z), Vector3(p0.x,p0.y,rear_z),
			Vector3(p1.x,p1.y,rear_z), Vector3(p1.x,p1.y,front_z), col)
	# Geschlossene Rückwand als Fächer, vorne eine tiefdunkle offene Hallenöffnung.
	var rear_center := Vector3(0, 11.5, rear_z)
	var front_center := Vector3(0, 11.5, front_z - 0.03)
	for i in range(profile.size() - 1):
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		_tri(st, rear_center, Vector3(p0.x,p0.y,rear_z), Vector3(p1.x,p1.y,rear_z),
			_shade(steel, 0.78))
		_tri(st, front_center, Vector3(p1.x,p1.y,front_z - 0.03),
			Vector3(p0.x,p0.y,front_z - 0.03), portal)
	st.generate_normals()
	var hall := MeshInstance3D.new()
	hall.name = "Zeppelinhalle"
	hall.mesh = st.commit()
	hall.material_override = _building_mat()
	node.add_child(hall)

	var steel_mat := _mat(steel, 0.52)
	var dark_mat := _mat(steel_dark, 0.48)
	var glass_mat := _mat(Color(0.08, 0.17, 0.22), 0.32)
	var brick_mat := _mat(Color(0.43, 0.20, 0.14), 0.94)
	var roof_mat := _mat(Color(0.24, 0.29, 0.32), 0.64)
	var concrete := _mat(Color(0.48, 0.49, 0.46), 0.94)
	var brass := _mat(Color(0.65, 0.50, 0.20), 0.48)
	var timber := _mat(Color(0.27, 0.20, 0.14), 0.92)

	# Zwei zurückgeschobene Torflügel und markante Portalpfosten.
	for sx in [-1.0, 1.0]:
		_box(node, Vector3(sx * 17.8, 10.5, front_z - 0.55),
			Vector3(7.8, 21.0, 0.85), steel_mat)
		_box(node, Vector3(sx * 22.35, 10.0, front_z - 0.15),
			Vector3(0.70, 20.0, 1.0), dark_mat)
	_box(node, Vector3(0, 0.18, 0), Vector3(46.0, 0.36, 101.0), concrete)

	# Transversale Außenrippen: wenige kräftige Linien statt vieler Detailstreben.
	for z in [-36.0, -12.0, 12.0, 36.0]:
		for sx in [-1.0, 1.0]:
			_box(node, Vector3(sx * 22.18, 8.0, z), Vector3(0.42, 16.0, 0.65), dark_mat)
		_box(node, Vector3(0, 25.45, z), Vector3(9.0, 0.48, 0.65), dark_mat)
	# Große Seitenfenster als zusammenhängende Industrie-Bänder.
	for sx in [-1.0, 1.0]:
		for z in [-29.0, -10.0, 9.0, 28.0]:
			_box(node, Vector3(sx * 22.23, 8.2, z), Vector3(0.18, 3.0, 10.5), glass_mat)

	# Werkstattflügel und Verwaltungsbau.
	_box(node, Vector3(32.0, 4.0, 12.0), Vector3(17.0, 8.0, 42.0),
		_mat(Color(0.50, 0.43, 0.34), 0.90))
	_gable_roof(node, Vector3(32.0, 8.0, 12.0), 19.0, 44.0, 4.4,
		roof_mat.albedo_color, Color(0.50, 0.43, 0.34))
	for z in [-1.0, 12.0, 25.0]:
		_box(node, Vector3(23.45, 4.3, z), Vector3(0.16, 2.2, 5.8), glass_mat)
	_box(node, Vector3(31.0, 5.0, -29.0), Vector3(19.0, 10.0, 20.0),
		_mat(Color(0.57, 0.59, 0.56), 0.88))
	_box(node, Vector3(31.0, 10.35, -29.0), Vector3(20.0, 0.7, 21.0), roof_mat)
	for x in [25.0, 31.0, 37.0]:
		_box(node, Vector3(x, 5.7, -39.2), Vector3(3.0, 2.2, 0.18), glass_mat)

	# Kesselhaus: zwei gestufte Backsteinschlote, weithin sichtbare Vertikalen.
	_box(node, Vector3(32.0, 3.5, 39.0), Vector3(18.0, 7.0, 15.0), brick_mat)
	for x in [28.0, 36.0]:
		_cylinder(node, Vector3(x, 18.0, 42.0), 1.65, 1.20, 29.0, 10, brick_mat)
		_cylinder(node, Vector3(x, 32.8, 42.0), 1.48, 1.48, 0.7, 10, brass)

	# Drei Gastanks, auf der freien Hallenseite als eigene industrielle Silhouette.
	for i in 3:
		var tz := 22.0 + float(i) * 15.0
		_cylinder(node, Vector3(-34.0, 4.0, tz), 5.0, 5.0, 8.0, 12, steel_mat)
		_cylinder(node, Vector3(-34.0, 8.25, tz), 4.7, 0.0, 1.5, 12, steel_mat)

	# Werftgleise führen vom dunklen Tor zum Ankermast.
	for sx in [-1.0, 1.0]:
		_box(node, Vector3(sx * 7.2, 0.10, -77.0), Vector3(0.32, 0.18, 56.0), dark_mat)
	for z in range(-102, -50, 6):
		_box(node, Vector3(0, 0.07, float(z)), Vector3(18.0, 0.12, 0.36), timber)

	# Ankermast mit Leuchtknauf.
	_cylinder(node, Vector3(0, 17.0, -107.0), 3.1, 0.65, 34.0, 8, dark_mat)
	_box(node, Vector3(0, 25.0, -107.0), Vector3(13.0, 0.55, 0.55), steel_mat)
	_glow(node, Vector3(0, 35.0, -107.0), Color(1.0, 0.52, 0.18))

	# Halbfertiger Zeppelin neben der Halle: sehr leichtes 12x6-Low-Poly-Ellipsoid.
	var envelope := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 12
	sph.rings = 6
	envelope.mesh = sph
	envelope.position = Vector3(-37.0, 12.0, -18.0)
	envelope.scale = Vector3(7.2, 7.2, 23.0)
	envelope.material_override = _mat(Color(0.66, 0.70, 0.68), 0.56)
	envelope.name = "Zeppelin_Rohbau"
	node.add_child(envelope)
	_box(node, Vector3(-37.0, 3.7, -20.0), Vector3(5.2, 2.0, 9.0), dark_mat)
	_box(node, Vector3(-37.0, 12.0, 5.8), Vector3(0.55, 13.0, 6.0), steel_mat)
	_box(node, Vector3(-37.0, 12.0, 5.8), Vector3(13.0, 0.55, 6.0), steel_mat)


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


# --- FELSENTOR ------------------------------------------------------------------------
# Ein LOCH IN EINER FELSRIPPE am Eingang des Hochtals, durch das man hindurchfliegt. Das
# einzige Wahrzeichen mit KOLLISION.
#
# WARUM ALS EIGENE GEOMETRIE UND NICHT ALS GELAENDE: TerrainWorld.height_at liefert genau
# EINE Hoehe je Punkt. Ein Bogen braucht an derselben Stelle zwei Flaechen uebereinander —
# Boden und Torbogen. Ein Hoehenfeld kann das grundsaetzlich nicht, egal wie man die
# Massive stellt. Deshalb ein Mesh.
#
# WARUM MIT KOLLISION, anders als alle anderen Wahrzeichen hier: durch massiven Fels
# hindurchzufliegen sieht kaputt aus, und das Tor soll eine Mutprobe sein, kein Poster.
# Die Kollisionsflaeche kommt aus DENSELBEN Dreiecken wie das Sichtnetz — nicht aus einer
# vereinfachten Huelle, sonst schlaegt man in der Toroeffnung gegen unsichtbares Zeug.
#
# FORM — UND WARUM DIE ERSTE FASSUNG FALSCH WAR: die war ein geloftetes Band ueber zwei
# symmetrischen Fusskloetzen, also ein freistehender REIFEN. tools/_tor_form.gd hat das
# nachgemessen: 56 m Fels ueber dem Scheitel und darueber offener Himmel, Oeffnung
# 328 x 224 m — also BREITER als hoch. Ein durchgewittertes Loch sieht anders aus:
#   * Es sitzt IN einer Rippe, die ueber dem Scheitel WEITERLAEUFT. Hier steigt sie als
#     gestufte Felsnadel auf und bildet den hoechsten Punkt des ganzen Gebildes — der
#     Bogenscheitel ist NICHT die Spitze.
#   * Die beiden Beine sind sehr ungleich: +X ein massiger geschichteter Pfeiler,
#     -X eine schlanke Saeule, die sich nach UNTEN verjuengt und schraeg steht.
#   * Die Oeffnung ist HOEHER ALS BREIT und spitzbogig, der Scheitel aussermittig.
#   * An beiden Fuessen liegen Schuttkegel aus einzelnen, kantigen Bloecken.
#
# WICKLUNG: der Kopfkommentar der Datei warnt, der Bogen sei einmal komplett schwarz
# gewesen, weil die Wicklung falsch war. Das galt fuer das GELOFTETE BAND. Bei den
# heutigen Quadern war die damals gewaehlte Richtung ihrerseits verkehrt: jede
# Aussenflaeche wurde weggecullt und man sah in offene Kaesten hinein. Nachgemessen und
# korrigiert — die Begruendung steht bei _fels_tri und ist dort nachprufbar beschrieben.
#
# GEBAUT AUS WAAGERECHTEN BAENKEN statt als geloftetes Rohr. Das ist keine Deko: Fels
# dieser Art verwittert entlang seiner Schichtfugen, und ein Stapel Baenke liefert die
# Stufen im Bogeninneren (Kragbogen) gratis. Der Loft hatte ausserdem eine stille Falle —
# sein Querschnittsrahmen drehte sich NICHT mit dem Bogen mit, wodurch die Beine
# unterschiedlich dick wurden, ohne dass das jemand so entworfen haette. Baenke sind genau
# das, was tools/_tor_form.gd rastert: Form und Messung reden ueber dasselbe.
#
# ACHSEN: build_felsentor wird mit yaw = atan2(TAL_RICHTUNG.x, TAL_RICHTUNG.y) gedreht,
# lokales +Z zeigt damit talauswaerts, lokales +X quer dazu. DIE DICKE SEITE LIEGT BEI +X.
# ACHTUNG BEIM VERGLEICHEN: im Anflugbild (Posen tal_tor, tal_tor_nah) erscheint +X
# LINKS, in der Ausgabe von tools/_tor_form.gd dagegen als "rechts" — dort ist "links"
# schlicht die kleinere x-Koordinate.
#
# spannweite = Breitenmass des Gebildes, hoehe = LICHTE HOEHE des Lochs ueber der
# Fusslinie (die Felsnadel steht noch einmal 55 Prozent davon obendrauf),
# breite = Tiefe des Fels laengs der Flugrichtung.
# gelaende = TerrainWorld; wird nur fuer die Schutthalde gebraucht (Decke und Bloecke
# muessen auf dem echten Hang liegen). Ohne das Argument entfaellt sie.
const TOR_TS := 0.40          # Kaempferhoehe als Anteil der lichten Hoehe

static var _fels_vertex_mat: StandardMaterial3D


static func _fels_mat() -> StandardMaterial3D:
	if _fels_vertex_mat == null:
		_fels_vertex_mat = StandardMaterial3D.new()
		_fels_vertex_mat.albedo_color = Color.WHITE
		_fels_vertex_mat.vertex_color_use_as_albedo = true
		_fels_vertex_mat.roughness = 0.96
		# SCHATTENAUFHELLUNG. Anders als das Gelaende, das fast nur flach liegende Dreiecke
		# zeigt, besteht dieser Fels aus grossen SENKRECHTEN Flaechen. Die von der Sonne
		# abgewandten standen im Bild als schwarzblaue Wand da, obwohl die Grundfarbe warm
		# graubraun ist. Eine schwache Eigenfarbe hebt genau die an und laesst die
		# besonnten Flaechen fast unveraendert.
		_fels_vertex_mat.emission_enabled = true
		_fels_vertex_mat.emission = Color(0.44, 0.37, 0.29)
		# 0.20 STATT 0.40. Die 0.40 waren die Antwort auf schwarze Flaechen, die es gar nicht
		# gab: die Wicklung war umgekehrt (siehe _fels_tri), das echte Licht traf deshalb
		# ueberall die falsche Seite. Mit richtiger Wicklung leuchtete die Eigenfarbe den
		# ganzen Bogen weiss aus — im Bild stand ein Gipsmodell im Tal.
		# NICHT WEITER HERUNTER ALS 0.20: die Bogenlaibung liegt als einzige grosse Flaeche
		# des Tors ganztaegig im Schlagschatten und faellt darunter ins Schwarze. Gemessen
		# hat das Referenzbild dort 122/117/99, also einen klar durchgezeichneten Mittelton.
		# Die Aufhellung wirkt absolut und faellt auf den besonnten Flaechen kaum auf; die
		# Grundfarbe ist als Ausgleich um denselben Betrag dunkler gesetzt.
		_fels_vertex_mat.emission_energy_multiplier = 0.20
	return _fels_vertex_mat


## Innenkante des Lochs (die Seite, an der man vorbeifliegt) auf der Hoehe t = y / hoehe.
## seite = +1 dicke Seite (lokales +X), -1 duenne Seite (-X). xm ist die Scheitel-x.
##
## FORM: unter dem Kaempfer TOR_TS steht die Kante fast senkrecht, darueber schliesst ein
## SPITZBOGEN. Der Exponent 1.6 in (1 - u^1.6) ist genau der Unterschied zwischen spitz
## und stumpf: ein Kreisbogen laeuft mit SENKRECHTER Tangente in den Scheitel und wird
## dort rund; hier bleibt die Steigung endlich, der Scheitel bekommt eine Spitze. Genau
## daran haengt, dass die Oeffnung hoeher als breit wirkt.
static func _tor_loch(t: float, seite: float, s_w: float, xm: float) -> float:
	var kae := (0.19 if seite > 0.0 else -0.235) * s_w     # Weite am Kaempfer
	var fus := (0.21 if seite > 0.0 else -0.275) * s_w     # unten etwas weiter
	if t < TOR_TS:
		return lerpf(fus, kae, smoothstep(0.0, 1.0, t / TOR_TS))
	var u := (t - TOR_TS) / (1.0 - TOR_TS)
	return xm + (kae - xm) * (1.0 - pow(u, 1.6))


## Aussenkante des Beins auf der Hoehe t = y / hoehe — die SOLLKURVE. Der Sockel
## (_tor_sockel) und der Zufallslauf der Flucht (_flucht) kommen in build_felsentor dazu.
##
## SIE WIRD DIREKT VORGEGEBEN, NICHT ALS INNENKANTE PLUS DICKE. Der erste Versuch rechnete
## sie aus einer nach oben abnehmenden Dicke — dabei wanderte die Aussenkante des dicken
## Pfeilers 219 m nach innen, und im Bild stand statt eines Tors ein Tipi. Der massige
## Pfeiler des Referenzbildes steht dagegen fast senkrecht; nur die Laibung kruemmt sich.
##
## Die Ungleichheit der beiden Beine ist der Kern der Form, nicht Zufall: +X ist ein
## rund 230 m breiter Pfeiler ueber die ganze Hoehe, -X eine 30 bis 70 m schlanke Saeule,
## die sich nach UNTEN verjuengt. tools/_tor_form.gd misst das Verhaeltnis zwischen 15 und
## 55 Prozent der Gesamthoehe und verlangt mindestens 1.5.
##
## DIE FUSSVERBREITERUNG STAND FRUEHER HIER und war der groesste Einzelfehler des Bildes:
## ein Term (1 - smoothstep(0, 0.30, t)) * s_w * 0.22 zog die Aussenkante ueber die
## unteren 126 m stetig um 114 m herein. Bei 13 m Bankhoehe sind das zehn Baenke, die alle
## um rund 10 m in DIESELBE Richtung zuruecktreten. Gemessen hatte unsere Aussenkante auf
## 310 Bildzeilen nur 19 Richtungswechsel und wich 2.9 px von ihrer eigenen Sollkurve ab;
## das Referenzbild hat 103 Wechsel und 18.1 px. Im Bild war das eine Treppe aus
## gestapelten Platten. _tor_sockel macht daraus zwei grosse Absaetze.
static func _tor_aussen(t: float, seite: float, s_w: float, h: float, xm: float) -> float:
	if seite > 0.0:
		# FAST SENKRECHT. Beim ersten Versuch lief diese Kante von 0.66 auf 0.50 zusammen;
		# zusammen mit der einlaufenden duennen Seite ergab das im Bild eine Pyramide mit
		# Schlitz. Erst eine stehende Aussenkante macht daraus eine WAND, in der ein Loch
		# sitzt — und erst dann setzt sich die Felsnadel darueber als eigene Form ab.
		# LEICHT NACH AUSSEN GENEIGT (0.52 -> 0.60 statt 0.52 -> 0.49). Das ist keine
		# Kosmetik, sondern die Antwort auf den gemessenen Himmelspalt: die Felsrippe
		# daneben (Main._hochgebirge) steigt mit rund 1.3 m je Meter an, ihre Oberflaeche
		# wandert mit der Hoehe also nach AUSSEN. Eine senkrechte Beinkante entfernt sich
		# von ihr mit jedem Meter Hoehe weiter; eine mitwandernde bleibt in ihrer Naehe, und
		# der Pfeiler liest sich als Teil der Flanke statt als Saeule davor.
		# MEHR GEHT NICHT: bei 0.66 lehnte sich das Bein sichtbar ueber den Hang und der
		# Bogen sah aus wie ein umkippender Turm.
		return lerpf(0.52, 0.60, t) * s_w
	var d := lerpf(0.085, 0.150, t / TOR_TS) if t < TOR_TS \
		else lerpf(0.150, 0.260, (t - TOR_TS) / (1.0 - TOR_TS))
	return _tor_loch(t, seite, s_w, xm) - h * d


## Der Fuss des Beins: Abstand der Aussenflucht nach AUSSEN gegen die Sollkurve, in Metern
## und immer >= 0. Er sorgt dafuer, dass der Pfeiler aus dem Hang WAECHST statt wie eine
## Saeule daraufgestellt zu sein.
##
## ZWEI ABSAETZE, KEINE RAMPE — das ist der ganze Punkt dieser Funktion. Ein Bein, das
## nach unten stetig breiter wird, ergibt ueber zehn Baenke zehn gleichsinnige
## Ruecksprunge, und zehn gleichsinnige Ruecksprunge sind eine Treppe, kein Fels. Fels
## bricht anders: er steht ueber viele Meter senkrecht und tritt dann auf einmal um einen
## halben Bankdurchmesser zurueck. Hier sind es zwei Sprunge von rund 51 m und 37 m am
## dicken Pfeiler statt zehn von je 10 m.
##
## Die beiden Sprunghoehen liegen auf festen t-Werten, NICHT auf einer Bankgrenze. Welche
## Bank den Absatz traegt, entscheidet damit der Zufallslauf der Bankhoehen — der Absatz
## sitzt nicht auf einer runden Zahl, und Absatz und Schichtfuge fallen nicht zusammen.
## Linke (zum Scheitel zeigende) Kante der Felsnadel auf ihrer Hoehe v = 0 .. 1.
##
## ZWEI ABSCHNITTE STATT EINER KURVE. Eine durchgehende Interpolation ueber die ganze
## Nadelhoehe war auf halber Hoehe noch 202 m breit bei 231 m Gesamthoehe, also ein Stumpf;
## Bogen und Nadel lasen sich zusammen als EIN Trapez. So zieht sich die Kante schnell an
## den Scheitel heran und BLEIBT dort, bis die Felsdecke ueber dem Scheitel steht
## (v = 0.76); erst darueber laeuft die Nadel in eine schmale Spitze aus.
##
## Eigene Funktion, weil build_felsentor sie je Bank ZWEIMAL braucht — unten und oben, denn
## die Baenke sind Trapeze (siehe _tor_bank).
static func _nadel_li(v: float, li0: float, s_w: float, xm: float) -> float:
	if v > 0.76:
		return lerpf(xm - 24.0, xm + 0.06 * s_w, (v - 0.76) / 0.24)
	return lerpf(li0, xm - 24.0, minf(v / 0.55, 1.0))


static func _tor_sockel(t: float, seite: float, s_w: float) -> float:
	var a := s_w * (0.17 if seite > 0.0 else 0.15)
	if t < 0.085:
		return a
	if t < 0.235:
		return a * 0.42
	return 0.0


## Ein Dreieck des Felsens. Die WICKLUNG wird gegen den Blockmittelpunkt selbst korrigiert
## statt geraten — bei konvexen Bloecken ist das exakt. In diesem Projekt hat eine von Hand
## geratene Reihenfolge schon einmal einen komplett schwarzen Bogen erzeugt.
## Die Helligkeit je Flaechenrichtung wird in die Vertexfarbe gebacken (wie bei den
## Haeusern): so bleibt die Form auch aus 1 km und bei flach stehender Sonne lesbar.
static func _fels_tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3,
		m: Vector3, col: Color) -> void:
	# DIE RICHTUNG DIESES VERGLEICHS WAR VERKEHRT HERUM, und das war der groesste einzelne
	# Bildfehler des Tors. Godot zeichnet eine Flaeche, wenn ihre Ecken VON DER KAMERA AUS
	# im Uhrzeigersinn stehen; fuer eine solche Reihenfolge zeigt die Rechte-Hand-Normale
	# (p1-p0) x (p2-p0) vom Betrachter WEG, bei einem Block also nach INNEN. Die alte Zeile
	# drehte die Reihenfolge so, dass diese Normale nach AUSSEN zeigte — damit war jede
	# Aussenflaeche des Tors rueckseitig und wurde weggecullt. Sichtbar blieb, was man
	# durch den fehlenden Deckel sah: die INNENSEITE der jeweils gegenueberliegenden Wand.
	# Nachgewiesen, indem die sechs Blockflaechen einzeln eingefaerbt wurden — im Anflug
	# war der Pfeiler in der Farbe der Deck- und der RUECKwand gestrichen, die Vorderwand
	# kam im Bild ueberhaupt nicht vor.
	# Genau daher kam der Befund "Treppe aus gestapelten Platten": man sah in offene
	# Kaesten hinein, und die Kanten zwischen Rueck-, Decken- und Seitenwand liefen als
	# Dreiecksfahnen quer ueber den Fels. Ausserdem lief die Beleuchtung ueber
	# generate_normals() auf den nach innen zeigenden Normalen, der Fels war deshalb flach
	# und richtungslos ausgeleuchtet.
	# ACHTUNG: der Kopfkommentar zu build_felsentor stammt aus der Zeit des gelofteten
	# Bandes; dort war der Bogen bei der anderen Wicklung schwarz. Bei Quadern ist es
	# umgekehrt, und das hier ist gemessen, nicht geraten.
	var n := (p1 - p0).cross(p2 - p0)
	var q1 := p1
	var q2 := p2
	if n.dot((p0 + p1 + p2) / 3.0 - m) > 0.0:
		q1 = p2
		q2 = p1
		n = -n
	# n zeigt nach der Korrektur nach INNEN; fuer die eingebackene Helligkeit zaehlt die
	# Aussenrichtung.
	var nn := -n.normalized()
	# Die eingebackene Helligkeit kommt ZUSAETZLICH zum echten Licht und muss deshalb um
	# 1.0 herum bleiben. Sie hat nur eine Aufgabe: den Fels auch dann noch lesbar zu
	# machen, wenn die Sonne flach steht und zwei benachbarte Flaechen fast gleich hell
	# waeren. Der waagerechte Anteil bleibt klein — waagerechte Deckflaechen bekommen von
	# der hochstehenden Sonne ohnehin das meiste Licht, und noch einmal 22 Prozent
	# obendrauf machten aus jeder Bankkante einen weissen Strich.
	# UNTERSEITEN WERDEN JETZT ABGEDUNKELT (der Term mit minf). Vorher war das unmoeglich:
	# nn zeigte wegen der verkehrten Wicklung nach innen, "unten" und "oben" waren
	# vertauscht. Eine dunkle Unterseite ist genau das, was einen Ueberhang als Ueberhang
	# lesbar macht statt als hellen Streifen.
	var c2 := _shade(col, 0.94 + 0.10 * maxf(nn.y, 0.0) + 0.18 * minf(nn.y, 0.0)
		+ 0.07 * nn.x)
	st.set_color(c2); st.add_vertex(p0)
	st.set_color(c2); st.add_vertex(q1)
	st.set_color(c2); st.add_vertex(q2)


## Kantiger Felsblock aus ACHT frei gesetzten Ecken (unten 0..3, oben 4..7, jeweils in der
## Reihenfolge -x-z, +x-z, +x+z, -x+z). Acht Ecken statt Mitte+Groesse, weil die Baenke
## Trapeze mit unterschiedlicher Tiefe oben und unten sind.
static func _fels_quader(st: SurfaceTool, e: Array, col: Color) -> void:
	var m := Vector3.ZERO
	for v: Vector3 in e:
		m += v
	m /= 8.0
	for s: Array in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5],
			[2, 3, 7, 6], [3, 0, 4, 7]]:
		_fels_tri(st, e[s[0]], e[s[1]], e[s[2]], m, col)
		_fels_tri(st, e[s[0]], e[s[2]], e[s[3]], m, col)


## Eine waagerechte Felsbank von x0 bis x1 zwischen y0 und y1, in zwei bis drei Bloecke
## unterteilt.
##
## ZWEI REGELN, die nicht verhandelbar sind:
##  1. Die Trennkanten der Bloecke liegen EXAKT aufeinander. Ein Spalt dazwischen waere in
##     der Silhouette ein drittes Bein und wuerde tools/_tor_form.gd die Zeile verderben —
##     im Bild waere er ein Lichtschlitz mitten im Fels.
##  2. Die Oberkante wird nur nach OBEN verwuerfelt, nie nach unten. Die naechste Bank
##     beginnt bei y1, die Baenke ueberlappen sich dadurch; verwuerfelte man nach unten,
##     entstuenden waagerechte Ritzen durch den ganzen Pfeiler.
## loch_seite sagt, welches Ende die Bogeninnenseite ist (0 = x0, 1 = x1, -1 = keins).
## Sie wird nur schwach angefasst, das Aussenende dafuer kraeftig — Verwitterung frisst
## von aussen, und die lichte Weite soll nicht zufaellig wandern.
##
## DIE BANK IST EIN TRAPEZ, KEIN RECHTECK: xu sind ihre beiden x-Kanten UNTEN (links,
## rechts), xo dieselben OBEN. Das ist der Unterschied zwischen einem Bogen und einer
## Treppe. Vorher hatte jede Bank oben und unten dasselbe x; die Laibung des Bogens
## entstand dadurch als Kragstufe, und jede Bank sprang gegenueber der darunter um die
## x-Aenderung der Laibungskurve ins Loch — bis zu 25 m auf 15 m Bankhoehe. Von der
## Anflugkamera aus, die 540 m unter dem Scheitel steht, ist so eine Stufe keine Stufe,
## sondern eine frei ueber der Oeffnung schwebende Platte mit heller Unterseite. Mit dem
## Trapez laeuft die Laibung als geschlossener Streckenzug durch, ohne eine einzige
## waagerechte Flaeche. Die Absaetze der AUSSENflucht bleiben davon unberuehrt: die setzt
## build_felsentor bewusst nur alle vier bis sieben Baenke, und nur dort soll es eine
## echte Stufe geben.
##
## loch_seite sagt, welches Ende die Bogeninnenseite ist (0 = links, 1 = rechts,
## -1 = keins). Sie wird nur schwach angefasst — die lichte Weite soll nicht zufaellig
## wandern.
##
## kluft/kluft_z/kluft_d sind die SENKRECHTE FUGENSCHAR (siehe build_felsentor): kluft
## haelt die festen x-Positionen der Kluefte, kluft_z je Spalte dazwischen einen
## Tiefenversatz und kluft_d je Spalte ihre halbe Tiefe, beides als Anteil der Tortiefe.
## Alle drei gelten fuer das GANZE Tor, nicht fuer eine Bank — genau das macht aus einer
## Fuge eine durchgehende senkrechte Kante.
static func _tor_bank(st: SurfaceTool, rng: RandomNumberGenerator, xu: Vector2, xo: Vector2,
		y0: float, y1: float, tiefe: float, loch_seite: int, grund: Color, zb := 0.0,
		kluft := PackedFloat32Array(), kluft_z := PackedFloat32Array(),
		kluft_d := PackedFloat32Array()) -> void:
	var hb := y1 - y0
	# BLOCKGRENZEN. Sie wurden frueher JE BANK neu gewuerfelt (drei bis vier Bloecke von
	# rund 55 m). Gemessen war das Ergebnis eine Mauer: waagerechte Kantenenergie 0.166,
	# senkrechte 0.114, Verhaeltnis 1.45 — im Referenzbild ist es 0.92, dort ueberwiegen
	# also die SENKRECHTEN. Der Grund ist einfach: eine je Bank neu gewuerfelte Fuge ist
	# nur 7 bis 23 m lang und faellt neben der durchgehenden Schichtfuge nicht auf.
	# Gebankter Fels hat ZWEI Fugenscharen, und die senkrechte laeuft ueber viele Baenke
	# DURCH. Deshalb stehen die Trennstellen jetzt fest (kluft) und jede Spalte behaelt
	# ueber die ganze Hoehe ihren eigenen Tiefenversatz (kluft_z).
	# DIE 16 M SIND EINE SPLITTERSPERRE: eine Kluft dicht an der Bankkante ergaebe einen
	# fadenduennen Block, und der zeigt im Anflug nur seine beiden Seitenflaechen.
	# Eine Kluft zaehlt nur, wenn sie UNTEN WIE OBEN im Inneren der Bank liegt. Bei einer
	# schraegen Bankkante (Laibung) wandert das Bankende ueber die Hoehe; eine Kluft, die
	# nur auf einer der beiden Hoehen drinliegt, ergaebe einen Block mit negativer Breite.
	var e_lo := maxf(xu.x, xo.x)
	var e_hi := minf(xu.y, xo.y)
	var kanten := PackedFloat32Array()
	kanten.append(0.0)                         # Platzhalter: Rand, kommt aus xu/xo
	var s0 := 0                                # Index der ersten Spalte in dieser Bank
	for i in kluft.size():
		var kv: float = kluft[i]
		if kv <= e_lo + 16.0:
			s0 = i + 1
		elif kv < e_hi - 16.0:
			kanten.append(kv)
	kanten.append(0.0)                         # Platzhalter: Rand
	var n := kanten.size() - 1
	# HIER STAND EINMAL "EINEN RANDBLOCK GANZ WEGLASSEN, hier und da" (22 Prozent je Bank).
	# Gedacht war eine tiefe Kerbe; gemessen war es der groesste Einzelposten in der
	# Silhouette. tools/_tor_flucht.gd zaehlte am dicken Bein 34 Spruenge der Aussenkante
	# mit im Mittel 48 m — auf einem 190 m breiten Pfeiler. Der Grund: der weggelassene
	# Block ist eine ganze Spalte von 40 bis 92 m Breite, und er fehlt nur in EINER Bank.
	# Die Kante springt also um eine Spaltenbreite herein und eine Bank spaeter wieder
	# heraus. Aus 300 m Naehe war jede dieser Kerben eine quer durch den Pfeiler laufende
	# Doppelkante mit heller Ober- und dunkler Unterseite — ein Plattenschlitz, keine Kerbe.
	# Kerben macht jetzt die Aussenflucht, und die springt in Gruppen von vier bis sieben
	# Baenken; eine Kerbe ist damit 60 bis 100 m hoch statt 15 m und liest sich als Form.
	for i in n:
		# Nur die AEUSSEREN Spaltenkanten stehen unten und oben verschieden; die Kluefte
		# dazwischen sind senkrechte Fugen und stehen ueber die ganze Hoehe fest.
		var au: float = xu.x if i == 0 else kanten[i]
		var ao: float = xo.x if i == 0 else kanten[i]
		var bu: float = xu.y if i == n - 1 else kanten[i + 1]
		var bo: float = xo.y if i == n - 1 else kanten[i + 1]
		# Am LOCHENDE nur eine Fase von wenigen Metern (die lichte Weite soll nicht
		# wandern); die grosse Bewegung am Aussenende steckt schon in xu/xo. Unten und oben
		# derselbe Wert, sonst kippte die Fase die Laibungskante.
		if i == 0 and loch_seite == 0:
			var fa := rng.randf_range(-2.0, 3.0)
			au -= fa
			ao -= fa
		if i == n - 1 and loch_seite == 1:
			var fa := rng.randf_range(-2.0, 3.0)
			bu += fa
			bo += fa
		# EIN VORSPRINGENDER BLOCK MUSS AUCH IN DER TIEFE VORSPRINGEN — sonst liegt seine
		# Vorderflaeche in derselben Ebene wie die des Blocks aus der Nachbarbank, mit dem
		# er sich ueberlappt, und zwei deckungsgleiche Flaechen streiten sich um die Tiefe.
		# Im Bild war das ein Teppich aus hell-dunklen DREIECKSPAAREN quer ueber den
		# Pfeiler; die Diagonale darin ist die Kante zwischen den beiden Dreiecken einer
		# Flaeche und verraet den Tiefenstreit eindeutig. Der Ueberstand wird gewuerfelt
		# (5 bis 12 Prozent der Tortiefe), damit auch zwei uebereinanderliegende
		# Vorspruenge nicht zufaellig auf derselben Ebene landen.
		# Bloecke OHNE Vorsprung enden dagegen exakt auf der Bankgrenze: dort stossen
		# Deckflaeche und Bodenflaeche Ruecken an Ruecken, und eine von beiden wird
		# ohnehin weggecullt — kein Streit, keine Ritze.
		# 0.10 statt 0.32: die Tiefenstruktur traegt jetzt die Kluftspalte (siehe unten),
		# und jeder zusaetzliche Vorsprung bringt wieder eine WAAGERECHTE Deckflaeche mit.
		# Bei 0.32 war aus 300 m Naehe jede Bank ein eigenes Tablett mit heller Oberseite
		# und dunkler Unterseite — der Pfeiler las sich als Stapel Pappkarten.
		# 0.05 statt 0.10: die Kamera im Anflug steht auf 150 m und das Tor ist 690 m hoch —
		# man sieht das Ding fast ganz von UNTEN. Ein vorspringender Block zeigt dort nicht
		# seine Deckflaeche, sondern seine UNTERSEITE, und die liegt als heller Streifen quer
		# vor dem dahinterliegenden Fels. Jeder zwanzigste Block reicht, um die Flucht zu
		# brechen; jeder zehnte war schon wieder ein Muster.
		var reck := rng.randf() < 0.05
		var vor := tiefe * rng.randf_range(0.03, 0.07) if reck else 0.0
		# DIE HALBE TIEFE GEHOERT ZUR SPALTE, NICHT ZUR BANK. Sie wurde frueher je Bank neu
		# gewuerfelt (0.92 bis 1.0 der halben Tortiefe, also bis zu 4 m Unterschied). Das
		# klingt nach nichts, war im Bild aber der groesste Einzelposten: die Vorderflaeche
		# jeder Bank sass ein paar Meter vor oder hinter der darunter, und im leicht abwaerts
		# gerichteten Anflug wurde daraus je Bank ein 190 m breiter, hell beleuchteter
		# WAAGERECHTER Streifen. Vierzig davon uebereinander sind genau das, was die Kritik
		# als "Treppe aus gestapelten Platten" gemessen hat (Kantenenergie waagerecht zu
		# senkrecht 1.39 gegen 1.00 im Referenzbild).
		# Je Spalte fest heisst dagegen: die Baenke einer Fluchtgruppe fluchten auch in der
		# TIEFE exakt, und aus vier bis sieben Baenken wird EINE geschlossene Wand, deren
		# einzige Zeichnung das Fugennetz ist.
		var kd := 1.0
		if not kluft_d.is_empty():
			kd = kluft_d[mini(s0 + i, kluft_d.size() - 1)]
		var d0 := tiefe * 0.5 * kd + vor
		var d1 := tiefe * 0.5 * kd + vor
		# TIEFENVERSATZ NUR ENTLANG DER KLUEFTE. Das Tor ist 520 m breit, aber nur 105 m
		# tief; jeder Meter Versatz in z erzeugt im Anflug eine Kante. Entscheidend ist,
		# WELCHE: ein je Bank neu gewuerfelter Versatz ergibt einen waagerechten Sims —
		# davon lagen einmal zweihundert ueber dem Pfeiler und das Bild war ein
		# Geroellhaufen. Ein Versatz, der ueber die ganze Hoehe zur SPALTE gehoert, ergibt
		# dagegen eine durchgehende senkrechte Kante, und genau die fehlte gegenueber dem
		# Referenzbild.
		# DIE STREUUNG JE BANK IST GANZ WEG (frueher +-0.02 der Tortiefe, also +-2 m). Sie
		# stammte aus der Zeit, als es kluft_z noch nicht gab, und hatte denselben Fehler wie
		# die gewuerfelte halbe Tiefe darueber: sie verschiebt eine GANZE Bank in z und legt
		# damit einen waagerechten Sims ueber die volle Beinbreite. Zwei Meter reichen dafuer
		# aus, wenn man leicht von oben darauf blickt.
		var kz := 0.0
		if not kluft_z.is_empty():
			kz = kluft_z[mini(s0 + i, kluft_z.size() - 1)]
		var zc := zb + tiefe * kz
		# Nur der vorspringende Block bekommt auch eine eigene Ober- und Unterkante. Gab
		# man sie JEDEM Block, zeigte jeder eine beleuchtete Deck- und eine dunkle
		# Seitenflaeche; bei fuenf Bloecken auf vierzig Baenken waren das zweihundert
		# Stufen, und die legten sich als regelmaessiges Gitter ueber den Pfeiler —
		# Schuttgeroell statt Fels. Gebankter Fels sieht anders aus: die Schichtfuge laeuft
		# ueber weite Strecken durch, und nur hier und da steht ein Block vor.
		# Verschoben wird NUR NACH OBEN, und die Unterkante bleibt exakt auf der Bankgrenze.
		# Frueher ging es auch nach unten (bis 4 m). Von der Anflugkamera aus, die 540 m
		# unter dem Scheitel steht, ist jede nach unten verschobene Kante eine freiliegende
		# Blockunterseite — genau die Signatur "gestapelte Platte". Nach oben verschoben
		# verdeckt der Block dagegen seine eigene Deckflaeche.
		var ob := y1 + (rng.randf_range(2.0, minf(hb * 0.40, 6.0)) if reck else 0.0)
		var ub := y0
		# STREUUNG DER BLOCKHELLIGKEIT — die einzige Zeichnung, die der Fels zwischen zwei
		# Fluchtabsaetzen noch hat, seit die Baenke exakt fluchten. Gemessen an
		# Renderausschnitten: Kantenenergie waagerecht 2.1 gegen 9.5 im Referenzbild, das
		# Verhaeltnis waagerecht zu senkrecht war mit 0.50 gegen 1.05 ins Gegenteil gekippt —
		# die senkrechte Kluftschar allein trug das Bild, die Schichtung fehlte. Sie darf
		# hier NICHT als Geometrie zurueckkommen: jede Bank, die gegen ihre Nachbarin
		# versetzt steht, ist von unten gesehen wieder eine Platte. Als Farbe kostet sie
		# nichts und wirft keinen falschen Schatten.
		var col := _shade(grund, rng.randf_range(0.64, 1.34))
		_fels_quader(st, [
			Vector3(au, ub, zc - d0), Vector3(bu, ub, zc - d0),
			Vector3(bu, ub, zc + d0), Vector3(au, ub, zc + d0),
			Vector3(ao, ob, zc - d1), Vector3(bo, ob, zc - d1),
			Vector3(bo, ob, zc + d1), Vector3(ao, ob, zc + d1)], col)


## Neuer Versatz der Aussenflucht gegen ihre Sollkurve, in Metern nach AUSSEN gerechnet
## (positiv = vorspringend). vorher ist der Versatz der Bankgruppe darunter, ziel der
## frisch gewuerfelte Wunschwert.
##
## BEIDE RICHTUNGEN WERDEN GEDECKELT, und genau das ist der Unterschied zur vorigen
## Fassung. Dort war nur der VORSPRUNG begrenzt, der Ruecksprung dagegen unbegrenzt. Das
## ist ein Gleichrichter: der Lauf konnte die Kante beliebig weit hereinziehen, aber nur
## ein paar Meter herausbringen, und in der Summe lief sie deshalb immer nur nach innen.
## Es gab konstruktiv KEINE Stufe, die wieder herauskommt — gemessen 19 Richtungswechsel
## der Aussenkante auf 310 Bildzeilen gegen 103 im Referenzbild, und eine Streuung um die
## eigene Sollkurve von 2.9 px gegen 18.1. Herauskommende Stufen sind der Ueberhang, an
## dem man Fels von einer Treppe unterscheidet; ohne sie bleibt es eine Rampe.
##
## Der Ruecksprung darf etwas groesser sein als der Vorsprung (32 gegen 26 m): Fels wird
## von aussen abgetragen, es kommt keiner hinzu. Aber eben nur ETWAS — die frueheren
## 9 m Vorsprung gegen unbegrenzten Ruecksprung waren keine Asymmetrie mehr, sondern eine
## Einbahnstrasse.
##
## DIE ZAHLEN SIND KLEIN, und das ist kein Zoegern. Die Anflugkamera steht 540 m unter dem
## Scheitel; ein Absatz nach aussen zeigt ihr nicht seine Deckflaeche, sondern seine
## UNTERSEITE, und die liegt als heller Streifen quer vor dem Fels. Mit 26 m Vorsprung
## waren das im Bild frei ueber dem Loch schwebende Platten. Elf Meter auf einem 190 m
## breiten Pfeiler sind knapp 6 Prozent — genau die Groessenordnung, in der die
## Aussenkante des Referenzbildes um ihre eigene Sollkurve streut (18 px auf 340 px).
static func _flucht(vorher: float, ziel: float, max_vor := 11.0, max_zur := 24.0) -> float:
	return clampf(ziel, vorher - max_zur, vorher + max_vor)


## Ein waagerecht liegendes Dreieck der Schutthalde. Die Wicklung wird gegen OBEN
## korrigiert statt gegen einen Blockmittelpunkt wie in _fels_tri — bei einer Bodenflaeche
## ist "aussen" schlicht die Himmelsrichtung, einen Koerpermittelpunkt gibt es nicht.
static func _boden_tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3,
		col: Color) -> void:
	# Dieselbe Umkehr wie in _fels_tri und aus demselben Grund: fuer eine von OBEN
	# sichtbare Flaeche muss die Rechte-Hand-Normale nach UNTEN zeigen. Vorher zeigte sie
	# nach oben, die Felsdecke der Halde war damit rueckseitig — man sah durch sie hindurch
	# auf das Gelaende darunter, und der Rand der Decke stand als Kante im Hang.
	var n := (p1 - p0).cross(p2 - p0)
	var q1 := p1
	var q2 := p2
	if n.y > 0.0:
		q1 = p2
		q2 = p1
		n = -n
	var nn := -n.normalized()
	var c2 := _shade(col, 0.86 + 0.22 * maxf(nn.y, 0.0) + 0.07 * nn.x)
	st.set_color(c2); st.add_vertex(p0)
	st.set_color(c2); st.add_vertex(q1)
	st.set_color(c2); st.add_vertex(q2)


## UMRISS DER SCHUTTHALDE — EINE Quelle fuer zwei Nutzer.
##
## _tor_halde baut daraus Felsdecke und Bloecke; TerrainWorld haengt dieselbe Zone in
## _open_ground ein und nimmt ihr in _face_color die Almwiese. Vorher kannte nur _tor_halde
## die beiden Ellipsen, und die Bepflanzung liess ihren Wald mitten durch den Schutt
## wachsen. Eine drueben NACHGEBAUTE Ellipse waere beim naechsten Umbau still falsch
## geworden — dieselbe Falle, aus der das Talbreitenprofil schon einmal herausgeholt wurde
## (siehe TerrainWorld._tal_halbbreite).
##
## "roh" ist die Dichte im TORSYSTEM (lokales +X quer zum Tal zur DICKEN Seite hin, +Z
## talauswaerts), 0 aussen bis ueber 1 am Fuss. Zwei Kegel, je einer unter einem Bein; der
## am dicken Pfeiler ist deutlich groesser, weil dort auch der Fels groesser ist. Beide
## sind laengs des Tals (z) gestreckt — Schutt rutscht den Hang hinunter, und der Hang
## faellt hier talwaerts.
##
## DIE AUSSPARUNG FUER DIE BACHRINNE STECKT ABSICHTLICH NICHT DARIN. Sie gehoert zur
## Felsdecke (die darf nicht ueber dem Wasser liegen), nicht zur Bewuchssperre: unter dem
## Bogen soll auch dann kein Wald stehen, wenn dort die Decke aussetzt.
##
## GROESSE DER KEGEL: auf der dicken Seite gross (0.88/0.98), denn dort faellt die
## Felsrippe wirklich zum Tor hin ab und der Schutt gehoert dorthin. Auf der duennen Seite
## klein — als er dort gross war, ueberzog er den ganzen Sporn gegenueber bis zu dessen
## Kuppe, und im Bild lag ein Haufen heller Kisten auf einem Huegel. Ein Schuttkegel liegt
## am FUSS, er steigt nicht ueber einen Nachbarberg.
## 0.46 -> 0.50 UND MITTE 0.30 -> 0.34: gerade so weit, dass der Schutt die dem Tor
## zugewandte Flanke des Sporns hinaufreicht (bis -437 m) statt an seinem Fuss abzubrechen.
## Die Kuppe des Sporns liegt bei -400 m und behaelt damit eine Dichte von nur 0.14 — dort
## liegen einzelne Broecken, keine Schuerze. Ohne das stand der Sporn im Bild als glatte,
## einfarbige Duene neben einer Blockhalde.
static func tor_halde_zone(mitte_x: float, mitte_z: float, yaw: float, s_w: float,
		seed_v: int) -> Dictionary:
	var nz := FastNoiseLite.new()
	nz.seed = seed_v + 91
	nz.frequency = 0.0085                      # rund 120 m grosse Lappen am Haldenrand
	var roh := func(lx: float, lz: float) -> float:
		var a := 1.0 - Vector2((lx - 0.40 * s_w) / (0.88 * s_w), lz / (0.98 * s_w)).length()
		var b := 1.0 - Vector2((lx + 0.34 * s_w) / (0.50 * s_w), lz / (0.56 * s_w)).length()
		return maxf(a, b) + 0.34 * nz.get_noise_2d(lx, lz)
	# "reich" ist der Halbmesser, ab dem "roh" sicher unter null liegt: der grosse Kegel
	# reicht bis 0.40 + 0.88 = 1.28 s_w, und das Rauschen (0.34) schiebt seine Nullinie um
	# weitere 0.34 * 0.88 = 0.30 s_w hinaus. 1.60 hat also Luft.
	return {"x": mitte_x, "z": mitte_z, "cos": cos(yaw), "sin": sin(yaw),
		"s_w": s_w, "reich": 1.60 * s_w, "roh": roh}


## SCHUTTHALDE UNTER DEM FELSENTOR: eine Decke aus blankem Fels, darauf einzelne Bloecke.
##
## WARUM UEBERHAUPT: die vorige Fassung streute nur Bloecke, und zwar ueber die gruene
## Almwiese des Talbodens und bis 350 m talwaerts. Im Bild waren das helle Kisten, die
## jemand auf einer Wiese abgestellt hat. Im Referenzbild waechst der Bogen aus einer
## blanken, blockigen Halde heraus — der Boden UNTER dem Schutt ist selbst Fels, und
## genau das fehlte. Der Schutt allein reicht nicht: zwischen den Bloecken bleibt sonst
## Gras stehen, und Gras zwischen Bloecken liest sich als Wiese mit Steinen.
##
## WARUM EIN EIGENER KNOTEN NEBEN dem Felsentor statt darin — drei getrennte Gruende:
##  * KOLLISION. Das Tor bezieht seine Kollisionsflaeche aus seinem GESAMTEN Sichtnetz.
##    Eine bodennahe Platte darin waere eine unsichtbare Stolperkante quer durchs Tal.
##  * MESSUNG. tools/_tor_form.gd projiziert alle Meshes unter dem Knoten "Felsentor" in
##    die Silhouette und wertet fuer die Beindicke nur Zeilen mit GENAU ZWEI getrennten
##    Felsflaechen. Die Halde steigt am Hang ueber 100 m an und waere dort eine dritte.
##    Die vorige Fassung hat den Schutt darum mit einem Hoehendeckel bei 13 Prozent
##    kuenstlich kleingehalten — ein eigener Knoten sagt dasselbe ehrlicher und laesst
##    die Halde dem Hang folgen, wie ein Schuttkegel es tut.
##  * TORTIEFE. Mit dem Schutt im Tor meldete das Werkzeug "Tortiefe 734 m"; das war die
##    Streuung der Bloecke, nicht die Dicke des Fels.
##
## WARUM DIE HALDE TROTZDEM INS GELAENDE HINEINREDET: sie ist Geometrie des Wahrzeichens,
## aber sie liegt AUF dem Gelaende, und das Gelaende bepflanzt sich selbst. Solange die
## Bepflanzung nichts von ihr wusste, wuchs Nadel- und Laubwald mitten durch den Schutt —
## gemessen 63 Prozent Gruen im Fussbereich gegen 6 Prozent im Referenzbild. Deshalb gibt
## tor_halde_zone die Form heraus; TerrainWorld sperrt darueber Bewuchs und Almwiese.
## Gefaerbt wird in _face_color weiterhin nichts Besonderes: dort faellt nur der WIESENHUB
## weg, und uebrig bleibt die ganz normale Felsfarbe der Weltregel.
static func _tor_halde(parent: Node3D, mitte: Vector3, yaw: float, s_w: float,
		gelaende: Object, seed_v: int) -> void:
	var t0 := Time.get_ticks_msec()
	var node := Node3D.new()
	node.name = "Torhalde"
	node.position = mitte
	node.rotation.y = yaw
	parent.add_child(node)

	# GROBE STUFE fuer die Ferne: jeder sechste Block, dafuer groesser. Sie traegt die
	# Silhouette der Halde weiter, kostet aber nur rund ein Sechstel der Dreiecke.
	var st_grob := SurfaceTool.new()
	st_grob.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_grob.set_smooth_group(-1)

	var welt := Transform3D(Basis(Vector3.UP, yaw), mitte)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 91
	var nz := FastNoiseLite.new()
	nz.seed = seed_v + 91
	nz.frequency = 0.0085                      # rund 120 m grosse Lappen am Haldenrand

	# DICHTE DER HALDE. Der UMRISS kommt aus tor_halde_zone (dort steht, warum er dort
	# steht und nicht hier); hier kommt nur die Bachrinne dazu.
	# BACHRINNE FREIHALTEN: der Talbach laeuft laengs unter dem Bogen hindurch. Ohne die
	# Aussparung liegt die Felsdecke ueber dem Wasser und der Bach verschwindet darunter.
	# DIE RINNE IST VON 34..108 M AUF 20..62 M GESCHRUMPFT. Mit der alten Weite blieb quer
	# durch die Torgasse ein 216 m breiter Streifen ohne Decke und ohne Bloecke — genau
	# dort, wo im Referenzbild Bloecke bis in die untere Oeffnung hinein liegen. Der Bach
	# selbst ist keine 30 m breit, mehr Luft braucht er nicht.
	var roh: Callable = tor_halde_zone(mitte.x, mitte.z, yaw, s_w, seed_v)["roh"]
	var dicht := func(lx: float, lz: float) -> float:
		return float(roh.call(lx, lz)) * smoothstep(20.0, 62.0, absf(lx))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	# DEUTLICH DUNKLER ALS VORHER (0.60/0.53/0.44). Das Gelaende um das Tor ist seit der
	# neuen Felsrippe nackter Hochgebirgsfels in rund 0.60/0.57/0.53 — die alte Haldenfarbe
	# lag genau darauf, und die ganze Schuerze war im Bild schlicht nicht zu finden. Schutt
	# ist frisch gebrochener Fels und damit dunkler als die verwitterte, staubige Flanke.
	# 0.33/0.28/0.22 STATT 0.46/0.41/0.34, aus demselben Grund wie die Felsfarbe: die alten
	# Werte waren gegen ein Bild eingestellt, in dem die Halde wegen der verkehrten Wicklung
	# ueberhaupt nicht sichtbar war (_boden_tri). Gemessen kam sie danach auf 204/193/169,
	# das Referenzbild hat 155/138/116.
	var halde := Color(0.26, 0.21, 0.16)

	# --- FELSDECKE ----------------------------------------------------------------------
	# 15 m Maschenweite. Das Terrainnetz hat 8 m (CHUNK 384 / CELLS 48); mit deutlich
	# groesseren Maschen stanzen dessen Kuppen durch die Decke.
	# DAS RECHTECK UMSCHLIESST DEN UMRISS JETZT GANZ (frueher -0.82..1.10 und +-0.88 s_w).
	# Es war KLEINER als die Dichtefunktion reicht: der grosse Kegel geht bis 1.28 s_w,
	# das Randrauschen noch 0.30 s_w weiter. Die Decke war dort also abgeschnitten,
	# waehrend die Bewuchssperre (TerrainWorld, aus derselben Dichtefunktion) bis zum
	# Umriss geht — uebrig bliebe ein baumloser Streifen ohne Schutt darauf. Maschen
	# ausserhalb des Umrisses kosten nur den Test in der Schleife darunter.
	var schritt := 15.0
	var x_lo := -0.86 * s_w
	var x_hi := 1.62 * s_w
	var z_lo := -1.34 * s_w
	var z_hi := 1.34 * s_w
	var nx := int((x_hi - x_lo) / schritt) + 2
	var nzz := int((z_hi - z_lo) / schritt) + 2
	var hy := PackedFloat32Array()
	var dv := PackedFloat32Array()
	hy.resize(nx * nzz)
	dv.resize(nx * nzz)
	for j in nzz:
		for i in nx:
			var lx := x_lo + float(i) * schritt
			var lz := z_lo + float(j) * schritt
			var w: Vector3 = welt * Vector3(lx, 0.0, lz)
			# NUR 1.6 m ueber dem Gelaende, dazu ein kurzwelliger Anteil von 1.4 m. Mit
			# 3 m Hub und 2.6 m Welle stand die Decke an ihrem Rand als Kante im Hang und
			# einzelne Maschen lasen sich als flache Pappkarten. Weniger Abstand heisst,
			# dass hier und da eine Gelaendekuppe durchstoesst — das sieht aus wie
			# anstehender Fels im Schutt und ist genau richtig.
			hy[j * nx + i] = gelaende.height_at(w.x, w.z) - mitte.y + 1.6 \
				+ 1.4 * nz.get_noise_2d(lx * 3.4, lz * 3.4)
			dv[j * nx + i] = dicht.call(lx, lz)
	for j in nzz - 1:
		for i in nx - 1:
			var d00: float = dv[j * nx + i]
			var d10: float = dv[j * nx + i + 1]
			var d01: float = dv[(j + 1) * nx + i]
			var d11: float = dv[(j + 1) * nx + i + 1]
			var dmin := minf(minf(d00, d10), minf(d01, d11))
			# KEIN ZUFAELLIGES AUSDUENNEN AM RAND. Der erste Versuch liess im aeusseren
			# Drittel Maschen zufaellig ausfallen; uebrig blieben einzeln stehende
			# 15-m-Platten, die im Bild wie hingeworfene Pappkarten aussahen. Der Rand
			# franst schon durch das Rauschen in der Dichtefunktion aus, und der franst
			# ZUSAMMENHAENGEND aus — das ist der Unterschied.
			if dmin <= 0.02:
				continue
			var x0 := x_lo + float(i) * schritt
			var z0 := z_lo + float(j) * schritt
			var p00 := Vector3(x0, hy[j * nx + i], z0)
			var p10 := Vector3(x0 + schritt, hy[j * nx + i + 1], z0)
			var p01 := Vector3(x0, hy[(j + 1) * nx + i], z0 + schritt)
			var p11 := Vector3(x0 + schritt, hy[(j + 1) * nx + i + 1], z0 + schritt)
			var col := _shade(halde, rng.randf_range(0.80, 1.18))
			_boden_tri(st, p00, p10, p11, col)
			_boden_tri(st, p00, p11, p01, _shade(halde, rng.randf_range(0.80, 1.18)))

	# --- BLOCKSCHUERZE ------------------------------------------------------------------
	# Einzeln erkennbar und kantig, kein Kegel aus einem Stueck: daran erkennt man
	# Verwitterung statt Bauwerk.
	#
	# JITTER-GITTER STATT ZUFALLSWURF — das ist die eigentliche Aenderung dieser Runde.
	# Vorher lagen 1200 Bloecke ZUFAELLIG auf der Flaeche. Bei reiner Streuung bleiben auch
	# bei doppelter Zahl Loecher stehen (Poisson: selbst bei rechnerisch voller Deckung
	# liegen 37 Prozent der Flaeche frei), und durch genau diese Loecher sah man die glatte
	# 15-m-Felsdecke. Im Bild las sich das als gepflasterter Vorplatz MIT Bloecken darauf
	# statt als Schuerze AUS Bloecken; gemessen 7.7 m Fugenabstand gegen 2.5 m im
	# Referenzbild, also Faktor drei zu grob.
	# Ein Gitter mit Versatz belegt jede Masche hoechstens einmal und laesst keine zwei
	# Bloecke aufeinanderfallen. Die Masche ist 13 m, die Bloecke sind 14 bis 64 m breit —
	# jeder ueberlappt seine Nachbarn, die Decke kommt nirgends mehr durch.
	# AUSGEDUENNT WIRD UEBER DIE BELEGUNG, NICHT UEBER DIE GROESSE. Der alte Faktor
	# lerpf(0.45, 1.0, d) machte die Bloecke zum Rand hin klein, und kleine Bloecke lesen
	# sich als Kies. Ein Schuttkegel hat an seinem Fuss dieselben Broecken wie in der
	# Mitte, es liegen nur weniger davon.
	# BIS 0.02 STATT BIS 0.14: dort endet auch die Felsdecke. Mit 0.14 blieb rundherum ein
	# Kranz aus blanker Decke ohne einen einzigen Block stehen.
	#
	# ZWEI KORNGROESSEN, NICHT EINE. Im Referenzbild liegen zwischen den grossen Broecken
	# ueberall kleinere Splitter; das ist das Merkmal, an dem man Schutt von Pflaster
	# unterscheidet. Mit nur einer Groesse war unsere Schuerze ein Verband aus fast gleich
	# grossen Platten — gemessen streute der Fels bei uns nur 42.8 Graustufen gegen 58.5 im
	# Referenzbild. Der Grobgang deckt, der Feingang bricht die Deckung auf.
	# DIE KORNGROESSEN SIND EIN KOMPROMISS MIT DER ANFLUGENTFERNUNG, und beide Grenzen
	# sind schon einmal ueberschritten worden. Bei 2.5 bis 13 m war die Halde aus 900 m
	# (Pose tal_tor_nah) ein zerfranster grauer Teppich; bei 12 bis 32 m im Grobgang war
	# der gemessene Fugenabstand 6.3 m gegen 2.5 m im Referenzbild. 10 bis 28 m grob und
	# 2.8 bis 7.5 m fein trifft beides: die grossen Broecken tragen die Form aus der
	# Entfernung, die kleinen liefern die Koernung dazwischen.
	var gelegt := 0
	for durchgang in 2:
		var gs := 10.0 if durchgang == 0 else 5.0
		var g_lo := 9.0 if durchgang == 0 else 2.5
		var g_hi := 22.0 if durchgang == 0 else 6.5
		# Der Feingang belegt nur ein Drittel seiner Maschen und nur im Kegel selbst:
		# Splitt sammelt sich zwischen den grossen Bloecken, nicht auf dem auslaufenden
		# Saum, wo einzelne Broecken liegen.
		var d_lo := 0.02 if durchgang == 0 else 0.16
		var d_hi := 0.34 if durchgang == 0 else 0.34
		var p_max := 1.0 if durchgang == 0 else 0.34
		var nbx := int((x_hi - x_lo) / gs) + 1
		var nbz := int((z_hi - z_lo) / gs) + 1
		for j in nbz:
			for i in nbx:
				var lx := x_lo + (float(i) + 0.5) * gs + rng.randf_range(-0.45, 0.45) * gs
				var lz := z_lo + (float(j) + 0.5) * gs + rng.randf_range(-0.45, 0.45) * gs
				var d: float = dicht.call(lx, lz)
				if d <= d_lo or rng.randf() > smoothstep(d_lo, d_hi, d) * p_max:
					continue
				gelegt += 1
				# pow(.., 2.2): viele mittlere, wenige sehr grosse Bloecke. Eine
				# Gleichverteilung liess den Kegel wie eine Kiste Wuerfel aussehen.
				# UNTERGRENZE 10 M IM GROBGANG IST KEINE GESCHMACKSFRAGE: 2 * 10 * 0.60 =
				# 12 m schmalste Blockbreite gegen 11 m Masche. Faellt sie darunter,
				# entstehen wieder Fugen und die Felsdecke kommt durch.
				var gr := lerpf(g_lo, g_hi, pow(rng.randf(), 2.2))
				var hx := gr * rng.randf_range(0.60, 1.00)
				var hyy := gr * rng.randf_range(0.48, 0.86)
				var hz := gr * rng.randf_range(0.60, 1.00)
				# Boden an DREI Stellen abtasten und den tiefsten Wert nehmen: der Block soll
				# in den Hang einsinken, nicht auf seiner hoechsten Ecke balancieren.
				# NUR IM GROBGANG. Die Splitter sind 3 bis 7 m breit, ueber diese Strecke
				# aendert sich der Hang um weniger als einen halben Meter — drei Proben
				# waeren dreimal derselbe Wert. Bei 6300 Splittern sind das 12 600 gesparte
				# height_at-Aufrufe auf dem Hauptthread.
				var w: Vector3 = welt * Vector3(lx, 0.0, lz)
				var by: float = gelaende.height_at(w.x, w.z) - mitte.y
				if durchgang == 0:
					var wa: Vector3 = welt * Vector3(lx - hx, 0.0, lz)
					var wb: Vector3 = welt * Vector3(lx + hx, 0.0, lz)
					by = minf(by, minf(gelaende.height_at(wa.x, wa.z),
						gelaende.height_at(wb.x, wb.z)))
				# GEKIPPT, NICHT NUR GEDREHT — die zweite wichtige Aenderung dieser Runde.
				# Mit reiner Y-Drehung blieb jede Deckflaeche WAAGERECHT. Nebeneinander
				# ergaben die Deckflaechen dadurch eine durchgehende Ebene, und im Bild lag
				# am Fuss ein gestufter Steinbruchboden statt einer Halde: der Befund
				# "gepflasterter Vorplatz" kam zur Haelfte daher und nicht nur von den Fugen.
				# Abgestuerzte Broecken liegen, wie sie zur Ruhe gekommen sind. Bis 26 Grad
				# (0.45 rad) — mehr sieht aus, als staenden sie auf der Kante.
				var achse := Vector3(rng.randf_range(-1.0, 1.0), 0.0,
					rng.randf_range(-1.0, 1.0)).normalized()
				var dreh := Basis(achse, rng.randf_range(-0.45, 0.45)) \
					* Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				# Halb eingesunken. Die vorige Fassung sass mit 0.68 der Halbhoehe ueber
				# Grund und stand auf einem Hang deshalb auf der Talseite frei — darunter
				# klaffte eine Schattenhoehle, und der Block wirkte hingestellt statt
				# abgestuerzt.
				var sitz := Vector3(lx, by + 1.6 + hyy * 0.34, lz)
				var ecken: Array = []
				for be: Vector3 in [Vector3(-1, -1, -1), Vector3(1, -1, -1),
						Vector3(1, -1, 1), Vector3(-1, -1, 1), Vector3(-1, 1, -1),
						Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]:
					# ECKENSTREUUNG. AUFGEBOHRT AUF 0.86 .. 1.34 UND WIEDER ZURUECK: die Idee
					# war, den Block ohne ein einziges zusaetzliches Dreieck vielflaechiger
					# zu machen (mehr Streuung der acht Ecken = mehr Streuung der zwoelf
					# Dreiecksnormalen = mehr Helligkeitsstufen je Block). Gemessen wurde es
					# SCHLECHTER: der Anteil gleichfarbiger 5x5-Felder stieg von 24.4 auf
					# 27.3 Prozent, weil das nach aussen verschobene Fenster die Bloecke im
					# Mittel um 15 Prozent groesser macht und groessere Bloecke groessere
					# ebene Flaechen haben. Der Kennwert haengt an der BILDGROESSE des Blocks,
					# nicht an seiner Flaechenzahl — und die Blockgroesse ist nach unten
					# durch die Lesbarkeit aus 830 m gebunden. Also unveraendert gelassen.
					ecken.append(sitz + dreh * (Vector3(be.x * hx, be.y * hyy, be.z * hz)
						* rng.randf_range(0.78, 1.14)))
				var farbe := _shade(halde, rng.randf_range(0.72, 1.14))
				_fels_quader(st, ecken, farbe)
				# Jeder sechste Block auch grob — um 1.7 aufgeblasen, damit die Halde aus
				# der Ferne geschlossen bleibt statt zu sieben.
				if gelegt % 6 == 0:
					var grob_ecken: Array = []
					for e: Vector3 in ecken:
						grob_ecken.append(sitz + (e - sitz) * 1.7)
					_fels_quader(st_grob, grob_ecken, farbe)
	# WIE BEI DER FERNSCHUERZE MITGEZAEHLT. Die Schuerze ist mit Abstand der groesste
	# Posten des Wahrzeichens (der Bogen selbst hat 4752 Dreiecke, tools/_tor_kosten.gd),
	# und sie entsteht auf dem HAUPTTHREAD beim Weltaufbau: drei height_at je Block. Ohne
	# die Zahl im Log faellt eine Ueberdosis erst im Spiel auf.
	print("Torhalde: %d Bloecke, %.2f s" % [gelegt, float(Time.get_ticks_msec() - t0) / 1000.0])

	# ZWEI STUFEN STATT EINER. Die feine Halde hat gemessen 147 198 Dreiecke (der Bogen
	# selbst nur 4 752, die GESAMTE Fernschuerze ueber 40 km Welt 481 898). Ein Drittel der
	# Weltgeometrie an einer einzigen Stelle ist zu viel fuer etwas, das man nur aus der
	# Naehe als Bloecke erkennt — aus 2 km ist es ein grauer Fleck.
	# Godots eingebaute Mesh-LOD greift hier nicht: die entsteht beim IMPORT, dieses Netz
	# wird zur Laufzeit gebaut. Also zwei Netze und die Sichtweiten-Bereiche von
	# GeometryInstance3D, die den Wechsel ohne eine einzige Zeile Bildlogik erledigen.
	# Der Ueberlappungsbereich (2400 gegen 2200) ist Absicht: ohne ihn klafft beim
	# Umschalten ein Frame lang eine Luecke.
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _fels_mat()
	mi.visibility_range_end = 2400.0
	node.add_child(mi)
	st_grob.generate_normals()
	var mig := MeshInstance3D.new()
	mig.mesh = st_grob.commit()
	mig.material_override = _fels_mat()
	mig.visibility_range_begin = 2200.0
	node.add_child(mig)


static func build_felsentor(parent: Node3D, mitte: Vector3, spannweite: float,
		hoehe: float, breite: float, yaw: float, seed_v := 7731,
		gelaende: Object = null) -> Node3D:
	var node := Node3D.new()
	node.name = "Felsentor"
	node.position = mitte
	node.rotation.y = yaw
	parent.add_child(node)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v                          # fester Seed -> dieselbe Form bei jedem Start
	var s_w := spannweite
	var h := hoehe
	var xm := 0.04 * s_w                       # Scheitel aussermittig, zur dicken Seite
	var nadel_h := h * 0.55                    # Rippe UEBER dem Scheitel
	# SCHICHTDICKE. Der Kragbogen springt je Bank um einen ganzen Schritt ins Loch — bei
	# 23 m Grunddicke waren das im Bild handbreite Simse, unter denen man die Unterseite
	# sah, und der Pfeiler las sich als Stapel Tische. Mit 13 m wird aus denselben Stufen
	# eine feine Schichtung, so wie der Fels im Referenzbild verwittert ist.
	var bank := 13.0
	# Warm graubraun. Der umgebende Hochgebirgsfels ist kalt grau bis weiss und der
	# Talboden gruen — das Tor soll sich von beidem absetzen, sonst verschwindet es im
	# Hang. Mit 0.72/0.60/0.46 lag es aus 1 km im selben Helligkeitsbereich wie die
	# Schneegipfel dahinter und las sich als heller Plattenstapel; 0.60/0.52/0.42 war
	# umgekehrt so kalt, dass es wie Beton wirkte. Dazwischen, deutlich waermer.
	# 0.58/0.47/0.36 STATT 0.64/0.53/0.41. Die Begruendung von damals gilt weiter (warm
	# graubraun, damit sich das Tor vom kalten Fels und vom gruenen Talboden absetzt), nur
	# ist die Umgebung eine andere geworden: die Felsrippe steht jetzt unmittelbar daneben
	# und ist mit rund 0.60/0.57/0.53 fast gleich hell. Das Tor verschwand darin.
	# 0.37/0.28/0.20 STATT 0.58/0.47/0.36. Alle frueheren Werte hier wurden gegen ein Bild
	# eingestellt, in dem der Fels von der falschen Seite beleuchtet war (siehe _fels_tri);
	# mit richtiger Wicklung stand statt eines Bogens ein Gipsmodell im Tal. Nachgemessen
	# an den Renderbildern: der Pfeiler kam auf 176/161/138, das Referenzbild hat an der
	# entsprechenden Stelle 123/107/86 — also rund 30 Prozent zu hell und dabei zu kalt.
	# Die neuen Werte treffen das und halten den Abstand zum umgebenden Gelaende (183/171/
	# 147), an dem der Bogen sonst nicht mehr zu erkennen ist.
	var fels := Color(0.27, 0.20, 0.135)

	# --- DIE SENKRECHTE FUGENSCHAR ------------------------------------------------------
	# Kantenenergie im Fels, aus Renderausschnitten gemessen: bei uns waagerecht 0.166 zu
	# senkrecht 0.114 (Verhaeltnis 1.45), im Referenzbild 0.372 zu 0.403 (0.92) bei rund
	# der 2,4-fachen Dichte. Solange die Waagerechten ueberwiegen, liest sich der Fels als
	# Mauerwerk, egal wie gut er im Hang steckt.
	# Gebankter Fels hat ZWEI Fugenscharen. Die Schichtung liefert _tor_bank ueber die
	# Bankhoehen; die KLUEFTUNG stand bisher nicht im Modell, weil die Blockgrenzen je Bank
	# neu gewuerfelt wurden — eine 7 bis 23 m kurze Fuge, die im naechsten Stapel woanders
	# liegt, ist im Bild nichts. Jetzt stehen die Kluefte fest ueber die volle Hoehe, und
	# jede Spalte dazwischen behaelt ihren eigenen Tiefenversatz: zwei Nachbarspalten
	# stehen um bis zu 0.22 * Tortiefe (rund 23 m) gegeneinander vor, und die Kante
	# dazwischen laeuft vom Fuss bis in die Nadel durch.
	# ABSTAND UNGLEICH (40 bis 92 m): gleich breite Spalten waeren gemauerte Pilaster.
	# NICHT ENGER: unter rund 35 m Spaltenbreite zeigt im steilen Anflug jede Spalte nur
	# noch ihre beiden Seitenflaechen, und aus dem Fels wird eine Ziehharmonika.
	#
	# DER VERSATZ WECHSELT JETZT MEIST DAS VORZEICHEN von Spalte zu Spalte (frueher je
	# Spalte unabhaengig aus -0.11 .. +0.11). Unabhaengig gewuerfelt liegen zwei Nachbarn
	# im Mittel nur 0.07 der Tortiefe auseinander, und der Sprung dazwischen wirft keinen
	# Schatten: gemessen kam die senkrechte Kantenenergie auf 0.015 gegen 0.037 im
	# Referenzbild, die Kluftschar war im Bild also praktisch nicht vorhanden. Mit
	# wechselndem Vorzeichen stehen zwei Nachbarspalten um 0.18 bis 0.50 der Tortiefe
	# (18 bis 50 m) gegeneinander vor. Nicht IMMER wechseln (78 Prozent): strenger Wechsel
	# waere eine Ziehharmonika mit fester Periode.
	# OBERGRENZE 0.19: bei mehr als der halben Tortiefe Unterschied verlieren zwei
	# Nachbarspalten den Kontakt und der Pfeiler faellt in senkrechte Scheiben auseinander.
	# Von 0.25 heruntergesetzt, nachdem die Wicklung stimmte (siehe _fels_tri) und die
	# Kluefte damit ueberhaupt erst sichtbar wurden: die Kantenenergie im Pfeiler kippte
	# von waagerecht/senkrecht 1.39 auf 0.55, das Referenzbild liegt bei 1.05. Die
	# senkrechte Fugenschar trug plotzlich das ganze Bild allein. Nebenbei sank die
	# gemessene Tortiefe von 173 auf rund 150 m — die 0.25 hatten den Bogen in der Tiefe
	# aufgeblaht, obwohl er mit 105 m angelegt ist.
	var kluft := PackedFloat32Array()
	var kluft_z := PackedFloat32Array()
	# Halbe Tiefe je Spalte. Sie ersetzt eine frueher JE BANK gewuerfelte Tiefe — die
	# Begruendung steht bei _tor_bank; kurz: je Bank ergab sie waagerechte Simse ueber die
	# volle Beinbreite, je Spalte ergibt sie senkrechte Kanten ueber die volle Hoehe.
	var kluft_d := PackedFloat32Array()
	var kx := -1.05 * s_w
	var vz := 1.0 if rng.randf() < 0.5 else -1.0
	kluft_z.append(rng.randf_range(0.07, 0.19) * vz)
	kluft_d.append(rng.randf_range(0.84, 1.0))
	while kx < 1.05 * s_w:
		kluft.append(kx)
		if rng.randf() < 0.78:
			vz = -vz
		kluft_z.append(rng.randf_range(0.07, 0.19) * vz)
		kluft_d.append(rng.randf_range(0.84, 1.0))
		kx += rng.randf_range(28.0, 62.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)                    # Flatshading wie das uebrige Gelaende

	# --- DIE BEIDEN BEINE, Bank fuer Bank von unten nach oben ---------------------------
	# Deutlich unter der Fusslinie anfangen: das Gelaende steigt zur dicken Seite hin um
	# ueber 400 m an, der Pfeiler soll dort aus dem anstehenden Fels herauswachsen und
	# nicht auf ihm stehen.
	# 0.42 STATT 0.30: auf der duennen Seite faellt das Gelaende zur Talmitte hin ab, und
	# dort endete die schlanke Saeule mit einer flach abgeschnittenen, hell beleuchteten
	# Deckplatte AUF der Wiese. Die zusaetzlichen 50 m stecken unter Grund und kosten
	# nichts — unsichtbare Baenke sind billiger als ein sichtbarer Schnitt.
	var y := -h * 0.42
	# VERSATZ DER AUSSENFLUCHT gegen ihre Sollkurve, je Bein, in Metern nach aussen. Er
	# laeuft ueber den Bogen HINWEG in die Felsnadel weiter — die Aussenflaechen des
	# Pfeilers setzen sich dort ja fort.
	#
	# DER VERSATZ WIRD NUR ALLE VIER BIS SIEBEN BAENKE NEU GESETZT, und das ist die
	# wichtigste Aenderung an dieser Schleife. Vorher bewegte er sich bei JEDER Bank; das
	# ergab auf 310 Bildzeilen 25 gleich grosse Trittstufen und nur 19 Richtungswechsel,
	# waehrend das Referenzbild auf derselben Strecke 103 Wechsel und die 6-fache Streuung
	# um die eigene Sollkurve hat. Sechs bis acht ECHTE Absaetze lesen sich als Fels,
	# fuenfundzwanzig kleine als Treppe. Zwischen zwei Sprungen fluchten die Baenke exakt
	# (dieselbe Aussenkante, dieselbe Tiefe, dieselben Spaltenkanten) — daraus wird eine
	# 60 bis 100 m hohe geschlossene Wand, deren einzige Zeichnung das Fugennetz ist.
	var o_dick := 0.0
	var o_duenn := 0.0
	# Antrieb der beiden Laeufe.
	var w_dick := 0.0
	var w_duenn := 0.0
	# Verbleibende Baenke, bis die jeweilige Flucht wieder springen darf.
	var grp_dick := 0
	var grp_duenn := 0
	# Dasselbe fuer die TIEFE: ein Lauf je Bein, der mit derselben Gruppe springt. Bewegte
	# er sich je Bank, laege ueber jeder Bankgrenze ein waagerechter Sims ueber die volle
	# Beinbreite (siehe _tor_bank) — genau der Plattenstapel, den wir loswerden wollen.
	var z_dick := 0.0
	var z_duenn := 0.0
	while y < h * 0.985:
		# Sehr ungleiche Bankdicken (7 bis 23 m). Gleich dicke Baenke lesen sich als
		# Mauerwerk, ungleiche als Schichtung.
		var hb := bank * rng.randf_range(0.55, 1.80)
		# Die Laibung wird am Unter- UND am Oberrand der Bank ausgewertet; die Bank ist ein
		# Trapez und die Laibung damit ein geschlossener Streckenzug (siehe _tor_bank).
		var t := clampf(y / h, 0.0, 1.0)
		var t2 := clampf((y + hb) / h, 0.0, 1.0)
		for seite: float in [1.0, -1.0]:
			var innen := _tor_loch(t, seite, s_w, xm)
			var innen_o := _tor_loch(t2, seite, s_w, xm)
			var aussen := _tor_aussen(t, seite, s_w, h, xm)
			var aussen_o := _tor_aussen(t2, seite, s_w, h, xm)
			var lo := minf(innen, aussen)
			var hi := maxf(innen, aussen)
			# Amplitude als ANTEIL DER BANKBREITE, nicht absolut: ein fester Wert haette
			# entweder den Pfeiler kaum bewegt oder die schlanke Saeule zerlegt.
			# Der Zufallslauf ist mittelwertfrei, die gemessene mittlere Beindicke und
			# damit das Verhaeltnis der beiden Beine bleiben also unberuehrt.
			# 0.11: auf dem dicken Pfeiler sind das +-21 m, auf der schlanken Saeule +-4 bis
			# 12 m. Mit 0.20 sprang die Kante am Absatz um bis zu 40 m, und weil man das Tor
			# von UNTEN sieht (Kamera 150 m, Scheitel 690 m), war jeder Vorsprung eine frei
			# schwebende Platte mit heller Unterseite. Der Absatz muss nicht gross sein, er
			# muss selten sein — das leistet die Gruppierung, nicht die Amplitude.
			var amp := (hi - lo) * 0.11
			var sock := _tor_sockel(t, seite, s_w)
			var sock_o := _tor_sockel(t2, seite, s_w)
			if seite > 0.0:
				if grp_dick <= 0:
					grp_dick = rng.randi_range(4, 7)
					# Gedaechtnis 0.40 statt 0.72: der Lauf laeuft jetzt ueber GRUPPEN statt
					# ueber Baenke. Mit dem traegen alten Faktor haetten zwei
					# aufeinanderfolgende Absaetze fast denselben Wert und die Wand waere
					# trotz Gruppen wieder glatt.
					w_dick = clampf(w_dick * 0.40 + rng.randf_range(-0.95, 0.95), -1.2, 1.2)
					o_dick = _flucht(o_dick, w_dick * amp)
					z_dick = clampf(z_dick * 0.40 + rng.randf_range(-0.9, 0.9), -1.1, 1.1)
				grp_dick -= 1
				# Sicherung: der Versatz stammt aus einer Gruppe, die weiter unten begonnen
				# hat, die Sollbreite des Beins aendert sich aber ueber die Hoehe. Mehr als
				# 45 Prozent der Bankbreite duerfte er nie fressen, sonst schnuerte eine
				# Gruppe das Bein ab.
				var vs := clampf(o_dick, -(hi - lo) * 0.45, (hi - lo) * 0.45)
				_tor_bank(st, rng, Vector2(innen, aussen + vs + sock),
					Vector2(innen_o, aussen_o + vs + sock_o), y, y + hb,
					breite * lerpf(1.0, 0.76, t), 0, fels, z_dick * breite * 0.06,
					kluft, kluft_z, kluft_d)
			else:
				if grp_duenn <= 0:
					grp_duenn = rng.randi_range(4, 7)
					w_duenn = clampf(w_duenn * 0.40 + rng.randf_range(-0.95, 0.95), -1.2, 1.2)
					o_duenn = _flucht(o_duenn, w_duenn * amp)
					z_duenn = clampf(z_duenn * 0.40 + rng.randf_range(-0.9, 0.9), -1.1, 1.1)
				grp_duenn -= 1
				var vs := clampf(o_duenn, -(hi - lo) * 0.45, (hi - lo) * 0.45)
				_tor_bank(st, rng, Vector2(aussen - vs - sock, innen),
					Vector2(aussen_o - vs - sock_o, innen_o), y, y + hb,
					breite * lerpf(1.0, 0.76, t), 1, fels, z_duenn * breite * 0.06,
					kluft, kluft_z, kluft_d)
		y += hb

	# --- FELSNADEL UEBER DEM SCHEITEL ---------------------------------------------------
	# Das ist der Unterschied zwischen Loch-in-Rippe und Reifen. Sie setzt bruchlos auf der
	# obersten Bogenbank auf (gleiche Kanten bei v = 0) und laeuft nach oben in eine
	# schmale, nach +X geneigte Spitze aus.
	# DIE BEIDEN EXPONENTEN SIND DER KERN und ziehen in verschiedene Richtungen:
	#  * v^1.7 links haelt die Kante lange ueber dem Scheitel — das IST die gemessene
	#    "Felsdecke ueber dem Scheitel".
	#  * v^0.5 rechts holt die Kante frueh herein, damit die Nadel schnell schlanker wird
	#    als der Pfeiler und sich als eigene Form absetzt.
	# Mit 2.8 links stand die Decke zwar 220 m hoch, im Bild war die Nadel aber so breit
	# wie das ganze Tor und alles zusammen sah aus wie eine Pyramide.
	var nadel0 := y
	var nadel1 := h + nadel_h
	var li0 := _tor_aussen(1.0, -1.0, s_w, h, xm)
	var re0 := _tor_aussen(1.0, 1.0, s_w, h, xm)
	while y < nadel1:
		# DEUTLICH DICKERE BAENKE als im Bogen (23 bis 39 m): die Nadel soll in sieben, acht
		# grossen Absaetzen zuruecktreten. Mit den duennen Bogenbaenken wurde daraus eine
		# fein gestufte Pyramide, mit ueber 40 m dagegen ein Stapel schwebender Platten.
		var hb := bank * rng.randf_range(1.75, 3.00)
		var v := clampf((y - nadel0) / (nadel1 - nadel0), 0.0, 1.0)
		# DIESELBE SCHRANKE WIE IM BOGEN, und hier ist sie noch noetiger: pow(v, 0.42) hat
		# bei v = 0 eine unendliche Steigung. Die erste Nadelbank sprang mit ihrer rechten
		# Kante um 111 m herein — ein einziger Absatz, so breit wie die halbe Nadel, und im
		# Bild der Ansatz, an dem Bogen und Nadel als zwei getrennte Bauteile auseinander
		# fielen. Mit hoechstens 24 m je Bank steht am Nadelfuss stattdessen eine kurze
		# Folge von Absaetzen, wie sie ein verwitterter Felskopf hat.
		for _v in 5:
			if hb <= 7.0:
				break
			var vp := clampf((y + hb - nadel0) / (nadel1 - nadel0), 0.0, 1.0)
			if absf(pow(vp, 0.42) - pow(v, 0.42)) * (re0 - xm - 0.115 * s_w) <= 24.0:
				break
			hb *= 0.62
		# Kanten unten UND oben: die Nadelbaenke sind Trapeze wie die des Bogens, ihre
		# Aussenflaechen laufen dadurch als geschlossener Streckenzug durch (siehe _tor_bank).
		var v2 := clampf((y + hb - nadel0) / (nadel1 - nadel0), 0.0, 1.0)
		var li := _nadel_li(v, li0, s_w, xm)
		var li_o := _nadel_li(v2, li0, s_w, xm)
		var re := lerpf(re0, xm + 0.115 * s_w, pow(v, 0.42))
		var re_o := lerpf(re0, xm + 0.115 * s_w, pow(v2, 0.42))
		# Beide Kanten der Nadel sind Aussenkanten, hier gibt es kein Loch. Die Amplitude
		# ist derselbe Anteil wie unten: an der breiten Nadelbasis sind das grosse
		# Absaetze, an der schmalen Spitze nur noch wenige Meter — die Spitze bleibt spitz.
		var amp := (re - li) * 0.11
		# KUERZERE GRUPPEN ALS IM BOGEN (2 bis 4 statt 4 bis 7 Baenke): die Nadelbaenke sind
		# mit 23 bis 39 m schon doppelt so hoch wie die des Bogens. Sieben davon waeren eine
		# 200 m hohe glatte Wand auf einer 231 m hohen Nadel, und die Nadel soll ja gerade
		# in mehreren Absaetzen zuruecktreten.
		if grp_dick <= 0:
			grp_dick = rng.randi_range(2, 4)
			w_dick = clampf(w_dick * 0.40 + rng.randf_range(-0.95, 0.95), -1.2, 1.2)
			o_dick = _flucht(o_dick, w_dick * amp)
			z_dick = clampf(z_dick * 0.40 + rng.randf_range(-0.9, 0.9), -1.1, 1.1)
		grp_dick -= 1
		if grp_duenn <= 0:
			grp_duenn = rng.randi_range(2, 4)
			w_duenn = clampf(w_duenn * 0.40 + rng.randf_range(-0.95, 0.95), -1.2, 1.2)
			o_duenn = _flucht(o_duenn, w_duenn * amp)
		grp_duenn -= 1
		# DIE FELSDECKE UEBER DEM SCHEITEL IST DIE HARTE BEDINGUNG und darf nicht dem
		# Zufall ueberlassen bleiben: EINE Bank, deren linke Kante rechts am Scheitel xm
		# vorbeirutscht, zerschneidet die durchgehende Decke — gemessen fiel sie so von
		# 196 m auf 74 m. Der Lauf darf die Kante deshalb nach LINKS frei bewegen (daher
		# kommen die Zacken), nach rechts nur bis 22 m links des Scheitels, und das auch
		# nur im unteren Dreiviertel: oben soll die Nadel ja schlank auslaufen.
		var li_a := li - o_duenn
		var li_b := li_o - o_duenn
		if v < 0.76:
			li_a = minf(li_a, xm - 22.0)
		if v2 < 0.76:
			li_b = minf(li_b, xm - 22.0)
		var re_a := re + o_dick
		var re_b := re_o + o_dick
		# SICHERUNG GEGEN EINE UMGESCHLAGENE BANK. Der Versatz stammt aus dem 190 m breiten
		# Pfeiler weiter unten, die Nadelspitze ist aber nur noch wenige Meter breit; ohne
		# die Grenze koennte die linke Kante rechts an der rechten vorbeiwandern, und
		# _fels_quader baute daraus einen nach innen gestuelpten Block.
		re_a = maxf(re_a, li_a + 18.0)
		re_b = maxf(re_b, li_b + 18.0)
		# loch_seite = 0 haelt hier NICHT ein Loch frei, sondern die Felsdecke: es sorgt
		# dafuer, dass die linke Kante nur um wenige Meter angefast wird. Genau die traegt
		# den Scheitel.
		_tor_bank(st, rng, Vector2(li_a, re_a), Vector2(li_b, re_b), y, minf(y + hb, nadel1),
			breite * lerpf(0.76, 0.26, v), 0, fels,
			z_dick * breite * 0.05, kluft, kluft_z, kluft_d)
		y += hb

	# --- SCHUTTHALDE AN BEIDEN FUESSEN --------------------------------------------------
	# Als EIGENER Knoten neben dem Tor, nicht als Teil davon. Begruendung steht bei
	# _tor_halde; kurz: der Schutt braucht weder Kollision noch soll er in der Silhouette
	# mitgemessen werden, und die Halde muss dem Hang frei nach oben folgen duerfen.
	if gelaende != null and gelaende.has_method("height_at"):
		_tor_halde(parent, mitte, yaw, s_w, gelaende, seed_v)

	# Normalen aus der Wicklung berechnen lassen, statt sie von Hand zu setzen. Die
	# Wicklung ist in _fels_tri bereits selbstkorrigierend — damit gibt es nur EINE Quelle
	# fuer die Orientierung statt zweier, die sich widersprechen koennen.
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _fels_mat()
	node.add_child(mi)

	var body := StaticBody3D.new()
	body.name = "Kollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	# DIESELBEN Dreiecke wie das Sichtnetz, direkt aus dem fertigen Mesh geholt statt
	# waehrend des Bauens parallel mitgeschrieben: zwei Listen koennen auseinanderlaufen,
	# eine nicht.
	shape.set_faces(mi.mesh.get_faces())
	cs.shape = shape
	body.add_child(cs)
	node.add_child(body)
	return node
