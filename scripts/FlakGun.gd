class_name FlakGun
extends Node3D

# Flugabwehr-Geschütz, das eine FLAK-ZONE verteidigt. Sobald der Spieler in der Zone und im
# Höhen-Band ist, rechnet es eine Vorhalt-/Abfanglösung (aus Position+Geschwindigkeit), feuert
# eine sichtbare Granate und telegrafiert den Einschlag: großer roter Kreis (Druckwellen-Radius)
# + Countdown. Beim Ablauf explodiert die Granate -> Druckwelle (Schaden) am echten Spielerort.
# Tiefer Flug = schnellere Granate = kürzere Vorwarnzeit (gefährlicher). Wegfliegen = ausweichen.

# --- von _spawn gesetzt (Zone) ---
var zone_center := Vector3.ZERO
var zone_radius := 320.0

const RANGE := 1700.0           # max. Verfolgungsdistanz (Lauf zielt)
const MIN_ALT := 45.0           # Zielband: darunter feuert die Flak NICHT (zu tief)
const MAX_ALT := 650.0          # ... darüber auch nicht (zu hoch)
const SHELL_SPEED_LO := 340.0   # Granaten-Tempo TIEF (schnell -> kurze Vorwarnzeit)
const SHELL_SPEED_HI := 195.0   # ... HOCH (langsam -> mehr Reaktionszeit)
const FIRE_CD := 3.0            # Sekunden zwischen Schüssen (pro Geschütz)
const MAX_LEAD_T := 11.0        # Lösung verwerfen, wenn Flugzeit länger
const BLAST_RADIUS := 34.0      # Radius Druckwelle = Größe des roten Kreises (m)
const BLAST_DV := 23.0          # Spitzen-Geschwindigkeitsstoß im Zentrum (m/s, ×Masse)
const SPREAD := 6.5             # Streuung der Lösung (m)

const MARKER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform vec3 col : source_color = vec3(1.0, 0.12, 0.08);
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	if (r > 1.0) { discard; }
	float ring = smoothstep(0.80, 0.88, r) - smoothstep(0.94, 1.0, r);
	float fillmask = 1.0 - smoothstep(fill - 0.03, fill + 0.03, r);
	float a = clamp(ring * 0.95 + fillmask * 0.28, 0.0, 0.92);
	ALBEDO = col;
	ALPHA = a;
	EMISSION = col * (ring * 1.6 + fillmask * 0.45);
}
"""

var _cd := 2.0
var _turret: Node3D
var _cradle: Node3D
var _muzzle: Node3D
var _shells: Array = []
var _shader: Shader


func _ready() -> void:
	_build_model()
	_cd = randf_range(0.8, FIRE_CD)   # Geschütze versetzt feuern lassen


# ===========================================================================
func _process(delta: float) -> void:
	var plane := _find_player()
	if plane == null:
		_clear_shells()
		return
	var p: Vector3 = plane.global_position
	var alt: float = p.y - global_position.y
	var altf := clampf((alt - MIN_ALT) / (MAX_ALT - MIN_ALT), 0.0, 1.0)
	var speed := lerpf(SHELL_SPEED_LO, SHELL_SPEED_HI, altf)   # tief = schnell
	var sol := _intercept(p, plane.linear_velocity, speed)
	if sol["ok"] and global_position.distance_to(p) < RANGE:
		_aim(sol["point"])
		var in_band := alt > MIN_ALT and alt < MAX_ALT
		var in_zone := Vector2(p.x - zone_center.x, p.z - zone_center.z).length() < zone_radius
		if in_band and in_zone:
			_cd -= delta
			if _cd <= 0.0:
				_fire(sol)
				_cd = FIRE_CD
	_update_shells(delta, plane)


func _find_player() -> AircraftBody:
	var n := get_tree().get_first_node_in_group("player")
	if n is AircraftBody and is_instance_valid(n):
		return n
	return null


# Quadratische Abfanglösung: t mit |P + V*t - G| = speed*t (Granate trifft den Ort, wo der
# Spieler in t Sekunden ist -> bezieht Höhe/Position UND Geschwindigkeit ein).
func _intercept(p_pos: Vector3, p_vel: Vector3, speed: float) -> Dictionary:
	var gun: Vector3 = _muzzle.global_position
	var d := p_pos - gun
	var a := p_vel.dot(p_vel) - speed * speed
	var b := 2.0 * d.dot(p_vel)
	var c := d.dot(d)
	var t := -1.0
	if absf(a) < 0.01:
		if absf(b) > 0.0001:
			t = -c / b
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq := sqrt(disc)
			for cand in [(-b - sq) / (2.0 * a), (-b + sq) / (2.0 * a)]:
				if cand > 0.05 and (t < 0.0 or cand < t):
					t = cand
	if t <= 0.0 or t > MAX_LEAD_T:
		return {"ok": false}
	return {"ok": true, "t": t, "point": p_pos + p_vel * t}


func _fire(sol: Dictionary) -> void:
	var t: float = sol["t"]
	var point: Vector3 = sol["point"] + Vector3(
		randf_range(-SPREAD, SPREAD), randf_range(-SPREAD, SPREAD), randf_range(-SPREAD, SPREAD))
	var mk := _make_marker(point)
	var shell := _make_shell()
	shell.global_position = _muzzle.global_position
	_muzzle_flash()
	_shells.append({
		"node": mk["node"], "mat": mk["mat"], "label": mk["label"],
		"shell": shell, "from": _muzzle.global_position, "point": point, "t_left": t, "t_total": t,
	})


func _update_shells(delta: float, plane: AircraftBody) -> void:
	for i in range(_shells.size() - 1, -1, -1):
		var s: Dictionary = _shells[i]
		s["t_left"] = float(s["t_left"]) - delta
		var frac := clampf(1.0 - float(s["t_left"]) / float(s["t_total"]), 0.0, 1.0)
		var shell: Node3D = s["shell"]
		if is_instance_valid(shell):
			shell.global_position = (s["from"] as Vector3).lerp(s["point"], frac)
		var mat: ShaderMaterial = s["mat"]
		if mat != null:
			mat.set_shader_parameter("fill", frac)
		var label: Label3D = s["label"]
		if is_instance_valid(label):
			label.text = "%.1f" % maxf(float(s["t_left"]), 0.0)
		if float(s["t_left"]) <= 0.0:
			_explode(s, plane)
			_shells.remove_at(i)


func _explode(s: Dictionary, plane: AircraftBody) -> void:
	var point: Vector3 = s["point"]
	if is_instance_valid(s["shell"]):
		s["shell"].queue_free()
	if is_instance_valid(s["node"]):
		s["node"].queue_free()
	_blast_fx(point)
	if plane != null and is_instance_valid(plane):
		plane.take_blast(point, BLAST_RADIUS, BLAST_DV)


func _clear_shells() -> void:
	for s in _shells:
		if is_instance_valid(s["node"]):
			s["node"].queue_free()
		if is_instance_valid(s["shell"]):
			s["shell"].queue_free()
	_shells.clear()


# ===========================================================================
# Granate (sichtbar anfliegend) + Marker (roter Kreis + Timer)
# ===========================================================================
func _make_shell() -> Node3D:
	var s := Node3D.new()
	add_child(s)
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.85
	sm.height = 1.7
	body.mesh = sm
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.material_override = _glow(Color(1.0, 0.78, 0.32), 7.0)
	s.add_child(body)
	# Leucht-Trail (Welt-Koordinaten -> Schweif bleibt liegen, während die Granate fliegt)
	var tr := CPUParticles3D.new()
	tr.local_coords = false
	tr.amount = 26
	tr.lifetime = 0.55
	tr.speed_scale = 1.0
	tr.direction = Vector3.ZERO
	tr.spread = 12.0
	tr.initial_velocity_min = 0.0
	tr.initial_velocity_max = 2.0
	tr.gravity = Vector3.ZERO
	tr.scale_amount_min = 0.6
	tr.scale_amount_max = 1.1
	var pm := SphereMesh.new()
	pm.radius = 0.35
	pm.height = 0.7
	pm.material = _glow(Color(1.0, 0.6, 0.2), 5.0)
	tr.mesh = pm
	s.add_child(tr)
	return s


func _make_marker(point: Vector3) -> Dictionary:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = MARKER_SHADER
	var node := Node3D.new()
	add_child(node)
	node.global_position = point
	var circle := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(BLAST_RADIUS * 2.0, BLAST_RADIUS * 2.0)
	circle.mesh = quad
	circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("fill", 0.0)
	circle.material_override = mat
	node.add_child(circle)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0007
	label.font_size = 110
	label.outline_size = 28
	label.modulate = Color(1.0, 0.92, 0.3)
	label.outline_modulate = Color(0, 0, 0, 0.85)
	node.add_child(label)
	return {"node": node, "mat": mat, "label": label}


func _muzzle_flash() -> void:
	var fl := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.7
	sm.height = 1.4
	fl.mesh = sm
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fl.material_override = _glow(Color(1.0, 0.85, 0.42), 7.0)
	add_child(fl)
	fl.global_position = _muzzle.global_position
	var tw := create_tween()
	tw.tween_property(fl, "scale", Vector3.ONE * 0.1, 0.09)
	tw.tween_callback(fl.queue_free)


# ===========================================================================
# Explosion (Blitz + Feuerball + Schockwelle + Rauch + Funken + Licht)
# ===========================================================================
func _blast_fx(point: Vector3) -> void:
	_fx_sphere(point, Color(1.0, 1.0, 0.85, 0.95), BLAST_RADIUS * 0.4, BLAST_RADIUS * 0.6, 0.12, 9.0)   # Blitz
	_fx_sphere(point, Color(1.0, 0.5, 0.16, 0.9), BLAST_RADIUS * 0.18, BLAST_RADIUS * 0.72, 0.5, 6.0)   # Feuerball
	_fx_ring(point, BLAST_RADIUS * 1.25, 0.45)                                                          # Schockwelle
	_fx_smoke(point)                                                                                    # Rauch
	_fx_sparks(point)                                                                                   # Funken
	_fx_light(point)                                                                                    # Lichtblitz


func _fx_sphere(point: Vector3, col: Color, r0: float, r1: float, dur: float, energy: float) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	m.mesh = sm
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _glow(Color(col.r, col.g, col.b), energy)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	m.material_override = mat
	add_child(m)
	m.global_position = point
	m.scale = Vector3.ONE * r0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * r1, dur)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.set_parallel(false)
	tw.tween_callback(m.queue_free)


func _fx_ring(point: Vector3, r1: float, dur: float) -> void:
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	m.mesh = tm
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _glow(Color(1.0, 0.82, 0.5), 4.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.6, 0.75)
	m.material_override = mat
	add_child(m)
	m.global_position = point
	m.scale = Vector3.ONE * 0.6
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * r1, dur)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.set_parallel(false)
	tw.tween_callback(m.queue_free)


func _fx_smoke(point: Vector3) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	m.mesh = sm
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.22, 0.21, 0.2, 0.7)
	m.material_override = mat
	add_child(m)
	m.global_position = point
	m.scale = Vector3.ONE * (BLAST_RADIUS * 0.3)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * (BLAST_RADIUS * 0.8), 1.4)
	tw.tween_property(m, "global_position", point + Vector3(0, BLAST_RADIUS * 0.5, 0), 1.4)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.4).set_delay(0.3)
	tw.set_parallel(false)
	tw.tween_callback(m.queue_free)


func _fx_sparks(point: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 30
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 100.0
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 34.0
	p.gravity = Vector3(0, -22.0, 0)
	p.scale_amount_min = 0.25
	p.scale_amount_max = 0.5
	var pm := SphereMesh.new()
	pm.radius = 0.35
	pm.height = 0.7
	pm.material = _glow(Color(1.0, 0.72, 0.28), 5.0)
	p.mesh = pm
	add_child(p)
	p.global_position = point
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)


func _fx_light(point: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.62, 0.26)
	l.light_energy = 9.0
	l.omni_range = BLAST_RADIUS * 1.6
	add_child(l)
	l.global_position = point
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


# ===========================================================================
# Modell + Zielen
# ===========================================================================
func _build_model() -> void:
	var gun := _mat(Color(0.17, 0.19, 0.20), 0.6, 0.42)
	var sand := _mat(Color(0.54, 0.49, 0.35), 0.0, 0.95)
	var concrete := _mat(Color(0.33, 0.33, 0.35), 0.0, 0.85)
	# Betonpad
	_mi(self, _cyl(4.4, 4.4, 0.5, 18), concrete, Vector3(0, 0.25, 0))
	# Sandsack-Ring
	var ring := TorusMesh.new()
	ring.inner_radius = 3.5
	ring.outer_radius = 4.5
	ring.rings = 10
	ring.ring_segments = 18
	_mi(self, ring, sand, Vector3(0, 0.7, 0))
	# feste Lafetten-Basis
	_mi(self, _cyl(1.3, 1.7, 1.1, 14), gun, Vector3(0, 0.95, 0))
	# Turm (dreht horizontal)
	_turret = Node3D.new()
	_turret.position = Vector3(0, 1.55, 0)
	add_child(_turret)
	_mi(_turret, _cyl(1.15, 1.25, 0.7, 14), gun, Vector3(0, 0.1, 0))
	# Wiege (kippt vertikal)
	_cradle = Node3D.new()
	_cradle.position = Vector3(0, 0.4, 0)
	_turret.add_child(_cradle)
	# Schutzschild vorne
	_mi(_cradle, _box(2.3, 1.5, 0.18), gun, Vector3(0, 0.25, -0.55))
	# Zwillingsrohre + Mündungsbremsen
	for sx in [-0.34, 0.34]:
		var bar := _mi(_cradle, _cyl(0.13, 0.17, 3.6, 12), gun, Vector3(sx, 0.0, -1.8))
		bar.rotation_degrees = Vector3(-90, 0, 0)
		var mb := _mi(_cradle, _cyl(0.24, 0.24, 0.45, 10), gun, Vector3(sx, 0.0, -3.55))
		mb.rotation_degrees = Vector3(-90, 0, 0)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.0, -3.85)
	_cradle.add_child(_muzzle)


func _aim(point: Vector3) -> void:
	if _turret == null:
		return
	var tp := _turret.global_position
	var flat := Vector3(point.x, tp.y, point.z)
	if tp.distance_to(flat) > 0.5:
		_turret.look_at(flat, Vector3.UP)     # nur Gieren (Ziel auf Turmhöhe)
	var d := point - tp
	var horiz := maxf(Vector2(d.x, d.z).length(), 0.001)
	var elev := clampf(atan2(d.y, horiz), 0.0, 1.4)   # 0..80°, nie unter den Horizont
	_cradle.rotation = Vector3(elev, 0.0, 0.0)         # Rohre (-Z) nach oben kippen


# ---- kleine Bau-Helfer ----
func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m


func _glow(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = Color(col.r, col.g, col.b)
	m.emission_energy_multiplier = energy
	return m


func _cyl(top: float, bot: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bot
	c.height = h
	c.radial_segments = seg
	return c


func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m
