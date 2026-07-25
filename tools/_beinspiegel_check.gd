## Prueft, dass ein ausgefahrenes Fahrwerksbein auf das GESPIEGELTE Rad uebertragen
## wird — sonst stuende das Flugzeug schief.
extends SceneTree
var f := 0

func _rad_y(teil: Node3D) -> float:
	var v := teil.get_node_or_null("Visual") as Node3D
	if v == null:
		return NAN
	var r := v.find_child("Wheel", true, false) as Node3D
	return NAN if r == null else r.global_position.y

func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var bc := BuildController.new()
	root.add_child(bc)
	bc.symmetry = true
	bc.load_design([
		{"id": "cockpit", "xform": Transform3D()},
		{"id": "wheel_jet", "xform": Transform3D(Basis(), Vector3(1.4, -0.6, 0.0))},
	])
	var rad: Node3D = null
	for c in bc.design_root.get_children():
		if String(c.get_meta("part_id", "")) == "wheel_jet":
			rad = c
	bc._select_part(rad)
	bc._sync_mirror(rad, rad.get_meta("pscale", Vector3.ONE))
	var sp = rad.get_meta("mirror") if rad.has_meta("mirror") else null
	if sp == null or not is_instance_valid(sp):
		print("FEHLER: kein Spiegel entstanden")
		quit()
		return true
	for gl in [1.0, 1.8, 2.4]:
		rad.set_meta("gear_len", gl)
		bc._rebuild_visual(rad)
		bc._apply_part_scale(rad, rad.get_meta("pscale", Vector3.ONE))
		bc._sync_mirror(rad, rad.get_meta("pscale", Vector3.ONE))
		print("gear_len=%.1f  Original y=%+.4f (x=%+.2f)  Spiegel y=%+.4f (x=%+.2f)  glen_spiegel=%.2f  Differenz %.5f"
			% [gl, _rad_y(rad), rad.position.x, _rad_y(sp), sp.position.x,
			   float(sp.get_meta("gear_len", 1.0)), absf(_rad_y(rad) - _rad_y(sp))])
	quit()
	return true
