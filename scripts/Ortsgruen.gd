## ORTSGRUEN (2026-10-02, Nutzer: „erhoehe die Liebe und den Detailgrad von den Doerfern/Staedten“).
## BEFUND: jedes Strassendorf, das Landdorf und die Nordhaelfte der Grossstadt lagen auf einer kahlen
## Sandscheibe (die Flachzone haelt den Wald frei, darunter schien die Heide durch — siehe
## TerrainWorld._ort_anteil), zwischen den Haeusern stand kein einziger Baum, die Haeuser standen
## ohne Weg neben der Strasse, die Stadt war Rasen und Asphalt.
## HIER (statisch, deterministisch je Ort):
##   * HOFBAEUME hinter jedem Haus (die Seite, die nicht zur Strasse zeigt)
##   * STREUOBSTWIESEN in Feldern um die Doerfer (kleine runde Kronen in Reihen)
##   * DORFLINDE bei Kirche bzw. Kapelle
##   * HOFZUFAHRTEN aus Kies von der Haustuer zur Strasse (Strassendoerfer)
##   * ALLEEN auf den Boulevards, Baeume in Hoefen und Parks (Grossstadt)
## Die Baeume sind die der Welt (TerrainWorld._flora, mit Karten, Mittelstufe und Impostor,
## eingehaengt ueber TerrainWorld._attach_multi) — nah wie fern dieselben wie im Wald daneben.
class_name Ortsgruen
extends RefCounted

const ZELLE := 32.0              # Raster fuer die Hindernissuche
# Bilanz fuer die Startmeldung (Main): Pflanzen, Zufahrten, Orte, Bauzeit (us)
static var bilanz := [0, 0, 0, 0]
const HAUS_RAND := 2.5           # Abstand der Baumstaemme zu Hauswaenden
const BAUM_ABSTAND := 4.5        # Mindestabstand zwischen zwei Baeumen
const ZUFAHRT_HALB := 0.8        # halbe Breite einer Hofzufahrt


## Hindernisse eines Orts: Hausgrundrisse (aus CityBuilder.karte_haeuser), Strassenstuecke (aus
## CityBuilder.karte_strassen und eigenen), Landstrassen (TerrainWorld.strasse_abstand) und schon
## gesetzte Baeume — alle in einem 32-m-Raster.
class Hindernisse:
	var haeuser: Array = []          # [mitte, halbe Groesse, yaw]
	var strassen: Array = []         # [a, b, halbe Breite]
	var baeume := PackedVector2Array()
	var h_raster := {}
	var s_raster := {}
	var b_raster := {}
	var terrain: TerrainWorld

	func _zellen(lo: Vector2, hi: Vector2) -> Array:
		var raus: Array = []
		for gx in range(floori(lo.x / ZELLE), floori(hi.x / ZELLE) + 1):
			for gz in range(floori(lo.y / ZELLE), floori(hi.y / ZELLE) + 1):
				raus.append(Vector2i(gx, gz))
		return raus

	func haus(e: Array) -> void:
		var c: Vector2 = e[0]
		var h: Vector2 = e[1]
		var r := h.length() + HAUS_RAND
		var i := haeuser.size()
		haeuser.append(e)
		for k in _zellen(c - Vector2(r, r), c + Vector2(r, r)):
			if not h_raster.has(k):
				h_raster[k] = []
			(h_raster[k] as Array).append(i)

	func strasse(a: Vector2, b: Vector2, halb: float) -> void:
		var i := strassen.size()
		strassen.append([a, b, halb])
		var r := halb + 4.0
		for k in _zellen(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(r, r),
				Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(r, r)):
			if not s_raster.has(k):
				s_raster[k] = []
			(s_raster[k] as Array).append(i)

	func baum(p: Vector2) -> void:
		var k := Vector2i(floori(p.x / ZELLE), floori(p.y / ZELLE))
		if not b_raster.has(k):
			b_raster[k] = []
		(b_raster[k] as Array).append(baeume.size())
		baeume.append(p)

	## Liegt p in einem Haus (plus Rand)?
	func im_haus(p: Vector2, rand: float) -> bool:
		var k := Vector2i(floori(p.x / ZELLE), floori(p.y / ZELLE))
		for i in h_raster.get(k, []):
			var e: Array = haeuser[i]
			var q: Vector2 = (p - (e[0] as Vector2)).rotated(float(e[2]))
			var h: Vector2 = e[1]
			if absf(q.x) < h.x + rand and absf(q.y) < h.y + rand:
				return true
		return false

	## Abstand zur naechsten Fahrbahnkante (negativ = auf der Strasse), Landstrassen eingeschlossen.
	func strasse_rand(p: Vector2) -> float:
		var d := INF
		var k := Vector2i(floori(p.x / ZELLE), floori(p.y / ZELLE))
		for i in s_raster.get(k, []):
			var s: Array = strassen[i]
			var c := Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
			d = minf(d, p.distance_to(c) - float(s[2]))
		if terrain != null:
			d = minf(d, terrain.strasse_abstand(p.x, p.y) - TerrainWorld.STRASSE_B_HAUPT - Strassen.BANKETT)
		return d

	func baum_nah(p: Vector2, abstand: float) -> bool:
		var gx := floori(p.x / ZELLE)
		var gz := floori(p.y / ZELLE)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for i in b_raster.get(Vector2i(gx + dx, gz + dz), []):
					if baeume[i].distance_squared_to(p) < abstand * abstand:
						return true
		return false

	## Darf hier ein Baum stehen? (kein Haus, keine Strasse, kein Baum zu nah, nicht im Wasser)
	func frei(p: Vector2, strassen_rand := 2.5, baum_abstand := BAUM_ABSTAND) -> bool:
		if im_haus(p, HAUS_RAND) or strasse_rand(p) < strassen_rand or baum_nah(p, baum_abstand):
			return false
		return terrain == null or terrain.height_at(p.x, p.y) > TerrainWorld.SEA_Y + 1.2


## Sammelt Baeume nach Art und haengt sie am Ende als Flora ein.
class Pflanzung:
	var arten := {}               # Art -> Array[Transform3D]
	var rng := RandomNumberGenerator.new()
	var terrain: TerrainWorld

	func setzen(art: String, p: Vector2, gross: float) -> void:
		if not arten.has(art):
			arten[art] = []
		var sc := gross * rng.randf_range(0.88, 1.12)
		var y := terrain.height_at(p.x, p.y) - 0.15
		(arten[art] as Array).append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(sc, sc * rng.randf_range(0.94, 1.10), sc)), Vector3(p.x, y, p.y)))


## Hindernisse eines Orts aufbauen: Haeuser ab Index h0 und Strassenstuecke ab s0 der Kartenlisten
## (was dieser Ort gerade gebaut hat), dazu eigene Strassenstuecke [a, b, halbe Breite].
static func hindernisse(terrain: TerrainWorld, h0: int, s0: int, extra_strassen: Array = []) -> Hindernisse:
	var hi := Hindernisse.new()
	hi.terrain = terrain
	for i in range(h0, CityBuilder.karte_haeuser.size()):
		hi.haus(CityBuilder.karte_haeuser[i])
	for i in range(s0, CityBuilder.karte_strassen.size()):
		var s: Array = CityBuilder.karte_strassen[i]
		hi.strasse(s[0], s[1], float(s[2]) * 0.5)
	for s in extra_strassen:
		hi.strasse(s[0], s[1], float(s[2]))
	return hi


static func _wurzel(parent: Node3D, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(n)
	return n


static func _einhaengen(wurzel: Node3D, terrain: TerrainWorld, pf: Pflanzung) -> int:
	var n := 0
	for art in pf.arten:
		var mesh: Mesh = terrain._flora.get(art)
		if mesh == null:
			continue
		terrain._attach_multi(wurzel, mesh, pf.arten[art])
		n += (pf.arten[art] as Array).size()
	return n


## HOFBAEUME: je Haus 0..2 Baeume auf der Seite, die nicht zur Strasse zeigt (Front = +z des
## Modells). Kleine Haeuser bekommen eher einen, grosse Hoefe zwei.
static func _hofbaeume(hi: Hindernisse, pf: Pflanzung, anteil: float, arten: Array) -> void:
	for e in hi.haeuser:
		if pf.rng.randf() > anteil:
			continue
		var c: Vector2 = e[0]
		var h: Vector2 = e[1]
		var yaw: float = e[2]
		var vorn := Vector2(sin(yaw), cos(yaw))
		var seite := Vector2(vorn.y, -vorn.x)
		var n := 1 if h.x * h.y < 50.0 or pf.rng.randf() < 0.4 else (2 if pf.rng.randf() < 0.7 else 3)
		for k in n:
			for versuch in 10:
				# erst hinter dem Haus, dann auch seitlich (hinter Bauernhaeusern steht oft die
				# Scheune — dort blieb sonst jeder Versuch haengen)
				var p: Vector2
				if versuch < 4:
					p = c - vorn * (h.y + pf.rng.randf_range(3.5, 10.0)) \
						+ seite * pf.rng.randf_range(-h.x - 3.0, h.x + 3.0)
				else:
					var sv := 1.0 if pf.rng.randf() < 0.5 else -1.0
					p = c + seite * sv * (h.x + pf.rng.randf_range(3.5, 8.0)) \
						+ vorn * pf.rng.randf_range(-h.y - 4.0, h.y * 0.3)
				if hi.frei(p):
					hi.baum(p)
					var art: String = arten[pf.rng.randi() % arten.size()]
					pf.setzen(art, p, 0.85 if art != "Busch" else 1.2)
					break


## VORGAERTEN: ein bis drei Bueschel neben der Hausfront (nicht auf der Zufahrt, nicht an der
## Strasse).
static func _vorgaerten(hi: Hindernisse, pf: Pflanzung, anteil: float) -> void:
	for e in hi.haeuser:
		if pf.rng.randf() > anteil:
			continue
		var c: Vector2 = e[0]
		var h: Vector2 = e[1]
		var yaw: float = e[2]
		if h.x * h.y < 20.0:
			continue
		var vorn := Vector2(sin(yaw), cos(yaw))
		var seite := Vector2(vorn.y, -vorn.x)
		for k in 1 + pf.rng.randi() % 3:
			var sv := 1.0 if pf.rng.randf() < 0.5 else -1.0
			var p := c + vorn * (h.y + pf.rng.randf_range(1.6, 3.5)) \
				+ seite * sv * pf.rng.randf_range(ZUFAHRT_HALB + 1.8, h.x + 1.0)
			if not hi.im_haus(p, 1.2) and hi.strasse_rand(p) > 2.0 and not hi.baum_nah(p, 2.5):
				hi.baum(p)
				pf.setzen("Busch", p, pf.rng.randf_range(0.7, 1.0))


## DORFBAEUME an der Strasse: alle ~26 m im Wechsel links und rechts an der Fahrbahn, wo frei.
static func _strassenbaeume(hi: Hindernisse, pf: Pflanzung, p: Vector2, dir: Vector2, halb: float) -> void:
	var quer := Vector2(-dir.y, dir.x)
	var x := -halb
	var seite := 1.0
	while x <= halb:
		for versuch in 3:
			var off := TerrainWorld.STRASSE_B_HAUPT + Strassen.BANKETT + pf.rng.randf_range(3.0, 5.5)
			var q := p + dir * (x + pf.rng.randf_range(-3.0, 3.0)) + quer * seite * off
			if hi.frei(q, 2.5, 9.0):
				hi.baum(q)
				pf.setzen("Eiche", q, pf.rng.randf_range(1.0, 1.25))
				break
		seite = -seite
		x += pf.rng.randf_range(22.0, 30.0)


## STREUOBSTWIESE: ein Feld kleiner runder Baeume in Reihen (Abstand 9 x 10 m, leicht versetzt),
## Achse `achse`, Mitte m, Ausdehnung (laengs, quer). Was auf Haus/Strasse faellt, entfaellt.
static func _obstwiese(hi: Hindernisse, pf: Pflanzung, m: Vector2, achse: Vector2, laengs: float,
		quer: float) -> void:
	var n := Vector2(-achse.y, achse.x)
	var a := -laengs * 0.5
	var reihe := 0
	while a <= laengs * 0.5:
		var b := -quer * 0.5 + (4.5 if reihe % 2 == 1 else 0.0)
		while b <= quer * 0.5:
			var p := m + achse * (a + pf.rng.randf_range(-1.0, 1.0)) + n * (b + pf.rng.randf_range(-1.0, 1.0))
			if pf.rng.randf() < 0.9 and hi.frei(p, 3.0, 6.0):
				hi.baum(p)
				pf.setzen("Eiche", p, pf.rng.randf_range(0.42, 0.58))
			b += 9.0
		a += 10.0
		reihe += 1


## HOFZUFAHRTEN: von der Hausfront zur naechsten Fahrbahn, wenn die hoechstens 24 m entfernt ist.
## Ein Netz je Ort, Kiesweg-Shader (strasse.gdshader, neben = true).
static func _zufahrten(wurzel: Node3D, hi: Hindernisse, terrain: TerrainWorld) -> int:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for e in hi.haeuser:
		var c: Vector2 = e[0]
		var h: Vector2 = e[1]
		var yaw: float = e[2]
		if h.x * h.y < 20.0:
			continue
		var vorn := Vector2(sin(yaw), cos(yaw))
		var start := c + vorn * (h.y - 0.3)
		# Bis zur Fahrbahnkante: der Abstand ist eine untere Grenze fuer den Weg geradeaus, also
		# schrittweise um ihn vorruecken (wenige Abfragen statt Meter fuer Meter)
		var ende := -1.0
		var s := 0.0
		for it in 8:
			var d := hi.strasse_rand(start + vorn * s)
			if d <= 0.25:
				ende = s
				break
			s += d
			if s > 24.0:
				break
		if ende < 2.0:
			continue
		var quer := Vector2(vorn.y, -vorn.x) * ZUFAHRT_HALB
		var schritte := maxi(1, ceili(ende / 3.0))
		var lauf := 0.0
		for j in schritte:
			var a := start + vorn * (ende * float(j) / float(schritte))
			var b := start + vorn * (ende * float(j + 1) / float(schritte))
			var ya := terrain.height_at(a.x, a.y) + 0.05
			var yb := terrain.height_at(b.x, b.y) + 0.05
			var l0 := a + quer
			var r0 := a - quer
			var l1 := b + quer
			var r1 := b - quer
			var lb := lauf + ende / float(schritte)
			var v := [Vector3(l0.x, ya, l0.y), Vector3(r0.x, ya, r0.y), Vector3(r1.x, yb, r1.y),
				Vector3(l1.x, yb, l1.y)]
			var uv := [Vector2(ZUFAHRT_HALB, lauf), Vector2(-ZUFAHRT_HALB, lauf),
				Vector2(-ZUFAHRT_HALB, lb), Vector2(ZUFAHRT_HALB, lb)]
			# Nach oben wickeln (Front im Uhrzeigersinn von oben gesehen)
			var v0: Vector3 = v[0]
			var v1: Vector3 = v[1]
			var v2: Vector3 = v[2]
			var auf: bool = (v1 - v0).cross(v2 - v0).y > 0.0
			var tris := [[0, 2, 1], [0, 3, 2]] if auf else [[0, 1, 2], [0, 2, 3]]
			for t in tris:
				for k in t:
					st.set_normal(Vector3.UP)
					st.set_uv(uv[k])
					st.set_uv2(Vector2(ZUFAHRT_HALB, 0.0))
					st.add_vertex(v[k])
			lauf = lb
		n += 1
	if n == 0:
		return 0
	var mi := MeshInstance3D.new()
	mi.name = "Zufahrten"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/strasse.gdshader")
	mat.set_shader_parameter("neben", true)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = CityBuilder.SICHT_DIST
	wurzel.add_child(mi)
	return n


## STRASSENDORF (Strassen._dorf): Hindernisse ab h0/s0, Mitte p, Achse dir (lokal x), Groesse gr,
## Dorfstrassen-Stuecke dazu. Kirche bzw. Kapelle stehen bei lokal (0, -30) bzw. (0, -24).
static func strassendorf(parent: Node3D, terrain: TerrainWorld, name: String, p: Vector2,
		dir: Vector2, gr: int, laenge: float, h0: int, s0: int, dorfstrassen: Array,
		plan: Array = [], dreh := 0.0) -> Array:
	var t0 := Time.get_ticks_usec()
	var hi := hindernisse(terrain, h0, s0, dorfstrassen)
	var pf := Pflanzung.new()
	pf.terrain = terrain
	pf.rng.seed = hash("gruen_" + name)
	var wurzel := _wurzel(parent, "Ortsgruen_" + name)
	var quer := Vector2(-dir.y, dir.x)
	# Dorflinde bei der Kirche (lokal z negativ = Kirchseite)
	if gr >= 1:
		var kz := -30.0 if gr == 2 else -24.0
		for kand in [Vector2(20, kz + 12), Vector2(-20, kz + 12), Vector2(24, kz - 6), Vector2(-24, kz - 6)]:
			var w: Vector2 = p + dir * kand.x + quer * kand.y
			if hi.frei(w, 3.0, 8.0):
				hi.baum(w)
				pf.setzen("Eiche", w, 1.65)
				break
	_hofbaeume(hi, pf, 0.85, ["Eiche", "Eiche", "Birke", "Busch"])
	_strassenbaeume(hi, pf, p, dir, laenge + 20.0)
	# Zufahrten vor den Vorgaerten (die Bueschel halten Abstand zu ihnen ueber ZUFAHRT_HALB)
	_vorgaerten(hi, pf, 0.75)
	# Streuobstwiesen hinter den Hoefen, je Seite ein bis zwei Felder
	for seite: float in [-1.0, 1.0]:
		var felder := 1 + (pf.rng.randi() % 2 if gr > 0 else 0)
		for k in felder:
			var x := pf.rng.randf_range(-laenge * 0.8, laenge * 0.8)
			var z := seite * pf.rng.randf_range(62.0, 78.0)
			_obstwiese(hi, pf, p + dir * x + quer * z, dir, pf.rng.randf_range(40.0, 70.0),
				pf.rng.randf_range(24.0, 36.0))
	# STROHBALLEN neben Scheunen und Staellen: drei bis sechs in einer Reihe an der Giebelseite
	var bs := Basis(Vector3.UP, dreh)
	for e in plan:
		var typ := String(e.get("typ", ""))
		if typ != "Haus_Scheune" and typ != "Haus_Stall":
			continue
		var lok: Vector2 = e["pos"]
		var w3: Vector3 = bs * Vector3(lok.x, 0.0, lok.y)
		var c := p + Vector2(w3.x, w3.z)
		var yaw := float(e.get("yaw", 0.0)) + dreh
		var laengs := Vector2(cos(yaw), -sin(yaw))     # lokal +x des Modells in Welt
		var vor := Vector2(sin(yaw), cos(yaw))
		var seite := 1.0 if pf.rng.randf() < 0.5 else -1.0
		var anz := 3 + pf.rng.randi() % 4
		for k in anz:
			var q := c + laengs * seite * pf.rng.randf_range(10.5, 12.0) + vor * (float(k) - anz * 0.5) * 1.6
			if not hi.im_haus(q, 0.9) and hi.strasse_rand(q) > 2.0:
				if not pf.arten.has("Ballen"):
					pf.arten["Ballen"] = []
				var y := terrain.height_at(q.x, q.y) - 0.15
				(pf.arten["Ballen"] as Array).append(Transform3D(Basis(Vector3.UP, yaw + PI * 0.5
					+ pf.rng.randf_range(-0.15, 0.15)), Vector3(q.x, y, q.y)))
	var n_zu := _zufahrten(wurzel, hi, terrain)
	var n := _einhaengen(wurzel, terrain, pf)
	bilanz = [int(bilanz[0]) + n, int(bilanz[1]) + n_zu, int(bilanz[2]) + 1,
		int(bilanz[3]) + Time.get_ticks_usec() - t0]
	return [n, n_zu]


## ORT MIT STRASSENNETZ (Grossstadt, Landdorf): Hofbaeume, Alleen auf den Boulevards, Baeume in
## freien Hoefen und Gruenflaechen, um das Dorf Obstwiesen. r = Radius des bebauten Gebiets.
static func ort(parent: Node3D, terrain: TerrainWorld, name: String, mitte: Vector2, r: float,
		h0: int, s0: int, stadt: bool) -> int:
	var t0 := Time.get_ticks_usec()
	var hi := hindernisse(terrain, h0, s0)
	var pf := Pflanzung.new()
	pf.terrain = terrain
	pf.rng.seed = hash("gruen_" + name)
	var wurzel := _wurzel(parent, "Ortsgruen_" + name)
	# ALLEEN: alle 16 m beidseits auf dem Gehweg der Boulevards, nicht an den Kreuzungen; auf den
	# Stadtstrassen schlanke Baeume alle 20 m, wo die Hauswand weit genug weg ist (Gehweg 2,25 m)
	var bw := Stadtstrassen.breite(Stadtstrassen.BOULEVARD)
	var sw := Stadtstrassen.breite(Stadtstrassen.STRASSE)
	for i in range(s0, CityBuilder.karte_strassen.size()):
		var s: Array = CityBuilder.karte_strassen[i]
		if stadt and absf(float(s[2]) - sw) < 0.1:
			var a2: Vector2 = s[0]
			var b2: Vector2 = s[1]
			var l2 := a2.distance_to(b2)
			var d2 := (b2 - a2) / maxf(l2, 0.01)
			var n2 := Vector2(-d2.y, d2.x)
			var t2 := 12.0
			while t2 < l2 - 12.0:
				for seite: float in [-1.0, 1.0]:
					var q := a2 + d2 * t2 + n2 * seite * (float(Stadtstrassen.FAHRBAHN[Stadtstrassen.STRASSE]) * 0.5 + 1.3)
					if not hi.im_haus(q, 2.6) and not hi.baum_nah(q, 9.0):
						hi.baum(q)
						pf.setzen("Birke", q, 0.75)
				t2 += 20.0
			continue
		if absf(float(s[2]) - bw) > 0.1:
			continue
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var l := a.distance_to(b)
		if l < 30.0:
			continue
		var d := (b - a) / l
		var nq := Vector2(-d.y, d.x)
		var t := 14.0
		while t < l - 14.0:
			for seite: float in [-1.0, 1.0]:
				var q := a + d * t + nq * seite * (float(Stadtstrassen.FAHRBAHN[Stadtstrassen.BOULEVARD]) * 0.5 + 1.6)
				if not hi.im_haus(q, 1.5) and not hi.baum_nah(q, 8.0):
					hi.baum(q)
					pf.setzen("Eiche", q, 1.0)
			t += 16.0
	_hofbaeume(hi, pf, 0.6 if stadt else 0.9, ["Eiche", "Birke", "Busch", "Eiche"])
	_vorgaerten(hi, pf, 0.3 if stadt else 0.7)
	# Freie Hoefe und Gruenflaechen: lockere Streuung
	var n_streu := int(r * r / (220.0 if stadt else 500.0))
	for i in n_streu:
		var w := mitte + Vector2.from_angle(pf.rng.randf() * TAU) * sqrt(pf.rng.randf()) * r
		if hi.frei(w, 2.0, 7.0):
			hi.baum(w)
			var art: String = ["Eiche", "Eiche", "Birke", "Busch", "Kiefer"][pf.rng.randi() % 5]
			pf.setzen(art, w, 1.0 if art != "Busch" else 1.3)
	# Obstwiesen um das Dorf
	if not stadt:
		for k in 5:
			var wk := TAU * (float(k) + pf.rng.randf_range(0.0, 0.6)) / 5.0
			var m := mitte + Vector2.from_angle(wk) * pf.rng.randf_range(r + 30.0, r + 70.0)
			_obstwiese(hi, pf, m, Vector2.from_angle(wk + PI * 0.5), pf.rng.randf_range(40.0, 70.0),
				pf.rng.randf_range(24.0, 34.0))
	var n := _einhaengen(wurzel, terrain, pf)
	bilanz = [int(bilanz[0]) + n, int(bilanz[1]), int(bilanz[2]) + 1, int(bilanz[3]) + Time.get_ticks_usec() - t0]
	return n
