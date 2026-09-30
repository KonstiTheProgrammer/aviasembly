## Dreiecke und Eckpunkte je Baumart NACH der Aufbereitung im Spiel (_weiche_krone
## verschweisst das Laub) — die GPU ist bei der Flora eckpunktgebunden, also zaehlt das.
## Vergleicht zwei glb-Dateien (alt/neu), ohne Import:
##   Godot --headless --path . --script res://tools/_flora_zahlen.gd -- <alt.glb> <neu.glb>
extends SceneTree


func _zahlen(pfad: String) -> Dictionary:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(pfad, st) != OK:
		push_error("kann %s nicht lesen" % pfad)
		return {}
	var sc := doc.generate_scene(st)
	var d := {}
	for n in sc.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var m: Mesh = mi.mesh
		if not mi.name in TerrainWorld.HART_BLEIBEN and mi.name != "Fels":
			m = TerrainWorld._weiche_krone(m)
		var tris := 0
		var verts := 0
		for si in m.get_surface_count():
			var arr := m.surface_get_arrays(si)
			var ix: Variant = arr[Mesh.ARRAY_INDEX]
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			verts += vs.size()
			@warning_ignore("integer_division")
			tris += ((ix as PackedInt32Array).size() if ix != null else vs.size()) / 3
		d[String(mi.name)] = Vector2i(tris, verts)
	sc.free()
	return d


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var alt := _zahlen(args[0])
	var neu := _zahlen(args[1])
	var sa := Vector2i.ZERO
	var sn := Vector2i.ZERO
	print("%-12s %14s %14s" % ["Art", "alt Tri/Eck", "neu Tri/Eck"])
	for art in TerrainWorld.ARTEN + ["Fels"]:
		var a: Vector2i = alt.get(art, Vector2i.ZERO)
		var b: Vector2i = neu.get(art, Vector2i.ZERO)
		sa += a
		sn += b
		print("%-12s %6d / %5d %6d / %5d" % [art, a.x, a.y, b.x, b.y])
	print("%-12s %6d / %5d %6d / %5d" % ["SUMME", sa.x, sa.y, sn.x, sn.y])
	quit()
