## ERKENNT DER FLUGCODE DIE BOMBEN IM SCHACHT?
##
## Die letzte ungepruefte Verbindung des Systems. Der Lichtraum stimmt (geprueft), die
## Sperre greift (geprueft) — aber ob FlightController beim Zusammenbau des ECHTEN
## Bauplans die vier Bomben auch wirklich dem Schacht zuordnet, entscheidet sich in einer
## Schleife, die man von aussen nicht sieht. Faellt die Zuordnung aus, ist die Sperre
## wirkungslos und niemand merkt es: es wuerde einfach wie vorher geworfen.
##
## Deshalb wird hier die ganze Kette gefahren: Bauplan laden, in den Flug schalten, die
## Waffenliste befragen.
##
## Godot --headless --path . --script res://tools/_falke_flug.gd
extends SceneTree

var f := 0
var _main: Node = null


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if _main == null:
		_main = load("res://scenes/Main.tscn").instantiate()
		root.add_child(_main)
		return false
	if f == 20:
		var ok: bool = _main.call("_load_design_from", "res://designs/nachtfalke.json")
		print("Bauplan geladen: %s" % str(ok))
		if not ok:
			quit()
			return true
		return false
	if f == 40:
		print("Modus vor dem Umschalten: %d" % int(_main.get("mode")))
		_main.call("_set_mode", 1)     # Mode.FLY
		return false
	if f == 60:
		print("Modus nach dem Umschalten: %d" % int(_main.get("mode")))
		return false
	if f < 140:
		return false

	var fc = _main.get("flight_ctrl")
	var ac = fc.get("aircraft")
	if ac == null:
		print("kein Flugzeug gebaut")
		quit()
		return true
	var waffen: Array = fc.get("weapons")
	var bomben := 0
	var im_schacht := 0
	for w in waffen:
		if String(w.get("type", "")) != "bomb":
			continue
		bomben += 1
		var s := bool(w.get("schacht", false))
		if s:
			im_schacht += 1
		var o: Vector3 = w["off"]
		print("  Bombe bei (%5.2f,%5.2f,%5.2f)  %s"
			% [o.x, o.y, o.z, "IM SCHACHT" if s else "aussen"])
	print("Bomben %d, davon im Schacht %d" % [bomben, im_schacht])
	print("Klappen gefunden: %d   Status \"%s\"   Abwurf frei: %s"
		% [ac.get("_bay_doors").size(), ac.get("bay_status"), str(ac.call("bay_frei"))])

	var fehler := 0
	if bomben != 4 or im_schacht != 4:
		fehler += 1
		print("!! nicht alle vier Bomben dem Schacht zugeordnet")
	if ac.get("_bay_doors").size() != 2:
		fehler += 1
		print("!! Klappen nicht gefunden")
	if ac.call("bay_frei"):
		fehler += 1
		print("!! Abwurf ist frei, obwohl der Schacht beim Start zu sein muss")
	print("-> %d Beanstandungen" % fehler)
	quit()
	return true
