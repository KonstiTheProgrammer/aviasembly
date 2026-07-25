## Belegt den Zielzoom: dieselbe Szene ohne und mit Zoom, plus die gemessenen Werte.
extends SceneTree
var f := 0
var m: Node
var phase := 0
var t0 := 0

func _stell() -> void:
	var fc = m.flight_ctrl
	var ac = fc.aircraft
	ac.global_position = Vector3(3000, 300, 1400)
	ac.linear_velocity = Vector3.ZERO
	m.terrain.build_now_around(ac.global_position, 1100.0)

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var ps: PackedScene = load("res://scenes/Main.tscn")
		m = ps.instantiate()
		get_root().add_child(m)
		return false
	if f == 20:
		m._set_mode(1)
		return false
	if f == 45:
		_stell()
		t0 = f
		return false
	if t0 > 0 and f - t0 == 50:
		var fc = m.flight_ctrl
		print("OHNE  zoom_t=%.2f  vfov=%.1f  cam_dist=%.1f" % [fc.zoom_t, fc.camera.fov,
			fc.camera.global_position.distance_to(fc.aircraft.global_position)])
		get_root().get_viewport().get_texture().get_image().save_png("user://zoom_aus.png")
		fc.zoom_t = 1.0                     # entspricht gehaltenem V
		return false
	if t0 > 0 and f - t0 == 60:
		var fc = m.flight_ctrl
		fc.zoom_t = 1.0
		print("MIT   zoom_t=%.2f  vfov=%.1f  cam_dist=%.1f" % [fc.zoom_t, fc.camera.fov,
			fc.camera.global_position.distance_to(fc.aircraft.global_position)])
		get_root().get_viewport().get_texture().get_image().save_png("user://zoom_an.png")
		quit()
		return true
	if t0 > 0 and f - t0 > 50:
		m.flight_ctrl.zoom_t = 1.0          # gegen das Zurueckfahren pro Frame
	if f > 900:
		print("TIMEOUT")
		quit()
	return false
