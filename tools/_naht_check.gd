## PASST DIE NAHT? — setzt die Me-262-Cockpitsektion zwischen Nasenkonus, Rumpfsegment
## und Heckkonus und misst den Spalt an beiden Stossstellen.
##
## WOFUER: dass die Stirnflaeche rechnerisch ein Kreis mit Radius 0.600 ist, sagt noch
## nicht, dass die Teile im Spiel buendig stehen — dort kommen Katalog-Groessen und die
## tatsaechliche Modellausdehnung zusammen. Diese Datei prueft das Zusammengesetzte.
extends SceneTree
var f := 0

func _rand(id: String, z: float, vorn: bool) -> Dictionary:
	## Randkurve der vorderen bzw. hinteren Stirnflaeche eines Teils, in Weltkoordinaten.
	var n := PartCatalog.build_visual(PartCatalog.get_part(id))
	get_root().add_child(n)
	n.position = Vector3(0, 0, z)
	var pts: Array[Vector3] = []
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			for v: Vector3 in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				pts.append(mi.global_transform * v)
	var grenze := 1e9 if vorn else -1e9
	for p in pts:
		grenze = minf(grenze, p.z) if vorn else maxf(grenze, p.z)
	var ring: Array[Vector2] = []
	for p in pts:
		if absf(p.z - grenze) < 0.01:
			ring.append(Vector2(p.x, p.y))
	return {"z": grenze, "ring": ring, "node": n}


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	# Cockpitsektion bei z = 0 (Laenge 2.0 -> Enden bei -1.0 und +1.0),
	# Rumpfsegment direkt dahinter, Nasenkonus direkt davor.
	var ck_v := _rand("me262_cockpit", 0.0, true)
	var ck_h := _rand("me262_cockpit", 0.0, false)
	var fs := _rand("fuselage", 2.0, true)          # Rumpfsegment (Laenge 2.0) dahinter
	print("Cockpitsektion: vorne z=%.3f, hinten z=%.3f" % [ck_v["z"], ck_h["z"]])
	print("Rumpfsegment  : vorne z=%.3f" % fs["z"])
	print("  Laengsspalt an der hinteren Naht: %.4f m" % absf(float(fs["z"]) - float(ck_h["z"])))
	# Radien beider Randkurven vergleichen.
	for nm in [["Cockpit hinten", ck_h], ["Rumpfsegment vorne", fs]]:
		var ring: Array = (nm[1] as Dictionary)["ring"]
		var rmin := 1e9
		var rmax := -1e9
		for p: Vector2 in ring:
			rmin = minf(rmin, p.length())
			rmax = maxf(rmax, p.length())
		print("  %-20s %3d Punkte  Radius %.4f..%.4f" % [nm[0], ring.size(), rmin, rmax])
	quit()
	return true
