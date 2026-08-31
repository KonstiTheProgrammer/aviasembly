## PRUEFSTAND FUER LENKWAFFEN — was können sie wirklich?
##
## WARUM ES DAS BRAUCHT. Reichweite, Wendigkeit und Trefferquote einer Rakete stehen
## nirgends in einer Zahl; sie FOLGEN aus Schub, Brenndauer, Widerstand, Querlast und
## Lenkgesetz. Man kann sie deshalb nicht in eine Tabelle schreiben, man kann sie nur
## messen. Ohne dieses Werkzeug waeren alle Werte in FlightController.LENKWAFFEN geraten,
## und der Kommentar daneben waere eine Behauptung.
##
## Gemessen wird in vier Lagen, und jede beantwortet eine Frage, die im Gefecht zaehlt:
##
##   SPITZE       Wie schnell wird sie? (Bestimmt, wie viel Vorwarnzeit das Ziel hat.)
##   VON VORN     Reichweite gegen ein entgegenkommendes Ziel.
##   VON HINTEN   Reichweite gegen ein davonfliegendes Ziel. Der Unterschied zu "von vorn"
##                ist die Kernaussage ueber jede Lenkwaffe — er entsteht ganz von selbst
##                aus Motor und Luftwiderstand und wird nirgends eingestellt.
##   AUSWEICHEN   Trefferquote gegen ein Ziel, das mit 6 g quer wegzieht.
##   FACKELN      dieselbe Lage, aber das Ziel wirft Koeder. Die Differenz ist die
##                Wirksamkeit der Gegenmassnahme — auch sie ist nirgends eingestellt,
##                sondern faellt aus dem Signalvergleich im Suchkopf.
##
## Godot --headless --path . --script res://tools/_raketen_pruefstand.gd
extends SceneTree

const DT := 1.0 / 60.0
const MAX_SCHRITTE := 2400          # 40 s Flugzeit reichen fuer jede Lage

var f := 0
var _welt: Node3D = null
var _spec: Dictionary = {}


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	_welt = Node3D.new()
	root.add_child(_welt)
	# Die Baumustertabelle liegt in FlightController; sie ist die eine Quelle.
	_spec = FlightController.LENKWAFFEN

	print("Baumuster       | Spitze | von vorn | von hinten | frei | 1 Salve | Kassette")
	print("----------------+--------+----------+------------+------+---------+---------")
	for typ in ["missile", "missile_heavy", "missile_drop"]:
		var sp: Dictionary = _spec[typ]
		var spitze := _spitzentempo(typ)
		# VORZEICHEN: Die Rakete fliegt nach -Z, das Ziel steht bei -dist. Ein Ziel mit
		# POSITIVER z-Geschwindigkeit kommt ihr also entgegen. Beim ersten Lauf stand es
		# andersherum, und die Messung meldete groessere Reichweite von hinten als von
		# vorn — physikalisch unmoeglich und damit der Beweis, dass die Achse falsch war.
		var vorn := _reichweite(typ, 220.0)
		var hinten := _reichweite(typ, -220.0)
		var frei := _trefferquote(typ, 0)
		var salve := _trefferquote(typ, 1)
		var alles := _trefferquote(typ, 2)
		print("%-15s | %4.0f m/s | %6.0f m | %8.0f m | %3.0f %% | %5.0f %% | %6.0f %%"
			% [String(sp["name"]), spitze, vorn, hinten,
				frei * 100.0, salve * 100.0, alles * 100.0])
	_diagnose("missile")
	print("\n(von vorn = Ziel kommt mit 220 m/s entgegen, von hinten = flieht mit 220 m/s.")
	print(" Reichweite = groesste Startentfernung, bei der noch getroffen wird; die")
	print(" Messung endet bei 6000 m — ein Wert von 6000 heisst also 'mindestens'.")
	print(" Im Spiel begrenzt ohnehin die Erfassung, wie weit man ueberhaupt schiessen kann:")
	print(" 1700 m bei IR-KURZ, 4200 m bei RADAR-MITTEL, 2500 m bei IR-SCHWER.)")
	quit()
	return true


## EIN Gefecht im Zeitlupenprotokoll: was verfolgt der Suchkopf, und wie stark ist
## welches Signal? Ohne diese Ausgabe bleibt "Fackeln wirken zu 100 Prozent" ein Befund
## ohne Ursache — und man dreht an Zahlen, die gar nicht schuld sind.
func _diagnose(typ: String) -> void:
	print("\n--- Protokoll: %s, Ziel wirft EINE Salve, Start 900 m ---"
		% String(_spec[typ]["name"]))
	print("  t    Abstand  Sucher-Ziel   Signal(Ziel)  Signal(Koeder)")
	_protokoll = true
	_durchgang(typ, 900.0, -60.0, 6.0, 1)
	_protokoll = false


## Ein Durchgang. Gibt zurück: true = getroffen.
##
## ziel_v: Geschwindigkeit des Ziels laengs der Schussachse (negativ = kommt entgegen).
## quer_g: Querbeschleunigung des Ziels (Ausweichmanoever).
## koeder: 0 = keine, 1 = EINE Salve 1,5 s vor dem Einschlag (so wirft ein Pilot),
##         2 = Dauerwurf alle 0,45 s (die ganze Kassette raus).
func _durchgang(typ: String, dist: float, ziel_v: float, quer_g: float, koeder: int) -> bool:
	var sp: Dictionary = _spec[typ]
	var traeger := Node3D.new()
	_welt.add_child(traeger)
	traeger.global_position = Vector3.ZERO
	# Der Traeger schaut nach -Z, also genau auf das Ziel — sonst schaltet eine halbaktive
	# Rakete sofort ab, weil sie nicht beleuchtet wird.
	traeger.look_at(Vector3(0, 0, -1000.0), Vector3.UP)

	var ziel := Node3D.new()
	ziel.add_to_group("target")
	ziel.set_meta("ir_signatur", 260.0)      # Flugzeug mit Vollgas
	# 82 = was AircraftBody.radar_signatur bei rund 30 Bauteilen liefert. Vorher stand
	# hier 40, und damit wurden Dueppel gegen einen anderen Massstab kalibriert als im
	# Stellungspruefstand — sie wirkten dort und hier nicht.
	ziel.set_meta("radar_signatur", 82.0)
	ziel.set_meta("hit_radius", 3.0)
	_welt.add_child(ziel)
	ziel.global_position = Vector3(0, 0, -dist)
	var zv := Vector3(0, 0, ziel_v)
	ziel.set_meta("vel", zv)

	var m := Missile.new()
	m.muster = String(sp["name"])
	m.sucher = String(sp["sucher"])
	m.koeder_gruppe = String(sp["koeder"])
	m.feind_gruppe = "target"
	m.schub = float(sp["schub"])
	m.brenndauer = float(sp["brenndauer"])
	m.cw = float(sp["cw"])
	m.max_g = float(sp["max_g"])
	m.lebensdauer = float(sp["lebensdauer"])
	m.schwerkraft = 0.0                       # im Pruefstand waagerecht, ohne Fallbogen
	m.sucher_kegel = float(sp["kegel"])
	m.erfassung = float(sp["erfassung"])
	m.lenkfaktor = float(sp["lenkfaktor"])
	m.zuender = float(sp["zuender"])
	m.braucht_beleuchtung = bool(sp.get("beleuchtung", false))
	m.startverzug = float(sp.get("abwurf", 0.0))
	m.traeger = traeger
	m.ziel = ziel
	_welt.add_child(m)
	m.global_position = Vector3(0, 0, -2.0)
	m.v = Vector3(0, 0, -float(sp["start_v"]) - 150.0)   # Traegertempo 150 m/s

	var getroffen := false
	var koeder_uhr := 0.0
	_salve_raus = false
	for i in MAX_SCHRITTE:
		if not is_instance_valid(m):
			break
		# Ziel bewegen. Das Ausweichen zieht quer zur Schussachse.
		if quer_g > 0.0:
			zv += Vector3(quer_g * 9.81, 0, 0) * DT
		ziel.global_position += zv * DT
		ziel.set_meta("vel", zv)
		# AUSRICHTEN. Der Heckaspekt im Suchkopf liest basis.z des Ziels — ein Knoten mit
		# Einheitsbasis "fliegt" also immer nach -Z, egal wohin er sich bewegt, und die
		# Messung waere Unsinn.
		if zv.length() > 1.0:
			ziel.look_at(ziel.global_position + zv, Vector3.UP)
		# Der Traeger haelt die Nase auf dem Ziel (halbaktive Beleuchtung).
		traeger.look_at(ziel.global_position, Vector3.UP)
		# WANN GEWORFEN WIRD, ist die halbe Wirkung. Eine Salve zur falschen Zeit ist
		# verschenkt; deshalb misst der Pruefstand den geuebten Wurf (Modus 1) getrennt
		# vom Leerraeumen der Kassette (Modus 2).
		var wurf := false
		if koeder == 2:
			koeder_uhr -= DT
			if koeder_uhr <= 0.0:
				koeder_uhr = 0.45
				wurf = true
		elif koeder == 1 and not _salve_raus:
			var abst_j := m.global_position.distance_to(ziel.global_position)
			var nae_j := (m.v - zv).dot(
				(ziel.global_position - m.global_position).normalized())
			if nae_j > 1.0 and abst_j / nae_j < 1.5:
				wurf = true
				_salve_raus = true
		if wurf:
				var art := "flare" if String(sp["sucher"]) == "ir" else "chaff"
				var c := Countermeasure.werfen(_welt, art,
					ziel.global_position + Vector3(0, -1.0, 2.0), zv * 0.8)
				# Der Pruefstand laeuft in Handtakt: die Koeder muessen mitgeschritten
				# werden, sonst altern sie nie und bleiben ewig gleich hell.
				_koeder.append(c)
		for c2 in _koeder:
			if is_instance_valid(c2):
				c2._physics_process(DT)
		m._physics_process(DT)
		if _protokoll and i % 15 == 0 and not m._tot:
			var abst := m.global_position.distance_to(ziel.global_position)
			var was := "—"
			if is_instance_valid(m.ziel):
				was = "ZIEL" if m.ziel == ziel else "KOEDER"
			var richtung := (ziel.global_position - m.global_position).normalized()
			var s_ziel: float = m._signal(ziel, maxf(abst, 1.0), richtung)
			var s_koe := 0.0
			for ck in _koeder:
				if is_instance_valid(ck) and ck.get_parent() != null:
					var dk: float = m.global_position.distance_to(ck.global_position)
					var rk: Vector3 = (ck.global_position - m.global_position).normalized()
					s_koe = maxf(s_koe, m._signal(ck, maxf(dk, 1.0), rk))
			print("%5.2f  %7.0f  %-12s  %11.5f  %11.5f"
				% [float(i) * DT, abst, was, s_ziel, s_koe])
		# NICHT ueber is_instance_valid pruefen! queue_free() wirkt erst am Ende eines
		# echten Frames, und dieser Pruefstand taktet von Hand — der Knoten bliebe also
		# bis zum Schluss "gueltig" und es gaebe nie einen Treffer. Das Flag _tot wird
		# dagegen sofort in _detonieren gesetzt.
		if m._tot:
			getroffen = m.global_position.distance_to(ziel.global_position) \
				<= float(sp["zuender"]) + 4.0
			break

	# SOFORT AUS DER GRUPPE UND AUS DEM BAUM, nicht per queue_free. Dieselbe Falle wie
	# oben, nur schlimmer: ein per queue_free "geloeschtes" Ziel bleibt im Handtakt in der
	# Gruppe "target" liegen, und der naechste Durchgang findet auf seinem Weg ein Dutzend
	# Altziele, an denen er zuendet. Genau daran ist die erste Messung gescheitert — nur
	# der allererste Lauf traf, alle folgenden zerlegten sich an Leichen.
	for c3 in _koeder:
		if is_instance_valid(c3):
			_weg(c3)
	_koeder.clear()
	if is_instance_valid(m):
		_weg(m)
	_weg(ziel)
	_weg(traeger)
	return getroffen


## Knoten sofort und restlos entfernen: erst aus allen Gruppen, dann aus dem Baum.
func _weg(n: Node) -> void:
	for g in n.get_groups():
		n.remove_from_group(g)
	var e := n.get_parent()
	if e != null:
		e.remove_child(n)
	if not n.is_queued_for_deletion():
		n.free()


var _koeder: Array = []
var _protokoll := false
var _salve_raus := false
var _letzter_abstand := 1.0e9


## Spitzentempo: einmal ohne Ziel geradeaus, Maximum der Bahngeschwindigkeit.
func _spitzentempo(typ: String) -> float:
	var sp: Dictionary = _spec[typ]
	var m := Missile.new()
	m.schub = float(sp["schub"])
	m.brenndauer = float(sp["brenndauer"])
	m.cw = float(sp["cw"])
	m.lebensdauer = float(sp["lebensdauer"])
	m.schwerkraft = 0.0
	m.startverzug = float(sp.get("abwurf", 0.0))
	m.feind_gruppe = "__keine__"
	m.koeder_gruppe = "__keine__"
	_welt.add_child(m)
	m.global_position = Vector3.ZERO
	m.v = Vector3(0, 0, -float(sp["start_v"]) - 150.0)
	var spitze := 0.0
	for i in MAX_SCHRITTE:
		if not is_instance_valid(m):
			break
		m._physics_process(DT)
		if is_instance_valid(m):
			spitze = maxf(spitze, m.v.length())
	if is_instance_valid(m):
		_weg(m)
	return spitze


## Größte Startentfernung, bei der noch getroffen wird (in 200-m-Schritten).
func _reichweite(typ: String, ziel_v: float) -> float:
	var beste := 0.0
	var d := 200.0
	while d <= 6000.0:
		if _durchgang(typ, d, ziel_v, 0.0, 0):
			beste = d
		else:
			# Einmal daneben heisst nicht immer daneben — erst nach zwei Fehlschuessen
			# in Folge abbrechen, sonst beendet ein Ausreisser die Messung zu frueh.
			if not _durchgang(typ, d + 200.0, ziel_v, 0.0, 0):
				break
			beste = d + 200.0
			d += 200.0
		d += 200.0
	return beste


## Trefferquote gegen ein ausweichendes Ziel, über mehrere Startentfernungen gemittelt.
func _trefferquote(typ: String, koeder: int) -> float:
	var treffer := 0
	var laeufe := 0
	for d in [400.0, 700.0, 1000.0, 1400.0, 1900.0, 2400.0]:
		laeufe += 1
		if _durchgang(typ, d, -60.0, 6.0, koeder):
			treffer += 1
	return float(treffer) / float(maxi(laeufe, 1))
