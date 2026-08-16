## FEINES ZIELEN: kleine Korrekturen (Zeigerversatz unter 15 Grad).
## Das ist der Fall, der im Luftkampf ueber Treffen und Danebenschiessen entscheidet:
## das Ziel steht schon fast im Fadenkreuz, der Spieler schiebt die Maus ein Stueck
## nach und erwartet, dass die Nase draufrastet und DORT bleibt.
##
## UNTERSCHIED ZU tools/mf_bar.gd (bewusst, sonst misst man Muell):
##  1) VORLAUF: jeder Sprung startet aus dem EINGESCHWUNGENEN Flug (4 s Marker auf der
##     Nase), nicht aus dem Einsetz-Transienten frisch gebauter Zelle. Ohne das misst
##     man den Absack-/Antrimm-Vorgang der ersten Sekunden mit.
##  2) SPRUNG RELATIV ZUR NASE: der Marker springt um genau `deg` von der AKTUELLEN
##     Nasenrichtung weg. Damit ist e0 = deg und der stehende Restversatz faelscht die
##     Anstiegszeit nicht (mf_bar springt absolut und misst Sockel + Sprung zusammen).
##  3) VORZEICHENACHSE ZUR LAUFZEIT: axis_w = (Nase x Marker) IM SPRUNGMOMENT.
##     mf_bar setzt fuer den waagerechten Fall axis_w = UP fest; (Nase x Marker) zeigt
##     dort aber nach -UP -> jeder Fehler wird negativ gezaehlt und die Ueberschwing-
##     Kennzahl meldet stur 100 %. Deshalb sind die "ueber="-Werte von mf_bar in den
##     h-Faellen nicht lesbar, diese hier schon.
##
## KENNZAHL = DREHVEKTOR von der Nase auf den Marker: rot = norm(Nase x Marker) * Winkel.
## Davon zwei Zahlen:
##   e_ax  = rot · axis_w  -> Fehler AUF der Manoeverachse (t90, Ueberschwingen, Einlaufen)
##   e_ges = |rot|         -> Gesamt-Grosskreisfehler ("steht die Nase auf dem Marker?")
## WARUM NICHT der signierte Grosskreiswinkel (mein erster Versuch, verworfen):
## acos()+Vorzeichen ueber axis_w kippt, sobald der REST quer zur Manoeverachse steht.
## Beim waagerechten Sprung blieb der senkrechte 5.3°-Sockel stehen; sein Vorzeichen
## flackerte mit der Querlage und die Kennzahl meldete 10.5° Spitze-Spitze Pendeln,
## wo in Wirklichkeit gar nichts pendelte. Die Vektorzerlegung kann das nicht:
## ein rein senkrechter Rest hat e_ax = 0 und taucht sauber in e_ges/e_quer auf.
##
## ZIELWERTE (aus der Messlatte, Spieler-Design, 140 m/s):
##   Ruhe:  Bias <= 0.20°, SD <= 0.05°, Spitze-Spitze <= 0.20°
##   10° senkrecht: t90 <= 1.00 s | 10° waagerecht: t90 <= 1.60 s
##   Ueberschwingen <= 5 % | Einschwingen in das 0.2°-Band <= 2.20 s
## Start: godot --headless --path . --script res://tools/mf_fein.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var case_i := -1
var stepped := false            # Vorlauf vorbei, Sprung gesetzt?
var step0 := 1.0                # tatsaechlicher Anfangsfehler im Sprungmoment (rad)
var axis_w := Vector3.UP
var _prev_e := 0.0
var samples: PackedFloat64Array = PackedFloat64Array()   # e_ax: Fehler auf der Manoeverachse
var total: PackedFloat64Array = PackedFloat64Array()     # e_ges: Gesamt-Grosskreisfehler
var times: PackedFloat64Array = PackedFloat64Array()
var body_h: PackedFloat64Array = PackedFloat64Array()
var body_v: PackedFloat64Array = PackedFloat64Array()
var elev_sum := 0.0             # aufsummierter |Hoehenruder|-Weg (Ausnutzung)
var elev_n := 0
var w_ax_max := 0.0             # groesste erreichte Drehrate um die Manoeverachse
var v_at_step := 0.0

# deg = Sprungweite, ax = h (waagerecht/Gier) oder v (senkrecht/Nick), v = Startspeed
const CASES := [
	{"deg": 0.0, "ax": "v", "v": 140.0},     # RUHE (kein Sprung)
	{"deg": 2.0, "ax": "v", "v": 140.0},
	{"deg": 5.0, "ax": "v", "v": 140.0},
	{"deg": 10.0, "ax": "v", "v": 140.0},
	{"deg": 15.0, "ax": "v", "v": 140.0},
	{"deg": 2.0, "ax": "h", "v": 140.0},
	{"deg": 5.0, "ax": "h", "v": 140.0},
	{"deg": 10.0, "ax": "h", "v": 140.0},
	{"deg": 15.0, "ax": "h", "v": 140.0},
	{"deg": 10.0, "ax": "h", "v": 200.0},
	{"deg": 10.0, "ax": "v", "v": 200.0},
]
const T_PRE := 4.0              # Vorlauf: Marker auf der Nase, Regler laeuft ein
const T_RUN := 8.0              # Messfenster nach dem Sprung
const BAND := 0.2 * PI / 180.0  # 0.2°-Ring = "auf 400 m innerhalb der Rumpfbreite"


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	if frame == 2:
		_setup()
		case_i = 0
		_start()
		return false
	var ac := fc.aircraft
	if ac == null:
		return false
	fc.throttle = 1.0
	t += delta
	if not stepped:
		if t >= T_PRE:
			_do_step()
		return false
	# --- Messung: Drehvektor Nase -> Marker, zerlegt in Manoeverachse und Rest ---
	var b: Basis = ac.global_transform.basis
	var nose: Vector3 = -b.z
	var aimw: Vector3 = fc._aim_dir()
	var ang := acos(clampf(nose.dot(aimw), -1.0, 1.0))
	var cr := nose.cross(aimw)
	var rot: Vector3 = (cr.normalized() * ang) if cr.length() > 1e-9 else Vector3.ZERO
	_prev_e = rot.dot(axis_w)
	samples.push_back(_prev_e)
	total.push_back(ang)
	times.push_back(t - T_PRE)
	var e: Vector3 = b.transposed() * aimw
	body_h.push_back(atan2(e.x, -e.z))
	body_v.push_back(atan2(e.y, sqrt(e.x * e.x + e.z * e.z)))
	elev_sum += absf(ac.in_pitch)
	elev_n += 1
	w_ax_max = maxf(w_ax_max, absf(ac.angular_velocity.dot(axis_w)))
	if t - T_PRE > T_RUN:
		_report()
		case_i += 1
		if case_i >= CASES.size():
			quit()
			return true
		_start()
	return false


func _setup() -> void:
	var bc := BuildController.new()
	root.add_child(bc)
	fc = FlightController.new()
	root.add_child(fc)
	fc.build_from_design(_load_design())
	fc.set_active(true)
	fc.mouse_fly = true


func _start() -> void:
	var c: Dictionary = CASES[case_i]
	fc.build_from_design(fc.design)
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
	ac.linear_velocity = Vector3(0, 0, -float(c["v"]))
	ac.angular_velocity = Vector3.ZERO
	ac.gear_down = false
	fc.look_yaw = 0.0
	fc.look_pitch = 0.0
	fc._reset_mouse_state()
	fc._aim_cmd = -ac.global_transform.basis.z
	t = 0.0
	stepped = false
	samples = PackedFloat64Array()
	total = PackedFloat64Array()
	times = PackedFloat64Array()
	body_h = PackedFloat64Array()
	body_v = PackedFloat64Array()
	elev_sum = 0.0
	elev_n = 0
	w_ax_max = 0.0
	_prev_e = 0.0


# Sprung RELATIV zur aktuellen Nase: Marker = Nasenrichtung + deg auf der Fallachse.
func _do_step() -> void:
	var c: Dictionary = CASES[case_i]
	var ac := fc.aircraft
	var nose: Vector3 = -ac.global_transform.basis.z
	var yaw := atan2(nose.x, -nose.z)
	var pitch := asin(clampf(nose.y, -1.0, 1.0))
	var rad := deg_to_rad(float(c["deg"]))
	if c["ax"] == "h":
		yaw += rad
	else:
		pitch += rad
	fc.look_yaw = yaw
	fc.look_pitch = clampf(pitch, -1.5, 1.5)
	var aimw: Vector3 = fc._aim_dir()
	step0 = maxf(acos(clampf(nose.dot(aimw), -1.0, 1.0)), 1e-5)
	var cr := nose.cross(aimw)
	axis_w = cr.normalized() if cr.length() > 1e-6 else Vector3.UP
	v_at_step = ac.airspeed
	stepped = true


func _report() -> void:
	var c: Dictionary = CASES[case_i]
	if float(c["deg"]) <= 0.0:
		_report_quiet()
		return
	var t90 := -1.0             # Anstieg: Achsfehler auf 10 % des Sprungs herunter
	var over := 0.0             # Ueberschwingen: wie weit der Achsfehler durch null hindurchgeht
	var last_out := 0.0         # letzter Moment ausserhalb des 0.2°-Rings (GESAMTfehler)
	var last_out2 := 0.0        # ... ausserhalb des 2-%-Rings (Achsfehler)
	var tend: float = times[times.size() - 1]
	for i in samples.size():
		var e: float = samples[i]
		var tt: float = times[i]
		if t90 < 0.0 and absf(e) <= 0.10 * step0:
			t90 = tt
		if e < 0.0:
			over = maxf(over, -e)
		if total[i] > BAND:
			last_out = tt
		if absf(e) > 0.02 * step0:
			last_out2 = tt
	var t_band := last_out if last_out < tend - 0.05 else -1.0
	var t2p := last_out2 if last_out2 < tend - 0.05 else -1.0
	var tail := _tail_stats(samples, 2.0)     # Rest AUF der Achse
	var tg := _tail_stats(total, 2.0)         # Rest GESAMT (das sieht der Spieler)
	# UEBERSCHWINGEN IN PROZENT ALLEIN IST FUER KLEINE SPRUENGE IRREFUEHREND:
	# der Zielwert "<= 5 %" bedeutet beim 2°-Sprung 0.10° — das liegt UNTER dem
	# 0.2°-Akzeptanzring, in dem die Kennzahl t0.2ges das Einlaufen ueberhaupt erst
	# zaehlt. Ein Durchzug, der den Ring nie verlaesst, ist im Spiel unsichtbar und
	# nicht schussrelevant; wer die Prozentzahl trotzdem wegoptimiert, kauft sie mit
	# Anstiegszeit und macht das Zielen SCHLECHTER. Umgekehrt sind 3 % beim 15°-Sprung
	# 0.45° und damit mehr als das Doppelte des Rings — also sehr wohl sichtbar.
	# Deshalb wird ab jetzt BEIDES gedruckt: Prozent (wie die Messlatte es formuliert)
	# UND Grad (was der Spieler sieht). Der Test wird dadurch nicht laxer — er zeigt
	# nur zusaetzlich die Zahl, an der man das Prozentmass ueberhaupt einordnen kann.
	print("SPRUNG %5.1f°%s v=%3.0f | e0=%5.2f° | t90=%6.2f  ueber=%5.1f%% (%5.3f°)  t2%%=%6.2f  t0.2ges=%6.2f | achse %6.3f° sd=%.3f° | GESAMT %6.3f° pp=%.3f° | wmax=%.3f ruder=%.2f" % [
		float(c["deg"]), c["ax"], v_at_step, rad_to_deg(step0),
		t90, 100.0 * over / step0, rad_to_deg(over), t2p, t_band,
		rad_to_deg(tail.z), rad_to_deg(tail.x),
		rad_to_deg(tg.z), rad_to_deg(tg.y),
		w_ax_max, elev_sum / maxf(elev_n, 1)])


func _report_quiet() -> void:
	var th := _tail_stats(body_h, 5.0)
	var tv := _tail_stats(body_v, 5.0)
	# Drift = Aenderung des GESAMTfehlers ueber die letzten 5 s (steht die Nase wirklich?)
	var i0 := 0
	var tend: float = times[times.size() - 1]
	for i in times.size():
		if times[i] > tend - 5.0:
			i0 = i
			break
	var drift := (total[total.size() - 1] - total[i0]) / maxf(tend - times[i0], 1e-3)
	print("RUHE   v=%3.0f | waagerecht bias=%6.3f° sd=%.4f° pp=%.4f° | senkrecht bias=%6.3f° sd=%.4f° pp=%.4f° | drift=%.4f°/s" % [
		v_at_step, rad_to_deg(th.z), rad_to_deg(th.x), rad_to_deg(th.y),
		rad_to_deg(tv.z), rad_to_deg(tv.x), rad_to_deg(tv.y), rad_to_deg(drift)])


# (Standardabweichung, Spitze-Spitze, Mittelwert) ueber die letzten sec Sekunden
func _tail_stats(arr: PackedFloat64Array, sec: float) -> Vector3:
	if arr.size() < 5:
		return Vector3.ZERO
	var tend: float = times[times.size() - 1]
	var start := 0
	for i in times.size():
		if times[i] > tend - sec:
			start = i
			break
	var n := arr.size() - start
	if n < 5:
		return Vector3.ZERO
	var mean := 0.0
	var lo := 1e9
	var hi := -1e9
	for i in range(start, arr.size()):
		mean += arr[i]
		lo = minf(lo, arr[i])
		hi = maxf(hi, arr[i])
	mean /= n
	var sd := 0.0
	for i in range(start, arr.size()):
		sd += (arr[i] - mean) * (arr[i] - mean)
	return Vector3(sqrt(sd / n), hi - lo, mean)


func _load_design() -> Array:
	var f := FileAccess.open("user://aircraft_design.json", FileAccess.READ)
	if f == null:
		push_error("kein user://aircraft_design.json")
		return []
	var arr = JSON.parse_string(f.get_as_text())
	f.close()
	var design: Array = []
	for it in arr:
		var a = it["xform"]
		var xf := Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))
		var col = it.get("color", [0, 0, 0, 0])
		var sc = it.get("scale", [1, 1, 1])
		design.append({"id": it["id"], "xform": xf, "color": Color(col[0], col[1], col[2], col[3]), "scale": Vector3(sc[0], sc[1], sc[2]), "taper": it.get("taper", -1.0), "taper_front": it.get("taper_front", -1.0)})
	return design
