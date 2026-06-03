## Baut einen F-22-„Raptor"-artigen Stealth-Jet (gut gefaked aus Modulteilen): gepfeilte
## Delta-Flügel, schräg gestellte Doppel-Seitenleitwerke, zwei eckige Schubdüsen hinten,
## Stabilatoren, Bordkanone. Stealth-grau. -> user://aircraft_design.json
## Godot --headless --path . --script res://tools/build_f22.gd
extends SceneTree

var bc: BuildController
var frame := 0
const GREY := Color(0.37, 0.39, 0.43)     # Stealth-Grau
const DARK := Color(0.22, 0.23, 0.26)

func P(id: String, pos: Vector3, basis := Basis(), scl := Vector3.ONE, col := GREY) -> void:
	bc._place_id(id, Transform3D(basis, pos), scl, col)

func _process(_d: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	bc = BuildController.new()
	root.add_child(bc)
	bc.symmetry = true
	bc.clear_design()
	for c in bc.design_root.get_children():
		if c.is_in_group("part"):
			bc._recolor(c, GREY)

	var nx := bc._orient_to_normal(Vector3(1, 0, 0))   # Flügel/Stabilatoren: Spannweite +X
	var vfin := Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))   # Flosse: Ruder hinten
	var vcant := Basis(Vector3(0, 0, 1), deg_to_rad(-26.0)) * vfin             # nach außen gekippt (F-22)

	# --- Dedizierter gefacetteter Stealth-Rumpf (ein langes Teil, Nase..Heck mit Kanzel) ---
	P("f22_body", Vector3(0, 0, 0))

	# --- Gepfeilte Delta-Flügel (mittig-tief) ---
	P("wing_delta", Vector3(0.55, -0.28, 0.7), nx, Vector3(1.35, 1.0, 1.3), GREY)

	# --- Zwei dedizierte 2D-Schubvektordüsen hinten, eng beieinander ---
	P("f22_engine", Vector3(0.38, -0.05, 4.4), Basis(), Vector3.ONE, Color(0, 0, 0, 0))

	# --- Stabilatoren (alle-beweglich) hinten ---
	P("h_stab", Vector3(0.6, 0.0, 3.9), nx, Vector3(1.05, 1.0, 1.0), GREY)

	# --- Schräg gestellte Doppel-Seitenleitwerke ---
	P("v_stab", Vector3(0.5, 0.32, 3.4), vcant, Vector3.ONE, GREY)

	# --- Bordkanone (M61, vorne rechts) ---
	P("cannon", Vector3(0.55, 0.05, -2.6), Basis(), Vector3.ONE, DARK)

	# --- Einziehfahrwerk ---
	P("wheel_retract", Vector3(0, -0.7, -2.4))
	P("wheel_retract", Vector3(1.0, -0.78, 0.8))

	var floating: int = bc.floating_count()
	var design := bc.get_design()
	# Cockpit-Wurzel verstecken (winzig + tief im Rumpf) -> keine zweite Kanzel, f22_body liefert die.
	for it in design:
		if String(it.get("id", "")) == "cockpit":
			it["scale"] = Vector3(0.16, 0.16, 0.16)
			it["xform"] = Transform3D((it["xform"] as Transform3D).basis, Vector3(0, -0.2, -1.5))
	_save(design)
	print("F-22 gespeichert: ", design.size(), " Teile | schwebend: ", floating)
	if floating > 0:
		for fp in bc.floating_parts():
			print("  ⚠ schwebend: ", fp.get("id", "?"), " @ ", (fp["xform"] as Transform3D).origin)
	quit()
	return true

func _save(design: Array) -> void:
	var data: Array = []
	for it in design:
		var t: Transform3D = it["xform"]
		var b := t.basis
		var c: Color = it.get("color", Color(0, 0, 0, 0))
		var s: Vector3 = it.get("scale", Vector3.ONE)
		data.append({
			"id": it["id"],
			"xform": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z,
				t.origin.x, t.origin.y, t.origin.z],
			"color": [c.r, c.g, c.b, c.a],
			"scale": [s.x, s.y, s.z],
		})
	var f := FileAccess.open("user://aircraft_design.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
