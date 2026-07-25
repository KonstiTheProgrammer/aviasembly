## Prueft das ausfahrbare Fahrwerksbein: Struktur, Weg des Reifens, unverzerrter Reifen,
## Kollisions-Aufstandspunkt im Flug und die harte Begrenzung der Spanne.
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	for id in ["wheel_jet", "wheel", "wheel_spitfire"]:
		var p := PartCatalog.get_part(id)
		var lang := PartCatalog.gear_leg_len(p)
		print("%-14s Beinlaenge %.3f  Spanne %.1f..%.1f  max. Auszug %.3f m"
			% [id, lang, PartCatalog.GEAR_LEN_MIN, PartCatalog.GEAR_LEN_MAX,
			   PartCatalog.gear_ext(p, PartCatalog.GEAR_LEN_MAX)])
		var root3 := Node3D.new()
		get_root().add_child(root3)
		var vis := PartCatalog.build_visual(p)
		root3.add_child(vis)
		var rad0: Vector3 = (vis.find_child("Wheel", true, false) as Node3D).global_position
		for f2 in [1.0, 1.6, 2.4, 9.0]:
			PartCatalog.set_gear_length(vis, p, f2)
			var bein := vis.find_child("Leg", true, false) as Node3D
			var lm := bein.get_node_or_null("LegMesh") as Node3D
			var rad := vis.find_child("Wheel", true, false) as Node3D
			var soll := PartCatalog.gear_ext(p, f2)
			print("   f=%.1f  Beinnetz-Skalierung y=%.3f  Reifen ab %.4f (soll %.4f)  Reifen-Skalierung %s  Leg=%s"
				% [f2, lm.scale.y, rad0.y - rad.global_position.y, soll,
				   str(rad.scale.round()), bein.get_class()])
		vis.queue_free()
		root3.queue_free()
	# Flug: Aufstandspunkt muss mitwandern
	var fc := FlightController.new()
	root.add_child(fc)
	for glen in [1.0, 2.4]:
		fc.build_from_design([
			{"id": "cockpit", "xform": Transform3D()},
			{"id": "wheel_jet", "xform": Transform3D(Basis(), Vector3(0, -0.6, 0)), "glen": glen},
		])
		var ac = fc.aircraft
		var tiefster := 1e9
		for c in ac.get_children():
			var cs := c as CollisionShape3D
			if cs != null and cs.shape is SphereShape3D:
				tiefster = minf(tiefster, cs.transform.origin.y - (cs.shape as SphereShape3D).radius)
		print("Flug glen=%.1f  Radunterkante lokal y=%+.4f" % [glen, tiefster])
	quit()
	return true
