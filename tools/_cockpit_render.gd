## Rendert jede Kanzel MIT angedocktem Rumpfsegment — zeigt, ob die ebene Stirnflaeche
## und der Querschnitt des Segments wirklich zusammenpassen (Naht).
extends SceneTree
var f := 0
var i := 0
var teile := ["bubble", "jet", "frame", "tandem"]
var root3: Node3D
var cam: Camera3D
var akt: Node3D

func _zeige() -> void:
	if akt != null:
		akt.queue_free()
	akt = Node3D.new()
	root3.add_child(akt)
	var stil := String(teile[i])
	var cd := PartCatalog.get_part("cockpit_" + stil)
	var fd := PartCatalog.get_part("fuselage_" + stil)
	var ps: PackedScene = load("res://models/cockpit_%s.glb" % stil)
	var cp: Node3D = ps.instantiate()
	akt.add_child(cp)
	# Rumpfsegment buendig hinter die Kanzel (genau wie der Editor es setzt)
	var fu := PartCatalog.build_visual(fd)
	fu.position = Vector3(0, 0, PartCatalog.col_size(cd).z * 0.5 + PartCatalog.col_size(fd).z * 0.5)
	akt.add_child(fu)
	var laenge: float = PartCatalog.col_size(cd).z + PartCatalog.col_size(fd).z
	var ctr := Vector3(0, 0, laenge * 0.5 - PartCatalog.col_size(cd).z * 0.5)
	cam.position = ctr + Vector3(-1.0, 0.52, -1.15).normalized() * laenge * 1.15
	cam.look_at(ctr, Vector3.UP)

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		root3 = Node3D.new()
		get_root().add_child(root3)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.13, 0.15, 0.18)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.55, 0.58, 0.64)
		e.ambient_light_energy = 0.9
		env.environment = e
		root3.add_child(env)
		var l := DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-40, 35, 0)
		l.light_energy = 1.7
		root3.add_child(l)
		cam = Camera3D.new()
		root3.add_child(cam)
		cam.current = true
		return false
	if f == 8:
		_zeige()
		return false
	if f > 8 and (f - 8) % 14 == 0:
		get_root().get_viewport().get_texture().get_image().save_png(
			"user://cp3d_%s.png" % teile[i])
		print("SHOT ", teile[i])
		i += 1
		if i >= teile.size():
			quit()
			return true
		_zeige()
	return false
