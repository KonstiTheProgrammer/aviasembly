## Projectile.gd — abgefeuertes Geschoss: Kugel (gerade), Zielsuchrakete (homing)
## oder Bombe (Freifall). Treffererkennung gegen Gruppe "target" per Segment-Abstand.
class_name Projectile
extends Node3D

var kind := "bullet"          # bullet | missile | bomb
var vel := Vector3.ZERO
var life := 2.5
var damage := 1.0
var gravity := 0.0            # Bullet-Drop: m/s² nach unten (0 = schnurgerade). Pro Kaliber gesetzt.
var tracer_color := Color(1.0, 0.85, 0.2)  # Leuchtspur-Farbe (Kaliber)
var tracer_scale := 1.0       # Leuchtspur-Größe (größeres Kaliber = dicker/länger)
var turn := 3.0               # Lenkrate der Rakete (rad/s grob)
var guided := false           # Suchkopf aktiv? (sonst rein geradeaus)
var seek_range := 70.0        # Reichweite, ab der ein Ziel angeflogen wird
const SEEK_CONE := 0.2        # nur Ziele grob voraus erfassen (dot vel·Richtung)
var _target: Node3D = null

# Leuchtspur (Tracer): kameragerichtetes Band aus den letzten Weltpositionen, das zum
# Schweif hin ausblendet -> sichtbarer Schuss-/Drop-Bogen wie echtes Leuchtspurfeuer.
const TRAIL_LEN := 9          # Anzahl gespeicherter Stützpunkte (länger = längere Spur)
var _trail_mi: MeshInstance3D = null
var _trail_pts: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	_build_visual()


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if kind == "missile" and guided:
		_home(delta)
	if gravity != 0.0:
		vel.y -= gravity * delta   # Bullet-Drop / Bomben-Fall (ballistischer Bogen)
	var a := global_position
	global_position += vel * delta
	var b := global_position
	# Auch Geschosse an der Flugbahn ausrichten -> Leuchtspur kippt mit dem Drop-Bogen.
	# Up-Referenz absichern: ist die Bahn fast senkrecht (parallel zu UP), wirft look_at sonst.
	if vel.length() > 1.0:
		var up_ref := Vector3.UP
		if absf(vel.normalized().dot(Vector3.UP)) > 0.99:
			up_ref = Vector3.FORWARD
		look_at(b + vel, up_ref)
	# Leuchtspur fortschreiben (Ringpuffer der letzten Weltpositionen) + neu zeichnen
	if _trail_mi != null:
		_trail_pts.push_back(b)
		while _trail_pts.size() > TRAIL_LEN:
			_trail_pts.remove_at(0)
		_update_trail()
	# Treffer? (Strecke a->b gegen alle Ziele, damit schnelle Kugeln nicht durchtunneln)
	for t in get_tree().get_nodes_in_group("target"):
		if not is_instance_valid(t):
			continue
		if _seg_dist(a, b, t.global_position) < t.hit_radius:
			t.hit(damage)
			_boom()
			queue_free()
			return
	if kind == "bomb" and global_position.y <= 0.4:
		_boom()
		queue_free()


func _home(delta: float) -> void:
	# Suchkopf: nur lenken, wenn ein Ziel im Suchradius UND grob voraus ist.
	# Sonst fliegt die Rakete geradeaus weiter.
	# WICHTIG: _target erst auf Gültigkeit prüfen (Kurzschluss!), sonst wird ein
	# bereits freigegebenes Ziel an _in_seek(t: Node3D) übergeben -> Typ-Check-Crash.
	if not is_instance_valid(_target) or not _in_seek(_target):
		_target = _nearest()
	if is_instance_valid(_target):
		var dir: Vector3 = (_target.global_position - global_position).normalized()
		var cur: Vector3 = vel.normalized()
		if cur.length() > 0.01 and dir.length() > 0.01:
			# lerp+normalize statt Vector3.slerp (slerp wirft bei fast-parallel "axis must be normalized")
			var nd: Vector3 = cur.lerp(dir, clampf(turn * delta, 0.0, 1.0)).normalized()
			vel = nd * vel.length()


func _in_seek(t: Node3D) -> bool:
	if not is_instance_valid(t):
		return false
	var to: Vector3 = t.global_position - global_position
	if to.length() > seek_range:
		return false
	return to.normalized().dot(vel.normalized()) > SEEK_CONE


# Nächstes Ziel im Suchradius + Suchkegel (null = nichts -> geradeaus).
func _nearest() -> Node3D:
	var best: Node3D = null
	var bd := seek_range
	var vd := vel.normalized()
	for t in get_tree().get_nodes_in_group("target"):
		if not is_instance_valid(t):
			continue
		var to: Vector3 = t.global_position - global_position
		var d := to.length()
		if d < bd and to.normalized().dot(vd) > SEEK_CONE:
			bd = d
			best = t
	return best


func _seg_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-6:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)


func _build_visual() -> void:
	var mi := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if kind == "bullet":
		var bm := BoxMesh.new()
		# Kaliber: größeres Kaliber -> dickere & längere Leuchtspur
		bm.size = Vector3(0.12 * tracer_scale, 0.12 * tracer_scale, 0.9 * (0.7 + 0.5 * tracer_scale))
		mi.mesh = bm
		m.albedo_color = tracer_color
		m.emission_enabled = true
		m.emission = tracer_color
		m.emission_energy_multiplier = 2.2
	elif kind == "missile":
		var cm := CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = 0.12
		cm.height = 1.4
		mi.mesh = cm
		mi.rotation = Vector3(PI * 0.5, 0, 0)
		m.albedo_color = Color(0.85, 0.86, 0.9)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	else:  # bomb
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.9
		mi.mesh = sm
		m.albedo_color = Color(0.2, 0.24, 0.2)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mi.material_override = m
	add_child(mi)
	if kind == "bullet":
		_make_trail()


# Leuchtspur-Band (ImmediateMesh, additiv leuchtend, kameragerichtet, zum Schweif ausblendend).
func _make_trail() -> void:
	_trail_mi = MeshInstance3D.new()
	_trail_mi.mesh = ImmediateMesh.new()
	_trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.vertex_color_use_as_albedo = true
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD          # additiv -> glüht wie Leuchtspur
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mi.material_override = tm
	add_child(_trail_mi)


func _update_trail() -> void:
	var im: ImmediateMesh = _trail_mi.mesh
	im.clear_surfaces()
	var n := _trail_pts.size()
	if n < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos: Vector3 = cam.global_position if cam != null else global_position + Vector3.UP * 50.0
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n:
		var wp: Vector3 = _trail_pts[i]
		var dir: Vector3 = (_trail_pts[i + 1] - wp) if i < n - 1 else (wp - _trail_pts[i - 1])
		if dir.length() < 1e-4:
			dir = -basis.z
		dir = dir.normalized()
		var side: Vector3 = dir.cross(cam_pos - wp)
		if side.length() < 1e-4:
			side = dir.cross(Vector3.UP)
		side = side.normalized()
		var frac := float(i) / float(n - 1)               # 0 = Schweif (aus), 1 = Kopf (hell)
		var w := lerpf(0.015, 0.13 * tracer_scale, frac)  # Band verjüngt sich zum Schweif
		# RGB mit frac modulieren -> sauberer Fade auch bei additivem Blend
		var col := Color(tracer_color.r * frac, tracer_color.g * frac, tracer_color.b * frac, frac)
		im.surface_set_color(col)
		im.surface_add_vertex(to_local(wp + side * w))
		im.surface_set_color(col)
		im.surface_add_vertex(to_local(wp - side * w))
	im.surface_end()


func _boom() -> void:
	var par := get_parent()
	if par == null or not is_inside_tree() or not par.is_inside_tree():
		return
	var pos := global_position
	# Explosionsgröße nach Geschosstyp: Kugel klein, Rakete mittel, Bombe groß.
	var amount := 14
	var pradius := 0.15
	var vmax := 9.0
	match kind:
		"bomb":
			amount = 80; pradius = 0.5; vmax = 34.0
		"missile":
			amount = 46; pradius = 0.32; vmax = 22.0
		_:
			amount = 14; pradius = 0.15; vmax = 9.0
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, -9.0, 0)
	var mesh := SphereMesh.new()
	mesh.radius = pradius
	mesh.height = pradius * 2.0
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1.0, 0.6, 0.15)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.5, 0.12)
	mm.emission_energy_multiplier = 2.5
	mesh.material = mm
	p.mesh = mesh
	par.add_child(p)
	p.global_position = pos
	p.get_tree().create_timer(1.6).timeout.connect(p.queue_free)
	# Heller Mündungs-/Einschlag-Blitz bei Rakete & Bombe (kurzlebige Leucht-Kugel)
	if kind != "bullet":
		_flash(par, pos, 1.7 if kind == "bomb" else 1.0)


func _flash(par: Node, pos: Vector3, scl: float) -> void:
	var fm := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.9 * scl
	sm.height = 1.8 * scl
	fm.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.86, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.4)
	mat.emission_energy_multiplier = 6.0
	fm.material_override = mat
	par.add_child(fm)
	fm.global_position = pos
	par.get_tree().create_timer(0.12).timeout.connect(fm.queue_free)
