## Vergleicht je Teil die SNAP-/KOLLISIONSBOX (col_size + col_offset) mit der ECHTEN
## Geometrie (AABB des Visuals) — genau das, was die Debug-Ansicht cyan/gelb zeichnet.
## Ein Ueberstand der Box heisst: der Snap legt das Nachbarteil an die BOX, nicht an das
## sichtbare Modell -> genau der gemeldete Abstand.
extends SceneTree

func _aabb(n: Node3D) -> AABB:
	var ab := AABB()
	var erst := true
	for c in n.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if not vi.visible:
			continue
		var w: AABB = vi.global_transform * vi.get_aabb()
		ab = w if erst else ab.merge(w)
		erst = false
	return ab

func _process(_d: float) -> bool:
	var root3 := Node3D.new()
	get_root().add_child(root3)
	for id in ["wing_straight", "wing_tapered", "b29_wing", "wheel_jet", "wheel",
			"wheel_retract", "fuselage"]:
		var p := PartCatalog.get_part(id)
		if p.is_empty():
			print(id, ": unbekannt")
			continue
		var vis := PartCatalog.build_visual(p)
		root3.add_child(vis)
		var ab := _aabb(vis)
		var cs: Vector3 = PartCatalog.col_size(p)
		var co: Vector3 = PartCatalog.col_offset(p)
		var blo: Vector3 = co - cs * 0.5
		var bhi: Vector3 = co + cs * 0.5
		print("%-14s Box  %+.3f..%+.3f | %+.3f..%+.3f | %+.3f..%+.3f"
			% [id, blo.x, bhi.x, blo.y, bhi.y, blo.z, bhi.z])
		print("               Geo  %+.3f..%+.3f | %+.3f..%+.3f | %+.3f..%+.3f"
			% [ab.position.x, ab.end.x, ab.position.y, ab.end.y, ab.position.z, ab.end.z])
		# Ueberstand der Box je Seite (positiv = Box ragt ueber das Modell hinaus)
		print("               Ueberstand X %+.3f/%+.3f  Y %+.3f/%+.3f  Z %+.3f/%+.3f"
			% [ab.position.x - blo.x, bhi.x - ab.end.x,
			   ab.position.y - blo.y, bhi.y - ab.end.y,
			   ab.position.z - blo.z, bhi.z - ab.end.z])
		vis.queue_free()
	quit()
	return true
