## WIE SIEHT DIE KUESTE AUS — SEKTOR FUER SEKTOR?
##
## Vor jedem Eingriff in den Umriss der Insel muss man wissen, was dort schon liegt. Zwei
## Fragen entscheiden ueber jede Platzierung:
##
##   RELIEF   Ein Fjord braucht Waende. Schneidet man ihn in flaches Vorland, ist er ein
##            Kanal. Gesucht ist die Sektorenspanne, in der das Land 3 bis 8 km hinter
##            der Kueste hoch ist.
##   BELEGUNG Flugplaetze, Staedte, Wahrzeichen und Schiffe stehen auf festen Koordinaten.
##            Eine Bucht, die einen davon flutet, ist kein Gewinn. Der Bericht nennt
##            deshalb zu jedem Sektor, was in ihm liegt.
##
## Godot --headless --path . --script res://tools/_kuestenlage.gd
extends SceneTree

const SEKTOREN := 36
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if not has_meta("main"):
		var m: Node = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		set_meta("main", m)
		return false
	if f < 8:
		return false
	var main: Node = get_meta("main")
	var tw = main.get("terrain")
	var meer: float = tw.SEA_Y

	# --- Was liegt wo? ------------------------------------------------------------------
	var poi: Array = []
	for af in main.get("airfields"):
		poi.append([String(af.get("name", "Platz")), Vector2(af["pos"].x, af["pos"].z)])
	poi.append(["NEONBUCHT", Vector2(2600, -3800)])
	for ms in tw.massifs:
		if String(ms.get("type", "berg")) == "insel":
			poi.append(["Insel r%d" % int(ms["r"]), Vector2(ms["pos"].x, ms["pos"].z)])

	print("Sekt |  Grad |  Kueste |  Land 3km |  Land 6km | max 8 km | was dort liegt")
	print("-----+-------+---------+-----------+-----------+----------+----------------")
	for s in SEKTOREN:
		var grad := 360.0 / float(SEKTOREN) * float(s)
		var a := deg_to_rad(grad)
		var ri := Vector2(cos(a), sin(a))
		# Kueste suchen: erste Stelle ab 18 km, an der die Hoehe unter den Spiegel faellt.
		var kueste := 34000.0
		var r := 18000.0
		while r < 34000.0:
			if tw.height_at(ri.x * r, ri.y * r) <= meer:
				kueste = r
				break
			r += 100.0
		var h3: float = tw.height_at(ri.x * (kueste - 3000.0), ri.y * (kueste - 3000.0))
		var h6: float = tw.height_at(ri.x * (kueste - 6000.0), ri.y * (kueste - 6000.0))
		var hmax := 0.0
		for k in 17:
			var rr := kueste - 8000.0 + float(k) * 500.0
			hmax = maxf(hmax, tw.height_at(ri.x * rr, ri.y * rr))
		# Welche POI liegen in diesem Sektor (+-5 Grad) und weiter aussen als 12 km?
		var wer := ""
		for p in poi:
			var v: Vector2 = p[1]
			if v.length() < 12000.0:
				continue
			var dg := rad_to_deg(atan2(v.y, v.x)) - grad
			while dg > 180.0:
				dg -= 360.0
			while dg < -180.0:
				dg += 360.0
			if absf(dg) < 6.0:
				wer += "%s(%.0fkm) " % [p[0], v.length() / 1000.0]
		print("%4d | %5.0f | %6.1fkm | %8.0fm | %8.0fm | %7.0fm | %s"
			% [s, grad, kueste / 1000.0, h3, h6, hmax, wer])
	quit()
	return true
