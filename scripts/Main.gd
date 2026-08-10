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
const SONNE_WINKEL := Vector3(-50.0, -50.0, 0.0)

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
const NEBEL_FREI := 0.00006
const NEBEL_WOLKE := 0.020
const NEBEL_FARBE_FREI := Color(0.66, 0.79, 0.94)
const NEBEL_FARBE_WOLKE := Color(0.93, 0.95, 0.97)
# Kennlinie: erst tief in der Wolke wird es wirklich weiss. Linear waere die Sicht schon
# beim Streifen einer Kante halb zu, und das fuehlt sich falsch an.
const NEBEL_KURVE := 1.7

# --- FERNSCHUERZE (siehe _fernschuerze_starten) -------------------------------------
# Rasterweite der groben Fernlage. Die Chunks fahren 8 m; 64 m ist genau ein Achtel
# davon, das Gitter faellt also auf JEDE achte Chunk-Stuetzstelle und beide Flaechen
# treffen sich dort exakt.
const FERN_ZELLE := 64.0
# Kantenlaenge einer Schuerzen-Kachel (24 Zellen). Groesser = weniger Draw-Calls, aber
# groebere Sichtbarkeits-Auslese; 1536 m = vier Chunkbreiten hat sich als Mitte ergeben.
const FERN_KACHEL := 1536.0
# Halbe Kantenlaenge des abgesuchten Weltausschnitts. GEMESSEN: das entfernteste Land
# dieses Seeds liegt bei 17,7 km (200x200-Raster ueber +-22 km), 18,5 km deckt es ab.
const FERN_WELT := 18500.0
# Grundabsenkung im Ueberlappbereich. GEMESSEN an 40 000 Landproben: das echte 8-m-Gelaende
# liegt gegenueber der 64-m-Interpolation im schlechtesten Fall 44 m tiefer, aber schon
# bei 12 m sind 99,9 % erfasst. 14 m halten die Schuerze also praktisch ueberall unter
# den Chunks, ohne an der Naht eine dicke Stufe zu bauen (14 m sind in 3,5 km rund 2 px).
const FERN_BIAS := 14.0
# Tiefe der Nahfeld-Absenkung: mehr als der hoechste Berg (230 m), damit die grobe Lage
# im Nahbereich garantiert unter dem Boden verschwindet.
const FERN_TIEF := 480.0
# Rampe der Nahfeld-Absenkung. FERN_FERN ist KEIN Geschmackswert, sondern die Grenze,
# bis zu der TerrainWorld garantiert Chunks stehen hat: es haelt Chunkmitten bis
# VIEW_DIST+CHUNK = 4184 m, davon halbe Chunkdiagonale (271 m) und die volle Zell-
# diagonale ab, die der Spieler seit dem letzten update_center zurueckgelegt haben
# kann (543 m) -> 3370 m. Darunter bleiben wir mit 3300 m.
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
var _fern_mutex: Mutex
var _fern_keys: Array[Vector2i] = []
var _fern_meshes: Array = []
var _fern_tris := 0
var showroom: ShowroomStage       # Praesentations-Buehne des Bau-Modus
var airfields: Array = []
var world_env: WorldEnvironment
var terrain: TerrainWorld           # seed-basierte Landschaft (Chunks um den Spieler)
var sky_lights: Node3D              # Sonne + Fülllicht NUR für den Flug
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
var _cat_open: Dictionary = {}     # Kategorie -> auf-/zugeklappt

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
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# WICHTIG: tonemap_white=1.0 presste die GESAMTE Range platt -> alles pastellig-milchig
	# ("fade Map"). white=6 gibt ACES seine Dynamik zurueck, Farben duerfen wieder satt sein.
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.05
	env.adjustment_brightness = 1.0
	# Luftperspektive statt Milchglas: weniger Dichte, dafuer mehr AERIAL (Ferne kippt in
	# den Himmelston = Tiefe + Farbe, statt alles weiss zu waschen).
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.66, 0.79, 0.94)
	env.fog_sun_scatter = 0.15
	env.fog_density = 0.00006
	env.fog_aerial_perspective = 0.30
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
	sun.light_color = Color(1.0, 0.97, 0.88)
	sun.light_energy = 1.30    # kraeftige Tagessonne — Facetten des Low-Poly-Terrains zeichnen
	sun.shadow_enabled = true
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
	# Fuelllicht von unten/hinten. Es bekommt bewusst KEINE Schatten (es soll aufhellen,
	# nicht ein zweites Schattenbild dazulegen) und wurde von 0.32 auf 0.24 gedaempft:
	# solange die Sonne schattenlos war, musste es die Formen retten — jetzt uebernimmt
	# das der Sonnenschatten, und zu viel Gegenlicht wuerde ihn wieder zuschmieren.
	var underfill := DirectionalLight3D.new()
	underfill.rotation_degrees = Vector3(58, 130, 0)
	underfill.light_color = Color(0.80, 0.86, 0.95)
	underfill.light_energy = 0.24
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
		{"name": "WESTKAP", "pos": Vector3(-9200, 0, -600), "heading": 1.9, "color": Color(0.55, 0.85, 0.60)},
		{"name": "SÜDSTRAND", "pos": Vector3(2600, 0, 9200), "heading": -0.6, "color": Color(0.95, 0.60, 0.85)},
		{"name": "VULKANFELD", "pos": Vector3(8800, 0, -4600), "heading": 0.9, "color": Color(0.95, 0.45, 0.20)},
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
		flat_zones.append({"pos": af["pos"], "heading": af["heading"],
			"r_flat": 1700.0 if is_main else 750.0,
			"r_blend": 2300.0 if is_main else 1200.0, "rects": rects})
	# --- WAHRZEICHEN/POIs: Stadt mit See + Leuchtturm + BERGDORF am FLUSS (Stufe 3) ---
	var town_pos := Vector3(1400, 0, 750)
	var factory_pos := town_pos + Vector3(-225, 0, 95)
	var lake_pos := Vector3(1400, 0, 1030)
	var lh_pos := Vector3(-950, 0, -1250)
	var village_pos := Vector3(2550, 120, 1650)   # Bergdorf-Plateau (Schelf am Massiv)
	flat_zones.append({"pos": town_pos, "r_flat": 360.0, "r_blend": 760.0})
	flat_zones.append({"pos": lake_pos, "r_flat": 230.0, "r_blend": 520.0})  # See-Umfeld flach
	flat_zones.append({"pos": lh_pos, "r_flat": 110.0, "r_blend": 300.0})
	flat_zones.append({"pos": village_pos, "r_flat": 140.0, "r_blend": 340.0, "y": 120.0})
	# --- NEUE VIERTEL aus den Blender-Gebaeuden (scripts/CityBuilder.gd) ---------------
	# Jedes braucht eine Einebnung, sonst stehen Hochhaeuser auf einem Hang.
	var city_pos := Vector3(4300, 0, 2500)      # Grossstadt mit Skyline
	var indu_pos := Vector3(3500, 0, -1500)     # Industriehafen
	var dorf_pos := Vector3(-2300, 0, 1900)     # Landdorf
	var burg_pos := Vector3(-1750, 0, 3150)     # Burgberg
	var mil_pos := Vector3(250, 0, -2400)       # Militaerposten (bei der FLAK-ZONE)
	flat_zones.append({"pos": city_pos, "r_flat": 480.0, "r_blend": 980.0})
	flat_zones.append({"pos": indu_pos, "r_flat": 300.0, "r_blend": 700.0})
	flat_zones.append({"pos": dorf_pos, "r_flat": 260.0, "r_blend": 620.0})
	flat_zones.append({"pos": burg_pos, "r_flat": 160.0, "r_blend": 420.0, "y": 78.0})
	flat_zones.append({"pos": mil_pos, "r_flat": 200.0, "r_blend": 480.0})
	var lakes := [{"pos": lake_pos, "r": 175.0, "surf": -1.0},
		{"pos": Vector3(-3300, 0, 5250), "r": 260.0, "surf": -2.0}]   # Canyon-Endsee
	# Erzwungene Formen: Bergmassiv (Bergdorf/Flussquelle) + VULKANINSEL + ARCHIPEL
	# draußen im Ozean als Ausflugsziele (Insel-Typ fällt am Rand unter den Meeresspiegel
	# -> echte Küsten mit Türkis-Schelf, egal welcher Seed).
	var massifs := [
		{"pos": Vector3(2400, 0, 1500), "r": 850.0, "peak": 205.0},
		{"pos": burg_pos, "r": 420.0, "peak": 88.0},   # Burgberg (Flachzone y=78 sitzt oben drauf)
				# CANYON-FLANKEN: erzwungene Grate beidseits der Schlucht-Spline — der River-Carve
		# schneidet DANACH hindurch (Reihenfolge in height_at) -> echte Waende, seed-robust.
		{"pos": Vector3(-6725, 0, 1450), "r": 750.0, "peak": 120.0},
		{"pos": Vector3(-5875, 0, 950), "r": 750.0, "peak": 135.0},
		{"pos": Vector3(-5675, 0, 3050), "r": 750.0, "peak": 140.0},
		{"pos": Vector3(-4825, 0, 2550), "r": 750.0, "peak": 125.0},
		{"pos": Vector3(-4625, 0, 4350), "r": 700.0, "peak": 110.0},
		{"pos": Vector3(-3775, 0, 3850), "r": 700.0, "peak": 120.0},
		{"pos": Vector3(11800, 0, -5600), "r": 1250.0, "peak": 230.0, "type": "vulkan"},
		{"pos": Vector3(16000, 0, -3800), "r": 520.0, "peak": 40.0, "type": "insel"},
		{"pos": Vector3(12500, 0, -11500), "r": 500.0, "peak": 34.0, "type": "insel"},
		{"pos": Vector3(-11500, 0, 13000), "r": 700.0, "peak": 55.0, "type": "insel"},
		{"pos": Vector3(-14500, 0, 9000), "r": 430.0, "peak": 24.0, "type": "insel"},
		{"pos": Vector3(3800, 0, -15800), "r": 600.0, "peak": 45.0, "type": "insel"},
	]
	# ECHTER FLUSS: Spline von der Bergquelle (hoch) bis in den See (tief).
	# Punkte = (x, Wasserhöhe, z); Höhe fällt monoton -> fließt bergab.
	var rivers := [{
		# CANYON DES WESTENS: extrem breites/tiefes "Flusstal" = durchfliegbare Schlucht
		# (die Distanz-Rampe macht dort echte Berge -> hohe Waende links und rechts).
		"w": 40.0, "valley": 260.0, "depth": 7.0,
		"pts": [
			Vector3(-6600, 46, 900), Vector3(-6050, 34, 1900), Vector3(-5250, 22, 2800),
			Vector3(-4450, 12, 3700), Vector3(-3800, 8, 4500), Vector3(-3380, 4, 5100),
		],
	}, {
		"w": 13.0, "valley": 55.0, "depth": 4.0,
		"pts": [
			Vector3(2545, 112, 1760), Vector3(2330, 82, 1600), Vector3(2110, 56, 1460),
			Vector3(1900, 35, 1320), Vector3(1710, 20, 1210), Vector3(1560, 8, 1130),
			Vector3(1460, 1, 1075), Vector3(1430, -1, 1030),
		],
	}]
	terrain.setup(game.world_seed, flat_zones, lakes, rivers, massifs)
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
		{"name": "Wrack", "pos": Vector3(16600, 0, -4600), "color": Color(0.62, 0.42, 0.30)},
		{"name": "GROSSSTADT", "pos": city_pos, "color": Color(0.95, 0.90, 0.55)},
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
	_build_windfarm(Vector3(-3900, 0, -700))
	# Ozean-Leben: Segelschiffe weit draussen (garantiert Wasser, d > 16 km) + Wrack
	for sh in [[Vector2(15600, -5200), 0.7], [Vector2(13400, -11000), 2.4],
			[Vector2(-11400, 12800), -0.9], [Vector2(4600, -16600), 1.6]]:
		Landmarks.build_ship(fly_world, sh[0], sh[1])
	Landmarks.build_wreck(fly_world, Vector2(16600, -4600), 0.8)
	Landmarks.build_village(fly_world, village_pos)
	# Blender-Gebaeude einbauen (MultiMesh je Typ; ohne Kollision wie die Landmarks)
	if CityBuilder.has_lib():
		CityBuilder.build(fly_world, terrain, city_pos, CityBuilder.plan_grossstadt(), "Grossstadt")
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
			# NEBEN die Bahn (die laeuft im lokalen Z des Flugplatzes, 900 m lang!) und die
			# ganze Planung mit dem Bahnkurs drehen -> Hangars stehen parallel zur Piste.
			var hd: float = af["heading"]
			var ap: Vector3 = af["pos"] + Basis(Vector3.UP, hd) * Vector3(230.0, 0.0, -60.0)
			CityBuilder.build(fly_world, terrain, ap, CityBuilder.plan_flugplatz(),
				"Flugplatzbauten_" + String(af["name"]), hd)
	Landmarks.build_bridge(fly_world, Vector3(1560, 22, 1130), 120.0, 1.0)   # Viadukt überm Fluss
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

	# Der Blueprint-Boden gehoert jetzt zu ShowroomStage und wird mit der Buehne
	# geschaltet (frueher ein eigenes MeshInstance3D mit hellem Inline-Shader).


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
	# Der fragment()-Teil ist absichtlich Zeichen fuer Zeichen der des Terrains
	# (TerrainWorld.setup): Vertexfarbe als Albedo, sRGB->linear gewandelt. Nur so
	# trifft die Schuerze die Palette der Chunks, an die sie anschliesst.
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
	var t0 := Time.get_ticks_msec()
	var gid := WorkerThreadPool.add_group_task(_fern_kachel, _fern_keys.size(),
		-1, false, "Fernschuerze")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	call_deferred("_fern_fertig", Time.get_ticks_msec() - t0)


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
	var n := int(FERN_KACHEL / FERN_ZELLE)
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			hs[j * (n + 1) + i] = maxf(
				terrain.height_at(ox + float(i) * FERN_ZELLE, oz + float(j) * FERN_ZELLE),
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
			var x0 := ox + float(i) * FERN_ZELLE
			var z0 := oz + float(j) * FERN_ZELLE
			var v00 := Vector3(x0, h00, z0)
			var v10 := Vector3(x0 + FERN_ZELLE, h10, z0)
			var v01 := Vector3(x0, h01, z0 + FERN_ZELLE)
			var v11 := Vector3(x0 + FERN_ZELLE, h11, z0 + FERN_ZELLE)
			_fern_tri(st, v00, v10, v11)
			_fern_tri(st, v00, v11, v01)
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
func _fern_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nn := (b - a).cross(c - a).normalized()
	var cen := (a + b + c) / 3.0
	var col := terrain._face_color(cen, absf(nn.y))
	col.a = clampf(0.25 + cen.y / 60.0, 0.25, 1.0)
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _fern_fertig(ms: int) -> void:
	if _fern_thread != null:
		_fern_thread.wait_to_finish()
		_fern_thread = null
	if fern_root == null or not is_instance_valid(fern_root):
		return
	for m in _fern_meshes:
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
		fern_root.add_child(mi)
	print("Fernschuerze: %d Kacheln, %d Dreiecke, %.2f s" % [_fern_meshes.size(), _fern_tris, ms / 1000.0])
	_fern_meshes.clear()


func _exit_tree() -> void:
	# Der Schuerzen-Thread liest terrain. Wird Main abgeraeumt, muss er vorher stehen.
	if _fern_thread != null and _fern_thread.is_started():
		_fern_thread.wait_to_finish()
		_fern_thread = null


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
	var nd := int(RWY_LEN / 60.0)
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
	# Namensschild hoch oben (immer sichtbar)
	var lbl := Label3D.new()
	lbl.text = af["name"]
	lbl.font_size = 130
	lbl.pixel_size = 0.22
	lbl.position = Vector3(0, 60, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.modulate = af["color"]
	lbl.outline_size = 26
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	node.add_child(lbl)
	# Umfeld: Baumguertel, Felsbrocken, Platzzaun (siehe _gruenguertel).
	_gruenguertel(node)
	# HEIMAT = Hauptbasis: großes Extra-Paket (Radar, Großhangar, Flutlicht, Helipad, …)
	if af.get("main", false):
		_build_main_base(vf, af["color"])


# Hauptbasis-Ausbau für HEIMAT: erweitertes Vorfeld, offener Großhangar (begehbar),
# drehender Radarturm, Tower-Antenne mit Blinklicht, Flutlicht-Masten, Helipad,
# Splitterschutz-Boxen (Blast Pens) mit GEPARKTEN Flugzeugen aus den Vorlagen.
func _build_main_base(node: Node3D, _col: Color) -> void:
	# EXAKT derselbe Ton wie in _build_airfield — die Erweiterung stoesst dort buendig an.
	# Mit den frueheren 0.60 gegen 0.55 war die Naht als Farbkante quer ueber das Vorfeld
	# zu sehen (in heimat_3 ist die Flaeche einheitlich).
	var concrete := _flat_mat(Color(0.70, 0.69, 0.65), 0.9)
	# --- Vorfeld nach Osten erweitern (stoesst BUENDIG an die Basisplatte bei x = 126:
	# ueberlappende gleich hohe Platten flimmern, eine geteilte Kante nicht) ---
	_deco_box(node, Vector3(142.0, 0.035, -5.0), Vector3(32.0, 0.07, 190.0), concrete)
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
func _gruenguertel(wurzel: Node3D) -> void:
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
	for versuch in 1700:
		var x := rng.randf_range(-175.0, 320.0)
		var z := rng.randf_range(-625.0, 625.0)
		var d := _fp_abstand(x, z)
		if d < 1.5 or d > 150.0:
			continue
		if rng.randf() < 0.55 * (1.0 - smoothstep(8.0, 95.0, d)):
			# Findlinge, 1,5 bis 3,8 m breit (Vorgabe 1 bis 4 m). Der alte Saum warf sie mit
			# 3,0 bis 5,3 m zu GROSS — neben der 30-m-Bahn las sich das als Felsblock.
			var s := rng.randf_range(0.45, 1.15)
			felsen.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				.scaled(Vector3(s * 1.5, s * 0.8, s * 1.2)), Vector3(x, s * 0.2, z)))
		elif d > 30.0 and rng.randf() < 0.42:
			# Einzelbaeume ab 30 m Abstand — sie fuellen die Luecke zwischen Bahnkante und
			# dem Punkt, ab dem das Gelaende volle Dichte faehrt.
			var s2 := rng.randf_range(0.8, 1.5)
			baeume.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				.scaled(Vector3(s2, s2 * rng.randf_range(0.85, 1.25), s2)), Vector3(x, 0.0, z)))
	_trockenflecken(node, rng, felsen)
	_multi(node, _baum_mesh(), baeume, null)
	var fels := SphereMesh.new()
	fels.radius = 1.1
	fels.height = 1.8
	fels.radial_segments = 6
	fels.rings = 3
	_multi(node, fels, felsen, _flat_mat(Color(0.46, 0.44, 0.40), 1.0))
	# --- PLATZZAUN westlich der Bahn (in heimat_1 und heimat_2 laeuft er dort mit) ---
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
		lines.append("Schub: %d N%s" % [int(p["thrust"]), ("  (Jet)" if p.get("jet", false) else "")])
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


func _rand_target_pos(ymin: float, ymax: float) -> Vector3:
	# vor der Startbahn (Flieger schaut nach -Z), gut erreichbar
	return Vector3(randf_range(-380.0, 380.0), randf_range(ymin, ymax), randf_range(-750.0, -30.0))


func _make_target(kind: String, pos: Vector3, col: Color, diff := 1.0) -> void:
	var t := Target.new()
	targets_root.add_child(t)
	t.setup(kind, pos, col, diff)
	t.killed.connect(_on_target_killed)


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
