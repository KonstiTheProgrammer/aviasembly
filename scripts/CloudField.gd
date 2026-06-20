class_name CloudField
extends RefCounted

# WolkenMEER: eine dichte, rollende Kumulus-Decke (wie aus dem Flugzeug über den Wolken).
# Statt verstreuter Einzelwolken eine zusammenhängende Decke: Noise ballt die Wolken zu
# großen Feldern mit Löchern (Durchblick zum Boden), ein zweites Noise lässt die Deckenhöhe
# rollen (Hügel & Täler). Jede Wolke = mehrere verschmolzene Kugel-Lappen zu einem
# Kumulus-Hügel. KEINE Kollision -> man fliegt hindurch. Lebt in der Flug-Welt.

static func build(parent: Node3D, opts := {}) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 20240617))
	var root := Node3D.new()
	root.name = "CloudField"
	parent.add_child(root)

	var area: float = opts.get("area", 4400.0)            # halbe Kantenlänge des Felds (m) -> weit gestreut
	var spacing: float = opts.get("spacing", 340.0)       # Rasterabstand (größer -> mehr Abstand)
	var layer_y: float = opts.get("layer_y", 175.0)       # mittlere Höhe
	var billow: float = opts.get("billow", 30.0)          # sanftes Höhen-Rollen
	var layer_jitter: float = opts.get("layer_jitter", 55.0)  # Höhenstreuung je Wolke (3D-Verteilung)
	var cover_thresh: float = opts.get("cover_thresh", -0.05)  # höher = weniger/mehr verstreute Wolken

	# Ballungs-Noise (wo ist Wolke, wo Loch) + Höhen-Noise (rollende Höhe).
	var cov := FastNoiseLite.new()
	cov.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cov.frequency = 0.0021                                  # kleinere Ballungen -> mehr aufgelockert
	cov.seed = rng.seed
	var hgt := FastNoiseLite.new()
	hgt.noise_type = FastNoiseLite.TYPE_SIMPLEX
	hgt.frequency = 0.00085
	hgt.seed = rng.seed + 7

	var mat := _cloud_material()
	var src := SphereMesh.new()
	src.radius = 1.0
	src.height = 2.0
	src.radial_segments = 10
	src.rings = 6

	# Mehrere Puff-Mesh-Varianten vorbauen und zufällig wiederverwenden.
	var variants: Array = []
	for i in 10:
		variants.append(_puff_mesh(src, rng))

	var half := int(area / spacing)
	for ix in range(-half, half + 1):
		for iz in range(-half, half + 1):
			var x := float(ix) * spacing + rng.randf_range(-0.4, 0.4) * spacing
			var z := float(iz) * spacing + rng.randf_range(-0.4, 0.4) * spacing
			var c := cov.get_noise_2d(x, z)                 # -1..1
			if c < cover_thresh:
				continue                                    # Loch in der Decke
			# Dichte: an den Rändern der Wolkenfelder dünn/klein, in den Zentren dick/groß.
			var dens := smoothstep(cover_thresh, cover_thresh + 0.55, c)
			# Höhe rollt sanft + je Wolke gestreut -> die Wolken liegen NICHT in einer flachen
			# Ebene, sondern verteilt über verschiedene Höhen (wirkt natürlicher, weniger "Block").
			var cy := layer_y + hgt.get_noise_2d(x, z) * billow + rng.randf_range(-layer_jitter, layer_jitter)
			var mi := MeshInstance3D.new()
			mi.mesh = variants[rng.randi() % variants.size()]
			mi.material_override = mat
			mi.position = Vector3(x, cy, z)
			mi.scale = Vector3.ONE * lerp(0.65, 1.4, dens) * rng.randf_range(0.8, 1.2)
			mi.rotation.y = rng.randf() * TAU
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
	return root


# Ein Kumulus-Hügel: Lappen ballen sich zur Mitte und steigen dort an (Blumenkohl-Wölbung),
# Basis flach. Mehrere Kugeln zu einem Mesh verschmolzen.
static func _puff_mesh(src: SphereMesh, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := rng.randf_range(34.0, 52.0)
	var lobes := rng.randi_range(7, 11)
	for i in lobes:
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * base * 1.25          # mehr Lappen Richtung Mitte
		var up := (1.0 - rad / (base * 1.25)) * base * 0.55 # Zentrum höher -> Wölbung
		var off := Vector3(cos(ang) * rad, up + rng.randf_range(-0.08, 0.10) * base, sin(ang) * rad)
		var rx := base * rng.randf_range(0.5, 0.95)
		var ry := rx * rng.randf_range(0.72, 1.0)
		var rz := base * rng.randf_range(0.5, 0.95)
		st.append_from(src, 0, Transform3D(Basis().scaled(Vector3(rx, ry, rz)), off))
	st.generate_normals()
	return st.commit()


static func _cloud_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.98, 0.985, 1.0)         # OPAK weiß
	m.roughness = 1.0
	m.metallic = 0.0
	# Wenig Eigenleuchten -> die Sonne formt die Decke (helle Tops, schattige Täler = 3D-Look).
	m.emission_enabled = true
	m.emission = Color(0.55, 0.60, 0.70)
	m.emission_energy_multiplier = 0.12
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# Opak + Back-Face-Culling -> solide Wolke (kein "inside out").
	m.cull_mode = BaseMaterial3D.CULL_BACK
	# Beim Annähern DITHER-auflösen (opak) -> man fliegt weich hindurch.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	m.distance_fade_min_distance = 8.0
	m.distance_fade_max_distance = 40.0
	return m
