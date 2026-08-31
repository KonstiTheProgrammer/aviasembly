## KOMMT MAN IN DIE KAVERNE HINEIN?
##
## Die Frage ist nicht, ob das Portal SICHTBAR offen ist — das ist es, 60 m breit und
## 40 m hoch. Die Frage ist, ob auf dem Weg hinein ein KOLLISIONSKOERPER steht, und die
## beantwortet kein Bild.
##
## Der Verdacht, der zu diesem Werkzeug gefuehrt hat: die Roehre ist ein Netz, der Berg
## darueber ist Gelaende, und die Gelaendekollision ist eine durchgehende Flaeche. Der
## Freihaltekreis der Felswand (felswaende, fx/fz/fr) nimmt dort nur das RELIEF weg,
## damit die gebaute Stirn anschliesst — ein Loch in der Kollision ist er nicht. Wenn die
## Gelaendeflaeche vor dem Portal auf Portalhoehe steigt, fliegt man gegen unsichtbaren
## Fels, obwohl das Tor offen aussieht.
##
## GEMESSEN WIRD ZWEIERLEI:
##   PROFIL     Gelaendehoehe entlang der Talachse, auf der Achse und seitlich versetzt.
##              Zeigt, WO der Berg die lichte Hoehe der Roehre erreicht.
##   EINFLUG    Eine Kugel von Rumpfgroesse wird die Achse entlang geschoben. Gemeldet
##              wird die erste Beruehrung mit Ort, Koerper und Mass — nur so laesst sich
##              Gelaende von gebauter Roehre unterscheiden.
##
## Godot --headless --path . --script res://tools/_kaverne_einflug.gd
extends SceneTree

const START := Vector2(-11000.0, -2500.0)
const RICHTUNG := Vector2(0.6139, -0.7893)
const PORTAL_LAENGS := 9310.0
const BODEN := 90.7            # ADLERHORST_HOEHE + 0.7, der Hallenboden
const LICHT_H := 40.0          # lichte Hoehe am Portal (HB_H_MUND)
const KUGEL := 7.0             # halbe Spannweite plus Reserve

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
	if f < 40:
		return false
	var main: Node = get_meta("main")
	var tw = main.get("terrain")
	var p0 := _pkt(PORTAL_LAENGS)
	tw.build_now_around(Vector3(p0.x, BODEN, p0.y), 1600.0)

	print("PROFIL — Gelaendehoehe ueber der Talachse (Hallenboden liegt auf %.1f m,")
	print("         die Roehre ist bis %.1f m licht)" % [BODEN, BODEN + LICHT_H])
	print(" laengs |  quer -40    quer 0   quer +40 | Zustand")
	print("--------+---------------------------------+-------------------------")
	var quer := Vector2(RICHTUNG.y, -RICHTUNG.x)
	for i in 20:
		var l := 9200.0 + float(i) * 30.0
		var h: Array[float] = []
		for q: float in [-40.0, 0.0, 40.0]:
			var p := _pkt(l) + quer * q
			h.append(tw.height_at(p.x, p.y))
		var hm: float = h[1]
		var zustand := "frei (unter dem Portalboden)"
		if hm > BODEN + LICHT_H:
			zustand = "BERG ueber der Roehre — dicht"
		elif hm > BODEN + 1.0:
			zustand = "STEIGT IN DIE LICHTE HOEHE"
		print("%7.0f | %8.1f  %8.1f  %8.1f | %s" % [l, h[0], h[1], h[2], zustand])

	# --- Einflug ----------------------------------------------------------------------
	var raum := main.get_viewport().get_world_3d().direct_space_state
	print("\nEINFLUG — Kugel r=%.0f m entlang der Achse, Anflughoehe je ueber Hallenboden"
		% KUGEL)
	print("  Hoehe |  erste Beruehrung")
	print("--------+--------------------------------------------------------------")
	for hoehe: float in [8.0, 15.0, 22.0, 30.0]:
		var a := _pkt(9150.0)
		var b := _pkt(10300.0)
		var va := Vector3(a.x, BODEN + hoehe, a.y)
		var vb := Vector3(b.x, BODEN + hoehe, b.y)
		var t := _treffer(raum, va, vb)
		if t.is_empty():
			print("%6.0f m | DURCH — freier Einflug bis 990 m in den Berg" % hoehe)
		else:
			print("%6.0f m | bei laengs %5.0f  (%s)" % [hoehe, t["laengs"], t["was"]])
	# --- WIE WEIT KOMMT MAN? -----------------------------------------------------------
	#
	# Kugelproben sagen nur "hier ist was" und tasten den Raum in Stufen ab; was zwischen
	# zwei Stufen steht, sehen sie nicht. Ein Strahl trifft dagegen auf den Meter genau
	# und liefert den Ort mit. Ein Buendel paralleler Strahlen die Roehre entlang
	# beantwortet deshalb die eigentliche Frage direkt: an welcher Laengsstation endet
	# die Bahn — je Punkt des Querschnitts?
	#
	# Ausgegeben wird die LAENGE des freien Weges in Zehnermetern ab dem Portal (9310):
	# "  ." heisst ueber 200 m frei (durch), eine Zahl heisst "hier ist Schluss".
	print("\nEINDRINGTIEFE ab Portal 9310, in Metern/10. '.' = ueber 200 m frei.")
	print("Spalten quer -35..+35 (5 m), Zeilen Hoehe 40..0 ueber Hallenboden.")
	for hi in 9:
		var hoehe := 40.0 - float(hi) * 5.0
		var zeile := "  %4.0f m |" % hoehe
		for qi in 15:
			var q := -35.0 + float(qi) * 5.0
			var pa := _pkt(9310.0) + quer * q
			var pb := _pkt(10380.0) + quer * q
			var rq := PhysicsRayQueryParameters3D.create(
				Vector3(pa.x, BODEN + hoehe, pa.y), Vector3(pb.x, BODEN + hoehe, pb.y))
			rq.collision_mask = 1
			var tr := raum.intersect_ray(rq)
			if tr.is_empty():
				zeile += "    ."
			else:
				var d: Vector3 = tr["position"]
				var tief := (Vector2(d.x, d.z) - _pkt(9310.0)).dot(RICHTUNG)
				zeile += "   ." if tief > 200.0 else "%5.0f" % (tief / 10.0)
		print(zeile)
	# --- IST DER BERG NOCH DICHT? -------------------------------------------------------
	#
	# Die Aussparung nimmt Gelaendedreiecke weg, und die Sorge dabei ist berechtigt: ein
	# Loch im Hang, durch das man in die Roehre sieht, waere schlimmer als die Wand, die
	# vorher drin stand. Ein Bild beantwortet das schlecht — man muesste die richtige
	# Kamera erraten. Ein Strahl von SENKRECHT OBEN beantwortet es fuer jeden Punkt:
	# trifft er Gelaende, ist der Berg dort geschlossen; faellt er bis auf Hallenhoehe
	# durch, klafft ein Loch.
	print("\nDICHTHEIT VON OBEN — Strahl aus 2000 m senkrecht nach unten.")
	print("Trefferhoehe in m; 'LOCH' heisst: bis unter die Hallendecke durchgefallen.")
	print(" laengs |   quer -60    quer -30      quer 0    quer +30    quer +60")
	print("--------+-------------------------------------------------------------")
	var loecher := 0
	for i in 13:
		var l := 9280.0 + float(i) * 20.0
		var zeile := "%7.0f |" % l
		for q: float in [-60.0, -30.0, 0.0, 30.0, 60.0]:
			var pp := _pkt(l) + quer * q
			var rq := PhysicsRayQueryParameters3D.create(
				Vector3(pp.x, 2000.0, pp.y), Vector3(pp.x, BODEN - 20.0, pp.y))
			rq.collision_mask = 1
			var tr := raum.intersect_ray(rq)
			if tr.is_empty():
				zeile += "        LOCH"
				loecher += 1
			else:
				var y: float = (tr["position"] as Vector3).y
				# Unter der Hallendecke angekommen = durch den Berg gefallen.
				if y < BODEN + LICHT_H and l > 9330.0:
					zeile += "  %6.0f !!" % y
					loecher += 1
				else:
					zeile += "     %7.0f" % y
		print(zeile)
	print("-> %d Durchbrueche" % loecher)
	quit()
	return true


func _pkt(laengs: float) -> Vector2:
	return START + RICHTUNG * laengs


## Erste Beruehrung einer Kugel auf dem Weg a->b, mit Ort und Herkunft.
func _treffer(raum: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var n := int(a.distance_to(b) / (KUGEL * 0.6)) + 1
	var form := SphereShape3D.new()
	form.radius = KUGEL
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = form
	q.collision_mask = 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		q.transform = Transform3D(Basis.IDENTITY, p)
		var tr := raum.intersect_shape(q, 1)
		if tr.is_empty():
			continue
		var koll: Node = tr[0].collider
		# Der Pfad verraet die Herkunft: Gelaendechunk oder gebaute Roehre.
		var was := koll.name
		var el: Node = koll.get_parent()
		if el != null:
			was = "%s/%s" % [el.name, was]
		var d := Vector2(p.x, p.z) - START
		return {"laengs": d.dot(RICHTUNG), "was": was}
	return {}
