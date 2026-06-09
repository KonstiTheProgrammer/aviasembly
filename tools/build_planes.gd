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
	_build_me262()
	_build_f86()
	_build_mig15()
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

# Platziert einen Flügel als ZWEI in der Mitte (x=0) zusammenstoßende Hälften: rechte
# Hälfte normal (+X), linke Hälfte X-gespiegelt (−X). Die Wurzeln treffen sich bündig bei
# x=0 -> KEIN Spalt in der Mitte. Beide werden als Symmetrie-Paar verknüpft. So bleibt ein
# durchgehender Flügel auch wenn er über/unter dem Rumpf liegt (Dreidecker oben/unten).
func PW(bc: BuildController, id: String, y: float, z: float, col := Color(0, 0, 0, 0),
		pscale := Vector3.ONE) -> void:
	var rt := bc._make_part(id, Transform3D(Basis(), Vector3(0, y, z)), col, pscale)
	var lb := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))   # X gespiegelt -> linke Hälfte
	var lf := bc._make_part(id, Transform3D(lb, Vector3(0, y, z)), col, pscale)
	rt.set_meta("mirror", lf)
	lf.set_meta("mirror", rt)

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
	# --- Drei gerade Tragflächen (je zwei mittig zusammenstoßende Hälften -> KEIN Mittelspalt) ---
	PW(bc, "wing_straight", 1.35, -0.12, RED, Vector3(0.85, 1.0, 0.6))   # oben (am breitesten)
	PW(bc, "wing_straight", 0.10, 0.0, RED, Vector3(0.76, 1.0, 0.6))     # Mitte
	PW(bc, "wing_straight", -1.15, 0.12, RED, Vector3(0.70, 1.0, 0.6))   # unten
	# --- Streben: Kabinenstreben OBEN und UNTEN (verbinden oberen UND unteren Flügel je
	#     mit dem Rumpf) + EINE durchgehende Interplane-Strebe außen (verbindet alle drei) ---
	var ST := Vector3(0.7, 1.0, 0.45)                                # schlanke Holzstrebe
	P(bc, "strut", Vector3(0.42, 0.72, -0.04), Basis(), WOOD, ST)    # Kabine: Rumpf<->oben (gespiegelt)
	P(bc, "strut", Vector3(0.42, -0.52, 0.06), Basis(), WOOD, ST)    # Kabine: Rumpf<->unten (gespiegelt)
	P(bc, "strut", Vector3(2.55, 0.10, -0.02), Basis(), WOOD, Vector3(0.7, 1.85, 0.45))  # Interplane durchgehend, alle 3 (gespiegelt)
	# --- Leitwerk: Höhenleitwerk als durchgehende Hälften (kein Mittelspalt), Seitenflosse mittig ---
	PW(bc, "h_stab", 0.0, 2.95, RED, Vector3(1.0, 1.0, 1.0))
	P(bc, "v_stab", Vector3(0, 0.45, 3.1), _ny(), RED, Vector3(0.95, 1.1, 1.0))
	# --- Twin-Spandau-MG auf der Haube (gespiegelt) ---
	P(bc, "mg", Vector3(0.18, 0.45, -0.45), Basis(), DARK)
	# --- Kreuz-Achsfahrwerk: Beine + DÜNNE Querachse + Räder MITTIG auf der Achse + Hecksporn ---
	P(bc, "strut", Vector3(0.45, -1.10, -0.1), Basis(), WOOD, Vector3(0.7, 0.76, 0.45))  # Bein (gespiegelt)
	P(bc, "strut", Vector3(0, -1.64, -0.1), _ny(), WOOD, Vector3(0.6, 1.0, 0.3))         # dünne Achse quer
	P(bc, "wheel", Vector3(0.58, -1.64, -0.1), Basis(), DARK)                             # Rad mittig auf der Achse (gespiegelt)
	P(bc, "wheel_light", Vector3(0, -0.55, 2.85), Basis(), DARK)                          # Hecksporn
	_finish(bc, "fokker_dr1", "Fokker Dr.I")


# 2) Supermarine Spitfire — eleganter Tiefdecker (WWII, RAF) — komplett neu
func _build_spitfire() -> void:
	var bc := _new_bc()
	var GREEN := Color(0.26, 0.33, 0.22)         # RAF-Dunkelgrün
	var GREY := Color(0.55, 0.57, 0.55)
	var DARK := Color(0.12, 0.12, 0.14)
	var BODY := Vector3(0.82, 0.92, 1.0)         # schlanker, runder Rumpf
	_setup_root(bc, GREEN, BODY)
	# --- Rumpf: Merlin-Nase, langer schlanker Rumpf, zum Heck spitz auslaufend ---
	P(bc, "prop_engine_big", Vector3(0, 0, -1.85), Basis(), GREEN, Vector3(0.70, 0.70, 1.05))
	P(bc, "fuselage", Vector3(0, 0, 1.70), Basis(), GREEN, BODY, 0.85, 1.0)
	P(bc, "fuselage_taper", Vector3(0, 0, 3.75), Basis(), GREEN, BODY, 0.3, 0.95)
	# --- Bauch-Kühler (Spitfire-typisch unter dem Rumpf) ---
	P(bc, "fueltank", Vector3(0, -0.52, 1.25), Basis(), GREY, Vector3(0.5, 0.42, 1.05))
	# --- Tiefdecker-Tragflächen (elliptisch angenähert), durchgehend ohne Mittelspalt (PW) ---
	PW(bc, "wing_tapered", -0.42, 0.60, GREEN, Vector3(0.92, 1.0, 1.2))
	# --- NEU: Flügel-MGs (Blender-Modell) paarweise in den Flügeln, feuern nach vorn ---
	P(bc, "wing_gun", Vector3(1.45, -0.42, -0.55), Basis(), DARK)
	P(bc, "wing_gun", Vector3(2.15, -0.42, -0.40), Basis(), DARK)
	# --- Leitwerk: Höhenleitwerk durchgehend (PW), Seitenflosse mittig ---
	PW(bc, "h_stab", 0.10, 4.55, GREEN, Vector3(0.85, 1.0, 1.0))
	P(bc, "v_stab", Vector3(0, 0.45, 4.75), _ny(), GREEN, Vector3(1.0, 1.15, 1.0))
	# --- Einziehfahrwerk (gespiegelt) + Spornrad (mittig) ---
	P(bc, "wheel_retract", Vector3(0.78, -0.42, 0.15), Basis(), GREY)   # Bein montiert am Flügel, Rad haengt darunter
	P(bc, "wheel_light", Vector3(0, -0.5, 4.45), Basis(), DARK)
	_finish(bc, "spitfire", "Spitfire")


# 3) North American P-51 Mustang — silberner Tiefdecker (WWII)
func _build_mustang() -> void:
	var bc := _new_bc()
	var SILVER := Color(0.80, 0.81, 0.84)        # blankes Aluminium (bare metal)
	var DARK := Color(0.13, 0.13, 0.15)
	# Cockpit-Wurzel verstecken (winzig + im Rumpf vergraben) — mustang_body liefert die Kanzel
	_setup_root(bc, SILVER, Vector3(0.12, 0.12, 0.12))
	var rp := _root_part(bc)
	if rp:
		rp.position = Vector3(0, -0.05, 0.3)
	# --- Dedizierter P-51-Rumpf (Blender-Modell: Rumpf + Kanzel + Bauch-Kühler) @ origin ---
	P(bc, "mustang_body", Vector3(0, 0, 0), Basis(), SILVER)
	# --- Packard-Merlin-Nase + 4-Blatt-Prop, deckt die Rumpfnase ---
	P(bc, "prop_engine_big", Vector3(0, 0, -2.25), Basis(), SILVER, Vector3(0.70, 0.70, 1.10))
	# --- Laminar-Tiefdecker, durchgehend ohne Mittelspalt (PW) ---
	PW(bc, "wing_tapered", -0.42, 0.45, SILVER, Vector3(1.0, 1.0, 1.18))
	# --- .50 cal Flügel-MGs (in den Flügeln eingelassen) ---
	P(bc, "wing_gun", Vector3(1.55, -0.42, 0.25), Basis(), DARK)
	P(bc, "wing_gun", Vector3(2.25, -0.42, 0.40), Basis(), DARK)
	# --- Leitwerk am Heck-Boom: Höhenleitwerk durchgehend (PW), hohe Seitenflosse mittig ---
	PW(bc, "h_stab", 0.05, 3.20, SILVER, Vector3(0.92, 1.0, 1.0))
	P(bc, "v_stab", Vector3(0, 0.50, 3.40), _ny(), SILVER, Vector3(1.0, 1.2, 1.0))
	# --- Einziehfahrwerk (am Flügel) + Spornrad (mittig) ---
	P(bc, "wheel_retract", Vector3(0.82, -0.42, 0.10), Basis(), SILVER)
	P(bc, "wheel_light", Vector3(0, -0.42, 3.15), Basis(), DARK)
	_finish(bc, "mustang_p51", "P-51 Mustang")


## 5) Messerschmitt Me 262 Schwalbe — erster einsatzfähiger Düsenjäger der Welt
func _build_me262() -> void:
	var bc := _new_bc()
	var GREY := Color(0.64, 0.67, 0.69)        # RLM 76 hellgrau-blau
	var DARK := Color(0.13, 0.13, 0.15)
	# Cockpit-Wurzel verstecken — me262_body liefert die Kanzel
	_setup_root(bc, GREY, Vector3(0.12, 0.12, 0.12))
	var rp := _root_part(bc)
	if rp:
		rp.position = Vector3(0, -0.05, -0.5)
	# Dedizierter Me-262-Rumpf (Blender: Hai-Querschnitt + Kanzel) @ origin
	P(bc, "me262_body", Vector3(0, 0, 0), Basis(), GREY)
	# Pfeilflügel (durchgehend, tief)
	PW(bc, "wing_swept", -0.20, 0.25, GREY, Vector3(1.05, 1.0, 1.0))
	# Zwei Jumo-004-Düsengondeln unter den Flügeln (Symmetrie spiegelt die linke)
	P(bc, "jet_engine", Vector3(1.65, -0.5, 0.1), Basis(), GREY, Vector3(0.78, 0.78, 0.9))
	# Leitwerk am Heck: durchgehendes Höhenleitwerk + hohe Seitenflosse
	PW(bc, "h_stab", 0.32, 3.15, GREY)
	P(bc, "v_stab", Vector3(0, 0.42, 3.3), _ny(), GREY, Vector3(1.0, 1.15, 1.0))
	# 4x MK108 30mm in der Nase (tief in die Nase eingelassen -> Mündung bündig)
	P(bc, "cannon", Vector3(0, -0.06, -1.55), Basis(), DARK, Vector3(0.85, 0.85, 0.9))
	# Dreirad-Jet-Fahrwerk: Bug (mittig) + Hauptfahrwerk (Symmetrie, rumpfnah)
	P(bc, "wheel_jet", Vector3(0, -0.5, -1.5), Basis(), DARK)
	P(bc, "wheel_jet", Vector3(0.5, -0.5, 0.55), Basis(), DARK)
	_finish(bc, "me262", "Me 262 Schwalbe")


## 6) North American F-86 Sabre — früher Pfeilflügel-Düsenjäger (Korea), Bare Metal
func _build_f86() -> void:
	var bc := _new_bc()
	var SILVER := Color(0.82, 0.83, 0.86)
	var DARK := Color(0.13, 0.13, 0.15)
	_setup_root(bc, SILVER, Vector3(0.12, 0.12, 0.12))
	var rp := _root_part(bc)
	if rp:
		rp.position = Vector3(0, 0.0, -0.6)
	# Dedizierter F-86-Rumpf (Blender: Nasen-Einlauf + Kanzel) @ origin
	P(bc, "f86_body", Vector3(0, 0, 0), Basis(), SILVER)
	# Triebwerk axial im Rumpf (lang & schlank -> genug Schub, Gondel versteckt), Düse/Flamme am Heck
	P(bc, "jet_engine", Vector3(0, 0.02, 1.92), Basis(), SILVER, Vector3(0.48, 0.48, 1.5))
	# Pfeilflügel (~35°), mittig
	PW(bc, "wing_swept", -0.08, 0.45, SILVER, Vector3(1.1, 1.0, 1.0))
	# Gepfeiltes Leitwerk
	PW(bc, "h_stab", 0.22, 3.0, SILVER)
	P(bc, "v_stab", Vector3(0, 0.40, 3.2), _ny(), SILVER, Vector3(1.0, 1.1, 1.0))
	# Dreirad-Jet-Fahrwerk: Bug (mittig) + Hauptfahrwerk am Flügel (Symmetrie)
	P(bc, "wheel_jet", Vector3(0, -0.55, -1.8), Basis(), DARK)
	P(bc, "wheel_jet", Vector3(0.7, -0.5, 0.55), Basis(), DARK)
	_finish(bc, "f86", "F-86 Sabre")


## 7) Mikojan-Gurewitsch MiG-15 — sowjetischer Pfeilflügel-Jet (Korea), hohes Leitwerk
func _build_mig15() -> void:
	var bc := _new_bc()
	var SILVER := Color(0.80, 0.81, 0.84)
	var DARK := Color(0.13, 0.13, 0.15)
	# MODULAR aus 4 gelofteten Abschnitten — alle mit GLEICHEM Querschnitt (0.65 x 0.55),
	# stoßbündig aneinander (kein Overlap -> keine Naht, keine Zacken):
	#   1) Frontteil (eigenes Modell, Lufteinlauf)  2) generisches Rumpfsegment
	#   3) Cockpit (eigenes Modell, Kanzel)          4) generisches Rumpfsegment (hinten,
	#      per Taper als Heckkonus -> Düse). Wurzel winzig im Rumpf vergraben.
	_setup_root(bc, SILVER, Vector3(0.1, 0.1, 0.1))
	var rp := _root_part(bc)
	if rp:
		rp.position = Vector3(0, 0.0, 0.0)
	P(bc, "jet_nose", Vector3(0, 0, -3.0), Basis(), SILVER)                       # 1) Frontteil
	P(bc, "jet_body", Vector3(0, 0, -1.28), Basis(), SILVER)                      # 2) generisch
	P(bc, "jet_cockpit", Vector3(0, 0, 0.32), Basis(), SILVER)                    # 3) Cockpit
	P(bc, "jet_body", Vector3(0, 0, 1.92), Basis(), SILVER, Vector3.ONE, 0.5, 1.0) # 4) generisch -> Heckkonus
	# Triebwerk axial (Düse tritt aus dem Heckkonus aus); lang im Rumpf verborgen
	P(bc, "jet_engine", Vector3(0, 0.05, 0.3), Basis(), SILVER, Vector3(0.5, 0.5, 1.5))
	# Pfeilflügel (~35°), mittig-tief — etwas größer, mit Grenzschichtzaun (MiG-Detail)
	PW(bc, "wing_swept", -0.12, 0.3, SILVER, Vector3(1.08, 1.0, 1.08))
	P(bc, "wing_fence", Vector3(1.25, 0.03, 0.42), Basis(), SILVER)
	# HOHE Seitenflosse + HOCH am Fin montiertes Höhenleitwerk (das MiG-15-Merkmal!)
	P(bc, "v_stab", Vector3(0, 0.5, 2.2), _ny(), SILVER, Vector3(1.05, 1.55, 1.0))
	PW(bc, "h_stab", 1.45, 2.35, SILVER, Vector3(0.92, 1.0, 1.0))
	# Dreirad-Jet-Fahrwerk: Bug (mittig) + Hauptfahrwerk am Flügel (Symmetrie)
	P(bc, "wheel_jet", Vector3(0, -0.6, -1.4), Basis(), DARK)
	P(bc, "wheel_jet", Vector3(0.6, -0.55, 0.4), Basis(), DARK)
	# --- Sowjet-Hoheitsabzeichen: rote Sterne (Material bleibt rot, Farbe egal) ---
	var bL := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))   # nach links (-X) gedreht
	var bUp := Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))   # Normale nach oben (+Y)
	P(bc, "red_star", Vector3(0.57, 0.0, 1.35), Basis(), SILVER, Vector3(1.0, 1.0, 1.0))  # Rumpf rechts (gespiegelt)
	P(bc, "red_star", Vector3(0.08, 0.9, 1.95), Basis(), SILVER, Vector3(0.6, 0.6, 0.6))  # Seitenflosse rechts
	P(bc, "red_star", Vector3(-0.08, 0.9, 1.95), bL, SILVER, Vector3(0.6, 0.6, 0.6))      # Seitenflosse links
	P(bc, "red_star", Vector3(1.7, 0.0, 0.55), bUp, SILVER, Vector3(0.9, 0.9, 0.9))       # Flügel oben (gespiegelt)
	_finish(bc, "mig15", "MiG-15")


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
