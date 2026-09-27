## SURVIVAL VON ANFANG BIS AUSWERTUNG.
##
## Prueft in der echten Main-Szene mit einem frischen Survival-Spielstand (nur Starter-
## Teile, 1000 Geld):
##   SPERRE     Vorlage mit ungekauften Teilen laden -> Start wird verweigert
##   START      Standard-Doppeldecker (nur Starter-Teile) -> Start klappt, Welle 1 laeuft
##   WELLE      alle Ziele abschiessen -> Geld steigt, Combo, Welle 2 startet
##   AUSWERTUNG zurueck in den Hangar -> Ergebnisdialog steht
##
## ACHTUNG: schreibt user://aviassembly_progress.json und stellt den alten Inhalt am Ende
## wieder her. Trotzdem NUR mit umgebogenem HOME starten:
##   HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/_survival_check.gd
extends SceneTree

const PFAD := "user://aviassembly_progress.json"
var m: Node = null
var f := 0
var fehler := 0
var alt_stand := ""
var hatte_stand := false
var phase := 0
var t := 0
var geld0 := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		hatte_stand = FileAccess.file_exists(PFAD)
		if hatte_stand:
			alt_stand = FileAccess.get_file_as_string(PFAD)
		var unl := {}
		for id in GameState.STARTER:
			unl[id] = true
		var fa := FileAccess.open(PFAD, FileAccess.WRITE)
		fa.store_string(JSON.stringify({"version": 1, "mode": GameState.GameMode.SURVIVAL,
			"money": 1000, "unlocked": unl, "flags": {"controls_hint": true}}))
		fa.close()
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f < 20:
		return false
	t += 1
	match phase:
		0:
			var game = m.get("game")
			_pruef("Spielstand ist Survival", not game.is_sandbox())
			m.call("_load_design_from", "res://designs/f22.json")
			m.call("_set_mode", 1)
			_pruef("F-22 mit ungekauften Teilen: Start verweigert", int(m.get("mode")) == 0,
				"gesperrt: " + ", ".join(m.call("_ungekaufte_teile")))
			m.get("build_ctrl").call("load_design", m.call("_default_design"))
			_pruef("Standard-Doppeldecker: nichts gesperrt",
				(m.call("_ungekaufte_teile") as Array).is_empty())
			geld0 = int(game.money)
			m.call("_set_mode", 1)
			_pruef("Standard-Doppeldecker startet", int(m.get("mode")) == 1)
			_pruef("Welle 1 laeuft", int(m.get("_wave")) == 1, "%d Ziele" % int(m.get("_alive")))
			phase = 1
			t = 0
		1:
			# Alle Ziele der Welle abschiessen, eins je Frame (Combo zaehlt).
			var tr: Node = m.get("targets_root")
			var getroffen := false
			for c in tr.get_children():
				if c is Target and not bool(c.get("_dead")):
					c.call("hit", 99.0)
					getroffen = true
					break
			if not getroffen and t > 5:
				var game = m.get("game")
				_pruef("Geld gestiegen", int(game.money) > geld0, "%d -> %d" % [geld0, int(game.money)])
				_pruef("Combo gezaehlt", int(m.get("_best_combo")) >= 3,
					"beste Combo x%d" % int(m.get("_best_combo")))
				phase = 2
				t = 0
		2:
			if int(m.get("_wave")) == 2 or t > 60 * 6:
				_pruef("Welle 2 startet nach der Pause", int(m.get("_wave")) == 2)
				m.call("_set_mode", 0)
				var steht := false
				for c in (m.get("ui") as Node).get_children():
					if c is Control and (c as Control).visible and _hat_text(c, "Flug-Auswertung"):
						steht = true
				_pruef("Ergebnisdialog nach der Landung", steht)
				_ende()
	return false


func _hat_text(n: Node, s: String) -> bool:
	if n is Label and (n as Label).text.contains(s):
		return true
	for c in n.get_children():
		if _hat_text(c, s):
			return true
	return false


func _pruef(name: String, ok: bool, info := "") -> void:
	print("%-50s %s  %s" % [name, "OK" if ok else "FALSCH", info])
	if not ok:
		fehler += 1


func _ende() -> void:
	if hatte_stand:
		var fa := FileAccess.open(PFAD, FileAccess.WRITE)
		fa.store_string(alt_stand)
		fa.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PFAD))
	print("-> %d Beanstandungen" % fehler)
	quit()
