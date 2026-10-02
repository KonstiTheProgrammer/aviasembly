## WAS KOSTET DER AUSBAU DER FELSENBASIS? Bildzeit in 4K (wie tools/_gelaende_zeit.gd: Median,
## MSAA 4x, Wandzeit, weil Metal keine GPU-Zeitstempel liefert) an vier Stellungen in und vor
## der Kaverne ADLERHORST, jeweils: alles / ohne den Ausbau (scripts/Bergbasis.gd: Netze
## "Ausbau*" und alle Schilder) / ohne die ganze Felsenbasis.
##
##   HOME=<test-home> Godot --path . --script res://tools/_kaverne_zeit.gd
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
	var basis: Node3D = main.fly_world.find_child("Felsenbasis", true, false)
	if basis == null:
		print("KAVERNENZEIT: keine Felsenbasis gefunden")
		_fertig = true
		quit()
		return
	var ausbau: Array[Node3D] = []
	for c in basis.get_children():
		if c is Label3D or String(c.name).begins_with("Ausbau"):
			ausbau.append(c)
	# Stellungen in Bauwerksmassen (x quer, y ueber Hallenboden, z ab Portal)
	var stellungen := [
		["Achse z 250", Vector3(0, 3.5, 250), Vector3(0, 9, 620)],
		["Seite z 470", Vector3(-62, 7, 470), Vector3(70, 10, 450)],
		["Mitte hoch", Vector3(50, 26, 380), Vector3(-20, 4, 760)],
		["Portal aussen", Vector3(0, 12, -110), Vector3(0, 18, 60)],
	]
	for st in stellungen:
		var p: Vector3 = basis.global_transform * (st[1] as Vector3)
		var z: Vector3 = basis.global_transform * (st[2] as Vector3)
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
		for n in ausbau:
			n.visible = false
		var ohne := await _median()
		for n in ausbau:
			n.visible = true
		basis.visible = false
		var ohne_basis := await _median()
		basis.visible = true
		print("KAVERNENZEIT %-14s alles %6.2f | Ausbau %5.2f  ganze Basis %5.2f ms"
			% [st[0], alles.x, alles.x - ohne.x, alles.x - ohne_basis.x])
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
