## KOMMT DIE WELT BEI HOHEM TEMPO MIT? Fliegt im ECHTEN FENSTER (Echtzeit, echte GPU) eine
## Gerade mit festem Tempo quer ueber die Hauptinsel und misst alle 0,5 s, wie weit VORAUS
## die Welt fertig ist:
##   chunk   = erster fehlender Chunk auf der Flugachse (Gelaende nah, bis VIEW_DIST)
##   loch    = fehlende Chunks im Umkreis von 2 km (kahle Stellen / Schuerze im Nahbereich)
##   flora   = Chunks im Umkreis von 2,5 km, deren Baeume noch in der Warteschlange stehen
##   grob/fein = erste fehlende Schuerzenkachel auf der Achse (grob bis 18 km, fein nur Land)
##   karte   = erste fehlende Minimap-Detailkachel (Stufe 1) auf der Achse bis 8 km
## Headless taugt dafuer nicht: dort rechnen die Worker in Echtzeit, die Frames laufen
## aber so schnell die CPU kann (siehe _ruck_check) — der Rueckstand waere Unsinn.
##
##   HOME=<test-home> Godot --path . --script res://tools/_tempo_nachladen.gd -- [v=450] [s=40] [agl=350]
## Optionen (Umgebung): TEMPO_BILD=<s> Bild user://tempo_<v>.png zu dieser Flugzeit,
## TEMPO_STEHEN=1 (Vergleich im Stand), TEMPO_OHNE_MASKE=1 (Schuerze ohne Rueckfallmaske).
## Am Ende: Ergebniszeile + Profil der Streaming-Abschnitte auf dem Hauptfaden
## (TerrainWorld.profil). Die Framezeit je Probe steht hinten in jeder t-Zeile (Mittel/Max).
## Die G-Anzeige/der Tunnelblick im Bild sind ein Artefakt des Verschiebens.
extends SceneTree

var m: Node
var f := 0
var v := 450.0
var sek := 40.0
var agl := 350.0
var pos := Vector3(-24000, 0, 14000)
var dir := Vector3(1.0, 0.0, -0.62).normalized()
var phase := 0
var t_flug := 0.0
var t_probe := 0.0
var warte := 0
var zeilen: Array = []
var frames: Array = []
var _pr_alt := {}
var _ev_fern := 0
var _ev_kachel := 0
var _ev_chunks := 0
var _ev_cc := Vector2i.ZERO
var _ev_vorher: Array = []
var _ev_langsam := {}
var _ev_alle := {}
var _pr_max := {}
var _frame_i := 0


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
		# Startpunkt vorbereiten: dort alles fertig bauen lassen (wie nach dem Spawn)
		pos.y = maxf(t.height_at(pos.x, pos.z), TerrainWorld.SEA_Y) + agl
		_setzen(ac)
		warte += 1
		var fertig: bool = m.get("_fern_stufe_knoten") != null and m.call("fern_bereit", pos) \
			and (t.get("_pending") as Dictionary).is_empty() \
			and (t.get("_flora_warteschlange") as Array).is_empty()
		if fertig or warte > 9000:
			phase = 1
			t.set("profil_an", true)
			(t.get("profil") as Dictionary).clear()
			if OS.get_environment("TEMPO_OHNE_MASKE") != "":
				(m.get("_fern_mat") as ShaderMaterial).set_shader_parameter("fein_da", false)
			if OS.get_environment("TEMPO_STEHEN") != "":
				v = 0.0
			print("START v=%.0f m/s, %.0f s, %.0f m ueber Grund (Vorbereitung %d Frames)" % [v, sek, agl, warte])
		return false
	if phase == 1:
		t_flug += d
		frames.append(d)
		# Ereignisse dieses Frames, um langsame Frames zuzuordnen
		var ev := []
		var gz := (m.get("_fern_grob_mi") as Dictionary).size() + (m.get("_fern_fein_mi") as Dictionary).size()
		if gz != _ev_fern:
			ev.append("schuerze")
			_ev_fern = gz
		var wmk: WorldMap = m.get("world_map")
		var kz := (wmk.get("_kacheln") as Dictionary).size() if wmk != null else 0
		if kz != _ev_kachel:
			ev.append("kachel")
			_ev_kachel = kz
		var cz := (t.get("_chunks") as Dictionary).size()
		if cz > _ev_chunks:
			ev.append("chunk")
		_ev_chunks = cz
		var lcc: Vector2i = t.get("_last_cc")
		if lcc != _ev_cc:
			ev.append("zelle")
			_ev_cc = lcc
		if d > 0.020:
			var k := ",".join(PackedStringArray(_ev_vorher)) if not _ev_vorher.is_empty() else "-"
			_ev_langsam[k] = int(_ev_langsam.get(k, 0)) + 1
		for e in _ev_vorher:
			_ev_alle[e] = int(_ev_alle.get(e, 0)) + 1
		_ev_vorher = ev
		# Spitzen je Abschnitt: Zuwachs der Profilsummen in diesem Frame
		var pr: Dictionary = t.get("profil")
		for k in pr:
			var alt := float(_pr_alt.get(k, 0.0))
			var dz := float(pr[k]) - alt
			_pr_alt[k] = float(pr[k])
			if not String(k).ends_with("_n") and dz > float(_pr_max.get(k, 0.0)):
				_pr_max[k] = dz
		pos += dir * v * d
		# Hoehe weich ueber dem Gelaende VORAUS halten (nicht jeden Huegel nachzeichnen)
		var voraus := pos + dir * v * 2.0
		var soll := maxf(maxf(t.height_at(pos.x, pos.z), t.height_at(voraus.x, voraus.z)),
			TerrainWorld.SEA_Y) + agl
		pos.y = lerpf(pos.y, soll, 1.0 - exp(-1.5 * d))
		_setzen(ac)
		var bild_t := float(OS.get_environment("TEMPO_BILD")) if OS.get_environment("TEMPO_BILD") != "" else -1.0
		if bild_t > 0.0 and t_flug >= bild_t and t_flug - d < bild_t:
			root.get_viewport().get_texture().get_image().save_png("user://tempo_%d.png" % int(v))
			print("BILD user://tempo_%d.png bei %.1f s" % [int(v), t_flug])
		t_probe += d
		if t_probe >= 0.5:
			t_probe = 0.0
			_probe(t)
		if t_flug >= sek:
			_bericht()
			quit()
			return true
	return false


func _setzen(ac: RigidBody3D) -> void:
	if not is_instance_valid(ac):
		return
	ac.freeze = true
	ac.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
	ac.linear_velocity = dir * v


func _probe(t: TerrainWorld) -> void:
	var chunks: Dictionary = t.get("_chunks")
	var p2 := Vector2(pos.x, pos.z)
	var d2 := Vector2(dir.x, dir.z).normalized()
	# Chunk-Vorlauf auf der Achse
	var vor_chunk := TerrainWorld.VIEW_DIST
	var s := 0.0
	while s <= TerrainWorld.VIEW_DIST:
		var q := p2 + d2 * s
		if not chunks.has(Vector2i(floori(q.x / TerrainWorld.CHUNK), floori(q.y / TerrainWorld.CHUNK))):
			vor_chunk = s
			break
		s += 48.0
	# Loecher im Umkreis 2 km (Land UND Meer — auch ueber Wasser fehlt sonst der Grund)
	var loch := 0
	var r := int(ceil(2000.0 / TerrainWorld.CHUNK))
	var cc := Vector2i(floori(p2.x / TerrainWorld.CHUNK), floori(p2.y / TerrainWorld.CHUNK))
	for cy in range(cc.y - r, cc.y + r + 1):
		for cx in range(cc.x - r, cc.x + r + 1):
			var k := Vector2i(cx, cy)
			var mitte := (Vector2(k) + Vector2(0.5, 0.5)) * TerrainWorld.CHUNK
			if mitte.distance_to(p2) < 2000.0 and not chunks.has(k):
				loch += 1
	# Flora in Arbeit (einzelne Chunks) im Umkreis 2,5 km
	var flora_n := {}
	for e in (t.get("_flora_warteschlange") as Array):
		var n: Variant = e["node"]
		if is_instance_valid(n) and Vector2((n as Node3D).global_position.x, (n as Node3D).global_position.z).distance_to(p2) < 2500.0:
			flora_n[n] = true
	# Schuerze
	var grob_da: Dictionary = m.get("_fern_grob_da")
	var grob_mi: Dictionary = m.get("_fern_grob_mi")
	var fein_mi: Dictionary = m.get("_fern_fein_mi")
	var fk: float = m.get_script().get_script_constant_map()["FERN_KACHEL"]
	var vor_grob := 18000.0
	s = 0.0
	while s <= 18000.0:
		var q := p2 + d2 * s
		if not grob_da.has(Vector2i(floori(q.x / fk), floori(q.y / fk))):
			vor_grob = s
			break
		s += 250.0
	var vor_fein := 11500.0
	s = 0.0
	while s <= 11500.0:
		var q := p2 + d2 * s
		var k := Vector2i(floori(q.x / fk), floori(q.y / fk))
		if grob_mi.has(k) and not fein_mi.has(k):
			vor_fein = s
			break
		s += 250.0
	# Minimap-Kacheln (Stufe 1)
	var wm: WorldMap = m.get("world_map")
	var vor_karte := 8000.0
	if wm != null:
		var kacheln: Dictionary = wm.get("_kacheln")
		var km := WorldMap.kachel_m(1)
		var n := WorldMap.kachel_n(1)
		s = 0.0
		while s <= 8000.0:
			var q := p2 + d2 * s
			var key := Vector3i(clampi(floori((q.x + WorldMap.WORLD_R) / km), 0, n - 1),
				clampi(floori((q.y + WorldMap.WORLD_R) / km), 0, n - 1), 1)
			if not kacheln.has(key):
				vor_karte = s
				break
			s += 250.0
	var wn: int = int(t.get("mess_worker_n")) if t.get("mess_worker_n") != null else 0
	var wus: int = int(t.get("mess_worker_us")) if t.get("mess_worker_us") != null else 0
	print("      worker: %d gebaut, %.1f ms je Chunk, %s verworfen" % [wn,
		float(wus) / 1000.0 / maxf(wn, 1), str(t.get("mess_verworfen"))])
	var jobs := (t.get("_jobs") as Array).size()
	var done := (t.get("_done") as Array).size()
	zeilen.append([t_flug, vor_chunk, loch, flora_n.size(), vor_grob, vor_fein, vor_karte, jobs, done])
	var fm := 0.0
	var fx := 0.0
	for x in frames.slice(_frame_i):
		fm += x
		fx = maxf(fx, x)
	fm /= maxf(frames.size() - _frame_i, 1)
	_frame_i = frames.size()
	print("t %5.1f  chunk %5.0f m  loch %3d  flora %3d  grob %6.0f  fein %6.0f  karte %5.0f  jobs %3d done %2d  frame %.1f/%.1f ms" % [
		t_flug, vor_chunk, loch, flora_n.size(), vor_grob, vor_fein, vor_karte, jobs, done, fm * 1000.0, fx * 1000.0])


func _bericht() -> void:
	var ueber20 := 0
	var ueber33 := 0
	for x in frames:
		if x > 0.020:
			ueber20 += 1
		if x > 0.0333:
			ueber33 += 1
	print("SPITZEN Frames ueber 20 ms: %d, ueber 33 ms: %d von %d" % [ueber20, ueber33, frames.size()])
	for k in _ev_langsam:
		print("LANGSAM nach [%s]: %d Frames" % [k, _ev_langsam[k]])
	for k in _ev_alle:
		print("EREIGNIS %s: %d mal" % [k, _ev_alle[k]])
	for k in _pr_max:
		if float(_pr_max[k]) > 1000.0:
			print("SPITZE %-16s max %.2f ms in einem Frame" % [k, float(_pr_max[k]) / 1000.0])
	var pr: Dictionary = m.terrain.get("profil")
	var zeilen_p: Array = []
	for k in pr:
		zeilen_p.append([float(pr[k]), k])
	zeilen_p.sort()
	zeilen_p.reverse()
	for z in zeilen_p:
		if String(z[1]).ends_with("_n"):
			print("PROFIL %-16s %8.0f" % [z[1], z[0]])
		else:
			print("PROFIL %-16s %7.2f ms je Frame" % [z[1], z[0] / 1000.0 / maxf(frames.size(), 1)])
	var mins := [INF, 0, 0, INF, INF, INF]
	var loch_proben := 0
	for z in zeilen:
		if float(z[0]) < 3.0:
			continue     # Anlauf: die Welt um den Startpunkt ist vorbereitet
		mins[0] = minf(mins[0], z[1])
		mins[1] = maxi(mins[1], z[2])
		mins[2] = maxi(mins[2], z[3])
		mins[3] = minf(mins[3], z[4])
		mins[4] = minf(mins[4], z[5])
		mins[5] = minf(mins[5], z[6])
		if int(z[2]) > 0:
			loch_proben += 1
	frames.sort()
	var p99: float = frames[int(frames.size() * 0.99)] if not frames.is_empty() else 0.0
	var mittel := 0.0
	for x in frames:
		mittel += x
	mittel /= maxf(frames.size(), 1)
	print("ERGEBNIS v=%.0f: Chunk-Vorlauf min %.0f m | Loecher <2 km max %d (in %d von %d Proben) | Flora offen max %d | Schuerze grob min %.0f m, fein min %.0f m | Karte min %.0f m | Frame %.1f ms Mittel, p99 %.1f ms" % [
		v, mins[0], mins[1], loch_proben, zeilen.size(), mins[2], mins[3], mins[4], mins[5], mittel * 1000.0, p99 * 1000.0])
