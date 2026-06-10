## SEED-BASIERTES TERRAIN: riesige, deterministische Low-Poly-Landschaft.
## FastNoiseLite-fBm-Höhenfeld, in CHUNKS um den Spieler gestreamt (Queue, max. 2
## Builds/Frame gegen Ruckler). Flatshading mit Höhen-/Hangfarben über Vertex-
## Colors (Sand/Gras/Fels/Schnee), Trimesh-Kollision je Chunk (Layer 1 = Boden).
## FLUGPLÄTZE werden ins Gelände EINGEEBNET (Höhe -> exakt 0 im Innenradius,
## weicher Übergang außen) — die Bahnen liegen also nahtlos im Terrain.
## Nahe dem Ursprung bleibt die Amplitude klein (sanfte Wiesen um HEIMAT),
## mit der Entfernung wachsen echte Berge (bis ~110 m + Schneegrenze).
## Das MEER liegt bei y=-6 (Senken füllen sich); die Kollision dort liefert
## der WorldBoundary-Boden in Main (Sicherheitsnetz unter allem).
class_name TerrainWorld
extends Node3D

const CHUNK := 384.0            # Kantenlänge eines Chunks (m)
const CELLS := 48               # Zellen pro Kante (8 m Raster -> Low-Poly-Look)
const VIEW_DIST := 2400.0       # Chunks innerhalb dieses Radius werden geladen
const SEA_Y := -6.0             # Meeresspiegel (Main legt dort die Kollisionsebene hin)
const MAX_BUILDS_PER_FRAME := 2

var seed_value := 1337
var airfields: Array = []       # [{pos: Vector3, r_flat: float, r_blend: float}]
var _noise: FastNoiseLite
var _patch: FastNoiseLite       # Sekundär-Rauschen für Gras-Flecken
var _chunks: Dictionary = {}    # Vector2i -> Node3D
var _queue: Array = []          # zu bauende Chunk-Koordinaten
var _mat: ShaderMaterial
var _water: MeshInstance3D


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
	add_child(_water)


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
	var cc := Vector2i(int(floor(world_pos.x / CHUNK)), int(floor(world_pos.z / CHUNK)))
	var r := int(ceil(VIEW_DIST / CHUNK))
	var want := {}
	for cy in range(cc.y - r, cc.y + r + 1):
		for cx in range(cc.x - r, cc.x + r + 1):
			var key := Vector2i(cx, cy)
			var center := Vector2((float(cx) + 0.5) * CHUNK, (float(cy) + 0.5) * CHUNK)
			if center.distance_to(Vector2(world_pos.x, world_pos.z)) > VIEW_DIST + CHUNK:
				continue
			want[key] = true
			if not _chunks.has(key) and not _queue.has(key):
				_queue.append(key)
	# entfernte Chunks abbauen
	for key in _chunks.keys():
		if not want.has(key):
			_chunks[key].queue_free()
			_chunks.erase(key)
	# Wasser folgt dem Spieler (riesige Platte, aber endlich)
	_water.position.x = world_pos.x
	_water.position.z = world_pos.z
	# Queue: nahe Chunks zuerst
	if not _queue.is_empty():
		var pc := Vector2(world_pos.x, world_pos.z)
		_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var ca := Vector2((float(a.x) + 0.5) * CHUNK, (float(a.y) + 0.5) * CHUNK)
			var cb := Vector2((float(b.x) + 0.5) * CHUNK, (float(b.y) + 0.5) * CHUNK)
			return ca.distance_squared_to(pc) < cb.distance_squared_to(pc))


func _process(_delta: float) -> void:
	for i in MAX_BUILDS_PER_FRAME:
		if _queue.is_empty():
			return
		_build_chunk(_queue.pop_front())


# Startbereich SOFORT bauen (synchron), damit das Flugzeug beim Spawn nicht
# durch noch fehlende Kollision fällt.
func build_now_around(world_pos: Vector3, radius: float) -> void:
	update_center(world_pos)
	var keep: Array = []
	for key in _queue:
		var center := Vector2((float(key.x) + 0.5) * CHUNK, (float(key.y) + 0.5) * CHUNK)
		if center.distance_to(Vector2(world_pos.x, world_pos.z)) <= radius + CHUNK:
			_build_chunk(key)
		else:
			keep.append(key)
	_queue = keep


func _build_chunk(key: Vector2i) -> void:
	if _chunks.has(key):
		return
	var ox := float(key.x) * CHUNK
	var oz := float(key.y) * CHUNK
	var step := CHUNK / float(CELLS)
	# Höhenfeld einmal sampeln (CELLS+1)²
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
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	node.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	node.add_child(body)
	add_child(node)
	_chunks[key] = node


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
