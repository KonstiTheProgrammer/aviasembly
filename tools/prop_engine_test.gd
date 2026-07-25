## Regression für den normalen Propellermotor:
## - Standardlack ist weiß und fast nicht metallisch.
## - Das Modell enthält die neuen Reihenmotor-Details, aber keine Sternzylinder.
## - Motor->Rumpf und Rumpf->Motor verwenden beide die echte Cut-Variante.
extends SceneTree

var frame := 0
var failed := false


func _check(ok: bool, message: String) -> void:
	if ok:
		print("OK  ", message)
	else:
		failed = true
		push_error("FAIL  " + message)


func _hit_on(part: Node3D, local_pos: Vector3, local_n: Vector3) -> Dictionary:
	return {
		"position": part.global_transform * local_pos,
		"normal": (part.global_transform.basis * local_n).normalized(),
		"collider": part.get_node_or_null("Pick"),
	}


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

	var bc := BuildController.new()
	root.add_child(bc)
	bc.clear_design()

	print("=== Propellermotor auf Rumpf ===")
	var fus := bc._place_id("fuselage", Transform3D())
	var fus_def := PartCatalog.get_part("fuselage")
	var hit := _hit_on(fus,
		Vector3(0, 0, -PartCatalog.col_size(fus_def).z * 0.5), Vector3(0, 0, -1))
	var snap := bc._compute_snap_for("prop_engine", hit)
	_check(snap.get("valid", false), "Motor rastet an der Rumpfnase ein")
	_check(String(snap.get("id", "")) == "prop_engine_nose",
		"Motor wird beim Andocken zur Cut-Variante")
	var snap_color: Color = snap.get("color", Color.BLACK)
	_check(snap_color.a == 0.0,
		"weiße Serienlackierung wird nicht von der Rumpffarbe überschrieben")

	var nose := bc._place_id(String(snap.get("id", "prop_engine_nose")),
		snap.get("xform", Transform3D()), snap.get("scale", Vector3.ONE),
		snap.get("color", Color(0, 0, 0, 0)))
	var visual := nose.get_node_or_null("Visual")
	_check(visual != null and visual.find_child("flat_fuselage_cut", true, false) != null,
		"Cut-Modell besitzt eine echte plane Rumpf-Schnittfläche")
	_check(visual != null and visual.find_child("cooling_louver", true, false) != null,
		"Kühlkiemen sind vorhanden")
	_check(visual != null and visual.find_child("service_panel", true, false) != null,
		"Wartungsdeckel ist vorhanden")
	_check(visual != null and visual.find_child("exhaust_stack", true, false) != null,
		"seitliche Reihenmotor-Auspuffstutzen sind vorhanden")
	_check(visual != null and visual.find_child("cylinder_barrel", true, false) == null,
		"keine sichtbaren Sternmotor-Zylinder mehr")
	var paint := _find_material(visual, "engine")
	_check(paint != null, "lackierbares engine-Material ist vorhanden")
	if paint != null:
		_check(paint.albedo_color.r > 0.85 and paint.albedo_color.g > 0.85 \
				and paint.albedo_color.b > 0.85, "Serienfarbe ist weiß")
		_check(paint.metallic < 0.15, "weiße Verkleidung ist nicht metallisch")

	var nose_def := PartCatalog.get_part("prop_engine_nose")
	var nose_scale: Vector3 = snap.get("scale", Vector3.ONE)
	var rear_z: float = nose.position.z + PartCatalog.col_size(nose_def).z * nose_scale.z * 0.5
	var fus_front_z: float = fus.position.z - PartCatalog.col_size(fus_def).z * 0.5
	_check(absf(rear_z - fus_front_z) < 0.001, "Cut-Fläche liegt spaltfrei am Rumpf")

	print("=== Rumpf auf bereits platzierten Propellermotor ===")
	bc.clear_design()
	var engine := bc._place_id("prop_engine", Transform3D())
	var reverse_hit := _hit_on(engine, Vector3(0.5, 0, 0), Vector3(1, 0, 0))
	var reverse_snap := bc._compute_snap_for("fuselage", reverse_hit)
	_check(reverse_snap.get("valid", false), "Rumpf rastet auch an einen bestehenden Motor ein")
	_check(reverse_snap.get("cut_target") == engine,
		"bestehender Motor ist als Cut-Ziel markiert")
	var reverse_fus := bc._place_id("fuselage", reverse_snap.get("xform", Transform3D()),
		reverse_snap.get("scale", Vector3.ONE))
	bc._convert_prop_to_nose(reverse_snap.get("cut_target") as Node3D)
	_check(String(engine.get_meta("part_id", "")) == "prop_engine_nose",
		"bestehender Motor wird beim Drop zur Cut-Variante")
	var reverse_scale: Vector3 = engine.get_meta("pscale", Vector3.ONE)
	var reverse_rear: float = engine.position.z \
		+ PartCatalog.col_size(nose_def).z * reverse_scale.z * 0.5
	var reverse_fus_def := PartCatalog.get_part("fuselage")
	var reverse_fus_scale: Vector3 = reverse_fus.get_meta("pscale", Vector3.ONE)
	var reverse_front: float = reverse_fus.position.z \
		- PartCatalog.col_size(reverse_fus_def).z * reverse_fus_scale.z * 0.5
	_check(absf(reverse_rear - reverse_front) < 0.001,
		"umgekehrte Baurichtung bleibt ebenfalls spaltfrei")

	print("PROP_ENGINE_TEST ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
	return true
