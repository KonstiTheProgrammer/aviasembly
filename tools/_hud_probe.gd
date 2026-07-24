## Schnell-Probe: nur Flug-HUD-Screenshot (ohne auf die Karten-Generierung zu warten).
extends SceneTree
var f := 0
var m: Node
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var ps: PackedScene = load("res://scenes/Main.tscn")
		m = ps.instantiate()
		get_root().add_child(m)
		return false
	if f == 20:
		m._set_mode(1)
		return false
	if f == 140:
		get_root().get_viewport().get_texture().get_image().save_png("user://ui_flug2.png")
		print("SHOT ui_flug2.png")
		quit()
	return false
