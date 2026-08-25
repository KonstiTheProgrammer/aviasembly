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
	# Vulkaninsel von Norden. SIE STAND BEI (11800, 780, -4750) UND DAMIT IM BERG: das sind
	# 850 m vom Mittelpunkt, und dort steht die Flanke seit der Vergroesserung auf 840 m —
	# die Kamera sass 60 m unter der Gelaendeoberflaeche und das Bild war schwarz.
	# 1290 m vom Mittelpunkt und 1470 m hoch ist dieselbe Stellung IN ANTEILEN des Kegels,
	# die sie vorher hatte (0.68 * r und 1.3 * Gipfelhoehe).
	["vulkan", Vector3(11800, 1470, -4310), Vector3(11800, 300, -5600)],
	# VULKAN IM BLICKWINKEL DER REFERENZ: flach schraeg von oben aus rund 3,5 km, sodass der
	# Kegel das Bild fuellt und der Horizont mit Land und Meer dahinter stehenbleibt. Die
	# Kamera steht bewusst WEIT genug, dass sie fuer Gipfel zwischen 200 und 900 m taugt —
	# waehrend eines Umbaus aendert sich die Hoehe staendig, und ein Bild, dessen Ausschnitt
	# mitwandert, taugt nicht zum Vergleich zweier Staende.
	["vulkan_ref", Vector3(11800, 1500, -2100), Vector3(11800, 330, -5600)],
	# In den Krater hinein (Rand, Schuessel, Lavasee).
	# SIE IST MITGEWACHSEN, ALS DER KEGEL WUCHS, und das war keine Kosmetik: aus der alten
	# Stellung (1450 m hoch, 1150 m vom Mittelpunkt) verlief die Sichtlinie zur Seemitte am
	# NAHEN Kraterrand nur noch 13 m ueber der Lippe. Bei 620 m Kraterradius und einer Lippe
	# auf rund 1080 m haette der Rand die halbe Schuessel verdeckt — und eine Abnahme, die
	# den Krater auf einem solchen Bild beurteilt, meldet dasselbe wie schon einmal die
	# Dampffahne: "kein Krater vorhanden".
	# 2150 m hoch und 1500 m vom Mittelpunkt raeumt 207 m ueber der Lippe. Wer den Kegel
	# noch einmal vergroessert, muss das nachrechnen: die Sichtlinie muss bei md = crater_r
	# ueber peak + apron + rand_h liegen.
	["vulkan_krater", Vector3(11800, 2150, -4100), Vector3(11800, 620, -5600)],
	# Der Bergfuss: hier muss die Baumgrenze schlagartig anfangen.
	# SIE IST NACH AUSSEN GEWANDERT, WEIL DIE BAUMGRENZE ES IST. Sie ist eine HOEHENLINIE
	# (44 bis 68 m), und seit unter dem Kegel die Ascheschuerze liegt, schneidet diese Hoehe
	# das Gelaende nicht mehr bei 1200 m vom Mittelpunkt, sondern bei rund 2400 bis 2600.
	# Aus 3450 heraus stand die Kamera mitten auf dem Aschefaecher, und im Bild war nichts
	# als Schutt im Vordergrund — vom Waldrand, den dieser Shot pruefen soll, kein Halm.
	# 2300 legt die Kamera vor den Faechersaum und den Waldsaum in die Bildmitte.
	["vulkan_fuss", Vector3(11800, 120, -2300), Vector3(11800, 300, -5600)],
	# IN DIE SCHLUCHT. Sie stand bei (-6300, 120, 1300) und damit IM HANG: seit das
	# Talband des Flusses von 260 auf 110 m verengt und die sechs Flankenmassive auf
	# 225 bis 280 m gehoben wurden, steht dort Fels — gemessen 180 m bei (-6100, 1100).
	# Vorher war das eine Wiese, weil der Flussschnitt einen Viertelkilometer links und
	# rechts flachgelegt hat. Die neue Stellung liegt AUF der Flusslinie, 35 m ueber dem
	# Wasser des ersten Stuetzpunkts, und blickt die Schlucht hinunter.
	["canyon", Vector3(-6600, 81, 900), Vector3(-5250, 22, 2800)],
	["canyon_hoch", Vector3(-5900, 620, 1600), Vector3(-4400, 0, 3900)], # Schlucht von oben
	# FELSENBASIS ADLERHORST — jetzt der KAVERNENFLUGPLATZ am Talschluss. Das Portal
	# steht bei (-5285, 90.7, -9848) auf der Bahnachse (Talstation 9310); die Achse in den
	# Berg ist +TAL_RICHTUNG (0.6139, -0.7893), heraus (-0.6139, 0.7893).
	# DIE ALTEN basis_-STELLUNGEN ZEIGTEN AUF DIE SEITENWAND und sind mit dem Umzug
	# wertlos geworden — die Namen bleiben, damit Werkzeuge und Fortschrittsseite weiter
	# funktionieren, aber Vergleiche ueber den Umzug hinweg sind nicht zulaessig.
	# anflug = Blickwinkel der Vorlage: tief auf der Achse, kurz vor der Schwelle.
	["basis_anflug", Vector3(-5456, 116, -9627), Vector3(-5285, 128, -9848)],
	["basis_fern", Vector3(-5714, 230, -9296), Vector3(-5285, 150, -9848)],
	["basis_halle", Vector3(-5187, 106, -9975), Vector3(-4965, 95, -10259)],
	["basis_zurueck", Vector3(-5021, 112, -10188), Vector3(-5285, 108, -9848)],
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
	# Felsentor bei Talachse 3600 -> rund (-8790,-5341); Bergsee bei 5000 -> (-7930,-6447).
	["tal_tor", Vector3(-9900, 190, -3900), Vector3(-8790, 120, -5341)],     # aufs Tor zu
	["tal_tor_nah", Vector3(-9250, 150, -4650), Vector3(-8500, 130, -5700)], # kurz davor
	["tal_see", Vector3(-8800, 320, -5600), Vector3(-7930, 78, -6447)],      # Bergsee
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
	# FREIE KAMERA: frei=x,y,z,zx,zy,zz macht GENAU EIN Bild aus dieser Stellung und
	# ueberspringt die Tabelle. Wer einen Umbau beurteilt, braucht andere Blickwinkel als
	# die, die beim Anlegen der Tabelle sinnvoll schienen — ohne diesen Schalter muesste er
	# dafuer das Werkzeug aendern, und zwei Leute, die das gleichzeitig tun, ueberschreiben
	# sich gegenseitig die Vergleichsbilder.
	for a in ua:
		if String(a).begins_with("frei="):
			var f := String(a).substr(5).split(",")
			if f.size() < 6:
				push_error("frei= braucht sechs Zahlen: x,y,z,zx,zy,zz")
				_finished = true
				quit(1)
				return
			await _shoot("frei",
				Vector3(float(f[0]), float(f[1]), float(f[2])),
				Vector3(float(f[3]), float(f[4]), float(f[5])))
			print("Freies Bild fertig")
			_finished = true
			quit()
			return
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
	# ohne_schuerze: Fernschuerze ausblenden, um zu entscheiden, ob ein Artefakt aus ihr
	# kommt oder aus den Chunks. MUSS HIER STEHEN, nicht beim Start: die Schuerze entsteht
	# auf einem Thread und wird per call_deferred eingehaengt — beim Start ist fern_root
	# noch leer, und ein Schalter dort bleibt wirkungslos (genau darauf bin ich
	# hereingefallen: beide Vergleichsbilder waren identisch).
	var schalter := OS.get_cmdline_user_args()
	if schalter.has("ohne_schuerze") and main.fern_root != null:
		main.fern_root.visible = false
	# Weitere Verdaechtige einzeln abschaltbar: horizontale Ebenen, die das Gelaende
	# durchdringen koennen (Wasserplatte des Terrains, Wolkendecke, Seen/Fluesse).
	if schalter.has("ohne_wasser"):
		for n in terrain.get_children():
			if n is MeshInstance3D:
				(n as MeshInstance3D).visible = false
	if schalter.has("ohne_wolken"):
		for n in main.fly_world.get_children():
			if String(n.name).begins_with("Cloud") or String(n.name).begins_with("Wolken"):
				(n as Node3D).visible = false
	# ohne_fahne: die Dampffahne des Vulkans ausblenden. SIE FAELLT NICHT UNTER ohne_wolken,
	# obwohl sie aus denselben Puffs besteht — und das ist Absicht, denn sie gehoert zum Berg
	# und nicht zum Wetter.
	# WOFUER DER SCHALTER DA IST: die Fahne steht senkrecht ueber dem Krater und verdeckt ihn
	# aus jeder Kamera, die von oben hineinschaut. Eine Bewertung der KRATERFORM anhand eines
	# solchen Bildes ist wertlos — genau darauf ist eine Abnahme schon hereingefallen und hat
	# einen vorhandenen, vermessenen Krater als "nicht vorhanden" gemeldet. Form beurteilt man
	# ohne Fahne, die Fahne beurteilt man im normalen Bild.
	if schalter.has("ohne_fahne"):
		for n in main.fly_world.get_children():
			if String(n.name).begins_with("VulkanFahne"):
				(n as Node3D).visible = false
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
	# GEZEICHNETE PRIMITIVEN MIT AUSGEBEN. Ohne diese Zahl ist jede Aussage ueber
	# Zeichenlast geraten: die Kamera-Fernebene liegt bei 9 km und kullt ohnehin das
	# meiste, ein Dreieck im Speicher ist also noch lange keines im Bild. Der Wert kommt
	# aus dem letzten gezeichneten Frame, steht also fuer genau diese Kamerastellung.
	var prims := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	print("Render -> %s   md5=%s  chunks=%d  h=%.1f  build=%d ms  prim=%d"
		% [path, sum, terrain.get_child_count(), terrain.height_at(pos.x, pos.z),
			build_ms, int(prims)])
