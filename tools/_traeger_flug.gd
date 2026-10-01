## FLUGZEUGTRAEGER IM FLUG: stehen, starten, aufsetzen — in der echten Main-Szene.
##
## _traeger_check prueft Modell und Kollision fuer sich. Ob man auf dem Deck auch wirklich
## FLIEGEN kann, prueft dieses Werkzeug mit dem Erststart-Flugzeug an jedem Traeger aus
## Main.TRAEGER, dort wo er im Spiel liegt:
##   1. STEHEN   am Anfang der Landebahn abgesetzt, 2,5 s: bleibt auf Deckhoehe liegen
##               (faellt nicht durch, rutscht nicht, nichts bricht).
##   2. START    Vollgas in Bahnrichtung: hebt ab, ohne danach ins Wasser zu sacken.
##   3. AUFSETZEN  mit 32 m/s und 1,5 m/s Sinken ueber dem Heck losgelassen, Schub auf
##               Bremse: setzt auf, ohne zu zerschellen. Ob es VOR dem Bahnende steht, wird
##               gemessen und gemeldet (es gibt keine Fangseile).
##
## Schreibt nach user:// — NUR mit umgebogenem Spielstand-Ordner starten (Windows: APPDATA,
## macOS: HOME), vorher aviassembly_progress.json dorthin kopieren:
##   APPDATA=<ordner> Godot --headless --fixed-fps 60 --path . --script res://tools/_traeger_flug.gd
extends SceneTree

const MASSE := "res://tools/traeger_modelle_masse.json"

var m: Node = null
var f := 0
var fc: Node = null
var fehler := 0
var daten: Dictionary = {}
var idx := 0
var phase := -1
var t := 0.0
var _deck_y := 0.0
var _a := Vector3.ZERO
var _b := Vector3.ZERO
var _max_ueber := 0.0
var _min_y := 1e9
var _kontakt := false
var _stand_bei := -1.0


func _process(delta: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 20:
		(m.get("game") as Node).call("start_mode", 1)
		(m.get("build_ctrl") as Node).call("load_design", m.call("_default_design"))
		daten = JSON.parse_string(FileAccess.open(MASSE, FileAccess.READ).get_as_text())
		return false
	if f == 30:
		m.call("_set_mode", 1)
		return false
	if f < 60:
		return false
	if fc == null:
		fc = m.get("flight_ctrl")
		_pruef("Flugzeug gebaut", fc.get("aircraft") != null)
		if fc.get("aircraft") == null:
			return _ende()
		_naechste_phase()
		return false
	var ac: RigidBody3D = fc.get("aircraft")
	if ac == null or not is_instance_valid(ac):
		_pruef("Flugzeug noch da", false)
		return _ende()
	t += delta
	var traeger: Array = m.get("TRAEGER")
	var name := String(traeger[idx]["name"])
	var p := ac.global_position
	match phase:
		0:   # STEHEN
			if t > 2.5:
				var soll := _deck_y + float(fc.get("spawn_height"))
				_pruef("%s: steht auf dem Deck" % name, absf(p.y - soll) < 0.6 and not bool(ac.get("exploded")),
					"Hoehe %.2f m, Soll %.2f m, v %.2f m/s, Fahrwerk %s" % [p.y, soll,
					ac.linear_velocity.length(), str(ac.get("gear_status"))])
				_pruef("%s: rutscht nicht" % name, ac.linear_velocity.length() < 1.0 and p.distance_to(_a) < 6.0,
					"%.1f m vom Absetzpunkt" % p.distance_to(_a))
				_naechste_phase()
		1:   # START
			fc.set("throttle", 1.0)
			if ac.linear_velocity.length() > 28.0:
				fc.set("look_pitch", 0.16)
			_max_ueber = maxf(_max_ueber, p.y - _deck_y)
			if t > 1.0:
				_min_y = minf(_min_y, p.y)
			if t > 14.0:
				_pruef("%s: hebt ab" % name, _max_ueber > 12.0 and not bool(ac.get("exploded")),
					"bis %.0f m ueber Deck, tiefster Punkt %.1f m ueber dem Meer" % [_max_ueber,
					_min_y - float(TerrainWorld.SEA_Y)])
				_pruef("%s: sackt nicht ins Wasser" % name, _min_y > float(TerrainWorld.SEA_Y) + 4.0)
				_naechste_phase()
		2:   # AUFSETZEN
			fc.set("throttle", -0.4)
			if ac.get_contact_count() > 0:
				_kontakt = true
			if _kontakt and _stand_bei < 0.0 and ac.linear_velocity.length() < 1.5:
				_stand_bei = (p - _a).dot((_b - _a).normalized())
			if t > 14.0:
				_pruef("%s: setzt auf, ohne zu zerschellen" % name, _kontakt and not bool(ac.get("exploded")),
					"Fahrwerk %s" % str(ac.get("gear_status")))
				var bahn := _a.distance_to(_b)
				if _stand_bei >= 0.0 and p.y > _deck_y - 0.5:
					print("    steht nach %.0f m (Bahn %.0f m)" % [_stand_bei, bahn])
				else:
					print("    HINWEIS: rollt ueber das Bahnende hinaus (Bahn %.0f m, keine Fangseile)" % bahn)
				idx += 1
				phase = -1
				if idx >= traeger.size():
					return _ende()
				_naechste_phase()
	return false


## Flugzeug fuer die naechste Phase am aktuellen Traeger hinstellen.
func _naechste_phase() -> void:
	phase += 1
	t = 0.0
	var traeger: Array = m.get("TRAEGER")
	var schiff: Dictionary = traeger[idx]
	var node := (m.get("fly_world") as Node3D).get_node_or_null("Traeger_" + String(schiff["id"])) as Node3D
	if node == null:
		_pruef("%s: steht in der Welt" % String(schiff["name"]), false)
		return
	var bahn: Array = daten[String(schiff["id"])]["bahn"]
	_a = node.global_transform * Vector3(bahn[0][0], bahn[0][1], bahn[0][2])
	_b = node.global_transform * Vector3(bahn[1][0], bahn[1][1], bahn[1][2])
	_deck_y = _a.y
	var richtung := (_b - _a).normalized()
	_a += richtung * 14.0                       # ganzes Flugzeug sicher auf dem Deck
	var ac: RigidBody3D = fc.get("aircraft")
	if phase == 2 or bool(ac.get("exploded")):
		fc.call("_reset_to_runway")             # frisch: Fahrwerk draussen, nichts gebrochen
		ac = fc.get("aircraft")
	var basis := Basis.looking_at(richtung, Vector3.UP)
	var hoch := float(fc.get("spawn_height"))
	fc.set("throttle", 0.0)
	ac.set("throttle", 0.0)
	if phase == 2:
		ac.global_transform = Transform3D(basis, _a + Vector3.UP * (hoch + 1.6))
		ac.linear_velocity = richtung * 32.0 + Vector3.DOWN * 1.5
		_kontakt = false
		_stand_bei = -1.0
	else:
		ac.global_transform = Transform3D(basis, _a + Vector3.UP * hoch)
		ac.linear_velocity = Vector3.ZERO
	ac.angular_velocity = Vector3.ZERO
	if fc.has_method("_reset_mouse_state"):
		fc.call("_reset_mouse_state")
	_max_ueber = 0.0
	_min_y = 1e9


func _ende() -> bool:
	print("URTEIL: ", "OK" if fehler == 0 else "FEHLER (%d)" % fehler)
	quit(0 if fehler == 0 else 1)
	return true


func _pruef(name: String, ok: bool, info := "") -> void:
	print("%-48s %s  %s" % [name, "OK" if ok else "FALSCH", info])
	if not ok:
		fehler += 1
