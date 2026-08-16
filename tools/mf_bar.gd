## MESSLATTE (War-Thunder-Maus-Aim): die vier Kennzahlen-Familien in EINEM Lauf,
## gefahren mit dem SPIELER-Design (user://aircraft_design.json) — nicht mit dem
## Super-Flieger aus mousefly_test.gd (der hat 21.6 g Fluegelkapazitaet und dreht
## 145 Grad/s; daran laesst sich WT-Gefuehl nicht messen).
##
##  A) SPRUNG: Markersprung um 10 / 30 / 90 / 180 Grad ->
##     t90 (Anstieg), Ueberschwingen %, t2% (Einschwingen), t99, Nachpendeln
##  B) SCHLEPP: Marker wandert mit konstanter Rate (Kreis) -> stationaerer Schleppfehler
##     je Rate; die Rate wird in Prozent der PHYSISCH moeglichen Drehrate angegeben.
##  C) RUHE: Maus steht still -> Standardabweichung des Winkelfehlers
##
## HAUPTKENNZAHL = GROSSKREISWINKEL zwischen Nase und Marker, signiert mit der
## ANFANGS-Drehachse IM WELTSYSTEM und stetig fortgesetzt (Unwrap).
## Warum nicht die Koerperachsen-Zerlegung: bei 90° Querlage kippt ein WAAGERECHTER
## Weltfehler komplett in die SENKRECHTE Koerperachse — die Zerlegung meldete dann
## t90=2.2 s fuer einen 90°-Flick, den die Nase in Wahrheit erst nach ~11 s schafft.
## Die Koerperkomponenten laufen weiter mit, aber nur als BIAS-Nachweis.
## Start: godot --headless --path . --script res://tools/mf_bar.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var case_i := -1
var is_h := true                # Manoeverachse: waagerecht (Gier) oder senkrecht (Nick)
var step0 := 1.0
var samples: PackedFloat64Array = PackedFloat64Array()   # Fehler AUF der Manoeverachse
var ortho: PackedFloat64Array = PackedFloat64Array()     # Koerper-Querfehler (Bias-Nachweis)
var ortho2: PackedFloat64Array = PackedFloat64Array()    # Koerperfehler auf der Manoeverachse
var axis_w := Vector3.UP        # feste Welt-Drehachse des Falls (Vorzeichen des Fehlers)
var times: PackedFloat64Array = PackedFloat64Array()
var w_max_seen := 0.0
var _prev_e := 0.0              # Vorframe-Fehler fuer die stetige Fortsetzung (Unwrap)

# Sprungfaelle: Grad, Achse (h=horizontal/Gier, v=vertikal/Nick), Startgeschwindigkeit
const STEPS := [
	{"deg": 10.0, "ax": "h", "v": 140.0},
	{"deg": 10.0, "ax": "v", "v": 140.0},
	{"deg": 10.0, "ax": "h", "v": 200.0},
	{"deg": 30.0, "ax": "h", "v": 140.0},
	{"deg": 90.0, "ax": "h", "v": 140.0},
	{"deg": 180.0, "ax": "h", "v": 140.0},
]
# Schleppfaelle: Marker-Winkelrate (rad/s) horizontal
const TRACKS := [0.05, 0.10, 0.15, 0.20, 0.30, 0.35]
const T_STEP := 12.0
const T_TRACK := 14.0
const T_QUIET := 8.0


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
	var n_steps := STEPS.size()
	var n_track := TRACKS.size()
	if case_i >= n_steps and case_i < n_steps + n_track:
		# Marker wandert gleichmaessig um Welt-Oben
		fc.look_yaw = TRACKS[case_i - n_steps] * t
	# Fehler ZERLEGT im Koerpersystem. Wichtig: die Sprungkennzahlen duerfen NUR die
	# Manoeverachse sehen — ein stehender Rest in der anderen Achse (gemessen: 5.4°
	# Nick-Bias bei stillstehender Maus) faelscht sonst jedes "Ueberschwingen".
	var e: Vector3 = ac.global_transform.basis.transposed() * fc._aim_dir()
	var horiz := atan2(e.x, -e.z)
	var vert := atan2(e.y, sqrt(e.x * e.x + e.z * e.z))
	# Grosskreisfehler, Vorzeichen ueber die feste Welt-Drehachse des Falls
	var nose: Vector3 = -ac.global_transform.basis.z
	var aimw: Vector3 = fc._aim_dir()
	var cur := acos(clampf(nose.dot(aimw), -1.0, 1.0))
	if nose.cross(aimw).dot(axis_w) < 0.0:
		cur = -cur
	# Unwrap: bei 180°-Wenden springt atan2 an der Naht — ohne das zaehlte der erste
	# Frame als "100 % Ueberschwingen".
	if samples.size() > 0:
		cur = _prev_e + wrapf(cur - _prev_e, -PI, PI)
	_prev_e = cur
	samples.push_back(cur)
	ortho.push_back(vert if is_h else horiz)
	ortho2.push_back(horiz if is_h else vert)
	times.push_back(t)
	w_max_seen = maxf(w_max_seen, ac.angular_velocity.length())
	var dur := T_STEP
	if case_i >= n_steps + n_track:
		dur = T_QUIET
	elif case_i >= n_steps:
		dur = T_TRACK
	if t > dur:
		_finish()
		case_i += 1
		if case_i >= n_steps + n_track + 1:
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
	var n_steps := STEPS.size()
	var v := 140.0
	var yaw := 0.0
	var pitch := 0.0
	if case_i < n_steps:
		var c: Dictionary = STEPS[case_i]
		v = float(c["v"])
		var rad := deg_to_rad(float(c["deg"]))
		if c["ax"] == "h":
			yaw = rad
		else:
			pitch = rad
	fc.build_from_design(fc.design)
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
	ac.linear_velocity = Vector3(0, 0, -v)
	ac.angular_velocity = Vector3.ZERO
	ac.gear_down = false
	fc.look_yaw = yaw
	fc.look_pitch = pitch
	fc._aim_cmd = -ac.global_transform.basis.z
	fc._bank_offset = 0.0
	fc._trim_pitch = 0.0
	fc._aim_ff = Vector3.ZERO
	fc._wh_filt = 0.0
	is_h = pitch == 0.0
	axis_w = Vector3.UP if is_h else Vector3.RIGHT
	if not is_h:
		axis_w = Vector3(-1, 0, 0)     # Nase hoch = Drehung um -X (Godot: -Z vorne, +Y oben)
	step0 = maxf(absf(yaw) + absf(pitch), 1e-4)
	t = 0.0
	samples = PackedFloat64Array()
	ortho = PackedFloat64Array()
	ortho2 = PackedFloat64Array()
	times = PackedFloat64Array()
	_prev_e = 0.0
	w_max_seen = 0.0


func _finish() -> void:
	var n_steps := STEPS.size()
	var n_track := TRACKS.size()
	if case_i < n_steps:
		_report_step()
	elif case_i < n_steps + n_track:
		_report_track()
	else:
		_report_quiet()


func _report_step() -> void:
	var c: Dictionary = STEPS[case_i]
	var t90 := -1.0
	var t99 := -1.0
	var t2 := -1.0
	var over := 0.0
	var last_out := 0.0
	for i in samples.size():
		var e: float = samples[i]
		var tt: float = times[i]
		if t90 < 0.0 and absf(e) <= 0.10 * step0:
			t90 = tt
		if t99 < 0.0 and absf(e) <= 0.01 * step0:
			t99 = tt
		if e < 0.0:
			over = maxf(over, -e)
		if absf(e) > 0.02 * step0:
			last_out = tt
	t2 = last_out if last_out < times[times.size() - 1] - 0.05 else -1.0
	# Nachpendeln + stehender Rest: letzte 3 s, Achse UND Querachse
	var tail := _tail_stats(samples, 3.0)
	var tq := _tail_stats(ortho, 3.0)
	var tq2 := _tail_stats(ortho2, 3.0)
	print("SPRUNG %5.0f°%s v=%3.0f | t90=%5.2f t99=%5.2f t2%%=%5.2f | ueber=%5.1f%% | rest: bias=%6.2f° sd=%.3f° pp=%.3f° | koerper h/v bias=%6.2f°/%6.2f°" % [
		float(c["deg"]), c["ax"], float(c["v"]), t90, t99, t2,
		100.0 * over / step0, rad_to_deg(tail.z), rad_to_deg(tail.x), rad_to_deg(tail.y),
		rad_to_deg(tq2.z if is_h else tq.z), rad_to_deg(tq.z if is_h else tq2.z)])


func _report_track() -> void:
	var rate: float = TRACKS[case_i - STEPS.size()]
	# stationaerer Schleppfehler = Mittel der letzten 5 s
	var acc := 0.0
	var n := 0
	var mx := 0.0
	var tend: float = times[times.size() - 1]
	for i in samples.size():
		if times[i] > tend - 5.0:
			acc += absf(samples[i])
			mx = maxf(mx, absf(samples[i]))
			n += 1
	var mean := acc / maxf(n, 1)
	var tq := _tail_stats(ortho, 5.0)
	print("SCHLEPP rate=%.2f rad/s (%4.1f°/s) | schlepp_mittel=%6.2f° max=%6.2f° | quer=%6.2f° | wmax=%.2f rad/s" % [
		rate, rad_to_deg(rate), rad_to_deg(mean), rad_to_deg(mx), rad_to_deg(tq.z), w_max_seen])


func _report_quiet() -> void:
	var th := _tail_stats(ortho2, 4.0)
	var tv := _tail_stats(ortho, 4.0)
	print("RUHE (Marker fix, letzte 4 s) | waagerecht bias=%6.3f° sd=%.4f° pp=%.4f° | senkrecht bias=%6.3f° sd=%.4f° pp=%.4f°" % [
		rad_to_deg(th.z), rad_to_deg(th.x), rad_to_deg(th.y),
		rad_to_deg(tv.z), rad_to_deg(tv.x), rad_to_deg(tv.y)])


# (Standardabweichung, Spitze-Spitze, Mittelwert/Bias) ueber die letzten sec Sekunden
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
		var c = it.get("color", [0, 0, 0, 0])
		var sc = it.get("scale", [1, 1, 1])
		design.append({"id": it["id"], "xform": xf, "color": Color(c[0], c[1], c[2], c[3]), "scale": Vector3(sc[0], sc[1], sc[2]), "taper": it.get("taper", -1.0), "taper_front": it.get("taper_front", -1.0)})
	return design
