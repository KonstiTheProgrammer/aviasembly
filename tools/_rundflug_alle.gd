## RUNDFLUG MIT JEDER VORLAGE — der Smoketest fuer "startet, fliegt, schiesst, landet
## wieder im Hangar", ueber ALLE Presets aus Main.PRESETS.
##
## Pro Vorlage: laden -> Flug -> Vollgas, nach dem Abheben leicht ziehen -> jede
## Waffengruppe feuern, Bombe, Fahrwerk, Schacht -> Reset -> zurueck in den Hangar.
## Geloggt wird je Vorlage eine Zeile mit Hoehe/Tempo/Status; Laufzeitfehler landen
## ohnehin auf stderr und stehen durch die Marker "== <id>" direkt an der Vorlage.
##
## NICHT IM ECHTEN BENUTZERORDNER LAUFEN LASSEN: Main schreibt beim Laden den Autosave.
## Deshalb mit umgebogenem HOME starten (Godot nimmt user:// unter macOS aus $HOME):
##   HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/_rundflug_alle.gd
## --fixed-fps 60 macht jeden Frame zu genau einem Physikschritt: schnell UND reproduzierbar.
extends SceneTree

const T_FLUG := 40.0          # Sekunden je Vorlage im Flug
var m: Node = null
var f := 0
var idx := -1
var t := 0.0
var phase := 0
var ergebnisse: Array = []
var _max_h := 0.0
var _max_v := 0.0
var _nan := false
var _schuesse := 0
var _abgehoben_t := -1.0


func _process(delta: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f < 20:
		return false
	var presets: Array = [["_standard", "Erststart"]] + (m.get("PRESETS") as Array)
	if idx < 0:
		idx = 0
		_start(presets[idx][0])
		return false
	t += delta
	var fc = m.get("flight_ctrl")
	var ac = fc.get("aircraft")
	match phase:
		0:
			if t > 0.3:
				m.call("_set_mode", 1)
				phase = 1
				t = 0.0
		1:
			if ac == null or not is_instance_valid(ac):
				print("  !! kein Flugzeug gebaut")
				_weiter(presets)
				return false
			fc.set("throttle", 1.0)
			var p: Vector3 = ac.global_position
			if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
				_nan = true
			var v: float = ac.linear_velocity.length()
			_max_v = maxf(_max_v, v)
			var hoehe: float = p.y - float(fc.get("spawn_height"))
			_max_h = maxf(_max_h, hoehe)
			if _abgehoben_t < 0.0 and hoehe > 3.0:
				_abgehoben_t = t
			# Nach dem Abheben sanft ziehen (Maus-Flug: Blickrichtung 8 Grad hoch).
			if v > 45.0:
				fc.set("look_pitch", 0.14)
			if t > 22.0 and t < 30.0 and int(t * 4.0) != int((t - delta) * 4.0):
				_feuern(fc)
			if absf(t - 24.0) < delta * 0.5:
				ac.call("toggle_gear")
				if ac.has_method("toggle_bay"):
					ac.call("toggle_bay")
			if absf(t - 32.0) < delta * 0.5:
				fc.call("_reset_to_runway")
			if t > T_FLUG:
				_bericht(presets[idx][0], ac)
				m.call("_set_mode", 0)
				phase = 2
				t = 0.0
		2:
			if t > 0.5:
				_weiter(presets)
	return false


func _start(id: String) -> void:
	print("== %s" % id)
	if id == "_standard":
		# Das Erststart-Flugzeug (Main._default_design) — das, was ein neuer Spieler ohne
		# Speicherstand als erstes fliegt. Es hing einmal mit frei schwebenden Raedern fest.
		(m.get("build_ctrl") as Node).call("load_design", m.call("_default_design"))
		var frei: int = (m.get("build_ctrl") as Node).call("floating_count")
		if frei > 0:
			print("  !! %d Teil(e) haengen frei — Start waere blockiert" % frei)
	else:
		var ok: bool = m.call("_load_design_from", "res://designs/%s.json" % id)
		if not ok:
			print("  !! Vorlage nicht ladbar")
	phase = 0
	t = 0.0
	_max_h = 0.0
	_max_v = 0.0
	_nan = false
	_schuesse = 0
	_abgehoben_t = -1.0


func _feuern(fc) -> void:
	var gruppen: Array = fc.get("weapon_groups")
	for i in gruppen.size():
		fc.set("weapon_sel", i)
		var n_vor := _geschosse(fc)
		fc.call("_fire_primary", gruppen[i]["types"], false)
		_schuesse += maxi(0, _geschosse(fc) - n_vor)
	fc.call("_drop_bomb", true)


func _geschosse(fc) -> int:
	var wr = fc.get("world_root")
	return 0 if wr == null else (wr as Node).get_child_count()


func _bericht(id: String, ac) -> void:
	var zeile := "  %-12s  max Hoehe %6.1f m   max v %5.1f m/s   abgehoben %s   Schuesse %3d   NaN %s   Fluegel %s   Fahrwerk %s" % [
		id, _max_h, _max_v,
		("bei %.1f s" % _abgehoben_t) if _abgehoben_t >= 0.0 else "NIE",
		_schuesse, str(_nan), str(ac.get("wing_status")), str(ac.get("gear_status"))]
	print(zeile)
	ergebnisse.append(zeile)


func _weiter(presets: Array) -> void:
	idx += 1
	if idx >= presets.size():
		print("\n==== ZUSAMMENFASSUNG")
		for z in ergebnisse:
			print(z)
		quit()
		return
	_start(presets[idx][0])
