## STADTSTRASSEN-PRUEFUNG (headless): fuer GROSSSTADT, Landdorf und FREIHAFEN
##   * Netz: Knoten, Kanten, Laenge, Kreuzungen
##   * Bauplan gegen die ECHTEN Netzgrundrisse: kein Haus auf einer Strasse (Fahrbahn und
##     Gehweg), keine zwei Haeuser ineinander — unabhaengig vom Planer nachgerechnet
##   * Strassennetz-Geometrie: an 500 Stichpunkten rund um die Knoten liegt hoechstens EIN
##     Dreieck (keine uebereinanderliegenden Baender = keine Tiefenkaempfe) und im Kern jedes
##     Knotens genau eines (kein Loch in der Kreuzung)
## Urteilszeile "STADTSTRASSEN OK" / "STADTSTRASSEN FEHLER".
##   HOME=<test-home> Godot --headless --path . --script res://tools/_stadtstrassen_check.gd
extends SceneTree
var f := 0
var m: Node
var fehler := 0


func _haeuser(name: String, plan: Array, netz: Dictionary, nur_innen: float) -> void:
	var obbs: Array = []
	var je := {}
	for e in plan:
		je[e["typ"]] = int(je.get(e["typ"], 0)) + 1
		obbs.append(Stadtstrassen.obb(String(e["typ"]), e["pos"], float(e.get("yaw", 0.0)), -0.3))
	var auf := 0
	var ineinander := 0
	var band := Stadtstrassen.baender(netz, 0.0)
	for i in obbs.size():
		for b in band:
			if Stadtstrassen.obb_schnitt(b, obbs[i]):
				auf += 1
				if auf <= 4:
					print("    auf der Strasse: ", plan[i]["typ"], " ", plan[i]["pos"])
				break
		if (plan[i]["pos"] as Vector2).length() > nur_innen:
			continue
		for j in range(i + 1, obbs.size()):
			if Stadtstrassen.obb_schnitt(obbs[i], obbs[j]):
				ineinander += 1
				if ineinander <= 4:
					print("    ineinander: ", plan[i]["typ"], plan[i]["pos"], " / ", plan[j]["typ"], plan[j]["pos"])
	print("  %s: %d Bauten, %d auf einer Strasse, %d ineinander" % [name, plan.size(), auf, ineinander])
	fehler += auf + ineinander


func _geometrie(name: String, knoten: Node, netz: Dictionary, mitte: Vector3) -> void:
	var mi: MeshInstance3D = null
	if knoten != null:
		for c in knoten.find_children("Strassen", "MeshInstance3D", true, false):
			mi = c
	if mi == null and knoten is MeshInstance3D:
		mi = knoten
	if mi == null or mi.mesh == null:
		print("  %s: Strassennetz-Mesh fehlt" % name)
		fehler += 1
		return
	var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var n := vs.size() / 3
	var p: Array = netz["p"]
	var grad: PackedInt32Array = netz["grad"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var doppelt := 0
	var loch := 0
	var proben := 0
	var kreuz: Array = []
	for i in p.size():
		if grad[i] >= 3:
			kreuz.append(i)
	for k in 500:
		var ki: int = kreuz[rng.randi() % kreuz.size()]
		var kern := k % 2 == 0
		var q: Vector2 = (p[ki] as Vector2) + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) \
			* (1.2 if kern else 14.0)
		var w := Vector2(mitte.x + q.x, mitte.z + q.y)
		var treffer := 0
		var beruehrt := 0
		for t in n:
			var a := Vector2(vs[t * 3].x, vs[t * 3].z)
			var b := Vector2(vs[t * 3 + 1].x, vs[t * 3 + 1].z)
			var c := Vector2(vs[t * 3 + 2].x, vs[t * 3 + 2].z)
			if w.x < minf(a.x, minf(b.x, c.x)) or w.x > maxf(a.x, maxf(b.x, c.x)) \
					or w.y < minf(a.y, minf(b.y, c.y)) or w.y > maxf(a.y, maxf(b.y, c.y)):
				continue
			# strikt innen (mit kleinem Rand: Punkte genau auf einer Kante zaehlen nicht)
			var d1 := (b - a).cross(w - a)
			var d2 := (c - b).cross(w - b)
			var d3 := (a - c).cross(w - c)
			var eps := 0.02
			if (d1 > eps and d2 > eps and d3 > eps) or (d1 < -eps and d2 < -eps and d3 < -eps):
				treffer += 1
			# fuer die Lochpruefung zaehlt auch ein Punkt genau auf einer Dreieckskante
			if (d1 >= -eps and d2 >= -eps and d3 >= -eps) or (d1 <= eps and d2 <= eps and d3 <= eps):
				beruehrt += 1
		proben += 1
		if treffer > 1:
			doppelt += 1
			if doppelt <= 3:
				print("    doppelt belegt bei ", q, " (", treffer, " Dreiecke)")
		if kern and beruehrt == 0:
			loch += 1
			if loch <= 3:
				print("    Loch im Knoten bei ", q)
	var z := Stadtstrassen.zahlen(netz)
	print("  %s: %d Knoten, %d Kanten, %.1f km, %d Kreuzungen | %d Dreiecke | %d Proben: %d doppelt, %d Loecher"
		% [name, z["knoten"], z["kanten"], float(z["laenge"]) / 1000.0, z["kreuzungen"], n, proben, doppelt, loch])
	fehler += doppelt + loch


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
	if f == 6:
		var tw: TerrainWorld = m.terrain
		var fw: Node = m.get("fly_world")
		CityBuilder.has_lib()
		# die Netze sind von Main gebaut und liegen im Zwischenspeicher
		var city := Vector3(4300, 0, 2500)
		var dorf := Vector3(-2300, 0, 1900)
		var zu_stadt := CityBuilder.zufahrten(tw, city, 360.0)
		var zu_dorf := CityBuilder.zufahrten(tw, dorf, 180.0)
		print("Zufahrten: Grossstadt %d, Landdorf %d" % [zu_stadt.size(), zu_dorf.size()])
		var n_stadt := CityBuilder.netz_grossstadt(zu_stadt)
		var n_dorf := CityBuilder.netz_dorf(zu_dorf)
		var n_hafen := Hafenstadt.netz()
		print("HAEUSER")
		_haeuser("Grossstadt", CityBuilder.plan_grossstadt(zu_stadt), n_stadt, 320.0)
		_haeuser("Landdorf", CityBuilder.plan_dorf(zu_dorf), n_dorf, 130.0)
		_haeuser("Freihafen", Hafenstadt.plan(), n_hafen, Hafenstadt.R_FLACH)
		print("NETZE")
		# die Strassen-Meshes: Kinder von fly_world mit Namen "Strassen" (Reihenfolge wie in Main)
		var netze: Array = []
		for c in fw.get_children():
			if c is MeshInstance3D and String(c.name).begins_with("Strassen"):
				netze.append(c)
		if netze.size() < 2:
			print("  Strassen-Meshes fehlen (", netze.size(), ")")
			fehler += 1
		else:
			_geometrie("Grossstadt", netze[0], n_stadt, city)
			_geometrie("Landdorf", netze[1], n_dorf, dorf)
		_geometrie("Freihafen", fw.get_node_or_null("Hafenstadt"), n_hafen, Hafenstadt.MITTE)
		print("STADTSTRASSEN OK" if fehler == 0 else "STADTSTRASSEN FEHLER (%d)" % fehler)
		quit()
	return false
