## Prueft, WOHIN sich das Rad beim Einklappen bewegt: Pivot muss am Anschluss oben
## liegen, nicht auf der Radnabe. Ausgabe = Weltposition der Radmitte bei fold 0 und 1.
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var root3 := Node3D.new()
	get_root().add_child(root3)
	for id in ["wheel_retract", "wheel_jet", "wheel_spitfire"]:
		var p := PartCatalog.get_part(id)
		var vis := PartCatalog.build_visual(p)
		root3.add_child(vis)
		var leg := vis.find_child("Leg", true, false) as Node3D
		var rad := vis.find_child("Wheel", true, false) as Node3D
		if leg == null or rad == null:
			print(id, ": Leg/Wheel NICHT gefunden")
			continue
		var lr: Transform3D = leg.transform
		var p0: Vector3 = rad.global_transform.origin
		var achse := Vector3.RIGHT
		leg.transform = Transform3D(Basis(achse, deg_to_rad(88.0)) * lr.basis, lr.origin)
		var p1: Vector3 = rad.global_transform.origin
		print("%-16s Pivot=%+.3f | Nabe aus=(%+.2f %+.2f %+.2f) ein=(%+.2f %+.2f %+.2f) Weg=%.3f"
			% [id, lr.origin.y, p0.x, p0.y, p0.z, p1.x, p1.y, p1.z, p0.distance_to(p1)])
		vis.queue_free()
	quit()
	return true
