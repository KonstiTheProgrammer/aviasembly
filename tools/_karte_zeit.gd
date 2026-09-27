## WIE LANGE BRAUCHT DIE VOLLBILD-KARTE (Taste M)?
##
## Main startet WorldMap.generate_image(terrain, 512) beim Weltaufbau im Hintergrund;
## bis es fertig ist, meldet M nur "Karte wird noch gezeichnet ...". Gemessen wird die
## reine Rechenzeit derselben Funktion, dazu eine Pruefsumme, damit eine schnellere
## Fassung nachweislich DASSELBE Bild liefert.
##
##   HOME=/tmp/avi_home Godot --headless --path . --script res://tools/_karte_zeit.gd
extends SceneTree
var f := 0
var m: Node
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		get_root().add_child(m)
	if f == 10:
		var t0 := Time.get_ticks_msec()
		var img: Image = WorldMap.generate_image(m.terrain, 512)
		var ms := Time.get_ticks_msec() - t0
		var summe := 0
		var daten := img.get_data()
		for i in range(0, daten.size(), 7):
			summe = (summe * 31 + daten[i]) % 1000000007
		print("KARTE 512 px: %.2f s   Pruefsumme %d" % [ms / 1000.0, summe])
		quit()
	return false
