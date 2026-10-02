## WIE SCHNELL STEHEN DIE BAEUME NACH DEM ZURUECKSETZEN WIEDER? Echtzeit (60 Bilder/s, auch
## headless). Startet am Platz, wartet, bis alles steht, springt 8 km weg (wartet wieder), drueckt
## Enter (zurueck an den Platz) und schreibt jede Sekunde: sichtbare Pflanzen im Umkreis 1,5 km,
## Chunks dort mit offenem Bewuchs, Auftraege und Warteschlange.
##   HOME=<test-home> Godot --headless --path . --script res://tools/_neuladen_zeit.gd -- [x=8000] [z=3000]
extends SceneTree

var m: Node
var f := 0
var phase := 0
var warte := 0
var t_alt := 0
var t_nach := 0.0
var t_takt := 0.0
var start_zahl := 0
var weit := Vector3(8000, 0, 3000)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("x="):
			weit.x = float(a.substr(2))
		elif a.begins_with("z="):
			weit.z = float(a.substr(2))


func _process(_d: float) -> bool:
	var jetzt := Time.get_ticks_usec()
	if t_alt > 0:
		var rest := 16667 - (jetzt - t_alt)
		if rest > 0:
			OS.delay_usec(rest)
	t_alt = Time.get_ticks_usec()
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
	var ac = m.flight_ctrl.aircraft
	if is_instance_valid(ac):
		ac.freeze = true
	match phase:
		0, 1:
			warte += 1
			if (_ruhig(t) and warte > 60) or warte > 6000:
				if phase == 0:
					start_zahl = _zaehlen(t, ac.global_position)[0]
					print("START am Platz: %d Pflanzen" % start_zahl)
					var p := weit
					p.y = maxf(t.height_at(p.x, p.z), TerrainWorld.SEA_Y) + 150.0
					ac.global_transform = Transform3D(Basis(), p)
				else:
					print("WEIT (%.0f, %.0f): %d Pflanzen, jetzt Enter" % [weit.x, weit.z,
						_zaehlen(t, ac.global_position)[0]])
					_taste(KEY_ENTER)
				phase += 1
				warte = 0
		2:
			t_nach += 1.0 / 60.0
			t_takt += 1.0 / 60.0
			if t_takt >= 1.0:
				t_takt = 0.0
				var z := _zaehlen(t, ac.global_position)
				print("  +%4.1f s  %6d Pflanzen (%3.0f %%), %2d Chunks offen, Auftraege %3d, Warteschlange %3d"
					% [t_nach, z[0], 100.0 * z[0] / maxf(start_zahl, 1), z[1],
					(t.get("_pending") as Dictionary).size(), (t.get("_flora_warteschlange") as Array).size()])
			if t_nach > 40.0:
				quit()
				return true
	return false


func _ruhig(t: TerrainWorld) -> bool:
	return (t.get("_pending") as Dictionary).is_empty() \
		and (t.get("_flora_warteschlange") as Array).is_empty()


func _taste(code: Key) -> void:
	for gedrueckt in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = gedrueckt
		Input.parse_input_event(ev)


## [sichtbare Pflanzen, Chunks mit offenem Bewuchs] im Umkreis 1,5 km
func _zaehlen(t: TerrainWorld, pos: Vector3) -> Array:
	var z := 0
	var offen := 0
	var p2 := Vector2(pos.x, pos.z)
	for c in t.get_children():
		if not (c is Node3D) or not c.has_meta("key") or c.is_queued_for_deletion():
			continue
		var k: Vector2i = c.get_meta("key")
		var mitte := Vector2((float(k.x) + 0.5) * TerrainWorld.CHUNK, (float(k.y) + 0.5) * TerrainWorld.CHUNK)
		if mitte.distance_to(p2) > 1500.0:
			continue
		if c.has_meta("bewuchs_offen"):
			offen += 1
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
	return [z, offen]
