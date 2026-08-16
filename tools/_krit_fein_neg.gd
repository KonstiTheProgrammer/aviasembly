## KRITIKER-GEGENPROBE zu tools/mf_fein.gd — NUR LESEND, aendert nichts am Regler.
## GRUND: mf_fein prueft ausschliesslich POSITIVE Sprungrichtungen (deg > 0 heisst
## Marker nach OBEN bzw. nach RECHTS) und genau zwei Tempi (143/163 m/s). Der Regler
## ist aber in beiden Achsen unsymmetrisch: der AoA-Limiter klemmt nach unten bei
## AOA_MIN = -0.105 gegen AOA_MAX = +0.211, der G-Limiter nach unten mit G_NEG = 0.45,
## und die Bank-Kaskade ist ueber sin(current_bank) vorzeichenbehaftet. Ein Regler,
## der nur auf die vier gemessenen Faelle getrimmt ist, faellt hier auf.
## Gemessen wird EXAKT wie in mf_fein (gleiche Kennzahlen, gleiches 0.2-Grad-Band),
## damit die Zahlen direkt nebeneinander lesbar sind.
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var case_i := -1
var stepped := false
var step0 := 1.0
var axis_w := Vector3.UP
var samples: PackedFloat64Array = PackedFloat64Array()
var total: PackedFloat64Array = PackedFloat64Array()
var times: PackedFloat64Array = PackedFloat64Array()
var w_ax_max := 0.0
var v_at_step := 0.0

# dh = Sprung in Gier (rad, + = rechts), dv = Sprung in Nick (rad, + = hoch)
const CASES := [
	{"name": "10 runter   ", "dh": 0.0, "dv": -10.0, "v": 140.0},
	{"name": "15 runter   ", "dh": 0.0, "dv": -15.0, "v": 140.0},
	{"name": " 2 runter   ", "dh": 0.0, "dv": -2.0, "v": 140.0},
	{"name": "10 links    ", "dh": -10.0, "dv": 0.0, "v": 140.0},
	{"name": "15 links    ", "dh": -15.0, "dv": 0.0, "v": 140.0},
	{"name": " 2 links    ", "dh": -2.0, "dv": 0.0, "v": 140.0},
	{"name": "10 diag ro  ", "dh": 7.07, "dv": 7.07, "v": 140.0},
	{"name": "10 diag ru  ", "dh": 7.07, "dv": -7.07, "v": 140.0},
	{"name": "10 diag lu  ", "dh": -7.07, "dv": -7.07, "v": 140.0},
	{"name": "10 rechts@110", "dh": 10.0, "dv": 0.0, "v": 110.0},
	{"name": "10 rechts@185", "dh": 10.0, "dv": 0.0, "v": 185.0},
	{"name": "10 links@185", "dh": -10.0, "dv": 0.0, "v": 185.0},
	{"name": "10 rechts@240", "dh": 10.0, "dv": 0.0, "v": 240.0},
]
const T_PRE := 4.0
const T_RUN := 8.0
const BAND := 0.2 * PI / 180.0


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
	var b: Basis = ac.global_transform.basis
	var nose: Vector3 = -b.z
	var aimw: Vector3 = fc._aim_dir()
	var ang := acos(clampf(nose.dot(aimw), -1.0, 1.0))
	var cr := nose.cross(aimw)
	var rot: Vector3 = (cr.normalized() * ang) if cr.length() > 1e-9 else Vector3.ZERO
	samples.push_back(rot.dot(axis_w))
	total.push_back(ang)
	times.push_back(t - T_PRE)
	w_ax_max = maxf(w_ax_max, absf(ac.angular_velocity.dot(axis_w)))
	if t - T_PRE > T_RUN:
		_report()
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
	fc.build_from_design(fc.design)
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
	ac.linear_velocity = Vector3(0, 0, -float(c["v"]))
	ac.angular_velocity = Vector3.ZERO
	ac.gear_down = false
	fc.look_yaw = 0.0
	fc.look_pitch = 0.0
	fc._reset_mouse_state()
	fc._aim_cmd = -ac.global_transform.basis.z
	t = 0.0
	stepped = false
	samples = PackedFloat64Array()
	total = PackedFloat64Array()
	times = PackedFloat64Array()
	w_ax_max = 0.0


func _do_step() -> void:
	var c: Dictionary = CASES[case_i]
	var ac := fc.aircraft
	var nose: Vector3 = -ac.global_transform.basis.z
	var yaw := atan2(nose.x, -nose.z) + deg_to_rad(float(c["dh"]))
	var pitch := asin(clampf(nose.y, -1.0, 1.0)) + deg_to_rad(float(c["dv"]))
	fc.look_yaw = yaw
	fc.look_pitch = clampf(pitch, -1.5, 1.5)
	var aimw: Vector3 = fc._aim_dir()
	step0 = maxf(acos(clampf(nose.dot(aimw), -1.0, 1.0)), 1e-5)
	var cr := nose.cross(aimw)
	axis_w = cr.normalized() if cr.length() > 1e-6 else Vector3.UP
	v_at_step = ac.airspeed
	stepped = true


func _report() -> void:
	var c: Dictionary = CASES[case_i]
	var t90 := -1.0
	var over := 0.0
	var last_out := 0.0
	var tend: float = times[times.size() - 1]
	for i in samples.size():
		var e: float = samples[i]
		if t90 < 0.0 and absf(e) <= 0.10 * step0:
			t90 = times[i]
		if e < 0.0:
			over = maxf(over, -e)
		if total[i] > BAND:
			last_out = times[i]
	var t_band := last_out if last_out < tend - 0.05 else -1.0
	var tg := _tail_stats(total, 2.0)
	# Zielwerte des Aspekts: t90 senkr <= 1.0 s, waagr <= 1.6 s, ueber <= 5 %, Band <= 2.2 s
	var lim_t90: float = 1.0 if absf(float(c["dh"])) < 0.01 else 1.6
	var ok := t90 >= 0.0 and t90 <= lim_t90 and (100.0 * over / step0) <= 5.0 and t_band >= 0.0 and t_band <= 2.2
	print("%-13s v=%3.0f e0=%5.2f° | t90=%6.2f (Ziel %.1f)  ueber=%5.1f%% (%5.3f°)  t0.2ges=%6.2f (Ziel 2.20) | Rest %6.3f° pp=%.3f° | wmax=%.3f  %s" % [
		c["name"], v_at_step, rad_to_deg(step0), t90, lim_t90,
		100.0 * over / step0, rad_to_deg(over), t_band,
		rad_to_deg(tg.z), rad_to_deg(tg.y), w_ax_max, "OK" if ok else "<== VERFEHLT"])


func _tail_stats(arr: PackedFloat64Array, sec: float) -> Vector3:
	if arr.size() < 5:
		return Vector3.ZERO
	var tend: float = times[times.size() - 1]
	var start := 0
	for i in times.size():
		if times[i] > tend - sec:
			start = i
			break
	var n := arr.size() - start
	if n < 5:
		return Vector3.ZERO
	var mean := 0.0
	var lo := 1e9
	var hi := -1e9
	for i in range(start, arr.size()):
		mean += arr[i]
		lo = minf(lo, arr[i])
		hi = maxf(hi, arr[i])
	mean /= n
	var sd := 0.0
	for i in range(start, arr.size()):
		sd += (arr[i] - mean) * (arr[i] - mean)
	return Vector3(sqrt(sd / n), hi - lo, mean)


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
