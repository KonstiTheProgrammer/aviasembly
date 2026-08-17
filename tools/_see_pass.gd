## WO KANN DER BERGSEE UEBERHAUPT ABFLIESSEN?
##
## Dieses Werkzeug legt TerrainWorld.SEE_ABFLUSS_GRAD fest. Wer am Hochtal etwas aendert
## (Ketten, Keil, Massive), laesst es noch einmal laufen: die Richtung, in der der See
## ueberlaeuft, ist keine Geschmacksfrage, sondern eine Eigenschaft des Gelaendes.
##
## Der See liegt in einer geschlossenen Wanne: das gewachsene Gelaende steht rundum
## ueber seinem Spiegel. Jeder Abfluss ist also ein EINSCHNITT, und die einzige Frage
## ist, wo er am wenigsten kostet. "Am wenigsten" heisst hier: die niedrigste
## FLASCHENHALSHOEHE — der hoechste Punkt eines Weges vom Ufer bis hinunter ins Tal.
##
## Dijkstra auf dem Raster, aber nicht mit Summe, sondern mit max(): die Kosten eines
## Weges sind die hoechste Zelle darauf. Das liefert genau den Pass, den auch Wasser
## suchen wuerde, und nebenbei den Weg dorthin — also die Stuetzpunkte fuer die Spline.
##
## Gelaende OHNE See und OHNE Fluesse (lakes/rivers leer): gesucht ist der GEWACHSENE
## Pass, nicht der, den der eigene Carve schon gegraben hat.
##
## Godot --headless --path . --script res://tools/_see_pass.gd -- [schritt=20] [ziel=30]
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var schritt := 20.0
	var ziel := 30.0        # Hoehe, ab der man "im Tal unten" ist
	var weite := 2600.0
	# BODEN: Zellen darunter sind gesperrt, solange man noch in Seenaehe ist. Der Grund
	# steht im Kopfkommentar von SEE_ABFLUSS_GRAD: ein Bachbett darf nie ueber dem Boden
	# liegen, eine Mulde unterwegs zieht es also nach unten und der naechste Riegel muss
	# umso tiefer angeschnitten werden. Mit boden=0 sucht das Werkzeug den reinen
	# Flaschenhals, mit boden nahe dem Spiegel den Weg mit dem KLEINSTEN EINSCHNITT.
	var boden := 0.0
	# START: nur dieser Uferabschnitt darf Ausgangspunkt sein (Grad in Seekoordinaten,
	# 999 = das ganze Ufer). Sobald die Scharte steht, ist die Frage nicht mehr "wo
	# ueberhaupt", sondern "wie weiter von DORT".
	var start_grad := 999.0
	var start_weite := 12.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("schritt="):
			schritt = float(a.substr(8))
		elif a.begins_with("ziel="):
			ziel = float(a.substr(5))
		elif a.begins_with("boden="):
			boden = float(a.substr(6))
		elif a.begins_with("start="):
			start_grad = float(a.substr(6))

	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var ach: Vector2 = Vector2(K["TAL_RICHTUNG"])
	var quer := Vector2(ach.y, -ach.x)
	var mitte: Vector2 = Vector2(K["TAL_START"]) + ach * float(K["SEE_LAENGS"])
	var spiegel: float = K["SEE_SPIEGEL"]
	var see: Dictionary = {}
	for lk in tw.lakes:
		if lk.has("_rad"):
			see = lk

	var n := int(weite / schritt)
	var w := 2 * n + 1
	var hoehe := PackedFloat32Array()
	hoehe.resize(w * w)
	var ufer := PackedByteArray()
	ufer.resize(w * w)
	var sperre := PackedByteArray()
	sperre.resize(w * w)
	var kante := PackedByteArray()      # "unten angekommen" trotz boden-Sperre
	kante.resize(w * w)
	var lks: Array = tw.lakes
	tw.lakes = []
	tw.rivers = []
	for j in w:
		for i in w:
			var p := mitte + Vector2(float(i - n), float(j - n)) * schritt
			hoehe[j * w + i] = tw.height_at(p.x, p.y)
			var dd := p - mitte
			var lu := dd.dot(ach)
			var lv := dd.dot(quer)
			var rr: float = tw._see_umriss(see, atan2(lv, lu)).x
			# Startmenge: der Ring dicht ausserhalb der Uferlinie.
			var r := dd.length()
			if r >= rr and r < rr + schritt * 1.5 \
					and (start_grad > 900.0
					or absf(rad_to_deg(wrapf(atan2(lv, lu) - deg_to_rad(start_grad),
						-PI, PI))) < start_weite):
				ufer[j * w + i] = 1
			if hoehe[j * w + i] < boden:
				if r > 1000.0:
					kante[j * w + i] = 1     # der Absatz ins Tal: hier ist der Bach frei
				else:
					sperre[j * w + i] = 1
	tw.lakes = lks

	# --- Dijkstra mit max() statt + ----------------------------------------------------
	var kosten := PackedFloat32Array()
	kosten.resize(w * w)
	var vor := PackedInt32Array()
	vor.resize(w * w)
	for k in w * w:
		kosten[k] = 1e9
		vor[k] = -1
	# Einfache Bucket-Warteschlange: Hoehen sind hier 0..1300 m, ein Eimer je Meter reicht.
	var eimer: Array = []
	eimer.resize(1400)
	for b in 1400:
		eimer[b] = PackedInt32Array()
	for k in w * w:
		if ufer[k] == 1 and sperre[k] == 0:
			kosten[k] = hoehe[k]
			eimer[clampi(int(hoehe[k]), 0, 1399)].append(k)
	var best := -1
	for b in 1400:
		var liste: PackedInt32Array = eimer[b]
		var z := 0
		while z < liste.size():
			var k: int = liste[z]
			z += 1
			if kosten[k] < float(b) - 1.0 or kosten[k] > float(b) + 1.0:
				continue
			if hoehe[k] <= ziel or kante[k] == 1:
				best = k
				break
			var i := k % w
			var j := k / w
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var i2 := i + d.x
				var j2 := j + d.y
				if i2 < 0 or i2 >= w or j2 < 0 or j2 >= w:
					continue
				var k2 := j2 * w + i2
				if sperre[k2] == 1:
					continue
				var c := maxf(kosten[k], hoehe[k2])
				if c < kosten[k2] - 0.001:
					kosten[k2] = c
					vor[k2] = k
					eimer[clampi(int(c), 0, 1399)].append(k2)
			liste = eimer[b]
		if best >= 0:
			break

	if best < 0:
		print("KEIN Weg unter %.0f m gefunden." % ziel)
		quit(); return true
	print("SEE-ABFLUSS: niedrigster Uebergang vom Ufer bis unter %.0f m" % ziel)
	print("  FLASCHENHALS %.1f m  = %+.1f m ueber dem Spiegel (%.1f m)"
		% [kosten[best], kosten[best] - spiegel, spiegel])
	print("  -> so tief muss der Bach den Beckenrand mindestens anschneiden.\n")
	var weg: Array[int] = []
	var k3 := best
	while k3 >= 0:
		weg.append(k3)
		k3 = vor[k3]
	weg.reverse()
	print("=== WEG (vom Ufer abwaerts) ===")
	print("   Grad  Abstand   Hoehe   hoechster Punkt bisher")
	var lauf := -1e9
	for idx in weg.size():
		var k4: int = weg[idx]
		var p := mitte + Vector2(float(k4 % w - n), float(k4 / w - n)) * schritt
		var dd := p - mitte
		lauf = maxf(lauf, hoehe[k4])
		print("  %6.1f  %6.0f m %7.1f m   %7.1f m" % [rad_to_deg(atan2(dd.dot(quer),
			dd.dot(ach))), dd.length(), hoehe[k4], lauf])
	quit()
	return true
