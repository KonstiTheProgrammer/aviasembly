## Wieviel HOEHENRUDER braucht das Spieler-Design ueberhaupt, um NICHT zu steigen?
## Der Regler steht im Ruhefall bei in_pitch = -0.37 und erreicht damit exakt
## 0.000 rad/s Nickrate. Frage: ist das der Anschlag der Zelle (dann ist der
## 5.4°-Versatz Physik) oder liegt Ruderweg brach (dann ist es Reglerverschulden)?
## Verfahren: Regler AUS, feste Ruderstellung, 2 s halten, Nickrate messen.
## Start: godot --headless --path . --script res://tools/_mf_trimm.gd
extends SceneTree

var fc: FlightController
var ac: AircraftBody
var frame := 0
var t := 0.0
var case_i := -1

const DEFL := [0.0, -0.2, -0.37, -0.5, -0.75, -1.0, 1.0]


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
		ac = fc.aircraft
		var au: Vector3 = fc._auth_rates()
		_next()
		print("auth(nick/gier/roll) = %.3f / %.3f / %.3f rad/s | pitch_area=%.3f masse=%.0f kg" % [
			au.x, au.y, au.z, ac.pitch_area, ac.mass])
		return false
	t += delta
	fc.throttle = 1.0
	ac.in_pitch = float(DEFL[case_i])   # Regler liefert weiter roll/yaw, Nick wird ueberschrieben
	ac.in_roll = 0.0
	ac.in_yaw = 0.0
	if t > 2.0:
		var wb: Vector3 = ac.global_transform.basis.transposed() * ac.angular_velocity
		print("ruder=%5.2f -> nickrate=%7.4f rad/s  aoa=%5.2f°  g=%4.2f  v=%5.1f" % [
			float(DEFL[case_i]), wb.x, rad_to_deg(ac.aoa_signed), ac.load_factor, ac.airspeed])
		if case_i >= DEFL.size() - 1:
			quit()
			return true
		_next()
	return false


func _next() -> void:
	case_i += 1
	ac.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
	ac.linear_velocity = Vector3(0, 0, -140.0)
	ac.angular_velocity = Vector3.ZERO
	ac.gear_down = false
	fc._reset_mouse_state()
	t = 0.0


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
