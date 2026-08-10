extends SceneTree
## HIMMELS-ABNAHME: feste Kamerastellungen, eingefrorene Zeit, echte Spielszene.
##
## Warum ein eigenes Werkzeug neben tools/_terrain_render.gd: dessen acht Ansichten sind
## auf die LANDSCHAFT ausgelegt — der Himmel steht dort meist als schmaler Streifen am
## oberen Rand. Fuer die Beurteilung von Verlauf, Sonne, Dunst und Wolken braucht es
## Blicke, in denen der Himmel das Bild traegt.
##
##   godot --path . --script res://tools/_sky_render.gd -- <prefix> [t=<sek>] [nur=<name>]
##                                                        [<breite> <hoehe>]
##
## Erzeugt <prefix>_<name>.png fuer jede Stellung.
##
## ------------------------------------------------------------------------------------
## WAS HIER REPARIERT WURDE UND WARUM (die alte Fassung hat ihr eigenes Versprechen
## "zwei Laeufe liefern pixelweise vergleichbare Bilder" NICHT gehalten — gemessen wichen
## zwei Laeufe bei voellig identischem Projektstand im Mittel um 8.8 bis 52.2 je Kanal ab,
## der zu messende Shaderwechsel selbst nur um 10.1 bis 56.4; in 5 von 8 Ansichten war das
## Rauschen also groesser als das Signal). Drei unabhaengige Ursachen:
##
## 1) GELAENDE-STREAMING. Die alte Reihenfolge war update_center() DANN build_now_around().
##    update_center() wirft dabei alles ausserhalb des neuen Sichtkreises per queue_free()
##    weg (wirkt erst am Frameende) und legt gleichzeitig fuer jeden fehlenden Chunk einen
##    Auftrag in den Worker-Thread. Danach baute build_now_around() dieselben Chunks noch
##    einmal synchron. Ergebnis: (a) die Chunks der VORIGEN Pose standen je nach Timing im
##    Bild oder nicht — daher der Gruenanteil 40.2 / 32.8 / 0.0 Prozent ueber drei Laeufe
##    in horiz_sonne; (b) die Worker-Auftraege liefen noch Dutzende Frames weiter (nur EIN
##    Chunk je Frame wird eingehaengt) und tropften mitten in SPAETERE Schuesse.
##    Jetzt: erst synchron bauen, DANN update_center — dann findet update_center alles
##    schon vor und stellt gar keinen Auftrag mehr. Danach wird gewartet, bis Auftrags-
##    und Fertigliste leer sind und die freigegebenen Knoten wirklich weg sind.
##
## 2) DIE UHR. Engine.time_scale = 0 friert die Shader-Variable TIME NICHT ein — die haengt
##    am Renderer, nicht am Spielzeitschritt. Deshalb hatte jedes Bild eine neue md5, die
##    Entprell-Schleife brach IMMER schon beim ersten Versuch ab (sie suchte ja nur nach
##    einem Bild, das sich von den bisherigen unterscheidet), und Wolkendrift und Wellen
##    liefen zwischen zwei Laeufen auseinander. Jetzt wird die Uhr an der QUELLE angehalten:
##    der Himmel bekommt cloud_clock (Uniform, siehe sky_clouds.gdshader), das Wasser
##    bekommt alle drei Wellengeschwindigkeiten auf 0. Damit ist das Bild eine reine
##    Funktion der Pose — und die Entprellung kann endlich das Richtige pruefen:
##    fertig ist, wenn ZWEI aufeinanderfolgende Bilder BITGLEICH sind.
##    t=<sek> setzt die Wolkenuhr auf einen anderen Zeitpunkt; genau so wird geprueft, ob
##    sich die Wolken ueberhaupt entwickeln oder nur als starre Tapete durchziehen.
##
## 3) POSE UND BILD PASSTEN NICHT ZUSAMMEN. Die alte Fassung wartete EINEN Frame VOR dem
##    look_at und sicherte danach beim ersten frame_post_draw. In "zenit" (Nick +55 Grad,
##    Horizont rechnerisch 463 Zeilen UNTER dem Bild) stand deshalb eine Kueste mitten im
##    Bild — gespeichert war noch die vorige Pose. Jetzt wird die Kamera VOR dem Warten
##    gesetzt und erst nach dem Einschwingen gesichert; zusaetzlich meldet jede Zeile die
##    per unproject_position aus der TATSAECHLICHEN Kameramatrix bestimmte Horizontzeile,
##    sodass sich am fertigen Bild nachpruefen laesst, ob es zur Pose gehoert.
##
## Ausserdem neu: die Ansicht "sonne_frei" (Nick = Sonnenhoehe, Blick in den Sonnenazimut).
## Vorher stand die Sonne in genau einer der acht Ansichten ueberhaupt im Bild, dort am
## oberen Rand und hinter einer Wolke — das Kriterium "Sonne" war damit gar nicht pruefbar.

const VFOV := 64.0          # wie Main._setup_camera
const CAM_FAR := 9000.0

var prefix := "/tmp/sky"
var breite := 1280
var hoehe := 720
var uhr := 0.0              # fester Zeitpunkt fuer die Wolken (Sekunden)
var nur: PackedStringArray = []   # nur diese Ansichten rendern (leer = alle)
var stellen := {}           # set=<uniform>:<wert> — Probeschuesse ohne Shaderaenderung
var vp: SubViewport
var main: Node3D
var cam: Camera3D
var _started := false
var _finished := false


func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _finished


func _run() -> void:
	var groesse: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("t="):
			uhr = float(a.substr(2))
		elif a.begins_with("nur="):
			nur = a.substr(4).split(",")
		elif a.begins_with("set="):
			var kv := a.substr(4).split(":")
			# Ein Wert -> float, drei durch Komma getrennte -> Farbe.
			# ALS COLOR, NICHT ALS VECTOR3: die Farb-Uniforms im Shader tragen den Hinweis
			# source_color, und Godot rechnet solche Werte von sRGB nach linear um. Ein
			# Vector3 umgeht diese Umrechnung — die Probe stuende dann fuenf- bis achtfach
			# zu hell da und man wuerde etwas voellig anderes einmessen als das, was im
			# Shader steht. (Genau in diese Falle bin ich beim ersten Anlauf getreten:
			# eine DUNKLERE Schattenfarbe machte das Bild heller.)
			var teile := kv[1].split(",")
			if teile.size() == 3:
				stellen[kv[0]] = Color(float(teile[0]), float(teile[1]), float(teile[2]))
			else:
				stellen[kv[0]] = float(kv[1])
		elif a.is_valid_int():
			groesse.append(int(a))
		elif a != "":
			prefix = a
	if groesse.size() >= 2:
		breite = groesse[0]
		hoehe = groesse[1]

	vp = SubViewport.new()
	vp.size = Vector2i(breite, hoehe)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	main = load("res://scenes/Main.tscn").instantiate()
	vp.add_child(main)
	cam = Camera3D.new()
	cam.far = CAM_FAR
	vp.add_child(cam)
	ViewUtil.apply_vfov(cam, VFOV)
	cam.current = true

	await process_frame
	await process_frame
	_flugzustand()
	# Spielzeit anhalten (Flugzeug, Wolkendecke, alles Prozessgesteuerte). Fuer die
	# SHADER-Zeit reicht das nicht, siehe _uhr_anhalten().
	Engine.time_scale = 0.0
	_uhr_anhalten()

	# Sonnenrichtung aus DERSELBEN Quelle wie Licht und Himmel — sonst stehen die
	# "zur Sonne"-Ansichten woanders, sobald jemand SONNE_WINKEL dreht.
	var sonne: Vector3 = Basis.from_euler(Vector3(
		deg_to_rad(main.SONNE_WINKEL.x), deg_to_rad(main.SONNE_WINKEL.y), 0.0)).z
	var az := Vector3(sonne.x, 0.0, sonne.z).normalized()      # Sonnenazimut, waagerecht
	var quer := Vector3(-az.z, 0.0, az.x)                      # 90 Grad dazu
	var sonnenhoehe := rad_to_deg(asin(sonne.y))
	print("Sonne: ", sonne, "  Hoehenwinkel %.1f Grad   Wolkenuhr t=%.1f s" % [sonnenhoehe, uhr])

	# Ueber offener See (Abstand vom Ursprung > Kuestenradius ~12,8 km) und ueber Land.
	var see := Vector3(0, 0, 17000)
	var land := Vector3(700, 0, 200)

	# [Name, Standort, Hoehe, Blickrichtung (waagerecht), Nickwinkel Grad]
	# Die ersten acht sind unveraendert — sonst waeren die Bilder in /tmp/skyref wertlos.
	var posen: Array = [
		["horiz_sonne",  see,  300.0,  az,    0.0],    # Sonne im Bild, Horizont in der Mitte
		["horiz_gegen",  see,  300.0, -az,    0.0],    # Gegensonne — dort ist der Himmel am flachsten
		["horiz_quer",   see,  300.0,  quer,  0.0],    # Seitlich: Verlauf ohne Sonneneinfluss
		["zenit",        see,  300.0,  quer, 55.0],    # steil nach oben: Verlauf und Banding
		["unter_decke",  see,  150.0,  az,   25.0],    # unter der Wolkendecke hindurch nach oben
		["ueber_decke",  see,  900.0,  az,  -20.0],    # ueber der Decke, Blick ueber die Oberseite
		["hoch",         see, 3000.0,  quer, -12.0],   # grosse Hoehe: ganzer Himmel plus Horizont
		["land_gegen",   land, 400.0, -az,   10.0],    # ueber Land, Gegensonne — Dunst und Ferne
		# NEU: Nick GENAU auf die Sonnenhoehe, Blick in den Sonnenazimut -> die Sonne steht
		# in der Bildmitte. Nur hier sind Scheibe, Glast und Hof ueberhaupt beurteilbar.
		["sonne_frei",   see,  600.0,  az, sonnenhoehe],
	]
	for p in posen:
		if nur.size() > 0 and not nur.has(String(p[0])):
			continue
		await _schuss(p)

	# NAHAUFNAHMEN DER VOLUMENWOLKEN, mit gesuchtem statt festem Ziel.
	# WARUM GESUCHT: die Nahprobe hing bisher daran, dass in der festen Ansicht "zenit"
	# zufaellig eine grosse Wolke stand. Die Feldbelegung verschiebt sich aber bei jeder
	# Aenderung an der Wolkenform — schon ein Zufallswurf mehr in _puff_mesh setzt die
	# ganze Decke neu. Genau das ist passiert: nach der ersten Formrunde stand in "zenit"
	# ueberhaupt keine Volumenwolke mehr, und die Nahaufnahme prueft seither nur noch den
	# gemalten Himmel. Eine Ansicht, die sich ihre Wolke SUCHT, kann so nicht verlorengehen.
	for np in [["puff_160", 160.0], ["puff_70", 70.0]]:
		var nm := String(np[0])
		if nur.size() > 0 and not nur.has(nm):
			continue
		var pose := _pose_puff_nah(nm, see, float(np[1]), quer)
		if pose.is_empty():
			print("Sky -> %s ENTFAELLT: keine sichtbare Volumenwolke gefunden" % nm)
			continue
		await _schuss(pose)

	# --- FLUGPLATZ HEIMAT: vier Ansichten, die den Referenzbildern entsprechen ----------
	# Die Kamerastellungen sind aus dem TATSAECHLICHEN Aufbau abgeleitet (Main._build_airfield:
	# HEIMAT bei (0,0,-100), Bahn 900 x 30 m laengs Z, Vorfeld und Bauten bei +X), damit sie
	# nicht verrutschen, wenn jemand den Platz umbaut. Sie heissen wie die Referenzbilder.
	for fp in [
		["fp_ueberflug", Vector3(-210.0, 330.0, -830.0), Vector3(95.0, 0.0, -150.0)],
		["fp_schwelle",  Vector3(0.0, 6.0, 355.0),       Vector3(0.0, 6.0, -400.0)],
		["fp_vorfeld",   Vector3(-55.0, 60.0, 195.0),    Vector3(100.0, 8.0, -70.0)],
		["fp_anflug",    Vector3(-115.0, 235.0, 500.0),  Vector3(65.0, 0.0, -230.0)],
	]:
		if nur.size() > 0 and not nur.has(String(fp[0])):
			continue
		await _schuss(_pose_nach(String(fp[0]), fp[1], fp[2]))

	_finished = true
	quit()


## Wandelt Kameraort und Blickziel in das Posenformat von _schuss um.
func _pose_nach(name: String, kam: Vector3, ziel: Vector3) -> Array:
	var d := ziel - kam
	var waag := Vector3(d.x, 0.0, d.z)
	if waag.length_squared() < 0.0001:
		waag = Vector3(0, 0, -1)
	var nick := rad_to_deg(atan2(d.y, waag.length()))
	return [name, Vector3(kam.x, 0.0, kam.z), kam.y, waag.normalized(), nick]


## Baut eine Pose, die die groesste sichtbare Volumenwolke in der Naehe von `ort` aus
## `abstand` Metern zeigt — Blick waagerecht in Richtung `richt`, leicht von unten (so
## sieht der Spieler die Decke aus dem Cockpit die meiste Zeit).
## Liefert eine leere Liste, wenn dort keine Wolke steht.
func _pose_puff_nah(name: String, ort: Vector3, abstand: float, richt: Vector3) -> Array:
	var feld: Node3D = main.cloud_field
	if feld == null or not is_instance_valid(feld):
		return []
	var beste: MeshInstance3D = null
	var bester_r := 0.0
	for k in feld.get_children():
		var mi := k as MeshInstance3D
		if mi == null or not mi.visible or mi.mesh == null:
			continue
		# Nur Wolken in der Naehe des Messortes — sonst steht die Kamera am Weltrand.
		if Vector2(mi.position.x - ort.x, mi.position.z - ort.z).length() > 2500.0:
			continue
		var bb := mi.mesh.get_aabb()
		var r: float = maxf(bb.size.x, bb.size.z) * 0.5 * mi.scale.x
		if r > bester_r:
			bester_r = r
			beste = mi
	if beste == null:
		return []
	# Blickrichtung: waagerecht `richt`, 15 Grad angehoben.
	var nick := deg_to_rad(15.0)
	var d := (richt.normalized() * cos(nick) + Vector3.UP * sin(nick)).normalized()
	var kam := beste.position - d * abstand
	print("  %s: Wolke bei (%.0f, %.0f, %.0f), Halbmesser %.0f m, Kamera %.0f m davor"
		% [name, beste.position.x, beste.position.y, beste.position.z, bester_r, abstand])
	return [name, Vector3(kam.x, 0.0, kam.z), kam.y,
		Vector3(d.x, 0.0, d.z).normalized(), rad_to_deg(nick)]


func _flugzustand() -> void:
	## Wie tools/_terrain_render.gd: Main startet im Bau-Modus, hier wird der Flugzustand
	## nachgezogen, ohne _set_mode zu rufen (das faengt die Maus und startet Wellen).
	main.build_ctrl.set_active(false)
	main.build_ctrl.design_root.visible = false
	main.build_root.visible = false
	main.flight_root.visible = false
	main.world_env.environment = main.env_sky
	main.fly_world.visible = true
	if main.showroom != null:
		main.showroom.set_stage_visible(false)
	if main.sky_lights != null:
		main.sky_lights.visible = true
	main.camera.current = false
	cam.current = true
	main.mode = 1
	_overlays_aus(main)


## Alles anhalten, was an der SHADER-Zeit haengt. Engine.time_scale erreicht TIME nicht.
## Nur so ist das Bild eine Funktion der Pose allein — und nur dann sagt ein Pixelvergleich
## zweier Laeufe etwas ueber den Shader aus.
func _uhr_anhalten() -> void:
	var sm := main.env_sky.sky.sky_material as ShaderMaterial
	if sm != null:
		# cloud_clock < 0 bedeutet im Shader "TIME benutzen"; ein Wert >= 0 haelt die
		# Wolkenuhr fest. Drift UND Entwicklung haengen dort an derselben einen Zahl.
		sm.set_shader_parameter("cloud_clock", uhr)
		# Probeschuesse: einzelne Uniforms von der Kommandozeile setzen. Dafuer gibt es
		# einen handfesten Grund — die Kennlinie der Nachbelichtung (ACES white 6,
		# saturation 1.18, contrast 1.05, sRGB) laesst sich nicht zuverlaessig
		# nachrechnen; sie muss AM BILD eingemessen werden. Mit set=cloud_shade_hi:-0.9
		# bzw. :2.0 faehrt man die Beleuchtung an ihre beiden Anschlaege und liest ab,
		# welche Bildwerte lit = 1 und lit = 0 wirklich ergeben.
		for k in stellen.keys():
			sm.set_shader_parameter(k, stellen[k])
	# DIESELBEN Proben auch an die Volumenwolken. Godot meckert nicht, wenn ein Uniform
	# im jeweiligen Shader gar nicht existiert — man kann also mit einem Aufruf beide
	# Wolkensorten bedienen, ohne die Namen auseinanderhalten zu muessen.
	if not stellen.is_empty() and main.cloud_field != null:
		for k2 in main.cloud_field.get_children():
			var mi := k2 as MeshInstance3D
			if mi == null:
				continue
			var pm := mi.material_override as ShaderMaterial
			if pm == null:
				continue
			for k in stellen.keys():
				pm.set_shader_parameter(k, stellen[k])
			break        # alle Puffs teilen sich EIN Material
	# Wasser: die Wellenmuster laufen mit speed*TIME. Geschwindigkeit 0 haelt das Muster an,
	# ohne seine Form zu aendern (das Argument ist p/len - dir*speed*t/len).
	for m in main.terrain._wasser_mats:
		m.set_shader_parameter("swell_speed", 0.0)
		m.set_shader_parameter("chop_speed", 0.0)
		m.set_shader_parameter("ripple_speed", 0.0)


func _overlays_aus(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer:
			c.visible = false
		_overlays_aus(c)


## Gelaende um `pos` FERTIG bauen und zur Ruhe kommen lassen.
## Reihenfolge ist entscheidend, siehe Kopfkommentar Punkt 1.
func _welt_fertig(pos: Vector3) -> void:
	# 0) offene Worker-Auftraege wegwerfen. Wir bauen ohnehin gleich alles synchron, und
	#    eingehaengt wird nur EIN Chunk je Frame (MAX_ATTACH_PER_FRAME = 1): allein der
	#    Vorrat, den Main._ready um den Spawn herum bestellt, sind rund 370 Chunks und
	#    damit 370 Frames, in denen fremdes Gelaende in laufende Schuesse tropft.
	#    _pending darf mitgeloescht werden — es ist reine Buchhaltung gegen doppelte
	#    Auftraege, und _process verwirft ohnehin jeden Chunk, den es schon gibt.
	main.terrain._mutex.lock()
	main.terrain._jobs.clear()
	main.terrain._mutex.unlock()
	main.terrain._pending.clear()
	# 1) alles Sichtbare synchron bauen. build_now_around benutzt denselben Radiusfilter
	#    wie update_center (Abstand > radius + CHUNK faellt raus) und laeuft eine Chunkreihe
	#    weiter — es baut also sicher die ganze Wunschmenge von update_center.
	main.terrain.build_now_around(pos, TerrainWorld.VIEW_DIST, false)
	# 2) jetzt erst umziehen: die Wasserplatte nachfuehren und Fernes abraeumen. Weil alles
	#    Gewuenschte schon dasteht, legt update_center KEINEN einzigen Worker-Auftrag mehr an.
	main.terrain.update_center(pos)
	# 3) warten, bis nichts mehr unterwegs ist (Auftraege aus frueheren Posen, vor allem der
	#    Spawn-Aufbau in Main._ready) und bis die per queue_free abgeraeumten Knoten
	#    wirklich aus dem Baum sind. Ohne diesen Punkt stand das Land der VORIGEN Pose je
	#    nach Timing noch im Bild.
	var ruhig := 0
	for runde in 900:
		await process_frame
		if main.terrain._pending.is_empty() and main.terrain._done.is_empty():
			ruhig += 1
			if ruhig >= 3:
				return
		else:
			ruhig = 0
	push_warning("Gelaende kam nicht zur Ruhe")


func _schuss(p: Array) -> void:
	_overlays_aus(main)                      # die Karte haengt sich spaeter ein
	var name: String = p[0]
	var ort: Vector3 = p[1]
	var hoehe_m: float = p[2]
	var richt: Vector3 = p[3]
	var nick := deg_to_rad(float(p[4]))

	var pos := ort + Vector3(0, hoehe_m, 0)
	await _welt_fertig(pos)
	_uhr_anhalten()                          # falls unterwegs neue Wassermaterialien kamen

	# Kamera VOR dem Warten setzen — sonst gehoert das erste gezeichnete Bild noch zur
	# vorigen Pose (genau der Fehler, der in "zenit" eine Kueste ins Bild gestellt hat).
	var ziel := pos + (richt * cos(nick) + Vector3.UP * sin(nick)) * 1000.0
	cam.look_at_from_position(pos, ziel, Vector3.UP)

	# Horizontzeile aus der TATSAECHLICHEN Kamerabasis. Damit laesst sich am fertigen PNG
	# nachpruefen, ob Bild und Pose zusammengehoeren — genau der Test, an dem die alte
	# Fassung aufgeflogen ist (zenit meldete Nick +55, im Bild stand eine Kueste).
	# Herleitung: der Strahl zur Bildzeile r ist -basis.z + basis.y * (h/2 - r)/f mit
	# f = (h/2)/tan(vfov/2). Waagerecht (Strahl.y = 0) wird er bei r = h/2 - f*bz.y/by.y.
	# unproject_position ist hier NICHT brauchbar: es lieferte fuer jede Pose Zahlen, die
	# nachweislich nicht zur gerenderten Ansicht passen (zenit 360 statt 1183).
	var b := cam.global_transform.basis
	var f := (float(hoehe) * 0.5) / tan(deg_to_rad(VFOV) * 0.5)
	var hz := float(hoehe) * 0.5 - f * (b.z.y / b.y.y)

	var pfad := "%s_%s.png" % [prefix, name]
	# Entprellen, jetzt mit dem RICHTIGEN Kriterium: fertig ist, wenn zwei aufeinander-
	# folgende Bilder bitgleich sind. Das kann nur greifen, weil die Uhr steht.
	var sum := ""
	var vorher := ""
	var stabil_nach := -1
	for versuch in 16:
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(pfad)
		sum = FileAccess.get_md5(pfad)
		if sum == vorher:
			stabil_nach = versuch
			break
		vorher = sum
	if stabil_nach < 0:
		print("WARNUNG: %s wurde in 16 Frames nicht stabil" % name)
	print("Sky -> %s   md5=%s  stabil@%d  pos=(%.0f, %.0f, %.0f)  nick=%.1f  horizont_y=%.0f"
			% [pfad, sum, stabil_nach, pos.x, pos.y, pos.z, float(p[4]), hz])
