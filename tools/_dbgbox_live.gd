## Schaltet die Debug-Ansicht im ECHTEN BuildController ein und prueft, dass je Teil zwei
## Drahtboxen entstehen und deren Ausdehnung zu col_size bzw. zur Geometrie passt.
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var bc := BuildController.new()
	root.add_child(bc)
	bc.load_design([
		{"id": "cockpit", "xform": Transform3D()},
		{"id": "wing_straight", "xform": Transform3D(Basis(), Vector3(0.6, 0, 0))},
		{"id": "wheel_jet", "xform": Transform3D(Basis(), Vector3(2.0, -0.074, 0))},
	])
	bc.set_debug_boxes(true)
	var dr := bc.design_root.get_node_or_null("DebugBoxen")
	if dr == null:
		print("FEHLER: kein DebugBoxen-Knoten")
		quit()
		return true
	print("Boxen-Knoten: ", dr.get_child_count(), " (erwartet 2 pro Teil)")
	for mi in dr.get_children():
		var v := mi as MeshInstance3D
		if v == null:
			continue
		var ab: AABB = v.global_transform * v.get_aabb()
		print("  Box  X %+.3f..%+.3f  Y %+.3f..%+.3f  Z %+.3f..%+.3f  Farbe=%s"
			% [ab.position.x, ab.end.x, ab.position.y, ab.end.y, ab.position.z, ab.end.z,
			   str(v.mesh.surface_get_material(0).albedo_color.to_html(false))])
	bc.set_debug_boxes(false)
	print("Aus: ", bc.design_root.get_node_or_null("DebugBoxen"))
	quit()
	return true
