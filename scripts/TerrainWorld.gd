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
var lakes: Array = []           # [{pos: Vector3, r: float, surf: float}] Inland-Seen
var _noise: FastNoiseLite
var _patch: FastNoiseLite       # Sekundär-Rauschen für Gras-Flecken
var _forest: FastNoiseLite      # grobes Rauschen: wo stehen WÄLDER (Cluster)
var _ridge: FastNoiseLite       # Ridged-Noise -> scharfe Bergketten
var _relief: FastNoiseLite      # sehr grob: wie GEBIRGIG ist eine Region (Ebene<->Alpen)
var _biome: FastNoiseLite       # sehr grob: welches BIOM (Wald/Wüste/Hochland/Heide)
var _mesh_conifer: ArrayMesh    # Low-Poly-Tanne (einmal gebaut, via MultiMesh instanziert)
var _mesh_leaf: ArrayMesh       # Low-Poly-Laubbaum
var _mesh_rock: ArrayMesh       # Low-Poly-Felsblock
var _mesh_palm: ArrayMesh       # Low-Poly-Palme (Wüste)

# Biom-Konstanten (aus _biome-Rauschen, -1..1)
enum Biome { WALD, WUESTE, HOCHLAND, HEIDE }
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


func setup(seedv: int, afs: Array, lks: Array = []) -> void:
	seed_value = seedv
	airfields = afs
	lakes = lks
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
	_forest = FastNoiseLite.new()
	_forest.seed = seedv * 13 + 5
	_forest.frequency = 1.0 / 260.0
	# Ridged-Noise: scharfe Bergrücken (kein Domain-Warp -> günstig, height_at läuft
	# pro Vertex; Warp war zu teuer für den synchronen Spawn-Build).
	_ridge = FastNoiseLite.new()
	_ridge.seed = seedv * 17 + 11
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 4
	_ridge.fractal_gain = 0.55
	_ridge.frequency = 1.0 / 1700.0
	# Relief: sehr grob — wie gebirgig eine Region ist (Ebene 0 .. Alpen 1)
	_relief = FastNoiseLite.new()
	_relief.seed = seedv * 23 + 7
	_relief.frequency = 1.0 / 3600.0
	# Biom: sehr grob — Regionen-Einteilung
	_biome = FastNoiseLite.new()
	_biome.seed = seedv * 31 + 13
	_biome.frequency = 1.0 / 3200.0
	_mesh_conifer = _build_conifer_mesh()
	_mesh_leaf = _build_leaf_mesh()
	_mesh_rock = _build_rock_mesh()
	_mesh_palm = _build_palm_mesh()
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
	# Tropisches Tiefen-Wasser (Shader): türkise Untiefen -> Lagune -> tiefes Blau
	# über den Tiefenpuffer, Schaumkante am Ufer, Fresnel-Spiegelung.
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/water.gdshader")
	_water.material_override = wmat
	add_child(_water)
	# Inland-Seen: je eine ruhige, leicht spiegelnde Wasserfläche an der Oberfläche.
	for lk in lakes:
		var lp: Vector3 = lk["pos"]
		var lr: float = lk["r"]
		var lake := MeshInstance3D.new()
		var lm := PlaneMesh.new()
		lm.size = Vector2(lr * 2.1, lr * 2.1)
		lake.mesh = lm
		lake.position = Vector3(lp.x, float(lk["surf"]), lp.z)
		var lkmat := StandardMaterial3D.new()
		lkmat.albedo_color = Color(0.30, 0.46, 0.55, 0.86)
		lkmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lkmat.roughness = 0.10
		lkmat.metallic = 0.3
		lake.material_override = lkmat
		add_child(lake)
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
## Wie gebirgig die Region ist (0 = Ebene, 1 = Alpen). Sehr grob.
func relief_at(x: float, z: float) -> float:
	return smoothstep(-0.12, 0.42, _relief.get_noise_2d(x, z))

## Biom an einer Welt-Position (Tiefland-Charakter; Fels/Schnee kommt aus Höhe/Hang).
func biome_at(x: float, z: float) -> int:
	var b := _biome.get_noise_2d(x, z)
	if b < -0.32:
		return Biome.WUESTE
	if b > 0.40:
		return Biome.HEIDE
	return Biome.WALD

func height_at(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	# Distanz-Ramp: Spawn-Umfeld ruhig, Gebirge baut sich erst weiter draußen auf
	var dist_k := smoothstep(700.0, 3000.0, d)
	var relief := relief_at(x, z) * dist_k
	# 1) sanfte Grundwelligkeit überall
	var rolling := _noise.get_noise_2d(x, z) * lerpf(6.0, 24.0, relief)
	# 2) scharfe Bergketten NUR wo Relief hoch (ridged + domain-warp)
	var rdg := clampf(_ridge.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var peaks := pow(rdg, 1.6) * lerpf(0.0, 175.0, relief) * relief
	var h := rolling + peaks
	# Flugplätze einebnen: im Innenradius exakt 0, außen weich überblenden
	for af in airfields:
		var ap: Vector3 = af["pos"]
		var ad := Vector2(x - ap.x, z - ap.z).length()
		h *= smoothstep(float(af["r_flat"]), float(af["r_blend"]), ad)
	# Inland-Seen: Becken in den (bereits flachen) Grund graben, Boden bleibt über
	# dem Meeresspiegel (-6), damit das globale Meer nicht durchscheint.
	for lk in lakes:
		var lp: Vector3 = lk["pos"]
		var lr: float = lk["r"]
		var ld := Vector2(x - lp.x, z - lp.z).length()
		var bowl := 1.0 - smoothstep(lr * 0.55, lr, ld)   # 1 Mitte .. 0 Rand
		if bowl > 0.0:
			var floor_y: float = float(lk["surf"]) - 4.0
			h = lerpf(h, floor_y, bowl)
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
		_attach_chunk(key, item["mesh"], item["shape"], item.get("conifers", []), item.get("leafs", []), item.get("rocks", []), item.get("palms", []))


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
			_attach_chunk(key, data["mesh"], data["shape"], data["conifers"], data["leafs"], data["rocks"], data["palms"])


func _attach_chunk(key: Vector2i, mesh: ArrayMesh, shape: Shape3D,
		conifers: Array = [], leafs: Array = [], rocks: Array = [], palms: Array = []) -> void:
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
	# Flora: je Variante EIN MultiMesh (hunderte Bäume = 1 Draw-Call)
	_attach_multi(node, _mesh_conifer, conifers)
	_attach_multi(node, _mesh_leaf, leafs)
	_attach_multi(node, _mesh_rock, rocks)
	_attach_multi(node, _mesh_palm, palms)
	add_child(node)
	_chunks[key] = node


func _attach_multi(parent: Node3D, mesh: ArrayMesh, xfs: Array) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat
	parent.add_child(mmi)


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
	# --- FLORA: deterministisch aus Seed+Chunk — Bäume in Wald-Clustern, Felsen
	# verstreut. Nur Transforms berechnen (Worker); MultiMesh baut der Main-Thread.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, seed_value))
	var conifers: Array = []
	var leafs: Array = []
	var palms: Array = []
	var rocks: Array = []
	for a in 130:
		var px := ox + rng.randf() * CHUNK
		var pz := oz + rng.randf() * CHUNK
		var h := height_at(px, pz)
		if h < 0.8 or h > 64.0:
			continue   # nichts am Strand/Wasser/Flugplatz oder über der Baumgrenze
		# Steilheit aus zwei Nachbarproben (Bäume nur auf gangbarem Hang)
		var hx := height_at(px + 6.0, pz)
		var hz := height_at(px, pz + 6.0)
		if absf(hx - h) > 2.6 or absf(hz - h) > 2.6:
			continue
		var biome := biome_at(px, pz)
		if biome == Biome.WUESTE:
			# Wüste: spärliche Palmen-Oasen in tieferen Lagen
			if h > 28.0 or rng.randf() > 0.07:
				continue
			var ps := rng.randf_range(1.0, 1.7)
			palms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(
				Vector3(ps, ps * rng.randf_range(0.9, 1.2), ps)), Vector3(px, h - 0.1, pz)))
			continue
		var f := _forest.get_noise_2d(px, pz)
		if f < 0.05:
			continue   # kein Wald-Cluster hier
		var dens := clampf((f - 0.05) * 3.2, 0.0, 0.95)
		if biome == Biome.HEIDE:
			dens *= 0.35   # offene Heide -> nur vereinzelte Bäume
		if rng.randf() > dens:
			continue
		var sc := rng.randf_range(1.1, 2.0)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.25), sc)), Vector3(px, h - 0.15, pz))
		if h > 30.0 or rng.randf() < 0.68:
			conifers.append(xf)
		else:
			leafs.append(xf)
	for a in 14:
		var px := ox + rng.randf() * CHUNK
		var pz := oz + rng.randf() * CHUNK
		var h := height_at(px, pz)
		if h < SEA_Y + 1.0 or absf(h) < 0.4:
			continue   # nicht im Meer, nicht auf der Flugplatz-Ebene
		var hx := height_at(px + 6.0, pz)
		if rng.randf() > (0.18 + clampf(absf(hx - h) * 0.25, 0.0, 0.5) + (0.35 if h > 45.0 else 0.0)):
			continue   # Felsen bevorzugt an Hängen + in Hochlagen
		var rsc := Vector3(rng.randf_range(0.7, 2.4), rng.randf_range(0.5, 1.8), rng.randf_range(0.7, 2.4))
		rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(rsc), Vector3(px, h - 0.3, pz)))
	return {"mesh": mesh, "shape": mesh.create_trimesh_shape(),
		"conifers": conifers, "leafs": leafs, "palms": palms, "rocks": rocks}


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
	# GEDÄMPFTE, erdig-pastellige Low-Poly-Palette (Aviassembly-Look): Sage-Grün,
	# warmer Sand, staubiges Rosé/Lavendel, warmer Fels — nichts grell.
	if cen.y < SEA_Y + 1.6:
		return Color(0.88, 0.79, 0.60)        # warmer, heller Sandstrand/Ufer
	# Schnee + Fels kommen aus HÖHE/HANG (in jedem Biom): nur die HOHEN Gipfel weiß.
	if cen.y > 124.0:
		return Color(0.95, 0.95, 0.97)        # Schnee nur auf den höchsten Gipfeln
	if cen.y > 100.0 and ny > 0.55:
		return Color(0.70, 0.68, 0.68).lerp(Color(0.95, 0.95, 0.97),
			clampf((cen.y - 100.0) / 24.0, 0.0, 1.0))   # Schnee-Übergang auf flachen Kuppen
	if cen.y > 56.0 or ny < 0.70:
		return Color(0.50, 0.47, 0.46)        # warm-grauer Fels: steil ODER Hochlage
	var t := _patch.get_noise_2d(cen.x, cen.z)
	match biome_at(cen.x, cen.z):
		Biome.WUESTE:
			# Wüste: warme Sand-/Dünentöne, Erd-/Felsbänder dazwischen
			if t < -0.35:
				return Color(0.80, 0.66, 0.46) # feuchter/schattiger Sand
			if t > 0.45:
				return Color(0.72, 0.60, 0.45) # Geröll-/Erdfleck
			return Color(0.91, 0.82, 0.58).lerp(Color(0.86, 0.76, 0.52),
				clampf(t * 0.6 + 0.5, 0.0, 1.0))
		Biome.HEIDE:
			# Heide/Herbst: staubiges Rosé/Ocker
			if t < -0.40:
				return Color(0.74, 0.62, 0.60) # Rosé-Fleck
			if t > 0.45:
				return Color(0.80, 0.72, 0.50) # Ocker-Gras
			return Color(0.74, 0.68, 0.50).lerp(Color(0.66, 0.58, 0.50),
				clampf(t * 0.6 + 0.5, 0.0, 1.0))
		_:
			# Wald/Wiese: gedämpftes Sage-Grün + Rosé-/Sand-Flecken
			if t < -0.40:
				return Color(0.72, 0.62, 0.62) # staubige Rosé-Flecken
			if t > 0.42:
				return Color(0.83, 0.75, 0.57) # warme Lichtungs-/Sandflecken
			var g1 := Color(0.60, 0.69, 0.47)  # helles Sage-Grün
			var g2 := Color(0.51, 0.60, 0.43)  # tieferes Sage
			return g1.lerp(g2, clampf(t * 0.6 + 0.5, 0.0, 1.0))


# ---------------------------------------------------------------------------
# Low-Poly-Flora-Meshes (einmal gebaut, via MultiMesh überall instanziert).
# Gleiche Technik wie das Terrain: flache Facetten + Vertex-Farben (_mat).
# ---------------------------------------------------------------------------
func _cone_into(st: SurfaceTool, base_y: float, top_y: float, r: float, col: Color, segs: int, dark: float) -> void:
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := Vector3(cos(a0) * r, base_y, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, base_y, sin(a1) * r)
		var tip := Vector3(0, top_y, 0)
		# leichte Ton-Variation pro Facette -> lebendiger Low-Poly-Look
		var c := col.darkened(dark * (0.5 + 0.5 * sin(a0 * 3.0)))
		st.set_color(c)
		st.add_vertex(tip)
		st.add_vertex(p1)
		st.add_vertex(p0)


func _trunk_into(st: SurfaceTool, h: float, r: float) -> void:
	var col := Color(0.42, 0.30, 0.20)
	for i in 5:
		var a0 := TAU * float(i) / 5.0
		var a1 := TAU * float(i + 1) / 5.0
		var b0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var b1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var t0 := b0 + Vector3(0, h, 0)
		var t1 := b1 + Vector3(0, h, 0)
		st.set_color(col.darkened(0.15 * sin(a0 * 2.0)))
		st.add_vertex(t0)
		st.add_vertex(b1)
		st.add_vertex(b0)
		st.set_color(col)
		st.add_vertex(t0)
		st.add_vertex(t1)
		st.add_vertex(b1)


func _build_conifer_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_trunk_into(st, 2.2, 0.45)
	var green := Color(0.16, 0.40, 0.22)
	_cone_into(st, 1.8, 5.4, 2.6, green, 7, 0.18)
	_cone_into(st, 4.2, 7.6, 1.9, green.lightened(0.06), 7, 0.18)
	_cone_into(st, 6.4, 9.6, 1.2, green.lightened(0.12), 7, 0.18)
	st.generate_normals()
	return st.commit()


func _build_leaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_trunk_into(st, 3.0, 0.5)
	# Krone = Doppel-Kegel (oben spitz, unten gestülpt) -> kantige Laub-"Knolle"
	var green := Color(0.33, 0.55, 0.24)
	_cone_into(st, 4.6, 8.8, 3.1, green, 6, 0.22)
	var st2 := st   # untere Halbknolle: Kegel kopfüber
	for i in 6:
		var a0 := TAU * float(i) / 6.0
		var a1 := TAU * float(i + 1) / 6.0
		var p0 := Vector3(cos(a0) * 3.1, 4.6, sin(a0) * 3.1)
		var p1 := Vector3(cos(a1) * 3.1, 4.6, sin(a1) * 3.1)
		var tip := Vector3(0, 2.6, 0)
		st2.set_color(green.darkened(0.28 + 0.1 * sin(a0 * 2.0)))
		st2.add_vertex(tip)
		st2.add_vertex(p0)
		st2.add_vertex(p1)
	st.generate_normals()
	return st.commit()


func _build_rock_mesh() -> ArrayMesh:
	# kantiger Brocken: unregelmäßiges Doppel-Kegel-Polyeder
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var gray := Color(0.52, 0.51, 0.53)
	var ring: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i in 6:
		var a := TAU * float(i) / 6.0
		ring.append(Vector3(cos(a) * rng.randf_range(0.7, 1.15), rng.randf_range(0.25, 0.55), sin(a) * rng.randf_range(0.7, 1.15)))
	var top := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(1.0, 1.4), rng.randf_range(-0.2, 0.2))
	for i in 6:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % 6]
		st.set_color(gray.darkened(0.12 * sin(float(i) * 1.7)))
		st.add_vertex(top)
		st.add_vertex(p1)
		st.add_vertex(p0)
		# Sockel auf den Boden ziehen
		var b0 := Vector3(p0.x * 1.15, -0.4, p0.z * 1.15)
		var b1 := Vector3(p1.x * 1.15, -0.4, p1.z * 1.15)
		st.set_color(gray.darkened(0.2))
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(b1)
		st.add_vertex(p0)
		st.add_vertex(b1)
		st.add_vertex(b0)
	st.generate_normals()
	return st.commit()


func _dtri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	# doppelseitiges Dreieck (Wedel sind von beiden Seiten sichtbar)
	st.set_color(col)
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)


func _build_palm_mesh() -> ArrayMesh:
	# Wüsten-Palme: leicht geneigter, segmentierter Stamm + hängende Wedelkrone.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var trunk := Color(0.56, 0.44, 0.29)
	var H := 5.0
	var lean := Vector3(0.7, 0.0, 0.2)        # leichte Krümmung zur Seite
	var segs := 5
	var sides := 5
	var prev_c := Vector3.ZERO
	var prev_r := 0.30
	for s in range(1, segs + 1):
		var tt := float(s) / float(segs)
		var c := lean * (tt * tt) + Vector3(0, H * tt, 0)
		var r := lerpf(0.30, 0.15, tt)
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var b0 := prev_c + Vector3(cos(a0) * prev_r, 0, sin(a0) * prev_r)
			var b1 := prev_c + Vector3(cos(a1) * prev_r, 0, sin(a1) * prev_r)
			var t0 := c + Vector3(cos(a0) * r, 0, sin(a0) * r)
			var t1 := c + Vector3(cos(a1) * r, 0, sin(a1) * r)
			st.set_color(trunk.darkened(0.1 * sin(a0 * 2.0 + float(s))))
			st.add_vertex(t0); st.add_vertex(b1); st.add_vertex(b0)
			st.add_vertex(t0); st.add_vertex(t1); st.add_vertex(b1)
		prev_c = c; prev_r = r
	# Wedelkrone: nach außen-unten hängende Blätter (doppelseitige Rauten)
	var top: Vector3 = lean + Vector3(0, H, 0)
	var frond := Color(0.42, 0.54, 0.25)
	var nf := 8
	for i in nf:
		var a := TAU * float(i) / float(nf) + 0.4
		var dir := Vector3(cos(a), 0, sin(a))
		var midp: Vector3 = top + dir * 1.8 + Vector3(0, 0.5, 0)
		var tip: Vector3 = top + dir * 3.6 + Vector3(0, -1.9, 0)
		var side := Vector3(-dir.z, 0, dir.x) * 0.5
		var col := frond.darkened(0.14 * sin(a * 2.0))
		_dtri(st, top, midp + side, midp - side, col)
		_dtri(st, midp + side, tip, midp - side, col)
	st.generate_normals()
	return st.commit()
