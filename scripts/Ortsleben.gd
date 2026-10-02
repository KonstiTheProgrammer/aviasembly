## ORTSLEBEN (2026-10-02, Nutzer: „mach die Stadt und die Doerfer viel besser“). Nach dem Ortsgruen
## standen Stadt und Doerfer wie Modellbahn ohne Figuren da: kein Auto, kein Tier, keine Bank.
## HIER (statisch, deterministisch): Netze aus Quadern mit Vertexfarbe (gemalt, Stil der Welt),
## gezeichnet mit dem Material der Bruecken (shaders/bruecke.gdshader, COLOR.a = 0 -> glatt,
## klares Licht wie das Gelaende), je Art eine MultiMesh je Ort, Farbe je Instanz.
##   * AUTOS: an den Stadtstrassen am Bordstein geparkt, in den Doerfern vor manchen Haeusern
##   * WEIDEN am Dorfrand: Holzzaun, Kuehe (schwarz-weiss, braun) oder Schafe, Tränke
##   * BAENKE an der Kirche und am Dorfplatz
class_name Ortsleben
extends RefCounted

static var _netze: Dictionary = {}
static var bilanz := [0, 0, 0, 0]     # Autos, Tiere, Weiden, Zeit (us)


# --- Netze ------------------------------------------------------------------------------
## Quader (Mitte c, Groesse g, Drehung um y) mit Farbe col; Flaechen nach aussen gewickelt.
static func _quader(st: SurfaceTool, c: Vector3, g: Vector3, col: Color, yaw := 0.0, schraeg := 0.0) -> void:
	var h := g * 0.5
	var bs := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, schraeg)
	var e := func(x: float, y: float, z: float) -> Vector3:
		return c + bs * Vector3(x * h.x, y * h.y, z * h.z)
	var flaechen := [
		[[-1, -1, -1], [-1, 1, -1], [1, 1, -1], [1, -1, -1], Vector3(0, 0, -1), 0.88],
		[[1, -1, 1], [1, 1, 1], [-1, 1, 1], [-1, -1, 1], Vector3(0, 0, 1), 0.92],
		[[-1, -1, 1], [-1, 1, 1], [-1, 1, -1], [-1, -1, -1], Vector3(-1, 0, 0), 0.84],
		[[1, -1, -1], [1, 1, -1], [1, 1, 1], [1, -1, 1], Vector3(1, 0, 0), 0.95],
		[[-1, 1, -1], [-1, 1, 1], [1, 1, 1], [1, 1, -1], Vector3(0, 1, 0), 1.0],
		[[-1, -1, 1], [-1, -1, -1], [1, -1, -1], [1, -1, 1], Vector3(0, -1, 0), 0.7],
	]
	for fl in flaechen:
		var nrm: Vector3 = bs * (fl[4] as Vector3)
		var v: Array = []
		for k in 4:
			var q: Array = fl[k]
			v.append(e.call(float(q[0]), float(q[1]), float(q[2])))
		var col2 := Color(col.r * float(fl[5]), col.g * float(fl[5]), col.b * float(fl[5]), 0.0)
		for tri in [[0, 1, 2], [0, 2, 3]]:
			var a: Vector3 = v[tri[0]]
			var b2: Vector3 = v[tri[1]]
			var c2: Vector3 = v[tri[2]]
			if (b2 - a).cross(c2 - a).dot(nrm) > 0.0:
				var tmp := b2
				b2 = c2
				c2 = tmp
			for p in [a, b2, c2]:
				st.set_color(col2)
				st.set_normal(nrm)
				st.add_vertex(p)


## AUTO (laengs x, 4,2 m): Karosserie WEISS (Farbe kommt je Instanz), Kabine mit dunklen
## Scheiben, Raeder, Scheinwerfer, Ruecklichter.
static func auto_netz() -> ArrayMesh:
	if _netze.has("auto"):
		return _netze["auto"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var weiss := Color(1, 1, 1)
	var glas := Color(0.16, 0.20, 0.26)
	var reifen := Color(0.08, 0.08, 0.09)
	_quader(st, Vector3(0, 0.62, 0), Vector3(4.1, 0.62, 1.72), weiss)            # Unterbau
	_quader(st, Vector3(1.55, 0.86, 0), Vector3(1.0, 0.14, 1.66), weiss)          # Motorhaube hinten auslaufend
	_quader(st, Vector3(-0.25, 1.18, 0), Vector3(2.2, 0.56, 1.52), glas)          # Fenster
	_quader(st, Vector3(-0.25, 1.48, 0), Vector3(2.0, 0.06, 1.48), weiss)         # Dach
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_quader(st, Vector3(sx * 1.32, 0.33, sz * 0.78), Vector3(0.66, 0.66, 0.24), reifen)
		_quader(st, Vector3(2.06, 0.70, sx * 0.62), Vector3(0.04, 0.16, 0.30), Color(0.98, 0.95, 0.80))
		_quader(st, Vector3(-2.06, 0.74, sx * 0.66), Vector3(0.04, 0.14, 0.26), Color(0.80, 0.12, 0.10))
	st.index()
	_netze["auto"] = st.commit()
	return _netze["auto"]


## KUH (laengs x, 2,3 m): Rumpf, Kopf vorn unten (grasend), Beine, Euter; Farbe je Instanz auf dem
## Fell (weiss), Flecken dunkel gemalt.
static func kuh_netz() -> ArrayMesh:
	if _netze.has("kuh"):
		return _netze["kuh"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fell := Color(1, 1, 1)
	var fleck := Color(0.10, 0.09, 0.09)
	var nase := Color(0.86, 0.66, 0.62)
	_quader(st, Vector3(0, 1.10, 0), Vector3(1.75, 0.80, 0.78), fell)
	_quader(st, Vector3(-0.35, 1.32, 0.0), Vector3(0.70, 0.40, 0.80), fleck)         # Fleck oben
	_quader(st, Vector3(0.45, 0.95, 0.30), Vector3(0.50, 0.40, 0.20), fleck)          # Fleck Flanke
	_quader(st, Vector3(1.05, 0.62, 0), Vector3(0.50, 0.42, 0.40), fell, 0.0, 0.0)    # Kopf (grasend)
	_quader(st, Vector3(1.32, 0.48, 0), Vector3(0.16, 0.22, 0.34), nase)
	_quader(st, Vector3(0.95, 0.86, 0.22), Vector3(0.10, 0.06, 0.18), fleck)         # Ohren
	_quader(st, Vector3(0.95, 0.86, -0.22), Vector3(0.10, 0.06, 0.18), fleck)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_quader(st, Vector3(sx * 0.62, 0.36, sz * 0.26), Vector3(0.16, 0.72, 0.16), fell)
			_quader(st, Vector3(sx * 0.62, 0.04, sz * 0.26), Vector3(0.17, 0.08, 0.17), fleck)
	_quader(st, Vector3(-0.30, 0.66, 0), Vector3(0.30, 0.16, 0.30), nase)              # Euter
	_quader(st, Vector3(-0.92, 0.95, 0), Vector3(0.06, 0.60, 0.06), fell)              # Schwanz
	st.index()
	_netze["kuh"] = st.commit()
	return _netze["kuh"]


## SCHAF (1,3 m): wollige Kugel aus drei Quadern, dunkler Kopf und Beine.
static func schaf_netz() -> ArrayMesh:
	if _netze.has("schaf"):
		return _netze["schaf"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wolle := Color(0.93, 0.91, 0.86)
	var kopf := Color(0.16, 0.14, 0.13)
	_quader(st, Vector3(0, 0.72, 0), Vector3(1.05, 0.58, 0.66), wolle)
	_quader(st, Vector3(0, 0.78, 0), Vector3(0.85, 0.70, 0.76), wolle)
	_quader(st, Vector3(0.62, 0.62, 0), Vector3(0.30, 0.28, 0.26), kopf)
	_quader(st, Vector3(0.55, 0.74, 0.17), Vector3(0.08, 0.05, 0.14), kopf)
	_quader(st, Vector3(0.55, 0.74, -0.17), Vector3(0.08, 0.05, 0.14), kopf)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_quader(st, Vector3(sx * 0.32, 0.22, sz * 0.20), Vector3(0.10, 0.44, 0.10), kopf)
	st.index()
	_netze["schaf"] = st.commit()
	return _netze["schaf"]


## BANK: Holzsitz und Lehne auf zwei gusseisernen Wangen (1,8 m).
static func bank_netz() -> ArrayMesh:
	if _netze.has("bank"):
		return _netze["bank"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var holz := Color(0.58, 0.40, 0.24)
	var eisen := Color(0.14, 0.17, 0.15)
	_quader(st, Vector3(0, 0.45, 0), Vector3(1.8, 0.06, 0.45), holz)
	_quader(st, Vector3(0, 0.78, -0.22), Vector3(1.8, 0.36, 0.05), holz, 0.0, -0.18)
	for sx: float in [-0.75, 0.75]:
		_quader(st, Vector3(sx, 0.40, -0.02), Vector3(0.07, 0.80, 0.50), eisen)
	st.index()
	_netze["bank"] = st.commit()
	return _netze["bank"]


## ZAUNFELD (1 m lang laengs x, Pfosten bei x = 0, zwei Latten bis x = 1): jede Instanz streckt es
## per Basis auf ihr Feld (X = Weg zum naechsten Pfosten samt Hoehenunterschied -> die Latten
## folgen dem Gelaende). Eine MultiMesh je Ort statt eines Netzes aus Einzelbalken (14 ms je Dorf).
static func zaun_netz() -> ArrayMesh:
	if _netze.has("zaun"):
		return _netze["zaun"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var holz := Color(0.56, 0.42, 0.27)
	_quader(st, Vector3(0.0, 0.55, 0.0), Vector3(0.04, 1.3, 0.12), holz)     # Pfosten (x gestreckt!)
	for hy: float in [0.55, 0.98]:
		_quader(st, Vector3(0.5, hy, 0.0), Vector3(1.0, 0.09, 0.05), holz)
	st.index()
	_netze["zaun"] = st.commit()
	return _netze["zaun"]


## Zaunfelder entlang eines Rechtecks (Mitte m, Achse a, halbe Laenge/Breite) an xfs anhaengen;
## Felder ~3 m, auf der ersten Seite in der Mitte ein offenes Tor.
static func _zaun(xfs: Array, terrain: TerrainWorld, m: Vector2, a: Vector2, hl: float, hb: float) -> void:
	var n := Vector2(-a.y, a.x)
	var ecken := [m - a * hl - n * hb, m + a * hl - n * hb, m + a * hl + n * hb, m - a * hl + n * hb]
	for k in 4:
		var p0: Vector2 = ecken[k]
		var p1: Vector2 = ecken[(k + 1) % 4]
		var l := p0.distance_to(p1)
		var d := (p1 - p0) / l
		var schritte := maxi(1, roundi(l / 3.0))
		var y_alt := terrain.height_at(p0.x, p0.y)
		for j in schritte:
			var q0 := p0 + d * (l * float(j) / float(schritte))
			var q1 := p0 + d * (l * float(j + 1) / float(schritte))
			var y1 := terrain.height_at(q1.x, q1.y)
			if k == 0 and j == (schritte >> 1):
				y_alt = y1
				continue
			var x := Vector3(q1.x - q0.x, y1 - y_alt, q1.y - q0.y)
			var z := Vector3(-d.y, 0.0, d.x)
			xfs.append(Transform3D(Basis(x, Vector3.UP, z), Vector3(q0.x, y_alt, q0.y)))
			y_alt = y1


static func _material() -> ShaderMaterial:
	return Strassen._stein_material()


## In KACHELN zu 250 m: die Sichtweite (visibility_range) misst Godot von der Mitte der Huelle — eine
## MultiMesh ueber die ganze Stadt hatte ihre Mitte 3 km weg und wurde nie gezeichnet.
static func _einhaengen(wurzel: Node3D, name: String, mesh: Mesh, xfs: Array, farben: Array,
		sicht: float) -> void:
	if xfs.is_empty():
		return
	var kacheln := {}
	for i in xfs.size():
		var o: Vector3 = (xfs[i] as Transform3D).origin
		var k := Vector2i(floori(o.x / 250.0), floori(o.z / 250.0))
		if not kacheln.has(k):
			kacheln[k] = []
		(kacheln[k] as Array).append(i)
	for k in kacheln:
		var idx: Array = kacheln[k]
		var t: Array = []
		var c: Array = []
		for i in idx:
			t.append(xfs[i])
			if not farben.is_empty():
				c.append(farben[i])
		_einhaengen_kachel(wurzel, "%s_%d_%d" % [name, k.x, k.y], mesh, t, c, sicht)


static func _einhaengen_kachel(wurzel: Node3D, name: String, mesh: Mesh, xfs: Array, farben: Array,
		sicht: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not farben.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mm.use_colors:
			var c: Color = farben[i]
			mm.set_instance_color(i, Color(c.r, c.g, c.b, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = _material()
	mmi.visibility_range_end = sicht
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	wurzel.add_child(mmi)


const AUTOFARBEN := [Color(0.80, 0.16, 0.14), Color(0.92, 0.92, 0.90), Color(0.18, 0.30, 0.58),
	Color(0.20, 0.22, 0.24), Color(0.55, 0.58, 0.60), Color(0.88, 0.70, 0.22), Color(0.26, 0.45, 0.32),
	Color(0.62, 0.78, 0.86), Color(0.92, 0.92, 0.90), Color(0.20, 0.22, 0.24)]
const KUHFARBEN := [Color(1.0, 1.0, 1.0), Color(0.62, 0.40, 0.24), Color(0.80, 0.62, 0.40)]


## AUTOS AN DEN STADTSTRASSEN: je Strassenstueck (Art STRASSE/GASSE) am rechten Bordstein alle
## 6,5 m mit Wahrscheinlichkeit dicht, nicht naeher als 9 m an den Enden (Kreuzungen).
static func stadt(parent: Node3D, terrain: TerrainWorld, name: String, s0: int, s1: int,
		hi: Ortsgruen.Hindernisse, dicht: float) -> void:
	var t0 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("leben_" + name)
	var xfs: Array = []
	var farben: Array = []
	var sw := Stadtstrassen.breite(Stadtstrassen.STRASSE)
	var gw := Stadtstrassen.breite(Stadtstrassen.GASSE)
	var dw := Stadtstrassen.breite(Stadtstrassen.DORF)
	for i in range(s0, s1):
		var s: Array = CityBuilder.karte_strassen[i]
		var br := float(s[2])
		var fb := 0.0
		if absf(br - sw) < 0.1:
			fb = float(Stadtstrassen.FAHRBAHN[Stadtstrassen.STRASSE])
		elif absf(br - gw) < 0.1 or absf(br - dw) < 0.1:
			fb = br
		else:
			continue
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var l := a.distance_to(b)
		if l < 22.0:
			continue
		var d := (b - a) / l
		var nq := Vector2(-d.y, d.x)
		var t := 9.0
		while t < l - 9.0:
			for seite: float in [-1.0, 1.0]:
				if rng.randf() > dicht:
					continue
				var q := a + d * t + nq * seite * (fb * 0.5 - 1.05)
				if hi.im_haus(q, 1.2):
					continue
				var y := terrain.height_at(q.x, q.y) + Stadtstrassen.HUB
				var yaw := atan2(-d.y, d.x) + (0.0 if seite > 0.0 else PI) + rng.randf_range(-0.04, 0.04)
				xfs.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, y, q.y)))
				farben.append(AUTOFARBEN[rng.randi() % AUTOFARBEN.size()])
			t += 6.5
	var wurzel := Node3D.new()
	wurzel.name = "Ortsleben_" + name
	wurzel.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(wurzel)
	_einhaengen(wurzel, "Autos", auto_netz(), xfs, farben, 1200.0)
	if OS.get_environment("ORTSLEBEN_ZEIGEN") != "" and not xfs.is_empty():
		for k in mini(4, xfs.size()):
			print("ORTSLEBEN %s Auto %s" % [name, (xfs[(k * xfs.size()) >> 2] as Transform3D).origin])
	bilanz = [int(bilanz[0]) + xfs.size(), bilanz[1], bilanz[2], int(bilanz[3]) + Time.get_ticks_usec() - t0]


## DORF: Autos vor manchen Haeusern (am Ende der Zufahrt bzw. neben dem Haus), eine Weide mit
## Kuehen oder Schafen hinter den Hoefen, Baenke an der Kirche.
static func dorf(parent: Node3D, terrain: TerrainWorld, name: String, p: Vector2, dir: Vector2,
		gr: int, laenge: float, hi: Ortsgruen.Hindernisse) -> void:
	var t0 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("leben_" + name)
	var wurzel := Node3D.new()
	wurzel.name = "Ortsleben_" + name
	wurzel.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(wurzel)
	# Autos neben dem Haus (Seite zur Strasse hin), jedes dritte Haus
	var autos: Array = []
	var farben: Array = []
	for e in hi.haeuser:
		var h: Vector2 = e[1]
		if h.x * h.y < 30.0 or rng.randf() > 0.35:
			continue
		var c: Vector2 = e[0]
		var yaw: float = e[2]
		var vorn := Vector2(sin(yaw), cos(yaw))
		var seite := Vector2(vorn.y, -vorn.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var q := c + seite * (h.x + 2.2) + vorn * (h.y * 0.2)
		if hi.im_haus(q, 0.6) or hi.strasse_rand(q) < 0.8 or hi.baum_nah(q, 2.8):
			continue
		var y := terrain.height_at(q.x, q.y)
		autos.append(Transform3D(Basis(Vector3.UP, atan2(-vorn.y, vorn.x)), Vector3(q.x, y, q.y)))
		farben.append(AUTOFARBEN[rng.randi() % AUTOFARBEN.size()])
	_einhaengen(wurzel, "Autos", auto_netz(), autos, farben, 900.0)
	# Weide: Rechteck hinter den Hoefen, frei von Haus, Strasse, Baum
	var quer := Vector2(-dir.y, dir.x)
	var tiere: Array = []
	var tierfarben: Array = []
	var schafe: Array = []
	var weiden := 0
	var zaun: Array = []
	for versuch in 10:
		if weiden >= (1 if gr == 0 else 2):
			break
		var seite := 1.0 if rng.randf() < 0.5 else -1.0
		var hl := rng.randf_range(24.0, 36.0)
		var hb := rng.randf_range(16.0, 24.0)
		var m := p + dir * rng.randf_range(-laenge, laenge) + quer * seite * rng.randf_range(95.0, 130.0)
		var frei := true
		for k in 9:
			var qq := m + dir * (float(k % 3 - 1) * hl) + quer * (float((k - k % 3) / 3.0 - 1.0) * hb)
			if hi.im_haus(qq, 4.0) or hi.strasse_rand(qq) < 5.0 or hi.baum_nah(qq, 6.0) \
					or terrain.height_at(qq.x, qq.y) < TerrainWorld.SEA_Y + 1.5:
				frei = false
				break
		if not frei:
			continue
		weiden += 1
		_zaun(zaun, terrain, m, dir, hl, hb)
		var schaf := rng.randf() < 0.4
		var anz := rng.randi_range(5, 9) if not schaf else rng.randi_range(9, 16)
		var herde := m + dir * rng.randf_range(-hl * 0.4, hl * 0.4)
		for k in anz:
			# lokal in der Weide (laengs dir, quer), mit 3 m Abstand zum Zaun
			var lx := clampf((herde - m).dot(dir) + rng.randf_range(-1.0, 1.0) * hb * 0.75, -hl + 3.0, hl - 3.0)
			var lz := clampf(rng.randf_range(-1.0, 1.0) * (hb - 3.0), -hb + 3.0, hb - 3.0)
			var tp := m + dir * lx + quer * lz
			var y := terrain.height_at(tp.x, tp.y)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 1.08)),
				Vector3(tp.x, y, tp.y))
			if schaf:
				schafe.append(xf)
			else:
				tiere.append(xf)
				tierfarben.append(KUHFARBEN[rng.randi() % KUHFARBEN.size()])
		for e2 in range(0, 9):
			hi.baum(m + dir * (float(e2 % 3 - 1) * hl * 0.7) + quer * (float((e2 - e2 % 3) / 3.0 - 1.0) * hb * 0.7))
	_einhaengen(wurzel, "Weidezaun", zaun_netz(), zaun, [], 700.0)
	_einhaengen(wurzel, "Kuehe", kuh_netz(), tiere, tierfarben, 900.0)
	_einhaengen(wurzel, "Schafe", schaf_netz(), schafe, [], 900.0)
	# Baenke an der Kirche bzw. Kapelle: auf der Strassenseite, Blick zur Strasse; die erste freie
	# von mehreren Stellen (die Kirchhofmauer steht nicht im Hausgrundriss)
	var baenke: Array = []
	if gr >= 1:
		var kz := -30.0 if gr == 2 else -24.0
		var gesetzt := 0
		for kand in [Vector2(-12, -9.5), Vector2(12, -9.5), Vector2(-20, -9.5), Vector2(20, -9.5),
				Vector2(-26, kz + 4.0), Vector2(26, kz + 4.0)]:
			if gesetzt >= 2:
				break
			var q: Vector2 = p + dir * kand.x + quer * kand.y
			if hi.im_haus(q, 2.4) or hi.strasse_rand(q) < 1.2 or hi.baum_nah(q, 2.0):
				continue
			var zur: Vector2 = (p + dir * float(kand.x) - q).normalized()       # zur Strasse
			baenke.append(Transform3D(Basis(Vector3.UP, atan2(zur.x, zur.y)), Vector3(q.x, terrain.height_at(q.x, q.y), q.y)))
			hi.baum(q)
			gesetzt += 1
	_einhaengen(wurzel, "Baenke", bank_netz(), baenke, [], 500.0)
	bilanz = [int(bilanz[0]) + autos.size(), int(bilanz[1]) + tiere.size() + schafe.size(),
		int(bilanz[2]) + weiden, int(bilanz[3]) + Time.get_ticks_usec() - t0]
