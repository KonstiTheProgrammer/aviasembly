## GROBE LAND/MEER-KARTE der echten Spielwelt als Text.
##
## WOFUER: bevor man irgendwo ein Massiv, einen Flugplatz oder einen POI setzt, muss man
## wissen, ob dort ueberhaupt Land ist. Die Belegung aus Main.gd sagt nur, was schon da
## steht — nicht, wo der Meeresspiegel liegt. Diese Datei instanziert Main (also die
## ECHTE Welt mit Spielstand-Seed, allen Massiven und Flachzonen) und tastet das
## Hoehenfeld ab.
##
## Godot --headless --path . --script res://tools/_landkarte.gd -- [km=16] [schritt=1000]
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var km := 16.0
	var schritt := 1000.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("km="):
			km = float(a.substr(3))
		elif a.begins_with("schritt="):
			schritt = float(a.substr(8))
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	if tw == null:
		print("kein Terrain"); quit(); return true
	print("Hoehe in Metern, . = Meer, Zahl = Hundertmeter (3 = 300 m)")
	var n := int(km * 1000.0 / schritt)
	var kopf := "      "
	for c in range(-n, n + 1):
		kopf += "%2d" % int(round(c * schritt / 1000.0)) if absf(c * schritt) < 10000.0 else " *"
	print(kopf)
	for r in range(-n, n + 1):
		var zeile := "%5d " % int(r * schritt / 1000.0)
		for c in range(-n, n + 1):
			var h := tw.height_at(float(c) * schritt, float(r) * schritt)
			if h < TerrainWorld.SEA_Y + 1.0:
				zeile += " ."
			else:
				zeile += "%2d" % int(h / 100.0)
		print(zeile)
	quit()
	return true
