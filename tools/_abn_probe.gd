## ABNAHME-PROBE (temporaer, wird nach dem Lauf wieder geloescht).
## Zwei Fragen, die _gebirge_check nicht beantwortet:
##  1. Wie steil steht die Wand quer zur Bahn DIREKT neben ADLERHORST? Der Querschnitt
##     dort misst nur alle 400 m und springt von 90 auf 417 m — zu grob, um Aushub von
##     gewachsenem Hang zu trennen.
##  2. Wie sieht das Laengsprofil HINTER dem Platz aus (8000..11400 m)?
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var t: TerrainWorld = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var quer := Vector2(dir.y, -dir.x)
	var ahl: float = K["ADLERHORST_LAENGS"]

	print("\n=== QUER DURCH ADLERHORST (laengs %.0f m), 50-m-Schritte ===" % ahl)
	var mid := start + dir * ahl
	var vor := 0.0
	for i in range(-24, 25):
		var d := float(i) * 50.0
		var p := mid + quer * d
		var h := t.height_at(p.x, p.y)
		var st := "" if i == -24 else "  %+5.1f Grad" % rad_to_deg(atan((h - vor) / 50.0))
		print("  %+6.0f m : %6.1f m%s" % [d, h, st])
		vor = h

	print("\n=== LAENGS HINTER DEM PLATZ (8000..11400 m), 200-m-Schritte ===")
	for i in range(40, 58):
		var l := float(i) * 200.0
		var p := start + dir * l
		print("  %5.0f m : %6.1f m" % [l, t.height_at(p.x, p.y)])
	quit()
	return true
