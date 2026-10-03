## DER AKTIVE VULKAN (scripts/Vulkanausbruch.gd): Aufbau, Asche im Flug, Druckwelle, Aufwind.
##
##   AUFBAU      Saeule, Schirm, beide Fassungen der Ausbruchseffekte, Dampf, Fontaene, Regen,
##               Druckwelle stehen im Baum
##   DICHTE      mitten in der Saeule und im Schirm hoch, weit weg null
##   AUSBRUCH    ausloesen() setzt stoss_alter der neuen Fassung auf 0, die andere bleibt
##   WELLE       trifft einen Punkt in 3 km genau dann, wenn sie mit 340 m/s dort ankommt
##   IM FLUG     Flugzeug in die Saeule gesetzt: Nebel dicht und DUNKEL, Turbulenz hoch, Aufwind;
##               wieder heraus: Nebel weg
##
##   HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/_vulkan_ausbruch_check.gd
extends SceneTree

var m: Node = null
var f := 0
var fehler := 0
var v: Vulkanausbruch
var in_saeule := Vector3.ZERO


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 20:
		m.call("_set_mode", 1)
	if f == 40:
		_aufbau()
	if f >= 41 and f <= 160:
		_festhalten(in_saeule)
	if f == 160:
		_in_der_asche()
	if f >= 161 and f <= 260:
		_festhalten(v.schlot + Vector3(-9000.0, 1200.0, 0.0))
	if f == 260:
		var wd: float = m.get("wolken_dichte")
		_pruef("wieder draussen: kein Aschenebel", wd < 0.1, "Dichte %.2f" % wd)
		print("-> %d Beanstandungen" % fehler)
		quit()
	return false


func _festhalten(p: Vector3) -> void:
	var ac: RigidBody3D = m.get("flight_ctrl").get("aircraft")
	ac.global_position = p
	ac.linear_velocity = Vector3.ZERO
	ac.angular_velocity = Vector3.ZERO


func _aufbau() -> void:
	v = m.get("vulkan")
	_pruef("Vulkanausbruch gebaut", v != null)
	if v == null:
		quit()
		return
	for nm in ["Saeule_0", "Schirm_0", "Ausbruchswolke0_0", "Ausbruchswolke1_0", "Lavabomben0",
			"Lavabomben1", "Rauchspuren0", "Rauchspuren1", "Dampf", "Funken", "Ascheregen",
			"Druckwelle", "Vulkanblitz0"]:
		_pruef("Knoten " + nm, v.get_node_or_null(nm) != null)
	_pruef("Kraterrand ueber dem See", v.rand_tiefe > 100.0, "%.0f m" % v.rand_tiefe)
	var h := 1500.0
	var hz := h / v.steig_h
	var achse := v.wind * v.neigung * v.steig_h * pow(hz, v.biegung)
	in_saeule = v.schlot + Vector3(achse.x, h, achse.y)
	var d_s := v.dichte_bei(in_saeule)
	_pruef("Saeule 1500 m: dicht", d_s > 0.9, "%.2f" % d_s)
	var oben := v.schlot + Vector3(v.wind.x, 0.0, v.wind.y) * (v.neigung * v.steig_h + v.schirm_l * 0.3) \
		+ Vector3(0.0, v.steig_h, 0.0)
	var d_o := v.dichte_bei(oben)
	_pruef("Schirm: dicht", d_o > 0.5, "%.2f" % d_o)
	var weit := v.dichte_bei(v.schlot + Vector3(-5000.0, 1000.0, 0.0))
	_pruef("5 km gegen den Wind: frei", weit == 0.0, "%.2f" % weit)
	var auf := v.aufwind_bei(v.schlot + Vector3(0.0, 300.0, 0.0))
	_pruef("Aufwind ueber dem Schlot", auf > 0.3, "%.2f g" % auf)
	# Ausbruch
	v.ausloesen()
	var fa: int = v._fassung
	_pruef("Ausbruch: neue Fassung bei 0 s", v._alter_ab[fa] == 0.0 and v._alter_ab[1 - fa] > 1.0)
	# Druckwelle: 3 km vom Schlot auf Randhoehe
	var p3 := v.schlot + Vector3(3000.0, v.rand_tiefe * 0.8, 0.0)
	v._alter = 8.0
	var w_frueh := v.welle_trifft(p3, 0.1)
	v._alter = 3000.0 / Vulkanausbruch.SCHALL + 0.05
	var w_da := v.welle_trifft(p3, 0.1)
	_pruef("Welle trifft 3 km nach 8,8 s, nicht frueher", w_frueh == 0.0 and w_da > 0.0,
		"%.2f / %.2f" % [w_frueh, w_da])
	v._alter = 0.0


func _in_der_asche() -> void:
	var wd: float = m.get("wolken_dichte")
	var ak: float = m.get("_asche_k")
	var fc: Node = m.get("flight_ctrl")
	_pruef("in der Saeule: Nebel dicht", wd > 0.8, "Dichte %.2f" % wd)
	_pruef("in der Saeule: Nebel ist Asche", ak > 0.8, "%.2f" % ak)
	var env: Environment = m.get("env_sky")
	var c := env.fog_light_color
	_pruef("Nebelfarbe dunkel", c.get_luminance() < 0.35, "%.2f %.2f %.2f" % [c.r, c.g, c.b])
	_pruef("Turbulenz hoch", float(fc.get("turbulenz_faktor")) > 3.0, "%.1f" % float(fc.get("turbulenz_faktor")))
	_pruef("Aufwind in der Saeule", float(fc.get("aufwind")) > 0.1, "%.2f g" % float(fc.get("aufwind")))


func _pruef(name: String, ok: bool, info := "") -> void:
	print("%-44s %s  %s" % [name, "OK" if ok else "FALSCH", info])
	if not ok:
		fehler += 1
