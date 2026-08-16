## RATENTREUE IM DAUERZUG: liefert die innere Nickschleife die Rate, die sie kommandiert?
## Marker wandert mit 130 % der Zellenrate (Saettigung), Nickkanal klebt am Cap.
## Verglichen wird die KOMMANDIERTE Nickrate (= pitch_max, weil in diesem Fall weder
## AoA- noch G-Limiter binden — beide werden mitgeloggt) gegen die GEFLOGENE wb.x.
## Start: godot --headless --path . --script res://tools/_fein_treue.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
const T_PRE := 3.0        # geradeaus einschwingen (Trimm laedt)
const T_RUN := 9.0
var rate := 0.0
var yaw0 := 0.0
var acc_cmd := 0.0
var acc_ist := 0.0
var acc_n := 0
var trim_sum := 0.0


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	if frame == 2:
		_setup()
		return false
	var ac := fc.aircraft
	if ac == null:
		return false
	fc.throttle = 1.0
	t += delta
	if t < T_PRE:
		return false
	if rate <= 0.0:
		rate = 1.30 * fc._auth_rates().x
		yaw0 = fc.look_yaw
		print("Markerrate = %.4f rad/s (130 %% von auth.x = %.4f)" % [rate, fc._auth_rates().x])
	# Marker WAAGERECHT wandern lassen (Dauerkurve, wie mf_schlepp) — der Nickkanal
	# zieht die Kurve, laeuft also am Cap, und die Pitch-Klemme kann nicht zuschlagen.
	fc.look_yaw += rate * delta
	var b: Basis = ac.global_transform.basis
	var wb: Vector3 = b.transposed() * ac.angular_velocity
	var auth: Vector3 = fc._auth_rates()
	var v: float = maxf(ac.airspeed, 12.0)
	var pitch_max: float = minf(fc._tab(v, FlightController.PITCH_RATE_TAB), auth.x * FlightController.AUTH_HEADROOM)
	# letzte 4 s = eingeschwungen
	if t > T_PRE + T_RUN - 4.0:
		acc_cmd += pitch_max
		acc_ist += wb.x
		trim_sum += fc._trim_pitch
		acc_n += 1
	if t > T_PRE + T_RUN:
		var c: float = acc_cmd / maxf(acc_n, 1)
		var i: float = acc_ist / maxf(acc_n, 1)
		print("kommandiert %.4f rad/s | geflogen %.4f rad/s | RATENTREUE %.2f" % [c, i, i / maxf(c, 1e-6)])
		print("Trimm %.4f | Ruder %.3f | aoa %.4f (Limit %.4f) | g %.2f (weich ab %.2f) | v %.0f" % [
			trim_sum / maxf(acc_n, 1), ac.in_pitch, ac.aoa_signed, FlightController.AOA_MAX,
			ac.load_factor, FlightController.G_SOFT * clampf(ac.wing_capacity / maxf(ac.mass * 9.81, 1.0), 3.0, 14.0), v])
		quit()
		return true
	return false


func _setup() -> void:
	var bc := BuildController.new()
	root.add_child(bc)
	fc = FlightController.new()
	root.add_child(fc)
	fc.build_from_design(_load_design())
	fc.set_active(true)
	fc.mouse_fly = true
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
	ac.linear_velocity = Vector3(0, 0, -140.0)
	ac.angular_velocity = Vector3.ZERO
	ac.gear_down = false
	fc.look_yaw = 0.0
	fc.look_pitch = 0.0
	fc._reset_mouse_state()
	fc._aim_cmd = -ac.global_transform.basis.z


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
