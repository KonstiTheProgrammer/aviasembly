extends SceneTree
func _process(_d: float) -> bool:
	for id in ["wheel_retract", "wheel_jet", "wheel_spitfire"]:
		var p := PartCatalog.get_part(id)
		print("--- ", id, "  model=", p.get("model", "<keins>"))
		var res := load("res://models/%s.glb" % id)
		print("    load() = ", res)
		var vis := PartCatalog.build_visual(p)
		var namen := PackedStringArray()
		for n in vis.find_children("*", "", true, false):
			namen.append(n.name)
		print("    Knoten: ", ", ".join(namen))
	quit()
	return true
