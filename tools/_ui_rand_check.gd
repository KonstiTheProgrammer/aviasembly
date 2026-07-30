## Startet die ECHTE Main-Szene, oeffnet den Werkzeuge-Reiter (Lackieren) und misst,
## ob irgendein Bedienelement ueber den Bildschirmrand oder aus seinem Panel laeuft.
## Dazu ein Screenshot zum Draufschauen.
extends SceneTree
var f := 0
var m: Node


func _shot(n: String) -> void:
	get_root().get_viewport().get_texture().get_image().save_png("user://" + n)
	print("SHOT ", n)


# Laeuft ein Control ueber den Bildschirm hinaus?
func _pruefe(c: Control, schirm: Vector2, pfad: String, raus: Array) -> void:
	if not c.is_visible_in_tree():
		return
	var r: Rect2 = c.get_global_rect()
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var ueber := []
	if r.position.x < -0.5:
		ueber.append("links %.0f" % r.position.x)
	if r.position.y < -0.5:
		ueber.append("oben %.0f" % r.position.y)
	if r.end.x > schirm.x + 0.5:
		ueber.append("rechts %.0f" % (r.end.x - schirm.x))
	if r.end.y > schirm.y + 0.5:
		ueber.append("unten %.0f" % (r.end.y - schirm.y))
	if not ueber.is_empty():
		raus.append("%s  [%s]  Rect %.0f,%.0f %.0fx%.0f" % [pfad, ", ".join(ueber),
			r.position.x, r.position.y, r.size.x, r.size.y])


func _gehe(n: Node, schirm: Vector2, pfad: String, raus: Array, tiefe: int) -> void:
	if n is Control:
		_pruefe(n as Control, schirm, pfad, raus)
	if tiefe > 14:
		return
	for c in n.get_children():
		_gehe(c, schirm, pfad + "/" + String(c.name), raus, tiefe + 1)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var ps: PackedScene = load("res://scenes/Main.tscn")
		m = ps.instantiate()
		get_root().add_child(m)
		return false
	if f == 40:
		# Werkzeuge-Reiter oeffnen (dort sitzt LACKIEREN)
		m._on_tools_icon()
		return false
	if f == 70:
		_shot("ui_werkzeuge.png")
		var schirm: Vector2 = get_root().get_viewport().get_visible_rect().size
		print("Bildschirm: %.0f x %.0f" % [schirm.x, schirm.y])
		var raus: Array = []
		_gehe(m, schirm, "", raus, 0)
		# Zweiter Fehler aus dem Screenshot: die obere Werkzeugleiste lag UEBER dem
		# linken Bau-Panel und verdeckte die letzten Kategorie-Icons. Reine
		# Bildschirmgrenzen finden das nicht — also die Ueberlappung direkt messen.
		var links: Control = null
		var rechts: Control = null
		for c in m.build_root.get_children():
			if c is PanelContainer:
				var r: Rect2 = (c as Control).get_global_rect()
				if r.position.x < 40.0:
					links = c
				elif r.end.x > schirm.x - 40.0 and r.position.y < 120.0:
					rechts = c
		# Gezielt ueber den Namen — die Leiste per Baumform zu suchen ging schief,
		# sobald sich der Aufbau aenderte, und die Probe mass stumm etwas anderes.
		var leiste := m.find_child("Werkzeugleiste", true, false) as Control
		if leiste == null:
			var namen: Array = []
			for c in m.build_root.get_children():
				namen.append(String(c.name))
			print("build_root-Kinder: ", str(namen))
		if leiste == null:
			raus.append("Werkzeugleiste nicht gefunden")
		else:
			var lr: Rect2 = leiste.get_global_rect()
			print("Werkzeugleiste %.0f..%.0f (%.0f breit, %.0f hoch)"
				% [lr.position.x, lr.end.x, lr.size.x, lr.size.y])
			for paar in [[links, "Bau-Panel"], [rechts, "Statistik-Panel"]]:
				var pc: Control = paar[0]
				if pc == null:
					continue
				var pr: Rect2 = pc.get_global_rect()
				print("   %-16s %.0f..%.0f" % [paar[1], pr.position.x, pr.end.x])
				if pr.intersects(lr):
					raus.append("Werkzeugleiste ueberlappt das %s" % paar[1])
		print("")
		if raus.is_empty():
			print("URTEIL: OK — kein Bedienelement laeuft ueber den Rand")
		else:
			print("URTEIL: %d Elemente laufen ueber den Rand" % raus.size())
			for r in raus:
				print("   ", r)
		quit()
	return false
