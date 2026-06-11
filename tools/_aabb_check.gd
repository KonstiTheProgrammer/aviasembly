extends SceneTree
## Druckt für jedes Preset-Teil die Welt-AABB des Visuals (z-Bereich) — Lückensuche.

var frame := 0

func _process(_d: float) -> bool:
	frame += 1
	if frame < 2: return false
	var f := FileAccess.open("res://designs/mig21.json", FileAccess.READ)
	var arr: Array = JSON.parse_string(f.get_as_text())
	var root := Node3D.new()
	get_root().add_child(root)
	for e in arr:
		var id: String = e["id"]
		var x: Array = e["xform"]
		var b := Basis(Vector3(x[0],x[1],x[2]), Vector3(x[3],x[4],x[5]), Vector3(x[6],x[7],x[8]))
		var pos := Vector3(x[9],x[10],x[11])
		var vis := PartCatalog.build_visual(PartCatalog.get_part(id), Color(0.7,0.7,0.7))
		root.add_child(vis)
		var sc: Array = e.get("scale", [1,1,1])
		vis.transform = Transform3D(b, pos).scaled_local(Vector3(sc[0],sc[1],sc[2]))
		var ab := _vis_aabb(vis)
		print("%-14s pos=(%.2f,%.2f,%.2f)  x[%.2f..%.2f] y[%.2f..%.2f] z[%.2f..%.2f]" % [
			id, pos.x, pos.y, pos.z,
			ab.position.x, ab.position.x+ab.size.x,
			ab.position.y, ab.position.y+ab.size.y,
			ab.position.z, ab.position.z+ab.size.z])
	quit()
	return true

func _vis_aabb(n: Node3D) -> AABB:
	var ab := AABB()
	var first := true
	var stack: Array = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			var m := (c as MeshInstance3D)
			var gab := m.global_transform * m.get_aabb()
			if first: ab = gab; first = false
			else: ab = ab.merge(gab)
		for k in c.get_children(): stack.append(k)
	return ab
