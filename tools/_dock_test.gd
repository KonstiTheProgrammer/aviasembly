## Fährt den ECHTEN BuildController: Motor setzen -> Rumpf andocken (über _compute_snap_for,
## also exakt den Editor-Pfad) -> schaltet der Motor auf die offene Variante um?
extends SceneTree

var bc: BuildController
var frame := 0


func _shown(part: Node3D, n: String) -> bool:
	var vis := part.get_node_or_null("Visual")
	if vis == null:
		return false
	var c := vis.find_child(n, true, false)
	return c != null and (c as Node3D).visible


func _pickbox(part: Node3D) -> String:
	var cs := part.get_node_or_null("Pick/CollisionShape3D") as CollisionShape3D
	if cs == null:
		var b := part.get_node_or_null("Pick")
		if b:
			cs = b.get_child(0) as CollisionShape3D
	if cs == null or not (cs.shape is BoxShape3D):
		return "<keine Box>"
	var s: Vector3 = (cs.shape as BoxShape3D).size
	return "size=%v  offset=%v  -> lokal z %.3f .. %.3f" % [s, cs.transform.origin,
		cs.transform.origin.z - s.z * 0.5, cs.transform.origin.z + s.z * 0.5]


func _hit_on(part: Node3D, local_pos: Vector3, local_n: Vector3) -> Dictionary:
	var body := part.get_node_or_null("Pick")
	return {"position": part.global_transform * local_pos,
		"normal": (part.global_transform.basis * local_n).normalized(),
		"collider": body}


func _try(label: String, eng: Node3D, local_pos: Vector3, local_n: Vector3) -> void:
	var hit := _hit_on(eng, local_pos, local_n)
	var found := bc._part_from_hit(hit)
	var snap := bc._compute_snap_for("fuselage", hit)
	print("  %-26s Treffer-Teil=%s" % [label, "engine" if found == eng else str(found)])
	if not snap.get("valid", false):
		print("      -> KEIN Snap")
		return
	var xf: Transform3D = snap["xform"]
	print("      -> id=%s  origin=%v  scale=%v"
		% [snap.get("id", "fuselage"), xf.origin, snap.get("scale", Vector3.ONE)])


func _process(_d: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	bc = BuildController.new()
	root.add_child(bc)
	bc.clear_design()
	# Motor weit weg vom Wurzel-Cockpit, damit nichts dazwischenfunkt
	var eng := bc._place_id("engine_radial", Transform3D(Basis(), Vector3(6, 0, 0)))
	bc._notify_changed()

	print("=== 1) Motor allein ===")
	print("  Full=%s  Half=%s  (erwartet Full)" % [_shown(eng, "Full"), _shown(eng, "Half")])
	print("  Pick-Box : %s" % _pickbox(eng))
	print("  Visual   : Full reicht bis lokal z=+1.174, Schnittebene bei z=+0.319")

	print("=== 2) Snap-Versuche (was der Editor beim Ziehen macht) ===")
	_try("Heck der HALF-Box", eng, Vector3(0, 0, 0.32), Vector3(0, 0, 1))
	_try("Heck des SICHTBAREN Konus", eng, Vector3(0, 0, 1.17), Vector3(0, 0, 1))
	_try("Seite der Cowl", eng, Vector3(0.6, 0, 0.0), Vector3(1, 0, 0))
	_try("Seite nahe Heck", eng, Vector3(0.6, 0, 0.25), Vector3(1, 0, 0))

	print("=== 3) Rumpf wirklich andocken (Treffer auf der Cowl-SEITE) ===")
	# Bewusst der Fall, der vorher seitlich andockte -> muss jetzt hinten landen.
	var hit := _hit_on(eng, Vector3(0.6, 0, 0.0), Vector3(1, 0, 0))
	var snap := bc._compute_snap_for("fuselage", hit)
	if snap.get("valid", false):
		var fus := bc._place_id(snap.get("id", "fuselage"), snap["xform"], snap.get("scale", Vector3.ONE))
		bc._notify_changed()
		print("  Rumpf-Origin=%v (erwartet ~(6, 0, 1.3194))" % fus.global_position)
		print("  Full=%s  Half=%s  (erwartet Half)" % [_shown(eng, "Full"), _shown(eng, "Half")])
		print("  Pick-Box jetzt: %s  (darf NICHT in den Rumpf ab z=+0.319 reichen)" % _pickbox(eng))
		# Vorderfläche des Rumpfs muss exakt auf der Schnittebene liegen
		var fd := PartCatalog.get_part("fuselage_radial")
		var front: float = fus.global_position.z - PartCatalog.col_size(fd).z * 0.5
		print("  Rumpf-Vorderfläche z=%.4f  vs Schnittebene z=%.4f  -> Spalt %.5f"
			% [front, 0.3194, absf(front - 0.3194)])
		# und wieder abnehmen -> zurück auf die freistehende Gondel
		fus.free()
		bc._notify_changed()
		print("  nach Löschen des Rumpfs: Full=%s  Half=%s  (erwartet Full)"
			% [_shown(eng, "Full"), _shown(eng, "Half")])
		print("  Pick-Box wieder: %s" % _pickbox(eng))
	else:
		print("  KEIN Snap -> nichts platziert")

	print("=== 4) Umgekehrt: Motor auf ein Rumpfteil ziehen ===")
	var fus2 := bc._place_id("fuselage", Transform3D(Basis(), Vector3(-6, 0, 0)))
	bc._notify_changed()
	# Treffer auf der VORDERfläche des Rumpfs (-Z) -> Motor soll davor
	var h2 := _hit_on(fus2, Vector3(0, 0, -1.0), Vector3(0, 0, -1))
	var s2 := bc._compute_snap_for("engine_radial", h2)
	if s2.get("valid", false):
		var e2 := bc._place_id("engine_radial", s2["xform"], s2.get("scale", Vector3.ONE))
		bc._notify_changed()
		var ep := PartCatalog.get_part("engine_radial")
		var eb := e2.global_transform.basis
		var cut_w: Vector3 = e2.global_position + eb * Vector3(0, 0, PartCatalog.engine_cut_z(ep))
		var fd := PartCatalog.get_part("fuselage")
		var fus_front: float = fus2.global_position.z - PartCatalog.col_size(fd).z * 0.5
		print("  Motor-Origin=%v  Nase zeigt nach %v" % [e2.global_position, -eb.z])
		print("  Full=%s  Half=%s  (erwartet Half — der Rumpf führt weiter)"
			% [_shown(e2, "Full"), _shown(e2, "Half")])
		print("  Schnittebene z=%.4f  Rumpf-Vorderfläche z=%.4f  -> Spalt %.5f"
			% [cut_w.z, fus_front, absf(cut_w.z - fus_front)])
		print("  Pick-Box: %s" % _pickbox(e2))
	else:
		print("  KEIN Snap")

	print("=== 5) Rumpf ans Doppeldecker-Cockpit docken (gleiche Profil-Familie) ===")
	var cp := bc._place_id("cockpit_radial", Transform3D(Basis(), Vector3(12, 0, 0)))
	bc._notify_changed()
	var cpd := PartCatalog.get_part("cockpit_radial")
	var h5 := _hit_on(cp, Vector3(0, 0, -PartCatalog.col_size(cpd).z * 0.5), Vector3(0, 0, -1))
	var s5 := bc._compute_snap_for("fuselage", h5)
	if s5.get("valid", false):
		var fd5 := PartCatalog.get_part("fuselage_radial")
		var xf5: Transform3D = s5["xform"]
		var front: float = cp.global_position.z - PartCatalog.col_size(cpd).z * 0.5
		var rear: float = xf5.origin.z + PartCatalog.col_size(fd5).z * 0.5
		print("  id=%s  scale=%v  (erwartet fuselage_radial, (1,1,1))" % [s5.get("id"), s5.get("scale")])
		print("  Rumpf-Hinterkante z=%.4f  Cockpit-Vorderkante z=%.4f  -> Spalt %.5f"
			% [rear, front, absf(rear - front)])
	else:
		print("  KEIN Snap")

	print("=== 6) Cockpit-Anschlussrahmen: pro Seite automatisch ausblenden ===")
	var cp6 := bc._place_id("cockpit_radial", Transform3D(Basis(), Vector3(20, 0, 0)))
	bc._notify_changed()
	print("  allein:       FrameF=%s FrameB=%s  (erwartet true/true)"
		% [_shown(cp6, "FrameF"), _shown(cp6, "FrameB")])
	var cpd6 := PartCatalog.get_part("cockpit_radial")
	var fd6 := PartCatalog.get_part("fuselage_radial")
	# Radial-Rumpf buendig HINTEN (+Z)
	var fus6 := bc._place_id("fuselage_radial", Transform3D(Basis(),
		Vector3(20, 0, PartCatalog.col_size(cpd6).z * 0.5 + PartCatalog.col_size(fd6).z * 0.5)))
	bc._notify_changed()
	print("  Rumpf hinten: FrameF=%s FrameB=%s  (erwartet true/false)"
		% [_shown(cp6, "FrameF"), _shown(cp6, "FrameB")])
	# Sternmotor buendig VORNE (-Z): seine Schnittebene auf der Cockpit-Vorderkante
	var ep6 := PartCatalog.get_part("engine_radial")
	var e6 := bc._place_id("engine_radial", Transform3D(Basis(),
		Vector3(20, 0, -PartCatalog.col_size(cpd6).z * 0.5 - PartCatalog.engine_cut_z(ep6))))
	bc._notify_changed()
	print("  +Motor vorn:  FrameF=%s FrameB=%s  (erwartet false/false)"
		% [_shown(cp6, "FrameF"), _shown(cp6, "FrameB")])
	fus6.free()
	bc._notify_changed()
	print("  Rumpf weg:    FrameF=%s FrameB=%s  (erwartet false/true)"
		% [_shown(cp6, "FrameF"), _shown(cp6, "FrameB")])
	e6.free()
	bc._notify_changed()
	print("  Motor weg:    FrameF=%s FrameB=%s  (erwartet true/true)"
		% [_shown(cp6, "FrameF"), _shown(cp6, "FrameB")])
	quit()
	return true
