## WIE GLATT IST DIE TALSCHLUSSWAND WIRKLICH?
##
## Im Anflugbild fuellt sie 60 Prozent der Flaeche als fugenloser beiger Verlauf, und drei
## Abnahmen nacheinander haben sie als "gemalte Kulisse" gelesen. Bevor ich Relief
## auflege, muss die Frage beantwortet sein, die ein Bild nicht beantwortet: SCHWANKT die
## Hoehe dort ueberhaupt, und auf welcher Laenge?
##
## Gemessen wird quer zur Talachse auf mehreren Stationen. Ausgegeben werden je Zeile die
## Hoehe, die mittlere Steigung und — das ist die eigentliche Zahl — die mittlere
## KRUEMMUNG (zweite Differenz). Eine Ebene hat Kruemmung 0; jeder Fels hat sie nicht.
##
## Godot --headless --path . --script res://tools/_wandprofil.gd
extends SceneTree

const START := Vector2(-11000.0, -2500.0)
const RICHTUNG := Vector2(0.6139, -0.7893)
const SCHRITT := 8.0      # Abtastung quer, in Metern

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var quer := Vector2(RICHTUNG.y, -RICHTUNG.x)
	print(" laengs |  h(quer=0) | Spanne quer +-240 | mittl. Kruemmung je %.0f m" % SCHRITT)
	for i in 9:
		var l := 9330.0 + float(i) * 45.0
		var h: PackedFloat64Array = []
		for k in 61:
			var d := -240.0 + float(k) * SCHRITT
			var p: Vector2 = START + RICHTUNG * l + quer * d
			h.append(tw.height_at(p.x, p.y))
		var hmin := h[0]
		var hmax := h[0]
		var kr := 0.0
		for k in h.size():
			hmin = minf(hmin, h[k])
			hmax = maxf(hmax, h[k])
			if k > 0 and k < h.size() - 1:
				kr += absf(h[k - 1] - 2.0 * h[k] + h[k + 1])
		kr /= float(h.size() - 2)
		print("%7.0f | %10.0f | %6.0f .. %-6.0f  | %8.2f m" % [l, h[30], hmin, hmax, kr])
	# Und einmal laengs, den Hang hinauf: wie gleichmaessig steigt er?
	print("\n Anstieg auf der Achse, je 20 m Talstation:")
	var vor := 0.0
	for i in 16:
		var l := 9300.0 + float(i) * 20.0
		var p: Vector2 = START + RICHTUNG * l
		var hh := tw.height_at(p.x, p.y)
		print("%7.0f | h = %6.0f | Zuwachs %+6.0f" % [l, hh, hh - vor if i > 0 else 0.0])
		vor = hh
	quit()
	return true
