## DIAGNOSE (nur lesend): WO entsteht das maxW von mousefly_test?
## mousefly_test misst max|angular_velocity| ERST NACH dem Einschwingen
## (align > 0.995 fuer 60 Frames), Gate < 2.5 rad/s. Dieses Werkzeug faehrt den
## rechts90-Fall mit demselben Aufbau und protokolliert die Drehratenkomponenten,
## Querlage und Fehler ab dem Einschwing-Zeitpunkt.
## Start: godot --headless --path . --script res://tools/_fein_maxw.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var hold := 0
var settled := false
var t_settle := 0.0
var n := 0


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	if frame == 2:
		_setup()
		return false
	if fc == null or not is_instance_valid(fc.aircraft):
		return false
	var ac := fc.aircraft
	fc.throttle = 1.0
	t += delta
	var aim: Vector3 = fc._aim_dir()
	var b: Basis = ac.global_transform.basis
	var nose: Vector3 = -b.z
	var align := nose.dot(aim)
	if not settled:
		hold = hold + 1 if align > 0.995 else 0
		if hold >= 60:
			settled = true
			t_settle = t
			print("--- eingeschwungen bei t=%.2f, Fehler=%.2f Grad, Querlage=%.1f Grad ---" % [
				t, rad_to_deg(acos(clampf(align, -1.0, 1.0))), rad_to_deg(atan2(b.x.y, b.y.y))])
			print("   t   |w|    wx     wy     wz  | bank   err  | inR   inP   inY")
	else:
		n += 1
		if n % 6 == 0:
			var wb: Vector3 = b.transposed() * ac.angular_velocity
			print("%5.2f %5.2f %6.3f %6.3f %6.3f | %6.1f %5.2f | %5.2f %5.2f %5.2f" % [
				t - t_settle, ac.angular_velocity.length(), wb.x, wb.y, wb.z,
				rad_to_deg(atan2(b.x.y, b.y.y)), rad_to_deg(acos(clampf(align, -1.0, 1.0))),
				ac.in_roll, ac.in_pitch, ac.in_yaw])
		if n >= 300:
			quit()
			return true
	if t > 18.0:
		quit()
		return true
	return false


func _setup() -> void:
	var bc := BuildController.new()
	root.add_child(bc)
	fc = FlightController.new()
	root.add_child(fc)
	fc.build_from_design(_design(bc))
	fc.set_active(true)
	fc.mouse_fly = true
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 300, 0))
	ac.linear_velocity = Vector3(0, 0, -70.0)
	ac.angular_velocity = Vector3.ZERO
	ac.gear_down = false
	fc.look_yaw = PI * 0.5
	fc.look_pitch = 0.0
	fc._aim_cmd = -ac.global_transform.basis.z


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
