## Rendert beliebige TEILE (prozedural oder glb) ueber PartCatalog.build_visual.
extends SceneTree
var f := 0
var i := 0
var teile := ["canopy_bean", "jet_cockpit"]
var root3: Node3D
var cam: Camera3D
var akt: Node3D

func _zeige() -> void:
	if akt != null:
		akt.queue_free()
	var p := PartCatalog.get_part(String(teile[i]))
	akt = PartCatalog.build_visual(p)
	root3.add_child(akt)
	var sz: Vector3 = p.get("size", Vector3.ONE)
	var r: float = sz.length() * 0.5
	cam.position = Vector3(-1.0, 0.40, -1.05).normalized() * (r / tan(deg_to_rad(cam.fov * 0.5)) * 1.25)
	cam.look_at(Vector3.ZERO, Vector3.UP)

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
		var img := get_root().get_viewport().get_texture().get_image()
		var vs := img.get_size()
		var cw: int = mini(1900, vs.x)
		var ch: int = mini(1300, vs.y)
		img.get_region(Rect2i((vs.x - cw) / 2, (vs.y - ch) / 2, cw, ch)).save_png(
			"user://part_%s.png" % teile[i])
		print("SHOT ", teile[i])
		i += 1
		if i >= teile.size():
			quit()
			return true
		_zeige()
	return false
