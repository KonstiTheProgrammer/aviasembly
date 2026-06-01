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

var runway: Node3D
var ground_mesh: MeshInstance3D
var blueprint_grid: MeshInstance3D
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
var tool_label: Label
var toast_label: Label
var drag_view_btn: Button
var part_buttons: Dictionary = {}


func _ready() -> void:
	_setup_world()
	_setup_camera()
	_setup_controllers()
	_setup_ui()
	if not _load_design():
		build_ctrl.load_design(_default_design())
	_set_mode(Mode.BUILD)
	_refresh_tool_ui()


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
	env.fog_density = 0.0006
	env_sky = env

	# Blueprint-Umgebung für den Bau-Modus (tiefblauer Raum)
	env_blueprint = Environment.new()
	env_blueprint.background_mode = Environment.BG_COLOR
	env_blueprint.background_color = Color(0.04, 0.13, 0.30)
	env_blueprint.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env_blueprint.ambient_light_color = Color(0.62, 0.76, 0.96)
	env_blueprint.ambient_light_energy = 1.1
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

	# Boden (unendliche Ebene als Kollision + große Sichtfläche)
	var ground_body := StaticBody3D.new()
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	var gcs := CollisionShape3D.new()
	gcs.shape = WorldBoundaryShape3D.new()
	ground_body.add_child(gcs)
	add_child(ground_body)

	ground_mesh = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	ground_mesh.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.34, 0.5, 0.3)
	gmat.roughness = 1.0
	ground_mesh.material_override = gmat
	add_child(ground_mesh)

	# Startbahn
	runway = Node3D.new()
	add_child(runway)
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(18, 0.12, 340)
	strip.mesh = sm
	strip.position = Vector3(0, 0.06, -100)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.17, 0.17, 0.19)
	smat.roughness = 0.95
	strip.material_override = smat
	runway.add_child(strip)
	var line := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.5, 0.04, 300)
	line.mesh = lm
	line.position = Vector3(0, 0.13, -100)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.9, 0.9, 0.85)
	lmat.emission_enabled = true
	lmat.emission = Color(0.8, 0.8, 0.7)
	lmat.emission_energy_multiplier = 0.2
	line.material_override = lmat
	runway.add_child(line)

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


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 64.0
	camera.far = 6000.0
	camera.current = true
	add_child(camera)


func _setup_controllers() -> void:
	build_ctrl = BuildController.new()
	add_child(build_ctrl)
	build_ctrl.set_camera(camera)
	build_ctrl.design_changed.connect(_on_design_changed)

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

	# Blueprint-Raum im Bau-Modus, Himmel/Boden/Bahn im Flug
	world_env.environment = env_blueprint if building else env_sky
	blueprint_grid.visible = building
	ground_mesh.visible = not building
	runway.visible = not building

	if building:
		flight_ctrl.set_active(false)
		flight_ctrl.clear_aircraft()
	else:
		flight_ctrl.build_from_design(build_ctrl.get_design())
		flight_ctrl.set_active(true)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_set_mode(Mode.FLY if mode == Mode.BUILD else Mode.BUILD)
		get_viewport().set_input_as_handled()


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
	_rect(panel, 0, 0, 0, 1, 10, 10, 308, -10)
	build_root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var title := _lbl("🛠  HANGAR", 22, Color(1, 1, 1))
	vb.add_child(title)
	tool_label = _lbl("Werkzeug: —", 13, Color(0.7, 1.0, 0.7))
	vb.add_child(tool_label)
	vb.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	_fill_part_list(list)

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
	for cat in PartCatalog.categories():
		var header := _lbl(cat.to_upper(), 14, Color(1.0, 0.78, 0.35))
		header.add_theme_constant_override("line_spacing", 2)
		list.add_child(header)
		for p in PartCatalog.parts_in(cat):
			var b := Button.new()
			b.text = "  %s   (%d kg)" % [p["name"], int(p["mass"])]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.tooltip_text = p.get("desc", p["name"])
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(_on_pick_part.bind(p["id"]))
			list.add_child(b)
			part_buttons[p["id"]] = b


func _on_pick_part(id: String) -> void:
	build_ctrl.set_brush(id)
	_refresh_tool_ui()


func _on_move_tool() -> void:
	build_ctrl.set_erase_mode(false)
	build_ctrl.set_paint_mode(false)
	build_ctrl.set_brush("")
	_refresh_tool_ui()


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
	_toast("Windkanal: " + ("AN — Luftströmung über das Modell" if on else "aus"))


func _refresh_tool_ui() -> void:
	for pid in part_buttons:
		part_buttons[pid].modulate = Color(1, 1, 1)
	if build_ctrl.erase_mode:
		tool_label.text = "Werkzeug: 🧹 Abriss – Teil anklicken zum Löschen"
	elif build_ctrl.paint_mode:
		tool_label.text = "Werkzeug: 🎨 Lackieren – Teil anklicken zum Umfärben"
	elif build_ctrl.brush_id == "":
		tool_label.text = "Werkzeug: ✋ Bewegen – Teil ziehen verschiebt, leerer Raum dreht"
	else:
		var p := PartCatalog.get_part(build_ctrl.brush_id)
		tool_label.text = "Werkzeug: %s – ziehen & loslassen zum Setzen" % p.get("name", build_ctrl.brush_id)
		if part_buttons.has(build_ctrl.brush_id):
			part_buttons[build_ctrl.brush_id].modulate = Color(0.6, 1.0, 0.7)


func _build_flight_ui() -> void:
	# HUD oben links
	var hp := _panel(Color(0, 0, 0, 0.45))
	_rect(hp, 0, 0, 0, 0, 12, 12, 320, 290)
	flight_root.add_child(hp)
	var hv := VBoxContainer.new()
	hp.add_child(hv)
	hv.add_child(_lbl("✈  FLUG-HUD", 16, Color(0.6, 0.85, 1.0)))
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

	# Hinweisleiste unten
	var hint := _lbl("Schub: Shift/Strg · Nase: W/S · Rollen: A/D · Gieren: Z/C · G: Fahrwerk · Q: Steuerung umkehren · T: Assist · Enter: neu", 14, Color(0.92, 0.92, 0.92))
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
	stats_label.text = "Teile: %d\nMasse: %d kg\nFlügelfläche: %.1f m²\nSchub: %d N\nSchub/Gewicht: %.2f\nLuftwiderstand cW·A: %.2f m²\nLängsstabilität: %s\nMax. Flügellast: %s\nFahrwerk-Last: %s" % [
		int(stats["parts"]), int(stats["mass"]), stats["area"],
		int(stats["thrust"]), stats["tw"], stats.get("drag_area", 0.0),
		stab, wingload, gear]


func _on_hud_changed(d: Dictionary) -> void:
	if hud_label == null:
		return
	var assist_txt: String = "AN" if d.get("assist", true) else "AUS (Pro)"
	var inv_txt: String = "INVERTIERT ⚠" if d.get("inverted", false) else "normal"
	var thr_pct := int(round(d["throttle"] * 100.0))
	var thr_txt := ("🛑 Bremse %d%%" % absi(thr_pct)) if thr_pct < 0 else ("Schub %d%%" % thr_pct)
	hud_label.text = "%s\nSpeed:  %d km/h  (%d m/s)\nHöhe:   %d m\nSteig:  %+.1f m/s\nAnstellw.: %d°\nG-Kraft:  %.1f g\nFlügel: %s\nFahrwerk (G): %s\nSteuerung (Q): %s\nAssist (T): %s" % [
		thr_txt, int(d["kmh"]), int(d["speed"]),
		int(d["alt"]), d["climb"], int(d["aoa"]), d.get("gforce", 1.0),
		d.get("wings", "ok"), d.get("gear", "—"), inv_txt, assist_txt]
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


# --- Button-/UI-Aktionen ---------------------------------------------------
func _on_fly_pressed() -> void:
	_set_mode(Mode.FLY)


func _on_hangar_pressed() -> void:
	_set_mode(Mode.BUILD)


func _on_symmetry_toggled(on: bool) -> void:
	build_ctrl.set_symmetry(on)


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
		data.append({"id": it["id"], "xform": _xform_to_array(it["xform"]), "color": [c.r, c.g, c.b, c.a]})
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
			arr.append({"id": it["id"], "xform": _array_to_xform(it["xform"]), "color": col})
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
