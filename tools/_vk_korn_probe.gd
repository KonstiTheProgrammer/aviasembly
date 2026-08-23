extends SceneTree
## Kurze Gegenprobe: WIE STARK schwankt die 13-m-Kornlage ueberhaupt, und wie stark
## zwischen zwei Punkten, die 8 m auseinanderliegen? Zwei Aenderungsrunden haben an ihr
## gedreht, ohne dass sich am Bild etwas bewegte — bevor eine dritte folgt, wird gemessen,
## ob die Lage ueberhaupt Amplitude hat.
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	for paar in [["schutt", tw._vk_schutt_takt], ["grus", tw._vk_grus_takt],
			["rost", tw._vk_rost_takt]]:
		var takt: float = paar[1]
		var s := 0.0
		var s2 := 0.0
		var d := 0.0
		var n := 0
		for j in 200:
			for i in 200:
				var x := 11800.0 + float(i) * 8.0
				var z := -5600.0 + float(j) * 8.0
				var v: float = tw._patch.get_noise_2d(x * takt, z * takt)
				var v2: float = tw._patch.get_noise_2d((x + 8.0) * takt, z * takt)
				s += v
				s2 += v * v
				d += absf(v - v2)
				n += 1
		print("%-8s takt %.3f  Mittel %.4f  Streuung %.4f  Nachbarsprung(8 m) %.4f"
			% [paar[0], takt, s / n, sqrt(s2 / n - (s / n) * (s / n)), d / n])
	quit()
	return true
