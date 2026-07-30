## Misst die vier C-130-glbs IN GODOT nach: laden sie, wie gross sind sie, sitzt der
## drehende "Prop"-Knoten auf der Achse, und welche Materialien sind lackierbar?
extends SceneTree

## Die beiden RUMPFRINGE stehen hier bewusst NICHT: sie sind prozedural (Shape
## "c130_tube" aus C130_PROFILE). Als glb waeren die Enden-Werkzeuge wirkungslos,
## weil _attach_model vor dem Mesh-Bau aussteigt. Geprueft werden sie in
## tools/_c130_enden_check.gd und tools/_versatz_form.gd.
const DATEIEN: Array = ["cockpit_c130", "engine_c130"]


func _aabb(n: Node3D) -> AABB:
	var box := AABB()
	var erst := true
	var stapel: Array = [n]
	while not stapel.is_empty():
		var k: Node = stapel.pop_back()
		for c in k.get_children():
			stapel.append(c)
		if k is MeshInstance3D and (k as MeshInstance3D).mesh != null:
			var mi := k as MeshInstance3D
			var xf: Transform3D = mi.transform
			var p: Node = mi.get_parent()
			while p != null and p != n:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var a: AABB = xf * mi.mesh.get_aabb()
			box = a if erst else box.merge(a)
			erst = false
	return box


func _initialize() -> void:
	var fehler: Array = []
	for id in DATEIEN:
		var pfad := "res://models/%s.glb" % id
		var res = load(pfad)
		print("")
		print("### %s" % id)
		if res == null:
			print("   LAEDT NICHT (fehlt der Import?)")
			fehler.append(id + ": laedt nicht")
			continue
		var wurzel: Node3D = res.instantiate()
		var box := _aabb(wurzel)
		print("   Groesse %.3f x %.3f x %.3f   Mitte %+.3f %+.3f %+.3f"
			% [box.size.x, box.size.y, box.size.z,
			   box.get_center().x, box.get_center().y, box.get_center().z])
		# Knoten + Materialien
		var mats: Array = []
		var stapel: Array = [wurzel]
		var namen: Array = []
		while not stapel.is_empty():
			var k: Node = stapel.pop_back()
			for c in k.get_children():
				stapel.append(c)
			namen.append(k.name)
			if k is MeshInstance3D:
				var m: Mesh = (k as MeshInstance3D).mesh
				if m != null:
					for si in m.get_surface_count():
						var mt: Material = m.surface_get_material(si)
						if mt != null and not mats.has(mt.resource_name):
							mats.append(mt.resource_name)
		print("   Knoten: %s" % str(namen))
		print("   Materialien: %s" % str(mats))

		if id == "engine_c130":
			var prop := wurzel.find_child("Prop", true, false) as Node3D
			if prop == null:
				fehler.append("engine_c130: kein Knoten 'Prop'")
				print("   KEIN 'Prop'-KNOTEN -> Propeller wuerde sich nicht drehen")
			else:
				var pb := _aabb(prop)
				# Der Ursprung MUSS auf der Drehachse liegen (x=0, y=0 lokal), sonst
				# eiert der Propeller beim rotate_z statt zu drehen.
				var achsversatz := Vector2(prop.position.x, prop.position.y).length()
				print("   Prop-Knoten: Position %+.3f %+.3f %+.3f  Achsversatz %.4f"
					% [prop.position.x, prop.position.y, prop.position.z, achsversatz])
				print("   Prop-Scheibe: %.3f x %.3f x %.3f um den eigenen Ursprung %+.3f %+.3f"
					% [pb.size.x, pb.size.y, pb.size.z, pb.get_center().x, pb.get_center().y])
				if achsversatz > 0.01:
					fehler.append("engine_c130: Prop-Ursprung %.3f neben der Achse" % achsversatz)
				var mitte := Vector2(pb.get_center().x, pb.get_center().y).length()
				if mitte > 0.05:
					fehler.append("engine_c130: Prop-Scheibe %.3f aussermittig" % mitte)
				# vorne? Der Propeller gehoert an die Nase (-Z)
				if prop.position.z > 0.0:
					fehler.append("engine_c130: Prop sitzt hinten (z=%+.3f)" % prop.position.z)
		wurzel.free()

	print("")
	print("=".repeat(70))
	if fehler.is_empty():
		print("URTEIL: OK")
	else:
		print("URTEIL: %d FEHLER" % fehler.size())
		for m in fehler:
			print("   ", m)
	quit()
