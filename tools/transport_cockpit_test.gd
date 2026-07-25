## Regressionstest für das eigenständige moderne Transport-Cockpit.
extends SceneTree

var frame := 0
var failed := false


func _check(ok: bool, message: String) -> void:
	if ok:
		print("OK  ", message)
	else:
		failed = true
		push_error("FAIL  " + message)


func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_meshes(child)
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


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 2:
		return false

	var packed := load("res://models/cockpit_transport.glb") as PackedScene
	_check(packed != null, "Transport-Cockpit-GLB lässt sich in Godot laden")
	if packed == null:
		quit(1)
		return true

	var model := packed.instantiate()
	root.add_child(model)
	var hull := model.find_child("Transport_Cockpit_Hull", true, false) as MeshInstance3D
	var details := model.find_child("Transport_Cockpit_Details", true, false) as MeshInstance3D
	_check(hull != null, "integrierte Cockpit-Außenhaut ist vorhanden")
	_check(details != null, "Details liegen in einer eigenen sauberen Meshgruppe")
	_check(_count_meshes(model) == 2, "GLB enthält genau zwei Meshgruppen")

	var body := _find_material(model, "cockpit_body")
	var frame_mat := _find_material(model, "frame")
	var glass := _find_material(model, "glass")
	var detail_mat := _find_material(model, "body_detail")
	_check(body != null, "lackierbares cockpit_body-Material ist erhalten")
	_check(frame_mat != null, "Fensterrahmen besitzen ein eigenes Material")
	_check(glass != null, "dunkles Glas besitzt ein eigenes Material")
	_check(detail_mat != null, "Radom und Kleinteile besitzen body_detail")
	if glass != null:
		print("TRANSPORT_GLASS color=", glass.albedo_color,
			" roughness=", glass.roughness)
		_check(glass.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
			"Transport-Cockpitglas ist blickdicht")
		_check(glass.albedo_color.get_luminance() < 0.08,
			"Glas ist passend zum Spielstil fast schwarz")
		_check(glass.roughness <= 0.56, "Glas bleibt dunkel mit weicher Reflexion")

	if hull != null and hull.mesh != null:
		var bounds: AABB = hull.transform * hull.get_aabb()
		_check(bounds.size.x > 2.19 and bounds.size.x < 2.23,
			"Rumpfbreite liegt bei ungefähr 2,20 m")
		_check(bounds.size.y > 1.84 and bounds.size.y < 1.88,
			"Rumpfhöhe liegt bei ungefähr 1,86 m")
		_check(bounds.size.z > 2.94 and bounds.size.z < 2.96,
			"kurzer Bug ist ungefähr 2,95 m lang")
		_check(absf(bounds.end.z - 1.40) < 0.001,
			"ebene hintere Andockfläche liegt exakt bei lokal Z=+1,40")

	print("TRANSPORT_COCKPIT_TEST ", "FAILED" if failed else "PASSED")
	model.free()
	quit(1 if failed else 0)
	return true
