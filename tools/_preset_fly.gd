extends SceneTree
## Kurzer Preset-Flugcheck: lädt res://designs/<arg>.json, Vollgas, prüft
## Abheben, Tempo, eine harte Kurve (Maus-Ziel 90° rechts), Flügelstatus.
## Godot --headless --path . --script res://tools/_preset_fly.gd -- mig21

var frame := 0
var fc: FlightController
var t := 0.0
var phase := "roll"
var took_off := false
var vmax := 0.0
var gmax := 0.0

func _process(delta: float) -> bool:
	frame += 1
	if frame == 1: return false
	if frame == 2:
		var ua := OS.get_cmdline_user_args()
		var name := "mig21" if ua.is_empty() else ua[0]
		var bc := BuildController.new(); root.add_child(bc)
		fc = FlightController.new(); root.add_child(fc)
		var f := FileAccess.open("res://designs/%s.json" % name, FileAccess.READ)
		var arr = JSON.parse_string(f.get_as_text()); f.close()
		var design: Array = []
		for it in arr:
			var a = it["xform"]
			var xf := Transform3D(Basis(Vector3(a[0],a[1],a[2]),Vector3(a[3],a[4],a[5]),Vector3(a[6],a[7],a[8])), Vector3(a[9],a[10],a[11]))
			var c = it.get("color",[0,0,0,0]); var sc = it.get("scale",[1,1,1])
			design.append({"id": it["id"], "xform": xf, "color": Color(c[0],c[1],c[2],c[3]), "scale": Vector3(sc[0],sc[1],sc[2])})
		fc.build_from_design(design)
		fc.set_active(true)
		fc.mouse_fly = true
		var ac0 := fc.aircraft
		ac0.global_position = Vector3(0, 300, 0)
		ac0.linear_velocity = Vector3(0, 0, -120)
		print("MASSE=%.0f kg  FLAECHE=%.1f m²  WINGCAP=%.0f N  SCHUB=%.0f N" % [
			ac0.mass, ac0.wing_area, ac0.wing_capacity, ac0.total_thrust])
		return false
	var ac := fc.aircraft
	fc.throttle = 1.0
	t += delta
	vmax = maxf(vmax, ac.airspeed)
	gmax = maxf(gmax, ac.gforce)
	match phase:
		"roll":
			took_off = true
			phase = "climb"
		"climb":
			fc.look_pitch = deg_to_rad(12.0)
			if t > 14.0:
				phase = "turn"
				fc.look_yaw = deg_to_rad(90.0)
				fc.look_pitch = 0.0
		"turn":
			if t > 22.0:
				var fwd := -ac.global_transform.basis.z
				var yaw_err := rad_to_deg(absf(atan2(fwd.x, -fwd.z) - deg_to_rad(90.0)))
				print("KURVE: rest-Fehler=%.1f°  v=%.0f  g_max=%.1f  FLUEGEL=%s  alt=%.0f" % [
					yaw_err, ac.airspeed, gmax, ac.wing_status, ac.global_position.y])
				print("FAZIT: abgehoben=%s  vmax=%.0f  fluegel=%s" % [took_off, vmax, ac.wing_status])
				quit()
				return true
	if t > 30.0:
		print("TIMEOUT: phase=%s v=%.0f alt=%.1f abgehoben=%s" % [phase, ac.airspeed, ac.global_position.y, took_off])
		quit()
		return true
	return false
