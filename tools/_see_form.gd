## FORM DES BERGSEES: ist das Ufer gelappt — oder eine Scheibe?
##
## Die Frage, die man dem Code nicht ansieht: der Seeumriss steht an ZWEI Stellen
## (das Becken in TerrainWorld.height_at, das Wassernetz in _build_lake_water). Was
## der Spieler sieht, ist die Schnittlinie des Wasserspiegels mit dem ECHTEN
## Hoehenfeld — also weder die eine noch die andere Formel allein. Deshalb wird hier
## nicht gerechnet, sondern abgetastet: height_at auf einem feinen Raster, Grenze bei
## SEE_SPIEGEL.
##
## MASSZAHL: Rundheit = Umfang^2 / (4 * PI * Flaeche). Ein exakter Kreis ist 1.0, alles
## Gelappte liegt darueber. Die Zahl ist dimensionslos, ein groesserer See allein macht
## sie also nicht besser — nur mehr Buchten tun das.
##
## WARUM MARCHING SQUARES statt Randzellen zaehlen: ein treppenfoermiger Umfang ist um
## den Faktor 4/PI = 1.27 zu lang, ein Kreis kaeme damit schon auf Rundheit 1.6 und die
## Messung waere wertlos. Die Kontur wird deshalb zwischen den Rasterpunkten linear
## interpoliert.
##
## KALIBRIERT an analytischen Formen mit genau diesem Verfahren, damit man weiss, was eine
## Zahl bedeutet: exakter Kreis 1.000 (Schrittweite 2 bis 8 m), Ellipse 400 x 245 m 1.091,
## zwei verschmolzene Kreise 1.362, drei Lappen mit 30 Prozent Amplitude 1.337, vier
## Lappen 1.619, Kreis mit einem 650 x 110 m langen Arm 1.966. Ueber 1.4 kommt man also
## nicht mit einer Delle, sondern nur mit mehreren echten Buchten oder einem Arm.
##
## SCHRITTWEITE: 2, 4 und 8 m liefern dasselbe Ergebnis (1.109 / 1.104 / 1.102 am
## IST-See), 16 m glaettet die Uferlinie schon weg (1.056). Unter 8 m bleiben.
##
## TUERKISSAUM: der Wasser-Shader faerbt nach Tiefe (shallow_col/mid_col/deep_col). Wie
## breit der tuerkise Rand aussieht, haengt also nur daran, wie weit das Ufer flach
## auslaeuft. Gemessen als Flaeche zwischen Wasserlinie und 2-m-Tiefenlinie, geteilt
## durch den mittleren Umfang der beiden.
##
## NUR DER ZUSAMMENHAENGENDE SEE zaehlt: eine Pfuetze irgendwo sonst im Fenster wuerde
## Flaeche und Umfang verfaelschen. Deshalb Flutfuellung von der Seemitte aus.
##
## DIE 2-M-LINIE WIRD NICHT GEFLUTET, sondern INNERHALB der Seemaske gezaehlt. Das war
## vorher anders und hat falsch gemessen: die Flutfuellung startete auch fuer die 2-m-Linie
## in der RASTERMITTE, und sobald der See dort eine Untiefe hat — bei einem gelappten See
## mit Enge in der Mitte ist das der Normalfall — brach sie sofort ab und das Werkzeug
## meldete "der ganze See ist flacher als 2 m", obwohl die Umrisskarte daneben ein tiefes
## Hauptbecken zeigte. Ein zweiter Startpunkt haette es auch nicht geloest: das Tiefwasser
## darf aus mehreren getrennten Becken bestehen. Die Masszahl selbst ist unveraendert.
##
## Godot --headless --path . --script res://tools/_see_form.gd -- [schritt=4] [fenster=2.5]
extends SceneTree
var f := 0

const SAUM_TIEFE := 2.0          # Grenze, bis zu der der Shader "flach" faerbt


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var schritt := 4.0
	var fenster := 2.5           # Halbe Fensterbreite in Vielfachen von SEE_R
	for a in OS.get_cmdline_user_args():
		if a.begins_with("schritt="):
			schritt = float(a.substr(8))
		elif a.begins_with("fenster="):
			fenster = float(a.substr(8))

	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	# Konstanten aus dem Skript von Main holen statt sie hier zu wiederholen — sonst misst
	# das Werkzeug irgendwann einen anderen See, als das Spiel baut.
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var mitte: Vector2 = start + dir * float(K["SEE_LAENGS"])
	var see_r: float = K["SEE_R"]
	var spiegel: float = K["SEE_SPIEGEL"]

	# --- Hoehenfeld abtasten -----------------------------------------------------------
	var n := int(see_r * fenster / schritt)
	var w := 2 * n + 1
	# feld = Wassertiefe: positiv = unter dem Spiegel = Wasser.
	var feld := PackedFloat32Array()
	feld.resize(w * w)
	for j in w:
		var z := mitte.y + float(j - n) * schritt
		for i in w:
			var x := mitte.x + float(i - n) * schritt
			feld[j * w + i] = spiegel - tw.height_at(x, z)
	print("BERGSEE bei (%.0f / %.0f), Spiegel %.0f m — Raster %d x %d, Schritt %.1f m"
		% [mitte.x, mitte.y, spiegel, w, w, schritt])

	# --- Wasserlinie und 2-m-Linie messen ----------------------------------------------
	var wl := _messen(feld, w, 0.0, schritt)
	if float(wl["flaeche"]) <= 0.0:
		print("  KEIN Wasser an der Seemitte gefunden — Becken oder Spiegel passen nicht.")
		quit(); return true
	var tl := _messen(feld, w, SAUM_TIEFE, schritt, wl["maske"])

	var a0: float = wl["flaeche"]
	var p0: float = wl["umfang"]
	var rundheit := p0 * p0 / (4.0 * PI * a0)
	print("\n=== UFERLINIE (Grenze bei Spiegel %.0f m) ===" % spiegel)
	print("  Flaeche %.0f m2  (Kreis gleicher Flaeche haette Radius %.0f m)"
		% [a0, sqrt(a0 / PI)])
	print("  Umfang  %.0f m   (Kreis gleicher Flaeche haette Umfang %.0f m)"
		% [p0, TAU * sqrt(a0 / PI)])
	print("  RUNDHEIT %.3f     (Kreis = 1.000, Ziel > 1.400)" % rundheit)

	var a2: float = tl["flaeche"]
	var p2: float = tl["umfang"]
	print("\n=== TUERKISSAUM (weniger als %.0f m Wassertiefe) ===" % SAUM_TIEFE)
	if a2 <= 0.0:
		print("  Der ganze See ist flacher als %.0f m — kein tiefes Zentrum." % SAUM_TIEFE)
	else:
		var saum := (a0 - a2) / maxf((p0 + p2) * 0.5, 1.0)
		print("  Saumflaeche %.0f m2, mittlere Saumbreite %.1f m" % [a0 - a2, saum])
		print("  Tiefwasser (ueber %.0f m) %.0f m2 = %.0f Prozent der Seeflaeche"
			% [SAUM_TIEFE, a2, 100.0 * a2 / a0])

	# --- Tiefe und Ausdehnung ----------------------------------------------------------
	var maske: PackedByteArray = wl["maske"]
	var tmax := 0.0
	var imin := w
	var imax := -1
	var jmin := w
	var jmax := -1
	for j in w:
		for i in w:
			if maske[j * w + i] == 0:
				continue
			tmax = maxf(tmax, feld[j * w + i])
			imin = mini(imin, i); imax = maxi(imax, i)
			jmin = mini(jmin, j); jmax = maxi(jmax, j)
	print("\n  groesste Tiefe %.1f m, Ausdehnung %.0f x %.0f m (Ost-West x Nord-Sued)"
		% [tmax, float(imax - imin) * schritt, float(jmax - jmin) * schritt])

	# --- Umriss als Bild ---------------------------------------------------------------
	# Ohne Bild sagt eine Rundheit von 1.05 nichts darueber, WO die Form fehlt.
	print("\n=== UMRISS  ('#' tiefer als %.0f m, '+' Untiefe, '.' Land) ===" % SAUM_TIEFE)
	var zeilen := 34
	var spalten := 78
	for r in zeilen:
		var j := int(float(r) * float(w - 1) / float(zeilen - 1))
		var zeile := "  "
		for c in spalten:
			var i := int(float(c) * float(w - 1) / float(spalten - 1))
			var t := feld[j * w + i]
			if maske[j * w + i] == 0:
				zeile += "."
			elif t >= SAUM_TIEFE:
				zeile += "#"
			else:
				zeile += "+"
		print(zeile)
	quit()
	return true


## Flutfuellung ab der Rastermitte + Marching Squares auf der Hoehe L.
## Rueckgabe: {flaeche, umfang, maske}. maske ist 1 fuer Zellen des zusammenhaengenden
## Sees — alles andere zaehlt nicht mit, auch wenn es unter dem Spiegel liegt.
## Mit "innen" wird NICHT geflutet: dann zaehlt jede Zelle dieser Maske, die tiefer als L
## liegt. So wird die 2-m-Linie gemessen (Begruendung im Kopfkommentar).
func _messen(feld: PackedFloat32Array, w: int, L: float, schritt: float,
		innen: Variant = null) -> Dictionary:
	var n := (w - 1) / 2
	var maske := PackedByteArray()
	maske.resize(w * w)
	if innen != null:
		var iv: PackedByteArray = innen
		for k in w * w:
			if iv[k] == 1 and feld[k] > L:
				maske[k] = 1
	else:
		var start := n * w + n
		if feld[start] <= L:
			return {"flaeche": 0.0, "umfang": 0.0, "maske": maske}
		var stapel: Array[int] = [start]
		maske[start] = 1
		while not stapel.is_empty():
			var k: int = stapel.pop_back()
			var i := k % w
			var j := k / w
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var i2 := i + d.x
				var j2 := j + d.y
				if i2 < 0 or i2 >= w or j2 < 0 or j2 >= w:
					continue
				var k2 := j2 * w + i2
				if maske[k2] == 1 or feld[k2] <= L:
					continue
				maske[k2] = 1
				stapel.append(k2)
	# Alles ausserhalb der Maske auf "weit unter L" setzen, damit Marching Squares nur die
	# eine Uferlinie sieht und nicht die einer Pfuetze am Fensterrand.
	var g := PackedFloat32Array()
	g.resize(w * w)
	for k in w * w:
		g[k] = feld[k] if maske[k] == 1 else L - 1000.0

	# Flaeche: je Zelle der Anteil der Ecken ueber L. Das passt zur interpolierten Kontur
	# und ist nicht auf ganze Zellen gerundet.
	var flaeche := 0.0
	var umfang := 0.0
	var zelle := schritt * schritt
	# Kantenpaare je Fall. Kanten: 0 unten, 1 rechts, 2 oben, 3 links.
	# Die Faelle 5 und 10 sind mehrdeutig (zwei Ecken ueber Kreuz) und werden weiter unten
	# ueber den Mittelwert der vier Ecken aufgeloest.
	var tab := [[], [[3, 0]], [[0, 1]], [[3, 1]], [[1, 2]], [], [[0, 2]], [[3, 2]],
		[[2, 3]], [[0, 2]], [], [[1, 2]], [[3, 1]], [[0, 1]], [[3, 0]], []]
	for j in w - 1:
		for i in w - 1:
			var f00 := g[j * w + i]
			var f10 := g[j * w + i + 1]
			var f11 := g[(j + 1) * w + i + 1]
			var f01 := g[(j + 1) * w + i]
			var b := 0
			if f00 > L: b |= 1
			if f10 > L: b |= 2
			if f11 > L: b |= 4
			if f01 > L: b |= 8
			flaeche += zelle * float((b & 1) + ((b >> 1) & 1) + ((b >> 2) & 1)
				+ ((b >> 3) & 1)) * 0.25
			if b == 0 or b == 15:
				continue
			var paare: Array = tab[b]
			if b == 5 or b == 10:
				var zentrum := (f00 + f10 + f11 + f01) * 0.25
				var verbunden := zentrum > L
				if (b == 5) == verbunden:
					paare = [[0, 1], [2, 3]]
				else:
					paare = [[3, 0], [1, 2]]
			# Schnittpunkte auf den vier Kanten (nur die gebrauchten werden benutzt).
			var pt := [
				Vector2(float(i) + _t(f00, f10, L), float(j)),
				Vector2(float(i + 1), float(j) + _t(f10, f11, L)),
				Vector2(float(i + 1) - _t(f11, f01, L), float(j + 1)),
				Vector2(float(i), float(j + 1) - _t(f01, f00, L))]
			for pr: Array in paare:
				umfang += (pt[int(pr[0])] - pt[int(pr[1])]).length() * schritt
	return {"flaeche": flaeche, "umfang": umfang, "maske": maske}


## Anteil auf einer Rasterkante, an dem der Wert L erreicht wird (0 .. 1).
func _t(a: float, b: float, L: float) -> float:
	if is_equal_approx(a, b):
		return 0.5
	return clampf((L - a) / (b - a), 0.0, 1.0)
