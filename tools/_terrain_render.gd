extends SceneTree
## Offscreen-Render der Flugwelt (Terrain + Himmel + Sonne + Fog) in einen SubViewport,
## um den "Vibe" der Map ohne das schwarze Hauptfenster zu beurteilen.
## Godot --path . --script res://tools/_terrain_render.gd -- <out_prefix>

var frame := 0
var vp: SubViewport
var prefix := "/tmp/map"
var cam: Camera3D
var terrain: TerrainWorld
var _desert_c := Vector3.ZERO
var _mtn_c := Vector3.ZERO
var _peak := 0.0

var _shots: Array = []
var _si := 0

func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		var ua := OS.get_cmdline_user_args()
		if ua.size() >= 1 and ua[0] != "": prefix = ua[0]
		_setup()
		_shots = [
			["town",   Vector3(1140, 55, 880), Vector3(1400, 12, 730)],
			["lighthouse", Vector3(-872, 16, -1168), Vector3(-950, 12, -1252)],
			["mtn",    _mtn_c + Vector3(120, maxf(_peak, 120.0) * 0.7 + 60.0, 320.0),
			           _mtn_c + Vector3(0, _peak * 0.55, -60)],
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

	# --- Wolken-Himmel (Shader) + satte Farben ---
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky_clouds.gdshader")
	# Sonnenrichtung passend zur DirectionalLight unten (rot -50,-50)
	var sb := Basis.from_euler(Vector3(deg_to_rad(-50), deg_to_rad(-50), 0))
	sm.set_shader_parameter("sun_dir", sb.z)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.25                    # hell & luftig, aber nicht ausgebrannt
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.0
	# Weich-pastellig, hell — Farben bleiben sichtbar.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.04
	env.adjustment_contrast = 1.0
	env.adjustment_brightness = 1.0
	# Heller, luftiger Dunst MIT Substanz — Fernes verschwimmt sanft, wird aber
	# nicht weiß-gewaschen (Dichte/Aerial moderat, Farbe leicht blau statt weiß).
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.86, 0.89, 0.93)      # luftiges Blau-Milch
	env.fog_sun_scatter = 0.2
	env.fog_density = 0.00036
	env.fog_aerial_perspective = 0.46
	env.fog_sky_affect = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.18
	env.glow_strength = 0.85
	env.glow_hdr_threshold = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	w.add_child(we)

	# Hohe, neutrale Tagessonne — weiche Schatten, freundlich (kein Golden-Hour-Orange)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -50, 0)
	sun.light_color = Color(1.0, 0.98, 0.92)
	sun.light_energy = 1.2
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
	var smat := ShaderMaterial.new()
	smat.shader = load("res://shaders/water.gdshader")
	sea.material_override = smat
	sea.position = Vector3(0, TerrainWorld.SEA_Y, 0)
	w.add_child(sea)

	# --- Terrain + POIs (Stufe 2) ---
	terrain = TerrainWorld.new()
	var town_pos := Vector3(1400, 0, 750)
	var lake_pos := Vector3(1400, 0, 1030)
	var lh_pos := Vector3(-950, 0, -1250)
	var flat_zones := [
		{"pos": Vector3.ZERO, "r_flat": 1700.0, "r_blend": 2300.0},
		{"pos": town_pos, "r_flat": 360.0, "r_blend": 760.0},
		{"pos": lake_pos, "r_flat": 230.0, "r_blend": 520.0},
		{"pos": lh_pos, "r_flat": 110.0, "r_blend": 300.0},
	]
	var lakes := [{"pos": lake_pos, "r": 175.0, "surf": -1.0}]
	terrain.setup(20259, flat_zones, lakes)
	w.add_child(terrain)
	Landmarks.build_town(w, town_pos)
	Landmarks.build_lighthouse(w, lh_pos)
	terrain.build_now_around(town_pos, 700.0)
	terrain.build_now_around(lh_pos, 450.0)
	# Scan: finde ein Wüsten- und ein Hochgebirgs-Zentrum (Noise ist sofort abfragbar)
	var desert_c := Vector3(4200, 0, 0)
	var mtn_c := Vector3(0, 0, 4200)
	var best_relief := -1.0
	var found_desert := false
	for ang in range(0, 360, 12):
		for dist in [3200.0, 4000.0, 4800.0, 5600.0]:
			var dd: float = dist
			var px: float = cos(deg_to_rad(ang)) * dd
			var pz: float = sin(deg_to_rad(ang)) * dd
			var rel: float = terrain.relief_at(px, pz) * smoothstep(700.0, 3000.0, dd)
			if rel > best_relief:
				best_relief = rel; mtn_c = Vector3(px, 0, pz)
			if not found_desert and terrain.biome_at(px, pz) == 1:  # WUESTE
				found_desert = true; desert_c = Vector3(px, 0, pz)
	# höchsten Gipfel ums Gebirgs-Zentrum finden (für die Kamera-Höhe)
	var peak := 0.0
	for dx in range(-700, 701, 100):
		for dz in range(-700, 701, 100):
			peak = maxf(peak, terrain.height_at(mtn_c.x + dx, mtn_c.z + dz))
	print("DESERT @ ", desert_c, "  MTN @ ", mtn_c, "  peak=", peak, "  relief=", best_relief)
	terrain.build_now_around(Vector3.ZERO, 600.0)
	terrain.build_now_around(desert_c, 850.0)
	terrain.build_now_around(mtn_c, 950.0)
	_desert_c = desert_c
	_mtn_c = mtn_c
	_peak = peak

	cam = Camera3D.new()
	cam.fov = 62.0
	cam.far = 7000.0
	cam.current = true
	vp.add_child(cam)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

