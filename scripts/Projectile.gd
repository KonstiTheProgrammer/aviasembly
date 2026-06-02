## Projectile.gd — abgefeuertes Geschoss: Kugel (gerade), Zielsuchrakete (homing)
## oder Bombe (Freifall). Treffererkennung gegen Gruppe "target" per Segment-Abstand.
class_name Projectile
extends Node3D

var kind := "bullet"          # bullet | missile | bomb
var vel := Vector3.ZERO
var life := 2.5
var damage := 1.0
var turn := 3.0               # Lenkrate der Rakete (rad/s grob)
var guided := false           # Suchkopf aktiv? (sonst rein geradeaus)
var seek_range := 70.0        # Reichweite, ab der ein Ziel angeflogen wird
const SEEK_CONE := 0.2        # nur Ziele grob voraus erfassen (dot vel·Richtung)
var _target: Node3D = null


func _ready() -> void:
	_build_visual()


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if kind == "bomb":
		vel.y -= 24.0 * delta
	elif kind == "missile" and guided:
		_home(delta)
	var a := global_position
	global_position += vel * delta
	var b := global_position
	if kind != "bullet" and vel.length() > 1.0:
		look_at(b + vel, Vector3.UP)
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
			vel = cur.slerp(dir, clampf(turn * delta, 0.0, 1.0)) * vel.length()


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
		bm.size = Vector3(0.12, 0.12, 0.9)
		mi.mesh = bm
		m.albedo_color = Color(1.0, 0.85, 0.2)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.8, 0.2)
		m.emission_energy_multiplier = 2.0
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


func _boom() -> void:
	var par := get_parent()
	if par == null or not is_inside_tree() or not par.is_inside_tree():
		return
	var pos := global_position
	var big := kind == "bomb"
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 60 if big else 16
	p.lifetime = 0.8
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 30.0 if big else 10.0
	p.gravity = Vector3(0, -9.0, 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.4 if big else 0.18
	mesh.height = 0.8 if big else 0.36
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1.0, 0.6, 0.15)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.5, 0.12)
	mm.emission_energy_multiplier = 2.5
	mesh.material = mm
	p.mesh = mesh
	par.add_child(p)
	p.global_position = pos
	var tmr := p.get_tree().create_timer(1.5)
	tmr.timeout.connect(p.queue_free)
