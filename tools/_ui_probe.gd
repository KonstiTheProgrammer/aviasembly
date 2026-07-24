## UI-PROBE: startet die ECHTE Main-Szene (native Aufloesung), speichert Screenshots von
## Hangar-UI, Flug-HUD und KARTE nach user:// — zur Design-Analyse auf dem echten Rechner.
extends SceneTree
var f := 0
var m: Node
var _map_opened := false
func _shot(n: String) -> void:
	get_root().get_viewport().get_texture().get_image().save_png("user://" + n)
	print("SHOT ", n)
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var ps: PackedScene = load("res://scenes/Main.tscn")
		m = ps.instantiate()
		get_root().add_child(m)
		return false
	if f == 30:
		_shot("ui_hangar.png")
		m._set_mode(1)   # Mode.FLY
		return false
	if f == 140:
		_shot("ui_flug.png")
		return false
	if f > 140 and not _map_opened and m.world_map != null and not m.world_map.visible:
		_map_opened = true   # nur EINMAL oeffnen (sonst Reopen-Loop)
		m._toggle_map()
		return false
	if f > 145 and m.world_map != null and m.world_map.visible and f % 5 == 0:
		_shot("ui_karte.png")
		m._toggle_map()   # schliessen -> Corner-Minimap wird sichtbar
		return false
	if f > 150 and m.world_map != null and not m.world_map.visible and m.flight_hud.mini_tex != null:
		_shot("ui_minimap.png")
		quit()
	if f > 2400:
		print("TIMEOUT Karte")
		quit()
	return false
