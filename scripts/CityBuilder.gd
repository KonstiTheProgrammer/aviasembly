## CityBuilder — setzt die 42 Blender-Gebaeude aus models/world_buildings.glb in die Welt.
##
## WARUM EIGENES SKRIPT (nicht in Landmarks.gd): Landmarks baut seine Bauwerke PROZEDURAL
## aus Boxen; hier kommen fertige Blender-Meshes rein. Getrennt zu halten heisst auch:
## beide Quellen koennen unabhaengig weiterentwickelt werden.
##
## PERFORMANCE: pro Gebaeudetyp und Viertel EIN MultiMeshInstance3D -> ein Draw-Call je Typ,
## egal wie oft er vorkommt (gleiches Prinzip wie die Baeume in TerrainWorld). Die Meshes
## selbst sind Ein-Mesh-Multi-Material-Modelle mit ~94 Tris im Schnitt.
## Wie die Landmarks-Bauten haben sie KEINE Kollision (man fliegt hindurch) — bewusst
## gleich gehalten und deutlich billiger.
##
## ACHSEN: Blender Z-up -> glTF +Y up. Die Haeuser schauen in Blender nach -Y, im Spiel
## also nach +Z. `yaw` dreht um die Hochachse (0 = Front nach Sueden/+Z).
class_name CityBuilder
extends RefCounted

const LIB := "res://models/world_buildings.glb"
const LIB_HD := "res://models/world_buildings_hd.glb"
## Ab dieser Entfernung schaltet ein Viertel von der Nah- auf die Fernstufe.
const LOD_DIST := 900.0
# Sichtlimit der Fernstufe: knapp INNERHALB des Terrainrands. Vorher hatte die Fernstufe
# gar kein Limit — die Haeuser wurden bis zur Kamera-Fernebene (9 km) gezeichnet, das
# Terrain aber nur bis VIEW_DIST. Genau daher standen Gebaeude sichtbar im Leeren.
const SICHT_DIST := TerrainWorld.VIEW_DIST - 250.0
const SICHT_FADE := 300.0

static var _meshes: Dictionary = {}     # "Haus_Kirche" -> ArrayMesh (Fernstufe)
static var _meshes_hd: Dictionary = {}  # dieselbe Form mit Nahdetails
static var _loaded := false


static func _sammeln(pfad: String, ziel: Dictionary) -> void:
	var ps: PackedScene = load(pfad)
	if ps == null:
		push_warning("CityBuilder: %s fehlt (importiert?)" % pfad)
		return
	var root: Node = ps.instantiate()
	for c in root.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# Die HD-Knoten heissen "<Typ>_HD" (Blender laesst zwei Objekte nicht gleich heissen)
		var nm := String(c.name)
		if nm.ends_with("_HD"):
			nm = nm.substr(0, nm.length() - 3)
		ziel[nm] = mi.mesh
	root.free()


static func _load_lib() -> void:
	if _loaded:
		return
	_loaded = true
	_sammeln(LIB, _meshes)
	_sammeln(LIB_HD, _meshes_hd)


static func has_lib() -> bool:
	_load_lib()
	return not _meshes.is_empty()


## plan = [{"typ": String, "pos": Vector2 (relativ zum Zentrum), "yaw": float, "scale": float}]
## Bauten ohne bekannten Typ werden uebersprungen (statt den ganzen Aufbau zu killen).
## `dreh` dreht die GANZE Planung (Positionen und Ausrichtungen) — noetig an Flugplaetzen,
## damit die Hangars parallel zur Bahn stehen statt quer darauf.
static func build(parent: Node3D, terrain, center: Vector3, plan: Array,
		gruppe := "Viertel", dreh := 0.0) -> Node3D:
	_load_lib()
	var node := Node3D.new()
	node.name = gruppe
	node.position = Vector3(center.x, 0.0, center.z)   # Instanzen bleiben LOKAL -> enge AABB
	parent.add_child(node)
	# nach Typ buendeln -> je Typ ein MultiMesh
	var nach_typ: Dictionary = {}
	for e in plan:
		var t := String(e.get("typ", ""))
		if not _meshes.has(t):
			continue
		if not nach_typ.has(t):
			nach_typ[t] = []
		(nach_typ[t] as Array).append(e)
	for t in nach_typ.keys():
		var liste: Array = nach_typ[t]
		# Transforms EINMAL rechnen und an beide Detailstufen geben (identische Silhouette
		# -> beim Umschalten springt nichts).
		var xf: Array = []
		xf.resize(liste.size())
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[t]
		mm.instance_count = liste.size()
		for i in liste.size():
			var e: Dictionary = liste[i]
			var off0: Vector2 = e.get("pos", Vector2.ZERO)
			var r3: Vector3 = Basis(Vector3.UP, dreh) * Vector3(off0.x, 0.0, off0.y)
			var off := Vector2(r3.x, r3.z)
			# LOKALE Position im Viertel-Node; Bodenhoehe wird in WELT-Koordinaten gefragt.
			var wx := center.x + off.x
			var wz := center.z + off.y
			var p := Vector3(off.x, 0.0, off.y)
			p.y = terrain.height_at(wx, wz) if terrain != null else center.y
			var sc: float = float(e.get("scale", 1.0))
			var b := Basis(Vector3.UP, float(e.get("yaw", 0.0)) + dreh).scaled(Vector3(sc, sc, sc))
			xf[i] = Transform3D(b, p)
			mm.set_instance_transform(i, xf[i])
		# NAHSTUFE: dieselben Transforms mit dem Detail-Mesh
		if _meshes_hd.has(t):
			var mh := MultiMesh.new()
			mh.transform_format = MultiMesh.TRANSFORM_3D
			mh.mesh = _meshes_hd[t]
			mh.instance_count = liste.size()
			for i in xf.size():
				mh.set_instance_transform(i, xf[i])
			var mih := MultiMeshInstance3D.new()
			mih.name = String(t) + "_HD"
			mih.multimesh = mh
			mih.visibility_range_end = LOD_DIST      # nur in der Naehe zeichnen
			node.add_child(mih)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = String(t)
		mmi.multimesh = mm
		if _meshes_hd.has(t):
			mmi.visibility_range_begin = LOD_DIST    # uebernimmt ab der Umschaltweite
		mmi.visibility_range_end = SICHT_DIST        # nie ueber den Terrainrand hinaus
		mmi.visibility_range_end_margin = SICHT_FADE
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		# KEIN custom_aabb: MultiMesh leitet seine Bounds aus den Instanzen ab. Eine von Hand
		# gesetzte Box um den Node-Ursprung hat frueher das ganze Viertel weggecullt
		# (Instanzen lagen in WELT-Koordinaten, die Box aber beim Ursprung).
		node.add_child(mmi)
	return node


# --- Viertel-Generatoren ---------------------------------------------------------------
# Jeder liefert einen Plan; Layouts sind deterministisch (fester RNG-Seed) — dieselbe
# Stadt bei jedem Start, unabhaengig vom Welt-Seed.

## GROSSSTADT: Hochhaus-Kern, drumherum Blockrand, aussen Vorstadt. Plus Stadion + Funkturm.
static func plan_grossstadt() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x0C17
	var plan: Array = []
	# Kern: die Tuerme (von Hand gesetzt, damit die Skyline sitzt)
	var kern := [
		["Haus_Wolkenkratzer", Vector2(0, 0), 0.35],
		["Haus_Bueroturm", Vector2(-78, 40), 0.0],
		["Haus_Bueroturm", Vector2(66, -52), 1.57],
		["Haus_Wohnturm", Vector2(-52, -70), 0.0],
		["Haus_Wohnturm", Vector2(30, 78), 3.14],
		["Haus_Wohnturm", Vector2(96, 62), 0.0],
		["Haus_Hotel", Vector2(-104, -34), 0.2],
		["Haus_Kaufhaus", Vector2(72, 12), 3.14],
		["Haus_Parkhaus", Vector2(-30, 96), 0.0],
		["Haus_Krankenhaus", Vector2(150, -96), 0.0],
		["Haus_Bahnhof", Vector2(-166, 108), 3.14],
		["Haus_Rathaus", Vector2(112, 128), 3.14],
		["Haus_Kirche", Vector2(-146, -128), 0.0],
		["Haus_Stadion", Vector2(300, 250), 0.4],
		["Haus_Funkturm", Vector2(-300, -230), 0.0],
		["Haus_Plattenbau", Vector2(-250, 210), 1.57],
		["Haus_Plattenbau", Vector2(-250, 300), 1.57],
		["Haus_Speicher", Vector2(230, -220), 0.0],
	]
	for k in kern:
		plan.append({"typ": k[0], "pos": k[1], "yaw": k[2]})
	# Blockrand-Bebauung: Stadthaeuser auf einem Raster mit Luecken
	var typen := ["Haus_Stadthaus2", "Haus_Stadthaus3", "Haus_Reihenhaus", "Haus_Eckhaus",
		"Haus_Gasthaus", "Haus_Villa"]
	for gx in range(-5, 6):
		for gz in range(-5, 6):
			var p := Vector2(float(gx) * 46.0, float(gz) * 46.0)
			if p.length() < 130.0 or p.length() > 250.0:
				continue                       # Kern freihalten, aussen ausduennen
			if rng.randf() < 0.30:
				continue
			plan.append({"typ": typen[rng.randi() % typen.size()],
				"pos": p + Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7)),
				"yaw": float(rng.randi() % 4) * 1.5708})
	return plan


## INDUSTRIEHAFEN: Fabrik, Kraftwerk, Silos, Kraene, Tanks — an einer Kaikante aufgereiht.
static func plan_industrie() -> Array:
	var plan: Array = []
	var teile := [
		["Haus_Fabrik", Vector2(-120, 40), 0.0],
		["Haus_Kraftwerk", Vector2(60, 90), 0.0],
		["Haus_Getreidesilo", Vector2(-40, -60), 1.57],
		["Haus_Hafenkran", Vector2(40, -140), 1.57],
		["Haus_Hafenkran", Vector2(110, -140), 1.57],
		["Haus_Tanklager", Vector2(180, 30), 0.0],
		["Haus_Wasserturm", Vector2(-180, -80), 0.0],
		["Haus_Speicher", Vector2(-10, -140), 0.0],
		["Haus_Speicher", Vector2(-60, -140), 0.0],
		["Haus_Werkstatt", Vector2(150, -60), 3.14],
		["Haus_Silo", Vector2(-110, -20), 0.0],
		["Haus_Lotsenhaus", Vector2(210, -150), 3.14],
		["Haus_Parkhaus", Vector2(-200, 90), 0.0],
	]
	for t in teile:
		plan.append({"typ": t[0], "pos": t[1], "yaw": t[2]})
	return plan


## LANDDORF: Bauernhoefe um einen Anger, Muehlen am Rand.
static func plan_dorf() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x0D0F
	var plan: Array = []
	var fest := [
		["Haus_Kapelle", Vector2(0, 0), 3.14],
		["Haus_Windmuehle", Vector2(-150, -90), 0.0],
		["Haus_Wassermuehle", Vector2(140, 110), 0.6],
		["Haus_Gasthaus", Vector2(-60, 60), 3.14],
		["Haus_Scheune", Vector2(90, -70), 1.2],
		["Haus_Scheune", Vector2(-120, 70), 0.3],
		["Haus_Stall", Vector2(60, -110), 1.57],
		["Haus_Silo", Vector2(120, -40), 0.0],
	]
	for f in fest:
		plan.append({"typ": f[0], "pos": f[1], "yaw": f[2]})
	var typen := ["Haus_Bauernhaus", "Haus_Fachwerk", "Haus_Kate", "Haus_Stadthaus2"]
	for i in 22:
		var a := rng.randf() * TAU
		var r := rng.randf_range(45.0, 175.0)
		plan.append({"typ": typen[rng.randi() % typen.size()],
			"pos": Vector2(cos(a) * r, sin(a) * r), "yaw": rng.randf() * TAU})
	return plan


## BURGBERG: Burg mit kleiner Vorburg-Siedlung.
static func plan_burg() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB017
	var plan: Array = [{"typ": "Haus_Burg", "pos": Vector2.ZERO, "yaw": 0.5}]
	for i in 9:
		var a := 0.9 + float(i) * 0.42
		var r := rng.randf_range(58.0, 92.0)
		plan.append({"typ": "Haus_Fachwerk" if i % 2 == 0 else "Haus_Kate",
			"pos": Vector2(cos(a) * r, sin(a) * r), "yaw": a + PI})
	plan.append({"typ": "Haus_Kirche", "pos": Vector2(-95, 55), "yaw": 0.9})
	return plan


## MILITAERPOSTEN: Radarstation + Bunker + Tower (passt zur FLAK-ZONE).
static func plan_militaer() -> Array:
	return [
		{"typ": "Haus_Radarstation", "pos": Vector2(0, 0), "yaw": 0.3},
		{"typ": "Haus_Bunker", "pos": Vector2(-70, 40), "yaw": 1.2},
		{"typ": "Haus_Bunker", "pos": Vector2(60, -55), "yaw": 2.6},
		{"typ": "Haus_Bunker", "pos": Vector2(95, 70), "yaw": 0.4},
		{"typ": "Haus_Tower", "pos": Vector2(-110, -80), "yaw": 0.0},
		{"typ": "Haus_Werkstatt", "pos": Vector2(-40, -110), "yaw": 1.57},
		{"typ": "Haus_Tanklager", "pos": Vector2(120, -10), "yaw": 1.57},
	]


## FLUGPLATZ-GEBAEUDE: Hangars + Tower + Wasserturm laengs der Bahn.
static func plan_flugplatz() -> Array:
	return [
		{"typ": "Haus_Hangar", "pos": Vector2(-40, 0), "yaw": 0.0},
		{"typ": "Haus_Hangar", "pos": Vector2(30, 0), "yaw": 0.0},
		{"typ": "Haus_Tower", "pos": Vector2(95, -30), "yaw": 3.14},
		{"typ": "Haus_Werkstatt", "pos": Vector2(-115, -10), "yaw": 0.0},
		{"typ": "Haus_Tanklager", "pos": Vector2(-40, 70), "yaw": 0.0},
		{"typ": "Haus_Wasserturm", "pos": Vector2(120, 60), "yaw": 0.0},
		{"typ": "Haus_Radarstation", "pos": Vector2(180, 20), "yaw": 3.14},
	]
