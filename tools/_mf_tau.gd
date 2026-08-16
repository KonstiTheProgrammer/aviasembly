## DIAGNOSE (Wegwerf): Wie schnell baut die Zelle ueberhaupt Nickrate auf?
## Legt den Regler still und gibt ROH vollen Hoehenruderausschlag. Gemessen wird der
## Anstieg von wb.x -> daraus Zeitkonstante tau und Endrate. Das ist die PHYSIKALISCHE
## Untergrenze jeder Anstiegszeit; kein Regler kann schneller sein.
## Start: godot --headless --path . --script res://tools/_mf_tau.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var nxt := 0.0
var w_end := 0.0


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
		fc.mouse_fly = false     # Regler AUS: wir wollen die nackte Zelle sehen
		fc.set_physics_process(false)
		var ac := fc.aircraft
		ac.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
		ac.linear_velocity = Vector3(0, 0, -140.0)
		ac.angular_velocity = Vector3.ZERO
		ac.gear_down = false
		ac.mouse_fly = true      # gleiche MOUSE_AUTH wie im Maus-Flug
		ac.throttle = 1.0
		print("auth_rates=%s  masse=%.0f kg" % [fc._auth_rates(), ac.mass])
		return false
	var ac2 := fc.aircraft
	ac2.throttle = 1.0
	ac2.in_pitch = 1.0
	ac2.in_roll = 0.0
	ac2.in_yaw = 0.0
	t += delta
	var wb: Vector3 = ac2.global_transform.basis.transposed() * ac2.angular_velocity
	w_end = wb.x
	if t >= nxt:
		nxt += 0.1
		print("t=%5.2f wb.x=%7.4f rad/s  aoa=%6.2f°  v=%5.1f  g=%5.2f" % [
			t, wb.x, rad_to_deg(ac2.aoa_signed), ac2.airspeed, ac2.load_factor])
	if t > 3.0:
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
