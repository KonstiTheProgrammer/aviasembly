## UMSCHAU- UND ZOOM-PRUEFUNG (C = Free-Look, Z/V = Zielzoom), headless mit echtem Main:
##   * C behaelt den Abstand der Flugkamera (auch herausgezoomt und mit Tempo-Vorhalt) — vorher
##     kreiste C mit festen 14 m um den Flieger und zog einen heran;
##   * kein Sprung beim Druecken und Loslassen (Versatz Kamera -> Flieger je Frame);
##   * die Maus dreht im Free-Look nur den Blick (Flugrichtung bleibt);
##   * Z zoomt (FOV eng, Kamera zurueck) — auch im Free-Look — und gibt KEIN Seitenruder mehr.
##   HOME=<test-home> Godot --headless --fixed-fps 60 --path . --script res://tools/_umschau_check.gd
extends SceneTree

var f := 0
var m: Node
var fehler := 0
var phase := 0
var t := 0
var d_normal := 0.0
var rel_alt := Vector3.ZERO
var sprung := 0.0
var vor_alt := Vector3.ZERO
var schritt_alt := Vector3.ZERO


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		get_root().add_child(m)
		return false
	if f == 20:
		m._set_mode(1)
		return false
	if f < 45:
		return false
	var fc = m.flight_ctrl
	var ac = fc.aircraft
	var cam: Camera3D = fc.camera
	var rel: Vector3 = cam.global_position - ac.get_global_transform_interpolated().origin
	t += 1
	match phase:
		0:
			if t == 1:
				_in_die_luft(fc, ac)
				fc.cam_zoom_target = 2.6
				fc.cam_zoom = 2.6
			_halten(ac)
			if t == 150:
				d_normal = rel.length()
				print("Flugkamera herausgezoomt: Abstand %.1f m (150 m/s)" % d_normal)
				_bild("umschau_1_normal")
				vor_alt = -ac.global_transform.basis.z
				rel_alt = rel
				sprung = 0.0
				_taste(KEY_C, true)
				phase = 1
				t = 0
		1:
			_halten(ac)
			if t < 60:
				sprung = maxf(sprung, (rel - rel_alt).length())
			rel_alt = rel
			if t == 59:
				print("  C halten: Abstand %.1f m" % rel.length())
			if t == 60:
				_pruef("C: Abstand bleibt (nicht herangezogen)", absf(rel.length() - d_normal) < d_normal * 0.08,
					"%.1f m gegen %.1f m" % [rel.length(), d_normal])
				_pruef("C druecken: kein Sprung", sprung < 1.0, "max %.2f m je Frame" % sprung)
				fc.flook_yaw = wrapf(fc.flook_yaw + 1.6, -PI, PI)    # Maus nach links schwenken
			if t == 150:
				var cf := -cam.global_transform.basis.z
				var vor: Vector3 = -ac.global_transform.basis.z
				var w := rad_to_deg(Vector2(cf.x, cf.z).angle_to(Vector2(vor.x, vor.z)))
				_pruef("C + Maus: Blick seitlich", absf(w) > 60.0, "%.0f Grad zur Flugrichtung" % w)
				_pruef("C + Maus: Flugrichtung bleibt", vor.angle_to(vor_alt) < deg_to_rad(4.0),
					"%.1f Grad" % rad_to_deg(vor.angle_to(vor_alt)))
				_pruef("C + Maus: Abstand bleibt", absf(rel.length() - d_normal) < d_normal * 0.08,
					"%.1f m" % rel.length())
				_bild("umschau_2_c_seitlich")
				_taste(KEY_Z, true)
			if t == 230:
				_pruef("C + Z: Zoom an", fc.zoom_t > 0.95 and cam.fov < 32.0,
					"zoom_t %.2f, FOV %.1f" % [fc.zoom_t, cam.fov])
				_bild("umschau_3_c_und_z")
				_pruef("C + Z: Kamera geht zurueck (Flieger bleibt etwa gleich gross)",
					rel.length() / d_normal > 1.7, "x%.2f" % (rel.length() / d_normal))
				_taste(KEY_Z, false)
			if t == 300:
				sprung = 0.0
				schritt_alt = rel - rel_alt
				rel_alt = rel
				_taste(KEY_C, false)
				phase = 2
				t = 0
		2:
			_halten(ac)
			# RUCK = Aenderung des Schritts von Frame zu Frame: die Rueckdrehung selbst ist eine
			# Bewegung, ein Sprung ist ein ploetzlicher Wechsel darin.
			var schritt := rel - rel_alt
			sprung = maxf(sprung, (schritt - schritt_alt).length())
			schritt_alt = schritt
			rel_alt = rel
			if t == 90:
				_pruef("C loslassen: weich zurueck (kein Ruck)", sprung < 0.8, "max %.2f m je Frame^2" % sprung)
				_pruef("C loslassen: zurueck auf Flugkamera", absf(rel.length() - d_normal) < d_normal * 0.08,
					"%.1f m" % rel.length())
				_tippen(KEY_N)           # Tastatur-Flug: dort ist in_yaw das reine Tastensignal
				phase = 3
				t = 0
		3:
			_halten(ac)
			if t == 5:
				_taste(KEY_Z, true)
			if t == 60:
				_pruef("Tastatur-Flug + Z: kein Seitenruder", absf(float(ac.in_yaw)) < 0.01,
					"in_yaw %.2f" % float(ac.in_yaw))
				_pruef("Tastatur-Flug + Z: Zoom an", fc.zoom_t > 0.95, "zoom_t %.2f" % fc.zoom_t)
				_taste(KEY_Z, false)
				_taste(KEY_E, true)
			if t == 90:
				_pruef("E: Seitenruder links", float(ac.in_yaw) < -0.5, "in_yaw %.2f" % float(ac.in_yaw))
				_taste(KEY_E, false)
				print("-> %d Beanstandungen" % fehler)
				quit()
				return true
	if f > 3000:
		print("TIMEOUT")
		quit()
	return false


# Geradeaus mit 150 m/s halten (die Pruefung misst die Kamera, nicht das Flugmodell).
func _halten(ac) -> void:
	ac.linear_velocity = -ac.global_transform.basis.z * 150.0
	ac.angular_velocity = Vector3.ZERO


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
	print("%-52s %s  %s" % [name, "OK" if ok else "FALSCH", info])
	if not ok:
		fehler += 1


## Im Fenster ein Bild nach user:// (headless gibt es keins).
func _bild(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw(false)
	get_root().get_viewport().get_texture().get_image().save_png("user://%s.png" % name)
