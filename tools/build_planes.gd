## Baut drei historische Flugzeuge aus Bauteilen und speichert sie als Vorlagen
## nach res://designs/<id>.json (im Hangar unter "Vorlagen" ladbar).
## Godot --headless --path . --script res://tools/build_planes.gd
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
	return Basis()                                                   # horizontale Fläche, Spannweite X
func _ny() -> Basis:
	return Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))  # senkrechte Flosse

func _new_bc() -> BuildController:
	var bc := BuildController.new()
	root.add_child(bc)
	bc.symmetry = true
	bc.snap_enabled = false
	bc.clear_design()
	return bc

func _recolor_root(bc: BuildController, col: Color) -> void:
	for c in bc.design_root.get_children():
		if c.is_in_group("part") and c.get_meta("is_root", false):
			bc._recolor(c, col)

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


# 1) Fokker Dr.I — roter Dreidecker (WWI)
func _build_fokker() -> void:
	var bc := _new_bc()
	var RED := Color(0.72, 0.11, 0.12)
	var DARK := Color(0.14, 0.14, 0.16)
	var WOOD := Color(0.43, 0.28, 0.15)
	_recolor_root(bc, RED)
	# Rumpf: runder WWI-Motor vorn, kurzer Rumpf, zum Heck verjüngt
	P(bc, "prop_engine", Vector3(0, 0, -1.7), Basis(), RED, Vector3(1.1, 1.1, 1.0))
	P(bc, "fuselage", Vector3(0, 0, 1.7), Basis(), RED, Vector3(1.0, 1.0, 1.0), 0.5, 1.0)   # Heck schmaler
	P(bc, "tailcone", Vector3(0, 0, 3.2), Basis(), RED, Vector3(0.7, 0.7, 1.0))
	# Drei gestaffelte Tragflächen (gespiegelt)
	P(bc, "wing_short", Vector3(0.2, 1.25, -0.1), _nx(), RED)
	P(bc, "wing_short", Vector3(0.2, 0.15, 0.1), _nx(), RED)
	P(bc, "wing_short", Vector3(0.2, -0.95, 0.3), _nx(), RED)
	# Kabinenstreben (Mitte, verbinden die Flügel senkrecht durch den Rumpf)
	P(bc, "strut", Vector3(0, 0.7, 0.0), Basis(), WOOD)
	P(bc, "strut", Vector3(0, -0.4, 0.2), Basis(), WOOD)
	# Außenstreben (Optik)
	P(bc, "strut", Vector3(1.8, 0.7, -0.05), Basis(), WOOD)
	P(bc, "strut", Vector3(1.8, -0.4, 0.15), Basis(), WOOD)
	# Leitwerk
	P(bc, "h_stab", Vector3(0, 0.0, 3.2), _nx(), RED)
	P(bc, "v_stab", Vector3(0, 0.45, 3.5), _ny(), RED)
	# Festes Fahrwerk + Hecksporn
	P(bc, "wheel", Vector3(0.55, -1.55, -0.2), Basis(), DARK)
	P(bc, "wheel_light", Vector3(0, -0.8, 3.1), Basis(), DARK)
	_finish(bc, "fokker_dr1", "Fokker Dr.I")


# 2) Supermarine Spitfire — eleganter Tiefdecker (WWII, RAF)
func _build_spitfire() -> void:
	var bc := _new_bc()
	var GREEN := Color(0.27, 0.34, 0.21)
	var GREY := Color(0.55, 0.57, 0.55)
	_recolor_root(bc, GREEN)
	# Schlanke, spitze Merlin-Nase (Triebwerk schmal skaliert, Haube grün)
	P(bc, "prop_engine_big", Vector3(0, 0, -1.85), Basis(), GREEN, Vector3(0.8, 0.8, 1.05))
	P(bc, "fuselage", Vector3(0, 0, 1.9), Basis(), GREEN, Vector3(1.0, 1.0, 1.0), 0.8, 1.0)
	# verjüngter Heckrumpf -> schlanke Spitze
	P(bc, "fuselage_taper", Vector3(0, 0, 4.1), Basis(), GREEN, Vector3(1.0, 1.0, 1.0), 0.32, 1.0)
	# Elegante, breite Tiefdecker-Tragflächen
	P(bc, "wing_tapered", Vector3(0.3, -0.42, 0.7), _nx(), GREEN, Vector3(1.25, 1.0, 1.2))
	# Leitwerk auf dem schlanken Heck
	P(bc, "h_stab", Vector3(0, 0.0, 5.0), _nx(), GREEN)
	P(bc, "v_stab", Vector3(0, 0.45, 5.2), _ny(), GREEN)
	# Einziehfahrwerk + Spornrad
	P(bc, "wheel_retract", Vector3(0.72, -1.05, 0.1), Basis(), GREY)
	P(bc, "wheel_light", Vector3(0, -0.55, 4.9), Basis(), GREY)
	_finish(bc, "spitfire", "Spitfire")


# 3) North American P-51 Mustang — silberner Tiefdecker (WWII)
func _build_mustang() -> void:
	var bc := _new_bc()
	var SILVER := Color(0.70, 0.72, 0.76)
	var DARK := Color(0.20, 0.20, 0.22)
	_recolor_root(bc, SILVER)
	# Lange schlanke Nase, langer Rumpf zum verjüngten Heck
	P(bc, "prop_engine_big", Vector3(0, 0, -1.85), Basis(), SILVER, Vector3(0.82, 0.82, 1.05))
	P(bc, "fuselage", Vector3(0, 0, 1.9), Basis(), SILVER, Vector3(1.0, 1.0, 1.0), 0.85, 1.0)
	P(bc, "fuselage_long", Vector3(0, 0, 4.2), Basis(), SILVER, Vector3(1.0, 1.0, 1.0), 0.4, 1.0)
	# Charakteristischer Bauch-Kühler (Radiator-Scoop)
	P(bc, "fueltank", Vector3(0, -0.72, 1.7), Basis(), SILVER, Vector3(0.7, 0.6, 1.3))
	# Laminare Tiefdecker-Tragflächen
	P(bc, "wing_tapered", Vector3(0.3, -0.40, 0.8), _nx(), SILVER, Vector3(1.15, 1.0, 1.05))
	# Leitwerk auf dem verjüngten Heck
	P(bc, "h_stab", Vector3(0, 0.0, 5.4), _nx(), SILVER)
	P(bc, "v_stab", Vector3(0, 0.5, 5.6), _ny(), SILVER)
	# Einziehfahrwerk + Spornrad
	P(bc, "wheel_retract", Vector3(0.72, -1.0, 0.2), Basis(), DARK)
	P(bc, "wheel_light", Vector3(0, -0.55, 5.7), Basis(), DARK)
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
