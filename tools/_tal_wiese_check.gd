## IST DER TALBODEN GRUEN — und was liegt sonst noch unter der Felsfarbe?
##
## Ergaenzt tools/_krit_seering.gd (das misst die Gruenbreite in 24 Richtungen um den See).
## Hier wird der GANZE Talkorridor abgetastet, denn die Almwiese haengt seit dem Umbau nicht
## mehr am See, sondern an der Lage im Tal (TerrainWorld._tal_wiese).
##
## Drei Fragen, jede mit einer Zahl:
##   1. Traegt irgendein Punkt im Korridor UNTER dem Seespiegel Felsfarbe? Das war der
##      Kernbefund der Kritik (Gelaende auf 71 m, 7 m unter dem Spiegel, in Geroellbraun).
##   2. Wie hoch ueber dem Talboden reicht das Gruen? Die Antwort soll aus dem GELAENDE
##      kommen (Wandfuss), nicht aus einem gemalten Radius.
##   3. Welches BIOM liegt im Talboden? Solange der Fels darueber lag, war das egal; jetzt
##      scheint _boden_farbe durch, und eine Wuestenzunge im Hochtal waere sofort sichtbar.
##
## Die Farbe kommt aus TerrainWorld._face_color, nicht aus einer nachgebauten Formel — sonst
## misst man etwas anderes, als das Netz faerbt. Die Normale wird ueber 8 m gebildet, also
## mit der Netzweite, mit der auch _tri die Steilheit sieht.
##
## DAS GRUENKRITERIUM IST STRENG (g > r + 0.03 und g > b) und schlaegt auch bei Bodenfarben
## an, die keineswegs Fels sind: der "seltene erdige Fleck" der Wiese (0.50/0.52/0.40) hat
## nur 0.02 Vorsprung und zaehlt hier als NICHT gruen. Wer die Restmeldungen liest, muss
## also die ausgegebene Farbe ansehen und nicht nur die Zahl — Fels ist im fraglichen
## Hoehenband an r > g zu erkennen (0.45/0.41/0.36 und aufwaerts).
##
## godot --headless --path . --script res://tools/_tal_wiese_check.gd
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var quer := Vector2(dir.y, -dir.x)
	var lg: float = K["TAL_LAENGE"]
	var spiegel: float = K["SEE_SPIEGEL"]

	# REIHENFOLGE WIE IN TerrainWorld.Biome — HOCHLAND steht dort mit drin, auch wenn
	# biome_at es nie zurueckgibt. Ohne den Platzhalter lief der Zaehler aus dem Feld.
	var namen := ["WALD", "WUESTE", "HOCHLAND", "HEIDE"]
	var biom_zaehler := [0, 0, 0, 0]
	var unter_spiegel := 0
	var unter_spiegel_fels := 0
	var unter_spiegel_ungruen := 0
	var schlimmster := Vector3.ZERO
	var schlimmster_c := Color.BLACK
	print("laengs |  Talboden | Gruen bis (Hoehe) | ueber Boden | Biom im Boden")
	for i in 24:
		var l := lg * float(i) / 23.0
		var mitte := start + dir * l
		var boden: float = tw.height_at(mitte.x, mitte.y)
		var gruen_max := -1.0e9
		var boden_min := 1.0e9
		# Querprofil in 2-m-Schritten bis 1400 m auf beiden Seiten
		for s: float in [-1.0, 1.0]:
			var q := 0.0
			while q < 1400.0:
				q += 20.0
				var p: Vector2 = mitte + quer * (q * s)
				var h: float = tw.height_at(p.x, p.y)
				boden_min = minf(boden_min, h)
				var c := _farbe(tw, p)
				var ist_gruen := c.g > c.r + 0.03 and c.g > c.b
				if q < 700.0:
					biom_zaehler[tw.biome_at(p.x, p.y)] += 1
				if h < spiegel and h > -5.0:
					unter_spiegel += 1
					if not ist_gruen:
						unter_spiegel_ungruen += 1
					# FELS von SAND unterscheiden — die Kritik zielt auf Geroell, nicht auf
					# jede nicht-gruene Flaeche. Der Fels dieser Palette ist entsaettigt
					# (0.35/0.31/0.27 bis 0.56/0.52/0.46, Spanne r-b unter 0.10), der
					# Wuestenboden dagegen warm (0.91/0.82/0.58, Spanne 0.33) und der erdige
					# Wiesenfleck hat g ueber r. Deshalb: r >= g UND r - b < 0.16.
					if c.r >= c.g and c.r - c.b < 0.16:
						unter_spiegel_fels += 1
						if h < schlimmster.y or schlimmster == Vector3.ZERO:
							schlimmster = Vector3(p.x, h, p.y)
							schlimmster_c = c
				if ist_gruen:
					gruen_max = maxf(gruen_max, h)
		var tb := minf(boden, boden_min)
		if gruen_max < -1.0e8:
			print("%6.0f | %6.0f m  |   KEIN GRUEN      |             | %s"
				% [l, tb, _biom_text(tw, mitte, namen)])
		else:
			print("%6.0f | %6.0f m  | %10.0f m      | %7.0f m   | %s"
				% [l, tb, gruen_max, gruen_max - tb, _biom_text(tw, mitte, namen)])
	var gesamt: int = biom_zaehler[0] + biom_zaehler[1] + biom_zaehler[2] + biom_zaehler[3]
	print("\nBIOM im Talboden (+-700 m um die Achse): WALD %.0f %%, WUESTE %.0f %%, HEIDE %.0f %%"
		% [100.0 * biom_zaehler[0] / gesamt, 100.0 * biom_zaehler[1] / gesamt,
			100.0 * biom_zaehler[3] / gesamt])
	print("UNTER DEM SPIEGEL (%.0f m) im Korridor: %d Proben, davon nicht gruen %d, FELS %d"
		% [spiegel, unter_spiegel, unter_spiegel_ungruen, unter_spiegel_fels])
	if unter_spiegel_fels > 0:
		print("  tiefste davon (%.0f / %.0f) auf %.0f m, Farbe %.2f/%.2f/%.2f"
			% [schlimmster.x, schlimmster.z, schlimmster.y,
				schlimmster_c.r, schlimmster_c.g, schlimmster_c.b])
	quit()
	return true


func _biom_text(tw: TerrainWorld, p: Vector2, namen: Array) -> String:
	return namen[tw.biome_at(p.x, p.y)]


func _farbe(tw: TerrainWorld, p: Vector2) -> Color:
	var e := 8.0
	var hx := tw.height_at(p.x + e, p.y) - tw.height_at(p.x - e, p.y)
	var hz := tw.height_at(p.x, p.y + e) - tw.height_at(p.x, p.y - e)
	var n := Vector3(-hx, 2.0 * e, -hz).normalized()
	return tw._face_color(Vector3(p.x, tw.height_at(p.x, p.y), p.y), absf(n.y))
