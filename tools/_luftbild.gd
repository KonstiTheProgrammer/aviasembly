## LUFTBILDER DER WELT an frei gewaehlten Stellen — im echten Spielbild (Chunks, Baeume,
## Fernschuerze, Wasser, Himmel). Zum Beurteilen neuer Regionen und Biome.
##
##   HOME=/tmp/avi_home Godot --path . --script res://tools/_luftbild.gd -- \
##       name px py pz zx zy zz  [name px py pz zx zy zz ...]
## p = Kameraposition, z = Blickziel (Welt). Bilder: user://luft_<name>.png
## Wartet auf die grobe Fernschuerze, damit der Horizont nicht leer ist, und baut die
## Chunks um jede Kamera synchron. Das Flugzeug wandert mit (sonst verwirft der Chunk-
## Worker alles jenseits VIEW_DIST um das Flugzeug, siehe _city_render).
extends SceneTree
var f := 0
var m: Node
var cam: Camera3D
var shots: Array = []
var i := 0
var t0 := 0
var warte := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var k := 0
	while k + 6 < a.size():
		shots.append([a[k], Vector3(float(a[k + 1]), float(a[k + 2]), float(a[k + 3])),
			Vector3(float(a[k + 4]), float(a[k + 5]), float(a[k + 6]))])
		k += 7


func _hin() -> void:
	var p: Vector3 = shots[i][1]
	var ziel: Vector3 = shots[i][2]
	# LUFT_REL=1: y-Werte sind Hoehen UEBER DEM BODEN (sonst steht die Kamera leicht im
	# Berg und man sieht das Gelaende von unten).
	if OS.get_environment("LUFT_REL") != "":
		p.y += maxf(m.terrain.height_at(p.x, p.z), TerrainWorld.SEA_Y)
		ziel.y += maxf(m.terrain.height_at(ziel.x, ziel.z), TerrainWorld.SEA_Y)
	var ac = m.flight_ctrl.aircraft
	if is_instance_valid(ac):
		ac.global_position = p + Vector3(0, 30, 0)
		ac.linear_velocity = Vector3.ZERO
		ac.freeze = true
	var boden := Vector3(p.x, 0, p.z).lerp(Vector3(ziel.x, 0, ziel.z), 0.35)
	m.terrain.build_now_around(boden, 2600.0)
	cam.look_at_from_position(p, ziel, Vector3.UP)
	# Dunst wie im Flug in dieser Hoehe (Main._wolken_aufenthalt folgt der Spielkamera,
	# nicht dieser)
	var env: Environment = m.get("env_sky")
	if env != null:
		env.fog_density = m.nebel_frei_bei(p.y)
		m.terrain.setze_dunst(env.fog_density, env.fog_light_color)


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		get_root().add_child(m)
		return false
	if f == 20:
		m._set_mode(1)
		cam = Camera3D.new()
		cam.far = float(OS.get_environment("LUFT_FAR")) if OS.get_environment("LUFT_FAR") != "" else 9000.0   # = Main.KAMERA_FERN, wie im Spiel
		cam.fov = 62.0
		m.fly_world.add_child(cam)
		return false
	if f == 25:
		cam.current = true
		if OS.get_environment("LUFT_OHNE_STELLV") != "":
			m.terrain.set("_flora_grob_ab", 99999.0)
		# Freie Sicht: Wolken und HUD aus (die Bilder sollen die Landschaft zeigen)
		for c in m.get("cloud_fields"):
			(c as Node3D).visible = false
		for c in m.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		return false
	if f > 25 and t0 == 0:
		# erst die grobe Fernschuerze abwarten (hoechstens ~90 s)
		warte += 1
		if m.get("_fern_stufe_knoten") != null or warte > 5400:
			if shots.is_empty():
				print("KEINE SHOTS")
				quit()
				return true
			t0 = f
			_hin()
		return false
	# Nach dem Umsetzen warten, bis die Fernschuerze um die neue Stelle steht (sie streamt
	# mit dem Flugzeug, siehe Main._fern_pruefen) — hoechstens 40 s.
	if t0 > 0 and f - t0 >= 90 and f - t0 < 9000 and not m.call("fern_bereit", shots[i][1]):
		return false
	# ... und bis die Baeume eingehaengt sind (hoechstens zwei Chunks je Frame, siehe
	# TerrainWorld.FLORA_PRO_FRAME) — sonst fehlen ganze Chunkreihen als Streifen im Wald.
	if t0 > 0 and f - t0 >= 90 and f - t0 < 9000 \
			and (not (m.terrain.get("_flora_warteschlange") as Array).is_empty()
				or not (m.terrain.get("_pending") as Dictionary).is_empty()
				or not (m.terrain.get("_done") as Array).is_empty()):
		return false
	if t0 > 0 and f - t0 >= 90:
		if OS.get_environment("LUFT_OHNE_FERN") != "" and m.fern_root != null:
			m.fern_root.visible = false
		if OS.get_environment("LUFT_AABB") != "":
			var n := 0
			for mmi in m.terrain.find_children("*", "MultiMeshInstance3D", true, false):
				var mm := (mmi as MultiMeshInstance3D).multimesh
				if mm != null and n < 6:
					print("AABB mmi ", mmi.get_aabb(), " mesh ", mm.mesh.get_aabb().size, " n ", mm.instance_count)
					n += 1
				(mmi as MultiMeshInstance3D).custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 2000, 10000))
		if OS.get_environment("LUFT_OHNE_SCHATTEN") != "":
			for l in m.find_children("*", "DirectionalLight3D", true, false):
				(l as DirectionalLight3D).shadow_enabled = false
		var name := String(shots[i][0])
		get_root().get_viewport().get_texture().get_image().save_png("user://luft_%s.png" % name)
		print("LUFTBILD ", name)
		i += 1
		if i >= shots.size():
			quit()
			return true
		t0 = f
		_hin()
	return false
