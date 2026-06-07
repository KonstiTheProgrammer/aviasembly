## Baut drei historische Flugzeuge aus Bauteilen und speichert sie als Vorlagen
## nach res://designs/<id>.json (im Hangar unter "Vorlagen" ladbar).
## Godot --headless --path . --script res://tools/build_planes.gd
##
## WICHTIG zur Spiegelung: Teile mit Wurzel-x = 0 werden NICHT gespiegelt (unter der
## Schwelle ~0.15). Alles, was links UND rechts da sein soll (Flügel, Höhenleitwerk!),
## muss bei x >= ~0.2 platziert werden. Mittige Einzelteile (Seitenflosse, Bauchkühler,
## Spornrad) bleiben bei x = 0.
extends SceneTree

var frame := 0

func _process(_d: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	DirAccess.make_dir_recursive_absolute("res://designs")
	_build_fokker()
	_build_spitfire()
	_build_mustang()
	quit()
	return true

func _nx() -> Basis:
	return Basis()
func _ny() -> Basis:
	return Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))

func _new_bc() -> BuildController:
	var bc := BuildController.new()
	root.add_child(bc)
	bc.symmetry = true
	bc.snap_enabled = false
	bc.clear_design()
	return bc

func _root_part(bc: BuildController) -> Node3D:
	for c in bc.design_root.get_children():
		if c.is_in_group("part") and c.get_meta("is_root", false):
			return c
	return null

func _setup_root(bc: BuildController, col: Color, sc: Vector3) -> void:
	var r := _root_part(bc)
	if r:
		bc._recolor(r, col)
		bc._apply_part_scale(r, sc)

func P(bc: BuildController, id: String, pos: Vector3, basis := Basis(), col := Color(0, 0, 0, 0),
		pscale := Vector3.ONE, taper := -1.0, taper_front := -1.0) -> void:
	bc._place_id(id, Transform3D(basis, pos), pscale, col, taper, taper_front)

func _finish(bc: BuildController, fname: String, title: String) -> void:
	bc._notify_changed()
	var design := bc.get_design()
	var fc := bc.floating_count()
	_save(design, fname)
	print("%-12s : %d Teile  |  schwebend: %d  %s" % [
		title, design.size(), fc, ("OK" if fc == 0 else "!! NICHT VERBUNDEN")])
	bc.queue_free()


# 1) Fokker Dr.I — roter Dreidecker (WWI), Manfred von Richthofen — komplett neu
func _build_fokker() -> void:
	var bc := _new_bc()
	var RED := Color(0.74, 0.10, 0.11)
	var DARK := Color(0.11, 0.11, 0.13)
	var WOOD := Color(0.40, 0.26, 0.13)
	var BODY := Vector3(0.9, 1.1, 1.0)          # tiefer, schmaler WWI-Rumpf
	_setup_root(bc, RED, BODY)
	# --- Rumpf: Rotary-Motor vorn, kurzer tiefer Rumpf, Heckkonus ---
	P(bc, "prop_engine", Vector3(0, 0, -1.55), Basis(), RED, Vector3(1.1, 1.1, 1.0))
	P(bc, "fuselage", Vector3(0, 0, 1.45), Basis(), RED, BODY, 0.5, 1.0)
	P(bc, "tailcone", Vector3(0, 0, 2.85), Basis(), RED, Vector3(0.55, 0.62, 1.0))
	# --- Drei gerade Tragflächen: oben am breitesten, gleichmäßig gestapelt, leichter Staffel ---
	P(bc, "wing_straight", Vector3(0.2, 1.35, -0.12), _nx(), RED, Vector3(0.80, 1.0, 0.6))   # oben
	P(bc, "wing_straight", Vector3(0.2, 0.1, 0.0), _nx(), RED, Vector3(0.72, 1.0, 0.6))      # Mitte
	P(bc, "wing_straight", Vector3(0.2, -1.15, 0.12), _nx(), RED, Vector3(0.66, 1.0, 0.6))   # unten
	# --- Streben: Kabinenstreben OBEN und UNTEN (verbinden oberen UND unteren Flügel je
	#     mit dem Rumpf) + EINE durchgehende Interplane-Strebe außen (verbindet alle drei) ---
	var ST := Vector3(0.7, 1.0, 0.45)                                # schlanke Holzstrebe
	P(bc, "strut", Vector3(0.42, 0.72, -0.04), Basis(), WOOD, ST)    # Kabine: Rumpf<->oben (gespiegelt)
	P(bc, "strut", Vector3(0.42, -0.52, 0.06), Basis(), WOOD, ST)    # Kabine: Rumpf<->unten (gespiegelt)
	P(bc, "strut", Vector3(2.55, 0.10, -0.02), Basis(), WOOD, Vector3(0.7, 1.85, 0.45))  # Interplane durchgehend, alle 3 (gespiegelt)
	# --- Leitwerk: Höhenleitwerk gespiegelt (x=0.2!), Seitenflosse mittig ---
	P(bc, "h_stab", Vector3(0.2, 0.0, 2.95), _nx(), RED, Vector3(1.0, 1.0, 1.0))
	P(bc, "v_stab", Vector3(0, 0.45, 3.1), _ny(), RED, Vector3(0.95, 1.1, 1.0))
	# --- Twin-Spandau-MG auf der Haube (gespiegelt) ---
	P(bc, "mg", Vector3(0.18, 0.45, -0.45), Basis(), DARK)
	# --- Kreuz-Achsfahrwerk: Beine + DÜNNE Querachse + Räder MITTIG auf der Achse + Hecksporn ---
	P(bc, "strut", Vector3(0.45, -1.10, -0.1), Basis(), WOOD, Vector3(0.7, 0.76, 0.45))  # Bein (gespiegelt)
	P(bc, "strut", Vector3(0, -1.64, -0.1), _ny(), WOOD, Vector3(0.6, 1.0, 0.3))         # dünne Achse quer
	P(bc, "wheel", Vector3(0.58, -1.64, -0.1), Basis(), DARK)                             # Rad mittig auf der Achse (gespiegelt)
	P(bc, "wheel_light", Vector3(0, -0.55, 2.85), Basis(), DARK)                          # Hecksporn
	_finish(bc, "fokker_dr1", "Fokker Dr.I")


# 2) Supermarine Spitfire — eleganter Tiefdecker (WWII, RAF)
func _build_spitfire() -> void:
	var bc := _new_bc()
	var GREEN := Color(0.27, 0.34, 0.21)
	var GREY := Color(0.5, 0.52, 0.5)
	var DARK := Color(0.12, 0.12, 0.14)
	var BODY := Vector3(0.85, 0.92, 1.0)
	_setup_root(bc, GREEN, BODY)
	P(bc, "prop_engine_big", Vector3(0, 0, -1.8), Basis(), GREEN, Vector3(0.72, 0.72, 1.05))
	P(bc, "fuselage", Vector3(0, 0, 1.85), Basis(), GREEN, BODY, 0.82, 1.0)
	P(bc, "fuselage_taper", Vector3(0, 0, 4.0), Basis(), GREEN, BODY, 0.3, 1.0)
	# Tiefdecker-Tragflächen: tief am Rumpf, leicht vor dem Schwerpunkt, gespiegelt
	P(bc, "wing_tapered", Vector3(0.3, -0.46, 0.45), _nx(), GREEN, Vector3(0.95, 1.0, 1.2))
	# MG in den Flügeln (gespiegelt)
	P(bc, "mg", Vector3(1.5, -0.46, -0.25), Basis(), DARK)
	P(bc, "mg", Vector3(2.2, -0.46, -0.15), Basis(), DARK)
	# Leitwerk: Höhenleitwerk GESPIEGELT (x=0.2), Seitenflosse mittig hoch
	P(bc, "h_stab", Vector3(0.2, 0.05, 4.9), _nx(), GREEN, Vector3(0.8, 1.0, 1.0))
	P(bc, "v_stab", Vector3(0, 0.45, 5.1), _ny(), GREEN, Vector3(1.0, 1.15, 1.0))
	# Einziehfahrwerk (gespiegelt) + Spornrad (mittig)
	P(bc, "wheel_retract", Vector3(0.7, -1.0, 0.05), Basis(), GREY)
	P(bc, "wheel_light", Vector3(0, -0.5, 4.8), Basis(), GREY)
	_finish(bc, "spitfire", "Spitfire")


# 3) North American P-51 Mustang — silberner Tiefdecker (WWII)
func _build_mustang() -> void:
	var bc := _new_bc()
	var SILVER := Color(0.70, 0.72, 0.76)
	var DARK := Color(0.16, 0.16, 0.18)
	var BODY := Vector3(0.85, 0.92, 1.0)
	_setup_root(bc, SILVER, BODY)
	P(bc, "prop_engine_big", Vector3(0, 0, -1.8), Basis(), SILVER, Vector3(0.74, 0.74, 1.05))
	P(bc, "fuselage", Vector3(0, 0, 1.85), Basis(), SILVER, BODY, 0.85, 1.0)
	P(bc, "fuselage_long", Vector3(0, 0, 4.1), Basis(), SILVER, BODY, 0.4, 1.0)
	# Charakteristischer Bauch-Kühler (mittig)
	P(bc, "fueltank", Vector3(0, -0.7, 1.6), Basis(), SILVER, Vector3(0.62, 0.55, 1.2))
	# Laminare Tiefdecker-Tragflächen (gespiegelt)
	P(bc, "wing_tapered", Vector3(0.3, -0.46, 0.55), _nx(), SILVER, Vector3(0.92, 1.0, 1.05))
	# .50 cal MG in den Flügeln (gespiegelt)
	P(bc, "mg", Vector3(1.4, -0.46, -0.1), Basis(), DARK)
	P(bc, "mg", Vector3(2.0, -0.46, 0.0), Basis(), DARK)
	# Leitwerk: Höhenleitwerk GESPIEGELT (x=0.2), Seitenflosse mittig
	P(bc, "h_stab", Vector3(0.2, 0.05, 5.3), _nx(), SILVER, Vector3(0.8, 1.0, 1.0))
	P(bc, "v_stab", Vector3(0, 0.5, 5.5), _ny(), SILVER, Vector3(1.0, 1.1, 1.0))
	# Einziehfahrwerk (gespiegelt) + Spornrad (mittig)
	P(bc, "wheel_retract", Vector3(0.7, -1.0, 0.2), Basis(), DARK)
	P(bc, "wheel_light", Vector3(0, -0.5, 5.6), Basis(), DARK)
	_finish(bc, "mustang_p51", "P-51 Mustang")


func _save(design: Array, fname: String) -> void:
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
			"taper": it.get("taper", 1.0), "taper_front": it.get("taper_front", 1.0),
			"taper_y": it.get("taper_y", -1.0), "taper_front_y": it.get("taper_front_y", -1.0),
		})
	var f := FileAccess.open("res://designs/%s.json" % fname, FileAccess.WRITE)
	if f == null:
		print("FEHLER: kann res://designs/%s.json nicht schreiben" % fname)
		return
	f.store_string(JSON.stringify(data))
	f.close()
