## TRAEGT DER BODEN NOCH? — Probe in der ECHTEN Physikwelt, nicht auf dem Papier.
##
## tools/_koll_fehler.gd rechnet den Fehler des groberen Kollisionsrasters aus den
## Hoehendaten aus. Das ist die Theorie. Diese Datei prueft die Praxis: sie baut das
## Gelaende samt Physikkoerpern auf und schiesst Strahlen von oben nach unten — also
## genau das, was auch das Fahrwerk tut. Gemeldet wird, wo KEIN Treffer kommt (dort
## faellt das Flugzeug durch) und wie weit der Treffer vom sichtbaren Boden abweicht.
##
## Godot --headless --path . --script res://tools/_koll_probe.gd -- [n=40] [x=] [z=]
extends SceneTree

var _tw: TerrainWorld
var _mitte := Vector3(600, 0, -400)
var _n := 40
var _phase := 0


func _process(_d: float) -> bool:
	if _phase == 0:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("n="):
				_n = int(a.substr(2))
			elif a.begins_with("x="):
				_mitte.x = float(a.substr(2))
			elif a.begins_with("z="):
				_mitte.z = float(a.substr(2))
		_tw = TerrainWorld.new()
		root.add_child(_tw)
		_tw.setup(1337, [{"pos": Vector3.ZERO, "r_flat": 240.0, "r_blend": 620.0}], [], [], [])
		# Synchron bauen, damit im naechsten Frame wirklich alles steht — inklusive
		# Kollisionskoerper (build_now_around liegt innerhalb von KOLLISIONS_DIST).
		_tw.build_now_around(_mitte, 900.0)
		_phase = 1
		return false
	if _phase < 4:
		_phase += 1     # der Physikwelt ein paar Frames geben, die Koerper aufzunehmen
		return false

	var raum := root.get_world_3d().direct_space_state
	var kein_treffer := 0
	var proben := 0
	var summe := 0.0
	var schlimmster := 0.0
	var schlimm_bei := Vector2.ZERO
	# Gleichmaessig ueber den gebauten Bereich rastern, mit Versatz, damit die Proben
	# nicht ausgerechnet auf den Rasterpunkten liegen (dort ist der Fehler naturgemaess 0).
	for j in _n:
		for i in _n:
			var x := _mitte.x - 700.0 + (float(i) + 0.37) * 1400.0 / float(_n)
			var z := _mitte.z - 700.0 + (float(j) + 0.61) * 1400.0 / float(_n)
			var soll := _tw.height_at(x, z)
			if soll < TerrainWorld.SEA_Y + 1.0:
				continue    # unter Wasser gibt es kein Gelaende zu treffen
			proben += 1
			var von := Vector3(x, soll + 300.0, z)
			var nach := Vector3(x, soll - 300.0, z)
			var p := PhysicsRayQueryParameters3D.create(von, nach)
			p.collide_with_areas = false
			var tr := raum.intersect_ray(p)
			if tr.is_empty():
				kein_treffer += 1
				continue
			var got: Vector3 = tr["position"]
			var f := got.y - soll
			summe += absf(f)
			if absf(f) > schlimmster:
				schlimmster = absf(f)
				schlimm_bei = Vector2(x, z)
	print("=== STRAHLENPROBE IN DER PHYSIKWELT (KOLL_SCHRITT=%d) ==="
		% TerrainWorld.KOLL_SCHRITT)
	print("  %d Proben ueber Land" % proben)
	print("  OHNE TREFFER (Flugzeug wuerde durchfallen): %d   <- muss 0 sein" % kein_treffer)
	print("  Abweichung vom sichtbaren Boden: Mittel %.2f m, groesste %.2f m bei (%.0f, %.0f)"
		% [summe / maxf(proben - kein_treffer, 1), schlimmster, schlimm_bei.x, schlimm_bei.y])
	_tw.queue_free()
	quit()
	return true
