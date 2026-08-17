## LAEUFT DER ABFLUSS DES BERGSEES UEBERHAUPT BERGAB — und haengt er am See?
##
## Die Frage, die _see_form.gd nicht beantwortet: dort zaehlt nur die Uferlinie. Ob das
## Wasser den See auch VERLASSEN kann, entscheidet das Gelaende dahinter, und das steht
## aus drei Quellen uebereinander: gewachsener Berg, Beckenrand (SEE_WALL_*) und
## Fluss-Carve. Deshalb wird hier dreimal dasselbe Profil abgetastet und nebeneinander
## gestellt — nur so sieht man, WER den Riegel baut.
##   roh   = weder See noch Fluesse (lakes/rivers leer)  -> der gewachsene Berg
##   wall  = See ja, Fluesse nein                        -> Berg + Beckenrand
##   voll  = wie im Spiel
##
## MASSZAHL IST DIE PASSHOEHE, nicht die Hoehe an einer Stelle: der hoechste Punkt
## zwischen Uferlinie und dem jeweiligen Abstand, quer ueber den ganzen Sektor als
## MINIMUM genommen (der Bach sucht sich die niedrigste Stelle). Liegt sie ueber dem
## Spiegel, kann kein Tropfen abfliessen — dann ist der "Abfluss" ein Bach, der auf einem
## Riegel steht. Unter dem Spiegel bedeutet umgekehrt: die Flutfuellung von _see_form.gd
## laeuft dort hinaus. Beides ist falsch; richtig ist eine Schwelle knapp UEBER dem
## Spiegel, hinter der es monoton faellt.
##
## Godot --headless --path . --script res://tools/_see_abfluss.gd -- [schritt=10]
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var schritt := 10.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("schritt="):
			schritt = float(a.substr(8))

	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var mitte: Vector2 = Vector2(K["TAL_START"]) + Vector2(K["TAL_RICHTUNG"]) * float(K["SEE_LAENGS"])
	var spiegel: float = K["SEE_SPIEGEL"]
	var grad: float = TerrainWorld.SEE_ABFLUSS_GRAD

	var see: Dictionary = {}
	for lk in tw.lakes:
		if lk.has("_rad"):
			see = lk
	var ach: Vector2 = see["_achse"]
	var quer := Vector2(ach.y, -ach.x)

	# Sicherungskopien; die drei Faelle entstehen, indem lakes/rivers voruebergehend
	# geleert werden. height_at liest beide Listen bei jedem Aufruf frisch.
	var lks: Array = tw.lakes
	var rvs: Array = tw.rivers

	print("BERGSEE-ABFLUSS — Spiegel %.1f m, Richtung %.0f Grad" % [spiegel, grad])

	# --- Uferradius rund um die Scharte ------------------------------------------------
	# Der Bach darf der Uferlinie nicht zu nahe kommen (siehe unten), und "zu nahe" misst
	# sich nicht radial: neben der Scharte kann eine Bucht weit vorspringen.
	var zeile := "  "
	for g in range(110, 191, 5):
		zeile += "%d:%.0f  " % [g, tw._see_umriss(see, deg_to_rad(float(g))).x]
	print("\n=== UFERRADIUS je Grad ===\n" + zeile)

	# --- Profil laengs der Abflussrichtung ---------------------------------------------
	print("\n=== LAENGSPROFIL (Abstand vom Seemittelpunkt) ===")
	print("  Abstand    roh    wall    voll   | ueber Spiegel (voll)")
	var ufer: float = tw._see_umriss(see, deg_to_rad(grad)).x
	var d := 0.0
	var reihen: Array = []
	while d <= 1400.0:
		var p := mitte + (ach * cos(deg_to_rad(grad)) + quer * sin(deg_to_rad(grad))) * d
		tw.lakes = []; tw.rivers = []
		var h_roh := tw.height_at(p.x, p.y)
		tw.lakes = lks
		var h_wall := tw.height_at(p.x, p.y)
		tw.rivers = rvs
		var h_voll := tw.height_at(p.x, p.y)
		reihen.append([d, h_roh, h_wall, h_voll])
		var mark := ""
		if d > ufer:
			mark = "  %+5.1f m" % (h_voll - spiegel)
		print("  %6.0f m %6.1f  %6.1f  %6.1f %s%s"
			% [d, h_roh, h_wall, h_voll, mark, "   <-- UFERLINIE" if absf(d - ufer) < schritt * 0.5 else ""])
		d += schritt if d < 900.0 else 50.0

	# --- Schwelle und Passhoehe ---------------------------------------------------------
	# ZWEI ZAHLEN, ZWEI RICHTUNGEN, und beide muessen stimmen:
	#   SCHWELLE = der hoechste Punkt zwischen Uferlinie und Bachanfang. Er legt den
	#     Wasserstand fest und muss knapp UEBER dem Spiegel liegen: darunter laeuft der See
	#     aus (und die Flutfuellung von _see_form.gd mit ihm), viel darueber steht der Bach
	#     auf einem Riegel.
	#   RIEGEL = das laufende Maximum LAENGS DES BACHES ab seinem ersten Punkt. Ein Bach,
	#     der irgendwo wieder ansteigt, fliesst bergauf. Gemessen wird das Minimum quer zur
	#     Laufrichtung (+-30 m), denn die Spline trifft die Rinnensohle nicht auf den Meter.
	# Ein fester Winkelsektor taugt dafuer nicht: der Lauf dreht sich um 25 Grad, und ab
	# 1000 m Abstand liegt in jedem festen Sektor eine Bergflanke.
	var bach: Dictionary = {}
	for rv in tw.rivers:
		if int(rv.get("seebach", 0)) < 0:
			bach = rv
	var bpts: PackedVector3Array = bach["pts"]
	var kopf := Vector2(bpts[0].x, bpts[0].z)
	var kdir := (kopf - mitte).normalized()
	print("\n=== SCHWELLE (Uferlinie %.0f m bis Bachanfang) ===" % ufer)
	var schwelle := -1e9
	var ds := 0.0
	while ds <= (kopf - mitte).length() - ufer:
		var p := mitte + kdir * (ufer + ds)
		var h := tw.height_at(p.x, p.y)
		schwelle = maxf(schwelle, h)
		print("  %4.0f m hinter dem Ufer : %6.1f m  (%+5.1f)" % [ds, h, h - spiegel])
		ds += 4.0
	print("  SCHWELLE %.1f m = %+.1f m ueber dem Spiegel" % [schwelle, schwelle - spiegel])
	if schwelle < spiegel:
		print("  -> DER SEE LAEUFT AUS: die Schwelle liegt unter dem Spiegel.")
	elif schwelle > spiegel + 3.0:
		print("  -> ZU HOCH: der Bach kommt nicht an den See heran.")
	else:
		print("  -> Schwelle knapp ueber dem Spiegel. So gehoert es sich.")

	print("\n=== LAENGS DES BACHES (Minimum quer +-30 m) ===")
	var riegel := -1e9
	var lauf := 0.0
	for i in range(bpts.size() - 1):
		var a := Vector2(bpts[i].x, bpts[i].z)
		var b := Vector2(bpts[i + 1].x, bpts[i + 1].z)
		var seg := b - a
		var qn := Vector2(-seg.y, seg.x).normalized()
		var n2 := int(seg.length() / 20.0) + 1
		for s in n2:
			var p := a + seg * (float(s) / float(n2))
			var tief := 1e9
			for q in range(-3, 4):
				var pq := p + qn * float(q) * 10.0
				tief = minf(tief, tw.height_at(pq.x, pq.y))
			riegel = maxf(riegel, tief)
			if s == 0:
				print("  Punkt %2d (%5.0f m Lauflaenge): Sohle %6.1f m, hoechster Punkt bisher %6.1f m"
					% [i, lauf, tief, riegel])
			lauf += seg.length() / float(n2)
	print("  RIEGEL %.1f m = %+.1f m gegen den Bachanfang (%.1f m)"
		% [riegel, riegel - tw.height_at(kopf.x, kopf.y), tw.height_at(kopf.x, kopf.y)])
	if riegel > tw.height_at(kopf.x, kopf.y) + 1.0:
		print("  -> DER BACH FLIESST BERGAUF.")
	else:
		print("  -> Der Bach faellt auf ganzer Laenge.")

	# --- Und haengt der ZUFLUSS noch? ---------------------------------------------------
	# Er wird hier nicht veraendert, aber jede Aenderung am Beckenrand trifft ihn mit: seine
	# Muendung liegt im selben Wall.
	for rv in tw.rivers:
		if int(rv.get("seebach", 0)) <= 0:
			continue
		var zpts: PackedVector3Array = rv["pts"]
		var m := zpts[zpts.size() - 1]
		print("\n=== ZUFLUSSBACH ===")
		print("  Muendung %.0f m vom Seemittelpunkt, Wasser %.1f m (%+.1f gegen den Spiegel), Gelaende %.1f m"
			% [Vector2(m.x - mitte.x, m.z - mitte.y).length(), m.y, m.y - spiegel,
			tw.height_at(m.x, m.z)])

	# --- Wo faengt das Wasserband des Abflusses an? ------------------------------------
	for rv in tw.rivers:
		if int(rv.get("seebach", 0)) >= 0:
			continue
		var pts: PackedVector3Array = rv["pts"]
		var p0 := pts[0]
		var dd := Vector2(p0.x - mitte.x, p0.z - mitte.y)
		var a0 := rad_to_deg(atan2(dd.dot(quer), dd.dot(ach)))
		print("\n=== ABFLUSSBACH ===")
		print("  erster Stuetzpunkt: %.0f m vom Seemittelpunkt (%.0f m hinter der Uferlinie), %.0f Grad"
			% [dd.length(), dd.length() - ufer, a0])
		print("  Wasserhoehe dort %.1f m (%+.1f m gegen den Spiegel), Gelaende darunter %.1f m"
			% [p0.y, p0.y - spiegel, tw.height_at(p0.x, p0.z)])
		# ABSTAND ZUR UFERLINIE, kuerzester (nicht radialer): _river_carve wirkt im Umkreis
		# des Talbandes, und ob es den See anschneidet, entscheidet der kuerzeste Abstand.
		print("  kuerzester Abstand zur Uferlinie: %.0f m (Talband an der Quelle %.0f m)"
			% [_uferabstand(tw, see, mitte, ach, quer, Vector2(p0.x, p0.z)),
			float(rv.get("tal", PackedFloat32Array([float(rv["valley"])]))[0])])
		var vor := p0.y
		for i in range(1, pts.size()):
			var pk := pts[i]
			var dq := Vector2(pk.x - mitte.x, pk.z - mitte.y).length()
			print("   Punkt %2d: %5.0f m vom Mittelpunkt, Wasser %6.1f m (%+5.1f gegen den Vorgaenger), Gelaende %6.1f m"
				% [i, dq, pk.y, pk.y - vor, tw.height_at(pk.x, pk.z)])
			vor = pk.y
	quit()
	return true


## Kuerzester Abstand eines Punktes zur Uferlinie (720 Stuetzstellen der Umrisstabelle).
func _uferabstand(tw: TerrainWorld, see: Dictionary, mitte: Vector2, ach: Vector2,
		quer: Vector2, p: Vector2) -> float:
	var best := INF
	for i in 720:
		var a := TAU * float(i) / 720.0
		var r: float = tw._see_umriss(see, a).x
		var u := mitte + (ach * cos(a) + quer * sin(a)) * r
		best = minf(best, (u - p).length())
	return best
