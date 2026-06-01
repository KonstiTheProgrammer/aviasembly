## Baut einen Kampfjet zusammen und speichert ihn nach user://aircraft_design.json.
## Godot --headless --path . --script res://tools/build_jet.gd
extends SceneTree

var bc: BuildController
var frame := 0
const MIL := Color(0.40, 0.44, 0.41)     # militärgrün-grau
const DARK := Color(0.22, 0.24, 0.26)

func P(id: String, pos: Vector3, basis := Basis(), col := Color(0, 0, 0, 0)) -> void:
	bc._place_id(id, Transform3D(basis, pos), Vector3.ONE, col)

func _process(_d: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	bc = BuildController.new()
	root.add_child(bc)               # _ready -> design_root
	bc.symmetry = true
	bc.clear_design()                # Cockpit (Wurzel) bei (0,0,0)
	# Cockpit grau überlackieren
	for c in bc.design_root.get_children():
		if c.is_in_group("part"):
			bc._recolor(c, MIL)

	var nx := bc._orient_to_normal(Vector3(1, 0, 0))   # Flügel rechts (Spannweite +X)
	var ny := bc._orient_to_normal(Vector3(0, 1, 0))   # Seitenflosse (nach oben)

	# --- Rumpf (Mittellinie) ---
	P("nose", Vector3(0, 0, -2.0), Basis(), MIL)
	P("fuselage", Vector3(0, 0, 2.1), Basis(), MIL)
	P("fuselage_long", Vector3(0, 0, 4.7), Basis(), MIL)
	# Zwei ECKIGE Triebwerke hinten nebeneinander (Symmetrie spiegelt)
	P("jet_square", Vector3(0.7, 0, 7.5), Basis(), DARK)

	# --- Tragwerk ---
	P("wing_delta", Vector3(0.62, -0.1, 4.6), nx, MIL)        # Deltaflügel (spiegelt)
	P("canard", Vector3(0.62, 0.05, -0.6), nx, MIL)           # Canards vorne (spiegelt)
	P("v_stab", Vector3(0, 0.55, 6.9), ny, MIL)               # Seitenleitwerk (Mitte)
	P("h_stab", Vector3(0.55, 0.0, 7.0), nx, MIL)             # Höhenleitwerk (spiegelt)

	# --- Fahrwerk (Bugrad + 2 Hauptfahrwerke) ---
	P("wheel_heavy", Vector3(0, -0.85, -0.7))
	P("wheel_heavy", Vector3(0.9, -0.8, 3.2))

	_save(bc.get_design())
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
	print("KAMPFJET gespeichert: ", data.size(), " Teile")
