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
	_check(visual.find_child("B29_Nasenhaut", true, false) != null,
		"Metall, bündige Rahmen und Scheiben bilden eine gemeinsame Nasenhaut")
	_check(visual.find_child("B29_Pilotenverglasung", true, false) != null,
		"Pilotenfenster bilden eine gemeinsame Verglasungsgruppe")
	_check(visual.find_child("B29_Rumpf_komplett", true, false) != null,
		"Rumpf und Kinn sind zu einer sauberen Baugruppe zusammengefasst")
	_check(visual.find_child("B29_Innenraum", true, false) != null,
		"Innenausbau ist zu einer sauberen Baugruppe zusammengefasst")
	_check(visual.find_child("Astrodome", true, false) == null,
		"kein falscher Astrodome sitzt auf dem Cockpitteil")
	var paint := _find_material(visual, "cockpit_body")
	var glass := _find_material(visual, "glass")
	_check(paint != null, "cockpit_body ist als Lackmaterial erhalten")
	_check(glass != null, "Glas besitzt ein getrenntes Material")
	if glass != null:
		_check(glass.albedo_color.b > glass.albedo_color.r * 2.0,
			"Glasnase ist dunkelblau getönt")

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
