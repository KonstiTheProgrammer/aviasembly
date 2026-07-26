## Regression für den eigenständigen B-29-R-3350-Motor:
## - eigenes Blender-GLB und eigener sichtbarer Katalogeintrag,
## - Vierblattpropeller am animierbaren "Prop"-Pivot,
## - lackierbare Cowling, plane Montagefläche und charakteristische Details.
extends SceneTree

var frame := 0
var failed := false


func _check(ok: bool, message: String) -> void:
	if ok:
		print("OK  ", message)
	else:
		failed = true
		push_error("FAIL  " + message)


func _count_prefix(node: Node, prefix: String) -> int:
	var count := 1 if node.name.begins_with(prefix) else 0
	for child in node.get_children():
		count += _count_prefix(child, prefix)
	return count


func _find_material(node: Node, wanted: String) -> StandardMaterial3D:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for surface in mi.mesh.get_surface_count():
				var material := mi.get_active_material(surface)
				if material is StandardMaterial3D \
						and (material as StandardMaterial3D).resource_name == wanted:
					return material as StandardMaterial3D
	for child in node.get_children():
		var found := _find_material(child, wanted)
		if found != null:
			return found
	return null


func _visual_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var root_inv := node.global_transform.affine_inverse()
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is MeshInstance3D:
			var mi := current as MeshInstance3D
			var local_xf: Transform3D = root_inv * mi.global_transform
			var bounds: AABB = local_xf * mi.get_aabb()
			result = bounds if first else result.merge(bounds)
			first = false
		for child in current.get_children():
			stack.append(child)
	return result


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 2:
		return false

	var part: Dictionary = PartCatalog.get_part("b29_engine")
	_check(not part.is_empty(), "B-29-Motor ist im Teilekatalog")
	_check(PartCatalog.in_palette("b29_engine"), "B-29-Motor ist in der Baupalette sichtbar")
	_check(String(part.get("name", "")).contains("R-3350"), "historischer Motortyp ist benannt")
	_check(float(part.get("thrust", 0.0)) >= 15000.0, "schwerer Bombermotor besitzt passenden Schub")
	_check(absf(float(part.get("spin_mult", 1.0)) - 0.72) < 0.001,
		"großer Vierblattpropeller dreht mit schwerer Trägheit")
	_check(ResourceLoader.exists("res://models/b29_engine.glb"),
		"eigenständiges B-29-Blender-GLB ist vorhanden")

	var scene_res: PackedScene = load("res://models/b29_engine.glb") as PackedScene
	var model: Node3D = scene_res.instantiate() as Node3D if scene_res != null else null
	_check(model != null, "B-29-Motor-GLB lässt sich in Godot laden")
	if model != null:
		root.add_child(model)
		var prop: Node = model.find_child("Prop", true, false)
		_check(prop is Node3D, "animierbarer Prop-Pivot ist vorhanden")
		_check(_count_prefix(prop, "prop_blade_") == 4 if prop != null else false,
			"Prop-Pivot enthält genau vier Blätter")
		if prop is Node3D:
			var prop_bounds: AABB = _visual_bounds(prop as Node3D)
			print("B29_PROP_BOUNDS ", prop_bounds)
			_check(prop_bounds.size.x > 2.94 and prop_bounds.size.y > 2.94 \
					and prop_bounds.size.z < 0.48,
				"Propeller liegt korrekt in der X/Y-Scheibe und dreht um lokal Z")
		_check(model.find_child("B29_Cowling", true, false) is MeshInstance3D,
			"lange B-29-Cowling ist vorhanden")
		_check(model.find_child("rear_mount_face", true, false) is MeshInstance3D,
			"plane hintere Montagefläche ist vorhanden")
		_check(model.find_child("cowl_flaps", true, false) is MeshInstance3D,
			"hintere Kühlklappen sind vorhanden")
		_check(model.find_child("oil_cooler_opening", true, false) is MeshInstance3D,
			"unterer Ölkühler ist vorhanden")
		_check(model.find_child("exhaust_outlet_L", true, false) is MeshInstance3D \
				and model.find_child("exhaust_outlet_R", true, false) is MeshInstance3D,
			"beide Abgasstutzen sind vorhanden")
		var paint := _find_material(model, "engine")
		_check(paint != null, "Cowling besitzt das lackierbare engine-Material")
		if paint != null:
			_check(paint.metallic > 0.35 and paint.metallic < 0.50,
				"Cowling bleibt lackiertes Metall statt Chrom")
		var bounds: AABB = _visual_bounds(model)
		_check(bounds.size.x > 2.94 and bounds.size.y > 2.94,
			"Vierblattpropeller spannt ungefähr drei Meter auf")
		_check(bounds.size.z > 1.85 and bounds.size.z < 2.05,
			"Gondel und Spinner ergeben eine kompakte Gesamtlänge")

	var bc: BuildController = BuildController.new()
	root.add_child(bc)
	bc.clear_design()
	var placed: Node3D = bc._place_id("b29_engine", Transform3D())
	var visual: Node = placed.get_node_or_null("Visual")
	_check(visual != null, "B-29-Motor lässt sich im Hangar platzieren")
	_check(visual != null and visual.find_child("Prop", true, false) != null,
		"platzierter Motor behält den drehbaren Propeller")

	print("B29_ENGINE_TEST ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
	return true
