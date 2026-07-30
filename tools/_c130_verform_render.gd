## Rendert den C-130-Ring in Ruhe, verjuengt und versetzt — Sichtprobe fuer die
## Verformung des importierten Modells (vor allem: stimmt die Beleuchtung noch?).
extends SceneTree
var f := 0
var i := 0
var faelle := [
	["ruhe", 1.0, Vector2.ZERO],
	["verjuengt", 0.45, Vector2.ZERO],
	["versetzt", 1.0, Vector2(0.0, 0.35)],
]
var root3: Node3D
var cam: Camera3D
var akt: Node3D


func _zeige() -> void:
	if akt != null:
		akt.queue_free()
	var p := PartCatalog.get_part("fuselage_c130_long")
	var tf: float = faelle[i][1]
	var sv: Vector2 = faelle[i][2]
	akt = PartCatalog.build_visual(p, Color(0, 0, 0, 0), 1.0, tf, -1.0, -1.0, sv, Vector2.ZERO)
	root3.add_child(akt)
	var ab := AABB()
	var erst := true
	for n in akt.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		var w: AABB = vi.global_transform * vi.get_aabb()
		ab = w if erst else ab.merge(w)
		erst = false
	var mitte: Vector3 = ab.get_center()
	var r: float = maxf(ab.size.length() * 0.5, 0.05)
	cam.position = mitte + Vector3(-1.0, 0.42, -0.85).normalized() \
		* (r / tan(deg_to_rad(cam.fov * 0.5)) * 1.15)
	cam.look_at(mitte, Vector3.UP)


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
		e.ambient_light_energy = 1.4
		env.environment = e
		root3.add_child(env)
		var l := DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-38, 30, 0)
		l.light_energy = 2.8
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
		var cw: int = mini(1700, vs.x)
		var ch: int = mini(1150, vs.y)
		img.get_region(Rect2i((vs.x - cw) / 2, (vs.y - ch) / 2, cw, ch)).save_png(
			"user://c130_%s.png" % faelle[i][0])
		print("SHOT ", faelle[i][0])
		i += 1
		if i >= faelle.size():
			quit()
			return true
		_zeige()
	return false
