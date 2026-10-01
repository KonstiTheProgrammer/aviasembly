## WAS KOSTET DIE HAFENSTADT? Bildzeit in 4K (Verfahren wie tools/_gelaende_zeit.gd: Median der
## Wandzeit, weil Metal keine GPU-Zeitstempel liefert) an vier Stellungen, jeweils mit und
## ohne den Knoten "Hafenstadt" (Haeuser, Statue, Kai, Schiffe, Stadtbaeume).
##   HOME=<test-home> Godot --path . --script res://tools/_hafen_zeit.gd
## HZ_ORT=grossstadt misst stattdessen die GROSSSTADT (Knoten "Grossstadt" + ihr Strassennetz).
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
	var mi := Hafenstadt.MITTE
	var gross := OS.get_environment("HZ_ORT") == "grossstadt"
	if gross:
		mi = Vector3(4300, 0, 2500)
	var stellungen := [
		["Kai 40 m", mi + Vector3(480, 40, 330), mi + Vector3(260, 6, -80)],
		["Stadt 150 m", mi + Vector3(-700, 150, -160), mi + Vector3(300, 0, 20)],
		["Anflug 400 m", mi + Vector3(1900, 400, 700), mi + Vector3(300, 0, 0)],
		["Fern 900 m", mi + Vector3(-3200, 900, -900), mi + Vector3(0, 0, 0)],
	]
	var fw: Node = main.get("fly_world")
	var teile: Array = [fw.get_node_or_null("Hafenstadt")]
	if gross:
		teile = [fw.get_node_or_null("Grossstadt"), fw.get_node_or_null("Strassen_4300_2500")]
		stellungen = [
			["Kern 45 m", mi + Vector3(-50, 45, 140), mi + Vector3(30, 20, 0)],
			["Stadt 150 m", mi + Vector3(-560, 150, -200), mi + Vector3(100, 0, 20)],
			["Anflug 400 m", mi + Vector3(1500, 400, 700), mi + Vector3(0, 0, 0)],
			["Fern 900 m", mi + Vector3(-3200, 900, -900), mi + Vector3(0, 0, 0)],
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
		var ohne := alles
		if teile[0] != null:
			for t in teile:
				if t != null:
					(t as Node3D).visible = false
			ohne = await _median()
			for t in teile:
				if t != null:
					(t as Node3D).visible = true
		print("HAFENZEIT %-14s alles %6.2f | ohne den Ort %6.2f | Ort %5.2f ms"
			% [st[0], alles.x, ohne.x, alles.x - ohne.x])
	_fertig = true
	quit()


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
