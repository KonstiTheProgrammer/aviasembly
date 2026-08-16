## Wegwerf-Trace: WARUM dauert eine kleine WAAGERECHTE Korrektur so lange?
## mf_fein misst fuer 2 Grad seitlich t90 = 3.33 s und Einschwingen 5.31 s, waehrend
## derselbe Sprung senkrecht in 0.36 s steht. Gesucht ist die Stelle, an der der
## waagerechte Pfad die Autoritaet verliert.
## Geloggt wird die ganze Kette: Fehler -> Ratenbedarf -> GATE -> Soll-Bank -> Ist-Bank
## -> tatsaechliche Drehrate. Das Gate ist der Verdaechtige:
##   bank_need = _wh_filt * smoothstep(0.006, 0.018, |_wh_filt|)
## Start: godot --headless --path . --script res://tools/_fein_quer.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var stepped := false
var nxt := 0.0

const DEG := 2.0        # Sprungweite seitlich
const T_PRE := 4.0


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
	if not stepped:
		if t >= T_PRE:
			var nose: Vector3 = -ac.global_transform.basis.z
			fc.look_yaw = atan2(nose.x, -nose.z) + deg_to_rad(DEG)
			fc.look_pitch = asin(clampf(nose.y, -1.0, 1.0))
			stepped = true
			nxt = t
			print("--- Sprung %.1f Grad seitlich, v=%.0f ---" % [DEG, ac.airspeed])
			print(" t    err°  horiz°  vert°  bankIst°  wmag    d_pitch   wb.x   yawSoll   wb.y    wUP    hoehe  hoeh_r  quer  seiten  trim   beta°")
		return false
	if t >= nxt:
		nxt += 0.25
		var b: Basis = ac.global_transform.basis
		var aimw: Vector3 = fc._aim_dir()
		var nose: Vector3 = -b.z
		var err := acos(clampf(nose.dot(aimw), -1.0, 1.0))
		# Kette exakt wie im Regler nachrechnen
		var auth: Vector3 = fc._auth_rates()
		var v: float = maxf(ac.airspeed, 12.0)
		var pitch_max: float = minf(fc._tab(v, FlightController.PITCH_RATE_TAB), auth.x * FlightController.AUTH_HEADROOM)
		var g_lim: float = clampf(ac.wing_capacity / maxf(ac.mass * 9.81, 1.0), 3.0, 14.0)
		var n_turn: float = FlightController.G_SOFT * g_lim
		var w_gcap: float = 9.81 * sqrt(maxf(n_turn * n_turn - 1.0, 0.25)) / v
		var w_cap: float = minf(pitch_max, w_gcap)
		var w_mag: float = minf(w_cap, minf(FlightController.INS_KP_V * err, sqrt(2.0 * FlightController.AIM_TURN_ACC * err)))
		var bank_ist := atan2(b.x.y, b.y.y)
		var wb: Vector3 = b.transposed() * ac.angular_velocity
		var v_b: Vector3 = b.transposed() * ac.linear_velocity
		var beta := atan2(v_b.x, absf(v_b.z) + 0.6)
		# Fehlerzerlegung und Soll-Drehvektor exakt wie der Regler
		var e: Vector3 = b.transposed() * fc._aim_cmd
		var horiz: float = fc._soft_dead(atan2(e.x, -e.z))
		var vert: float = fc._soft_dead(atan2(e.y, sqrt(e.x * e.x + e.z * e.z)))
		var cross_w: Vector3 = (-b.z).cross(fc._aim_cmd)
		var axis_w: Vector3 = cross_w.normalized() if cross_w.length() > 1e-4 else Vector3.ZERO
		var w_des_w: Vector3 = axis_w * w_mag
		var w_b_des: Vector3 = b.transposed() * w_des_w
		var d_pitch: float = clampf(w_b_des.x, -pitch_max, pitch_max)
		var yaw_cap: float = minf(0.3, auth.y * FlightController.AUTH_HEADROOM)
		var yaw_soll: float = clampf(w_b_des.y, -yaw_cap, yaw_cap)
		print("%5.2f %6.3f %6.3f %6.3f %8.2f %7.4f %8.4f %8.4f %8.4f %8.4f %7.4f %7.1f %6.2f %6.2f %6.2f %6.2f %6.2f" % [
			t - T_PRE, rad_to_deg(err), rad_to_deg(horiz), rad_to_deg(vert), rad_to_deg(bank_ist),
			w_mag, d_pitch, wb.x, yaw_soll, wb.y, ac.angular_velocity.y,
			ac.global_position.y, ac.linear_velocity.y,
			ac.in_roll, ac.in_yaw, fc._trim_pitch, rad_to_deg(beta)])
	if t - T_PRE > 8.0:
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
