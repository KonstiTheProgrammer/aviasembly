## Wo steigt das Gelaende innerhalb der geladenen Chunks steil an? Nur Hilfsmittel fuer
## tools/_rakete_gelaende.gd — ein Durchflugtest ist wertlos, wenn er auf eine Ebene zielt.
extends SceneTree
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw = main.terrain
	print("Richtung |  500 m | 1000 m | 1500 m | 2000 m | 2500 m")
	for gr in [0, 45, 90, 135, 180, 225, 270, 315]:
		var r := deg_to_rad(float(gr))
		var zeile := "%7d° |" % gr
		for d in [500.0, 1000.0, 1500.0, 2000.0, 2500.0]:
			zeile += " %6.0f |" % tw.height_at(sin(r) * d, -cos(r) * d)
		print(zeile)
	quit()
	return true
