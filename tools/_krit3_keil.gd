## KRITIKPROBE: verjuengt sich das Tal WIRKLICH monoton zur Tiefe?
## Misst die Gesamtbreite (beide Seiten) je Hoehenlinie ueber die ganze Tallaenge und
## meldet jede Stelle, an der es weiter hinten BREITER wird als weiter vorn.
## Godot --headless --path . --script res://tools/_krit3_keil.gd
extends SceneTree
var f := 0
const RASTER := 20.0
const WEIT := 3400.0
const SCHRITT := 400.0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var quer := Vector2(-dir.y, dir.x)

	for stufe: float in [200.0, 400.0, 600.0, 800.0]:
		var b: Array = []
		var lgs: Array = []
		var anschlag := 0
		print("\n=== HOEHENLINIE %d m: Gesamtbreite ===" % int(stufe))
		for i in range(0, 25):
			var lg := float(i) * SCHRITT
			var p := start + dir * lg
			var l := _kontur(tw, p, quer, 1.0, stufe)
			var r := _kontur(tw, p, quer, -1.0, stufe)
			if l >= WEIT - 1.0 or r >= WEIT - 1.0:
				anschlag += 1
			var w := l + r
			b.append(w)
			lgs.append(lg)
			print("%6.0f m : %5.0f m  (l %4.0f / r %4.0f) %s" % [lg, w, l, r,
				"ANSCHLAG" if (l >= WEIT - 1.0 or r >= WEIT - 1.0) else ""])
		print("  Anschlaege: %d von %d" % [anschlag, b.size()])
		# Monotonie: jede Stelle, an der spaeter breiter als frueher
		var verstoss := 0
		var max_verstoss := 0.0
		for i in b.size():
			for j in range(i + 1, b.size()):
				if float(b[j]) > float(b[i]) + 1.0:
					verstoss += 1
					max_verstoss = maxf(max_verstoss, float(b[j]) - float(b[i]))
		print("  Monotonie-Verstoesse: %d Paare, groesster %0.0f m" % [verstoss, max_verstoss])
		var vorn: float = (float(b[1]) + float(b[2]) + float(b[3])) / 3.0
		var hint: float = (float(b[20]) + float(b[21]) + float(b[22])) / 3.0
		print("  vorn (400..1200) %0.0f m / hinten (8000..8800) %0.0f m  =  %0.2f : 1"
			% [vorn, hint, vorn / maxf(hint, 1.0)])
	quit()
	return true

func _kontur(tw: TerrainWorld, p: Vector2, q: Vector2, s: float, stufe: float) -> float:
	var d := 0.0
	while d < WEIT:
		d += RASTER
		if tw.height_at(p.x + q.x * s * d, p.y + q.y * s * d) >= stufe:
			return d
	return WEIT
