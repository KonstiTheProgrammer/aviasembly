## MISST, WAS WIRKLICH IN DER SZENE HAENGT — nicht was _make_chunk_data zurueckgibt.
## Geht ueber den GESTREAMTEN Pfad (update_center -> Worker -> _process -> _attach_chunk),
## genau den, der vorher Flora verschluckt hat. Zaehlt MultiMeshInstance3D-Knoten und die
## Summe ihrer instance_count je Chunk, plus Dichte pro km^2.
extends SceneTree

var _tw: TerrainWorld
var _frames := 0
var _started := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_tw = TerrainWorld.new()
		root.add_child(_tw)
		_tw.setup(12345, [{"pos": Vector3.ZERO, "r_flat": 240.0, "r_blend": 620.0}], [], [], [])
		_tw.update_center(Vector3(2000, 200, 2000))
		return false
	_frames += 1
	# genug Frames, damit der Worker alle Chunks liefert und _process sie einhaengt
	if _frames < 900:
		return false
	var eye := Vector2(2000, 2000)
	var chunks := 0
	var mmi_nodes := 0
	var inst := 0
	var sicht_knoten := 0
	var sicht_inst := 0
	for c in _tw.get_children():
		if not (c is Node3D) or c is MeshInstance3D:
			continue
		var has_terrain := false
		var nah := false
		for g in c.get_children():
			if g is MultiMeshInstance3D:
				var mmi := g as MultiMeshInstance3D
				mmi_nodes += 1
				var n: int = mmi.multimesh.instance_count
				inst += n
				var ctr := mmi.multimesh.get_aabb().get_center()
				if Vector2(ctr.x, ctr.z).distance_to(eye) <= TerrainWorld.FLORA_DIST:
					sicht_knoten += 1
					sicht_inst += n
					nah = true
			elif g is MeshInstance3D:
				has_terrain = true
		if has_terrain:
			chunks += 1
		if nah:
			pass
	var flaeche := float(chunks) * TerrainWorld.CHUNK * TerrainWorld.CHUNK / 1_000_000.0
	print("LIVE-SZENE  Chunks=%d  MultiMesh-Knoten=%d  Instanzen=%d" % [chunks, mmi_nodes, inst])
	print("  je Chunk: %.1f Instanzen   Dichte: %.0f / km^2  (Flaeche %.1f km^2)"
		% [float(inst) / maxf(chunks, 1), float(inst) / maxf(flaeche, 0.001), flaeche])
	print("  innerhalb FLORA_DIST=%.0f: %d Draw-Calls, %d Instanzen"
		% [TerrainWorld.FLORA_DIST, sicht_knoten, sicht_inst])
	# Kosten eines Chunks im Worker (Mesh + Kollision + Bewuchs)
	# BEWACHSENE Chunks messen (nicht draussen im Meer, sonst misst man nur das Mesh)
	var t0 := Time.get_ticks_usec()
	var geplanzt := 0
	for n in 20:
		var d: Dictionary = _tw._make_chunk_data(Vector2i(3 + n % 5, 3 + n / 5))
		for art in d["flora"].keys():
			geplanzt += d["flora"][art].size()
	print("  _make_chunk_data: %.2f ms je Chunk (20 bewachsene, im Schnitt %d Pflanzen)"
		% [(Time.get_ticks_usec() - t0) / 20000.0, geplanzt / 20])
	quit()
	return true
