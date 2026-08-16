## DIAGNOSE (nur lesend): waagerechter Feinsprung, volle Kette Kommando -> Physik.
## Frage: der waagerechte Endanflug schliesst mit 0.5-0.7 Grad/s, obwohl die
## Querlage (17-34 Grad) eine koordinierte Kurve von 1.1-2.2 Grad/s hergaebe.
## Wo geht der Zug verloren? Geloggt wird d_pitch (nachgerechnet wie im Regler),
## die erreichte Nickrate, der Lastfaktor und die tatsaechliche Welt-Drehrate der Nase.
## Start: godot --headless --path . --script res://tools/_fein_bank.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var stepped := false
var nxt := 0.0
var ax0 := Vector3.UP
var prev_nose := Vector3.ZERO
var prev_t := 0.0

const DEG := 5.0
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
			prev_nose = nose0
			var aw: Vector3 = nose0.cross(fc._aim_dir())
			ax0 = aw.normalized() if aw.length() > 1e-6 else Vector3.UP
			prev_t = t
			print("--- %.1f Grad seitlich, v=%.0f ---" % [DEG, ac.airspeed])
			print("   t    err  horiz   vert |  bank | w_mag  gcPit  komp d_pitch |  wb.x  wb.y | n    aoa | inP  inR  inY | omH  omV | beta   vz")
		return false
	if t >= nxt:
		nxt += 0.2
		var b: Basis = ac.global_transform.basis
		var nose: Vector3 = -b.z
		var aimw: Vector3 = fc._aim_dir()
		var err := acos(clampf(nose.dot(aimw), -1.0, 1.0))
		var v: float = maxf(ac.airspeed, 12.0)
		var auth: Vector3 = fc._auth_rates()
		var pitch_max: float = minf(fc._tab(v, FlightController.PITCH_RATE_TAB), auth.x * FlightController.AUTH_HEADROOM)
		var g_lim: float = clampf(ac.wing_capacity / maxf(ac.mass * 9.81, 1.0), 3.0, 14.0)
		var n_turn: float = FlightController.G_SOFT * g_lim
		var w_gcap: float = 9.81 * sqrt(maxf(n_turn * n_turn - 1.0, 0.25)) / v
		var w_cap: float = minf(pitch_max, w_gcap)
		# ROHE Fehler (ohne _soft_dead) — die gedaempften taugen unter 0.46 Grad nicht
		var e: Vector3 = b.transposed() * fc._aim_cmd
		var horiz := atan2(e.x, -e.z)
		var vert := atan2(e.y, sqrt(e.x * e.x + e.z * e.z))
		var err_c := acos(clampf(-e.z, -1.0, 1.0))
		var w_mag: float = minf(w_cap, minf(FlightController.INS_KP_V * err_c, sqrt(2.0 * FlightController.AIM_TURN_ACC * err_c)))
		var cross_w: Vector3 = (-b.z).cross(aimw)
		var axis_w: Vector3 = cross_w.normalized() if cross_w.length() > 1e-4 else Vector3.ZERO
		var ff: Vector3 = fc._aim_ff * smoothstep(0.06, 0.18, fc._aim_ff.length())
		var w_des_w: Vector3 = axis_w * w_mag + ff.limit_length(w_cap * 0.7)
		if w_des_w.length() > w_cap:
			w_des_w = w_des_w.normalized() * w_cap
		var w_b_des: Vector3 = b.transposed() * w_des_w
		var gc_pitch: float = clampf(w_b_des.x, -pitch_max, pitch_max)
		var bank := atan2(b.x.y, b.y.y)
		var wh_eff := -w_des_w.y
		var komp := -wh_eff * sin(bank)
		var d_pitch: float = clampf(gc_pitch + komp, -pitch_max, pitch_max)
		var wb: Vector3 = b.transposed() * ac.angular_velocity
		var v_b: Vector3 = b.transposed() * ac.linear_velocity
		var beta := atan2(v_b.x, absf(v_b.z) + 0.6)
		# tatsaechliche Nasen-Drehung seit dem letzten Log (Welt): waagerecht/senkrecht
		var dt: float = maxf(t - prev_t, 1e-4)
		var dn: Vector3 = (nose - prev_nose) / dt
		var om_h := (dn.x * -prev_nose.z - dn.z * -prev_nose.x) / maxf(prev_nose.x * prev_nose.x + prev_nose.z * prev_nose.z, 1e-6)
		var om_v := dn.y
		prev_nose = nose
		prev_t = t
		print("%5.2f %6.3f %6.3f %6.3f | %6.1f | %.4f %6.4f %6.4f %7.4f | %6.4f %7.4f | %4.2f %5.3f | %5.2f %5.2f %5.2f | %6.3f %6.3f | %5.2f %6.1f" % [
			t - T_PRE, rad_to_deg((cross_w.normalized() * err).dot(ax0) if cross_w.length() > 1e-9 else 0.0), rad_to_deg(horiz), rad_to_deg(vert), rad_to_deg(bank),
			w_mag, gc_pitch, komp, d_pitch, wb.x, wb.y,
			ac.load_factor, ac.aoa_signed, ac.in_pitch, ac.in_roll, ac.in_yaw,
			rad_to_deg(om_h), rad_to_deg(om_v), rad_to_deg(beta), ac.linear_velocity.y])
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
