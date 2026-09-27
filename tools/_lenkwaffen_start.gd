## LENKWAFFEN AUS DEM COCKPIT: Aufschalten -> Abschuss -> Treffer, ueber FlightController.
##
## _raketen_pruefstand prueft die FLUGPHYSIK einer Missile. Ob der Weg vom Piloten dorthin
## traegt — Waffengruppe waehlen, Aufschaltung (_update_lock), _fire_primary mit
## Einzelschuss, Uebergabe des Ziels an den Suchkopf, Munition und Teil-Abwurf — prueft
## dieses Werkzeug in der echten Main-Szene mit der Vorlage "sturmjet".
##
##   HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/_lenkwaffen_start.gd
extends SceneTree

var m: Node = null
var f := 0
var fc: Node = null
var ac: RigidBody3D = null
var ziel: Node3D = null
var phase := 0
var t := 0
var fehler := 0
var typ := ""
var munition_vorher := 0
const LAEUFE := ["missile", "missile_heavy"]
var lauf := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 20:
		m.call("_load_design_from", "res://designs/sturmjet.json")
		return false
	if f == 30:
		m.call("_set_mode", 1)
		return false
	if f < 60:
		return false
	fc = m.get("flight_ctrl")
	ac = fc.get("aircraft")
	t += 1
	match phase:
		0:
			typ = LAEUFE[lauf]
			ac.freeze = true
			# FREIER LUFTRAUM, weit weg vom Ballonfeld vor der Startbahn: ein Waermesucher
			# nimmt das STAERKSTE Signal im Blickfeld, und ein naher Ballon ist heller als ein
			# Luftschiff von vorn — das ist gewollt, wuerde hier aber etwas anderes messen.
			ac.global_transform = Transform3D(Basis(), Vector3(4000.0, 700.0, 4000.0))
			# Ziel 700 m voraus, leicht versetzt — innerhalb des 28-Grad-Aufschaltkegels.
			var tg := Target.new()
			(m.get("targets_root") as Node).add_child(tg)
			tg.setup("airship", Vector3(4060.0, 720.0, 3300.0), Color(0.8, 0.8, 0.9))
			ziel = tg
			# Lenkwaffengruppe waehlen
			var gruppen: Array = fc.get("weapon_groups")
			for i in gruppen.size():
				if String(gruppen[i]["id"]) == "missile":
					fc.set("weapon_sel", i)
			munition_vorher = _munition(typ)
			phase = 1
			t = 0
		1:
			# Aufschaltung laeuft im Physiktakt des FlightControllers.
			if int(fc.get("lock_stufe")) >= 2 and fc.get("lock_ziel") == ziel:
				print("[%s] Aufschaltung nach %.2f s" % [typ, t / 60.0])
				# nur DIESEN Typ feuern (die Gruppe enthaelt beide)
				fc.call("_fire_primary", [typ], true)
				var nachher := _munition(typ)
				_pruef("[%s] Abschuss verbraucht genau eine Waffe" % typ,
					nachher == munition_vorher - 1, "%d -> %d" % [munition_vorher, nachher])
				phase = 2
				t = 0
			elif t > 60 * 5:
				_pruef("[%s] Aufschaltung innerhalb 5 s" % typ, false,
					"stufe %d" % int(fc.get("lock_stufe")))
				_weiter()
		2:
			if not is_instance_valid(ziel) or ziel.is_queued_for_deletion():
				print("[%s] Treffer nach %.2f s" % [typ, t / 60.0])
				_pruef("[%s] Ziel zerstoert" % typ, true)
				_weiter()
			elif t > 60 * 12:
				_pruef("[%s] Ziel zerstoert" % typ, false, "HP %.1f" % float(ziel.get("hp")))
				_weiter()
	return false


func _weiter() -> void:
	if is_instance_valid(ziel):
		ziel.queue_free()
	lauf += 1
	phase = 0
	t = 0
	if lauf >= LAEUFE.size():
		print("-> %d Beanstandungen" % fehler)
		quit()


func _munition(ty: String) -> int:
	var n := 0
	for w in fc.get("weapons"):
		if String(w["type"]) == ty:
			n += maxi(int(w["ammo"]), 0)
	return n


func _pruef(name: String, ok: bool, info := "") -> void:
	print("%-52s %s  %s" % [name, "OK" if ok else "FALSCH", info])
	if not ok:
		fehler += 1
