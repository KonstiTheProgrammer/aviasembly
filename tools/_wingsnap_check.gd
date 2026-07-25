## Reproduziert das ECHTE Platzieren: Teil per _compute_snap_for auf die Unterseite eines
## Fluegels setzen und den SPALT messen (Fluegelhaut unten <-> Oberkante des neuen Teils).
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
		{"id": "wing_straight", "xform": Transform3D(Basis(), Vector3(0.6, 0.0, 0.0))},
	])
	var fl: Node3D = null
	for c in bc.design_root.get_children():
		if String(c.get_meta("part_id", "")) == "wing_straight":
			fl = c
	if fl == null:
		print("FEHLER: Fluegel nicht gefunden")
		quit()
		return true
	var wp := PartCatalog.get_part("wing_straight")
	var haut_y: float = fl.position.y + PartCatalog.col_offset(wp).y \
		- PartCatalog.col_size(wp).y * 0.5          # Boxunterseite = Profilunterseite
	var treff := Vector3(fl.position.x + 1.6, haut_y, 0.0)
	var pick := fl.get_node_or_null("Pick")
	print("Fluegel-Unterseite y=%+.4f, Treffer %s" % [haut_y, str(treff)])
	for id in ["wheel", "wheel_jet", "wheel_retract", "wheel_spitfire", "wheel_light",
			"missile", "tank"]:
		var p := PartCatalog.get_part(id)
		if p.is_empty():
			continue
		var snap: Dictionary = bc._compute_snap_for(id,
			{"position": treff, "normal": Vector3.DOWN, "collider": pick})
		if not snap.get("valid", false):
			print("  %-15s kein Snap" % id)
			continue
		var xf: Transform3D = snap["xform"]
		var co: Vector3 = PartCatalog.col_offset(p)
		var cs: Vector3 = PartCatalog.col_size(p)
		var box_oben: float = xf.origin.y + co.y + cs.y * 0.5   # Oberkante der Kollisionsbox
		print("  %-15s Ursprung y=%+.4f  Box-Oberkante y=%+.4f  SPALT %+.4f"
			% [id, xf.origin.y, box_oben, haut_y - box_oben])
	quit()
	return true
