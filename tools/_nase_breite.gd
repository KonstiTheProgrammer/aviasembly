## Wie breit und wie hoch ist der Me-262-Rumpf an einer gegebenen z-Stelle?
## Gebraucht, um die vier MK 108 so zu setzen, dass sie IM Rumpf sitzen: die Nase ist
## ein Kegel, die Haut liegt also je nach z ganz woanders. Geschaetzt hatte ich falsch.
extends SceneTree
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var n := PartCatalog.build_visual(PartCatalog.get_part("me262_body"))
	get_root().add_child(n)
	# Alle Eckpunkte einsammeln und nach z-Scheiben sortieren.
	var pts: Array[Vector3] = []
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			for v: Vector3 in (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				pts.append(mi.global_transform * v)
	print("Rumpfquerschnitt (%d Eckpunkte):" % pts.size())
	for zs in [-2.4, -2.0, -1.8, -1.6, -1.4, -1.2, -1.0, -0.5, 0.0]:
		var bx := 0.0
		var ymin := 9.9
		var ymax := -9.9
		for p in pts:
			if absf(p.z - zs) < 0.12:
				bx = maxf(bx, absf(p.x))
				ymin = minf(ymin, p.y)
				ymax = maxf(ymax, p.y)
		if bx > 0.0:
			print("  z=%5.2f   halbe Breite %.3f   y von %.2f bis %.2f" % [zs, bx, ymin, ymax])
	quit()
	return true
