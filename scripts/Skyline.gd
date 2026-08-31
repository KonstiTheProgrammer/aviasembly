## Skyline.gd — ein Hochhausviertel, durch das man HINDURCHFLIEGT.
##
## WAS DIESES VIERTEL VON DER GROSSSTADT UNTERSCHEIDET, ist nicht die Höhe, sondern die
## KOLLISION. CityBuilder setzt fertige Blender-Haeuser als MultiMesh und gibt ihnen
## bewusst keine Kollisionskoerper — man fliegt hindurch, und das ist dort auch richtig:
## aus 1500 m ist eine Stadt Koernung, kein Hindernis.
##
## Hier ist das Hindernis der ganze Zweck. Zwischen Haeusern durchzufliegen ist nur dann
## etwas wert, wenn die Haeuser hart sind — sonst ist es eine Diashow. Deshalb bekommt
## jeder Turm einen StaticBody mit Kastenformen, und deshalb sind die Schluchten breit
## genug bemessen, dass es fliegbar bleibt statt frustrierend.
##
## DIE MASSE SIND DAS EIGENTLICHE ENTWURFSPROBLEM:
##
##   RASTER 128 M, TURM 52 bis 86 M  ->  Schluchten von 42 bis 76 m Breite.
##   Ein Flugzeug dieses Spiels hat rund 12 m Spannweite und fliegt 100 bis 200 m/s.
##   Bei 60 m Gassenbreite bleiben links und rechts je 24 m Luft — eng genug, dass es
##   Koennen verlangt, weit genug, dass ein Verwackeln nicht sofort das Ende ist.
##   Enger waere kein Nervenkitzel, sondern eine Falle; weiter waere ein Feld mit Saeulen.
##
##   DIE GASSEN LAUFEN GERADE DURCH. Ein versetztes Raster saehe interessanter aus, aber
##   man kann es nicht durchfliegen — man kaeme nach zwei Bloecken vor eine Wand. Gerade
##   Fluchten sind hier Spielmechanik und nicht Bequemlichkeit.
##
##   EINE PRACHTSTRASSE von 210 m Breite quer durch die Mitte. Sie ist die Einflugschneise
##   fuer den ersten schnellen Durchgang; die engen Gassen sind fuer den zweiten.
##
## WAS ES ZU TUN GIBT, wenn man drin ist: TORE (Tuerme auf zwei Beinen, durch die man
## quer hindurchkann) und BRUECKEN zwischen den Tuermen, die man unterfliegen muss.
## Beides steht in Hoehen zwischen 40 und 170 m, also genau dort, wo man bei einem
## schnellen Durchflug ohnehin ist.
class_name Skyline
extends RefCounted

# --- Rastermasse -----------------------------------------------------------------------
const RASTER := 128.0            # Abstand der Turmmitten
const FELDER := 13               # Raster ist FELDER x FELDER
# Halbe Kantenlaenge der Blockbebauung. 40 m laesst zwischen zwei Bloecken 48 m Strasse
# frei (128 - 2*40) — genug fuer eine Spannweite mit Reserve und eng genug, dass die
# Gasse eine Schlucht ist und kein Platz.
const BLOCK_HALB := 40.0
const ACHSE_BREIT := 210.0       # halbe Breite der Prachtstrasse (freigehaltener Streifen)

# --- Turmhöhen -------------------------------------------------------------------------
# Sie fallen nach aussen ab: ein Kern, der sich aus der Ferne als Silhouette liest, und
# ein Rand, ueber den man hineinfliegt, ohne sofort in einer Wand zu stecken.
const H_KERN := 340.0
const H_RAND := 78.0
const H_SUPER := 520.0           # der eine Turm, der aus 10 km noch zu sehen ist


static func bauen(parent: Node3D, terrain, mitte: Vector3) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Skyline"
	parent.add_child(wurzel)

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5C1F                     # feste Saat: dasselbe Viertel in jedem Spiel

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)

	var koerper := StaticBody3D.new()
	koerper.name = "SkylineKollision"
	koerper.collision_layer = 1           # dieselbe Ebene wie das Gelaende
	wurzel.add_child(koerper)

	var boden: float = terrain.height_at(mitte.x, mitte.z)
	var halb := float(FELDER - 1) * 0.5
	var tuerme: Array = []                # fuer Bruecken: [Mitte, Hoehe, halbe Breite]
	var bloecke: Array[Vector3] = []      # Rasterpunkte mit Blockbebauung, fuer die Tafeln

	for gi in FELDER:
		for gj in FELDER:
			var lx := (float(gi) - halb) * RASTER
			var lz := (float(gj) - halb) * RASTER
			# Prachtstrasse quer durch die Mitte freihalten.
			if absf(lz) < ACHSE_BREIT * 0.5:
				continue
			# Ein paar Luecken als Plaetze — eine geschlossene Front waere aus der Luft
			# eine Mauer und aus der Gasse eine Roehre.
			if rng.randf() < 0.13:
				continue
			var d := Vector2(lx, lz).length()
			var t := clampf(d / (halb * RASTER), 0.0, 1.0)
			# DER AEUSSERSTE RING TRAEGT KEINE TUERME.
			#
			# Im Anflugbild endete das Viertel an einer geraden Linie: volle Turmhoehe bis
			# zum letzten Feld, dahinter Wiese. Eine Stadt hoert nicht auf, sie duennt
			# aus — erst niedrige Haeuser, dann nichts. Ohne diese Stufe sieht das Viertel
			# aus wie ausgeschnitten und aufgeklebt, und das faellt aus der Luft mehr auf
			# als jede Fassade.
			var nur_flach := t > 0.88
			var hoehe := lerpf(H_KERN, H_RAND, pow(t, 0.85)) * rng.randf_range(0.78, 1.18)
			# BREITE IST EIN BUDGET, KEIN RICHTWERT. Keine Bauform darf im Grundriss
			# darueber hinausgehen — vorher durfte eine Scheibe das 1,45-fache und ein
			# Sockel das 1,24-fache nehmen, was bei 86 m Grundmass 113 m im 128-m-Raster
			# ergeben haette. Die Gasse waere auf 15 m zusammengeschrumpft und damit fuer
			# eine Spannweite zu eng. Jetzt teilen sich alle Formen dasselbe Feld.
			var breite := rng.randf_range(46.0, 74.0)
			# VERSATZ IM FELD. Aus der Luft war das Viertel als exaktes Raster zu lesen:
			# jede Turmmitte auf dem Gitterpunkt, jede Reihe schnurgerade. Ein Versatz
			# von wenigen Metern nimmt dem Blick von oben das Tabellarische, ohne dass
			# unten eine Gasse verschwindet — die Reserve steckt im Budget oben.
			var vs := Vector3(rng.randf_range(-8.0, 8.0), 0.0, rng.randf_range(-8.0, 8.0))
			var gitter := Vector3(mitte.x + lx, boden, mitte.z + lz)
			var mp := gitter + vs
			# Blockrandbebauung ZUERST — der Turm steht danach mitten darin und verdeckt
			# die Stossfuge, statt neben ihr zu stehen.
			var bcol := _ton(rng)
			bcol.a = (float(rng.randi() % 3) + rng.randf()) / 3.2
			# 0.68 statt 0.5 mal Breite: der Grundriss ist bis zu 12 Grad gedreht (Faktor
			# 1.19) und die Attika steht 1,2 m ueber. Lieber etwas zu grosszuegig gesperrt
			# als ein Kasten, der aus einer Turmwand herausschaut.
			_block(st, koerper, gitter, bcol, mp,
				0.0 if nur_flach else breite * 0.68, rng, 0.55 if nur_flach else 1.0)
			bloecke.append(gitter)
			# Jeder achte Turm ist ein TOR: zwei Beine, oben zusammengefasst. Man kann
			# quer hindurch, und das ist die auffaelligste Belohnung fuers Hinsehen.
			if nur_flach:
				pass                       # nur der Block, den _block schon gesetzt hat
			elif rng.randf() < 0.13 and hoehe > 150.0:
				_tor(st, koerper, mp, breite, hoehe, rng)
				tuerme.append([mp, hoehe, breite * 0.5])
			else:
				_turm(st, koerper, mp, breite, hoehe, rng)
				tuerme.append([mp, hoehe, breite * 0.5])

	# --- Der eine sehr hohe Turm, NEBEN der Prachtstrasse -----------------------------
	#
	# NEBEN, NICHT AUF IHR. Zuerst stand er genau in der Mitte — und damit mitten in der
	# Einflugschneise. Der Durchflugtest (tools/_neon_flug.gd) meldete die Prachtstrasse
	# daraufhin auf JEDER Hoehe als blockiert, waehrend elf bis zwoelf der zwoelf engen
	# Gassen frei waren: ausgerechnet die breite, einladende Achse war die einzige Falle.
	# Jetzt flankiert er sie — als Marke am Rand, an der man vorbeizieht.
	#
	# UND ER WUERFELT SEINE FORM NICHT. Seit es Archetypen gibt, wuerde _turm() auch fuer
	# ihn eine ziehen — er koennte als gedrungenes Kreuz oder als Scheibe herauskommen.
	# Das Wahrzeichen eines Viertels ist aber genau der Turm, dessen Form man NICHT dem
	# Zufall ueberlaesst: er ist die Marke, an der man sich aus 10 km orientiert, und dafuer
	# braucht er die eine Silhouette, die sich von allen anderen unterscheidet — eine
	# Nadel. Er bekommt sie ausdruecklich, achsparallel und ohne Drehung.
	var sup := Vector3(mitte.x, boden, mitte.z - ACHSE_BREIT * 0.5 - 78.0)
	# Art 0 = senkrechte Baender: die Fassadensprache, die eine Nadel hoch aussehen laesst.
	_t_spitz(st, koerper, sup, 74.0, H_SUPER, Color(0.33, 0.36, 0.42, 0.5 / 3.2), 0.0, rng)
	_mast(st, koerper, wurzel, sup + Vector3(0.0, H_SUPER, 0.0))

	# --- Brücken zwischen benachbarten Türmen -----------------------------------------
	_bruecken(st, koerper, tuerme, rng)

	# --- Straßenbelag: die Schluchten SIND die Straßen ---------------------------------
	_belag(wurzel, mitte, boden)
	_ausstattung(wurzel, mitte, boden, bloecke, rng)

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "SkylineNetz"
	mi.mesh = st.commit()
	mi.material_override = _material(boden)
	wurzel.add_child(mi)
	return wurzel


## DIE BLOCKRANDBEBAUUNG — und sie ist die groesste Einzelverbesserung des Viertels.
##
## WAS DAS BILD VORHER ZEIGTE. Ein 1,7 km grosses, fast einfarbiges Feld aus hellem Belag
## mit duennen Strichen darauf, und darauf einzeln hingestellte Tuerme mit breiten Luecken
## dazwischen. Aus der Gasse sah das aus wie ein Flughafenvorfeld, auf dem jemand
## Hochhaeuser abgestellt hat. Der Grund war nicht die Farbe des Belags: es fehlte das,
## was eine Strasse ueberhaupt zur Strasse macht — eine WAND an ihrem Rand.
##
## Ein Turm allein liefert die nicht. Er ist rund 60 m breit in einem 128-m-Feld, also
## steht zwischen zwei Tuermen mehr Luft als Haus. Erst ein niedriger Baukoerper, der das
## Feld bis kurz vor die Fahrbahn ausfuellt, schliesst die Front. Dann ist unten eine
## Schlucht mit durchgehenden Waenden und oben die Staffelung der Tuerme — und genau
## dieser Schnitt ist es, wonach ein Hochhausviertel aussieht.
##
## DAS FLIEGEN GEWINNT DABEI, es verliert nicht. Die Gasse wird von "irgendwo zwischen
## den Tuermen durch" zu einem klar begrenzten Kanal von 48 m Breite, dessen Waende man
## im Tiefflug rechts und links vorbeiziehen sieht. Das ist der Unterschied zwischen
## schnell fliegen und schnell AUSSEHEN.
##
## DER BLOCK STEHT AUF DEM RASTERPUNKT, NICHT AUF DER VERSETZTEN TURMMITTE. Der Versatz
## (+/-8 m) soll die Tuerme aus der Reihe bringen; die Strassenkante muss dagegen gerade
## bleiben, sonst maeandert die Gasse und die gemessene Mindestbreite gilt nicht mehr.
static func _block(st: SurfaceTool, koerper: StaticBody3D, gitter: Vector3, col: Color,
		turm: Vector3, turm_halb: float, rng: RandomNumberGenerator,
		hoch := 1.0) -> void:
	var h := rng.randf_range(11.0, 30.0) * hoch
	# Der Block ist nie ganz quadratisch — sonst liegt an jeder Ecke dieselbe Kante.
	var bx := BLOCK_HALB * 2.0 * rng.randf_range(0.86, 1.0)
	var bz := BLOCK_HALB * 2.0 * rng.randf_range(0.86, 1.0)
	var m := gitter + Vector3(0.0, h * 0.5, 0.0)
	_kasten(st, m, Vector3(bx, h, bz), col)
	_koll(koerper, m, Vector3(bx, h, bz))
	# Attika: dieselbe Schattenfuge wie bei den Tuermen, aus demselben Grund.
	var ha := 1.8
	var ma := gitter + Vector3(0.0, h + ha * 0.5, 0.0)
	_kasten(st, ma, Vector3(bx + 1.6, ha, bz + 1.6), _sch(col, 1.05), 0.0, true)
	_koll(koerper, ma, Vector3(bx + 1.6, ha, bz + 1.6))

	# WO DAS DACH WIRKLICH LIEGT. Ein Teil der Bloecke bekommt ein zweites, eingerticktes
	# Geschoss — das gibt der Dachlandschaft zwischen den Tuermen eine zweite Hoehe statt
	# einer durchgehenden Tischplatte. Die Technik muss dann aber DARAUF stehen und nicht
	# hindurch: beide auf dieselbe Hoehe zu setzen war der Fehler der ersten Fassung, und
	# er faellt aus der Luft sofort auf. Deshalb wird die tatsaechliche Deckflaeche
	# mitgefuehrt statt zweimal unabhaengig aus h berechnet.
	var dach_y := h + ha
	var dach_x := bx
	var dach_z := bz
	if rng.randf() < 0.45:
		var h2 := rng.randf_range(5.0, 13.0)
		var f := rng.randf_range(0.55, 0.78)
		var v := _dreh(Vector2(bx * (1.0 - f) * 0.5 * rng.randf_range(-0.6, 0.6),
			bz * (1.0 - f) * 0.5 * rng.randf_range(-0.6, 0.6)), 0.0)
		var m2 := gitter + v + Vector3(0.0, dach_y + h2 * 0.5, 0.0)
		_kasten(st, m2, Vector3(bx * f, h2, bz * f), col)
		_koll(koerper, m2, Vector3(bx * f, h2, bz * f))
		dach_y += h2
		dach_x = bx * f
		dach_z = bz * f
		gitter += v
	# Ein Blockdach ist gross und flach und liegt genau auf der Hoehe, in der man durch
	# das Viertel zieht — es ist die Flaeche, die man am laengsten ansieht. Es bekommt
	# deshalb MEHR Aufbauten als ein Turmdach, nicht weniger.
	_dachaufbauten(st, koerper, gitter + Vector3(0.0, dach_y, 0.0), dach_x, dach_z, 0.0,
		3 + (rng.randi() % 3), rng, turm, turm_halb)


## Ein Turm. WELCHER Turm, entscheidet der Wuerfel.
##
## WARUM UEBERHAUPT ARCHETYPEN. Die erste Fassung kannte genau eine Bauform: einen
## Stapel aus zwei bis vier Kaesten mit Ruecksprung. Bei hundertdreissig Tuermen heisst
## das hundertdreissig Mal dasselbe Haus in leicht anderer Groesse. Aus der Gasse sieht
## man das sofort — nicht als "aehnlich", sondern als "das ist EIN Modell, kopiert". Eine
## Skyline lebt davon, dass die Silhouetten sich unterscheiden: Scheibe neben Rundturm
## neben Nadel. Erst dann traegt sie einen Blick nach oben.
##
## EINE FARBE JE TURM, NICHT JE KASTEN. Der zweite Fehler der ersten Fassung: _ton() wurde
## fuer JEDE Stufe neu gewuerfelt. Ein Haus, dessen Sockel sandfarben und dessen Aufsatz
## blaugrau ist, liest sich nicht als gegliedert, sondern als verrechnet. Die Farbe wird
## deshalb hier oben EINMAL gezogen und nach unten durchgereicht; Unterschiede zwischen
## den Flaechen macht schon _kasten() ueber die Seitentoene.
##
## Die Verteilung ist bewusst schief: der Staffelturm bleibt haeufig, weil er das ruhige
## Grundrauschen einer Skyline ist. Die auffaelligen Formen sind selten genug, dass sie
## auffallen — bei gleicher Verteilung waere das Viertel ein Musterkatalog.
static func _turm(st: SurfaceTool, koerper: StaticBody3D, fuss: Vector3, breite: float,
		hoehe: float, rng: RandomNumberGenerator) -> void:
	var col := _ton(rng)
	# FASSADENART UND MASSSTAB IN DEN ALPHAKANAL. Der Shader liest sie dort wieder aus
	# (die lange Begruendung steht in _material). Geteilt wird durch 3.2 statt durch 3,
	# damit der groesste Wert (2 + fast 1) bei 0.937 landet und die Grenze 0.94 fuer
	# "glattes Bauteil" nicht von oben erreicht wird.
	col.a = (float(rng.randi() % 3) + rng.randf()) / 3.2
	# Die Drehung ist klein und selten: die meisten Haeuser folgen dem Strassenraster,
	# weil sie an einer Strasse stehen. Nur ein Teil schert aus. Waeren alle gedreht,
	# saehe es aus wie ein umgekipptes Regal, nicht wie eine gewachsene Stadt.
	# ZWOELF GRAD, NICHT MEHR. Ein gedrehter Grundriss belegt mehr Platz als ein gerader:
	# ein Quadrat der Kante b misst quer gemessen b*(cos a + sin a), bei 12 Grad also das
	# 1,19-fache. Genau das frisst die Reserve, die die Gasse offen haelt.
	var yaw := 0.0
	if rng.randf() < 0.40:
		yaw = deg_to_rad(rng.randf_range(-12.0, 12.0))
	var w := rng.randf()
	if w < 0.30:
		_t_staffel(st, koerper, fuss, breite, hoehe, col, yaw, rng)
	elif w < 0.46:
		_t_sockel(st, koerper, fuss, breite, hoehe, col, yaw, rng)
	elif w < 0.62:
		_t_scheibe(st, koerper, fuss, breite, hoehe, col, yaw, rng)
	elif w < 0.76:
		_t_rund(st, koerper, fuss, breite, hoehe, col, yaw, rng)
	elif w < 0.89:
		_t_spitz(st, koerper, fuss, breite, hoehe, col, yaw, rng)
	else:
		_t_kreuz(st, koerper, fuss, breite, hoehe, col, yaw, rng)


## STAFFELTURM — gestapelte Kaesten mit Ruecksprung. Das ruhige Grundrauschen.
static func _t_staffel(st: SurfaceTool, koerper: StaticBody3D, fuss: Vector3, breite: float,
		hoehe: float, col: Color, yaw: float, rng: RandomNumberGenerator) -> void:
	var stufen := 2 + (rng.randi() % 3)
	var y := 0.0
	var b := breite * rng.randf_range(0.84, 1.0)
	var t := breite * rng.randf_range(0.76, 1.0)
	# Die Krone sitzt auf der OBERSTEN Stufe, nicht auf einer weiter geschrumpften: die
	# Schleife rueckt am Ende noch einmal ein, obwohl darueber nichts mehr kommt. Deshalb
	# werden die zuletzt GEBAUTEN Masse mitgefuehrt.
	var b_oben := b
	var t_oben := t
	for i in stufen:
		var rest := hoehe - y
		var h: float = rest if i == stufen - 1 else rest * rng.randf_range(0.35, 0.62)
		var mitte := fuss + Vector3(0.0, y + h * 0.5, 0.0)
		var groesse := Vector3(b, h, t)
		_kasten(st, mitte, groesse, col, yaw)
		_koll(koerper, mitte, groesse, yaw)
		b_oben = b
		t_oben = t
		y += h
		# Ruecksprung in BEIDEN Richtungen, sonst wird der Turm nach oben zur Klinge.
		var f := rng.randf_range(0.76, 0.92)
		b *= f
		t *= f
	_krone(st, koerper, fuss + Vector3(0.0, hoehe, 0.0), b_oben, t_oben, hoehe, col,
		yaw, rng)


## SOCKELTURM — breites Podium, schlanker Schaft darauf.
##
## Die haeufigste Bauform echter Geschaeftsviertel und aus der Gasse die wirksamste: der
## Sockel steht dicht an der Fahrbahn, der Schaft weicht zurueck. Wer unten durchfliegt,
## sieht deshalb eine ENGE Schlucht mit hohem Himmel darueber statt eines gleichmaessigen
## Schachts.
static func _t_sockel(st: SurfaceTool, koerper: StaticBody3D, fuss: Vector3, breite: float,
		hoehe: float, col: Color, yaw: float, rng: RandomNumberGenerator) -> void:
	var h_sockel: float = minf(hoehe * rng.randf_range(0.14, 0.24), 46.0)
	# Der Sockel schoepft das Budget aus, der Schaft weicht zurueck. So bleibt der
	# Rueckstaffelungs-Eindruck erhalten, ohne dass irgendetwas ueber das Feld hinausragt.
	var bs := breite * rng.randf_range(0.92, 1.0)
	var ts := breite * rng.randf_range(0.90, 1.0)
	var m := fuss + Vector3(0.0, h_sockel * 0.5, 0.0)
	_kasten(st, m, Vector3(bs, h_sockel, ts), col, yaw)
	_koll(koerper, m, Vector3(bs, h_sockel, ts), yaw)

	var b := bs * rng.randf_range(0.56, 0.72)
	var t := ts * rng.randf_range(0.56, 0.72)
	var hs := hoehe - h_sockel
	# Der Schaft steht nicht mittig, sondern an eine Kante des Sockels gerueckt — sonst
	# sieht die Anordnung wie eine Torte mit Kerze aus.
	var v := _dreh(Vector2((bs - b) * 0.5 * rng.randf_range(-0.7, 0.7),
		(ts - t) * 0.5 * rng.randf_range(-0.7, 0.7)), yaw)
	m = fuss + v + Vector3(0.0, h_sockel + hs * 0.5, 0.0)
	_kasten(st, m, Vector3(b, hs, t), col, yaw)
	_koll(koerper, m, Vector3(b, hs, t), yaw)
	_krone(st, koerper, fuss + v + Vector3(0.0, hoehe, 0.0), b, t, hoehe, col, yaw, rng)


## SCHEIBE — lang in der einen, duenn in der anderen Richtung.
##
## Von der schmalen Seite eine Nadel, von der breiten eine Wand: dieselbe Form gibt aus
## zwei Anflugrichtungen zwei voellig verschiedene Bilder. Manche bekommen einen SCHLITZ,
## einen durchgehenden Spalt in der Mitte — das ist aus der Luft die auffaelligste
## Einzelheit des ganzen Viertels.
static func _t_scheibe(st: SurfaceTool, koerper: StaticBody3D, fuss: Vector3, breite: float,
		hoehe: float, col: Color, yaw: float, rng: RandomNumberGenerator) -> void:
	var lang := breite * rng.randf_range(0.90, 1.0)
	var duenn := breite * rng.randf_range(0.30, 0.44)
	var quer := rng.randf() < 0.5           # welche Richtung ist die lange?
	var bx: float = lang if quer else duenn
	var bz: float = duenn if quer else lang
	if rng.randf() < 0.34 and hoehe > 170.0:
		# Mit Schlitz: zwei Haelften, dazwischen Luft, oben durch einen Riegel verbunden.
		var spalt := breite * rng.randf_range(0.18, 0.30)
		var teil := (lang - spalt) * 0.5
		var h_riegel: float = minf(hoehe * 0.16, 44.0)
		var hs := hoehe - h_riegel
		for sgn: float in [-1.0, 1.0]:
			var off := (spalt + teil) * 0.5 * sgn
			var m := fuss + _dreh(Vector2(off, 0.0) if quer else Vector2(0.0, off), yaw) \
				+ Vector3(0.0, hs * 0.5, 0.0)
			var g := Vector3(teil if quer else duenn, hs, duenn if quer else teil)
			_kasten(st, m, g, col, yaw)
			_koll(koerper, m, g, yaw)
		var mr := fuss + Vector3(0.0, hs + h_riegel * 0.5, 0.0)
		_kasten(st, mr, Vector3(bx, h_riegel, bz), col, yaw)
		_koll(koerper, mr, Vector3(bx, h_riegel, bz), yaw)
	else:
		var m := fuss + Vector3(0.0, hoehe * 0.5, 0.0)
		_kasten(st, m, Vector3(bx, hoehe, bz), col, yaw)
		_koll(koerper, m, Vector3(bx, hoehe, bz), yaw)
	_krone(st, koerper, fuss + Vector3(0.0, hoehe, 0.0), bx, bz, hoehe, col, yaw, rng)


## RUNDTURM — ein Vielkant, der aus der Entfernung als Zylinder liest.
##
## Zwoelf Seiten sind der Punkt, an dem die Silhouette rund wirkt und die Fassade noch
## ebene Facetten hat — das braucht der Shader, dessen Fensterachsen eine Wandrichtung
## voraussetzen. Bei acht Seiten sieht man das Vieleck, bei zwanzig zahlt man Dreiecke
## fuer nichts.
static func _t_rund(st: SurfaceTool, koerper: StaticBody3D, fuss: Vector3, breite: float,
		hoehe: float, col: Color, yaw: float, rng: RandomNumberGenerator) -> void:
	# r*1.14 ist bei abgesetztem Kopf der weiteste Punkt — der Faktor steckt hier drin.
	var r := breite * 0.5 * rng.randf_range(0.78, 0.86)
	var dreh := rng.randf() * TAU
	var r_oben := r
	if rng.randf() < 0.4:
		# Abgesetzter Kopf: der obere Zylinder ist weiter als der Schaft.
		#
		# 0.86 UND 1.06, NICHT 0.74 UND 1.14. Der erste Anlauf liess den Kopf um 54 %
		# ueber den Schaft springen — im Bild war das kein abgesetztes Geschoss mehr,
		# sondern ein Pilz. Ein Absatz muss man SEHEN, aber er darf die Silhouette nicht
		# uebernehmen; 23 % Sprung sind der Punkt, an dem beides zutrifft.
		var hs := hoehe * rng.randf_range(0.74, 0.86)
		_prisma(st, fuss, r * 0.86, hs, 12, dreh, col)
		_koll_rund(koerper, fuss + Vector3(0.0, hs * 0.5, 0.0), r * 0.86, hs)
		var hk := hoehe - hs
		_prisma(st, fuss + Vector3(0.0, hs, 0.0), r * 1.06, hk, 12, dreh, col, true)
		_koll_rund(koerper, fuss + Vector3(0.0, hs + hk * 0.5, 0.0), r * 1.06, hk)
		r_oben = r * 1.06
	else:
		_prisma(st, fuss, r, hoehe, 12, dreh, col)
		_koll_rund(koerper, fuss + Vector3(0.0, hoehe * 0.5, 0.0), r, hoehe)
	_krone_rund(st, koerper, fuss + Vector3(0.0, hoehe, 0.0), r_oben, dreh, col, rng)


## SPITZTURM — verjuengt sich ueber schraege Waende und endet in einer Nadel.
##
## SCHRAEGE WAENDE, keine gestapelten Kaesten. Das ist der Unterschied, auf den es
## ankommt: ein Stapel hat waagerechte Absaetze, ein Stumpf hat eine durchgehende Linie
## nach oben. Im Gegenlicht ist das die einzige Silhouette im Viertel, die nicht aus
## rechten Winkeln besteht.
static func _t_spitz(st: SurfaceTool, koerper: StaticBody3D, fuss: Vector3, breite: float,
		hoehe: float, col: Color, yaw: float, rng: RandomNumberGenerator) -> void:
	var h_schaft := hoehe * rng.randf_range(0.80, 0.90)
	var b0 := Vector2(breite * rng.randf_range(0.88, 1.0),
		breite * rng.randf_range(0.82, 1.0))
	var b1 := b0 * rng.randf_range(0.42, 0.60)
	_stumpf(st, fuss, b0, b1, h_schaft, col, yaw)
	# Kollision als DREI Kaesten statt einem: ein einzelner Quader um den ganzen Stumpf
	# waere unten richtig und oben viel zu breit — man wuerde in Luft anstossen.
	for i in 3:
		var t0 := float(i) / 3.0
		var t1 := float(i + 1) / 3.0
		var bm := b0.lerp(b1, (t0 + t1) * 0.5)
		var hm := h_schaft * (t1 - t0)
		_koll(koerper, fuss + Vector3(0.0, h_schaft * (t0 + t1) * 0.5, 0.0),
			Vector3(bm.x, hm, bm.y), yaw)
	# Die Nadel: ein duenner Stumpf, der fast auf einen Punkt zulaeuft.
	var hn := hoehe - h_schaft
	_stumpf(st, fuss + Vector3(0.0, h_schaft, 0.0), b1 * 0.5, b1 * 0.10, hn, _sch(col, 0.9), yaw)
	_koll(koerper, fuss + Vector3(0.0, h_schaft + hn * 0.5, 0.0),
		Vector3(b1.x * 0.3, hn, b1.y * 0.3), yaw)


## KREUZTURM — zwei sich durchdringende Scheiben.
##
## Der Grundriss ist ein Kreuz, und das heisst: aus JEDER der vier Himmelsrichtungen
## sieht man eine schmale Seite mit tiefen Einschnitten daneben. Diese Form wirft die
## interessantesten Schatten auf sich selbst — bei tiefer Sonne zieht sie eine harte
## Kante quer ueber die eigene Fassade.
static func _t_kreuz(st: SurfaceTool, koerper: StaticBody3D, fuss: Vector3, breite: float,
		hoehe: float, col: Color, yaw: float, rng: RandomNumberGenerator) -> void:
	var lang := breite * rng.randf_range(0.90, 1.0)
	var duenn := breite * rng.randf_range(0.36, 0.48)
	var m := fuss + Vector3(0.0, hoehe * 0.5, 0.0)
	# Der Querarm endet tiefer als der Laengsarm — sonst ist die Silhouette wieder ein
	# flacher Deckel und die ganze Form von aussen nicht zu erkennen.
	var h2 := hoehe * rng.randf_range(0.62, 0.82)
	_kasten(st, m, Vector3(lang, hoehe, duenn), col, yaw)
	_koll(koerper, m, Vector3(lang, hoehe, duenn), yaw)
	var m2 := fuss + Vector3(0.0, h2 * 0.5, 0.0)
	_kasten(st, m2, Vector3(duenn, h2, lang), col, yaw)
	_koll(koerper, m2, Vector3(duenn, h2, lang), yaw)
	_krone(st, koerper, fuss + Vector3(0.0, hoehe, 0.0), lang, duenn, hoehe, col, yaw, rng)


## DIE KRONE EINES RUNDTURMS — und warum sie nicht die eckige sein darf.
##
## _krone() setzt einen KASTEN als Attika. Auf einen Zylinder gesetzt ergibt das einen
## quadratischen Deckel auf rundem Schaft, und im Bild sah man genau das: einen Teller,
## der an vier Stellen uebersteht und an vier Stellen zurueckspringt. Dazu kam ein
## Rechenfehler — _kasten erwartet die volle Breite, bekam aber r*1.2 statt 2*r, der
## Deckel war also zusaetzlich nur halb so gross wie der Turm.
##
## Ein Zylinder braucht einen Ring. Derselbe _prisma, nur flach und etwas weiter.
static func _krone_rund(st: SurfaceTool, koerper: StaticBody3D, oben: Vector3, r: float,
		dreh: float, col: Color, rng: RandomNumberGenerator) -> void:
	var ha := rng.randf_range(2.4, 4.0)
	_prisma(st, oben, r + 1.3, ha, 12, dreh, _sch(col, 1.04), true)
	_koll_rund(koerper, oben + Vector3(0.0, ha * 0.5, 0.0), r + 1.3, ha)
	if rng.randf() < 0.30:
		var nc := Color(0.26, 0.84, 1.0) if rng.randf() < 0.5 else Color(1.0, 0.26, 0.40)
		nc.a = 0.98
		_prisma(st, oben + Vector3(0.0, ha * 0.42, 0.0), r + 1.9, ha * 0.30, 12, dreh, nc, true)
	# Die Technik steht im QUADRAT innerhalb des Kreises — Kaesten auf einem runden Dach
	# duerfen nicht bis an den Rand, sonst haengen sie ueber die Kante.
	_dachaufbauten(st, koerper, oben + Vector3(0.0, ha, 0.0), r * 1.30, r * 1.30, dreh,
		1 + (rng.randi() % 3), rng)


## DAS DACH. Attika, Technikaufbauten, bei den hohen ein Mast.
##
## WARUM DAS DIE GROESSTE EINZELNE VERBESSERUNG IST. Auf dem ersten Bild von unten waren
## alle Daecher nackte, dunkle Deckel — als haette jemand die Tuerme mit einem Messer
## abgeschnitten. Genau das ist es, was ein Kasten von einem Haus unterscheidet: ein Haus
## hat oben eine Kante, die uebersteht, und darauf Technik, die niemand versteckt hat.
##
## Die Attika steht 1,2 m ueber die Fassade hinaus. Das ist wenig und trotzdem der
## wirksamste Teil: sie erzeugt eine Schattenfuge rund um den Turmkopf, und diese Fuge
## ist es, die man aus der Ferne als "Dach" liest.
static func _krone(st: SurfaceTool, koerper: StaticBody3D, oben: Vector3, bx: float,
		bz: float, hoehe: float, col: Color, yaw: float, rng: RandomNumberGenerator) -> void:
	var h_att := rng.randf_range(2.4, 4.2)
	var m := oben + Vector3(0.0, h_att * 0.5, 0.0)
	var g := Vector3(bx + 2.4, h_att, bz + 2.4)
	_kasten(st, m, g, _sch(col, 1.04), yaw, true)
	_koll(koerper, m, g, yaw)

	_dachaufbauten(st, koerper, oben + Vector3(0.0, h_att, 0.0), bx, bz, yaw,
		2 + (rng.randi() % 3), rng)

	# KRONENBAND. Ein schmaler leuchtender Ring auf der Attika. Aus der Luft ist er das,
	# was NEONBUCHT von jeder anderen Ansammlung grauer Kaesten unterscheidet — und im
	# Gegenlicht, wenn die Fassaden zu Silhouetten werden, ist er das Einzige, was noch
	# Farbe hat. Er faehrt im FASSADENNETZ mit und wird ueber Alpha 0.98 leuchtend
	# gemacht (siehe _material); ein eigenes Netz waere ein Zeichenaufruf fuer zwei Ringe.
	if rng.randf() < 0.30:
		const KRONE_NEON := [Color(1.0, 0.26, 0.40), Color(0.26, 0.84, 1.0),
			Color(0.62, 0.38, 1.0), Color(1.0, 0.74, 0.22)]
		var nc: Color = KRONE_NEON[rng.randi() % KRONE_NEON.size()]
		nc.a = 0.98
		var mb := oben + Vector3(0.0, h_att * 0.62, 0.0)
		_kasten(st, mb, Vector3(bx + 3.0, h_att * 0.30, bz + 3.0), nc, yaw, true)

	# Ein Mast nur auf den hohen. Auf jedem Dach waere es ein Nadelkissen.
	if hoehe > 240.0 and rng.randf() < 0.55:
		var hm := rng.randf_range(14.0, 34.0)
		var mm := oben + Vector3(0.0, h_att + hm * 0.5, 0.0)
		_kasten(st, mm, Vector3(1.6, hm, 1.6), Color(0.42, 0.20, 0.18))


## TECHNIK AUF EINEM DACH: Aufzugskopf, Lueftung, Kuehler, Wassertank.
##
## WARUM DAS AUS DER LUFT MEHR ZAEHLT ALS JEDE FASSADE. Wer ueber ein Viertel hinwegfliegt,
## sieht ueberwiegend DAECHER — schaetzungsweise ein Drittel des Bildes. Ein leeres Dach
## ist eine leere Flaeche, und hundert leere Flaechen nebeneinander sehen aus wie ein
## Grundriss, ueber den jemand Farbe gegossen hat. Ein paar Kaesten darauf geben jedem
## Dach eine eigene Silhouette und, wichtiger, einen Schatten AUF sich selbst.
##
## Alle Aufbauten teilen einen hellen Betonton, nie den der Fassade: Technik wird
## nachtraeglich aufgestellt und passt sich dem Haus nicht an. Genau dieser Bruch ist es,
## der sie als Aufbauten lesbar macht statt als Fortsetzung des Turmes.
##
## Sie bekommen Kollision. Ein sichtbarer Kasten, durch den man hindurchfliegt, ist
## schlimmer als gar keiner — und Dachkanten streifen ist genau das, wofuer man tief
## fliegt.
static func _dachaufbauten(st: SurfaceTool, koerper: StaticBody3D, dach: Vector3,
		bx: float, bz: float, yaw: float, n: int, rng: RandomNumberGenerator,
		sperr_mitte := Vector3.ZERO, sperr_halb := 0.0) -> void:
	var tech := Color(0.55, 0.55, 0.54)
	for i in n:
		var hb := rng.randf_range(3.5, 12.0)
		var gb := Vector3(bx * rng.randf_range(0.16, 0.38), hb,
			bz * rng.randf_range(0.16, 0.38))
		var pos := dach + _dreh(Vector2((bx - gb.x) * 0.5 * rng.randf_range(-0.82, 0.82),
			(bz - gb.z) * 0.5 * rng.randf_range(-0.82, 0.82)), yaw) \
			+ Vector3(0.0, hb * 0.5, 0.0)
		# SPERRZONE. Auf einem Blockdach steht mitten im Feld der Turm. Ein Aufbau, der
		# dort landet, steckt im Turm und ragt auf der anderen Seite wieder heraus — im
		# Bild waren das beige Klumpen, die auf halber Hoehe aus den Fassaden wuchsen.
		#
		# Ein blosser Mindestabstand vom Feldmittelpunkt genuegt dafuer NICHT: der Turm
		# ist versetzt und bis zu 88 m breit, das Blockdach nur 80 m — es gibt Faelle, in
		# denen der Turm das ganze Dach ueberdeckt. Deshalb wird gegen die tatsaechliche
		# Turmmitte und deren tatsaechliches Mass geprueft, und wo kein Platz ist, steht
		# eben nichts. Weniger Aufbauten sind besser als steckende.
		if sperr_halb > 0.0 \
				and absf(pos.x - sperr_mitte.x) < sperr_halb + gb.x * 0.5 \
				and absf(pos.z - sperr_mitte.z) < sperr_halb + gb.z * 0.5:
			continue
		_kasten(st, pos, gb, tech, yaw)
		_koll(koerper, pos, gb, yaw)
		# Ein Teil bekommt einen Kuehler obendrauf: ein flacher, breiterer Kasten. Das
		# ist die Silhouette, an der man einen Technikaufbau ueberhaupt erkennt.
		if rng.randf() < 0.4:
			var gk := Vector3(gb.x * 1.25, 1.4, gb.z * 1.25)
			_kasten(st, pos + Vector3(0.0, hb * 0.5 + 0.7, 0.0), gk, _sch(tech, 0.86), yaw, true)


## Ein Vielkant (Prisma) in das gemeinsame Netz.
##
## DIE UMLAUFRICHTUNG ist dieselbe wie bei _kasten und stammt direkt von dort: der Kasten
## IST ein Vierkant, seine vier Seiten laufen in der Reihenfolge (-x,-z) (+x,-z) (+x,+z)
## (-x,+z) — also mit STEIGENDEM Winkel atan2(z, x) — und jede Seite ist
## (unten, oben, naechstes oben, naechstes unten). Wer das aus dem Kopf herleiten will,
## dreht es zuverlaessig um; hier ist es aus einer Flaeche abgelesen, die sichtbar ist.
static func _prisma(st: SurfaceTool, fuss: Vector3, r: float, h: float, seiten: int,
		dreh: float, col: Color, unterseite := false) -> void:
	var oben := fuss.y + h
	for i in seiten:
		var a0 := dreh + TAU * float(i) / float(seiten)
		var a1 := dreh + TAU * float(i + 1) / float(seiten)
		var p0 := Vector3(fuss.x + cos(a0) * r, 0.0, fuss.z + sin(a0) * r)
		var p1 := Vector3(fuss.x + cos(a1) * r, 0.0, fuss.z + sin(a1) * r)
		# Jede Facette leicht anders hell, damit der Zylinder auch im Schatten rund wirkt.
		var t := 0.86 + 0.20 * (0.5 + 0.5 * cos(a0 - 0.6))
		_quad(st,
			Vector3(p0.x, fuss.y, p0.z), Vector3(p0.x, oben, p0.z),
			Vector3(p1.x, oben, p1.z), Vector3(p1.x, fuss.y, p1.z), _sch(col, t))
	# Deckel als Faecher um die Mitte.
	for i in seiten:
		var a0 := dreh + TAU * float(i) / float(seiten)
		var a1 := dreh + TAU * float(i + 1) / float(seiten)
		st.set_color(_dachton(col))
		st.add_vertex(Vector3(fuss.x, oben, fuss.z))
		st.add_vertex(Vector3(fuss.x + cos(a0) * r, oben, fuss.z + sin(a0) * r))
		st.add_vertex(Vector3(fuss.x + cos(a1) * r, oben, fuss.z + sin(a1) * r))
	if unterseite:
		for i in seiten:
			var a0 := dreh + TAU * float(i) / float(seiten)
			var a1 := dreh + TAU * float(i + 1) / float(seiten)
			st.set_color(_sch(col, 0.62))
			st.add_vertex(Vector3(fuss.x, fuss.y, fuss.z))
			st.add_vertex(Vector3(fuss.x + cos(a1) * r, fuss.y, fuss.z + sin(a1) * r))
			st.add_vertex(Vector3(fuss.x + cos(a0) * r, fuss.y, fuss.z + sin(a0) * r))


## Ein Stumpf: unten b0 breit, oben b1 breit, mit SCHRAEGEN Waenden.
static func _stumpf(st: SurfaceTool, fuss: Vector3, b0: Vector2, b1: Vector2, h: float,
		col: Color, yaw: float = 0.0) -> void:
	var oben := fuss.y + h
	# Grundrissecken in derselben Umlaufrichtung wie _kasten.
	var ecken := [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5),
		Vector2(-0.5, 0.5)]
	var seiten := [0.94, 1.0, 0.88, 0.82]
	var cs := cos(yaw)
	var sn := sin(yaw)
	var u := func(e: Vector2, b: Vector2, y: float) -> Vector3:
		var v := Vector2(e.x * b.x, e.y * b.y)
		return Vector3(fuss.x + v.x * cs - v.y * sn, y, fuss.z + v.x * sn + v.y * cs)
	for i in 4:
		var e0: Vector2 = ecken[i]
		var e1: Vector2 = ecken[(i + 1) % 4]
		var t: float = seiten[i]
		_quad(st, u.call(e0, b0, fuss.y), u.call(e0, b1, oben),
			u.call(e1, b1, oben), u.call(e1, b0, fuss.y), _sch(col, t))
	_quad(st, u.call(ecken[0], b1, oben), u.call(ecken[3], b1, oben),
		u.call(ecken[2], b1, oben), u.call(ecken[1], b1, oben), _dachton(col))


## Ein Versatz IN TURMACHSEN als Weltversatz.
##
## Gebraucht ueberall dort, wo ein Bauteil "an die linke Kante" oder "an die schmale
## Seite" gesetzt wird: solche Angaben meinen die Achsen DES TURMES. Ohne diese Drehung
## wandert ein Anbau bei gedrehtem Turm sichtbar aus der Flucht — der Sockel steht schief
## unter dem Schaft, der Aufzugskopf haengt ueber die Attika hinaus.
static func _dreh(v: Vector2, yaw: float) -> Vector3:
	var c := cos(yaw)
	var n := sin(yaw)
	return Vector3(v.x * c - v.y * n, 0.0, v.x * n + v.y * c)


## Eine Flaeche abdunkeln, OHNE den Alphakanal anzufassen.
##
## Ab jetzt traegt Color.a die Fassadenart (siehe _material). Ein schlichtes `col * 0.88`
## wuerde sie mitmultiplizieren — Godots Color-Multiplikation nimmt alle vier Kanaele —
## und aus einer Lochfassade auf der Sonnenseite wuerde auf der Schattenseite eine andere
## Bauart. Genau der Fehler, den man erst im Bild sieht und dann lange sucht.
## Eine sRGB-Farbe in den linearen Raum, in dem Godot rechnet.
##
## WARUM DAS HIER STEHEN MUSS. Der Fassadenshader rechnet die Scheitelfarbe ausdruecklich
## um; die Flaechen mit StandardMaterial3D (Belag, Laternen, Tafeln) taten es nicht, und
## deren vertex_color_use_as_albedo reicht den Wert UNVERAENDERT als linearen Albedo
## durch. Ein als "dunkles Asphaltgrau" gemeintes 0.27 ist linear gelesen etwa 0.56 in
## sRGB — also mittelhell. Zusammen mit der warmen Sonne (1.0/0.94/0.80 bei Energie 1.55)
## und ACES kam daraus das helle Beige, das im Bild wie ein Flughafenvorfeld aussah.
## Nicht die Farbwahl war falsch, sondern der Farbraum.
static func _srgb(c: Color) -> Color:
	return c.srgb_to_linear()


static func _sch(col: Color, t: float) -> Color:
	return Color(col.r * t, col.g * t, col.b * t, col.a)


## Der Ton der DECKFLAECHE eines Baukoerpers.
##
## WAS FALSCH WAR: die Oberseite bekam die Fassadenfarbe mal 1.08, war also HELLER als
## die Waende. Das ist genau verkehrt herum. Ein Dach ist kein weitergefuehrtes Mauerwerk,
## sondern Kies, Bitumen und Blech — grau, matt und deutlich dunkler als die Fassade. Aus
## der Luft ist die Dachflaeche knapp ein Drittel von allem, was man sieht; solange sie
## in Fassadenfarbe leuchtet, sieht ein Hochhausviertel aus wie ein Stapel Bauklötze.
##
## Nicht rein grau, sondern zur Fassade hin gemischt: ein Dach nimmt Staub und Abrieb
## vom eigenen Haus an, und ein voellig einheitliches Grau ueber allen Daechern waere die
## naechste Gleichfoermigkeit.
##
## LEUCHTBAENDER (Alpha ueber 0.96) bleiben unberuehrt — ein grau abgetoentes Neonband
## waere kein Neonband mehr.
static func _dachton(col: Color) -> Color:
	if col.a > 0.96:
		return col
	var kies := Color(0.26, 0.26, 0.25)
	return Color(lerpf(col.r, kies.r, 0.62), lerpf(col.g, kies.g, 0.62),
		lerpf(col.b, kies.b, 0.62), col.a)


static func _koll_rund(koerper: StaticBody3D, mitte: Vector3, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var zy := CylinderShape3D.new()
	zy.radius = r
	zy.height = h
	cs.shape = zy
	cs.position = mitte
	koerper.add_child(cs)


## Ein Turm auf zwei Beinen: man kann quer hindurchfliegen.
##
## Die Durchfahrt ist 46 m hoch und so breit wie der Turm minus zwei Beine — also rund
## 30 bis 50 m. Deutlich enger als eine Gasse, und genau deshalb ist sie das, worauf man
## beim zweiten Durchgang zielt.
static func _tor(st: SurfaceTool, koerper: StaticBody3D, fuss: Vector3, breite: float,
		hoehe: float, rng: RandomNumberGenerator) -> void:
	var col := _ton(rng)
	col.a = (float(rng.randi() % 3) + rng.randf()) / 3.2
	var yaw := deg_to_rad(rng.randf_range(-12.0, 12.0)) if rng.randf() < 0.4 else 0.0
	var bein := breite * 0.26
	var durch := 46.0
	var tiefe := breite * rng.randf_range(0.86, 1.10)
	for sx: float in [-1.0, 1.0]:
		var m := fuss + _dreh(Vector2(sx * (breite * 0.5 - bein * 0.5), 0.0), yaw) \
			+ Vector3(0.0, durch * 0.5, 0.0)
		var g := Vector3(bein, durch, tiefe)
		_kasten(st, m, g, col, yaw)
		_koll(koerper, m, g, yaw)
	# Alles oberhalb der Durchfahrt ist wieder ein normaler Turm.
	var rest := hoehe - durch
	var mo := fuss + Vector3(0.0, durch + rest * 0.5, 0.0)
	var go := Vector3(breite, rest, tiefe)
	_kasten(st, mo, go, col, yaw)
	_koll(koerper, mo, go, yaw)
	_krone(st, koerper, fuss + Vector3(0.0, hoehe, 0.0), breite, tiefe, hoehe, col, yaw, rng)


## Brücken zwischen nahen Türmen — Hindernisse auf Flughöhe.
##
## Sie werden NICHT zufällig gespannt, sondern nur zwischen Türmen, die sich im Raster
## direkt benachbart sind und beide hoch genug sind. Eine Brücke, die quer über eine
## Kreuzung läuft, wäre aus der Gasse nicht zu sehen und damit ein unfairer Treffer.
static func _bruecken(st: SurfaceTool, koerper: StaticBody3D, tuerme: Array,
		rng: RandomNumberGenerator) -> void:
	var gebaut := 0
	for i in tuerme.size():
		if gebaut >= 18:
			break
		if rng.randf() > 0.22:
			continue
		var a: Array = tuerme[i]
		var pa: Vector3 = a[0]
		for j in range(i + 1, tuerme.size()):
			var b: Array = tuerme[j]
			var pb: Vector3 = b[0]
			var d := Vector2(pb.x - pa.x, pb.z - pa.z).length()
			if d < RASTER * 0.9 or d > RASTER * 1.15:
				continue
			var hmax: float = minf(float(a[1]), float(b[1]))
			if hmax < 120.0:
				continue
			# Zwischen 40 und 170 m, aber immer unter beiden Dachkanten.
			var y := rng.randf_range(45.0, minf(170.0, hmax - 25.0))
			var m := (pa + pb) * 0.5 + Vector3(0.0, y, 0.0)
			var laengs := (pb - pa).normalized()
			var g := Vector3(d, 7.0, 11.0)
			# Der Kasten liegt laengs x; bei einer Bruecke in z-Richtung tauschen.
			if absf(laengs.z) > absf(laengs.x):
				g = Vector3(11.0, 7.0, d)
			_kasten(st, m, g, Color(0.44, 0.45, 0.48), 0.0, true)
			_koll(koerper, m, g)
			gebaut += 1
			break


## Sendemast auf dem höchsten Dach — dieselbe Rolle wie der am Heimatplatz: eine Marke,
## die man aus großer Entfernung sieht und anfliegen kann.
static func _mast(st: SurfaceTool, koerper: StaticBody3D, wurzel: Node3D,
		dach: Vector3) -> void:
	var h := 70.0
	var m := dach + Vector3(0.0, h * 0.5, 0.0)
	var g := Vector3(3.0, h, 3.0)
	_kasten(st, m, g, Color(0.58, 0.24, 0.22))
	_koll(koerper, m, g)
	var lampe := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.0
	sm.height = 6.0
	sm.radial_segments = 8
	sm.rings = 5
	lampe.mesh = sm
	lampe.position = dach + Vector3(0.0, h + 3.0, 0.0)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1.0, 0.2, 0.15)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.2, 0.15)
	lm.emission_energy_multiplier = 7.0
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lampe.material_override = lm
	wurzel.add_child(lampe)


## Die Farbe eines Turmes.
##
## WAS VORHER FALSCH WAR: ein Grauwert zwischen 0,42 und 0,66, dazu ein Hauch Blau ODER
## Sand. Das ist rechnerisch Abwechslung und im Bild keine — hundertdreissig Tuerme in
## einem einzigen Beigeton, der sich in der dritten Nachkommastelle unterscheidet. Eine
## Skyline ist nicht deshalb interessant, weil ihre Haeuser leicht verschieden hell sind,
## sondern weil dunkles Glas neben hellem Kalkstein neben rotem Backstein steht.
##
## Sieben FAMILIEN mit deutlichem Abstand zueinander, in jeder eine kleine Streuung. Der
## Abstand zwischen den Familien ist der ganze Zweck; die Streuung innerhalb sorgt nur
## dafuer, dass zwei Nachbarn derselben Familie nicht wie ein Haus aussehen.
##
## Die Gewichte sind ungleich: Beton und Kalkstein tragen das Viertel, Backstein und
## dunkles Glas sind die Ausnahmen, die man wahrnimmt. Waeren alle gleich haeufig, waere
## das Ergebnis wieder ein Mittelwert — nur ein bunterer.
static func _ton(rng: RandomNumberGenerator) -> Color:
	var w := rng.randf()
	var c: Color
	if w < 0.22:
		c = Color(0.54, 0.55, 0.58)       # Beton, kuehl
	elif w < 0.42:
		c = Color(0.68, 0.67, 0.64)       # Kalkstein, hell
	elif w < 0.58:
		c = Color(0.60, 0.56, 0.48)       # Sandstein
	elif w < 0.72:
		c = Color(0.36, 0.40, 0.46)       # dunkles Glas
	elif w < 0.84:
		c = Color(0.46, 0.44, 0.42)       # Beton, warmgrau
	elif w < 0.94:
		c = Color(0.50, 0.36, 0.30)       # Backstein
	else:
		c = Color(0.30, 0.33, 0.35)       # fast schwarz — die seltenen Marken im Viertel
	var v := rng.randf_range(0.88, 1.12)
	return Color(clampf(c.r * v, 0.0, 1.0), clampf(c.g * v, 0.0, 1.0),
		clampf(c.b * v, 0.0, 1.0))


static func _koll(koerper: StaticBody3D, mitte: Vector3, groesse: Vector3,
		yaw: float = 0.0) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = groesse
	cs.shape = bs
	# Die Kollision muss dieselbe Drehung tragen wie das Netz. Ein gedrehter Turm mit
	# achsparallelem Koerper waere der schlimmste Fall von allen: man streift sichtbar
	# Luft und fliegt sichtbar durch Wand.
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), mitte)
	koerper.add_child(cs)


## Ein Kasten in das gemeinsame Netz. Jede Seite bekommt ihren eigenen Ton, damit ein
## Turm auch ohne direktes Sonnenlicht noch Kanten zeigt.
##
## GIERDREHUNG. Aus der Luft war das Viertel vorher als exaktes Raster zu lesen: jeder
## Turm achsparallel, jede Kante zu jeder anderen Kante parallel. Das ist der Blick auf
## eine Tabelle, nicht auf eine Stadt. Ein paar Grad Drehung je Turm brechen das auf,
## ohne die Gassen anzutasten — die Drehung dreht den Turm um SEINE Mitte, der Platz im
## Raster bleibt.
##
## Die Ecken werden dafuer gedreht, nicht der Kasten: das Netz ist ein einziges Mesh in
## Weltkoordinaten, es gibt keinen Knoten, den man drehen koennte.
## `unterseite` schliesst den Kasten nach unten.
##
## WOZU, UND WARUM NICHT IMMER. Ein Kasten hatte bisher vier Waende und einen Deckel,
## aber keinen Boden — bei einem Baukoerper, der auf dem Grund oder auf einem anderen
## Kasten steht, ist das richtig: die Flaeche waere nie zu sehen und wuerde mit dem
## Nachbarn um dieselbe Ebene streiten (Z-Fighting).
##
## Bei einem UEBERSTEHENDEN Teil ist es dagegen ein sichtbarer Fehler. Die Attika steht
## 1,2 m ueber die Fassade, und wer von der Strasse hinaufsieht, blickt genau unter diesen
## Ueberstand. Ohne Bodenflaeche sieht er dort ins offene Innere des Kastens — und weil
## cull_back die zugewandten Innenwaende wegwirft, erscheint das als dunkler Keil unter
## jedem Turmkopf. Im Bild sah es aus wie ein schwarzer Schatten, der keiner war.
static func _kasten(st: SurfaceTool, mitte: Vector3, groesse: Vector3, col: Color,
		yaw: float = 0.0, unterseite := false) -> void:
	var h := groesse * 0.5
	var y0 := mitte.y - h.y
	var y1 := mitte.y + h.y
	var cs := cos(yaw)
	var sn := sin(yaw)
	# Ecken in derselben Umlaufrichtung wie ueberall sonst: (-x,-z) (+x,-z) (+x,+z) (-x,+z).
	var e := [Vector2(-h.x, -h.z), Vector2(h.x, -h.z), Vector2(h.x, h.z), Vector2(-h.x, h.z)]
	var p: Array[Vector2] = []
	for v: Vector2 in e:
		p.append(Vector2(mitte.x + v.x * cs - v.y * sn, mitte.z + v.x * sn + v.y * cs))
	var seiten := [0.94, 1.0, 0.88, 0.82]
	for i in 4:
		var a: Vector2 = p[i]
		var b: Vector2 = p[(i + 1) % 4]
		var t: float = seiten[i]
		_quad(st, Vector3(a.x, y0, a.y), Vector3(a.x, y1, a.y),
			Vector3(b.x, y1, b.y), Vector3(b.x, y0, b.y), _sch(col, t))
	_quad(st, Vector3(p[0].x, y1, p[0].y), Vector3(p[3].x, y1, p[3].y),
		Vector3(p[2].x, y1, p[2].y), Vector3(p[1].x, y1, p[1].y), _dachton(col))
	if unterseite:
		# Genau umgekehrt umlaufen wie der Deckel — dann zeigt sie nach unten.
		_quad(st, Vector3(p[0].x, y0, p[0].y), Vector3(p[1].x, y0, p[1].y),
			Vector3(p[2].x, y0, p[2].y), Vector3(p[3].x, y0, p[3].y), _sch(col, 0.62))


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.set_color(col)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


## Der Boden des Viertels: eine durchgehende Platte mit hellen Fahrbahnen darauf.
##
## WARUM UEBERHAUPT. Die Flachzone ebnet den Grund und nimmt ihm den Bewuchs, aber die
## FARBE bleibt die des Bioms — im ersten Anlauf standen die Hochhaeuser auf einer Wiese,
## und das sah aus wie Modellbau auf einem Rasenteppich. Eine Stadt hat unter sich Belag.
##
## DAS RASTER DER FAHRBAHNEN IST DAS DER TUERME. Das ist keine Kosmetik: die hellen
## Baender zeigen dem Piloten schon aus der Anflughoehe, WO die durchgehenden Schluchten
## liegen. Wer im Tiefflug hinein will, sieht seine Gasse, bevor er in ihr steckt.
static func _belag(wurzel: Node3D, mitte: Vector3, boden: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rand := float(FELDER) * RASTER * 0.5 + 40.0
	# --- AUSGEFRANSTE KANTE ------------------------------------------------------------
	#
	# Die Grundplatte ist ein Rechteck, und ein Rechteck endet an einer geraden Linie. Im
	# Anflug sah man deshalb Asphalt, dann einen Strich, dann Wiese — auf 1,7 km ohne eine
	# einzige Unterbrechung. Nichts an einer Stadt hat eine solche Kante.
	#
	# GEFRANST WIRD NACH INNEN, NICHT NACH AUSSEN. Der naheliegende Weg waere ein Ring
	# zusaetzlicher Felder jenseits der Platte — er ist falsch. Die Flachzone des Viertels
	# (Main._setup_world) ebnet und entwaldet ein Rechteck von +/-880 m, und das ist
	# genau das Mass der Platte. Kacheln DAHINTER laegen auf abfallendem Gelaende und
	# mitten im Wald: schwebende Platten mit Baeumen hindurch. Also wird die geschlossene
	# Flaeche verkleinert und der frei werdende Streifen zur Franse — dieselbe Wirkung,
	# vollstaendig innerhalb dessen, was das Gelaende schon hergibt.
	var kern := rand - 116.0
	var kachel := 58.0
	_platte(st, Vector3(mitte.x, boden + 0.12, mitte.z), kern * 2.0, kern * 2.0,
		_srgb(Color(0.19, 0.19, 0.198)))
	var rf := RandomNumberGenerator.new()
	rf.seed = 0x3A9C
	var kn := int(rand / kachel) + 1
	for i in range(-kn, kn + 1):
		for j in range(-kn, kn + 1):
			var px := (float(i) + 0.5) * kachel
			var pz := (float(j) + 0.5) * kachel
			if absf(px) < kern and absf(pz) < kern:
				continue                      # schon von der Platte gedeckt
			if absf(px) > rand or absf(pz) > rand:
				continue                      # ausserhalb der geebneten Flaeche
			# Nach aussen fallende Wahrscheinlichkeit — das ist das ganze Mittel.
			var ueber := (maxf(absf(px), absf(pz)) - kern) / (rand - kern)
			if rf.randf() < ueber * 0.92:
				continue
			_platte(st, Vector3(mitte.x + px, boden + 0.115, mitte.z + pz),
				kachel, kachel, _srgb(Color(0.185, 0.185, 0.19)))

	var halb := float(FELDER - 1) * 0.5
	for i in FELDER:
		var o := (float(i) - halb) * RASTER
		# Fahrbahn zwischen zwei Turmreihen, also auf der halben Rastermasse versetzt.
		var m := o + RASTER * 0.5
		if absf(m) > rand:
			continue
		# Die Fahrbahn ist BREITER als vorher (26 -> 44 m): seit die Bloecke die Felder
		# ausfuellen, ist der freie Streifen 48 m, und ein 26-m-Band darin liess links
		# und rechts einen unerklaerlichen Saum stehen. Jetzt reicht der Asphalt fast bis
		# an die Hauswand, wie in einer Strasse.
		# Laenge = Kern, nicht rand: eine Fahrbahn, die ueber die Luecken der Franse
		# hinauslaeuft, schwebt dort ueber Wiese.
		_platte(st, Vector3(mitte.x + m, boden + 0.20, mitte.z), 44.0, kern * 2.0,
			_srgb(Color(0.235, 0.235, 0.243)))
		_platte(st, Vector3(mitte.x, boden + 0.20, mitte.z + m), kern * 2.0, 44.0,
			_srgb(Color(0.235, 0.235, 0.243)))
	# Die Prachtstrasse quer durch die Mitte — breit, hell, unuebersehbar.
	_platte(st, Vector3(mitte.x, boden + 0.26, mitte.z), kern * 2.0, ACHSE_BREIT * 0.86,
		_srgb(Color(0.265, 0.265, 0.275)))
	# --- Mittellinien: was die Gasse im Tiefflug LESBAR macht -------------------------
	#
	# Eine Gasse ist aus 300 m Entfernung ein dunkler Spalt zwischen zwei Tuermen — man
	# sieht, DASS dort etwas frei ist, aber nicht, ob sie durchgeht und wohin sie fuehrt.
	# Eine unterbrochene helle Linie auf ihrem Grund beantwortet beides in dem Moment,
	# in dem man sie ueberhaupt zum ersten Mal sieht: eine Fluchtlinie zeigt Richtung UND
	# Durchgaengigkeit. Dasselbe Mittel wie die Bahnbefeuerung in der Kaverne, aus
	# demselben Grund.
	var strich := 34.0        # Strichlaenge
	var luecke := 26.0
	for i in FELDER:
		var o := (float(i) - halb) * RASTER + RASTER * 0.5
		if absf(o) > kern:
			continue
		var n := int(kern * 2.0 / (strich + luecke))
		for k in n:
			var s0 := -kern + float(k) * (strich + luecke) + strich * 0.5
			_platte(st, Vector3(mitte.x + o, boden + 0.30, mitte.z + s0),
				2.2, strich, _srgb(Color(0.82, 0.80, 0.66)))
			_platte(st, Vector3(mitte.x + s0, boden + 0.30, mitte.z + o),
				strich, 2.2, _srgb(Color(0.82, 0.80, 0.66)))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "SkylineBelag"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.93
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mi)


## STRASSENEBENE: Laternen, Schilder, Container.
##
## WARUM DAS MEHR IST ALS DEKORATION. Im Tiefflug durch eine Schlucht fehlt bisher das
## Wichtigste, was Geschwindigkeit ueberhaupt spuerbar macht: etwas Nahes, das VORBEIZIEHT.
## Die Turmwaende sind 30 m entfernt und glatt; sie bewegen sich am Rand des Blickfelds
## kaum. Eine Reihe Masten in gleichem Abstand direkt neben der Fahrbahn liefert genau den
## Takt, aus dem das Auge Tempo liest — dasselbe Prinzip wie Leitpfosten an der Landstrasse.
## Ohne sie fliegt man in einer Schlucht schnell und fuehlt sich langsam.
##
## DIE SCHILDER SIND DER NAME DES VIERTELS. NEONBUCHT hiess bisher so, ohne dass irgendwo
## Neon gewesen waere. Ein paar grosse leuchtende Tafeln an den Fassaden geben dem Ort
## eine Farbe, die keine Landschaft der Karte sonst hat — und aus der Ferne im Gegenlicht
## sind sie das, woran man das Viertel erkennt, bevor man die Tuerme unterscheiden kann.
##
## ZWEI NETZE, WEIL ZWEI MATERIALIEN. Masten duerfen das Fassadenraster nicht bekommen —
## ein 1 m dicker Pfosten mit Fensterachsen darauf waere gestreifter Unsinn. Und Tafeln
## brauchen Eigenleuchten, das die Masten nicht haben sollen. Beides sind eigene Flaechen.
static func _ausstattung(wurzel: Node3D, mitte: Vector3, boden: float,
		bloecke: Array[Vector3], rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var leucht := SurfaceTool.new()
	leucht.begin(Mesh.PRIMITIVE_TRIANGLES)
	leucht.set_smooth_group(-1)

	var rand := float(FELDER) * RASTER * 0.5 + 40.0
	var halb := float(FELDER - 1) * 0.5
	var stahl := _srgb(Color(0.22, 0.23, 0.25))

	# --- Masten entlang jeder Fahrbahn ------------------------------------------------
	#
	# ABSTAND 62 m, EINE SEITE. Enger waere aus der Luft ein Kamm und kostet Dreiecke fuer
	# nichts; auf beiden Seiten verdoppelt es die Zahl, ohne den Takt zu verbessern — man
	# fliegt in der Mitte und sieht ohnehin nur eine Reihe scharf.
	const MAST_AB := 62.0
	for i in FELDER:
		var o := (float(i) - halb) * RASTER + RASTER * 0.5
		if absf(o) > rand:
			continue
		var n := int(rand * 2.0 / MAST_AB)
		for k in n:
			var t := -rand + float(k) * MAST_AB + MAST_AB * 0.5
			_laterne(st, Vector3(mitte.x + o + 13.0, boden, mitte.z + t), true, stahl)
			_laterne(st, Vector3(mitte.x + t, boden, mitte.z + o + 13.0), false, stahl)

	# --- Leuchttafeln an den Blockfassaden ---------------------------------------------
	#
	# AN DEN BLOECKEN, NICHT AN DEN TUERMEN — und das ist keine Geschmacksfrage, sondern
	# die Lehre aus dem ersten Versuch. Der setzte die Tafeln auf "Rasterpunkt plus 40 m"
	# in der Hoffnung, dort stehe schon eine Turmwand. Die Tuerme sind aber im Feld
	# versetzt, gedreht und unterschiedlich breit: die Tafeln standen daraufhin frei in
	# der Luft, mitten ueber der Strasse, und sahen im Bild aus wie ein Fehler im Netz.
	#
	# Ein Block hat dagegen eine EXAKT bekannte Aussenkante — er sitzt ohne Versatz auf
	# dem Rasterpunkt und ist ungedreht. Deshalb wird hier aus der Liste der wirklich
	# gebauten Bloecke gezogen und die Tafel an deren Wand gesetzt. Was nicht gebaut
	# wurde, steht auch nicht in der Liste; freischwebende Tafeln koennen so gar nicht
	# mehr entstehen.
	const NEON := [Color(1.0, 0.24, 0.42), Color(0.24, 0.86, 1.0), Color(1.0, 0.70, 0.18),
		Color(0.55, 0.32, 1.0), Color(0.30, 1.0, 0.52)]
	if not bloecke.is_empty():
		for k in 34:
			var g: Vector3 = bloecke[rng.randi() % bloecke.size()]
			var quer := rng.randf() < 0.5
			var seite: float = 1.0 if rng.randf() < 0.5 else -1.0
			# Die Tafel haengt ueber der Strasse an der Blockwand; ihre Oberkante bleibt
			# unter der niedrigsten Blockhoehe (11 m), damit sie nie ueber die Attika
			# hinausragt und wieder frei steht.
			var ht := rng.randf_range(3.4, 6.0)
			var bt := rng.randf_range(10.0, 22.0)
			var y := rng.randf_range(4.0, 9.0)
			# Laengs der Wand versetzt, sonst sitzt jede Tafel mittig auf ihrer Fassade.
			var laengs := rng.randf_range(-BLOCK_HALB * 0.5, BLOCK_HALB * 0.5)
			var col: Color = NEON[rng.randi() % NEON.size()]
			# 0.9 m vor der Wand: weit genug, dass nichts durchsticht (der Block ist bis
			# zu 14 % schmaler als BLOCK_HALB*2), nah genug, dass sie anliegt.
			if quer:
				_kasten(leucht, g + Vector3(seite * (BLOCK_HALB + 0.9), y, laengs),
					Vector3(1.0, ht, bt), col, 0.0, true)
			else:
				_kasten(leucht, g + Vector3(laengs, y, seite * (BLOCK_HALB + 0.9)),
					Vector3(bt, ht, 1.0), col, 0.0, true)

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "SkylineAusstattung"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.65
	mat.metallic = 0.4
	mi.material_override = mat
	wurzel.add_child(mi)

	leucht.generate_normals()
	var ml := MeshInstance3D.new()
	ml.name = "SkylineNeon"
	ml.mesh = leucht.commit()
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	# Eigenleuchten aus der Scheitelfarbe: EINE Tafel-Farbe je Material waere ein
	# Material je Tafel und damit 26 Zeichenaufrufe. So bleibt es einer.
	lm.emission_enabled = true
	lm.emission_energy_multiplier = 1.6
	lm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	lm.emission = Color.WHITE
	ml.material_override = lm
	# Tafeln werfen keinen Schatten: sie sind duenn, und ihr Schatten waere ein Strich
	# quer ueber die Fassade, der aussieht wie ein Fehler im Netz.
	ml.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(ml)


## Eine Laterne: Mast mit auskragendem Arm.
##
## Der Arm zeigt IMMER zur Fahrbahn, deshalb der Schalter: an einer Gasse laengs z steht
## der Mast seitlich und muss nach -x auskragen, an einer Gasse laengs x nach -z.
static func _laterne(st: SurfaceTool, fuss: Vector3, laengs_z: bool, col: Color) -> void:
	var h := 11.0
	_kasten(st, fuss + Vector3(0.0, h * 0.5, 0.0), Vector3(0.9, h, 0.9), col)
	var arm := 4.6
	var am: Vector3 = fuss + Vector3(-arm * 0.5, h - 0.6, 0.0) if laengs_z \
		else fuss + Vector3(0.0, h - 0.6, -arm * 0.5)
	var ag: Vector3 = Vector3(arm, 0.6, 0.6) if laengs_z else Vector3(0.6, 0.6, arm)
	_kasten(st, am, ag, _sch(col, 1.1), 0.0, true)
	# Der Kopf ist hell — er faengt bei tiefer Sonne einen Lichtpunkt, und das ist es,
	# was die Reihe im Tiefflug ueberhaupt sichtbar macht.
	var km: Vector3 = fuss + Vector3(-arm, h - 1.1, 0.0) if laengs_z \
		else fuss + Vector3(0.0, h - 1.1, -arm)
	_kasten(st, km, Vector3(1.9, 0.5, 1.4), Color(0.86, 0.84, 0.74).srgb_to_linear(),
		0.0, true)


## Eine waagerechte Platte.
##
## WICKLUNGSRICHTUNG — UND ICH HABE SIE HIER ZUM ZWEITEN MAL FALSCH GERATEN. Die erste
## Fassung nahm (x0,z0) (x0,z1) (x1,z1) (x1,z0) und war im Bild vollstaendig unsichtbar,
## genau wie das Strassennetz der Grossstadt einen Tag zuvor (siehe
## CityBuilder._band). In der x/z-Ebene der Welt ist wegen der gespiegelten z-Achse die
## UMGEKEHRTE Reihenfolge die nach oben zeigende. Der Wert unten ist der, der dort
## nachweislich funktioniert hat — nicht der, den ich fuer richtig hielt.
static func _platte(st: SurfaceTool, m: Vector3, bx: float, bz: float, col: Color) -> void:
	var x0 := m.x - bx * 0.5
	var x1 := m.x + bx * 0.5
	var z0 := m.z - bz * 0.5
	var z1 := m.z + bz * 0.5
	st.set_color(col)
	st.add_vertex(Vector3(x0, m.y, z0)); st.add_vertex(Vector3(x1, m.y, z0))
	st.add_vertex(Vector3(x1, m.y, z1))
	st.set_color(col)
	st.add_vertex(Vector3(x0, m.y, z0)); st.add_vertex(Vector3(x1, m.y, z1))
	st.add_vertex(Vector3(x0, m.y, z1))


## FASSADENRASTER AUS DEM SHADER, NICHT AUS GEOMETRIE.
##
## WARUM UEBERHAUPT IM SHADER. Ein Turm ohne Gliederung ist eine Betonstele. Als
## Geometrie waere sie teuer: hundertdreissig Tuerme mit je fuenfzig Geschossen auf vier
## Seiten sind ueber 25 000 zusaetzliche Vierecke, und sie zerbrechen das eine Netz in
## viele. Im Shader kostet sie nichts.
##
## WAS AN DER ERSTEN FASSUNG FALSCH WAR — und es war grundlegend falsch, nicht knapp
## daneben: sie zog NUR waagerechte Baender. Ein Hochhaus, das von oben bis unten aus
## gleich dicken Querstreifen besteht, sieht aus wie Kordsamt, und zwar auf jedem Turm
## identisch. Eine Fassade ist ein RASTER aus zwei Richtungen: Geschosse waagerecht,
## Fensterachsen senkrecht. Erst ihr Kreuz macht daraus Architektur.
##
## DIE SENKRECHTE KOORDINATE muss ENTLANG der Wand laufen, nicht in Weltrichtung x oder
## z. Welche der beiden es ist, verraet die Normale: zeigt sie nach x, laeuft die Wand in
## z — und umgekehrt. Bei runden Tuermen ist das je Facette richtig, weil jede Facette
## eben ist.
##
## SOCKEL UND KRONE. Ein Haus hat unten etwas anderes als in der Mitte: hohe Erdgeschosse,
## keine Fensterachsen, dunkler. Weil alle Tuerme dieses Viertels auf derselben
## eingeebneten Flaeche stehen, genuegt EIN Uniform fuer die Bodenhoehe — der Shader kann
## daraus "Hoehe ueber Grund" bilden, ohne dass jeder Turm sein eigenes Material braucht.
static func _material(boden: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, diffuse_burley;

// Geschosshoehe und Achsbreite in Metern. Beide bewusst groesser als in Wirklichkeit
// (3 m / 1,5 m): bei echten Massen waere das Raster aus 300 m feiner als ein Bildpunkt
// und wuerde nur flimmern. Gebraucht wird eine LESBARE Gliederung, keine Bauzeichnung.
// Grundwerte; das Mass je Turm wird daraus gestreckt (siehe unten, sk).
uniform float geschoss = 7.0;
uniform float achse = 9.0;
// Anteil des Rasterfeldes, der Glas ist. Der Rest ist Bruestung und Pfosten.
uniform float glasanteil = 0.62;
uniform vec3 glas : source_color = vec3(0.20, 0.30, 0.40);
uniform float boden = 0.0;
// Hoehe der Sockelzone ueber Grund.
uniform float sockel_h = 13.0;

varying vec3 welt;
// DIE NORMALE IM WELTRAUM, ausdruecklich als eigenes varying.
//
// In Godot ist NORMAL im fragment() im SICHTRAUM. Dort heisst NORMAL.y nicht "oben",
// sondern "oben aus Sicht der Kamera" — ein Dach waere je nach Blickwinkel mal waagerecht
// und mal senkrecht, und die Fensterachsen wuerden beim Fliegen ueber die Fassade wandern.
// Im vertex() ist NORMAL dagegen noch im Modellraum, also einmal mit MODEL_MATRIX drehen
// und selbst weiterreichen. Bei flacher Schattierung ist sie je Flaeche konstant, die
// Interpolation kostet also nichts.
varying vec3 wnorm;

void vertex() {
	welt = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Ein weiches Fenster in einer Wiederholung: 1 in der Mitte des Feldes, 0 am Rand.
float feld(float t, float anteil) {
	float lo = (1.0 - anteil) * 0.5;
	float hi = 1.0 - lo;
	// Weiche Kanten, sonst wird das Raster aus der Ferne zu Moire.
	return smoothstep(lo, lo + 0.10, t) * (1.0 - smoothstep(hi - 0.10, hi, t));
}

void fragment() {
	// sRGB -> LINEAR: set_color() liefert sRGB, ALBEDO erwartet linear. Dieselbe
	// Umrechnung wie im Gelaende-Shader.
	vec3 c = COLOR.rgb;
	vec3 lin = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));

	// Nur an senkrechten Flaechen — ein Dach mit Fensterachsen waere sofort als Fehler
	// zu sehen. Der Anteil kommt aus der Normalen, nicht aus einer zweiten Zuweisung.
	float senkrecht = 1.0 - abs(wnorm.y);
	float h = welt.y - boden;

	// --- FASSADENART UND MASSSTAB AUS DEM ALPHAKANAL --------------------------------
	//
	// WOZU. Ein einziges Raster fuer alle Haeuser sieht nach zwei Minuten aus wie
	// kariertes Papier — dieselbe Falle wie vorher bei den Querstreifen, nur feiner
	// gewebt. Echte Hochhaeuser sprechen wenige, deutlich verschiedene Fassadensprachen:
	// die einen ziehen durchgehende SENKRECHTE Baender und wirken dadurch hoch, die
	// anderen setzen einzelne LOECHER in eine Wand, die dritten legen waagerechte
	// BAENDER um das Haus. Nebeneinander erkennt man sie sofort auseinander.
	//
	// WARUM IM ALPHAKANAL. Art und Massstab muessen JE TURM verschieden sein, aber alle
	// Tuerme teilen sich ein Netz und damit ein Material — ein Uniform kann es also nicht
	// sein, ohne das Netz in hundertdreissig Teile zu zerlegen. Die Scheitelfarbe faehrt
	// dagegen ohnehin je Flaeche mit, und ihr Alphakanal war frei.
	//
	// Ueber 0.94 heisst "glattes Bauteil": Bruecken, Masten, Technikaufbauten. Sie haben
	// den Vorgabewert 1.0 und bekommen dadurch von selbst keine Fenster — was richtig
	// ist, denn ein Aufzugskopf mit Fensterachsen waere Unsinn.
	float typ = COLOR.a;
	float schmuck = step(typ, 0.94);
	// 0.98 IST EIN LEUCHTBAND. Die Kronenbaender der Tuerme brauchen Eigenleuchten, aber
	// kein eigenes Netz: sie liegen mitten in der Turmgeometrie, und ein zweites Mesh
	// dafuer waere ein zweiter Zeichenaufruf fuer je zwei Ringe. Der Alphakanal hatte
	// ueber der Fassadengrenze noch Platz. 1.0 (der Vorgabewert glatter Bauteile) faellt
	// ausdruecklich NICHT darunter — daher die obere Schranke.
	float neon = step(0.96, typ) * step(typ, 0.995);
	float e = typ * 3.2;
	float art = floor(e);
	float sk = fract(e);
	float ge = geschoss * mix(0.72, 1.30, sk);
	float ac = achse * mix(0.68, 1.55, sk);

	// Die Koordinate ENTLANG der Wand: zeigt die Normale nach x, laeuft die Wand in z.
	float u = mix(welt.x, welt.z, step(0.5, abs(wnorm.x)));
	float g = feld(fract(h / ge), glasanteil);
	float a = feld(fract(u / ac), glasanteil);

	// 0 SENKRECHTE BAENDER: durchgehende Glasstreifen, nur senkrecht geteilt. Der breite
	//   Glasanteil laesst schmale Pfosten stehen — das ist es, was den Turm hoch macht.
	// 1 LOCHFASSADE: das Kreuz aus beiden Richtungen.
	// 2 WAAGERECHTE BAENDER: Fensterbaender mit hoher Bruestung. Zwei Korrekturen gegen
	//   den Kordsamt-Eindruck, den die allererste Fassung dieses Shaders hatte: der
	//   Glasanteil ist auf 0.34 herunter (0.46 las sich im Bild immer noch als Streifen
	//   halb/halb statt als Fensterband mit Bruestung), und das Band ist nicht mehr
	//   voellig durchgehend — alle paar Achsen steht ein Pfosten. Ein Fensterband OHNE
	//   jede senkrechte Unterbrechung ist der Unterschied zwischen einem Haus und einem
	//   gestreiften Pullover.
	float r0 = feld(fract(u / ac), 0.76);
	float r1 = g * a;
	float r2 = feld(fract(h / ge), 0.34) * feld(fract(u / (ac * 3.0)), 0.88);
	float raster = mix(mix(r0, r1, step(0.5, art)), r2, step(1.5, art));

	// SOCKEL: hohe Erdgeschosse ohne Achsraster, dunkler. Darueber blendet er aus.
	float ist_sockel = 1.0 - smoothstep(sockel_h - 3.0, sockel_h, h);
	float sockelglas = feld(fract(h / (sockel_h * 0.5)), 0.72) * a;
	raster = mix(raster, sockelglas, ist_sockel);

	float f = raster * senkrecht * schmuck;
	vec3 wand = mix(lin, lin * 0.78, ist_sockel * 0.8);
	ALBEDO = mix(wand, glas, f * 0.86);
	// Schwaches Eigenleuchten: Glas spiegelt den Himmel und waere sonst ein totes
	// schwarzes Feld, sobald die Fassade im Schatten liegt.
	ALBEDO = mix(ALBEDO, lin, neon);
	EMISSION = mix(glas * f * 0.20, lin * 2.4, neon);
	ROUGHNESS = mix(mix(0.88, 0.22, f), 0.4, neon);
	METALLIC = f * 0.30 * (1.0 - neon);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("boden", boden)
	return m
