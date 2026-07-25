## Prueft world_trees.glb: Knotennamen, Dreiecke und ob VERTEX-FARBEN ankommen.
## Ohne Farbattribut waeren die Baeume schwarz (die Flora wird mit ALBEDO=COLOR gezeichnet).
extends SceneTree
func _process(_d: float) -> bool:
	var ps := load("res://models/world_trees.glb")
	if ps == null:
		print("FEHLER: glb nicht geladen")
		quit()
		return true
	var sc: Node = ps.instantiate()
	for n in sc.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var m: Mesh = mi.mesh
		var fmt: int = m.surface_get_format(0)
		var hat_farbe: bool = (fmt & Mesh.ARRAY_FORMAT_COLOR) != 0
		var arr: Array = m.surface_get_arrays(0)
		var probe := "-"
		if hat_farbe and arr[Mesh.ARRAY_COLOR] != null:
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			if cols.size() > 0:
				probe = "%s .. %s" % [cols[0].to_html(false), cols[cols.size() - 1].to_html(false)]
		print("%-10s Flaechen=%d  Vertexfarben=%s  %s"
			% [mi.name, m.get_faces().size() / 3, hat_farbe, probe])
	quit()
	return true
