## FlightController.gd
## Baut aus einem Design einen fliegenden AircraftBody, übernimmt Steuerung,
## Verfolgerkamera und liefert Telemetrie fürs HUD.
class_name FlightController
extends Node3D

signal hud_changed(data: Dictionary)

const AIRCRAFT_LAYER := 4
const GROUND_LAYER := 1
const SPAWN := Vector3(0, 2.2, 35.0)

var camera: Camera3D
var aircraft: AircraftBody
var design: Array = []
var throttle := 0.0
var spawn_height := 2.0


func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)


func set_camera(c: Camera3D) -> void:
	camera = c


func set_active(active: bool) -> void:
	set_process(active)
	set_physics_process(active)
	set_process_unhandled_input(active)
	if active and aircraft:
		_snap_camera()


# ---------------------------------------------------------------------------
# Flugzeug aus Design bauen
# ---------------------------------------------------------------------------
func build_from_design(d: Array) -> void:
	clear_aircraft()
	design = d
	var body := AircraftBody.new()
	body.collision_layer = AIRCRAFT_LAYER
	body.collision_mask = GROUND_LAYER

	var total_mass := 0.0
	var com := Vector3.ZERO
	var engines: Array = []
	var props: Array = []
	var thrust_total := 0.0
	var min_y := INF
	var wing_area := 0.0
	var ar_sum := 0.0
	var lift_sum := 0.0
	var pitch_area := 0.0
	var roll_area := 0.0
	var yaw_area := 0.0
	var gear_items: Array = []
	var gear_cap := 0.0
	var wing_cap := 0.0
	var drag_area := 0.0
	var part_infos: Array = []

	for item in d:
		var id: String = item.get("id", "")
		if not PartCatalog.has(id):
			continue
		var p := PartCatalog.get_part(id)
		var xf: Transform3D = item.get("xform", Transform3D())

		var vis := PartCatalog.build_visual(p, item.get("color", Color(0, 0, 0, 0)))
		vis.transform = xf
		body.add_child(vis)
		var prop := vis.find_child("Prop", true, false)
		if prop:
			props.append(prop)

		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = PartCatalog.col_size(p)
		cs.shape = box
		# Korrekte (ggf. gespiegelte) Box-Mitte, aber mit proper Orientierung
		# (det > 0), sonst wird der Trägheitstensor fehlerhaft -> Physik-Explosion.
		var cob: Vector3 = PartCatalog.col_offset(p)
		var center_local: Vector3 = xf * cob
		var ori := xf.basis.orthonormalized()
		if ori.determinant() < 0.0:
			ori.x = -ori.x
		cs.transform = Transform3D(ori, center_local)
		body.add_child(cs)
		part_infos.append({
			"vis": vis, "cs": cs, "xform": xf, "csize": box.size, "coffset": cob,
			"is_wing": p.get("is_wing", false), "control": p.get("control", ""),
		})
		# tiefsten Punkt fürs Aufsetzen auf der Bahn ermitteln
		var ext: Vector3 = box.size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var corner: Vector3 = xf * (cob + Vector3(sx * ext.x, sy * ext.y, sz * ext.z))
					min_y = minf(min_y, corner.y)

		var m: float = p.get("mass", 0.0)
		total_mass += m
		com += m * xf.origin

		drag_area += PartCatalog.part_drag(p)
		if p.get("is_wing", false):
			var a: float = p.get("area", 0.0)
			var span: float = p.get("span", sqrt(maxf(a, 0.01)))
			var ar: float = clampf(span * span / maxf(a, 0.01), 0.6, 10.0)
			wing_cap += a * PartCatalog.WING_STRESS   # volle Fläche zählt strukturell
			# Orientierung: nur der waagerechte Anteil erzeugt Auftrieb;
			# der gekippte/senkrechte Anteil wirkt als Rollsteuerung.
			var up_align: float = clampf(absf(xf.basis.y.dot(Vector3.UP)), 0.0, 1.0)
			var lift_part: float = a * up_align
			var ctrl_part: float = a * (1.0 - up_align)
			wing_area += lift_part
			ar_sum += lift_part * ar
			lift_sum += lift_part * p.get("lift", 1.0)
			match p.get("control", ""):
				"pitch": pitch_area += a
				"roll": roll_area += a
				"yaw": yaw_area += a
				_: roll_area += ctrl_part            # gekippter Normalflügel hilft rollen
		var thr: float = p.get("thrust", 0.0)
		if thr > 0.0:
			engines.append({"pos": xf.origin, "thrust": thr, "jet": p.get("jet", false)})
			thrust_total += thr
		var cap: float = p.get("gear_capacity", 0.0)
		if cap > 0.0:
			gear_cap += cap
			gear_items.append({"vis": vis, "cs": cs, "retract": p.get("retract", false), "base": xf})

	if total_mass > 0.0:
		com /= total_mass

	# Spawn-Höhe so, dass der tiefste Punkt knapp über der Bahn liegt
	if min_y == INF:
		min_y = -1.0
	spawn_height = 0.3 - min_y

	body.mass = max(total_mass, 1.0)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = com
	body.wing_area = wing_area
	body.eff_ar = (ar_sum / wing_area) if wing_area > 0.0 else 4.0
	body.lift_scale = (lift_sum / wing_area) if wing_area > 0.0 else 1.0
	body.pitch_area = pitch_area
	body.roll_area = roll_area
	body.yaw_area = yaw_area
	body.engines = engines
	body.props = props
	body.total_thrust = thrust_total
	body.gear_items = gear_items
	body.gear_capacity = gear_cap
	body.gear_overloaded = gear_cap > 0.0 and total_mass > gear_cap
	body.wing_capacity = wing_cap
	body.drag_area = drag_area
	body.parts = part_infos

	add_child(body)
	aircraft = body
	throttle = 0.0
	_place_at_spawn()


func clear_aircraft() -> void:
	if is_instance_valid(aircraft):
		aircraft.queue_free()
	aircraft = null
	# herumliegende Trümmer entfernen
	for c in get_children():
		if c.is_in_group("debris"):
			c.queue_free()


func _place_at_spawn() -> void:
	if not is_instance_valid(aircraft):
		return
	aircraft.global_transform = Transform3D(Basis(), Vector3(0.0, spawn_height, 40.0))
	aircraft.linear_velocity = Vector3.ZERO
	aircraft.angular_velocity = Vector3.ZERO
	throttle = 0.0
	aircraft.throttle = 0.0
	aircraft.in_pitch = 0.0
	aircraft.in_roll = 0.0
	aircraft.in_yaw = 0.0
	aircraft.reset_gear()
	_snap_camera()


# Reset (Enter): Flugzeug komplett neu aufbauen -> repariert Flügel/Fahrwerk
func _reset_to_runway() -> void:
	if design.is_empty():
		return
	build_from_design(design)


# ---------------------------------------------------------------------------
# Steuerung
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if not is_instance_valid(aircraft):
		return

	# Schub (unter 0 % = bremsen)
	if Input.is_key_pressed(KEY_SHIFT):
		throttle += 0.6 * delta
	if Input.is_key_pressed(KEY_CTRL):
		throttle -= 0.6 * delta
	throttle = clamp(throttle, -0.4, 1.0)

	# Pitch (S/↓ = Nase hoch, W/↑ = Nase runter)
	var pitch := 0.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pitch += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pitch -= 1.0
	# Roll — A und D vertauscht (A = rechts, D = links)
	var roll := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		roll += 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		roll -= 1.0
	# Yaw (C = rechts, Z = links) — Q ist jetzt der Invertieren-Schalter
	var yaw := 0.0
	if Input.is_physical_key_pressed(KEY_C):
		yaw += 1.0
	if Input.is_physical_key_pressed(KEY_Z):
		yaw -= 1.0

	aircraft.throttle = throttle
	aircraft.in_pitch = pitch
	aircraft.in_roll = roll
	aircraft.in_yaw = yaw

	_emit_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_BACKSPACE or event.keycode == KEY_KP_ENTER:
			_reset_to_runway()
		elif event.keycode == KEY_T and is_instance_valid(aircraft):
			aircraft.assist = not aircraft.assist
		elif event.keycode == KEY_G and is_instance_valid(aircraft):
			aircraft.toggle_gear()
		elif event.keycode == KEY_Q and is_instance_valid(aircraft):
			aircraft.toggle_invert()


# ---------------------------------------------------------------------------
# Verfolgerkamera
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if camera == null or not is_instance_valid(aircraft):
		return
	var t := aircraft.global_transform
	var desired := t.origin + t.basis.z.normalized() * 11.0 + Vector3.UP * 3.8
	camera.global_position = camera.global_position.lerp(desired, clamp(delta * 4.0, 0.0, 1.0))
	camera.look_at(t.origin + Vector3.UP * 0.8, Vector3.UP)


func _snap_camera() -> void:
	if camera == null or not is_instance_valid(aircraft):
		return
	var t := aircraft.global_transform
	camera.global_position = t.origin + t.basis.z.normalized() * 11.0 + Vector3.UP * 3.8
	camera.look_at(t.origin + Vector3.UP * 0.8, Vector3.UP)


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------
func _emit_hud() -> void:
	if not is_instance_valid(aircraft):
		return
	hud_changed.emit({
		"throttle": throttle,
		"speed": aircraft.airspeed,
		"kmh": aircraft.airspeed * 3.6,
		"alt": aircraft.altitude,
		"aoa": aircraft.aoa_deg,
		"climb": aircraft.climb,
		"stall": aircraft.stall,
		"gforce": aircraft.gforce,
		"thrust": aircraft.total_thrust,
		"assist": aircraft.assist,
		"gear": aircraft.gear_status,
		"wings": aircraft.wing_status,
		"inverted": aircraft.inverted,
		"land_msg": aircraft.landing_msg,
	})
