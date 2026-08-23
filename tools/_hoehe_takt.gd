## WAS KOSTET EINE HOEHENPROBE? Der Wert steht als Begruendung an mehreren Stellen im Code
## (Fernschuerze: "height_at kostet gemessen 11,15 us"), und jede Aenderung an height_at
## oder an dem, was es aufruft, kann ihn verschieben, ohne dass man es im Bild sieht.
##
## Gemessen wird auf DREI Feldern getrennt, weil die Kosten stark vom Ort abhaengen:
## im offenen Tiefland greifen fast alle Vorfilter, im Canyon laeuft der Flussschnitt mit,
## und am Vulkan kommt dessen ganze Formgebung dazu.
##
## Godot --headless --path . --script res://tools/_hoehe_takt.gd
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	print("Feld                   Proben     gesamt     je Probe")
	for feld in [["Tiefland offen", Vector2(1500, -2500)],
			["Canyon (Flussschnitt)", Vector2(-5200, 2700)],
			["Vulkan", Vector2(11800, -5600)],
			["Hochtal", Vector2(-6600, -8000)]]:
		var mp: Vector2 = feld[1]
		# Einmal warmlaufen, damit Rauschtabellen und Zweige geladen sind.
		for i in 500:
			tw.height_at(mp.x + float(i), mp.y)
		var n := 40000
		var t0 := Time.get_ticks_usec()
		var summe := 0.0
		for i in n:
			var x := mp.x + float(i % 200) * 8.0
			var z := mp.y + float(i / 200) * 8.0
			summe += tw.height_at(x, z)
		var dt := Time.get_ticks_usec() - t0
		print("%-22s %6d  %7.1f ms   %6.2f us   (Summe %.0f)"
			% [feld[0], n, dt / 1000.0, float(dt) / float(n), summe])
	quit()
	return true
