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
			# SCHATTEN AN. Hier stand frueher, das ginge nicht: die MultiMeshes tragen ihr
			# Material im Mesh statt als Override, und daraus wurde Fehlerspam, sobald das
			# Showroom-Licht als erster Schattenwerfer auftauchte. Nachgeprueft, seit auch
			# die Sonne im Flug wirft: mit cast_shadow ON kam ueber alle acht Abnahme-
			# Ansichten und ueber Start plus Hangar keine einzige Fehlerzeile. Ein
			# material_override waere hier ausserdem der falsche Ausweg — MultiMeshInstance3D
			# kennt keine Surface-Overrides, und die Haeuser sind Ein-Mesh-MEHR-Material-
			# Modelle: ein Override zoege alle Flaechen auf eine Farbe. Ohne Schatten
			# schweben die Haeuser ueber ihrem eigenen Grund — das war der teurere Fehler.
			mih.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			node.add_child(mih)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = String(t)
		mmi.multimesh = mm
		# Auch die Fernstufe wirft. Teuer wird das nicht: der Sonnenschatten reicht 3 km
		# weit (directional_shadow_max_distance), die Fernstufe uebernimmt ab 900 m — es
		# ist also nur das Band dazwischen, das ueberhaupt in eine Kaskade faellt.
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
	# VORSTADT. Die Stadt hoerte bei 250 m auf und war damit 600 m breit — im Anflug aus
	# 1,6 km eine Handvoll Tuermchen in leerer Heide, nicht die GROSSSTADT, als die sie auf
	# der Karte steht. Eine Stadt endet aber nicht an einer Linie, sie franst aus.
	#
	# DIE DICHTE FAELLT MIT DEM RADIUS, statt in Ringen zu springen: von 0.72 bei 250 m auf
	# 0.12 bei 620 m. Damit entsteht der Verlauf, den man aus der Luft kennt — geschlossene
	# Blockrandbebauung, dann Einzelhaeuser mit Gaerten, dann Hoefe im Feld.
	# Die Haustypen wechseln bei 450 m mit: aussen stehen Bauernhaus, Scheune und Kate, und
	# der Uebergang in die Landschaft ist damit auch inhaltlich einer und nicht nur eine
	# Ausduennung derselben Reihenhaeuser.
	#
	# DAS KOSTET FAST NICHTS: build() buendelt je Typ in ein MultiMesh, die zusaetzlichen
	# Haeuser sind also weitere Instanzen und keine weiteren Draw Calls. Und sie duerfen
	# ueber die Flachzone der Stadt (r_flat 480) hinausreichen, weil jedes Haus seine Hoehe
	# mit terrain.height_at selbst abtastet.
	var vorstadt := ["Haus_Reihenhaus", "Haus_Stadthaus2", "Haus_Villa", "Haus_Eckhaus",
		"Haus_Gasthaus", "Haus_Werkstatt"]
	var feldrand := ["Haus_Bauernhaus", "Haus_Scheune", "Haus_Kate", "Haus_Villa"]
	for gx in range(-14, 15):
		for gz in range(-14, 15):
			var q := Vector2(float(gx) * 46.0, float(gz) * 46.0)
			var d := q.length()
			if d <= 250.0 or d > 620.0:
				continue
			if rng.randf() > lerpf(0.72, 0.12, clampf((d - 250.0) / 370.0, 0.0, 1.0)):
				continue
			var liste: Array = vorstadt if d < 450.0 else feldrand
			plan.append({"typ": liste[rng.randi() % liste.size()],
				"pos": q + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9)),
				"yaw": float(rng.randi() % 4) * 1.5708})
	# Ein paar Marken in der Vorstadt, damit die Silhouette dort nicht nur aus Daechern
	# besteht — von Hand gesetzt, weil ein Wasserturm neben dem naechsten albern aussaehe.
	for m in [["Haus_Wasserturm", Vector2(-390, 210)], ["Haus_Kapelle", Vector2(345, -300)],
			["Haus_Werkstatt", Vector2(-300, -395)], ["Haus_Speicher", Vector2(430, 165)],
			["Haus_Windmuehle", Vector2(-520, -120)], ["Haus_Wasserturm", Vector2(255, 470)]]:
		plan.append({"typ": m[0], "pos": m[1], "yaw": rng.randf() * TAU})
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


## STRASSENNETZ — das, woran man eine Stadt aus der Luft ZUERST erkennt.
##
## WARUM ES DAS BRAUCHT. Der Stadtplan oben setzt Tuerme von Hand, baut Blockrand auf
## einem 46-m-Raster und laesst die Vorstadt nach aussen ausduennen. Aus 1500 m Hoehe kam
## davon trotzdem nichts an: die Abnahme las die Grossstadt als "rund 60 lose Kaesten auf
## einer nackten Sandscheibe, ohne Strassenraster, ohne Blockstruktur, ohne Zufahrt — ein
## Partikelstreuer mit dem Etikett Stadt". Und das stimmt: aus der Luft liest man eine
## Stadt an ihren LINIEN, nicht an ihren Haeusern. Die Haeuser sind aus der Hoehe nur
## Koernung, das Raster ist die Form.
##
## Vier Lagen, und jede beantwortet eine andere Entfernung:
##   RASTER    Wohnstrassen alle 46 m im Kern — die Koernung, die aus 800 m traegt.
##   ACHSEN    zwei Diagonalen durch die Mitte — die Form, die aus 3 km noch da ist.
##   RING      eine geschlossene Ringstrasse als KANTE. Vorher franste die Stadt ins
##             Gelaende aus und hatte gar keinen Rand; ein Ring gibt ihr eine Grenze.
##   AUSFALL   drei Strassen, die den Ring verlassen und in die Landschaft laufen. Sie
##             sind der Grund, warum die Stadt dort liegt, wo sie liegt.
##
## KOSTEN: ein einziges Mesh mit rund 90 Vierecken, ein Zeichenaufruf. Die Baender liegen
## flach auf dem Gelaende und tasten ihre Hoehe stueckweise ab (terrain.height_at), damit
## sie einer Mulde folgen statt darueber zu schweben.
static func strassennetz(parent: Node3D, terrain, center: Vector3, r_kern := 250.0,
		r_ring := 300.0, r_aus := 900.0) -> Node3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	# DUNKLER ALS ZUERST (0.24 / 0.20). Der Boden der Stadt liegt bei rund 0.62; ein
	# Grau bei 0.24 hebt sich davon zwar rechnerisch ab, aber durch die Luftperspektive
	# auf 1,6 km blieben davon gemessen nur rund 10 Prozent Wertunterschied uebrig — die
	# Strassen waren da, ohne im Bild zu erscheinen. Ein Belag darf ruhig fast schwarz
	# sein; genau so sieht frischer Asphalt aus der Luft aus.
	var asphalt := Color(0.13, 0.128, 0.135)
	var haupt := Color(0.10, 0.098, 0.107)

	# --- Raster im Kern -------------------------------------------------------------
	# Halbe Rasterweite versetzt, damit die Strassen ZWISCHEN den Hausreihen liegen und
	# nicht durch sie hindurch: der Bauplan setzt die Haeuser auf Vielfache von 46.
	var schritt := 46.0
	var n := int(r_kern / schritt)
	for i in range(-n, n + 1):
		var o := (float(i) + 0.5) * schritt
		if absf(o) > r_kern:
			continue
		# Laenge der Strasse in der Kreisscheibe (Sehne).
		var halb := sqrt(maxf(r_kern * r_kern - o * o, 0.0))
		_band(st, terrain, center, Vector2(-halb, o), Vector2(halb, o), 7.0, asphalt)
		_band(st, terrain, center, Vector2(o, -halb), Vector2(o, halb), 7.0, asphalt)

	# --- Diagonalachsen -------------------------------------------------------------
	var dk := r_kern * 0.92
	_band(st, terrain, center, Vector2(-dk, -dk), Vector2(dk, dk), 13.0, haupt)
	_band(st, terrain, center, Vector2(-dk, dk), Vector2(dk, -dk), 13.0, haupt)

	# --- Ringstrasse ----------------------------------------------------------------
	var seiten := 32
	for i in seiten:
		var a0 := TAU * float(i) / float(seiten)
		var a1 := TAU * float(i + 1) / float(seiten)
		_band(st, terrain, center,
			Vector2(cos(a0), sin(a0)) * r_ring, Vector2(cos(a1), sin(a1)) * r_ring,
			12.0, haupt)

	# --- Ausfallstrassen ------------------------------------------------------------
	# Drei Richtungen, unterschiedlich lang. Sie enden nicht abrupt, sondern verjuengen
	# sich (das letzte Stueck ist schmaler) — eine Strasse, die im Feld aufhoert, faellt
	# sonst als abgeschnittenes Band auf.
	for gr in [18.0, 142.0, 255.0]:
		var r := deg_to_rad(gr)
		var d := Vector2(cos(r), sin(r))
		_band(st, terrain, center, d * r_ring, d * (r_aus * 0.75), 11.0, haupt)
		_band(st, terrain, center, d * (r_aus * 0.75), d * r_aus, 7.0, asphalt)

	# OHNE DAS BLEIBT DAS NETZ UNSICHTBAR. Ein SurfaceTool-Netz ohne Normalen bekommt vom
	# Shader keine Beleuchtung — im ersten Anlauf war von den Strassen im Bild nichts zu
	# sehen, obwohl sie gebaut wurden.
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Strassen"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mi.material_override = mat
	# cast_shadow gehoert an die MeshInstance, NICHT an das Material — Godot meldet dort
	# nur eine Warnung und ignoriert es. Eine flach aufliegende Strasse soll ohnehin
	# keinen Schatten werfen.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = Vector3.ZERO
	return mi


## Ein Straßenband von a nach b (lokale Meter um "center"), auf das Gelände gelegt.
##
## Es wird in Stuecke von rund 24 m zerlegt und jedes Stueck tastet seine Ecken einzeln
## ab. Ohne das liegt ein 500 m langes Band als Ebene ueber einer gewellten Wiese und
## verschwindet in der ersten Mulde.
static func _band(st: SurfaceTool, terrain, center: Vector3, a: Vector2, b: Vector2,
		breite: float, col: Color) -> void:
	var laenge := a.distance_to(b)
	if laenge < 1.0:
		return
	var richtung := (b - a) / laenge
	var quer := Vector2(-richtung.y, richtung.x) * (breite * 0.5)
	var stuecke := maxi(1, int(laenge / 24.0))
	for i in stuecke:
		var t0 := float(i) / float(stuecke)
		var t1 := float(i + 1) / float(stuecke)
		var p0 := a.lerp(b, t0)
		var p1 := a.lerp(b, t1)
		# WICKLUNGSRICHTUNG — UND SIE WAR ZUERST FALSCH HERUM, MIT KOMPLETT UNSICHTBAREM
		# ERGEBNIS. "quer" entsteht als (-y, x) der Fahrtrichtung; das ist die
		# Linkssenkrechte in einer normalen x/y-Ebene, in der x/z-Ebene der Welt aber
		# wegen der gespiegelten z-Achse die RECHTSsenkrechte. Alle Baender zeigten
		# dadurch nach unten und wurden vom Rueckseitenkulling entfernt.
		#
		# GEFUNDEN NUR DURCH AUSSCHLUSS: das Netz existierte (1052 Dreiecke), war
		# sichtbar, lag laut AABB genau ueber der Stadt — und blieb selbst als magentaner
		# Streifen drei Meter ueber dem Boden bei NULL Pixeln. Erst ein einfacher Wuerfel
		# am selben Ort (der erschien) und danach ein Lauf mit CULL_DISABLED (1905 Pixel
		# mehr) haben die Ursache eingekreist.
		var ecken := [p0 - quer, p1 - quer, p1 + quer, p0 + quer]
		var w: Array[Vector3] = []
		for e in ecken:
			var wx: float = center.x + e.x
			var wz: float = center.z + e.y
			# 0,35 m ueber Grund: hoch genug gegen Z-Fighting, flach genug, dass keine
			# Kante im streifenden Licht als Mauer steht.
			w.append(Vector3(wx, terrain.height_at(wx, wz) + 0.35, wz))
		st.set_color(col)
		st.add_vertex(w[0]); st.add_vertex(w[1]); st.add_vertex(w[2])
		st.set_color(col)
		st.add_vertex(w[0]); st.add_vertex(w[2]); st.add_vertex(w[3])
