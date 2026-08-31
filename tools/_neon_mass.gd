## WAS STEHT EIGENTLICH IN NEONBUCHT?
##
## Der Anlass ist ein Fehler: ich hatte das Viertel einmal mit "91 Tuerme" beschrieben,
## ohne je gezaehlt zu haben — die Zahl war geraten und falsch. Eine gebaute Welt laesst
## sich zaehlen, also wird sie gezaehlt.
##
## Gemeldet werden Netze und Dreiecke je Flaeche sowie die Kollisionskoerper nach Art.
## Die Zahl der TUERME steht nirgends im Baum (alle liegen in einem Netz), sie wird
## deshalb nicht behauptet; stattdessen zaehlt der Bericht die Zylinderkoerper, denn die
## kommen ausschliesslich von Rundtuermen und sind damit eine ehrliche Teilangabe.
##
## Godot --headless --path . --script res://tools/_neon_mass.gd
extends SceneTree

const MITTE := Vector3(2600.0, 0.0, -3800.0)

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if not has_meta("main"):
		var m: Node = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		set_meta("main", m)
		return false
	if f < 20:
		return false
	var main: Node = get_meta("main")
	# REKURSIV SUCHEN, nicht ueber einen geratenen Pfad. Der erste Anlauf nahm
	# "FlyWorld/Skyline" an; stimmt der Pfad nicht, ist sky null, der Ausweichzweig
	# greift ins Leere und das Werkzeug haengt still bis zum Zeitlimit — zehn Minuten
	# fuer nichts. Ein Name laesst sich suchen, ein Pfad muss man wissen.
	var sky: Node = main.find_child("Skyline", true, false)
	if sky == null:
		print("Skyline nicht gefunden")
		quit()
		return true

	print("Netz                  Flaechen   Dreiecke")
	print("--------------------- -------- ----------")
	var summe := 0
	for k in sky.get_children():
		if k is MeshInstance3D:
			# NICHT AUF ArrayMesh TYPISIEREN. Unter Skyline haengt auch eine SphereMesh
			# (das Leuchtfeuer am Sendemast), und eine fehlgeschlagene typisierte
			# Zuweisung bricht _process ab — quit() wird dann nie erreicht und das
			# Werkzeug dreht sich bis zum Zeitlimit. Genau so sind hier zwei Laeufe von
			# je zehn Minuten verlorengegangen.
			var me: Mesh = (k as MeshInstance3D).mesh
			if me == null:
				continue
			var d := 0
			for si in me.get_surface_count():
				var arr: Array = me.surface_get_arrays(si)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] \
					if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				if idx.size() > 0:
					d += idx.size() / 3
				else:
					d += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			summe += d
			print("%-21s %8d %10d" % [k.name, me.get_surface_count(), d])
	print("%-21s %8s %10d" % ["SUMME", "", summe])

	var kasten := 0
	var zylinder := 0
	for k in sky.get_children():
		if k is StaticBody3D:
			for c in k.get_children():
				if c is CollisionShape3D:
					if (c as CollisionShape3D).shape is BoxShape3D:
						kasten += 1
					elif (c as CollisionShape3D).shape is CylinderShape3D:
						zylinder += 1
	print("\nKollision: %d Quader, %d Zylinder (nur Rundtuerme) = %d Koerper"
		% [kasten, zylinder, kasten + zylinder])
	quit()
	return true
