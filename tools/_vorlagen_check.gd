## SIND ALLE VORLAGEN STARTKLAR — OHNE UPGRADES?
##
## Fuer das Erststart-Flugzeug und jede Vorlage aus Main.PRESETS:
##   - laedt vollstaendig (keine unbekannten Teile)
##   - hat eine Wurzel und KEINE frei haengenden Teile (sonst ist der Start blockiert)
##   - Fahrwerk traegt die Masse (sonst reissen beim Start die Raeder ab)
##
## compute_stats rechnet OHNE die Survival-Upgrades. Genau darauf kommt es an: der
## Nachtfalke war um 5 kg ueberlastet, und wer — wie beim Entwerfen — Leichtbau auf
## Stufe 3 hatte, merkte es nie; ein neuer Spieler lag nach dem Start auf dem Bauch.
##
##   HOME=/tmp/avi_home Godot --headless --path . --script res://tools/_vorlagen_check.gd
extends SceneTree

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


func _lauf() -> void:
	var bc = m.get("build_ctrl")
	var fehler := 0
	var liste: Array = [["_standard", "Erststart"]] + (m.get("PRESETS") as Array)
	for pr in liste:
		var id := String(pr[0])
		var soll := 0
		if id == "_standard":
			var d: Array = m.call("_default_design")
			soll = d.size()
			bc.load_design(d)
		else:
			var roh = JSON.parse_string(FileAccess.get_file_as_string("res://designs/%s.json" % id))
			soll = (roh as Array).size() if roh is Array else -1
			m.call("_load_design_from", "res://designs/%s.json" % id)
		var st: Dictionary = bc.compute_stats()
		var teile: int = bc.get_design().size()
		var frei: int = bc.floating_count()
		var masse: float = st.get("mass", 0.0)
		var kap: float = st.get("gear_cap", 0.0)
		var probleme: Array = []
		if teile != soll:
			probleme.append("%d von %d Teilen geladen" % [teile, soll])
		if not bc.has_root():
			probleme.append("keine Wurzel")
		if frei > 0:
			probleme.append("%d frei haengend" % frei)
		if kap > 0.0 and masse > kap:
			probleme.append("Fahrwerk ueberlastet (%.0f > %.0f kg)" % [masse, kap])
		print("%-12s %3d Teile  %5.0f kg  Traglast %5.0f kg  %s" % [id, teile, masse, kap,
			"ok" if probleme.is_empty() else "FALSCH: " + ", ".join(probleme)])
		if not probleme.is_empty():
			fehler += 1
	print("-> %d Beanstandungen" % fehler)
