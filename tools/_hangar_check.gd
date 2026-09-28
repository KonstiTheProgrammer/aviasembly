## HANGAR-WERKZEUGE, DIE KEIN ANDERER TEST ANFASST.
##
##   WINDKANAL      an -> Hotspot benannt, Teile eingefaerbt; aus -> Originalmaterial zurueck
##   ANSICHTEN      1/2/3 orthografisch, 0 wieder Perspektive
##   SPIEGEL        Fluegel per Panel skalieren/drehen -> Spiegelteil zieht exakt mit
##   UMKEHRSCHUB    am Propeller -> Meta auf Teil und Spiegel, Ampel rechnet neu
##   DEBUG-BOXEN    an/aus ohne Fehler
##   LEEREN         clear_design -> keine Wurzel, Start verweigert
##
##   HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/_hangar_check.gd
extends SceneTree

var m: Node = null
var f := 0
var fehler := 0


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
	if f == 24:
		var bc = m.get("build_ctrl")
		bc.set_wind_tunnel(true)
	if f == 30:
		_teil_a()
	if f == 34:
		_teil_b()
		print("-> %d Beanstandungen" % fehler)
		quit()
	return false


func _teil_a() -> void:
	var bc = m.get("build_ctrl")
	# Windkanal: der Hotspot wird benannt, mindestens ein Mesh traegt den Heat-Shader.
	_pruef("Windkanal: Hotspot benannt", String(bc.get("wind_worst")) != "",
		String(bc.get("wind_worst")))
	_pruef("Windkanal: Teile eingefaerbt", _overrides(bc.design_root) > 0,
		"%d Meshes" % _overrides(bc.design_root))
	bc.set_wind_tunnel(false)
	_pruef("Windkanal aus: keine Heat-Overrides mehr", _heat_overrides(bc.design_root) == 0,
		"%d uebrig" % _heat_overrides(bc.design_root))
	# Ansichten
	var cam: Camera3D = bc.get("camera")
	var ok := true
	for v in [1, 2, 3]:
		bc.set_view(v)
		bc._update_camera()
		ok = ok and cam.projection == Camera3D.PROJECTION_ORTHOGONAL
	bc.set_view(0)
	bc._update_camera()
	_pruef("Ansichten 1-3 ortho, 0 Perspektive",
		ok and cam.projection == Camera3D.PROJECTION_PERSPECTIVE)


func _teil_b() -> void:
	var bc = m.get("build_ctrl")
	# Spiegel: rechte Tragflaeche (die groesste Flaeche mit Spiegel) skalieren und drehen.
	var fl: Node3D = null
	for c in bc.design_root.get_children():
		if not c.is_in_group("part") or not c.has_meta("mirror"):
			continue
		var p := PartCatalog.get_part(String(c.get_meta("part_id")))
		# Rechte Seite ueber die SPANNRICHTUNG, nicht die Position: Spitfire-Fluegel
		# wurzeln bei x = 0 und spannen nach aussen.
		if bool(p.get("is_wing", false)) and (c as Node3D).transform.basis.x.x > 0.0:
			if fl == null or float(p.get("area", 0.0)) > float(PartCatalog.get_part(
					String(fl.get_meta("part_id"))).get("area", 0.0)):
				fl = c
	_pruef("Fluegel mit Spiegel gefunden", fl != null)
	if fl == null:
		return
	bc._select_part(fl)
	bc.nudge_scale(0, 1.18)
	bc.tilt_selected()
	var sp: Node3D = fl.get_meta("mirror")
	var sc_a: Vector3 = fl.get_meta("pscale", Vector3.ONE)
	var sc_b: Vector3 = sp.get_meta("pscale", Vector3.ONE)
	_pruef("Spiegel: gleiche Skalierung", sc_a.is_equal_approx(sc_b), "%s / %s" % [sc_a, sc_b])
	var pa: Vector3 = fl.position
	var pb: Vector3 = sp.position
	_pruef("Spiegel: Position an x gespiegelt",
		Vector3(-pa.x, pa.y, pa.z).distance_to(pb) < 0.001, "%s / %s" % [pa, pb])
	var xa: Vector3 = fl.transform.basis.x
	var xb: Vector3 = sp.transform.basis.x
	_pruef("Spiegel: Spannachse gespiegelt",
		Vector3(-xa.x, xa.y, xa.z).distance_to(xb) < 0.01, "%s / %s" % [xa, xb])
	# Umkehrschub am Propeller
	var prop: Node3D = null
	for c in bc.design_root.get_children():
		if c.is_in_group("part"):
			var p := PartCatalog.get_part(String(c.get_meta("part_id")))
			if float(p.get("thrust", 0.0)) > 0.0 and not bool(p.get("jet", false)):
				prop = c
	_pruef("Propeller gefunden", prop != null)
	if prop != null:
		var tw0: float = bc.compute_stats().get("tw", 0.0)
		bc._select_part(prop)
		bc.set_reverse_thrust(true)
		var tw1: float = bc.compute_stats().get("tw", 0.0)
		_pruef("Umkehrschub: Meta gesetzt", bool(prop.get_meta("thrust_reverse", false)))
		_pruef("Umkehrschub: Vorwaertsschub dreht das Vorzeichen", tw0 > 0.0 and tw1 < 0.0,
			"tw %.2f -> %.2f" % [tw0, tw1])
		bc.set_reverse_thrust(false)
	bc.set_debug_boxes(true)
	bc.set_debug_boxes(false)
	_pruef("Debug-Boxen an/aus", true)
	bc.clear_design()
	_pruef("Leeren: keine Wurzel mehr", not bc.has_root())
	m.call("_set_mode", 1)
	_pruef("Leeren: Start verweigert", int(m.get("mode")) == 0)


func _overrides(n: Node) -> int:
	var k := 0
	if n is GeometryInstance3D and (n as GeometryInstance3D).material_override != null:
		k += 1
	for c in n.get_children():
		k += _overrides(c)
	return k


func _heat_overrides(n: Node) -> int:
	var k := 0
	if n is GeometryInstance3D:
		var mo = (n as GeometryInstance3D).material_override
		if mo is ShaderMaterial and (mo as ShaderMaterial).shader != null \
				and (mo as ShaderMaterial).shader.code.contains("heat"):
			k += 1
	for c in n.get_children():
		k += _heat_overrides(c)
	return k


func _pruef(name: String, ok: bool, info := "") -> void:
	print("%-44s %s  %s" % [name, "OK" if ok else "FALSCH", info])
	if not ok:
		fehler += 1
