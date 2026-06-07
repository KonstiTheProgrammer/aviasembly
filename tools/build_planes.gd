## Baut drei historische Flugzeuge aus Bauteilen zusammen und speichert sie als
## Vorlagen nach res://designs/<id>.json (vom Hangar-Menü ladbar).
## Godot --headless --path . --script res://tools/build_planes.gd
extends SceneTree

var frame := 0

func _process(_d: float) -> bool:
	frame += 1
	if frame < 2:                      # Setup erst im 1. _process-Frame (Nodes sind dann bereit)
		return false
	DirAccess.make_dir_recursive_absolute("res://designs")
	_build_fokker()
	_build_spitfire()
	_build_mustang()
	quit()
	return true


# Horizontale Tragfläche/Leitwerk: Spannweite entlang X (Symmetrie spiegelt nach -X).
func _nx() -> Basis:
	return Basis()
# Senkrechte Flosse: Spannweite nach oben (Y), Ruder hinten.
func _ny() -> Basis:
	return Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))


func _new_bc() -> BuildController:
	var bc := BuildController.new()
	root.add_child(bc)                 # _ready -> design_root
	bc.symmetry = true
	bc.snap_enabled = false            # exakte Platzierung aus dem Skript, kein Auto-Snap
	bc.clear_design()                  # Cockpit (Wurzel) bei (0,0,0)
	return bc


func _recolor_root(bc: BuildController, col: Color) -> void:
	for c in bc.design_root.get_children():
		if c.is_in_group("part") and c.get_meta("is_root", false):
			bc._recolor(c, col)


func P(bc: BuildController, id: String, pos: Vector3, basis := Basis(),
		col := Color(0, 0, 0, 0), pscale := Vector3.ONE) -> void:
	bc._place_id(id, Transform3D(basis, pos), pscale, col)


func _finish(bc: BuildController, fname: String, title: String) -> void:
	bc._notify_changed()
	var design := bc.get_design()
	var fc := bc.floating_count()
	_save(design, fname)
	print("%-10s gespeichert: %d Teile  |  schwebend: %d  %s" % [
		title, design.size(), fc, ("OK" if fc == 0 else "!! NICHT VERBUNDEN")])
	bc.queue_free()


# ===========================================================================
# 1) Fokker Dr.I — roter Dreidecker (WWI)
# ===========================================================================
func _build_fokker() -> void:
	var bc := _new_bc()
	var RED := Color(0.72, 0.11, 0.12)
	var DARK := Color(0.15, 0.15, 0.17)
	var WOOD := Color(0.45, 0.30, 0.16)
	_recolor_root(bc, RED)
	# Rumpf-Kette: Motor (vorn) - Cockpit(0) - Rumpf - Heck
	P(bc, "prop_engine", Vector3(0, 0, -1.9), Basis(), DARK)
	P(bc, "fuselage", Vector3(0, 0, 1.8), Basis(), RED)
	P(bc, "tailcone", Vector3(0, 0, 3.5), Basis(), RED)
	# DREI gestaffelte Tragflächen (Dreidecker), Wurzel auf der Mittellinie -> durchgehend verbunden
	P(bc, "wing_short", Vector3(0.2, 1.25, -0.1), _nx(), RED)   # oben (gespiegelt -> links+rechts)
	P(bc, "wing_short", Vector3(0.2, 0.15, 0.1), _nx(), RED)    # Mitte (am Rumpf)
	P(bc, "wing_short", Vector3(0.2, -0.95, 0.3), _nx(), RED)   # unten
	# Kabinenstreben (verbinden die Flügel senkrecht durch den Rumpf -> Verbindung sicher)
	P(bc, "strut", Vector3(0, 0.7, 0.0), Basis(), WOOD)         # Mitte->oben
	P(bc, "strut", Vector3(0, -0.4, 0.2), Basis(), WOOD)        # Mitte->unten
	# Außenstreben (Optik), an den Flügeln
	P(bc, "strut", Vector3(1.8, 0.7, -0.05), Basis(), WOOD)
	P(bc, "strut", Vector3(1.8, -0.4, 0.15), Basis(), WOOD)
	# Leitwerk
	P(bc, "h_stab", Vector3(0, 0.0, 3.4), _nx(), RED)
	P(bc, "v_stab", Vector3(0, 0.45, 3.7), _ny(), RED)
	# Festes Fahrwerk (zwei Räder vorn) + Hecksporn
	P(bc, "wheel", Vector3(0.55, -1.55, -0.2), Basis(), DARK)
	P(bc, "wheel_light", Vector3(0, -0.85, 3.3), Basis(), DARK)
	_finish(bc, "fokker_dr1", "Fokker Dr.I")


# ===========================================================================
# 2) Supermarine Spitfire — eleganter Tiefdecker (WWII, RAF)
# ===========================================================================
func _build_spitfire() -> void:
	var bc := _new_bc()
	var GREEN := Color(0.27, 0.34, 0.21)
	var GREY := Color(0.55, 0.57, 0.55)
	var DARK := Color(0.17, 0.17, 0.19)
	_recolor_root(bc, GREEN)
	# Rumpf: großer Merlin vorn, schlank zum Heck
	P(bc, "prop_engine_big", Vector3(0, 0, -2.0), Basis(), DARK)
	P(bc, "fuselage", Vector3(0, 0, 1.9), Basis(), GREEN)
	P(bc, "fuselage_taper", Vector3(0, 0, 4.2), Basis(), GREEN)
	# Elegante, breite Tiefdecker-Tragflächen (elliptisch angenähert)
	P(bc, "wing_tapered", Vector3(0.3, -0.42, 0.7), _nx(), GREEN, Vector3(1.2, 1.0, 1.15))
	# Leitwerk
	P(bc, "h_stab", Vector3(0, -0.05, 5.1), _nx(), GREEN)
	P(bc, "v_stab", Vector3(0, 0.5, 5.3), _ny(), GREEN)
	# Einziehfahrwerk unter den Flügeln + Spornrad
	P(bc, "wheel_retract", Vector3(0.75, -1.05, 0.1), Basis(), GREY)
	P(bc, "wheel_light", Vector3(0, -0.6, 4.9), Basis(), GREY)
	_finish(bc, "spitfire", "Spitfire")


# ===========================================================================
# 3) North American P-51 Mustang — silberner Tiefdecker (WWII)
# ===========================================================================
func _build_mustang() -> void:
	var bc := _new_bc()
	var SILVER := Color(0.70, 0.72, 0.76)
	var DARK := Color(0.20, 0.20, 0.22)
	var BLUE := Color(0.16, 0.26, 0.5)
	_recolor_root(bc, SILVER)
	# Langer, schlanker Rumpf
	P(bc, "prop_engine_big", Vector3(0, 0, -2.0), Basis(), DARK)
	P(bc, "fuselage", Vector3(0, 0, 1.9), Basis(), SILVER)
	P(bc, "fuselage_long", Vector3(0, 0, 4.2), Basis(), SILVER)
	P(bc, "tailcone", Vector3(0, 0, 6.2), Basis(), SILVER)
	# Tiefdecker-Tragflächen (gerade, laminar)
	P(bc, "wing_tapered", Vector3(0.3, -0.40, 0.8), _nx(), SILVER, Vector3(1.1, 1.0, 1.05))
	# Charakteristischer Bauch-Kühler (Radiator-Scoop)
	P(bc, "fueltank", Vector3(0, -0.75, 1.7), Basis(), SILVER, Vector3(0.7, 0.7, 1.3))
	# Leitwerk
	P(bc, "h_stab", Vector3(0, -0.05, 6.0), _nx(), SILVER)
	P(bc, "v_stab", Vector3(0, 0.55, 6.2), _ny(), SILVER)
	# Einziehfahrwerk + Spornrad
	P(bc, "wheel_retract", Vector3(0.75, -1.0, 0.2), Basis(), DARK)
	P(bc, "wheel_light", Vector3(0, -0.6, 6.4), Basis(), DARK)
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
