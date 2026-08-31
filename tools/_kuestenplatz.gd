## Wo laesst sich an der neuen Kueste ein Flugplatz bauen?
##
## Zwei Plaetze heissen WESTKAP und SUEDSTRAND und lagen an der alten Kueste. Nach dem
## Vergroessern der Insel liegen sie 15 bis 17 km im Landesinneren — ihre Namen sind damit
## falsch, und die neue Flaeche hat kein Ziel. Dieses Werkzeug sucht auf ihren Peilungen
## eine Stelle, die nah genug am Wasser und flach genug fuer eine Bahn ist.
extends SceneTree
var f := 0
const PEILUNG := [["WESTKAP", Vector2(-9200, -600)], ["SUEDSTRAND", Vector2(2600, 9200)]]
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw = main.terrain
	for e in PEILUNG:
		var ri: Vector2 = (e[1] as Vector2).normalized()
		# Kueste suchen
		var kueste := 0.0
		var r := 8000.0
		while r < 40000.0:
			if tw.height_at(ri.x * r, ri.y * r) < TerrainWorld.SEA_Y:
				kueste = r
				break
			r += 150.0
		print("\n%s: Kueste bei %.1f km" % [String(e[0]), kueste / 1000.0])
		print("  Abstand |    Hoehe | Spanne im 700-m-Feld")
		for zurueck in [1200.0, 1800.0, 2600.0, 3600.0]:
			var p: Vector2 = ri * (kueste - zurueck)
			var lo := 1.0e9
			var hi := -1.0e9
			for i in 8:
				for j in 8:
					var h: float = tw.height_at(p.x + (float(i) - 3.5) * 200.0,
						p.y + (float(j) - 3.5) * 200.0)
					lo = minf(lo, h)
					hi = maxf(hi, h)
			print("  %6.0f m | %7.1f m | %6.0f m   (%.0f, %.0f)"
				% [zurueck, tw.height_at(p.x, p.y), hi - lo, p.x, p.y])
	quit()
	return true
