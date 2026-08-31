## Liegen die geplanten Inselpositionen im offenen Wasser?
##
## Die fuenf "insel"-Massive standen bei 11,5 bis 16 km und waren damit vor dem
## Vergroessern Inseln vor der Kueste. Jetzt sind es Huegel im Landesinneren. Dieses
## Werkzeug prueft neue Positionen: das Massiv hebt das Gelaende um "peak" an, es muss
## also RINGSUM tief genug sein, sonst waechst die Insel mit dem Festland zusammen.
extends SceneTree
var f := 0
const KAND := [
	Vector2(27244, -6468), Vector2(21197, -19498), Vector2(-19559, 22096),
	Vector2(-24055, 14914), Vector2(6692, -27799),
	Vector2(28600, -10600), Vector2(29400, -3200), Vector2(25200, -14900),
	Vector2(30100, -7600),
]
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw = main.terrain
	print("Position            | Mitte | tiefster Punkt im 1600-m-Ring | Urteil")
	for k in KAND:
		var mitte: float = tw.height_at(k.x, k.y)
		var hoch := -1.0e9
		for i in 12:
			var a := TAU * float(i) / 12.0
			hoch = maxf(hoch, tw.height_at(k.x + cos(a) * 800.0, k.y + sin(a) * 800.0))
		var ok := mitte < TerrainWorld.SEA_Y - 4.0 and hoch < TerrainWorld.SEA_Y - 2.0
		print("(%6.0f, %6.0f) | %5.1f | hoechster Ringwert %6.1f | %s"
			% [k.x, k.y, mitte, hoch, "frei" if ok else "ZU NAH AM LAND"])
	quit()
	return true
