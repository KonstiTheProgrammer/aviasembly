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


## Strassen fuer TerrainWorld (vor setup()).
static func strassen_daten() -> Array:
	var raus: Array = []
	for s in StrassenDaten.STRASSEN:
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
		raus.append({"pos": Vector3(p.x, 0.0, p.y), "r_flat": z[0], "r_blend": z[1], "y": 0.0})
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
	var knoten := Node3D.new()
	knoten.name = "Landstrassen"
	parent.add_child(knoten)
	var mat_haupt := _material(false)
	var mat_neben := _material(true)
	for i in terrain.strassen_profile.size():
		var pr: Array = terrain.strassen_profile[i]
		var neben: bool = terrain.strassen[i].get("neben", false)
		_band(knoten, pr, mat_neben if neben else mat_haupt)
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
## UV: u quer (0 links .. 1 rechts), v = Laufmeter.
static func _band(parent: Node3D, pr: Array, mat: Material) -> void:
	var pts: PackedVector2Array = pr[0]
	var hh: PackedFloat32Array = pr[1]
	var w: float = pr[3]
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
		# DAS STUECK LIEGT UM SEINE EIGENE MITTE: Godot misst die Sichtweite (visibility_range)
		# ab dem Ursprung des Knotens. Mit Weltkoordinaten am Ursprung verschwanden alle
		# Baender weiter als 3,5 km vom Weltmittelpunkt — also fast das ganze Netz.
		var mitte := (pts[i0] + pts[i1]) * 0.5
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(i0, i1):
			var q := [_rand(pts, i, w), _rand(pts, i + 1, w)]
			var y0 := hh[i] + BAND_Y
			var y1 := hh[i + 1] + BAND_Y
			var l0: Vector2 = q[0][0] - mitte
			var r0: Vector2 = q[0][1] - mitte
			var l1: Vector2 = q[1][0] - mitte
			var r1: Vector2 = q[1][1] - mitte
			var v := [Vector3(l0.x, y0, l0.y), Vector3(r0.x, y0, r0.y),
				Vector3(r1.x, y1, r1.y), Vector3(l1.x, y1, l1.y)]
			var uv := [Vector2(0.0, lauf[i]), Vector2(1.0, lauf[i]),
				Vector2(1.0, lauf[i + 1]), Vector2(0.0, lauf[i + 1])]
			# WICKLUNG wie CityBuilder._band (dort nachgewiesen: die umgekehrte Reihenfolge
			# zeigte nach unten und wurde komplett weggekullt): (r0, r1, l1), (r0, l1, l0).
			for t in [[1, 2, 3], [1, 3, 0]]:
				for k in t:
					st.set_normal(Vector3.UP)
					st.set_uv(uv[k])
					st.add_vertex(v[k])
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
		i0 = i1


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


static func _bruecke(parent: Node3D, terrain: TerrainWorld, pts: PackedVector2Array,
		hh: PackedFloat32Array, a: int, b: int, halb: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stein := Color(0.72, 0.68, 0.61)
	var dunkel := Color(0.56, 0.53, 0.49)
	var body := StaticBody3D.new()
	body.name = "Bruecke"
	for i in range(a, b):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var d := p1 - p0
		var l := d.length()
		if l < 0.1:
			continue
		var mitte := (p0 + p1) * 0.5
		var y := (hh[i] + hh[i + 1]) * 0.5
		var yaw := atan2(-d.y, d.x)
		var bs := Basis(Vector3.UP, yaw)
		var c := Vector3(mitte.x, y, mitte.y)
		# Platte (Oberkante = Fahrbahnbett) und Gelaender
		_quader(st, c + Vector3(0, -0.7, 0), Vector3(l + 0.6, 1.4, halb * 2.0), bs, stein)
		for sx in [-1.0, 1.0]:
			_quader(st, c + bs * Vector3(0, 0.55, sx * (halb - 0.25)),
				Vector3(l + 0.6, 1.1, 0.5), bs, dunkel)
		var koll := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(l + 0.6, 1.4, halb * 2.0)
		koll.shape = box
		koll.transform = Transform3D(bs, c + Vector3(0, -0.7, 0))
		body.add_child(koll)
		# Pfeiler jeden zweiten Stuetzpunkt (ca. 40 m), bis 1 m unter den Grund
		if (i - a) % 2 == 1:
			var grund := terrain.height_at(p0.x, p0.y)
			var ph := y - 1.4 - grund + 1.0
			if ph > 1.0:
				_quader(st, Vector3(p0.x, grund - 1.0 + ph * 0.5, p0.y),
					Vector3(2.4, ph, halb * 1.4), Basis(Vector3.UP, yaw), dunkel)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Brueckenbau"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	mi.material_override = mat
	parent.add_child(mi)
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)


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
	_dorfstrasse(knoten, terrain, p, dir, LAENGE[gr] + 10.0, mat_neben)
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


## DORFSTRASSE entlang der Dorfachse, wo nicht schon eine Landstrasse liegt. Die Strassen des
## Netzes ENDEN meist in der Dorfmitte — ohne dieses Stueck stuenden die Haeuser auf der
## anderen Seite an keiner Strasse. Knapp unter dem Landstrassenband (keine Tiefenkaempfe).
static func _dorfstrasse(knoten: Node3D, terrain: TerrainWorld, p: Vector2, dir: Vector2,
		halb: float, mat: Material) -> void:
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
		if not frei:
			lauf = PackedVector2Array()
		s += 10.0


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
