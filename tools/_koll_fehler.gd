## WIE FALSCH WIRD DER BODEN, WENN DAS KOLLISIONSRASTER GROEBER WIRD?
##
## Der BVH-Aufbau der Kollisionsform ist der letzte grosse Posten im Nachladeruck, und er
## haengt an der Dreieckszahl. Bevor das Raster ausgeduennt wird, muss der Preis dafuer auf
## dem Tisch liegen: um wie viele METER weicht die Kollisionsflaeche dann vom sichtbaren
## Gelaende ab, und WO.
##
## Verglichen wird gegen height_at() — dieselbe Quelle, aus der auch das Sichtnetz seine
## Ecken zieht. Die Kollisionsflaeche wird so nachgebaut, wie sie im Spiel entsteht:
## lineare Interpolation ueber das grobe Dreieck (Diagonale v00-v11 wie beim Netz).
##
## Positiver Fehler = Kollision liegt UEBER dem sichtbaren Boden (Flugzeug schwebt),
## negativer = darunter (Flugzeug taucht ein). Beides zaehlt, deshalb auch getrennt.
##
## Godot --headless --path . --script res://tools/_koll_fehler.gd
extends SceneTree

const CELLS := TerrainWorld.CELLS
const CHUNK := TerrainWorld.CHUNK
const SCHRITTE := [1, 2, 3, 4]
# Ueber die ganze Karte streuen, nicht nur um den Spawn: die Ausduennung tut genau dort
# weh, wo das Gelaende krumm ist, also im Gebirge.
const GEBIETE := [
	{"name": "Flugplatz", "p": Vector2(0, 0)},
	{"name": "Huegelland", "p": Vector2(2400, -1800)},
	{"name": "Gebirge", "p": Vector2(7600, 5200)},
	{"name": "Kueste", "p": Vector2(-4200, 3100)},
	{"name": "Hochland", "p": Vector2(-9000, -7400)},
]

var _tw: TerrainWorld
var _start := false


func _process(_d: float) -> bool:
	if not _start:
		_start = true
		_tw = TerrainWorld.new()
		root.add_child(_tw)
		_tw.setup(1337, [{"pos": Vector3.ZERO, "r_flat": 240.0, "r_blend": 620.0}], [], [], [])
		return false
	var step := CHUNK / float(CELLS)
	print("Rasterweite des Sichtnetzes: %.0f m,  %d x %d Zellen je Chunk" % [step, CELLS, CELLS])
	for s: int in SCHRITTE:
		var kc: int = CELLS / s
		print("\n=== KOLL_SCHRITT %d  ->  %d x %d Zellen a %.0f m  =  %d Dreiecke (statt %d) ==="
			% [s, kc, kc, step * s, kc * kc * 2, CELLS * CELLS * 2])
		var g_max := 0.0
		var g_sum := 0.0
		var g_n := 0
		for geb in GEBIETE:
			var mp: Vector2 = geb["p"]
			var ox := mp.x
			var oz := mp.y
			var maxf_ := 0.0      # groesste Abweichung nach oben
			var minf := 0.0       # groesste nach unten
			var sum := 0.0
			var n := 0
			# Alle FEINEN Rasterpunkte des Chunks gegen die grobe Flaeche halten.
			for j in CELLS + 1:
				for i in CELLS + 1:
					var x := ox + float(i) * step
					var z := oz + float(j) * step
					var wahr := _tw.height_at(x, z)
					# Welches grobe Dreieck deckt den Punkt?
					var ci := mini(i / s, kc - 1)
					var cj := mini(j / s, kc - 1)
					var bx := ox + float(ci * s) * step
					var bz := oz + float(cj * s) * step
					var ks := step * float(s)
					var h00 := _tw.height_at(bx, bz)
					var h10 := _tw.height_at(bx + ks, bz)
					var h01 := _tw.height_at(bx, bz + ks)
					var h11 := _tw.height_at(bx + ks, bz + ks)
					var u := (x - bx) / ks
					var v := (z - bz) / ks
					# Dieselbe Triangulierung wie im Netz: v00-v10-v11 und v00-v11-v01.
					var grob := (h00 + u * (h10 - h00) + v * (h11 - h10)) if u >= v \
						else (h00 + v * (h01 - h00) + u * (h11 - h01))
					var f := grob - wahr
					maxf_ = maxf(maxf_, f)
					minf = minf(minf, f)
					sum += absf(f)
					n += 1
			var mittel := sum / maxf(n, 1)
			g_max = maxf(g_max, maxf(maxf_, -minf))
			g_sum += sum
			g_n += n
			print("  %-11s  Mittel %5.2f m   schwebend bis %5.2f m   eintauchend bis %5.2f m"
				% [geb["name"], mittel, maxf_, -minf])
		print("  ---> ueber alle Gebiete: Mittel %.2f m, schlimmste Abweichung %.2f m"
			% [g_sum / maxf(g_n, 1), g_max])
	_tw.queue_free()
	quit()
	return true
