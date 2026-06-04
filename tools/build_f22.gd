## Baut einen schnittigen Kampfjet MODULAR aus Standardteilen (kein Monolith-Rumpf mehr):
## echtes Cockpit-Modell als Wurzel + Nasenkonus + Rumpfsegment + rundes Düsentriebwerk
## (mit Nachbrenner) + Deltaflügel + schräge Doppel-Seitenleitwerke + Stabilatoren + Fahrwerk.
## Stealth-grau. -> user://aircraft_design.json
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
	# Cockpit (Wurzel @ 0,0,0) stealth-grau lackieren — bleibt SICHTBAR (das ist das Cockpit-Modell).
	for c in bc.design_root.get_children():
		if c.is_in_group("part"):
			bc._recolor(c, GREY)

	var nx := bc._orient_to_normal(Vector3(1, 0, 0))   # Flügel/Stabilatoren: Spannweite +X
	var vfin := Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))   # Flosse: Ruder hinten
	var vcant := Basis(Vector3(0, 0, 1), deg_to_rad(-26.0)) * vfin             # nach außen gekippt (F-22-Look)

	# Vorne = -Z. Module flächenbündig aneinander (Cockpit ist 2.2 lang -> z ∈ [-1.1, 1.1]).
	P("nose", Vector3(0, 0, -2.0))                                   # Nasenkonus (Rückseite an Cockpit-Front)
	P("fuselage_long", Vector3(0, 0, 2.7))                           # Rumpfsegment hinter dem Cockpit (z 1.1..4.3)
	P("jet_engine", Vector3(0, 0, 5.4), Basis(), Vector3.ONE, Color(0, 0, 0, 0))  # rundes Triebwerk hinten

	# Gepfeilte Delta-Flügel (mittig-tief, leicht hinten)
	P("wing_delta", Vector3(0.55, -0.22, 2.2), nx, Vector3(1.4, 1.0, 1.4), GREY)

	# Stabilatoren (alle-beweglich) ganz hinten
	P("h_stab", Vector3(0.55, 0.0, 4.3), nx, Vector3(1.05, 1.0, 1.0), GREY)

	# Schräg gestellte Doppel-Seitenleitwerke
	P("v_stab", Vector3(0.5, 0.33, 3.7), vcant, Vector3.ONE, GREY)

	# Einziehfahrwerk: Bug (mittig) + Hauptfahrwerk (gespiegelt)
	P("wheel_retract", Vector3(0, -0.62, -1.5))
	P("wheel_retract", Vector3(0.55, -0.66, 2.0))

	var floating: int = bc.floating_count()
	var design := bc.get_design()
	_save(design)
	print("Kampfjet (modular) gespeichert: ", design.size(), " Teile | schwebend: ", floating)
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
