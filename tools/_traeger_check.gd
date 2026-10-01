extends SceneTree
## Prueft die Flugzeugtraeger (tools/build_traeger_modelle.py) so, wie das Spiel sie setzt:
## je Traeger wird das glb wirklich geladen, stimmt mit den gemessenen Massen ueberein, bleibt
## schlicht, und Landmarks.build_traeger legt eine Kollision darunter, deren Deck dort ist, wo
## die Landebahn eingetragen ist (Strahl von oben auf Anfang, Mitte und Ende der Bahn).
## Laedt Main NICHT — fasst also keinen Spielstand an.
##   Godot --headless --path . --script res://tools/_traeger_check.gd

const MASSE := "res://tools/traeger_modelle_masse.json"
const MAX_DREIECKE := 3500          # "schlicht": die Vorlagen hatten 230 000 bis 450 000
const ABSTAND := 600.0              # so weit stehen die Prueflinge auseinander

var _frame := 0
var _daten: Dictionary = {}
var _knoten: Dictionary = {}
var _welt: Node3D = null
var _info := ""


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	if _welt == null:
		var f := FileAccess.open(MASSE, FileAccess.READ)
		_daten = JSON.parse_string(f.get_as_text())
		_welt = Node3D.new()
		root.add_child(_welt)
		var i := 0
		for id: String in _daten.keys():
			_knoten[id] = Landmarks.build_traeger(_welt, id, Vector2(float(i) * ABSTAND, 0.0), 0.7 * float(i))
			i += 1
		return false
	if _frame < 8:                 # die Physik braucht ein paar Schritte, bis die Koerper stehen
		return false
	var schlecht := 0
	for id: String in _daten.keys():
		_info = ""
		var fehler := _pruefe(id)
		print("%-12s %s  %s" % [id, "OK" if fehler.is_empty() else "FEHLER", _info])
		for t in fehler:
			print("    %s" % t)
		if not fehler.is_empty():
			schlecht += 1
	print("URTEIL: ", "OK (%d Traeger)" % _daten.size() if schlecht == 0
		else "FEHLER (%d von %d)" % [schlecht, _daten.size()])
	quit(0 if schlecht == 0 else 1)
	return true


func _pruefe(id: String) -> Array[String]:
	var fehler: Array[String] = []
	var soll: Dictionary = _daten[id]
	var node := _knoten[id] as Node3D
	if node == null:
		fehler.append("build_traeger liefert nichts (glb fehlt oder nicht importiert)")
		return fehler
	var box := AABB()
	var erste := true
	var dreiecke := 0
	var namen: Array[String] = []
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var felder := mi.mesh.surface_get_arrays(s)
			var punkte: PackedVector3Array = felder[Mesh.ARRAY_VERTEX]
			var idx = felder[Mesh.ARRAY_INDEX]
			dreiecke += (punkte.size() if idx == null else (idx as PackedInt32Array).size()) / 3
			var mat := mi.mesh.surface_get_material(s)
			namen.append("" if mat == null else String(mat.resource_name))
			for p in punkte:
				if erste:
					box = AABB(p, Vector3.ZERO)
					erste = false
				else:
					box = box.expand(p)
	_nah(fehler, "Laenge", box.size.z, float(soll["laenge"]), 0.05)
	_nah(fehler, "Breite", box.size.x, float(soll["breite"]), 0.05)
	_nah(fehler, "Hoehe ueber Wasser", box.end.y, float(soll["hoehe"]), 0.05)
	if dreiecke != int(soll["dreiecke"]):
		fehler.append("Dreiecke %d, gebaut wurden %d" % [dreiecke, int(soll["dreiecke"])])
	if dreiecke > MAX_DREIECKE:
		fehler.append("%d Dreiecke — nicht mehr schlicht (Grenze %d)" % [dreiecke, MAX_DREIECKE])
	for n: String in ["rumpf", "deck", "aufbau"]:
		if not namen.has(n):
			fehler.append("Material '%s' fehlt" % n)
	# Kollision: vorhanden, und ohne die Deckmarkierung
	var form: ConcavePolygonShape3D = null
	for cs: CollisionShape3D in node.find_children("*", "CollisionShape3D", true, false):
		form = cs.shape as ConcavePolygonShape3D
	if form == null:
		fehler.append("keine Kollision")
		return fehler
	var koll_dreiecke := form.get_faces().size() / 3
	if koll_dreiecke <= 0 or koll_dreiecke >= dreiecke:
		fehler.append("Kollision hat %d Dreiecke bei %d sichtbaren — die Markierung ist nicht draussen"
			% [koll_dreiecke, dreiecke])
	# Deck dort, wo die Bahn eingetragen ist
	var bahn: Array = soll.get("bahn", [])
	if bahn.size() != 2:
		fehler.append("keine Landebahn eingetragen")
		return fehler
	var a := Vector3(bahn[0][0], bahn[0][1], bahn[0][2])
	var b := Vector3(bahn[1][0], bahn[1][1], bahn[1][2])
	var raum := root.get_world_3d().direct_space_state
	for t: float in [0.02, 0.5, 0.98]:
		var lokal := a.lerp(b, t)
		var welt := node.global_transform * lokal
		var q := PhysicsRayQueryParameters3D.create(welt + Vector3.UP * 80.0, welt - Vector3.UP * 80.0, 1)
		var treffer := raum.intersect_ray(q)
		if treffer.is_empty():
			fehler.append("Bahn bei %.0f %%: kein Deck unter dem Strahl" % (t * 100.0))
			continue
		var hoehe: float = (treffer["position"] as Vector3).y - node.global_position.y
		if absf(hoehe - lokal.y) > 0.15:
			fehler.append("Bahn bei %.0f %%: Deck auf %.2f m, eingetragen %.2f m" % [t * 100.0, hoehe, lokal.y])
		if (treffer["normal"] as Vector3).y < 0.9:
			fehler.append("Bahn bei %.0f %%: Flaeche zeigt nicht nach oben (%s)" % [t * 100.0, treffer["normal"]])
	_info = "%.0f x %.0f m, Deck %.1f m, Mast %.1f m, %d Dreiecke (Kollision %d), Bahn %.0f m" % [
		box.size.z, box.size.x, float(soll["deck"]), box.end.y, dreiecke, koll_dreiecke, a.distance_to(b)]
	return fehler


func _nah(fehler: Array[String], was: String, ist: float, soll: float, tol: float) -> void:
	if absf(ist - soll) > tol:
		fehler.append("%s %.2f m, gebaut wurden %.2f m" % [was, ist, soll])
