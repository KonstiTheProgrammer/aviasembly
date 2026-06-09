## Offscreen-Render eines Designs mit den ECHTEN PartCatalog-Meshes in einen
## SubViewport (rendert unter Metal korrekt, anders als der Hauptfenster-Grab) und
## speichert ein PNG. So lässt sich ein Flugzeug ohne Sicht aufs Spiel verifizieren.
##
## Godot --path . --script res://tools/snap_render.gd -- <design.json|id> <out.png> <angle>
##   angle: 34 | 34b | front | back | side | top   (Default 34)
extends SceneTree

var frame := 0
var vp: SubViewport
var out_path := "/Users/konstantinkanzler/Downloads/aviasembly/tools/render_out.png"
var design_path := "res://designs/fokker_dr1.json"
var angle := "34"

func _process(_d: float) -> bool:
	frame += 1
	if frame == 2:
		_setup()
	if frame >= 12:
		_capture()
		quit()
		return true
	return false

func _args() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() >= 1 and ua[0] != "":
		var a0 := ua[0]
		if a0.ends_with(".json"):
			design_path = a0 if a0.begins_with("res://") or a0.begins_with("/") else "res://designs/" + a0
		else:
			design_path = "res://designs/%s.json" % a0
	if ua.size() >= 2 and ua[1] != "":
		out_path = ua[1]
	if ua.size() >= 3 and ua[2] != "":
		angle = ua[2]

func _setup() -> void:
	_args()
	var f := FileAccess.open(design_path, FileAccess.READ)
	if f == null:
		print("FEHLER: kann ", design_path, " nicht lesen"); quit(); return
	var arr = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(arr) != TYPE_ARRAY:
		print("FEHLER: ungueltiges Design"); quit(); return

	vp = SubViewport.new()
	vp.size = Vector2i(1200, 760)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var env := Environment.new()
	# Spiegelnder Gradient-Himmel als Reflexions-/Ambient-Quelle (wie im Hangar) — damit
	# Metall-Reflexe (z. B. der Einlauf-Ring) im Render SICHTBAR sind und prüfbar werden.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.40, 0.66)
	sky_mat.sky_horizon_color = Color(0.78, 0.85, 0.97)
	sky_mat.ground_horizon_color = Color(0.62, 0.66, 0.72)
	sky_mat.ground_bottom_color = Color(0.34, 0.37, 0.42)
	var sky := Sky.new(); sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.50, 0.55, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -42, 0)
	key.light_energy = 1.5
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(16, 132, 0)
	fill.light_energy = 0.55
	vp.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(8, 20, 0)
	rim.light_energy = 0.4
	vp.add_child(rim)

	var holder := Node3D.new()
	vp.add_child(holder)
	var acc := {"box": AABB(), "has": false}
	for item in arr:
		var id: String = item.get("id", "")
		if not PartCatalog.has(id):
			continue
		var p := PartCatalog.get_part(id)
		var xf := _xf(item.get("xform", []))
		var col := _col(item.get("color", []))
		var sc := _vec(item.get("scale", []), Vector3.ONE)
		var tp: float = _num(item, "taper", -1.0); if tp < 0.0: tp = float(p.get("taper", 1.0))
		var tpf: float = _num(item, "taper_front", -1.0); if tpf < 0.0: tpf = float(p.get("taper_front", 1.0))
		var tpy: float = _num(item, "taper_y", -1.0); if tpy < 0.0: tpy = tp
		var tpfy: float = _num(item, "taper_front_y", -1.0); if tpfy < 0.0: tpfy = tpf
		var vis := PartCatalog.build_visual(p, col, tp, tpf, tpy, tpfy)
		vis.scale = sc
		var part := Node3D.new()
		part.transform = xf
		part.add_child(vis)
		holder.add_child(part)
		_accum(part, Transform3D.IDENTITY, acc)

	var box: AABB = acc["box"] if acc["has"] else AABB(Vector3(-3, -2, -3), Vector3(6, 4, 6))
	var center: Vector3 = box.get_center()
	var radius: float = maxf(box.size.length() * 0.5, 1.0)
	var cam := Camera3D.new()
	cam.fov = 40.0
	var dist: float = radius / tan(deg_to_rad(cam.fov * 0.5)) * 1.04
	var dir: Vector3 = _dir(angle)
	cam.look_at_from_position(center + dir * dist, center, Vector3.UP)
	cam.current = true
	vp.add_child(cam)
	print("Geladen: ", design_path, "  Teile-AABB=", box)

func _dir(a: String) -> Vector3:
	match a:
		"front": return Vector3(0, 0.18, -1).normalized()
		"back":  return Vector3(0, 0.18, 1).normalized()
		"side":  return Vector3(1, 0.12, 0.02).normalized()
		"top":   return Vector3(0.001, 1, 0.001).normalized()
		"34b":   return Vector3(-0.85, 0.5, -1).normalized()
		_:       return Vector3(0.85, 0.5, -1).normalized()

func _capture() -> void:
	if vp == null:
		return
	RenderingServer.force_draw(false)
	var img := vp.get_texture().get_image()
	if img == null:
		print("FEHLER: kein Bild"); return
	var err := img.save_png(out_path)
	print("Render gespeichert -> ", out_path, "  (err=", err, ")")

# ---- Helfer ----
func _num(d: Dictionary, k: String, def: float) -> float:
	return float(d[k]) if d.has(k) else def

func _xf(a) -> Transform3D:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 12:
		return Transform3D()
	return Transform3D(
		Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])),
		Vector3(a[9], a[10], a[11]))

func _col(a) -> Color:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 4:
		return Color(0, 0, 0, 0)
	return Color(a[0], a[1], a[2], a[3])

func _vec(a, def := Vector3.ZERO) -> Vector3:
	if typeof(a) != TYPE_ARRAY or (a as Array).size() < 3:
		return def
	return Vector3(a[0], a[1], a[2])

func _accum(node: Node, xf: Transform3D, acc: Dictionary) -> void:
	var t := xf
	if node is Node3D:
		t = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var b: AABB = t * (node as MeshInstance3D).mesh.get_aabb()
		acc["box"] = (acc["box"] as AABB).merge(b) if acc["has"] else b
		acc["has"] = true
	for ch in node.get_children():
		_accum(ch, t, acc)
