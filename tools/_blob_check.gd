## Prueft die Blob-Animation: Reifen-Skalierung an mehreren Fahrwerksstellungen.
extends SceneTree
var f := 0
var fc: FlightController
func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	fc = FlightController.new()
	root.add_child(fc)
	var d: Array = [
		{"id": "cockpit", "xform": Transform3D()},
		{"id": "wheel_retract", "xform": Transform3D(Basis(), Vector3(0, -1.1, 0))},
		{"id": "wheel_jet", "xform": Transform3D(Basis(), Vector3(1.2, -1.1, 0.6))},
		{"id": "wheel_spitfire", "xform": Transform3D(Basis(), Vector3(-1.2, -1.1, 0.6))},
	]
	fc.build_from_design(d)
	var ac = fc.aircraft
	print("Fahrwerks-Elemente: ", ac.gear_items.size())
	for a in [0.0, 0.3, 0.65, 0.85, 1.0]:
		ac._gear_anim = a
		ac.gear_down = a < 0.5
		ac._process(0.001)
		var zeile := "a=%.2f  " % a
		for g in ac.gear_items:
			if not g["retract"]:
				continue
			var v = g["vis"]
			var sc: Vector3 = v.transform.basis.get_scale()
			zeile += "[%s %.2f/%.2f sichtbar=%s] " % [
				String(v.name).substr(0, 8), sc.x, sc.y, v.visible]
		print(zeile)
	quit()
	return true
