## SICHTPROBE WEICHES ERSCHEINEN: haengt 3 x 3 Chunks im Gebirge ueber den Streaming-Weg
## neu ein und fotografiert sie im ALTER 0,05 / 0,7 / 2,0 s (der Zeitpunkt "erschienen"
## wird je Bild gesetzt — so haengt das Bild nicht an der Framezeit).
##   HOME=<test-home> Godot --path . --script res://tools/_weich_bild.gd -- [x z]
## Bilder: user://weich_0.png, weich_1.png, weich_2.png
extends SceneTree
var m: Node
var f := 0
var cam: Camera3D
var ziel := Vector2(-8200, -6400)
var t_neu := 0
var bild := 0
const ALTER := [0.05, 0.7, 2.0]
var neu_knoten: Array = []
var warte := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 2:
		ziel = Vector2(float(a[0]), float(a[1]))


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f < 20:
		return false
	if f == 20:
		m._set_mode(1)
		return false
	var t: TerrainWorld = m.terrain
	if f == 30:
		var gy := t.height_at(ziel.x, ziel.y)
		var p := Vector3(ziel.x + 380.0, gy + 260.0, ziel.y + 520.0)
		var ac = m.flight_ctrl.aircraft
		ac.freeze = true
		ac.global_position = p + Vector3(0, 40, 0)
		t.build_now_around(Vector3(ziel.x, 0, ziel.y), 2200.0)
		cam = Camera3D.new()
		cam.far = 9000.0
		cam.fov = 62.0
		m.fly_world.add_child(cam)
		cam.look_at_from_position(p, Vector3(ziel.x, gy, ziel.y), Vector3.UP)
		cam.current = true
		for c in m.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		return false
	if f < 400:
		return false     # Schuerze/Wasser/Baeume ringsum setzen lassen
	if t_neu == 0:
		# 3 x 3 Chunks um das Ziel ueber den Streaming-Weg neu einhaengen
		var k0 := Vector2i(floori(ziel.x / TerrainWorld.CHUNK), floori(ziel.y / TerrainWorld.CHUNK))
		var chunks: Dictionary = t.get("_chunks")
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var k := k0 + Vector2i(dx, dz)
				if chunks.has(k):
					(chunks[k] as Node).free()
					chunks.erase(k)
				var dat: Dictionary = t._make_chunk_data(k)
				t._attach_chunk(k, dat["mesh"], dat["shape"], dat["flora"], dat["rocks"],
					dat["tiefe"], dat["gras"], true)
				neu_knoten.append(chunks[k])
		t.call("_flora_alles_nachziehen")
		t.call("_tiefe_hochladen")
		t_neu = 1
		return false
	# Alter setzen (jeden Frame, damit es steht), nach 4 Frames fotografieren
	var jetzt := TerrainWorld.welt_zeit()
	for n in neu_knoten:
		for c in (n as Node).get_children():
			if c is GeometryInstance3D:
				(c as GeometryInstance3D).set_instance_shader_parameter("erschienen",
					jetzt - float(ALTER[bild]))
	warte += 1
	if warte >= 4:
		warte = 0
		root.get_viewport().get_texture().get_image().save_png("user://weich_%d.png" % bild)
		print("WEICH Bild %d im Alter %.2f s" % [bild, ALTER[bild]])
		bild += 1
		if bild >= ALTER.size():
			quit()
	return false
