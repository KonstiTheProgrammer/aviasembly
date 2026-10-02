## WAS KOSTET DER FLUSS IN DER HOEHENPROBE? height_at auf Feldern UEBER dem Silberfluss
## (600 x 600 m, Mitte auf dem Lauf) gegen dieselbe Probe ohne Fluesse (Zellraster leer) —
## die Differenz ist der Flussschnitt samt Suche im Zellraster. Dazu, wie viele Segmente eine
## Probe im Mittel durchsehen muss.
##   HOME=<test-home> Godot --headless --path . --script res://tools/_fluss_takt.gd
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var felder := [["Oberlauf", Vector2(5550, -13463)], ["Vorland", Vector2(4200, -6225)],
		["Mittellauf", Vector2(6838, 1000)], ["Tiefland", Vector2(10725, 8363)],
		["Muendung", Vector2(15900, 15600)]]
	print("Segmente gesamt: %d, Bloecke %d, Zellen %d x %d, Eintraege %d" % [tw._fl_a.size(),
		tw._flb_a.size(), tw._fl_nx, tw._fl_nz, tw._fl_blk.size()])
	print("Feld          je Probe mit   ohne Fluss   Fluss   Bloecke/Probe")
	var gesamt := 0.0
	for feld in felder:
		var mp: Vector2 = feld[1]
		var pts := PackedVector2Array()
		for i in 60:
			for j in 60:
				pts.append(mp + Vector2(float(i) * 10.0 - 300.0, float(j) * 10.0 - 300.0))
		for p in pts:
			tw.height_at(p.x, p.y)
		var seg := 0
		for p in pts:
			var k := tw._fl_zelle(p.x, p.y)
			if k >= 0:
				seg += tw._fl_start[k + 1] - tw._fl_start[k]
		var t0 := Time.get_ticks_usec()
		for wdh in 3:
			for p in pts:
				tw.height_at(p.x, p.y)
		var mit := float(Time.get_ticks_usec() - t0) / float(pts.size() * 3)
		# Ohne Fluss: Zellraster vorruebergehend leeren (die Schuerze laeuft weiter, liest
		# aber nur — hier wird nur _fl_nx umgestellt, das macht _fl_zelle zu -1).
		var nx := tw._fl_nx
		tw._fl_nx = 0
		t0 = Time.get_ticks_usec()
		for wdh in 3:
			for p in pts:
				tw.height_at(p.x, p.y)
		var ohne := float(Time.get_ticks_usec() - t0) / float(pts.size() * 3)
		tw._fl_nx = nx
		gesamt += mit - ohne
		# Nur die Suche und nur der Schnitt — ohne den Rest von height_at, also ohne dessen
		# Schwankung (die Chunk-Worker laufen nebenher). Bestes von fuenf Laeufen.
		var such := INF
		var schnitt := INF
		for wdh in 5:
			t0 = Time.get_ticks_usec()
			for p in pts:
				tw._fl_finden(p.x, p.y)
			such = minf(such, float(Time.get_ticks_usec() - t0) / float(pts.size()))
			t0 = Time.get_ticks_usec()
			for p in pts:
				tw._river_carve(p.x, p.y, 0.0)
			schnitt = minf(schnitt, float(Time.get_ticks_usec() - t0) / float(pts.size()))
		print("%-12s %8.2f us %10.2f us %7.2f us %10.1f   Suche %.2f us, Schnitt %.2f us" % [feld[0],
			mit, ohne, mit - ohne, float(seg) / float(pts.size()), such, schnitt])
	print("Flussanteil im Mittel: %.2f us je Probe" % (gesamt / felder.size()))
	quit()
	return true
