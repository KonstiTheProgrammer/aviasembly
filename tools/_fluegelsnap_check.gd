## PRUEFT die Fluegel-Anhaftung gegen die Erwartung eines Spielers und faellt ein Urteil.
##
## Tragflaechen:  Spannweite zeigt auf die geklickte SEITE, Sehne nach HINTEN,
##                Auftrieb nach OBEN, und die PFEILUNG zeigt auf beiden Seiten
##                nach hinten (links darf keine 180-Grad-Drehung sein, sondern
##                muss die Spiegelung sein -> Determinante < 0).
## Seitenflossen: stehen SENKRECHT (unter dem Rumpf getroffen: nach unten),
##                Sehne nach HINTEN.
extends SceneTree
var f := 0

# [Name, Trefferpunkt, Normale, erwartete Seite (+1 rechts / -1 links / 0 egal)]
const STELLEN: Array = [
	["links mittig",      Vector3(-1.10, 0.00, 2.40),  Vector3(-1, 0, 0),        -1.0],
	["rechts mittig",     Vector3(1.10, 0.00, 2.40),   Vector3(1, 0, 0),          1.0],
	["links leicht hoch", Vector3(-1.00, 0.55, 2.40),  Vector3(-0.75, 0.66, 0),  -1.0],
	["links weit hoch",   Vector3(-0.55, 0.86, 2.40),  Vector3(-0.35, 0.94, 0),  -1.0],
	["rechts weit unten", Vector3(0.55, -0.86, 2.40),  Vector3(0.35, -0.94, 0),   1.0],
	["oben LINKS aussen", Vector3(-0.45, 0.90, 2.40),  Vector3(0, 1, 0),         -1.0],
	["oben RECHTS aussen", Vector3(0.45, 0.90, 2.40),  Vector3(0, 1, 0),          1.0],
	["unten LINKS aussen", Vector3(-0.45, -0.90, 2.40), Vector3(0, -1, 0),       -1.0],
	["oben genau mittig", Vector3(0.00, 0.93, 2.40),   Vector3(0, 1, 0),          0.0],
]


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var bc := BuildController.new()
	root.add_child(bc)
	bc.load_design([
		{"id": "cockpit", "xform": Transform3D(), "root": true},
		{"id": "fuselage", "xform": Transform3D(Basis(), Vector3(0, 0, 2.4))},
	])
	var rumpf: Node3D = null
	for c in bc.design_root.get_children():
		if String(c.get_meta("part_id", "")) == "fuselage":
			rumpf = c
	var koerper: Node3D = null
	for c in rumpf.get_children():
		if c is StaticBody3D:
			koerper = c

	var ids: Array = []
	for id in PartCatalog.all().keys():
		if bool((PartCatalog.all()[id] as Dictionary).get("is_wing", false)):
			ids.append(id)
	ids.sort()

	var fehler: Array = []
	for id in ids:
		var p: Dictionary = PartCatalog.all()[id]
		var yaw: bool = String(p.get("control", "")) == "yaw"
		var sa: int = bc._fluegel_spannachse(p)
		var cs: Vector3 = PartCatalog.col_size(p)
		var co: Vector3 = PartCatalog.col_offset(p)
		print("")
		print("### %-16s %-30s %s" % [id, String(p.get("name", "")),
			"SEITENFLOSSE" if yaw else ("Spannachse " + ("Y" if sa == 1 else "X"))])
		for st in STELLEN:
			var hit := {"position": st[1], "normal": (st[2] as Vector3).normalized(),
				"collider": koerper}
			var r: Dictionary = bc._compute_snap_for(id, hit)
			if not bool(r.get("valid", false)):
				fehler.append("%s / %s: ungueltig" % [id, st[0]])
				continue
			var b: Basis = (r["xform"] as Transform3D).basis
			# echte Spannrichtung des Teils (nicht stumpf basis.x)
			var spann: Vector3 = (b * (Vector3.UP if sa == 1 else Vector3.RIGHT)).normalized()
			var sehne: Vector3 = (b * Vector3.BACK).normalized()
			var auftrieb: Vector3 = (b * Vector3.UP).normalized()
			var pfeil: float = (b * Vector3(0, 0, co.z)).z         # Pfeilung in Weltkoordinaten
			var erw: float = st[3]

			var meldung: Array = []
			if yaw:
				# senkrecht: Spannrichtung muss (fast) die Welt-Hochachse sein
				var vertikal: float = absf(spann.dot(Vector3.UP))
				if vertikal < 0.95:
					meldung.append("nicht senkrecht (%.2f)" % vertikal)
				if String(st[0]).begins_with("unten") and spann.y > 0.0:
					meldung.append("unter dem Rumpf, zeigt aber nach oben")
			else:
				if erw != 0.0 and signf(spann.x) != erw:
					meldung.append("falsche Seite (%.2f statt %+d)" % [spann.x, int(erw)])
				if absf(spann.y) > 0.05:
					meldung.append("nicht waagerecht")
				if auftrieb.dot(Vector3.UP) < 0.95:
					meldung.append("Auftrieb nicht nach oben")
				if absf(co.z) > 0.05 and pfeil < 0.0:
					meldung.append("PFEILUNG nach vorne (%.2f)" % pfeil)
			if sehne.dot(Vector3.BACK) < 0.95:
				meldung.append("Sehne nicht nach hinten")

			var det: float = b.determinant()
			print("   %-19s Spann=(%+.2f %+.2f %+.2f) Sehne=(%+.2f %+.2f %+.2f) det=%+.2f %s"
				% [st[0], spann.x, spann.y, spann.z, sehne.x, sehne.y, sehne.z, det,
				   "" if meldung.is_empty() else ("<-- " + ", ".join(meldung))])
			for m in meldung:
				fehler.append("%s / %s: %s" % [id, st[0], m])

	print("")
	print("=".repeat(70))
	if fehler.is_empty():
		print("URTEIL: OK — alle %d Fluegel haften auf allen %d Stellen richtig an"
			% [ids.size(), STELLEN.size()])
	else:
		print("URTEIL: %d FEHLER" % fehler.size())
		for m in fehler:
			print("   ", m)
	quit()
	return true
