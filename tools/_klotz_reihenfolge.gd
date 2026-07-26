## Belegt die Reihenfolge-Regel am Klotz:
##   A) erst 3x in die Laenge skalieren, DANN runden -> Kanten in allen Achsen GLEICH gross
##   B) erst runden, DANN 3x skalieren               -> die Rundung wird MITGESTRECKT
extends SceneTree

func _ecke(m: Mesh, halb: Vector3, sc: Vector3) -> Vector3:
	## BREITE DER RUNDUNG je Achse, in Weltmass: auf der Deckflaeche (y = Maximum) reicht
	## der ebene Teil bis b-r; die Differenz zur Aussenkante IST die Rundungsbreite.
	var vs: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var y_max := -9.9
	for v in vs:
		y_max = maxf(y_max, v.y)
	var flach_x := 0.0
	var flach_z := 0.0
	for v in vs:
		if absf(v.y - y_max) < 0.0005:                  # liegt in der Deckebene
			flach_x = maxf(flach_x, absf(v.x))
			flach_z = maxf(flach_z, absf(v.z))
	# Rundungshoehe: wie tief liegt die Deckebene unter der scharfen Oberkante
	return Vector3((halb.x - flach_x) * sc.x, (halb.y - y_max) * sc.y,
		(halb.z - flach_z) * sc.z)

func _process(_d: float) -> bool:
	var p := PartCatalog.get_part("block")
	var basis: Vector3 = p.get("size", Vector3.ONE)
	var pscale := Vector3(1.0, 1.0, 3.0)
	var rund := PartCatalog.block_radien_neu()
	for i in 8:
		rund[i] = 0.6
	print("Grundgroesse %s, Skalierung %s, Rundung 0.6" % [str(basis), str(pscale)])
	# A) erst skalieren, dann runden -> bake = pscale
	var groesse_a := Vector3(basis.x * pscale.x, basis.y * pscale.y, basis.z * pscale.z)
	var ma := PartCatalog._block_mesh(groesse_a, rund)
	var rest_a := PartCatalog.block_rest_scale(pscale, pscale)
	print("A erst skalieren, dann runden: Netz %s  Restskalierung %s"
		% [str(groesse_a), str(rest_a)])
	print("   Kantenmass je Achse: %s" % str(_ecke(ma, groesse_a * 0.5, rest_a)))
	# B) erst runden, dann skalieren -> bake = 1
	var mb := PartCatalog._block_mesh(basis, rund)
	var rest_b := PartCatalog.block_rest_scale(pscale, Vector3.ONE)
	print("B erst runden, dann skalieren: Netz %s  Restskalierung %s"
		% [str(basis), str(rest_b)])
	print("   Kantenmass je Achse: %s" % str(_ecke(mb, basis * 0.5, rest_b)))
	quit()
	return true
