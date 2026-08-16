## Wie schnell dreht die Nase, wenn der Regler MIT allen Limitern voll ausdreht?
## (= die ehrliche flugmechanische Obergrenze, gegen die jede Sprung-/Schleppzeit
## zu messen ist. Der Rohstock-Test _mf_envelope.gd faehrt die Zelle in AoA-Grenzen,
## der Regler nicht — deshalb hier die Messung MIT Regler.)
## Marker steht fest 90 Grad rechts; geloggt werden Nasen-Azimutrate, Tempo, g, AoA.
## Start: godot --headless --path . --script res://tools/_mf_wmax.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var nxt := 0.0
var prev_az := 0.0
var best := 0.0
var case_i := 0
const SPEEDS := [140.0, 200.0, 100.0]


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
		_start()
		return false
	var ac := fc.aircraft
	fc.throttle = 1.0
	t += delta
	var nose: Vector3 = -ac.global_transform.basis.z
	var az := atan2(nose.x, -nose.z)
	if t >= nxt:
		nxt += 0.5
		var rate := absf(wrapf(az - prev_az, -PI, PI)) / 0.5
		if t > 1.0:
			best = maxf(best, rate)
		print("  t=%5.2f az=%7.1f° rate=%5.1f°/s v=%5.1f g=%5.2f aoa=%5.2f° bank=%6.1f° alt=%5.0f" % [
			t, rad_to_deg(az), rad_to_deg(rate), ac.airspeed, ac.load_factor,
			rad_to_deg(ac.aoa_signed), rad_to_deg(atan2(ac.global_transform.basis.x.y, ac.global_transform.basis.y.y)),
			ac.global_position.y])
		prev_az = az
	if t > 12.0:
		print("v_start=%3.0f -> SPITZENRATE(1s-Fenster) = %.1f °/s = %.3f rad/s" % [
			SPEEDS[case_i], rad_to_deg(best), best])
		case_i += 1
		if case_i >= SPEEDS.size():
			quit()
			return true
		_start()
	return false


func _start() -> void:
	fc.build_from_design(fc.design)
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 4000, 0))
	ac.linear_velocity = Vector3(0, 0, -SPEEDS[case_i])
	ac.angular_velocity = Vector3.ZERO
	ac.gear_down = false
	fc.look_yaw = PI * 0.5
	fc.look_pitch = 0.0
	fc._aim_cmd = -ac.global_transform.basis.z
	fc._bank_offset = 0.0
	fc._trim_pitch = 0.0
	t = 0.0
	nxt = 0.0
	prev_az = 0.0
	best = 0.0


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
