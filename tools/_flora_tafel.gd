## Artentafel der Weltflora MIT DEM SPIELWEG: die Meshes kommen aus TerrainWorld._load_flora
## (weiche Kronen, verschweisstes Laub) und werden mit dem echten Flora-Material gezeichnet —
## so, wie sie im Flug erscheinen. Drei Blickwinkel (Augenhoehe, Schraegflug, von unten) plus
## die Fernstufe (_grob_cache) als eigene Reihe.
## Aufruf (FENSTER, nicht headless):
##   Godot --path . --script res://tools/_flora_tafel.gd -- <ausgabeordner>
extends SceneTree

var f := 0
var root3: Node3D
var cam: Camera3D
var tw: TerrainWorld
var ziel := "user://"
var schuss := 0
var ansichten := []


func _licht() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.74, 0.90)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.70, 0.78, 0.92)
	e.ambient_light_energy = 0.62
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root3.add_child(env)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-42, 35, 0)
	l.light_energy = 1.7
	l.light_color = Color(1.0, 0.91, 0.74)
	l.shadow_enabled = true
	l.directional_shadow_max_distance = 200.0
	root3.add_child(l)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			ziel = args[0]
		get_root().size = Vector2i(1800, 900)
		root3 = Node3D.new()
		get_root().add_child(root3)
		_licht()
		cam = Camera3D.new()
		cam.fov = 40.0
		root3.add_child(cam)
		cam.current = true
		tw = TerrainWorld.new()
		tw.setup(12345, [], [], [], [])
		var boden := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(400, 200)
		boden.mesh = pm
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.36, 0.48, 0.24)
		bm.roughness = 1.0
		boden.material_override = bm
		root3.add_child(boden)
		var x := -((TerrainWorld.ARTEN.size() - 1) * 9.0) * 0.5
		for art in TerrainWorld.ARTEN:
			var mesh: Mesh = tw._flora[art]
			for reihe in 2:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh if reihe == 0 else tw._grob_cache.get(mesh, mesh)
				mi.material_override = tw._flora_mat
				mi.position = Vector3(x, 0, -reihe * 30.0)
				root3.add_child(mi)
			x += 9.0
		# Felsbrocken am Ende der Reihe, einmal wie gesetzt (gestreckt) und einmal roh
		for k in 2:
			var fm := MeshInstance3D.new()
			fm.mesh = tw._mesh_rock
			fm.material_override = tw._flora_mat
			fm.position = Vector3(x + k * 4.0, -0.3, 0)
			fm.scale = Vector3(2.2, 1.4, 1.8) if k == 0 else Vector3.ONE
			root3.add_child(fm)
		# Je fuenf Arten ein Bild, einmal auf Augenhoehe, einmal schraeg von oben (Flug).
		var x0 := -((TerrainWorld.ARTEN.size() - 1) * 9.0) * 0.5
		for g in range(0, TerrainWorld.ARTEN.size(), 5):
			var n := mini(5, TerrainWorld.ARTEN.size() - g)
			var cx := x0 + (g + (n - 1) * 0.5) * 9.0
			ansichten.append(["seite%d" % int(g / 5.0), Vector3(cx, 4.5, 30.0), Vector3(cx, 5.5, 0)])
			ansichten.append(["schraeg%d" % int(g / 5.0), Vector3(cx, 26.0, 30.0), Vector3(cx, 3.0, -2.0)])
		ansichten.append(["fern", Vector3(0, 40.0, 60.0), Vector3(0, 0.0, -30.0)])
		ansichten.append(["unten", Vector3(0, 0.6, 22.0), Vector3(0, 9.0, -4.0)])
		_ansicht()
		return false
	if f == 12 + schuss * 10:
		var img := get_root().get_viewport().get_texture().get_image()
		var p: String = ziel.path_join("flora_%s.png" % ansichten[schuss][0])
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
	cam.look_at_from_position(a[1], a[2], Vector3.UP)
	if a[0] == "fern":
		cam.fov = 60.0
	elif a[0] == "unten":
		cam.fov = 70.0
		# nur die ersten sechs Arten, ganz nah
		cam.position.x = -((TerrainWorld.ARTEN.size() - 1) * 9.0) * 0.5 + 22.0
	else:
		cam.fov = 40.0
