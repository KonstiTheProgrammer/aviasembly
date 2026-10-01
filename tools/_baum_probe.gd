## BAUMPROBE: Nahaufnahmen einzelner Arten und ein Probewald aus Flugperspektive — mit dem
## SPIELWEG (Meshes aus TerrainWorld._load_flora, echtes Flora-Material, Fernfassungen aus
## _grob_cache), aber ohne die Welt zu laden. Zum Abstimmen von tools/build_baeume.py,
## TerrainWorld._weiche_krone und dem Flora-Shader: ein Durchlauf dauert Sekunden statt der
## Minuten, die tools/_gefuehl_bilder.gd fuer ein echtes Flugbild braucht.
## Aufruf (FENSTER, nicht headless):
##   Godot --path . --script res://tools/_baum_probe.gd -- <ausgabeordner> [nah] [wald]
extends SceneTree

const NAH := [["Fichte", "Kiefer", "Birke"], ["Eiche", "Busch", "Schneetanne"],
	["Urwaldbaum", "Akazie", "Mangrove"], ["Palme", "Baumfarn", "Kaktus"],
	["Fels", "Totholz", "Busch"]]
# Mischung des Probewalds (Anteile wie im Bergwald der Hauptinsel, dazu ein Laubhain)
const WALD := [["Fichte", 0.62], ["Kiefer", 0.16], ["Birke", 0.10], ["Eiche", 0.07], ["Busch", 0.05]]

var f := 0
var root3: Node3D
var cam: Camera3D
var tw: TerrainWorld
var ziel := "user://"
var schuss := 0
var ansichten := []
var nah_root: Node3D
var wald_root: Node3D
var fern_root: Node3D


func _licht() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.74, 0.90)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.70, 0.78, 0.92)
	e.ambient_light_energy = 0.62
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Color(0.70, 0.81, 0.95)
	# Tiefennebel wie im Spiel (Main.NEBEL_ENDE / NEBEL_FORM)
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_density = 1.0
	e.fog_depth_begin = 1000.0
	e.fog_depth_end = 20000.0
	e.fog_depth_curve = 1.0
	e.fog_aerial_perspective = 0.74
	env.environment = e
	root3.add_child(env)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-42, 35, 0)
	l.light_energy = 1.7
	l.light_color = Color(1.0, 0.95, 0.86)   # wie Main (Sonne)
	l.shadow_enabled = true
	l.directional_shadow_max_distance = 500.0
	root3.add_child(l)


func _boden(groesse: float, farbe: Color) -> void:
	var boden := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(groesse, groesse)
	boden.mesh = pm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = farbe
	bm.roughness = 1.0
	boden.material_override = bm
	root3.add_child(boden)


func _wald(wurzel: Node3D, grob: bool, mitte: Vector3, halb: float, anzahl: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 1.0 / 90.0
	var listen := {}
	var n := 0
	var versuche := 0
	while n < anzahl and versuche < anzahl * 20:
		versuche += 1
		var p := Vector3(rng.randf_range(-halb, halb), 0.0, rng.randf_range(-halb, halb))
		# Lichtungen wie im Spiel: Dichte aus einem groben Rauschen
		if noise.get_noise_2d(p.x, p.z) < -0.12:
			continue
		var r := rng.randf()
		var art := "Fichte"
		var summe := 0.0
		for w in WALD:
			summe += float(w[1])
			if r < summe:
				art = w[0]
				break
		# Laubhain: in einer Ecke kehrt sich die Mischung um
		if noise.get_noise_2d(p.x + 500.0, p.z) > 0.25 and rng.randf() < 0.7:
			art = "Eiche" if rng.randf() < 0.45 else "Birke"
		var lo := 0.8 if art == "Busch" else 1.1
		var hi := 1.8 if art == "Busch" else 2.0
		var sc := rng.randf_range(lo, hi)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(sc, sc * rng.randf_range(0.9, 1.25), sc)), mitte + p - Vector3(0, 0.15, 0))
		if not listen.has(art):
			listen[art] = []
		(listen[art] as Array).append(xf)
		n += 1
	for art in listen:
		var mesh: Mesh = tw._flora[art]
		if grob:
			mesh = tw._grob_cache.get(mesh, mesh)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var l: Array = listen[art]
		mm.instance_count = l.size()
		for i in l.size():
			mm.set_instance_transform(i, l[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = tw._flora_mat
		wurzel.add_child(mmi)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			ziel = args[0]
		var mit_nah := args.size() < 2 or args.has("nah")
		var mit_wald := args.size() < 2 or args.has("wald")
		get_root().size = Vector2i(1800, 1100)
		root3 = Node3D.new()
		get_root().add_child(root3)
		_licht()
		cam = Camera3D.new()
		cam.far = 6000.0
		root3.add_child(cam)
		cam.current = true
		tw = TerrainWorld.new()
		tw.setup(12345, [], [], [], [])
		tw._flora_mat.set_shader_parameter("fade_start", 9000.0)
		tw._flora_mat.set_shader_parameter("fade_end", 10000.0)
		_boden(6000.0, Color(0.30, 0.44, 0.20))
		nah_root = Node3D.new()
		wald_root = Node3D.new()
		fern_root = Node3D.new()
		for w in [nah_root, wald_root, fern_root]:
			root3.add_child(w)
			(w as Node3D).visible = false
		if mit_nah:
			for g in NAH.size():
				var gruppe: Array = NAH[g]
				for k in gruppe.size():
					var mi := MeshInstance3D.new()
					if gruppe[k] == "Fels":
						# wie gesetzt: je Achse gestreckt, 0,3 m im Boden
						mi.mesh = tw._mesh_rock
						mi.scale = Vector3(2.4, 1.5, 1.9)
						mi.position = Vector3((k - 1) * 9.5, -0.3, 2000.0 + g * 200.0 + 6.0)
					elif tw._flora.has(gruppe[k]):
						mi.mesh = tw._flora[gruppe[k]]
						mi.scale = Vector3.ONE * 1.4
						mi.position = Vector3((k - 1) * 9.5, 0.0, 2000.0 + g * 200.0)
					else:
						continue
					mi.material_override = tw._flora_mat
					nah_root.add_child(mi)
				var m := Vector3(0, 6.5, 2000.0 + g * 200.0)
				ansichten.append(["nah%d_sonne" % g, nah_root, m + Vector3(9, 5.0, 31), m, 34.0])
				ansichten.append(["nah%d_oben" % g, nah_root, m + Vector3(-6, 24.0, 22), m - Vector3(0, 2.5, 0), 34.0])
				ansichten.append(["nah%d_gegen" % g, nah_root, m + Vector3(-12, 3.0, -30), m, 34.0])
		if mit_wald:
			_wald(wald_root, false, Vector3.ZERO, 420.0, 9000, 7)
			_wald(fern_root, true, Vector3(0, 0, -1900), 700.0, 26000, 9)
			ansichten.append(["wald_tief", wald_root, Vector3(40, 46, 330), Vector3(0, 4, 60), 64.0])
			ansichten.append(["wald_rand", wald_root, Vector3(-40, 14, 520), Vector3(0, 9, 380), 50.0])
			ansichten.append(["wald_sonne", wald_root, Vector3(-300, 42, -330), Vector3(0, 30, 20), 64.0])
			ansichten.append(["wald_gegen", wald_root, Vector3(-60, 60, -360), Vector3(0, 4, -60), 64.0])
			ansichten.append(["wald_hoch", wald_root, Vector3(-120, 300, 620), Vector3(0, 0, 0), 64.0])
			ansichten.append(["wald_fern", fern_root, Vector3(0, 200, -900), Vector3(0, 0, -1900), 30.0])
		_ansicht()
		return false
	if f == 14 + schuss * 8:
		var img := get_root().get_viewport().get_texture().get_image()
		var p: String = ziel.path_join("probe_%s.png" % ansichten[schuss][0])
		img.save_png(p)
		print("SHOT ", p)
		schuss += 1
		if schuss >= ansichten.size():
			quit()
			return true
		_ansicht()
	return false


func _ansicht() -> void:
	var a: Array = ansichten[schuss]
	for w in [nah_root, wald_root, fern_root]:
		(w as Node3D).visible = w == a[1]
	cam.look_at_from_position(a[2], a[3], Vector3.UP)
	cam.fov = a[4]
