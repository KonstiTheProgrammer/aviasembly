## SamSite.gd — Flugabwehr-Raketenstellung. Der Gegenpart zu Fackeln und Düppeln.
##
## WARUM ES DIESE DATEI GEBEN MUSS. Gegenmassnahmen ohne Bedrohung sind eine Taste ohne
## Wirkung. Vor dieser Stellung gab es in der ganzen Welt nichts, was auf den Spieler
## schiesst, ausser der Flak — und gegen Granaten helfen weder Fackeln noch Dueppel. Erst
## eine Stellung, die LENKWAFFEN startet, macht aus dem Werfer eine Entscheidung.
##
## ZWEI ARTEN, UND SIE VERLANGEN VERSCHIEDENES:
##
##   IR-STELLUNG    kurze Reichweite, sehr wendig, feuert und vergisst. Sie kommt erst
##                  spaet, dafuer schnell. Antwort: Fackeln — und zwar nach hinten, wo
##                  ihr Sucher hinsieht. Wer im Leerlauf gleitet, wird oft gar nicht
##                  erst erfasst (AircraftBody.ir_signatur haengt am Schub).
##
##   RADAR-STELLUNG grosse Reichweite, traege, HALBAKTIV: die Rakete sieht nur, was die
##                  Stellung anstrahlt. Der Werfer dreht sichtbar mit — solange er auf
##                  einen zeigt, ist man beleuchtet. Antwort: Dueppel, oder aus dem
##                  Strahl heraus hinter Gelaende gehen.
##
## WAS GEGEN WELCHE STELLUNG HILFT — gemessen mit tools/_sam_pruefstand.gd, je Zahl der
## Anteil der Treffer ueber fuenf Anfluege:
##
##   Stellung  Lage     frei  nur Koeder  nur Kurve  Koeder+Kurve  Gas aus
##   IR        quer     80 %       80 %      100 %        100 %       0 %
##   IR        Flucht  100 %       40 %      100 %         20 %      40 %
##   RADAR     quer     80 %       80 %        0 %          0 %      80 %
##   RADAR     Flucht  100 %       40 %      100 %         20 %     100 %
##
## Zu lesen: gegen die Waermestellung hilft im Vorbeiflug das GAS (sie startet gar nicht
## erst), im Fluchtflug die FACKEL. Gegen die Radarstellung ist es umgekehrt — im
## Vorbeiflug die KURVE, im Fluchtflug der DUEPPEL. Kein einzelner Knopf gewinnt gegen
## beide, und keine Stellung ist ohne Antwort. Genau das war das Ziel.
##
## EINE ZAHL SIEHT AUS WIE EIN FEHLER UND IST KEINER: gegen die Waermestellung macht die
## Kurve im Vorbeiflug es SCHLECHTER (80 auf 100 Prozent). Das ist richtig so. Der
## Pruefstand dreht vom Anflug fort — und wer einem Waermesucher davondreht, zeigt ihm
## genau das, wonach er sucht: die Duese. Gegen IR gehoert die Rakete auf die Seite
## gelegt oder angeflogen, nicht ins Heck genommen. Dass diese Lehre aus der Formel
## faellt und nicht hineingeschrieben wurde, ist der beste Beleg dafuer, dass das Modell
## traegt.
##
## Die Stellung baut ihre Raketen mit demselben Missile.gd wie der Spieler. Es gibt keine
## "Gegner-Rakete" mit eigenen Regeln — dieselbe Physik, dieselbe Suchkopf-Formel, nur
## eine andere Feindgruppe. Das ist der Grund, warum sich gegnerische Lenkwaffen genauso
## verhalten wie die eigenen und warum eine Verbesserung an einer Stelle beiden zugutekommt.
class_name SamSite
extends Node3D

# --- von _spawn gesetzt ----------------------------------------------------------------
var art := "ir"                 # "ir" oder "radar"

# Reichweite, Hoehenband und Nachladezeit je Art. Das Hoehenband ist wichtig: ganz tief
# fliegen ist eine gueltige Antwort auf eine Radarstellung, weil das Gelaende den Strahl
# bricht. Ohne Untergrenze waere Tiefflug wirkungslos.
const WERTE := {
	"ir": {
		"reichweite": 1500.0, "min_hoehe": 25.0, "nachladen": 7.0,
		"schub": 230.0, "brenndauer": 1.9, "cw": 0.00021, "max_g": 13.0,
		"lebensdauer": 13.0, "kegel": 50.0, "erfassung": 1900.0, "lenkfaktor": 4.0,
		"zuender": 11.0, "kraft": 7.0, "start": 70.0, "traegheit": 0.9,
	},
	# TRAEGHEIT 0.9 UND NICHT 3.5. Waehrend der Traegheitsphase wirken Koeder nicht — das
	# ist richtig so, aber bei 3,5 s deckte sie bei rund 600 m/s praktisch den GANZEN
	# Anflug ab. Gemessen: Dueppel aenderten die Trefferquote der Radarstellung um exakt
	# null Prozentpunkte, in jeder Lage. Auch 1,5 s reichten noch nicht — erst bei 0,9 s
	# bleibt genug Endanflug uebrig, dass eine Salve etwas ausrichtet (gemessen: von
	# 100 auf 40 Prozent im Fluchtflug).
	"radar": {
		"reichweite": 3300.0, "min_hoehe": 70.0, "nachladen": 11.0,
		"schub": 150.0, "brenndauer": 3.4, "cw": 0.00010, "max_g": 8.0,
		"lebensdauer": 26.0, "kegel": 26.0, "erfassung": 4600.0, "lenkfaktor": 3.3,
		"zuender": 16.0, "kraft": 15.0, "start": 60.0, "traegheit": 0.9,
	},
}

# QUERLAST — UND SIE IST BEWUSST KLEIN. Zuerst standen hier 24 g (IR) und 15 g (Radar),
# also die Werte moderner Lenkwaffen. Der Pruefstand hat daraufhin in JEDER Lage und mit
# jeder Gegenmassnahme "TREFFER" gemeldet: eine Rakete mit 24 g gegen ein Flugzeug, das
# 6 g zieht, gewinnt geometrisch immer, und dem Spieler bleibt nichts als zuzusehen.
#
# 13 g und 8 g sind die Groessenordnung frueher Boden-Luft-Raketen: gross, schnell,
# traege. Damit ist eine harte Kurve im richtigen Moment wieder eine Antwort — und die
# Gegenmassnahmen sind die zweite, nicht die einzige.

# Wie stark der Werfer nachfuehrt (rad/s). Bewusst traege — man SIEHT ihn drehen, und
# eine harte Kurve quer zu ihm bringt ihn kurz aus dem Tritt.
const NACHFUEHRUNG := 1.1
# Ab dieser Wolkendichte gilt der Spieler als gedeckt. Dieselbe Regel wie bei der Flak;
# eine Wolke soll ueberall dasselbe bedeuten.
const DECKUNG := 0.5

## Wird ausgelöst, wenn die Stellung zerstört wird — Main verrechnet die Prämie.
signal zerstoert(reward: int, pos: Vector3)

# LEBENSPUNKTE. Eine Stellung, die auf einen schiesst und selbst unverwundbar ist, ist
# kein Gegner, sondern ein Naturereignis. 14 heisst: eine schwere Lenkwaffe (13 bis 15)
# raeumt sie mit einem Schuss, Bordkanonen brauchen mehrere Anflüge — und jeder davon
# fuehrt durch ihren eigenen Wirkungsbereich.
var hp := 14.0
var _tot := false

var _kanzel: Node3D = null      # der drehbare Teil (Werfer + Antenne)
var _cd := 3.0                  # beim Start nicht sofort feuern
var _welt: Node3D = null


func _ready() -> void:
	_welt = get_parent()
	_bauen()
	_cd = randf_range(2.0, 6.0)
	# ALS ZIEL ANGEMELDET. Damit kann der Spieler sie aufschalten und bekaempfen — und
	# damit schliesst sich der Kreis: wer beschossen wird, kann zurueckschiessen.
	# targets_root zaehlt nur seine eigenen Kinder, die Wellenlogik bleibt also unberuehrt.
	add_to_group("target")
	# Der Werfer ist kalt, das Aggregat nicht: wenig Waerme, dafuer als Radarstellung ein
	# grosses Blechziel. Eine Radarlenkwaffe ist hier die natuerliche Wahl.
	set_meta("ir_signatur", 55.0)
	set_meta("radar_signatur", 620.0 if art == "radar" else 300.0)
	set_meta("hit_radius", 6.0)


## Treffer einstecken. Gleiche Signatur wie Target.hit — Missile ruft beides gleich auf.
func hit(dmg: float) -> void:
	if _tot:
		return
	hp -= dmg
	if hp > 0.0:
		return
	_tot = true
	_zerlegen()


func _zerlegen() -> void:
	zerstoert.emit(450 if art == "radar" else 300, global_position)
	if _welt != null and is_instance_valid(_welt):
		_start_effekt(global_position + Vector3(0, 4.0, 0))
	queue_free()


func _physics_process(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	var plane := get_tree().get_first_node_in_group("player") as Node3D
	if plane == null or not is_instance_valid(plane):
		return
	var w: Dictionary = WERTE[art]
	var zu: Vector3 = plane.global_position - global_position
	var d := zu.length()
	if d > float(w["reichweite"]) * 1.25:
		return

	# NACHFUEHREN, AUCH OHNE ZU SCHIESSEN. Der drehende Werfer ist die einzige Warnung,
	# die eine Stellung von sich aus gibt — man soll sie sehen koennen, bevor sie feuert.
	if is_instance_valid(_kanzel):
		# VORZEICHEN. Die Vorderseite eines Knotens zeigt in Godot auf -Z. Eine Drehung um
		# +Y bildet -Z auf (-sin, 0, -cos) ab; damit das gleich der Zielrichtung ist, muss
		# die Gierung atan2(-x, -z) lauten. Mit atan2(x, z) steht der Werfer exakt 180 Grad
		# verkehrt — sichtbar als Starter, der vom Ziel wegzeigt, und messbar daran, dass
		# die halbaktive Rakete NIE traf: sie wurde nie beleuchtet. Der Pruefstand
		# (tools/_sam_pruefstand.gd) meldete "Start ja, Treffer nein" in jedem Anflug.
		var ziel_gier := atan2(-zu.x, -zu.z)
		_kanzel.rotation.y = lerp_angle(_kanzel.rotation.y, ziel_gier, NACHFUEHRUNG * delta)
		# Entsprechend die Neigung: Drehung um +X hebt -Z um +sin an, also ohne Minus.
		var neigung := clampf(atan2(zu.y, Vector2(zu.x, zu.z).length()), -0.1, 1.2)
		_kanzel.rotation.x = lerp_angle(_kanzel.rotation.x, neigung, NACHFUEHRUNG * delta)

	if _tot or _cd > 0.0 or d > float(w["reichweite"]):
		return
	var hoehe := plane.global_position.y - global_position.y
	if hoehe < float(w["min_hoehe"]):
		return
	# Deckung in der Wolke: Main haengt die Dichte als Meta ans Flugzeug (siehe Flak).
	if float(plane.get_meta("wolken_dichte", 0.0)) > DECKUNG:
		return
	# WAERMESUCHER BRAUCHEN WAERME. Wer mit gezogenem Gas anschleicht, wird von einer
	# IR-Stellung nicht erfasst — das ist dieselbe Formel wie im Suchkopf, nur eine Stufe
	# frueher angewandt, damit die Stellung gar nicht erst startet.
	if art == "ir":
		# Methode ODER Meta — dieselbe Regel wie im Suchkopf (Missile._signal). Sonst
		# haengt das Verhalten davon ab, wie das Ziel zufaellig gebaut ist.
		var waerme := 0.0
		if plane.has_method("ir_signatur"):
			waerme = float(plane.call("ir_signatur"))
		elif plane.has_meta("ir_signatur"):
			waerme = float(plane.get_meta("ir_signatur"))
		else:
			waerme = 160.0
		# Signal am Werfer, gleiche Form wie Missile._signal. Der Schwellwert ist so
		# gewaehlt, dass Vollgas auf voller Reichweite gerade noch reicht.
		if waerme / maxf(d * d, 1.0) < 1.1e-4:
			return
	# SICHTLINIE. Eine Stellung, die durch Berge schiesst, macht Gelaende bedeutungslos —
	# und das Hoehenband oben waere nur noch eine willkuerliche Zahl statt der Aufforderung,
	# tief zu bleiben. Erst hier geprueft, weil ein Strahl teurer ist als jede Abfrage
	# davor und die meisten Bilder ohnehin an ihnen scheitern.
	if not _freie_sicht(plane):
		return
	_starten(plane, w)


## Steht etwas zwischen Werfer und Flugzeug?
##
## Ausserhalb des Physikschritts (Pruefstand) gilt die Sicht als frei: dort gibt es kein
## Gelaende, und direct_space_state waere gesperrt.
func _freie_sicht(plane: Node3D) -> bool:
	if not Engine.is_in_physics_frame():
		return true
	var welt := get_world_3d()
	if welt == null:
		return true
	var von := global_position + Vector3(0, 7.5, 0)
	var q := PhysicsRayQueryParameters3D.create(von, plane.global_position, 1)
	var tr := welt.direct_space_state.intersect_ray(q)
	if tr.is_empty():
		return true
	var wer = tr.get("collider")
	return wer is Node and (wer as Node).is_in_group("player")


func _starten(plane: Node3D, w: Dictionary) -> void:
	if _welt == null or not is_instance_valid(_welt):
		return
	var m := Missile.new()
	m.muster = "SAM-" + art.to_upper()
	m.sucher = art
	m.koeder_gruppe = "flare" if art == "ir" else "chaff"
	m.feind_gruppe = "player"
	m.schub = float(w["schub"])
	m.brenndauer = float(w["brenndauer"])
	m.cw = float(w["cw"])
	m.max_g = float(w["max_g"])
	m.lebensdauer = float(w["lebensdauer"])
	m.sucher_kegel = float(w["kegel"])
	m.erfassung = float(w["erfassung"])
	m.lenkfaktor = float(w["lenkfaktor"])
	m.zuender = float(w["zuender"])
	m.sprengkraft = float(w["kraft"])
	m.blast_dv = 30.0
	m.traegheitsphase = float(w["traegheit"])
	m.braucht_beleuchtung = (art == "radar")
	m.traeger = _kanzel if is_instance_valid(_kanzel) else self
	m.ziel = plane
	_welt.add_child(m)
	m.global_position = global_position + Vector3(0.0, 7.5, 0.0)
	# STEIL LOSGESCHOSSEN. Eine Rakete, die flach aus der Stellung faehrt, pfluegt durch
	# den naechsten Huegel. Der erste Impuls geht deshalb nach oben und wird erst von der
	# Lenkung auf das Ziel gezogen.
	var hin := (plane.global_position - m.global_position).normalized()
	# Weniger steil als zuerst (1.6): jeder Grad Aufrichtung ist Energie, die nicht in
	# Richtung Ziel geht. 0.9 raeumt den Startplatz und verschenkt wenig.
	m.v = (Vector3.UP * 0.9 + hin).normalized() * float(w["start"])
	_cd = float(w["nachladen"])
	_start_effekt(m.global_position)


# --- Bauwerk ---------------------------------------------------------------------------
func _bauen() -> void:
	var beton := StandardMaterial3D.new()
	beton.albedo_color = Color(0.42, 0.43, 0.41)
	beton.roughness = 0.9
	var stahl := StandardMaterial3D.new()
	stahl.albedo_color = Color(0.26, 0.29, 0.27) if art == "ir" else Color(0.30, 0.33, 0.36)
	stahl.metallic = 0.4
	stahl.roughness = 0.6

	# GROSS GENUG, UM SIE ZU SEHEN. Die erste Fassung war 7 m breit und 5 m hoch — aus
	# der Luft ein grauer Fleck, den man erst bemerkt, wenn die Rakete schon laeuft. Eine
	# Bedrohung, die man nicht kommen sieht, ist keine Entscheidung, sondern ein Unfall.
	# Jetzt: 13 m Bettung, ein Erdwall darum und Rampen, die aus der Silhouette lesbar
	# sind. Der Wall ist ausserdem das, was solche Stellungen in echt umgibt.
	_kasten(Vector3(0, 0.5, 0), Vector3(13.0, 1.0, 13.0), beton)      # Bettung
	var erde := StandardMaterial3D.new()
	erde.albedo_color = Color(0.34, 0.33, 0.26)
	erde.roughness = 0.95
	for i in 4:
		var w := TAU * float(i) / 4.0
		_kasten(Vector3(sin(w) * 8.0, 1.3, cos(w) * 8.0),
			Vector3(15.0 if i % 2 == 0 else 2.4, 2.6, 2.4 if i % 2 == 0 else 15.0), erde)
	_kanzel = Node3D.new()
	_kanzel.position = Vector3(0, 1.0, 0)
	add_child(_kanzel)
	_kasten_an(_kanzel, Vector3(0, 1.7, 0), Vector3(5.0, 3.4, 6.0), stahl)   # Drehteil

	if art == "ir":
		# Vierlingsstarter: vier Rohre nebeneinander, deutlich ueber das Drehteil hinaus.
		for i in 4:
			var x := -1.8 + float(i) * 1.2
			_kasten_an(_kanzel, Vector3(x, 4.0, -0.5), Vector3(0.7, 0.7, 5.6), stahl)
	else:
		# Zwei grosse Behaelter und die Antenne, die sie fuehrt.
		for sx in [-1.0, 1.0]:
			_kasten_an(_kanzel, Vector3(sx * 1.7, 4.2, -0.3), Vector3(1.2, 1.2, 8.4), stahl)
		var schuessel := MeshInstance3D.new()
		var zy := CylinderMesh.new()
		zy.top_radius = 3.0
		zy.bottom_radius = 3.0
		zy.height = 0.22
		zy.radial_segments = 14
		schuessel.mesh = zy
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.78, 0.80, 0.83)
		m.metallic = 0.3
		m.roughness = 0.45
		schuessel.material_override = m
		schuessel.rotation_degrees = Vector3(-78.0, 0.0, 0.0)
		schuessel.position = Vector3(0.0, 6.0, 1.2)
		_kanzel.add_child(schuessel)


func _kasten(pos: Vector3, groesse: Vector3, mat: Material) -> void:
	_kasten_an(self, pos, groesse, mat)


func _kasten_an(eltern: Node3D, pos: Vector3, groesse: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = groesse
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	eltern.add_child(mi)


func _start_effekt(punkt: Vector3) -> void:
	if _welt == null or not is_instance_valid(_welt):
		return
	var p := CPUParticles3D.new()
	p.amount = 90
	p.lifetime = 2.4
	p.one_shot = true
	p.explosiveness = 0.75
	p.local_coords = false
	p.spread = 60.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 22.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 5.0
	p.gravity = Vector3(0, 1.5, 0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.85, 0.84, 0.82, 0.6)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p.material_override = pm
	_welt.add_child(p)
	p.global_position = punkt
	p.emitting = true
	var t := p.create_tween()
	t.tween_interval(3.2)
	t.tween_callback(p.queue_free)
