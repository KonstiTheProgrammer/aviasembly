## SIND NACH DEM NEULADEN NOCH BAEUME DA? (Nutzer: „wenn man neu laedt, sind da keine Baeume
## mehr“.) Spielt die Wege nach, auf denen die Welt um das Flugzeug neu entsteht, und zaehlt jeweils
## die SICHTBAREN Pflanzen im Umkreis von 1,5 km, nachdem das Nachladen zur Ruhe gekommen ist:
##   start      Flugstart am Platz
##   enter      Zuruecksetzen (Enter) am Platz
##   weit       Flug 8 km weg (Sprung), dort
##   enter_weit Zuruecksetzen von dort zurueck an den Platz
##   hangar     Tab in den Hangar und zurueck
##   vorlage    Vorlage laden, dann fliegen
## Ein Fall mit weniger als der Haelfte der Startzahl (am selben Ort) ist ein FEHLER.
##   HOME=<test-home> Godot --headless --fixed-fps 60 --path . --script res://tools/_neuladen_check.gd
## Im Fenster (ohne --headless) zusaetzlich je Schritt ein Bild user://neuladen_<n>_<fall>.png.
extends SceneTree

var m: Node
var f := 0
var schritt := 0
var warte := 0
var ergebnisse: Array = []
var start_zahl := -1
var weit_pos := Vector3(8000, 0, 3000)
var zurueck := 0      # Frames im Hangar, dann zurueck in den Flug


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 20:
		m._set_mode(1)
		return false
	if f < 25:
		return false
	var t: TerrainWorld = m.terrain
	if zurueck > 0:
		zurueck -= 1
		if zurueck == 0:
			m._set_mode(1)
		return false
	var ac = m.flight_ctrl.aircraft
	if is_instance_valid(ac):
		ac.freeze = true
	warte += 1
	if not _ruhig(t) or warte < 90:
		if warte < 12000:
			return false
	var pos: Vector3 = ac.global_position if is_instance_valid(ac) else Vector3.ZERO
	var n := _zaehlen(t, pos)
	var name: String = ["start", "enter", "weit", "enter_weit", "hangar", "vorlage"][schritt]
	ergebnisse.append([name, n, pos, warte])
	print("%-11s %6d Pflanzen sichtbar im Umkreis 1,5 km  (%.0f, %.0f), %d Frames gewartet%s"
		% [name, n, pos.x, pos.z, warte, "" if _ruhig(t) else "  NICHT RUHIG"])
	_bild("neuladen_%d_%s" % [schritt, name])
	if schritt == 0:
		start_zahl = n
	warte = 0
	schritt += 1
	match schritt:
		1:
			_taste(KEY_ENTER)
		2:
			var p := weit_pos
			p.y = maxf(t.height_at(p.x, p.z), TerrainWorld.SEA_Y) + 150.0
			ac.global_transform = Transform3D(Basis(), p)
		3:
			_taste(KEY_ENTER)
		4:
			m._set_mode(0)
			zurueck = 3
		5:
			m._set_mode(0)
			m._do_load_preset("spitfire", "Supermarine Spitfire")
			zurueck = 3
		_:
			_bericht()
			quit()
			return true
	return false


## Im Fenster ein Bild nach user:// (headless gibt es keins).
func _bild(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw(false)
	get_root().get_viewport().get_texture().get_image().save_png("user://%s.png" % name)


func _ruhig(t: TerrainWorld) -> bool:
	return (t.get("_pending") as Dictionary).is_empty() \
		and (t.get("_flora_warteschlange") as Array).is_empty()


func _taste(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var los := InputEventKey.new()
	los.keycode = code
	los.physical_keycode = code
	los.pressed = false
	Input.parse_input_event(los)


## Sichtbare Pflanzen (MultiMeshes, die selbst UND deren Eltern sichtbar sind).
func _zaehlen(t: TerrainWorld, pos: Vector3) -> int:
	var z := 0
	var p2 := Vector2(pos.x, pos.z)
	for c in t.get_children():
		if not (c is Node3D) or not c.has_meta("key") or c.is_queued_for_deletion():
			continue
		var k: Vector2i = c.get_meta("key")
		var mitte := Vector2((float(k.x) + 0.5) * TerrainWorld.CHUNK, (float(k.y) + 0.5) * TerrainWorld.CHUNK)
		if mitte.distance_to(p2) > 1500.0:
			continue
		if not (c as Node3D).is_visible_in_tree():
			continue
		for e in c.get_meta("flora_mmis", []):
			for rolle in ["voll", "grob", "mittel"]:
				var mi: Variant = e.get(rolle)
				if mi == null or not is_instance_valid(mi):
					continue
				var mmi := mi as MultiMeshInstance3D
				if not mmi.is_visible_in_tree():
					continue
				var mm := mmi.multimesh
				z += mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	return z


func _bericht() -> void:
	var fehler := 0
	for e in ergebnisse:
		# Am Platz (alles ausser "weit") mit der Startzahl vergleichen
		if e[0] != "weit" and start_zahl > 0 and int(e[1]) < start_zahl / 2:
			fehler += 1
			print("  FEHLER: %s nur %d statt ~%d" % [e[0], e[1], start_zahl])
	print("NEULADEN %s" % ("OK" if fehler == 0 else "FEHLER (%d)" % fehler))
