## LECKEN KNOTEN ODER OBJEKTE UEBER VIELE FLUEGE?
##
## Ein Zyklus = in den Flug, 3 s mit allen Waffen feuern, Bombe, Fackeln/Dueppel, Reset,
## zurueck in den Hangar. Nach dem Aufwaermen muss die Knoten- und Objektzahl im Hangar
## wieder auf demselben Stand landen — steigt sie je Zyklus, sammelt sich etwas an
## (Truemmer, Effekte, Geschosse, Timer-Leichen), das ein langer Spielabend zu spueren
## bekommt.
##
##   HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/_leck_check.gd
extends SceneTree

const ZYKLEN := 8
var m: Node = null
var f := 0
var t := 0
var zyklus := 0
var phase := 0
var knoten: Array = []
var objekte: Array = []
var zensus: Array = []
var ohne_gelaende: Array = []


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 20:
		m.call("_load_design_from", "res://designs/sturmjet.json")
		return false
	if f < 30:
		return false
	var fc = m.get("flight_ctrl")
	t += 1
	match phase:
		0:
			m.call("_set_mode", 1)
			phase = 1
			t = 0
		1:
			var ac = fc.get("aircraft")
			if t == 2:
				ac.global_transform = Transform3D(Basis(), Vector3(3500.0, 500.0, 3500.0))
				ac.linear_velocity = Vector3(0, 0, -150.0)
				fc.set("throttle", 1.0)
				fc.call("_reset_mouse_state")
			if t > 2 and t < 180 and t % 6 == 0:
				for g in fc.get("weapon_groups"):
					fc.call("_fire_primary", g["types"], false)
				fc.call("_drop_bomb", true)
				fc.call("_werfen", "flare")
				fc.call("_werfen", "chaff")
			if t == 180:
				fc.call("_reset_to_runway")
			if t == 200:
				m.call("_set_mode", 0)
				phase = 2
				t = 0
		2:
			# Effekte laufen mit Timern bis ~10 s aus — erst dann zaehlen.
			if t == 60 * 11:
				knoten.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
				objekte.append(int(Performance.get_monitor(Performance.OBJECT_COUNT)))
				var z := {}
				_zaehlen(root, z, 0)
				zensus.append(z)
				var im_baum := 0
				for v in z.values():
					im_baum += int(v)
				var terr: Node = m.get("terrain")
				var terr_knoten := _anzahl(terr)
				ohne_gelaende.append(knoten[-1] - terr_knoten)
				print("Zyklus %d: Knoten %d (Gelaende %d in %d Chunks, Rest %d, Waisen %d)  Objekte %d" % [
					zyklus + 1, knoten[-1], terr_knoten, (terr.get("_chunks") as Dictionary).size(),
					ohne_gelaende[-1],
					int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), objekte[-1]])

				zyklus += 1
				if zyklus >= ZYKLEN:
					_urteil()
					quit()
					return false
				phase = 0
				t = 0
	return false


func _anzahl(n: Node) -> int:
	var k := 0
	for c in n.get_children(true):
		k += 1 + _anzahl(c)
	return k


## Knoten je (Elternname / Klasse) — daran sieht man, WO sich etwas ansammelt.
func _zaehlen(n: Node, z: Dictionary, tiefe: int) -> void:
	for c in n.get_children(true):
		var k := "%s/%s" % [String(n.name).substr(0, 24), c.get_class()]
		z[k] = int(z.get(k, 0)) + 1
		_zaehlen(c, z, tiefe + 1)


func _urteil() -> void:
	var a: Dictionary = zensus[1]
	var b: Dictionary = zensus[-1]
	var zeilen: Array = []
	for k in b.keys():
		var d := int(b[k]) - int(a.get(k, 0))
		if d != 0:
			zeilen.append([d, k])
	for k in a.keys():
		if not b.has(k):
			zeilen.append([-int(a[k]), k])
	zeilen.sort_custom(func(x, y): return absi(x[0]) > absi(y[0]))
	print("Veraenderung Zyklus 2 -> %d (Eltern/Klasse):" % zensus.size())
	for i in mini(15, zeilen.size()):
		print("   %+5d  %s" % [zeilen[i][0], zeilen[i][1]])
	# Zyklus 1 ist Aufwaermen (Caches, erste Effekt-Ressourcen). Danach zaehlt die Steigung.
	# GELAENDE HERAUSGERECHNET: die Chunkzahl schwankt mit dem Streaming (wo der Flieger
	# zuletzt war, was der Worker gerade liefert) und ist kein Leck. Gezaehlt wird der Rest.
	var dk: float = float(ohne_gelaende[-1] - ohne_gelaende[1]) / float(ohne_gelaende.size() - 2)
	var do: float = float(objekte[-1] - objekte[1]) / float(objekte.size() - 2)
	print("Zuwachs je Zyklus (ab Zyklus 2, ohne Gelaende): Knoten %+.1f" % dk)
	# Die OBJEKTE werden nur berichtet, nicht bewertet: jeder Chunk bringt rund 38 Objekte
	# mit (Mesh, Kollisionsform, Baum-MultiMeshes, ...), und die Chunkzahl im Hangar haengt
	# davon ab, wo der Flieger beim Wechsel zuletzt war. Gemessen: +305 Objekte bei +8
	# Chunks. Ein echtes Leck zeigte sich in den Knoten ausserhalb des Gelaendes.
	print("Objekte je Zyklus %+.1f (folgt der Chunkzahl, siehe Kommentar)" % do)
	var ok := absf(dk) < 1.0
	print("-> %s" % ("kein Leck" if ok else "LECK-VERDACHT"))
