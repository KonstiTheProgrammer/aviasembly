## SCHLEPPFEHLER bei wanderndem Zeiger — ehrlich parametriert und sauber zerlegt.
##
## WARUM EIN EIGENES WERKZEUG (zwei Fallen in tools/mf_track.gd):
## 1. Dort wandert der Marker mit fest 0.35 rad/s. Diese Zelle (Spieler-Design,
##    kein Leitwerk -> pitch_area = 0) dreht laut _auth_rates().x nur 0.298 rad/s.
##    Der 96-Grad-Wert ist damit per Konstruktion ein SAETTIGUNGSFALL: er misst
##    Flugmechanik, nicht Regelguete, und kann nie klein werden.
## 2. Der Grosskreisfehler vermischt zwei voellig verschiedene Fehler: das
##    NACHLAUFEN in Zieh-Richtung (der eigentliche Schleppfehler) und den
##    stationaeren SENKRECHT-VERSATZ (gemessen 5.4 Grad, eigene Baustelle).
##    Hier wird beides getrennt: entlang der Markerbahn = Schlepp, quer = Versatz.
##
## Markerrate = ANTEIL der zur Laufzeit aus dem Bau berechneten Rate omega_inst:
##   25 % = gemuetliches Nachziehen   -> reiner Vorhalt, darf fast nichts kosten (Ziel <= 0.5 Grad)
##   50 % = typisches Dogfight-Ziehen -> noch 100 % Reserve (Ziel <= 2.0 Grad)
##   80 % = nahe der Zellengrenze     -> darf sichtbar sein, nicht davonlaufen (Ziel <= 5.0 Grad)
##  130 % = SAETTIGUNG                -> Fehlerzuwachs ist Physik; geprueft wird nur, dass die
##                                       volle Rate steht und nach Marker-Stopp monoton
##                                       (ohne Vorbeiziehen) aufgeholt wird.
## Start: godot --headless --path . --script res://tools/mf_schlepp.gd
extends SceneTree

var fc: FlightController
var frame := 0
var t := 0.0
var case_i := 0

const FRAC := [0.25, 0.50, 0.80, 1.30]   # Markerrate als Anteil von omega_inst
const T_SETTLE := 2.5                    # geradeaus einschwingen (Tempo/Trim), Marker steht
const T_ZIEH := 10.0                     # so lange wandert der Marker (nach dem Einschwingen)
const T_STOPP := 4.0                     # danach steht er still (Erholung)
const V0 := 140.0

var omega_inst := 0.0     # rad/s, aus dem Bau (erst nach dem Einschwingen gueltig!)
var rate := 0.0           # rad/s Markerrate dieses Falls
var yaw0 := 0.0
var bias0 := 0.0          # Querversatz am Ende des Einschwingens (= der bekannte 5.4-Grad-Sockel)

# Messgroessen im eingeschwungenen Fenster (letzte 4 s des Ziehens)
var lag_acc := 0.0        # Nachlauf ENTLANG der Markerbahn (rad, + = Nase hinterher)
var lag_n := 0
var lag_max := 0.0
var quer_acc := 0.0       # Querversatz (rad, betragsmaessig)
var err_acc := 0.0        # Grosskreisfehler gesamt (Vergleichbarkeit mit mf_track)
var w_acc := 0.0          # erreichte Nasen-Drehrate (Grosskreis)
var w_n := 0
var prev_nose := Vector3.FORWARD
var lag_stop := 0.0       # Nachlauf im Moment des Marker-Stopps
var lag_end := 0.0        # Nachlauf am Ende der Erholung
var vorbei := false       # Vorzeichenwechsel = Vorbeiziehen waehrend der Erholung?
var v_mit := 0.0
var v_n := 0
var aoa_max := 0.0
var g_max := 0.0


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	if frame == 2:
		var bc := BuildController.new()
		root.add_child(bc)
		fc = FlightController.new()
		root.add_child(fc)
		fc.build_from_design(_load_design())
		fc.set_active(true)
		fc.mouse_fly = true
		_start()
		return false
	var ac := fc.aircraft
	fc.throttle = 1.0
	t += delta
	var tz := t - T_SETTLE     # Zieh-Zeit (negativ = Einschwingphase)
	# --- omega_inst erst messen, wenn airspeed wirklich anliegt (sonst greift die
	#     qf-Untergrenze 0.04 und _auth_rates liefert Unsinn: 0.036 statt 0.298) ---
	if omega_inst <= 0.0 and t > T_SETTLE * 0.5:
		omega_inst = fc._auth_rates().x
		rate = FRAC[case_i] * omega_inst
		if case_i == 0:
			print("Zelle: masse=%.0f kg  fluegel=%.1f m2  kapazitaet=%.1f g" % [
				ac.mass, ac.wing_area, ac.wing_capacity / maxf(ac.mass * 9.81, 1.0)])
			print("omega_inst (= _auth_rates().x bei %.0f m/s) = %.3f rad/s = %.1f Grad/s" % [
				ac.airspeed, omega_inst, rad_to_deg(omega_inst)])
			print("")
	# --- Zeiger fuehren: reine Azimut-Wanderung (der klassische Zieh-Fall) ---
	if tz > 0.0 and tz <= T_ZIEH:
		fc.look_yaw = yaw0 + rate * tz
	var aim: Vector3 = fc._aim_dir()
	var nose: Vector3 = -ac.global_transform.basis.z
	var err := acos(clampf(nose.dot(aim), -1.0, 1.0))
	# --- FEHLERZERLEGUNG am Zeiger (nicht in Koerperachsen — die kippen bei Bank) ---
	# u = Tangente der Markerbahn IN Wanderrichtung. Fuer die Azimut-Wanderung ist
	# d(aim)/d(yaw) = (cos yaw, 0, sin yaw) — das ist genau aim x UP (NICHT UP x aim,
	# das zeigt entgegengesetzt und dreht das Vorzeichen des Schleppfehlers um).
	var u := aim.cross(Vector3.UP)
	if u.length() < 1e-5:
		u = Vector3.RIGHT
	u = u.normalized()
	var c := u.cross(aim).normalized()          # Querrichtung (im Wesentlichen "oben")
	# +lag = Nase laeuft der Markerbahn HINTERHER, -lag = Nase ist vorbeigezogen
	var lag := -atan2(nose.dot(u), nose.dot(aim))
	var quer := asin(clampf(nose.dot(c), -1.0, 1.0))
	# erreichte Nasen-Drehrate am GROSSKREIS (nicht Koerperachse)
	var wn := prev_nose.angle_to(nose) / maxf(delta, 1e-5)
	prev_nose = nose
	if tz <= 0.0:
		bias0 = quer                              # Sockel am Ende des Einschwingens
		return false
	aoa_max = maxf(aoa_max, absf(ac.aoa_signed))
	g_max = maxf(g_max, ac.load_factor)
	if tz > T_ZIEH - 4.0 and tz <= T_ZIEH:
		lag_acc += lag
		lag_n += 1
		lag_max = maxf(lag_max, lag)
		quer_acc += absf(quer)
		err_acc += err
		w_acc += wn
		w_n += 1
		v_mit += ac.airspeed
		v_n += 1
	if tz > T_ZIEH:
		if lag_stop == 0.0:
			lag_stop = lag
		if lag < -deg_to_rad(0.3):
			vorbei = true                          # Nase ist am Zeiger VORBEIgezogen
		lag_end = lag
		lag_max = maxf(lag_max, lag)
	if tz > T_ZIEH + T_STOPP:
		_bericht()
		case_i += 1
		if case_i >= FRAC.size():
			quit()
			return true
		_start()
	return false


func _bericht() -> void:
	var lag_mit := lag_acc / maxf(lag_n, 1)
	var quer_mit := quer_acc / maxf(lag_n, 1)
	var err_mit := err_acc / maxf(lag_n, 1)
	var w_ist := w_acc / maxf(w_n, 1)
	var art := "SAETTIGUNG" if FRAC[case_i] > 1.0 else "regelbar  "
	print("%3.0f%% von omega_inst  Markerrate=%5.2f Grad/s  [%s]" % [
		FRAC[case_i] * 100.0, rad_to_deg(rate), art])
	print("    SCHLEPPFEHLER (entlang der Bahn, Mittel letzte 4 s) = %7.2f Grad   Spitze = %7.2f Grad" % [
		rad_to_deg(lag_mit), rad_to_deg(lag_max)])
	print("    Querversatz (Sockel, andere Baustelle)              = %7.2f Grad   (Start %5.2f Grad)" % [
		rad_to_deg(quer_mit), rad_to_deg(bias0)])
	print("    Grosskreisfehler gesamt (wie mf_track zaehlt)       = %7.2f Grad" % rad_to_deg(err_mit))
	print("    Nase dreht %5.2f Grad/s von %5.2f Grad/s gefordert -> Ratenausnutzung %.2f" % [
		rad_to_deg(w_ist), rad_to_deg(rate), w_ist / maxf(rate, 1e-6)])
	print("    Erholung: %7.2f Grad bei Marker-Stopp -> %7.2f Grad nach %.0f s   Vorbeiziehen=%s" % [
		rad_to_deg(lag_stop), rad_to_deg(lag_end), T_STOPP, "JA" if vorbei else "nein"])
	print("    v=%5.1f m/s  aoa_max=%5.2f Grad (Limit %.2f)  g_max=%.1f" % [
		v_mit / maxf(v_n, 1), rad_to_deg(aoa_max), rad_to_deg(FlightController.AOA_MAX), g_max])
	print("")


func _start() -> void:
	fc.build_from_design(fc.design)
	var ac := fc.aircraft
	ac.global_transform = Transform3D(Basis(), Vector3(0, 3000, 0))
	ac.linear_velocity = Vector3(0, 0, -V0)
	ac.angular_velocity = Vector3.ZERO
	ac.gear_down = false
	fc.look_yaw = 0.0
	fc.look_pitch = 0.0
	fc._reset_mouse_state()
	yaw0 = fc.look_yaw
	omega_inst = 0.0
	rate = 0.0
	prev_nose = -ac.global_transform.basis.z
	t = 0.0
	lag_acc = 0.0
	lag_n = 0
	lag_max = 0.0
	quer_acc = 0.0
	err_acc = 0.0
	w_acc = 0.0
	w_n = 0
	lag_stop = 0.0
	lag_end = 0.0
	vorbei = false
	bias0 = 0.0
	v_mit = 0.0
	v_n = 0
	aoa_max = 0.0
	g_max = 0.0


func _load_design() -> Array:
	var f := FileAccess.open("user://aircraft_design.json", FileAccess.READ)
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
