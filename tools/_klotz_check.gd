## Prueft den Klotz: Mesh scharf vs. gerundet, Rundung EINZELN pro Ecke, und dass die
## acht Eckgriffe nur beim Klotz erscheinen.
extends SceneTree
var f := 0

func _eckabstand(m: Mesh, e: Vector3, halb: Vector3) -> float:
	## Wie weit ist die Geometrie von der theoretischen scharfen Ecke entfernt?
	var ecke := Vector3(e.x * halb.x, e.y * halb.y, e.z * halb.z)
	var best := 9.9
	var arr: Array = m.surface_get_arrays(0)
	for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		best = minf(best, v.distance_to(ecke))
	return best

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var p := PartCatalog.get_part("block")
	if p.is_empty():
		print("FEHLER: Teil block fehlt")
		quit()
		return true
	var halb: Vector3 = (p.get("size", Vector3.ONE) as Vector3) * 0.5
	print("Klotz size=%s" % str(p.get("size")))
	var scharf := PartCatalog.block_radien_neu()
	var m0 := PartCatalog._block_mesh(p["size"], scharf)
	print("  scharf:      %d Dreiecke" % (m0.get_faces().size() / 3))
	var alle := PartCatalog.block_radien_neu()
	for i in 8:
		alle[i] = 1.0
	var m1 := PartCatalog._block_mesh(p["size"], alle)
	print("  alle rund:   %d Dreiecke" % (m1.get_faces().size() / 3))
	# nur Ecke 0 (-x,-y,-z) runden
	var eine := PartCatalog.block_radien_neu()
	eine[0] = 1.0
	var m2 := PartCatalog._block_mesh(p["size"], eine)
	print("  Ecke 0 rund: %d Dreiecke" % (m2.get_faces().size() / 3))
	print("  Abstand Geometrie <-> scharfe Ecke:")
	for i in 8:
		var e := Vector3(1.0 if (i & 1) != 0 else -1.0, 1.0 if (i & 2) != 0 else -1.0,
			1.0 if (i & 4) != 0 else -1.0)
		print("    Ecke %d  scharf=%.3f  alle_rund=%.3f  nur_Ecke0=%.3f"
			% [i, _eckabstand(m0, e, halb), _eckabstand(m1, e, halb),
			   _eckabstand(m2, e, halb)])
	# Griffe
	var bc := BuildController.new()
	root.add_child(bc)
	bc.load_design([
		{"id": "cockpit", "xform": Transform3D()},
		{"id": "block", "xform": Transform3D(Basis(), Vector3(1.4, 0, 0))},
	])
	for such in ["block", "cockpit"]:
		var teil: Node3D = null
		for c in bc.design_root.get_children():
			if String(c.get_meta("part_id", "")) == such:
				teil = c
		bc._select_part(teil)
		var n := 0
		for h in bc._handles:
			if String(h.get_meta("kind", "")) == "round":
				n += 1
		print("  %-8s Eckgriffe: %d" % [such, n])
	quit()
	return true
