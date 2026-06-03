## Baut einen A-10-„Warthog"-artigen Jet (gut gefaked aus den Modulteilen): gerade Flügel,
## Doppelleitwerk, hohe Triebwerke hinten, GAU-8-Minigun in der Nase. Grau lackiert.
## Godot --headless --path . --script res://tools/build_a10.gd
extends SceneTree

var bc: BuildController
var frame := 0
const GREY := Color(0.44, 0.46, 0.49)     # A-10-Grau
const DARK := Color(0.28, 0.30, 0.32)

func P(id: String, pos: Vector3, basis := Basis(), scl := Vector3.ONE, col := GREY) -> void:
	bc._place_id(id, Transform3D(basis, pos), scl, col)

func _process(_d: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	bc = BuildController.new()
	root.add_child(bc)
	bc.symmetry = true
	bc.clear_design()                 # Cockpit (Wurzel) bei (0,0,0)
	for c in bc.design_root.get_children():
		if c.is_in_group("part"):
			bc._recolor(c, GREY)

	var nx := bc._orient_to_normal(Vector3(1, 0, 0))   # Flügel/Höhenleitwerk: Spannweite +X
	var ny := bc._orient_to_normal(Vector3(0, 1, 0))   # Seitenflossen nach oben

	# --- Rumpf (lang) ---
	P("nose", Vector3(0, 0, -2.1))
	P("fuselage", Vector3(0, 0, 1.9))
	P("fuselage", Vector3(0, 0, 3.7))
	P("tailcone", Vector3(0, 0, 5.4))

	# --- GAU-8 Minigun in der Nase (gunmetal -> keine Lackierung) ---
	P("minigun", Vector3(0, -0.12, -3.4), Basis(), Vector3.ONE, Color(0, 0, 0, 0))

	# --- Gerade Tragflächen, tief angesetzt (groß) ---
	P("wing_straight", Vector3(0.6, -0.35, 2.0), nx, Vector3(1.35, 1.0, 1.25), GREY)

	# --- Hohe Triebwerke hinten (A-10-typisch, an den Rumpfseiten) ---
	P("jet_engine", Vector3(0.85, 0.55, 3.7), Basis(), Vector3(1.05, 1.05, 1.0), DARK)

	# --- Doppelleitwerk: breites Höhenleitwerk + zwei Seitenflossen an den Enden ---
	P("h_stab", Vector3(0.45, 0.25, 5.4), nx, Vector3(1.45, 1.0, 1.0), GREY)
	P("v_stab", Vector3(1.6, 0.45, 5.4), ny, Vector3.ONE, GREY)

	# --- Einziehfahrwerk: Bugrad + 2 Haupträder ---
	P("wheel_retract", Vector3(0, -0.9, -1.1))
	P("wheel_retract", Vector3(1.35, -0.95, 2.1))

	var floating: int = bc.floating_count()
	var design := bc.get_design()
	_save(design)
	print("A-10 gespeichert: ", design.size(), " Teile | schwebend: ", floating)
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
