## MESSLATTE-VORARBEIT: Was kann die ZELLE physisch? (kein Regler-Test!)
## Trennt sauber "Flugmechanik" von "Regler": misst je Design und Tempo
##   (a) Dauer-Rollrate bei vollem Querruder  -> Zeit fuer die Querlage vor jedem Flick
##   (b) Dauer-Kurvenrate am AoA-/G-Limit     -> untere Schranke fuer 90-/180-Grad-Zeiten
## Daraus faellt das kinematische Optimum t_opt = t_roll + dPsi/w_max ab; nur der
## Abstand dazu ist dem Regler anzulasten.
## Start: godot --headless --path . --script res://tools/_mf_envelope.gd
extends SceneTree

var fc: FlightController
var frame := 0
var phase := 0
var t := 0.0
var case_i := 0
var roll_peak := 0.0
var turn_peak := 0.0
var turn_sust := 0.0
var g_peak := 0.0
var aoa_peak := 0.0
var v_now := 0.0
var results: Array = []

const SPEEDS := [70.0, 140.0, 200.0]
var design_name := "jet_testdesign"


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
	t += delta
	# Tempo festhalten: wir messen die Zelle, nicht den Beschleunigungsverlauf.
	var sp: float = SPEEDS[case_i % SPEEDS.size()]
	var vd := ac.linear_velocity
	if vd.length() > 1.0:
		ac.linear_velocity = vd.normalized() * sp
	var wb := ac.global_transform.basis.transposed() * ac.angular_velocity
	if phase == 0:
		# --- (a) ROLLRATE: volles Querruder, Regler aus
		fc.mouse_fly = false
		ac.mouse_fly = false
		ac.in_roll = 1.0
		ac.in_pitch = 0.0
		ac.in_yaw = 0.0
		ac.throttle = 1.0
		if t > 1.0:
			roll_peak = maxf(roll_peak, absf(wb.z))
		if t > 3.0:
			phase = 1
			t = 0.0
			# in eine 60-Grad-Querlage bringen und ziehen
			ac.global_transform = Transform3D(Basis(Vector3(0, 0, -1), 1.2), Vector3(0, 3000, 0))
			ac.linear_velocity = -ac.global_transform.basis.z * sp
			ac.angular_velocity = Vector3.ZERO
	elif phase == 1:
		# --- (b) KURVENRATE am Limit: voll ziehen, Querlage halten
		ac.in_pitch = 1.0
		ac.in_roll = 0.0
		ac.in_yaw = 0.0
		ac.throttle = 1.0
		if t > 1.0:
			var w := ac.angular_velocity.length()
			turn_peak = maxf(turn_peak, w)
			turn_sust = w
			g_peak = maxf(g_peak, ac.load_factor)
			aoa_peak = maxf(aoa_peak, absf(ac.aoa_signed))
		if t > 5.0:
			results.append({
				"v": sp, "roll": roll_peak, "wpeak": turn_peak, "wsust": turn_sust,
				"g": g_peak, "aoa": aoa_peak,
			})
			case_i += 1
			if case_i >= SPEEDS.size():
				_report()
				quit()
				return true
			_start()
	return false


func _setup() -> void:
	var bc := BuildController.new()
	root.add_child(bc)
	fc = FlightController.new()
	root.add_child(fc)
	var design := _load_design()
	fc.build_from_design(design)
	fc.set_active(true)
	fc.mouse_fly = false


func _start() -> void:
	var ac := fc.aircraft
	var sp: float = SPEEDS[case_i % SPEEDS.size()]
	ac.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
	ac.linear_velocity = Vector3(0, 0, -sp)
	ac.angular_velocity = Vector3.ZERO
	ac.gear_down = false
	phase = 0
	t = 0.0
	roll_peak = 0.0
	turn_peak = 0.0
	turn_sust = 0.0
	g_peak = 0.0
	aoa_peak = 0.0


func _report() -> void:
	var ac := fc.aircraft
	print("DESIGN=%s  masse=%.0f kg  fluegel=%.1f m2  kapazitaet=%.0f N  (=%.1f g)" % [
		design_name, ac.mass, ac.wing_area, ac.wing_capacity,
		ac.wing_capacity / maxf(ac.mass * 9.81, 1.0)])
	print("%6s %9s %9s %9s %7s %7s | %8s %8s %8s" % [
		"v m/s", "roll r/s", "roll d/s", "wsust r/s", "d/s", "g", "t_roll90", "t90opt", "t180opt"])
	for r in results:
		var rollrate: float = maxf(r["roll"], 1e-3)
		var w: float = maxf(r["wsust"], 1e-3)
		# Zeit, um ~85 Grad Querlage aufzubauen (mit Anlauf/Ausrollen ~ 1.3x ideal)
		var t_roll := 1.3 * 1.48 / rollrate
		print("%6.0f %9.2f %9.0f %9.3f %7.1f %7.1f | %8.2f %8.2f %8.2f" % [
			r["v"], r["roll"], rad_to_deg(r["roll"]), r["wsust"], rad_to_deg(r["wsust"]),
			r["g"], t_roll, t_roll + (PI * 0.5) / w, t_roll + PI / w])
	print("(t90opt/t180opt = kinematisches Optimum: Querlage aufbauen + Grosskreis am Limit)")


func _load_design() -> Array:
	# "-- test" auf der Kommandozeile = das Design aus tools/mousefly_test.gd messen
	if OS.get_cmdline_user_args().has("test"):
		design_name = "jet_testdesign"
		return _fallback_design()
	var f := FileAccess.open("user://aircraft_design.json", FileAccess.READ)
	if f == null:
		design_name = "jet_testdesign"
		return _fallback_design()
	design_name = "user_design"
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


func _fallback_design() -> Array:
	var d: Array = []
	d.append({"id": "cockpit", "xform": Transform3D(Basis(), Vector3.ZERO)})
	d.append({"id": "nose", "xform": Transform3D(Basis(), Vector3(0, 0, -2.0))})
	d.append({"id": "fuselage", "xform": Transform3D(Basis(), Vector3(0, 0, 1.9))})
	d.append({"id": "tailcone", "xform": Transform3D(Basis(), Vector3(0, 0, 3.6))})
	d.append({"id": "jet_engine", "xform": Transform3D(Basis(), Vector3(0, 0, 1.0))})
	d.append({"id": "wing_swept", "xform": Transform3D(Basis(), Vector3(0.6, 0, 0.6))})
	d.append({"id": "wing_swept", "xform": Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(-0.6, 0, 0.6))})
	d.append({"id": "h_stab", "xform": Transform3D(Basis(), Vector3(0.5, 0.1, 3.6))})
	d.append({"id": "h_stab", "xform": Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(-0.5, 0.1, 3.6))})
	d.append({"id": "v_stab", "xform": Transform3D(Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)), Vector3(0, 0.5, 3.6))})
	return d
