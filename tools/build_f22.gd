## Baut die F-22 aus KOPF-MODELL + verjüngbarem Rumpfteil (kein Monolith mehr):
## f22_head (Spitznase + Kanzel) endet am gechinten Querschnitt; daran dockt f22_fuselage
## (prism, beide Enden skalierbar) und läuft zum Doppeltriebwerk zu. Delta, Doppelflossen,
## Stabilatoren, Kanone, Fahrwerk. Cockpit-Wurzel versteckt. Stealth-grau.
## -> user://aircraft_design.json   Godot --headless --path . --script res://tools/build_f22.gd
extends SceneTree

var bc: BuildController
var frame := 0
const GREY := Color(0.37, 0.39, 0.43)
const DARK := Color(0.22, 0.23, 0.26)

func P(id: String, pos: Vector3, basis := Basis(), scl := Vector3.ONE, col := GREY, taper := -1.0, taper_front := -1.0) -> void:
	bc._place_id(id, Transform3D(basis, pos), scl, col, taper, taper_front)

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
	var vcant := Basis(Vector3(0, 0, 1), deg_to_rad(-27.0)) * vfin

	# Kopf @ origin: Nase bei Z≈-2.2, Andock-Querschnitt (Heck) bei Z≈+1.8.
	P("f22_head", Vector3(0, 0, 0))
	# Verjüngbarer Rumpf: Front (voll) dockt an den Kopf (Z=1.8), Heck verjüngt (0.55) auf die Düsen.
	P("f22_fuselage", Vector3(0, 0, 3.1), Basis(), Vector3.ONE, GREY, 0.55, 1.0)
	# Zwei 2D-Schubvektordüsen am schmalen Heck (gespiegelt)
	P("f22_engine", Vector3(0.3, -0.02, 5.0), Basis(), Vector3.ONE, Color(0, 0, 0, 0))

	# Gepfeilte Delta-Flügel (mittig-tief)
	P("wing_delta", Vector3(0.6, -0.26, 2.1), nx, Vector3(1.35, 1.0, 1.3), GREY)
	# Stabilatoren hinten
	P("h_stab", Vector3(0.6, 0.0, 4.7), nx, Vector3(1.05, 1.0, 1.0), GREY)
	# Schräge Doppel-Seitenleitwerke
	P("v_stab", Vector3(0.45, 0.28, 4.0), vcant, Vector3.ONE, GREY)
	# Bordkanone (vorne rechts)
	P("cannon", Vector3(0.55, 0.1, -1.4), Basis(), Vector3.ONE, DARK)

	# Einziehfahrwerk: Bug + Hauptfahrwerk (gespiegelt)
	P("wheel_retract", Vector3(0, -0.55, -1.2))
	P("wheel_retract", Vector3(0.8, -0.6, 2.4))

	var floating: int = bc.floating_count()
	var design := bc.get_design()
	# Cockpit-Wurzel verstecken (winzig + tief im Kopf) -> keine zweite Kanzel; f22_head liefert die.
	for it in design:
		if String(it.get("id", "")) == "cockpit":
			it["scale"] = Vector3(0.16, 0.16, 0.16)
			it["xform"] = Transform3D((it["xform"] as Transform3D).basis, Vector3(0, -0.2, -1.0))
	_save(design)
	print("F-22 (Kopf+Rumpf) gespeichert: ", design.size(), " Teile | schwebend: ", floating)
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
			"taper_front": it.get("taper_front", 1.0),
		})
	var f := FileAccess.open("user://aircraft_design.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
