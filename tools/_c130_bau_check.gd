## Prueft den C-130-Baukasten im echten Editor:
##   1. Rumpfsegmente docken KOAXIAL und STOSSBUENDIG an (kein Spalt, nicht seitlich)
##   2. Die Laengenregel waehlt kurz -> lang, so wie es die Quelldatei vormacht
##   3. Der Propeller des Triebwerks dreht sich im Flug (Knoten "Prop")
extends SceneTree
var f := 0


func _koerper(teil: Node3D) -> StaticBody3D:
	for c in teil.get_children():
		if c is StaticBody3D:
			return c
	return null


# Weltlage der vorderen/hinteren Stirnflaeche eines Teils entlang seiner Z-Achse
func _stirn(teil: Node3D, hinten: bool) -> Vector3:
	var p := PartCatalog.get_part(teil.get_meta("part_id"))
	var b := teil.global_transform.basis.orthonormalized()
	var sc: Vector3 = teil.get_meta("pscale", Vector3.ONE)
	var mitte: Vector3 = teil.global_position + b * (PartCatalog.col_offset(p) * sc)
	var h: float = PartCatalog.col_size(p).z * sc.z * 0.5
	return mitte + b.z * (h if hinten else -h)


func _process(_d: float) -> bool:
	if _laeuft:
		return _weiter()
	f += 1
	if f < 2:
		return false
	var fehler: Array = []
	var bc := BuildController.new()
	root.add_child(bc)
	bc.symmetry = false
	bc.load_design([{"id": "cockpit_c130", "xform": Transform3D(), "root": true}])

	print("=== 1) Rumpfkette bauen (immer hinten andocken) ===")
	var letzte: Node3D = null
	for c in bc.design_root.get_children():
		if c.is_in_group("part") and String(c.get_meta("part_id", "")) == "cockpit_c130":
			letzte = c
	if letzte == null:
		print("  Cockpit nicht gebaut")
		_ende(["cockpit_c130 nicht gebaut"])
		return true
	for i in 5:
		var laenge: float = bc._c130_kette_laenge()
		var erwartet: String = "fuselage_c130_long" if laenge >= bc.C130_LANG_AB \
			else "fuselage_c130_short"
		# Treffer HINTEN auf dem Mantel (nicht auf der Stirnflaeche) — der schwierige Fall
		var hb := _stirn(letzte, true)
		var tb := letzte.global_transform.basis.orthonormalized()
		var hit := {"position": hb - tb.z * 0.25 + tb.x * 1.27,
			"normal": tb.x, "collider": _koerper(letzte)}
		var r: Dictionary = bc._compute_snap_for("fuselage", hit)
		if not bool(r.get("valid", false)):
			fehler.append("Schritt %d: kein gueltiger Snap" % i)
			break
		var gew := String(r.get("id", "fuselage"))
		var vorher := hb
		var neu: Node3D = bc._place_id(gew, r["xform"], r.get("scale", Vector3.ONE))
		bc._notify_changed()
		# Spalt zwischen der Rueckflaeche des letzten und der Vorderflaeche des neuen
		var spalt: float = vorher.distance_to(_stirn(neu, false))
		# koaxial? (Achsen muessen parallel sein)
		var achse: float = absf(tb.z.dot(neu.global_transform.basis.orthonormalized().z))
		print("  Schritt %d: Kette %.3f -> %-24s Spalt %.5f  Achse %.4f"
			% [i, laenge, gew, spalt, achse])
		if gew != erwartet:
			fehler.append("Schritt %d: %s statt %s" % [i, gew, erwartet])
		if spalt > 0.001:
			fehler.append("Schritt %d: Spalt %.4f" % [i, spalt])
		if achse < 0.999:
			fehler.append("Schritt %d: nicht koaxial (%.3f)" % [i, achse])
		letzte = neu
	print("  Gesamtlaenge der Kette: %.3f" % bc._c130_kette_laenge())

	print("")
	print("=== 2) Triebwerk: dreht der Propeller? ===")
	var d: Array = bc.get_design()
	d.append({"id": "engine_c130", "xform": Transform3D(Basis(), Vector3(2.6, 0, 0))})
	var fc := FlightController.new()
	root.add_child(fc)
	fc.build_from_design(d)
	var ac: AircraftBody = fc.aircraft
	if ac == null:
		fehler.append("kein Flugzeug gebaut")
	else:
		var prop: Node3D = null
		var stapel: Array = [ac]
		while not stapel.is_empty():
			var k: Node = stapel.pop_back()
			for c in k.get_children():
				stapel.append(c)
			if k.name == "Prop":
				prop = k as Node3D
		if prop == null:
			fehler.append("Propeller-Knoten im gebauten Flugzeug nicht gefunden")
			print("  KEIN 'Prop'-Knoten")
		else:
			var vorher: float = prop.rotation.z
			_prop = prop
			_ac = ac
			_fc = fc
			_start = vorher
			_laeuft = true
			print("  Prop gefunden, Startwinkel %.4f — drehe 60 Frames" % vorher)
			_fehler = fehler
			return false
	_ende(fehler)
	return true


var _prop: Node3D = null
var _ac: AircraftBody = null
var _fc: FlightController = null
var _start := 0.0
var _laeuft := false
var _schritt := 0
var _fehler: Array = []


func _ende(fehler: Array) -> void:
	print("")
	print("=".repeat(66))
	if fehler.is_empty():
		print("URTEIL: OK")
	else:
		print("URTEIL: %d FEHLER" % fehler.size())
		for m in fehler:
			print("   ", m)
	quit()


func _weiter() -> bool:
	_schritt += 1
	if _schritt == 1:
		_ac.freeze = false
		_fc.set_active(true)
		_fc.throttle = 1.0
	if _schritt < 60:
		return false
	var gedreht: float = absf(wrapf(_prop.rotation.z - _start, -PI, PI))
	print("  nach 60 Frames um %.3f rad gedreht" % gedreht)
	if gedreht < 0.05:
		_fehler.append("Propeller dreht sich nicht (%.4f rad)" % gedreht)
	_ende(_fehler)
	return true
