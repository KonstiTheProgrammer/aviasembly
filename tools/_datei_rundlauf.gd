## DATEI-RUNDLAUF: ueberlebt jeder Wert eines Entwurfs Speichern und Laden?
##
## CLAUDE.md: "Ein neues Pro-Teil-Meta braucht VIER Stellen" — get_design/load_design,
## Main._design_data (Datei schreiben), Main._load_design_from (Datei lesen) und den
## Mesh-Bauer. Fehlt eine, ist der Wert im Editor da und nach dem Neustart still weg.
## Dieses Werkzeug faehrt fuer JEDE Vorlage den kompletten Weg:
##   Vorlage laden -> get_design -> Datei schreiben -> Datei laden -> get_design
## und vergleicht Schluessel fuer Schluessel. Zusaetzlich ein Entwurf, in dem von Hand
## geformt wurde (Versatz, Beinlaenge, Umkehrschub, Wurzel nicht das erste Teil).
##
##   HOME=/tmp/avi_home Godot --headless --path . --script res://tools/_datei_rundlauf.gd
extends SceneTree

const TMP := "user://_rundlauf_tmp.json"
var m: Node = null
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 20:
		_lauf()
		quit()
	return false


func _gleich(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_TRANSFORM3D:
		var ta: Transform3D = a
		var tb: Transform3D = b
		return ta.origin.distance_to(tb.origin) < 1e-4 \
			and (ta.basis.x - tb.basis.x).length() < 1e-4 \
			and (ta.basis.y - tb.basis.y).length() < 1e-4 \
			and (ta.basis.z - tb.basis.z).length() < 1e-4
	if typeof(a) == TYPE_COLOR:
		return (a as Color).is_equal_approx(b)
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return absf(float(a) - float(b)) < 1e-4
	if typeof(a) in [TYPE_VECTOR2, TYPE_VECTOR3]:
		return a.is_equal_approx(b)
	if typeof(a) == TYPE_ARRAY:
		var aa: Array = a
		var bb: Array = b
		if aa.size() != bb.size():
			return false
		for i in aa.size():
			if not _gleich(aa[i], bb[i]):
				return false
		return true
	return a == b


func _vergleich(name: String) -> int:
	var bc = m.get("build_ctrl")
	var vorher: Array = bc.get_design()
	m.call("_write_design", TMP)
	m.call("_load_design_from", TMP)
	var nachher: Array = bc.get_design()
	# PER INDEX vergleichen, nicht ueber id+Position: manche Vorlagen haben zwei gleiche
	# Teile am selben Ort, nur verschieden gedreht — eine Zuordnung ueber die Position
	# verwechselte sie und meldete falsche Verluste. Die Reihenfolge ist stabil:
	# get_design laeuft ueber die Kinder, load_design legt sie in Array-Reihenfolge an.
	var verloren := {}
	if nachher.size() != vorher.size():
		verloren["<Teilezahl %d -> %d>" % [vorher.size(), nachher.size()]] = true
	for i in mini(vorher.size(), nachher.size()):
		var it: Dictionary = vorher[i]
		var n: Dictionary = nachher[i]
		for key in it.keys():
			if not n.has(key) or not _gleich(it[key], n[key]):
				verloren[key] = true
	var fehl := verloren.size()
	print("%-22s %3d Teile   %s" % [name, vorher.size(),
		"alles erhalten" if fehl == 0 else "VERLOREN: " + ", ".join(verloren.keys())])
	return 1 if fehl > 0 else 0


func _lauf() -> void:
	var fehler := 0
	for pr in m.get("PRESETS"):
		m.call("_load_design_from", "res://designs/%s.json" % pr[0])
		fehler += _vergleich(pr[0])
	# Von Hand geformt: die Werte, die frueher schon einmal verloren gingen.
	m.call("_load_design_from", "res://designs/spitfire.json")
	var bc = m.get("build_ctrl")
	var teile: Array = []
	for c in bc.design_root.get_children():
		if c.is_in_group("part"):
			teile.append(c)
	for c in teile:
		c.set_meta("is_root", false)
		var p := PartCatalog.get_part(String(c.get_meta("part_id")))
		if p.get("biends", false):
			c.set_meta("shift_front", Vector2(0.1, -0.05))
			c.set_meta("shift_back", Vector2(-0.02, 0.07))
		if float(p.get("gear_capacity", 0.0)) > 0.0:
			c.set_meta("gear_len", 1.4)
		if float(p.get("thrust", 0.0)) > 0.0 and not bool(p.get("jet", false)):
			c.set_meta("thrust_reverse", true)
	# Die Wurzel absichtlich NICHT auf das Cockpit legen: _ensure_root waehlte beim Laden
	# sonst ohnehin das Cockpit, und der Test saehe nicht, ob die Wurzel gespeichert wird.
	(teile[teile.size() - 1] as Node).set_meta("is_root", true)
	fehler += _vergleich("von Hand geformt")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	print("-> %d Entwuerfe mit Verlust" % fehler)
