## SCHADENSMODELL VON ANFANG BIS RESET.
##
## Prueft in der echten Main-Szene (Vorlage "spitfire", in der Luft):
##   FLUEGELBRUCH   Hauptfluegel abreissen -> Teile als Truemmer weg, Auftriebsflaeche sinkt,
##                  Rest fliegt weiter (keine NaN), Schadensrauch
##   DRUCKWELLE     Flak-Volltreffer (take_blast) -> Stoss + Fluegel ab
##   ZERSCHELLEN    Absturz mit eingefahrenem Fahrwerk -> exploded, keine Fehler
##   RESET          Enter (_reset_to_runway) -> alles wieder heil, Fluegelflaeche wie vorher
##
##   HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/_schaden_check.gd
extends SceneTree

var m: Node = null
var f := 0
var t := 0
var phase := 0
var fehler := 0
var flaeche0 := 0.0
var teile0 := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 20:
		m.call("_load_design_from", "res://designs/spitfire.json")
		m.call("_set_mode", 1)
		return false
	if f < 40:
		return false
	var fc = m.get("flight_ctrl")
	var ac = fc.get("aircraft")
	t += 1
	match phase:
		0:
			_in_die_luft(ac)
			flaeche0 = float(ac.get("wing_area"))
			teile0 = _heile_teile(ac)
			ac.call("_queue_break", ac.call("_wing_root_indices"))
			phase = 1
			t = 0
		1:
			if t == 30:
				var fl := float(ac.get("wing_area"))
				_pruef("Fluegelbruch: Auftriebsflaeche sinkt", fl < flaeche0 * 0.6,
					"%.1f -> %.1f m2" % [flaeche0, fl])
				_pruef("Fluegelbruch: Teile abgetrennt", _heile_teile(ac) < teile0,
					"%d -> %d heile Teile" % [teile0, _heile_teile(ac)])
				_pruef("Fluegelbruch: Truemmer in der Welt", _truemmer() > 0)
				_pruef("Fluegelbruch: Lage endlich", ac.global_position.is_finite())
				fc.call("_reset_to_runway")
				phase = 2
				t = 0
		2:
			if t == 20:
				ac = fc.get("aircraft")
				_pruef("Reset: Fluegelflaeche wieder voll",
					absf(float(ac.get("wing_area")) - flaeche0) < 0.01)
				_in_die_luft(ac)
				ac.call("take_blast", ac.global_position + Vector3(0, -2.0, 0), 34.0, 23.0)
				phase = 3
				t = 0
		3:
			if t == 30:
				_pruef("Druckwelle: Volltreffer reisst die Fluegel ab",
					float(ac.get("wing_area")) < flaeche0 * 0.6)
				fc.call("_reset_to_runway")
				phase = 4
				t = 0
		4:
			if t == 20:
				ac = fc.get("aircraft")
				_in_die_luft(ac)
				ac.call("toggle_gear")
				phase = 5
				t = 0
		5:
			if t == 90:
				# STURZFLUG mit der Nase voran, 80 m/s, ueber Land. Flach fallend bremst die
				# Tragflaeche den Fall unter EXPLODE_SPEED (gemessen 60 -> 24 m/s) — das ist
				# richtig so, taugt aber nicht als Absturz.
				var bx := 2600.0
				var bz := 1800.0
				var h: float = m.get("terrain").call("height_at", bx, bz)
				m.get("terrain").call("build_now_around", Vector3(bx, h, bz), 500.0)
				ac.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5),
					Vector3(bx, h + 40.0, bz))
				ac.linear_velocity = Vector3(0, -80.0, 0)
			if t > 90 and bool(ac.get("exploded")):
				_pruef("Zerschellen mit eingefahrenem Fahrwerk", true)
				fc.call("_reset_to_runway")
				phase = 6
				t = 0
			elif t > 400:
				_pruef("Zerschellen mit eingefahrenem Fahrwerk", false, "nicht explodiert")
				phase = 7
		6:
			if t == 20:
				ac = fc.get("aircraft")
				_pruef("Reset nach Zerschellen: heil und startklar",
					not bool(ac.get("exploded")) and not ac.freeze
					and absf(float(ac.get("wing_area")) - flaeche0) < 0.01)
				phase = 7
		7:
			print("-> %d Beanstandungen" % fehler)
			quit()
	return false


func _in_die_luft(ac) -> void:
	ac.global_transform = Transform3D(Basis(), Vector3(4000.0, 500.0, 4000.0))
	ac.linear_velocity = Vector3(0, 0, -90.0)
	ac.angular_velocity = Vector3.ZERO


func _heile_teile(ac) -> int:
	var n := 0
	for p in ac.get("parts"):
		if not bool(p.get("broken", false)):
			n += 1
	return n


func _truemmer() -> int:
	return get_nodes_in_group_count("debris")


func get_nodes_in_group_count(g: String) -> int:
	return get_nodes_in_group(g).size()


func _pruef(name: String, ok: bool, info := "") -> void:
	print("%-50s %s  %s" % [name, "OK" if ok else "FALSCH", info])
	if not ok:
		fehler += 1
