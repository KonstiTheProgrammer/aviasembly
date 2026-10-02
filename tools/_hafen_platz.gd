## HOEHENRASTER eines Ausschnitts als Zeichenbild — zum Aussuchen von Bauplaetzen an der
## Kueste (Hafenstadt). Zeichen: '~' tiefes Wasser, '-' flaches Wasser (bis 4 m), '.' Land
## bis 6 m ueber dem Meer, ':' bis 20 m, '+' bis 50 m, '#' darueber, 'F' Flussnaehe.
##   HOME=<test-home> Godot --headless --path . --script res://tools/_hafen_platz.gd -- x0 z0 x1 z1 schritt
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
		var x0 := float(a[0])
		var z0 := float(a[1])
		var x1 := float(a[2])
		var z1 := float(a[3])
		var s := float(a[4])
		var tw: TerrainWorld = m.terrain
		var kopf := "        "
		var x := x0
		while x <= x1:
			kopf += "%d" % (int(x / 1000.0) % 10) if is_equal_approx(fmod(x, 1000.0), 0.0) else " "
			x += s
		print(kopf)
		var z := z0
		while z <= z1:
			var zeile := "%7d " % int(z)
			x = x0
			while x <= x1:
				var h := tw.height_at(x, z)
				var t := h - TerrainWorld.SEA_Y
				var c := "#"
				if t < -4.0:
					c = "~"
				elif t < 0.0:
					c = "-"
				elif t < 6.0:
					c = "."
				elif t < 20.0:
					c = ":"
				elif t < 50.0:
					c = "+"
				var fl: Vector4 = tw._fluss_naechst(x, z)
				if fl.x < absf(fl.z) * 1.5 and t >= 0.0:
					c = "F"
				zeile += c
				x += s
			print(zeile)
			z += s
		quit()
	return false
