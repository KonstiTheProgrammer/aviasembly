## Wo auf der aeusseren Insel steht ein Leuchtturm richtig?
## Er stand zuerst auf der bewaldeten Kuppe und war dort niedriger als die Kiefern —
## also unsichtbar. Ein Leuchtturm gehoert ans Ufer und muss frei stehen.
extends SceneTree
var f := 0
const MITTE := Vector2(30100, -7600)
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw = main.terrain
	print("Abstand vom Inselmittelpunkt nach Osten (seewaerts):")
	for r in [0.0, 150.0, 250.0, 350.0, 430.0, 500.0, 560.0, 620.0]:
		var p := MITTE + Vector2(r, 0.0)
		print("  %4.0f m -> Hoehe %6.1f m" % [r, tw.height_at(p.x, p.y)])
	quit()
	return true
