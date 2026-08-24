## WAS KOSTET EIN BILD, UND WORAN LIEGT ES?
##
## Die Primitivenzahl allein sagt wenig: 9,3 Millionen klingen viel, aber ob sie weh tun,
## haengt daran, wie sie verteilt sind. Dieses Werkzeug misst die BILDZEIT an mehreren
## Kamerastellungen und schaltet dabei die grossen Posten einzeln ab, sodass man sieht,
## welcher davon sie traegt.
##
## GEMESSEN WIRD DER MEDIAN, nicht das Mittel: die ersten Bilder nach einem Kameraschwenk
## bauen Chunks nach und sind Ausreisser, die jeden Mittelwert unbrauchbar machen.
##
## Godot --path . --script res://tools/_bildzeit.gd
extends SceneTree

const BREITE := 1280
const HOCH := 720
const PROBEN := 90

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
	# VSYNC ZUERST AUS. Ohne das misst man 8,33 ms an jeder Stellung und bei jeder
	# Abschaltung — das ist 1/120 s und damit der Bildschirm, nicht die Szene. Genau
	# darauf ist der erste Messlauf hereingefallen.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	vp = SubViewport.new()
	vp.size = Vector2i(BREITE, HOCH)
	vp.msaa_3d = Viewport.MSAA_4X
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
	main.camera.current = false
	cam.current = true
	main.mode = 1
	for c in main.find_children("*", "CanvasLayer", true, false):
		c.visible = false

	var stellungen := [
		["Tiefflug ueber Wald", Vector3(700, 280, 200), Vector3(1700, 60, 1000)],
		["Reiseflug 1200 m", Vector3(0, 1200, -1500), Vector3(0, 200, -9000)],
		["ueber der Stadt", Vector3(4300, 420, 4100), Vector3(4300, 60, 2500)],
	]
	print("%-22s %7s %7s %7s %7s %7s %7s %7s"
		% ["Stellung", "alles", "-Flora", "-FlSchat", "-Fern", "-Gelae", "", ""])
	for st in stellungen:
		cam.look_at_from_position(st[1], st[2], Vector3.UP)
		main.terrain.update_center(st[1])
		main.terrain.build_now_around(st[1], TerrainWorld.VIEW_DIST, false)
		var zeile := "%-22s" % st[0]
		var calls := 0
		var prims := 0
		for fall in ["alles", "flora", "florasch", "schuerze", "gelaende"]:
			_schalten(fall)
			zeile += " %7.2f" % await _median()
			if fall == "alles":
				calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				prims = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			elif fall == "flora":
				zeile += "  (ohne Flora: %d Aufrufe)" % int(Performance.get_monitor(
					Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		print(zeile, " ms   |  alles: %d Zeichenaufrufe, %d Primitiven" % [calls, prims])
		_schalten("alles")
	_fertig = true
	quit()


## Genau EINEN Posten abschalten, alle anderen an. "alles" schaltet nichts ab.
##
## GELAENDE UND FLORA SIND GETRENNT: beide haengen an denselben Chunk-Knoten, das
## Gelaendenetz als MeshInstance3D, die Bepflanzung als MultiMeshInstance3D. Wer den
## ganzen Chunk unsichtbar macht, misst beide zusammen und lernt nichts.
func _schalten(fall: String) -> void:
	main.fern_root.visible = fall != "schuerze"
	for n in main.fly_world.get_children():
		var nm := String(n.name)
		if nm.begins_with("Cloud") or nm.begins_with("Wolken"):
			(n as Node3D).visible = fall != "wolken"
		elif n != main.terrain and n != main.fern_root and n is Node3D:
			# Alles uebrige in der Flugwelt: Staedte, Wahrzeichen, Schiffe, Windpark.
			(n as Node3D).visible = fall != "bauten"
	for c in main.terrain.get_children():
		if c is MeshInstance3D:
			# Die Wasserflaeche des Terrains haengt direkt unter ihm.
			(c as MeshInstance3D).visible = fall != "wasser"
			continue
		for k in c.get_children():
			if k is MultiMeshInstance3D:
				(k as MultiMeshInstance3D).visible = fall != "flora"
			elif k is MeshInstance3D:
				(k as MeshInstance3D).visible = fall != "gelaende"
			# "florasch": die Baeume bleiben SICHTBAR, werfen aber keinen Schatten mehr.
			# Damit trennt sich, was ihre Geometrie im Kamerapass kostet, von dem, was sie
			# in den vier Schattenkaskaden der Sonne kostet — dort laeuft dieselbe
			# Geometrie noch einmal je Kaskade.
			if k is MultiMeshInstance3D:
				(k as MultiMeshInstance3D).cast_shadow = (
					GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if fall == "florasch"
					else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


func _median() -> float:
	for i in 12:
		await RenderingServer.frame_post_draw      # einschwingen
	var w := PackedFloat32Array()
	for i in PROBEN:
		var t0 := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		w.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	w.sort()
	return w[PROBEN / 2]
