## Regression für die B-29-Kanzel:
## - Das echte Blender-Modell wird statt des prozeduralen Fallbacks geladen.
## - Glasnase, Sprossen und Innenausbau sind vorhanden.
## - Rumpflack bleibt lackierbar, Glas bleibt ein eigenes Material.
## - Ein Rumpfsegment dockt an der ebenen Rückseite spaltfrei an.
extends SceneTree

var frame := 0
var failed := false


func _check(ok: bool, message: String) -> void:
	if ok:
		print("OK  ", message)
	else:
		failed = true
		push_error("FAIL  " + message)


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


func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count


func _mesh_center(node: Node) -> Vector3:
	var mi := node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return Vector3(INF, INF, INF)
	return mi.transform * mi.get_aabb().get_center()


func _mesh_parent_aabb(node: Node) -> AABB:
	var mi := node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return AABB()
	return mi.transform * mi.get_aabb()


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 2:
		return false

	var part := PartCatalog.get_part("cockpit_b29")
	_check(not part.is_empty(), "B-29-Kanzel ist im Katalog")
	_check(PartCatalog.in_palette("cockpit_b29"), "B-29-Kanzel ist in der Teilepalette")
	_check(PartCatalog.has_model("cockpit_b29"), "cockpit_b29.glb wird gefunden")
	_check(PartCatalog.in_palette("b29_wing"), "passende B-29-Tragfläche ist in der Palette")

	var visual := PartCatalog.build_visual(part)
	_check(visual.find_child("B29_Rumpf_mit_Nase", true, false) != null,
		"Nasenhaut und Rumpfzylinder sind ein einziges verschweißtes Mesh")
	_check(visual.find_child("B29_Nasenhaut", true, false) == null \
			and visual.find_child("B29_Rumpf_komplett", true, false) == null,
		"keine getrennten Nasen- oder Rumpfobjekte bleiben übrig")
	_check(visual.find_child("B29_Pilotenverglasung", true, false) == null,
		"keine aufgesetzte Pilotenverglasung überlappt die Rumpfhaut")
	_check(visual.find_child("B29_Innenraum", true, false) != null,
		"Innenausbau ist zu einer sauberen Baugruppe zusammengefasst")
	_check(_count_meshes(visual) == 4,
		"Export besteht nur aus vier Mesh-Baugruppen inklusive verschweißter Außenhaut")
	_check(visual.find_child("Astrodome", true, false) == null,
		"kein falscher Astrodome sitzt auf dem Cockpitteil")
	var front_glass := visual.find_child("B29_Glasdetails", true, false)
	var front_frame := visual.find_child("B29_Rahmendetails", true, false)
	_check(front_glass != null and front_frame != null,
		"Frontscheibe und Frontring sind getrennt prüfbar")
	if front_glass != null and front_frame != null:
		var glass_center := _mesh_center(front_glass)
		var frame_center := _mesh_center(front_frame)
		_check(Vector2(glass_center.x, glass_center.y).distance_to(
			Vector2(frame_center.x, frame_center.y)) < 0.001,
			"Frontscheibe und Frontring besitzen exakt denselben Mittelpunkt")
		var glass_box := _mesh_parent_aabb(front_glass)
		var frame_box := _mesh_parent_aabb(front_frame)
		_check(frame_box.size.z > 0.025 and frame_box.size.z < 0.040,
			"Frontring bildet eine kurze integrierte Ringlippe")
		_check(glass_box.position.z - frame_box.position.z > 0.002,
			"runde Frontscheibe sitzt sichtbar hinter der vorderen Ringkante")
	var paint := _find_material(visual, "cockpit_body")
	var glass := _find_material(visual, "glass")
	_check(paint != null, "cockpit_body ist als Lackmaterial erhalten")
	_check(glass != null, "Glas besitzt ein getrenntes Material")
	if glass != null:
		print("GLAS_IMPORT transparency=", glass.transparency,
			" color=", glass.albedo_color, " roughness=", glass.roughness)
		_check(glass.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
			"Glas ist vollständig blickdicht")
		_check(glass.albedo_color.a > 0.99,
			"Glas lässt den Innenraum nicht durchscheinen")
		_check(glass.roughness <= 0.13,
			"Glas behält einen klaren Bubble-Glanz")
		_check(glass.albedo_color.get_luminance() < 0.035,
			"Glas ist wie das Referenzobjekt fast schwarz")

	var bc := BuildController.new()
	root.add_child(bc)
	bc.clear_design()
	var cockpit := bc._place_id("cockpit_b29", Transform3D())
	bc._notify_changed()
	_check(cockpit.get_meta("part_id", "") == "cockpit_b29",
		"Kanzel kann als Wurzelteil platziert werden")
	var half_z: float = PartCatalog.col_size(part).z * 0.5
	var hit := {
		"position": cockpit.global_transform * Vector3(0, 0, half_z),
		"normal": cockpit.global_transform.basis * Vector3(0, 0, 1),
		"collider": cockpit.get_node_or_null("Pick"),
	}
	var snap := bc._compute_snap_for("fuselage", hit)
	_check(snap.get("valid", false), "Rumpfsegment rastet an der ebenen Rückseite ein")
	var fus := bc._place_id("fuselage", snap.get("xform", Transform3D()),
		snap.get("scale", Vector3.ONE))
	var fus_part := PartCatalog.get_part("fuselage")
	var cockpit_rear: float = cockpit.position.z + half_z
	var fus_front: float = fus.position.z - PartCatalog.col_size(fus_part).z * 0.5
	_check(absf(cockpit_rear - fus_front) < 0.001,
		"Rumpf und B-29-Kanzel schließen ohne sichtbaren Spalt")

	print("B29_COCKPIT_TEST ", "FAILED" if failed else "PASSED")
	visual.free()
	bc.free()
	quit(1 if failed else 0)
	return true
