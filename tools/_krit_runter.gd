## KRITIKER-TRACE, NUR LESEND: warum ist die Feinkorrektur nach UNTEN so viel
## langsamer als nach oben? Faehrt denselben 10-Grad-Sprung einmal hoch, einmal
## runter und druckt die beobachtbare Kette: Fehler, Hoehenruder, erreichte
## Koerper-Nickrate, Anstellwinkel, Lastvielfaches, Trimm.
## Wenn das Ruder klein bleibt -> das Regelgesetz fordert nichts (Reglerfehler).
## Wenn das Ruder am Anschlag steht -> die Zelle kann nicht mehr (Flugmechanik).
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var case_i := -1
var stepped := false
var step0 := 1.0
var axis_w := Vector3.UP
var next_print := 0.0

const CASES := [
	{"name": "HOCH  +10", "dv": 10.0},
	{"name": "RUNTER-10", "dv": -10.0},
]
const T_PRE := 4.0
const T_RUN := 4.0


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	if frame == 2:
		_setup()
		case_i = 0
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
		return false
	var tt := t - T_PRE
	var b: Basis = ac.global_transform.basis
	var nose: Vector3 = -b.z
	var aimw: Vector3 = fc._aim_dir()
	var ang := acos(clampf(nose.dot(aimw), -1.0, 1.0))
	var cr := nose.cross(aimw)
	var rot: Vector3 = (cr.normalized() * ang) if cr.length() > 1e-9 else Vector3.ZERO
	var wb: Vector3 = b.transposed() * ac.angular_velocity
	var auth: Vector3 = fc._auth_rates()
	if tt >= next_print:
		next_print += 0.15
		print("   t=%5.2f  e_ax=%7.3f°  ruder=%6.3f  wb.x=%7.4f  authx=%.3f  ratenutz=%5.2f  aoa=%6.3f  g=%5.2f  trim=%6.3f  v=%5.1f" % [
			tt, rad_to_deg(rot.dot(axis_w)), ac.in_pitch, wb.x, auth.x,
			wb.x / maxf(auth.x * 0.95, 1e-6), ac.aoa_signed, ac.load_factor, fc._trim_pitch, ac.airspeed])
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
	var c: Dictionary = CASES[case_i]
	print("=== %s ===" % c["name"])
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
	next_print = 0.0


func _do_step() -> void:
	var c: Dictionary = CASES[case_i]
	var ac := fc.aircraft
	var nose: Vector3 = -ac.global_transform.basis.z
	fc.look_yaw = atan2(nose.x, -nose.z)
	fc.look_pitch = clampf(asin(clampf(nose.y, -1.0, 1.0)) + deg_to_rad(float(c["dv"])), -1.5, 1.5)
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
