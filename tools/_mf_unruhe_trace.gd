## Zeitverlauf der RESTUNRUHE im EINGESCHWUNGENEN Zustand — mit dem Flieger aus
## tools/mousefly_test.gd (nicht dem Spieler-Design!), damit sichtbar wird, WORAUS
## dessen horizSD besteht: rechts90 0.00708 rad, hinten180 0.01340 rad.
## Frage: stehender Rest (Bias), langsame Phygoide oder schneller Grenzzyklus?
## Start: godot --headless --path . --script res://tools/_mf_unruhe_trace.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var nxt := 0.0
var case_i := 0

const CASES := [
	{"name": "rechts90", "yaw": PI * 0.5, "pitch": 0.0},
	{"name": "hinten180", "yaw": PI, "pitch": 0.0},
]


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	if frame == 2:
		var bc := BuildController.new()
		root.add_child(bc)
		fc = FlightController.new()
		root.add_child(fc)
		fc.build_from_design(_design(bc))
		fc.set_active(true)
		fc.mouse_fly = true
		_start()
		return false
	var ac := fc.aircraft
	fc.throttle = 1.0
	t += delta
	if t >= nxt:
		nxt += 0.2
		var b := ac.global_transform.basis
		var e: Vector3 = b.transposed() * fc._aim_dir()
		var horiz := atan2(e.x, -e.z)
		var vert := atan2(e.y, sqrt(e.x * e.x + e.z * e.z))
		var wb: Vector3 = b.transposed() * ac.angular_velocity
		print("%-9s t=%5.2f h=%8.4f° v=%8.4f° bank=%7.1f° wz=%6.3f wx=%6.3f roll=%6.3f pitch=%6.3f v=%5.1f" % [
			CASES[case_i]["name"], t, rad_to_deg(horiz), rad_to_deg(vert),
			rad_to_deg(atan2(b.x.y, b.y.y)), wb.z, wb.x, ac.in_roll, ac.in_pitch, ac.airspeed])
	if t > 16.0:
		case_i += 1
		if case_i >= CASES.size():
			quit()
			return true
		_start()
	return false


func _start() -> void:
	var c: Dictionary = CASES[case_i]
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 300, 0))
	ac.linear_velocity = Vector3(0, 0, -70.0)
	ac.angular_velocity = Vector3.ZERO
	fc.look_yaw = float(c["yaw"])
	fc.look_pitch = float(c["pitch"])
	fc._aim_cmd = -ac.global_transform.basis.z
	t = 0.0
	nxt = 0.0


func _design(bc: BuildController) -> Array:
	bc.clear_design()
	var d: Array = []
	d.append({"id": "cockpit", "xform": Transform3D(Basis(), Vector3.ZERO)})
	d.append({"id": "nose", "xform": Transform3D(Basis(), Vector3(0, 0, -2.0))})
	d.append({"id": "fuselage", "xform": Transform3D(Basis(), Vector3(0, 0, 1.9))})
	d.append({"id": "tailcone", "xform": Transform3D(Basis(), Vector3(0, 0, 3.6))})
	d.append({"id": "jet_engine", "xform": Transform3D(Basis(), Vector3(0, 0, 1.0))})
	var nx := Basis(Vector3(1, 0, 0), 0.0)
	d.append({"id": "wing_swept", "xform": Transform3D(nx, Vector3(0.6, 0, 0.6))})
	d.append({"id": "wing_swept", "xform": Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(-0.6, 0, 0.6))})
	d.append({"id": "h_stab", "xform": Transform3D(Basis(), Vector3(0.5, 0.1, 3.6))})
	d.append({"id": "h_stab", "xform": Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(-0.5, 0.1, 3.6))})
	d.append({"id": "v_stab", "xform": Transform3D(Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)), Vector3(0, 0.5, 3.6))})
	return d
