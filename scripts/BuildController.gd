## BuildController.gd
## Der Hangar-Editor: Orbit-Kamera, flächenbündiges Anrasten von Teilen,
## Ghost-Vorschau, Symmetrie-Modus, Löschen, Live-Statistik.
class_name BuildController
extends Node3D

signal design_changed(stats: Dictionary)
signal selection_changed(info: Dictionary)   # {} = nichts gewählt; sonst {name, scale, is_root}

const BUILD_LAYER := 2
const HANDLE_LAYER := 8       # Transform-Griffe (eigener Raycast-Layer)

var camera: Camera3D

var design_root: Node3D
var ghost: Node3D
var brush_id := ""           # aktuell gewähltes Teil aus der Palette ("" = kein Teil)
var erase_mode := false      # Abriss-Werkzeug
var symmetry := true
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
var _moving_sel := false          # ausgewähltes Teil per Body-Drag verschieben
var _move_plane := Plane()
var _move_grab := Vector3.ZERO
var _edit_xf0 := Transform3D()    # Snapshot bei Drag-Beginn (History nur bei echter Änderung)
var _edit_sc0 := Vector3.ONE
# Blender-artiges Gizmo: Modus 0=Bewegen (Pfeile) · 1=Drehen (ziehen) · 2=Skalieren (Würfel).
# Tasten G/R/S. Vorhandenes Teil anklicken = auswählen, dann je nach Modus bearbeiten.
const GIZ_MOVE := 0
const GIZ_ROTATE := 1
const GIZ_SCALE := 2
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
		camera.size = orbit_dist
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	var up := Vector3.UP if _ortho_view != 3 else Vector3(0, 0, -1)  # Oben-Ansicht: Nase nach oben im Bild
	camera.look_at(orbit_focus, up)


func _update_ghost() -> void:
	var id := _active_id()
	if ghost == null or id == "":
		if ghost:
			ghost.visible = false
		return
	var snap := _compute_snap_for(id, _raycast_mouse())
	if snap.get("valid", false):
		_last_valid = true
		_last_xform = snap["xform"]
		ghost.transform = _last_xform
		ghost.visible = true
	else:
		_last_valid = false
		ghost.visible = false


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
				_place_id(carry_id, snap["xform"], _carry_scale, _carry_color)
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
	_emit_selection()


func _deselect() -> void:
	selected_part = null
	_drag_handle = null
	_moving_sel = false
	_rotating = false
	_clear_handles()
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
	})


# --- Aktionen auf das ausgewählte Teil (vom UI-Panel aufgerufen) -----------
func nudge_scale(axis: int, factor: float) -> void:
	if selected_part == null:
		return
	var sc: Vector3 = selected_part.get_meta("pscale", Vector3.ONE)
	var v := [sc.x, sc.y, sc.z]
	v[axis] = clampf(float(v[axis]) * factor, 0.25, 6.0)
	var new_sc := Vector3(v[0], v[1], v[2])
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
	if selected_part == null or selected_part.get_meta("is_root", false):
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
	var part := _part_from_hit(_raycast_mouse(BUILD_LAYER))
	if part == null:
		return
	if part != selected_part:
		_select_part(part)
	var is_root: bool = bool(part.get_meta("is_root", false))
	_ctx_menu.clear()
	_ctx_menu.add_item("✥  Bewegen", 0)
	_ctx_menu.add_item("⟳  Drehen", 1)
	_ctx_menu.add_item("⤢  Skalieren", 2)
	_ctx_menu.add_separator()
	_ctx_menu.add_item("↺  Umdrehen (180°)", 3)
	_ctx_menu.add_item("🗑  Löschen", 4)
	_ctx_menu.set_item_disabled(_ctx_menu.get_item_index(4), is_root)
	_ctx_menu.reset_size()
	_ctx_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))


func _on_ctx_id(id: int) -> void:
	match id:
		0: set_gizmo_mode(GIZ_MOVE)
		1: set_gizmo_mode(GIZ_ROTATE)
		2: set_gizmo_mode(GIZ_SCALE)
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
	var id: String = selected_part.get_meta("part_id")
	if id == "":
		return
	var xf := selected_part.transform
	var off := Vector3(1.2, 0.0, 0.0)
	if camera != null:
		off = camera.global_transform.basis.x.normalized() * 1.3   # nach Bildschirm-rechts versetzt
	xf.origin += off
	var sc: Vector3 = selected_part.get_meta("pscale", Vector3.ONE)
	var cl: Color = selected_part.get_meta("color", Color(0, 0, 0, 0))
	var np := _place_id(id, xf, sc, cl)
	_push_history()
	_notify_changed()
	if np != null:
		_select_part(np)


# Ausgewähltes Teil um delta (Weltachsen) verschieben (Pfeiltasten-Feinjustage).
func nudge_selected(delta_world: Vector3) -> void:
	if selected_part == null:
		return
	_apply_sel_transform(selected_part.transform.basis,
		selected_part.position + delta_world,
		selected_part.get_meta("pscale", Vector3.ONE))
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
	else:
		# Bewegen/Drehen: welt-ausgerichteter Halter (dreht NICHT mit dem Teil)
		_gizmo_root = Node3D.new()
		design_root.add_child(_gizmo_root)
		if gizmo_mode == GIZ_MOVE:
			_build_move_handles()
		else:
			_build_rotate_handles()
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
		# Collider entlang der Achse (greifbarer Schaft)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		if i == 0: box.size = Vector3(1.5, 0.4, 0.4)
		elif i == 1: box.size = Vector3(0.4, 1.5, 0.4)
		else: box.size = Vector3(0.4, 0.4, 1.5)
		cs.shape = box
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
	var part := _part_from_hit(_raycast_mouse(BUILD_LAYER))
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


# Gizmo-Modus setzen (0=Bewegen 1=Drehen 2=Skalieren) und Griffe neu aufbauen.
func set_gizmo_mode(m: int) -> void:
	gizmo_mode = clampi(m, 0, 2)
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
	_drag_sign = handle.get_meta("sign")
	_drag_scale0 = selected_part.get_meta("pscale", Vector3.ONE)
	_drag_origin0 = selected_part.position
	if _drag_kind == "move":
		_drag_axis_w = _axis_vec(_drag_axis_i) * _drag_sign   # WELT-Achse (global, nicht lokal)
	else:  # scale -> lokale Teil-Achse strecken
		_drag_axis_w = (selected_part.global_transform.basis * _axis_vec(_drag_axis_i)).normalized() * _drag_sign
	_drag_t0 = _ray_axis_t(_drag_origin0, _drag_axis_w)


func _begin_move() -> void:
	_moving_sel = true
	_drag_handle = null
	_edit_xf0 = selected_part.transform
	_edit_sc0 = selected_part.get_meta("pscale", Vector3.ONE)
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
		_apply_sel_transform(selected_part.transform.basis, origin, _drag_scale0)
	elif _drag_handle != null and _drag_kind == "rotate":
		# Ring ziehen -> um die WELT-Achse drehen (Winkel aus der Maus in der Ringebene)
		var a := _ring_angle()
		var nb := (Basis(_rot_axis_w, a - _rot_a0) * _rot_b0).orthonormalized()
		_apply_sel_transform(nb, selected_part.position, selected_part.get_meta("pscale", Vector3.ONE))
	elif _drag_handle != null:
		var p := PartCatalog.get_part(selected_part.get_meta("part_id"))
		var bs: Vector3 = PartCatalog.col_size(p)
		var i := _drag_axis_i
		var base_i: float = [bs.x, bs.y, bs.z][i]
		var s0: float = [_drag_scale0.x, _drag_scale0.y, _drag_scale0.z][i]
		var half0: float = base_i * s0 * 0.5
		var t := _ray_axis_t(_drag_origin0, _drag_axis_w)
		var new_half: float = maxf(half0 + (t - _drag_t0), base_i * 0.125)
		var new_s: float = clampf(new_half * 2.0 / base_i, 0.25, 6.0)
		var sc := _drag_scale0
		if i == 0:
			sc.x = new_s
		elif i == 1:
			sc.y = new_s
		else:
			sc.z = new_s
		# Mittelpunkt um die VOLLE Größenänderung verschieben -> die gegenüberliegende
		# (angeheftete) Fläche bleibt exakt fix -> kein Spalt/Überlappung zum Nachbarteil.
		var moved: float = base_i * new_s * 0.5 - half0
		var origin := _drag_origin0 + _drag_axis_w * moved
		_apply_sel_transform(selected_part.transform.basis, origin, sc)
	elif _moving_sel:
		var newpos := _plane_ray() - _move_grab
		_apply_sel_transform(selected_part.transform.basis, newpos, selected_part.get_meta("pscale", Vector3.ONE))


# Wendet Basis/Origin/Skalierung auf das gewählte Teil an und hält die Symmetrie aktuell.
func _apply_sel_transform(new_basis: Basis, origin: Vector3, sc: Vector3) -> void:
	selected_part.transform = Transform3D(new_basis, origin)
	_apply_part_scale(selected_part, sc)
	_sync_mirror(selected_part, sc)
	_update_handles()
	_notify_changed()


# Spiegelteil dynamisch erzeugen/aktualisieren beim Verschieben/Drehen/Skalieren, damit der
# Symmetrie-Modus auch nachträglich greift (vorher nur beim Platzieren).
func _sync_mirror(part: Node3D, sc: Vector3) -> void:
	var m = part.get_meta("mirror") if part.has_meta("mirror") else null
	var m_valid := is_instance_valid(m)
	var want: bool = symmetry and not bool(part.get_meta("is_root", false)) and absf(part.position.x) > 0.15
	if want and not m_valid:
		# Symmetrie an, Teil außermittig, aber noch kein Spiegel -> neuen erzeugen
		m = _make_part(part.get_meta("part_id"), _mirror_xform(part.transform),
			part.get_meta("color", Color(0, 0, 0, 0)), sc)
		part.set_meta("mirror", m)
		m.set_meta("mirror", part)
	elif m_valid:
		# vorhandenen Spiegel mitziehen (folgt auch bei ausgeschalteter Symmetrie)
		m.transform = _mirror_xform(part.transform)
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


func _transform_release() -> void:
	# History nur, wenn sich wirklich was geändert hat (reiner Auswahl-Klick -> kein Undo-Müll).
	if (_drag_handle != null or _moving_sel or _rotating) and selected_part != null:
		var moved_sc: Vector3 = selected_part.get_meta("pscale", Vector3.ONE)
		var changed: bool = selected_part.transform != _edit_xf0 or moved_sc != _edit_sc0
		if changed:
			_push_history()
			_notify_changed()
	_drag_handle = null
	_moving_sel = false
	_rotating = false
	_left_orbit = false


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


# --- Lackieren --------------------------------------------------------------
func _paint_hovered(hit: Dictionary) -> void:
	var part := _part_from_hit(hit)
	if part == null:
		return
	_recolor(part, paint_color)
	if part.has_meta("mirror"):
		var m = part.get_meta("mirror")
		if is_instance_valid(m):
			_recolor(m, paint_color)
	_push_history()
	_notify_changed()


func _recolor(part: Node, c: Color) -> void:
	part.set_meta("color", c)
	var vis := part.get_node_or_null("Visual")
	if vis:
		vis.free()
	var nv := PartCatalog.build_visual(PartCatalog.get_part(part.get_meta("part_id")), c)
	nv.name = "Visual"
	nv.scale = part.get_meta("pscale", Vector3.ONE)
	part.add_child(nv)


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
	if node == null:
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
	for child in design_root.get_children():
		if child.is_in_group("part"):
			_recolor(child, child.get_meta("color", Color(0, 0, 0, 0)))
	if com_marker:
		com_marker.visible = true


# Platziert ein Teil (mit Symmetrie, falls aktiv und außermittig)
func _place_id(id: String, t: Transform3D, pscale := Vector3.ONE, col := Color(0, 0, 0, 0)) -> Node3D:
	if id == "":
		return null
	var part := _make_part(id, t, col, pscale)
	if symmetry and absf(t.origin.x) > 0.15:
		var mt := _mirror_xform(t)
		var mpart := _make_part(id, mt, col, pscale)
		part.set_meta("mirror", mpart)
		mpart.set_meta("mirror", part)
	return part


func _delete_hovered() -> void:
	var part := _part_from_hit(_raycast_mouse())
	if part == null or part.get_meta("is_root", false):
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
		pscale := Vector3.ONE) -> Node3D:
	var p := PartCatalog.get_part(id)
	var part := Node3D.new()
	part.add_to_group("part")
	part.set_meta("part_id", id)
	part.set_meta("is_root", p.get("root", false))
	part.set_meta("color", col)
	part.transform = xform
	var vis := PartCatalog.build_visual(p, col)
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
	var vis := part.get_node_or_null("Visual")
	if vis:
		(vis as Node3D).scale = pscale
	var cs := part.get_node_or_null("Pick/CollisionShape3D") as CollisionShape3D
	if cs == null:
		var body := part.get_node_or_null("Pick")
		if body:
			cs = body.get_child(0) as CollisionShape3D
	if cs and cs.shape is BoxShape3D:
		(cs.shape as BoxShape3D).size = PartCatalog.col_size(p) * pscale
		cs.transform = Transform3D(Basis(), PartCatalog.col_offset(p) * pscale)


# ---------------------------------------------------------------------------
# Snapping-Mathematik
# ---------------------------------------------------------------------------
func _compute_snap_for(id: String, hit: Dictionary) -> Dictionary:
	if id == "" or hit.is_empty():
		return {"valid": false}
	var part := _part_from_hit(hit)
	if part == null:
		return {"valid": false}
	var n: Vector3 = hit["normal"].normalized()
	var surface: Vector3 = hit["position"]
	var p := PartCatalog.get_part(id)
	if p.is_empty():
		return {"valid": false}

	if p.get("orient_normal", false):
		var ori := _orient_to_normal(n)
		if ghost_rot != 0:
			# R kippt den Flügel um die Sehne (0/30/60/90°): senkrecht -> Rollsteuerung
			ori = ori * Basis(Vector3(0, 0, 1), deg_to_rad(30.0 * ghost_rot))
		var origin := surface - n * 0.04
		origin = _snap_tangential(origin, n, 0.5)
		return {"valid": true, "xform": Transform3D(ori, origin)}
	else:
		var ori := Basis()
		if ghost_rot != 0:
			ori = Basis(Vector3.UP, deg_to_rad(90.0 * ghost_rot))
		var he: Vector3 = PartCatalog.col_size(p) * 0.5
		var support := absf(n.x) * he.x + absf(n.y) * he.y + absf(n.z) * he.z
		var origin := surface + n * support
		origin = _snap_tangential(origin, n, 0.25)
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


func _snap_tangential(origin: Vector3, n: Vector3, grid: float) -> Vector3:
	var snap_pos := origin.snapped(Vector3.ONE * grid)
	var along := (origin - snap_pos).dot(n)
	return snap_pos + n * along


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
func _raycast_mouse(mask := BUILD_LAYER) -> Dictionary:
	if camera == null:
		return {}
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var to := from + camera.project_ray_normal(mp) * 2000.0
	var space := get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = mask
	q.collide_with_areas = false
	return space.intersect_ray(q)


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
func _rebuild_ghost() -> void:
	if ghost:
		ghost.queue_free()
		ghost = null
	_last_valid = false
	var id := _active_id()
	if id == "" or not PartCatalog.has(id):
		return
	ghost = PartCatalog.build_visual(PartCatalog.get_part(id))
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
				"color": child.get_meta("color", Color(0, 0, 0, 0)),
				"scale": child.get_meta("pscale", Vector3.ONE),
			})
	return out


func load_design(arr: Array) -> void:
	_clear_nodes()
	for item in arr:
		var id: String = item.get("id", "")
		if PartCatalog.has(id):
			_make_part(id, item.get("xform", Transform3D()),
				item.get("color", Color(0, 0, 0, 0)), item.get("scale", Vector3.ONE))
	_ensure_root()
	_relink_mirrors()
	if not _suppress_history:
		_seed_history()
	_notify_changed()


# Nach dem Laden Spiegelpaare wieder verknüpfen (gleiche ID, an −x gespiegelte Position),
# damit der Symmetrie-Modus beim Verschieben/Drehen/Skalieren wieder greift und keine
# Duplikate erzeugt werden.
func _relink_mirrors() -> void:
	var parts: Array = []
	for c in design_root.get_children():
		if c.is_in_group("part"):
			parts.append(c)
	for a in parts:
		if a.has_meta("mirror") or a.get_meta("is_root", false) or absf(a.position.x) <= 0.15:
			continue
		var target: Vector3 = _mirror_xform(a.transform).origin
		for b in parts:
			if b == a or b.has_meta("mirror") or b.get_meta("is_root", false):
				continue
			if b.get_meta("part_id") == a.get_meta("part_id") and b.position.distance_to(target) < 0.06:
				a.set_meta("mirror", b)
				b.set_meta("mirror", a)
				break


func clear_design() -> void:
	_clear_nodes()
	_make_part("cockpit", Transform3D(Basis(), Vector3.ZERO))
	_push_history()
	_notify_changed()


func _clear_nodes() -> void:
	_deselect()
	for child in design_root.get_children():
		if child.is_in_group("part"):
			child.free()


func _ensure_root() -> void:
	for child in design_root.get_children():
		if child.is_in_group("part") and child.get_meta("is_root", false):
			return
	_make_part("cockpit", Transform3D(Basis(), Vector3.ZERO))


# ---------------------------------------------------------------------------
# Statistik & Marker
# ---------------------------------------------------------------------------
func compute_stats() -> Dictionary:
	var mass := 0.0
	var n := 0
	var area := 0.0
	var thrust := 0.0
	var gear_cap := 0.0
	var wing_cap := 0.0
	var drag_area := 0.0
	var com := Vector3.ZERO
	var col := Vector3.ZERO
	var col_w := 0.0
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
		thrust += p.get("thrust", 0.0) * vol
		gear_cap += p.get("gear_capacity", 0.0) * vol
		drag_area += PartCatalog.part_drag(p) * psc.x * psc.y
		com += m * child.position
		if p.get("is_wing", false):
			var a_full: float = p.get("area", 0.0) * psc.x * psc.z
			var span_w: float = p.get("span", sqrt(maxf(a_full, 0.01))) * psc.x
			# im Rumpf vergrabene Fläche zählt nicht (effektive Auftriebsfläche)
			var exp: float = PartCatalog.wing_exposed_fraction(child.transform, span_w, PartCatalog.col_offset(p).z * psc.z, body_boxes)
			var a: float = a_full * exp
			area += a
			wing_cap += a_full * PartCatalog.WING_STRESS
			col += a * child.position
			col_w += a
	if mass > 0.0:
		com /= mass
	if col_w > 0.0:
		col /= col_w
	var tw: float = thrust / max(mass * 9.81, 0.001)
	var max_g: float = wing_cap / max(mass * 9.81, 0.001)
	return {
		"mass": mass, "parts": n, "area": area, "thrust": thrust,
		"tw": tw, "com": com, "col": col, "col_valid": col_w > 0.0,
		"gear_cap": gear_cap, "gear_overload": gear_cap > 0.0 and mass > gear_cap,
		"has_gear": gear_cap > 0.0, "drag_area": drag_area,
		"max_g": max_g, "has_wings": wing_cap > 0.0,
	}


func _notify_changed() -> void:
	var stats := compute_stats()
	if com_marker:
		com_marker.position = stats["com"]
	if col_marker:
		col_marker.position = stats["col"]
		col_marker.visible = stats["col_valid"]
	if wind_tunnel:
		_apply_drag_heatmap()
	_update_float_markers()
	design_changed.emit(stats)


# --- Verbindungs-Prüfung: kein freies Schweben ----------------------------
# Welt-AABB der Teil-Box (rotiert), für Nachbarschafts-Test.
func _part_world_aabb(part: Node3D) -> AABB:
	var p := PartCatalog.get_part(part.get_meta("part_id"))
	var psc: Vector3 = part.get_meta("pscale", Vector3.ONE)
	var half: Vector3 = PartCatalog.col_size(p) * psc * 0.5
	var t := part.transform
	var center: Vector3 = t * (PartCatalog.col_offset(p) * psc)
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


func floating_count() -> int:
	return floating_parts().size()


# Rote Warn-Marker über frei schwebenden Teilen (nicht das Teil selbst einfärben).
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
