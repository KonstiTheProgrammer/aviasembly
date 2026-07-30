## Prueft, dass beim Verschieben eines Rumpfendes die daran haengenden Teile MITWANDERN
## (und die auf der anderen Seite NICHT). Erfassung wie beim Verschieben: BFS ab Cockpit.
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var bc := BuildController.new()
	root.add_child(bc)
	# Kette: Cockpit - Segment A - Segment B (B haengt HINTEN an A)
	bc.load_design([
		{"id": "cockpit", "xform": Transform3D()},
		{"id": "fuselage", "xform": Transform3D(Basis(), Vector3(0, 0, 1.6))},
		{"id": "fuselage", "xform": Transform3D(Basis(), Vector3(0, 0, 3.6))},
	])
	var teile: Array = []
	for c in bc.design_root.get_children():
		if String(c.get_meta("part_id", "")) == "fuselage":
			teile.append(c)
	teile.sort_custom(func(a, b): return a.position.z < b.position.z)
	var a: Node3D = teile[0]
	var b: Node3D = teile[1]
	bc._select_part(a)
	print("vorher:  A z=%.2f y=%.2f   B z=%.2f y=%.2f"
		% [a.position.z, a.position.y, b.position.z, b.position.y])
	for seite in [1.0, -1.0]:
		bc._capture_end_kids(seite)
		var namen: Array[String] = []
		for k in bc._move_kids:
			namen.append("z=%.1f" % (k["n"] as Node3D).position.z)
		print("  Ende %+.0f (%s): %d Teil(e) haengen dran %s"
			% [seite, "hinten" if seite > 0.0 else "vorne", bc._move_kids.size(),
			   str(namen)])
	# hinteres Ende 0.5 nach oben -> B muss mit
	bc._capture_end_kids(1.0)
	var sc: Vector3 = a.get_meta("pscale", Vector3.ONE)
	var gr: Vector3 = PartCatalog.col_size(PartCatalog.get_part("fuselage"))
	var d := Vector2(0.0, 0.5)
	a.set_meta("shift_back", d)
	bc._rebuild_visual(a)
	var welt: Vector3 = a.transform.basis * Vector3(d.x * gr.x * sc.x, d.y * gr.y * sc.y, 0.0)
	for k in bc._move_kids:
		(k["n"] as Node3D).position = (k["p0"] as Vector3) + welt
	print("nachher: A z=%.2f y=%.2f   B z=%.2f y=%.2f  (B soll um %.2f hoch)"
		% [a.position.z, a.position.y, b.position.z, b.position.y, welt.y])
	quit()
	return true
