## Liegen die Schiffe noch im Wasser? Nach dem Vergroessern der Insel keine rhetorische
## Frage: sie standen auf Positionen, die zur alten Kuestenlinie gehoerten.
extends SceneTree
var f := 0
const ORTE := [["Schiff 1", Vector2(23189, -7730)], ["Schiff 2", Vector2(19120, -15695)],
	["Schiff 3", Vector2(-18051, 20268)], ["Schiff 4", Vector2(6843, -24695)],
	["Wrack", Vector2(23539, -6523)], ["Leuchtturm", Vector2(-950, -1250)]]
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw = main.terrain
	print("Ort         |   Gelaende |  Zustand")
	for e in ORTE:
		var p: Vector2 = e[1]
		var h: float = tw.height_at(p.x, p.y)
		var z := "im Wasser" if h < TerrainWorld.SEA_Y else "AUF DEM TROCKENEN"
		print("%-11s | %8.1f m | %s" % [String(e[0]), h, z])
		if h >= TerrainWorld.SEA_Y and String(e[0]) != "Leuchtturm":
			# Auf derselben Peilung nach aussen suchen, bis 900 m offenes Wasser da sind.
			var ri := p.normalized()
			var r := p.length()
			while r < 40000.0:
				r += 200.0
				var q: Vector2 = ri * r
				if tw.height_at(q.x, q.y) < TerrainWorld.SEA_Y - 3.0 \
						and tw.height_at(q.x + ri.x * 900.0, q.y + ri.y * 900.0) \
							< TerrainWorld.SEA_Y - 3.0:
					print("              -> neu: Vector2(%.0f, %.0f)  bei %.1f km"
						% [q.x, q.y, r / 1000.0])
					break
	quit()
	return true
