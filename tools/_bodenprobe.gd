## WELCHE REGEL FAERBT DIESEN BODEN? Im Bild um die Grossstadt liegen grosse helle Flaechen,
## die aussehen wie Wueste — der Wuestenzweig von _boden_farbe reagiert dort aber nicht auf
## Aenderungen. Diese Probe legt fuer ein Raster offen, was tatsaechlich gilt: Biom, Hoehe,
## Walddichte und Freihaltung, dazu die fertige Farbe.
##
## Godot --headless --path . --script res://tools/_bodenprobe.gd -- x z [halbe_kantenlaenge]
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var ua := OS.get_cmdline_user_args()
	var mx := float(ua[0]) if ua.size() > 0 else 4300.0
	var mz := float(ua[1]) if ua.size() > 1 else 2500.0
	var w := float(ua[2]) if ua.size() > 2 else 900.0
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	# Die Aufzaehlung hat mehr Eintraege als die drei, die man erwartet — ein fester
	# Namensarray lief hier aus dem Index. Also aus der Klasse selbst lesen.
	var namen: Array = TerrainWorld.Biome.keys()
	var zaehler := {}
	print("Probe um (%.0f / %.0f), halbe Kante %.0f m" % [mx, mz, w])
	print("   x        z      Hoehe   Biom     Farbe (r g b)")
	for j in 9:
		for i in 9:
			var x := mx - w + 2.0 * w * float(i) / 8.0
			var z := mz - w + 2.0 * w * float(j) / 8.0
			var h := tw.height_at(x, z)
			var b: int = tw.biome_at(x, z)
			zaehler[b] = int(zaehler.get(b, 0)) + 1
			if i == 4 and j % 2 == 0:
				var c: Color = tw._boden_farbe(Vector3(x, h, z))
				print("%8.0f %8.0f %7.1f   %-7s  %.2f %.2f %.2f"
					% [x, z, h, namen[b], c.r, c.g, c.b])
	var s := ""
	for k in zaehler:
		s += "%s %d  " % [namen[k], zaehler[k]]
	print("Verteilung im Raster: ", s)
	quit()
	return true
