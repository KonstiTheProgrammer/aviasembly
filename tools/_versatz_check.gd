## Prueft das Versetzen der Rumpfenden: Mitte des vorderen/hinteren Rings im Visual,
## dazu die Griffe und die Uebertragung auf den Spiegel (X gespiegelt).
extends SceneTree
var f := 0

func _ringmitte(vis: Node3D, hinten: bool) -> Vector3:
	## Mittelpunkt aller Vertices an der jeweiligen Stirnflaeche (lokales z = +-halbe Laenge)
	var mi := vis.find_children("*", "MeshInstance3D", true, false)
	if mi.is_empty():
		return Vector3.ZERO
	var m: Mesh = (mi[0] as MeshInstance3D).mesh
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
	var p := PartCatalog.get_part("fuselage")
	print("Rumpfsegment size=%s" % str(p.get("size")))
	for fall in [[Vector2.ZERO, Vector2.ZERO], [Vector2(0.0, 0.4), Vector2.ZERO],
			[Vector2(-0.3, 0.0), Vector2(0.25, -0.2)]]:
		var vis := PartCatalog.build_visual(p, Color(0, 0, 0, 0), 1.0, 1.0, -1.0, -1.0,
			fall[0], fall[1])
		get_root().add_child(vis)
		var vorn := _ringmitte(vis, false)
		var hint := _ringmitte(vis, true)
		print("  Versatz vorn %s hinten %s -> Ringmitte vorn (%+.3f %+.3f) hinten (%+.3f %+.3f)"
			% [str(fall[0]), str(fall[1]), vorn.x, vorn.y, hint.x, hint.y])
		vis.queue_free()
	# Griffe + Spiegel
	var bc := BuildController.new()
	root.add_child(bc)
	bc.symmetry = true
	bc.load_design([
		{"id": "cockpit", "xform": Transform3D()},
		{"id": "fuselage", "xform": Transform3D(Basis(), Vector3(1.6, 0, 0))},
	])
	var teil: Node3D = null
	for c in bc.design_root.get_children():
		if String(c.get_meta("part_id", "")) == "fuselage":
			teil = c
	bc._select_part(teil)
	for modus in [3, 4]:
		bc.set_gizmo_mode(modus)
		var arten: Dictionary = {}
		for h in bc._handles:
			var k := String(h.get_meta("kind", "?"))
			arten[k] = int(arten.get(k, 0)) + 1
		print("  Modus %d (%s): %s" % [modus, "Enden" if modus == 3 else "Versetzen",
			str(arten)])
		# kleinster Abstand zwischen zwei Griffen — muss groesser als die Klickbox sein
		var min_d := 99.0
		for a in bc._handles:
			for b in bc._handles:
				if a != b:
					min_d = minf(min_d, (a.position - b.position).length())
		print("      kleinster Griff-Abstand: %.2f (Klickbox 0.5)" % min_d)
	bc.set_gizmo_mode(4)
	for h in bc._handles:
		if String(h.get_meta("kind", "")) == "shift":
			print("    Versatz-Griff: Ende %+.0f  Achse %d (%s)  Position %s"
				% [h.get_meta("sign"), h.get_meta("axis"),
				   "links/rechts" if int(h.get_meta("axis")) == 0 else "hoch/runter",
				   str(h.position.round())])
	var sc: Vector3 = teil.get_meta("pscale", Vector3.ONE)
	bc._sync_mirror(teil, sc)        # Spiegel erst erzeugen
	teil.set_meta("shift_front", Vector2(0.3, 0.2))
	bc._sync_mirror_shift(teil, sc)
	var sp = teil.get_meta("mirror") if teil.has_meta("mirror") else null
	if sp != null and is_instance_valid(sp):
		print("  Spiegel-Versatz vorn: ", str(sp.get_meta("shift_front", Vector2.ZERO)),
			"  (erwartet (-0.3, 0.2))")
	quit()
	return true
