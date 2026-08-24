## WOHIN GEHT DIE BILDZEIT? Messung an der ECHTEN Flugwelt, an mehreren Orten.
##
## NICHT HEADLESS AUFRUFEN. Ohne Fenster laeuft kein GPU-Pass, und gerade die Flora kostet
## fast nur dort — headless gemessen sieht sie zehn- bis hundertmal billiger aus, als sie
## ist. Aus demselben Grund zaehlt der MEDIAN und nicht die Spitze: macOS drosselt ein
## Fenster im Hintergrund, einzelne Bilder sind dann Ausreisser ohne Aussagekraft.
##
## Godot --path . --script res://tools/_bildzeit.gd
extends SceneTree

const AUFWAERMEN := 45
const PROBEN := 160

# [Name, Kameraposition, Blickziel] — Reiseflug, Tiefflug, Gebirge, Vulkan.
var _orte: Array = [
	["Reiseflug 1200 m", Vector3(0, 1200, -1500), Vector3(0, 200, -9000)],
	["Tiefflug ueber Wald", Vector3(300, 120, 900), Vector3(1700, 60, 2400)],
	["Hochgebirge", Vector3(-8700, 420, -5400), Vector3(-5598, 90, -9446)],
	["Vulkan", Vector3(11800, 1500, -2100), Vector3(11800, 330, -5600)],
]

var vp: SubViewport
var main: Node3D
var cam: Camera3D
var _los := false
var _fertig := false


func _process(_d: float) -> bool:
	if not _los:
		_los = true
		_lauf()
	return _fertig


func _lauf() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
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
	if main.sky_lights != null:
		main.sky_lights.visible = true
	main.camera.current = false
	cam.current = true
	main.mode = 1
	for c in main.get_children():
		if c is CanvasLayer:
			c.visible = false

	# Die Fernschuerze baut auf einem eigenen Thread und in zwei Stufen. Wer misst, bevor
	# die feine Stufe steht, misst die halbe Welt.
	var warte := 0
	while main._fern_stufe_knoten == null or warte < 60 * 32:
		await process_frame
		warte += 1
		if warte > 60 * 45:
			break

	print("Ort                     Median   p90     Bilder/s (Median)  Primitive   Draw Calls")
	for o in _orte:
		cam.look_at_from_position(o[1], o[2], Vector3.UP)
		main.terrain.update_center(o[1])
		main.terrain.build_now_around(o[1], TerrainWorld.VIEW_DIST, false)
		for i in AUFWAERMEN:
			await process_frame
		var zeiten := PackedFloat32Array()
		for i in PROBEN:
			var t0 := Time.get_ticks_usec()
			await process_frame
			zeiten.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		zeiten.sort()
		var med: float = zeiten[PROBEN / 2]
		var p90: float = zeiten[int(PROBEN * 0.9)]
		print("%-22s %6.2f ms %6.2f ms %8.0f          %9d %9d"
			% [o[0], med, p90, 1000.0 / maxf(med, 0.001),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	print("Videospeicher: %.0f MB" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
	_fertig = true
	quit()
