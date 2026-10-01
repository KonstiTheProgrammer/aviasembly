## NEUE WAFFEN IM FLUG: haengen, zaehlen, abfeuern — in der echten Main-Szene.
##
## _waffen_modelle_check prueft die MODELLE. Ob ein neues Katalogteil auch als Waffe ankommt
## (Start nicht blockiert, FlightController kennt den Typ, die Gruppe erscheint, ein Schuss
## verbraucht genau eine), prueft dieses Werkzeug: es nimmt die Vorlage "sturmjet" und
## tauscht deren vier Waffenarten gegen je ein neues Teil desselben Grundtyps.
##
## Schreibt nach user:// — NUR mit umgebogenem Spielstand-Ordner starten (Windows: APPDATA,
## macOS: HOME), vorher aviassembly_progress.json dorthin kopieren:
##   APPDATA=<ordner> Godot --headless --fixed-fps 60 --path . --script res://tools/_waffen_neu_flug.gd
extends SceneTree

const TAUSCH := {"missile": "r73", "missile_heavy": "aim54", "rocket_pod": "s24", "bomb": "fab500"}
const ZIEL := "user://_waffen_neu_flug.json"

var m: Node = null
var f := 0
var fc: Node = null
var fehler := 0
var schritt := 0
var warten := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 20:
		# Sandbox erzwingen: im Survival waeren die neuen Teile nicht gekauft und der Start
		# zu Recht gesperrt — das ist hier nicht die Frage.
		(m.get("game") as Node).call("start_mode", 1)
		var quelle := FileAccess.open("res://designs/sturmjet.json", FileAccess.READ)
		var teile: Array = JSON.parse_string(quelle.get_as_text())
		var getauscht := 0
		for e in teile:
			var alt := String(e["id"])
			if TAUSCH.has(alt):
				e["id"] = TAUSCH[alt]
				getauscht += 1
		var aus := FileAccess.open(ZIEL, FileAccess.WRITE)
		aus.store_string(JSON.stringify(teile))
		aus.close()
		_pruef("Vorlage traegt acht Waffen zum Tauschen", getauscht == 8, "%d" % getauscht)
		_pruef("Entwurf laedt", bool(m.call("_load_design_from", ZIEL)))
		return false
	if f == 30:
		m.call("_set_mode", 1)
		return false
	if f < 60:
		return false
	if fc == null:
		fc = m.get("flight_ctrl")
		var ac: RigidBody3D = fc.get("aircraft")
		_pruef("Start nicht blockiert (Flugzeug gebaut)", ac != null)
		if ac == null:
			return _ende()
		ac.freeze = true
		ac.global_transform = Transform3D(Basis(), Vector3(4000.0, 900.0, 4000.0))
		_pruef("zwei R-73 als IR-KURZ", _munition("missile") == 2, "%d" % _munition("missile"))
		_pruef("zwei AIM-54 als RADAR-MITTEL", _munition("missile_heavy") == 2, "%d" % _munition("missile_heavy"))
		_pruef("zwei S-24 als Rakete", _munition("rocket") == 2, "%d" % _munition("rocket"))
		_pruef("zwei FAB-500 als Bombe", _munition("bomb") == 2, "%d" % _munition("bomb"))
		var ids: Array[String] = []
		for g in fc.get("weapon_groups"):
			ids.append(String(g["id"]))
		_pruef("Gruppen Raketen, Lenkwaffen, Bomben", ids.has("rocket") and ids.has("missile") and ids.has("bomb"),
			str(ids))
		return false
	warten += 1
	if warten < 20:
		return false
	warten = 0
	match schritt:
		0:
			fc.call("_fire_primary", ["rocket"], true)
			_pruef("S-24: ein Schuss verbraucht eine", _munition("rocket") == 1, "%d" % _munition("rocket"))
		1:
			fc.call("_fire_primary", ["missile"], true)
			_pruef("R-73: ein Schuss verbraucht eine", _munition("missile") == 1, "%d" % _munition("missile"))
		2:
			fc.call("_drop_bomb", true)
			_pruef("FAB-500: ein Abwurf verbraucht eine", _munition("bomb") == 1, "%d" % _munition("bomb"))
		_:
			return _ende()
	schritt += 1
	return false


func _ende() -> bool:
	print("URTEIL: ", "OK" if fehler == 0 else "FEHLER (%d)" % fehler)
	quit(0 if fehler == 0 else 1)
	return true


func _munition(ty: String) -> int:
	var n := 0
	for w in fc.get("weapons"):
		if String(w["type"]) == ty:
			n += maxi(int(w["ammo"]), 0)
	return n


func _pruef(name: String, ok: bool, info := "") -> void:
	print("%-48s %s  %s" % [name, "OK" if ok else "FALSCH", info])
	if not ok:
		fehler += 1
