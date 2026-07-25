## Prueft, dass die Bohne beim Andocken wirklich zu ~40 % im Rumpf steckt.
extends SceneTree
var bc: BuildController
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	bc = BuildController.new()
	root.add_child(bc)
	bc.clear_design()
	var fus := bc._place_id("fuselage", Transform3D(Basis(), Vector3.ZERO))
	bc._notify_changed()
	var fd := PartCatalog.get_part("fuselage")
	var oben: float = PartCatalog.col_size(fd).y * 0.5          # Oberseite des Rumpfs
	var hit := {"position": Vector3(0, oben, 0), "normal": Vector3.UP,
		"collider": fus.get_node_or_null("Pick")}
	var snap := bc._compute_snap_for("canopy_bean", hit)
	if not snap.get("valid", false):
		print("KEIN Snap"); quit(); return true
	var b := bc._place_id("canopy_bean", snap["xform"], snap.get("scale", Vector3.ONE))
	bc._notify_changed()
	# tiefsten Punkt der Bohnen-Geometrie in Weltkoordinaten suchen
	var vis := b.get_node_or_null("Visual")
	var tief := INF
	var hoch := -INF
	var stack: Array = [vis]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			var a := mi.get_aabb()
			for k in 8:
				var w: Vector3 = mi.global_transform * a.get_endpoint(k)
				tief = minf(tief, w.y)
				hoch = maxf(hoch, w.y)
		for c in n.get_children():
			stack.append(c)
	var ganz: float = hoch - tief
	var drin: float = oben - tief
	print("Rumpf-Oberseite y=%.3f   Bohne y=%.3f..%.3f  (Hoehe %.3f)" % [oben, tief, hoch, ganz])
	print("EINGEBETTET: %.3f von %.3f  =  %.1f %%" % [drin, ganz, drin / ganz * 100.0])
	quit()
	return true
