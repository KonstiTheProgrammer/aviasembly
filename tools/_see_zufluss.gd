## LIEGT DER ZUFLUSSBACH DES BERGSEES SICHTBAR IM GELAENDE — oder haengt sein Wasserband
## ueber dem Boden bzw. in einer Klamm?
##
## Die Frage, die _see_abfluss.gd nicht stellt: dort wird nur die Muendung ausgegeben. Ob
## der Bach auf seiner ganzen Laenge als BAND ZU SEHEN ist, entscheidet der Abstand zwischen
## Wasserhoehe und dem Gelaende NEBEN dem Bett. Liegt das Ufer viel hoeher, steckt der Bach
## in einer Klamm und ist von oben unsichtbar; liegt es tiefer, schwebt das Band.
##
## godot --headless --path . --script res://tools/_see_zufluss.gd
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
	var mitte: Vector2 = Vector2(K["TAL_START"]) + Vector2(K["TAL_RICHTUNG"]) * float(K["SEE_LAENGS"])
	var spiegel: float = K["SEE_SPIEGEL"]
	print("BERGSEE-ZUFLUSS — Spiegel %.1f m" % spiegel)
	for rv in tw.rivers:
		if int(rv.get("seebach", 0)) <= 0:
			continue
		var pts: PackedVector3Array = rv["pts"]
		var w: float = float(rv["w"])
		print("  i  Abstand   Wasser  Sohle   Ufer(+-%.0f m)  Einschnitt" % (w * 2.0))
		for i in pts.size():
			var p := pts[i]
			var d := Vector2(p.x - mitte.x, p.z - mitte.y).length()
			var sohle := tw.height_at(p.x, p.z)
			# Ufer quer zum Lauf, beide Seiten, im doppelten Bandabstand
			var j := maxi(i - 1, 0)
			var k := mini(i + 1, pts.size() - 1)
			var dir := Vector2(pts[k].x - pts[j].x, pts[k].z - pts[j].z).normalized()
			var qn := Vector2(-dir.y, dir.x) * w * 2.0
			var u1 := tw.height_at(p.x + qn.x, p.z + qn.y)
			var u2 := tw.height_at(p.x - qn.x, p.z - qn.y)
			print("  %2d %7.0f m %7.1f %6.1f   %6.1f / %6.1f   %+5.1f m"
				% [i, d, p.y, sohle, u1, u2, p.y - minf(u1, u2)])
	quit()
	return true
