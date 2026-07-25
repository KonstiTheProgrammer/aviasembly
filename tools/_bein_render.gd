## Ein Bild: dasselbe Fahrwerk bei 1.0 / 1.7 / 2.4 Beinlaenge nebeneinander.
## Nur so ist zu sehen, ob wirklich NUR die Stange waechst und Gabel/Achse bleiben.
extends SceneTree
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var root3 := Node3D.new()
		get_root().add_child(root3)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.13, 0.15, 0.18)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.60, 0.64, 0.72)
		e.ambient_light_energy = 1.6
		env.environment = e
		root3.add_child(env)
		var l := DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-38, 34, 0)
		l.light_energy = 2.4
		root3.add_child(l)
		var l2 := DirectionalLight3D.new()
		l2.rotation_degrees = Vector3(-16, -140, 0)
		l2.light_energy = 1.2
		root3.add_child(l2)
		var p := PartCatalog.get_part("wheel_jet")
		var x := -1.1
		for fak in [1.0, 1.7, 2.4]:
			var vis := PartCatalog.build_visual(p)
			PartCatalog.set_gear_length(vis, p, fak)
			vis.position = Vector3(x, 0, 0)
			root3.add_child(vis)
			x += 1.1
		var cam := Camera3D.new()
		root3.add_child(cam)
		cam.current = true
		cam.position = Vector3(-0.4, -0.55, 2.9)
		cam.look_at(Vector3(0.0, -0.75, 0), Vector3.UP)
		return false
	if f == 12:
		get_root().get_viewport().get_texture().get_image().save_png("user://bein_stufen.png")
		print("SHOT")
		quit()
		return true
	return false
