## WIE WEIT STOESST DIE FERNSCHUERZE DURCH DAS GELAENDE?
##
## Die Schuerze tastet das Hoehenfeld mit FERN_ZELLE_FEIN (32 m) ab und interpoliert dazwischen
## linear; die Chunks nehmen 8 m. Wo das grobe Raster ueber dem feinen liegt, ragt die
## Schuerze durch den Boden — sichtbar als heller, treppenfoermiger Streifen im Hang.
## Dagegen laufen zwei Konstanten: FERN_BIAS senkt die Schuerze ueberall ab, FERN_TIEF
## zusaetzlich im Nahfeld. Beide waren an einem 230-m-Gelaende eingemessen.
##
## Diese Datei misst den Fehler dort, wo es jetzt drauf ankommt: im Hochtal.
##
## Godot --headless --path . --script res://tools/_fern_fehler.gd
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
	var Z: float = K["FERN_ZELLE_FEIN"]

	# Bilineare Interpolation auf dem 64-m-Raster, genau wie die Schuerze sie baut.
	var grob := func(x: float, z: float) -> float:
		var gx := floorf(x / Z) * Z
		var gz := floorf(z / Z) * Z
		var tx := (x - gx) / Z
		var tz := (z - gz) / Z
		var h00 := tw.height_at(gx, gz)
		var h10 := tw.height_at(gx + Z, gz)
		var h01 := tw.height_at(gx, gz + Z)
		var h11 := tw.height_at(gx + Z, gz + Z)
		return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

	for geb in [["Hochtal (neu)", Vector2(-8000.0, -6500.0), 4000.0],
			["Altes Bergland", Vector2(2400.0, 1500.0), 1500.0],
			["Flachland", Vector2(0.0, 0.0), 1500.0]]:
		var mitte: Vector2 = geb[1]
		var r: float = geb[2]
		var schlimm := -9e9
		var wo := Vector2.ZERO
		var summe := 0.0
		var n := 0
		var ueber := 0
		for j in range(-60, 61):
			for i in range(-60, 61):
				var x := mitte.x + float(i) * r / 60.0
				var z := mitte.y + float(j) * r / 60.0
				var fein := tw.height_at(x, z)
				if fein < TerrainWorld.SEA_Y + 1.0:
					continue
				# Positiv = das grobe Raster liegt UEBER dem feinen -> Schuerze stoesst durch.
				var d: float = float(grob.call(x, z)) - fein
				summe += maxf(d, 0.0)
				n += 1
				if d > 14.0:
					ueber += 1
				if d > schlimm:
					schlimm = d
					wo = Vector2(x, z)
		print("%-16s  schlimmster Durchstoss %6.1f m bei (%.0f, %.0f)   Mittel %.2f m   ueber FERN_BIAS=14: %.1f %%"
			% [geb[0], schlimm, wo.x, wo.y, summe / maxf(n, 1), 100.0 * float(ueber) / maxf(n, 1)])
	quit()
	return true
