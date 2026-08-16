## Diagnose: WOHER kommt der Querversatz (Nase unter dem Zeiger) beim zuegigen Ziehen?
## Faehrt den 80-%-Fall aus tools/mf_schlepp.gd und loggt Bank, Hoehe, Bahnneigung,
## kommandierte gegen geflogene Rate sowie die Aufteilung des Drehbudgets.
## Start: godot --headless --path . --script res://tools/_mf_quer_trace.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var nxt := 0.0
var rate := 0.0
var omega_inst := 0.0
const T_SETTLE := 2.5


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
		var ac0 := fc.aircraft
		ac0.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
		ac0.linear_velocity = Vector3(0, 0, -140.0)
		ac0.angular_velocity = Vector3.ZERO
		ac0.gear_down = false
		fc.look_yaw = 0.0
		fc.look_pitch = 0.0
		fc._reset_mouse_state()
		return false
	var ac := fc.aircraft
	fc.throttle = 1.0
	t += delta
	var tz := t - T_SETTLE
	if omega_inst <= 0.0 and t > T_SETTLE * 0.5:
		omega_inst = fc._auth_rates().x
		rate = 0.80 * omega_inst
		print("omega_inst=%.3f rad/s  Markerrate=%.3f rad/s = %.1f Grad/s" % [
			omega_inst, rate, rad_to_deg(rate)])
		print("  t   quer   lag    bank   alt    v    bahn   aoa   g   w_soll w_ist  pitchIN rollIN")
	if tz > 0.0:
		fc.look_yaw = rate * tz
	var aim: Vector3 = fc._aim_dir()
	var nose: Vector3 = -ac.global_transform.basis.z
	var u := aim.cross(Vector3.UP).normalized()
	var c := u.cross(aim).normalized()
	var lag := -atan2(nose.dot(u), nose.dot(aim))
	var quer := asin(clampf(nose.dot(c), -1.0, 1.0))
	var bb := ac.global_transform.basis
	# Bahnneigung = Steig-/Sinkwinkel des GESCHWINDIGKEITSVEKTORS
	var vel := ac.linear_velocity
	var bahn := asin(clampf(vel.normalized().y, -1.0, 1.0)) if vel.length() > 1.0 else 0.0
	# kommandierte Grosskreisrate (so wie der Regler sie in Z.609/610 deckelt)
	var auth := fc._auth_rates()
	var pmax: float = minf(fc._tab(maxf(ac.airspeed, 12.0), FlightController.PITCH_RATE_TAB), auth.x * FlightController.AUTH_HEADROOM)
	if tz > 0.0 and t >= nxt:
		nxt = t + 1.0
		print("%5.1f %6.2f %6.2f %7.1f %6.0f %5.0f %6.2f %5.2f %4.1f  %5.2f  %5.2f   %5.2f  %5.2f" % [
			tz, rad_to_deg(quer), rad_to_deg(lag),
			rad_to_deg(atan2(bb.x.y, bb.y.y)), ac.global_position.y, ac.airspeed,
			rad_to_deg(bahn), rad_to_deg(ac.aoa_signed), ac.load_factor,
			rad_to_deg(pmax), rad_to_deg(ac.angular_velocity.length()),
			ac.in_pitch, ac.in_roll])
	if tz > 12.0:
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
		var col = it.get("color", [0, 0, 0, 0])
		var sc = it.get("scale", [1, 1, 1])
		design.append({"id": it["id"], "xform": xf, "color": Color(col[0], col[1], col[2], col[3]), "scale": Vector3(sc[0], sc[1], sc[2]), "taper": it.get("taper", -1.0), "taper_front": it.get("taper_front", -1.0)})
	return design
