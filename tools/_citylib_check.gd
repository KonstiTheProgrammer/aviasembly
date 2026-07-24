extends SceneTree
func _process(_d: float) -> bool:
	var ps: PackedScene = load("res://models/world_buildings.glb")
	if ps == null:
		print("LIB: load() -> null")
		quit(); return true
	var r := ps.instantiate()
	print("ROOT ", r.name, " Kinder=", r.get_child_count())
	var n := 0
	for c in r.get_children():
		if n < 4:
			print("  ", c.name, " [", c.get_class(), "]")
		n += 1
	print("has_lib()=", CityBuilder.has_lib(), "  Meshes=", CityBuilder._meshes.size())
	quit()
	return true
