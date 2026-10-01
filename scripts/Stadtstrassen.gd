## STADTSTRASSEN — Strassennetze der Orte als echtes Netz: Fahrbahn, Bordstein und Gehweg in
## einem Band, saubere Kreuzungen, Markierung und Zebrastreifen (shaders/stadtstrasse.gdshader).
##
## WARUM. Vorher legten CityBuilder.strassennetz und Hafenstadt._pflaster jede Strasse als
## einfarbiges Rechteck aufs Gelaende: an jeder Kreuzung lagen zwei Baender uebereinander
## (Tiefenkaempfe), die Ringstrasse klaffte an jedem Knick als Saegezahn auf, es gab weder
## Gehweg noch Linie — und die Haeuser standen ohne Bezug daneben oder mitten darauf.
##
## AUFBAU.
##   NETZ      Strecken werden roh gesammelt (`strecke`) und dann an allen Schnittpunkten
##             zerlegt (`schliessen`): Knoten + Kanten. Kanten unter grossen Bauten fallen weg.
##   KNOTEN    An jedem Knoten werden die Arme nach Winkel geordnet. Jeder Arm wird so weit
##             zurueckgeschnitten, dass sich die Baender nicht ueberlappen (`_schnitte`); die
##             Luecke fuellen ein Asphalt-Faecher und je Armpaar eine Gehwegecke. Das gilt fuer
##             JEDEN Winkel: Kreuzung, Einmuendung, Knick (Gehrung), Breitenwechsel.
##   BAND      Je Kante ein Band mit drei Punkten quer (links, Achse, rechts), alle ~24 m dem
##             Gelaende nachgefuehrt. Der Shader malt daraus Fahrbahn, Bordstein, Gehweg.
##   HAEUSER   `bebauen` setzt Haeuser entlang der Kanten, Front zur Strasse, direkt hinter
##             den Gehweg — und nie auf eine andere Strasse oder ein anderes Haus.
## Alles statisch und deterministisch. Beleg: tools/_stadtstrassen_check.gd.
class_name Stadtstrassen
extends RefCounted

const GASSE := 0
const STRASSE := 1
const BOULEVARD := 2
const WEG := 3
const DORF := 4
const LAND := 5
## Fahrbahnbreite und Gehweg je Seite (Meter), je Art.
const FAHRBAHN := [5.0, 6.5, 12.0, 3.6, 5.5, 7.2]
const GEHWEG := [0.0, 2.25, 3.0, 0.0, 0.0, 0.0]
const HUB := 0.35            # ueber dem Gelaende (wie die alten Baender: gegen Tiefenkaempfe)
const STUECK := 24.0         # Laenge eines Bandstuecks (Gelaende nachfuehren)
const UEBERGANG := 5.0       # Laenge des Uebergangs, wo sich die Breite aendert
const RANG := [0, 2, 3, 0, 1, 2]   # welcher Belag an einer Kreuzung gewinnt (je Art)

static var _mat: ShaderMaterial = null


static func breite(art: int) -> float:
	return float(FAHRBAHN[art]) + 2.0 * float(GEHWEG[art])


static func netz_neu() -> Dictionary:
	return {"roh": [], "p": [], "k": [], "cut": [], "grad": PackedInt32Array()}


static func strecke(netz: Dictionary, a: Vector2, b: Vector2, art: int) -> void:
	if a.distance_to(b) > 0.5:
		(netz["roh"] as Array).append([a, b, art])


## Linienzug (z. B. Ring): Strecken zwischen aufeinanderfolgenden Punkten.
static func zug(netz: Dictionary, pts: Array, art: int, geschlossen := false) -> void:
	for i in range(pts.size() - 1):
		strecke(netz, pts[i], pts[i + 1], art)
	if geschlossen and pts.size() > 2:
		strecke(netz, pts[pts.size() - 1], pts[0], art)


static func _knoten(p: Array, q: Vector2) -> int:
	for i in p.size():
		if (p[i] as Vector2).distance_squared_to(q) < 0.01:
			return i
	p.append(q)
	return p.size() - 1


## Rohstrecken an allen Schnitt- und Beruehrpunkten zerlegen -> Knoten und Kanten. `sperr`:
## OBBs (siehe `obb`) grosser Bauten; Kanten, die darunter laegen, entfallen.
static func schliessen(netz: Dictionary, sperr: Array = []) -> void:
	var roh: Array = netz["roh"]
	var p: Array = []
	var kanten: Array = []
	var schon: Dictionary = {}
	for i in roh.size():
		var a: Vector2 = roh[i][0]
		var b: Vector2 = roh[i][1]
		var ab := b - a
		var l2 := ab.length_squared()
		var ts: Array[float] = [0.0, 1.0]
		for j in roh.size():
			if j == i:
				continue
			var c: Vector2 = roh[j][0]
			var d: Vector2 = roh[j][1]
			# schneller Ausschluss ueber die Huellrechtecke
			if maxf(c.x, d.x) < minf(a.x, b.x) - 0.1 or minf(c.x, d.x) > maxf(a.x, b.x) + 0.1 \
					or maxf(c.y, d.y) < minf(a.y, b.y) - 0.1 or minf(c.y, d.y) > maxf(a.y, b.y) + 0.1:
				continue
			for q: Vector2 in [c, d]:
				var t := (q - a).dot(ab) / l2
				if t > 0.0005 and t < 0.9995 and (a + ab * t).distance_to(q) < 0.06:
					ts.append(t)
			var s: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
			if s != null:
				var sv: Vector2 = s
				var t2 := (sv - a).dot(ab) / l2
				if t2 > 0.0005 and t2 < 0.9995:
					ts.append(t2)
		ts.sort()
		var vor := -1
		var t_vor := -1.0
		var l := sqrt(l2)
		for t in ts:
			if vor >= 0 and (t - t_vor) * l < 0.2:
				continue
			var kn := _knoten(p, a + ab * t)
			if vor >= 0 and kn != vor:
				var key := Vector2i(mini(vor, kn), maxi(vor, kn))
				if not schon.has(key):
					schon[key] = true
					kanten.append([vor, kn, int(roh[i][2])])
			vor = kn
			t_vor = t
	if not sperr.is_empty():
		var bleibt: Array = []
		for k in kanten:
			var band := _kante_obb(p[int(k[0])], p[int(k[1])], breite(int(k[2])) * 0.5 - 0.5, -1.0)
			var frei := true
			for o in sperr:
				if obb_schnitt(band, o):
					frei = false
					break
			if frei:
				bleibt.append(k)
		kanten = bleibt
	netz["p"] = p
	netz["k"] = kanten
	_schnitte(netz)


## Arme je Knoten, nach Winkel geordnet: [winkel, kante, richtung, art, ende (0/1)].
static func _arme(netz: Dictionary) -> Array:
	var p: Array = netz["p"]
	var k: Array = netz["k"]
	var arme: Array = []
	arme.resize(p.size())
	for i in p.size():
		arme[i] = []
	for e in k.size():
		var a: Vector2 = p[int(k[e][0])]
		var b: Vector2 = p[int(k[e][1])]
		var d := (b - a).normalized()
		(arme[int(k[e][0])] as Array).append([d.angle(), e, d, int(k[e][2]), 0])
		(arme[int(k[e][1])] as Array).append([(-d).angle(), e, -d, int(k[e][2]), 1])
	for i in p.size():
		(arme[i] as Array).sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	return arme


## Wie weit jeder Arm an seinem Knoten zurueckgeschnitten wird. Fuer zwei Nachbararme i, j
## (Winkel phi dazwischen) treffen sich die AUSSENKANTEN im Abstand
## (w_j/2 + w_i/2 * cos phi) / sin phi laengs Arm i — davor ueberlappen die Baender.
static func _schnitte(netz: Dictionary) -> void:
	var p: Array = netz["p"]
	var k: Array = netz["k"]
	var cut: Array = []
	for e in k.size():
		cut.append([0.0, 0.0])
	var grad := PackedInt32Array()
	grad.resize(p.size())
	var arme := _arme(netz)
	for i in p.size():
		var al: Array = arme[i]
		grad[i] = al.size()
		if al.size() < 2:
			continue
		for m in al.size():
			var x: Array = al[m]
			var y: Array = al[(m + 1) % al.size()]
			var phi := fposmod(float(y[0]) - float(x[0]), TAU)
			if phi < 1e-4:
				phi = TAU
			var hx := breite(int(x[3])) * 0.5
			var hy := breite(int(y[3])) * 0.5
			var s := sin(phi)
			var tx := 0.0
			var ty := 0.0
			if absf(s) < 0.12:
				if absf(phi - PI) < 0.2 and int(x[3]) != int(y[3]):
					tx = UEBERGANG
					ty = UEBERGANG
			else:
				tx = maxf((hy + hx * cos(phi)) / s, 0.0)
				ty = maxf((hx + hy * cos(phi)) / s, 0.0)
			var cx: Array = cut[int(x[1])]
			cx[int(x[4])] = maxf(float(cx[int(x[4])]), tx)
			var cy: Array = cut[int(y[1])]
			cy[int(y[4])] = maxf(float(cy[int(y[4])]), ty)
	# nie mehr als knapp die halbe Kante (entartete Geometrie in sehr spitzen Winkeln)
	for e in k.size():
		var l := (p[int(k[e][0])] as Vector2).distance_to(p[int(k[e][1])])
		cut[e][0] = minf(float(cut[e][0]), l * 0.48)
		cut[e][1] = minf(float(cut[e][1]), l * 0.48)
	netz["cut"] = cut
	netz["grad"] = grad


# --- Rechtecke in beliebiger Lage (OBB): [mitte, halbe Groesse, Achse (Einheitsvektor)] ---------
static func _kante_obb(a: Vector2, b: Vector2, halb_b: float, laenger: float) -> Array:
	var d := (b - a).normalized()
	return [(a + b) * 0.5, Vector2(a.distance_to(b) * 0.5 + laenger, halb_b), d]


static func obb_schnitt(a: Array, b: Array) -> bool:
	var ca: Vector2 = a[0]
	var ha: Vector2 = a[1]
	var ua: Vector2 = a[2]
	var cb: Vector2 = b[0]
	var hb: Vector2 = b[1]
	var ub: Vector2 = b[2]
	var va := Vector2(-ua.y, ua.x)
	var vb := Vector2(-ub.y, ub.x)
	var dd := cb - ca
	for ax: Vector2 in [ua, va, ub, vb]:
		var ra := absf(ua.dot(ax)) * ha.x + absf(va.dot(ax)) * ha.y
		var rb := absf(ub.dot(ax)) * hb.x + absf(vb.dot(ax)) * hb.y
		if absf(dd.dot(ax)) > ra + rb:
			return false
	return true


## OBB eines Hauses (Grundriss des Fern-Netzes) an pos mit yaw, um `rand` vergroessert.
static func obb(typ: String, pos: Vector2, yaw: float, rand := 0.0) -> Array:
	var mesh: Mesh = CityBuilder._meshes.get(typ)
	var ab := AABB(Vector3(-6, 0, -6), Vector3(12, 8, 12))
	if mesh != null:
		ab = mesh.get_aabb()
	var u := Vector2(cos(yaw), -sin(yaw))       # lokal +x in der Welt (x, z)
	var f := Vector2(sin(yaw), cos(yaw))        # lokal +z (Front)
	var m := pos + u * (ab.position.x + ab.size.x * 0.5) + f * (ab.position.z + ab.size.z * 0.5)
	return [m, Vector2(ab.size.x * 0.5 + rand, ab.size.z * 0.5 + rand), u]


## Baender aller Kanten als OBBs (fuer Kollisionspruefungen), um `rand` verbreitert.
static func baender(netz: Dictionary, rand := 0.6) -> Array:
	var p: Array = netz["p"]
	var raus: Array = []
	for k in netz["k"]:
		raus.append(_kante_obb(p[int(k[0])], p[int(k[1])], breite(int(k[2])) * 0.5 + rand, 0.0))
	return raus


## Steht das Rechteck auf irgendeiner Strasse?
static func auf_strasse(netz: Dictionary, o: Array, rand := 0.6) -> bool:
	for b in baender(netz, rand):
		if obb_schnitt(b, o):
			return true
	return false


## HAEUSER ENTLANG DER KANTEN. `waehle(probe: Vector2, rng) -> String` liefert den Haustyp fuer
## eine Stelle ("" = hier nichts). `belegt` (OBBs) wird fortgeschrieben; `arten`: nur an Kanten
## dieser Arten bauen (leer = alle). Rueckgabe: Planeintraege fuer CityBuilder.build.
static func bebauen(netz: Dictionary, rng: RandomNumberGenerator, waehle: Callable,
		belegt: Array, arten: Array = [], abstand := 1.0, luecke := 0.7) -> Array:
	var p: Array = netz["p"]
	var k: Array = netz["k"]
	var cut: Array = netz["cut"]
	var band := baender(netz, 0.6)
	var plan: Array = []
	for e in k.size():
		var art := int(k[e][2])
		if not arten.is_empty() and not arten.has(art):
			continue
		var a: Vector2 = p[int(k[e][0])]
		var b: Vector2 = p[int(k[e][1])]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		var hw := breite(art) * 0.5
		var ende := a.distance_to(b) - float(cut[e][1]) - 0.6
		for seite: float in [1.0, -1.0]:
			var t := float(cut[e][0]) + 0.6
			while t < ende - 5.0:
				var probe := a + d * (t + 5.0) + n * (seite * (hw + 7.0))
				var typ: String = waehle.call(probe, rng)
				if typ == "" or not CityBuilder._meshes.has(typ):
					t += 9.0
					continue
				var ab: AABB = (CityBuilder._meshes[typ] as Mesh).get_aabb()
				var yaw := atan2(-seite * n.x, -seite * n.y)       # Front (+z) zur Strasse
				var u := Vector2(cos(yaw), -sin(yaw))
				var sgn := 1.0 if u.dot(d) > 0.0 else -1.0
				var lo := ab.position.x if sgn > 0.0 else -ab.end.x
				var w := ab.size.x
				if t + w > ende:
					break
				var vorn := ab.end.z
				var tief := ab.size.z
				var pos := a + d * (t - lo) + n * (seite * (hw + abstand + vorn))
				var o: Array = [a + d * (t + w * 0.5) + n * (seite * (hw + abstand + tief * 0.5)),
					Vector2(w * 0.5, tief * 0.5), d]
				t += w + luecke
				var frei := true
				for f in band.size():
					if f != e and obb_schnitt(band[f], o):
						frei = false
						break
				if frei:
					for o2 in belegt:
						if obb_schnitt(o2, o):
							frei = false
							break
				if not frei:
					continue
				belegt.append(o)
				plan.append({"typ": typ, "pos": pos, "yaw": yaw})
	return plan


# --- Geometrie ------------------------------------------------------------------------------------
static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/stadtstrasse.gdshader")
	return _mat


## Eckpunkt: [Lage (lokal), UV, UV2, CUSTOM0]
static func _dreieck(st: SurfaceTool, terrain, center: Vector3, hoehen: Dictionary, a: Array,
		b: Array, c: Array) -> void:
	var w: Array[Vector3] = []
	for e: Array in [a, b, c]:
		var l: Vector2 = e[0]
		var hk := Vector2i(roundi(l.x * 20.0), roundi(l.y * 20.0))
		var h: Variant = hoehen.get(hk)
		if h == null:
			h = terrain.height_at(center.x + l.x, center.z + l.y) + HUB if terrain != null \
				else center.y + HUB
			hoehen[hk] = h
		w.append(Vector3(center.x + l.x, float(h), center.z + l.y))
	var folge: Array = [a, b, c]
	var wf: Array[Vector3] = [w[0], w[1], w[2]]
	# Vorderseite = im Uhrzeigersinn; Normale dazu (c - a) x (b - a) muss nach oben zeigen
	if (w[2] - w[0]).cross(w[1] - w[0]).y < 0.0:
		folge = [a, c, b]
		wf = [w[0], w[2], w[1]]
	for i in 3:
		var e: Array = folge[i]
		st.set_normal(Vector3.UP)
		st.set_uv(e[1])
		st.set_uv2(e[2])
		st.set_custom(0, e[3])
		st.add_vertex(wf[i])


static func bauen(parent: Node3D, terrain, center: Vector3, netz: Dictionary,
		name := "Strassen") -> MeshInstance3D:
	var p: Array = netz["p"]
	var k: Array = netz["k"]
	var cut: Array = netz["cut"]
	var grad: PackedInt32Array = netz["grad"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var hoehen: Dictionary = {}
	var kein := Vector2(1.0e4, 1.0e4)
	var mw := Vector2(center.x, center.z)
	# --- Baender ---
	for e in k.size():
		var art := int(k[e][2])
		var a: Vector2 = p[int(k[e][0])]
		var b: Vector2 = p[int(k[e][1])]
		CityBuilder.karte_strassen.append([mw + a, mw + b, breite(art)])
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		var hc := float(FAHRBAHN[art]) * 0.5
		var hw := breite(art) * 0.5
		var s0 := float(cut[e][0])
		var s1 := a.distance_to(b) - float(cut[e][1])
		if s1 - s0 < 0.05:
			continue
		var ka := grad[int(k[e][0])] >= 3
		var kb := grad[int(k[e][1])] >= 3
		var dat := Color(hc, float(GEHWEG[art]), float(art), 1.0)
		var teile := maxi(1, int(ceil((s1 - s0) / STUECK)))
		for i in teile:
			var v0 := lerpf(s0, s1, float(i) / float(teile))
			var v1 := lerpf(s0, s1, float(i + 1) / float(teile))
			var reihe: Array = []
			for v: float in [v0, v1]:
				var u2 := Vector2(v - s0 if ka else 1.0e4, s1 - v if kb else 1.0e4)
				for q: float in [-hw, 0.0, hw]:
					reihe.append([a + d * v + n * q, Vector2(q, v - s0), u2, dat])
			for c in 2:
				_dreieck(st, terrain, center, hoehen, reihe[c], reihe[c + 1], reihe[c + 4])
				_dreieck(st, terrain, center, hoehen, reihe[c], reihe[c + 4], reihe[c + 3])
	# --- Knoten: Asphalt-Faecher und Gehwegecken ---
	var arme := _arme(netz)
	for i in p.size():
		var al: Array = arme[i]
		if al.size() < 2:
			continue
		var nn: Vector2 = p[i]
		# Belag der Kreuzung: der der "groessten" beteiligten Strasse (Boulevard vor Strasse
		# und Landstrasse vor Dorfstrasse vor Gasse und Weg).
		var art_max := int(al[0][3])
		var tief := 0.0
		for x: Array in al:
			tief = maxf(tief, float(cut[int(x[1])][int(x[4])]))
			if int(RANG[int(x[3])]) > int(RANG[art_max]):
				art_max = int(x[3])
		if tief < 0.02:
			continue
		var d_asph := Color(1000.0, 0.0, float(art_max), 0.0)
		var mitte_uv := Vector2(500.0, 0.0)     # weit weg von Achse UND Rand: reine Fahrbahn
		var rand: Array = []       # Umriss der Fahrbahnflaeche, im Winkelsinn
		for m in al.size():
			var x: Array = al[m]
			var y: Array = al[(m + 1) % al.size()]
			var dx: Vector2 = x[2]
			var dy: Vector2 = y[2]
			var nx := Vector2(-dx.y, dx.x)
			var ny := Vector2(-dy.y, dy.x)
			var cx := float(cut[int(x[1])][int(x[4])])
			var cy := float(cut[int(y[1])][int(y[4])])
			var hcx := float(FAHRBAHN[int(x[3])]) * 0.5
			var hcy := float(FAHRBAHN[int(y[3])]) * 0.5
			var hwx := breite(int(x[3])) * 0.5
			var hwy := breite(int(y[3])) * 0.5
			var ci := nn + dx * cx + nx * hcx
			var oi := nn + dx * cx + nx * hwx
			var cj := nn + dy * cy - ny * hcy
			var oj := nn + dy * cy - ny * hwy
			var xi := (ci + cj) * 0.5
			var ki := (oi + oj) * 0.5
			if absf(dx.cross(dy)) > 0.12:
				var sx: Variant = Geometry2D.line_intersects_line(nn + nx * hcx, dx, nn - ny * hcy, dy)
				if sx != null:
					xi = sx
				var sk: Variant = Geometry2D.line_intersects_line(nn + nx * hwx, dx, nn - ny * hwy, dy)
				if sk != null:
					ki = sk
			rand.append(nn + dx * cx - nx * hcx)
			rand.append(ci)
			rand.append(xi)
			# Gehwegecke zwischen Arm x (linke Seite) und Arm y (rechte Seite)
			var geh := maxf(float(GEHWEG[int(x[3])]), float(GEHWEG[int(y[3])]))
			if geh > 0.05:
				var dg := Color(0.0, geh, float(art_max), 0.0)
				var v_ci: Array = [ci, Vector2(0.0, 0.0), kein, dg]
				var v_cj: Array = [cj, Vector2(0.0, 0.0), kein, dg]
				var v_x: Array = [xi, Vector2(0.0, 0.0), kein, dg]
				var v_oi: Array = [oi, Vector2(geh if hwx > hcx else 0.0, 0.0), kein, dg]
				var v_oj: Array = [oj, Vector2(geh if hwy > hcy else 0.0, 0.0), kein, dg]
				var v_k: Array = [ki, Vector2(geh, 0.0), kein, dg]
				for t: Array in [[v_ci, v_oi, v_k], [v_ci, v_k, v_x], [v_x, v_k, v_cj], [v_cj, v_k, v_oj]]:
					if _flaeche(t[0][0], t[1][0], t[2][0]) > 0.005:
						_dreieck(st, terrain, center, hoehen, t[0], t[1], t[2])
		var v_n: Array = [nn, mitte_uv, kein, d_asph]
		for m in rand.size():
			var q0: Vector2 = rand[m]
			var q1: Vector2 = rand[(m + 1) % rand.size()]
			if _flaeche(nn, q0, q1) > 0.005:
				_dreieck(st, terrain, center, hoehen, v_n, [q0, mitte_uv, kein, d_asph],
					[q1, mitte_uv, kein, d_asph])
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.material_override = material()
	# Eine flach aufliegende Strasse wirft keinen Schatten.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = Vector3.ZERO
	return mi


static func _flaeche(a: Vector2, b: Vector2, c: Vector2) -> float:
	return absf((b - a).cross(c - a)) * 0.5


## Kennzahlen eines Netzes (fuer Pruefungen): Knoten, Kanten, Laenge, Kreuzungen (Grad >= 3).
static func zahlen(netz: Dictionary) -> Dictionary:
	var p: Array = netz["p"]
	var laenge := 0.0
	for k in netz["k"]:
		laenge += (p[int(k[0])] as Vector2).distance_to(p[int(k[1])])
	var kreuz := 0
	for g in netz["grad"]:
		if g >= 3:
			kreuz += 1
	return {"knoten": p.size(), "kanten": (netz["k"] as Array).size(), "laenge": laenge,
		"kreuzungen": kreuz}
