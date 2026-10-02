## WAS KOSTET DIE FELDFLUR IM CHUNKBAU? Baut feine und grobe Chunks in einer Feldflur (und zum
## Vergleich ausserhalb) und misst Gelaende (fein/grob) und Bewuchs je Chunk, bestes von drei.
## Die Fernschuerze wird vorher angehalten (sie rechnet sonst nebenher).
##   HOME=<test-home> Godot --headless --path . --script res://tools/_feld_zeit.gd
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	main.set("_fern_stopp", true)
	var tw: TerrainWorld = main.terrain
	var orte := [["Flur Tiefland", Vector2(7000, 7000)], ["Flur Ost", Vector2(16500, -7000)],
		["Huegelland", Vector2(1500, -2500)]]
	print("Ort              fein ms (mit Bewuchs)   grob ms   Bewuchs ms   (je Chunk, Mittel ueber 6 Chunks)")
	for ort in orte:
		var mp: Vector2 = ort[1]
		var k0 := Vector2i(floori(mp.x / TerrainWorld.CHUNK), floori(mp.y / TerrainWorld.CHUNK))
		var keys: Array[Vector2i] = []
		for i in 3:
			for j in 2:
				keys.append(k0 + Vector2i(i, j))
		var summe := [0.0, 0.0, 0.0]
		for key in keys:
			var best := [INF, INF, INF]
			for wdh in 3:
				var t0 := Time.get_ticks_usec()
				tw._make_chunk_data(key, TerrainWorld.AUFTRAG_FEIN)
				best[0] = minf(best[0], float(Time.get_ticks_usec() - t0) / 1000.0)
				t0 = Time.get_ticks_usec()
				var grob := tw._make_chunk_data(key, TerrainWorld.AUFTRAG_GROB)
				best[1] = minf(best[1], float(Time.get_ticks_usec() - t0) / 1000.0)
				var hd: PackedFloat32Array = grob.get("hd", PackedFloat32Array())
				if not hd.is_empty():
					t0 = Time.get_ticks_usec()
					tw._bewuchs_rechnen(key, hd, hd)
					best[2] = minf(best[2], float(Time.get_ticks_usec() - t0) / 1000.0)
			for q in 3:
				summe[q] += best[q] / keys.size()
		print("%-15s %8.1f %9.1f %12.1f" % [ort[0], summe[0], summe[1], summe[2]])
	quit()
	return true
