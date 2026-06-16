## Main.gd
## Zentrale: Welt/Licht/Himmel, Modus-Umschaltung (Hangar <-> Flug),
## komplettes UI + HUD, Speichern/Laden und das Start-Flugzeug.
extends Node3D

enum Mode { BUILD, FLY }

const SAVE_PATH := "user://aircraft_design.json"   # Autoload: zuletzt gebautes/geladenes
const SLOT_DIR := "user://hangar"                  # benannte eigene Speicher-Slots

# Blueprint-Gitter-Shader (anti-aliased, zum Horizont ausgeblendet)
const _BLUEPRINT_GRID_SHADER := "
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec3 line_color : source_color = vec3(0.55, 0.67, 0.82);
uniform vec3 major_color : source_color = vec3(0.38, 0.53, 0.72);
uniform vec3 bg_color : source_color = vec3(0.78, 0.83, 0.88);
uniform float cell = 1.0;
uniform float fade_dist = 95.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float grid_a(vec2 p, float div) {
	vec2 c = p / div;
	vec2 g = abs(fract(c - 0.5) - 0.5) / fwidth(c);
	return 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
}
void fragment() {
	vec2 p = wpos.xz;
	float minor = grid_a(p, cell);
	float major = grid_a(p, cell * 10.0);
	vec3 col = mix(bg_color, line_color, minor * 0.55);
	col = mix(col, major_color, major);
	float fade = clamp(1.0 - length(p) / fade_dist, 0.0, 1.0);
	ALBEDO = mix(bg_color, col, fade);
}
"

var mode: int = Mode.BUILD
var camera: Camera3D
var build_ctrl: BuildController
var flight_ctrl: FlightController

var fly_world: Node3D
var blueprint_grid: MeshInstance3D
var airfields: Array = []
var world_env: WorldEnvironment
var terrain: TerrainWorld           # seed-basierte Landschaft (Chunks um den Spieler)
var hangar_lights: Node3D           # Studio-Beleuchtung NUR für den Bau-Modus
var sky_lights: Node3D              # Sonne + Fülllicht NUR für den Flug
var env_sky: Environment
var env_blueprint: Environment

# UI
var ui: CanvasLayer
var build_root: Control
var flight_root: Control
var stats_label: Label
var ampel_label: Label              # "Fliegt's?"-Ampel (grün/gelb/rot + Tipp)
var hud_label: Label
var land_label: Label
var flight_hud: FlightHud           # Primary-Flight-Display (Kompass, Speed/Höhe, Zielkreis)
var tool_label: Label
var toast_label: Label
var pause_overlay: Control          # Pause-Menü (Esc)
var _paused := false
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _hint_box: Control              # einmaliger Steuer-Hinweis beim ersten Flug
var snap_cb: CheckBox               # Auto-Andocken an/aus (Bau-Editor)
var drag_view_btn: Button
var wind_legend: Control            # Farb-Legende, nur bei aktivem Windkanal sichtbar
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
var _blink_t := 0.0
const COMBO_WINDOW := 5.0          # Sekunden zwischen Abschüssen, um die Combo zu halten
var part_list_box: VBoxContainer   # Palette (zum Neuaufbau nach Kauf)
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
var sel_mode_btns: Array = []      # [Bewegen, Drehen, Skalieren] zum Hervorheben des aktiven Modus
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
	_setup_ui()
	if not _load_design():
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
	# GOLDEN HOUR: warmer, cinematischer Flug-Himmel mit atmosphärischer Tiefe.
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.16, 0.26, 0.46)        # tiefes warmes Blau im Zenit
	psm.sky_horizon_color = Color(0.97, 0.72, 0.46)    # goldener Horizont
	psm.sky_curve = 0.12
	psm.sky_energy_multiplier = 1.1
	psm.ground_horizon_color = Color(0.80, 0.60, 0.42)
	psm.ground_bottom_color = Color(0.28, 0.26, 0.26)
	psm.sun_angle_max = 7.0
	psm.sun_curve = 0.08
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.ambient_light_color = Color(0.74, 0.80, 0.92)  # kühles Himmels-Ambient -> Schatten bleiben kühl
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.15
	# Atmosphärische Tiefe: warmer Dunst, der erst in der FERNE aufbaut (Nahgrund bleibt grün),
	# Sonne streut hinein, Fernes blendet sanft zur Himmelsfarbe (aerial perspective).
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.96, 0.80, 0.62)
	env.fog_sun_scatter = 0.35
	env.fog_density = 0.00036
	env.fog_aerial_perspective = 0.24
	env.fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 0.95
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.0
	env_sky = env

	# Blueprint-Umgebung für den Bau-Modus (tiefblauer Raum). Hintergrund bleibt dunkel,
	# aber ein blauer Gradient-Himmel dient als REFLEXIONS- und Ambient-Quelle -> metallische
	# Teile spiegeln (oben hell, unten dunkel) und das Drehen ändert die Reflexion sichtbar.
	# HELLER TAGESLICHT-EDITOR (Feeling wie im Original-Aviassembly): freundlicher
	# blauer Himmel mit fast weißem Horizont als Hintergrund UND Licht-/Reflexions-
	# quelle — kein dunkler Raum mehr, das Flugzeug steht wie draußen am Flugfeld.
	var sky_bp := Sky.new()
	var psm_bp := ProceduralSkyMaterial.new()
	psm_bp.sky_top_color = Color(0.42, 0.64, 0.90)
	psm_bp.sky_horizon_color = Color(0.87, 0.92, 0.97)
	psm_bp.ground_horizon_color = Color(0.86, 0.91, 0.96)
	psm_bp.ground_bottom_color = Color(0.76, 0.81, 0.87)
	psm_bp.sky_energy_multiplier = 1.0
	sky_bp.sky_material = psm_bp
	env_blueprint = Environment.new()
	env_blueprint.background_mode = Environment.BG_SKY
	env_blueprint.sky = sky_bp
	env_blueprint.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env_blueprint.ambient_light_energy = 1.3
	env_blueprint.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env_blueprint.tonemap_mode = Environment.TONE_MAPPER_ACES
	env_blueprint.ssao_enabled = true
	env_blueprint.ssao_intensity = 1.1
	env_blueprint.ssao_radius = 1.4
	env_blueprint.glow_enabled = true
	env_blueprint.glow_intensity = 0.3
	env_blueprint.glow_strength = 0.9
	env_blueprint.glow_hdr_threshold = 1.1

	world_env = WorldEnvironment.new()
	world_env.environment = env_sky
	add_child(world_env)

	# --- Flug-Beleuchtung: Sonne + Fülllicht (nur im Flug aktiv) ---
	sky_lights = Node3D.new()
	add_child(sky_lights)
	# Tiefe, warme Sonne (Golden Hour) — lange weiche Schatten, kräftiges Schlüssellicht
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-16, -52, 0)
	sun.light_color = Color(1.0, 0.78, 0.52)
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	sky_lights.add_child(sun)
	var underfill := DirectionalLight3D.new()
	underfill.rotation_degrees = Vector3(50, 120, 0)
	underfill.light_color = Color(0.55, 0.62, 0.80)   # kühles Himmels-Gegenlicht
	underfill.light_energy = 0.35
	underfill.shadow_enabled = false
	sky_lights.add_child(underfill)

	# --- HANGAR-STUDIO-RIG (nur im Bau-Modus aktiv): klassisches 3-Punkt-Licht ---
	# Key warm + Schatten (Form), Fill kühl von rechts (weiche Schattenseite),
	# Rim von hinten-oben (Kantenlicht trennt vom dunklen Raum), Underfill dezent.
	hangar_lights = Node3D.new()
	add_child(hangar_lights)
	# KEINE SONNE (Nutzerwunsch): weiches, richtungsarmes Softbox-Licht wie an
	# einem bedeckten Tag — keine Schatten, keine harte Lichtkante. Zwei ganz
	# schwache, schattenlose Aufheller geben den Teilen minimale Plastizität,
	# die Hauptarbeit macht der helle Himmels-Ambient.
	var soft_top := DirectionalLight3D.new()
	soft_top.rotation_degrees = Vector3(-62, -20, 0)
	soft_top.light_energy = 0.45
	soft_top.light_color = Color(1.0, 0.99, 0.96)
	soft_top.shadow_enabled = false
	soft_top.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY   # keine Sonnenscheibe im Himmel
	hangar_lights.add_child(soft_top)
	var soft_side := DirectionalLight3D.new()
	soft_side.rotation_degrees = Vector3(-18, 135, 0)
	soft_side.light_energy = 0.22
	soft_side.light_color = Color(0.85, 0.90, 1.0)
	soft_side.shadow_enabled = false
	soft_side.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	hangar_lights.add_child(soft_side)
	var hfill := DirectionalLight3D.new()
	hfill.rotation_degrees = Vector3(58, 40, 0)
	hfill.light_energy = 0.28
	hfill.shadow_enabled = false
	hfill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	hangar_lights.add_child(hfill)

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
	]

	# SEED-BASIERTES TERRAIN ersetzt die flache Platte + Deko-Berge/-See.
	# Jeder Flugplatz bekommt eine Einebnungs-Zone (HEIMAT größer — dort liegt
	# auch der Hindernis-Parcours). Seed kommt aus dem Spielstand (einmal
	# gewürfelt, dann stabil — dieselbe Welt bei jedem Start).
	if game.world_seed == 0:
		game.world_seed = randi() % 1000000
		game.save()
	terrain = TerrainWorld.new()
	var flat_zones: Array = []
	for af in airfields:
		var is_main: bool = af.get("main", false)
		flat_zones.append({"pos": af["pos"], "r_flat": 1700.0 if is_main else 750.0,
			"r_blend": 2300.0 if is_main else 1200.0})
	terrain.setup(game.world_seed, flat_zones)
	fly_world.add_child(terrain)
	terrain.build_now_around(Vector3.ZERO, 900.0)   # Spawn-Bereich sofort (Kollision!)
	for af in airfields:
		_build_airfield(af)
	_build_obstacles()   # solider Hindernis-Parcours nahe HEIMAT (Tore, Pylonen, Felsen, Sperrballons)

	# Blueprint-Gitter (nur im Bau-Modus sichtbar)
	blueprint_grid = MeshInstance3D.new()
	var gp := PlaneMesh.new()
	gp.size = Vector2(260, 260)
	blueprint_grid.mesh = gp
	blueprint_grid.position = Vector3(0, -1.9, 0)
	var grid_shader := Shader.new()
	grid_shader.code = _BLUEPRINT_GRID_SHADER
	var gsm := ShaderMaterial.new()
	gsm.shader = grid_shader
	blueprint_grid.material_override = gsm
	add_child(blueprint_grid)
	blueprint_grid.visible = false


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


func _build_airfield(af: Dictionary) -> void:
	var node := Node3D.new()
	node.position = af["pos"]
	node.rotation.y = af["heading"]
	fly_world.add_child(node)
	var hl := RWY_LEN * 0.5
	var asphalt := _flat_mat(Color(0.16, 0.16, 0.18), 0.95)
	var concrete := _flat_mat(Color(0.55, 0.56, 0.58), 0.9)
	var paint := _emit_mat(Color(0.93, 0.93, 0.88), 0.18)
	var paint_y := _emit_mat(Color(0.95, 0.8, 0.2), 0.18)

	# --- Bahn (flach, damit Räder nicht einsinken) + Schulter ---
	_deco_box(node, Vector3(0, 0.04, 0), Vector3(RWY_W, 0.08, RWY_LEN), asphalt)
	_deco_box(node, Vector3(0, 0.02, 0), Vector3(RWY_W + 8.0, 0.04, RWY_LEN + 30.0), _flat_mat(Color(0.28, 0.36, 0.26), 1.0))
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
	_deco_box(node, Vector3(34.0, 0.035, 10.0), Vector3(12.0, 0.07, 160.0), concrete)         # Rollweg parallel
	_deco_box(node, Vector3(22.0, 0.035, -60.0), Vector3(24.0, 0.07, 12.0), concrete)         # Verbinder Nord
	_deco_box(node, Vector3(22.0, 0.035, 80.0), Vector3(24.0, 0.07, 12.0), concrete)          # Verbinder Süd
	_deco_box(node, Vector3(62.0, 0.035, 10.0), Vector3(45.0, 0.07, 110.0), concrete)         # Apron
	_deco_box(node, Vector3(34.0, 0.09, 10.0), Vector3(0.5, 0.03, 150.0), paint_y)            # Rollweg-Gelblinie
	# --- Gebäude aufs Vorfeld ---
	_add_hangar(node, Vector3(68, 0, -20), af["color"])
	_add_hangar(node, Vector3(68, 0, 15), af["color"])
	_add_tower(node, Vector3(58, 0, 55))
	_add_windsock(node, Vector3(-24, 0, -hl + 60.0))
	# Tankstelle: zwei weiße Zylinder
	for tz in [44.0, 52.0]:
		var tank := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 3.0
		cm.bottom_radius = 3.0
		cm.height = 7.0
		tank.mesh = cm
		tank.position = Vector3(74.0, 3.5, tz)
		tank.material_override = _flat_mat(Color(0.9, 0.9, 0.92), 0.4)
		node.add_child(tank)
		_collider_box(node, Vector3(74.0, 3.5, tz), Vector3(6.5, 7, 6.5))
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
	# HEIMAT = Hauptbasis: großes Extra-Paket (Radar, Großhangar, Flutlicht, Helipad, …)
	if af.get("main", false):
		_build_main_base(node, af["color"])


# Hauptbasis-Ausbau für HEIMAT: erweitertes Vorfeld, offener Großhangar (begehbar),
# drehender Radarturm, Tower-Antenne mit Blinklicht, Flutlicht-Masten, Helipad,
# Splitterschutz-Boxen (Blast Pens) mit GEPARKTEN Flugzeugen aus den Vorlagen.
func _build_main_base(node: Node3D, col: Color) -> void:
	var concrete := _flat_mat(Color(0.55, 0.56, 0.58), 0.9)
	var dark := _flat_mat(Color(0.3, 0.31, 0.33), 0.85)
	# --- Vorfeld nach Osten erweitern ---
	_deco_box(node, Vector3(95.0, 0.03, 0.0), Vector3(40.0, 0.06, 150.0), concrete)
	# --- Offener Großhangar (man sieht/rollt hinein): Rückwand, 2 Seiten, Dach ---
	var hcol := col.darkened(0.15)
	_deco_box(node, Vector3(112.0, 6.0, -15.0), Vector3(1.2, 12.0, 34.0), _flat_mat(hcol, 0.7))    # Rückwand
	_collider_box(node, Vector3(112.0, 6.0, -15.0), Vector3(1.2, 12.0, 34.0))
	for sz in [-32.0, 2.0]:
		_deco_box(node, Vector3(101.0, 6.0, sz), Vector3(22.0, 12.0, 1.2), _flat_mat(hcol, 0.7))   # Seitenwände
		_collider_box(node, Vector3(101.0, 6.0, sz), Vector3(22.0, 12.0, 1.2))
	_deco_box(node, Vector3(101.0, 12.4, -15.0), Vector3(24.0, 0.8, 35.0), _flat_mat(hcol.darkened(0.25), 0.7))  # Dach
	_collider_box(node, Vector3(101.0, 12.4, -15.0), Vector3(24.0, 0.8, 35.0))
	_deco_box(node, Vector3(101.0, 0.05, -15.0), Vector3(22.0, 0.05, 33.0), dark)                  # dunkler Boden
	_add_parked_plane(node, "spitfire", Vector3(102.0, 1.0, -15.0), 90.0)                          # Flieger IM Hangar
	# --- Radarturm mit DREHENDER Schüssel ---
	var rt := Vector3(45.0, 0.0, 105.0)
	_deco_box(node, rt + Vector3(0, 7.0, 0), Vector3(4.0, 14.0, 4.0), _flat_mat(Color(0.6, 0.62, 0.65), 0.6))
	_collider_box(node, rt + Vector3(0, 7.0, 0), Vector3(4.0, 14.0, 4.0))
	var pivot := Node3D.new()
	pivot.position = rt + Vector3(0, 14.6, 0)
	node.add_child(pivot)
	var dish := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 3.6
	dm.bottom_radius = 3.6
	dm.height = 0.5
	dish.mesh = dm
	dish.position = Vector3(0, 1.2, 0)
	dish.rotation_degrees = Vector3(58, 0, 0)
	dish.material_override = _flat_mat(Color(0.85, 0.87, 0.9), 0.4)
	pivot.add_child(dish)
	_spin_nodes.append(pivot)
	# --- Tower-Antenne mit rotem Blinklicht (Tower steht bei 58/55) ---
	_deco_box(node, Vector3(58.0, 28.0, 55.0), Vector3(0.4, 6.0, 0.4), _flat_mat(Color(0.7, 0.7, 0.72), 0.5))
	var bl := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.5
	bs.height = 1.0
	bl.mesh = bs
	bl.position = Vector3(58.0, 31.6, 55.0)
	bl.material_override = _emit_mat(Color(1.0, 0.15, 0.1), 3.0)
	node.add_child(bl)
	_blink_nodes.append(bl)
	# --- 4 Flutlicht-Masten um das Vorfeld ---
	for fp in [Vector3(40, 0, -52), Vector3(112, 0, 30), Vector3(40, 0, 72), Vector3(112, 0, 60)]:
		_deco_box(node, fp + Vector3(0, 6.5, 0), Vector3(0.7, 13.0, 0.7), _flat_mat(Color(0.5, 0.5, 0.54), 0.6))
		_collider_box(node, fp + Vector3(0, 6.5, 0), Vector3(0.9, 13.0, 0.9))
		_deco_box(node, fp + Vector3(0, 13.2, 0), Vector3(2.4, 0.9, 1.0), _emit_mat(Color(1.0, 0.97, 0.85), 1.6))
	_build_base_life(node)
	# --- Helipad westlich der Bahn ---
	var hp := Vector3(-40.0, 0.0, 70.0)
	var pad := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 10.0
	pc.bottom_radius = 10.0
	pc.height = 0.08
	pad.mesh = pc
	pad.position = hp + Vector3(0, 0.04, 0)
	pad.material_override = dark
	node.add_child(pad)
	var hl3 := Label3D.new()
	hl3.text = "H"
	hl3.font_size = 380
	hl3.pixel_size = 0.05
	hl3.modulate = Color(0.95, 0.95, 0.9)
	hl3.position = hp + Vector3(0, 0.12, 0)
	hl3.rotation_degrees = Vector3(-90, 0, 0)
	node.add_child(hl3)
	for ang in range(8):
		var a := float(ang) * TAU / 8.0
		_deco_light(node, hp + Vector3(cos(a) * 10.5, 0.3, sin(a) * 10.5), Color(1.0, 0.8, 0.25))
	# --- Zwei Splitterschutz-Boxen (Blast Pens) mit geparkten Jets ---
	for px in [52.0, 80.0]:
		var pp := Vector3(px, 0.0, -68.0)
		_deco_box(node, pp + Vector3(0, 2.6, -7.0), Vector3(16.0, 5.2, 1.6), dark)     # Rückwand
		_collider_box(node, pp + Vector3(0, 2.6, -7.0), Vector3(16.0, 5.2, 1.6))
		for sx in [-8.0, 8.0]:
			_deco_box(node, pp + Vector3(sx, 2.6, 0.0), Vector3(1.6, 5.2, 15.0), dark)  # Seitenwälle
			_collider_box(node, pp + Vector3(sx, 2.6, 0.0), Vector3(1.6, 5.2, 15.0))
	_add_parked_plane(node, "f86", Vector3(52.0, 1.0, -66.0), 180.0)
	_add_parked_plane(node, "mig15", Vector3(80.0, 1.0, -66.0), 180.0)
	# --- Geparkte Mustang auf dem Vorfeld ---
	_add_parked_plane(node, "mustang_p51", Vector3(62.0, 1.0, 35.0), 215.0)


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
	_deco_truck(node, Vector3(88.0, 0.0, 20.0), 35.0, yellow, true)
	# --- FEUERWEHR: kleines Haus + roter Truck davor ---
	var fh := Vector3(50.0, 0.0, 88.0)
	_deco_box(node, fh + Vector3(0, 3.0, 0), Vector3(12.0, 6.0, 10.0), red)
	_collider_box(node, fh + Vector3(0, 3.0, 0), Vector3(12.0, 6.0, 10.0))
	_deco_box(node, fh + Vector3(0, 6.3, 0), Vector3(13.0, 0.6, 11.0), _flat_mat(Color(0.92, 0.92, 0.95), 0.7))
	_deco_box(node, fh + Vector3(-3.0, 2.2, 5.1), Vector3(4.5, 4.4, 0.2), darkm)   # Tor
	_deco_truck(node, fh + Vector3(4.0, 0.0, 9.0), 90.0, red, false)
	# --- GEPÄCK-ZUG: Zugmaschine + 2 Anhänger ---
	var bz := Vector3(78.0, 0.0, 42.0)
	_deco_box(node, bz + Vector3(0, 0.8, 0), Vector3(2.0, 1.2, 3.0), metal)
	_collider_box(node, bz + Vector3(0, 0.8, 0), Vector3(2.0, 1.2, 3.0))
	for i in [1, 2]:
		_deco_box(node, bz + Vector3(0, 0.7, 3.6 * float(i)), Vector3(1.8, 1.0, 2.6), darkm)
		_deco_box(node, bz + Vector3(0, 1.35, 3.6 * float(i)), Vector3(1.6, 0.5, 2.2), yellow)
	# --- PYLONEN-Reihe am Vorfeldrand ---
	var cone := _flat_mat(Color(1.0, 0.45, 0.1), 0.6)
	for i in 6:
		var cp := Vector3(72.0, 0.0, -40.0 + float(i) * 6.0)
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
	for spz in [-30.0, 10.0, 50.0]:
		_deco_box(node, Vector3(63.0, 0.55, spz), Vector3(0.25, 1.1, 1.8), darkm)
		_deco_box(node, Vector3(63.0, 0.75, spz), Vector3(0.3, 0.5, 1.5), yellow)
	# --- DREHFEUER auf dem Tower (rotierender Doppel-Strahl, grün/weiß) ---
	var beacon_pivot := Node3D.new()
	beacon_pivot.position = Vector3(58.0, 26.0, 55.0)
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
	# --- ANTENNEN-FARM hinterm Tower ---
	for i in 3:
		var ap := Vector3(66.0 + float(i) * 4.0, 0.0, 62.0)
		var hgt := 9.0 + float(i) * 3.0
		_deco_box(node, ap + Vector3(0, hgt * 0.5, 0), Vector3(0.25, hgt, 0.25), metal)
		_deco_light(node, ap + Vector3(0, hgt + 0.3, 0), Color(1.0, 0.2, 0.15))


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


# Windsack: Mast + orangener Kegel (zeigt dekorativ quer zur Bahn).
func _add_windsock(parent: Node3D, pos: Vector3) -> void:
	var mast := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.12
	mm.bottom_radius = 0.18
	mm.height = 8.0
	mast.mesh = mm
	mast.position = pos + Vector3(0, 4, 0)
	mast.material_override = _flat_mat(Color(0.75, 0.75, 0.78), 0.5)
	parent.add_child(mast)
	var sock := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.18
	sm.bottom_radius = 0.55
	sm.height = 3.2
	sock.mesh = sm
	sock.position = pos + Vector3(1.7, 7.6, 0)
	sock.rotation_degrees = Vector3(0, 0, -90)
	sock.material_override = _emit_mat(Color(1.0, 0.45, 0.1), 0.3)
	parent.add_child(sock)


func _add_hangar(parent: Node3D, pos: Vector3, col: Color) -> void:
	var h := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(16, 7, 12)
	h.mesh = b
	h.position = pos + Vector3(0, 3.5, 0)
	h.material_override = _flat_mat(col, 0.7)
	parent.add_child(h)
	var roof := MeshInstance3D.new()
	var pr := PrismMesh.new()
	pr.size = Vector3(16.6, 3, 12)
	roof.mesh = pr
	roof.position = pos + Vector3(0, 8.5, 0)
	roof.material_override = _flat_mat(col.darkened(0.3), 0.7)
	parent.add_child(roof)
	# solide Kollision: Box über Gebäude + Dach (man kann reinkrachen)
	_collider_box(parent, pos + Vector3(0, 5.0, 0), Vector3(16, 11, 12))


func _add_tower(parent: Node3D, pos: Vector3) -> void:
	var t := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(5, 22, 5)
	t.mesh = b
	t.position = pos + Vector3(0, 11, 0)
	t.material_override = _flat_mat(Color(0.82, 0.82, 0.86), 0.6)
	parent.add_child(t)
	var cab := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(8, 4, 8)
	cab.mesh = cb
	cab.position = pos + Vector3(0, 23, 0)
	var cm := _flat_mat(Color(0.2, 0.35, 0.5), 0.2)
	cm.metallic = 0.4
	cab.material_override = cm
	parent.add_child(cab)
	# solide Kollision: Turm + Kanzel
	_collider_box(parent, pos + Vector3(0, 13.5, 0), Vector3(8, 27, 8))




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
	camera.fov = 64.0
	camera.far = 9000.0
	camera.current = true
	add_child(camera)


func _setup_controllers() -> void:
	build_ctrl = BuildController.new()
	add_child(build_ctrl)
	build_ctrl.set_camera(camera)
	build_ctrl.design_changed.connect(_on_design_changed)
	build_ctrl.selection_changed.connect(_on_selection_changed)
	build_ctrl.snap_changed.connect(_on_snap_changed)

	flight_ctrl = FlightController.new()
	add_child(flight_ctrl)
	flight_ctrl.set_camera(camera)
	flight_ctrl.hud_changed.connect(_on_hud_changed)


# ===========================================================================
# MODUS
# ===========================================================================
func _set_mode(m: int) -> void:
	# Nicht starten, wenn Teile frei schweben (nicht mit dem Flugzeug verbunden).
	if m == Mode.FLY and mode == Mode.BUILD and build_ctrl != null and build_ctrl.has_floating():
		_toast("⚠ %d Teil(e) hängen frei (rot markiert) — erst verbinden, dann Start" % build_ctrl.floating_count())
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
	blueprint_grid.visible = building
	fly_world.visible = not building
	if hangar_lights != null:
		hangar_lights.visible = building   # Studio-Rig nur im Hangar
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
	var t := _lbl("⏸  PAUSE", 30, Color(0.6, 1.0, 0.7))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b_resume := Button.new()
	b_resume.text = "▶  Weiter"
	b_resume.pressed.connect(func(): _set_pause(false))
	v.add_child(b_resume)
	# Maus-Flug-Empfindlichkeit (0.5–2.0, persistiert in GameState)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	v.add_child(srow)
	srow.add_child(_lbl("🖱 Maus-Empfindlichkeit:", 14, Color(0.8, 0.88, 1.0)))
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
	b_hangar.text = "🛠  Zum Hangar"
	b_hangar.pressed.connect(_pause_to_hangar)
	v.add_child(b_hangar)
	var b_quit := Button.new()
	b_quit.text = "✕  Spiel beenden"
	b_quit.pressed.connect(func(): get_tree().quit())
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
	var lbl := _lbl("🛩  STEUERUNG  (blendet gleich aus)\n\nW/S = Nase hoch/runter    ·    A/D = rollen (A = RECHTS!)\nQ/E = gieren    ·    Shift / Strg = Schub / bremsen\nLeertaste = feuern    ·    B = Bombe    ·    G = Fahrwerk\nM = Maus-/Tastatur-Flug (Start: MAUS)    ·    H = G-Schutz    ·    J = Arcade    ·    T = Assist\nEnter = Reset/Reparatur    ·    Tab = zurück zum Hangar    ·    Esc = Pause", 15, Color(0.86, 0.95, 1.0))
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
	var th := Theme.new()
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.11, 0.15, 0.21, 0.92)
	n.set_corner_radius_all(6)
	n.set_border_width_all(1)
	n.border_color = Color(1, 1, 1, 0.10)
	n.content_margin_left = 10
	n.content_margin_right = 10
	n.content_margin_top = 5
	n.content_margin_bottom = 5
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = Color(0.16, 0.23, 0.33, 0.96)
	h.border_color = Color(0.45, 0.72, 1.0, 0.45)
	var pr: StyleBoxFlat = n.duplicate()
	pr.bg_color = Color(0.10, 0.26, 0.46, 0.97)
	pr.border_color = Color(0.5, 0.78, 1.0, 0.85)
	var dis: StyleBoxFlat = n.duplicate()
	dis.bg_color = Color(0.09, 0.11, 0.14, 0.6)
	th.set_stylebox("normal", "Button", n)
	th.set_stylebox("hover", "Button", h)
	th.set_stylebox("pressed", "Button", pr)
	th.set_stylebox("disabled", "Button", dis)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(0.92, 0.95, 1.0))
	th.set_color("font_hover_color", "Button", Color(1, 1, 1))
	th.set_color("font_pressed_color", "Button", Color(0.85, 0.95, 1.0))
	th.set_color("font_disabled_color", "Button", Color(0.6, 0.65, 0.72))
	# Checkboxen: kein Knopf-Kasten, nur Haken + Text (ruhiger)
	th.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	th.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	th.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	th.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	th.set_color("font_color", "CheckBox", Color(0.88, 0.92, 0.98))
	# Tooltips: dunkel-glasig mit Akzentrand (Teil-Infos lesen sich deutlich besser)
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.06, 0.09, 0.13, 0.97)
	tip.set_corner_radius_all(8)
	tip.set_border_width_all(1)
	tip.border_color = Color(0.45, 0.72, 1.0, 0.4)
	tip.set_content_margin_all(10)
	th.set_stylebox("panel", "TooltipPanel", tip)
	th.set_color("font_color", "TooltipLabel", Color(0.93, 0.96, 1.0))
	# Trenner dezent
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.12)
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
	_build_flight_ui()


func _build_hangar_ui() -> void:
	# --- Linkes Teile-Panel ---
	var panel := _panel(Color(0, 0, 0, 0.5))
	_rect(panel, 0, 0, 0, 1, 10, 10, 248, -10)
	build_root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var title := _lbl("🛠  HANGAR", 21, Color(0.92, 0.96, 1.0))
	vb.add_child(title)
	money_label = _lbl("", 15, Color(1.0, 0.86, 0.3))
	vb.add_child(money_label)
	tool_label = _lbl("Werkzeug: —", 13, Color(0.7, 1.0, 0.7))
	# WICHTIG: Umbruch an, sonst zwingt der lange Text die ganze Panel-Box auf Textbreite auf.
	tool_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_label.custom_minimum_size = Vector2(0, 0)
	vb.add_child(tool_label)
	vb.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	part_list_box = VBoxContainer.new()
	part_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	part_list_box.add_theme_constant_override("separation", 3)
	scroll.add_child(part_list_box)
	_fill_part_list(part_list_box)

	upgrade_box = VBoxContainer.new()
	upgrade_box.add_theme_constant_override("separation", 2)
	vb.add_child(upgrade_box)

	vb.add_child(HSeparator.new())
	var move_btn := Button.new()
	move_btn.text = "✋  Bewegen / Greifen"
	move_btn.pressed.connect(_on_move_tool)
	vb.add_child(move_btn)
	var erase_btn := Button.new()
	erase_btn.text = "🧹  Abriss-Modus"
	erase_btn.pressed.connect(_on_erase_tool)
	vb.add_child(erase_btn)

	# --- Lackieren ---
	vb.add_child(_lbl("🎨  Lackieren — Farbe wählen, dann Teil klicken:", 12, Color(0.82, 0.9, 1.0)))
	var pal := GridContainer.new()
	pal.columns = 7
	vb.add_child(pal)
	var colors: Array = [
		Color("d6382f"), Color("e8821a"), Color("eccb47"), Color("46a85a"),
		Color("2f74bd"), Color("8e44ad"), Color("19bfc7"), Color("eef0f4"),
		Color("9aa3ad"), Color("3a4049"), Color("121519"), Color("6e4a2c"),
		Color("e85b9a"), Color("8bd24a"),
	]
	for c in colors:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(26, 22)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(4)
		sw.add_theme_stylebox_override("normal", sb)
		sw.add_theme_stylebox_override("hover", sb)
		sw.add_theme_stylebox_override("pressed", sb)
		sw.add_theme_stylebox_override("focus", sb)
		sw.pressed.connect(_on_paint_color.bind(c))
		pal.add_child(sw)

	# --- Undo / Redo / Ansicht ---
	var row3 := HBoxContainer.new()
	vb.add_child(row3)
	var undo_btn := Button.new()
	undo_btn.text = "↶ Undo"
	undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_btn.pressed.connect(_on_undo)
	row3.add_child(undo_btn)
	var redo_btn := Button.new()
	redo_btn.text = "↷ Redo"
	redo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	redo_btn.pressed.connect(_on_redo)
	row3.add_child(redo_btn)
	var cam_btn := Button.new()
	cam_btn.text = "🎯 Ansicht"
	cam_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cam_btn.pressed.connect(_on_reset_view)
	row3.add_child(cam_btn)

	drag_view_btn = Button.new()
	drag_view_btn.text = "🌬  Windkanal-Ansicht"
	drag_view_btn.toggle_mode = true
	drag_view_btn.toggled.connect(_on_drag_view)
	vb.add_child(drag_view_btn)
	# Farb-Legende der Heatmap (nur bei aktivem Windkanal eingeblendet)
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
	vb.add_child(leg)

	var sym := CheckBox.new()
	sym.text = "Symmetrie (beide Seiten)"
	sym.button_pressed = true
	sym.toggled.connect(_on_symmetry_toggled)
	vb.add_child(sym)

	snap_cb = CheckBox.new()
	snap_cb.text = "Andocken / Snapping  (Taste N)"
	snap_cb.button_pressed = true
	snap_cb.toggled.connect(_on_snap_toggled)
	vb.add_child(snap_cb)

	var row := HBoxContainer.new()
	vb.add_child(row)
	var clear_btn := Button.new()
	clear_btn.text = "Neu"
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_btn.pressed.connect(_on_clear_pressed)
	row.add_child(clear_btn)
	var save_btn := Button.new()
	save_btn.text = "Speichern"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_on_save_pressed)
	row.add_child(save_btn)
	var load_btn := Button.new()
	load_btn.text = "Laden"
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.pressed.connect(_on_load_pressed)
	row.add_child(load_btn)

	# Vorlagen (Spitfire/Mustang/…) und eigene Speicherstände liegen jetzt im »Laden«-Dialog.
	vb.add_child(_lbl("Vorlagen & eigene Flugzeuge: über »Laden« ↑", 11, Color(0.7, 0.8, 0.95)))

	# --- Testflug-Button oben mitte ---
	var fly_btn := Button.new()
	fly_btn.text = "▶  TESTFLUG STARTEN  (Tab)"
	fly_btn.add_theme_font_size_override("font_size", 18)
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
	_rect(fly_btn, 0.5, 0, 0.5, 0, -150, 10, 150, 52)
	fly_btn.pressed.connect(_on_fly_pressed)
	build_root.add_child(fly_btn)

	# --- Statistik oben rechts ---
	var spanel := _panel(Color(0, 0, 0, 0.5))
	# Höhe NICHT festnageln: nominell klein, der PanelContainer wächst mit dem
	# Inhalt nach unten (Windkanal-Report braucht mehr Zeilen als die Basisliste).
	_rect(spanel, 1, 0, 1, 0, -290, 10, -10, 80)
	build_root.add_child(spanel)
	var sv := VBoxContainer.new()
	spanel.add_child(sv)
	sv.add_child(_lbl("📊  STATISTIK", 16, Color(0.65, 0.82, 1.0)))
	ampel_label = _lbl("", 14, Color(0.6, 1.0, 0.6))
	ampel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(ampel_label)
	stats_label = _lbl("", 14)
	sv.add_child(stats_label)
	var legend := _lbl("● Schwerpunkt   ● Auftriebspunkt", 11, Color(0.85, 0.85, 0.85))
	sv.add_child(legend)

	_build_selection_panel()

	# --- Hinweisleiste unten ---
	var hint := _lbl("Aus Liste ziehen = bauen (rastet am Teil unter der Maus) · Teil ziehen = andocken wo du hinzeigst (Anbauten wandern mit · Alt = nur das Teil) · Teil klicken = bearbeiten (G/R/S) · Strg+D: duplizieren · Pfeile: verschieben · 1/2/3 Ansicht Front/Seite/Oben, 4 frei · X: löschen · M: Symmetrie · Strg+Z/Y: Undo · F: Ansicht", 13, Color(0.25, 0.32, 0.42))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(hint, 0, 1, 1, 1, 320, -34, -10, -8)
	build_root.add_child(hint)

	# Toast (kurze Meldung)
	toast_label = _lbl("", 15, Color(0.6, 1.0, 0.7))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(toast_label, 0.5, 0, 0.5, 0, -200, 66, 200, 92)
	build_root.add_child(toast_label)


func _fill_part_list(list: VBoxContainer) -> void:
	_part_group = ButtonGroup.new()
	_part_group.allow_unpress = true
	for cat in PartCatalog.categories():
		var parts := PartCatalog.parts_in(cat)
		if parts.is_empty():
			continue
		if not _cat_open.has(cat):
			_cat_open[cat] = true
		# --- aufklappbare Kategorie-Überschrift ---
		var header := Button.new()
		header.toggle_mode = true
		header.button_pressed = _cat_open[cat]
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_font_size_override("font_size", 13)
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hb := StyleBoxFlat.new()
		hb.bg_color = Color(0.35, 0.62, 1.0, 0.10)
		hb.set_corner_radius_all(6)
		hb.content_margin_left = 8
		hb.content_margin_top = 4
		hb.content_margin_bottom = 4
		var hbh: StyleBoxFlat = hb.duplicate()
		hbh.bg_color = Color(0.35, 0.62, 1.0, 0.20)
		header.add_theme_stylebox_override("normal", hb)
		header.add_theme_stylebox_override("hover", hbh)
		header.add_theme_stylebox_override("pressed", hb)
		header.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		header.add_theme_color_override("font_color", Color(0.65, 0.82, 1.0))
		header.add_theme_color_override("font_hover_color", Color(0.8, 0.9, 1.0))
		header.add_theme_color_override("font_pressed_color", Color(0.65, 0.82, 1.0))
		list.add_child(header)
		# --- Grid mit Vorschau-Kacheln ---
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		grid.visible = _cat_open[cat]
		list.add_child(grid)
		header.text = ("▾  " if _cat_open[cat] else "▸  ") + cat.to_upper() + "   (%d)" % parts.size()
		header.toggled.connect(func(on: bool) -> void:
			grid.visible = on
			_cat_open[cat] = on
			header.text = ("▾  " if on else "▸  ") + cat.to_upper() + "   (%d)" % parts.size()
		)
		for p in parts:
			grid.add_child(_make_part_tile(p))


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
	lines.append("Preis: %d 🪙" % PartCatalog.part_cost(p))
	return "\n".join(lines)


func _make_part_tile(p: Dictionary) -> Button:
	var id: String = p["id"]
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(0, 94)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.tooltip_text = _part_stats_text(p) + "\n→ in den Bauraum ziehen zum Setzen"
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
	nm.add_theme_font_size_override("font_size", 10)
	box.add_child(nm)

	var locked: bool = game != null and not game.is_unlocked(id)
	var mass := Label.new()
	mass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mass.add_theme_font_size_override("font_size", 9)
	if locked:
		mass.text = "🔒 %d 🪙" % PartCatalog.part_cost(p)
		mass.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
		tile.modulate = Color(0.68, 0.68, 0.74)   # gesperrt -> ausgegraut
		tile.tooltip_text = _part_stats_text(p) + "\n🔒 klicken zum Kaufen"
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
	vp.size = Vector2i(124, 74)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	svc.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.12, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.8)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -38, 0)
	key.light_energy = 1.25
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(18, 130, 0)
	fill.light_energy = 0.45
	vp.add_child(fill)

	var vis := PartCatalog.build_visual(p)
	vp.add_child(vis)

	# Kamera so setzen, dass das Teil formatfüllend im 3/4-Winkel sitzt
	var aabb := _visual_aabb(vis)
	var center: Vector3 = aabb.get_center()
	var radius: float = maxf(aabb.size.length() * 0.5, 0.4)
	var cam := Camera3D.new()
	cam.fov = 36.0
	var dist: float = radius / tan(deg_to_rad(cam.fov * 0.5)) * 1.06
	var dir: Vector3 = Vector3(0.82, 0.58, 1.0).normalized()
	var pos: Vector3 = center + dir * dist
	# look_at() braucht den Baum — hier noch nicht eingehängt, daher from_position:
	cam.look_at_from_position(pos, center, Vector3.UP)
	cam.current = true
	vp.add_child(cam)
	return svc


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
			_toast("Gekauft: %s  (−%d 🪙)" % [p.get("name", id), cost])
			_rebuild_palette()
		else:
			_toast("Zu teuer: %s kostet %d 🪙 (du hast %d)" % [p.get("name", id), cost, game.money])


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
	sel_title = _lbl("✦ Ausgewählt", 15, Color(0.55, 1.0, 0.7))
	v.add_child(sel_title)
	sel_scale_label = _lbl("", 12, Color(0.8, 0.85, 0.95))
	v.add_child(sel_scale_label)
	# --- Modus-Umschaltung (Blender-artig: Bewegen/Drehen/Skalieren, Tasten G/R/S) ---
	v.add_child(_lbl("Werkzeug (G / R / S):", 11, Color(0.82, 0.82, 0.88)))
	var mrow := HBoxContainer.new()
	v.add_child(mrow)
	sel_mode_btns.clear()
	var modes := [["↔ Bewegen", 0], ["↻ Drehen", 1], ["⤢ Skalieren", 2], ["⇿ Enden", 3]]
	for md in modes:
		var mb := Button.new()
		mb.text = md[0]
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.add_theme_font_size_override("font_size", 11)
		mb.pressed.connect(build_ctrl.set_gizmo_mode.bind(md[1]))
		mrow.add_child(mb)
		sel_mode_btns.append(mb)
	v.add_child(_lbl("Pfeile/Würfel im 3D-Raum ziehen · Drehen: Teil ziehen · 90°-Schritte unten:", 10, Color(0.7, 0.74, 0.82)))
	v.add_child(_lbl("⇿ Enden (Rumpf, auch per Rechtsklick): 4 Vierecke — vorne/hinten je X (seitlich) + Y (oben) — auswärts ziehen = dicker.", 10, Color(0.55, 0.72, 0.95)))
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
	rot.text = "↻ Drehen"
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
	sel_reverse_cb.text = "↩  Schub umkehren"
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
	sel_delete_btn.text = "🗑  Löschen"
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
	sel_title.text = "✦ %s" % info.get("name", "Teil")
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
	if sel_mode_btns.size() >= 4:
		sel_mode_btns[3].visible = biends
	# »Schub umkehren« nur bei Prop-Triebwerken zeigen; Haken ohne Signal setzen
	if sel_reverse_cb:
		sel_reverse_cb.visible = info.get("is_prop", false)
		sel_reverse_cb.set_pressed_no_signal(info.get("thrust_reverse", false))


func _on_erase_tool() -> void:
	build_ctrl.set_erase_mode(true)
	_refresh_tool_ui()


func _on_paint_color(c: Color) -> void:
	build_ctrl.set_paint_color(c)
	_refresh_tool_ui()


func _on_undo() -> void:
	build_ctrl.undo()


func _on_redo() -> void:
	build_ctrl.redo()


func _on_reset_view() -> void:
	build_ctrl.reset_camera()


func _on_drag_view(on: bool) -> void:
	build_ctrl.set_wind_tunnel(on)
	if wind_legend != null:
		wind_legend.visible = on
	if on:
		var worst: String = build_ctrl.wind_worst
		var tip := "nur angeströmte Teile gefärbt (grau = Windschatten)"
		if worst != "":
			tip = "rot = größter Widerstand: %s (grau = Windschatten)" % worst
		_toast("🌬 Windkanal AN — " + tip)
	else:
		_toast("Windkanal aus")


func _refresh_tool_ui() -> void:
	var sel := "" if (build_ctrl.erase_mode or build_ctrl.paint_mode) else build_ctrl.brush_id
	for pid in part_buttons:
		part_buttons[pid].set_pressed_no_signal(pid == sel)
	if build_ctrl.erase_mode:
		tool_label.text = "Werkzeug: 🧹 Abriss – Teil anklicken zum Löschen"
	elif build_ctrl.paint_mode:
		tool_label.text = "Werkzeug: 🎨 Lackieren – Teil anklicken zum Umfärben"
	elif build_ctrl.brush_id == "":
		tool_label.text = "Teil aus Liste ziehen = setzen · Teil anklicken = bearbeiten (G/R/S) · leer = drehen"
	else:
		var p := PartCatalog.get_part(build_ctrl.brush_id)
		tool_label.text = "Werkzeug: %s – ziehen & loslassen zum Setzen" % p.get("name", build_ctrl.brush_id)


func _build_flight_ui() -> void:
	# HUD oben links
	var hp := _panel(Color(0, 0, 0, 0.45))
	_rect(hp, 0, 0, 0, 0, 12, 12, 320, 290)
	flight_root.add_child(hp)
	var hv := VBoxContainer.new()
	hp.add_child(hv)
	hv.add_child(_lbl("✈  FLUG-HUD", 16, Color(0.6, 0.85, 1.0)))
	fly_money_label = _lbl("", 14, Color(1.0, 0.86, 0.3))
	hv.add_child(fly_money_label)
	hud_label = _lbl("", 15)
	hv.add_child(hud_label)

	# (Stall-Warnung zeichnet das PFD selbst: FlightHud._draw_stall — pulsierender
	#  Rahmen + Banner. Das frühere stall_label hier war eine Doppelung.)

	# Survival-HUD oben rechts (Welle / Abschüsse / Combo / Score)
	survival_label = _lbl("", 15, Color(0.7, 1.0, 0.8))
	survival_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rect(survival_label, 1, 0, 1, 0, -300, 44, -14, 120)
	survival_label.visible = false
	flight_root.add_child(survival_label)

	# Lande-/Schadensmeldung mitte
	land_label = _lbl("", 22, Color(1, 0.85, 0.3))
	land_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(land_label, 0.5, 0, 0.5, 0, -320, 124, 320, 158)
	flight_root.add_child(land_label)

	# Zurück-Button
	var back_btn := Button.new()
	back_btn.text = "◀  ZURÜCK ZUM HANGAR  (Tab)"
	back_btn.add_theme_font_size_override("font_size", 16)
	_rect(back_btn, 0.5, 0, 0.5, 0, -150, 10, 150, 48)
	back_btn.pressed.connect(_on_hangar_pressed)
	flight_root.add_child(back_btn)

	# Primary-Flight-Display (Custom-Drawing): Kompass oben, Speed/Höhe-Boxen, großer Zielkreis.
	flight_hud = FlightHud.new()
	flight_root.add_child(flight_hud)

	# Hinweisleiste unten
	var hint := _lbl("Maus: Zielen (Standard) · M: Tastatur-Modus · J: Arcade · Schub: Shift/Strg (>100 % = 🔥 Nachbrenner) · Nase: W/S · Rollen: A/D (halten = 🔄 Barrel Roll) · Gieren: Q/E · C halten: 👀 Umsehen · 🔫 LEERTASTE (gelber Pipper = echter Treffpunkt) · 💣 B · G: Fahrwerk · F: Klappen · H: G-Schutz · T: Assist · Enter: neu", 14, Color(0.92, 0.92, 0.92))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(hint, 0, 1, 1, 1, 10, -34, -10, -8)
	flight_root.add_child(hint)


# ===========================================================================
# Signal-Handler
# ===========================================================================
func _on_design_changed(stats: Dictionary) -> void:
	if stats_label == null:
		return
	var stab := "—"
	if stats.get("col_valid", false):
		var d: float = stats["col"].z - stats["com"].z
		if d > 0.2:
			stab = "stabil ✓"
		elif d < -0.2:
			stab = "kopflastig ⚠"
		else:
			stab = "neutral"
	var gear := "kein Fahrwerk"
	if stats.get("has_gear", false):
		if stats.get("gear_overload", false):
			gear = "%d/%d kg ⚠ KOLLABIERT!" % [int(stats["mass"]), int(stats["gear_cap"])]
		else:
			gear = "%d/%d kg ✓" % [int(stats["mass"]), int(stats["gear_cap"])]
	var wingload := "—"
	if stats.get("has_wings", false):
		wingload = "bis ~%.1f g" % stats["max_g"]
	var drag_line := "Luftwiderstand cW·A: %.2f m²" % stats.get("drag_area", 0.0)
	if build_ctrl != null and build_ctrl.wind_tunnel and not build_ctrl.wind_report.is_empty():
		# Windkanal-Analyse: exponierter Gesamtwiderstand + die größten Verursacher
		# mit Anteil (Verdeckung eingerechnet — Teile im Windschatten zählen ~0).
		var tot: float = maxf(build_ctrl.wind_total, 0.001)
		drag_line += "\n🌬 exponiert (Verdeckung): %.2f m²" % build_ctrl.wind_total
		var rank := 0
		for e in build_ctrl.wind_report:
			if rank >= 3 or float(e["drag"]) < 0.01:
				break
			rank += 1
			drag_line += "\n  %d. %s — %.2f m² (%d %%)" % [
				rank, e["name"], e["drag"], int(round(float(e["drag"]) / tot * 100.0))]
	stats_label.text = "Teile: %d\nMasse: %d kg\nFlügelfläche: %.1f m²\nSchub: %d N\nSchub/Gewicht: %.2f\n%s\nLängsstabilität: %s\nMax. Flügellast: %s\nFahrwerk-Last: %s" % [
		int(stats["parts"]), int(stats["mass"]), stats["area"],
		int(stats["thrust"]), stats["tw"], drag_line,
		stab, wingload, gear]
	_update_ampel(stats)


# "Fliegt's?"-Ampel: aus Stabilität, Schub/Gewicht, Flügeln und Fahrwerk eine grün/gelb/rote
# Einschätzung mit kurzem Tipp ableiten.
func _update_ampel(stats: Dictionary) -> void:
	if ampel_label == null:
		return
	if build_ctrl != null and build_ctrl.has_floating():
		ampel_label.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
		ampel_label.text = "🔴 %d Teil(e) hängen frei (rot markiert) — verbinden zum Starten" % build_ctrl.floating_count()
		return
	var has_wings: bool = stats.get("has_wings", false)
	var tw: float = stats.get("tw", 0.0)                       # VORWÄRTS-Schub / Gewicht
	var up_tw: float = stats.get("up_tw", 0.0)                 # Senkrechtschub / Gewicht (VTOL)
	var offset: float = stats.get("thrust_offset", 0.0)        # Schub-Hebel (m) um den COM
	var inst_tw: float = float(stats.get("thrust", 0.0)) / max(float(stats.get("mass", 0.0)) * 9.81, 0.001)
	var d: float = (stats["col"].z - stats["com"].z) if stats.get("col_valid", false) else 0.0
	var txt: String
	var col: Color
	if not has_wings:
		col = Color(1, 0.45, 0.4); txt = "🔴 Fliegt nicht — keine Tragflächen dran"
	elif stats.get("gear_overload", false):
		col = Color(1, 0.45, 0.4); txt = "🔴 Fahrwerk überlastet — Reifen reißen beim Start ab"
	elif offset > 1.0:
		# außermittiger/schräger Schub (z. B. Düse hinten, die nach oben zeigt) -> kippt/dreht
		col = Color(1, 0.45, 0.4); txt = "🔴 Schub stark außermittig — kippt/dreht beim Gasgeben (Triebwerke symmetrisch & durch den Schwerpunkt richten)"
	elif tw < 0.12 and up_tw < 0.9:
		if inst_tw >= 0.30:   # es GIBT Schub, er zeigt nur nicht nach vorne (gedreht/Reverse)
			col = Color(1, 0.45, 0.4); txt = "🔴 Schub zeigt nicht nach vorne — Triebwerke nach vorne richten (oder Reverse aus)"
		else:
			col = Color(1, 0.45, 0.4); txt = "🔴 Zu wenig Schub zum Abheben"
	elif stats.get("col_valid", false) and d < -0.5:
		col = Color(1, 0.45, 0.4); txt = "🔴 Stark kopflastig — überschlägt sich"
	else:
		var warns: Array = []
		if up_tw >= 0.9 and tw < 0.5:
			warns.append("Senkrechtschub-Stil — braucht Vorwärtsschub für sauberen Vorwärtsflug")
		elif tw < 0.30:
			warns.append("wenig Vorwärtsschub")
		if offset > 0.15:
			warns.append("Schub nicht durch den Schwerpunkt — zieht/kippt beim Gasgeben (Triebwerk auf COM-Höhe = ruhiger)")
		if stats.get("col_valid", false) and d < 0.15:
			warns.append("grenzwertig stabil (Leitwerk/Flügel weiter nach hinten)")
		if not stats.get("has_gear", false):
			warns.append("kein Fahrwerk (Bauchlandung)")
		if has_wings and stats.get("max_g", 9.0) < 3.0:
			warns.append("Flügel kaum belastbar")
		if warns.is_empty():
			col = Color(0.45, 1.0, 0.5); txt = "🟢 Flugbereit!"
		else:
			col = Color(1.0, 0.85, 0.3); txt = "🟡 " + ", ".join(warns)
	ampel_label.add_theme_color_override("font_color", col)
	ampel_label.text = txt


func _on_hud_changed(d: Dictionary) -> void:
	if hud_label == null:
		return
	var assist_txt: String = "AN" if d.get("assist", true) else "AUS (Pro)"
	var inv_txt: String = "INVERTIERT ⚠" if d.get("inverted", false) else "normal"
	var mf: bool = d.get("mouse_fly", false)
	var arc: bool = d.get("arcade", false)
	var mf_txt: String = ("🖱 AN — ARCADE 🎮" if arc else "🖱 AN (Cursor lenkt)") if mf else "AUS (Umschauen)"
	var thr_pct := int(round(d["throttle"] * 100.0))
	var thr_txt: String
	if thr_pct < 0:
		thr_txt = "🛑 Bremse %d%%" % absi(thr_pct)
	elif thr_pct > 100:
		thr_txt = "🔥 NACHBRENNER %d%%" % thr_pct
	else:
		thr_txt = "Schub %d%%" % thr_pct
	var nav := _nearest_airfield(d.get("pos", Vector3.ZERO))
	# Speed/Höhe/Kurs/Steig zeigt jetzt das PFD; hier nur noch Systeme/Status.
	hud_label.text = "%s\nAnstellw.: %d°\nG-Kraft:  %.1f g\nFlügel: %s\nFahrwerk (G): %s\nKlappen (F): %s\nSteuerung (I): %s\nAssist (T): %s\nMaus-Flug (M): %s\n➤ %s" % [
		thr_txt, int(d["aoa"]), d.get("gforce", 1.0),
		d.get("wings", "ok"), d.get("gear", "—"), d.get("flaps", "AUS"), inv_txt, assist_txt, mf_txt, nav]
	var ammo_txt: String = d.get("ammo", "")
	if ammo_txt != "":
		hud_label.text += "\nMunition: " + ammo_txt
	# Primary-Flight-Display füttern (Kompass, Speed/Höhe-Boxen, Zielkreis)
	if flight_hud:
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
		if mf:
			modes.append("ARCADE" if arc else "MAUS-FLUG")
		if not bool(d.get("g_protect", true)):
			modes.append("⚠ G-SCHUTZ AUS")
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
			_toast("🛡 G-Schutz AN — Flügel reißen nicht ab" if gp else "⚠ G-Schutz AUS — volle Physik, Flügel können brechen!")
	if land_label:
		var lm: String = d.get("land_msg", "")
		land_label.text = lm
		if lm.begins_with("💥"):
			land_label.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
		elif lm.begins_with("⚠"):
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
	if snap_cb:
		snap_cb.set_pressed_no_signal(on)
	_toast("Andocken " + ("AN" if on else "AUS — freie Platzierung"))


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
		_toast("💥 Abschuss! +%d 🪙" % reward)
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
		_toast("💥 +%d 🪙   ×%d COMBO!" % [gain, _combo])
	else:
		_toast("💥 Abschuss! +%d 🪙" % gain)
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
func _process(delta: float) -> void:
	# Terrain-Chunks um den Spieler streamen (nur im Flug nötig)
	if mode == Mode.FLY and terrain != null and flight_ctrl != null \
			and is_instance_valid(flight_ctrl.aircraft):
		terrain.update_center(flight_ctrl.aircraft.global_position)
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
	_toast("🌊  WELLE %d  —  %d Ziele" % [n, _alive])
	_update_survival_hud()


func _wave_cleared() -> void:
	var bonus := 150 + _wave * 150        # höherer Wellen-Bonus -> Geldfluss stagniert spät nicht
	game.add_money(bonus)
	_flight_score += bonus
	_toast("✅  WELLE %d GESCHAFFT!   Bonus +%d 🪙" % [_wave, bonus])
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
		return "🥇 Ass!"
	if s >= 1500:
		return "🥈 Veteran"
	if s >= 500:
		return "🥉 Pilot"
	return "Rekrut"


func _show_result_screen() -> void:
	if game == null or game.is_sandbox():
		return
	if survival_label:
		survival_label.visible = false
	var earned := maxi(game.money - _flight_money0, 0)
	var v := _dialog_shell("🏁  Flug-Auswertung")
	v.add_child(_lbl("Erreichte Welle:    %d" % _wave, 17))
	v.add_child(_lbl("Abschüsse:    %d" % _kills, 17))
	v.add_child(_lbl("Beste Combo:    ×%d" % _best_combo, 17))
	v.add_child(_lbl("Flug-Score:    %d" % _flight_score, 17))
	v.add_child(_lbl("Verdient:    +%d 🪙" % earned, 18, Color(1.0, 0.86, 0.3)))
	v.add_child(_lbl("Rang:    %s" % _rank_for(_flight_score), 22, Color(0.7, 1.0, 0.8)))
	var ok := Button.new()
	ok.text = "Weiter"
	ok.pressed.connect(_close_dialog)
	v.add_child(ok)


# ===========================================================================
# WIRTSCHAFT · MODI (Sandbox / Survival)
# ===========================================================================
func _on_game_changed() -> void:
	var mstr := "Sandbox ∞" if (game != null and game.is_sandbox()) else ("🪙 %d" % (game.money if game else 0))
	if money_label:
		money_label.text = "Guthaben: " + mstr
	if fly_money_label:
		fly_money_label.text = "🪙 " + ("∞ (Sandbox)" if (game and game.is_sandbox()) else str(game.money if game else 0))
	_build_upgrades_ui()


func _build_upgrades_ui() -> void:
	if upgrade_box == null:
		return
	for c in upgrade_box.get_children():
		c.queue_free()
	if game == null:
		return
	upgrade_box.add_child(_lbl("⬆  UPGRADES", 13, Color(0.6, 1.0, 0.8)))
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
			b.text = "%s  [Lv %d]  %d 🪙" % [u["name"], lvl, cost]
			b.pressed.connect(_on_buy_upgrade.bind(u["key"], cost))
		upgrade_box.add_child(b)


func _on_buy_upgrade(key: String, cost: int) -> void:
	if game.buy_upgrade(key, cost, 3):
		_toast("Upgrade gekauft: %s  (−%d 🪙)" % [key, cost])
	else:
		_toast("Zu teuer oder Maximum erreicht")


func _rebuild_palette() -> void:
	if part_list_box == null:
		return
	for c in part_list_box.get_children():
		c.queue_free()
	part_buttons.clear()
	_fill_part_list(part_list_box)
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
	sandbox.text = "🧰  SANDBOX\nAlle Teile frei · unbegrenzt bauen & fliegen"
	sandbox.custom_minimum_size = Vector2(460, 70)
	sandbox.add_theme_font_size_override("font_size", 18)
	sandbox.pressed.connect(_choose_mode.bind(GameState.GameMode.SANDBOX))
	v.add_child(sandbox)
	var surv := Button.new()
	surv.text = "🪖  SURVIVAL\nStarte klein · erfülle Missionen · verdiene Geld · kaufe & upgrade"
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
		data.append({"id": it["id"], "xform": _xform_to_array(it["xform"]),
			"color": [c.r, c.g, c.b, c.a], "scale": [s.x, s.y, s.z],
			"taper": it.get("taper", 1.0), "taper_front": it.get("taper_front", 1.0),
			"taper_y": it.get("taper_y", -1.0), "taper_front_y": it.get("taper_front_y", -1.0),
			"fill": it.get("fill", 0.0), "thrust_reverse": it.get("thrust_reverse", false)})
	return data


func _write_design(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		# NICHT still scheitern: Spieler würde sonst unbemerkt sein Design verlieren.
		_toast("⚠ Speichern fehlgeschlagen (%s, Fehler %d)" % [path, FileAccess.get_open_error()])
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
			_toast("⚠ Speicher-Ordner konnte nicht angelegt werden (Fehler %d)" % err)


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
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return v


func _show_save_dialog() -> void:
	if build_ctrl == null:
		return
	var v := _dialog_shell("✈  Flugzeug speichern")
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
	var ok := Button.new(); ok.text = "💾  Speichern"; ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		_toast("Gespeichert: " + nm + " ✓")
	else:
		_toast("Speichern fehlgeschlagen")
	_close_dialog()


func _show_load_dialog() -> void:
	var v := _dialog_shell("✈  Flugzeug laden")
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
		scroll.custom_minimum_size = Vector2(470, minf(slots.size() * 40.0, 220.0))
		v.add_child(scroll)
		var sv := VBoxContainer.new()
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(sv)
		for nm in slots:
			var hb := HBoxContainer.new()
			hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sv.add_child(hb)
			var lb := Button.new()
			lb.text = "📂  " + nm
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lb.pressed.connect(_do_load_slot.bind(nm))
			hb.add_child(lb)
			var db := Button.new()
			db.text = "🗑"
			db.tooltip_text = "Löschen"
			db.pressed.connect(_do_delete_slot.bind(nm))
			hb.add_child(db)
	var close := Button.new(); close.text = "Schließen"
	close.pressed.connect(_close_dialog)
	v.add_child(close)


func _do_load_preset(id: String, title: String) -> void:
	if _load_design_from("res://designs/%s.json" % id):
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
			arr.append({"id": it["id"], "xform": _array_to_xform(it["xform"]), "color": col, "scale": scl, "taper": tp, "taper_front": tpf, "taper_y": tpy, "taper_front_y": tpfy, "fill": float(it.get("fill", 0.0)), "thrust_reverse": bool(it.get("thrust_reverse", false))})
	if arr.is_empty():
		return false
	build_ctrl.load_design(arr)
	return true


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
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	return l


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
