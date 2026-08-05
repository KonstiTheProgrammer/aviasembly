extends SceneTree
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f < 2: return false
	var p := PartCatalog.get_part("wheel_f22")
	if p.is_empty():
		print("FEHLER: wheel_f22 nicht im Katalog"); quit(); return true
	print("Katalog: ", p.get("name"), " | Traglast=", p.get("gear_capacity"),
		" | retract=", p.get("retract"), " | Masse=", p.get("mass"))
	var vis := PartCatalog.build_visual(p)
	if vis == null:
		print("FEHLER: build_visual lieferte null"); quit(); return true
	get_root().add_child(vis)
	var ap := vis.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("AnimationPlayer: ", ap != null, " | retract: ", ap != null and ap.has_animation("retract"))
	print("Leg: ", vis.find_child("Leg", true, false) != null,
		" | Wheel: ", vis.find_child("Wheel", true, false) != null,
		" | Door: ", vis.find_child("Door", true, false) != null)
	var mats := {}
	var tris := 0
	for n in vis.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null: continue
		tris += mi.mesh.get_faces().size() / 3
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m != null: mats[m.resource_name] = true
	print("Materialien: ", mats.keys())
	print("Dreiecke gesamt: ", tris)
	var lackierbar := []
	for k in mats.keys():
		if PartCatalog.PAINT_MATS.has(k): lackierbar.append(k)
	print("davon lackierbar (PAINT_MATS): ", lackierbar, "  (leer = Fahrwerk behaelt eigene Optik)")
	quit()
	return true
