## PRUEFT, DASS DER BEWUCHS NICHT VON DER DETAILSTUFE ABHAENGT:
##  (1) grob und fein setzen DIESELBEN Pflanzen (Art, Zahl, Reihenfolge, Lage x/z, Drehung,
##      Groesse); nur die Standhoehe darf abweichen (jede Stufe steht auf ihrer Flaeche).
##      Grob heisst wie im Spiel: Gelaende-Auftrag ohne Bewuchs, dann AUFTRAG_BEWUCHS
##      (_bewuchs_rechnen auf der groben Flaeche).
##  (2) der feine Bau MIT VORLAGE (Bewuchs des groben uebernommen, _bewuchs_umsetzen) ist
##      bis auf Rundung derselbe wie der frisch gerechnete feine.
## Ohne (1) tauschte das Abloesen grob -> fein sichtbar den Wald aus ("die Baeume
## verschwinden die ganze Zeit, auch unter mir").
##   HOME=<test-home> Godot --headless --path . --script res://tools/_bewuchs_stufen_check.gd
extends SceneTree
var m: Node
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
	if f == 8:
		_pruefen()
		quit()
	return false


## Vergleicht zwei Bauergebnisse; liefert [Pflanzen, Abweichungen, Hoehendifferenzen].
func _vergleich(a: Dictionary, b: Dictionary, k: Vector2i) -> Array:
	var n := 0
	var fehler := 0
	var dys := PackedFloat32Array()
	for teil in ["flora", "rocks"]:
		var la: Array = []
		var lb: Array = []
		if teil == "flora":
			var fa: Dictionary = a["flora"]
			var fb: Dictionary = b["flora"]
			if fa.keys() != fb.keys():
				print("  Arten weichen ab bei ", k)
				fehler += 1
				continue
			for art in fa:
				la.append_array(fa[art])
				lb.append_array(fb[art])
		else:
			la = a["rocks"]
			lb = b["rocks"]
		if la.size() != lb.size():
			print("  Anzahl %s weicht ab bei %s: %d / %d" % [teil, k, la.size(), lb.size()])
			fehler += 1
			continue
		for i in la.size():
			var xa: Transform3D = la[i]
			var xb: Transform3D = lb[i]
			n += 1
			if xa.basis != xb.basis or absf(xa.origin.x - xb.origin.x) > 1e-4 \
					or absf(xa.origin.z - xb.origin.z) > 1e-4:
				fehler += 1
			dys.append(absf(xa.origin.y - xb.origin.y))
	return [n, fehler, dys]


func _pruefen() -> void:
	var t: TerrainWorld = m.terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var s1 := [0, 0, PackedFloat32Array()]
	var s2 := [0, 0, PackedFloat32Array()]
	for n in 16:
		var k := Vector2i(rng.randi_range(-60, 60), rng.randi_range(-60, 60))
		if n == 0:
			k = Vector2i(-22, -17)
		var fein: Dictionary = t._make_chunk_data(k, TerrainWorld.AUFTRAG_FEIN)
		# Grob wie im Spiel: erst das Gelaende, dann der Bewuchs-Auftrag auf dessen Flaeche hd.
		var gelaende: Dictionary = t._make_chunk_data(k, TerrainWorld.AUFTRAG_GROB)
		var grob := {"flora": {}, "rocks": []}
		if gelaende["bewuchs_offen"]:
			var fr: Array = t._bewuchs_rechnen(k, gelaende["hd"], gelaende["hd"])
			grob = {"flora": fr[0], "rocks": fr[1]}
		if not (gelaende["flora"] as Dictionary).is_empty() or not (gelaende["rocks"] as Array).is_empty():
			print("  grobes Gelaende traegt schon Bewuchs bei ", k)
			s1[1] += 1
		var aus_vorlage: Dictionary = t._make_chunk_data(k, TerrainWorld.AUFTRAG_FEIN_AUS_GROB,
			[grob["flora"], grob["rocks"]])
		for paar in [[fein, grob, s1], [fein, aus_vorlage, s2]]:
			var r := _vergleich(paar[0], paar[1], k)
			var ziel: Array = paar[2]
			ziel[0] += r[0]
			ziel[1] += r[1]
			# Packed-Arrays sind Werte: ueber einen Cast angehaengt landete es in einer Kopie.
			ziel[2] = (ziel[2] as PackedFloat32Array) + (r[2] as PackedFloat32Array)
	var ok := true
	for e in [["GROB/FEIN", s1, 5.0], ["VORLAGE/FEIN", s2, 0.01]]:
		var s: Array = e[1]
		var dys: PackedFloat32Array = s[2]
		dys.sort()
		var dmax := dys[dys.size() - 1] if dys.size() > 0 else 0.0
		var gut: bool = s[1] == 0 and dmax <= float(e[2])
		ok = ok and gut
		print("BEWUCHS %-12s %d Pflanzen, %d Abweichungen, Hoehendifferenz Median %.3f / 99 %% %.3f / max %.3f m -> %s"
			% [e[0], s[0], s[1], dys[dys.size() / 2], dys[dys.size() * 99 / 100], dmax, "OK" if gut else "FEHLER"])
	print("BEWUCHS-STUFEN ", "OK" if ok else "FEHLER")
