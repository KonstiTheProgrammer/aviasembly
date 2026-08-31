## Main.gd
## Zentrale: Welt/Licht/Himmel, Modus-Umschaltung (Hangar <-> Flug),
## komplettes UI + HUD, Speichern/Laden und das Start-Flugzeug.
extends Node3D

enum Mode { BUILD, FLY }

const SAVE_PATH := "user://aircraft_design.json"   # Autoload: zuletzt gebautes/geladenes
var _design_dirty := false   # AUTOSAVE: Bauänderung seit letztem Schreiben? (2-s-Debounce)
var _autosave_t := 0.0
const SLOT_DIR := "user://hangar"                  # benannte eigene Speicher-Slots
const F_BOLD := preload("res://fonts/TitilliumWeb-Bold.ttf")   # fetter Schnitt für Überschriften
const F_SEMI := preload("res://fonts/TitilliumWeb-SemiBold.ttf")  # Standard-UI-Schnitt (crisp)

# Der Blueprint-Boden-Shader liegt jetzt als eigene Datei:
# res://shaders/blueprint_floor.gdshader (siehe ShowroomStage).

var mode: int = Mode.BUILD
var camera: Camera3D
var build_ctrl: BuildController
var flight_ctrl: FlightController

# SONNENSTAND (Grad, Euler XY). Gilt fuer das gerichtete Licht UND fuer die gemalte
# Sonne im Himmels-Shader — beide lasen den Wert frueher getrennt ab.
# SONNENSTAND — 26 GRAD STATT 50, UND DAS IST DIE GROESSTE EINZELNE AENDERUNG AM AUSSEHEN
# DER WELT.
#
# Bei 50 Grad steht die Sonne fast im Zenit. Der Unterschied zwischen einem Hang, der ihr
# zugewandt ist, und einem, der von ihr wegzeigt, ist dann klein — beide bekommen fast
# denselben Streifwinkel. Genau das war der Befund der Abnahme: "es gibt keine Sonne",
# kein Berg hat eine Licht- und eine Schattenseite, ein 400 px breites Massiv liegt von
# der linken bis zur rechten Flanke in einem einzigen Braunton da.
#
# Bei 26 Grad streift das Licht. Jede Kuppe bekommt eine helle und eine dunkle Seite,
# jeder Grat wirft einen langen Schatten ueber den Hang dahinter, und das Low-Poly-Facett
# bekommt endlich das, wovon es lebt: Kontrast zwischen benachbarten Flaechen.
const SONNE_WINKEL := Vector3(-26.0, -50.0, 0.0)

# Kamera-Fernebene im Flug. Steht hier, weil ausser der Kamera auch die Wolkendecke sie
# braucht: die Puffs muessen vorher ausgeblendet sein (siehe unten).
const KAMERA_FERN := 9000.0

# WOLKENDECKE: halbe Kantenlaenge des Wolkenfelds und zugleich die Entfernung, in der
# eine Wolke auf die Gegenseite umgeschlagen wird (CloudField.mitfuehren).
# 17170 ist KEIN Geschmackswert, sondern drei aufaddierte Groessen:
#   16503 m  am weitesten entfernte ECKE der Fernebene — NICHT die Fernebene selbst,
#            sonst sieht man das Umschlagen, sobald man schraeg zu den Weltachsen
#            fliegt (Herleitung in CloudField.mitfuehren). Gerechnet mit dem WEITESTEN
#            Sichtwinkel, den die Kamera je einnimmt: FlightController weitet sie mit
#            der Geschwindigkeit von FOV_BASE 64 auf FOV_MAX 74 Grad auf. Mit 64 Grad
#            kaeme man auf 14580 m — und saehe den Umschlag genau dann, wenn man schnell
#            fliegt. Ueber die Seitenverhaeltnisse liegt das Maximum bei 16:9. Der Zoom
#            (FOV_ZOOM 22) verengt nur; seine Transiente — zoom_t zieht mit 5/s an,
#            _cam_vfov folgt nur mit 2.5/s, waehrend der Kameraabstand waechst — wurde
#            mit 16541 m gemessen und liegt ebenfalls im Budget.
#   + 200 m  WOLKEN_PASS_WEG: so weit kann der Spieler geflogen sein, bevor eine
#            bestimmte Wolke wieder an der Reihe ist. Sie landet nach dem Umschlagen
#            nicht bei `area`, sondern bei `area` MINUS diesem Ueberschuss.
#   + 284 m  groesster Puff-Halbmesser, GEMESSEN ab dem Knotenursprung ueber alle vier
#            Wolkensorten (Kumulus ist der groesste). Hier stand vorher 207 m — das war
#            die halbe AABB-KANTE und damit zu klein, denn die Lappen sitzen ausserhalb
#            der Mesh-Mitte. Wer die Wolken vergroessert, MUSS diesen Wert neu messen:
#            die Sorte selbst kann wachsen, dieser Posten waechst mit.
# Der Versatz der Kamera hinter dem Flieger taucht hier bewusst NICHT auf: die Decke
# wird um die Kamera zentriert (siehe Aufrufstelle), nicht um das Flugzeug.
# Aufgerundet auf 51.5 * spacing (340 m), damit die Umschlagperiode 2*area genau 103
# Rasterspalten lang ist und die Decke ueber die Naht hinweg gleichmaessig bleibt.
# 16503 + 200 + 284 = 16987 waeren noetig; 17510 laesst 523 m Luft. Die vorige Fassung
# stand mit 17170 auf 183 m Rest — das reichte, war aber nach EINER Vergroesserung der
# Wolken schon fast aufgebraucht.
const WOLKEN_AREA := 17510.0
# Strecke, nach der jede Wolke einmal geprueft wurde. Der Durchlauf wird darueber verteilt
# statt auf einen Schlag gemacht — geht als Reserve in WOLKEN_AREA ein.
const WOLKEN_PASS_WEG := 200.0
# Welche Wolkensorten gebaut werden, von unten nach oben. Die Masse je Sorte (Hoehe,
# Raster, Haeufigkeit, Form) stehen in CloudField.TYPEN. Lage 0 ist die Kumulusdecke und
# bleibt unter cloud_field erreichbar.
const WOLKEN_LAGEN := ["kumulus", "turm", "schaefchen", "linse"]
# --- IN DER WOLKE ----------------------------------------------------------------------
# Wie stark sich die Sicht eintruebt, wenn man drinsteckt. Der Nebel ist im Freien
# bewusst hauchduenn (die Ferne SOLL lesbar sein); in der Wolke muss er auf Sichtweiten
# von wenigen Dutzend Metern gehen, sonst fliegt man durch eine Farbe statt durch Wetter.
# LUFTPERSPEKTIVE. 0.00006 ergab auf 3 km gerade 16 Prozent Eintruebung und auf 10 km
# 45 — im Bild ein schmaler heller Streifen direkt am Horizont und sonst nichts. Die
# Abnahme las das als "flaches Diorama von oben fotografiert, hintere Kante retuschiert".
# 0.00013 gibt auf 3 km 32 Prozent und auf 10 km 73: eine durchgehende Rampe statt eines
# Aufklebers, und damit liest sich nah gegen fern.
const NEBEL_FREI := 0.00013
const NEBEL_WOLKE := 0.020
# NEBELFARBE BEI FREIER SICHT. Sie stand auf 0.66/0.79/0.94, also Blau minus Rot = 0.28.
# Das ist die staerkste Einzelquelle des Blaustichs, der ueber der ganzen Karte liegt:
# gemessen hat der dunkle Basalt des Vulkans b-r = +0.208, waehrend die Vorlage bei +0.067
# steht. Der Nebel ist bei 3,5 km ein ADDITIVER Sockel von 0.254 Leuchtdichte (Schwarzprobe
# mit auf null gesetzten Gesteinsfarben) — er faerbt also nicht nur, er hellt auch auf, und
# beides zusammen laesst jedes ferne Gestein kalt und flau aussehen.
# 0.75/0.82/0.92 haelt b-r bei 0.17 — die Luftperspektive bleibt deutlich blau (sonst
# verliert die Ferne ihre Tiefe und der Horizont trennt sich vom Himmel), aber sie
# ueberfaerbt das Motiv nicht mehr.
const NEBEL_FARBE_FREI := Color(0.75, 0.82, 0.92)
const NEBEL_FARBE_WOLKE := Color(0.93, 0.95, 0.97)
# Kennlinie: erst tief in der Wolke wird es wirklich weiss. Linear waere die Sicht schon
# beim Streifen einer Kante halb zu, und das fuehlt sich falsch an.
const NEBEL_KURVE := 1.7

# --- FERNSCHUERZE (siehe _fernschuerze_starten) -------------------------------------
# Rasterweite der Fernlage. Die Chunks fahren 8 m; BEIDE Stufen sind Vielfache davon, das
# Gitter faellt also auf Chunk-Stuetzstellen und die Flaechen treffen sich dort exakt.
#
# ZWEI STUFEN, NACHEINANDER GEBAUT. Mit 64 m allein war das Land jenseits der Chunkgrenze
# eine glatte, strukturlose Masse: die Grate der Massive haben rund 230 m Wellenlaenge und
# werden von einem 64-m-Raster mit dreieinhalb Punkten je Welle abgetastet — sie
# verschwinden schlicht. Aus Reiseflughoehe war das der auffaelligste Bruch der Karte,
# weil die Chunks daneben jeden Grat zeigen.
# 32 m loest die Grate auf (gemessen: 1,92 Mio. statt 482 000 Dreiecke), braucht aber
# 17 bis 22 s statt 5 bis 6 — und so lange klaffte im Weltbild ein Loch.
# Deshalb baut _fern_bauen ERST grob und haengt das ein, DANN fein und tauscht. Der Spieler
# sieht nach rund fuenf Sekunden ein vollstaendiges Land und nach rund zwanzig ein feines;
# der Tausch faellt nicht auf, weil beide Stufen dieselbe Farbfunktion und dieselbe
# Absenkung fahren.
const FERN_ZELLE_GROB := 64.0
const FERN_ZELLE_FEIN := 32.0
# Kantenlaenge einer Schuerzen-Kachel (24 Zellen). Groesser = weniger Draw-Calls, aber
# groebere Sichtbarkeits-Auslese; 1536 m = vier Chunkbreiten hat sich als Mitte ergeben.
# GROESSER GEWORDEN (1536), UND ZWAR ABSICHTLICH IM GLEICHEN SCHRITT WIE DIE WELT.
# Die Kachelzahl ist (2 * ceil(FERN_WELT / FERN_KACHEL) + 1) im Quadrat. Bei 1536 m und
# 33 km Reichweite waeren das 2025 Kacheln statt bisher 961 — mehr als das Doppelte an
# Netzen und Zeichenaufrufen fuer dieselbe Aufgabe. Mit 2200 m bleibt es bei 961: jede
# Kachel deckt mehr Flaeche, die Aufloesung darin (FERN_ZELLE_*) bleibt unveraendert.
const FERN_KACHEL := 2200.0
# Halbe Kantenlaenge des abgesuchten Weltausschnitts. Muss den Kuestenradius aus
# TerrainWorld.height_at abdecken (18000 +- 2400, also bis 20,4 km) plus den Auslauf.
# Vorher standen hier 18500 fuer die kleinere Insel; die neue haette jenseits davon
# einfach aufgehoert.
# MIT DER INSEL GEWACHSEN (23000). Die Schuerze muss ueber die Kueste hinausreichen,
# sonst hoert die Welt sichtbar vor ihrem eigenen Rand auf.
# 35000 STATT 33000: das Sturmkap reicht bis 32,1 km hinaus (gemessen), die Schuerze
# haette es mit 900 m Rest gerade noch gedeckt. Zwei Kilometer Reserve sind der
# Unterschied zwischen 'passt gerade' und 'passt auch beim naechsten Umbau'.
const FERN_WELT := 35000.0
# Grundabsenkung im Ueberlappbereich. GEMESSEN an 40 000 Landproben: das echte 8-m-Gelaende
# liegt gegenueber der 64-m-Interpolation im schlechtesten Fall 44 m tiefer, aber schon
# bei 12 m sind 99,9 % erfasst. 14 m halten die Schuerze also praktisch ueberall unter
# den Chunks, ohne an der Naht eine dicke Stufe zu bauen (14 m sind in 3,5 km rund 2 px).
const FERN_BIAS := 14.0
# Tiefe der Nahfeld-Absenkung: mehr als der hoechste Berg (230 m), damit die grobe Lage
# im Nahbereich garantiert unter dem Boden verschwindet.
# Farbe, in die der Fernwald einfaerbt. Dunkler und kaelter als das Gras: ein Nadelwald
# aus der Entfernung ist praktisch ein dunkelgruener Filz, kein saftiges Gruen.
const FERN_WALD := Color(0.115, 0.235, 0.135)
const FERN_TIEF := 480.0
# Rampe der Nahfeld-Absenkung. FERN_FERN ist KEIN Geschmackswert, sondern die Grenze,
# bis zu der TerrainWorld garantiert Chunks stehen hat: es haelt Chunkmitten bis
# VIEW_DIST+CHUNK = 4184 m, davon halbe Chunkdiagonale (271 m) und die volle Zell-
# diagonale ab, die der Spieler seit dem letzten update_center zurueckgelegt haben
# kann (543 m) -> 3370 m. Darunter bleiben wir mit 3300 m.
# --- DAS HOCHTAL und der Flugplatz ADLERHORST darin ----------------------------------
# Ein KEILFOERMIGES Tal zwischen zwei Ketten, nicht mehr ein Sattel auf einem Grat. Alle
# Werte hier: die Talachse, an der beide Ketten und der Flugplatz haengen. Sie gehen an
# vier Stellen ein (beide Ketten, der Platz, seine Einebnungszone) — deshalb einmal.
const TAL_START := Vector2(-11000.0, -2500.0)
const TAL_RICHTUNG := Vector2(0.6139, -0.7893)
const TAL_LAENGE := 11400.0
# Abstand jeder Kette von der Talachse, VORN am Taleingang und HINTEN am Talschluss. Das
# Tal ist ein Keil, kein Kanal: dazwischen wird linear interpoliert (_tal_halbbreite).
# Urzustand: jedes Kettenmassiv hing am selben Wert 2700, die Kaemme liefen also exakt
# parallel; gemessene Talbodenbreite 1725 m bei 500, 1425 bei 3000, 1350 bei 6500,
# 1375 bei 8000, 875 bei 9500 — nach hinten eher weiter statt enger.
#
# DIE FALLE, IN DIE DIE ERSTE KEILFASSUNG GELAUFEN IST: sie stand auf 3600 / 2200 und kam
# damit auf ein Verhaeltnis von 1,94 : 1 — aber 94 Prozent davon waren AUFWEITEN VORN.
# Gemessen 3350 m Boden bei 500 m und 2550 bei 3000 statt 1725 / 1425; das Tal war an
# jeder Stelle bis 6500 m BREITER als der Urzustand, im Mittel 2042 statt 1350 m. Ein
# Keil, der durch Verbreitern entsteht, ist kein Keil. Die Verjuengung muss deshalb aus
# dem ZUSAMMENZIEHEN HINTEN kommen, und das Mittel muss unter dem Urzustand bleiben.
#
# WARUM DIESE ZWEI ZAHLEN. Der Talboden (Gelaende unter 200 m) endet nicht am Massiv-
# mittelpunkt, sondern rund 0,77 * r davor — bei r = 2200 also 1690 m weiter innen. Die
# halbe Bodenbreite ist damit etwa Halbbreite - 1690, reagiert also SEHR empfindlich:
# 100 m an der Halbbreite sind 200 m Boden.
# NACH UNTEN begrenzt der Talschluss. Gemessen (Reihe GEWACHSEN, also ohne Flachzonen)
# bleiben bei 8000 m noch 950 m Boden und bei 8500 m 875 m; ab 8800 m greift der Fuss der
# Querkette auf die Achse und der gewachsene Boden geht auf null. ADLERHORST steht damit
# ohnehin in einer Einebnung — aber das Vorfeld reicht quer bis x = 432 m (FP_RECHTECKE
# plus Bausatz), und je schmaler das gewachsene Tal dort ist, desto tiefer schneidet
# diese Einebnung. Bei 2110 und der jetzigen Zone (520/620) steht der gewachsene Fels an
# der Platzmitte auf 238 m und 100 m daneben auf 232 m — also 148 bzw. 142 m Aushub,
# gleich viel wie mit der alten, weiteren Zone. Deutlich enger als 2110 wuerde daraus ein
# Steinbruch neben der Bahn.
# NACH OBEN begrenzt der Urzustand: 2480 gibt vorn 1650 m Boden und bleibt damit unter
# den 1725 m von damals. Groesser waere wieder Aufweiten statt Verjuengen.
#
# WARUM 2480 / 2110 UND NICHT MEHR 2380 / 2030. Die vorige Fassung hatte die Verjuengung
# an der falschen Stelle: gemessen (tools/_krit_keil.gd) 1317 m Mittel vorn gegen 886 m
# hinten, aber der GANZE Abfall lag in den ersten 3,5 km. Ueber laengs 4000..8750 —
# 55 Prozent der Tallaenge und genau der Endanflug — stand der Boden bei 950 / 975 / 950 /
# 850 / 850 / 1025 m, also ein parallelwandiger Kanal mit einer Aufweitung am Schluss.
# Der Grund war nicht die Spanne, sondern ihre STEIGUNG: 350 m Halbbreite auf TAL_LAENGE
# 11400 verteilt sind 30,7 m je km, und davon wurden nur die ersten 81 Prozent ueberhaupt
# benutzt (siehe TAL_KEIL_LAENGE). Jetzt sind es 370 m auf 9200 m = 40,2 m je km, also
# 31 Prozent mehr Verjuengung je Kilometer, und sie laeuft bis zum Talschluss durch.
const TAL_BREITE := 2480.0
const TAL_BREITE_HINTEN := 2110.0
# UEBER WELCHE LAENGE der Keil interpoliert. NICHT TAL_LAENGE — das Tal ist laenger
# gerechnet als es existiert: gemessen endet der zusammenhaengende Talboden bei laengs
# 9250 m (725 m Boden), bei 9500 m greift der Fuss der Querkette auf die Achse und es
# gibt gar keinen Boden mehr. Mit TAL_LAENGE = 11400 als Nenner wurden nur 81 Prozent
# der Rampe je benutzt, am Talschluss stand 2096 statt 2030 m Halbbreite — 66 m
# Halbbreite oder rund 130 m Boden wurden verschenkt, und zwar genau dort, wo das Tal
# am engsten sein soll.
#
# WER DEN KEIL NACHMISST, FINDET BEI LAENGS 3500 EINEN EINBRUCH und darf ihn nicht fuer
# einen Messfehler halten: der Talboden geht dort von rund 700 auf 300 m herunter und bei
# 4000 m wieder auf 625 m hoch. Das ist die groesste Einzelunstetigkeit der ganzen Reihe,
# und sie gehoert NICHT zur Kette, sondern zum FELSENTOR — es ist der Fuss seiner
# Felsrippe (siehe _hochgebirge, "rippe"), die bei TOR_LAENGS = 3600 quer ins Tal
# hineinsteht. Sie soll dort sein: das Tor sitzt in einer Engstelle. Wer sie
# "wegoptimiert", nimmt dem Tor den Fels, in dem das Loch steckt.
const TAL_KEIL_LAENGE := 9200.0
# Radius der Kettenmassive und ihr Laengsabstand. Die beiden gehoeren zusammen: der
# Abstand ist die HAELFTE des Radius, und nur so wird aus der Kette ein durchgehender Grat
# statt einer Perlenschnur (Begruendung bei _hochgebirge).
# VON 2600 AUF 2200 HERUNTER. Der Radius ist der zweite Hebel neben der Halbbreite: bei
# gleicher Gipfelhoehe steht die Flanke steiler (1150 m auf 2200 statt auf 2600), und der
# Fuss liegt 310 m weiter innen, sodass dieselbe Halbbreite mehr freien Talboden laesst.
# Der alte Wert gab am Talquerschnitt bei 3000 m im Mittel 22 Grad Flankenneigung — bei
# 2500 m Bodenbreite davor liest sich das als Becken, nicht als Tal.
const TAL_KETTE_R := 2200.0
const TAL_KETTE_ABSTAND := 1100.0
# LAENGSVERSATZ DER BEIDEN KETTEN GEGENEINANDER — die halbe Massivteilung.
# WOGEGEN ER HILFT: die Kaemme sind aus Kegeln gebaut, der Talboden ist zwischen zwei
# Massiven also breiter als vor einem. Standen beide Ketten auf DENSELBEN Laengspositionen,
# addierten sich diese Ausbuchtungen zu einer Schwebung: gemessen 1575 / 1350 / 1525 /
# 1250 m Boden bei 500 / 1000 / 1500 / 2000 m — das Tal wurde auf dem Weg nach innen
# fuenfmal wieder breiter. Um eine halbe Teilung versetzt fallen die Ausbuchtungen der
# einen Seite auf die Engstellen der anderen: 1475 / 1425 / 1425 / 1300 m, und die Summe
# aller AUFWEITUNGEN auf dem Weg nach innen (500..8500 m, ohne die Engstelle 3500 m, die
# der Torschulter gehoert) geht von 475 auf 150 m zurueck.
# ES WIRD DAVON NICHTS BREITER: das Mittel ueber 500..8500 m bleibt bei 1120 m (1122 vor,
# 1118 nach dem Versatz), der Taleingang wird sogar 100 m schmaler. Der Preis steht im
# Verhaeltnis vorn zu hinten — es liest sich als 1.64 : 1 statt 1.80 : 1, weil die alten
# 1575 m gar keine Talbreite waren, sondern der hoechste Punkt der Schwebung.
# DER LAENGSABSTAND IN DER KETTE AENDERT SICH NICHT: verschoben wird die ganze Kette,
# nicht einzelne Massive — Abstand/Radius bleibt 0.500 auf beiden Seiten.
const TAL_KETTE_VERSATZ := 550.0
# Wo im Tal der Platz liegt (Abstand vom Talanfang) und auf welcher Hoehe.
# Weit hinten im Tal: der Anflug geht die ganze Laenge durch die Schlucht, und hinter dem
# Platz schliesst die Querkette das Tal ab — man muss also drehen und wieder hinaus.
# DER PLATZ LIEGT IM BERG. Er stand bei 8800 auf dem Talboden, und die Kaverne war nur
# sein Abschluss — im Bild eine Bahn auf der Wiese vor einer Wand mit Loch. Bei 9820 liegt
# die ganze 900-m-Bahn INNERHALB des Massivs: das Portal steht bei 9310, die Bahn reicht
# von 9370 bis 10270, und darueber stehen laut tools/_kaverne_platz.gd zwischen 488 m
# (bei 9400) und ueber 1000 m (bei 10350) Fels. Der Hallenscheitel liegt bei 145 m.
const ADLERHORST_LAENGS := 9820.0
# Wo die EINEBNUNG sitzt — bewusst NICHT mehr am Platz. Sie haelt den Talboden vor dem
# Portal auf Flugfeldhoehe, damit der Anflug eben bleibt und die Portalstirn sauber
# aufsetzt. Am Platz selbst waere sie schaedlich: sie wuerde den halben Berg abtragen,
# unter dem er liegt.
# 8800 UND KEINEN METER WEITER. Mit r_flat 520 reicht die Zone bis Talstation 9320 und
# haelt damit genau den Fuss der Portalstirn (9310) eben — das ist ihre Aufgabe. Ein
# Versuch mit 8900 schob sie bis 9420 und trug die FRONT DES MASSIVS ab: gemessen stand
# das Gelaende bei laengs 9400 auf 488 m, danach auf 90, und aus 150 m Hoehe im Berg
# blickte man ueber das Tal.
const ADLERHORST_VORFELD_LAENGS := 8800.0
# Talstation der QUERKETTE, die den Talschluss dichtmacht. Entspricht dem frueheren
# ADLERHORST_LAENGS + 1600 = 10400 und steht jetzt fuer sich, damit sie nicht mitwandert,
# wenn der Flugplatz umzieht. Die Kaverne endet bei 10390 — also genau in ihrem Fuss.
const TAL_QUERKETTE_LAENGS := 10400.0
const ADLERHORST_HOEHE := 90.0
# Abstand des Hoehlenportals von der Bahnachse, quer dazu. Begruendung an der Baustelle
# (Main._setup_world, "FELSENBASIS ADLERHORST").
# LAENGSSTATION DES KAVERNENPORTALS auf der Talachse. GEMESSEN (tools/_kaverne_platz.gd):
# bis 9300 liegt die ganze Roehrenbreite auf 90 m (die Bahn-Linse haelt), bei 9325 beginnt
# das Gelaende zu steigen, bei 9350 steht es schon auf 180 bis 226 — die Talschlusswand
# ist auf der Achse fast senkrecht. 9310 stellt die Portalstirn direkt an diese Wand; das
# Band, in dem die Gelaendeflaeche die Roehre durchquert, ist nur rund 30 m tief
# (laengs 9325 bis 9355) und liegt damit vollstaendig hinter dem Portalring.
# Die Bahn endet bei laengs 9270 — wer durchstartet, fliegt in den Berg.
const ADLERHORST_KAVERNE_LAENGS := 9310.0
# FELSENTOR am Taleingang: Position auf der Talachse. Weit genug drinnen, dass man schon
# zwischen den Waenden fliegt, weit genug vor dem Platz fuer einen langen Endanflug.
const TOR_LAENGS := 3600.0
# Breitenmass und Seed des Felsentors. ALS KONSTANTEN, weil sie an ZWEI Stellen gebraucht
# werden: beim Bau des Wahrzeichens und schon vorher beim Anmelden seiner Schutthalde beim
# Gelaende (die sperrt dort Bewuchs und Almwiese). Zwei Zahlenpaare waeren beim naechsten
# Umbau still auseinandergelaufen, und die Sperre haette dann neben der Halde gelegen.
const TOR_SPANN := 520.0
const TOR_SEED := 7731
# BERGSEE zwischen Tor und Flugplatz. surf ist der Wasserspiegel, SEE_R nur noch der
# MASSSTAB des gelappten Umrisses (TerrainWorld._see_umriss_faktor) — der Arm reicht bis
# 1,93 * SEE_R, quer bleiben rund 0,67 * SEE_R.
# SEE_R WAR 420 UND MUSSTE HERUNTER: der Umriss ist laenger als der alte Kreis, und mit
# 420 haette der Arm 913 m weit gereicht — quer durchs halbe Tal.
# 340 AUF 360 ZURUECK, weil die Grundform vom Kreis zum EI geworden ist (Begruendung dort:
# der See war im Grundriss ein spiegelsymmetrischer Schmetterling quer zum Tal). Das Ei ist
# schmaler, und bei gleichem Massstab waere der See auf 260 000 m2 geschrumpft. Mit 360
# bleibt er bei 313 000 m2, also praktisch so gross wie vorher — nur eben 1215 zu 482 m
# statt 1043 zu 510 m.
# DER SEE BRAUCHT KEINE FLACHZONE MEHR. Hier standen SEE_UFERZONE (790 m) und
# SEE_UFERBLEND (1270 m): eine Platte auf Spiegel + 6 m, die ihn davor bewahren sollte,
# ins Tal auszulaufen. Sie war zweimal falsch. Erstens war die Begruendung falsch — der
# Talboden ist hier NICHT auf 0 m (das war laengs 3000 und 6500 gemessen, also vor und
# hinter dem See), sondern auf 41 bis 230 m, Mittel 116 m: der See liegt in einer
# gewachsenen Mulde und stand nie auf einem Sockel. Zweitens ist jede Flachzone in
# TerrainWorld._open_ground zugleich eine FREIHALTEZONE, hier gemessen 0 Bewuchs bis
# 620 m und voll erst ab 1147 m — daher der kahle braune Ring auf allen Bildern.
# Dicht ist der See jetzt ueber den Beckenrand (TerrainWorld.SEE_WALL_*).
const SEE_LAENGS := 5000.0
const SEE_R := 360.0
const SEE_SPIEGEL := 78.0

const FERN_NAH := 2300.0
const FERN_FERN := 3300.0
# Ab hier laeuft auch die Grundabsenkung aus: jenseits der Chunks gibt es nichts mehr,
# was verdeckt werden muesste, und eine dauerhaft 14 m tiefere Schuerze wuerde flache
# Kuesten unter die Wasserplatte druecken.
const FERN_BIAS_AUS_A := 4000.0
const FERN_BIAS_AUS_B := 4800.0

var fly_world: Node3D
var cloud_field: Node3D           # Kumulusdecke (Lage 0) — Werkzeuge greifen darauf zu
var cloud_fields: Array[Node3D] = []   # ALLE Wolkenschichten, siehe WOLKEN_LAGEN
var wolken_dichte := 0.0          # 0 = freie Luft, 1 = mitten in einer Wolke
var fern_root: Node3D             # grobe Gelaendelage jenseits der Chunk-Sichtweite
var _fern_mat: ShaderMaterial
var _fern_thread: Thread
# Rasterweite, mit der der Schuerzen-Thread GERADE baut, und der Knoten der zuletzt
# eingehaengten Stufe (er wird beim Tausch freigegeben).
var _fern_zelle := FERN_ZELLE_GROB
var _fern_stufe_knoten: Node3D
var _fern_mutex: Mutex
var _fern_keys: Array[Vector2i] = []
var _fern_meshes: Array = []
var _fern_tris := 0
var showroom: ShowroomStage       # Praesentations-Buehne des Bau-Modus
var airfields: Array = []
var world_env: WorldEnvironment
var terrain: TerrainWorld           # seed-basierte Landschaft (Chunks um den Spieler)
var sky_lights: Node3D              # Sonne + Fülllicht NUR für den Flug
var sonne_licht: DirectionalLight3D # die Flugsonne — Grafikeinstellungen greifen darauf zu
var env_sky: Environment
var env_blueprint: Environment
var world_map: WorldMap             # KARTE (Taste M im Flug), Bild kommt aus dem Thread
var _map_thread: Thread
var _map_pois: Array = []

# UI
var ui: CanvasLayer
var build_root: Control
var flight_root: Control
var stats_label: Label
# Praesentationstafel rechts: grosser Flugzeugname + Kennwerte (Showroom-Komposition)
var praesent_titel: Label
var praesent_werte: Label
var flight_check: FlightCheckPanel  # grafische Flug-Info (Balance / Stabilität / Kennwerte / Verdict)
var hud_label: Label
var land_label: Label
var flight_hud: FlightHud           # Primary-Flight-Display (Kompass, Speed/Höhe, Zielkreis)
var tool_label: Label
var toast_label: Label
var pause_overlay: Control          # Pause-Menü (Esc)
var _paused := false
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _hint_box: Control              # einmaliger Steuer-Hinweis beim ersten Flug
# Snapping-Toggle ist jetzt snap_btn (Magnet) in der unteren Aktionsleiste.
var drag_view_btn: Button
var wind_legend: Control            # Farb-Legende, nur bei aktivem Windkanal sichtbar
var paint_preview: ColorRect        # zeigt die aktuelle Lackfarbe
var paint_picker: ColorPickerButton # freie Farbwahl (Farbrad/RGB/Hex)
var pipette_btn: Button             # Pipette an/aus
var part_buttons: Dictionary = {}
var _part_group: ButtonGroup       # exklusive Auswahl der Teil-Kacheln

# Wirtschaft / Modi
var game: GameState
var money_label: Label             # Hangar
var fly_money_label: Label         # Flug-HUD
var survival_label: Label          # Flug-HUD: Welle / Abschüsse / Combo / Score (Survival)
# --- Survival-Wellen & Flug-Score ---
var _wave := 0                     # aktuelle Welle (0 = keine läuft)
var _alive := 0                    # noch lebende Wellen-Ziele
var _kills := 0                    # Abschüsse dieser Flug-Session
var _combo := 0                    # aktuelle Abschuss-Combo
var _combo_t := 0.0                # Restzeit des Combo-Fensters
var _best_combo := 0               # beste Combo dieser Session
var _flight_money0 := 0            # Guthaben bei Flugbeginn (für „verdient")
var _flight_score := 0             # Punkte dieser Session
var _wave_session := 0             # Token: jeder Flugstart erhöht es -> alte Wellen-Timer verfallen
var _spin_nodes: Array = []        # Basis-Deko: drehende Nodes (Radar)
var _blink_nodes: Array = []       # Basis-Deko: blinkende Lichter (Antennen)
# Erzeugte Flugplatz-Meshes (Bogenschale, Stirnwand, Baum, Gitterturm). Sieben Flugplaetze
# bauen dieselben Formen — ohne diesen Speicher entstuenden sie 7-fach als eigene Resource
# und waeren fuer den Renderer sieben verschiedene Meshes (kein Instancing, mehr Speicher).
var _fp_meshes: Dictionary = {}
var _blink_t := 0.0
const COMBO_WINDOW := 5.0          # Sekunden zwischen Abschüssen, um die Combo zu halten
var part_grid: GridContainer       # Palette-Grid der AKTIVEN Kategorie (Neuaufbau nach Kauf/Tab-Wechsel)
var cat_tabs: TabBar               # Kategorie-Unterreiter (Rumpf/Flügel/…)
var _active_cat: int = 0           # aktive Kategorie (Tab-Index, bleibt über Rebuilds erhalten)
var _cat_icon_btns: Array = []     # runde Kategorie-Reiter (Icons) — fürs Highlight
var tools_icon_btn: Button         # ••• -Reiter (Werkzeuge & mehr)
var parts_view: ScrollContainer    # Bauteile-Ansicht (Grid)
var tools_view: ScrollContainer    # Werkzeuge-Ansicht (hinter dem ••• -Reiter)
var snap_btn: Button               # Snapping-Toggle (Magnet) — jetzt in der oberen Werkzeugleiste
var mirror_btn: Button             # Spiegelung-Toggle — jetzt in der oberen Werkzeugleiste
var _tb_view_btns: Array = []      # Ansicht-Buttons (Frei/Front/Seite/Oben) der Werkzeugleiste
var _tb_tool_btns: Array = []      # Werkzeug-Buttons (Bewegen/Drehen/Skalieren) der Werkzeugleiste
var _show_tools := false           # zeigt gerade die Werkzeuge-Ansicht?
var upgrade_box: VBoxContainer     # Upgrade-Panel
var mode_overlay: Control          # Modus-Auswahl-Overlay
var dialog_overlay: Control = null # Speichern-/Laden-Overlay
var _slot_name := "Mein Flugzeug"  # zuletzt verwendeter Slot-Name (Default im Speichern-Dialog)
# Vorlagen-Flugzeuge (id, Anzeigename) — werden im Laden-Dialog gelistet
const PRESETS := [
	["fokker_dr1", "Fokker Dr.I  ·  Roter Baron"],
	["spitfire", "Supermarine Spitfire"],
	["mustang_p51", "P-51 Mustang"],
	["me262", "Me 262 Schwalbe  ·  Erster Düsenjäger"],
	["f86", "F-86 Sabre  ·  Korea-Düsenjäger"],
	["mig15", "MiG-15  ·  Sowjet-Düsenjäger"],
	["f4", "F-4 Phantom II  ·  Vietnam-Allrounder"],
	["mig21", "MiG-21  ·  meistgebauter Überschalljet"],
	["f14", "F-14 Tomcat  ·  Top-Gun-Legende"],
	["f22", "F-22 Raptor  ·  Stealth-Jäger"],
	["sturmjet", "Sturmjet  ·  schwer bewaffnet"],
	["jet", "Kampfjet  ·  Delta-Canard"],
]
var sel_panel: Control             # Kontext-Panel für ausgewähltes Teil
var sel_title: Label
var sel_scale_label: Label
var sel_delete_btn: Button
var sel_mode_btns: Array = []      # [Bewegen, Drehen, Skalieren, Enden skalieren,
                                   #  Enden verschieben] — Index = gizmo_mode
var sel_taper_row: VBoxContainer   # Verjüngungs-Regler (nur für taper-fähige Rumpfteile)
var sel_taper_front_row: HBoxContainer  # vorderes Ende (nur biends-Teile, z. B. F-22-Rumpf)
var sel_taper_label: Label
var sel_reverse_cb: CheckBox        # »Schub umkehren« (nur für Prop-Triebwerke sichtbar)

# Ziele zum Abschießen (Luftballons/Luftschiffe) + Geschosse
var targets_root: Node3D           # Container in fly_world für Ziele + Geschosse


func _ready() -> void:
	# Höhere Physikrate gegen Ruckeln auf 120-Hz-Displays (ProMotion)
	Engine.physics_ticks_per_second = 120
	game = GameState.new()
	add_child(game)
	game.load_state()
	game.changed.connect(_on_game_changed)
	_setup_world()
	_setup_camera()
	_setup_controllers()
	targets_root = Node3D.new()
	fly_world.add_child(targets_root)
	flight_ctrl.world_root = targets_root
	flight_ctrl.sens_mult = game.mouse_sens   # persistierte Maus-Flug-Empfindlichkeit anwenden
	flight_ctrl.g_protect = game.g_protect    # persistierter G-Schutz (Taste H)
	_spawn_targets()
	_spawn_flak()
	_spawn_sam()
	_spawn_inselwehr()
	_setup_ui()
	if not _load_design():
		# Erststart ohne Speicherstand: fertiger Beispiel-Doppeldecker im Hangar,
		# damit man sofort losfliegen kann (Umbauen/Abreissen jederzeit möglich).
		build_ctrl.load_design(_default_design())
	_set_mode(Mode.BUILD)
	_refresh_tool_ui()
	_on_game_changed()
	if game.mode == GameState.GameMode.NONE:
		_show_mode_select()


# ===========================================================================
# WELT
# ===========================================================================
func _setup_world() -> void:
	# Umgebung / Himmel
	# AVIASSEMBLY-HIMMEL: satter Blau-Verlauf + Sonne + fluffige prozedurale
	# Kumuluswolken (Shader res://shaders/sky_clouds.gdshader). sun_dir passend
	# zur Tagessonne unten (rot -50,-50).
	var env := Environment.new()
	var sky := Sky.new()
	var sky_sm := ShaderMaterial.new()
	sky_sm.shader = load("res://shaders/sky_clouds.gdshader")
	# EIN Sonnenstand fuer Himmel UND Licht: SONNE_WINKEL steht ueber beiden, damit
	# Schattenrichtung und gemalte Sonne nicht auseinanderlaufen koennen.
	var sun_basis := Basis.from_euler(Vector3(deg_to_rad(SONNE_WINKEL.x), deg_to_rad(SONNE_WINKEL.y), 0.0))
	sky_sm.set_shader_parameter("sun_dir", sun_basis.z)
	sky.sky_material = sky_sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# 0.52 STATT 0.85. Ambient ist Licht ohne Richtung — je mehr davon, desto weniger
	# bedeutet der Sonnenstand. Bei 0.85 gegen eine Sonne von 1.30 kam fast die Haelfte der
	# Beleuchtung aus allen Richtungen zugleich und fuellte jeden Schatten wieder auf.
	# Weniger Ambient macht die Schattenseite dunkel genug, dass die Sonnenseite ueberhaupt
	# als solche zu erkennen ist.
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# WICHTIG: tonemap_white=1.0 presste die GESAMTE Range platt -> alles pastellig-milchig
	# ("fade Map"). white=6 gibt ACES seine Dynamik zurueck, Farben duerfen wieder satt sein.
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.0
	# KONTAKTVERSCHATTUNG. Ohne sie beruehrt kein Gegenstand den Boden: Flugzeuge,
	# Kisten, Masten und Hangars stehen mit einer sauberen Kante auf der Flaeche und
	# lesen sich als aufgeklebt — in drei unabhaengigen Abnahmen ueber drei Runden der
	# am haeufigsten wiederholte Befund. Der Radius ist mit 1,6 m ABSICHTLICH klein: er
	# soll Auflagepunkte und Innenkanten fassen, nicht die grossen Flaechen abdunkeln.
	# light_affect bleibt 0, damit die Verschattung nur das Umgebungslicht daempft und
	# die Lichtseen der Lampen unangetastet bleiben.
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.6
	env.ssao_power = 1.6
	env.ssao_detail = 0.55
	env.ssao_horizon = 0.07
	env.ssao_light_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.05
	env.adjustment_brightness = 1.0
	# Luftperspektive statt Milchglas: weniger Dichte, dafuer mehr AERIAL (Ferne kippt in
	# den Himmelston = Tiefe + Farbe, statt alles weiss zu waschen).
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	# DIESELBEN KONSTANTEN WIE DIE WOLKEN-EINTRUEBUNG. Hier standen die beiden Zahlen ein
	# zweites Mal als Literal, waehrend _wolken_aufenthalt sie aus NEBEL_FREI und
	# NEBEL_FARBE_FREI nimmt. Zwei Wahrheiten fuer denselben Wert: wer eine davon aendert,
	# aendert den Nebel im Flug oder beim Aufbau, aber nicht beides — und die Abnahmebilder
	# (tools/_terrain_render.gd) kommen ohne Flugzeug aus, laufen also NUR ueber diesen Pfad.
	env.fog_light_color = NEBEL_FARBE_FREI
	env.fog_sun_scatter = 0.15
	env.fog_density = NEBEL_FREI
	# 0.62 STATT 0.30. Der Wert bestimmt, wie stark der Nebel die Farbe des HIMMELS
	# annimmt statt einer festen Nebelfarbe — also wie sehr Ferne sich in Luft aufloest.
	env.fog_aerial_perspective = 0.62
	env.fog_sky_affect = 0.1
	# GLOW: AUS — und zwar gemessen, nicht aus Geschmack.
	# Die Nachbelichtungskette dieser Szene wurde durchkalibriert (Graukeil durch
	# Tonemap+Adjustments): sRGB 255 entspricht HDR 1.56, sRGB 220 schon HDR 0.84.
	# Die Szene liegt also fast vollstaendig UNTER 1.0 — die alte Schwelle 1.45 fing
	# damit praktisch nichts ein. Drei Renderlaeufe ueber dieselben acht Ansichten:
	#   Schwelle 1.45 gegen Glow AUS -> groesster Unterschied 3 von 255
	#   Schwelle 0.85 gegen Glow AUS -> groesster Unterschied 3 von 255
	#   Schwelle 1.10, Intensitaet 0.35 -> 0.0-0.7 % der Pixel ueber 3, Maximum 8
	# (Rauschgrenze zwischen zwei identischen Laeufen: bis 8.9 % der Pixel ueber 3.)
	# Der Pass liegt also durchgehend UNTER dem Rauschen des Renderers und kostet
	# trotzdem jeden Frame die volle Kette. Deshalb ab: sichtbar wuerde er erst mit
	# einer Schwelle mitten im Motiv — und das waere genau der Schleier, den die
	# Art Direction nicht will.
	env.glow_enabled = false
	env_sky = env

	# PRAESENTATIONS-BUEHNE fuer den Bau-Modus. Frueher stand hier ein heller Tages-
	# himmel ("das Flugzeug steht wie draussen am Flugfeld"); die jetzige Art Direction
	# verlangt stattdessen einen dunklen Petrolraum mit Blueprint-Boden, gerichtetem
	# Dreipunktlicht und kraeftigen Kontaktschatten. Alles dazu steckt gebuendelt in
	# ShowroomStage — Environment, Licht, Boden und Vignette.
	showroom = ShowroomStage.new()
	add_child(showroom)                       # _ready() der Buehne baut das Environment
	env_blueprint = showroom.environment

	world_env = WorldEnvironment.new()
	world_env.environment = env_sky
	add_child(world_env)

	# --- Flug-Beleuchtung: Sonne + Fülllicht (nur im Flug aktiv) ---
	sky_lights = Node3D.new()
	add_child(sky_lights)
	# Hohe, freundliche Tagessonne (einen Tick wärmer -> verspielt).
	# SCHATTEN AN: ohne sie war jeder Berg eine flache Farbfläche und der Landeanflug
	# hatte kein Hoehengefuehl. Vier Kaskaden bis 3 km — das ist genau die Weite, in der
	# das Terrain lebt (TerrainWorld.VIEW_DIST = 3,8 km); darueber uebernimmt die
	# Luftperspektive. Bias/Normal-Bias sind fuer die grossen Low-Poly-Facetten
	# eingestellt (8-m-Raster, sehr flache Winkel am Nachmittagsstand der Sonne).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = SONNE_WINKEL
	# 1.55 UND WAERMER. Mit halbiertem Ambient muss die Sonne mehr tragen, und eine tief
	# stehende Sonne ist waermer — 26 Grad Hoehe sind spaeter Nachmittag, nicht Mittag.
	sun.light_color = Color(1.0, 0.94, 0.80)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	# SCHATTEN DUERFEN NICHT SCHWARZ SEIN — und das ist die Kehrseite des halbierten
	# Ambients. Gemessen nach der Umstellung: die verschattete Canyonwand stand bei
	# RGB (2, 2, 1), und 16 Prozent des Bildes lagen unter Luminanz 5. Ein Viertel der
	# Aufnahme war ein Loch ohne Silhouette.
	#
	# shadow_opacity ist dafuer der richtige Regler und nicht das Ambient: er hellt NUR
	# den Schatten auf und laesst die besonnte Seite, wo der ganze Gewinn liegt, unberuehrt.
	# Waere ich stattdessen ans Ambient gegangen, haette ich genau die Flachheit
	# zurueckgeholt, gegen die der tiefe Sonnenstand angetreten ist.
	sun.shadow_opacity = 0.76
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 3000.0
	sun.directional_shadow_split_1 = 0.045
	sun.directional_shadow_split_2 = 0.13
	sun.directional_shadow_split_3 = 0.38
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.9
	sun.shadow_bias = 0.09
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 1.1
	# GEMESSEN: mit opacity 0.92 fiel besonnter Sand von sRGB 234 auf 75 — Wolkenschatten
	# sahen aus wie Tintenflecken, nicht wie Schatten. 0.62 laesst genug Sonne durch,
	# dass der Schatten FARBIG bleibt und trotzdem klar liest.
	sun.shadow_opacity = 0.62
	sky_lights.add_child(sun)
	sonne_licht = sun
	# Fuelllicht von unten/hinten. Es bekommt bewusst KEINE Schatten (es soll aufhellen,
	# nicht ein zweites Schattenbild dazulegen) und wurde von 0.32 auf 0.24 gedaempft:
	# solange die Sonne schattenlos war, musste es die Formen retten — jetzt uebernimmt
	# das der Sonnenschatten, und zu viel Gegenlicht wuerde ihn wieder zuschmieren.
	var underfill := DirectionalLight3D.new()
	# 22 GRAD HOEHE STATT 58 — UND DAS WAR DER EIGENTLICHE FEHLER, NICHT DIE ENERGIE.
	# Aus 58 Grad faellt das Licht steil ein und trifft eine fast SENKRECHTE Steilwand
	# kaum: gemessen brachte eine Verdreifachung der Energie im Canyonbild ganze 1,1
	# Prozentpunkte weniger schwarze Flaeche. Eine Wand braucht Licht, das sie streift,
	# nicht Licht von oben. 22 Grad gegenueber der Sonne tun genau das.
	underfill.rotation_degrees = Vector3(22, 130, 0)
	underfill.light_color = Color(0.80, 0.86, 0.95)
	# 0.62 STATT 0.24 — UND DAS IST DER RICHTIGE HEBEL FUER SCHWARZE SCHATTENSEITEN.
	#
	# Nach dem Umstellen auf tiefe Sonne und halbes Ambient stand die abgewandte
	# Canyonwand bei RGB (2, 2, 1); 16 Prozent des Bildes lagen unter Luminanz 5. Zuerst
	# habe ich es mit shadow_opacity versucht und damit gemessen NICHTS erreicht
	# (16,2 auf 15,8 Prozent) — aus gutem Grund: die Wand liegt gar nicht im
	# SCHLAGSCHATTEN, sie ist nur von der Sonne ABGEWANDT. Dagegen hilft kein
	# Schattenregler, sondern Licht aus einer anderen Richtung.
	#
	# Genau dafuer steht dieses Fuelllicht schon hier. Es kommt aus 58 Grad Hoehe und
	# 130 Grad Azimut, also grob gegenueber der Sonne, und ist kuehl gefaerbt — es hebt
	# die Schattenseiten an, ohne die Sonnenseite zu beruehren, und gibt ihnen nebenbei
	# den kalten Ton, den Himmelslicht in Wirklichkeit hat.
	underfill.light_energy = 0.62
	underfill.shadow_enabled = false
	sky_lights.add_child(underfill)

	# Das Hangar-Licht liegt jetzt in ShowroomStage (Key/Fill/Rim mit Schatten).
	# Frueher standen hier drei schattenlose Aufheller — die gaben zwar ein sehr
	# gleichmaessiges Bild, aber weder Silhouette noch Kontaktschatten.

	# Boden-Kollision: unendliche Ebene auf MEERES-Niveau (-6 m) — Sicherheitsnetz
	# unter allem + "Wasseroberfläche" zum Notwassern. Land-Kollision liefert das Terrain.
	var ground_body := StaticBody3D.new()
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	ground_body.position = Vector3(0, TerrainWorld.SEA_Y, 0)
	var gcs := CollisionShape3D.new()
	gcs.shape = WorldBoundaryShape3D.new()
	ground_body.add_child(gcs)
	add_child(ground_body)

	# Flug-Welt: Terrain, Flugplätze (nur im Flug sichtbar)
	fly_world = Node3D.new()
	add_child(fly_world)

	# Flugplätze (Name, Position, Ausrichtung, Farbe)
	airfields = [
		{"name": "HEIMAT", "pos": Vector3(0, 0, -100), "heading": 0.0, "color": Color(0.9, 0.9, 0.95), "main": true},
		{"name": "NORDFELD", "pos": Vector3(-1500, 0, -2000), "heading": 0.7, "color": Color(0.95, 0.75, 0.3)},
		{"name": "OSTHAFEN", "pos": Vector3(2200, 0, -250), "heading": -1.15, "color": Color(0.45, 0.75, 0.98)},
		{"name": "BERGPISTE", "pos": Vector3(900, 0, 2000), "heading": 2.3, "color": Color(0.95, 0.5, 0.45)},
		# Aussenfelder der GROSSEN Insel (~10-15 km Kuestenradius) — echte Reiseziele
		# AN DIE NEUE KUESTE GERUECKT (war -9200/-600). Beide Namen — WESTKAP und
		# SUEDSTRAND — beschreiben Kuestenlagen, und nach dem Vergroessern der Insel von
		# 17,8 auf 25,8 km mittleren Radius lagen sie 15 bis 17 km im Landesinneren. Das
		# war nicht nur ein falscher Name: die neu gewonnene Flaeche hatte damit ueberhaupt
		# kein Ziel, und "groesser" waere blosse leere Strecke geblieben.
		# Die Stellen sind gemessen (tools/_kuestenplatz.gd): Westkap 1800 m hinter der
		# Kueste bei 52 m Hoehenspanne im 700-m-Feld, Suedstrand 1200 m dahinter bei 31 m —
		# die flachsten Punkte auf ihrer jeweiligen Peilung.
		# MIT DER KUESTE NACH AUSSEN GERUECKT. Durch die Vergroesserung auf 27,2 km lag
		# WESTKAP statt 1,7 plötzlich 3,1 km von der Wasserlinie — ein "Kap" mitten im
		# Hinterland. Dieselbe Peilung, derselbe Abstand zum Wasser wie vorher.
		{"name": "WESTKAP", "pos": Vector3(-25706, 0, -1662), "heading": 1.9, "color": Color(0.55, 0.85, 0.60)},
		# EBENSO SUEDSTRAND: von 0,7 auf 2,0 km ins Landesinnere gerutscht. Ein
		# Strandflugplatz, von dem aus man das Meer nicht sieht, ist ein Namensfehler.
		{"name": "SÜDSTRAND", "pos": Vector3(7188, 0, 25403), "heading": -0.6, "color": Color(0.95, 0.60, 0.85)},
		{"name": "VULKANFELD", "pos": Vector3(8800, 0, -4600), "heading": 0.9, "color": Color(0.95, 0.45, 0.20)},
		# ADLERHORST liegt als EINZIGER Platz nicht auf Meereshoehe, sondern auf einem
		# Sattel im Hochgebirge. Die y-Komponente traegt die Plateauhoehe; _build_airfield
		# setzt den ganzen Platz darauf, und die Einebnungszone unten zieht das Gelaende
		# auf denselben Wert.
		# DER KURS LAEUFT LAENGS DES TALS und wird aus der Talachse GERECHNET, nicht
		# hingeschrieben. Nachgemessen mit tools/_gebirge_check.gd stehen die Waende bis
		# 762 m ueber dem Platz; quer zum Tal zu starten verlangte 17,9 Grad Steigwinkel.
		# Laengs ist die eine Richtung frei (Talausgang), die andere fuehrt auf die
		# Querkette zu — man startet also talauswaerts und dreht draussen.
		{"name": "ADLERHORST", "pos": _adlerhorst_pos(), "heading": _adlerhorst_kurs(),
			"color": Color(0.80, 0.86, 0.95)},
	]

	# SEED-BASIERTES TERRAIN ersetzt die flache Platte + Deko-Berge/-See.
	# Jeder Flugplatz bekommt eine Einebnungs-Zone (HEIMAT größer — dort liegt
	# auch der Hindernis-Parcours). Seed kommt aus dem Spielstand (einmal
	# gewürfelt, dann stabil — dieselbe Welt bei jedem Start).
	if game.world_seed == 0:
		game.world_seed = randi() % 1000000
		game.save()
	terrain = TerrainWorld.new()
	# EIN Sonnenstand fuer Himmel, Licht UND Wasser. Muss VOR dem Bauen gesetzt sein,
	# damit die Wasser-Materialien gleich mit der richtigen Richtung entstehen.
	terrain.setze_sonne(Basis.from_euler(Vector3(
		deg_to_rad(SONNE_WINKEL.x), deg_to_rad(SONNE_WINKEL.y), 0.0)).z)
	# DIESELBE RICHTUNG AN DIE BAUWERKE. Landmarks faerbt Fels nach Sonnen- und
	# Schattenseite (Landmarks._fels_tri) und muss dafuer wissen, wo die Sonne steht.
	# Zwei Quellen waeren zwei Sonnen: Tor und Halde wuerden aus einer anderen Richtung
	# beleuchtet erscheinen als der Berg, an dem sie lehnen.
	Landmarks.sonne_zu = Basis.from_euler(Vector3(
		deg_to_rad(SONNE_WINKEL.x), deg_to_rad(SONNE_WINKEL.y), 0.0)).z.normalized()
	var flat_zones: Array = []
	for af in airfields:
		var is_main: bool = af.get("main", false)
		# r_flat/r_blend ebnen wie bisher einen KREIS ein (die Bahn muss flach bleiben,
		# und bei HEIMAT liegt der Hindernis-Parcours in der Zone). "rects" steuert etwas
		# ANDERES: welche Flaeche von Bewuchs und Felsen freigehalten wird. Das hing frueher
		# am selben Kreis und legte den Platz in eine 1147 m weite kahle Scheibe — siehe
		# TerrainWorld._open_ground. Format je Rechteck: [mitte_x, mitte_z, halb_x, halb_z]
		# in PLATZ-Koordinaten (Bahn laengs Z, Ursprung Bahnmitte).
		# EINE Quelle fuer beide Seiten: derselbe Satz Rechtecke steuert die Freihaltung im
		# Gelaende UND den Nahsaum in _gruenguertel. Liefen die auseinander, saete der Saum
		# genau dorthin, wo das Gelaende gerade freiraeumt.
		var rects: Array = FP_RECHTECKE.duplicate(true)
		if not is_main:
			# Aussenfelder bekommen zusaetzlich den Blender-Bausatz bei lokal (230, -60);
			# plan_flugplatz() spannt davon -115..180 in x und -30..70 in z auf.
			rects.append([262.0, -40.0, 170.0, 70.0])
		# ADLERHORST: die KAVERNE freihalten. Im Bild standen Nadelbaeume mitten im
		# Tunnelmund — die Bepflanzung weiss nichts von ihr, und der Kreis des Platzes
		# (r_flat 520) endet lange vor dem Portal.
		# LOKALE KOORDINATEN: die Bahn laeuft laengs Z, und _adlerhorst_kurs() zeigt
		# ENTGEGEN TAL_RICHTUNG — talaufwaerts, also zur Kaverne hin, ist damit -Z.
		# Das Portal liegt bei Talstation 9310, der Platz bei 8800: 510 m voraus. Die
		# Halle reicht 700 m weiter, also bis -1210. Mitte -860, Halbtiefe 350,
		# Halbbreite 175 (Roehre 168 plus Rand).
		# Das wirkt NUR auf den Bewuchs: die Hoehe des Gelaendes haengt an r_flat/r_blend,
		# nicht an den Rechtecken — der Berg ueber der Kaverne bleibt also stehen.
		if String(af.get("name", "")) == "ADLERHORST":
			# DIE RECHTECKE GELTEN ZUR ZONE, NICHT ZUM PLATZ. Genau daran bin ich
			# gescheitert: hier stand [0, -30, 175, 560], gerechnet ab dem Platz bei 9820 —
			# die Zone sitzt aber im Vorfeld bei 8800. Freigehalten wurde damit laengs 8240
			# bis 9370, also ein Kilometer Wiese vor dem Berg, und in der Halle stand ab
			# laengs 9460 _open_ground auf 1.00: gemessener voller Bewuchs ueber die ganze
			# Kaverne, im Bild Straeucher neben der Bahn.
			# AUS DEN KONSTANTEN GERECHNET statt hingeschrieben, damit das Rechteck der
			# Roehre folgt, wenn HB_LAENGE oder eine der Stationen sich aendert.
			# Talaufwaerts ist lokal -Z, die Station waechst also gegen -Z.
			var z_portal := -(ADLERHORST_KAVERNE_LAENGS - ADLERHORST_VORFELD_LAENGS)
			var z_rueck := z_portal - Landmarks.HB_LAENGE
			rects.append([0.0, (z_portal + z_rueck) * 0.5, 175.0,
				(z_portal - z_rueck) * 0.5 + 20.0])
		# ADLERHORST BEKOMMT SEINE ZONE WOANDERS. Der Platz liegt seit dem Umbau tief im
		# Berg; eine Einebnung an seiner Stelle wuerde das Massiv ueber ihm abtragen. Sie
		# sitzt deshalb vorn im Tal (ADLERHORST_VORFELD_LAENGS) und haelt dort den
		# Anflugstreifen und den Fuss der Portalstirn eben — genau das, wofuer sie da ist.
		var fz_pos: Vector3 = af["pos"]
		if String(af.get("name", "")) == "ADLERHORST":
			var vp := _tal_punkt(ADLERHORST_VORFELD_LAENGS)
			fz_pos = Vector3(vp.x, 0.0, vp.y)
		var fz := {"pos": fz_pos, "heading": af["heading"],
			"r_flat": 1700.0 if is_main else 750.0,
			"r_blend": 2300.0 if is_main else 1200.0, "rects": rects}
		# HOEHE MITGEBEN. Bisher kannte diese Schleife nur Plaetze auf Meereshoehe und
		# liess das Feld weg, womit TerrainWorld auf 0 einebnete. ADLERHORST liegt auf
		# einem Bergsattel — ohne das hier haette die Einebnung ihm den Berg unter den
		# Fuessen weggeschnitten und einen 340 m tiefen Krater hinterlassen.
		var ay: float = (af["pos"] as Vector3).y
		if absf(ay) > 0.01:
			fz["y"] = ay
			# Engere Zone als bei den anderen Aussenfeldern: mit 1200 m Ausblendung reichte
			# sie bis in die Nachbargipfel und haette den 660er auf 562 m gedrueckt.
			# VON 700/1050 UEBER 630/780 AUF 520/620 HERUNTER. Die Zone liegt an der
			# TIEFSTEN Stelle des Tals und war dort trotzdem die WEITESTE: gemessen
			# (tools/_krit_keil.gd) 1025 m Talboden bei laengs 8750 m gegen 850..900 m an
			# der engsten Stelle davor — +21 Prozent genau dort, wo der Talschluss sein
			# soll. Gewachsen sind an derselben Stelle nur 50 m Boden; die ganze Aufweitung
			# ist die Einebnung.
			#
			# WAS DIE ZONE WIRKLICH BRAUCHT — und das ist WENIGER, als die alten Radien
			# vorgaben. Bindend sind drei Punkte, alle in Platz-Koordinaten:
			#   * die Bahnflaeche, ueber die tools/_gebirge_check.gd die Unebenheit misst:
			#     eine KREISSCHEIBE mit 450 m Radius. Sie ist die harte Bedingung.
			#   * das Bahnende bei (0, 470) — (RWY_LEN + 40) / 2.
			#   * die weiteste Ecke des Blender-Bausatzes bei (432, -110).
			# Der Umkreis all dessen ist rund 470 m, nicht 630. Die 630 kamen allein daher,
			# dass der Querfaktor 0.72 die 450 m Bahnbreite auf 450 / 0.72 = 625 aufblies.
			# JETZT ANDERSHERUM: Querfaktor 0.88 und r_flat 520. Quer bleiben 0.88 * 520 =
			# 458 m flach (die 450 m der Bahnflaeche mit 8 m Rand), laengs 520 m (Bahnende
			# mit 50 m Rand), und die Bausatzecke liegt elliptisch bei 502 m, also 18 m
			# innerhalb — dieselbe Reserve wie vorher. Die Linse ist damit LAENGS 110 m
			# kuerzer geworden, ohne quer schmaler zu werden.
			# NICHT WEITER HERUNTER: bei r_flat 500 liegt die Bausatzecke ausserhalb, bei
			# Querfaktor ueber 0.90 reicht die Ausblendung auf die Bahn und die Unebenheit
			# ist nicht mehr 0.000 m.
			#
			# WARUM 620 UND NICHT WENIGER: r_blend - r_flat ist die Boeschung, quer also
			# 0.88 * 100 = 88 m statt vorher 0.72 * 150 = 108 m. Sie wird davon NICHT
			# steiler, obwohl sie kuerzer ist — die Zone hebt weniger Material aus, also
			# muss die Boeschung auch weniger Hoehe ueberwinden. Gemessen quer bei 8800 m
			# in 100-m-Schritten ueber der Fusslinie 90 m (tools/_tal_keil.gd):
			#   vorher  90 90 90 90 90 158 313  -> steilste Stufe 57 Grad
			#   jetzt   90 90 90 90 90 168 304  -> steilste Stufe 54 Grad
			# DAS IST TROTZDEM DER ABWAEGUNGSPUNKT: jeder weitere Meter, den die Boeschung
			# kuerzer wird, nimmt zwei Meter Talbodenbreite am Platz weg und stellt die Wand
			# neben dem Vorfeld steiler. Ab rund 72 Grad steht dort eine Steinbruchwand.
			# Der Talboden kann hier ohnehin nie unter 2 * 458 = 916 m: das Plateau selbst
			# liegt auf 90 m und zaehlt in jeder Messung als Talboden. 916 m ist die harte
			# Untergrenze, die die Bahnflaeche vorgibt — naeher ist ohne kuerzere Bahn nicht
			# heranzukommen.
			fz["r_flat"] = 520.0
			fz["r_blend"] = 620.0
			# QUERFAKTOR — die Einebnung ist hier eine ELLIPSE laengs der Bahn, kein Kreis.
			# WARUM: der Kreis mit 1050 m Ausblendung liegt im engsten Teil des Tals und
			# hat den Talboden dort auf 1725 m aufgeweitet, obwohl der Fels nur 1040 m
			# frei laesst. In der Aufsicht war das ein exakter Kreis mitten im Keil, und
			# gemessen war der tiefste Punkt des Tals damit der WEITESTE — genau das
			# Gegenteil der Absicht.
			# 0.88 QUER: quer flach gebraucht werden 450 m (die Bahnflaeche, an der die
			# Unebenheit gemessen wird) — mehr nicht. Der Querfaktor ist deshalb NICHT der
			# Hebel, um die Zone schmaler zu bekommen: quer_faktor * r_flat muss rund 455
			# bleiben, egal wie man die beiden aufteilt. Er ist der Hebel, um sie LAENGS
			# kuerzer zu bekommen — je groesser er ist, desto kleiner darf r_flat sein und
			# desto weniger weit reicht die Linse ins Tal hinein.
			# GEGENPROBE ZUR ALTEN FASSUNG (0.72 / 630 / 780): dieselbe Bahnbreite, aber die
			# Linse reichte laengs bis 8800 + 780 = 9580 m, also bis in den Talschluss, den
			# die Querkette ab 9250 m dichtmacht. Jetzt endet sie bei 9420 m.
			fz["quer_faktor"] = 0.88
		flat_zones.append(fz)
	# FUER DIE KAVERNE AM TALSCHLUSS BRAUCHT ES KEINE EIGENE EINEBNUNG — und das ist kein
	# Zufall, sondern der Grund, warum sie dort steht: die Bahn-Linse haelt das Gelaende
	# auf der Achse bis laengs 9300 auf exakt 90 m, und dahinter steigt die Talschlusswand
	# so steil, dass die Gelaendeflaeche schon bei 9355 ueber dem Roehrenscheitel liegt.
	# Das schmale Band dazwischen verdeckt der Portalring (siehe Landmarks, LINER).
	# Die fruehere Einebnung fuer den Seitenwand-Stollen ist mit ihm entfernt.
	# --- WAHRZEICHEN/POIs: Stadt mit See + Leuchtturm + BERGDORF am FLUSS (Stufe 3) ---
	var town_pos := Vector3(1400, 0, 750)
	var factory_pos := town_pos + Vector3(-225, 0, 95)
	var lake_pos := Vector3(1400, 0, 1030)
	var lh_pos := Vector3(-950, 0, -1250)
	var village_pos := Vector3(2550, 120, 1650)   # Bergdorf-Plateau (Schelf am Massiv)
	flat_zones.append({"pos": town_pos, "r_flat": 360.0, "r_blend": 760.0})
	flat_zones.append({"pos": lake_pos, "r_flat": 230.0, "r_blend": 520.0})  # See-Umfeld flach
	# HIER STAND DIE FLACHZONE DES BERGSEES. Sie ist ersatzlos weg — Begruendung und
	# Messwerte oben bei SEE_LAENGS. Das Becken schneidet trotzdem nicht schraeg in den
	# Talhang: innerhalb der Uferlinie rechnet height_at nur noch mit der Umrissformel,
	# und nach aussen uebernimmt der Beckenrand.
	flat_zones.append({"pos": lh_pos, "r_flat": 110.0, "r_blend": 300.0})
	# Kleine Freiflaeche fuer den Inselleuchtturm. y = 18 entspricht dem gewachsenen
	# Gelaende an dieser Stelle, es entsteht also keine Stufe — die Zone ist nur dafuer da,
	# den Bewuchs zu sperren (jede Flachzone tut das in _open_ground).
	flat_zones.append({"pos": Vector3(30450, 18.0, -7600), "r_flat": 55.0,
		"r_blend": 130.0, "y": 18.0})
	# UND EINE FUER DIE STELLUNG AUF DER GROSSEN INSEL — aus demselben Grund, und der
	# hat mich diesmal eine ganze Fehlersuche gekostet: die Stellung stand vollstaendig,
	# an der richtigen Weltposition, mit neun sichtbaren Netzen — und war im Bild
	# trotzdem nicht zu finden. Erst ein magentafarbener Testanstrich zeigte von ihr
	# einen 18 Pixel breiten Splitter zwischen zwei Kiefern. Sie steckte im Wald, genau
	# wie der Leuchtturm eine Viertelstunde vorher. Auf einer bewaldeten Insel braucht
	# JEDES Bauwerk seine Lichtung, sonst ist es gebaut und trotzdem nicht da.
	flat_zones.append({"pos": Vector3(28560, 95.0, -10680), "r_flat": 150.0,
		"r_blend": 280.0, "y": 95.0})
	flat_zones.append({"pos": village_pos, "r_flat": 140.0, "r_blend": 340.0, "y": 120.0})
	# --- NEUE VIERTEL aus den Blender-Gebaeuden (scripts/CityBuilder.gd) ---------------
	# Jedes braucht eine Einebnung, sonst stehen Hochhaeuser auf einem Hang.
	var city_pos := Vector3(4300, 0, 2500)      # Grossstadt mit Skyline
	var indu_pos := Vector3(3500, 0, -1500)     # Industriehafen
	var dorf_pos := Vector3(-2300, 0, 1900)     # Landdorf
	var burg_pos := Vector3(-1750, 0, 3150)     # Burgberg
	var mil_pos := Vector3(250, 0, -2400)       # Militaerposten (bei der FLAK-ZONE)
	# HOCHHAUSVIERTEL. Bewusst weit weg von allem anderen: naechster Nachbar ist der
	# Industriehafen 2,5 km entfernt, die Grossstadt liegt 6,6 km weg. Es soll ein ORT
	# sein, zu dem man hinfliegt, und keine Erweiterung eines vorhandenen.
	var sky_pos := Vector3(2600, 0, -3800)      # Hochhausviertel zum Durchfliegen
	flat_zones.append({"pos": city_pos, "r_flat": 480.0, "r_blend": 980.0})
	# GROSSZUEGIG EINGEEBNET, und das ist hier keine Bequemlichkeit: die Tuerme stehen auf
	# einem 1664 m breiten Raster und tragen KOLLISION. Auf welligem Grund staende ein Teil
	# von ihnen im Hang und die Gassen waeren an manchen Stellen unpassierbar, ohne dass man
	# es vor dem Einflug sehen koennte.
	# MIT RECHTECK, NICHT NUR MIT RADIUS. _open_ground deckelt den Freihalte-Radius einer
	# KREIS-Zone bei CLEAR_CAP (620 m) — das Viertel ist aber 1536 m breit, und in seinem
	# aeusseren Ring stand deshalb Wald zwischen den Hochhaeusern. Der Rechteck-Zweig kennt
	# diesen Deckel nicht; er ist genau fuer solche Flaechen da.
	flat_zones.append({"pos": sky_pos, "r_flat": 1150.0, "r_blend": 1900.0,
		"heading": 0.0, "rects": [[0.0, 0.0, 880.0, 880.0]]})
	flat_zones.append({"pos": indu_pos, "r_flat": 300.0, "r_blend": 700.0})
	flat_zones.append({"pos": dorf_pos, "r_flat": 260.0, "r_blend": 620.0})
	flat_zones.append({"pos": burg_pos, "r_flat": 160.0, "r_blend": 420.0, "y": 78.0})
	flat_zones.append({"pos": mil_pos, "r_flat": 200.0, "r_blend": 480.0})
	var see_p := _tal_punkt(SEE_LAENGS)
	var lakes := [{"pos": lake_pos, "r": 175.0, "surf": -1.0},
		{"pos": Vector3(-3300, 0, 5250), "r": 260.0, "surf": -2.0},   # Canyon-Endsee
		# BERGSEE im Hochtal. Liegt zwischen Felsentor und Flugplatz und ist beim Anflug
		# der Punkt, an dem man weiss, dass die Bahn gleich kommt.
		# "form_achse" schaltet den GELAPPTEN Umriss ein (TerrainWorld._see_umriss_bauen):
		# Enge in der Mitte, schmaler Arm talaufwaerts, Buchten am Hauptbecken. SEE_R ist
		# damit nur noch der Massstab — der Arm reicht bis 2,35 * SEE_R hinaus.
		# Die Achse zeigt talaufwaerts zum Flugplatz. An ihr haengt, wo Arm und Enge liegen
		# und welche Seite die steile Felsflanke mit dem schmalen Tuerkissaum ist.
		{"pos": Vector3(see_p.x, 0.0, see_p.y), "r": SEE_R, "surf": SEE_SPIEGEL,
			"form_achse": TAL_RICHTUNG}]
	# Erzwungene Formen: Bergmassiv (Bergdorf/Flussquelle) + VULKANINSEL + ARCHIPEL
	# draußen im Ozean als Ausflugsziele (Insel-Typ fällt am Rand unter den Meeresspiegel
	# -> echte Küsten mit Türkis-Schelf, egal welcher Seed).
	var massifs := [
		{"pos": Vector3(2400, 0, 1500), "r": 850.0, "peak": 205.0},
		# Burgberg. "glatt" haelt _massive_charakterisieren von ihm fern: auf ihm sitzt eine
		# Flachzone mit y = 78, und eine Spitze wuerde unter ihr durchstossen — die Burg
		# staende dann auf einem abgeschnittenen Kegel statt auf einer Kuppe.
		{"pos": burg_pos, "r": 420.0, "peak": 88.0, "glatt": true},
				# CANYON-FLANKEN: erzwungene Grate beidseits der Schlucht-Spline — der River-Carve
		# schneidet DANACH hindurch (Reihenfolge in height_at) -> echte Waende, seed-robust.
		{"pos": Vector3(-6725, 0, 1450), "r": 750.0, "peak": 245.0},
		{"pos": Vector3(-5875, 0, 950), "r": 750.0, "peak": 270.0},
		{"pos": Vector3(-5675, 0, 3050), "r": 750.0, "peak": 280.0},
		{"pos": Vector3(-4825, 0, 2550), "r": 750.0, "peak": 255.0},
		{"pos": Vector3(-4625, 0, 4350), "r": 700.0, "peak": 225.0},
		{"pos": Vector3(-3775, 0, 3850), "r": 700.0, "peak": 235.0},
		# DER VULKAN. Die Schluessel gehoeren zusammen und stehen deshalb hier beieinander;
		# was jeder einzelne tut, steht bei TerrainWorld.height_at (SCHICHTVULKAN, RIPPEN,
		# KRATER). Fehlt einer, faellt das Massiv auf die Inselform zurueck.
		# DER BERG WAR ZU BREIT FUER SEINE HOEHE — und das ist die Korrektur an der Runde
		# davor, deren Rechnung gleich darunter steht. Der Befund damals lautete "zu klein
		# fuer sein Umland", gemeint war GIPFELHOEHE; bekommen hat der Kegel BREITE, weil
		# die Rechnung r mit peak und crater_r gemeinsam skalierte. Ergebnis: peak 860 auf
		# r 1900, also 24 Grad mittlere Boeschung, und die unteren zwei Drittel liefen als
		# 10- bis 15-Grad-Rampe in die Ebene aus. Im Bild wirkte er dadurch gedrungen.
		# r 1900 -> 1350 BEI UNVERAENDERTEM peak. Die mittlere Boeschung peak/r geht damit
		# von 24 auf 32,5 Grad — der Bereich eines Schichtvulkans (31 bis 33) — und die
		# Gipfelhoehe bleibt, wo sie ist. Das ist ausdruecklich KEINE Ruecknahme der
		# Vergroesserung: peak bleibt 860, die Schuerze bleibt 240, der Gipfel steht
		# weiterhin bei rund 1100 m. Nur der Fussabdruck geht von 3000 auf 1960 m Radius.
		# DIE SCHUERZE ("apron") BLEIBT BEI 240 UND WIRD STEILER STATT KLEINER. Sie ist der
		# Hebel fuer HOEHE OHNE STEILHEIT (sie traegt unter dem Kraterrand rund 88 Prozent
		# ihrer Nennhoehe und faellt erst draussen ab), und an ihr zu sparen haette genau
		# die Gipfelhoehe gekostet, die stehenbleiben soll. Was sich aendert, steht bei
		# VULKAN_APRON_K: der Exponent geht von 0.55 auf 0.85 und zieht die Masse nach
		# innen, damit aus der Schuerze kein zweites flaches Vorland wird. Gerechnet steht
		# sie am Kegelfuss jetzt auf 69 statt 125 m — also genau auf der Baumgrenze
		# (VULKAN_BAUM_AUS, 68 m), und damit traegt das steile Profil bis kurz vor den Wald.
		# UEBER RUND 260 WIRD ES HEIKEL, und der Grund ist nicht die Optik: die Schuerze
		# schiebt das Kragenband (44 bis 68 m Hoehe) mit sich nach aussen, und ab einer
		# gewissen Hoehe schiebt sie es ueber VULKAN_KRAGEN_AUS hinaus. Dann faellt der
		# Waldguertel lautlos aus — die Probe dagegen ist tools/_vulkan_form.gd, WALDSAUM.
		# flanke 1.62 -> 1.15, UND DAS IST ERZWUNGEN, NICHT GESCHMACK. Der Exponent wirkt
		# auf die STRECKE vom Kraterrand zum Fuss, und die ist von 1280 auf 950 m
		# geschrumpft. Die Steigung direkt unter der Lippe ist peak * flanke / Strecke —
		# mit 1.62 waeren das 1.47, also 56 Grad, und der Kegel stuende als Turm da (die
		# alte Notiz "ueber 2 geht nicht, dann sind es 60 Grad" gilt weiter, nur ist die
		# Schwelle mit der kuerzeren Flanke nach unten gewandert). 1.15 ergibt nachgerechnet
		# 46 Grad unter der Lippe, 43 auf halber Flanke und 36 bei vier Fuenfteln: konkav,
		# und in derselben Kurvenform wie vorher, nur auf der kuerzeren Strecke.
		# crater_r 620 -> 400, UND DAS IST DER ZWEITE GRUND, WARUM DIE FLANKE NICHT ZUM TURM
		# WIRD: der Krater frisst die Flankenstrecke von oben weg. Bei 620 auf r 1350 blieben
		# nur 730 m Lauf fuer 860 m Fallhoehe, also 50 Grad im Mittel. Mit 400 sind es 950 m
		# und 42 Grad. Zugleich stimmt damit das VERHAELTNIS wieder: an der Vorlage
		# ausgemessen ist der Kraterradius rund ein Viertel des Kegelfussradius, bei 620 auf
		# 1350 waeren es 46 Prozent gewesen — eine Caldera, kein Schichtvulkankrater.
		# crater_depth 340 -> 215 ZIEHT MIT, und zwar damit die WANDNEIGUNG bleibt: die Wand
		# laeuft zwischen VULKAN_SOHLE (0.66) und 0.97 des Kraterradius, das sind bei 400 m
		# nur noch 124 m Lauf. Die gemessenen 60 Grad der letzten Runde ergeben darauf 215 m
		# Tiefe; mit den alten 340 stuende die Wand auf 70 Grad und die Schuessel waere
		# wieder der Trichter, gegen den sie gebaut wurde.
		# lavasee 96 -> 62 und schlot 42 -> 28 sind dieselbe Rechnung: beide sind Stufen IN
		# dieser Wand und muessen ihren Anteil daran behalten.
		# lippe 0.22 STATT 0.16, weil der Rand sonst als Bogen las: der Radius schwankte
		# gemessen zwischen 408 und 496 m (bei crater_r 460). Die HOEHE der Lippe bleibt
		# davon unberuehrt und schwankt um gut zwei Prozent — gezackt, nicht schief.
		# --- DER KRATER SOLL GESCHMOLZEN AUSSEHEN, NICHT NUR TIEF SEIN ------------------
		# Der zweite Befund derselben Abnahme, woertlich: "statt einer steilwandigen
		# Schuessel mit dunklem Boden und echtem Lavasee haben wir einen glatten Trichter,
		# der in einem kleinen flachen Orangefleck endet". Drei Zahlen antworten darauf,
		# und sie haengen zusammen:
		#   crater_depth 248 -> 340   die Wand hat mehr zu ueberwinden; zusammen mit
		#                             VULKAN_SOHLE 0.55 -> 0.66 steht sie jetzt auf 60 Grad
		#                             im Mittel statt auf 56 bei halb so kurzem Lauf.
		#   lavasee 96 (neu)          die Stufe von der Schuttsohle auf den Spiegel. Der See
		#                             fuellt die inneren drei Viertel der Sohle, und
		#                             height_at zieht auf ihm das Rauschen wieder ab — er
		#                             ist die einzige exakt waagerechte Flaeche des Berges.
		#   schlot 125 -> 42          der "kleine flache Orangefleck" WAR der Schlot. Er
		#                             ist jetzt nicht mehr die Antwort auf eine helle
		#                             Pfanne (die gibt es nicht mehr), sondern der Schlund
		#                             IM See — und ein tiefes Loch darin hiesse, der See
		#                             sei leergelaufen. Siehe VULKAN_SCHLOT_R.
		# DIE ALTE PROBE GILT WEITER, ist aber entspannt: tiefster Punkt im Krater jetzt
		# rund 560 m gegen FLORA_MAX_H 230 m. Faellt er darunter, waechst im Schlot ein
		# Waeldchen — tools/_vulkan_form.gd muss dort Waldanteil 0 melden.
		# scharte_ri = -2.0 zeigt nach -x/-z, also von den Abnahmekameras weg. Die Kerbe sitzt
		# damit im FERNEN Kraterrand und schneidet in die Gipfelsilhouette; auf der nahen
		# Seite haette man von ihr nur die Innenwand gesehen, die ohnehin der Rand verdeckt.
		# DIE DREI ZAHLEN rippen / fels / barranco TEILEN SICH EINE FLANKE, und ihr
		# VERHAELTNIS ist wichtiger als jede einzelne. Hier stand 72 / 22 / 48, also die
		# Rauschlage anderthalbmal so hoch wie die gerechneten Rinnen — und genau das hat ein
		# fremder Blick auf das Abnahmebild als "glatter Kegel mit dunklem Schlierenmuster"
		# gemeldet: Gelaende war reichlich da, aber es war RICHTUNGSLOS. Zehn Rauschlappen mit
		# vier Oktaven ergeben Beulen, keine Rippen; die 32 Barrancos lagen als Kraeuselung
		# darauf und waren aus der Referenzentfernung nicht mehr zu zaehlen.
		# JETZT FUEHREN DIE RINNEN: barranco 78 gegen rippen 56. Damit ist die Gliederung des
		# Kegels gerechnet (zaehlbar, radial, mit einem Anfang am Kraterrand und einem Ende im
		# Apron), und das Rauschen tut nur noch das, was ein Rauschen kann — die Flanken der
		# Rinnen aufrauen, damit sie keine Blechrinnen sind.
		# BEIDE SIND MIT DEM BERG GEWACHSEN (62/44 -> 78/56, also derselbe Faktor 1.26), und
		# das ist kein Automatismus, sondern folgt aus ihrer Bauart: die Rinnenzahl ist fest
		# (VULKAN_BARR_N, 32), der Rippenkreis haengt an md/mr. Beide Muster werden mit dem
		# Kegel BREITER — 32 Rinnen auf 1250 m Fussradius sind 245 m je Rinne statt 167. Ein
		# gleich tiefes Muster auf anderthalbfacher Breite ist flacher, und im Bild sieht ein
		# flacheres Muster nicht nach einem groesseren Berg aus, sondern nach einem glatteren.
		# DAS VERHAELTNIS 0.72 BLEIBT, und das ist der Punkt: die Rinnen fuehren weiter.
		# 78/56 -> 55/40, WEIL DIESELBE RECHNUNG JETZT RUECKWAERTS LAEUFT: der Fussradius
		# geht von 1900 auf 1350, eine Rinne ist am Fuss damit 265 statt 373 m breit, und
		# eine gleich tiefe Rinne auf zwei Dritteln der Breite ist eine Klamm. Faktor 0.71
		# auf beide, das Verhaeltnis 0.72 bleibt unangetastet.
		# UND ES IST ZUGLEICH DIE ANTWORT AUF EINEN BEFUND, DEN DREI RUNDEN FALSCH GELESEN
		# HABEN. Gemeldet wurde fuenfmal "die Flanke ist glatt, es fehlt radiale Geometrie",
		# und dreimal wurde daraufhin mehr davon eingebaut. Gemessen (tools/_vulkan_rippen.gd)
		# standen zuletzt 22 bis 30 Grat-Rinne-Paare je Ring bei 83 bis 129 m Amplitude —
		# MEHR, als die Abnahmen selbst verlangt hatten (20 bis 30 Paare bei 25 bis 40 m).
		# Die Grossform war also nie das Problem, und noch mehr davon war jedesmal die
		# falsche Kur. Was fehlt, ist die kurze Welle, und die steht jetzt in "nasen".
		# fels 22 -> 30 IST DIE GEGENRECHNUNG DAZU, und sie gehoert zum Krater: die Rippen
		# beissen oben in die Lippe (VULKAN_RIPPEN_LIPPE) und machen sie gezackt. Nimmt man
		# ihnen ein Drittel Amplitude, wird die Krone wieder gedrechselt. Die Felslage haengt
		# an sv, steht also oben am staerksten und liegt auf Lippe UND Kratersohle — sie
		# ersetzt dort genau das, was die Rippen abgeben, ohne auf der Flanke wieder Beulen
		# zu machen (150 m Welle, das sind Facetten, keine Lappen).
		# barranco 78 ist die TIEFE der Erosionsrinnen in Metern, Grat gegen Sohle, mal der
		# Tiefenstreuung (VULKAN_BARR_TIEF_MIN, jetzt 0.64) also 50 bis 78 m. Bei 48 mit
		# Streuung ab 0.50 war die flachste Rinne 24 m tief und damit auf halber Flanke
		# (160 m Rinnenbreite) eine 17-Grad-Mulde — die wirft bei hochstehender Sonne keinen
		# Schatten und verschwand im Rippenrauschen daneben. Ab rund 27 Grad Rinnenwand
		# steht sie im eigenen Schatten, und dieselbe Rechnung ergibt auf der jetzt 1.52-mal
		# breiteren Rinne eben 78 statt 62 m.
		# DIE ALTE OBERGRENZE VON 65 IST MITGEWANDERT, und zwar aus dem Grund, aus dem sie
		# gezogen war: der Grat traegt zwei Drittel der Tiefe nach OBEN (bei 78 also 52 m),
		# und darunter muss genug Berg stehen. Am Auslaufpunkt der Barrancos
		# (VULKAN_BARR_AUS_AB, 0.87 * r = 1653 m) steht der Kegel jetzt 61 m und die
		# Schuerze darunter weitere 114 m hoch — zusammen 175 statt der frueheren 85. Ohne
		# die Schuerze waeren 78 m dort ein Zackenkranz.
		# apron_rippen 76 SETZT DIESE RINNEN NACH AUSSEN FORT, in derselben Phase (siehe
		# VULKAN_APRON_RIP_AB).
		# HIER STANDEN ZUERST 38, mit der Begruendung, die Schuerze sei flach und vertrage
		# keine tiefen Rinnen. GEMESSEN AM FERTIGEN BILD war das falsch herum: der Faecher
		# kam auf einen mittleren Helligkeitssprung von 0.0039, die Vorlage steht am selben
		# Ort bei 0.0274 — ein Tuch, kein Gelaende. Der Grund ist die BREITE: eine Rinne ist
		# draussen 470 m breit, 38 m Tiefe darauf sind 9 Grad Rinnenwand, und ueber 470 m
		# liest das Auge 9 Grad als Woelbung und nicht als Rinne. 76 m sind rund 18 Grad, und
		# damit steht die abgewandte Wand im eigenen Halbschatten.
		# TIEFER GEHT NICHT: das Rinnenprofil ist um seinen Mittelwert zentriert, die Sohle
		# liegt also ein Drittel der Tiefe unter der Schuerze — bei 76 sind das 25 m, und am
		# aeusseren Saum ist die Schuerze selbst nur noch 20 bis 30 m maechtig. height_at
		# faengt das mit einem maxf gegen null ab (dort steht, warum), aber ein Faecher, der
		# ueberall an dieser Klammer haengt, ist unten wieder flach.
		# apron_bloecke 15 IST DIE ZWEITE HAELFTE DERSELBEN ANTWORT: die kurze Welle. Sie
		# liegt auf derselben 46-m-Lage wie "bloecke" auf der Flanke und setzt genau dort an,
		# wo die dort auslaeuft. Warum sie vor dem Waldkragen aufhoeren muss, steht bei
		# VULKAN_APRON_BLOCK_AB — es ist dieselbe Falle wie bei "bloecke" selbst.
		# 20 -> 15, WEIL DER FAECHER FLACH IST. Dieselbe Lage steht auf der Flanke mit 32 m
		# gut da: dort sitzt sie auf 30 bis 45 Grad Hang und bricht ihn auf. Auf 5 Grad
		# Grundneigung wird aus derselben Amplitude etwas anderes — freistehende Pyramiden
		# auf einer Ebene, im Bild ein Blockfeld statt eines Aschefaechers.
		# ader_tief 26 ist die Tiefe des LAVAKANALS, Damm gegen Sohle. Er ist die Antwort auf
		# den einen Befund, an dem die Lava zweimal gescheitert ist: sie lag als Farbe OBEN
		# AUF der Flanke. Das Lavanetz ist ein Baum (acht Staemme, zwei Gabelungen), es
		# laeuft also quer ueber Barranco-Grate hinweg — eine gluehende Linie auf einer Kante
		# ist noch aufgemalter als eine auf einer Flaeche. Der Kanal schneidet sich seine
		# eigene Mulde und legt den Aushub als Damm daneben; erst damit hat die Ader einen
		# Boden, in dem sie liegen kann, und einen Rand, der Schatten wirft.
		# TIEFER ALS 35 GEHT NICHT: am Stamm sitzt der Kanal auf einem Barranco-Grat, und
		# wenn er mehr abtraegt, als der Grat hoch steht (2/3 * 62 = 41 m), reisst er dort
		# eine Kerbe durch die Oberflanke. Nach unten faellt er von selbst flacher aus, weil
		# die Tiefe an der Aderbreite haengt — sonst staende am Fuss eine Klamm.
		# 22 -> 26, weil die Ader schmaler geworden ist (VULKAN_ADER_KERN): eine 30 m breite
		# Rinne mit 22 m Tiefe liest sich noch als Mulde, eine 15 m breite braucht mehr
		# Fallhoehe, damit ihr Rand ueberhaupt eine Kante hat, die Schatten wirft.
		# lava_lappen 30 ist die Hoehe der erkalteten Lappen, in denen die Adern am Fuss
		# ENDEN, also knapp vier Bloecke. Ohne sie hoerte jede Ader irgendwo auf, und das
		# liest sich als abgeschnitten statt als ausgelaufen. Hoeher wird es ein Wall: die
		# Lappen stehen am Kegelfuss, wo der Kegel selbst nur noch rund 30 m hoch ist — die
		# Schuerze traegt dort allerdings weitere 90, deshalb sind aus 24 jetzt 30 geworden.
		# bloecke 26 IST DIE ANTWORT AUF DEN LETZTEN BEFUND, und der war messbar: "Flanken
		# sind strukturlos, glatte einfarbig dunkelblau-schwarze Facetten". Gemessen an den
		# beiden Bildern lag der mittlere Helligkeitssprung von Pixel zu Pixel bei uns auf
		# einem Viertel dessen der Vorlage (0.008 gegen 0.030), waehrend der MEDIAN der
		# Flanke fast doppelt so hell stand (0.209 gegen 0.114). Der Flanke fehlten also
		# beide Enden zugleich: die schwarzen Schattenschlitze und die hellen Kanten. Alle
		# drei vorhandenen Lagen sind gross gegen ein 8-m-Dreieck und kippen die Flaeche nur
		# um wenige Grad je Zelle — deshalb die grossen glatten Felder.
		# 26 M AUF 46 M WELLE (VULKAN_BLOCK_M) stellen die Blockflanke rund 38 Grad ueber den
		# Hang, auf dem sie sitzt. Das ist die Schwelle, ab der eine Facette bei diesem
		# Sonnenstand (50 Grad Hoehe) entweder Streiflicht faengt oder im eigenen Schatten
		# steht — darunter variiert sie die Hangneigung nur.
		# HIER STANDEN ZUERST 18, UND DAS WAR ZU WENIG: im Bild wurde der Umriss zackig, die
		# Flanke davor blieb glatt. Die Schwelle (VULKAN_BLOCK_AB) schneidet einen Teil der
		# Amplitude weg, bevor sie aufgetragen wird — 18 m standen am Ende nur rund 22 Grad
		# ueber dem Hang. Gemessen am fertigen Bild ist der mittlere Helligkeitssprung von
		# Pixel zu Pixel mit 26 m auf 0.015 gegangen, mit 18 m stand er auf 0.011.
		# DIE SCHRANKE NACH OBEN WAR DER WALDKRAGEN, und sie ist nachgemessen statt
		# geschaetzt: die Bepflanzung duennt nach dem Hoehenunterschied ueber der 8-m-Zelle
		# aus und faellt ueber 4,6 m ganz aus. Die Lage lief schon oberhalb des Kragens aus
		# (VULKAN_BLOCK_AUS_AB, 0.72 .. 0.86 * r), aber ihre Auslaufzone reichte in dessen
		# Oberkante hinein — deshalb standen hier lange 26 m.
		# 26 -> 32, WEIL DER KRAGEN UMGEZOGEN IST. Er sitzt in einer HOEHENLAGE (26 bis
		# 82 m), und die liegt seit der Schuerze nicht mehr am Kegelfuss, sondern draussen
		# auf dem Faecher bei rund 1.15 bis 1.28 * r. Zwischen der Auslaufzone der Blocklage
		# und der Oberkante des Kragens liegen jetzt gut 500 m; die Schranke bindet nicht
		# mehr. WER SIE WIEDER BINDEN LAESST — indem er den Kragen nach innen holt oder die
		# Lage nach aussen zieht —, muss die Probe wiederholen (tools/_vulkan_form.gd,
		# WALDSAUM: Deckung 0.85, Uebergangsband unter 20 m, kein echtes Loch). Der Kragen
		# faellt lautlos aus, ohne dass sich am Gestein etwas aendert.
		# DIE SCHUTTLAGE DER SCHUERZE HAT DIESE SCHRANKE GEERBT und deshalb eine eigene,
		# engere Ausblendung (VULKAN_APRON_BLOCK_AUS_AB) — sie laeuft ja mitten durch den
		# Kragen.
		# rand_h 44 statt 32: die Lippe ist ein Grat auf der Kante und soll im Umriss zu
		# sehen sein. Ihre Hoehe muss deshalb mit dem Krater wachsen, sonst ist sie auf
		# einem 1240 m weiten Ring ein Saum von wenigen Bildpunkten. 32 * 1.36 = 44.
		# 44 -> 36 ZIEHT MIT DEM KLEINEREN KRATER MIT (620 -> 400), aus genau demselben
		# Grund, nur andersherum: der Ring misst jetzt 800 statt 1240 m Durchmesser, und ein
		# gleich hoher Wall darauf waere im Umriss ein Kamm statt eines Saums.
		# --- DIE KURZE WELLE: "nasen" --------------------------------------------------
		# SIE IST DIE ANTWORT AUF DEN BEFUND, AN DEM DREI RUNDEN GESCHEITERT SIND. Alle
		# vorhandenen Lagen sind GROSSFORM: Rippen (rund 10 im Umfang), Barrancos (265 m am
		# Fuss), Felslage (150 m). Ueber die sichtbare Kegelbreite sind das sechs bis acht
		# Wellen — eine Gliederung, keine Koernung. Was der Vorlage aus der Naehe ihr
		# Felsaussehen gibt, sind Rippenbrueche und Abrisskanten von wenigen Dutzend Metern.
		# 13 M AUF DER 34-M-WELLE (VULKAN_GRUS_M) sind rund 68 Grad Steilkante an der
		# Abrissstufe. Warum ausgerechnet 34 m und nicht die 8 bis 20, die naeher am
		# Wunsch waeren: das Gelaendenetz hat 8 m Maschenweite, eine 20-m-Welle sind also
		# 2,5 Zellen — das ist keine Kante mehr, sondern Flimmern (dieselbe Grenze, vor der
		# schon VULKAN_FELS_M und VULKAN_BLOCK_M warnen). 34 m sind gut vier Zellen und
		# damit die kuerzeste Welle, die auf diesem Netz noch eine eigene Flanke hat.
		# SIE TEILT SICH IHR RAUSCHEN MIT DER GRUS-FARBLAGE, und das ist der eigentliche
		# Griff: die Koernung, die bisher NEBEN der Form lag und deshalb als "helle Striemen"
		# gemeldet wurde, sitzt jetzt auf ihr. Naeheres bei VULKAN_NASEN_AB.
		# --- UND "feinrippen" 15, DIE RICHTUNG DAZU -------------------------------------
		# DIE ABRISSKANTEN ALLEIN WAREN NICHT GENUG, und das steht hier, damit es niemand
		# noch einmal probiert: mit ihnen allein war die Zielzahl der Abnahme erreicht
		# (lokale Streuung 0.0348 gegen 0.030 gefordert) und das Bild trotzdem falsch — das
		# helle Gestein lag als runde, isolierte Flecken auf der Flanke, also als
		# aufgestreuter Kies. Die Vorlage zeigt LANGE, HANGPARALLELE Baender. Eine isotrope
		# Lage kann die nicht machen, egal wie fein oder wie stark man sie stellt.
		# 15 M SIND BEWUSST WENIG — rund ein Drittel der groben Rippen. Diese Lage soll die
		# Flanke nicht noch einmal gliedern (davon hat sie genug, siehe oben), sondern der
		# Aufhellung eine Richtung geben; die Arbeit macht VULKAN_FEINRIPPE_HELL. Mehr
		# Amplitude waere die vierte Grossformlage, und drei Runden haben gezeigt, dass
		# davon nichts besser wird.
		{"pos": Vector3(11800, 0, -5600), "r": 1350.0, "peak": 860.0, "type": "vulkan",
			"apron": 240.0, "apron_rippen": 54.0, "apron_bloecke": 15.0,
			"flanke": 1.15, "rippen": 40.0, "fels": 26.0, "fuss": 0.11,
			"barranco": 55.0, "ader_tief": 26.0, "lava_lappen": 26.0, "bloecke": 32.0,
			"nasen": 13.0, "feinrippen": 15.0,
			"crater_r": 400.0, "lippe": 0.22,
			"rand_h": 36.0, "crater_depth": 215.0, "lavasee": 62.0, "schlot": 28.0,
			"scharte": 1.0, "scharte_ri": -2.0},
		# INSELN — MIT DER KUESTE NACH AUSSEN GEZOGEN UND ZU EINER KETTE ERGAENZT.
		#
		# Die fuenf alten Positionen (16000/-3800 und so fort) lagen bei 11,5 bis 16 km und
		# waren damit Inseln vor der alten Kueste. Nach dem Vergroessern der Insel auf
		# 25,8 km mittleren Radius waren es Huegel MITTEN IM LAND — dieselbe Regression wie
		# bei den Schiffen, nur unauffaelliger, weil ein Huegel nicht falsch aussieht.
		#
		# Die neuen Punkte liegen alle in 24 m tiefem Wasser mit freiem 1600-m-Ring
		# (gemessen, tools/_inselplatz.gd) — eine Insel, die mit dem Festland zusammen-
		# waechst, ist eine Halbinsel und keine.
		#
		# DIE VIER ZUSAETZLICHEN bilden vor der Ostkueste eine KETTE. Das ist der Grund,
		# warum es sie gibt: acht Kilometer neue Strecke ohne ein einziges Ziel waeren
		# blosse Leere gewesen. Eine Kette gibt dem Tiefflug ueber See eine Linie, an der
		# man sich entlanghangelt, und den beiden hoeheren Kuppen die Rolle von Marken.
		{"pos": Vector3(27244, 0, -6468), "r": 520.0, "peak": 40.0, "type": "insel"},
		{"pos": Vector3(21197, 0, -19498), "r": 500.0, "peak": 34.0, "type": "insel"},
		# 31,0 STATT 29,5 KM. Gemessen (tools/_seelage2.gd) lag der Rand dieser Insel
		# nach der Vergroesserung bei -0,9 m, also 5 m UEBER dem Spiegel (SEA_Y = -6):
		# sie war ueber eine Untiefe mit dem Festland verwachsen und damit eine
		# Halbinsel.
		{"pos": Vector3(-20541, 0, 23219), "r": 700.0, "peak": 55.0, "type": "insel"},
		# 30,8 STATT 28,2 KM: durch die groessere Kueste (27200 statt 26000) lag diese
		# Insel bei 148 Grad plötzlich 300 m INNERHALB der Wasserlinie und war damit ein
		# Kuestenhuegel. Gemessen mit tools/_kuestenlage.gd; derselbe Fehler wie bei der
		# letzten Vergroesserung, nur diesmal beim ersten Nachmessen gefunden.
		{"pos": Vector3(-26183, 0, 16219), "r": 430.0, "peak": 24.0, "type": "insel"},
		{"pos": Vector3(6692, 0, -27799), "r": 600.0, "peak": 45.0, "type": "insel"},
		{"pos": Vector3(29400, 0, -3200), "r": 360.0, "peak": 26.0, "type": "insel"},
		{"pos": Vector3(28600, 0, -10600), "r": 780.0, "peak": 88.0, "type": "insel"},
		{"pos": Vector3(25200, 0, -14900), "r": 340.0, "peak": 19.0, "type": "insel"},
		{"pos": Vector3(30100, 0, -7600), "r": 610.0, "peak": 66.0, "type": "insel"},
	]
	massifs.append_array(_hochgebirge())
	_massive_charakterisieren(massifs)
	# ECHTER FLUSS: Spline von der Bergquelle (hoch) bis in den See (tief).
	# Punkte = (x, Wasserhöhe, z); Höhe fällt monoton -> fließt bergab.
	var rivers := [{
		# CANYON DES WESTENS: extrem breites/tiefes "Flusstal" = durchfliegbare Schlucht
		# (die Distanz-Rampe macht dort echte Berge -> hohe Waende links und rechts).
		# DAS TALBAND WAR 260 M BREIT UND HAT DIE SCHLUCHT SELBST EINGEEBNET.
		# _river_carve zieht im ganzen Band die Ufer auf Wasserhoehe + 1,2 m; bei 260 m
		# heisst das, dass links und rechts je ein Viertelkilometer flachgelegt wird — und
		# gemessen (tools/_fluss_schnitt.gd) stand das Gelaende bei 90 m Abstand nur 6,3 m
		# ueber dem Wasser. Die Kamera "IN die Schlucht" zeigte deshalb ein breites, flaches
		# Flusstal ohne Waende, obwohl der Eintrag hier "durchfliegbare Schlucht" verspricht.
		# Mit 110 m bleibt der Talboden breit genug zum Durchfliegen (die Spannweite der
		# Bausatzflugzeuge liegt bei rund 12 m), und die Flanken der sechs Canyonmassive
		# stehen wieder da, wo sie hingehoeren: direkt am Wasser.
		"w": 40.0, "valley": 110.0, "depth": 7.0,
		# MAEANDER. Aus der Luft war die Schlucht ein schnurgerades blaues Band von gleicher
		# Breite quer durch die halbe Karte — die auffaelligste kuenstliche Linie der Welt,
		# weil acht Stuetzpunkte eben acht Geraden sind. 130 m Auslenkung bleiben INNERHALB
		# des 260-m-Talbandes: die Schlucht windet sich, ihre Waende bleiben aber dieselben
		# Massive und reissen nicht auf.
		"maeander": 130.0, "maeander_welle": 1500.0,
		"pts": [
			Vector3(-6600, 46, 900), Vector3(-6050, 34, 1900), Vector3(-5250, 22, 2800),
			Vector3(-4450, 12, 3700), Vector3(-3800, 8, 4500), Vector3(-3380, 4, 5100),
		],
	}, {
		"w": 13.0, "valley": 55.0, "depth": 4.0,
		# Derselbe Grund wie beim Canyon, nur eine Nummer kleiner: 70 m Auslenkung auf 700 m
		# Wellenlaenge geben dem Tieflandfluss die Boegen, die ein Fluss in der Ebene hat.
		"maeander": 70.0, "maeander_welle": 700.0,
		"pts": [
			Vector3(2545, 112, 1760), Vector3(2330, 82, 1600), Vector3(2110, 56, 1460),
			Vector3(1900, 35, 1320), Vector3(1710, 20, 1210), Vector3(1560, 8, 1130),
			Vector3(1460, 1, 1075), Vector3(1430, -1, 1030),
		],
	}, {
		# ZUFLUSS DES BERGSEES: Wildbach von der steilen Felsflanke herunter in den ARM.
		#
		# DIE HOEHEN IN DER LISTE SIND NULLEN UND BLEIBEN ES. Sie kommen aus
		# TerrainWorld.seebaeche_einpassen(), das sie nach dem Aufbau am Gelaende abliest —
		# "seebach": 1 markiert den Bach dafuer. Hier standen frueher zwoelf von Hand
		# abgelesene Werte (266, 208, 166, ...), und die waren beim naechsten Eingriff ins
		# Hochtal wertlos: _river_carve SETZT die Hoehe, eine Spline ueber dem Gelaende
		# schuettet also einen Damm auf und eine darunter graebt eine Schlucht.
		# DIE RICHTUNG IST WIEDER GEMESSEN. Der alte Lauf schwenkte am Ende auf die Talachse
		# und muendete in die Spitze des Arms — dort steht aber der Riegel, der das Becken
		# talaufwaerts abschliesst: gemessen 101 m bei 0 Grad und 122 bis 128 m bei 12 bis
		# 15 Grad, waehrend der Bach dahinter in einer Senke auf 96 m lag. Er musste also
		# ueber einen Buckel und stand gemessen 13,4 m ueber dem Boden — ein Damm quer durch
		# den Hang. Im Sektor 22 bis 34 Grad faellt das Gelaende dagegen von 240 m bei
		# 1400 m Abstand bis 93 m bei 600 m LUECKENLOS ab; dort liegt der Bach von selbst.
		# Schmaler als die anderen Fluesse (w 9 statt 13) und mit engem Talband: valley 26
		# haelt den Uferwall des Carves aus dem See heraus. Die Muendung steht deshalb 81 m
		# hinter der Uferlinie — naeher wuerde sie den Seegrund auf Wasserhoehe + 1,2 m
		# anheben und ein Stueck Ufer wegnehmen.
		# DIE MUENDUNG IST VON 400 AUF 312 M GEWANDERT, und beides hat einen eigenen Grund.
		# Erstens der Umriss: mit der Eiform liegt das Ufer bei 27 Grad auf 279 statt 319 m,
		# die alten 400 m waeren 121 m NEBEN dem See gewesen. Zweitens stand dort ein
		# 8,1 m hoher Beckenrand zwischen Bach und Wasser — im Bild endete der Zufluss im
		# Wald, und der See hatte sichtbar keinen Speiser. Der Rand hat jetzt eine Kerbe
		# (TerrainWorld.SEE_ZUFLUSS_GRAD, Delta auf Spiegel + 0,9 m), und die Muendung steht
		# 33 m hinter der Uferlinie darauf.
		# NAEHER GEHT NICHT: _river_carve zieht im Talband (valley 26) die Ufer auf
		# Wasserhoehe + 1,2 m, ein Stueck Seeufer waere sonst zugeschuettet.
		# depth 0.9 statt 1.3: die Muendung liegt per Formel auf Spiegel + Tiefe + 0,2 m
		# (seebaeche_einpassen — flacher darf sie nicht, sonst zapft das Bett den See an).
		# Jeder Meter Tiefe hebt damit den Wasserspiegel des Baches an der Muendung um einen
		# Meter UEBER den See. Mit 0,9 m ist die Stufe 1,1 m und liest sich als Delta; mit
		# 1,3 m waren es 1,5 m und der Bach stand sichtbar ueber dem See.
		"w": 9.0, "valley": 26.0, "depth": 0.9, "seebach": 1, "max_tief": 14.0,
		# Die Punkte stehen bewusst DICHT und mit wechselndem Winkel: mit sechs Stuetzstellen
		# lief der Bach im Bild als Lineal quer ueber die Flanke.
		"pts": [
			_see_punkt(35.0, 1500.0, 0.0), _see_punkt(34.0, 1370.0, 0.0),
			_see_punkt(33.0, 1240.0, 0.0), _see_punkt(32.0, 1120.0, 0.0),
			_see_punkt(31.0, 1010.0, 0.0), _see_punkt(30.0, 900.0, 0.0),
			_see_punkt(29.0, 800.0, 0.0), _see_punkt(28.0, 700.0, 0.0),
			_see_punkt(27.0, 600.0, 0.0), _see_punkt(27.0, 495.0, 0.0),
			_see_punkt(27.5, 430.0, 0.0), _see_punkt(27.0, 380.0, 0.0),
			_see_punkt(26.5, 345.0, 0.0), _see_punkt(27.0, 312.0, 0.0),
		],
	}, {
		# ABFLUSS DES BERGSEES: ueber die Scharte im Beckenrand und die Talstufe hinunter.
		#
		# DIE LINIE IST GEMESSEN, NICHT GEZEICHNET. tools/_see_pass.gd sucht auf dem
		# GEWACHSENEN Gelaende (ohne See, ohne Fluesse) den Weg vom Ufer ins Tal, dessen
		# HOECHSTER Punkt am niedrigsten liegt — Dijkstra mit max() statt Summe, also genau
		# das, was auch Wasser tut. Ergebnis ab der Scharte (140 Grad, siehe
		# TerrainWorld.SEE_ABFLUSS_GRAD): der Flaschenhals liegt bei 75,4 m und damit 2,6 m
		# UNTER dem Seespiegel. Der Bach muss also gar nichts anschneiden — suedoestlich des
		# Sees zieht eine gewachsene Rinne (56 bis 75 m) im Bogen von 146 auf 173 Grad, und
		# die Punkte hier liegen darin. Deshalb wandert der Winkel mit dem Abstand.
		# Die alte Linie ging bei 161 Grad aus dem Becken und musste dafuer erst eine Mulde
		# hinab und dann einen Riegel von 88,9 m anschneiden, also 20 m tief graben.
		#
		# Hoehen wieder aus seebaeche_einpassen() ("seebach": -1, flussabwaerts gerechnet).
		#
		# valley 70: der Bach durchschneidet weiter unten eine Stufe, und mit einem engen
		# Talband stand das als senkrechter Schlitz im Gelaende. 70 m macht daraus eine
		# Klamm mit geneigten Waenden.
		# tal_quelle 13 UND DER ERSTE PUNKT 28 M HINTER DER UFERLINIE sind die Rechnung aus
		# TerrainWorld.SEE_SCHARTE_BANK: der Boden bleibt hinter der Uferlinie 24 m lang ueber
		# dem Spiegel (Schwelle 16 m plus Kamm 0,60 m bei 7,5 Prozent Bankgefaelle), und so
		# weit muss der Bach wegbleiben, sonst senkt _river_carve die Schwelle auf Wasserhoehe
		# und laesst den See ab. _river_carve greift bis "w" neben der Spline mit voller Tiefe,
		# der Bachkopf senkt den Boden also erst 28 - 10 = 18 m hinter der Uferlinie. Gemessen
		# (tools/_see_abfluss.gd) bleibt damit ein geschlossener Riegel von 18 m ueber dem
		# Spiegel stehen, und tools/_see_form.gd meldet bei Schrittweite 2, 4 und 8 m
		# dieselbe Flaeche — die Schwelle ist also ein echter Damm und kein Rasterartefakt.
		# tal_quelle MUSS GROESSER ALS w SEIN: _river_carve rechnet k = smoothstep(w, tal, d),
		# und mit tal < w liefert smoothstep eine umgekehrte Rampe.
		# HIER STANDEN 470 M UND 18 M TALBAND, und der Bach hing trotzdem nicht am See: nicht
		# wegen des Abstands, sondern wegen der Fallhoehe. Gemessen lag sein erster Punkt auf
		# 64,6 m, also 13,4 m UNTER dem Spiegel, weil die Rinne dahinter mit 60 Prozent abfiel.
		# Mit der Kiesbank sind es rund 1,3 m — die zwei Wasserflaechen stehen praktisch auf
		# einer Ebene, und die Abflussbucht (TerrainWorld._see_umriss_faktor) schiebt das
		# Tuerkis noch 56 m auf die Schwelle zu.
		# Die Punkte auf den ersten 120 m stehen dicht: ueber die Kante der Talstufe zieht die
		# Spline sonst eine Sehne, und _river_carve haengt das Wasserband an die Sehne statt
		# an den Hang — im Bild eine schwebende Rampe.
		"w": 10.0, "valley": 70.0, "tal_quelle": 13.0, "tal_lauf": 260.0,
		"depth": 1.4, "seebach": -1, "max_tief": 14.0,
		"pts": [
			_see_punkt(151.0, 536.0, 0.0), _see_punkt(151.2, 546.0, 0.0),
			_see_punkt(151.5, 554.0, 0.0), _see_punkt(151.8, 562.0, 0.0),
			_see_punkt(152.2, 570.0, 0.0), _see_punkt(152.6, 582.0, 0.0),
			_see_punkt(153.2, 598.0, 0.0), _see_punkt(154.0, 620.0, 0.0),
			_see_punkt(155.0, 645.0, 0.0), _see_punkt(157.0, 668.0, 0.0),
			_see_punkt(159.0, 685.0, 0.0), _see_punkt(160.0, 725.0, 0.0),
			_see_punkt(161.0, 775.0, 0.0), _see_punkt(162.0, 820.0, 0.0),
			_see_punkt(164.0, 865.0, 0.0), _see_punkt(166.0, 895.0, 0.0),
			_see_punkt(167.5, 940.0, 0.0), _see_punkt(168.0, 1000.0, 0.0),
			_see_punkt(168.3, 1060.0, 0.0), _see_punkt(170.0, 1115.0, 0.0),
			_see_punkt(172.0, 1150.0, 0.0), _see_punkt(173.5, 1200.0, 0.0),
			_see_punkt(173.5, 1320.0, 0.0), _see_punkt(173.5, 1450.0, 0.0),
			_see_punkt(173.5, 1600.0, 0.0),
		],
	}]
	# TALKORRIDOR fuer die ALMWIESE (TerrainWorld._tal_wiese): die Felsschwelle der
	# Gelaendefarbe wandert im Hochtal nach oben, damit der Talboden gruen ist statt beige.
	# DAS BREITENPROFIL WIRD ABGETASTET UND UEBERGEBEN, nicht drueben nachgebaut: die
	# Keilform steht in _tal_halbbreite und gehoert hierher; eine zweite Kopie in
	# TerrainWorld waere beim naechsten Umbau still falsch geworden.
	var tal_hb := PackedFloat32Array()
	for i in 33:
		tal_hb.append(_tal_halbbreite(TAL_LAENGE * float(i) / 32.0))
	# SCHUTTHALDE DES FELSENTORS ANMELDEN — VOR setup(). Ueber ihr waechst nichts und es
	# gibt keine Almwiese. Das Wahrzeichen selbst entsteht erst weiter unten (es braucht
	# die Gelaendehoehe, die es ohne setup() nicht gibt), aber der Chunk-Worker laeuft ab
	# setup(), und die ersten Kacheln am Tor waeren sonst schon bepflanzt gewesen.
	# Die Form kommt aus Landmarks; build_felsentor holt sich unten dieselbe Zone.
	var tor_q := _tal_punkt(TOR_LAENGS)
	terrain.schutthalden = [Landmarks.tor_halde_zone(tor_q.x, tor_q.y,
		atan2(TAL_RICHTUNG.x, TAL_RICHTUNG.y), TOR_SPANN, TOR_SEED)]
	terrain.setup(game.world_seed, flat_zones, lakes, rivers, massifs,
		{"start": TAL_START, "richtung": TAL_RICHTUNG, "laenge": TAL_LAENGE,
			"halbbreite": tal_hb})
	# FELSWAND AM TALSCHLUSS. Ohne sie ist die Wand hinter ADLERHORST auf 480 m Breite
	# um ganze 34 m gegliedert (gemessen, tools/_wandprofil.gd) — eine Ebene, die im
	# Anflug 60 Prozent des Bildes fuellt und als Kulisse gelesen wird.
	# MITTE BEI 9700, NICHT AM PORTAL: die Zone soll die ganze sichtbare Flanke fassen,
	# und die reicht vom Wandfuss bei 9330 bis ueber den Kamm.
	# 200 BIS 340 M ALS HOEHENTOR: darunter liegt der eingeebnete Talboden und die
	# Portalstirn, die beide unberuehrt bleiben muessen.
	var wand_p := _tal_punkt(9700.0)
	var portal_p := _tal_punkt(ADLERHORST_KAVERNE_LAENGS)
	# ================================================================================
	# KUESTENFORMEN — was die Insel von einer Scheibe unterscheidet
	# ================================================================================
	#
	# WARUM ES SIE BRAUCHT. Die Kueste entstand bisher allein aus r_coast(winkel): EIN
	# Radius je Richtung. Eine solche Kurve kann keinen Fjord haben, keine Bucht mit
	# enger Einfahrt, keine Landzunge, die sich zurueckkruemmt — auf jedem Strahl gibt es
	# genau einen Wechsel von Land zu Wasser. Egal wie fein man das Winkelrauschen macht,
	# es bleibt eine gebeulte Scheibe. Die beiden Formen hier brauchen jeweils mehrere
	# Wechsel und sind deshalb ueber TerrainWorld.kuestenformen gebaut (Polylinien).
	#
	# WO SIE STEHEN, IST GEMESSEN, nicht geraten. tools/_kuestenlage.gd hat den Umriss in
	# 36 Sektoren abgetastet: der Korridor 190 bis 260 Grad ist zwischen 14 und 33 km
	# vollstaendig frei von Massiven, Plaetzen und Wahrzeichen — dort darf gebaut werden,
	# ohne bestehendes zu fluten. Dieselbe Messung hat auch die urspruengliche Idee
	# widerlegt, einen Fjord einfach ins Vorland zu schneiden: die Kueste ist RINGSUM
	# flach (3 und 6 km landeinwaerts ueberall zwischen -5 und +130 m). Ein Meeresarm in
	# flachem Land ist ein Kanal. Der Fjord muss seine Waende also mitbringen — deshalb
	# steht unter ihm ein eigenes Gebirge.
	terrain.kuestenformen = [
		# --- STURMKAP: ein Gebirgskap, 4 km weiter drausen als die uebrige Kueste ------
		#
		# Es traegt zwei Aufgaben auf einmal. Erstens macht es die Insel groesser, und
		# zwar dort, wo man es SIEHT — ein Kap, das aus dem Meer aufsteigt, aendert den
		# Umriss staerker als ein gleichmaessig groesserer Radius. Zweitens liefert es die
		# Waende fuer den Fjord, der es gleich darauf spaltet.
		#
		# Die Hoehen laufen von 120 m am Festlandsfuss ueber 840 m in der Mitte auf 240 m
		# an der Spitze. Ein Kamm mit KONSTANTER Hoehe waere eine Mauer; die Kurve macht
		# daraus eine Kette, die aus dem Land aufsteigt und ins Meer abtaucht.
		{
			"art": "land",
			# DER LETZTE PUNKT LIEGT AUF NULL, und das ist keine Kosmetik: jenseits des
			# Polylinienendes misst _kf_lage radial zum Endpunkt, die Form laeuft dort
			# also als Kuppel vom Radius r_aus weiter. Mit 240 m Resthoehe und 4,6 km
			# Reichweite hiess das ein 120-m-Huegel drei Kilometer DRAUSSEN IM MEER — im
			# Bild stand vor der Fjordeinfahrt Duenenland mit Nadelwald. Ein Stuetzpunkt
			# auf 0 laesst die Kette auslaufen, statt sie abzuschneiden.
			"pts": PackedVector2Array([
				Vector2(-12379, -13748), Vector2(-15282, -15825),
				Vector2(-18188, -17873), Vector2(-21209, -19778),
				Vector2(-23773, -20666), Vector2(-25511, -21558)]),
			"hs": PackedFloat32Array([120.0, 620.0, 840.0, 700.0, 240.0, 0.0]),
			"r_kern": 1500.0, "r_aus": 4600.0, "unruhe": 0.55,
		},
		# --- DER FJORD, der das Kap spaltet -------------------------------------------
		#
		# Er liegt auf der Kapachse (134 m Versatz in der Mitte, also praktisch mittig)
		# und schneidet es damit der Laenge nach in zwei Grate. Das ist der Punkt: von
		# aussen sieht man ein Kap, von innen fliegt man 13 km zwischen zwei 800-m-Waenden
		# auf Meereshoehe. So etwas gibt es sonst nirgends auf der Karte.
		#
		# DIE SOHLE HAT EINE SCHWELLE AM EINGANG (-18 m) und wird nach innen tiefer
		# (-78 m), bevor sie zum Talschluss ansteigt. Das ist kein Detailverliebtsein: ein
		# echter Fjord ist ein ausgeschliffenes Trogtal, dessen Gletscher am Ausgang seine
		# Endmoraene liegengelassen hat. Sichtbar wird es an der Wasserfarbe — der
		# Strandschelf faerbt flaches Wasser tuerkis, tiefes petrol. Man sieht die
		# Schwelle also von oben als hellen Riegel quer vor der Einfahrt.
		#
		# r_kern 320 / r_aus 780: 640 m offenes Wasser, und die Wand steigt darueber auf
		# 460 m Horizontale zur vollen Hoehe. Das sind rund 57 Grad — steil genug, dass
		# es eine Wand ist, flach genug, dass der Fels sich noch gliedert.
		{
			"art": "wasser",
			# DER ERSTE PUNKT LIEGT IM OFFENEN MEER (34,2 km), nicht am Kapfuss. Sonst
			# endet die Rinne innerhalb des Kaps und ihre letzten 900 m waeren durch
			# dessen auslaufende Flanke gestaut — ein Fjord, den man nicht befahren kann.
			# Die SCHWELLE sitzt deshalb als eigener Stuetzpunkt bei 32,2 km auf -16 m.
			"pts": PackedVector2Array([
				Vector2(-26199, -21983), Vector2(-24485, -20912),
				Vector2(-21347, -19629), Vector2(-18281, -17778),
				Vector2(-15338, -15772), Vector2(-13233, -14594)]),
			"hs": PackedFloat32Array([-24.0, -16.0, -62.0, -78.0, -52.0, -14.0]),
			"r_kern": 320.0, "r_aus": 780.0,
		},
		# --- DIE HAKENZUNGE mit ihrer Lagune ------------------------------------------
		#
		# Der Gegenentwurf zum Kap, auf der anderen Seite der Insel: kein Fels, sondern
		# ein flacher Sandhaken von 18 km Laenge, der sich zur Kueste zurueckkruemmt und
		# dabei ein Binnenmeer einschliesst. Zwischen seiner Spitze und dem Festland
		# bleiben rund 600 m Einfahrt.
		#
		# ER MUSS NICHT AUSGEHOEHLT WERDEN. Die Lagune entsteht von selbst: das Wasser
		# zwischen Kueste (dort bei 26 bis 27 km) und Haken (bei 28 bis 30 km) ist
		# ohnehin Meer — der Haken schliesst es nur ein. Das ist der ganze Gewinn der
		# Polylinienform gegenueber dem Radius.
		#
		# Hoehen von 90 m an der Wurzel auf 22 m an der Spitze: der Strandschelf verschleift
		# das zu breiten Sandbaenken, und genau so soll eine Nehrung aussehen.
		{
			"art": "land",
			# WEITER DRAUSSEN ALS IM ERSTEN ANLAUF, und das war der Unterschied zwischen
			# einer Lagune und gar nichts. Zuerst lief die Achse bei 25 bis 30 km, die
			# Innenflanke (1,5 km) reichte damit bis an den Schelf des Festlands heran —
			# gemessen mit tools/_kuestenprofil.gd blieb es auf der Peilung durch die
			# Lagune bei EINEM Land-Wasser-Wechsel: die Nehrung war mit der Kueste
			# verwachsen und das eingeschlossene Wasser aufgefuellt. Jetzt liegt sie 1,5
			# bis 2 km weiter aussen und ist mit r_aus 1100 schmaler.
			"pts": PackedVector2Array([
				Vector2(0, 26000), Vector2(-3084, 29338), Vector2(-7693, 30855),
				Vector2(-12582, 29640), Vector2(-15863, 26401), Vector2(-16928, 23300)]),
			# Die Spitze auf 12 m statt 22: auch hier laeuft die Form als Kuppel weiter,
			# und bei 22 m stand jenseits der Nehrung noch eine trockene Sandbank. Bei
			# 12 m verschwindet sie unter dem Strandschelf — also unter Wasser.
			"hs": PackedFloat32Array([90.0, 62.0, 46.0, 38.0, 30.0, 12.0]),
			"r_kern": 300.0, "r_aus": 1100.0, "unruhe": 0.25,
		},
	]
	terrain.felswaende = [{
		# 900 STATT 620: mit 620 lief die Radialblende schon bei 340 m aus, und im weiten
		# Blick auf den Talschluss standen die beiden Flanken links und rechts wieder
		# glatt neben der gegliederten Mitte. Der Talboden braucht keinen Schutz durch
		# einen kleinen Radius — dafuer sorgt das Hoehentor.
		"x": wand_p.x, "z": wand_p.y, "r": 900.0, "r2": 900.0 * 900.0,
		# 185 BIS 300 STATT 200 BIS 340: die Portalstirn endet 163 m ueber dem Meer
		# (Hallensohle 90,7 plus HB_STIRN_H), das Tor darf also knapp darueber oeffnen.
		# 150 BIS 240, UND DAS IST EINE FRAGE DES BILDAUSSCHNITTS, NICHT DES GESCHMACKS.
		# Die Anflugkamera steht 300 m vor der Wand auf 116 m Hoehe und hat 64 Grad
		# senkrechten Bildwinkel — sie sieht damit Gelaendehoehen von rund 46 bis 305 m.
		# Mit dem Tor bei 185 bis 300 lag das gesamte Relief AUSSERHALB dieses Bandes:
		# gemessen war die Wand danach siebenfach staerker gegliedert, im Bild aenderte
		# sich nichts. Bei 150 faellt der Einsatz knapp unter das Band und knapp ueber
		# die Portalstirn, die 163 m hoch endet.
		"h0": 150.0, "h1": 240.0, "amp": 1.6,
		# FREIHALTEKREIS NUR 40 M. Mit 170 m stand er genau ueber der sichtbaren Wand und
		# loeschte das Relief dort, wo es hin soll: gemessen blieb die Kruemmung bei
		# Talstation 9375 bei 1,45 m, waehrend sie weiter oben schon auf 7 m stand. Die
		# Stirn schuetzt das Hoehentor, nicht dieser Kreis — er faengt nur die letzten
		# Meter am Mund ab.
		"fx": portal_p.x, "fz": portal_p.y, "fr": 40.0,
	}]
	fly_world.add_child(terrain)
	terrain.build_now_around(Vector3.ZERO, 900.0)   # Spawn-Bereich sofort (Kollision!)
	# KARTE: Bild im Hintergrund-Thread generieren (~100k height_at-Samples, kein Startup-Ruckler;
	# height_at ist pure Noise-Mathematik und laeuft schon jetzt parallel im Chunk-Worker).
	_map_pois = [
		{"name": "Stadt", "pos": town_pos, "color": Color(0.95, 0.85, 0.35)},
		{"name": "Luftschiffwerft", "pos": factory_pos, "color": Color(0.58, 0.76, 0.82)},
		{"name": "Leuchtturm", "pos": lh_pos, "color": Color(0.95, 0.45, 0.40)},
		{"name": "Bergdorf", "pos": village_pos, "color": Color(0.80, 0.70, 0.55)},
		{"name": "Vulkan", "pos": Vector3(11800, 0, -5600), "color": Color(0.85, 0.35, 0.25)},
		{"name": "FLAK-ZONE", "pos": Vector3(250, 0, -2400), "color": Color(1.0, 0.25, 0.2)},
		{"name": "Canyon", "pos": Vector3(-5250, 0, 2800), "color": Color(0.90, 0.62, 0.30)},
		{"name": "Windpark", "pos": Vector3(-3900, 0, -700), "color": Color(0.75, 0.88, 0.95)},
		# AUF DAS ECHTE WRACK, nicht 7 km daneben. Das Etikett stand noch auf der
		# Position von vor der Inselvergroesserung, das Wrack selbst wurde damals mit der
		# Kueste hinausgerueckt (siehe Landmarks.build_wreck weiter unten) — das Schild
		# blieb zurueck und zeigte seither auf offenes Land.
		{"name": "Wrack", "pos": Vector3(26983, 0, -7477), "color": Color(0.62, 0.42, 0.30)},
		# --- Die neuen Kuestenformen als Ziele auf der Karte ---------------------------
		#
		# OHNE MARKE FINDET SIE NIEMAND. Der Fjord liegt 32 km vom Startplatz und ist von
		# aussen nur ein Spalt zwischen zwei Bergen; wer nicht weiss, dass er da ist,
		# fliegt daran vorbei. Dasselbe gilt fuer die Lagune hinter der Nehrung — vom
		# Festland aus sieht man nur Wasser, nicht dass es eingeschlossen ist.
		{"name": "Sturmkap", "pos": Vector3(-17195, 0, -18831), "color": Color(0.72, 0.70, 0.66)},
		{"name": "Fjordmund", "pos": Vector3(-24485, 0, -20912), "color": Color(0.36, 0.60, 0.72)},
		{"name": "Lagune", "pos": Vector3(-9209, 0, 28341), "color": Color(0.42, 0.76, 0.70)},
		{"name": "GROSSSTADT", "pos": city_pos, "color": Color(0.95, 0.90, 0.55)},
		{"name": "NEONBUCHT", "pos": sky_pos, "color": Color(0.55, 0.80, 1.0)},
		{"name": "Industriehafen", "pos": indu_pos, "color": Color(0.80, 0.70, 0.62)},
		{"name": "Landdorf", "pos": dorf_pos, "color": Color(0.72, 0.86, 0.60)},
		{"name": "Burg", "pos": burg_pos, "color": Color(0.85, 0.75, 0.90)},
	]
	_map_thread = Thread.new()
	_map_thread.start(func() -> void:
		var img := WorldMap.generate_image(terrain, 512)
		call_deferred("_on_map_image_ready", img))
	for af in airfields:
		_build_airfield(af)
	_build_obstacles()   # solider Hindernis-Parcours nahe HEIMAT (Tore, Pylonen, Felsen, Sperrballons)
	_build_town(town_pos)
	Landmarks.build_airship_factory(fly_world, factory_pos, 0.12)
	_build_lighthouse(lh_pos)
	# --- DIE INSELKETTE BEKOMMT EINEN GRUND, HINAUSZUFLIEGEN --------------------------
	#
	# Neun Inseln vor der Ostkueste sind Landschaft. Landschaft ist kein Ziel: man sieht
	# sie einmal an und kommt nicht wieder. Drei Dinge machen daraus einen Ort —
	#
	#   ein LEUCHTTURM auf der aeussersten Kuppe (30,1 km draussen). Er ist die Marke, die
	#   den Weg lohnt und die man schon von der Kueste aus sieht;
	#   eine STELLUNG auf der groessten Insel, damit der Anflug etwas kostet;
	#   ein WRACK auf dem Riff daneben, das erzaehlt, warum.
	#
	# Die Hoehen kommen von den Inselmassiven selbst (peak 66 bzw. 88), die Bauwerke
	# tasten ihren Grund ueber terrain.height_at ab.
	# AUF DEM UFERVORSPRUNG, NICHT AUF DER KUPPE. Zuerst stand er auf dem hoechsten
	# Punkt der Insel (83 m) — und damit MITTEN IM WALD: mit seinen 19 m Bauhoehe war er
	# dort niedriger als die Kiefern ringsum und im Bild ein roter Punkt zwischen Baeumen.
	# Ein Leuchtturm muss frei stehen und vom Wasser aus zu sehen sein.
	# Gemessen (tools/_leuchtplatz.gd) faellt die Insel nach Osten von 83 m auf 18 m bei
	# 350 m; dort ist Ufervorsprung, und die kleine Flachzone weiter oben haelt ihm die
	# Baeume vom Leib.
	var insel_leucht := Vector3(30450, 0, -7600)
	insel_leucht.y = terrain.height_at(insel_leucht.x, insel_leucht.z)
	_build_lighthouse(insel_leucht)
	Landmarks.build_wreck(fly_world, Vector2(25640, -15320), 2.1)
	_build_windfarm(Vector3(-3900, 0, -700))
	# Ozean-Leben: Segelschiffe weit draussen (garantiert Wasser, d > 16 km) + Wrack
	# MIT DER KUESTE NACH AUSSEN GERUECKT. Die alten Positionen (15600/-5200 und so fort)
	# gehoerten zu einer Insel mit 17,8 km mittlerem Radius. Nach dem Vergroessern auf
	# 25,8 km lagen sie ALLE auf dem Trockenen — eines der Schiffe auf 94 m Hoehe mitten
	# in einem Huegel (gemessen mit tools/_seelage.gd). Die neuen Punkte liegen auf
	# derselben Peilung und haben in Fahrtrichtung mindestens 900 m offenes Wasser vor
	# sich, sind also nicht bloss knapp nass.
	# ZUM ZWEITEN MAL MIT DER KUESTE HINAUSGERUECKT, und diesmal mit Reserve, die etwas
	# aushaelt. Nach der Vergroesserung auf 27,2 km lagen ALLE FUENF an Land — einer 48 m
	# ueber dem Meer mitten in einem Huegel. Der Grund stand im alten Kommentar schon da:
	# "mindestens 900 m offenes Wasser". 900 m ueberlebt keine Kuestenaenderung.
	#
	# Die Punkte sind nicht geschaetzt, sondern gerechnet (tools/_seeplatz.gd): das
	# Werkzeug behaelt die PEILUNG jedes Schiffes bei, sucht auf diesem Strahl die
	# Wasserlinie und setzt es 2500 m dahinter. Nachgemessen liegen vier von ihnen jetzt
	# ueber 24 m tiefem Wasser.
	#
	# SEGLER 3 IST DIE AUSNAHME und musste seine Peilung aendern: sein Strahl (131,7 Grad)
	# trifft die vorgelagerte Insel, die in derselben Runde nach aussen gerueckt wurde —
	# gerechnet kam er 144 m neben deren Mittelpunkt zu liegen, also an Land auf 68 m.
	# Acht Grad seitlich bringen ihn frei, ohne dass er die Insel aus dem Blick verliert.
	for sh in [[Vector2(26373, -8791), 0.7], [Vector2(21642, -17765), 2.4],
			[Vector2(-23566, 19986), -0.9], [Vector2(7824, -28236), 1.6]]:
		Landmarks.build_ship(fly_world, sh[0], sh[1])
	Landmarks.build_wreck(fly_world, Vector2(26983, -7477), 0.8)
	Landmarks.build_village(fly_world, village_pos)
	# Blender-Gebaeude einbauen (MultiMesh je Typ; ohne Kollision wie die Landmarks)
	if CityBuilder.has_lib():
		CityBuilder.build(fly_world, terrain, city_pos, CityBuilder.plan_grossstadt(), "Grossstadt")
		# STRASSEN ZUR STADT. Sie sind aus der Luft die eigentliche Stadtform — die
		# Haeuser sind aus 1500 m nur noch Koernung (Begruendung bei
		# CityBuilder.strassennetz). Das Dorf bekommt ein kleines Netz mit derselben
		# Funktion, damit es nicht als zweite lose Haeuserhaufen danebenliegt.
		CityBuilder.strassennetz(fly_world, terrain, city_pos)
		CityBuilder.strassennetz(fly_world, terrain, dorf_pos, 90.0, 120.0, 420.0)
		CityBuilder.build(fly_world, terrain, indu_pos, CityBuilder.plan_industrie(), "Industriehafen")
		CityBuilder.build(fly_world, terrain, dorf_pos, CityBuilder.plan_dorf(), "Landdorf")
		CityBuilder.build(fly_world, terrain, burg_pos, CityBuilder.plan_burg(), "Burgberg")
		CityBuilder.build(fly_world, terrain, mil_pos, CityBuilder.plan_militaer(), "Militaerposten")
		for af in airfields:   # Hangars/Tower an die AUSSENfelder
			# HEIMAT bekommt diesen Bausatz NICHT MEHR. Er setzt seine sieben Blender-Haeuser
			# (zwei Hangars, Tower, Werkstatt, Tanklager, Wasserturm, Radarstation) 115 bis
			# 410 m oestlich der Bahn ins Gras — also mitten in das Vorfeld, das HEIMAT seit
			# dieser Runde selbst bebaut. Im Bild standen dadurch zwei Tower, zwei Radare und
			# vier Hangars durcheinander, die Haelfte davon ohne Beton darunter. Die
			# Aussenfelder haben nur den Grundplatz und behalten den Bausatz.
			if af.get("main", false):
				continue
			# ADLERHORST AUCH NICHT — ER LIEGT IM BERG. Der Bausatz sitzt bei lokal x 230,
			# und plan_flugplatz() spannt davon 115 bis 410 auf; die Halle ist 52 m halb
			# breit. Alle sieben Haeuser stecken also im Fels, und der Hangar an der
			# Innenkante ragte im Bild als gruener Buckel durch die Wand. Ein Wasserturm
			# und eine Radarstation unter 500 m Gestein waeren ohnehin sinnlos. Was der
			# Platz unter Tage braucht, baut Landmarks._hb_einrichtung: Kraene, Laufstege,
			# Masten, Kanzel.
			if String(af.get("name", "")) == "ADLERHORST":
				continue
			# NEBEN die Bahn (die laeuft im lokalen Z des Flugplatzes, 900 m lang!) und die
			# ganze Planung mit dem Bahnkurs drehen -> Hangars stehen parallel zur Piste.
			var hd: float = af["heading"]
			var ap: Vector3 = af["pos"] + Basis(Vector3.UP, hd) * Vector3(230.0, 0.0, -60.0)
			CityBuilder.build(fly_world, terrain, ap, CityBuilder.plan_flugplatz(),
				"Flugplatzbauten_" + String(af["name"]), hd)
	# HOCHHAUSVIERTEL — AUSSERHALB DES has_lib()-ZWEIGS, denn Skyline baut sich selbst und
	# braucht die Blender-Bibliothek nicht. Und NACH terrain.setup(): vorher kennt das
	# Gelaende seine Flachzonen noch nicht, height_at lieferte also die Hoehe eines
	# Huegels, den es an dieser Stelle gar nicht mehr gibt, und die Tuerme staenden in
	# der Luft oder im Boden.
	Skyline.bauen(fly_world, terrain, sky_pos)
	Landmarks.build_bridge(fly_world, Vector3(1560, 22, 1130), 120.0, 1.0)   # Viadukt überm Fluss
	# FELSENTOR am Eingang des Hochtals. Der Bogen steht QUER zur Talachse, man fliegt also
	# beim Einflug hindurch. Die Fusslinie liegt auf der Gelaendehoehe an der Stelle —
	# nicht auf einem geratenen Wert, sonst haengt das Tor in der Luft oder steckt im Hang.
	var tor_p := _tal_punkt(TOR_LAENGS)
	var tor_y := terrain.height_at(tor_p.x, tor_p.y)
	# hoehe ist die LICHTE Hoehe des Lochs; die Felsnadel darueber kommt noch obendrauf
	# (55 Prozent, Gesamthoehe also rund 650 m). 420 statt der frueheren 260, weil die
	# Oeffnung hoeher als breit sein soll — mit 260 war sie 328 x 224 m, also andersherum;
	# gemessen sind es jetzt 226 x 388 m (tools/_tor_form.gd).
	# terrain wird fuer die Schutthalde gebraucht: Felsdecke und Bloecke liegen auf dem
	# echten Hang, der zur dicken Seite hin um ueber 400 m ansteigt.
	Landmarks.build_felsentor(fly_world, Vector3(tor_p.x, tor_y, tor_p.y),
		TOR_SPANN, 420.0, 105.0, atan2(TAL_RICHTUNG.x, TAL_RICHTUNG.y), TOR_SEED, terrain)
	# FELSENBASIS ADLERHORST: der unterirdische Flugplatz im Talschluss.
	#
	# NICHT MEHR IN DER SEITENWAND. Die erste Fassung war ein Stollen quer zur Bahn — ein
	# Loch in der Wand neben dem Platz. Jetzt laeuft die Kaverne AUF DER BAHNACHSE in den
	# Talschluss: die Bahn endet bei laengs 9270, das Portal steht bei 9310, und wer
	# ausrollt, rollt in den Berg. Begruendung der Station bei ADLERHORST_KAVERNE_LAENGS.
	# Der Kurs ist derselbe wie der der Bahn, nur bergwaerts: +TAL_RICHTUNG.
	# DER HALLENBODEN LIEGT 0,7 M UEBER DEM FLUGFELD: die Linse haelt das Gelaende am
	# Portal auf exakt ADLERHORST_HOEHE, koplanare Flaechen streiten um dieselbe Tiefe —
	# im Bild schien frueher das Gras durch den Boden.
	var kav_p := _tal_punkt(ADLERHORST_KAVERNE_LAENGS)
	# DEN LICHTRAUM DER ROEHRE BEIM GELAENDE ANMELDEN — sonst ist das Portal eine Attrappe.
	#
	# Das Gelaende ist ein Hoehenfeld und kennt keine Roehre; hinter dem Portal steigt der
	# Talschluss von 90 auf 180 m, und seine KOLLISIONSFLAECHE steht quer im Stollen. Von
	# innen sieht man sie nicht (die Vorderseite zeigt talwaerts, die Rueckseite wird
	# weggeschnitten), von aussen fliegt man dagegen nach 10 bis 35 m gegen unsichtbaren
	# Fels — gemessen mit tools/_kaverne_einflug.gd. Genau deshalb war die Kaverne
	# einsehbar und nicht anfliegbar.
	#
	# DIE MASSE SIND ABSICHTLICH ENGER ALS DIE HALLE. Ausgespart werden muss nur dort, wo
	# die Hangflaeche die Roehre kreuzt, und das ist ein Band von rund 30 m gleich hinter
	# dem Mund — tiefer im Berg liegt das Gelaende 600 m ueber der Halle. 52 m halbe
	# Breite deckt den 30-m-Mund mit Reserve und bleibt zugleich weit innerhalb der 80 m
	# halben Breite der Portalstirn: das Loch im Hang liegt damit vollstaendig hinter
	# ihrer Silhouette und ist aus dem Tal nicht zu sehen.
	#
	# UNTEN 1 M UEBER DEM HALLENBODEN, nicht darunter: der Talboden vor dem Portal liegt
	# auf exakt ADLERHORST_HOEHE und soll bleiben. Wuerde die Aussparung ihn erfassen,
	# risse sie ein Loch in das Vorfeld, auf dem man gerade noch gerollt ist.
	terrain.tunnel.append({
		"pos": Vector3(kav_p.x, ADLERHORST_HOEHE + 0.7, kav_p.y),
		"dir": TAL_RICHTUNG.normalized(),
		"laenge": 1080.0,          # Landmarks.HB_LAENGE
		"halb_b": 52.0,
		"unten": 1.0,
		"oben": 66.0,              # Landmarks.HB_H_HALLE + Reserve
	})
	var kaverne := Landmarks.build_felsenbasis(fly_world,
		Vector3(kav_p.x, ADLERHORST_HOEHE + 0.7, kav_p.y),
		atan2(TAL_RICHTUNG.x, TAL_RICHTUNG.y))
	# MASCHINEN AUF DEN STANDPLAETZEN. Ohne sie ist die Kaverne ein beleuchteter Korridor
	# mit Markierungen auf dem Boden — ein Flugplatz wird sie erst durch das, was dort
	# steht. Die Standplaetze sind in Landmarks._hb_einrichtung bei x = +-46 und z = 320
	# bis 500 markiert; hier stehen die Flieger genau darauf.
	# SIE HAENGEN AM KAVERNENKNOTEN, nicht an fly_world: dessen Drehung und Lage gelten
	# damit auch fuer sie, und die Zahlen unten sind Masse IM BAUWERK statt Weltkoordinaten.
	# PREIS: rund 35 000 Dreiecke je Maschine (siehe _bahnbelag). Sechs sind rund 210 000 —
	# bei 2,15 ms Grundlast der Kaverne vertretbar, nachgemessen mit tools/_bildzeit.gd.
	# DIE MISCHUNG IST ABSICHT: zwei Kolben, zwei Korea-Jets, zwei Ueberschall. Eine
	# Bergbasis, in der sechs gleiche Flieger stehen, sieht aus wie ein Katalogbild.
	if kaverne != null:
		var stand := [
			["spitfire", -30.0, 320.0, 90.0], ["me262", 30.0, 320.0, -90.0],
			["f86", -30.0, 450.0, 90.0], ["mig15", 30.0, 450.0, -90.0],
			["mig21", -30.0, 580.0, 90.0], ["mustang_p51", 30.0, 580.0, -90.0],
			# VIER WEITERE, UND ZWAR AUF DEN AUSSENSTAENDEN VOR DEN HALLEN. Die ersten
			# sechs stehen alle im mittleren Drittel bei x = +-30; in den Abnahmebildern
			# war deshalb je Aufnahme hoechstens EINE Maschine zu sehen, und ein Platz
			# mit einem Flugzeug liest sich als Modellbau. Diese vier sitzen weiter
			# aussen und ueber die ganze Tiefe verteilt, damit aus jeder Kamerastellung
			# mehrere im Bild stehen.
			["f86", -46.0, 190.0, 90.0], ["spitfire", 46.0, 190.0, -90.0],
			["mig15", -46.0, 700.0, 90.0], ["me262", 46.0, 830.0, -90.0],
		]
		for e in stand:
			_add_parked_plane(kaverne, String(e[0]),
				Vector3(float(e[1]), 0.2, float(e[2])), float(e[3]))
	# Alle Wahrzeichen auf denselben Sichthorizont deckeln wie die Haeuser: sie sind feste
	# Meshes und wurden vorher bis zur Kamera-Fernebene (9 km) gezeichnet, das Terrain aber
	# nur bis VIEW_DIST — Stadt, Leuchtturm und Dorf standen dadurch sichtbar im Leeren.
	# Wolken bleiben ABSICHTLICH unbegrenzt: die haengen hoch in der Luft, brauchen keinen
	# Boden darunter und sollen den Horizont fuellen.
	_limit_sichtweite(fly_world, CityBuilder.SICHT_DIST, CityBuilder.SICHT_FADE)

	# FERNSCHUERZE: das Land hoert nicht mehr an der Chunk-Grenze auf. MUSS nach
	# _limit_sichtweite laufen — die Schuerze ist die eine Geometrie in fly_world, die
	# gerade NICHT auf den Haeuser-Sichthorizont gedeckelt werden darf.
	_fernschuerze_starten()

	# WOLKEN: hoch in der Luft, locker über viele Höhen verteilte Kumulus zum Durchfliegen
	# (keine Kollision, nur Flug-Welt).
	# WEITE: das Feld reichte nur 4,4 km — die Decke endete also VOR dem Horizont und die
	# halbe Himmelsrunde blieb leer. Jetzt deckt es die Kamera-Fernebene ab und wird dem
	# Spieler nachgefuehrt (CloudField.mitfuehren), damit es auch am anderen Ende der
	# Insel steht.
	# MEHRERE SCHICHTEN statt einer. Bis eben gab es genau eine Wolkensorte auf genau
	# einer Hoehe — damit sah jeder Steigflug ab 500 m gleich aus, und ueber der Decke war
	# der Himmel leer. Die Sorten und ihre Hoehen stehen in CloudField.TYPEN; alle sind
	# durchfliegbar und werden einzeln mitgefuehrt.
	cloud_fields.clear()
	for typ in WOLKEN_LAGEN:
		var feld := CloudField.build(fly_world, {"area": WOLKEN_AREA, "typ": typ})
		cloud_fields.append(feld)
		# SCHATTEN: Wolkenschatten sind die staerkste Erdung, die eine Flugwelt hat — sie
		# legen Massstab auf den Boden und zeigen, dass ueber einem etwas haengt.
		# CloudField baut die Puffs schattenlos; hier wird das umgestellt, weil die Sonne
		# jetzt wirft. NUR die unteren Schichten: was in 2,3 km oder 3,4 km haengt, liegt
		# jenseits von directional_shadow_max_distance (3 km) und wuerde nur Kaskaden
		# kosten, ohne je einen Schatten auf den Boden zu legen.
		if CloudField.TYPEN[typ]["layer_y"] <= 1200.0:
			for w in feld.get_children():
				var mi := w as GeometryInstance3D
				if mi != null:
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Die Kumulusdecke bleibt unter dem alten Namen erreichbar — Werkzeuge greifen darauf.
	cloud_field = cloud_fields[0]
	_vulkanfahnen()
	# Gespeicherte Grafikeinstellungen anwenden. MUSS nach dem Wolkenaufbau stehen: die
	# Funktion schaltet Schattenwurf und Sichtbarkeit der Lagen, die es vorher nicht gibt.
	grafik_anwenden()

	# Der Blueprint-Boden gehoert jetzt zu ShowroomStage und wird mit der Buehne
	# geschaltet (frueher ein eigenes MeshInstance3D mit hellem Inline-Shader).


## DAMPFFAHNE UEBER JEDEM VULKAN. Die Saeule selbst baut CloudField (dort steht auch,
## warum sie aus denselben Puffs besteht wie die Wolkendecke) — hier wird nur bestimmt, WO
## sie steht und wie hoch sie reicht.
##
## SIE MUSS NACH _limit_sichtweite STEHEN. Das deckelt alle Wahrzeichen auf den
## Haeuser-Sichthorizont, weil sie sonst ueber leerem Gelaende schweben. Fuer die Fahne
## waere genau das falsch herum: sie haengt in der Luft, braucht keinen Boden unter sich
## und soll gerade dann noch zu sehen sein, wenn vom Kegel nur ein Buckel am Horizont
## uebrig ist.
##
## DER FUSS LIEGT IM KRATER, nicht auf der Lippe: der Rand steht rund 0.7 Gipfelhoehen ueber
## dem Kraterboden (tools/_vulkan_form.gd misst beides). Mit dem Fuss auf 0.70 der
## Gipfelhoehe wachsen die untersten Ballen aus der Schuessel heraus, und aus der Ferne kommt
## die Saeule aus dem Berg statt auf ihm zu sitzen.
##
## "GIPFELHOEHE" IST peak PLUS SCHUERZE, nicht peak allein. Die Schuerze ("apron", siehe die
## Massivtabelle) traegt den ganzen Kegel um ihre Hoehe hoeher; wer hier nur peak liest,
## setzt die Saeule genau um diesen Betrag zu tief an — bei 190 m Schuerze also unter den
## Kraterboden, wo vom untersten Drittel der Fahne nichts mehr zu sehen waere. Ohne den
## Schluessel ist der Summand null und es bleibt bei peak, wie bisher.
func _vulkanfahnen() -> void:
	for ms in terrain.massifs:
		if String(ms.get("type", "")) != "vulkan":
			continue
		var p: Vector3 = ms["pos"]
		var peak := float(ms["peak"]) + float(ms.get("apron", 0.0))
		CloudField.fahne(fly_world, {
			"name": "VulkanFahne",
			"fuss": Vector3(p.x, peak * 0.70, p.z),
			# Gut eine Kegelhoehe ueber dem Fuss. Kuerzer las sich die Saeule als Wolke, die
			# zufaellig ueber dem Gipfel haengt; deutlich hoeher als Fabrikschornstein.
			"hoehe": peak * 1.30,
			"r_unten": float(ms.get("crater_r", 400.0)) * 0.11,
			"r_oben": float(ms.get("crater_r", 400.0)) * 0.48,
			"seed": int(p.x) * 31 + int(p.z),
		})


## Traegt ALLE Grafikeinstellungen aus dem Spielstand in die Szene.
##
## EINE Stelle fuer alles: die Werte wirken auf Licht, Wolken, Flora und Viewport, und
## jede haette sonst ihre eigene Anwendungsstelle mit eigener Vergesslichkeit. So genuegt
## ein Aufruf — beim Weltaufbau und nach jeder Aenderung im Menue.
func grafik_anwenden() -> void:
	# SONNENSCHATTEN. Groesster Einzelposten der Flugansicht: gemessen 6,4 von 20,45 ms
	# bei vollem Sichtring, also rund ein Drittel der Bildzeit.
	if sonne_licht != null and is_instance_valid(sonne_licht):
		sonne_licht.shadow_enabled = game.gfx_sonnenschatten

	# WOLKENSCHATTEN. Sie sind die staerkste Erdung, die eine Flugwelt hat — kosten aber
	# je Wolke einen Durchgang durch die Schattenkaskaden. Getrennt schaltbar, damit man
	# die Bodenschatten behalten kann, ohne die Wolken zu bezahlen.
	for i in cloud_fields.size():
		var feld: Node3D = cloud_fields[i]
		if feld == null or not is_instance_valid(feld):
			continue
		# Nur die unteren Lagen werfen ueberhaupt (siehe Aufbau) — die oberen liegen
		# jenseits der Schattenreichweite.
		var wirft: bool = game.gfx_wolkenschatten \
			and CloudField.TYPEN[WOLKEN_LAGEN[i]]["layer_y"] <= 1200.0
		for w in feld.get_children():
			var mi := w as GeometryInstance3D
			if mi != null:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if wirft \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# WOLKENLAGEN: 0 = keine, 1 = nur die Kumulusdecke, 2 = alle vier.
		feld.visible = game.gfx_wolkenlagen >= 2 or (game.gfx_wolkenlagen == 1 and i == 0)

	# BAUMWEITE. Die Flora war gemessen 4,65 von 7,86 ms je Bild, also 59 Prozent — hier
	# liegt der groesste Regler des ganzen Spiels.
	if terrain != null and is_instance_valid(terrain):
		terrain.setze_baumweite(game.gfx_baumweite)

	# AUFLOESUNG. Bei 70 Prozent wird ein Viertel weniger Flaeche berechnet und wieder
	# hochskaliert; das trifft ALLES, auch den bildfuellenden Himmel.
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = clampf(float(game.gfx_aufloesung) / 100.0, 0.5, 1.0)


## Haelt die Wolkendecke um den Spieler herum geschlossen. Die eigentliche Arbeit macht
## CloudField.mitfuehren — dort steht auch, warum das frueher als gedaempfte Drift des
## GANZEN Blocks gebaut war und warum das nicht funktionieren konnte.
func _wolken_nachziehen(ziel: Vector3) -> void:
	for feld in cloud_fields:
		CloudField.mitfuehren(feld, ziel, WOLKEN_PASS_WEG)


## Steckt das Flugzeug in einer Wolke? Eine Zahl, drei Wirkungen — deshalb wird sie hier
## EINMAL bestimmt und dann verteilt, statt dass drei Systeme dasselbe nachrechnen:
##   Turbulenz   -> FlightController.wolken_dichte (Ruetteln und Sacken)
##   Sicht       -> der Nebel dieser Funktion (Weissabriss)
##   Deckung     -> als Meta am Flugzeug, damit FlakGun nicht mehr aufheben muss und
##                  weder CloudField noch Main kennen muss
##
## TRAEGE NACHFUEHRUNG: beim Streifen einer Wolkenkante springt der Rohwert; wuerde man
## ihn direkt benutzen, flackerten Nebel und Ruetteln. Die Zeitkonstante ist mit rund
## einer Viertelsekunde so gewaehlt, dass der Einflug noch als Ereignis lesbar bleibt.
func _wolken_aufenthalt(delta: float) -> void:
	var pos: Vector3 = flight_ctrl.aircraft.global_position
	var roh := CloudField.dichte_bei_allen(cloud_fields, pos)
	if not is_finite(roh):
		roh = 0.0
	wolken_dichte = clampf(lerpf(wolken_dichte, roh, clampf(delta * 4.0, 0.0, 1.0)), 0.0, 1.0)

	flight_ctrl.wolken_dichte = wolken_dichte
	flight_ctrl.aircraft.set_meta("wolken_dichte", wolken_dichte)

	if env_sky != null:
		var k := pow(wolken_dichte, NEBEL_KURVE)
		env_sky.fog_density = lerpf(NEBEL_FREI, NEBEL_WOLKE, k)
		env_sky.fog_light_color = NEBEL_FARBE_FREI.lerp(NEBEL_FARBE_WOLKE, k)
		# Auch der HIMMEL muss mit eintrueben, sonst steht mitten im Weiss noch ein
		# blauer Zenit — der Nebel faerbt nur Geometrie, nicht den Hintergrund.
		env_sky.fog_sky_affect = lerpf(0.1, 1.0, k)


# ===========================================================================
# FERNSCHUERZE — Gelaende JENSEITS der Chunk-Sichtweite
# ===========================================================================
# BEFUND, der das noetig machte: TerrainWorld laedt Chunks nur bis VIEW_DIST (3,8 km),
# dahinter lag nichts. Aus 600 m ueber Land brach das Gelaende deshalb auf einer
# schnurgeraden Bildzeile ab — gemessen 29 % der Spalten auf exakt derselben Zeile,
# Helligkeitssprung 44,7/255 ueber vier Pixel; aus 2000 m ein Lineal mit 90-Grad-
# Chunkstufen. Der Himmels-Shader kann das per Konstruktion NICHT heilen: er faerbt nur,
# was HINTER der Kante liegt, er ersetzt kein fehlendes Land davor. Gegenprobe des
# Pruefers: mit 6 km Bauradius fiel derselbe Sprung auf 0,8/255. Es fehlte Geometrie,
# nicht Nebel — und mehr Nebel war ausdruecklich unerwuenscht.
#
# Die Schuerze ist eine ZWEITE, grobe Terrainlage ueber die ganze Welt:
#   - 64-m-Raster statt 8 m; kein Detail, nur Silhouette und Grossform,
#   - KEINE Kollision, KEINE Flora, KEIN Schattenwurf,
#   - NUR ueber Land. Ueber offenem Wasser bleibt es beim Himmelsband, dessen Naht der
#     Pruefer bereits abgenommen hat (Himmel gegen Fernwasser hoechstens 4/255).
#
# WARUM SIE SICH NICHT MIT DEN CHUNKS BEISST: der Vertex-Shader zieht jeden Punkt umso
# tiefer, je NAEHER er der Kamera steht (FERN_TIEF bis FERN_NAH, ausgelaufen bei
# FERN_FERN, danach nur noch FERN_BIAS). Im Nahfeld liegt die grobe Lage damit eine
# halbe Bergeshoehe unter dem Boden und ist unsichtbar; erst dort, wo die Chunks enden,
# taucht sie auf. Das ist ein STETIGER Verlauf an der Kamera — kein Ein-/Ausblenden,
# kein Popping im Flug, keine wandernde Naht, wie sie ein nachgezogener Kachelring haette.
func _fernschuerze_starten() -> void:
	fern_root = Node3D.new()
	fern_root.name = "Fernschuerze"
	fly_world.add_child(fern_root)

	var sh := Shader.new()
	# Der fragment()-Teil ist absichtlich der des Terrains (TerrainWorld.setup):
	# Vertexfarbe als Albedo, sRGB->linear gewandelt. Nur so trifft die Schuerze die
	# Palette der Chunks, an die sie anschliesst.
	# EINE ZEILE FEHLT ABSICHTLICH, naemlich die Glut (EMISSION aus COLOR.a). Hier ist
	# COLOR.a schon vergeben — er traegt die Grundabsenkung, siehe vertex() —, und der
	# Preis dafuer ist klein: die Schuerze faengt erst 3,8 km vom Spieler entfernt an,
	# und dort ist eine Glutrinne unter einem Bildpunkt breit. Die GESTEINSFARBE des
	# Vulkans samt seiner Lavazungen kommt dagegen aus _face_color und steht auf der
	# Schuerze genauso wie in den Chunks — der Kegel bleibt also auch aus 20 km schwarz.
	sh.code = """
shader_type spatial;
uniform float senke_nah;
uniform float senke_fern;
uniform float senke_tief;
uniform float senke_bias;
uniform float bias_aus_a;
uniform float bias_aus_b;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = distance(wp.xz, CAMERA_POSITION_WORLD.xz);
	// COLOR.a traegt, wie viel Grundabsenkung diese Flaeche BRAUCHT (siehe _fern_tri):
	// im Gebirge die volle, an flachen Kuesten fast keine.
	float s = senke_tief * (1.0 - smoothstep(senke_nah, senke_fern, d))
		+ senke_bias * COLOR.a * (1.0 - smoothstep(bias_aus_a, bias_aus_b, d));
	// COLOR.a == 0 markiert den Grundriss des Kavernenflugplatzes (siehe _fern_tri).
	// Dort wird die Absenkung GEDECKELT, damit keine Zelle in der Halle landet: wer
	// ueber 220 m liegt, parkt beim Absinken auf 220 (mitten im Fels, unsichtbar),
	// wer darunter liegt, sinkt voll und landet unter dem Hallenboden.
	if (COLOR.a < 0.05 && wp.y > 220.0) {
		s = min(s, wp.y - 220.0);
	}
	VERTEX.y -= s;
}
void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
"""
	_fern_mat = ShaderMaterial.new()
	_fern_mat.shader = sh
	_fern_mat.set_shader_parameter("senke_nah", FERN_NAH)
	_fern_mat.set_shader_parameter("senke_fern", FERN_FERN)
	_fern_mat.set_shader_parameter("senke_tief", FERN_TIEF)
	_fern_mat.set_shader_parameter("senke_bias", FERN_BIAS)
	_fern_mat.set_shader_parameter("bias_aus_a", FERN_BIAS_AUS_A)
	_fern_mat.set_shader_parameter("bias_aus_b", FERN_BIAS_AUS_B)

	_fern_mutex = Mutex.new()
	var half := int(ceil(FERN_WELT / FERN_KACHEL))
	for ty in range(-half, half):
		for tx in range(-half, half):
			_fern_keys.append(Vector2i(tx, ty))
	# Eigener Thread, damit der Start nicht haengt (wie bei der Karte). Er verteilt die
	# Kacheln danach ueber den WorkerThreadPool — height_at kostet gemessen 11,15 us,
	# und die Schuerze braucht rund 230 000 Proben. Auf einem Kern waeren das 2,6 s,
	# ueber alle Kerne ist sie da, bevor der Spieler den Hangar verlaesst.
	_fern_thread = Thread.new()
	_fern_thread.start(_fern_bauen)


func _fern_bauen() -> void:
	for zelle in [FERN_ZELLE_GROB, FERN_ZELLE_FEIN]:
		var t0 := Time.get_ticks_msec()
		_fern_zelle = zelle
		# Sammelliste VOR dem Lauf leeren, und zwar hier auf dem Bauthread. Sie fruehe zu
		# leeren war _fern_fertigs Aufgabe — das geht mit zwei Stufen nicht mehr, weil die
		# zweite Stufe anlaufen kann, waehrend die erste noch eingehaengt wird.
		_fern_mutex.lock()
		_fern_meshes = []
		_fern_tris = 0
		_fern_mutex.unlock()
		var gid := WorkerThreadPool.add_group_task(_fern_kachel, _fern_keys.size(),
			-1, false, "Fernschuerze")
		WorkerThreadPool.wait_for_group_task_completion(gid)
		_fern_mutex.lock()
		var fertig: Array = _fern_meshes
		var tris := _fern_tris
		_fern_meshes = []
		_fern_mutex.unlock()
		call_deferred("_fern_stufe_fertig", fertig, tris,
			Time.get_ticks_msec() - t0, zelle)
	call_deferred("_fern_thread_ende")


## Eine Kachel. Laeuft im Pool, also nur lesende Zugriffe auf terrain (height_at,
## _face_color) — dieselben, die der Chunk-Worker und der Karten-Thread laengst
## nebenlaeufig fahren.
func _fern_kachel(idx: int) -> void:
	var key: Vector2i = _fern_keys[idx]
	var ox := float(key.x) * FERN_KACHEL
	var oz := float(key.y) * FERN_KACHEL
	# 1) Billige Vorprobe (9x9, 192 m Abstand): drei Viertel der Welt sind offenes
	#    Wasser, und dort waeren die 625 Rasterproben komplett verschenkt.
	var land := false
	for j in 9:
		for i in 9:
			if terrain.height_at(ox + float(i) * FERN_KACHEL / 8.0,
					oz + float(j) * FERN_KACHEL / 8.0) > TerrainWorld.SEA_Y - 1.0:
				land = true
				break
		if land:
			break
	if not land:
		return

	# 2) Hoehenraster. Auf Meereshoehe geklemmt: die Wasserplatte reicht nur 4,6 km weit,
	#    ein absaufender Kuestenhang waere dahinter als Loch im Meer zu sehen. So endet
	#    das Land an der Wasserlinie, genau wie es aus der Ferne aussehen soll.
	var zelle := _fern_zelle
	var n := int(FERN_KACHEL / zelle)
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			hs[j * (n + 1) + i] = maxf(
				terrain.height_at(ox + float(i) * zelle, oz + float(j) * zelle, zelle),
				TerrainWorld.SEA_Y)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)          # FLAT shading, wie die Chunks
	var tris := 0
	for j in n:
		for i in n:
			var h00 := hs[j * (n + 1) + i]
			var h10 := hs[j * (n + 1) + i + 1]
			var h01 := hs[(j + 1) * (n + 1) + i]
			var h11 := hs[(j + 1) * (n + 1) + i + 1]
			# Zelle komplett unter Wasser -> kein Dreieck (siehe Kopfkommentar).
			if maxf(maxf(h00, h10), maxf(h01, h11)) <= TerrainWorld.SEA_Y + 0.01:
				continue
			var x0 := ox + float(i) * zelle
			var z0 := oz + float(j) * zelle
			var v00 := Vector3(x0, h00, z0)
			var v10 := Vector3(x0 + zelle, h10, z0)
			var v01 := Vector3(x0, h01, z0 + zelle)
			var v11 := Vector3(x0 + zelle, h11, z0 + zelle)
			_fern_tri(st, v00, v10, v11, zelle)
			_fern_tri(st, v00, v11, v01, zelle)
			tris += 2
	if tris == 0:
		return
	st.generate_normals()
	var mesh := st.commit()
	_fern_mutex.lock()
	_fern_meshes.append(mesh)
	_fern_tris += tris
	_fern_mutex.unlock()


## Wicklung und Farbgebung EXAKT wie TerrainWorld._tri — die Schuerze soll die
## Fortsetzung der Chunks sein, nicht eine zweite Farbwelt daneben.
##
## Der ALPHA-Kanal ist kein Deckungsgrad (das Material ist opak), sondern der Faktor
## fuer die Grundabsenkung im Vertex-Shader. Grund: die 44 m, um die das 64-m-Raster
## im schlechtesten Fall UEBER dem echten Gelaende liegen kann, treten ausschliesslich
## im Gebirge auf — dort braucht es die volle Absenkung. An flachen Kuesten dagegen
## deckt sich grob mit fein bis auf Zentimeter, und eine pauschale 14-m-Absenkung
## wuerde dort den Strand unter die Wasserplatte druecken: beim Vorbeiflug waeren
## Kuestenstreifen in einem mitwandernden Ring abgesoffen. Also skaliert die
## Absenkung mit der Hoehe; 0,25 bleibt als Mindestmass gegen Z-Fighting stehen.
func _fern_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, zelle: float) -> void:
	var nn := (b - a).cross(c - a).normalized()
	var cen := (a + b + c) / 3.0
	var col := terrain._face_color(cen, absf(nn.y), zelle, nn)
	# WALD AUF DER GANZEN INSEL, ohne ein einziges zusaetzliches Dreieck. Echte Baeume gibt
	# es nur in den gestreamten Chunks (3,8 km um den Spieler); die Schuerze reicht bis
	# 20 km und war bisher unbewaldet, der Wald wanderte also mit dem Spieler mit. Aus
	# dieser Entfernung ist ein Wald ohnehin nur eine dunkelgruene Flaeche — genau die wird
	# hier eingefaerbt, nach DERSELBEN Regel, die auch die echten Baeume setzt. Der
	# Uebergang an der Chunkgrenze faellt nicht auf, weil dort dieselbe Regel gilt.
	var w := terrain.wald_anteil(cen.x, cen.z, cen.y, absf(nn.y))
	if w > 0.0:
		col = col.lerp(FERN_WALD, clampf(w * 0.85, 0.0, 0.85))
	col.a = clampf(0.25 + cen.y / 60.0, 0.25, 1.0)
	# ALPHA 0 = KAVERNENGRUNDRISS. Der Vertex-Shader DECKELT dort die Absenkung (siehe
	# _fernschuerze_starten): Zellen ueber 220 m parken beim Absinken auf 220 — ueber dem
	# Hallenscheitel (177), unter der echten Oberflaeche (500 bis 1000), also mitten im
	# Felsvolumen, wo niemand hinsehen kann. Zellen unter 220 m sinken voll und landen
	# unter dem Hallenboden. Beides zusammen heisst: nichts haengt je in der Halle, und
	# die Silhouette des Talschlusses bleibt aus JEDER Entfernung vollstaendig.
	# DREI LOESCH-VARIANTEN VORHER RISSEN IMMER IRGENDWO EIN LOCH: alle Zellen im
	# Grundriss weg = heller Schlitz vom Tal aus; nur die unter 260 m = Woelbung blieb
	# (Absenkung reicht tiefer, als die Zelle hoch liegt); nur die hinteren unter 700 m =
	# Himmelsfenster durch den Grat, weil genau sie die Silhouette getragen haben.
	var k_dx := cen.x - TAL_START.x
	var k_dz := cen.z - TAL_START.y
	var k_l := k_dx * TAL_RICHTUNG.x + k_dz * TAL_RICHTUNG.y
	if k_l > ADLERHORST_KAVERNE_LAENGS - 40.0 \
			and k_l < ADLERHORST_KAVERNE_LAENGS + 790.0 \
			and absf(k_dx * TAL_RICHTUNG.y - k_dz * TAL_RICHTUNG.x) < 175.0:
		col.a = 0.0
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## EINE Stufe einhaengen und die vorige wegraeumen.
##
## DER THREAD DARF HIER NICHT ABGEWARTET WERDEN. Frueher stand am Anfang dieser Funktion
## _fern_thread.wait_to_finish() — mit zwei Stufen waere das ein Selbstblock: die erste
## Stufe wird eingehaengt, waehrend derselbe Thread schon die zweite baut. Das Abwarten
## steht deshalb in _fern_thread_ende, das der Thread als letztes selbst anstoesst.
func _fern_stufe_fertig(meshes: Array, tris: int, ms: int, zelle: float) -> void:
	if fern_root == null or not is_instance_valid(fern_root):
		return
	var vorige := _fern_stufe_knoten
	var stufe := Node3D.new()
	stufe.name = "Stufe%d" % int(zelle)
	fern_root.add_child(stufe)
	for m in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _fern_mat
		# Kein Schattenwurf: die Schuerze ist eine ABGESENKTE Naeherung des Bodens. Wuerfe
		# sie, lege sie im Nahfeld aus 480 m Tiefe einen zweiten, falschen Schatten unter
		# das echte Gelaende.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Der Vertex-Shader schiebt Punkte bis FERN_TIEF+FERN_BIAS nach unten. Ohne
		# Zuschlag wuerde Godot gegen die UNVERSCHOBENE AABB auslesen und Kacheln
		# wegkullen, die erst durch die Absenkung ins Bild rutschen.
		mi.extra_cull_margin = FERN_TIEF + FERN_BIAS + 16.0
		stufe.add_child(mi)
	# ERST DIE NEUE STUFE HAENGT, DANN FAELLT DIE ALTE. Andersherum stuende fuer einen
	# Frame gar keine Schuerze da, und das saehe man als aufblitzendes Loch am Horizont.
	_fern_stufe_knoten = stufe
	if vorige != null and is_instance_valid(vorige):
		vorige.queue_free()
	print("Fernschuerze %d m: %d Kacheln, %d Dreiecke, %.2f s"
		% [int(zelle), meshes.size(), tris, ms / 1000.0])


func _fern_thread_ende() -> void:
	if _fern_thread != null:
		_fern_thread.wait_to_finish()
		_fern_thread = null


func _exit_tree() -> void:
	# Der Schuerzen-Thread liest terrain. Wird Main abgeraeumt, muss er vorher stehen.
	if _fern_thread != null and _fern_thread.is_started():
		_fern_thread.wait_to_finish()
		_fern_thread = null
	# DER KARTEN-THREAD GENAUSO. Auf ihn wurde bisher NUR in _on_map_image_ready
	# gewartet — also erst, wenn er sein Bild geliefert hat. Endet das Spiel vorher
	# (Beenden im Hangar, Absturz einer Sitzung, jeder Testlauf mit --quit), wird das
	# Thread-Objekt zerstoert, ohne dass jemand darauf gewartet hat. Godot meldet dann
	# "A Thread object is being destroyed without its completion having been realized"
	# und laesst Objekte im ObjectDB zurueck. Schlimmer als die Meldung ist die Ursache:
	# der Thread liest waehrenddessen `terrain`, das gerade abgeraeumt wird.
	if _map_thread != null and _map_thread.is_started():
		_map_thread.wait_to_finish()
		_map_thread = null


func _flat_mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _emit_mat(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


# Flughafen: 900-m-Bahn (3×) mit echter Markierung (Randlinien, Mittellinie, Piano-Keys,
# Aufsetzpunkt-Blöcke, Bahnnummern), Randbefeuerung (weiß) + Schwellenlichter (grün) +
# Anflugbefeuerung, Rollweg zum Vorfeld (Beton-Apron) mit Hangars, Tower, Windsack & Tanks.
const RWY_LEN := 900.0
const RWY_W := 30.0
# Sandschulter beidseits des Asphalts. Die Referenzbilder zeigen die Bahn NIE nackt im
# Gras — sie sitzt in einem hellen Streifen, und genau der gibt ihr aus der Luft die
# Breite. 9 m je Seite ist das Verhaeltnis aus den Vorlagen (Schulter ≈ 0,3 × Bahnbreite).
const RWY_SHOULDER := 7.5
# Tower-Standort im VORFELD-Koordinatensystem (Unterknoten "Vorfeld", siehe VORFELD_Z).
# Frueher stand die 58/55 an vier Stellen einzeln im Code (Turm, Antenne, Blinklicht,
# Drehfeuer) — beim Umstellen des Vorfelds waere garantiert eine davon stehengeblieben.
const TOWER_POS := Vector3(94.0, 0.0, -52.0)
# LAENGSVERSATZ DES GANZEN VORFELDS zur Bahnmitte (+Z = zur Schwelle 36 hin).
# Gemessen an heimat_1: dort liegt die Apron-Mitte nicht auf der Bahnmitte, sondern bei
# rund 55 % der Bahnlaenge von der FERNEN Schwelle aus — also gut 50 m suedlich der Mitte;
# in heimat_2 (Blick von der Schwelle 36 die Bahn hinunter) steht der Tower gross im Bild,
# was bei 455 m Abstand rechnerisch unmoeglich ist. 150 m Versatz bringt beides zusammen:
# Apron-Mitte auf 55,5 % der Bahn, Tower 305 statt 455 m von der Schwelle. Weil ALLES
# Vorfeld-Gebaute an EINEM Unterknoten haengt, bleiben die ~90 Einzelkoordinaten unten
# unveraendert — der Versatz ist eine Zahl, nicht 90.
const VORFELD_Z := 150.0
# DIE BEBAUTE FLAECHE, als Rechtecke [mitte_x, mitte_z, halb_x, halb_z] in PLATZ-
# Koordinaten (Bahn laengs Z, Ursprung Bahnmitte). Zwei Verbraucher muessen sich darauf
# einigen: TerrainWorld._open_ground haelt diese Flaeche von Bewuchs frei, _gruenguertel
# saet seinen Nahsaum genau daran entlang.
#  - Bahn samt Sandschulter: RWY_W/2 + RWY_SHOULDER = 22,5 m breit,
#    (RWY_LEN + 40)/2 = 470 m lang.
#  - Rollweg, Verbinder und Vorfeld: die Betonkante liegt im Vorfeld-Knoten bei x 24..162
#    und z -104..94; mit VORFELD_Z = 150 sind das z 46..244, und der Rollweg reicht bis
#    x = 8. Daraus Mitte (86, 145), halb (80, 106).
const FP_RECHTECKE := [
	[0.0, 0.0, 22.5, 470.0],
	[86.0, 145.0, 80.0, 106.0],
]


func _build_airfield(af: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Flugplatz_" + String(af["name"])
	node.position = af["pos"]
	node.rotation.y = af["heading"]
	fly_world.add_child(node)
	var hl := RWY_LEN * 0.5
	# BAHNBELAG — der schwerste Einzelbefund der letzten Runde. GEMESSEN am alten Stand
	# (Median ueber alle grauen Bahn-Pixel in fp_schwelle): sRGB(24, 22, 18), also nahezu
	# schwarz und dazu WARM gestochen, R:G:B = 1.33 : 1.22 : 1.00. Die vier Vorlagen liegen
	# bei sRGB(65,65,64) / (73,74,75) / (64,63,64) mit R:G:B rund 0.97 : 0.99 : 1.00 — also
	# Mittelgrau, neutral bis leicht kuehl. Mit dem alten Wert las sich die Bahn aus der
	# Luft als LOCH im Gras und jede weisse Markierung als ausgestanztes Rechteck.
	# Zwei getrennte Ursachen:
	#  1) zu dunkle Albedo. Die Kennlinie (ACES, white 6, Saettigung 1.18) ist nicht
	#     linear, der Faktor liess sich also nicht ausrechnen — er ist in zwei Laeufen AM
	#     BILD eingemessen worden (Werte siehe unten am Endstand).
	#  2) Der Braunstich kommt NICHT vom Material, sondern vom Licht: die Sonne steht auf
	#     Color(1.0, 0.97, 0.88) und die Nachbelichtung zieht die Saettigung auf 1.18.
	#     Gegengesteuert wird am Material, denn die Bahn ist die einzige grosse Flaeche,
	#     fuer die die Vorlagen einen kuehlen Ton verlangen.
	# DERSELBE Ton traegt auch die Rollwege — in heimat_1 und heimat_4 sind sie genauso
	# dunkel wie die Bahn.
	# EINGEMESSEN, nicht geschaetzt: erster Wurf (0.395, 0.415, 0.470) ergab im Bild
	# sRGB(60, 62, 63) bei R:G:B = 0.95 : 0.98 : 1.00. Aus diesem Punkt und dem alten
	# folgt die Kennliniensteigung (Bildwert rund proportional zu scene^0.91); daraus
	# dieser Wert fuer das Ziel sRGB(66, 68, 71) bei 0.93 : 0.96 : 1.00.
	var asphalt := _flat_mat(Color(0.415, 0.441, 0.500), 0.95)
	# Beton HELLER und waermer als vorher (0.55/0.55/0.53). In heimat_3 und heimat_4 ist das
	# Vorfeld die hellste Flaeche des Platzes — heller als die Sandschulter und deutlich
	# heller als das Gras. Mit dem alten Wert lag es unter dem Gras-Ton und las sich aus der
	# Luft als grauer Fleck statt als Beton.
	var concrete := _flat_mat(Color(0.70, 0.69, 0.65), 0.9)
	var sand := _flat_mat(Color(0.78, 0.73, 0.58), 1.0)
	var paint := _emit_mat(Color(0.93, 0.93, 0.88), 0.18)
	var paint_y := _emit_mat(Color(0.95, 0.8, 0.2), 0.18)

	# --- Bahn (flach, damit Räder nicht einsinken) + Sandschulter ---
	# Der Asphalt behaelt exakt RWY_W × RWY_LEN. Verbreitert wird nur die Platte DARUNTER:
	# frueher war sie grasgruen (0.28/0.36/0.26) und ging im Gelaende unter, die Bahn lag
	# also wie ein Klebestreifen in der Wiese. In allen vier Vorlagen traegt sie beidseits
	# einen hellen Sandstreifen — der ist es, der aus der Luft die Bahnachse zeichnet.
	# Der Unterbau traegt nur noch die 7 cm hohe KANTE; die Oberflaeche kommt als
	# Plattenfeld bei y = 0.08 darauf (siehe _bahnbelag). 1 cm Luft dazwischen — bei
	# gleicher Hoehe flimmern zwei Flaechen gegeneinander.
	_deco_box(node, Vector3(0, 0.035, 0), Vector3(RWY_W, 0.07, RWY_LEN), asphalt)
	_bahnbelag(node, asphalt.albedo_color)
	var schulter_b := RWY_W + 2.0 * RWY_SHOULDER
	_deco_box(node, Vector3(0, 0.02, 0), Vector3(schulter_b, 0.04, RWY_LEN + 40.0), sand)
	# Solide Kollision an der Bahn-OBERKANTE (y=0.08): Der Asphalt liegt sichtbar über
	# dem auf y=0 eingeebneten Terrain. Ohne eigene Kollision rasten die Räder auf dem
	# Terrain (y=0) ein -> der sichtbare Reifen steckt ~8 cm in der Bahn. Diese Box (inkl.
	# Schulter) lässt die Räder AUF der Bahn stehen. Layer 1 = Boden (Flugzeug-Maske).
	# Sie deckt die GANZE Schulter ab: rollt ein Rad neben den Asphalt, darf es nicht in
	# die 4 cm hohe Sandplatte fallen.
	var rwy_body := StaticBody3D.new()
	rwy_body.collision_layer = 1
	rwy_body.collision_mask = 0
	var rwy_cs := CollisionShape3D.new()
	var rwy_box := BoxShape3D.new()
	rwy_box.size = Vector3(schulter_b, 0.08, RWY_LEN + 40.0)
	rwy_cs.shape = rwy_box
	rwy_cs.position = Vector3(0, 0.04, 0)   # Oberkante bei y=0.08 (= Asphalt-Oberkante)
	rwy_body.add_child(rwy_cs)
	node.add_child(rwy_body)
	# Randlinien (durchgehend, volle Länge)
	for sx in [-1.0, 1.0]:
		_deco_box(node, Vector3(sx * (RWY_W * 0.5 - 1.0), 0.1, 0), Vector3(0.7, 0.04, RWY_LEN - 24.0), paint)
	# Mittellinie gestrichelt (30-m-Striche)
	# NUR AUF DEM ASPHALT. Hier stand RWY_LEN / 60 = 15, und die Schleife laeuft von -nd
	# bis +nd — die Striche reichten also von z -900 bis +900, waehrend die Bahn bei +-450
	# endet. Die halbe Mittellinie lag damit an JEDEM Platz als weisse Farbe im Gras; bei
	# ADLERHORST fuehrte sie ueber die Wiese bis ans Portal und war dort nicht mehr zu
	# uebersehen. Der letzte Strich braucht seine halbe Laenge (15 m) plus den
	# Schwellenbalken (12 m) Abstand zum Bahnende.
	var nd := int((RWY_LEN * 0.5 - 30.0) / 60.0)
	for i in range(-nd, nd + 1):
		_deco_box(node, Vector3(0, 0.1, i * 60.0), Vector3(0.9, 0.04, 30.0), paint)
	# Schwellen: "Piano-Keys" + Aufsetzpunkt-Blöcke + Touchdown-Paare
	for se in [-1.0, 1.0]:
		for x in [-12.0, -8.6, -5.2, -1.8, 1.8, 5.2, 8.6, 12.0]:
			_deco_box(node, Vector3(x, 0.1, se * (hl - 12.0)), Vector3(1.9, 0.04, 16.0), paint)
		for sx in [-1.0, 1.0]:
			_deco_box(node, Vector3(sx * 6.0, 0.1, se * (hl - 150.0)), Vector3(3.0, 0.04, 22.0), paint)   # Aufsetzpunkt
			_deco_box(node, Vector3(sx * 9.0, 0.1, se * (hl - 75.0)), Vector3(1.5, 0.04, 12.0), paint)    # TDZ
		# Bahnnummer (flach auf der Bahn, je Richtung)
		var num := _rwy_number(af["heading"], se < 0.0)
		var nlbl := Label3D.new()
		nlbl.text = num
		nlbl.font_size = 220
		nlbl.pixel_size = 0.05
		nlbl.modulate = Color(0.93, 0.93, 0.88)
		nlbl.position = Vector3(0, 0.12, se * (hl - 40.0))
		nlbl.rotation_degrees = Vector3(-90, 0 if se > 0.0 else 180, 0)
		node.add_child(nlbl)
	# --- Befeuerung: Rand weiß, Schwelle grün, Anflug pulsfrei weiß ---
	var nl := int(RWY_LEN / 75.0)
	for i in range(-nl, nl + 1):
		for sx in [-1.0, 1.0]:
			_deco_light(node, Vector3(sx * (RWY_W * 0.5 + 1.4), 0.4, i * 75.0), Color(0.95, 0.95, 0.85))
	for se in [-1.0, 1.0]:
		for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
			_deco_light(node, Vector3(x, 0.4, se * (hl + 2.0)), Color(0.25, 1.0, 0.4))
		for k in range(1, 6):
			_deco_light(node, Vector3(0, 0.6, se * (hl + 20.0 + k * 28.0)), Color(1.0, 0.95, 0.8))
	# --- REIFENSPUREN in der Aufsetzzone (dunkle Abrieb-Streifen, leicht versetzt) ---
	var rubber := _flat_mat(Color(0.09, 0.09, 0.10), 1.0)
	for se in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			for k in 4:
				var off := Vector3(sx * (4.6 + float(k) * 0.9), 0.085, se * (hl - 105.0 - float(k) * 14.0))
				_deco_box(node, off, Vector3(0.55, 0.015, 26.0 - float(k) * 3.0), rubber)
	# --- PAPI: 4-Lampen-Reihe links neben jeder Schwelle (2 weiß / 2 rot) ---
	for se in [-1.0, 1.0]:
		for k in 4:
			var pp := Vector3(-(RWY_W * 0.5 + 6.0 + float(k) * 3.2), 0.5, se * (hl - 130.0))
			_deco_box(node, pp - Vector3(0, 0.25, 0), Vector3(0.5, 0.5, 0.5), _flat_mat(Color(0.25, 0.26, 0.3), 0.8))
			_deco_light(node, pp + Vector3(0, 0.15, 0), Color(1.0, 0.97, 0.9) if k < 2 else Color(1.0, 0.18, 0.12))
	# --- Rollweg + Vorfeld (Beton) ---
	# ALLES AB HIER haengt am Unterknoten `vf`, der um VORFELD_Z nach Sueden versetzt ist
	# (Begruendung siehe dort). Die Zahlen unten sind deshalb weiter Vorfeld-Koordinaten.
	var vf := Node3D.new()
	vf.name = "Vorfeld"
	vf.position = Vector3(0.0, 0.0, VORFELD_Z)
	node.add_child(vf)
	# ADLERHORST LIEGT IM BERG UND BEKOMMT DIESES VORFELD NICHT. Es spannt lokal x 24 bis
	# 162 auf; die Halle ist 78 m halb breit. Alles ab x 78 steckt also im Fels, und die
	# beiden Hangars bei x 54 und 74 ragten als olivgruene Buckel durch die Wand — genau
	# das war im Bild zu sehen (tools/_kaverne_inventar.gd hat sie bei quer -54 gefunden,
	# nachdem drei Vermutungen daneben lagen).
	# ES WIRD GEBAUT UND DANN VERWORFEN statt uebersprungen: die Vorfeld-Strecke ist ein
	# Block von rund siebzig Zeilen mit neunzig Einzelkoordinaten, und ihn einzuruecken,
	# um ein if darumzulegen, waere die riskantere Aenderung. Der Bau kostet ein paar
	# Millisekunden EINMAL beim Start.
	var unter_tage := String(af.get("name", "")) == "ADLERHORST"
	# Die Betonstuecke ueberlappen sich absichtlich um ein bis zwei Meter, liegen dafuer
	# aber auf GESTAFFELTEN Hoehen (0.056 / 0.06 / 0.07 Oberkante). Gleich hohe, sich
	# ueberlappende Platten flimmern (Z-Fighting); 1 cm Stufe faellt beim Rollen nicht auf,
	# die Raeder stehen ohnehin auf dem eingeebneten Terrain bei y = 0.
	# SCHMALE HELLE KANTE unter dem ganzen Beton. In heimat_1 und heimat_4 stossen Vorfeld
	# und Rollweg nicht nackt ans Gras, sondern haben rundum einen schmalen, etwas HELLEREN
	# Randstreifen — kein Sandbett (das hat nur die Bahn). Erster Versuch war eine breite
	# Sandschuerze; die machte aus dem Platz eine Sandinsel, die in keiner Vorlage vorkommt.
	# 4 m Ueberstand, EIN Kasten, 12 Dreiecke.
	_deco_box(vf, Vector3(93.0, 0.012, -5.0), Vector3(138.0, 0.024, 198.0),
		_flat_mat(Color(0.76, 0.75, 0.71), 0.95))
	# ROLLWEGE IN ASPHALT, nicht in Beton: in heimat_1 und heimat_4 ist der Rollweg zwischen
	# Bahn und Vorfeld genauso dunkel wie die Bahn selbst und hebt sich als dunkles Band vom
	# hellen Vorfeld ab. In Betongrau verschmolz er mit dem Apron zu einer einzigen Flaeche
	# und der Platz verlor seine Gliederung.
	_deco_box(vf, Vector3(34.0, 0.030, -10.0), Vector3(12.0, 0.06, 200.0), asphalt)         # Rollweg parallel
	_deco_box(vf, Vector3(24.0, 0.028, -95.0), Vector3(32.0, 0.056, 14.0), asphalt)         # Verbinder Nord
	_deco_box(vf, Vector3(24.0, 0.028, 70.0), Vector3(32.0, 0.056, 14.0), asphalt)          # Verbinder Süd
	_deco_box(vf, Vector3(82.0, 0.035, -5.0), Vector3(88.0, 0.07, 190.0), concrete)         # Apron
	# Plattenfugen: in den Vorlagen ist das Vorfeld sichtbar in Felder geteilt. Ohne die
	# Fugen liest sich die Flaeche aus der Luft als graue Pappe. 9 Streifen, keine Kollision.
	# DUNKLER als der Beton (vorher heller): in heimat_3/heimat_4 sind die Plattenstoesse
	# Schattenfugen, keine weissen Striche — hell gezeichnet sahen sie aus wie Markierungen.
	var fuge := _flat_mat(Color(0.58, 0.57, 0.54), 0.9)
	for fz in [-80.0, -40.0, 0.0, 40.0, 80.0]:
		_deco_box(vf, Vector3(82.0, 0.072, fz), Vector3(88.0, 0.02, 0.3), fuge)
	for fx in [50.0, 72.0, 94.0, 116.0]:
		_deco_box(vf, Vector3(fx, 0.072, -5.0), Vector3(0.3, 0.02, 190.0), fuge)
	# Gelbe Fuehrungslinien: Rollweg-Mitte, beide Verbinder und die Vorfeld-Achse.
	_deco_box(vf, Vector3(34.0, 0.065, -10.0), Vector3(0.5, 0.02, 195.0), paint_y)
	for cz in [-95.0, 70.0]:
		_deco_box(vf, Vector3(25.0, 0.062, cz), Vector3(30.0, 0.02, 0.5), paint_y)
	_deco_box(vf, Vector3(84.0, 0.076, -28.0), Vector3(92.0, 0.02, 0.5), paint_y)
	_deco_box(vf, Vector3(60.0, 0.076, 22.0), Vector3(0.5, 0.02, 100.0), paint_y)
	# GEBOGENE EINROLLLINIE vom Rollweg auf die Vorfeldachse. In heimat_1 und heimat_3 ist
	# die gelbe Fuehrung KURVIG — genau das unterscheidet ein Vorfeld von einem Parkplatz;
	# rechte Winkel rollt kein Flugzeug. Viertelkreis, Mittelpunkt (59, -3), Halbmesser 25:
	# beruehrt bei (34, -3) die Rollwegmitte und bei (59, -28) die Vorfeldachse.
	# 12 Stuecke = 144 Dreiecke.
	for k in 12:
		var a_bog := PI + (PI * 0.5) * (float(k) + 0.5) / 12.0
		var st_bog := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.02, 25.0 * (PI * 0.5) / 12.0 + 0.2)
		st_bog.mesh = bm
		st_bog.position = Vector3(59.0 + cos(a_bog) * 25.0, 0.076, -3.0 + sin(a_bog) * 25.0)
		st_bog.rotation.y = -a_bog                       # Laengsachse tangential zum Kreis
		st_bog.material_override = paint_y
		vf.add_child(st_bog)
	# --- Gebäude aufs Vorfeld (Reihe quer zur Bahn, wie in allen vier Vorlagen) ---
	_add_hangar(vf, Vector3(54, 0, -55), af["color"])
	_add_hangar(vf, Vector3(74, 0, -55), af["color"])
	_add_tower(vf, TOWER_POS)
	_add_ops_haus(vf, Vector3(114, 0, -55))
	_add_windsock(vf, Vector3(84, 0, -34))
	# Tanklager: drei weiße Zylinder in einer Auffangwanne (Vorlage: Silos neben dem
	# Betriebsgebaeude, nicht frei im Beton stehend).
	_deco_box(vf, Vector3(62.0, 0.5, -12.0), Vector3(26.0, 1.0, 10.0), _flat_mat(Color(0.62, 0.62, 0.60), 0.9))
	for tx in [54.0, 62.0, 70.0]:
		var tank := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 3.2
		cm.bottom_radius = 3.2
		cm.height = 8.0
		cm.radial_segments = 12
		cm.rings = 1
		tank.mesh = cm
		tank.position = Vector3(tx, 5.0, -12.0)
		tank.material_override = _flat_mat(Color(0.88, 0.89, 0.9), 0.45)
		vf.add_child(tank)
		_collider_box(vf, Vector3(tx, 5.0, -12.0), Vector3(6.8, 9, 6.8))
	if unter_tage:
		node.remove_child(vf)
		vf.queue_free()
		_kavernen_vorfeld(node, af["color"])

	# Namensschild hoch oben (immer sichtbar)
	var lbl := Label3D.new()
	lbl.text = af["name"]
	lbl.font_size = 130
	lbl.pixel_size = 0.22
	# UNTER TAGE ANS PORTAL, NICHT IN DIE MITTE DES BERGES. Das Schild traegt
	# no_depth_test, ist also durch Gestein hindurch sichtbar — das ist so gewollt, denn
	# aus der Luft muss man die Basis finden. Auf der Platzmitte haengt es dabei 500 m
	# TIEF IM MASSIV: von aussen schwebt es irgendwo ueber dem Kamm, von innen steht es
	# mitten in der Halle und verdeckt das Portal. Am Mund (lokal z = +510) zeigt es von
	# aussen auf den Eingang und ist von innen aus dem Weg.
	lbl.position = Vector3(0, 50, 510) if unter_tage else Vector3(0, 60, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	# NUR AUS DER FERNE. Das Schild ist eine Navigationshilfe fuer den Anflug und traegt
	# deshalb no_depth_test — es leuchtet durch Gestein. In der Halle stand es damit
	# formatfuellend quer im Bild und verdeckte ausgerechnet das Portal, also den einzigen
	# Blickpunkt der Aufnahme. Ab 700 m ist es wieder da, wo es gebraucht wird.
	if unter_tage:
		# 1500, NICHT 700: die Halle ist 1080 m tief, und aus ihrem hinteren Ende stand
		# das Schild bei 700 wieder im Bild — ausgerechnet quer ueber dem Portal, dem
		# einzigen Blickpunkt der Aufnahme. Jenseits von 1500 m ist man draussen.
		lbl.visibility_range_begin = 1500.0
		lbl.visibility_range_begin_margin = 200.0
	lbl.modulate = af["color"]
	lbl.outline_size = 26
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	node.add_child(lbl)
	# Umfeld: Baumguertel, Felsbrocken, Platzzaun (siehe _gruenguertel).
	# ADLERHORST LIEGT IM BERG und bekommt deshalb die Kavernenfassung: keine Baeume,
	# kein Zaun, keine Trockenflecken. Ohne diesen Schalter pflanzte der Saum seine
	# Nadelbaeume auf den Hallenboden und zog den Platzzaun bei lokal x = -78 quer durch
	# den Fels — beides im Bild zu sehen, und beides wusste nichts von der Roehre.
	_gruenguertel(node, String(af.get("name", "")) == "ADLERHORST")
	# HEIMAT = Hauptbasis: großes Extra-Paket (Radar, Großhangar, Flutlicht, Helipad, …)
	if af.get("main", false):
		_build_main_base(vf, af["color"])


# Hauptbasis-Ausbau für HEIMAT: erweitertes Vorfeld, offener Großhangar (begehbar),
# drehender Radarturm, Tower-Antenne mit Blinklicht, Flutlicht-Masten, Helipad,
# Splitterschutz-Boxen (Blast Pens) mit GEPARKTEN Flugzeugen aus den Vorlagen.
## EIN SENDEMAST, 165 M HOCH — die einzige Marke der Karte, die von weit her trägt.
##
## WOFUER. Beide unabhaengigen Weltabnahmen haben denselben Satz geschrieben: es gibt auf
## dieser Insel nichts, worauf man zufliegen moechte. Der Horizont ist in jeder
## Weitaufnahme derselbe Streifen austauschbarer Huegel, und der Beweis steht im Bild
## selbst — die Welt traegt schwebende Schilder ("HEIMAT", "BERGPISTE"), weil die
## Geometrie dem Piloten nicht sagen kann, wo etwas ist. In einem Flugspiel IST die
## Silhouette die Navigationsanzeige.
##
## WARUM EIN MAST UND NICHT EIN GROESSERES GEBAEUDE. Ein Turm mit 165 m ist aus acht
## Kilometern noch ein senkbarer Strich am Horizont, kostet aber nur ein Dutzend Kaesten —
## und ein duenner senkrechter Strich ist genau das, was in einer Landschaft aus liegenden
## Formen auffaellt. Das rote Blinklicht macht ihn ausserdem bei schlechter Sicht und im
## Gegenlicht auffindbar, also genau dann, wenn man ihn braucht.
##
## Die Abspannungen sind kein Zierrat: ohne sie liest sich ein 165-m-Strich als Fehler im
## Bild, mit ihnen als Bauwerk.
func _sendemast(node: Node3D, wo: Vector3) -> void:
	var stahl := _flat_mat(Color(0.62, 0.24, 0.20), 0.7)     # Signalrot-Weiss-Anstrich
	var weiss := _flat_mat(Color(0.88, 0.88, 0.86), 0.7)
	var hoehe := 165.0
	var felder := 11                                          # Schuesse zu je 15 m
	var b0 := 5.2                                             # Breite unten
	var b1 := 1.6                                             # Breite oben
	for i in felder:
		var t0 := float(i) / float(felder)
		var t1 := float(i + 1) / float(felder)
		var y0 := hoehe * t0
		var y1 := hoehe * t1
		var br0 := lerpf(b0, b1, t0) * 0.5
		var br1 := lerpf(b0, b1, t1) * 0.5
		var mat: Material = stahl if i % 2 == 0 else weiss
		# Vier Eckstiele je Schuss. Sie stehen leicht schraeg, weil der Mast sich verjuengt.
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var u := wo + Vector3(sx * br0, y0, sz * br0)
				var o := wo + Vector3(sx * br1, y1, sz * br1)
				var m := (u + o) * 0.5
				var laenge := u.distance_to(o)
				var bx := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.42, laenge, 0.42)
				bx.mesh = bm
				bx.position = m
				# Neigung des Stiels: er wandert je Schuss um (br0-br1) nach innen.
				bx.rotation = Vector3(atan2(sz * (br1 - br0), laenge), 0.0,
					-atan2(sx * (br1 - br0), laenge))
				bx.material_override = mat
				node.add_child(bx)
		# Riegel oben auf jedem Schuss — ohne sie ist es ein Bund Stangen, kein Fachwerk.
		for sx2 in [-1.0, 1.0]:
			_deco_box(node, wo + Vector3(sx2 * br1, y1, 0.0),
				Vector3(0.3, 0.3, br1 * 2.0), mat)
			_deco_box(node, wo + Vector3(0.0, y1, sx2 * br1),
				Vector3(br1 * 2.0, 0.3, 0.3), mat)
	# Abspannungen: drei Seile in 120 Grad, vom oberen Drittel zum Boden.
	for i in 3:
		var a := TAU * float(i) / 3.0
		var fuss := wo + Vector3(cos(a), 0.0, sin(a)) * 62.0
		var kopf := wo + Vector3(0.0, hoehe * 0.72, 0.0)
		var seil := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.16, fuss.distance_to(kopf), 0.16)
		seil.mesh = sm
		seil.position = (fuss + kopf) * 0.5
		seil.look_at_from_position(seil.position, kopf, Vector3.UP)
		# look_at richtet -Z aus; der Kasten steht auf +Y. Um X kippen bringt beides zusammen.
		seil.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		seil.material_override = _flat_mat(Color(0.30, 0.30, 0.32), 0.8)
		node.add_child(seil)
		_deco_box(node, fuss + Vector3(0.0, 0.8, 0.0), Vector3(2.0, 1.6, 2.0),
			_flat_mat(Color(0.55, 0.55, 0.52), 0.9))
	# KOLLISION AUF DEN GANZEN MAST. Bisher hatte er keine — Konvention der uebrigen
	# Platzbauten, aber bei 165 m Hoehe eine schlechte: ein Hindernis, das genau die
	# Hoehen bedeckt, in denen man den Platz anfliegt, und durch das man hindurchfaellt,
	# ist keine Marke, sondern eine Luege im Bild. EIN Kasten ueber die volle Hoehe
	# genuegt; die Gitterstruktur muss nicht einzeln getroffen werden.
	var kk := StaticBody3D.new()
	kk.collision_layer = 1
	node.add_child(kk)
	var ks := CollisionShape3D.new()
	var kb := BoxShape3D.new()
	kb.size = Vector3(b0 * 0.8, hoehe, b0 * 0.8)
	ks.shape = kb
	ks.position = wo + Vector3(0.0, hoehe * 0.5, 0.0)
	kk.add_child(ks)

	# Spitze mit Blinklicht.
	_deco_box(node, wo + Vector3(0.0, hoehe + 4.0, 0.0), Vector3(0.3, 8.0, 0.3), weiss)
	var lampe := MeshInstance3D.new()
	var ls := SphereMesh.new()
	ls.radius = 1.4
	ls.height = 2.8
	ls.radial_segments = 8
	ls.rings = 5
	lampe.mesh = ls
	lampe.position = wo + Vector3(0.0, hoehe + 8.5, 0.0)
	lampe.material_override = _emit_mat(Color(1.0, 0.16, 0.12), 6.0)
	node.add_child(lampe)
	var licht := OmniLight3D.new()
	licht.light_color = Color(1.0, 0.2, 0.15)
	licht.light_energy = 8.0
	licht.omni_range = 60.0
	licht.shadow_enabled = false
	licht.position = lampe.position
	node.add_child(licht)


func _build_main_base(node: Node3D, _col: Color) -> void:
	# EXAKT derselbe Ton wie in _build_airfield — die Erweiterung stoesst dort buendig an.
	# Mit den frueheren 0.60 gegen 0.55 war die Naht als Farbkante quer ueber das Vorfeld
	# zu sehen (in heimat_3 ist die Flaeche einheitlich).
	var concrete := _flat_mat(Color(0.70, 0.69, 0.65), 0.9)
	# --- Vorfeld nach Osten erweitern (stoesst BUENDIG an die Basisplatte bei x = 126:
	# ueberlappende gleich hohe Platten flimmern, eine geteilte Kante nicht) ---
	_deco_box(node, Vector3(142.0, 0.035, -5.0), Vector3(32.0, 0.07, 190.0), concrete)
	# SENDEMAST NEBEN DEM PLATZ. Weit genug von der Bahn, dass er keine Anflugachse
	# schneidet, nah genug, dass er den Platz markiert und nicht irgendein Feld.
	_sendemast(node, Vector3(196.0, 0.0, 150.0))
	# --- Offener Großhangar als TONNENHALLE ---
	# Vorher: vier graue Kisten (Rueckwand, zwei Seiten, Dachplatte). Die Vorlage zeigt an
	# dieser Stelle das Wahrzeichen des Platzes — eine Bogenhalle mit offener Stirn, in der
	# ein Flugzeug steht. _tonnenhalle baut die Schale als EIN ArrayMesh (aussen + innen +
	# Laibung, 6 Dreiecke je Segment); bei 12 Segmenten sind das 72 Dreiecke gegen vorher
	# 48 aus vier Boxen — der Mehrpreis fuer die Form ist also ein knappes Drittel.
	var hcol := Color(0.42, 0.45, 0.36)     # Olivgruen wie in allen vier Vorlagen
	# GRUNDFLAECHE ZURUECKGESTUTZT: vorher 34 x 40 m = 1360 m^2 gegen 2 x 16 x 20 = 640 m^2
	# der beiden geschlossenen Tonnenhallen — also rund die doppelte Flaeche, und im Bild
	# schluckte die Halle alles andere. Jetzt 27 x 28 m = 756 m^2, immer noch das groesste
	# und mit 13,5 m das hoechste Gebaeude auf dem Vorfeld (die kleinen sind 8 m), aber in
	# der Groessenordnung der Vorlage. Nebeneffekt: 27 statt 34 m Spannweite spart an der
	# Schale genau die Dreiecke wieder ein, die der Ausbau kostet.
	var h_rad := 13.5
	var h_tief := 28.0
	_tonnenhalle(node, Vector3(122.0, 0.0, 5.0), h_rad, h_tief, 0.0, hcol, false)
	_deco_box(node, Vector3(122.0, 0.05, 5.0), Vector3(2.0 * h_rad + 1.5, 0.05, h_tief - 1.0),
		_flat_mat(Color(0.66, 0.66, 0.64), 0.9))                                    # Hallenboden (heller Beton)
	# Der Flieger steht IM TOR, nicht hinten in der Halle: 13 m tiefer drin lag er im
	# Eigenschatten der Schale und war im Bild nicht mehr auszumachen. Das Tor liegt bei
	# z = 5 + 14 = 19; auf 14,5 steht der Rumpf gerade noch in der Laibung und die Nase
	# davor — genauso wie in heimat_3.
	_add_parked_plane(node, "spitfire", Vector3(122.0, 1.0, 14.5), 0.0)              # Flieger IM Tor
	# --- Radar: GITTERTURM mit drehender Schuessel ---
	# Die Vorlage zeigt einen Fachwerkmast, keine Betonsaeule. Das Gitter ist EIN Mesh
	# (SurfaceTool, ~250 Dreiecke, 1 Zeichenaufruf) statt 20 einzelner Boxen.
	# GROESSER als vorher (24 m / Schuessel 4,2 m). In heimat_3 und heimat_4 ist der Radarmast
	# das HOECHSTE Bauwerk des Platzes, deutlich ueber dem 25-m-Tower, und die Schuessel misst
	# rund ein Drittel der Masthoehe. Mit 24 m stand er niedriger als der Tower und ging
	# neben dem Grosshangar unter. Der Mast ist EIN gebackenes Mesh — groesser kostet kein
	# einziges Dreieck mehr, nur das Gelaender (4 Kaesten = 48 Dreiecke) kommt dazu.
	var rt := Vector3(146.0, 0.0, -35.0)
	_gitterturm(node, rt, 32.0, 5.0, 3.0)
	_collider_box(node, rt + Vector3(0, 16.0, 0), Vector3(10.0, 32.0, 10.0))
	for s3 in [1.0, -1.0]:                                       # Gelaender der Plattform
		_deco_box(node, rt + Vector3(0, 33.3, s3 * 4.0), Vector3(8.0, 0.12, 0.12), _flat_mat(Color(0.6, 0.61, 0.63), 0.7))
		_deco_box(node, rt + Vector3(s3 * 4.0, 33.3, 0), Vector3(0.12, 0.12, 8.0), _flat_mat(Color(0.6, 0.61, 0.63), 0.7))
	var pivot := Node3D.new()
	pivot.position = rt + Vector3(0, 33.8, 0)
	node.add_child(pivot)
	var dish := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 5.6
	dm.bottom_radius = 3.4      # flacher Kegelstumpf = Parabolschuessel im Low-Poly-Stil
	dm.height = 1.4
	dm.radial_segments = 14
	dm.rings = 1
	dish.mesh = dm
	dish.position = Vector3(0, 1.4, 0)
	dish.rotation_degrees = Vector3(58, 0, 0)
	dish.material_override = _flat_mat(Color(0.85, 0.87, 0.9), 0.4)
	pivot.add_child(dish)
	_deco_box(pivot, Vector3(0, 2.6, -1.6), Vector3(0.3, 0.3, 2.6), _flat_mat(Color(0.5, 0.5, 0.55), 0.5))  # Erreger
	_spin_nodes.append(pivot)
	# --- Tower-Antenne mit rotem Blinklicht (Standort aus TOWER_POS) ---
	_deco_box(node, TOWER_POS + Vector3(0, 28.5, 0), Vector3(0.4, 6.0, 0.4), _flat_mat(Color(0.7, 0.7, 0.72), 0.5))
	var bl := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.5
	bs.height = 1.0
	bl.mesh = bs
	bl.position = TOWER_POS + Vector3(0, 32.1, 0)
	bl.material_override = _emit_mat(Color(1.0, 0.15, 0.1), 3.0)
	node.add_child(bl)
	_blink_nodes.append(bl)
	# --- Flutlicht-Masten am Vorfeldrand (siehe _flutlichtmast) ---
	# Ziel jeder Kopfgruppe ist die Vorfeldmitte: die Scheinwerfer leuchten das Vorfeld
	# aus, nicht die Landschaft. Aus dem Standort ergibt sich damit die Drehung von selbst
	# — ein fester Winkel haette bei fuenf ueber das Vorfeld verteilten Masten zwangslaeufig
	# an mindestens zwei davon in die falsche Richtung gezeigt.
	var vf_mitte := Vector3(93.0, 0.0, -5.0)
	var mast_xf: Array[Transform3D] = []
	for fp in [Vector3(44, 0, -80), Vector3(44, 0, 45), Vector3(96, 0, 84),
			Vector3(154, 0, -60), Vector3(154, 0, 30)]:
		var zu: Vector3 = vf_mitte - fp
		mast_xf.append(Transform3D(Basis(Vector3.UP, atan2(zu.x, zu.z)), fp))
		# Kollision wie bisher, nur bis zur neuen Gesamthoehe (Sockel 1,0 + Mast bis 16,35 +
		# Leuchtenkranz bis 17,6). Ohne sie flaege man durch den Mast hindurch.
		_collider_box(node, fp + Vector3(0, 8.8, 0), Vector3(1.3, 17.6, 1.3))
	_flutlichtmast(node, mast_xf)
	_build_base_life(node)
	# --- Helipad auf dem Vorfeld (Vorlage: es liegt AUF dem Beton, nicht drueben im Gras) ---
	# Aufbau von unten: heller Betonteller, dunkler Belag darauf (das Ueberstehen des
	# Tellers ERZEUGT den weissen Ring — billiger als ein Torus), gelber Kreisring aus
	# 16 kurzen Segmenten, weisses H.
	var hp := Vector3(140.0, 0.0, 60.0)
	for r_pad in [[11.0, 0.03, Color(0.86, 0.86, 0.84)], [9.6, 0.05, Color(0.26, 0.27, 0.29)]]:
		var pad := MeshInstance3D.new()
		var pc := CylinderMesh.new()
		pc.top_radius = float(r_pad[0])
		pc.bottom_radius = float(r_pad[0])
		pc.height = 0.06
		pc.radial_segments = 24
		pc.rings = 1
		pad.mesh = pc
		pad.position = hp + Vector3(0, float(r_pad[1]), 0)
		pad.material_override = _flat_mat(r_pad[2], 0.9)
		node.add_child(pad)
	var gelb_ring := _emit_mat(Color(0.95, 0.8, 0.2), 0.18)
	for seg in 16:
		var a := float(seg) * TAU / 16.0
		var ring := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.5, 0.02, 3.1)
		ring.mesh = rb
		ring.position = hp + Vector3(cos(a) * 8.4, 0.09, sin(a) * 8.4)
		ring.rotation.y = -a
		ring.material_override = gelb_ring
		node.add_child(ring)
	var hl3 := Label3D.new()
	hl3.text = "H"
	hl3.font_size = 380
	hl3.pixel_size = 0.05
	hl3.modulate = Color(0.95, 0.95, 0.9)
	hl3.position = hp + Vector3(0, 0.12, 0)
	hl3.rotation_degrees = Vector3(-90, 0, 0)
	node.add_child(hl3)
	for ang in range(8):
		var a2 := float(ang) * TAU / 8.0
		_deco_light(node, hp + Vector3(cos(a2) * 11.4, 0.3, sin(a2) * 11.4), Color(1.0, 0.8, 0.25))
	# --- Drei Splitterschutz-Boxen (Blast Pens), Oeffnung zur Bahn hin ---
	# Sandbeige statt Betongrau und in einer Reihe laengs des Vorfeldrands — so stehen sie
	# in heimat_1 und heimat_4. Jede Box: Rueckwand + zwei Seitenwaelle, alle mit Kollision
	# (man kann hineinfliegen).
	var pen_mat := _flat_mat(Color(0.68, 0.63, 0.48), 0.95)
	# Die Oeffnung zeigt nach SUEDEN (+Z) — also in die Blickrichtung von drei der vier
	# Abnahme-Ansichten. Mit der Oeffnung zur Seite war von den Jets nichts zu sehen:
	# die Kamera steht 60 m hoch und 290 m weit weg, das sind 10 Grad Senkung, und schon
	# eine 3,8-m-Wand verdeckt bei 10 Grad alles bis 21 m dahinter — die ganze 16-m-Box.
	# HOEHER (4,6 statt 3,8 m) und mit ABGETREPPTER Seitenwand: in heimat_1 und heimat_4 ist
	# der Wall hinten hoch und faellt zur Oeffnung hin ab. Erster Versuch dieser Runde war
	# stattdessen ein angeschuetteter Fuss (3 m dicke Sohle) — im Bild las sich die Box
	# daraufhin als Badewanne, in der die Jets bis zur Kanzel versanken; die Vorlage zeigt
	# duenne Waende und darin ein gut sichtbares Flugzeug. Jetzt: 1,4 m Wandstaerke,
	# hinten pen_h, vorn 0,62 x pen_h.
	# Ueber 4,6 m geht nicht: die Parkflieger sind rund 4 m hoch, und aus fp_vorfeld (Kamera
	# 60 m hoch, 200 m weit = 17 Grad Senkung) verdeckt schon eine 5,2-m-Wand 17 m dahinter,
	# also die ganze 16-m-Box samt Flieger.
	# 5 Kaesten je Platz (60 Dreiecke) gegen vorher 3 — die Kollision bleibt bei 3 Kaesten,
	# der niedrigere Vorderteil steckt in derselben Box wie der hintere.
	var pen_h := 4.6
	var pens := [Vector3(54.0, 0.0, 60.0), Vector3(78.0, 0.0, 60.0), Vector3(102.0, 0.0, 60.0)]
	for i in pens.size():
		var pp: Vector3 = pens[i]
		_deco_box(node, pp + Vector3(0.0, pen_h * 0.5, -8.5), Vector3(17.0, pen_h, 1.4), pen_mat)   # Rückwand (Nord)
		_collider_box(node, pp + Vector3(0.0, pen_h * 0.5, -8.5), Vector3(17.0, pen_h, 1.4))
		for sx2 in [-8.0, 8.0]:
			_deco_box(node, pp + Vector3(sx2, pen_h * 0.5, -4.0), Vector3(1.4, pen_h, 8.0), pen_mat)         # hinten hoch
			_deco_box(node, pp + Vector3(sx2, pen_h * 0.31, 4.0), Vector3(1.4, pen_h * 0.62, 8.0), pen_mat)  # vorn niedriger
			_collider_box(node, pp + Vector3(sx2, pen_h * 0.5, 0.0), Vector3(1.4, pen_h, 16.0))
		_deco_box(node, pp + Vector3(0.0, 0.08, 5.0), Vector3(9.0, 0.02, 0.4), _emit_mat(Color(0.95, 0.8, 0.2), 0.18))
	# In heimat_1 und heimat_4 steht in JEDER Box ein Jet, und auf dem freien Vorfeld steht
	# KEIN Flugzeug (dort stehen Fahrzeuge und Kisten). Die Mustang, die bisher frei auf dem
	# Beton parkte, wandert deshalb als MiG-21 in die dritte Box: gleiche Anzahl Parkflieger
	# wie vorher, also KEIN Dreieck mehr — ein Parkflieger kostet gemessen rund 35 000
	# Dreiecke und 77 Zeichenaufrufe, ein vierter waere der teuerste Posten dieser Runde
	# gewesen.
	_add_parked_plane(node, "f86", pens[0] + Vector3(0.0, 1.0, 1.0), 180.0)
	_add_parked_plane(node, "mig15", pens[1] + Vector3(0.0, 1.0, 1.0), 180.0)
	_add_parked_plane(node, "mig21", pens[2] + Vector3(0.0, 1.0, 1.0), 180.0)


# Geparktes Deko-Flugzeug aus einer Vorlage (nur Visuals + ein grober Kollisionsblock).
# "Leben" auf dem Vorfeld: Tankwagen, Feuerwehr, Gepäckzug, Pylonen, Schilder,
# Parkpositions-Linien, Drehfeuer auf dem Tower, Antennen-Farm. Alles Low-Poly-
# Boxen/Zylinder aus den vorhandenen Helfern — billig, aber der Platz wirkt benutzt.
func _build_base_life(node: Node3D) -> void:
	var yellow := _flat_mat(Color(0.95, 0.78, 0.1), 0.6)
	var red := _flat_mat(Color(0.82, 0.16, 0.1), 0.55)
	var metal := _flat_mat(Color(0.72, 0.74, 0.78), 0.35)
	var darkm := _flat_mat(Color(0.22, 0.23, 0.26), 0.8)
	var line_y := _flat_mat(Color(0.95, 0.8, 0.15), 0.9)
	# --- TANKWAGEN (gelb) auf dem Vorfeld ---
	_deco_truck(node, Vector3(100.0, 0.0, 40.0), 35.0, yellow, true)
	# --- FEUERWEHR: kleines Haus + roter Truck davor ---
	# Haus SANDFARBEN mit dunklem Dach, nicht mehr knallrot mit weissem Dach: in den vier
	# Vorlagen ist KEIN einziges Gebaeude rot, alle Nebenbauten sind sand/oliv mit dunklem
	# Flachdach — der rote Kasten war in heimat_3-Perspektive der auffaelligste Fleck des
	# ganzen Platzes und zog das Auge auf etwas, das die Vorlage gar nicht kennt.
	# Rot bleibt, wo es hingehoert: Tor und Fahrzeug.
	var fh := Vector3(50.0, 0.0, -86.0)
	_deco_box(node, fh + Vector3(0, 3.0, 0), Vector3(12.0, 6.0, 10.0), _flat_mat(Color(0.80, 0.75, 0.62), 0.85))
	_collider_box(node, fh + Vector3(0, 3.0, 0), Vector3(12.0, 6.0, 10.0))
	_deco_box(node, fh + Vector3(0, 6.3, 0), Vector3(13.0, 0.6, 11.0), _flat_mat(Color(0.34, 0.35, 0.36), 0.85))
	_deco_box(node, fh + Vector3(-3.0, 2.2, 5.1), Vector3(4.5, 4.4, 0.2), red)     # Tor
	_deco_truck(node, fh + Vector3(4.0, 0.0, 9.0), 90.0, red, false)
	# --- GEPÄCK-ZUG: Zugmaschine + 2 Anhänger ---
	var bz := Vector3(72.0, 0.0, 30.0)
	_deco_box(node, bz + Vector3(0, 0.8, 0), Vector3(2.0, 1.2, 3.0), metal)
	_collider_box(node, bz + Vector3(0, 0.8, 0), Vector3(2.0, 1.2, 3.0))
	for i in [1, 2]:
		_deco_box(node, bz + Vector3(0, 0.7, 3.6 * float(i)), Vector3(1.8, 1.0, 2.6), darkm)
		_deco_box(node, bz + Vector3(0, 1.35, 3.6 * float(i)), Vector3(1.6, 0.5, 2.2), yellow)
	# --- PYLONEN-Reihe am Vorfeldrand ---
	var cone := _flat_mat(Color(1.0, 0.45, 0.1), 0.6)
	for i in 6:
		var cp := Vector3(92.0, 0.0, -38.0 + float(i) * 6.0)
		var cm := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.35
		cyl.height = 0.9
		cm.mesh = cyl
		cm.position = cp + Vector3(0, 0.45, 0)
		cm.material_override = cone
		node.add_child(cm)
	# --- PARKPOSITIONEN: gelbe Führungslinien + Stopplinie (3 Stellplätze) ---
	for i in 3:
		var px := 86.0
		var pz := -36.0 + float(i) * 16.0
		_deco_box(node, Vector3(px, 0.07, pz), Vector3(10.0, 0.02, 0.35), line_y)          # Einrolllinie
		_deco_box(node, Vector3(px - 5.0, 0.07, pz), Vector3(0.35, 0.02, 5.0), line_y)     # Stopp-T
	# --- TAXIWAY-SCHILDER (gelb auf schwarz) ---
	for spz in [-70.0, -20.0, 30.0]:
		_deco_box(node, Vector3(44.0, 0.55, spz), Vector3(0.25, 1.1, 1.8), darkm)
		_deco_box(node, Vector3(44.0, 0.75, spz), Vector3(0.3, 0.5, 1.5), yellow)
	# --- DREHFEUER auf dem Tower (rotierender Doppel-Strahl, grün/weiß) ---
	var beacon_pivot := Node3D.new()
	beacon_pivot.position = TOWER_POS + Vector3(0.0, 26.5, 0.0)
	node.add_child(beacon_pivot)
	var b1 := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(2.6, 0.25, 0.25)
	b1.mesh = bb
	b1.position = Vector3(1.3, 0, 0)
	b1.material_override = _emit_mat(Color(1.0, 1.0, 0.9), 4.0)
	beacon_pivot.add_child(b1)
	var b2 := MeshInstance3D.new()
	b2.mesh = bb
	b2.position = Vector3(-1.3, 0, 0)
	b2.material_override = _emit_mat(Color(0.2, 1.0, 0.4), 4.0)
	beacon_pivot.add_child(b2)
	_spin_nodes.append(beacon_pivot)
	# --- ANTENNEN-FARM am Nordrand des Vorfelds ---
	for i in 3:
		var ap := Vector3(96.0 + float(i) * 4.0, 0.0, -86.0)
		var hgt := 9.0 + float(i) * 3.0
		_deco_box(node, ap + Vector3(0, hgt * 0.5, 0), Vector3(0.25, hgt, 0.25), metal)
		_deco_light(node, ap + Vector3(0, hgt + 0.3, 0), Color(1.0, 0.2, 0.15))
	# --- MATERIALKISTEN an den Hallenwaenden -------------------------------------------
	# In allen vier Vorlagen steht ueberall olives Kistengut herum — das ist es, was den
	# Beton benutzt aussehen laesst. EIN MultiMesh fuer 16 Kisten: 1 Zeichenaufruf,
	# 16 x 12 = 192 Dreiecke. Einzeln waeren es 16 Zeichenaufrufe.
	# Keine Kollision: 1,4 m hohe Kisten, in die niemand hineinfliegt.
	var kisten: Array[Transform3D] = []
	for kp in [Vector3(46.0, 0, -44.0), Vector3(48.2, 0, -44.6), Vector3(47.0, 0, -46.6),
			Vector3(83.0, 0, -44.0), Vector3(85.1, 0, -44.8), Vector3(104.0, 0, -40.0),
			Vector3(106.0, 0, -40.7), Vector3(105.0, 0, -42.4), Vector3(138.0, 0, -14.0),
			Vector3(140.1, 0, -14.7), Vector3(139.0, 0, -16.3), Vector3(152.0, 0, -47.0),
			Vector3(154.0, 0, -47.8), Vector3(64.0, 0, 34.0), Vector3(66.1, 0, 34.7),
			Vector3(65.0, 0, 36.2)]:
		var s := 0.8 + fmod(absf(kp.x + kp.z) * 0.17, 0.45)     # leichte Groessenstreuung
		kisten.append(Transform3D(Basis(Vector3.UP, fmod(kp.x * 1.7, TAU)).scaled(Vector3(s, s, s)),
			kp + Vector3(0, 0.7 * s, 0)))
	var kiste := BoxMesh.new()
	kiste.size = Vector3(1.8, 1.4, 1.8)
	_multi(node, kiste, kisten, _flat_mat(Color(0.40, 0.42, 0.30), 0.9))


# Low-Poly-Truck: Kabine + Aufbau (Tank-Zylinder beim Tanker, Kasten bei der Feuerwehr).
func _deco_truck(parent: Node3D, pos: Vector3, yaw_deg: float, body_mat: Material, tanker: bool) -> void:
	var t := Node3D.new()
	t.position = pos
	t.rotation_degrees = Vector3(0, yaw_deg, 0)
	parent.add_child(t)
	var darkm := _flat_mat(Color(0.18, 0.19, 0.22), 0.8)
	_deco_box(t, Vector3(0, 0.55, 2.6), Vector3(2.2, 1.5, 1.6), body_mat)       # Kabine
	_deco_box(t, Vector3(0, 1.05, 2.55), Vector3(1.9, 0.7, 1.2), _flat_mat(Color(0.6, 0.75, 0.85), 0.2))  # Scheiben
	if tanker:
		var cyl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.height = 4.6
		cyl.mesh = cm
		cyl.rotation_degrees = Vector3(90, 0, 0)
		cyl.position = Vector3(0, 1.25, -0.6)
		cyl.material_override = body_mat
		t.add_child(cyl)
	else:
		_deco_box(t, Vector3(0, 1.15, -0.6), Vector3(2.2, 2.0, 4.6), body_mat)
		_deco_box(t, Vector3(0, 2.35, -0.6), Vector3(0.5, 0.4, 2.0), _flat_mat(Color(0.9, 0.9, 0.95), 0.4))
	for wz in [1.9, -1.9]:
		for wx in [-1.05, 1.05]:
			var wm := MeshInstance3D.new()
			var wc := CylinderMesh.new()
			wc.top_radius = 0.45
			wc.bottom_radius = 0.45
			wc.height = 0.4
			wm.mesh = wc
			wm.rotation_degrees = Vector3(0, 0, 90)
			wm.position = Vector3(wx, 0.45, wz)
			wm.material_override = darkm
			t.add_child(wm)
	var cb := StaticBody3D.new()
	cb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.4, 2.6, 7.0)
	cs.shape = bs
	cs.position = Vector3(0, 1.3, 0.3)
	cb.add_child(cs)
	t.add_child(cb)


func _add_parked_plane(parent: Node3D, preset: String, pos: Vector3, yaw_deg: float) -> void:
	var f := FileAccess.open("res://designs/%s.json" % preset, FileAccess.READ)
	if f == null:
		return
	var arr = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(arr) != TYPE_ARRAY:
		return
	var root := Node3D.new()
	root.name = "Parkflieger_" + preset       # im Szenenbaum wiederfindbar
	root.position = pos
	root.rotation_degrees = Vector3(0, yaw_deg, 0)
	parent.add_child(root)
	for item in arr:
		var id: String = item.get("id", "")
		if not PartCatalog.has(id):
			continue
		var p := PartCatalog.get_part(id)
		var c = item.get("color", [0, 0, 0, 0])
		var pcol := Color(c[0], c[1], c[2], c[3]) if (typeof(c) == TYPE_ARRAY and c.size() >= 4) else Color(0, 0, 0, 0)
		var sc = item.get("scale", [1, 1, 1])
		var scl := Vector3(sc[0], sc[1], sc[2]) if (typeof(sc) == TYPE_ARRAY and sc.size() >= 3) else Vector3.ONE
		var tp := float(item.get("taper", -1.0))
		if tp < 0.0:
			tp = float(p.get("taper", 1.0))
		var tpf := float(item.get("taper_front", -1.0))
		if tpf < 0.0:
			tpf = float(p.get("taper_front", 1.0))
		var vis := PartCatalog.build_visual(p, pcol, tp, tpf, float(item.get("taper_y", -1.0)), float(item.get("taper_front_y", -1.0)))
		vis.scale = scl
		var holder := Node3D.new()
		holder.transform = _array_to_xform(item.get("xform", []))
		holder.add_child(vis)
		root.add_child(holder)
	# grober Kollisionsblock, damit man nicht durch geparkte Flieger hindurchfliegt
	_collider_box(parent, pos + Vector3(0, 1.4, 0), Vector3(9.0, 3.0, 8.0))


# Bahnnummer aus dem Heading (dekorativ, wie echte Runway-Designatoren 01-36).
## BAHNOBERFLAECHE ALS PLATTENFELD. Vorher war der Belag EINE Box, also absolut
## gleichmaessig — in den Vorlagen ist er sichtbar in Platten geteilt und streut von
## Platte zu Platte im Ton. Solange die Flaeche uniform bleibt, wirkt sie wie Pappe,
## egal wie gut der Mittelwert getroffen ist.
##
## RUNDE 3 — DREI BEFUNDE AN DIESER FLAECHE, alle drei hier abgearbeitet:
##  1) KEINE FUGEN. Das auffaelligste Merkmal der Vorlage (heimat_2, Bahn im Vordergrund)
##     ist das sichtbare Fugenraster zwischen den Platten. Die alte Fassung setzte die
##     Platten stumpf aneinander; ohne Fuge verschmelzen zwei aehnlich helle Nachbarn zu
##     einer Flaeche und uebrig bleibt weiches Gewoelk statt eines Plattenfelds — genau
##     der "Nassflecken"-Eindruck. Jetzt laeuft zwischen den Feldern eine 4 cm breite,
##     15 % dunklere Fuge (FUGE_B / FUGE_F), als EIGENE, nicht ueberlappende Quads in
##     DERSELBEN Flaeche — koplanar und lueckenlos, also weder Z-Fighting noch Loecher.
##  2) FALSCHES FORMAT. 5 x 5 m waren Quadrate; die Vorlage zeigt quer zur Bahn schmalere,
##     laengs deutlich laengere Felder. Jetzt 5,0 m quer x 7,96 m laengs (900 / 113).
##     Das Raster liegt in BAHNKOORDINATEN — das Netz wird im Bahnknoten gebaut, die
##     Fugen laufen also zwangslaeufig parallel und rechtwinklig zur Bahnachse.
##  3) ZU WENIG STREUUNG. Gemessen im Pruefkasten (350,405)-(900,455) von fp_schwelle,
##     nur Grauwerte 30..130: vorher std 14.47 bei Mittel 74.98. Der Ton kam aus einem
##     Zufallszahlengeber; jetzt aus einem HASH DES RASTERINDEX (_platten_hash) — gleiche
##     Platte, gleicher Ton, unabhaengig von Aufbaureihenfolge und Startwert — und die
##     Amplitude steigt von +/-0.115 auf +/-0.175. Der Mittelwert bleibt dabei stehen:
##     die Streuung ist symmetrisch, und die Fugen decken nur rund 1,3 % der Flaeche ab
##     (4 cm auf 5,0 m quer + 4 cm auf 7,96 m laengs), ziehen den Mittelwert also um
##     0,2 % nach unten. Endstand siehe Bericht.
##
## AUSSERDEM ZURUECKGENOMMEN: die grossflaechige Aufsetzzonen-Maske. Sie dunkelte ueber
## 150 m weich um 15 % ab und war die zweite Quelle des Gewoelks — eine weiche Maske ueber
## 19 Plattenreihen liest sich als nasser Fleck, nicht als Gummiabrieb. Der Abrieb steht
## in den Vorlagen als SCHARFE Streifen im Bild, und die liefern die Reifenspuren-Kaesten
## in _build_airfield bereits. Rest: 6 % ueber 80 m, gerade noch als Anflaugung erkennbar.
##
## PREIS: 678 Platten + 677 Fugenstuecke = 2710 Dreiecke gegen vorher 2160, also +550.
## Es bleibt EIN Zeichenaufruf und EIN Material, die Flaeche liegt flach (kein Overdraw),
## und das Netz wird EINMAL gebaut und von allen sieben Plaetzen geteilt. Zum Vergleich
## kostet ein einziges geparktes Deko-Flugzeug auf dem Vorfeld rund 35 000 Dreiecke.
## Gemessene Bildzeit siehe Bericht.
##
## Die Toenung steckt in FLAECHENFARBEN (set_color je Platte, flat shading). Das Material
## multipliziert sie ueber vertex_color_use_as_albedo auf `grund` — die Kalibrierung des
## Mittelwerts bleibt damit an EINER Stelle, naemlich der Albedo des Bahnmaterials.
func _bahnbelag(parent: Node3D, grund: Color) -> void:
	# EINMAL bauen, siebenmal benutzen: alle sieben Plaetze haben dieselbe Bahn
	# (RWY_LEN x RWY_W) und denselben festen Wurf. Ohne den Speicher lagen sieben
	# gleiche Netze mit je 2160 Dreiecken im Speicher.
	if _fp_meshes.has("bahnbelag"):
		var mi0 := MeshInstance3D.new()
		mi0.mesh = _fp_meshes["bahnbelag"]
		mi0.position = Vector3(0, 0.08, 0)
		mi0.material_override = _bahn_mat(grund)
		parent.add_child(mi0)
		return
	var nx := 6                                   # 30 m / 6 = 5,0 m Plattenbreite (quer)
	var nz := int(round(RWY_LEN / 8.0))           # 900 m / 8 m = 113 Reihen -> 7,96 m laengs
	var sx := RWY_W / float(nx)
	var sz := RWY_LEN / float(nz)
	var hl := RWY_LEN * 0.5
	# FUGENBREITE 8 cm, nicht die vorgegebenen 3 bis 5 cm — GEMESSEN begruendet: die
	# Abnahmekamera fp_schwelle steht 6 m hoch, ihre Brennweite entspricht 576 px je
	# Bildhoehe. Auf 50 m Entfernung (das ist die Mitte des Pruefkastens) deckt 1 cm damit
	# 0,115 px ab; eine 4-cm-Fuge belegt also weniger als ein halbes Pixel und verschwindet
	# im Kantenglaetter — im ersten Wurf war sie ab 25 m unsichtbar, und das Plattenfeld
	# las sich wieder nur als Tonflecken. In heimat_2 sind die Fugen ueber die ganze
	# Bildtiefe lesbar und messen dort rund 2 % der Plattenbreite, also bei 5 m Platte rund
	# 10 cm. 8 cm sind der Kompromiss: sichtbar, aber schmaler als die Vorlage.
	const FUGE_B := 0.08                          # Fugenbreite in m
	const FUGE_F := 0.85                          # Fuge 15 % dunkler als der Plattengrund
	var h := FUGE_B * 0.5                         # halbe Fuge = Einzug je Plattenkante
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)                       # flat shading, wie das ganze Low-Poly-Land
	for j in nz:
		for i in nx:
			var x0 := -RWY_W * 0.5 + float(i) * sx
			var z0 := -hl + float(j) * sz
			var cx := x0 + sx * 0.5
			var cz := z0 + sz * 0.5
			# Plattenton aus dem HASH DES RASTERINDEX. Ueber die 678 Platten der Bahn liefert
			# _platten_hash nachgerechnet Mittel 0.491 und std 0.280 ohne Nachbarkorrelation.
			# AMPLITUDE AM BILD EINGEMESSEN, nicht geschaetzt: mit +/-0.175 kam im Pruefkasten
			# der Ansicht fp_schwelle (350,405)-(900,455), nur Belagspixel 30..130, eine
			# Streuung von 9,11 heraus — die Referenz heimat_2 liegt im selben Kasten bei
			# 24,01 bei aehnlichem Mittel (78,6 gegen 85,3). Die Bahn las sich dadurch als
			# gleichmaessige dunkle Flaeche, auf der jede weisse Markierung wie ausgestanzt
			# wirkt. Verdoppelte Amplitude schliesst rund die Haelfte dieser Luecke; der Rest
			# steckt in den Fugen, die bei 8 cm auf halber Bildtiefe unter die Pixelgroesse
			# fallen. Wer weiter will, macht dort weiter, nicht an der Amplitude — ueber 0.4
			# beginnt das Feld als Schachbrett zu lesen.
			var f := 1.0 + (_platten_hash(i, j) * 2.0 - 1.0) * 0.34
			# AUFSETZZONE, stark zurueckgenommen (vorher 15 % ueber 150 m, siehe Kopf):
			# 6 % ueber 80 m. Quer dazu blendet sie zur Kante aus — der Gummi liegt, wo die
			# Raeder aufsetzen, nicht am Bahnrand.
			var ein := (hl - 20.0) - absf(cz)     # >0 = Richtung Bahnmitte hinter der Schwelle
			if ein >= 0.0:
				var zone := (1.0 - smoothstep(0.0, 80.0, ein)) \
					* (1.0 - smoothstep(9.0, 13.0, absf(cx)))
				f *= lerpf(1.0, 0.94, zone)
			# PLATTE, an jeder INNEREN Kante um die halbe Fuge eingezogen. An den vier
			# Aussenkanten der Bahn bleibt sie stehen: dort ist keine Nachbarplatte, und ein
			# Einzug wuerde einen 2 cm breiten Spalt zum Randstreifen offen lassen.
			var px0 := x0 + (h if i > 0 else 0.0)
			var px1 := x0 + sx - (h if i < nx - 1 else 0.0)
			var pz0 := z0 + (h if j > 0 else 0.0)
			var pz1 := z0 + sz - (h if j < nz - 1 else 0.0)
			st.set_color(Color(f, f, f))
			# WICKLUNG WIE IM TERRAIN (_make_chunk_data): v00 -> v10 -> v11. Godot-Front
			# ist im Uhrzeigersinn von aussen; die umgekehrte Reihenfolge wird bei Sicht
			# von oben weggecullt und die Bahn waere unsichtbar.
			_quad(st, Vector3(px0, 0, pz0), Vector3(px1, 0, pz0),
				Vector3(px1, 0, pz1), Vector3(px0, 0, pz1), Vector3.UP)
			# QUERFUGE zur naechsten Reihe. Sie reicht nur von Plattenkante zu Plattenkante,
			# damit sie die durchgehende Laengsfuge nicht ueberlappt (koplanare Ueberlappung
			# = Z-Fighting). 6 Stuecke je Reihenstoss.
			if j < nz - 1:
				st.set_color(Color(FUGE_F, FUGE_F, FUGE_F))
				_quad(st, Vector3(px0, 0, pz1), Vector3(px1, 0, pz1),
					Vector3(px1, 0, pz1 + FUGE_B), Vector3(px0, 0, pz1 + FUGE_B), Vector3.UP)
	# LAENGSFUGEN durchgehend ueber die volle Bahnlaenge: EIN Quad je Stoss statt 113.
	# Sie liegen genau in den Spalten, die die Platten oben freigelassen haben.
	st.set_color(Color(FUGE_F, FUGE_F, FUGE_F))
	for i in range(1, nx):
		var fx := -RWY_W * 0.5 + float(i) * sx
		_quad(st, Vector3(fx - h, 0, -hl), Vector3(fx + h, 0, -hl),
			Vector3(fx + h, 0, hl), Vector3(fx - h, 0, hl), Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	_fp_meshes["bahnbelag"] = mi.mesh
	mi.position = Vector3(0, 0.08, 0)
	mi.material_override = _bahn_mat(grund)
	parent.add_child(mi)


## Grundton EINER Bahnplatte aus ihrem Rasterindex, 0..1 gleichverteilt.
## WARUM HASH STATT ZUFALLSZAHLENGEBER: der alte rng lief in Bauschleifen-Reihenfolge
## durch. Damit haengt der Ton jeder Platte daran, wie viele Platten vorher gezogen
## wurden — wer das Raster aendert (hier: 5 m auf 8 m laengs), wuerfelt die ganze Bahn
## neu, und zwei Laeufe sind nur so lange vergleichbar, wie die Schleife unveraendert
## bleibt. Der Hash haengt allein an (i, j): dieselbe Platte behaelt ihren Ton.
## Ganzzahlmischung nach Art von Wang/Jenkins; die Maske auf 31 Bit haelt das Ergebnis
## in GDScripts vorzeichenbehafteten 64-Bit-Ganzzahlen positiv.
func _platten_hash(i: int, j: int) -> float:
	var h := (i * 73856093) ^ (j * 19349663)
	h = (h ^ (h >> 13)) & 0x7FFFFFFF
	h = (h * 1274126177) & 0x7FFFFFFF
	h = (h ^ (h >> 16)) & 0x7FFFFFFF
	return float(h & 0xFFFFFF) / 16777216.0


## Material des Plattenfelds: `grund` haelt den eingemessenen Mittelwert, die
## Flaechenfarben aus _bahnbelag multiplizieren die Plattenstreuung darauf.
func _bahn_mat(grund: Color) -> StandardMaterial3D:
	var mat := _flat_mat(grund, 0.95)
	mat.vertex_color_use_as_albedo = true
	return mat


func _rwy_number(heading: float, far_end: bool) -> String:
	var deg := fposmod(rad_to_deg(heading), 360.0)
	var n := int(round(deg / 10.0))
	if far_end:
		n = (n + 18) % 36
	if n <= 0:
		n = 36
	return "%02d" % n


# Deko-Box ohne Kollision (Markierungen, Flächen).
func _deco_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	parent.add_child(m)


# Befeuerungs-Licht: kleine leuchtende Kugel (ohne Kollision, ohne echtes Licht -> billig).
func _deco_light(parent: Node3D, pos: Vector3, col: Color) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.35
	s.height = 0.7
	s.radial_segments = 8
	s.rings = 4
	m.mesh = s
	m.position = pos
	m.material_override = _emit_mat(col, 2.2)
	parent.add_child(m)


# Sichtweite aller Meshes unter `wurzel` deckeln (rekursiv). Terrain-Chunks haengen nicht
# hier drunter, die regelt TerrainWorld selbst.
func _limit_sichtweite(wurzel: Node, dist: float, fade: float) -> void:
	for c in wurzel.get_children():
		# TERRAIN AUSLASSEN: das regelt seine Sichtweite selbst ueber das Streaming und
		# baut Chunks jenseits von VIEW_DIST wieder ab. Ohne diese Ausnahme erwischte die
		# Rekursion genau die Chunks, die beim Start schon fertig waren — gezaehlt 32 von
		# 376 — und deckelte NUR die auf SICHT_DIST. Um den Spawn herum verschwand dadurch
		# ein Block, waehrend die Nachbarchunks stehen blieben. Dieselbe Deckelung traf
		# die See- und Fluss-Wasserflaechen.
		if c is TerrainWorld:
			continue
		var gi := c as GeometryInstance3D
		if gi != null and gi.visibility_range_end <= 0.0:
			gi.visibility_range_end = dist
			gi.visibility_range_end_margin = fade
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_limit_sichtweite(c, dist, fade)


# Wahrzeichen/POIs (Stufe 2) — Geometrie in Landmarks.gd (Spiel + Render-Tool teilen sie).
func _build_town(center: Vector3) -> void:
	Landmarks.build_town(fly_world, center)


func _build_lighthouse(center: Vector3) -> void:
	Landmarks.build_lighthouse(fly_world, center)


# Windsack: Mast mit Ausleger + rot/weiss geringelter Sack (Vorlage: dreifarbig geringelt,
# nicht einfarbig orange — der Ringel ist das, was ihn auf 100 m als Windsack lesbar macht).
func _add_windsock(parent: Node3D, pos: Vector3) -> void:
	var mast := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.12
	mm.bottom_radius = 0.18
	mm.height = 9.0
	mm.radial_segments = 8
	mm.rings = 1
	mast.mesh = mm
	mast.position = pos + Vector3(0, 4.5, 0)
	mast.material_override = _flat_mat(Color(0.85, 0.85, 0.87), 0.5)
	parent.add_child(mast)
	_deco_box(parent, pos + Vector3(0, 0.3, 0), Vector3(2.2, 0.6, 2.2), _flat_mat(Color(0.6, 0.6, 0.58), 0.9))
	var rot := _flat_mat(Color(0.88, 0.18, 0.14), 0.7)
	var weiss := _flat_mat(Color(0.95, 0.95, 0.93), 0.7)
	# Drei Kegelstuempfe hintereinander: von 0,25 m (Spitze) auf 0,62 m (Maul) aufgeweitet.
	var radien := [0.62, 0.50, 0.38, 0.25]
	for i in 3:
		var seg := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.bottom_radius = float(radien[i])
		sm.top_radius = float(radien[i + 1])
		sm.height = 1.2
		sm.radial_segments = 8
		sm.rings = 1
		seg.mesh = sm
		seg.position = pos + Vector3(0.7 + float(i) * 1.2, 8.4, 0)
		seg.rotation_degrees = Vector3(0, 0, -90)
		seg.material_override = rot if (i % 2 == 0) else weiss
		parent.add_child(seg)


# Kleine Halle als TONNENDACH-Hangar (Quonset). Die Vorlagen zeigen an dieser Stelle
# ueberall Rundbogenhallen mit dunklem Tor, nie die flache Kiste mit Satteldach, die hier
# vorher stand. Farbe kommt NICHT mehr aus af["color"] (das ist die Kartenfarbe des Platzes
# und machte weisse/rosa/hellblaue Hangars) — die Vorlagen haben durchweg Olivgruen.
## VORFELD UNTER TAGE — der Ersatz fuer den Aussenplatz in der Kaverne.
##
## Das normale Vorfeld ist auf freies Feld gerechnet: 138 m Beton NEBEN der Bahn, Tower,
## Windsack, Tanklager, dazu ein 850 m langer Platzzaun. In einer Roehre von 156 m lichter
## Weite hat davon nichts Platz, und ein Windsack unter 500 m Fels waere ohnehin Unsinn.
##
## Was hier steht, ist auf die Roehre gerechnet: zwei Betonstreifen zwischen Bahnschulter
## und Wandfuss, darauf je fuenf geschlossene Tonnenhallen mit dem Ruecken zur Wand, und
## ein Betriebsgebaeude am hinteren Ende. Die Hallen sind um 90 Grad gedreht — dann messen
## sie 20 m quer und nur 16 m laengs und stehen als Reihe an der Wand, statt sich
## gegenseitig die Tore zuzustellen.
##
## LAGE IN PLATZKOORDINATEN: die Bahn laeuft laengs Z, talaufwaerts ist -Z, und der Platz
## sitzt 510 m hinter dem Portal. Die Tiefe ab Portal ist damit 510 - z; die Reihe von
## z = 180 bis z = -140 liegt also 330 bis 650 m im Berg, wo die Halle ihre volle Weite
## erreicht hat (sie weitet sich ueber die ersten 30 Prozent).
func _kavernen_vorfeld(wurzel: Node3D, farbe: Color) -> void:
	var node := Node3D.new()
	node.name = "KavernenVorfeld"
	wurzel.add_child(node)
	var beton := _flat_mat(Color(0.60, 0.59, 0.57), 0.9)
	var paint_y := _flat_mat(Color(0.86, 0.72, 0.12), 0.9)
	# x 24 bis 74: innen an der Bahnschulter (die Bahn ist 30 m breit, Schulter bis 22),
	# aussen 4 m vor dem Wandfuss bei 78.
	for sx in [1.0, -1.0]:
		_deco_box(node, Vector3(49.0 * sx, 0.05, 20.0), Vector3(50.0, 0.10, 620.0), beton)
		# Gelbe Fuehrungslinie auf der Streifenachse — dieselbe Sprache wie draussen.
		_deco_box(node, Vector3(49.0 * sx, 0.11, 20.0), Vector3(0.5, 0.02, 600.0), paint_y)
		# TORSEITE. _tonnenhalle setzt ihre Oeffnung auf lokal +Z; yaw dreht die ganze
		# Halle. Hier stand fest 90 Grad fuer BEIDE Reihen — damit zeigten die Tore der
		# einen Reihe zur Bahn und die der anderen in den Fels, und die Haelfte der
		# Hangars stand als fensterlose gruene Roehre da. -90 * sx dreht jede Reihe zur
		# Bahn hin.
		# VERSETZT UND VERSCHIEDEN LANG. Fuenf gleiche Hallen im gleichen Abstand liest
		# das Auge als Kopie und zaehlt sie ab. Der Versatz von 40 m zwischen den Reihen
		# und drei Tiefen im Wechsel brechen das Raster, ohne dass eine Halle aus der
		# Flucht faellt.
		var versatz := 40.0 if sx > 0.0 else 0.0
		for k in 5:
			var z := 180.0 - float(k) * 80.0 - versatz
			var tiefe: float = [20.0, 26.0, 20.0, 30.0, 24.0][k]
			# BETONGRAU, NICHT OLIVGRUEN. Olive Wellblechhallen sind Feldunterstaende
			# gegen Wetter und Sicht — unter 500 m Fels gibt es weder das eine noch das
			# andere, und im Bild lasen sich neun blassgruene Roehren als Plastik. Ein
			# Ton, der zum Beton der Sohle passt, sagt stattdessen: hier hineingebaut.
			_tonnenhalle(node, Vector3(61.0 * sx, 0.0, z), 8.0, tiefe, -90.0 * sx,
				Color(0.37, 0.375, 0.36).lerp(farbe, 0.08), true)
			# Abstellmarkierung vor jedem Tor, zur Bahn hin.
			_deco_box(node, Vector3(38.0 * sx, 0.11, z), Vector3(22.0, 0.02, 0.4), paint_y)
	_add_ops_haus(node, Vector3(58.0, 0.0, -240.0))


func _add_hangar(parent: Node3D, pos: Vector3, col: Color) -> void:
	var oliv := Color(0.40, 0.44, 0.33).lerp(col, 0.10)   # Platzfarbe nur als leichter Stich
	_tonnenhalle(parent, pos, 8.0, 20.0, 0.0, oliv, true)


# Betriebsgebaeude: flacher Sandbau mit dunklem Flachdach und Fensterband — in heimat_1
# und heimat_4 steht genau so eines rechts neben dem Tower.
func _add_ops_haus(parent: Node3D, pos: Vector3) -> void:
	var sand := _flat_mat(Color(0.80, 0.75, 0.62), 0.85)
	var glas := _flat_mat(Color(0.24, 0.34, 0.40), 0.25)
	_deco_box(parent, pos + Vector3(0, 3.0, 0), Vector3(20.0, 6.0, 12.0), sand)
	_deco_box(parent, pos + Vector3(0, 6.3, 0), Vector3(21.0, 0.6, 13.0), _flat_mat(Color(0.34, 0.35, 0.36), 0.85))
	for wx in [-6.5, 0.0, 6.5]:
		_deco_box(parent, pos + Vector3(wx, 3.6, 6.1), Vector3(4.6, 1.6, 0.2), glas)
	_deco_box(parent, pos + Vector3(-9.0, 1.5, 6.1), Vector3(1.8, 3.0, 0.2), _flat_mat(Color(0.28, 0.29, 0.3), 0.8))
	_collider_box(parent, pos + Vector3(0, 3.3, 0), Vector3(20.0, 6.6, 12.0))


# Kontrollturm: sandfarbener Schaft, umlaufende Galerie mit Gelaender, VERGLASTE Kanzel
# mit Rahmen und dunkles Dach. Vorher waren das zwei nackte Boxen; in allen vier Vorlagen
# ist der Tower das Gebaeude, an dem man den Platz erkennt.
func _add_tower(parent: Node3D, pos: Vector3) -> void:
	var sand := _flat_mat(Color(0.80, 0.75, 0.62), 0.7)
	var beton := _flat_mat(Color(0.62, 0.62, 0.60), 0.85)
	# Kanzelglas HELLER und mit etwas Eigenleuchten. Mit 0.22/0.36/0.44 und metallic 0.5 stand
	# die Kanzel im gerenderten Bild schwarz da — sie schaut nach Norden, bekommt von der
	# 50-Grad-Sonne also nur Streulicht ab. In heimat_3 ist die Verglasung das HELLSTE am
	# Tower (tuerkis, spiegelt den Himmel). 0.2 Eigenleuchten ersetzt die Spiegelung, ohne
	# dass der Bau bei Nacht zu gluehen anfaengt.
	var glas := _emit_mat(Color(0.34, 0.52, 0.56), 0.2)
	glas.roughness = 0.15
	glas.metallic = 0.5
	_deco_box(parent, pos + Vector3(0, 10.0, 0), Vector3(6.0, 20.0, 6.0), sand)          # Schaft
	_deco_box(parent, pos + Vector3(0, 0.4, 0), Vector3(7.2, 0.8, 7.2), beton)           # Sockel
	for wy in [7.0, 12.0, 17.0]:                                                          # schmale Fensterschlitze
		for s in [1.0, -1.0]:
			_deco_box(parent, pos + Vector3(0, wy, s * 3.05), Vector3(1.0, 1.8, 0.12), glas)
			_deco_box(parent, pos + Vector3(s * 3.05, wy, 0), Vector3(0.12, 1.8, 1.0), glas)
	_deco_box(parent, pos + Vector3(0, 20.3, 0), Vector3(9.6, 0.6, 9.6), beton)          # Galerie
	for s2 in [1.0, -1.0]:                                                                # Gelaender
		_deco_box(parent, pos + Vector3(0, 21.2, s2 * 4.7), Vector3(9.6, 0.12, 0.12), beton)
		_deco_box(parent, pos + Vector3(s2 * 4.7, 21.2, 0), Vector3(0.12, 0.12, 9.6), beton)
	_deco_box(parent, pos + Vector3(0, 22.6, 0), Vector3(8.0, 4.0, 8.0), glas)           # Kanzel
	for cx in [-4.05, 4.05]:                                                              # Rahmenpfosten
		for cz in [-4.05, 4.05]:
			_deco_box(parent, pos + Vector3(cx, 22.6, cz), Vector3(0.35, 4.0, 0.35), sand)
	_deco_box(parent, pos + Vector3(0, 24.9, 0), Vector3(9.0, 0.7, 9.0), _flat_mat(Color(0.36, 0.37, 0.38), 0.85))
	_deco_box(parent, pos + Vector3(2.5, 25.6, 2.5), Vector3(1.6, 0.8, 1.6), beton)      # Aufbau aufs Dach
	# solide Kollision: Schaft + Kanzel (man kann reinkrachen)
	_collider_box(parent, pos + Vector3(0, 12.7, 0), Vector3(9.6, 25.4, 9.6))


# --- TONNENHALLE ------------------------------------------------------------------
# Halbzylinder-Schale mit Stirnwand. `offen == false` -> geschlossene Halle mit Tor
# (kleine Hangars), `offen == true` -> vorne offen, man rollt hinein (Grosshangar).
# Achse laeuft laengs Z, die Oeffnung zeigt nach +Z; `yaw_deg` dreht die ganze Halle.
func _tonnenhalle(parent: Node3D, pos: Vector3, radius: float, tiefe: float,
		yaw_deg: float, col: Color, geschlossen: bool) -> void:
	var h := Node3D.new()
	h.position = pos
	h.rotation_degrees = Vector3(0, yaw_deg, 0)
	parent.add_child(h)
	var seg := 12 if radius < 10.0 else 14
	# LAENGSPANEELE nur an der grossen offenen Halle: dort ist die Aussenhaut das groesste
	# zusammenhaengende Stueck Flaeche im Bild und stand vorher als glatter Schlauch da.
	# Die geschlossenen kleinen Hallen bleiben ungeteilt (1) — sie sind 20 m tief und
	# haetten von der Unterteilung nur die Dreiecke.
	var paneele := 1 if geschlossen else 6
	var schale := MeshInstance3D.new()
	schale.mesh = _bogen_mesh(radius, tiefe, seg, paneele)
	# Flaechen-Overrides statt material_override: Aussenhaut und Innenhaut brauchen
	# GEGENSAETZLICHE Werte, und nur zwei Flaechen koennen das trennen.
	var aussen_mat := _flat_mat(col, 0.75)
	aussen_mat.vertex_color_use_as_albedo = true    # Paneel-Toenung, siehe _bogen_mesh
	schale.set_surface_override_material(0, aussen_mat)
	# INNENHAUT: frueher col.lightened(0.42) plus Eigenleuchten — das Innere war damit
	# HELLER als die Aussenhaut und heller als der Beton davor, und genau daran las sich
	# der Bau als Plastikschlauch statt als Halle. Jetzt grob halb so hell wie die
	# Aussenhaut und klar dunkler als das Vorfeld (Beton 0.70). Die Tiefe kommt nicht
	# mehr aus einer flaechigen Aufhellung, sondern aus Bogenbindern und zwei
	# Deckenleuchten (siehe _grosshalle_ausbau). Das kleine Restleuchten verhindert nur,
	# dass die Nordseite im Gegenlicht als schwarzes Loch ausbricht.
	# Die geschlossenen Hallen teilen sich dieses Material — bei ihnen ist die Innenhaut
	# hinter Stirn- und Rueckwand ohnehin nie zu sehen.
	var innen_mat := _flat_mat(col.darkened(0.5), 0.9)
	innen_mat.emission_enabled = true
	# ZWEITER MESSPUNKT: mit emission = col.darkened(0.35) bei 0.10 stand das Innere im
	# Bild bei sRGB(14,19,18) — wieder ein schwarzes Loch, in dem weder Binder noch
	# Flugzeug zu erkennen waren. Die ALBEDO bleibt bei der geforderten halben
	# Aussenhelligkeit; angehoben wird nur die Fuellung. col bei 0.5 legt das Gewoelbe
	# rechnerisch auf rund sRGB 70 — klar unter dem Vorfeldbeton (gemessen 141) und unter
	# der besonnten Aussenhaut (133), aber hell genug fuer die Tiefenstaffelung.
	innen_mat.emission = col
	innen_mat.emission_energy_multiplier = 0.5
	schale.set_surface_override_material(1, innen_mat)
	h.add_child(schale)
	# Rueckwand (immer) und Stirnwand (nur bei geschlossenen Hallen).
	# Bei der OFFENEN Halle schaut man auf die Rueckwand — sie ist dort die tiefste, am
	# staerksten verschattete Flaeche der Vorlage und muss unter der Innenhaut liegen,
	# sonst leuchtet sie am Ende des Tunnels auf. Bei den geschlossenen Hallen ist
	# dieselbe Scheibe die AUSSENseite (dort sitzt das Tor davor) und bleibt hell.
	var wand_mat := _flat_mat(col.darkened(0.18 if geschlossen else 0.66), 0.8)
	var hinten := MeshInstance3D.new()
	hinten.mesh = _halbscheibe_mesh(radius - 0.3, seg)
	hinten.position = Vector3(0, 0, -tiefe * 0.5 + 0.2)
	hinten.material_override = wand_mat
	h.add_child(hinten)
	if geschlossen:
		var vorne := MeshInstance3D.new()
		vorne.mesh = _halbscheibe_mesh(radius - 0.3, seg)
		vorne.position = Vector3(0, 0, tiefe * 0.5 - 0.2)
		vorne.material_override = wand_mat
		h.add_child(vorne)
		# Tor: dunkles Rechteck mit hellem Sturz — so lesen die Vorlagen-Hangars.
		var tor_b := radius * 0.85
		_deco_box(h, Vector3(0, radius * 0.35, tiefe * 0.5 - 0.05), Vector3(tor_b, radius * 0.7, 0.25),
			_flat_mat(Color(0.24, 0.26, 0.22), 0.85))
		_deco_box(h, Vector3(0, radius * 0.72, tiefe * 0.5 - 0.02), Vector3(tor_b + 0.6, 0.35, 0.25),
			_flat_mat(col.lightened(0.15), 0.8))
		# EIN Kollisionsblock ueber die ganze Halle — man kann nicht hinein.
		_collider_box(parent, pos + Vector3(0, radius * 0.5, 0),
			(Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Vector3(2.0 * radius, radius, tiefe)).abs())
	else:
		_grosshalle_ausbau(h, radius, tiefe, col)
		# Offene Halle: Kollision NUR an Flanken, Rueckwand und Dach, damit die Oeffnung
		# befliegbar bleibt (dieselbe Aufteilung wie in der alten Kastenfassung).
		# Flanken und Dach reichen 1,9 m WEITER nach vorn als die Schale: dort steht seit
		# dieser Runde der Portalrahmen (bis hz + 1,65 m). Ohne die Verlaengerung waere er
		# das einzige Bauteil des Platzes, durch das man hindurchfliegt.
		var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
		var t_koll := tiefe + 1.9
		var z_koll := 0.95
		for sx in [-1.0, 1.0]:
			_collider_box(parent, pos + b * Vector3(sx * (radius - 1.0), radius * 0.3, z_koll),
				(b * Vector3(2.0, radius * 0.6, t_koll)).abs())
		_collider_box(parent, pos + b * Vector3(0, radius - 0.8, z_koll),
			(b * Vector3(2.0 * radius, 1.6, t_koll)).abs())
		_collider_box(parent, pos + b * Vector3(0, radius * 0.5, -tiefe * 0.5 + 0.3),
			(b * Vector3(2.0 * radius, radius, 0.8)).abs())


## AUSBAU DER OFFENEN GROSSHALLE — sie ist in fp_vorfeld das groesste Objekt im Bild und
## war zugleich das leerste: eine glatte Halbroehre, deren Oeffnung einfach abgeschnitten
## ist. heimat_3 zeigt an derselben Stelle einen dicken, vorstehenden Portalrahmen in zwei
## Stufen, im Inneren quer laufende Bogenbinder ueber einer dunklen Schale, Deckenleuchten,
## einen Dachluefter und gelbe Poller an den Torecken.
##
## PREIS: 168 Dreiecke Portal (zwei Lagen), 360 Binder, 24 Rahmenfuesse, 72 Leuchten samt
## Abhaengern, 24 Luefter, 48 Poller — zusammen rund 700 Dreiecke und 14 Zeichenaufrufe
## fuer das Wahrzeichen des Platzes. Zum Vergleich: das geparkte Flugzeug DARIN kostet
## rund 35 000 Dreiecke und 77 Zeichenaufrufe.
## Die Halle ist gleichzeitig auf rund die Haelfte ihrer Grundflaeche geschrumpft (siehe
## _build_main_base), unter dem Strich wird der Bau also billiger, nicht teurer.
func _grosshalle_ausbau(h: Node3D, radius: float, tiefe: float, _col: Color) -> void:
	var hz := tiefe * 0.5
	var seg := 14
	# (1) PORTALRAHMEN in zwei Stufen. Aussen 1,4 m breit und 1,1 m vorstehend, davor eine
	# schmalere zweite Lage — die Stufe dazwischen ist der Grund, warum die Oeffnung nicht
	# mehr wie abgeschnitten wirkt. Beide Lagen DUNKLER als die Huelle, sonst blendet der
	# Rahmen mit der sonnenbeschienenen Dachflaeche zusammen.
	# Die Grautoene sind eingemessen: mit 0.29 / 0.22 stand der Rahmen im Bild als
	# schwarzer Ring da, in dem die beiden Lagen nicht mehr auseinanderzuhalten waren.
	# 0.40 / 0.31 bleibt im Gruenkanal unter der Huelle (0.45) — also weiter "dunkler als
	# die Huelle" wie gefordert — liest sich aber als Grau gegen das Olivgruen.
	for lage in [[radius - 0.3, radius + 1.15, 1.1, 0.55, Color(0.40, 0.41, 0.39)],
			[radius - 0.1, radius + 0.75, 0.5, 1.4, Color(0.31, 0.32, 0.31)]]:
		var pm := MeshInstance3D.new()
		pm.mesh = _portalbogen_mesh(float(lage[0]), float(lage[1]), float(lage[2]), seg)
		pm.position = Vector3(0, 0, hz + float(lage[3]))
		pm.material_override = _flat_mat(lage[4], 0.8)
		h.add_child(pm)
	# Rahmenfuesse: der Bogen endet sonst in der Luft ueber dem Beton.
	for sx in [-1.0, 1.0]:
		_deco_box(h, Vector3(sx * (radius + 0.42), 1.1, hz + 0.55),
			Vector3(1.45, 2.2, 1.1), _flat_mat(Color(0.40, 0.41, 0.39), 0.8))
	# (2) BOGENBINDER: sechs quer laufende Rippen dicht unter der Innenhaut, dazu die schon
	# vorhandene geschlossene Rueckwand. Sie sind das Einzige, woran das Auge im Inneren
	# eine Tiefe ablesen kann — ohne sie ist die Schale eine gleichmaessige Flaeche ohne
	# jeden Anhaltspunkt, wie weit sie nach hinten reicht.
	var binder := MeshInstance3D.new()
	binder.mesh = _binder_mesh(radius - 0.32, 0.45, 0.55, 6, tiefe - 2.4, 10)
	binder.material_override = _flat_mat(Color(0.20, 0.21, 0.22), 0.7)
	h.add_child(binder)
	# (3) DREI DECKENLEUCHTEN als Hallenpendel. Sie beleuchten nichts (Eigenleuchten wirft
	# kein Licht), sie setzen dem dunklen Gewoelbe helle Marken in die Tiefenstaffelung —
	# genau so stehen sie in heimat_3.
	# DREIMAL NACHGEBESSERT, und kein einziges Mal war die Helligkeit schuld, sondern immer
	# die Sichtlinie. Fuer die Abnahmestellung fp_vorfeld: Kamera (-55, 60, 195), Tor
	# (122, 0, 69) — 217 m Grundabstand und, entscheidend, 54,6 Grad SCHRAEG zur
	# Hallenachse. Der Sehstrahl zu einer Leuchte in der Tiefe d hinter dem Tor tritt bei
	# x = -177*d/(126+d) und y = 60 - (60-y_L)*126/(126+d) durch die Oeffnung und muss dort
	# unter den Bogen sqrt(13,5^2 - x^2) passen. Das gibt d <= rund 6,5 m: die Halle ist
	# aus dieser Stellung nur ihr vorderes Viertel weit einsehbar, alles dahinter verdeckt
	# der eigene Torpfosten. Deshalb haengt die vorderste Leuchte 4,5 m hinter dem Tor —
	# sie ist die, die man im Abnahmebild sieht. Die beiden hinteren stehen dort, wo sie
	# hingehoeren, und tragen beim Rollen und im Tiefflug.
	var lampe := _emit_mat(Color(1.0, 0.96, 0.84), 3.4)
	for lz in [tiefe * 0.34, tiefe * 0.0, -tiefe * 0.30]:
		_deco_box(h, Vector3(0, radius * 0.52, lz), Vector3(2.2, 0.5, tiefe * 0.14), lampe)
		# Abhaenger zur Schale, sonst schwebt die Leuchte frei unter dem Gewoelbe
		_deco_box(h, Vector3(0, radius * 0.76, lz), Vector3(0.12, radius * 0.48, 0.12),
			_flat_mat(Color(0.22, 0.23, 0.22), 0.7))
	# (4) DACHLUEFTERKASTEN auf dem First, leicht nach vorn versetzt wie in der Vorlage.
	var luefter := _flat_mat(Color(0.52, 0.53, 0.50), 0.8)
	_deco_box(h, Vector3(0, radius + 0.30, hz * 0.45), Vector3(2.4, 1.0, 3.4), luefter)
	_deco_box(h, Vector3(0, radius + 0.88, hz * 0.45), Vector3(2.9, 0.25, 3.9),
		_flat_mat(Color(0.34, 0.35, 0.34), 0.8))
	# (5) GELBE ANFAHRPOLLER an den beiden Torecken — in heimat_3 stehen sie genau dort,
	# und sie geben dem Tor nebenbei einen Massstab. Ein MultiMesh, ein Zeichenaufruf.
	var poller := CylinderMesh.new()
	poller.top_radius = 0.28
	poller.bottom_radius = 0.32
	poller.height = 1.2
	poller.radial_segments = 6
	poller.rings = 1
	var pfx: Array[Transform3D] = []
	for sx2 in [-1.0, 1.0]:
		pfx.append(Transform3D(Basis(), Vector3(sx2 * (radius + 1.9), 0.6, hz + 1.6)))
	_multi(h, poller, pfx, _flat_mat(Color(0.90, 0.72, 0.12), 0.7))


## Portalbogen: halbringfoermiger Rahmen mit rechteckigem Querschnitt, Achse laengs Z.
## Drei Flaechen je Segment — Stirn (nach +Z), Aussenmantel, Laibung. Die Rueckseite
## liegt an der Schale an und wird weggelassen.
func _portalbogen_mesh(r_i: float, r_a: float, dicke: float, seg: int) -> ArrayMesh:
	var key := "portal_%.2f_%.2f_%.2f_%d" % [r_i, r_a, dicke, seg]
	if _fp_meshes.has(key):
		return _fp_meshes[key]
	var hd := dicke * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := PI * float(i) / float(seg)
		var a1 := PI * float(i + 1) / float(seg)
		var d0 := Vector3(-cos(a0), sin(a0), 0.0)
		var d1 := Vector3(-cos(a1), sin(a1), 0.0)
		_quad(st, d0 * r_i + Vector3(0, 0, hd), d0 * r_a + Vector3(0, 0, hd),
			d1 * r_a + Vector3(0, 0, hd), d1 * r_i + Vector3(0, 0, hd), Vector3(0, 0, 1))
		_quad(st, d0 * r_a + Vector3(0, 0, -hd), d1 * r_a + Vector3(0, 0, -hd),
			d1 * r_a + Vector3(0, 0, hd), d0 * r_a + Vector3(0, 0, hd), (d0 + d1) * 0.5)
		_quad(st, d1 * r_i + Vector3(0, 0, -hd), d0 * r_i + Vector3(0, 0, -hd),
			d0 * r_i + Vector3(0, 0, hd), d1 * r_i + Vector3(0, 0, hd), -(d0 + d1) * 0.5)
	var m: ArrayMesh = st.commit()
	_fp_meshes[key] = m
	return m


## `n` Bogenbinder, gleichmaessig ueber `spanne` verteilt, alle in EIN Mesh gebacken —
## als Einzelknoten waeren sechs Rippen sechs Zeichenaufrufe, so ist es einer.
## Je Segment nur drei Flaechen (Innenseite und zwei Flanken); die vierte liegt an der
## Innenhaut an und ist nie zu sehen.
func _binder_mesh(r: float, breite: float, dicke: float, n: int, spanne: float,
		seg: int) -> ArrayMesh:
	var key := "binder_%.2f_%.2f_%.2f_%d_%.2f_%d" % [r, breite, dicke, n, spanne, seg]
	if _fp_meshes.has(key):
		return _fp_meshes[key]
	var hb := breite * 0.5
	var ri := r - dicke
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n:
		var z := -spanne * 0.5 + spanne * (float(k) + 0.5) / float(n)
		for i in seg:
			var a0 := PI * float(i) / float(seg)
			var a1 := PI * float(i + 1) / float(seg)
			var d0 := Vector3(-cos(a0), sin(a0), 0.0)
			var d1 := Vector3(-cos(a1), sin(a1), 0.0)
			_quad(st, d1 * ri + Vector3(0, 0, z - hb), d0 * ri + Vector3(0, 0, z - hb),
				d0 * ri + Vector3(0, 0, z + hb), d1 * ri + Vector3(0, 0, z + hb),
				-(d0 + d1) * 0.5)
			_quad(st, d0 * ri + Vector3(0, 0, z + hb), d0 * r + Vector3(0, 0, z + hb),
				d1 * r + Vector3(0, 0, z + hb), d1 * ri + Vector3(0, 0, z + hb),
				Vector3(0, 0, 1))
			_quad(st, d1 * ri + Vector3(0, 0, z - hb), d1 * r + Vector3(0, 0, z - hb),
				d0 * r + Vector3(0, 0, z - hb), d0 * ri + Vector3(0, 0, z - hb),
				Vector3(0, 0, -1))
	var m: ArrayMesh = st.commit()
	_fp_meshes[key] = m
	return m


## Halbe Zylinderschale: Flaeche 0 = Aussenhaut samt Laibung an der offenen Stirn,
## Flaeche 1 = Innenhaut (0,3 m nach innen versetzt = Wandstaerke, Normalen nach innen).
## 6 Dreiecke je Segment.
## ZWEI FLAECHEN, nicht cull_disabled und nicht eine einzige: nur so bekommt das Innere
## eine eigene, nach innen zeigende Normale UND ein eigenes Material. Die erste Fassung
## teilte sich ein Material — das Halleninnere stand im Bild als schwarzes Loch, waehrend
## die Vorlage dort eine helle Halle mit einem Flugzeug darin zeigt.
## `paneele` teilt die AUSSENHAUT zusaetzlich in Laengsabschnitte. Die Absetzung an den
## Fugen steckt in FLAECHENFARBEN (jedes zweite Paneel 6 % dunkler), nicht in einem
## Radiusversatz: ein echter Absatz haette an jeder Fuge einen offenen Schlitz
## hinterlassen, durch den man in die Wandstaerke sieht. Der Tonwechsel liefert dieselbe
## sichtbare Kante fuer 140 Dreiecke und ohne Loch.
func _bogen_mesh(radius: float, tiefe: float, seg: int, paneele: int = 1) -> ArrayMesh:
	var key := "bogen_%.2f_%.2f_%d_%d" % [radius, tiefe, seg, paneele]
	if _fp_meshes.has(key):
		return _fp_meshes[key]
	var hz := tiefe * 0.5
	var ri := radius - 0.3
	var aussen := SurfaceTool.new()
	aussen.begin(Mesh.PRIMITIVE_TRIANGLES)
	var innen := SurfaceTool.new()
	innen.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := PI * float(i) / float(seg)
		var a1 := PI * float(i + 1) / float(seg)
		var d0 := Vector3(-cos(a0), sin(a0), 0.0)
		var d1 := Vector3(-cos(a1), sin(a1), 0.0)
		for p in paneele:
			var z0 := -hz + tiefe * float(p) / float(paneele)
			var z1 := -hz + tiefe * float(p + 1) / float(paneele)
			var t := 1.0 if p % 2 == 0 else 0.94
			aussen.set_color(Color(t, t, t))
			_quad(aussen, d0 * radius + Vector3(0, 0, z0), d1 * radius + Vector3(0, 0, z0),
				d1 * radius + Vector3(0, 0, z1), d0 * radius + Vector3(0, 0, z1), (d0 + d1) * 0.5)
		aussen.set_color(Color.WHITE)
		_quad(aussen, d0 * ri + Vector3(0, 0, hz), d0 * radius + Vector3(0, 0, hz),
			d1 * radius + Vector3(0, 0, hz), d1 * ri + Vector3(0, 0, hz), Vector3(0, 0, 1))
		_quad(innen, d1 * ri + Vector3(0, 0, -hz), d0 * ri + Vector3(0, 0, -hz),
			d0 * ri + Vector3(0, 0, hz), d1 * ri + Vector3(0, 0, hz), -(d0 + d1) * 0.5)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, aussen.commit_to_arrays())
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, innen.commit_to_arrays())
	_fp_meshes[key] = m
	return m


## Halbkreisscheibe (Stirn-/Rueckwand einer Tonnenhalle), beidseitig sichtbar.
func _halbscheibe_mesh(radius: float, seg: int) -> ArrayMesh:
	var key := "scheibe_%.2f_%d" % [radius, seg]
	if _fp_meshes.has(key):
		return _fp_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in seg:
		var a0 := PI * float(i) / float(seg)
		var a1 := PI * float(i + 1) / float(seg)
		var p0 := Vector3(-cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1 := Vector3(-cos(a1) * radius, sin(a1) * radius, 0.0)
		_tri(st, Vector3.ZERO, p0, p1, Vector3(0, 0, 1))
		_tri(st, Vector3.ZERO, p1, p0, Vector3(0, 0, -1))
	var m: ArrayMesh = st.commit()
	_fp_meshes[key] = m
	return m


## Fachwerkmast (Radar): vier nach innen geneigte Beine und drei waagerechte Ringe,
## alles in EIN Mesh gebacken. Als Einzelknoten waeren das 20 Zeichenaufrufe fuer einen
## einzigen Mast — hier ist es einer.
## FLUTLICHTMAST. Runde-3-Befund: der alte Mast war nicht bloss aermer als die Vorlage,
## er war der FALSCHE GEGENSTAND — ein Stab mit einer leuchtenden Platte obendrauf
## (ein Quader 3.0 x 1.0 x 1.2 emissiv, ein dunkler 2.6 x 0.9 x 1.0 darunter, Pfosten
## 0.7 x 16 x 0.7 ohne Fuss direkt aus dem Beton). In heimat_3 steht an derselben Stelle
## ein Mastenkopf: angefaster Betonsockel, nach oben verjuengter Mast, ein QUERTRAEGER und
## daran VIER EINZELN STEHENDE Scheinwerferkoepfe, nach unten aufs Vorfeld gekippt.
## Das faellt auf, weil die fuenf Masten nach Tower und Radarturm die hoechsten
## freistehenden Dinge am Vorfeld sind und mit vollem Umriss gegen Gras und Himmel stehen
## — die falsche Form stand also fuenfmal ungefiltert im Bild.
##
## AUFBAU (Masse aus heimat_3 abgegriffen, Nullpunkt = Mastfuss):
##   Sockel   1.8 x 0.65 x 1.8 und darauf 1.4 x 0.35 x 1.4  -> 1,0 m hoch, oben schmaler
##   Mast     0.72 breit von 1,0 bis 9,0 m, 0.52 von 9,0 bis 16,35 m (verjuengt)
##   Traeger  4.5 m breit, 0.25 m stark, bei y = 16.25, quer zur Blickrichtung
##   Koepfe   4 x 1.25 x 0.95 x 0.62 bei x = -1.75 / -0.62 / +0.62 / +1.75, auf 0,4 m
##            hohen Staendern UEBER dem Traeger, je -30 Grad nach vorn unten gekippt
##   Front    je Kopf EINE Platte 1.08 x 0.06 x 0.52 an der geneigten Unterseite, emissiv
##
## PREIS — DER MAST WIRD BILLIGER, nicht teurer. Vorher: 3 Deko-Kaesten je Mast, also 15
## MeshInstance3D und 15 Zeichenaufrufe fuer fuenf Masten bei 36 Dreiecken je Mast.
## Jetzt: vier gebackene Teilnetze (Sockel / Mast / Traeger+Gehaeuse / Frontplatten), jedes
## als EIN MultiMesh ueber alle fuenf Standorte — 4 Zeichenaufrufe statt 15. Dafuer 17
## Kaesten = 204 statt 36 Dreiecke je Mast, also +840 Dreiecke insgesamt. Vier Teilnetze
## deshalb, weil
## Beton, Stahl, Gehaeuse und Leuchtflaeche vier verschiedene Materialien sind und
## Vertexfarben am MultiMesh nachweislich nicht ankommen (siehe _baum_mesh).
func _flutlichtmast(parent: Node3D, stellen: Array[Transform3D]) -> void:
	if stellen.is_empty():
		return
	var st_sockel := SurfaceTool.new()
	st_sockel.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bake_box(st_sockel, Vector3(1.8, 0.65, 1.8), Transform3D(Basis(), Vector3(0, 0.325, 0)))
	_bake_box(st_sockel, Vector3(1.4, 0.35, 1.4), Transform3D(Basis(), Vector3(0, 0.825, 0)))
	var st_mast := SurfaceTool.new()
	st_mast.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bake_box(st_mast, Vector3(0.72, 8.0, 0.72), Transform3D(Basis(), Vector3(0, 5.0, 0)))
	_bake_box(st_mast, Vector3(0.52, 7.35, 0.52), Transform3D(Basis(), Vector3(0, 12.675, 0)))
	var st_kopf := SurfaceTool.new()
	st_kopf.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bake_box(st_kopf, Vector3(4.5, 0.25, 0.35), Transform3D(Basis(), Vector3(0, 16.25, 0)))
	var st_licht := SurfaceTool.new()
	st_licht.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Vier GETRENNTE Koepfe in zwei Paaren, jeder auf einem kurzen Staender UEBER dem
	# Traeger. Beides ist am Bild nachgebessert worden:
	#  - Der erste Wurf setzte die Koepfe mit 1.1 x 0.8 x 0.5 direkt unter den Traeger. In
	#    der Abnahmeansicht fp_vorfeld (Mast rund 150 m entfernt, also gut 0,3 px je 10 cm)
	#    verschmolzen Traeger und Koepfe zu EINEM waagerechten Strich — aus dem falschen
	#    Gegenstand war ein T-Balken geworden statt eines Leuchtenkranzes.
	#  - In heimat_1 und heimat_3 sitzen die Koepfe sichtbar OBERHALB des Traegers, und
	#    zwischen Traeger und Kopf steht Himmel. Genau dieser Spalt macht den Kranz.
	# Daher 1.25 x 0.95 x 0.62 (statt 1.1 x 0.8 x 0.5), Paare weiter auseinander und
	# 0,4 m Staender dazwischen.
	for ox in [-1.75, -0.62, 0.62, 1.75]:
		_bake_box(st_kopf, Vector3(0.14, 0.4, 0.14), Transform3D(Basis(), Vector3(ox, 16.55, 0.05)))
		var kopf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-30.0)), Vector3(ox, 17.0, 0.14))
		_bake_box(st_kopf, Vector3(1.25, 0.95, 0.62), kopf)
		_bake_box(st_licht, Vector3(1.08, 0.06, 0.52), kopf * Transform3D(Basis(), Vector3(0, -0.51, 0)))
	_multi(parent, st_sockel.commit(), stellen, _flat_mat(Color(0.66, 0.65, 0.62), 0.9))
	_multi(parent, st_mast.commit(), stellen, _flat_mat(Color(0.50, 0.50, 0.54), 0.6))
	_multi(parent, st_kopf.commit(), stellen, _flat_mat(Color(0.32, 0.33, 0.35), 0.7))
	# Gleiche Leuchtstaerke wie vorher (1.6), aber auf deutlich kleinerer Flaeche: die vier
	# Frontplatten messen zusammen 4 x 1,08 x 0,52 = 2,25 m^2 gegen 3,0 x 1,2 = 3,6 m^2 der
	# alten Leuchtplatte. Der Kopf liest sich damit als Punktgruppe, nicht als Laterne.
	_multi(parent, st_licht.commit(), stellen, _emit_mat(Color(1.0, 0.97, 0.85), 1.6))


## Kasten mit gegebener Groesse unter `xf` in eine SurfaceTool backen. Duenne Huelle um
## append_from — die Box-Normalen kommen dabei fertig mit, was bei handgeschriebenen
## Quads jedes Mal eine Fehlerquelle war.
func _bake_box(st: SurfaceTool, size: Vector3, xf: Transform3D) -> void:
	var b := BoxMesh.new()
	b.size = size
	st.append_from(b, 0, xf)


func _gitterturm(parent: Node3D, pos: Vector3, hoehe: float, b_unten: float, b_oben: float) -> void:
	var key := "gitter_%.1f_%.1f_%.1f" % [hoehe, b_unten, b_oben]
	var mesh: ArrayMesh
	if _fp_meshes.has(key):
		mesh = _fp_meshes[key]
	else:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var bein := BoxMesh.new()
		bein.size = Vector3(0.6, hoehe, 0.6)
		for ex in [-1.0, 1.0]:
			for ez in [-1.0, 1.0]:
				# Bein von (ex*b_unten, 0) nach (ex*b_oben, hoehe) -> leichte Neigung.
				var mitte := Vector3(ex * (b_unten + b_oben) * 0.5, hoehe * 0.5, ez * (b_unten + b_oben) * 0.5)
				var neig := Basis(Vector3(0, 0, 1), atan2(ex * (b_unten - b_oben), hoehe)) \
					* Basis(Vector3(1, 0, 0), atan2(-ez * (b_unten - b_oben), hoehe))
				st.append_from(bein, 0, Transform3D(neig, mitte))
		var strebe := BoxMesh.new()
		strebe.size = Vector3(1.0, 0.4, 0.4)
		for k in 4:
			var t := float(k + 1) / 5.0
			var b := lerpf(b_unten, b_oben, t)
			var y := hoehe * t
			for s in [-1.0, 1.0]:
				var q := BoxMesh.new()
				q.size = Vector3(2.0 * b, 0.38, 0.38)
				st.append_from(q, 0, Transform3D(Basis(), Vector3(0, y, s * b)))
				st.append_from(q, 0, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(s * b, y, 0)))
		mesh = st.commit()   # append_from bringt die Normalen der Boxen schon mit
		_fp_meshes[key] = mesh
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _flat_mat(Color(0.55, 0.56, 0.58), 0.6)
	parent.add_child(mi)
	# Plattform oben (die Schuessel steht sonst in der Luft)
	_deco_box(parent, pos + Vector3(0, hoehe + 0.3, 0), Vector3(2.0 * b_oben + 2.0, 0.4, 2.0 * b_oben + 2.0),
		_flat_mat(Color(0.6, 0.61, 0.63), 0.7))
	# Fundament
	_deco_box(parent, pos + Vector3(0, 0.5, 0), Vector3(2.0 * b_unten + 2.0, 1.0, 2.0 * b_unten + 2.0),
		_flat_mat(Color(0.64, 0.64, 0.62), 0.9))


# --- UMFELD DES PLATZES -----------------------------------------------------------
# WAS SICH HIER GEAENDERT HAT UND WARUM. Bis zu dieser Runde war das ein Notnagel:
# TerrainWorld hielt rund um jeden Platz einen KREIS von 620 m voellig frei und blendete
# erst ab 1147 m wieder ein, und der Guertel pflanzte in diesen Kreis 54 kuenstliche Haine
# mit rund 740 Baeumen, damit er nicht ganz leer aussah. Beides war falsch: der Guertel
# reichte nur bis 680 m und half genau dort nicht mehr, wo im Ueberflug die kahle Scheibe
# zu sehen war, und seine Haine waren eine zweite, groebere Waldsorte neben der des
# Gelaendes.
# Seit die Freihaltung an der BEBAUTEN Flaeche haengt (FP_RECHTECKE, siehe
# TerrainWorld._open_ground) pflanzt das Gelaende selbst bis 50 m an die Bahnkante — mit
# seinen sieben Baumarten, seiner Waldverteilung und dem dazu passenden Waldboden. Der
# Guertel darf das nicht noch einmal tun, sonst steht Wald in Wald.
# Was BLEIBT, ist der NAHSAUM, den das Gelaenderaster nicht liefern kann: die Felsbrocken
# direkt an der Bahnkante. Das Gelaende wuerfelt Felsen nach HANGNEIGUNG
# (0.004 + slope*0.012), und rund um den Platz ist alles auf y=0 eingeebnet — dort faellt
# also praktisch keiner. In heimat_4 liegen in den ersten 60 m neben der Bahn ueber ein
# Dutzend Brocken von 1 bis 3 m im Gras.
#
# PREIS: GEZAEHLT am laufenden Spiel (HEIMAT, Knoten "Umfeld") 257 Baeume, 151 Felsen und
# 106 Zaunpfosten gegen die frueheren rund 740 Baeume. Bei 22 Dreiecken je Baum und 48 je
# Felsbrocken sind das rund 13 000 statt rund 40 000 Dreiecke — der Saum wird also
# BILLIGER, und zwar deutlich. Weiterhin drei MultiMeshes = drei Zeichenaufrufe je Platz.
## kaverne: der Platz steht unter Tage. Dann faellt alles weg, was Himmel braucht, und
## uebrig bleiben Sturzbloecke am Wandfuss — das, was in einem gesprengten Stollen
## tatsaechlich herumliegt.
func _gruenguertel(wurzel: Node3D, kaverne := false) -> void:
	# Eigener Unterknoten: so laesst sich der Saum im Messwerkzeug in einem Rutsch
	# ausblenden und sein Anteil an der Bildzeit einzeln ablesen.
	var node := Node3D.new()
	node.name = "Umfeld"
	wurzel.add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED       # fester Wurf: derselbe Platz sieht bei jedem Start gleich aus
	var baeume: Array[Transform3D] = []
	var felsen: Array[Transform3D] = []
	# Gestreut wird ueber das umschriebene Rechteck beider Bauflaechen plus 150 m Saum;
	# behalten wird nur, was im Abstandsband 22..150 m um die Bebauung liegt. Unter 22 m
	# raeumt das Gelaende ohnehin frei (FREI_INNEN = 20 m) — dort stuende der Saum allein
	# und verriete sich als Ring.
	# RUNDE-3-BEFUND: der Guertel begann erst bei 22 m Abstand — genau die ersten zwanzig
	# Meter neben Belagkante und Vorfeld, die im Ueberflug und im Endanflug den groessten
	# Teil des Bildes fuellen, blieben leer. In heimat_1 und heimat_4 liegen die Findlinge
	# BIS AN DIE ASPHALTKANTE. Jetzt ab 1,5 m: naeher darf der Mittelpunkt nicht, sonst
	# steht ein 3-m-Brocken mit halbem Leib im Sandstreifen.
	# Die Felswahrscheinlichkeit musste dabei neu gestellt werden: die alte Kurve
	# 1 - smoothstep(20, 90, d) lag bei d = 22 noch bei 0,99, verteilt auf das neue,
	# deutlich groessere Nahband haette sie einen Steinbruch ergeben. 0,55 x
	# (1 - smoothstep(8, 95, d)) haelt die Gesamtzahl in der Groessenordnung der alten
	# 151 Brocken und schiebt sie nach innen.
	# UNTER TAGE WIRD NUR DAS BAND ZWISCHEN BAHNSCHULTER UND WANDFUSS GESTREUT. Die
	# Halle ist HB_W_HALLE breit; ab 6 m vor der Wand steigt sie schon merklich an, ein
	# Block dort haenge halb in der Luft.
	var kav_x: float = Landmarks.HB_W_HALLE - 6.0
	for versuch in 1700:
		var x := rng.randf_range(-175.0, 320.0)
		var z := rng.randf_range(-625.0, 625.0)
		if kaverne:
			x = rng.randf_range(-kav_x, kav_x)
			z = rng.randf_range(-520.0, 520.0)
		var d := _fp_abstand(x, z)
		if d < 1.5 or d > 150.0:
			continue
		if rng.randf() < 0.55 * (1.0 - smoothstep(8.0, 95.0, d)):
			# Findlinge, 1,5 bis 3,8 m breit (Vorgabe 1 bis 4 m). Der alte Saum warf sie mit
			# 3,0 bis 5,3 m zu GROSS — neben der 30-m-Bahn las sich das als Felsblock.
			var s := rng.randf_range(0.45, 1.15)
			felsen.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				.scaled(Vector3(s * 1.5, s * 0.8, s * 1.2)), Vector3(x, s * 0.2, z)))
		elif not kaverne and d > 30.0 and rng.randf() < 0.42:
			# Einzelbaeume ab 30 m Abstand — sie fuellen die Luecke zwischen Bahnkante und
			# dem Punkt, ab dem das Gelaende volle Dichte faehrt.
			var s2 := rng.randf_range(0.8, 1.5)
			baeume.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				.scaled(Vector3(s2, s2 * rng.randf_range(0.85, 1.25), s2)), Vector3(x, 0.0, z)))
	if not kaverne:
		_trockenflecken(node, rng, felsen)
	_multi(node, _baum_mesh(), baeume, null)
	var fels := SphereMesh.new()
	fels.radius = 1.1
	fels.height = 1.8
	fels.radial_segments = 6
	fels.rings = 3
	_multi(node, fels, felsen, _flat_mat(Color(0.46, 0.44, 0.40), 1.0))
	# --- PLATZZAUN westlich der Bahn (in heimat_1 und heimat_2 laeuft er dort mit) ---
	# Nicht unter Tage: der Berg IST die Umzaeunung.
	if kaverne:
		return
	var pfosten: Array[Transform3D] = []
	var zaun_x := -78.0
	var zaun_z0 := -430.0
	var n_pf := 106
	for i in n_pf:
		pfosten.append(Transform3D(Basis(), Vector3(zaun_x, 1.1, zaun_z0 + float(i) * 8.0)))
	var pf := BoxMesh.new()
	pf.size = Vector3(0.14, 2.2, 0.14)
	var zaun_mat := _flat_mat(Color(0.52, 0.53, 0.55), 0.7)
	_multi(node, pf, pfosten, zaun_mat)
	for wy in [1.1, 1.9]:
		_deco_box(node, Vector3(zaun_x, wy, zaun_z0 + float(n_pf - 1) * 4.0),
			Vector3(0.07, 0.07, float(n_pf - 1) * 8.0), zaun_mat)


## TROCKENFLECKEN im Grasguertel zwischen Belagkante und Baumbestand.
##
## RUNDE-3-BEFUND: dieser Guertel war voellig leer. Die Vorlagen zeigen dort in der Narbe
## unregelmaessige Trockenerd- und Sandflecken — in heimat_1 sind allein im Nahbereich
## mehrere Dutzend zu zaehlen, dichter am Vorfeld und an den Rollwegen als weiter draussen.
## Das Gelaende hat so etwas zwar (TerrainWorld._face_color, "Geroell-/Erdfleck"), aber
## erst in der grossflaechigen Biom-Schicht, die rund um den Platz Hunderte Meter entfernt
## einsetzt — genau dort, wo sie im Bild nicht mehr hilft.
##
## WARUM EIGENE FLAECHEN UND NICHT DIE GELAENDEFARBE: das Gelaende ist abgenommen und
## gehoert dieser Runde nicht. Es gibt aber auch einen sachlichen Grund — der Platz ebnet
## sein Umfeld auf exakt y = 0 ein (r_flat = 1700 m bei HEIMAT, weit ueber die 80 m dieses
## Guertels hinaus). Auf einer garantiert ebenen Flaeche ist ein flaches Netz bei y = 0.03
## das billigste denkbare Mittel: keine Hoehenabfrage, kein Z-Fighting, und wo es unter
## Sandstreifen (Oberkante 0.04) oder Beton (0.07) geraet, verschwindet es von selbst
## darunter — die Kanten des Platzes bleiben also sauber.
##
## FORM: 7 bis 10 Ecken mit gewuerfeltem Halbmesser um einen Mittelpunkt, als Dreiecks-
## faecher. Kein Kreis (die Ecken sitzen unregelmaessig) und kein Viereck, sondern derselbe
## kantige Umriss, den die Gelaende-Triangulierung daneben erzeugt.
##
## PREIS: rund 110 Flecken zu je 7 bis 10 Dreiecken, also rund 950 Dreiecke — in EINEM
## Netz, EINEM Zeichenaufruf, EINEM Material, flach liegend und ohne Kollision.
func _trockenflecken(node: Node3D, rng: RandomNumberGenerator, felsen: Array[Transform3D]) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)          # flat shading wie das ganze Low-Poly-Land
	var n := 0
	# 1400 Proben: bei der kleineren Fleckengroesse (4 bis 19 m statt 5 bis 25 m) deckt ein
	# Fleck nur noch rund 60 % der frueheren Flaeche ab — ohne mehr Proben waere der
	# Guertel nach der Groessenkorrektur duenner geworden statt dichter.
	for versuch in 1400:
		var x := rng.randf_range(-130.0, 280.0)
		var z := rng.randf_range(-560.0, 560.0)
		var d := _fp_abstand(x, z)
		# Band: von der Aussenkante des Sandstreifens (d = 0) bis 80 m nach aussen, umlaufend
		# um Bahn UND Vorfeld — FP_RECHTECKE deckt beides ab. Ab 2 m, damit kein Fleck zur
		# Haelfte unter dem Sandstreifen verschwindet.
		if d < 2.0 or d > 80.0:
			continue
		# Dichte faellt nach aussen: 0,90 an der Kante, 0,18 draussen.
		if rng.randf() > 0.18 + 0.72 * (1.0 - smoothstep(3.0, 70.0, d)):
			continue
		var r := rng.randf_range(2.0, 9.5)           # 4 bis 19 m Durchmesser
		var ecken := rng.randi_range(7, 10)
		# OCKERTON, EINGEMESSEN statt geschaetzt. Erster Wurf (0.63/0.575/0.395) stand im
		# Ueberflug bei sRGB(208, 197, 158) — praktisch der Ton der Sandschulter, die Flecken
		# lasen sich als verschuetteter Sand. In heimat_1 messen dieselben Flecken
		# sRGB(177, 157, 108), also deutlich dunkler und satter (das Gras daneben liegt dort
		# bei (105, 124, 36)). Umgerechnet ueber die Kennlinie (Bildwert rund scene^0.91)
		# ergibt das je Kanal Faktor 0.84 / 0.78 / 0.66 — daraus dieser Wert.
		# Je Fleck leicht anders: gleich getoente Flecken lesen sich als Muster, nicht als
		# Narbe.
		var t := rng.randf_range(0.84, 1.12)
		st.set_color(Color(0.53 * t, 0.45 * t, 0.26 * t))
		var mp := Vector3(x, 0.03, z)
		var ring: Array[Vector3] = []
		for k in ecken:
			# Winkel gleichmaessig, Halbmesser gewuerfelt: das gibt die eingebuchtete,
			# blobfoermige Kontur. Zusaetzlich am Winkel zu ruetteln erzeugte gelegentlich
			# ueberschlagende Kanten (Halbmesser gross bei zwei fast gleichen Winkeln).
			var a := TAU * float(k) / float(ecken)
			var rr := r * rng.randf_range(0.55, 1.0)
			ring.append(mp + Vector3(cos(a) * rr, 0.0, sin(a) * rr))
		for k in ecken:
			# Wicklung wie in _quad (Winkel steigend) — die umgekehrte Reihenfolge wird bei
			# Sicht von oben weggecullt, der Fleck waere nur von unten zu sehen.
			_tri(st, mp, ring[k], ring[(k + 1) % ecken], Vector3.UP)
		n += 1
		# FINDLINGE AM FLECKENRAND. In den Vorlagen haeufen sich die Steine dort, wo die
		# Narbe aufreisst. Sie kommen in dieselbe Liste wie die des Guertels und damit ins
		# selbe MultiMesh — kein zusaetzlicher Zeichenaufruf.
		if rng.randf() < 0.55:
			var ra := rng.randf_range(0.0, TAU)
			var s := rng.randf_range(0.45, 1.05)
			var rp := mp + Vector3(cos(ra), 0.0, sin(ra)) * r * rng.randf_range(0.8, 1.15)
			felsen.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				.scaled(Vector3(s * 1.5, s * 0.8, s * 1.2)), Vector3(rp.x, s * 0.2, rp.z)))
	if n == 0:
		return
	# EINMAL bauen, siebenmal benutzen: alle sieben Plaetze haben dieselbe Bebauungsflaeche
	# und denselben festen Wurf, das Netz ist also bei allen bitgleich. Die SCHLEIFE muss
	# trotzdem jedes Mal laufen — sie liefert die Findlinge am Fleckenrand und haelt die
	# Zufallsfolge des Guertels im Takt.
	if not _fp_meshes.has("trockenflecken"):
		_fp_meshes["trockenflecken"] = st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _fp_meshes["trockenflecken"]
	var mat := _flat_mat(Color.WHITE, 1.0)
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	# Kein Schattenwurf: die Flecken sind FARBE auf dem Boden, keine Erhebung. Mit Schatten
	# saeumte jeder von ihnen einen 3 cm hohen Schlagschatten und sah aus wie eine Platte.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)


## Abstand zur BEBAUTEN Flaeche in Platz-Koordinaten, 0 = mittendrin. Rechnet mit
## FP_RECHTECKE, also mit exakt denselben Kanten, an denen TerrainWorld._open_ground
## freiraeumt. Frueher stand hier eine eigene, groessere Sperrflaeche (|x| < 46 und
## |z| < 790) — die passte zur alten Kreis-Freihaltung, haette jetzt aber einen 790 m
## langen baumfreien Schlauch laengs der Bahn hinterlassen, waehrend das Gelaende
## daneben schon ab 50 m pflanzt.
func _fp_abstand(x: float, z: float) -> float:
	var nah := 1.0e9
	for r in FP_RECHTECKE:
		var qx: float = absf(x - float(r[0])) - float(r[2])
		var qz: float = absf(z - float(r[1])) - float(r[3])
		if qx <= 0.0 and qz <= 0.0:
			return 0.0
		var ex := maxf(qx, 0.0)
		var ez := maxf(qz, 0.0)
		nah = minf(nah, sqrt(ex * ex + ez * ez))
	return nah


## MultiMesh-Instanz anlegen (ein Zeichenaufruf fuer beliebig viele Kopien).
func _multi(parent: Node3D, mesh: Mesh, xfs: Array[Transform3D], mat: Material) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	parent.add_child(mmi)


## Low-Poly-Nadelbaum, rund 11 m hoch: Stamm + zwei Kegel.
## ZWEI FLAECHEN mit je eigenem Material statt einer Flaeche mit Vertexfarben. Die
## Vertexfarben-Fassung stand im Bild kalkweiss da — weder SurfaceTool.set_material noch
## ein material_override mit vertex_color_use_as_albedo brachten die Farbe ans MultiMesh.
## Zwei Flaechen kosten einen Zeichenaufruf mehr je Guertel und sind dafuer sicher.
func _baum_mesh() -> ArrayMesh:
	if _fp_meshes.has("baum"):
		return _fp_meshes["baum"]
	var m := ArrayMesh.new()
	var s_stamm := SurfaceTool.new()
	s_stamm.begin(Mesh.PRIMITIVE_TRIANGLES)
	_kegel(s_stamm, Vector3(0, 0, 0), 0.42, 0.30, 3.0, 5)
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s_stamm.commit_to_arrays())
	var s_laub := SurfaceTool.new()
	s_laub.begin(Mesh.PRIMITIVE_TRIANGLES)
	_kegel(s_laub, Vector3(0, 2.2, 0), 2.7, 0.0, 5.2, 6)
	_kegel(s_laub, Vector3(0, 5.6, 0), 1.9, 0.0, 5.2, 6)
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s_laub.commit_to_arrays())
	m.surface_set_material(0, _flat_mat(Color(0.30, 0.20, 0.13), 0.95))
	m.surface_set_material(1, _flat_mat(Color(0.13, 0.32, 0.15), 0.95))
	_fp_meshes["baum"] = m
	return m


## Kegelstumpf mit Deckel-los offener Unterseite (von unten sieht ihn nie jemand).
func _kegel(st: SurfaceTool, fuss: Vector3, r0: float, r1: float, h: float, seg: int) -> void:
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		var u0 := Vector3(cos(a0), 0.0, sin(a0))
		var u1 := Vector3(cos(a1), 0.0, sin(a1))
		var n := (u0 + u1).normalized() * 0.85 + Vector3.UP * 0.25 * (r0 - r1) / maxf(h, 0.01)
		var p0 := fuss + u0 * r0
		var p1 := fuss + u1 * r0
		var q0 := fuss + u0 * r1 + Vector3(0, h, 0)
		var q1 := fuss + u1 * r1 + Vector3(0, h, 0)
		for v in [[p0, p1, q1], [p0, q1, q0]]:
			for k in 3:
				st.set_normal(n.normalized())
				st.add_vertex(v[k])


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var nn := n.normalized()
	for v in [a, b, c]:
		st.set_normal(nn)
		st.add_vertex(v)


func _collider_box(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	parent.add_child(sb)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)


# Sichtbarer + solider Quader (Mesh + Box-Kollision), pos = Mitte.
func _solid_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	parent.add_child(sb)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)


# Sichtbarer + solider Zylinder, pos = Mitte.
func _solid_cyl(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	parent.add_child(sb)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	sb.add_child(cs)


# Hindernis-Parcours nahe HEIMAT (Startbahn-Achse = -Z): Pylonen-Slalom, Durchflug-Tore,
# Findlinge zum Tieffliegen und Sperrballons in der Luft. Alles solide -> harter Kontakt
# reißt (über AircraftBody._evaluate_impact) die getroffenen Teile ab.
func _build_obstacles() -> void:
	var root := Node3D.new()
	root.name = "Hindernisse"
	fly_world.add_child(root)
	var concrete := _flat_mat(Color(0.7, 0.71, 0.73), 0.85)
	var red := _flat_mat(Color(0.85, 0.2, 0.18), 0.7)
	var white := _flat_mat(Color(0.92, 0.92, 0.93), 0.7)
	var rock := _flat_mat(Color(0.4, 0.38, 0.35), 1.0)

	# (Alles HINTER dem Ende der 900-m-Bahn von HEIMAT — Bahn endet bei Welt-z ≈ -550.)
	# Slalom-Pylonen abwechselnd links/rechts der Achse (zum Durchweben), Bahn bleibt frei
	var pyh := 45.0
	var z := -1030.0
	var side := 1.0
	for k in range(8):
		var col: Material = red if (k % 2 == 0) else white
		_solid_cyl(root, Vector3(side * 18.0, pyh * 0.5, z), 2.2, pyh, col)
		z -= 80.0
		side = -side

	# Drei Durchflug-Tore (zwei Pfeiler + Querbalken, Lücke offen) — leicht versetzt = Slalom
	for g in [Vector3(0, 0, -1080), Vector3(28, 0, -1260), Vector3(-28, 0, -1460)]:
		_build_gate(root, g, concrete)

	# Findlinge am Boden (zum Tieffliegen / Ausweichen)
	for b in [Vector3(-55, 0, -880), Vector3(48, 0, -950), Vector3(-42, 0, -1140), Vector3(60, 0, -1310)]:
		var rr := randf_range(9.0, 15.0)
		_solid_cyl(root, b + Vector3(0, rr * 0.35, 0), rr, rr * 0.7, rock)

	# Sperrballons (WWI-Thema) in der Luft — grau, NICHT abschießbar, nur ausweichen
	for bp in [Vector3(22, 55, -1170), Vector3(-32, 72, -1380)]:
		_build_balloon(root, bp)


# Durchflug-Tor: zwei Pfeiler + Querbalken oben; man fliegt durch die Lücke.
func _build_gate(parent: Node3D, pos: Vector3, mat: Material) -> void:
	var ph := 30.0          # Pfeilerhöhe
	var gap := 38.0         # lichte Weite zwischen den Pfeilern
	var pillar := Vector3(4, ph, 4)
	_solid_box(parent, pos + Vector3(-gap * 0.5, ph * 0.5, 0), pillar, mat)
	_solid_box(parent, pos + Vector3(gap * 0.5, ph * 0.5, 0), pillar, mat)
	_solid_box(parent, pos + Vector3(0, ph + 2.0, 0), Vector3(gap + 8, 4, 4), mat)


# Sperrballon: dicke Hülle (Kollision) an dünnem Halteseil (nur Optik).
func _build_balloon(parent: Node3D, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	parent.add_child(sb)
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 12.0
	sphere.height = 24.0
	mi.mesh = sphere
	mi.scale = Vector3(1.0, 1.0, 1.4)   # länglich (Zeppelin-artig)
	mi.material_override = _flat_mat(Color(0.55, 0.55, 0.62), 0.6)
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = 12.0
	cs.shape = ss
	sb.add_child(cs)
	# Halteseil zum Boden (nur Optik)
	var rope := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.18
	rm.bottom_radius = 0.18
	rm.height = pos.y
	rope.mesh = rm
	rope.position = Vector3(0, -pos.y * 0.5, 0)
	rope.material_override = _flat_mat(Color(0.18, 0.18, 0.2), 1.0)
	sb.add_child(rope)


func _setup_camera() -> void:
	camera = Camera3D.new()
	# Die Kamera wird in _process geführt -> NICHT physik-interpolieren
	# (sonst kämpfen zwei Glättungen; Godot warnt sonst pro Frame).
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	ViewUtil.apply_vfov(camera, 64.0)   # ultrawide-bewusst (kein Fischauge auf 21:9/32:9)
	camera.far = KAMERA_FERN
	camera.current = true
	add_child(camera)


func _setup_controllers() -> void:
	build_ctrl = BuildController.new()
	add_child(build_ctrl)
	build_ctrl.set_camera(camera)
	build_ctrl.design_changed.connect(_on_design_changed)
	build_ctrl.selection_changed.connect(_on_selection_changed)
	build_ctrl.snap_changed.connect(_on_snap_changed)
	build_ctrl.kopiert.connect(func(n: String) -> void: _toast("Kopiert: %s (Strg+V einfügen)"
		% PartCatalog.get_part(n).get("name", n)))
	build_ctrl.farbe_gepickt.connect(_on_farbe_gepickt)
	build_ctrl.pipette_umgeschaltet.connect(func(an: bool) -> void:
		if pipette_btn != null:
			pipette_btn.button_pressed = an
		_refresh_tool_ui())

	flight_ctrl = FlightController.new()
	add_child(flight_ctrl)
	flight_ctrl.set_camera(camera)
	flight_ctrl.hud_changed.connect(_on_hud_changed)
	flight_ctrl.map_requested.connect(_toggle_map)


# ===========================================================================
# MODUS
# ===========================================================================
func _set_mode(m: int) -> void:
	# Nicht starten ohne Cockpit/Wurzel (leerer Bauraum) — da startet der Bauplan.
	if m == Mode.FLY and mode == Mode.BUILD and build_ctrl != null and not build_ctrl.has_root():
		_toast("Erst ein Cockpit setzen — das ist der Start deines Bauplans.")
		return
	# Nicht starten, wenn Teile frei schweben (nicht mit dem Flugzeug verbunden).
	if m == Mode.FLY and mode == Mode.BUILD and build_ctrl != null and build_ctrl.has_floating():
		_toast("%d Teil(e) hängen frei (rot markiert) — erst verbinden, dann Start" % build_ctrl.floating_count())
		return
	var was_fly := (mode == Mode.FLY)
	mode = m
	var building := (m == Mode.BUILD)
	build_ctrl.set_active(building)
	build_ctrl.design_root.visible = building
	build_root.visible = building
	flight_root.visible = not building

	# Blueprint-Raum im Bau-Modus, Himmel + Flug-Welt im Flug
	world_env.environment = env_blueprint if building else env_sky
	fly_world.visible = not building
	if showroom != null:
		# Eigene Methode statt `visible`: die Vignette haengt in einem CanvasLayer und
		# wuerde sonst auch im Flug stehen bleiben.
		showroom.set_stage_visible(building)
	if sky_lights != null:
		sky_lights.visible = not building  # Sonne nur im Flug

	if building:
		flight_ctrl.set_active(false)
		flight_ctrl.clear_aircraft()
		# Aus dem Survival-Flug zurück -> Flug-Auswertung zeigen
		if was_fly and game != null and not game.is_sandbox() and _wave > 0:
			_show_result_screen()
	else:
		if game != null:
			flight_ctrl.thrust_mult = game.thrust_mult()
			flight_ctrl.wing_mult = game.wing_mult()
			flight_ctrl.mass_mult = game.mass_mult()
		flight_ctrl.build_from_design(build_ctrl.get_design())
		flight_ctrl.set_active(true)
		_begin_flight()        # Survival: Welle 1 starten + Score zurücksetzen
		# Einmaliger Steuer-Hinweis beim allerersten Flug
		if game != null and not game.flag("controls_hint"):
			game.set_flag("controls_hint")
			_show_controls_hint()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_set_mode(Mode.FLY if mode == Mode.BUILD else Mode.BUILD)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			# Esc öffnet das Pause-Menü (Weiter / Hangar / Beenden). Vollbild via F11.
			_set_pause(true)
			get_viewport().set_input_as_handled()


func _toggle_fullscreen() -> void:
	var win := DisplayServer.WINDOW_MODE_WINDOWED if \
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN \
		else DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(win)
	_toast("Vollbild: " + ("AN  (F11)" if win == DisplayServer.WINDOW_MODE_FULLSCREEN else "aus"))


# --- Pause-Menü (Esc) -------------------------------------------------------
func _set_pause(p: bool) -> void:
	if _paused == p:
		return
	_paused = p
	if p and pause_overlay == null:
		_build_pause_overlay()
	if pause_overlay:
		pause_overlay.visible = p
	if p:
		_prev_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = _prev_mouse
	get_tree().paused = p


func _build_pause_overlay() -> void:
	pause_overlay = ColorRect.new()
	(pause_overlay as ColorRect).color = Color(0.03, 0.05, 0.09, 0.82)
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS   # bleibt bei get_tree().paused bedienbar
	pause_overlay.visible = false
	ui.add_child(pause_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(300, 0)
	center.add_child(v)
	var t := _lbl("PAUSE", 30, Color(0.6, 1.0, 0.7))
	t.add_theme_font_override("font", F_BOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b_resume := Button.new()
	b_resume.text = "Weiter"
	b_resume.pressed.connect(func(): _set_pause(false))
	v.add_child(b_resume)
	# Maus-Flug-Empfindlichkeit (0.5–2.0, persistiert in GameState)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	v.add_child(srow)
	srow.add_child(_lbl("Maus-Empfindlichkeit:", 14, Color(0.8, 0.88, 1.0)))
	var sval := _lbl("×%.1f" % game.mouse_sens, 15, Color(0.7, 1.0, 0.8))
	var sminus := Button.new(); sminus.text = "−"; sminus.custom_minimum_size = Vector2(38, 0)
	var splus := Button.new(); splus.text = "+"; splus.custom_minimum_size = Vector2(38, 0)
	var apply_sens := func(d: float):
		game.mouse_sens = clampf(snappedf(game.mouse_sens + d, 0.1), 0.5, 2.0)
		flight_ctrl.sens_mult = game.mouse_sens
		game.save()
		sval.text = "×%.1f" % game.mouse_sens
	sminus.pressed.connect(func(): apply_sens.call(-0.1))
	splus.pressed.connect(func(): apply_sens.call(0.1))
	srow.add_child(sminus)
	srow.add_child(sval)
	srow.add_child(splus)
	# --- GRAFIK ------------------------------------------------------------------------
	# Aufklappbar, damit das Pausenmenue nicht zur Wand wird. Jede Zeile nennt ihre
	# Wirkung: eine Einstellung, deren Preis man nicht kennt, stellt niemand um.
	var g_auf := Button.new()
	g_auf.text = "Grafik ▾"
	v.add_child(g_auf)
	var gbox := VBoxContainer.new()
	gbox.add_theme_constant_override("separation", 6)
	gbox.visible = false
	v.add_child(gbox)
	g_auf.pressed.connect(func():
		gbox.visible = not gbox.visible
		g_auf.text = "Grafik ▴" if gbox.visible else "Grafik ▾")

	# Ein Umschalter mit fester Beschriftungsbreite, damit die Knoepfe untereinander stehen.
	var schalter := func(titel: String, hinweis: String, texte: Array,
			lies: Callable, schreib: Callable) -> void:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		gbox.add_child(row)
		var l := _lbl(titel, 14, Color(0.80, 0.88, 1.0))
		l.custom_minimum_size = Vector2(186, 0)
		row.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, 0)
		b.text = String(texte[clampi(int(lies.call()), 0, texte.size() - 1)])
		b.pressed.connect(func():
			var neu: int = (int(lies.call()) + 1) % texte.size()
			schreib.call(neu)
			b.text = String(texte[neu])
			grafik_anwenden()
			game.save())
		row.add_child(b)
		gbox.add_child(_lbl(hinweis, 11, Color(0.55, 0.66, 0.78)))

	schalter.call("Wolkenschatten", "Wolken werfen Schatten auf den Boden — die staerkste Erdung der Flugwelt.",
		["aus", "an"],
		func(): return 1 if game.gfx_wolkenschatten else 0,
		func(n): game.gfx_wolkenschatten = n == 1)
	schalter.call("Schlagschatten", "Groesster Einzelposten: gemessen rund ein Drittel der Bildzeit.",
		["aus", "an"],
		func(): return 1 if game.gfx_sonnenschatten else 0,
		func(n): game.gfx_sonnenschatten = n == 1)
	schalter.call("Baumweite", "Wie weit echte Baeume stehen. Flora ist gemessen 59 % der Bildzeit.",
		["nah", "normal", "weit"],
		func(): return game.gfx_baumweite,
		func(n): game.gfx_baumweite = n)
	schalter.call("Wolkenschichten", "Keine, nur die Kumulusdecke, oder alle vier Hoehen.",
		["keine", "nur Kumulus", "alle"],
		func(): return game.gfx_wolkenlagen,
		func(n): game.gfx_wolkenlagen = n)
	schalter.call("Aufloesung", "Rechnet das Bild kleiner und skaliert hoch. Trifft alles, auch den Himmel.",
		["70 %", "85 %", "100 %"],
		func(): return {70: 0, 85: 1, 100: 2}.get(game.gfx_aufloesung, 2),
		func(n): game.gfx_aufloesung = [70, 85, 100][n])

	var b_hangar := Button.new()
	b_hangar.text = "Zum Hangar"
	b_hangar.pressed.connect(_pause_to_hangar)
	v.add_child(b_hangar)
	var b_quit := Button.new()
	b_quit.text = "Spiel beenden"
	b_quit.pressed.connect(func():
		if _design_dirty:
			_save_design()   # ungesicherte Bauänderungen noch mitnehmen
		get_tree().quit())
	v.add_child(b_quit)


func _pause_to_hangar() -> void:
	_paused = false
	get_tree().paused = false
	if pause_overlay:
		pause_overlay.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if mode != Mode.BUILD:
		_set_mode(Mode.BUILD)


# Einmaliger Steuer-Hinweis beim allerersten Flug (blendet nach 12 s aus).
func _show_controls_hint() -> void:
	if is_instance_valid(_hint_box):
		_hint_box.queue_free()
	var box := ColorRect.new()
	box.color = Color(0.03, 0.06, 0.10, 0.85)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect(box, 0.5, 0, 0.5, 0, -300, 84, 300, 246)
	ui.add_child(box)
	var lbl := _lbl("STEUERUNG  (blendet gleich aus)\n\nW/S = Nase hoch/runter    ·    A/D = rollen (A = RECHTS!)\nQ/E = gieren    ·    Shift / Strg = Schub / bremsen\nLeertaste / Linksklick = feuern    ·    B = Bombe    ·    G = Fahrwerk\nM = KARTE    ·    N = Maus-/Tastatur-Flug (Start: MAUS)    ·    H = G-Schutz    ·    J = Arcade    ·    T = Assist\nEnter = Reset/Reparatur    ·    Tab = zurück zum Hangar    ·    Esc = Pause", 15, Color(0.86, 0.95, 1.0))
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(lbl)
	_hint_box = box
	get_tree().create_timer(12.0, false).timeout.connect(func():   # pause-bewusst
		if is_instance_valid(box):
			box.queue_free())


# ===========================================================================
# UI
# ===========================================================================
# EIN zentrales Theme statt verstreuter Einzel-Styles: dunkle Blueprint-Optik,
# azurner Akzent, runde Ecken. Explizite Overrides (Kacheln, Header, Ampel)
# gewinnen weiterhin gegen das Theme — das hier ist die saubere Grundschicht.
func _make_ui_theme() -> Theme:
	# Die Farben kommen aus ShowroomStage — dieselbe Palette wie die 3D-Buehne, damit
	# UI und Bild zusammengehoeren und nicht an zwei Stellen nachgezogen werden muessen.
	# Frueher stand hier ein eigenes Blau-Schema, das neben dem Petrolraum fremd wirkte.
	var th := Theme.new()
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.055, 0.145, 0.170, 0.90)          # Petrol, halbtransparent
	n.set_corner_radius_all(7)
	n.set_border_width_all(1)
	n.border_color = Color(ShowroomStage.AKZENT_KALT, 0.22)
	n.content_margin_left = 12
	n.content_margin_right = 12
	n.content_margin_top = 6
	n.content_margin_bottom = 6
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = Color(0.085, 0.215, 0.245, 0.95)
	h.border_color = Color(ShowroomStage.AKZENT_KALT, 0.55)
	# AKTIV = orange. Das ist die einzige warme Farbe in der UI und trennt dadurch
	# eindeutig, was gerade gewaehlt ist.
	var pr: StyleBoxFlat = n.duplicate()
	pr.bg_color = Color(ShowroomStage.AKZENT, 0.90)
	pr.border_color = Color(1.0, 0.78, 0.55, 0.9)
	var dis: StyleBoxFlat = n.duplicate()
	dis.bg_color = Color(0.045, 0.095, 0.110, 0.55)
	dis.border_color = Color(1, 1, 1, 0.06)
	th.set_stylebox("normal", "Button", n)
	th.set_stylebox("hover", "Button", h)
	th.set_stylebox("pressed", "Button", pr)
	th.set_stylebox("disabled", "Button", dis)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", ShowroomStage.TEXT)
	th.set_color("font_hover_color", "Button", Color(1, 1, 1))
	th.set_color("font_pressed_color", "Button", Color(0.16, 0.09, 0.04))   # dunkel auf Orange
	th.set_color("font_disabled_color", "Button", Color(0.55, 0.66, 0.68))
	# Checkboxen: kein Knopf-Kasten, nur Haken + Text (ruhiger)
	th.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	th.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	th.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	th.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	th.set_color("font_color", "CheckBox", ShowroomStage.TEXT)
	# Tooltips: dunkel-glasig mit kaltem Akzentrand
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.030, 0.080, 0.095, 0.97)
	tip.set_corner_radius_all(8)
	tip.set_border_width_all(1)
	tip.border_color = Color(ShowroomStage.AKZENT_KALT, 0.40)
	tip.set_content_margin_all(10)
	th.set_stylebox("panel", "TooltipPanel", tip)
	th.set_color("font_color", "TooltipLabel", ShowroomStage.TEXT)
	# Trenner dezent
	var sep := StyleBoxLine.new()
	sep.color = Color(ShowroomStage.AKZENT_KALT, 0.16)
	th.set_stylebox("separator", "HSeparator", sep)
	return th


func _setup_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	var th := _make_ui_theme()
	build_root = Control.new()
	build_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	build_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_root.theme = th
	ui.add_child(build_root)

	flight_root = Control.new()
	flight_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	flight_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight_root.theme = th
	ui.add_child(flight_root)

	_build_hangar_ui()
	_build_praesentation_panel()
	_build_flight_ui()


func _build_hangar_ui() -> void:
	# --- Linkes Bau-Panel (eingerückt -> schwebt) ---
	var panel := _panel(Color(0, 0, 0, 0.5))
	_rect(panel, 0, 0, 0, 1, 18, 18, 496, -18)
	build_root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	money_label = _lbl("", 15, Color(1.0, 0.86, 0.3))
	vb.add_child(money_label)
	tool_label = _lbl("Werkzeug: bereit", 12, Color(0.7, 1.0, 0.7))
	tool_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tool_label)

	# --- Kategorie-Reiter als runde Emoji-Icons (oben) ---
	var icon_row := HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 5)
	icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(icon_row)
	_cat_icon_btns.clear()
	# Gestaltete SVG-Icons (res://icons/) je Kategorie: Rumpf/Flügel/Leitwerk/Antrieb/Fahrwerk/Waffen
	var cat_icons := [
		"res://icons/rumpf.svg", "res://icons/fluegel.svg", "res://icons/leitwerk.svg",
		"res://icons/antrieb.svg", "res://icons/fahrwerk.svg", "res://icons/waffen.svg",
	]
	var cats := PartCatalog.categories()
	for i in cats.size():
		var ib := _make_icon_btn(cat_icons[i] if i < cat_icons.size() else "res://icons/more.svg")
		ib.tooltip_text = String(cats[i])
		ib.pressed.connect(_on_cat_icon.bind(i))
		icon_row.add_child(ib)
		_cat_icon_btns.append(ib)
	tools_icon_btn = _make_icon_btn("res://icons/more.svg")
	tools_icon_btn.tooltip_text = "Werkzeuge & mehr (Lackieren, Upgrades, Speichern …)"
	tools_icon_btn.pressed.connect(_on_tools_icon)
	icon_row.add_child(tools_icon_btn)

	# --- BAUTEILE-Ansicht: großes 3D-Vorschau-Grid ---
	parts_view = ScrollContainer.new()
	parts_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parts_view.custom_minimum_size = Vector2(0, 240)
	parts_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(parts_view)
	part_grid = GridContainer.new()
	part_grid.columns = 3
	part_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	part_grid.add_theme_constant_override("h_separation", 6)
	part_grid.add_theme_constant_override("v_separation", 6)
	parts_view.add_child(part_grid)
	_fill_part_grid()

	# --- WERKZEUGE-Ansicht (hinter dem ••• -Reiter) ---
	tools_view = ScrollContainer.new()
	tools_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tools_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tools_view.visible = false
	vb.add_child(tools_view)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 6)
	tools_view.add_child(tv)

	tv.add_child(_section("WERKZEUGE"))
	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 6)
	tv.add_child(tool_row)
	var move_btn := Button.new()
	move_btn.text = "Bewegen / Greifen"
	move_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_btn.pressed.connect(_on_move_tool)
	tool_row.add_child(move_btn)
	var erase_btn := Button.new()
	erase_btn.text = "Abriss"
	erase_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	erase_btn.pressed.connect(_on_erase_tool)
	tool_row.add_child(erase_btn)

	tv.add_child(_section("LACKIEREN"))

	# Kopfzeile: aktuelle Farbe + freie Farbwahl + Pipette. Die drei gehoeren zusammen —
	# man sieht, womit man malt, kann jede Farbe mischen und eine vorhandene aufnehmen.
	var farb_kopf := HBoxContainer.new()
	farb_kopf.add_theme_constant_override("separation", 6)
	tv.add_child(farb_kopf)

	paint_preview = ColorRect.new()
	paint_preview.custom_minimum_size = Vector2(38, 30)
	paint_preview.color = build_ctrl.paint_color
	paint_preview.tooltip_text = "Aktuelle Lackfarbe"
	farb_kopf.add_child(paint_preview)

	paint_picker = ColorPickerButton.new()
	paint_picker.custom_minimum_size = Vector2(0, 30)
	paint_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint_picker.text = "Farbe mischen"
	paint_picker.color = build_ctrl.paint_color
	paint_picker.edit_alpha = false
	paint_picker.tooltip_text = "Beliebige Farbe wählen (Farbrad, RGB, Hex)"
	paint_picker.color_changed.connect(_on_paint_color)
	farb_kopf.add_child(paint_picker)

	pipette_btn = Button.new()
	pipette_btn.toggle_mode = true
	pipette_btn.text = "Pipette"
	pipette_btn.custom_minimum_size = Vector2(78, 30)
	pipette_btn.tooltip_text = "Pipette: Farbe von einem vorhandenen Teil aufnehmen (Taste P)"
	pipette_btn.pressed.connect(_on_pipette)
	farb_kopf.add_child(pipette_btn)

	var hinweis := _lbl("Farbe wählen, dann Teil anklicken · Pipette nimmt die Farbe eines Teils", 11,
		Color(0.66, 0.72, 0.80))
	hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(hinweis)

	# Palette in zwei Bloecken: erst Flugzeug-Lackierungen (die man wirklich braucht),
	# darunter kraeftige Farben zum Markieren.
	for gruppe in [
		["Militär & Zivil", [
			Color("3f4a3a"), Color("6a7355"), Color("8d8163"), Color("c8b892"),
			Color("2c3742"), Color("55606b"), Color("9aa3ad"), Color("d8dde3"),
			Color("eef0f4"), Color("1b2027"), Color("4a3b2c"), Color("7a5c3a"),
			Color("1d3f6e"), Color("2f74bd"),
		]],
		["Kräftig", [
			Color("d6382f"), Color("e8821a"), Color("eccb47"), Color("46a85a"),
			Color("19bfc7"), Color("8e44ad"), Color("e85b9a"), Color("8bd24a"),
			Color("f2f2f2"), Color("121519"), Color("b3801f"), Color("6e4a2c"),
			Color("0f8f7a"), Color("c2352f"),
		]],
	]:
		var titel := _lbl(String(gruppe[0]), 11, Color(0.55, 0.62, 0.72))
		tv.add_child(titel)
		var pal := GridContainer.new()
		pal.columns = 7
		pal.add_theme_constant_override("h_separation", 5)
		pal.add_theme_constant_override("v_separation", 5)
		tv.add_child(pal)
		for c in (gruppe[1] as Array):
			pal.add_child(_farb_knopf(c))

	# Ansicht/Undo/Redo/Windkanal/Zentrieren sind jetzt in der oberen WERKZEUGLEISTE (_build_toolbar).
	# Hier bleibt nur die Windkanal-Farblegende (erscheint, wenn der Windkanal an ist).
	tv.add_child(_section("WINDKANAL-LEGENDE"))
	var leg := VBoxContainer.new()
	leg.add_theme_constant_override("separation", 2)
	var bar := TextureRect.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.set_color(0, Color(0.16, 0.75, 0.30))
	grad.set_color(1, Color(0.92, 0.18, 0.12))
	grad.add_point(0.5, Color(0.95, 0.85, 0.25))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 220
	gt.height = 10
	bar.texture = gt
	leg.add_child(bar)
	var leg_row := HBoxContainer.new()
	var l1 := _lbl("wenig Widerstand", 10, Color(0.62, 0.9, 0.65))
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leg_row.add_child(l1)
	var l2 := _lbl("viel", 10, Color(1.0, 0.55, 0.45))
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	leg_row.add_child(l2)
	leg.add_child(leg_row)
	leg.add_child(_lbl("grau = Windschatten (verdeckt)", 10, Color(0.7, 0.74, 0.8)))
	leg.visible = false
	wind_legend = leg
	tv.add_child(leg)

	tv.add_child(_section("UPGRADES"))
	upgrade_box = VBoxContainer.new()
	upgrade_box.add_theme_constant_override("separation", 2)
	tv.add_child(upgrade_box)

	tv.add_child(_section("FLUGZEUG"))
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 6)
	tv.add_child(frow)
	var clear_btn := Button.new()
	clear_btn.text = "Neu"
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_btn.pressed.connect(_on_clear_pressed)
	frow.add_child(clear_btn)
	var save_btn := Button.new()
	save_btn.text = "Speichern"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_on_save_pressed)
	frow.add_child(save_btn)
	var load_btn := Button.new()
	load_btn.text = "Laden"
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.pressed.connect(_on_load_pressed)
	frow.add_child(load_btn)

	_refresh_cat_icons()

	# (Snap/Undo/Symmetrie + alle weiteren Aktionen sind jetzt in der oberen WERKZEUGLEISTE.)

	# --- Testflug-Button oben mitte ---
	var fly_btn := Button.new()
	fly_btn.text = "TESTFLUG STARTEN   (Tab)"
	fly_btn.add_theme_font_size_override("font_size", 18)
	fly_btn.add_theme_font_override("font", F_BOLD)
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.10, 0.34, 0.62, 0.95)
	fb.set_corner_radius_all(10)
	fb.set_border_width_all(1)
	fb.border_color = Color(0.55, 0.8, 1.0, 0.7)
	fb.set_content_margin_all(8)
	var fbh: StyleBoxFlat = fb.duplicate()
	fbh.bg_color = Color(0.14, 0.44, 0.78, 0.98)
	fly_btn.add_theme_stylebox_override("normal", fb)
	fly_btn.add_theme_stylebox_override("hover", fbh)
	fly_btn.add_theme_stylebox_override("pressed", fbh)
	fly_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_rect(fly_btn, 0.5, 0, 0.5, 0, -160, 18, 160, 60)
	fly_btn.pressed.connect(_on_fly_pressed)
	build_root.add_child(fly_btn)

	# Obere WERKZEUGLEISTE: alle Editor-Funktionen sichtbar & klickbar (statt nur Tastenkürzel).
	_build_toolbar()

	# --- Flug-Check (grafisch) oben rechts ---
	var spanel := _panel(Color(0, 0, 0, 0.5))
	# Höhe wächst mit dem Inhalt (Diagramm + Balken + Detail-Zahlen + Windkanal-Report).
	_rect(spanel, 1, 0, 1, 0, -340, 18, -18, 88)
	build_root.add_child(spanel)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	spanel.add_child(sv)
	var fc_title := _lbl("FLUG-CHECK", 16, Color(0.65, 0.82, 1.0))
	fc_title.add_theme_font_override("font", F_BOLD)
	sv.add_child(fc_title)
	flight_check = FlightCheckPanel.new()
	sv.add_child(flight_check)
	stats_label = _lbl("", 13)
	sv.add_child(stats_label)
	var legend := _lbl("gelb = Schwerpunkt · blau = Auftriebspunkt (auch im 3D-Bild markiert)", 11, Color(0.8, 0.84, 0.9))
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(legend)

	_build_selection_panel()

	# --- Hinweisleiste unten ---
	var hint := _lbl("Aus Liste ziehen = bauen (rastet am Teil unter der Maus) · Teil ziehen = andocken wo du hinzeigst (Anbauten wandern mit · Alt = nur das Teil) · Teil klicken = bearbeiten (G/R/S) · Strg+D: duplizieren · Pfeile: verschieben · 1/2/3 Ansicht Front/Seite/Oben, 4 frei · X: löschen · M: Symmetrie · Strg+Z/Y: Undo · F: Ansicht", 13, Color(0.25, 0.32, 0.42))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# OHNE Umbruch ist die Mindestbreite eines Labels die volle Textbreite — die Anker
	# koennen es dann nicht schmaler machen und es schob sich rechts aus dem Bild
	# (gemessen 398 px). Mit Umbruch bricht es auf zwei Zeilen, dafuer mehr Hoehe.
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.clip_text = true
	_rect(hint, 0, 1, 1, 1, 512, -58, -18, -8)
	build_root.add_child(hint)

	# Toast (kurze Meldung)
	toast_label = _lbl("", 15, Color(0.6, 1.0, 0.7))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(toast_label, 0.5, 0, 0.5, 0, -200, 66, 200, 92)
	build_root.add_child(toast_label)


func _fill_part_grid() -> void:
	if part_grid == null:
		return
	for c in part_grid.get_children():
		c.queue_free()
	part_buttons.clear()
	if _part_group == null:
		_part_group = ButtonGroup.new()
		_part_group.allow_unpress = true
	var cats := PartCatalog.categories()
	if cats.is_empty():
		return
	var cat: String = cats[clampi(_active_cat, 0, cats.size() - 1)]
	for p in PartCatalog.parts_in(cat):
		if not PartCatalog.in_palette(p.get("id", "")):
			continue   # ausgemistete Rumpf-Teile (nur im Katalog für Presets)
		part_grid.add_child(_make_part_tile(p))


# Kurzer Tab-Titel je Kategorie (lange Namen passen sonst nicht in die Reiterleiste).
func _cat_short(cat: String) -> String:
	match cat:
		PartCatalog.CAT_WING: return "Flügel"
		PartCatalog.CAT_CTRL: return "Leitwerk"
		PartCatalog.CAT_WEAPON: return "Waffen"
		_: return cat


func _on_cat_tab_changed(idx: int) -> void:
	_active_cat = idx
	_fill_part_grid()
	_refresh_tool_ui()


# Eine Bauteil-Kachel: 3D-Vorschau + Name + Masse, klickbar (exklusiv markiert).
# Kompakte Teil-Statistik (für Hover-Tooltips & Auswahl-Panel).
func _part_stats_text(p: Dictionary) -> String:
	var lines: Array = []
	if String(p.get("desc", "")) != "":
		lines.append(str(p["desc"]))
	lines.append("Masse: %d kg" % int(p.get("mass", 0.0)))
	if p.get("is_wing", false) and p.get("area", 0.0) > 0.0:
		lines.append("Fläche: %.1f m²  ·  Auftrieb ×%.2f" % [p["area"], p.get("lift", 1.0)])
	if p.get("thrust", 0.0) > 0.0:
		var thrust_type: String = "  (Rakete)" if p.get("rocket_engine", false) else ("  (Jet)" if p.get("jet", false) else "")
		lines.append("Schub: %d N%s" % [int(p["thrust"]), thrust_type])
	if p.get("gear_capacity", 0.0) > 0.0:
		lines.append("Traglast: %d kg" % int(p["gear_capacity"]))
	if String(p.get("weapon", "")) != "":
		lines.append("Waffe: %s" % String(p["weapon"]))
	lines.append("Luftwiderstand cW·A: %.2f m²" % PartCatalog.part_drag(p))
	# Strukturwert: wie viel Aufprall das Teil aushält, bevor es bei einer Kollision abreißt.
	var st: float = PartCatalog.part_strength(p)
	var stq: String = "sehr fragil" if st < 6.0 else ("fragil" if st < 10.0 else ("robust" if st < 16.0 else "sehr robust"))
	lines.append("Struktur: %d  (%s — bricht bei Aufprall ab %d m/s)" % [int(round(st)), stq, int(round(st))])
	lines.append("Preis: %d" % PartCatalog.part_cost(p))
	return "\n".join(lines)


func _make_part_tile(p: Dictionary) -> Button:
	var id: String = p["id"]
	var tile := Button.new()
	# 176 statt 156: die Vorschau ist hoeher geworden, dadurch schnitt clip_contents
	# bei zweizeiligen Namen die Massenangabe ab.
	tile.custom_minimum_size = Vector2(0, 176)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.tooltip_text = _part_stats_text(p) + "\nin den Bauraum ziehen zum Setzen"
	tile.clip_contents = true
	_style_tile(tile)
	# Drag&Drop aus dem Inventar: Drücken startet den Drag, Klick (auf gesperrt) kauft.
	tile.button_down.connect(_on_tile_down.bind(id))
	tile.pressed.connect(_on_pick_part.bind(id))

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 4
	box.offset_top = 4
	box.offset_right = -4
	box.offset_bottom = -4
	box.add_theme_constant_override("separation", 0)
	tile.add_child(box)

	var preview := _make_preview(p)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(preview)

	var nm := Label.new()
	nm.text = p["name"]
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.add_theme_font_size_override("font_size", 12)
	box.add_child(nm)

	var locked: bool = game != null and not game.is_unlocked(id)
	var mass := Label.new()
	mass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mass.add_theme_font_size_override("font_size", 11)
	if locked:
		mass.text = "Kauf %d" % PartCatalog.part_cost(p)
		mass.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
		tile.modulate = Color(0.68, 0.68, 0.74)   # gesperrt -> ausgegraut
		tile.tooltip_text = _part_stats_text(p) + "\nklicken zum Kaufen"
	else:
		mass.text = "%d kg" % int(p["mass"])
		mass.add_theme_color_override("font_color", Color(0.72, 0.8, 0.92))
	box.add_child(mass)

	part_buttons[id] = tile
	return tile


# Kleines 3D-Vorschaubild eines Bauteils in eigenem SubViewport (rendert einmal).
func _make_preview(p: Dictionary) -> SubViewportContainer:
	var svc := SubViewportContainer.new()
	svc.stretch = false
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var vp := SubViewport.new()
	vp.size = Vector2i(140, 104)
	vp.own_world_3d = true
	vp.transparent_bg = false
	# 8x statt 4x: die Kachel wird nur EINMAL gerendert (UPDATE_ONCE), die hoehere
	# Stufe kostet also nichts Laufendes und nimmt duennen Streben und
	# Propellerblaettern die Treppchen.
	vp.msaa_3d = Viewport.MSAA_8X
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	svc.add_child(vp)

	# HIMMEL statt Volltonflaeche: gibt gleichzeitig einen weichen Verlauf im Hintergrund
	# UND eine Reflexionsquelle. Vorher stand alles auf einer flachen dunklen Flaeche —
	# dunkle Teile (Bohnen-Kanzel, Metallrahmen) verschwanden darin fast, und die
	# Metall-Materialien hatten nichts zu spiegeln und wirkten wie Grauguss.
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	# Wie eine Studio-Hohlkehle: oben dunkel, unten deutlich heller. Die Kamera schaut
	# leicht nach unten, das Teil sitzt also vor dem hellen Teil — helle Teile heben sich
	# oben ab, dunkle unten. Ein gleichmaessig dunkler Grund liess schwarze Teile
	# (Bohnen-Kanzel, Metallrahmen) im Hintergrund verschwinden.
	psm.sky_top_color = Color(0.09, 0.12, 0.17)
	psm.sky_horizon_color = Color(0.17, 0.22, 0.29)
	psm.ground_horizon_color = Color(0.40, 0.46, 0.54)
	psm.ground_bottom_color = Color(0.24, 0.29, 0.36)
	psm.sky_energy_multiplier = 1.0
	psm.ground_energy_multiplier = 1.0
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	# Drei-Punkt-Licht: Fuehrung von vorn-oben-links, weiche Aufhellung von unten-rechts
	# gegen schwarze Unterseiten, und eine Kante von hinten, die das Teil vom Hintergrund
	# abloest. Ohne die Kante liefen dunkle Teile am Rand in den Hintergrund ueber.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 34, 0)
	key.light_energy = 2.1
	key.light_color = Color(1.0, 0.97, 0.92)
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(14, -128, 0)
	fill.light_energy = 0.55
	fill.light_color = Color(0.80, 0.88, 1.0)
	vp.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-16, 168, 0)
	rim.light_energy = 1.15
	rim.light_color = Color(0.72, 0.86, 1.0)
	vp.add_child(rim)

	var vis := PartCatalog.build_visual(p)
	vp.add_child(vis)

	# Kamera im 3/4-Winkel VON VORNE. Vorher zeigte die Richtung nach +Z — die Teile
	# haben ihre Nase aber bei -Z, man sah also von JEDEM Teil nur das Heck. Cockpits,
	# Nasen und Motoren waren dadurch nicht voneinander zu unterscheiden.
	var aabb := _visual_aabb(vis)
	var center: Vector3 = aabb.get_center()
	var cam := Camera3D.new()
	cam.fov = 34.0
	# BLICKHOEHE AUS DER TEILFORM: Ein Rumpf will den 3/4-Blick von schraeg vorn, eine
	# TRAGFLAECHE dagegen den Blick von OBEN — flach von der Seite sind Trapez-, Pfeil-
	# und Deltafluegel nicht zu unterscheiden (alle nur ein Splitter). "Flach" heisst:
	# Hoehe im Verhaeltnis zur groessten Grundflaechen-Kante.
	var mass: Vector3 = aabb.size
	var flach: float = mass.y / maxf(maxf(mass.x, mass.z), 0.001)
	var hoehe: float = lerpf(1.55, 0.46, clampf(flach / 0.30, 0.0, 1.0))
	var dir: Vector3 = Vector3(0.78, hoehe, -1.0).normalized()
	var dist: float = _vorschau_abstand(aabb, dir, cam.fov,
		float(vp.size.x) / float(vp.size.y))
	var pos: Vector3 = center + dir * dist
	# look_at() braucht den Baum — hier noch nicht eingehängt, daher from_position:
	cam.look_at_from_position(pos, center, Vector3.UP)
	cam.current = true
	vp.add_child(cam)
	return svc


# Abstand, bei dem das Teil die Kachel gerade ausfuellt. Gerechnet wird ueber die ACHT
# ECKEN der Box im Kamerabild, nicht ueber die Umkugel: bei einer breiten, duennen Form
# (Propellerscheibe, Tragflaeche) ist die Umkugel viel groesser als die sichtbare
# Silhouette — die Motoren sassen dadurch verloren klein in der Kachel.
func _vorschau_abstand(box: AABB, dir: Vector3, fov: float, seite: float) -> float:
	var vorwaerts: Vector3 = -dir.normalized()
	var rechts: Vector3 = Vector3.UP.cross(vorwaerts)
	if rechts.length() < 0.001:
		rechts = Vector3.RIGHT
	rechts = rechts.normalized()
	var oben: Vector3 = vorwaerts.cross(rechts).normalized()
	var ty: float = tan(deg_to_rad(fov * 0.5))          # Godot: fov ist die HOEHE
	var tx: float = ty * maxf(seite, 0.01)
	var mitte: Vector3 = box.get_center()
	var d := 0.0
	for i in 8:
		var e := Vector3(
			box.position.x + (box.size.x if (i & 1) != 0 else 0.0),
			box.position.y + (box.size.y if (i & 2) != 0 else 0.0),
			box.position.z + (box.size.z if (i & 4) != 0 else 0.0)) - mitte
		var tiefe: float = e.dot(vorwaerts)              # + = hinter der Mitte
		d = maxf(d, absf(e.dot(rechts)) / tx - tiefe)
		d = maxf(d, absf(e.dot(oben)) / ty - tiefe)
	return maxf(d, 0.2) * 1.12                           # etwas Luft zum Kachelrand


# Kombinierte AABB aller Mesh-Kinder eines Visuals (im lokalen Raum).
func _visual_aabb(vis: Node3D) -> AABB:
	var acc := {"box": AABB(), "has": false}
	_accum_aabb(vis, Transform3D.IDENTITY, acc)
	return acc["box"] if acc["has"] else AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)


func _accum_aabb(node: Node, xf: Transform3D, acc: Dictionary) -> void:
	var t := xf
	if node is Node3D:
		t = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var b: AABB = t * (node as MeshInstance3D).mesh.get_aabb()
		if acc["has"]:
			acc["box"] = (acc["box"] as AABB).merge(b)
		else:
			acc["box"] = b
			acc["has"] = true
	for ch in node.get_children():
		_accum_aabb(ch, t, acc)


func _style_tile(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.13, 0.19, 0.9)
	normal.set_corner_radius_all(8)
	normal.set_border_width_all(1)
	normal.border_color = Color(1, 1, 1, 0.08)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(0.14, 0.20, 0.30, 0.96)
	hover.border_color = Color(0.45, 0.72, 1.0, 0.55)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(0.12, 0.26, 0.18, 0.96)
	pressed.set_border_width_all(2)
	pressed.border_color = Color(0.4, 1.0, 0.55)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", pressed)


# Klick auf eine Kachel: nur fürs KAUFEN gesperrter Teile. Freigeschaltete Teile werden
# per Drag&Drop gesetzt (siehe _on_tile_down) — ein reiner Klick tut nichts.
func _on_pick_part(id: String) -> void:
	if game != null and not game.is_unlocked(id):
		var p := PartCatalog.get_part(id)
		var cost := PartCatalog.part_cost(p)
		if game.buy_part(id, cost):
			_toast("Gekauft: %s  (−%d)" % [p.get("name", id), cost])
			_rebuild_palette()
		else:
			_toast("Zu teuer: %s kostet %d (du hast %d)" % [p.get("name", id), cost, game.money])


# Drücken auf eine Kachel startet das Drag&Drop aus dem Inventar (nur freigeschaltete Teile).
func _on_tile_down(id: String) -> void:
	if game != null and not game.is_unlocked(id):
		return   # gesperrt -> nur Kaufen per Klick (_on_pick_part)
	build_ctrl.begin_drag_from_palette(id)
	_refresh_tool_ui()


func _on_move_tool() -> void:
	# Abriss/Lackieren ablegen -> vorhandene Teile packen & ziehen / Liste droppen.
	build_ctrl.clear_tools()
	_refresh_tool_ui()


# --- Kontext-Panel fürs ausgewählte Teil ----------------------------------
func _make_taper_row(label_text: String, fn: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var lbl := _lbl(label_text, 12)
	lbl.custom_minimum_size = Vector2(78, 0)
	row.add_child(lbl)
	var minus := Button.new()
	minus.text = " schmaler "
	minus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minus.pressed.connect(fn.bind(0.85))
	row.add_child(minus)
	var plus := Button.new()
	plus.text = " breiter "
	plus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plus.pressed.connect(fn.bind(1.0 / 0.85))
	row.add_child(plus)
	return row


func _build_selection_panel() -> void:
	sel_panel = _panel(Color(0, 0, 0, 0.55))
	_rect(sel_panel, 1, 0, 1, 0, -290, 200, -10, 624)
	build_root.add_child(sel_panel)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_top = 8
	v.offset_right = -8
	v.offset_bottom = -8
	v.add_theme_constant_override("separation", 4)
	sel_panel.add_child(v)
	sel_title = _lbl("Ausgewählt", 15, Color(0.55, 1.0, 0.7))
	v.add_child(sel_title)
	sel_scale_label = _lbl("", 12, Color(0.8, 0.85, 0.95))
	v.add_child(sel_scale_label)
	# --- Modus-Umschaltung (Blender-artig: Bewegen/Drehen/Skalieren, Tasten G/R/S) ---
	v.add_child(_lbl("Werkzeug (G / R / S · Enden: E / T):", 11, Color(0.82, 0.82, 0.88)))
	var mrow := HBoxContainer.new()
	v.add_child(mrow)
	sel_mode_btns.clear()
	# Die beiden ENDEN-Werkzeuge stehen zusammen in einer eigenen Zeile darunter: sie
	# gehoeren inhaltlich zusammen (dasselbe Rumpfende, einmal formen, einmal versetzen)
	# und brauchen laengere Beschriftungen, als in eine Fuenferzeile passen.
	var modes := [["Bewegen", 0], ["Drehen", 1], ["Skalieren", 2]]
	for md in modes:
		var mb := Button.new()
		mb.text = md[0]
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.add_theme_font_size_override("font_size", 11)
		mb.pressed.connect(build_ctrl.set_gizmo_mode.bind(md[1]))
		mrow.add_child(mb)
		sel_mode_btns.append(mb)
	var erow := HBoxContainer.new()
	v.add_child(erow)
	for md in [["Enden skalieren", 3], ["Enden verschieben", 4]]:
		var eb := Button.new()
		eb.text = md[0]
		eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eb.add_theme_font_size_override("font_size", 11)
		eb.pressed.connect(build_ctrl.set_gizmo_mode.bind(md[1]))
		erow.add_child(eb)
		sel_mode_btns.append(eb)
	v.add_child(_lbl("Pfeile/Würfel im 3D-Raum ziehen · Drehen: Teil ziehen · 90°-Schritte unten:", 10, Color(0.7, 0.74, 0.82)))
	v.add_child(_lbl("Enden skalieren (E): 4 Würfel — vorne/hinten je X (seitlich) + Y (oben), auswärts ziehen = dicker.", 10, Color(0.55, 0.72, 0.95)))
	v.add_child(_lbl("Enden verschieben (T): je Ende 2 Zylinder — links/rechts und hoch/runter.", 10, Color(0.55, 0.72, 0.95)))
	var axis_names := ["Breite", "Höhe", "Länge"]
	for i in 3:
		var row := HBoxContainer.new()
		v.add_child(row)
		var lbl := _lbl(axis_names[i], 12)
		lbl.custom_minimum_size = Vector2(78, 0)
		row.add_child(lbl)
		var minus := Button.new()
		minus.text = "  −  "
		minus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		minus.pressed.connect(build_ctrl.nudge_scale.bind(i, 1.0 / 1.18))
		row.add_child(minus)
		var plus := Button.new()
		plus.text = "  +  "
		plus.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		plus.pressed.connect(build_ctrl.nudge_scale.bind(i, 1.18))
		row.add_child(plus)
	var row2 := HBoxContainer.new()
	v.add_child(row2)
	var rot := Button.new()
	rot.text = "Drehen"
	rot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rot.pressed.connect(build_ctrl.rotate_selected)
	row2.add_child(rot)
	var tilt := Button.new()
	tilt.text = "⤡ Kippen"
	tilt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tilt.pressed.connect(build_ctrl.tilt_selected)
	row2.add_child(tilt)
	var rst := Button.new()
	rst.text = "⟲ Größe zurücksetzen"
	rst.pressed.connect(build_ctrl.reset_selected_scale)
	v.add_child(rst)
	# --- Verjüngung: Rumpf-Enden breiter/schmaler (vorne/hinten einzeln) ---
	sel_taper_row = VBoxContainer.new()
	sel_taper_row.add_theme_constant_override("separation", 2)
	v.add_child(sel_taper_row)
	sel_taper_label = _lbl("Verjüngung", 12, Color(0.75, 0.9, 1.0))
	sel_taper_row.add_child(sel_taper_label)
	sel_taper_front_row = _make_taper_row("Vorne", build_ctrl.nudge_taper_front)
	sel_taper_row.add_child(sel_taper_front_row)
	sel_taper_row.add_child(_make_taper_row("Hinten", build_ctrl.nudge_taper))
	sel_reverse_cb = CheckBox.new()
	sel_reverse_cb.text = "Schub umkehren"
	sel_reverse_cb.tooltip_text = "Propeller schiebt in die ENTGEGENGESETZTE Richtung (z. B. als Bremse / Rückwärts)."
	sel_reverse_cb.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	sel_reverse_cb.toggled.connect(build_ctrl.set_reverse_thrust)
	v.add_child(sel_reverse_cb)
	var dup := Button.new()
	dup.text = "⧉  Duplizieren  (Strg+D)"
	dup.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	dup.pressed.connect(build_ctrl.duplicate_selected)
	v.add_child(dup)
	sel_delete_btn = Button.new()
	sel_delete_btn.text = "Löschen"
	sel_delete_btn.add_theme_color_override("font_color", Color(1, 0.6, 0.55))
	sel_delete_btn.pressed.connect(build_ctrl.delete_selected)
	v.add_child(sel_delete_btn)
	sel_panel.visible = false


func _on_selection_changed(info: Dictionary) -> void:
	if sel_panel == null:
		return
	if info.is_empty():
		sel_panel.visible = false
		return
	sel_panel.visible = true
	sel_title.text = "%s" % info.get("name", "Teil")
	# Stats des ausgewählten Teils als Tooltip am Titel (Hover zeigt Masse/Auftrieb/Schub/…)
	var pid: String = String(info.get("id", ""))
	if pid != "" and PartCatalog.has(pid):
		sel_title.tooltip_text = _part_stats_text(PartCatalog.get_part(pid))
	var s: Vector3 = info.get("scale", Vector3.ONE)
	sel_scale_label.text = "Größe: %.2f × %.2f × %.2f   (Shift = uniform · Strg = X+Y)" % [s.x, s.y, s.z]
	var is_root: bool = info.get("is_root", false)
	sel_delete_btn.disabled = is_root
	sel_delete_btn.tooltip_text = "Das Cockpit ist die Basis und kann nicht gelöscht werden." if is_root else ""
	# Verjüngungs-Regler: »Hinten« für taperable, zusätzlich »Vorne« für biends (F-22-Rumpf)
	var taperable: bool = info.get("taperable", false)
	var biends: bool = info.get("biends", false)
	if sel_taper_row:
		sel_taper_row.visible = taperable or biends
		sel_taper_front_row.visible = biends
		var tb := int(round(float(info.get("taper", 1.0)) * 100.0))
		var tf := int(round(float(info.get("taper_front", 1.0)) * 100.0))
		sel_taper_label.text = ("Verjüngung — vorne %d %% · hinten %d %%" % [tf, tb]) if biends else ("Verjüngung hinten: %d %%" % tb)
	# aktiven Werkzeug-Modus hervorheben; »Enden« nur für Rumpfsegmente (biends) zeigen
	var gm: int = info.get("gizmo", 0)
	for i in sel_mode_btns.size():
		sel_mode_btns[i].modulate = Color(0.5, 1.0, 0.6) if i == gm else Color(1, 1, 1)
	# Beide ENDEN-Werkzeuge nur bei Rumpfsegmenten mit zwei formbaren Enden zeigen
	if sel_mode_btns.size() >= 5:
		sel_mode_btns[3].visible = biends
		sel_mode_btns[4].visible = biends
	# »Schub umkehren« nur bei Prop-Triebwerken zeigen; Haken ohne Signal setzen
	if sel_reverse_cb:
		sel_reverse_cb.visible = info.get("is_prop", false)
		sel_reverse_cb.set_pressed_no_signal(info.get("thrust_reverse", false))


func _on_erase_tool() -> void:
	build_ctrl.set_erase_mode(true)
	_refresh_tool_ui()


# Ein Palettenfeld. Der Rahmen macht helle Farben auf dunklem Grund ueberhaupt
# erst als Flaeche erkennbar.
func _farb_knopf(c: Color) -> Button:
	var sw := Button.new()
	sw.custom_minimum_size = Vector2(34, 28)
	sw.tooltip_text = "#" + c.to_html(false)
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.18)
	for zustand in ["normal", "hover", "pressed", "focus"]:
		sw.add_theme_stylebox_override(zustand, sb)
	sw.pressed.connect(_on_paint_color.bind(c))
	return sw


func _on_pipette() -> void:
	var an: bool = pipette_btn.button_pressed
	build_ctrl.set_pick_mode(an)
	_refresh_tool_ui()
	if an:
		_toast("Pipette: Teil anklicken, um dessen Farbe zu übernehmen")


# Die Pipette hat eine Farbe geholt -> Vorschau, Farbrad und Knopf nachziehen.
func _on_farbe_gepickt(c: Color) -> void:
	if pipette_btn != null:
		pipette_btn.button_pressed = false
	_zeige_lackfarbe(c)
	_refresh_tool_ui()
	_toast("Farbe übernommen: #" + c.to_html(false))


func _zeige_lackfarbe(c: Color) -> void:
	if paint_preview != null:
		paint_preview.color = c
	if paint_picker != null and not paint_picker.color.is_equal_approx(c):
		paint_picker.color = c


func _on_paint_color(c: Color) -> void:
	_zeige_lackfarbe(c)
	if pipette_btn != null:
		pipette_btn.button_pressed = false
	build_ctrl.set_paint_color(c)
	_refresh_tool_ui()


func _on_undo() -> void:
	build_ctrl.undo()


func _on_redo() -> void:
	build_ctrl.redo()


func _on_reset_view() -> void:
	build_ctrl.reset_camera()


func _on_debug_boxes(on: bool) -> void:
	build_ctrl.set_debug_boxes(on)
	if on:
		_toast("Debug: cyan = Snap-Box (Andocken rechnet damit), gelb = echte Geometrie")


func _on_drag_view(on: bool) -> void:
	build_ctrl.set_wind_tunnel(on)
	if wind_legend != null:
		wind_legend.visible = on
	if on:
		var worst: String = build_ctrl.wind_worst
		var tip := "nur angeströmte Teile gefärbt (grau = Windschatten)"
		if worst != "":
			tip = "rot = größter Widerstand: %s (grau = Windschatten)" % worst
		_toast("Windkanal AN — " + tip)
	else:
		_toast("Windkanal aus")


func _refresh_tool_ui() -> void:
	var sel := "" if (build_ctrl.erase_mode or build_ctrl.paint_mode or build_ctrl.pick_mode) 		else build_ctrl.brush_id
	for pid in part_buttons:
		part_buttons[pid].set_pressed_no_signal(pid == sel)
	if pipette_btn != null and pipette_btn.button_pressed != build_ctrl.pick_mode:
		pipette_btn.set_pressed_no_signal(build_ctrl.pick_mode)
	if build_ctrl.erase_mode:
		tool_label.text = "Werkzeug: Abriss – Teil anklicken zum Löschen"
	elif build_ctrl.pick_mode:
		tool_label.text = "Pipette – Teil anklicken, um dessen Farbe zu übernehmen"
	elif build_ctrl.paint_mode:
		tool_label.text = "Werkzeug: Lackieren (#%s) – Teil anklicken zum Umfärben" 			% build_ctrl.paint_color.to_html(false)
	elif build_ctrl.brush_id == "":
		tool_label.text = "Teil aus Liste ziehen = setzen · Teil anklicken = bearbeiten (G/R/S) · leer = drehen"
	else:
		var p := PartCatalog.get_part(build_ctrl.brush_id)
		tool_label.text = "Werkzeug: %s – ziehen & loslassen zum Setzen" % p.get("name", build_ctrl.brush_id)


# Praesentationstafel am RECHTEN Bildrand: grosser Name, darunter die wenigen
# Kennwerte, die beim Ansehen wirklich interessieren. Bewusst ohne Kasten und ohne
# Rahmen — die Vorgabe verlangt weniger technische Kaesten und mehr freie Flaeche.
# Das Flugzeug sitzt darum links im Bild (siehe BuildController.praesent_versatz).
func _build_praesentation_panel() -> void:
	var box := VBoxContainer.new()
	box.name = "Praesentation"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 6)
	# Rechts oben verankert, mit fester Breite. Bei schmalen Fenstern schrumpft die
	# Breite mit, damit die Tafel nicht ins Bauteil-Panel links hineinlaeuft.
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.anchor_left = 1.0
	box.offset_left = -420.0
	box.offset_right = -28.0
	box.offset_top = 26.0
	build_root.add_child(box)

	praesent_titel = Label.new()
	praesent_titel.text = _slot_name.to_upper()
	praesent_titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	praesent_titel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	praesent_titel.add_theme_font_override("font", F_BOLD)
	praesent_titel.add_theme_font_size_override("font_size", 40)
	praesent_titel.add_theme_color_override("font_color", ShowroomStage.TEXT)
	# Weicher dunkler Schatten: haelt den hellen Text auch ueber hellen Flaechen lesbar.
	praesent_titel.add_theme_color_override("font_shadow_color", Color(0, 0.04, 0.05, 0.75))
	praesent_titel.add_theme_constant_override("shadow_offset_x", 0)
	praesent_titel.add_theme_constant_override("shadow_offset_y", 3)
	praesent_titel.add_theme_constant_override("shadow_outline_size", 6)
	box.add_child(praesent_titel)

	# Duenne orange Linie als Trenner — die einzige warme Farbe in der Tafel.
	var linie := ColorRect.new()
	linie.color = ShowroomStage.AKZENT
	linie.custom_minimum_size = Vector2(0, 2)
	linie.size_flags_horizontal = Control.SIZE_SHRINK_END
	linie.custom_minimum_size.x = 96
	box.add_child(linie)

	praesent_werte = Label.new()
	praesent_werte.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	praesent_werte.add_theme_font_size_override("font_size", 15)
	praesent_werte.add_theme_color_override("font_color", ShowroomStage.AKZENT_KALT)
	praesent_werte.add_theme_color_override("font_shadow_color", Color(0, 0.04, 0.05, 0.7))
	praesent_werte.add_theme_constant_override("shadow_offset_y", 2)
	praesent_werte.add_theme_constant_override("shadow_outline_size", 4)
	box.add_child(praesent_werte)


func _aktualisiere_praesentation(stats: Dictionary) -> void:
	if praesent_titel != null:
		praesent_titel.text = _slot_name.to_upper()
	if praesent_werte != null:
		praesent_werte.text = "%d Teile   ·   %d kg\n%.1f m² Fläche   ·   %d N Schub" % [
			int(stats.get("parts", 0)), int(stats.get("mass", 0.0)),
			float(stats.get("area", 0.0)), int(stats.get("thrust", 0.0))]


func _build_flight_ui() -> void:
	# HUD oben links
	var hp := _panel(Color(0, 0, 0, 0.45))
	_rect(hp, 0, 0, 0, 0, 12, 12, 320, 290)
	flight_root.add_child(hp)
	hp.visible = false   # ersetzt durch das FLUG-STATUS-Panel im FlightHud (Mockup-Design)
	var hv := VBoxContainer.new()
	hp.add_child(hv)
	hv.add_child(_lbl("FLUG-HUD", 16, Color(0.6, 0.85, 1.0)))
	fly_money_label = _lbl("", 14, Color(1.0, 0.86, 0.3))
	hv.add_child(fly_money_label)
	hud_label = _lbl("", 15)
	hv.add_child(hud_label)

	# (Stall-Warnung zeichnet das PFD selbst: FlightHud._draw_stall — pulsierender
	#  Rahmen + Banner. Das frühere stall_label hier war eine Doppelung.)

	# Survival-HUD oben rechts (Welle / Abschüsse / Combo / Score)
	survival_label = _lbl("", 15, Color(0.7, 1.0, 0.8))
	survival_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rect(survival_label, 1, 0, 1, 0, -300, 62, -14, 138)
	survival_label.visible = false
	flight_root.add_child(survival_label)

	# Lande-/Schadensmeldung mitte
	land_label = _lbl("", 22, Color(1, 0.85, 0.3))
	land_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(land_label, 0.5, 0, 0.5, 0, -320, 124, 320, 158)
	flight_root.add_child(land_label)

	# Zurück-Button — oben RECHTS (mittig kollidierte er mit dem HUD-Kompass), HUD-Panel-Optik
	var back_btn := Button.new()
	back_btn.text = "HANGAR  (Tab)"
	back_btn.add_theme_font_override("font", F_SEMI)
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.add_theme_color_override("font_color", Color(0.86, 0.90, 0.96))
	back_btn.add_theme_color_override("font_hover_color", Color(0.36, 0.78, 0.91))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.075, 0.095, 0.135, 0.88)
	bsb.set_corner_radius_all(9)
	bsb.set_border_width_all(1)
	bsb.border_color = Color(1, 1, 1, 0.10)
	bsb.set_content_margin_all(10)
	back_btn.add_theme_stylebox_override("normal", bsb)
	var bsh: StyleBoxFlat = bsb.duplicate()
	bsh.border_color = Color(0.36, 0.78, 0.91, 0.55)
	back_btn.add_theme_stylebox_override("hover", bsh)
	back_btn.add_theme_stylebox_override("pressed", bsh)
	_rect(back_btn, 1, 0, 1, 0, -196, 14, -16, 52)
	back_btn.pressed.connect(_on_hangar_pressed)
	flight_root.add_child(back_btn)

	# Primary-Flight-Display (Custom-Drawing): Kompass oben, Speed/Höhe-Boxen, großer Zielkreis.
	flight_hud = FlightHud.new()
	flight_root.add_child(flight_hud)

	# (Hinweisleiste unten auf Wunsch entfernt — Steuerung steht im README.)


# ===========================================================================
# Signal-Handler
# ===========================================================================
func _on_design_changed(stats: Dictionary) -> void:
	_aktualisiere_praesentation(stats)
	_design_dirty = true   # -> Autosave-Debounce in _process (seit dem Slot-Menü fehlte JEDES Autosave)
	if flight_check == null:
		return
	# Umlaut-fähige Schrift vom echten Label übernehmen (generisches Control liefert sie nicht).
	if stats_label != null:
		flight_check.set_font(stats_label.get_theme_font("font"))
	# Grafische Flug-Info (Balance/Stabilität/Kennwerte + Verdict) aktualisieren
	var v := _flight_verdict(stats)
	flight_check.set_data(stats, v["text"], v["color"])
	# Detail-Zahlen unter der Grafik
	var gear := "kein Fahrwerk"
	if stats.get("has_gear", false):
		gear = "%d/%d kg%s" % [int(stats["mass"]), int(stats["gear_cap"]),
			("  ÜBERLASTET!" if stats.get("gear_overload", false) else "")]
	var drag_line := "Luftwiderstand cW·A: %.2f m²" % stats.get("drag_area", 0.0)
	if build_ctrl != null and build_ctrl.wind_tunnel and not build_ctrl.wind_report.is_empty():
		# Windkanal-Analyse: exponierter Gesamtwiderstand + größte Verursacher (Verdeckung eingerechnet).
		var tot: float = maxf(build_ctrl.wind_total, 0.001)
		drag_line += "\nexponiert (Verdeckung): %.2f m²" % build_ctrl.wind_total
		var rank := 0
		for e in build_ctrl.wind_report:
			if rank >= 3 or float(e["drag"]) < 0.01:
				break
			rank += 1
			drag_line += "\n  %d. %s — %.2f m² (%d %%)" % [
				rank, e["name"], e["drag"], int(round(float(e["drag"]) / tot * 100.0))]
	if stats_label:
		stats_label.text = "Teile: %d   ·   Masse: %d kg\nFlügelfläche: %.1f m²   ·   Schub: %d N\nFahrwerk-Last: %s\n%s" % [
			int(stats["parts"]), int(stats["mass"]), stats["area"],
			int(stats["thrust"]), gear, drag_line]


# "Fliegt's?"-Verdict aus Stabilität, Schub/Gewicht, Flügeln und Fahrwerk ableiten.
# Gibt {text, color} zurück (vom grafischen Flug-Check verwendet).
func _flight_verdict(stats: Dictionary) -> Dictionary:
	var red := Color(1, 0.45, 0.4)
	if build_ctrl != null and not build_ctrl.has_root():
		var hint := "Leerer Bauraum" if int(stats.get("parts", 0)) == 0 else "Keine Wurzel"
		return {"text": "%s — zieh ein Cockpit rein (kommt in die Mitte) und starte deinen Bauplan." % hint, "color": red}
	if build_ctrl != null and build_ctrl.has_floating():
		return {"text": "%d Teil(e) hängen frei (rot markiert) — verbinden zum Starten" % build_ctrl.floating_count(), "color": red}
	var has_wings: bool = stats.get("has_wings", false)
	var tw: float = stats.get("tw", 0.0)                       # VORWÄRTS-Schub / Gewicht
	var up_tw: float = stats.get("up_tw", 0.0)                 # Senkrechtschub / Gewicht (VTOL)
	var offset: float = stats.get("thrust_offset", 0.0)        # Schub-Hebel (m) um den COM
	var inst_tw: float = float(stats.get("thrust", 0.0)) / max(float(stats.get("mass", 0.0)) * 9.81, 0.001)
	var d: float = (stats["col"].z - stats["com"].z) if stats.get("col_valid", false) else 0.0
	if not has_wings:
		return {"text": "Fliegt nicht — keine Tragflächen dran", "color": red}
	if stats.get("gear_overload", false):
		return {"text": "Fahrwerk überlastet — Reifen reißen beim Start ab", "color": red}
	if offset > 1.0:
		return {"text": "Schub stark außermittig — kippt/dreht beim Gasgeben", "color": red}
	if tw < 0.12 and up_tw < 0.9:
		if inst_tw >= 0.30:   # es GIBT Schub, er zeigt nur nicht nach vorne (gedreht/Reverse)
			return {"text": "Schub zeigt nicht nach vorne — Triebwerke nach vorne richten", "color": red}
		return {"text": "Zu wenig Schub zum Abheben", "color": red}
	if stats.get("col_valid", false) and d < -0.5:
		return {"text": "Stark kopflastig — überschlägt sich", "color": red}
	var warns: Array = []
	if up_tw >= 0.9 and tw < 0.5:
		warns.append("Senkrechtschub-Stil — braucht Vorwärtsschub")
	elif tw < 0.30:
		warns.append("wenig Vorwärtsschub")
	if offset > 0.15:
		warns.append("Schub nicht durch den Schwerpunkt")
	if stats.get("col_valid", false) and d < 0.15:
		warns.append("grenzwertig stabil (Leitwerk weiter nach hinten)")
	if not stats.get("has_gear", false):
		warns.append("kein Fahrwerk (Bauchlandung)")
	if has_wings and stats.get("max_g", 9.0) < 3.0:
		warns.append("Flügel kaum belastbar")
	if warns.is_empty():
		return {"text": "Flugbereit!", "color": Color(0.45, 1.0, 0.5)}
	return {"text": ", ".join(warns), "color": Color(1.0, 0.85, 0.3)}


func _on_hud_changed(d: Dictionary) -> void:
	if hud_label == null:
		return
	var assist_txt: String = "AN" if d.get("assist", true) else "AUS (Pro)"
	var inv_txt: String = "INVERTIERT " if d.get("inverted", false) else "normal"
	var mf: bool = d.get("mouse_fly", false)
	var arc: bool = d.get("arcade", false)
	var mf_txt: String = ("AN — ARCADE " if arc else "AN (Cursor lenkt)") if mf else "AUS (Umschauen)"
	var thr_pct := int(round(d["throttle"] * 100.0))
	var thr_txt: String
	if thr_pct < 0:
		thr_txt = "Bremse %d%%" % absi(thr_pct)
	elif thr_pct > 100:
		thr_txt = "NACHBRENNER %d%%" % thr_pct
	else:
		thr_txt = "Schub %d%%" % thr_pct
	var nav := _nearest_airfield(d.get("pos", Vector3.ZERO))
	# Speed/Höhe/Kurs/Steig zeigt jetzt das PFD; hier nur noch Systeme/Status.
	hud_label.text = "%s\nAnstellw.: %d°\nG-Kraft:  %.1f g\nFlügel: %s\nFahrwerk (G): %s\nKlappen (F): %s\nSteuerung (I): %s\nAssist (T): %s\nMaus-Flug (N): %s\n%s" % [
		thr_txt, int(d["aoa"]), d.get("gforce", 1.0),
		d.get("wings", "ok"), d.get("gear", "—"), d.get("flaps", "AUS"), inv_txt, assist_txt, mf_txt, nav]
	var ammo_txt: String = d.get("ammo", "")
	if ammo_txt != "":
		hud_label.text += "\nMunition: " + ammo_txt
	# Primary-Flight-Display füttern (Kompass, Speed/Höhe-Boxen, Zielkreis)
	if flight_hud:
		flight_hud.mini_player = flight_ctrl.aircraft
		flight_hud.gear_text = str(d.get("gear", "—"))
		flight_hud.flaps_text = str(d.get("flaps", "AUS"))
		flight_hud.steer_text = inv_txt
		flight_hud.assist_text = assist_txt
		flight_hud.mousefly_text = mf_txt
		flight_hud.wings_text = str(d.get("wings", "ok"))
		flight_hud.nav_text = nav
		flight_hud.ammo_text = str(d.get("ammo", ""))
		flight_hud.weapon_groups = d.get("wgroups", [])
		flight_hud.weapon_sel = int(d.get("wsel", -1))
		flight_hud.badge_text = "SANDBOX" if game.is_sandbox() else fly_money_label.text
		flight_hud.heading = d.get("heading", 0.0)
		flight_hud.speed_kmh = d.get("kmh", 0.0)
		flight_hud.speed_ms = d.get("speed", 0.0)
		flight_hud.altitude = d.get("alt", 0.0)
		flight_hud.climb = d.get("climb", 0.0)
		flight_hud.throttle = d.get("throttle", 0.0)
		flight_hud.gforce = d.get("gforce", 1.0)
		flight_hud.stall = d.get("stall", false)
		flight_hud.aoa = d.get("aoa", 0.0)
		# Modus-Badge im PFD: nur aktive Sondermodi (lenken stark um -> sichtbar machen)
		var modes: Array = []
		var zf: float = d.get("zoom", 0.0)
		if zf > 1.02:
			modes.append("ZOOM %.1f×" % zf)
		if mf:
			modes.append("ARCADE" if arc else "MAUS-FLUG")
		if not bool(d.get("g_protect", true)):
			modes.append("G-SCHUTZ AUS")
		if d.get("inverted", false):
			modes.append("INVERS")
		flight_hud.mode_text = "     ".join(modes)
		flight_hud.mouse_fly = mf
		flight_hud.lock_pos = d.get("lock", Vector2.ZERO)
		flight_hud.lock_on = bool(d.get("lock_active", false)) and bool(d.get("lock_vis", false))
		flight_hud.lock_stufe = int(d.get("lock_stufe", 0))
		flight_hud.lock_dist = float(d.get("lock_dist", 0.0))
		flight_hud.lock_name = String(d.get("lock_name", ""))
		flight_hud.lock_sucher = String(d.get("lock_sucher", ""))
		flight_hud.flares = int(d.get("flares", 0))
		flight_hud.chaff = int(d.get("chaff", 0))
		flight_hud.warn_aktiv = bool(d.get("warn_aktiv", false))
		flight_hud.warn_winkel = float(d.get("warn_winkel", 0.0))
		flight_hud.warn_zeit = float(d.get("warn_zeit", 0.0))
		flight_hud.lenk_meldung = String(d.get("lenk_meldung", ""))
		flight_hud.aim_pos = d.get("aim", Vector2.ZERO)
		flight_hud.aim_vis = mf and bool(d.get("aim_vis", true))
		flight_hud.nose_pos = d.get("nose", Vector2.ZERO)
		flight_hud.nose_vis = mf and bool(d.get("nose_vis", true))
		flight_hud.gun_pos = d.get("gun", Vector2.ZERO)
		flight_hud.gun_vis = bool(d.get("gun_vis", false))
		# G-Schutz-Toggle (H) erkennen -> Toast + persistieren
		var gp := bool(d.get("g_protect", true))
		if gp != game.g_protect:
			game.g_protect = gp
			game.save()
			_toast("G-Schutz AN — Flügel reißen nicht ab" if gp else "G-Schutz AUS — volle Physik, Flügel können brechen!")
	if land_label:
		var lm: String = d.get("land_msg", "")
		land_label.text = lm
		var low := lm.to_lower()
		if "zerschell" in low or "abgerissen" in low or "überlast" in low:
			land_label.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
		elif "harte landung" in low:
			land_label.add_theme_color_override("font_color", Color(1, 0.75, 0.25))
		else:
			land_label.add_theme_color_override("font_color", Color(0.5, 1, 0.6))


## Weltposition des Talflugplatzes — aus derselben Achse gerechnet wie die beiden Ketten,
## damit Platz und Tal nicht auseinanderlaufen koennen.
## Bahnkurs des Talflugplatzes: laengs der Talachse, in Richtung AUSGANG.
## Die Bahn laeuft im lokalen Z des Platzes, ihre Weltrichtung ist also (sin k, cos k).
## Gesucht ist k mit (sin k, cos k) = -TAL_RICHTUNG, denn -TAL_RICHTUNG zeigt vom Platz
## zurueck zum offenen Talanfang.
func _adlerhorst_kurs() -> float:
	return atan2(-TAL_RICHTUNG.x, -TAL_RICHTUNG.y)


func _adlerhorst_pos() -> Vector3:
	var p := TAL_START + TAL_RICHTUNG * ADLERHORST_LAENGS
	return Vector3(p.x, ADLERHORST_HOEHE, p.y)


## Punkt auf der Talachse — fuer Tor und See, damit beide nicht neben dem Tal landen.
func _tal_punkt(laengs: float) -> Vector2:
	return TAL_START + TAL_RICHTUNG * laengs


## Punkt im Umfeld des BERGSEES, in dessen eigenen Polarkoordinaten: Winkel 0 zeigt
## talaufwaerts (dorthin, wo der Arm liegt), +90 Grad zur steilen Felsflanke.
## Dieselbe Basis, mit der TerrainWorld._see_umriss die Uferlinie abfragt — so lassen sich
## Zu- und Abfluss auf Buchten und Arm beziehen, ohne Weltkoordinaten abzutippen.
func _see_punkt(grad: float, abstand: float, hoehe: float) -> Vector3:
	var a := deg_to_rad(grad)
	var quer := Vector2(TAL_RICHTUNG.y, -TAL_RICHTUNG.x)
	var p := _tal_punkt(SEE_LAENGS) + (TAL_RICHTUNG * cos(a) + quer * sin(a)) * abstand
	return Vector3(p.x, hoehe, p.y)


## HALBER KAMMABSTAND an der Stelle "laengs" — die eine Stelle, an der die Keilform steht.
## Linear, weil das Referenzbild eine stetige Verjuengung zeigt und keine einzelne
## Engstelle: vorn faehrt man in ein weites Becken ein, hinter dem Flugplatz laeuft das
## Tal in den Schneegipfeln aus.
##
## WARUM LINEAR UND NICHT "VORN FLACH, HINTEN STEIL". Naheliegend waere, die Verjuengung
## dorthin zu legen, wo man fliegt (laengs 3000..9000), und den Talmund gleich breit zu
## lassen. Das geht NICHT, weil das hintere Ende eine harte Untergrenze hat: die
## Bahnflaeche von ADLERHORST ist eine Kreisscheibe mit 450 m Radius auf 90 m Hoehe, und
## die zaehlt in jeder Bodenmessung als Talboden. Unter 2 * 458 = 916 m kommt das Tal bei
## laengs 8800 also nie (siehe die Einebnungszone in _build_world). Wer hinten staerker
## zusammenzieht, macht damit nicht das Tal enger, sondern nur die Flachzone auffaelliger.
## Die Verjuengung muss deshalb ueber die GANZE Laenge gleichmaessig laufen.
##
## Gemessen mit tools/_krit_keil.gd (zusammenhaengender Talboden unter 200 m, 25-m-Raster,
## Reihe wie im Spiel — Flachzonen also drin):
##   laengs        500  3000  4250  5000  6000  7000  8000  8500  8750
##   vorige       1425  1200  1075   975   950   850   850   925  1025
##   jetzt        1675  1325  1200  1100  1025   900   900   875  1025
## Vorher lag der gesamte Abfall in den ersten 3,5 km: ueber 4000..8750 schwankte der
## Boden um 850..1075 m ohne Richtung, und der TIEFSTE Punkt des Tals war mit 1025 m die
## WEITESTE Stelle des hinteren Tals. Jetzt faellt er von 1200 m hinter dem Tor auf 875 m
## am Talschluss durch — 27 Prozent ueber die Strecke, auf der man den Endanflug fliegt.
## Uebrig bleibt die Linse von ADLERHORST bei 8750 m (1025 m): sie ist die oben genannte
## Untergrenze plus 88 m Boeschung und laesst sich nicht wegrechnen, nur kuerzer machen.
## NICHT AN 5000 UND 8800 IN DER REIHE "GEBAUT" MESSEN, wenn man die KETTEN pruefen will:
## dort liegt die Flachzone von ADLERHORST, die den Boden auf ihren eigenen Radius
## aufweitet. Dafuer hat tools/_tal_keil.gd die Reihe GEWACHSEN.
func _tal_halbbreite(laengs: float) -> float:
	return lerpf(TAL_BREITE, TAL_BREITE_HINTEN, clampf(laengs / TAL_KEIL_LAENGE, 0.0, 1.0))


## DAS HOCHTAL im Nordwesten — zwei Ketten mit einem KEILFOERMIGEN Tal dazwischen, und im
## Tal der Flugplatz ADLERHORST.
##
## FORM: die Massive selbst koennen nur ANHEBEN (max in height_at), ein Tal laesst sich
## also nicht graben. Es entsteht als der Raum, den man FREILAESST — zwei Kaemme im
## Abstand 2 * _tal_halbbreite(laengs), dazwischen bleibt das Grundgelaende stehen. Der
## Abstand nimmt nach hinten ab (2480 -> 2110 halbseitig ueber 9200 m), das Tal verjuengt
## sich also zur Tiefe hin. Am hinteren Ende schliesst eine Querkette das Tal ab, sodass
## es eine Sackgasse ist.
##
## DER KEIL STECKT ABER NUR ZUR HAELFTE IN DIESEM ABSTAND. Was man aus dem Cockpit sieht,
## ist nicht der Talboden, sondern die Hoehenlinie auf Augenhoehe, und die liegt bei
## r * (1 - h / peak) vom Massivmittelpunkt — sie haengt also genauso an der GIPFELHOEHE
## wie an der Sollinie. Beide Hebel muessen in dieselbe Richtung zeigen, sonst hebt der
## eine den anderen auf; die Begruendung und die Messwerte stehen unten bei "kaemme".
##
## ABSTAND DER MASSIVE UNTEREINANDER: rund die HAELFTE ihres Radius, nicht ein ganzer.
## Die Kegelform ist cone = 1 - smoothstep(0, r, d), und smoothstep faellt in der Mitte
## steil ab: bei Abstand = r beruehren sich zwei Massive nur an der Basis und man bekommt
## eine Perlenkette einzelner Kuppeln. Bei r/2 liegt der Sattel dazwischen noch bei rund
## 93 Prozent der Gipfelhoehe — daraus wird ein durchgehender Kamm.
##
## HOEHEN bis 1250 m. Der bisher hoechste Punkt der Karte war der Vulkan mit 230 m; die
## erste Fassung dieser Kette ging bis 650 m. Oberhalb von 230 m waechst nichts mehr
## (FLORA_MAX_H), der Schnee blendet ueber 240 Hoehenmeter ein — die Kaemme sind damit
## kahler Fels mit weissen Gipfeln, das Tal darunter gruen. Die 1250 m stehen NICHT
## irgendwo in der Kette, sondern am Talschluss: beide Ketten steigen monoton dorthin.
## CHARAKTER FUER DIE MASSIVE DES KERNLANDS.
##
## Die Berge um den Spawn und die sechs Canyonflanken standen als nackte {pos, r, peak}
## in der Liste: runder Fussabdruck, fuer alle dieselbe Gratfrequenz, keine Schaerfe. Im
## Abnahmebild (tools/_terrain_render.gd, Shot pan2) waren sie flache braune Pfannkuchen
## ohne Relief — dieselbe Ausgangslage, in der der Vulkan vor seinem Umbau stand.
##
## Die Schluessel dafuer gibt es laengst; das Hochgebirge nutzt sie seit seinem eigenen
## Umbau. Hier bekommen sie die uebrigen Massive, GEWUERFELT AUS DER POSITION und nicht
## aus dem Listenindex: so bleibt die Welt bei jedem Start dieselbe, und ein spaeter
## eingefuegter Berg verschiebt nicht den Charakter aller anderen.
##
## UEBERSPRUNGEN WIRD DREIERLEI, jedes aus einem eigenen Grund:
##   * alles mit "type" (Vulkan, Inseln) — die haben ihre eigene Formgebung,
##   * alles, was schon "schaerfe" mitbringt (die beiden Ketten des Hochgebirges),
##   * alles mit "glatt" — das traegt heute nur der Burgberg, und die Begruendung steht
##     bei ihm in der Liste.
##
## DIE WERTE SIND KLEINER ALS IM HOCHGEBIRGE, und das ist kein Geschmack:
##   * nz_frq ist eine WELTfrequenz, keine Zahl von Rippen. Ein 750-m-Berg ueberdeckt ein
##     Neuntel der Flaeche eines 2200-m-Kegels und traegt bei gleicher Frequenz entsprechend
##     weniger Perioden. Damit die Rippen gleich fein AUSSEHEN, muss die Zahl hier groesser
##     sein — 2.6 bis 6.5 gegen 1.3 bis 4.2 dort.
##   * schaerfe bleibt unter 0.78. Diese Berge sind 110 bis 205 m hoch; eine Nadel steht im
##     Tiefland falsch, gebraucht wird eine Kuppe mit Kanten.
##   * dehnung bleibt zwischen 0.86 und 1.18. SECHS DIESER MASSIVE SIND DIE WAENDE DES
##     CANYONS. Ein stark gestreckter Fussabdruck kann eine Wand seitlich wegziehen, und
##     weil der Flussschnitt in height_at DANACH laeuft, stuende dort ein Loch statt einer
##     Schlucht. Die Streckung ist deshalb hier ein Akzent und kein Hebel.
func _massive_charakterisieren(liste: Array) -> void:
	for ms in liste:
		if ms.has("type") or ms.has("schaerfe"):
			continue
		if ms.get("glatt", false):
			continue
		var mp: Vector3 = ms["pos"]
		var wuerfel := RandomNumberGenerator.new()
		wuerfel.seed = hash(Vector2i(int(mp.x), int(mp.z))) ^ 0x4B0D_3117
		ms["schaerfe"] = wuerfel.randf_range(0.30, 0.78)
		ms["grat"] = wuerfel.randf_range(1.9, 3.4)
		ms["nz_frq"] = wuerfel.randf_range(2.6, 6.5)
		ms["nz_off"] = wuerfel.randf_range(-9000.0, 9000.0)
		ms["dehnung"] = wuerfel.randf_range(0.86, 1.18)
		ms["drall"] = wuerfel.randf_range(0.0, PI)


func _hochgebirge() -> Array:
	var quer := Vector2(TAL_RICHTUNG.y, -TAL_RICHTUNG.x)   # senkrecht zur Talachse
	var out: Array = []
	# Gipfelhoehen je Kette, von vorn nach hinten.
	# ELF STATT NEUN JE KETTE, weil der Laengsabstand mit dem Radius von 1300 auf 1100 m
	# heruntergegangen ist (TAL_KETTE_ABSTAND). 11 * 1100 deckt dieselben 11 km ab.
	#
	# DIESE LISTE IST DER ZWEITE HEBEL DES KEILS, UND ER IST DER STAERKERE.
	# Die Sollinie _tal_halbbreite verengt das Tal um 370 m je Seite. Die Hoehenlinie h
	# eines geraden Kegels liegt aber bei r * (1 - h / peak) vom Mittelpunkt — bei
	# r = 2200 verschiebt schon der Unterschied zwischen 850 und 1250 m Gipfel die
	# 800-m-Linie um 2200 * (0.36 - 0.06) = 663 m. Die Gipfelliste bewegt die SICHTBARE
	# Kante also fast doppelt so weit wie die Sollinie.
	#
	# WAS HIER VORHER STAND UND WARUM ES DEN KEIL AUFGEHOBEN HAT: die Hoehen sprangen
	# innerhalb einer Kette zwischen 850 und 1250 m und FIELEN nach hinten ab (Kette +1
	# endete auf 980/850, Kette -1 auf 1140/830). Am Talschluss standen damit die
	# NIEDRIGSTEN Waende, und dort lag die 800-m-Linie am weitesten aussen: gemessen
	# (tools/_tal_kammkeil.gd) 1450/1575 m bei laengs 7000, aber 2075/1750 bei 8000 —
	# das Tal wurde oben nach hinten BREITER. Der Boden verjuengte sich (1.58 : 1), die
	# Silhouette, die man aus dem Cockpit sieht, nicht (H800 1.46 : 1 mit 4275 m
	# Aufweitung an 14 Stellen). Das ist genau umgekehrt zum Referenzbild, in dem das
	# Tal in die hoechsten, verschneiten Gipfel hineinlaeuft.
	#
	# JETZT: beide Ketten steigen MONOTON zum Talschluss und laufen dort in die 1250 m
	# aus. Der Streubereich innerhalb einer Kette ist damit weg — die Ungleichheit der
	# beiden Talseiten kommt jetzt SYSTEMATISCH statt zufaellig: Kette -1 liegt auf ihrer
	# ganzen Laenge rund 50 bis 70 m ueber Kette +1 und ist damit durchgehend die
	# steilere, dominante Flanke, so wie im Referenzbild die rechte. Zufaelliges Auf und
	# Ab braucht es dafuer nicht: der Faktor (0.68 + 0.32 * rdg) in TerrainWorld streut
	# jeden Gipfel ohnehin um -32 Prozent, gemessen stehen von 1250 m nominal zwischen
	# 850 und 1100 m im Gelaende.
	# DER TALMUND BLEIBT NIEDRIG (860/910). Das ist eine bewusste Abwaegung, und sie hat
	# einen Preis, der hier stehen bleibt, damit ihn niemand fuer einen Fehler haelt:
	# niedrigere Gipfel vorn heissen flachere Kegel vorn, und der Talboden am Mund wird
	# dadurch breiter — gemessen (tools/_tal_keil.gd, Reihe GEWACHSEN) 1800 statt 1725 m
	# an der breitesten Stelle der ersten 3 km. Dagegen steht: der MITTELWERT ueber
	# 500..9500 m bleibt bei 1080 m (vorher 1076 m), das Tal ist also nirgends im Mittel
	# breiter geworden, und die Verjuengung geht von 1.82 auf 2.12 : 1 hoch.
	# WARUM DER PREIS SICH LOHNT: haelt man den Mund hoch (Rampe erst ab 1000 m), wandert
	# die 600-m-Hoehenlinie vorn um rund 120 m je Seite nach INNEN und das Keilmass auf
	# dieser Linie faellt von 1.43 auf rund 1.33 : 1 zurueck — also fast auf den Zustand,
	# den diese Runde beheben sollte. Der sichtbare Keil steckt zum groesseren Teil im
	# NIEDRIGEN MUND, nicht in den hohen Gipfeln hinten.
	# Gemessen mit tools/_tal_kammkeil.gd, vorher -> nachher:
	#   Talboden  H200:  1.58 -> 1.75 : 1
	#   400-m-Linie:     1.34 -> 1.48 : 1
	#   600-m-Linie:     1.30 -> 1.43 : 1, und sie oeffnet sich nicht mehr nach hinten
	#                    (vorher mitte 2486 / hinten 2558 m, jetzt 2567 / 2394 m)
	#   hoechster Kamm:  vorn 931 / hinten 983 m  ->  vorn 880 / hinten 1072 m
	var kaemme := [
		[1.0, [860.0, 925.0, 990.0, 1050.0, 1105.0, 1150.0, 1190.0, 1220.0, 1245.0,
			1250.0, 1250.0]],
		[-1.0, [910.0, 980.0, 1045.0, 1105.0, 1155.0, 1200.0, 1230.0, 1250.0, 1250.0,
			1250.0, 1250.0]],
	]
	for k in kaemme:
		var seite: float = k[0]
		var gipfel: Array = k[1]
		# LAENGSVERSATZ: die nordoestliche Kette (seite -1, die landeinwaerts stehende)
		# sitzt eine halbe Massivteilung weiter vorn, damit ihre Ausbuchtungen auf die
		# Engstellen der Gegenseite fallen. Begruendung und Messwerte bei
		# TAL_KETTE_VERSATZ. Nach VORN und nicht nach hinten, weil das erste Massiv damit
		# bei laengs -550 m steht und dort noch tief im Land liegt (Radius 9.5 km); die
		# seewaertige Kette bleibt unangetastet, ihre Kuestenlage aendert sich also nicht.
		var kette_off := 0.0 if seite > 0.0 else -TAL_KETTE_VERSATZ
		for i in gipfel.size():
			var laengs := float(i) * TAL_KETTE_ABSTAND + kette_off
			# KEIL: die Halbbreite haengt an der Laengsposition, nicht mehr an einer
			# Konstanten. Der Laengsabstand der Massive bleibt bei 1100 m — der Versatz
			# quer dazu betraegt 370 m ueber 9200 m, also 44 m je Schritt, und aus 1100 m
			# Abstand werden dadurch sqrt(1100^2 + 44^2) = 1101 m. Das Verhaeltnis zum
			# Radius bleibt damit bei 0.50 und die Kette ein Grat (tools/_tal_keil.gd
			# meldet 0.500 auf beiden Seiten).
			var p := TAL_START + TAL_RICHTUNG * laengs \
				+ quer * seite * _tal_halbbreite(laengs)
			# JEDER BERG EIN EIGENER. Vorher trugen alle 18 Massive der beiden Ketten
			# dieselben vier Werte — gleiche Schaerfe, gleiche Gratstaerke, runder
			# Fussabdruck, dasselbe Rauschmuster. Sie unterschieden sich nur in Hoehe und
			# Ort, und genau deshalb sahen sie aus wie Kopien voneinander.
			# Die Streuung kommt aus einem festen Wuerfel je Berg, NICHT aus randf():
			# die Welt muss bei jedem Start dieselbe sein. Der Index geht in den Seed,
			# damit Nachbarn nie zufaellig gleich ausfallen.
			var wuerfel := RandomNumberGenerator.new()
			wuerfel.seed = hash(Vector2i(int(seite), i)) ^ 0x5EED_BE46
			# schaerfe: 0.45 gibt eine breite Schulter, 0.98 eine Nadel.
			var schaerfe := wuerfel.randf_range(0.45, 0.98)
			# grat: wie stark die Rippen und Rinnen ausgepraegt sind.
			var grat := wuerfel.randf_range(1.6, 4.6)
			# nz_frq: Feinheit der Rippen. Klein = wenige breite Grate, gross = zerklueftet.
			# OBERGRENZE VON 4.2 AUF 2.5 HERUNTER. Bei 4.2 lag die Rippung so fein, dass sie
			# in die Maschenweite des Netzes lief, und im Bild (Shot tal_quer) war die ganze
			# Kette ein Salz-und-Pfeffer-Teppich aus hellen und dunklen Dreiecken statt eines
			# Berges. Mit 2.5 liest sie sich als zusammenhaengender Fels.
			#
			# DIE MESSUNG BELEGT DIESE AENDERUNG NICHT, und das ist wichtig festzuhalten,
			# damit niemand sie fuer eine Zahlenoptimierung haelt: tools/_rauheit.gd meldet
			# vorher wie nachher rund 5 m mittleren Hoehensprung je 8-m-Schritt, der Anteil
			# der Punkte ueber 45 Grad geht nur von 14,1 auf 13,3 Prozent. Was sich aendert,
			# ist nicht die GROESSE der Spruenge, sondern ihre ZUSAMMENHANGSLAENGE — und die
			# misst diese Zahl nicht. Entschieden hat hier das Bild, nicht der Messwert.
			#
			# ZWEI FEHLSPUREN VORHER, beide durch Messung ausgeschlossen:
			#  * "Der Schnee schaltet je Facette an und aus." Er tat es, und die Schwelle ist
			#    inzwischen ueber ein Rauschen gegluettet — am Bild aenderte das fast nichts.
			#    Die dunklen Dreiecke waren nie schneefreier Fels, sondern SCHATTIERTE.
			#  * "Das Gelaende ist zu rau." Der Vulkan ist mit 48,6 Prozent der Punkte ueber
			#    45 Grad weit rauer als dieser Kamm mit 14,1 und sieht trotzdem gut aus. Sein
			#    Basalt ist dunkel; auf dunklem Grund verschluckt das Auge dieselben
			#    Winkelspruenge, die auf hellem Kalk jede einzelne Facette sichtbar machen.
			var frq := wuerfel.randf_range(1.0, 2.5)
			# dehnung/drall: gedrehte Ellipse als Grundriss. Der staerkste Hebel ueberhaupt —
			# ein 1.6-fach gestreckter Berg liest sich voellig anders als ein Kegel.
			var dehnung := wuerfel.randf_range(0.72, 1.55)
			out.append({"pos": Vector3(p.x, 0.0, p.y), "r": TAL_KETTE_R,
				"peak": float(gipfel[i]), "schaerfe": schaerfe, "grat": grat,
				"nz_frq": frq, "nz_off": wuerfel.randf_range(-9000.0, 9000.0),
				"dehnung": dehnung, "drall": wuerfel.randf_range(0.0, PI)})
	# DIE FELSRIPPE am Taleingang: der Fels, in dem das Felsentor als LOCH sitzt.
	#
	# HIER STANDEN NACHEINANDER SCHON ZWEI FALSCHE FASSUNGEN:
	#  1. zwei gleiche Kegel (r 380, peak 260, je 300 m links und rechts der Achse) — im
	#     Bild zwei ununterscheidbare, glatte Sandduenen mit einem Reifen dazwischen.
	#  2. Schulter (470 m aussen, r 560, peak 520) plus eine Rippe erst bei 980 m. Die
	#     Rippe stand damit GANZ AUSSERHALB des Bildausschnitts, den tools/_tor_form.gd
	#     rastert (lo.x - 400 .. hi.x + 400, also etwa +-760 m), und zwischen Schulter und
	#     Rippe klaffte auf Scheitelhoehe ein rund 300 m breiter Himmelspalt. Gemessen:
	#     "hoechstes Gelaende quer zur Torachse 467 m" bei 654 m Scheitel, "seitlich
	#     angebunden: links nein, rechts nein". Im Bild: ein Stapelturm VOR einem Sattel.
	#
	# JETZT EINE EINZIGE, DOMINANTE FELSMASSE dicht am Tor, dahinter zwei Massive, die sie
	# an die Talkette anschliessen. quer ist das lokale +X des Tors (build_felsentor dreht
	# mit atan2(TAL_RICHTUNG.x, TAL_RICHTUNG.y)); bei +X steht das dicke Bein, dort also
	# die Rippe. Gegenueber bleibt nur ein niedriger Sporn — die Ungleichheit der beiden
	# Seiten ist der Kern der Form.
	#
	# DIE ZWEI ZAHLEN, AN DENEN DIE RIPPE HAENGT, sind Abstand und Radius, nicht der
	# Gipfel: mit schaerfe ~ 1 ist das Profil der GERADE Kegel peak * (1 - d/r), und der
	# Fuss liegt damit exakt bei (Abstand - r).
	#  * Fuss bei 120 m quer zur Achse (700 - 580): dort steht schon das dicke Bein
	#    (Innenkante 0.19 * 520 = 99 m). Die lichte Weite des Tors liegt also GANZ vor dem
	#    Rippenfuss und kann von ihm nicht zugehen — auf der Talachse selbst ist der
	#    Beitrag null (d = 700 > r = 580).
	#  * Gipfel 1080 m bei 700 m Abstand: das Gelaende steigt mit rund 1.3 m je Meter an
	#    und steht 700 m neben dem Tor rund 900 m hoch — ueber dem 654 m hohen Scheitel.
	#    Genau das misst _tor_form.gd als "hoechstes Gelaende quer zur Torachse", und
	#    genau das ist der Unterschied zwischen Rippe mit Loch und freistehendem Reifen.
	# Der Faktor (0.68 + 0.32 * rdg) in TerrainWorld streut die Hoehe um -20 Prozent; die
	# 1080 sind deshalb mit Reserve gewaehlt und nicht knapp auf 654 gerechnet.
	#
	# grat 5.0 ist die beidseitige Gratamplitude (crag - 0.5) * 30 * (grat - 1). Sie
	# zerlegt die Kegelflanke in Rippen und Rinnen — ohne sie waere auch diese Masse
	# wieder eine glatte Duene.
	var tor_m: Vector2 = TAL_START + TAL_RICHTUNG * TOR_LAENGS
	var rippe: Vector2 = tor_m + quer * 700.0 + TAL_RICHTUNG * 40.0
	out.append({"pos": Vector3(rippe.x, 0.0, rippe.y), "r": 580.0, "peak": 1080.0,
		"schaerfe": 0.96, "grat": 5.0})
	# ANSCHLUSS AN DIE TALKETTE. Ohne diese beiden staende die Rippe als einzelner Zahn im
	# Tal. Abstand zum Vorgaenger jeweils rund die HAELFTE des Radius (420/610 = 0.69 und
	# 380/600 = 0.63) — die Regel aus dem Kopfkommentar, sonst wird aus dem Grat eine
	# Perlenschnur. Beide liegen mit ihrem Fuss (1120 - 640 = 480 bzw. 1520 - 700 = 820 m)
	# weit ausserhalb der Durchfahrt.
	var rippe2: Vector2 = tor_m + quer * 1120.0 - TAL_RICHTUNG * 60.0
	out.append({"pos": Vector3(rippe2.x, 0.0, rippe2.y), "r": 640.0, "peak": 1200.0,
		"schaerfe": 0.92, "grat": 4.5})
	var rippe3: Vector2 = tor_m + quer * 1520.0 + TAL_RICHTUNG * 90.0
	out.append({"pos": Vector3(rippe3.x, 0.0, rippe3.y), "r": 700.0, "peak": 1150.0,
		"schaerfe": 0.90, "grat": 4.0})
	# Gegenueber nur ein Sporn — er nimmt die schlanke Saeule auf, die dort einsticht.
	# Er darf NICHT so hoch werden wie die Rippe: ein zweiter Berg machte daraus wieder
	# ein Tor zwischen zwei gleichen Kegeln.
	# 400 statt 360 m aussen und r 400 statt 380: sein Fuss liegt damit auf der Talachse
	# (400 - 400 = 0) statt 20 m davor. Vorher hob er die Achse selbst um rund 20 m an und
	# schob die lichte Hoehe des Tors nach oben.
	var sporn: Vector2 = tor_m - quer * 400.0
	out.append({"pos": Vector3(sporn.x, 0.0, sporn.y), "r": 400.0, "peak": 330.0,
		"schaerfe": 0.95, "grat": 4.0})
	# QUERKETTE am hinteren Ende: macht das Tal zur Sackgasse. Sie steht 1,6 km hinter dem
	# Flugplatz — weit genug, um nach dem Aufsetzen noch auszurollen und zu drehen.
	#
	# DIE AEUSSEREN BEIDEN STEHEN HOEHER ALS DIE MITTLERE, UND DAS IST DER PUNKT.
	# Mit einheitlich 980 m schloss das Tal in einer Kuppe, die NIEDRIGER war als die
	# Seitenketten daneben (dort jetzt 1250 m): im Bild (tal_anflug) endete das Tal in einem
	# braunen Huegel unter der Schneegrenze, waehrend links und rechts weisse Waende
	# standen. Im Referenzbild schliesst das Tal in den HOECHSTEN, verschneiten Gipfeln.
	#
	# WARUM DIE MITTLERE TROTZDEM NIEDRIGER BLEIBT: sie ist die einzige der drei, die nah
	# genug an ADLERHORST steht, um dort Gelaende zu machen — 1600 m Abstand bei r 2300
	# geben rund 230 m gewachsenen Fels auf der Platzmitte, und genau so viel muss die
	# Einebnung wieder abtragen. Jeder Meter hier ist ein Meter tieferer Steinbruch neben
	# der Bahn. Die aeusseren beiden liegen mit sqrt(1600^2 + 1500^2) = 2193 m schon fast am
	# Kegelrand und tragen auf der Platzmitte nur rund 33 m bei; 1250 statt 980 kosten dort
	# also 9 m, geben aber die weissen Gipfel am Talschluss.
	var quer_gipfel := [1250.0, 1080.0, 1250.0]
	for j in range(-1, 2):
		# SIE HING AM PLATZ (ADLERHORST_LAENGS + 1600) UND DAS WAR EINE FALLE. Als der
		# Platz in den Berg zog (8800 -> 9820), wanderte die Querkette mit — 1000 m weiter
		# weg —, und mit ihr verschwand der Fels ueber der Kaverne: gemessen fiel das
		# Gelaende bei laengs 9550 von 618 auf 154 m. Der Talschluss ist ein ORT in der
		# Landschaft und darf nicht davon abhaengen, wo gerade ein Flugplatz liegt.
		var p := TAL_START + TAL_RICHTUNG * TAL_QUERKETTE_LAENGS \
			+ quer * float(j) * 1500.0
		out.append({"pos": Vector3(p.x, 0.0, p.y), "r": 2300.0,
			"peak": float(quer_gipfel[j + 1]), "schaerfe": 0.85, "grat": 3.2})
	return out


# Nächster Flugplatz: Name, Entfernung (km), Kompasskurs (Nord = -Z = 0°)
func _nearest_airfield(pos: Vector3) -> String:
	if airfields.is_empty():
		return "—"
	var best: Dictionary = airfields[0]
	var bestd := INF
	for af in airfields:
		var ap: Vector3 = af["pos"]
		var dd := Vector2(pos.x - ap.x, pos.z - ap.z).length()
		if dd < bestd:
			bestd = dd
			best = af
	var bp: Vector3 = best["pos"]
	var brg := rad_to_deg(atan2(bp.x - pos.x, -(bp.z - pos.z)))
	if brg < 0.0:
		brg += 360.0
	return "%s   %.1f km   %03d°" % [best["name"], bestd / 1000.0, int(round(brg))]


# --- Button-/UI-Aktionen ---------------------------------------------------
func _on_fly_pressed() -> void:
	_set_mode(Mode.FLY)


func _on_hangar_pressed() -> void:
	_set_mode(Mode.BUILD)


func _on_symmetry_toggled(on: bool) -> void:
	build_ctrl.set_symmetry(on)


func _on_snap_toggled(on: bool) -> void:
	build_ctrl.snap_enabled = on
	_toast("Andocken " + ("AN" if on else "AUS — freie Platzierung"))


# Aus dem Bau-Editor (Taste N): Checkbox synchron halten + Toast.
func _on_snap_changed(on: bool) -> void:
	if snap_btn:
		snap_btn.set_pressed_no_signal(on)
	_toast("Andocken " + ("AN" if on else "AUS — freie Platzierung"))


# ===========================================================================
# OBERE WERKZEUGLEISTE — alle Editor-Funktionen sichtbar & klickbar (statt nur Tastenkürzel)
# ===========================================================================
func _build_toolbar() -> void:
	# Frueher stand die Leiste bildschirm-mittig (Anker 0.5, 1280 breit) und lag damit
	# ueber dem linken Bau-Panel — die letzten Kategorie-Icons waren verdeckt. Jetzt
	# spannt ein unsichtbarer Halter NUR den freien Bereich rechts des Panels auf, und
	# die Leiste zentriert sich darin. Damit kann sie das Panel nie mehr ueberlappen und
	# sitzt auf jeder Bildschirmbreite mittig im verbleibenden Platz.
	var halter := Control.new()
	halter.name = "WerkzeugleisteHalter"
	halter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Rechts endet der freie Bereich am FLUG-CHECK-Panel (Anker rechts, 340 breit,
	# 18 Rand) — sonst schoeben sich "Windkanal / Debug / Zentrieren" darunter.
	_rect(halter, 0, 0, 1, 0, 512, 84, -376, 196)
	build_root.add_child(halter)
	var bar := _panel(Color(0.05, 0.07, 0.11, 0.86))
	bar.name = "Werkzeugleiste"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	halter.add_child(bar)
	# HFlowContainer statt HBoxContainer: eine HBox hat als Mindestbreite die SUMME
	# aller Knoepfe und waechst notfalls aus dem Bild heraus — genau so schob sie sich
	# unter das Statistik-Panel (gemessen: 1018 noetig, 946 frei). Der Flow-Container
	# bricht stattdessen in eine zweite Reihe um und bleibt im Rahmen.
	var hb := HFlowContainer.new()
	hb.add_theme_constant_override("h_separation", 3)
	hb.add_theme_constant_override("v_separation", 3)
	hb.alignment = FlowContainer.ALIGNMENT_CENTER
	bar.add_child(hb)
	# Verlauf
	hb.add_child(_tb_btn("Undo", "Rückgängig (Strg+Z)", _on_undo))
	hb.add_child(_tb_btn("Redo", "Wiederholen (Strg+Y)", _on_redo))
	hb.add_child(VSeparator.new())
	# Bearbeiten
	hb.add_child(_tb_btn("Dupliz.", "Auswahl duplizieren + spiegeln (Strg+D)", func() -> void: build_ctrl.duplicate_selected()))
	hb.add_child(_tb_btn("Löschen", "Ausgewähltes Teil löschen (X)", func() -> void: build_ctrl.delete_selected()))
	hb.add_child(VSeparator.new())
	# Werkzeug-Modi (Bewegen/Drehen/Skalieren)
	_tb_tool_btns.clear()
	var tools := [["Bewegen", "Bewegen-Gizmo (G)"], ["Drehen", "Drehen-Gizmo (R) — SHIFT beim Ziehen = 45-Grad-Schritte"], ["Skalieren", "Skalieren-Gizmo (S)"]]
	for ti in tools.size():
		var gi := ti
		var rb := _tb_radio(tools[ti][0], tools[ti][1], func() -> void: build_ctrl.set_gizmo_mode(gi))
		_tb_tool_btns.append(rb)
		hb.add_child(rb)
	hb.add_child(VSeparator.new())
	# Optionen (Toggles)
	mirror_btn = _tb_toggle("Symmetrie", "Symmetrie-Spiegelung (M)", build_ctrl.symmetry, _on_symmetry_toggled)
	hb.add_child(mirror_btn)
	snap_btn = _tb_toggle("Snap", "Magnetisches Andocken (N)", build_ctrl.snap_enabled, _on_snap_toggled)
	hb.add_child(snap_btn)
	hb.add_child(VSeparator.new())
	# Ansichten (Frei/Front/Seite/Oben)
	_tb_view_btns.clear()
	var views := [["Frei", "Freie Perspektive (4)"], ["Front", "Front-Ansicht (1)"], ["Seite", "Seiten-Ansicht (2)"], ["Oben", "Ober-Ansicht (3)"]]
	for vi in views.size():
		var vp := vi
		var vbtn := _tb_radio(views[vi][0], views[vi][1], func() -> void: build_ctrl.set_view(vp))
		_tb_view_btns.append(vbtn)
		hb.add_child(vbtn)
	hb.add_child(VSeparator.new())
	# Analyse
	drag_view_btn = _tb_toggle("Windkanal", "Windkanal-Widerstandsansicht (Heatmap)", build_ctrl.wind_tunnel, _on_drag_view)
	hb.add_child(drag_view_btn)
	hb.add_child(_tb_toggle("Debug",
		"Debug: Boxen um jedes Teil — CYAN = Snap-/Kollisionsbox (damit rechnet das Andocken), GELB = echte Geometrie",
		build_ctrl.debug_boxes, _on_debug_boxes))
	hb.add_child(_tb_btn("Zentrieren", "Kamera auf das Flugzeug zentrieren (F)", _on_reset_view))
	_sync_toolbar()


func _tb_btn(txt: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", 12)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _tb_toggle(txt: String, tip: String, pressed: bool, cb: Callable) -> Button:
	var b := _tb_btn(txt, tip, Callable())
	b.toggle_mode = true
	b.button_pressed = pressed
	b.toggled.connect(cb)
	return b


func _tb_radio(txt: String, tip: String, cb: Callable) -> Button:
	var b := _tb_btn(txt, tip, Callable())
	b.toggle_mode = true
	b.pressed.connect(cb)
	return b


# Toolbar-Zustand mit dem BuildController synchron halten (auch bei Tastenkürzeln).
# Aktive Toggles/Modi/Ansichten werden eingedrückt + grün getönt.
func _sync_toolbar() -> void:
	if build_ctrl == null:
		return
	if mirror_btn != null:
		_tb_hl(mirror_btn, build_ctrl.symmetry)
	if snap_btn != null:
		_tb_hl(snap_btn, build_ctrl.snap_enabled)
	if drag_view_btn != null:
		_tb_hl(drag_view_btn, build_ctrl.wind_tunnel)
	for i in _tb_view_btns.size():
		_tb_hl(_tb_view_btns[i], build_ctrl._ortho_view == i)
	for i in _tb_tool_btns.size():
		_tb_hl(_tb_tool_btns[i], build_ctrl.gizmo_mode == i)
	if wind_legend != null:
		wind_legend.visible = build_ctrl.wind_tunnel


func _tb_hl(b: Button, active: bool) -> void:
	b.set_pressed_no_signal(active)
	b.modulate = Color(0.5, 1.0, 0.6) if active else Color(1, 1, 1)


# ===========================================================================
# ZIELE (Luftballons / Luftschiffe zum Abschießen)
# ===========================================================================
const _TARGET_COLORS := [
	Color(0.92, 0.22, 0.2), Color(0.96, 0.72, 0.12), Color(0.22, 0.6, 0.96),
	Color(0.3, 0.85, 0.35), Color(0.85, 0.32, 0.88), Color(0.95, 0.5, 0.15),
]


func _spawn_targets() -> void:
	for i in 16:
		_make_target("balloon", _rand_target_pos(40.0, 210.0), _TARGET_COLORS[i % _TARGET_COLORS.size()])
	for i in 3:
		_make_target("airship", _rand_target_pos(130.0, 250.0), Color(0.72, 0.74, 0.8))


# FLAK-ZONE: ein verteidigter Bereich ein Stück vor dem Spawn (Flieger schaut nach -Z).
# Mehrere Geschütze feuern nur, wenn der Spieler IN der Zone und im Höhen-Band ist.
# Windpark: 7 Raeder auf den Huegeln, Hoehe je Standort aus dem Terrain abgefragt
# (seed-robust: zu flache/versunkene Standorte werden uebersprungen).
var _wind_rotors: Array = []
func _build_windfarm(center: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for i in 7:
		var off := Vector3(rng.randf_range(-750, 750), 0, rng.randf_range(-550, 550))
		var p := center + off
		var h := terrain.height_at(p.x, p.z)
		if h < 14.0:
			continue
		var rotor := Landmarks.build_windmill(fly_world, Vector3(p.x, h - 0.4, p.z),
			0.6 + rng.randf_range(-0.15, 0.15))
		_wind_rotors.append(rotor)


func _on_map_image_ready(img: Image) -> void:
	if _map_thread != null:
		_map_thread.wait_to_finish()
		_map_thread = null
	var lay := CanvasLayer.new()
	lay.layer = 30                      # ueber dem Flug-HUD
	add_child(lay)
	world_map = WorldMap.new()
	lay.add_child(world_map)
	world_map.setup(img, airfields, _map_pois, null)
	# Corner-Minimap im Flug-HUD mit derselben Karte fuettern
	if flight_hud != null:
		flight_hud.mini_tex = ImageTexture.create_from_image(img)
		flight_hud.mini_airfields = airfields
		flight_hud.mini_pois = _map_pois


func _toggle_map() -> void:
	if world_map == null:
		_toast("Karte wird noch gezeichnet ...")
		return
	world_map.set_player(flight_ctrl.aircraft)   # Flieger wird je Flug neu gebaut
	world_map.toggle()
	if flight_hud != null:
		flight_hud.big_map_open = world_map.visible


func _spawn_flak() -> void:
	var center := Vector3(250.0, 0.0, -2400.0)
	var radius := 300.0
	var offsets := [
		Vector3(0, 0, 0), Vector3(210, 0, 90), Vector3(-165, 0, 150), Vector3(70, 0, -215),
	]
	for off in offsets:
		var pos: Vector3 = center + off
		if terrain != null:
			pos.y = terrain.height_at(pos.x, pos.z)
		var flak := FlakGun.new()
		flak.zone_center = center
		flak.zone_radius = radius
		fly_world.add_child(flak)
		flak.global_position = pos


## RAKETENSTELLUNGEN. Sie sind der Grund, warum es Fackeln und Düppel gibt.
##
## WO SIE STEHEN, IST EINE AUSSAGE UEBER DIE KARTE. Die Flakzone im Sueden bekommt eine
## Waermesuchende dazu — dort fliegt man tief und schnell, und genau da beisst sie. Der
## Talschluss vor ADLERHORST bekommt zwei Radarstellungen: eine Basis im Berg, an die man
## ueber ein enges Hochtal heranfliegt, ist der Ort, an dem eine weitreichende
## Radarstellung wirklich weh tut — und an dem Tiefflug hinter den Flanken die richtige
## Antwort ist, weil das Hoehenband der Radarstellung bei 70 m beginnt.
##
## Bewusst WENIGE. Vier Stellungen auf einer 20-km-Insel sind keine Flugabwehrdecke,
## sondern vier Orte, an denen man aufpassen muss.
## FLUGABWEHR AUF DER GROSSEN INSEL DER KETTE.
##
## WOFUER. Die neu gewonnenen acht Kilometer Aussenring hatten ausser zwei Flugplaetzen
## und Landschaft keinen Inhalt. Eine verteidigte Insel macht aus einem langen Flug eine
## Aufgabe: hinfliegen, tief bleiben, die Stellung ausschalten, wieder heraus. Sie nutzt
## dieselben Bauwerke wie das Festland (SamSite, FlakGun) und ist damit sofort
## verstaendlich — wer die Regeln am Talschluss gelernt hat, kennt sie hier.
##
## EINE Raketenstellung und ZWEI Flak, nicht mehr. Die Insel ist 1,5 km breit; wer sie
## dichter besetzt, macht aus einer Aufgabe eine Wand.
func _spawn_inselwehr() -> void:
	var insel := Vector3(28600, 0, -10600)
	var sam := SamSite.new()
	sam.art = "radar"
	sam.zerstoert.connect(_on_sam_zerstoert)
	fly_world.add_child(sam)
	var sp := insel + Vector3(-90.0, 0.0, 40.0)
	sp.y = terrain.height_at(sp.x, sp.z)
	sam.global_position = sp
	for off in [Vector3(160.0, 0.0, -120.0), Vector3(-40.0, 0.0, -210.0)]:
		var fp: Vector3 = insel + off
		fp.y = terrain.height_at(fp.x, fp.z)
		var flak := FlakGun.new()
		flak.zone_center = insel
		flak.zone_radius = 900.0
		fly_world.add_child(flak)
		flak.global_position = fp


func _spawn_sam() -> void:
	var stellungen := [
		# Bei der Flakzone im Sueden: kurze Reichweite, schnelle Reaktion.
		{"art": "ir", "pos": Vector3(430.0, 0.0, -2250.0)},
		{"art": "ir", "pos": Vector3(60.0, 0.0, -2620.0)},
	]
	# Am Talschluss vor der Bergbasis, links und rechts der Anflugachse.
	var quer := Vector2(TAL_RICHTUNG.y, -TAL_RICHTUNG.x)
	for seite in [-1.0, 1.0]:
		var tp: Vector2 = _tal_punkt(8300.0) + quer * (seite * 520.0)
		stellungen.append({"art": "radar", "pos": Vector3(tp.x, 0.0, tp.y)})
	for st in stellungen:
		var pos: Vector3 = st["pos"]
		if terrain != null:
			pos.y = terrain.height_at(pos.x, pos.z)
		var sam := SamSite.new()
		sam.art = String(st["art"])
		sam.zerstoert.connect(_on_sam_zerstoert)
		fly_world.add_child(sam)
		sam.global_position = pos


func _rand_target_pos(ymin: float, ymax: float) -> Vector3:
	# vor der Startbahn (Flieger schaut nach -Z), gut erreichbar
	return Vector3(randf_range(-380.0, 380.0), randf_range(ymin, ymax), randf_range(-750.0, -30.0))


func _make_target(kind: String, pos: Vector3, col: Color, diff := 1.0) -> void:
	var t := Target.new()
	targets_root.add_child(t)
	t.setup(kind, pos, col, diff)
	t.killed.connect(_on_target_killed)


## Eine ausgeschaltete Raketenstellung: Geld, sonst nichts.
##
## BEWUSST NICHT ueber _on_target_killed. Der Weg der Ballons haengt zwei Dinge an einen
## Abschuss, die hier beide falsch waeren: im Sandkasten setzt er nach sieben Sekunden
## einen ERSATZBALLON in die Luft (eine Stellung ist kein Ballon), und im Ueberlebensmodus
## zaehlt er den Abschuss auf den Wellenfortschritt an. Eine Welle waere damit auch ohne
## einen einzigen getroffenen Ballon zu schaffen — das waere eine stille Aenderung an der
## bestehenden Spielschleife, und die gehoert nicht in diese Neuerung.
func _on_sam_zerstoert(reward: int, _pos: Vector3) -> void:
	if game == null:
		return
	game.add_money(reward)
	_toast("Raketenstellung ausgeschaltet! +%d" % reward)


func _on_target_killed(reward: int, _pos: Vector3) -> void:
	if game == null:
		return
	if game.is_sandbox():
		# Sandbox: freies Zielfeld, Nachschub-Ballon (Geld egal)
		game.add_money(reward)
		_toast("Abschuss! +%d" % reward)
		get_tree().create_timer(7.0).timeout.connect(_respawn_balloon)
		return
	# Survival: Combo, Score, Wellen-Fortschritt
	_kills += 1
	_combo += 1
	_combo_t = COMBO_WINDOW
	_best_combo = maxi(_best_combo, _combo)
	var mult := 1.0 + 0.25 * float(_combo - 1)        # ×1, ×1.25, ×1.5, …
	var gain := int(round(float(reward) * mult))
	game.add_money(gain)
	_flight_score += gain
	if _combo >= 3:
		_toast("+%d   ×%d COMBO!" % [gain, _combo])
	else:
		_toast("Abschuss! +%d" % gain)
	# Wellen-Fortschritt nur zählen, solange die Welle noch läuft -> _alive wird nie negativ
	# und _wave_cleared() feuert genau EINMAL (beim Übergang auf 0), nicht bei Nachzüglern.
	if _alive > 0:
		_alive -= 1
		if _alive == 0:
			_wave_cleared()
	_update_survival_hud()


func _respawn_balloon() -> void:
	if targets_root == null or (game != null and not game.is_sandbox()):
		return
	_make_target("balloon", _rand_target_pos(40.0, 210.0), _TARGET_COLORS[randi() % _TARGET_COLORS.size()])


# --- Survival: Wellen-System + Flug-Score ----------------------------------
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _design_dirty:
		_save_design()   # Fenster-X vor Ablauf des Autosave-Debounce: noch schnell sichern


func _process(delta: float) -> void:
	# AUTOSAVE (Debounce): Bauänderungen landen nach 2 s Ruhe in user:// —
	# Bauen ohne explizites Slot-Speichern übersteht so den Neustart.
	if _design_dirty:
		_autosave_t += delta
		if _autosave_t >= 2.0:
			_design_dirty = false
			_autosave_t = 0.0
			_save_design()
	else:
		_autosave_t = 0.0
	# Windraeder drehen (billig; nur sichtbar im Flug)
	if mode == Mode.FLY:
		for r in _wind_rotors:
			if is_instance_valid(r):
				r.rotate_z(delta * 1.1)
	# Werkzeugleiste mit dem Editor-Zustand synchron halten (auch bei Tastenkürzeln)
	if mode == Mode.BUILD and not _tb_view_btns.is_empty():
		_sync_toolbar()
	# Terrain-Chunks um den Spieler streamen (nur im Flug nötig)
	if mode == Mode.FLY and terrain != null and flight_ctrl != null \
			and is_instance_valid(flight_ctrl.aircraft):
		terrain.update_center(flight_ctrl.aircraft.global_position)
		_wolken_aufenthalt(delta)
		# Die Decke wird um die KAMERA zentriert, nicht um das Flugzeug: die Spitze des
		# Sichtvolumens sitzt in der Kamera, und die haengt je nach Zoom, Free-Look und
		# Ruettelei bis zu 44 m hinter dem Flieger. Mit der Flugzeugposition muesste
		# WOLKEN_AREA diese 44 m zusaetzlich einplanen — so faellt der Posten ganz weg.
		_wolken_nachziehen(camera.global_position if camera != null
			else flight_ctrl.aircraft.global_position)
	# Basis-Deko animieren (drehendes Radar, Blinklichter) — billig, läuft immer
	for s in _spin_nodes:
		if is_instance_valid(s):
			s.rotate_y(delta * 0.9)
	_blink_t += delta
	var blink_on := fmod(_blink_t, 1.2) < 0.6
	for b in _blink_nodes:
		if is_instance_valid(b):
			b.visible = blink_on
	# Combo-Fenster herunterzählen (nur im Survival-Flug)
	if mode != Mode.FLY or game == null or game.is_sandbox():
		return
	if _combo_t > 0.0:
		_combo_t -= delta
		if _combo_t <= 0.0 and _combo > 0:
			_combo = 0
			_update_survival_hud()


func _begin_flight() -> void:
	# Beim Start in den Flug: Survival = frische Session + Welle 1; Sandbox = Feld bleibt.
	if game == null or game.is_sandbox():
		if survival_label:
			survival_label.visible = false
		return
	_kills = 0; _combo = 0; _best_combo = 0; _combo_t = 0.0; _flight_score = 0
	_flight_money0 = game.money
	_wave = 0
	_wave_session += 1            # entwertet evtl. noch laufende Wellen-Timer voriger Flüge
	_clear_targets()
	_start_wave(1)
	if survival_label:
		survival_label.visible = true


func _clear_targets() -> void:
	if targets_root == null:
		return
	for t in targets_root.get_children():
		if t.is_in_group("target"):
			t.queue_free()
	_alive = 0


func _start_wave(n: int) -> void:
	_wave = n
	# Spätere Wellen driften schneller — flach ansteigend + gedeckelt, damit Welle 10+
	# fordernd bleibt, aber schaffbar (vorher +12 %/Welle ungedeckelt -> W10 unspielbar).
	var diff := minf(1.0 + 0.06 * float(n - 1), 1.6)
	var balloons := 4 + n * 2
	var airships := int(n * 0.5)                       # ab Welle 2 ein Luftschiff, Welle 4 zwei …
	for i in balloons:
		_make_target("balloon", _rand_target_pos(40.0, 210.0), _TARGET_COLORS[i % _TARGET_COLORS.size()], diff)
	for i in airships:
		_make_target("airship", _rand_target_pos(130.0, 250.0), Color(0.72, 0.74, 0.8), diff)
	_alive = balloons + airships
	_toast("WELLE %d  —  %d Ziele" % [n, _alive])
	_update_survival_hud()


func _wave_cleared() -> void:
	var bonus := 150 + _wave * 150        # höherer Wellen-Bonus -> Geldfluss stagniert spät nicht
	game.add_money(bonus)
	_flight_score += bonus
	_toast("WELLE %d GESCHAFFT!   Bonus +%d" % [_wave, bonus])
	_update_survival_hud()
	var nw := _wave + 1
	var sess := _wave_session
	# pause-bewusster Timer (false), und nur feuern, wenn dieselbe Flug-Session noch läuft
	get_tree().create_timer(3.5, false).timeout.connect(func():
		if sess == _wave_session and mode == Mode.FLY:
			_next_wave(nw))


func _next_wave(n: int) -> void:
	if mode != Mode.FLY or game == null or game.is_sandbox():
		return
	_start_wave(n)


func _update_survival_hud() -> void:
	if survival_label == null:
		return
	var combo_txt := ("    ×%d COMBO" % _combo) if _combo >= 2 else ""
	survival_label.text = "WELLE %d  ·  übrig %d\nAbschüsse %d%s\nScore %d" % [_wave, _alive, _kills, combo_txt, _flight_score]


func _rank_for(s: int) -> String:
	if s >= 3500:
		return "Ass!"
	if s >= 1500:
		return "Veteran"
	if s >= 500:
		return "Pilot"
	return "Rekrut"


func _show_result_screen() -> void:
	if game == null or game.is_sandbox():
		return
	if survival_label:
		survival_label.visible = false
	var earned := maxi(game.money - _flight_money0, 0)
	var v := _dialog_shell("Flug-Auswertung")
	v.add_child(_lbl("Erreichte Welle:    %d" % _wave, 17))
	v.add_child(_lbl("Abschüsse:    %d" % _kills, 17))
	v.add_child(_lbl("Beste Combo:    ×%d" % _best_combo, 17))
	v.add_child(_lbl("Flug-Score:    %d" % _flight_score, 17))
	v.add_child(_lbl("Verdient:    +%d" % earned, 18, Color(1.0, 0.86, 0.3)))
	v.add_child(_lbl("Rang:    %s" % _rank_for(_flight_score), 22, Color(0.7, 1.0, 0.8)))
	var ok := Button.new()
	ok.text = "Weiter"
	ok.pressed.connect(_close_dialog)
	v.add_child(ok)


# ===========================================================================
# WIRTSCHAFT · MODI (Sandbox / Survival)
# ===========================================================================
func _on_game_changed() -> void:
	var mstr := "Sandbox ∞" if (game != null and game.is_sandbox()) else ("%d" % (game.money if game else 0))
	if money_label:
		money_label.text = "Guthaben: " + mstr
	if fly_money_label:
		fly_money_label.text = "" + ("∞ (Sandbox)" if (game and game.is_sandbox()) else str(game.money if game else 0))
	_build_upgrades_ui()


func _build_upgrades_ui() -> void:
	if upgrade_box == null:
		return
	for c in upgrade_box.get_children():
		c.queue_free()
	if game == null:
		return
	upgrade_box.add_child(_lbl("UPGRADES", 13, Color(0.6, 1.0, 0.8)))
	var defs := [
		{"key": "thrust", "name": "Triebwerks-Tuning (+15% Schub)"},
		{"key": "wing", "name": "Verstärkte Flügel (+30% Last)"},
		{"key": "light", "name": "Leichtbau (−8% Masse)"},
	]
	for u in defs:
		var lvl: int = game.upgrades.get(u["key"], 0)
		var b := Button.new()
		b.add_theme_font_size_override("font_size", 11)
		if lvl >= 3:
			b.text = "%s — MAX" % u["name"]
			b.disabled = true
		else:
			var cost := 500 * (lvl + 1)
			b.text = "%s  [Lv %d]  %d" % [u["name"], lvl, cost]
			b.pressed.connect(_on_buy_upgrade.bind(u["key"], cost))
		upgrade_box.add_child(b)


func _on_buy_upgrade(key: String, cost: int) -> void:
	if game.buy_upgrade(key, cost, 3):
		_toast("Upgrade gekauft: %s  (−%d)" % [key, cost])
	else:
		_toast("Zu teuer oder Maximum erreicht")


func _rebuild_palette() -> void:
	if part_grid == null:
		return
	_fill_part_grid()
	_refresh_tool_ui()


# --- Modus-Auswahl-Overlay -------------------------------------------------
func _show_mode_select() -> void:
	mode_overlay = ColorRect.new()
	mode_overlay.color = Color(0.03, 0.05, 0.09, 0.94)
	mode_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	mode_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(mode_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	mode_overlay.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	var t := _lbl("AVIASSEMBLY", 40, Color(1, 1, 1))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := _lbl("Wähle deinen Modus", 18, Color(0.7, 0.85, 1.0))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var sandbox := Button.new()
	sandbox.text = "SANDBOX\nAlle Teile frei · unbegrenzt bauen & fliegen"
	sandbox.custom_minimum_size = Vector2(460, 70)
	sandbox.add_theme_font_size_override("font_size", 18)
	sandbox.pressed.connect(_choose_mode.bind(GameState.GameMode.SANDBOX))
	v.add_child(sandbox)
	var surv := Button.new()
	surv.text = "SURVIVAL\nStarte klein · erfülle Missionen · verdiene Geld · kaufe & upgrade"
	surv.custom_minimum_size = Vector2(460, 70)
	surv.add_theme_font_size_override("font_size", 18)
	surv.pressed.connect(_choose_mode.bind(GameState.GameMode.SURVIVAL))
	v.add_child(surv)


func _choose_mode(m: int) -> void:
	game.start_mode(m)
	if is_instance_valid(mode_overlay):
		mode_overlay.queue_free()
	mode_overlay = null
	_rebuild_palette()
	_on_game_changed()
	_toast("Sandbox-Modus" if m == GameState.GameMode.SANDBOX else "Survival-Modus — viel Erfolg!")


func _on_clear_pressed() -> void:
	build_ctrl.clear_design()
	_refresh_tool_ui()


# Liest ein gespeichertes Design (Slot ODER Vorlage) als reine Teile-Liste — OHNE es zu laden.
# Für die Vorschau-Thumbnails im Laden-Menü.
func _read_design_parts(path: String) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_ARRAY:
		return out
	for it in data:
		if typeof(it) == TYPE_DICTIONARY and it.has("id") and typeof(it.get("xform")) == TYPE_ARRAY:
			var col := Color(0, 0, 0, 0)
			if it.has("color") and typeof(it["color"]) == TYPE_ARRAY and it["color"].size() >= 4:
				var ca: Array = it["color"]
				col = Color(ca[0], ca[1], ca[2], ca[3])
			var scl := Vector3.ONE
			if it.has("scale") and typeof(it["scale"]) == TYPE_ARRAY and it["scale"].size() >= 3:
				var sa: Array = it["scale"]
				scl = Vector3(sa[0], sa[1], sa[2])
			out.append({
				"id": it["id"], "xform": _array_to_xform(it["xform"]), "color": col, "scale": scl,
				"taper": float(it.get("taper", 1.0)), "taper_front": float(it.get("taper_front", 1.0)),
				"taper_y": float(it.get("taper_y", -1.0)), "taper_front_y": float(it.get("taper_front_y", -1.0)),
			})
	return out


# Kleines 3D-Vorschaubild eines GANZEN Designs (eigener SubViewport, rendert einmal).
func _make_design_thumb(parts: Array) -> Control:
	var svc := SubViewportContainer.new()
	svc.stretch = false
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.custom_minimum_size = Vector2(76, 48)
	var vp := SubViewport.new()
	vp.size = Vector2i(76, 48)
	vp.own_world_3d = true
	vp.transparent_bg = false
	# 8x statt 4x: die Kachel wird nur EINMAL gerendert (UPDATE_ONCE), die hoehere
	# Stufe kostet also nichts Laufendes und nimmt duennen Streben und
	# Propellerblaettern die Treppchen.
	vp.msaa_3d = Viewport.MSAA_8X
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	svc.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.14, 0.17, 0.23)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.72, 0.84)
	env.ambient_light_energy = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -38, 0)
	key.light_energy = 1.7
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(18, 130, 0)
	fill.light_energy = 0.7
	vp.add_child(fill)
	var root := Node3D.new()
	vp.add_child(root)
	for pd in parts:
		var p := PartCatalog.get_part(pd["id"])
		if p.is_empty():
			continue
		var holder := Node3D.new()
		holder.transform = pd["xform"]
		var vis := PartCatalog.build_visual(p, pd["color"], pd["taper"], pd["taper_front"], pd["taper_y"], pd["taper_front_y"])
		(vis as Node3D).scale = pd["scale"]
		holder.add_child(vis)
		root.add_child(holder)
	# Kamera auf die kombinierte AABB ausrichten (3/4-Ansicht von vorne-oben-rechts)
	var aabb := _visual_aabb(root)
	var center: Vector3 = aabb.get_center()
	var radius: float = maxf(aabb.size.length() * 0.5, 0.5)
	var cam := Camera3D.new()
	cam.fov = 38.0
	var dist: float = radius / tan(deg_to_rad(cam.fov * 0.5)) * 1.08
	var dir: Vector3 = Vector3(0.85, 0.55, 1.0).normalized()
	cam.look_at_from_position(center + dir * dist, center, Vector3.UP)
	cam.current = true
	vp.add_child(cam)
	return svc


func _on_save_pressed() -> void:
	_show_save_dialog()


func _on_load_pressed() -> void:
	_show_load_dialog()


func _on_toast_timeout() -> void:
	if toast_label:
		toast_label.text = ""


func _toast(msg: String) -> void:
	if toast_label == null:
		return
	toast_label.text = msg
	var t := get_tree().create_timer(1.6)
	t.timeout.connect(_on_toast_timeout)


# ===========================================================================
# Speichern / Laden
# ===========================================================================
func _save_design() -> void:
	_write_design(SAVE_PATH)


# Serialisiert das aktuelle Design in ein JSON-fähiges Array.
func _design_data() -> Array:
	var data: Array = []
	for it in build_ctrl.get_design():
		var c: Color = it.get("color", Color(0, 0, 0, 0))
		var s: Vector3 = it.get("scale", Vector3.ONE)
		# Alles, was der Spieler von Hand FORMT, muss mit in die Datei. Fehlte es hier,
		# lieferte get_design() die Werte zwar korrekt, beim naechsten Start waren sie weg:
		# Enden-Versatz, Beinlaenge und Eckrundungen sprangen stumm auf Standard zurueck.
		var sf: Vector2 = it.get("sf", Vector2.ZERO)
		var sb: Vector2 = it.get("sb", Vector2.ZERO)
		var bsc: Vector3 = it.get("bsc", Vector3.ONE)
		data.append({"id": it["id"], "xform": _xform_to_array(it["xform"]),
			"color": [c.r, c.g, c.b, c.a], "scale": [s.x, s.y, s.z],
			"taper": it.get("taper", 1.0), "taper_front": it.get("taper_front", 1.0),
			"taper_y": it.get("taper_y", -1.0), "taper_front_y": it.get("taper_front_y", -1.0),
			"tuser_f": it.get("tuser_f", false), "tuser_b": it.get("tuser_b", false),
			"glen": it.get("glen", 1.0), "br": it.get("br", []),
			"sf": [sf.x, sf.y], "sb": [sb.x, sb.y], "bsc": [bsc.x, bsc.y, bsc.z],
			"fill": it.get("fill", 0.0), "thrust_reverse": it.get("thrust_reverse", false)})
	return data


func _write_design(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		# NICHT still scheitern: Spieler würde sonst unbemerkt sein Design verlieren.
		_toast("Speichern fehlgeschlagen (%s, Fehler %d)" % [path, FileAccess.get_open_error()])
		push_warning("Design-Speichern fehlgeschlagen: %s (err %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(_design_data()))
	f.close()
	return true


# --- Benannte Speicher-Slots (user://hangar/<name>.json) ------------------------
func _ensure_slot_dir() -> void:
	if not DirAccess.dir_exists_absolute(SLOT_DIR):
		var err := DirAccess.make_dir_recursive_absolute(SLOT_DIR)
		if err != OK:
			_toast("Speicher-Ordner konnte nicht angelegt werden (Fehler %d)" % err)


func _safe_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges():
		if ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
			continue
		out += ch
	return out.substr(0, 40)


func _slot_path(n: String) -> String:
	return SLOT_DIR + "/" + _safe_name(n) + ".json"


func _list_slots() -> Array:
	var out: Array = []
	var d := DirAccess.open(SLOT_DIR)
	if d == null:
		return out
	for fn in d.get_files():
		if fn.ends_with(".json"):
			out.append(fn.get_basename())   # Anzeigename = Dateiname ohne .json
	out.sort()
	return out


# --- Speichern-/Laden-Overlays --------------------------------------------------
func _close_dialog() -> void:
	if is_instance_valid(dialog_overlay):
		dialog_overlay.queue_free()
	dialog_overlay = null


func _dialog_shell(title: String) -> VBoxContainer:
	_close_dialog()
	dialog_overlay = ColorRect.new()
	(dialog_overlay as ColorRect).color = Color(0.03, 0.05, 0.09, 0.92)
	dialog_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(dialog_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_overlay.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(470, 0)
	center.add_child(v)
	var t := _lbl(title, 24, Color(0.6, 1.0, 0.7))
	t.add_theme_font_override("font", F_BOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return v


func _show_save_dialog() -> void:
	if build_ctrl == null:
		return
	var v := _dialog_shell("Flugzeug speichern")
	v.add_child(_lbl("Name:", 14, Color(0.8, 0.85, 0.95)))
	var le := LineEdit.new()
	le.text = _slot_name
	le.custom_minimum_size = Vector2(470, 38)
	le.select_all_on_focus = true
	v.add_child(le)
	le.text_submitted.connect(func(_t): _do_save_slot(le.text))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var ok := Button.new(); ok.text = "Speichern"; ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.pressed.connect(func(): _do_save_slot(le.text))
	row.add_child(ok)
	var cancel := Button.new(); cancel.text = "Abbrechen"; cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_close_dialog)
	row.add_child(cancel)
	le.grab_focus()


func _do_save_slot(nm_raw: String) -> void:
	var nm := _safe_name(nm_raw)
	if nm == "":
		_toast("Bitte einen Namen eingeben")
		return
	_slot_name = nm
	_ensure_slot_dir()
	if _write_design(_slot_path(nm)):
		_write_design(SAVE_PATH)   # auch als aktuelles Autoload merken
		_toast("Gespeichert: " + nm + "")
	else:
		_toast("Speichern fehlgeschlagen")
	_close_dialog()


func _show_load_dialog() -> void:
	var v := _dialog_shell("Flugzeug laden")
	v.add_child(_lbl("Vorlagen", 14, Color(0.82, 0.9, 1.0)))
	for pr in PRESETS:
		var pb := Button.new()
		pb.text = pr[1]
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.pressed.connect(_do_load_preset.bind(pr[0], pr[1]))
		v.add_child(pb)
	v.add_child(HSeparator.new())
	v.add_child(_lbl("Eigene Flugzeuge", 14, Color(0.82, 0.9, 1.0)))
	var slots := _list_slots()
	if slots.is_empty():
		v.add_child(_lbl("(noch keine gespeichert — über »Speichern« anlegen)", 12, Color(0.7, 0.7, 0.78)))
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(470, minf(slots.size() * 56.0, 300.0))
		v.add_child(scroll)
		var sv := VBoxContainer.new()
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_theme_constant_override("separation", 6)
		scroll.add_child(sv)
		for nm in slots:
			var hb := HBoxContainer.new()
			hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_theme_constant_override("separation", 8)
			sv.add_child(hb)
			# 3D-Vorschau des gespeicherten Flugzeugs
			hb.add_child(_make_design_thumb(_read_design_parts(_slot_path(nm))))
			var lb := Button.new()
			lb.text = nm
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lb.size_flags_vertical = Control.SIZE_EXPAND_FILL
			lb.pressed.connect(_do_load_slot.bind(nm))
			hb.add_child(lb)
			var db := Button.new()
			db.text = "Entf."
			db.tooltip_text = "Löschen"
			db.size_flags_vertical = Control.SIZE_EXPAND_FILL
			db.pressed.connect(_do_delete_slot.bind(nm))
			hb.add_child(db)
	var close := Button.new(); close.text = "Schließen"
	close.pressed.connect(_close_dialog)
	v.add_child(close)


func _do_load_preset(id: String, title: String) -> void:
	if _load_design_from("res://designs/%s.json" % id):
		# Vorlagenname als Flugzeugname uebernehmen — die Praesentationstafel zeigt ihn
		# gross an. Eigene Slots taten das schon, Vorlagen bisher nicht.
		_slot_name = title.split("  ·  ")[0]
		_write_design(SAVE_PATH)
		_toast("Geladen: " + title)
	else:
		_toast("Vorlage nicht gefunden: " + id)
	_close_dialog()


func _do_load_slot(nm: String) -> void:
	if _load_design_from(_slot_path(nm)):
		_slot_name = nm
		_write_design(SAVE_PATH)
		_toast("Geladen: " + nm)
	else:
		_toast("Konnte nicht laden: " + nm)
	_close_dialog()


func _do_delete_slot(nm: String) -> void:
	DirAccess.remove_absolute(_slot_path(nm))
	_toast("Gelöscht: " + nm)
	_show_load_dialog()   # Dialog mit aktualisierter Liste neu aufbauen


func _load_design() -> bool:
	return _load_design_from(SAVE_PATH)


# Lädt ein Design aus beliebigem Pfad (Speicherstand ODER Vorlage in res://designs/).
func _load_design_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_ARRAY or data.is_empty():
		return false
	var arr: Array = []
	for it in data:
		if typeof(it) == TYPE_DICTIONARY and it.has("id") and typeof(it.get("xform")) == TYPE_ARRAY:
			var col := Color(0, 0, 0, 0)
			if it.has("color") and typeof(it["color"]) == TYPE_ARRAY and it["color"].size() >= 4:
				var ca: Array = it["color"]
				col = Color(ca[0], ca[1], ca[2], ca[3])
			var scl := Vector3.ONE
			if it.has("scale") and typeof(it["scale"]) == TYPE_ARRAY and it["scale"].size() >= 3:
				var sa: Array = it["scale"]
				scl = Vector3(sa[0], sa[1], sa[2])
			var tp: float = float(it.get("taper", 1.0))
			var tpf: float = float(it.get("taper_front", 1.0))
			var tpy: float = float(it.get("taper_y", -1.0))
			var tpfy: float = float(it.get("taper_front_y", -1.0))
			# Von Hand geformte Werte zurueckholen (siehe _design_data). Fehlen sie in der
			# Datei, ist es ein ALTER Speicherstand -> Standard, und die tuser-Flags bleiben
			# ABWESEND, damit die bestehende Alt-Save-Erkennung im BuildController greift.
			var bscv := Vector3.ONE
			if typeof(it.get("bsc")) == TYPE_ARRAY and (it["bsc"] as Array).size() >= 3:
				var ba: Array = it["bsc"]
				bscv = Vector3(ba[0], ba[1], ba[2])
			var eintrag: Dictionary = {"id": it["id"], "xform": _array_to_xform(it["xform"]),
				"color": col, "scale": scl, "taper": tp, "taper_front": tpf,
				"taper_y": tpy, "taper_front_y": tpfy,
				"glen": float(it.get("glen", 1.0)),
				"br": it.get("br", []), "bsc": bscv,
				"sf": _array_to_vec2(it.get("sf")), "sb": _array_to_vec2(it.get("sb")),
				"fill": float(it.get("fill", 0.0)),
				"thrust_reverse": bool(it.get("thrust_reverse", false))}
			if it.has("tuser_f") or it.has("tuser_b"):
				eintrag["tuser_f"] = bool(it.get("tuser_f", false))
				eintrag["tuser_b"] = bool(it.get("tuser_b", false))
			arr.append(eintrag)
	if arr.is_empty():
		return false
	build_ctrl.load_design(arr)
	return true


# [x, y] aus der Datei -> Vector2 (fehlt/kaputt -> Null, also kein Versatz).
func _array_to_vec2(v) -> Vector2:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		var a: Array = v
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


func _xform_to_array(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z,
		t.origin.x, t.origin.y, t.origin.z]


func _array_to_xform(a: Array) -> Transform3D:
	# Korruptes/verkürztes JSON darf das Laden nicht crashen -> Identität als Fallback.
	if a.size() < 12:
		push_warning("Design: ungültige xform (%d Werte) — ersetze durch Identität" % a.size())
		return Transform3D.IDENTITY
	for v in a:
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			push_warning("Design: nicht-numerische xform — ersetze durch Identität")
			return Transform3D.IDENTITY
	return Transform3D(
		Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])),
		Vector3(a[9], a[10], a[11]))


# ===========================================================================
# Start-Flugzeug
# ===========================================================================
# Anfangsfahrzeug: WWI-Doppeldecker mit Propeller (Rotor) und einem langsamen MG.
func _default_design() -> Array:
	var red := Color(0.62, 0.16, 0.13)
	var wood := Color(0.34, 0.27, 0.18)
	var d: Array = []
	var col := func(id: String, t: Transform3D, c: Color) -> void:
		d.append({"id": id, "xform": t, "color": c})
	# Rumpf + Rotor (Mittellinie)
	col.call("cockpit", Transform3D(Basis(), Vector3(0, 0, 0)), red)
	col.call("nose", Transform3D(Basis(), Vector3(0, 0, -2.0)), red)
	col.call("fuselage", Transform3D(Basis(), Vector3(0, 0, 2.1)), red)
	col.call("tailcone", Transform3D(Basis(), Vector3(0, 0, 4.0)), red)
	col.call("prop_engine", Transform3D(Basis(), Vector3(0, 0, -3.65)), red)

	var wb := build_ctrl._orient_to_normal(Vector3.RIGHT)
	# Doppeldecker: untere + obere Tragfläche (je gespiegelt)
	for yy in [-0.10, 1.40]:
		var wt := Transform3D(wb, Vector3(0.65, yy, 0.3))
		col.call("wing_straight", wt, red)
		col.call("wing_straight", build_ctrl._mirror_xform(wt), red)
	# Streben verbinden obere & untere Fläche (sonst schwebt die obere frei)
	for xx in [1.0, 2.2]:
		var st := Transform3D(Basis(), Vector3(xx, 0.65, 0.3))
		col.call("strut", st, wood)
		col.call("strut", build_ctrl._mirror_xform(st), wood)
	# Leitwerk
	var ht := Transform3D(wb, Vector3(0.55, 0.0, 4.1))
	col.call("h_stab", ht, red)
	col.call("h_stab", build_ctrl._mirror_xform(ht), red)
	# Seitenflosse: Hinterkante (Ruder) hinten (+Z). _orient_to_normal(UP) dreht die Sehne verkehrt.
	col.call("v_stab", Transform3D(Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)), Vector3(0, 0.55, 4.2)), red)
	# Eine langsame Waffe (MG oben am Rumpf)
	d.append({"id": "mg", "xform": Transform3D(Basis(), Vector3(0, 0.55, -1.2))})
	# Festes Fahrwerk: 2 Haupträder + Hecksporn
	d.append({"id": "wheel", "xform": Transform3D(Basis(), Vector3(1.3, -1.05, 0.3))})
	d.append({"id": "wheel", "xform": Transform3D(Basis(), Vector3(-1.3, -1.05, 0.3))})
	d.append({"id": "wheel_light", "xform": Transform3D(Basis(), Vector3(0, -0.85, 3.7))})
	return d


# ===========================================================================
# UI-Helfer
# ===========================================================================
func _lbl(text: String, size: int = 14, color: Color = Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", F_SEMI)   # crisp: Projekt-Font statt weicher Default-Font
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	return l


# Kleine, dezente Sektions-Überschrift fürs Bau-Panel (mehr Struktur/Übersicht).
func _section(text: String) -> Label:
	var l := _lbl(text, 11, Color(0.52, 0.68, 0.92))
	l.add_theme_font_override("font", F_BOLD)
	return l


# --- Runde Emoji-Icon-Buttons (Kategorie-Reiter + untere Leiste) -------------------
func _make_icon_btn(icon_path: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(54, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.expand_icon = false
	var tex: Texture2D = load(icon_path)
	if tex != null:
		b.icon = tex
	_style_icon_active(b, false)
	return b


# Kategorie-Icon (momentan): grau, aktiv = orange.
func _style_icon_active(b: Button, active: bool) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.90, 0.51, 0.10) if active else Color(0.92, 0.93, 0.96)
	n.set_corner_radius_all(25)
	n.set_content_margin_all(3)
	var h: StyleBoxFlat = n.duplicate()
	if not active:
		h.bg_color = Color(1, 1, 1)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", n)
	b.add_theme_stylebox_override("focus", n)
	var fc := Color(1, 1, 1) if active else Color(0.10, 0.12, 0.16)
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	# Icon (weißes SVG) einfärben: dunkel auf hellem Kreis, weiß auf orange aktiv.
	for ic in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		b.add_theme_color_override(ic, fc)


# Toggle-Icon (Snapping-Magnet): aus = grau, an = orange (über die pressed-Stylebox).
func _style_icon_toggle(b: Button) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.92, 0.93, 0.96)
	n.set_corner_radius_all(25)
	n.set_content_margin_all(3)
	var p := StyleBoxFlat.new()
	p.bg_color = Color(0.90, 0.51, 0.10)
	p.set_corner_radius_all(25)
	p.set_content_margin_all(3)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", n)
	b.add_theme_color_override("font_color", Color(0.10, 0.12, 0.16))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	var off := Color(0.10, 0.12, 0.16)
	b.add_theme_color_override("icon_normal_color", off)
	b.add_theme_color_override("icon_hover_color", off)
	b.add_theme_color_override("icon_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("icon_focus_color", off)


# Toggle-Pille (Mirror/Spiegeln): aus = dunkel, an = orange.
func _style_pill_toggle(b: Button) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.16, 0.20, 0.28, 0.96)
	n.set_corner_radius_all(12)
	n.set_content_margin_all(8)
	var p := StyleBoxFlat.new()
	p.bg_color = Color(0.90, 0.51, 0.10, 0.98)
	p.set_corner_radius_all(12)
	p.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("focus", n)
	b.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("icon_normal_color", Color(0.85, 0.9, 1.0))
	b.add_theme_color_override("icon_hover_color", Color(0.95, 0.97, 1.0))
	b.add_theme_color_override("icon_pressed_color", Color(1, 1, 1))


func _on_cat_icon(idx: int) -> void:
	_active_cat = idx
	_show_tools = false
	if parts_view: parts_view.visible = true
	if tools_view: tools_view.visible = false
	_fill_part_grid()
	_refresh_cat_icons()
	_refresh_tool_ui()


func _on_tools_icon() -> void:
	_show_tools = true
	if parts_view: parts_view.visible = false
	if tools_view: tools_view.visible = true
	_refresh_cat_icons()


func _refresh_cat_icons() -> void:
	for i in _cat_icon_btns.size():
		_style_icon_active(_cat_icon_btns[i], (not _show_tools) and i == _active_cat)
	if tools_icon_btn:
		_style_icon_active(tools_icon_btn, _show_tools)


func _panel(bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# Glas-Optik: dunkler Grund + feiner Akzentrand statt flacher schwarzer Box
	sb.bg_color = Color(0.05, 0.08, 0.12, maxf(bg.a, 0.55)) if bg.r + bg.g + bg.b < 0.2 else bg
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.45, 0.72, 1.0, 0.22)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _rect(c: Control, al: float, at: float, ar: float, ab: float,
		ol: float, ot: float, oright: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = oright
	c.offset_bottom = ob
