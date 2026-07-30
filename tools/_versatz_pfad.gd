## Faehrt den ECHTEN Pfad des Ziehens: Meta setzen -> _rebuild_visual -> _apply_part_scale,
## und misst danach die Ringmitten im fertigen Visual. Deckt auf, ob ein Ende haengt.
extends SceneTree
var f := 0

func _ringmitte(teil: Node3D, hinten: bool) -> Vector3:
	var vis := teil.get_node_or_null("Visual") as Node3D
	if vis == null:
		return Vector3.INF
	var mis := vis.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		return Vector3.INF
	var m: Mesh = (mis[0] as MeshInstance3D).mesh
	var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var grenze := -9.9 if hinten else 9.9
	for v in vs:
		grenze = maxf(grenze, v.z) if hinten else minf(grenze, v.z)
	var s := Vector3.ZERO
	var n := 0
	for v in vs:
		if absf(v.z - grenze) < 0.002:
			s += v
			n += 1
	return s / maxf(float(n), 1.0)

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var bc := BuildController.new()
	root.add_child(bc)
	bc.load_design([
		{"id": "cockpit", "xform": Transform3D()},
		{"id": "fuselage", "xform": Transform3D(Basis(), Vector3(0, 0, 1.8))},
	])
	var teil: Node3D = null
	for c in bc.design_root.get_children():
		if String(c.get_meta("part_id", "")) == "fuselage":
			teil = c
	var sc: Vector3 = teil.get_meta("pscale", Vector3.ONE)
	for fall in [["shift_front", Vector2(0.0, 0.5)], ["shift_back", Vector2(0.0, -0.5)],
			["shift_front", Vector2(0.4, 0.5)]]:
		teil.set_meta(fall[0], fall[1])
		bc._rebuild_visual(teil)
		bc._apply_part_scale(teil, sc)
		var v := _ringmitte(teil, false)
		var h := _ringmitte(teil, true)
		print("  %s = %s -> vorn (%+.3f %+.3f)  hinten (%+.3f %+.3f)"
			% [fall[0], str(fall[1]), v.x, v.y, h.x, h.y])
	print("  Metas am Teil: vorn %s hinten %s"
		% [str(teil.get_meta("shift_front", Vector2.ZERO)),
		   str(teil.get_meta("shift_back", Vector2.ZERO))])
	# jetzt der Weg ueber _notify_changed (Auto-Taper laeuft mit)
	bc._notify_changed()
	var v2 := _ringmitte(teil, false)
	var h2 := _ringmitte(teil, true)
	print("  nach _notify_changed: vorn (%+.3f %+.3f)  hinten (%+.3f %+.3f)"
		% [v2.x, v2.y, h2.x, h2.y])
	quit()
	return true
