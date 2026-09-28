## BELEG: DIE HAUPTINSEL BLEIBT BITGENAU. Rastert ±34 km (die ganze Hauptinsel samt
## Kueste, Kap, Hakenzunge und Inselkette) ab und bildet Pruefsummen ueber Hoehe, Farbe,
## Walddichte und Biom. Vor und nach einem Eingriff an den neuen Landmassen laufen lassen:
## alle vier Summen muessen gleich bleiben.
##
##   HOME=/tmp/avi_home Godot --headless --path . --script res://tools/_haupt_pruefsumme.gd
extends SceneTree
var f := 0
var m: Node

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
	if f == 6:
		var t: TerrainWorld = m.terrain
		var n := 300
		var halb := 34000.0
		var sh := 0
		var sc := 0
		var sw := 0
		var sb := 0
		for j in n:
			for i in n:
				var x := -halb + 2.0 * halb * float(i) / float(n - 1)
				var z := -halb + 2.0 * halb * float(j) / float(n - 1)
				var h := t.height_at(x, z)
				var c := t._face_color(Vector3(x, h, z), 0.93, 8.0, Vector3(0.2, 0.93, 0.3).normalized())
				var w := t.wald_anteil(x, z, h, 0.93)
				sh = (sh * 31 + int(h * 1000.0)) % 1000000007
				sc = (sc * 31 + int(c.r * 10000.0) + int(c.g * 1000.0) * 7 + int(c.b * 100.0)) % 1000000007
				sw = (sw * 31 + int(w * 100000.0)) % 1000000007
				sb = (sb * 31 + t.biome_at(x, z)) % 1000000007
		print("HAUPTINSEL hoehe %d  farbe %d  wald %d  biom %d" % [sh, sc, sw, sb])
		quit()
	return false
