## BILDER VOM FLUG-UI zum Draufschauen: HUD mit voller Waffenleiste, Vollbildkarte,
## Pausenmenue und der Nachtfalke mit Schachtzeile. Die Randpruefung (_ui_rand_check)
## misst nur gegen den Bildschirmrand — Ueberlappungen untereinander sieht man nur im Bild.
##
##   HOME=/tmp/avi_home Godot --path . --script res://tools/_flug_bilder.gd
## Bilder landen in user:// (flug_hud.png, flug_hud_stadt.png, flug_karte.png,
## flug_karte_zoom.png (3x, mit Detailkacheln), flug_karte_zoom8.png, flug_hud_wegpunkt.png, flug_pause.png,
## flug_schacht.png).
extends SceneTree

var m: Node = null
var f := 0
var t := 0
var phase := 0
var zustand := 0
var t_zoom := 0


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
		m.call("_set_mode", 1)
		return false
	if f < 30:
		return false
	var fc = m.get("flight_ctrl")
	var ac = fc.get("aircraft")
	t += 1
	match phase:
		0:
			ac.global_transform = Transform3D(Basis(), Vector3(200.0, 380.0, -900.0))
			ac.linear_velocity = Vector3(0, 0, -140.0)
			fc.set("throttle", 0.9)
			fc.call("_reset_mouse_state")
			var gruppen: Array = fc.get("weapon_groups")
			for i in gruppen.size():
				if String(gruppen[i]["id"]) == "missile":
					fc.set("weapon_sel", i)
			phase = 1
			t = 0
		1:
			if t == 140:
				ac.set("landing_msg", "Saubere Landung")
				ac.set("_land_timer", 3.0)
			if t == 150:
				_bild("flug_hud.png")
			# Auf die FEINE Karte warten (zweite Stufe, siehe Main): _map_thread ist erst
			# danach wieder null. Dann ueber die Grossstadt setzen, damit die Zoomstufen
			# Strassen, Haeuser und Bahnen zeigen.
			if m.get("world_map") != null and m.get("_map_thread") == null and t > 150:
				ac.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-35.0)),
					Vector3(3300.0, 420.0, 3600.0))
				ac.linear_velocity = -ac.global_transform.basis.z * 120.0
				fc.call("_reset_mouse_state")
				phase = 2
				t = 0
		2:
			var wm = m.get("world_map")
			if t == 30:
				_bild("flug_hud_stadt.png")
				m.call("_toggle_map")
				# Wegpunkt aufs Landdorf, Maus ueber die Karte (Tooltip)
				wm.call("setze_wegpunkt", Vector2(-2300.0, 1900.0), "")
			if t == 45:
				wm.set("_maus", Vector2(760.0, 420.0))
			if t == 50:
				_bild("flug_karte.png")
				wm.call("set_zoom", 3.0)
			# Auf die scharfen Detailkacheln warten (hoechstens 60 s), dann noch naeher ran
			if t > 60 and t < 5000 and t % 10 == 0 and zustand == 0 \
					and (wm.call("kacheln_bereit") or t > 60 + 3600):
				_bild("flug_karte_zoom.png")
				wm.call("set_zoom", 8.0)
				zustand = 1
				t_zoom = t
			if zustand == 1 and t > t_zoom + 10 and t % 10 == 0 \
					and (wm.call("kacheln_bereit") or t > t_zoom + 3600):
				_bild("flug_karte_zoom8.png")
				wm.call("set_zoom", 1.0)
				m.call("_toggle_map")
				zustand = 2
				t = 50
			if zustand == 2 and t == 65:
				_bild("flug_hud_wegpunkt.png")   # NAV-Pille zeigt den Wegpunkt
				m.call("_set_pause", true)
				t = 70
			if t == 80 and zustand == 2:
				_bild("flug_pause.png")
				m.call("_set_pause", false)
				m.call("_set_mode", 0)
				m.call("_load_design_from", "res://designs/nachtfalke.json")
				m.call("_set_mode", 1)
				phase = 3
				t = 0
		3:
			if t == 5:
				ac = fc.get("aircraft")
				ac.global_transform = Transform3D(Basis(), Vector3(200.0, 380.0, -900.0))
				ac.linear_velocity = Vector3(0, 0, -120.0)
				fc.call("_reset_mouse_state")
				ac.call("toggle_bay")
			if t == 120:
				_bild("flug_schacht.png")
				quit()
	return false


func _bild(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("user://" + name)
	print("BILD ", name)
