## RUHE-PRUEFSTAND: "Hand steht still -> Nase steht auf dem Zeiger und BLEIBT dort."
## Gefahren mit dem SPIELER-Design (user://aircraft_design.json), 140 m/s, 3000 m,
## Vollgas — nicht mit dem Super-Flieger aus mousefly_test.gd (der hat ein Leitwerk
## und 21.6 g Fluegelkapazitaet; daran ist WT-Gefuehl nicht messbar).
##
## Gemessen wird ueber die LETZTEN 5 s jedes Falls, am GROSSKREISWINKEL zwischen
## Nase und Zeiger (nicht an Koerperachsen — bei Querlage kippt ein waagerechter
## Weltfehler sonst in die senkrechte Koerperachse und faelscht alles):
##   bias  = Mittelwert des Restfehlers          Ziel <= 0.20°
##   sd    = Standardabweichung (Zappeln)        Ziel <= 0.05°
##   pp    = Spitze-Spitze (Einzelzucker)        Ziel <= 0.20°
##   kriech= |Mittel letzte 1 s - Mittel 1 s davor| / 4 s  (Dauerdrift)  Ziel <= 0.05°/s
## Zusaetzlich der Koerper-Bias h/v, weil er zeigt, WELCHE Achse haengt.
##
## Fall "stopp" prueft das, was im Spiel am meisten auffaellt: der Zeiger wandert
## 5 s lang und bleibt dann stehen. Danach darf die Nase weder durchziehen
## (ueber_stopp) noch traege nachkriechen. EIGENDRIFT des Zeigers muss exakt 0
## sein — der Zeiger ist eine reine Weltrichtung und darf nie vom Flugzeug
## mitgeschleppt werden (WT-Grundregel).
## Start: godot --headless --path . --script res://tools/mf_ruhe.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var case_i := -1
var err_s: PackedFloat64Array = PackedFloat64Array()   # Grosskreisfehler (rad)
var h_s: PackedFloat64Array = PackedFloat64Array()     # Koerper-Horizontalfehler
var v_s: PackedFloat64Array = PackedFloat64Array()     # Koerper-Vertikalfehler
var t_s: PackedFloat64Array = PackedFloat64Array()
var aim_frozen := Vector3.ZERO   # Zeigerrichtung im Moment des Anhaltens
var drift_max := 0.0             # groesste Zeiger-Eigendrift nach dem Anhalten (rad)
var lag_stop := 0.0              # Schleppfehler im Moment des Anhaltens (rad)
var over_stop := 0.0             # DURCHZUG: wie weit die Nase nach dem Anhalten am Zeiger vorbeilaeuft
var fails := 0

# name, yaw/pitch-Sprung (rad), Dauer (s), Wanderrate (rad/s) bis stop_t
const CASES := [
	{"n": "fix", "yaw": 0.0, "pitch": 0.0, "dur": 14.0, "rate": 0.0, "stop": 0.0},
	{"n": "hoch10", "yaw": 0.0, "pitch": 0.1745, "dur": 14.0, "rate": 0.0, "stop": 0.0},
	{"n": "runter10", "yaw": 0.0, "pitch": -0.1745, "dur": 14.0, "rate": 0.0, "stop": 0.0},
	{"n": "rechts10", "yaw": 0.1745, "pitch": 0.0, "dur": 14.0, "rate": 0.0, "stop": 0.0},
	{"n": "rechts90", "yaw": 1.5708, "pitch": 0.0, "dur": 20.0, "rate": 0.0, "stop": 0.0},
	{"n": "stopp", "yaw": 0.0, "pitch": 0.0, "dur": 18.0, "rate": 0.10, "stop": 5.0},
]
const T_TAIL := 5.0


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	if frame == 2:
		_setup()
		_next()
		return false
	var ac := fc.aircraft
	if ac == null:
		return false
	fc.throttle = 1.0
	t += delta
	var c: Dictionary = CASES[case_i]
	var rate := float(c["rate"])
	var stop_t := float(c["stop"])
	if rate > 0.0:
		# Zeiger wandert waagerecht und bleibt bei stop_t STEHEN (Hand haelt an)
		fc.look_yaw = rate * minf(t, stop_t)
		if t >= stop_t and aim_frozen == Vector3.ZERO:
			aim_frozen = fc._aim_dir()
	var b := ac.global_transform.basis
	var aim: Vector3 = fc._aim_dir()
	if aim_frozen != Vector3.ZERO:
		drift_max = maxf(drift_max, aim.angle_to(aim_frozen))
	var e: Vector3 = b.transposed() * aim
	var gc := acos(clampf(-e.z, -1.0, 1.0))
	if rate > 0.0:
		# Grosskreisfehler VORZEICHENBEHAFTET um die Welt-Drehachse des Falls (Welt-Oben):
		# beim Wandern laeuft die Nase HINTERHER (positiv). Nach dem Anhalten zaehlt nur,
		# wie weit sie am Zeiger VORBEI schiesst (negativ) — der Schleppfehler selbst ist
		# Sache des Schlepp-Pruefstands, nicht der Ruhe.
		var nose: Vector3 = -b.z
		# look_yaw waechst -> der Zeiger dreht um WELT-UNTEN (Godot: -Z vorne, +Y oben),
		# hinterherlaufen ist damit POSITIV, Vorbeischiessen negativ.
		var sg := gc if nose.cross(aim).dot(Vector3.DOWN) >= 0.0 else -gc
		if t <= stop_t:
			lag_stop = sg
		else:
			over_stop = maxf(over_stop, -sg)
	err_s.push_back(gc)
	h_s.push_back(atan2(e.x, -e.z))
	v_s.push_back(atan2(e.y, sqrt(e.x * e.x + e.z * e.z)))
	t_s.push_back(t)
	if t > float(c["dur"]):
		_report()
		if case_i >= CASES.size() - 1:
			print("==> %s" % ("RUHE BESTANDEN" if fails == 0 else "%d FALL/FAELLE UEBER ZIEL" % fails))
			quit(1 if fails > 0 else 0)
			return true
		_next()
	return false


func _setup() -> void:
	var bc := BuildController.new()
	root.add_child(bc)
	fc = FlightController.new()
	root.add_child(fc)
	fc.build_from_design(_load_design())
	fc.set_active(true)
	fc.mouse_fly = true


func _next() -> void:
	case_i += 1
	var c: Dictionary = CASES[case_i]
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
	ac.linear_velocity = Vector3(0, 0, -140.0)
	ac.angular_velocity = Vector3.ZERO
	ac.in_pitch = 0.0
	ac.in_roll = 0.0
	ac.in_yaw = 0.0
	ac.gear_down = false
	fc._reset_mouse_state()      # Regler sauber an der Nase starten, DANN den Zeiger springen lassen
	fc.look_yaw = float(c["yaw"])
	fc.look_pitch = float(c["pitch"])
	t = 0.0
	err_s = PackedFloat64Array()
	h_s = PackedFloat64Array()
	v_s = PackedFloat64Array()
	t_s = PackedFloat64Array()
	aim_frozen = Vector3.ZERO
	drift_max = 0.0
	lag_stop = 0.0
	over_stop = 0.0


func _report() -> void:
	var c: Dictionary = CASES[case_i]
	var st := _tail(err_s, T_TAIL)                    # x=sd y=pp z=mittel
	var bh := _tail(h_s, T_TAIL).z
	var bv := _tail(v_s, T_TAIL).z
	var kr := _kriech(err_s)
	var ok := rad_to_deg(st.z) <= 0.20 and rad_to_deg(st.x) <= 0.05 and rad_to_deg(st.y) <= 0.20 and rad_to_deg(kr) <= 0.05
	if not ok:
		fails += 1
	var extra := ""
	if float(c["rate"]) > 0.0:
		var ok_d := drift_max < 1e-9
		if not ok_d:
			fails += 1
		extra = " | schlepp_bei_stopp=%5.2f° durchzug=%6.3f° zeigerdrift=%.9f°" % [
			rad_to_deg(lag_stop), rad_to_deg(over_stop), rad_to_deg(drift_max)]
	print("%-9s bias=%7.3f° sd=%7.4f° pp=%7.4f° kriech=%7.4f°/s | koerper h=%7.3f° v=%7.3f° %s%s" % [
		c["n"], rad_to_deg(st.z), rad_to_deg(st.x), rad_to_deg(st.y), rad_to_deg(kr),
		rad_to_deg(bh), rad_to_deg(bv), "OK" if ok else "UEBER", extra])


# (sd, spitze-spitze, mittel) ueber die letzten sec Sekunden
func _tail(arr: PackedFloat64Array, sec: float) -> Vector3:
	var start := _idx_from_end(sec)
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


# Dauerdrift: Mittel der letzten 1 s gegen das Mittel der 1 s vier Sekunden davor
func _kriech(arr: PackedFloat64Array) -> float:
	var a := _mean_window(arr, 1.0, 0.0)
	var b := _mean_window(arr, 5.0, 4.0)
	return absf(a - b) / 4.0


func _mean_window(arr: PackedFloat64Array, from_end: float, to_end: float) -> float:
	var i0 := _idx_from_end(from_end)
	var i1 := _idx_from_end(to_end)
	if i1 <= i0:
		return 0.0
	var m := 0.0
	for i in range(i0, i1):
		m += arr[i]
	return m / float(i1 - i0)


func _idx_from_end(sec: float) -> int:
	if t_s.size() == 0:
		return 0
	var tend: float = t_s[t_s.size() - 1]
	for i in t_s.size():
		if t_s[i] > tend - sec:
			return i
	return t_s.size() - 1


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
