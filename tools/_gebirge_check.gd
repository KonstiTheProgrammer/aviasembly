## PROFIL DES HOCHGEBIRGES und Abnahme des Bergflugplatzes ADLERHORST.
##
## Prueft drei Dinge, die man dem Code nicht ansieht:
##   1. Wird aus der Massivkette wirklich ein durchgehender GRAT — oder eine Perlenkette
##      einzelner Kuppeln? Gemessen als Hoehenprofil laengs der Geraden.
##   2. Ist das Plateau wirklich EBEN? Die Bahn ist 900 m lang; ein Restgefaelle darauf
##      waere im Spiel ein Berg-und-Tal-Rollfeld.
##   3. Wie hoch stehen die Waende rings um den Platz? Das ist der ganze Reiz des Feldes.
##
## Godot --headless --path . --script res://tools/_gebirge_check.gd
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	# Konstanten aus dem Skript von Main holen statt sie hier zu wiederholen — sonst misst
	# das Werkzeug irgendwann etwas anderes, als das Spiel baut.
	var K: Dictionary = main.get_script().get_script_constant_map()
	var AH_LAENGS: float = K["ADLERHORST_LAENGS"]
	var AH_HOEHE: float = K["ADLERHORST_HOEHE"]
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var breite: float = K["TAL_BREITE"]

	print("=== HOEHENPROFIL LAENGS DER TALACHSE (alle 200 m) ===")
	var minh := 9e9
	var maxh := -9e9
	for i in range(0, 41):
		var d := float(i) * 200.0
		var p := start + dir * d
		var h := tw.height_at(p.x, p.y)
		minh = minf(minh, h)
		maxh = maxf(maxh, h)
		var balken := "#".repeat(int(h / 20.0))
		var mark := "  <- ADLERHORST" if absf(d - AH_LAENGS) < 100.0 else ""
		print("  %4.0f m  %4.0f m  %s%s" % [d, h, balken, mark])
	print("  Talboden: tiefster Punkt %.0f m, hoechster %.0f m" % [minh, maxh])
	# QUERSCHNITT: wie hoch stehen die Waende links und rechts, und wie breit ist der Boden?
	print("\n=== TALQUERSCHNITT (quer zur Achse, an drei Stellen) ===")
	var quer := Vector2(dir.y, -dir.x)
	for laengs: float in [3000.0, 6000.0, float(K["ADLERHORST_LAENGS"])]:
		var mitte: Vector2 = start + dir * float(laengs)
		var zeile := "  bei %5.0f m: " % laengs
		for q in range(-9, 10):
			var h := tw.height_at(mitte.x + quer.x * float(q) * 400.0,
				mitte.y + quer.y * float(q) * 400.0)
			zeile += "%4d" % int(h)
		print(zeile)
	print("  (Spalten: -3600 m bis +3600 m quer zur Achse in 400-m-Schritten)")

	# --- Plateau ---
	var fp: Vector3 = main._adlerhorst_pos()
	print("\n=== PLATEAU ADLERHORST (Soll %.0f m) ===" % AH_HOEHE)
	var pmin := 9e9
	var pmax := -9e9
	var n := 0
	for j in range(-9, 10):
		for i in range(-9, 10):
			var x := fp.x + float(i) * 50.0
			var z := fp.z + float(j) * 50.0
			if Vector2(float(i) * 50.0, float(j) * 50.0).length() > 450.0:
				continue          # nur die Bahnflaeche (900 m lang)
			var h := tw.height_at(x, z)
			pmin = minf(pmin, h)
			pmax = maxf(pmax, h)
			n += 1
	print("  ueber die Bahnflaeche (%d Proben): %.2f .. %.2f m, Unebenheit %.3f m"
		% [n, pmin, pmax, pmax - pmin])

	# --- Waende ringsum ---
	# --- Was steht in BAHNRICHTUNG? ---
	# Die Bahn laeuft im lokalen Z des Flugplatzes; die Weltrichtung ist (sin h, cos h).
	var kurs := 0.0
	for af in main.airfields:
		if String(af["name"]) == "ADLERHORST":
			kurs = float(af["heading"])
	var bahn := Vector2(sin(kurs), cos(kurs))
	print("\n=== ABFLUGKORRIDOR (Bahnkurs %.1f Grad) ===" % rad_to_deg(kurs))
	for vz in [1.0, -1.0]:
		var schlimmster := -9e9
		var bei := 0.0
		for st in range(5, 41):
			var d := float(st) * 100.0
			var h := tw.height_at(fp.x + bahn.x * vz * d, fp.z + bahn.y * vz * d)
			var steig := (h - AH_HOEHE) / d
			if steig > schlimmster:
				schlimmster = steig
				bei = d
		print("  Richtung %+.0f: steilster noetiger Steigwinkel %.1f Grad (bei %.0f m)"
			% [vz, rad_to_deg(atan(schlimmster)), bei])

	print("\n=== WAENDE RINGS UM DEN PLATZ (hoechster Punkt je Richtung, bis 2 km) ===")
	for grad in [0, 45, 90, 135, 180, 225, 270, 315]:
		var a := deg_to_rad(float(grad))
		var hoch := -9e9
		var bei := 0.0
		for s in range(2, 21):
			var d := float(s) * 100.0
			var h := tw.height_at(fp.x + cos(a) * d, fp.z + sin(a) * d)
			if h > hoch:
				hoch = h
				bei = d
		print("  %3d Grad: bis %4.0f m (%.0f m ueber dem Platz) bei %.0f m Entfernung"
			% [grad, hoch, hoch - AH_HOEHE, bei])
	quit()
	return true
