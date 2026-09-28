## FLUGMODI UEBER ECHTE TASTENEINGABEN.
##
## _rundflug_alle fliegt nur den Standard (Maus-Flug) und ruft Funktionen direkt auf. Hier
## gehen die Eingaben durch Input.parse_input_event — also durch denselben Weg wie eine
## echte Taste (_unhandled_input, Input.is_physical_key_pressed):
##   ARCADE (J)      Ziel 90 Grad rechts -> Nase dort in wenigen Sekunden, keine NaN
##   FASSROLLE (A)   A halten -> Rollrate um BARREL_RATE, Fluegel heil
##   TASTATUR (N)    N -> Tastatur-Flug; S halten -> Nase hoch
##   KLAPPEN (F), UMKEHR (I), ASSIST (T), FREE-LOOK (C halten), KARTE (M)
##   RESET (Enter), HANGAR UND ZURUECK (Tab, Tab)
##
##   HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/_flugmodi_check.gd
extends SceneTree

var m: Node = null
var f := 0
var t := 0
var phase := 0
var fehler := 0
var wert := 0.0
var max_roll := 0.0
var nan := false


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 20:
		m.call("_load_design_from", "res://designs/mig21.json")
		m.call("_set_mode", 1)
		return false
	if f < 40:
		return false
	var fc = m.get("flight_ctrl")
	var ac = fc.get("aircraft")
	if ac != null and is_instance_valid(ac) and not ac.global_position.is_finite():
		nan = true
	t += 1
	match phase:
		0:
			_in_die_luft(fc, ac)
			_tippen(KEY_J)
			phase = 1
			t = 0
		1:
			if t == 2:
				_pruef("J schaltet Arcade ein", bool(fc.get("arcade")))
				fc.set("look_yaw", PI * 0.5)       # Ziel: 90 Grad rechts
			if t == 60 * 4:
				var nase: Vector3 = -ac.global_transform.basis.z
				var ziel: Vector3 = fc.call("_aim_dir")
				var fehlw := rad_to_deg(nase.angle_to(ziel))
				_pruef("Arcade: Nase nach 4 s auf dem Ziel", fehlw < 10.0, "Restfehler %.1f Grad" % fehlw)
				_tippen(KEY_J)
				phase = 2
				t = 0
		2:
			if t == 2:
				_pruef("J schaltet Arcade wieder aus", not bool(fc.get("arcade")))
				_in_die_luft(fc, ac)
				_taste(KEY_A, true)
				max_roll = 0.0
			if t > 2 and t < 150:
				var wb: Vector3 = ac.global_transform.basis.transposed() * ac.angular_velocity
				max_roll = maxf(max_roll, absf(wb.z))
			if t == 150:
				_taste(KEY_A, false)
				_pruef("Fassrolle: Rollrate erreicht", max_roll > 3.0, "%.2f rad/s" % max_roll)
				_pruef("Fassrolle: Fluegel heil", String(ac.get("wing_status")) == "ok")
			if t == 200:
				_in_die_luft(fc, ac)
				_tippen(KEY_N)
				phase = 3
				t = 0
		3:
			if t == 2:
				_pruef("N schaltet auf Tastatur-Flug", not bool(fc.get("mouse_fly")))
				_taste(KEY_S, true)
				wert = 0.0
			if t > 10 and t < 70:
				var wb: Vector3 = ac.global_transform.basis.transposed() * ac.angular_velocity
				wert = maxf(wert, wb.x)
			if t == 70:
				_taste(KEY_S, false)
				_pruef("Tastatur: S zieht die Nase hoch", wert > 0.2, "Nickrate %.2f rad/s" % wert)
				_tippen(KEY_N)
			if t == 75:
				_pruef("N zurueck auf Maus-Flug", bool(fc.get("mouse_fly")))
				_tippen(KEY_F)
			if t == 78:
				_pruef("F: Klappen Stufe Start", is_equal_approx(float(ac.get("flaps")), 0.5),
					"flaps %.2f" % float(ac.get("flaps")))
				_tippen(KEY_F)
				_tippen(KEY_F)
				_tippen(KEY_I)
			if t == 82:
				_pruef("F dreimal: Klappen wieder aus", is_zero_approx(float(ac.get("flaps"))))
				_pruef("I: Steuerung umgekehrt", bool(ac.get("inverted")))
				_tippen(KEY_I)
				var assist_vor: bool = ac.get("assist")
				_tippen(KEY_T)
				wert = 1.0 if assist_vor else 0.0
			if t == 85:
				_pruef("I nochmal: Steuerung normal", not bool(ac.get("inverted")))
				_pruef("T schaltet Assist um", bool(ac.get("assist")) != (wert > 0.5))
				_tippen(KEY_T)
				_taste(KEY_C, true)
			if t == 88:
				_pruef("C halten: Free-Look", bool(fc.get("free_look")))
				_taste(KEY_C, false)
			if t == 91:
				_pruef("C loslassen: Free-Look aus", not bool(fc.get("free_look")))
				phase = 4
				t = 0
		4:
			# Karte erst, wenn sie gezeichnet ist (Hintergrundthread beim Weltaufbau).
			if m.get("world_map") != null:
				_tippen(KEY_M)
				phase = 5
				t = 0
			elif t > 60 * 30:
				_pruef("Karte wird fertig", false)
				phase = 6
		5:
			if t == 3:
				_pruef("M oeffnet die Karte", (m.get("world_map") as Control).visible)
				_tippen(KEY_M)
			if t == 6:
				_pruef("M schliesst die Karte", not (m.get("world_map") as Control).visible)
				ac.global_position = Vector3(3000, 500, 3000)
				_tippen(KEY_ENTER)
			if t == 10:
				ac = fc.get("aircraft")
				_pruef("Enter: zurueck auf der Startbahn",
					ac.global_position.distance_to(Vector3(0, ac.global_position.y, 40)) < 5.0
					and ac.global_position.y < 10.0)
				_tippen(KEY_TAB)
			if t == 14:
				_pruef("Tab: in den Hangar", int(m.get("mode")) == 0)
				_tippen(KEY_TAB)
			if t == 20:
				_pruef("Tab: wieder in den Flug", int(m.get("mode")) == 1
					and is_instance_valid(fc.get("aircraft")))
				phase = 6
		6:
			_pruef("keine NaN-Lage im ganzen Lauf", not nan)
			print("-> %d Beanstandungen" % fehler)
			quit()
	return false


func _in_die_luft(fc, ac) -> void:
	ac.global_transform = Transform3D(Basis(), Vector3(3000.0, 600.0, 3000.0))
	ac.linear_velocity = Vector3(0, 0, -150.0)
	ac.angular_velocity = Vector3.ZERO
	fc.set("throttle", 0.9)
	fc.call("_reset_mouse_state")


func _taste(code: Key, gedrueckt: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = gedrueckt
	Input.parse_input_event(ev)


func _tippen(code: Key) -> void:
	_taste(code, true)
	_taste(code, false)


func _pruef(name: String, ok: bool, info := "") -> void:
	print("%-44s %s  %s" % [name, "OK" if ok else "FALSCH", info])
	if not ok:
		fehler += 1
