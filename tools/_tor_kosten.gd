## KOSTEN DES FELSENTORS: wie viele Dreiecke stecken im Bogen und wie viele in der
## Schutthalde? Die Halde ist seit der Blockschuerze der groessere Posten, und sie hat
## keine Kollision — ohne diese Zahl faellt eine Ueberdosis erst im Spiel auf.
##
## Godot --headless --path . --script res://tools/_tor_kosten.gd
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 4:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	if f < 8:
		return false
	for name in ["Felsentor", "Torhalde"]:
		var n: Node = _suchen(root, name)
		if n == null:
			print("%s: nicht gefunden" % name)
			continue
		var tri := 0
		var netze := 0
		for mi in _meshes(n):
			netze += 1
			var m: Mesh = mi.mesh
			for s in m.get_surface_count():
				tri += m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size() / 3
		print("%s: %d Netze, %d Dreiecke" % [name, netze, tri])
	quit()
	return true


func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and n.mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _suchen(n: Node, name: String) -> Node:
	if n.name == name:
		return n
	for c in n.get_children():
		var r := _suchen(c, name)
		if r != null:
			return r
	return null
