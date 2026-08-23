## WIE STARK SPRINGT DAS GELAENDE VON EINEM GITTERPUNKT ZUM NAECHSTEN?
##
## Im Bild (Shot tal_quer) ist das Hochgebirge ein Salz-und-Pfeffer-Teppich aus hellen und
## dunklen Dreiecken. Die naheliegende Erklaerung — der Schnee schalte je Facette an und aus —
## ist falsch: die dunklen Dreiecke sind SCHATTIERTE Flaechen, nicht schneefreier Fels. Dann
## kann es nur die Geometrie sein. Bei 8 m Maschenweite entsteht aus einem Hoehensprung von
## 8 m bereits eine 45-Grad-Facette; wechselt das Vorzeichen von Punkt zu Punkt, steht jede
## Facette anders im Licht und das Auge sieht Rauschen statt Berg.
##
## Gemessen wird der Betrag der Differenz zum oestlichen und noerdlichen Nachbarn auf dem
## ECHTEN Netzraster von 8 m, dazu der Anteil der Punkte ueber 45 Grad.
##
## Godot --headless --path . --script res://tools/_rauheit.gd
extends SceneTree

const SCHRITT := 8.0
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	print("Feld                    Mittel   p90     max     ueber 45 Grad   ueber 60 Grad")
	for feld in [["Hochgebirge Kamm", Vector2(-7600.0, -6200.0)],
			["Hochgebirge Flanke", Vector2(-6900.0, -7400.0)],
			["Vulkanflanke", Vector2(12500.0, -5600.0)],
			["Bergmassiv Kernland", Vector2(2400.0, 1500.0)],
			["Tiefland", Vector2(1500.0, -2500.0)]]:
		var mp: Vector2 = feld[1]
		var summe := 0.0
		var groesste := 0.0
		var alle := PackedFloat32Array()
		var steil := 0
		var sehr := 0
		var n := 0
		for j in 120:
			for i in 120:
				var x := mp.x + float(i) * SCHRITT
				var z := mp.y + float(j) * SCHRITT
				var h := tw.height_at(x, z)
				var d := maxf(absf(tw.height_at(x + SCHRITT, z) - h),
					absf(tw.height_at(x, z + SCHRITT) - h))
				summe += d
				groesste = maxf(groesste, d)
				alle.append(d)
				if d > SCHRITT:
					steil += 1
				if d > SCHRITT * 1.732:
					sehr += 1
				n += 1
		alle.sort()
		print("%-22s %6.2f  %6.2f  %6.2f      %5.1f %%        %5.1f %%"
			% [feld[0], summe / n, alle[int(n * 0.9)], groesste,
				100.0 * float(steil) / n, 100.0 * float(sehr) / n])
	quit()
	return true
