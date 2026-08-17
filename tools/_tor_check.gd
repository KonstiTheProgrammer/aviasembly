## ABNAHME DES FELSENTORS: traegt die Kollision, und ist die Durchfahrt frei?
##
## Zwei Fragen, die man dem Code nicht ansieht:
##   1. Das Tor ist das einzige Wahrzeichen MIT Kollisionskoerper. Greift der wirklich —
##      oder fliegt man durch massiven Fels?
##   2. Wie gross ist das Loch? Ein Tor, durch das man nicht passt, ist eine Wand.
##
## Godot --headless --path . --script res://tools/_tor_check.gd
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 4:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	if f < 8:
		return false
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var p: Vector2 = start + dir * float(K["TOR_LAENGS"])
	var boden: float = main.terrain.height_at(p.x, p.y)
	var raum := root.get_world_3d().direct_space_state

	# 1) Trifft ein Strahl von der Seite den Bogen? (Bogenscheitel liegt bei +260 m)
	var quer := Vector2(dir.y, -dir.x)
	var treffer := 0
	for hoehe in [200.0, 230.0, 255.0]:
		var von := Vector3(p.x + quer.x * 600.0, boden + hoehe, p.y + quer.y * 600.0)
		var nach := Vector3(p.x - quer.x * 600.0, boden + hoehe, p.y - quer.y * 600.0)
		var q := PhysicsRayQueryParameters3D.create(von, nach)
		if not raum.intersect_ray(q).is_empty():
			treffer += 1
	print("Kollision des Bogens: %d von 3 Querstrahlen treffen (muss 3 sein)" % treffer)

	# 2) Durchfahrt: senkrechtes Raster in der Torebene, wo ist frei?
	var frei_b := 0.0
	var frei_h := 0.0
	for hh in range(1, 30):
		var hoehe := float(hh) * 10.0
		var breit := 0.0
		for qq in range(-30, 31):
			var off := float(qq) * 10.0
			var pos := Vector3(p.x + quer.x * off, boden + hoehe, p.y + quer.y * off)
			# Kurzer Strahl laengs der Flugrichtung: trifft er nichts, ist die Stelle frei.
			var q2 := PhysicsRayQueryParameters3D.create(
				pos - Vector3(dir.x, 0, dir.y) * 260.0, pos + Vector3(dir.x, 0, dir.y) * 260.0)
			if raum.intersect_ray(q2).is_empty():
				breit += 10.0
		if breit > frei_b:
			frei_b = breit
			frei_h = hoehe
	print("Freie Durchfahrt: %.0f m breit, breiteste Stelle %.0f m ueber dem Talboden"
		% [frei_b, frei_h])
	print("Talboden am Tor: %.0f m" % boden)
	quit()
	return true
