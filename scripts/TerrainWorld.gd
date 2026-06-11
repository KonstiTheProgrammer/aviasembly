## SEED-BASIERTES TERRAIN: riesige, deterministische Low-Poly-Landschaft.
## FastNoiseLite-fBm-Höhenfeld, in CHUNKS um den Spieler gestreamt. Mesh +
## Trimesh-Kollision entstehen auf einem WORKER-THREAD (ein Chunk kostet
## ~7.5 ms — auf dem Main-Thread riss das bei 120 fps jedes Mal den Frame:
## sichtbares Zucken bei jedem Nachladen). Der Main-Thread instanziert nur
## noch fertige Daten (<1 ms) und hängt sie ein.
## Flatshading mit Höhen-/Hangfarben über Vertex-Colors (Sand/Gras/Fels/
## Schnee), FLUGPLÄTZE werden ins Gelände EINGEEBNET (Höhe -> exakt 0 im
## Innenradius, weicher Übergang außen). Nahe dem Ursprung sanfte Wiesen,
## mit der Entfernung echte Berge (~110 m + Schneegipfel). MEER bei y=-6
## (Kollision: WorldBoundary-Boden in Main als Sicherheitsnetz).
## FALLEN (gelernt): Godot-Front-Faces = im Uhrzeigersinn von außen (sonst
## cullt ALLES von oben); Steilheits-Farbe über |n.y|; StandardMaterial3D
## ignorierte Vertex-Farben -> Mini-Shader ALBEDO=COLOR.
class_name TerrainWorld
extends Node3D

const CHUNK := 384.0            # Kantenlänge eines Chunks (m)
const CELLS := 48               # Zellen pro Kante (8 m Raster -> Low-Poly-Look)
const VIEW_DIST := 2400.0       # Chunks innerhalb dieses Radius werden geladen
const SEA_Y := -6.0             # Meeresspiegel (Main legt dort die Kollisionsebene hin)
const MAX_ATTACH_PER_FRAME := 1 # fertige Chunks je Frame einhängen (Physik-Insert kostet)

var seed_value := 1337
var airfields: Array = []       # [{pos: Vector3, r_flat: float, r_blend: float}]
var _noise: FastNoiseLite
var _patch: FastNoiseLite       # Sekundär-Rauschen für Gras-Flecken
var _chunks: Dictionary = {}    # Vector2i -> Node3D (eingehängt)
var _pending: Dictionary = {}   # Vector2i -> true (im Worker unterwegs)
var _mat: ShaderMaterial
var _water: MeshInstance3D
var _last_cc := Vector2i(2147483647, 0)   # zuletzt verarbeitete Spieler-Chunk-Zelle
var _last_pos := Vector3.ZERO

# --- Worker-Thread-Verkehr ---
var _thread: Thread
var _sem: Semaphore
var _mutex: Mutex
var _jobs: Array = []           # Keys für den Worker (nahe zuerst)
var _done: Array = []           # fertige {key, mesh, shape}
var _exit := false


func setup(seedv: int, afs: Array) -> void:
	seed_value = seedv
	airfields = afs
	_noise = FastNoiseLite.new()
	_noise.seed = seedv
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 5
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5
	_noise.frequency = 1.0 / 1500.0
	_patch = FastNoiseLite.new()
	_patch.seed = seedv * 7 + 3
	_patch.frequency = 1.0 / 60.0
	# Vertex-Farbe DIREKT als Albedo (StandardMaterial ignorierte die Farben trotz
	# vertex_color_use_as_albedo bei material_override + SurfaceTool-Mesh).
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	# Wasserfläche (rein optisch; Kollision = WorldBoundary bei SEA_Y in Main)
	_water = MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(VIEW_DIST * 2.4, VIEW_DIST * 2.4)
	_water.mesh = wm
	_water.position = Vector3(0, SEA_Y + 0.15, 0)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.18, 0.42, 0.62, 0.82)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.12
	wmat.metallic = 0.2
	_water.material_override = wmat
	add_child(_water)
	# Worker starten
	_sem = Semaphore.new()
	_mutex = Mutex.new()
	_thread = Thread.new()
	_thread.start(_worker_loop)


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_exit = true
		_sem.post()
		_thread.wait_to_finish()


# Geländehöhe an Weltposition (deterministisch aus dem Seed).
func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	# sanft um den Ursprung (Wiesen), echte Berge erst weiter draußen
	var amp := lerpf(5.0, 110.0, smoothstep(900.0, 4500.0, d))
	var h := _noise.get_noise_2d(x, z) * amp
	# Flugplätze einebnen: im Innenradius exakt 0, außen weich überblenden
	for af in airfields:
		var ap: Vector3 = af["pos"]
		var ad := Vector2(x - ap.x, z - ap.z).length()
		h *= smoothstep(float(af["r_flat"]), float(af["r_blend"]), ad)
	return h


func update_center(world_pos: Vector3) -> void:
	_last_pos = world_pos
	# Wasser folgt dem Spieler (riesige Platte, aber endlich)
	_water.position.x = world_pos.x
	_water.position.z = world_pos.z
	var cc := Vector2i(int(floor(world_pos.x / CHUNK)), int(floor(world_pos.z / CHUNK)))
	if cc == _last_cc:
		return   # gleiche Zelle -> Lade-Plan unverändert (kein Scan pro Frame)
	_last_cc = cc
	var r := int(ceil(VIEW_DIST / CHUNK))
	var want := {}
	var new_jobs: Array = []
	for cy in range(cc.y - r, cc.y + r + 1):
		for cx in range(cc.x - r, cc.x + r + 1):
			var key := Vector2i(cx, cy)
			if _chunk_center(key).distance_to(Vector2(world_pos.x, world_pos.z)) > VIEW_DIST + CHUNK:
				continue
			want[key] = true
			if not _chunks.has(key) and not _pending.has(key):
				_pending[key] = true
				new_jobs.append(key)
	# entfernte Chunks abbauen
	for key in _chunks.keys():
		if not want.has(key):
			_chunks[key].queue_free()
			_chunks.erase(key)
	if new_jobs.is_empty():
		return
	# nahe zuerst bauen
	var pc := Vector2(world_pos.x, world_pos.z)
	new_jobs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_center(a).distance_squared_to(pc) < _chunk_center(b).distance_squared_to(pc))
	_mutex.lock()
	_jobs.append_array(new_jobs)
	_mutex.unlock()
	for i in new_jobs.size():
		_sem.post()


func _chunk_center(key: Vector2i) -> Vector2:
	return Vector2((float(key.x) + 0.5) * CHUNK, (float(key.y) + 0.5) * CHUNK)


# Worker: rechnet Höhenfeld + Mesh + Kollisions-Shape (alles Resources, off-tree
# Thread-sicher). Der Main-Thread hängt nur noch ein.
func _worker_loop() -> void:
	while true:
		_sem.wait()
		if _exit:
			return
		_mutex.lock()
		var key_v: Variant = _jobs.pop_front() if not _jobs.is_empty() else null
		_mutex.unlock()
		if key_v == null:
			continue
		var key: Vector2i = key_v
		var data := _make_chunk_data(key)
		_mutex.lock()
		_done.append({"key": key, "mesh": data["mesh"], "shape": data["shape"]})
		_mutex.unlock()


func _process(_delta: float) -> void:
	# fertige Chunks einhängen (billig: Nodes + fertige Resources)
	for i in MAX_ATTACH_PER_FRAME:
		_mutex.lock()
		var item_v: Variant = _done.pop_front() if not _done.is_empty() else null
		_mutex.unlock()
		if item_v == null:
			return
		var item: Dictionary = item_v
		var key: Vector2i = item["key"]
		_pending.erase(key)
		# inzwischen außer Reichweite? -> verwerfen (wird bei Bedarf neu geplant)
		if _chunks.has(key) or _chunk_center(key).distance_to(Vector2(_last_pos.x, _last_pos.z)) > VIEW_DIST + CHUNK:
			continue
		_attach_chunk(key, item["mesh"], item["shape"])


# Startbereich SOFORT bauen (synchron, Main-Thread), damit das Flugzeug beim
# Spawn nicht durch noch fehlende Kollision fällt.
func build_now_around(world_pos: Vector3, radius: float) -> void:
	update_center(world_pos)
	var r := int(ceil(radius / CHUNK)) + 1
	var cc := Vector2i(int(floor(world_pos.x / CHUNK)), int(floor(world_pos.z / CHUNK)))
	for cy in range(cc.y - r, cc.y + r + 1):
		for cx in range(cc.x - r, cc.x + r + 1):
			var key := Vector2i(cx, cy)
			if _chunks.has(key):
				continue
			if _chunk_center(key).distance_to(Vector2(world_pos.x, world_pos.z)) > radius + CHUNK:
				continue
			var data := _make_chunk_data(key)
			_attach_chunk(key, data["mesh"], data["shape"])


func _attach_chunk(key: Vector2i, mesh: ArrayMesh, shape: Shape3D) -> void:
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	node.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	node.add_child(body)
	add_child(node)
	_chunks[key] = node


# Mesh + Kollision für einen Chunk bauen (läuft im Worker ODER synchron beim Spawn).
func _make_chunk_data(key: Vector2i) -> Dictionary:
	var ox := float(key.x) * CHUNK
	var oz := float(key.y) * CHUNK
	var step := CHUNK / float(CELLS)
	var hs := PackedFloat32Array()
	hs.resize((CELLS + 1) * (CELLS + 1))
	for j in CELLS + 1:
		for i in CELLS + 1:
			hs[j * (CELLS + 1) + i] = height_at(ox + float(i) * step, oz + float(j) * step)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # FLAT shading (Low-Poly-Facetten)
	for j in CELLS:
		for i in CELLS:
			var x0 := ox + float(i) * step
			var z0 := oz + float(j) * step
			var h00 := hs[j * (CELLS + 1) + i]
			var h10 := hs[j * (CELLS + 1) + i + 1]
			var h01 := hs[(j + 1) * (CELLS + 1) + i]
			var h11 := hs[(j + 1) * (CELLS + 1) + i + 1]
			var v00 := Vector3(x0, h00, z0)
			var v10 := Vector3(x0 + step, h10, z0)
			var v01 := Vector3(x0, h01, z0 + step)
			var v11 := Vector3(x0 + step, h11, z0 + step)
			# Godot-Front = im Uhrzeigersinn von außen: Wicklung so, dass die
			# Flächen nach OBEN zeigen (sonst cullt alles bei Sicht von oben)
			_tri(st, v00, v10, v11)
			_tri(st, v00, v11, v01)
	st.generate_normals()
	var mesh := st.commit()
	return {"mesh": mesh, "shape": mesh.create_trimesh_shape()}


# Ein Dreieck mit Flächenfarbe (aus Höhe + Steilheit am Schwerpunkt) einfügen.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	var cen := (a + b + c) / 3.0
	# |n.y|: die geometrische Normale zeigt je nach Wicklung nach unten —
	# für die Steilheits-Farbe zählt nur der Winkel zur Senkrechten.
	st.set_color(_face_color(cen, absf(n.y)))
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _face_color(cen: Vector3, ny: float) -> Color:
	if cen.y < SEA_Y + 1.6:
		return Color(0.78, 0.72, 0.54)        # Sandstrand/Ufer
	if cen.y > 80.0:
		return Color(0.93, 0.94, 0.97)        # Schnee NUR auf Gipfeln
	if cen.y > 52.0 or ny < 0.74:
		return Color(0.47, 0.46, 0.48)        # Fels: steil ODER Hochlage
	# Gras in zwei Tönen (Flecken-Rauschen) — Low-Poly-Wiese
	var t := _patch.get_noise_2d(cen.x, cen.z)
	var g1 := Color(0.38, 0.56, 0.30)
	var g2 := Color(0.31, 0.49, 0.27)
	return g1.lerp(g2, clampf(t * 0.5 + 0.5, 0.0, 1.0))
