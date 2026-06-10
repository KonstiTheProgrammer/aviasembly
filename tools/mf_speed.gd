## Highspeed-Maus-Flug-Test: Überschwinger/Pendeln/Flügel/G bei 70+140 m/s (WT-Instructor).
## Start: Godot --headless --path . --script res://tools/mf_speed.gd
## Maus-Flug bei verschiedenen GESCHWINDIGKEITEN: Überschwinger + Pendeln messen.
extends SceneTree
var fc: FlightController
var frame := 0
var t := 0.0
var case_i := -1
var crossed := false
var peak_after := 0.0
var sd_n := 0
var sd_sum := 0.0
var sd_sq := 0.0
var settled_hold := 0
var max_w := 0.0
var gmax_seen := 0.0
const CASES := [
	{"name": "r90@70", "yaw": PI*0.5, "v": 70.0},
	{"name": "r90@140", "yaw": PI*0.5, "v": 140.0},
	{"name": "h180@140", "yaw": PI, "v": 140.0},
]
func _process(delta: float) -> bool:
	frame += 1
	if frame == 1: return false
	if frame == 2:
		var bc := BuildController.new(); root.add_child(bc)
		fc = FlightController.new(); root.add_child(fc)
		var f := FileAccess.open("res://designs/mig15.json", FileAccess.READ)
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
		_next()
		return false
	var ac := fc.aircraft
	fc.throttle = 1.0
	t += delta
	var aim: Vector3 = fc._aim_dir()
	var e: Vector3 = ac.global_transform.basis.transposed() * aim
	var horiz := atan2(e.x, -e.z)
	var c: Dictionary = CASES[case_i]
	# Überschwinger = Peak NACHDEM der Fehler erstmals ~0 erreicht hat. (Vorher
	# stand hier 0.25 rad — das maß bei monotoner Annäherung nur den EINLAUF-Wert
	# knapp unter der Schwelle, immer ~14°, egal wie gut der Regler war.)
	if not crossed and absf(horiz) < 0.03 and t > 0.3:
		crossed = true
	if crossed:
		peak_after = maxf(peak_after, absf(horiz))
	var align := (-ac.global_transform.basis.z).dot(aim)
	gmax_seen = maxf(gmax_seen, ac.gforce)
	if align > 0.995:
		settled_hold += 1
	else:
		settled_hold = 0
	if settled_hold > 40:
		sd_n += 1; sd_sum += horiz; sd_sq += horiz * horiz
		max_w = maxf(max_w, ac.angular_velocity.length())
	if sd_n >= 250 or t > 16.0:
		var sd := 0.0
		if sd_n > 10:
			var mean := sd_sum / sd_n
			sd = sqrt(maxf(sd_sq / sd_n - mean * mean, 0.0))
		print("%-10s ueberschw=%5.1f°  pendelSD=%6.4f  maxW=%.2f  v_end=%.0f  FLUEGEL=%s  gforce_max=%.1f" % [
			c["name"], rad_to_deg(peak_after), sd, max_w, ac.airspeed, ac.wing_status, gmax_seen])
		if case_i >= CASES.size() - 1:
			quit(); return true
		_next()
	return false
func _next() -> void:
	case_i += 1
	var c: Dictionary = CASES[case_i]
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 500, 0))
	ac.linear_velocity = Vector3(0, 0, -float(c["v"]))
	ac.angular_velocity = Vector3.ZERO
	fc.look_yaw = float(c["yaw"]); fc.look_pitch = 0.0
	fc._aim_cmd = -ac.global_transform.basis.z
	fc._bank_offset = 0.0
	t = 0.0; crossed = false; peak_after = 0.0
	sd_n = 0; sd_sum = 0.0; sd_sq = 0.0; settled_hold = 0; max_w = 0.0; gmax_seen = 0.0
