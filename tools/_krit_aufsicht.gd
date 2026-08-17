## KRITIKER: AUFSICHT DES HOCHTALS in Talkoordinaten (laengs waagerecht, quer senkrecht).
## Orthogonal abgetastet, damit keine Perspektive eine Verjuengung vortaeuscht.
## Godot --headless --path . --script res://tools/_krit_aufsicht.gd -- <ausgabe.png>
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var args := OS.get_cmdline_user_args()
	var ziel := "user://krit_aufsicht.png" if args.is_empty() else args[0]
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var quer := Vector2(-dir.y, dir.x)
	var W := 760            # laengs 0 .. 11400 m in 15-m-Schritten
	var H := 480            # quer -3600 .. +3600 m in 15-m-Schritten
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for ix in W:
		var lg := float(ix) * 15.0
		for iy in H:
			var qd := (float(iy) - float(H) * 0.5) * 15.0
			var p := start + dir * lg + quer * qd
			var h := tw.height_at(p.x, p.y)
			var c: Color
			# Harte Stufen statt Verlauf: nur so sieht man die Breite einer Stufe.
			if h < 0.0:
				c = Color(0.1, 0.25, 0.5)
			elif h < 200.0:
				c = Color(0.25, 0.6, 0.25)        # Talboden
			elif h < 400.0:
				c = Color(0.55, 0.5, 0.3)
			elif h < 700.0:
				c = Color(0.5, 0.45, 0.42)
			elif h < 1000.0:
				c = Color(0.75, 0.75, 0.75)
			else:
				c = Color(1.0, 1.0, 1.0)
			img.set_pixel(ix, iy, c)
	# Achse und 1000-m-Marken als duenne Linien.
	for ix in W:
		if int(float(ix) * 15.0) % 1000 < 15:
			for iy in range(0, H, 8):
				img.set_pixel(ix, iy, Color(1, 0, 0))
	img.save_png(ziel)
	print("Aufsicht -> %s  (%d x %d, 15 m je Pixel)" % [ziel, W, H])
	quit()
	return true
