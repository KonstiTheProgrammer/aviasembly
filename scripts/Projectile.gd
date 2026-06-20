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

# Drop-and-Boost-Zielsuchrakete (kind "missile_drop"): erst Freifall, dann Turbo-Schub
# mit dicker Rauchfahne, dann Homing auf den nächsten Luftballon.
var boost_delay := 0.5        # s im Freifall, bevor der Motor zündet
var boost_accel := 210.0      # Turbo-Beschleunigung (m/s²)
var boost_speed := 165.0      # angepeilte Marschgeschwindigkeit (m/s)
var home_anywhere := false    # Ziel auch OHNE Voraus-Kegel verfolgen (Drop-Rakete kurvt voll rum)
var _age := 0.0
var _boosting := false
var _smoke: CPUParticles3D = null
const DROP_G := 9.8

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
	if kind == "missile_drop":
		_age += delta
		if not _boosting:
			vel.y -= DROP_G * delta            # Freifall-Phase (physikalischer Abwurf)
			if _age >= boost_delay:
				_ignite()                       # Motor zündet -> Turbo + Rauchfahne + Homing
		else:
			var dn := vel.normalized()
			if dn.length() > 0.01:
				vel = dn * minf(vel.length() + boost_accel * delta, boost_speed)
			_home(delta)
	elif kind == "missile" and guided:
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
	if (kind == "bomb" or kind == "missile_drop") and global_position.y <= 0.4:
		_boom()
		queue_free()


func _home(delta: float) -> void:
	# Suchkopf: nur lenken, wenn ein Ziel im Suchradius UND grob voraus ist.
	# Sonst fliegt die Rakete geradeaus weiter.
	# WICHTIG: _target erst auf Gültigkeit prüfen (Kurzschluss!), sonst wird ein
	# bereits freigegebenes Ziel an _in_seek(t: Node3D) übergeben -> Typ-Check-Crash.
	if home_anywhere:
		# Drop-Rakete: nächsten Ballon in Reichweite verfolgen, egal in welche Richtung.
		if not is_instance_valid(_target) or global_position.distance_to(_target.global_position) > seek_range:
			_target = _nearest_any()
	elif not is_instance_valid(_target) or not _in_seek(_target):
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


# Nächstes Ziel in Reichweite OHNE Kegel-Bedingung (Drop-Rakete darf voll herumkurven).
func _nearest_any() -> Node3D:
	var best: Node3D = null
	var bd := seek_range
	for t in get_tree().get_nodes_in_group("target"):
		if not is_instance_valid(t):
			continue
		var d := global_position.distance_to(t.global_position)
		if d < bd:
			bd = d
			best = t
	return best


# Motorzündung nach der Freifall-Phase: in Zielrichtung schwenken, Turbo + Rauchfahne an.
func _ignite() -> void:
	_boosting = true
	guided = true
	var tgt := _nearest_any()
	var d: Vector3
	if is_instance_valid(tgt):
		d = (tgt.global_position - global_position).normalized()
	else:
		d = Vector3(vel.x, maxf(vel.y, 3.0), vel.z)   # sonst vorwärts, leicht steigend
		if d.length() < 0.01:
			d = -basis.z
		d = d.normalized()
	vel = d * maxf(vel.length(), 50.0)
	_start_smoke()
	if _trail_mi == null:
		_make_trail()                                 # heller Schub-Streifen (Tracer-Band)
	var par := get_parent()
	if par != null and is_inside_tree():
		_flash(par, global_position, 0.8)             # Zünd-Blitz


# Dicke Rauchfahne hinter der Rakete (Partikel bleiben in der Welt stehen -> Schweif).
func _start_smoke() -> void:
	var sp := CPUParticles3D.new()
	sp.local_coords = false
	sp.amount = 46
	sp.lifetime = 1.4
	sp.emitting = true
	sp.spread = 14.0
	sp.initial_velocity_min = 0.5
	sp.initial_velocity_max = 2.5
	sp.gravity = Vector3(0, 1.2, 0)
	var smesh := SphereMesh.new()
	smesh.radius = 0.4
	smesh.height = 0.8
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.86, 0.87, 0.92, 0.55)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smesh.material = smat
	sp.mesh = smesh
	# über die Lebenszeit wachsen (Rauch quillt auf)
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 2.2))
	sp.scale_amount_curve = curve
	# über die Lebenszeit ausblenden
	var grad := Gradient.new()
	grad.set_color(0, Color(0.9, 0.91, 0.95, 0.6))
	grad.set_color(1, Color(0.7, 0.72, 0.78, 0.0))
	sp.color_ramp = grad
	add_child(sp)
	sp.position = Vector3(0, 0, 0.95)   # Austritt an der Düse (hinten)
	_smoke = sp


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
	elif kind == "missile_drop":
		# DICKE Rakete: fetter Körper + Nasenkonus + glühende Schubdüse hinten.
		var bcm := CylinderMesh.new()
		bcm.top_radius = 0.22
		bcm.bottom_radius = 0.22
		bcm.height = 1.7
		mi.mesh = bcm
		mi.rotation = Vector3(PI * 0.5, 0, 0)
		m.albedo_color = Color(0.55, 0.58, 0.63)
		m.metallic = 0.5
		m.roughness = 0.4
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		var nose := MeshInstance3D.new()
		var ncm := CylinderMesh.new()
		ncm.top_radius = 0.0
		ncm.bottom_radius = 0.22
		ncm.height = 0.55
		nose.mesh = ncm
		nose.rotation = Vector3(-PI * 0.5, 0, 0)
		nose.position = Vector3(0, 0, -1.12)   # vorne = -z
		nose.material_override = m
		add_child(nose)
		var noz := MeshInstance3D.new()
		var nzm := CylinderMesh.new()
		nzm.top_radius = 0.16
		nzm.bottom_radius = 0.27
		nzm.height = 0.3
		noz.mesh = nzm
		noz.rotation = Vector3(PI * 0.5, 0, 0)
		noz.position = Vector3(0, 0, 0.95)     # hinten = +z
		var nmat := StandardMaterial3D.new()
		nmat.albedo_color = Color(1.0, 0.5, 0.15)
		nmat.emission_enabled = true
		nmat.emission = Color(1.0, 0.45, 0.1)
		nmat.emission_energy_multiplier = 3.0
		nmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		noz.material_override = nmat
		add_child(noz)
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
		"missile_drop":
			amount = 64; pradius = 0.42; vmax = 28.0
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
