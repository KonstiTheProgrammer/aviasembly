## VULKAN IN ZAHLEN — was man dem Bild nicht ansieht.
##
## Ein Render zeigt, ob der Kegel gut aussieht; er zeigt nicht, ob die Boeschung wirklich
## im Bereich eines Schichtvulkans liegt, ob der Kraterrand HOEHER steht als die Flanke
## darunter (sonst ist es eine Delle und kein Krater) und wie tief die Scharte einschneidet.
## Seit der Kegel auch eine HAUT hat, misst das Werkzeug ausserdem die beiden Rauschlagen,
## auf denen Glut und Lavazungen sitzen, und wie viel Flaeche sie am Ende bedecken — die
## Schwellen dafuer sind nach Gefuehl nicht zu treffen (siehe _haut_messen).
##
## Godot --headless --path . --script res://tools/_vulkan_form.gd
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var vk: Dictionary = {}
	for ms in tw.massifs:
		if String(ms.get("type", "")) == "vulkan":
			vk = ms
			break
	if vk.is_empty():
		print("KEIN VULKAN IN DER MASSIVTABELLE")
		quit()
		return true
	var p: Vector3 = vk["pos"]
	var mr := float(vk["r"])
	print("Vulkan bei (%.0f, %.0f), r = %.0f, peak = %.0f" % [p.x, p.z, mr, float(vk["peak"])])

	# --- RADIALES PROFIL, ueber acht Richtungen gemittelt --------------------------------
	print("\n=== FLANKE (Mittel ueber 8 Richtungen) ===")
	print(" Abstand   Hoehe    Neigung zum vorigen Punkt")
	var vorh := 0.0
	var gipfel := -9e9
	for i in range(0, 27):
		var d := float(i) * 50.0
		var sum := 0.0
		for k in 8:
			var a := float(k) * TAU / 8.0
			sum += tw.height_at(p.x + cos(a) * d, p.z + sin(a) * d)
		var hm := sum / 8.0
		gipfel = maxf(gipfel, hm)
		var grad := 0.0 if i == 0 else rad_to_deg(atan2(absf(hm - vorh), 50.0))
		print("  %5.0f m  %6.1f m   %5.1f Grad" % [d, hm, grad])
		vorh = hm
	print("Mittlere Boeschung peak/r: %.1f Grad" % rad_to_deg(atan2(float(vk["peak"]), mr)))

	# --- KRATERRAND: liegt er hoeher als die Flanke darunter? ----------------------------
	print("\n=== KRATERSCHNITT je Richtung (Rand, Flanke 250 m darunter, Boden) ===")
	print(" Winkel   Randhoehe  Rand-r   Flanke aussen   Ueberhoehung   Kraterboden")
	var tiefsten := 9e9
	for k in 16:
		var a := float(k) * TAU / 16.0
		var ca := cos(a)
		var sa := sin(a)
		var rand_h := -9e9
		var rand_r := 0.0
		for i in range(0, 90):
			var d := float(i) * 8.0
			var hh := tw.height_at(p.x + ca * d, p.z + sa * d)
			if hh > rand_h:
				rand_h = hh
				rand_r = d
		var aussen := tw.height_at(p.x + ca * (rand_r + 250.0), p.z + sa * (rand_r + 250.0))
		var boden := tw.height_at(p.x + ca * rand_r * 0.25, p.z + sa * rand_r * 0.25)
		tiefsten = minf(tiefsten, rand_h)
		print(" %5.0f Grad  %7.1f m  %5.0f m  %10.1f m  %11.1f m  %10.1f m"
			% [rad_to_deg(a), rand_h, rand_r, aussen, rand_h - aussen, boden])
	print("Niedrigster Punkt der Lippe: %.1f m (Scharte)" % tiefsten)
	print("Gipfel (Mittel): %.1f m" % gipfel)

	# --- SCHLOTSOHLE GEGEN DIE BAUMGRENZE ------------------------------------------------
	# Der Krater ist die einzige Stelle des Gipfels, an der das Gelaende wieder FAELLT. Wird
	# der Schlot zu tief, taucht seine Sohle unter FLORA_MAX_H — und dann steht als einziger
	# Bewuchs weit und breit ein Waeldchen im Schlot. Das faellt in keinem Hoehenprofil auf,
	# deshalb steht die Probe hier: tiefster Punkt im Krater und der groesste Waldanteil,
	# den die Welt dort ueberhaupt zulassen wuerde.
	var tiefster := 9e9
	var wald := 0.0
	for i in range(-30, 31):
		for k in range(-30, 31):
			var px := p.x + float(i) * 10.0
			var pz := p.z + float(k) * 10.0
			var hh := tw.height_at(px, pz)
			tiefster = minf(tiefster, hh)
			wald = maxf(wald, tw.wald_anteil(px, pz, hh, 1.0))
	print("\n=== KRATERINNERES (300 m um die Achse) ===")
	print("Tiefster Punkt: %.1f m  (Baumgrenze %.0f m)" % [tiefster, TerrainWorld.FLORA_MAX_H])
	print("Groesster Waldanteil dort: %.4f  (muss 0 sein)" % wald)

	# --- RIPPEN: Streuung quer zum Hang --------------------------------------------------
	print("\n=== RIPPEN: Hoehenstreuung auf einem Ring (soll deutlich > 0 sein) ===")
	for d in [500.0, 700.0, 900.0, 1100.0]:
		var lo := 9e9
		var hi := -9e9
		for k in 180:
			var a := float(k) * TAU / 180.0
			var hh := tw.height_at(p.x + cos(a) * d, p.z + sin(a) * d)
			lo = minf(lo, hh)
			hi = maxf(hi, hh)
		print("  r = %4.0f m: %6.1f .. %6.1f m  (Spanne %5.1f m)" % [d, lo, hi, hi - lo])

	_barrancos_messen(tw, vk)

	# --- HAUT: GESTEIN, ZUNGEN, GLUT -----------------------------------------------------
	# WOFUER DIESER TEIL DA IST: alle Schwellen der Haut sitzen auf dem Ridged-Rauschen, und
	# dessen Werte sind NICHT um null verteilt. Wer sie (VULKAN_GRAT_AB / _VOLL,
	# VULKAN_GLUT_AB / _VOLL, VULKAN_ADER_AB / _VOLL, VULKAN_KRUME_MITTE) nach Gefuehl setzt,
	# bekommt entweder einen komplett gluehenden Berg oder gar nichts — beides ist im Render
	# erst nach anderthalb Minuten zu sehen. Hier stehen die Zahlen in Sekunden.
	# ABGETASTET WIRD UNTEN DER RIPPENKREIS. Glut und Ader lesen dasselbe Rauschen auf
	# anderen Kreisen (fest statt mitwachsend, weniger Lappen); die VERTEILUNG ist deshalb
	# dieselbe Familie und taugt weiter als Richtwert fuer ihre Schwellen — der gemessene
	# FLAECHENANTEIL weiter unten ist die Probe, die wirklich zaehlt.
	_haut_messen(tw, vk)
	_saum_messen(tw, vk)
	_netz_messen(tw, vk)
	quit()
	return true


## DER WALDSAUM AM FUSS — IST ES EIN KRAGEN ODER SIND ES INSELN?
##
## WOFUER DIESE PROBE, OBWOHL _haut_messen SCHON "Hoechster Baum" UND "Bewaldeter Anteil"
## DRUCKT: beide Zahlen koennen gut aussehen, waehrend das Bild trotzdem keinen Waldrand
## zeigt. Ein Kragen, der auf einem Drittel des Umfangs geschlossen steht und auf zwei
## Dritteln fehlt, hat denselben Flaechenanteil wie ein rundum halbdichter Schleier — und
## nur der erste Fall liest sich als Grenze. Gemessen wird deshalb JE RICHTUNG:
##   OBERKANTE  die hoechste Stelle mit nennenswertem Wald (die Baumgrenze, wie sie im Bild
##              steht, nicht wie sie in der Konstanten steht),
##   DECKUNG    der mittlere Waldanteil im Kragenband zwischen Fussschwelle und Baumgrenze
##              — er ist die Zahl fuer "dicht" und war der eigentliche Mangel,
##   BAND       ueber wie viele Hoehenmeter der Uebergang von voll auf null laeuft. Ein
##              Waldrand sind wenige Dutzend Meter, ein Verlauf ueber hundert ist keiner.
## Darunter die Streuung der Oberkante ueber alle Richtungen: sie sagt, ob die Grenze
## umlaeuft oder ob sie stellenweise den halben Hang hinaufkriecht.
func _saum_messen(tw: TerrainWorld, vk: Dictionary) -> void:
	var p: Vector3 = vk["pos"]
	var mr := float(vk["r"])
	print("\n=== WALDSAUM AM VULKANFUSS (32 Richtungen) ===")
	print("  (Deckung = mittlerer Waldanteil UNTER der Baumgrenze, also im geschlossenen Teil")
	print("   %.0f..%.0f m — nur der sagt, ob der Kragen dicht ist; ueber VULKAN_BAUM_AB"
		% [TerrainWorld.VULKAN_HAUT_FUSS, TerrainWorld.VULKAN_BAUM_AB])
	print("   soll er ja gerade ausblenden. Band = Hoehenmeter zwischen Deckung 0.75 und 0.10.")
	print("   ABGETASTET WIRD DER KEGEL UND SEINE SCHUERZE: bis 1.02 * r ohne, bis an den")
	print("   Saum der Schuerze mit. DAS IST KEINE BEQUEMLICHKEIT — das Kragenband liegt in")
	print("   einer HOEHENLAGE (26 bis 44 m), und die ist mit der Schuerze nach aussen")
	print("   gewandert: ohne sie am Kegelfuss, mit ihr bei rund 1.15 bis 1.28 * r. Mit der")
	print("   alten festen Schranke 1.02 lief der Strahl gar nicht mehr durch das Band und")
	print("   die Probe meldete einen tadellosen Kragen als vollstaendig fehlend.)")
	var oberkanten: Array[float] = []
	var deckungen: Array[float] = []
	var baender: Array[float] = []
	# ZWEI SORTEN LUECKE, und sie bedeuten Gegenteiliges. Eine Richtung ohne Wald ist nur dann
	# ein Loch im Kragen, wenn dort auch nichts liegt, das ihn verdraengt: auf einem erstarrten
	# Lavaband SOLL keiner stehen (siehe vulkan_bewuchs), das ist die Verzahnung von Gruen und
	# Schwarz, um die es geht. Ohne diese Unterscheidung meldet die Probe genau die Stellen als
	# Mangel, die richtig sind.
	# DIE ASCHESCHUERZE GEHOERT SEIT IHRER EINFUEHRUNG IN DIESELBE KATEGORIE, und ohne sie
	# stand die Probe kopf: sie meldete 9 von 32 Richtungen als "echtes Loch", waehrend im
	# Bild an genau diesen Stellen ein sauberer Waldrand gegen schwarze Asche stand. Die
	# Asche ist die Verdraengung, um die diese Runde ausdruecklich gebeten hat ("Ascheboden-
	# und Lavazungen sollen die Baumgrenze unregelmaessig aufreissen") — sie als Mangel zu
	# zaehlen hiesse, das Ziel als Fehler zu melden.
	# GEMESSEN WIRD SIE ALS 1 - vulkan_bewuchs UND NICHT MIT EINER EIGENEN ABFRAGE: das ist
	# genau die Maske, mit der die Bepflanzung arbeitet, und im Band unter VULKAN_BAUM_AB ist
	# die Baumgrenze selbst noch eins — was dort fehlt, fehlt also wegen Asche oder Lava.
	var luecken := 0
	var luecken_lava := 0
	for k in 32:
		var a := float(k) * TAU / 32.0
		var ca := cos(a)
		var sa := sin(a)
		# Radial nach innen laufen und Hoehe gegen Waldanteil auftragen.
		var oben := -9e9
		var summe := 0.0
		var n := 0
		var strom_bahn := 0.0
		var asche_bahn := 0.0
		var h_voll := -9e9
		var h_leer := -9e9
		# 3 m Schritt und nicht 6: am Fuss liegen die Lavalappen als Bloecke, und ueber eine
		# solche Stufe sprang der grobe Schritt schon einmal ganz ueber das Kragenband hinweg —
		# die Probe meldete dann "Deckung 0.00", wo in Wahrheit gar nicht gemessen wurde.
		# DIE HOEHE AM ANFANG DES STRAHLS WIRD MITGEFUEHRT, weil "0 Proben" zwei Ursachen hat
		# und nur eine davon den Kegel betrifft: in einigen Richtungen (gemessen 180 bis 202
		# Grad) stoesst der Fuss an eine hoehere Nachbarkuppe der Insel, das Gelaende steht dort
		# schon am Fussradius ueber der Baumgrenze und der Strahl kreuzt das Kragenband gar
		# nicht mehr. Ohne diese Zahl liest sich das wie ein Loch im Kragen.
		var h_start := 0.0
		# Aussenpunkt des Strahls: der Saum der Schuerze, sonst wie bisher 1.02 * r.
		var d_aussen := mr * 1.02
		if float(vk.get("apron", 0.0)) > 0.0:
			d_aussen = mr * TerrainWorld.VULKAN_APRON_WEIT
		for i in range(0, 700):
			var d := d_aussen - float(i) * 3.0
			if d < mr * 0.10:
				break
			var x := p.x + ca * d
			var z := p.z + sa * d
			var h := tw.height_at(x, z)
			if i == 0:
				h_start = h
			if h <= TerrainWorld.VULKAN_HAUT_FUSS or h > TerrainWorld.VULKAN_BAUM_AUS + 60.0:
				continue
			var w := tw.wald_anteil(x, z, h, 0.94)
			if h <= TerrainWorld.VULKAN_BAUM_AB:
				summe += w
				n += 1
				strom_bahn = maxf(strom_bahn, tw.vulkan_strom_bei(x, z))
				asche_bahn = maxf(asche_bahn, 1.0 - tw.vulkan_bewuchs(x, z, h))
			if w > 0.05:
				oben = maxf(oben, h)
			if w >= 0.75:
				h_voll = maxf(h_voll, h)
			if w <= 0.10 and h_leer < 0.0:
				h_leer = h
			elif w > 0.10:
				h_leer = -9e9
		var deck := summe / maxf(float(n), 1.0)
		if n > 0:
			deckungen.append(deck)
		if oben > -9e8:
			oberkanten.append(oben)
		elif n == 0:
			pass          # nichts gemessen (Lappenstufe im Band) — kein Befund
		elif strom_bahn > 0.5 or asche_bahn > 0.5:
			luecken_lava += 1
		else:
			luecken += 1
		var band := 0.0
		if h_voll > -9e8 and oben > -9e8 and oben > h_voll:
			band = oben - h_voll
			baender.append(band)
		var anm := ""
		if asche_bahn > 0.5:
			anm = ", Asche"
		if strom_bahn > 0.5:
			anm = ", Lavaband"
		if n == 0:
			anm = ", Fuss auf %.0f m — Nachbarkuppe, kein Kragenband auf dem Strahl" % h_start
		print("  %5.0f Grad   Oberkante %6s   Deckung %s   Band %5.0f m   (%d Proben%s)"
			% [rad_to_deg(a), ("%.0f m" % oben) if oben > -9e8 else "—",
				("%.2f" % deck) if n > 0 else "  —", band, n, anm])
	oberkanten.sort()
	deckungen.sort()
	baender.sort()
	if not oberkanten.is_empty():
		print("Oberkante: tiefste %.0f m   Median %.0f m   hoechste %.0f m   Spanne %.0f m"
			% [oberkanten[0], oberkanten[oberkanten.size() / 2],
				oberkanten[oberkanten.size() - 1],
				oberkanten[oberkanten.size() - 1] - oberkanten[0]])
	print("Richtungen ganz ohne Wald: %d echte Loecher, %d auf einem Lavaband (von 32)"
		% [luecken, luecken_lava])
	print("  (Nur die ersten sind ein Mangel. Die zweiten sind die Verzahnung von Gruen und")
	print("   Schwarz am Fuss, die die Vorlage ebenso zeigt.)")
	var ds := 0.0
	for w in deckungen:
		ds += w
	print("Deckung im Kragenband: min %.2f   Median %.2f   Mittel %.2f   max %.2f"
		% [deckungen[0], deckungen[deckungen.size() / 2], ds / float(deckungen.size()),
			deckungen[deckungen.size() - 1]])
	if not baender.is_empty():
		print("Uebergangsband: Median %.0f m   breitestes %.0f m  (schmal ist gut)"
			% [baender[baender.size() / 2], baender[baender.size() - 1]])
	# WELCHES BIOM LIEGT UEBERHAUPT AM FUSS? Die Weltregel duennt die Wueste auf ein
	# Zwanzigstel aus und sperrt dort ausserdem alles ueber 28 m — in einem Wuestensektor
	# kann der Kragen also gar nicht stehen, ganz gleich was die Vulkanschranke sagt.
	var zahl := [0, 0, 0, 0]
	for k in 64:
		var a := float(k) * TAU / 64.0
		zahl[tw.biome_at(p.x + cos(a) * mr * 1.05, p.z + sin(a) * mr * 1.05)] += 1
	print("Biom am Fussring (64 Richtungen): WALD %d   HEIDE %d   WUESTE %d"
		% [zahl[TerrainWorld.Biome.WALD], zahl[TerrainWorld.Biome.HEIDE],
			zahl[TerrainWorld.Biome.WUESTE]])


## DIE BARRANCOS IN ZAHLEN — ZAEHLT MAN SIE, ODER SIEHT MAN NUR RAUSCHEN?
##
## WOFUER ES DIESE PROBE BRAUCHT, OBWOHL DARUEBER SCHON EINE "RIPPEN"-ZEILE STEHT: die misst
## die Spanne hoch minus tief auf einem Ring, und die war die ganze Zeit ueber 170 m — auch
## als ein fremder Blick auf dem fertigen Bild "glatter Kegel ohne Rippen/Rinnen-System"
## gemeldet hat. Der Grund ist, dass in dieser Spanne alles zusammenfaellt, was den Ring
## unrund macht: der gebrochene Fussradius ("fuss" zieht ihn winkelabhaengig um bis zu elf
## Prozent nach innen, das sind allein schon ueber hundert Meter Hoehe), die Lavakanaele,
## die Rippen. Eine Zahl, die auch dann gross ist, wenn die Rinnen fehlen, taugt nicht als
## Abnahme.
##
## GEZAEHLT WIRD DESHALB DIE ZAHL DER RINNEN, und zwar an der Form selbst: Ring abtasten,
## den langwelligen Anteil abziehen (gleitendes Mittel ueber DREI Rinnenbreiten — das laesst
## die Rinne stehen und nimmt Fussradius und Rippenlappen heraus), dann die Taeler zaehlen,
## die tiefer als die Schwelle sind. Herauskommen muessen rund VULKAN_BARR_N Stueck; deutlich
## weniger heisst, dass die Rinnen im Rauschen ersaufen, deutlich mehr, dass das Rauschen
## selbst gezaehlt wird.
## Die zweite Zahl ist die mittlere Tiefe Grat gegen Sohle. Sie ist die, die im Bild ueber
## den Schlagschatten entscheidet, und sie soll nach aussen hin NICHT einbrechen — der
## Kritikpunkt lautete "ueber die GANZE Flanke".
func _barrancos_messen(tw: TerrainWorld, vk: Dictionary) -> void:
	var p: Vector3 = vk["pos"]
	var mr := float(vk["r"])
	var n_barr := int(TerrainWorld.VULKAN_BARR_N)
	print("\n=== BARRANCOS: ZAEHLBARE RINNEN AUF DEM RING (Soll %d) ===" % n_barr)
	print("  (Langwelliges abgezogen: gleitendes Mittel ueber drei Rinnenbreiten.)")
	print(" Abstand   Rinnen   mittlere Tiefe Grat/Sohle   Rinnenbreite")
	var n := 1440
	# Fenster des gleitenden Mittels: drei Rinnenbreiten, auf ungerade gerundet.
	var win := int(round(3.0 * float(n) / float(n_barr))) | 1
	for d: float in [0.45, 0.60, 0.72, 0.85, 0.95]:
		var r := mr * d
		var hs: Array[float] = []
		for k in n:
			var a := float(k) * TAU / float(n)
			hs.append(tw.height_at(p.x + cos(a) * r, p.z + sin(a) * r))
		# Hochpass: Wert minus gleitendes Mittel, zyklisch.
		var hp: Array[float] = []
		for k in n:
			var s := 0.0
			for j in range(-(win / 2), win / 2 + 1):
				s += hs[posmod(k + j, n)]
			hp.append(hs[k] - s / float(win))
		# Taeler zaehlen: ein Tal gilt, sobald das Signal unter -schwelle faellt und
		# danach wieder ueber +schwelle steigt. Die Hysterese ist der Grund fuer die
		# beiden Schwellen — ohne sie zaehlt jedes Dreieck am Nulldurchgang mit.
		var schwelle := 4.0
		var tief := false
		var rinnen := 0
		var summe := 0.0
		var lo := 0.0
		var hi := 0.0
		for k in n * 2:
			var v: float = hp[k % n]
			if v < -schwelle and not tief:
				tief = true
				lo = v
			elif v > schwelle and tief:
				tief = false
				if k >= n:
					rinnen += 1
					summe += hi - lo
				hi = v
			if tief:
				lo = minf(lo, v)
			else:
				hi = maxf(hi, v)
		print("  %4.2f * r (%4.0f m)   %4d      %6.1f m                %5.0f m"
			% [d, r, rinnen, summe / maxf(float(rinnen), 1.0), TAU * r / float(n_barr)])


## DAS LAVANETZ IN ZAHLEN.
##
## WOFUER: an diesem Netz sind zwei Anlaeufe gescheitert, und beide Male hat erst ein
## fremder Blick auf das fertige Bild den Mangel benannt — "acht gerade, parallele,
## unverzweigte Baender, die auf halber Flanke ohne Abschluss enden". Jede einzelne dieser
## vier Eigenschaften ist eine ZAHL, und keine davon stand irgendwo:
##   Wie viele Adern kreuzt ein Ring? (soll nach unten hin MEHR werden — das ist das
##   Verzweigen, und nur so ist es zu belegen.)
##   Wie breit ist eine? (soll nach unten hin schmaler werden.)
##   Wie weit unten glueht die letzte? (soll bis an den Waldrand reichen.)
##   Wie heiss ist sie dort? (soll oben orange und unten tiefrot sein.)
func _netz_messen(tw: TerrainWorld, vk: Dictionary) -> void:
	var p: Vector3 = vk["pos"]
	var mr := float(vk["r"])
	print("\n=== LAVANETZ: ADERN JE RING ===")
	print("  (Adern soll nach aussen ZUNEHMEN — acht Staemme, zwei Gabelungen, 32 Enden.")
	print("   Breite soll ABNEHMEN. Glut ist der hellste Wert auf dem Ring, 0 bis 1.)")
	print(" Abstand   Adern   mittlere Breite   Anteil   staerkste Glut   Farbe dort")
	for d: float in [520.0, 640.0, 760.0, 880.0, 1000.0, 1120.0]:
		var n_probe := 2880
		var offen := 0
		var kanten := 0
		var vorher := false
		var maxg := 0.0
		var maxc := Color.BLACK
		for k in n_probe:
			var a := float(k) * TAU / float(n_probe)
			var x := p.x + cos(a) * d
			var z := p.z + sin(a) * d
			var h := tw.height_at(x, z)
			var c := tw._face_color(Vector3(x, h, z), 0.86)
			var g := 1.0 - c.a
			if g > maxg:
				maxg = g
				maxc = c
			var an := g > 0.10
			if an:
				offen += 1
			if an and not vorher:
				kanten += 1
			vorher = an
		var bogen := TAU * d / float(n_probe)
		print("  %5.0f m   %5d   %9.0f m      %4.1f %%      %.2f     %.2f %.2f %.2f"
			% [d, kanten, (float(offen) * bogen) / maxf(float(kanten), 1.0),
				100.0 * float(offen) / float(n_probe), maxg, maxc.r, maxc.g, maxc.b])

	# --- WIE WEIT UNTEN ENDET DAS NETZ? -------------------------------------------------
	# HIER STAND EIN STRAHL JE RICHTUNG, und das war die falsche Messung: eine Ader wandert
	# beim Gabeln seitwaerts aus, ein Strahl bei festem Winkel folgt ihr also nicht, sondern
	# kreuzt sie und verliert sie wieder. Er meldete "Reichweite 0.54" fuer ein Netz, das der
	# Ringzaehler daneben bei 880 m noch mit 26 Adern fand.
	# Gezaehlt wird deshalb je SEKTOR (ein Zweiunddreissigstel des Umfangs, also gerade die
	# Breite, um die ein Ast beim Gabeln auswandern kann) die TIEFSTE Stelle, an der in ihm
	# noch etwas glueht. Das ist die Zahl, um die es geht: der Kritikpunkt lautete "endet auf
	# halber Flanke", und eine halbe Flanke sind hier rund 300 m ueber NN.
	print("\n=== LAVANETZ: WIE TIEF KOMMT DIE GLUT? (32 Sektoren) ===")
	var hoehen: Array[float] = []
	var kalt := 0
	for k in 32:
		var tief := 9e9
		for j in 12:
			var a := (float(k) + float(j) / 12.0) * TAU / 32.0
			var ca := cos(a)
			var sa := sin(a)
			for i in range(38, 116):
				var d := mr * float(i) / 100.0
				var x := p.x + ca * d
				var z := p.z + sa * d
				var h := tw.height_at(x, z)
				if h <= TerrainWorld.VULKAN_HAUT_FUSS:
					continue
				if (1.0 - tw._face_color(Vector3(x, h, z), 0.86).a) < 0.10:
					continue
				tief = minf(tief, h)
		if tief > 8e8:
			kalt += 1
			continue
		hoehen.append(tief)
	hoehen.sort()
	print("Sektoren ganz ohne Glut: %d von 32  (ein paar duerfen kalt sein)" % kalt)
	print("Unterste Glut im Sektor: Median %.0f m   tiefste %.0f m   hoechste %.0f m"
		% [hoehen[hoehen.size() / 2], hoehen[0], hoehen[hoehen.size() - 1]])
	print("  (Fussschwelle der Haut %.0f m, Waldrand des Kegels %.0f..%.0f m — dort soll das"
		% [TerrainWorld.VULKAN_HAUT_FUSS, TerrainWorld.VULKAN_BAUM_AB,
			TerrainWorld.VULKAN_BAUM_AUS])
	print("   Netz ankommen. Ueber 250 m heisst: es endet auf halber Flanke.)")

	# --- LAPPEN: DER ABSCHLUSS AM FUSS ---------------------------------------------------
	# Gemessen wird die Maske selbst und was sie am Gelaende bewirkt: eine Ader, die in
	# nichts ausläuft, liest sich als abgeschnitten. Der Lappen soll ERHABEN sein (2 bis 4
	# Bloecke), sonst ist er nur ein dunkler Fleck.
	print("\n=== LAVALAPPEN AM FUSS ===")
	var n_l := 0
	var n_ges := 0
	var hoch := 0.0
	for k in 720:
		var a := float(k) * TAU / 720.0
		var ca := cos(a)
		var sa := sin(a)
		for i in range(84, 106):
			var d := mr * float(i) / 100.0
			n_ges += 1
			var rn: Vector3 = tw._vulkan_rinne(ca, sa, d)
			var ad: Vector3 = tw._vulkan_ader(rn.z, d, mr, float(vk["crater_r"]))
			var lp: float = tw._vulkan_lappen(ad, d, mr)
			if lp < 0.5:
				continue
			n_l += 1
			hoch = maxf(hoch, lp * float(vk.get("lava_lappen", 0.0)))
	print("Anteil des Apron-Rings unter Lappen: %.1f %%  (ein geschlossener Kranz waere falsch)"
		% (100.0 * float(n_l) / maxf(float(n_ges), 1.0)))
	print("Groesste Auftragshoehe: %.0f m  (2 bis 4 Bloecke sind 16 bis 32 m)" % hoch)

	# --- SENKRECHTE WAENDE: DIE PROBE, DIE EIN BILD NICHT LIEFERT ------------------------
	# WOFUER: eine Maske, die irgendwo SPRINGT, statt zu blenden, wird im Hoehenfeld zu einer
	# senkrechten Wand — im Bild ein Lattenzaun aus einzelnen Dreiecken, und aus 2 km
	# Entfernung sieht der aus wie ein Schattenstreifen. Genau so ist an dieser Stelle schon
	# einmal ein Sprung uebersehen worden. Die Netzweite ist 8 m; alles ueber rund 20 m
	# Hoehenunterschied auf 4 m Grundriss steht praktisch senkrecht und ist ein Fehler,
	# keine Gelaendeform.
	print("\n=== SENKRECHTE WAENDE AUF DEM KEGEL (Sprung je 4 m Grundriss) ===")
	var sprung := 0.0
	var s_r := 0.0
	var s_a := 0.0
	for k in 900:
		var a := float(k) * TAU / 900.0
		var ca := cos(a)
		var sa := sin(a)
		var vor := tw.height_at(p.x + ca * mr * 0.30, p.z + sa * mr * 0.30)
		for i in range(1, 220):
			var d := mr * (0.30 + float(i) * 0.004)
			var h := tw.height_at(p.x + ca * d, p.z + sa * d)
			if absf(h - vor) > sprung:
				sprung = absf(h - vor)
				s_r = d / mr
				s_a = rad_to_deg(a)
			vor = h
	print("Groesster radialer Sprung: %.1f m bei %.2f * r, Richtung %.0f Grad" % [sprung, s_r, s_a])
	var sprung_q := 0.0
	var q_r := 0.0
	for i in range(30, 116):
		var d := mr * float(i) / 100.0
		var vor := tw.height_at(p.x + d, p.z)
		for k in range(1, 1801):
			var a := float(k) * TAU / 1800.0
			var h := tw.height_at(p.x + cos(a) * d, p.z + sin(a) * d)
			if absf(h - vor) > sprung_q:
				sprung_q = absf(h - vor)
				q_r = d / mr
			vor = h
	print("Groesster Sprung QUER dazu:  %.1f m bei %.2f * r  (Bogenschritt %.0f m)"
		% [sprung_q, q_r, TAU * mr * q_r / 1800.0])


## Verteilung der beiden Rauschlagen, auf denen die Vulkanhaut sitzt, und was die
## eingestellten Schwellen daraus machen. Abgetastet wird ein Raster ueber den ganzen
## Fussabdruck; gezaehlt wird nur, was ueber der Fussschwelle liegt.
func _haut_messen(tw: TerrainWorld, vk: Dictionary) -> void:
	var p: Vector3 = vk["pos"]
	var mr := float(vk["r"])
	var rip: Array[float] = []      # Rippenrauschen an der Stelle (dort sitzt die Glut)
	var fls: Array[float] = []      # Felslage (dort sitzt die Helligkeitskrume)
	var blk: Array[float] = []      # Blocklage (dort sitzen die Felsaufschluesse)
	# STEILE DER FERTIGEN FLAECHE. Sie ist die einzige Groesse der Haut, die nicht aus einer
	# Rauschlage kommt, sondern aus dem GEBAUTEN Gelaende — und genau deshalb muss sie
	# gemessen werden: VULKAN_STEIL_MITTE zentriert den Aufhellungsterm um seinen eigenen
	# Mittelwert, und ein falsch geratener Mittelwert hebt oder senkt die ganze Flanke.
	# Gerechnet wird die Normale aus einer zentralen Differenz ueber 8 m, also ueber genau
	# die Zellweite, mit der das Netz seine Facetten baut.
	var steil_summe := 0.0
	var steil_n := 0
	var n_kegel := 0
	var n_glut := 0.0
	var n_strom := 0.0
	var n_aussen := 0               # Proben JENSEITS des Fussradius (dort laufen Zungen)
	var n_aussen_strom := 0.0
	# HELLIGKEIT DER HAUT. Die Vorlage ist an dieser Zahl vermessen worden, und der Befund war
	# nicht "zu braun", sondern ZU FLAU: dort ist das oberste Zwanzigstel sechsmal so hell wie
	# der Median, bei uns war es knapp doppelt. Der Median steht fuer den Basalt, das obere
	# Ende fuer die abgeriebenen Gratruecken — faellt der Abstand zusammen, ist der Kegel
	# wieder ein Anstrich, ganz gleich welchen Ton er traegt.
	var lum: Array[float] = []
	# SCHNEEPROBE. Der Kegel steht auf 647 m Lippenhoehe, die Schneegrenze der Welt liegt bei
	# 188 m — nach der Weltregel muesste hier also die obere Haelfte weiss sein. Dass sie es
	# nicht ist, haengt an EINER Zeile in _face_color (die Haut kehrt zurueck, bevor Fels und
	# Schnee ueberhaupt drankommen), und eine Zusicherung, die an einer Zeile haengt, gehoert
	# nachgemessen. Gesucht ist die hellste Farbe oberhalb der Schneegrenze.
	var n_hoch := 0
	var hell := 0.0
	var hell_c := Color.BLACK
	# BAUMGRENZE DES KEGELS: bis wohin steht Wald, und wie breit ist der Rand. Ein Kragen ist
	# es, wenn der Wald unten geschlossen steht und der Uebergang schmal bleibt.
	var baum_max := -9e9
	var n_wald := 0
	for i in range(-88, 89):
		for k in range(-88, 89):
			var x := p.x + float(i) * 20.0
			var z := p.z + float(k) * 20.0
			var md := Vector2(x - p.x, z - p.z).length()
			if md > mr * TerrainWorld.VULKAN_HAUT_REICH or md < 1.0:
				continue
			var h := tw.height_at(x, z)
			if h < TerrainWorld.SEA_Y + 1.6:
				continue
			var ux := (x - p.x) / md
			var uz := (z - p.z) / md
			var strom := tw.vulkan_strom_bei(x, z)
			if md > mr:
				n_aussen += 1
				n_aussen_strom += strom
				continue
			if h <= TerrainWorld.VULKAN_HAUT_FUSS:
				continue
			n_kegel += 1
			n_strom += strom
			fls.append(tw._ridge.get_noise_2d(x * tw._vk_fels_takt, z * tw._vk_fels_takt))
			blk.append(tw._ridge.get_noise_2d(x * tw._vk_block_takt, z * tw._vk_block_takt))
			var gx := (tw.height_at(x + 4.0, z) - tw.height_at(x - 4.0, z)) / 8.0
			var gz := (tw.height_at(x, z + 4.0) - tw.height_at(x, z - 4.0)) / 8.0
			var nyf := 1.0 / sqrt(1.0 + gx * gx + gz * gz)
			steil_summe += smoothstep(TerrainWorld.VULKAN_STEIL_AB,
				TerrainWorld.VULKAN_STEIL_VOLL, nyf)
			steil_n += 1
			var rkr: float = tw._vk_rippen_kreis * sqrt(md / mr)
			rip.append(tw._ridge.get_noise_3d(ux * rkr, uz * rkr,
				md * TerrainWorld.VULKAN_RIPPEN_LAUF))
			# Die Farbe selbst: ihr Alphakanal IST die Glut (siehe TerrainWorld-Shader).
			# ny = 0.8 ist mit Absicht kein flacher Boden: genau bei diesem Wert stuende die
			# Weltregel mit halber Schneedeckung da, die Probe trifft die Zusicherung also.
			var c := tw._face_color(Vector3(x, h, z), 0.8)
			n_glut += 1.0 - c.a
			var l := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			lum.append(l)
			var w := tw.wald_anteil(x, z, h, 0.97)
			if w > 0.05:
				n_wald += 1
				baum_max = maxf(baum_max, h)
			if h > 188.0:
				n_hoch += 1
				if l > hell:
					hell = l
					hell_c = c
	rip.sort()
	fls.sort()
	blk.sort()
	lum.sort()
	print("\n=== HAUT: RAUSCHVERTEILUNG AUF DEM KEGEL (%d Proben) ===" % n_kegel)
	print(" Lage       min      2%       10%      Mittel    90%      98%      max")
	for eintrag in [["Rippen", rip], ["Felslage", fls], ["Blocklage", blk]]:
		var v: Array[float] = eintrag[1]
		if v.is_empty():
			continue
		var summe := 0.0
		for w in v:
			summe += w
		print(" %-9s %6.3f  %6.3f  %6.3f  %6.3f  %6.3f  %6.3f  %6.3f"
			% [eintrag[0], v[0], v[int(v.size() * 0.02)], v[int(v.size() * 0.10)],
				summe / float(v.size()), v[int(v.size() * 0.90)],
				v[int(v.size() * 0.98)], v[v.size() - 1]])
	print("VULKAN_KRUME_MITTE soll dem Mittel der Felslage entsprechen: %.2f"
		% TerrainWorld.VULKAN_KRUME_MITTE)
	print("VULKAN_BLOCK_AB/_VOLL (%.2f/%.2f) schneiden aus der Blocklage die Aufschluesse."
		% [TerrainWorld.VULKAN_BLOCK_AB, TerrainWorld.VULKAN_BLOCK_VOLL])
	if not blk.is_empty():
		var ueber := 0
		var voll := 0
		var bsum := 0.0
		for w in blk:
			if w > TerrainWorld.VULKAN_BLOCK_AB:
				ueber += 1
			if w > TerrainWorld.VULKAN_BLOCK_VOLL:
				voll += 1
			bsum += smoothstep(TerrainWorld.VULKAN_BLOCK_AB,
				TerrainWorld.VULKAN_BLOCK_VOLL, w)
		print("  Flaeche ueber AB: %.0f %%   ueber VOLL (voller Auswurf): %.1f %%   Mittel der Huelle: %.2f"
			% [100.0 * float(ueber) / float(blk.size()),
				100.0 * float(voll) / float(blk.size()), bsum / float(blk.size())])
		print("  (Ein Aufschlussfeld sind rund ein Drittel der Flaeche; steht 'ueber VOLL' bei")
		print("   null, erreicht KEIN Block seine volle Hoehe und die Lage koernt nur.)")
	print("\n=== STEILE: NEIGUNG DER FERTIGEN FACETTEN (%d Proben) ===" % steil_n)
	print("Mittel des Fensters %.2f..%.2f: %.3f   — VULKAN_STEIL_MITTE steht auf %.2f"
		% [TerrainWorld.VULKAN_STEIL_AB, TerrainWorld.VULKAN_STEIL_VOLL,
			steil_summe / maxf(float(steil_n), 1.0), TerrainWorld.VULKAN_STEIL_MITTE])
	print("(Beide muessen zusammenpassen: der Aufhellungsterm ist um diesen Mittelwert")
	print(" zentriert, damit die Steilkante aufhellt UND die flache Facette abdunkelt,")
	print(" ohne dass die Flanke im Mittel heller wird.)")
	if not lum.is_empty():
		var lmed: float = lum[int(lum.size() * 0.50)]
		print("\n=== HAUT: HELLIGKEIT DER GESTEINSFARBE ===")
		print(" 5%%: %.3f   25%%: %.3f   Median: %.3f   75%%: %.3f   95%%: %.3f   Spreizung 95/50: %.1f"
			% [lum[int(lum.size() * 0.05)], lum[int(lum.size() * 0.25)], lmed,
				lum[int(lum.size() * 0.75)], lum[int(lum.size() * 0.95)],
				lum[int(lum.size() * 0.95)] / maxf(lmed, 0.001)])
		print(" (In der Vorlage steht die Spreizung bei rund 3,3 — gemessen am fertigen Bild,")
		print("  hier an der Rohfarbe, also nur als Richtung zu lesen, nicht als Zielwert.)")
	print("\n=== SCHNEE UND BAUMGRENZE AUF DEM KEGEL ===")
	print("Proben ueber der Schneegrenze (188 m): %d" % n_hoch)
	print("Hellste Farbe dort: %.3f  (%.2f %.2f %.2f)  — Schnee waere ueber 0.7"
		% [hell, hell_c.r, hell_c.g, hell_c.b])
	print("Hoechster Baum: %.0f m  (Schranke %.0f..%.0f m, Welt: %.0f m)"
		% [baum_max, TerrainWorld.VULKAN_BAUM_AB, TerrainWorld.VULKAN_BAUM_AUS,
			TerrainWorld.FLORA_MAX_H])
	print("Bewaldeter Anteil des Kegels: %.1f %%" % (100.0 * float(n_wald) / maxf(float(n_kegel), 1.0)))
	print("\n=== HAUT: FLAECHENANTEILE ===")
	print("Glut auf dem Kegel:      %.1f %%  (Rinnen; ein paar Prozent sind richtig)"
		% (100.0 * n_glut / maxf(float(n_kegel), 1.0)))
	print("Lavazunge auf dem Kegel: %.1f %%" % (100.0 * n_strom / maxf(float(n_kegel), 1.0)))
	print("Lavazunge JENSEITS des Fusses: %.1f %% von %d Proben  (die Zungen in der Ebene)"
		% [100.0 * n_aussen_strom / maxf(float(n_aussen), 1.0), n_aussen])
	# WIE WEIT REICHT DIE EINZELNE ZUNGE? Der Flaechenanteil allein sagt das nicht: er kann
	# aus einem breiten Saum am Fuss kommen, und der liest sich im Bild als Schatten, nicht
	# als Strom. Gezaehlt wird deshalb je Richtung, wie weit draussen die Maske zuletzt ueber
	# der Haelfte steht, und wie dunkel die Flaeche dort wirklich wird.
	print("\n=== ZUNGEN JE RICHTUNG (Reichweite und Farbe am Ende) ===")
	print(" Winkel   letzte Stelle mit Zunge>0.5   Hoehe    Farbe dort")
	for k in 24:
		var a := float(k) * TAU / 24.0
		var weit := 0.0
		var wh := 0.0
		var wc := Color.BLACK
		for i in range(60, 132):
			var d := mr * float(i) / 100.0
			var x := p.x + cos(a) * d
			var z := p.z + sin(a) * d
			if tw.vulkan_strom_bei(x, z) < 0.5:
				continue
			var h := tw.height_at(x, z)
			if h < TerrainWorld.SEA_Y + 1.6:
				continue
			weit = d / mr
			wh = h
			wc = tw._face_color(Vector3(x, h, z), 0.95)
		if weit <= 0.0:
			print(" %5.0f Grad   —" % rad_to_deg(a))
			continue
		print(" %5.0f Grad   %.2f * r%s  %6.1f m   %.2f %.2f %.2f"
			% [rad_to_deg(a), weit, "  (ueber den Fuss hinaus)" if weit > 1.0 else "         ",
				wh, wc.r, wc.g, wc.b])
