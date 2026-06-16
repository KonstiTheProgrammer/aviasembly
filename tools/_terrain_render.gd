extends SceneTree
## Offscreen-Render der Flugwelt (Terrain + Himmel + Sonne + Fog) in einen SubViewport,
## um den "Vibe" der Map ohne das schwarze Hauptfenster zu beurteilen.
## Godot --path . --script res://tools/_terrain_render.gd -- <out_prefix>

var frame := 0
var vp: SubViewport
var prefix := "/tmp/map"
var cam: Camera3D
var terrain: TerrainWorld

var _shots: Array = []
var _si := 0

func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		var ua := OS.get_cmdline_user_args()
		if ua.size() >= 1 and ua[0] != "": prefix = ua[0]
		_setup()
		var C := Vector3(3600, 0, 3600)
		_shots = [
			["mtn",  C + Vector3(0, 220, 760),   C + Vector3(120, 40, -300)],
			["low",  C + Vector3(-200, 90, 360), C + Vector3(150, 110, -700)],
			["spawn", Vector3(0, 80, 500),       Vector3(0, 25, -400)],
		]
		return false
	if frame == 6:
		print("chunks=", terrain.get_child_count(), " h(C)=", terrain.height_at(3600.0, 3600.0),
			" h(spawn+400)=", terrain.height_at(0.0, 400.0))
	# Pro Shot: Kamera setzen, 3 Frames rendern lassen, dann fotografieren
	if frame >= 6 and (frame - 6) % 3 == 0:
		var idx := (frame - 6) / 3
		if idx < _shots.size():
			var s = _shots[idx]
			cam.look_at_from_position(s[1], s[2], Vector3.UP)
	if frame >= 8 and (frame - 8) % 3 == 0:
		var idx := (frame - 8) / 3
		if idx < _shots.size():
			var s = _shots[idx]
			var img := vp.get_texture().get_image()
			img.save_png("%s_%s.png" % [prefix, s[0]])
			print("Render -> %s_%s.png" % [prefix, s[0]])
			if idx == _shots.size() - 1:
				quit()
				return true
	return false

func _setup() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	get_root().add_child(vp)
	var w := Node3D.new(); vp.add_child(w)

	# --- CLEAN BRIGHT DAYLIGHT (Aviassembly-Editor-Look) ---
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.40, 0.62, 0.90)        # heller, freundlicher blauer Himmel
	psm.sky_horizon_color = Color(0.86, 0.91, 0.97)    # fast weißer Horizont (clean)
	psm.sky_curve = 0.09
	psm.sky_energy_multiplier = 1.1
	psm.ground_horizon_color = Color(0.82, 0.88, 0.93)
	psm.ground_bottom_color = Color(0.58, 0.66, 0.66)
	psm.sun_angle_max = 4.0
	psm.sun_curve = 0.10
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.15                    # hell & gleichmäßig (low contrast, freundlich)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.0
	# Klare Sicht — nur ganz feiner blauer Dunst in der Ferne (aerial perspective),
	# das Panorama soll tragen, kein dichter Nebel.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.82, 0.88, 0.95)
	env.fog_sun_scatter = 0.1
	env.fog_density = 0.00012
	env.fog_aerial_perspective = 0.38
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_strength = 0.9
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)

	# Hohe, neutrale Tagessonne — weiche Schatten, freundlich (kein Golden-Hour-Orange)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -50, 0)
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	w.add_child(sun)
	var underfill := DirectionalLight3D.new()
	underfill.rotation_degrees = Vector3(58, 130, 0)
	underfill.light_color = Color(0.80, 0.86, 0.95)
	underfill.light_energy = 0.45
	w.add_child(underfill)

	# Sauberes, helles blaues Wasser (clean) — leicht spiegelnd
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(12000, 12000)
	sea.mesh = pm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.17, 0.42, 0.62)
	smat.metallic = 0.30; smat.roughness = 0.12
	smat.metallic_specular = 0.7
	sea.material_override = smat
	sea.position = Vector3(0, TerrainWorld.SEA_Y, 0)
	w.add_child(sea)

	# --- Terrain ---
	terrain = TerrainWorld.new()
	var flat_zones := [{"pos": Vector3.ZERO, "r_flat": 1700.0, "r_blend": 2300.0}]
	terrain.setup(20259, flat_zones)
	w.add_child(terrain)
	terrain.build_now_around(Vector3.ZERO, 1000.0)
	terrain.build_now_around(Vector3(3600, 0, 3600), 1500.0)

	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 7000.0
	cam.current = true
	vp.add_child(cam)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

