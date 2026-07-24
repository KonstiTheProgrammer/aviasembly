## Beleg, dass die Blender-Gebaeude IM SPIEL stehen: zaehlt die MultiMesh-Instanzen im
## echten Szenenbaum und schiesst mit einer eigenen Kamera Luftbilder der neuen Viertel.
extends SceneTree
var f := 0
var m: Node
var cam: Camera3D
var i := 0
var t0 := 0
var ziele := [
	["stadt", Vector3(4300, 0, 2500), 620.0, 330.0],
	["industrie", Vector3(3500, 0, -1500), 430.0, 200.0],
	["dorf", Vector3(-2300, 0, 1900), 400.0, 190.0],
	["burg", Vector3(-1750, 0, 3150), 300.0, 190.0],
	["flugplatz", Vector3(0, 0, 210), 330.0, 150.0],
]

func _zaehle() -> void:
	for n in m.fly_world.get_children():
		if not (n is Node3D) or n.get_child_count() == 0:
			continue
		var typen := 0
		var inst := 0
		for c in n.get_children():
			var mmi := c as MultiMeshInstance3D
			if mmi != null and mmi.multimesh != null:
				typen += 1
				inst += mmi.multimesh.instance_count
		if typen > 0:
			print("VIERTEL %-26s %2d Typen, %3d Gebaeude" % [n.name, typen, inst])

func _hin() -> void:
	var z: Vector3 = ziele[i][1]
	# Das Flugzeug MUSS mitkommen: Main._process ruft update_center(aircraft.pos) und
	# loescht alles jenseits VIEW_DIST — sonst baut und verwirft der Worker im Wechsel
	# (Endlos-Thrash, genau darin haengengeblieben).
	var ac = m.flight_ctrl.aircraft
	if is_instance_valid(ac):
		ac.global_position = z + Vector3(0, ziele[i][3] + 60.0, 0)
		ac.linear_velocity = Vector3.ZERO
	m.terrain.build_now_around(z, 1100.0)
	var d: float = ziele[i][2]
	var h: float = ziele[i][3]
	var p := z + Vector3(-d, h, -d)
	cam.look_at_from_position(p, z + Vector3(0, 30, 0), Vector3.UP)

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var ps: PackedScene = load("res://scenes/Main.tscn")
		m = ps.instantiate()
		get_root().add_child(m)
		return false
	if f == 20:
		m._set_mode(1)
		_zaehle()
		cam = Camera3D.new()
		cam.far = 9000.0
		m.fly_world.add_child(cam)
		return false
	if f == 30:
		cam.current = true      # erst wenn im Baum -> uebernimmt von der Flugkamera
		t0 = f
		_hin()
		return false
	if t0 > 0 and f - t0 == 70:
		get_root().get_viewport().get_texture().get_image().save_png(
			"user://city_%s.png" % ziele[i][0])
		print("SHOT ", ziele[i][0])
		i += 1
		if i >= ziele.size():
			quit()
			return true
		t0 = f
		_hin()
	if f > 2500:
		print("TIMEOUT")
		quit()
	return false
