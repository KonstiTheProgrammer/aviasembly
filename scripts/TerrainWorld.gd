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
	# Relief: sehr grob — wie gebirgig eine Region ist (Ebene 0 .. Alpen 1)
	_relief = FastNoiseLite.new()
	_relief.seed = seedv * 23 + 7
	_relief.frequency = 1.0 / 3600.0
	# Biom: sehr grob — Regionen-Einteilung
	_biome = FastNoiseLite.new()
	_biome.seed = seedv * 31 + 13
	_biome.frequency = 1.0 / 3200.0
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
void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
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
		var cone := 1.0 - smoothstep(0.0, mr, md)
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
				var top := lerpf(h, float(ms["peak"]), s) + s * crag * 22.0
				if typ == "vulkan":
					# Krater: Kegelspitze zur Schüssel eindrücken (Boden bleibt hoch/trocken)
					var cr := float(ms.get("crater_r", mr * 0.16))
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
			var open := _open_ground(cx, cz)
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
			var f := _forest.get_noise_2d(cx, cz)
			# Waldkern dicht, Rand ausduennend, echte Lichtungen unter f = -0.28.
			var dens := smoothstep(-0.28, 0.30, f)
			dens = dens * dens
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
	# VULKAN-Flanken: dunkler Basalt statt Schnee/Fels (sonst weisser Marshmallow-Kegel);
	# zum Gipfel leicht roetlich verwitterte Schlacke. Unterer Gruenguertel bleibt normal.
	for ms in massifs:
		if String(ms.get("type", "")) == "vulkan" and cen.y > 26.0 \
				and Vector2(cen.x - ms["pos"].x, cen.z - ms["pos"].z).length() < float(ms["r"]) * 1.05:
			var vt := clampf((cen.y - 26.0) / maxf(float(ms["peak"]) - 26.0, 1.0), 0.0, 1.0)
			return Color(0.24, 0.21, 0.20).lerp(Color(0.38, 0.25, 0.20), vt)
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
		return fels

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
	var hub := TAL_WIESE_HUB * wiese
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
		var boden := _boden_farbe(cen, wiese * smoothstep(30.0, 48.0, cen.y))
		c = boden if fels_anteil < 0.002 else boden.lerp(fels, fels_anteil)
	if kies > 0.002:
		# 0.6 -> 0.82 und ein waermerer Ton: mit dem alten Wert lag der Kies als Hauch auf
		# dem Wiesengruen und war im Bild schlicht nicht zu finden. Im Referenzbild ist der
		# Strand die HELLSTE Flaeche des ganzen Talbodens.
		c = c.lerp(Color(0.80, 0.77, 0.70), kies * 0.82)
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
func _boden_farbe(cen: Vector3, alpin: float = 0.0) -> Color:
	var t := _patch.get_noise_2d(cen.x, cen.z)
	# WALDBODEN: exakt dieselbe Dichte-Formel wie die Bepflanzung in _make_chunk_data,
	# also faerbt sich der Boden GENAU dort dunkel, wo auch Baeume stehen. Zwei Gewinne:
	# unter dem Kronendach wirkt der Wald geschlossen statt aufgesetzt, und JENSEITS der
	# Instanz-Sichtweite (FLORA_DIST, 3.2 km) liest sich das Land weiter als Wald statt
	# als Rasen — ohne dafuer einen einzigen Baum zu zeichnen.
	# _open_ground MUSS mit: sonst liegt rund um Bahn und Stadt dunkler Waldboden
	# auf einer Wiese, auf der per Definition kein Baum steht.
	var wald := smoothstep(-0.28, 0.30, _forest.get_noise_2d(cen.x, cen.z))
	wald = wald * wald * smoothstep(FLORA_MIN_H, FLORA_FULL_H, cen.y) \
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
	return bc if alpin < 0.002 else bc.lerp(wc, alpin)


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
