## BuildController.gd
## Der Hangar-Editor: Orbit-Kamera, flächenbündiges Anrasten von Teilen,
## Ghost-Vorschau, Symmetrie-Modus, Löschen, Live-Statistik.
class_name BuildController
extends Node3D

signal design_changed(stats: Dictionary)

const BUILD_LAYER := 2

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
var _orbiting := false       # rechte Maus
var _panning := false        # mittlere Maus
var _left_orbit := false     # linke Maus auf leeren Raum -> drehen

# Drag & Snap
var _carrying := false       # gerade wird ein Teil mit der Maus gezogen
var carry_id := ""
var _carry_existing := false # vorhandenes Teil aufgenommen (vs. neues aus Palette)
var _carry_orig := Transform3D()
var _carry_had_mirror := false

# Lackieren & Undo/Redo
var paint_mode := false
var paint_color := Color(0.86, 0.22, 0.20)
var wind_tunnel := false     # Windkanal-Ansicht (Pro-Teil-Heatmap + Luftströmung)
var wind_worst := ""         # Teil mit dem höchsten Flug-Widerstand
var _tunnel_particles: CPUParticles3D
var _history: Array = []
var _hist_i := -1
var _suppress_history := false

# letzte Vorschau
var _last_valid := false
var _last_xform := Transform3D()

var com_marker: MeshInstance3D
var col_marker: MeshInstance3D


func _ready() -> void:
	design_root = Node3D.new()
	design_root.name = "DesignRoot"
	add_child(design_root)
	_make_markers()
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
	if ghost:
		ghost.visible = false
	if active:
		_update_camera()


func _active_id() -> String:
	return carry_id if _carrying else brush_id


# ---------------------------------------------------------------------------
# Kamera & Vorschau
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	# Tastatur-Zoom (+/- bzw. Numpad)
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
		orbit_dist -= 28.0 * delta
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		orbit_dist += 28.0 * delta
	_update_camera()


func _physics_process(_delta: float) -> void:
	_update_ghost()


func _update_camera() -> void:
	if camera == null:
		return
	orbit_pitch = clamp(orbit_pitch, -1.4, 1.4)
	orbit_dist = clamp(orbit_dist, 2.5, 110.0)
	var dir := Vector3(
		cos(orbit_pitch) * sin(orbit_yaw),
		sin(orbit_pitch),
		cos(orbit_pitch) * cos(orbit_yaw))
	camera.global_position = orbit_focus + dir * orbit_dist
	camera.look_at(orbit_focus, Vector3.UP)


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
				_orbiting = event.pressed
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
				else:
					_on_left_release()
	elif event is InputEventMagnifyGesture:        # Trackpad-Pinch zum Zoomen
		orbit_dist /= maxf(event.factor, 0.01)
	elif event is InputEventPanGesture:            # Zwei-Finger-Scroll zum Zoomen
		orbit_dist += event.delta.y * 0.6
	elif event is InputEventMouseMotion:
		if _carrying:
			pass # Ghost folgt der Maus in _update_ghost()
		elif _orbiting or _left_orbit:
			orbit_yaw -= event.relative.x * 0.01
			orbit_pitch += event.relative.y * 0.01
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
			return
		match event.keycode:
			KEY_R:
				ghost_rot = (ghost_rot + 1) % 4
			KEY_F:
				reset_camera()
			KEY_ESCAPE:
				if _carrying:
					_cancel_carry()
				else:
					set_brush("")
			KEY_X, KEY_DELETE:
				_delete_hovered()
			KEY_M:
				symmetry = not symmetry


# Linke Maustaste gedrückt: Teil aufnehmen / platzieren / Kamera drehen
func _on_left_press() -> void:
	var hit := _raycast_mouse()
	if erase_mode:
		_delete_hovered()
		return
	if paint_mode:
		_paint_hovered(hit)
		return
	if brush_id != "":
		# Neues Teil aus der Palette: bei gültigem Snap "in die Hand nehmen"
		if _compute_snap_for(brush_id, hit).get("valid", false):
			carry_id = brush_id
			_carry_existing = false
			_carrying = true
			_rebuild_ghost()
		else:
			_left_orbit = true   # auf leeren Raum geklickt -> drehen
		return
	# Kein Teil gewählt: vorhandenes Teil greifen, sonst Kamera drehen
	var part := _part_from_hit(hit)
	if part != null and not part.get_meta("is_root", false):
		carry_id = part.get_meta("part_id")
		_carry_existing = true
		_carry_orig = part.transform
		_carry_had_mirror = part.has_meta("mirror")
		if _carry_had_mirror:
			var m = part.get_meta("mirror")
			if is_instance_valid(m):
				m.free()
		part.free()
		_carrying = true
		_rebuild_ghost()
		_notify_changed()
	else:
		_left_orbit = true


func _on_left_release() -> void:
	if _carrying:
		var placed := false
		var snap := _compute_snap_for(carry_id, _raycast_mouse())
		if snap.get("valid", false):
			_place_id(carry_id, snap["xform"])
			placed = true
		elif _carry_existing:
			_place_id(carry_id, _carry_orig)  # ungültig abgelegt -> zurück
			placed = true
		_carrying = false
		_carry_existing = false
		carry_id = ""
		_rebuild_ghost()
		if placed:
			_push_history()
		_notify_changed()
	_left_orbit = false


func _cancel_carry() -> void:
	if not _carrying:
		return
	if _carry_existing:
		_place_id(carry_id, _carry_orig)
	_carrying = false
	_carry_existing = false
	carry_id = ""
	_rebuild_ghost()
	_notify_changed()


# ---------------------------------------------------------------------------
# Platzierung
# ---------------------------------------------------------------------------
func set_brush(id: String) -> void:
	brush_id = id
	if id != "":
		erase_mode = false
		paint_mode = false
	ghost_rot = 0
	_rebuild_ghost()


func set_erase_mode(b: bool) -> void:
	erase_mode = b
	if b:
		brush_id = ""
		paint_mode = false
	_rebuild_ghost()


func set_paint_mode(b: bool) -> void:
	paint_mode = b
	if b:
		brush_id = ""
		erase_mode = false
	_rebuild_ghost()


func set_paint_color(c: Color) -> void:
	paint_color = c
	paint_mode = true
	brush_id = ""
	erase_mode = false
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
	_update_camera()


# --- Windkanal-Ansicht: Pro-Teil-Widerstands-Heatmap + Luftströmung --------
func set_wind_tunnel(b: bool) -> void:
	wind_tunnel = b
	if b:
		_build_wind_tunnel()
	else:
		_clear_wind_tunnel()


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


# Färbt jedes Teil nach seinem Flug-Widerstand: grün (wenig) -> rot (viel).
# Bezug = größter Wert im Design (mit Untergrenze), damit ein sauberes
# Flugzeug grün bleibt und nur echte Problemteile rot werden.
func _apply_drag_heatmap() -> void:
	var max_d := 0.0
	wind_worst = ""
	for child in design_root.get_children():
		if not child.is_in_group("part"):
			continue
		var p := PartCatalog.get_part(child.get_meta("part_id"))
		var dd: float = PartCatalog.part_drag(p)
		if dd > max_d:
			max_d = dd
			wind_worst = p.get("name", "")
	var denom := maxf(max_d, 0.6)
	for child in design_root.get_children():
		if not child.is_in_group("part"):
			continue
		var dd: float = PartCatalog.part_drag(PartCatalog.get_part(child.get_meta("part_id")))
		var frac := clampf(dd / denom, 0.0, 1.0)
		_tint(child.get_node_or_null("Visual"), _drag_color(frac), frac)


func _drag_color(f: float) -> Color:
	if f < 0.5:
		return Color(0.18, 0.85, 0.30).lerp(Color(0.97, 0.86, 0.15), f * 2.0)
	return Color(0.97, 0.86, 0.15).lerp(Color(0.97, 0.16, 0.12), (f - 0.5) * 2.0)


func _tint(node: Node, c: Color, emis: float) -> void:
	if node == null:
		return
	for ch in node.get_children():
		_tint(ch, c, emis)
	if node is MeshInstance3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if emis > 0.55:                       # heiße Teile glühen leicht -> stechen heraus
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = (emis - 0.55) * 2.2
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
func _place_id(id: String, t: Transform3D) -> void:
	if id == "":
		return
	var part := _make_part(id, t)
	if symmetry and absf(t.origin.x) > 0.15:
		var mt := _mirror_xform(t)
		var mpart := _make_part(id, mt)
		part.set_meta("mirror", mpart)
		mpart.set_meta("mirror", part)


func _delete_hovered() -> void:
	var part := _part_from_hit(_raycast_mouse())
	if part == null or part.get_meta("is_root", false):
		return
	if part.has_meta("mirror"):
		var m = part.get_meta("mirror")
		if is_instance_valid(m):
			m.free()
	part.free()
	_push_history()
	_notify_changed()


func _make_part(id: String, xform: Transform3D, col := Color(0, 0, 0, 0)) -> Node3D:
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
	body.collision_layer = BUILD_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = PartCatalog.col_size(p)
	cs.shape = box
	cs.transform = Transform3D(Basis(), PartCatalog.col_offset(p))
	body.add_child(cs)
	part.add_child(body)
	design_root.add_child(part)
	return part


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
func _raycast_mouse() -> Dictionary:
	if camera == null:
		return {}
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var to := from + camera.project_ray_normal(mp) * 2000.0
	var space := get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = BUILD_LAYER
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
			})
	return out


func load_design(arr: Array) -> void:
	_clear_nodes()
	for item in arr:
		var id: String = item.get("id", "")
		if PartCatalog.has(id):
			_make_part(id, item.get("xform", Transform3D()), item.get("color", Color(0, 0, 0, 0)))
	_ensure_root()
	if not _suppress_history:
		_seed_history()
	_notify_changed()


func clear_design() -> void:
	_clear_nodes()
	_make_part("cockpit", Transform3D(Basis(), Vector3.ZERO))
	_push_history()
	_notify_changed()


func _clear_nodes() -> void:
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
	var drag_worst := ""
	var drag_worst_v := 0.0
	var com := Vector3.ZERO
	var col := Vector3.ZERO
	var col_w := 0.0
	for child in design_root.get_children():
		if not child.is_in_group("part"):
			continue
		var p := PartCatalog.get_part(child.get_meta("part_id"))
		var m: float = p.get("mass", 0.0)
		mass += m
		n += 1
		thrust += p.get("thrust", 0.0)
		gear_cap += p.get("gear_capacity", 0.0)
		var pd: float = PartCatalog.part_drag(p)
		drag_area += pd
		if pd > drag_worst_v:
			drag_worst_v = pd
			drag_worst = p.get("name", "")
		com += m * child.position
		if p.get("is_wing", false):
			var a: float = p.get("area", 0.0)
			area += a
			wing_cap += a * PartCatalog.WING_STRESS
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
		"drag_worst": drag_worst,
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
	design_changed.emit(stats)


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
