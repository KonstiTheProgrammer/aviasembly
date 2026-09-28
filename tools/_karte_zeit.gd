## WIE LANGE BRAUCHT DIE VOLLBILD-KARTE (Taste M)?
##
## Main startet die Karte beim Weltaufbau in einem eigenen Thread (Main._setup_world,
## zweistufig 512 -> 1024 px); bis die erste Stufe da ist, meldet M nur "Karte wird noch
## gezeichnet ...".
## Gemessen wird GENAU DIESER Lauf — mitten im Start, neben der Fernschuerze, also unter
## den Bedingungen, die der Spieler hat. Eine zweite Erzeugung aus diesem Skript heraus
## liefe parallel zu der von Main und verfaelschte beide Zeiten.
##
## Ausgabe: Zeit bis zur ersten (schnellen) und zur feinen Karte, die Stufenzeiten der
## letzten Erzeugung, eine Pruefsumme (gleiche Summe = gleiches Bild, z. B. nach einer
## reinen Beschleunigung) und das Bild selbst als user://karte_roh.png.
##
##   HOME=/tmp/avi_home Godot --headless --path . --script res://tools/_karte_zeit.gd
extends SceneTree
var f := 0
var m: Node
var t0 := 0
var erste := -1


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		t0 = Time.get_ticks_msec()
		m = load("res://scenes/Main.tscn").instantiate()
		get_root().add_child(m)
		return false
	if m == null:
		return false
	var wm = m.get("world_map")
	if wm != null and erste < 0:
		erste = Time.get_ticks_msec() - t0
		print("KARTE erste Stufe nach %.2f s (%d px), Stufen %s" % [erste / 1000.0,
			(wm.get("_tex") as ImageTexture).get_width(), str(WorldMap.stufen_ms)])
	if wm != null and m.get("_map_thread") == null:
		var ms := Time.get_ticks_msec() - t0
		var img: Image = (wm.get("_tex") as ImageTexture).get_image()
		img.save_png("user://karte_roh.png")
		var summe := 0
		var daten := img.get_data()
		for i in range(0, daten.size(), 7):
			summe = (summe * 31 + daten[i]) % 1000000007
		print("KARTE fertig nach %.2f s (%d px)   Pruefsumme %d   Stufen %s" % [ms / 1000.0,
			img.get_width(), summe, str(WorldMap.stufen_ms)])
		quit()
	if Time.get_ticks_msec() - t0 > 240000:
		print("KARTE nach 240 s nicht fertig")
		quit()
	return false
