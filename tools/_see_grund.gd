## UMFELD DES BERGSEES: liegt er in einer Mulde oder auf einer Platte?
## Godot --headless --path . --script res://tools/_see_grund.gd
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var wsp: float = K["SEE_SPIEGEL"]
	var mitte: Vector2 = start + dir * float(K["SEE_LAENGS"])
	var quer := Vector2(dir.y, -dir.x)

	print("Talboden LAENGS (Abstand vom Talanfang -> Hoehe in der Achse):")
	var s := ""
	for i in range(20):
		var l := 2000.0 + float(i) * 400.0
		var p := start + dir * l
		s += "%.0f:%.0f  " % [l, tw.height_at(p.x, p.y)]
	print("  " + s)

	print("\nRadial um die Seemitte (0 Grad = talaufwaerts):")
	print("  Ufer = ERSTE Stelle auf oder ueber dem Spiegel (von der Mitte nach aussen),")
	print("  eben bis = erste Stelle darueber, die hoeher als Spiegel + 8 m liegt.")
	print("  DAS MUSS VON INNEN NACH AUSSEN GESUCHT WERDEN: nimmt man die LETZTE Stelle")
	print("  unter dem Spiegel, meldet der Strahl den Talboden 2 km weiter als 'Ufer' —")
	print("  der liegt naemlich tiefer als der See, gehoert aber nicht zu ihm.")
	var saum := 0.0
	var n := 0
	for gi in range(24):
		var g := float(gi) * 15.0
		var a := deg_to_rad(g)
		var rich := dir * cos(a) + quer * sin(a)
		var ufer := 0.0
		var eben := 0.0
		var hmax := -1.0e9
		for i in range(1, 401):
			var r := float(i) * 6.0
			var p := mitte + rich * r
			var hh: float = tw.height_at(p.x, p.y)
			if ufer <= 0.0:
				if hh >= wsp:
					ufer = r
				continue
			if eben <= 0.0 and hh > wsp + 8.0:
				eben = r
			if r < ufer + 400.0:
				hmax = maxf(hmax, hh)
		if eben <= 0.0:
			eben = ufer
		saum += eben - ufer
		n += 1
		print("  %3.0f Grad: Ufer %4.0f m, eben bis %4.0f m -> flacher Saum %4.0f m,"
			% [g, ufer, eben, eben - ufer]
			+ "  Rand steigt auf %+5.0f m ueber Spiegel" % (hmax - wsp))
	print("  MITTEL flacher Saum %.0f m rundum" % (saum / float(n)))

	print("\nBewuchs (_open_ground, 1 = voll) radial, Abstand 100..1400 m:")
	for gi in [0, 90, 180, 270]:
		var a := deg_to_rad(float(gi))
		var rich := dir * cos(a) + quer * sin(a)
		var z := "  %4d Grad: " % gi
		for i in range(14):
			var p := mitte + rich * (100.0 + float(i) * 100.0)
			z += " %.2f" % tw._open_ground(p.x, p.y)
		print(z)
	quit()
	return true
