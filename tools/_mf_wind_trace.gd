## DIAGNOSE (Wegwerf): Was macht der Trim-Integrator im SAETTIGUNGSFALL?
## Faehrt exakt das Szenario aus tools/mf_track.gd Fall 0 (Marker wandert mit
## 0.35 rad/s seitlich + 0.15 rad Nick-Sinus) und legt die Innereien der Nickachse
## offen: kommandierte Rate, geflogene Rate, Vorsteuerung, Trimm, Ruderweg, AoA.
## Damit laesst sich unterscheiden, ob ein groesserer Schleppfehler vom Integrator
## kommt (Windup gegen den AoA-Limiter) oder von der Zelle (ehrliche Saettigung).
## Start: godot --headless --path . --script res://tools/_mf_wind_trace.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var nxt := 0.0
var err_acc := 0.0
var err_n := 0


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	if frame == 2:
		var bc := BuildController.new()
		root.add_child(bc)
		fc = FlightController.new()
		root.add_child(fc)
		fc.build_from_design(_load_design())
		fc.set_active(true)
		fc.mouse_fly = true
		var ac := fc.aircraft
		ac.global_transform = Transform3D(Basis(), Vector3(0, 1500, 0))
		ac.linear_velocity = Vector3(0, 0, -160)
		ac.angular_velocity = Vector3.ZERO
		ac.gear_down = false
		fc.look_yaw = 0.0
		fc.look_pitch = 0.0
		fc._aim_cmd = -ac.global_transform.basis.z
		fc._bank_offset = 0.0
		print("TRIM_I=%.2f TRIM_MAX=%.2f AUTH_HEADROOM=%.2f" % [
			fc.AIM_TRIM_I, fc.AIM_TRIM_MAX, fc.AUTH_HEADROOM])
		return false
	var ac2 := fc.aircraft
	if ac2 == null:
		return false
	fc.throttle = 1.0
	t += delta
	fc.look_yaw = 0.35 * t
	fc.look_pitch = 0.15 * sin(t * 0.8)
	var b := ac2.global_transform.basis
	var aim: Vector3 = fc._aim_dir()
	var err := acos(clampf((-b.z).dot(aim), -1.0, 1.0))
	if t > 3.0:
		err_acc += err
		err_n += 1
	var wb: Vector3 = b.transposed() * ac2.angular_velocity
	var auth: Vector3 = fc._auth_rates()
	if t >= nxt:
		nxt += 0.5
		print("t=%5.2f err=%6.1f°  wbx=%7.4f  authx=%6.4f  in_pitch=%7.4f  trim=%7.4f  aoa=%6.2f°  bank=%7.1f°  v=%5.1f  g=%5.2f" % [
			t, rad_to_deg(err), wb.x, auth.x, ac2.in_pitch, fc._trim_pitch,
			rad_to_deg(ac2.aoa_signed), rad_to_deg(atan2(b.x.y, b.y.y)), ac2.airspeed, ac2.load_factor])
	if t > 12.0:
		print("==> errMittel(>3s)=%.1f°" % rad_to_deg(err_acc / maxf(err_n, 1)))
		quit()
		return true
	return false


func _load_design() -> Array:
	var f := FileAccess.open("user://aircraft_design.json", FileAccess.READ)
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
