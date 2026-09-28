## UEBERSICHT DER GANZEN WELT als Kartenbild (dieselbe Erzeugung wie die Karte, Taste M),
## zum Draufschauen beim Bauen neuer Regionen.
##
##   HOME=/tmp/avi_home Godot --headless --path . --script res://tools/_welt_uebersicht.gd -- [px] [mitte_x mitte_z halbe_kante]
## Ohne Ausschnitt die ganze Welt (WorldMap.WORLD_R). Bild: user://welt_uebersicht.png
extends SceneTree
var f := 0
var m: Node

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
	if f == 6:
		var a := OS.get_cmdline_user_args()
		var px := 768 if a.size() < 1 else int(a[0])
		var mitte := Vector2.ZERO
		var halb := WorldMap.WORLD_R
		if a.size() >= 4:
			mitte = Vector2(float(a[1]), float(a[2]))
			halb = float(a[3])
		var t0 := Time.get_ticks_msec()
		var img := WorldMap.generate_image(m.terrain, px, halb, true, 4, [false], mitte, 0)
		img.save_png("user://welt_uebersicht.png")
		print("UEBERSICHT %d px, %.0f km, %.1f s" % [px, halb * 2.0 / 1000.0,
			(Time.get_ticks_msec() - t0) / 1000.0])
		quit()
	return false
