## DAS PROFIL DES HOCHTALS LAENGS SEINER ACHSE.
##
## Im Anflug auf ADLERHORST steht hinter dem Platz ein grauer Wall mit auffallend glattem,
## waagerechtem Deckel — er passt zu nichts ringsum, wo alles zackig ist. Aus dem Bild ist
## nicht zu entscheiden, ob dort zwei Bergketten zusammenlaufen, ob eine Flachzone im Weg
## steht oder ob eine Hoehe irgendwo gedeckelt wird. Dieses Profil entscheidet es.
##
## Godot --headless --path . --script res://tools/_talschluss.gd
extends SceneTree

const START := Vector2(-11000.0, -2500.0)
const RICHTUNG := Vector2(0.6139, -0.7893)

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var quer := Vector2(RICHTUNG.y, -RICHTUNG.x)
	print("laengs   Talboden   +-300 m     +-600 m     +-900 m    (quer zur Achse)")
	for i in range(60, 145):
		var l := float(i) * 100.0
		var p := START + RICHTUNG * l
		var h0 := tw.height_at(p.x, p.y)
		var zeile := "%6.0f   %8.1f" % [l, h0]
		for d: float in [300.0, 600.0, 900.0]:
			var a: Vector2 = START + RICHTUNG * l + quer * d
			var b: Vector2 = START + RICHTUNG * l - quer * d
			zeile += "   %5.0f/%5.0f" % [tw.height_at(a.x, a.y), tw.height_at(b.x, b.y)]
		# Sprung zum Vorgaenger auffaellig machen
		print(zeile)
	quit()
	return true
