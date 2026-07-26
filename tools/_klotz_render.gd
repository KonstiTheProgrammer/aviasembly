## Drei Kloetze nebeneinander: scharf, halb gerundet, voll gerundet — dazu einer mit nur
## EINER runden Ecke. Nur im Bild ist zu beurteilen, ob die Rundung glatt wirkt.
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
		e.ambient_light_color = Color(0.58, 0.62, 0.70)
		e.ambient_light_energy = 1.3
		env.environment = e
		root3.add_child(env)
		var l := DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-42, 32, 0)
		l.light_energy = 2.2
		root3.add_child(l)
		var l2 := DirectionalLight3D.new()
		l2.rotation_degrees = Vector3(-14, -145, 0)
		l2.light_energy = 1.0
		root3.add_child(l2)
		var p := PartCatalog.get_part("block")
		var x := -2.4
		for stufe in [0.0, 0.5, 1.0, -1.0]:
			var vis := PartCatalog.build_visual(p)
			var ra := PartCatalog.block_radien_neu()
			if stufe < 0.0:
				ra[7] = 1.0                     # nur eine Ecke
			else:
				for i in 8:
					ra[i] = stufe
			PartCatalog.set_block_rounding(vis, p, ra)
			vis.position = Vector3(x, 0, 0)
			root3.add_child(vis)
			x += 1.6
		var cam := Camera3D.new()
		root3.add_child(cam)
		cam.current = true
		cam.position = Vector3(-1.3, 1.9, 4.2)
		cam.look_at(Vector3(-0.4, 0.0, 0), Vector3.UP)
		return false
	if f == 12:
		get_root().get_viewport().get_texture().get_image().save_png("user://klotz.png")
		print("SHOT")
		quit()
		return true
	return false
