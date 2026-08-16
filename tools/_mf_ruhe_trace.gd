## Zeitverlauf der RESTUNRUHE bei stillstehender Maus (Spieler-Design).
## Zweck: unterscheiden, ob der Restfehler eine LANGE Phygoide (Hoehe/Tempo, ~30 s,
## in WT auch vorhanden) oder ein schneller Regel-Grenzzyklus ist (das WT-"Wobble",
## das weg muss). Druckt alle 0.25 s Fehler, Bank, Ruderausschlaege.
## Start: godot --headless --path . --script res://tools/_mf_ruhe_trace.gd
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
		fc.look_yaw = 0.0
		fc.look_pitch = 0.0
		fc._aim_cmd = -ac.global_transform.basis.z
		return false
	var ac2 := fc.aircraft
	fc.throttle = 1.0
	t += delta
	if t >= nxt:
		nxt += 0.25
		var b := ac2.global_transform.basis
		var e: Vector3 = b.transposed() * fc._aim_dir()
		var horiz := atan2(e.x, -e.z)
		var vert := atan2(e.y, sqrt(e.x * e.x + e.z * e.z))
		print("t=%5.2f h=%7.2f° v=%7.2f° bank=%7.1f° roll=%6.2f pitch=%6.2f yaw=%6.2f v=%5.1f alt=%6.0f g=%5.2f aoa=%5.2f" % [
			t, rad_to_deg(horiz), rad_to_deg(vert), rad_to_deg(atan2(b.x.y, b.y.y)),
			ac2.in_roll, ac2.in_pitch, ac2.in_yaw, ac2.airspeed, ac2.global_position.y,
			ac2.load_factor, rad_to_deg(ac2.aoa_signed)])
	if t > 20.0:
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
