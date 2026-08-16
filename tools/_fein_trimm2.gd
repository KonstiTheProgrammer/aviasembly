## TRACE: was macht der Halte-Trimm waehrend einer kleinen Nick-Korrektur?
## Liest _trim_pitch, in_pitch, die Koerper-Nickrate und rechnet i_gate nach.
## Start: godot --headless --path . --script res://tools/_fein_trimm2.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var stepped := false
var case_i := 0
const CASES := [2.0, 5.0, 10.0]
const T_PRE := 4.0
const T_RUN := 6.0
var nose0 := Vector3.FORWARD
var axis_w := Vector3.UP
var step0 := 1.0


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	if frame == 2:
		_setup()
		_start()
		return false
	var ac := fc.aircraft
	if ac == null:
		return false
	fc.throttle = 1.0
	t += delta
	if not stepped:
		if t >= T_PRE:
			_do_step()
			print("--- SPRUNG %.0f°  trim beim Sprung = %.4f  ruder = %.4f" % [CASES[case_i], fc._trim_pitch, ac.in_pitch])
		return false
	var b: Basis = ac.global_transform.basis
	var nose: Vector3 = -b.z
	var aimw: Vector3 = fc._aim_dir()
	var ang := acos(clampf(nose.dot(aimw), -1.0, 1.0))
	var cr := nose.cross(aimw)
	var rot: Vector3 = (cr.normalized() * ang) if cr.length() > 1e-9 else Vector3.ZERO
	var e_ax := rot.dot(axis_w)
	# i_gate nachrechnen (dieselben Formeln wie im Regler)
	var auth: Vector3 = fc._auth_rates()
	var v: float = maxf(ac.airspeed, 12.0)
	var pitch_max: float = minf(fc._tab(v, FlightController.PITCH_RATE_TAB), auth.x * FlightController.AUTH_HEADROOM)
	var wb: Vector3 = b.transposed() * ac.angular_velocity
	var tt := t - T_PRE
	# w_mag der Stopp-Planung nachrechnen und dem Vorhalt gegenueberstellen
	var w_gcap: float = 9.81 * sqrt(maxf(pow(FlightController.G_SOFT * clampf(ac.wing_capacity / maxf(ac.mass * 9.81, 1.0), 3.0, 14.0), 2.0) - 1.0, 0.25)) / v
	var w_cap: float = minf(pitch_max, w_gcap)
	var w_mag: float = minf(w_cap, minf(FlightController.INS_KP_V * ang, sqrt(2.0 * FlightController.AIM_TURN_ACC * ang)))
	if tt < 1.2:
		print("  t=%5.2f  e=%6.3f°  wmag=%.4f  ff=%.4f  cap=%.4f  trim=%7.4f  ruder=%7.4f  wb.x=%7.4f" % [
			tt, rad_to_deg(e_ax), w_mag, fc._aim_ff.length(), w_cap, fc._trim_pitch, ac.in_pitch, wb.x])
	if tt > T_RUN:
		case_i += 1
		if case_i >= CASES.size():
			quit()
			return true
		_start()
	return false


func _setup() -> void:
	var bc := BuildController.new()
	root.add_child(bc)
	fc = FlightController.new()
	root.add_child(fc)
	fc.build_from_design(_load_design())
	fc.set_active(true)
	fc.mouse_fly = true


func _start() -> void:
	fc.build_from_design(fc.design)
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
	ac.linear_velocity = Vector3(0, 0, -140.0)
	ac.angular_velocity = Vector3.ZERO
	ac.gear_down = false
	fc.look_yaw = 0.0
	fc.look_pitch = 0.0
	fc._reset_mouse_state()
	fc._aim_cmd = -ac.global_transform.basis.z
	t = 0.0
	stepped = false


func _do_step() -> void:
	var ac := fc.aircraft
	var nose: Vector3 = -ac.global_transform.basis.z
	var yaw := atan2(nose.x, -nose.z)
	var pitch := asin(clampf(nose.y, -1.0, 1.0)) + deg_to_rad(CASES[case_i])
	fc.look_yaw = yaw
	fc.look_pitch = clampf(pitch, -1.5, 1.5)
	var aimw: Vector3 = fc._aim_dir()
	step0 = maxf(acos(clampf(nose.dot(aimw), -1.0, 1.0)), 1e-5)
	var cr := nose.cross(aimw)
	axis_w = cr.normalized() if cr.length() > 1e-6 else Vector3.UP
	stepped = true


func _load_design() -> Array:
	var f := FileAccess.open("user://aircraft_design.json", FileAccess.READ)
	if f == null:
		push_error("kein user://aircraft_design.json")
		return []
	var arr = JSON.parse_string(f.get_as_text())
	f.close()
	var design: Array = []
	for it in arr:
		var a = it["xform"]
		var xf := Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))
		var col = it.get("color", [0, 0, 0, 0])
		var sc = it.get("scale", [1, 1, 1])
		design.append({"id": it["id"], "xform": xf, "color": Color(col[0], col[1], col[2], col[3]), "scale": Vector3(sc[0], sc[1], sc[2]), "taper": it.get("taper", -1.0), "taper_front": it.get("taper_front", -1.0)})
	return design
