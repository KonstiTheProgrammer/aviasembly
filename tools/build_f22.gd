## Baut den coolen F-22-Look MODULAR + per SKALIERUNG & VERJÜNGUNG (Taper):
## simples Cockpit als Wurzel; flacher, breiter Rumpf (y-flach skaliert), der nach hinten
## auf das Doppeltriebwerk ZULÄUFT (verjüngbare Rumpfteile). Lange Spitznase, großes Delta,
## schräge Doppel-Seitenleitwerke, Stabilatoren, Fahrwerk. Stealth-grau.
## -> user://aircraft_design.json     Godot --headless --path . --script res://tools/build_f22.gd
extends SceneTree

var bc: BuildController
var frame := 0
const GREY := Color(0.37, 0.39, 0.43)
const DARK := Color(0.22, 0.23, 0.26)

# taper: -1 = Teil-Default; sonst Verjüngung am +Z-Ende (1=keine, <1 schmaler, >1 breiter)
func P(id: String, pos: Vector3, basis := Basis(), scl := Vector3.ONE, col := GREY, taper := -1.0) -> void:
	bc._place_id(id, Transform3D(basis, pos), scl, col, taper)

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

	var nx := bc._orient_to_normal(Vector3(1, 0, 0))
	var vfin := Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))
	var vcant := Basis(Vector3(0, 0, 1), deg_to_rad(-28.0)) * vfin

	# Vorne = -Z. Flach (y≈0.6) + Verjüngung zum Heck -> Blended-Body.
	P("nose", Vector3(0, -0.05, -2.3), Basis(), Vector3(1.12, 0.6, 1.35))   # lange flache Spitznase
	# Cockpit = Wurzel @ (0,0,0), sichtbar.
	# Breiter flacher Mittelrumpf (gleichbleibend breit)
	P("fuselage_long", Vector3(0, -0.05, 2.7), Basis(), Vector3(1.42, 0.62, 1.0), GREY, 1.0)
	# Heck-Rumpf: läuft nach hinten schmal zu (Taper 0.5) -> auf die Düsen
	P("fuselage", Vector3(0, -0.05, 5.1), Basis(), Vector3(1.42, 0.62, 1.0), GREY, 0.5)
	# Doppeltriebwerk am schmalen Heck (gespiegelt) — zwei Nachbrenner
	P("jet_engine", Vector3(0.34, -0.05, 6.5), Basis(), Vector3(0.78, 0.82, 1.0), Color(0, 0, 0, 0))

	# Gepfeilte Delta-Flügel (groß, tief)
	P("wing_delta", Vector3(0.62, -0.22, 2.5), nx, Vector3(1.5, 1.0, 1.45), GREY)
	# Stabilatoren hinten
	P("h_stab", Vector3(0.55, -0.05, 5.2), nx, Vector3(1.1, 1.0, 1.0), GREY)
	# Schräge Doppel-Seitenleitwerke
	P("v_stab", Vector3(0.42, 0.2, 4.5), vcant, Vector3.ONE, GREY)

	# Einziehfahrwerk: Bug + Hauptfahrwerk (gespiegelt)
	P("wheel_retract", Vector3(0, -0.45, -1.5))
	P("wheel_retract", Vector3(0.5, -0.5, 2.3))

	var floating: int = bc.floating_count()
	var design := bc.get_design()
	_save(design)
	print("F-22 (modular, verjüngt) gespeichert: ", design.size(), " Teile | schwebend: ", floating)
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
			"taper": it.get("taper", 1.0),
		})
	var f := FileAccess.open("user://aircraft_design.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
