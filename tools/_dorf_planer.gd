## DORF- UND STRASSENPLANER — erzeugt scripts/StrassenDaten.gd.
##
## 1. Tastet die Hauptinsel auf einem 100-m-Raster ab (echtes, gewachsenes Gelaende mit
##    Fluessen, wie im Spiel).
## 2. DOERFER: Standorte auf einem 400-m-Raster bewerten (flach, bewohnbar, nicht im Meer/
##    See/Fluss, nicht am Vulkan/Plateau/Hochhausviertel, Abstand zu vorhandenen Orten und
##    Plaetzen), dann gierig die besten mit Mindestabstand waehlen.
## 3. STRASSEN: Knoten = neue Doerfer + vorhandene Orte + Flugplatz-Vorfelder. Kanten =
##    minimaler Spannbaum ueber die Wegkosten plus Abkuerzungen, die deutlich kuerzer sind
##    als der Umweg durch den Baum (so entstehen Ringe statt nur Aeste). Jede Kante wird per
##    A* auf dem Raster gesucht: Laenge x (1 + (Steigung/4,5 %)^2), ueber 22 % gesperrt,
##    Flussquerung = Brueckenaufschlag, schon gebaute Strassen kosten nur ein Drittel —
##    dadurch buendeln sich Wege zu Staemmen mit Abzweigen statt paralleler Doppelstrassen.
##    Die Stuecke, die ueber schon gebaute Strasse laufen, werden weggelassen.
## 4. Glaetten (Douglas-Peucker 30 m + Chaikin), FLUSSQUERUNGEN RECHTWINKLIG begradigen
##    (_querungen_begradigen) und als GDScript-Konstanten schreiben.
##
##   HOME=<test-home> Godot --headless --path . --script res://tools/_dorf_planer.gd
##
## MODUS "anschluss" (... --script res://tools/_dorf_planer.gd -- anschluss): laesst das
## vorhandene Netz (StrassenDaten) UNVERAENDERT und sucht nur Anschlussstrassen von der
## Hafenstadt (Hafenstadt.anschluesse()) dorthin — derselbe A*, dieselbe Buendelung (was ueber
## schon gebaute Strasse laeuft, entfaellt), dasselbe Glaetten. Schreibt
## scripts/StrassenZusatz.gd; Strassen.strassen_daten() haengt es an. Ein voller Neulauf
## wuerde alle Doerfer und Strassen neu wuerfeln.
extends SceneTree

const Z := 100.0
const X0 := -30000.0
const X1 := 30000.0
const Z0 := -28000.0
const Z1 := 30000.0
const ZIEL := "res://scripts/StrassenDaten.gd"
const N_DOERFER := 20
const DORF_ABSTAND := 3600.0
const ORT_ABSTAND := 2800.0
const MAX_STEIG := 0.30

var m: Node
var f := 0
var t: TerrainWorld
var nx := 0
var nz := 0
var h := PackedFloat32Array()
var sperre := PackedByteArray()     # 1 = gesperrt
var fluss := PackedByteArray()      # 1 = Flussbett (Bruecke)
var strasse := PackedByteArray()    # 1 = schon Strasse
var rauh := PackedFloat32Array()    # steilste 25-m-Steigung in der Zelle (Felsstufen)
var fenster := Rect2()              # Modus "anschluss": nur dieser Ausschnitt wird abgetastet


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
	if f == 8:
		if OS.get_cmdline_user_args().has("anschluss"):
			_anschluss()
		else:
			_planen()
		quit()
	return false


## Das 100-m-Raster: Hoehe, Sperren, Flusstaeler, Rauheit (siehe Kopfkommentar, Schritt 1).
func _raster() -> void:
	nx = int((X1 - X0) / Z)
	nz = int((Z1 - Z0) / Z)
	h.resize(nx * nz)
	sperre.resize(nx * nz)
	fluss.resize(nx * nz)
	strasse.resize(nx * nz)
	rauh.resize(nx * nz)
	var t0 := Time.get_ticks_msec()
	# Sperrzonen: Vulkan, Hochhausviertel, Bahnen
	var kreise := [[Vector2(11800, -5600), 2500.0], [Vector2(2600, -3800), 1100.0]]
	var bahnen: Array = []
	for af in m.airfields:
		var p: Vector3 = af["pos"]
		if absf(p.x) > 34000.0 or absf(p.z) > 34000.0 or String(af["name"]) == "ADLERHORST":
			continue
		bahnen.append([Vector2(p.x, p.z), float(af["heading"])])
	for iz in nz:
		for ix in nx:
			var i := _idx(ix, iz)
			var w := _welt(i)
			# Nur ein Ausschnitt (Modus "anschluss"): alles ausserhalb ist gesperrt
			if fenster.size.x > 0.0 and not fenster.has_point(w):
				sperre[i] = 1
				continue
			var hh := t.height_at(w.x, w.y)
			h[i] = hh
			var sp := 0
			if hh < TerrainWorld.SEA_Y + 1.5 or t.region_at(w.x, w.y) != TerrainWorld.Region.HAUPT:
				sp = 1
			for k in kreise:
				if w.distance_to(k[0]) < float(k[1]):
					sp = 1
			for b in bahnen:
				var lok: Vector2 = (w - (b[0] as Vector2)).rotated(float(b[1]))
				if absf(lok.x) < 70.0 and absf(lok.y) < 520.0:
					sp = 1
			for lk in t.lakes:
				var lp: Vector3 = lk["pos"]
				if w.distance_to(Vector2(lp.x, lp.z)) < float(lk["r"]) * 1.05 + 25.0:
					sp = 1
			if sp == 0 and t._plateau_anteil(w.x, w.y) > 0.25:
				sp = 1
			sperre[i] = sp
			# FLUSSTAL = Brueckenzone: das ganze eingeschnittene Tal (Talband), nicht nur das
			# Wasser. Die Uferhaenge sind steiler als MAX_STEIG — als Sperre zerschnitt der
			# Silberfluss die Insel in West und Ost (196 Kanten ohne Weg).
			var fl: Vector4 = t._fluss_naechst(w.x, w.y)
			if fl.x < maxf(fl.z * 0.5 + 40.0, fl.w * 0.8):
				fluss[i] = 1
			# RAUHEIT: auf 100 m sieht eine Felsstufe wie ein maessiger Hang aus. Die erste
			# Fassung fuehrte die Strasse ins Hochtal ueber eine Wand, die im Spiel einen
			# 282 m tiefen Einschnitt verlangte. Steilste Steigung zwischen 25-m-Proben.
			if sp == 0:
				var st_max := 0.0
				var vorher := hh
				for k in 4:
					var qx := w.x - 37.5 + 25.0 * float(k)
					var hq := t.height_at(qx, w.y)
					if k > 0:
						st_max = maxf(st_max, absf(hq - vorher) / 25.0)
					vorher = hq
				vorher = hh
				for k in 4:
					var qz := w.y - 37.5 + 25.0 * float(k)
					var hq := t.height_at(w.x, qz)
					if k > 0:
						st_max = maxf(st_max, absf(hq - vorher) / 25.0)
					vorher = hq
				rauh[i] = st_max
	print("PLANER Raster %dx%d in %.1f s" % [nx, nz, (Time.get_ticks_msec() - t0) / 1000.0])


func _idx(ix: int, iz: int) -> int:
	return iz * nx + ix


func _welt(i: int) -> Vector2:
	return Vector2(X0 + (float(i % nx) + 0.5) * Z, Z0 + (float(i / nx) + 0.5) * Z)


func _zelle(p: Vector2) -> int:
	var ix := clampi(int((p.x - X0) / Z), 0, nx - 1)
	var iz := clampi(int((p.y - Z0) / Z), 0, nz - 1)
	return _idx(ix, iz)


func _planen() -> void:
	t = m.terrain
	# AUF DEM GELAENDE OHNE DIE EIGENEN DOERFER UND STRASSEN planen: sonst sieht der Planer
	# den vorigen Stand als "vorhandene Orte" und waehlt 20 neue Doerfer daneben.
	# Schuerzen- und Kartenfaden ANHALTEN, bevor Listen des Gelaendes veraendert werden —
	# beide lesen sie nebenlaeufig (sonst Absturz im Kartenfaden, Signal 11).
	m.set("_fern_stopp", true)
	var ft: Thread = m.get("_fern_thread")
	if ft != null and ft.is_started():
		ft.wait_to_finish()
		m.set("_fern_thread", null)
	(m.get("_map_stopp") as Array)[0] = true
	var mt: Thread = m.get("_map_thread")
	if mt != null and mt.is_started():
		mt.wait_to_finish()
		m.set("_map_thread", null)
	t.set("_strassen_an", false)
	var eigene: Dictionary = {}
	for d in StrassenDaten.DOERFER:
		eigene[String(d[0])] = true
	for z in m.get("_dorf_zonen"):
		t.airfields.erase(z)
	t.zonen_gitter_bauen()      # das Flachzonen-Raster haengt an der Liste
	_raster()

	# --- vorhandene Orte und Plaetze (Knoten + Abstand) ------------------------------
	var knoten: Array = []    # [name, Vector2, art]   art: 0 Dorf, 1 Ort, 2 Flugplatz
	for poi in m._map_pois:
		if String(poi.get("art", "")) == "ort" and not eigene.has(String(poi["name"])):
			var pp: Vector3 = poi["pos"]
			# Nicht angeschlossen: das Hochhausviertel (eigenes Raster) und das BERGDORF auf
			# seinem Felsschelf (120 m) hinter der Muehlbachschlucht — die Strasse dorthin wurde
			# ein 1,3 km langes Viadukt, das mitten in der Stadt 30 m hoch begann.
			if absf(pp.x) < 34000.0 and absf(pp.z) < 34000.0 \
					and not String(poi["name"]) in ["NEONBUCHT", "Bergdorf"]:
				knoten.append([String(poi["name"]), Vector2(pp.x, pp.z), 1])
	for af in m.airfields:
		var p: Vector3 = af["pos"]
		if absf(p.x) > 34000.0 or absf(p.z) > 34000.0 or String(af["name"]) == "ADLERHORST":
			continue
		var lokal := Vector3(200.0, 0.0, 145.0) if af.get("main", false) else Vector3(300.0, 0.0, 80.0)
		var v: Vector3 = p + Basis(Vector3.UP, float(af["heading"])) * lokal
		knoten.append([String(af["name"]), Vector2(v.x, v.z), 2])
	var meiden: Array = []
	for k in knoten:
		meiden.append(k[1])
		_freigeben(k[1])
	for poi in m._map_pois:
		var pp: Vector3 = poi["pos"]
		if String(poi.get("art", "")) == "natur" and absf(pp.x) < 34000.0 and absf(pp.z) < 34000.0:
			meiden.append(Vector2(pp.x, pp.z))

	# --- DOERFER -------------------------------------------------------------------
	# Geeignet: bewohnbare Hoehe, nicht im Wasser/Fluss/gesperrt, halbwegs eben (Spanne im
	# 5x5-Fenster +-200 m unter 30 m). GEWAEHLT wird dann nach ABDECKUNG: je Runde die
	# geeignete Stelle, die am weitesten von allem Bestehenden (Orte, Plaetze, Wahrzeichen,
	# schon gewaehlte Doerfer) entfernt ist, plus ein kleiner Bonus fuer Ebenheit, Kueste
	# und Flussnaehe. Die erste Fassung nahm schlicht die flachsten Stellen — das war fast
	# ausschliesslich der Strand (20 von 20 Doerfern auf 4 bis 7 m).
	var kand: Array = []      # [guete, Vector2, hoehe, kueste, fluss_nah, spanne]
	var schritt := 4
	for iz in range(2, nz - 2, schritt):
		for ix in range(2, nx - 2, schritt):
			var i := _idx(ix, iz)
			if sperre[i] == 1 or fluss[i] == 1:
				continue
			var hc := h[i]
			if hc < 7.0 or hc > 520.0:
				continue
			var lo := INF
			var hi := -INF
			var bad := false
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var j := _idx(ix + dx, iz + dz)
					if sperre[j] == 1 or fluss[j] == 1:
						bad = true
					lo = minf(lo, h[j])
					hi = maxf(hi, h[j])
			if bad or hi - lo > 30.0:
				continue
			var w := _welt(i)
			# NICHT INS HOCHTAL: ein Gebirgstal mit dem Hoehlenflugplatz, der einzige Zugang
			# fuer eine Strasse waere die Felsstufe am Talausgang (282 m Einschnitt).
			var tal: Dictionary = t.tal
			if not tal.is_empty():
				var tr: Vector2 = Vector2(tal["richtung"]).normalized()
				var tq := w - Vector2(tal["start"])
				var tl := tq.dot(tr)
				if tl > -800.0 and tl < float(tal["laenge"]) + 800.0 \
						and absf(tq.dot(Vector2(tr.y, -tr.x))) < 2600.0:
					continue
			var kueste := false
			for a in 12:
				var q := w + Vector2(cos(TAU * a / 12.0), sin(TAU * a / 12.0)) * 900.0
				if t.height_at(q.x, q.y) < TerrainWorld.SEA_Y:
					kueste = true
			var fl: Vector4 = t._fluss_naechst(w.x, w.y)
			var fluss_nah := fl.x < 1200.0
			var guete := (30.0 - (hi - lo)) * 25.0 + (400.0 if kueste else 0.0) \
				+ (500.0 if fluss_nah else 0.0)
			kand.append([guete, w, hc, kueste, fluss_nah, hi - lo])
	var doerfer: Array = []
	var belegt: Array = meiden.duplicate()
	for runde in N_DOERFER:
		var best := -INF
		var bc: Array = []
		for c in kand:
			var w: Vector2 = c[1]
			var nah := INF
			for mp in belegt:
				nah = minf(nah, w.distance_to(mp))
			if nah < ORT_ABSTAND:
				continue
			var wert := minf(nah, 9000.0) + float(c[0])
			if wert > best:
				best = wert
				bc = c
		if bc.is_empty():
			break
		doerfer.append(bc)
		belegt.append(bc[1])
	print("PLANER %d Kandidaten, %d Doerfer" % [kand.size(), doerfer.size()])
	var namen_kueste := ["Moewenbucht", "Fischerhafen", "Kliffdorf", "Strandheim", "Seewinkel"]
	var namen_hoch := ["Hohenweide", "Kleeberg", "Sonnenhang", "Almrode", "Falkenried"]
	var namen_fluss := ["Muehlheim", "Weidenau", "Steinbach", "Brunnwald", "Erlengrund"]
	var namen := ["Lindenau", "Birkenfeld", "Eichhofen", "Moosbach", "Wiesental", "Kirchberg",
		"Tannhausen", "Gruenau", "Heideck", "Rosenthal", "Buchenau", "Ahornfeld", "Hasenwinkel",
		"Kornau", "Fuchsried"]
	var dorf_daten: Array = []
	for d in doerfer:
		var nm := ""
		if d[3] and not namen_kueste.is_empty():
			nm = namen_kueste.pop_front()
		elif float(d[2]) > 220.0 and not namen_hoch.is_empty():
			nm = namen_hoch.pop_front()
		elif d[4] and not namen_fluss.is_empty():
			nm = namen_fluss.pop_front()
		else:
			nm = namen.pop_front()
		# Groesse: 0 Weiler, 1 Dorf, 2 Marktflecken — nach Ebenheit
		var gr := 1
		if float(d[5]) < 9.0:
			gr = 2
		elif float(d[5]) > 20.0:
			gr = 0
		dorf_daten.append([nm, d[1], gr])
		knoten.append([nm, d[1], 0])
		_freigeben(d[1])
		print("DORF %-12s (%6.0f, %6.0f) h %4.0f  Groesse %d  Spanne %.0f m%s%s" % [nm, d[1].x, d[1].y,
			d[2], gr, d[5], "  Kueste" if d[3] else "", "  Fluss" if d[4] else ""])

	# --- STRASSEN ------------------------------------------------------------------
	# Kandidatenkanten: jeder Knoten zu seinen 4 naechsten (bis 11 km).
	var kanten: Dictionary = {}
	for a in knoten.size():
		var liste: Array = []
		for b in knoten.size():
			if a != b:
				liste.append([(knoten[a][1] as Vector2).distance_to(knoten[b][1]), b])
		liste.sort_custom(func(u: Array, v: Array) -> bool: return float(u[0]) < float(v[0]))
		for k in mini(5, liste.size()):
			if float(liste[k][0]) > 13000.0:
				continue
			var b: int = liste[k][1]
			kanten[Vector2i(mini(a, b), maxi(a, b))] = float(liste[k][0])
	# Kosten je Kante vorab (ohne Buendelung) fuer Spannbaum und Abkuerzungen
	var kosten: Dictionary = {}
	for key in kanten:
		var r := _astern(knoten[key.x][1], knoten[key.y][1])
		if r.is_empty():
			continue
		kosten[key] = r[0]
	var fehl := kanten.size() - kosten.size()
	# ZUSAMMENHANG ERZWINGEN: solange es mehrere Teilnetze gibt, je zwei Teilnetze ueber
	# ihre naechsten Knotenpaare (die 3 naechsten) verbinden. Mit nur den vier naechsten
	# Nachbarn zerfiel das Netz in Inseln (Westen, Ostkueste, Norden ohne Anschluss).
	for versuch in 12:
		var teil: Array = []
		for i in knoten.size():
			teil.append(i)
		for key in kosten:
			var ra := _finde(teil, key.x)
			var rb := _finde(teil, key.y)
			if ra != rb:
				teil[ra] = rb
		var gruppen: Dictionary = {}
		for i in knoten.size():
			var r := _finde(teil, i)
			if not gruppen.has(r):
				gruppen[r] = []
			(gruppen[r] as Array).append(i)
		if gruppen.size() <= 1:
			break
		print("PLANER Teilnetze: %d" % gruppen.size())
		if versuch == 11 or versuch == 0:
			for gk in gruppen:
				var namen_g := PackedStringArray()
				for i in gruppen[gk]:
					namen_g.append(String(knoten[i][0]))
				print("  Teilnetz: ", ", ".join(namen_g))
		var gl: Array = gruppen.values()
		for ga in gl.size():
			# naechste Paare zu IRGENDEINEM anderen Teilnetz
			var paare: Array = []
			for a in gl[ga]:
				for gb in gl.size():
					if gb == ga:
						continue
					for b in gl[gb]:
						paare.append([(knoten[a][1] as Vector2).distance_to(knoten[b][1]), a, b])
			paare.sort_custom(func(u: Array, v: Array) -> bool: return float(u[0]) < float(v[0]))
			for k in mini(3, paare.size()):
				var key := Vector2i(mini(paare[k][1], paare[k][2]), maxi(paare[k][1], paare[k][2]))
				if kosten.has(key):
					continue
				var r := _astern(knoten[key.x][1], knoten[key.y][1])
				if not r.is_empty():
					kosten[key] = r[0]
				else:
					fehl += 1
					if versuch == 0:
						print("PLANER kein Weg: %s -> %s" % [knoten[key.x][0], knoten[key.y][0]])
	print("PLANER Kanten ohne Weg: %d" % fehl)
	# Kruskal
	var eltern: Array = []
	for i in knoten.size():
		eltern.append(i)
	var sortiert: Array = kosten.keys()
	sortiert.sort_custom(func(u: Vector2i, v: Vector2i) -> bool: return float(kosten[u]) < float(kosten[v]))
	var baum: Array = []
	var uebrig: Array = []
	for key in sortiert:
		var ra := _finde(eltern, key.x)
		var rb := _finde(eltern, key.y)
		if ra != rb:
			eltern[ra] = rb
			baum.append(key)
		else:
			uebrig.append(key)
	# Abkuerzungen: Kante, deren Kosten weniger als 62 % des Wegs durch den Baum sind
	var extra: Array = []
	for key in uebrig:
		var umweg := _baum_weg(baum, kosten, knoten.size(), key.x, key.y)
		if float(kosten[key]) < umweg * 0.62:
			extra.append(key)
	print("PLANER %d Knoten, Baum %d Kanten, Abkuerzungen %d" % [knoten.size(), baum.size(), extra.size()])
	# Bauen: Baum zuerst (kuerzeste zuerst), dann Abkuerzungen — mit Buendelung
	var strassen: Array = []
	for key in baum + extra:
		var r := _astern(knoten[key.x][1], knoten[key.y][1], true)
		if r.is_empty():
			continue
		var pfad: Array = r[1]
		# Stuecke, die NICHT schon Strasse sind; Enden reichen eine Zelle in die alte hinein
		var stueck: Array = []
		for k in pfad.size():
			var i: int = pfad[k]
			if strasse[i] == 0:
				if stueck.is_empty() and k > 0:
					stueck.append(pfad[k - 1])
				stueck.append(i)
			else:
				if not stueck.is_empty():
					stueck.append(i)
					if stueck.size() >= 3:
						strassen.append([stueck, knoten[key.x][2] == 0 and knoten[key.y][2] == 0])
					stueck = []
		if stueck.size() >= 3:
			strassen.append([stueck, knoten[key.x][2] == 0 and knoten[key.y][2] == 0])
		for i in pfad:
			strasse[i] = 1
	# Glaetten + schreiben
	var zeilen := PackedStringArray()
	zeilen.append("## ERZEUGT von tools/_dorf_planer.gd — nicht von Hand bearbeiten, neu erzeugen.")
	zeilen.append("## Doerfer und Strassennetz der Hauptinsel (Stil: Landstrassen zwischen Doerfern,")
	zeilen.append("## Orten und Flugplaetzen). Hoehen rechnet das Spiel aus dem Gelaende (Strassen.gd).")
	zeilen.append("class_name StrassenDaten")
	zeilen.append("")
	zeilen.append("## [Name, Lage (x, z), Groesse 0 Weiler / 1 Dorf / 2 Marktflecken]")
	zeilen.append("const DOERFER := [")
	for d in dorf_daten:
		zeilen.append("\t[\"%s\", Vector2(%d, %d), %d]," % [d[0], roundi(d[1].x), roundi(d[1].y), d[2]])
	zeilen.append("]")
	zeilen.append("")
	zeilen.append("## [Nebenstrasse? (nur Doerfer verbunden), Punkte (x, z)]")
	zeilen.append("const STRASSEN := [")
	var gesamt := 0.0
	for s in strassen:
		var pts: Array[Vector2] = []
		for i in s[0]:
			pts.append(_welt(i))
		var einfach := _dp(pts, 30.0)
		# Nach dem Begradigen noch ein Chaikin: rundet die Anschlussknicke der Querungen ab,
		# die gerade Rampe bleibt gerade (kollineare Punkte bleiben auf der Linie).
		var glatt := _chaikin(_querungen_begradigen(_chaikin(_chaikin(einfach))))
		for k in range(1, glatt.size()):
			gesamt += glatt[k].distance_to(glatt[k - 1])
		var z := "\t[%s, [" % ("true" if s[1] else "false")
		for k in glatt.size():
			z += "Vector2(%d, %d), " % [roundi(glatt[k].x), roundi(glatt[k].y)]
		zeilen.append(z + "]],")
	zeilen.append("]")
	var fa := FileAccess.open(ZIEL, FileAccess.WRITE)
	fa.store_string("\n".join(zeilen) + "\n")
	fa.close()
	print("PLANER %d Strassenstuecke, %.1f km, geschrieben: %s" % [strassen.size(), gesamt / 1000.0, ZIEL])


## ANSCHLUSSSTRASSEN an das vorhandene Netz (siehe Kopfkommentar).
func _anschluss() -> void:
	t = m.terrain
	m.set("_fern_stopp", true)
	var ft: Thread = m.get("_fern_thread")
	if ft != null and ft.is_started():
		ft.wait_to_finish()
		m.set("_fern_thread", null)
	(m.get("_map_stopp") as Array)[0] = true
	var mt: Thread = m.get("_map_thread")
	if mt != null and mt.is_started():
		mt.wait_to_finish()
		m.set("_map_thread", null)
	# gewachsenes Gelaende OHNE die Einschnitte der Strassen (auch der eigenen vom letzten Lauf)
	t.set("_strassen_an", false)
	fenster = Rect2(2500.0, -1500.0, 19000.0, 15000.0)
	_raster()
	# Die Hafenstadt selbst ist gesperrt: die Strasse beginnt am Ortsrand und laeuft aussen herum.
	var hm := Vector2(Hafenstadt.MITTE.x, Hafenstadt.MITTE.z)
	for i in nx * nz:
		if _welt(i).distance_to(hm) < Hafenstadt.R_FLACH + 30.0:
			sperre[i] = 1
	# vorhandenes Netz in die Strassenmaske
	for st in StrassenDaten.STRASSEN:
		var sp: Array = st[1]
		for k in range(sp.size() - 1):
			var a: Vector2 = sp[k]
			var b: Vector2 = sp[k + 1]
			var n := maxi(1, int(a.distance_to(b) / 25.0))
			for j in n + 1:
				strasse[_zelle(a.lerp(b, float(j) / float(n)))] = 1
	var zeilen := PackedStringArray()
	zeilen.append("## ERZEUGT von tools/_dorf_planer.gd -- anschluss — nicht von Hand bearbeiten.")
	zeilen.append("## Anschlussstrassen der Hafenstadt FREIHAFEN an das Netz aus StrassenDaten (das")
	zeilen.append("## dabei unveraendert bleibt). Jede beginnt genau an Hafenstadt.anschluesse().")
	zeilen.append("class_name StrassenZusatz")
	zeilen.append("")
	zeilen.append("## [Nebenstrasse?, Punkte (x, z)]")
	zeilen.append("const STRASSEN := [")
	var gesamt := 0.0
	for auftrag in Hafenstadt.anschluesse():
		var start: Vector2 = auftrag[0]
		var ziel: Vector2 = auftrag[1]
		sperre[_zelle(start)] = 0
		_freigeben(ziel)
		var r := _astern(start, ziel, true)
		if r.is_empty():
			print("ANSCHLUSS kein Weg: ", start, " -> ", ziel)
			continue
		var pfad: Array = r[1]
		# wie im Planer: nur Stuecke, die nicht schon Strasse sind; das Ende reicht eine
		# Zelle in die alte Strasse hinein
		var stuecke: Array = []
		var stueck: Array = []
		for k in pfad.size():
			var i: int = pfad[k]
			if strasse[i] == 0:
				if stueck.is_empty() and k > 0:
					stueck.append(pfad[k - 1])
				stueck.append(i)
			elif not stueck.is_empty():
				stueck.append(i)
				if stueck.size() >= 3:
					stuecke.append(stueck)
				stueck = []
		if stueck.size() >= 3:
			stuecke.append(stueck)
		for i in pfad:
			strasse[i] = 1
		for si in stuecke.size():
			var pts: Array[Vector2] = []
			for i in stuecke[si]:
				pts.append(_welt(i))
			# das erste Stueck beginnt GENAU am Anschlusspunkt der Stadt
			if si == 0 and int(stuecke[si][0]) == _zelle(start):
				pts[0] = start
			var glatt := _chaikin(_querungen_begradigen(_chaikin(_chaikin(_dp(pts, 30.0)))))
			if si == 0 and int(stuecke[si][0]) == _zelle(start):
				glatt[0] = start
			# Das Ende AUF die alte Strasse ziehen: es liegt sonst nur in deren Rasterzelle,
			# bis zu 70 m neben der Fahrbahn (gemessen 34 m — eine Luecke zwischen den Baendern).
			var ende := glatt[glatt.size() - 1]
			var best := ende
			var best_d := 90.0
			for alt_s in StrassenDaten.STRASSEN:
				var ap: Array = alt_s[1]
				for k in range(ap.size() - 1):
					var q := Geometry2D.get_closest_point_to_segment(ende, ap[k], ap[k + 1])
					if q.distance_to(ende) < best_d:
						best_d = q.distance_to(ende)
						best = q
			glatt[glatt.size() - 1] = best
			var lang := 0.0
			for k in range(1, glatt.size()):
				lang += glatt[k].distance_to(glatt[k - 1])
			gesamt += lang
			print("ANSCHLUSS %s -> %s: Stueck %d, %.1f km, von %s bis %s" % [start, ziel, si,
				lang / 1000.0, glatt[0], glatt[glatt.size() - 1]])
			var z := "\t[false, ["
			for k in glatt.size():
				z += "Vector2(%d, %d), " % [roundi(glatt[k].x), roundi(glatt[k].y)]
			zeilen.append(z + "]],")
	zeilen.append("]")
	var fa := FileAccess.open("res://scripts/StrassenZusatz.gd", FileAccess.WRITE)
	fa.store_string("\n".join(zeilen) + "\n")
	fa.close()
	print("ANSCHLUSS %.1f km geschrieben: res://scripts/StrassenZusatz.gd" % (gesamt / 1000.0))


## Um einen Knoten 600 m freigeben (Sperrzonen duerfen keinen Ort einschliessen —
## VULKANFELD lag selbst in der Vulkanzone und kam nie heraus). Wasser bleibt gesperrt.
func _freigeben(p: Vector2) -> void:
	var c := _zelle(p)
	var cx := c % nx
	var cz := c / nx
	for dz in range(-6, 7):
		for dx in range(-6, 7):
			var ax := cx + dx
			var az := cz + dz
			if ax < 0 or az < 0 or ax >= nx or az >= nz:
				continue
			var i := _idx(ax, az)
			if h[i] > TerrainWorld.SEA_Y + 1.5:
				sperre[i] = 0


func _finde(e: Array, i: int) -> int:
	while e[i] != i:
		e[i] = e[e[i]]
		i = e[i]
	return i


## Kosten des Wegs von a nach b durch den Baum (Dijkstra auf dem kleinen Graphen).
func _baum_weg(baum: Array, kosten: Dictionary, n: int, a: int, b: int) -> float:
	var d: Array = []
	d.resize(n)
	d.fill(INF)
	d[a] = 0.0
	var offen := [a]
	while not offen.is_empty():
		var bi := 0
		for k in offen.size():
			if float(d[offen[k]]) < float(d[offen[bi]]):
				bi = k
		var u: int = offen[bi]
		offen.remove_at(bi)
		for key in baum:
			var v := -1
			if key.x == u:
				v = key.y
			elif key.y == u:
				v = key.x
			if v < 0:
				continue
			var nd: float = float(d[u]) + float(kosten[key])
			if nd < float(d[v]):
				d[v] = nd
				offen.append(v)
	return float(d[b])


## A* auf dem Raster. Rueckgabe [kosten, pfad (Zellindizes)] oder [].
func _astern(pa: Vector2, pb: Vector2, buendeln := false) -> Array:
	var s := _zelle(pa)
	var ziel := _zelle(pb)
	var g := PackedFloat32Array()
	g.resize(nx * nz)
	g.fill(1e30)
	var vor := PackedInt32Array()
	vor.resize(nx * nz)
	vor.fill(-1)
	var zu := PackedByteArray()
	zu.resize(nx * nz)
	g[s] = 0.0
	var hk := PackedFloat32Array([0.0])
	var hv := PackedInt32Array([s])
	var zx := ziel % nx
	var zz := ziel / nx
	var nb := [[1, 0, 1.0], [-1, 0, 1.0], [0, 1, 1.0], [0, -1, 1.0],
		[1, 1, 1.4142], [1, -1, 1.4142], [-1, 1, 1.4142], [-1, -1, 1.4142]]
	var gefunden := false
	while hk.size() > 0:
		var v0 := hv[0]
		var last := hk.size() - 1
		hk[0] = hk[last]
		hv[0] = hv[last]
		hk.resize(last)
		hv.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m2 := i
			if l < hk.size() and hk[l] < hk[m2]:
				m2 = l
			if r < hk.size() and hk[r] < hk[m2]:
				m2 = r
			if m2 == i:
				break
			var tk := hk[i]; hk[i] = hk[m2]; hk[m2] = tk
			var tv := hv[i]; hv[i] = hv[m2]; hv[m2] = tv
			i = m2
		if zu[v0] == 1:
			continue
		zu[v0] = 1
		if v0 == ziel:
			gefunden = true
			break
		var cx := v0 % nx
		var cz := v0 / nx
		for e in nb:
			var ax: int = cx + int(e[0])
			var az: int = cz + int(e[1])
			if ax < 0 or az < 0 or ax >= nx or az >= nz:
				continue
			var w := az * nx + ax
			if zu[w] == 1:
				continue
			if sperre[w] == 1 and w != ziel:
				continue
			var lang := Z * float(e[2])
			var steig := maxf(absf(h[w] - h[v0]) / lang, rauh[w] * 0.3)
			var bruecke := fluss[w] == 1 or fluss[v0] == 1
			if bruecke:
				steig = 0.0          # ueber das Tal fuehrt eine Bruecke
			elif steig > MAX_STEIG or rauh[w] > 0.85:
				continue
			var c := lang * (1.0 + pow(steig / 0.045, 2.0))
			# Im Flusstal: queren ja, laengs fahren nein — jeder Meter Bruecke ist teuer.
			# Ohne diesen Aufschlag liefen Strassen gern das (steigungsfreie) Tal entlang und
			# wurden im Spiel zu 800 m langen Bruecken neben dem Fluss.
			if bruecke:
				c = lang * 4.0
			if fluss[w] == 1 and fluss[v0] == 0:
				c += 1500.0
			if buendeln and strasse[w] == 1:
				c *= 0.33
			var ng := g[v0] + c
			if ng < g[w]:
				g[w] = ng
				vor[w] = v0
				var f_h := Z * Vector2(ax - zx, az - zz).length() * (0.33 if buendeln else 1.0)
				hk.append(ng + f_h)
				hv.append(w)
				var j := hk.size() - 1
				while j > 0:
					var p := (j - 1) / 2
					if hk[p] <= hk[j]:
						break
					var tk2 := hk[p]; hk[p] = hk[j]; hk[j] = tk2
					var tv2 := hv[p]; hv[p] = hv[j]; hv[j] = tv2
					j = p
	if not gefunden:
		return []
	var pfad: Array = []
	var v := ziel
	while v >= 0:
		pfad.push_front(v)
		v = vor[v]
	return [g[ziel], pfad]


func _dp(p: Array[Vector2], eps: float) -> Array[Vector2]:
	if p.size() < 3:
		return p
	var a := p[0]
	var b := p[p.size() - 1]
	var best := -1.0
	var bi := 0
	for i in range(1, p.size() - 1):
		var ab := b - a
		var l2 := ab.length_squared()
		var tt := 0.0 if l2 < 1e-6 else clampf((p[i] - a).dot(ab) / l2, 0.0, 1.0)
		var dd := p[i].distance_to(a + ab * tt)
		if dd > best:
			best = dd
			bi = i
	if best <= eps:
		return [a, b]
	var links := _dp(p.slice(0, bi + 1), eps)
	var rechts := _dp(p.slice(bi), eps)
	links.remove_at(links.size() - 1)
	links.append_array(rechts)
	return links


func _chaikin(p: Array[Vector2]) -> Array[Vector2]:
	if p.size() < 3:
		return p
	var raus: Array[Vector2] = [p[0]]
	for k in range(p.size() - 1):
		var a := p[k]
		var b := p[k + 1]
		if k > 0:
			raus.append(a.lerp(b, 0.25))
		if k < p.size() - 2:
			raus.append(a.lerp(b, 0.75))
	raus.append(p[p.size() - 1])
	return raus


# --- Flussquerungen -------------------------------------------------------------------
## Naechstes Flusssegment: Vector4(Abstand zur Flussmitte, halbe Wasserbreite, Richtung x, z)
## und die Seite (Vorzeichen) ueber seitenwahl. Liest das Zellenraster des Gelaendes.
func _fluss_bei(p: Vector2) -> Array:
	var k0 := t._fl_zelle(p.x, p.y)
	if k0 < 0:
		return [INF, 0.0, Vector2.ZERO, 0.0]
	var best := INF
	var raus := [INF, 0.0, Vector2.ZERO, 0.0]
	for j in range(t._fl_start[k0], t._fl_start[k0 + 1]):
		var si := t._fl_seg[j]
		var a := Vector2(t._fl_a[si].x, t._fl_a[si].z)
		var b := Vector2(t._fl_b[si].x, t._fl_b[si].z)
		var ab := b - a
		var l2 := ab.length_squared()
		var tt := 0.0 if l2 < 1e-6 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var q := a + ab * tt
		var d := p.distance_to(q)
		if d < best:
			best = d
			var dir := ab.normalized()
			raus = [d, lerpf(t._fl_w[si * 2], t._fl_w[si * 2 + 1], tt) * 0.5, dir,
				signf(dir.x * (p.y - a.y) - dir.y * (p.x - a.x))]
	return raus


## FLUSSQUERUNGEN BEGRADIGEN: Auf dem 100-m-Raster und nach dem Glaetten querte die Strasse
## einen Fluss, der in ihrer Richtung lief, unter flachem Winkel — bei (-5750, 2115) unter 19
## Grad, im Spiel eine 237 m lange Bruecke LAENGS am Ufer. Jede Querung unter 65 Grad wird
## ersetzt: gerade Rampe unter 90/70/55 Grad zum Fluss, beidseits per Hermite-Kurve
## tangential an den alten Verlauf angeschlossen (Anschluss 160..600 m). STUR RECHTWINKLIG
## war die zweite Fassung: im engen Tal fuehrte das S der Anschlusskurven in den Uferhang,
## 36 m tiefer Einschnitt am Brueckenkopf. Deshalb wird jede Variante mit dem ECHTEN
## Strassenprofil (TerrainWorld.strasse_profil) bewertet: groesster Einschnitt/Damm zuerst,
## dann Brueckenlaenge. Geht keine sauber (Doppelquerung, Anschluss im Wasser), bleibt die
## Stelle und wird gemeldet.
func _querungen_begradigen(p: Array[Vector2]) -> Array[Vector2]:
	var k := 0
	while k < p.size() - 1:
		# Seitenwechsel in 10-m-Schritten suchen: nach DP + Chaikin liegen Stuetzpunkte auf
		# geraden Strecken Hunderte Meter auseinander, ein 40-m-Fluss faellt dazwischen durch.
		var seg_l := p[k].distance_to(p[k + 1])
		var n_sub := maxi(int(seg_l / 10.0), 1)
		var c := Vector2.INF
		var fa := _fluss_bei(p[k])
		for j in n_sub:
			var q1 := p[k].lerp(p[k + 1], float(j + 1) / float(n_sub))
			var fb := _fluss_bei(q1)
			if float(fa[3]) != float(fb[3]) and float(fa[0]) < float(fa[1]) + 40.0 \
					and float(fb[0]) < float(fb[1]) + 40.0:
				var q0 := p[k].lerp(p[k + 1], float(j) / float(n_sub))
				var da: float = float(fa[0]) * float(fa[3])
				var db: float = float(fb[0]) * float(fb[3])
				c = q0.lerp(q1, clampf(da / (da - db), 0.0, 1.0)) if absf(da - db) > 1e-3 else q0
				break
			fa = fb
		if c == Vector2.INF:
			k += 1
			continue
		var fc := _fluss_bei(c)
		var tang: Vector2 = fc[2]
		var halb: float = float(fc[1])
		var lauf := (p[k + 1] - p[k]).normalized()
		var nrm := Vector2(-tang.y, tang.x)
		if nrm.dot(lauf) < 0.0:
			nrm = -nrm
		var mit := 1.0 if lauf.dot(tang) >= 0.0 else -1.0
		var winkel := 90.0 - rad_to_deg(acos(clampf(absf(nrm.dot(lauf)), 0.0, 1.0)))   # Kreuzungswinkel
		if winkel >= 65.0:
			k += 1
			continue           # steil genug: den gewachsenen Verlauf lassen
		var best: Array[Vector2] = []
		var best_wert := INF
		var best_ia := 0
		var best_ib := 0
		var best_text := ""
		for ziel_w: float in [90.0, 70.0, 55.0]:
			var rw := deg_to_rad(ziel_w)
			var rdir := (tang * mit * cos(rw) + nrm * sin(rw)).normalized()
			var l := (halb + 35.0) / sin(rw)
			for zusatz: float in [160.0, 280.0, 420.0, 600.0]:
				var dd := l + zusatz
				# Anschlusspunkte auf dem alten Verlauf: Bogenlaenge dd vor/nach der Querung
				var ia := k
				var acc := p[k].distance_to(c)
				while ia > 0 and acc < dd:
					acc += p[ia].distance_to(p[ia - 1])
					ia -= 1
				var ib := k + 1
				acc = p[k + 1].distance_to(c)
				while ib < p.size() - 1 and acc < dd:
					acc += p[ib].distance_to(p[ib + 1])
					ib += 1
				if ia == 0 or ib == p.size() - 1:
					continue
				var a_pt := c - rdir * l
				var b_pt := c + rdir * l
				var ta := (p[ia + 1] - p[ia - 1]).normalized()
				var tb := (p[ib + 1] - p[ib - 1]).normalized()
				var h1 := _hermite(p[ia], ta, a_pt, rdir)
				var h2 := _hermite(b_pt, rdir, p[ib], tb)
				h2.remove_at(0)
				var stueck: Array[Vector2] = []
				stueck.append_array(h1)
				var n_gerade := maxi(int(l * 2.0 / 20.0), 2)
				for j in n_gerade:
					stueck.append(a_pt.lerp(b_pt, float(j) / float(n_gerade)))
				stueck.append(b_pt)
				stueck.append_array(h2)
				# Genau EIN Seitenwechsel; die Anschlusskurven nie naeher als halb + 12 m am Wasser
				var seite := float(_fluss_bei(p[ia])[3])
				var wechsel := 0
				for q in stueck:
					var fq := _fluss_bei(q)
					if float(fq[0]) < float(fq[1]) + 40.0 and float(fq[3]) != seite:
						wechsel += 1
						seite = float(fq[3])
				var nah := false
				for q in h1 + h2:
					var fq := _fluss_bei(q)
					if float(fq[0]) < float(fq[1]) + 12.0:
						nah = true
				if wechsel != 1 or nah:
					continue
				var wert := _querung_wert(p, ia, ib, stueck)
				if wert[0] < best_wert:
					best_wert = wert[0]
					best = stueck
					best_ia = ia
					best_ib = ib
					best_text = "%.0f Grad, Anschluss %.0f m: Eingriff %.1f m, Bruecke %.0f m" % [
						ziel_w, dd, wert[1], wert[2]]
		if best.is_empty():
			print("PLANER Querung bei (%.0f, %.0f): %.0f Grad, NICHT begradigt" % [c.x, c.y, winkel])
			k += 1
			continue
		var alt := _querung_wert(p, best_ia, best_ib, p.slice(best_ia, best_ib + 1))
		var neu: Array[Vector2] = []
		neu.append_array(p.slice(0, best_ia))
		neu.append_array(best)
		var weiter := neu.size()
		neu.append_array(p.slice(best_ib + 1))
		print("PLANER Querung bei (%.0f, %.0f): %.0f Grad (Eingriff %.1f m, Bruecke %.0f m) -> %s" % [
			c.x, c.y, winkel, alt[1], alt[2], best_text])
		p = neu
		k = weiter
	return p


## Bewertung einer Querungsvariante: Strassenprofil ueber das Ersatzstueck plus 300 m davor
## und danach. [Wert, groesster Einschnitt/Damm ausserhalb der Bruecke, Brueckenlaenge].
func _querung_wert(p: Array[Vector2], ia: int, ib: int, stueck: Array[Vector2]) -> Array:
	var zug := PackedVector2Array()
	var i0 := ia
	var acc := 0.0
	while i0 > 0 and acc < 300.0:
		acc += p[i0].distance_to(p[i0 - 1])
		i0 -= 1
	for i in range(i0, ia):
		zug.append(p[i])
	zug.append_array(PackedVector2Array(stueck))
	var i1 := ib
	acc = 0.0
	while i1 < p.size() - 1 and acc < 300.0:
		acc += p[i1].distance_to(p[i1 + 1])
		i1 += 1
	for i in range(ib + 1, i1 + 1):
		zug.append(p[i])
	var pts := TerrainWorld.strasse_abtasten(zug)
	var prof := t.strasse_profil(pts)
	var hh: PackedFloat32Array = prof[0]
	var br: PackedByteArray = prof[1]
	var gel: PackedFloat32Array = prof[2]
	var eingriff := 0.0
	var bruecke := 0.0
	var laenge := 0.0
	for i in pts.size():
		if i > 0:
			laenge += pts[i].distance_to(pts[i - 1])
		if br[i] == 1:
			bruecke += TerrainWorld.STRASSE_SCHRITT
		else:
			eingriff = maxf(eingriff, absf(gel[i] - hh[i]))
	return [eingriff + 0.04 * bruecke + 0.004 * laenge, eingriff, bruecke]


## Kubische Hermite-Kurve von a (Richtung ta) nach b (Richtung tb), ohne den Endpunkt b.
func _hermite(a: Vector2, ta: Vector2, b: Vector2, tb: Vector2) -> Array[Vector2]:
	var raus: Array[Vector2] = []
	var l := a.distance_to(b)
	var n := maxi(int(l / 20.0), 2)
	for j in n:
		var u := float(j) / float(n)
		var u2 := u * u
		var u3 := u2 * u
		raus.append(a * (2.0 * u3 - 3.0 * u2 + 1.0) + ta * l * (u3 - 2.0 * u2 + u)
			+ b * (-2.0 * u3 + 3.0 * u2) + tb * l * (u3 - u2))
	return raus
