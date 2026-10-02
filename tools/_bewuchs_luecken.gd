## STEHEN BEIM NACHLADEN GEBIETE OHNE BAEUME? Fliegt in ECHTZEIT (60 Bilder/s, auch headless:
## jedes Bild wartet auf seine 16,7 ms — sonst liefen die Bilder den Chunk-Faeden davon) eine
## Gerade ueber die Hauptinsel und zaehlt alle 0,5 s die Chunks im Umkreis R, deren Bewuchs noch
## FEHLT (Meta "bewuchs_offen": grob eingehaengt, Bewuchsauftrag nicht geliefert). Am Ende: wie
## viele Proben solche Luecken hatten, die naechste Luecke und wie lange ein Chunk hoechstens offen
## stand.
##   HOME=<test-home> Godot --headless --path . --script res://tools/_bewuchs_luecken.gd -- [v=200] [s=40] [agl=150]
extends SceneTree

const R := 1500.0

var m: Node
var f := 0
var v := 200.0
var sek := 40.0
var agl := 150.0
var pos := Vector3(-24000, 0, 14000)
var dir := Vector3(1.0, 0.0, -0.62).normalized()
var phase := 0
var warte := 0
var t_flug := 0.0
var t_probe := 0.0
var proben := 0
var proben_luecke := 0
var naechste := INF
var offen_seit := {}      # Vector2i -> Flugzeit, seit der der Chunk nah und offen ist
var laengste := 0.0
var t_alt := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("v="):
			v = float(a.substr(2))
		elif a.begins_with("s="):
			sek = float(a.substr(2))
		elif a.begins_with("agl="):
			agl = float(a.substr(4))


func _process(_d: float) -> bool:
	# Echtzeit: jedes Bild dauert mindestens 1/60 s
	var jetzt := Time.get_ticks_usec()
	if t_alt > 0:
		var rest := 16667 - (jetzt - t_alt)
		if rest > 0:
			OS.delay_usec(rest)
	t_alt = Time.get_ticks_usec()
	var d := 1.0 / 60.0
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
	var ac: RigidBody3D = m.flight_ctrl.aircraft
	var t: TerrainWorld = m.terrain
	if phase == 0:
		pos.y = maxf(t.height_at(pos.x, pos.z), TerrainWorld.SEA_Y) + agl
		_setzen(ac)
		warte += 1
		if ((t.get("_pending") as Dictionary).is_empty()
				and (t.get("_flora_warteschlange") as Array).is_empty() and warte > 30) or warte > 9000:
			phase = 1
			print("START v=%.0f m/s, %.0f s, %.0f m ueber Grund" % [v, sek, agl])
		return false
	t_flug += d
	pos += dir * v * d
	var voraus := pos + dir * v * 2.0
	var soll := maxf(maxf(t.height_at(pos.x, pos.z), t.height_at(voraus.x, voraus.z)),
		TerrainWorld.SEA_Y) + agl
	pos.y = lerpf(pos.y, soll, 1.0 - exp(-1.5 * d))
	_setzen(ac)
	t_probe += d
	if t_probe >= 0.5:
		t_probe = 0.0
		_probe(t)
	if t_flug >= sek:
		print("PROBEN %d, davon mit offenem Bewuchs naeher als %.0f m: %d" % [proben, R, proben_luecke])
		print("NAECHSTE LUECKE %.0f m, LAENGSTE offen in der Naehe %.1f s" % [naechste, laengste])
		print("BEWUCHS-LUECKEN %s" % ("OK" if proben_luecke * 10 <= proben else "VIELE"))
		quit()
	return false


func _setzen(ac: RigidBody3D) -> void:
	if not is_instance_valid(ac):
		return
	ac.freeze = true
	ac.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
	ac.linear_velocity = dir * v


func _probe(t: TerrainWorld) -> void:
	proben += 1
	var p2 := Vector2(pos.x, pos.z)
	var luecke := false
	var noch := {}
	for c in t.get_children():
		if not (c is Node3D) or not c.has_meta("key") or c.is_queued_for_deletion():
			continue
		if not c.has_meta("bewuchs_offen"):
			continue
		var k: Vector2i = c.get_meta("key")
		var mitte := Vector2((float(k.x) + 0.5) * TerrainWorld.CHUNK, (float(k.y) + 0.5) * TerrainWorld.CHUNK)
		var ab := mitte.distance_to(p2)
		if ab > R:
			continue
		luecke = true
		naechste = minf(naechste, ab)
		noch[k] = true
		if not offen_seit.has(k):
			offen_seit[k] = t_flug
		laengste = maxf(laengste, t_flug - float(offen_seit[k]))
	for k in offen_seit.keys():
		if not noch.has(k):
			offen_seit.erase(k)
	if luecke:
		proben_luecke += 1
