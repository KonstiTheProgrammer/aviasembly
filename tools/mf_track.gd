## Praxis-Szenarien Maus-Flug (Nutzer-Design): (1) wandernder Marker = kontinuierliches
## Maus-Ziehen (Schleppfehler!), (2) Split-S (Ziel hinten-unten, Latch + Großkreis).
## Start: Godot --headless --path . --script res://tools/mf_track.gd
extends SceneTree
var fc: FlightController
var frame := 0
var t := 0.0
var case_i := 0
var err_acc := 0.0
var err_n := 0
var err_max_late := 0.0
var max_w := 0.0
var gmax := 0.0
func _process(delta: float) -> bool:
	frame += 1
	if frame == 1: return false
	if frame == 2:
		var bc := BuildController.new(); root.add_child(bc)
		fc = FlightController.new(); root.add_child(fc)
		var f := FileAccess.open("user://aircraft_design.json", FileAccess.READ)
		var arr = JSON.parse_string(f.get_as_text()); f.close()
		var design: Array = []
		for it in arr:
			var a = it["xform"]
			var xf := Transform3D(Basis(Vector3(a[0],a[1],a[2]),Vector3(a[3],a[4],a[5]),Vector3(a[6],a[7],a[8])), Vector3(a[9],a[10],a[11]))
			var c = it.get("color",[0,0,0,0]); var sc = it.get("scale",[1,1,1])
			design.append({"id": it["id"], "xform": xf, "color": Color(c[0],c[1],c[2],c[3]), "scale": Vector3(sc[0],sc[1],sc[2]), "taper": it.get("taper",-1.0), "taper_front": it.get("taper_front",-1.0)})
		fc.build_from_design(design)
		fc.set_active(true)
		fc.mouse_fly = true
		_start_case()
		return false
	var ac := fc.aircraft
	fc.throttle = 1.0
	t += delta
	if case_i == 0:
		# Marker wandert mit 0.35 rad/s seitlich (typisches Ziehen) — Nase soll folgen
		fc.look_yaw = 0.35 * t
		fc.look_pitch = 0.15 * sin(t * 0.8)
	var aim: Vector3 = fc._aim_dir()
	var nose: Vector3 = -ac.global_transform.basis.z
	var err := acos(clampf(nose.dot(aim), -1.0, 1.0))
	max_w = maxf(max_w, ac.angular_velocity.length())
	gmax = maxf(gmax, ac.gforce)
	if t > 3.0:
		err_acc += err; err_n += 1
		err_max_late = maxf(err_max_late, err)
	if case_i == 1 and frame % 30 == 0:
		var bb := ac.global_transform.basis
		print("  s t=%5.2f err=%6.1f° bank=%7.1f° pitchdeg=%6.1f v=%5.0f alt=%5.0f g=%5.1f" % [
			t, rad_to_deg(err), rad_to_deg(atan2(bb.x.y, bb.y.y)), rad_to_deg(asin(clampf(-bb.z.y if false else -(-bb.z).y * -1.0, -1, 1))), ac.airspeed, ac.global_position.y, ac.gforce])
	if t > 12.0:
		print("%-8s errMittel=%5.1f°  errMax(>3s)=%5.1f°  maxW=%.2f  g=%.1f  FLUEGEL=%s  alt=%.0f" % [
			["track","splitS"][case_i], rad_to_deg(err_acc/maxf(err_n,1)), rad_to_deg(err_max_late), max_w, gmax, ac.wing_status, ac.global_position.y])
		if case_i >= 1:
			quit(); return true
		case_i += 1
		_start_case()
	return false
func _start_case() -> void:
	var ac := fc.aircraft
	fc.build_from_design(fc.design)
	ac = fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 1500, 0))
	ac.linear_velocity = Vector3(0, 0, -160)
	ac.angular_velocity = Vector3.ZERO
	if case_i == 0:
		fc.look_yaw = 0.0; fc.look_pitch = 0.0
	else:
		fc.look_yaw = PI; fc.look_pitch = -0.6   # hinten-unten = Split-S
	fc._aim_cmd = -ac.global_transform.basis.z
	fc._bank_offset = 0.0
	t = 0.0; err_acc = 0.0; err_n = 0; err_max_late = 0.0; max_w = 0.0; gmax = 0.0
