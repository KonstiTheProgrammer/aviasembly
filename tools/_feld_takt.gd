## Mikromessung der Feldflur-Bausteine (je Aufruf, us): Hash, Lage, Teilung, Staerke, Raster.
##   HOME=<test-home> Godot --headless --path . --script res://tools/_feld_takt.gd
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	main.set("_fern_stopp", true)
	var tw: TerrainWorld = main.terrain
	var n := 20000
	var pts := PackedVector2Array()
	for i in n:
		pts.append(Vector2(6000.0 + float(i % 200) * 8.0, 6000.0 + float(i / 200) * 8.0))
	var t0 := Time.get_ticks_usec()
	var s := 0.0
	for i in n:
		s += tw.feld_hash(i, 7, 3)
	print("feld_hash      %.2f us" % (float(Time.get_ticks_usec() - t0) / n))
	t0 = Time.get_ticks_usec()
	var lagen: Array[Vector4] = []
	for p in pts:
		lagen.append(tw._feld_lage(p.x, p.y))
	print("_feld_lage     %.2f us" % (float(Time.get_ticks_usec() - t0) / n))
	t0 = Time.get_ticks_usec()
	for l in lagen:
		tw._feld_teil(l.x, l.y)
	print("_feld_teil     %.2f us" % (float(Time.get_ticks_usec() - t0) / n))
	t0 = Time.get_ticks_usec()
	for l in lagen:
		tw._feld_teil_hash(l.x, l.y)
	print("_feld_teil_hash %.2f us" % (float(Time.get_ticks_usec() - t0) / n))
	# GLEICHHEIT Tabelle gegen Hash (Frucht, Schwelle, Streifen, Heckenfaktor), auch auf
	# zufaelligen Lagen im ganzen Rahmen
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var abw := 0
	var proben := 0
	for i in 60000:
		var u := rng.randf_range(150.0, 14000.0)
		var v := rng.randf_range(150.0, 14000.0)
		if i < lagen.size():
			u = lagen[i].x
			v = lagen[i].y
		var a := tw._feld_teil(u, v)
		var b := tw._feld_teil_hash(u, v)
		var ha := 1.0 - smoothstep(2.5, 6.0, a.z)
		var hb := 1.0 - smoothstep(2.5, 6.0, b.z)
		proben += 1
		if a.x != b.x or absf(a.y - b.y) > 1e-5 or a.w != b.w or absf(ha - hb) > 1e-4:
			abw += 1
			if abw < 5:
				print("  ABWEICHUNG bei (%.2f, %.2f): %s gegen %s" % [u, v, a, b])
	print("Tabelle gegen Hash: %d Abweichungen in %d Proben -> %s" % [abw, proben, "OK" if abw == 0 else "FALSCH"])
	t0 = Time.get_ticks_usec()
	for p in pts:
		var h := tw.height_at(p.x, p.y)
		s += h
	var t_h := float(Time.get_ticks_usec() - t0) / n
	t0 = Time.get_ticks_usec()
	for p in pts:
		var kk := tw.land_kammer(p.x, p.y)
		var wald := smoothstep(-0.28, 0.30, tw._forest.get_noise_2d(p.x, p.y))
		s += tw._feld_staerke(p.x, p.y, 20.0, wald * wald, kk)
	print("Staerke inkl. 2 Rauschen %.2f us" % (float(Time.get_ticks_usec() - t0) / n))
	t0 = Time.get_ticks_usec()
	for p in pts:
		s += tw._open_ground(p.x, p.y)
	print("_open_ground   %.2f us" % (float(Time.get_ticks_usec() - t0) / n))
	t0 = Time.get_ticks_usec()
	for p in pts:
		s += tw._region_n.get_noise_2d(p.x, p.y)
	print("1 Rauschen     %.2f us   (height_at %.2f us)" % [float(Time.get_ticks_usec() - t0) / n, t_h])
	print(s)
	quit()
	return true
