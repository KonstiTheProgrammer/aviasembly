## AUSSENFLUCHT UND FLAECHENHAUSHALT DES FELSENTORS.
##
## _tor_form.gd beantwortet die harten Bedingungen (Beinverhaeltnis, Fels ueber dem
## Scheitel, lichte Weite). Dieses Werkzeug beantwortet die andere Frage, an der die
## vorige Runde gescheitert ist: liest sich der Fels als EIN Koerper oder als TREPPE AUS
## GESTAPELTEN PLATTEN? Dafuer misst es zwei Dinge, beide direkt an der Geometrie und
## damit unabhaengig von Kamera, Sonnenstand und Bildausschnitt:
##
## 1. DIE AUSSENKANTE JE HOEHENZEILE. Die Silhouette wird wie in _tor_form.gd gerastert;
##    je Zeile ist die Aussenkante des dicken Beins das groesste belegte x, die des
##    duennen das kleinste. Daraus:
##      * Richtungswechsel: wie oft kehrt die Kante ihre Bewegungsrichtung um. Eine
##        analytische Rampe mit lauter gleichsinnigen Stufen hat fast keine, ein
##        gewachsener Fels viele. Die Kritik hat das im Bild gemessen: unsere Fassung 19
##        Wechsel auf 310 Bildzeilen, das Referenzbild 103.
##      * Stufenhoehen: wie viele Zeilen die Kante still steht, bevor sie springt, und wie
##        weit sie dann springt. Ziel sind 6 bis 8 ECHTE Absaetze, nicht 25 Trittstufen.
##      * ausgeglichene Bilanz: Summe der Spruenge nach aussen gegen Summe nach innen. Die
##        vorige Fassung konnte konstruktiv nur nach innen (unbegrenzter Ruecksprung gegen
##        gedeckelten Vorsprung), das Verhaeltnis lag entsprechend schief.
##
## 2. DER SICHTBARE FLAECHENHAUSHALT aus der Anflugkamera (tools/_terrain_render.gd, Pose
##    tal_tor_nah, 150 m hoch bei einem 690 m hohen Tor — man sieht das Ding also fast ganz
##    von UNTEN). Anteil der sichtbaren, zur Kamera projizierten Flaeche, die waagerecht
##    liegt (|ny| > 0.80), getrennt nach oben und nach UNTEN zeigend.
##
##    WARUM SICHTBAR UND NICHT EINFACH ALLE DREIECKE: das Tor besteht aus Quadern. Ein
##    Quader hat immer rund ein Drittel seiner Flaeche waagerecht, egal wie buendig er
##    sitzt — die rohe Bilanz meldet deshalb IMMER 33/33/34 und sagt nichts. Entscheidend
##    ist, ob die Deck- und Bodenflaeche vom Nachbarquader verdeckt wird. Deshalb ein
##    Strahl von jedem Dreiecksmittelpunkt zur Kamera gegen alle anderen Dreiecke.
##
##    Jede sichtbare nach UNTEN zeigende Flaeche ist im Bild eine schwebende
##    Plattenunterseite — genau das, was die Kritik als "Treppe aus gestapelten Platten"
##    beschrieben hat. Bei einer Felswand geht dieser Anteil gegen null.
##
## Die Halde zaehlt NICHT mit: sie haengt als eigener Knoten "Torhalde" neben dem Tor und
## besteht naturgemaess aus liegenden Flaechen (Felsdecke auf dem Hang).
##
## Godot --headless --path . --script res://tools/_tor_flucht.gd -- [schritt=2] [sicht=1]
## sicht=0 laesst den Sichtbarkeitsteil weg. Er kostet mehrere Minuten (ein Strahl je
## Dreieck gegen alle anderen) und ist die einzige teure Stelle; die Kennzahlen der
## Aussenkante kommen in Sekunden.
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 4:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	if f < 8:
		return false                      # fly_world wird erst nach ein paar Frames gefuellt
	var schritt := 2.0
	var sicht := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("schritt="):
			schritt = float(a.substr(8))
		elif a.begins_with("sicht="):
			sicht = a.substr(6) != "0"

	var tor: Node3D = _suchen(root, "Felsentor")
	if tor == null:
		print("Kein Knoten 'Felsentor' gefunden."); quit(); return true

	# --- Dreiecke einsammeln, in Torkoordinaten -----------------------------------------
	var tris: Array[PackedVector3Array] = []
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for mi: MeshInstance3D in _meshes(tor):
		var tf: Transform3D = tor.global_transform.affine_inverse() * mi.global_transform
		var roh: PackedVector3Array = mi.mesh.get_faces()
		for k in range(0, roh.size(), 3):
			var d := PackedVector3Array([tf * roh[k], tf * roh[k + 1], tf * roh[k + 2]])
			tris.append(d)
			for v: Vector3 in d:
				lo = lo.min(Vector2(v.x, v.y)); hi = hi.max(Vector2(v.x, v.y))
	if tris.is_empty():
		print("Das Felsentor hat keine Dreiecke."); quit(); return true

	# --- 2. SICHTBARER FLAECHENHAUSHALT -------------------------------------------------
	# AUSSENRICHTUNG IST -n, NICHT n. Godot zeichnet eine Flaeche, wenn ihre Ecken von der
	# Kamera aus im Uhrzeigersinn stehen; fuer eine solche Reihenfolge zeigt die
	# Rechte-Hand-Normale (p1-p0) x (p2-p0) vom Betrachter WEG. Landmarks._fels_tri richtet
	# die Wicklung genau danach aus. Wer hier n statt -n nimmt, misst konsequent die
	# Rueckseiten und bekommt Zahlen, die nichts mit dem Bild zu tun haben.
	# Kameraposition der Pose tal_tor_nah aus tools/_terrain_render.gd, in Torkoordinaten.
	var kam: Vector3 = tor.global_transform.affine_inverse() * Vector3(-9250.0, 150.0, -4650.0)
	var mitt := PackedVector3Array()
	var norm := PackedVector3Array()
	var flae := PackedFloat32Array()
	var rad := PackedFloat32Array()
	for d: PackedVector3Array in tris:
		var n := (d[1] - d[0]).cross(d[2] - d[0])
		var ar := n.length() * 0.5
		var m := (d[0] + d[1] + d[2]) / 3.0
		mitt.append(m)
		norm.append(-n.normalized() if ar > 0.0 else Vector3.UP)
		flae.append(ar)
		rad.append(maxf((d[0] - m).length(), maxf((d[1] - m).length(), (d[2] - m).length())))
	var a_ges := 0.0
	var a_oben := 0.0
	var a_unten := 0.0
	for k in (tris.size() if sicht else 0):
		if flae[k] <= 0.0:
			continue
		var ri: Vector3 = kam - mitt[k]
		var wg: float = norm[k].dot(ri.normalized())
		if wg <= 0.02:
			continue                       # von der Kamera abgewandt
		if _verdeckt(tris, mitt, rad, k, ri):
			continue
		# Projizierte Flaeche: was das Dreieck im Bild einnimmt, nicht was es in der Welt
		# misst. Eine steil stehende Wand ist im Anflug schmal, eine waagerechte Platte
		# breit — genau darum geht es hier.
		var pa: float = flae[k] * wg
		a_ges += pa
		if norm[k].y > 0.80:
			a_oben += pa
		elif norm[k].y < -0.80:
			a_unten += pa

	# --- 1. SILHOUETTE RASTERN ----------------------------------------------------------
	var nx := int((hi.x - lo.x) / schritt) + 2
	var ny_ := int((hi.y - lo.y) / schritt) + 2
	var bel := PackedByteArray()
	bel.resize(nx * ny_)
	for d: PackedVector3Array in tris:
		_fuellen(bel, nx, ny_, lo, schritt,
			Vector2(d[0].x, d[0].y), Vector2(d[1].x, d[1].y), Vector2(d[2].x, d[2].y))

	# Aussenkanten je Zeile. Nur Zeilen mitnehmen, in denen ueberhaupt Fels steht.
	var y_re := PackedFloat32Array()          # groesstes belegtes x  (dickes Bein)
	var y_li := PackedFloat32Array()          # kleinstes belegtes x  (duennes Bein)
	var y_h := PackedFloat32Array()
	for j in ny_:
		var a := -1
		var b := -1
		for i in nx:
			if bel[j * nx + i] != 0:
				if a < 0:
					a = i
				b = i
		if a < 0:
			continue
		y_li.append(lo.x + float(a) * schritt)
		y_re.append(lo.x + float(b) * schritt)
		y_h.append(lo.y + float(j) * schritt)

	print("FELSENTOR — Aussenflucht und Flaechenhaushalt")
	print("  %d Dreiecke, Silhouette %.0f x %.0f m, Raster %.0f m" %
		[tris.size(), hi.x - lo.x, hi.y - lo.y, schritt])
	print("")
	print("=== SICHTBARE FLAECHE aus der Pose tal_tor_nah (Kamera 150 m, Tor 690 m hoch) ===")
	if not sicht or a_ges <= 0.0:
		print("  uebersprungen (sicht=0)")
	else:
		print("  waagerecht nach OBEN : %5.1f %% der sichtbaren Bildflaeche"
			% [100.0 * a_oben / a_ges])
		print("  waagerecht nach UNTEN: %5.1f %%   <- schwebende Plattenunterseiten"
			% [100.0 * a_unten / a_ges])
		print("  steil (Rest)         : %5.1f %%"
			% [100.0 * (a_ges - a_oben - a_unten) / a_ges])
	print("")
	print("=== AUSSENKANTE JE HOEHENZEILE ===")
	_kante("dickes Bein (max x)", y_re, y_h, 1.0)
	_kante("duennes Bein (min x)", y_li, y_h, -1.0)
	quit()
	return true


## Kennzahlen einer Aussenkante. richtung = +1, wenn "nach aussen" das groessere x ist.
func _kante(name: String, xs: PackedFloat32Array, hs: PackedFloat32Array,
		richtung: float) -> void:
	var n := xs.size()
	if n < 8:
		print("  %s: zu wenige Zeilen." % name); return
	# Richtungswechsel: eine Zeile zaehlt nur, wenn sie sich um mehr als 1 m bewegt —
	# sonst zaehlt man das Rastern selbst als Zacken.
	var wechsel := 0
	var vor := 0.0
	var spruenge: Array[float] = []
	var halt: Array[int] = []
	var stand := 0
	var raus := 0.0
	var rein := 0.0
	for i in range(1, n):
		var d: float = xs[i] - xs[i - 1]
		if absf(d) <= 1.0:
			stand += 1
			continue
		if stand > 0:
			halt.append(stand)
		stand = 0
		spruenge.append(absf(d))
		if d * richtung > 0.0:
			raus += absf(d)
		else:
			rein += absf(d)
		if vor != 0.0 and signf(d) != signf(vor):
			wechsel += 1
		vor = d
	var mit_spr := 0.0
	for s: float in spruenge:
		mit_spr += s
	mit_spr = mit_spr / maxf(1.0, float(spruenge.size()))
	var mit_halt := 0.0
	for s: int in halt:
		mit_halt += float(s)
	mit_halt = mit_halt / maxf(1.0, float(halt.size()))
	# Streuung um den eigenen Gleitschnitt ueber 21 Zeilen: misst, wie weit die Kante von
	# ihrer eigenen Sollkurve abweicht. Eine analytische Rampe liegt praktisch darauf.
	var abw := 0.0
	for i in n:
		var s := 0.0
		var c := 0
		for k in range(maxi(0, i - 10), mini(n, i + 11)):
			s += xs[k]; c += 1
		abw += pow(xs[i] - s / float(c), 2.0)
	abw = sqrt(abw / float(n))
	print("  %s ueber %d Zeilen (%.0f .. %.0f m):" % [name, n, hs[0], hs[n - 1]])
	print("    Richtungswechsel %d,  Spruenge %d (Mittel %.0f m),  Stufenhoehe %.0f Zeilen"
		% [wechsel, spruenge.size(), mit_spr, mit_halt])
	print("    Bilanz: %.0f m nach aussen gegen %.0f m nach innen  (Verhaeltnis %.2f)"
		% [raus, rein, raus / maxf(1.0, rein)])
	print("    Streuung um den eigenen Gleitschnitt: %.1f m" % [abw])


## Liegt zwischen dem Mittelpunkt von Dreieck k und der Kamera ein anderes Dreieck?
## Moeller-Trumbore gegen alle; die Umkugel je Dreieck siebt die weit entfernten vorher aus,
## sonst laeuft das quadratisch ueber 3000 Dreiecke ins Minutenfeld.
func _verdeckt(tris: Array[PackedVector3Array], mitt: PackedVector3Array,
		rad: PackedFloat32Array, k: int, ri: Vector3) -> bool:
	var o: Vector3 = mitt[k] + ri.normalized() * 0.05     # knapp von der eigenen Flaeche weg
	var laenge := ri.length()
	var d := ri / laenge
	for j in tris.size():
		if j == k:
			continue
		# Abstand des Dreiecksmittelpunkts von der Strahlgeraden gegen seinen Umkreis.
		var v: Vector3 = mitt[j] - o
		var s := v.dot(d)
		if s < 0.0 or s > laenge:
			continue
		if (v - d * s).length_squared() > rad[j] * rad[j]:
			continue
		var t: PackedVector3Array = tris[j]
		var e1 := t[1] - t[0]
		var e2 := t[2] - t[0]
		var p := d.cross(e2)
		var det := e1.dot(p)
		if absf(det) < 1e-9:
			continue
		var inv := 1.0 / det
		var tv := o - t[0]
		var u := tv.dot(p) * inv
		if u < 0.0 or u > 1.0:
			continue
		var q := tv.cross(e1)
		var vv := d.dot(q) * inv
		if vv < 0.0 or u + vv > 1.0:
			continue
		var tt := e2.dot(q) * inv
		if tt > 0.02 and tt < laenge:
			return true
	return false


func _fuellen(bel: PackedByteArray, nx: int, ny_: int, lo: Vector2, s: float,
		a: Vector2, b: Vector2, c: Vector2) -> void:
	var j0 := int(floor((minf(a.y, minf(b.y, c.y)) - lo.y) / s))
	var j1 := int(ceil((maxf(a.y, maxf(b.y, c.y)) - lo.y) / s))
	for j in range(maxi(0, j0), mini(ny_, j1 + 1)):
		var yy := lo.y + float(j) * s
		var xs := PackedFloat32Array()
		for e: Array in [[a, b], [b, c], [c, a]]:
			var p: Vector2 = e[0]
			var q: Vector2 = e[1]
			if (p.y <= yy and q.y > yy) or (q.y <= yy and p.y > yy):
				xs.append(p.x + (q.x - p.x) * (yy - p.y) / (q.y - p.y))
		if xs.size() < 2:
			continue
		xs.sort()
		var i0 := int(floor((xs[0] - lo.x) / s))
		var i1 := int(ceil((xs[xs.size() - 1] - lo.x) / s))
		for i in range(maxi(0, i0), mini(nx, i1 + 1)):
			bel[j * nx + i] = 1


func _suchen(n: Node, name: String) -> Node3D:
	if n.name == name and n is Node3D:
		return n
	for k: Node in n.get_children():
		var r := _suchen(k, name)
		if r != null:
			return r
	return null


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for k: Node in n.get_children():
		out.append_array(_meshes(k))
	return out
