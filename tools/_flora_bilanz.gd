## WORAUS BESTEHEN DIE PRIMITIVE IM NAHFELD? Die Bildzeitmessung (tools/_bildzeit.gd)
## nennt beim Tiefflug ueber Wald 32,4 Millionen Primitive bei 47 Bildern je Sekunde. Diese
## Probe schluesselt auf, WO sie herkommen: je Detailstufe die Zahl der Instanzen, die
## Dreieckszahl des benutzten Meshes und das Produkt aus beidem.
##
## Ohne diese Aufschluesselung optimiert man ins Blaue — die Dichte zu senken ist etwas
## voellig anderes als ein zu feines Baummesh zu ersetzen, und beide sehen in der
## Gesamtzahl gleich aus.
##
## Godot --path . --script res://tools/_flora_bilanz.gd
extends SceneTree
# WARUM EINE EIGENE KOROUTINE UND NICHT DIREKT IN _process: sobald in _process ein await
# steht, gibt die Funktion sofort zurueck und ihr Rueckgabewert ist kein bool mehr — der
# Baum bekommt nie sein "fertig" und die Ausgabe erschien gar nicht. Dieselbe Bauart wie
# tools/_terrain_render.gd: _process stoesst einmal an und liest ein Flag.
var _los := false
var _fertig := false


func _dreiecke(m: Mesh) -> int:
	if m == null:
		return 0
	# ARRAY_INDEX ist NIL, wenn das Mesh unindiziert ist — und die Flatshading-Meshes hier
	# sind es. Direkt in ein PackedInt32Array zu schreiben knallt dann.
	var n := 0
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			n += (idx as PackedInt32Array).size() / 3
		else:
			var vs: Variant = arr[Mesh.ARRAY_VERTEX]
			if vs != null:
				n += (vs as PackedVector3Array).size() / 3
	return n


func _process(_d: float) -> bool:
	if not _los:
		_los = true
		_lauf()
	return _fertig


func _lauf() -> void:
	await process_frame
	await process_frame
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var mitte := Vector3(300, 120, 900)
	tw.update_center(mitte)
	tw.build_now_around(mitte, TerrainWorld.VIEW_DIST, false)
	await process_frame
	await process_frame

	var nach_mesh: Dictionary = {}     # mesh-Name -> [Instanzen, Dreiecke je Instanz, Knoten]
	var gelaende := 0
	for chunk in tw.get_children():
		if not (chunk is Node3D):
			continue
		for n in (chunk as Node3D).get_children():
			if n is MultiMeshInstance3D:
				var mmi := n as MultiMeshInstance3D
				if mmi.multimesh == null:
					continue
				var d := _dreiecke(mmi.multimesh.mesh)
				var c := mmi.multimesh.visible_instance_count
				if c < 0:
					c = mmi.multimesh.instance_count
				var k := "%s (%s)" % [String(mmi.name), "sichtbar" if mmi.visible else "aus"]
				if not nach_mesh.has(k):
					nach_mesh[k] = [0, d, 0]
				nach_mesh[k][0] += c
				nach_mesh[k][2] += 1
			elif n is MeshInstance3D:
				gelaende += _dreiecke((n as MeshInstance3D).mesh)

	print("Im Umkreis von %.0f m um den Spieler:" % TerrainWorld.VIEW_DIST)
	print("%-34s %10s %10s %14s" % ["Lage", "Instanzen", "Dreiecke", "Primitive"])
	var summe := 0
	var keys: Array = nach_mesh.keys()
	keys.sort()
	for k in keys:
		var e: Array = nach_mesh[k]
		var p: int = e[0] * e[1]
		summe += p
		print("%-34s %10d %10d %14d" % [k, e[0], e[1], p])
	print("%-34s %10s %10s %14d" % ["Gelaende (Chunk-Netze)", "-", "-", gelaende])
	print("%-34s %10s %10s %14d" % ["SUMME Flora", "", "", summe])
	_fertig = true
	quit()
