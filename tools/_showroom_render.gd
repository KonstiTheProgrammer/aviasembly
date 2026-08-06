## Sichtpruefung der Praesentations-Buehne (ShowroomStage) mit einem echten Design.
##
##   /opt/homebrew/bin/godot --script tools/_showroom_render.gd -- <design> <out.png> [breite hoehe] [konturIdx] [schalter...]
##
## DIAGNOSE-SCHALTER (einzeln zuschaltbar, um Bildfehler einzukreisen):
##   nofarbe   gespeicherte Lackierung ignorieren -> zeigt die KATALOG-Palette
##   noshadow  Schatten des Key-Lights aus
##   nossao    SSAO aus
##   nahplan   Kamera-Nahebene anheben (mehr Tiefenpraezision)
## Genau diese drei haben ein feines Punktmuster auf Streben und Klappen als
## SCHATTEN-AKNE entlarvt — es sah aus wie Z-Fighting, verschwand aber weder mit
## angehobener Nahebene noch ohne SSAO, sondern erst ohne Schatten.
##
## Baut dieselbe Buehne wie der Bau-Modus (Environment, Drei-Punkt-Licht, Blueprint-
## Boden, Vignette) und stellt das Flugzeug mit DEN GLEICHEN Kamerawerten davor wie
## BuildController.reset_camera — dadurch entspricht der Screenshot dem, was der
## Spieler im Editor sieht.
##
## Warum nicht einfach die Hauptszene laden: Main.gd baut beim Start Terrain, Stadt,
## Wolken und einen Karten-Thread auf. Das dauert und ist fuer die Beurteilung der
## Art Direction voellig unnoetig.
extends SceneTree

var frame := 0
var vp: SubViewport
var design_path := "res://designs/mustang_p51.json"
var out_path := "/tmp/showroom.png"
var breite := 1600
var hoehe := 900
var kontur_idx := -1
# Gespeicherte Lackierung ignorieren -> zeigt die KATALOG-Palette.
var ohne_farbe := false


func _process(_d: float) -> bool:
	frame += 1
	if frame == 2:
		_setup()
	# Vorlauf, damit Schattenkarte, SSAO und Glow eingeschwungen sind.
	if frame >= 30:
		_capture()
		quit()
		return true
	return false


func _args() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1 and a[0] != "":
		design_path = a[0] if a[0].begins_with("res://") else "res://designs/%s.json" % a[0]
	if a.size() >= 2 and a[1] != "":
		out_path = a[1]
	if a.size() >= 4:
		breite = int(a[2])
		hoehe = int(a[3])
	if a.size() >= 5:
		kontur_idx = int(a[4])
	if a.size() >= 6 and a[5] == "nofarbe":
		ohne_farbe = true


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
	vp.size = Vector2i(breite, hoehe)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	# DIE BUEHNE — identisch zu der, die Main.gd im Bau-Modus benutzt.
	var buehne := ShowroomStage.new()
	vp.add_child(buehne)
	buehne.set_stage_visible(true)
	if OS.get_cmdline_user_args().has("noshadow"):
		buehne.key_light.shadow_enabled = false
	if OS.get_cmdline_user_args().has("nossao"):
		buehne.environment.ssao_enabled = false
	var we := WorldEnvironment.new()
	we.environment = buehne.environment
	vp.add_child(we)

	var holder := Node3D.new()
	vp.add_child(holder)
	var acc := {"box": AABB(), "has": false}
	var teile: Array = []
	for item in arr:
		var id: String = item.get("id", "")
		if not PartCatalog.has(id):
			continue
		var p := PartCatalog.get_part(id)
		var farbe := Color(0, 0, 0, 0) if ohne_farbe else _col(item.get("color", []))
		var vis := PartCatalog.build_visual(p, farbe)
		vis.scale = _vec(item.get("scale", []), Vector3.ONE)
		var part := Node3D.new()
		part.transform = _xf(item.get("xform", []))
		part.add_child(vis)
		holder.add_child(part)
		_accum(part, Transform3D.IDENTITY, acc)
		teile.append(vis)

	var box: AABB = acc["box"] if acc["has"] else AABB(Vector3(-3, -2, -3), Vector3(6, 4, 6))

	# Optional: Auswahlkontur an EINEM Teil zeigen (Argument 5 = Teil-Index).
	if kontur_idx >= 0 and kontur_idx < teile.size():
		var km := ShaderMaterial.new()
		km.shader = load("res://shaders/selection_outline.gdshader")
		km.set_shader_parameter("kontur_farbe", Color(ShowroomStage.KONTUR, 1.0))
		km.set_shader_parameter("pixel", 3.0)
		km.set_shader_parameter("staerke", 0.85)
		_kontur_an(teile[kontur_idx], km)

	# --- Kamera: exakt die Werte aus BuildController.reset_camera ---
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.fov = BuildController.PRAESENT_VFOV
	var aspect := float(breite) / float(hoehe)
	var vfov := deg_to_rad(cam.fov)
	var yaw := deg_to_rad(30.0)
	var pitch := deg_to_rad(12.0)
	var fokus: Vector3 = box.get_center() + Vector3(0, box.size.y * 0.18, 0)
	var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
	var dist: float = clamp(ViewUtil.fit_distance(box, vfov, aspect, dir,
		BuildController.PRAESENT_FUELLUNG, 0.78), 3.0, 90.0)
	# ERST in den Baum, DANN positionieren: global_transform gibt es ausserhalb des
	# Baums nicht, die Kamera waere sonst im Ursprung stehen geblieben.
	# Test: Nahebene anheben -> mehr Tiefenpraezision. Wenn das Punktmuster damit
	# verschwindet, sind die Flaechen wirklich koinzident (Geometrie), sonst nicht.
	if OS.get_cmdline_user_args().has("nahplan"):
		cam.near = 0.6
	cam.current = true
	vp.add_child(cam)
	# Modell nach links ruecken (Platz fuer Name/Kennwerte rechts)
	var breite_welt: float = 2.0 * dist * tan(vfov * 0.5) * aspect
	var ziel: Vector3 = fokus + Vector3.UP.cross(dir).normalized() * breite_welt * 0.11
	cam.look_at_from_position(fokus + dir * dist, ziel, Vector3.UP)
	print("Design: ", design_path, "  AABB=", box, "  Abstand=", "%.2f" % dist)


func _capture() -> void:
	RenderingServer.force_draw(false)
	var img := vp.get_texture().get_image()
	if img == null:
		print("FEHLER: kein Bild"); return
	img.save_png(out_path)
	print("SHOWROOM ", out_path, " ", img.get_width(), "x", img.get_height())


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
		var bb: AABB = t * (node as MeshInstance3D).mesh.get_aabb()
		acc["box"] = (acc["box"] as AABB).merge(bb) if acc["has"] else bb
		acc["has"] = true
	for ch in node.get_children():
		_accum(ch, t, acc)


func _kontur_an(node: Node, mat: ShaderMaterial) -> void:
	for ch in node.get_children():
		_kontur_an(ch, mat)
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var ov := MeshInstance3D.new()
		ov.mesh = (node as MeshInstance3D).mesh
		ov.material_override = mat
		ov.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(ov)
