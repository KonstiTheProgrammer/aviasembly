## BILDER DER DIALOGE UND DES SURVIVAL-UI zum Draufschauen.
##
## Laeuft mit einem FRISCHEN Benutzerordner (kein Spielstand -> Modus-Auswahl erscheint):
##   HOME=/tmp/avi_frisch Godot --path . --script res://tools/_dialog_bilder.gd
## Bilder in user://: dlg_modus.png, dlg_laden.png, dlg_speichern.png,
## dlg_survival_flug.png, dlg_auswertung.png
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
	match f:
		40:
			_bild("dlg_modus.png")
			m.call("_choose_mode", GameState.GameMode.SURVIVAL)
		50:
			m.call("_show_load_dialog")
		60:
			_bild("dlg_laden.png")
			m.call("_close_dialog")
			m.call("_show_save_dialog")
		70:
			_bild("dlg_speichern.png")
			m.call("_close_dialog")
			m.call("_set_mode", 1)
		80:
			var ac = m.get("flight_ctrl").get("aircraft")
			ac.global_transform = Transform3D(Basis(), Vector3(0.0, 150.0, -300.0))
			ac.linear_velocity = Vector3(0, 0, -60.0)
			m.get("flight_ctrl").call("_reset_mouse_state")
			# ein paar Abschuesse fuer Combo und Score
			var n := 0
			for c in (m.get("targets_root") as Node).get_children():
				if c is Target and n < 3:
					c.call("hit", 99.0)
					n += 1
		110:
			_bild("dlg_survival_flug.png")
			m.call("_set_mode", 0)
		125:
			_bild("dlg_auswertung.png")
			quit()
	return false


func _bild(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("user://" + name)
	print("BILD ", name)
