## WAS KOSTET DER BILD-LOOK? Glow, Flug-Blick (shaders/flug_blick) und Wolken, je einzeln
## abgeschaltet, in 4K an drei Flugstellungen. Verfahren wie tools/_wasser_zeit.gd.
##
## HOME=<test-home> Godot --path . --script res://tools/_gefuehl_zeit.gd
extends SceneTree
const BREITE := 3840
const HOCH := 2160
const PROBEN := 120

var vp: SubViewport
var main: Node3D
var cam: Camera3D
var _f := 0
var _fertig := false


func _process(_d: float) -> bool:
	if _f == 0:
		_f = 1
		_lauf()
	return _fertig


func _lauf() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	vp = SubViewport.new()
	vp.size = Vector2i(BREITE, HOCH)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	main = load("res://scenes/Main.tscn").instantiate()
	vp.add_child(main)
	cam = Camera3D.new()
	cam.far = 9000.0
	vp.add_child(cam)
	ViewUtil.apply_vfov(cam, 64.0)
	cam.current = true
	await process_frame
	await process_frame
	main.build_ctrl.set_active(false)
	main.build_ctrl.design_root.visible = false
	main.build_root.visible = false
	main.flight_root.visible = false
	main.world_env.environment = main.env_sky
	main.fly_world.visible = true
	if main.showroom != null:
		main.showroom.set_stage_visible(false)
	main.camera.current = false
	cam.current = true
	main.mode = 1
	main.flight_root.visible = true
	main.flight_hud.visible = false
	var stellungen := [
		["Sonne ueber See", Vector3(7400, 140, 26600), Vector3(5000, 900, 28600)],
		["Wolken 1050 m", Vector3(1500, 1050, -2500), Vector3(4000, 900, -1900)],
		["Berge 950 m", Vector3(-2600, 950, -4500), Vector3(-2350, 700, -7000)],
		["Gewitter nah", Vector3(29200, 1200, 600), Vector3(31500, 1800, 2500)],
		["Nebelmeer", Vector3(-32500, 440, 9500), Vector3(-29000, 350, 9700)],
	]
	var gpu := false
	for st in stellungen:
		cam.look_at_from_position(st[1], st[2], Vector3.UP)
		main.terrain.update_center(st[1])
		main.terrain.build_now_around(st[1], TerrainWorld.VIEW_DIST, false)
		var env: Environment = main.get("env_sky")
		var blick: Control = main.get("_blick") if "_blick" in main else null
		if blick != null:
			blick.visible = true
		var alles := await _median()
		env.glow_enabled = false
		var o_glow := await _median()
		env.glow_enabled = true
		var o_blick := alles
		if blick != null:
			blick.visible = false
			o_blick = await _median()
			blick.visible = true
		_wolken(false)
		var o_wolken := await _median()
		_wolken(true)
		for f in main.get("wolken_formationen"):
			(f as Node3D).visible = false
		var o_form := await _median()
		for f in main.get("wolken_formationen"):
			(f as Node3D).visible = true
		var himmel := env.sky.sky_material as ShaderMaterial
		himmel.set_shader_parameter("zirren", 0.0)
		var o_zirren := await _median()
		himmel.set_shader_parameter("zirren", 0.30)
		gpu = gpu or alles.y > 0.0
		print("LOOKZEIT %-16s alles %6.2f | Glow %5.2f  Blick %5.2f  Decken %5.2f  Formationen %5.2f  Zirren %5.2f ms"
			% [st[0], alles.x, alles.x - o_glow.x, alles.x - o_blick.x, alles.x - o_wolken.x,
				alles.x - o_form.x, alles.x - o_zirren.x])
	print("LOOKZEIT Quelle: ", "GPU-Zeitstempel" if gpu else "Wandzeit (4K)")
	_fertig = true
	quit()


func _wolken(an: bool) -> void:
	for c in main.get("cloud_fields"):
		(c as Node3D).visible = an


## Median der Bildzeit; x = verwendeter Wert, y = GPU-Zeit (0 wenn nicht verfuegbar).
func _median() -> Vector2:
	for i in 20:
		await RenderingServer.frame_post_draw
	var w := PackedFloat32Array()
	var g := PackedFloat32Array()
	for i in PROBEN:
		var t0 := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		w.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		g.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
	w.sort()
	g.sort()
	var gm := g[int(PROBEN * 0.5)]
	return Vector2(gm if gm > 0.0 else w[int(PROBEN * 0.5)], gm)
