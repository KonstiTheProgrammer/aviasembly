## HAUS-TAFEL: Gebaeude aus world_buildings_hd.glb mit dem ECHTEN Spielweg (CityBuilder laedt
## und tauscht die Materialien gegen shaders/haus.gdshader) in einer kleinen Szene — ohne die
## Welt zu laden. Zum Beurteilen von Licht, Farbverlauf und Details.
##   Godot --path . --script res://tools/_haus_tafel.gd -- <ausgabeordner> [Typ Typ ...]
## Ohne Typen: eine Auswahl. HAUS_FERN=1 nimmt die Fernstufe.
extends SceneTree

var f := 0
var root3: Node3D
var cam: Camera3D
var ziel := "user://"
var namen: Array = ["Haus_Bauernhaus", "Haus_Fachwerk", "Haus_Kate", "Haus_Gasthaus",
	"Haus_Kirche", "Haus_Burg", "Haus_Wohnturm", "Haus_Bueroturm", "Haus_Kraftwerk"]
var schuss := 0
var ansichten := []


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			ziel = args[0]
		if args.size() > 1:
			namen = args.slice(1)
		get_root().size = Vector2i(1800, 900)
		root3 = Node3D.new()
		get_root().add_child(root3)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		var sky := Sky.new()
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = Color(0.30, 0.50, 0.85)
		psm.sky_horizon_color = Color(0.70, 0.81, 0.95)
		psm.ground_horizon_color = Color(0.55, 0.62, 0.50)
		psm.ground_bottom_color = Color(0.30, 0.36, 0.24)
		sky.sky_material = psm
		e.background_mode = Environment.BG_SKY
		e.sky = sky
		e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		e.ambient_light_energy = 0.62
		e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.environment = e
		root3.add_child(env)
		var l := DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-42, 145, 0)
		l.light_energy = 1.7
		l.light_color = Color(1.0, 0.95, 0.86)   # wie Main (Sonne)
		l.shadow_enabled = true
		l.directional_shadow_max_distance = 400.0
		root3.add_child(l)
		var boden := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1200, 600)
		boden.mesh = pm
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.36, 0.48, 0.24)
		bm.roughness = 1.0
		boden.material_override = bm
		root3.add_child(boden)
		CityBuilder.has_lib()
		var lib: Dictionary = CityBuilder._meshes if OS.get_environment("HAUS_FERN") != "" \
			else CityBuilder._meshes_hd
		var x := 0.0
		var hoch := 0.0
		for nm in namen:
			if not lib.has(nm):
				print("FEHLT: ", nm)
				continue
			var mesh: Mesh = lib[nm]
			var ab := mesh.get_aabb()
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.position = Vector3(x - ab.position.x, 0, 0)
			root3.add_child(mi)
			x += ab.size.x + 6.0
			hoch = maxf(hoch, ab.end.y)
		var breite := x - 6.0
		cam = Camera3D.new()
		cam.fov = 38.0
		root3.add_child(cam)
		cam.current = true
		var d := maxf(breite * 0.80, hoch * 2.2)
		var mitte := Vector3(breite * 0.5, hoch * 0.30, 0)
		# Blender -y (Vorderseite) ist in Godot +z
		ansichten = [
			["vorn", mitte + Vector3(-d * 0.25, d * 0.30, d)],
			["oben", mitte + Vector3(d * 0.2, d * 0.75, d * 0.7)],
			["hinten", mitte + Vector3(d * 0.3, d * 0.32, -d)],
		]
		cam.look_at_from_position(ansichten[0][1], mitte, Vector3.UP)
		set_meta("mitte", mitte)
		return false
	if f >= 14 and (f - 14) % 10 == 0 and schuss < ansichten.size():
		var img := get_root().get_viewport().get_texture().get_image()
		var p: String = ziel.path_join("haus_%s.png" % ansichten[schuss][0])
		img.save_png(p)
		print("SHOT ", p)
		schuss += 1
		if schuss >= ansichten.size():
			quit()
			return true
		cam.look_at_from_position(ansichten[schuss][1], get_meta("mitte"), Vector3.UP)
	return false
