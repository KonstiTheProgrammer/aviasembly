## Missile.gd — ein gelenkter Flugkörper mit Suchkopf, Motor und Näherungszünder.
##
## WOFUER ES DIESE DATEI GIBT. Projectile.gd kann bereits "homing": es dreht jeden Frame
## ein Stueck auf das naechste Ziel zu. Das ist Verfolgungsflug (pure pursuit), und der hat
## eine Eigenschaft, die man im Spiel sofort merkt — er haengt einem kurvenden Ziel IMMER
## hinterher. Wer wegkurvt, wird nie getroffen; wer geradeaus fliegt, immer. Zwischen
## diesen beiden Zustaenden gibt es nichts, und deshalb fuehlt sich so eine Rakete nicht
## wie eine Waffe an, sondern wie ein Wuerfelwurf.
##
## Hier steht stattdessen das, was echte Lenkwaffen tun, und es sind drei Dinge:
##
##  1. PROPORTIONALNAVIGATION statt Verfolgung. Nicht "drehe auf das Ziel zu", sondern
##     "halte die SICHTLINIE zum Ziel drehfrei". Dreht sich die Linie zwischen Rakete und
##     Ziel, wird quer dazu beschleunigt, und zwar proportional zu dieser Drehrate. Das
##     Ergebnis ist Vorhalt: die Rakete fliegt dorthin, wo das Ziel SEIN WIRD. Drei Zeilen
##     Mathematik, und sie sind der Unterschied zwischen Spielzeug und Waffe.
##
##  2. MOTOR UND WIDERSTAND statt einer Zahl namens "Reichweite". Der Motor brennt ein
##     paar Sekunden und ist dann leer; danach zehrt die Rakete von ihrer Energie. Damit
##     ist Reichweite kein Wert in einer Tabelle, sondern eine FOLGE: von vorn auf ein
##     entgegenkommendes Ziel traegt dieselbe Rakete doppelt so weit wie von hinten auf
##     ein davonfliegendes. Genau daraus entsteht das Gefuehl, einen Schuss zu "verheizen".
##
##  3. EIN SUCHKOPF, DER SICH TAEUSCHEN LAESST. Der Sucher waehlt jeden Frame das
##     STAERKSTE Signal in seinem Blickfeld — nicht "das Ziel". Eine Fackel ist heisser als
##     ein Triebwerk, eine Dueppelwolke wirft mehr zurueck als ein Flugzeug. Dass
##     Gegenmassnahmen wirken, ist deshalb keine Sonderregel mit einer Wahrscheinlichkeit,
##     sondern faellt aus derselben Formel wie das Zielen selbst. Das ist der Grund, warum
##     Fackeln von hinten gut wirken und von vorn kaum: die Formel weiss nichts von
##     "wirkt", sie vergleicht nur Signale.
##
## Alles, was ein Baumuster unterscheidet — Reichweite, Wendigkeit, Suchkopfart,
## Anfaelligkeit — sind Felder auf diesem einen Skript. Es gibt keine Unterklassen, und
## das ist Absicht: eine neue Rakete ist ein Eintrag in einer Tabelle, kein neues Skript.
class_name Missile
extends Node3D

# --- BAUMUSTER: was diesen Flugkörper ausmacht ----------------------------------------
var muster := "ir_kurz"           # nur fuer Anzeige und Fehlersuche
var sucher := "ir"                # "ir" = Waermesuchkopf, "radar" = Radarsuchkopf
var feind_gruppe := "target"      # Gruppe, in der gueltige Ziele liegen
var koeder_gruppe := "flare"      # Gruppe der Koeder, die diesen Sucher stoeren

# --- FLUGLEISTUNG ---------------------------------------------------------------------
var schub := 420.0                # Beschleunigung waehrend des Brennens (m/s^2)
var brenndauer := 2.0             # wie lange der Motor laeuft (s)
# ZUENDVERZUG. Eine abgeworfene Waffe faellt erst aus der Aufhaengung und zuendet dann —
# sonst brennt der Motor unter der eigenen Tragflaeche. In dieser Spanne fliegt sie
# ballistisch und lenkt nicht: das ist der Grund, warum ein Abwurfstart im Tiefflug
# gefaehrlich ist.
var startverzug := 0.0
var cw := 0.0016                  # Widerstand: dv = -cw * v^2 * dt (1/m)
var max_g := 22.0                 # Querbeschleunigung, in g
var lebensdauer := 22.0           # Selbstzerlegung (s) — begrenzt die absolute Reichweite
var schwerkraft := 6.0            # abgeschwaecht: der Koerper traegt sich zum Teil selbst

# --- SUCHKOPF -------------------------------------------------------------------------
var sucher_kegel := 50.0          # halber Oeffnungswinkel in Grad (Blickfeld)
var erfassung := 2600.0           # Entfernung, bis zu der ueberhaupt erfasst wird (m)
var lenkfaktor := 3.6             # N der Proportionalnavigation (3 bis 5 ist der Bereich)
# TRAEGHEIT DES SUCHKOPFS. Ohne sie springt der Sucher bei zwei fast gleich starken
# Signalen jeden Frame hin und her und die Rakete fliegt Zickzack ins Nichts. Das aktuelle
# Ziel bekommt einen Bonus; ein Koeder muss also DEUTLICH staerker sein, um sie zu holen.
var haltebonus := 3.2
# TRAEGHEITSPHASE (Mittelflug). So lange folgt die Rakete dem Ziel, das ihr beim Start
# MITGEGEBEN wurde, ohne dass ihr Suchkopf es sehen muss.
#
# DAS IST KEINE BEQUEMLICHKEIT, SONDERN NOTWENDIGKEIT — und der Pruefstand hat es
# erzwungen: eine Raketenstellung schiesst steil los, damit sie nicht in den naechsten
# Huegel pflueg, und steht damit rund 50 Grad neben der Sichtlinie zum Ziel. Der
# Radarsuchkopf hat aber nur 26 Grad Blickfeld. Er sah sein Ziel also NIE, gab nach der
# Blindgeduld auf und flog ballistisch weiter: gemessen "Start ja, Treffer nein" in jedem
# einzelnen Anflug.
#
# Echte Lenkwaffen loesen das genauso — Mittelflug traegheitsgefuehrt, Suchkopf erst im
# Endanflug. Nebenwirkung, und auch die ist richtig: Koeder wirken in dieser Phase nicht.
# Dueppel auf grosse Entfernung sind vergeudet, im Endanflug sind sie gefaehrlich.
var traegheitsphase := 1.0
# NUR RADAR: dieser Sucher hoert nur, was der Traeger anstrahlt (halbaktiv). Verliert der
# Schuetze die Aufschaltung, faellt die Lenkung aus. Das ist der Preis der grossen
# Reichweite und der Grund, warum man nach dem Schuss die Nase auf dem Ziel halten muss.
var braucht_beleuchtung := false
var traeger: Node3D = null        # wer geschossen hat (fuer Beleuchtung und Eigenschutz)

# --- GEFECHTSKOPF ---------------------------------------------------------------------
var zuender := 11.0               # Naeherungszuender: Radius, in dem gezuendet wird (m)
var sprengkraft := 9.0            # Schaden am Ziel
var blast_dv := 26.0              # Wucht auf ein getroffenes Flugzeug

# --- LAUFENDER ZUSTAND ----------------------------------------------------------------
var v := Vector3.ZERO             # Geschwindigkeit (m/s), Weltkoordinaten
var ziel: Node3D = null           # was der Sucher gerade verfolgt (kann ein Koeder sein)
var _alter := 0.0
var _brennt := true
var _letzte_sicht := Vector3.ZERO # Sichtlinie des Vorframes (fuer die Drehrate)
var _hat_sicht := false
var _blind_seit := 0.0            # wie lange ohne Signal (Radar: Beleuchtung verloren)
var _tot := false
var _rauch: CPUParticles3D = null
var _flamme: MeshInstance3D = null
var _licht: OmniLight3D = null

# Wie lange eine halbaktive Rakete ohne Beleuchtung weiterfliegt, bevor sie aufgibt. Nicht
# null, damit ein kurzes Verrutschen der Nase den Schuss nicht sofort wegwirft.
const BLIND_GEDULD := 1.6
# Ab hier gilt ein Ziel als getroffen, egal was der Zuender sagt (Direkttreffer).
const DIREKT := 2.0


func _ready() -> void:
	# In der Gruppe, damit die Anflugwarnung des Cockpits sie findet, ohne die ganze
	# Szene durchsuchen zu muessen.
	add_to_group("missile")
	_bau_visuell()
	if v.length() < 1.0:
		v = -global_transform.basis.z * 60.0
	_richte_aus()


func _physics_process(delta: float) -> void:
	if _tot:
		return
	_alter += delta
	if _alter >= lebensdauer:
		_selbstzerlegung()
		return
	_brennt = _alter >= startverzug and _alter < startverzug + brenndauer

	if _alter >= startverzug:
		_sucher_takt(delta)
		_lenken(delta)
	_antrieb(delta)

	var vor := global_position
	global_position += v * delta
	_richte_aus()
	_flamme_zeigen()

	if _treffer_pruefen(vor, global_position):
		return
	if _gelaende_treffer(vor, global_position):
		return
	# Notbremse, falls der Strahl einmal nichts findet (Chunk noch nicht geladen).
	if global_position.y < -30.0:
		_selbstzerlegung()


## Schlägt die Rakete in Gelände oder Bauwerk ein?
##
## OHNE DAS FLIEGEN LENKWAFFEN DURCH BERGE, und das ist nicht nur haesslich: es macht eine
## Verteidigung wirkungslos, die anderswo ausdruecklich dokumentiert ist. In SamSite steht
## "Tiefflug hinter den Flanken" als Antwort auf eine Radarstellung — das gilt nur, wenn
## der Berg auch etwas aufhaelt. Vorher zerlegte sich eine Rakete erst 30 m unter dem
## Meeresspiegel; alles darueber durchflog sie.
##
## Der Strahl laeuft ueber die Strecke des letzten Frames auf Ebene 1, auf die
## TerrainWorld seine Chunk-Koerper legt (siehe _attach_chunk).
##
## NUR IM PHYSIKSCHRITT. direct_space_state ist ausserhalb davon gesperrt; die
## Pruefstaende takten diese Funktion von Hand aus _process und wuerden sonst eine
## Fehlermeldung je Frame erzeugen. Ohne Physikwelt gibt es dort auch kein Gelaende, die
## Messung verliert also nichts.
func _gelaende_treffer(a: Vector3, b: Vector3) -> bool:
	if not Engine.is_in_physics_frame():
		return false
	var welt := get_world_3d()
	if welt == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	var tr := welt.direct_space_state.intersect_ray(q)
	if tr.is_empty():
		return false
	var wer = tr.get("collider")
	# Das eigene Ziel ist kein Gelaende — dafuer ist der Naeherungszuender zustaendig,
	# der schon eine Zeile vorher gelaufen ist.
	if wer is Node and (wer as Node).is_in_group(feind_gruppe):
		return false
	_tot = true
	_explosion(tr["position"])
	queue_free()
	return true


# --- SUCHKOPF: welches Signal ist das staerkste? --------------------------------------
#
# Das ist das Herz der Gegenmassnahmen. Es gibt keine Wuerfelprobe "Fackel wirkt zu 40 %"
# — es gibt eine Signalstaerke je Kandidat, und der Sucher nimmt die groesste. Ob eine
# Fackel wirkt, haengt damit von Entfernung, Blickwinkel und Alter der Fackel ab, ganz
# von selbst.
func _sucher_takt(delta: float) -> void:
	# Mittelflug: das mitgegebene Ziel gilt, ohne Blickfeld und ohne Koedervergleich.
	if _alter < startverzug + traegheitsphase and is_instance_valid(ziel) \
			and ziel.is_in_group(feind_gruppe):
		_blind_seit = 0.0
		return
	var kandidaten: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(feind_gruppe):
		if n is Node3D and is_instance_valid(n):
			kandidaten.append(n)
	for n in get_tree().get_nodes_in_group(koeder_gruppe):
		if n is Node3D and is_instance_valid(n):
			kandidaten.append(n)

	var kegel := cos(deg_to_rad(sucher_kegel))
	var blick := (v.normalized() if v.length() > 1.0 else -global_transform.basis.z)
	var bestes: Node3D = null
	var beste_staerke := 0.0
	for n in kandidaten:
		var zu: Vector3 = n.global_position - global_position
		var d := zu.length()
		if d < 0.5 or d > erfassung:
			continue
		# BLICKFELD. Ein Suchkopf sitzt in der Spitze und sieht nach vorn; was seitlich
		# oder hinter der Rakete liegt, existiert fuer ihn nicht. Genau deshalb kann man
		# einer Rakete durch eine harte Kurve aus dem Blickfeld gehen.
		if blick.dot(zu / d) < kegel:
			continue
		if braucht_beleuchtung and not _wird_beleuchtet(n):
			continue
		var s := _signal(n, d, zu / d)
		if n == ziel:
			s *= haltebonus
		if s > beste_staerke:
			beste_staerke = s
			bestes = n

	if bestes != null:
		ziel = bestes
		_blind_seit = 0.0
	else:
		_blind_seit += delta
		# Nach der Geduldsspanne ist die Aufschaltung endgueltig weg: die Rakete fliegt
		# ballistisch weiter und zerlegt sich am Ende ihrer Lebensdauer.
		if _blind_seit > BLIND_GEDULD:
			ziel = null


## Signalstaerke eines Kandidaten. Grosse Zahl = wird verfolgt.
##
## Die absoluten Werte sind bedeutungslos — es wird nur VERGLICHEN. Wichtig sind die
## Exponenten: beim Waermesucher faellt das Signal mit dem Quadrat der Entfernung, beim
## Radar mit der vierten Potenz (Hin- und Rueckweg). Daraus folgt von selbst, dass Dueppel
## dicht an der Rakete verheerend wirken und weit weg fast nicht.
func _signal(n: Node3D, d: float, richtung: Vector3) -> float:
	if sucher == "ir":
		var waerme := 1.0
		if n.has_method("ir_signatur"):
			waerme = float(n.call("ir_signatur"))
		elif n.has_meta("ir_signatur"):
			waerme = float(n.get_meta("ir_signatur"))
		else:
			waerme = 40.0
		# HECKASPEKT — UND DAS VORZEICHEN WAR ZUERST FALSCH HERUM.
		#
		# Ein Triebwerk strahlt nach HINTEN, also entlang +basis.z des Ziels. Eine Rakete
		# sieht diese Duese genau dann, wenn sie selbst in dieser Halbebene steht. Sie
		# steht dort, wenn (Rakete - Ziel) * basis.z > 0 ist — und "richtung" zeigt von
		# der Rakete ZUM Ziel, also genau andersherum. Deshalb das Minus.
		#
		# Mit dem falschen Vorzeichen lieferte ein von hinten verfolgtes Flugzeug den
		# KLEINSTEN statt den groessten Wert, und der Pruefstand meldete: Fackeln wirken zu
		# 100 Prozent, immer. Der Fehler war im Bild nicht zu sehen — nur in der Messung.
		#
		# KOEDER BEKOMMEN KEINEN ASPEKT. Eine brennende Fackel strahlt in alle Richtungen;
		# ihr eine Vorzugsrichtung zu geben haette sie von der zufaelligen Ausrichtung
		# eines Knotens abhaengig gemacht, der gar keine hat.
		var heck := 1.0
		if not n.is_in_group(koeder_gruppe):
			var nach_hinten: Vector3 = n.global_transform.basis.z.normalized()
			heck = 0.35 + 1.75 * maxf(0.0, -richtung.dot(nach_hinten))
		return waerme * heck / maxf(d * d, 1.0)
	# Radar: Rueckstrahlflaeche, Signal faellt mit d^4.
	var rcs := 1.0
	if n.has_method("radar_signatur"):
		rcs = float(n.call("radar_signatur"))
	elif n.has_meta("radar_signatur"):
		rcs = float(n.get_meta("radar_signatur"))
	else:
		rcs = 60.0
	var d2 := maxf(d * d, 1.0)
	return rcs / (d2 * d2) * 1.0e10


## Halbaktiv: sieht der Traeger diesen Kandidaten ueberhaupt an? Ohne Beleuchtung gibt es
## nichts zu empfangen. Der Kegel ist bewusst weiter als der Aufschaltkegel im Cockpit —
## man soll die Nase grob halten muessen, nicht auf das Pixel genau.
func _wird_beleuchtet(n: Node3D) -> bool:
	if traeger == null or not is_instance_valid(traeger):
		return false
	var zu: Vector3 = n.global_position - traeger.global_position
	var d := zu.length()
	if d < 1.0 or d > erfassung * 1.35:
		return false
	var nase := -traeger.global_transform.basis.z.normalized()
	return nase.dot(zu / d) > cos(deg_to_rad(38.0))


# --- LENKUNG: Proportionalnavigation ---------------------------------------------------
#
# a_quer = N * V_naeherung * Omega, wobei Omega die DREHRATE DER SICHTLINIE ist.
#
# Anschaulich: bleibt das Ziel im Blick immer an derselben Stelle und wird nur groesser,
# stimmt der Kurs — dann ist Omega null und es wird nicht gelenkt. Wandert es aus, wird
# quer dazu beschleunigt, bis es wieder steht. Genau so haelt man beim Autofahren auf eine
# Kreuzung zu, an der ein anderer Wagen ankommt: bewegt er sich im Seitenfenster nicht,
# stossen beide zusammen.
func _lenken(delta: float) -> void:
	if ziel == null or not is_instance_valid(ziel):
		_hat_sicht = false
		return
	var zu: Vector3 = ziel.global_position - global_position
	var d := zu.length()
	if d < 0.5:
		return
	var sicht := zu / d
	if not _hat_sicht:
		_letzte_sicht = sicht
		_hat_sicht = true
		return
	# Drehrate der Sichtlinie als Vektor (Achse * rad/s).
	var omega := _letzte_sicht.cross(sicht) / maxf(delta, 0.0001)
	_letzte_sicht = sicht
	# Naeherungsgeschwindigkeit: wie schnell schliesst sich der Abstand?
	var v_ziel := Vector3.ZERO
	if ziel is RigidBody3D:
		v_ziel = (ziel as RigidBody3D).linear_velocity
	elif ziel.has_method("get_velocity"):
		v_ziel = ziel.call("get_velocity")
	elif ziel.has_meta("vel"):
		v_ziel = ziel.get_meta("vel")
	var v_nae := maxf((v - v_ziel).dot(sicht), 30.0)
	var a := omega.cross(sicht) * (lenkfaktor * v_nae)
	# Nur QUER zur eigenen Bahn steuern — eine Rakete kann nicht bremsen oder Gas geben,
	# ihre Flossen erzeugen ausschliesslich Querkraft.
	var laengs := v.normalized()
	a -= laengs * a.dot(laengs)
	var grenze := max_g * 9.81
	if a.length() > grenze:
		a = a.normalized() * grenze
	v += a * delta


func _antrieb(delta: float) -> void:
	var richtung := v.normalized() if v.length() > 1.0 else -global_transform.basis.z
	if _alter < startverzug:
		# Freier Fall aus der Aufhaengung: volle Schwerkraft, kein Schub, keine Lenkung.
		v.y -= 9.81 * delta
		return
	if _brennt:
		v += richtung * schub * delta
	# Widerstand waechst mit dem Quadrat — deshalb wird eine ausgebrannte Rakete schnell
	# langsam und ist irgendwann nicht mehr gefaehrlich, ohne dass das jemand abfragt.
	var sp := v.length()
	v -= richtung * (cw * sp * sp) * delta
	v.y -= schwerkraft * delta


func _richte_aus() -> void:
	if v.length_squared() < 1.0:
		return
	# Der Koerper zeigt in Flugrichtung. look_at braucht ein Ziel, keine Richtung.
	var oben := Vector3.UP
	if absf(v.normalized().dot(Vector3.UP)) > 0.99:
		oben = Vector3.FORWARD
	look_at(global_position + v, oben)


# --- TREFFER --------------------------------------------------------------------------
#
# Geprueft wird gegen die STRECKE des letzten Frames, nicht gegen den Punkt. Bei 600 m/s
# und 60 Bildern legt eine Rakete zehn Meter je Frame zurueck; eine reine Punktabfrage
# wuerde durch jedes Ziel hindurchspringen, das kleiner als das ist.
func _treffer_pruefen(a: Vector3, b: Vector3) -> bool:
	var beste: Node3D = null
	var beste_d := 1.0e20
	for n in get_tree().get_nodes_in_group(feind_gruppe):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var p: Vector3 = (n as Node3D).global_position
		var d := _abstand_zu_strecke(p, a, b)
		if d < beste_d:
			beste_d = d
			beste = n
	if beste == null:
		return false
	var radius := zuender
	if beste.has_meta("hit_radius"):
		radius += float(beste.get_meta("hit_radius"))
	elif "hit_radius" in beste:
		radius += float(beste.get("hit_radius"))
	if beste_d > radius:
		return false
	_detonieren(beste)
	return true


static func _abstand_zu_strecke(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _detonieren(getroffen: Node3D) -> void:
	if _tot:
		return
	_tot = true
	var punkt := global_position
	if getroffen.has_method("hit"):
		getroffen.call("hit", sprengkraft)
	elif getroffen.has_method("take_blast"):
		getroffen.call("take_blast", punkt, zuender * 2.0, blast_dv)
	_explosion(punkt)
	queue_free()


func _selbstzerlegung() -> void:
	if _tot:
		return
	_tot = true
	_explosion(global_position)
	queue_free()


# --- DARSTELLUNG -----------------------------------------------------------------------
func _bau_visuell() -> void:
	var koerper := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.055
	cy.bottom_radius = 0.075
	cy.height = 1.5
	cy.radial_segments = 8
	koerper.mesh = cy
	# Der Zylinder steht in Godot aufrecht; die Rakete fliegt nach -Z.
	koerper.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.80, 0.81, 0.84) if sucher == "ir" else Color(0.62, 0.66, 0.72)
	mat.metallic = 0.5
	mat.roughness = 0.45
	koerper.material_override = mat
	koerper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(koerper)

	# Flossen: vier schmale Platten am Heck. Sie tun nichts fuer die Physik, aber ohne sie
	# ist eine Rakete im Bild ein fliegender Stift.
	for i in 4:
		var f := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.03, 0.26, 0.30)
		f.mesh = bm
		f.material_override = mat
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.rotation_degrees = Vector3(0.0, 0.0, 90.0 * float(i))
		f.position = Vector3(
			sin(TAU * float(i) / 4.0) * 0.14,
			cos(TAU * float(i) / 4.0) * 0.14, 0.62)
		add_child(f)

	_flamme = MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.16
	fm.height = 0.32
	fm.radial_segments = 8
	fm.rings = 4
	_flamme.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.72, 0.25)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.62, 0.20)
	fmat.emission_energy_multiplier = 6.0
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flamme.material_override = fmat
	_flamme.position = Vector3(0.0, 0.0, 0.95)
	_flamme.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flamme)

	_licht = OmniLight3D.new()
	_licht.light_color = Color(1.0, 0.72, 0.35)
	_licht.light_energy = 3.0
	_licht.omni_range = 22.0
	_licht.shadow_enabled = false
	_licht.position = Vector3(0.0, 0.0, 0.9)
	add_child(_licht)

	_rauch = CPUParticles3D.new()
	_rauch.amount = 42
	_rauch.lifetime = 1.6
	_rauch.local_coords = false
	_rauch.direction = Vector3(0, 0, 1)
	_rauch.spread = 6.0
	_rauch.initial_velocity_min = 1.0
	_rauch.initial_velocity_max = 4.0
	_rauch.scale_amount_min = 0.5
	_rauch.scale_amount_max = 1.4
	_rauch.gravity = Vector3(0, 0.6, 0)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.88, 0.88, 0.90, 0.55)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_rauch.material_override = pm
	_rauch.position = Vector3(0.0, 0.0, 0.9)
	add_child(_rauch)


func _flamme_zeigen() -> void:
	if is_instance_valid(_flamme):
		_flamme.visible = _brennt
		if _brennt:
			var p := 1.0 + 0.25 * sin(_alter * 61.0)
			_flamme.scale = Vector3(p, p, 1.6 + 0.5 * sin(_alter * 47.0))
	if is_instance_valid(_licht):
		_licht.light_energy = 3.0 if _brennt else 0.0
	if is_instance_valid(_rauch):
		_rauch.emitting = _brennt


func _explosion(punkt: Vector3) -> void:
	var wurzel := get_parent()
	if wurzel == null or not is_instance_valid(wurzel):
		return
	var blitz := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 10
	sm.rings = 6
	blitz.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.45, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.62, 0.2)
	mat.emission_energy_multiplier = 8.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blitz.material_override = mat
	blitz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(blitz)
	blitz.global_position = punkt
	blitz.scale = Vector3.ONE * (zuender * 0.25)
	var tw := blitz.create_tween()
	tw.set_parallel(true)
	tw.tween_property(blitz, "scale", Vector3.ONE * (zuender * 1.5), 0.28)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.32)
	tw.chain().tween_callback(blitz.queue_free)
