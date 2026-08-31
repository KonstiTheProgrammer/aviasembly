## PRUEFSTAND FUER DIE RAKETENSTELLUNGEN — die andere Hälfte des Systems.
##
## Der Waffen-Pruefstand misst, was der SPIELER verschiesst. Hier geht es um das, was auf
## ihn zufliegt: startet eine Stellung ueberhaupt, trifft sie, und retten Fackeln bzw.
## Dueppel den Piloten? Ohne diese Messung waere die halbe Neuerung ungeprueft — und
## ausgerechnet die Haelfte, die im Spiel weh tut.
##
## Der Pruefstand baut KEINE Welt: eine Stellung, ein Scheinflugzeug, sonst nichts. Damit
## laeuft er in Sekunden statt in Minuten und misst nur das, was er messen soll.
##
## Godot --headless --path . --script res://tools/_sam_pruefstand.gd
extends SceneTree

const DT := 1.0 / 60.0
const SCHRITTE := 3000

var f := 0
var _welt: Node3D = null


func _process(_d: float) -> bool:
	f += 1
	if f < 2:
		return false
	_welt = Node3D.new()
	root.add_child(_welt)
	# TREFFERQUOTEN, KEINE EINZELFAELLE. Ein Ja/Nein aus einer Lage ist keine Messung: die
	# erste Fassung lieferte je nach Anflugabstand widerspruechliche Aussagen ("Kurve macht
	# es schlimmer"), weil sie genau EINEN Punkt abtastete. Jede Zahl unten ist der Anteil
	# der Treffer ueber fuenf Anfluege mit verschiedenem Abstand.
	print("Stellung | Lage    |  frei | nur Koeder | nur Kurve  | Koeder+Kurve | Gas aus")
	print("---------+---------+-------+------------+------------+--------------+--------")
	# ZWEI LAGEN, WEIL SIE VERSCHIEDENES VERLANGEN. Im Querflug trennt sich ein Koeder
	# kaum von der Sichtlinie und wirkt wenig; im Fluchtflug liegt er genau dort, wo der
	# Suchkopf hinsieht. Wer nur eine Lage misst, haelt eine Geometrie fuer eine Regel.
	for art in ["ir", "radar"]:
		for lage in ["quer", "Flucht"]:
			print("%-8s | %-7s | %5.0f %% | %8.0f %% | %8.0f %% | %10.0f %% | %5.0f %%"
				% [art.to_upper(), lage,
					_quote(art, lage, false, 0.0, 1.0),
					_quote(art, lage, true, 0.0, 1.0),
					_quote(art, lage, false, 6.0, 1.0),
					_quote(art, lage, true, 6.0, 1.0),
					_quote(art, lage, false, 0.0, 0.08)])
	print("\n(\"Gas aus\" = Schub auf 8 Prozent. Ein Waermesucher braucht Waerme: die IR-Stellung")
	print(" startet dann erst viel spaeter und trifft entsprechend seltener. Fuer Radar ist")
	print(" der Schub bedeutungslos — dort hilft nur Tiefflug, Wolke oder Dueppel.)")
	quit()
	return true


## Trefferquote über fünf Anflüge mit verschiedenem Abstand.
func _quote(art: String, lage: String, koeder: bool, ausweichen: float, gas: float) -> float:
	var treffer := 0
	var n := 0
	for versatz in [-300.0, -500.0, -700.0, -900.0, -1100.0]:
		n += 1
		if _lauf(art, gas, koeder, lage, ausweichen, versatz)["treffer"]:
			treffer += 1
	return 100.0 * float(treffer) / float(maxi(n, 1))


## Ein Ergebnis in einem Wort.
func _wort(e: Dictionary) -> String:
	if not e["start"]:
		return "kein Start"
	return "TREFFER" if e["treffer"] else "entkommen"


## Ein Anflug. gas: 0..1.2, koeder: wirft der Pilot Gegenmassnahmen?
func _lauf(art: String, gas: float, koeder: bool, lage: String = "quer",
		ausweichen := 0.0, versatz := -400.0) -> Dictionary:
	var sam := SamSite.new()
	sam.art = art
	_welt.add_child(sam)
	sam.global_position = Vector3.ZERO
	sam._cd = 0.0                       # sofort feuerbereit, kein Zufall im Pruefstand

	# Scheinflugzeug: fliegt quer an der Stellung vorbei, 180 m hoch, 1200 m Abstand.
	var plane := Node3D.new()
	plane.add_to_group("player")
	plane.set_meta("wolken_dichte", 0.0)
	# Dieselben Werte, die AircraftBody.ir_signatur/radar_signatur bei diesem Gas liefern.
	plane.set_meta("ir_signatur", 26.0 + 210.0 * clampf(gas, 0.0, 1.0))
	plane.set_meta("radar_signatur", 82.0)
	_welt.add_child(plane)
	# quer  = fliegt an der Stellung vorbei; Flucht = fliegt von ihr weg (Heck zur Rakete).
	var pv := Vector3(190.0, 0.0, 0.0) if lage == "quer" else Vector3(0.0, 0.0, -190.0)
	# "versatz" ist im Querflug der seitliche Vorbeiflugabstand, im Fluchtflug der
	# Startabstand zur Stellung. Beides in Metern, negativ entlang -Z.
	plane.global_position = (Vector3(-1200.0, 180.0, versatz) if lage == "quer"
		else Vector3(0.0, 180.0, versatz))
	plane.look_at(plane.global_position + pv, Vector3.UP)

	var start := false
	var treffer := false
	var koeder_raus := false
	var koeder_liste: Array = []
	for i in SCHRITTE:
		# Ausweichkurve: quer zur eigenen Bahn ziehen, sobald etwas unterwegs ist.
		if ausweichen > 0.0 and start:
			# WEG VON DER RAKETE, nicht irgendwohin. Die erste Fassung drehte immer in
			# dieselbe Richtung — je nach Lage also auch mitten in den Anflug hinein, und
			# die Messung meldete dann "Kurve macht es schlimmer". Das war der Aufbau,
			# nicht das System. Ausgewichen wird quer zur Sichtlinie, von ihr fort.
			var quer := pv.cross(Vector3.UP).normalized()
			var zur_rakete := Vector3.ZERO
			for n in _welt.get_children():
				if n is Missile and not (n as Missile)._tot:
					zur_rakete = (n as Node3D).global_position - plane.global_position
					break
			if quer.dot(zur_rakete) > 0.0:
				quer = -quer
			pv += quer * (ausweichen * 9.81) * DT
			pv = pv.normalized() * 190.0
		plane.global_position += pv * DT
		plane.look_at(plane.global_position + pv, Vector3.UP)
		sam._physics_process(DT)
		var raketen: Array = []
		for n in _welt.get_children():
			if n is Missile and not (n as Missile)._tot:
				raketen.append(n)
		if not raketen.is_empty():
			start = true
		for r in raketen:
			var m := r as Missile
			var abst := m.global_position.distance_to(plane.global_position)
			# Der Pilot wirft, sobald es eng wird — dasselbe Zeitfenster wie im
			# Waffen-Pruefstand (rund anderthalb Sekunden vor dem Einschlag).
			if koeder and not koeder_raus:
				var nae := (m.v - pv).dot(
					(plane.global_position - m.global_position).normalized())
				if nae > 1.0 and abst / nae < 1.5:
					koeder_raus = true
					var kart := "flare" if art == "ir" else "chaff"
					# IM FLUGZEUGSYSTEM, nicht in Weltkoordinaten: ein Werfer sitzt hinten am
					# Rumpf, und "hinten" haengt davon ab, wohin die Maschine schaut. Mit
					# festem Weltversatz lagen die Koeder im Querflug VOR dem Flugzeug.
					var pb := plane.global_transform.basis
					for s2 in [-1.0, 1.0]:
						koeder_liste.append(Countermeasure.werfen(_welt, kart,
							plane.global_position + pb * Vector3(s2 * 1.2, -0.6, 1.8),
							pv * 0.85 + pb * Vector3(s2 * 7.0, -5.0, 9.0)))
			for k in koeder_liste:
				if is_instance_valid(k):
					k._physics_process(DT)
			m._physics_process(DT)
			if m._tot:
				if m.global_position.distance_to(plane.global_position) <= m.zuender + 5.0:
					treffer = true
		if treffer:
			break
	var erg := {"start": start, "treffer": treffer}
	for n in _welt.get_children():
		_weg(n)
	return erg


func _weg(n: Node) -> void:
	for g in n.get_groups():
		n.remove_from_group(g)
	var e := n.get_parent()
	if e != null:
		e.remove_child(n)
	if not n.is_queued_for_deletion():
		n.free()
