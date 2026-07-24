extends SceneTree
## Schneller Luftbild-QA-Render nur fuer die Landmark-Gebaeude.
## Braucht den Vulkan-Renderer, also OHNE --headless starten:
## Godot --path . --script res://tools/_buildings_render.gd -- <out_prefix>

var vp: SubViewport
var cam: Camera3D
var prefix := "C:/Users/Konst/AppData/Local/Temp/buildings"
var frame := 0
var shot := -1
var settle := 0
var shots := [
	["stadt_250m", Vector3(205, 205, 250), Vector3(0, 7, 0)],
	["stadt_500m", Vector3(-360, 410, 430), Vector3(0, 5, 0)],
	["bergdorf_220m", Vector3(545, 190, 185), Vector3(420, 7, 0)],
]


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		var args := OS.get_cmdline_user_args()
		if not args.is_empty() and args[0] != "":
			prefix = args[0]
		_setup()
		return false
	if frame < 3:
		return false
	if settle > 0:
		settle -= 1
		if settle == 0:
			var data: Array = shots[shot]
			var path := "%s_%s.png" % [prefix, data[0]]
			vp.get_texture().get_image().save_png(path)
			print("Render -> ", path)
		return false
	shot += 1
	if shot >= shots.size():
		quit()
		return true
	var data: Array = shots[shot]
	cam.look_at_from_position(data[1], data[2], Vector3.UP)
	settle = 4
	return false


func _setup() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(1280, 800)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.33, 0.53, 0.74)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.76, 0.90)
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 900.0
	world.add_child(sun)

	_ground(world, Vector3.ZERO, Vector2(330, 330), Color(0.29, 0.43, 0.22))
	_ground(world, Vector3(420, 0, 0), Vector2(190, 190), Color(0.33, 0.41, 0.24))
	Landmarks.build_town(world, Vector3.ZERO)
	Landmarks.build_village(world, Vector3(420, 0, 0))

	cam = Camera3D.new()
	cam.fov = 58.0
	cam.far = 1800.0
	cam.current = true
	vp.add_child(cam)


func _ground(parent: Node3D, pos: Vector3, size: Vector2, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mi.mesh = plane
	mi.position = pos + Vector3(0, -0.06, 0)
	mi.material_override = Landmarks._mat(color, 0.96)
	parent.add_child(mi)
