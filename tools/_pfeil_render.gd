## Sichtprobe fuer die Bewegen-Pfeile: baut ein Teil, waehlt es aus, schaltet auf
## Bewegen und rendert das Gizmo zusammen mit der Debug-Box (die Pfeile sollen an
## deren Flaechen ansetzen, nicht in der Luft haengen).
extends SceneTree
var f := 0
var i := 0
var teile := ["wing_straight", "aileron", "fuselage_c130_long"]
var bc: BuildController
var cam: Camera3D
var welt: Node3D


func _zeige() -> void:
	bc.load_design([
		{"id": "cockpit", "xform": Transform3D(), "root": true},
		{"id": String(teile[i]), "xform": Transform3D(Basis(), Vector3(0, 0, 3.4))},
	])
	var teil: Node3D = null
	for c in bc.design_root.get_children():
		if String(c.get_meta("part_id", "")) == String(teile[i]):
			teil = c
	if teil == null:
		return
	bc.set_debug_boxes(true)
	bc._select_part(teil)
	bc.set_gizmo_mode(bc.GIZ_MOVE)
	var wab: AABB = bc._part_world_aabb(teil)
	var r: float = maxf(wab.size.length() * 0.5, 0.8) + 1.4
	var mitte: Vector3 = wab.get_center()
	cam.look_at_from_position(mitte + Vector3(-0.9, 0.72, -1.0).normalized() * r * 2.2,
		mitte, Vector3.UP)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		welt = Node3D.new()
		get_root().add_child(welt)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.07, 0.10, 0.15)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.6, 0.66, 0.78)
		e.ambient_light_energy = 1.5
		env.environment = e
		welt.add_child(env)
		var l := DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-42, 32, 0)
		l.light_energy = 2.2
		welt.add_child(l)
		cam = Camera3D.new()
		welt.add_child(cam)
		cam.current = true
		bc = BuildController.new()
		bc.symmetry = false
		welt.add_child(bc)
		bc.camera = cam
		return false
	if f == 12:
		_zeige()
		return false
	if f > 12 and (f - 12) % 16 == 0:
		get_root().get_viewport().get_texture().get_image().save_png(
			"user://pfeil_%s.png" % teile[i])
		print("SHOT ", teile[i])
		i += 1
		if i >= teile.size():
			quit()
			return true
		_zeige()
	return false
