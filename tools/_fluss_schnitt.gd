## QUERSCHNITT DURCH EINEN FLUSSLAUF. Im Bild lief neben dem Wasserband ein fast
## senkrechter schwarzer Schlitz mit — sichtbar aus dem Spawn-Blick, also dort, wo jeder
## Spieler zuerst hinschaut. Aus der Luft ist nicht zu entscheiden, ob das Gelaende dort
## eine Kerbe hat oder ob nur das Wasser sie nicht ueberdeckt. Dieser Schnitt entscheidet es:
## er stellt die Gelaendehoehe quer zum Lauf neben die Wasserhoehe des Flusses.
##
## Godot --headless --path . --script res://tools/_fluss_schnitt.gd
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	# Der Tieflandfluss ist der zweite; sein Lauf steht in tw.rivers.
	for ri in tw.rivers.size():
		var rv: Dictionary = tw.rivers[ri]
		var pts: PackedVector3Array = rv["pts"]
		if pts.size() < 4:
			continue
		var i := pts.size() / 2
		var a := pts[i]
		var b := pts[i + 1]
		var dir := Vector2(b.x - a.x, b.z - a.z).normalized()
		var quer := Vector2(-dir.y, dir.x)
		print("--- Fluss %d, Stuetzpunkt %d bei (%.0f, %.0f), Wasser auf %.2f m, w=%.0f valley=%.0f"
			% [ri, i, a.x, a.z, a.y, float(rv["w"]), float(rv["valley"])])
		print("   quer[m]   Gelaende   ueber Wasser")
		var s := ""
		for k in range(-9, 10):
			var d := float(k) * 10.0
			var h := tw.height_at(a.x + quer.x * d, a.z + quer.y * d)
			s = "  <-- unter Wasser, aber ausserhalb des Bandes" if (h < a.y and absf(d) > float(rv["w"]) * 0.5) else ""
			print("   %6.0f    %8.2f   %8.2f%s" % [d, h, h - a.y, s])
	quit()
	return true
