## Regression für den Blender-Raketenantrieb im Teilekatalog.
extends SceneTree

var _frame := 0
var _failed := false


func _check(ok: bool, message: String) -> void:
	if ok:
		print("OK  ", message)
	else:
		_failed = true
		push_error("FAIL  " + message)


func _collect(node: Node, meshes: Array[MeshInstance3D], materials: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		meshes.append(mi)
		if mi.mesh != null:
			for surface in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(surface)
				if mat != null:
					materials[mat.resource_name] = true
	for child in node.get_children():
		_collect(child, meshes, materials)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	var part: Dictionary = PartCatalog.get_part("rocket_engine")
	_check(not part.is_empty(), "Raketenantrieb ist im Katalog")
	_check(PartCatalog.in_palette("rocket_engine"), "Raketenantrieb ist in der Hangar-Palette")
	_check(PartCatalog.has_model("rocket_engine"), "rocket_engine.glb wird gefunden")
	_check(float(part.get("thrust", 0.0)) == 65000.0, "Raketenantrieb besitzt 65 kN Schub")
	_check(part.get("rocket_engine", false), "Raketen-Sondertyp ist gesetzt")
	var scene := load("res://models/rocket_engine.glb") as PackedScene
	var model := scene.instantiate() if scene != null else null
	_check(model != null, "GLB lässt sich instanzieren")
	if model != null:
		root.add_child(model)
		var meshes: Array[MeshInstance3D] = []
		var materials := {}
		_collect(model, meshes, materials)
		_check(meshes.size() == 8, "GLB besteht aus acht optimierten Meshgruppen")
		for wanted in ["engine", "gunmetal", "copper", "tube", "throat", "band", "lip", "soot"]:
			_check(materials.has(wanted), "Material %s ist erhalten" % wanted)
	print("ROCKET_ENGINE_TEST ", "FAILED" if _failed else "PASSED")
	quit(1 if _failed else 0)
	return true
