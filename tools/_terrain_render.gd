extends SceneTree
## ABNAHME-RENDER DER ECHTEN FLUGWELT.
##
## Frueher baute dieses Werkzeug eine EIGENE Welt nach: fester Seed, halber POI-Satz,
## eine tool-eigene 26-km-Wasserplatte, camera.far 7000 und keine Wolken. Es zeigte damit
## eine Welt, die es im Spiel nicht gibt — als Abnahme-Beleg wertlos.
##
## Jetzt wird scenes/Main.tscn instanziert und in den FLUG-Zustand geschaltet. Damit ist
## per Konstruktion alles drin, was der Spieler sieht: sein Seed aus dem Spielstand,
## alle Flugplaetze, Staedte, Inseln, Windpark, Schiffe, Wolken, das Wasser des Terrains
## und dieselbe Kamera-Fernebene (9 km).
##
## Godot --path . --script res://tools/_terrain_render.gd -- <out_prefix>

const VFOV := 64.0        # wie Main._setup_camera (ViewUtil, ultrawide-bewusst)
const CAM_FAR := 9000.0   # wie Main._setup_camera — NICHT 7000
const SHOT_W := 1280
const SHOT_H := 720

var prefix := "/tmp/map"
var vp: SubViewport
var main: Node3D
var cam: Camera3D
var terrain: TerrainWorld

var _started := false
var _finished := false
var _seen := {}          # md5 -> Shot-Name (Doppel-Erkennung)

# [Name, Kameraposition, Blickziel]
var _shots: Array = [
	["pan1", Vector3(700, 280, 200), Vector3(1700, 60, 1000)],           # Spawn -> Stadt/See/Berge
	["pan2", Vector3(3550, 360, 600), Vector3(2500, 90, 1450)],          # Blick aufs Bergmassiv
	["spawn", Vector3(0, 110, 420), Vector3(0, 8, -250)],                # ueber dem Flugfeld HEIMAT
	["grossstadt", Vector3(4300, 420, 4100), Vector3(4300, 60, 2500)],   # Skyline aus Sued
	["windpark", Vector3(-3900, 300, 900), Vector3(-3900, 40, -700)],    # Windpark + Weite
	["vulkan", Vector3(11800, 780, -4750), Vector3(11800, 120, -5600)],  # Vulkaninsel von Norden
	["canyon", Vector3(-6300, 120, 1300), Vector3(-4900, 20, 3100)],     # IN die Schlucht
	["canyon_hoch", Vector3(-5900, 620, 1600), Vector3(-4400, 0, 3900)], # Schlucht von oben
	# HOCHGEBIRGE im Nordwesten mit dem Bergflugplatz ADLERHORST auf dem Sattel.
	# Der Grat laeuft von (-9600,-4400) nach Suedosten; Kamera quer dazu, damit die
	# Kette als Kette zu sehen ist und nicht als einzelner Huegel.
	# HOCHTAL im Nordwesten: zwei Ketten bis 1250 m, dazwischen das Tal mit ADLERHORST.
	# Die Talachse laeuft von (-11000,-2500) mit Richtung (0.6139,-0.7893); der Platz liegt
	# bei 8800 m auf der Achse, also rund (-5598,-9446).
	["tal_anflug", Vector3(-8700, 420, -5400), Vector3(-5598, 90, -9446)],   # den Talgrund hinein
	["tal_platz", Vector3(-6900, 260, -8100), Vector3(-5598, 90, -9446)],    # kurz vor der Bahn
	["tal_oben", Vector3(-9600, 1750, -4800), Vector3(-5598, 90, -9446)],    # ueber dem Kamm
	["tal_quer", Vector3(-2400, 900, -8600), Vector3(-6600, 200, -8000)],    # Ketten von aussen
]


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()          # Koroutine — laeuft ueber viele Frames weiter
	return _finished


func _run() -> void:
	var ua := OS.get_cmdline_user_args()
	if ua.size() >= 1 and ua[0] != "":
		prefix = ua[0]

	_setup()
	# Main._ready() ist beim Einhaengen gelaufen; ein Frame Ruhe fuer Threads/Deferreds.
	await process_frame
	await process_frame
	_to_flight_state()

	print("SEED=", main.game.world_seed, "  far=", cam.far, "  fov=", cam.fov,
		"  Flugplaetze=", main.airfields.size(), "  POIs=", main._map_pois.size(),
		"  Wolken=", _count_clouds())

	var t0 := Time.get_ticks_msec()
	var nur: PackedStringArray = []
	for a in ua:
		if String(a).begins_with("nur="):
			nur = String(a).substr(4).split(",")
	for s in _shots:
		if nur.size() > 0 and not nur.has(String(s[0])):
			continue
		await _shoot(String(s[0]), s[1], s[2])
	print("Gesamt %.1f s fuer %d Shots" % [(Time.get_ticks_msec() - t0) / 1000.0, _shots.size()])

	_finished = true
	quit()


func _setup() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(SHOT_W, SHOT_H)
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)

	# DIE ECHTE SPIELSZENE. Kein Nachbau mehr.
	main = load("res://scenes/Main.tscn").instantiate()
	vp.add_child(main)
	terrain = main.terrain

	cam = Camera3D.new()
	cam.far = CAM_FAR
	vp.add_child(cam)
	ViewUtil.apply_vfov(cam, VFOV)     # 1280x720 = 16:9 -> vertikal 64 Grad wie im Spiel
	cam.current = true                 # verdraengt Main.camera


## Main startet im BAU-Modus (Blueprint-Raum, Showroom-Licht, Bau-UI). _set_mode(FLY)
## koennen wir nicht aufrufen — das baut ein Flugzeug, faengt die Maus und startet
## Survival-Wellen. Also genau die Sicht-Umschaltungen aus _set_mode nachziehen und
## danach `mode` auf FLY setzen, damit Mains _process nicht die Bau-Leiste synchronisiert.
func _to_flight_state() -> void:
	main.build_ctrl.set_active(false)
	main.build_ctrl.design_root.visible = false
	main.build_root.visible = false
	main.flight_root.visible = false          # HUD gehoert nicht auf ein Landschaftsbild
	main.world_env.environment = main.env_sky
	main.fly_world.visible = true
	if main.showroom != null:
		main.showroom.set_stage_visible(false)
	if main.sky_lights != null:
		main.sky_lights.visible = true
	main.camera.current = false
	cam.current = true
	main.mode = 1                              # Main.Mode.FLY
	_hide_overlays(main)


## Alles, was ueber der 3D-Welt liegt (Bau-UI, HUD, Vignette, Modus-Dialog), abschalten.
func _hide_overlays(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer:
			c.visible = false
		_hide_overlays(c)


func _count_clouds() -> int:
	var cf: Node = main.fly_world.find_child("CloudField", false, false)
	return 0 if cf == null else cf.get_child_count()


func _shoot(name: String, pos: Vector3, target: Vector3) -> void:
	# Erneut, nicht nur einmal beim Aufbau: Main haengt die Karte erst ein, wenn der
	# Hintergrund-Thread ihr Bild geliefert hat — die CanvasLayer entsteht also spaeter.
	_hide_overlays(main)
	cam.look_at_from_position(pos, target, Vector3.UP)
	# Die Welt so hinstellen, wie sie fuer einen Spieler AN DIESER STELLE aussieht:
	# update_center schiebt die Wasserplatte des Terrains mit und wirft Chunks jenseits
	# von VIEW_DIST weg (echte Weltkante!), build_now_around fuellt den Rest SYNCHRON,
	# damit nichts halb geladen ins Bild kommt.
	var t0 := Time.get_ticks_msec()
	terrain.update_center(pos)
	terrain.build_now_around(pos, TerrainWorld.VIEW_DIST, false)
	var build_ms := Time.get_ticks_msec() - t0
	await process_frame

	var path := "%s_%s.png" % [prefix, name]
	var sum := ""
	# Bis zu 8 Versuche: get_image() liefert nur NACH frame_post_draw den frisch
	# gezeichneten Inhalt. Fehlte dieses await, kam unter GPU-Last der vorige Frame
	# zurueck — daher die frueher mehrfach identischen PNGs. Der Doppel-Check haelt
	# das dauerhaft ehrlich, statt sich auf "zwei Frames warten reicht schon" zu verlassen.
	for versuch in 8:
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(path)
		sum = FileAccess.get_md5(path)
		if not _seen.has(sum):
			break
		print("  ! %s gleicht noch %s (md5 %s) — Versuch %d" % [name, _seen[sum], sum, versuch + 1])

	if _seen.has(sum):
		push_warning("Shot %s ist IDENTISCH mit %s" % [name, _seen[sum]])
		print("FEHLER: %s == %s (md5 %s)" % [name, _seen[sum], sum])
	else:
		_seen[sum] = name
	print("Render -> %s   md5=%s  chunks=%d  h=%.1f  build=%d ms"
		% [path, sum, terrain.get_child_count(), terrain.height_at(pos.x, pos.z), build_ms])
