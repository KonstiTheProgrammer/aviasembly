## BuildController.gd
## Der Hangar-Editor: Orbit-Kamera, flächenbündiges Anrasten von Teilen,
## Ghost-Vorschau, Symmetrie-Modus, Löschen, Live-Statistik.
class_name BuildController
extends Node3D

signal design_changed(stats: Dictionary)
signal selection_changed(info: Dictionary)   # {} = nichts gewählt; sonst {name, scale, is_root}
signal snap_changed(on: bool)                 # Auto-Andocken an/aus (Checkbox + Taste N synchron)
signal kopiert(part_name: String)             # Strg+C: fuer die Rueckmeldung im Hangar

const BUILD_LAYER := 2
const HANDLE_LAYER := 8       # Transform-Griffe (eigener Raycast-Layer)

var camera: Camera3D

var design_root: Node3D
var ghost: Node3D
var _ghost_built_id := ""        # mit welcher Teil-ID das Hologramm aktuell gebaut ist (für Modell-Swap)
var _ghost_mats: Array = []      # Material-Overrides des Hologramms (zum Umfärben gültig/ungültig)
var _ghost_valid := true         # aktuelle Hologramm-Einfärbung (grün=platzierbar / rot=nicht)
var brush_id := ""           # aktuell gewähltes Teil aus der Palette ("" = kein Teil)
var erase_mode := false      # Abriss-Werkzeug
var symmetry := true
const WING_FILL_MAX := 0.8       # max. Innen-Verlängerung je Flügelhälfte (Mittelspalt-Füllung)
var snap_enabled := true        # Auto-Andocken (magnetisches Flächen-Snapping) an/aus
var ghost_rot := 0           # R-Drehung (nur für achsen-ausgerichtete Teile)

# Orbit-Kamera (Blueprint: frei ums Flugzeug drehen)
var orbit_yaw := 0.7
var orbit_pitch := 0.4
var orbit_dist := 15.0
var orbit_focus := Vector3(0, 0.0, 0)
var _ortho_view := 0         # 0=frei (Perspektive), 1=Front, 2=Seite, 3=Oben (orthografisch)
var _orbiting := false       # rechte Maus
var _panning := false        # mittlere Maus
var _left_orbit := false     # linke Maus auf leeren Raum -> drehen

# Drag & Snap
var _carrying := false       # gerade wird ein Teil mit der Maus gezogen
var carry_id := ""
var _carry_existing := false # vorhandenes Teil aufgenommen (vs. neues aus Palette)
var _carry_orig := Transform3D()
var _carry_scale := Vector3.ONE
var _carry_color := Color(0, 0, 0, 0)
var _carry_from_tile := false  # Drag wurde aus der Teile-Liste (Inventar) gestartet
var _lmb_was_down := false     # linke Maustaste letzten Frame gedrückt? (Release-Erkennung)

# Lackieren & Undo/Redo
var paint_mode := false
var paint_color := Color(0.86, 0.22, 0.20)
var wind_tunnel := false     # Windkanal-Ansicht (Pro-Teil-Heatmap + Luftströmung)
var wind_worst := ""         # Teil mit dem höchsten Flug-Widerstand
var wind_report: Array = []  # Windkanal: [{name, drag}] pro Teilname (Spiegel summiert), absteigend
var wind_total := 0.0        # Windkanal: Summe exponierte Fläche × Formbeiwert (m² CdA)
var _tunnel_particles: CPUParticles3D
var _wind_shader: Shader      # markiert nur die angeströmten Flächen (Normale gegen +Z)
var _history: Array = []
var _hist_i := -1
var _suppress_history := false

# letzte Vorschau
var _last_valid := false
var _last_xform := Transform3D()

var com_marker: MeshInstance3D
var col_marker: MeshInstance3D
var _float_markers: Array = []   # rote Marker über frei schwebenden (nicht verbundenen) Teilen
var debug_boxes := false         # Debug-Ansicht: Drahtboxen um jedes Teil
var _dbg_root: Node3D = null

# Bearbeiten ist IMMER aktiv, wenn kein Palette-Teil/Abriss/Lackieren gewählt ist
# (auswählen + Griffe ziehen: Länge/Breite/Höhe + Body ziehen = verschieben).
var selected_part: Node3D
var _handles: Array = []          # 6 Flächen-Griffe (StaticBody3D)
var _drag_handle: Node3D          # gerade gezogener Griff (null = keiner)
var _drag_axis_i := 0             # 0=X(Breite) 1=Y(Höhe) 2=Z(Länge)
var _drag_sign := 1.0
var _drag_axis_w := Vector3.ZERO  # Welt-Achsenrichtung des Griffs
var _drag_t0 := 0.0               # Startparameter auf der Achse
var _drag_scale0 := Vector3.ONE
var _drag_origin0 := Vector3.ZERO
var _drag_taper0 := 1.0           # Enden-Drag: Taper-Wert des Endes beim Greifen
var _drag_corner := 0            # gezogene Klotz-Ecke (0..7)
var _drag_shift0 := Vector2.ZERO  # Enden-Versatz beim Greifen
var _drag_ebene0 := Vector3.ZERO  # Startpunkt in der Querschnittsebene
const SHIFT_MAX := 0.9            # feste Spanne: +-90 % der Querschnittsgroesse
var _drag_half := 1.0             # Enden-Drag: halbe Höhe (Sensitivität)
var _moving_sel := false          # ausgewähltes Teil per Body-Drag verschieben
var _move_kids: Array = []        # Anbauten (auswärtiger Teilbaum), die beim Verschieben mitwandern
var _clipboard: Dictionary = {}   # Strg+C-Ablage: reine Daten, kein Node-Verweis (siehe copy_selected)
var _move_sel_p0 := Vector3.ZERO  # Startposition des gewählten Teils für den Kid-Versatz
var _move_plane := Plane()
var _move_grab := Vector3.ZERO
var _edit_xf0 := Transform3D()    # Snapshot bei Drag-Beginn (History nur bei echter Änderung)
var _edit_sc0 := Vector3.ONE
# Blender-artiges Gizmo: Modus 0=Bewegen (Pfeile) · 1=Drehen (ziehen) · 2=Skalieren (Würfel).
# Tasten G/R/S. Vorhandenes Teil anklicken = auswählen, dann je nach Modus bearbeiten.
const GIZ_MOVE := 0
const GIZ_ROTATE := 1
const GIZ_SCALE := 2
const GIZ_ENDS := 3             # Enden skalieren (nur Rumpfsegmente: vorne/hinten dick/dünn)
const GIZ_SHIFT := 4            # Enden VERSETZEN (eigener Modus, sonst kollidieren die
                                # Griffe mit den Taper-Wuerfeln und man greift den falschen)
var gizmo_mode := GIZ_MOVE
var _drag_kind := "scale"         # "move" (Pfeil) | "rotate" (Ring) | "scale" (Würfel)
var _rotating := false            # (Alt-Pfad, ungenutzt — Drehen läuft jetzt über Ring-Griffe)
var _rot_b0 := Basis()
# Welt-ausgerichteter Halter für Bewegen-/Drehen-Griffe (steht NICHT mit der Teil-Rotation,
# sondern global zur Welt). Skalier-Würfel bleiben am Teil (lokal -> Dimensionen strecken).
var _gizmo_root: Node3D = null
var _hover_handle: Node3D = null  # Griff unter der Maus (Hover-Highlight)
# Ring-Drehung (Drag eines Dreh-Rings)
var _rot_axis_w := Vector3.UP     # Welt-Drehachse
var _rot_center := Vector3.ZERO   # Drehzentrum (Teil-Weltposition)
var _rot_u := Vector3.RIGHT       # Referenzachsen in der Ringebene
var _rot_v := Vector3.BACK
var _rot_a0 := 0.0                 # Startwinkel
# Rechtsklick-Kontextmenü (Bewegen/Drehen/Skalieren/Umdrehen/Löschen)
var _ctx_menu: PopupMenu = null
var _rmb_press := Vector2.ZERO
var _rmb_moved := false
const RING_MARGIN := 1.1          # Dreh-Ring-Radius = max. Halbgröße + dieser Abstand


func _ready() -> void:
	design_root = Node3D.new()
	design_root.name = "DesignRoot"
	add_child(design_root)
	_make_markers()
	# Rechtsklick-Kontextmenü auf ein Teil: Werkzeug wählen / umdrehen / löschen
	_ctx_menu = PopupMenu.new()
	add_child(_ctx_menu)
	_ctx_menu.id_pressed.connect(_on_ctx_id)
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)


func set_camera(c: Camera3D) -> void:
	camera = c


func set_active(active: bool) -> void:
	set_process(active)
	set_physics_process(active)
	set_process_unhandled_input(active)
	_orbiting = false
	_panning = false
	_left_orbit = false
	if not active and _carrying:
		_carrying = false
		_carry_existing = false
		carry_id = ""
		_rebuild_ghost()
	if not active:
		_deselect()
		# Kamera für den Flug wieder auf Perspektive (falls Blueprint-Ortho-Ansicht aktiv war)
		if camera:
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	if ghost:
		ghost.visible = false
	if active:
		_update_camera()


func _active_id() -> String:
	return carry_id if _carrying else brush_id


# Drag aus der Teile-Liste (Inventar) gestartet: Teil "in die Hand nehmen", Ghost folgt der
# Maus. Loslassen über dem 3D-Raum platziert (in _process erkannt), über der UI verworfen.
func begin_drag_from_palette(id: String) -> void:
	if _carrying or id == "":
		return
	erase_mode = false
	paint_mode = false
	brush_id = id
	carry_id = id
	_carry_existing = false
	_carry_scale = Vector3.ONE
	_carry_color = Color(0, 0, 0, 0)
	_carrying = true
	_carry_from_tile = true
	_lmb_was_down = true
	ghost_rot = 0
	_deselect()
	_rebuild_ghost()


# ---------------------------------------------------------------------------
# Kamera & Vorschau
# ---------------------------------------------------------------------------
var _sel_glow_nodes: Array = []    # Overlay-Meshes der Auswahl-Animation
var _sel_glow_mat: ShaderMaterial = null
var _sel_glow_tween: Tween = null
var _sel_glow_shader: Shader = null
var _heatmap_dirty := false        # Windkanal-Heatmap muss neu gerechnet werden
var _heatmap_t := 0.0              # Throttle-Timer dafür


func _process(delta: float) -> void:
	# Tastatur-Zoom (+/- bzw. Numpad)
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		orbit_dist -= 28.0 * delta
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		orbit_dist += 28.0 * delta
	# Loslassen robust per Polling erkennen (deckt auch ab: Inventar-Drag, dessen Druck an die
	# UI ging, und Teile, die über der UI losgelassen werden -> sonst "klebt" das Teil).
	if _carrying:
		var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if _lmb_was_down and not down:
			_on_left_release()   # platziert am Mauspunkt (oder verwirft, wenn über UI/ungültig)
		_lmb_was_down = down
	else:
		_lmb_was_down = false
	# Griff-Hover: Transform-Griff unter der Maus hervorheben (wie in 3D-Programmen) — nicht beim Ziehen.
	if selected_part != null and _drag_handle == null and not _moving_sel and not _carrying and camera != null:
		var hov: Node3D = null
		var hh := _raycast_mouse(HANDLE_LAYER)
		if not hh.is_empty():
			var c = hh.get("collider")
			if c and c.is_in_group("handle"):
				hov = c
		if hov != _hover_handle:
			_set_handle_hl(_hover_handle, false)
			_hover_handle = hov
			_set_handle_hl(_hover_handle, true)
	_update_camera()
	# Windkanal-Heatmap vom Editier-Frame entkoppeln: höchstens ~8×/s neu rechnen statt bei
	# JEDEM Drag-Frame (das Strahlengitter macht sonst bis ~2400 Raycasts/Frame -> Ruckeln).
	if wind_tunnel:
		_heatmap_t -= delta
		if _heatmap_dirty and _heatmap_t <= 0.0:
			_heatmap_dirty = false
			_heatmap_t = 0.12
			_apply_drag_heatmap()


func _physics_process(_delta: float) -> void:
	_update_ghost()


func _update_camera() -> void:
	if camera == null:
		return
	orbit_pitch = clamp(orbit_pitch, -1.55, 1.55)   # bis fast senkrecht (für Oben-Ansicht)
	orbit_dist = clamp(orbit_dist, 2.5, 110.0)
	var dir := Vector3(
		cos(orbit_pitch) * sin(orbit_yaw),
		sin(orbit_pitch),
		cos(orbit_pitch) * cos(orbit_yaw))
	camera.global_position = orbit_focus + dir * orbit_dist
	# Bei einer Blueprint-Ansicht orthografisch (kein Perspektiv-Verzerren beim Ausrichten).
	if _ortho_view > 0:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.keep_aspect = Camera3D.KEEP_HEIGHT   # ortho: size = Höhe (unverzerrt, wie bisher)
		camera.size = orbit_dist
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		ViewUtil.apply_vfov(camera, 64.0)           # 64° vertikal (16:9); Ultrawide -> kein Fischauge
	var up := Vector3.UP if _ortho_view != 3 else Vector3(0, 0, -1)  # Oben-Ansicht: Nase nach oben im Bild
	camera.look_at(orbit_focus, up)


func _update_ghost() -> void:
	var id := _active_id()
	if id == "":
		if ghost:
			ghost.visible = false
		return
	var snap := _compute_snap_for(id, _raycast_mouse())
	# Modell ggf. tauschen (z.B. Prop-Motor am Rumpf -> bündige Cowl) -> Vorschau passt zum Ergebnis.
	var eid: String = String(snap.get("id", id))
	if eid != _ghost_built_id:
		_rebuild_ghost(eid)
	if ghost == null:
		return
	if snap.get("valid", false):
		# Gültiger Andockpunkt -> Hologramm rastet ein, grün = platzierbar.
		_last_valid = true
		_last_xform = snap["xform"]
		ghost.transform = _last_xform
		ghost.scale = snap.get("scale", Vector3.ONE)   # Vorschau der übernommenen Breite/Höhe
		ghost.visible = true
		_set_ghost_valid(true)
	else:
		# Kein Andockpunkt -> Hologramm trotzdem zeigen (frei unter dem Cursor),
		# rot = "hier nicht platzierbar". Gesetzt wird erst auf einem gültigen Punkt.
		_last_valid = false
		ghost.transform = _free_ghost_xform()
		ghost.scale = Vector3.ONE
		ghost.visible = true
		_set_ghost_valid(false)


# Hologramm einfärben: grün = platzierbar, rot = (noch) nicht platzierbar.
func _set_ghost_valid(valid: bool) -> void:
	if valid == _ghost_valid:
		return
	_ghost_valid = valid
	var alb := Color(0.4, 1.0, 0.55, 0.45) if valid else Color(1.0, 0.42, 0.36, 0.42)
	var emi := Color(0.2, 0.8, 0.3) if valid else Color(0.95, 0.3, 0.22)
	for m in _ghost_mats:
		if m != null:
			m.albedo_color = alb
			m.emission = emi


# Welt-Punkt unter der Maus (Schnitt mit der Bau-Ebene y=0, sonst fester Abstand).
func _mouse_world_point() -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.y) > 0.0001:
		var t := -from.y / dir.y
		if t > 0.0:
			return from + dir * t
	return from + dir * maxf(orbit_dist, 6.0)


# Transform des frei schwebenden Hologramms (kein Snap).
func _free_ghost_xform() -> Transform3D:
	var b := Basis.IDENTITY
	if ghost_rot != 0:
		b = Basis(Vector3.UP, deg_to_rad(90.0 * ghost_rot))
	return Transform3D(b, _mouse_world_point())


# ---------------------------------------------------------------------------
# Eingabe
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_orbiting = true
					_rmb_press = event.position
					_rmb_moved = false
				else:
					_orbiting = false
					if not _rmb_moved:
						_on_right_click()   # reiner Rechtsklick (kein Drehen) -> Kontextmenü
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					orbit_dist -= 1.2
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					orbit_dist += 1.2
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_on_left_press()
				elif _drag_handle != null or _moving_sel or _rotating:
					_transform_release()
				else:
					_on_left_release()
	elif event is InputEventMagnifyGesture:        # Trackpad-Pinch zum Zoomen
		orbit_dist /= maxf(event.factor, 0.01)
	elif event is InputEventPanGesture:            # Zwei-Finger-Scroll zum Zoomen
		orbit_dist += event.delta.y * 0.6
	elif event is InputEventMouseMotion:
		if _drag_handle != null or _moving_sel or _rotating:
			_update_transform_drag()
		elif _carrying:
			pass # Ghost folgt der Maus in _update_ghost()
		elif _orbiting or _left_orbit:
			if _orbiting and event.position.distance_to(_rmb_press) > 5.0:
				_rmb_moved = true   # gedreht -> kein Kontextmenü beim Loslassen
			orbit_yaw -= event.relative.x * 0.01
			orbit_pitch += event.relative.y * 0.01
			_ortho_view = 0   # manuelles Drehen -> zurück zur freien Perspektive
		elif _panning and camera:
			var cam_b := camera.global_transform.basis
			var pan_amt := orbit_dist * 0.0016
			orbit_focus -= cam_b.x * event.relative.x * pan_amt
			orbit_focus += cam_b.y * event.relative.y * pan_amt
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed or event.meta_pressed:
			if event.keycode == KEY_Z:
				if event.shift_pressed:
					redo()
				else:
					undo()
			elif event.keycode == KEY_Y:
				redo()
			elif event.keycode == KEY_D:
				duplicate_selected()
			elif event.keycode == KEY_C:
				copy_selected()
			elif event.keycode == KEY_V:
				paste_clipboard()
			return
		match event.keycode:
			KEY_G:
				if selected_part != null:
					set_gizmo_mode(GIZ_MOVE)
			KEY_R:
				if selected_part != null:
					set_gizmo_mode(GIZ_ROTATE)
				else:
					ghost_rot = (ghost_rot + 1) % 4   # Ghost beim Setzen drehen
			KEY_S:
				if selected_part != null:
					set_gizmo_mode(GIZ_SCALE)
			# E = Enden verjuengen, T = Enden VERSETZEN (eigener Modus)
			KEY_E:
				if selected_part != null:
					set_gizmo_mode(GIZ_ENDS)
			KEY_T:
				if selected_part != null:
					set_gizmo_mode(GIZ_SHIFT)
				# V: ein Rumpf-Ende verjüngen (schmaler), Shift+V = breiter.
			KEY_V:
				if selected_part != null:
					nudge_taper((1.0 / 0.85) if event.shift_pressed else 0.85)
			# Pfeiltasten: ausgewähltes Teil fein verschieben (Weltachsen, 0.25er-Schritte)
			KEY_LEFT:
				nudge_selected(Vector3(-0.25, 0, 0))
			KEY_RIGHT:
				nudge_selected(Vector3(0.25, 0, 0))
			KEY_UP:
				nudge_selected(Vector3(0, 0, -0.25))
			KEY_DOWN:
				nudge_selected(Vector3(0, 0, 0.25))
			KEY_PAGEUP:
				nudge_selected(Vector3(0, 0.25, 0))
			KEY_PAGEDOWN:
				nudge_selected(Vector3(0, -0.25, 0))
			# Blueprint-Ansichten
			KEY_1:
				set_view(1)
			KEY_2:
				set_view(2)
			KEY_3:
				set_view(3)
			KEY_4:
				set_view(0)
			KEY_F:
				reset_camera()
			KEY_ESCAPE:
				if selected_part != null:
					_deselect()
				elif _carrying:
					_cancel_carry()
				else:
					set_brush("")
			KEY_X, KEY_DELETE:
				_delete_hovered()
			KEY_M:
				symmetry = not symmetry
				_refresh_all_wing_fill()
			KEY_N:
				snap_enabled = not snap_enabled
				snap_changed.emit(snap_enabled)


# Linke Maus im 3D-Raum: Abriss / Lackieren / vorhandenes Teil AUSWÄHLEN+bearbeiten / Kamera drehen.
# Neue Teile kommen per Drag&Drop aus der Teile-Liste (begin_drag_from_palette), NICHT von hier.
func _on_left_press() -> void:
	var hit := _raycast_mouse()
	if erase_mode:
		_delete_hovered()
		return
	if paint_mode:
		_paint_hovered(hit)
		return
	# Vorhandenes Teil anklicken = auswählen -> Gizmo (Bewegen/Drehen/Skalieren) + Panel.
	# Klick auf leeren Raum = abwählen + Kamera drehen.
	_transform_left_press()


func _on_left_release() -> void:
	if _carrying:
		var over_ui := get_viewport().gui_get_hovered_control() != null
		var placed := false
		if over_ui:
			# Über der UI losgelassen: neues Teil verwerfen, vorhandenes an alte Stelle zurück.
			if _carry_existing:
				_place_id(carry_id, _carry_orig, _carry_scale, _carry_color)
		else:
			var snap := _compute_snap_for(carry_id, _raycast_mouse())
			if snap.get("valid", false):
				# Auto-Fit liefert ggf. eine angepasste Größe (Breite/Höhe vom Zielteil) und ein
				# anderes Modell (z.B. Prop-Motor -> bündige Cowl) inkl. übernommener Farbe.
				_place_id(snap.get("id", carry_id), snap["xform"],
					snap.get("scale", _carry_scale), snap.get("color", _carry_color))
				# Umgekehrte Baurichtung: Wird der Rumpf AN den bereits stehenden normalen
				# Propellermotor gesetzt, bekommt auch dieser die kurze, plan geschnittene
				# Bughauben-Variante. Das Snap-Dictionary hält das Ziel nur für diesen Drop.
				var cut_target: Node3D = snap.get("cut_target") as Node3D
				if cut_target != null:
					_convert_prop_to_nose(cut_target)
				placed = true
			elif _carry_existing:
				_place_id(carry_id, _carry_orig, _carry_scale, _carry_color)  # ungültig -> zurück
		_carrying = false
		_carry_existing = false
		_carry_from_tile = false
		carry_id = ""
		brush_id = ""        # nach Inventar-Drop zurück in den Greif-/Verschiebe-Modus
		_rebuild_ghost()
		if placed:
			_push_history()
		_notify_changed()
	_left_orbit = false


func _cancel_carry() -> void:
	if not _carrying:
		return
	if _carry_existing:
		_place_id(carry_id, _carry_orig, _carry_scale, _carry_color)
	_carrying = false
	_carry_existing = false
	_carry_from_tile = false
	carry_id = ""
	brush_id = ""
	_rebuild_ghost()
	_notify_changed()


# ===========================================================================
# Transform-Werkzeug: Teil auswählen, Flächen-Griffe ziehen (Länge/Breite/Höhe),
# Body ziehen = verschieben. Wie SimplePlanes/Blender-Transform.
# ===========================================================================
# In den Bearbeiten-Default zurück (kein Palette-Teil, kein Abriss/Lackieren).
func clear_tools() -> void:
	brush_id = ""
	erase_mode = false
	paint_mode = false
	_rebuild_ghost()


func _axis_vec(i: int) -> Vector3:
	return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][i]


func _select_part(part: Node3D) -> void:
	selected_part = part
	_build_handles()
	_apply_sel_glow(part)
	_emit_selection()


func _deselect() -> void:
	selected_part = null
	_drag_handle = null
	_moving_sel = false
	_rotating = false
	_clear_handles()
	_clear_sel_glow()
	selection_changed.emit({})


func _emit_selection() -> void:
	if selected_part == null:
		selection_changed.emit({})
		return
	var p := PartCatalog.get_part(selected_part.get_meta("part_id"))
	selection_changed.emit({
		"id": selected_part.get_meta("part_id"),
		"name": p.get("name", selected_part.get_meta("part_id")),
		"scale": selected_part.get_meta("pscale", Vector3.ONE),
		"is_root": selected_part.get_meta("is_root", false),
		"gizmo": gizmo_mode,
		"taperable": p.get("taperable", false),
		"biends": p.get("biends", false),
		"taper": selected_part.get_meta("taper", 1.0),
		"taper_front": selected_part.get_meta("taper_front", 1.0),
		"is_prop": String(p.get("shape", "")) == "prop",   # Reverse-Option nur für Prop-Triebwerke
		"thrust_reverse": selected_part.get_meta("thrust_reverse", false),
	})


# Schub-Umkehr (Prop-Option) für das ausgewählte Teil setzen — auch am Spiegelpartner.
func set_reverse_thrust(on: bool) -> void:
	if selected_part == null:
		return
	selected_part.set_meta("thrust_reverse", on)
	var m = selected_part.get_meta("mirror") if selected_part.has_meta("mirror") else null
	if is_instance_valid(m):
		m.set_meta("thrust_reverse", on)
	_push_history()
	_notify_changed()


# --- Aktionen auf das ausgewählte Teil (vom UI-Panel aufgerufen) -----------
func nudge_scale(axis: int, factor: float) -> void:
	if selected_part == null:
		return
	var sc: Vector3 = selected_part.get_meta("pscale", Vector3.ONE)
	var v := [sc.x, sc.y, sc.z]
	var new_sc: Vector3
	if Input.is_key_pressed(KEY_SHIFT):
		# Shift = UNIFORM: alle 3 Achsen mit demselben Faktor skalieren
		new_sc = Vector3(clampf(sc.x * factor, 0.25, 6.0), clampf(sc.y * factor, 0.25, 6.0),
			clampf(sc.z * factor, 0.25, 6.0))
	elif (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)) and axis != 2:
		# Strg + X/Y = Querschnitt: X UND Y zusammen (Länge Z bleibt)
		new_sc = Vector3(clampf(sc.x * factor, 0.25, 6.0), clampf(sc.y * factor, 0.25, 6.0), sc.z)
	else:
		v[axis] = clampf(float(v[axis]) * factor, 0.25, 6.0)
		new_sc = Vector3(v[0], v[1], v[2])
	# Beim Skalieren die zur Rumpfmitte/Wurzel zeigende Fläche fix lassen -> kein Spalt.
	var origin := _scale_anchor_origin(selected_part, axis, sc, new_sc)
	_apply_sel_transform(selected_part.transform.basis, origin, new_sc)
	_emit_selection()
	_push_history()


# Neue Position beim Skalieren, so dass die zur Wurzel (Rumpfmitte, 0,0,0) NÄHERE Fläche
# fix bleibt — die Anbindung ans Nachbarteil bleibt bündig, es wächst nach außen.
func _scale_anchor_origin(part: Node3D, axis_i: int, old_s: Vector3, new_s: Vector3) -> Vector3:
	var p := PartCatalog.get_part(part.get_meta("part_id"))
	var bs: Vector3 = PartCatalog.col_size(p)
	var base: float = [bs.x, bs.y, bs.z][axis_i]
	var oh: float = base * [old_s.x, old_s.y, old_s.z][axis_i] * 0.5
	var nh: float = base * [new_s.x, new_s.y, new_s.z][axis_i] * 0.5
	var wdir: Vector3 = (part.transform.basis * _axis_vec(axis_i)).normalized()
	var c: Vector3 = part.position
	# Die näher an der Wurzel liegende der beiden Flächen verankern:
	if (c - wdir * oh).length() <= (c + wdir * oh).length():
		return c + wdir * (nh - oh)   # −wdir-Fläche (innen) bleibt fix -> wächst nach außen
	return c - wdir * (nh - oh)       # +wdir-Fläche bleibt fix


func reset_selected_scale() -> void:
	if selected_part == null:
		return
	_apply_sel_transform(selected_part.transform.basis, selected_part.position, Vector3.ONE)
	_emit_selection()
	_push_history()


func rotate_selected() -> void:
	if selected_part == null:
		return
	var b := selected_part.transform.basis * Basis(Vector3.UP, deg_to_rad(90.0))
	_apply_sel_transform(b.orthonormalized(), selected_part.position,
		selected_part.get_meta("pscale", Vector3.ONE))
	_push_history()


func tilt_selected() -> void:
	if selected_part == null:
		return
	var b := selected_part.transform.basis * Basis(Vector3(0, 0, 1), deg_to_rad(45.0))
	_apply_sel_transform(b.orthonormalized(), selected_part.position,
		selected_part.get_meta("pscale", Vector3.ONE))
	_push_history()


func delete_selected() -> void:
	# Alles löschbar — auch die Wurzel. Ist danach kein Teil mehr da, ist der Bauraum leer
	# und das nächste platzierte Teil startet (zentriert) einen neuen Bauplan.
	if selected_part == null:
		return
	var part := selected_part
	_deselect()
	if part.has_meta("mirror"):
		var m = part.get_meta("mirror")
		if is_instance_valid(m):
			m.free()
	part.free()
	_push_history()
	_notify_changed()


# Rechtsklick auf ein Teil: auswählen + Kontextmenü (Werkzeug wählen / umdrehen / löschen).
func _on_right_click() -> void:
	if erase_mode or paint_mode or _carrying:
		return
	var part := _pick_part_at_mouse()
	if part == null:
		return
	if part != selected_part:
		_select_part(part)
	_ctx_menu.clear()
	_ctx_menu.add_item("Bewegen", 0)
	_ctx_menu.add_item("⟳  Drehen", 1)
	_ctx_menu.add_item("⤢  Skalieren", 2)
	# Die beiden ENDEN-Werkzeuge — nur für Rumpfsegmente (biends). Beide gehoeren hier
	# zusammen: ohne den zweiten Eintrag kam man ueber das Rechtsklickmenue gar nicht in
	# den Versetzen-Modus und zog stattdessen weiter an den Taper-Wuerfeln.
	if PartCatalog.get_part(part.get_meta("part_id")).get("biends", false):
		_ctx_menu.add_item("Enden skalieren (X/Y)", 5)
		_ctx_menu.add_item("Enden verschieben (hoch/seitlich)", 6)
	_ctx_menu.add_separator()
	_ctx_menu.add_item("Umdrehen (180°)", 3)
	_ctx_menu.add_item("Löschen", 4)   # auch die Wurzel ist löschbar
	_ctx_menu.reset_size()
	_ctx_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))


func _on_ctx_id(id: int) -> void:
	match id:
		0: set_gizmo_mode(GIZ_MOVE)
		1: set_gizmo_mode(GIZ_ROTATE)
		2: set_gizmo_mode(GIZ_SCALE)
		5: set_gizmo_mode(GIZ_ENDS)
		6: set_gizmo_mode(GIZ_SHIFT)
		3: invert_selected()
		4: delete_selected()


# Ausgewähltes Teil um 180° um die Hochachse umdrehen (z. B. Triebwerk/Flosse herumdrehen).
func invert_selected() -> void:
	if selected_part == null:
		return
	var nb := (Basis(Vector3.UP, PI) * selected_part.transform.basis).orthonormalized()
	_apply_sel_transform(nb, selected_part.position, selected_part.get_meta("pscale", Vector3.ONE))
	_push_history()
	_notify_changed()


# Ausgewähltes Teil klonen (mit Spiegel via Symmetrie), seitlich versetzt, und den Klon auswählen.
func duplicate_selected() -> void:
	if selected_part == null:
		return
	_teil_einsetzen(_teil_schnappschuss(selected_part))


# Schnappschuss eines Teils im get_design()-Format — eine Quelle fuer Duplizieren,
# Kopieren und Speichern, damit nie wieder eine Eigenschaft nur an einer Stelle mitkommt.
func _teil_schnappschuss(teil: Node3D) -> Dictionary:
	# Dieselben Schluessel wie get_design(), aber fuer EIN Teil (get_design liefert keine
	# Zuordnung zum Node zurueck, also direkt am Node auslesen).
	return {
		"id": teil.get_meta("part_id", ""),
		"xform": teil.transform,
		"color": teil.get_meta("color", Color(0, 0, 0, 0)),
		"scale": teil.get_meta("pscale", Vector3.ONE),
		"taper": teil.get_meta("taper", 1.0),
		"taper_front": teil.get_meta("taper_front", 1.0),
		"taper_y": teil.get_meta("taper_y", -1.0),
		"taper_front_y": teil.get_meta("taper_front_y", -1.0),
		"tuser_b": teil.has_meta("taper_user"),
		"tuser_f": teil.has_meta("taper_front_user"),
		"fill": teil.get_meta("fill", 0.0),
		"glen": teil.get_meta("gear_len", 1.0),
		"br": Array(_block_r(teil)),
		"sf": teil.get_meta("shift_front", Vector2.ZERO),
		"sb": teil.get_meta("shift_back", Vector2.ZERO),
		"bsc": teil.get_meta("block_sc", Vector3.ONE),
		"thrust_reverse": teil.get_meta("thrust_reverse", false),
	}


# Setzt einen Schnappschuss als NEUES Teil, nach Bildschirm-rechts versetzt, und waehlt es aus.
func _teil_einsetzen(daten: Dictionary) -> void:
	var id: String = daten.get("id", "")
	if id == "" or not PartCatalog.has(id):
		return
	var xf: Transform3D = daten.get("xform", Transform3D())
	var off := Vector3(1.2, 0.0, 0.0)
	if camera != null:
		off = camera.global_transform.basis.x.normalized() * 1.3   # nach Bildschirm-rechts versetzt
	xf.origin += off
	var np := _place_id(id, xf, daten.get("scale", Vector3.ONE),
		daten.get("color", Color(0, 0, 0, 0)))
	if np != null:
		# Verjuengung setzen, BEVOR die Form uebernommen wird (die baut das Visual neu).
		for schluessel in [["taper", "taper"], ["taper_front", "taper_front"],
				["taper_y", "taper_y"], ["taper_front_y", "taper_front_y"]]:
			np.set_meta(schluessel[0], float(daten.get(schluessel[1], 1.0)))
		np.set_meta("thrust_reverse", bool(daten.get("thrust_reverse", false)))
		_form_uebernehmen(np, id, daten)
		_rebuild_visual(np)
		_apply_part_scale(np, np.get_meta("pscale", Vector3.ONE))
		# Im Symmetrie-Modus entsteht ein Spiegel — der muss dieselbe Formung erben,
		# sonst steht auf der einen Seite ein geformtes und auf der anderen ein rohes Teil.
		var nsc: Vector3 = np.get_meta("pscale", Vector3.ONE)
		var nm = np.get_meta("mirror") if np.has_meta("mirror") else null
		if is_instance_valid(nm):
			nm.set_meta("thrust_reverse", bool(daten.get("thrust_reverse", false)))
			for tk in ["taper", "taper_front", "taper_y", "taper_front_y"]:
				(nm as Node3D).set_meta(tk, np.get_meta(tk, 1.0))
			for uk in ["taper_user", "taper_front_user"]:
				if np.has_meta(uk):
					(nm as Node3D).set_meta(uk, true)
			_sync_mirror_shift(np, nsc)
			_sync_mirror_block(np, nsc)
			_sync_mirror_gear(np, nm, nsc)
	_push_history()
	_notify_changed()
	if np != null:
		_select_part(np)


# Strg+C / Strg+V. Die Ablage ueberlebt Moduswechsel und Neuaufbauten, weil sie reine
# Daten haelt (kein Node-Verweis, der beim Loeschen ungueltig wuerde).
func copy_selected() -> void:
	if selected_part == null:
		return
	_clipboard = _teil_schnappschuss(selected_part)
	kopiert.emit(String(_clipboard.get("id", "")))


func paste_clipboard() -> void:
	if _clipboard.is_empty():
		return
	_teil_einsetzen(_clipboard)


# Ausgewähltes Teil um delta (Weltachsen) verschieben (Pfeiltasten-Feinjustage).
func nudge_selected(delta_world: Vector3) -> void:
	if selected_part == null:
		return
	_capture_move_kids()
	_apply_sel_transform(selected_part.transform.basis,
		selected_part.position + delta_world,
		selected_part.get_meta("pscale", Vector3.ONE))
	_move_kids = []
	_emit_selection()
	_push_history()


# Blueprint-Ansichten: 0=frei (Perspektive), 1=Front, 2=Seite, 3=Oben (orthografisch).
func set_view(preset: int) -> void:
	_ortho_view = preset
	match preset:
		1: orbit_yaw = PI; orbit_pitch = 0.0          # von vorne auf die Nase
		2: orbit_yaw = PI * 0.5; orbit_pitch = 0.0    # Seitenprofil
		3: orbit_yaw = 0.0; orbit_pitch = 1.55        # von oben
		_:
			orbit_yaw = 0.7; orbit_pitch = 0.4        # freie Perspektive
	_update_camera()


func _clear_handles() -> void:
	for h in _handles:
		if is_instance_valid(h):
			h.queue_free()
	_handles.clear()
	if is_instance_valid(_gizmo_root):
		_gizmo_root.queue_free()
	_gizmo_root = null
	_hover_handle = null


const GIZ_COLS := [Color(0.95, 0.3, 0.3), Color(0.4, 0.95, 0.4), Color(0.4, 0.6, 1.0)]  # X=rot Y=grün Z=blau


# Griffe je nach Modus aufbauen: Skalieren=6 Flächenwürfel, Bewegen=3 Achsenpfeile,
# Drehen=keine 3D-Griffe (Body ziehen = drehen, Panel-Buttons fürs 90°-Snappen).
func _build_handles() -> void:
	_clear_handles()
	if selected_part == null:
		return
	if gizmo_mode == GIZ_SCALE:
		_build_scale_handles()        # Würfel: bleiben am Teil (lokal -> Dimensionen strecken)
	elif gizmo_mode == GIZ_ENDS:
		_build_ends_handles()         # 4 Würfel an den Enden (lokal): vorne/hinten dick/dünn
	elif gizmo_mode == GIZ_SHIFT:
		_build_shift_handles()        # je Ende zwei Achsen-Zylinder zum Versetzen
	else:
		# Bewegen/Drehen: welt-ausgerichteter Halter (dreht NICHT mit dem Teil)
		_gizmo_root = Node3D.new()
		design_root.add_child(_gizmo_root)
		if gizmo_mode == GIZ_MOVE:
			_build_move_handles()
		else:
			_build_rotate_handles()
	# Fahrwerk: IMMER zusaetzlich der Bein-Griff (egal in welchem Gizmo-Modus) — beim
	# Reifen ist die Beinlaenge die haeufigste Anpassung, die soll nicht in einem
	# Untermodus versteckt sein.
	if String(PartCatalog.get_part(selected_part.get_meta("part_id")).get(
			"category", "")) == PartCatalog.CAT_GEAR:
		_build_leg_handle()
	# Klotz: acht Eckgriffe zum Abrunden, ebenfalls in jedem Gizmo-Modus
	if String(PartCatalog.get_part(selected_part.get_meta("part_id")).get(
			"shape", "")) == "block":
		_build_round_handles()
	_update_handles()


func _gizmo_mat(c: Color, bright := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var col: Color = Color(1, 1, 1) if bright else c   # Hover -> weiß/leuchtend
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.4 if bright else 0.4
	m.no_depth_test = true   # Griffe immer sichtbar (auch hinter Geometrie)
	return m


# Griff hervorheben/zurücksetzen (Hover) — alle Mesh-Kinder umfärben.
func _set_handle_hl(h: Node3D, on: bool) -> void:
	if not is_instance_valid(h):
		return
	var col: Color = h.get_meta("base_col", Color(1, 1, 1))
	for ch in h.get_children():
		if ch is MeshInstance3D:
			ch.material_override = _gizmo_mat(col, on)


# 6 Flächenwürfel (Skalieren) — Würfel an den Flächenmitten, ziehen streckt die Achse.
func _build_scale_handles() -> void:
	for i in 3:
		for s in [1.0, -1.0]:
			var h := StaticBody3D.new()
			h.add_to_group("handle")
			h.collision_layer = HANDLE_LAYER
			h.collision_mask = 0
			h.set_meta("kind", "scale")
			h.set_meta("axis", i)
			h.set_meta("sign", s)
			h.set_meta("base_col", GIZ_COLS[i])
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.5, 0.5, 0.5)
			cs.shape = bs
			h.add_child(cs)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.42, 0.42, 0.42)
			mi.mesh = bm
			mi.material_override = _gizmo_mat(GIZ_COLS[i])
			h.add_child(mi)
			selected_part.add_child(h)
			_handles.append(h)


# Meta-Schlüssel für ein Enden-Viereck: vorne/hinten (sign) × X/Y (axis).
func _ends_key(sgn: float, axis: int) -> String:
	if sgn < 0.0:
		return "taper_front" if axis == 0 else "taper_front_y"
	return "taper" if axis == 0 else "taper_y"


# Enden-Modus: 4 Vierecke — vorne (-Z) & hinten (+Z), je eines für X (Breite, seitlich)
# und Y (Höhe, oben). Nach außen ziehen macht dieses Ende in DIESER Achse dicker.
# Ein Wuerfel unter dem Reifen: nach unten ziehen = Bein ausfahren (mehr Bodenfreiheit).
func _build_leg_handle() -> void:
	var h := StaticBody3D.new()
	h.add_to_group("handle")
	h.collision_layer = HANDLE_LAYER
	h.collision_mask = 0
	h.set_meta("kind", "leg")
	h.set_meta("axis", 1)
	h.set_meta("sign", -1.0)
	var col := Color(1.0, 0.85, 0.25)
	h.set_meta("base_col", col)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.5, 0.5, 0.5)
	cs.shape = bs
	h.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.4, 0.4)
	mi.mesh = bm
	mi.material_override = _gizmo_mat(col)
	h.add_child(mi)
	selected_part.add_child(h)
	_handles.append(h)


# Acht Eckgriffe des Klotzes: nach INNEN ziehen rundet diese Ecke ab.
func _build_round_handles() -> void:
	for i in 8:
		var h := StaticBody3D.new()
		h.add_to_group("handle")
		h.collision_layer = HANDLE_LAYER
		h.collision_mask = 0
		h.set_meta("kind", "round")
		h.set_meta("axis", 0)
		h.set_meta("corner", i)
		var col := Color(0.45, 1.0, 0.65)
		h.set_meta("base_col", col)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.42, 0.42, 0.42)
		cs.shape = bs
		h.add_child(cs)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.17
		sm.height = 0.34
		sm.radial_segments = 8
		sm.rings = 5
		mi.mesh = sm
		mi.material_override = _gizmo_mat(col)
		h.add_child(mi)
		selected_part.add_child(h)
		_handles.append(h)


# Je Ende ZWEI Achsen-Zylinder zum VERSETZEN: einer laengs X (links/rechts), einer
# laengs Y (hoch/runter). Jeder zieht NUR auf seiner Achse — eine freie Kugel liess sich
# schlechter kontrollieren, weil sie beide Richtungen gleichzeitig verstellte.
# Der vorhandene Enden-Taper skaliert das Ende nur; versetzen ging vorher gar nicht.
func _build_shift_handles() -> void:
	for s in [-1.0, 1.0]:
		for ax in [0, 1]:
			var h := StaticBody3D.new()
			h.add_to_group("handle")
			h.collision_layer = HANDLE_LAYER
			h.collision_mask = 0
			h.set_meta("kind", "shift")
			h.set_meta("axis", ax)              # 0 = links/rechts, 1 = hoch/runter
			h.set_meta("sign", s)               # -1 = vorderes Ende, +1 = hinteres
			# Achsenfarbe wie beim Bewegen-Gizmo, vorn etwas heller als hinten
			var col: Color = GIZ_COLS[ax] if s < 0.0 else GIZ_COLS[ax].darkened(0.25)
			h.set_meta("base_col", col)
			# Sieht aus wie der normale Bewegen-Pfeil (Schaft + Kegelspitze), nur kleiner:
			# es ist dieselbe Geste (auf einer Achse ziehen), also dieselbe Sprache. Der
			# schlichte Zylinder davor las sich wie ein Skalier-Anfasser.
			var achse := _axis_vec(ax)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			# Klickbox LAENGER als der Schaft, damit auch die Spitze trifft (dieselbe
			# Lehre wie beim Bewegen-Gizmo), quer aber schlank — sonst ueberlappen sich
			# der X- und der Y-Pfeil desselben Endes wieder.
			bs.size = Vector3(1.5, 0.42, 0.42) if ax == 0 else Vector3(0.42, 1.5, 0.42)
			cs.shape = bs
			cs.position = achse * 0.18
			h.add_child(cs)
			var schaft := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.8, 0.1, 0.1) if ax == 0 else Vector3(0.1, 0.8, 0.1)
			schaft.mesh = sm
			schaft.material_override = _gizmo_mat(col)
			h.add_child(schaft)
			var spitze := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = 0.17
			cm.height = 0.36
			cm.radial_segments = 12
			spitze.mesh = cm
			spitze.material_override = _gizmo_mat(col)
			spitze.position = achse * 0.55       # zeigt nach AUSSEN, vom Teil weg
			if ax == 0:
				spitze.rotation = Vector3(0, 0, -PI * 0.5)   # CylinderMesh zeigt +Y -> X
			h.add_child(spitze)
			selected_part.add_child(h)
			_handles.append(h)


func _build_ends_handles() -> void:
	for s in [-1.0, 1.0]:
		for ax in [0, 1]:
			var h := StaticBody3D.new()
			h.add_to_group("handle")
			h.collision_layer = HANDLE_LAYER
			h.collision_mask = 0
			h.set_meta("kind", "ends")
			h.set_meta("axis", ax)              # 0 = X (Breite), 1 = Y (Höhe)
			h.set_meta("sign", s)               # -1 vorne, +1 hinten
			# vorne bläulich / hinten orange; Y-Würfel grünlich getönt (X vs. Y unterscheidbar)
			var base: Color = Color(0.35, 0.8, 1.0) if s < 0.0 else Color(1.0, 0.62, 0.2)
			var col: Color = base if ax == 0 else base.lerp(Color(0.25, 1.0, 0.45), 0.55)
			h.set_meta("base_col", col)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.5, 0.5, 0.5)
			cs.shape = bs
			h.add_child(cs)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.42, 0.42, 0.42)
			mi.mesh = bm
			mi.material_override = _gizmo_mat(col)
			h.add_child(mi)
			selected_part.add_child(h)
			_handles.append(h)


# 3 Achsenpfeile (Bewegen) — Schaft + Spitze entlang +X/+Y/+Z, ziehen verschiebt entlang Achse.
func _build_move_handles() -> void:
	for i in 3:
		var axis := _axis_vec(i)
		var h := StaticBody3D.new()
		h.add_to_group("handle")
		h.collision_layer = HANDLE_LAYER
		h.collision_mask = 0
		h.set_meta("kind", "move")
		h.set_meta("axis", i)
		h.set_meta("sign", 1.0)
		h.set_meta("base_col", GIZ_COLS[i])
		# Collider entlang der Achse: LÄNGER als der Schaft (die Pfeilspitze sitzt
		# bei 0.95-1.2 und lag außerhalb der alten ±0.75-Box -> Klicks auf die
		# Spitze gingen ins Leere) und großzügig dick (leichter zu treffen).
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		if i == 0: box.size = Vector3(2.6, 0.55, 0.55)
		elif i == 1: box.size = Vector3(0.55, 2.6, 0.55)
		else: box.size = Vector3(0.55, 0.55, 2.6)
		cs.shape = box
		cs.position = axis * 0.25   # asymmetrisch: deckt -1.05 .. +1.55 ab (inkl. Spitze)
		h.add_child(cs)
		# Schaft
		var shaft := MeshInstance3D.new()
		var sm := BoxMesh.new()
		if i == 0: sm.size = Vector3(1.4, 0.12, 0.12)
		elif i == 1: sm.size = Vector3(0.12, 1.4, 0.12)
		else: sm.size = Vector3(0.12, 0.12, 1.4)
		shaft.mesh = sm
		shaft.material_override = _gizmo_mat(GIZ_COLS[i])
		h.add_child(shaft)
		# Pfeilspitze (Kegel) an der Spitze
		var tip := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.22
		cm.height = 0.5
		tip.mesh = cm
		tip.material_override = _gizmo_mat(GIZ_COLS[i])
		tip.position = axis * 0.95
		if i == 0: tip.rotation = Vector3(0, 0, -PI * 0.5)   # Y->X
		elif i == 2: tip.rotation = Vector3(PI * 0.5, 0, 0)  # Y->Z
		h.add_child(tip)
		_gizmo_root.add_child(h)   # welt-ausgerichtet (nicht an der Teil-Rotation)
		_handles.append(h)


# 3 Dreh-Ringe (welt-ausgerichtet): Ring um jede Weltachse, ziehen dreht das Teil um diese Achse.
func _build_rotate_handles() -> void:
	var r := _gizmo_radius()
	for i in 3:
		var h := StaticBody3D.new()
		h.add_to_group("handle")
		h.collision_layer = HANDLE_LAYER
		h.collision_mask = 0
		h.set_meta("kind", "rotate")
		h.set_meta("axis", i)
		h.set_meta("base_col", GIZ_COLS[i])
		# sichtbarer Ring (Torus liegt in XZ-Ebene = Achse Y; für X/Z entsprechend kippen)
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.1
		tm.outer_radius = r + 0.1
		tm.rings = 56
		mi.mesh = tm
		mi.material_override = _gizmo_mat(GIZ_COLS[i])
		if i == 0:
			mi.rotation = Vector3(0, 0, PI * 0.5)     # Achse Y -> X
		elif i == 2:
			mi.rotation = Vector3(PI * 0.5, 0, 0)     # Achse Y -> Z
		h.add_child(mi)
		# Klick-Collider: ÜBERLAPPENDE Kugeln entlang des Rings (Torus hat keine Kollisionsform).
		# Anzahl skaliert mit dem Umfang, Radius > halber Abstand -> lückenlos klickbar.
		var segs := clampi(int(ceil(TAU * r / 0.34)), 24, 44)
		var cr := (TAU * r / float(segs)) * 0.62 + 0.07
		for k in segs:
			var a := TAU * float(k) / float(segs)
			var cs := CollisionShape3D.new()
			var ss := SphereShape3D.new()
			ss.radius = cr
			cs.shape = ss
			var on_ring := Vector3(cos(a), 0.0, sin(a)) * r   # Ringpunkt in XZ (Achse Y)
			if i == 0:
				on_ring = Vector3(0.0, cos(a), sin(a)) * r    # Achse X -> Ring in YZ
			elif i == 2:
				on_ring = Vector3(cos(a), sin(a), 0.0) * r    # Achse Z -> Ring in XY
			cs.position = on_ring
			h.add_child(cs)
		_gizmo_root.add_child(h)
		_handles.append(h)


# Radius der Bewegen-/Drehen-Griffe aus der aktuellen Teilgröße.
func _gizmo_radius() -> float:
	var p := PartCatalog.get_part(selected_part.get_meta("part_id"))
	var half: Vector3 = PartCatalog.col_size(p) * selected_part.get_meta("pscale", Vector3.ONE) * 0.5
	return maxf(maxf(half.x, half.y), half.z) + RING_MARGIN


# Griffe an die (skalierten) Flächen/Achsen setzen (Würfel an Flächenmitte, Pfeile außerhalb).
func _update_handles() -> void:
	if selected_part == null:
		return
	var p := PartCatalog.get_part(selected_part.get_meta("part_id"))
	var bs: Vector3 = PartCatalog.col_size(p)
	var psc: Vector3 = selected_part.get_meta("pscale", Vector3.ONE)
	var off: Vector3 = PartCatalog.col_offset(p) * psc
	var half_v := bs * psc * 0.5
	var halves := [half_v.x, half_v.y, half_v.z]
	var radius := maxf(maxf(half_v.x, half_v.y), half_v.z) + RING_MARGIN
	# Halter ans Hüllenzentrum. Bewegen: Identitäts-Basis (global zur Welt). Drehen: Teil-Basis
	# -> die Ringe drehen mit dem Objekt mit (lokal ausgerichtet).
	if is_instance_valid(_gizmo_root):
		var giz_basis: Basis = selected_part.global_transform.basis if gizmo_mode == GIZ_ROTATE else Basis()
		_gizmo_root.global_transform = Transform3D(giz_basis, selected_part.global_transform * off)
	for h in _handles:
		var i: int = h.get_meta("axis")
		var kind: String = h.get_meta("kind", "scale")
		if kind == "move":
			h.position = _axis_vec(i) * radius        # Welt-Achse, relativ zum Welt-Halter
		elif kind == "rotate":
			h.position = Vector3.ZERO                 # Ring um das Zentrum
		elif kind == "ends":
			# 4 Enden-Vierecke: X-Würfel seitlich (+X), Y-Würfel oben (+Y), je am ±Z-Endquerschnitt.
			# Rückt mit der aktuellen Dicke dieses Endes/dieser Achse nach außen (direktes Feedback).
			var es: float = h.get_meta("sign")
			var ekey := _ends_key(es, i)
			var et: float = selected_part.get_meta(ekey, 1.0)
			if i == 0:
				h.position = off + Vector3(float(halves[0]) * et + 0.4, 0.0, es * float(halves[2]))
			else:
				h.position = off + Vector3(0.0, float(halves[1]) * et + 0.4, es * float(halves[2]))
		elif kind == "shift":
			# sitzt am Mittelpunkt der jeweiligen Stirnflaeche, wandert mit dem Versatz
			# mit, und die beiden Achsen-Zylinder stehen versetzt nebeneinander
			var ss: float = h.get_meta("sign")
			var sv: Vector2 = _end_shift(selected_part, ss)
			var basis_pos := off + Vector3(sv.x * bs.x * psc.x, sv.y * bs.y * psc.y,
				ss * (float(halves[2]) + 0.22))
			if i == 0:
				basis_pos += Vector3(float(halves[0]) + 0.55, 0.0, 0.0)
			else:
				basis_pos += Vector3(0.0, float(halves[1]) + 0.55, 0.0)
			h.position = basis_pos
		elif kind == "round":
			var ci: int = h.get_meta("corner", 0)
			var e := Vector3(1.0 if (ci & 1) != 0 else -1.0,
				1.0 if (ci & 2) != 0 else -1.0,
				1.0 if (ci & 4) != 0 else -1.0)
			# Griff sitzt AUF der Ecke und wandert mit der Rundung nach innen
			var rr: float = _block_r(selected_part)[ci]
			var schrumpf: float = minf(minf(half_v.x, half_v.y), half_v.z) * rr * 0.55
			h.position = off + Vector3(e.x * (half_v.x - schrumpf),
				e.y * (half_v.y - schrumpf), e.z * (half_v.z - schrumpf))
		elif kind == "leg":
			# sitzt unter dem Reifen und wandert beim Ausfahren mit
			var ext: float = PartCatalog.gear_ext(p, selected_part.get_meta("gear_len", 1.0))
			h.position = off + Vector3(0.0, -(float(halves[1]) + ext * psc.y + 0.4), 0.0)
		else:  # scale: am Teil (lokal), an der Flächenmitte
			var s: float = h.get_meta("sign")
			h.position = off + _axis_vec(i) * (s * (float(halves[i]) + 0.45))


# --- Transform-Interaktion -------------------------------------------------
func _transform_left_press() -> void:
	# 1) Griff getroffen -> Resize
	var hh := _raycast_mouse(HANDLE_LAYER)
	if not hh.is_empty():
		var hc = hh.get("collider")
		if hc and hc.is_in_group("handle"):
			_begin_handle_drag(hc)
			return
	# 2) Teil getroffen -> auswählen + verschieben
	var part := _pick_part_at_mouse()
	if part != null:
		if part != selected_part:
			_select_part(part)
		# Body ziehen = frei verschieben (nur im Bewegen-Modus). Drehen/Skalieren laufen über die Griffe.
		if gizmo_mode == GIZ_MOVE:
			_begin_move()
		return
	# 3) leerer Raum -> abwählen + Kamera drehen
	_deselect()
	_left_orbit = true


# Winkel des Maus-Strahls in der Ring-Ebene (um die Drehachse) — für den Ring-Drag.
func _ring_angle() -> float:
	if camera == null:
		return _rot_a0
	var mp := get_viewport().get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	var plane := Plane(_rot_axis_w, _rot_center.dot(_rot_axis_w))
	var hit = plane.intersects_ray(ro, rd)
	if hit == null:
		return _rot_a0
	var rel: Vector3 = (hit as Vector3) - _rot_center
	return atan2(rel.dot(_rot_v), rel.dot(_rot_u))


# Gizmo-Modus setzen (0=Bewegen 1=Drehen 2=Skalieren 3=Enden) und Griffe neu aufbauen.
func set_gizmo_mode(m: int) -> void:
	gizmo_mode = clampi(m, 0, 4)
	# Enden-Modi nur für Rumpfsegmente mit zwei formbaren Enden (biends).
	if (gizmo_mode == GIZ_ENDS or gizmo_mode == GIZ_SHIFT) and selected_part != null \
			and not PartCatalog.get_part(selected_part.get_meta("part_id")).get("biends", false):
		gizmo_mode = GIZ_SCALE
	if selected_part != null:
		_build_handles()
		_emit_selection()

func _begin_handle_drag(handle: Node3D) -> void:
	_drag_handle = handle
	_moving_sel = false
	_rotating = false
	_drag_kind = handle.get_meta("kind", "scale")
	_drag_axis_i = handle.get_meta("axis")
	_edit_xf0 = selected_part.transform
	_edit_sc0 = selected_part.get_meta("pscale", Vector3.ONE)
	if _drag_kind == "rotate":
		# Ring ziehen -> um die LOKALE Teil-Achse drehen (Ringe sind am Teil ausgerichtet, drehen mit).
		_rot_axis_w = (selected_part.global_transform.basis * _axis_vec(_drag_axis_i)).normalized()
		_rot_center = _gizmo_root.global_position
		_rot_b0 = selected_part.transform.basis
		_rot_u = _rot_axis_w.cross(Vector3.UP)
		if _rot_u.length() < 0.1:
			_rot_u = _rot_axis_w.cross(Vector3.RIGHT)
		_rot_u = _rot_u.normalized()
		_rot_v = _rot_axis_w.cross(_rot_u).normalized()
		_rot_a0 = _ring_angle()
		return
	if _drag_kind == "shift":
		# NUR entlang der eigenen Achse ziehen (0 = links/rechts, 1 = hoch/runter)
		_drag_sign = handle.get_meta("sign")
		_drag_axis_i = handle.get_meta("axis")
		_drag_shift0 = _end_shift(selected_part, _drag_sign)
		_drag_axis_w = (selected_part.global_transform.basis
			* _axis_vec(_drag_axis_i)).normalized()
		_drag_origin0 = handle.global_position
		_drag_t0 = _ray_axis_t(_drag_origin0, _drag_axis_w)
		_capture_end_kids(_drag_sign)   # was an DIESEM Ende haengt, wandert mit
		return
	if _drag_kind == "round":
		# entlang der RAUMDIAGONALE durch diese Ecke ziehen: nach innen = runder
		_drag_corner = handle.get_meta("corner", 0)
		var bp := PartCatalog.get_part(selected_part.get_meta("part_id"))
		var bpsc: Vector3 = selected_part.get_meta("pscale", Vector3.ONE)
		var bh: Vector3 = PartCatalog.col_size(bp) * bpsc * 0.5
		_drag_half = maxf(minf(minf(bh.x, bh.y), bh.z), 0.12)
		_drag_taper0 = _block_r(selected_part)[_drag_corner]
		var e := Vector3(1.0 if (_drag_corner & 1) != 0 else -1.0,
			1.0 if (_drag_corner & 2) != 0 else -1.0,
			1.0 if (_drag_corner & 4) != 0 else -1.0)
		_drag_axis_w = (selected_part.global_transform.basis * e).normalized()
		_drag_origin0 = handle.global_position
		_drag_t0 = _ray_axis_t(_drag_origin0, _drag_axis_w)
		return
	if _drag_kind == "leg":
		# entlang der LOKALEN Y-Achse ziehen (nach unten = laenger)
		var gp := PartCatalog.get_part(selected_part.get_meta("part_id"))
		_drag_half = maxf(PartCatalog.gear_leg_len(gp), 0.15)
		_drag_taper0 = selected_part.get_meta("gear_len", 1.0)
		_drag_axis_w = (selected_part.global_transform.basis * Vector3.UP).normalized()
		_drag_origin0 = handle.global_position
		_drag_t0 = _ray_axis_t(_drag_origin0, _drag_axis_w)
		return
	if _drag_kind == "ends":
		# Enden-Drag wie ein Scale-Würfel: X-Würfel entlang +X, Y-Würfel entlang +Y ziehen.
		# Nach AUSSEN ziehen -> dieses Ende in DIESER Achse dicker; nach INNEN -> dünner.
		_drag_sign = handle.get_meta("sign")
		_drag_axis_i = handle.get_meta("axis")              # 0 = X (Breite), 1 = Y (Höhe)
		var ep := PartCatalog.get_part(selected_part.get_meta("part_id"))
		var epsc: Vector3 = selected_part.get_meta("pscale", Vector3.ONE)
		var ehalf: Vector3 = PartCatalog.col_size(ep) * epsc * 0.5
		_drag_half = maxf(ehalf.x if _drag_axis_i == 0 else ehalf.y, 0.3)     # Sensitivität ~ diese Achse
		_drag_taper0 = selected_part.get_meta(_ends_key(_drag_sign, _drag_axis_i), 1.0)
		_drag_axis_w = (selected_part.global_transform.basis * _axis_vec(_drag_axis_i)).normalized()  # auswärts +X/+Y
		_drag_origin0 = handle.global_position
		_drag_t0 = _ray_axis_t(_drag_origin0, _drag_axis_w)
		return
	_drag_sign = handle.get_meta("sign")
	_drag_scale0 = selected_part.get_meta("pscale", Vector3.ONE)
	_drag_origin0 = selected_part.position
	if _drag_kind == "move":
		_capture_move_kids()   # Anbauten wandern auch beim Pfeil-Ziehen mit
		_drag_axis_w = _axis_vec(_drag_axis_i) * _drag_sign   # WELT-Achse (global, nicht lokal)
	else:  # scale -> lokale Teil-Achse strecken
		_drag_axis_w = (selected_part.global_transform.basis * _axis_vec(_drag_axis_i)).normalized() * _drag_sign
	_drag_t0 = _ray_axis_t(_drag_origin0, _drag_axis_w)


# Auswärtiger TEILBAUM des gewählten Teils: alles, was NUR über dieses Teil am
# Cockpit hängt (gleiche Logik wie der Verbindungs-Baum beim Flügelbruch) —
# wandert beim Verschieben MIT. Alt-Taste gedrückt = nur das Teil allein.
func _capture_move_kids() -> void:
	_move_kids = []
	if selected_part == null:
		return
	_move_sel_p0 = selected_part.position
	if Input.is_key_pressed(KEY_ALT) or selected_part.get_meta("is_root", false):
		return
	var parts: Array = []
	var root: Node3D = null
	for c in design_root.get_children():
		if c.is_in_group("part"):
			parts.append(c)
			if c.get_meta("is_root", false):
				root = c
	if root == null:
		return
	var boxes := {}
	for pp in parts:
		boxes[pp] = _part_world_aabb(pp).grow(0.12)
	# 1) Was ist OHNE Weg durch das gewählte Teil vom Cockpit erreichbar?
	var reach := {selected_part: true, root: true}
	var queue: Array = [root]
	while not queue.is_empty():
		var cur = queue.pop_back()
		for o in parts:
			if not reach.has(o) and boxes[cur].intersects(boxes[o]):
				reach[o] = true
				queue.append(o)
	# 2) Auswärts vom gewählten Teil: alles, was nur über IHN dranhängt
	var sub := {}
	queue = [selected_part]
	while not queue.is_empty():
		var cur = queue.pop_back()
		for o in parts:
			if not reach.has(o) and not sub.has(o) and boxes[cur].intersects(boxes[o]):
				sub[o] = true
				queue.append(o)
	for o in sub:
		_move_kids.append({"n": o, "p0": (o as Node3D).position})


# Teile, die am angegebenen ENDE des gewaehlten Teils haengen (-1 = vorne/-Z, +1 = hinten).
# Basis ist dieselbe BFS wie beim Verschieben und beim Fluegelbruch: erst alles, was OHNE
# Weg ueber das gewaehlte Teil vom Cockpit erreichbar ist, dann der Rest auswaerts. Aus dem
# wird nur behalten, was auf der Seite DIESES Endes liegt.
func _capture_end_kids(seite: float) -> void:
	_move_kids = []
	if selected_part == null:
		return
	var parts: Array = []
	var root: Node3D = null
	for c in design_root.get_children():
		if c.is_in_group("part"):
			parts.append(c)
			if c.get_meta("is_root", false):
				root = c
	if root == null or root == selected_part:
		return
	var boxes := {}
	for pp in parts:
		boxes[pp] = _part_world_aabb(pp).grow(0.12)
	var reach := {selected_part: true, root: true}
	var queue: Array = [root]
	while not queue.is_empty():
		var cur = queue.pop_back()
		for o in parts:
			if not reach.has(o) and boxes[cur].intersects(boxes[o]):
				reach[o] = true
				queue.append(o)
	var sub := {}
	queue = [selected_part]
	while not queue.is_empty():
		var cur2 = queue.pop_back()
		for o in parts:
			if not reach.has(o) and not sub.has(o) and boxes[cur2].intersects(boxes[o]):
				sub[o] = true
				queue.append(o)
	# Seite bestimmen: Lage des Nachbarn im LOKALEN System des gewaehlten Teils
	var inv := selected_part.global_transform.affine_inverse()
	for o in sub:
		var lz: float = (inv * (o as Node3D).global_position).z
		if signf(lz) == signf(seite) or absf(lz) < 0.05:
			_move_kids.append({"n": o, "p0": (o as Node3D).position})


func _begin_move() -> void:
	_moving_sel = true
	_drag_handle = null
	_edit_xf0 = selected_part.transform
	_edit_sc0 = selected_part.get_meta("pscale", Vector3.ONE)
	_capture_move_kids()
	var n := -camera.global_transform.basis.z      # Kamera-Blickrichtung
	var o := selected_part.global_position
	_move_plane = Plane(n, o.dot(n))
	_move_grab = _plane_ray() - o


func _update_transform_drag() -> void:
	if selected_part == null:
		return
	if _drag_handle != null and _drag_kind == "move":
		# Pfeil ziehen -> entlang der Achse verschieben (Gegenrichtung durch Zurückziehen).
		var t := _ray_axis_t(_drag_origin0, _drag_axis_w)
		var origin := _drag_origin0 + _drag_axis_w * (t - _drag_t0)
		origin = _snap_move(selected_part, origin, _drag_axis_i)   # Raster nur auf der Zieh-Achse
		# Pfeil-Zug: NUR in Fahrtrichtung (der gezogenen Achse) andocken — die anderen Achsen
		# bleiben unangetastet (kein seitliches Wegspringen).
		origin = _snap_to_neighbors(selected_part, origin, _drag_axis_i)
		_apply_sel_transform(selected_part.transform.basis, origin, _drag_scale0)
	elif _drag_handle != null and _drag_kind == "rotate":
		# Ring ziehen -> um die WELT-Achse drehen (Winkel aus der Maus in der Ringebene)
		var a := _ring_angle()
		var dreh := a - _rot_a0
		if Input.is_key_pressed(KEY_SHIFT):
			# SHIFT = 45-Grad-Raster. Gerastert wird die AENDERUNG gegenueber dem Griff-
			# Anfang (nicht die absolute Lage): so springt ein schon schraeg stehendes Teil
			# beim Anfassen nicht sofort weg, und aus der Grundstellung heraus landet man
			# exakt auf 45/90/135 Grad. Gleiche Bedeutung wie beim Skalieren, wo SHIFT
			# ebenfalls "regelmaessig" heisst.
			dreh = roundf(dreh / (PI * 0.25)) * (PI * 0.25)
		var nb := (Basis(_rot_axis_w, dreh) * _rot_b0).orthonormalized()
		_apply_sel_transform(nb, selected_part.position, selected_part.get_meta("pscale", Vector3.ONE))
	elif _drag_handle != null and _drag_kind == "shift":
		# Mausweg auf DIESER Achse; die andere Komponente bleibt unangetastet.
		var tref: float = _ray_axis_t(_drag_origin0, _drag_axis_w)
		var weg: float = tref - _drag_t0
		var sp := PartCatalog.get_part(selected_part.get_meta("part_id"))
		var gr: Vector3 = PartCatalog.col_size(sp)
		var neu := _drag_shift0
		if _drag_axis_i == 0:
			neu.x = clampf(_drag_shift0.x + weg / maxf(gr.x, 0.05), -SHIFT_MAX, SHIFT_MAX)
		else:
			neu.y = clampf(_drag_shift0.y + weg / maxf(gr.y, 0.05), -SHIFT_MAX, SHIFT_MAX)
		selected_part.set_meta("shift_front" if _drag_sign < 0.0 else "shift_back", neu)
		var ssc: Vector3 = selected_part.get_meta("pscale", Vector3.ONE)
		_rebuild_visual(selected_part)
		_apply_part_scale(selected_part, ssc)
		_sync_mirror_shift(selected_part, ssc)
		# Was an diesem Ende haengt, um DENSELBEN Weg mitnehmen — sonst bleibt an der
		# Naht genau der Versatz als Stufe stehen.
		var d := neu - _drag_shift0
		var welt: Vector3 = selected_part.transform.basis * Vector3(d.x * gr.x * ssc.x,
			d.y * gr.y * ssc.y, 0.0)
		for k in _move_kids:
			var kn = k["n"]
			if is_instance_valid(kn):
				(kn as Node3D).position = (k["p0"] as Vector3) + welt
				_sync_mirror(kn, (kn as Node3D).get_meta("pscale", Vector3.ONE))
		_update_handles()
		_notify_changed()
	elif _drag_handle != null and _drag_kind == "round":
		# Mausweg auf der Ecken-Diagonale -> Rundungsgrad 0..1 (feste Spanne).
		# SHIFT = ALLE acht Ecken zugleich, ohne SHIFT nur die gezogene.
		var rt := _ray_axis_t(_drag_origin0, _drag_axis_w)
		var wert: float = clampf(float(_drag_taper0) + (_drag_t0 - rt) / _drag_half,
			0.0, 1.0)
		var rad: PackedFloat32Array = _block_r(selected_part)
		if Input.is_key_pressed(KEY_SHIFT):
			for i in 8:
				rad[i] = wert
		else:
			rad[_drag_corner] = wert
		selected_part.set_meta("block_r", rad)
		# Skalierung von JETZT einbacken: damit sind die Kanten in der aktuellen (evtl.
		# gestreckten) Form gleich gross. Spaeteres Skalieren streckt sie dann mit.
		var bsc: Vector3 = selected_part.get_meta("pscale", Vector3.ONE)
		selected_part.set_meta("block_sc", bsc)
		_rebuild_visual(selected_part)
		_apply_part_scale(selected_part, bsc)
		_sync_mirror_block(selected_part, bsc)
		_update_handles()
		_notify_changed()
	elif _drag_handle != null and _drag_kind == "leg":
		# Mausweg entlang -Y in Beinlaengen umrechnen; die Spanne ist FEST (kein Stelzen).
		var lt := _ray_axis_t(_drag_origin0, _drag_axis_w)
		var neu: float = clampf(float(_drag_taper0) - (lt - _drag_t0) / _drag_half,
			PartCatalog.GEAR_LEN_MIN, PartCatalog.GEAR_LEN_MAX)
		selected_part.set_meta("gear_len", neu)
		var lsc: Vector3 = selected_part.get_meta("pscale", Vector3.ONE)
		_rebuild_visual(selected_part)
		_apply_part_scale(selected_part, lsc)   # Pickbox auf das neue Bein ziehen
		_sync_mirror(selected_part, lsc)        # gespiegeltes Rad faehrt mit aus
		_update_handles()
		_notify_changed()
	elif _drag_handle != null and _drag_kind == "ends":
		# Enden-Würfel ziehen: außen = dieses Ende in X/Y dicker, innen = dünner.
		var te := _ray_axis_t(_drag_origin0, _drag_axis_w)
		var new_t: float = clampf(_drag_taper0 + (te - _drag_t0) / _drag_half, 0.25, 2.5)
		var ekey := _ends_key(_drag_sign, _drag_axis_i)
		# manuell geformt -> Auto-Taper fasst dieses Ende nicht mehr an
		var ukey := ("taper_front" if ekey.begins_with("taper_front") else "taper") + "_user"
		selected_part.set_meta(ekey, new_t)
		selected_part.set_meta(ukey, true)
		_rebuild_visual(selected_part)
		if selected_part.has_meta("mirror"):
			var mm = selected_part.get_meta("mirror")
			if is_instance_valid(mm):
				mm.set_meta(ekey, new_t)
				mm.set_meta(ukey, true)
				_rebuild_visual(mm)
		_update_handles()
		_emit_selection()
		_notify_changed()
	elif _drag_handle != null:
		var p := PartCatalog.get_part(selected_part.get_meta("part_id"))
		var bs: Vector3 = PartCatalog.col_size(p)
		var i := _drag_axis_i
		var base_i: float = [bs.x, bs.y, bs.z][i]
		var s0: float = [_drag_scale0.x, _drag_scale0.y, _drag_scale0.z][i]
		var half0: float = base_i * s0 * 0.5
		var t := _ray_axis_t(_drag_origin0, _drag_axis_w)
		var d := t - _drag_t0                                        # Mausweg entlang der Achse
		# Die GEZOGENE Fläche folgt der Maus EXAKT 1:1 (kein Raster, kein Magnet) -> der Würfel
		# klebt am Cursor. X/Y skalieren SYMMETRISCH (Zentrum fix, beide Seiten wachsen gleich),
		# Z (Länge) verankert (Gegenfläche fix). Bei verankert wandert das Zentrum mit, daher
		# ändert sich die Halb-Größe nur um den HALBEN Mausweg (sonst liefe die Fläche 2× voraus).
		var symmetric := (i != 2)
		var new_half: float
		var origin: Vector3
		if symmetric:
			new_half = maxf(half0 + d, base_i * 0.125)
			origin = _drag_origin0
		else:
			new_half = maxf(half0 + d * 0.5, base_i * 0.125)
			origin = _drag_origin0 + _drag_axis_w * (new_half - half0)
		var new_s: float = clampf(new_half * 2.0 / base_i, 0.25, 6.0)
		var sc := _drag_scale0
		if Input.is_key_pressed(KEY_SHIFT):
			# Shift = UNIFORM skalieren: alle 3 Achsen mit demselben Verhältnis wie die gezogene
			var ratio: float = new_s / maxf(s0, 0.001)
			sc = Vector3(clampf(_drag_scale0.x * ratio, 0.25, 6.0),
				clampf(_drag_scale0.y * ratio, 0.25, 6.0),
				clampf(_drag_scale0.z * ratio, 0.25, 6.0))
		elif (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)) and i != 2:
			# Strg + X/Y-Griff = Querschnitt: X UND Y zusammen skalieren (Länge Z bleibt)
			var ratio2: float = new_s / maxf(s0, 0.001)
			sc.x = clampf(_drag_scale0.x * ratio2, 0.25, 6.0)
			sc.y = clampf(_drag_scale0.y * ratio2, 0.25, 6.0)
		elif i == 0:
			sc.x = new_s
		elif i == 1:
			sc.y = new_s
		else:
			sc.z = new_s
		_apply_sel_transform(selected_part.transform.basis, origin, sc)
		_update_handles()   # gezogenen Würfel dem Cursor nachführen -> klebt an der Maus
	elif _moving_sel:
		# 1) Zeigt die Maus auf ein ANDERES Teil -> bündig auf DESSEN Fläche snappen
		#    (wie beim Setzen aus der Palette: das Teil dockt da an, wo man hinzeigt).
		var hov: Variant = _snap_move_to_hovered(selected_part) if snap_enabled else null
		var newpos: Vector3
		if hov != null:
			newpos = hov
		else:
			# 2) freier Raum: bisheriges Verhalten (Ebene + Raster + Magnet)
			newpos = _plane_ray() - _move_grab
			newpos = _snap_move(selected_part, newpos)   # aufs Raster
			newpos = _snap_to_neighbors(selected_part, newpos)   # magnetisch bündig an Nachbar-Teile
		_apply_sel_transform(selected_part.transform.basis, newpos, selected_part.get_meta("pscale", Vector3.ONE))


# Wendet Basis/Origin/Skalierung auf das gewählte Teil an und hält die Symmetrie aktuell.
func _apply_sel_transform(new_basis: Basis, origin: Vector3, sc: Vector3) -> void:
	selected_part.transform = Transform3D(new_basis, origin)
	_apply_part_scale(selected_part, sc)
	_sync_mirror(selected_part, sc)
	# ANBAUTEN MITNEHMEN: der beim Move-Start eingesammelte Teilbaum folgt 1:1
	# dem Versatz (inkl. Spiegel-Sync je Anbau -> die Gegenseite zieht mit).
	if not _move_kids.is_empty():
		var off := origin - _move_sel_p0
		for k in _move_kids:
			var kn = k["n"]
			if is_instance_valid(kn):
				kn.position = k["p0"] + off
				_sync_mirror(kn, kn.get_meta("pscale", Vector3.ONE))
	_update_handles()
	_notify_changed()


# Spiegelteil dynamisch erzeugen/aktualisieren beim Verschieben/Drehen/Skalieren, damit der
# Symmetrie-Modus auch nachträglich greift (vorher nur beim Platzieren).
# Ab welchem |x| ein Teil gespiegelt wird. Flügel/Steuerflächen ragen nach außen -> schon knapp
# neben der Mitte. Rumpf-/Körperteile erst, wenn sie die Mittelachse NICHT mehr überlappen
# -> "in der Mitte platziert" = KEIN Spiegel (auch bei aktiver Symmetrie).
func _mirror_threshold(id: String, pscale: Vector3) -> float:
	var p := PartCatalog.get_part(id)
	if p.get("is_wing", false) or String(p.get("shape", "")) == "wing":
		return 0.15
	# schmale Mitte-Zone: nur wirklich zentrale Teile bleiben einzeln, knapp daneben wird gespiegelt
	return maxf(PartCatalog.col_size(p).x * pscale.x * 0.3, 0.15)


func _sync_mirror(part: Node3D, sc: Vector3) -> void:
	var m = part.get_meta("mirror") if part.has_meta("mirror") else null
	var m_valid := is_instance_valid(m)
	var want: bool = symmetry and not bool(part.get_meta("is_root", false)) \
		and absf(part.position.x) > _mirror_threshold(part.get_meta("part_id"), sc)
	if want:
		if not m_valid:
			# Symmetrie an, Teil außermittig, aber noch kein Spiegel -> neuen erzeugen
			m = _make_part(part.get_meta("part_id"), _mirror_xform(part.transform),
				part.get_meta("color", Color(0, 0, 0, 0)), sc,
				part.get_meta("taper", -1.0), part.get_meta("taper_front", -1.0))
			part.set_meta("mirror", m)
			m.set_meta("mirror", part)
			m.set_meta("thrust_reverse", part.get_meta("thrust_reverse", false))
		else:
			# vorhandenen Spiegel mitziehen (folgt auch bei ausgeschalteter Symmetrie)
			m.transform = _mirror_xform(part.transform)
			_apply_part_scale(m, sc)
		_sync_mirror_gear(part, m, sc)
		if part.has_meta("block_r"):
			_sync_mirror_block(part, sc)
		# Mittelspalt-Füllung beider Hälften an die neue Position anpassen
		_update_wing_fill(part)
		_update_wing_fill(m)
	elif m_valid and symmetry and String(PartCatalog.get_part(part.get_meta("part_id")).get("shape", "")) == "wing":
		# Symmetrie AN + zentriertes Flügel-Paar (zwei in der Mitte zusammenstoßende
		# Hälften = durchgehender Flügel): NICHT entfernen, sondern beide Hälften gleich
		# skalieren/mitziehen -> die Symmetrie greift auch beim mittigen Flügel.
		m.transform = _mirror_xform(part.transform)
		_apply_part_scale(m, sc)
		_update_wing_fill(part)
		_update_wing_fill(m)
	elif m_valid:
		# Symmetrie AUS (wie bisher) oder symmetrisches Teil (Box/Zylinder) mittig:
		# doppelten/deckungsgleichen Spiegel entfernen.
		part.remove_meta("mirror")
		m.free()
		_update_wing_fill(part)


# Versatz eines Rumpfendes (-1 = vorne/-Z, +1 = hinten/+Z), in Teil-Einheiten.
func _end_shift(part: Node3D, sign: float) -> Vector2:
	return part.get_meta("shift_front" if sign < 0.0 else "shift_back", Vector2.ZERO)


# Schnittpunkt des Maus-Strahls mit der Ebene durch `punkt` senkrecht zu `normale`.
func _ray_ebene(punkt: Vector3, normale: Vector3) -> Vector3:
	if camera == null:
		return punkt
	var mp := get_viewport().get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	var d := normale.dot(rd)
	if absf(d) < 0.00001:
		return punkt
	return ro + rd * (normale.dot(punkt - ro) / d)


# Versatz auf den Spiegel uebertragen — X gespiegelt, Y gleich.
func _sync_mirror_shift(part: Node3D, sc: Vector3) -> void:
	var m = part.get_meta("mirror") if part.has_meta("mirror") else null
	if m == null or not is_instance_valid(m):
		return
	for k in ["shift_front", "shift_back"]:
		var v: Vector2 = part.get_meta(k, Vector2.ZERO)
		m.set_meta(k, Vector2(-v.x, v.y))
	_rebuild_visual(m)
	_apply_part_scale(m, sc)


# Eckrundungen des Klotzes (8 Werte 0..1); fehlt das Meta, alle scharf.
func _block_r(part: Node3D) -> PackedFloat32Array:
	if part.has_meta("block_r"):
		var a: PackedFloat32Array = part.get_meta("block_r")
		if a.size() == 8:
			return a
	return PartCatalog.block_radien_neu()


# Rundung auf den Spiegel uebertragen — sonst haette die gespiegelte Haelfte scharfe Ecken.
func _sync_mirror_block(part: Node3D, sc: Vector3) -> void:
	var m = part.get_meta("mirror") if part.has_meta("mirror") else null
	if m == null or not is_instance_valid(m):
		return
	m.set_meta("block_r", _block_r(part).duplicate())
	m.set_meta("block_sc", part.get_meta("block_sc", Vector3.ONE))
	_rebuild_visual(m)
	_apply_part_scale(m, sc)


# Ausgefahrenes Fahrwerksbein auf den Spiegel uebertragen. Ohne das blieb das
# gespiegelte Rad auf Originallaenge stehen — das Flugzeug stand schief.
func _sync_mirror_gear(part: Node3D, m: Node3D, sc: Vector3) -> void:
	if m == null or not is_instance_valid(m):
		return
	if String(PartCatalog.get_part(part.get_meta("part_id")).get("category", "")) 			!= PartCatalog.CAT_GEAR:
		return
	var gl: float = part.get_meta("gear_len", 1.0)
	if absf(float(m.get_meta("gear_len", 1.0)) - gl) < 0.0001:
		return
	m.set_meta("gear_len", gl)
	_rebuild_visual(m)
	_apply_part_scale(m, sc)


# Parameter t entlang der Achse (lo + t*ld), am nächsten zum Maus-Strahl.
func _ray_axis_t(lo: Vector3, ld: Vector3) -> float:
	var mp := get_viewport().get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	var r := lo - ro
	var b := ld.dot(rd)
	var d := ld.dot(r)
	var e := rd.dot(r)
	var denom := 1.0 - b * b
	if absf(denom) < 1e-6:
		return 0.0
	return (b * e - d) / denom


# Schnittpunkt des Maus-Strahls mit der Verschiebe-Ebene.
func _plane_ray() -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	var hit = _move_plane.intersects_ray(ro, rd)
	return hit if hit != null else selected_part.global_position


# Verschieben mit Blick aufs Ziel: zeigt die Maus auf ein anderes Teil, liefert das
# den Ursprung, mit dem das gezogene Teil BÜNDIG auf der getroffenen Fläche sitzt
# (Stützweite = Projektion seiner ORIENTIERTEN, skalierten Halbausdehnung auf die
# Flächennormale). null = Maus zeigt ins Leere/aufs eigene Teil -> Fallback Ebene.
func _snap_move_to_hovered(part: Node3D) -> Variant:
	var ex: Array[RID] = []
	var mirror = part.get_meta("mirror") if part.has_meta("mirror") else null
	var ex_nodes: Array = [part, mirror]
	for k in _move_kids:
		ex_nodes.append(k["n"])
		var km = k["n"].get_meta("mirror") if (is_instance_valid(k["n"]) and k["n"].has_meta("mirror")) else null
		ex_nodes.append(km)
	for n in ex_nodes:
		if n != null and is_instance_valid(n):
			for c in n.get_children():
				if c is CollisionObject3D:
					ex.append((c as CollisionObject3D).get_rid())
	var hit := _raycast_mouse(BUILD_LAYER, ex)
	if hit.is_empty():
		return null
	var tgt := _part_from_hit(hit)
	if tgt == null or tgt == part or tgt == mirror:
		return null
	var n3: Vector3 = hit["normal"].normalized()
	var surface: Vector3 = hit["position"]
	var p := PartCatalog.get_part(part.get_meta("part_id"))
	var sc: Vector3 = part.get_meta("pscale", Vector3.ONE)
	# Flügel & Co. (orient_normal): Ursprung sitzt an der Wurzelfläche -> wie beim
	# Setzen aus der Palette direkt AUF die Oberfläche legen (Orientierung bleibt).
	if p.get("orient_normal", false):
		return _snap_tangential(surface - n3 * 0.04, n3, 0.5)
	var he: Vector3 = PartCatalog.col_size(p) * sc * 0.5
	var b := part.transform.basis
	var support := absf(n3.dot(b.x)) * he.x + absf(n3.dot(b.y)) * he.y + absf(n3.dot(b.z)) * he.z
	var center := surface + n3 * support
	var origin := center - b * (PartCatalog.col_offset(p) * sc)
	return _snap_tangential(origin, n3, 0.25)


func _transform_release() -> void:
	# History nur, wenn sich wirklich was geändert hat (reiner Auswahl-Klick -> kein Undo-Müll).
	if (_drag_handle != null or _moving_sel or _rotating) and selected_part != null:
		var moved_sc: Vector3 = selected_part.get_meta("pscale", Vector3.ONE)
		var changed: bool = selected_part.transform != _edit_xf0 or moved_sc != _edit_sc0
		if _drag_handle != null and _drag_kind == "ends":
			var ekey := _ends_key(_drag_sign, _drag_axis_i)
			changed = changed or selected_part.get_meta(ekey, 1.0) != _drag_taper0
		if changed:
			_push_history()
			_notify_changed()
	_drag_handle = null
	_moving_sel = false
	_rotating = false
	_left_orbit = false
	_move_kids = []


# ---------------------------------------------------------------------------
# Platzierung
# ---------------------------------------------------------------------------
func set_brush(id: String) -> void:
	brush_id = id
	if id != "":
		erase_mode = false
		paint_mode = false
		_deselect()
	ghost_rot = 0
	_rebuild_ghost()


func set_erase_mode(b: bool) -> void:
	erase_mode = b
	if b:
		brush_id = ""
		paint_mode = false
		_deselect()
	_rebuild_ghost()


func set_paint_mode(b: bool) -> void:
	paint_mode = b
	if b:
		brush_id = ""
		erase_mode = false
		_deselect()
	_rebuild_ghost()


func set_paint_color(c: Color) -> void:
	paint_color = c
	paint_mode = true
	brush_id = ""
	erase_mode = false
	_deselect()
	_rebuild_ghost()


func set_symmetry(b: bool) -> void:
	symmetry = b
	_refresh_all_wing_fill()


# --- Lackieren --------------------------------------------------------------
func _paint_hovered(_hit: Dictionary) -> void:
	var part := _pick_part_at_mouse()   # smarter Pick: trifft auch eingebettete Teile
	if part == null:
		return
	_recolor(part, paint_color)
	if part.has_meta("mirror"):
		var m = part.get_meta("mirror")
		if is_instance_valid(m):
			_recolor(m, paint_color)
	_push_history()
	_notify_changed()


# --- Auswahl-Animation: pulsierender Fresnel-Glow + einmaliger Scan-Sweep ----
# Pro Mesh des gewählten Teils wird ein additives Overlay-Mesh (gleiche Geometrie,
# Kind des Originals -> folgt jeder Bewegung) mit Rim-Shader eingehängt. Beim
# Anwählen blitzt es auf (flash 1->0) und ein Scan-Band läuft von unten nach
# oben durchs Teil; danach bleibt ein sanftes Puls-Glimmen (TIME im Shader).
func _get_sel_glow_shader() -> Shader:
	if _sel_glow_shader == null:
		_sel_glow_shader = Shader.new()
		_sel_glow_shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec3 glow_col : source_color = vec3(0.35, 0.75, 1.0);
uniform float flash = 0.0;
uniform float sweep = -1.0;
uniform float ymin = 0.0;
uniform float ymax = 1.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	float puls = 0.5 + 0.5 * sin(TIME * 4.6);
	float a = fr * (0.30 + 0.30 * puls + flash * 1.7);
	if (sweep >= 0.0) {
		float band_y = mix(ymin, ymax, sweep);
		float band = 1.0 - smoothstep(0.0, 0.16, abs(wpos.y - band_y));
		a += band * (1.2 + flash);
	}
	ALBEDO = glow_col * a;
}
"""
	return _sel_glow_shader


func _apply_sel_glow(part: Node3D) -> void:
	_clear_sel_glow()
	if part == null:
		return
	var vis: Node = part.get_node_or_null("Visual")
	if vis == null:
		return
	var ab := _part_world_aabb(part)
	_sel_glow_mat = ShaderMaterial.new()
	_sel_glow_mat.shader = _get_sel_glow_shader()
	_sel_glow_mat.set_shader_parameter("ymin", ab.position.y - 0.05)
	_sel_glow_mat.set_shader_parameter("ymax", ab.end.y + 0.05)
	_sel_glow_mat.set_shader_parameter("flash", 1.0)
	_sel_glow_mat.set_shader_parameter("sweep", 0.0)
	_attach_glow(vis)
	_sel_glow_tween = create_tween()
	_sel_glow_tween.set_parallel(true)
	_sel_glow_tween.tween_property(_sel_glow_mat, "shader_parameter/flash", 0.0, 0.65) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_sel_glow_tween.tween_property(_sel_glow_mat, "shader_parameter/sweep", 1.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sel_glow_tween.chain().tween_callback(func() -> void:
		if _sel_glow_mat != null:
			_sel_glow_mat.set_shader_parameter("sweep", -1.0))


func _attach_glow(node: Node) -> void:
	for ch in node.get_children():
		_attach_glow(ch)
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var src := node as MeshInstance3D
		var ov := MeshInstance3D.new()
		ov.set_meta("sel_glow", true)   # vom Windkanal-Shader ausnehmen
		ov.mesh = src.mesh
		ov.material_override = _sel_glow_mat
		ov.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		src.add_child(ov)   # Kind mit Identitäts-Transform -> folgt 1:1
		_sel_glow_nodes.append(ov)


func _clear_sel_glow() -> void:
	if _sel_glow_tween != null and _sel_glow_tween.is_valid():
		_sel_glow_tween.kill()
	_sel_glow_tween = null
	for n in _sel_glow_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_sel_glow_nodes = []
	_sel_glow_mat = null


func _recolor(part: Node, c: Color) -> void:
	part.set_meta("color", c)
	_rebuild_visual(part)
	if part == selected_part:
		_apply_sel_glow(selected_part)   # Visual wurde neu gebaut -> Glow neu anhängen


# Visual aus den aktuellen Metadaten (Farbe + beide Taper-Enden + pscale) neu bauen.
func _rebuild_visual(part: Node) -> void:
	var vis := part.get_node_or_null("Visual")
	if vis:
		vis.free()
	var nv := PartCatalog.build_visual(PartCatalog.get_part(part.get_meta("part_id")),
		part.get_meta("color", Color(0, 0, 0, 0)),
		part.get_meta("taper", 1.0), part.get_meta("taper_front", 1.0),
		part.get_meta("taper_y", -1.0), part.get_meta("taper_front_y", -1.0),
		part.get_meta("shift_front", Vector2.ZERO), part.get_meta("shift_back", Vector2.ZERO))
	nv.name = "Visual"
	nv.scale = part.get_meta("pscale", Vector3.ONE)
	part.add_child(nv)
	var pdef := PartCatalog.get_part(part.get_meta("part_id"))
	PartCatalog.set_gear_length(nv, pdef, part.get_meta("gear_len", 1.0))
	if part.has_meta("block_r"):
		PartCatalog.set_block_rounding(nv, pdef, part.get_meta("block_r"),
			part.get_meta("block_sc", Vector3.ONE))
		nv.scale = PartCatalog.block_rest_scale(nv.scale,
			part.get_meta("block_sc", Vector3.ONE))


# --- Verjüngung (Taper): Enden des Rumpfes breiter/schmaler ----------------
# nudge_taper = hinteres (+Z) Ende; nudge_taper_front = vorderes (-Z) Ende.
func nudge_taper(factor: float) -> void:
	_apply_taper("taper", factor, false)

func nudge_taper_front(factor: float) -> void:
	_apply_taper("taper_front", factor, true)

func _apply_taper(meta_key: String, factor: float, front_only: bool) -> void:
	if selected_part == null:
		return
	var p := PartCatalog.get_part(selected_part.get_meta("part_id"))
	var ok: bool = p.get("biends", false) or (not front_only and p.get("taperable", false))
	if not ok:
		return
	var tp: float = clampf(selected_part.get_meta(meta_key, 1.0) * factor, 0.25, 2.5)
	var yk := meta_key + "_y"                          # Regler skaliert X UND Y gleichförmig
	selected_part.set_meta(meta_key, tp)
	selected_part.set_meta(yk, tp)
	selected_part.set_meta(meta_key + "_user", true)   # manuell geformt -> Auto-Taper aus
	_rebuild_visual(selected_part)
	if selected_part.has_meta("mirror"):
		var m = selected_part.get_meta("mirror")
		if is_instance_valid(m):
			m.set_meta(meta_key, tp)
			m.set_meta(yk, tp)
			m.set_meta(meta_key + "_user", true)
			_rebuild_visual(m)
	_emit_selection()
	_push_history()
	_notify_changed()


# --- Undo / Redo ------------------------------------------------------------
func _seed_history() -> void:
	_history = [get_design()]
	_hist_i = 0


func _push_history() -> void:
	if _suppress_history:
		return
	_history = _history.slice(0, _hist_i + 1)
	_history.append(get_design())
	_hist_i = _history.size() - 1
	if _history.size() > 40:
		_history.pop_front()
		_hist_i -= 1


func can_undo() -> bool:
	return _hist_i > 0


func can_redo() -> bool:
	return _hist_i < _history.size() - 1


func undo() -> void:
	if not can_undo():
		return
	_hist_i -= 1
	_apply_history()


func redo() -> void:
	if not can_redo():
		return
	_hist_i += 1
	_apply_history()


func _apply_history() -> void:
	_suppress_history = true
	load_design(_history[_hist_i].duplicate(true))
	_suppress_history = false


# --- Kamera zentrieren ------------------------------------------------------
func reset_camera() -> void:
	orbit_yaw = 0.7
	orbit_pitch = 0.4
	orbit_dist = 15.0
	orbit_focus = Vector3(0, 0, 0)
	_ortho_view = 0
	_update_camera()


# --- Windkanal-Ansicht: Pro-Teil-Widerstands-Heatmap + Luftströmung --------
func set_wind_tunnel(b: bool) -> void:
	wind_tunnel = b
	if b:
		_build_wind_tunnel()
	else:
		_clear_wind_tunnel()
	design_changed.emit(compute_stats())   # Statistik (Hotspot) sofort aktualisieren


func _build_wind_tunnel() -> void:
	_apply_drag_heatmap()
	if com_marker:
		com_marker.visible = false
	if col_marker:
		col_marker.visible = false
	if is_instance_valid(_tunnel_particles):
		return  # Strömung läuft schon (z. B. nur Heatmap neu)
	# Luftstrom-Linien (von vorne -Z über das Modell nach +Z)
	_tunnel_particles = CPUParticles3D.new()
	_tunnel_particles.amount = 280
	_tunnel_particles.lifetime = 2.2
	_tunnel_particles.preprocess = 1.5
	_tunnel_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_tunnel_particles.emission_box_extents = Vector3(7.0, 4.0, 0.05)
	_tunnel_particles.position = Vector3(0, 0, -11)
	_tunnel_particles.direction = Vector3(0, 0, 1)
	_tunnel_particles.spread = 0.0
	_tunnel_particles.gravity = Vector3.ZERO
	_tunnel_particles.initial_velocity_min = 11.0
	_tunnel_particles.initial_velocity_max = 11.0
	var streak := BoxMesh.new()
	streak.size = Vector3(0.04, 0.04, 0.8)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.55, 0.85, 1.0, 0.55)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = sm
	_tunnel_particles.mesh = streak
	design_root.add_child(_tunnel_particles)


# Färbt jedes Teil nach seinem ECHTEN Flug-Widerstand: grün (wenig) -> rot (viel).
# Der Wind kommt von vorne (-Z). Per Strahlengitter wird ermittelt, welche Fläche
# jedes Teil der Anströmung TATSÄCHLICH zuwendet — verdeckte Teile (im Windschatten
# hinter anderen) fangen keinen Wind und bleiben grün. Druck-Widerstand pro Teil =
# exponierte Stirnfläche × Formbeiwert. So leuchtet nur das wirklich störende,
# vorne-anliegende Teil rot, nicht ein Heckteil im Schatten.
func _apply_drag_heatmap() -> void:
	wind_worst = ""
	var parts: Array = []
	for child in design_root.get_children():
		if child.is_in_group("part"):
			parts.append(child)
	if parts.is_empty():
		return
	var space := get_viewport().get_world_3d().direct_space_state
	if space == null:
		return
	# 1) exponierte Fläche je Teil per Raycast aus -Z einsammeln
	var exposed := {}
	for pt in parts:
		exposed[pt] = 0.0
	var aabb := _model_aabb_world(parts)
	var w: float = maxf(aabb.size.x, 0.1)
	var h: float = maxf(aabb.size.y, 0.1)
	var nx: int = clampi(int(ceil(w / 0.2)), 6, 60)
	var ny: int = clampi(int(ceil(h / 0.2)), 4, 40)
	var cell: float = (w / float(nx)) * (h / float(ny))
	var z0: float = aabb.position.z - 3.0
	var z1: float = aabb.position.z + aabb.size.z + 3.0
	var q := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO)
	q.collision_mask = BUILD_LAYER
	q.collide_with_areas = false
	for i in nx:
		var x: float = aabb.position.x + (float(i) + 0.5) / float(nx) * w
		for j in ny:
			var y: float = aabb.position.y + (float(j) + 0.5) / float(ny) * h
			q.from = Vector3(x, y, z0)
			q.to = Vector3(x, y, z1)
			var hit := space.intersect_ray(q)     # erster Treffer = windzugewandt
			if hit.is_empty():
				continue
			var pt := _part_from_hit(hit)
			if pt != null and exposed.has(pt):
				exposed[pt] += cell
	# 2) Druckwiderstand = exponierte Fläche × Formbeiwert; stärkstes Teil + max. Exposition
	var drag := {}
	var max_d := 0.0
	var max_exp := 0.0
	for pt in parts:
		var cd: float = PartCatalog.part_cd(PartCatalog.get_part(pt.get_meta("part_id")))
		var dv: float = exposed[pt] * cd
		drag[pt] = dv
		max_exp = maxf(max_exp, exposed[pt])
		if dv > max_d:
			max_d = dv
			wind_worst = PartCatalog.get_part(pt.get_meta("part_id")).get("name", "")
	# 2b) Analyse-Report für die Statistik: CdA je TEILNAME (Spiegelpaare summiert) + Gesamt
	wind_total = 0.0
	var by_name := {}
	for pt in parts:
		wind_total += drag[pt]
		var nm: String = PartCatalog.get_part(pt.get_meta("part_id")).get("name", "?")
		by_name[nm] = by_name.get(nm, 0.0) + drag[pt]
	wind_report = []
	for nm in by_name:
		wind_report.append({"name": nm, "drag": by_name[nm]})
	wind_report.sort_custom(func(a, b): return a["drag"] > b["drag"])
	# 3) Per-Pixel-Shader: NUR die angeströmten FLÄCHEN (Normale gegen den +Z-Wind) werden
	#    eingefärbt (grün->rot je nach Teil-Widerstand), Seiten-/Leeflächen bleiben grau.
	#    Teile ganz im Windschatten -> komplett grau (heat = grau).
	var denom := maxf(max_d, 0.45)
	var wind_min := maxf(0.04, max_exp * 0.05)   # darunter = praktisch kein Wind
	var gray := Color(0.62, 0.65, 0.72)
	for pt in parts:
		var vis: Node = pt.get_node_or_null("Visual")
		if exposed[pt] < wind_min:
			_apply_wind_shader(vis, gray, 0.0)
		else:
			var frac := clampf(drag[pt] / denom, 0.0, 1.0)
			var glow := maxf(frac - 0.55, 0.0) * 2.2
			_apply_wind_shader(vis, _drag_color(frac), glow)
	design_changed.emit(compute_stats())   # Report/Hotspot in der Statistik aktualisieren


# Welt-AABB aller Teil-Kollisionsboxen (für das Strahlengitter).
func _model_aabb_world(parts: Array) -> AABB:
	var aabb := AABB()
	var first := true
	for pt in parts:
		var p := PartCatalog.get_part(pt.get_meta("part_id"))
		var ext: Vector3 = PartCatalog.col_size(p) * 0.5
		var off: Vector3 = PartCatalog.col_offset(p)
		var xf: Transform3D = pt.global_transform
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var corner: Vector3 = xf * (off + Vector3(sx * ext.x, sy * ext.y, sz * ext.z))
					if first:
						aabb = AABB(corner, Vector3.ZERO)
						first = false
					else:
						aabb = aabb.expand(corner)
	return aabb


func _drag_color(f: float) -> Color:
	if f < 0.5:
		return Color(0.18, 0.85, 0.30).lerp(Color(0.97, 0.86, 0.15), f * 2.0)
	return Color(0.97, 0.86, 0.15).lerp(Color(0.97, 0.16, 0.12), (f - 0.5) * 2.0)


# Shader, der NUR die angeströmten Flächen markiert: Weltnormale gegen den +Z-Wind
# -> frontale Flächen bekommen heat_color, Seiten-/Leeflächen bleiben base_color (grau).
# So wird die widerstandsauslösende OBERFLÄCHE markiert, nicht das ganze Teil.
func _get_wind_shader() -> Shader:
	if _wind_shader == null:
		_wind_shader = Shader.new()
		_wind_shader.code = "shader_type spatial;\n" \
			+ "render_mode unshaded, cull_disabled;\n" \
			+ "uniform vec3 heat_color : source_color = vec3(0.6, 0.6, 0.6);\n" \
			+ "uniform vec3 base_color : source_color = vec3(0.62, 0.65, 0.72);\n" \
			+ "uniform float glow = 0.0;\n" \
			+ "void fragment() {\n" \
			+ "	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);\n" \
			+ "	if (!FRONT_FACING) { wn = -wn; }\n" \
			+ "	float w = max(0.0, -wn.z);\n" \
			+ "	float blend = smoothstep(0.12, 0.55, w);\n" \
			+ "	ALBEDO = mix(base_color, heat_color, blend);\n" \
			+ "	EMISSION = heat_color * (blend * glow);\n" \
			+ "}\n"
	return _wind_shader


func _apply_wind_shader(node: Node, heat_color: Color, glow: float) -> void:
	if node == null or (node is MeshInstance3D and node.get_meta("sel_glow", false)):
		return
	for ch in node.get_children():
		_apply_wind_shader(ch, heat_color, glow)
	if node is MeshInstance3D:
		var m := ShaderMaterial.new()
		m.shader = _get_wind_shader()
		m.set_shader_parameter("heat_color", heat_color)
		m.set_shader_parameter("base_color", Color(0.62, 0.65, 0.72))
		m.set_shader_parameter("glow", glow)
		node.material_override = m


func _clear_wind_tunnel() -> void:
	if is_instance_valid(_tunnel_particles):
		_tunnel_particles.queue_free()
	_tunnel_particles = null
	wind_worst = ""
	wind_report = []
	wind_total = 0.0
	for child in design_root.get_children():
		if child.is_in_group("part"):
			_recolor(child, child.get_meta("color", Color(0, 0, 0, 0)))
	if com_marker:
		com_marker.visible = true
	if col_marker:                                  # COL-Marker ebenfalls wiederherstellen
		col_marker.visible = compute_stats().get("col_valid", false)
	_heatmap_dirty = false                          # Debounce-Flag sauber zurücksetzen


# Platziert ein Teil (mit Symmetrie, falls aktiv und außermittig)
func _place_id(id: String, t: Transform3D, pscale := Vector3.ONE, col := Color(0, 0, 0, 0), taper := -1.0, taper_front := -1.0, taper_y := -1.0, taper_front_y := -1.0) -> Node3D:
	if id == "":
		return null
	var part := _make_part(id, t, col, pscale, taper, taper_front, taper_y, taper_front_y)
	# Erstes Teil im (vorher) leeren/wurzellosen Bauraum = WURZEL -> Start des Bauplans.
	# (_make_part hat die neue Teil-Wurzel auf false gesetzt; has_root() sieht also nur
	#  bereits vorhandene Wurzeln.)
	if not has_root():
		part.set_meta("is_root", true)
	if symmetry and absf(t.origin.x) > _mirror_threshold(id, pscale):
		var mt := _mirror_xform(t)
		var mpart := _make_part(id, mt, col, pscale, taper, taper_front, taper_y, taper_front_y)
		part.set_meta("mirror", mpart)
		mpart.set_meta("mirror", part)
		mpart.set_meta("thrust_reverse", part.get_meta("thrust_reverse", false))
		_update_wing_fill(part)
		_update_wing_fill(mpart)
	return part


func _delete_hovered() -> void:
	var part := _pick_part_at_mouse()
	if part == null:
		return
	if part == selected_part:
		_deselect()
	if part.has_meta("mirror"):
		var m = part.get_meta("mirror")
		if is_instance_valid(m):
			m.free()
	part.free()
	_push_history()
	_notify_changed()


func _make_part(id: String, xform: Transform3D, col := Color(0, 0, 0, 0),
		pscale := Vector3.ONE, taper := -1.0, taper_front := -1.0, taper_y := -1.0, taper_front_y := -1.0) -> Node3D:
	var p := PartCatalog.get_part(id)
	var part := Node3D.new()
	part.add_to_group("part")
	part.set_meta("part_id", id)
	# Wurzel wird NICHT mehr automatisch aus dem Katalog-Flag gesetzt, sondern explizit:
	# das ERSTE platzierte Teil (_place_id) bzw. beim Laden (load_design/_ensure_root).
	part.set_meta("is_root", false)
	part.set_meta("color", col)
	# taper/taper_front = X-Skalierung hinten/vorne (< 0 -> Teil-Default, 1.0 = voll).
	# taper_y/taper_front_y = separate Y-Skalierung (< 0 -> wie X, gleichförmig).
	var tp: float = taper if taper >= 0.0 else float(p.get("taper", 1.0))
	var tpf: float = taper_front if taper_front >= 0.0 else float(p.get("taper_front", 1.0))
	var tpy: float = taper_y if taper_y >= 0.0 else tp
	var tpfy: float = taper_front_y if taper_front_y >= 0.0 else tpf
	part.set_meta("taper", tp)
	part.set_meta("taper_front", tpf)
	part.set_meta("taper_y", tpy)
	part.set_meta("taper_front_y", tpfy)
	part.transform = xform
	var vis := PartCatalog.build_visual(p, col, tp, tpf, tpy, tpfy)
	vis.name = "Visual"
	part.add_child(vis)
	# Pick-Körper (nur für Editor-Raycasts)
	var body := StaticBody3D.new()
	body.name = "Pick"
	body.collision_layer = BUILD_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	body.add_child(cs)
	part.add_child(body)
	design_root.add_child(part)
	_apply_part_scale(part, pscale)        # Visual + Kollisionsbox skalieren
	return part


# Wendet die Pro-Teil-Skalierung an: Visual-Mesh + Editor-Pickbox (+ Offset).
func _apply_part_scale(part: Node3D, pscale: Vector3) -> void:
	pscale = pscale.clamp(Vector3(0.25, 0.25, 0.25), Vector3(6, 6, 6))
	part.set_meta("pscale", pscale)
	var p := PartCatalog.get_part(part.get_meta("part_id"))
	# Mittelspalt-Füllung: ein Tragflügel im Symmetrie-Modus wird um "fill" (Weltachsen-
	# Einheiten) nach INNEN (zur Wurzel = lokales −X) verlängert -> Spalt zum Spiegel zu.
	var fill: float = float(part.get_meta("fill", 0.0))
	var wingfill := fill > 0.0 and String(p.get("shape", "")) == "wing"
	var nspan: float = maxf(float(p.get("span", 1.0)), 0.01)
	var vis := part.get_node_or_null("Visual")
	if vis:
		if wingfill:
			(vis as Node3D).scale = Vector3(pscale.x + fill / nspan, pscale.y, pscale.z)
			(vis as Node3D).position = Vector3(-fill, 0.0, 0.0)
		else:
			# Beim Klotz ist die Skalierung, die beim Runden galt, schon im NETZ. Die
			# Node-Skalierung traegt nur den Rest — sonst wirkte sie doppelt.
			(vis as Node3D).scale = PartCatalog.block_rest_scale(pscale,
				part.get_meta("block_sc", Vector3.ONE)) if part.has_meta("block_r") \
				else pscale
			(vis as Node3D).position = Vector3.ZERO
	var cs := part.get_node_or_null("Pick/CollisionShape3D") as CollisionShape3D
	if cs == null:
		var body := part.get_node_or_null("Pick")
		if body:
			cs = body.get_child(0) as CollisionShape3D
	if cs and cs.shape is BoxShape3D:
		var bsize: Vector3 = PartCatalog.col_size(p) * pscale
		var boff: Vector3 = PartCatalog.col_offset(p) * pscale
		if wingfill:
			(cs.shape as BoxShape3D).size = bsize + Vector3(fill, 0.0, 0.0)
			cs.transform = Transform3D(Basis(), boff - Vector3(fill * 0.5, 0.0, 0.0))
		else:
			(cs.shape as BoxShape3D).size = bsize
			cs.transform = Transform3D(Basis(), boff)


# Berechnet die Mittelspalt-Füllung eines Tragflügels neu: nur im Symmetrie-Modus, nur für
# echte Auftriebsflügel (keine Steuerflächen), und nur bis WING_FILL_MAX. So schließt sich der
# Spalt zur gespiegelten Hälfte automatisch (Flügel wird länger), aber nicht unbegrenzt —
# zieht man die Flügel weiter als WING_FILL_MAX nach außen, öffnet sich der Spalt wieder.
func _update_wing_fill(part: Node3D) -> void:
	if not is_instance_valid(part):
		return
	var p := PartCatalog.get_part(part.get_meta("part_id", ""))
	if not bool(p.get("is_wing", false)) or String(p.get("control", "")) != "":
		return
	var fill := 0.0
	if symmetry and part.has_meta("mirror") and is_instance_valid(part.get_meta("mirror")):
		fill = clampf(absf(part.position.x), 0.0, WING_FILL_MAX)
	if not is_equal_approx(float(part.get_meta("fill", 0.0)), fill):
		part.set_meta("fill", fill)
		_apply_part_scale(part, part.get_meta("pscale", Vector3.ONE))


func _refresh_all_wing_fill() -> void:
	for c in design_root.get_children():
		if c.is_in_group("part"):
			_update_wing_fill(c)


# ---------------------------------------------------------------------------
# Snapping-Mathematik
# ---------------------------------------------------------------------------
func _compute_snap_for(id: String, hit: Dictionary) -> Dictionary:
	if id == "":
		return {"valid": false}
	var p := PartCatalog.get_part(id)
	if p.is_empty():
		return {"valid": false}
	# ERSTES Teil im leeren Bauraum: zentriert auf den Ursprung (0,0,0) -> hier startet der
	# Bauplan. Egal wo die Maus ist, das erste Cockpit kommt in die Mitte.
	if _design_empty():
		var b0 := Basis()
		if ghost_rot != 0:
			b0 = Basis(Vector3.UP, deg_to_rad(90.0 * ghost_rot))
		return {"valid": true, "xform": Transform3D(b0, Vector3.ZERO)}
	if hit.is_empty():
		return {"valid": false}
	var part := _part_from_hit(hit)
	if part == null:
		return {"valid": false}
	var n: Vector3 = hit["normal"].normalized()
	var surface: Vector3 = hit["position"]

	# AUTO-FIT am RETO-Motor: ein normales Rumpfsegment (biends), das am Reto-Motor oder an
	# einem Profil-Segment andockt, ÜBERNIMMT dessen Profil-Form (Querschnitt aus dem
	# Blender-Profilblatt) -> die Kette führt die Form nahtlos weiter. Skalierbar wie immer.
	var _reto_tgt := String(part.get_meta("part_id"))
	if p.get("biends", false) and (_reto_tgt == "reto_engine" or _reto_tgt == "fuselage_reto"):
		var rdef := PartCatalog.get_part("fuselage_reto")
		var rfit := _fuselage_fit(rdef, part, n, surface)
		if not rfit.is_empty():
			rfit["id"] = "fuselage_reto"
			if _reto_tgt == "reto_engine":
				rfit["scale"] = Vector3.ONE   # Motor-Heck = exakt die Profilblatt-Größe (0.95×1.24)
			return rfit

	# ANDOCKEN AM STERNMOTOR: er hat GENAU EINE Andockfläche — die Schnittebene hinten.
	# Darum hier direkt rechnen statt _fuselage_fit: dessen "längste Achse"-Heuristik nähme bei
	# dieser Gondel X (die Montage-Box ist mit 1.2 breiter als lang) und dockte SEITLICH an.
	# Zusätzlich ist es egal, wo man den Motor trifft — ein Rumpfteil gehört immer hinter ihn;
	# das macht das Ziehen tolerant (die große Cowl reicht als Ziel).
	if p.get("biends", false) and _reto_tgt == "engine_radial":
		var edef := PartCatalog.get_part("engine_radial")
		var fdef := PartCatalog.get_part("fuselage_radial")
		var etb := part.global_transform.basis.orthonormalized()
		var etsc: Vector3 = part.get_meta("pscale", Vector3.ONE)
		var eoff: Vector3 = PartCatalog.col_offset(edef)
		var cut: Vector3 = part.global_position + etb * Vector3(eoff.x * etsc.x, eoff.y * etsc.y,
			PartCatalog.engine_cut_z(edef) * etsc.z)        # Schnittebene in Weltkoordinaten
		var forg: Vector3 = cut + etb.z * (PartCatalog.col_size(fdef).z * 0.5) \
			- etb * PartCatalog.col_offset(fdef)
		# scale = ONE: die Schnittebene IST exakt die Profilblatt-Größe (1.200 × 1.129).
		return {"valid": true, "xform": Transform3D(etb, forg), "scale": Vector3.ONE,
			"id": "fuselage_radial"}

	# Profil-Segment an Profil-Segment ODER ans Doppeldecker-Cockpit (gleiche Profil-Familie):
	# hier passt _fuselage_fit (Z ist jeweils die längste Achse) -> Kette führt die Form weiter.
	# Am Cockpit scale=ONE: das Segment bekommt exakt die Profilblatt-Größe (1.20×1.13) und
	# schiebt sich unter die minimal größere Cockpit-Außenschale (1.23×1.18) = Haut-Überlapp.
	if p.get("biends", false) and (_reto_tgt == "fuselage_radial" or _reto_tgt == "cockpit_radial"):
		var afit := _fuselage_fit(PartCatalog.get_part("fuselage_radial"), part, n, surface)
		if not afit.is_empty():
			afit["id"] = "fuselage_radial"
			if _reto_tgt == "cockpit_radial":
				afit["scale"] = Vector3.ONE
			return afit

	# B-29-GLASNASE: Der gesamte gerade Metallkragen ist eine tolerante Andockzone.
	# Ein Rumpfsegment landet unabhängig vom genauen Treffpunkt immer mittig auf der
	# ebenen Rückseite und übernimmt dort exakt Breite und Höhe des Blender-Modells.
	if p.get("biends", false) and _reto_tgt == "cockpit_b29":
		var b29def := PartCatalog.get_part("cockpit_b29")
		var b29b := part.global_transform.basis.orthonormalized()
		var b29sc: Vector3 = part.get_meta("pscale", Vector3.ONE)
		var b29co: Vector3 = PartCatalog.col_offset(b29def)
		var rear_surface := part.global_position + b29b * Vector3(
			b29co.x * b29sc.x, b29co.y * b29sc.y,
			(b29co.z + PartCatalog.col_size(b29def).z * 0.5) * b29sc.z)
		# Nicht das generische Segment nehmen: dessen Querschnitt (shape "box") trifft das
		# Zwoelfeck der Glasnase nicht, an der Naht blieb eine Kante stehen. fuselage_b29
		# traegt genau dieselbe Kontur; scale=ONE laesst ihm exakt die Modellgroesse.
		var b29seg := PartCatalog.get_part("fuselage_b29")
		var b29fit := _fuselage_fit(b29seg, part, b29b.z, rear_surface)
		if not b29fit.is_empty():
			b29fit["id"] = "fuselage_b29"
			b29fit["scale"] = Vector3.ONE
			return b29fit

	# B-29-Segment an B-29-Segment: die Kette fuehrt dieselbe Zwoelfeck-Kontur weiter.
	if p.get("biends", false) and _reto_tgt == "fuselage_b29":
		var kfit := _fuselage_fit(PartCatalog.get_part("fuselage_b29"), part, n, surface)
		if not kfit.is_empty():
			kfit["id"] = "fuselage_b29"
			kfit["scale"] = Vector3.ONE
			return kfit

	# MODERNES TRANSPORT-COCKPIT: Der gesamte gerade Heckkragen führt ein normales
	# Rumpfsegment zur planen Rückseite. Dort wird es durch das verborgene
	# fuselage_transport mit exakt derselben 12-seitigen Superellipse ersetzt.
	if p.get("biends", false) and _reto_tgt == "cockpit_transport":
		var transport_def := PartCatalog.get_part("cockpit_transport")
		var transport_basis := part.global_transform.basis.orthonormalized()
		var transport_scale: Vector3 = part.get_meta("pscale", Vector3.ONE)
		var transport_offset: Vector3 = PartCatalog.col_offset(transport_def)
		var transport_rear := part.global_position + transport_basis * Vector3(
			transport_offset.x * transport_scale.x,
			transport_offset.y * transport_scale.y,
			(transport_offset.z + PartCatalog.col_size(transport_def).z * 0.5) \
				* transport_scale.z)
		var transport_seg := PartCatalog.get_part("fuselage_transport")
		var transport_fit := _fuselage_fit(
			transport_seg, part, transport_basis.z, transport_rear)
		if not transport_fit.is_empty():
			transport_fit["id"] = "fuselage_transport"
			transport_fit["scale"] = Vector3.ONE
			return transport_fit

	# Transport-Segment an Transport-Segment: Querschnitt und flache Facetten bleiben
	# über die ganze Rumpfkette erhalten.
	if p.get("biends", false) and _reto_tgt == "fuselage_transport":
		var transport_chain := _fuselage_fit(
			PartCatalog.get_part("fuselage_transport"), part, n, surface)
		if not transport_chain.is_empty():
			transport_chain["id"] = "fuselage_transport"
			transport_chain["scale"] = Vector3.ONE
			return transport_chain

	# UMGEDREHTES ANDOCKEN AM NORMALEN PROPELLERMOTOR: Steht der Motor bereits im Raum
	# und der Spieler zieht ein Rumpfteil daran, rechnen wir mit der kurzen, planen
	# Bughauben-Box. Beim Loslassen wird das Zielteil dauerhaft auf prop_engine_nose
	# umgestellt. Vorderkante/Propeller bleiben dabei an derselben Stelle; nur das Heck
	# wird bis zur Rumpf-Anschlussfläche gekürzt.
	if _is_fuselage(p) and _reto_tgt == "prop_engine":
		var nose_def := PartCatalog.get_part("prop_engine_nose")
		var tb := part.global_transform.basis.orthonormalized()
		var tsc: Vector3 = part.get_meta("pscale", Vector3.ONE)
		var nco: Vector3 = PartCatalog.col_offset(nose_def)
		var rear_surface: Vector3 = part.global_position + tb * Vector3(
			nco.x * tsc.x, nco.y * tsc.y,
			(nco.z + PartCatalog.col_size(nose_def).z * 0.5) * tsc.z)
		var reverse_fit := _fuselage_fit(p, part, tb.z, rear_surface, nose_def)
		if not reverse_fit.is_empty():
			reverse_fit["cut_target"] = part
			return reverse_fit

	# AUTO-FIT Rumpf-an-Rumpf: neues Rumpfteil koaxial & bündig ans getroffene Ende setzen
	# und Breite/Höhe an den Querschnitt des Zielteils anpassen ("in der Mitte", gleiche Größe).
	if _is_fuselage(p) and _is_fuselage(PartCatalog.get_part(part.get_meta("part_id"))):
		var fit := _fuselage_fit(p, part, n, surface)
		if not fit.is_empty():
			return fit

	# AUTO-FIT Prop-Motor an Rumpf: bündige Bugmotor-Cowl, Querschnitt = Rumpf (geht perfekt über).
	# Statt der freistehenden Gondel wird die "prop_engine_nose"-Variante gesetzt.
	if _is_prop_engine(p) and _is_fuselage(PartCatalog.get_part(part.get_meta("part_id"))):
		var nose_def := PartCatalog.get_part("prop_engine_nose")
		var nfit := _fuselage_fit(nose_def, part, n, surface)
		if not nfit.is_empty():
			# Das Modell ist hinten FLACH durchgeschnitten -> setzt direkt bündig an (kein Versenken,
			# keine Geometrie im Rumpf). Querschnitt kommt per Auto-Fit auf die Rumpfgröße;
			# die serienmäßige weiße Motorlackierung bleibt unabhängig von der Rumpffarbe.
			nfit["id"] = "prop_engine_nose"
			nfit["color"] = Color(0, 0, 0, 0)
			return nfit

	if p.get("orient_normal", false):
		return _fluegel_snap(p, part, n, surface)
	else:
		var ori := Basis()
		if ghost_rot != 0:
			ori = Basis(Vector3.UP, deg_to_rad(90.0 * ghost_rot))
		var he: Vector3 = PartCatalog.col_size(p) * 0.5
		# Stuetzweite in der GEDREHTEN Teilbasis messen (bei R-Drehung tauschen x/z),
		# und danach col_offset ZURUECKRECHNEN: Die Box, nicht der Ursprung, soll die
		# getroffene Flaeche beruehren.
		# FRUEHER wurde col_offset hier ignoriert und der Ursprung stumpf um die halbe
		# Boxgroesse versetzt. Bei jedem Teil, dessen Box NICHT um den Ursprung zentriert
		# ist, hing es dadurch genau um col_offset in der Luft — gemessen an einer
		# Fluegelunterseite: wheel_jet 0.50 m, wheel_retract 0.52 m, wheel_spitfire 0.66 m
		# (Reifen ohne Offset wie wheel/wheel_light sassen immer schon bundig).
		var support := absf(n.dot(ori.x)) * he.x + absf(n.dot(ori.y)) * he.y \
			+ absf(n.dot(ori.z)) * he.z
		var origin := surface + n * support - ori * PartCatalog.col_offset(p)
		origin = _snap_tangential(origin, n, 0.25)
		return {"valid": true, "xform": Transform3D(ori, origin)}


# ===========================================================================
# FLUEGEL-ANHAFTUNG
# ---------------------------------------------------------------------------
# Gerechnet wird im BEZUGSSYSTEM DES GETROFFENEN TEILS, nicht in Weltachsen.
# Damit stimmt die Ausrichtung auch an einem gerollten Rumpf, und ein Fluegel auf
# einem bereits gespiegelten Fluegel (Basis mit det<0) erbt die Spiegelung von
# selbst — sein "auswaerts" ist dann automatisch die andere Seite.
#
# Drei Regeln, aus denen sich alles ergibt:
#   1. SEITE aus dem Treffer: die Normale entscheidet, wo sie eindeutig ist, sonst
#      die Trefferposition. Damit landet ein Klick oben/unten nicht mehr blind rechts.
#   2. Die linke Seite ist die SPIEGELUNG der rechten, keine 180-Grad-Drehung.
#      Vorher kippte z = x kreuz y die Sehne mit um: gepfeilte und Deltafluegel
#      pfeilten links nach VORNE (gemessen: Delta -1.35 statt +1.35).
#   3. Die Sehne folgt der LAENGSACHSE des getroffenen Teils, nicht der Weltachse.
# ---------------------------------------------------------------------------

# Auf welcher lokalen Achse waechst der Fluegel aus seiner Wurzel? Ablesbar an
# col_offset: auf der Spannachse ist der Versatz genau die halbe Boxgroesse (die
# Wurzel sitzt im Ursprung, die Box liegt komplett auf einer Seite). Die meisten
# Fluegel spannen in +X; mig21_fin ist als bereits stehende Flosse gebaut (+Y).
# Ohne diese Unterscheidung legte die alte Ausrichtung genau diese Flosse flach.
func _fluegel_spannachse(p: Dictionary) -> int:
	var cs: Vector3 = PartCatalog.col_size(p)
	var co: Vector3 = PartCatalog.col_offset(p)
	if absf(co.y - cs.y * 0.5) < 0.02 and absf(co.x - cs.x * 0.5) > 0.02:
		return 1
	return 0


# Wie tief die Wurzel unter die Haut rutscht: genug, dass an einer gewoelbten
# Flanke keine Fuge aufblitzt, aber nie mehr als ein Viertel der eigenen Dicke —
# sonst verschwaende ein duennes Ruder halb im Rumpf.
func _fluegel_einsink(p: Dictionary) -> float:
	return clampf(PartCatalog.col_size(p).y * 0.25, 0.03, 0.10)


func _fluegel_snap(p: Dictionary, ziel: Node3D, n: Vector3, surface: Vector3) -> Dictionary:
	var T: Basis = ziel.global_transform.basis.orthonormalized()
	var Ti: Basis = T.inverse()
	var lp: Vector3 = Ti * (surface - ziel.global_position)   # Treffer im Zielsystem
	var ln: Vector3 = (Ti * n).normalized()                   # Normale im Zielsystem

	# --- 1) Seite bestimmen ---------------------------------------------------
	# Vorzeichen bevorzugt aus der Normale (eindeutig an einer Flanke), sonst aus
	# der Position (Klick oben/unten), sonst rechts. Das "sonst" ist der Fall, der
	# vorher IMMER griff, sobald man nicht genau seitlich traf.
	var sx: float = signf(ln.x) if absf(ln.x) > 0.30 else signf(lp.x)
	if sx == 0.0:
		sx = 1.0
	var sy: float = signf(ln.y) if absf(ln.y) > 0.30 else signf(lp.y)
	if sy == 0.0:
		sy = 1.0

	# --- 2) Basis im Zielsystem bauen ----------------------------------------
	# Sehne (Z) zeigt IMMER nach hinten, Auftrieb (Y) nach oben. Nur die Spann-
	# richtung kippt — genau das macht aus der rechten Seite die gespiegelte linke
	# (Determinante < 0, dieselbe improper Basis, die auch der Symmetrie-Modus
	# erzeugt; fuer die Kollision wird sie wie dort proper gemacht).
	var lokal: Basis
	if String(p.get("control", "")) == "yaw":
		# Seitenflosse: steht senkrecht, oben oder (unter dem Rumpf) unten.
		if _fluegel_spannachse(p) == 1:
			# Geometrie ist schon stehend gebaut -> nur die Hochachse umdrehen. Z NICHT
			# mitdrehen: sonst zeigt die Sehne der Unterflosse nach vorne (gemessen).
			# Die Basis wird dadurch improper — eine Unterflosse IST die Spiegelung
			# einer Oberflosse, genau wie links/rechts beim Tragfluegel.
			lokal = Basis(Vector3(1, 0, 0), Vector3(0, sy, 0), Vector3(0, 0, 1))
		else:
			# Spannachse X muss nach oben zeigen.
			lokal = Basis(Vector3(0, sy, 0), Vector3(-sy, 0, 0), Vector3(0, 0, 1))
	else:
		lokal = Basis(Vector3(sx, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))

	var ori: Basis = T * lokal
	if ghost_rot != 0:
		# R kippt weiter um die Sehne (30er-Schritte). Auf der gespiegelten Seite
		# kippt es dadurch spiegelbildlich mit -> aus einem Paar wird echte V-Stellung.
		ori = ori * Basis(Vector3(0, 0, 1), deg_to_rad(30.0 * ghost_rot))

	# --- 3) Wurzel setzen -----------------------------------------------------
	# Laengs und hoch auf ein Raster IM ZIELSYSTEM — dadurch landen linke und rechte
	# Seite auf exakt derselben Station, statt um Bruchteile zu versetzen.
	var raster := 0.25
	lp.z = roundf(lp.z / raster) * raster
	lp.y = roundf(lp.y / raster) * raster
	var origin: Vector3 = ziel.global_position + T * lp - n * _fluegel_einsink(p)
	return {"valid": true, "xform": Transform3D(ori, origin)}


func _orient_to_normal(n: Vector3) -> Basis:
	var x := n.normalized()
	var up := Vector3.UP
	var y := up - x * up.dot(x)
	if y.length() < 0.05:
		var rgt := Vector3.RIGHT
		y = rgt - x * rgt.dot(x)
	y = y.normalized()
	var z := x.cross(y).normalized()
	y = z.cross(x).normalized()
	return Basis(x, y, z).orthonormalized()


# Ist das ein Rumpfteil? (Kategorie "Rumpf", kein Flügel) -> nimmt am Auto-Fit teil.
func _is_fuselage(p: Dictionary) -> bool:
	return p.get("category", "") == PartCatalog.CAT_BODY and not p.get("is_wing", false)


# Freistehender Propellermotor (Form "prop") -> bekommt am Rumpf die bündige Cowl-Variante.
func _is_prop_engine(p: Dictionary) -> bool:
	return p.get("id", "") == "prop_engine"


# Bereits platzierten normalen Propellermotor auf die echte Cut-Variante umstellen.
# Metadaten wie Wurzel, Farbe, Schubumkehr und Spiegelverknüpfung bleiben erhalten.
func _convert_prop_to_nose(part: Node3D) -> void:
	if not is_instance_valid(part) or String(part.get_meta("part_id", "")) != "prop_engine":
		return
	part.set_meta("part_id", "prop_engine_nose")
	_rebuild_visual(part)
	_apply_part_scale(part, part.get_meta("pscale", Vector3.ONE))
	var mirror: Node3D = null
	if part.has_meta("mirror"):
		mirror = part.get_meta("mirror") as Node3D
	if is_instance_valid(mirror) and String(mirror.get_meta("part_id", "")) == "prop_engine":
		mirror.set_meta("part_id", "prop_engine_nose")
		_rebuild_visual(mirror)
		_apply_part_scale(mirror, mirror.get_meta("pscale", Vector3.ONE))


# Auto-Fit: neues Rumpfteil koaxial & bündig an die getroffene Fläche des Zielteils setzen
# und seine Breite/Höhe (die beiden Querschnitt-Achsen) an das Zielteil anpassen.
# Liefert {valid, xform, scale} — scale = die übernommene pscale.
func _fuselage_fit(pd: Dictionary, target: Node3D, n: Vector3,
		hit_pos := Vector3.INF, target_def_override: Dictionary = {}) -> Dictionary:
	var tdef: Dictionary = target_def_override
	if tdef.is_empty():
		tdef = PartCatalog.get_part(target.get_meta("part_id"))
	if tdef.is_empty():
		return {}
	var tb := target.global_transform.basis.orthonormalized()
	var tsc: Vector3 = target.get_meta("pscale", Vector3.ONE)
	var tcs := PartCatalog.col_size(tdef)          # Einheits-Boxgröße Ziel
	var ncs := PartCatalog.col_size(pd)            # Einheits-Boxgröße neues Teil
	# Getroffene Fläche -> dominante Achse + Vorzeichen im Lokalsystem des Ziels
	var ln := tb.inverse() * n
	var axis := 0
	if absf(ln.y) >= absf(ln.x) and absf(ln.y) >= absf(ln.z):
		axis = 1
	elif absf(ln.z) >= absf(ln.x) and absf(ln.z) >= absf(ln.y):
		axis = 2
	var sgn := 1.0 if ln[axis] >= 0.0 else -1.0
	# KETTENBAU-HILFE: liegt der Treffer deutlich im ENDBEREICH der Längsachse, die Kette dort
	# bündig verlängern — auch bei einem Seitentreffer nahe dem Ende. Macht das Andocken von
	# Rumpfsegmenten viel leichter (man muss nicht die kleine runde Endkappe exakt treffen).
	if hit_pos.is_finite():
		var tlen := tcs * tsc
		var laxis := 0
		if tlen.y >= tlen.x and tlen.y >= tlen.z: laxis = 1
		elif tlen.z >= tlen.x and tlen.z >= tlen.y: laxis = 2
		var tcenter0 := target.global_position + tb * (PartCatalog.col_offset(tdef) * tsc)
		var lhit := tb.inverse() * (hit_pos - tcenter0)
		if laxis != axis and absf(lhit[laxis]) > tlen[laxis] * 0.30:   # >60% zum Ende hin
			axis = laxis
			sgn = 1.0 if lhit[laxis] >= 0.0 else -1.0
	# Querschnitt (die beiden ANDEREN Achsen): Breite/Höhe vom Ziel übernehmen.
	var ns := Vector3.ONE
	for a in 3:
		if a == axis:
			continue
		var val: float = (tcs[a] * tsc[a]) / maxf(ncs[a], 0.001)
		if a == 0: ns.x = val
		elif a == 1: ns.y = val
		else: ns.z = val
	ns = ns.clamp(Vector3(0.25, 0.25, 0.25), Vector3(6, 6, 6))
	# Bündig ans getroffene Ende, koaxial (kein Quer-Versatz = "perfekt in der Mitte").
	var half_t: float = tcs[axis] * tsc[axis] * 0.5
	var half_n: float = ncs[axis] * ns[axis] * 0.5
	var dir := (tb * _axis_vec(axis)) * sgn
	var tcenter := target.global_position + tb * (PartCatalog.col_offset(tdef) * tsc)
	var new_center := tcenter + dir * (half_t + half_n)
	var origin := new_center - tb * (PartCatalog.col_offset(pd) * ns)
	return {"valid": true, "xform": Transform3D(tb, origin), "scale": ns}


func _snap_tangential(origin: Vector3, n: Vector3, grid: float) -> Vector3:
	var snap_pos := origin.snapped(Vector3.ONE * grid)
	var along := (origin - snap_pos).dot(n)
	return snap_pos + n * along


# Grid-Snapping beim VERSCHIEBEN: der Teil-Mittelpunkt rastet auf ein feines Raster (GRID).
# So lassen sich Teile sauber & vorhersehbar aneinander ausrichten. only_axis>=0 = nur diese Achse.
const MOVE_GRID := 0.025
func _snap_move(part: Node3D, pos: Vector3, only_axis := -1) -> Vector3:
	if not snap_enabled:
		return pos
	var p := PartCatalog.get_part(part.get_meta("part_id"))
	var cov: Vector3 = PartCatalog.col_offset(p) * part.get_meta("pscale", Vector3.ONE)
	var c := [pos.x + cov.x, pos.y + cov.y, pos.z + cov.z]   # genäherter Box-Mittelpunkt
	for a in 3:
		if only_axis >= 0 and a != only_axis:
			continue
		c[a] = roundf(c[a] / MOVE_GRID) * MOVE_GRID
	return Vector3(c[0], c[1], c[2]) - cov


# Magnetisches Flächen-Snapping: rastet Teile BÜNDIG aneinander. Reichweite + Raster fürs Skalieren.
const SNAP_MAG := 0.14           # magnetische Reichweite fürs Andocken — klein gehalten: großer freier
                                 # Spielraum, rastet erst ein wenn man wirklich nah dran ist (nicht bei jeder Bewegung)
const SCALE_GRID := 0.05

# Welt-AABB des Teils, wenn sein Ursprung bei `origin` läge und es Skalierung `sc` hätte.
func _aabb_for(part: Node3D, origin: Vector3, sc: Vector3) -> AABB:
	var p := PartCatalog.get_part(part.get_meta("part_id"))
	var half: Vector3 = PartCatalog.col_size(p) * sc * 0.5
	var b := part.transform.basis
	var center: Vector3 = origin + b * (PartCatalog.col_offset(p) * sc)
	var ab := AABB(center, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				ab = ab.expand(center + b * Vector3(sx * half.x, sy * half.y, sz * half.z))
	return ab


# Andock-Priorität: gleiche Kategorie zuerst (Rumpf-Kette, Flügel-Paar), Rumpf generell
# bevorzugt (Rückgrat). Höhere Affinität schlägt kürzere Distanz -> ein Rumpf dockt eher an
# einen Rumpf als an einen zufällig näheren Flügel.
func _snap_affinity(cat_d: String, cat_n: String) -> int:
	var s := 1
	if cat_d == cat_n:
		s += 2
	if cat_n == PartCatalog.CAT_BODY:
		s += 1
	return s


# Verschieben: zieht das Teil pro Achse BÜNDIG an die nächste PASSENDE Nachbar-Fläche
# (Affinität VOR Distanz), sofern sich die beiden anderen Achsen überlappen.
func _snap_to_neighbors(part: Node3D, pos: Vector3, only_axis := -1) -> Vector3:
	if not snap_enabled:
		return pos
	var sc: Vector3 = part.get_meta("pscale", Vector3.ONE)
	var result := pos
	var mir = part.get_meta("mirror") if part.has_meta("mirror") else null
	var cat_d: String = PartCatalog.get_part(part.get_meta("part_id")).get("category", "")
	for a in 3:
		if only_axis >= 0 and a != only_axis:
			continue
		var my := _aabb_for(part, result, sc)
		var mn := my.position
		var mx := my.position + my.size
		var b1 := (a + 1) % 3
		var b2 := (a + 2) % 3
		var best_aff := 0           # höhere Affinität gewinnt IMMER (solange in Reichweite)
		var best_d := SNAP_MAG      # bei gleicher Affinität: kleinster Abstand gewinnt
		var best_delta := 0.0
		for other in design_root.get_children():
			if not other.is_in_group("part") or other == part or other == mir:
				continue
			var ob := _part_world_aabb(other)
			var omn := ob.position
			var omx := ob.position + ob.size
			if mx[b1] <= omn[b1] + 0.04 or mn[b1] >= omx[b1] - 0.04:
				continue
			if mx[b2] <= omn[b2] + 0.04 or mn[b2] >= omx[b2] - 0.04:
				continue
			var aff := _snap_affinity(cat_d, PartCatalog.get_part(other.get_meta("part_id")).get("category", ""))
			# meine −Fläche an deren +Fläche  /  meine +Fläche an deren −Fläche
			for cand in [[absf(omx[a] - mn[a]), omx[a] - mn[a]], [absf(omn[a] - mx[a]), omn[a] - mx[a]]]:
				var d: float = cand[0]
				if d >= SNAP_MAG:
					continue
				if aff > best_aff or (aff == best_aff and d < best_d):
					best_aff = aff
					best_d = d
					best_delta = cand[1]
		if best_aff > 0:
			result[a] += best_delta
	return result


# Skalieren: Offset der gezogenen Fläche (von _drag_origin0 entlang _drag_axis_w) aufs Raster
# bzw. magnetisch an eine Nachbar-Fläche einrasten. Gibt den evtl. gesnappten Offset zurück.
func _snap_scale_face(part: Node3D, face_off: float) -> float:
	# Skalieren folgt EXAKT der Maus (kein Raster) — nur magnetisch bündig an eine Nachbar-
	# Fläche, wenn man nah dran ist. So scrubt die Größe 1:1 mit der Mausbewegung.
	if not snap_enabled:
		return face_off
	var axw := _drag_axis_w
	var k := 0
	if absf(axw.y) > absf(axw[k]):
		k = 1
	if absf(axw.z) > absf(axw[k]):
		k = 2
	if absf(axw[k]) < 0.94:                          # nicht achsenparallel -> exakt (kein Magnet)
		return face_off
	var dir: float = signf(axw[k])
	var face_k: float = _drag_origin0[k] + axw[k] * face_off
	var my := _part_world_aabb(part)
	var mn := my.position
	var mx := my.position + my.size
	var b1 := (k + 1) % 3
	var b2 := (k + 2) % 3
	var mir = part.get_meta("mirror") if part.has_meta("mirror") else null
	var cat_d: String = PartCatalog.get_part(part.get_meta("part_id")).get("category", "")
	var best_aff := 0
	var best_d := SNAP_MAG
	var best := face_k
	for other in design_root.get_children():
		if not other.is_in_group("part") or other == part or other == mir:
			continue
		var ob := _part_world_aabb(other)
		var omn := ob.position
		var omx := ob.position + ob.size
		if mx[b1] <= omn[b1] + 0.04 or mn[b1] >= omx[b1] - 0.04:
			continue
		if mx[b2] <= omn[b2] + 0.04 or mn[b2] >= omx[b2] - 0.04:
			continue
		var aff := _snap_affinity(cat_d, PartCatalog.get_part(other.get_meta("part_id")).get("category", ""))
		for cand in [omn[k], omx[k]]:
			var d: float = absf(cand - face_k)
			if d >= SNAP_MAG:
				continue
			if aff > best_aff or (aff == best_aff and d < best_d):
				best_aff = aff
				best_d = d
				best = cand
	if best_aff > 0:
		return (best - _drag_origin0[k]) * dir
	return face_off                                  # kein Nachbar -> exakt der Maus folgen


func _mirror_xform(t: Transform3D) -> Transform3D:
	var b := t.basis
	var nb := Basis(
		Vector3(-b.x.x, b.x.y, b.x.z),
		Vector3(-b.y.x, b.y.y, b.y.z),
		Vector3(-b.z.x, b.z.y, b.z.z))
	return Transform3D(nb, Vector3(-t.origin.x, t.origin.y, t.origin.z))


# ---------------------------------------------------------------------------
# Raycast-Helfer
# ---------------------------------------------------------------------------
func _raycast_mouse(mask := BUILD_LAYER, exclude: Array[RID] = []) -> Dictionary:
	if camera == null:
		return {}
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var to := from + camera.project_ray_normal(mp) * 2000.0
	var space := get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = mask
	q.collide_with_areas = false
	q.exclude = exclude
	return space.intersect_ray(q)


# Teil unter der Maus — präziser als der rohe erste Ray-Treffer: Boxen großer
# Teile umschließen oft kleinere sichtbare Anbauten (Kanone im Rumpf, MG am
# Flügel) — dann gewann immer die große Hülle, nicht das Teil, auf das man
# ZEIGT. Hier werden die Treffer im Nahbereich des ersten eingesammelt und das
# VOLUMENKLEINSTE gewinnt (das eingebettete/aufgesetzte Teil ist das gemeinte).
func _pick_part_at_mouse() -> Node3D:
	var ex: Array[RID] = []
	var first_d := -1.0
	var best: Node3D = null
	var best_vol := INF
	var ro := camera.project_ray_origin(get_viewport().get_mouse_position()) if camera != null else Vector3.ZERO
	for i in 5:
		var hit := _raycast_mouse(BUILD_LAYER, ex)
		if hit.is_empty():
			break
		var part := _part_from_hit(hit)
		if part != null:
			var d: float = (Vector3(hit["position"]) - ro).length()
			if first_d < 0.0:
				first_d = d
			if d > first_d + 0.9:
				break   # zu weit hinter dem ersten Treffer -> anderes Teil, kein Nest
			var pdef := PartCatalog.get_part(part.get_meta("part_id"))
			var cz: Vector3 = PartCatalog.col_size(pdef) * part.get_meta("pscale", Vector3.ONE)
			var vol: float = cz.x * cz.y * cz.z
			if vol < best_vol:
				best_vol = vol
				best = part
		var col = hit.get("collider")
		if col == null:
			break
		ex.append((col as CollisionObject3D).get_rid())
	return best


func _part_from_hit(hit: Dictionary) -> Node3D:
	if hit.is_empty():
		return null
	var c = hit.get("collider")
	if c == null:
		return null
	var pn = c.get_parent()
	if pn != null and pn.is_in_group("part"):
		return pn
	return null


# ---------------------------------------------------------------------------
# Ghost-Vorschau
# ---------------------------------------------------------------------------
func _rebuild_ghost(override_id := "") -> void:
	if ghost:
		ghost.queue_free()
		ghost = null
	_last_valid = false
	_ghost_built_id = ""
	var id := override_id if override_id != "" else _active_id()
	if id == "" or not PartCatalog.has(id):
		return
	ghost = PartCatalog.build_visual(PartCatalog.get_part(id))
	_ghost_built_id = id
	_ghost_mats.clear()
	_ghost_valid = true
	_apply_ghost_material(ghost)
	ghost.visible = false
	add_child(ghost)


func _apply_ghost_material(node: Node) -> void:
	for c in node.get_children():
		_apply_ghost_material(c)
	if node is MeshInstance3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.4, 1.0, 0.55, 0.45)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.emission_enabled = true
		m.emission = Color(0.2, 0.8, 0.3)
		m.emission_energy_multiplier = 0.3
		node.material_override = m
		_ghost_mats.append(m)


# ---------------------------------------------------------------------------
# Design-Verwaltung
# ---------------------------------------------------------------------------
func get_design() -> Array:
	var out: Array = []
	for child in design_root.get_children():
		if child.is_in_group("part"):
			out.append({
				"id": child.get_meta("part_id"),
				"xform": child.transform,
				"root": child.get_meta("is_root", false),   # Wurzel/Start des Bauplans
				"color": child.get_meta("color", Color(0, 0, 0, 0)),
				"scale": child.get_meta("pscale", Vector3.ONE),
				"taper": child.get_meta("taper", 1.0),
				"taper_front": child.get_meta("taper_front", 1.0),
				"taper_y": child.get_meta("taper_y", -1.0),
				"taper_front_y": child.get_meta("taper_front_y", -1.0),
				"tuser_b": child.has_meta("taper_user"),        # Enden von Hand geformt?
				"tuser_f": child.has_meta("taper_front_user"),  # (Auto-Taper respektiert das)
				"fill": child.get_meta("fill", 0.0),   # Flügel-Mittelspalt-Füllung (für Flug + Speichern)
				"glen": child.get_meta("gear_len", 1.0),   # ausgefahrenes Fahrwerksbein
				"br": Array(_block_r(child)),              # Eckrundungen des Klotzes
				"sf": child.get_meta("shift_front", Vector2.ZERO),   # Versatz vorderes Ende
				"sb": child.get_meta("shift_back", Vector2.ZERO),    # Versatz hinteres Ende
				"bsc": child.get_meta("block_sc", Vector3.ONE),  # Skalierung beim Runden
				"thrust_reverse": child.get_meta("thrust_reverse", false),   # Prop-Schub umkehren
			})
	return out


func load_design(arr: Array) -> void:
	_clear_nodes()
	for item in arr:
		var id: String = item.get("id", "")
		if PartCatalog.has(id):
			var np := _make_part(id, item.get("xform", Transform3D()),
				item.get("color", Color(0, 0, 0, 0)), item.get("scale", Vector3.ONE),
				item.get("taper", -1.0), item.get("taper_front", -1.0),
				item.get("taper_y", -1.0), item.get("taper_front_y", -1.0))
			np.set_meta("thrust_reverse", bool(item.get("thrust_reverse", false)))
			_form_uebernehmen(np, id, item)
			if item.has("root"):   # gespeicherte Wurzel exakt wiederherstellen (neue Saves)
				np.set_meta("is_root", bool(item["root"]))
	_ensure_root()
	_relink_mirrors()
	_refresh_all_wing_fill()    # Mittelspalt-Füllung der geladenen Flügel herstellen
	if not _suppress_history:
		_seed_history()
	_notify_changed()


# Uebertraegt ALLES, was der Spieler an einem Teil von Hand geformt hat, aus einem
# get_design()-Eintrag auf ein frisch gebautes Teil. Laden UND Kopieren/Einfuegen gehen
# durch DIESELBE Funktion — vorher trug duplicate_selected nur Farbe/Groesse mit, die
# Formung (Verjuengung, Enden-Versatz, Eckrundung, Beinlaenge) fiel still weg.
func _form_uebernehmen(np: Node3D, id: String, item: Dictionary) -> void:
	# Ausgefahrenes Fahrwerksbein wiederherstellen (Visual neu bauen, damit die
	# Beinlaenge sofort steht — _add_part kennt das Meta beim Bauen noch nicht).
	var vsf: Vector2 = item.get("sf", Vector2.ZERO)
	var vsb: Vector2 = item.get("sb", Vector2.ZERO)
	if vsf.length() > 0.0005 or vsb.length() > 0.0005:
		np.set_meta("shift_front", vsf)
		np.set_meta("shift_back", vsb)
		_rebuild_visual(np)
		_apply_part_scale(np, np.get_meta("pscale", Vector3.ONE))
	var brs: Array = item.get("br", [])
	if brs.size() == 8:
		var ra := PartCatalog.block_radien_neu()
		var scharf := true
		for i in 8:
			ra[i] = clampf(float(brs[i]), 0.0, 1.0)
			if ra[i] > 0.002:
				scharf = false
		if not scharf:
			np.set_meta("block_r", ra)
			np.set_meta("block_sc", item.get("bsc", Vector3.ONE))
			_rebuild_visual(np)
			_apply_part_scale(np, np.get_meta("pscale", Vector3.ONE))
	var glen := float(item.get("glen", 1.0))
	if glen > 1.0001:
		np.set_meta("gear_len", clampf(glen, PartCatalog.GEAR_LEN_MIN,
			PartCatalog.GEAR_LEN_MAX))
		_rebuild_visual(np)
		_apply_part_scale(np, np.get_meta("pscale", Vector3.ONE))
	# Manuell-geformt-Flags wiederherstellen. ALT-Saves (ohne tuser_*) kennzeichnen
	# jedes vom Teil-Default abweichende Ende als manuell — die Auto-Anpassung darf
	# bestehende Designs beim Laden nicht umformen.
	if item.has("tuser_b") or item.has("tuser_f"):
		if bool(item.get("tuser_b", false)):
			np.set_meta("taper_user", true)
		if bool(item.get("tuser_f", false)):
			np.set_meta("taper_front_user", true)
	else:
		var pd := PartCatalog.get_part(id)
		var d_b := float(pd.get("taper", 1.0))
		var i_b := float(item.get("taper", d_b))
		var i_by := float(item.get("taper_y", -1.0))
		if absf(i_b - d_b) > 0.001 or (i_by >= 0.0 and absf(i_by - i_b) > 0.001):
			np.set_meta("taper_user", true)
		var d_f := float(pd.get("taper_front", 1.0))
		var i_f := float(item.get("taper_front", d_f))
		var i_fy := float(item.get("taper_front_y", -1.0))
		if absf(i_f - d_f) > 0.001 or (i_fy >= 0.0 and absf(i_fy - i_f) > 0.001):
			np.set_meta("taper_front_user", true)


# Nach dem Laden Spiegelpaare wieder verknüpfen (gleiche ID, an −x gespiegelte Position),
# damit der Symmetrie-Modus beim Verschieben/Drehen/Skalieren wieder greift und keine
# Duplikate erzeugt werden.
func _relink_mirrors() -> void:
	var parts: Array = []
	for c in design_root.get_children():
		if c.is_in_group("part"):
			parts.append(c)
	for a in parts:
		if a.has_meta("mirror") or a.get_meta("is_root", false) \
				or absf(a.position.x) <= _mirror_threshold(a.get_meta("part_id"), a.get_meta("pscale", Vector3.ONE)):
			continue
		var target: Vector3 = _mirror_xform(a.transform).origin
		for b in parts:
			if b == a or b.has_meta("mirror") or b.get_meta("is_root", false):
				continue
			if b.get_meta("part_id") == a.get_meta("part_id") and b.position.distance_to(target) < 0.06:
				a.set_meta("mirror", b)
				b.set_meta("mirror", a)
				break
	# MITTIGE Spiegelpaare (x≈0): zwei gleiche Teile an gleicher Stelle, eine Hälfte mit
	# gespiegelter (improper, det<0) Basis -> z. B. ein durchgehender Flügel aus zwei in der
	# Mitte zusammenstoßenden Hälften. Damit greift der Symmetrie-Modus auch hier.
	for a in parts:
		if a.has_meta("mirror") or a.get_meta("is_root", false) or absf(a.position.x) > 0.05:
			continue
		if a.transform.basis.determinant() >= 0.0:
			continue                                  # nur die gespiegelte (linke) Hälfte sucht
		for b in parts:
			if b == a or b.has_meta("mirror") or b.get_meta("is_root", false):
				continue
			if b.get_meta("part_id") != a.get_meta("part_id") or absf(b.position.x) > 0.05:
				continue
			if b.transform.basis.determinant() > 0.0 and a.position.distance_to(b.position) < 0.1:
				a.set_meta("mirror", b)
				b.set_meta("mirror", a)
				break


func clear_design() -> void:
	# Komplett leeren — KEIN automatisches Cockpit mehr. Das nächste platzierte Teil
	# startet (zentriert auf den Ursprung) einen neuen Bauplan.
	_clear_nodes()
	_push_history()
	_notify_changed()


func _clear_nodes() -> void:
	_deselect()
	for child in design_root.get_children():
		if child.is_in_group("part"):
			child.free()


func _ensure_root() -> void:
	# Stellt sicher, dass eine Wurzel markiert ist — erzeugt aber KEIN Phantom-Cockpit mehr.
	# Leeres Design bleibt leer. Hat ein geladenes Design (alter Save/Vorlage) keine markierte
	# Wurzel, wird bevorzugt ein Cockpit, sonst das erste Teil zur Wurzel befördert.
	var parts: Array = []
	for child in design_root.get_children():
		if child.is_in_group("part"):
			if child.get_meta("is_root", false):
				return
			parts.append(child)
	if parts.is_empty():
		return
	for c in parts:
		if PartCatalog.get_part(c.get_meta("part_id")).get("root", false):
			c.set_meta("is_root", true)
			return
	parts[0].set_meta("is_root", true)


# ---------------------------------------------------------------------------
# Statistik & Marker
# ---------------------------------------------------------------------------
func compute_stats() -> Dictionary:
	var mass := 0.0
	var n := 0
	var area := 0.0
	var thrust := 0.0       # installierter Schub-Betrag (Anzeige)
	var fwd_thrust := 0.0   # nach VORNE gerichteter Anteil (für die "Fliegt's?"-Ampel)
	var thrust_up := 0.0    # nach OBEN gerichteter Anteil (Senkrechtschub / VTOL)
	var thrust_arms: Array = []   # [pos, kraftvektor] je Triebwerk -> Schub-Drehmoment um den COM
	var gear_cap := 0.0
	var wing_cap := 0.0
	var drag_area := 0.0
	var com := Vector3.ZERO
	var col := Vector3.ZERO
	var col_w := 0.0
	var z_lo := INF         # Längs-Ausdehnung (Nase -Z .. Heck +Z) für die grafische Balance-Achse
	var z_hi := -INF
	# Rumpf-Boxen (Nicht-Flügel) für den Vergrabungs-Test
	var body_boxes: Array = []
	for child in design_root.get_children():
		if not child.is_in_group("part"):
			continue
		var pp := PartCatalog.get_part(child.get_meta("part_id"))
		if pp.get("is_wing", false):
			continue
		body_boxes.append(PartCatalog.part_box(pp, child.transform, child.get_meta("pscale", Vector3.ONE)))
	for child in design_root.get_children():
		if not child.is_in_group("part"):
			continue
		var p := PartCatalog.get_part(child.get_meta("part_id"))
		var psc: Vector3 = child.get_meta("pscale", Vector3.ONE)
		var vol: float = psc.x * psc.y * psc.z
		var m: float = p.get("mass", 0.0) * vol
		mass += m
		n += 1
		z_lo = minf(z_lo, child.position.z)
		z_hi = maxf(z_hi, child.position.z)
		var et: float = p.get("thrust", 0.0) * vol
		thrust += et
		if et > 0.0:
			# Schubrichtung = Blickrichtung (-Z), bei umgekehrtem Prop nach hinten -> zählt negativ.
			var edir: Vector3 = -child.transform.basis.z.normalized()
			if bool(child.get_meta("thrust_reverse", false)):
				edir = -edir
			fwd_thrust += et * (-edir.z)   # nur die nach-vorne-Komponente treibt das Abheben
			thrust_up += et * edir.y       # nach oben gerichteter Anteil (Senkrechtschub)
			thrust_arms.append([child.position, edir * et])   # für das Schub-Drehmoment um den COM
		gear_cap += p.get("gear_capacity", 0.0) * vol
		drag_area += PartCatalog.part_drag(p) * psc.x * psc.y
		com += m * child.position
		if p.get("is_wing", false):
			var a_full: float = p.get("area", 0.0) * psc.x * psc.z
			var span_w: float = p.get("span", sqrt(maxf(a_full, 0.01))) * psc.x
			# im Rumpf vergrabene Fläche zählt nicht (effektive Auftriebsfläche)
			var exposed: float = PartCatalog.wing_exposed_fraction(child.transform, span_w, PartCatalog.col_offset(p).z * psc.z, body_boxes)
			var a: float = a_full * exposed
			area += a
			wing_cap += a_full * PartCatalog.WING_STRESS * p.get("stress_mult", 1.0)
			col += a * child.position
			col_w += a
	if mass > 0.0:
		com /= mass
	if col_w > 0.0:
		col /= col_w
	if n == 0:                  # leeres Design: z-Achse endlich halten (kein INF)
		z_lo = 0.0
		z_hi = 0.0
	# Schub-Drehmoment um den COM: außermittige/schräge Triebwerke kippen/drehen das Flugzeug.
	# thrust_offset = |Drehmoment| / Schub = effektiver Hebel (m), um den der Netto-Schub am COM
	# vorbeizieht. 0 = ausbalanciert (symmetrisch / auf der COM-Achse), groß = kippt unter Last.
	var thrust_torque := Vector3.ZERO
	for arm in thrust_arms:
		var apos: Vector3 = arm[0]
		var afrc: Vector3 = arm[1]
		thrust_torque += (apos - com).cross(afrc)
	var weight: float = max(mass * 9.81, 0.001)
	var tw: float = fwd_thrust / weight          # Ampel nutzt den VORWÄRTS-Schub
	var up_tw: float = thrust_up / weight          # Senkrechtschub / Gewicht (VTOL-fähig ab ~1.0)
	var thrust_offset: float = thrust_torque.length() / max(thrust, 0.001)
	var max_g: float = wing_cap / weight
	return {
		"mass": mass, "parts": n, "area": area, "thrust": thrust,
		"tw": tw, "com": com, "col": col, "col_valid": col_w > 0.0,
		"gear_cap": gear_cap, "gear_overload": gear_cap > 0.0 and mass > gear_cap,
		"has_gear": gear_cap > 0.0, "drag_area": drag_area,
		"max_g": max_g, "has_wings": wing_cap > 0.0,
		"up_tw": up_tw, "thrust_offset": thrust_offset,
		"z_min": z_lo, "z_max": z_hi,
	}


func _notify_changed() -> void:
	_sync_engine_variants()     # VOR compute_stats: setzt das Variant-Meta, das _part_box liest
	_sync_auto_taper()          # verbundene Rumpf-Enden an die Nachbar-Querschnitte anpassen
	var stats := compute_stats()
	if com_marker:
		com_marker.position = stats["com"]
	if col_marker:
		col_marker.position = stats["col"]
		col_marker.visible = stats["col_valid"]
	if wind_tunnel:
		_heatmap_dirty = true       # gedrosselt in _process neu rechnen (statt jeden Frame)
	_update_float_markers()
	_update_debug_boxes()   # Debug-Boxen folgen jeder Aenderung
	design_changed.emit(stats)


# Sternmotor: hinten ein Rumpfteil angedockt -> offene Variante ("Half", Heck weicht dem Rumpf),
# sonst die freistehende Gondel ("Full"). Hier zentral, damit Setzen/Verschieben/Löschen/Undo/
# Laden alle durch denselben Pfad laufen. Nur Sichtbarkeit -> kein Visual-Neubau.
func _sync_engine_variants() -> void:
	var parts: Array = []
	for c in design_root.get_children():
		if c.is_in_group("part"):
			parts.append(c)
	var items: Array = []
	for pp in parts:
		items.append({"id": String(pp.get_meta("part_id")), "xform": pp.transform,
			"pscale": pp.get_meta("pscale", Vector3.ONE)})
	for i in parts.size():
		if items[i]["id"] == "cockpit_radial":
			# Anschlussrahmen pro Seite: verschwindet, sobald dort ein Rumpf/Motor sitzt.
			var cvis: Node = parts[i].get_node_or_null("Visual")
			if cvis != null:
				var cothers: Array = items.duplicate()
				cothers.remove_at(i)
				PartCatalog.set_cockpit_frames(cvis,
					not PartCatalog.cockpit_side_docked("cockpit_radial", items[i]["xform"], items[i]["pscale"], cothers, false),
					not PartCatalog.cockpit_side_docked("cockpit_radial", items[i]["xform"], items[i]["pscale"], cothers, true))
			continue
		if items[i]["id"] != "engine_radial":
			continue
		var vis: Node = parts[i].get_node_or_null("Visual")
		if vis == null:
			continue
		var others: Array = items.duplicate()
		others.remove_at(i)
		var half: bool = PartCatalog.rear_docked(
			"engine_radial", items[i]["xform"], items[i]["pscale"], others)
		PartCatalog.set_engine_half(vis, half)
		parts[i].set_meta("engine_half", half)
		_apply_engine_pickbox(parts[i])


# --- AUTO-Taper: verbundene Rumpf-Enden passen sich dem Nachbar-Querschnitt an -------------
# Sitzt an einem Ende eines biends-Segments buendig ein Rumpfteil/Antrieb, wird dieses Ende
# automatisch auf dessen Breite/Hoehe verjuengt bzw. aufgeweitet — VORNE und HINTEN einzeln
# (Motor schmal + Cockpit breit -> Segment blendet fliessend ueber). Manuell geformte Enden
# ("taper*_user"-Meta, gesetzt von Panel-Reglern/Enden-Drag und beim Laden alter Saves)
# bleiben unangetastet; freie Enden behalten ihren Wert. Kein History-Push (abgeleiteter
# Zustand wie engine_half). Bis zu 3 Durchlaeufe, damit Ketten sofort konvergieren.
func _sync_auto_taper() -> void:
	var parts: Array = []
	for c in design_root.get_children():
		if c.is_in_group("part"):
			parts.append(c)
	for _pass in 3:
		if not _auto_taper_pass(parts):
			break


func _auto_taper_pass(parts: Array) -> bool:
	var any := false
	for i in parts.size():
		var part: Node3D = parts[i]
		var p := PartCatalog.get_part(part.get_meta("part_id"))
		if not p.get("biends", false):
			continue
		var psc: Vector3 = part.get_meta("pscale", Vector3.ONE)
		var sz: Vector3 = p.get("size", Vector3.ONE)
		var changed := false
		for back in [false, true]:
			var key := "taper" if back else "taper_front"
			if part.has_meta(key + "_user"):
				continue   # von Hand geformt -> Automatik lässt die Finger davon
			var n := _taper_neighbor(part, p, psc, parts, i, back)
			if n.is_empty():
				continue   # freies Ende: letzten Wert behalten
			var tx: float = clampf(float(n["w"]) / maxf(sz.x * psc.x, 0.01), 0.25, 2.5)
			var ty: float = clampf(float(n["h"]) / maxf(sz.y * psc.y, 0.01), 0.25, 2.5)
			var cx: float = part.get_meta(key, 1.0)
			var cyv: float = part.get_meta(key + "_y", -1.0)
			var cy: float = cyv if cyv >= 0.0 else cx
			if absf(cx - tx) > 0.004 or absf(cy - ty) > 0.004:
				part.set_meta(key, tx)
				part.set_meta(key + "_y", ty)
				changed = true
		if changed:
			_rebuild_visual(part)
			any = true
	return any


# Nachbar-Querschnitt am Ende (back=false: vorne/-Z) — {} wenn dort nichts buendig sitzt.
# Beruecksichtigt beim Nachbarn dessen eigenes Taper am beruehrten Ende (Ketten-Verlauf).
func _taper_neighbor(part: Node3D, p: Dictionary, psc: Vector3, parts: Array, i: int, back: bool) -> Dictionary:
	var co := PartCatalog.col_offset(p)
	var s := 1.0 if back else -1.0
	var probe: Vector3 = part.transform * Vector3(co.x * psc.x, co.y * psc.y,
		(co.z + s * PartCatalog.col_size(p).z * 0.5) * psc.z + s * 0.06)
	for j in parts.size():
		if j == i:
			continue
		var nb: Node3D = parts[j]
		var op := PartCatalog.get_part(nb.get_meta("part_id"))
		if op.is_empty():
			continue
		if not PartCatalog.is_fuselage_part(op) and op.get("category", "") != PartCatalog.CAT_PROP:
			continue   # nur Rumpf/Antrieb gibt ein Profil vor (Fluegel/Fahrwerk nicht)
		var opsc: Vector3 = nb.get_meta("pscale", Vector3.ONE)
		var lp: Vector3 = nb.transform.affine_inverse() * probe
		var c: Vector3 = PartCatalog.col_offset(op) * opsc
		var hf: Vector3 = PartCatalog.col_size(op) * opsc * 0.5
		if absf(lp.x - c.x) > hf.x or absf(lp.y - c.y) > hf.y or absf(lp.z - c.z) > hf.z:
			continue
		var osz: Vector3 = op.get("size", Vector3.ONE)
		# Manche Blender-Teile sind vorne rundlich/größer als ihre plane Rückseite.
		# dock_size beschreibt dann den echten Endquerschnitt statt der Gesamt-Bounding-Box.
		var dock: Vector2 = op.get("dock_size", Vector2(osz.x, osz.y))
		var w: float = dock.x * opsc.x
		var h: float = dock.y * opsc.y
		if op.get("biends", false):
			var facing_front: bool = lp.z < c.z          # beruehrtes Ende des Nachbarn
			var k := "taper_front" if facing_front else "taper"
			var txn: float = nb.get_meta(k, float(op.get(k, 1.0)))
			var tyn: float = nb.get_meta(k + "_y", -1.0)
			w *= txn
			h *= (tyn if tyn >= 0.0 else txn)
		return {"w": w, "h": h}
	return {}


# Box eines Teils als [size, offset]. Nur der Sternmotor weicht ab: seine Katalog-Box ist die
# MONTAGE-Box (Nase..Schnittebene, damit die Snap-Mathematik stimmt) — solange aber die volle
# Gondel zu SEHEN ist, muss Klickkörper/Nachbarschaft den Heckkonus mit abdecken.
func _part_box(part: Node3D) -> Array:
	var p := PartCatalog.get_part(part.get_meta("part_id"))
	if String(part.get_meta("part_id", "")) == "engine_radial" \
			and not part.get_meta("engine_half", false):
		return PartCatalog.engine_solo_box(p)
	if String(p.get("category", "")) == PartCatalog.CAT_GEAR:
		# Ausgefahrenes Bein: die Box waechst NACH UNTEN, die Oberkante (Anschlussflaeche)
		# bleibt wo sie ist — sonst haenge das Fahrwerk beim Andocken tiefer als gedacht.
		var ext: float = PartCatalog.gear_ext(p, part.get_meta("gear_len", 1.0))
		if ext > 0.0:
			var cs2: Vector3 = PartCatalog.col_size(p)
			var co2: Vector3 = PartCatalog.col_offset(p)
			return [Vector3(cs2.x, cs2.y + ext, cs2.z), Vector3(co2.x, co2.y - ext * 0.5, co2.z)]
	return [PartCatalog.col_size(p), PartCatalog.col_offset(p)]


# Klickkörper des Motors auf die sichtbare Variante ziehen (freistehend inkl. Heckkonus,
# angedockt nur bis zur Schnittebene -> greift nicht durch den Rumpf).
func _apply_engine_pickbox(part: Node3D) -> void:
	var cs := part.get_node_or_null("Pick/CollisionShape3D") as CollisionShape3D
	if cs == null:
		var body := part.get_node_or_null("Pick")
		if body != null and body.get_child_count() > 0:
			cs = body.get_child(0) as CollisionShape3D
	if cs == null or not (cs.shape is BoxShape3D):
		return
	var psc: Vector3 = part.get_meta("pscale", Vector3.ONE)
	var b := _part_box(part)
	(cs.shape as BoxShape3D).size = (b[0] as Vector3) * psc
	cs.transform = Transform3D(Basis(), (b[1] as Vector3) * psc)


# --- Verbindungs-Prüfung: kein freies Schweben ----------------------------
# Welt-AABB der Teil-Box (rotiert), für Nachbarschafts-Test.
func _part_world_aabb(part: Node3D) -> AABB:
	var psc: Vector3 = part.get_meta("pscale", Vector3.ONE)
	var b := _part_box(part)                       # Sternmotor: je nach sichtbarer Variante
	var half: Vector3 = (b[0] as Vector3) * psc * 0.5
	var t := part.transform
	var center: Vector3 = t * ((b[1] as Vector3) * psc)
	var ab := AABB(center, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				ab = ab.expand(center + t.basis * Vector3(sx * half.x, sy * half.y, sz * half.z))
	return ab


# Menge der mit dem Cockpit verbundenen Teile (BFS über sich berührende Boxen).
func _connected_set() -> Dictionary:
	var parts: Array = []
	var root: Node3D = null
	for c in design_root.get_children():
		if c.is_in_group("part"):
			parts.append(c)
			if c.get_meta("is_root", false):
				root = c
	var conn := {}
	if root == null:
		return conn
	var boxes := {}
	for pp in parts:
		boxes[pp] = _part_world_aabb(pp).grow(0.12)   # kleiner Spielraum = "berührt"
	var queue: Array = [root]
	conn[root] = true
	while not queue.is_empty():
		var cur = queue.pop_back()
		var ca: AABB = boxes[cur]
		for o in parts:
			if not conn.has(o) and ca.intersects(boxes[o]):
				conn[o] = true
				queue.append(o)
	return conn


func floating_parts() -> Array:
	var conn := _connected_set()
	var out: Array = []
	for c in design_root.get_children():
		if c.is_in_group("part") and not c.get_meta("is_root", false) and not conn.has(c):
			out.append(c)
	return out


func has_floating() -> bool:
	return floating_parts().size() > 0


# Leerer Bauraum? (kein einziges Teil)
func _design_empty() -> bool:
	for c in design_root.get_children():
		if c.is_in_group("part"):
			return false
	return true


# Gibt es ein als Wurzel markiertes Teil? (sonst kein gültiger Bauplan -> Start blockiert)
func has_root() -> bool:
	for c in design_root.get_children():
		if c.is_in_group("part") and c.get_meta("is_root", false):
			return true
	return false


func floating_count() -> int:
	return floating_parts().size()


# Rote Warn-Marker über frei schwebenden Teilen (nicht das Teil selbst einfärben).
# DEBUG-BOXEN. Pro Teil werden ZWEI Drahtboxen gezeichnet, weil genau deren Differenz
# Spalte erklaert:
#   CYAN = Snap-/Kollisionsbox (col_size + col_offset, mit pscale) — MIT DIESER Box rechnet
#          das Andocken, und auf sie zielt auch der Klick-Raycast.
#   GELB = die echte Geometrie (AABB des "Visual"-Knotens) — das, was man sieht.
# Sitzt ein Reifen mit Abstand am Fluegel, liegt die cyane Box bundig an und die gelbe endet
# vorher: dann ist die Kollisionsbox des GETROFFENEN Teils dicker als sein Modell (ein
# duenner Fluegel in einer kastenfoermigen Pickbox), nicht der Reifen falsch.
func set_debug_boxes(on: bool) -> void:
	debug_boxes = on
	_update_debug_boxes()


func _update_debug_boxes() -> void:
	if _dbg_root != null and is_instance_valid(_dbg_root):
		# Erst aushaengen, dann freigeben: queue_free() wirkt erst am Frame-Ende, der Name
		# waere sonst noch belegt und ein sofortiges Wieder-Einschalten legte "DebugBoxen2" an.
		var par := _dbg_root.get_parent()
		if par != null:
			par.remove_child(_dbg_root)
		_dbg_root.queue_free()
	_dbg_root = null
	if not debug_boxes or design_root == null:
		return
	_dbg_root = Node3D.new()
	_dbg_root.name = "DebugBoxen"
	design_root.add_child(_dbg_root)
	for kind in design_root.get_children():
		var part := kind as Node3D
		if part == null or not part.has_meta("part_id"):
			continue
		var psc: Vector3 = part.get_meta("pscale", Vector3.ONE)
		var b := _part_box(part)              # Sternmotor: je nach sichtbarer Variante
		_dbg_root.add_child(_wire_box(part.transform, (b[1] as Vector3) * psc,
			(b[0] as Vector3) * psc * 0.5, Color(0.15, 0.95, 1.0)))
		var vis := part.get_node_or_null("Visual") as Node3D
		if vis == null:
			continue
		var ab := _visual_local_aabb(part, vis)
		if ab.size.length() > 0.0001:
			_dbg_root.add_child(_wire_box(part.transform, ab.get_center(), ab.size * 0.5,
				Color(1.0, 0.85, 0.1)))


# AABB aller Meshes des Visuals, ausgedrueckt im LOKALEN System des Teils (damit die Box
# mit derselben Teil-Transform gezeichnet werden kann wie die Kollisionsbox).
func _visual_local_aabb(part: Node3D, vis: Node3D) -> AABB:
	var inv := part.global_transform.affine_inverse()
	var ab := AABB()
	var erst := true
	for n in vis.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if not vi.visible:
			continue                          # ausgeblendete Varianten (Full/Half, Rahmen)
		var lokal := inv * vi.global_transform
		var box: AABB = vi.get_aabb()
		for sx in [0.0, 1.0]:
			for sy in [0.0, 1.0]:
				for sz in [0.0, 1.0]:
					var p: Vector3 = lokal * (box.position
						+ Vector3(sx * box.size.x, sy * box.size.y, sz * box.size.z))
					if erst:
						ab = AABB(p, Vector3.ZERO)
						erst = false
					else:
						ab = ab.expand(p)
	return ab


func _wire_box(t: Transform3D, ctr: Vector3, half: Vector3, col: Color) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true                    # durch das Modell hindurch sichtbar
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	var e: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				e.append(ctr + Vector3(sx * half.x, sy * half.y, sz * half.z))
	# Index = 4*ix + 2*iy + iz (0 = Minus-Seite) -> beide X-Flaechen plus die vier Holme
	for k in [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4],
			[0, 4], [1, 5], [2, 6], [3, 7]]:
		im.surface_add_vertex(e[k[0]])
		im.surface_add_vertex(e[k[1]])
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.transform = t
	return mi


func _update_float_markers() -> void:
	for m in _float_markers:
		if is_instance_valid(m):
			m.queue_free()
	_float_markers.clear()
	for fp in floating_parts():
		var ab := _part_world_aabb(fp)
		var mk := _make_marker(Color(1.0, 0.25, 0.2))
		mk.scale = Vector3(1.6, 1.6, 1.6)
		mk.position = fp.position + Vector3(0, ab.size.y * 0.5 + 0.6, 0)
		design_root.add_child(mk)
		_float_markers.append(mk)


func _make_markers() -> void:
	com_marker = _make_marker(Color(1.0, 0.85, 0.1))
	col_marker = _make_marker(Color(0.2, 0.7, 1.0))
	design_root.add_child(com_marker)
	design_root.add_child(col_marker)


func _make_marker(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	return mi
