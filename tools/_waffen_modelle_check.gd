extends SceneTree
## Prueft die Blender-Modelle der Waffen gegen den Katalog: missile_drop
## (tools/build_missile_drop_model.py) und alle aus tools/waffen_modelle_masse.json
## (tools/build_waffen_modelle.py). Je Waffe: das glb wird wirklich geladen, passt in die
## Teil-Box, ist so lang wie die Box, bleibt schlicht, und der Lack greift nur auf `body`.
## Laedt Main NICHT — fasst also keinen Spielstand an.
##   Godot --headless --path . --script res://tools/_waffen_modelle_check.gd

const MASSE := "res://tools/waffen_modelle_masse.json"
const MAX_DREIECKE := 1600          # "schlicht": die Vorlagen hatten 700 bis 22 000
const TOLERANZ := 0.011             # Box ist auf Zentimeter gerundet

var _frame := 0


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	var ids: Array[String] = ["missile_drop"]
	var f := FileAccess.open(MASSE, FileAccess.READ)
	if f != null:
		var daten: Variant = JSON.parse_string(f.get_as_text())
		if daten is Dictionary:
			for k in (daten as Dictionary).keys():
				ids.append(String(k))
	var schlecht := 0
	for id in ids:
		var fehler: Array[String] = _pruefe(id)
		if not fehler.is_empty():
			schlecht += 1
			for t in fehler:
				print("  FEHLER %s: %s" % [id, t])
	print("URTEIL: ", "OK (%d Waffen)" % ids.size() if schlecht == 0 else "FEHLER (%d von %d)" % [schlecht, ids.size()])
	quit(0 if schlecht == 0 else 1)
	return true


func _pruefe(id: String) -> Array[String]:
	var fehler: Array[String] = []
	if not PartCatalog.has(id):
		fehler.append("steht nicht im Katalog")
		return fehler
	if not PartCatalog.has_model(id):
		fehler.append("models/%s.glb fehlt oder ist nicht importiert" % id)
		return fehler
	var p: Dictionary = PartCatalog.get_part(id)
	# Der Waffentyp muss einer sein, den der Flug kennt — sonst haengt das Teil nur da.
	var typ := String(p.get("weapon", ""))
	var bekannt := false
	for gr in FlightController.WGROUPS:
		if (gr["types"] as Array).has(typ):
			bekannt = true
	if not bekannt:
		fehler.append("Waffentyp '%s' gehoert zu keiner Waffengruppe" % typ)
	var lack := Color(0.80, 0.10, 0.90)
	var vis: Node3D = PartCatalog.build_visual(p, lack)
	get_root().add_child(vis)

	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var dreiecke := 0
	var glas_z := 0.0
	var glas_n := 0
	var namen: Array[String] = []
	var body_farbe := Color(0, 0, 0, 0)
	var gelackt_sonst := false
	var stapel: Array[Node] = [vis]
	while not stapel.is_empty():
		var n: Node = stapel.pop_back()
		for k in n.get_children():
			stapel.append(k)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			dreiecke += int(float(idx.size() if idx.size() > 0 else vs.size()) / 3.0)
			var mat: Material = mi.get_active_material(si)
			var mat_name: String = mat.resource_name if mat != null else ""
			namen.append(mat_name)
			for v in vs:
				var w: Vector3 = mi.global_transform * v
				lo = lo.min(w)
				hi = hi.max(w)
				if mat_name == "glass":
					glas_z += w.z
					glas_n += 1
			if mat is StandardMaterial3D:
				var farbe: Color = (mat as StandardMaterial3D).albedo_color
				if mat_name == "body":
					body_farbe = farbe
				elif farbe.is_equal_approx(lack):
					gelackt_sonst = true

	var halb: Vector3 = PartCatalog.col_size(p) * 0.5
	var mitte: Vector3 = PartCatalog.col_offset(p)
	var ueber: float = maxf(
		maxf(hi.x - (mitte.x + halb.x), (mitte.x - halb.x) - lo.x),
		maxf(maxf(hi.y - (mitte.y + halb.y), (mitte.y - halb.y) - lo.y),
			maxf(hi.z - (mitte.z + halb.z), (mitte.z - halb.z) - lo.z)))
	var laenge: float = hi.z - lo.z
	if dreiecke <= 0 or dreiecke > MAX_DREIECKE:
		fehler.append("Dreiecke %d (erlaubt 1..%d)" % [dreiecke, MAX_DREIECKE])
	if ueber > TOLERANZ:
		fehler.append("ragt %.3f m ueber die Teil-Box" % ueber)
	if absf(laenge - PartCatalog.col_size(p).z) > TOLERANZ:
		fehler.append("Laenge %.3f statt %.3f" % [laenge, PartCatalog.col_size(p).z])
	if not namen.has("body"):
		fehler.append("Material 'body' fehlt")
	elif not body_farbe.is_equal_approx(lack):
		fehler.append("Lack greift nicht auf 'body' (%s)" % str(body_farbe))
	if gelackt_sonst:
		fehler.append("Lack faerbt auch andere Materialien")
	# Wo ein Suchkopf aus Glas sitzt, muss er vorn sein (Godot: -Z).
	if glas_n > 0 and glas_z / float(glas_n) > lo.z + 0.25 * laenge:
		fehler.append("Suchkopf sitzt nicht an der Nase (-Z)")
	print("%-13s %4d Dreiecke  %d Materialien  %.2f x %.2f x %.2f m  Ueberstand %.3f" % [
		id, dreiecke, namen.size(), hi.x - lo.x, hi.y - lo.y, laenge, maxf(ueber, 0.0)])
	vis.queue_free()
	return fehler
