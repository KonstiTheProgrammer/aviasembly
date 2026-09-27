## GRAFIKEINSTELLUNGEN: alle Kombinationen, und ausgeblendete Wolken sind keine Wolken.
##
##   KOMBINATIONEN  jede Stellung von Wolkenschatten, Sonnenschatten, Baumweite,
##                  Wolkenlagen und Aufloesung einmal anwenden (keine Fehler)
##   WOLKE AUS      Flugzeug mitten in eine Kumuluswolke setzen: Dichte hoch. Wolkenlagen
##                  auf "keine" -> Dichte 0 (kein Nebel, keine Turbulenz, keine Deckung).
##                  Vorher zaehlten die unsichtbaren Wolken weiter.
##
##   HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/_grafik_check.gd
extends SceneTree

var m: Node = null
var f := 0
var fehler := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 20:
		m.call("_set_mode", 1)
	if f == 40:
		_lauf()
		quit()
	return false


func _lauf() -> void:
	var game = m.get("game")
	var alt := [game.gfx_wolkenschatten, game.gfx_sonnenschatten, game.gfx_baumweite,
		game.gfx_wolkenlagen, game.gfx_aufloesung]
	var n := 0
	for ws in [false, true]:
		for ss in [false, true]:
			for bw in [0, 1, 2]:
				for wl in [0, 1, 2]:
					for au in [70, 85, 100]:
						game.gfx_wolkenschatten = ws
						game.gfx_sonnenschatten = ss
						game.gfx_baumweite = bw
						game.gfx_wolkenlagen = wl
						game.gfx_aufloesung = au
						m.call("grafik_anwenden")
						n += 1
	_pruef("alle %d Kombinationen angewandt" % n, true)

	# Eine Wolke der untersten Lage suchen und das Flugzeug hineinsetzen.
	var felder: Array = m.get("cloud_fields")
	game.gfx_wolkenlagen = 2
	m.call("grafik_anwenden")
	var mitte := Vector3.ZERO
	var gefunden := false
	for w in (felder[0] as Node3D).get_children():
		if w is MeshInstance3D and (w as MeshInstance3D).visible and w.has_meta("wc"):
			mitte = (w as MeshInstance3D).position + (w.get_meta("wc") as Vector3)
			gefunden = true
			break
	_pruef("Kumuluswolke gefunden", gefunden)
	var d_an: float = CloudField.dichte_bei_allen(felder, mitte)
	_pruef("in der Wolke: Dichte hoch", d_an > 0.9, "%.2f" % d_an)
	game.gfx_wolkenlagen = 0
	m.call("grafik_anwenden")
	var d_aus: float = CloudField.dichte_bei_allen(felder, mitte)
	_pruef("Wolkenlagen 'keine': Dichte 0", d_aus == 0.0, "%.2f" % d_aus)
	game.gfx_wolkenlagen = 1
	m.call("grafik_anwenden")
	var d_eins: float = CloudField.dichte_bei_allen(felder, mitte)
	_pruef("Wolkenlagen 'nur Kumulus': Kumulus zaehlt", d_eins > 0.9, "%.2f" % d_eins)

	game.gfx_wolkenschatten = alt[0]
	game.gfx_sonnenschatten = alt[1]
	game.gfx_baumweite = alt[2]
	game.gfx_wolkenlagen = alt[3]
	game.gfx_aufloesung = alt[4]
	m.call("grafik_anwenden")
	print("-> %d Beanstandungen" % fehler)


func _pruef(name: String, ok: bool, info := "") -> void:
	print("%-44s %s  %s" % [name, "OK" if ok else "FALSCH", info])
	if not ok:
		fehler += 1
