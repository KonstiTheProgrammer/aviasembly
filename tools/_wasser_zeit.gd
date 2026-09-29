## WAS KOSTET DAS WASSER? Bildzeit an drei Stellungen ueber dem Meer, einmal mit und
## einmal ohne Wasserflaechen (Meer, Seen, Fluesse) — die Differenz ist der Preis.
##
## Gleiches Verfahren wie tools/_bildzeit.gd (Median, GPU-Zeitstempel falls vorhanden,
## sonst Wandzeit). Auf dem Mac liefert Metal keine GPU-Zeitstempel und die Wandzeit klebt
## an der Bildwiederholrate — deshalb rendert dieses Werkzeug in 4K: dann liegt die
## Bildzeit ueber 8,3 ms und die Unterschiede werden ueberhaupt messbar.
##
## HOME=<test-home> Godot --path . --script res://tools/_wasser_zeit.gd
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
	var stellungen := [
		["Strand tief 45 m", Vector3(7188, 45, 26300), Vector3(7188, 0, 28500)],
		["Gegenlicht 110 m", Vector3(7400, 110, 26600), Vector3(5400, 0, 28300)],
		["offene See 2500 m", Vector3(20000, 2500, 38000), Vector3(21000, 0, 45000)],
	]
	var gpu := false
	for st in stellungen:
		cam.look_at_from_position(st[1], st[2], Vector3.UP)
		main.terrain.update_center(st[1])
		main.terrain.build_now_around(st[1], TerrainWorld.VIEW_DIST, false)
		var mit := await _median()
		_wasser(false)
		var ohne := await _median()
		_wasser(true)
		gpu = gpu or mit.y > 0.0
		print("WASSERZEIT %-20s mit %6.2f  ohne %6.2f  Wasser %5.2f ms"
			% [st[0], mit.x, ohne.x, mit.x - ohne.x])
	print("WASSERZEIT Quelle: ", "GPU-Zeitstempel" if gpu else "Wandzeit (4K)")
	_fertig = true
	quit()


func _wasser(an: bool) -> void:
	for n in main.terrain.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var m := mi.material_override as ShaderMaterial
		if m != null and m.shader != null and m.shader.resource_path.ends_with("water.gdshader"):
			mi.visible = an


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
