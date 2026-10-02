## FLUSSLEBEN-PRUEFUNG: passt jedes Ding am Fluss zu Wasser und Gelaende?
##
## Flussleben.gd setzt Seerosen, Enten, Reiher, Schilf, Steine und Stege nach der GEPLANTEN
## Uferlinie (Flussleben._ufer). Das Gelaende rechnet aber mit einer wandernden Uferlinie
## (UFER_WANDERN) und dem 8-m-Netz — beides kann ein Ding aufs Trockene oder unter Wasser
## setzen. Hier wird jede Instanz gegen das ECHTE Gelaende (height_at) und den Wasserspiegel
## (_fluss_naechst) gehalten:
##   Seerose  muss auf Wasser liegen (Grund mind. 0,15 m unter dem Spiegel)
##   Ente     der ganze Kreis, den die Familie paddelt, muss Wasser sein
##   Reiher   steht am Ufer: Fuesse hoechstens knapp ueber dem Boden, nicht im Tiefen
##   Schilf   Fuss am Boden (nicht schwebend, nicht vergraben)
##   Stein    sitzt auf dem Boden (Unterkante nicht ueber dem Gelaende)
## Ausgabe: je Art Zahl und Beanstandungen mit Lage, dann URTEIL.
##   HOME=<test-home> Godot --headless --fixed-fps 60 --path . --script res://tools/_flussleben_check.gd
extends SceneTree

var f := 0
var m: Node = null
var fehler := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 12:
		_pruefen()
		quit()
	return false


## Die Lagen rechnet die Pruefung genauso wie Flussleben.bauen (gleicher Zufallsstart, gleiche
## Reihenfolge) — aus den MultiMeshes lesen geht headless nicht: der Dummy-Renderer speichert
## keine Instanzlagen und liefert ueberall die Nulllage.
var _d := {}


func _sammeln(tw: TerrainWorld) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5F1055
	for k in ["steine", "schilf", "rosen", "bluete", "reiher", "enten"]:
		_d[k] = {}
	for rv: Dictionary in tw.rivers:
		var pts: PackedVector3Array = rv["pts"]
		if pts.size() < 3:
			continue
		Flussleben._steine_sammeln(rv, tw, rng, _d["steine"])
		Flussleben._ufer_sammeln(rv, tw, rng, _d["schilf"], _d["rosen"], _d["bluete"], _d["reiher"], _d["enten"])


func _instanzen(art: String) -> Array:
	var out: Array = []
	for key in _d[art]:
		out.append_array(_d[art][key])
	return out


func _melde(art: String, liste: Array, n: int) -> void:
	var zeile := "%-8s %6d   beanstandet %4d" % [art, n, liste.size()]
	print(zeile + ("   OK" if liste.is_empty() else ""))
	for k in mini(liste.size(), 8):
		print("    " + String(liste[k]))
	fehler += liste.size()


func _pruefen() -> void:
	var tw: TerrainWorld = m.terrain
	_sammeln(tw)
	# Wasserband liegt 0,15 m ueber den Stuetzpunkten (TerrainWorld._build_river_water).
	var spiegel := func(x: float, z: float) -> float:
		var v: Vector4 = tw._fluss_naechst(x, z)
		return v.y + 0.15 if v.x < INF else -INF

	# --- Seerosen -------------------------------------------------------------------
	var rosen := _instanzen("rosen") + _instanzen("bluete")
	var bad: Array = []
	for x: Transform3D in rosen:
		var p := x.origin
		var h := tw.height_at(p.x, p.z)
		var s: float = spiegel.call(p.x, p.z)
		if s - h < 0.15:
			bad.append("Seerose auf dem Trockenen bei (%.0f, %.0f): Grund %.2f, Spiegel %.2f" % [p.x, p.z, h, s])
		elif absf(p.y - s) > 0.25:
			bad.append("Seerose nicht auf dem Spiegel bei (%.0f, %.0f): %.2f gegen %.2f" % [p.x, p.z, p.y, s])
	_melde("Seerosen", bad, rosen.size())

	# --- Enten ----------------------------------------------------------------------
	var enten := _instanzen("enten")
	bad = []
	for x: Transform3D in enten:
		var dreh := x.origin + x.basis * Vector3(Flussleben.ENTEN_R, 0.0, 0.0)
		var trocken := 0
		var schlimm := 0.0
		for k in 16:
			var a := TAU * float(k) / 16.0
			var q := dreh + Vector3(cos(a), 0.0, sin(a)) * (Flussleben.ENTEN_R + 0.3)
			var h := tw.height_at(q.x, q.z)
			var s: float = spiegel.call(q.x, q.z)
			if s - h < 0.10:
				trocken += 1
				schlimm = maxf(schlimm, h - s)
		if trocken > 0:
			bad.append("Enten an Land bei (%.0f, %.0f): %d/16 Kreispunkte trocken, Boden bis %.2f m ueber dem Spiegel" % [dreh.x, dreh.z, trocken, schlimm])
	_melde("Enten", bad, enten.size())

	# --- Reiher ---------------------------------------------------------------------
	var reiher := _instanzen("reiher")
	bad = []
	for x: Transform3D in reiher:
		var p := x.origin
		var h := tw.height_at(p.x, p.z)
		var s: float = spiegel.call(p.x, p.z)
		# Im seichten Wasser watet er: die Fuesse duerfen dann ueber dem Grund, aber nicht ueber
		# dem Spiegel stehen (das Wasser ist undurchsichtig).
		var fuss_bezug := maxf(h, s - 0.25) if s > h else h
		if p.y - fuss_bezug > 0.12:
			bad.append("Reiher schwebt bei (%.0f, %.0f): %.2f m ueber dem Boden (Spiegel %+.2f)" % [p.x, p.z, p.y - h, s - h])
		elif h - p.y > 0.15:
			bad.append("Reiher im Boden bei (%.0f, %.0f): %.2f m" % [p.x, p.z, h - p.y])
		if s - h > 0.45:
			bad.append("Reiher im tiefen Wasser bei (%.0f, %.0f): %.2f m" % [p.x, p.z, s - h])
	_melde("Reiher", bad, reiher.size())

	# --- Schilf ---------------------------------------------------------------------
	var schilf := _instanzen("schilf")
	bad = []
	for x: Transform3D in schilf:
		var p := x.origin
		var h := tw.height_at(p.x, p.z)
		if p.y - h > 0.20:
			bad.append("Schilf schwebt bei (%.0f, %.0f): %.2f m" % [p.x, p.z, p.y - h])
		elif h - p.y > 0.40:
			bad.append("Schilf vergraben bei (%.0f, %.0f): %.2f m" % [p.x, p.z, h - p.y])
	_melde("Schilf", bad, schilf.size())

	# --- Steine ---------------------------------------------------------------------
	var steine := _instanzen("steine")
	var fels: Mesh = tw.get("_mesh_rock")
	var unten_y := fels.get_aabb().position.y if fels else 0.0
	bad = []
	for x: Transform3D in steine:
		var p := x.origin
		var h := tw.height_at(p.x, p.z)
		# Unterkante des Felsnetzes darf nicht ueber dem Boden haengen.
		var u := p.y + unten_y * x.basis.get_scale().y
		if u - h > 0.15:
			bad.append("Stein schwebt bei (%.0f, %.0f): Unterkante %.2f m ueber dem Boden" % [p.x, p.z, u - h])
	_melde("Steine", bad, steine.size())

	# --- Stege: Kopf auf dem Ufer (nicht im Hang, nicht hoch in der Luft), Ende ueber Wasser,
	# keine Planke im Boden. Masse wie Flussleben._stege_bauen (Deck 0,85 ueber c.y).
	bad = []
	var n_steg := 0
	var fl: Node = m.find_child("Flussleben", true, false)
	for k in fl.get_children():
		if not k.has_meta("steg_land"):
			continue
		n_steg += 1
		var land: float = k.get_meta("steg_land")
		var kn := k as Node3D
		var mi: MeshInstance3D = null
		for kk in kn.get_children():
			if kk is MeshInstance3D and mi == null:
				mi = kk
		var b: Basis = mi.basis
		var o := kn.global_position
		var deck := o.y + 0.85
		var ende := o + b * Vector3(0, 0, -10.0)
		var he := tw.height_at(ende.x, ende.z)
		var se: float = spiegel.call(ende.x, ende.z)
		if se - he < 0.2:
			bad.append("Stegende auf dem Trockenen bei (%.0f, %.0f): Grund %.2f, Spiegel %.2f" % [ende.x, ende.z, he, se])
		var z := -10.0
		var hoch_max := -INF
		while z <= land:
			var q := o + b * Vector3(0, 0, z)
			hoch_max = maxf(hoch_max, tw.height_at(q.x, q.z) - deck)
			z += 0.25
		if hoch_max > -0.04:
			bad.append("Steg steckt im Boden bei (%.0f, %.0f): Boden bis %.2f m ueber dem Deck" % [o.x, o.z, hoch_max])
		var kopf := o + b * Vector3(0, 0, land)
		var hk := tw.height_at(kopf.x, kopf.z)
		if deck - hk > 0.9:
			bad.append("Stegkopf schwebt bei (%.0f, %.0f): %.2f m ueber dem Grund" % [kopf.x, kopf.z, deck - hk])
		print("    Steg bei (%.0f, %.0f): an Land %.1f m, Kopf %.2f unter dem Deck, Ende Wassertiefe %.2f" % [o.x, o.z, land, deck - hk, se - he])
	_melde("Stege", bad, n_steg)

	print("URTEIL: %s" % ("OK" if fehler == 0 else "%d Beanstandungen" % fehler))
