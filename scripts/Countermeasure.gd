## Countermeasure.gd — Wärmefackel (Flare) und Düppel (Chaff).
##
## WARUM DAS HIER SO WENIG CODE IST. Ein Koeder taeuscht keinen Sucher — er STRAHLT nur.
## Ob eine Fackel wirkt, entscheidet nicht diese Datei, sondern Missile._signal(): dort
## werden alle Kandidaten im Blickfeld verglichen, und wer das staerkste Signal liefert,
## wird verfolgt. Eine Fackel ist deshalb nichts weiter als ein Objekt in der Gruppe
## "flare", das eine sehr grosse ir_signatur() meldet und diese schnell verliert.
##
## Daraus folgt alles Weitere von selbst, ohne eine einzige Sonderregel:
##
##  * Fackeln wirken nach HINTEN am besten. Sie fallen zurueck und liegen damit in
##    demselben Kegel, in dem auch die Duesen strahlen — genau dort, wo ein von hinten
##    anfliegender Waermesucher hinsieht.
##  * Sie wirken SPAET besser als frueh. Aus zwei Kilometern sind Flugzeug und Fackel fuer
##    den Sucher fast am selben Ort und die Entfernungsdaempfung trifft beide gleich; auf
##    den letzten hundert Metern liegt die Fackel dagegen deutlich naeher an der Rakete
##    als das Flugzeug, und ihr Signal gewinnt haushoch.
##  * Eine einzelne Fackel reicht selten. Deshalb wirft der Werfer sie paarweise.
##  * Duessel wirken nur gegen Radar, Fackeln nur gegen Waerme. Nicht weil es verboten
##    waere, sondern weil ein Radarsucher schlicht nicht in die Gruppe "flare" schaut.
##
## Die Zahlen unten sind gegen die Signaturen in AircraftBody abgestimmt (siehe dort).
class_name Countermeasure
extends Node3D

var art := "flare"                # "flare" (gegen IR) oder "chaff" (gegen Radar)
var v := Vector3.ZERO
var _alter := 0.0
var _dauer := 4.5
var _mi: MeshInstance3D = null
var _licht: OmniLight3D = null
var _rauch: CPUParticles3D = null

# Spitzenwerte der Signaturen — UND SIE SIND EINGEFLOGEN, NICHT GESCHAETZT.
#
# Beim ersten Ansatz standen hier 5200 und 9e5. Der Pruefstand
# (tools/_raketen_pruefstand.gd) hat daraufhin gemeldet: Trefferquote MIT Koedern null
# Prozent, bei allen drei Baumustern. Das ist kein starkes Gegenmittel, das ist ein
# Ausschalter — ein Spieler mit Fackeln waere gegen Waermesucher schlicht unverwundbar
# gewesen, und die ganze Waffengattung damit sinnlos.
#
# ZWEITER ANLAUF, nachdem das Protokoll des Pruefstands zeigte, woran es lag: bei 1400
# war eine Fackel schon IM AUGENBLICK DES AUSWURFS um den Faktor 2,57 staerker als das
# Flugzeug (260 mal Heckaspekt 2,1 = 546). Der Haltebonus des Suchers betraegt 2,4 — die
# Fackel gewann also sofort, noch bevor sie sich ueberhaupt vom Flugzeug getrennt hatte,
# und hatte den Bonus danach selbst.
#
# 950 liegt bei Faktor 1,74 und damit UNTER dem Haltebonus. Eine Fackel reisst den Sucher
# damit nicht mehr allein durch ihre Helligkeit herum, sondern erst, wenn Geometrie dazu
# kommt: wenn sie naeher an der Rakete liegt als das Flugzeug (Endanflug), oder wenn das
# Flugzeug kalt wird (Gas zurueck) oder quer abdreht. Genau das sind die Momente, in
# denen ein Pilot sie werfen soll.
const FLARE_SPITZE := 950.0
const CHAFF_SPITZE := 290.0
# Wie schnell die Wolke ihre Wirkung verliert. Kurz genug, dass Dauerfeuer nichts bringt.
const FLARE_ABKLINGEN := 2.6
const CHAFF_BLUEHT := 0.35        # Duessel braucht einen Moment, bis die Wolke steht


static func werfen(wurzel: Node3D, art_: String, pos: Vector3, start_v: Vector3) -> Countermeasure:
	var c := Countermeasure.new()
	c.art = art_
	c.v = start_v
	c._dauer = 4.5 if art_ == "flare" else 5.0
	wurzel.add_child(c)
	c.global_position = pos
	c.add_to_group(art_)
	return c


func _ready() -> void:
	_bau()


func _physics_process(delta: float) -> void:
	_alter += delta
	if _alter >= _dauer:
		queue_free()
		return
	# Beide bremsen hart ab und fallen zurueck — genau das ist ihre Wirkungsweise. Duessel
	# bremst staerker: eine Wolke aus Metallstreifen hat kaum Masse und viel Flaeche und
	# steht nach einer Sekunde praktisch in der Luft.
	var bremse := 1.9 if art == "chaff" else 0.85
	v -= v * bremse * delta
	# Fallen: die Fackel brennt und faellt, die Wolke sinkt kaum.
	v.y -= (9.8 if art == "flare" else 1.2) * delta
	global_position += v * delta
	_zeigen()


## Waermesignatur für IR-Suchköpfe. Sehr hell am Anfang, dann rasch weg.
func ir_signatur() -> float:
	if art != "flare":
		return 0.0
	var t := _alter / FLARE_ABKLINGEN
	return FLARE_SPITZE * exp(-t * t * 1.6)


## Rückstrahlfläche für Radarsuchköpfe. Braucht einen Moment zum Aufblühen.
func radar_signatur() -> float:
	if art != "chaff":
		return 0.0
	var auf := clampf(_alter / CHAFF_BLUEHT, 0.0, 1.0)
	var ab := exp(-maxf(_alter - CHAFF_BLUEHT, 0.0) * 0.55)
	return CHAFF_SPITZE * auf * ab


func _bau() -> void:
	_mi = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5 if art == "flare" else 1.4
	sm.height = sm.radius * 2.0
	sm.radial_segments = 8
	sm.rings = 5
	_mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if art == "flare":
		mat.albedo_color = Color(1.0, 0.95, 0.72, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.85, 0.45)
		mat.emission_energy_multiplier = 14.0
	else:
		mat.albedo_color = Color(0.86, 0.88, 0.94, 0.45)
	_mi.material_override = mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)

	if art == "flare":
		_licht = OmniLight3D.new()
		_licht.light_color = Color(1.0, 0.86, 0.5)
		_licht.light_energy = 6.0
		_licht.omni_range = 40.0
		_licht.shadow_enabled = false
		add_child(_licht)

	_rauch = CPUParticles3D.new()
	_rauch.amount = 30 if art == "flare" else 70
	_rauch.lifetime = 2.2 if art == "flare" else 3.4
	_rauch.local_coords = false
	_rauch.spread = 25.0 if art == "flare" else 180.0
	_rauch.initial_velocity_min = 0.5
	_rauch.initial_velocity_max = 3.0 if art == "flare" else 9.0
	_rauch.scale_amount_min = 0.4
	_rauch.scale_amount_max = 1.5 if art == "flare" else 3.0
	_rauch.gravity = Vector3(0, -0.8 if art == "flare" else 0.2, 0)
	var pm := StandardMaterial3D.new()
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.albedo_color = (Color(0.95, 0.92, 0.85, 0.5) if art == "flare"
		else Color(0.90, 0.93, 1.0, 0.30))
	_rauch.material_override = pm
	add_child(_rauch)


func _zeigen() -> void:
	var rest := 1.0 - clampf(_alter / _dauer, 0.0, 1.0)
	if is_instance_valid(_mi):
		var mat := _mi.material_override as StandardMaterial3D
		if art == "flare":
			# Flackern: eine brennende Fackel ist keine Gluehbirne.
			var fl := 0.75 + 0.25 * sin(_alter * 43.0)
			mat.emission_energy_multiplier = 14.0 * rest * fl
			mat.albedo_color.a = rest
			_mi.scale = Vector3.ONE * (0.7 + 0.5 * rest)
		else:
			# Die Wolke waechst und wird duenner.
			mat.albedo_color.a = 0.45 * rest
			_mi.scale = Vector3.ONE * (1.0 + 2.2 * clampf(_alter / 1.2, 0.0, 1.0))
	if is_instance_valid(_licht):
		_licht.light_energy = 6.0 * rest
