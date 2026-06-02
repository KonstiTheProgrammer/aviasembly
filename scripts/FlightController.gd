## FlightController.gd
## Baut aus einem Design einen fliegenden AircraftBody, übernimmt Steuerung,
## Verfolgerkamera und liefert Telemetrie fürs HUD.
class_name FlightController
extends Node3D

signal hud_changed(data: Dictionary)

const AIRCRAFT_LAYER := 4
const GROUND_LAYER := 1
const SPAWN := Vector3(0, 2.2, 35.0)

const LOOK_SENS := 0.006        # Maus-Empfindlichkeit fürs Umschauen
const LOOK_RECENTER := 0.6      # s ohne Mausbewegung -> Kamera schwenkt sanft zurück

# --- Maus-Flug (War-Thunder-Stil): Cursor zeigt wohin, Nase folgt -----------
const AIM_SENS := 0.0019        # Maus -> Steuermarker
const AIM_RADIUS_F := 0.32      # Marker-Bewegungsradius (Anteil kürzerer Bildkante)
const AIM_PITCH := 1.3          # Marker hoch/runter -> Nick-Auslenkung
const AIM_BANK_MAX := 1.05      # Marker ganz seitlich -> Soll-Querlage (~60°)
const AIM_BANK_P := 3.0         # Querlage-Fehler -> Soll-Rollrate
const AIM_ROLL_RATE_MAX := 1.8  # max. Rollrate (rad/s) -> verhindert Hochschaukeln/Überschwingen
const AIM_ROLL_P := 1.1         # Rollraten-Fehler -> Roll-Auslenkung
const AIM_TURN_PULL := 0.22     # etwas Höhenruder-Zug in der Kurve (hält die Nase oben)
const AIM_YAW := 0.35           # leicht koordiniert in Kurvenrichtung gieren

var camera: Camera3D
var aircraft: AircraftBody
var design: Array = []
var throttle := 0.0
var spawn_height := 2.0
var look_yaw := 0.0             # freies Umschauen (Maus) — horizontal
var look_pitch := 0.0           # vertikal
var _mouse_idle := 0.0
var mouse_fly := false          # Maus-Flug an? (Cursor lenkt, statt umzuschauen)
var _aim := Vector2.ZERO        # Steuermarker, normiert (-1..1) ums Bildzentrum
var aim_screen := Vector2.ZERO  # Pixelposition Steuermarker (fürs HUD)
var nose_screen := Vector2.ZERO # Pixelposition der aktuellen Nasenrichtung
# Survival-Upgrade-Multiplikatoren (von Main aus GameState gesetzt)
var thrust_mult := 1.0
var wing_mult := 1.0
var mass_mult := 1.0

# Waffen (feuerbar): Mündungs-Offsets je Typ, aus dem Design gesammelt
var weapons: Array = []        # [{type, off:Vector3 lokal, cd:float}]
var world_root: Node3D         # wohin Geschosse/Effekte gespawnt werden (von Main gesetzt)


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
	# Maus im Flug fangen (frei umschauen), im Hangar normal sichtbar.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE
	if active and aircraft:
		look_yaw = 0.0
		look_pitch = 0.0
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

	var min_y := INF
	var part_infos: Array = []   # je Teil: alle Aero-Beiträge (für Neuberechnung nach Bruch)
	weapons.clear()

	for item in d:
		var id: String = item.get("id", "")
		if not PartCatalog.has(id):
			continue
		var p := PartCatalog.get_part(id)
		var xf: Transform3D = item.get("xform", Transform3D())
		var psc: Vector3 = item.get("scale", Vector3.ONE)
		var vol: float = psc.x * psc.y * psc.z      # Volumen-Faktor (Masse/Traglast)

		var vis := PartCatalog.build_visual(p, item.get("color", Color(0, 0, 0, 0)))
		# Skalierung in die Basis einrechnen (NICHT vis.scale setzen): bei gespiegelten
		# Teilen ist die Basis improper (det<0); vis.scale würde die Spiegelung zerstören
		# -> Flügel klappt auf die andere Seite -> "halbes Flugzeug".
		vis.transform = Transform3D(xf.basis * Basis.from_scale(psc), xf.origin)
		body.add_child(vis)
		var prop := vis.find_child("Prop", true, false)

		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = PartCatalog.col_size(p) * psc
		cs.shape = box
		# Korrekte (ggf. gespiegelte) Box-Mitte, aber mit proper Orientierung
		# (det > 0), sonst wird der Trägheitstensor fehlerhaft -> Physik-Explosion.
		var cob: Vector3 = PartCatalog.col_offset(p) * psc
		var center_local: Vector3 = xf * cob
		var ori := xf.basis.orthonormalized()
		if ori.determinant() < 0.0:
			ori.x = -ori.x
		cs.transform = Transform3D(ori, center_local)
		body.add_child(cs)
		# tiefsten Punkt fürs Aufsetzen auf der Bahn ermitteln
		var ext: Vector3 = box.size * 0.5
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var corner: Vector3 = xf * (cob + Vector3(sx * ext.x, sy * ext.y, sz * ext.z))
					min_y = minf(min_y, corner.y)

		# Alle Aero-Beiträge pro Teil vorberechnen -> AircraftBody kann nach einem
		# Bruch das Modell aus den ÜBRIGEN Teilen neu zusammenrechnen.
		var pinfo := {
			"vis": vis, "cs": cs, "xform": xf, "csize": box.size, "coffset": cob,
			"pos": xf.origin, "prop": prop, "broken": false,
			"is_root": p.get("root", false),
			"is_wing": p.get("is_wing", false), "control": String(p.get("control", "")),
			"mass": p.get("mass", 0.0) * vol,
			"drag": PartCatalog.part_drag(p) * psc.x * psc.y,
			"lift_part": 0.0, "ar": 4.0, "lift_coef": 1.0, "wing_cap": 0.0,
			"pitch_a": 0.0, "roll_a": 0.0, "yaw_a": 0.0,
			"thrust": p.get("thrust", 0.0) * vol, "jet": p.get("jet", false),
			"gear_cap": p.get("gear_capacity", 0.0) * vol, "retract": p.get("retract", false),
		}
		if pinfo["is_wing"]:
			var a: float = p.get("area", 0.0) * psc.x * psc.z
			var span: float = p.get("span", sqrt(maxf(a, 0.01))) * psc.x
			var up_align: float = clampf(absf(xf.basis.y.dot(Vector3.UP)), 0.0, 1.0)
			pinfo["ar"] = clampf(span * span / maxf(a, 0.01), 0.6, 10.0)
			pinfo["lift_coef"] = p.get("lift", 1.0)
			pinfo["wing_cap"] = a * PartCatalog.WING_STRESS
			pinfo["lift_part"] = a * up_align
			var ctrl_part: float = a * (1.0 - up_align)
			match pinfo["control"]:
				"pitch": pinfo["pitch_a"] = a
				"roll": pinfo["roll_a"] = a
				"yaw": pinfo["yaw_a"] = a
				_: pinfo["roll_a"] = ctrl_part
		part_infos.append(pinfo)
		var wp := String(p.get("weapon", ""))
		if wp != "":
			weapons.append({"type": wp, "off": xf.origin, "cd": 0.0})

	# Spawn-Höhe so, dass der tiefste Punkt knapp über der Bahn liegt
	if min_y == INF:
		min_y = -1.0
	spawn_height = 0.3 - min_y

	body.parts = part_infos
	body.thrust_mult = thrust_mult
	body.wing_mult = wing_mult
	body.mass_mult = mass_mult
	add_child(body)
	body.recompute_aero()        # Masse/COM/Flächen/Schub/Fahrwerk aus den Teilen
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
	# Gieren / Seitenleitwerk (Q oder C = rechts, E oder Z = links)
	var yaw := 0.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_C):
		yaw += 1.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_Z):
		yaw -= 1.0

	# Maus-Flug: Steuermarker (Cursor) lenkt die Nase. Bank-to-turn -> der seitliche
	# Marker gibt eine SOLL-QUERLAGE vor, der Roll regelt nur die DIFFERENZ zur aktuellen
	# Querlage. So legt sich das Flugzeug auf eine feste Schräglage und HÄLT sie (fliegt die
	# Kurve) statt endlos zu rollen. Marker oben/unten = ziehen/drücken. Additiv zur Tastatur.
	if mouse_fly:
		var b := aircraft.global_transform.basis
		# Querlage MUSS gleiches Vorzeichen wie in_roll haben (in_roll>0 lässt basis.x.y
		# steigen), sonst Mitkopplung -> Aufschaukeln/Trudeln. Marker rechts -> target>0
		# -> roll_cmd>0 -> deckt sich mit Tastatur (A=rechts).
		var current_bank := asin(clampf(b.x.y, -1.0, 1.0))
		var roll_rate := (b.transposed() * aircraft.angular_velocity).z   # aktuelle Rollrate
		# Marker rechts -> Rechtskurve. Da die Roll-/Gier-Achsen hier "vertauscht" sind
		# (in_roll>0 dreht physikalisch links, vgl. Tastatur A=rechts), zeigt der Marker
		# mit umgekehrtem Vorzeichen auf die Soll-Querlage/Gier.
		var target_bank := -_aim.x * AIM_BANK_MAX
		# Kaskaden-Regler: Querlage-Fehler -> BEGRENZTE Soll-Rollrate -> Roll-Auslenkung.
		# Die Ratenbegrenzung verhindert, dass die Rollrate hochschaukelt -> kein
		# Überschwingen/Trudeln; das Flugzeug legt sich sauber auf die Querlage und hält sie.
		var desired_rate := clampf((target_bank - current_bank) * AIM_BANK_P, -AIM_ROLL_RATE_MAX, AIM_ROLL_RATE_MAX)
		var roll_cmd := clampf((desired_rate - roll_rate) * AIM_ROLL_P, -1.0, 1.0)
		var pitch_cmd := clampf(-_aim.y * AIM_PITCH + absf(sin(current_bank)) * AIM_TURN_PULL, -1.0, 1.0)
		pitch = clampf(pitch + pitch_cmd, -1.0, 1.0)
		roll = clampf(roll + roll_cmd, -1.0, 1.0)
		yaw = clampf(yaw - _aim.x * AIM_YAW, -1.0, 1.0)

	aircraft.mouse_fly = mouse_fly   # Body schaltet damit das Auto-Leveling im Maus-Flug ab
	aircraft.throttle = throttle
	if mouse_fly:
		# Maus-Flug: Befehle kommen aus dem (schon glatten) Regler -> DIREKT anwenden.
		# Das _ramp würde den Brems-Befehl verzögern und Überschwingen verursachen.
		aircraft.in_pitch = pitch
		aircraft.in_roll = roll
		aircraft.in_yaw = yaw
	else:
		# Weiches Eingabe-Ramping (analoges Gefühl auf Tastatur, nicht ruckartig ±1).
		# Schnelles Aufbauen, etwas langsameres Zurückzentrieren.
		aircraft.in_pitch = _ramp(aircraft.in_pitch, pitch, delta, 4.0, 6.0)
		aircraft.in_roll = _ramp(aircraft.in_roll, roll, delta, 7.0, 9.0)
		aircraft.in_yaw = _ramp(aircraft.in_yaw, yaw, delta, 4.0, 6.0)

	# --- Waffen (Cooldown pro Waffe) ------------------------------------
	for w in weapons:
		w["cd"] = maxf(0.0, w["cd"] - delta)
	if Input.is_physical_key_pressed(KEY_SPACE):
		_fire_primary()
	if Input.is_physical_key_pressed(KEY_B):
		_drop_bomb()

	_emit_hud()


# Mündungsrichtung = Flugzeug-Vorwärts (-Z), Position = Welt-Offset des Mounts.
func _muzzle(off: Vector3) -> Vector3:
	return aircraft.global_transform * off


func _fire_primary() -> void:
	if world_root == null:
		return
	var fwd := -aircraft.global_transform.basis.z.normalized()
	var av := aircraft.linear_velocity
	for w in weapons:
		if w["cd"] > 0.0:
			continue
		var pos: Vector3 = _muzzle(w["off"])
		match w["type"]:
			"gun":
				_spawn("bullet", pos + fwd * 1.2, av + fwd * 350.0, 2.0, 1.0)
				w["cd"] = 0.09
			"rocket":
				_spawn("missile", pos, av + fwd * 150.0, 6.0, 4.0)   # geradeaus, ungelenkt
				w["cd"] = 0.5
			"salvo":
				var rgt := aircraft.global_transform.basis.x.normalized()
				for s in [-1.0, 0.0, 1.0]:                            # 3er-Salve gefächert
					var d: Vector3 = (fwd + rgt * (float(s) * 0.12)).normalized()
					_spawn("missile", pos, av + d * 150.0, 6.0, 3.5)
				w["cd"] = 1.0
			"missile":
				var m := _spawn("missile", pos, av + fwd * 120.0, 8.0, 4.0)
				m.guided = true
				m.turn = 3.0
				m.seek_range = 80.0
				w["cd"] = 1.0
			"missile_heavy":
				var mh := _spawn("missile", pos, av + fwd * 100.0, 11.0, 10.0)
				mh.guided = true
				mh.turn = 2.0
				mh.seek_range = 110.0
				w["cd"] = 1.7


func _drop_bomb() -> void:
	var av := aircraft.linear_velocity
	for w in weapons:
		if w["type"] == "bomb" and w["cd"] <= 0.0:
			_spawn("bomb", _muzzle(w["off"]), av, 12.0, 6.0)
			w["cd"] = 0.8


func _spawn(kind: String, pos: Vector3, vel: Vector3, life: float, dmg: float) -> Projectile:
	var root := world_root if world_root != null else get_parent()
	if root == null:
		return null
	var p := Projectile.new()
	p.kind = kind
	p.vel = vel
	p.life = life
	p.damage = dmg
	root.add_child(p)
	p.global_position = pos
	return p


# Eingabe sanft Richtung Ziel führen (rise = drücken, fall = loslassen/zentrieren).
func _ramp(cur: float, target: float, delta: float, rise: float, fall: float) -> float:
	var rate := rise if absf(target) > absf(cur) else fall
	return move_toward(cur, target, rate * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if mouse_fly:
			# Maus-Flug: Cursor bewegt den Steuermarker (auf Einheitskreis begrenzt)
			_aim += event.relative * AIM_SENS
			if _aim.length() > 1.0:
				_aim = _aim.normalized()
		else:
			# Umschauen: Kamera frei um das Flugzeug schwenken
			look_yaw = clampf(look_yaw - event.relative.x * LOOK_SENS, -PI, PI)
			look_pitch = clampf(look_pitch - event.relative.y * LOOK_SENS, -1.2, 1.35)
			_mouse_idle = 0.0
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_BACKSPACE or event.keycode == KEY_KP_ENTER:
			_reset_to_runway()
		elif event.keycode == KEY_M:
			_toggle_mouse_fly()
		elif event.keycode == KEY_T and is_instance_valid(aircraft):
			aircraft.assist = not aircraft.assist
		elif event.keycode == KEY_G and is_instance_valid(aircraft):
			aircraft.toggle_gear()
		elif event.keycode == KEY_I and is_instance_valid(aircraft):
			aircraft.toggle_invert()


# Maus-Flug umschalten: Cursor lenkt die Nase (an) <-> freies Umschauen (aus).
func _toggle_mouse_fly() -> void:
	mouse_fly = not mouse_fly
	_aim = Vector2.ZERO
	look_yaw = 0.0
	look_pitch = 0.0


# ---------------------------------------------------------------------------
# Verfolgerkamera
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if camera == null or not is_instance_valid(aircraft):
		return
	# Ohne Mausbewegung sanft zur Verfolgeransicht zurückschwenken
	_mouse_idle += delta
	if _mouse_idle > LOOK_RECENTER:
		var k := clampf(delta * 2.2, 0.0, 1.0)
		look_yaw = lerpf(look_yaw, 0.0, k)
		look_pitch = lerpf(look_pitch, 0.0, k)
	var t := aircraft.global_transform
	var desired := t.origin + _cam_offset(t)
	camera.global_position = camera.global_position.lerp(desired, clamp(delta * 6.0, 0.0, 1.0))
	camera.look_at(t.origin + Vector3.UP * 0.8, Vector3.UP)


# Kamera-Versatz hinter dem Flugzeug, per Umschau-Winkeln (look_yaw/pitch) gedreht.
# look=0 -> klassische Verfolgeransicht.
func _cam_offset(t: Transform3D) -> Vector3:
	var base: Vector3 = t.basis.z.normalized() * 11.0 + Vector3.UP * 3.8
	var off: Vector3 = Basis(Vector3.UP, look_yaw) * base
	var rightax: Vector3 = off.cross(Vector3.UP)
	if rightax.length() > 0.01:
		off = Basis(rightax.normalized(), look_pitch) * off
	return off


func _snap_camera() -> void:
	if camera == null or not is_instance_valid(aircraft):
		return
	var t := aircraft.global_transform
	camera.global_position = t.origin + _cam_offset(t)
	camera.look_at(t.origin + Vector3.UP * 0.8, Vector3.UP)


# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------
func _update_markers() -> void:
	# Steuermarker = Bildmitte + normierter Maus-Versatz; Nasenmarker = wohin die
	# Nase aktuell zeigt (150 m voraus auf den Schirm projiziert).
	var vp := get_viewport().get_visible_rect().size
	var ctr := vp * 0.5
	var radius := minf(vp.x, vp.y) * AIM_RADIUS_F
	aim_screen = ctr + _aim * radius
	if camera != null and camera.is_inside_tree():
		var npt := aircraft.global_position - aircraft.global_transform.basis.z * 150.0
		nose_screen = ctr if camera.is_position_behind(npt) else camera.unproject_position(npt)
	else:
		nose_screen = ctr


func _emit_hud() -> void:
	if not is_instance_valid(aircraft):
		return
	_update_markers()
	hud_changed.emit({
		"mouse_fly": mouse_fly,
		"aim": aim_screen,
		"nose": nose_screen,
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
		"pos": aircraft.global_position,
	})
