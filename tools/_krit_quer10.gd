## KRITIKER-Trace (nur lesend, aendert nichts am Regler).
## Frage: mf_fein meldet fuer den 10-Grad-Sprung WAAGERECHT t90 = 1.21 s, aber
## 5.36 s bis in den 0.2-Grad-Ring. Wo bleiben die 4 Sekunden zwischen 1 Grad und
## 0.2 Grad? Geloggt wird die Roll-Kette (Bedarf -> Gate -> Soll-Bank -> Ist-Bank)
## neben dem Grosskreisfehler.
## Start: godot --headless --path . --script res://tools/_krit_quer10.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var stepped := false
var nxt := 0.0

const DEG := 10.0
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
			var nose0: Vector3 = -ac.global_transform.basis.z
			fc.look_yaw = atan2(nose0.x, -nose0.z) + deg_to_rad(DEG)
			fc.look_pitch = asin(clampf(nose0.y, -1.0, 1.0))
			stepped = true
			nxt = t
			print("--- Sprung %.1f Grad seitlich, v=%.0f ---" % [DEG, ac.airspeed])
			print("   t    errGes  horiz   vert   whFilt   gate  bankSoll bankIst  wr_des   wb.z  in_roll  wb.y  beta")
		return false
	if t >= nxt:
		nxt += 0.25
		var b: Basis = ac.global_transform.basis
		var aimw: Vector3 = fc._aim_dir()
		var nose: Vector3 = -b.z
		var err := acos(clampf(nose.dot(aimw), -1.0, 1.0))
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
		var e: Vector3 = b.transposed() * fc._aim_cmd
		var horiz: float = fc._soft_dead(atan2(e.x, -e.z))
		var vert: float = fc._soft_dead(atan2(e.y, sqrt(e.x * e.x + e.z * e.z)))
		var cross_w: Vector3 = nose.cross(fc._aim_cmd)
		var axis_w: Vector3 = cross_w.normalized() if cross_w.length() > 1e-4 else Vector3.ZERO
		var w_des_w: Vector3 = axis_w * w_mag
		# Roll-Kette exakt wie im Regler (Zeilen 656-699)
		var wh_eff := -w_des_w.y
		var whf: float = fc._wh_filt
		var gate: float = smoothstep(0.006, 0.018, absf(whf))
		var bank_need: float = whf * gate
		var bank_soll: float = clampf(-atan(bank_need * v / 9.81) + fc._bank_offset, -FlightController.AIM_BANK_MAX, FlightController.AIM_BANK_MAX)
		var dbank := wrapf(bank_soll - bank_ist, -PI, PI)
		var roll_max: float = minf(fc._tab(v, FlightController.ROLL_RATE_TAB), auth.z * FlightController.AUTH_HEADROOM)
		var wr_coord: float = signf(dbank) * minf(roll_max, minf(sqrt(2.0 * FlightController.AIM_ROLL_ACC * absf(dbank)), absf(dbank) * 4.5))
		wr_coord *= 1.0 - 0.8 * clampf(absf(vert) / 0.45, 0.0, 1.0)
		print("%5.2f %8.3f %7.3f %6.3f %8.4f %6.3f %8.2f %7.2f %8.4f %7.4f %7.3f %7.4f %6.2f" % [
			t - T_PRE, rad_to_deg(err), rad_to_deg(horiz), rad_to_deg(vert),
			whf, gate, rad_to_deg(bank_soll), rad_to_deg(bank_ist),
			wr_coord, wb.z, ac.in_roll, wb.y, rad_to_deg(beta)])
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
