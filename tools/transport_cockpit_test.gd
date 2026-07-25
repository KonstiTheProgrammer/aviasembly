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

	var part := PartCatalog.get_part("cockpit_transport")
	_check(not part.is_empty(), "Transport-Cockpit ist im Teilekatalog")
	_check(PartCatalog.in_palette("cockpit_transport"),
		"Transport-Cockpit ist in der Baupalette sichtbar")
	_check(PartCatalog.has_model("cockpit_transport"),
		"Spielkatalog verwendet das neue Blender-GLB")
	_check(part.get("root", false), "Transport-Cockpit kann als Wurzelteil starten")
	_check(not PartCatalog.in_palette("fuselage_transport"),
		"passendes Transport-Rumpfsegment entsteht nur automatisch")

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

	var bc := BuildController.new()
	root.add_child(bc)
	bc.clear_design()
	var cockpit := bc._place_id("cockpit_transport", Transform3D())
	bc._notify_changed()
	_check(cockpit.get_meta("part_id", "") == "cockpit_transport",
		"Transport-Cockpit lässt sich als erstes Bauteil platzieren")
	var cockpit_box: Vector3 = PartCatalog.col_size(part)
	var cockpit_offset: Vector3 = PartCatalog.col_offset(part)
	var hit := {
		# Absichtlich seitlich auf den geraden Kragen zielen: Der Spezial-Snap
		# muss das Segment trotzdem zur mittigen Rückseite führen.
		"position": cockpit.global_transform * Vector3(
			cockpit_box.x * 0.5, cockpit_offset.y,
			cockpit_offset.z + cockpit_box.z * 0.30),
		"normal": cockpit.global_transform.basis * Vector3(1, 0, 0),
		"collider": cockpit.get_node_or_null("Pick"),
	}
	var snap := bc._compute_snap_for("fuselage", hit)
	_check(snap.get("valid", false), "Metallkragen nimmt Rumpfsegmente tolerant an")
	_check(snap.get("id", "") == "fuselage_transport",
		"Standardrumpf wird automatisch zum passenden Transport-Profil")
	var segment_id: String = snap.get("id", "fuselage")
	var segment := bc._place_id(segment_id, snap.get("xform", Transform3D()),
		snap.get("scale", Vector3.ONE))
	bc._notify_changed()
	var segment_def := PartCatalog.get_part("fuselage_transport")
	var cockpit_rear: float = cockpit.position.z + cockpit_offset.z + cockpit_box.z * 0.5
	var segment_front: float = segment.position.z \
		+ PartCatalog.col_offset(segment_def).z \
		- PartCatalog.col_size(segment_def).z * 0.5
	_check(absf(cockpit_rear - segment_front) < 0.001,
		"Cockpit und Transport-Rumpf schließen ohne axialen Spalt")
	_check(segment.get_meta("pscale", Vector3.ZERO).is_equal_approx(Vector3.ONE),
		"Transport-Rumpf behält den exakten Cockpit-Querschnitt")
	var segment_hit := {
		"position": segment.global_transform * Vector3(
			0, PartCatalog.col_offset(segment_def).y,
			PartCatalog.col_size(segment_def).z * 0.5),
		"normal": segment.global_transform.basis * Vector3(0, 0, 1),
		"collider": segment.get_node_or_null("Pick"),
	}
	var chain_snap := bc._compute_snap_for("fuselage", segment_hit)
	_check(chain_snap.get("id", "") == "fuselage_transport",
		"weitere Rumpfsegmente führen das Transport-Profil als Kette fort")

	print("TRANSPORT_COCKPIT_TEST ", "FAILED" if failed else "PASSED")
	model.free()
	bc.free()
	quit(1 if failed else 0)
	return true
