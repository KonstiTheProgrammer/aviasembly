## DER BOMBENSCHACHT VON UNTEN, IN DREI KLAPPENSTELLUNGEN.
##
## Von unten, weil dort das Loch ist — von schraeg oben sieht ein Schacht aus wie jedes
## andere Rumpfsegment und man sieht genau das nicht, worauf es ankommt. Drei Stellungen,
## weil sich die drei Fragen nur so trennen lassen:
##
##   ZU        Schliessen die Klappen den Ausschnitt sauber? Sie sind ein Stueck derselben
##             Ellipse; steht die Kruemmung falsch, klafft es an den Raendern.
##   HALB      Dreht sich die Klappe um die richtige ACHSE und in die richtige RICHTUNG?
##             Eine falsch herum drehende Klappe faehrt in den Rumpf statt heraus.
##   AUF       Sieht man einen Laderaum oder durch das Flugzeug hindurch? Das ist die
##             eigentliche Probe auf das Loch.
##
## Godot --path . --script res://tools/_schacht_render.gd -- <zielpfad-praefix>
extends SceneTree

const W := 1100
const H := 720
var f := 0
var i := 0
var prefix := "user://schacht"
var vp: SubViewport
var cam: Camera3D
var akt: Node3D
const STELLUNGEN := [["zu", 0.0], ["halb", 0.5], ["auf", 1.0]]


## SceneTree._process MUSS bool liefern. Ein "await" darin macht die Funktion zu einer
## Koroutine, die stattdessen ein Signal zurueckgibt — der erste Anlauf lief deshalb
## durch, ohne ein einziges Bild zu schreiben. Also von Hand takten: aufbauen, Stellung
## setzen, ein paar Frames zeichnen lassen, speichern.
func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		var ua := OS.get_cmdline_user_args()
		if ua.size() > 0:
			prefix = String(ua[0])
		_aufbau()
		return false
	if f < 4:
		return false
	var schritt := (f - 4) % 5
	var nr := (f - 4) / 5
	if nr >= STELLUNGEN.size() * 2:
		quit()
		return true
	@warning_ignore("integer_division")
	var art: String = "schraeg" if nr < STELLUNGEN.size() else "unten"
	if schritt == 0:
		i = nr % STELLUNGEN.size()
		_kamera(art)
		_stellen()
	elif schritt == 4:
		var pfad := "%s_%s_%s.png" % [prefix, art, STELLUNGEN[i][0]]
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
	e.background_color = Color(0.10, 0.12, 0.15)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.70)
	e.ambient_light_energy = 0.9
	we.environment = e
	vp.add_child(we)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-38.0, 34.0, 0.0)
	l.light_energy = 1.5
	vp.add_child(l)
	# Ein zweites Licht VON UNTEN — sonst liegt der Laderaum als schwarzes Loch im Bild
	# und man kann nicht beurteilen, ob dort Waende stehen oder gar nichts.
	var l2 := DirectionalLight3D.new()
	l2.rotation_degrees = Vector3(58.0, -120.0, 0.0)
	l2.light_energy = 0.8
	vp.add_child(l2)
	cam = Camera3D.new()
	# DICHT DRAN UND VON SCHRAEG UNTEN, mit engem Blickfeld. Aus der Ferne und mit weitem
	# Winkel war der Schacht ein Fingernagel im Bild — man sah, DASS sich etwas bewegt,
	# aber nicht, ob die Klappe den Ausschnitt trifft. Genau das ist die Frage.
	cam.fov = 40.0
	vp.add_child(cam)


## Zwei Blickrichtungen, weil sie verschiedene Fragen beantworten.
##
## SCHRAEG zeigt die Tiefe des Laderaums und ob die Klappe wirklich heraussteht.
## UNTEN blickt senkrecht auf die Oeffnung: dort muss das Bild spiegelsymmetrisch sein.
## Jede Unsymmetrie heisst, dass eine Klappe in die falsche Richtung dreht — und aus der
## schraegen Sicht war genau das nicht zu entscheiden, weil die ferne Klappe fast in der
## Blickachse liegt.
func _kamera(art: String) -> void:
	if art == "unten":
		cam.position = Vector3(0.0, -3.4, 0.0)
		cam.look_at_from_position(cam.position, Vector3.ZERO, Vector3.BACK)
	else:
		cam.position = Vector3(1.35, -1.55, 1.95)
		cam.look_at_from_position(cam.position, Vector3(0, -0.36, 0), Vector3.UP)


func _stellen() -> void:
	if akt != null:
		akt.free()
	akt = PartCatalog.build_visual(PartCatalog.get_part("bombbay"))
	vp.add_child(akt)
	# PRUEFMODUS: alle Materialien durch einen Shader ersetzen, der Vorderseiten gruen und
	# Rueckseiten rot faerbt. Genau dieser Test hat im Hochhausviertel ein komplett falsch
	# gewickeltes Netz aufgedeckt, das aus der Entfernung jahrelang wie ein Haus aussah —
	# und der Schacht ist mit derselben Gewohnheit geschrieben.
	if OS.get_cmdline_user_args().has("pruef"):
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_disabled, unshaded;
void fragment() { ALBEDO = FRONT_FACING ? vec3(0.15, 0.75, 0.25) : vec3(0.95, 0.1, 0.1); }
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		_faerben(akt, m)
	var winkel: float = float(STELLUNGEN[i][1]) * deg_to_rad(102.0)
	for k in akt.find_child("Schacht", false, false).get_children():
		if k.has_meta("bay_door"):
			k.rotation.z = float(k.get_meta("bay_door")) * winkel


## Alle Netze unter einem Knoten mit demselben Material ueberschreiben.
func _faerben(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = m
	for c in n.get_children():
		_faerben(c, m)
