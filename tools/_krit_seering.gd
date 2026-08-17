## LIEGT DER SEE IM TALBODEN — oder in einem gemalten Halsband?
##
## Das Referenzbild zeigt einen Talboden, der von Wasserlinie bis Wandfuss gruen ist; der
## See ist NICHT die Quelle des Gruens. Hier wird gemessen, ob das bei uns auch so ist:
## von der Seemitte in 24 Richtungen nach aussen laufen, die Uferlinie ueber SEE_SPIEGEL
## suchen, danach je Probe die ECHTE Gelaendefarbe aus TerrainWorld._face_color holen
## (nicht die Formel nachbauen — sonst misst man etwas anderes, als das Netz faerbt) und
## zaehlen, wie weit hinter dem Ufer das Gruen reicht.
##
## WARUM DIE HOEHE MITGEDRUCKT WIRD: die entscheidende Frage ist nicht "wie breit ist das
## Gruen", sondern ob Gelaende, das TIEFER als der Seespiegel liegt, trotzdem Felsfarbe
## bekommt. Genau das war der Befund: Richtung 135 Grad, 700 m hinter dem Ufer, Gelaende
## 71 m (7 m UNTER dem Spiegel von 78 m), Farbe 0.39/0.35/0.31 — Fels.
##
## godot --headless --path . --script res://tools/_krit_seering.gd
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var mitte: Vector2 = start + dir * float(K["SEE_LAENGS"])
	var spiegel: float = K["SEE_SPIEGEL"]

	print("Seemitte (%.0f / %.0f), Spiegel %.0f m" % [mitte.x, mitte.y, spiegel])
	print("Richtung | Ufer bei | Gruen ab Ufer | Hoehe und Farbe 300 / 700 / 1100 m dahinter")
	var breiten: Array[float] = []
	for k in 24:
		var a := TAU * float(k) / 24.0
		var d := Vector2(cos(a), sin(a))
		var ufer := -1.0
		var r := 0.0
		while r < 1200.0:
			r += 8.0
			if tw.height_at(mitte.x + d.x * r, mitte.y + d.y * r) > spiegel:
				ufer = r
				break
		if ufer < 0.0:
			continue
		# Ab Ufer nach aussen: erste Stelle, ab der 5 Proben in Folge nicht gruen sind.
		# Fuenf statt einer, damit ein einzelner Felskopf im Wald das Ergebnis nicht kippt.
		var gruen_bis := -1.0
		var nicht := 0
		var s := 0.0
		var farben := {}
		while s < 2000.0:
			s += 20.0
			var c := _farbe(tw, mitte + d * (ufer + s))
			if c.g > c.r + 0.03 and c.g > c.b:
				nicht = 0
			else:
				nicht += 1
				if nicht == 5 and gruen_bis < 0.0:
					gruen_bis = s - 80.0
			for m in [300.0, 700.0, 1100.0]:
				if absf(s - m) < 10.0:
					farben[m] = c
		if gruen_bis < 0.0:
			gruen_bis = 2000.0
		breiten.append(gruen_bis)
		var txt := ""
		for m in [300.0, 700.0, 1100.0]:
			var c: Color = farben.get(m, Color.BLACK)
			var p2: Vector2 = mitte + d * (ufer + float(m))
			txt += " %3.0fm %.2f/%.2f/%.2f |" % [tw.height_at(p2.x, p2.y), c.r, c.g, c.b]
		print("%7.0f  | %6.0f m | %8.0f m    |%s" % [rad_to_deg(a), ufer, gruen_bis, txt])
	var su := 0.0
	for b in breiten:
		su += b
	breiten.sort()
	print("\nGruenbreite hinter dem Ufer: Mittel %.0f m, kleinste %.0f m, groesste %.0f m"
		% [su / float(breiten.size()), breiten[0], breiten[-1]])
	quit()
	return true


## Gelaendefarbe an einer Stelle. Die Normale kommt aus Differenzen ueber 8 m — das ist die
## Netzweite, also dieselbe Steilheit, die _face_color beim Bauen sieht.
func _farbe(tw: TerrainWorld, p: Vector2) -> Color:
	var e := 8.0
	var hx := tw.height_at(p.x + e, p.y) - tw.height_at(p.x - e, p.y)
	var hz := tw.height_at(p.x, p.y + e) - tw.height_at(p.x, p.y - e)
	var n := Vector3(-hx, 2.0 * e, -hz).normalized()
	return tw._face_color(Vector3(p.x, tw.height_at(p.x, p.y), p.y), absf(n.y))
