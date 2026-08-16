## ECHTER QUERSCHNITT EINES RUMPFTEILS — als Zahlen, nicht als Bild.
##
## WOFUER: wer ein neues Rumpfmodul baut, das buendig anstossen soll, braucht die
## Randkurve der Stirnflaeche des Nachbarteils. Das Katalog-Feld `size` gibt nur die
## Huellbox her und verleitet zu der Annahme, der Querschnitt sei ein RECHTECK. Ist er
## nicht — und ein Modul mit scharfen Ecken stoesst dann nicht buendig an, sondern
## steht an vier Stellen ueber.
##
## Godot --path . --script res://tools/_querschnitt.gd -- <teil-id> [<teil-id> ...]
extends SceneTree
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var ids := OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = ["fuselage"]
	for id in ids:
		var n := PartCatalog.build_visual(PartCatalog.get_part(id))
		get_root().add_child(n)
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
		var zmin := 1e9
		var zmax := -1e9
		for p in pts:
			zmin = minf(zmin, p.z)
			zmax = maxf(zmax, p.z)
		print("\n=== %s ===  %d Eckpunkte, z von %.3f bis %.3f" % [id, pts.size(), zmin, zmax])
		# Randkurve an der VORDEREN Stirnflaeche (kleinstes z) einsammeln.
		var ring: Array[Vector2] = []
		for p in pts:
			if absf(p.z - zmin) < 0.02:
				ring.append(Vector2(p.x, p.y))
		ring.sort_custom(func(a, b): return a.angle() < b.angle())
		print("  Stirnflaeche bei z=%.3f: %d Punkte" % [zmin, ring.size()])
		var s := ""
		for p in ring:
			s += "(%.3f,%.3f) " % [p.x, p.y]
		print("  " + s)
		n.queue_free()
	quit()
	return true
