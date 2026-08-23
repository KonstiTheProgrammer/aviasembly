## STICHPROBE DES GANZEN HOEHENFELDES — Beleg dafuer, dass ein Eingriff nur dort wirkt,
## wo er soll. Rastert die Welt grob ab und druckt eine Pruefsumme je Gebiet.
## Vor und nach einer Aenderung laufen lassen und die Zeilen vergleichen: was sich nicht
## aendern durfte, hat dieselbe Summe.
##
## Godot --headless --path . --script res://tools/_welt_stichprobe.gd
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	# [Name, Mitte, Halbe Kantenlaenge]
	var felder := [
		["Spawn/Heimat", Vector2(0, 0), 1500.0],
		["Bergmassiv", Vector2(2400, 1500), 1200.0],
		["Canyon", Vector2(-5700, 2500), 2000.0],
		["Hochtal/Adlerhorst", Vector2(-7500, -7000), 3000.0],
		["Grossstadt", Vector2(4300, 3000), 1500.0],
		["Insel Ost", Vector2(16000, -3800), 900.0],
		["Insel Nord", Vector2(12500, -11500), 900.0],
		["Insel West", Vector2(-11500, 13000), 1100.0],
		["Vorland Vulkan (aussen)", Vector2(11800, -5600), 2600.0],
		["Vulkan selbst", Vector2(11800, -5600), 1300.0],
	]
	# DIE FARBE STEHT MIT IN DER PROBE, seit die Vulkanhaut dazugekommen ist. Eine
	# Hoehensumme allein belegt naemlich gar nichts mehr ueber die Welt daneben: ein
	# Eingriff, der nur _face_color anfasst, laesst jede Hoehe stehen und faerbt trotzdem
	# den halben Kontinent um. Gerechnet wird eine gewichtete Summe der drei Kanaele UND
	# des Alphakanals — der traegt seit dieser Runde die Glut, und ein a < 1 ausserhalb des
	# Vulkans waere ein leuchtender Fleck irgendwo in der Landschaft.
	for fe in felder:
		var name: String = fe[0]
		var m: Vector2 = fe[1]
		var hw: float = fe[2]
		var summe := 0.0
		var hoch := -9e9
		var fsum := 0.0
		var glut := 0.0
		for i in 41:
			for j in 41:
				var x := m.x - hw + 2.0 * hw * float(i) / 40.0
				var z := m.y - hw + 2.0 * hw * float(j) / 40.0
				var hh := tw.height_at(x, z)
				summe += hh
				hoch = maxf(hoch, hh)
				var c := tw._face_color(Vector3(x, hh, z), 0.92)
				fsum += c.r + 2.0 * c.g + 3.0 * c.b
				glut += 1.0 - c.a
		print("%-26s Summe %14.3f   hoechster Punkt %8.2f m   Farbe %10.4f   Glut %7.4f"
			% [name, summe, hoch, fsum, glut])
	quit()
	return true
