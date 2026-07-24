## Generiert das Kartenbild (verifiziert INSEL-Form ohne Chunks) + rendert das M-Overlay.
extends SceneTree
var f := 0
var wm: WorldMap
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var t := TerrainWorld.new()
		t.setup(20259, [], [], [], [
			{"pos": Vector3(2400, 0, 1500), "r": 850.0, "peak": 205.0},
			{"pos": Vector3(5400, 0, -2600), "r": 1250.0, "peak": 230.0, "type": "vulkan"},
			{"pos": Vector3(7600, 0, -1800), "r": 520.0, "peak": 40.0, "type": "insel"},
			{"pos": Vector3(5800, 0, -5400), "r": 500.0, "peak": 34.0, "type": "insel"},
			{"pos": Vector3(1800, 0, -7500), "r": 600.0, "peak": 45.0, "type": "insel"},
			{"pos": Vector3(-5400, 0, 6200), "r": 700.0, "peak": 55.0, "type": "insel"},
			{"pos": Vector3(-6900, 0, 4300), "r": 430.0, "peak": 24.0, "type": "insel"},
			
		])
		var img := WorldMap.generate_image(t, 300)
		img.save_png("user://map_image.png")
		print("Kartenbild gespeichert")
		# Overlay mit Markern rendern
		DisplayServer.window_set_size(Vector2i(1600, 1000))
		wm = WorldMap.new()
		get_root().add_child(wm)
		wm.setup(img, [
			{"name": "HEIMAT", "pos": Vector3(0, 0, -100), "color": Color(0.9, 0.9, 0.95)},
			{"name": "NORDFELD", "pos": Vector3(-1500, 0, -2000), "color": Color(0.95, 0.75, 0.3)},
			{"name": "OSTHAFEN", "pos": Vector3(2200, 0, -250), "color": Color(0.45, 0.75, 0.98)},
			{"name": "BERGPISTE", "pos": Vector3(900, 0, 2000), "color": Color(0.95, 0.5, 0.45)},
		], [
			{"name": "Stadt", "pos": Vector3(1400, 0, 750), "color": Color(0.95, 0.85, 0.35)},
			{"name": "Leuchtturm", "pos": Vector3(-950, 0, -1250), "color": Color(0.95, 0.45, 0.40)},
			{"name": "Bergdorf", "pos": Vector3(2550, 0, 1650), "color": Color(0.80, 0.70, 0.55)},
			{"name": "Vulkan", "pos": Vector3(5400, 0, -2600), "color": Color(0.85, 0.35, 0.25)},
			{"name": "FLAK-ZONE", "pos": Vector3(250, 0, -2400), "color": Color(1.0, 0.25, 0.2)},
		], null)
		var dummy := Node3D.new()
		get_root().add_child(dummy)
		dummy.global_position = Vector3(600, 300, 400)
		dummy.rotate_y(0.8)
		wm.set_player(dummy)
		wm.visible = true
		return false
	if f == 8:
		get_root().get_viewport().get_texture().get_image().save_png("user://map_overlay.png")
		print("Overlay gespeichert")
		quit()
	return false
