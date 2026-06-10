## Headless-Test des MAUS-FLUG-Reglers (nach dem Smoothness-Umbau).
## Prüft pro Zielrichtung (vorne/rechts/180°-hinten/oben):
##   (a) Konvergenz: align(-Z, Ziel) erreicht >= 0.99 (Flick-Zeit gemessen)
##   (b) Stabilität: max. Drehrate im eingeschwungenen Zustand < 2.5 rad/s
##       (deckt den knackigen Bank-Ausroll am Settle-Rand ab; Trudeln fängt das SD-Gate)
##   (c) Pendeln: Stddev des Horizontalfehlers über ~300 Frames < 0.09 rad
## BASELINE (gemessen, alter == neuer Regler — airframe-bedingtes Rest-Weaving der
## Bank-to-turn-Kaskade): vorne 0.000 / rechts90 ~0.075 / hinten180 ~0.017 / oben ~0.001.
## Das Gate (0.09) ist Regressionsschutz; der große Gewinn des Umbaus: 180°-Flick
## t99 13.4 s -> 2.8 s (adaptive Glättung), Kamera-/Ziel-Ruhe im Spiel.
## Start: Godot --headless --path . --script res://tools/mousefly_test.gd
## (Setup erst im ersten _process-Frame — bekannte SceneTree-Falle; set_active(true) nötig!)
extends SceneTree

var fc: FlightController
var frame := 0
var case_i := -1
var t := 0.0
var t99 := -1.0
var settled := false
var hold := 0                 # Frames in Folge nahe am Ziel (echtes Einschwingen, kein Durchschwinger)
var horiz_samples: PackedFloat64Array = PackedFloat64Array()
var max_w := 0.0
var fails := 0

const CASES := [
	{"name": "vorne", "yaw": 0.0, "pitch": 0.0},
	{"name": "rechts90", "yaw": PI * 0.5, "pitch": 0.0},
	{"name": "hinten180", "yaw": PI, "pitch": 0.0},
	{"name": "oben60", "yaw": 0.0, "pitch": 1.0},
]


func _process(delta: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	if frame == 2:
		_setup()
		_next_case()
		return false
	if fc == null or not is_instance_valid(fc.aircraft):
		return false
	var ac := fc.aircraft
	fc.throttle = 1.0
	t += delta
	var aim: Vector3 = fc._aim_dir()
	var nose: Vector3 = -ac.global_transform.basis.z
	var align := nose.dot(aim)
	if t99 < 0.0 and align > 0.99:
		t99 = t
	# EINGESCHWUNGEN = 1 s in Folge nahe am Ziel (sonst misst man den Durchschwinger mit)
	if not settled:
		hold = hold + 1 if align > 0.995 else 0
		if hold >= 60:
			settled = true
	else:
		var e: Vector3 = ac.global_transform.basis.transposed() * aim
		horiz_samples.push_back(atan2(e.x, -e.z))
		max_w = maxf(max_w, ac.angular_velocity.length())
	# Fall abschließen: genug eingeschwungene Samples ODER Timeout
	if horiz_samples.size() >= 300 or t > 18.0:
		_finish_case(align)
		if case_i >= CASES.size() - 1:
			print("==> %s" % ("ALLE TESTS BESTANDEN ✓" if fails == 0 else "%d TEST(S) FEHLGESCHLAGEN ✗" % fails))
			quit(1 if fails > 0 else 0)
			return true
		_next_case()
	return false


func _setup() -> void:
	var bc := BuildController.new()
	root.add_child(bc)
	fc = FlightController.new()
	root.add_child(fc)
	fc.build_from_design(_design(bc))
	fc.set_active(true)      # _ready schaltet Processing aus — ohne das läuft der Regler nicht!
	fc.mouse_fly = true


func _next_case() -> void:
	case_i += 1
	var c: Dictionary = CASES[case_i]
	var ac := fc.aircraft
	# Level-Flug in der Höhe mit Tempo, Nase nach -Z
	ac.global_transform = Transform3D(Basis(), Vector3(0, 300, 0))
	ac.linear_velocity = Vector3(0, 0, -70.0)
	ac.angular_velocity = Vector3.ZERO
	# Flick: Ziel springt auf die Fall-Richtung, Glättung startet an der Nase (wie _toggle)
	fc.look_yaw = float(c["yaw"])
	fc.look_pitch = float(c["pitch"])
	fc._aim_smooth = -ac.global_transform.basis.z
	t = 0.0
	t99 = -1.0
	settled = false
	hold = 0
	horiz_samples = PackedFloat64Array()
	max_w = 0.0


func _finish_case(align: float) -> void:
	var c: Dictionary = CASES[case_i]
	var sd := 0.0
	if horiz_samples.size() > 10:
		var mean := 0.0
		for v in horiz_samples:
			mean += v
		mean /= horiz_samples.size()
		for v in horiz_samples:
			sd += (v - mean) * (v - mean)
		sd = sqrt(sd / horiz_samples.size())
	var ok_conv := t99 >= 0.0
	var ok_w := settled and max_w < 2.5
	var ok_lc := settled and sd < 0.09
	var ok := ok_conv and ok_w and ok_lc
	if not ok:
		fails += 1
	print("%-10s align=%.4f  t99=%5.2fs  maxW=%.2f  horizSD=%.5f  %s" % [
		c["name"], align, t99, max_w, sd, "OK" if ok else "FAIL(conv=%s w=%s lc=%s)" % [ok_conv, ok_w, ok_lc]])


func _design(bc: BuildController) -> Array:
	bc.clear_design()
	var d: Array = []
	d.append({"id": "cockpit", "xform": Transform3D(Basis(), Vector3.ZERO)})
	d.append({"id": "nose", "xform": Transform3D(Basis(), Vector3(0, 0, -2.0))})
	d.append({"id": "fuselage", "xform": Transform3D(Basis(), Vector3(0, 0, 1.9))})
	d.append({"id": "tailcone", "xform": Transform3D(Basis(), Vector3(0, 0, 3.6))})
	d.append({"id": "jet_engine", "xform": Transform3D(Basis(), Vector3(0, 0, 1.0))})
	var nx := Basis(Vector3(1, 0, 0), 0.0)
	d.append({"id": "wing_swept", "xform": Transform3D(nx, Vector3(0.6, 0, 0.6))})
	d.append({"id": "wing_swept", "xform": Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(-0.6, 0, 0.6))})
	d.append({"id": "h_stab", "xform": Transform3D(Basis(), Vector3(0.5, 0.1, 3.6))})
	d.append({"id": "h_stab", "xform": Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)), Vector3(-0.5, 0.1, 3.6))})
	d.append({"id": "v_stab", "xform": Transform3D(Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)), Vector3(0, 0.5, 3.6))})
	return d
