## WO LIEGT FELDFLUR? Tastet die Hauptinsel im 500-m-Raster ab (Feldstaerke wie _boden_farbe)
## und gibt die 2-km-Zellen mit dem groessten Feldanteil aus — Kamerapunkte fuer Bilder.
##   HOME=<test-home> Godot --headless --path . --script res://tools/_feld_suche.gd
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var zellen := {}
	var gesamt := 0
	var land := 0
	for i in range(-68, 69):
		for j in range(-68, 69):
			var x := float(i) * 500.0
			var z := float(j) * 500.0
			if tw.region_at(x, z) != TerrainWorld.Region.HAUPT:
				continue
			var h := tw.height_at(x, z)
			if h < TerrainWorld.SEA_Y + 1.0:
				continue
			land += 1
			var wald := smoothstep(-0.28, 0.30, tw._forest.get_noise_2d(x, z))
			var kk := tw.land_kammer(x, z)
			wald = clampf(wald * wald * tw.kammer_wald(kk), 0.0, 1.0)
			var fs := tw._feld_staerke(x, z, h, wald, kk)
			if fs > 0.3:
				gesamt += 1
			var key := Vector2i(floori(x / 2000.0), floori(z / 2000.0))
			zellen[key] = float(zellen.get(key, 0.0)) + fs
	print("Land-Proben %d, davon Feldflur > 0.3: %d (%.1f %%)" % [land, gesamt, 100.0 * gesamt / maxf(land, 1)])
	var liste: Array = []
	for key in zellen:
		liste.append([zellen[key], key])
	liste.sort_custom(func(a, b): return a[0] > b[0])
	for n in mini(16, liste.size()):
		var key: Vector2i = liste[n][1]
		print("Zelle Mitte (%6d, %6d)  Feldsumme %5.1f / 16" % [key.x * 2000 + 1000, key.y * 2000 + 1000, liste[n][0]])
	quit()
	return true
