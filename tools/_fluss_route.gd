## FINDET DEN LAUF DES HAUPTSTROMS auf dem echten Gelaende (ohne Fluesse).
##
## Dijkstra auf einem 150-m-Raster von der Quelle bis zur ersten Meereszelle an der
## Suedkueste. Kosten je Schritt: Laenge x (1 + Hoehe/60) — der Weg sucht die Talboeden —
## plus 80 je Meter BERGAUF (Wasser fliesst nicht hinauf; wo es muss, graebt der Fluss eine
## Schlucht, und die soll kurz sein). Flugplaetze, Orte und der Vulkan sind gesperrt: der
## Fluss graebt sein Bett, und durch eine Startbahn soll er nicht laufen.
## Ausgabe: vereinfachte Punktliste (Douglas-Peucker 110 m + Chaikin) als GDScript.
##
##   HOME=<test-home> Godot --headless --path . --script res://tools/_fluss_route.gd -- qx qz
extends SceneTree

const ZELLE := 150.0
const X0 := -3000.0
const X1 := 17000.0
const Z0 := -16500.0
const Z1 := 26500.0
const ZIEL_Z := 18000.0        # Meer erst suedlich davon zaehlt als Muendung (nicht der Ostgolf)

var m: Node
var f := 0
var quelle := Vector2(5600, -12200)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 2:
		quelle = Vector2(float(a[0]), float(a[1]))


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
	if f == 8:
		_rechnen()
		quit()
	return false


func _rechnen() -> void:
	var t: TerrainWorld = m.terrain
	var alle := t.rivers
	t.rivers = []                                    # gewachsenes Gelaende, ohne Fluesse
	var nx := int((X1 - X0) / ZELLE)
	var nz := int((Z1 - Z0) / ZELLE)
	var h := PackedFloat32Array()
	h.resize(nx * nz)
	var sperre := PackedByteArray()
	sperre.resize(nx * nz)
	var t0 := Time.get_ticks_msec()
	for iz in nz:
		for ix in nx:
			var x := X0 + (float(ix) + 0.5) * ZELLE
			var z := Z0 + (float(iz) + 0.5) * ZELLE
			h[iz * nx + ix] = t.height_at(x, z)
	# Sperrzonen: alle Flugplaetze plus Rand, Grossstadt, Kleinstadt, Neonbucht, Vulkan
	var zonen: Array = []
	for af in t.airfields:
		var p: Vector3 = af["pos"]
		zonen.append([Vector2(p.x, p.z), 1500.0])
	for zz in [[Vector2(4300, 2500), 1300.0], [Vector2(1400, 750), 900.0],
			[Vector2(11800, -5600), 2700.0], [Vector2(2352, -3480), 1000.0]]:
		zonen.append(zz)
	for iz in nz:
		for ix in nx:
			var p := Vector2(X0 + (float(ix) + 0.5) * ZELLE, Z0 + (float(iz) + 0.5) * ZELLE)
			for zo in zonen:
				if p.distance_to(zo[0]) < float(zo[1]):
					sperre[iz * nx + ix] = 1
					break
	print("ROUTE Raster %dx%d, Hoehen in %.1f s" % [nx, nz, (Time.get_ticks_msec() - t0) / 1000.0])
	# Dijkstra mit Binaerheap
	var dist := PackedFloat32Array()
	dist.resize(nx * nz)
	dist.fill(1.0e30)
	var vor := PackedInt32Array()
	vor.resize(nx * nz)
	vor.fill(-1)
	var qi := clampi(int((quelle.x - X0) / ZELLE), 0, nx - 1)
	var qk := clampi(int((quelle.y - Z0) / ZELLE), 0, nz - 1)
	var start := qk * nx + qi
	print("ROUTE Quelle %.0f m" % h[start])
	dist[start] = 0.0
	var heap_k := PackedFloat32Array([0.0])
	var heap_v := PackedInt32Array([start])
	var ziel := -1
	var nb := [[1, 0, 1.0], [-1, 0, 1.0], [0, 1, 1.0], [0, -1, 1.0],
		[1, 1, 1.4142], [1, -1, 1.4142], [-1, 1, 1.4142], [-1, -1, 1.4142]]
	while heap_k.size() > 0:
		# pop min
		var k0 := heap_k[0]
		var v0 := heap_v[0]
		var last := heap_k.size() - 1
		heap_k[0] = heap_k[last]
		heap_v[0] = heap_v[last]
		heap_k.resize(last)
		heap_v.resize(last)
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var s := i
			if l < heap_k.size() and heap_k[l] < heap_k[s]:
				s = l
			if r < heap_k.size() and heap_k[r] < heap_k[s]:
				s = r
			if s == i:
				break
			var tk := heap_k[i]; heap_k[i] = heap_k[s]; heap_k[s] = tk
			var tv := heap_v[i]; heap_v[i] = heap_v[s]; heap_v[s] = tv
			i = s
		if k0 > dist[v0]:
			continue
		var cx := v0 % nx
		var cz := v0 / nx
		var hc := h[v0]
		var z_welt := Z0 + (float(cz) + 0.5) * ZELLE
		if hc < TerrainWorld.SEA_Y - 1.0 and z_welt > ZIEL_Z:
			ziel = v0
			break
		for e in nb:
			var ax: int = cx + int(e[0])
			var az: int = cz + int(e[1])
			if ax < 0 or az < 0 or ax >= nx or az >= nz:
				continue
			var w := az * nx + ax
			var hn := h[w]
			var zw := Z0 + (float(az) + 0.5) * ZELLE
			if hn < TerrainWorld.SEA_Y - 1.0 and zw <= ZIEL_Z:
				continue                       # anderes Meer (Ostgolf): gesperrt
			var d := ZELLE * float(e[2])
			var c := d * (1.0 + maxf(hn, 0.0) / 60.0) + 300.0 * maxf(0.0, hn - hc)
			if sperre[w] == 1:
				c += 6000.0
			var nd := k0 + c
			if nd < dist[w]:
				dist[w] = nd
				vor[w] = v0
				# push
				heap_k.append(nd)
				heap_v.append(w)
				var j := heap_k.size() - 1
				while j > 0:
					var p := (j - 1) / 2
					if heap_k[p] <= heap_k[j]:
						break
					var tk2 := heap_k[p]; heap_k[p] = heap_k[j]; heap_k[j] = tk2
					var tv2 := heap_v[p]; heap_v[p] = heap_v[j]; heap_v[j] = tv2
					j = p
	if ziel < 0:
		print("ROUTE kein Weg gefunden")
		return
	var pfad: Array[Vector2] = []
	var hp: Array[float] = []
	var v := ziel
	while v >= 0:
		pfad.push_front(Vector2(X0 + (float(v % nx) + 0.5) * ZELLE, Z0 + (float(v / nx) + 0.5) * ZELLE))
		hp.push_front(h[v])
		v = vor[v]
	var laenge := 0.0
	var gesperrt := 0
	for k in range(1, pfad.size()):
		laenge += pfad[k].distance_to(pfad[k - 1])
	print("ROUTE %d Zellen, %.1f km, Hoehen Quelle %.0f m -> Muendung %.0f m"
		% [pfad.size(), laenge / 1000.0, hp[0], hp[hp.size() - 1]])
	# Anstiege entlang des Weges (wo der Fluss graben muss)
	var tiefster := hp[0]
	var max_graben := 0.0
	for k in hp.size():
		tiefster = minf(tiefster, hp[k])
		max_graben = maxf(max_graben, hp[k] - tiefster)
	print("ROUTE groesster Einschnitt noetig: %.1f m" % max_graben)
	var prof := "ROUTE_PROFIL "
	var tief2 := hp[0]
	for k in range(0, hp.size(), 6):
		tief2 = minf(tief2, hp[k])
		prof += "%d/%d " % [roundi(hp[k]), roundi(hp[k] - tief2)]
	print(prof)
	var einfach := _dp(pfad, 110.0)
	# Chaikin einmal, Enden festhalten
	var glatt: Array[Vector2] = [einfach[0]]
	for k in range(einfach.size() - 1):
		var a2 := einfach[k]
		var b2 := einfach[k + 1]
		if k > 0:
			glatt.append(a2.lerp(b2, 0.25))
		if k < einfach.size() - 2:
			glatt.append(a2.lerp(b2, 0.75))
	glatt.append(einfach[einfach.size() - 1])
	var zeile := "ROUTE_PUNKTE ["
	for k in glatt.size():
		zeile += "Vector2(%d, %d), " % [roundi(glatt[k].x), roundi(glatt[k].y)]
		if k % 4 == 3:
			zeile += "\n\t"
	print(zeile + "]")
	print("ROUTE %d Punkte nach Vereinfachung" % glatt.size())
	t.rivers = alle


func _dp(p: Array[Vector2], eps: float) -> Array[Vector2]:
	if p.size() < 3:
		return p
	var a := p[0]
	var b := p[p.size() - 1]
	var best := -1.0
	var bi := 0
	for i in range(1, p.size() - 1):
		var d := _abstand(p[i], a, b)
		if d > best:
			best = d
			bi = i
	if best <= eps:
		return [a, b]
	var links := _dp(p.slice(0, bi + 1), eps)
	var rechts := _dp(p.slice(bi), eps)
	links.remove_at(links.size() - 1)
	links.append_array(rechts)
	return links


func _abstand(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
