extends SceneTree
var f := 0
func _walk(n: Node, ind: String) -> void:
	print(ind, n.name, "  [", n.get_class(), "]", "  visible=", (n as Node3D).visible if n is Node3D else "-")
	for c in n.get_children():
		_walk(c, ind + "  ")
func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var ps: PackedScene = load("res://models/cockpit_radial.glb")
	_walk(ps.instantiate(), "")
	quit()
	return true
