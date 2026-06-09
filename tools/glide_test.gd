## Gleitflug-Regressionstest: MiG-15 bei 150 m/s, Triebwerk AUS -> wie schnell verliert
## sie Fahrt? Bestanden, wenn nach ~5.4 s noch > 100 m/s übrig sind (Energie bleibt
## erhalten; früher fraß ein versteckter linear_damp=0.1 (COMBINE-Modus!) 150->60).
## Start: Godot --headless --path . --script res://tools/glide_test.gd
extends SceneTree
var fc: FlightController
var frame := 0
var t := 0.0
func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	if frame == 2:
		var bc := BuildController.new()
		root.add_child(bc)
		fc = FlightController.new()
		root.add_child(fc)
		var f := FileAccess.open("res://designs/mig15.json", FileAccess.READ)
		var arr = JSON.parse_string(f.get_as_text())
		f.close()
		var design: Array = []
		for it in arr:
			var a = it["xform"]
			var xf := Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))
			var c = it.get("color", [0, 0, 0, 0])
			var sc = it.get("scale", [1, 1, 1])
			design.append({"id": it["id"], "xform": xf, "color": Color(c[0], c[1], c[2], c[3]), "scale": Vector3(sc[0], sc[1], sc[2]), "taper": it.get("taper", -1.0), "taper_front": it.get("taper_front", -1.0)})
		fc.build_from_design(design)
		fc.set_active(true)
		fc.aircraft.global_transform = Transform3D(Basis(), Vector3(0, 600, 0))
		fc.aircraft.linear_velocity = Vector3(0, 0, -150)
		return false
	var ac := fc.aircraft
	fc.throttle = 0.0
	ac.throttle = 0.0
	t += delta
	if frame % 60 == 0:
		print("t=%4.1f  v=%5.1f  alt=%6.1f" % [t, ac.airspeed, ac.altitude])
	if t > 5.4:
		var ok := ac.airspeed > 100.0
		print("==> v(5.4s)=%.1f m/s  %s" % [ac.airspeed, "GLEITTEST BESTANDEN ✓" if ok else "ZU STARKE BREMSE ✗"])
		quit(0 if ok else 1)
		return true
	return false
