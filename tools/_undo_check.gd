## UNDO / REDO IM HANGAR — und ob jede Bearbeitung den Autosave anstoesst.
##
## Bis hierher testete kein einziges Werkzeug den Verlauf. Geprueft wird in der echten
## Main-Szene mit der Spitfire-Vorlage:
##   LOESCHEN     Fluegel samt Spiegel weg -> Undo bringt beide zurueck, Spiegel wieder
##                verknuepft -> Redo entfernt sie wieder
##   PFEILTASTE   nudge_selected verschiebt -> Autosave-Flag gesetzt -> Undo stellt zurueck
##   DUPLIZIEREN  Klon (+Spiegel) -> Undo entfernt ihn
##   LACKIEREN    Farbe -> Undo stellt die alte Farbe her
##   GRENZE       60 Schritte -> Verlauf bleibt bei 40, Undo laeuft bis zum Anfang durch
##
##   HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/_undo_check.gd
extends SceneTree

var m: Node = null
var f := 0
var fehler := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 20:
		m.call("_load_design_from", "res://designs/spitfire.json")
		return false
	if f == 25:
		_lauf()
		quit()
	return false


func _signatur(bc) -> String:
	var zeilen: Array = []
	for it in bc.get_design():
		var xf: Transform3D = it.get("xform", Transform3D())
		var c: Color = it.get("color", Color(0, 0, 0, 0))
		zeilen.append("%s@%.2f,%.2f,%.2f#%s" % [it.get("id", "?"), xf.origin.x, xf.origin.y,
			xf.origin.z, c.to_html()])
	zeilen.sort()
	return "|".join(zeilen)


func _pruef(name: String, ok: bool, info := "") -> void:
	print("%-44s %s  %s" % [name, "OK" if ok else "FALSCH", info])
	if not ok:
		fehler += 1


func _teil_mit_spiegel(bc) -> Node3D:
	for c in bc.design_root.get_children():
		if c.is_in_group("part") and c.has_meta("mirror") and is_instance_valid(c.get_meta("mirror")) \
				and not bool(c.get_meta("is_root", false)) and (c as Node3D).position.x > 0.3:
			return c
	return null


func _lauf() -> void:
	var bc = m.get("build_ctrl")
	var s0 := _signatur(bc)
	var n0: int = bc.get_design().size()
	_pruef("Start: kein Undo moeglich", not bc.can_undo(), "(%d Teile)" % n0)

	# --- LOESCHEN mit Spiegel -----------------------------------------------------
	var teil := _teil_mit_spiegel(bc)
	_pruef("Teil mit Spiegel gefunden", teil != null,
		String(teil.get_meta("part_id")) if teil != null else "")
	if teil == null:
		return
	var tid := String(teil.get_meta("part_id"))
	bc._select_part(teil)
	bc.delete_selected()
	var n1: int = bc.get_design().size()
	_pruef("Loeschen entfernt Teil + Spiegel", n1 == n0 - 2, "%d -> %d" % [n0, n1])
	bc.undo()
	_pruef("Undo bringt beide zurueck (identisch)", _signatur(bc) == s0)
	var zurueck := _teil_mit_spiegel(bc)
	_pruef("Spiegel nach Undo wieder verknuepft", zurueck != null)
	bc.redo()
	_pruef("Redo loescht wieder", bc.get_design().size() == n0 - 2)
	bc.undo()

	# --- PFEILTASTE ---------------------------------------------------------------
	teil = _teil_mit_spiegel(bc)
	m.set("_design_dirty", false)
	bc._select_part(teil)
	var p0: Vector3 = teil.position
	bc.nudge_selected(Vector3(0, 0.25, 0))
	_pruef("Pfeiltaste verschiebt", teil.position.distance_to(p0 + Vector3(0, 0.25, 0)) < 0.001)
	_pruef("Pfeiltaste stoesst den Autosave an", bool(m.get("_design_dirty")))
	bc.undo()
	_pruef("Undo nach Pfeiltaste = Ausgangszustand", _signatur(bc) == s0)

	# --- DUPLIZIEREN --------------------------------------------------------------
	teil = _teil_mit_spiegel(bc)
	bc._select_part(teil)
	bc.duplicate_selected()
	var n2: int = bc.get_design().size()
	_pruef("Duplizieren legt Klon + Spiegel an", n2 == n0 + 2, "%d -> %d" % [n0, n2])
	bc.undo()
	_pruef("Undo nach Duplizieren = Ausgangszustand", _signatur(bc) == s0)

	# --- LACKIEREN ----------------------------------------------------------------
	teil = _teil_mit_spiegel(bc)
	bc._recolor(teil, Color(0.1, 0.9, 0.2))
	bc._push_history()
	_pruef("Lackieren aendert den Entwurf", _signatur(bc) != s0)
	bc.undo()
	_pruef("Undo nach Lackieren = alte Farbe", _signatur(bc) == s0)

	# --- GRENZE -------------------------------------------------------------------
	teil = _teil_mit_spiegel(bc)
	bc._select_part(teil)
	for i in 60:
		bc.nudge_selected(Vector3(0.0, 0.0, 0.01))
	var laenge: int = (bc.get("_history") as Array).size()
	_pruef("Verlauf auf 40 Eintraege begrenzt", laenge <= 41, "%d" % laenge)
	var schritte := 0
	while bc.can_undo() and schritte < 100:
		bc.undo()
		schritte += 1
	_pruef("Undo laeuft bis zum Anfang durch", not bc.can_undo(), "%d Schritte" % schritte)
	var tid2 := ""
	var t2 := _teil_mit_spiegel(bc)
	if t2 != null:
		tid2 = String(t2.get_meta("part_id"))
	_pruef("Entwurf danach noch vollstaendig", bc.get_design().size() == n0 and tid2 == tid)
	print("-> %d Beanstandungen" % fehler)
