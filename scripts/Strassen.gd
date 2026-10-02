## STRASSEN UND DOERFER der Hauptinsel — Aufbau der sichtbaren Teile.
##
## DATEN: scripts/StrassenDaten.gd (erzeugt von tools/_dorf_planer.gd: Standorte nach
## Abdeckung und Bewohnbarkeit, Strassen per A* ueber das echte Gelaende, Spannbaum plus
## Abkuerzungen). GELAENDE: TerrainWorld (strassen / strassen_fertigstellen) legt das ebene
## Bett mit Boeschungen ins Hoehenfeld und rechnet das Profil. HIER:
##   * Flachzonen der Doerfer (vor setup(); Hoehe danach aus dem Ring-Median)
##   * Fahrbahnbaender (eigener Shader: Asphalt mit Rand- und Mittellinie bzw. Schotterweg)
##   * Bruecken ueber die Fluesse (Platte, Gelaender, Pfeiler bis auf den Grund, Kollision)
##   * Haeuser: Strassendoerfer entlang der Strasse, Fronten zur Fahrbahn, Hoefe dahinter
##   * Kartendaten (Namen als Orte, Strassen als eigene Ebene in WorldMap)
class_name Strassen
extends RefCounted

## Flachzone je Dorfgroesse [r_flat, r_blend], halbe Laenge der Dorfstrasse.
const ZONE := [[75.0, 180.0], [125.0, 290.0], [175.0, 390.0]]
const LAENGE := [55.0, 110.0, 165.0]
const BAND_Y := 0.08                 # Fahrbahnband ueber dem Bett
const STUECK := 50                   # Abschnitte je Band-Netz (ca. 1 km, fuers Kulling)
## Kreise [Mitte, Radius] um Orte mit eigenem Strassennetz (Stadtstrassen): innerhalb wird
## kein Landstrassenband gezeichnet — das Stadtnetz uebernimmt an der Zufahrt. Main setzt sie.
static var stadt_kreise: Array = []


## Strassen fuer TerrainWorld (vor setup()).
static func strassen_daten() -> Array:
	var raus: Array = []
	for s in StrassenDaten.STRASSEN:
		raus.append({"neben": bool(s[0]), "pts": PackedVector2Array(s[1] as Array)})
	# Anschlussstrassen der Hafenstadt (eigene Datei: das Netz oben bleibt, wie es ist)
	for s in StrassenZusatz.STRASSEN:
		raus.append({"neben": bool(s[0]), "pts": PackedVector2Array(s[1] as Array)})
	return raus


## Flachzonen der Doerfer (vor setup()). "y" ist ein Platzhalter — der Schluessel muss vor
## setup() stehen, weil der Chunk-Worker das Woerterbuch liest; der Wert kommt danach
## (dorf_hoehen).
static func flachzonen() -> Array:
	var raus: Array = []
	for d in StrassenDaten.DOERFER:
		var p: Vector2 = d[1]
		var z: Array = ZONE[int(d[2])]
		raus.append({"pos": Vector3(p.x, 0.0, p.y), "r_flat": z[0], "r_blend": z[1], "y": 0.0,
			"ort": true})
	return raus


## Nach setup(): Hoehe jeder Dorfzone = Median des DORFGRUNDS selbst (Mitte + Ring bei
## 60 % des Flachradius), gemessen mit abgeschalteter eigener Zone (sie steht dafuer kurz
## weit weg — die Chunk-Worker warten da noch, der Kartenfaden laeuft noch nicht).
## FALLE, die das noetig machte: ein Ring AUSSERHALB der Zone (wie bei den Orten der
## Regionen) lag bei Moosbach, einem Dorf auf einer Kuppe am Meer, zur Haelfte im Wasser —
## Median 4 m, und das Dorf sass in einer 85 m tiefen Grube.
static func dorf_hoehen(terrain: TerrainWorld, zonen: Array) -> void:
	for fz in zonen:
		var p: Vector3 = fz["pos"]
		fz["pos"] = Vector3(1.0e7, 0.0, 1.0e7)
		var r: float = float(fz["r_flat"]) * 0.6
		var hs: Array = [terrain.height_at(p.x, p.z)]
		for k in 8:
			var a := TAU * float(k) / 8.0
			hs.append(terrain.height_at(p.x + cos(a) * r, p.z + sin(a) * r))
		hs.sort()
		fz["pos"] = p
		fz["y"] = maxf(float(hs[4]), 4.0)


## Karten-POIs der Doerfer.
static func karten_orte() -> Array:
	var raus: Array = []
	for d in StrassenDaten.DOERFER:
		var p: Vector2 = d[1]
		raus.append({"name": String(d[0]), "pos": Vector3(p.x, 0.0, p.y),
			"color": Color(0.86, 0.80, 0.62), "art": "ort",
			"radius": LAENGE[int(d[2])] * 0.9})
	return raus


## Alles Sichtbare bauen (nach strassen_fertigstellen). zonen = flachzonen() mit Hoehe.
static func bauen(parent: Node3D, terrain: TerrainWorld, zonen: Array) -> void:
	Ortsgruen.bilanz = [0, 0, 0, 0]
	Ortsleben.bilanz = [0, 0, 0, 0]
	var knoten := Node3D.new()
	knoten.name = "Landstrassen"
	knoten.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # statisch
	parent.add_child(knoten)
	var mat_haupt := _material(false)
	var mat_neben := _material(true)
	for i in terrain.strassen_profile.size():
		var pr: Array = terrain.strassen_profile[i]
		var neben: bool = terrain.strassen[i].get("neben", false)
		_band(knoten, pr, mat_neben if neben else mat_haupt, not neben)
		_bruecken(knoten, terrain, pr)
	if CityBuilder.has_lib():
		for k in StrassenDaten.DOERFER.size():
			_dorf(parent, knoten, terrain, StrassenDaten.DOERFER[k], zonen[k], mat_neben)


# --- Fahrbahn --------------------------------------------------------------------------
static func _material(neben: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/strasse.gdshader")
	m.set_shader_parameter("neben", neben)
	return m


## Band entlang des Profils, in Stuecke zu STUECK Abschnitten (Kulling, Sichtweite).
## UV.x = Abstand von der Achse in METERN (+ links), UV.y = Laufmeter, UV2.x = halbe Fahrbahn.
## SEIT 2026-10-02 mit BANKETT (Schotterstreifen jenseits der Fahrbahn, liegt auf dem ebenen Bett —
## vorher endete das Asphaltband als duenner Strich direkt in der Wiese) und LEITPFOSTEN alle 50 m
## (Landstrassen, nicht auf Bruecken). Nebenstrassen bekommen einen schmalen Grasrand.
static func _band(parent: Node3D, pr: Array, mat: Material, leitpfosten := false) -> void:
	var pts: PackedVector2Array = pr[0]
	var hh: PackedFloat32Array = pr[1]
	var br: PackedByteArray = pr[2]
	var w: float = pr[3]
	var schulter: float = BANKETT if leitpfosten else BANKETT_NEBEN
	var n := pts.size()
	if n < 2:
		return
	var lauf := PackedFloat32Array()
	lauf.resize(n)
	for i in range(1, n):
		lauf[i] = lauf[i - 1] + pts[i].distance_to(pts[i - 1])
	var i0 := 0
	while i0 < n - 1:
		var i1 := mini(i0 + STUECK, n - 1)
		# Das Stueck liegt um seine eigene Mitte (lokale Koordinaten, kleine Zahlen). Die
		# Sichtweite richtet sich nach der Huelle der Geometrie, nicht nach dem Knoten
		# (nachgemessen) — das war also NICHT der Grund fuer die anfangs fehlenden Baender
		# (der war das leere Strassenraster, siehe TerrainWorld._strassen_gitter_bauen).
		var mitte := (pts[i0] + pts[i1]) * 0.5
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pfosten: Array = []
		var naechster := ceilf(lauf[i0] / LEITPFOSTEN_ABSTAND) * LEITPFOSTEN_ABSTAND
		for i in range(i0, i1):
			var im_ort := false
			for kr in stadt_kreise:
				var km: Vector2 = kr[0]
				var r2: float = float(kr[1]) * float(kr[1])
				if pts[i].distance_squared_to(km) < r2 and pts[i + 1].distance_squared_to(km) < r2:
					im_ort = true
					break
			if im_ort:
				continue
			var y0 := hh[i] + BAND_Y
			var y1 := hh[i + 1] + BAND_Y
			# Querschnitt: Bankett links, Fahrbahn, Bankett rechts (vier Laengsstreifen-Kanten).
			# Auf Bruecken kein Bankett (dort steht die Bruestung).
			var sch := 0.0 if (br[i] == 1 or br[i + 1] == 1) else schulter
			var quer := [w + sch, w, -w, -(w + sch)]
			var k0: Array = []
			var k1: Array = []
			for q: float in quer:
				var a0: Vector2 = _rand(pts, i, absf(q))[0 if q > 0.0 else 1] - mitte
				var a1: Vector2 = _rand(pts, i + 1, absf(q))[0 if q > 0.0 else 1] - mitte
				k0.append(Vector3(a0.x, y0, a0.y))
				k1.append(Vector3(a1.x, y1, a1.y))
			for streifen in 3:
				if streifen != 1 and sch <= 0.0:
					continue
				var v := [k0[streifen], k0[streifen + 1], k1[streifen + 1], k1[streifen]]
				var uv := [Vector2(quer[streifen], lauf[i]), Vector2(quer[streifen + 1], lauf[i]),
					Vector2(quer[streifen + 1], lauf[i + 1]), Vector2(quer[streifen], lauf[i + 1])]
				# WICKLUNG wie CityBuilder._band (dort nachgewiesen: die umgekehrte Reihenfolge
				# zeigte nach unten und wurde komplett weggekullt): (r0, r1, l1), (r0, l1, l0).
				for t in [[1, 2, 3], [1, 3, 0]]:
					for k in t:
						st.set_normal(Vector3.UP)
						st.set_uv(uv[k])
						st.set_uv2(Vector2(w, 0.0))
						st.add_vertex(v[k])
			# Leitpfosten auf diesem Abschnitt
			while leitpfosten and naechster < lauf[i + 1]:
				if br[i] == 0 and br[i + 1] == 0:
					var u := (naechster - lauf[i]) / maxf(lauf[i + 1] - lauf[i], 0.01)
					var pp := pts[i].lerp(pts[i + 1], u)
					var d := (pts[i + 1] - pts[i]).normalized()
					var nq := Vector2(-d.y, d.x)
					var yp := lerpf(hh[i], hh[i + 1], u) + BAND_Y
					for seite: float in [1.0, -1.0]:
						var q2 := pp + nq * seite * (w + schulter + 0.35) - mitte
						pfosten.append(Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)), Vector3(q2.x, yp, q2.y)))
				naechster += LEITPFOSTEN_ABSTAND
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Nie ueber den Rand der geladenen Chunks hinaus (dahinter liegt die abgesenkte
		# Fernschuerze, das Band schwebte darueber) — wie die Haeuser (CityBuilder).
		mi.visibility_range_end = CityBuilder.SICHT_DIST
		mi.visibility_range_end_margin = CityBuilder.SICHT_FADE
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mi.position = Vector3(mitte.x, 0.0, mitte.y)
		parent.add_child(mi)
		if not pfosten.is_empty():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _leitpfosten_netz()
			mm.instance_count = pfosten.size()
			for k in pfosten.size():
				mm.set_instance_transform(k, pfosten[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = _stein_material()
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 700.0
			mmi.position = Vector3(mitte.x, 0.0, mitte.y)
			parent.add_child(mmi)
		i0 = i1


const BANKETT := 1.0                # Schotterbankett der Landstrassen (m)
const BANKETT_NEBEN := 0.6          # Grasrand der Nebenstrassen
const LEITPFOSTEN_ABSTAND := 50.0
static var _pfosten_netz: ArrayMesh = null
static var _stein_mat: ShaderMaterial = null


## Material der Bruecken (Vertexfarbe, COLOR.a = Mauerwerk) — auch fuer die Leitpfosten.
static func _stein_material() -> ShaderMaterial:
	if _stein_mat == null:
		_stein_mat = ShaderMaterial.new()
		_stein_mat.shader = load("res://shaders/bruecke.gdshader")
	return _stein_mat


## LEITPFOSTEN: weisser Pfosten (1 m, dreieckig wie die echten), schwarzes Band oben mit
## Rueckstrahler. Einmal gebaut, alle Strassen teilen ihn.
static func _leitpfosten_netz() -> ArrayMesh:
	if _pfosten_netz != null:
		return _pfosten_netz
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var weiss := Color(0.92, 0.92, 0.90, 0.0)
	var schwarz := Color(0.10, 0.10, 0.11, 0.0)
	var strahler := Color(0.98, 0.62, 0.20, 0.0)
	# Grundriss: Dreieck, Spitze vom Verkehr weg (lokal +z quer); Breite laengs 0,12 m
	var g := [Vector3(-0.06, 0, -0.04), Vector3(0.06, 0, -0.04), Vector3(0.0, 0, 0.07)]
	var lagen := [[-0.3, 0.72, weiss], [0.72, 0.97, schwarz], [0.97, 1.0, weiss]]
	for la in lagen:
		var y0: float = la[0]
		var y1: float = la[1]
		var c: Color = la[2]
		for k in 3:
			var p0: Vector3 = g[k]
			var p1: Vector3 = g[(k + 1) % 3]
			var aussen := ((p0 + p1) * 0.5).normalized()
			_br_flaeche(st, [p0 + Vector3(0, y0, 0), p1 + Vector3(0, y0, 0), p1 + Vector3(0, y1, 0),
				p0 + Vector3(0, y1, 0)], c, aussen)
	_br_flaeche(st, [g[0] + Vector3(0, 1.0, 0), g[1] + Vector3(0, 1.0, 0), g[2] + Vector3(0, 1.0, 0)],
		weiss, Vector3.UP)
	# Rueckstrahler auf beiden Seiten, im schwarzen Band (lokal +-x = laengs zur Strasse)
	for sx: float in [1.0, -1.0]:
		var x := sx * 0.0605
		_br_flaeche(st, [Vector3(x, 0.78, -0.02), Vector3(x, 0.78, 0.02), Vector3(x, 0.90, 0.02),
			Vector3(x, 0.90, -0.02)], strahler, Vector3(sx, 0, 0))
	_pfosten_netz = st.commit()
	return _pfosten_netz


## Linker und rechter Rand am Punkt i (Normale aus den Nachbarpunkten -> Gehrung in Kurven).
static func _rand(pts: PackedVector2Array, i: int, w: float) -> Array:
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var d := (b - a).normalized()
	var quer := Vector2(-d.y, d.x) * w
	return [pts[i] + quer, pts[i] - quer]


# --- Bruecken --------------------------------------------------------------------------
## Je zusammenhaengender Brueckenspanne: Platte mit Gelaender, Pfeiler alle ~24 m bis auf
## den Grund, Kastenkollision fuer die Platte (landen und rollen geht).
static func _bruecken(parent: Node3D, terrain: TerrainWorld, pr: Array) -> void:
	var pts: PackedVector2Array = pr[0]
	var hh: PackedFloat32Array = pr[1]
	var br: PackedByteArray = pr[2]
	var w: float = pr[3]
	var i := 0
	while i < pts.size():
		if br[i] == 0:
			i += 1
			continue
		var a := i
		while i < pts.size() and br[i] == 1:
			i += 1
		var b := i - 1
		if b <= a:
			continue
		_bruecke(parent, terrain, pts, hh, a, b, w + 1.2)


## STEINBRUECKEN (2026-10-02, Nutzer: „die Strassen und Bruecken schauen gar nicht gut aus“).
## Vorher je 20-m-Abschnitt ein eigener Kasten, gegeneinander geknickt und versetzt, darauf
## schwarze Balken als Gelaender, darunter eine weisse Unterseite und duenne Pfeiler. Jetzt eine
## gemauerte BOGENBRUECKE bzw. ein VIADUKT: durchgehende Platte entlang des Laufs (Gehrung aus den
## Nachbarpunkten), Felder von 12-28 m (nach der Hoehe) mit Bogen, Bogenring und Zwickelmauern —
## wo kein Bogen Platz hat, gerade Untersicht —, Pfeiler mit Eisbrechern und Kaempfergesims,
## Widerlager an beiden Enden, Gesims, Bruestung mit Abdeckplatte. Shader shaders/bruecke.gdshader
## (Quadermauerwerk aus der Weltlage, COLOR.a = Mauerwerksanteil).
const BR_DECKE := 1.1            # Plattendicke unter der Fahrbahn
const BR_BRUESTUNG := 0.95       # Bruestung ueber der Fahrbahn
const BR_STEIN := Color(0.64, 0.58, 0.50, 1.0)
const BR_HELL := Color(0.77, 0.72, 0.63, 0.15)
const BR_BOGEN := Color(0.50, 0.46, 0.40, 1.0)
const BR_PFLASTER := Color(0.55, 0.52, 0.48, 0.45)


## Weg einer Bruecke: Stationen (m ab dem ersten Brueckenpunkt), Lage, Fahrbahnhoehe und
## Tangente je Punkt; dazwischen linear (Tangente gemittelt -> Gehrung in Kurven).
class BrWeg:
	var p := PackedVector2Array()
	var y := PackedFloat32Array()
	var t := PackedVector2Array()
	var s := PackedFloat32Array()

	func laenge() -> float:
		return s[s.size() - 1]

	## [Lage (Vector2), Fahrbahnhoehe, Tangente (Vector2)] bei Station st (auch jenseits der Enden).
	func bei(st: float) -> Array:
		var n := s.size()
		var i := 0
		if st >= s[n - 1]:
			i = n - 2
		elif st > 0.0:
			i = clampi(s.bsearch(st) - 1, 0, n - 2)
		var u := (st - s[i]) / maxf(s[i + 1] - s[i], 1.0e-4)
		var uc := clampf(u, 0.0, 1.0)
		return [p[i].lerp(p[i + 1], u), lerpf(y[i], y[i + 1], uc), t[i].lerp(t[i + 1], uc).normalized()]


static func _bruecke(parent: Node3D, terrain: TerrainWorld, pts: PackedVector2Array,
		hh: PackedFloat32Array, a: int, b: int, halb: float) -> void:
	var weg := BrWeg.new()
	var acc := 0.0
	for i in range(a, b + 1):
		if i > a:
			acc += pts[i].distance_to(pts[i - 1])
		weg.p.append(pts[i])
		weg.y.append(hh[i])
		weg.s.append(acc)
		var q0 := pts[maxi(i - 1, 0)]
		var q1 := pts[mini(i + 1, pts.size() - 1)]
		weg.t.append((q1 - q0).normalized())
	var lang := weg.laenge()
	if lang < 4.0:
		return
	# Felder nach der Hoehe: niedrige Bruecken kurze Felder, hohe Viadukte weite Boegen
	var hoehe := 0.0
	for i in range(a, b + 1):
		hoehe = maxf(hoehe, hh[i] - terrain.height_at(pts[i].x, pts[i].y))
	var feld := clampf(hoehe * 0.9, 12.0, 28.0)
	var n := maxi(1, roundi(lang / feld))
	var bp := clampf(lang / float(n) * 0.13, 1.8, 3.6)      # Pfeilerbreite laengs
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "Bruecke"
	# Felder zuerst (ihre Kaempferhoehe braucht das Pfeilergesims)
	var kaempfer := PackedFloat32Array()
	for k in n:
		var s0 := lang * float(k) / float(n) + (bp * 0.5 if k > 0 else 0.0)
		var s1 := lang * float(k + 1) / float(n) - (bp * 0.5 if k < n - 1 else 0.0)
		kaempfer.append(_br_feld(st, terrain, weg, s0, s1, halb))
	for k in range(1, n):
		var ks := minf(kaempfer[k - 1], kaempfer[k])
		_br_pfeiler(st, body, terrain, weg, lang * float(k) / float(n), bp, halb, ks)
	_br_widerlager(st, body, terrain, weg, 0.0, -1.0, halb)
	_br_widerlager(st, body, terrain, weg, lang, 1.0, halb)
	_br_platte(st, weg, halb)
	# Kollision der Platte je Abschnitt (landen und rollen)
	for i in range(a, b):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var d := p1 - p0
		var l := d.length()
		if l < 0.1:
			continue
		var m := (p0 + p1) * 0.5
		var koll := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(l + 0.6, BR_DECKE, halb * 2.0)
		koll.shape = box
		koll.transform = Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)),
			Vector3(m.x, (hh[i] + hh[i + 1]) * 0.5 - BR_DECKE * 0.5, m.y))
		body.add_child(koll)
	var mi := MeshInstance3D.new()
	# eindeutig benennen — gleiche Namen unter einem Elternknoten benennt Godot in "@...@" um
	mi.name = "Brueckenbau_%d_%d" % [int(pts[a].x), int(pts[a].y)]
	body.name = "Bruecke_%d_%d" % [int(pts[a].x), int(pts[a].y)]
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bruecke.gdshader")
	mi.material_override = mat
	parent.add_child(mi)
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)


## Punkt im Bruecken-Querschnitt: Station st, quer (+ = links), Hoehe y absolut.
static func _br_punkt(weg: BrWeg, st: float, quer: float, y: float) -> Vector3:
	var l: Array = weg.bei(st)
	var pp: Vector2 = l[0]
	var tg: Vector2 = l[2]
	var nn := Vector2(-tg.y, tg.x)
	var q := pp + nn * quer
	return Vector3(q.x, y, q.y)


## Linke Normale (3D) bei Station st.
static func _br_links(weg: BrWeg, st: float) -> Vector3:
	var tg: Vector2 = weg.bei(st)[2]
	return Vector3(-tg.y, 0.0, tg.x)


## Vier- oder Dreieck mit Flaechennormale, so gewickelt, dass es nach `aussen` zeigt.
static func _br_flaeche(st: SurfaceTool, v: Array, col: Color, aussen: Vector3) -> void:
	var p0: Vector3 = v[0]
	var p1v: Vector3 = v[1]
	var p2v: Vector3 = v[2]
	var nrm: Vector3 = (p1v - p0).cross(p2v - p0)
	if v.size() == 4 and nrm.length_squared() < 1.0e-10:
		var p3v: Vector3 = v[3]
		nrm = (p2v - p0).cross(p3v - p0)
	if nrm.length_squared() < 1.0e-10:
		return
	nrm = nrm.normalized()
	if nrm.dot(aussen) < 0.0:
		nrm = -nrm
	st.set_color(col)
	st.set_normal(nrm)
	var dreiecke := [[0, 1, 2]] if v.size() == 3 else [[0, 1, 2], [0, 2, 3]]
	for tri in dreiecke:
		var q0: Vector3 = v[tri[0]]
		var q1: Vector3 = v[tri[1]]
		var q2: Vector3 = v[tri[2]]
		# Godot: Vorderseite im Uhrzeigersinn von aussen -> Kreuzprodukt zeigt nach innen
		if (q1 - q0).cross(q2 - q0).dot(nrm) > 0.0:
			var tmp := q1
			q1 = q2
			q2 = tmp
		st.add_vertex(q0)
		st.add_vertex(q1)
		st.add_vertex(q2)


## EIN FELD zwischen s0 und s1 (Pfeiler- bzw. Widerlagerflanken). Mit Platz ein Bogen (elliptisch,
## Kaempfer ueber dem Grund, Scheitel 0,45 m unter der Platte) samt Bogenring und Zwickelmauern,
## sonst eine gerade Untersicht. Liefert die Kaempferhoehe (fuer das Pfeilergesims).
static func _br_feld(st: SurfaceTool, terrain: TerrainWorld, weg: BrWeg, s0: float, s1: float,
		halb: float) -> float:
	var weite := s1 - s0
	var schritte := maxi(6, ceili(weite / 1.0))
	var yu_min := INF
	var g_max := -INF
	for j in schritte + 1:
		var sj := lerpf(s0, s1, float(j) / float(schritte))
		var l: Array = weg.bei(sj)
		yu_min = minf(yu_min, float(l[1]) - BR_DECKE)
		var pp: Vector2 = l[0]
		g_max = maxf(g_max, terrain.height_at(pp.x, pp.y))
	var scheitel := yu_min - 0.45
	var kaempfer := maxf(g_max + 1.2, scheitel - weite * 0.5)
	var stich := scheitel - kaempfer
	var bogen := stich >= 1.2
	var mitte_s := (s0 + s1) * 0.5
	# Bogenlinie je Schritt: (Station, Hoehe der Untersicht)
	var ys := PackedFloat32Array()
	var ss := PackedFloat32Array()
	for j in schritte + 1:
		var tt := float(j) / float(schritte)
		var sj := lerpf(s0, s1, tt)
		ss.append(sj)
		var yu := float(weg.bei(sj)[1]) - BR_DECKE
		if bogen:
			ys.append(kaempfer + stich * sqrt(maxf(0.0, 1.0 - (2.0 * tt - 1.0) * (2.0 * tt - 1.0))))
		else:
			ys.append(yu)
	var mitte_p := _br_punkt(weg, mitte_s, 0.0, kaempfer)
	for j in schritte:
		var sa := ss[j]
		var sb := ss[j + 1]
		var ya := ys[j]
		var yb := ys[j + 1]
		var yua := float(weg.bei(sa)[1]) - BR_DECKE
		var yub := float(weg.bei(sb)[1]) - BR_DECKE
		var la := _br_punkt(weg, sa, halb, ya)
		var lb := _br_punkt(weg, sb, halb, yb)
		var ra := _br_punkt(weg, sa, -halb, ya)
		var rb := _br_punkt(weg, sb, -halb, yb)
		# Untersicht (Leibung) — zeigt in die Oeffnung
		var innen := mitte_p - (la + rb) * 0.5
		if not bogen:
			innen = Vector3.DOWN
		_br_flaeche(st, [la, ra, rb, lb], BR_BOGEN, innen)
		if not bogen:
			continue
		var nl := _br_links(weg, (sa + sb) * 0.5)
		for seite: float in [1.0, -1.0]:
			# Zwickelmauer zwischen Bogen und Platte
			_br_flaeche(st, [_br_punkt(weg, sa, seite * halb, ya), _br_punkt(weg, sa, seite * halb, yua),
				_br_punkt(weg, sb, seite * halb, yub), _br_punkt(weg, sb, seite * halb, yb)],
				BR_STEIN, nl * seite)
			# Bogenring: 0,6 m breit (radial zur Ellipse), 0,1 m vor der Mauer
			var ra_a := _br_ring(weg, sa, ya, mitte_s, kaempfer, weite, stich, seite * (halb + 0.1))
			var ra_b := _br_ring(weg, sb, yb, mitte_s, kaempfer, weite, stich, seite * (halb + 0.1))
			var ia := _br_punkt(weg, sa, seite * (halb + 0.1), ya)
			var ib := _br_punkt(weg, sb, seite * (halb + 0.1), yb)
			_br_flaeche(st, [ia, ra_a, ra_b, ib], Color(BR_HELL.r, BR_HELL.g, BR_HELL.b, 1.0), nl * seite)
			# Leibung des Rings (die 0,1 m zwischen Mauer und Ringvorderkante)
			_br_flaeche(st, [_br_punkt(weg, sa, seite * halb, ya), ia, ib, _br_punkt(weg, sb, seite * halb, yb)],
				BR_BOGEN, innen)
	return kaempfer if bogen else yu_min


## Aeusserer Punkt des Bogenrings bei Station st (radial zur Ellipse um mitte_s/kaempfer).
static func _br_ring(weg: BrWeg, st: float, y: float, mitte_s: float, kaempfer: float, weite: float,
		stich: float, quer: float) -> Vector3:
	var ah := weite * 0.5
	var dx := (st - mitte_s) / (ah * ah)
	var dy := (y - kaempfer) / (stich * stich)
	var d := Vector2(dx, dy).normalized() * 0.6
	return _br_punkt(weg, st + d.x, quer, y + d.y)


## PFEILER an Station sp: Schaft bis unter die Platte, Eisbrecher (spitz) quer zum Weg, Gesims auf
## Kaempferhoehe, Fuss 1,5 m im Grund. Kollision als Kasten.
static func _br_pfeiler(st: SurfaceTool, body: StaticBody3D, terrain: TerrainWorld, weg: BrWeg,
		sp: float, bp: float, halb: float, kaempfer: float) -> void:
	var l: Array = weg.bei(sp)
	var yu := float(l[1]) - BR_DECKE
	var hq := halb + 0.3
	var g := INF
	for e in [[-1.0, -1.0], [1.0, -1.0], [-1.0, 1.0], [1.0, 1.0], [0.0, 0.0]]:
		var q := _br_punkt(weg, sp + float(e[0]) * bp * 0.5, float(e[1]) * (hq + 1.6), 0.0)
		g = minf(g, terrain.height_at(q.x, q.z))
	var fuss := g - 1.5
	if yu - fuss < 1.0:
		return
	var nl := _br_links(weg, sp)
	var tg3 := Vector3(float(l[2].x), 0.0, float(l[2].y))
	var ecken := func(y: float, quer_v: float, laengs_v: float) -> Array:
		return [_br_punkt(weg, sp - laengs_v, quer_v, y), _br_punkt(weg, sp + laengs_v, quer_v, y),
			_br_punkt(weg, sp + laengs_v, -quer_v, y), _br_punkt(weg, sp - laengs_v, -quer_v, y)]
	var unten: Array = ecken.call(fuss, hq, bp * 0.5)
	var oben: Array = ecken.call(yu, hq, bp * 0.5)
	# Schaft: vier Seiten (0-1 links, 1-2 vorn, 2-3 rechts, 3-0 hinten)
	var aussen := [nl, tg3, -nl, -tg3]
	for k in 4:
		var k2 := (k + 1) % 4
		_br_flaeche(st, [unten[k], unten[k2], oben[k2], oben[k]], BR_STEIN, aussen[k])
	# Eisbrecher an beiden Querenden: spitzes Prisma bis halbe Hoehe, Dach geneigt
	var y_eis := minf(fuss + maxf(3.5, (yu - fuss) * 0.45), kaempfer - 0.3)
	if y_eis > g + 0.5:
		for seite: float in [1.0, -1.0]:
			var a0 := _br_punkt(weg, sp - bp * 0.5, seite * hq, fuss)
			var a1 := _br_punkt(weg, sp + bp * 0.5, seite * hq, fuss)
			var sp0 := _br_punkt(weg, sp, seite * (hq + 1.6), fuss)
			var b0 := _br_punkt(weg, sp - bp * 0.5, seite * hq, y_eis)
			var b1 := _br_punkt(weg, sp + bp * 0.5, seite * hq, y_eis)
			var sp1 := _br_punkt(weg, sp, seite * (hq + 1.6), y_eis - 0.6)
			_br_flaeche(st, [a0, sp0, sp1, b0], BR_STEIN, (nl * seite - tg3).normalized())
			_br_flaeche(st, [sp0, a1, b1, sp1], BR_STEIN, (nl * seite + tg3).normalized())
			var dach := BR_HELL
			_br_flaeche(st, [b0, sp1, b1], dach, Vector3.UP + nl * seite * 0.5)
	# Kaempfergesims: umlaufendes Band, 0,15 m vorstehend
	if kaempfer > fuss + 1.0 and kaempfer < yu - 0.3:
		var g0: Array = ecken.call(kaempfer - 0.18, hq + 0.15, bp * 0.5 + 0.15)
		var g1: Array = ecken.call(kaempfer + 0.18, hq + 0.15, bp * 0.5 + 0.15)
		for k in 4:
			var k2 := (k + 1) % 4
			_br_flaeche(st, [g0[k], g0[k2], g1[k2], g1[k]], BR_HELL, aussen[k])
		_br_flaeche(st, [g1[0], g1[1], g1[2], g1[3]], BR_HELL, Vector3.UP)
		_br_flaeche(st, [g0[0], g0[1], g0[2], g0[3]], BR_HELL, Vector3.DOWN)
	var koll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(bp, yu - fuss, hq * 2.0)
	koll.shape = box
	var pp: Vector2 = l[0]
	koll.transform = Transform3D(Basis(Vector3.UP, atan2(-float(l[2].y), float(l[2].x))),
		Vector3(pp.x, (yu + fuss) * 0.5, pp.y))
	body.add_child(koll)


## WIDERLAGER am Brueckenende (Station se, richtung -1 = Anfang, +1 = Ende): Mauerblock von der
## Bogenflanke 5 m in den Damm, bis unter die Platte, etwas breiter als die Bruecke.
static func _br_widerlager(st: SurfaceTool, body: StaticBody3D, terrain: TerrainWorld, weg: BrWeg,
		se: float, richtung: float, halb: float) -> void:
	var yu := float(weg.bei(se)[1]) - BR_DECKE
	var hq := halb + 0.6
	var s_innen := se
	var s_aussen := se + richtung * 5.0
	var g := INF
	for q in [_br_punkt(weg, s_innen, hq, 0.0), _br_punkt(weg, s_innen, -hq, 0.0),
			_br_punkt(weg, s_aussen, hq, 0.0), _br_punkt(weg, s_aussen, -hq, 0.0)]:
		g = minf(g, terrain.height_at(q.x, q.z))
	var fuss := g - 1.5
	if yu - fuss < 0.8:
		return
	var nl := _br_links(weg, se)
	var tg: Vector2 = weg.bei(se)[2]
	var vorn := Vector3(tg.x, 0.0, tg.y) * -richtung      # zeigt in die Bruecke
	var e := func(st_v: float, quer: float, y: float) -> Vector3:
		return _br_punkt(weg, st_v, quer, y)
	# Stirn zur Bruecke, zwei Seiten
	_br_flaeche(st, [e.call(s_innen, hq, fuss), e.call(s_innen, -hq, fuss), e.call(s_innen, -hq, yu),
		e.call(s_innen, hq, yu)], BR_STEIN, vorn)
	for seite: float in [1.0, -1.0]:
		_br_flaeche(st, [e.call(s_innen, seite * hq, fuss), e.call(s_aussen, seite * hq, fuss),
			e.call(s_aussen, seite * hq, yu), e.call(s_innen, seite * hq, yu)], BR_STEIN, nl * seite)
	var pp: Vector2 = weg.bei((s_innen + s_aussen) * 0.5)[0]
	var koll := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, yu - fuss, hq * 2.0)
	koll.shape = box
	koll.transform = Transform3D(Basis(Vector3.UP, atan2(-tg.y, tg.x)), Vector3(pp.x, (yu + fuss) * 0.5, pp.y))
	body.add_child(koll)


## PLATTE ueber die ganze Laenge: Stirn (Mauerwerk), Gesims, Bruestung mit Abdeckplatte, Pflaster
## zwischen Fahrbahnband und Bruestung, gerade Untersicht dort, wo kein Feld sie deckt (Enden).
static func _br_platte(st: SurfaceTool, weg: BrWeg, halb: float) -> void:
	var lang := weg.laenge()
	var s_von := -0.6
	var s_bis := lang + 0.6
	var schritte := maxi(2, ceili((s_bis - s_von) / 2.0))
	const GES_U := 0.44            # Gesims: Unterkante unter der Fahrbahn
	const GES_O := 0.10            # Gesims: Oberkante unter der Fahrbahn
	const GES_VOR := 0.20
	const BR_DICKE := 0.45
	const DECK_U := 0.12           # Abdeckplatte: Dicke
	const DECK_VOR := 0.07
	for j in schritte:
		var sa := lerpf(s_von, s_bis, float(j) / float(schritte))
		var sb := lerpf(s_von, s_bis, float(j + 1) / float(schritte))
		var nl := _br_links(weg, (sa + sb) * 0.5)
		var p := func(st_v: float, quer: float, dy: float) -> Vector3:
			return _br_punkt(weg, st_v, quer, float(weg.bei(st_v)[1]) + dy)
		# Pflaster (die Mitte deckt das Fahrbahnband)
		_br_flaeche(st, [p.call(sa, halb, 0.0), p.call(sa, -halb, 0.0), p.call(sb, -halb, 0.0),
			p.call(sb, halb, 0.0)], BR_PFLASTER, Vector3.UP)
		for seite: float in [1.0, -1.0]:
			var q := seite
			# Stirn unter dem Gesims
			_br_flaeche(st, [p.call(sa, q * halb, -BR_DECKE), p.call(sb, q * halb, -BR_DECKE),
				p.call(sb, q * halb, -GES_U), p.call(sa, q * halb, -GES_U)], BR_STEIN, nl * q)
			# Gesims: Unterseite, Vorderseite, Oberseite
			_br_flaeche(st, [p.call(sa, q * halb, -GES_U), p.call(sb, q * halb, -GES_U),
				p.call(sb, q * (halb + GES_VOR), -GES_U), p.call(sa, q * (halb + GES_VOR), -GES_U)],
				BR_HELL, Vector3.DOWN)
			_br_flaeche(st, [p.call(sa, q * (halb + GES_VOR), -GES_U), p.call(sb, q * (halb + GES_VOR), -GES_U),
				p.call(sb, q * (halb + GES_VOR), -GES_O), p.call(sa, q * (halb + GES_VOR), -GES_O)],
				BR_HELL, nl * q)
			_br_flaeche(st, [p.call(sa, q * halb, -GES_O), p.call(sb, q * halb, -GES_O),
				p.call(sb, q * (halb + GES_VOR), -GES_O), p.call(sa, q * (halb + GES_VOR), -GES_O)],
				BR_HELL, Vector3.UP)
			# Bruestung aussen (buendig mit der Stirn) und innen
			_br_flaeche(st, [p.call(sa, q * halb, -GES_O), p.call(sb, q * halb, -GES_O),
				p.call(sb, q * halb, BR_BRUESTUNG), p.call(sa, q * halb, BR_BRUESTUNG)], BR_STEIN, nl * q)
			_br_flaeche(st, [p.call(sa, q * (halb - BR_DICKE), 0.0), p.call(sb, q * (halb - BR_DICKE), 0.0),
				p.call(sb, q * (halb - BR_DICKE), BR_BRUESTUNG), p.call(sa, q * (halb - BR_DICKE), BR_BRUESTUNG)],
				BR_STEIN, -nl * q)
			# Abdeckplatte: oben, aussen, innen, Unterseiten der Ueberstaende
			var ai := q * (halb - BR_DICKE - DECK_VOR)
			var aa := q * (halb + DECK_VOR)
			var yo := BR_BRUESTUNG + DECK_U
			_br_flaeche(st, [p.call(sa, ai, yo), p.call(sb, ai, yo), p.call(sb, aa, yo), p.call(sa, aa, yo)],
				BR_HELL, Vector3.UP)
			_br_flaeche(st, [p.call(sa, aa, BR_BRUESTUNG), p.call(sb, aa, BR_BRUESTUNG), p.call(sb, aa, yo),
				p.call(sa, aa, yo)], BR_HELL, nl * q)
			_br_flaeche(st, [p.call(sa, ai, BR_BRUESTUNG), p.call(sb, ai, BR_BRUESTUNG), p.call(sb, ai, yo),
				p.call(sa, ai, yo)], BR_HELL, -nl * q)
			_br_flaeche(st, [p.call(sa, aa, BR_BRUESTUNG), p.call(sb, aa, BR_BRUESTUNG),
				p.call(sb, q * halb, BR_BRUESTUNG), p.call(sa, q * halb, BR_BRUESTUNG)], BR_HELL, Vector3.DOWN)
			_br_flaeche(st, [p.call(sa, ai, BR_BRUESTUNG), p.call(sb, ai, BR_BRUESTUNG),
				p.call(sb, q * (halb - BR_DICKE), BR_BRUESTUNG), p.call(sa, q * (halb - BR_DICKE), BR_BRUESTUNG)],
				BR_HELL, Vector3.DOWN)
	# Stirnseiten der Bruestungen an beiden Enden
	for se: float in [s_von, s_bis]:
		var vorn := Vector3(float(weg.bei(se)[2].x), 0.0, float(weg.bei(se)[2].y)) * (1.0 if se > 0.0 else -1.0)
		var y0 := float(weg.bei(se)[1])
		for seite: float in [1.0, -1.0]:
			_br_flaeche(st, [_br_punkt(weg, se, seite * (halb - BR_DICKE), y0),
				_br_punkt(weg, se, seite * halb, y0),
				_br_punkt(weg, se, seite * halb, y0 + BR_BRUESTUNG + DECK_U),
				_br_punkt(weg, se, seite * (halb - BR_DICKE), y0 + BR_BRUESTUNG + DECK_U)], BR_HELL, vorn)


## Gedrehter Quader (Mitte c, Groesse g, Drehung bs) — gleiche Flaechenfolge wie
## Landmarks._box_geo, nur jede Ecke gedreht.
static func _quader(st: SurfaceTool, c: Vector3, g: Vector3, bs: Basis, col: Color) -> void:
	var h := g * 0.5
	var e := func(x: float, y: float, z: float) -> Vector3:
		return c + bs * Vector3(x * h.x, y * h.y, z * h.z)
	var flaechen := [
		[e.call(-1, -1, -1), e.call(-1, 1, -1), e.call(1, 1, -1), e.call(1, -1, -1), 1.0],
		[e.call(1, -1, 1), e.call(1, 1, 1), e.call(-1, 1, 1), e.call(-1, -1, 1), 0.90],
		[e.call(-1, -1, 1), e.call(-1, 1, 1), e.call(-1, 1, -1), e.call(-1, -1, -1), 0.82],
		[e.call(1, -1, -1), e.call(1, 1, -1), e.call(1, 1, 1), e.call(1, -1, 1), 0.95],
		[e.call(-1, 1, -1), e.call(-1, 1, 1), e.call(1, 1, 1), e.call(1, 1, -1), 1.05],
		[e.call(-1, -1, 1), e.call(-1, -1, -1), e.call(1, -1, -1), e.call(1, -1, 1), 0.72],
	]
	for fl in flaechen:
		var k: float = fl[4]
		st.set_color(Color(col.r * k, col.g * k, col.b * k))
		for idx in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(fl[idx])


# --- Doerfer ---------------------------------------------------------------------------
## Richtung der Strasse, die dem Punkt am naechsten liegt (fuer die Ausrichtung des Dorfs).
static func _richtung_bei(terrain: TerrainWorld, p: Vector2) -> Vector2:
	var best := INF
	var dir := Vector2(1, 0)
	for pr in terrain.strassen_profile:
		var pts: PackedVector2Array = pr[0]
		for i in range(pts.size() - 1):
			var d := pts[i].distance_squared_to(p)
			if d < best:
				best = d
				dir = (pts[i + 1] - pts[i]).normalized()
	return dir


static func _dorf(parent: Node3D, knoten: Node3D, terrain: TerrainWorld, d: Array, zone: Dictionary,
		mat_neben: Material) -> void:
	var name := String(d[0])
	var p: Vector2 = d[1]
	var gr := int(d[2])
	var mitte := Vector3(p.x, float(zone["y"]), p.y)
	var dir := _richtung_bei(terrain, p)
	# CityBuilder dreht die Planung mit Basis(UP, dreh): lokal +x -> Welt (cos, -sin)
	var dreh := atan2(-dir.y, dir.x)
	var kueste := false
	for k in 12:
		var q := p + Vector2(cos(TAU * k / 12.0), sin(TAU * k / 12.0)) * 700.0
		if terrain.height_at(q.x, q.y) < TerrainWorld.SEA_Y:
			kueste = true
	var fluss := false
	if not terrain.rivers.is_empty():
		fluss = terrain._fluss_naechst(p.x, p.y).x < 900.0
	var plan := plan_strassendorf(name, gr, kueste, fluss)
	var h0 := CityBuilder.karte_haeuser.size()
	var s0 := CityBuilder.karte_strassen.size()
	var dorfstr := _dorfstrasse(knoten, terrain, p, dir, LAENGE[gr] + 10.0, mat_neben)
	# Nichts auf eine Strasse stellen: an Kreuzungen laufen weitere Strassen durchs Dorf,
	# und die Dorfstrasse selbst kruemmt sich.
	var frei: Array = []
	var bs := Basis(Vector3.UP, dreh)
	for e in plan:
		var lok: Vector2 = e["pos"]
		var wv: Vector3 = bs * Vector3(lok.x, 0.0, lok.y)
		if terrain.strasse_abstand(p.x + wv.x, p.y + wv.z) < float(e.get("frei", 11.0)):
			continue
		frei.append(e)
	CityBuilder.build(parent, terrain, mitte, frei, "Dorf_" + name, dreh)
	# Baeume, Obstwiesen, Dorflinde, Hofzufahrten (scripts/Ortsgruen.gd)
	Ortsgruen.strassendorf(parent, terrain, name, p, dir, gr, LAENGE[gr], h0, s0, dorfstr, frei, dreh)


## DORFSTRASSE entlang der Dorfachse, wo nicht schon eine Landstrasse liegt. Die Strassen des
## Netzes ENDEN meist in der Dorfmitte — ohne dieses Stueck stuenden die Haeuser auf der
## anderen Seite an keiner Strasse. Knapp unter dem Landstrassenband (keine Tiefenkaempfe).
static func _dorfstrasse(knoten: Node3D, terrain: TerrainWorld, p: Vector2, dir: Vector2,
		halb: float, mat: Material) -> Array:
	var stuecke: Array = []     # [a, b, halbe Breite] fuer Ortsgruen
	var lauf := PackedVector2Array()
	var s := -halb
	while s <= halb + 0.01:
		var q := p + dir * s
		var frei := terrain.strasse_abstand(q.x, q.y) > TerrainWorld.STRASSE_B_HAUPT + 0.3
		if frei:
			lauf.append(q)
		if (not frei or s + 10.0 > halb + 0.01) and lauf.size() >= 2:
			var hh := PackedFloat32Array()
			for q2 in lauf:
				hh.append(terrain.height_at(q2.x, q2.y) - 0.03)
			var br := PackedByteArray()
			br.resize(lauf.size())
			_band(knoten, [lauf, hh, br, TerrainWorld.STRASSE_B_NEBEN], mat)
			stuecke.append([lauf[0], lauf[lauf.size() - 1], TerrainWorld.STRASSE_B_NEBEN + BANKETT_NEBEN])
		if not frei:
			lauf = PackedVector2Array()
		s += 10.0
	return stuecke


## STRASSENDORF: Haeuser beidseits der Dorfstrasse (lokal x), Fronten zur Fahrbahn,
## Hoefe mit Scheune/Stall dahinter. In der Mitte Kirche bzw. Kapelle und Gasthaus, im
## Marktflecken auch Rathaus und Stadthaeuser. Am Rand Muehle, Silo oder — an der
## Kueste — Lotsenhaus und Speicher. Deterministisch aus dem Namen.
static func plan_strassendorf(name: String, gr: int, kueste: bool, fluss: bool) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var L: float = LAENGE[gr]
	var plan: Array = []
	if gr == 2:
		plan.append({"typ": "Haus_Kirche", "pos": Vector2(0, -30), "yaw": 0.0})
		plan.append({"typ": "Haus_Rathaus", "pos": Vector2(42, 26), "yaw": PI})
		plan.append({"typ": "Haus_Gasthaus", "pos": Vector2(-40, 24), "yaw": PI})
	elif gr == 1:
		plan.append({"typ": "Haus_Kapelle", "pos": Vector2(0, -24), "yaw": 0.0})
		plan.append({"typ": "Haus_Gasthaus", "pos": Vector2(30, 22), "yaw": PI})
	var mitte_frei := 58.0 if gr == 2 else (40.0 if gr == 1 else 0.0)
	for seite in [-1.0, 1.0]:
		var x := -L + rng.randf_range(0.0, 12.0)
		while x < L:
			if absf(x) > mitte_frei:
				var innen := 1.0 - absf(x) / L
				var typ := "Haus_Bauernhaus"
				var r := rng.randf()
				if gr == 2 and innen > 0.5:
					typ = ["Haus_Stadthaus2", "Haus_Stadthaus3", "Haus_Eckhaus", "Haus_Fachwerk"][
						rng.randi() % 4]
				elif r < 0.30:
					typ = "Haus_Fachwerk"
				elif r < 0.50:
					typ = "Haus_Kate"
				elif r < 0.62 and gr > 0:
					typ = "Haus_Villa" if rng.randf() < 0.3 else "Haus_Reihenhaus"
				var zz: float = seite * rng.randf_range(15.0, 19.0)
				plan.append({"typ": typ, "pos": Vector2(x, zz),
					"yaw": (0.0 if seite < 0.0 else PI) + rng.randf_range(-0.08, 0.08)})
				if typ == "Haus_Bauernhaus" and rng.randf() < 0.75:
					plan.append({"typ": "Haus_Scheune" if rng.randf() < 0.6 else "Haus_Stall",
						"pos": Vector2(x + rng.randf_range(-6.0, 6.0), seite * rng.randf_range(38.0, 46.0)),
						"yaw": rng.randf_range(-0.3, 0.3) + (PI * 0.5 if rng.randf() < 0.5 else 0.0),
						"frei": 16.0})
			x += rng.randf_range(24.0, 34.0) if gr > 0 else rng.randf_range(30.0, 46.0)
	# Rand
	var rand := L + 30.0
	if kueste:
		plan.append({"typ": "Haus_Lotsenhaus", "pos": Vector2(rand, -34), "yaw": 0.0})
		if gr > 0:
			plan.append({"typ": "Haus_Speicher", "pos": Vector2(-rand, 36), "yaw": PI})
	elif fluss:
		plan.append({"typ": "Haus_Wassermuehle", "pos": Vector2(-rand, 38), "yaw": PI})
	if gr > 0:
		plan.append({"typ": "Haus_Windmuehle" if rng.randf() < 0.6 else "Haus_Silo",
			"pos": Vector2(rand * (1.0 if rng.randf() < 0.5 else -1.0), 52.0 * (1.0 if rng.randf() < 0.5 else -1.0)),
			"yaw": rng.randf() * TAU, "frei": 18.0})
	return plan
