## VERSCHWINDEN BAEUME IN DER NAEHE? (Nutzer: "die Baeume verschwinden die ganze Zeit, auch
## wenn sie unter mir sind, und diese Animation, wenn die Renderobjekte ausgetauscht werden,
## verwirrt".) Fliegt tief eine Gerade ueber die Hauptinsel und zaehlt JEDEN FRAME je Chunk
## die sichtbaren Pflanzen — ueber alle Knoten dieses Chunks, also auch einen groben, der
## gerade von seinem feinen Nachfolger abgeloest wird. Sinkt die Zahl eines Chunks, dessen
## Mitte naeher als NAH am Flugzeug liegt, ist das ein AUSFALL. Dazu: wie oft abgeloest
## wurde (grob -> fein) und wo Bewuchs zum ersten Mal erschien (nah = spaet nachgereicht).
##
##   HOME=<test-home> Godot [--headless --fixed-fps 60] --path . --script res://tools/_baum_ausfall_check.gd -- [v=250] [s=30] [agl=120]
## Headless laufen die Frames schneller als die Worker liefern: haerterer Fall (viele Chunks
## stehen erst grob, das Abloesen passiert naeher am Flugzeug).
extends SceneTree

const NAH := 1500.0

var m: Node
var f := 0
var v := 250.0
var sek := 30.0
var agl := 120.0
var pos := Vector3(-24000, 0, 14000)
var dir := Vector3(1.0, 0.0, -0.62).normalized()
var phase := 0
var warte := 0
var t_flug := 0.0
var vorher := {}          # Vector2i -> sichtbare Pflanzen im letzten Frame
var knoten_vorher := {}   # Vector2i -> Instanz-ID des Knotens in _chunks
var ausfaelle: Array = []
var tausch := 0
var erst_nah: Array = []  # [Abstand] — Chunk bekam erstmals Bewuchs, naeher als NAH


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("v="):
			v = float(a.substr(2))
		elif a.begins_with("s="):
			sek = float(a.substr(2))
		elif a.begins_with("agl="):
			agl = float(a.substr(4))


func _process(d: float) -> bool:
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
	_zaehlen(t)
	if t_flug >= sek:
		_bericht()
		quit()
	return false


func _setzen(ac: RigidBody3D) -> void:
	if not is_instance_valid(ac):
		return
	ac.freeze = true
	ac.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
	ac.linear_velocity = dir * v


## Sichtbare Pflanzen eines Chunk-Knotens (MultiMeshes, die selbst sichtbar sind).
func _sichtbar(n: Node3D) -> int:
	if not n.visible:
		return 0
	var z := 0
	for e in n.get_meta("flora_mmis", []):
		for rolle in ["voll", "grob"]:
			var mi: Variant = e[rolle]
			if is_instance_valid(mi) and (mi as MultiMeshInstance3D).visible:
				var mm := (mi as MultiMeshInstance3D).multimesh
				z += mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	return z


func _zaehlen(t: TerrainWorld) -> void:
	var jetzt := {}
	for c in t.get_children():
		if not (c is Node3D) or not c.has_meta("key") or c.is_queued_for_deletion():
			continue
		var k: Vector2i = c.get_meta("key")
		jetzt[k] = int(jetzt.get(k, 0)) + _sichtbar(c)
	var chunks: Dictionary = t.get("_chunks")
	var p2 := Vector2(pos.x, pos.z)
	for k in jetzt:
		var mitte := Vector2((float(k.x) + 0.5) * TerrainWorld.CHUNK, (float(k.y) + 0.5) * TerrainWorld.CHUNK)
		var ab := mitte.distance_to(p2)
		var n := int(jetzt[k])
		if vorher.has(k):
			var alt := int(vorher[k])
			if ab < NAH and n < alt:
				ausfaelle.append([t_flug, k, alt, n, ab])
			if alt == 0 and n > 0 and ab < NAH:
				erst_nah.append(ab)
		if chunks.has(k):
			var id := (chunks[k] as Object).get_instance_id()
			if knoten_vorher.has(k) and knoten_vorher[k] != id:
				tausch += 1
			knoten_vorher[k] = id
	vorher = jetzt


func _bericht() -> void:
	print("GETAUSCHT (grob -> fein): %d Chunks" % tausch)
	erst_nah.sort()
	print("ERSTER BEWUCHS naeher als %.0f m: %d Chunks%s" % [NAH, erst_nah.size(),
		(", naechster %.0f m" % erst_nah[0]) if not erst_nah.is_empty() else ""])
	for a in ausfaelle.slice(0, 12):
		print("  AUSFALL t=%.2f s Chunk %s: %d -> %d Pflanzen, %.0f m entfernt" % a)
	print("BAUM-AUSFALL %d Ausfaelle im Umkreis von %.0f m -> %s" % [ausfaelle.size(), NAH,
		"OK" if ausfaelle.is_empty() else "FEHLER"])
