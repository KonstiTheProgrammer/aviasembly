## KEILFORM DES HOCHTALS — misst, ob sich das Tal zur Tiefe hin wirklich verengt.
##
## Der Talquerschnitt in _gebirge_check.gd tastet nur alle 400 m und nur an drei Stellen
## ab; damit sieht man eine Verjuengung von ein paar hundert Metern nicht. Hier laeuft ein
## 25-m-Raster quer zur Achse ueber die ganze Talllaenge.
##
## GEMESSEN WIRD DER ZUSAMMENHAENGENDE BODEN UM DIE ACHSE, nicht "alle Proben unter der
## Schwelle": jenseits eines Kamms liegt das Vorland auch tief, und wer nur zaehlt,
## bekommt dessen Breite geschenkt. Deshalb von der Achse aus nach aussen laufen und beim
## ersten Punkt ueber der Schwelle abbrechen.
##
## Dazu zwei Gegenproben, die zu dieser Aenderung gehoeren:
##   * KAMMABSTAND ZU RADIUS. Der Laengsabstand der Kettenmassive muss rund die Haelfte
##     ihres Radius bleiben, sonst zerfaellt der Grat in Einzelkuppen. Durch den Keil
##     stehen die Massive nicht mehr exakt 1300 m auseinander, sondern etwas schraeg.
##   * KUESTE. Vorn steht die suedwestliche Kette weiter draussen als bisher. Wenn ihr
##     Fuss ueber die Kuestenlinie hinausreicht, entsteht im Meer eine Halbinsel, die dort
##     nichts zu suchen hat.
##
## godot --headless --path . --script res://tools/_tal_keil.gd [-- <aufsicht.png>]
## Ohne Argument landet die Aufsicht in user://tal_keil_aufsicht.png.
extends SceneTree
var f := 0
# Bricht ein Laufzeitfehler die Messung ab, ruft die Schleife _process im naechsten Frame
# WIEDER auf — und jeder Durchgang baut Main.tscn samt Fernschuerze neu. Ein einziger
# Tippfehler hat so einmal zehn Minuten Rechenzeit verbrannt, ohne eine Zeile Ausgabe.
var lief := false

const SCHWELLE := 200.0     # "Talboden" = Gelaende unter dieser Hoehe
const SCHRITT := 25.0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	if lief:
		push_error("Messung ist abgebrochen — siehe Fehler oben.")
		quit(1)
		return true
	lief = true
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var laenge: float = K["TAL_LAENGE"]
	var kette_r: float = K["TAL_KETTE_R"]
	var kette_d: float = K["TAL_KETTE_ABSTAND"]
	var quer := Vector2(dir.y, -dir.x)

	# ZWEI MESSREIHEN, und das ist der Kern des Werkzeugs.
	# "gewachsen" schaltet die Flachzonen (Flugplatz, Bergsee) fuer die Dauer der Messung
	# ab. Sonst misst man an den zwei interessantesten Stellen des Tals gar nicht die
	# Ketten, sondern die Radien zweier Einebnungszonen: die Zone von ADLERHORST hat den
	# Boden bei 8500..9000 m auf 1725 m aufgeweitet, obwohl der Fels dort nur rund 1040 m
	# frei laesst, und die Seezone haelt bei 5000 m rund 2000 m offen. Wer nur die gebaute
	# Reihe liest, haelt beide Kreise fuer Talform.
	# "gebaut" ist trotzdem die Reihe, die man im Spiel sieht — beide gehoeren berichtet.
	var af_sichern: Array = tw.airfields
	var lk_sichern: Array = tw.lakes
	for durchgang in 2:
		var gewachsen := durchgang == 0
		if gewachsen:
			tw.airfields = []
			tw.lakes = []
		else:
			tw.airfields = af_sichern
			tw.lakes = lk_sichern
		print("=== TALBODENBREITE %s (Gelaende unter %.0f m, zusammenhaengend um die Achse) ==="
			% ["GEWACHSEN (ohne Flachzonen)" if gewachsen else "GEBAUT (wie im Spiel)",
				SCHWELLE])
		var vorn := 0.0
		var hinten := 0.0
		var am_platz := 0.0
		# MITTELWERT ueber 500..9500 m. Ohne ihn laesst sich ein Keil vortaeuschen, indem
		# man nur vorn aufweitet: das Verhaeltnis stimmt dann, das Tal ist aber ueberall
		# breiter geworden. Urzustand (parallele Ketten, 2700/2600) lag bei rund 1350 m.
		var summe := 0.0
		var nmit := 0
		# 500-m-Raster PLUS die Stelle des Flugplatzes. Die 300-m-Toleranz von frueher hat
		# 8500 und 9000 beide als "bei ADLERHORST" gewertet und die letzte Probe gewinnen
		# lassen — dort steht schon die Querkette, gemeldet wurden 50 m Boden.
		var stationen: Array[float] = []
		for s in range(1, 23):
			var l := float(s) * 500.0
			if l > laenge:
				break
			if l > K["ADLERHORST_LAENGS"] and not stationen.has(K["ADLERHORST_LAENGS"]):
				stationen.append(K["ADLERHORST_LAENGS"])
			stationen.append(l)
		for laengs: float in stationen:
			var m := start + dir * laengs
			var seiten := [0.0, 0.0]
			for si in 2:
				var vz := 1.0 if si == 0 else -1.0
				var d := 0.0
				while d < 4000.0:
					d += SCHRITT
					var p := m + quer * vz * d
					if tw.height_at(p.x, p.y) > SCHWELLE:
						break
				seiten[si] = d
			var breite: float = seiten[0] + seiten[1]
			if laengs <= 3000.0:
				vorn = maxf(vorn, breite)
			# HINTEN wird bei 8000 m abgelesen, nicht am Platz: 8000 ist die letzte Stelle
			# vor BEIDEN Bauwerken — der Flachzone des Flugplatzes und dem Fuss der
			# Querkette, die ab 8100 m auf die Achse greift. Wer weiter hinten misst,
			# bekommt einen Wert, der nichts mehr mit den beiden Ketten zu tun hat.
			if absf(laengs - 8000.0) < 1.0:
				hinten = breite
			if absf(laengs - float(K["ADLERHORST_LAENGS"])) < 1.0:
				am_platz = breite
			if laengs >= 500.0 and laengs <= 9500.0 and fmod(laengs, 500.0) < 1.0:
				summe += breite
				nmit += 1
			var balken := "=".repeat(int(breite / 60.0))
			var mark := "  <- ADLERHORST" if absf(laengs - float(K["ADLERHORST_LAENGS"])) < 1.0 else ""
			print("  %5.0f m  Boden %5.0f m (links %4.0f / rechts %4.0f)  %s%s"
				% [laengs, breite, seiten[1], seiten[0], balken, mark])
		print("  vorn (bis 3000 m) bis %.0f m, bei 8000 m %.0f m -> Verjuengung %.2f : 1"
			% [vorn, hinten, vorn / maxf(hinten, 1.0)])
		print("  am Platz (8800 m): %.0f m" % am_platz)
		print("  Mittel 500..9500 m: %.0f m  (Urzustand rund 1350 m — hoeher heisst: das Tal"
			% (summe / maxf(float(nmit), 1.0)) + " ist breiter geworden, nicht enger)")
	tw.airfields = af_sichern
	tw.lakes = lk_sichern

	# --- Feiner Querschnitt am Flugplatz -----------------------------------------------
	# Die 400-m-Spalten in _gebirge_check.gd springen von 90 m auf mehrere hundert; ob
	# daneben eine Wand oder eine Boeschung steht, sieht man erst in 100-m-Schritten.
	print("\n=== QUERSCHNITT BEI ADLERHORST (100-m-Schritte, Platz auf 90 m) ===")
	var ah: float = K["ADLERHORST_LAENGS"]
	var mah: Vector2 = start + dir * ah
	for si in 2:
		var vz := 1.0 if si == 0 else -1.0
		var zeile := "  quer %+.0f: " % vz
		for q in range(0, 21):
			var p: Vector2 = mah + quer * vz * float(q) * 100.0
			zeile += "%4d" % int(tw.height_at(p.x, p.y))
		print(zeile)
	print("  (0 bis 2000 m von der Achse)")

	# --- Kammabstand zu Radius --------------------------------------------------------
	print("\n=== MASSIVABSTAND IN DER KETTE (Ziel rund 0.50 * Radius) ===")
	var schlimmst := 0.0
	for seite: float in [1.0, -1.0]:
		var prev := Vector2.ZERO
		var line := "  Seite %+.0f: " % seite
		# Zahl und Abstand der Massive NICHT abtippen — sie sind mit dem Radius zusammen
		# gewandert (2600/1300 -> 2200/1100) und das Werkzeug haette sonst still die
		# falsche Kette vermessen.
		# Der Laengsversatz der einen Kette muss mitgerechnet werden, sonst misst das
		# Werkzeug Positionen, die so gar nicht gebaut werden.
		var koff: float = 0.0 if seite > 0.0 else -float(K["TAL_KETTE_VERSATZ"])
		for i in int(ceil(laenge / kette_d)):
			var laengs := float(i) * kette_d + koff
			var p: Vector2 = start + dir * laengs + quer * seite * main._tal_halbbreite(laengs)
			if i > 0:
				var v := p.distance_to(prev) / kette_r
				schlimmst = maxf(schlimmst, v)
				line += "%.3f " % v
			prev = p
		print(line)
	print("  groesstes Verhaeltnis %.3f (ueber 0.70 zerfaellt die Kette)" % schlimmst)

	# --- Kueste: ragt der Bergfuss ins Meer? -------------------------------------------
	print("\n=== KUESTE IM NORDWESTEN (Land ueber dem Meeresspiegel, je Radius) ===")
	for radius: float in [14000.0, 15000.0, 16000.0, 17000.0, 18000.0]:
		var land := 0
		var n := 0
		var hmax := -9e9
		for g in range(150, 241):     # Sektor, in dem das Hochtal liegt
			var a := deg_to_rad(float(g))
			var h := tw.height_at(cos(a) * radius, sin(a) * radius)
			n += 1
			if h > TerrainWorld.SEA_Y:
				land += 1
			hmax = maxf(hmax, h)
		print("  %5.0f m: %d von %d Proben ueber Wasser, hoechste %.0f m" % [radius, land, n, hmax])

	# --- Aufsicht ----------------------------------------------------------------------
	# Die Schraegrender aus _terrain_render.gd verjuengen ALLES, auch einen exakt
	# parallelen Kanal — an ihnen laesst sich die Keilform nicht beurteilen. Diese
	# Aufsicht ist in TALKOORDINATEN gezeichnet (waagerecht = quer, senkrecht = laengs),
	# eine echte Verjuengung ist darin ein Dreieck.
	var bw := 480
	var bh := 640
	var img := Image.create(bw, bh, false, Image.FORMAT_RGB8)
	for py in bh:
		var laengs := laenge * float(py) / float(bh - 1)
		var m := start + dir * laengs
		for px in bw:
			var q := (float(px) / float(bw - 1) - 0.5) * 9000.0
			var p := m + quer * q
			var h := tw.height_at(p.x, p.y)
			var c: Color
			if h < TerrainWorld.SEA_Y:
				c = Color(0.15, 0.30, 0.55)
			elif h < SCHWELLE:
				c = Color(0.30, 0.62, 0.28)            # Talboden
			else:
				var t := clampf((h - SCHWELLE) / 1000.0, 0.0, 1.0)
				c = Color(0.45, 0.40, 0.34).lerp(Color(1, 1, 1), t)
			img.set_pixel(px, py, c)
	var ziel := "user://tal_keil_aufsicht.png"
	if OS.get_cmdline_user_args().size() > 0:
		ziel = OS.get_cmdline_user_args()[0]
	img.save_png(ziel)
	print("\nAufsicht -> %s  (%.0f m breit, %.0f m lang, oben = Taleingang)"
		% [ProjectSettings.globalize_path(ziel), 9000.0, laenge])

	quit()
	return true
