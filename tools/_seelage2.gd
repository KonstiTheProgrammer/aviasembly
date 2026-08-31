## STEHEN SCHIFFE, INSELN UND KUESTENZIELE NOCH IM WASSER?
##
## Die Frage stellt sich nach JEDER Aenderung an der Kuestenlinie neu, und sie hat sich
## schon zweimal mit "nein" beantwortet: bei der letzten Vergroesserung lagen vier
## Schiffe und ein Wrack an Land, eines davon auf 94 m Hoehe. Ein Werkzeug, das das in
## zwanzig Sekunden sagt, ist billiger als das Bild, auf dem man es zufaellig sieht.
##
## Godot --headless --path . --script res://tools/_seelage2.gd
extends SceneTree

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
	var fehler := 0

	print("SCHWIMMENDES — muss unter dem Meeresspiegel liegen")
	print("Objekt              |     x |     z |  Grund | Urteil")
	print("--------------------+-------+-------+--------+--------")
	# DIE ECHTEN POSITIONEN, NICHT DIE KARTENETIKETTEN. Der erste Anlauf las _map_pois
	# und meldete das Wrack "AN LAND" — zu Recht, nur betraf das das SCHILD auf der Karte
	# und nicht das Schiff, das 7 km weiter draussen liegt. Ein Werkzeug, das das falsche
	# Objekt prueft, ist schlimmer als keins: es erzeugt Arbeit und Vertrauen zugleich.
	# Die Werte stammen aus Main._setup_world (Ozean-Leben).
	for e in [["Segler 1", Vector2(26373, -8791)], ["Segler 2", Vector2(21642, -17765)],
			["Segler 3", Vector2(-23552, 20005)], ["Segler 4", Vector2(7824, -28236)],
			["Wrack", Vector2(26983, -7477)]]:
		var v: Vector2 = e[1]
		var g: float = tw.height_at(v.x, v.y)
		var ok := g < meer - 3.0
		if not ok:
			fehler += 1
		print("%-19s | %5.0f | %5.0f | %6.1f | %s"
			% [e[0], v.x, v.y, g, "im Wasser" if ok else "AN LAND"])

	print("\nINSELN — Mittelpunkt muss ueber, Umgebung unter dem Spiegel liegen")
	print("Insel        |  r  |  Mitte | Rand 1,6r | Urteil")
	print("-------------+-----+--------+-----------+--------")
	for ms in tw.massifs:
		if String(ms.get("type", "berg")) != "insel":
			continue
		var p: Vector3 = ms["pos"]
		var r: float = float(ms["r"])
		var mitte: float = tw.height_at(p.x, p.z)
		# In acht Richtungen 1,6 Radien hinaus: dort muss Meer sein, sonst haengt die
		# Insel am Festland.
		var hoechster := -999.0
		for k in 8:
			var a := TAU * float(k) / 8.0
			hoechster = maxf(hoechster,
				tw.height_at(p.x + cos(a) * r * 1.6, p.z + sin(a) * r * 1.6))
		var frei := hoechster < meer
		if not frei or mitte <= meer:
			fehler += 1
		print("r=%-10.0f | %3.0f | %6.1f | %9.1f | %s"
			% [r, r, mitte, hoechster,
				"Insel" if frei and mitte > meer else "AM FESTLAND / ERTRUNKEN"])
	print("\n-> %d Beanstandungen" % fehler)
	quit()
	return true
