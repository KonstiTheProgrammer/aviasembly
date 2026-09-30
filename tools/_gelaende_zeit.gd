## WAS KOSTET DAS GELAENDE? Bildzeit in 4K an fuenf Stellungen: alles, ohne Bodendetail
## (detail_staerke = 0 an Chunks und Schuerze), ohne Flora (Baeume/Felsen ausgeblendet).
## Verfahren wie tools/_wasser_zeit.gd (Median, 4K, weil Metal keine GPU-Zeitstempel liefert).
## Laeuft auch auf einem Stand ohne Detail-Shader (dann ist die Detailspalte ~0) — so laesst
## sich alt gegen neu vergleichen.
##
## HOME=<test-home> Godot --path . --script res://tools/_gelaende_zeit.gd
## GZ_NUR=Wald,Hang: nur diese Stellungen. GZ_ARTEN=1: zusaetzlich Flora-Kosten je Baumart.
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
	# [Name, Kamera, Ziel, relativ zum Boden?]
	var stellungen := [
		["Wald 22 m", Vector3(600, 22, -2400), Vector3(1300, 4, -3000), true],
		["Hang 40 m", Vector3(-2600, 40, -3800), Vector3(-2400, 60, -4600), true],
		["Schlucht", Vector3(-13686, 70, 11879), Vector3(-13600, 50, 12900), false],
		["Berge 950 m", Vector3(-2600, 950, -4500), Vector3(-2350, 700, -7000), false],
		["Mittel 700 m", Vector3(-6000, 700, 3000), Vector3(-7000, 300, 4000), false],
	]
	var gpu := false
	var summe := Vector3.ZERO
	var gras_summe := 0.0
	# GZ_NUR=Wald,Mittel: nur diese Stellungen (Namensanfang)
	var nur := OS.get_environment("GZ_NUR")
	if nur != "":
		var gewaehlt := []
		for st in stellungen:
			for w in nur.split(","):
				if String(st[0]).begins_with(w):
					gewaehlt.append(st)
		stellungen = gewaehlt
	for st in stellungen:
		var p: Vector3 = st[1]
		var z: Vector3 = st[2]
		if st[3]:
			p.y += maxf(main.terrain.height_at(p.x, p.z), TerrainWorld.SEA_Y)
			z.y += maxf(main.terrain.height_at(z.x, z.z), TerrainWorld.SEA_Y)
		cam.look_at_from_position(p, z, Vector3.UP)
		var ac = main.flight_ctrl.aircraft
		if is_instance_valid(ac):
			ac.global_position = p + Vector3(0, 30, 0)
			ac.freeze = true
		main.terrain.update_center(p)
		main.terrain.build_now_around(p, TerrainWorld.VIEW_DIST, false)
		# Bepflanzung und Schuerze nachziehen lassen
		for i in 600:
			await process_frame
			if (main.terrain.get("_flora_warteschlange") as Array).is_empty() \
					and main.call("fern_bereit", p):
				break
		var alles := await _median()
		_detail(0.0)
		var o_det := await _median()
		_detail(1.0)
		_flora(false)
		var o_flora := await _median()
		_flora(true)
		_gras(false)
		var o_gras := await _median()
		_gras(true)
		# GZ_ARTEN=1: Flora-Kosten JE ART (alle MultiMeshes dieser Art aus, Unterschied messen)
		if OS.get_environment("GZ_ARTEN") != "":
			var tw = main.terrain
			var arten: Dictionary = {"Fels": [tw._mesh_rock, tw._grob_cache.get(tw._mesh_rock)]}
			for art in tw._flora:
				arten[art] = [tw._flora[art], tw._grob_cache.get(tw._flora[art])]
			for art in arten:
				_art(arten[art], false)
				var o_art := await _median()
				_art(arten[art], true)
				print("    ART %-12s %5.2f ms" % [art, alles.x - o_art.x])
		gpu = gpu or alles.y > 0.0
		summe += Vector3(alles.x, alles.x - o_det.x, alles.x - o_flora.x)
		gras_summe += alles.x - o_gras.x
		print("GELAENDEZEIT %-14s alles %6.2f | Detail %5.2f  Flora %5.2f  Gras %5.2f ms"
			% [st[0], alles.x, alles.x - o_det.x, alles.x - o_flora.x, alles.x - o_gras.x])
	summe /= float(stellungen.size())
	print("GELAENDEZEIT %-14s alles %6.2f | Detail %5.2f  Flora %5.2f  Gras %5.2f ms"
		% ["MITTEL", summe.x, summe.y, summe.z, gras_summe / float(stellungen.size())])
	print("GELAENDEZEIT Quelle: ", "GPU-Zeitstempel" if gpu else "Wandzeit (4K)")
	_fertig = true
	quit()


func _detail(k: float) -> void:
	var mats: Array = [main.terrain.get("_mat"), main.get("_fern_mat")]
	for mt in mats:
		if mt is ShaderMaterial:
			(mt as ShaderMaterial).set_shader_parameter("detail_staerke", k)


## Graswiesen (TerrainWorld._gras_knoten) — auf einem Stand ohne Gras ein Leerlauf.
func _gras(an: bool) -> void:
	main.terrain.set("_gras_an", an)
	for n in main.terrain.find_children("Gras_*", "GPUParticles3D", true, false):
		(n as Node3D).visible = an


## Sichtbarkeit vor dem Ausblenden merken und EXAKT wiederherstellen. Frueher stellte
## _flora(true) jede MultiMesh auf sichtbar — auch die Fernfassungen, die TerrainWorld je
## nach Abstand gerade ausgeblendet hatte (voll und grob liegen als zwei Knoten je Art und
## Chunk vor). Danach zeichnete die Szene jeden Baum doppelt, und jede folgende Messung
## (Gras) lag zu hoch — daher die negativen Gras-Werte.
var _gemerkt: Dictionary = {}


func _art(meshes: Array, an: bool) -> void:
	for n in main.terrain.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm != null and mm.mesh in meshes:
			_setze(n as Node3D, an)


func _flora(an: bool) -> void:
	for n in main.terrain.find_children("*", "MultiMeshInstance3D", true, false):
		_setze(n as Node3D, an)


func _setze(n: Node3D, an: bool) -> void:
	if not an:
		_gemerkt[n] = n.visible
		n.visible = false
	elif _gemerkt.has(n):
		n.visible = _gemerkt[n]
		_gemerkt.erase(n)


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
