## Prueft die Naht Glasnase <-> B-29-Rumpfsegment: beide Querschnitte muessen deckungs-
## gleich sein und die Stirnflaechen in derselben Ebene liegen.
extends SceneTree

func _aabb(n: Node3D) -> AABB:
	var ab := AABB()
	var erst := true
	for c in n.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		var w: AABB = vi.global_transform * vi.get_aabb()
		ab = w if erst else ab.merge(w)
		erst = false
	return ab

func _process(_d: float) -> bool:
	var root3 := Node3D.new()
	get_root().add_child(root3)
	for id in ["cockpit_b29", "fuselage_b29"]:
		var p := PartCatalog.get_part(id)
		var vis := PartCatalog.build_visual(p)
		root3.add_child(vis)
		var ab := _aabb(vis)
		var aus_glb: bool = PartCatalog.has_model(id) and not p.get("force_proc", false)
		print("%-13s glb=%s  X %+.3f..%+.3f  Y %+.3f..%+.3f  Z %+.3f..%+.3f"
			% [id, aus_glb, ab.position.x, ab.end.x, ab.position.y, ab.end.y,
			   ab.position.z, ab.end.z])
		print("              Querschnitt %.3f x %.3f  Mitte Y %+.3f  dock_size %s"
			% [ab.size.x, ab.size.y, (ab.position.y + ab.end.y) * 0.5,
			   str(p.get("dock_size", Vector2.ZERO))])
		vis.queue_free()
	print("Palette: cockpit_b29=%s fuselage_b29=%s"
		% [PartCatalog.in_palette("cockpit_b29"), PartCatalog.in_palette("fuselage_b29")])
	quit()
	return true
