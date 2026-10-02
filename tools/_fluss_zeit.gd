## WAS KOSTEN DIE FLUESSE? Bildzeit in 4K (wie tools/_kaverne_zeit.gd: Median, MSAA 4x,
## Wandzeit, weil Metal keine GPU-Zeitstempel liefert) an Stellungen am Silberfluss und am
## Muehlbach, jeweils: alles / ohne Flussleben (scripts/Flussleben.gd) / ohne Schilf.
##
##   HOME=<test-home> Godot --path . --script res://tools/_fluss_zeit.gd
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
	for c in main.find_children("*", "CanvasLayer", true, false):
		c.visible = false
	var leben: Node3D = main.fly_world.find_child("Flussleben", true, false)
	if leben == null:
		print("FLUSSZEIT: kein Flussleben gefunden")
		_fertig = true
		quit()
		return
	var schilf: Array[Node3D] = []
	for c in leben.get_children():
		if String(c.name).begins_with("Schilf"):
			schilf.append(c)
	# Stellungen (Welt, absolut): Kamera, Blickziel
	var stellungen := [
		["Steg 2 m", Vector3(10695, 2.2, 8031), Vector3(10711, 0.5, 8002)],
		["Schilf 3 m", Vector3(9070, 3.0, 6700), Vector3(9200, 0.0, 6860)],
		["Tiefflug 60 m", Vector3(8100, 60.0, 4300), Vector3(8700, 0.0, 6100)],
		["Kaskaden 230 m", Vector3(5450, 420.0, -13150), Vector3(5700, 250.0, -13700)],
		["Muehle", Vector3(2124, 113.0, 1451), Vector3(2155, 103.0, 1456)],
	]
	for st in stellungen:
		var p: Vector3 = st[1]
		var z: Vector3 = st[2]
		cam.look_at_from_position(p, z, Vector3.UP)
		var ac = main.flight_ctrl.aircraft
		if is_instance_valid(ac):
			ac.global_position = p + Vector3(0, 30, 0)
			ac.freeze = true
		main.terrain.update_center(p)
		main.terrain.build_now_around(p, TerrainWorld.VIEW_DIST, false)
		for i in 600:
			await process_frame
			if (main.terrain.get("_flora_warteschlange") as Array).is_empty() \
					and main.call("fern_bereit", p):
				break
		var alles := await _median()
		for n in schilf:
			n.visible = false
		var ohne_schilf := await _median()
		for n in schilf:
			n.visible = true
		leben.visible = false
		var ohne := await _median()
		leben.visible = true
		print("FLUSSZEIT %-15s alles %6.2f | Flussleben %5.2f  davon Schilf %5.2f ms"
			% [st[0], alles.x, alles.x - ohne.x, alles.x - ohne_schilf.x])
	_fertig = true
	quit()


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
