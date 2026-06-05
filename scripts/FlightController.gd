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
const FREE_LOOK_SENS := 0.014   # Free-Look (C): flotter -> voll 360° mit normalem Swipe
const LOOK_RECENTER := 0.6      # s ohne Mausbewegung -> Kamera schwenkt sanft zurück
const CAM_LOOK_ABOVE := 6.5     # Maus-Flug: Kamera blickt so viel ÜBER den Flieger -> er sitzt tief im unteren Bildbereich
const CAM_SHAKE_DECAY := 2.8    # Kamera-Shake klingt so schnell ab (1/s)
const CAM_SHAKE_POS := 0.55     # Shake-Positionsausschlag (m bei vollem Trauma)
const CAM_SHAKE_ROLL := 0.05    # Shake-Rollausschlag (rad)
const BARREL_HOLD := 0.32       # A/D so lange halten -> Fass-Roll (War-Thunder-Stil)
# Landeklappen-Stufen (Taste F): Aus -> Start -> Landung. Wert = Klappenstellung 0..1.
const FLAP_STAGES := [0.0, 0.5, 1.0]
const FLAP_NAMES := ["AUS", "Start", "Landung"]
# Geschütz-Kaliber: Mündungsgeschwindigkeit, Schaden, Lebenszeit, Kadenz (cd),
# Bullet-Drop (m/s² Schwerkraft aufs Geschoss) und Leuchtspur. Schwereres Kaliber =
# langsameres Geschoss + mehr Drop + mehr Schaden + dickere/längere Spur.
const CALIBERS := {
	"mg":         {"speed": 380.0, "dmg": 1.2,  "life": 2.6, "cd": 0.55, "drop": 9.0,  "tcol": Color(1.0, 0.92, 0.45), "tscl": 0.8},
	"gun":        {"speed": 330.0, "dmg": 2.2,  "life": 2.8, "cd": 0.10, "drop": 12.0, "tcol": Color(1.0, 0.82, 0.30), "tscl": 1.0},
	"autocannon": {"speed": 280.0, "dmg": 5.0,  "life": 3.0, "cd": 0.28, "drop": 17.0, "tcol": Color(1.0, 0.60, 0.20), "tscl": 1.4},
	"heavy":      {"speed": 235.0, "dmg": 11.0, "life": 3.4, "cd": 0.85, "drop": 23.0, "tcol": Color(1.0, 0.45, 0.12), "tscl": 1.9},
	"minigun":    {"speed": 360.0, "dmg": 2.4,  "life": 2.8, "cd": 0.045, "drop": 11.0, "tcol": Color(1.0, 0.72, 0.25), "tscl": 1.1},
}
# Minigun (Gatling): dreht erst hoch, feuert dann sehr schnell. Läufe drehen sichtbar mit.
const MINIGUN_SPINUP := 0.75    # s bis volle Drehzahl
const MINIGUN_SPINDOWN := 0.55  # s zum Auslaufen
const MINIGUN_FIRE_SPIN := 0.82 # ab dieser Drehzahl kommen Schüsse
const MINIGUN_MAX_RPS := 46.0   # max. Lauf-Drehrate (rad/s)
# Jede montierte Bombe/Rakete = GENAU 1 Stück. Beim Abfeuern verschwindet das Teil vom Modell
# (queue_detach -> Aero neu). Mehr Munition = mehr Teile anbauen. Geschütze fehlen -> unbegrenzt.
const AMMO := {
	"rocket": 1, "salvo": 1, "missile": 1, "missile_heavy": 1, "bomb": 1,
}
# Rückstoß-Impuls je Schuss (N·s, entgegen der Mündungsrichtung). Bei ~1200 kg ergibt 1200 ≈ 1 m/s
# Tempoverlust. Schweres Kaliber/Raketen schubsen kräftig, MG nur leicht. Bombe: kein Rückstoß.
const RECOIL := {
	"mg": 180.0, "gun": 320.0, "autocannon": 900.0, "heavy": 2200.0, "minigun": 240.0,
	"rocket": 1500.0, "salvo": 3000.0, "missile": 1300.0, "missile_heavy": 2600.0,
}

# --- Maus-Flug (War-Thunder-Stil): Maus zeigt in eine WELTRICHTUNG (360°),
#     das Flugzeug dreht die Nase dorthin (Pursuit). look_yaw/look_pitch = Zielrichtung.
const AIM_LOOK_SENS := 0.005    # Maus -> Blick-/Zielrichtung (rad pro Pixel)
const AIM_SMOOTH := 24.0        # nur LEICHTE Glättung der Zielrichtung (kaum Lag) -> reaktionsschnell
const AIM_DEADZONE := 0.01      # Totbereich (rad) am Ziel -> kein Marker-Zittern (Limit-Cycle)
const AIM_BANK_MAX := 1.25      # max. Querlage in Kurven (~72°, sicherer Abstand zu 90°)
const AIM_BANK_K := 2.4         # Horizontal-Zielfehler (rad) -> Soll-Querlage (stark in die Kurve)
const AIM_BANK_P := 6.5         # Querlage-Fehler -> Soll-Rollrate (schnelles Einrollen, kostet keine G)
const AIM_ROLL_RATE_MAX := 5.5  # max. Rollrate (rad/s) -> sehr zügiges Einrollen (atan2-Messung -> kein Überbank-Taumeln)
const AIM_ROLL_P := 2.0         # Rollraten-Fehler -> Roll-Auslenkung (straffe Ratenführung)
const AIM_PITCH_K := 2.2        # Vertikal-Zielfehler (rad) -> Soll-Nickrate
const AIM_PITCH_RATE_MAX := 2.3 # max. Nickrate (rad/s) -> schnell, aber unter Stall
const AIM_PITCH_RATE_P := 1.5   # Nickraten-Fehler -> Auslenkung (gut gedämpft, kein Überziehen)
const AIM_TURN_PULL := 0.7      # Höhenruder-Zug proportional zum Horizontalfehler (zieht durch die Kurve, getapert)
const AIM_YAW_K := 0.5          # Ruderkoordination Richtung Ziel (direkteres Anvisieren)
const AIM_YAW_D := 0.3          # Gier-Dämpfung
const AIM_MARK_SMOOTH := 0.5    # Nasenmarker-Pixelglättung (Lerp/Frame)

var camera: Camera3D
var aircraft: AircraftBody
var design: Array = []
var throttle := 0.0
var spawn_height := 2.0
var look_yaw := 0.0             # freies Umschauen (Maus) — horizontal
var look_pitch := 0.0           # vertikal
var free_look := false          # C halten: Kamera frei um den Flieger schwenken (ohne zu steuern)
var flook_yaw := 0.0            # Free-Look-Blickwinkel horizontal
var flook_pitch := 0.0          # Free-Look-Blickwinkel vertikal
var _mouse_idle := 0.0
var mouse_fly := false          # Maus-Flug an? (Maus = Weltzielrichtung, Nase folgt)
var arcade := false             # Arcade-Lenkung an? (kinematisch super-smooth, nur im Maus-Flug)
var _roll_hold := 0.0           # wie lange A/D schon gehalten (für Fass-Roll)
var _roll_dir := 0              # aktuelle Roll-Halterichtung (+1=A, -1=D, 0=keine)
var _flap_stage := 0            # Landeklappen-Stufe (Index in FLAP_STAGES), Taste F schaltet weiter
var _cam_shake := 0.0           # aktuelles Kamera-Shake-„Trauma" (0..~1.4), klingt ab
var _aim_smooth := Vector3(0, 0, -1)  # geglättete Zielrichtung (Regler folgt ihr -> smoother)
var _nose_px := Vector2.ZERO    # geglättete Nasenmarker-Pixelposition
var aim_screen := Vector2.ZERO  # Pixelposition Zielmarker (fürs HUD)
var nose_screen := Vector2.ZERO # Pixelposition der aktuellen Nasenrichtung
var aim_visible := true         # Zielmarker im Bild?
var nose_visible := true        # Nasenmarker im Bild?
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

	# Vorab: Rumpf-Boxen (Nicht-Flügel) -> im Rumpf vergrabene Flügelfläche erzeugt keinen Auftrieb.
	var body_boxes: Array = []
	for it in d:
		var bid: String = it.get("id", "")
		if not PartCatalog.has(bid):
			continue
		var bpp := PartCatalog.get_part(bid)
		if bpp.get("is_wing", false):
			continue
		body_boxes.append(PartCatalog.part_box(bpp, it.get("xform", Transform3D()), it.get("scale", Vector3.ONE)))

	for item in d:
		var id: String = item.get("id", "")
		if not PartCatalog.has(id):
			continue
		var p := PartCatalog.get_part(id)
		var xf: Transform3D = item.get("xform", Transform3D())
		var psc: Vector3 = item.get("scale", Vector3.ONE)
		var vol: float = psc.x * psc.y * psc.z      # Volumen-Faktor (Masse/Traglast)

		var vis := PartCatalog.build_visual(p, item.get("color", Color(0, 0, 0, 0)), item.get("taper", 1.0), item.get("taper_front", 1.0))
		# Skalierung in die Basis einrechnen (NICHT vis.scale setzen): bei gespiegelten
		# Teilen ist die Basis improper (det<0); vis.scale würde die Spiegelung zerstören
		# -> Flügel klappt auf die andere Seite -> "halbes Flugzeug".
		vis.transform = Transform3D(xf.basis * Basis.from_scale(psc), xf.origin)
		body.add_child(vis)
		var prop := vis.find_child("Prop", true, false)
		# Bewegliche Fläche: Hauptflügel = "FlapHinge" (Rolle "flap"), Steuerflügel = "CtrlHinge"
		# (Rolle = control: pitch/roll/yaw). Wird im AircraftBody animiert.
		var surf_node: Node3D = vis.find_child("FlapHinge", true, false)
		var surf_role := "flap"
		if surf_node == null:
			surf_node = vis.find_child("CtrlHinge", true, false)
			surf_role = String(p.get("control", ""))

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
			"surf": surf_node, "surf_role": surf_role,
			# Welt-"unten"-Vorzeichen aus der Flügel-Oberseite (basis.y.y); kippt bei Spiegelung
			# NICHT (Mirror negiert nur X) -> beide Seiten schlagen gleich aus. Vertikale Flosse
			# (y.y≈0) -> Fallback 1. surf_side (x-Seite) für gegensinnige Quer-/Flaperon-Ausschläge.
			"surf_dn": (1.0 if absf(xf.basis.y.y) < 0.3 else signf(xf.basis.y.y)),
			"surf_side": (1.0 if xf.origin.x >= 0.0 else -1.0),
			"is_root": p.get("root", false),
			"is_wing": p.get("is_wing", false), "control": String(p.get("control", "")),
			"mass": p.get("mass", 0.0) * vol,
			"drag": PartCatalog.part_drag(p) * psc.x * psc.y,
			"lift_part": 0.0, "ar": 4.0, "lift_coef": 1.0, "wing_cap": 0.0, "span": 2.0,
			"pitch_a": 0.0, "roll_a": 0.0, "yaw_a": 0.0,
			"thrust": p.get("thrust", 0.0) * vol, "jet": p.get("jet", false),
			"gear_cap": p.get("gear_capacity", 0.0) * vol, "retract": p.get("retract", false),
			"scale": psc,
		}
		if pinfo["is_wing"]:
			var a_full: float = p.get("area", 0.0) * psc.x * psc.z
			var span: float = p.get("span", sqrt(maxf(a_full, 0.01))) * psc.x
			# im Rumpf vergrabene Spannweite zählt nicht (weniger Auftrieb/Steuerkraft)
			var exposed: float = PartCatalog.wing_exposed_fraction(xf, span, PartCatalog.col_offset(p).z * psc.z, body_boxes)
			var a: float = a_full * exposed
			var up_align: float = clampf(absf(xf.basis.y.dot(Vector3.UP)), 0.0, 1.0)
			pinfo["span"] = span
			pinfo["ar"] = clampf(span * span / maxf(a_full, 0.01), 0.6, 10.0)
			pinfo["lift_coef"] = p.get("lift", 1.0)
			pinfo["wing_cap"] = a_full * PartCatalog.WING_STRESS
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
			# ammo = -1 -> unbegrenzt (Geschütze); 1 -> Bombe/Rakete (verschwindet nach Schuss).
			# part_idx verknüpft die Waffe mit ihrem Bauteil (zum Entfernen beim Abfeuern).
			var went := {"type": wp, "off": xf.origin, "cd": 0.0,
				"ammo": int(AMMO.get(wp, -1)), "part_idx": part_infos.size() - 1}
			if wp == "minigun":
				went["spin"] = 0.0
				went["barrels"] = vis.find_child("Barrels", true, false)   # rotierendes Laufbündel
			weapons.append(went)

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
	_flap_stage = 0              # Klappen eingefahren auf der Bahn
	aircraft.flaps = 0.0
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

	# Free-Look: C halten -> nur die Kamera schwenkt frei (siehe _process), Steuerung bleibt.
	free_look = Input.is_physical_key_pressed(KEY_C)

	# Schub (unter 0 % = bremsen, über 100 % = Nachbrenner bis 110 %)
	if Input.is_key_pressed(KEY_SHIFT):
		throttle += 0.6 * delta
	if Input.is_key_pressed(KEY_CTRL):
		throttle -= 0.6 * delta
	throttle = clamp(throttle, -0.4, 1.1)

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
	# Gieren / Seitenleitwerk (Q = rechts, E oder Z = links). C ist jetzt Free-Look.
	var yaw := 0.0
	if Input.is_physical_key_pressed(KEY_Q):
		yaw += 1.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_Z):
		yaw -= 1.0

	# Fass-Roll (War-Thunder-Stil): A oder D LANGE halten -> kinematische 360°-Rolle um die
	# Längsachse. Kurzes Antippen rollt/bankt normal; ab BARREL_HOLD übernimmt die Fass-Roll.
	var rdir := 0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		rdir = 1
	elif Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		rdir = -1
	if rdir != 0 and rdir == _roll_dir:
		_roll_hold += delta
	else:
		_roll_dir = rdir
		_roll_hold = delta if rdir != 0 else 0.0
	aircraft.barrel_roll = rdir if (rdir != 0 and _roll_hold > BARREL_HOLD) else 0

	# Maus-Flug: Die Maus zeigt in eine WELTRICHTUNG (look_yaw/look_pitch), das Flugzeug
	# dreht seine Nase dorthin (Pursuit) — voll 360°. Schaust du nach Westen, fliegt es nach
	# Westen. Bank-to-turn: Horizontalfehler -> Soll-Querlage (Kaskade, kein Trudeln);
	# Vertikalfehler -> Nick; Zug proportional zum Horizontalfehler zieht durch die Kurve.
	if mouse_fly:
		var b := aircraft.global_transform.basis
		aircraft.aim_world = _aim_dir()   # Arcade-Lenkung (AircraftBody) nutzt die rohe Zielrichtung
		# Geglättete Zielrichtung -> der Regler folgt nicht jedem Maus-Ruckeln (smoother Flugweg).
		# lerp+normalize statt Vector3.slerp: slerp wirft bei fast-parallelen Vektoren
		# "axis must be normalized" (interne Achse aus ~0-Kreuzprodukt). lerp ist robust.
		_aim_smooth = _aim_smooth.lerp(_aim_dir(), clampf(delta * AIM_SMOOTH, 0.0, 1.0)).normalized()
		var e := b.transposed() * _aim_smooth     # Zielrichtung im Körpersystem (Nase = -Z)
		var horiz := atan2(e.x, -e.z)             # Horizontalwinkel zum Ziel: +rechts, ±π hinten
		var vert := atan2(e.y, sqrt(e.x * e.x + e.z * e.z))  # Vertikalwinkel: +oben
		# Kleiner Totbereich nahe am Ziel -> kein Mikro-Zittern (Limit-Cycle) der Nase/Marker.
		if absf(horiz) < AIM_DEADZONE:
			horiz = 0.0
		if absf(vert) < AIM_DEADZONE:
			vert = 0.0
		var wb := b.transposed() * aircraft.angular_velocity   # Körperraten (x=Nick, y=Gier, z=Roll)
		# Roll: Bank-to-turn-Kaskade. Achsen "vertauscht" (in_roll>0 dreht physikalisch links),
		# daher Vorzeichen negiert -> Ziel rechts = Rechtskurve. Querlage als asin(basis.x.y)
		# (gleiches Vorzeichen wie in_roll, sonst Mitkopplung).
		# Querlage als atan2 (voller Bereich, kippt nicht bei 90° wie asin -> kein Taumeln).
		var current_bank := atan2(b.x.y, b.y.y)
		var target_bank := clampf(-horiz * AIM_BANK_K, -AIM_BANK_MAX, AIM_BANK_MAX)
		var d_roll := clampf((target_bank - current_bank) * AIM_BANK_P, -AIM_ROLL_RATE_MAX, AIM_ROLL_RATE_MAX)
		var roll_cmd := clampf((d_roll - wb.z) * AIM_ROLL_P, -1.0, 1.0)
		# Nick: Vertikalfehler -> BEGRENZTE Soll-Nickrate -> GEDÄMPFTE Auslenkung (kein Jagen).
		# Kurvenzug NUR wenn gebankt (·|sin(bank)|): sonst zieht die Nase vor dem Einrollen
		# nutzlos nach oben -> Zeitverlust. So rollt es erst zügig ein und zieht dann durch.
		var d_pitch := clampf(vert * AIM_PITCH_K, -AIM_PITCH_RATE_MAX, AIM_PITCH_RATE_MAX)
		var pitch_cmd := clampf((d_pitch - wb.x) * AIM_PITCH_RATE_P + clampf(absf(horiz), 0.0, 1.5) * AIM_TURN_PULL * absf(sin(current_bank)), -1.0, 1.0)
		# Gier: leicht koordiniert Richtung Ziel + gedämpft (vertauscht -> negiert).
		var yaw_cmd := clampf(-horiz * AIM_YAW_K - wb.y * AIM_YAW_D, -1.0, 1.0)
		pitch = clampf(pitch + pitch_cmd, -1.0, 1.0)
		roll = clampf(roll + roll_cmd, -1.0, 1.0)
		yaw = clampf(yaw + yaw_cmd, -1.0, 1.0)

	aircraft.mouse_fly = mouse_fly   # Body schaltet damit das Auto-Leveling im Maus-Flug ab
	aircraft.arcade = arcade         # Arcade-Lenkung (kinematisch) im Body aktivieren
	aircraft.throttle = throttle
	aircraft.flaps = FLAP_STAGES[_flap_stage]   # Landeklappen: mehr Auftrieb + Widerstand
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
	# Minigun: Spin-up/Spin-down + Läufe drehen (auch wenn nicht gefeuert wird)
	var firing := Input.is_physical_key_pressed(KEY_SPACE)
	for w in weapons:
		if w["type"] != "minigun":
			continue
		var pidx: int = int(w.get("part_idx", -1))
		var alive: bool = pidx < 0 or pidx >= aircraft.parts.size() or not aircraft.parts[pidx].get("broken", false)
		var target := 1.0 if (firing and alive) else 0.0
		var rate := (1.0 / MINIGUN_SPINUP) if target > float(w["spin"]) else (1.0 / MINIGUN_SPINDOWN)
		w["spin"] = move_toward(float(w["spin"]), target, rate * delta)
		var b = w.get("barrels")
		if b != null and is_instance_valid(b):
			b.rotate_z(float(w["spin"]) * MINIGUN_MAX_RPS * delta)
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
		if w["cd"] > 0.0 or int(w["ammo"]) == 0:   # Cooldown läuft ODER aufgebraucht
			continue
		var pidx: int = int(w.get("part_idx", -1))
		if pidx >= 0 and pidx < aircraft.parts.size() and aircraft.parts[pidx].get("broken", false):
			continue   # Mount/Teil weggebrochen -> nicht feuern
		var pos: Vector3 = _muzzle(w["off"])
		var fired := false
		# Geschütz-Kaliber (mit Bullet-Drop): einheitlich aus der CALIBERS-Tabelle. Unbegrenzt.
		if CALIBERS.has(w["type"]):
			if w["type"] == "minigun" and float(w.get("spin", 0.0)) < MINIGUN_FIRE_SPIN:
				continue   # Gatling noch nicht auf Drehzahl
			var c: Dictionary = CALIBERS[w["type"]]
			_spawn("bullet", pos + fwd * 1.2, av + fwd * float(c["speed"]),
				float(c["life"]), float(c["dmg"]), float(c["drop"]), c["tcol"], float(c["tscl"]))
			w["cd"] = float(c["cd"])
			fired = true
		else:
			match w["type"]:
				"rocket":
					_spawn("missile", pos, av + fwd * 150.0, 6.0, 4.0)   # geradeaus, ungelenkt
					w["cd"] = 0.5
					fired = true
				"salvo":
					var rgt := aircraft.global_transform.basis.x.normalized()
					for s in [-1.0, 0.0, 1.0]:                            # 3er-Salve gefächert
						var d: Vector3 = (fwd + rgt * (float(s) * 0.12)).normalized()
						_spawn("missile", pos, av + d * 150.0, 6.0, 3.5)
					w["cd"] = 1.0
					fired = true
				"missile":
					var m := _spawn("missile", pos, av + fwd * 120.0, 8.0, 4.0)
					m.guided = true
					m.turn = 3.0
					m.seek_range = 80.0
					w["cd"] = 1.0
					fired = true
				"missile_heavy":
					var mh := _spawn("missile", pos, av + fwd * 100.0, 11.0, 10.0)
					mh.guided = true
					mh.turn = 2.0
					mh.seek_range = 110.0
					w["cd"] = 1.7
					fired = true
		if fired:
			# Rückstoß: Impuls entgegen der Mündungsrichtung (nach hinten = -fwd).
			aircraft.add_recoil(-fwd * float(RECOIL.get(w["type"], 0.0)))
			# Kamera-Shake je nach Kaliber (aus dem Rückstoß abgeleitet)
			add_shake(clampf(float(RECOIL.get(w["type"], 300.0)) / 9000.0, 0.02, 0.16))
			# Begrenzte Munition verbrauchen; bei 0 verschwindet das Bauteil (-> Aero neu).
			if int(w["ammo"]) > 0:
				w["ammo"] -= 1
				if int(w["ammo"]) == 0:
					aircraft.queue_detach(pidx)


func _drop_bomb() -> void:
	var av := aircraft.linear_velocity
	for w in weapons:
		if w["type"] != "bomb" or w["cd"] > 0.0 or int(w["ammo"]) == 0:
			continue
		var pidx: int = int(w.get("part_idx", -1))
		if pidx >= 0 and pidx < aircraft.parts.size() and aircraft.parts[pidx].get("broken", false):
			continue   # Bombe schon weg/abgerissen
		_spawn("bomb", _muzzle(w["off"]), av, 12.0, 6.0, 24.0)   # Bombe fällt (Schwerkraft)
		add_shake(0.1)
		w["cd"] = 0.8
		if int(w["ammo"]) > 0:
			w["ammo"] -= 1
			if int(w["ammo"]) == 0:
				aircraft.queue_detach(pidx)   # Bombe verschwindet vom Modell -> Aero neu


func _spawn(kind: String, pos: Vector3, vel: Vector3, life: float, dmg: float,
		grav := 0.0, tcol := Color(1.0, 0.85, 0.2), tscl := 1.0) -> Projectile:
	var root := world_root if world_root != null else get_parent()
	if root == null:
		return null
	var p := Projectile.new()
	p.kind = kind
	p.vel = vel
	p.life = life
	p.damage = dmg
	p.gravity = grav        # Bullet-Drop / Bomben-Fall
	p.tracer_color = tcol
	p.tracer_scale = tscl
	root.add_child(p)       # _ready -> _build_visual nutzt die schon gesetzten Tracer-Werte
	p.global_position = pos
	return p


# Eingabe sanft Richtung Ziel führen (rise = drücken, fall = loslassen/zentrieren).
func _ramp(cur: float, target: float, delta: float, rise: float, fall: float) -> float:
	var rate := rise if absf(target) > absf(cur) else fall
	return move_toward(cur, target, rate * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if free_look:
			# Free-Look (C): Maus schwenkt nur die Kamera frei um den Flieger (voll 360°), lenkt NICHT.
			flook_yaw = wrapf(flook_yaw - event.relative.x * FREE_LOOK_SENS, -PI, PI)
			flook_pitch = clampf(flook_pitch - event.relative.y * FREE_LOOK_SENS, -1.3, 1.3)
			return
		if mouse_fly:
			# Maus-Flug: Maus dreht die ZIELRICHTUNG frei in der Welt (360° horizontal).
			# Nach rechts schauen -> rechts; nach hinten schauen -> Flieger dreht ganz herum.
			look_yaw = wrapf(look_yaw + event.relative.x * AIM_LOOK_SENS, -PI, PI)
			look_pitch = clampf(look_pitch - event.relative.y * AIM_LOOK_SENS, -1.45, 1.45)
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
		elif event.keycode == KEY_J:
			_toggle_arcade()
		elif event.keycode == KEY_T and is_instance_valid(aircraft):
			aircraft.assist = not aircraft.assist
		elif event.keycode == KEY_G and is_instance_valid(aircraft):
			aircraft.toggle_gear()
		elif event.keycode == KEY_F:
			_flap_stage = (_flap_stage + 1) % FLAP_STAGES.size()   # Aus -> Start -> Landung -> Aus
		elif event.keycode == KEY_I and is_instance_valid(aircraft):
			aircraft.toggle_invert()


# Maus-Flug umschalten: Maus = Weltzielrichtung (an) <-> freies Umschauen (aus).
func _toggle_mouse_fly() -> void:
	mouse_fly = not mouse_fly
	if mouse_fly and is_instance_valid(aircraft):
		# Zielrichtung auf die aktuelle Nasenrichtung setzen -> kein Ruck beim Einschalten.
		var f := -aircraft.global_transform.basis.z
		look_yaw = atan2(f.x, -f.z)
		look_pitch = asin(clampf(f.y, -1.0, 1.0))
		_aim_smooth = _aim_dir()
	else:
		look_yaw = 0.0
		look_pitch = 0.0


# Arcade-Lenkung umschalten. Braucht den Maus-Flug -> ggf. mit einschalten.
func _toggle_arcade() -> void:
	arcade = not arcade
	if arcade and not mouse_fly:
		_toggle_mouse_fly()


# Zielrichtung (Weltkoordinaten) aus look_yaw/look_pitch. yaw=0,pitch=0 -> -Z (vorne/Nord).
func _aim_dir() -> Vector3:
	var cp := cos(look_pitch)
	return Vector3(sin(look_yaw) * cp, sin(look_pitch), -cos(look_yaw) * cp)


# ---------------------------------------------------------------------------
# Verfolgerkamera
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if camera == null or not is_instance_valid(aircraft):
		return
	# Kamera-Shake: Anfragen vom Flugzeug (Aufprall/Explosion/Bruch) aufnehmen + abklingen
	_cam_shake = minf(_cam_shake + aircraft.shake_request, 1.4)
	aircraft.shake_request = 0.0
	_cam_shake = maxf(0.0, _cam_shake - delta * CAM_SHAKE_DECAY)
	var t := aircraft.global_transform
	if free_look:
		# C halten: Kamera kreist frei um die MITTE des Flugzeugs (Schwerpunkt) und schaut sie an
		# -> von jedem Winkel sieht man den ganzen Flieger (nicht nur die Nase). Flug läuft normal.
		var center: Vector3 = t * aircraft.center_of_mass
		var off := _free_cam_offset(t)
		var up_ref := Vector3.UP
		if absf(off.normalized().y) > 0.95:        # fast senkrechte Sicht -> horizontaler Up-Bezug
			up_ref = t.basis.z
		camera.global_position = camera.global_position.lerp(center + off, clampf(delta * 7.0, 0.0, 1.0))
		camera.look_at(center, up_ref)
		_apply_cam_shake()
		return
	# Free-Look-Winkel sanft zurückstellen, wenn nicht (mehr) aktiv
	flook_yaw = lerpf(flook_yaw, 0.0, clampf(delta * 5.0, 0.0, 1.0))
	flook_pitch = lerpf(flook_pitch, 0.0, clampf(delta * 5.0, 0.0, 1.0))
	if mouse_fly:
		# Kamera blickt in die ZIELRICHTUNG (Maus), Flugzeug im Vordergrund -> du siehst,
		# wohin du zeigst und wie die Nase nachzieht. Kein Zurückschwenken (Ziel bleibt stehen).
		var aim := _aim_dir()
		var up_ref := Vector3.UP
		if absf(aim.dot(Vector3.UP)) > 0.97:
			up_ref = t.basis.y
		var cam_pos := t.origin - aim * 12.0 + Vector3.UP * 3.2
		camera.global_position = camera.global_position.lerp(cam_pos, clampf(delta * 6.0, 0.0, 1.0))
		# Blickpunkt etwas ÜBER dem Flieger -> Kamera neigt sich hoch -> Flieger sitzt tiefer im Bild
		camera.look_at(t.origin + aim * 30.0 + Vector3.UP * CAM_LOOK_ABOVE, up_ref)
		_apply_cam_shake()
		return
	# Ohne Mausbewegung sanft zur Verfolgeransicht zurückschwenken
	_mouse_idle += delta
	if _mouse_idle > LOOK_RECENTER:
		var k := clampf(delta * 2.2, 0.0, 1.0)
		look_yaw = lerpf(look_yaw, 0.0, k)
		look_pitch = lerpf(look_pitch, 0.0, k)
	var desired := t.origin + _cam_offset(t)
	camera.global_position = camera.global_position.lerp(desired, clamp(delta * 6.0, 0.0, 1.0))
	camera.look_at(t.origin + Vector3.UP * 0.8, Vector3.UP)
	_apply_cam_shake()


# Kamera-Shake auslösen (Feuer/Aufprall) und anwenden (Positions- + Roll-Jitter, quadratisch).
func add_shake(amount: float) -> void:
	_cam_shake = minf(_cam_shake + amount, 1.4)


func _apply_cam_shake() -> void:
	if _cam_shake <= 0.001:
		return
	var s := _cam_shake * _cam_shake   # quadratisch -> satter Stoß, sanftes Ausklingen
	var b := camera.global_transform.basis
	var off: Vector3 = b.x * randf_range(-1.0, 1.0) + b.y * randf_range(-1.0, 1.0)
	camera.global_position += off * (s * CAM_SHAKE_POS)
	camera.rotate_object_local(Vector3(0, 0, 1), randf_range(-1.0, 1.0) * s * CAM_SHAKE_ROLL)


# Kamera-Versatz hinter dem Flugzeug, per Umschau-Winkeln (look_yaw/pitch) gedreht.
# look=0 -> klassische Verfolgeransicht.
func _cam_offset(t: Transform3D) -> Vector3:
	var base: Vector3 = t.basis.z.normalized() * 11.0 + Vector3.UP * 3.8
	var off: Vector3 = Basis(Vector3.UP, look_yaw) * base
	var rightax: Vector3 = off.cross(Vector3.UP)
	if rightax.length() > 0.01:
		off = Basis(rightax.normalized(), look_pitch) * off
	return off


# Kamera-Versatz für Free-Look (C): saubere KUGEL mit KONSTANTEM Radius um den Schwerpunkt
# -> gleicher Abstand bei jedem Winkel. flook_yaw=0 = horizontal hinter dem Flieger.
const FREE_LOOK_DIST := 14.0
func _free_cam_offset(_t: Transform3D) -> Vector3:
	var behind: Vector3 = Vector3(_t.basis.z.x, 0.0, _t.basis.z.z)   # Heading horizontal projiziert
	if behind.length() < 0.01:
		behind = Vector3(0, 0, 1)
	behind = behind.normalized()
	var dir: Vector3 = Basis(Vector3.UP, flook_yaw) * behind
	var rightax: Vector3 = dir.cross(Vector3.UP)
	if rightax.length() > 0.01:
		dir = (Basis(rightax.normalized(), flook_pitch) * dir).normalized()
	return dir * FREE_LOOK_DIST


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
	# Zielmarker = wohin die Maus zeigt (Weltrichtung), Nasenmarker = wohin die Nase zeigt.
	# Decken sie sich, fliegt das Flugzeug genau aufs Ziel.
	var vp := get_viewport().get_visible_rect().size
	var ctr := vp * 0.5
	if camera == null or not camera.is_inside_tree():
		aim_screen = ctr
		nose_screen = ctr
		aim_visible = false
		nose_visible = false
		return
	var ap := aircraft.global_position + _aim_dir() * 400.0
	var np := aircraft.global_position - aircraft.global_transform.basis.z * 400.0
	aim_visible = not camera.is_position_behind(ap)
	nose_visible = not camera.is_position_behind(np)
	aim_screen = camera.unproject_position(ap) if aim_visible else ctr
	# Nasenmarker zusätzlich pixelgeglättet (kleine Restbewegung der Nase nicht sichtbar zittern)
	if nose_visible:
		var raw := camera.unproject_position(np)
		_nose_px = raw if _nose_px == Vector2.ZERO else _nose_px.lerp(raw, AIM_MARK_SMOOTH)
		nose_screen = _nose_px
	else:
		_nose_px = Vector2.ZERO
		nose_screen = ctr


# Restmunition der begrenzten Waffen (Raketen/Lenkwaffen/Bomben) je Kategorie summiert.
func _ammo_text() -> String:
	var rockets := 0
	var missiles := 0
	var bombs := 0
	var has_r := false
	var has_m := false
	var has_b := false
	for w in weapons:
		var a: int = int(w["ammo"])
		match String(w["type"]):
			"rocket", "salvo":
				has_r = true
				rockets += maxi(a, 0)
			"missile", "missile_heavy":
				has_m = true
				missiles += maxi(a, 0)
			"bomb":
				has_b = true
				bombs += maxi(a, 0)
	var parts: Array = []
	if has_r:
		parts.append("🚀 %d" % rockets)
	if has_m:
		parts.append("🎯 %d" % missiles)
	if has_b:
		parts.append("💣 %d" % bombs)
	return "   ".join(parts)


# Nasenkurs in Grad (0 = Nord/-Z, im Uhrzeigersinn: O=90, S=180, W=270).
func _heading_deg() -> float:
	var fwd := -aircraft.global_transform.basis.z
	return fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)


func _emit_hud() -> void:
	if not is_instance_valid(aircraft):
		return
	_update_markers()
	hud_changed.emit({
		"mouse_fly": mouse_fly,
		"arcade": arcade,
		"aim": aim_screen,
		"nose": nose_screen,
		"aim_vis": aim_visible,
		"nose_vis": nose_visible,
		"throttle": throttle,
		"heading": _heading_deg(),
		"speed": aircraft.airspeed,
		"kmh": aircraft.airspeed * 3.6,
		"alt": aircraft.altitude,
		"aoa": aircraft.aoa_deg,
		"climb": aircraft.climb,
		"stall": aircraft.stall,
		"gforce": aircraft.gforce,
		"thrust": aircraft.total_thrust,
		"assist": aircraft.assist,
		"flaps": FLAP_NAMES[_flap_stage],
		"ammo": _ammo_text(),
		"gear": aircraft.gear_status,
		"wings": aircraft.wing_status,
		"inverted": aircraft.inverted,
		"land_msg": aircraft.landing_msg,
		"pos": aircraft.global_position,
	})
