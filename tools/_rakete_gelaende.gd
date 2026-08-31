## HÄLT GELÄNDE EINE RAKETE AUF?
##
## Die beiden anderen Pruefstaende takten von Hand und haben deshalb gar keine Physikwelt
## — sie koennen ueber Gelaendetreffer nichts sagen. Genau das ist aber eine Behauptung,
## die im Code steht: SamSite nennt "Tiefflug hinter den Flanken" als Antwort auf eine
## Radarstellung, und Missile._gelaende_treffer soll sie einloesen. Ohne diese Messung
## waere beides ein Kommentar ohne Deckung.
##
## Dieser Pruefstand baut deshalb die ECHTE Welt und laesst die Engine takten. Er kostet
## dafuer eine halbe Minute Aufbauzeit.
##
## Gemessen wird zweierlei:
##   EINSCHLAG   Eine Rakete ohne Ziel wird steil nach unten geschossen. Sie muss
##               verschwinden, bevor ihre Lebensdauer abgelaufen ist, und zwar auf
##               Gelaendehoehe — nicht darunter und nicht erst nach 11 Sekunden.
##   DURCHFLUG   Dieselbe Rakete waagerecht auf einen Berghang. Sie darf nicht hindurch.
##
## Godot --headless --path . --script res://tools/_rakete_gelaende.gd
extends SceneTree

var f := 0
var _main: Node = null
var _phase := 0
var _m: Missile = null
var _letzte := Vector3.ZERO
var _start := Vector3.ZERO
var _frames := 0
var _boden := 0.0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if _main == null:
		_main = load("res://scenes/Main.tscn").instantiate()
		root.add_child(_main)
		return false
	if f < 40:
		return false      # Gelaende um den Ursprung aufbauen lassen
	match _phase:
		0:
			_starte_senkrecht()
			_phase = 1
		1:
			if _takt():
				print("EINSCHLAG  Start %5.0f m ueber Grund, Ende %5.0f m ueber Grund, %d Frames"
					% [_start.y - _boden, _letzte.y - _boden, _frames])
				print("           %s" % ("BESTANDEN — auf Gelaendehoehe zerlegt"
					if absf(_letzte.y - _boden) < 25.0 else "DURCHGEFALLEN — nicht am Boden"))
				_phase = 2
		2:
			_starte_waagerecht()
			_phase = 3
		3:
			if _takt():
				var weg := _letzte.distance_to(_start)
				print("DURCHFLUG  Weg bis zur Zerlegung: %5.0f m (die Wand steht bei rund 500 m)"
					% weg)
				print("           %s" % ("BESTANDEN — an der Wand gestoppt" if weg < 900.0
					else "DURCHGEFALLEN — durch den Berg geflogen"))
				quit()
	return false


## Ein Frame Beobachtung. Gibt true zurück, wenn die Rakete weg ist.
func _takt() -> bool:
	_frames += 1
	if is_instance_valid(_m) and not _m._tot:
		_letzte = _m.global_position
		if _frames < 1200:
			return false
	return true


func _rakete(pos: Vector3, richtung: Vector3) -> void:
	var welt: Node3D = _main.get("fly_world")
	_m = Missile.new()
	_m.feind_gruppe = "__keins__"      # kein Ziel: sie fliegt geradeaus
	_m.koeder_gruppe = "__keins__"
	_m.schub = 200.0
	_m.brenndauer = 1.5
	_m.cw = 0.0002
	_m.lebensdauer = 11.0
	_m.schwerkraft = 4.0
	welt.add_child(_m)
	_m.global_position = pos
	_m.v = richtung.normalized() * 220.0
	_start = pos
	_letzte = pos
	_frames = 0


func _starte_senkrecht() -> void:
	var tw = _main.get("terrain")
	var p := Vector3(120.0, 0.0, -300.0)
	_boden = tw.height_at(p.x, p.z)
	_rakete(Vector3(p.x, _boden + 400.0, p.z), Vector3(0.15, -1.0, 0.0))


func _starte_waagerecht() -> void:
	# AM TALSCHLUSS, NICHT AM PLATZ. Der erste Versuch schoss vom Startfeld nach Nordost —
	# und flog 2765 m weit, ohne etwas zu treffen. Der Grund war nicht die Rakete: rund um
	# den Platz ist das Gelaende auf 2,5 km in JEDER Richtung flach (hoechster Wert 43 m,
	# gemessen mit tools/_hangsuche.gd), und jenseits von VIEW_DIST gibt es ueberhaupt
	# keine Kollisionskoerper mehr. Der Test zielte also auf nichts.
	#
	# Die Wand hinter ADLERHORST steigt dagegen gemessen von 90 auf 545 m ueber 100 m
	# Talstation. Dorthin muessen die Chunks erst geladen werden — der Ort liegt 12 km vom
	# Ursprung entfernt. 250 m seitlich versetzt, damit die Rakete auf Fels trifft und
	# nicht ins Portal fliegt.
	var tw = _main.get("terrain")
	var achse := Vector2(0.6139, -0.7893)
	var quer := Vector2(achse.y, -achse.x)
	var st := Vector2(-11000.0, -2500.0) + achse * 8900.0 + quer * 250.0
	var p := Vector3(st.x, 0.0, st.y)
	tw.build_now_around(p, 1400.0)
	_boden = tw.height_at(p.x, p.z)
	_rakete(Vector3(p.x, _boden + 150.0, p.z), Vector3(achse.x, 0.0, achse.y))
