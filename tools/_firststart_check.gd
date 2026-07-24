## Erststart-Probe: ohne Speicherstand muss der Beispiel-Doppeldecker im Hangar stehen.
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
	if f == 30:
		var n := 0
		var ids := {}
		for c in m.build_ctrl.design_root.get_children():
			if c.is_in_group("part"):
				n += 1
				ids[String(c.get_meta("part_id"))] = true
		print("TEILE=", n, "  ids=", ids.keys())
		get_root().get_viewport().get_texture().get_image().save_png("user://ui_firststart.png")
		quit()
	return false
