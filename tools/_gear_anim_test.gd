## End-to-End: Flieger mit den 3 animierten Raedern bauen, G (toggle_gear) druecken und
## messen: laeuft die "retract"-Animation (Pivot-Rotation aendert sich), geht die
## Kollision aus, kommt sie beim Ausfahren zurueck? (Setup im 1. _process-Frame — SceneTree-Falle)
extends SceneTree

var fc: FlightController
var frame := 0
var phase := 0
var rot0 := {}

func _design() -> Array:
	var d: Array = []
	d.append({"id": "cockpit", "xform": Transform3D(), "color": Color(0,0,0,0), "scale": Vector3.ONE})
	var ids := ["wheel_biplane_spoke", "wheel_biplane_disc", "wheel_spitfire"]
	for i in ids.size():
		d.append({"id": ids[i], "xform": Transform3D(Basis(), Vector3(-1.5 + i * 1.5, -0.6, 0)),
			"color": Color(0,0,0,0), "scale": Vector3.ONE})
	# Fluegel damit build_from_design nicht ueber fehlende Aero stolpert
	d.append({"id": "wing_straight", "xform": Transform3D(Basis(), Vector3(1.4, 0, 0)), "color": Color(0,0,0,0), "scale": Vector3.ONE})
	return d

func _pivots() -> Dictionary:
	var out := {}
	for g in fc.aircraft.gear_items:
		var vis = g["vis"]
		if is_instance_valid(vis):
			var p = vis.find_child("Pivot_*", true, false)
			if p != null:
				out[vis] = (p as Node3D).rotation_degrees
	return out

func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		fc = FlightController.new()
		get_root().add_child(fc)
		fc.build_from_design(_design())
		return false
	var ac := fc.aircraft
	if frame == 2:
		var n_anim := 0
		for g in ac.gear_items:
			if g.get("anim") != null:
				n_anim += 1
		print("gear_items=%d  davon animiert=%d  (erwartet 3)" % [ac.gear_items.size(), n_anim])
		rot0 = _pivots()
		ac.toggle_gear()
		print("G gedrueckt -> gear_down=", ac.gear_down, " (erwartet false)")
		return false
	if frame == 80 and phase == 0:
		phase = 1
		print("nach Einfahren: _gear_anim=%.2f (erwartet 1.0)" % ac._gear_anim)
		var moved := 0
		var r1 := _pivots()
		for k in r1:
			if rot0.has(k) and (Vector3(r1[k]) - Vector3(rot0[k])).length() > 45.0:
				moved += 1
		print("Pivots bewegt: %d/3 (erwartet 3)" % moved)
		var dis := 0
		for g in ac.gear_items:
			if is_instance_valid(g["cs"]) and g["cs"].disabled:
				dis += 1
		print("Kollisionen deaktiviert: %d/3 (erwartet 3)" % dis)
		ac.toggle_gear()
		print("G nochmal -> ausfahren...")
		return false
	if frame == 160:
		print("nach Ausfahren: _gear_anim=%.2f (erwartet 0.0)" % ac._gear_anim)
		var back := 0
		var r2 := _pivots()
		for k in r2:
			if rot0.has(k) and (Vector3(r2[k]) - Vector3(rot0[k])).length() < 5.0:
				back += 1
		print("Pivots zurueck in Ruhelage: %d/3 (erwartet 3)" % back)
		var en := 0
		for g in ac.gear_items:
			if is_instance_valid(g["cs"]) and not g["cs"].disabled:
				en += 1
		print("Kollisionen wieder aktiv: %d/3 (erwartet 3)" % en)
		quit()
	return false
