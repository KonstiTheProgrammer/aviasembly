## Baut den coolen F-22-Look MODULAR + per SKALIERUNG (kein Monolith-Rumpf):
## simples Cockpit als Wurzel, davon erweitert mit runden Standardteilen, die per pscale
## FLACH & BREIT gedrückt werden -> Stealth-Blended-Body. Doppeltriebwerk (zwei Nachbrenner),
## gepfeilte Deltaflügel, schräge Doppel-Seitenleitwerke, Stabilatoren, Fahrwerk. Stealth-grau.
## -> user://aircraft_design.json     Godot --headless --path . --script res://tools/build_f22.gd
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
	var vcant := Basis(Vector3(0, 0, 1), deg_to_rad(-28.0)) * vfin             # nach außen gekippt (F-22)

	# Vorne = -Z. FLACH-Skalierung (y runter, x leicht hoch) -> Stealth-Blended-Body.
	# Nase: lang, flach, spitz. (Rückseite an Cockpit-Front bei z=-1.1)
	P("nose", Vector3(0, -0.05, -2.45), Basis(), Vector3(1.12, 0.6, 1.55))
	# Cockpit ist die Wurzel @ (0,0,0) — Kanzel bleibt sichtbar (sitzt erhöht auf dem flachen Body).
	# Flacher, breiter Rumpf hinter dem Cockpit (z 1.1 .. 4.3)
	P("fuselage_long", Vector3(0, -0.05, 2.7), Basis(), Vector3(1.14, 0.62, 1.0))
	# Doppeltriebwerk hinten, eng nebeneinander (gespiegelt) — zwei Nachbrenner
	P("jet_engine", Vector3(0.4, -0.05, 5.5), Basis(), Vector3(0.82, 0.74, 1.0), Color(0, 0, 0, 0))

	# Gepfeilte Delta-Flügel (groß, tief, leicht hinten)
	P("wing_delta", Vector3(0.6, -0.22, 2.35), nx, Vector3(1.5, 1.0, 1.45), GREY)
	# Stabilatoren (alle-beweglich) ganz hinten
	P("h_stab", Vector3(0.58, -0.05, 4.5), nx, Vector3(1.1, 1.0, 1.0), GREY)
	# Schräg gestellte Doppel-Seitenleitwerke
	P("v_stab", Vector3(0.45, 0.22, 3.95), vcant, Vector3.ONE, GREY)

	# Einziehfahrwerk: Bug (mittig) + Hauptfahrwerk (gespiegelt)
	P("wheel_retract", Vector3(0, -0.5, -1.6))
	P("wheel_retract", Vector3(0.5, -0.52, 2.0))

	var floating: int = bc.floating_count()
	var design := bc.get_design()
	_save(design)
	print("F-22 (modular, skaliert) gespeichert: ", design.size(), " Teile | schwebend: ", floating)
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
