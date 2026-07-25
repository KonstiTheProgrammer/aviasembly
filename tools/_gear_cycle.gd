## Faehrt den ECHTEN Fahrwerks-Zyklus ab (einfahren -> ausfahren) und protokolliert je
## Schritt Skalierung, Sichtbarkeit und Weltposition der Radnabe. Der bisherige
## _blob_check setzt nur Einzelstellungen und trifft die Rueckwaerts-Sequenz nicht.
extends SceneTree
var f := 0

func _radbasis(ac) -> String:
	## Lokale Skalierung und Determinante des "Wheel"-Knotens. Kollabiert die Basis,
	## verschwindet der Reifen, obwohl visible=true und der Blob wieder 1.0 ist.
	var s := ""
	for w in ac.wheels:
		var wn = w["node"]
		if not is_instance_valid(wn):
			continue
		var b: Basis = wn.transform.basis
		var sc: Vector3 = b.get_scale()
		s += "[s=(%.3f %.3f %.3f) det=%.4f] " % [sc.x, sc.y, sc.z, b.determinant()]
	return s


func _zeile(ac, a: float) -> String:
	var s := "a=%.3f " % a
	for g in ac.gear_items:
		if not g["retract"]:
			continue
		var v = g["vis"]
		if not is_instance_valid(v):
			s += "[weg] "
			continue
		var sc: Vector3 = v.transform.basis.get_scale()
		var rad := v.find_child("Wheel", true, false) as Node3D
		var wy := 0.0
		if rad != null:
			wy = rad.global_transform.origin.y
		s += "[%.2f/%.2f %s y=%+.2f] " % [sc.x, sc.y, "AN" if v.visible else "--", wy]
	return s

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var fc := FlightController.new()
	root.add_child(fc)
	var d: Array = []
	# Wenn der Spieler ein Design gespeichert hat, DAS pruefen — sonst ein Ersatzdesign.
	if FileAccess.file_exists("user://aircraft_design.json"):
		var txt := FileAccess.get_file_as_string("user://aircraft_design.json")
		var j = JSON.parse_string(txt)
		# Der Speicherstand ist eine FLACHE LISTE von Teilen (kein Dict mit "parts") —
		# beim ersten Versuch lief der Test deshalb still auf das Ersatzdesign.
		var liste: Array = []
		if j is Array:
			liste = j
		elif j is Dictionary and j.has("parts"):
			liste = j["parts"]
		for p in liste:
			var e := {"id": p.get("id", "")}
			var x: Array = p.get("xform", [])
			if x.size() >= 12:
				e["xform"] = Transform3D(Basis(Vector3(x[0], x[1], x[2]),
					Vector3(x[3], x[4], x[5]), Vector3(x[6], x[7], x[8])),
					Vector3(x[9], x[10], x[11]))
			else:
				e["xform"] = Transform3D()
			var s: Array = p.get("scale", [])
			if s.size() >= 3:
				e["scale"] = Vector3(s[0], s[1], s[2])
			d.append(e)
		if not d.is_empty():
			print("Design des Spielers: ", d.size(), " Teile")
	if d.is_empty():
		d = [
			{"id": "cockpit", "xform": Transform3D()},
			{"id": "wheel_retract", "xform": Transform3D(Basis(), Vector3(0, -1.1, 0))},
			{"id": "wheel_jet", "xform": Transform3D(Basis(), Vector3(1.2, -1.1, 0.6))},
			{"id": "wheel_spitfire", "xform": Transform3D(Basis(), Vector3(-1.2, -1.1, 0.6))},
		]
		print("Ersatzdesign")
	fc.build_from_design(d)
	var ac = fc.aircraft
	var eingefahren := 0
	for g in ac.gear_items:
		if g["retract"]:
			eingefahren += 1
	print("Fahrwerk: %d Elemente, %d einziehbar, kollabiert=%s"
		% [ac.gear_items.size(), eingefahren, ac._collapsed])
	print("Ruhe:   ", _zeile(ac, ac._gear_anim))

	print("--- EINFAHREN (Raeder laufen dabei nach, wie direkt nach dem Abheben)")
	ac.gear_down = false
	for i in range(70):
		ac._wheel_spin = 25.0        # Rollen erzwingen: genau der reale Fall
		ac._process(1.0 / 60.0)
		if i % 14 == 13:
			print("  ", _zeile(ac, ac._gear_anim))
			print("     Radbasis: ", _radbasis(ac))
	print("--- AUSFAHREN")
	ac.gear_down = true
	for i in range(70):
		ac._process(1.0 / 60.0)
		if i % 7 == 6:
			print("  ", _zeile(ac, ac._gear_anim))
			print("     Radbasis: ", _radbasis(ac))
	quit()
	return true
