## Zwei Bilder: (1) alle sieben Arten nebeneinander, (2) ein echter Waldausschnitt aus
## der Welt. Nur so ist beurteilbar, ob die Baeume auch wirklich gut aussehen.
extends SceneTree
var f := 0
var root3: Node3D
var cam: Camera3D
var phase := 0

func _licht() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.56, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.78)
	e.ambient_light_energy = 1.1
	env.environment = e
	root3.add_child(env)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-48, 38, 0)
	l.light_energy = 1.5
	root3.add_child(l)

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		root3 = Node3D.new()
		get_root().add_child(root3)
		_licht()
		cam = Camera3D.new()
		root3.add_child(cam)
		cam.current = true
		# 1) Artentafel: die sieben Baeume in einer Reihe auf einem Grasstreifen
		var ps: PackedScene = load("res://models/world_trees.glb")
		var sc: Node = ps.instantiate()
		var x := -21.0
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.95
		for art in ["Fichte", "Kiefer", "Birke", "Eiche", "Palme", "Totholz", "Busch"]:
			var q := sc.find_child(art, true, false) as MeshInstance3D
			if q == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = q.mesh
			mi.material_override = mat
			mi.position = Vector3(x, 0, 0)
			root3.add_child(mi)
			x += 7.0
		var boden := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(90, 40)
		boden.mesh = pm
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.30, 0.42, 0.22)
		boden.material_override = bm
		root3.add_child(boden)
		cam.position = Vector3(0, 7.5, 30.0)
		cam.look_at(Vector3(0, 4.5, 0), Vector3.UP)
		return false
	if f == 10:
		var img := get_root().get_viewport().get_texture().get_image()
		img.save_png("user://baeume_arten.png")
		print("SHOT arten")
		# 2) echter Waldausschnitt
		for c in root3.get_children():
			if c is MeshInstance3D:
				c.queue_free()
		var tw := TerrainWorld.new()
		tw.setup(12345, [], [], [], [])
		root3.add_child(tw)
		tw.build_now_around(Vector3(700, 0, -1200), 420.0, false)
		var h: float = tw.height_at(700, -1200)
		cam.position = Vector3(700 - 46, h + 22.0, -1200 + 46)
		cam.look_at(Vector3(700, h + 6.0, -1200), Vector3.UP)
		return false
	if f == 26:
		var img2 := get_root().get_viewport().get_texture().get_image()
		img2.save_png("user://baeume_wald.png")
		print("SHOT wald")
		quit()
		return true
	return false
