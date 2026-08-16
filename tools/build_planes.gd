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
	# Ohne Argument werden ALLE Vorlagen neu geschrieben. Mit `nur=<id>` nur die genannte
	# — beim Feilen an einem Flugzeug soll nicht nebenbei jede andere Vorlage angefasst
	# werden, sonst steht am Ende ein Diff ueber sieben Dateien fuer eine Aenderung.
	var nur := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("nur="):
			nur = a.substr(4)
	if nur == "" or nur == "fokker":
		_build_fokker()
	if nur == "" or nur == "spitfire":
		_build_spitfire()
	if nur == "" or nur == "mustang":
		_build_mustang()
	if nur == "" or nur == "me262":
		_build_me262()
	if nur == "" or nur == "f86":
		_build_f86()
	if nur == "" or nur == "mig15":
		_build_mig15()
	if nur == "" or nur == "sturmjet":
		_build_sturmjet()
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
##
## ALLE STELLEN SIND AUS DEM ECHTEN FLUGZEUG GERECHNET, nicht geschätzt.
##
## ACHTUNG, DIE FALLE: `me262_body` liegt NICHT mittig auf dem Ursprung. Nachgemessen an
## der Geometrie (nicht am Katalog-Feld `size`!) reicht der Rumpf von z = -2.88 bis
## z = +3.72 — der Ursprung sitzt also bei 44 % der Länge. Wer mit der Mitte rechnet,
## setzt alles um 0,42 m zu weit vorn; beim ersten Versuch ragten deshalb die
## Kanonenrohre 31 cm vor der Nasenspitze in die Luft.
##
## Die Me 262 A-1a ist 10,60 m lang, der Rumpf hier 6,60 m -> Maßstab 0,6226. Eine
## Station x Meter hinter der echten Nasenspitze landet bei
##       z = -2.88 + x * 0.6226
## Alle Zahlen unten kommen aus dieser Formel und sind damit nachrechenbar.
##
## Verwendete Stationen (Dreiseitenansicht der A-1a, Meter ab Nasenspitze):
##   Flügelwurzel Vorderkante 4,35 · Hinterkante 7,50   -> Mitte 5,93 -> z = +0.81
##   Gondel vorn 4,15 · hinten 7,95                     -> Mitte 6,05 -> z = +0.89
##   Seitenflosse Wurzel-Vorderkante 8,40               ->             z = +2.35
##   Höhenleitwerk Mitte 9,90                           ->             z = +3.28
##   Kanonen (MK 108) Mitte 1,70                        ->             z = -1.82
##   Bugfahrwerk 1,90 · Hauptfahrwerk 5,40              -> z = -1.70 / +0.48
##
## Gemessene Eigen-Ausdehnungen der Teile (tools/_aabb_me262.gd), gebraucht, um von der
## gewünschten STATION auf den zu setzenden URSPRUNG zu kommen:
##   autocannon  z[-1.11..0.87]  (Rohr zeigt nach -z, Ursprung bei 56 %)
##   jet_engine  z[-1.33..1.62]  y[-0.78..0.59]
##   wing_swept  z[-0.85..2.04]  (Ursprung = Wurzel-Mitte)
##   v_stab      z[-0.65..1.10]  x[0..1.80] (Spannweite -> nach dem Drehen die Höhe)
##   h_stab      z[-0.55..0.68]  x[0..2.60]
##   wheel_jet   y[-1.05..0]     wheel_nose  y[-1.10..0.02]
func _build_me262() -> void:
	var bc := _new_bc()
	var GREY := Color(0.62, 0.66, 0.70)        # RLM 76 hellgrau-blau, Rumpf und Gondeln
	var GRUEN := Color(0.38, 0.43, 0.36)       # RLM 82 dunkelgrün, Tragflächen und Leitwerk
	var DARK := Color(0.13, 0.13, 0.15)
	# Die Cockpit-Wurzel wird nur als Ankerpunkt gebraucht und deshalb winzig gemacht:
	# me262_body bringt die Rahmenkanzel bereits mit. Zwei Kanzeln uebereinander waren
	# der auffaelligste Fehler der alten Fassung.
	_setup_root(bc, GREY, Vector3(0.12, 0.12, 0.12))
	var rp := _root_part(bc)
	if rp:
		rp.position = Vector3(0, -0.05, -0.5)
	# Dedizierter Me-262-Rumpf (Blender: Hai-Querschnitt + Kanzel) @ origin
	P(bc, "me262_body", Vector3(0, 0, 0), Basis(), GREY)
	# PFEILFLÜGEL, tief am dreieckigen Rumpf. Halbspannweite 3,95 m (echte 12,60 m mal
	# Maßstab, halbiert) -> 3.95/4.60 = 0.86. Der Ursprung des Flügels IST die
	# Wurzelmitte, die Station geht also direkt als z ein.
	# Pfeilung bleibt unskaliert: 1,5 m Spitzenversatz auf 3,95 m = 21 Grad gegen die
	# echten 18,5 Grad an der Vorderkante — näher kommt kein Flügel im Katalog.
	PW(bc, "wing_swept", -0.30, 0.81, GRUEN, Vector3(0.86, 1.0, 1.0))
	# ZWEI JUMO-004-GONDELN UNTER dem Flügel (Symmetrie spiegelt die linke).
	# Länge 3,80 m -> 2,37 m -> 0.92. Durchmesser 0,85 m verhält sich zum 1,10 m breiten
	# echten Rumpf wie 0,62 m zu den 0,80 m hier -> 0.52.
	# z: Gondelmitte soll auf +0.89; der Ursprung liegt 0,135 m davor -> +0.76.
	# y: Flügelunterseite liegt bei -0.37, Gondeloberseite 0,31 m über dem Ursprung
	#    -> -0.68. Damit hängt die Gondel UNTER dem Flügel statt darauf.
	P(bc, "jet_engine", Vector3(1.45, -0.68, 0.76), Basis(), GREY, Vector3(0.52, 0.52, 0.92))
	# SEITENFLOSSE. Ragt echte 1,75 m über den Rumpf -> 1,10 m -> 1.10/1.80 = 0.61.
	# Vorher stand hier 1.15, also fast doppelt so hoch: das war die „F-15-Flosse“.
	# z: Wurzel-Vorderkante soll auf +2.35, sie liegt 0,52 m vor dem Ursprung -> +2.87;
	#    die Hinterkante endet damit auf +3.75, also bündig mit dem Rumpfende (+3.72).
	P(bc, "v_stab", Vector3(0, 0.30, 2.87), _ny(), GRUEN, Vector3(0.61, 1.0, 0.80))
	# HÖHENLEITWERK — bei der Me 262 sitzt es ein Stück ÜBER dem Rumpf an der Flosse, auf
	# rund 28 % ihrer Höhe. Genau das ist das Erkennungsmerkmal des Hecks, und genau das
	# hatte die alte Fassung auf Rumpfhöhe verschenkt.
	# Spannweite 3,70 m -> 2,30 m -> je Seite 1,15 -> 1.15/2.60 = 0.44.
	PW(bc, "h_stab", 0.61, 3.22, GRUEN, Vector3(0.44, 1.0, 0.85))
	# VIER MK 108 (30 mm) IN DER NASE, paarweise übereinander. autocannon statt cannon:
	# die Me 262 trug 30-mm-, keine 20-mm-Kanonen.
	# TIEF EINGELASSEN. Die Rechnung „Mündung 4 cm hinter der Nasenspitze“ war zwar
	# richtig, taugte aber nichts: die Spitze ist ein PUNKT auf der Mittellinie, und die
	# Rohre sitzen seitlich und höhenversetzt daneben — dort liegt die Rumpfhaut viel
	# weiter hinten, und die Rohre standen entsprechend weit im Freien.
	# Maßgeblich ist die Haut AN DER STELLE DES ROHRS. Nachgemessen (tools/_nase_breite.gd):
	#     z = -2.40  halbe Breite 0.12       z = -1.80  0.24       z = -1.20  0.33
	# x = ±0.21 (knapp über der Spiegelschwelle 0.15, sonst gäbe es nur zwei statt vier
	# Kanonen) passt ab z = -1.87 in den Rumpf. Mit Skalierung 0.6 ragt das Rohr 0,67 m
	# vor den Ursprung, bei z = -1.20 endet die Mündung also genau dort.
	# Am Original sieht man von den vier MK 108 ohnehin nur die Mündungsöffnungen.
	P(bc, "autocannon", Vector3(0.21, 0.05, -1.20), Basis(), DARK, Vector3(0.7, 0.7, 0.6))
	P(bc, "autocannon", Vector3(0.21, -0.20, -1.20), Basis(), DARK, Vector3(0.7, 0.7, 0.6))
	# DREIRADFAHRWERK — die Me 262 war der erste deutsche Serienjäger damit. Bugbein
	# eigens als wheel_nose (Doppelrad, Lenkkranz); vorher stand dort ein drittes
	# Hauptfahrwerksbein.
	# Beide Beine sind so gesetzt, dass die Räder auf DERSELBEN Ebene stehen (-1.37):
	# wheel_jet hängt 1,05 m unter seinem Ursprung, wheel_nose 1,10 m.
	# Die Ebene liegt 0,28 m unter der Gondelunterseite (-1.09) — das ist die
	# Bodenfreiheit, die die Triebwerke brauchen.
	P(bc, "wheel_nose", Vector3(0, -0.27, -1.70), Basis(), DARK, Vector3(0.8, 1.0, 0.8))
	P(bc, "wheel_jet", Vector3(0.55, -0.32, 0.48), Basis(), DARK)
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
	P(bc, "jet_nose", Vector3(0, 0, -3.0), Basis(), SILVER)                       # 1) Frontteil (Blender)
	P(bc, "jet_body", Vector3(0, 0, -1.25), Basis(), SILVER)                      # 2) generisch
	P(bc, "jet_cockpit", Vector3(0, 0, 0.35), Basis(), SILVER)                    # 3) Cockpit
	P(bc, "jet_body", Vector3(0, 0, 1.95), Basis(), SILVER, Vector3.ONE, 0.5, 1.0) # 4) generisch -> Heckkonus
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


## 7) Sturmjet — schwer bewaffneter Delta-Abfangjäger. Zeigt ALLE vier Waffentypen
##    (Raketenwerfer/Salve, Zielsuchrakete, schwere Lenkrakete, Bombe) + Delta-Flügel.
func _build_sturmjet() -> void:
	var bc := _new_bc()
	var GREY := Color(0.42, 0.46, 0.43)        # mattgrün-grau (Tarnung)
	var DARK := Color(0.13, 0.13, 0.15)
	# Nahtloser Loft-Rumpf (wie MiG): Nase + Rumpf + Cockpit + Heckkonus
	_setup_root(bc, GREY, Vector3(0.1, 0.1, 0.1))
	var rp := _root_part(bc)
	if rp:
		rp.position = Vector3(0, 0, 0)
	P(bc, "jet_nose", Vector3(0, 0, -3.0), Basis(), GREY)
	P(bc, "jet_body", Vector3(0, 0, -1.25), Basis(), GREY)
	P(bc, "jet_cockpit", Vector3(0, 0, 0.35), Basis(), GREY)
	P(bc, "jet_body", Vector3(0, 0, 1.95), Basis(), GREY, Vector3.ONE, 0.5, 1.0)
	P(bc, "jet_engine", Vector3(0, 0.05, 0.3), Basis(), GREY, Vector3(0.55, 0.55, 1.55))
	# Delta-Flügel (durchgehend) + hohes Kreuz-Leitwerk
	PW(bc, "wing_delta", -0.1, 0.5, GREY, Vector3(1.15, 1.0, 1.15))
	P(bc, "v_stab", Vector3(0, 0.5, 2.2), _ny(), GREY, Vector3(1.05, 1.5, 1.0))
	PW(bc, "h_stab", 1.3, 2.35, GREY, Vector3(0.9, 1.0, 1.0))
	# --- BEWAFFNUNG: alle vier Waffentypen unter den Flügeln (Symmetrie spiegelt) ---
	P(bc, "missile_heavy", Vector3(0.95, -0.42, 0.45), Basis(), DARK)   # schwere Lenkrakete (innen)
	P(bc, "rocket_pod", Vector3(1.45, -0.36, 0.35), Basis(), DARK)      # Raketenwerfer (Salve)
	P(bc, "missile", Vector3(2.05, -0.3, 0.4), Basis(), DARK)           # Zielsuchrakete (außen)
	P(bc, "bomb", Vector3(0.55, -0.5, 0.7), Basis(), DARK)             # Bombe (Rumpf-nah)
	# Dreirad-Jet-Fahrwerk
	P(bc, "wheel_jet", Vector3(0, -0.62, -1.4), Basis(), DARK)
	P(bc, "wheel_jet", Vector3(0.65, -0.55, 0.5), Basis(), DARK)
	_finish(bc, "sturmjet", "Sturmjet · schwer bewaffnet")


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
