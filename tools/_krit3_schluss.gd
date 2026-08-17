## KRITIKPROBE: wie hoch schliesst das Tal hinten ab — gegen die Flanken gerechnet?
## Godot --headless --path . --script res://tools/_krit3_schluss.gd
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
	print("laengs | Achse | max Flanke links | max Flanke rechts")
	for i in range(16, 30):
		var lg := float(i) * 400.0
		var p := start + dir * lg
		var h: float = tw.height_at(p.x, p.y)
		var ml := 0.0
		var mr := 0.0
		var d := 200.0
		while d <= 3000.0:
			ml = maxf(ml, tw.height_at(p.x + quer.x * d, p.y + quer.y * d))
			mr = maxf(mr, tw.height_at(p.x - quer.x * d, p.y - quer.y * d))
			d += 50.0
		print("%6.0f | %5.0f | %6.0f | %6.0f" % [lg, h, ml, mr])
	quit()
	return true
