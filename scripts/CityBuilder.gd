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
## FARBVARIANTEN (tools/build_haeuser_blend.py, VARIANTEN): "Haus_Bauernhaus" ->
## ["Haus_Bauernhaus", "Haus_Bauernhaus_2", "Haus_Bauernhaus_3"]. Die Plaene nennen nur den
## Grundtyp; build() waehlt je Bauplatz eine Variante aus der Lage (fest, jeder Start gleich).
static var _varianten: Dictionary = {}
static var _loaded := false
## HAUS-SHADER (shaders/haus.gdshader): weiches Licht wie Gelaende und Baeume, Materialfarbe
## mal Vertexfarbe (gemalter Verlauf aus dem Bauskript). Je Quellmaterial EIN ShaderMaterial.
static var _haus_shader: Shader = null
static var _mat_cache: Dictionary = {}

## FUER DIE KARTE (WorldMap): Grundrisse aller gesetzten Haeuser und Strassenstuecke in
## Weltkoordinaten. Die Karte zeichnet daraus beim Hineinzoomen die ECHTE Bebauung statt
## eines Symbols. Main leert beides am Anfang von _setup_world (karte_leeren), sonst
## sammelten sich bei jedem neuen Main (Testlaeufe) Duplikate an.
## Haus: [Vector2 mitte, Vector2 halbe_groesse, float yaw]; Strasse: [Vector2 a, Vector2 b, breite]
static var karte_haeuser: Array = []
static var karte_strassen: Array = []


static func karte_leeren() -> void:
	karte_haeuser.clear()
	karte_strassen.clear()
	_netz_cache.clear()


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
		_malen(mi.mesh)
		ziel[nm] = mi.mesh
	root.free()


## Die importierten Standardmaterialien eines Haus-Meshes gegen den Haus-Shader tauschen
## (Farbe, Rauheit, Metall uebernommen). Die Meshes sind geteilte Ressourcen — der Tausch
## gilt fuer die Sitzung, die glb-Dateien bleiben unberuehrt.
static func _malen(mesh: Mesh) -> void:
	if _haus_shader == null:
		_haus_shader = load("res://shaders/haus.gdshader")
	if _haus_shader == null:
		return
	for si in mesh.get_surface_count():
		var m := mesh.surface_get_material(si)
		var bm := m as BaseMaterial3D
		if bm == null:
			continue
		if not _mat_cache.has(bm):
			var sm := ShaderMaterial.new()
			sm.shader = _haus_shader
			sm.set_shader_parameter("haus_farbe", bm.albedo_color)
			sm.set_shader_parameter("rauheit", bm.roughness)
			sm.set_shader_parameter("metall", bm.metallic)
			_mat_cache[bm] = sm
		mesh.surface_set_material(si, _mat_cache[bm])


static func _load_lib() -> void:
	if _loaded:
		return
	_loaded = true
	_sammeln(LIB, _meshes)
	_sammeln(LIB_HD, _meshes_hd)
	# Varianten zuordnen: "<Grundtyp>_<Zahl>", dessen Grundtyp selbst existiert. (Namen wie
	# "Haus_Stadthaus2" tragen die Zahl OHNE Unterstrich und sind eigene Typen.)
	for nm in _meshes.keys():
		var s := String(nm)
		var i := s.rfind("_")
		if i > 0 and s.substr(i + 1).is_valid_int() and _meshes.has(s.substr(0, i)):
			var grund := s.substr(0, i)
			if not _varianten.has(grund):
				_varianten[grund] = [grund]
			(_varianten[grund] as Array).append(s)
	for grund in _varianten:
		(_varianten[grund] as Array).sort()


## Variante eines Typs fuer einen Bauplatz (Weltlage) — Hash der Lage, damit dasselbe Dorf bei
## jedem Start gleich aussieht und Nachbarhaeuser selten dieselbe Farbe tragen.
static func variante(typ: String, wx: float, wz: float) -> String:
	var liste: Array = _varianten.get(typ, [])
	if liste.size() < 2:
		return typ
	# hash() mischt alle Bits. Ein XOR zweier Produkte (erste Fassung) hatte gerade untere Bits,
	# sobald die Bauplaetze auf einem geraden Raster lagen — bei zwei Varianten kam dann immer
	# dieselbe heraus (tools/_haus_varianten_check.gd).
	var h := hash(Vector2i(int(floor(wx * 0.5)), int(floor(wz * 0.5))))
	return String(liste[h % liste.size()])


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
	# Statisch: ohne Physik-Interpolation (sonst wartet jedes MultiMesh-Einhaengen auf den
	# Renderfaden, siehe TerrainWorld.setup)
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(node)
	# nach Typ buendeln -> je Typ ein MultiMesh. Die Farbvariante wird HIER gewaehlt (aus der
	# Weltlage des Bauplatzes); jede Variante ist ein eigenes Mesh, also ein eigenes MultiMesh.
	var nach_typ: Dictionary = {}
	for e in plan:
		var t := String(e.get("typ", ""))
		if not _meshes.has(t):
			continue
		if _varianten.has(t):
			var o0: Vector2 = e.get("pos", Vector2.ZERO)
			var r0: Vector3 = Basis(Vector3.UP, dreh) * Vector3(o0.x, 0.0, o0.y)
			t = variante(t, center.x + r0.x, center.z + r0.z)
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
			var bb: AABB = (_meshes[t] as Mesh).get_aabb()
			karte_haeuser.append([Vector2(wx, wz) + Vector2(bb.get_center().x, bb.get_center().z).rotated(
				-(float(e.get("yaw", 0.0)) + dreh)) * sc,
				Vector2(bb.size.x, bb.size.z) * (0.5 * sc), float(e.get("yaw", 0.0)) + dreh])
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

## STRASSENNETZ EINES ORTS (scripts/Stadtstrassen.gd) — die gemeinsame Grundlage fuer Bauplan
## UND Strassenbild: plan_grossstadt/plan_dorf setzen ihre Haeuser an genau die Strassen, die
## strassennetz() danach baut. Vorher standen die Haeuser auf einem eigenen Raster mit
## Zufallsversatz, die Strassen daneben — oder mitten hindurch.
##
##   STADT (r_kern >= 150): Raster alle RASTER m bis an die Ringstrasse, zwei Boulevards
##       (vier Spuren) als Achsenkreuz, die als Landstrassen und zuletzt als Feldwege in die
##       Landschaft auslaufen, dazu vier Vorstadtstrassen.
##   DORF: Strassenkreuz um den Anger, Dorfstrasse als Ring, vier Feldwege hinaus.
## `sperr`: OBBs grosser Bauten (Bahnhof ...) — Strassenstuecke darunter entfallen.
## `zufahrt`: Punkte (lokal), an denen eine Landstrasse ankommt; sie bekommt eine Einmuendung
## in den Ring.
const RASTER := 46.0
static var _netz_cache: Dictionary = {}


static func netz_ort(r_kern: float, r_ring: float, r_aus: float, sperr: Array = [],
		zufahrt: Array = [], schluessel := "") -> Dictionary:
	if schluessel != "" and _netz_cache.has(schluessel):
		return _netz_cache[schluessel]
	var netz := Stadtstrassen.netz_neu()
	var stadt := r_kern >= 150.0
	var ringpunkte: Array = []
	var linien: Array[float] = []
	var i_max := int(floor(r_kern / RASTER - 0.5)) if stadt else 0
	for i in range(-i_max - 1, i_max + 1):
		linien.append((float(i) + 0.5) * RASTER)
	var aussen: float = linien[linien.size() - 1]
	var hinaus := r_aus - r_ring
	var benutzt: Dictionary = {}
	for o in linien:
		var art := Stadtstrassen.STRASSE if stadt else Stadtstrassen.DORF
		if stadt and is_equal_approx(o, 0.5 * RASTER):
			art = Stadtstrassen.BOULEVARD
		# bis an den Ring — ausser der Stummel dorthin waere kuerzer als ein guter halber Block
		var reich := sqrt(maxf(r_ring * r_ring - o * o, 0.0))
		var am_ring := reich - aussen > RASTER * 0.6
		var bis := reich if am_ring else aussen
		for laengs_z: bool in [true, false]:
			var enden: Array[Vector2] = [Vector2(o, -bis), Vector2(o, bis)]
			if not laengs_z:
				enden = [Vector2(-bis, o), Vector2(bis, o)]
			Stadtstrassen.strecke(netz, enden[0], enden[1], art)
			if not am_ring:
				continue
			for ende in enden:
				ringpunkte.append(ende)
				var dir := Vector2(0.0, signf(ende.y)) if laengs_z else Vector2(signf(ende.x), 0.0)
				# Kommt hier in der Naehe eine Landstrasse an, schliesst SIE an dieses Ende an
				# (statt 30 m neben einer eigenen Ausfallstrasse herzulaufen).
				var zi := -1
				for k in zufahrt.size():
					var zz: Vector2 = zufahrt[k]
					if not benutzt.has(k) and zz.distance_to(ende) < 110.0 \
							and (zz - ende).normalized().dot(dir) > 0.77:
						zi = k
						break
				if zi >= 0:
					benutzt[zi] = true
					Stadtstrassen.strecke(netz, ende, zufahrt[zi], Stadtstrassen.LAND)
					continue
				if stadt and art == Stadtstrassen.BOULEVARD:
					# Achsen laufen als Landstrasse hinaus und zuletzt als Feldweg aus
					Stadtstrassen.strecke(netz, ende, ende + dir * hinaus * 0.72, Stadtstrassen.LAND)
					Stadtstrassen.strecke(netz, ende + dir * hinaus * 0.72, ende + dir * hinaus,
						Stadtstrassen.WEG)
				elif stadt and is_equal_approx(absf(o), 2.5 * RASTER):
					Stadtstrassen.strecke(netz, ende, ende + dir * 170.0, Stadtstrassen.DORF)   # Vorstadt
				elif not stadt and (o > 0.0) == ((ende.y if laengs_z else ende.x) > 0.0):
					# im Dorf laeuft je Linie EIN Ende als Feldweg hinaus (Windrad aus vier Wegen)
					Stadtstrassen.strecke(netz, ende, ende + dir * hinaus * 0.6, Stadtstrassen.WEG)
	# Zufahrten der Landstrassen: Stummel vom Ring zum Ankunftspunkt. Der Ringpunkt haelt
	# Abstand zu den anderen Anschluessen (sonst entstuende ein spitzer Fuenfarm-Knoten).
	for zk in zufahrt.size():
		if benutzt.has(zk):
			continue
		var z: Vector2 = zufahrt[zk]
		var w0 := z.angle()
		var gefunden := false
		var pr := Vector2.ZERO
		for versuch in 12:
			var dw := deg_to_rad(4.0) * floorf(float(versuch + 1) * 0.5) * (1.0 if versuch % 2 == 0 else -1.0)
			pr = Vector2(cos(w0 + dw), sin(w0 + dw)) * r_ring
			gefunden = true
			for q: Vector2 in ringpunkte:
				if q.distance_to(pr) < 36.0:
					gefunden = false
					break
			if gefunden:
				break
		if not gefunden:
			continue
		ringpunkte.append(pr)
		Stadtstrassen.strecke(netz, pr, z, Stadtstrassen.LAND)
	# RINGSTRASSE durch alle Anschlusspunkte; dazwischen Stuetzpunkte, damit kein Bogen
	# laenger als 12 Grad ist (die Knicke werden als Gehrung geschlossen).
	ringpunkte.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.angle() < y.angle())
	var ring: Array = []
	for i in ringpunkte.size():
		var q0: Vector2 = ringpunkte[i]
		var q1: Vector2 = ringpunkte[(i + 1) % ringpunkte.size()]
		ring.append(q0)
		var bogen := fposmod(q1.angle() - q0.angle(), TAU)
		var n := int(floor(bogen / deg_to_rad(12.0)))
		for j in range(1, n + 1):
			var w := q0.angle() + bogen * float(j) / float(n + 1)
			ring.append(Vector2(cos(w), sin(w)) * r_ring)
	Stadtstrassen.zug(netz, ring, Stadtstrassen.STRASSE if stadt else Stadtstrassen.DORF, true)
	Stadtstrassen.schliessen(netz, sperr)
	if schluessel != "":
		_netz_cache[schluessel] = netz
	return netz


## Wo Landstrassen den Kreis um einen Ort kreuzen: Punkte (lokal) auf dem Radius r.
static func zufahrten(terrain, center: Vector3, r: float) -> Array:
	var raus: Array = []
	if terrain == null:
		return raus
	var c := Vector2(center.x, center.z)
	for pr in terrain.strassen_profile:
		var pts: PackedVector2Array = pr[0]
		for i in range(pts.size() - 1):
			var a := pts[i] - c
			var b := pts[i + 1] - c
			if (a.length() < r) == (b.length() < r):
				continue
			var q := a.lerp(b, clampf((r - a.length()) / (b.length() - a.length()), 0.0, 1.0))
			var neu := true
			for z: Vector2 in raus:
				if z.distance_to(q) < 40.0:
					neu = false
			if neu:
				raus.append(q)
	return raus


## Feste Bauten als Planeintraege und als OBBs fuer Netz und Bebauung.
static func _fest(liste: Array, plan: Array, belegt: Array, rand := 1.5) -> void:
	for f in liste:
		var typ := String(f[0])
		if not _meshes.has(typ):
			continue
		plan.append({"typ": typ, "pos": f[1], "yaw": float(f[2])})
		belegt.append(Stadtstrassen.obb(typ, f[1], float(f[2]), rand))


## Die festen Bauten der Grossstadt: Tuerme und oeffentliche Bauten stehen in der MITTE ihres
## Blocks (Vielfache von RASTER), der Bahnhof ueber zwei Bloecke (die Strasse dazwischen
## entfaellt), Stadion und Funkturm ausserhalb des Rings.
const GROSSSTADT_FEST := [
	["Haus_Wolkenkratzer", Vector2(0, 0), 0.0],
	["Haus_Bueroturm", Vector2(-92, 46), 0.0],
	["Haus_Bueroturm", Vector2(92, -46), 1.5708],
	["Haus_Wohnturm", Vector2(-46, -92), 0.0],
	["Haus_Wohnturm", Vector2(46, 92), 3.1416],
	["Haus_Wohnturm", Vector2(92, 46), 0.0],
	["Haus_Hotel", Vector2(-92, -46), 0.0],
	["Haus_Kaufhaus", Vector2(-139.5, 46), 0.0],
	["Haus_Parkhaus", Vector2(-46, 92), 0.0],
	["Haus_Krankenhaus", Vector2(138, -92), 0.0],
	["Haus_Bahnhof", Vector2(-161, 92), 3.1416],
	["Haus_Rathaus", Vector2(92, 138), 3.1416],
	["Haus_Kirche", Vector2(-138, -138), 0.0],
	["Haus_Stadion", Vector2(330, 280), 0.4],
	["Haus_Funkturm", Vector2(-330, -260), 0.0],
	["Haus_Plattenbau", Vector2(-292, 268), 1.5708],
	["Haus_Plattenbau", Vector2(-350, 268), 1.5708],
	["Haus_Speicher", Vector2(262, -250), 0.0],
	["Haus_Wasserturm", Vector2(-420, 240), 0.0],
	["Haus_Kapelle", Vector2(375, -330), 0.6],
	["Haus_Windmuehle", Vector2(-560, -150), 1.1],
	["Haus_Wasserturm", Vector2(285, 500), 0.0],
]


static func netz_grossstadt(zufahrt: Array = []) -> Dictionary:
	if _netz_cache.has("grossstadt"):
		return _netz_cache["grossstadt"]
	_load_lib()
	var sperr: Array = []
	for f in GROSSSTADT_FEST:
		if String(f[0]) == "Haus_Bahnhof" and _meshes.has(f[0]):
			sperr.append(Stadtstrassen.obb(f[0], f[1], float(f[2]), 0.0))
	return netz_ort(250.0, 300.0, 900.0, sperr, zufahrt, "grossstadt")


## GROSSSTADT: Hochhaus-Kern, drumherum Blockrand, aussen Vorstadt. Plus Stadion + Funkturm.
## Alle Haeuser stehen AN einer Strasse des Netzes (Front zum Gehweg). Die Dichte faellt mit
## dem Abstand von der Mitte: geschlossene Blockraender im Kern, lockere Zeilen an den
## Vorstadtstrassen, Hoefe an den Landstrassen und Feldwegen.
static func plan_grossstadt(zufahrt: Array = []) -> Array:
	_load_lib()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x0C17
	var plan: Array = []
	var belegt: Array = []
	_fest(GROSSSTADT_FEST, plan, belegt)
	var netz := netz_grossstadt(zufahrt)
	var kern := ["Haus_Stadthaus3", "Haus_Stadthaus2", "Haus_Eckhaus", "Haus_Stadthaus3",
		"Haus_Gasthaus", "Haus_Reihenhaus"]
	var vorstadt := ["Haus_Reihenhaus", "Haus_Stadthaus2", "Haus_Villa", "Haus_Eckhaus",
		"Haus_Villa", "Haus_Werkstatt"]
	var feldrand := ["Haus_Bauernhaus", "Haus_Scheune", "Haus_Kate", "Haus_Villa"]
	var waehle := func(q: Vector2, r: RandomNumberGenerator) -> String:
		var d := q.length()
		var wurf := r.randf()
		var wahl := r.randi()
		if d < 285.0:
			return String(kern[wahl % kern.size()]) if wurf < 0.93 else ""
		if d < 470.0:
			return String(vorstadt[wahl % vorstadt.size()]) \
				if wurf < lerpf(0.72, 0.42, (d - 285.0) / 185.0) else ""
		return String(feldrand[wahl % feldrand.size()]) \
			if wurf < lerpf(0.30, 0.10, clampf((d - 470.0) / 300.0, 0.0, 1.0)) else ""
	plan.append_array(Stadtstrassen.bebauen(netz, rng, waehle, belegt))
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


## LANDDORF: Bauernhoefe um einen Anger, Muehlen am Rand. Die Haeuser stehen an den
## Dorfstrassen des Netzes (netz_ort im Dorfmassstab); auf dem Anger steht die Kapelle.
const DORF_FEST := [
	["Haus_Kapelle", Vector2(0, 0), 3.1416],
	["Haus_Windmuehle", Vector2(-150, -90), 0.0],
	["Haus_Wassermuehle", Vector2(140, 110), 0.6],
	["Haus_Gasthaus", Vector2(-46, 40), 3.1416],
	["Haus_Scheune", Vector2(138, -78), 1.2],
	["Haus_Scheune", Vector2(-138, 70), 0.3],
	["Haus_Stall", Vector2(74, -128), 1.5708],
	["Haus_Silo", Vector2(142, -44), 0.0],
]


static func netz_dorf(zufahrt: Array = []) -> Dictionary:
	return netz_ort(90.0, 120.0, 420.0, [], zufahrt)


static func plan_dorf(zufahrt: Array = []) -> Array:
	_load_lib()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x0D0F
	var plan: Array = []
	var belegt: Array = []
	_fest(DORF_FEST, plan, belegt)
	var netz := netz_dorf(zufahrt)
	var typen := ["Haus_Bauernhaus", "Haus_Fachwerk", "Haus_Kate", "Haus_Stadthaus2",
		"Haus_Fachwerk", "Haus_Bauernhaus"]
	var waehle := func(q: Vector2, r: RandomNumberGenerator) -> String:
		var wurf := r.randf()
		var wahl := r.randi()
		# Anger freihalten, nach aussen ausduennen
		if absf(q.x) < 21.0 and absf(q.y) < 21.0:
			return ""
		return String(typen[wahl % typen.size()]) \
			if wurf < lerpf(0.42, 0.08, clampf(q.length() / 170.0, 0.0, 1.0)) else ""
	plan.append_array(Stadtstrassen.bebauen(netz, rng, waehle, belegt,
		[Stadtstrassen.DORF], 1.6, 6.0))
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
## Aus der Luft liest man eine Stadt an ihren LINIEN, nicht an ihren Haeusern: die Haeuser
## sind aus der Hoehe nur Koernung, das Raster ist die Form. Die erste Fassung legte dafuer
## einfarbige Baender aufs Gelaende (Raster, zwei Diagonalen, Ring aus 32 Rechtecken, drei
## Ausfallstrassen). Aus der Naehe trug das nicht: die Baender ueberlappten an jeder
## Kreuzung, der Ring klaffte an den Knicken, es gab weder Gehweg noch Markierung, und die
## Diagonalen liefen mitten durch die Haeuser.
##
## Jetzt baut Stadtstrassen (scripts/Stadtstrassen.gd) das Netz aus netz_ort(): Fahrbahn,
## Bordstein, Gehweg, Mittellinien, Zebrastreifen, geschlossene Kreuzungen — und die
## Bauplaene setzen ihre Haeuser an genau diese Strassen. `plan`: Bauten, unter denen
## Strassenstuecke entfallen sollen (Orte, deren Plan nicht aus dem Netz entsteht).
static func strassennetz(parent: Node3D, terrain, center: Vector3, r_kern := 250.0,
		r_ring := 300.0, r_aus := 900.0, zufahrt: Array = [], plan: Array = []) -> Node3D:
	var netz: Dictionary
	if r_kern >= 150.0:
		netz = netz_grossstadt(zufahrt)
	elif plan.is_empty():
		netz = netz_dorf(zufahrt)
	else:
		_load_lib()
		var sperr: Array = []
		for e in plan:
			sperr.append(Stadtstrassen.obb(String(e["typ"]), e["pos"], float(e.get("yaw", 0.0)), 1.0))
		netz = netz_ort(r_kern, r_ring, r_aus, sperr, zufahrt)
	return Stadtstrassen.bauen(parent, terrain, center, netz,
		"Strassen_%d_%d" % [int(center.x), int(center.z)])


## Ein Straßenband von a nach b (lokale Meter um "center"), auf das Gelände gelegt.
## (Seit den Stadtstrassen ohne Aufrufer; bleibt wegen der Wicklungs-Lektion unten stehen,
## auf die Strassen.gd und Skyline.gd verweisen.)
##
## Es wird in Stuecke von rund 24 m zerlegt und jedes Stueck tastet seine Ecken einzeln
## ab. Ohne das liegt ein 500 m langes Band als Ebene ueber einer gewellten Wiese und
## verschwindet in der ersten Mulde.
static func _band(st: SurfaceTool, terrain, center: Vector3, a: Vector2, b: Vector2,
		breite: float, col: Color) -> void:
	var laenge := a.distance_to(b)
	if laenge < 1.0:
		return
	karte_strassen.append([Vector2(center.x, center.z) + a, Vector2(center.x, center.z) + b, breite])
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
