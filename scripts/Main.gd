## Main.gd
## Zentrale: Welt/Licht/Himmel, Modus-Umschaltung (Hangar <-> Flug),
## komplettes UI + HUD, Speichern/Laden und das Start-Flugzeug.
extends Node3D

enum Mode { BUILD, FLY }

const SAVE_PATH := "user://aircraft_design.json"

# Blueprint-Gitter-Shader (anti-aliased, zum Horizont ausgeblendet)
const _BLUEPRINT_GRID_SHADER := "
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 line_color : source_color = vec3(0.40, 0.74, 1.0);
uniform vec3 major_color : source_color = vec3(0.78, 0.92, 1.0);
uniform vec3 bg_color : source_color = vec3(0.04, 0.13, 0.30);
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
var ground_mesh: MeshInstance3D
var blueprint_grid: MeshInstance3D
var airfields: Array = []
var world_env: WorldEnvironment
var env_sky: Environment
var env_blueprint: Environment

# UI
var ui: CanvasLayer
var build_root: Control
var flight_root: Control
var stats_label: Label
var hud_label: Label
var stall_label: Label
var land_label: Label
var center_cross: Label             # statisches Fadenkreuz (im Maus-Flug aus)
var aim_marker: Label               # Maus-Flug: Steuermarker (Cursor)
var nose_marker: Label              # Maus-Flug: aktuelle Nasenrichtung
var tool_label: Label
var toast_label: Label
var drag_view_btn: Button
var part_buttons: Dictionary = {}
var _part_group: ButtonGroup       # exklusive Auswahl der Teil-Kacheln
var _cat_open: Dictionary = {}     # Kategorie -> auf-/zugeklappt

# Wirtschaft / Modi
var game: GameState
var money_label: Label             # Hangar
var fly_money_label: Label         # Flug-HUD
var part_list_box: VBoxContainer   # Palette (zum Neuaufbau nach Kauf)
var upgrade_box: VBoxContainer     # Upgrade-Panel
var mode_overlay: Control          # Modus-Auswahl-Overlay
var sel_panel: Control             # Kontext-Panel für ausgewähltes Teil
var sel_title: Label
var sel_scale_label: Label
var sel_delete_btn: Button
var sel_mode_btns: Array = []      # [Bewegen, Drehen, Skalieren] zum Hervorheben des aktiven Modus

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
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.22, 0.42, 0.72)
	psm.sky_horizon_color = Color(0.72, 0.82, 0.92)
	psm.ground_horizon_color = Color(0.62, 0.66, 0.62)
	psm.ground_bottom_color = Color(0.32, 0.38, 0.32)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.82, 0.92)
	env.fog_density = 0.00012   # dünn, damit ferne Flugplätze sichtbar bleiben
	env_sky = env

	# Blueprint-Umgebung für den Bau-Modus (tiefblauer Raum)
	env_blueprint = Environment.new()
	env_blueprint.background_mode = Environment.BG_COLOR
	env_blueprint.background_color = Color(0.04, 0.13, 0.30)
	env_blueprint.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_blueprint.ambient_light_color = Color(0.62, 0.76, 0.96)
	env_blueprint.ambient_light_energy = 1.5
	env_blueprint.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	world_env = WorldEnvironment.new()
	world_env.environment = env_sky
	add_child(world_env)

	# Sonne
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -47, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	add_child(sun)

	# Fülllicht von UNTEN (kein Schatten) -> Flugzeug-Unterseite ist nicht mehr stockdunkel,
	# man sieht es auch von unten. Etwas seitlich für plastischere Optik.
	var underfill := DirectionalLight3D.new()
	underfill.rotation_degrees = Vector3(62, 130, 0)
	underfill.light_energy = 0.55
	underfill.shadow_enabled = false
	add_child(underfill)

	# Boden-Kollision (unendliche Ebene)
	var ground_body := StaticBody3D.new()
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	var gcs := CollisionShape3D.new()
	gcs.shape = WorldBoundaryShape3D.new()
	ground_body.add_child(gcs)
	add_child(ground_body)

	# Flug-Welt: Boden, Landschaft, Flugplätze (nur im Flug sichtbar)
	fly_world = Node3D.new()
	add_child(fly_world)

	ground_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12000, 12000)
	ground_mesh.mesh = pm
	ground_mesh.material_override = _flat_mat(Color(0.34, 0.5, 0.3), 1.0)
	fly_world.add_child(ground_mesh)

	# Flugplätze (Name, Position, Ausrichtung, Farbe)
	airfields = [
		{"name": "HEIMAT", "pos": Vector3(0, 0, -100), "heading": 0.0, "color": Color(0.9, 0.9, 0.95)},
		{"name": "NORDFELD", "pos": Vector3(-1500, 0, -2000), "heading": 0.7, "color": Color(0.95, 0.75, 0.3)},
		{"name": "OSTHAFEN", "pos": Vector3(2200, 0, -250), "heading": -1.15, "color": Color(0.45, 0.75, 0.98)},
		{"name": "BERGPISTE", "pos": Vector3(900, 0, 2000), "heading": 2.3, "color": Color(0.95, 0.5, 0.45)},
	]

	# Landschaft (nur Optik): See + Berge als Orientierung
	_build_lake(Vector3(-1000, 0, 700), 650.0)
	for hp in [Vector3(1300, 0, 1500), Vector3(-2000, 0, -600), Vector3(700, 0, -2100), Vector3(-300, 0, 2600), Vector3(2600, 0, 1400)]:
		_build_mountain(hp)
	for af in airfields:
		_build_airfield(af)

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


func _build_airfield(af: Dictionary) -> void:
	var node := Node3D.new()
	node.position = af["pos"]
	node.rotation.y = af["heading"]
	fly_world.add_child(node)
	# Bahn
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(20, 0.14, 300)
	strip.mesh = sm
	strip.position = Vector3(0, 0.07, 0)
	strip.material_override = _flat_mat(Color(0.17, 0.17, 0.19), 0.95)
	node.add_child(strip)
	# gestrichelte Mittellinie
	for i in range(-6, 7):
		var d := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(0.6, 0.04, 10)
		d.mesh = dm
		d.position = Vector3(0, 0.15, i * 22.0)
		d.material_override = _emit_mat(Color(0.9, 0.9, 0.85), 0.25)
		node.add_child(d)
	# Schwellen-Markierungen an den Enden
	for zz in [-142.0, 142.0]:
		for x in [-7.0, -3.5, 0.0, 3.5, 7.0]:
			var th := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(2.0, 0.04, 12)
			th.mesh = tm
			th.position = Vector3(x, 0.15, zz)
			th.material_override = _emit_mat(Color(0.95, 0.95, 0.9), 0.2)
			node.add_child(th)
	# Hangars + Tower
	_add_hangar(node, Vector3(-24, 0, -70), af["color"])
	_add_hangar(node, Vector3(26, 0, -55), af["color"])
	_add_tower(node, Vector3(-28, 0, 50))
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


func _build_mountain(pos: Vector3) -> void:
	var c := CylinderMesh.new()
	c.bottom_radius = randf_range(240, 380)
	c.top_radius = 8.0
	c.height = randf_range(320, 560)
	c.radial_segments = 6
	var m := MeshInstance3D.new()
	m.mesh = c
	m.position = pos + Vector3(0, c.height * 0.5, 0)
	m.material_override = _flat_mat(Color(0.33, 0.3, 0.27), 1.0)
	fly_world.add_child(m)
	var sc := CylinderMesh.new()
	sc.bottom_radius = 75.0
	sc.top_radius = 8.0
	sc.height = c.height * 0.26
	sc.radial_segments = 6
	var snow := MeshInstance3D.new()
	snow.mesh = sc
	snow.position = pos + Vector3(0, c.height - sc.height * 0.5, 0)
	snow.material_override = _flat_mat(Color(0.92, 0.94, 0.98), 0.85)
	fly_world.add_child(snow)


func _build_lake(pos: Vector3, r: float) -> void:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.5
	c.radial_segments = 40
	var lake := MeshInstance3D.new()
	lake.mesh = c
	lake.position = pos + Vector3(0, 0.2, 0)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.2, 0.45, 0.7)
	lm.metallic = 0.7
	lm.roughness = 0.08
	lake.material_override = lm
	fly_world.add_child(lake)


func _setup_camera() -> void:
	camera = Camera3D.new()
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

	flight_ctrl = FlightController.new()
	add_child(flight_ctrl)
	flight_ctrl.set_camera(camera)
	flight_ctrl.hud_changed.connect(_on_hud_changed)


# ===========================================================================
# MODUS
# ===========================================================================
func _set_mode(m: int) -> void:
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

	if building:
		flight_ctrl.set_active(false)
		flight_ctrl.clear_aircraft()
	else:
		if game != null:
			flight_ctrl.thrust_mult = game.thrust_mult()
			flight_ctrl.wing_mult = game.wing_mult()
			flight_ctrl.mass_mult = game.mass_mult()
		flight_ctrl.build_from_design(build_ctrl.get_design())
		flight_ctrl.set_active(true)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_set_mode(Mode.FLY if mode == Mode.BUILD else Mode.BUILD)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			# Esc: Vollbild verlassen (Fenster), sonst Spiel beenden
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				get_tree().quit()
			get_viewport().set_input_as_handled()


func _toggle_fullscreen() -> void:
	var win := DisplayServer.WINDOW_MODE_WINDOWED if \
		DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN \
		else DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(win)
	_toast("Vollbild: " + ("AN  (F11 / Esc zum Verlassen)" if win == DisplayServer.WINDOW_MODE_FULLSCREEN else "aus"))


# ===========================================================================
# UI
# ===========================================================================
func _setup_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)

	build_root = Control.new()
	build_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	build_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(build_root)

	flight_root = Control.new()
	flight_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	flight_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	var title := _lbl("🛠  HANGAR", 22, Color(1, 1, 1))
	vb.add_child(title)
	money_label = _lbl("", 15, Color(1.0, 0.86, 0.3))
	vb.add_child(money_label)
	tool_label = _lbl("Werkzeug: —", 13, Color(0.7, 1.0, 0.7))
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

	var sym := CheckBox.new()
	sym.text = "Symmetrie (beide Seiten)"
	sym.button_pressed = true
	sym.toggled.connect(_on_symmetry_toggled)
	vb.add_child(sym)

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

	# --- Testflug-Button oben mitte ---
	var fly_btn := Button.new()
	fly_btn.text = "▶  TESTFLUG STARTEN  (Tab)"
	fly_btn.add_theme_font_size_override("font_size", 18)
	_rect(fly_btn, 0.5, 0, 0.5, 0, -150, 10, 150, 52)
	fly_btn.pressed.connect(_on_fly_pressed)
	build_root.add_child(fly_btn)

	# --- Statistik oben rechts ---
	var spanel := _panel(Color(0, 0, 0, 0.5))
	_rect(spanel, 1, 0, 1, 0, -300, 10, -10, 258)
	build_root.add_child(spanel)
	var sv := VBoxContainer.new()
	spanel.add_child(sv)
	sv.add_child(_lbl("📊  STATISTIK", 16, Color(1, 0.9, 0.5)))
	stats_label = _lbl("", 14)
	sv.add_child(stats_label)
	var legend := _lbl("● Schwerpunkt   ● Auftriebspunkt", 11, Color(0.85, 0.85, 0.85))
	sv.add_child(legend)

	_build_selection_panel()

	# --- Hinweisleiste unten ---
	var hint := _lbl("Teil ziehen = setzen/verschieben  ·  leerer Raum/Rechtsmaus = drehen  ·  Zoom: Mausrad / + − / Pinch / Zwei-Finger  ·  X: löschen  ·  R: drehen  ·  M: Symmetrie  ·  Strg+Z/Y: Undo  ·  F: Ansicht", 13, Color(0.9, 0.9, 0.9))
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
		hb.bg_color = Color(1.0, 0.78, 0.35, 0.16)
		hb.set_corner_radius_all(4)
		hb.content_margin_left = 6
		hb.content_margin_top = 3
		hb.content_margin_bottom = 3
		header.add_theme_stylebox_override("normal", hb)
		header.add_theme_stylebox_override("hover", hb)
		header.add_theme_stylebox_override("pressed", hb)
		header.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
		list.add_child(header)
		# --- Grid mit Vorschau-Kacheln ---
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 5)
		grid.add_theme_constant_override("v_separation", 5)
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
func _make_part_tile(p: Dictionary) -> Button:
	var id: String = p["id"]
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(0, 94)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.tooltip_text = "%s — in den Bauraum ziehen zum Setzen" % p.get("desc", p["name"])
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
		tile.tooltip_text = "%s — kosten %d 🪙 (klicken zum Kaufen)" % [p.get("desc", p["name"]), PartCatalog.part_cost(p)]
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
	normal.bg_color = Color(0.12, 0.15, 0.21, 0.85)
	normal.set_corner_radius_all(5)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.3, 0.36, 0.46)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.18, 0.22, 0.30, 0.95)
	hover.border_color = Color(0.5, 0.6, 0.75)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.16, 0.30, 0.20, 0.95)
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
	var modes := [["↔ Bewegen", 0], ["↻ Drehen", 1], ["⤢ Skalieren", 2]]
	for md in modes:
		var mb := Button.new()
		mb.text = md[0]
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.add_theme_font_size_override("font_size", 11)
		mb.pressed.connect(build_ctrl.set_gizmo_mode.bind(md[1]))
		mrow.add_child(mb)
		sel_mode_btns.append(mb)
	v.add_child(_lbl("Pfeile/Würfel im 3D-Raum ziehen · Drehen: Teil ziehen · 90°-Schritte unten:", 10, Color(0.7, 0.74, 0.82)))
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
	var s: Vector3 = info.get("scale", Vector3.ONE)
	sel_scale_label.text = "Größe: %.2f × %.2f × %.2f" % [s.x, s.y, s.z]
	var is_root: bool = info.get("is_root", false)
	sel_delete_btn.disabled = is_root
	sel_delete_btn.tooltip_text = "Das Cockpit ist die Basis und kann nicht gelöscht werden." if is_root else ""
	# aktiven Werkzeug-Modus hervorheben
	var gm: int = info.get("gizmo", 0)
	for i in sel_mode_btns.size():
		sel_mode_btns[i].modulate = Color(0.5, 1.0, 0.6) if i == gm else Color(1, 1, 1)


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
		tool_label.text = "Teil aus der Liste in den Bauraum ZIEHEN zum Setzen · vorhandenes Teil packen & ziehen = verschieben · leerer Raum = drehen"
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

	# Stall-Warnung mitte oben
	stall_label = _lbl("⚠  STRÖMUNGSABRISS  ⚠", 26, Color(1, 0.3, 0.25))
	stall_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(stall_label, 0.5, 0, 0.5, 0, -260, 70, 260, 110)
	stall_label.visible = false
	flight_root.add_child(stall_label)

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

	# Fadenkreuz (Mitte) — im Maus-Flug ausgeblendet (dann zeigt der Nasenmarker)
	center_cross = _lbl("✛", 26, Color(1, 1, 1, 0.7))
	center_cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rect(center_cross, 0.5, 0.5, 0.5, 0.5, -16, -18, 16, 18)
	flight_root.add_child(center_cross)

	# Maus-Flug-Marker (frei positioniert; werden in _on_hud_changed gesetzt)
	aim_marker = _make_marker("⊕", 34, Color(0.3, 1.0, 0.45, 0.95))
	flight_root.add_child(aim_marker)
	nose_marker = _make_marker("◇", 26, Color(1.0, 0.88, 0.3, 0.95))
	flight_root.add_child(nose_marker)

	# Hinweisleiste unten
	var hint := _lbl("Maus: Umschauen · M: Maus-Flug · J: Arcade · Schub: Shift/Strg · Nase: W/S · Rollen: A/D (halten = 🔄 Barrel Roll) · Gieren: Q/E · 🔫 LEERTASTE · 💣 B · G: Fahrwerk · T: Assist · Enter: neu", 14, Color(0.92, 0.92, 0.92))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(hint, 0, 1, 1, 1, 10, -34, -10, -8)
	flight_root.add_child(hint)


# Frei positionierbarer HUD-Marker (fixe Box, mittig ausgerichtet -> Position = Mittelpunkt).
func _make_marker(glyph: String, size: int, color: Color) -> Label:
	var m := _lbl(glyph, size, color)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	m.size = Vector2(48, 48)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.visible = false
	return m


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
	if build_ctrl != null and build_ctrl.wind_tunnel and build_ctrl.wind_worst != "":
		drag_line += "\n  ↳ Hotspot: %s" % build_ctrl.wind_worst
	stats_label.text = "Teile: %d\nMasse: %d kg\nFlügelfläche: %.1f m²\nSchub: %d N\nSchub/Gewicht: %.2f\n%s\nLängsstabilität: %s\nMax. Flügellast: %s\nFahrwerk-Last: %s" % [
		int(stats["parts"]), int(stats["mass"]), stats["area"],
		int(stats["thrust"]), stats["tw"], drag_line,
		stab, wingload, gear]


func _on_hud_changed(d: Dictionary) -> void:
	if hud_label == null:
		return
	var assist_txt: String = "AN" if d.get("assist", true) else "AUS (Pro)"
	var inv_txt: String = "INVERTIERT ⚠" if d.get("inverted", false) else "normal"
	var mf: bool = d.get("mouse_fly", false)
	var arc: bool = d.get("arcade", false)
	var mf_txt: String = ("🖱 AN — ARCADE 🎮" if arc else "🖱 AN (Cursor lenkt)") if mf else "AUS (Umschauen)"
	var thr_pct := int(round(d["throttle"] * 100.0))
	var thr_txt := ("🛑 Bremse %d%%" % absi(thr_pct)) if thr_pct < 0 else ("Schub %d%%" % thr_pct)
	var nav := _nearest_airfield(d.get("pos", Vector3.ZERO))
	hud_label.text = "%s\nSpeed:  %d km/h  (%d m/s)\nHöhe:   %d m\nSteig:  %+.1f m/s\nAnstellw.: %d°\nG-Kraft:  %.1f g\nFlügel: %s\nFahrwerk (G): %s\nSteuerung (I): %s\nAssist (T): %s\nMaus-Flug (M): %s\n➤ %s" % [
		thr_txt, int(d["kmh"]), int(d["speed"]),
		int(d["alt"]), d["climb"], int(d["aoa"]), d.get("gforce", 1.0),
		d.get("wings", "ok"), d.get("gear", "—"), inv_txt, assist_txt, mf_txt, nav]
	# Maus-Flug-Marker: Zielmarker (Maus/Weltrichtung) + Nasenrichtung; statisches Kreuz aus
	if center_cross:
		center_cross.visible = not mf
	if aim_marker:
		aim_marker.visible = mf and bool(d.get("aim_vis", true))
		if aim_marker.visible:
			aim_marker.position = (d.get("aim", Vector2.ZERO) as Vector2) - aim_marker.size * 0.5
	if nose_marker:
		nose_marker.visible = mf and bool(d.get("nose_vis", true))
		if nose_marker.visible:
			nose_marker.position = (d.get("nose", Vector2.ZERO) as Vector2) - nose_marker.size * 0.5
	stall_label.visible = d.get("stall", false) and d.get("speed", 0.0) > 4.0
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


func _make_target(kind: String, pos: Vector3, col: Color) -> void:
	var t := Target.new()
	targets_root.add_child(t)
	t.setup(kind, pos, col)
	t.killed.connect(_on_target_killed)


func _on_target_killed(reward: int, _pos: Vector3) -> void:
	if game != null:
		game.add_money(reward)
	_toast("💥 Abschuss! +%d 🪙" % reward)
	# Nachschub: nach kurzer Zeit einen neuen Ballon einfliegen lassen
	var tmr := get_tree().create_timer(7.0)
	tmr.timeout.connect(_respawn_balloon)


func _respawn_balloon() -> void:
	if targets_root == null:
		return
	_make_target("balloon", _rand_target_pos(40.0, 210.0), _TARGET_COLORS[randi() % _TARGET_COLORS.size()])


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
			var cost := 600 * (lvl + 1)
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
	_save_design()
	_toast("Design gespeichert ✓")


func _on_load_pressed() -> void:
	if _load_design():
		_toast("Design geladen ✓")
	else:
		_toast("Kein Speicherstand vorhanden")


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
	var data: Array = []
	for it in build_ctrl.get_design():
		var c: Color = it.get("color", Color(0, 0, 0, 0))
		var s: Vector3 = it.get("scale", Vector3.ONE)
		data.append({"id": it["id"], "xform": _xform_to_array(it["xform"]),
			"color": [c.r, c.g, c.b, c.a], "scale": [s.x, s.y, s.z]})
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func _load_design() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_ARRAY or data.is_empty():
		return false
	var arr: Array = []
	for it in data:
		if typeof(it) == TYPE_DICTIONARY and it.has("id") and it.has("xform"):
			var col := Color(0, 0, 0, 0)
			if it.has("color") and typeof(it["color"]) == TYPE_ARRAY and it["color"].size() >= 4:
				var ca: Array = it["color"]
				col = Color(ca[0], ca[1], ca[2], ca[3])
			var scl := Vector3.ONE
			if it.has("scale") and typeof(it["scale"]) == TYPE_ARRAY and it["scale"].size() >= 3:
				var sa: Array = it["scale"]
				scl = Vector3(sa[0], sa[1], sa[2])
			arr.append({"id": it["id"], "xform": _array_to_xform(it["xform"]), "color": col, "scale": scl})
	if arr.is_empty():
		return false
	build_ctrl.load_design(arr)
	return true


func _xform_to_array(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z,
		t.origin.x, t.origin.y, t.origin.z]


func _array_to_xform(a: Array) -> Transform3D:
	return Transform3D(
		Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])),
		Vector3(a[9], a[10], a[11]))


# ===========================================================================
# Start-Flugzeug
# ===========================================================================
func _default_design() -> Array:
	var d: Array = []
	d.append({"id": "cockpit", "xform": Transform3D(Basis(), Vector3(0, 0, 0))})
	d.append({"id": "nose", "xform": Transform3D(Basis(), Vector3(0, 0, -2.0))})
	d.append({"id": "fuselage", "xform": Transform3D(Basis(), Vector3(0, 0, 2.1))})
	d.append({"id": "tailcone", "xform": Transform3D(Basis(), Vector3(0, 0, 4.0))})
	d.append({"id": "prop_engine", "xform": Transform3D(Basis(), Vector3(0, 0, -3.65))})

	var wb := build_ctrl._orient_to_normal(Vector3.RIGHT)
	var wt := Transform3D(wb, Vector3(0.65, -0.05, 0.5))
	d.append({"id": "wing_tapered", "xform": wt})
	d.append({"id": "wing_tapered", "xform": build_ctrl._mirror_xform(wt)})

	var ht := Transform3D(wb, Vector3(0.6, 0.1, 4.1))
	d.append({"id": "h_stab", "xform": ht})
	d.append({"id": "h_stab", "xform": build_ctrl._mirror_xform(ht)})

	var vb := build_ctrl._orient_to_normal(Vector3.UP)
	d.append({"id": "v_stab", "xform": Transform3D(vb, Vector3(0, 0.55, 4.2))})

	d.append({"id": "wheel", "xform": Transform3D(Basis(), Vector3(1.5, -1.05, 0.8))})
	d.append({"id": "wheel", "xform": Transform3D(Basis(), Vector3(-1.5, -1.05, 0.8))})
	d.append({"id": "wheel", "xform": Transform3D(Basis(), Vector3(0, -1.05, -1.8))})
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
	sb.bg_color = bg
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
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
