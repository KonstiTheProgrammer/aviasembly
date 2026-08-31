## WO KREUZT DIE TALSCHLUSSWAND DIE KAVERNENROEHRE?
##
## Die Kaverne des unterirdischen Flugplatzes laeuft auf der BAHNACHSE in den Talschluss.
## Ihr Boden liegt auf 90 m, ihr Scheitel auf rund 170. Das Gelaende ist eine FLAECHE:
## solange sie UNTER dem Boden oder UEBER dem Scheitel liegt, stoert sie nicht — nur in
## dem Band, in dem sie die Roehre durchquert, steht Grasnarbe im Stollen. Dieses Band
## muss der Portalring (Liner) verdecken, und dafuer muss man wissen, wo es liegt.
##
## Godot --headless --path . --script res://tools/_kaverne_platz.gd
extends SceneTree

const START := Vector2(-11000.0, -2500.0)
const RICHTUNG := Vector2(0.6139, -0.7893)

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var quer := Vector2(RICHTUNG.y, -RICHTUNG.x)
	# Querabstaende auf die neue Hallenbreite gezogen: HB_W_HALLE ist 78, der Wandfuss
	# liegt also bei +-78, und 95 fragt, ob auch der Fels DAHINTER noch traegt.
	print(" laengs |  quer 0   +-60    +-78    +-95   | Band? (90 < h < 175)")
	for i in 24:
		var l := 9250.0 + float(i) * 50.0
		var zeile := "%7.0f |" % l
		var band := false
		for d in [0.0, 60.0, 78.0, 95.0]:
			var hs := ""
			for seite in ([1.0] if d == 0.0 else [-1.0, 1.0]):
				var p: Vector2 = START + RICHTUNG * l + quer * d * seite
				var h := tw.height_at(p.x, p.y)
				if h > 91.5 and h < 175.0:
					band = true
				hs += "%s%.0f" % ["/" if hs != "" else "", h]
			zeile += " %9s" % hs
		print(zeile, "   <- BAND" if band else "")
	quit()
	return true
