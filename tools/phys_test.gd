## Headless-Physik-Smoketest (temporär).
## Start: Godot --headless --path . --script res://tools/phys_test.gd
extends SceneTree

var fc: FlightController
var t := 0.0
var next_print := 0.5


func _initialize() -> void:
	# Boden
	var gb := StaticBody3D.new()
	gb.collision_layer = 1
	gb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	gb.add_child(cs)
	root.add_child(gb)

	var bc := BuildController.new()
	root.add_child(bc)
	fc = FlightController.new()
	root.add_child(fc)

	var design := _default_design(bc)
	fc.build_from_design(design)
	if OS.has_environment("NO_ASSIST"):
		fc.aircraft.assist = false
	print("--- Aircraft: mass=", fc.aircraft.mass, " thrust=", fc.aircraft.total_thrust,
		" wing_area=", fc.aircraft.wing_area, " eff_ar=", snappedf(fc.aircraft.eff_ar, 0.01),
		" lift_scale=", snappedf(fc.aircraft.lift_scale, 0.01), " com=", fc.aircraft.center_of_mass, " ---")


func _process(delta: float) -> bool:
	if fc == null or not is_instance_valid(fc.aircraft):
		return false
	var ac := fc.aircraft
	ac.throttle = 1.0
	ac.in_pitch = 0.0
	ac.in_roll = 0.0
	ac.in_yaw = 0.0
	# Spieler-Szenario: ab ~25 m/s (90 km/h) VOLL S ziehen und halten
	if ac.airspeed > 25.0:
		ac.in_pitch = 1.0
	t += delta
	if t >= next_print:
		next_print += 0.25
		var e := ac.global_transform.basis.get_euler()
		var w := ac.angular_velocity
		print("t=%4.2f v=%5.1f alt=%7.2f climb=%+6.2f | pitch=%6.1f roll=%6.1f yaw=%6.1f | aoa=%4.1f in_p=%.2f" % [
			t, ac.airspeed, ac.altitude, ac.climb,
			rad_to_deg(e.x), rad_to_deg(e.z), rad_to_deg(e.y),
			ac.aoa_deg, ac.in_pitch])
	return t > 20.0


func _default_design(bc: BuildController) -> Array:
	var d: Array = []
	d.append({"id": "cockpit", "xform": Transform3D(Basis(), Vector3(0, 0, 0))})
	d.append({"id": "nose", "xform": Transform3D(Basis(), Vector3(0, 0, -2.0))})
	d.append({"id": "fuselage", "xform": Transform3D(Basis(), Vector3(0, 0, 2.1))})
	d.append({"id": "tailcone", "xform": Transform3D(Basis(), Vector3(0, 0, 4.0))})
	d.append({"id": "prop_engine", "xform": Transform3D(Basis(), Vector3(0, 0, -3.65))})
	var wb := bc._orient_to_normal(Vector3.RIGHT)
	var wt := Transform3D(wb, Vector3(0.65, -0.05, 0.5))
	d.append({"id": "wing_tapered", "xform": wt})
	d.append({"id": "wing_tapered", "xform": bc._mirror_xform(wt)})
	var ht := Transform3D(wb, Vector3(0.6, 0.1, 4.1))
	d.append({"id": "h_stab", "xform": ht})
	d.append({"id": "h_stab", "xform": bc._mirror_xform(ht)})
	var vb := bc._orient_to_normal(Vector3.UP)
	if not OS.has_environment("NO_VSTAB"):
		d.append({"id": "v_stab", "xform": Transform3D(vb, Vector3(0, 0.55, 4.2))})
	d.append({"id": "wheel", "xform": Transform3D(Basis(), Vector3(1.5, -1.05, 0.8))})
	d.append({"id": "wheel", "xform": Transform3D(Basis(), Vector3(-1.5, -1.05, 0.8))})
	d.append({"id": "wheel", "xform": Transform3D(Basis(), Vector3(0, -1.05, -1.8))})
	return d
