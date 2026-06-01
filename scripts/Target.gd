## Target.gd — abschießbares Ziel: Luftballon oder Luftschiff.
## Schwebt/driftet, hat HP, gibt beim Abschuss Geld (Signal) + Knall-Effekt.
class_name Target
extends Node3D

signal killed(reward: int, pos: Vector3)

var hp := 1.0
var hit_radius := 2.6
var reward := 120
var kind := "balloon"
var _base := Vector3.ZERO
var _phase := 0.0
var _drift := Vector3.ZERO
var _dead := false


func setup(p_kind: String, pos: Vector3, col: Color) -> void:
	kind = p_kind
	position = pos
	_base = pos
	_phase = randf() * TAU
	var ang := randf() * TAU
	if kind == "airship":
		hp = 4.0
		hit_radius = 6.5
		reward = 600
		_drift = Vector3(cos(ang), 0, sin(ang)) * randf_range(5.0, 9.0)
		_build_airship(col)
	else:
		hp = 1.0
		hit_radius = 2.8
		reward = 120
		_drift = Vector3(cos(ang), 0, sin(ang)) * randf_range(1.5, 4.0)
		_build_balloon(col)


func _ready() -> void:
	add_to_group("target")


func _process(delta: float) -> void:
	_phase += delta
	_base += _drift * delta
	if absf(_base.x) > 2000.0 or absf(_base.z) > 2000.0:
		_drift = -_drift
	var amp := 1.6 if kind == "balloon" else 0.7
	var freq := 1.1 if kind == "balloon" else 0.45
	position = _base + Vector3(0, sin(_phase * freq) * amp, 0)
	if kind == "airship" and _drift.length() > 0.1:
		look_at(position + _drift, Vector3.UP)
	else:
		rotate_y(delta * 0.4)


func hit(dmg: float) -> void:
	if _dead:
		return
	hp -= dmg
	if hp <= 0.0:
		_dead = true
		_die()


func _die() -> void:
	killed.emit(reward, global_position)
	_boom()
	queue_free()


# --- Optik ----------------------------------------------------------------
func _mat(c: Color, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.0
	m.roughness = 0.5
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m


func _build_balloon(col: Color) -> void:
	var s := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.3
	sm.height = 3.0          # leicht eiförmig
	s.mesh = sm
	s.material_override = _mat(col, 0.25)
	add_child(s)
	# Knoten unten + Schnur
	var knot := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.25
	km.height = 0.5
	knot.mesh = km
	knot.position = Vector3(0, -1.55, 0)
	knot.material_override = _mat(col.darkened(0.3))
	add_child(knot)
	var cord := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.03
	cm.height = 2.0
	cord.mesh = cm
	cord.position = Vector3(0, -2.7, 0)
	cord.material_override = _mat(Color(0.15, 0.15, 0.15))
	add_child(cord)


func _build_airship(col: Color) -> void:
	# Zigarrenkörper (lang entlang -Z = Fahrtrichtung)
	var body := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	body.mesh = sm
	body.scale = Vector3(3.0, 3.0, 8.0)
	body.material_override = _mat(col, 0.1)
	add_child(body)
	# Gondel unten
	var gon := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 1.0, 3.0)
	gon.mesh = bm
	gon.position = Vector3(0, -3.2, 1.0)
	gon.material_override = _mat(Color(0.25, 0.26, 0.3), 0.0)
	add_child(gon)
	# Heckflossen
	var fmat := _mat(col.darkened(0.2))
	for i in 4:
		var fin := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(0.25, 3.2, 2.0)
		fin.mesh = fb
		fin.material_override = fmat
		var h := Node3D.new()
		h.rotation = Vector3(0, 0, deg_to_rad(45.0 + 90.0 * i))
		h.add_child(fin)
		fin.position = Vector3(0, 2.6, 7.0)
		add_child(h)


func _boom() -> void:
	var par := get_parent()
	if par == null:
		return
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 40 if kind == "balloon" else 90
	p.lifetime = 1.0
	p.explosiveness = 0.95
	p.global_position = global_position
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 16.0 if kind == "balloon" else 26.0
	p.gravity = Vector3(0, -9.0, 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1.0, 0.6, 0.15)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.55, 0.12)
	mm.emission_energy_multiplier = 2.0
	mesh.material = mm
	p.mesh = mesh
	par.add_child(p)
	p.global_position = global_position
	var tmr := p.get_tree().create_timer(2.0)
	tmr.timeout.connect(p.queue_free)
