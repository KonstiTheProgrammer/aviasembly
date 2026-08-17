## FORM DES FELSENTORS: gewachsene Rippe mit Loch — oder freistehender Reifen?
##
## _tor_check.gd fragt, OB man durchpasst und ob die Kollision traegt. Hier geht es um die
## Gestalt: wie dick sind die beiden Beine, wie gross ist die Oeffnung, und steht ueber dem
## Bogenscheitel noch Fels? Das letzte ist das Unterscheidungsmerkmal — ein durchgewittertes
## Loch sitzt IN einer Felsrippe, die oben und seitlich weiterlaeuft; ein Reifen hat ueber
## sich nur Himmel.
##
## GEMESSEN WIRD DIE SILHOUETTE, die man beim Anflug laengs der Talachse sieht: alle
## Dreiecke des Tors werden auf die Torebene projiziert und dort ausgefuellt. Zwei
## Belegungen laufen nebeneinander:
##   MESH = nur die Geometrie aus Landmarks.build_felsentor
##   VOLL = Mesh ODER Gelaende (height_at quer zur Talachse, ueber die Tortiefe gemaxt)
## Die BEINDICKE kommt aus MESH. Grund: sie ist das, was build_felsentor steuert, und ein
## Bein, das seitlich in den Hang uebergeht, haette in VOLL gar keine endliche Dicke mehr.
## Oeffnung und Scheiteldecke dagegen aus VOLL — dem Spieler ist egal, ob das, was ihm im
## Weg steht, Mesh oder Gelaende ist.
##
## WARUM SILHOUETTE UND NICHT EIN EBENENSCHNITT durch die Tormitte: das Bogenband ist ein
## an beiden Enden OFFENES Rohr (build_felsentor loftet Ringe, ohne die Endringe zu
## schliessen). Der Ebenenschnitt eines offenen Rohrs ist keine geschlossene Kurve; die
## Paritaetsfuellung verbindet dann die losen Enden des linken mit denen des rechten Beins.
## Gemessen kam so ein 434 m breiter Felsriegel bei 0 bis 58 m heraus, der in der Geometrie
## nicht existiert. Die Projektion hat das Problem nicht: sie fuellt jedes Dreieck fuer
## sich, Ueberlappung schadet nicht, offene Raender auch nicht.
##
## ACHSEN: build_felsentor setzt rotation.y = atan2(TAL_RICHTUNG.x, TAL_RICHTUNG.y).
## Lokales +Z zeigt damit laengs des Tals, lokales +X quer dazu — also laengs der
## Spannweite. y = 0 ist die Fusslinie (Gelaendehoehe an der Torposition).
##
## Godot --headless --path . --script res://tools/_tor_form.gd -- [schritt=2]
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 4:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	if f < 8:
		return false      # fly_world wird erst nach ein paar Frames bestueckt
	var schritt := 2.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("schritt="):
			schritt = float(a.substr(8))

	var tw: TerrainWorld = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var p: Vector2 = start + dir * float(K["TOR_LAENGS"])
	var quer := Vector2(dir.y, -dir.x)             # lokales +X in Weltkoordinaten
	var fuss := tw.height_at(p.x, p.y)

	var tor: Node3D = _suchen(root, "Felsentor")
	if tor == null:
		print("Kein Knoten 'Felsentor' gefunden."); quit(); return true

	# --- Dreiecke des Tors in Torkoordinaten sammeln ------------------------------------
	var tris: Array[PackedVector2Array] = []       # je Dreieck (x, y), z faellt weg
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var ztief := 0.0
	for mi: MeshInstance3D in _meshes(tor):
		var t: Transform3D = tor.global_transform.affine_inverse() * mi.global_transform
		var roh: PackedVector3Array = mi.mesh.get_faces()
		for k in range(0, roh.size(), 3):
			var a := t * roh[k]
			var b := t * roh[k + 1]
			var c := t * roh[k + 2]
			var d := PackedVector2Array([Vector2(a.x, a.y), Vector2(b.x, b.y),
				Vector2(c.x, c.y)])
			tris.append(d)
			for v: Vector2 in d:
				lo = lo.min(v); hi = hi.max(v)
			ztief = maxf(ztief, maxf(absf(a.z), maxf(absf(b.z), absf(c.z))))
	if tris.is_empty():
		print("Das Felsentor hat keine Dreiecke."); quit(); return true
	var bogen_h := hi.y
	print("FELSENTOR bei (%.0f / %.0f), Fusslinie %.0f m ueber Null." % [p.x, p.y, fuss])
	print("Silhouette: %.0f m breit, Scheitel %.0f m ueber der Fusslinie, Tortiefe %.0f m."
		% [hi.x - lo.x, bogen_h, ztief * 2.0])

	# --- Raster aufbauen ---------------------------------------------------------------
	var xlo := lo.x - 400.0
	var xhi := hi.x + 400.0
	var spalten := int((xhi - xlo) / schritt) + 1
	var zeilen := int((bogen_h + 200.0) / schritt) + 1
	# Gelaende: je Spalte EIN Wert statt je Rasterpunkt (es haengt nur von x ab). Ueber die
	# Tortiefe gemaxt, damit auch ein Buckel dicht vor oder hinter dem Tor als Sichtsperre
	# zaehlt — die Silhouette des Mesh tut das schliesslich auch.
	var terr := PackedFloat32Array()
	terr.resize(spalten)
	for c in spalten:
		var x := xlo + float(c) * schritt
		var w := p + quer * x
		var h := -1e9
		for s in range(-2, 3):
			var zo := ztief * float(s) * 0.5
			h = maxf(h, tw.height_at(w.x + dir.x * zo, w.y + dir.y * zo))
		terr[c] = h - fuss

	var mesh_b: Array[PackedByteArray] = []
	var voll_b: Array[PackedByteArray] = []
	for r in zeilen:
		var mz := PackedByteArray(); mz.resize(spalten)
		mesh_b.append(mz)
	# Dreiecke zeilenweise rastern: je Dreieck nur die Zeilen anfassen, die es beruehrt.
	for d: PackedVector2Array in tris:
		var ymin := minf(d[0].y, minf(d[1].y, d[2].y))
		var ymax := maxf(d[0].y, maxf(d[1].y, d[2].y))
		var r0 := maxi(0, int(ceil(ymin / schritt)))
		var r1 := mini(zeilen - 1, int(floor(ymax / schritt)))
		for r in range(r0, r1 + 1):
			var y := float(r) * schritt
			var xa := 1e9
			var xb := -1e9
			for e in 3:
				var p0 := d[e]
				var p1 := d[(e + 1) % 3]
				if (p0.y > y) == (p1.y > y):
					continue
				var xx := lerpf(p0.x, p1.x, (y - p0.y) / (p1.y - p0.y))
				xa = minf(xa, xx); xb = maxf(xb, xx)
			if xb < xa:
				continue
			var c0 := maxi(0, int(ceil((xa - xlo) / schritt)))
			var c1 := mini(spalten - 1, int(floor((xb - xlo) / schritt)))
			var zeile: PackedByteArray = mesh_b[r]
			for c in range(c0, c1 + 1):
				zeile[c] = 1
	for r in zeilen:
		var y := float(r) * schritt
		var vz := PackedByteArray(); vz.resize(spalten)
		var mz: PackedByteArray = mesh_b[r]
		for c in spalten:
			vz[c] = 1 if (mz[c] == 1 or terr[c] >= y) else 0
		voll_b.append(vz)

	# --- OEFFNUNG ----------------------------------------------------------------------
	# Breiteste freie Strecke, die auf BEIDEN Seiten von Fels begrenzt ist UND die Talachse
	# enthaelt. Ohne die zweite Bedingung gewinnt irgendeine Luecke zwischen zwei
	# Gelaendebuckeln weit neben dem Tor: gemessen wurden so 468 m Oeffnung mit Mitte bei
	# x = +468 m, also ein "Tor", durch das die Talachse gar nicht laeuft.
	var achse := clampi(int((0.0 - xlo) / schritt), 0, spalten - 1)
	var b_breite := 0.0
	var b_zeile := 0
	var b_mitte := achse
	for r in zeilen:
		var lauf: Array = _loch(voll_b[r], spalten, achse)
		if float(lauf[0]) * schritt > b_breite:
			b_breite = float(lauf[0]) * schritt
			b_zeile = r
			b_mitte = int(lauf[1])
	print("\n=== OEFFNUNG (Mesh + Gelaende) ===")
	var oben := zeilen
	if b_breite <= 0.0:
		print("  Keine beidseits begrenzte Oeffnung auf der Talachse — das Tor hat kein Loch.")
	else:
		print("  lichte BREITE  %.0f m (bei %.0f m ueber der Fusslinie, Mitte x = %+.0f m)"
			% [b_breite, float(b_zeile) * schritt, xlo + float(b_mitte) * schritt])
		var unten := 0
		while unten < zeilen and voll_b[unten][b_mitte] == 1:
			unten += 1                          # Gelaendebuckel unter der Oeffnung
		oben = unten
		while oben < zeilen and voll_b[oben][b_mitte] == 0:
			oben += 1
		print("  lichte HOEHE   %.0f m (frei von %.0f bis %.0f m ueber der Fusslinie)"
			% [float(oben - unten) * schritt, float(unten) * schritt, float(oben) * schritt])

	# --- SCHEITEL ----------------------------------------------------------------------
	# Wie viel Fels steht ueber dem Loch? Beim freistehenden Reifen ist das genau die
	# Banddicke; eine Rippe traegt darueber noch den halben Berg.
	print("\n=== SCHEITEL ===")
	var hoechst := -1e9
	for c in spalten:
		hoechst = maxf(hoechst, terr[c])
	if oben >= zeilen:
		print("  Ueber der Oeffnung steht ueberhaupt kein Fels — kein Bogen, nur ein Spalt.")
	else:
		var decke := 0
		var rr := oben
		while rr < zeilen and voll_b[rr][b_mitte] == 1:
			decke += 1
			rr += 1
		print("  Fels ueber dem Scheitel: %.0f m durchgehend (Unterkante bei %.0f m)"
			% [float(decke) * schritt, float(oben) * schritt])
		print("  darueber wieder freier Himmel: %s"
			% ["JA — freistehender Reifen" if rr < zeilen else "NEIN — geschlossene Rippe"])
		# Laeuft der Fels auf halber Scheitelhoehe seitlich bis zum Rasterrand weiter?
		var pr: int = clampi(oben + decke / 2, 0, zeilen - 1)
		print("  auf Scheitelhoehe seitlich angebunden: links %s, rechts %s"
			% ["ja" if voll_b[pr][0] == 1 else "nein",
			"ja" if voll_b[pr][spalten - 1] == 1 else "nein"])
	print("  hoechstes Gelaende quer zur Torachse: %.0f m ueber der Fusslinie (Scheitel %.0f m)"
		% [hoechst, bogen_h])

	# --- BEINDICKE (nur Mesh) ----------------------------------------------------------
	# Gemessen zwischen 15 und 55 Prozent der Bogenhoehe: darunter sitzen die Fussklotze und
	# die offenen Bandenden, darueber laufen die Beine in den Scheitel zusammen.
	#
	# ZWEI ZAHLEN, und man braucht beide. Die waagerechte Breite ist das, was der Spieler
	# sieht — aber ein Bein, das schraeg steht, erscheint darin um 1/sin(Neigung) breiter,
	# ohne mehr Material zu haben. Die zweite Zahl rechnet das heraus: Breite mal Sinus der
	# oertlichen Bandneigung, also die Dicke SENKRECHT zum Bandverlauf. Weichen die beiden
	# Verhaeltnisse auseinander, ist die Ungleichheit nur perspektivisch.
	print("\n=== BEINE (nur die Geometrie aus build_felsentor) ===")
	var von := int(bogen_h * 0.15 / schritt)
	var bis := mini(int(bogen_h * 0.55 / schritt), zeilen - 1)
	var mit := PackedFloat32Array()      # Mitte je Bein und Zeile, in Metern
	var brt := PackedFloat32Array()      # waagerechte Breite je Bein und Zeile
	# Eigenes Gueltigkeitsfeld: die Mitte des LINKEN Beins ist immer negativ, ein
	# "mit < 0 heisst ungueltig" haette es in jeder Zeile verworfen.
	var gut := PackedByteArray()
	mit.resize((bis - von + 1) * 2)
	brt.resize((bis - von + 1) * 2)
	gut.resize(bis - von + 1)
	for r in range(von, bis + 1):
		var k := (r - von) * 2
		var laeufe: Array = _laeufe(mesh_b[r], spalten)
		if laeufe.size() != 2:
			continue                     # verschmolzen oder aufgefasert: nicht wertbar
		for s in 2:
			var lauf: Array = laeufe[s]
			mit[k + s] = (float(lauf[0]) + float(lauf[1])) * 0.5 * schritt + xlo
			brt[k + s] = float(int(lauf[1]) - int(lauf[0]) + 1) * schritt
		gut[r - von] = 1
	var sum := [0.0, 0.0]
	var sum_s := [0.0, 0.0]
	var anz := 0
	print("  Hoehe    links waag.  senkr.   rechts waag.  senkr.")
	for r in range(von + 1, bis):
		var k := (r - von) * 2
		if gut[r - von] == 0 or gut[r - von - 1] == 0 or gut[r - von + 1] == 0:
			continue
		var z := [0.0, 0.0]
		var zs := [0.0, 0.0]
		for s in 2:
			var dx: float = mit[k + 2 + s] - mit[k - 2 + s]
			var dy := 2.0 * schritt
			z[s] = brt[k + s]
			zs[s] = brt[k + s] * dy / sqrt(dx * dx + dy * dy)
			sum[s] += z[s]
			sum_s[s] += zs[s]
		anz += 1
		if (r - von) % maxi(1, (bis - von) / 8) == 0:
			print("  %5.0f m   %8.1f %8.1f   %8.1f %8.1f"
				% [float(r) * schritt, z[0], zs[0], z[1], zs[1]])
	if anz == 0:
		print("  Keine zwei getrennten Beine gefunden.")
	else:
		var ml: float = sum[0] / float(anz)
		var mr: float = sum[1] / float(anz)
		var sl: float = sum_s[0] / float(anz)
		var sr: float = sum_s[1] / float(anz)
		print("  Mittel ueber %d Hoehen:" % anz)
		print("    waagerecht (Silhouette): links %.1f m, rechts %.1f m" % [ml, mr])
		print("    senkrecht zum Band:      links %.1f m, rechts %.1f m" % [sl, sr])
		print("  VERHAELTNIS dicker/duenner = %.2f  (Silhouette)   (Ziel >= 1.50)"
			% (maxf(ml, mr) / maxf(minf(ml, mr), 0.001)))
		print("  VERHAELTNIS dicker/duenner = %.2f  (echte Banddicke)"
			% (maxf(sl, sr) / maxf(minf(sl, sr), 0.001)))

	# --- Bild --------------------------------------------------------------------------
	# Ohne Bild sagt ein Verhaeltnis von 1.0 nichts darueber, WO die Form fehlt.
	print("\n=== BLICK DURCH DAS TOR  ('#' Mesh, ':' Gelaende, ' ' frei) ===")
	var az := 26
	var asp := 108
	for k in az:
		var r := int(float(az - 1 - k) * float(zeilen - 1) / float(az - 1))
		var zeile := "  "
		for c2 in asp:
			var c := int(float(c2) * float(spalten - 1) / float(asp - 1))
			if mesh_b[r][c] == 1:
				zeile += "#"
			elif voll_b[r][c] == 1:
				zeile += ":"
			else:
				zeile += " "
		print("%s  %4.0f m" % [zeile, float(r) * schritt])
	print("  (Bildbreite %.0f m, x = %+.0f .. %+.0f m quer zur Talachse)"
		% [xhi - xlo, xlo, xhi])
	quit()
	return true


## Zusammenhaengende belegte Abschnitte einer Rasterzeile als [von, bis] (Spaltenindex).
func _laeufe(z: PackedByteArray, n: int) -> Array:
	var out: Array = []
	var c := 0
	while c < n:
		if z[c] == 0:
			c += 1
			continue
		var v := c
		while c < n and z[c] == 1:
			c += 1
		out.append([v, c - 1])
	return out


## Der freie Abschnitt einer Zeile, der die Spalte 'achse' enthaelt — sofern er links UND
## rechts von Fels begrenzt ist. Ein Streifen bis zum Rasterrand ist keine Oeffnung,
## sondern offener Himmel neben dem Tor. Rueckgabe [Breite in Spalten, Mittelspalte].
func _loch(z: PackedByteArray, n: int, achse: int) -> Array:
	if z[achse] == 1:
		return [0, achse]
	var v := achse
	while v > 0 and z[v - 1] == 0:
		v -= 1
	var b := achse
	while b < n - 1 and z[b + 1] == 0:
		b += 1
	if v == 0 or b == n - 1:
		return [0, achse]                 # zur Seite offen: keine Oeffnung
	return [b - v + 1, (v + b) / 2]


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for k in n.get_children():
		out.append_array(_meshes(k))
	return out


func _suchen(n: Node, name_: String) -> Node3D:
	if n.name == name_ and n is Node3D:
		return n
	for k in n.get_children():
		var t := _suchen(k, name_)
		if t != null:
			return t
	return null
