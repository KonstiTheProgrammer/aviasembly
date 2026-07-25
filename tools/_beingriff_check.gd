## Prueft, dass beim Auswaehlen eines Fahrwerks der Bein-Griff erscheint (in JEDEM
## Gizmo-Modus) und bei anderen Teilen nicht.
extends SceneTree
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	var bc := BuildController.new()
	root.add_child(bc)
	bc.load_design([
		{"id": "cockpit", "xform": Transform3D()},
		{"id": "wing_straight", "xform": Transform3D(Basis(), Vector3(0.6, 0, 0))},
		{"id": "wheel_jet", "xform": Transform3D(Basis(), Vector3(2.0, -0.074, 0))},
	])
	for such in ["wheel_jet", "wing_straight"]:
		var teil: Node3D = null
		for c in bc.design_root.get_children():
			if String(c.get_meta("part_id", "")) == such:
				teil = c
		bc._select_part(teil)
		for modus in range(0, 3):
			bc.set_gizmo_mode(modus)
			var arten: Dictionary = {}
			for h in bc._handles:
				var k := String(h.get_meta("kind", "?"))
				arten[k] = int(arten.get(k, 0)) + 1
			var pos := ""
			for h in bc._handles:
				if String(h.get_meta("kind", "")) == "leg":
					pos = " Griff bei y=%+.3f" % h.position.y
			print("%-14s Modus %d -> %s%s" % [such, modus, str(arten), pos])
	quit()
	return true
