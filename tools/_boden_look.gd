## BODEN-LOOK: dieselben festen Kamerastellungen in mehreren Fassungen der Umgebung
## (Dunst, Licht) — zum Abstimmen von Gelaendefarbe und Luftperspektive ("verwaschen?").
##
##   HOME=<test-home> Godot --path . --script res://tools/_boden_look.gd [-- stellung ...]
## Fassungen ueber BODEN_FASSUNGEN (Komma-Liste, Standard "basis"):
##   basis        wie im Spiel
##   ohne_dunst   Nebel aus (zeigt die reinen Materialfarben)
##   ohne_luft    Luftperspektive 0 (Dunst nur in fog_light_color)
##   frei, z. B.  e1.3+f0.7+a0.4+c0.45_0.55_0.69+s0.2  (Kurvenende als Faktor, Kurvenform,
##                Luftperspektive, Dunstfarbe sRGB, Sonnenstreuung — Tiefennebel wie im
##                Spiel, siehe Main.NEBEL_ENDE)
## Bilder: user://look_<stellung>_<fassung>.png, Wolken und HUD aus. Zahlen je Bild:
## mittlere Saettigung und Helligkeits-Spreizung in drei Bildstreifen (nah/mittel/fern),
## damit "verwaschen" messbar wird und nicht nur Geschmack ist.
extends SceneTree

# name, Kamera, Blickziel (Welt, absolut)
const STELLUNGEN := [
	["berge", Vector3(-2600, 950, -4500), Vector3(-2300, 380, -7500)],
	["ebene", Vector3(-6000, 700, 3000), Vector3(-8100, 60, 5100)],
	["reise", Vector3(2000, 1800, 8000), Vector3(2600, 0, 11000)],
	["wiese", Vector3(74, 410, -1933), Vector3(1574, 120, -3263)],
	["kueste", Vector3(9000, 70, 24500), Vector3(6000, 20, 24050)],
	["hoch", Vector3(0, 5200, 3000), Vector3(2700, 0, -6000)],
]

var f := 0
var m: Node
var cam: Camera3D
var wahl: Array = []
var fassungen: PackedStringArray = ["basis"]
var i := 0
var j := 0
var t0 := 0
var warte := 0
var basis_farbe := Color()
var basis_luft := -1.0
var basis_streu := 0.0
var aktiv := "basis"
var gesetzt := ""


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for s in STELLUNGEN:
		if a.is_empty() or a.has(String(s[0])):
			wahl.append(s)
	var fe := OS.get_environment("BODEN_FASSUNGEN")
	if fe != "":
		fassungen = fe.split(",")


func _hin() -> void:
	var p: Vector3 = wahl[i][1]
	var ziel: Vector3 = wahl[i][2]
	var ac = m.flight_ctrl.aircraft
	if is_instance_valid(ac):
		ac.global_position = p + Vector3(0, 30, 0)
		ac.linear_velocity = Vector3.ZERO
		ac.freeze = true
		ac.visible = false
	m.terrain.build_now_around(Vector3(p.x, 0, p.z).lerp(Vector3(ziel.x, 0, ziel.z), 0.35), 2600.0)
	cam.look_at_from_position(p, ziel, Vector3.UP)


func _fassung(name: String) -> void:
	aktiv = name
	_anwenden()


## Main._wolken_aufenthalt setzt Dichte und Farbe des Dunsts JEDEN Frame neu — die Fassung
## wird deshalb kurz vor dem Zeichnen (RenderingServer.frame_pre_draw) erneut aufgelegt.
func _anwenden() -> void:
	if m == null or wahl.is_empty() or i >= wahl.size():
		return
	var env: Environment = m.get("env_sky")
	var p: Vector3 = wahl[i][1]
	# immer erst auf den Spielstand zurueck
	if basis_luft < 0.0:
		basis_farbe = env.fog_light_color
		basis_luft = env.fog_aerial_perspective
		basis_streu = env.fog_sun_scatter
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_depth_end = m.nebel_ende_bei(p.y)
	env.fog_depth_curve = m.nebel_form_bei(p.y)
	env.fog_light_color = basis_farbe
	env.fog_aerial_perspective = basis_luft
	env.fog_sun_scatter = basis_streu
	match aktiv:
		"ohne_dunst":
			env.fog_enabled = false
		"ohne_luft":
			env.fog_aerial_perspective = 0.0
		_:
			# Freie Fassung aus Bausteinen mit "+": b<m> Kurvenanfang, e<faktor> Kurvenende,
			# f<form> Kurvenform,
			# a<wert> Luftperspektive, s<wert> Sonnenstreuung, c<r>_<g>_<b> Dunstfarbe (sRGB)
			for tok in aktiv.split("+"):
				if tok.begins_with("b"):
					env.fog_depth_begin = float(tok.substr(1))
				elif tok.begins_with("e"):
					env.fog_depth_end *= float(tok.substr(1))
				elif tok.begins_with("f"):
					env.fog_depth_curve = float(tok.substr(1))
				elif tok.begins_with("a"):
					env.fog_aerial_perspective = float(tok.substr(1))
				elif tok.begins_with("s"):
					env.fog_sun_scatter = float(tok.substr(1))
				elif tok.begins_with("c"):
					var k := tok.substr(1).split("_")
					env.fog_light_color = Color(float(k[0]), float(k[1]), float(k[2]))
	if aktiv != gesetzt:
		gesetzt = aktiv
		m.terrain.setze_nebel_licht(env, m.get("sonne_licht"))
	m.terrain.setze_dunst(env.fog_depth_begin, env.fog_depth_end if env.fog_enabled else 1.0e9,
		env.fog_depth_curve, env.fog_light_color)


## Mittlere Saettigung (HSV), Median der Helligkeit und Helligkeitsspreizung (P90 - P10) je
## Bildstreifen. Die Streifen sind feste Bildzeilen unter dem Horizont (nah unten, fern knapp
## unter der Bildmitte) — die Stellungen blicken alle schraeg nach unten.
func _zahlen(img: Image) -> String:
	var w := img.get_width()
	var h := img.get_height()
	var out := ""
	for streifen in [[0.80, 0.98, "nah"], [0.62, 0.78, "mitte"], [0.50, 0.60, "fern"]]:
		var y0 := int(h * float(streifen[0]))
		var y1 := int(h * float(streifen[1]))
		var sat := 0.0
		var n := 0
		var lum := PackedFloat32Array()
		for y in range(y0, y1, 6):
			for x in range(0, w, 6):
				var c := img.get_pixel(x, y)
				sat += c.s
				lum.append(c.get_luminance())
				n += 1
		lum.sort()
		var spreiz := lum[int(lum.size() * 0.9)] - lum[int(lum.size() * 0.1)]
		out += "  %s: sat %.3f  hell %.3f  spreiz %.3f" % [streifen[2], sat / maxf(n, 1),
			lum[lum.size() / 2], spreiz]
	return out


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		get_root().add_child(m)
		return false
	if f == 20:
		m._set_mode(1)
		RenderingServer.frame_pre_draw.connect(_anwenden)
		cam = Camera3D.new()
		cam.far = 9000.0
		cam.fov = 62.0
		m.fly_world.add_child(cam)
		return false
	if f == 25:
		cam.current = true
		for c in m.get("cloud_fields"):
			(c as Node3D).visible = false
		for c in m.get("wolken_formationen"):
			(c as Node3D).visible = false
		for c in m.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		return false
	if f > 25 and t0 == 0:
		warte += 1
		if m.get("_fern_stufe_knoten") != null or warte > 5400:
			if wahl.is_empty():
				quit()
				return true
			t0 = f
			_hin()
			_fassung(fassungen[0])
		return false
	if f - t0 >= 90 and f - t0 < 9000 and not m.call("fern_bereit", wahl[i][1]):
		return false
	if f - t0 >= 90 and f - t0 < 9000 \
			and (not (m.terrain.get("_flora_warteschlange") as Array).is_empty()
				or not (m.terrain.get("_pending") as Dictionary).is_empty()
				or not (m.terrain.get("_done") as Array).is_empty()):
		return false
	if f - t0 >= 90:
		var name := "%s_%s" % [wahl[i][0], fassungen[j]]
		var img := get_root().get_viewport().get_texture().get_image()
		img.save_png("user://look_%s.png" % name)
		print("LOOK ", name, _zahlen(img))
		j += 1
		if j >= fassungen.size():
			j = 0
			i += 1
			if i >= wahl.size():
				quit()
				return true
			_hin()
			t0 = f
		else:
			# andere Fassung derselben Stellung: nur ein paar Frames fuer den Dunst
			t0 = f - 80
		_fassung(fassungen[j])
	return false
