## KRITIKER-MESSUNG: verengt sich das Tal wirklich zur Tiefe?
##
## Unabhaengig von tools/_tal_keil.gd geschrieben. Misst zwei Dinge:
##   1. Zusammenhaengende Talbodenbreite je Laengsposition (Gelaende unter einer Schwelle,
##      von der Achse aus nach beiden Seiten gelaufen, nicht "alle Proben unter Schwelle").
##   2. Die HOEHENKONTUREN quer: bei welcher Querentfernung ist die Flanke auf 300/600 m?
##      Ein Keil muss sich auch dort verengen, nicht nur am Boden.
##
## Godot --headless --path . --script res://tools/_krit_keil.gd
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var quer := Vector2(-dir.y, dir.x)
	var LAENGE: float = K["TAL_LAENGE"]

	print("=== TALBODEN, zusammenhaengend von der Achse (Raster 25 m) ===")
	print("laengs |  <200m  <300m | Flanke 300m  Flanke 600m  (Querentf. je Seite, links/rechts)")
	var reihe: Array = []
	for i in range(0, 40):
		var lg := float(i) * 250.0
		if lg > LAENGE:
			break
		var p := start + dir * lg
		var b200 := _breite(tw, p, quer, 200.0)
		var b300 := _breite(tw, p, quer, 300.0)
		var f300 := _flanke(tw, p, quer, 300.0)
		var f600 := _flanke(tw, p, quer, 600.0)
		reihe.append([lg, b200])
		print("%6.0f | %6.0f %6.0f | %5.0f/%5.0f   %5.0f/%5.0f"
			% [lg, b200, b300, f300.x, f300.y, f600.x, f600.y])

	# Verhaeltnis vorn zu hinten ueber die Strecke, in der es ein Tal gibt.
	print("\n=== KEILMASS ===")
	var vorn := 0.0
	var n1 := 0
	var hinten := 0.0
	var n2 := 0
	for e in reihe:
		var lg: float = e[0]
		var b: float = e[1]
		if lg >= 500.0 and lg <= 2500.0:
			vorn += b
			n1 += 1
		if lg >= 6500.0 and lg <= 8500.0:
			hinten += b
			n2 += 1
	if n1 > 0 and n2 > 0:
		vorn /= float(n1)
		hinten /= float(n2)
		print("  Mittel  500..2500 m: %.0f m   Mittel 6500..8500 m: %.0f m   -> %.2f : 1"
			% [vorn, hinten, vorn / maxf(hinten, 1.0)])
	# Monotonie: wie oft wird das Tal auf dem Weg nach innen wieder BREITER?
	var aufweitungen := 0.0
	var stellen := 0
	for i in range(1, reihe.size()):
		var lg: float = reihe[i][0]
		if lg > 9000.0:
			break
		var d: float = reihe[i][1] - reihe[i - 1][1]
		if d > 0.0:
			aufweitungen += d
			stellen += 1
	print("  Aufweitungen bis 9000 m: %.0f m an %d Stellen (0 waere streng monoton)"
		% [aufweitungen, stellen])
	quit()
	return true

## Zusammenhaengende Breite: von der Achse aus nach beiden Seiten, solange unter schwelle.
func _breite(tw: TerrainWorld, p: Vector2, quer: Vector2, schwelle: float) -> float:
	var b := 0.0
	for vz: float in [1.0, -1.0]:
		var d := 0.0
		while d < 4000.0:
			d += 25.0
			var q: Vector2 = p + quer * vz * d
			if tw.height_at(q.x, q.y) > schwelle:
				break
		b += d - 25.0
	return b

## Querentfernung, bei der die Flanke je Seite die Hoehe hoehe zum ersten Mal erreicht.
func _flanke(tw: TerrainWorld, p: Vector2, quer: Vector2, hoehe: float) -> Vector2:
	var r := Vector2(4000.0, 4000.0)
	for k in range(0, 2):
		var vz := 1.0 if k == 0 else -1.0
		var d := 0.0
		while d < 4000.0:
			d += 25.0
			var q := p + quer * vz * d
			if tw.height_at(q.x, q.y) >= hoehe:
				break
		r[k] = d
	return r
