## WO KANN EIN HOEHLENPORTAL IN DIE TALWAND?
##
## Eine Hoehle laesst sich im Hoehenfeld nicht bauen — height_at liefert EINE Hoehe je
## Punkt, ein Ueberhang ist darin nicht darstellbar. Sie braucht eigene Geometrie mit
## eigener Kollision, so wie das Felsentor. Damit das Portal nicht in der Luft haengt oder
## im Berg verschwindet, muss die Wand an seiner Stelle steil genug sein und ueber dem
## Portal genug Fels stehen.
##
## Dieses Werkzeug tastet das Gelaende QUER ZUR TALACHSE an der Station des Flugplatzes ab
## und meldet je Abstand die Hoehe, die oertliche Steigung und wie viel Fels 120 m weiter
## im Berg noch darueber steht (die Deckenstaerke ueber einer 40 m hohen Halle).
##
## Godot --headless --path . --script res://tools/_hoehle_platz.gd -- [laengs=8800]
extends SceneTree

const START := Vector2(-11000.0, -2500.0)
const RICHTUNG := Vector2(0.6139, -0.7893)
const HALLE_H := 40.0        # lichte Hoehe der geplanten Halle
const TIEFE := 120.0         # wie weit die Halle in den Berg reicht

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var ua := OS.get_cmdline_user_args()
	var laengs := float(ua[0]) if ua.size() > 0 else 8800.0
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var mitte := START + RICHTUNG * laengs
	var quer := Vector2(RICHTUNG.y, -RICHTUNG.x)
	print("Station laengs %.0f, Mitte (%.0f / %.0f), Bahn auf 90 m" % [laengs, mitte.x, mitte.y])
	print(" Abstand   Hoehe   Steigung   Fels ueber der Decke (%.0f m tief)" % TIEFE)
	for seite in [-1.0, 1.0]:
		print("  --- Seite %+.0f (quer %.3f/%.3f) ---" % [seite, quer.x * seite, quer.y * seite])
		for i in 13:
			var d := float(i) * 80.0 + 160.0
			var p: Vector2 = mitte + quer * seite * d
			var h := tw.height_at(p.x, p.y)
			var p2: Vector2 = mitte + quer * seite * (d + 40.0)
			var steig := (tw.height_at(p2.x, p2.y) - h) / 40.0
			# Wie hoch steht der Berg 120 m TIEFER drin, ueber der Hallendecke?
			var pi: Vector2 = mitte + quer * seite * (d + TIEFE)
			var decke := tw.height_at(pi.x, pi.y) - (90.0 + HALLE_H)
			print("   %5.0f   %7.1f   %8.2f   %8.1f m%s"
				% [d, h, steig, decke,
					"   <- taugt" if steig > 0.55 and decke > 25.0 else ""])
	quit()
	return true
