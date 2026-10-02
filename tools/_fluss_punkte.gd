## Gibt den feinen Lauf eines Flusses alle ~"schritt" Meter aus (Lage, Spiegel, Breite,
## Richtung) — zum Setzen von Kamerapunkten. Godot --headless ... -- <Name> [schritt]
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var m: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(m)
	var a := OS.get_cmdline_user_args()
	var name := a[0] if a.size() > 0 else "Silberfluss"
	var schritt := float(a[1]) if a.size() > 1 else 500.0
	for rv: Dictionary in m.terrain.rivers:
		if String(rv.get("name", "")) != name:
			continue
		var pts: PackedVector3Array = rv["pts"]
		var br: PackedFloat32Array = rv["breite"]
		var l := 0.0
		var naechst := 0.0
		for i in range(1, pts.size() - 1):
			l += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
			if l < naechst:
				continue
			naechst = l + schritt
			var d := Vector2(pts[i + 1].x - pts[i - 1].x, pts[i + 1].z - pts[i - 1].z).normalized()
			print("%7.0f m  (%7.0f, %7.0f)  Spiegel %6.1f  Breite %5.1f  Richtung (%5.2f, %5.2f)"
				% [l, pts[i].x, pts[i].z, pts[i].y, br[i], d.x, d.y])
	quit()
	return true
