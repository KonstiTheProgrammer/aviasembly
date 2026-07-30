## Ein DIREKT links gesetzter Fluegel bekommt jetzt eine gespiegelte Basis (det<0) —
## dieselbe improper Basis, die bisher nur der Symmetrie-Modus erzeugte. Dieser Test
## baut so ein Flugzeug OHNE Symmetrie und fliegt es, um zu belegen, dass Kollision,
## Traegheitstensor und Aero das mitmachen (kein NaN, keine Explosion, Auftrieb da).
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	if _laeuft:
		return _fliegen()
	f += 1
	if f < 2:
		return false
	var bc := BuildController.new()
	root.add_child(bc)
	bc.symmetry = false      # bewusst AUS: beide Fluegel werden einzeln gesetzt
	bc.load_design([
		{"id": "cockpit", "xform": Transform3D(), "root": true},
		{"id": "fuselage", "xform": Transform3D(Basis(), Vector3(0, 0, 2.4))},
		{"id": "tailcone", "xform": Transform3D(Basis(), Vector3(0, 0, 4.3))},
		{"id": "prop_engine", "xform": Transform3D(Basis(), Vector3(0, 0, -1.7))},
	])
	var rumpf: Node3D = null
	for c in bc.design_root.get_children():
		if String(c.get_meta("part_id", "")) == "fuselage":
			rumpf = c
	var koerper: Node3D = null
	for c in rumpf.get_children():
		if c is StaticBody3D:
			koerper = c

	# beide Fluegel ueber den ECHTEN Snap-Pfad setzen, je einmal links und rechts
	var gesetzt: Array = []
	for seite in [[-1.0, "links"], [1.0, "rechts"]]:
		var sx: float = seite[0]
		var hit := {"position": Vector3(sx * 1.10, 0.0, 2.40),
			"normal": Vector3(sx, 0, 0), "collider": koerper}
		var r: Dictionary = bc._compute_snap_for("wing_swept", hit)
		var xf: Transform3D = r["xform"]
		gesetzt.append({"id": "wing_swept", "xform": xf})
		print("  %-7s Basis-Determinante %+.2f  Pfeilung nach %s" % [seite[1],
			xf.basis.determinant(),
			"HINTEN" if (xf.basis * Vector3(0, 0, 0.75)).z > 0.0 else "VORNE"])
	var d: Array = bc.get_design()
	for g in gesetzt:
		d.append(g)
	d.append({"id": "h_stab", "xform": Transform3D(Basis(), Vector3(0.4, 0, 4.6))})
	d.append({"id": "h_stab", "xform": Transform3D(Basis(Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(-0.4, 0, 4.6))})
	d.append({"id": "v_stab", "xform": Transform3D(Basis(Vector3(0, 1, 0),
		Vector3(-1, 0, 0), Vector3(0, 0, 1)), Vector3(0, 0.4, 4.6))})

	# --- fliegen ---------------------------------------------------------------
	var fc := FlightController.new()
	root.add_child(fc)
	fc.build_from_design(d)
	var ac: AircraftBody = fc.aircraft
	if ac == null:
		print("KEIN Flugzeug gebaut")
		quit()
		return true
	print("")
	print("  Masse %.1f kg   Fluegelflaeche %.2f m2   Schub %.0f N"
		% [ac.mass, ac.wing_area, ac.total_thrust])

	ac.freeze = false
	ac.global_position = Vector3(0, 300, 0)
	ac.linear_velocity = Vector3(0, 0, -70)      # 70 m/s nach vorne
	fc.set_active(true)
	fc.throttle = 1.0

	ac.freeze = false
	_ac = ac
	_fc = fc
	_laeuft = true
	return false


var _ac: AircraftBody = null
var _fc: FlightController = null
var _laeuft := false
var _schritt := 0
var _schlecht := 0
var _hoehen: Array = []


# Der Flug laeuft ueber die normalen Frames des SceneTree (kein await in _process).
func _fliegen() -> bool:
	_schritt += 1
	var pos: Vector3 = _ac.global_position
	var vel: Vector3 = _ac.linear_velocity
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z) 			or is_nan(vel.x) or is_nan(vel.y) or is_nan(vel.z) 			or _ac.angular_velocity.length() > 12.0:
		_schlecht += 1
	if _schritt % 60 == 0:
		_hoehen.append("%.0f" % pos.y)
	if _schritt < 240:
		return false
	print("  Hoehe je Sekunde: %s" % str(_hoehen))
	print("  Endgeschwindigkeit %.1f m/s   Drehrate %.2f rad/s"
		% [_ac.linear_velocity.length(), _ac.angular_velocity.length()])
	print("  schlechte Frames (NaN / Ueberdrehen): %d" % _schlecht)
	print("")
	print("URTEIL: ", "OK" if _schlecht == 0 and _ac.linear_velocity.length() > 10.0 else "FEHLER")
	quit()
	return true
