## DER NACHTFALKE — Bauplan laden, aufbauen, von vier Seiten ansehen.
##
## Ein Bauplan ist eine Liste aus Teilenamen und Zahlen; ob daraus ein Flugzeug wird oder
## ein Haufen sich durchdringender Kloetze, sieht man erst im Bild. Zusaetzlich mit
## geoeffnetem Schacht, denn die Bomben darin sind der halbe Zweck der Uebung.
##
## Godot --path . --script res://tools/_falke_render.gd -- <praefix>
extends SceneTree

const W := 1280
const H := 720
var f := 0
var vp: SubViewport
var cam: Camera3D
var akt: Node3D
var prefix := "user://falke"
# [Name, Kameraposition, Blickziel, Klappen offen]
var SICHTEN := [
	["seite",  Vector3(-19.0, 1.2, 0.2), Vector3(0, 0.1, 0.2), false],
	["oben",   Vector3(0.5, 30.0, 0.6), Vector3(0, 0, 0.4), false],
	["front",  Vector3(4.5, 3.0, -15.0), Vector3(0, -0.1, -0.5), false],
	["unten",  Vector3(4.5, -12.0, -3.5), Vector3(0, 0, 1.1), true],
	["heck",   Vector3(7.5, 2.2, 15.0), Vector3(0, 0.1, 2.0), true],
]


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		var ua := OS.get_cmdline_user_args()
		if ua.size() > 0:
			prefix = String(ua[0])
		_aufbau()
		return false
	if f < 5:
		return false
	var schritt := (f - 5) % 5
	var nr := (f - 5) / 5
	if nr >= SICHTEN.size():
		quit()
		return true
	if schritt == 0:
		_stellen(nr)
	elif schritt == 4:
		var pfad := "%s_%s.png" % [prefix, SICHTEN[nr][0]]
		vp.get_texture().get_image().save_png(pfad)
		print("SCHUSS %s" % pfad)
	return false


func _aufbau() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.11, 0.13, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.52, 0.58, 0.70)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_white = 6.0
	we.environment = e
	vp.add_child(we)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-34.0, 42.0, 0.0)
	l.light_energy = 1.6
	vp.add_child(l)
	var l2 := DirectionalLight3D.new()
	l2.rotation_degrees = Vector3(24.0, -140.0, 0.0)
	l2.light_energy = 0.55
	vp.add_child(l2)
	cam = Camera3D.new()
	cam.fov = 38.0
	vp.add_child(cam)
	akt = Node3D.new()
	vp.add_child(akt)
	_bauen()


## Den Bauplan genauso lesen, wie Main._load_design_from es tut.
func _bauen() -> void:
	var fh := FileAccess.open("res://designs/nachtfalke.json", FileAccess.READ)
	var liste: Array = JSON.parse_string(fh.get_as_text())
	for e in liste:
		var p := PartCatalog.get_part(String(e["id"]))
		var vis := PartCatalog.build_visual(p, Color(e["color"][0], e["color"][1],
			e["color"][2], 1.0))
		var x: Array = e["xform"]
		var b := Basis(Vector3(x[0], x[3], x[6]), Vector3(x[1], x[4], x[7]),
			Vector3(x[2], x[5], x[8]))
		var knoten := Node3D.new()
		knoten.transform = Transform3D(b, Vector3(x[9], x[10], x[11]))
		var sc: Array = e.get("scale", [1, 1, 1])
		vis.scale = Vector3(sc[0], sc[1], sc[2])
		knoten.add_child(vis)
		akt.add_child(knoten)


func _stellen(nr: int) -> void:
	var s: Array = SICHTEN[nr]
	cam.position = s[1]
	cam.look_at_from_position(s[1], s[2], Vector3.UP)
	var w: float = deg_to_rad(102.0) if bool(s[3]) else 0.0
	for k in _klappen(akt):
		(k as Node3D).rotation.z = float(k.get_meta("bay_door")) * w


func _klappen(n: Node) -> Array:
	var out: Array = []
	if n.has_meta("bay_door"):
		out.append(n)
	for c in n.get_children():
		out.append_array(_klappen(c))
	return out
