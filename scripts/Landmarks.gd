## Wahrzeichen / POIs (Stufe-2-Map): Stadt mit Kirche + Leuchtturm.
## STATISCH, damit Spiel (Main) UND Render-Tool dieselbe Geometrie bauen.
## Reine Low-Poly-Box-/Pyramiden-Bauten (passend zum restlichen Welt-Stil).
class_name Landmarks
extends RefCounted


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


static func _house(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, walls: Array, roof_mat: Material) -> void:
	var w: float = rng.randf_range(7.0, 11.0)
	var d: float = rng.randf_range(7.0, 11.0)
	var stories: int = 2 if rng.randf() < 0.35 else 1
	var hgt: float = 3.8 * float(stories)
	var wall := _mat(walls[rng.randi() % walls.size()], 0.92)
	_box(parent, pos + Vector3(0, hgt * 0.5, 0), Vector3(w, hgt, d), wall)
	_roof(parent, pos + Vector3(0, hgt + 1.6, 0), maxf(w, d), rng.randf_range(2.6, 3.8), roof_mat)


# Stadt: runde Silhouette aus Low-Poly-Häusern + Kirche mit Turm im Zentrum.
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
	var span := 5
	var spacing := 27.0
	for gx in range(-span, span + 1):
		for gz in range(-span, span + 1):
			var bx: float = float(gx) * spacing + rng.randf_range(-4.0, 4.0)
			var bz: float = float(gz) * spacing + rng.randf_range(-4.0, 4.0)
			if Vector2(bx, bz).length() > float(span) * spacing * 0.95:
				continue
			if rng.randf() < 0.16:
				continue
			_house(node, Vector3(bx, 0, bz), rng, walls, roof_a if rng.randf() < 0.6 else roof_b)
	# Kirche im Zentrum
	var cwall := _mat(Color(0.90, 0.88, 0.82), 0.88)
	var croof := _mat(Color(0.36, 0.30, 0.44))
	_box(node, Vector3(0, 6.0, 0), Vector3(13, 12, 24), cwall)
	_roof(node, Vector3(0, 13.5, 0), 26.0, 6.0, croof)
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
	var span := 3
	var spacing := 19.0
	for gx in range(-span, span + 1):
		for gz in range(-span, span + 1):
			var bx: float = float(gx) * spacing + rng.randf_range(-3.0, 3.0)
			var bz: float = float(gz) * spacing + rng.randf_range(-3.0, 3.0)
			if Vector2(bx, bz).length() > float(span) * spacing * 0.92:
				continue
			if rng.randf() < 0.18:
				continue
			var w: float = rng.randf_range(6.0, 9.0)
			var d: float = rng.randf_range(6.0, 9.0)
			var hgt: float = rng.randf_range(4.0, 6.0)
			_box(node, Vector3(bx, hgt * 0.5, bz), Vector3(w, hgt, d), _mat(walls[rng.randi() % walls.size()], 0.92))
			# STEILES Satteldach -> hohe schmale Pyramide
			_roof(node, Vector3(bx, hgt + 2.6, bz), maxf(w, d) * 0.92, rng.randf_range(4.5, 6.0), roof)
	# kleine Kapelle mit Turm
	_box(node, Vector3(0, 4.0, 0), Vector3(8, 8, 12), _mat(Color(0.84, 0.80, 0.72), 0.9))
	_roof(node, Vector3(0, 10.5, 0), 14.0, 5.0, _mat(Color(0.34, 0.28, 0.30)))
	_box(node, Vector3(0, 8.0, -7.0), Vector3(4, 16, 4), _mat(Color(0.84, 0.80, 0.72), 0.9))
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
