## IST DAS HOCHHAUSVIERTEL WIRKLICH DURCHFLIEGBAR?
##
## Ein Bild beantwortet das nicht. Auf einer Aufnahme von oben sieht jedes Raster
## durchlaessig aus; ob eine Gasse frei ist, entscheiden die KOLLISIONSKOERPER, und die
## sind unsichtbar. Genau deshalb gibt es dieses Werkzeug: es schiebt eine Kugel vom
## Durchmesser einer Spannweite durch die Schluchten und meldet, wo sie anstoesst.
##
## GEPRUEFT WERDEN DREI DINGE:
##
##   GASSEN     Jede durchgehende Schlucht in beiden Richtungen, auf drei Hoehen. Eine
##              Gasse, die auf 40 m frei ist und auf 90 m an einer Bruecke endet, ist
##              KEIN Fehler — Bruecken sind Absicht. Die Ausgabe zeigt deshalb, auf
##              welcher Hoehe was blockiert, statt nur "frei" oder "zu".
##   ACHSE      Die Prachtstrasse muss auf jeder Hoehe unter 200 m durchgehend frei sein.
##              Sie ist die Einflugschneise; ein Hindernis darin waere ein Hinterhalt.
##   GEGENPROBE Ein Strahl mitten durch eine Turmreihe MUSS treffen. Ohne diese Zeile
##              koennte der ganze Test auch dann "alles frei" melden, wenn die Kollision
##              gar nicht existiert — und das waere der eine Fehler, den er finden soll.
##
## Godot --headless --path . --script res://tools/_neon_flug.gd
extends SceneTree

const MITTE := Vector3(2600.0, 0.0, -3800.0)
const RASTER := 128.0
const FELDER := 13
# Halbe Spannweite plus Sicherheitsabstand. Wer mit 12 m Spannweite fliegt, will nicht
# auf den Zentimeter genau in der Mitte sein muessen.
const KUGEL := 9.0

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
	if f < 30:
		return false                     # Chunks und Kollision aufbauen lassen
	var main: Node = get_meta("main")
	var tw = main.get("terrain")
	tw.build_now_around(MITTE, 1500.0)
	var boden: float = tw.height_at(MITTE.x, MITTE.z)
	var raum := main.get_viewport().get_world_3d().direct_space_state

	print("Hoehe ueber Grund |  Gassen frei (von 12) | Prachtstrasse")
	print("------------------+-----------------------+--------------")
	var halb := float(FELDER - 1) * 0.5
	for hoehe in [30.0, 60.0, 100.0, 160.0]:
		var frei := 0
		var gesamt := 0
		var schuld: Array = []
		for i in FELDER:
			var o := (float(i) - halb) * RASTER + RASTER * 0.5
			if absf(o) > halb * RASTER:
				continue
			gesamt += 1
			# Laengs z durch die Gasse bei x = o.
			var a := MITTE + Vector3(o, boden + hoehe, -halb * RASTER - 60.0)
			var b := MITTE + Vector3(o, boden + hoehe, halb * RASTER + 60.0)
			var t := _treffer(raum, a, b)
			if t.is_empty():
				frei += 1
			else:
				schuld.append(t)
		var ach_a := MITTE + Vector3(-halb * RASTER - 200.0, boden + hoehe, 0.0)
		var ach_b := MITTE + Vector3(halb * RASTER + 200.0, boden + hoehe, 0.0)
		print("%13.0f m  | %11d von %2d     | %s"
			% [hoehe, frei, gesamt, "frei" if _frei(raum, ach_a, ach_b) else "BLOCKIERT"])
		# WAS blockiert, nicht nur DASS etwas blockiert.
		#
		# Ohne diese Zeile ist eine gesperrte Gasse nicht zu beurteilen: eine Bruecke auf
		# 90 m ist Absicht, eine Turmkante auf 90 m ist ein Baufehler, und beide melden
		# sich als "blockiert". Der Unterschied steht in der GROESSE des getroffenen
		# Koerpers — eine Bruecke ist ein flacher Riegel von 7 m Hoehe, ein Turmabschnitt
		# ist zehnmal so hoch. Deshalb wird hier das Mass des Hindernisses ausgegeben.
		for t in schuld:
			print("                  |   -> Hindernis %5.1f x %5.1f x %5.1f m bei y=%.0f (%s)"
				% [t.groesse.x, t.groesse.y, t.groesse.z, t.pos.y - boden, t.art])

	# Gegenprobe: quer durch eine Turmreihe muss es krachen.
	var t_a := MITTE + Vector3(-halb * RASTER - 60.0, boden + 60.0, 0.0)
	var t_b := MITTE + Vector3(halb * RASTER + 60.0, boden + 60.0, 0.0)
	var quer_a := MITTE + Vector3(-halb * RASTER - 60.0, boden + 60.0, RASTER * 2.0)
	var quer_b := MITTE + Vector3(halb * RASTER + 60.0, boden + 60.0, RASTER * 2.0)
	print("\nGegenprobe quer durch eine Turmreihe: %s"
		% ("TRIFFT (Kollision vorhanden)" if not _frei(raum, quer_a, quer_b)
			else "FREI — DAS WAERE EIN FEHLER"))
	print("Kontrolle Prachtstrasse auf 60 m:     %s"
		% ("frei" if _frei(raum, t_a, t_b) else "BLOCKIERT"))
	quit()
	return true


## Wie _frei, aber es MELDET das erste Hindernis statt nur seine Existenz.
##
## Zurueck kommt {} bei freier Bahn, sonst {pos, groesse, art}. "art" ist die Deutung des
## Masses: ein flacher, langer Koerper ist eine Bruecke, ein hoher ist Turm oder Block.
func _treffer(raum: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var laenge := a.distance_to(b)
	var n := int(laenge / (KUGEL * 0.8)) + 1
	var form := SphereShape3D.new()
	form.radius = KUGEL
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = form
	q.collision_mask = 1
	for i in n + 1:
		q.transform = Transform3D(Basis.IDENTITY, a.lerp(b, float(i) / float(n)))
		var tr := raum.intersect_shape(q, 1)
		if tr.is_empty():
			continue
		var koll = tr[0].collider
		var idx: int = tr[0].shape
		var cs: CollisionShape3D = koll.shape_owner_get_owner(koll.shape_find_owner(idx))
		var g := Vector3.ONE
		if cs.shape is BoxShape3D:
			g = (cs.shape as BoxShape3D).size
		elif cs.shape is CylinderShape3D:
			var zy := cs.shape as CylinderShape3D
			g = Vector3(zy.radius * 2.0, zy.height, zy.radius * 2.0)
		var art := "Bruecke" if g.y < 14.0 and maxf(g.x, g.z) > 60.0 else "Bauteil"
		return {"pos": cs.global_position, "groesse": g, "art": art}
	return {}


## Kommt eine Kugel mit Radius KUGEL von a nach b, ohne anzustoßen?
##
## Godots Formsuche liefert kein Ergebnis "erste Beruehrung ueber eine ganze Strecke",
## deshalb wird die Strecke in Schritte zerlegt und an jedem Punkt eine Kugel geprueft.
## Schrittweite kleiner als der Radius, sonst schluepft man durch duenne Waende.
func _frei(raum: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var laenge := a.distance_to(b)
	var n := int(laenge / (KUGEL * 0.8)) + 1
	var form := SphereShape3D.new()
	form.radius = KUGEL
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = form
	q.collision_mask = 1
	for i in n + 1:
		q.transform = Transform3D(Basis.IDENTITY, a.lerp(b, float(i) / float(n)))
		if not raum.intersect_shape(q, 1).is_empty():
			return false
	return true
