## Baut einen WWI-Doppeldecker (Propeller + 1 langsames MG) und speichert ihn als
## Anfangsfahrzeug nach user://aircraft_design.json.
## Godot --headless --path . --script res://tools/build_biplane.gd
extends SceneTree

var bc: BuildController
var frame := 0
const RED := Color(0.62, 0.16, 0.13)     # Roter-Baron-Rot
const WOOD := Color(0.34, 0.27, 0.18)    # Streben/Holz

func P(id: String, pos: Vector3, basis := Basis(), col := Color(0, 0, 0, 0)) -> void:
	bc._place_id(id, Transform3D(basis, pos), Vector3.ONE, col)

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
			bc._recolor(c, RED)

	var nx := bc._orient_to_normal(Vector3(1, 0, 0))   # Flügel/Leitwerk: Spannweite +X
	var ny := bc._orient_to_normal(Vector3(0, 1, 0))   # Seitenflosse nach oben

	# --- Rumpf + Rotor ---
	P("nose", Vector3(0, 0, -2.0), Basis(), RED)
	P("fuselage", Vector3(0, 0, 2.1), Basis(), RED)
	P("tailcone", Vector3(0, 0, 4.0), Basis(), RED)
	P("prop_engine", Vector3(0, 0, -3.65), Basis(), RED)   # Propeller (Rotor)

	# --- Doppeldecker-Tragwerk: untere + obere Tragfläche, durch Streben verbunden ---
	P("wing_straight", Vector3(0.65, -0.10, 0.3), nx, RED)   # untere Fläche (spiegelt)
	P("wing_straight", Vector3(0.65, 1.40, 0.3), nx, RED)    # obere Fläche (spiegelt)
	P("strut", Vector3(1.0, 0.65, 0.3), Basis(), WOOD)       # innere Strebe (spiegelt)
	P("strut", Vector3(2.2, 0.65, 0.3), Basis(), WOOD)       # äußere Strebe (spiegelt)

	# --- Leitwerk ---
	P("h_stab", Vector3(0.55, 0.0, 4.1), nx, RED)            # Höhenleitwerk (spiegelt)
	P("v_stab", Vector3(0, 0.55, 4.2), ny, RED)              # Seitenleitwerk (Mitte)

	# --- EINE langsame Waffe: ein MG oben auf dem Rumpf, schießt geradeaus ---
	P("mg", Vector3(0, 0.55, -1.2))

	# --- Festes Fahrwerk (2 Haupträder + Hecksporn) ---
	P("wheel", Vector3(1.3, -1.05, 0.3))                     # Hauptrad (spiegelt)
	P("wheel_light", Vector3(0, -0.85, 3.7))                 # Heckrad

	var floating: int = bc.floating_count()
	_save(bc.get_design())
	print("DOPPELDECKER gespeichert: ", bc.get_design().size(), " Teile | schwebend: ", floating)
	if floating > 0:
		print("  ⚠ WARNUNG: ", floating, " Teil(e) hängen frei — Layout anpassen!")
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
