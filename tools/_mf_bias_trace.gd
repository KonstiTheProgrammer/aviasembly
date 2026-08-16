## DIAGNOSE (Wegwerf): Woher kommt der stehende Nickversatz bei stillstehender Maus?
## Zeiger fest nach vorne, Spieler-Design, 140 m/s. Geloggt wird der Ruderausschlag,
## den der Regler im eingeschwungenen Zustand DAUERHAFT braucht (in_pitch), gegen den
## Restfehler vert. Beides zusammen zeigt, ob der Versatz der klassische P-Sockel ist:
## err = u_halte / (dCmd/dErr) mit dCmd/dErr = (1/auth.x + AIM_PITCH_RATE_P) * INS_KP_V.
## Start: godot --headless --path . --script res://tools/_mf_bias_trace.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var nxt := 0.0


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
		ac.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
		ac.linear_velocity = Vector3(0, 0, -140.0)
		ac.angular_velocity = Vector3.ZERO
		ac.gear_down = false
		fc._reset_mouse_state()
		fc.look_yaw = 0.0
		fc.look_pitch = 0.0
		var a: Vector3 = fc._auth_rates()
		print("auth=%s masse=%.0f kg  dCmd/dErr=%.2f /rad" % [
			a, ac.mass, (1.0 / a.x + fc.AIM_PITCH_RATE_P) * fc.INS_KP_V])
		return false
	var ac2 := fc.aircraft
	if ac2 == null:
		return false
	fc.throttle = 1.0
	t += delta
	var b := ac2.global_transform.basis
	var e: Vector3 = b.transposed() * fc._aim_dir()
	var wb: Vector3 = b.transposed() * ac2.angular_velocity
	var vert := atan2(e.y, sqrt(e.x * e.x + e.z * e.z))
	if t >= nxt:
		nxt += (0.5 if t < 9.0 else 0.1)
		print("t=%5.2f vert=%9.5f°  in_pitch=%8.5f  wb.x=%9.6f  aoa=%6.2f°  trim=%8.5f  v=%5.1f  g=%5.2f" % [
			t, rad_to_deg(vert), ac2.in_pitch, wb.x, rad_to_deg(ac2.aoa_signed),
			fc._trim_pitch, ac2.airspeed, ac2.load_factor])
	if t > 14.0:
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
