## KRITIK-MESSUNG: Wie weit reicht die Schutthalde und wie hoch steigt sie am Hang?
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 4:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	if f < 8:
		return false
	var tw = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var p: Vector2 = start + dir * float(K["TOR_LAENGS"])
	var s_w: float = float(K["TOR_SPANN"])
	var yaw := atan2(dir.x, dir.y)
	var quer := Vector2(dir.y, -dir.x)
	var fuss: float = tw.height_at(p.x, p.y)
	var hz: Dictionary = load("res://scripts/Landmarks.gd").tor_halde_zone(p.x, p.y, yaw, s_w, int(K["TOR_SEED"]))
	var roh: Callable = hz["roh"]
	var minx := 1e9; var maxx := -1e9; var minz := 1e9; var maxz := -1e9
	var hmax := -1e9; var hmax_at := Vector2.ZERO
	var flaeche := 0.0
	var schritt := 5.0
	var reich := float(hz["reich"])
	var lx := -reich
	while lx <= reich:
		var lz := -reich
		while lz <= reich:
			if float(roh.call(lx, lz)) > 0.02:
				minx = minf(minx, lx); maxx = maxf(maxx, lx)
				minz = minf(minz, lz); maxz = maxf(maxz, lz)
				flaeche += schritt * schritt
				var w: Vector2 = p + quer * lx + dir * lz
				var hh: float = float(tw.height_at(w.x, w.y)) - fuss
				if hh > hmax:
					hmax = hh; hmax_at = Vector2(lx, lz)
			lz += schritt
		lx += schritt
	print("Spannweite Tor s_w = %.0f m, Fusslinie %.0f m" % [s_w, fuss])
	print("Halde quer  (lokal x): %.0f .. %.0f m  -> Breite %.0f m = %.2f Spannweiten" % [minx, maxx, maxx - minx, (maxx - minx) / s_w])
	print("Halde laengs (lokal z): %.0f .. %.0f m  -> Tiefe  %.0f m = %.2f Spannweiten" % [minz, maxz, maxz - minz, (maxz - minz) / s_w])
	print("Grundflaeche der Halde: %.2f km2" % (flaeche / 1e6))
	print("hoechster Punkt der Halde ueber der Fusslinie: %.0f m  (bei x=%.0f z=%.0f)" % [hmax, hmax_at.x, hmax_at.y])
	quit()
	return true
