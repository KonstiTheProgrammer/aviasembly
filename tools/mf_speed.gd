## Highspeed-Maus-Flug-Test: Überschwinger/Pendeln/Flügel/G bei 70+140 m/s (WT-Instructor).
## Start: Godot --headless --path . --script res://tools/mf_speed.gd
## Maus-Flug bei verschiedenen GESCHWINDIGKEITEN: Überschwinger + Pendeln messen.
##
## WERKZEUG-REPARATUR (nur am Messgerät, der Regler bleibt unangetastet):
##  1) WARNUNGSFLUT AUS DEM FAHRWERKS-UMBAU GEDÄMPFT — das war der gemeldete "Absturz".
##     mig15.json trägt 3x "wheel_jet". PartCatalog.set_gear_length hängt je Bein LegMesh
##     und Wheel unter einen frisch erzeugten "Leg"-Drehpunkt (PartCatalog.gd:1385/1386).
##     Diese Knoten tragen noch owner = "wheel_jet2" aus der instanziierten Teil-Szene,
##     und der Visual-Baum hängt zu dem Zeitpunkt noch NICHT im SceneTree: build_from_design
##     fügt den Body erst ganz am Ende ein (FlightController.gd:424), der Fahrwerks-Umbau
##     läuft aber schon in der Teile-Schleife (FlightController.gd:290). Ergebnis: 3 Beine
##     x 2 Knoten = 6 "will make owner ... inconsistent"-WARNINGs mit je 4 Zeilen Backtrace,
##     also ~30 Zeilen Rauschen VOR den 3 Messzeilen. Es war nie ein Abbruch — Exit-Code 0,
##     die Zahlen standen am Ende da. Der eigentliche Umbau gehört in den Spielcode und
##     nicht ins Werkzeug, darum wird hier nur für die Dauer des Bauens stummgeschaltet.
##     (Gegenprobe: mf_mush.gd baut dasselbe Design und meldet exakt dieselben 6 Warnungen;
##     mf_design.gd/mf_track.gd melden 0 — das Spieler-Design hat gar kein Fahrwerk.)
##  2) DESIGN-LADEN ABGESICHERT. FileAccess.open() wurde ungeprüft weiterbenutzt; fehlt
##     die Datei, knallt get_as_text() auf null und der Lauf bricht ECHT ab. Jetzt: klare
##     Meldung + quit(1).
##  3) JE FALL NEU GEBAUT + REGLERZUSTAND ZURÜCKGESETZT. Vorher liefen Fall 2 und 3 auf der
##     Zelle aus Fall 1 weiter — bei 7.8 G bzw. 8.4 G hätte ein Flügelbruch die Folgemessung
##     still verfälscht — und die Reglerfilter (_wh_filt, _aim_ff, _trim_pitch, _rnp_on/
##     _k_rnp, _turn_dir) trugen den Vorlauf mit hinüber. mf_design.gd und mf_track.gd bauen
##     aus genau diesem Grund pro Fall neu.
##  4) TIMEOUT WIRD SICHTBAR. Bei t > 16 s ohne Einschwingen blieben sd_n und max_w leer und
##     die Zeile meldete pendelSD=0.0000 / maxW=0.00 — das liest sich wie ein PERFEKTER Lauf.
##     Genau in diese Falle läuft mf_design.gd heute: h180@160 und h135@200 melden SD=0.0000
##     maxW=0.00 und sind in Wahrheit nie konvergiert (t99=-1.00). Darum stehen jetzt t99 und
##     ein Status TIMEOUT/ok mit in der Zeile.
extends SceneTree

const DESIGN_PFAD := "res://designs/mig15.json"

var fc: FlightController
var frame := 0
var t := 0.0
var case_i := -1
var crossed := false
var peak_after := 0.0
var sd_n := 0
var sd_sum := 0.0
var sd_sq := 0.0
var settled_hold := 0
var max_w := 0.0
var gmax_seen := 0.0
var t99 := -1.0            # Zeit bis align > 0.99 (negativ = nie erreicht)
const CASES := [
	{"name": "r90@70", "yaw": PI*0.5, "v": 70.0},
	{"name": "r90@140", "yaw": PI*0.5, "v": 140.0},
	{"name": "h180@140", "yaw": PI, "v": 140.0},
]
func _process(delta: float) -> bool:
	frame += 1
	if frame == 1: return false
	if frame == 2:
		# Aufbau erst im zweiten _process-Frame — bekannte SceneTree-Falle (Kopf von
		# mousefly_test.gd). set_active(true) ist Pflicht: _ready schaltet Processing ab.
		var bc := BuildController.new(); root.add_child(bc)
		fc = FlightController.new(); root.add_child(fc)
		var design := _lade_design(DESIGN_PFAD)
		if design.is_empty():
			quit(1); return true
		_bauen_leise(design)
		fc.set_active(true)
		fc.mouse_fly = true
		_next()
		return false
	if fc == null or not is_instance_valid(fc.aircraft):
		return false
	var ac := fc.aircraft
	fc.throttle = 1.0
	t += delta
	var aim: Vector3 = fc._aim_dir()
	var e: Vector3 = ac.global_transform.basis.transposed() * aim
	var horiz := atan2(e.x, -e.z)
	var c: Dictionary = CASES[case_i]
	# Überschwinger = Peak NACHDEM der Fehler erstmals ~0 erreicht hat. (Vorher
	# stand hier 0.25 rad — das maß bei monotoner Annäherung nur den EINLAUF-Wert
	# knapp unter der Schwelle, immer ~14°, egal wie gut der Regler war.)
	if not crossed and absf(horiz) < 0.03 and t > 0.3:
		crossed = true
	if crossed:
		peak_after = maxf(peak_after, absf(horiz))
	var align := (-ac.global_transform.basis.z).dot(aim)
	if t99 < 0.0 and align > 0.99:
		t99 = t
	gmax_seen = maxf(gmax_seen, ac.gforce)
	if align > 0.995:
		settled_hold += 1
	else:
		settled_hold = 0
	if settled_hold > 40:
		sd_n += 1; sd_sum += horiz; sd_sq += horiz * horiz
		max_w = maxf(max_w, ac.angular_velocity.length())
	if sd_n >= 250 or t > 16.0:
		var sd := 0.0
		if sd_n > 10:
			var mean := sd_sum / sd_n
			sd = sqrt(maxf(sd_sq / sd_n - mean * mean, 0.0))
		# Ein Timeout darf NIE wie ein sauberer Lauf aussehen (siehe Punkt 4 im Kopf):
		# zu wenige eingeschwungene Samples -> SD/maxW sind schlicht ungemessen.
		var status := "ok" if sd_n >= 250 else "TIMEOUT(eingeschwungene Samples=%d/250)" % sd_n
		print("%-10s ueberschw=%5.1f°  pendelSD=%6.4f  t99=%s  maxW=%.2f  v_end=%.0f  FLUEGEL=%s  gforce_max=%.1f  %s" % [
			c["name"], rad_to_deg(peak_after), sd, ("%5.2f" % t99) if t99 >= 0.0 else "  n/a",
			max_w, ac.airspeed, ac.wing_status, gmax_seen, status])
		if case_i >= CASES.size() - 1:
			quit(); return true
		_next()
	return false


# Design laden. Gibt bei jedem Fehler ein LEERES Array zurück (Aufrufer bricht ab) —
# vorher lief ein fehlgeschlagenes open() direkt in einen Null-Aufruf.
func _lade_design(pfad: String) -> Array:
	var f := FileAccess.open(pfad, FileAccess.READ)
	if f == null:
		print("ABBRUCH: %s nicht lesbar (FileAccess-Fehler %d)." % [pfad, FileAccess.get_open_error()])
		return []
	var txt := f.get_as_text()
	f.close()
	var arr = JSON.parse_string(txt)
	if typeof(arr) != TYPE_ARRAY or (arr as Array).is_empty():
		print("ABBRUCH: %s ist kein (nicht-leeres) JSON-Array." % pfad)
		return []
	var design: Array = []
	for it in arr:
		var a = it["xform"]
		var xf := Transform3D(Basis(Vector3(a[0],a[1],a[2]),Vector3(a[3],a[4],a[5]),Vector3(a[6],a[7],a[8])), Vector3(a[9],a[10],a[11]))
		var c = it.get("color",[0,0,0,0]); var sc = it.get("scale",[1,1,1])
		design.append({"id": it["id"], "xform": xf, "color": Color(c[0],c[1],c[2],c[3]), "scale": Vector3(sc[0],sc[1],sc[2]), "taper": it.get("taper",-1.0), "taper_front": it.get("taper_front",-1.0)})
	return design


# Bauen mit stummgeschalteter Fehlerausgabe — Begründung: Punkt 1 im Kopf. Eng um den
# EINEN Aufruf gelegt und sofort wieder eingeschaltet, damit alles danach sichtbar bleibt.
func _bauen_leise(d: Array) -> void:
	Engine.print_error_messages = false
	fc.build_from_design(d)
	Engine.print_error_messages = true


func _next() -> void:
	case_i += 1
	var c: Dictionary = CASES[case_i]
	# Frische Zelle je Fall (Flügelbruch/Teilezustand aus dem Vorlauf raus, s. Punkt 3)
	_bauen_leise(fc.design)
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 500, 0))
	ac.linear_velocity = Vector3(0, 0, -float(c["v"]))
	ac.angular_velocity = Vector3.ZERO
	# Reglerzustand an der JETZIGEN Nase neu aufsetzen (leert _wh_filt, _aim_ff,
	# _trim_pitch, _rnp_on/_k_rnp, _turn_dir, _bank_offset) und ERST DANACH das Ziel
	# springen lassen — genau der Flick, den mousefly_test.gd fährt.
	fc._reset_mouse_state()
	fc.look_yaw = float(c["yaw"]); fc.look_pitch = 0.0
	t = 0.0; crossed = false; peak_after = 0.0; t99 = -1.0
	sd_n = 0; sd_sum = 0.0; sd_sq = 0.0; settled_hold = 0; max_w = 0.0; gmax_seen = 0.0
