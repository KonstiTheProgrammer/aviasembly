## LAENGSPROFIL EINES FLUSSES: je Stuetzpunkt Laufmeter, Lage, Wasserhoehe, Gefaelle,
## Halbbreite und das GEWACHSENE Gelaende (Fluesse aus). Zum Finden von Stromschnellen,
## Kaskaden und Durchbruechen.
##
##   HOME=<test-home> Godot --headless --path . --script res://tools/_fluss_profil.gd -- [name] [schritt]
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var a := OS.get_cmdline_user_args()
	var name := a[0] if a.size() > 0 else "Silberfluss"
	var schritt := int(a[1]) if a.size() > 1 else 1
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	for rv in tw.rivers:
		if String(rv.get("name", "")) != name:
			continue
		var pts: PackedVector3Array = rv["pts"]
		var br: PackedFloat32Array = rv["breite"]
		var alle: Array = tw.rivers
		tw.rivers = []
		var gel := PackedFloat32Array()
		for p in pts:
			gel.append(tw.height_at(p.x, p.z))
		tw.rivers = alle
		var l := 0.0
		print("   lauf      x       z   wasser  gefaelle%  breite  gelaende  einschnitt")
		for i in pts.size():
			if i > 0:
				l += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
			if i % schritt != 0:
				continue
			var g := 0.0
			if i + 1 < pts.size():
				g = (pts[i].y - pts[i + 1].y) / maxf(Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length(), 0.01) * 100.0
			print("%7.0f %7.0f %7.0f %8.1f %8.2f %7.1f %9.1f %9.1f" % [l, pts[i].x, pts[i].z, pts[i].y, g, br[i], gel[i], gel[i] - pts[i].y])
	quit()
	return true
