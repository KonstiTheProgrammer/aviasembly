## SEED-BASIERTES TERRAIN: riesige, deterministische Low-Poly-Landschaft.
## FastNoiseLite-fBm-Höhenfeld, in CHUNKS um den Spieler gestreamt. Mesh +
## Trimesh-Kollision entstehen auf einem WORKER-THREAD (ein Chunk kostet
## gemessen 12,4 ms — auf dem Main-Thread riss das bei 120 fps jedes Mal den
## Frame). Der Main-Thread hängt nur fertige Daten ein: 10 us je Chunk.
##
## WAS DEN NACHLADERUCK WIRKLICH VERURSACHT HAT (gemessen mit
## tools/_ruck_check.gd, 2700 Frames Reiseflug — NICHT das Einhängen, wie
## lange vermutet). Streaming-Zeit am Main-Thread je Frame:
##                       vorher      nachher
##   Mittel              1377 us      294 us
##   p99                 5314 us     1152 us
##   schlimmster Frame   8143 us     3237 us
##   Frames über 4 ms       112           0
## Die drei Ursachen, jede an ihrer Stelle ausführlich belegt:
##   1. mesh.create_trimesh_shape() im Worker — ein synchroner Rückruf in den
##      Renderer, der obendrein beim Beenden zuverlässig verklemmte.
##   2. Zwei Pflegeschleifen, die JEDEN Frame über ALLES liefen (siehe
##      PFLEGE_SCHEIBEN und _chunks_pflegen).
##   3. Der BVH-Aufbau der Kollisionsform (siehe KOLL_SCHRITT).
## Und ein Fehler, der KEIN Ruckeln war, sondern fehlende Bäume: ein `return`
## in _process übersprang das Nachziehen der Bepflanzung (siehe dort).
## Flatshading mit Höhen-/Hangfarben über Vertex-Colors (Sand/Gras/Fels/
## Schnee), FLUGPLÄTZE werden ins Gelände EINGEEBNET (Höhe -> exakt 0 im
## Innenradius, weicher Übergang außen). Nahe dem Ursprung sanfte Wiesen,
## mit der Entfernung echte Berge (~110 m + Schneegipfel). MEER bei y=-6
## (Kollision: WorldBoundary-Boden in Main als Sicherheitsnetz).
## FALLEN (gelernt): Godot-Front-Faces = im Uhrzeigersinn von außen (sonst
## cullt ALLES von oben); Steilheits-Farbe über |n.y|; StandardMaterial3D
## ignorierte Vertex-Farben -> Mini-Shader ALBEDO=COLOR.
class_name TerrainWorld
extends Node3D

const CHUNK := 384.0            # Kantenlänge eines Chunks (m)
const CELLS := 48               # Zellen pro Kante (8 m Raster -> Low-Poly-Look)
const VIEW_DIST := 3800.0       # Chunks innerhalb dieses Radius werden geladen
# Ab hier werden Baeume und Felsen nicht mehr GEZEICHNET. Sie bleiben im Chunk und
# erscheinen beim Naeherkommen von selbst wieder — im Gegensatz zum Weglassen beim Bauen
# braucht es dafuer keinen Neuaufbau. Ohne das Limit kosten 3800 m Sichtweite pro Chunk
# bis zu acht zusaetzliche Draw-Calls, von denen man auf 3 km ohnehin nichts erkennt.
const FLORA_DIST := 3200.0
const FLORA_FADE := 900.0       # Laenge des Schrumpf-Uebergangs (siehe _flora_mat)
# Ab hier ist jede Instanz auf Groesse 0 gefahren. MUSS um mindestens eine halbe
# Chunk-Diagonale (271 m) unter FLORA_DIST liegen: visibility_range_end misst vom
# CHUNK-Mittelpunkt, das Schrumpfen dagegen pro Baum. Ohne den Abstand wuerde die
# nahe Chunk-Ecke mit noch sichtbaren Baeumen weggeschnitten — genau das Aufpoppen,
# das hier vermieden werden soll.
const FLORA_FADE_END := 2900.0
# --- FLORA-SPARSTUFEN ------------------------------------------------------------------
# Ab dieser Entfernung bekommt ein Chunk die grobe Baumfassung und nur noch einen Teil
# seiner Pflanzen. GEMESSEN, warum das noetig ist: die Flora kostet 4,65 von 7,86 ms je
# Bild (59 %) und stellt 5,46 von 7,35 Mio Primitiven (74 %).
# 1100 m ist so gewaehlt, dass die Umschaltung hinter der Strecke liegt, auf der man
# einen einzelnen Baum ueberhaupt als Baum erkennt.
const FLORA_GROB_AB := 1700.0
# Anteil der Pflanzen, der jenseits davon noch gezeichnet wird. Die Transformationen
# stehen in zufaelliger Reihenfolge im Puffer, ein Praefix ist also eine gleichmaessige
# Stichprobe der Flaeche — deshalb genuegt visible_instance_count und es muss nichts
# neu gebaut werden.
const FLORA_GROB_ANTEIL := 0.75
# Zeitbudget je Frame fuer das Nachziehen aufgeschobener Flora (Mikrosekunden).
# 1200 us ist rund ein Vierzehntel eines 60-Hz-Frames: genug, damit ein Chunk in wenigen
# Frames vollstaendig bestueckt ist, wenig genug, um im Bild nicht aufzufallen.
const FLORA_BUDGET_US := 1200.0
# Hoechstens so viele Flora-MultiMeshes je Frame einhaengen — Stueckzahl-Deckel ZUSAETZLICH
# zum Zeitbudget, weil ein einzelner Eintrag es weit ueberschreiten kann (siehe dort).
const FLORA_PRO_FRAME := 2

# --- KOLLISIONSRADIUS ------------------------------------------------------------------
# Nur Chunks innerhalb dieses Radius bekommen einen Physikkoerper. Vorher bekam JEDER
# geladene Chunk einen: bei VIEW_DIST 3800 m sind das rund 364 Chunks zu je 4608
# Kollisionsdreiecken, also ueber 1,6 Millionen Dreiecke in der Physikwelt — fuer ein
# Flugzeug, das nur in seiner unmittelbaren Umgebung ueberhaupt etwas beruehren kann.
# 1200 m sind reichlich bemessen: selbst mit 170 m/s dauert es sieben Sekunden bis dorthin,
# und das Nachladen schafft rund 20 Chunks je Sekunde. Die Flaeche schrumpft damit auf
# (1200/3800)^2 = 10 Prozent.
const KOLLISIONS_DIST := 1200.0
# --- KOLLISIONSRASTER -------------------------------------------------------------------
# Nur jeder KOLL_SCHRITT-te Punkt des Hoehenrasters geht in die Kollisionsflaeche. Das
# Sichtnetz bleibt fein (48x48 a 8 m), die Physik bekommt 24x24 a 16 m.
# WARUM: der BVH-Aufbau der Form ist der letzte grosse Posten im Nachladeruck, und er
# haengt an der Dreieckszahl. Er laesst sich NICHT auf den Worker verlagern — gemessen
# kostet dort set_faces() 0 us, Godot stellt die Daten also nur ein und baut den Baum erst,
# wenn die Form an einen Koerper geht. Das passiert zwangslaeufig am Main-Thread.
# WAS ES KOSTET (tools/_koll_fehler.gd, Abweichung der Kollisionsflaeche vom sichtbaren
# Boden, fuenf Gebiete von der Kueste bis ins Gebirge):
#   Schritt   Dreiecke   Fehler im Mittel   schlimmster Punkt   am Flugplatz
#      1        4608          0.00 m              0.00 m           0.00 m
#      2        1152          0.10 m              5.89 m           0.04 m
#      3         512          0.22 m              7.54 m           0.07 m
#      4         288          0.32 m              8.80 m           0.11 m
# Schritt 2 ist der Knick: vier Mal weniger Dreiecke fuer zehn Zentimeter. Entscheidend
# ist die letzte Spalte — der Flugplatz ist eingeebnet, dort sind alle vier Eckwerte
# gleich, und die grobe Flaeche trifft ihn exakt. Am LANDEN aendert sich also nichts.
# Die grossen Einzelfehler stehen im zerklueftetsten Huegelland; dort faellt ein halber
# Flugzeugdurchmesser nicht auf, weil man da ohnehin nicht aufsetzt.
const KOLL_SCHRITT := 2

# --- RUNDGANG ---------------------------------------------------------------------------
# Physikkoerper und Flora-Sparstufe haengen beide nur am ABSTAND eines Chunks zum Spieler.
# Beide wurden frueher jeden Frame ueber den ganzen Bestand geprueft — und genau das war,
# entgegen der naheliegenden Vermutung, der Nachladeruck. GEMESSEN ueber 2700 Frames
# Reiseflug (170 m/s, 400 m Hoehe, tools/_ruck_check.gd):
#     Abschnitt        Mittel je Frame   schlimmster Frame
#     Flora-Sparstufe        963 us            5863 us
#     Kollisionspflege       329 us            4167 us
#     Chunk einhaengen         5 us              61 us
# Das EINHAENGEN eines Chunks kostet also nichts mehr; die beiden Pflegelaeufe kosteten
# alles. Drei Gruende, alle behoben:
#   1. Die Flora lief ueber JEDE MultiMeshInstance (bis zu 4000) statt ueber jeden Chunk
#      (364) — obwohl alle Pflanzen eines Chunks denselben Abstand haben.
#   2. Sie las dabei mmi.global_position, was die Welttransformation neu ausrechnet, und
#      die Kollisionspflege fragte has_node("Kollision") — eine Suche ueber einen Pfadnamen.
#      Jetzt: eine Zahl aus der Chunkmitte und ein Merker am Knoten.
#   3. Ueberquerten viele Chunks dieselbe Grenze im selben Frame, kippten sie alle
#      gleichzeitig. Der Rundgang laeuft jetzt in Scheiben, und Physikkoerper entstehen
#      gedeckelt.
# Ein voller Rundgang dauert damit sechs Frames = 0,1 s = 17 m Flug. Die naechste Grenze
# liegt 1200 m entfernt; spaeter als noetig kommt hier nichts.
const PFLEGE_SCHEIBEN := 6
# Hoechstens so viele Physikkoerper je Frame einfuegen. Einer kostet rund 0,4 ms — der
# Deckel haelt die Spitze bei 0,8 ms, und 2 je Frame sind 120 je Sekunde gegenueber den
# rund 9, die beim Ueberqueren einer Chunkzelle wirklich anfallen.
const PFLEGE_BAU_PRO_FRAME := 2
# Hoechstens so viele Chunks duerfen je Frame ihre Flora-Sparstufe wechseln (siehe dort).
const PFLEGE_STUFE_PRO_FRAME := 1
# Totbaender. Ohne sie kippt ein Chunk, der genau auf der Grenze liegt, bei jedem
# Rundgang hin und her — und jedes Kippen kostet einen Physik-Einfuegevorgang bzw. einen
# Netzwechsel an der MultiMesh.
const KOLL_HYSTERESE := 90.0
const FLORA_HYSTERESE := 120.0
# GEMESSEN (1280x720, VSync aus, Reiseflug 400 m ueber Land, Blick in die Ferne):
#                       Bildzeit   Primitive
#   ohne Sparstufen     7,86 ms    7.354.668
#   mit Sparstufen      5,52 ms    6.273.904
# Die Flora selbst faellt damit von 4,65 auf 2,38 ms je Bild — knapp die Haelfte.
# ACHTUNG BEIM MESSEN: mit VSync sieht man davon NICHTS. Alle Faelle lagen dann auf
# exakt 8,33 ms, also 1/120 s. Wer hier nachmisst, schaltet VSync zuerst ab.
# Bewuchs-Raster: gesampelt wird auf dem Mesh-Hoehenraster (8 m). Erwartete Baeume je
# Zelle bei voller Walddichte. 2.3 / 64 m^2 sind rund 5,3 m Standabstand — dichter als die
# vorigen 1.6 (6,3 m), der Wald schliesst sich also staerker.
# NICHT AM FERNFELD SPAREN — das war ein Fehlgriff. Erst stand FLORA_GROB_ANTEIL bei 0.45,
# um die hoehere Dichte gegenzurechnen. Beim Ueberfliegen einer Insel liegt aber praktisch
# die GANZE Insel jenseits von FLORA_GROB_AB, also im ausgeduennten Bereich: der Wald sah
# dadurch duenner aus als vor der Verdichtung, obwohl im Nahfeld mehr Baeume standen.
# Gespart wird stattdessen ueber die grobe Meshfassung, die dort ohnehin greift.
const FLORA_PER_CELL := 2.3
# Baumgrenze. 64 m war viel zu tief: die Vulkaninsel IST ein Berg, ihr Hang liegt fast
# vollstaendig darueber — im Ueberflug stand der Wald deshalb nur als schmaler gruener Ring
# am Strand, der ganze Kegel war kahl braun. Genau das las sich als "zu wenig Baeume".
# 230 m laesst den Wald die Flanken hochwachsen und haelt nur die Kuppen frei, so wie in
# den Referenzbildern: bewaldete Haenge, felsiger Gipfel.
const FLORA_MAX_H := 230.0
# Untergrenze. NICHT 0.8 wie frueher: gemessen liegen 47.9 % der Flaeche im 8x8-km-Feld
# um den Spawn zwischen -4.4 m (Ende der Sandfarbe) und 0.8 m — flaches, GRUENES Tiefland,
# das die alte Schwelle komplett ausgesperrt hat. Genau das war die kahle Ebene. Der
# Meeresspiegel liegt bei -6, die Wasserplatte bei -5.85; -4.0..-2.2 laesst einen schmalen
# Strandsaum frei, ohne die Ebene zu opfern.
const FLORA_MIN_H := -4.0
const FLORA_FULL_H := -2.2      # ab hier volle Dichte
const CLEAR_CAP := 620.0        # groesster Freihalte-Radius um eine KREIS-Zone (Stadt, Dorf, …)
# FREIHALTUNG NACH BEBAUUNG statt nach Radius — nur fuer Zonen, die "rects" mitbringen
# (die Flugplaetze, siehe Main._setup_world). Gemessen wird der Abstand zum RAND der
# bebauten Rechtecke, nicht zum Platzmittelpunkt: bis FREI_INNEN bleibt alles frei, ab
# FREI_AUSSEN steht wieder voller Bewuchs. 20/50 m sind aus den Vorlagen abgelesen — in
# heimat_1 und heimat_4 stehen die ersten Nadelbaeume 20 bis 40 m neben der Bahnkante
# (= 35 bis 55 m von der Bahnachse), und die Bahn samt Sandschulter ist 45 m breit.
const FREI_INNEN := 20.0
const FREI_AUSSEN := 50.0
const SEA_Y := -6.0             # Meeresspiegel (Main legt dort die Kollisionsebene hin)
# Fertige Chunks je Frame einhaengen. Stand lange auf 1, begruendet mit den Kosten des
# Physik-Einfuegens — das stimmt nicht mehr: Kollisionskoerper entstehen inzwischen im
# Rundgang und nicht mehr hier (frisch gelieferte Chunks liegen am Sichtrand, weit
# jenseits von KOLLISIONS_DIST). Gemessen kostet ein Einhaengen noch 5 us.
# 1 je Frame waren 60 je Sekunde und lagen damit UNTER dem, was der Worker liefert
# (gemessen 80,9 je Sekunde, siehe tools/_worker_takt.gd) — nach einem Schwall staute
# sich also _done auf. 3 je Frame raeumen den Schwall ab, ohne die Spitze zu erhoehen;
# bei 6 stieg der schlimmste Frame von 3,9 auf 6,7 ms.
const MAX_ATTACH_PER_FRAME := 3

# --- VULKANKEGEL -------------------------------------------------------------------------
# Diese drei Zahlen stehen NICHT in der Massivtabelle, weil sie nicht einen bestimmten Berg
# beschreiben, sondern wie das vorhandene Rauschen in POLARKOORDINATEN abgetastet wird.
# Abgetastet wird immer auf einem KREIS im Rauschraum (Einheitsrichtung mal Kreisradius) —
# damit gibt es keine Naht bei +-pi, wie sie ein atan2 als Rauschachse unweigerlich
# hinterlaesst: dort spraenge das Muster, und der Sprung staende als kerzengerade Kante vom
# Gipfel bis zum Fuss im Hang.
# Die Kreisradien folgen aus der Frequenz der jeweiligen Rauschquelle und werden in setup()
# einmal ausgerechnet (_vk_rippen_kreis, _vk_lippen_kreis) — wer die Frequenz aendert, zieht
# sie damit automatisch mit.
# RIPPEN_N ist die Zahl der Hauptgrate rund um den Kegel. Das ist die Grundoktave; _ridge
# hat vier davon, die feineren Rippen entstehen von selbst.
# HIER STAND 10, UND DAS WAR ZU VIEL. Der Kreis wird in NOISE-Einheiten abgetastet, die
# Winkelwellenlaenge in METERN schrumpft also mit dem Abstand zum Gipfel — genau das sollen
# radiale Grate tun, sie laufen ja zusammen. Bei zehn Grundrippen ist die vierte Oktave am
# Kraterrand aber nur noch 27 m breit, also drei Netzzellen: im Bild wurde daraus ein
# feiner Cordsamt, der von jeder Entfernung wie eine gebuerstete Oberflaeche aussah statt
# wie Grate.
# FUENF WAREN DANN ZU WENIG: eine Rippe war auf halber Flanke 1000 m breit, und ein Buckel
# von 55 m auf 500 m Halbwelle kippt die Flaechennormale um sechs Grad. Bei Flachschattierung
# ist das nichts — der Kegel sah aus wie mit Schokolade uebergossen.
# ZEHN GEHEN ERST, SEIT DER KREIS MIT DEM ABSTAND WAECHST (siehe unten): die Zahl gilt am
# FUSS, oben wird das Muster von selbst grober.
const VULKAN_RIPPEN_N := 10.0
# Wie schnell das Rippenmuster hangabwaerts wandert (dritte Rauschachse, Meter -> Rauschmass).
# 0 gaebe kerzengerade Speichen wie auf einem Beachball, zu viel loest die Grate wieder in
# richtungslose Flecken auf — genau das war der Zustand vorher, als das Gratrauschen in
# KARTESISCHEN Koordinaten abgetastet wurde. Seit der Kreis mit dem Abstand waechst, wandert
# das Muster ohnehin schon quer, deshalb steht der Wert niedriger als die anfaenglichen 1.1.
const VULKAN_RIPPEN_LAUF := 0.8
# Anteil der Rippenamplitude, der AN DER LIPPE noch steht.
# HIER STAND NULL, und das war der Grund fuer den letzten Abnahmefehler: um den Krater lag
# ein rund 200 m breites Band, in dem die Flanke glatt anlief, und darueber sass ein
# gedrechselter Ring. Aus der Ferne las sich das als Tafelberg mit sauber abgedrehter
# Krone — die Grate schienen erst auf halber Hoehe anzufangen, als klebte der Gipfel auf
# dem Berg statt aus ihm zu wachsen.
# Jetzt beissen dieselben Rippen, die die Flanke aufrauen, oben in die Lippe. Das macht die
# Krone gezackt, ohne dass ihre HOEHE stark schwankt: bei 44 m Rippenamplitude rund 17 m auf
# 650, gut zwei Prozent. Voll aufdrehen darf man es nicht — bei 1.0 waeren es +-37 m, und
# ein Wall, der um ein Zehntel seiner Hoehe wackelt, reisst optisch auf.
# DASS DIE ZACKEN TROTZ DER KLEINEREN AMPLITUDE BLEIBEN, ist der Grund, warum "fels" in der
# Massivtabelle zugleich von 22 auf 30 gegangen ist: die Felslage haengt an sv und steht
# oben am staerksten, sie traegt den Rand jetzt mit.
# Nach INNEN laeuft derselbe Wert an der Kraterwand aus und rillt sie: die Referenz zeigt
# genau das, senkrechte Streifen in der Innenwand, keine glatte Schuessel.
# --- DIE FEINRIPPEN: DIE ZWEITE, VIEL DICHTERE LAGE AUF DEMSELBEN KREIS -------------------
# WARUM ES SIE BRAUCHT, UND ZWAR AUS EINEM BILDVERGLEICH. Ein Zwischenstand dieser Runde
# hatte die Zielzahl der Abnahme erreicht (lokale Streuung 0.0348 gegen 0.030 gefordert) und
# sah trotzdem falsch aus: die Aufhellung sass als RUNDE, ISOLIERTE Flecken auf der Flanke,
# im Bild ein aufgestreuter Kies. Die Vorlage macht es anders — ihr helles Gestein bildet
# LANGE, HANGPARALLELE Baender mit dunklen Rinnen dazwischen. Der Unterschied ist nicht die
# Amplitude und nicht die Groesse, sondern die RICHTUNG: eine isotrope Rauschlage kann keine
# Baender machen, egal wie fein man sie stellt.
# 3.4 IST DER FAKTOR AUF DEN RIPPENKREIS, also rund 34 Grundrippen statt zehn. Am Fuss sind
# das rund 250 m je Rippe, auf halber Flanke gut 130 — und weil _ridge vier Oktaven hat,
# liegt die sichtbare Gliederung darunter. Das trifft die Baenderbreite der Vorlage.
# WEITER HINAUF DARF ES NICHT: bei zehn Grundrippen war schon die vierte Oktave am
# Kraterrand nur 27 m breit und das Bild wurde zu Cordsamt (siehe VULKAN_RIPPEN_N). Bei 34
# gilt dieselbe Rechnung fuer die ZWEITE Oktave — was darunter liegt, faellt unter die
# Netzweite und darf deshalb nur noch faerben, nicht mehr Gelaende machen. Genau deshalb
# steht die Amplitude in der Massivtabelle niedrig und die Aufhellung dazu hoch.
const VULKAN_FEINRIPPE_N := 3.4
# WIE SCHNELL DAS MUSTER DEN HANG HINUNTERWANDERT. Deutlich schneller als bei den groben
# Rippen (0.8), und das ist der eigentliche Griff fuer die BANDFORM: quer schmal, laengs
# lang. Bei gleichem Lauf waeren es wieder Flecken, nur mehr davon.
const VULKAN_FEINRIPPE_LAUF := 2.2
# WIE HELL DER FEINE KAMM STEHT. Er darf fuehren wie der grobe, denn unter ihm liegt
# dieselbe Sorte Form — die Schwelle laesst nur das obere Drittel der Verteilung heraus,
# damit aus Baendern keine flaechige Aufhellung wird.
const VULKAN_FEINRIPPE_AB := 0.34
const VULKAN_FEINRIPPE_VOLL := 0.78
const VULKAN_FEINRIPPE_HELL := 0.72
const VULKAN_RIPPEN_LIPPE := 0.45
# Wo die Rippen INNEN anfangen, als Anteil des Kraterradius. 0.50 setzt sie knapp unterhalb
# der Sohlenkante an (VULKAN_SOHLE): die Innenwand bekommt ihre Rillen, die flache Sohle
# bleibt flach. Weiter nach innen zu gehen brachte nichts — dort ist der Abtastkreis so
# klein, dass aus den Rippen drei breite Beulen werden, und die sahen im Kraterboden aus
# wie ein liegengebliebener Schutthaufen.
const VULKAN_RIPPEN_INNEN := 0.50
# Zahl der Lappen, um die der Kraterrand aus dem Kreis wandert. Klein halten: das Rauschen
# bringt seine eigenen Oktaven mit, und eine Lippe mit acht Lappen liest sich als Zahnrad.
# 2.5 WAREN ZU WENIG, SEIT DER KRATER GEWACHSEN IST: bei 460 m Radius misst die Lippe
# 2900 m im Umfang, ein Lappen war damit 1150 m lang — also genau eine Seite, die ausbeult.
# Der Rand las sich als schief gedrechselter Ring statt als gezackte Lippe.
const VULKAN_LIPPEN_N := 3.5
# ZWEITE LAGE AUF DEMSELBEN RAND, feiner und schwaecher. Die 3.5 Lappen geben dem Krater
# seinen unrunden Grundriss, aber jeder einzelne Lappen ist ein 800 m langer, sauberer
# Bogen — im Umriss las sich der Rand deshalb wie mit dem Zirkel gezogen, nur eben aus drei
# Kreisen statt aus einem. Erst die feine Lage macht aus dem Bogen eine Kante.
# Zwei ganze Oktaven auseinander (Faktor 4) waeren zu weit: dann sitzen 14 Zacken auf dem
# Ring, jeder 200 m lang, und das ist wieder das Zahnrad. 2.8 liegt dazwischen.
const VULKAN_LIPPEN_ZACK_N := 2.8
const VULKAN_LIPPEN_ZACK := 0.40
# Wellenlaenge der feinen Felslage auf dem Kegel, in Metern. Sie ist RICHTUNGSLOS und
# ergaenzt die Rippen, statt mit ihnen zu konkurrieren: die Rippen geben dem Berg seine
# Gliederung, diese Lage gibt den einzelnen Flaechen ihre Neigung. Ohne sie bleibt der
# Kegel eine polierte Glasur, egal wie tief die Rinnen sind.
# 150 m sind bei 8 m Netzweite rund 19 Zellen je Welle — Facetten, die man aus der Luft
# als Fels liest. Deutlich darunter wird daraus Griess, der im Flug nur flimmert.
const VULKAN_FELS_M := 150.0
# --- DIE BLOCKLAGE: FELSAUFSCHLUESSE AUF DEN GRATEN ---------------------------------------
# DER BEFUND, DER SIE ERZWUNGEN HAT. Ein fremder Blick auf das letzte Abnahmebild: "Flanken
# sind strukturlos — glatte, einfarbig dunkelblau-schwarze Facetten ohne Felsaufschluesse
# oder Schuttbloecke". Nachgemessen an beiden Bildern (derselbe Ausschnitt der Mittelflanke,
# Lava und Gruen ausmaskiert) steckt der ganze Befund in ZWEI Zahlen:
#   MITTLERER HELLIGKEITSSPRUNG VON PIXEL ZU PIXEL   Vorlage 0.030, wir 0.008 — ein Viertel.
#   MEDIAN DER FLANKENHELLIGKEIT                     Vorlage 0.114, wir 0.209 — fast doppelt.
# Die Flanke ist also NICHT ZU DUNKEL, sie ist zu GLEICHMAESSIG. Ihr fehlen beide Enden: die
# tiefschwarzen Schattenschlitze ebenso wie die hell angeleuchteten Kanten dazwischen. Eine
# Farbe kann das nicht nachliefern — was einen Schlitz schwarz macht, ist eine Flaeche, die
# von der Sonne wegzeigt, und die muss im Hoehenfeld stehen.
# WARUM DIE VORHANDENEN LAGEN ES NICHT KOENNEN: Rippen (10 Wellen im Umfang), Felslage
# (150 m) und Barrancos (245 m am Fuss) sind alle GROSS gegen ein 8-m-Dreieck. Sie kippen
# eine Flaeche um wenige Grad je Zelle, ein Dutzend Nachbardreiecke zeigt also fast in
# dieselbe Richtung — daher die grossen glatten Facetten. Die Vorlage zeigt darunter
# Aufschluesse von 40 bis 80 m Breite mit voller eigener Fallhoehe: jeder ein paar Dreiecke
# gross, jeder mit einer besonnten und einer verschatteten Seite.
# 46 M SIND KNAPP SECHS ZELLEN — die kuerzeste Welle, die auf diesem Netz noch eine eigene
# Flanke hat, statt zur Zackenreihe zu werden. Darunter (32 m, vier Zellen) faellt sie in
# genau das Flimmern zurueck, vor dem schon VULKAN_FELS_M warnt.
const VULKAN_BLOCK_M := 46.0
# DIE SCHWELLE MACHT AUS EINEM TEPPICH EINZELNE AUFSCHLUESSE. Ohne sie liegt ueber der
# ganzen Flanke gleichmaessig Griess, und das ist wieder eine Textur statt einer Form. _ridge
# ist ridged, seine hohen Werte bilden von selbst zusammenhaengende Straenge; ab 0.34 bleibt
# davon rund ein Drittel der Flaeche uebrig, in Nestern verteilt, mit blanken Feldern
# dazwischen. Genau so sitzt der Fels in der Vorlage — verstreute Cluster, kein Belag.
# DIE OBERE SCHWELLE IST DER FEHLER, DEN DIESE ZEILEN ZUERST HATTEN, und er ist lehrreich:
# hier standen 0.34 / 0.95, gewaehlt "damit nur die staerksten Nester voll herauskommen".
# Gemessen (tools/_vulkan_form.gd) reicht die Blocklage aber nur bis 0.98, und ihr oberstes
# Zehntel faengt erst bei 0.63 an — ueber 0.95 lagen ganze 0.1 Prozent der Flaeche. KEIN
# EINZIGER BLOCK erreichte also seine 26 m, die mittlere Huelle stand bei 0.16, und im Bild
# war die Folge genau messbar: der Helligkeitssprung von Pixel zu Pixel stieg von 0.008 auf
# 0.013, gegen 0.030 in der Vorlage. Eine Schwelle, die am oberen Ende der Verteilung klebt,
# schaltet die Lage nicht scharf — sie schaltet sie aus.
# 0.24 / 0.64 SIND AN DER GEMESSENEN VERTEILUNG GEWAEHLT: rund drei Fuenftel der Flaeche
# tragen etwas, ein gutes Zehntel steht auf voller Hoehe. Das ist das Verhaeltnis der
# Vorlage — ueberwiegend Fels mit einzelnen glatten Baendern dazwischen, und darin die
# einzelnen Aufschluesse, die wirklich Schatten werfen.
const VULKAN_BLOCK_AB := 0.24
const VULKAN_BLOCK_VOLL := 0.64
# WIE VIEL DAVON IN DER RINNENSOHLE STEHENBLEIBT. Aufschluesse sitzen auf den Graten, in der
# Sohle liegt Schutt — und in der Sohle liegt auch die Lava (VULKAN_BARR_VERSATZ). Ein
# 18-m-Block mitten in einer 15 m breiten gluehenden Ader zerhackt sie zu einer Perlenkette,
# und genau das Aufgemalte, aus dem die Ader gerade herausgefuehrt wurde, waere zurueck.
# 0.30 laesst in der Sohle eine Koernung stehen, ohne den Kanal anzufassen.
const VULKAN_BLOCK_SOHLE := 0.30
# WO DIE BLOECKE AUFHOEREN, als Anteil des Fussradius — UND DAS IST KEINE GESCHMACKSFRAGE,
# SONDERN DIE BAUMGRENZE. Der Waldkragen sitzt gemessen zwischen 1020 und 1140 m (26 bis
# 82 m Hoehe), und die Bepflanzung duennt nach der NEIGUNG UEBER DER 8-M-ZELLE aus: ueber
# 4,6 m Hoehenunterschied je Zelle steht gar kein Baum mehr. 18 m Auswurf auf 46 m Welle
# sind rund 6 m je Zelle — Bloecke bis in den Kragen hinunter haetten den Ring, der in der
# Runde davor gerade erst geschlossen wurde (Deckung 0.85 im Median, kein einziges Loch),
# wieder aufgerissen. Sie laufen deshalb ueber 900 bis 1075 m aus und sind an der Oberkante
# des Kragens auf ein Siebtel herunter.
# NACH INNEN BRAUCHT ES KEINE SCHRANKE: der Aufschluss darf bis an die Lippe stehen, die
# Vorlage zeigt ihn dort am dichtesten. Die Rampe ab krx haelt ihn nur aus dem fertigen
# Kraterrand heraus, so wie es die Rinnen auch tun.
const VULKAN_BLOCK_AUS_AB := 0.72
const VULKAN_BLOCK_AUS_ZU := 0.86
# WIE HELL EIN AUFSCHLUSS STEHT. Er geht in DENSELBEN "blank"-Term wie Rippenkamm und
# Barranco-Grat und nicht als eigene Farbe daneben — blank ist blank, egal welche Lage die
# Flaeche aufgebrochen hat (dieselbe Begruendung wie bei VULKAN_HAUT_KRUME). Er DARF
# fuehren, denn unter ihm liegt Form: es ist Zeichen fuer Zeichen derselbe Ausdruck, mit dem
# height_at den Block auswirft. Genau das unterscheidet ihn von den beiden Rauschlagen, die
# als "helle Striemen" gemeldet wurden und seither nur noch koernen duerfen.
# 0.52 -> 0.72: mit dem kleineren Wert erreichte "blank" auf einem vollen Aufschluss nicht
# einmal die Haelfte, der Block blieb also im Basaltton stehen und war nur an seinem Schatten
# zu erkennen. Die Vorlage zeigt auf dem Aufschluss den HELLSTEN Ton der ganzen Flanke.
const VULKAN_BLOCK_HELL := 0.85
# --- BARRANCOS: DIE EROSIONSRINNEN DER FLANKE --------------------------------------------
# WARUM ES SIE BRAUCHT, OBWOHL SCHON RIPPEN AUF DEM HANG LIEGEN. Die Rippen sind eine
# RAUSCHLAGE: ridged, vier Oktaven, und die Oktaven 2 bis 4 liefern den Grossteil dessen,
# was man sieht. Im Abnahmebild las sich das als feiner, gleichfoermiger Striemen ueber
# einer sonst ungebrochenen Kegelflaeche — eine gebuerstete Oberflaeche, keine Gliederung.
# Rauschen kann das auch nicht leisten: es hat keine ZAEHLBARE Zahl von Rinnen, keine
# definierte Tiefe und keinen Ort, an dem eine Rinne anfaengt und aufhoert.
# Ein Barranco hat all das. Er faengt an der Lippe mit Tiefe null an, wird die Flanke
# hinunter tiefer, laeuft im Fuss-Apron aus, und zwischen zwei Rinnen steht ein GRAT.
# Deshalb steht hier eine gerechnete Winkelwelle und keine weitere Rauschlage.
#
# DAS ATAN2 IST HIER KEIN FEHLER, obwohl weiter oben steht, dass ein atan2 als Rauschachse
# eine Naht bei +-pi hinterlaesst. Der Unterschied ist die GANZE ZAHL: der Winkel geht nicht
# in ein Rauschen, sondern in eine periodische Welle mit VULKAN_BARR_N Perioden auf dem
# Vollkreis. Ueber die Naht springt die Phase um genau VULKAN_BARR_N, und der Nachkommateil
# — auf dem allein die Welle sitzt — merkt davon nichts. Die Zahl MUSS deshalb ganz sein,
# darum das round() in setup(); mit 30.5 staende dort die kerzengerade Kante vom Gipfel bis
# zum Fuss, vor der die Rippen gewarnt haben.
# 32 RINNEN sind an der Lippe (Umfang 2900 m) alle 91 m eine, auf halber Flanke alle 160 m,
# am Fuss alle 245 m — Rinnen, die nach unten breiter werden und nach oben zusammenlaufen,
# also genau das Fingermuster der Vorlage. Unter 24 wird der Kegel zum Zahnrad, ueber 40
# ist eine Rinne am Kraterrand schmaler als zehn Netzzellen und faellt in den Cordsamt
# zurueck, aus dem die Rippen gerade herausgeholt wurden.
# HIER STAND 30, UND DIE ZWEI MEHR SIND KEIN GESCHMACK: 32 ist EINE ZWEIERPOTENZ, und daran
# haengt das Lavanetz. Es ist ein Binaerbaum — acht Staemme am Kraterrand, zwei Gabelungen
# die Flanke hinunter, also 8 * 2^2 = 32 Enden. Nur wenn die Rinnenzahl durch JEDE Zellbreite
# des Baums teilbar ist, faellt eine Aderachse auf eine feste Stelle im Rinnenraster — welche
# das ist, entscheidet dann VULKAN_BARR_VERSATZ. Mit 30 laege sie in jeder Generation
# woanders, die Adern liefen also mal in einer Sohle und mal quer ueber einen Grat, und das
# ist wieder ein aufgemaltes Muster auf einer Form, die etwas anderes sagt.
const VULKAN_BARR_N := 32.0
# Die TIEFE steht als "barranco" in der Massivtabelle (Main), so wie "rippen" und "fels":
# sie beschreibt diesen einen Berg, waehrend die Zahlen hier beschreiben, WIE die Rinne
# gebaut ist. Fehlt der Schluessel, passiert nichts.
# Aufgetragen wird q*q (q = -1 Grat, 0 Sohle, +1 Grat), und q ist ueber die Zelle
# gleichverteilt — sein Quadrat hat damit das Mittel 1/3. GENAU DIESE ZAHL WIRD ABGEZOGEN,
# und deshalb steht sie hier als Konstante und nicht als 0.33 in der Zeile: sie ist der
# Grund, warum der Kegel im Mittel gleich hoch bleibt. Der Grat steigt um 2/3 der Tiefe,
# die Sohle faellt um 1/3, der Unterschied zwischen beiden ist die volle Tiefe.
# WARUM q*q UND KEIN DREIECK: an der Sohle (q = 0) ist die Steigung null, die Rinne bekommt
# also einen BODEN statt einer Schneide — dort soll die Lava liegen. Am Grat (|q| = 1)
# stossen zwei Parabeln mit voller Steigung aufeinander, das gibt den scharfen Kamm. Ein
# Dreieck haette es genau andersherum gemacht: spitze Rinne, runder Grat.
const VULKAN_BARR_MITTE := 0.3333
# VERSATZ ZWISCHEN RINNENGITTER UND LAVABAUM — EINE HALBE RINNE, UND SIE ENTSCHEIDET, OB DIE
# LAVA IN DER SOHLE ODER AUF DER KANTE LIEGT.
# Der Baum teilt die Flanke in Zellen der Breite 4, 2 und 1 Rinnen, und die Achse eines Astes
# ist die MITTE seiner Zelle — das MUSS so sein, sonst ist der Abstand zur Achse an einer
# Zellgrenze unstetig und im Hoehenfeld steht dort eine Wand (siehe _vulkan_ader).
# Zellmitten sind also 4j+2, 2j+1 und j+0.5: die beiden groben sind GANZE Zahlen, die feinste
# eine halbe. Ohne Versatz liegen die Rinnensohlen bei den halben Zahlen, und dann laege genau
# EINE Generation in einer Sohle — die feinste, die es erst ganz am Fuss gibt. Staemme und
# Hauptaeste liefen auf einem Grat. Genau das hat der Kritiker gesehen: "gluehende Baender
# OBEN AUF der Flanke".
# Eine halbe Rinne Versatz dreht das um. Die Sohlen liegen jetzt bei den GANZEN Zahlen, und
# damit liegen Stamm und erster Ast in einer Sohle — also die obere Haelfte der Flanke, wo die
# Ader breit ist und auffaellt. Nur die feinste Achse sitzt auf einem Grat, und sie wird erst
# am Fussradius selbst voll erreicht, wo ohnehin alles ausblendet.
# ES IST BILLIGER ALS JEDE ALTERNATIVE: eine Addition auf einer Zahl, die ohnehin gerechnet
# wird. Den Baum stattdessen zu verschieben ginge nicht — dann wandern seine Zellgrenzen mit,
# und die Mitten liegen wieder dort, wo sie vorher lagen.
const VULKAN_BARR_VERSATZ := 0.5
# --- DIE FEINE OBERHARMONISCHE ------------------------------------------------------------
# WOFUER: 32 Rinnen sind am Fuss 245 m auseinander. Das gliedert den Kegel, aber die Vorlage
# zeigt darunter noch eine zweite, viel dichtere Lage — Rippchen von wenigen Dutzend Metern,
# die den Flanken der grossen Rinnen ihre Kanten geben. Ohne sie ist jede Barranco-Wand eine
# glatte, 80 m breite Schraege, und aus der Referenzentfernung liest sich das wieder als
# weiche Kannelierung statt als Fels.
# DIE ZAHL MUSS UNGERADE SEIN, UND DAS IST DER GANZE TRICK. Die Grate der Grundlage liegen
# bei ganzen ph, ihre Sohlen bei halben. Verdreifacht man die Phase, liegt ueber jedem
# Grundgrat wieder ein Grat (3k ist ganz) und in jeder Grundsohle wieder eine Sohle
# (3k + 1.5 ist halb) — die feine Lage VERSTAERKT die grobe, statt sie zu zerkerben. Bei
# GERADER Zahl waere es genau umgekehrt: 2*(k+0.5) ist ganz, also saesse mitten in jeder
# Sohle ein Grat, und dort laeuft die Lava (siehe _vulkan_ader).
# DREI UND NICHT FUENF: 96 Rippchen sind am Fuss 82 m auseinander, also zehn Netzzellen; bei
# fuenf waeren es 49 m, und eine Rippe von sechs Zellen faellt in den Cordsamt zurueck, vor
# dem schon die Rippen gewarnt haben.
const VULKAN_BARR_FEIN_N := 3.0
# Anteil der Grundtiefe. 0.34 sind auf halber Flanke rund 16 m auf 56 m Breite — genug fuer
# eine eigene Schattenkante, zu wenig, um die Zaehlbarkeit der 32 Grundrinnen zu stoeren.
const VULKAN_BARR_FEIN := 0.34
# ... und wo sie einblendet, als Anteil der Flankenlaenge. Sie faengt SPAETER an als die
# Grundlage: oben am Kraterrand stehen 96 Rippchen 30 m auseinander, das sind keine vier
# Netzzellen. Nach unten hin waechst der Umfang und mit ihm der Platz.
const VULKAN_BARR_FEIN_AB := 0.25
const VULKAN_BARR_FEIN_VOLL := 0.62
# HUELLKURVE. Oben faengt die Rinne EXAKT an der gewachsenen Lippe mit null an (krx, nicht
# der nominelle Kraterradius — sonst schnitte sie dort, wo die Lippe nach innen wandert, in
# den fertigen Kraterrand). Voll ist sie nach diesem Anteil der Flankenlaenge.
# 0.38 WAREN 300 m ANLAUF von 790, also fast die halbe Oberflanke: der Kritikpunkt lautete
# "Rinnensystem ueber die GANZE Flanke", und darauf gab es unter dem Kraterrand ein breites
# Band, in dem die Rinne noch nicht stand. 0.30 sind 237 m — die Rinnen fangen am Rand immer
# noch bei null an (das muessen sie, sonst kerben sie in die fertige Lippe), haben ihre
# Tiefe aber schon auf dem obersten Drittel.
const VULKAN_BARR_OBEN := 0.30
# ... und unten laeuft sie im Apron aus. SIE MUSS AM FUSSRADIUS BEI NULL SEIN, UND DAS IST
# KEINE GESCHMACKSFRAGE: der ganze Massivzweig in height_at haengt an "cone > 0.0", und
# cone ist 1 - smoothstep(0, mr, md) — bei md = mr faellt er auf null und ALLES, was der
# Zweig aufgetragen hat, hoert von einem Schritt auf den anderen auf. Was dort noch steht,
# steht als senkrechte, kreisrunde Wand im Gelaende.
# HIER STAND 1.10, mit der Begruendung, die Grate duerften als Finger in die Ebene laufen.
# Sie konnten es nie: die Zeile mit dem Auslauf wird jenseits von mr gar nicht mehr
# erreicht. Uebrig blieb ein 12 m hoher Ring am Fussradius, den erst die Lavalappen
# (weitere 24 m) sichtbar gemacht haben — im Bild ein Lattenzaun aus 8-m-Dreiecken quer
# durch den Waldkragen. Die Probe dagegen steht jetzt in tools/_vulkan_form.gd und heisst
# SENKRECHTE WAENDE; sie muss unter rund 20 m bleiben.
# DER AUSLAUF FING BEI 0.80 AN UND WAR DAMIT ZU FRUEH: das unterste Fuenftel der Flanke —
# also gerade der Ring, in dem die Vorlage ihre Grate als Finger in den Waldkragen schiebt —
# hatte schon keine halbe Rinnentiefe mehr, und dort las sich der Kegel wieder als glatte
# Schuerze. 0.87 laesst die Rinnen bis 1090 m voll stehen und erst auf den letzten 160 m
# auslaufen. Bei NULL AM FUSSRADIUS bleibt es, siehe oben — daran haengt der ganze Zweig.
const VULKAN_BARR_AUS_AB := 0.87
const VULKAN_BARR_AUS_ZU := 1.00
# MAEANDER: um wie viel eine Rinne seitlich wandert, in Zellbreiten. Ohne ihn stuenden 30
# kerzengerade Speichen auf dem Kegel wie die Rillen einer Schallplatte. Das Rauschen dafuer
# wird auf einem KREIS abgetastet (also nahtfrei) und laeuft mit dem Abstand als dritter
# Achse — dieselbe Bauart wie bei Rippen und Zungen.
# UEBER 0.5 DARF ER NICHT: bei einer halben Zellbreite Versatz koennen zwei Nachbarrinnen
# ineinanderlaufen, und dann steht zwischen ihnen kein Grat mehr, sondern eine Mulde.
# 0.42 BEI LAUF 1.3 WAR NOCH ZU BRAV — im Bild liefen die Rinnen fast schnurgerade den
# Kegel hinunter wie die Rillen einer Schallplatte, waehrend die Vorlage wackelnde,
# ineinander verzahnte Finger zeigt. Der Maeander geht deshalb dicht an die Grenze, und
# vor allem laeuft er SCHNELLER hangabwaerts: bei 1.8 wandert eine Rinne auf der Flanke
# rund eine dreiviertel Rauschperiode weit, macht also einen sichtbaren Bogen statt einer
# Neigung.
const VULKAN_BARR_MAEANDER := 0.47
const VULKAN_BARR_WANDER_N := 2.0
const VULKAN_BARR_LAUF := 1.8
# TIEFENSTREUUNG: nicht jede Rinne ist gleich tief. Abgetastet wird auf demselben Kreis mit
# wenigen Lappen, es sind also GRUPPEN benachbarter Rinnen, die tief einschneiden, und
# andere, die kaum mehr als angedeutet sind. Eine Streuung je einzelner Rinne waere billiger
# zu haben (das Rauschen an der Rinnennummer), sah aber aus wie ein Strichcode.
# 0.50 WAR ZU TIEF ANGESETZT. Die flachste Rinne hatte damit die halbe Tiefe, auf halber
# Flanke also 24 m auf 160 m Breite — eine 17-Grad-Mulde, die bei hochstehender Sonne
# keinen Schatten wirft und im Rippenrauschen daneben verschwindet. Eine Gruppe, die man
# nicht mehr als Rinne liest, ist keine Streuung, sondern ein Loch im Muster: aus der
# Referenzentfernung sah der Kegel dort wieder glatt aus. 0.64 haelt auch die schwaechste
# Gruppe bei 40 m und damit ueber 27 Grad Rinnenwand.
const VULKAN_BARR_TIEF_N := 3.0
const VULKAN_BARR_TIEF_MIN := 0.64
# WIE STARK DIE RINNE IN DER FARBE STEHT. Die Form allein reicht nicht: bei hochstehender
# Sonne trifft das Licht Grat und Sohle fast gleich, und dann sieht man 30 Rinnen erst,
# wenn man von der Seite schaut. Der Grat ist abgerieben und hell, die Sohle liegt im
# Schutt und im Schatten — dieselbe Hell-Dunkel-Achse wie bei den Rippen, deshalb geht der
# Wert in DENSELBEN blank-Term statt als eigene Farbe daneben.
# 0.34 WAR ZU VIEL, SOLANGE DIE RIPPEN DANEBEN AUF 0.30/0.74 STANDEN: beide Lagen zusammen
# hoben den halben Kegel ins Grau. Seit das Rippenfenster schmal ist (VULKAN_GRAT_AB) traegt
# die Helligkeit die RINNE und nicht mehr die Rauschlage, und dann darf der Sprung genau
# hier stehen. Das ist der Unterschied, der 32 Rinnen auch dann noch zaehlbar macht, wenn die
# Sonne senkrecht darauf steht — die Form allein schafft es bei 62 m auf 160 m Breite nicht.
# 0.42 IST DIE FOLGE EINER RECHNUNG, NICHT EINES GESCHMACKS. In "blank" liegen vier Summanden
# nebeneinander, und drei davon wussten nichts von der Rinne: die Krume schwankte um +-0.40,
# der Grus um +-0.30, der Barranco-Term nur um +-0.21. Die Helligkeit der Flanke wurde also
# von zwei richtungslosen Rauschlagen bestimmt — genau das "dunkle Textur-Schlierenmuster"
# aus der Kritik, helle und dunkle Felder, die auf keiner Kante liegen. Die beiden anderen
# sind heruntergegangen (VULKAN_HAUT_KRUME, VULKAN_GRUS), dieser hier hoch: mit 0.42 traegt
# der Grat +0.28 bis +0.37 und die Sohle -0.14 bis -0.19, und damit fuehrt die FORM.
const VULKAN_BARR_HELL := 0.20
# --- GIPFEL UND KRATER -------------------------------------------------------------------
# Alle vier Masse stehen in VIELFACHEN DES KRATERRADIUS bzw. der Kratertiefe, nicht in
# Metern: wer den Krater weitet, will die Schuessel mitwachsen lassen und nicht ihre Wand
# stehen sehen.
# WARUM DIE LIPPE NACH AUSSEN FAST NICHTS MEHR AUFTRAEGT (KRONE_AUSSEN): ein Buckel der
# Hoehe a, der ueber die Strecke L nach aussen auslaeuft, nimmt der Flanke dort im Mittel
# a/L an Neigung. Vorher lagen dort 65 m ueber 0.62 Kraterradien, also ueber 186 m — auf
# einer Flanke, die mit 1.1 faellt, blieb davon fast nichts uebrig. Im Bild war das keine
# Lippe, sondern eine Schulter unter einer Kuppe, und der Gipfel las sich als Delle in
# einem Kegel statt als Krater in einem abgestumpften Kegel.
# DASS DER RAND TROTZDEM EIN ECHTES LOKALES MAXIMUM IST, macht die Schuessel dahinter: nach
# aussen faellt die Flanke, nach innen die Kraterwand. Dafuer braucht es keinen Buckel.
const VULKAN_KRONE_INNEN := 0.10
const VULKAN_KRONE_AUSSEN := 0.12
# Wo die flache Kratersohle aufhoert und die Innenwand anfaengt. Daran haengt, ob die
# Schuessel im Streiflicht ganz im Schatten liegt oder nur grau wird: die Wand hat die ganze
# Kratertiefe zu ueberwinden, und je kuerzer die Strecke, die sie dafuer hat, desto steiler
# steht sie.
# 0.50 gab 216 m Lauf und 52 Grad, und im Abnahmebild war die Schuessel eher hell als
# verschattet. 0.55 waren 189 m und 56 Grad — und AUCH DAS WAR ZU WENIG: eine Abnahme hat
# den Krater danach als "glatten Trichter" gemeldet, der nirgends tief aussieht.
# JETZT 0.66. Das sind bei crater_r 620 und crater_depth 340 rund 192 m Lauf, im Mittel
# 60 Grad und an der steilsten Stelle des smoothstep knapp 70 — eine Wand, die im
# Streiflicht ihren eigenen Schatten in die Schuessel wirft.
# DER ALTE EINWAND GEGEN 0.65 IST HINFAELLIG, und zwar nicht, weil er falsch war, sondern
# weil sich der Boden geaendert hat: er lautete "dann ist die Sohle zwei Drittel des
# Kraterdurchmessers breit, das ist eine Tasse". Diese Sohle ist aber nicht mehr leer —
# in ihren inneren drei Vierteln liegt der LAVASEE (VULKAN_SEE_R), und was uebrigbleibt,
# ist ein 99 m schmaler Schuttring zwischen Seeufer und Wandfuss. Eine breite Sohle ist
# genau das, was ein See braucht; leer waere sie eine Pfanne.
const VULKAN_SOHLE := 0.66
# --- DER LAVASEE AUF DER KRATERSOHLE ------------------------------------------------------
# WOGEGEN ER GEBAUT IST: "statt einer steilwandigen Schuessel mit dunklem Boden und echtem
# Lavasee haben wir einen glatten Trichter, der in einem kleinen flachen Orangefleck endet".
# Der Orangefleck war der Schlund (VULKAN_SCHLUND, 0.34 des Kraterradius) — bei 460 m
# Kraterradius rund 156 m breit, in einer 916 m weiten Schuessel also ein Punkt.
#
# DIE FLACHHEIT IST DER GANZE TRICK. Alles an diesem Berg ist rauh: Gratrauschen, Felslage,
# Blocklage, Rippen. Eine Flaeche, auf der NICHTS davon liegt, liest das Auge sofort als
# Fluessigkeit — es gibt in einer Landschaft keinen anderen Grund fuer eine exakte Ebene.
# Deshalb zieht height_at im See die beiden Rauschlagen wieder ab, die es kurz zuvor
# aufgetragen hat, statt den See einfach tiefer zu legen. Ein tiefer gelegter, aber weiter
# gewellter Boden war der erste Versuch und sah aus wie eine Schlackenhalde im Loch.
#
# VULKAN_SEE_R DARF NICHT UEBER VULKAN_RIPPEN_INNEN (0.50) LIEGEN. Dort fangen die radialen
# Rippen an, und die zieht das Flachziehen NICHT mit ab — eine Rippe auf einem See ist eine
# Welle in einem Spiegel. Beide Zahlen stehen deshalb auf 0.50 und muessen zusammen wandern.
const VULKAN_SEE_R := 0.50
# Breite des Ufers, in Kraterradien. Der Sprung von der Schuttsohle auf den Spiegel ist
# "lavasee" hoch (Massivtabelle); auf 0.09 * 620 = 56 m Lauf sind 96 m Fallhoehe rund
# 60 Grad im Mittel — dieselbe Steilheit wie die Kraterwand darueber, und aus demselben
# Grund: eine Boeschung darunter liest sich als Rutsche und nicht als Seeufer.
const VULKAN_SEE_UFER := 0.09
# DIE KRUSTE UND IHRE FUGEN. Ein Lavasee ist nicht orange, er ist SCHWARZ mit orangen
# Nahtstellen — die erkaltete Deckschicht zerreisst in Schollen, und nur dazwischen sieht
# man das Glutbett. Eine durchgehend orange Scheibe war der zweite Fehlversuch: sie las sich
# als Lampe im Berg, nicht als Gestein, das gerade schmilzt.
# Die Fugen liegen auf _ridge (ridged, also scharfe Kaemme = duenne Linien statt Flecken).
# 140 m Grundwelle heisst Schollen von rund 100 m auf einem See von 620 m Durchmesser: sechs
# bis acht Schollen quer, so wie es die Vorlage zeigt. Feiner darf es nicht werden — das
# Gelaendenetz hat 8 m Kantenlaenge, und ab rund 60 m Wellenlaenge flimmert die Farbe
# zwischen benachbarten Dreiecken (dieselbe Grenze wie bei VULKAN_FELS_M).
const VULKAN_SEE_M := 140.0
const VULKAN_SEE_FUGE_AB := 0.34
const VULKAN_SEE_FUGE_VOLL := 0.72
const VULKAN_SEE_KRUSTE := Color(0.042, 0.034, 0.033)
# --- DIE INNENWAND DES KESSELS ------------------------------------------------------------
# Der Krater hebt den Hoehenanteil "t" von innen auf voll (siehe _vulkan_haut), damit die
# Sohle nicht rostbraun wird. Der Preis dafuer: Innenwand und Aussenflanke bekommen genau
# dieselbe Haut, und im Abnahmebild war der Kessel deshalb ein mittelgraues Becken — hell
# genug, dass die 340 m Tiefe darin verschwanden.
# Ein Kraterinneres ist aber JUENGER als die Flanke: dort liegt frischer Auswurf, kein
# verwitterter Hang. VULKAN_KESSEL ist dieses fast schwarze Innere, und die Rampe blendet es
# von der Lippe (1.02) nach innen ein, statt an einer Kante umzuschalten — die gewachsene
# Lippe wandert um +-22 Prozent (siehe "lippe"), eine harte Grenze haette dort einen
# Farbring hinterlassen.
# NICHT GANZ DECKEND (0.62): die Felslage und die Blocklage sollen im Kessel weiter zu sehen
# sein. Bei 1.0 war die Wand eine schwarze Flaeche ohne Struktur, und damit war sie wieder
# so tiefenlos wie vorher die graue.
const VULKAN_KESSEL := Color(0.062, 0.052, 0.052)
const VULKAN_KESSEL_DECK := 0.62
const VULKAN_KESSEL_AB := 1.02
const VULKAN_KESSEL_VOLL := 0.72
# Radius des Schlots, als Anteil des Kraterradius.
# NICHT DIE TIEFE ENTSCHEIDET, OB MAN IHN SIEHT, SONDERN DAS VERHAELTNIS. Bei 0.30 und
# 115 m stand seine Wand auf 40 Grad, und eine 40-Grad-Mulde faengt bei hochstehender Sonne
# weder Streiflicht noch Schatten — im Bild lag in der hellen Pfanne eine kaum dunklere
# Pfanne. Ab rund 55 Grad kippt sie ins Schwarze.
# SEINE AUFGABE HAT SICH GEAENDERT, seit auf der Sohle der LAVASEE liegt: die helle Pfanne,
# gegen die er gebaut wurde, gibt es nicht mehr. Er ist jetzt der SCHLUND IM SEE — die
# Stelle, an der die Saeule steht und der Spiegel eingezogen ist. Deshalb ist er flach
# geworden (siehe "schlot" in der Massivtabelle): eine tiefe Grube im See wuerde heissen,
# dass der See leergelaufen ist, und ein leerer See ist wieder ein Trichter.
# 0.17 von 620 m sind 105 m Radius, also ein Schlund von gut 200 m in einem See von 620 m —
# das Verhaeltnis, das die Vorlage zeigt.
const VULKAN_SCHLOT_R := 0.17
# Tiefe der Scharte, gemessen an der KRATERTIEFE. Vorher hing sie an der Lippenhoehe und
# schrumpfte deshalb mit, sobald die Lippe flacher wurde — die Kerbe soll aber die Wand
# anschneiden, nicht die Lippe.
const VULKAN_SCHARTE_TIEF := 0.28

# --- HAUT DES VULKANS: GESTEIN, LAVAZUNGEN, GLUT ------------------------------------------
# DIE FORM ALLEIN MACHT KEINEN VULKAN. Ein Kritiker hat den abgenommenen Kegel neben die
# Referenz gestellt: Boeschung, Krater und Rippen waren gemessen richtig, und trotzdem las
# sich das Bild als roter Sandstein-Tafelberg. Der Grund ist ein einziger — die ganze
# Flanke trug EINEN Ton vom Fuss bis zur Lippe, ohne einen Hinweis darauf, dass hier etwas
# passiert. Drei Dinge liegen deshalb jetzt darauf, jedes mit eigener Schwelle:
#   GESTEIN  unten verwitterter rostbrauner Tuff, oben schwarze Asche,
#   ZUNGEN   erstarrte Stroeme, die ueber den Bergfuss hinaus in die Ebene auslaufen,
#   GLUT     offene Rinnen, die aus sich selbst leuchten (Alphakanal, siehe Shader).
# Alle drei kosten NUR innerhalb des Vulkan-Umkreises etwas; draussen faellt je Dreieck ein
# Abstandsquadrat an, siehe _vulkane.
#
# Hoehe in Metern, ab der die Vulkanhaut ueberhaupt gilt. Der Wert stand vorher schon in
# _face_color; darunter ist der Kegel Strand und Vorland wie jede andere Insel.
const VULKAN_HAUT_FUSS := 26.0
# Reichweite der Haut als Vielfaches des Massivradius. SIE IST GROESSER ALS EINS, und das
# ist der Punkt: ein Lavastrom, der genau am Fussradius aufhoert, sieht abgeschnitten aus.
# Die Zungen laufen darueber hinaus in die gruene Ebene und enden dort ausgefranst.
const VULKAN_HAUT_REICH := 1.32
# GEMESSEN AN DER VORLAGE, NICHT GESCHAETZT. Ihre Mittelflanke hat den Helligkeitsmedian
# bei 0.11, das obere Viertel faengt bei 0.19 an und das oberste Zwanzigstel liegt bei 0.36;
# unsere Flanke stand bei 0.22 / 0.28 / 0.28. Zwei Befunde stecken darin, und der zweite
# wiegt schwerer:
#   ZU HELL  — der Kegel ist fast schwarzer Basalt, kein brauner Berg.
#   ZU FLAU  — in der Vorlage ist der hellste Zehntel SECHSMAL so hell wie der Grund, bei uns
#              knapp doppelt. Das Bild lebt von diesem Sprung: hell abgeriebene Gratruecken
#              ueber fast schwarzen Rinnen.
# EINE HOEHENRAMPE KANN DIESEN SPRUNG NICHT ERZEUGEN. Hier stand
#     haut = ROST.lerp(ASCHE, smoothstep(0.28, 0.68, hoehenanteil))
# und das faerbt per Konstruktion jede Hoehenlinie gleich — dabei kommt ein Verlauf heraus,
# also genau der Anstrich, gegen den die Rampe eigentlich gebaut war. Die Helligkeit haengt
# jetzt am RIPPENRAUSCHEN, also an der Form selbst: hohe Werte sind die Kaemme, tiefe die
# Rinnen (dieselbe Lage, die height_at auftraegt und in deren Rinnen die Glut liegt).
# Grund, fast schwarz und eine Spur blaeulich — die Rinnen und die Schattseite ...
# DER BLAUSTICH IST RICHTIG UND BLEIBT, obwohl die letzte Kritik "dunkelblau-schwarz" als
# Mangel gemeldet hat. Nachgemessen ist das dunkelste Viertel der VORLAGE mit 0.054/0.067/0.124
# noch deutlich blauer als unseres — und das muss es sein: was dort leuchtet, ist der Himmel,
# nicht die Sonne. Der Mangel steckte in der HELLIGKEIT, nicht im Ton: dasselbe Viertel stand
# bei uns auf 0.121/0.155/0.224, also gut doppelt so hell. Ein Schattenschlitz, der halb so
# tief ist wie er sein sollte, liest sich als flaue Flaeche, und genau das war der Befund.
# 0.064 -> 0.050 zieht die Schattseite um ein knappes Viertel herunter.
# WEITER HINUNTER BRINGT NICHTS, UND DAS IST GEMESSEN, NICHT GESCHAETZT: ein Probelauf mit
# 0.036 hat den Median des fertigen Bildes um ganze 0.002 bewegt (0.221 auf 0.219). Der
# Grund ist die Luftperspektive — bei 2 km Kameraabstand liegt unter der Flanke ein
# additiver Sockel aus Nebel und Himmelslicht, der mit dem Albedo gar nicht skaliert. Wer
# die Flanke naeher an die 0.114 der Vorlage bringen will, muss also an der Atmosphaere
# drehen, und die gehoert der ganzen Welt. Was hier bleibt, ist der Weg ueber die FORM:
# Flaechen, die von der Sonne wegzeigen, liefert die Blocklage (VULKAN_BLOCK_M).
const VULKAN_BASALT := Color(0.028, 0.027, 0.036)
# ... und der abgeriebene Gratruecken darueber. Der Sprung dazwischen ist der gemessene
# Faktor sechs.
# HIER STAND 0.44 / 0.415 / 0.375, ALSO EIN HELLES WARMES GRAU, und das war zweimal daneben.
# Nachgemessen am fertigen Bild gegen die Vorlage (gleiche Ausschnitte, Himmel/Gruen/Lava
# ausmaskiert): unsere Mittelflanke stand im Median auf 0.25 gegen 0.15, ihr oberstes
# Zwanzigstel auf 0.53 gegen 0.36. Der helle Ton war also rund anderthalbmal zu hell, und im
# Bild las er sich auf der Oberflanke als Schnee.
# UND ER WAR ZU WARM. Der hellste Fels der Vorlage ist ein NEUTRALES Grau (gemessen
# 0.55/0.50/0.52, also eine Spur ins Kalte); ihr Braun kommt vom Rost, der darueber liegt.
# Unser Ton brachte die Waerme schon selbst mit und wurde vom Rost noch einmal gebraeunt —
# heraus kam Beige, und Beige auf einer Flanke heisst Sandstein.
# 0.335 / 0.320 / 0.308 sind drei Viertel der alten Helligkeit und fast neutral: Aschegrau mit
# gerade so viel Waerme, dass es nicht blau gegen den Basalt steht. Die Waerme macht der Rost.
# ZUERST STANDEN HIER 0.30 / 0.288 / 0.278, und das war eine Spur zu weit heruntergezogen:
# nachgemessen lag das oberste Zwanzigstel der Oberflanke danach bei 0.37 gegen 0.43 in der
# Vorlage, der Kegel also flacher als das Vorbild statt gleich. Der Rest der Reparatur sitzt
# ohnehin nicht in diesem Ton, sondern darin, WO er aufgetragen wird (siehe VULKAN_HELL_SOCKEL).
# UND ER IST WAERMER GEWORDEN, OHNE HELLER ZU WERDEN. Gemessen ist das hellste Zehntel der
# Vorlage 0.396/0.340/0.340 — rotbraun, nicht grau; unseres stand auf 0.377/0.379/0.394, also
# eine Spur ins Kalte. Die Begruendung oben ("die Waerme macht der Rost") stimmt fuer die
# FLAECHE, aber nicht fuer den Grat: dort deckt der Rost am duennsten, und uebrig blieb genau
# das kalte Grau, das im Bild als Schnee gelesen wurde. 0.366/0.309/0.280 hat dieselbe
# Helligkeit wie 0.335/0.320/0.308 (0.322 gegen 0.323 nach der Luma-Formel) und schiebt nur
# den Ton — es ist also KEINE Rueckkehr zu dem hellen Warmgrau, an dem der Ton zweimal
# gescheitert ist, sondern dessen Farbe bei der inzwischen gemessenen Helligkeit.
# ZWEI SCHRITTE, WEIL DER ERSTE ZU KURZ WAR: mit 0.352/0.316/0.288 stand das hellste Zehntel
# des Bildes auf 0.383/0.362/0.367 gegen 0.396/0.340/0.340 in der Vorlage — waermer als
# vorher, aber immer noch fast neutral. Die Luftperspektive mischt Blau dazu (der Kegel steht
# 2 km vor der Kamera), der Ton muss den Weg dorthin also mitrechnen.
const VULKAN_GRAT := Color(0.366, 0.309, 0.280)
# ... und derselbe Fels weiter oben, wo die Asche jung ist. Er ist DUNKLER als der abgeriebene
# Grat, und das ist der Punkt: abgerieben wird unten, oben liegt frischer Auswurf. Genau dort
# standen die hellen Striemen, weil der Rost nach oben hin ausblendet (VULKAN_ASCHE_AB/_VOLL)
# und den hellen Ton dann nichts mehr daempfte.
# ES IST TROTZDEM KEINE HOEHENRAMPE AUF DER GESTEINSFARBE — die war schon einmal hier und ist
# an ihrer eigenen Konstruktion gescheitert (siehe oben). Die Rampe faerbt nur, WOHIN "blank"
# aufhellt; WO aufgehellt wird, entscheidet weiter allein die Form. Auf einer Hoehenlinie ohne
# Kante passiert also nach wie vor gar nichts.
const VULKAN_ASCHE := Color(0.215, 0.207, 0.203)
# --- DER DRITTE TON: DAS ANSTEHENDE AN DER ABRISSKANTE ------------------------------------
# WARUM ES IHN GEBEN MUSS, UND ZWAR GEMESSEN. Eine SCHWARZPROBE (alle Gesteinsfarben des
# Kegels auf null, ein Renderlauf, vk/rzschwarz_vulkan_ref.png) hat gezeigt, was die Form
# allein leisten kann: bei 3,5 km Kameraabstand misst der Kegel dann 0.254 mittlere
# Leuchtdichte — das ist der reine Nebelsockel — und seine lokale Streuung faellt von 0.0141
# auf 0.0019. NULL. Der Nebel ist additiv, er skaliert nicht mit dem Albedo; wo kein Albedo
# steht, macht auch die zerklueftetste Geometrie keinen Helligkeitsunterschied. Genau daran
# sind drei Runden gescheitert, die mehr Gelaende eingebaut haben.
# Umgekehrt gilt: Kontrast entsteht NUR aus hellem Gestein, das steil steht. Die Vorlage
# staffelt dafuer drei Toene — schwarzer Basalt in der Flaeche, rostrote Baender darueber
# und, an Steilkanten und Abrissen, helles graues Anstehendes. Der dritte fehlte hier: der
# hellste Ton war VULKAN_GRAT, und der wird nach oben hin auch noch zu VULKAN_ASCHE
# abgedunkelt — ausgerechnet im Bildausschnitt der Abnahme stand als "hell" also 0.215.
# GEMESSEN AN DER VORLAGE ist ihr hellster Fels 0.55/0.50/0.52, also ein neutrales Grau.
# 0.52/0.495/0.475 liegt knapp darunter und ist bewusst NICHT die Rueckkehr zu dem hellen
# Warmgrau, an dem der Gratton zweimal gescheitert ist ("liest sich als Schnee"): dieser Ton
# wird NUR ueber "kante" aufgetragen, also ausschliesslich dort, wo unter ihm eine Kante
# liegt. Die formlosen Lagen (Felslage, Grus) kommen an ihn gar nicht mehr heran — sie
# hellen weiter nur bis zu Grat/Asche auf. Damit kann er per Konstruktion keine Striemen
# machen: er sitzt auf Abrissen oder nirgends.
# UND ER IST WAERMER GEWORDEN, OHNE HELLER ZU WERDEN — 0.52/0.495/0.475 auf 0.56/0.49/0.44
# bei gleicher Luma (0.4989 gegen 0.5013). Der Grund ist gemessen und war eine Ueberraschung:
# das Umgebungslicht dieser Welt kommt vom HIMMEL (Main: AMBIENT_SOURCE_SKY, Energie 0.85),
# ist also blau. Eine helle Facette, die von der Sonne wegzeigt, wird davon so blaustichig,
# dass sie im Bild b > r erreicht — und die Abnahmemessung haelt genau das fuer Himmel
# (vk/kontrast.py, "himmel"). Gemessen stieg der Anteil weggeworfener Bildpunkte mit jeder
# Aufhellung mit (9.4 auf 12.0 Prozent), und weil das 9x9-Fenster VOLLSTAENDIG auf Fels
# liegen muss, fiel die Zahl der gueltigen Fenster von 42 auf 18 Prozent: die Streuung wurde
# danach fast nur noch auf den flachen dunklen Resten gemessen und sank, obwohl das Bild
# kontrastreicher geworden war (Streuung um die Fenstermitte 0.048 -> 0.075).
# Der waermere Ton haelt r ueber b, auch nachdem das blaue Umgebungslicht darauf liegt.
# ZWEITER SCHRITT IN DIESELBE RICHTUNG, WEIL DER ERSTE NUR DEN BLAUKANAL GEHOLT HAT.
# Nachgemessen am fertigen Bild (Kasten der Abnahme, Himmel/Gruen/Lava ausmaskiert) stand
# unser hellstes Hundertstel auf 0.846/0.818/0.737, die Vorlage auf 0.597/0.526/0.505. In
# Verhaeltnissen zu Rot: wir 1 / 0.967 / 0.871, die Vorlage 1 / 0.881 / 0.846. Der Rueckstand
# sitzt also fast ganz im GRUEN — unser Fels ist auf der Rot-Gruen-Achse neutral, und ein
# neutraler Ton bei dieser Helligkeit liest sich als Schnee. Die Vorlage zeigt dort
# graubraunes bis rostiges Gestein.
# 0.615/0.478/0.383 HAT DIESELBE LEUCHTDICHTE wie 0.56/0.49/0.44 (0.5003 gegen 0.5013 nach
# der Luma-Formel) und schiebt nur die Farbe — es ist also ausdruecklich KEIN Abdunkeln und
# auch keine Rueckkehr zu dem hellen Warmgrau, an dem der Ton zweimal gescheitert ist: das
# war HELL und warm, dieses ist gleich hell wie zuletzt und nur warm.
# WARUM DER SCHRITT SO GROSS AUSFAELLT: der Nebelsockel bei 3,5 km ist additiv und fast
# neutral, er zieht jede Farbe zur Mitte. Gemessen kommt vom Albedo-Abstand zum Grau nur
# gut ein Viertel im Bild an (unser Albedo lag 0.125 unter eins im Gruenverhaeltnis, im Bild
# waren davon 0.033 uebrig). Ein zaghafter Schritt verschwindet im Nebel.
const VULKAN_ANSTEHEND := Color(0.615, 0.478, 0.383)
# AB WELCHER KANTE ES UEBERHAUPT ANSTEHT — und diese Schwelle ist der Unterschied zwischen
# einem gestaffelten Gestein und einem aufgehellten Kegel. GEMESSEN (tools/_vulkan_fein.gd):
# ohne sie hebt schon ein "kante" von 0.05 die Albedo der FLAECHE um mehr als das Doppelte,
# denn das Anstehende ist rund fuenfzigmal so hell wie der Basalt. Der Mittelwert des ganzen
# Kegels haengt also nicht an der Helligkeit des Tons, sondern an der Flaeche, die ihn
# ueberhaupt bekommt. Ohne Schwelle sagte die Kurve 0.325 Bildmittel voraus, mit 0.55 sind
# es 0.29 — bei fast unveraenderter Streuung, weil der Sprung an der Kante derselbe bleibt.
# ES IST AUSDRUECKLICH KEINE ZWEITE HELLIGKEITSREGEL, sondern eine Flaechenregel: was unter
# der Schwelle liegt, ist keine Kante, sondern eine leicht geneigte Facette — und auf der
# liegt Asche, kein blanker Fels.
const VULKAN_ANSTEHEND_AB := 0.72
# Schwellen auf dem Rippenrauschen. Gemessen (tools/_vulkan_form.gd) liegt es auf dem Kegel
# zwischen -0.41 und 0.94, im Mittel bei 0.38, das oberste Zehntel faengt bei 0.67 an.
# 0.42/0.80 STAND HIER ZUERST, nach der Flaechenrechnung: gut die Haelfte im Basalt, ein
# Fuenftel deutlich heraus. Im Bild war das zu wenig — von zehn Rippen leuchteten zwei, der
# Rest der Flanke stand als schwarze Masse da und der Kegel verlor seine Form. Die Vorlage
# hat auf JEDER Rippe einen hellen Ruecken. 0.30/0.74 traf das, SOLANGE DIE RIPPEN DIE FORM
# WAREN.
# JETZT SIND SIE ES NICHT MEHR: die Flanke wird von den 32 Barrancos gegliedert und die
# Rippenamplitude ist auf 44 m heruntergegangen (siehe Main, Massivtabelle). Ein breites
# Fenster auf einem Rauschen, das nur noch halb so viel Gelaende macht, ist genau das
# "dunkle Textur-Schlierenmuster", das ein fremder Blick auf dem letzten Abnahmebild
# gefunden hat: helle und dunkle Felder, die mit keiner Kante zusammenfallen. 0.44/0.86
# laesst nur noch das oberste Viertel der Verteilung hell werden — aus Feldern werden
# Kanten, und die Flaeche dazwischen gehoert der Rinne (VULKAN_BARR_HELL).
const VULKAN_GRAT_AB := 0.44
const VULKAN_GRAT_VOLL := 0.86
# WIEVIEL DER RIPPENKAMM UEBERHAUPT NOCH AUFHELLEN DARF. Er stand als EINZIGER der vier
# Terme in "kante" ohne eigenen Faktor da, also mit dem vollen Gewicht 1.0 — und das ist der
# teuerste Posten der ganzen Haut: gemessen hellt er im Mittel rund ein Viertel auf, und
# zwar UEBERALL, denn seine Wellenlaenge ist die des Rippenmusters (zehn Wellen im Umfang,
# also 250 bis 800 m). Am Bild nachgemessen bringt eine Aufhellung dieser Wellenlaenge im
# 9x9-Fenster der Abnahme fast nichts — das Fenster ist rund 55 m breit und sieht von einer
# 400-m-Welle nur eine schwach geneigte Ebene. Sie kostet also vollen Mittelwert und liefert
# keine Streuung, und der Mittelwert ist die Zahl, die ohnehin am Nebelsockel klebt.
# 0.45 laesst den Kamm weiter fuehren — er ist Form, und er soll dem Kegel seine Gliederung
# geben —, gibt aber die Haelfte des Helligkeitsbudgets an die Lagen ab, die auf
# Facettengroesse arbeiten (Blocklage 46 m, Abrissstufe 34 m).
const VULKAN_RIPPEN_HELL := 0.18
# GRUS. Die beiden Rauschlagen darueber (Rippen 10 Wellen im Umfang, Felslage 150 m) sind
# beide GROSS gegen ein 8-m-Dreieck: ihre Grenzen liefen als weiche Baender ueber den Hang
# und der Kegel sah luftgepinselt aus, waehrend die Vorlage koernigen Schutt zeigt. Diese
# Lage bricht die Grenze auf Dreiecksmassstab auf — bei 34 m Welle sind das vier bis fuenf
# Facetten je Lappen, also genau die Koernung, die das Netz ueberhaupt darstellen kann.
# STAERKER ALS 0.35 GEHT NICHT: darueber kippt es von Schutt in Bildrauschen, weil dann auch
# mitten im Basaltfeld einzelne Facetten hell aufblitzen.
# 0.30 WAREN TROTZDEM ZU VIEL, und der Grund steht bei VULKAN_BARR_HELL: diese Lage hat KEINE
# Form unter sich — sie faerbt nur. Solange sie um +-0.30 schwankte und der Barranco-Grat um
# +-0.21, entschied der Schutt darueber, welche Flaeche hell aussieht. 0.18 koernt weiter auf
# Dreiecksmassstab, ohne die Rinne zu ueberstimmen.
const VULKAN_GRUS_M := 34.0
# 0.18 -> 0.55, UND DER ALTE EINWAND DAGEGEN IST MIT DIESER RUNDE HINFAELLIG GEWORDEN. Er
# lautete: "STAERKER ALS 0.35 GEHT NICHT, darueber kippt es von Schutt in Bildrauschen, weil
# dann auch mitten im Basaltfeld einzelne Facetten hell aufblitzen" — und er war richtig,
# SOLANGE die Lage nur faerbte. Seit "nasen" auf demselben Rauschfeld eine Abrissstufe ins
# Gelaende schneidet, blitzt keine Facette mehr mitten im Feld auf: die hellen sitzen auf dem
# gehobenen Absatz, und darunter steht eine Kante.
# WARUM SO VIEL. Am Bild nachgemessen (vk/kontrast.py, ueber verschieden grosse Fenster)
# holt die Vorlage ihre Streuung SCHON ZWISCHEN BENACHBARTEN BILDPUNKTEN: 0.031 im
# 3x3-Fenster, wir standen bei 0.008. Ein Bildpunkt ist bei dieser Kamera rund 5 bis 6 m,
# also ungefaehr eine Gelaendezelle. Was fehlt, ist also genau das: der Sprung von Facette
# zu Facette — und den kann nur eine Lage in Zellgroesse liefern, die kraeftig genug ist,
# den Basalt wirklich zu verlassen.
const VULKAN_GRUS := 0.70
# WO DIE STUFE IHREN NULLPUNKT HAT (siehe _vulkan_haut). Ueber 0.5 heisst: der gehobene
# Absatz ist die MINDERHEIT, die Flaeche dazwischen bleibt Basalt.
const VULKAN_GRUS_MITTE := 0.66
# --- DER SCHUTT AUF DEM ABSATZ: EINE ZWEITE, ZELLGROSSE KOERNUNG ---------------------------
# WARUM ES SIE BRAUCHT, OBWOHL SCHON EINE KOERNUNG DA IST — und die Begruendung ist eine
# Messung am Bild, keine Geschmacksfrage. Die Abnahme misst die Streuung in einem
# 9x9-Fenster; bei dieser Kamera sind das rund 55 m Gelaende. Misst man dieselbe Streuung
# ueber verschieden grosse Fenster, zeigt sich, WO die Vorlage ihren Kontrast hat:
#       Fenster        3x3     9x9    33x33
#       Vorlage       0.031   0.046   0.058
#       wir (davor)   0.008   0.010   0.011
# Die Vorlage hat ihren Sprung schon zwischen BENACHBARTEN Bildpunkten. Bei 5 bis 6 m je
# Bildpunkt ist das eine Gelaendezelle. Eine 34-m-Lage bringt es auf knapp anderthalb
# Wechsel je Fenster — besser als alles, was vorher da war, aber ein Fenster mit anderthalb
# Wechseln misst noch fast die Kante selbst und nicht ihre Haeufigkeit.
# 18 M SIND RUND ZWEI ZELLEN und damit drei Wechsel im Messfenster. Fuer GELAENDE waere das
# zu fein (siehe VULKAN_NASEN_AB: unter rund 32 m Welle wird aus Relief Flimmern) — als
# FARBE ist es genau richtig, denn die Farbe liegt ohnehin je Dreieck flach an. Es ist
# derselbe Grund, aus dem der Schutt auf einer echten Vulkanflanke aus der Luft koernig
# aussieht, ohne dass sich das Gelaende darunter merklich wellt.
# 0.30 UND NICHT MEHR: bei dieser Lage gilt der alte Einwand gegen zu starke Koernung
# ("dann blitzen einzelne Facetten mitten im Basaltfeld auf") wieder voll, denn unter ihr
# liegt KEINE Form. Sie darf deshalb koernen und nicht fuehren — die Fuehrung haben die
# Kante und die Abrissstufe.
const VULKAN_SCHUTT_M := 13.0
const VULKAN_SCHUTT := 0.12
# --- DIE ABRISSKANTEN ("nasen") -----------------------------------------------------------
# WAS FUENF ABNAHMEN GEMELDET HABEN UND WARUM DREIMAL DAS FALSCHE GEBAUT WURDE. Der Befund
# lautete jedesmal "glatte Flanke, es fehlt radiale Geometrie", und dreimal wurden daraufhin
# die Rinnen tiefer gemacht. Gemessen (tools/_vulkan_rippen.gd) standen danach 22 bis 30
# Grat-Rinne-Paare je Ring bei 83 bis 129 m Amplitude — mehr, als die Abnahmen selbst
# gefordert hatten. Diese Rinnen haben rund 230 m Wellenlaenge; ueber die sichtbare
# Kegelbreite sind das sechs bis acht Stueck, also GROSSFORM. Noch mehr davon aendert nichts.
# WAS FEHLT, IST DIE KURZE WELLE — und zwar als KANTE, nicht als Welle. Diese Lage macht aus
# dem Rauschen keine Sinuskuppen, sondern Stufen: das schmale Fenster 0.40 .. 0.60 auf einem
# Feld, das von -1 bis 1 laeuft, laesst zwischen zwei Plateaus nur einen kurzen Uebergang
# stehen. Heraus kommen flach liegende Absaetze mit steilen Abrissen dazwischen, und genau
# darauf kommt es an: eine Kuppe kippt die Flaeche allmaehlich, eine Abrisskante stellt zwei
# BENACHBARTE Facetten verschieden ins Licht.
# DAS FENSTER LIEGT UM NULL, und das ist nicht Kosmetik: _patch ist fBm und damit um null
# verteilt (gemessen Streuung rund 0.35). Ein Fenster bei 0.40 .. 0.60 haette nur die
# obersten paar Prozent erwischt — vereinzelte Warzen auf einer ansonsten unveraenderten
# Flanke. Um null herum liegen dagegen rund die Haelfte der Flaeche oben und die Haelfte
# unten: Absatz, Abriss, Absatz. Zugleich ist die Lage damit von selbst um ihren eigenen
# Mittelwert zentriert, sie hebt den Kegel also nicht an — dieselbe Bauart wie bei den
# Barrancos (VULKAN_BARR_MITTE), und aus demselben Grund: die Boeschung ist vermessen.
# +-0.26 UND NICHT ENGER: der Uebergang ist damit rund 5,5 m breit, also knapp eine
# Netzzelle. Enger faellt die Stufe zwischen zwei Zellen und wird zu Treppenrauschen; viel
# weiter ist es keine Kante mehr, sondern wieder eine Welle wie die drei, die schon da sind.
# SIE LIEST DASSELBE RAUSCHEN WIE DIE GRUS-FARBLAGE (_vk_grus_takt, 34 m), und das ist der
# eigentliche Griff: der Grus war bisher eine Aufhellung OHNE Form darunter, und genau als
# solche ist er zweimal als "helle Striemen" gemeldet worden (siehe VULKAN_HELL_SOCKEL).
# Jetzt liegt unter ihm eine Kante. Es kostet keine zusaetzliche Rauschabfrage in
# _vulkan_haut und genau eine in height_at.
const VULKAN_NASEN_AB := -0.26
const VULKAN_NASEN_VOLL := 0.26
# WO DIE ABRISSE AUFHOEREN, als Anteil des Fussradius — DIESELBE FALLE WIE BEI DER
# BLOCKLAGE, und deshalb dieselbe Schranke: die Bepflanzung duennt nach dem Hoehenunterschied
# ueber der 8-m-Zelle aus und faellt ueber 4,6 m ganz aus. 13 m Stufe auf 34 m Welle sind an
# der Abrisskante rund 6 m je Zelle — durch den Waldkragen gelegt, riebe diese Lage ihn auf.
# Sie laeuft deshalb schon innerhalb des Kegels aus und ist am Kragen bei null.
const VULKAN_NASEN_AUS_AB := 0.74
const VULKAN_NASEN_AUS_ZU := 0.90
# WIE VIEL DIE BEIDEN FORMLOSEN LAGEN (Felslage und Grus) NEBEN EINER KANTE NOCH DUERFEN.
# Sie standen mit den beiden formfolgenden Lagen in EINER Summe und konnten zusammen 0.45
# beitragen — auf einer Flaeche, unter der keine Kante liegt, ist das die halbe Aufhellung
# aus dem Nichts. Im Bild waren es grosse weiche hellgraue Schlieren quer ueber die
# Oberflanke; ein fremder Blick hat sie als Schnee gelesen, und auf einem taetigen Vulkan ist
# das der schlimmste moegliche Irrtum.
# 0.22 laesst als Koernung stehen, was eine Koernung sein soll (noch +-0.10 statt +-0.45),
# und gibt die Fuehrung an die Kante zurueck. AUF der Kante wirken beide Lagen unveraendert
# voll — dort ist ihre Aufgabe, den Grat auszufransen und ihn auf Dreiecksmassstab
# aufzubrechen, und die war nie das Problem.
# NICHT AUF NULL: ohne jeden Sockel steht die Rinne als lackschwarze, voellig glatte Flaeche
# da, und das ist der Fehler in die andere Richtung.
# 0.22 -> 0.16, UND ZWAR WEIL EINE DRITTE FORMFOLGENDE LAGE DAZUGEKOMMEN IST. Der Sockel ist
# das, was die beiden formlosen Lagen NEBEN einer Kante noch duerfen; seit Blocklage und
# Steilkante dazwischen liegen, gibt es viel weniger Flaeche, auf der gar keine Form steht —
# was dort noch aufhellt, verwaescht nur den Sprung, um den es geht.
const VULKAN_HELL_SOCKEL := 0.20
# STEILHEIT ALS NEIGUNG ZUM BLANKLIEGEN — eine von fuenf Lagen in "kante".
# Sie liest die FLAECHENNORMALE, also die Form selbst und nicht ein Rauschen daneben: wo der
# Hang zu steil wird, bleibt weder Asche noch Grus liegen und der blanke Fels steht an. Das
# ist derselbe Mechanismus, mit dem die Weltregel ihren Fels vom Boden trennt (siehe
# fels_anteil in _face_color) — hier nur mit einer Schwelle, die zum Kegel passt.
# WARUM DAS KEINE HOEHENRAMPE DURCH DIE HINTERTUER IST, an der schon zwei Versuche gescheitert
# sind: auf einem glatten Kegel WAERE Neigung dasselbe wie Hoehe, hier ist sie es gerade nicht.
# Ueber Blocklage, Barrancos und Abrisskanten schwankt die Normale von Dreieck zu Dreieck um
# mehr als der Kegel selbst ueber die halbe Flanke — sie springt also mit der Facette und
# nicht mit der Hoehenlinie.
# 0.80/0.55 -> 0.90/0.36, UND DAS IST EINE MESSUNG UND KEINE GESCHMACKSFRAGE: nachgemessen
# (tools/_vulkan_fein.gd, Zeile "NY") liegt ny auf der Flanke im Median bei 0.567, das untere
# Viertel unter 0.424, das obere ueber 0.757. Das alte Fenster endete schon bei 0.55 und stand
# damit fuer mehr als die halbe Flanke auf seinem Anschlag — dort hat es gar nicht mehr
# unterschieden, sondern nur noch gleichmaessig aufgehellt. Das neue spannt ueber die
# tatsaechliche Verteilung, und erst dadurch trennt es Facette von Facette.
# SIE HELLT NICHT NUR AUF, SIE DUNKELT AUCH AB, und das ist der Unterschied zwischen dieser
# Fassung und der ersten. Zuerst stand die Steilheit rein additiv in "kante" — und im
# Renderlauf danach war der Median der Flanke HOEHER als vorher (0.223 gegen 0.209), obwohl
# der Grundton dunkler geworden war: der ganze Kegel steht schraeg, der Term war also nirgends
# null und hob die Flaeche flaechig an. Eine Lage, die nur addiert, macht keinen Kontrast, sie
# macht Helligkeit. Jetzt ist er um seinen eigenen Mittelwert zentriert.
# VULKAN_STEIL_MITTE ist genau dieser Mittelwert ueber die Kegelflaeche (tools/_vulkan_form.gd,
# "STEILE"). Mit dem breiteren Fenster steht er auf 0.55 statt auf 0.744; die Zahl gehoert
# nachgemessen, sobald sich Fenster oder Form aendern.
# 0.42 -> 0.70, WEIL DER TERM SEIT DIESER RUNDE GEDAEMPFT ANKOMMT: "kante" faerbt nicht mehr
# selbst, sondern verschiebt nur noch die Schwelle der Aschedecke, und das mit dem Faktor 0.12
# (VULKAN_DECKE_LAGEN). Gemessen: ohne diesen Summanden faellt das Verhaeltnis aus Streuung
# und Helligkeit ueber dem Nebelsockel von 0.64 auf 0.58.
const VULKAN_STEIL_AB := 0.90
const VULKAN_STEIL_VOLL := 0.36
const VULKAN_STEIL_HELL := 0.70
const VULKAN_STEIL_MITTE := 0.55
# --- DIE ASCHEDECKE: WORAN SICH IN DIESER RUNDE ALLES ENTSCHIEDEN HAT --------------------
# Fenster, in dem die Flanke von "blank" auf "zugeweht" umschlaegt. Der Treiber ist der
# Aufwaertsanteil der Flaechennormale, um das Feinkorn gewuerfelt und von den Formlagen
# verzogen:  ny + KORN * korn - LAGEN * kante.
# WARUM AUSGERECHNET DIE FLAECHENNORMALE. Die Abnahme misst die Streuung in einem
# 9x9-Fenster, das bei 6,07 m je Bildpunkt rund 55 m abdeckt — sie sieht also nur, was sich
# auf kuerzeren Wegen aendert. Gemessen (vk/fenster.py) hatte der Kegel ueber den ganzen
# Ausschnitt schon DIESELBE Streuung wie die Vorlage (0.098 gegen 0.093), im Fenster aber nur
# 0.036 gegen 0.051: der Kontrast sass in zu langen Wellen. Blocklage (46 m) und Feinrippe
# (37 m) sind im Bild Flecken von sechs bis acht Bildpunkten, also groesser als das Fenster.
# Die Flaechennormale dagegen aendert sich schon zwischen Nachbarn — von ihrer Streuung 0.211
# stehen 0.117 bereits im 3x3-Fenster (tools/_vulkan_fein.gd, "NY-STREUUNG").
# ES IST EIN TOR UND KEIN SUMMAND, und das ist der zweite Teil derselben Sache. Der Nebel bei
# 3,5 km liegt als ADDITIVER Sockel unter der Flanke (Schwarzprobe: 0.254 Bildhelligkeit bei
# Albedo null), unter ihn kommt keine Facette. Kontrast entsteht deshalb ausschliesslich durch
# HINZUGEFUEGTE Helligkeit, und bei festem Bildmittel haengt er allein daran, auf wie WENIGE
# Facetten sie verteilt ist. Solange jede Lage einzeln aufhellte, trug fast die ganze Flanke
# ein bisschen davon (Bildmedian 0.298 ueber einem Sockel von 0.258) — teuer im Mittel,
# wertlos im Fenster. Als Tor entscheidet die Decke stattdessen: entweder liegt Asche darueber
# und die Facette ist schwarz, oder sie liegt blank und traegt den vollen Ton.
# WER DIE FORM AENDERT, MISST DIE ZAHLEN NACH: sie haengen an der Verteilung der
# Flaechennormalen, also an Rippen, Barrancos, Bloecken und Nasen zusammen.
const VULKAN_DECKE_AB := -0.08
const VULKAN_DECKE_ZU := 0.14
# DER WUERFEL AUF DER SCHWELLE — UND ER HAT SEIT DIESER RUNDE ZWEI LAENGEN.
# Ohne Wuerfel faellt die Decke mit einer festen Schwelle auf die Normale, und weil die ueber
# eine Rippenflanke langsam kippt, waere ihr Rand eine gezeichnete Linie quer ueber jede
# Rippe. So weit galt das schon vorher und gilt weiter.
# WARUM DIE 13-M-LAGE DAS ALLEIN NICHT KONNTE, und das ist der ganze Befund dieser Runde:
# bei 6,07 m je Bildpunkt ist sie im Abnahmebild ein bis zwei Bildpunkte breit. Sie wuerfelt
# also zwischen NACHBARFACETTEN, und weil sie mit 0.70 der mit Abstand staerkste Summand im
# Treiber war, entschied praktisch sie allein, welche Facette blank liegt. Heraus kam genau
# das, was im Bild steht: einzelne helle Sprenkel im schwarzen Feld statt Schuttfelder.
# GEMESSEN (vk/kontrast.py) lag die Klumpigkeit — der Anteil heller Bildpunkte, deren vier
# Nachbarn auch hell sind — bei 0.633 gegen 0.705 in der Vorlage.
# DIE STREUUNG WAR DABEI NICHT DAS PROBLEM (0.0509 gegen 0.0444, also schon UEBER der
# Vorlage), und das ist die Falle, in die der Durchgang davor gelaufen ist: Punktrauschen
# trifft diese Zahl muehelos und sieht trotzdem falsch aus. Wer hier die Streuung weiter
# hochtreibt, baut denselben Sprenkel noch einmal (siehe Kopf von vk/kontrast.py).
# 90 M SIND RUND FUENFZEHN BILDPUNKTE, also deutlich mehr als das 9x9-Messfenster (55 m):
# benachbarte Facetten lesen jetzt denselben Wert und liegen gemeinsam blank oder gemeinsam
# zu — aus Sprenkeln werden Hangstuecke. NICHT WEITER HINAUF: ab rund 150 m deckt ein Feld
# eine ganze Kegelseite, und die Decke waere wieder das grosse weiche Fleckenmuster, an dem
# die Felslage schon einmal gescheitert ist (siehe VULKAN_HELL_SOCKEL).
const VULKAN_FELD_M := 90.0
const VULKAN_DECKE_FELD := 0.66
# DIE FEINE LAGE BLEIBT OBENAUF, nur nicht mehr als Fuehrung. Ohne sie haette das Feld einen
# glatten Rand und laege wie ausgeschnitten auf der Flanke; mit einem Sechstel des alten
# Gewichts franst sie ihn aus, ohne die Entscheidung noch zu tragen. Sie springt bei 8 m
# Netzweite von Facette zu Facette um 0.30 bei einer Streuung von 0.25
# (tools/_vk_korn_probe.gd), ist also praktisch unkorreliert.
# BEIDE ZUSAMMEN HALTEN DIE ALTE AMPLITUDE: 0.66 und 0.16 auf einer Lage mit Streuung 0.25
# ergeben 0.170 gegen vorher 0.175. Das ist Absicht — WIE VIEL Flaeche blank liegt (und
# damit das Bildmittel, das zwischen 0.28 und 0.33 bleiben soll) haengt an dieser Amplitude,
# WIE SIE VERTEILT IST an der Laenge. Diese Runde aendert nur die Verteilung.
const VULKAN_DECKE_KORN := 0.16
# WIE STARK DIE FORMLAGEN DIE DECKE AUFREISSEN. "kante" — Rippenkamm, Feinrippe,
# Barranco-Grat, Blocklage, Steilkante — sagt seit dieser Runde nicht mehr, WIE HELL eine
# Facette wird, sondern wie sehr sie dazu neigt, BLANK zu liegen: ein abgeblasener Gratruecken
# liegt schon bei geringerer Neigung frei, eine Rinnensohle sammelt.
# 0.22 IST BEWUSST KLEIN GEGEN DAS FENSTER (0.22 breit, also eine ganze Fensterbreite): die
# Lagen sollen den Rand der Decke verziehen, nicht an ihre Stelle treten — sonst waere ihre
# Wellenlaenge wieder die des Kontrasts, und genau davon kommt diese Runde her. Ganz ohne sie
# (0.0) folgt die Haut nur noch der Neigung, und Grat und Rinne verlieren ihre Handschrift:
# im Bild liegen die hellen Splitter dann als gleichmaessiger Sprenkel ueber der Flanke statt
# sich zu radialen Streifen auf den Ruecken zu sammeln.
# 0.12 -> 0.22 WAR IM MESSWERT UMSONST ZU HABEN (gerendert 0.310/0.0439 gegen 0.309/0.0445)
# und im Bild der Unterschied zwischen Sprenkel und Grat — deshalb der groessere Wert.
const VULKAN_DECKE_LAGEN := 0.22
# Staffelfenster auf "blank": darunter Basalt, darueber der volle Gesteinston. Es ersetzt den
# linearen Mischanteil, weil Zwischentoene den Mittelwert voll kosten und zur Streuung fast
# nichts beitragen — dieselbe Begruendung wie beim Tor darueber, eine Stufe tiefer.
const VULKAN_STAFFEL_AB := 0.24
const VULKAN_STAFFEL_VOLL := 0.44
# ROSTFLECKEN. Sie liegen NICHT als Hoehenband, sondern als Flecken: in der Vorlage sitzt das
# oxidierte Rotbraun in unregelmaessigen Partien quer ueber die Flanke, dichter unten, duenner
# oben. Der Fleckenwurf kommt aus _patch (einoktavig, also billig) auf rund 350 m gestreckt.
const VULKAN_ROST := Color(0.31, 0.135, 0.075)
# 350 -> 210 M. Die Zahl gehoert zum selben Befund wie die Blocklage: ein Fleck von 350 m
# ist auf der 790 m langen Flanke fast ein Drittel ihrer Laenge, und weil der Wurf
# einoktavig ist, lag das Rostbraun als grosse weiche Wolke darauf. Im Bild waren das
# zwei, drei braune Felder je Kegelseite, die mit keiner Kante zusammenfielen — dieselbe
# Sorte Fleck, wegen der die Felslage ihre Fuehrung abgeben musste, nur in Braun.
# 210 m sind rund die Laenge eines Barranco-Abschnitts: der Rost wechselt jetzt innerhalb
# einer Rinne und nicht mehr ueber den halben Berg.
# NICHT WEITER HERUNTER: unter rund 150 m faellt er in die Groessenordnung der Blocklage
# (46 m) und faerbt einzelne Aufschluesse ein, statt eine Partie zu ueberziehen — dann ist
# es kein Verwitterungssaum mehr, sondern buntes Gestein.
const VULKAN_ROST_M := 130.0
const VULKAN_ROST_AB := 0.12
const VULKAN_ROST_VOLL := 0.42
const VULKAN_ROST_STAERKE := 0.55
# WO DER ROST LIEGT — UND ZWAR IN DER RINNE UND NICHT AUF DEM GRAT.
# Der Fleckenwurf oben sagt nur, WIE VIEL oxidiert ist; er weiss nichts von der Form darunter,
# und deshalb lag der Rost bisher gleich dicht auf Kamm und Sohle. Die Vorlage macht es
# andersherum: der rostbraune Saum sitzt in den unteren Rinnen, wo der Feinschutt liegen
# bleibt und das Wasser steht, waehrend die abgeblasenen Grate grau sind.
# 0.42 heisst: auf dem vollen Barranco-Grat bleiben zwei Fuenftel der Deckung, in der Sohle
# die volle. AUSSERHALB DES RINNENBANDES AENDERT SICH NICHTS — der Faktor haengt an derselben
# Huellkurve wie die Rinne selbst, oben am Kraterrand und im Apron ist er also eins.
# 0.62 UND NICHT WENIGER, und das ist eine Korrektur an mir selbst: hier stand zuerst 0.42,
# und das haette eine Messung ueberschrieben, die weiter oben schon festgehalten ist — in der
# Vorlage sind ausgerechnet die hellsten Ruecken oft rotbraun ueberlaufen, der Rost meidet den
# Grat also nicht, er deckt dort nur duenner. Beides gilt zugleich: dicht in der Rinne, duenn
# auf dem Grat, nirgends fort.
# ZWEI ZAHLEN ZIEHEN MIT. VULKAN_ROST_STAERKE geht von 0.74 auf 0.84, weil der Rost durch die
# Umverteilung Flaeche verliert und die Flanke sonst insgesamt grauer wuerde statt nur anders
# verteilt — und weil sie nach der Messung ohnehin zu kalt stand (siehe VULKAN_GRAT). Der
# Faktor (1 - 0.35 * blank) in _vulkan_haut geht auf 0.26 herunter: er hat bisher ALLEIN die
# Aufgabe getragen, den Grat duenner zu decken, und tut es jetzt zu zweit.
const VULKAN_ROST_GRAT := 0.62
# Die HOEHE entscheidet weiter mit, aber nur noch ueber die Rostmenge und nicht mehr ueber
# die Gesteinsfarbe: oben ist die Asche jung und blank, unten ist sie verwittert. Dass die
# Zahlen von der alten Rampe stammen, ist kein Zufall — der Befund dahinter (unten braun,
# oben schwarz) war richtig, nur das Mittel war falsch.
const VULKAN_ASCHE_AB := 0.28
const VULKAN_ASCHE_VOLL := 0.68
# ... erstarrter Strom, noch eine Spur kaelter als der Basalt (er ist juenger als alles,
# worauf er liegt) ...
const VULKAN_STROM := Color(0.075, 0.072, 0.078)
# ... und offene Lava. SIE IST DIE EINZIGE FARBE DER WELT MIT EIGENLEUCHTEN: der Shader
# multipliziert genau diesen Ton mit der Glut aus dem Alphakanal.
const VULKAN_LAVA := Color(0.97, 0.31, 0.05)
# ... und dieselbe Lava, nachdem sie den halben Berg hinuntergelaufen ist: tiefrot, kaum
# noch gelb darin. Die Farbe der Ader wandert zwischen den beiden (siehe VULKAN_GLUT_KUEHL),
# und weil der Shader die EIGENE Farbe der Flaeche zum Leuchten bringt, kuehlt damit auch
# ihr Schein ab. Eine zweite, rote Lichtquelle waere derselbe Effekt zum doppelten Preis.
# SIE WAR ZWEIMAL ZU DUNKEL (0.46 und 0.55 im Rot). Auf dem Papier ist das die richtige
# Farbe fuer erkaltende Lava; im Bild verschwand die untere Flanke damit vollstaendig,
# denn sie liegt ohnehin im Schatten und der Basalt darunter ist fast schwarz. Die Vorlage
# zeigt dort ein kraeftiges Rot, kein Braunschwarz — abgekuehlt gegen den Kraterrand, aber
# unverkennbar noch offen. Das Schwarz ist den LAPPEN vorbehalten, und die sind Form, nicht
# nur Farbe.
const VULKAN_LAVA_KALT := Color(0.72, 0.12, 0.03)
# ZWEITE, FEINERE LAGE AUF DERSELBEN HELL-DUNKEL-ACHSE: die Felslage, die height_at als
# "fels" auftraegt (VULKAN_FELS_M, 150 m Welle). Sie schiebt den Gratanteil nach oben oder
# unten, statt eine eigene Helligkeit danebenzustellen — blank ist blank, egal welche Lage
# die Flaeche aufgebrochen hat. Ohne sie zerfaellt der Kegel in zehn saubere Speichen; mit
# ihr franst jeder Grat auf der Laenge aus.
# 0.55 AUF EINER LAGE, DIE VON -0.61 BIS 0.96 REICHT, sind +-0.4 auf blank — mehr als der
# Barranco-Grat selbst hatte. Die Felslage traegt zwar Gelaende (sie ist "fels" in der
# Massivtabelle), aber nur mit sv gewichtet, auf der Unterflanke also kaum noch: dort faerbte
# sie Felder, unter denen keine Form mehr lag. 0.40 laesst das Ausfransen und nimmt ihr die
# Fuehrung (siehe VULKAN_BARR_HELL).
const VULKAN_HAUT_KRUME := 0.18
# Mittelwert dieser Felslage, gemessen ueber die Vulkanflanke (tools/_vulkan_form.gd).
# Er steht hier, weil die Krume um ihn zentriert wird: ridged ist NICHT um null verteilt,
# und ohne die Verschiebung wuerde die Felslage den ganzen Kegel systematisch aufhellen
# statt ihn nur aufzurauen.
const VULKAN_KRUME_MITTE := 0.29
# BAUMGRENZE AM VULKAN, in Metern ueber NN. Die Weltbaumgrenze (FLORA_MAX_H, 230 m) ist fuer
# einen 650-m-Kegel die falsche Zahl: sie sitzt auf einem Drittel der Flankenhoehe, und weil
# die Dichte ueber die ganze Strecke von 46 bis 230 m ausblendet, kroch der Wald als immer
# duenner werdender Schleier ueber die halbe Flanke — grueneln bis weit hinauf, nirgends ein
# Waldrand. In der Vorlage steht er als DICHTER Kragen um den Fuss und hoert dann auf.
# Beide Zahlen liegen deshalb eng beieinander: bis 40 m voller Wald, ab 82 m keiner mehr.
# Am Fuss faellt der Hang mit rund 26 Grad, das sind 86 m Grundriss — ein Waldrand, kein
# Verlauf.
# 40..82 STANDEN HIER, UND DAS BAND WAR ZU BREIT — nicht in der Konstanten, sondern im Bild.
# Gemessen (tools/_vulkan_form.gd, "WALDSAUM") lag die Oberkante ueber 32 Richtungen zwischen
# 32 und 135 m, also 104 Hoehenmeter Streuung auf einer Grenze, die 42 breit sein sollte. Die
# Zacken (siehe VULKAN_BAUM_ZACK) legen sich naemlich AUF das Band und nicht hinein: der Wald
# reicht von AB - ZACK bis AUS + ZACK. Mit 44..68 und 22 Zacken sind das 22 bis 90 m statt
# 10 bis 112 — und die 24 m Bandbreite sind bei 26 Grad Hangneigung 49 m Grundriss, also gut
# sechs Bepflanzungszellen. Ein Waldrand, kein Verlauf.
# GEMESSEN steht die Oberkante damit ueber 32 Richtungen zwischen 53 und 75 m (Median 64), das
# Uebergangsband im Median bei 17 Hoehenmetern. Vorher waren es 32 bis 135 m.
# NOCH SCHMALER GEHT NICHT: unter rund 20 m Band faellt der Uebergang in weniger als drei
# Bepflanzungszellen, und dann steht dort keine Kante mehr, sondern eine Treppe aus 8-m-Feldern.
const VULKAN_BAUM_AB := 44.0
const VULKAN_BAUM_AUS := 68.0
# ... und weil eine reine Hoehenschranke einen gezeichneten Kreis um den Berg legt, wandert
# sie mit einer Rauschlage.
# HIER STAND DAFUER DAS WALDRAUSCHEN (_forest), UND GENAU DAS WAR DER FEHLER: dieselbe Lage
# setzt ueberall sonst die Waldinseln, sie entscheidet also zugleich ueber die DICHTE. Wo sie
# tief steht, faellt der Wald aus UND die Grenze rutscht ab; wo sie hoch steht, ist er dicht
# UND kriecht 30 m weiter hinauf. Beide Fehler zeigen in dieselbe Richtung und addieren sich —
# gemessen 7 von 32 Richtungen ganz ohne Wald neben Zungen, die bis 135 m hinaufreichten. Das
# war der Befund "der Uebergang liest sich als Zufall statt als Grenze".
# JETZT LAEUFT DIE ZACKE AUF _patch, also auf einer Lage, die mit der Dichte nichts zu tun hat,
# und auf einer eigenen, KURZEN Wellenlaenge: 130 m sind rund die Groesse eines Baumstandes.
# Der Rand kerbt damit ein, statt in grossen Bogen zu wandern — 22 m Zacke sind am 26-Grad-Fuss
# 45 m Grundriss, also eine sichtbare Kerbe je Welle.
const VULKAN_BAUM_ZACK := 22.0
const VULKAN_BAUM_M := 130.0
# WIE DICHT DER KRAGEN UNTER DER BAUMGRENZE STEHT, als Sockel unter der Walddichte (0 = wie
# die Weltregel es ergibt, 1 = geschlossener Bestand).
# WOFUER ES DEN SOCKEL BRAUCHT: die Weltdichte ist smoothstep(-0.28, 0.30, Waldrauschen) ZUM
# QUADRAT, sie steht also im Mittel bei einem Fuenftel und faellt auf einem Viertel der Flaeche
# ganz aus. Gemessen war die Deckung im Kragenband im Median 0.19 — ein Punktenebel, kein
# Kragen. Die Vorlage zeigt am Fuss einen GESCHLOSSENEN Bestand, der oben schlagartig aufhoert;
# die Grenze macht die Baumgrenze, nicht das Ausduennen.
# 0.85 UND NICHT 1.0: die Lichtungen des Waldrauschens sollen als Struktur erhalten bleiben,
# nur nicht mehr als Loecher. Was den Kragen darueber hinaus aufbricht, ist die Hangneigung in
# den Barrancos und die schwarze Lava — beides bleibt unangetastet und ist genau die
# Verzahnung von Gruen und Schwarz, die die Vorlage am Fuss zeigt.
const VULKAN_KRAGEN_DICHT := 0.85
# WIE WEIT DER SOCKEL NACH AUSSEN REICHT, als Vielfaches des Massivradius. Der Kragen sitzt auf
# dem Kegel zwischen rund 0.78 und 0.86 * r (dort liegen 26 bis 82 m Hoehe); nach aussen laeuft
# er ueber den Fuss in das Vorland weiter, weil ein Waldguertel, der genau am Fussradius
# aufhoert, wieder ein gezeichneter Kreis waere.
# ER MUSS UEBER DAS VORLAND MITREICHEN, weil dort die Biome liegen: gemessen sind 17 von 64
# Fussrichtungen WUESTE, und die Weltregel laesst dort ein Zwanzigstel der Dichte stehen und
# sperrt ausserdem alles ueber 28 m. Ohne den Sockel fehlt der Kragen in diesen Sektoren
# vollstaendig — das waren die Loecher im Ring.
# NICHT UEBER DIE HAUTREICHWEITE HINAUS ("reich2" in _vulkane_bauen): _face_color bricht
# seine Vulkanschleife an dieser Schranke ab und wuerde den Sockel weiter draussen nicht mehr
# sehen — der Guertel stuende dann als Wald auf ungefaerbtem Wuestenboden.
# 1.10/1.30 STANDEN HIER, UND MIT DER SCHUERZE WAREN SIE FALSCH GEWORDEN. Die Zahlen sind
# Vielfache des FUSSRADIUS, das Kragenband liegt aber in einer HOEHENLAGE (26 bis 82 m), und
# die ist mit der Schuerze nach aussen gewandert: sie steht am Kegelfuss noch 93 m hoch und
# traegt erst ueber die naechsten 1000 m aus. Gemessen liegt das Band jetzt zwischen rund
# 1.15 und 1.28 * r — die alte Ausblendung von 1.10 bis 1.30 lag also GENAU DARAUF und hat
# den Kragen auf halber Strecke ausgeknipst.
# 1.44/1.56 legen sie hinter das Band. Die Hautreichweite ist mit Schuerze 1.58 * r
# (VULKAN_APRON_WEIT), die Schranke oben ist damit gerade noch eingehalten — und sie ist der
# Grund, warum die Schuerze nicht beliebig hoch werden darf: je maechtiger sie ist, desto
# weiter draussen liegt das Kragenband, und bei 1.58 ist Schluss.
const VULKAN_KRAGEN_VOLL := 1.44
const VULKAN_KRAGEN_AUS := 1.56
# WIE STARK DER WALDBODEN IM KRAGEN DEN BASALT ZUDECKT. Ohne ihn war der Kragen ein gruener
# Punktenebel auf schwarzem Grund und nichts, was man einen Wald nennt: die Weltregel duennt
# die Baumdichte nach der HANGNEIGUNG aus, und am Fuss dieses Kegels stehen 26 Grad, also
# bleibt rund ein Fuenftel der Dichte uebrig. Einzelne Nadelbaeume auf schwarzem Fels lesen
# sich nicht als Waldrand. Denselben Handgriff macht die Welt ueberall (siehe WALDBODEN in
# _boden_farbe) — hier steht er nur auf der Haut statt auf der Wiese.
# NICHT GANZ ZUDECKEN: zwischen den Staemmen schaut der Fels durch, und genau daran liest man,
# dass dieser Wald auf einem Vulkan steht. In der Vorlage verzahnen sich Gruen und Schwarz am
# Fuss ebenso.
# 0.80 -> 0.66, UND DER GRUND IST DER DICHTESOCKEL. Die Begruendung oben stammt aus der Zeit,
# in der die Weltregel im Kragen rund ein Fuenftel der Dichte uebrigliess: der Boden musste
# den Wald damals mitspielen, weil zu wenige Baeume dastanden. Seit VULKAN_KRAGEN_DICHT den
# Bestand schliesst, tun das die Baeume selbst — und der breit aufgetragene Waldboden war im
# Bild nur noch ein heller Wiesenschimmer, der ueber den Fuss hinauflief. Weniger Boden heisst
# jetzt mehr Schwarz zwischen den Staemmen, also genau die Verzahnung, um die es geht.
const VULKAN_KRAGEN := 0.66
# LAVAZUNGEN. Zahl der Lappen rund um den Kegel und wie schnell das Muster hangabwaerts
# wandert — dieselbe Bauart wie bei den Rippen (siehe VULKAN_RIPPEN_LAUF), damit die Zunge
# nicht als kerzengerader Tortenschnitt vom Gipfel weglaeuft, sondern seitlich maeandert.
const VULKAN_ZUNGEN_N := 7.0
const VULKAN_ZUNGEN_LAUF := 0.75
# VERSATZ IM RAUSCHRAUM, und er ist NICHT beliebig, obwohl jede Zahl fuer sich gleich gut
# aussieht, solange man nur eine Seite des Berges betrachtet. Ohne ihn (also bei null)
# lagen die Stroeme gemessen in 9 von 24 Richtungen und ballten sich dabei auf einer
# Haelfte: ausgerechnet die Nordflanke, aus der die Abnahme den Berg ansieht, hatte keinen
# einzigen — und ein Vulkan schuettet nicht nur nach Sueden. Abgesucht wurden 65 Versaetze
# (Kriterium: moeglichst viele Richtungen bei moeglichst wenig Gesamtflaeche); mit 5600
# stehen sie jetzt in 15 von 24 Richtungen, bei nur wenig mehr Flaeche.
const VULKAN_ZUNGEN_OX := 5600.0
# Schwellen auf dem Zungenrauschen. Sie entscheiden, wie viel vom Umfang ein Strom bedeckt;
# gemessen sind es 16 Prozent der Kegelflaeche und 23 Prozent des Rings dahinter
# (tools/_vulkan_form.gd).
const VULKAN_ZUNGEN_AB := 0.07
const VULKAN_ZUNGEN_VOLL := 0.15
# WELCHE RINNEN UEBERHAUPT GLUEHEN. Abgetastet wird DASSELBE Rauschen, mit dem height_at
# die Rippen aufwirft, nur andersherum gelesen: seine hohen Werte sind die Kaemme, seine
# tiefen die Muldenzuege dazwischen. Die Schwellen sind an der gemessenen Verteilung
# gewaehlt (tools/_vulkan_form.gd druckt sie): auf dem Kegel liegt das Rippenrauschen
# zwischen -0.41 und 0.94 mit dem Mittel bei 0.38, das Zehntel der tiefsten Rinnen faengt
# bei 0.08 an.
# SEINE AUFGABE HAT SICH GEAENDERT, SEIT ES BARRANCOS GIBT. Vorher war dieses Rauschen die
# Glut selbst, und weil sein Abtastkreis nur mit der WURZEL des Abstands waechst, war eine
# Schwelle darauf oben ein 300 m breiter Lappen: im Bild lagen flaechige orange Flecken OBEN
# AUF der Flanke, wie aufgemalt. Jetzt sagt es nur noch, WO AM UMFANG etwas fliesst.
# ES WIRD DAFUER ANDERS ABGETASTET ALS FUER DIE GESTEINSFARBE, und das ist der Kern der
# Sache: FESTER Kreis (kein sqrt(md)) und ZWEI Achsen (keine dritte den Hang hinunter). Der
# Abtastpunkt haengt damit nur noch von der RICHTUNG ab — laengs eines Radialstrahls ist der
# Sektor konstant, von der Lippe bis in den Apron. Genau das hat im ersten Anlauf gefehlt:
# mit der wandernden dritten Achse schnitt schon diese Maske die Ader alle 50 m durch, und
# im Bild standen kurze orange Striche quer ueber der Flanke statt Adern, die den Berg
# hinunterlaufen. Wer hier wieder eine dritte Achse einzieht, bekommt die Striche zurueck.
# VIER GRUNDLAPPEN WAREN ZU WENIG: das Rauschen hat dann genau EINE tiefe Stelle auf dem
# Umfang, und im Bild gluehte eine geschlossene Gruppe von sechs Nachbarrinnen auf einer
# Seite, waehrend die anderen drei Viertel des Kegels vollkommen kalt dastanden. Ein Vulkan
# schuettet nicht nur nach einer Himmelsrichtung — derselbe Befund hat schon die Lavazungen
# ihren Versatz gekostet (VULKAN_ZUNGEN_OX).
# SIEBEN geben zwei bis drei getrennte Gruppen rings um den Kegel. Bei zehn wie bei den
# Rippen waere jede zweite Rinne dran und der Kegel ein Lampion.
# WAS DAVON HEUTE NOCH GILT: die Zahl und die Abtastung (fester Kreis, zwei Achsen, also
# eine reine Funktion der Richtung). Die BEGRUENDUNG darunter hat gewechselt — sie waehlt
# keine Rinnen mehr aus, dafuer gibt es den Baum, sie sagt nur noch, welche Seite des
# Berges heisser ist (siehe VULKAN_GLUT_SEITE).
const VULKAN_GLUT_SEKTOR_N := 7.0
# Schwellen auf demselben Rauschen (Verteilung siehe tools/_vulkan_form.gd: -0.41 bis 0.94,
# Mittel 0.38, unterstes Zehntel ab 0.08). 0.26/0.07 waren zusammen mit allen anderen
# Masken zu eng — gemessen blieben 0.8 Prozent Glut, und die lagen als Tupfer da.
const VULKAN_GLUT_AB := 0.38
const VULKAN_GLUT_VOLL := 0.06
# ... UND ES SCHALTET NICHTS MEHR AUS, ES DAEMPFT NUR NOCH. Solange dieses Rauschen die
# Adern AUSGEWAEHLT hat, lagen auf dem Kegel rund acht Baender: gleich breit, unverzweigt,
# zueinander parallel, alle am Kraterrand angesetzt und auf halber Flanke ohne Abschluss
# zu Ende. Das ist kein Lavanetz, das ist ein Zebrastreifen — und die Ursache war genau
# diese Maske, denn eine Schwelle auf einer Winkelfunktion kann nur BAENDER erzeugen, nie
# eine Verzweigung. Das Netz baut jetzt _vulkan_ader als Baum; hier bleibt die Aufgabe,
# fuer die eine Richtungsmaske taugt: dass eine Seite des Berges heisser ist als die
# andere. 0.58 ist, was der kalten Seite bleibt — sichtbar kuehler, aber nicht abgeschnitten.
# 0.34 WAR ZU WENIG: mit wenigen Staemmen sieht eine Kamera nur zwei bis vier davon, und wenn einer
# davon auf der kalten Seite steht, ist die halbe sichtbare Flanke leer. Bei acht Baendern
# fiel das nicht auf, bei vier schon.
# EIN HARTER SCHNITT DARF ES NICHT SEIN: eine Ader wandert beim Gabeln um bis zu vier
# Rinnen zur Seite, sie kreuzt also Sektorgrenzen. Wo die Maske ausschaltet, endet die Ader
# mitten am Hang — der Mangel, aus dem diese Runde herausfuehren soll.
const VULKAN_GLUT_SEITE := 0.58
# --- DAS LAVANETZ: EIN BAUM, KEINE BAENDER -----------------------------------------------
# Acht Staemme am Kraterrand, und jeder gabelt sich auf dem Weg nach unten zweimal — 32
# Enden am Fuss, also genau eine je Barranco (Begruendung bei VULKAN_BARR_N). Gerechnet
# wird das OHNE Rauschen, allein auf der stetigen Rinnenkoordinate: die Achse eines Astes
# ist die MITTE seiner Zelle, und beim Gabeln wandert der Punkt von der Elternmitte zu der
# des Kindes. Zwei Kinder, die aus einer Elternmitte nach beiden Seiten auseinanderlaufen,
# sind ein Y — man muss es nicht als Y rechnen, es faellt aus der Zellteilung heraus.
# ACHT STAEMME UND ZWEI GABELUNGEN, NICHT VIER UND DREI — und das ist eine Rechnung ueber
# den WINKEL, unter dem eine Ader den Hang quert, nicht ueber ihre Zahl.
# Beim Gabeln wandert ein Ast um eine VIERTEL Zellbreite zur Seite. Mit vier Staemmen ist die
# oberste Zelle 8 Rinnen breit, der Ast wandert also zwei Rinnen — auf halber Flanke sind das
# 244 m quer, waehrend die Gabelung nur ein Drittel der Flanke (330 m) Fallstrecke hat. Im
# fertigen Bild lief die Ader damit fast waagerecht ueber die Rippen hinweg, quer zu jeder
# Rinne, in die sie eigentlich gehoert: 36 Grad aus der Falllinie.
# Mit acht Staemmen ist die oberste Zelle 4 Rinnen breit, der Ast wandert eine Rinne, und
# weil eine Gabelung weniger noetig ist, hat jede die HALBE Flanke Fallstrecke. Das sind rund
# 17 Grad — eine Ader, die sichtbar bergab laeuft und sich dabei einen neuen Weg sucht.
# DAS ALTE BILD, VOR DEM DIE VIER STAEMME SCHUETZEN SOLLTEN, war ein anderes: acht gerade,
# parallele, UNVERZWEIGTE Baender. Verzweigt sind sie hier, sie maeandern mit den Rinnen und
# sie sind verschieden stark (VULKAN_ADER_WURF) — der Fehler von damals steckte nicht in der
# Zahl acht, sondern im Fehlen des Baums.
# 8 * 2^2 SIND WEITER 32 ENDEN, also eine je Barranco. Die Zellbreiten bleiben Zweierpotenzen
# (4, 2, 1), und daran haengt sowohl die Naht bei +-pi als auch der Versatz, mit dem die
# Achsen in den Sohlen liegen (VULKAN_BARR_VERSATZ).
const VULKAN_ADER_STAEMME := 8.0
const VULKAN_ADER_GABELN := 2.0
# WO DIE DRITTE UND LETZTE GABELUNG FERTIG IST, als Anteil des Fussradius. 1.0 heisst: am
# Fussradius selbst, und dort sitzt die feinste Aderachse dann genau auf einer Rinnensohle.
# KLEINER ALS 1 GEHT, GROESSER NICHT: bei 1.1 waere die letzte Gabelung am Fuss noch nicht
# durch, die Achse laege zwischen zwei Sohlen, und das Netz liefe quer zu den Rinnen.
const VULKAN_ADER_FUSS := 1.0
# ... und wie die zwei Gabelungen darauf verteilt sind. 1 waere gleichmaessig (Gabelungen auf
# 855 und 1250 m); 1.25 schiebt sie nach aussen (913 und 1250 m) und laesst der Oberflanke
# ihre acht Staemme. Viel groesser darf er nicht werden: dann draengen sich beide Gabelungen
# in das unterste Viertel, und dort gabelt sich nichts mehr, es franst nur noch aus.
const VULKAN_ADER_GABEL_K := 1.25
# HALBE BREITE DES GLUEHENDEN KERNS, in RINNENBREITEN (nicht in halben, wie bis zuletzt).
# Der Exponent gilt der Zellbreite: ein Ast mit halber Zelle ist 2^-0.66 = 0.63 mal so
# breit, die Breite halbiert sich also ungefaehr alle zwei Gabelungen.
# HIER STAND EINE NACHRECHNUNG UEBER 0.056/0.85 UND 70 m KANALBREITE, waehrend in der Zeile
# darunter 0.024/0.72 stand — die Zahlen im Text haben nie zum Code gehoert. Deshalb steht
# hier jetzt, was tools/_vulkan_form.gd MISST: mit 0.024/0.72 waren es 54 m Glutbreite bei
# 520 m und 22 m bei 1120 m.
# UND DAS WAR ZU BREIT. Der Befund am Abnahmebild lautete "fuenf gleichbreite gesaettigte
# Baender", und 54 m orange auf einer Flanke, deren Rinne 100 m breit ist, sind genau das:
# der Strom fuellt seine halbe Rinne aus, statt eine Linie in ihrer Sohle zu sein. In der
# Vorlage ist die Ader ein FADEN mit einem breiten schwarzen Saum (VULKAN_ADER_KRUSTE), und
# der Saum macht die Zeichnung, nicht die Glut.
# DIE ZAHLEN SIND SEIT ACHT STAEMMEN ANDERE (VULKAN_ADER_STAEMME): die oberste Zelle ist nur
# noch 4 statt 8 Rinnen breit, ein Kern derselben Formel waere am Stamm also von selbst
# duenner geworden. 0.023/0.78 halten ihn dort bei rund 26 m Glutbreite und lassen ihm am
# feinsten Ast noch 19 m.
# WEITER RUNTER GEHT NICHT: die Netzweite ist 8 m, und eine Ader von zwei Dreiecken Breite
# flackert beim Fliegen, weil sie zwischen den Facetten hin- und herspringt. Was die Ader
# duenner aussehen laesst, ist der Saum (VULKAN_ADER_SAUM), nicht der Kern.
const VULKAN_ADER_KERN := 0.023
const VULKAN_ADER_DICK := 0.78
# Der Kern glueht voll, bis SAUM mal Kern faellt er auf null ab, und bis KRUSTE mal Kern
# liegt schwarze, matte Kruste. DASS DIE KRUSTE VIEL BREITER IST ALS DIE GLUT, ist der
# Punkt: ein Strom zeigt nur seinen Kanal offen, der Rest ist erstarrt. Ohne sie sass das
# Orange unvermittelt auf braunem Gestein und sah aufgemalt aus.
# SAUM 2.2 -> 1.9 UND KRUSTE 4.2 -> 5.4: beide Zahlen sind Vielfache des Kerns, und der ist
# gerade um ein Viertel geschrumpft. Waeren sie stehen geblieben, waere mit dem Kern auch
# der schwarze Saum geschrumpft — die Ader haette dann nur weniger von allem gehabt statt
# ein duenner Faden in einem breiten erstarrten Bett zu sein. Gerechnet: die Kruste ist
# jetzt rund 2,8-mal so breit wie die Glut (vorher 1,9-mal).
const VULKAN_ADER_SAUM := 1.9
const VULKAN_ADER_KRUSTE := 5.4
# WIE UNGLEICH DIE AESTE SIND. Je Ast einmal gewuerfelt (siehe _vulkan_ader_wurf) und ueber
# die Gabelung von der Eltern- auf die Kindzahl geblendet: an einer Gabel wird der eine Arm
# heller als der andere, und das ist der Unterschied zwischen einem Geflecht und einem
# Ornament. Der schwaechste Ast behaelt 0.55 — dunkel, aber nicht verschwunden, denn seine
# Kruste zeichnet ihn weiter.
# 0.40 WAREN ZU WENIG, SEIT DIE ADERN DUENN SIND. Der Ringzaehler findet auf 1000 m Abstand
# 27 Adern, im Bild sind es vier bis fuenf: ein 20 m schmaler Faden mit 40 Prozent Leuchtkraft
# geht neben einem mit voller Leuchtkraft unter, und uebrig blieben genau die Hauptstaemme —
# also wieder "ein paar breite Baender" statt eines Netzes. Mit 0.55 traegt auch der
# schwaechste Ast noch, ohne dass die Gabelung ihren staerkeren und ihren schwaecheren Arm
# verliert. VULKAN_LAPPEN_KRAFT ist mitgezogen, weil es auf DERSELBEN Zahl schwellt.
const VULKAN_ADER_WURF := 0.55
# UNTERBRECHUNG DER LAENGE NACH. Eine Ader, die ohne Luecke von der Lippe bis in die Ebene
# durchlaeuft, sieht aus wie ein gezogener Strich. Dieses Rauschen laeuft deshalb schneller
# den Hang hinunter als um ihn herum (dritte Achse gegen einen schmalen Abtastkreis): es
# unterbricht die Ader quer, statt sie laengs zu spalten.
# 5.2 UND 0.34/0.12 WAREN VIEL ZU SCHARF. Zusammen mit dem damals ebenfalls wandernden
# Sektor blieben von der Ader 40 m lange Striche mit 4:1 Seitenverhaeltnis — im Bild
# Zaehlstriche, keine Lavaadern. Jetzt laeuft es halb so schnell und laesst gut die Haelfte
# offen: die Ader haelt ueber mehrere hundert Meter durch und setzt nur ab und zu aus.
# Der Abtastkreis bleibt bewusst SCHMAL (1.4 Lappen): quer zur Ader soll dieses Rauschen
# moeglichst nichts tun, sonst schiebt es die Glut aus der Sohle.
const VULKAN_ADER_TAKT := 1.4
const VULKAN_ADER_LAUF := 2.0
const VULKAN_ADER_AB := 0.62
const VULKAN_ADER_VOLL := 0.24
# WAS DER ADER AN DER SCHWAECHSTEN STELLE BLEIBT. 0.45 stand hier, solange die Unterbrechung
# die Nebenarme ganz ausknipsen sollte — das war der Ersatz fuer eine Verzweigung, die es
# noch nicht gab. Jetzt gibt es sie, und die Unterbrechung hat nur noch die Aufgabe, den
# Kanal ueberkrusten zu lassen: sie darf ihn daempfen, nicht durchschneiden. Eine Ader, die
# alle 200 m aussetzt, ist wieder eine Reihe von Strichen.
const VULKAN_ADER_GRUND := 0.62
# --- WIE WEIT UNTEN NOCH ETWAS GLUEHT UND WIE HEISS -------------------------------------
# ZWEI RAMPEN AUF DER HOEHE, UND SIE TUN VERSCHIEDENES. Die erste sagt, OB an dieser Stelle
# ueberhaupt noch offene Lava liegt; die zweite, WIE HEISS sie ist. Vorher war es eine
# einzige, und daran ist die Ader auf halber Flanke gestorben: voll erst ab einem Drittel
# der Kegelhoehe, aus bei einem Zwanzigstel — das sind, auf den Abstand umgerechnet, 560
# bis 950 m, also endete jede Ader bei drei Vierteln des Fussradius im Nichts.
# Jetzt laeuft der Kanal DURCH BIS AN DEN BERGFUSS und kuehlt dabei ab: voll ab 58 m ueber
# NN, ganz aus erst bei 28 m — das ist die Fussschwelle der Vulkanhaut selbst, weiter unten
# gibt es keinen Kegel mehr. GEMESSEN hat der erste Anlauf mit 0.015/0.10 die unterste Glut
# im Mittel auf 296 m stehen lassen, also auf halber Flankenhoehe; das Werkzeug zaehlt sie
# jetzt (tools/_vulkan_form.gd, LAVANETZ), damit dieser Befund nicht wieder erst aus einem
# fremden Blick aufs Bild kommen muss.
const VULKAN_GLUT_UNTEN := 0.004
const VULKAN_GLUT_OBEN := 0.055
# ... und das ist die Abkuehlung: oben hellorange, im unteren Drittel tiefrot. Sie faerbt
# NICHT nur, sie nimmt auch Leuchtkraft (VULKAN_GLUT_MATT ist der Rest ganz unten). Beides
# gehoert zusammen — eine dunkelrote Flaeche, die so hell strahlt wie eine orange, liest
# sich nicht als kuehler, sondern als andersfarbig.
# 0.52 STAND HIER EINEN RENDER LANG UND IST WIEDER WEG. Die Ueberlegung war, dass die Ader
# ueber ihre ganze Laenge in derselben gesaettigten Orange steht und deshalb aufgemalt
# aussieht; die Grenze sollte auf halbe Flankenhoehe (325 m) hoch, damit unten tiefes Rot
# liegt. Im Bild kam etwas anderes heraus: unter der halben Hoehe liegt die Flanke ohnehin
# im Schatten und traegt fast schwarzen Basalt, und eine dunkelrote Ader darauf ist keine
# Ader mehr, sondern verschwindet. Das Netz endete optisch auf halber Flanke — genau der
# Befund, gegen den VULKAN_GLUT_UNTEN/OBEN gebaut wurden. Und die Vorlage gibt es auch nicht
# her: dort leuchten die Faeden bis in den Waldkragen hinunter orange.
# DAS AUFGEMALTE lag nie an der Farbe, sondern an der BREITE (siehe VULKAN_ADER_KERN).
const VULKAN_GLUT_KUEHL := 0.00
const VULKAN_GLUT_HEISS := 0.30
const VULKAN_GLUT_MATT := 0.58
# --- DIE LAVALAPPEN AM BERGFUSS ----------------------------------------------------------
# WOFUER SIE DA SIND: eine Ader, die am Fuss einfach aufhoert, hat keinen Abschluss — und
# ohne Abschluss liest das Auge sie als abgeschnitten statt als ausgelaufen. Wo ein Ast
# ankommt, breitet er sich deshalb aus, erstarrt und bleibt als schwarzer, erhabener Lappen
# liegen. Er hat HOEHE ("lava_lappen" in der Massivtabelle, 2 bis 4 Bloecke), denn ein
# erkalteter Strom liegt AUF dem Gelaende, er faerbt es nicht nur ein.
# Die Huelle in Anteilen des Fussradius. SIE ENDET AUF DEM FUSSRADIUS, nicht dahinter, und
# zwar aus demselben zwingenden Grund wie die Barrancos: jenseits von mr traegt height_at
# nichts mehr auf, ein Lappen dort waere eine senkrechte Wand (siehe VULKAN_BARR_AUS_ZU).
# Voll ist er bei 0.93, also auf 1160 m — dort steht der Kegel noch rund 45 m hoch, und
# genau da faengt der Waldkragen an. Der Lappen legt sich also in den Waldrand hinein, so
# wie ein Strom, der im Gruen zum Stehen kommt.
# ER FAENGT ERST BEI 0.86 AN UND NICHT SCHON BEI 0.80: der Lappen loescht die Glut (er IST
# das Erkaltete), und bei 0.80 nahm er der Ader die untersten 250 m Weg weg — im Bild hoerte
# sie wieder auf halber Flanke auf, nur diesmal mit Begruendung.
const VULKAN_LAPPEN_AB := 0.86
const VULKAN_LAPPEN_VOLL := 0.93
const VULKAN_LAPPEN_AUS_AB := 0.97
const VULKAN_LAPPEN_AUS_ZU := 1.00
# Halbe Breite des Lappens in Rinnenbreiten: bei 1150 m Abstand sind 0.34 rund 78 m, der
# Lappen ist also gut 150 m breit — deutlich breiter als die Ader, die ihn speist, so wie
# ein Strom sich auf flachem Grund ausbreitet.
const VULKAN_LAPPEN_BREIT := 0.34
# NUR STARKE AESTE BILDEN EINEN LAPPEN. Sonst laege am Fuss ein geschlossener schwarzer
# Kranz aus 32 Lappen, und der ist kein Abschluss, sondern ein Sockel.
# DIE SCHWELLE SITZT AUF ad.z, UND DEREN UNTERGRENZE IST VULKAN_ADER_WURF — die beiden Zahlen
# muessen deshalb zusammen wandern. Als der Wurf von 0.40 auf 0.55 ging, lag mit 0.52 jeder
# einzelne Ast ueber der Schwelle, und der Kranz waere geschlossen gewesen. 0.64 trifft
# denselben Ausschnitt der Verteilung wie vorher; die Probe dafuer steht in
# tools/_vulkan_form.gd (LAVALAPPEN AM FUSS, rund ein Zehntel des Apron-Rings).
const VULKAN_LAPPEN_KRAFT := 0.64
# DER SCHLUND. Anteil des Kraterradius, bis zu dem der Kraterboden schwarz wird, und der
# engere Kern, in dem er glueht. Der Boden ist eine breite waagerechte Flaeche und faengt
# deshalb das meiste Licht ab; ohne einen dunklen Kern darin liest er sich als helle Pfanne.
# Genau dieser Befund hat schon den Schlot in die Geometrie gebracht — die Farbe macht
# daraus jetzt, was die Form allein nicht kann.
const VULKAN_SCHLUND := 0.34
const VULKAN_SCHLUND_KERN := 0.15

# --- DIE SCHUERZE AM FUSS (APRON) ---------------------------------------------------------
# WOGEGEN SIE GEBAUT IST, in den Worten der Abnahme: "der Kegel braucht statt des glatten
# Kreissaums einen radial gerippten Fuss-Faecher, dessen Rinnen die Lava bis in die Ebene
# tragen — erst dann sitzt der Berg im Land, statt darauf zu stehen." Genau das war der
# Befund: der Kegel endete bei mr auf den Meter, und ringsum lag ungestoerte gruene Wiese.
#
# WARUM SIE NICHT EINFACH EIN GROESSERES "r" IST: der Fussradius bestimmt zugleich die
# Flankenneigung (peak / (r - crater_r)). Zieht man ihn hoch, wird der Berg flacher — und
# die Neigung war das einzige an diesem Kegel, das die Abnahme ausdruecklich stehenlassen
# wollte. Die Schuerze ist deshalb ein ZWEITER, sehr flacher Kegel unter dem ersten: er
# traegt den Gipfel um "apron" Meter hoeher und laeuft ueber mehr als das Anderthalbfache
# des Fussradius aus. Der Kegel behaelt seine 47 bis 26 Grad, und der Berg bekommt
# trotzdem eine Basis, die man aus mehreren Kilometern noch als Massiv liest.
#
# 1.53 IST DIE GRENZE DES LANDES, NICHT EIN GESCHMACK. Gemessen (tools/_vulkan_umland.gd)
# liegt rings um den Vulkan Land bis rund 3400 m; erst danach faellt der Grund unter den
# Meeresspiegel. Bei r = 1900 m sind 1.58 rund 3000 m — die Schuerze bleibt also ueberall
# an Land. Wer weiter hinausgeht, hebt den Meeresgrund an und macht aus der Bucht im
# Nordosten eine Sandbank; die Probe dafuer ist genau jenes Werkzeug.
# 1.58 -> 1.45, UND DIE LANDGRENZE IST DABEI GAR NICHT MEHR DIE BINDENDE: der Fussradius
# des Kegels ist von 1900 auf 1350 gegangen (siehe Main, Massivtabelle), 1.58 waeren also
# ohnehin nur noch 2130 statt 3000 m. Die Zahl geht trotzdem herunter, weil die Schuerze
# sonst im VERHAELTNIS zum Kegel breiter wuerde als vorher — und genau ihr flacher
# Aussensaum war es, der den Berg gedrungen aussehen liess. 1958 m Aussenradius bleiben
# klar innerhalb der gemessenen 3400 m Land (tools/_vulkan_umland.gd).
const VULKAN_APRON_WEIT := 1.45
# DER EXPONENT AUF DEM PROFIL, und er ist der Unterschied zwischen Schuerze und Sockel.
# Die Grundkurve ist 1 - smoothstep(0, apr, md): sie hat an BEIDEN Enden die Steigung null,
# laeuft also im Vorland tangential aus (kein gezeichneter Ring am Saum) und liegt unter dem
# Kegel als Plateau. Roh (Exponent 1) waere die Schuerze aber auf halber Strecke am
# steilsten — mitten auf der Kegelflanke, wo sie 5 Grad dazugaebe.
# Der Exponent UNTER 1 schiebt die Masse nach aussen: unter dem Kegel bleibt die Kurve
# flach, und der Abfall passiert dort, wo der Kegel schon zu Ende ist. Bei 0.55 steht die
# Schuerze am Kegelfuss noch auf der Haelfte ihrer Hoehe und traegt von dort ueber 1100 m
# mit rund 5 Grad aus — das ist die lange konkave Basis, die gefehlt hat.
# 0.55 -> 0.85, UND DAS IST DIE KORREKTUR AN GENAU DIESEM SATZ. "Lange konkave Basis" war
# das Ziel, herausgekommen ist die flache Rampe, die der Abnahme danach als Grund fuer
# "gedrungen" aufgefallen ist: gemessen trug die Schuerze am Kegelfuss noch 125 m und lief
# von dort mit 9 Grad aus, waehrend die Flanke darueber mit 36 Grad ankam. Ein Knick von
# 27 Grad liest sich nicht als konkav, sondern als Berg auf einem Teller.
# 0.85 laesst den Exponenten UNTER eins — die Schuerze bleibt also unter dem Kegel flach
# und kippt ihn nicht — und zieht trotzdem so viel Masse nach innen, dass sie am Kegelfuss
# nur noch 69 m traegt. Das ist die Hoehe der Baumgrenze (VULKAN_BAUM_AUS): das steile
# Profil laeuft damit bis kurz vor den Wald durch, statt vorher auf eine Rampe zu kippen.
# NICHT AUF ODER UEBER 1: dann ist die Schuerze auf halber Strecke am steilsten, und das
# ist mitten auf der Kegelflanke — sie wuerde dort die Boeschung mitdrehen, die gerade erst
# auf 32 Grad eingestellt wurde.
const VULKAN_APRON_K := 0.85
# DIE RINNEN DES FAECHERS. Sie sind DIESELBEN Rinnen wie die Barrancos der Flanke
# (_vulkan_rinne, gleiche Phase, gleicher Maeander) und nicht ein zweites Muster daneben —
# nur so laeuft eine Rinne wirklich vom Kraterrand bis in die Ebene durch, statt am Fuss zu
# enden und ein paar hundert Meter weiter neu anzufangen.
# DIE HUELLEN UEBERLAPPEN MIT ABSICHT: die Barrancos laufen zwischen 0.87 und 1.00 * mr aus
# (VULKAN_BARR_AUS_AB/ZU), die Faecherrinnen blenden ab 0.78 ein. Im Uebergabeband liegen
# beide an, und weil sie dieselbe Phase haben, addieren sie sich zu einer durchgehenden
# Rinne. Haette man sie stumpf aneinandergesetzt, staende am Fuss eine Reihe von Absaetzen.
const VULKAN_APRON_RIP_AB := 0.78
const VULKAN_APRON_RIP_VOLL := 1.02
const VULKAN_APRON_RIP_AUS := 0.80
# --- DER SCHUTT AUF DEM FAECHER -----------------------------------------------------------
# GEMESSEN, NICHT GESCHAETZT: der erste fertige Faecher hatte einen mittleren
# Helligkeitssprung von Bildpunkt zu Bildpunkt von 0.0039. Die Vorlage steht am selben Ort
# bei 0.0274, die Kegelflanke daneben bei 0.0143. Der Faecher war also SIEBENMAL glatter als
# das Vorbild — im Bild ein Tuch, das jemand um den Berg gelegt hat.
# Das kann die Rinnenlage nicht heilen: eine Rinne ist draussen 470 m breit, ihre Wand steht
# auf 9 Grad, und ueber 470 m sieht das Auge keine Koernung, sondern eine Woelbung. Es fehlt
# die kurze Welle, und die gibt es an diesem Berg schon — die BLOCKLAGE (VULKAN_BLOCK_M,
# 46 m). Sie laeuft auf der Flanke zwischen 0.72 und 0.86 * r aus; hier setzt sie genau dort
# wieder an und traegt bis in den Faecher hinein.
# WARUM SIE VOR DEM WALDKRAGEN AUFHOEREN MUSS (1.06 .. 1.18): die Bepflanzung duennt nach
# dem Hoehenunterschied ueber der 8-m-Zelle aus und faellt ueber 4,6 m ganz aus. Der Kragen
# liegt jetzt draussen auf der Schuerze (rund 1.15 bis 1.28 * r), und eine Schuttlage mit
# voller Amplitude wuerde ihn dort lautlos aufloesen — genau die Falle, vor der schon der
# Schluessel "bloecke" warnt. An der Oberkante des Kragens steht die Lage noch auf gut einem
# Viertel, das sind unter 2 m je Zelle.
const VULKAN_APRON_BLOCK_AB := 0.72
const VULKAN_APRON_BLOCK_VOLL := 0.86
const VULKAN_APRON_BLOCK_AUS_AB := 1.06
const VULKAN_APRON_BLOCK_AUS_ZU := 1.18
# WO DIE ASCHE ANFAENGT AUSZUFRANSEN, als Anteil des Fussradius. Bis dahin ist die Schuerze
# geschlossen schwarz; das ist zugleich die Grenze, bis zu der _face_color die Vulkanhaut
# malt (siehe "haut_r" in _vulkane_bauen) — beide Zahlen MUESSEN dieselbe sein, sonst steht
# an der Nahtstelle ein Farbring.
const VULKAN_APRON_ASCHE_AB := 1.06
# WIE WEIT DIE ASCHE AUF DEM GRAT REICHT, gegen 1.0 in der Rinnensohle. Das ist der Kern der
# Sache: die Lava laeuft in den Rinnen, also greift die Asche dort weit ins Gruen hinaus und
# bleibt auf den Ruecken dazwischen zurueck. Der Waldrand bekommt damit von selbst seine
# Zacken — vorher war er ein Kreis, und ein Kreis ist die eine Form, die in einer Landschaft
# nicht vorkommt.
# 0.34 WAR ZU VIEL, und die Probe hat es gefunden, nicht das Bild: tools/_vulkan_form.gd
# meldete danach 10 echte Loecher im WALDKRAGEN und eine Deckung von 0.00 in fast allen
# Richtungen. Der Grund ist eine Ueberschneidung, die man der Zahl nicht ansieht — das
# Kragenband liegt zwischen 26 und 44 m Hoehe, mit der Schuerze also bei rund 2430 bis
# 2570 m, und die Asche reichte auf dem GRAT schon bis 2350 und im Mittel bis 2600. Sie hat
# den Kragen damit nicht aufgerissen, sondern abgeraeumt.
# Die Abnahme wollte das Gegenteil: "Ascheboden- und Lavazungen sollen die Baumgrenze
# unregelmaessig AUFREISSEN". Ein Riss braucht etwas, das er zerreisst.
# 0.10 WAR DANN ZU WENIG, und dieser Fehler stand im Bild statt in der Probe: die Asche war
# schon 150 m hinter der Nahtstelle weg, WAEHREND die Schuttlage darunter noch 200 m weiter
# lief. Im Vordergrund lag deshalb heller Fels mit Bloecken darin — Form ohne die Farbe, die
# zu ihr gehoert, also genau der Widerspruch, an dem hier schon die Almwiese und die
# Schutthalde haengengeblieben sind.
# DIE ZAHL IST JETZT GERECHNET UND NICHT GERATEN. Sie muss zusammen mit VULKAN_APRON_SAUM
# die Schuttlage ueberdecken, denn nur ueber der ist die Farbe zwingend Asche:
#     (GRAT - SAUM) * (apr - ab) + ab  >=  mr * VULKAN_APRON_BLOCK_AUS_ZU
# Mit ab = 1.06 * r, apr = 1.58 * r und AUS_ZU = 1.18 * r ergibt das GRAT - SAUM >= 0.23.
# 0.34 gegen 0.10 haelt das mit Rand ein: bis 1.18 * r deckt die Asche ueberall voll, und
# erst danach faengt sie an auszufransen.
const VULKAN_APRON_GRAT := 0.34
# ... UND DIE ZUNGEN MUESSEN ZUNGEN BLEIBEN. Der Anteil, mit dem eine Richtung als "Sohle"
# zaehlt, ist im Mittel gut die Haelfte — linear angesetzt lag die Asche damit ueberall auf
# halber Strecke, und aus den Zungen wurde wieder eine Scheibe mit welligem Rand.
# Der Exponent zieht die Verteilung auseinander: nur die tiefen Rinnensohlen tragen weit
# hinaus, alles dazwischen bleibt kurz. Bei 3.6 kommt die mittlere Richtung auf gut ein
# Zehntel der Strecke, die Sohle auf die ganze — das ist der Unterschied zwischen einem
# Saum und einem Geflecht. Bei 2.2 lag die mittlere Richtung auf einem Viertel, und
# zusammen mit dem Zackenwurf reichte die Asche im Mittel bis mitten in das Kragenband.
const VULKAN_APRON_ZUNGE := 3.6
# ... und darauf noch ein grober Wurf, damit die Zacken nicht alle gleich lang sind.
# 420 m Wellenlaenge auf _patch: das ist grob genug, dass eine Zunge mehrere Rinnen
# zusammenfasst, und fein genug, dass sie nicht die halbe Schuerze auf einmal verschiebt.
# ER SCHIEBT NUR NACH AUSSEN, NIE NACH INNEN (der Aufrufer rechnet mit 0.5 + 0.5 * Rauschen
# statt mit dem rohen Wert). Beidseitig angesetzt war er die zweite Haelfte des hellen
# Duenensands im Vordergrund: er konnte die Asche VOR VULKAN_APRON_GRAT zurueckziehen, und
# damit gab es keinen Radius mehr, bis zu dem die Schuerze garantiert geschlossen ist.
# Einseitig ist VULKAN_APRON_GRAT genau diese Garantie.
const VULKAN_APRON_ZACK := 0.24
const VULKAN_APRON_ZACK_M := 420.0
# Breite des Uebergangs von Asche zu Vorland, im selben Mass wie die Reichweite (0 am
# Kegelfuss, 1 am Saum). Schmaler waere eine gezeichnete Kante, breiter ein Schleier.
# 0.20 WAR SO BREIT WIE DIE REICHWEITE SELBST, und damit gab es gar keine Strecke mehr, auf
# der die Asche voll deckt: der Uebergang fing schon VOR der Nahtstelle an. 0.10 laesst der
# geschlossenen Schuerze ihren Ring und ist mit rund 100 m immer noch kein gezeichneter
# Strich. Die Rechnung dazu steht bei VULKAN_APRON_GRAT.
const VULKAN_APRON_SAUM := 0.10
# WIE STARK DIE ASCHE DAS VORLAND DECKT. Wie beim Lavastrom bleibt ein Rest der gewachsenen
# Farbe stehen (siehe dort): daran liest man, dass hier etwas UEBER dem Boden liegt, statt
# an seine Stelle getreten zu sein.
const VULKAN_APRON_DECK := 0.90
# Die Farbe der Schuerze. Sie ist absichtlich der Ton, den die Vulkanhaut am Kegelfuss
# ohnehin hat (dunkler Basalt mit Rostanteil, gemessen rund 0.20/0.14/0.12) — an der Naht
# bei VULKAN_APRON_ASCHE_AB stossen Haut und Schuerze zusammen, und zwei verschiedene
# Schwarztoene dort waeren genau der Ring, den die Naht vermeiden soll.
const VULKAN_APRON_ASCHE := Color(0.155, 0.122, 0.108)
# Auf den Ruecken zwischen den Rinnen und auf den Schuttnestern liegt Grus statt frischer
# Asche: heller, kaelter. Ohne diesen Unterschied ist der Faecher eine schwarze Flaeche, in
# der die Rinnen nur ueber die Schattierung sichtbar sind — und bei hochstehender Sonne ist
# das auf 5 Grad Grundneigung so gut wie nichts.
# DIE BEIDEN ANTEILE ADDIEREN SICH, WEIL SIE VERSCHIEDENE LAENGENSKALEN SIND: der Ruecken
# ist die 470-m-Welle (er gliedert), das Schuttnest die 46-m-Welle (sie koernt). Genau
# diese Trennung fehlte, als der Faecher mit 0.0039 Helligkeitssprung gemessen wurde.
# BEIDE SITZEN AUF FORM: der Ruecken auf dem Rinnenprofil, das height_at schneidet, das
# Nest auf der Blocklage, die height_at auftraegt. Eine Aufhellung, die neben der Form
# sitzt, ist an dieser Flanke schon einmal als "helle Striemen" gemeldet worden.
# SIE WAR ZUERST 0.315/0.278/0.248, ALSO ZU HELL UND ZU WARM. Im Bild lagen auf dem Faecher
# cremefarbene Facetten, und die liest das Auge als Sandstein — der Berg stand dann in einer
# Geroellwueste statt in seiner eigenen Asche. Ein Aschefaecher ist grau und kuehl; hell wird
# er nur dort, wo der Wind ihn abgerieben hat, und das ist ein Unterschied von wenigen
# Zehnteln, nicht der zwischen Schwarz und Sand.
const VULKAN_APRON_GRUS_C := Color(0.228, 0.208, 0.194)
const VULKAN_APRON_RUECKEN := 0.55
const VULKAN_APRON_BLOCK_HELL := 0.55
# Bis wohin die BAUMGRENZE DES KEGELS gilt, als Anteil des Fussradius. Ohne Schuerze waren
# das 1.06 (das Quadrat 1.1236 stand fest im Code) — mit ihr liegt das Band zwischen 44 und
# 68 m Hoehe nicht mehr am Kegelfuss, sondern draussen auf der Schuerze bei rund 1.15 bis
# 1.28 * mr. Bliebe die alte Schranke stehen, endete die Baumgrenze VOR ihrem eigenen Band,
# und auf der halben Schuerze stuende Wald auf 80 m Asche.
const VULKAN_APRON_BAUM := 1.36
# Wie weit die LAVAZUNGEN (_vulkan_strom) mit der Schuerze hinauslaufen, als Anteil ihres
# Aussenradius. Ohne Schuerze bleibt es bei VULKAN_HAUT_REICH, also exakt wie bisher.
const VULKAN_APRON_STROM := 0.95
# UM WIE VIEL DIE FELSSCHWELLE DER WELT AUF DER SCHUERZE NACH OBEN WANDERT, in Metern.
# DER BEFUND, GEGEN DEN DAS STEHT: zwischen dem schwarzen Faecher und dem gruenen Waldrand
# lag im Bild ein sandfarbener Ring. Er kam nicht aus dem Vulkan, sondern aus der Weltregel
# in _face_color — die faerbt ab 45 bis 59 m Hoehe Bergfels, und die Schuerze traegt das
# Vorland genau in diese Hoehenlage hinauf. Wo die Asche nicht deckte, stand deshalb heller
# Fels statt Wald.
# AUF DEM KEGEL GAB ES DAS PROBLEM NIE, und der Grund erklaert die Zeile: dort malt
# _vulkan_haut, und die Weltregel kommt gar nicht erst zum Zug. Mit der Schuerze liegt das
# Kragenband zum ersten Mal AUSSERHALB der Haut.
# 58 M SCHIEBT DIE SCHWELLE AUF 103 BIS 117 M und damit ueber die hoechste Stelle, an der
# die Baumgrenze des Kegels noch einen Baum zulaesst (VULKAN_BAUM_AUS 68 plus
# VULKAN_BAUM_ZACK 22 = 90 m). Darueber deckt ohnehin die Asche.
# DIE STEILHEIT BLEIBT UNBERUEHRT — dieselbe Trennung wie beim Wiesenhub im Hochtal (siehe
# TAL_WIESE_HUB): eine senkrechte Wand ist auch auf einer Ascheschuerze Fels.
const VULKAN_APRON_FELS_HUB := 58.0

var seed_value := 1337
var airfields: Array = []       # [{pos: Vector3, r_flat, r_blend, y?(Zielhöhe, default 0)}]
var lakes: Array = []           # [{pos: Vector3, r: float, surf: float}] Inland-Seen
var _flora_wasser_h := 34.0     # bis zu dieser Hoehe lohnt die Wasserpruefung der Flora
var rivers: Array = []          # kuratierte Fluss-Splines (siehe _prepare_rivers)
var massifs: Array = []         # [{pos: Vector3, r: float, peak: float}] erzwungene Berge
# TALKORRIDOR des Hochtals: {start, richtung, laenge, halbbreite: PackedFloat32Array}.
# Nur die ALMWIESE in _face_color liest ihn — das Hoehenfeld nicht. Warum es ihn gibt,
# steht bei TAL_WIESE_HUB.
var tal: Dictionary = {}
var _tal_boden := PackedFloat32Array()   # gemessene Talbodenhoehe je Stuetzstelle
# Breitenprofil AUSGEPACKT. Es steht als PackedFloat32Array in tal["halbbreite"], und ein
# `PackedFloat32Array(tal["halbbreite"])` je Abfrage waere eine Kopie JE DREIECK.
var _tal_hb := PackedFloat32Array()
var _tal_mitte := Vector2.ZERO           # Vorfilter: Mittelpunkt des Korridors ...
var _tal_reich2 := 0.0                   # ... und sein Umkreis, quadriert
# SCHUTTHALDEN der Wahrzeichen (heute nur die des Felsentors). Umrisse aus
# Landmarks.tor_halde_zone; MAIN SETZT SIE VOR setup(). Wo Blockschutt liegt, waechst
# nichts und es gibt auch keine Almwiese — vorher wusste die Bepflanzung nichts von der
# Halde und schickte ihren Wald mitten hindurch (63 Prozent Gruen im Fussbereich gegen
# 6 Prozent im Referenzbild).
var schutthalden: Array = []
var _halde_masken: Array = []            # daraus vorgerechnete Masken, siehe _halden_bauen
var _noise: FastNoiseLite
var _patch: FastNoiseLite       # Sekundär-Rauschen für Gras-Flecken
var _forest: FastNoiseLite      # grobes Rauschen: wo stehen WÄLDER (Cluster)
var _ridge: FastNoiseLite       # Ridged-Noise -> scharfe Bergketten
# Kreisradien, auf denen die Vulkanflanke ihr Rauschen abtastet (siehe VULKAN_RIPPEN_N),
# und der Streckfaktor der feinen Felslage.
var _vk_rippen_kreis := 0.0
var _vk_lippen_kreis := 0.0
var _vk_lippen_zack := 0.0
var _vk_zungen_kreis := 0.0
var _vk_fels_takt := 0.0
var _vk_block_takt := 0.0
var _vk_rost_takt := 0.0
var _vk_grus_takt := 0.0
var _vk_schutt_takt := 0.0
# Die GROBE Schwester des Schuttkorns: dieselbe Lage, nur auf Feldgroesse gestreckt. Sie
# treibt die Aschedecke (siehe VULKAN_FELD_M), das Korn franst nur noch ihren Rand aus.
var _vk_feld_takt := 0.0
var _vk_baum_takt := 0.0
# Barrancos: Zahl der Rinnen als GANZE Zahl (siehe VULKAN_BARR_N — daran haengt, dass die
# Winkelwelle bei +-pi keine Naht hat) sowie die Kreise fuer Maeander und Tiefenstreuung.
var _vk_barr_n := 0.0
var _vk_barr_wander := 0.0
var _vk_barr_tief := 0.0
# Zellbreite eines LAVASTAMMES in Rinnenbreiten (Rinnenzahl durch Stammzahl). Sie steht
# hier und nicht in _vulkan_ader, weil daran die Zusicherung haengt, dass sich die Zelle
# GABELN laesst: 32 / 4 = 8, danach 4, 2, 1 — lauter ganze Zahlen, und deshalb faellt die
# feinste Aderachse genau auf eine Rinnensohle.
var _vk_ader_stamm := 0.0
# Kreisfrequenzen des Astwurfs: ganzzahlige Perioden auf dem Umfang, sonst haette er an der
# atan2-Naht eine Kante (siehe _vulkan_ader_wurf).
var _vk_ader_wurf1 := 0.0
var _vk_ader_wurf2 := 0.0
var _vk_ader_kreis := 0.0
var _vk_glut_kreis := 0.0
var _vk_see_takt := 0.0
var _vk_apron_takt := 0.0
# VORGERECHNETE VULKANE fuer die Farbe und den Bewuchs: Mittelpunkt, Radien und der
# quadrierte Umkreis der Haut. _face_color und die Bepflanzung laufen ueber die GANZE Welt,
# und vorher stand dort eine Schleife ueber ALLE Massive mit je einem Stringvergleich und
# einer Wurzel — bei den rund dreissig Kegeln des Hochgebirges ist das je Dreieck spuerbar.
# Jetzt ist es je Vulkan ein Abstandsquadrat, und die Liste hat genau einen Eintrag.
var _vulkane: Array = []
var _relief: FastNoiseLite      # sehr grob: wie GEBIRGIG ist eine Region (Ebene<->Alpen)
var _biome: FastNoiseLite       # sehr grob: welches BIOM (Wald/Wüste/Hochland/Heide)
var _flora: Dictionary = {}     # Art -> Mesh (aus models/world_trees.glb, sieben Arten)
var _mesh_conifer: ArrayMesh    # Low-Poly-Tanne (Fallback, falls das glb fehlt)
var _mesh_leaf: ArrayMesh       # Low-Poly-Laubbaum
var _mesh_rock: ArrayMesh       # Low-Poly-Felsblock
var _grob_cache := {}           # Quellmesh -> vereinfachte Fassung
# Rundgang: Schluessel der laufenden Runde und wie weit sie gediehen ist (_chunks_pflegen).
var _pflege_keys: Array = []
var _pflege_i := 0
var _flora_warteschlange: Array = []   # Flora, die noch eingehaengt werden muss
# Laufende Werte der Baumweite — von Main.grafik_anwenden ueber setze_baumweite gesetzt.
var _flora_dist := FLORA_DIST
var _flora_grob_ab := FLORA_GROB_AB
var _mesh_palm: ArrayMesh       # Low-Poly-Palme (Wüste)
var _flora_mat: ShaderMaterial  # wie _mat, zusätzlich Entfernungs-Schrumpfen

const ARTEN := ["Fichte", "Kiefer", "Birke", "Eiche", "Palme", "Totholz", "Busch"]

# Biom-Konstanten (aus _biome-Rauschen, -1..1)
enum Biome { WALD, WUESTE, HOCHLAND, HEIDE }
var _chunks: Dictionary = {}    # Vector2i -> Node3D (eingehängt)
var _pending: Dictionary = {}   # Vector2i -> true (im Worker unterwegs)
var _mat: ShaderMaterial
var _water: MeshInstance3D
# Sonnenrichtung fuer den Glitzerpfad auf dem Wasser. Wird von Main ueber setze_sonne()
# gesetzt; der Vorgabewert hier ist nur eine Notbremse, falls das jemand vergisst.
var sonne_richtung := Vector3(0.55, 0.62, 0.55).normalized()
var _wasser_mats: Array[ShaderMaterial] = []
var _last_cc := Vector2i(2147483647, 0)   # zuletzt verarbeitete Spieler-Chunk-Zelle
var _last_pos := Vector3.ZERO

# --- Worker-Thread-Verkehr ---
var _thread: Thread
var _sem: Semaphore
var _mutex: Mutex
var _jobs: Array = []           # Keys für den Worker (nahe zuerst)
var _done: Array = []           # fertige {key, mesh, shape}
var _exit := false

# --- MESSHILFE -------------------------------------------------------------------------
## Ausgeschaltet kostet das je Abschnitt einen Bool-Test. Angeschaltet summiert `profil`
## die Mikrosekunden der einzelnen Streaming-Abschnitte im laufenden Frame; wer misst,
## leert es am Frameanfang selbst. Nur tools/_ruck_check.gd schaltet es an.
## WOFUER: der Ruck beim Nachladen ist nicht EIN Posten, sondern die Summe aus Einhaengen,
## Physik-Einfuegen, Abbauen ferner Chunks und Flora-Nachzug. Ohne Aufschluesselung
## optimiert man den falschen davon — genau das ist hier schon zweimal passiert.
var profil_an := false
var profil := {}


## Zeit seit t0 auf einen Abschnitt buchen. Kein Effekt, wenn nicht gemessen wird.
func _pz(abschnitt: String, t0: int) -> void:
	if profil_an:
		profil[abschnitt] = float(profil.get(abschnitt, 0.0)) + float(Time.get_ticks_usec() - t0)


func setup(seedv: int, afs: Array, lks: Array = [], rvs: Array = [], mss: Array = [],
		tlk: Dictionary = {}) -> void:
	seed_value = seedv
	airfields = afs
	tal = tlk
	# Rechteck-Zonen einmal vorbereiten: Drehung des Platzes und ein Umkreis fuer den
	# Vorfilter. _open_ground laeuft je DREIECK (4608 pro Chunk) ueber alle zwoelf Zonen —
	# dort darf kein cos/sin und keine Wurzel mehr stehen, die sich hier sparen laesst.
	for af in airfields:
		# "quer_faktor" braucht dieselbe Drehung wie die Rechtecke — deshalb hier mit
		# durchgereicht, auch wenn eine Zone gar keine Rechtecke hat.
		if not af.has("rects") and not af.has("quer_faktor"):
			continue
		var hd := float(af.get("heading", 0.0))
		af["_cos"] = cos(hd)
		af["_sin"] = sin(hd)
		if not af.has("rects"):
			continue
		var rmax := 0.0
		for r in af["rects"]:
			rmax = maxf(rmax, Vector2(absf(r[0]) + r[2], absf(r[1]) + r[3]).length())
		af["_rmax"] = rmax + FREI_AUSSEN
	lakes = lks
	# Seen mit "form_achse" bekommen den gelappten Umriss (siehe _see_umriss_bauen). Die
	# Tabelle entsteht EINMAL hier — height_at und _build_lake_water lesen danach beide
	# nur noch daraus ab, koennen sich also nicht mehr auseinanderentwickeln.
	for lk in lakes:
		if lk.has("form_achse"):
			_see_umriss_bauen(lk)
		_flora_wasser_h = maxf(_flora_wasser_h, float(lk["surf"]) + 1.0)
	massifs = mss
	_prepare_rivers(rvs)
	_noise = FastNoiseLite.new()
	_noise.seed = seedv
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 5
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5
	_noise.frequency = 1.0 / 1500.0
	_patch = FastNoiseLite.new()
	_patch.seed = seedv * 7 + 3
	_patch.frequency = 1.0 / 60.0
	_forest = FastNoiseLite.new()
	_forest.seed = seedv * 13 + 5
	_forest.frequency = 1.0 / 260.0
	# Ridged-Noise: scharfe Bergrücken (kein Domain-Warp -> günstig, height_at läuft
	# pro Vertex; Warp war zu teuer für den synchronen Spawn-Build).
	_ridge = FastNoiseLite.new()
	_ridge.seed = seedv * 17 + 11
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 4
	_ridge.fractal_gain = 0.55
	_ridge.frequency = 1.0 / 1700.0
	# Ein Kreis mit diesem Radius im Rauschraum ist genau VULKAN_RIPPEN_N Wellenlaengen lang.
	# Die Umrechnung steht hier und nicht in height_at: sie ist je Bild konstant, in der
	# Hoehenschleife waere sie eine Division je Probe.
	_vk_rippen_kreis = VULKAN_RIPPEN_N / (TAU * _ridge.frequency)
	_vk_lippen_kreis = VULKAN_LIPPEN_N / (TAU * _noise.frequency)
	_vk_lippen_zack = _vk_lippen_kreis * VULKAN_LIPPEN_ZACK_N
	_vk_zungen_kreis = VULKAN_ZUNGEN_N / (TAU * _noise.frequency)
	# DIE RUNDUNG IST KEINE KOSMETIK: nur bei einer GANZEN Rinnenzahl springt die Phase ueber
	# die atan2-Naht um einen ganzen Umlauf, und nur dann merkt der Nachkommateil nichts
	# davon. Steht in VULKAN_BARR_N eine gebrochene Zahl, laeuft der Kegel mit einer geraden
	# Kante vom Gipfel bis zum Fuss herum — deshalb wird sie hier gerundet und nicht in der
	# Hoehenschleife geprueft.
	_vk_barr_n = maxf(round(VULKAN_BARR_N), 1.0)
	_vk_barr_wander = VULKAN_BARR_WANDER_N / (TAU * _noise.frequency)
	_vk_barr_tief = VULKAN_BARR_TIEF_N / (TAU * _noise.frequency)
	_vk_ader_stamm = _vk_barr_n / maxf(VULKAN_ADER_STAEMME, 1.0)
	_vk_ader_wurf1 = TAU * 13.0 / _vk_barr_n
	_vk_ader_wurf2 = TAU * 5.0 / _vk_barr_n
	_vk_ader_kreis = VULKAN_ADER_TAKT / (TAU * _ridge.frequency)
	# FESTER Kreis fuer die Sektorwahl der Glut — er waechst mit Absicht NICHT mit dem
	# Abstand (Begruendung bei VULKAN_GLUT_SEKTOR_N).
	_vk_glut_kreis = VULKAN_GLUT_SEKTOR_N / (TAU * _ridge.frequency)
	# Die Felslage nimmt dieselbe Rauschquelle, nur weit hineingezoomt: aus 1700 m Grundwelle
	# werden VULKAN_FELS_M. Eine eigene FastNoiseLite dafuer waere ein weiterer Zustand, den
	# der naechste Umbau uebersehen kann.
	_vk_fels_takt = 1.0 / (VULKAN_FELS_M * _ridge.frequency)
	# Dieselbe Quelle noch einmal, noch weiter hineingezoomt: die BLOCKLAGE. Sie muss auf
	# _ridge liegen und nicht auf _patch — ihre scharfen Kaemme sind der halbe Zweck der
	# Sache (Begruendung bei VULKAN_BLOCK_AB), ein einoktaviges Fleckenrauschen gaebe runde
	# Beulen statt Aufschluesse.
	_vk_block_takt = 1.0 / (VULKAN_BLOCK_M * _ridge.frequency)
	# Dieselbe Umrechnung fuer die Rostflecken, nur auf _patch (einoktavig): aus 60 m
	# Grundwelle werden VULKAN_ROST_M. Eine dritte Rauschquelle waere hier reine Verschwendung
	# — ein Fleckenwurf braucht keine Oktaven, er braucht nur eine Laengenskala.
	_vk_rost_takt = 1.0 / (VULKAN_ROST_M * _patch.frequency)
	_vk_grus_takt = 1.0 / (VULKAN_GRUS_M * _patch.frequency)
	_vk_schutt_takt = 1.0 / (VULKAN_SCHUTT_M * _patch.frequency)
	# Vierte Stelle auf derselben Lage. Sie liegt bewusst NICHT auf einer eigenen
	# Rauschquelle: gebraucht wird eine zweite LAENGENSKALA, kein zweites Muster, und ein
	# Faktor sieben zwischen den beiden Takten reicht, damit sie sich nicht decken.
	_vk_feld_takt = 1.0 / (VULKAN_FELD_M * _patch.frequency)
	# Die FUGEN DER LAVASEE-KRUSTE liegen auf _ridge, weil dessen scharfe Kaemme duenne
	# Linien geben — ein einoktaviges Fleckenrauschen wuerde runde Inseln zeichnen, und eine
	# Kruste zerreisst in Schollen mit Naehten dazwischen (Begruendung bei VULKAN_SEE_M).
	_vk_see_takt = 1.0 / (VULKAN_SEE_M * _ridge.frequency)
	# Der grobe Wurf auf dem Saum der Ascheschuerze. Er liegt auf _patch und NICHT auf
	# _forest: _forest setzt zugleich die Walddichte, und eine Zunge, die genau dort weit
	# hinausgreift, wo ohnehin kein Wald steht, verschiebt keinen Waldrand — sie faerbt nur
	# eine Lichtung um. Derselbe Fehler steckte schon einmal in VULKAN_BAUM_ZACK.
	_vk_apron_takt = 1.0 / (VULKAN_APRON_ZACK_M * _patch.frequency)
	# Dritte Stelle auf derselben Lage, fuer die ZACKEN der Baumgrenze (Begruendung dort).
	# Sie darf NICHT auf _forest liegen — das ist die Lage, die zugleich die Dichte macht.
	_vk_baum_takt = 1.0 / (VULKAN_BAUM_M * _patch.frequency)
	# Relief: sehr grob — wie gebirgig eine Region ist (Ebene 0 .. Alpen 1)
	_relief = FastNoiseLite.new()
	_relief.seed = seedv * 23 + 7
	_relief.frequency = 1.0 / 3600.0
	# Biom: sehr grob — Regionen-Einteilung
	_biome = FastNoiseLite.new()
	_biome.seed = seedv * 31 + 13
	_biome.frequency = 1.0 / 3200.0
	_vulkane_bauen()
	# ERST HIER, nicht weiter oben: _talboden_bauen ruft height_at, und das braucht
	# saemtliche Rauschquellen. Ein Aufruf vor _biome lieferte lauter Nullen.
	_talboden_bauen()
	_halden_bauen()
	_mesh_conifer = _build_conifer_mesh()
	_mesh_leaf = _build_leaf_mesh()
	_mesh_rock = _build_rock_mesh()
	_mesh_palm = _build_palm_mesh()
	_flora = _load_flora()
	# Vertex-Farbe DIREKT als Albedo (StandardMaterial ignorierte die Farben trotz
	# vertex_color_use_as_albedo bei material_override + SurfaceTool-Mesh).
	# WICHTIG (war DIE Ursache der faden Map): die set_color-Werte sind sRGB, ALBEDO
	# erwartet LINEAR. Rohes COLOR.rgb wurde als linear gelesen -> systematisch
	# aufgehellt/entsaettigt (Mint statt Wiese, Geister-Berge). -> sRGB->linear wandeln.
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
// GLUT AUS DEM ALPHAKANAL. a = 1 ist kaltes Gestein — und das ist der Wert, den JEDE
// bisherige Farbe dieser Welt schon hat, denn Color(r, g, b) legt a auf eins. Je kleiner
// a, desto staerker leuchtet die Flaeche aus sich selbst, und zwar in IHRER EIGENEN
// Farbe: _face_color mischt die Gesteinsfarbe zur Lava hin, damit haben die schwach
// geoeffneten Rinnen unten von selbst ein dunkleres Rot als die heissen am Kraterrand.
// WARUM UEBER DEN ALPHAKANAL UND NICHT UEBER EIN ZWEITES MATERIAL: die Glutrinnen sind
// einzelne Dreiecke MITTEN in der Gelaendeflaeche. Ein zweites Material waere ein zweiter
// Zeichenaufruf je Chunk und eine zweite Netzhaelfte, die an jeder Kante mit der ersten
// verzahnt — fuer eine Eigenschaft, die eine einzige Zahl je Dreieck ist.
// DER FAKTOR STEHT DEUTLICH UEBER EINS, weil das Environment KEIN Glow hat (Main:
// glow_enabled = false, und das umzustellen wuerde die ganze Welt betreffen). Die Rinne
// muss also aus sich heraus lesbar sein: bei 4 kommt eine volle Lavaflaeche linear auf
// rund 3,6 und liegt damit sicher in der Schulter des ACES-Tonemappers, waehrend eine
// halb geoeffnete Rinne noch dunkelrot bleibt.
const float GLUT = 2.2;
void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	EMISSION = ALBEDO * (1.0 - COLOR.a) * GLUT;
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	# FLORA-MATERIAL: gleiche Farbbehandlung, aber jede Instanz faehrt zur Sichtgrenze
	# hin ihre GROESSE gegen null. Godots VISIBILITY_RANGE_FADE_SELF verlangt ein
	# transparentes Material und tat an diesem Opaque-Shader nichts — die Baeume waeren
	# an der Grenze hart erschienen. Alpha waere teuer und sortierpflichtig; Schrumpfen
	# ist geometrisch und kostet nichts: bei 2.9 km ist ein 10-m-Baum bei 64 Grad
	# vertikalem Sichtfeld auf 720 Zeilen noch rund zwei Pixel hoch.
	var fsh := Shader.new()
	fsh.code = """
shader_type spatial;
uniform float fade_start;
uniform float fade_end;
void vertex() {
	vec3 wo = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX *= 1.0 - smoothstep(fade_start, fade_end, distance(wo, CAMERA_POSITION_WORLD));
}
void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
"""
	_flora_mat = ShaderMaterial.new()
	_flora_mat.shader = fsh
	_flora_mat.set_shader_parameter("fade_start", FLORA_FADE_END - FLORA_FADE)
	_flora_mat.set_shader_parameter("fade_end", FLORA_FADE_END)
	# Wasserfläche (rein optisch; Kollision = WorldBoundary bei SEA_Y in Main)
	_water = MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(VIEW_DIST * 2.4, VIEW_DIST * 2.4)
	_water.mesh = wm
	_water.position = Vector3(0, SEA_Y + 0.15, 0)
	# Tropisches Tiefen-Wasser (Shader): tuerkise Untiefen -> Lagune -> tiefes Blau
	# ueber den Tiefenpuffer, Schaumkante am Ufer, Fresnel-Himmelsspiegelung.
	_water.material_override = _water_mat(MEER)
	add_child(_water)
	# Inland-Seen: DERSELBE Shader wie das Meer, nur ruhiger parametriert. Frueher hing
	# hier ein StandardMaterial3D mit roughness 0.08 — zusammen mit den Fluessen waren
	# das DREI verschiedene Wasser-Looks in einer Welt.
	for lk in lakes:
		_build_lake_water(lk)
	# ERST DIE SEEBAECHE EINPASSEN, DANN IHR WASSERBAND BAUEN. Andersherum lag das Band auf
	# der Hoehe, die in der Liste stand — bei den beiden Seebaechen ist das eine Null, also
	# tief unter dem Gelaende. Im Bild fehlten sie damit vollstaendig.
	_seebaeche_einpassen()
	# Fluss-Wasserflächen (Ribbons entlang der Splines)
	for rv in rivers:
		_build_river_water(rv)
	# Worker starten
	_sem = Semaphore.new()
	_mutex = Mutex.new()
	_thread = Thread.new()
	_thread.start(_worker_loop)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_exit = true
		_sem.post()
		_thread.wait_to_finish()


# Geländehöhe an Weltposition (deterministisch aus dem Seed).
## Wie gebirgig die Region ist (0 = Ebene, 1 = Alpen). Sehr grob.
func relief_at(x: float, z: float) -> float:
	return smoothstep(-0.12, 0.42, _relief.get_noise_2d(x, z))

## Biom an einer Welt-Position (Tiefland-Charakter; Fels/Schnee kommt aus Höhe/Hang).
func biome_at(x: float, z: float) -> int:
	var b := _biome.get_noise_2d(x, z)
	if b < -0.32:
		return Biome.WUESTE
	if b > 0.40:
		return Biome.HEIDE
	return Biome.WALD

func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	# Distanz-Ramp: Spawn-Umfeld ruhig, Gebirge baut sich erst weiter draußen auf
	var dist_k := smoothstep(700.0, 3000.0, d)
	var relief := relief_at(x, z) * dist_k
	# 1) sanfte Grundwelligkeit überall
	var rolling := _noise.get_noise_2d(x, z) * lerpf(6.0, 24.0, relief)
	# 2) scharfe Bergketten NUR wo Relief hoch (ridged + domain-warp)
	var rdg := clampf(_ridge.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var peaks := pow(rdg, 1.6) * lerpf(0.0, 175.0, relief) * relief
	var h := rolling + peaks
	# RIESIGE INSEL: die Welt ist EINE grosse Insel. Das Basis-Terrain fällt jenseits eines
	# winkelabhängig verrauschten Küstenradius (~5.3–7.6 km) unter den Meeresspiegel.
	# Vor den Massiven angewandt -> erzwungene Inseln/Vulkan draußen bleiben bestehen (max).
	var ang := atan2(z, x)
	var rvar := _biome.get_noise_2d(cos(ang) * 900.0, sin(ang) * 900.0)
	# INSELGROESSE. War 12800 +- 2400 (Kueste bei 10.4 bis 15.2 km). Fuer das Hochtal im
	# Nordwesten reicht das nicht: dessen suedwestliche Kette laege bei 14.5 km und damit
	# im Meer. 18000 gibt eine Kueste bei 15.6 bis 20.4 km, also knapp die doppelte
	# Landflaeche.
	# MITZIEHEN MUSS MAN ZWEI DINGE, sonst hoert die Welt vor ihrer eigenen Kueste auf:
	# Main.FERN_WELT (Reichweite der Fernschuerze) und WorldMap.WORLD_R (Kartenausschnitt).
	var r_coast := 18000.0 + rvar * 2400.0
	var fall := smoothstep(r_coast - 1400.0, r_coast + 800.0, d)
	if fall > 0.0:
		h = lerpf(h, SEA_Y - 18.0, fall)
	# MESA-TERRASSEN in der Wüste: gestufte Tafelberge/Canyon-Kanten (Low-Poly-Ikone).
	# Weiche Quantisierung: flache Tops, steile Flanken; nur im Wüsten-Biom & ab 8 m.
	if h > 8.0 and dist_k > 0.25 and _biome.get_noise_2d(x, z) < -0.32:
		var step_h := 16.0
		var q := floorf(h / step_h) * step_h
		var f := (h - q) / step_h
		h = lerpf(h, q + smoothstep(0.55, 1.0, f) * step_h, 0.75)
	# ERZWUNGENE FORMEN (Massive): garantieren Berg/Insel/Vulkan an gewünschter Stelle,
	# seed-unabhängig. Nur anheben (max) -> stören das übrige Gelände nie.
	for ms in massifs:
		var mp: Vector3 = ms["pos"]
		var mr := float(ms["r"])
		# FRUEH RAUS, BEVOR IRGENDETWAS GERECHNET WIRD. Diese Schleife laeuft fuer JEDE
		# Hoehenprobe ueber ALLE Massive — bei 2401 Proben je Chunk und inzwischen ueber
		# vierzig Massiven sind das 100 000 Durchlaeufe pro Chunk. Die allermeisten Proben
		# liegen ausserhalb jedes einzelnen Massivs.
		# Der Schelf von Inseln und Vulkanen reicht bis 1.9 * r, ein Berg nur bis r.
		var dx := x - mp.x
		var dz := z - mp.z
		var typ := String(ms.get("type", "berg"))
		var dehn := float(ms.get("dehnung", 1.0))
		# REICHWEITE MUSS BEIDE RICHTUNGEN DER ELLIPSE ABDECKEN. Hier stand
		# maxf(dehn, 1.0), und das war falsch: bei einer Dehnung UNTER 1 streckt sich das
		# Massiv quer zur Drallachse und reicht bis mr/dehn. Der Vorfilter schnitt es dann
		# bei mr kreisrund ab — im Bild eine senkrechte, 8 m gerasterte Wand mitten im
		# Hang, die aussah wie eine eingestuerzte Schlucht.
		var reichweite := mr * (1.0 if typ == "berg" else 1.9) * maxf(dehn, 1.0 / dehn)
		if dx * dx + dz * dz > reichweite * reichweite:
			continue
		var md := sqrt(dx * dx + dz * dz)
		# GEDREHTE ELLIPSE STATT KREIS. Der Fussabdruck war bei jedem Massiv rund, und
		# damit sah jeder Berg von oben gleich aus — der wirksamste Hebel gegen
		# "die schauen alle gleich aus" ist die Grundrissform, nicht die Hoehe.
		# dehnung 1.0 laesst alles wie vorher; alle vorhandenen Massive haben keinen Wert
		# und bleiben unveraendert.
		if dehn != 1.0:
			var dr := float(ms.get("drall", 0.0))
			var cc := cos(dr)
			var ss := sin(dr)
			var rx := dx * cc + dz * ss
			var rz := -dx * ss + dz * cc
			md = sqrt((rx / dehn) * (rx / dehn) + (rz * dehn) * (rz * dehn))
			if md > mr:
				continue
		# UNTERWASSER-SCHELF fuer Inseln und Vulkane (tuerkiser Ring). Er reicht bewusst
		# UEBER den Kegelradius hinaus und laeuft dort aus.
		# WARUM AUSSERHALB: frueher endete der Kegel am Rand bei der Konstanten SEA_Y - 9,
		# waehrend das Basisgelaende ringsum schon bei SEA_Y - 18 lag. Das ist eine
		# 9-m-Stufe im Meeresgrund, gemessen 9,24 m, und weil sie exakt dem Kegelradius
		# folgt, stand im Bild ein rasiermesserscharfer, perfekt kreisrunder Farbsprung
		# Tuerkis gegen Tiefblau ueber zwei Pixel — ein aufgemalter Planschbeckenrand.
		# Jetzt steigt der Grund von aussen her an und der Kegel setzt stufenlos darauf auf.
		if typ != "berg":
			var schelf := 1.0 - smoothstep(mr * 0.95, mr * 1.9, md)
			if schelf > 0.0:
				h = maxf(h, lerpf(h, SEA_Y - 9.0, schelf))
		# --- DIE SCHUERZE AM FUSS -------------------------------------------------------
		# "apron" ist ihre Hoehe unter dem Mittelpunkt in Metern und schaltet sie ein; ohne
		# den Schluessel ist sie eine Null, und jedes Massiv der Welt bleibt bitgenau, wie
		# es war. Wofuer es sie gibt und warum sie kein groesseres "r" ist, steht bei
		# VULKAN_APRON_WEIT.
		# SIE WIRD VOR DEM cone-TOR GERECHNET UND NICHT DARIN, und das ist ihr ganzer Sinn:
		# cone ist jenseits von mr exakt null, der Zweig darunter laeuft dort also gar nicht
		# mehr — genau dort aber liegt die Schuerze.
		var aph := float(ms.get("apron", 0.0))
		var apron := 0.0
		if aph > 0.0:
			var apr := mr * VULKAN_APRON_WEIT
			if md < apr:
				apron = aph * pow(1.0 - smoothstep(0.0, apr, md), VULKAN_APRON_K)
				# DIE RINNEN DES FAECHERS, in derselben Phase wie die Barrancos darueber
				# (Begruendung bei VULKAN_APRON_RIP_AB). Sie kosten zwei Rauschabfragen und
				# laufen deshalb nur, wo es sie ueberhaupt gibt: ab 0.78 * mr.
				var arp := float(ms.get("apron_rippen", 0.0))
				if arp > 0.0 and md > mr * VULKAN_APRON_RIP_AB:
					# EIGENE EINHEITSRICHTUNG statt der weiter unten gerechneten: die steht
					# im Insel-Zweig, und der laeuft hier draussen nicht. Zwei Divisionen,
					# und zwar nur fuer Massive mit Schuerze — also fuer genau eines.
					var aux := dx / md
					var auz := dz / md
					var arn := _vulkan_rinne(aux, auz, md)
					apron += arp * arn.y \
						* smoothstep(mr * VULKAN_APRON_RIP_AB, mr * VULKAN_APRON_RIP_VOLL, md) \
						* (1.0 - smoothstep(apr * VULKAN_APRON_RIP_AUS, apr, md)) \
						* _vulkan_rinne_profil(arn.x, arn.z, md,
							mr * VULKAN_APRON_RIP_AB, apr)
				# DER SCHUTT AUF DEM FAECHER. "apron_bloecke" ist seine Auswurfhoehe in
				# Metern und schaltet ihn ein; warum es ihn NEBEN den Rinnen braucht und wo
				# er aufhoeren muss, steht bei VULKAN_APRON_BLOCK_AB. Der Ausdruck ist
				# Zeichen fuer Zeichen der der Flanke (siehe DIE BLOCKLAGE), nur mit den
				# Huellen des Faechers — sonst laege die helle Koernung neben dem Schutt.
				var abl := float(ms.get("apron_bloecke", 0.0))
				if abl > 0.0 and md > mr * VULKAN_APRON_BLOCK_AB:
					apron += abl * _vulkan_apron_schutt(x, z, md, mr)
				# DIE SCHUERZE DARF NUR ANHEBEN. Das ist die Zusicherung der ganzen
				# Massivschleife ("nur anheben (max) -> stoeren das uebrige Gelaende nie"),
				# und ohne dieses maxf bricht sie: das Rinnenprofil ist um seinen Mittelwert
				# zentriert, die Sohle liegt also ein Drittel der Rinnentiefe UNTER null.
				# Am aeusseren Saum, wo von der Schuerze nur noch ein paar Meter uebrig
				# sind, schnitte das ins Vorland — und weil das Vorland rings um diesen
				# Vulkan auf Meereshoehe liegt, staende danach in jeder Rinne eine Pfuetze.
				apron = maxf(apron, 0.0)
		var cone := 1.0 - smoothstep(0.0, mr, md)
		if cone <= 0.0:
			# JENSEITS DES FUSSRADIUS GIBT ES NUR NOCH DIE SCHUERZE. Ohne sie ist die Zeile
			# ein "+= 0.0" und damit das alte Verhalten, Bit fuer Bit.
			h += apron
		if cone > 0.0:
			# craggy: breite Ridge-Form + hochfrequente Grat-Details -> Bergform statt Kuppel
			# GRATRAUSCHEN JE MASSIV EIGEN. Hier stand fuer JEDEN Berg dieselbe Frequenz
			# 2.4 und derselbe Ursprung — alle Berge trugen damit dasselbe Rippenmuster,
			# nur an anderer Stelle abgetastet. "nz_frq" aendert die Feinheit der Rippen
			# (kleiner = grobe breite Grate, groesser = zerklueftet), "nz_off" verschiebt
			# das Muster, sodass zwei Berge mit gleicher Frequenz trotzdem verschieden
			# aussehen. Ohne beide Werte bleibt es exakt wie vorher.
			var frq := float(ms.get("nz_frq", 2.4))
			var off := float(ms.get("nz_off", 0.0))
			var crag := clampf(_ridge.get_noise_2d((x + off) * frq, (z + off) * frq)
				* 0.5 + 0.5, 0.0, 1.0)
			# SPITZE STATT KUPPE. cone = 1 - smoothstep(0, r, d) hat am Mittelpunkt die
			# Steigung NULL — deshalb endet jedes Massiv oben in einer runden Kuppe, egal
			# wie hoch es ist. Fuer einen spitzen Gipfel braucht es ein Profil, das im
			# Zentrum eine echte Steigung hat.
			# Der GERADE Kegel 1 - d/r leistet genau das: im Zentrum hat er eine echte
			# Steigung (spitzer Gipfel), und auf halbem Radius liefert er 0.5 — denselben
			# Wert wie smoothstep. Der Berg wird also oben spitzer, ohne unten breiter zu
			# werden.
			# ERST PROBIERT UND VERWORFEN: pow(1 - d/r, 0.75). Der Exponent unter 1 macht
			# die Flanke VOLLER (0.595 statt 0.5 auf halbem Radius). Im Bild hob das den
			# ganzen Bergfuss an, das Vorland rutschte ueber die Felsschwelle und die
			# gruene Wiese vor dem Gebirge wurde braun.
			# "schaerfe" 0 = wie bisher, 1 = ganz spitz. Ohne den Wert aendert sich an
			# allen vorhandenen Massiven (Vulkan, Inseln, Canyonflanken) nichts.
			var s := smoothstep(0.0, 1.0, cone)
			var sch := float(ms.get("schaerfe", 0.0))
			if sch > 0.0:
				s = lerpf(s, clampf(1.0 - md / mr, 0.0, 1.0), sch)
			if typ == "berg":
				var top := float(ms["peak"]) * s * (0.68 + 0.32 * rdg)
				top += s * crag * 30.0
				# GRAT-AMPLITUDE, BEIDSEITIG. Der Vorgabewert 30 m gibt einer 200-m-Kuppe
				# eine feine Struktur, auf einem 660-m-Berg verschwindet er. "grat" legt
				# fuer das Hochgebirge kraeftige Rippen und Rinnen darueber.
				# WICHTIG IST DAS VORZEICHEN: crag liegt zwischen 0 und 1, addiert also
				# IMMER. Einfach hochzuskalieren hob deshalb die ganze Mittelflanke an —
				# bei Faktor 3.2 um bis zu 48 m — und schob das Vorland ueber die
				# Felsschwelle, sodass die gruene Wiese vor dem Gebirge braun wurde.
				# (crag - 0.5) ist um null zentriert: es schneidet ebenso viel Material
				# weg, wie es auftraegt. Die Silhouette wird zackig, die mittlere Hoehe
				# bleibt. Der Zusatz greift nur ueber dem Vorgabewert 1.0, alle
				# vorhandenen Massive bleiben damit unveraendert.
				var grat := float(ms.get("grat", 1.0))
				if grat > 1.0:
					top += s * (crag - 0.5) * 30.0 * (grat - 1.0)
				h = maxf(h, top)
			else:
				# INSEL/VULKAN: Rand fällt UNTER den Meeresspiegel -> echte Küste rundum.
				# Der Kegel setzt auf dem SCHELF auf (h), nicht auf einer Konstanten —
				# sonst entsteht am Kegelrand wieder die Stufe.
				var cr := float(ms.get("crater_r", mr * 0.16))
				# EINHEITSRICHTUNG vom Massivmittelpunkt nach aussen. Sie ersetzt jedes atan2
				# in diesem Block: cos(Winkel) und sin(Winkel) SIND dx/md und dz/md — ohne
				# Winkelfunktion und ohne Naht bei +-pi. Eine Naht waere hier nicht theoretisch:
				# jedes Muster, das ueber den Winkel laeuft, springt dort, und der Sprung
				# staende als kerzengerade Kante vom Gipfel bis zum Fuss im Hang.
				var ux := 0.0
				var uz := 0.0
				if md > 1.0:
					ux = dx / md
					uz = dz / md
				# --- ABGESTUMPFTER SCHICHTVULKAN ------------------------------------------
				# "flanke" ist der Exponent des Kegelprofils und schaltet diesen Abschnitt
				# ein. Ohne den Wert bleibt es beim doppelten smoothstep, also genau bei der
				# Form, die alle Inseln haben.
				# WAS DARAN FALSCH WAR: s = smoothstep(0, 1, cone) hat am Mittelpunkt UND am
				# Rand die Steigung null. Bei 230 m auf 1250 m Radius ergab das im Mittel
				# 10 Grad Boeschung, an beiden Enden flach — ein Fladen mit einer Delle.
				# Der Radius laeuft jetzt erst am KRATERRAND los (krx) statt im Mittelpunkt:
				# ein Schichtvulkan endet oben nicht in einer Spitze, sondern in der Lippe.
				# Die Gipfelflaeche ist damit von Haus aus eben und der Krater muss sie nicht
				# erst wieder abtragen — daran krankte die alte Fassung, die eine Kuppe
				# aufbaute und danach eine Delle hineinzog.
				# Der Exponent macht die Flanke KONKAV: knapp unter der Lippe rund 43 Grad,
				# auf halber Flanke 40, am Fuss unter 25. Ein Exponent UNTER 1 macht es
				# umgekehrt (steiler Fuss, flacher Gipfel) und liest sich als Tafelberg.
				var flanke := float(ms.get("flanke", 0.0))
				var sv := s
				var krx := cr
				if flanke > 0.0:
					# UNREGELMAESSIGE LIPPE: der Kraterrand wandert winkelabhaengig aus dem
					# Kreis heraus. Weil er zugleich die Kante der Gipfelflaeche ist, bekommt
					# die oberste Flanke dieselbe Unruhe mit und der Rand liest sich nicht mehr
					# als gedrechselt.
					# ZWEI LAGEN AUF DEMSELBEN KREIS (Begruendung bei VULKAN_LIPPEN_ZACK_N):
					# die grobe gibt dem Krater seinen unrunden Grundriss, die feine erst die
					# Kante. Beide aus DEMSELBEN Rauschen, nur weiter draussen abgetastet — eine
					# zweite FastNoiseLite waere Zustand, den der naechste Umbau uebersieht.
					krx = cr * (1.0 + float(ms.get("lippe", 0.0))
						* (_noise.get_noise_2d(ux * _vk_lippen_kreis, uz * _vk_lippen_kreis)
						+ VULKAN_LIPPEN_ZACK * _noise.get_noise_2d(
							ux * _vk_lippen_zack, uz * _vk_lippen_zack)))
					# GEBROCHENER FUSS. Der Kegel endete auf den Meter genau bei mr, und ein
					# Kreis dieser Groesse liest sich im Bild als gedrechselt — dieselbe
					# Erfahrung wie beim Grundriss der Berge (siehe "dehnung").
					# "fuss" zieht den Fussradius winkelabhaengig nach INNEN, nie nach aussen:
					# der Fussabdruck bleibt damit garantiert innerhalb der 1250 m, mit denen
					# das Massiv in der Tabelle steht, und kein Nachbargelaende wird beruehrt.
					# Abgetastet wird dasselbe Rauschen wie fuer die Lippe, nur an anderer
					# Stelle — sonst atmeten Lippe und Fuss im Gleichtakt.
					var mrx := mr
					var fuss := float(ms.get("fuss", 0.0))
					if fuss > 0.0:
						mrx = mr * (1.0 - fuss * (0.5 + 0.5 * _noise.get_noise_2d(
							ux * _vk_lippen_kreis + 4100.0, uz * _vk_lippen_kreis - 2700.0)))
					sv = pow(1.0 - clampf((md - krx) / maxf(mrx - krx, 1.0), 0.0, 1.0), flanke)
				# DIE BEIDEN RAUSCHLAGEN STEHEN IN EIGENEN VERAENDERLICHEN und werden nicht
				# mehr direkt aufaddiert. Der Grund steht ganz unten beim LAVASEE: der zieht
				# sie in seiner Flaeche wieder ab, und dafuer muss er wissen, wie viel an
				# dieser Stelle ueberhaupt aufgetragen wurde. Gerechnet wird nichts anderes.
				var kraut := sv * crag * 22.0
				var top := lerpf(h, float(ms["peak"]), sv) + kraut + apron
				# --- RADIALE GRATE UND RINNEN ---------------------------------------------
				# Das vorhandene Gratrauschen (crag) tastet in x/z ab. Auf einem Kegel ist das
				# richtungslos: es macht Flecken, die quer ueber die Flanke laufen, und genau
				# deshalb wirkte der Hang glatt und tot, obwohl Rauschen darauf lag.
				# Hier laeuft die eine Rauschachse UM den Berg und die andere den Hang
				# HINUNTER. Was quer schmal ist und laengs lang, sind Rippen — und _ridge ist
				# ridged, hat also scharfe Kaemme mit breiten Rinnen dazwischen, die
				# Aufteilung einer echten Vulkanflanke.
				var rip := float(ms.get("rippen", 0.0))
				if rip > 0.0 and md > krx * VULKAN_RIPPEN_INNEN:
					# HUELLKURVE IN DREI ABSCHNITTEN, und der erste ist neu: die Rippen fangen
					# jetzt INNEN in der Kraterwand an, stehen an der Lippe auf dem Anteil
					# VULKAN_RIPPEN_LIPPE (dort steht, warum) und erreichen erst ein Drittel die
					# Flanke hinunter ihre volle Hoehe.
					# DIE OBERE RAMPE WAR ZU KURZ (0.18). Direkt unter der Lippe stehen die
					# Rippen am dichtesten beieinander, weil sie dort zusammenlaufen; mit
					# voller Amplitude schon 170 m unter dem Rand sass um den Krater ein
					# Lattenzaun. Ueber ein Drittel der Flanke eingeblendet waechst der Grat
					# mit dem Platz, den er hat.
					# SIE BEI NULL ANFANGEN ZU LASSEN, war der Fehler danach: siehe
					# VULKAN_RIPPEN_LIPPE. Beide Teile addieren sich, weil jeder smoothstep im
					# Bereich des anderen konstant ist — an der Lippe ist der innere fertig und
					# der aeussere faengt bei null an, die Kurve hat dort also weder Sprung noch
					# Knick.
					# UNTEN LAEUFT SIE ERST AM FUSS AUS statt schon bei 0.80 * r. Die Grate
					# duerfen den Fussabdruck ausfransen — das ist die zweite Haelfte des
					# gebrochenen Fusses; abgeschnitten wird nichts, weil maxf gegen das
					# Vorland ohnehin nur anhebt.
					var huell := (VULKAN_RIPPEN_LIPPE
						* smoothstep(krx * VULKAN_RIPPEN_INNEN, krx, md)
						+ (1.0 - VULKAN_RIPPEN_LIPPE)
						* smoothstep(krx, krx + (mr - krx) * 0.35, md)) \
						* (1.0 - smoothstep(mr * 0.90, mr * 1.02, md))
					# DER KREIS WAECHST MIT DER WURZEL DES ABSTANDS, und daran haengt, ob man
					# die Grate ueberhaupt sieht:
					#   * fester Kreis heisst konstanter WINKEL je Rippe. Die Rippen laufen
					#     nach oben zusammen wie Speichen — am Gipfel Cordsamt, am Fuss 1000 m
					#     breite Wellen, die keine Flaeche mehr kippen. Beides war im Bild.
					#   * ein mit md mitwachsender Kreis waere konstante BREITE in Metern —
					#     das ist aber wieder gewoehnliches x/z-Rauschen, die Richtung ist weg.
					# Die Wurzel liegt dazwischen: die Rippe wird nach unten breiter, aber nur
					# halb so schnell wie der Umfang. Sie bleibt radial und ueber die ganze
					# Flanke in einer Breite, die man sieht.
					var rkr := _vk_rippen_kreis * sqrt(md / mr)
					top += rip * huell * _ridge.get_noise_3d(ux * rkr, uz * rkr,
						md * VULKAN_RIPPEN_LAUF)
					# DIE FEINRIPPEN AUF DEMSELBEN KREIS, nur dichter und schneller den Hang
					# hinunter (siehe VULKAN_FEINRIPPE_N). "feinrippen" ist ihre Amplitude in
					# Metern und schaltet sie ein; ohne den Schluessel bleibt die Flanke
					# exakt, wie sie war, und die zweite Rauschabfrage faellt weg.
					# SIE HAENGT AN DERSELBEN HUELLKURVE wie die groben Rippen — sie faengt
					# also innen in der Kraterwand an und laeuft am Fuss aus. Zwei
					# Huellkurven fuer dasselbe Muster waeren zwei Zahlen, die beim naechsten
					# Eingriff auseinanderlaufen.
					var frp := float(ms.get("feinrippen", 0.0))
					if frp > 0.0:
						top += frp * huell * _ridge.get_noise_3d(
							ux * rkr * VULKAN_FEINRIPPE_N, uz * rkr * VULKAN_FEINRIPPE_N,
							md * VULKAN_FEINRIPPE_LAUF)
				# --- FELSLAGE ------------------------------------------------------------
				# "fels" bricht die Flaechen auf (Begruendung bei VULKAN_FELS_M). Sie haengt
				# an sv, laeuft also zum Fuss hin von selbst aus und liegt zugleich auf der
				# Lippe und im Kraterboden — beide waren ohne sie gedrechselt glatt.
				var flz := float(ms.get("fels", 0.0))
				var felslage := 0.0
				if flz > 0.0:
					felslage = flz * sv * _ridge.get_noise_2d(
						x * _vk_fels_takt, z * _vk_fels_takt)
					top += felslage
				# --- ABRISSKANTEN: DIE KURZE WELLE ---------------------------------------
				# "nasen" ist die Hoehe der Stufe in Metern und schaltet die Lage ein; ohne
				# den Schluessel bleibt die Flanke exakt, wie sie war. Warum es sie NEBEN
				# Rippen, Felslage und Blocklage braucht — die alle GROSS gegen ein
				# 8-m-Dreieck sind —, steht bei VULKAN_NASEN_AB.
				# SIE STEHT VOR DEM BARRANCO-BLOCK UND NICHT DARIN, weil sie dessen
				# Rinnenlage nicht braucht: ein Abriss hat keine Vorzugsrichtung, er sitzt
				# auf dem Grat so gut wie in der Sohle. Damit kostet sie auch dann nur eine
				# Rauschabfrage, wenn der Kegel gar keine Rinnen hat.
				# DIE INNERE RAMPE haelt sie aus dem fertigen Kraterrand heraus, genau wie
				# bei Rinnen und Bloecken; die aeussere endet vor dem Waldkragen
				# (VULKAN_NASEN_AUS_AB, dort steht warum).
				var nas := float(ms.get("nasen", 0.0))
				if nas > 0.0 and md > krx and md < mr * VULKAN_NASEN_AUS_ZU:
					top += nas * (smoothstep(VULKAN_NASEN_AB, VULKAN_NASEN_VOLL,
							_patch.get_noise_2d(x * _vk_grus_takt, z * _vk_grus_takt)) - 0.5) \
						* smoothstep(krx, krx + (mr - krx) * 0.06, md) \
						* (1.0 - smoothstep(mr * VULKAN_NASEN_AUS_AB,
							mr * VULKAN_NASEN_AUS_ZU, md))
				# --- BARRANCOS: DIE EROSIONSRINNEN DER FLANKE ----------------------------
				# "barranco" ist ihre Tiefe in Metern (Grat gegen Sohle) und schaltet den
				# Abschnitt ein; ohne den Wert bleibt die Flanke exakt, wie sie war. Warum es
				# sie NEBEN den Rippen braucht und warum das atan2 hier ausnahmsweise keine
				# Naht macht, steht bei VULKAN_BARR_N.
				# SIE LIEGEN UEBER DEN RIPPEN, NICHT STATT IHRER: die Rippen (10 Grundlappen,
				# vier Oktaven) rauen die Flaechen auf, die Barrancos gliedern den Kegel in
				# 30 zaehlbare Rinnen mit Graten dazwischen. Die Rippen allein konnten das
				# nicht — ein Rauschen hat keine zaehlbaren Rinnen und keinen Ort, an dem
				# eine anfaengt.
				var bar := float(ms.get("barranco", 0.0))
				# "ader_tief" ist die Tiefe des LAVAKANALS in Metern, "lava_lappen" die
				# Hoehe der erkalteten Lappen am Fuss. Beide fehlen duerfen: dann bleibt
				# die Flanke exakt, wie sie ohne sie waere.
				var adt := float(ms.get("ader_tief", 0.0))
				var lpn := float(ms.get("lava_lappen", 0.0))
				# "bloecke" ist die Auswurfhoehe der FELSAUFSCHLUESSE in Metern und schaltet
				# die Blocklage ein; ohne den Wert bleibt die Flanke exakt, wie sie war.
				# Sie steht in DIESEM Block und nicht daneben, weil sie die Rinnenlage
				# braucht (Aufschluss auf dem Grat, Schutt in der Sohle) — rn ist hier
				# ohnehin schon geholt, die Lage kostet also genau eine Rauschabfrage.
				var blk := float(ms.get("bloecke", 0.0))
				if (bar > 0.0 or adt > 0.0 or lpn > 0.0 or blk > 0.0) \
						and md > krx and md < mr * VULKAN_BARR_AUS_ZU:
					var rn := _vulkan_rinne(ux, uz, md)
					if blk > 0.0:
						# DIE BLOCKLAGE — WAS SIE LEISTEN SOLL, STEHT BEI VULKAN_BLOCK_M:
						# Facetten in Dreiecksgroesse mit einer besonnten und einer
						# verschatteten Seite, statt grosser glatter Felder.
						# ABGETASTET WIRD IN X/Z UND NICHT RADIAL, und das ist Absicht: ein
						# Felsaufschluss hat keine Vorzugsrichtung. Die Gliederung des
						# Kegels machen die Rinnen, diese Lage gibt ihr den Massstab.
						# DREI HUELLEN, jede mit eigenem Grund:
						#   die Schwelle          — Nester statt Belag (VULKAN_BLOCK_AB),
						#   rn.x * rn.x           — Aufschluss auf dem Grat, Schutt in der
						#                           Sohle, damit die Ader ihren Boden behaelt,
						#   die beiden Rampen     — innen aus dem fertigen Kraterrand heraus,
						#                           aussen ueber dem Waldkragen aufhoeren
						#                           (VULKAN_BLOCK_AUS_AB, dort steht warum).
						top += blk * smoothstep(VULKAN_BLOCK_AB, VULKAN_BLOCK_VOLL,
								_ridge.get_noise_2d(x * _vk_block_takt, z * _vk_block_takt)) \
							* lerpf(VULKAN_BLOCK_SOHLE, 1.0, rn.x * rn.x) \
							* smoothstep(krx, krx + (mr - krx) * 0.10, md) \
							* (1.0 - smoothstep(mr * VULKAN_BLOCK_AUS_AB,
								mr * VULKAN_BLOCK_AUS_ZU, md))
					if bar > 0.0:
						# HUELLKURVE: an der gewachsenen Lippe null (krx, nicht der nominelle
						# Kraterradius — sonst schnitte die Rinne dort in den fertigen Rand,
						# wo die Lippe nach innen wandert), voll auf der Mittelflanke, im
						# Apron aus.
						var bhu := smoothstep(krx, krx + (mr - krx) * VULKAN_BARR_OBEN, md) \
							* (1.0 - smoothstep(mr * VULKAN_BARR_AUS_AB,
								mr * VULKAN_BARR_AUS_ZU, md))
						# UM DEN EIGENEN MITTELWERT ZENTRIERT (VULKAN_BARR_MITTE): Grat auf,
						# Sohle ab, mittlere Flankenhoehe unveraendert. Ein reiner Abtrag
						# haette den Kegel um zwei Drittel der Tiefe abgesenkt und die
						# vermessene Boeschung mitgenommen — und die ist fertig.
						# Das Querprofil bringt die feine Oberharmonische gleich mit
						# (siehe _vulkan_rinne_profil); die Farbe liest dieselbe Kurve.
						top += bar * bhu * rn.y \
							* _vulkan_rinne_profil(rn.x, rn.z, md, krx, mr)
					# --- DER LAVAKANAL UND SEIN LAPPEN -----------------------------------
					# WARUM DIE ADER EINE EIGENE FORM BRAUCHT UND NICHT NUR EINE FARBE:
					# das Netz gabelt sich ueber MEHRERE Rinnen hinweg, ein Stamm laeuft
					# oben also zwangslaeufig ueber einen Barranco-Grat. Eine gluehende Linie
					# auf einem Gratruecken ist genau der aufgemalte Zustand, aus dem diese
					# Runde herausfuehren soll — Lava liegt in einer Mulde, nicht auf einer
					# Kante. Der Kanal schneidet sie sich selbst und traegt den Aushub als
					# Damm daneben auf: das ist die Form, die ein Strom wirklich hinterlaesst,
					# und sie haelt den Hoehenverlust in Grenzen.
					if adt > 0.0 or lpn > 0.0:
						var ad := _vulkan_ader(rn.z, md, mr, cr)
						if adt > 0.0:
							# Der Kanal ist so breit wie die Kruste (nicht wie die Glut) und
							# faellt zum Fuss hin FLACHER aus: unten ist er 50 m breit, und
							# 28 m Tiefe darin waeren eine Klamm statt einer Rinne. Der
							# Massstab dafuer ist die Aderbreite selbst — eine zweite
							# Tiefenrampe waere eine Zahl, die neben der ersten ausschert.
							var kw := ad.y * VULKAN_ADER_KRUSTE
							var v := minf(ad.x / (kw * 1.8), 1.0)
							var q := 1.0 - v * v
							# 3.24 = 1.8^2: damit ist das Profil bei ad.x = kw genau null,
							# innen Rinne, aussen Damm. Der Damm traegt rund ein Siebtel
							# dessen auf, was die Rinne abtraegt.
							top += adt * clampf(ad.y / (VULKAN_ADER_KERN * 2.6), 0.45, 1.0) \
								* smoothstep(krx, krx + (mr - krx) * 0.12, md) \
								* (1.0 - smoothstep(mr * 0.82, mr * 0.96, md)) \
								* (3.24 * v * v - 1.0) * q * q
						if lpn > 0.0:
							top += lpn * _vulkan_lappen(ad, md, mr)
				if typ == "vulkan":
					# --- KRATER IM ABGESTUMPFTEN GIPFEL ------------------------------
					# "rand_h" schaltet ihn ein; ohne den Wert bleibt es bei der alten
					# abgezogenen Delle (siehe else).
					# DER RAND IST KEIN AUFGESETZTER BUCKEL MEHR, SONDERN DIE KANTE SELBST:
					# bei md = krx hoert die Flanke auf und die Schuessel faengt an. Nach beiden
					# Seiten faellt das Gelaende, der Rand ist damit von Haus aus ein lokales
					# Maximum und wirft im Streiflicht seinen Schatten in die Schuessel. Warum der
					# frueher aufgesetzte Buckel genau das verhindert hat, steht bei
					# VULKAN_KRONE_AUSSEN.
					# SEINE HOEHE IST RINGSUM DIESELBE (peak + rand_h); gezackt machen ihn die
					# Felslage und das Gratrauschen darunter, also rund 40 m auf 650 — wenige
					# Prozent, so wie es sein soll. Was stark schwankt, ist sein RADIUS
					# ("lippe"): das sieht man dem Umriss an, ohne dass der Ring aufreisst.
					var randh := float(ms.get("rand_h", 0.0))
					if randh > 0.0:
						var u := md / maxf(krx, 1.0)
						# SCHARTE: die Kerbe in der Lippe. "scharte_ri" ist ihre Richtung als
						# Winkel in der x/z-Ebene; gemessen wird ueber das Skalarprodukt mit der
						# Einheitsrichtung.
						# HIER STAND 0.90 .. 0.995, das sind gut 50 Grad Oeffnung, und abgetragen
						# wurde der Wall auf voller Hoehe und noch 80 m darunter. Das war keine
						# Scharte mehr: von aussen sah man durch den Gipfel in die Schuessel, der
						# Ringwall war kein Ring, und im Abnahmebild blieb vom Gipfel nur eine
						# einseitig offene Kerbe. Jetzt sind es rund 20 Grad.
						var sc := 0.0
						var sw := float(ms.get("scharte", 0.0))
						if sw > 0.0:
							var sri := float(ms.get("scharte_ri", 0.0))
							sc = sw * smoothstep(0.955, 0.999,
								ux * cos(sri) + uz * sin(sri))
						var tiefe := float(ms.get("crater_depth", float(ms["peak"]) * 0.45))
						# DIE LIPPE: ein schmaler Grat auf der Kante, nach beiden Seiten kurz aus.
						# minf statt einer Fallunterscheidung — beide Faktoren sind bei u = 1 genau
						# eins, und jeder deckt eine Seite ab.
						top += randh * (1.0 - sc) * minf(
							1.0 - smoothstep(0.0, VULKAN_KRONE_INNEN, 1.0 - u),
							1.0 - smoothstep(0.0, VULKAN_KRONE_AUSSEN, u - 1.0))
						# DIE SCHUESSEL. Oben endet sie bei 0.97 und nicht bei 1.0: ein smoothstep
						# hat an seinem Ende die Steigung null, die Wand liefe also direkt unter der
						# Lippe waagerecht aus und liesse dort eine Bank stehen, auf der das Licht
						# liegen bleibt statt in den Schatten zu kippen.
						top -= tiefe * (1.0 - smoothstep(VULKAN_SOHLE, 0.97, u))
						# --- DER LAVASEE AUF DER SOHLE ------------------------------
						# "lavasee" ist die Hoehe der Stufe von der Schuttsohle auf den
						# Spiegel, in Metern; ohne den Wert bleibt die Sohle durchgehend
						# wie bisher. Warum es ihn braucht, steht bei VULKAN_SEE_R.
						var see := float(ms.get("lavasee", 0.0))
						if see > 0.0:
							var sk := 1.0 - smoothstep(VULKAN_SEE_R,
								VULKAN_SEE_R + VULKAN_SEE_UFER, u)
							if sk > 0.0:
								top -= see * sk
								# UND JETZT DAS EIGENTLICHE: die beiden Rauschlagen, die
								# oben aufgetragen wurden, kommen im See wieder weg.
								# ER IST DIE EINZIGE WAAGERECHTE FLAECHE DES GANZEN BERGES,
								# und genau daran liest das Auge ihn als Fluessigkeit — in
								# einer Landschaft gibt es keinen anderen Grund fuer eine
								# exakte Ebene. Der erste Versuch legte den See nur tiefer
								# und liess das Rauschen darauf stehen; heraus kam eine
								# Schlackenhalde in einem Loch, und die ist genau so
								# tiefenlos wie der Trichter, den sie ersetzen sollte.
								# Die Rippen sind hier KEIN Thema: sie fangen erst bei
								# VULKAN_RIPPEN_INNEN an, und das ist dieselbe Zahl wie
								# VULKAN_SEE_R (dort steht, warum das so bleiben muss).
								top -= sk * (kraut + felslage)
						# DER SCHLOT. "schlot" ist seine Tiefe in Metern; ohne den Wert bleibt
						# die Sohle eben wie bisher.
						# ER IST NICHT SCHMUCK, SONDERN DAS, WAS DIE SCHUESSEL ALS SCHUESSEL
						# LESBAR MACHT. Die Sohle ist so breit wie der halbe Krater, und eine
						# waagerechte Flaeche dieser Groesse bekommt von der Sonne fast dieselbe
						# Helligkeit wie das Vorland: im Abnahmebild lag im Krater eine helle
						# Pfanne, an der das Auge keine Tiefe ablesen konnte, obwohl der Rand
						# gemessen 290 m darueber stand. Ein dunkles Loch in der Mitte gibt ihr
						# den Bezugspunkt zurueck.
						# Er sitzt auf u, nicht auf md — der Schlot wandert damit mit der Lippe
						# mit und ist von Haus aus gelappt statt gedrechselt.
						var slt := float(ms.get("schlot", 0.0))
						if slt > 0.0:
							top -= slt * (1.0 - smoothstep(0.0, VULKAN_SCHLOT_R, u))
						# DER EINSCHNITT GEHOERT DEM WALL, NICHT DER SOHLE. Ohne die innere Grenze
						# zog die Kerbe als Graben quer ueber den ganzen Kraterboden bis in die
						# Mitte und hinterliess dort obendrein einen einzelnen Zacken: im
						# Mittelpunkt selbst gibt es keine Richtung, die Kerbe greift dort also
						# nicht. Nach aussen laeuft sie als Rinne den Oberhang hinunter — erst damit
						# ist es ein Durchbruch, durch den etwas abfliessen koennte, und nicht bloss
						# eine flache Stelle im Wall.
						top -= sc * tiefe * VULKAN_SCHARTE_TIEF \
							* smoothstep(VULKAN_SOHLE, 0.88, u) \
							* (1.0 - smoothstep(1.05, 2.1, u))
					else:
						# Krater: Kegelspitze zur Schüssel eindrücken (Boden bleibt hoch/trocken)
						var bowl := 1.0 - smoothstep(cr * 0.35, cr, md)
						top -= bowl * float(ms.get("crater_depth", float(ms["peak"]) * 0.45))
				h = maxf(h, top)
	# STRAND-SCHELF: Hänge nahe der Wasserlinie abflachen -> breite Sandstrände und
	# breite türkise Untiefen (die Küste "leuchtet"). Blendet bis ±10 m sanft aus.
	var shelf_k := 1.0 - smoothstep(2.5, 10.0, absf(h - SEA_Y))
	if shelf_k > 0.001:
		h = lerpf(h, SEA_Y + (h - SEA_Y) * 0.45, shelf_k)
	# Flugplätze/Plateaus einebnen: im Innenradius exakt auf Zielhöhe y (default 0),
	# außen weich zum Gelände überblenden. (Bergdorf nutzt y>0 -> Hochplateau.)
	# "quer_faktor" macht aus dem Kreis eine ELLIPSE laengs der Bahn — nur ADLERHORST
	# nutzt das. Begruendung dort (Main._build_world, siehe QUERFAKTOR).
	for af in airfields:
		var ap: Vector3 = af["pos"]
		var adx := x - ap.x
		var adz := z - ap.z
		var ad := sqrt(adx * adx + adz * adz)
		# Vorfilter: jenseits von r_blend ist smoothstep 1 und lerpf die Identitaet. Der
		# Kreisradius ist nie groesser als der elliptische, der Abbruch ist also exakt und
		# spart in der Regel gleich die ganze Ellipsenrechnung.
		if ad >= float(af["r_blend"]):
			continue
		var qf: float = af.get("quer_faktor", 0.0)
		if qf > 0.0:
			var c: float = af["_cos"]
			var s: float = af["_sin"]
			var al := adx * s + adz * c          # laengs der Bahn (Weltrichtung sin/cos)
			var qu := (adx * c - adz * s) / qf   # quer dazu, gestaucht -> reicht kuerzer
			ad = sqrt(al * al + qu * qu)
		var ty: float = af.get("y", 0.0)
		h = lerpf(ty, h, smoothstep(float(af["r_flat"]), float(af["r_blend"]), ad))
	# Inland-Seen: Becken in den (bereits flachen) Grund graben, Boden bleibt über
	# dem Meeresspiegel (-6), damit das globale Meer nicht durchscheint.
	for lk in lakes:
		var lp: Vector3 = lk["pos"]
		var lr: float = lk["r"]
		var ldx := x - lp.x
		var ldz := z - lp.z
		if lk.has("_rad"):
			# BERGSEE mit gelapptem Umriss. Die Uferlinie liegt EXAKT auf dem
			# Tabellenradius: innen ist die Hoehe gesetzt (Mischanteil 0), aussen wird ueber
			# SEE_UFERBAND ins gewachsene Gelaende geblendet. Der Umriss haengt damit nicht
			# mehr davon ab, wie hoch das Umfeld zufaellig steht — beim alten Becken
			# entschied genau das (Flachzone gegen Rauschen) ueber die Uferlinie, und
			# heraus kam eine Scheibe mit ausgefranstem Rand.
			# Reichweite ist jetzt der WALL, nicht mehr das schmale Uferband: bis
			# SEE_WALL_ENDE hinter der Uferlinie rechnet der See am Gelaende mit.
			var rmax: float = float(lk["_rmax"]) + SEE_WALL_ENDE
			if absf(ldx) > rmax or absf(ldz) > rmax:
				continue
			var ld2 := sqrt(ldx * ldx + ldz * ldz)
			if ld2 > rmax:
				continue
			var ach: Vector2 = lk["_achse"]
			var lu := ldx * ach.x + ldz * ach.y      # laengs der Talachse
			var lv := ldx * ach.y - ldz * ach.x      # quer dazu
			var uw := _see_umriss(lk, atan2(lv, lu))
			var rr: float = uw.x
			var hang: float = uw.y
			var wsp: float = float(lk["surf"])
			if ld2 <= rr:
				var tief := minf(hang * (rr - ld2), _see_mulde(lu / lr, lv / lr))
				# Feine Unruhe auf dem Grund. Ohne sie faerbt der Wasser-Shader die Tiefe in
				# sauberen konzentrischen Baendern — von oben sah der See aus wie eine
				# Hoehenlinienkarte. Am Ufer auf null gezogen (die letzten 70 m), damit die
				# Uferlinie exakt auf dem Tabellenradius bleibt und das Wassernetz weiter passt.
				tief += 0.55 * _patch.get_noise_2d(x * 0.32, z * 0.32) \
					* minf(1.0, (rr - ld2) / 70.0)
				# INNEN GILT NUR DIE FORMEL. Dadurch liegt die Uferlinie exakt auf dem
				# Tabellenradius, egal wie das Gelaende ringsum steht — und genau daran
				# haengt die gemessene Rundheit.
				h = wsp - maxf(tief, 0.0)
			else:
				# AUSSEN: Beckenrand. Der Wall steht fuer sich, das gewachsene Gelaende darf
				# nur ANHEBEN und blendet ueber SEE_NATURBAND ein. Ohne diese Einblendung
				# stuende an der Uferlinie eine senkrechte Wand — der Talboden liegt hier
				# stellenweise 60 m ueber dem Spiegel.
				# DASS NUR ANGEHOBEN WIRD, ist die Dichtigkeitsgarantie: bis rund 275 m
				# hinter dem Ufer ist das Wallprofil positiv, also liegt dort ein
				# GESCHLOSSENER Ring ueber dem Spiegel, ganz gleich, was das Gelaende macht.
				var ua := ld2 - rr                     # Abstand hinter der Uferlinie
				var wall := wsp + _see_wallprofil(ua, hang, uw.z, uw.w)
				h = lerpf(wall, maxf(wall, h),
					smoothstep(0.0, lerpf(SEE_NATURBAND, SEE_SCHARTE_BAND, uw.w), ua))
			continue
		var ld := Vector2(ldx, ldz).length()
		var bowl := 1.0 - smoothstep(lr * 0.55, lr, ld)   # 1 Mitte .. 0 Rand
		if bowl > 0.0:
			var floor_y: float = float(lk["surf"]) - 4.0
			h = lerpf(h, floor_y, bowl)
	# FLÜSSE: Tal + Flussbett entlang der Spline graben (nur Chunks im River-AABB).
	if not rivers.is_empty():
		h = _river_carve(x, z, h)
	return h


# Gräbt das Flusstal: nächstes Spline-Segment suchen, Bett unter die (entlang der
# Spline fallende) Wasserhöhe senken, Ufer weich ins Gelände blenden. min() = nur
# nach UNTEN graben (nie Gelände aufschütten). AABB-Early-Out hält es performant.
func _river_carve(x: float, z: float, h: float) -> float:
	for rv in rivers:
		if x < rv["minx"] or x > rv["maxx"] or z < rv["minz"] or z > rv["maxz"]:
			continue
		var pts: PackedVector3Array = rv["pts"]
		var tal_breiten: PackedFloat32Array = rv["tal"]
		var best_d2 := INF
		var best_surf := 0.0
		var best_tal := 0.0
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var dx := b.x - a.x
			var dz := b.z - a.z
			var l2 := dx * dx + dz * dz
			var t := 0.0 if l2 < 1e-6 else clampf(((x - a.x) * dx + (z - a.z) * dz) / l2, 0.0, 1.0)
			var px := a.x + dx * t
			var pz := a.z + dz * t
			var dd := (x - px) * (x - px) + (z - pz) * (z - pz)
			if dd < best_d2:
				best_d2 = dd
				best_surf = lerpf(a.y, b.y, t)   # Wasserhöhe an dieser Stelle
				best_tal = lerpf(tal_breiten[i], tal_breiten[i + 1], t)
		var dist := sqrt(best_d2)
		var valley: float = best_tal
		if dist < valley:
			var w: float = rv["w"]
			# BETT NICHT UEBER DIE VOLLE BREITE FLACH, sondern zur Mitte hin tief.
			# Vorher lag es ueber die ganze Breite w auf einer Ebene, waehrend das
			# Wasserband nur 0,92*w breit ist: an der Bandkante standen damit noch 4 m
			# Tiefe. Der Shader schneidet die Uferlinie aber ueber die TIEFE (waterline) —
			# bei 4 m ist edge = 1 und foam = 0, das Wasser endete also mit voller
			# Deckkraft an einer schnurgeraden Polygonkante, ohne Untiefe und ohne Schaum.
			# Mit der Verjuengung bleibt an der Bandkante rund 0,2 m Tiefe uebrig, und der
			# Shader laesst das Wasser dort von selbst auslaufen.
			# Die Verjuengung muss VOR der Bandkante (0,92*w) auf null sein, nicht erst bei
			# w: bei 0,45..1,0 blieben dort gemessen noch 0,40 m Tiefe, und der Shader
			# schneidet die Uferlinie erst unter waterline (0,30 m) — die Kante waere
			# sichtbar geblieben.
			var mitte := 1.0 - smoothstep(w * 0.40, w * 0.88, dist)
			var bed: float = best_surf - float(rv["depth"]) * mitte
			# ROBUST (seed-unabhängig): Bett auf bed senken, Ufer steigen auf
			# mind. Wasserhöhe+1 (nie unter Wasser -> kein schwebendes Wasser),
			# außen ins natürliche Gelände blenden. Gesetzt, nicht nur min().
			var k := smoothstep(w, valley, dist)        # 0 Bett .. 1 Talrand
			var bank := maxf(best_surf + 1.2, h)        # Ufer immer über dem Wasser
			# EINSCHNITT DECKELN. Im Bett galt bisher h = bed, und bed kommt ALLEIN aus der
			# Spline: das Gelaende wurde dort auf die Wasserhoehe heruntergerissen, egal wie
			# hoch es ringsum stand. Laeuft eine Spline ueber eine Flanke, die 200 m ueber
			# ihrem Wasser liegt, schneidet ein 9 m breiter Bach eine 200-m-Schlucht mit
			# senkrechten Waenden. Genau das ist im Hochtal passiert — gemessen 201,7 m
			# Sprung auf 8 m Rasterweite, und ohne Fluesse blieben davon 49,8 m uebrig.
			# "max_tief" begrenzt, wie weit unter das VORHANDENE Gelaende der Bach graben
			# darf. Ohne den Wert bleibt alles wie bisher — der Westcanyon lebt davon, tief
			# einzuschneiden, und darf nicht gedeckelt werden.
			var mt: float = float(rv.get("max_tief", 0.0))
			if mt > 0.0:
				bed = maxf(bed, h - mt)
			h = lerpf(bed, bank, k)
	return h


# Fluss-Splines aufbereiten: Punkte als PackedVector3Array (x, Wasserhöhe y, z),
# AABB inkl. Tal-Margin für den Early-Out vorberechnen.
func _prepare_rivers(rvs: Array) -> void:
	rivers = []
	for rv in rvs:
		var pts := PackedVector3Array()
		for p in rv["pts"]:
			pts.append(p)
		if pts.size() < 2:
			continue
		var minx := INF; var maxx := -INF; var minz := INF; var maxz := -INF
		for p in pts:
			minx = minf(minx, p.x); maxx = maxf(maxx, p.x)
			minz = minf(minz, p.z); maxz = maxf(maxz, p.z)
		var valley: float = rv.get("valley", 60.0)
		# TALBAND JE STUETZPUNKT statt eine Zahl je Fluss. Gebraucht wird das nur am
		# Abfluss des Bergsees: dort muss das Band an der QUELLE schmal sein. _river_carve
		# zieht naemlich im ganzen Band die Ufer auf Wasserhoehe + 1,2 m und dazwischen
		# hinunter zum Bett — ein 70-m-Band reicht also 70 m um den ersten Stuetzpunkt
		# herum und wuerde die Schwelle des Sees aufschneiden. Der erste Punkt musste
		# deshalb 70 m hinter die Schwelle, und im Bild fing der Bach sichtbar erst weit
		# neben dem See an. Mit "tal_quelle" faengt er schmal an und weitet sich ueber
		# "tal_lauf" Meter auf die volle Breite — die Klamm entsteht dort, wo sie hingehoert.
		var tal_breiten := PackedFloat32Array()
		var tq: float = rv.get("tal_quelle", valley)
		var tl: float = maxf(float(rv.get("tal_lauf", 1.0)), 1.0)
		var lauf := 0.0
		for i in pts.size():
			if i > 0:
				lauf += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
			tal_breiten.append(lerpf(tq, valley, clampf(lauf / tl, 0.0, 1.0)))
		var m := valley + 6.0
		# max_tief MUSS MIT. Diese Funktion baut ein NEUES Woerterbuch; alles, was hier
		# nicht aufgefuehrt ist, kommt in _river_carve nie an. Genau daran ist der Deckel
		# gegen den 200-m-Einschnitt zuerst wirkungslos verpufft.
		rivers.append({"pts": pts, "w": rv.get("w", 14.0), "valley": valley, "tal": tal_breiten,
			"depth": rv.get("depth", 4.0), "max_tief": rv.get("max_tief", 0.0),
			# 1 = Zufluss des Bergsees, -1 = Abfluss. Ihre Hoehen stehen NICHT in der Liste,
			# sondern werden von seebaeche_einpassen() am Gelaende abgelesen.
			"seebach": int(rv.get("seebach", 0)),
			"minx": minx - m, "maxx": maxx + m, "minz": minz - m, "maxz": maxz + m})


## BAECHE DES BERGSEES AN DAS GELAENDE ANLEGEN. Laeuft einmal aus setup(), nachdem die
## Rauschgeneratoren stehen und bevor die Wasserbaender gebaut werden.
##
## WARUM ZUR LAUFZEIT UND NICHT ALS FESTE ZAHLEN IN DER FLUSSLISTE: _river_carve SETZT die
## Hoehe (h = lerp(bett, ufer, k)) und zieht das Ufer auf mindestens Wasserhoehe + 1,2 m
## hoch. Eine Spline UEBER dem Gelaende schuettet damit einen DAMM auf, eine weit darunter
## graebt eine SCHLUCHT. Beides ist hier schon passiert: die Zahlen in der Datei waren an
## ein Hochtal angepasst, das es nach der naechsten Aenderung an den Talketten nicht mehr
## gab (gemessen liegt der Talboden am See je nach Richtung zwischen 41 und 230 m).
## Abgelesen wird OHNE die Fluesse (rivers voruebergehend leer): sonst liest die Anpassung
## ihr eigenes Bett wieder ein und graebt sich bei jedem Start ein Stueck tiefer.
func _seebaeche_einpassen() -> void:
	var see: Dictionary = {}
	for lk in lakes:
		if lk.has("_rad"):
			see = lk
			break
	if see.is_empty():
		return
	var wsp: float = float(see["surf"])
	var lp: Vector3 = see["pos"]
	var ach: Vector2 = see["_achse"]
	var alle := rivers
	rivers = []
	for rv in alle:
		var art: int = int(rv.get("seebach", 0))
		if art == 0:
			continue
		var pts: PackedVector3Array = rv["pts"]
		var tiefe: float = float(rv["depth"])
		var n := pts.size()
		if art > 0:
			# ZUFLUSS: die Muendung ist der LETZTE Punkt, angepasst wird flussAUFwaerts.
			# Ihr Bett liegt GENAU auf dem Spiegel, keinen Zentimeter darunter — ein
			# tieferes Bett am Ufer zapft den See an, und die Flutfuellung von
			# tools/_see_form.gd liefe den Bach hinauf und maesse ihn als Seeflaeche mit.
			var p0 := pts[n - 1]
			p0.y = wsp + tiefe + 0.2
			pts[n - 1] = p0
			for i in range(n - 2, -1, -1):
				var p := pts[i]
				# Mindestgefaelle nach oben, damit der Bach nirgends bergauf fliesst; sonst
				# liegt er 1,2 m unter dem Gelaende, gilt also ein flaches Bett.
				var l := Vector2(p.x - pts[i + 1].x, p.z - pts[i + 1].z).length()
				p.y = maxf(pts[i + 1].y + SEE_BACH_STEIGUNG * l, height_at(p.x, p.z) - 1.2)
				pts[i] = p
		else:
			# ABFLUSS: Quelle ist der ERSTE Punkt, angepasst wird flussABwaerts.
			# HOECHSTENS SPIEGELHOEHE (er kommt aus dem See), aber wenn der Boden hinter der
			# Schwelle schon tiefer liegt, dann DORT hinein. Vorher stand hier nur die erste
			# Haelfte, und weil der Boden hinter der Schwelle rund 2 m unter dem Spiegel
			# liegt, schuettete _river_carve dem Bach einen Damm unter das Bett: gemessen lag
			# er auf den ersten 275 m 1 bis 2 m UEBER dem Seespiegel und floss bergauf.
			var q0 := pts[0]
			q0.y = minf(wsp + tiefe + 0.2, height_at(q0.x, q0.z) - 0.35)
			pts[0] = q0
			for i in range(1, n):
				var p := pts[i]
				# GEFAELLE JE METER, nicht je Stuetzstelle. Mit einem festen Betrag je Punkt
				# (0,4 m) blieb der Bach ueber 1000 m fast waagerecht stehen, waehrend das
				# Gelaende ringsum 30 m hoeher lag — im Bild war das ein schnurgerader,
				# schwarzer Schlitz quer durch die Talstufe. Mit 3,5 % faellt er so schnell,
				# wie ein Wildbach faellt, und schneidet nur noch die Schwelle an.
				var l := Vector2(p.x - pts[i - 1].x, p.z - pts[i - 1].z).length()
				p.y = minf(pts[i - 1].y - SEE_BACH_GEFAELLE * l, height_at(p.x, p.z) - 0.7)
				# SCHWELLE: auf ihr darf das Bett nicht unter den Spiegel fallen, sonst
				# schneidet der Abfluss den Beckenrand auf und laesst den See ab.
				# HIER STAND SEE_WALL_BREITE * 1.4, also 294 m — und das war zu viel: ueber
				# diese ganze Strecke wurde das Bett auf Spiegelhoehe HOCHgeklemmt, obwohl
				# der Boden darunter faellt. Genau daraus wurde der Damm. Die Schwelle ist
				# nur noch die Scharte selbst (SEE_SCHARTE_SILL), und der erste Stuetzpunkt
				# liegt ohnehin dahinter — der Zweig ist eine Bremse fuer den naechsten, der
				# die Punktliste in Main verschiebt, kein Bestandteil der Form.
				var dx := p.x - lp.x
				var dz := p.z - lp.z
				var u := dx * ach.x + dz * ach.y
				var v := dx * ach.y - dz * ach.x
				if sqrt(dx * dx + dz * dz) - _see_umriss(see, atan2(v, u)).x \
						< SEE_SCHARTE_SILL:
					p.y = maxf(p.y, wsp + tiefe + 0.2)
				pts[i] = p
		rv["pts"] = pts
	rivers = alle


const LAKE_SEG := 192      # Richtungen (Bogenschritt am Rand: 5.7 m bei r=175)
const LAKE_RINGS := 10     # Ringe Mittelpunkt -> Rand (Vorrat fuer die Gerstner-Runde)

# --- GELAPPTER SEEUMRISS (Bergsee im Hochtal) ------------------------------------------
# Der Umriss stand bisher an ZWEI Stellen: das Becken in height_at und das Wassernetz in
# _build_lake_water. Beide rechneten mit demselben Kreisradius r — sobald einer davon eine
# Bucht bekommt, passt das Wasser nicht mehr ins Becken. Deshalb wird die Uferlinie hier
# EINMAL in eine Tabelle gerechnet; beide Seiten lesen nur noch ab (_see_umriss).
# Nur Seen mit dem Schluessel "form_achse" bekommen sie — Stadtsee und Canyonsee bleiben
# unveraendert rund.
const SEE_TABELLE := 720   # Eintraege der Umrisstabelle (0,5 Grad; Fehler der Sehne < 1 m)
# Uferband, ueber das nach AUSSEN ins gewachsene Gelaende geblendet wird. In METERN, nicht
# als Anteil von R: der schmale Arm ist bei gleichem Anteil sonst von einem viel breiteren
# Ufersaum umgeben als das Hauptbecken.
const SEE_UFERBAND := 140.0
# --- BECKENRAND -----------------------------------------------------------------------
# Der See hing vorher an einer PLATTE: eine Flachzone von 790 m Radius hob sein ganzes
# Umfeld auf Spiegel + 6 m, damit er nicht ins Tal auslaeuft. Gemessen war das rundum ein
# 517 m breiter, ebener, KAHLER Saum — kahl, weil jede Flachzone in _open_ground zugleich
# eine Freihaltezone ist (gemessen: Bewuchs 0 bis 620 m, voll erst ab 1147 m). Auf 84 m
# Hoehe liegt sie ausserdem ueber der Felsschwelle von _face_color (45..59 m), also war
# sie auch noch braun. Im Bild lag der See als Pfuetze auf einer Pfanne.
# Jetzt traegt sich der See SELBST: ausserhalb der Uferlinie steigt ein Wall, der dem
# gelappten Umriss folgt, und in ihn hinein blendet das gewachsene Gelaende. Der Wall ist
# nur dort ueberhaupt zu sehen, wo der Talboden unter ihm liegt (maxf) — sonst steht der
# Berghang unveraendert bis ans Wasser. Gemessen liegt der Talboden hier auf 41..230 m
# (Mittel 116 m), der See auf 78 m: fast rundum gewinnt das Gelaende, der Wall dichtet nur
# die zwei flachen Richtungen ab.
const SEE_WALL_BREITE := 210.0   # Uferabstand des Kamms
const SEE_WALL_ENDE := 560.0     # ab hier ist der Wall rechnerisch weg -> Gelaende pur
const SEE_WALL_FALL := 300.0     # wie tief er hinter dem Kamm rechnerisch faellt
const SEE_NATURBAND := 240.0     # Strecke, ueber die das Gelaende von aussen einblendet
# HIER STAND DIE ALMWIESE (SEE_WIESE_HUB / SEE_WIESE_WEITE). Sie haengt jetzt am
# TALKORRIDOR statt am Uferabstand — Begruendung bei TAL_WIESE_HUB.
# ERZWUNGENES Gefaelle des Abflusses (0,8 %) und MINDESTanstieg des Zuflusses (0,6 %),
# jeweils in Metern je Meter Lauflaenge. Beide sind klein, und zwar aus demselben Grund:
# jeder Meter, den ein Bach ueber dem Boden verlangt, ist ein aufgeschuetteter Damm, und
# jeder Meter darunter ein Einschnitt (_river_carve SETZT die Hoehe). Das Gefaelle ist
# also nur die MINDESTneigung; das eigentliche Profil kommt aus dem Gelaende
# (min mit height_at - 0,7).
# HIER STANDEN 2,5 %. Auf der jetzigen Strecke — sie bleibt bis 1000 m hinter dem See
# zwischen 76 und 82 m, siehe SEE_ABFLUSS_GRAD — haetten 2,5 % das Bett bis dahin 14 m
# unter den Boden gezogen, also eine 14 m tiefe Rinne quer durch einen fast ebenen
# Talboden gegraben. Mit 0,8 % sind es rund 4 m.
const SEE_BACH_GEFAELLE := 0.008
const SEE_BACH_STEIGUNG := 0.006


## Gauss-Glocke ueber dem Winkel, kuerzeste Richtung (der Sprung bei +-PI faellt weg).
func _winkelglocke(a: float, mitte: float, breite: float) -> float:
	var d := wrapf(a - mitte, -PI, PI) / breite
	return exp(-d * d)


## UMRISSFAKTOR des Bergsees: Radius geteilt durch r, ueber dem Winkel a.
## a = 0 zeigt talaufwaerts (zum Flugplatz), a = +PI/2 quer dazu.
##
## Die Form ist die des Referenzbildes und besteht aus vier Teilen:
##   1. eine laengs gestreckte Grundellipse (1.05 zu 0.72) — der See liegt IM Tal,
##   2. eine Enge bei +-90 Grad: von beiden Ufern schieben sich Landzungen herein und
##      schnueren den See fast durch (die beiden Glocken sind ungleich stark, sonst steht
##      dort eine saubere Sanduhr),
##   3. ein schmaler ARM nach hinten (Glocke bei 0 Grad, nur 10 Grad breit) — er allein
##      bringt den groessten Teil der Rundheit,
##   4. vier Kaps und Buchten am Hauptbecken.
## Darueber liegen drei kleine Harmonische; sie kerben das Ufer, ohne die Form zu aendern.
##
## WARUM DIESE ZAHLEN: tools/_see_form.gd misst Rundheit = Umfang^2/(4*PI*Flaeche), und
## das Werkzeug ist an analytischen Formen kalibriert — eine blosse Delle bringt 1.09, zwei
## verschmolzene Kreise 1.36. Ueber die geforderten 1.4 kommt man nur mit Enge UND Arm.
## Diese Kurve liegt rechnerisch (Umfangsintegral) bei 2.14.
##
## DER GROESSTE RADIUS IST EIN HARTES BUDGET, nicht Geschmack: er betraegt 1.84, der See
## reicht mit Uferband also 1.84 * r + 140 m hinaus, und SO WEIT muss die Flachzone des
## Sees reichen. Der Talboden liegt hier naemlich auf rund 0 m — der See steht 78 m
## darueber und haelt sich allein an der Flachzone. Ragt er darueber hinaus, laeuft er ins
## Tal aus: gemessen mit rmax = 2.35 * 420 lief die Flutfuellung von _see_form.gd bis an
## den Fensterrand und meldete 1,05 km2 Flaeche und 80 m Tiefe.
func _see_umriss_faktor(a: float) -> float:
	# GRUNDFORM IST EIN EI, KEINE ELLIPSE. Hier stand eine Ellipse 1.05 zu 0.72, also
	# vorn und hinten gleich breit — und genau daraus wurde der Vorwurf "spiegelsymmetrischer
	# Schmetterling quer zum Tal". Nachgemessen war er berechtigt: die Halbbreite lag bei
	# u = -0.5 wie bei u = +0.5 bei 0.71 r, die beiden Becken waren gleich gross, und im
	# Grundriss stand eine saubere Sanduhr. Ein Trogsee sieht anders aus — vorn das grosse
	# Hauptbecken, dahinter ein langer, stetig schmaler werdender Schwanz.
	# Deshalb haengen beide Halbachsen am Vorzeichen von cos(a): talABwaerts (cos < 0) ist
	# der See lang und breit, talAUFwaerts kurz und schmal. Der Uebergang ist ein smoothstep
	# ueber cos(a) und kein Umschalten — an der Nahtstelle stuende sonst ein Knick, und ein
	# Knick in der Uferlinie ist im Wassernetz eine gerade Kante ueber 190 m.
	# Gemessen (Umfangsintegral): 1215 zu 482 m, also 2,5 zu 1 statt vorher 2,05 zu 1.
	var eg := smoothstep(-0.35, 0.35, cos(a))
	var ce := cos(a) / lerpf(1.40, 1.20, eg)
	var se := sin(a) / lerpf(0.58, 0.43, eg)
	var v := 1.0 / sqrt(ce * ce + se * se)
	# Enge in der Mitte. maxf faengt ab, dass die beiden Glocken den Radius auf null
	# druecken und der See dort in zwei Teile zerfaellt.
	# DIE BEIDEN SEITEN SIND JETZT SEHR VERSCHIEDEN (0.34 gegen 0.62). Vorher standen dort
	# 0.56 und 0.50, also praktisch dasselbe — und von oben war der See dadurch eine
	# Sanduhr mit vier gleichen Fluegeln, ein Schmetterling. Im Referenzbild schiebt sich
	# die Enge von EINER Seite herein: von der flachen, wo ein Schuttfaecher in den See
	# waechst. Die steile Felsflanke (+90 Grad) bleibt eine fast gerade Uferlinie.
	v *= maxf(1.0 - 0.34 * _winkelglocke(a, 1.5708, 0.4363)
		- 0.62 * _winkelglocke(a, -1.5708, 0.3665), 0.18)
	v += 0.72 * _winkelglocke(a, 0.0, 0.1745)          # schmaler Arm nach hinten
	# Der Arm ist als Polarfunktion zwangslaeufig ein Keil. Diese kleine Glocke daneben
	# knickt ihn aus der Achse, sonst steht dort ein sauberes gleichschenkliges Dreieck.
	v += 0.16 * _winkelglocke(a, 0.1571, 0.0873)
	# DIE DREI BREITEN LAPPEN SIND MIT DER EIFORM HERUNTERGEGANGEN (0.30/0.22/0.20 auf
	# 0.24/0.17/0.14). Sie stehen alle quer zur Talachse, und mit den alten Amplituden waere
	# der See zwar laenger, aber genauso breit geblieben — die Streckung waere in den Lappen
	# wieder verpufft. Die KERBEN (Kaps, Haken, Landzunge) bleiben unveraendert: sie kosten
	# keine Breite und tragen die Rundheit.
	v += 0.24 * _winkelglocke(a, 2.6529, 0.3840)       # runde Bucht
	v -= 0.20 * _winkelglocke(a, 3.5779, 0.2618)       # Kap dazwischen
	# HAKEN-KAP bei 202 Grad: eine SCHMALE, TIEFE Kerbe im Radius, also eine Landzunge, die
	# 100 m weit ins Wasser sticht — im Referenzbild das praegendste Merkmal des Ufers und
	# das, was hier gefehlt hat (das Ufer war ueberall glatt-konvex, die Rundheit kam allein
	# aus Taille und Arm). Die Bucht 10 Grad daneben kruemmt sie: ohne die zweite Glocke
	# steht dort ein gleichschenkliges Dreieck statt eines Hakens.
	# WARUM DIE ZUNGE VON SELBST EIN KIESHAKEN WIRD: sie liegt ausserhalb der Uferlinie,
	# also traegt sie das Wallprofil — auf dieser Seite (sin a < 0) sind das 4 m Randhoehe
	# und ein flacher Uferhang, die Zunge steht damit nur ein bis zwei Meter ueber dem
	# Wasser und faellt genau in das Hoehenband, in dem _face_color den Kiessaum faerbt.
	# Breite 0.085 rad ist die Untergrenze: das Wassernetz hat 192 Richtungen (1,9 Grad),
	# schmaler als rund 5 Grad kann es die Form nicht mehr zeichnen.
	v -= 0.24 * _winkelglocke(a, 3.5255, 0.0850)       # Haken-Kap
	v += 0.13 * _winkelglocke(a, 3.7000, 0.0750)       # Bucht dahinter
	v += 0.17 * _winkelglocke(a, 4.1539, 0.3316)       # breiter Lappen
	v -= 0.13 * _winkelglocke(a, 2.0595, 0.2269)       # zweites Kap
	v += 0.14 * _winkelglocke(a, 5.2360, 0.2967)       # Lappen an der Flachseite
	v -= 0.14 * _winkelglocke(a, 5.6723, 0.2269)       # Landzunge davor
	# ABFLUSSBUCHT bei 151 Grad, also GENAU auf der Scharte (SEE_ABFLUSS_GRAD). Sie ist
	# schmaler als die Scharte (0.075 gegen 0.11 rad), damit ihr ganzes Ufer schon im
	# Schwellenprofil liegt und nicht halb im hohen Wall.
	# WOZU: zwischen Uferlinie und Bachkopf liegen zwangslaeufig rund 40 m Kiesbank —
	# _river_carve senkt den Boden bis w Meter neben der Spline auf Wasserhoehe, naeher darf
	# der Bach der Schwelle nicht kommen (Rechnung bei SEE_SCHARTE_BANK). Mit der Bucht zieht
	# das WASSER dem Bach 56 m entgegen, statt dass die Bank ihn vom See wegschiebt. Sie ist
	# flach (nur Grundtiefe, siehe _see_mulde), das Tuerkis laeuft also als Trichter auf die
	# Schwelle zu: See -> Trichter -> Schotter -> Bach, ohne Bruch dazwischen.
	v += 0.165 * _winkelglocke(a, 2.6354, 0.0750)      # Abflussbucht auf der Scharte
	v += 0.030 * cos(7.0 * a + 1.1) + 0.022 * cos(11.0 * a + 2.3) \
		+ 0.014 * cos(17.0 * a + 0.4)
	return maxf(v, 0.12)


## UFERHANG in Metern Tiefe je Meter Uferabstand, ueber dem Winkel.
## Die Breite des tuerkisen Saums ist NICHTS ANDERES als 2 m geteilt durch diesen Wert —
## der Wasser-Shader faerbt allein nach Tiefe. Eine neue Farbe braucht es dafuer nicht.
## Absichtlich EINSEITIG: an der Felsflanke (a nahe +90 Grad) faellt das Ufer steil ab und
## der Saum verschwindet fast (0.48 -> 4,2 m), auf der Flachseite laeuft er weit aus
## (0.030 -> 67 m). Ein rundum gleich breiter Saum war genau das, was den alten See wie
## eine ausgestanzte Scheibe aussehen liess.
## HIER STAND 0.042 + 0.26 (6,7 bis 48 m). Der Unterschied war im Bild nicht zu sehen —
## nachgemessen liegt das daran, dass der Saum am flachen Ufer ohnehin an der Grundtiefe
## haengt (SEE_GRUNDTIEFE 1,8 m, also unter der 2-m-Grenze der Faerbung) und die 48 m
## damit gar nicht erreicht wurden. Was fehlte, war die STEILE Seite: 6,7 m sind bei 8 m
## Netzweite noch immer eine volle Dreiecksreihe Tuerkis. Mit 4,2 m verschwindet sie.
func _see_uferhang(a: float) -> float:
	return 0.030 + 0.45 * pow(clampf(sin(a), 0.0, 1.0), 1.4)


## HOEHE DES BECKENRANDES ueber dem Wasserspiegel, ueber dem Winkel.
## Ungleich, aber KLEIN: ein rundum gleich hoher Rand ist ein Kraterrand, ein hoher Rand
## ist ein Damm. Die Abwechslung soll aus dem Gelaende kommen (height_at nimmt das
## Maximum), nicht aus dieser Formel.
##
## HIER STAND 12 + 22 * sin, also 12 bis 34 m. Das war zu viel und ist der Grund, warum
## zwischen See und Abflussbach ein bewaldeter Ruecken stand: gemessen (tools/_see_pass.gd,
## Gelaende ohne See und ohne Fluesse) faellt der Boden suedoestlich des Sees schon 100 m
## hinter der Uferlinie auf 56 bis 75 m ab — dort gewinnt nicht das Gelaende das Maximum,
## sondern der Wall, und er stand als bis zu 35 m hoher, 350 m breiter Ringwall um den See.
## Mit 4 bis 13 m bleibt ein Uferwall, wie ihn eine Moraene macht, und dahinter faellt das
## Gelaende sofort wieder frei ab.
##
## HIER STAND, das Gelaende dichte den See fast von allein ab und die niedrigste
## natuerliche Schwelle liege 53 m ueber dem Spiegel. Das galt fuer ein frueheres Hochtal.
## Nachgemessen (tools/_see_pass.gd) stimmt es nur noch nach Nordwesten; nach Suedosten
## faellt der Boden auf 56 bis 75 m, also bis 22 m UNTER den Spiegel. Dort ist der Rand
## eine Moraene, kein Berghang — und genau deshalb muss er niedrig bleiben.
##
## --- DIE SCHARTE, ueber die der See abfliesst ------------------------------------------
## HIER STAND 161 GRAD, UND DAS WAR DIE FALSCHE RICHTUNG. Gemessen mit tools/_see_pass.gd
## (Dijkstra auf dem gewachsenen Gelaende, Kosten = HOECHSTE Zelle des Weges statt Summe —
## also genau der Pass, den auch Wasser suchen wuerde):
##   * ueber 161 Grad kostet der Weg ins Tal 88.9 m, also 10,9 m ueber dem Spiegel, und er
##     faellt dabei zuerst in eine Mulde auf 70 m. Ein Bachbett darf nie ueber dem Boden
##     liegen (_river_carve wuerde sonst einen Damm aufschuetten), die Mulde zieht es also
##     mit — und der naechste Riegel muss dann 20 m tief angeschnitten werden.
##   * ueber 151 Grad kostet er 75,4 m und liegt damit 2,6 m UNTER dem Spiegel: von der
##     Scharte bis zur Talstufe faellt der gewachsene Boden ohne einen einzigen Gegenhang.
##     Der Bach muss dort gar nichts anschneiden, er liegt einfach in der Rinne.
## Deshalb 151 Grad. Die Zahl ist gemessen, nicht gewaehlt; wer am Hochtal etwas aendert,
## laesst _see_pass.gd noch einmal laufen (Aufruf im Kopf der Datei) und danach
## tools/_see_abfluss.gd, das Schwelle und Laengsprofil des Baches nachmisst.
##
## DIE SCHWELLE IST DAS, WAS DEN WASSERSTAND FESTLEGT — sie darf nicht unter den Spiegel.
## Deshalb ist das Scharten-Profil die ersten SEE_SCHARTE_SILL Meter POSITIV: solange
## beide Zweige der Einblendung in height_at (Wall und max(Wall, Gelaende)) ueber dem
## Spiegel liegen, ist der Ring dicht, ganz gleich was das Gelaende darunter macht. Erst
## dahinter faellt es. 12 m Schwelle sind drei Rasterzellen der Flutfuellung in
## tools/_see_form.gd — genug, dass sie nicht durchsickert und den halben Talboden als
## Seeflaeche zaehlt, und kurz genug, dass die Schwelle im Bild ein Ufersaum bleibt und
## keine Terrasse. 24 m waren als flacher Grasstreifen zwischen See und Bach zu sehen.
const SEE_ABFLUSS_GRAD := 151.0   # Richtung, in der der See ueberlaeuft (siehe Main)
const SEE_SCHARTE_BREITE := 0.11  # halbe Winkelbreite der Scharte (rad) -> rund 45 m Gasse
const SEE_SCHARTE_KAMM := 0.60    # Hoehe der Schwelle ueber dem Spiegel
const SEE_SCHARTE_SILL := 16.0    # Laenge der Schwelle hinter der Uferlinie
# --- DIE KIESBANK HINTER DER SCHWELLE ---------------------------------------------------
# HIER FIEL DIE RINNE DIREKT HINTER DER SCHWELLE MIT 60 PROZENT AB, und das war der Grund,
# warum der Abfluss NICHT am See hing. Gemessen (tools/_see_abfluss.gd) lag der erste
# Stuetzpunkt des Baches 34 m hinter der Uferlinie auf 64,6 m — 13,4 m UNTER dem Spiegel.
# Naeher heran ging er nicht: _river_carve senkt den Boden im Umkreis w auf Wasserhoehe,
# ein Bachkopf dicht am Ufer haette also die Schwelle aufgeschnitten und den See abgelassen.
# Und tiefer als der Boden durfte er nicht liegen, sonst schuettet _river_carve einen Damm.
# Zwischen Wasserlinie und Bachanfang standen damit 34 m trockener Hang mit 40 Prozent
# Gefaelle — im Bild grasgruen, und das blaue Band setzte dahinter aus dem Nichts ein.
#
# Der Fehler war die 60-Prozent-Rinne, nicht der Abstand. Ein See laeuft nicht ueber eine
# Klippe aus, sondern ueber eine KIESBANK: erst SEE_SCHARTE_SILL Meter Schwelle knapp
# ueber dem Spiegel, dann SEE_SCHARTE_BANK Meter mit sanftem Gefaelle (die Bank, auf der
# der Bach anfaengt), und ERST DAHINTER die Steilstufe. Auf der Bank liegt der Bachkopf
# jetzt 1 bis 2 m unter dem Spiegel statt 13 m, und beide Wasserflaechen stehen praktisch
# auf einer Ebene.
# Rechnerisch bleibt der Boden bis SILL + KAMM/FALL_BANK = 16 + 8 = 24 m ueber dem
# Spiegel. DAS IST DAS BUDGET FUER DEN BACHKOPF: _river_carve senkt bis w Meter neben der
# Spline auf Wasserhoehe, der erste Stuetzpunkt muss also mindestens 24 + w hinter der
# Uferlinie liegen (siehe Main, Abflussliste). Wer eine der beiden Zahlen aendert, laesst
# tools/_see_form.gd laufen: sickert die Schwelle durch, meldet es sofort die halbe
# Talsohle als Seeflaeche.
const SEE_SCHARTE_BANK := 40.0      # Laenge der Kiesbank hinter der Schwelle
const SEE_SCHARTE_FALL_BANK := 0.075
# 0.60 = 60 Prozent Gefaelle, und das ist Absicht: unter rund 4,6 m Hoehenunterschied je
# 8-m-Zelle pflanzt die Flora noch Baeume (siehe die Hangschranke dort). Mit einer durchweg
# sanften Rinne stand im Bild ein bewaldeter Gruenhang zwischen See und Bach. Auf der
# Kiesbank ist das jetzt unkritisch: sie liegt innerhalb von _rmax und unter Spiegel + 0,8,
# und _submerged sperrt dort ohnehin jeden Baum. Ab der Steilstufe bleibt es bei 60 Prozent.
const SEE_SCHARTE_FALL := 0.60
# In der Scharte blendet das gewachsene Gelaende viel frueher ein als sonst (45 statt
# 240 m). WARUM: die Einblendung mischt den WALL mit max(Wall, Gelaende) — reicht sie
# weit, dann zieht ein abfallendes Scharten-Profil das Gelaende auf 240 m Laenge mit nach
# unten, und aus der Gasse wird ein 20 m tiefer Graben quer durch den Hang. Mit 45 m steht
# hinter der Schwelle sofort wieder der gewachsene Boden.
# HIER STANDEN 45 M, ALSO WENIGER, ALS DIE KIESBANK LANG IST (16 + 40 = 56 m). Dahinter
# gilt max(Wall, Gelaende); die Bank blieb zwar stehen, weil das gewachsene Gelaende hier
# steil faellt, aber ein Buckel im Rauschen haette sie durchstossen und den Bachkopf auf
# einen Riegel gesetzt. 60 m decken sie ganz ab. Die Warnung oben gilt weiter — massgeblich
# ist das GEFAELLE des Profils, nicht die Laenge: die Bank faellt auf 40 m um 3 m.
const SEE_SCHARTE_BAND := 60.0
# --- DAS DELTA, ueber das der See gespeist wird ----------------------------------------
# DERSELBE FEHLER WIE BEIM ABFLUSS, nur am anderen Ende: der Zuflussbach endete 81 m hinter
# der Uferlinie, und dazwischen stand der Beckenrand mit 8,1 m Hoehe (_see_wandhoehe bei
# 27 Grad). Im Bild verschwand der Bach im Wald und der See hatte sichtbar keinen Speiser.
# Ein Bergsee bekommt sein Wasser aber ueber einen SCHUTTFAECHER: eine flache, kiesige
# Ebene knapp ueber dem Spiegel, ueber die der Bach in mehreren Rinnen ins Becken laeuft.
# Genau das ist diese Kerbe — der Rand faellt im Zuflusssektor von 8,1 m auf 0,9 m ab.
# 0,9 m UND NICHT NULL: der Ring muss geschlossen ueber dem Spiegel bleiben, sonst laeuft
# der See hier aus (und die Flutfuellung von tools/_see_form.gd mit ihm). Das Bett des
# Baches liegt mit Spiegel + 0,2 m selbst noch darueber, schneidet also nur eine flache
# Rinne in das Delta, ohne den Ring zu oeffnen.
const SEE_ZUFLUSS_GRAD := 27.0    # Richtung, aus der der Zuflussbach kommt (siehe Main)
const SEE_ZUFLUSS_BREITE := 0.16  # halbe Winkelbreite des Deltas (rad) -> rund 95 m Front
# 0,45 M UND NICHT 0,9 — DIE ZAHL HAENGT AN DER FLORA, nicht an der Optik. _submerged
# sperrt Bewuchs bis Spiegel + 0,8 m. Mit 0,9 m lag das Delta 0,1 m DARUEBER, und im Bild
# stand ein geschlossener Fichtenwald auf dem Schuttfaecher: der Zuflussbach verschwand
# darin und der See sah wieder aus, als haette er keinen Speiser. Mit 0,45 m ist der
# Faecher kahl. Nach unten ist die Zahl durch die Dichtigkeit begrenzt — unter dem Spiegel
# laeuft der See hier aus. Dieselbe Rechnung steht beim Abfluss hinter SEE_SCHARTE_KAMM
# (0,60 m), und deshalb ist auch die Kiesbank dort baumfrei.
const SEE_DELTA_KAMM := 0.45      # Hoehe des Deltas ueber dem Spiegel


## Wie stark die Scharte an dieser Stelle wirkt (0 = voller Wall, 1 = Schwelle).
func _see_scharte(a: float) -> float:
	return _winkelglocke(a, deg_to_rad(SEE_ABFLUSS_GRAD), SEE_SCHARTE_BREITE)


func _see_wandhoehe(a: float) -> float:
	# Der Beckenrand, und im Zuflusssektor stattdessen das flache Delta. lerpf statt einer
	# Subtraktion: so ist die Kerbe unabhaengig davon, wie hoch der Rand ringsum steht.
	return lerpf(4.0 + 9.0 * clampf(sin(a), 0.0, 1.0), SEE_DELTA_KAMM,
		_winkelglocke(a, deg_to_rad(SEE_ZUFLUSS_GRAD), SEE_ZUFLUSS_BREITE))


## WALLPROFIL ueber dem Uferabstand d (0 = Uferlinie), in Metern ueber dem Spiegel.
##
## Faengt mit dem UFERHANG an: die Untiefe laeuft dadurch stufenlos ueber die Wasserlinie
## hinaus weiter, und der Kiessaum von _face_color liegt auf derselben Neigung wie der
## Seegrund davor. Bis SEE_WALL_BREITE steigt es auf wh.
##
## DANACH FAELLT ES RECHNERISCH WEIT UNTER NULL, und das ist kein Schoenheitsfehler,
## sondern der Trick: height_at nimmt das Maximum aus Wall und gewachsenem Gelaende. Ein
## Wall, der nur auf null zurueckginge, wuerde den Talboden ringsum auf Seehoehe halten —
## also wieder die Platte, nur mit weicherem Rand. Weit negativ verliert er das Maximum
## von selbst, und draussen steht exakt das unveraenderte Gelaende.
##
## In der Scharte (sch = 1) gilt stattdessen das Schwellenprofil: Schwelle knapp ueber dem
## Spiegel, dann eine Rinne bergab, die das Maximum schnell an das Gelaende verliert.
func _see_wallprofil(d: float, hang: float, wh: float, sch: float) -> float:
	var auf := maxf(smoothstep(0.0, SEE_WALL_BREITE, d), minf(hang * d / wh, 1.0))
	var wall := wh * auf - SEE_WALL_FALL * smoothstep(SEE_WALL_BREITE, SEE_WALL_ENDE, d)
	if sch <= 0.001:
		return wall
	# DREI ABSCHNITTE: Schwelle (waagerecht, ueber dem Spiegel), Kiesbank (sanft), Steilstufe.
	# Als Summe zweier abgeschnittener Rampen geschrieben, damit das Profil stetig bleibt —
	# eine Fallunterscheidung haette an den Knicken je eine Stufe hinterlassen, und im
	# Hoehenfeld ist jede Stufe eine sichtbare Dreieckskante.
	var rinne := SEE_SCHARTE_KAMM * minf(hang * d / SEE_SCHARTE_KAMM, 1.0) \
		- SEE_SCHARTE_FALL_BANK * maxf(d - SEE_SCHARTE_SILL, 0.0) \
		- (SEE_SCHARTE_FALL - SEE_SCHARTE_FALL_BANK) \
			* maxf(d - SEE_SCHARTE_SILL - SEE_SCHARTE_BANK, 0.0)
	return lerpf(wall, rinne, sch)


## Umrisstabelle eines Sees fuellen. Danach traegt lk die Schluessel _rad (Radius je
## Winkel), _hang (Uferhang je Winkel), _wall (Randhoehe je Winkel), _achse
## (Laengsrichtung) und _rmax.
func _see_umriss_bauen(lk: Dictionary) -> void:
	var ach: Vector2 = Vector2(lk["form_achse"]).normalized()
	var r0: float = float(lk["r"])
	var rad := PackedFloat32Array()
	var hang := PackedFloat32Array()
	var wall := PackedFloat32Array()
	var sch := PackedFloat32Array()
	rad.resize(SEE_TABELLE)
	hang.resize(SEE_TABELLE)
	wall.resize(SEE_TABELLE)
	sch.resize(SEE_TABELLE)
	var rmax := 0.0
	for i in SEE_TABELLE:
		var a := TAU * float(i) / float(SEE_TABELLE)
		var r := r0 * _see_umriss_faktor(a)
		rad[i] = r
		hang[i] = _see_uferhang(a)
		wall[i] = _see_wandhoehe(a)
		sch[i] = _see_scharte(a)
		rmax = maxf(rmax, r)
	lk["_rad"] = rad
	lk["_hang"] = hang
	lk["_wall"] = wall
	lk["_scharte"] = sch
	lk["_achse"] = ach
	lk["_rmax"] = rmax


## Tabelle ablesen: Vector4(Uferradius, Uferhang, Randhoehe, Schartenanteil) fuer a.
## Linear zwischen zwei Eintraegen — bei 0,5 Grad Schritt bleibt der Fehler unter 1 m.
func _see_umriss(lk: Dictionary, a: float) -> Vector4:
	var rad: PackedFloat32Array = lk["_rad"]
	var hang: PackedFloat32Array = lk["_hang"]
	var wall: PackedFloat32Array = lk["_wall"]
	var sch: PackedFloat32Array = lk["_scharte"]
	var t := a / TAU * float(SEE_TABELLE)
	var i := int(floor(t))
	var f := t - float(i)
	i = ((i % SEE_TABELLE) + SEE_TABELLE) % SEE_TABELLE
	var j := (i + 1) % SEE_TABELLE
	return Vector4(lerpf(rad[i], rad[j], f), lerpf(hang[i], hang[j], f),
		lerpf(wall[i], wall[j], f), lerpf(sch[i], sch[j], f))


## TIEFE des Bergsees an einer Stelle (Laengs/Quer in Vielfachen von r, gemessen vom
## Seemittelpunkt), begrenzt durch den Uferhang.
##
## WARUM NICHT EINFACH TIEFE = HANG * UFERABSTAND: der "Uferabstand" waere hier der
## RADIALE (R - Abstand zur Mitte). Im schmalen Arm ist der gross — das echte Ufer liegt
## aber seitlich, keine 60 m entfernt. Der Arm waere damit 15 m tief geworden statt zu
## einer Untiefe mit Kiesbaenken.
## HIER STANDEN ZWEI ELLIPSOIDE MULDEN (SEE_MULDE1/2), und von oben war genau das zu
## sehen: zwei saubere, dunkelblaue OVALE in einer tuerkisen Pfanne, dazwischen eine breite
## helle Schneise. Zwei Ovale sind keine Seetiefe, sondern zwei gezeichnete Flecken — im
## Referenzbild ist das Tiefwasser EIN zusammenhaengender Koerper, und seine Form folgt dem
## Ufer statt einer eigenen Achse.
##
## Jetzt gibt es stattdessen eine TIEFENLINIE (Thalweg): einen Streckenzug durch den See,
## an dem je Stuetzpunkt die groesste Tiefe steht. Die Tiefe faellt mit dem Abstand ZUR
## LINIE, nicht zu einem Mittelpunkt — damit ist das Tiefwasser per Konstruktion
## zusammenhaengend, und weil die Linie mitknickt (quer von -0,22 ueber +0,10 zurueck auf
## +0,06), ist es eine gekruemmte Niere und kein Oval.
## Die Tiefen sind die des Referenzbildes: tief im vorderen Hauptbecken, duenn und flach in
## der Enge, wieder etwas tiefer im hinteren Becken, und im Arm nur noch Grundtiefe. Der
## Arm bleibt damit von selbst eine tuerkise Untiefe mit Kiesbaenken.
##
## KOORDINATEN in Vielfachen von r, im Achsensystem des Sees: x laengs (positiv
## talaufwaerts, zum Arm), y quer, z die groesste Tiefe dort in Metern.
## Das Minimum mit hang * (R - ld) in height_at sorgt dafuer, dass die Tiefe an der
## Uferlinie EXAKT null wird; ohne das stuende dort eine Stufe. Es kappt auch, wo der Trog
## breiter waere als der See — in der Enge zum Beispiel.
const SEE_GRUNDTIEFE := 1.8      # Arm, Enge, Buchten (unter 2 m -> tuerkis)
## Die Stuetzpunkte sind ABGETASTET, nicht geschaetzt: fuer u von -1.3 bis 1.9 wurde die
## Uferlinie geschnitten und die Mitte zwischen den beiden Ufern genommen. Deshalb wandert
## y von +0.20 im Hauptbecken ueber -0.08 vor der Enge zurueck auf 0 — der See ist dort
## wirklich so aus der Achse gebogen. Wer den Umriss aendert, tastet das neu ab.
## w ist die halbe Breite des Trogs an dieser Stelle, ebenfalls in Vielfachen von r.
## SIE MUSS MITWANDERN, und das war der zweite Anlauf wert: mit EINER Breite fuer den
## ganzen See lag das Tiefwasser als gleich breites Band schraeg ueber dem Becken — im Bild
## ein dunkler Kanal, kein Seegrund. Jetzt ist der Trog im Hauptbecken fast so breit wie
## das Becken selbst (0.36 gegen 0.61 Halbbreite) und in der Enge nur noch ein Faden. Das
## Tiefwasser wird damit eine Linse, deren Rand dem Ufer folgt — genau das, was am
## Referenzbild anders war.
const SEE_TIEFENLINIE: Array[Vector4] = [
	Vector4(-1.28, 0.12, 2.0, 0.12),
	Vector4(-1.05, 0.20, 8.0, 0.21),
	Vector4(-0.72, 0.06, 12.5, 0.34),   # tiefste Stelle des Hauptbeckens
	Vector4(-0.50, -0.02, 12.5, 0.36),
	Vector4(-0.28, -0.08, 10.0, 0.32),
	Vector4(-0.08, -0.02, 6.0, 0.21),
	Vector4(0.06, 0.02, 3.2, 0.11),     # Enge: das Tiefwasser wird hier zum Faden
	Vector4(0.35, -0.05, 5.5, 0.21),    # hinteres Becken
	Vector4(0.75, 0.01, 2.0, 0.13),
	Vector4(1.20, 0.02, 0.6, 0.09),     # Arm: nur noch Grundtiefe
]
# Die innersten 15 Prozent der Trogbreite bleiben flach — ohne diese Sohle laeuft die Tiefe
# auf einen Grat zu, und der Shader zeichnet daraus eine dunkle Linie laengs durch den See.
const SEE_TIEFENSOHLE := 0.15


func _see_mulde(lu: float, lv: float) -> float:
	var tief := 0.0
	for i in range(SEE_TIEFENLINIE.size() - 1):
		var a: Vector4 = SEE_TIEFENLINIE[i]
		var b: Vector4 = SEE_TIEFENLINIE[i + 1]
		var dx := b.x - a.x
		var dy := b.y - a.y
		var l2 := dx * dx + dy * dy
		var t := 0.0 if l2 < 1e-9 else clampf(((lu - a.x) * dx + (lv - a.y) * dy) / l2, 0.0, 1.0)
		var qx := lu - (a.x + dx * t)
		var qy := lv - (a.y + dy * t)
		var d := sqrt(qx * qx + qy * qy)
		var hb := lerpf(a.w, b.w, t)
		# maxf ueber die Abschnitte: an einem Knick greifen zwei Abschnitte, und die Summe
		# waere dort eine Beule.
		tief = maxf(tief, lerpf(a.z, b.z, t)
			* (1.0 - smoothstep(hb * SEE_TIEFENSOHLE, hb, d)))
	return SEE_GRUNDTIEFE + tief

## Wasserflaeche eines Inlandsees: GESCHLOSSENES RINGGITTER UEBER DAS GANZE BECKEN.
##
## Die Uferlinie schneidet der SHADER, nicht das Mesh: dort ist ALPHA mit
## smoothstep(0, waterline, Wassertiefe) multipliziert, ueber trockenem Grund ist die
## senkrechte Tiefe null und die Flaeche damit unsichtbar. Das Mesh muss die Uferlinie
## also nicht nachzeichnen — es muss das Becken nur lueckenlos ueberdecken.
##
## Der Versuch, sie trotzdem GEOMETRISCH zu suchen (Bisektion je Richtung von r nach
## innen), ist gescheitert und war im Bild sofort zu sehen: er setzt voraus, dass
## height_at vom Seemittelpunkt nach aussen monoton steigt. Das tut sie nicht — der
## Fluss-Carve laeuft NACH dem See-Carve und zieht Uferwaelle quer durch das Becken
## (See 0, Richtung 0 Grad, Hoehe ueber surf bei r=0/40/80/120/160 m:
## -2.13 / -3.79 / +0.98 / -2.91 / +0.52). Die Bisektion landete auf der INNERSTEN
## Kreuzung, der Faecher kollabierte zum Mittelpunkt und riss Tortenstuecke heraus:
## gemessen See 0 Radius 41.5 .. 152.4 m (Fehlbetrag bis 109.5 m), See 1 0.0 .. 260.0 m.
##
## Nach AUSSEN wird bewusst NICHT gesucht: rund um See 1 liegt der Canyonboden auf
## weiter Flaeche unter dessen Wasserhoehe (gemessen: in 42 von 64 Richtungen noch bei
## 377 m, bis an die Messgrenze 780 m). Ein "bis zur naechsten Kreuzung fluten" wuerde
## dort die halbe Schlucht unter Wasser setzen. Das Becken endet bei r — das ist der
## Radius, bis zu dem height_at ueberhaupt graebt.
##
## GEMESSEN (Nadir-Render mit und ohne die Scheibe, Differenzbild, 64 Richtungen):
## fehlendes Wasser See 0 im Mittel 2.67 m, See 1 1.58 m; Wasser ueber trockenem Grund
## See 0 max 0.50 m, See 1 0.00 m.
func _build_lake_water(lk: Dictionary) -> void:
	var lp: Vector3 = lk["pos"]
	var lr: float = lk["r"]
	var surf: float = float(lk["surf"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	# Ringe vorberechnen. COLOR.a blendet den aeussersten Ring aus: wo der Beckenrand
	# ausnahmsweise noch im Wasser liegt (See 1, Canyonseite: 1.0 m Tiefe bei r), endet
	# die Flaeche sonst mit einer harten Linie. Innen ist COLOR.a = 1.
	# GELAPPTER UMRISS: der Randradius kommt je Richtung aus DERSELBEN Tabelle, aus der
	# auch height_at das Becken graebt (_see_umriss). Bis 1.02 hinaus, damit die Netzkante
	# sicher hinter der Uferlinie liegt — der Shader schneidet sie ueber die Tiefe.
	var geformt := lk.has("_rad")
	var ach: Vector2 = lk["_achse"] if geformt else Vector2(1.0, 0.0)
	var rings: Array = []
	for j in range(LAKE_RINGS + 1):
		var frac := float(j) / float(LAKE_RINGS)
		var fade := 1.0 - smoothstep(float(LAKE_RINGS - 1), float(LAKE_RINGS), float(j))
		var ring := PackedVector3Array()
		for i in LAKE_SEG:
			var a := TAU * float(i) / float(LAKE_SEG)
			var rr := lr * frac
			if geformt:
				rr = _see_umriss(lk, a).x * frac * 1.02
				# a ist der LOKALE Winkel um die Talachse — genau der, mit dem height_at
				# die Tabelle abfragt. Deshalb hier in dieselbe Basis zurueckdrehen.
				var cu := cos(a) * rr
				var cv := sin(a) * rr
				ring.append(Vector3(cu * ach.x + cv * ach.y, 0.0, cu * ach.y - cv * ach.x))
				continue
			ring.append(Vector3(cos(a) * rr, 0.0, sin(a) * rr))
		rings.append({"p": ring, "a": fade})
	# Der Shader laeuft mit cull_disabled und setzt NORMAL selbst — die Wickelrichtung
	# ist egal. Innerster Ring als Faecher, alles weitere als Quads: ein einzelner
	# Randpunkt kann damit kein Loch bis zur Mitte mehr reissen.
	var c0: Dictionary = rings[1]
	var cp: PackedVector3Array = c0["p"]
	st.set_color(Color(1, 1, 1, 1))
	for i in LAKE_SEG:
		var b := cp[(i + 1) % LAKE_SEG]
		st.add_vertex(Vector3.ZERO); st.add_vertex(cp[i]); st.add_vertex(b)
	for j in range(1, LAKE_RINGS):
		var ri: Dictionary = rings[j]
		var ro: Dictionary = rings[j + 1]
		var pi: PackedVector3Array = ri["p"]
		var po: PackedVector3Array = ro["p"]
		var ai: float = ri["a"]
		var ao: float = ro["a"]
		for i in LAKE_SEG:
			var k := (i + 1) % LAKE_SEG
			st.set_color(Color(1, 1, 1, ai)); st.add_vertex(pi[i])
			st.set_color(Color(1, 1, 1, ao)); st.add_vertex(po[i])
			st.set_color(Color(1, 1, 1, ao)); st.add_vertex(po[k])
			st.set_color(Color(1, 1, 1, ai)); st.add_vertex(pi[i])
			st.set_color(Color(1, 1, 1, ao)); st.add_vertex(po[k])
			st.set_color(Color(1, 1, 1, ai)); st.add_vertex(pi[k])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = Vector3(lp.x, surf, lp.z)
	var wm := _water_mat(SEE)
	if geformt:
		# NUR DER BERGSEE. depth_fade 3.0 stammt aus der Zeit, als jedes Becken pauschal 4 m
		# tief war (surf - 4). Dieses hier ist bis 15 m tief, und mit 3 m Blendstrecke war
		# alles jenseits von 1,4 m Tiefe schon volles deep_col: der tuerkise Verlauf fand auf
		# den letzten Metern vor dem Ufer statt und war im Bild nur ein milchiger Ring ueber
		# dem hellen Kies. Mit 9 m spannt sich der Verlauf ueber den ganzen Uferschelf —
		# shallow bis mid liegt bei 0 bis 4 m Tiefe, das sind am flachen Ufer (Uferhang
		# 0.042) rund 95 m Breite, an der Felsflanke (0.30) 13 m. Der Saum wird dadurch von
		# selbst ungleich breit, ohne eine einzige neue Farbe.
		# Stadtsee und Canyonsee behalten 3.0 — sie sind weiter nur 4 m tief.
		wm.set_shader_parameter("depth_fade", 9.0)
		# UND DIE UNTIEFE MUSS FARBE HABEN. alpha_shallow 0.40 heisst: in den Untiefen sieht
		# man zu 60 % den Grund. Das ist am Meeresschelf richtig, hier war es der Grund fuer
		# den milchigen Ring — der Kies darunter ist die hellste Flaeche des Tals. Mit 0.68
		# steht ueber dem Schelf Wasser statt Dunst; der Kies scheint noch durch, gibt dem
		# Tuerkis aber nur seine Helligkeit und nicht mehr seine Farbe.
		wm.set_shader_parameter("alpha_shallow", 0.68)
		# Kraeftigeres Tuerkis fuer den Schelf und ein tiefes Petrol dahinter. Der alte
		# shallow_col (0.30/0.63/0.60) war ein Graugruen — auf 40 % Deckung blieb davon
		# nichts uebrig.
		wm.set_shader_parameter("shallow_col", Color(0.22, 0.74, 0.70))
		wm.set_shader_parameter("mid_col", Color(0.07, 0.52, 0.62))
	mi.material_override = wm
	add_child(mi)


# Wasser-Ribbon entlang der Fluss-Spline (einmal gebaut, festes Mesh).
func _build_river_water(rv: Dictionary) -> void:
	var pts: PackedVector3Array = rv["pts"]
	if pts.size() < 2:
		return
	var w: float = float(rv["w"]) * 0.92
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in pts.size():
		var dir: Vector3
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == pts.size() - 1:
			dir = pts[i] - pts[i - 1]
		else:
			dir = pts[i + 1] - pts[i - 1]
		dir.y = 0.0
		dir = dir.normalized()
		var perp := Vector3(-dir.z, 0.0, dir.x)
		var c := Vector3(pts[i].x, pts[i].y + 0.15, pts[i].z)
		left.append(c + perp * w)
		right.append(c - perp * w)
	var col := Color(0.20, 0.68, 0.72)
	for i in pts.size() - 1:
		st.set_color(col)
		st.add_vertex(left[i]); st.add_vertex(right[i]); st.add_vertex(right[i + 1])
		st.add_vertex(left[i]); st.add_vertex(right[i + 1]); st.add_vertex(left[i + 1])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _water_mat(FLUSS)   # derselbe Shader wie Meer und See
	add_child(mi)


# Gewaesser-Typen fuer _water_mat.
const MEER := 0
const SEE := 1
const FLUSS := 2

## EIN Wasser-Shader fuer alles. Unterschiede zwischen Meer, See und Fluss sind reine
## Parameter, keine zweite Optik: Binnengewaesser sind flacher (depth_fade), ruhiger
## (kleinere Wellen, langsamer) und haben einen schmaleren Ufersaum. Alle Wellenmasse
## stehen in WELTMETERN bzw. m/s — der Shader tastet die Weltposition ab, deshalb passen
## dieselben Zahlen auf die 9,1-km-Meeresplatte wie auf ein 30 m breites Flussband.
func _water_mat(typ: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	if typ == SEE:
		# 3,0 m statt 6,5: das Becken ist nur 4 m tief (surf-4 in height_at). Mit einem
		# Verlauf ueber 6,5 m blieb der ganze See in der hellen Uferfarbe stehen und sah
		# aus wie eine graue Pfuetze statt wie ein See.
		# GILT NUR NOCH FUER STADT- UND CANYONSEE. Der Bergsee hat einen gelappten Umriss
		# und bis 15 m Tiefe; _build_lake_water ueberschreibt depth_fade, alpha_shallow und
		# die beiden Wasserfarben fuer ihn (Begruendung dort).
		m.set_shader_parameter("depth_fade", 3.0)
		m.set_shader_parameter("foam_band", 0.5)
		m.set_shader_parameter("waterline", 0.20)
		m.set_shader_parameter("foam_strength", 0.22)
		m.set_shader_parameter("shallow_col", Color(0.30, 0.63, 0.60))
		# Kuerzere Wellen, kleinere Amplituden — aber die Geschwindigkeit bleibt die
		# Phasengeschwindigkeit sqrt(g*L/2pi) der jeweiligen Laenge. Ein ruhiger See hat
		# KURZE Wellen, keine langsamen.
		m.set_shader_parameter("swell_len", 12.0)
		m.set_shader_parameter("swell_amp", 0.075)
		m.set_shader_parameter("swell_speed", 4.33)
		m.set_shader_parameter("chop_len", 4.0)
		m.set_shader_parameter("chop_amp", 0.030)
		m.set_shader_parameter("chop_speed", 2.50)
		m.set_shader_parameter("ripple_len", 1.5)
		m.set_shader_parameter("ripple_amp", 0.011)
		m.set_shader_parameter("ripple_speed", 1.53)
		# Binnengewaesser sind KLAR: in den Untiefen soll der Grund durchscheinen, nicht
		# ein tuerkiser Deckel liegen. Am Meer bleibt es deckender (Schwebstoffe, Gischt).
		m.set_shader_parameter("alpha_shallow", 0.40)
		m.set_shader_parameter("alpha_deep", 0.85)
		m.set_shader_parameter("deep_col", Color(0.07, 0.27, 0.44))
		# Binnengewaesser sind nie 2,6 km weit weg -> keine Weltkanten-Angleichung.
		m.set_shader_parameter("far_start", 9000.0)
		m.set_shader_parameter("far_end", 9500.0)
	elif typ == FLUSS:
		m.set_shader_parameter("depth_fade", 3.2)
		m.set_shader_parameter("foam_band", 0.30)
		m.set_shader_parameter("waterline", 0.12)
		m.set_shader_parameter("foam_strength", 0.14)
		m.set_shader_parameter("shallow_col", Color(0.32, 0.62, 0.58))
		# Fliessendes Wasser: die Duenung entfaellt, dafuer laeuft feiner Chop schnell.
		# Phasengeschwindigkeit PLUS rund 1,5 m/s Stroemung — Flusswasser wird zusaetzlich
		# mitgetragen, deshalb laeuft das Muster hier schneller als auf dem See.
		m.set_shader_parameter("swell_len", 9.0)
		m.set_shader_parameter("swell_amp", 0.045)
		m.set_shader_parameter("swell_speed", 5.25)
		m.set_shader_parameter("chop_len", 3.5)
		m.set_shader_parameter("chop_amp", 0.030)
		m.set_shader_parameter("chop_speed", 3.84)
		m.set_shader_parameter("ripple_len", 1.3)
		m.set_shader_parameter("ripple_amp", 0.012)
		m.set_shader_parameter("ripple_speed", 2.93)
		m.set_shader_parameter("ripple_fade", 500.0)
		m.set_shader_parameter("alpha_shallow", 0.28)
		m.set_shader_parameter("alpha_deep", 0.80)
		m.set_shader_parameter("deep_col", Color(0.09, 0.32, 0.46))
		m.set_shader_parameter("far_start", 9000.0)
		m.set_shader_parameter("far_end", 9500.0)
	m.set_shader_parameter("sun_dir", sonne_richtung)
	_wasser_mats.append(m)
	return m


## Sonnenrichtung an ALLE Wasserflaechen durchreichen — Meer, Seen und Fluesse.
## Ohne das stand sun_dir auf dem Vorgabewert des Uniforms und das Wasser glitzerte in
## eine Richtung, die mit nichts sonst zusammenpasste: gemessen 64 Grad neben der
## gemalten Sonne UND neben der Schattenrichtung. Der Kommentar am Uniform ("wie
## sky_clouds.sun_dir") galt nur fuer die Vorgabewerte, nicht zur Laufzeit.
## Darf auch NACH dem Bauen gerufen werden — die Materialien sind gemerkt.
func setze_sonne(richtung: Vector3) -> void:
	sonne_richtung = richtung
	for m in _wasser_mats:
		m.set_shader_parameter("sun_dir", richtung)


func update_center(world_pos: Vector3) -> void:
	var t_k := Time.get_ticks_usec() if profil_an else 0
	_chunks_pflegen(world_pos)
	_pz("pflege", t_k)
	_last_pos = world_pos
	# Wasser folgt dem Spieler (riesige Platte, aber endlich). Das WELLENMUSTER folgt
	# NICHT mit: water.gdshader tastet die Weltposition des Fragments ab, nicht die UV
	# des Meshes. Frueher flog das ganze Muster mit dem Flugzeug mit und stand deshalb
	# relativ zum Spieler still. Diese Zeilen duerfen also verschieben, was sie wollen.
	_water.position.x = world_pos.x
	_water.position.z = world_pos.z
	var cc := Vector2i(int(floor(world_pos.x / CHUNK)), int(floor(world_pos.z / CHUNK)))
	if cc == _last_cc:
		return   # gleiche Zelle -> Lade-Plan unverändert (kein Scan pro Frame)
	_last_cc = cc
	var t_p := Time.get_ticks_usec() if profil_an else 0
	var r := int(ceil(VIEW_DIST / CHUNK))
	var want := {}
	var new_jobs: Array = []
	for cy in range(cc.y - r, cc.y + r + 1):
		for cx in range(cc.x - r, cc.x + r + 1):
			var key := Vector2i(cx, cy)
			if _chunk_center(key).distance_to(Vector2(world_pos.x, world_pos.z)) > VIEW_DIST + CHUNK:
				continue
			want[key] = true
			if not _chunks.has(key) and not _pending.has(key):
				_pending[key] = true
				new_jobs.append(key)
	# entfernte Chunks abbauen
	for key in _chunks.keys():
		if not want.has(key):
			_chunks[key].queue_free()
			_chunks.erase(key)
	if new_jobs.is_empty():
		_pz("plan", t_p)
		return
	# nahe zuerst bauen
	var pc := Vector2(world_pos.x, world_pos.z)
	new_jobs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_center(a).distance_squared_to(pc) < _chunk_center(b).distance_squared_to(pc))
	_mutex.lock()
	_jobs.append_array(new_jobs)
	_mutex.unlock()
	for i in new_jobs.size():
		_sem.post()
	_pz("plan", t_p)


func _chunk_center(key: Vector2i) -> Vector2:
	return Vector2((float(key.x) + 0.5) * CHUNK, (float(key.y) + 0.5) * CHUNK)


# Worker: rechnet Höhenfeld + Mesh + Kollisions-Shape (alles Resources, off-tree
# Thread-sicher). Der Main-Thread hängt nur noch ein.
func _worker_loop() -> void:
	while true:
		_sem.wait()
		if _exit:
			return
		_mutex.lock()
		var key_v: Variant = _jobs.pop_front() if not _jobs.is_empty() else null
		_mutex.unlock()
		if key_v == null:
			continue
		var key: Vector2i = key_v
		var data := _make_chunk_data(key)
		_mutex.lock()
		# WICHTIG: flora/rocks MUESSEN mit — sonst kommt die im Worker berechnete
		# Bepflanzung nie am Main-Thread an und die gestreamte Welt bleibt kahl
		# (nur build_now_around um den Spawn hatte je Baeume).
		_done.append({"key": key, "mesh": data["mesh"], "shape": data["shape"],
			"flora": data["flora"], "rocks": data["rocks"]})
		_mutex.unlock()


func _process(_delta: float) -> void:
	# fertige Chunks einhängen (billig: Nodes + fertige Resources)
	for i in MAX_ATTACH_PER_FRAME:
		_mutex.lock()
		var item_v: Variant = _done.pop_front() if not _done.is_empty() else null
		_mutex.unlock()
		if item_v == null:
			# BREAK, NICHT RETURN. Hier stand ein return, und das war der Grund, warum
			# Baeume verspaetet oder gar nicht kamen: der Ausstieg uebersprang das
			# _flora_nachziehen() am Ende der Funktion. Die Bepflanzung lief damit NUR in
			# Frames, in denen auch ein Chunk fertig geworden war — zwischen zwei Schueben
			# stand die Warteschlange still, und sobald der Spieler anhielt oder alle
			# Chunks geliefert waren, blieb sie fuer immer stehen.
			# Nachgewiesen mit tools/_flora_live.gd: mit return und drei Chunks je Frame
			# kamen 0 von 326 195 Pflanzen in der Szene an.
			break
		var item: Dictionary = item_v
		var key: Vector2i = item["key"]
		_pending.erase(key)
		# inzwischen außer Reichweite? -> verwerfen (wird bei Bedarf neu geplant)
		if _chunks.has(key) or _chunk_center(key).distance_to(Vector2(_last_pos.x, _last_pos.z)) > VIEW_DIST + CHUNK:
			continue
		var t_a := Time.get_ticks_usec() if profil_an else 0
		_attach_chunk(key, item["mesh"], item["shape"], item.get("flora", {}),
			item.get("rocks", []))
		_pz("attach", t_a)
	var t_n := Time.get_ticks_usec() if profil_an else 0
	_flora_nachziehen()
	_pz("flora_nachzug", t_n)


## Haengt aufgeschobene Flora nach, gedeckelt durch ein Zeitbudget statt durch eine feste
## Anzahl: die Arten unterscheiden sich um mehr als das Zehnfache in der Pflanzenzahl, ein
## Stueckzaehler wuerde also mal zu wenig und mal zu viel zulassen.
## Baut den Physikkoerper eines Chunks nach.
func _kollision_bauen(node: Node3D) -> void:
	if bool(node.get_meta("koll", false)) or not node.has_meta("shape"):
		return
	var body := StaticBody3D.new()
	body.name = "Kollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	# ACHTUNG, HIER LIEGT DER GANZE PREIS: diese eine Zuweisung kostete gemessen 174 von
	# 198 ms der ganzen Kollisionsarbeit, mit Spitzen ueber 7 ms. Godot baut den BVH der
	# Form erst hier, beim ersten Kontakt mit einem Koerper — nicht schon bei set_faces().
	# Deshalb KOLL_SCHRITT (weniger Dreiecke) und PFLEGE_BAU_PRO_FRAME (nicht mehrere
	# gleichzeitig). Wer hier etwas aendert, misst mit tools/_ruck_check.gd nach.
	cs.shape = node.get_meta("shape")
	body.add_child(cs)
	node.add_child(body)
	# Merker statt has_node(): die Pfadsuche lief frueher je Chunk und Frame.
	node.set_meta("koll", true)


## DER RUNDGANG. Haelt zwei Dinge am Abstand des Chunks zum Spieler fest:
##   * den Physikkoerper — nur der Nahbereich braucht einen (siehe KOLLISIONS_DIST),
##   * die Flora-Sparstufe — ab _flora_grob_ab genuegt die grobe Fassung.
## Beides hing frueher an je einer eigenen Schleife, die JEDEN Frame ueber ALLES lief.
## Die Begruendung fuer den Umbau und die Messwerte stehen bei PFLEGE_SCHEIBEN.
##
## Der Abstand wird EINMAL JE CHUNK bestimmt, nicht je Pflanze: alle MultiMeshes eines
## Chunks sitzen im selben Knoten und haben damit denselben Abstand. Das allein sind
## 364 Rechnungen statt bis zu 4000.
func _chunks_pflegen(mitte: Vector3) -> void:
	var m := Vector2(mitte.x, mitte.z)
	# Neue Runde? Dann die Schluesselliste einmal festhalten. Waehrend einer Runde darf
	# sich _chunks aendern — verschwundene Schluessel faengt die Pruefung unten ab.
	if _pflege_i >= _pflege_keys.size():
		_pflege_keys = _chunks.keys()
		_pflege_i = 0
	if _pflege_keys.is_empty():
		return
	var rest := maxi(1, int(ceil(float(_pflege_keys.size()) / float(PFLEGE_SCHEIBEN))))
	var gebaut := 0
	var gekippt := 0
	# Quadrate vergleichen spart je Chunk eine Wurzel.
	var koll_ein := KOLLISIONS_DIST * KOLLISIONS_DIST
	var koll_aus := (KOLLISIONS_DIST + KOLL_HYSTERESE) * (KOLLISIONS_DIST + KOLL_HYSTERESE)
	var grob_ein := (_flora_grob_ab + FLORA_HYSTERESE) * (_flora_grob_ab + FLORA_HYSTERESE)
	var grob_aus := _flora_grob_ab * _flora_grob_ab
	while rest > 0 and _pflege_i < _pflege_keys.size():
		var key: Vector2i = _pflege_keys[_pflege_i]
		_pflege_i += 1
		rest -= 1
		var roh: Variant = _chunks.get(key)
		# FALLE: erst pruefen, dann typisieren. Eine typisierte Zuweisung prueft beim
		# Zuweisen selbst auf ein lebendes Objekt und bricht bei einem abgeraeumten Knoten
		# mit "Trying to assign invalid previously freed instance" ab — der Abbruch beendet
		# die Schleife, und alles dahinter bliebe stehen.
		if roh == null or not is_instance_valid(roh):
			continue
		var node: Node3D = roh
		var d2 := _chunk_center(key).distance_squared_to(m)
		# --- Physikkoerper ---
		var hat: bool = node.get_meta("koll", false)
		if not hat:
			if d2 <= koll_ein and gebaut < PFLEGE_BAU_PRO_FRAME:
				var t_kb := Time.get_ticks_usec() if profil_an else 0
				_kollision_bauen(node)
				_pz("p_koll_bau", t_kb)
				gebaut += 1
		elif d2 > koll_aus:
			var kn := node.get_node_or_null("Kollision")
			if kn != null:
				kn.queue_free()
			node.set_meta("koll", false)
		# --- Flora-Sparstufe ---
		var liste: Array = node.get_meta("flora_mmis", [])
		if liste.is_empty():
			continue
		var fern: bool = node.get_meta("fern", false)
		var soll := fern
		if fern and d2 < grob_aus:
			soll = false
		elif not fern and d2 > grob_ein:
			soll = true
		if soll == fern:
			continue
		# DECKEL. Ein Sparstufenwechsel tauscht das Netz an rund sieben MultiMeshes und
		# kostet mit echtem Renderer 2,6 ms je Chunk; kippten drei Chunks im selben Frame,
		# waren es 7,7 ms. Headless kostet dasselbe 2 us — deshalb ist das lange
		# unentdeckt geblieben.
		if gekippt >= PFLEGE_STUFE_PRO_FRAME:
			continue
		gekippt += 1
		node.set_meta("fern", soll)
		var t_fl := Time.get_ticks_usec() if profil_an else 0
		for e in liste:
			var rmmi: Variant = e["mmi"]
			if not is_instance_valid(rmmi):
				continue
			var mm: MultiMesh = (rmmi as MultiMeshInstance3D).multimesh
			mm.mesh = e["grob"] if soll else e["voll"]
			mm.visible_instance_count = int(int(e["n"]) * FLORA_GROB_ANTEIL) if soll else -1
		_pz("p_flora_stufe", t_fl)


func _flora_nachziehen() -> void:
	if _flora_warteschlange.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var getan := 0
	while not _flora_warteschlange.is_empty():
		var e: Dictionary = _flora_warteschlange.pop_front()
		var n: Variant = e["node"]
		# Der Chunk kann laengst wieder abgebaut sein — dann faellt seine Flora weg.
		if is_instance_valid(n):
			_attach_multi(n, e["mesh"], e["xfs"])
			getan += 1
		# STUECKZAHL VOR ZEITBUDGET. Das Budget allein genuegt nicht: es wird NACH einem
		# Eintrag geprueft, und ein einzelner kostet mit echtem Renderer bis zu 3,7 ms
		# (das add_child der MultiMeshInstance beim RenderingServer, gemessen 898 us im
		# Mittel). Ein Frame konnte so 8,2 ms verschlucken, obwohl 1200 us erlaubt waren.
		# Zwei je Frame sind 120 je Sekunde — der Bedarf im Reiseflug liegt bei rund 63.
		if getan >= FLORA_PRO_FRAME or float(Time.get_ticks_usec() - t0) > FLORA_BUDGET_US:
			return


# Startbereich SOFORT bauen (synchron, Main-Thread), damit das Flugzeug beim
# Spawn nicht durch noch fehlende Kollision fällt.
## recenter=false: NUR bauen, ohne update_center (das erasen ferner Chunks + Wasser-Verschieben
## entfaellt) — fuer Render-Tools, die mehrere weit auseinanderliegende Gebiete brauchen.
## Im Spiel (Spawn) bleibt der Default true.
func build_now_around(world_pos: Vector3, radius: float, recenter := true) -> void:
	if recenter:
		update_center(world_pos)
	var r := int(ceil(radius / CHUNK)) + 1
	var cc := Vector2i(int(floor(world_pos.x / CHUNK)), int(floor(world_pos.z / CHUNK)))
	for cy in range(cc.y - r, cc.y + r + 1):
		for cx in range(cc.x - r, cc.x + r + 1):
			var key := Vector2i(cx, cy)
			if _chunks.has(key):
				continue
			if _chunk_center(key).distance_to(Vector2(world_pos.x, world_pos.z)) > radius + CHUNK:
				continue
			var data := _make_chunk_data(key)
			_attach_chunk(key, data["mesh"], data["shape"], data["flora"], data["rocks"])
	# HIER KEIN AUFSCHUB. _attach_chunk stellt die Flora nur in die Warteschlange, damit
	# der Ruck beim Nachladen im Flug verschwindet. Diese Funktion ist aber der
	# SYNCHRONE Weg — Spawnbereich und Renderwerkzeuge verlassen sich darauf, dass
	# hinterher wirklich alles steht. Ohne den Vollabbau stuenden Baeume erst Frames
	# spaeter, und jedes Abnahmebild waere um seine Vegetation betrogen.
	_flora_alles_nachziehen()


## Warteschlange in einem Zug leeren, ohne Zeitbudget.
func _flora_alles_nachziehen() -> void:
	while not _flora_warteschlange.is_empty():
		var e: Dictionary = _flora_warteschlange.pop_front()
		var n: Variant = e["node"]
		if is_instance_valid(n):
			_attach_multi(n, e["mesh"], e["xfs"])


func _attach_chunk(key: Vector2i, mesh: ArrayMesh, shape: Shape3D,
		flora: Dictionary = {}, rocks: Array = []) -> void:
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	node.add_child(mi)
	# Die Form wird am Knoten hinterlegt und der Koerper erst gebaut, wenn der Chunk nahe
	# genug ist (siehe _chunks_pflegen). Beim Spawn und in den Renderwerkzeugen ist der
	# Chunk ohnehin sofort nah, der Koerper entsteht also im selben Frame.
	node.set_meta("shape", shape)
	node.set_meta("key", key)
	var d := _chunk_center(key).distance_to(Vector2(_last_pos.x, _last_pos.z))
	# Sparstufe schon hier festlegen: ein frisch eingehaengter Chunk liegt fast immer am
	# Rand der Sichtweite, also jenseits von _flora_grob_ab. Ohne das stuende er bis zum
	# naechsten Rundgang in voller Aufloesung — und _attach_multi richtet sich danach.
	node.set_meta("fern", d > _flora_grob_ab)
	if d <= KOLLISIONS_DIST:
		var t_kb := Time.get_ticks_usec() if profil_an else 0
		_kollision_bauen(node)
		_pz("kollision_bau", t_kb)
	add_child(node)
	_chunks[key] = node
	# FLORA NICHT IM SELBEN FRAME. Gemessen kostet das Einhaengen eines Land-Chunks
	# 6,44 ms im Mittel und bis zu 9,58 ms — bei 16,7 ms Frame ist das der sichtbare Ruck
	# beim Nachladen. Davon entfallen 2,75 ms auf Netz und Kollisionskoerper und 3,7 ms
	# auf die rund 730 Pflanzen. Das Gelaende MUSS sofort stehen (sonst faellt das
	# Flugzeug hindurch), die Baeume nicht — die kommen ueber die naechsten Frames nach,
	# gedeckelt durch ein Zeitbudget. Sichtbar ist das nicht: ein frisch geladener Chunk
	# liegt am Rand der Sichtweite, wo die Flora ohnehin klein und ausgeblendet ist.
	for art in flora.keys():
		_flora_warteschlange.append({"node": node, "mesh": _flora.get(art, _mesh_conifer),
			"xfs": flora[art]})
	if not rocks.is_empty():
		_flora_warteschlange.append({"node": node, "mesh": _mesh_rock, "xfs": rocks})


## Baumweite umschalten: 0 = nah, 1 = normal, 2 = weit. Wirkt sofort auf alle vorhandenen
## Flora-MultiMeshes und auf alle, die danach entstehen.
## Laeuft aus dem Einstellungsmenue, also einmal — hier darf der volle Durchlauf sein.
func setze_baumweite(stufe: int) -> void:
	match clampi(stufe, 0, 2):
		0:
			_flora_dist = FLORA_DIST * 0.55
			_flora_grob_ab = FLORA_GROB_AB * 0.55
		2:
			_flora_dist = FLORA_DIST * 1.35
			_flora_grob_ab = FLORA_GROB_AB * 1.35
		_:
			_flora_dist = FLORA_DIST
			_flora_grob_ab = FLORA_GROB_AB
	var m := Vector2(_last_pos.x, _last_pos.z)
	for key in _chunks:
		var roh: Variant = _chunks.get(key)
		if roh == null or not is_instance_valid(roh):
			continue
		var node: Node3D = roh
		var liste: Array = node.get_meta("flora_mmis", [])
		if liste.is_empty():
			continue
		# Der Grenzabstand hat sich verschoben — Stufe hier direkt neu setzen, statt auf
		# den naechsten Rundgang zu warten.
		var fern := _chunk_center(key).distance_to(m) > _flora_grob_ab
		node.set_meta("fern", fern)
		for e in liste:
			var rmmi: Variant = e["mmi"]
			if not is_instance_valid(rmmi):
				continue
			var mmi: MultiMeshInstance3D = rmmi
			mmi.visibility_range_end = _flora_dist
			var mm: MultiMesh = mmi.multimesh
			mm.mesh = e["grob"] if fern else e["voll"]
			mm.visible_instance_count = int(int(e["n"]) * FLORA_GROB_ANTEIL) if fern else -1


## Wandelt eine Liste von Transformationen in den Rohpuffer einer MultiMesh um.
## TRANSFORM_3D erwartet je Instanz ZWOELF Fliesskommazahlen: die Basis zeilenweise,
## jede Zeile gefolgt vom zugehoerigen Verschiebungsanteil.
static func _xf_puffer(xfs: Array, huelle: Array = []) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(xfs.size() * 12)
	var k := 0
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for xf: Transform3D in xfs:
		lo = lo.min(xf.origin)
		hi = hi.max(xf.origin)
		var b := xf.basis
		var o := xf.origin
		buf[k] = b.x.x; buf[k+1] = b.y.x; buf[k+2] = b.z.x; buf[k+3] = o.x
		buf[k+4] = b.x.y; buf[k+5] = b.y.y; buf[k+6] = b.z.y; buf[k+7] = o.y
		buf[k+8] = b.x.z; buf[k+9] = b.y.z; buf[k+10] = b.z.z; buf[k+11] = o.z
		k += 12
	if not huelle.is_empty():
		huelle[0] = lo
		huelle[1] = hi
	return buf


func _attach_multi(parent: Node3D, mesh: Mesh, xfs: Array) -> void:
	if xfs.is_empty() or mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	# EIN Aufruf statt einer je Pflanze. set_instance_transform() geht jedes Mal ueber die
	# Skript-Grenze in den RenderingServer; bei rund 590 Pflanzen je Chunk waren das 590
	# Einzelaufrufe im selben Frame, in dem der Chunk eingehaengt wird — genau der Frame,
	# in dem ohnehin schon der Physikkoerper eingefuegt wird. set_buffer() uebergibt
	# stattdessen den fertigen Rohpuffer am Stueck.
	var huelle := [Vector3.ZERO, Vector3.ZERO]
	mm.set_buffer(_xf_puffer(xfs, huelle))
	# EIGENE HUELLBOX SETZEN. Ohne sie rechnet Godot die Box beim Einhaengen und bei
	# JEDEM Netzwechsel ueber alle Instanzen neu — gemessen mit echtem Renderer kostete
	# das Einhaengen einer Flora-MultiMesh bis zu 13,7 ms und ein Sparstufenwechsel je
	# Chunk 3,8 ms. Headless faellt das nicht auf; dort ist es hundertmal billiger.
	# Die Box hier ist gratis: die Schleife in _xf_puffer laeuft ohnehin ueber alle
	# Transformationen. Grosszuegig aufgeweitet um die Groesse einer Pflanze.
	var lo: Vector3 = huelle[0] - Vector3(6.0, 1.0, 6.0)
	var hi: Vector3 = huelle[1] + Vector3(6.0, 14.0, 6.0)
	mm.custom_aabb = AABB(lo, hi - lo)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _flora_mat
	# Harter Schnitt erst dort, wo der Shader die Instanzen laengst auf Groesse 0
	# gefahren hat (FLORA_FADE_END + halbe Chunk-Diagonale) -> nichts poppt.
	mmi.visibility_range_end = _flora_dist
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	parent.add_child(mmi)
	# Fuer _chunks_pflegen merken. Die grobe Fassung wird je Quellmesh EINMAL gebaut und
	# dann von allen Chunks geteilt.
	if not _grob_cache.has(mesh):
		_grob_cache[mesh] = _grobe_fassung(mesh)
	# AM CHUNK-KNOTEN, nicht in einer globalen Liste. Damit gilt der Abstand des Chunks
	# fuer alle seine MultiMeshes gemeinsam (siehe _chunks_pflegen), und abgeraeumte
	# Eintraege koennen sich gar nicht erst ansammeln: mit dem Chunk geht auch seine
	# Liste. Die frueher globale Liste musste bei 4000 Eintraegen durchgefiltert werden.
	var liste: Array = parent.get_meta("flora_mmis", [])
	liste.append({"mmi": mmi, "voll": mesh, "grob": _grob_cache[mesh], "n": xfs.size()})
	parent.set_meta("flora_mmis", liste)
	# Neu eingehaengte MultiMeshes uebernehmen die Stufe, die der Chunk schon hat —
	# sonst stuende ein ferner Chunk kurz in voller Aufloesung da.
	if bool(parent.get_meta("fern", false)):
		mm.mesh = _grob_cache[mesh]
		mm.visible_instance_count = int(xfs.size() * FLORA_GROB_ANTEIL)


# Mesh + Kollision für einen Chunk bauen (läuft im Worker ODER synchron beim Spawn).
## WALDANTEIL AN EINEM PUNKT, 0 bis 1 — dieselbe Regel, nach der auch die echten Baeume
## gesetzt werden (Waldrauschen, Baumgrenze, Hangneigung, Biom, freigehaltene Flaechen).
##
## WOFUER: echte Baeume gibt es nur in den gestreamten Chunks, also 3,8 km um den Spieler.
## Alles darueber hinaus traegt die Fernschuerze, und die hatte gar keinen Bewuchs — der
## Wald wanderte deshalb mit dem Spieler mit und die Insel lag jenseits davon kahl da.
## Zehntausende Chunks bis 20 km zu streamen kommt nicht in Frage. Stattdessen faerbt die
## Schuerze ihre Dreiecke nach diesem Wert ein: aus der Entfernung, aus der man sie
## ueberhaupt sieht, ist ein Wald ohnehin nur eine dunkelgruene Flaeche. Das kostet KEIN
## einziges zusaetzliches Dreieck und keinen Zeichenaufruf.
func wald_anteil(x: float, z: float, h: float, ny: float) -> float:
	if h < FLORA_MIN_H or h > FLORA_MAX_H:
		return 0.0
	# ny ist der Aufwaerts-Anteil der Flaechennormale; daraus die Neigung wie im Chunk.
	var slope := (1.0 - clampf(ny, 0.0, 1.0)) * 12.0
	var edge := _open_ground(x, z) \
		* vulkan_bewuchs(x, z, h) \
		* smoothstep(FLORA_MIN_H, FLORA_FULL_H, h) \
		* (1.0 - smoothstep(46.0, FLORA_MAX_H, h)) \
		* (1.0 - smoothstep(2.8, 4.6, slope))
	if edge <= 0.005:
		return 0.0
	var dens := smoothstep(-0.28, 0.30, _forest.get_noise_2d(x, z))
	dens = dens * dens
	match biome_at(x, z):
		Biome.HEIDE:
			dens *= 0.30
		Biome.WUESTE:
			dens *= 0.05
	# DER WALDKRAGEN DES VULKANS HEBT DIE DICHTE AUF EINEN SOCKEL, und zwar NACH der
	# Biomausduennung — er soll den Ring auch im Wuestensektor schliessen (Begruendung bei
	# vulkan_kragen). Ausserhalb des Kegels liefert die Funktion null, die Zeile ist dort
	# also ein maxf gegen null und das Ergebnis bitgenau das bisherige.
	dens = maxf(dens, vulkan_kragen(x, z, h))
	return clampf(dens * edge, 0.0, 1.0)


func _make_chunk_data(key: Vector2i) -> Dictionary:
	var ox := float(key.x) * CHUNK
	var oz := float(key.y) * CHUNK
	var step := CHUNK / float(CELLS)
	var hs := PackedFloat32Array()
	hs.resize((CELLS + 1) * (CELLS + 1))
	for j in CELLS + 1:
		for i in CELLS + 1:
			hs[j * (CELLS + 1) + i] = height_at(ox + float(i) * step, oz + float(j) * step)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # FLAT shading (Low-Poly-Facetten)
	for j in CELLS:
		for i in CELLS:
			var x0 := ox + float(i) * step
			var z0 := oz + float(j) * step
			var h00 := hs[j * (CELLS + 1) + i]
			var h10 := hs[j * (CELLS + 1) + i + 1]
			var h01 := hs[(j + 1) * (CELLS + 1) + i]
			var h11 := hs[(j + 1) * (CELLS + 1) + i + 1]
			var v00 := Vector3(x0, h00, z0)
			var v10 := Vector3(x0 + step, h10, z0)
			var v01 := Vector3(x0, h01, z0 + step)
			var v11 := Vector3(x0 + step, h11, z0 + step)
			# Godot-Front = im Uhrzeigersinn von außen: Wicklung so, dass die
			# Flächen nach OBEN zeigen (sonst cullt alles bei Sicht von oben)
			_tri(st, v00, v10, v11)
			_tri(st, v00, v11, v01)
	st.generate_normals()
	var mesh := st.commit()
	# --- FLORA: deterministisch aus Seed+Chunk — Bäume in Wald-Clustern, Felsen
	# verstreut. Nur Transforms berechnen (Worker); MultiMesh baut der Main-Thread.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, seed_value))
	# ARTENWAHL: nicht mehr nur Nadel/Laub, sondern sieben Arten nach Biom und HOEHE —
	# Tiefland Laubwald mit Unterholz, Mittellage Nadelmischwald, ab 42 m Bergfichten mit
	# einzelnen abgestorbenen Staemmen, Wueste Palmenoasen mit Trockenbewuchs. Dadurch
	# wiederholt sich aus der Luft kein Muster.
	var flora: Dictionary = {}      # Art -> Array[Transform3D]
	var rocks: Array = []
	# DICHTE: frueher 150 Zufallsproben je Chunk (147 000 m^2) — nach allen Filtern blieben
	# 14 Baeume uebrig, also einer je 100 m Abstand. Aus der Luft war das eine kahle Wiese.
	# Jetzt wird jede Zelle des OHNEHIN BERECHNETEN Hoehenrasters besetzt: kein einziger
	# zusaetzlicher height_at-Aufruf (der teure Teil: fBm + Ridge + Massive + Fluesse), und
	# die Baeume stehen exakt auf der facettierten Flaeche statt auf der glatten Kurve
	# darunter — mit height_at gesampelt schwebten sie auf Graten und steckten in Mulden.
	var river_chunk := false
	for rv in rivers:
		if ox + CHUNK > rv["minx"] and ox < rv["maxx"] and oz + CHUNK > rv["minz"] and oz < rv["maxz"]:
			river_chunk = true
			break
	for j in CELLS:
		for i in CELLS:
			var h00 := hs[j * (CELLS + 1) + i]
			var h10 := hs[j * (CELLS + 1) + i + 1]
			var h01 := hs[(j + 1) * (CELLS + 1) + i]
			var h11 := hs[(j + 1) * (CELLS + 1) + i + 1]
			var hc := (h00 + h10 + h01 + h11) * 0.25
			if hc < SEA_Y + 1.0:
				continue
			# Steilheit als Hoehenunterschied ueber die 8-m-Zelle (aus dem Raster, gratis)
			var slope := maxf(maxf(absf(h10 - h00), absf(h01 - h00)),
				maxf(absf(h11 - h10), absf(h11 - h01)))
			var cx := ox + (float(i) + 0.5) * step
			var cz := oz + (float(j) + 0.5) * step
			# Eingeebnete Flugplaetze/Plateaus bleiben frei — frueher besorgte das die
			# Hoehenschwelle nebenbei, jetzt explizit (siehe FLORA_MIN_H).
			# AM VULKAN WAECHST WEDER AUF DEM ERSTARRTEN STROM NOCH OBERHALB SEINER
			# BAUMGRENZE ETWAS (vulkan_bewuchs). Der Strom ist dieselbe Maske, mit der
			# _face_color das schwarze Band ueber die gruene Ebene legt: ohne sie stuende der
			# Wald mitten darauf — genau der Widerspruch zwischen Farbe und Bewuchs, der beim
			# Blockschutt am Felsentor schon einmal der Befund war. Die Baumgrenze wiederum
			# ist die des KEGELS und nicht die der Welt, die bei 230 m auf einem Drittel
			# dieser Flanke saesse.
			var open := _open_ground(cx, cz) * vulkan_bewuchs(cx, cz, hc)
			if open <= 0.01:
				continue
			# FELSEN: unabhaengig vom Wald, bevorzugt an Haengen und in Hochlagen.
			# Auch oberhalb der Baumgrenze (dort tragen sie die Bergsilhouette).
			if rng.randf() < open * (0.004 + clampf(slope * 0.012, 0.0, 0.05)
					+ (0.02 if hc > 45.0 else 0.0)):
				var rsc := Vector3(rng.randf_range(0.7, 2.6), rng.randf_range(0.5, 1.9),
					rng.randf_range(0.7, 2.6))
				rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(rsc),
					Vector3(cx + rng.randf_range(-3.0, 3.0), hc - 0.3,
						cz + rng.randf_range(-3.0, 3.0))))
			# --- BEWUCHS ---
			if hc < FLORA_MIN_H or hc > FLORA_MAX_H:
				continue   # Strand/Wasser bzw. ueber der Baumgrenze
			# DIE SCHRANKE MUSS DEN HOECHSTEN SEE KENNEN. Hier stand fest "hc < 34.0", und
			# der Bergsee liegt auf 78 m: seine Wanne fiel komplett durch die Pruefung, und
			# sobald seine Flachzone weg war (die als Freihaltezone alles unterdrueckt hat),
			# stand im Bild ein geschlossener Nadelwald IM See. Fuer die Fluesse bleibt es
			# bei 34 m — ihre Splines reichen bis 112 m hinauf, und ein Bachbett muss keine
			# Baumsperre ueber das halbe Bergland ziehen.
			if hc < _flora_wasser_h and _submerged(cx, cz, hc, river_chunk and hc < 34.0):
				continue   # See- und Flussbett: nicht unter Wasser pflanzen
			# Weiche Raender statt harter Schwellen — der frueher harte Schnitt bei
			# h=0.8 / h=64 / Hang 2.6 zeichnete aus der Luft sichtbare Kanten.
			var edge := open * smoothstep(FLORA_MIN_H, FLORA_FULL_H, hc) \
				* (1.0 - smoothstep(46.0, FLORA_MAX_H, hc)) \
				* (1.0 - smoothstep(2.8, 4.6, slope))
			if edge <= 0.005:
				continue
			var biome := biome_at(cx, cz)
			# DER WALDKRAGEN DES VULKANS, und er steht GANZ OBEN, weil er alles darunter
			# betrifft (Begruendung bei vulkan_kragen). Ausserhalb des Kegels ist er null und
			# jede Zeile darunter bleibt exakt die bisherige.
			# IM KRAGEN GILT DAS BIOM NICHT. Das ist keine Bequemlichkeit, sondern die
			# eigentliche Reparatur: gemessen sind 17 von 64 Fussrichtungen WUESTE, und die
			# Weltregel laesst dort ein Zwanzigstel der Dichte stehen, sperrt alles ueber 28 m
			# UND pflanzt Palmen. In diesen Sektoren fehlte der Kragen deshalb vollstaendig —
			# das waren die 7 von 32 Richtungen ganz ohne Wald. Auf einem Aschekegel mit
			# Steigungsregen ist ein geschlossener Nadelwaldguertel ohnehin das Naheliegende,
			# und die Vorlage zeigt genau ihn.
			var kragen := vulkan_kragen(cx, cz, hc)
			if kragen > 0.01:
				biome = Biome.WALD
			var f := _forest.get_noise_2d(cx, cz)
			# Waldkern dicht, Rand ausduennend, echte Lichtungen unter f = -0.28.
			var dens := smoothstep(-0.28, 0.30, f)
			dens = dens * dens
			dens = maxf(dens, kragen)
			var per_cell := FLORA_PER_CELL
			if biome == Biome.HEIDE:
				per_cell *= 0.30   # offene Heide -> Strauchwerk und einzelne Baeume
			elif biome == Biome.WUESTE:
				if hc > 28.0:
					continue
				per_cell *= 0.05   # Wueste: nur Oasen-Tupfer im Rauschen-Hoch
			var expect := per_cell * dens * edge
			var n := int(floor(expect))
			if rng.randf() < expect - float(n):
				n += 1
			for k in n:
				var u := rng.randf()
				var v := rng.randf()
				# Hoehe auf der TATSAECHLICHEN Dreiecksflaeche (Diagonale v00-v11 wie
				# oben trianguliert), damit kein Stamm in der Facette haengt.
				var hp := (h00 + u * (h10 - h00) + v * (h11 - h10)) if u >= v \
					else (h00 + v * (h01 - h00) + u * (h11 - h01))
				var art := ""
				var lo := 1.1
				var hi := 2.0
				if biome == Biome.WUESTE:
					var w := rng.randf()
					if w < 0.34:
						art = "Palme"
						lo = 1.0
						hi = 1.7
					elif w < 0.52:
						art = "Totholz"
						lo = 0.9
						hi = 1.5
					else:
						art = "Busch"
						lo = 0.8
						hi = 1.8
				else:
					var r := rng.randf()
					if hp > 42.0:
						art = "Fichte" if r < 0.86 else "Totholz"
					elif hp > 24.0:
						if r < 0.50:
							art = "Fichte"
						elif r < 0.82:
							art = "Kiefer"
						else:
							art = "Birke"
					else:
						if r < 0.26:
							art = "Eiche"
						elif r < 0.50:
							art = "Birke"
						elif r < 0.70:
							art = "Fichte"
						elif r < 0.80:
							art = "Kiefer"
						else:
							art = "Busch"
					if biome == Biome.HEIDE and rng.randf() < 0.45:
						art = "Busch"   # offene Heide ist vor allem Strauchwerk
					if art == "Busch":
						lo = 0.8
						hi = 1.8
				var sc := rng.randf_range(lo, hi)
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(
					Vector3(sc, sc * rng.randf_range(0.9, 1.25), sc)),
					Vector3(ox + (float(i) + u) * step, hp - 0.15,
						oz + (float(j) + v) * step))
				if not flora.has(art):
					flora[art] = []
				flora[art].append(xf)
	# KOLLISION: WEITER ALS DREIECKSNETZ — HeightMapShape3D wurde geprueft und ist hier
	# LANGSAMER. Die Idee lag nahe (hs ist genau das 49x49-Raster, aus dem auch das Netz
	# entsteht, ein Hoehenfeld braucht keinen BVH), aber gemessen stieg das Einhaengen von
	# 3,40 auf 7,01 ms im Mittel und die Spitze von 10,92 auf 32,84 ms. Der Grund duerfte
	# die noetige nicht-uniforme Skalierung sein: HeightMapShape3D rechnet in ZELLEN, eine
	# Zelle ist eine Einheit, also muss die Form um die Rasterweite 8 gestreckt werden —
	# und Godot baut sie dabei offenbar neu auf. Wer es erneut versucht, misst zuerst.
	# Der grosse Hebel liegt ohnehin woanders, siehe KOLLISIONS_DIST.
	#
	# NIEMALS mesh.create_trimesh_shape() — das stand hier und war die schlimmste Bremse
	# im ganzen Streaming. Godot baut die Form dort nicht aus dem, was im Speicher liegt,
	# sondern ruft Mesh::generate_triangle_mesh() -> RenderingServer.mesh_surface_get_arrays().
	# Das ist ein SYNCHRONER RUECKRUF IN DEN RENDERER: der Worker-Thread stellt den Befehl in
	# die Renderer-Warteschlange und legt sich schlafen, bis der Renderer die Netzdaten
	# zurueckgibt — je Chunk einmal, mit einem Rueckweg der 13 824 Eckpunkte aus dem
	# Grafikspeicher holt. Belegt mit einem Stack-Sample: der Worker hing in
	# Mesh::create_trimesh_shape -> mesh_surface_get_arrays -> condition_variable::wait.
	# Zwei Folgen hatte das:
	#   1. RUCK. Der Renderer muss dafuer die Pipeline einholen, mitten im Bild.
	#   2. DEADLOCK BEIM BEENDEN. _exit_tree wartet auf den Worker (wait_to_finish), der
	#      Worker wartet auf den Renderer, den nur der Main-Thread bedient — und der steht
	#      im wait_to_finish. Der Prozess blieb dann fuer immer haengen.
	# Die Eckpunkte liegen ohnehin schon vor, sie werden oben beim Netzbau mitgeschrieben.
	# ConcavePolygonShape3D.set_faces() geht direkt an die Physik und fasst den Renderer
	# nicht an.
	# KOLLISIONSFLAECHE aus DEMSELBEN Hoehenraster, aber nur jedem KOLL_SCHRITT-ten Punkt.
	# Eigene Schleife statt im Netzbau mitgeschrieben, weil die Weite eine andere ist.
	# Ganzzahlig gewollt: 48 / 2 = 24 geht glatt auf. Wer KOLL_SCHRITT aendert, waehlt
	# einen Teiler von CELLS — sonst bliebe am Chunkrand ein Streifen ohne Kollision.
	@warning_ignore("integer_division")
	var kc := CELLS / KOLL_SCHRITT
	var kstep := step * float(KOLL_SCHRITT)
	var faces := PackedVector3Array()
	faces.resize(kc * kc * 6)
	var fi := 0
	for j in kc:
		for i in kc:
			var gi := i * KOLL_SCHRITT
			var gj := j * KOLL_SCHRITT
			var x0 := ox + float(gi) * step
			var z0 := oz + float(gj) * step
			var k00 := hs[gj * (CELLS + 1) + gi]
			var k10 := hs[gj * (CELLS + 1) + gi + KOLL_SCHRITT]
			var k01 := hs[(gj + KOLL_SCHRITT) * (CELLS + 1) + gi]
			var k11 := hs[(gj + KOLL_SCHRITT) * (CELLS + 1) + gi + KOLL_SCHRITT]
			var p00 := Vector3(x0, k00, z0)
			var p10 := Vector3(x0 + kstep, k10, z0)
			var p01 := Vector3(x0, k01, z0 + kstep)
			var p11 := Vector3(x0 + kstep, k11, z0 + kstep)
			# Gleiche Wicklung und gleiche Diagonale wie im Sichtnetz.
			faces[fi] = p00; faces[fi + 1] = p10; faces[fi + 2] = p11
			faces[fi + 3] = p00; faces[fi + 4] = p11; faces[fi + 5] = p01
			fi += 6
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return {"mesh": mesh, "shape": shape, "flora": flora, "rocks": rocks}


## Wie frei ist die Stelle fuer Bewuchs? 0 = eingeebneter Flugplatz/Plateau (auf der
## Piste waechst nichts, und dort stehen auch keine Felsbrocken), 1 = normales Gelaende.
## Muss explizit sein: die alte Hoehenschwelle h > 0.8 hat das nebenbei miterledigt,
## dafuer aber das halbe flache Tiefland gleich mit ausgesperrt.
## FLUGPLAETZE RECHNEN SEIT DIESER RUNDE MIT RECHTECKEN. Vorher galt auch fuer sie der
## Kreis unten: rf = min(r_flat, CLEAR_CAP) = 620 m, wieder voll ab rb = rf * 1.85 =
## 1147 m. Bei 900 m Bahnlaenge heisst das 170 m ueber das Bahnende und rund 600 m
## seitlich KEIN Baum, kein Busch, kein Stein — im Ueberflug lag der Platz in einer
## leeren Halo-Scheibe, waehrend heimat_1 und heimat_4 Nadelwald bis 20-40 m an die
## Bahnkante und Felsbrocken direkt am Bahnrand zeigen. Ein Kreis kann das nicht: er
## muss den Umkreis der 900-m-Bahn abdecken und raeumt damit zwangslaeufig auch quer
## dazu 450 m ab, wo gar nichts steht.
## Jetzt: Abstand zum RAND der bebauten Rechtecke (Bahn, Rollweg/Vorfeld, bei den
## Aussenfeldern zusaetzlich die Blender-Bauten). Kreise bleiben fuer Stadt, Dorf,
## Leuchtturm & Co. — die sind rund, dort war der Kreis nie das Problem.
## SCHUTTHALDEN HAENGEN SEIT DIESER RUNDE HIER MIT DRIN und nicht in einer eigenen
## Sperre: die Frage "waechst hier etwas" ist dieselbe, und _open_ground sperrt schon
## heute Baeume UND Felsbrocken in einem Zug. Auf einer Blockhalde steht kein Grashalm —
## gemessen waren es bei uns 63 Prozent Gruen im Fussbereich des Felsentors gegen
## 5.7 Prozent im Referenzbild.
func _open_ground(x: float, z: float) -> float:
	var k := _halde_frei(x, z)
	if k <= 0.0:
		return 0.0
	for af in airfields:
		var ap: Vector3 = af["pos"]
		var dx := x - ap.x
		var dz := z - ap.z
		# Quadrat-Vergleich zuerst: _face_color ruft das je DREIECK (4608 pro Chunk)
		# ueber alle zwoelf Zonen auf — fast immer liegt die Stelle draussen, und
		# dieser Zweig kostet dann weder Wurzel noch smoothstep.
		var d2 := dx * dx + dz * dz
		if af.has("rects"):
			var rmax: float = af["_rmax"]
			if d2 >= rmax * rmax:
				continue
			# In Platz-Koordinaten drehen (Bahn laeuft dort laengs Z). cos/sin sind in
			# setup() vorberechnet.
			var co: float = af["_cos"]
			var si: float = af["_sin"]
			var lx := co * dx - si * dz
			var lz := si * dx + co * dz
			var nah := 1.0e9
			for r in af["rects"]:
				# Abstand Punkt->Rechteck: Ueberstand je Achse, negativ = innerhalb.
				var qx: float = absf(lx - float(r[0])) - float(r[2])
				var qz: float = absf(lz - float(r[1])) - float(r[3])
				if qx <= 0.0 and qz <= 0.0:
					nah = 0.0
					break
				var ex := maxf(qx, 0.0)
				var ez := maxf(qz, 0.0)
				nah = minf(nah, sqrt(ex * ex + ez * ez))
			k = minf(k, smoothstep(FREI_INNEN, FREI_AUSSEN, nah))
		else:
			var rf := minf(float(af["r_flat"]), CLEAR_CAP)
			var rb := minf(float(af["r_blend"]), rf * 1.85)
			if d2 >= rb * rb:
				continue
			k = minf(k, smoothstep(rf, rb, sqrt(d2)))
		if k <= 0.0:
			break
	return k


## Steht an dieser Stelle Wasser ueber dem Boden? Meer deckt height_at schon ab, aber
## Inlandsee-Becken und Flussbetten liegen UEBER 0.8 m — ohne diese Pruefung waechst
## bei der neuen Dichte sichtbar Wald auf dem Seegrund.
## Der Fluss-Teil laeuft nur, wenn ueberhaupt eine Spline-AABB den Chunk schneidet.
func _submerged(x: float, z: float, h: float, check_rivers: bool) -> bool:
	for lk in lakes:
		var lp: Vector3 = lk["pos"]
		# _rmax statt r beim gelappten Bergsee: sein Arm reicht weit ueber r hinaus, und
		# mit dem alten Kreis waere dort Wald auf dem Seegrund gewachsen.
		var rr: float = float(lk.get("_rmax", lk["r"]))
		if Vector2(x - lp.x, z - lp.z).length() < rr and h < float(lk["surf"]) + 0.8:
			return true
	if not check_rivers:
		return false
	for rv in rivers:
		if x < rv["minx"] or x > rv["maxx"] or z < rv["minz"] or z > rv["maxz"]:
			continue
		var pts: PackedVector3Array = rv["pts"]
		var lim: float = float(rv["w"]) * 1.4
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var dx := b.x - a.x
			var dz := b.z - a.z
			var l2 := dx * dx + dz * dz
			var t := 0.0 if l2 < 1e-6 else clampf(((x - a.x) * dx + (z - a.z) * dz) / l2, 0.0, 1.0)
			var px := a.x + dx * t
			var pz := a.z + dz * t
			if (x - px) * (x - px) + (z - pz) * (z - pz) < lim * lim \
					and h < lerpf(a.y, b.y, t) + 0.8:
				return true
	return false


# Ein Dreieck mit Flächenfarbe (aus Höhe + Steilheit am Schwerpunkt) einfügen.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	var cen := (a + b + c) / 3.0
	# |n.y|: die geometrische Normale zeigt je nach Wicklung nach unten —
	# für die Steilheits-Farbe zählt nur der Winkel zur Senkrechten.
	st.set_color(_face_color(cen, absf(n.y)))
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


# --- ALMWIESE IM HOCHTAL ---------------------------------------------------------------
# Der Fels beginnt weltweit bei 45 bis 59 m Hoehe. Der Boden des Hochtals liegt gemessen
# auf 41 bis 235 m, der Bergsee mit seinem Spiegel auf 78 m — das ganze Tal steht also
# MITTEN IM FELSBAND und war beige. Im Bild war das eine Schotterpfanne, in der Baeume
# standen: die Bepflanzung waechst bis 230 m (FLORA_MAX_H), der Boden unter ihr war ab
# 59 m Fels. Genau dieser Widerspruch ist der Unterschied zum Referenzbild, auf dem der
# Talboden von der Wasserlinie bis an den Wandfuss gruen ist.
#
# VORIGE FASSUNG UND WARUM SIE FALSCH WAR: die Felsschwelle wanderte um SEE_WIESE_HUB
# nach oben, gemessen am Abstand zur UFERLINIE DES SEES. Damit war das Gruen per
# Konstruktion eine Kreisscheibe um den See, und das Rauschen auf der Grenze machte daraus
# nur ein ausgefranstes Halsband. Gemessen (tools/_krit_seering.gd) reichte es im Mittel
# 146 m hinter das Ufer, und 700 m dahinter lag Gelaende auf 71 m — SIEBEN METER UNTER dem
# Seespiegel — in Felsfarbe. Ein flacher Talboden, tiefer als der See, und trotzdem
# Geroell, nur weil er ausserhalb eines Radius lag.
#
# JETZT: die Schwelle haengt an der LAGE IM TALKORRIDOR (Achse aus Main, TAL_START /
# TAL_RICHTUNG) und an der HOEHE UEBER DEM GEMESSENEN TALBODEN (_tal_boden). Alles im
# Korridor bis TAL_WIESE_VOLL ueber dem Talboden bekommt den vollen Hub, bis
# TAL_WIESE_AUS laeuft er auf null. Der See spielt dabei gar keine Rolle mehr.
# Wo das Gruen endet, entscheidet damit das GELAENDE: an der Flanke steigt es rasch aus
# dem Band heraus, und dort uebernimmt ohnehin das Steilheitskriterium (ny) — der Saum
# liegt am Wandfuss, wie im Referenzbild, und folgt jeder Rinne und jedem Sporn.
#
# DIE ZAHLEN: 150 m Hub schiebt die Schwelle von 45..59 auf 195..209 m. Zusammen mit der
# Ausblendung liegt die Gruengrenze rund 110 bis 120 m ueber dem Talboden, also bei etwa
# 190 m Hoehe — genau dort, wo auch die Bepflanzung duenn wird (46 m an, 230 m aus). Ueber
# der Grenze faengt der Schnee erst bei 188 m an einzublenden und ist bei 195 m mit 0.01
# unsichtbar; es entsteht also kein weisser Saum.
const TAL_WIESE_HUB := 150.0
const TAL_WIESE_VOLL := 60.0     # bis so viel ueber dem Talboden gilt der volle Hub
const TAL_WIESE_AUS := 300.0     # ab so viel ueber dem Talboden ist er weg
# ZWISCHEN VOLL UND AUS LIEGEN 240 M, UND DAS IST KEINE BEQUEMLICHKEIT. Der Hub faellt mit
# der Hoehe, die Felsschwelle laeuft der Hoehe also entgegen: aus der 14 m breiten
# Felsrampe (45..59) wird eine wirksame Rampe von 14 / (1 + HUB * 1.5 / (AUS - VOLL)).
# Mit den ersten Zahlen (90/220) waren das 5,3 Hoehenmeter — auf der Flanke eine Kante
# von anderthalb Netzzellen, und im Bild lag dort eine schnurgerade, treppige Linie quer
# durch beide Haenge. Mit 60/300 sind es 7,2 m, und das Rauschen darf mitreden.
# Rauschen auf der HOEHE, nicht auf einem Abstand: die Grenze soll mit dem Hang verzahnen.
# In ZWEI Groessen — 214 m fuer die grossen Zungen und Buchten der Waldgrenze, 60 m fuer
# den ausgefransten Rand. Eine einzelne Groesse sah aus wie mit dem Pinsel gewellt.
const TAL_WIESE_RAUSCH := 34.0
const TAL_WIESE_RAUSCH2 := 13.0
const TAL_WIESE_ENDE := 500.0    # Ausblendung an Taleingang und Talschluss
const TAL_PROBEN := 64           # Stuetzstellen des Talbodenprofils (rund 180 m Abstand)


## TALBODENPROFIL messen: je Stuetzstelle neun Proben quer ueber den Korridor, davon die
## ZWEITNIEDRIGSTE. Nicht die niedrigste — die faengt das Flussbett (bis 7 m eingeschnitten)
## oder den Seegrund; nicht den Mittelwert — der zieht die Flanken mit herein und haette das
## Profil um ueber hundert Meter zu hoch gelegt. Danach ein Dreiertiefpass, damit einzelne
## Kuppen keine Stufe in die Gruengrenze schneiden.
## LAEUFT EINMAL BEIM AUFBAU (64 * 9 = 576 height_at-Aufrufe, unter 10 ms) — in _face_color
## waere jede einzelne Probe verboten teuer.
func _talboden_bauen() -> void:
	_tal_boden = PackedFloat32Array()
	_tal_hb = PackedFloat32Array()
	if tal.is_empty():
		return
	_tal_hb = PackedFloat32Array(tal["halbbreite"])
	var st: Vector2 = tal["start"]
	var ri: Vector2 = Vector2(tal["richtung"]).normalized()
	var qu := Vector2(ri.y, -ri.x)
	var lg: float = float(tal["laenge"])
	var roh := PackedFloat32Array()
	for i in TAL_PROBEN:
		var l := lg * float(i) / float(TAL_PROBEN - 1)
		var hb := _tal_halbbreite(l)
		var probe: Array[float] = []
		for k in range(-4, 5):
			var p := st + ri * l + qu * (hb * 0.09 * float(k))
			probe.append(height_at(p.x, p.y))
		probe.sort()
		roh.append(probe[1])
	for i in TAL_PROBEN:
		_tal_boden.append(0.25 * roh[maxi(i - 1, 0)] + 0.5 * roh[i]
			+ 0.25 * roh[mini(i + 1, TAL_PROBEN - 1)])
	# Vorfilter fuer _tal_wiese: ein Umkreis um den ganzen Korridor. _face_color laeuft je
	# DREIECK ueber die ganze Welt — draussen darf nur EIN Abstandsquadrat anfallen.
	var hbmax := 0.0
	for w in _tal_hb:
		hbmax = maxf(hbmax, w)
	_tal_mitte = st + ri * (lg * 0.5)
	# 2 * hbmax, weil die seitliche Ausblendung bis zum doppelten Kammabstand reicht. Ein
	# zu kleiner Umkreis waere kein Sparfilter mehr, sondern eine zweite, KREISRUNDE Grenze
	# der Wiese — genau die Sorte gemalter Kante, die hier abgeschafft werden soll.
	var reich := lg * 0.5 + 2.0 * hbmax + TAL_WIESE_ENDE
	_tal_reich2 = reich * reich


## Halbe Korridorbreite an der Stelle "laengs". Das PROFIL KOMMT AUS MAIN (Stuetzstellen
## gleichen Abstands), nicht aus einer hier nachgebauten Formel: die Keilform des Tals
## gehoert Main, und eine zweite Kopie waere beim naechsten Umbau still falsch geworden.
func _tal_halbbreite(laengs: float) -> float:
	var n := _tal_hb.size()
	if n == 0:
		return 0.0
	if n == 1:
		return _tal_hb[0]
	var t := clampf(laengs / float(tal["laenge"]), 0.0, 1.0) * float(n - 1)
	var i := mini(int(t), n - 2)
	return lerpf(_tal_hb[i], _tal_hb[i + 1], t - float(i))


# --- SCHUTTHALDEN ----------------------------------------------------------------------
# Maschenweite der vorgerechneten Haldenmaske. Der Umriss traegt ein Randrauschen mit rund
# 120 m Wellenlaenge; 10 m loesen das mehr als auf.
const HALDE_GITTER := 10.0
# 0 = blanke Halde (kein Baum, kein Stein, keine Wiese), 1 = normales Gelaende. Die
# Schwellen liegen auf der Haldendichte aus Landmarks.tor_halde_zone.
# DIE SPERRE MUSS BEI 0.02 SCHON VOLL SEIN, denn dort liegt der AEUSSERSTE Block (siehe
# _tor_halde). Der erste Versuch nahm -0.05 .. 0.12, und damit war die Stelle, an der der
# letzte Block liegt, noch zu 63 Prozent Wiese: im Bild sassen am Rand der Schuerze
# einzelne helle Quader auf gruenem Gras — genau der Befund, den die Halde beseitigen
# soll. Jetzt ist bei 0.04 alles kahl, und der Uebergang liegt mit -0.12 komplett
# AUSSERHALB der Ellipse, also im Gras und nicht auf dem Fels.
const HALDE_VON := -0.12
const HALDE_BIS := 0.04


## MASKE EINMAL VORRECHNEN statt je Dreieck die Dichtefunktion aufzurufen. _open_ground
## laeuft 4608-mal je Chunk, _face_color genauso; eine Callable mit Noise-Abfrage darin
## waere genau die Sorte teurer Sonderfall, vor der der Kopf von _face_color warnt. Eine
## 167x167-Maske sind 110 kB und je Abfrage eine bilineare Interpolation.
## Die FORM kommt aus Landmarks (tor_halde_zone) — hier wird sie nur abgetastet.
func _halden_bauen() -> void:
	_halde_masken = []
	for hz in schutthalden:
		var reich := float(hz["reich"])
		var roh: Callable = hz["roh"]
		var n := int(2.0 * reich / HALDE_GITTER) + 1
		var g := PackedFloat32Array()
		g.resize(n * n)
		for j in n:
			for i in n:
				var lx := -reich + float(i) * HALDE_GITTER
				var lz := -reich + float(j) * HALDE_GITTER
				g[j * n + i] = 1.0 - smoothstep(HALDE_VON, HALDE_BIS,
					float(roh.call(lx, lz)))
		_halde_masken.append({"x": float(hz["x"]), "z": float(hz["z"]),
			"cos": float(hz["cos"]), "sin": float(hz["sin"]),
			"reich": reich, "r2": 2.0 * reich * reich, "n": n, "g": g})


## Wie frei ist die Stelle von Blockschutt? 1 = normales Gelaende, 0 = blanke Halde.
## Ausserhalb kostet das ein Abstandsquadrat je Halde — mehr darf es nicht sein, die
## Funktion haengt an _open_ground und damit an jedem Gelaendedreieck der ganzen Welt.
func _halde_frei(x: float, z: float) -> float:
	var k := 1.0
	for hm in _halde_masken:
		var dx := x - float(hm["x"])
		var dz := z - float(hm["z"])
		if dx * dx + dz * dz >= float(hm["r2"]):
			continue
		# In das Torsystem drehen (dort liegt die Maske). Dieselbe Umkehr wie bei den
		# Flugplatz-Rechtecken oben: Landmarks dreht mit Basis(UP, yaw), also ist
		# lx = cos*dx - sin*dz.
		var co: float = hm["cos"]
		var si: float = hm["sin"]
		var reich: float = hm["reich"]
		var n: int = hm["n"]
		var fx := (co * dx - si * dz + reich) / HALDE_GITTER
		var fz := (si * dx + co * dz + reich) / HALDE_GITTER
		if fx < 0.0 or fz < 0.0 or fx >= float(n - 1) or fz >= float(n - 1):
			continue
		var i := int(fx)
		var j := int(fz)
		var u := fx - float(i)
		var v := fz - float(j)
		var g: PackedFloat32Array = hm["g"]
		var a := lerpf(g[j * n + i], g[j * n + i + 1], u)
		var b := lerpf(g[(j + 1) * n + i], g[(j + 1) * n + i + 1], u)
		k = minf(k, lerpf(a, b, v))
	return k


## WIESENANTEIL an einer Stelle: 1 = voller Hub der Felsschwelle, 0 = Weltregel.
## ny ist der Kosinus der Hangneigung (1 = eben) — dieselbe Zahl, mit der _face_color den
## Fels ueber die Steilheit einblendet.
func _tal_wiese(cen: Vector3, ny: float) -> float:
	if _tal_boden.is_empty():
		return 0.0
	var mx := cen.x - _tal_mitte.x
	var mz := cen.z - _tal_mitte.y
	if mx * mx + mz * mz > _tal_reich2:
		return 0.0
	var st: Vector2 = tal["start"]
	var ri: Vector2 = Vector2(tal["richtung"]).normalized()
	var ex := cen.x - st.x
	var ez := cen.z - st.y
	var lg: float = float(tal["laenge"])
	var l := ex * ri.x + ez * ri.y
	if l < -TAL_WIESE_ENDE or l > lg + TAL_WIESE_ENDE:
		return 0.0
	var q := absf(ex * ri.y - ez * ri.x)
	var hb := _tal_halbbreite(l)
	# SEITLICHE AUSBLENDUNG ERST WEIT HINTER DEM KAMM (1,0 bis 2,0 Kammabstaende).
	# ERSTER VERSUCH WAR 0.80 BIS 1.05, und das war im Bild sofort zu sehen: eine
	# schnurgerade, treppige Kante laengs der Talachse quer durch beide Flanken, weil dort
	# unten noch Gelaende unter der Wiesenschwelle liegt und die Grenze allein von der
	# Rechnung kam. Zwischen 1,0 und 2,0 Kammabstaenden (am Talmund 2480 bis 4960 m, am
	# Talschluss 2110 bis 4220 m — die Halbbreite ist ein Keil, siehe Main._tal_halbbreite)
	# steht dagegen ueberall der Kamm selbst — die Massive haben 2200 m Radius und bis
	# 1250 m Gipfel, und die Gipfel steigen zum Talschluss monoton an,
	# das Gelaende ist dort laengst ueber der Schwelle, und die Ausblendung kann gar nichts
	# mehr faerben. Sie bleibt trotzdem stehen: sie ist die Garantie, dass ausserhalb des
	# Hochtals keine einzige Flaeche die Farbe wechselt.
	var seit := 1.0 - smoothstep(hb, hb * 2.0, q)
	if seit <= 0.0:
		return 0.0
	seit *= smoothstep(-TAL_WIESE_ENDE, 0.0, l) * (1.0 - smoothstep(lg, lg + TAL_WIESE_ENDE, l))
	# HANG: die Alm hoert am STEILHANG auf, nicht auf einer Hoehenlinie. Ohne diesen Faktor
	# lief die Gruengrenze quer ueber Rippen und Rinnen hinweg, als waere sie gezeichnet;
	# mit ihm folgt sie der Form des Hangs, und aus jeder Felsrippe waechst Geroell in die
	# Wiese hinein. 0.78 bis 0.92 sind rund 39 bis 23 Grad. Der Sockel von 0.30 muss
	# bleiben: sonst verliert ein steiles Ufer direkt am Wasser die Wiese und der See
	# stuende wieder in einem grauen Rand.
	var hang := 0.30 + 0.70 * smoothstep(0.78, 0.92, ny)
	var t := clampf(l / lg, 0.0, 1.0) * float(TAL_PROBEN - 1)
	var i := mini(int(t), TAL_PROBEN - 2)
	var boden := lerpf(_tal_boden[i], _tal_boden[i + 1], t - float(i))
	# DIE BEIDEN RAUSCHABFRAGEN SIND DER TEURE TEIL dieser Funktion, und die Funktion laeuft
	# je DREIECK. Sie koennen die Hoehe um hoechstens RAUSCH + RAUSCH2 verschieben — wer
	# weiter als das von der Blendzone entfernt liegt, bekommt sein Ergebnis ohne sie. Das
	# trifft fast alles: den ganzen Talboden (voll) und die ganze Flanke darueber (null).
	var streu := TAL_WIESE_RAUSCH + TAL_WIESE_RAUSCH2
	if cen.y < boden + TAL_WIESE_VOLL - streu:
		return seit * hang
	if cen.y > boden + TAL_WIESE_AUS + streu:
		return 0.0
	var hh := cen.y + TAL_WIESE_RAUSCH * _patch.get_noise_2d(cen.x * 0.28, cen.z * 0.28) \
		+ TAL_WIESE_RAUSCH2 * _patch.get_noise_2d(cen.z + 900.0, cen.x - 400.0)
	return seit * hang * (1.0 - smoothstep(boden + TAL_WIESE_VOLL, boden + TAL_WIESE_AUS, hh))


## Legt die Vulkane fuer Farbe und Bewuchs zurecht (siehe _vulkane).
func _vulkane_bauen() -> void:
	_vulkane = []
	for ms in massifs:
		if String(ms.get("type", "")) != "vulkan":
			continue
		var p: Vector3 = ms["pos"]
		var mr := float(ms["r"])
		# AUSSENRADIUS DER SCHUERZE, oder null, wenn dieser Kegel keine hat. Er steht hier
		# EINMAL und wird von allen Ableitungen darunter gelesen — die Reichweite der Haut,
		# der Zungen und des Waldkragens haengen inzwischen alle an ihm, und drei Stellen,
		# die "mr * VULKAN_APRON_WEIT" jede fuer sich ausrechnen, laufen beim naechsten
		# Eingriff auseinander.
		var apr := 0.0
		if float(ms.get("apron", 0.0)) > 0.0:
			apr = mr * VULKAN_APRON_WEIT
		# REICHWEITE DER HAUT. Ohne Schuerze ist sie wie bisher mr * VULKAN_HAUT_REICH; mit
		# ihr muss sie bis an deren Saum gehen, denn dort draussen liegt jetzt die Asche,
		# der Waldkragen und das Ende der Lavazungen. _face_color und der Bewuchs brechen an
		# dieser Schranke ab — was dahinter liegt, sehen sie ueberhaupt nicht mehr.
		var reich := maxf(mr * VULKAN_HAUT_REICH, apr)
		_vulkane.append({
			"x": p.x, "z": p.z, "r": mr, "reich2": reich * reich, "apr": apr,
			# Bis wohin _face_color die VULKANHAUT malt. Ohne Schuerze steht hier wie bisher
			# 1.05 * r; mit ihr genau die Stelle, an der die Ascheschuerze anfaengt
			# auszufransen — die beiden MUESSEN zusammenfallen (siehe VULKAN_APRON_ASCHE_AB),
			# sonst liegt zwischen Haut und Asche ein Ring aus gewachsener Wiese.
			"haut_r": mr * (VULKAN_APRON_ASCHE_AB if apr > 0.0 else 1.05),
			# Bis wohin die BAUMGRENZE DES KEGELS gilt, als Quadrat. Hier stand die feste
			# Zahl 1.1236 (= 1.06^2) mitten in vulkan_bewuchs; mit der Schuerze liegt das
			# Band aber weiter draussen (Begruendung bei VULKAN_APRON_BAUM).
			"baum2": pow(mr * (VULKAN_APRON_BAUM if apr > 0.0 else 1.06), 2.0),
			# Ein- und Ausblenden der LAVAZUNGEN in Metern. Ohne Schuerze sind das exakt die
			# alten Werte (1.06 und VULKAN_HAUT_REICH mal r); mit ihr laufen die Zungen bis
			# fast an den Saum des Faechers, denn dorthin tragen die Rinnen sie.
			"str_ab": mr * 1.06,
			"str_zu": (apr * VULKAN_APRON_STROM) if apr > 0.0 else (mr * VULKAN_HAUT_REICH),
			# Reichweite des WALDKRAGENS als eigenes Quadrat. Sie ist heute dieselbe wie die
			# der Haut, steht aber getrennt da, weil sie an einer anderen Zahl haengt
			# (VULKAN_KRAGEN_AUS statt VULKAN_HAUT_REICH) — wer eine davon verschiebt, soll
			# nicht die andere mitziehen.
			"kr2": mr * VULKAN_KRAGEN_AUS * mr * VULKAN_KRAGEN_AUS,
			"cr": float(ms.get("crater_r", mr * 0.16)),
			# Ob dieser Kegel Barrancos hat. Die Haut braucht nur das JA/NEIN — ihre Tiefe
			# in Metern faerbt nichts, sie schneidet. Ohne den Schluessel bleibt die Haut
			# genau die, die sie vorher war (kein Grataufhellen, Adern aus dem alten
			# Rippenrauschen).
			"bar": float(ms.get("barranco", 0.0)) > 0.0,
			# Ob dieser Kegel eine BLOCKLAGE hat. Wieder nur das JA/NEIN: die Auswurfhoehe
			# in Metern hebt das Gelaende, die Haut braucht nur zu wissen, ob sie den
			# Aufschluss auch aufhellen darf. Fehlt der Schluessel, kostet die Haut keine
			# einzige zusaetzliche Rauschabfrage und faerbt bitgenau wie bisher.
			"blk": float(ms.get("bloecke", 0.0)) > 0.0,
			# Ob dieser Kegel FEINRIPPEN hat. Wieder nur das JA/NEIN: die Amplitude in
			# Metern hebt das Gelaende, die Haut braucht nur zu wissen, ob sie deren Kamm
			# aufhellen darf. Fehlt der Schluessel, kostet die Haut keine einzige
			# zusaetzliche Rauschabfrage.
			"frp": float(ms.get("feinrippen", 0.0)) > 0.0,
			# Ob dieser Kegel Lavalappen am Fuss hat. Auch hier nur das JA/NEIN: die Hoehe
			# in Metern hebt das Gelaende, die Bepflanzung interessiert nur, DASS dort
			# frische Lava liegt. Fehlt der Schluessel, kostet der Kragen keine einzige
			# zusaetzliche Rauschabfrage.
			"lpn": float(ms.get("lava_lappen", 0.0)) > 0.0,
			# Ob die Schuerze eine SCHUTTLAGE traegt. Wieder nur das JA/NEIN: die
			# Auswurfhoehe in Metern hebt das Gelaende, die Haut braucht nur zu wissen, ob
			# sie die Nester aufhellen darf. Fehlt der Schluessel, kostet die Schuerzenmaske
			# keine einzige zusaetzliche Rauschabfrage.
			"abl": float(ms.get("apron_bloecke", 0.0)) > 0.0,
			# Bezugshoehe des Farbverlaufs. "peak" ist die Hoehe, mit der das Massiv in der
			# Tabelle steht; die gewachsene Lippe liegt darueber, der Hoehenanteil saettigt
			# dort also bei eins — und genau das soll er.
			# DIE SCHUERZE MUSS MIT. Sie traegt den ganzen Kegel um "apron" Meter hoeher,
			# der Gipfel steht also bei peak + apron. Ohne diesen Summanden saettigte der
			# Hoehenanteil schon 190 m unter dem Gipfel, und die oberste Flanke bekaeme
			# eine andere Haut als der Rest — Asche und Rost sitzen auf ANTEILEN der
			# Flankenhoehe, nicht auf Metern.
			"hoch": maxf(float(ms["peak"]) + float(ms.get("apron", 0.0))
				- VULKAN_HAUT_FUSS, 1.0),
		})


## LAGE EINES PUNKTES IN SEINEM BARRANCO.
##   x = Querlage in der Rinne: 0 ist die Sohle, +-1 der Grat zum Nachbarn.
##   y = wie tief diese Rinne ueberhaupt einschneidet (VULKAN_BARR_TIEF_MIN .. 1).
##   z = die STETIGE Rinnenkoordinate selbst (Rinne k liegt zwischen k und k+1, ihre Sohle
##       bei k + 0.5). Sie kommt mit zurueck, weil das Lavanetz darauf laeuft: es soll sich
##       ueber MEHRERE Rinnen hinweg gabeln, und dafuer reicht die Querlage in EINER nicht.
##       Sie enthaelt den Maeander bereits — das Netz wackelt also mit den Rinnen mit,
##       statt schnurgerade ueber sie hinwegzulaufen.
##
## ZWEI AUFRUFER, UND DAS IST DER GRUND FUER DIE EIGENE FUNKTION — derselbe Grund wie bei
## _vulkan_strom, nur mit mehr Fallhoehe: height_at schneidet damit die Rinne, _vulkan_haut
## legt die gluehende Ader in ihre Sohle und den hellen Abrieb auf ihren Grat. Stuende der
## Ausdruck zweimal im Code, laege die Lava nach der naechsten Aenderung NEBEN der Rinne
## statt in ihr, und ein aufgemaltes Netz auf einer glatten Flanke ist genau der Zustand,
## aus dem die Barrancos herausfuehren sollten.
##
## BEIDE ZAHLEN KOMMEN ZUSAMMEN ZURUECK, damit kein Aufrufer die eine ohne die andere holen
## kann: eine flache Rinne muss auch eine blasse Ader und einen stumpfen Grat haben.
## Vector3 ist ein Wert, das kostet keine Zuteilung.
func _vulkan_rinne(ux: float, uz: float, md: float) -> Vector3:
	# Der Winkel geht als PHASE ein, nicht als Rauschachse — bei ganzer Rinnenzahl springt
	# er ueber die Naht bei +-pi um einen vollen Umlauf, und der Nachkommateil merkt davon
	# nichts (Begruendung bei VULKAN_BARR_N).
	var ph := atan2(uz, ux) * _vk_barr_n / TAU \
		+ VULKAN_BARR_MAEANDER * _noise.get_noise_3d(
			ux * _vk_barr_wander, uz * _vk_barr_wander, md * VULKAN_BARR_LAUF)
	# .x kommt aus der VERSETZTEN Phase (Sohlen auf ganzen Zahlen, siehe VULKAN_BARR_VERSATZ),
	# .z bleibt die rohe — auf ihr sitzt der Lavabaum mit seinen Zellgrenzen.
	var phb := ph + VULKAN_BARR_VERSATZ
	return Vector3(2.0 * (phb - floor(phb)) - 1.0,
		lerpf(VULKAN_BARR_TIEF_MIN, 1.0, 0.5 + 0.5 * _noise.get_noise_2d(
			ux * _vk_barr_tief + 8300.0, uz * _vk_barr_tief - 6100.0)), ph)


## DAS QUERPROFIL DER RINNE — GROBE LAGE PLUS FEINE OBERHARMONISCHE, um seinen eigenen
## Mittelwert zentriert (-1/3 in der Sohle, +2/3 auf dem Grat). Die Huellkurve der feinen
## Lage steckt mit drin, die der groben NICHT: die haengt am Aufrufer, weil height_at sie
## mit der gewachsenen Lippe rechnet und die Farbe mit dem nominellen Kraterradius.
##
## ZWEI AUFRUFER, UND ES IST DERSELBE GRUND WIE BEI _vulkan_rinne, nur eine Ebene tiefer:
## height_at schneidet dieses Profil als Gelaende, _vulkan_haut legt dieselbe Kurve als
## Hell-Dunkel darauf. Stuende der Ausdruck zweimal im Code, laege nach der naechsten
## Aenderung das helle Band neben dem Grat — und ein Streifenmuster, das quer zur Form
## laeuft, ist schlimmer als gar keins.
##
## "q" ist rn.x (Querlage in der groben Rinne), "ph" ist rn.z (die stetige Rinnenkoordinate).
func _vulkan_rinne_profil(q: float, ph: float, md: float, kr: float, mr: float) -> float:
	var p := q * q - VULKAN_BARR_MITTE
	var e := smoothstep(kr + (mr - kr) * VULKAN_BARR_FEIN_AB,
		kr + (mr - kr) * VULKAN_BARR_FEIN_VOLL, md)
	if e <= 0.0:
		return p
	# DIESELBE VERSETZTE PHASE WIE rn.x, sonst faenden Grundlage und Oberharmonische nicht
	# zusammen (siehe VULKAN_BARR_VERSATZ und VULKAN_BARR_FEIN_N).
	var f := (ph + VULKAN_BARR_VERSATZ) * VULKAN_BARR_FEIN_N
	f = 2.0 * (f - floor(f)) - 1.0
	return p + VULKAN_BARR_FEIN * e * (f * f - VULKAN_BARR_MITTE)


## LAGE EINES PUNKTES IM LAVANETZ — DER GANZE BAUM STECKT IN DIESEN ZEHN ZEILEN.
##   x = Abstand zur Achse des naechsten Astes, in Rinnenbreiten
##   y = halbe Breite des gluehenden Kerns dieses Astes, ebenfalls in Rinnenbreiten
##   z = Staerke dieses Astes, 0 bis 1 (je Ast einmal gewuerfelt)
##
## WIE DAS VERZWEIGEN OHNE VERZWEIGUNG ZUSTANDE KOMMT: die Flanke wird in Zellen der Breite
## s eingeteilt, die Achse eines Astes ist die MITTE seiner Zelle. Hangabwaerts halbiert
## sich s zweimal. Beim Halbieren zerfaellt jede Elternzelle in zwei Kinder, deren Mitten
## nach beiden Seiten aus der Elternmitte herauswandern — geblendet ueber die Gabelung ist
## das ein Y. Man muss es nicht als Y rechnen, es faellt aus der Zellteilung heraus, und
## deshalb kostet der ganze Baum kein einziges Rauschen.
##
## DIE ZELLBREITEN SIND GANZE ZAHLEN (4, 2, 1 Rinnen), und daran haengt alles: nur so
## faellt die Achse des feinsten Astes auf s * (j + 0.5) = k + 0.5, also genau in eine
## Rinnensohle. Siehe VULKAN_BARR_N — die Rinnenzahl ist deshalb eine Zweierpotenz.
## Ausserdem geht die Zellteilung damit ueber die atan2-Naht hinweg auf: bei ph und ph + 32
## liegt derselbe Punkt, und weil 32 durch jede Zellbreite teilbar ist, liegt er auch in
## derselben Zelle. Mit 30 Rinnen staende an der Naht eine Kante.
func _vulkan_ader(ph: float, md: float, mr: float, cr: float) -> Vector3:
	# "lam" ist die Zahl der schon vollzogenen Gabelungen als gebrochene Groesse: die ganze
	# Stelle waehlt die Zellbreite, der Rest blendet die eine Gabelung ein, die gerade laeuft.
	# Der Exponent schiebt sie nach aussen — bei 1.25 sind sie auf 788, 1032 und 1250 m
	# fertig, und die obere Haelfte der Flanke gehoert den acht Staemmen allein. Linear
	# kreuzte ein Ring schon bei 520 m ACHT Adern (gemessen mit tools/_vulkan_form.gd), der
	# Kraterrand hatte also gar keine vier Hauptrinnen mehr.
	var lam := VULKAN_ADER_GABELN * pow(clampf(
		(md - cr) / maxf(mr * VULKAN_ADER_FUSS - cr, 1.0), 0.0, 1.0), VULKAN_ADER_GABEL_K)
	var st := floorf(lam)
	# smoothstep statt des rohen Rests: eine Gabel, die linear aufgeht, hat an ihrem Anfang
	# einen Knick, und ein Knick auf 8 m Netzweite ist eine sichtbare Ecke in der Ader.
	var g := smoothstep(0.0, 1.0, lam - st)
	var sc := _vk_ader_stamm * pow(0.5, st)      # Zellbreite der ELTERN ...
	var sf := sc * 0.5                           # ... und die der KINDER
	# GENAU EINE GABELUNG ZUR ZEIT, UND DAS IST KEINE SPARSAMKEIT, SONDERN DIE BEDINGUNG
	# DAFUER, DASS DER ABSTAND ZUR ACHSE STETIG IST. Hier stand einmal eine Fassung, in der
	# jede Gabelung ihre eigene, weit gezogene Rampe hatte und alle sich
	# ueberlappten — damit lief keine Ader mehr quer ueber den Hang, dafuer stand am
	# Bergfuss ein LATTENZAUN aus 24 m hohen senkrechten Waenden.
	# WARUM: die Zellmitte springt an jeder Zellgrenze um eine Zellbreite. Blendet man von
	# der ELTERNMITTE zur Kindmitte, faellt der Sprung heraus, denn die Elternmitte liegt
	# GENAU zwischen den beiden Kindern — beide Seiten der Grenze haben denselben Abstand.
	# Ist die Elternmitte selbst schon eine Zwischenstellung (weil die vorige Gabelung noch
	# laeuft), gilt das nicht mehr, und der Sprung bleibt stehen. Im Hoehenfeld ist so ein
	# Sprung eine senkrechte Wand.
	# Der Preis ist, dass eine Gabelung nur ein Drittel der Flanke hat: der Ast wandert
	# dabei zwei Rinnen zur Seite, also rund 250 m auf 330 m Fallstrecke. Das sieht man ihm
	# an, und es ist das kleinere Uebel — ein Strom, der sich seitlich einen neuen Weg
	# sucht, tut genau das, eine Wand quer durch den Apron tut niemand.
	var c := lerpf(sc * (floorf(ph / sc) + 0.5), sf * (floorf(ph / sf) + 0.5), g)
	# Die Breite folgt der Zellbreite, nicht der Gabelzahl: dieselbe Blende, dieselbe Kurve,
	# kein zweiter Satz Zahlen, der beim naechsten Eingriff auseinanderlaeuft.
	return Vector3(absf(ph - c),
		VULKAN_ADER_KERN * pow(lerpf(sc, sf, g), VULKAN_ADER_DICK), _vulkan_ader_wurf(ph))


## WIE STARK DIESER AST IST, VULKAN_ADER_WURF bis 1.
##
## ER LIEST ph UND NICHT DIE ACHSE, OBWOHL DIE ACHSE DAS RICHTIGERE ARGUMENT WAERE. Der
## Grund ist eine Falle, in die zwei Fassungen hintereinander gelaufen sind: der Wurf traegt
## unten die LAVALAPPEN auf, also 24 m Gelaende, und jede Unstetigkeit in ihm ist dort eine
## senkrechte Wand. Die Achse c ist aber in ph stueckweise KONSTANT — sie springt an jeder
## Zellgrenze um eine halbe Zellbreite. Stetig ist nur der ABSTAND zu ihr, und das reicht
## nicht: mitten in einer halb offenen Gabelung liegt die Zellgrenze GENAU AUF der Achse,
## und dort steht dann die Wand. Dasselbe gilt fuer die Astnummer. ph dagegen ist stetig,
## und weil der Wurf sich auf der Laengenskala einer Rinne aendert, unterscheiden sich zwei
## Nachbaraeste trotzdem deutlich. Die Probe dazu heisst SENKRECHTE WAENDE
## (tools/_vulkan_form.gd) und muss unter rund 20 m bleiben.
## ZWEI SINUSSE MIT GANZZAHLIGEN PERIODEN AUF DEM UMFANG, sonst haette der Wurf an der
## atan2-Naht eine Kante. 13 und 5 sind teilerfremd zueinander und zu 32 — benachbarte
## Aeste (eine Rinne Abstand) unterscheiden sich damit deutlich, und das Muster wiederholt
## sich erst nach einem vollen Umlauf. Ein Rauschen waere hier falsch: es gibt Nachbarn
## AEHNLICHE Werte, und an einer Gabel sollen sich die beiden Arme gerade unterscheiden.
func _vulkan_ader_wurf(c: float) -> float:
	return lerpf(VULKAN_ADER_WURF, 1.0,
		0.5 + 0.25 * sin(c * _vk_ader_wurf1) + 0.25 * sin(c * _vk_ader_wurf2 + 1.7))


## LAVALAPPEN: was am Fuss von einem Ast uebrigbleibt, 0 bis 1. Er hat Hoehe (height_at),
## ist schwarz (_vulkan_haut) und traegt keinen Baum (vulkan_bewuchs) — drei Aufrufer,
## deshalb steht er als eigene Funktion da und nicht dreimal im Code.
## "ad" ist die Rueckgabe von _vulkan_ader; der Aufrufer hat sie ohnehin schon geholt.
func _vulkan_lappen(ad: Vector3, md: float, mr: float) -> float:
	var e := smoothstep(mr * VULKAN_LAPPEN_AB, mr * VULKAN_LAPPEN_VOLL, md) \
		* (1.0 - smoothstep(mr * VULKAN_LAPPEN_AUS_AB, mr * VULKAN_LAPPEN_AUS_ZU, md))
	if e <= 0.004:
		return 0.0
	# Der Lappen sitzt auf der Aderachse und ist breiter als sie — deshalb der eigene
	# Massstab in Rinnenbreiten statt eines Vielfachen der Aderbreite.
	# FLACHE RAMPE AUF DER ASTSTAERKE (0.30 breit, nicht 0.22): sie traegt Gelaende auf, und
	# je steiler sie ist, desto mehr macht sie aus einer kleinen Aenderung des Wurfs eine
	# grosse Aenderung der Hoehe.
	return e * smoothstep(VULKAN_LAPPEN_KRAFT, VULKAN_LAPPEN_KRAFT + 0.30, ad.z) \
		* (1.0 - smoothstep(VULKAN_LAPPEN_BREIT * 0.45, VULKAN_LAPPEN_BREIT, ad.x))


## ERSTARRTER LAVASTROM an einer Stelle: 0 = gewachsener Boden, 1 = blanker Basalt.
## md/ux/uz sind Abstand und Einheitsrichtung zum Vulkanmittelpunkt — der Aufrufer hat sie
## fuer seinen Vorfilter ohnehin schon gebraucht.
##
## ZWEI AUFRUFER, UND DAS IST DER GRUND FUER DIE EIGENE FUNKTION: die FARBE braucht die
## Maske (schwarzes Band ueber Flanke und Ebene) und der BEWUCHS braucht sie (auf frischem
## Basalt waechst nichts). Stuenden die beiden getrennt im Code, waere ueber kurz oder lang
## ein Wald auf dem Strom gewachsen — genau der Widerspruch zwischen Farbe und Bewuchs, an
## dem in dieser Welt schon die Almwiese und die Schutthalde haengengeblieben sind.
func _vulkan_strom(vk: Dictionary, md: float, ux: float, uz: float) -> float:
	var mr: float = vk["r"]
	# Huellkurve: INNEN faengt die Zunge erst unterhalb des Kraterrands an — weiter oben ist
	# die Flanke ohnehin schwarze Asche, dort waere ein schwarzes Band unsichtbar. AUSSEN
	# laeuft sie ueber den Fussradius hinaus aus.
	# DIE AEUSSEREN ZWEI ZAHLEN STEHEN JETZT IM VULKAN-EINTRAG statt hier im Ausdruck
	# ("str_ab"/"str_zu", siehe _vulkane_bauen): mit einer Schuerze am Fuss laufen die Zungen
	# bis fast an deren Saum, ohne sie bleibt es bei VULKAN_HAUT_REICH und damit exakt beim
	# alten Wert. Ein "if" mitten in einer Funktion, die je Dreieck laeuft, waere dafuer der
	# falsche Ort — der Fall entscheidet sich einmal beim Weltaufbau.
	var e := smoothstep(mr * 0.30, mr * 0.46, md) \
		* (1.0 - smoothstep(float(vk["str_ab"]), float(vk["str_zu"]), md))
	if e <= 0.004:
		return 0.0
	# Eine Achse laeuft UM den Berg, die zweite den Hang HINUNTER — dieselbe Bauart wie bei
	# den Rippen. Ohne die zweite waere die Zunge ein Tortenstueck mit kerzengeraden Kanten
	# vom Gipfel bis in die Ebene; mit ihr maeandert sie seitlich, so wie ein Strom, der
	# sich seinen Weg sucht.
	return e * smoothstep(VULKAN_ZUNGEN_AB, VULKAN_ZUNGEN_VOLL,
		_noise.get_noise_3d(ux * _vk_zungen_kreis + VULKAN_ZUNGEN_OX,
			uz * _vk_zungen_kreis, md * VULKAN_ZUNGEN_LAUF))


## DIE ASCHESCHUERZE AN EINER STELLE.
##   x = wie weit die Asche hier deckt, 0 (Vorland) bis 1 (blanker Faecher)
##   y = wie weit der Punkt auf dem RUECKEN zwischen zwei Rinnen liegt, 0 (Sohle) bis 1
##   z = die Schuttlage an dieser Stelle (siehe _vulkan_apron_schutt)
##
## ZWEI AUFRUFER, UND ES IST DERSELBE GRUND WIE BEI _vulkan_strom: die FARBE braucht die
## Maske (Asche ueber der gewachsenen Wiese) und der BEWUCHS braucht sie (auf frischer Asche
## waechst nichts). Stuenden sie getrennt im Code, waere ueber kurz oder lang ein Wald auf
## dem Faecher gewachsen — genau der Widerspruch zwischen Farbe und Bewuchs, an dem in dieser
## Welt schon die Almwiese und die Schutthalde haengengeblieben sind.
## DIE BEIDEN LESEN DESHALB DIESELBE ZAHL: die Farbe deckt mit x, der Bewuchs behaelt 1 - x.
## Die Baumgrenze steckt darin schon drin (siehe unten) — vulkan_bewuchs darf sie im
## Schuerzenring also NICHT ein zweites Mal auftragen, sonst duennt der Kragen quadratisch.
##
## DER RUECKENANTEIL KOMMT MIT ZURUECK, damit ihn die Farbe nicht ein zweites Mal holen muss:
## _vulkan_rinne ist eine Rauschabfrage, und diese Funktion laeuft je Dreieck. Was er soll,
## steht bei VULKAN_APRON_GRUS_C.
##
## WIE DER SAUM SEINE ZACKEN BEKOMMT: die Reichweite der ZUNGEN haengt an der Rinnenlage. In
## der Sohle reicht die Asche voll hinaus (dort laeuft die Lava), auf dem Ruecken nur bis
## VULKAN_APRON_GRAT. Der Waldrand faellt damit in die Rinnen hinein und steht auf den
## Ruecken vor — er ist von Haus aus gezackt, ohne dass ihn ein Rauschen zackig machen muss.
## Das grobe Rauschen darauf sorgt nur noch dafuer, dass nicht alle Zacken gleich lang sind.
##
## UND DARUEBER LIEGT DIE EIGENTLICHE REGEL: KAHLER BODEN AUF EINEM VULKAN IST ASCHE.
## Die Zungen allein waren zweimal falsch eingestellt, und beide Male aus demselben Grund —
## sie sind ein RADIUS, der Waldrand aber eine HOEHENLINIE. Wo beide auseinanderliefen, blieb
## ein Ring, auf dem weder Asche lag noch ein Baum stand: im Bild heller, sonnenbeschienener
## Bergfels, der den Faecher wie eine Geroellwueste aussehen liess.
## Der Ausdruck 1 - Baumgrenze * (1 - Zunge) macht daraus eine Zahl. Oberhalb der Baumgrenze
## ist er eins, ganz gleich, was der Radius sagt: dort ist der Boden kahl, also Asche.
## Unterhalb bleibt genau die Zunge uebrig, und die franst in den Wald hinein.
func _vulkan_apron(vk: Dictionary, x: float, z: float, h: float, md: float,
		ux: float, uz: float) -> Vector3:
	var apr: float = vk["apr"]
	if apr <= 0.0 or md >= apr:
		return Vector3.ZERO
	var mr: float = vk["r"]
	var ab := mr * VULKAN_APRON_ASCHE_AB
	var rn := _vulkan_rinne(ux, uz, md)
	var ruecken := rn.x * rn.x
	# DIE SCHUTTLAGE KOMMT MIT ZURUECK, weil die Farbe sie braucht und height_at sie
	# auftraegt. Beide lesen DIESELBE Funktion (_vulkan_apron_schutt) — stuende der Ausdruck
	# zweimal im Code, laege die helle Koernung nach der naechsten Aenderung neben ihren
	# Nestern, und ein Fleckenmuster ohne Form darunter ist an dieser Flanke schon einmal als
	# "helle Striemen" gemeldet worden.
	var schutt := 0.0
	if bool(vk.get("abl", false)) and md > mr * VULKAN_APRON_BLOCK_AB:
		schutt = _vulkan_apron_schutt(x, z, md, mr)
	# INNEN IST DIE SCHUERZE GESCHLOSSEN. Der Kegel steht dort ohnehin ueber seiner
	# Baumgrenze, die Regel unten gaebe also dasselbe — dies ist nur der Vorfilter, der die
	# Rauschabfragen dafuer spart.
	if md <= ab:
		return Vector3(1.0, ruecken, schutt)
	# 0 am Kegelfuss, 1 am aeusseren Saum — in diesem Mass steht auch die Reichweite.
	var q := (md - ab) / (apr - ab)
	# rn.y ist, WIE TIEF diese Rinne ueberhaupt einschneidet. Sie zieht mit: eine flache
	# Rinne traegt weniger Lava und schiebt die Asche deshalb auch weniger weit hinaus.
	var reich := lerpf(VULKAN_APRON_GRAT, 1.0,
			pow((1.0 - ruecken) * rn.y, VULKAN_APRON_ZUNGE)) \
		+ VULKAN_APRON_ZACK * (0.5 + 0.5 * _patch.get_noise_2d(
			x * _vk_apron_takt, z * _vk_apron_takt))
	var zunge := 1.0 - smoothstep(reich - VULKAN_APRON_SAUM, reich, q)
	# UND DAS SCHUTTNEST DECKT AUCH. Es ist ausgeworfener Block, also Asche wie der Rest —
	# und ohne diese Zeile war es der letzte helle Fleck auf dem Faecher: die Weltregel in
	# _face_color faerbt Fels nicht nur nach der HOEHE (die haelt VULKAN_APRON_FELS_HUB
	# heraus), sondern auch nach der STEILHEIT, und ein 15-m-Block auf 46 m Welle steht
	# steiler als deren Schwelle. Im Bild lagen deshalb sandfarbene Facetten mitten im
	# schwarzen Faecher, jede genau so gross wie ein Nest.
	# Die Bepflanzung liest dieselbe Zahl (vulkan_bewuchs): auf einem Blockfeld waechst
	# nichts, und der Kragen verliert dadurch nichts, was er nicht ohnehin verloren haette —
	# er faellt an solchen Stellen schon an der Hangneigung aus.
	return Vector3(maxf(1.0 - _vulkan_baumgrenze(x, z, h) * (1.0 - zunge), schutt),
		ruecken, schutt)


## DIE SCHUTTLAGE DES FAECHERS, 0 bis 1 — Nester aus 46-m-Bloecken, wie sie auf der Flanke
## darueber liegen (VULKAN_BLOCK_M). height_at multipliziert das mit "apron_bloecke" und
## traegt es auf, die Haut hellt dieselben Nester auf.
##
## ZWEI AUFRUFER, UND ES IST DER GRUND FUER DIE EIGENE FUNKTION: die Form und die Farbe
## muessen dieselbe Lage lesen. Warum die aeussere Huelle vor dem Waldkragen endet, steht bei
## VULKAN_APRON_BLOCK_AUS_AB.
func _vulkan_apron_schutt(x: float, z: float, md: float, mr: float) -> float:
	return smoothstep(VULKAN_BLOCK_AB, VULKAN_BLOCK_VOLL,
			_ridge.get_noise_2d(x * _vk_block_takt, z * _vk_block_takt)) \
		* smoothstep(mr * VULKAN_APRON_BLOCK_AB, mr * VULKAN_APRON_BLOCK_VOLL, md) \
		* (1.0 - smoothstep(mr * VULKAN_APRON_BLOCK_AUS_AB,
			mr * VULKAN_APRON_BLOCK_AUS_ZU, md))


## Dasselbe fuer Aufrufer, die nur x/z haben. Der Bewuchs geht ueber vulkan_bewuchs, das den
## Strom mit der Baumgrenze zusammenfasst — hier bleibt die NACKTE Strommaske, weil die
## Abnahme sie einzeln misst (tools/_vulkan_form.gd zaehlt Flaechenanteil und Reichweite je
## Richtung). Eine Messgroesse, die nur noch als Produkt mit etwas anderem zu haben ist,
## taugt nicht als Messgroesse.
func vulkan_strom_bei(x: float, z: float) -> float:
	for vk in _vulkane:
		var dx := x - float(vk["x"])
		var dz := z - float(vk["z"])
		var d2 := dx * dx + dz * dz
		if d2 > float(vk["reich2"]):
			continue
		var d := sqrt(d2)
		if d < 1.0:
			return 0.0
		return _vulkan_strom(vk, d, dx / d, dz / d)
	return 0.0


## WAS AM VULKAN VOM BEWUCHS UEBRIGBLEIBT, 0 bis 1. Draussen ist es eine Eins und kostet je
## Vulkan ein Abstandsquadrat — die Funktion haengt an jeder Bewuchszelle der ganzen Welt.
##
## ZWEI GRUENDE, WARUM HIER NICHTS WAECHST, und sie stehen zusammen in EINER Funktion, weil
## beide Aufrufer (die echten Baeume in _make_chunk_data und die eingefaerbte Fernschuerze
## ueber wald_anteil) beide brauchen und sonst zweimal denselben Vorfilter zahlen:
##   STROM  auf frischem Basalt waechst nichts, siehe _vulkan_strom.
##   HOEHE  die Baumgrenze des Kegels, siehe VULKAN_BAUM_AB.
## DIE FERNSCHUERZE MUSSTE MIT. Sie faerbt ihre Dreiecke nach wald_anteil dunkelgruen und
## kannte bisher nur den Strom — jenseits der gestreamten Chunks lag deshalb ein gruener
## Hauch bis auf 230 m die Flanke hinauf, waehrend im Nahfeld schon lange kein Baum mehr
## stand. Im Anflug wanderte der Waldrand also mit dem Spieler.
func vulkan_bewuchs(x: float, z: float, h: float) -> float:
	for vk in _vulkane:
		var dx := x - float(vk["x"])
		var dz := z - float(vk["z"])
		var d2 := dx * dx + dz * dz
		if d2 > float(vk["reich2"]):
			continue
		var f := 1.0
		var d := sqrt(d2)
		var ux := 0.0
		var uz := 0.0
		if d > 1.0:
			ux = dx / d
			uz = dz / d
		# ZWEI WEGE, UND SIE SCHLIESSEN EINANDER AUS.
		# MIT SCHUERZE steckt die Baumgrenze schon in der Aschemaske (Begruendung bei
		# _vulkan_apron: kahler Boden auf einem Vulkan IST Asche). Sie hier ein zweites Mal
		# aufzutragen hiesse, den Kragen quadratisch auszuduennen — genau der Unterschied
		# zwischen einem aufgerissenen Waldrand und gar keinem, den die Probe in
		# tools/_vulkan_form.gd misst.
		# OHNE SCHUERZE bleibt es bei der Baumgrenze allein, und zwar bis "baum2" hinaus.
		# Weiter draussen laufen nur noch die Zungen, und was neben einer erstarrten Zunge
		# waechst, ist ganz normales Vorland. Hier stand einmal die feste Zahl 1.1236.
		if float(vk["apr"]) > 0.0:
			f = 1.0 - _vulkan_apron(vk, x, z, h, d, ux, uz).x
			if f <= 0.004:
				return 0.0
		elif d2 < float(vk["baum2"]):
			f = _vulkan_baumgrenze(x, z, h)
			if f <= 0.004:
				return 0.0
		if d < 1.0:
			return f
		# LAVALAPPEN. Sie liegen genau in der Hoehenlage des Waldkragens, also da, wo sonst
		# der dichteste Wald des ganzen Kegels steht — ohne diese Zeilen waere jeder Lappen
		# ein schwarzer Fleck mit Nadelbaeumen darauf. Die Abfrage kostet zwei
		# Rauschabfragen und laeuft deshalb NUR im Apron-Ring, in dem es Lappen ueberhaupt
		# gibt; auf der ganzen uebrigen Flanke faellt sie an der Abstandsschranke ab.
		if bool(vk.get("lpn", false)) and f > 0.01:
			var mr: float = vk["r"]
			if d > mr * VULKAN_LAPPEN_AB and d < mr * VULKAN_LAPPEN_AUS_ZU:
				var rn := _vulkan_rinne(ux, uz, d)
				f *= 1.0 - _vulkan_lappen(
					_vulkan_ader(rn.z, d, mr, float(vk["cr"])), d, mr)
		return f * (1.0 - _vulkan_strom(vk, d, ux, uz))
	return 1.0


## BAUMGRENZE DES KEGELS an einer Stelle: 1 = Wald wie ueberall, 0 = kahl.
##
## SIE STEHT ALS EIGENE FUNKTION DA, WEIL ZWEI STELLEN SIE BRAUCHEN und beide dasselbe
## Ergebnis liefern muessen: die Bepflanzung setzt danach ihre Baeume, die Haut faerbt danach
## den Waldboden darunter. Liefen die beiden auseinander, stuenden Baeume auf blankem Basalt
## oder gruener Boden waere baumlos — derselbe Widerspruch zwischen Farbe und Bewuchs, an dem
## in dieser Welt schon die Almwiese und die Schutthalde haengengeblieben sind.
func _vulkan_baumgrenze(x: float, z: float, h: float) -> float:
	return 1.0 - smoothstep(VULKAN_BAUM_AB, VULKAN_BAUM_AUS,
		h - VULKAN_BAUM_ZACK * _patch.get_noise_2d(x * _vk_baum_takt, z * _vk_baum_takt))


## DICHTESOCKEL DES WALDKRAGENS an einer Stelle, 0 bis 1. Draussen ist es eine NULL und
## kostet je Vulkan ein Abstandsquadrat — wie vulkan_bewuchs haengt die Funktion an jeder
## Bewuchszelle der ganzen Welt und muss deshalb frueh abbrechen.
##
## WARUM SIE NICHT IN vulkan_bewuchs MIT DRIN STEHT, obwohl beide dieselbe Baumgrenze lesen:
## vulkan_bewuchs ist ein FAKTOR auf den Bewuchs (es nimmt weg), dieser hier ist ein SOCKEL
## unter der Dichte (er gibt dazu). In einen Wert zusammengefasst muesste er groesser als eins
## werden koennen, und dann traegt derselbe Rueckgabewert auch die Felsdichte und die
## Fernschuerze — beide wuerden stillschweigend mitwachsen.
##
## ZWEI DINGE HAELT ER FEST, und beide sind gemessen (tools/_vulkan_form.gd, "WALDSAUM"):
##   DICHTE  im Kragenband lag die Deckung im Median bei 0.19, weil die Weltdichte das
##           Waldrauschen QUADRIERT. Der Sockel hebt sie auf VULKAN_KRAGEN_DICHT.
##   BIOM    17 von 64 Fussrichtungen sind WUESTE; dort laesst die Weltregel ein Zwanzigstel
##           stehen und sperrt alles ueber 28 m. Der Sockel gilt AUCH dort (siehe die
##           Aufrufer) — sonst hat der Ring genau in diesen Sektoren sein Loch.
## WAS ER NICHT ANTASTET: Hangneigung, Lavastrom, Lappen und die Baumgrenze selbst. Der
## Kragen soll geschlossen sein, wo Wald wachsen kann, und nicht ueberall.
func vulkan_kragen(x: float, z: float, h: float) -> float:
	for vk in _vulkane:
		var dx := x - float(vk["x"])
		var dz := z - float(vk["z"])
		var d2 := dx * dx + dz * dz
		if d2 > float(vk["kr2"]):
			continue
		return vulkan_kragen_bei(vk, x, z, h, sqrt(d2))
	return 0.0


## DERSELBE WERT FUER EINEN AUFRUFER, DER SEINEN VULKAN SCHON GEFUNDEN HAT.
## _face_color laeuft je DREIECK und hat den Abstand zum Kegel in derselben Zeile schon
## ausgerechnet; ein zweiter Durchgang durch _vulkane waere dort geschenktes Geld.
func vulkan_kragen_bei(vk: Dictionary, x: float, z: float, h: float, d: float) -> float:
	var f := _vulkan_baumgrenze(x, z, h)
	if f <= 0.01:
		return 0.0
	# Nach aussen ausblenden, damit der Guertel nicht an einem gezeichneten Kreis endet.
	var mr: float = vk["r"]
	return VULKAN_KRAGEN_DICHT * f * (1.0 - smoothstep(
		mr * VULKAN_KRAGEN_VOLL, mr * VULKAN_KRAGEN_AUS, d))


## HAUT DES KEGELS: Gestein nach Hoehe, erstarrte Stroeme, offene Glut. Die Rueckgabe ist
## die Deckfarbe, und ihr ALPHAKANAL traegt die Glut (siehe Shader in setup): a = 1 ist
## kaltes Gestein, kleinere Werte leuchten aus sich selbst.
## "ny" ist der Aufwaertsanteil der FLAECHENNORMALE dieses Dreiecks. Er kommt von
## _face_color durchgereicht, das ihn ohnehin schon hat — gerechnet wird hier also nichts
## dazu. Wozu er dient, steht bei VULKAN_STEIL_AB: er trennt das blanke Anstehende an der
## Steilkante vom Aschefeld daneben, und er ist die einzige Groesse in dieser Funktion, die
## die FERTIGE Form kennt (alle anderen lesen die Lagen, aus denen sie gebaut wurde).
func _vulkan_haut(vk: Dictionary, cen: Vector3, md: float, ux: float, uz: float,
		ny: float) -> Color:
	var mr: float = vk["r"]
	var cr: float = vk["cr"]
	# Hoehenanteil ueber dem Fuss. IM KRATER GILT ER NICHT: dort faellt das Gelaende wieder
	# bis unter die halbe Gipfelhoehe, und nach der Hoehe allein waere ausgerechnet der
	# Kraterboden rostbraun — die juengste Flaeche des ganzen Berges. Deshalb hebt der
	# Krater den Anteil von innen auf voll, und zwar ueber eine Rampe um den nominellen
	# Kraterradius: die gewachsene Lippe wandert um +-22 Prozent (siehe "lippe"), eine
	# harte Grenze haette dort einen Farbring hinterlassen.
	var t := clampf((cen.y - VULKAN_HAUT_FUSS) / float(vk["hoch"]), 0.0, 1.0)
	t = maxf(t, 1.0 - smoothstep(cr * 0.85, cr * 1.15, md))
	# --- GESTEIN: GRATRUECKEN GEGEN RINNE ----------------------------------------------
	# EXAKT DER AUSDRUCK AUS height_at (siehe RADIALE GRATE), Zeichen fuer Zeichen — sonst
	# liegen die hellen Baender NEBEN den Graten, und ein quer ueber die Flanke gemaltes
	# Streifenmuster ist schlimmer als gar keins. Er steht jetzt hier oben statt nur im
	# Glutzweig, weil beide dasselbe Rauschen lesen: in seinen Rinnen sitzt die Glut, auf
	# seinen Kaemmen das blanke Gestein. Zwei getrennte Abfragen daraus zu machen hiesse,
	# dass die naechste Aenderung an der einen die andere verschiebt.
	var rkr := _vk_rippen_kreis * sqrt(md / mr)
	var lauf := md * VULKAN_RIPPEN_LAUF
	var rip := _ridge.get_noise_3d(ux * rkr, uz * rkr, lauf)
	# DER FEINE KAMM, ZEICHEN FUER ZEICHEN DERSELBE AUSDRUCK WIE IN height_at (siehe
	# FEINRIPPEN) — aus demselben Grund wie beim groben: laege die Aufhellung neben dem
	# Kamm, waere ein quer ueber die Flanke gemaltes Streifenmuster das Ergebnis.
	# "frp" sagt nur, OB dieser Kegel Feinrippen hat; ohne sie kostet die Haut keine
	# zusaetzliche Rauschabfrage und faerbt bitgenau wie ohne diese Lage.
	var feinrip := 0.0
	if bool(vk.get("frp", false)):
		feinrip = _ridge.get_noise_3d(ux * rkr * VULKAN_FEINRIPPE_N,
			uz * rkr * VULKAN_FEINRIPPE_N, md * VULKAN_FEINRIPPE_LAUF)
	var fl := _ridge.get_noise_2d(cen.x * _vk_fels_takt, cen.z * _vk_fels_takt)
	# NACH INNEN AUSBLENDEN, weil es die Grate dort gar nicht gibt: height_at laesst sie erst
	# ab VULKAN_RIPPEN_INNEN anlaufen. Ohne die Huelle laegen im Kraterboden zehn helle
	# Speichen auf einer Flaeche, die in Wahrheit eben ist. Gerechnet wird mit dem NOMINELLEN
	# Kraterradius statt mit der gewachsenen Lippe — auf der Sohle ist das ein Unterschied
	# von wenigen Metern, und dafuer lohnt die Lippenabfrage hier nicht.
	# --- DIE RINNE, IN DER DER PUNKT LIEGT ---------------------------------------------
	# Sie kommt aus DERSELBEN Funktion, mit der height_at die Rinne schneidet — sonst laege
	# die Ader neben ihrer Rinne (siehe _vulkan_rinne). Nur einmal geholt, weil unten die
	# Glut sie noch braucht.
	# rn.x ist null in der Sohle und +-1 auf dem Grat; ohne Barrancos steht hier eine
	# Sohle ueber die ganze Flanke, was den Grat-Term unten zu null macht — der Kegel sieht
	# dann exakt so aus wie vorher.
	# "bhu" ist DIESELBE Huellkurve, mit der height_at die Rinne einblendet: oben am
	# Kraterrand gibt es noch keine Rinne, im Apron keine mehr, und eine Farbe, die dort
	# schon (oder noch) eine zeichnet, ist ein Anstrich ohne Form darunter. Gerechnet wird
	# mit dem NOMINELLEN Kraterradius statt mit der gewachsenen Lippe — dieselbe Abkuerzung
	# wie beim Rippenzweig darueber, auf der Sohle sind das wenige Meter.
	# BEI EINEM KEGEL OHNE BARRANCOS BLEIBT SIE NULL, und damit faellt unten jeder Term
	# weg, der an ihr haengt: kein Grataufhellen, keine Ader. Der Schluessel fehlt, also
	# passiert nichts — dieselbe Zusicherung wie in height_at.
	var rn := Vector3.ZERO
	var bhu := 0.0
	var bprof := 0.0
	if bool(vk.get("bar", false)) and md > cr:
		rn = _vulkan_rinne(ux, uz, md)
		bhu = smoothstep(cr, cr + (mr - cr) * VULKAN_BARR_OBEN, md) \
			* (1.0 - smoothstep(mr * VULKAN_BARR_AUS_AB, mr * VULKAN_BARR_AUS_ZU, md))
		# Dasselbe Querprofil, das height_at als Gelaende schneidet, samt der feinen
		# Oberharmonischen — die Rippchen sollen ihre Kante auch in der Farbe haben.
		bprof = _vulkan_rinne_profil(rn.x, rn.z, md, cr, mr)
	# DER BARRANCO-GRAT GEHT IN DENSELBEN TERM wie die Rippen und nicht als eigene Farbe
	# daneben: blank ist blank, egal welche Lage die Flaeche aufgebrochen hat (dieselbe
	# Begruendung wie bei VULKAN_HAUT_KRUME). Zentriert wie in height_at, damit der Kegel im
	# Mittel gleich hell bleibt und nur der Sprung zwischen Grat und Sohle waechst.
	# OHNE IHN SIEHT MAN DIE RINNEN BEI HOHER SONNE NICHT: das Licht trifft Sohle und Grat
	# dann fast gleich, und 62 m Tiefe auf 170 m Breite kippen die Normale um keine 40 Grad.
	# Die Form macht die Rinne, die Farbe macht sie SICHTBAR.
	# VIER LAGEN HELLEN AUF, ABER NUR ZWEI HABEN FORM UNTER SICH: der Rippenkamm und der
	# Barranco-Grat sind beide EXAKT die Ausdruecke, mit denen height_at das Gelaende
	# aufwirft. Felslage und Grus faerben nur.
	# ALLE VIER STANDEN IN EINER SUMME, und darin lag der Befund "helle graue bis fast weisse
	# Striemen, die den Basalt fleckig aufhellen": die beiden formlosen konnten zusammen 0.45
	# beitragen, also fast die halbe Aufhellung, ohne dass darunter eine Kante lag — und weil
	# die Felslage auf 150 m Welle liegt, waren das grosse weiche Schlieren quer ueber die
	# Oberflanke. Kein Muster der Welt rettet eine Aufhellung, die neben der Form sitzt.
	# JETZT FUEHRT DIE KANTE, und die Koernung haengt an ihr: neben der Kante kommt nur noch
	# VULKAN_HELL_SOCKEL davon durch, auf der Kante wirkt sie unveraendert voll. Damit folgt
	# die Aufhellung den Graten und die beiden Rauschlagen tun wieder das, wofuer sie da sind
	# — ausfransen und koernen.
	# --- DER AUFSCHLUSS UND SEINE STEILKANTE --------------------------------------------
	# WIEDER ZEICHEN FUER ZEICHEN DERSELBE AUSDRUCK WIE IN height_at (siehe DIE BLOCKLAGE),
	# aus demselben Grund wie beim Rippenkamm: laege die Aufhellung neben dem Block, waere
	# ein quer ueber die Flanke gemaltes Fleckenmuster das Ergebnis — schlimmer als gar keins.
	# Nur die aeussere Rampe fehlt hier: die INNERE (ab krx) ist es, die den hellen Ton aus
	# dem fertigen Kraterrand heraushaelt, und gerechnet wird sie wie ueberall in dieser
	# Funktion mit dem nominellen Kraterradius statt mit der gewachsenen Lippe.
	# OHNE DEN SCHLUESSEL "bloecke" BLEIBT ES EINE NULL, und die Haut faerbt bitgenau wie
	# bisher — dieselbe Zusicherung wie bei den Barrancos.
	var block := 0.0
	if bool(vk.get("blk", false)) and md > cr:
		block = smoothstep(VULKAN_BLOCK_AB, VULKAN_BLOCK_VOLL,
				_ridge.get_noise_2d(cen.x * _vk_block_takt, cen.z * _vk_block_takt)) \
			* lerpf(VULKAN_BLOCK_SOHLE, 1.0, rn.x * rn.x) \
			* smoothstep(cr, cr + (mr - cr) * 0.10, md) \
			* (1.0 - smoothstep(mr * VULKAN_BLOCK_AUS_AB, mr * VULKAN_BLOCK_AUS_ZU, md))
	# DAS FEINKORN (13 m) WIRD ZWEIMAL GEBRAUCHT und deshalb einmal geholt: es koernt die
	# Aufhellung (VULKAN_SCHUTT) und es franst den Rand der Aschedecke aus. Eine zweite
	# Abfrage waere in einer Funktion, die je DREIECK ueber den ganzen Kegel laeuft,
	# geschenktes Geld. (Hier stand "dreimal" samt Verweis auf ein VULKAN_GRIES — diese
	# Konstante gibt es nicht mehr, der dritte Gebrauch ist laengst entfallen.)
	var korn := _patch.get_noise_2d(cen.x * _vk_schutt_takt, cen.z * _vk_schutt_takt)
	# DAS SCHUTTFELD (90 m) IST DIESELBE LAGE AUF FELDGROESSE und seit dieser Runde der
	# eigentliche Treiber der Aschedecke — die Begruendung, warum das Korn diese Rolle
	# abgeben musste, steht bei VULKAN_FELD_M. Es wird nur an EINER Stelle gebraucht; es
	# steht trotzdem hier neben dem Korn, weil die beiden zusammen eine Amplitude bilden und
	# wer an der einen dreht, die andere mitlesen muss.
	var feld := _patch.get_noise_2d(cen.x * _vk_feld_takt, cen.z * _vk_feld_takt)
	# DER RIPPENKAMM FUEHRT NICHT MEHR ALLEIN (VULKAN_RIPPEN_HELL, dort steht warum).
	var kante := clampf(VULKAN_RIPPEN_HELL
		* smoothstep(VULKAN_GRAT_AB, VULKAN_GRAT_VOLL, rip)
		* smoothstep(cr * VULKAN_RIPPEN_INNEN * 0.8, cr * VULKAN_RIPPEN_INNEN * 1.7, md)
		+ VULKAN_FEINRIPPE_HELL * smoothstep(VULKAN_FEINRIPPE_AB, VULKAN_FEINRIPPE_VOLL,
			feinrip)
		+ VULKAN_BARR_HELL * bhu * rn.y * bprof
		+ VULKAN_BLOCK_HELL * block
		+ VULKAN_STEIL_HELL * (smoothstep(VULKAN_STEIL_AB, VULKAN_STEIL_VOLL, ny)
			- VULKAN_STEIL_MITTE), 0.0, 1.0)
	# DIE KOERNUNG SITZT JETZT AUF DER ABRISSSTUFE, ZEICHEN FUER ZEICHEN DIESELBE, die
	# height_at auftraegt (siehe VULKAN_NASEN_AB): der gehobene Absatz ist abgeblasen und
	# blank, die Stufe darunter haelt Feinasche. Vorher stand hier der ROHE Rauschwert
	# derselben Lage — eine weiche Welle ohne Form darunter, und genau als solche ist sie
	# zweimal als "helle Striemen" gemeldet worden. Der Unterschied ist nicht die Staerke,
	# sondern dass es jetzt eine Kante gibt, der sie folgen kann.
	# DER NULLPUNKT LIEGT NICHT IN DER MITTE DER STUFE, SONDERN BEI VULKAN_GRUS_MITTE, und
	# das ist der Unterschied zwischen "gestaffelt" und "aufgehellt": bei 0.5 haette die
	# Koernung ebenso viel Flaeche aufgehellt wie abgedunkelt, und weil unter dem Basalt kein
	# Platz nach unten ist (er ist schon fast schwarz), waere davon nur die Aufhellung
	# uebriggeblieben — gerechnet 0.329 Bildmittel gegen 0.303 vorher, also heller statt
	# dunkler. Mit 0.70 bleibt der groessere Teil der Flanke im Basalt stehen und nur der
	# abgeblasene Absatz kommt heraus.
	# EXAKT DAS FENSTER, MIT DEM height_at DIE STUFE SCHNEIDET (VULKAN_NASEN_AB) — Zeichen
	# fuer Zeichen, aus demselben Grund wie bei Rippenkamm und Blocklage: laege die
	# Aufhellung neben der Stufe, waere sie wieder das quer ueber die Flanke gemalte
	# Fleckenmuster, das hier schon zweimal als "helle Striemen" gemeldet worden ist.
	# ES WAR EIN UMWEG PROBIERT UND VERWORFEN: ein eigenes, engeres Farbfenster weiter oben
	# auf demselben Rauschen ("blank geblasen ist nur die oberste Kuppe des Absatzes"). Das
	# klingt plausibel und war gemessen schlechter — mit 0.10/0.42 statt des Formfensters
	# fiel der Nachbarsprung von 0.0349 auf 0.0290, weil die helle Flaeche dann nicht mehr
	# mit der Kante zusammenfaellt, sondern als eigenes, groeberes Muster darauf liegt.
	# Welcher Anteil hell wird, steuert VULKAN_GRUS_MITTE — der Nullpunkt, nicht das Fenster.
	var stufe := smoothstep(VULKAN_NASEN_AB, VULKAN_NASEN_VOLL,
		_patch.get_noise_2d(cen.x * _vk_grus_takt, cen.z * _vk_grus_takt))
	# ZWEI KOERNUNGEN MIT VERSCHIEDENEM RECHT, und die Trennung ist der Kern dieser Runde.
	# Die alte Regel war "beide formlosen Lagen duerfen neben einer Kante nur den Sockel"
	# (VULKAN_HELL_SOCKEL) — richtig, solange BEIDE formlos waren. Die Grusslage ist es nicht
	# mehr: sie liest jetzt exakt die Abrissstufe, die height_at ins Gelaende schneidet, und
	# darf deshalb voll durch. Die Felslage (150 m Welle, nur mit sv gewichtet) hat auf der
	# Unterflanke nach wie vor kaum Form unter sich und bleibt am Sockel.
	var koern := VULKAN_GRUS * (stufe - VULKAN_GRUS_MITTE) * 2.0 + VULKAN_SCHUTT * korn
	var schlier := VULKAN_HAUT_KRUME * (fl - VULKAN_KRUME_MITTE)
	# DIE KOERNUNG UND DIE KANTE WERDEN GETRENNT AUFGETRAGEN, und das ist der Griff dieser
	# Runde. Bisher standen beide in EINER Summe "blank" und mischten auf DENSELBEN hellen
	# Ton — mit dem Ergebnis, dass der Ton so dunkel gewaehlt werden musste, wie es die
	# formlose Haelfte vertrug (sonst "helle Striemen"), und damit war er auch fuer die
	# Kante zu dunkel. Gemessen kam der Kegel deshalb ueber eine Albedospanne vom ersten
	# zum dritten Viertel von nur 0.0053 auf 0.0080 (linear) — praktisch einfarbig, und aus
	# einer einfarbigen Flanke kann keine Beleuchtung der Welt Kontrast machen.
	# JETZT HAT JEDE LAGE IHREN EIGENEN TON: die Koernung hellt wie bisher nur bis
	# Grat/Asche auf, die Kante geht bis zum Anstehenden (VULKAN_ANSTEHEND). Der Sprung
	# zwischen Flaeche und Abriss wird damit rund fuenfmal so gross, ohne dass irgendwo
	# aufgehellt wird, wo keine Form liegt.
	# "blank" ist wie eh und je die Gesamtaufhellung auf den mittleren Ton (Grat/Asche); daran
	# haengt auch die Deckung des Rosts weiter unten.
	# ES WAR EIN FEHLER, DIE KANTE HIER HERAUSZUNEHMEN, und der Renderlauf hat ihn gezeigt:
	# fuer einen Zwischenstand lief nur noch die Koernung auf den mittleren Ton und die Kante
	# allein auf den hellen. Gemessen fiel die Streuung im Bild damit von 0.0141 auf 0.0099,
	# obwohl die hellsten Facetten deutlich heller wurden (99. Perzentil 0.775 gegen 0.384) —
	# der Kontrast sass danach in zwei Prozent der Flaeche, und 98 Prozent standen als
	# gleichmaessig dunkle Masse da. Die Kante muss BEIDES fuehren: den mittleren Ton auf der
	# ganzen Flanke und den hellen an ihrer Spitze.
	# DAS GILT NUR NOCH ALS BEFUND, NICHT MEHR ALS BAUART: seit der Aschedecke (gleich
	# darunter) faerbt "kante" gar nicht mehr selbst. Der Schluss daraus bleibt aber richtig
	# und ist der Grund, warum die Decke ein TOR und keine dritte Aufhellung ist — Kontrast,
	# der in zwei Prozent der Flaeche sitzt, ist im Bild keiner.
	# --- DIE ASCHEDECKE: WAS FLACH LIEGT, IST ZUGEWEHT --------------------------------
	# SIE IST DER UNTERSCHIED ZWISCHEN ABZIEHEN UND ZUDECKEN, und daran haengt diese Runde.
	# Die Steilheit stand hier schon als SUMMAND in "kante" (VULKAN_STEIL_HELL): sie macht die
	# flache Facette dunkler, aber jede andere Lage — Feinrippe, Blocklage, Grus — kann sie
	# daneben wieder aufhellen. Gemessen (tools/_vulkan_fein.gd) lagen deshalb nur rund zehn
	# Prozent der Flanke wirklich auf dem Basaltgrund, der ganze Rest trug ueberall ein
	# bisschen Aufhellung: Bildmedian 0.298 bei einem Nebelsockel von 0.258. Eine Flanke, auf
	# der fast jede Facette ein wenig hell ist, hat einen hohen Mittelwert und trotzdem keinen
	# Sprung zwischen Nachbarn — genau der Befund "dunkel UND glatt".
	# ALS FAKTOR IST ES EINE ENTSCHEIDUNG STATT EINER MISCHUNG: wo Feinasche liegen bleibt,
	# liegt sie ueber ALLEM, was darunter ist, und die Facette ist schwarz. Nur wo der Hang zu
	# steil dafuer ist, steht ueberhaupt Gestein an — und dort steht es dann ganz.
	# DIE LAGEN SIND DAMIT NICHT ARBEITSLOS, sie sind eine Stufe weiter nach vorn gerueckt:
	# sie verziehen die Schwelle der Decke (VULKAN_DECKE_LAGEN), entscheiden also weiter, WO
	# blanker Fels steht — nur nicht mehr, wie hell er ist.
	# DAS FELD ENTSCHEIDET, DAS KORN FRANST AUS — und diese Reihenfolge ist der Griff dieser
	# Runde. Ohne jeden Jitter faellt die Decke mit einer festen Schwelle auf die
	# Flaechennormale, und weil die Normale ueber eine Rippenflanke langsam kippt, waere ihr
	# Rand eine gezeichnete Linie quer ueber jede Rippe. Trug den Jitter aber das 13-m-Korn
	# allein, dann wechselte die Decke von NACHBAR zu NACHBAR, und blanker Fels stand als
	# einzelne Sprenkel statt als Feld (Zahlen und Begruendung bei VULKAN_FELD_M).
	var decke := smoothstep(VULKAN_DECKE_AB, VULKAN_DECKE_ZU,
		ny + VULKAN_DECKE_FELD * feld + VULKAN_DECKE_KORN * korn
		- VULKAN_DECKE_LAGEN * kante)
	# DER TON IST JETZT ZWEIWERTIG: blanker Fels oder Basalt unter Asche, und nichts dazwischen
	# (Begruendung bei VULKAN_DECKE_LAGEN und VULKAN_DECKE_AB). "kante" hat damit die Rolle
	# gewechselt — sie steht oben als Neigung zum Blankliegen in den Treiber der Decke ein und
	# traegt hier unten nur noch weiter, WAS die Decke entschieden hat.
	var frei := 1.0 - decke
	kante = frei
	var blank := clampf(kante + koern
		+ schlier * (VULKAN_HELL_SOCKEL + (1.0 - VULKAN_HELL_SOCKEL) * kante), 0.0, 1.0) * frei
	# WIE JUNG DIE ASCHE HIER IST. Eine Zahl, zwei Aufgaben, und sie haengen zusammen: oben
	# liegt frischer Auswurf, der ist dunkel und traegt noch keinen Rost; unten ist der Fels
	# abgerieben und verwittert. Bisher drosselte diese Rampe NUR den Rost, und genau deshalb
	# stand der helle Grat ganz oben voellig ungedaempft da (siehe VULKAN_ASCHE).
	var asche := smoothstep(VULKAN_ASCHE_AB, VULKAN_ASCHE_VOLL, t)
	# DIE STAFFEL: AUS DER MISCHUNG WIRD EINE STUFE. "blank" lief bisher DIREKT als
	# Mischanteil in die Farbe, und damit war die Flanke ein Verlauf von Schwarz nach Grau —
	# gemessen lagen ihre mittleren Bildwerte dicht gedraengt zwischen 0.27 und 0.36, also
	# ueberall ein bisschen hell und nirgends ein Sprung. Fuer den Mittelwert zahlt man
	# solche Zwischentoene voll, fuer die Streuung bekommt man fast nichts: bei festem Mittel
	# haengt die Streuung daran, WIE VIELE Facetten hell sind, nicht wie hell die Mitte ist.
	# Die Vorlage kennt diese Mitte nicht — dort steht schwarzer Basalt neben hellem
	# Anstehendem, mit rostroten Baendern darueber, und daher kommt ihre Streuung.
	# Die Kurve schiebt die Mitte deshalb auseinander: unter VULKAN_STAFFEL_AB bleibt die
	# Facette Basalt, ueber VULKAN_STAFFEL_VOLL traegt sie den vollen Gesteinston.
	var haut := VULKAN_BASALT.lerp(VULKAN_GRAT.lerp(VULKAN_ASCHE, asche),
		smoothstep(VULKAN_STAFFEL_AB, VULKAN_STAFFEL_VOLL, blank))
	# UND DARUEBER DAS ANSTEHENDE. Die Hoehenrampe "asche" fasst es NICHT an, und das ist
	# Absicht: dass frischer Auswurf oben dunkler ist als abgeriebener Fels unten, gilt fuer
	# die FLAECHE — ein frischer Abriss legt in jeder Hoehe dasselbe Gestein frei. Genau
	# umgekehrt war es vorher, und weil der Messkasten der Abnahme auf der OBERflanke sitzt,
	# stand dort als hellster Ton die dunkle Asche.
	# UND ER KOMMT ERST UEBER EINER SCHWELLE (VULKAN_ANSTEHEND_AB, dort steht warum).
	haut = haut.lerp(VULKAN_ANSTEHEND, smoothstep(VULKAN_ANSTEHEND_AB, 1.0, kante))
	# --- ROSTFLECKEN --------------------------------------------------------------------
	# Sie liegen UEBER dem Gestein statt an seiner Stelle: oxidiert wird, was schon da ist.
	# Auf dem blanken Grat bleibt weniger haengen als in der windgeschuetzten Rinne, deshalb
	# nimmt die Deckung mit blank ab — aber nur um ein Drittel und nicht, wie zuerst
	# eingestellt, um die Haelfte: in der Vorlage sind ausgerechnet die hellsten Ruecken oft
	# rotbraun ueberlaufen (gemessen 0.45/0.33/0.31 gegen 0.37/0.34/0.31 daneben), der Rost
	# meidet den Grat also nicht, er deckt dort nur duenner. Nach oben hin wird er weniger:
	# dort ist die Asche jung.
	var rost := smoothstep(VULKAN_ROST_AB, VULKAN_ROST_VOLL,
		_patch.get_noise_2d(cen.x * _vk_rost_takt, cen.z * _vk_rost_takt))
	if rost > 0.004:
		# ... UND ER LIEGT IN DER RINNE (VULKAN_ROST_GRAT, dort steht warum). "bprof +
		# VULKAN_BARR_MITTE" ist das Querprofil OHNE seine Zentrierung, also null in der
		# Sohle und eins auf dem Grat — dieselbe Kurve, die height_at schneidet, nur eine
		# Zeile weiter unzentriert gelesen. Ausserhalb des Rinnenbandes ist bhu null und der
		# Faktor damit eins: am Kraterrand und im Apron aendert sich nichts.
		var rippe := clampf(bhu * rn.y * (bprof + VULKAN_BARR_MITTE), 0.0, 1.0)
		haut = haut.lerp(VULKAN_ROST, rost * VULKAN_ROST_STAERKE * (1.0 - 0.26 * blank)
			* lerpf(1.0, VULKAN_ROST_GRAT, rippe) * (1.0 - 0.62 * asche))
	var strom := _vulkan_strom(vk, md, ux, uz)
	if strom > 0.004:
		haut = haut.lerp(VULKAN_STROM, strom)
	# --- DAS LAVANETZ: KRUSTE UND LAPPEN --------------------------------------------------
	# ERST DAS SCHWARZE, DANN DAS ORANGE, und zwar in dieser Reihenfolge und mit Abstand:
	# das Netz ist bis in die Ebene hinunter als erstarrtes Geaest da, offen glueht nur sein
	# Kern. Vorher folgte die Kruste der BARRANCO-Sohle und war deshalb ueberall dort, wo
	# eine Rinne war — also ein durchgehender dunkler Streifen je Rinne. Jetzt folgt sie der
	# ADER: sie zeichnet die Verzweigung mit, auch da, wo laengst nichts mehr leuchtet, und
	# genau daran liest man ein Netz als Netz.
	# ad/netz/lappen werden HIER geholt und nicht erst im Glutzweig, weil der Waldkragen
	# darunter sie braucht: auf einem frischen Lavalappen steht kein Baum.
	var ad := Vector3.ZERO
	var netz := 0.0
	var lappen := 0.0
	if rn.y > 0.0:
		ad = _vulkan_ader(rn.z, md, mr, cr)
		var kw := ad.y * VULKAN_ADER_KRUSTE
		netz = (1.0 - smoothstep(kw * 0.42, kw, ad.x)) \
			* smoothstep(cr, cr * 1.10, md) \
			* (1.0 - smoothstep(mr * VULKAN_LAPPEN_AUS_AB, mr * VULKAN_LAPPEN_AUS_ZU, md))
		lappen = _vulkan_lappen(ad, md, mr)
		if netz > 0.004 or lappen > 0.004:
			haut = haut.lerp(VULKAN_STROM, maxf(netz, lappen))
	# --- WALDKRAGEN AM FUSS --------------------------------------------------------------
	# Wo Baeume stehen, ist der Boden Waldboden und nicht Basalt (Begruendung bei
	# VULKAN_KRAGEN). Gelesen wird DIESELBE Maske wie in der Bepflanzung: die Baumgrenze des
	# Kegels und der Strom, den diese Funktion ohnehin schon ausgerechnet hat — auf frischer
	# Lava steht kein Baum und liegt also auch kein Waldboden.
	# _boden_farbe kostet ein paar Rauschabfragen und laeuft deshalb NUR im Kragen: das ist der
	# Ring zwischen Fussschwelle (26 m) und Baumgrenze (68 m), also die unteren sieben Prozent
	# der Flankenhoehe. Gemessen traegt der Kegel darin gut ein Zehntel seiner Flaeche Wald
	# (tools/_vulkan_form.gd); alles darueber faellt an der Schranke ab, ohne _boden_farbe
	# auch nur anzufassen.
	# DER LAPPEN GEHOERT MIT IN DIESE MASKE, aus demselben Grund wie der Strom: er liegt
	# genau in der Hoehenlage des Kragens, und ein Waldboden mit Nadelbaeumen auf frischer
	# Lava ist der Widerspruch zwischen Farbe und Bewuchs, an dem in dieser Welt schon
	# Almwiese und Schutthalde haengengeblieben sind. Die Bepflanzung liest dieselbe Maske
	# (vulkan_bewuchs).
	var kragen := _vulkan_baumgrenze(cen.x, cen.z, cen.y) * (1.0 - strom) * (1.0 - lappen)
	if kragen > 0.01:
		# DER SOCKEL MUSS MIT (dritter Parameter): auch auf dem Kegel liegen Wuestensektoren,
		# und ohne ihn holt _boden_farbe dort helle Duenenfarbe unter den Waldkragen.
		# QUADRIERT, und das ist der Unterschied zwischen einem Waldrand und einem gruenen
		# Hauch: der Waldboden folgte der Baumgrenze LINEAR, lag also auf halbem Uebergang noch
		# mit 40 Prozent auf dem Basalt — im Bild ein gruener Schleier, der den Fuss hinauflief,
		# waehrend oben laengst keine Baeume mehr standen. Der Boden faerbt sich jetzt nur da,
		# wo der Bestand wirklich geschlossen ist; am ausduennenden Rand stehen einzelne
		# Fichten auf schwarzem Fels, und genau so zeigt es die Vorlage.
		haut = haut.lerp(_boden_farbe(cen, 0.0, kragen * VULKAN_KRAGEN_DICHT),
			kragen * kragen * VULKAN_KRAGEN)
	# --- GLUT: DER OFFENE KERN DES KANALS -------------------------------------------------
	# WAS HIER VORHER STAND UND WARUM ES WEG IST — zweimal hintereinander dieselbe Falle:
	# Zuerst war die Glut eine Schwelle auf dem Rippenrauschen, dessen Abtastkreis nur mit
	# der Wurzel des Abstands waechst: oben schnitt sie einen 300 m breiten Lappen heraus,
	# und im Bild lagen flaechige orange Flecken OBEN AUF der Flanke.
	# Dann war sie eine Schwelle auf einer reinen Richtungsfunktion, und heraus kamen acht
	# gleich breite, zueinander parallele, unverzweigte Baender, die alle am Kraterrand
	# ansetzten und auf halber Flanke im Nichts endeten. EINE SCHWELLE AUF EINEM WINKEL KANN
	# NICHTS ANDERES ERZEUGEN: sie hat keinen Begriff von "derselbe Strom weiter unten" und
	# also auch keinen von einer Gabelung.
	# JETZT IST ES EIN BAUM (_vulkan_ader), und die Masken haben klar getrennte Aufgaben:
	#   netz   WO ein Kanal ist — der Baum selbst, samt seiner schwarzen Kruste.
	#   hh     OB dort noch etwas offen ist. Laeuft bis an den Waldrand hinunter.
	#   heiss  WIE HEISS es ist: hellorange oben, tiefrot unten (Farbe UND Leuchtkraft).
	#   ad.z   WIE STARK dieser eine Ast ist — an einer Gabel wird ein Arm heller als der
	#          andere, und das unterscheidet ein Geflecht von einem Ornament.
	#   seite  welche SEITE des Berges ueberhaupt schuettet. Daempft nur noch (0.34), statt
	#          abzuschneiden: eine Ader wandert beim Gabeln ueber Sektorgrenzen hinweg.
	# DER LAPPEN LOESCHT DIE GLUT (1 - lappen): dort ist der Strom angekommen und erstarrt.
	# Genau das ist der Abschluss, der der Ader vorher gefehlt hat — sie hoerte auf, statt
	# irgendwo anzukommen.
	var glut := 0.0
	var hh := smoothstep(VULKAN_GLUT_UNTEN, VULKAN_GLUT_OBEN, t)
	if hh > 0.004 and netz > 0.004:
		var seite := lerpf(VULKAN_GLUT_SEITE, 1.0,
			smoothstep(VULKAN_GLUT_AB, VULKAN_GLUT_VOLL,
				_ridge.get_noise_2d(ux * _vk_glut_kreis, uz * _vk_glut_kreis)))
		# UNTERBRECHUNG DER LAENGE NACH. Das Rauschen laeuft schnell den Hang HINUNTER und
		# nur langsam um ihn herum — es laesst den Kanal streckenweise ueberkrusten, statt
		# ihn zu verbreitern. Es DARF IHN NICHT MEHR DURCHSCHNEIDEN (VULKAN_ADER_GRUND):
		# eine Ader, die alle 200 m aussetzt, ist wieder eine Reihe von Strichen.
		var schnitt := smoothstep(VULKAN_ADER_AB, VULKAN_ADER_VOLL,
			_ridge.get_noise_3d(ux * _vk_ader_kreis, uz * _vk_ader_kreis,
				md * VULKAN_ADER_LAUF))
		glut = hh * seite * ad.z * netz * (1.0 - lappen) \
			* (1.0 - smoothstep(ad.y, ad.y * VULKAN_ADER_SAUM, ad.x)) \
			* lerpf(VULKAN_ADER_GRUND, 1.0, schnitt)
	# --- DER KESSEL: INNENWAND UND LAVASEE ------------------------------------------------
	# WARUM DIE INNENWAND EINE EIGENE FARBE BRAUCHT, steht bei VULKAN_KESSEL: der Krater hebt
	# den Hoehenanteil von innen auf voll, damit die Sohle nicht rostbraun wird — und danach
	# tragen Innenwand und Aussenflanke dieselbe Haut. Im Abnahmebild war der Kessel deshalb
	# ein mittelgraues Becken, in dem 340 m Tiefe verschwanden.
	var kessel := smoothstep(cr * VULKAN_KESSEL_AB, cr * VULKAN_KESSEL_VOLL, md)
	if kessel > 0.004:
		haut = haut.lerp(VULKAN_KESSEL, kessel * VULKAN_KESSEL_DECK)
		# DER LAVASEE. Schwarze Kruste mit gluehenden Fugen, nicht eine orange Scheibe —
		# warum, steht bei VULKAN_SEE_KRUSTE. Die Ufergrenze ist DIESELBE wie die, an der
		# height_at den Spiegel flachzieht (VULKAN_SEE_R/_UFER), sonst laege der Glanz
		# neben dem Wasser.
		var seek := 1.0 - smoothstep(cr * VULKAN_SEE_R,
			cr * (VULKAN_SEE_R + VULKAN_SEE_UFER), md)
		if seek > 0.004:
			haut = haut.lerp(VULKAN_SEE_KRUSTE, seek)
			glut = maxf(glut, seek * smoothstep(VULKAN_SEE_FUGE_AB, VULKAN_SEE_FUGE_VOLL,
				_ridge.get_noise_2d(cen.x * _vk_see_takt, cen.z * _vk_see_takt)))
	# DER SCHLUND. Aussen schwarz, im Kern offen — siehe VULKAN_SCHLUND.
	if md < cr * VULKAN_SCHLUND:
		var sk := 1.0 - smoothstep(cr * VULKAN_SCHLUND_KERN, cr * VULKAN_SCHLUND, md)
		haut = haut.lerp(VULKAN_STROM, sk)
		glut = maxf(glut, 1.0 - smoothstep(cr * VULKAN_SCHLUND_KERN * 0.45,
			cr * VULKAN_SCHLUND_KERN, md))
	if glut > 0.004:
		# DIE ABKUEHLUNG. Der Schlund steht auf t = 1 (der Krater hebt den Hoehenanteil von
		# innen auf voll, siehe oben) und bleibt damit hellorange; die Ader kuehlt auf ihrem
		# Weg nach unten ab. BEIDES ZUGLEICH, Farbe und Leuchtkraft: eine tiefrote Flaeche,
		# die so hell strahlt wie eine orange, liest sich nicht als kuehler, sondern als
		# andersfarbig — und weil der Shader die EIGENE Farbe zum Leuchten bringt, sind die
		# beiden Zeilen zwei Seiten derselben Sache.
		var heiss := smoothstep(VULKAN_GLUT_KUEHL, VULKAN_GLUT_HEISS, t)
		haut = haut.lerp(VULKAN_LAVA_KALT.lerp(VULKAN_LAVA, heiss), glut)
		haut.a = 1.0 - glut * lerpf(VULKAN_GLUT_MATT, 1.0, heiss)
	return haut


func _face_color(cen: Vector3, ny: float) -> Color:
	# GEDÄMPFTE, erdig-pastellige Low-Poly-Palette (Aviassembly-Look): Sage-Grün,
	# warmer Sand, staubiges Rosé/Lavendel, warmer Fels — nichts grell.
	if cen.y < SEA_Y + 1.6:
		return Color(0.93, 0.85, 0.62)        # heller, warmer Sandstrand/Ufer
	# --- BERGSEE: KIESSAUM ------------------------------------------------------------
	# Die ALMWIESE stand frueher in dieser Schleife und hing am Uferabstand. Sie ist
	# umgezogen (_tal_wiese, weiter oben) — hier bleibt nur der Kies, und der GEHOERT ans
	# Ufer.
	# ZUERST DER ABSTAND (nur Quadrate, keine Wurzel): die Funktion laeuft je DREIECK,
	# 4608-mal pro Chunk ueber die ganze Welt, und fast immer liegt die Stelle draussen.
	var kies := 0.0
	for lk in lakes:
		if not lk.has("_rad"):
			continue
		var lp: Vector3 = lk["pos"]
		var kx := cen.x - lp.x
		var kz := cen.z - lp.z
		var kr: float = float(lk["_rmax"]) + 120.0
		var kd2 := kx * kx + kz * kz
		if kd2 > kr * kr:
			continue
		var wsp: float = float(lk["surf"])
		if cen.y > wsp + 4.0 or cen.y < wsp - 6.0:
			continue
		# ABSTAND ZUR UFERLINIE, nicht zum Seemittelpunkt. Ohne das faerbte sich auch das
		# Bachbett des Abflusses hell — es liegt im selben Hoehenband und im selben Umkreis,
		# und im Bild lief ein leuchtender Streifen schnurgerade vom See talabwaerts.
		var ach: Vector2 = lk["_achse"]
		var uw := _see_umriss(lk, atan2(kx * ach.y - kz * ach.x, kx * ach.x + kz * ach.y))
		var ds := sqrt(kd2) - uw.x
		# KIESSAUM: heller Schotter AN DER WASSERLINIE — ein Strand, kein Beckengrund.
		# ER REICHTE VORHER BIS 6 M UNTER WASSER, also am flachen Ufer 143 m weit ins
		# Becken hinein, und genau das war der Befund der Kritik: der Untiefensaum las sich
		# als milchig-cremeweisser Ring statt als tuerkises Band. Ursache war nicht die
		# Wasserfarbe, sondern der Grund darunter — bei alpha_shallow schaut man in den
		# Untiefen zu ueber der Haelfte auf den Boden, und der war weiss.
		# Jetzt liegt er zwischen 1,6 m Tiefe und 3 m ueber dem Spiegel. Das Wasser bekommt
		# seine Untiefen zurueck, der Strand bleibt der hellste Fleck des Talbodens.
		# NUR AM FLACHEN UFER. Ohne die Kopplung an den Uferhang lag der helle Saum als
		# gleichmaessig breiter Ring rund um den See — bei 8 m Netzweite ist das eine
		# Dreiecksreihe, und im Bild sah der See aus wie ein Planschbecken mit gemaltem Rand.
		# Am steilen Ufer durchlaeuft das Gelaende dasselbe Hoehenband auf 8 m Grundriss,
		# der Saum darf dort also gar nicht erst anfangen.
		# An allen Enden ausblenden, sonst steht eine gezeichnete Hoehenlinie im Bild.
		# IN DER SCHARTE GILT DER STEILHANG-VORBEHALT NICHT, und der aeussere Saum reicht
		# weiter. WARUM: der Abfluss liegt bei 151 Grad, dort ist der Uferhang 0.19 — ueber
		# der Schranke, also blieb die Kiesbank hinter der Schwelle GRUEN. Genau das war der
		# Befund: tuerkise Uferkante, dann Gras, dann faengt das blaue Band an. Ein See
		# laeuft aber ueber Schotter aus, nicht ueber eine Wiese. maxf statt Multiplikation,
		# damit die Scharte den Vorbehalt aufhebt statt ihn zu daempfen, und die aeussere
		# Ausblendung wandert mit der Gasse von 32/52 auf 62/86 m — das deckt Schwelle und
		# Bank (16 + 40 m) ganz ab, am Zufluss den Schuttfaecher.
		# "offen" ist der Anteil, mit dem der Beckenrand hier eine Gasse ist: die Scharte des
		# Abflusses (uw.w) ODER das Delta des Zuflusses. Das Delta hat keinen eigenen Kanal in
		# der Umrisstabelle und braucht auch keinen — es ist an der niedrigen RANDHOEHE
		# eindeutig zu erkennen (0,9 m gegen sonst mindestens 4 m, siehe _see_wandhoehe).
		var offen := maxf(uw.w, 1.0 - smoothstep(1.4, 3.0, uw.z))
		var kaus := lerpf(32.0, 62.0, offen)
		if ds > -60.0 and ds < kaus + 24.0:
			kies = smoothstep(wsp - 1.6, wsp - 0.5, cen.y) \
				* (1.0 - smoothstep(wsp + 1.4, wsp + 3.2, cen.y)) \
				* smoothstep(-60.0, -42.0, ds) * (1.0 - smoothstep(kaus, kaus + 24.0, ds)) \
				* maxf(1.0 - smoothstep(0.07, 0.16, uw.y), offen)
		break
	# --- VULKAN: GESTEIN, LAVAZUNGEN, GLUT --------------------------------------------
	# Der Kegel bekommt seine Haut (siehe _vulkan_haut) statt Fels und Schnee — sonst
	# stuende dort ein weisser Marshmallow. Sein STROM reicht darueber hinaus und wird
	# NICHT zurueckgegeben, sondern unten ueber die gewachsene Farbe gelegt: was jenseits
	# des Fusses liegt, ist Wiese mit einem schwarzen Band darauf und nicht Vulkan.
	# Vorfilter zuerst und nur Quadrate — die Funktion laeuft je DREIECK ueber die ganze
	# Welt, und fast jede Stelle liegt draussen.
	var strom := 0.0
	var kragen := 0.0
	var asche := Vector3.ZERO
	var asche_hub := 0.0
	for vk in _vulkane:
		var vdx := cen.x - float(vk["x"])
		var vdz := cen.z - float(vk["z"])
		var vd2 := vdx * vdx + vdz * vdz
		if vd2 > float(vk["reich2"]):
			continue
		var vd := sqrt(vd2)
		var vux := 0.0
		var vuz := 0.0
		if vd > 1.0:
			vux = vdx / vd
			vuz = vdz / vd
		if cen.y > VULKAN_HAUT_FUSS and vd < float(vk["haut_r"]):
			return _vulkan_haut(vk, cen, vd, vux, vuz, ny)
		strom = _vulkan_strom(vk, vd, vux, vuz)
		# DIE ASCHESCHUERZE. Sie faengt genau dort an, wo die Haut aufhoert ("haut_r" ist
		# dieselbe Zahl, siehe VULKAN_APRON_ASCHE_AB) und laeuft ueber den Faecher aus. Sie
		# wird NICHT hier aufgetragen, sondern unten ueber die gewachsene Farbe gelegt —
		# genau wie der Lavastrom, und aus demselben Grund: was hier draussen liegt, ist
		# Vorland mit Asche darauf und nicht Vulkan.
		asche = _vulkan_apron(vk, cen.x, cen.z, cen.y, vd, vux, vuz)
		# AUF DER SCHUERZE GILT DIE FELSSCHWELLE DER WELT NICHT (Begruendung bei
		# VULKAN_APRON_FELS_HUB). Die Schleife laeuft nur bis zum Saum der Schuerze
		# ("reich2"), die Zeile wirkt also genau dort und sonst nirgends; ohne Schuerze ist
		# "apr" null und der Hub bleibt null.
		if float(vk["apr"]) > 0.0:
			asche_hub = VULKAN_APRON_FELS_HUB
		# DER WALDKRAGEN REICHT UEBER DIE HAUT HINAUS, also bis in das Vorland vor dem Fuss
		# (siehe vulkan_kragen). Dort faerbt nicht mehr _vulkan_haut, sondern _boden_farbe —
		# und die kennt nur das Biom. Gemessen sind 17 von 64 Fussrichtungen WUESTE: ohne
		# diese Zeile stuende der Guertel dort als geschlossener Fichtenwald auf hellem
		# Duenensand, und das ist derselbe Widerspruch zwischen Farbe und Bewuchs, an dem hier
		# schon Almwiese und Schutthalde haengengeblieben sind.
		# (1 - strom), weil auf dem erstarrten Band ohnehin kein Baum steht — und aus
		# demselben Grund (1 - asche.x): auf dem blanken Faecher steht auch keiner. Beides
		# liest die Bepflanzung genauso (vulkan_bewuchs), sonst faerbte sich hier Waldboden
		# unter einer Flaeche, auf der kein Baum wachsen darf.
		kragen = vulkan_kragen_bei(vk, cen.x, cen.z, cen.y, vd) \
			* (1.0 - strom) * (1.0 - asche.x)
		break
	# --- FELS UND SCHNEE, DURCHGEHEND OHNE STUFE -----------------------------------
	# Hier standen ZWEI getrennte Zweige mit harten Grenzen bei 160 und 188 m. Der untere
	# blendete zwischen 160 und 188 m auf flachem Grund bis fast auf Schneeweiss hoch, der
	# obere fing darueber wieder bei dunklem Fels an. Solange 188 m die Bergspitze war, war
	# das ein schmaler Gipfelsaum. Mit Bergen bis 1250 m ist es eine WEISSE HOEHENLINIE
	# quer durch jeden Hang — genau der Strich, der gemeldet wurde.
	# GESUCHT HABE ICH IHN ZUERST AN DER FALSCHEN STELLE: Fernschuerze, Wasserplatte und
	# Wolken einzeln ausgeblendet, der Strich blieb in allen drei Bildern stehen. Er kam
	# aus dem Gelaende selbst.
	# Jetzt EINE durchgehende Felsrampe ueber die ganze Hoehe und EIN Schneeanteil, der
	# nach Hoehe einblendet und vom Hang moduliert wird. Keine Sprungstelle mehr.
	var fels := Color(0.35, 0.31, 0.27).lerp(Color(0.56, 0.52, 0.46),
		clampf((cen.y - 52.0) / 90.0, 0.0, 1.0))
	if cen.y > 142.0:
		# Weiter aufhellen, statt bei 142 m stehenzubleiben — die Fortsetzung setzt genau
		# auf dem Endwert der ersten Rampe auf, deshalb entsteht kein Sprung.
		fels = fels.lerp(Color(0.62, 0.60, 0.58), clampf((cen.y - 142.0) / 400.0, 0.0, 1.0))
	# SCHNEE. Massgeblich ist die Hoehe UEBER der Schneegrenze, der Hang moduliert nur.
	# Der Hang allein reicht NICHT: die Kegel des Hochgebirges sind bei 2200 m Radius und
	# 1250 m Gipfel rund 30 Grad geneigt, darauf liegt auch in echt Schnee — mit reinem
	# Hangkriterium blieb die ganze Kette weiss.
	var schnee := smoothstep(188.0, 428.0, cen.y) * smoothstep(0.72, 0.90, ny)
	if schnee > 0.001:
		fels = fels.lerp(Color(0.87, 0.88, 0.91), schnee)
	if cen.y > 188.0:
		# DER UEBERZUG MUSS AUCH AUF DIESEM WEG MIT. Hier stand ein blankes "return fels",
		# und das war der letzte helle Streifen auf der Ascheschuerze — gefunden hat ihn erst
		# ein Strahl durch den Bildpunkt (tools/_vulkan_stich.gd): das Vorland steigt in
		# einigen Sektoren schon von sich aus auf 150 m, die Schuerze legt bis zu 93 m
		# darauf, und ein Faecherrucken traegt noch einmal 50. An solchen Stellen steht der
		# Aschefaecher auf 247 m — ueber der Hochgebirgsschwelle der Weltregel, die deshalb
		# vor jeder Vulkanzeile abbog und Firn und Fels zurueckgab.
		return _vulkan_ueberzug(fels, asche, strom)

	# FELS UND BODEN UEBERBLENDEN statt hart umschalten. Hier stand
	#     if cen.y > 52.0 or ny < 0.70: return fels
	# also eine Stufenfunktion — und im Bild lag um jeden Berg ein scharf gezeichneter
	# brauner Ring, am deutlichsten am neuen Hochgebirge, wo er quer durch den Wald lief.
	# Der Anteil kommt jetzt aus zwei weichen Rampen (Hoehe ODER Steilheit, das Maximum
	# gewinnt) und wird ueber die Grundfarbe geblendet.
	# Die Rampen liegen ENG um die alten harten Schwellen (52 m und 0.70): der Uebergang
	# soll weich werden, die FLAECHE aber gleich bleiben. Der erste Versuch nahm 38-66 m
	# und 0.80-0.62 — damit bekam jede sanft geneigte Wiese am Bergfuss einen Braunstich,
	# und im Bild war das Vorland vor dem Hochgebirge nicht mehr gruen.
	# Die Hoehenschwelle wandert IM HOCHTAL nach oben (siehe ALMWIESE bei TAL_WIESE_HUB).
	# Die STEILHEIT bleibt unberuehrt: eine senkrechte Wand am Wasser ist auch dort Fels,
	# und genau daran endet das Gruen am Wandfuss.
	# UNTER EINER SCHUTTHALDE GILT WIEDER DIE WELTREGEL. Der Wiesenhub schiebt die
	# Felsschwelle im Hochtal um 150 m nach oben; ohne diesen Faktor lag unter der Halde
	# also GRUENER Boden, und ueberall, wo eine Gelaendekuppe durch die Felsdecke stiess
	# oder der Rand der Decke ausfranste, blitzte Wiese zwischen den Bloecken durch. Das
	# ist KEINE Sonderfarbe fuer ein Wahrzeichen: hier faellt nur eine Sonderregel weg,
	# uebrig bleibt der ganz normale Hochgebirgsfels der Weltregel.
	var wiese := _tal_wiese(cen, ny) * _halde_frei(cen.x, cen.z)
	# ZWEI HUBE, EINE SCHWELLE: der Wiesenhub des Hochtals und der Ascheschuerze-Hub des
	# Vulkans. Sie schliessen einander raeumlich aus (das Hochtal liegt im Nordwesten, der
	# Vulkan im Osten), addiert werden sie trotzdem statt maxf — ein maxf haette an einem
	# Ort, an dem beide gelten, stillschweigend einen davon verschluckt.
	var hub := TAL_WIESE_HUB * wiese + asche_hub
	var fels_anteil := maxf(smoothstep(45.0 + hub, 59.0 + hub, cen.y),
		smoothstep(0.745, 0.655, ny))
	var c: Color
	if fels_anteil > 0.998:
		c = fels
	else:
		# ERST AB 30 BIS 48 M wird die Biomfarbe zur Alm verschoben. Darunter aendert der
		# Wiesenhub ohnehin nichts (die Felsschwelle liegt bei 45 m), eine Farbverschiebung
		# waere dort also folgenlos — und sie hatte eine Nebenwirkung: am Taleingang liegt
		# WUESTE auf -4 bis 21 m, und dort pflanzt _make_chunk_data Palmen. Gruener Boden mit
		# Palmen darauf ist genau der Widerspruch zwischen Farbe und Bewuchs, den die
		# Almwiese eigentlich aufloest.
		var boden := _boden_farbe(cen, wiese * smoothstep(30.0, 48.0, cen.y), kragen)
		c = boden if fels_anteil < 0.002 else boden.lerp(fels, fels_anteil)
	if kies > 0.002:
		# 0.6 -> 0.82 und ein waermerer Ton: mit dem alten Wert lag der Kies als Hauch auf
		# dem Wiesengruen und war im Bild schlicht nicht zu finden. Im Referenzbild ist der
		# Strand die HELLSTE Flaeche des ganzen Talbodens.
		c = c.lerp(Color(0.80, 0.77, 0.70), kies * 0.82)
	return _vulkan_ueberzug(c, asche, strom)


## WAS DER VULKAN UEBER DIE GEWACHSENE FARBE LEGT: erst die Ascheschuerze, dann die Zunge.
##
## DIE REIHENFOLGE IST DIE DER NATUR: der Faecher ist der alte Auswurf, auf dem der Berg
## steht, die Zunge das juengste, was ueber ihn gelaufen ist. Umgekehrt aufgetragen deckte
## die Asche die Zungen wieder zu, und der Faecher waere eine einfarbige Flaeche.
##
## ZWEI AUFRUFER, UND DAS IST DER GRUND FUER DIE EIGENE FUNKTION: _face_color kehrt an ZWEI
## Stellen zurueck — einmal ueber 188 m mit blankem Hochgebirgsfels, einmal ganz unten mit
## der gemischten Bodenfarbe. Der erste Weg hatte den Ueberzug nicht, und genau dort lag im
## Abnahmebild ein heller Streifen quer ueber die Schuerze.
func _vulkan_ueberzug(c: Color, asche: Vector3, strom: float) -> Color:
	if asche.x > 0.004:
		# ZWEI LAENGENSKALEN HELLEN AUF, und beide haben Form unter sich: der RUECKEN
		# zwischen zwei Rinnen (470 m, gliedert) und das SCHUTTNEST (46 m, koernt). Warum
		# beides noetig ist und warum es sich addiert, steht bei VULKAN_APRON_GRUS_C.
		var hell := clampf(asche.y * VULKAN_APRON_RUECKEN
			+ asche.z * VULKAN_APRON_BLOCK_HELL, 0.0, 1.0)
		c = c.lerp(VULKAN_APRON_ASCHE.lerp(VULKAN_APRON_GRUS_C, hell),
			asche.x * VULKAN_APRON_DECK)
	if strom > 0.004:
		# DER STROM DECKT NICHT GANZ AB (0.92): ein Rest der Wiese schaut hindurch, und
		# genau daran liest man, dass hier etwas UEBER dem Boden liegt statt an seine
		# Stelle getreten zu sein. Bewuchs steht auf dem Band ohnehin keiner mehr, dafuer
		# sorgt dieselbe Maske in der Bepflanzung (vulkan_bewuchs).
		c = c.lerp(VULKAN_STROM, strom * 0.92)
	return c


## GRUNDFARBE OHNE FELS: Wiese, Wald, Wueste, Heide je nach Biom.
##
## Aus _face_color herausgeloest, damit sich Boden und Fels UEBERBLENDEN lassen. Vorher
## schaltete _face_color bei genau 52 m Hoehe bzw. 0.70 Hangneigung hart um, und im Bild
## lag um jeden Berg ein scharf gezeichneter brauner Ring — am neuen Hochgebirge lief er
## quer durch den Wald.
## KOSTET NICHTS EXTRA: _face_color ruft das nur, wenn der Felsanteil unter 1 liegt, also
## nur im schmalen Uebergangsband und nicht auf der ganzen Bergflanke. Das ist wichtig —
## die Funktion laeuft je DREIECK, also 4608-mal pro Chunk.
## ALPIN: Anteil, mit dem die BIOMFARBE zur Alm hin verschoben wird (dieselbe Zahl wie der
## Wiesenhub, siehe TAL_WIESE_HUB). Das grosse Biomrauschen laeuft ueber 3,2 km, das Hochtal
## ist 11,4 km lang — es kreuzt also zwangslaeufig Wueste und Heide. Gemessen liegt am
## Taleingang WUESTE, und solange der Fels darueber lag, fiel das nicht auf. Mit der Almwiese
## scheint _boden_farbe durch, und aus dem Talboden waere eine Sandzunge geworden: mitten im
## Hochgebirge, zwischen Schneegipfeln, in 0.88/0.79/0.55.
## Deshalb wird im Korridor auf die WALD/WIESE-Variante geblendet — nicht hart umgeschaltet,
## sonst stuende an der Biomgrenze eine Kante quer durch das Tal.
## KRAGEN: Dichtesockel des Vulkan-Waldguertels an dieser Stelle (siehe vulkan_kragen). Er
## tut hier GENAU DASSELBE wie "alpin" — er blendet auf die WALD/WIESE-Variante — und aus
## demselben Grund: dort steht ein geschlossener Bestand, und was darunter liegt, darf keine
## Duene sein. Ohne den Wert bleibt jede Stelle der Welt farblich exakt wie bisher.
func _boden_farbe(cen: Vector3, alpin: float = 0.0, kragen: float = 0.0) -> Color:
	var t := _patch.get_noise_2d(cen.x, cen.z)
	# WALDBODEN: exakt dieselbe Dichte-Formel wie die Bepflanzung in _make_chunk_data,
	# also faerbt sich der Boden GENAU dort dunkel, wo auch Baeume stehen. Zwei Gewinne:
	# unter dem Kronendach wirkt der Wald geschlossen statt aufgesetzt, und JENSEITS der
	# Instanz-Sichtweite (FLORA_DIST, 3.2 km) liest sich das Land weiter als Wald statt
	# als Rasen — ohne dafuer einen einzigen Baum zu zeichnen.
	# _open_ground MUSS mit: sonst liegt rund um Bahn und Stadt dunkler Waldboden
	# auf einer Wiese, auf der per Definition kein Baum steht.
	var wald := smoothstep(-0.28, 0.30, _forest.get_noise_2d(cen.x, cen.z))
	wald = wald * wald
	# GENAU DIESELBE ZEILE WIE IN DER BEPFLANZUNG, an derselben Stelle der Rechnung: erst der
	# Sockel auf die Dichte, dann die Schranken darauf. Stuende sie hier hinter den Schranken
	# und dort davor, waere der Waldboden im Kragen ein anderer als der Wald darauf.
	wald = maxf(wald, kragen)
	wald = wald * smoothstep(FLORA_MIN_H, FLORA_FULL_H, cen.y) \
		* (1.0 - smoothstep(46.0, FLORA_MAX_H, cen.y)) * _open_ground(cen.x, cen.z)
	# Wald/Wiese: SATTES Wiesen-Grün, nur wenige dezente Flecken (kein blasses Mint mehr)
	var g1 := Color(0.40, 0.61, 0.28)  # frisches, sattes Wiesen-Grün
	var g2 := Color(0.28, 0.49, 0.23)  # tieferes Grün
	var wc := g1.lerp(g2, clampf(t * 0.6 + 0.5, 0.0, 1.0))
	if t < -0.55:
		wc = Color(0.50, 0.52, 0.40)   # seltener erdiger Fleck
	elif t > 0.55:
		wc = Color(0.62, 0.62, 0.44)   # seltener trockener Gras-Fleck
	wc = wc.lerp(Color(0.15, 0.29, 0.16), wald * 0.62)
	# Im Hochtal gilt ab hier NUR NOCH diese Wiese — der Umweg ueber das Biom entfaellt,
	# und damit auch dessen Kosten.
	if alpin > 0.998:
		return wc
	var bc := wc
	match biome_at(cen.x, cen.z):
		Biome.WUESTE:
			# Wüste: warme Sand-/Dünentöne, Erd-/Felsbänder dazwischen
			if t < -0.35:
				bc = Color(0.80, 0.66, 0.46) # feuchter/schattiger Sand
			elif t > 0.45:
				bc = Color(0.72, 0.60, 0.45) # Geröll-/Erdfleck
			else:
				bc = Color(0.91, 0.82, 0.58).lerp(Color(0.86, 0.76, 0.52),
					clampf(t * 0.6 + 0.5, 0.0, 1.0))
		Biome.HEIDE:
			# Heide/Herbst: staubiges Rosé/Ocker
			var hc := Color(0.74, 0.68, 0.50).lerp(Color(0.66, 0.58, 0.50),
				clampf(t * 0.6 + 0.5, 0.0, 1.0))
			if t < -0.40:
				hc = Color(0.74, 0.62, 0.60)   # Rosé-Fleck
			elif t > 0.45:
				hc = Color(0.80, 0.72, 0.50)   # Ocker-Gras
			# Heide traegt nur 30 % der Walddichte -> auch nur ein Hauch Waldboden
			bc = hc.lerp(Color(0.44, 0.44, 0.31), wald * 0.30)
	# Der Vulkankragen blendet auf dieselbe WALD/WIESE-Variante wie der Almkorridor (siehe
	# oben) — eine Zeile, zwei Anlaesse, und beide meinen dasselbe: hier gilt das Biom nicht.
	var zu_wc := maxf(alpin, clampf(kragen / maxf(VULKAN_KRAGEN_DICHT, 0.01), 0.0, 1.0))
	return bc if zu_wc < 0.002 else bc.lerp(wc, zu_wc)


# Baumarten aus models/world_trees.glb (tools/build_baeume.py). Die Meshes tragen
# VERTEX-FARBEN und werden wie das Terrain mit _mat gezeichnet (ALBEDO = COLOR).
# Fehlt das glb, fallen alle Arten auf die alten prozeduralen Formen zurueck — das
# Spiel laeuft dann weiter, nur mit weniger Vielfalt.
## Erzeugt vereinfachte Stufen fuer ein Mesh. Fuer die Flora ist das der groesste
## Einzelhebel der Bodenansicht: gemessen kostet sie 4,65 von 7,86 ms je Bild (59 %) und
## stellt 5,46 von 7,35 Mio Primitiven (74 %) — und das fuer Baeume, die in der Ferne nur
## wenige Bildpunkte gross sind.
## Die Stufen kommen NICHT aus dem Import: der Baum-GLB liefert sie nicht mit, und die
## prozeduralen Ersatzmeshes koennen es gar nicht. Deshalb hier zur Ladezeit.
## Baut eine VEREINFACHTE Fassung eines Meshes: dieselben Ecken, aber die Indexliste der
## groebsten von generate_lods() erzeugten Stufe.
##
## WARUM NICHT EINFACH lod_bias AN DER MULTIMESH-INSTANZ: gemessen. Mit erzeugten
## LOD-Stufen und lod_bias 1.0 bis 0.2 aenderte sich die Primitivzahl von 7.354.668 auf
## 7.346.396 — ein Promille. Godot waehlt fuer eine MultiMesh keine LOD-Stufe aus; die
## Stufen liegen zwar im Mesh, werden aber nie benutzt. Also muss das Mesh SELBST
## getauscht werden, und genau das macht _chunks_pflegen() je Chunk.

static func _grobe_fassung(quelle: Mesh) -> Mesh:
	if quelle == null or quelle.get_surface_count() == 0:
		return quelle
	var im := ImporterMesh.new()
	for si in quelle.get_surface_count():
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, quelle.surface_get_arrays(si), [], {}, null, "", 0)
	im.generate_lods(25.0, 60.0, [])
	var raus := ArrayMesh.new()
	for si in quelle.get_surface_count():
		var arr := quelle.surface_get_arrays(si)
		# NICHT JEDES MESH IST INDIZIERT. Die prozeduralen Felsen kommen ohne Indexliste
		# aus dem SurfaceTool, arr[ARRAY_INDEX] ist dort null — die typisierte Zuweisung
		# brach damit beim Weltaufbau ab. Meine Pruefung hatte nur die Baum-GLB angesehen,
		# und die ist indiziert.
		var roh_idx: Variant = arr[Mesh.ARRAY_INDEX]
		var voll: PackedInt32Array = roh_idx if roh_idx != null else PackedInt32Array()
		var n := im.get_surface_lod_count(si)
		if n > 0 and voll.size() > 0:
			# NICHT BLIND DIE GROEBSTE STUFE NEHMEN.
			# Symptom war: ueber dem Boden schwebten Baumkronen ohne Stamm, anderswo
			# standen nackte Staemme. Ursache ist NICHT, dass Stamm und Krone getrennte
			# Teilflaechen waeren — sie liegen in derselben (jeder Baum hat genau eine).
			# Der Vereinfacher wirft schlicht den duennen Stamm zuerst weg, weil er von
			# allen Dreiecken am wenigsten zur Silhouette beitraegt. Gemessen: Birke fiel
			# von 272 auf 70 Dreiecke, Busch von 128 auf 32 — dabei geht der Stamm drauf.
			# Deshalb die groebste Stufe nehmen, die noch die HAELFTE behaelt. Der Verlust
			# ist klein: von sieben Baumarten dezimieren ohnehin nur zwei ueberhaupt, die
			# uebrigen liefern auf jeder Stufe dieselbe Dreieckszahl.
			var mind: int = maxi(int(voll.size() * 0.5), 12)
			for stufe in range(n - 1, -1, -1):
				var idx: PackedInt32Array = im.get_surface_lod_indices(si, stufe)
				if idx.size() >= mind:
					arr[Mesh.ARRAY_INDEX] = idx
					break
		raus.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return raus


func _load_flora() -> Dictionary:
	var d: Dictionary = {}
	var ps: Resource = load("res://models/world_trees.glb")
	if ps != null and ps is PackedScene:
		var sc: Node = (ps as PackedScene).instantiate()
		for n in sc.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				d[mi.name] = mi.mesh
		sc.free()
	for art in ARTEN:
		if not d.has(art):
			if art == "Palme":
				d[art] = _mesh_palm
			elif art in ["Birke", "Eiche", "Busch"]:
				d[art] = _mesh_leaf
			else:
				d[art] = _mesh_conifer
	return d


# ---------------------------------------------------------------------------
# Low-Poly-Flora-Meshes (einmal gebaut, via MultiMesh überall instanziert).
# Gleiche Technik wie das Terrain: flache Facetten + Vertex-Farben (_mat).
# ---------------------------------------------------------------------------
func _cone_into(st: SurfaceTool, base_y: float, top_y: float, r: float, col: Color, segs: int, dark: float) -> void:
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := Vector3(cos(a0) * r, base_y, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, base_y, sin(a1) * r)
		var tip := Vector3(0, top_y, 0)
		# leichte Ton-Variation pro Facette -> lebendiger Low-Poly-Look
		var c := col.darkened(dark * (0.5 + 0.5 * sin(a0 * 3.0)))
		st.set_color(c)
		st.add_vertex(tip)
		st.add_vertex(p1)
		st.add_vertex(p0)


func _trunk_into(st: SurfaceTool, h: float, r: float) -> void:
	var col := Color(0.42, 0.30, 0.20)
	for i in 5:
		var a0 := TAU * float(i) / 5.0
		var a1 := TAU * float(i + 1) / 5.0
		var b0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var b1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var t0 := b0 + Vector3(0, h, 0)
		var t1 := b1 + Vector3(0, h, 0)
		st.set_color(col.darkened(0.15 * sin(a0 * 2.0)))
		st.add_vertex(t0)
		st.add_vertex(b1)
		st.add_vertex(b0)
		st.set_color(col)
		st.add_vertex(t0)
		st.add_vertex(t1)
		st.add_vertex(b1)


func _build_conifer_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_trunk_into(st, 2.2, 0.45)
	var green := Color(0.16, 0.40, 0.22)
	_cone_into(st, 1.8, 5.4, 2.6, green, 7, 0.18)
	_cone_into(st, 4.2, 7.6, 1.9, green.lightened(0.06), 7, 0.18)
	_cone_into(st, 6.4, 9.6, 1.2, green.lightened(0.12), 7, 0.18)
	st.generate_normals()
	return st.commit()


func _build_leaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_trunk_into(st, 3.0, 0.5)
	# Krone = Doppel-Kegel (oben spitz, unten gestülpt) -> kantige Laub-"Knolle"
	var green := Color(0.33, 0.55, 0.24)
	_cone_into(st, 4.6, 8.8, 3.1, green, 6, 0.22)
	var st2 := st   # untere Halbknolle: Kegel kopfüber
	for i in 6:
		var a0 := TAU * float(i) / 6.0
		var a1 := TAU * float(i + 1) / 6.0
		var p0 := Vector3(cos(a0) * 3.1, 4.6, sin(a0) * 3.1)
		var p1 := Vector3(cos(a1) * 3.1, 4.6, sin(a1) * 3.1)
		var tip := Vector3(0, 2.6, 0)
		st2.set_color(green.darkened(0.28 + 0.1 * sin(a0 * 2.0)))
		st2.add_vertex(tip)
		st2.add_vertex(p0)
		st2.add_vertex(p1)
	st.generate_normals()
	return st.commit()


func _build_rock_mesh() -> ArrayMesh:
	# kantiger Brocken: unregelmäßiges Doppel-Kegel-Polyeder
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var gray := Color(0.52, 0.51, 0.53)
	var ring: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i in 6:
		var a := TAU * float(i) / 6.0
		ring.append(Vector3(cos(a) * rng.randf_range(0.7, 1.15), rng.randf_range(0.25, 0.55), sin(a) * rng.randf_range(0.7, 1.15)))
	var top := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(1.0, 1.4), rng.randf_range(-0.2, 0.2))
	for i in 6:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % 6]
		st.set_color(gray.darkened(0.12 * sin(float(i) * 1.7)))
		st.add_vertex(top)
		st.add_vertex(p1)
		st.add_vertex(p0)
		# Sockel auf den Boden ziehen
		var b0 := Vector3(p0.x * 1.15, -0.4, p0.z * 1.15)
		var b1 := Vector3(p1.x * 1.15, -0.4, p1.z * 1.15)
		st.set_color(gray.darkened(0.2))
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(b1)
		st.add_vertex(p0)
		st.add_vertex(b1)
		st.add_vertex(b0)
	st.generate_normals()
	return st.commit()


func _dtri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	# doppelseitiges Dreieck (Wedel sind von beiden Seiten sichtbar)
	st.set_color(col)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)


func _build_palm_mesh() -> ArrayMesh:
	# Wüsten-Palme: leicht geneigter, segmentierter Stamm + hängende Wedelkrone.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var trunk := Color(0.56, 0.44, 0.29)
	var H := 5.0
	var lean := Vector3(0.7, 0.0, 0.2)        # leichte Krümmung zur Seite
	var segs := 5
	var sides := 5
	var prev_c := Vector3.ZERO
	var prev_r := 0.30
	for s in range(1, segs + 1):
		var tt := float(s) / float(segs)
		var c := lean * (tt * tt) + Vector3(0, H * tt, 0)
		var r := lerpf(0.30, 0.15, tt)
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var b0 := prev_c + Vector3(cos(a0) * prev_r, 0, sin(a0) * prev_r)
			var b1 := prev_c + Vector3(cos(a1) * prev_r, 0, sin(a1) * prev_r)
			var t0 := c + Vector3(cos(a0) * r, 0, sin(a0) * r)
			var t1 := c + Vector3(cos(a1) * r, 0, sin(a1) * r)
			st.set_color(trunk.darkened(0.1 * sin(a0 * 2.0 + float(s))))
			st.add_vertex(t0); st.add_vertex(b1); st.add_vertex(b0)
			st.add_vertex(t0); st.add_vertex(t1); st.add_vertex(b1)
		prev_c = c; prev_r = r
	# Wedelkrone: nach außen-unten hängende Blätter (doppelseitige Rauten)
	var top: Vector3 = lean + Vector3(0, H, 0)
	var frond := Color(0.42, 0.54, 0.25)
	var nf := 8
	for i in nf:
		var a := TAU * float(i) / float(nf) + 0.4
		var dir := Vector3(cos(a), 0, sin(a))
		var midp: Vector3 = top + dir * 1.8 + Vector3(0, 0.5, 0)
		var tip: Vector3 = top + dir * 3.6 + Vector3(0, -1.9, 0)
		var side := Vector3(-dir.z, 0, dir.x) * 0.5
		var col := frond.darkened(0.14 * sin(a * 2.0))
		_dtri(st, top, midp + side, midp - side, col)
		_dtri(st, midp + side, tip, midp - side, col)
	st.generate_normals()
	return st.commit()
