## DIAGNOSE Grosser Flick (90 / 180 Grad): wo genau geht die Zeit verloren?
## Faehrt denselben Flick auf BEIDEN Zellen (Testflieger aus mousefly_test.gd und
## Spieler-Design) und protokolliert je Frame die vier Groessen, zwischen denen
## der Verlust entsteht:
##   w_cap   = min(pitch_max, w_gcap)       was der Instructor MAXIMAL kommandieren darf
##   w_mag   = min(w_cap, KP*err, sqrt(2a*err))  was er TATSAECHLICH kommandiert (Stopp-Planung!)
##   w_gc    = -d(Grosskreisfehler)/dt      was die Nase WIRKLICH dreht
##   bank    Querlage (Aufbau- und Ausrollphase)
## Damit laesst sich der Verlust aufteilen in: Rollanlauf, Planungsverlust
## (w_mag < w_cap), Ratendroop (w_gc < w_mag) und Limiterverlust (AoA/G).
## Start: godot --headless --path . --script res://tools/_mf_flick.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var case_i := -1
var _prev_e := 0.0
var _first := true
var rows: Array = []

# deg, Zelle ("test" = mousefly_test-Design, "spieler" = user://aircraft_design.json), v
const CASES := [
	{"deg": 90.0, "cell": "test", "v": 70.0},
	{"deg": 180.0, "cell": "test", "v": 70.0},
	{"deg": 90.0, "cell": "spieler", "v": 140.0},
	{"deg": 180.0, "cell": "spieler", "v": 140.0},
]
const T_RUN := 14.0


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
	var b := ac.global_transform.basis
	var nose: Vector3 = -b.z
	var aim: Vector3 = fc._aim_dir()
	var err := acos(clampf(nose.dot(aim), -1.0, 1.0))
	var wb: Vector3 = b.transposed() * ac.angular_velocity
	var v: float = maxf(ac.airspeed, 12.0)
	var auth: Vector3 = fc._auth_rates()
	var pitch_max: float = minf(fc._tab(v, FlightController.PITCH_RATE_TAB), auth.x * FlightController.AUTH_HEADROOM)
	var roll_max: float = minf(fc._tab(v, FlightController.ROLL_RATE_TAB), auth.z * FlightController.AUTH_HEADROOM)
	var g_lim: float = clampf(ac.wing_capacity / maxf(ac.mass * 9.81, 1.0), 3.0, 14.0)
	var n_turn: float = FlightController.G_SOFT * g_lim
	var w_gcap: float = 9.81 * sqrt(maxf(n_turn * n_turn - 1.0, 0.25)) / v
	var w_cap: float = minf(pitch_max, w_gcap)
	var w_mag: float = minf(w_cap, minf(FlightController.INS_KP_V * err, sqrt(2.0 * FlightController.AIM_TURN_ACC * err)))
	var w_gc := 0.0 if _first else (_prev_e - err) / maxf(delta, 1e-5)
	_first = false
	_prev_e = err
	rows.append({
		"t": t, "err": err, "w_gc": w_gc, "w_mag": w_mag, "w_cap": w_cap,
		"pmax": pitch_max, "rmax": roll_max, "wgcap": w_gcap,
		"bank": atan2(b.x.y, b.y.y), "wbx": wb.x, "wbz": wb.z,
		"aoa": ac.aoa_signed, "g": ac.load_factor,
		"ip": ac.in_pitch, "ir": ac.in_roll, "v": ac.airspeed,
	})
	if t > T_RUN:
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
	fc.set_active(true)
	fc.mouse_fly = true


func _start() -> void:
	var c: Dictionary = CASES[case_i]
	var bc: BuildController = root.get_child(0)
	fc.build_from_design(_design(bc) if c["cell"] == "test" else _load_design())
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
	ac.linear_velocity = Vector3(0, 0, -float(c["v"]))
	ac.angular_velocity = Vector3.ZERO
	ac.gear_down = false
	fc._reset_mouse_state()
	fc.look_yaw = deg_to_rad(float(c["deg"]))
	fc.look_pitch = 0.0
	fc._aim_cmd = -ac.global_transform.basis.z
	t = 0.0
	_first = true
	_prev_e = 0.0
	rows = []


func _report() -> void:
	var c: Dictionary = CASES[case_i]
	var step: float = deg_to_rad(float(c["deg"]))
	var t90 := -1.0
	var t99 := -1.0
	var t_roll := -1.0        # wann ist die Querlage zum ersten Mal > 90 % ihres Maximums
	var bank_pk := 0.0
	for r in rows:
		if t90 < 0.0 and r["err"] <= 0.10 * step:
			t90 = r["t"]
		if t99 < 0.0 and r["err"] <= 0.01 * step:
			t99 = r["t"]
		bank_pk = maxf(bank_pk, absf(r["bank"]))
	for r in rows:
		if t_roll < 0.0 and absf(r["bank"]) >= 0.9 * bank_pk:
			t_roll = r["t"]
	# Kennzahlen der PHASE zwischen Rollende und t90 (= der eigentliche Zug)
	var n := 0
	var s_gc := 0.0
	var s_mag := 0.0
	var s_cap := 0.0
	var s_aoa := 0.0
	var s_g := 0.0
	var s_ip := 0.0
	var lo: float = maxf(t_roll, 0.5)
	var hi: float = t90 if t90 > 0.0 else T_RUN
	for r in rows:
		if r["t"] >= lo and r["t"] <= hi:
			n += 1
			s_gc += r["w_gc"]
			s_mag += r["w_mag"]
			s_cap += r["w_cap"]
			s_aoa += r["aoa"]
			s_g += r["g"]
			s_ip += absf(r["ip"])
	var d: float = maxf(n, 1)
	# GRENZWERTTREUE ueber den GANZEN Lauf: ein schnellerer Regler darf nicht ueber
	# AoA-/G-Limit oder Fluegelbruch schnell werden.
	var aoa_pk := 0.0
	var g_pk := 0.0
	for r in rows:
		aoa_pk = maxf(aoa_pk, absf(r["aoa"]))
		g_pk = maxf(g_pk, r["g"])
	# UEBERSCHWINGEN am unsignierten Grosskreisfehler: erst das Minimum suchen,
	# dann den groessten Wiederanstieg DANACH (Vorbeiziehen + Zurueckkorrigieren).
	var i_min := 0
	for i in rows.size():
		if rows[i]["err"] < rows[i_min]["err"]:
			i_min = i
	var over := 0.0
	for i in range(i_min, rows.size()):
		over = maxf(over, rows[i]["err"] - rows[i_min]["err"])
	var last: Dictionary = rows[rows.size() - 1]
	print("\n=== %.0f Grad, Zelle=%s, v=%.0f  (Masse %.0f kg, Fluegel-g %.1f) ===" % [
		float(c["deg"]), c["cell"], float(c["v"]),
		fc.aircraft.mass, fc.aircraft.wing_capacity / maxf(fc.aircraft.mass * 9.81, 1.0)])
	print("  t90=%.2f s  t99=%.2f s  Restfehler nach %.0f s = %.2f Grad" % [t90, t99, T_RUN, rad_to_deg(last["err"])])
	print("  Rollphase: Spitzenbank %.1f Grad, 90%% davon bei t=%.2f s  (rollmax %.2f rad/s)" % [
		rad_to_deg(bank_pk), t_roll, float(rows[10]["rmax"])])
	print("  ZUGPHASE t=%.2f..%.2f s, Mittelwerte:" % [lo, hi])
	print("    w_cap  (darf)      = %.4f rad/s   [pitch_max %.4f | w_gcap %.4f]" % [
		s_cap / d, float(rows[10]["pmax"]), float(rows[10]["wgcap"])])
	print("    w_mag  (kommand.)  = %.4f rad/s   -> Planungsverlust %.1f %%" % [
		s_mag / d, 100.0 * (1.0 - (s_mag / d) / maxf(s_cap / d, 1e-6))])
	print("    w_gc   (geflogen)  = %.4f rad/s   -> Ratendroop     %.1f %%" % [
		s_gc / d, 100.0 * (1.0 - (s_gc / d) / maxf(s_mag / d, 1e-6))])
	print("    AoA %.4f von %.4f | G %.2f von %.2f | |Hoehenruder| %.2f von 1.0" % [
		s_aoa / d, FlightController.AOA_MAX, s_g / d, FlightController.G_HARD * clampf(fc.aircraft.wing_capacity / maxf(fc.aircraft.mass * 9.81, 1.0), 3.0, 14.0), s_ip / d])
	print("  GRENZEN (ganzer Lauf): AoA_max=%.4f / %.4f  G_max=%.2f / %.2f  Fluegel=%s | Ueberschwingen=%.2f Grad (%.1f %%)" % [
		aoa_pk, FlightController.AOA_MAX, g_pk,
		FlightController.G_HARD * clampf(fc.aircraft.wing_capacity / maxf(fc.aircraft.mass * 9.81, 1.0), 3.0, 14.0),
		"GEBROCHEN" if fc.aircraft.wings_broken else "ok", rad_to_deg(over), 100.0 * over / step])
	# Zeitreihe grob
	var line := "  Verlauf t/err/bank/w_mag/w_gc/aoa/g/ip:"
	print(line)
	var k := 0
	for r in rows:
		if k % 30 == 0 and r["t"] <= minf(hi + 2.0, T_RUN):
			print("    %5.2f s  err=%6.1f  bank=%6.1f  w_mag=%.3f  w_gc=%6.3f  aoa=%.3f  g=%5.2f  ip=%5.2f" % [
				r["t"], rad_to_deg(r["err"]), rad_to_deg(r["bank"]), r["w_mag"], r["w_gc"], r["aoa"], r["g"], r["ip"]])
		k += 1


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
		var c = it.get("color", [0, 0, 0, 0])
		var sc = it.get("scale", [1, 1, 1])
		design.append({"id": it["id"], "xform": xf, "color": Color(c[0], c[1], c[2], c[3]), "scale": Vector3(sc[0], sc[1], sc[2]), "taper": it.get("taper", -1.0), "taper_front": it.get("taper_front", -1.0)})
	return design
