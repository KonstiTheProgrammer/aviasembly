## HAFENSTADT "FREIHAFEN" am Westufer des Ostgolfs, mit der FREIHEITSSTATUE auf einer Insel
## vor der Hafeneinfahrt.
##
## AUFBAU (lokale Koordinaten um MITTE: x nach Osten = zum Wasser, z nach Sueden):
##   * Flachzone (Kreis R_FLACH) auf STADT_Y, nach Osten an der KAIKANTE x = KAI_X gerade
##     abgeschnitten (TerrainWorld: Zonenschluessel "kai") — davor das Hafenbecken, das eine
##     eigene Wasserform garantiert (unabhaengig vom Welt-Seed).
##   * Strassenraster 120 m, Blockrandbebauung aus den Blender-Haeusern (CityBuilder), nach
##     Vierteln: Altstadt um den Markt, Speicherstadt und Frachtkai im Norden, Fischerhafen
##     im Sueden, Wohnviertel landeinwaerts, Villen und Hoefe am Hang.
##   * Kaimauer, drei Piers, zwei Molen mit Leuchtfeuern, Containerlager — EIN Netz mit dem
##     Haus-Shader (Farbe je Eckpunkt) und Kastenkollision (man kann darauf landen).
##   * Schiffe (Frachter, Dampfer, Kutter, Segler) — ein Netz, ohne Kollision.
##   * Baeume an Promenade, Markt und im Stadtpark: eigene MultiMeshes mit den Flora-Netzen
##     des Gelaendes (die Flachzone selbst haelt den Bewuchs frei).
##   * Statueninsel: zweite Flachzone im Wasser, darauf "Haus_Freiheitsstatue"
##     (tools/build_haeuser_blend.py), mit Kollision und bis STATUE_SICHT sichtbar.
## Alles deterministisch (feste RNG-Seeds). Beleg: tools/_hafenstadt_check.gd.
class_name Hafenstadt
extends RefCounted

const MITTE := Vector3(14300.0, 0.0, 9900.0)
const STADT_Y := -2.0            # 4 m ueber dem Meer (SEA_Y = -6)
const R_FLACH := 560.0
const R_BLEND := 800.0
const KAI_X := 300.0             # Gelaendekante; die Kaimauer steht KAI_VOR davor
const KAI_VOR := 12.0
const KAI_HALB := 468.0          # halbe Laenge der Kaimauer (z)
const APRON_X := 232.0           # ab hier nach Osten ist der Kai gepflastert
const INSEL := Vector2(1040.0, 60.0)
const INSEL_Y := -2.5
const INSEL_R := 80.0
const INSEL_BLEND := 150.0
const INSEL_UFER := 104.0        # Ufermauer: verdeckt die Boeschung der Flachzone
# 93 m -> 150 m. In Originalgroesse stand sie vom Kai aus (1 km) als kleine Figur im Becken;
# ein Wahrzeichen in einem Flugspiel muss man aus mehreren Kilometern erkennen.
const STATUE_MASS := 1.6
const STATUE_YAW := 0.9          # Blick nach Suedosten, zur Einfahrt des Golfs
const STATUE_SICHT := 9000.0
const RASTER := 120.0
const NS := [190.0, 70.0, -50.0, -170.0, -290.0, -410.0]            # Strassen laengs z
const OW := [-360.0, -240.0, -120.0, 0.0, 120.0, 240.0, 360.0]      # Strassen laengs x
# Gesamtbreiten (Fahrbahn + Gehwege) wie Stadtstrassen.breite(): Strasse, Boulevard, Gasse
const STRASSE_B := 11.0
const HAUPT_B := 18.0
const GASSE_B := 5.0
const KAISTR_X := 262.5          # Kaistrasse laengs der Promenade (Altstadt- und Fischerkai)
# ANSCHLUSS ANS LANDSTRASSENNETZ: zwei Ortsausgaenge (lokal). Bis hierher reicht das Stadtnetz
# (Landstrassen-Stummel), ab hier laeuft die Landstrasse aus scripts/StrassenZusatz.gd
# (erzeugt von tools/_dorf_planer.gd -- anschluss).
const AUSGANG_WEST := Vector2(-652.0, -138.0)     # Richtung GROSSSTADT (Bruecke ueber den Silberfluss)
const AUSGANG_NORD := Vector2(-178.0, -652.0)     # Richtung Rosenthal (von dort weiter nach Fuchsried)
const NORD_ACHSE := -170.0                        # die Stadtstrasse, die im Norden hinausfuehrt
const VORGARTEN := 1.0           # Abstand der Hausfront vom Gehweg
## GASSEN in Altstadt, Speicherstadt und Fischerviertel: sie halbieren die 120-m-Bloecke.
## Ohne sie stand je Block nur eine duenne Haeuserzeile um einen leeren Hof — aus der Luft
## ein Vorort-Raster, keine Hafenstadt. [Achse, von, bis, laengs z?]
const GASSEN := [
	[130.0, -360.0, -120.0, true], [130.0, 0.0, 440.0, true],
	[10.0, -360.0, -120.0, true], [10.0, 120.0, 440.0, true],
	[-110.0, -360.0, 440.0, true],
	[-300.0, -170.0, 232.0, false], [-180.0, -170.0, 232.0, false],
	[-60.0, -170.0, 70.0, false], [60.0, -170.0, -50.0, false], [60.0, 70.0, 232.0, false],
	[180.0, -170.0, 232.0, false], [300.0, -170.0, 232.0, false],
]

# Haustyp -> [Breite laengs der Strasse, Tiefe nach vorn, Tiefe nach hinten]
const MASS := {
	"Haus_Stadthaus2": [9.6, 4.9, 4.3], "Haus_Stadthaus3": [7.0, 4.8, 4.6],
	"Haus_Fachwerk": [9.6, 4.7, 4.2], "Haus_Eckhaus": [15.8, 4.9, 6.2],
	"Haus_Gasthaus": [13.2, 6.6, 5.1], "Haus_Reihenhaus": [17.6, 4.9, 4.4],
	"Haus_Villa": [13.6, 7.9, 5.6], "Haus_Speicher": [10.6, 9.0, 6.8],
	"Haus_Werkstatt": [18.4, 4.3, 4.3], "Haus_Kate": [7.4, 3.3, 3.3],
	"Haus_Bauernhaus": [12.2, 4.9, 4.6],
}
const VIERTEL := {
	"alt": [["Haus_Stadthaus3", 0.34], ["Haus_Stadthaus2", 0.30], ["Haus_Fachwerk", 0.22],
		["Haus_Eckhaus", 0.08], ["Haus_Gasthaus", 0.06]],
	"speicher": [["Haus_Speicher", 0.80], ["Haus_Werkstatt", 0.20]],
	"fisch": [["Haus_Kate", 0.40], ["Haus_Fachwerk", 0.35], ["Haus_Stadthaus2", 0.25]],
	"wohn": [["Haus_Reihenhaus", 0.34], ["Haus_Stadthaus2", 0.32], ["Haus_Stadthaus3", 0.14],
		["Haus_Eckhaus", 0.10], ["Haus_Villa", 0.10]],
}

const C_APRON := Color(0.58, 0.57, 0.54)
const C_MARKT := Color(0.64, 0.58, 0.48)
const C_KAI := Color(0.55, 0.54, 0.52)
const C_KAI_KANTE := Color(0.72, 0.70, 0.65)
const C_FELS := Color(0.25, 0.25, 0.27)
const C_HOLZ := Color(0.44, 0.34, 0.24)


static func insel_welt() -> Vector3:
	return Vector3(MITTE.x + INSEL.x, INSEL_Y, MITTE.z + INSEL.y)


## Flachzonen fuer TerrainWorld (vor setup()): die Stadt mit Kaikante, die Statueninsel.
static func flachzonen() -> Array:
	var ins := insel_welt()
	return [
		{"pos": Vector3(MITTE.x, STADT_Y, MITTE.z), "r_flat": R_FLACH, "r_blend": R_BLEND,
			"y": STADT_Y, "kai": Vector3(1.0, 0.0, KAI_X)},
		{"pos": ins, "r_flat": INSEL_R, "r_blend": INSEL_BLEND, "y": INSEL_Y},
	]


## HAFENBECKEN als Wasserform (senkt nur): vor der Kaikante liegt damit bei JEDEM Welt-Seed
## tiefes Wasser — der Rand des Ostgolfs selbst haengt am Seed (breit_rausch).
static func wasserformen() -> Array:
	var p := PackedVector2Array()
	for l in [Vector2(1600, 400), Vector2(740, 380), Vector2(600, 0), Vector2(640, -560)]:
		p.append(Vector2(MITTE.x + l.x, MITTE.z + l.y))
	return [{"art": "wasser", "nur_senken": true, "pts": p,
		"hs": PackedFloat32Array([-12.0, -12.0, -12.0, -12.0]), "r_kern": 300.0, "r_aus": 480.0}]


## Auftraege fuer den Strassenplaner: [Start (Welt, am Ortsausgang), Ziel im vorhandenen Netz].
static func anschluesse() -> Array:
	var m := Vector2(MITTE.x, MITTE.z)
	return [
		[m + AUSGANG_NORD, Vector2(14250, 1450)],     # Fuchsried; der Planer buendelt ueber Rosenthal
		[m + AUSGANG_WEST, Vector2(4350, 2550)],      # GROSSSTADT
	]


static func _nord_ende() -> Vector2:
	return Vector2(NORD_ACHSE, -sqrt(540.0 * 540.0 - NORD_ACHSE * NORD_ACHSE))


static func _west_ende() -> Vector2:
	return Vector2(-sqrt(540.0 * 540.0 - 120.0 * 120.0), -120.0)


## Kartenpunkte (WorldMap).
static func pois() -> Array:
	return [
		{"name": "FREIHAFEN", "pos": MITTE, "color": Color(0.60, 0.86, 0.95), "art": "ort",
			"radius": 420.0},
		{"name": "Freiheitsstatue", "pos": insel_welt(), "color": Color(0.55, 0.90, 0.78)},
	]


# --- Stadtplan -------------------------------------------------------------------------------
static var _netz: Dictionary = {}


## Das Strassennetz fuer Stadtstrassen (Fahrbahn, Gehweg, Kreuzungen): alle Strassen aus
## strassen(), dazu die Kaistrasse und die Landstrasse nach Westen. Die Ost-West-Strassen
## suedlich des Frachtkais laufen ueber das Kaipflaster bis zur Kaistrasse durch.
static func netz() -> Dictionary:
	if not _netz.is_empty():
		return _netz
	var n := Stadtstrassen.netz_neu()
	for sg in strassen():
		var br: float = sg[4]
		var art := Stadtstrassen.BOULEVARD if br > 14.0 else Stadtstrassen.GASSE if br < 6.0 \
			else Stadtstrassen.STRASSE
		var a: float = sg[0]
		var bis: float = sg[2]
		if sg[3]:
			Stadtstrassen.strecke(n, Vector2(a, float(sg[1])), Vector2(a, bis), art)
		else:
			if is_equal_approx(bis, APRON_X) and a > -130.0:
				bis = KAISTR_X
			Stadtstrassen.strecke(n, Vector2(float(sg[1]), a), Vector2(bis, a), art)
	Stadtstrassen.strecke(n, Vector2(KAISTR_X, -120.0), Vector2(KAISTR_X, 440.0), Stadtstrassen.LAND)
	# Ortsausgaenge: Landstrassen-Stummel bis zum Beginn der Landstrassen (StrassenZusatz)
	Stadtstrassen.strecke(n, _west_ende(), AUSGANG_WEST, Stadtstrassen.LAND)
	Stadtstrassen.strecke(n, _nord_ende(), AUSGANG_NORD, Stadtstrassen.LAND)
	Stadtstrassen.schliessen(n)
	_netz = n
	return n


## Alle Strassenstuecke: [Achse, von, bis, laengs z?, Breite]
static func strassen() -> Array:
	var liste: Array = []
	for sx in NS:
		var reich := sqrt(maxf(540.0 * 540.0 - float(sx) * float(sx), 0.0))
		liste.append([float(sx), -reich, reich, true, STRASSE_B])
	for sz in OW:
		var reich := sqrt(maxf(540.0 * 540.0 - float(sz) * float(sz), 0.0))
		var haupt := is_zero_approx(float(sz))
		liste.append([float(sz), -462.0 if haupt else -reich, APRON_X, false,
			HAUPT_B if haupt else STRASSE_B])
	for g in GASSEN:
		liste.append([float(g[0]), float(g[1]), float(g[2]), bool(g[3]), GASSE_B])
	return liste


static func _viertel(p: Vector2) -> String:
	if p.y < -128.0 and p.x > 60.0:
		return "speicher"
	if p.y > 232.0 and p.x > 60.0:
		return "fisch"
	if absf(p.y) < 250.0 and p.x > -180.0:
		return "alt"
	return "wohn"


static func _dichte(p: Vector2, viertel: String) -> float:
	if viertel == "alt":
		return 0.96
	if viertel == "speicher" or viertel == "fisch":
		return 0.88
	return lerpf(0.80, 0.30, clampf((p.length() - 260.0) / 280.0, 0.0, 1.0))


static func _waehle(rng: RandomNumberGenerator, viertel: String) -> String:
	var typen: Array = VIERTEL[viertel]
	var r := rng.randf()
	var summe := 0.0
	for e in typen:
		summe += float(e[1])
		if r < summe:
			return String(e[0])
	return String(typen[0][0])


## Bauplan: [{"typ", "pos" (lokal), "yaw"}]. `frei` sammelt die belegten Rechtecke
## (Rect2 lokal), damit Baeume und Strassenmoebel nicht in Haeusern landen.
static func plan(frei: Array = []) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xF4E1
	var liste: Array = []
	var belegt: Array[Rect2] = []
	# RESERVIERT: Markt, Stadtpark, Frachtkai/Industrie im Norden, Bahnhofsplatz
	var tabu: Array[Rect2] = [
		Rect2(76, -114, 108, 108),          # Marktplatz
		Rect2(-44, 6, 108, 108),            # Stadtpark
		Rect2(-150, -560, 400, 192),        # Industrie am Nordkai
		Rect2(-560, -40, 110, 80),          # Bahnhof
	]
	# --- von Hand gesetzte Bauten ---------------------------------------------------------
	var fest := [
		["Haus_Rathaus", Vector2(92, -60), PI * 0.5],
		["Haus_Kirche", Vector2(150, -92), 0.0],
		["Haus_Gasthaus", Vector2(172, -28), -PI * 0.5],
		["Haus_Hotel", Vector2(211, 34), PI * 0.5],
		["Haus_Kaufhaus", Vector2(10, -22), 0.0],
		["Haus_Bahnhof", Vector2(-492, 0), PI * 0.5],
		["Haus_Krankenhaus", Vector2(-230, 182), PI],
		["Haus_Kapelle", Vector2(12, 62), PI],
		# Nordkai: Kraene, Silo, Tanks, Fabrik
		["Haus_Hafenkran", Vector2(292, -410), 0.0],
		["Haus_Hafenkran", Vector2(292, -330), 0.0],
		["Haus_Hafenkran", Vector2(292, -250), 0.0],
		["Haus_Getreidesilo", Vector2(150, -418), 0.0],
		["Haus_Tanklager", Vector2(40, -452), PI * 0.5],
		["Haus_Tanklager", Vector2(-20, -494), PI * 0.5],
		["Haus_Fabrik", Vector2(-92, -430), 0.0],
		["Haus_Werkstatt", Vector2(214, -396), PI * 0.5],
		# Fischerhafen
		["Haus_Werkstatt", Vector2(291, 300), PI * 0.5],
		["Haus_Werkstatt", Vector2(291, 388), PI * 0.5],
		["Haus_Lotsenhaus", Vector2(284, 424), PI * 0.5],
		["Haus_Lotsenhaus", Vector2(290, -120), PI * 0.5],
		# Rand
		["Haus_Wasserturm", Vector2(-322, -318), 0.0],
		["Haus_Windmuehle", Vector2(-560, 250), 1.2],
		["Haus_Windmuehle", Vector2(-420, 470), 0.5],
	]
	for f in fest:
		var typ := String(f[0])
		var pos: Vector2 = f[1]
		liste.append({"typ": typ, "pos": pos, "yaw": float(f[2])})
		var mesh: Mesh = CityBuilder._meshes.get(typ)
		var halb := Vector2(12.0, 12.0)
		if mesh != null:
			var ab := mesh.get_aabb()
			halb = Vector2(maxf(absf(ab.position.x), ab.end.x), maxf(absf(ab.position.z), ab.end.z))
			if absf(sin(float(f[2]))) > 0.5:
				halb = Vector2(halb.y, halb.x)
		belegt.append(Rect2(pos - halb - Vector2(2, 2), halb * 2.0 + Vector2(4, 4)))
	# --- Blockrand entlang aller Strassen ----------------------------------------------------
	# Strassenstuecke: [fest, von, bis, laengs_z?, Breite]
	var liste_str := strassen()
	var stuecke: Array = liste_str.duplicate()
	# Uferzeile: Haeuser mit Front zum Kai (wie an einer Strasse bei x = APRON_X + 4)
	stuecke.append([APRON_X + 4.0, -128.0, 440.0, true, 8.0, -1])
	stuecke.append([APRON_X + 4.0, -360.0, -132.0, true, 8.0, -1])
	for s in stuecke:
		var achse: float = s[0]
		var laengs_z: bool = s[3]
		var halb_b: float = float(s[4]) * 0.5
		for seite: int in [-1, 1]:
			if s.size() > 5 and seite != int(s[5]):
				continue
			var t: float = float(s[1]) + 4.0
			while t < float(s[2]) - 6.0:
				var probe := Vector2(achse, t) if laengs_z else Vector2(t, achse)
				var vt := _viertel(probe + (Vector2(seite * 14.0, 0) if laengs_z
					else Vector2(0, seite * 14.0)))
				var typ := _waehle(rng, vt)
				var m: Array = MASS[typ]
				var w: float = m[0]
				var vorn: float = m[1]
				var hinten: float = m[2]
				var quer := halb_b + VORGARTEN + vorn
				var mitte_t := t + w * 0.5
				var pos := Vector2(achse + seite * quer, mitte_t) if laengs_z \
					else Vector2(mitte_t, achse + seite * quer)
				# Front zur Strasse: Haus-+z zeigt gegen `seite`
				var yaw := (-PI * 0.5 if seite > 0 else PI * 0.5) if laengs_z \
					else (PI if seite > 0 else 0.0)
				var tief := (vorn + hinten) * 0.5
				var mitte_q := achse + seite * (halb_b + VORGARTEN + tief)
				var rect := Rect2(Vector2(mitte_q - tief, t), Vector2(tief * 2.0, w)) if laengs_z \
					else Rect2(Vector2(t, mitte_q - tief), Vector2(w, tief * 2.0))
				t += w + 0.7
				if rng.randf() > _dichte(pos, vt):
					continue
				if pos.length() > 546.0 or rect.end.x > APRON_X - 1.0:
					continue
				if _kreuzt_strasse(liste_str, rect, achse, laengs_z):
					continue
				var frei_hier := true
				for r in tabu:
					if r.intersects(rect):
						frei_hier = false
						break
				if frei_hier:
					for r in belegt:
						if r.intersects(rect):
							frei_hier = false
							break
				if not frei_hier:
					continue
				belegt.append(rect)
				liste.append({"typ": typ, "pos": pos, "yaw": yaw})
	# --- Am Hang rings um die Stadt: Villen, Hoefe, Katen (auf gewachsenem Gelaende) ---------
	var hang := ["Haus_Villa", "Haus_Bauernhaus", "Haus_Kate", "Haus_Scheune", "Haus_Villa"]
	for i in 34:
		var a := lerpf(1.75, 4.55, (float(i) + rng.randf()) / 34.0)      # West- und Landseite
		var r := rng.randf_range(R_FLACH + 14.0, R_FLACH + 150.0)
		var pos := Vector2(cos(a) * r, sin(a) * r)
		var typ_h: String = hang[rng.randi() % hang.size()]
		var yaw_h := atan2(-pos.x, -pos.y) + rng.randf_range(-0.5, 0.5)
		# nicht auf die Ortsausgaenge (die Landstrassen dahinter prueft bauen() am Gelaende)
		if Geometry2D.get_closest_point_to_segment(pos, _west_ende(), AUSGANG_WEST).distance_to(pos) < 24.0 \
				or Geometry2D.get_closest_point_to_segment(pos, _nord_ende(), AUSGANG_NORD).distance_to(pos) < 24.0:
			continue
		liste.append({"typ": typ_h, "pos": pos, "yaw": yaw_h})
	for r in belegt:
		frei.append(r)
	for r in tabu:
		frei.append(r)
	return liste


## Liegt das Rechteck auf einer ANDEREN Strasse (oder zu nah an ihr)? Die eigene zaehlt nicht.
static func _kreuzt_strasse(liste_str: Array, rect: Rect2, achse: float, laengs_z: bool) -> bool:
	for st in liste_str:
		var a: float = st[0]
		var lz: bool = st[3]
		if lz == laengs_z and is_equal_approx(a, achse):
			continue
		var saum: float = float(st[4]) * 0.5 + 1.6
		var band := Rect2(Vector2(a - saum, float(st[1])), Vector2(saum * 2.0, float(st[2]) - float(st[1]))) \
			if lz else Rect2(Vector2(float(st[1]), a - saum), Vector2(float(st[2]) - float(st[1]), saum * 2.0))
		if band.intersects(rect):
			return true
	return false


# --- Bauen -----------------------------------------------------------------------------------
static func bauen(parent: Node3D, terrain) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Hafenstadt"
	wurzel.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # statisch
	parent.add_child(wurzel)
	var frei: Array = []
	if CityBuilder.has_lib():
		# Haeuser am Hang (ausserhalb der Stadtflaeche) duerfen nicht auf einer Landstrasse stehen
		var bauplan: Array = []
		for e in plan(frei):
			var lp: Vector2 = e["pos"]
			if lp.length() > R_FLACH and terrain != null \
					and terrain.strasse_abstand(MITTE.x + lp.x, MITTE.z + lp.y) < 20.0:
				continue
			bauplan.append(e)
		CityBuilder.build(wurzel, terrain, MITTE, bauplan, "Freihafen")
		var st_node := CityBuilder.build(wurzel, terrain, insel_welt(),
			[{"typ": "Haus_Freiheitsstatue", "pos": Vector2.ZERO, "yaw": STATUE_YAW,
				"scale": STATUE_MASS}], "Freiheitsstatue")
		# Das Wahrzeichen bleibt weit sichtbar (die Fernstufe der Haeuser endet sonst am
		# Rand der geladenen Chunks; die Insel selbst steht in der Fernschuerze).
		for c in st_node.get_children():
			var mmi := c as MultiMeshInstance3D
			if mmi != null and not String(mmi.name).ends_with("_HD"):
				mmi.visibility_range_end = STATUE_SICHT
	_pflaster(wurzel, terrain)
	_kai(wurzel)
	_schiffe(wurzel)
	_baeume(wurzel, terrain, frei)
	_statue_kollision(wurzel)
	return wurzel


static func _w(l: Vector2, y: float) -> Vector3:
	return Vector3(MITTE.x + l.x, y, MITTE.z + l.y)


# --- Strassen, Kai-Pflaster, Markt (flach auf dem Gelaende) -----------------------------------
static func _pflaster(wurzel: Node3D, terrain) -> void:
	# STRASSEN: Fahrbahn, Bordstein, Gehweg, Kreuzungen (scripts/Stadtstrassen.gd)
	Stadtstrassen.bauen(wurzel, terrain, MITTE, netz(), "Strassen")
	# PLAETZE: ebene Platten UNTER der Strassenhoehe (Stadtstrassen.HUB = 0,35) — die
	# Strassen laufen darueber hinweg (Hauptstrasse ueber den Bahnhofsplatz, die Ost-West-
	# Strassen ueber das Kaipflaster bis zur Kaistrasse).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var tief := STADT_Y + 0.24
	_platte(st, Rect2(APRON_X, -KAI_HALB + 6.0, KAISTR_X + 3.6 - APRON_X, KAI_HALB * 2.0 - 12.0),
		tief, C_APRON)
	# oestlich der Kaistrasse wie bisher knapp unter der Kaimauerkrone
	_platte(st, Rect2(KAISTR_X + 3.6, -KAI_HALB + 6.0, KAI_X + 0.5 - KAISTR_X - 3.6,
		KAI_HALB * 2.0 - 12.0), STADT_Y + 0.38, C_APRON)
	_platte(st, Rect2(76, -114, 108, 105), tief, C_MARKT)
	_platte(st, Rect2(-470, -34, 28, 68), tief, C_MARKT)        # Bahnhofsplatz
	_platte(st, Rect2(-140, -470, 372, 96), STADT_Y + 0.20, Color(0.47, 0.46, 0.45))   # Werkhof
	CityBuilder.karte_strassen.append([Vector2(MITTE.x + 272.0, MITTE.z - KAI_HALB),
		Vector2(MITTE.x + 272.0, MITTE.z + KAI_HALB), 80.0])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Pflaster"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mi)


static func _platte(st: SurfaceTool, r: Rect2, y: float, col: Color) -> void:
	var a := _w(r.position, y)
	var b := _w(Vector2(r.end.x, r.position.y), y)
	var c := _w(r.end, y)
	var d := _w(Vector2(r.position.x, r.end.y), y)
	_viereck(st, a, b, c, d, col, Vector3.UP)


# --- Netzhelfer: Flaechen werden nach AUSSEN gewickelt (nie von Hand) --------------------------
static func _dreieck(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color,
		aussen: Vector3) -> void:
	# Godot: Vorderseite = im Uhrzeigersinn; die Normale dazu ist (c - a) x (b - a).
	st.set_color(col)
	if (c - a).cross(b - a).dot(aussen) < 0.0:
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	else:
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)


static func _viereck(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		col: Color, aussen: Vector3) -> void:
	_dreieck(st, a, b, c, col, aussen)
	_dreieck(st, a, c, d, col, aussen)


## Quader: mitte (Welt), groesse, um die Hochachse gedreht. `unten` = Boden mitzeichnen.
static func _quader(st: SurfaceTool, mitte: Vector3, gr: Vector3, col: Color, yaw := 0.0,
		oben_col: Variant = null) -> void:
	var b := Basis(Vector3.UP, yaw)
	var e: Array[Vector3] = []
	for sy in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			for sx in [-0.5, 0.5]:
				e.append(mitte + b * Vector3(sx * gr.x, sy * gr.y, sz * gr.z))
	var oc: Color = col if oben_col == null else oben_col
	_viereck(st, e[4], e[5], e[7], e[6], oc, Vector3.UP)
	_viereck(st, e[0], e[1], e[5], e[4], col, b * Vector3(0, 0, -1))
	_viereck(st, e[2], e[3], e[7], e[6], col, b * Vector3(0, 0, 1))
	_viereck(st, e[0], e[2], e[6], e[4], col, b * Vector3(-1, 0, 0))
	_viereck(st, e[1], e[3], e[7], e[5], col, b * Vector3(1, 0, 0))


## Damm mit Boeschung (Mole): von a nach b (lokal), oben `bo` breit auf y_o, unten `bu` auf y_u.
static func _damm(st: SurfaceTool, a: Vector2, b: Vector2, bo: float, bu: float, y_o: float,
		y_u: float, c_oben: Color, c_seite: Color) -> void:
	var d := (b - a).normalized()
	var q := Vector2(-d.y, d.x)
	var a0 := a - d * (bu - bo) * 0.5
	var b0 := b + d * (bu - bo) * 0.5
	var ol := [_w(a - q * bo * 0.5, y_o), _w(b - q * bo * 0.5, y_o)]
	var or_ := [_w(a + q * bo * 0.5, y_o), _w(b + q * bo * 0.5, y_o)]
	var ul := [_w(a0 - q * bu * 0.5, y_u), _w(b0 - q * bu * 0.5, y_u)]
	var ur := [_w(a0 + q * bu * 0.5, y_u), _w(b0 + q * bu * 0.5, y_u)]
	var q3 := Vector3(q.x, 0.3, q.y)
	var d3 := Vector3(d.x, 0.3, d.y)
	_viereck(st, ol[0], ol[1], or_[1], or_[0], c_oben, Vector3.UP)
	_viereck(st, ol[0], ol[1], ul[1], ul[0], c_seite, -q3 + Vector3(0, 0.6, 0))
	_viereck(st, or_[0], or_[1], ur[1], ur[0], c_seite, q3)
	_viereck(st, ol[0], or_[0], ur[0], ul[0], c_seite, -d3 + Vector3(0, 0.6, 0))
	_viereck(st, ol[1], or_[1], ur[1], ul[1], c_seite, d3)


static func _haus_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/haus.gdshader")
	m.set_shader_parameter("haus_farbe", Color(1, 1, 1))
	m.set_shader_parameter("rauheit", 0.9)
	m.set_shader_parameter("metall", 0.0)
	return m


## Farbe fuer den Haus-Shader: der multipliziert die Vertexfarbe ROH (linear) mit der
## Materialfarbe, also hier von sRGB nach linear wandeln.
static func _f(c: Color) -> Color:
	return c.srgb_to_linear()


static func _kasten(body: StaticBody3D, mitte: Vector3, gr: Vector3, yaw := 0.0) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = gr
	cs.shape = bs
	cs.position = mitte
	cs.rotation.y = yaw
	body.add_child(cs)


# --- Kaimauer, Piers, Molen, Container ---------------------------------------------------------
## Piers: [z, Laenge, Breite, hoelzern?]
const PIERS := [[-170.0, 170.0, 16.0, false], [-40.0, 210.0, 18.0, false],
	[150.0, 120.0, 7.0, true], [250.0, 140.0, 7.0, true], [350.0, 110.0, 7.0, true]]
## Molen: Punktzuege (lokal), der letzte Punkt traegt das Leuchtfeuer.
const MOLE_SUED := [Vector2(306, 452), Vector2(520, 470), Vector2(680, 400), Vector2(740, 290)]
const MOLE_NORD := [Vector2(306, -456), Vector2(500, -476), Vector2(640, -430)]


static func _kai(wurzel: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var body := StaticBody3D.new()
	body.name = "KaiKollision"
	wurzel.add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x4A1
	var oben := STADT_Y + 0.42
	var grund := TerrainWorld.SEA_Y - 9.0
	var kante := KAI_X + KAI_VOR
	# Kaimauer: vom Gelaendeanschluss bis zur Kante, bis unter den Hafengrund
	var km := _w(Vector2((KAI_X - 2.0 + kante) * 0.5, 0.0), (oben + grund) * 0.5)
	var kg := Vector3(kante - KAI_X + 2.0, oben - grund, KAI_HALB * 2.0)
	_quader(st, km, kg, _f(C_KAI), 0.0, _f(C_APRON))
	_kasten(body, km, kg)
	# Kantenstein und Poller
	_quader(st, _w(Vector2(kante - 0.8, 0.0), oben + 0.18), Vector3(1.6, 0.36, KAI_HALB * 2.0),
		_f(C_KAI_KANTE))
	var z := -KAI_HALB + 12.0
	while z < KAI_HALB - 8.0:
		_quader(st, _w(Vector2(kante - 2.6, z), oben + 0.45), Vector3(0.7, 0.9, 0.7),
			_f(Color(0.16, 0.16, 0.18)))
		z += 24.0
	# Laternen an der Promenade, Marktstaende am Fischerkai
	z = -120.0
	while z < KAI_HALB - 10.0:
		_quader(st, _w(Vector2(253.0, z), oben + 2.6), Vector3(0.24, 5.2, 0.24),
			_f(Color(0.14, 0.15, 0.17)))
		_quader(st, _w(Vector2(253.0, z), oben + 5.4), Vector3(0.9, 0.5, 0.9),
			_f(Color(0.98, 0.92, 0.70)))
		z += 31.0
	var planen := [Color(0.78, 0.26, 0.20), Color(0.92, 0.90, 0.84), Color(0.22, 0.42, 0.62),
		Color(0.90, 0.70, 0.24)]
	for i in 14:
		var sp := Vector2(278.0 + (4.5 if i % 2 == 0 else -1.5), 176.0 + float(i) * 17.0)
		if absf(sp.y - 250.0) < 9.0 or absf(sp.y - 350.0) < 9.0:
			continue                                        # Zugang zu den Stegen frei lassen
		_quader(st, _w(sp, oben + 0.55), Vector3(3.4, 1.1, 2.2), _f(C_HOLZ))
		_quader(st, _w(sp, oben + 2.75), Vector3(4.6, 0.3, 3.4), _f(planen[i % planen.size()]))
		for ex in [-1.0, 1.0]:
			for ez in [-1.0, 1.0]:
				_quader(st, _w(sp + Vector2(ex * 2.0, ez * 1.4), oben + 1.3),
					Vector3(0.14, 2.6, 0.14), _f(C_HOLZ.darkened(0.3)))
	# Kranbahn am Frachtkai (zwei Schienen)
	for sx in [282.0, 302.0]:
		_quader(st, _w(Vector2(sx, -305.0), oben + 0.06), Vector3(0.5, 0.12, 300.0),
			_f(Color(0.30, 0.30, 0.32)))
	# Piers
	for p in PIERS:
		var pz: float = p[0]
		var pl: float = p[1]
		var pb: float = p[2]
		if p[3]:
			# Holzsteg: niedrig, auf Pfaehlen
			var sy := TerrainWorld.SEA_Y + 1.7
			var sm := _w(Vector2(kante + pl * 0.5, pz), sy)
			_quader(st, sm, Vector3(pl, 0.5, pb), _f(C_HOLZ), 0.0, _f(C_HOLZ.lightened(0.14)))
			_kasten(body, sm, Vector3(pl, 0.5, pb))
			var x := kante + 6.0
			while x < kante + pl:
				for s in [-1.0, 1.0]:
					_quader(st, _w(Vector2(x, pz + s * (pb * 0.5 - 0.5)), sy - 3.2),
						Vector3(0.6, 7.4, 0.6), _f(C_HOLZ.darkened(0.25)))
				x += 12.0
			# Treppe vom Kai hinunter
			_quader(st, _w(Vector2(kante + 1.5, pz), (oben + sy) * 0.5), Vector3(3.0, oben - sy, pb),
				_f(C_KAI))
		else:
			var pm := _w(Vector2(kante + pl * 0.5 - 1.0, pz), (oben + grund) * 0.5)
			var pg := Vector3(pl + 2.0, oben - grund, pb)
			_quader(st, pm, pg, _f(C_KAI), 0.0, _f(C_APRON))
			_kasten(body, pm, pg)
			for s in [-1.0, 1.0]:
				_quader(st, _w(Vector2(kante + pl * 0.5, pz + s * (pb * 0.5 - 0.5)), oben + 0.16),
					Vector3(pl, 0.32, 1.0), _f(C_KAI_KANTE))
			var x := kante + 14.0
			while x < kante + pl - 4.0:
				for s in [-1.0, 1.0]:
					_quader(st, _w(Vector2(x, pz + s * (pb * 0.5 - 1.6)), oben + 0.45),
						Vector3(0.7, 0.9, 0.7), _f(Color(0.16, 0.16, 0.18)))
				x += 22.0
	# Molen mit Leuchtfeuer am Kopf
	var feuer := [[MOLE_SUED, Color(0.80, 0.20, 0.16)], [MOLE_NORD, Color(0.16, 0.56, 0.34)]]
	for mf in feuer:
		var zug: Array = mf[0]
		for i in zug.size() - 1:
			var a: Vector2 = zug[i]
			var b: Vector2 = zug[i + 1]
			_damm(st, a, b, 9.0, 30.0, oben, grund, _f(C_KAI), _f(C_FELS))
			var d := b - a
			_kasten(body, _w((a + b) * 0.5, (oben + grund) * 0.5),
				Vector3(d.length() + 9.0, oben - grund, 13.0), -atan2(d.y, d.x))
		var kopf: Vector2 = zug[zug.size() - 1]
		_leuchtfeuer(st, kopf, oben, mf[1])
		_kasten(body, _w(kopf, oben + 7.0), Vector3(4.0, 14.0, 4.0))
	# Containerlager auf dem Frachtkai
	var farben := [Color(0.72, 0.26, 0.20), Color(0.20, 0.38, 0.62), Color(0.86, 0.66, 0.20),
		Color(0.24, 0.50, 0.36), Color(0.80, 0.78, 0.74), Color(0.52, 0.30, 0.22)]
	for reihe in 3:
		var cx := 243.0 + float(reihe) * 9.5
		var cz := -446.0
		while cz < -188.0:
			var hoch := rng.randi_range(0, 3)
			for k in hoch:
				_quader(st, _w(Vector2(cx, cz), oben + 1.3 + float(k) * 2.6),
					Vector3(2.5, 2.6, 12.2), _f(farben[rng.randi() % farben.size()]))
			if hoch > 0:
				_kasten(body, _w(Vector2(cx, cz), oben + float(hoch) * 1.3),
					Vector3(2.5, float(hoch) * 2.6, 12.2))
			cz += 13.4
	# STATUENINSEL: gepflasterter Uferweg auf einer Ringmauer (verdeckt die Boeschung der
	# Flachzone, die als Saegezahn aus Strandfarbe im Wasser stand) und der Anleger zur Stadt.
	var ins := Vector2(INSEL.x, INSEL.y)
	var iy := INSEL_Y + 0.3
	_ringmauer(st, ins, INSEL_R - 2.0, INSEL_UFER, iy, grund, 40, _f(C_APRON), _f(C_KAI))
	_ringmauer(st, ins, INSEL_UFER - 1.4, INSEL_UFER, iy + 0.5, iy, 40, _f(C_KAI_KANTE),
		_f(C_KAI_KANTE))
	var ufer := CollisionShape3D.new()
	var uz := CylinderShape3D.new()
	uz.radius = INSEL_UFER
	uz.height = iy - grund
	ufer.shape = uz
	ufer.position = _w(ins, (iy + grund) * 0.5)
	body.add_child(ufer)
	var am := _w(ins + Vector2(-(INSEL_UFER + 29.0), 0.0), (iy + grund) * 0.5)
	var ag := Vector3(62.0, iy - grund, 10.0)
	_quader(st, am, ag, _f(C_KAI), 0.0, _f(C_APRON))
	_kasten(body, am, ag)
	# Fabrikhof im Norden und Marktstaende auf dem Markt
	for i in 10:
		var sp := Vector2(118.0 + float(i % 5) * 9.5, -44.0 + (12.0 if i >= 5 else 0.0))
		_quader(st, _w(sp, STADT_Y + 0.95), Vector3(3.4, 1.1, 2.2), _f(C_HOLZ))
		_quader(st, _w(sp, STADT_Y + 3.1), Vector3(4.6, 0.3, 3.4), _f(planen[(i * 3) % planen.size()]))
		for ex in [-1.0, 1.0]:
			for ez in [-1.0, 1.0]:
				_quader(st, _w(sp + Vector2(ex * 2.0, ez * 1.4), STADT_Y + 1.7),
					Vector3(0.14, 2.6, 0.14), _f(C_HOLZ.darkened(0.3)))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Kai"
	mi.mesh = st.commit()
	mi.material_override = _haus_material()
	mi.visibility_range_end = 7000.0     # Molen und Kai gehoeren zur Kuestenlinie
	mi.visibility_range_end_margin = 400.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	wurzel.add_child(mi)


## Ring mit ebener Deckflaeche (r_in..r_aus auf y_o) und senkrechter Aussenwand bis y_u.
static func _ringmauer(st: SurfaceTool, l: Vector2, r_in: float, r_aus: float, y_o: float,
		y_u: float, n: int, c_oben: Color, c_wand: Color) -> void:
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var u0 := Vector2(cos(a0), sin(a0))
		var u1 := Vector2(cos(a1), sin(a1))
		_viereck(st, _w(l + u0 * r_in, y_o), _w(l + u1 * r_in, y_o), _w(l + u1 * r_aus, y_o),
			_w(l + u0 * r_aus, y_o), c_oben, Vector3.UP)
		_viereck(st, _w(l + u0 * r_aus, y_o), _w(l + u1 * r_aus, y_o), _w(l + u1 * r_aus, y_u),
			_w(l + u0 * r_aus, y_u), c_wand, Vector3(u0.x + u1.x, 0.0, u0.y + u1.y))


## Kleines Leuchtfeuer auf dem Molenkopf: Sockel, geringelter Turm, Laterne.
static func _leuchtfeuer(st: SurfaceTool, l: Vector2, y: float, farbe: Color) -> void:
	_zylinder(st, _w(l, y), 7.5, 7.5, 1.4, 10, _f(C_KAI_KANTE))
	var weiss := Color(0.93, 0.93, 0.90)
	var hy := y + 1.4
	for k in 4:
		var r0 := lerpf(2.2, 1.4, float(k) / 4.0)
		var r1 := lerpf(2.2, 1.4, float(k + 1) / 4.0)
		_zylinder(st, _w(l, hy), r0, r1, 2.6, 10, _f(farbe if k % 2 == 0 else weiss))
		hy += 2.6
	_zylinder(st, _w(l, hy), 2.0, 2.0, 0.4, 10, _f(Color(0.18, 0.18, 0.20)))
	_zylinder(st, _w(l, hy + 0.4), 1.1, 1.1, 1.5, 8, _f(Color(1.0, 0.92, 0.60)))
	_zylinder(st, _w(l, hy + 1.9), 1.5, 0.1, 1.2, 8, _f(farbe))


static func _zylinder(st: SurfaceTool, fuss: Vector3, r0: float, r1: float, h: float, n: int,
		col: Color) -> void:
	var kopf := fuss + Vector3(0, h, 0)
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var u0 := Vector3(cos(a0), 0, sin(a0))
		var u1 := Vector3(cos(a1), 0, sin(a1))
		_viereck(st, fuss + u0 * r0, fuss + u1 * r0, kopf + u1 * r1, kopf + u0 * r1, col,
			u0 + u1)
		_dreieck(st, kopf + u0 * r1, kopf + u1 * r1, kopf, col, Vector3.UP)


# --- Schiffe -----------------------------------------------------------------------------------
## Rumpf mit spitzem Bug: Deckumriss als Sechseck, Bordwand leicht eingezogen. Bug zeigt nach
## lokal -z (wie Landmarks.build_ship), `kurs` dreht um die Hochachse.
static func _rumpf(st: SurfaceTool, l: Vector2, kurs: float, lang: float, breit: float,
		bord: float, c_rumpf: Color, c_deck: Color) -> Transform3D:
	var xf := Transform3D(Basis(Vector3.UP, kurs), _w(l, TerrainWorld.SEA_Y))
	var hb := breit * 0.5
	var hl := lang * 0.5
	var umriss := [Vector2(0, -hl), Vector2(hb, -hl * 0.55), Vector2(hb, hl * 0.82),
		Vector2(hb * 0.72, hl), Vector2(-hb * 0.72, hl), Vector2(-hb, hl * 0.82),
		Vector2(-hb, -hl * 0.55)]
	var n := umriss.size()
	var mitte_o := xf * Vector3(0, bord, 0)
	for i in n:
		var p0: Vector2 = umriss[i]
		var p1: Vector2 = umriss[(i + 1) % n]
		var o0 := xf * Vector3(p0.x, bord, p0.y)
		var o1 := xf * Vector3(p1.x, bord, p1.y)
		var u0 := xf * Vector3(p0.x * 0.82, -1.2, p0.y * 0.94)
		var u1 := xf * Vector3(p1.x * 0.82, -1.2, p1.y * 0.94)
		var aus := xf.basis * Vector3(p0.x + p1.x, 0.0, p0.y + p1.y)
		_viereck(st, o0, o1, u1, u0, c_rumpf, aus)
		_dreieck(st, o0, o1, mitte_o, c_deck, Vector3.UP)
	return xf


static func _aufbau(st: SurfaceTool, xf: Transform3D, mitte: Vector3, gr: Vector3,
		col: Color) -> void:
	_quader(st, xf * mitte, gr, col, atan2(xf.basis.z.x, xf.basis.z.z))


static func _segel(st: SurfaceTool, xf: Transform3D, mast_z: float, hoch: float, baum: float,
		col: Color) -> void:
	var fuss := xf * Vector3(0, 1.4, mast_z)
	var top := xf * Vector3(0, 1.4 + hoch, mast_z)
	var nock := xf * Vector3(0.6, 1.9, mast_z + baum)
	var bug := xf * Vector3(0, 1.5, mast_z - baum * 0.8)
	for aus in [xf.basis.x, -xf.basis.x]:
		_dreieck(st, fuss, top, nock, col, aus)
		_dreieck(st, fuss, top, bug, col.darkened(0.06), aus)
	_quader(st, (fuss + top) * 0.5, Vector3(0.22, hoch, 0.22), _f(C_HOLZ), 0.0)


static func _schiffe(wurzel: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5C1FF
	var kante := KAI_X + KAI_VOR
	var weiss := _f(Color(0.93, 0.93, 0.90))
	var farben := [Color(0.72, 0.26, 0.20), Color(0.20, 0.38, 0.62), Color(0.86, 0.66, 0.20),
		Color(0.24, 0.50, 0.36), Color(0.80, 0.78, 0.74)]
	# FRACHTER am Frachtkai (laengs der Kaimauer, Bug nach Sueden) mit Containern an Deck
	var f1 := _rumpf(st, Vector2(kante + 11.0, -300.0), PI, 118.0, 17.0, 5.2,
		_f(Color(0.16, 0.18, 0.22)), _f(Color(0.45, 0.24, 0.20)))
	_aufbau(st, f1, Vector3(0, 9.0, 44.0), Vector3(14.0, 8.0, 12.0), weiss)
	_aufbau(st, f1, Vector3(0, 14.4, 45.0), Vector3(9.0, 3.0, 7.0), weiss)
	_aufbau(st, f1, Vector3(0, 17.5, 49.0), Vector3(3.2, 4.6, 3.2), _f(Color(0.75, 0.22, 0.16)))
	for reihe in 6:
		for spalte in 3:
			var hoch := rng.randi_range(1, 3)
			for k in hoch:
				_aufbau(st, f1, Vector3(-5.2 + float(spalte) * 5.2, 6.5 + float(k) * 2.6,
					-40.0 + float(reihe) * 13.0), Vector3(2.5, 2.6, 12.2),
					_f(farben[rng.randi() % farben.size()]))
	# Zweiter Frachter am Nordpier
	var f2 := _rumpf(st, Vector2(kante + 92.0, -187.0), -PI * 0.5, 96.0, 15.0, 4.6,
		_f(Color(0.42, 0.14, 0.12)), _f(Color(0.36, 0.38, 0.40)))
	_aufbau(st, f2, Vector3(0, 8.0, 34.0), Vector3(12.0, 7.0, 11.0), weiss)
	_aufbau(st, f2, Vector3(0, 14.0, 37.0), Vector3(3.0, 5.0, 3.0), _f(Color(0.16, 0.18, 0.22)))
	for k in 4:
		_aufbau(st, f2, Vector3(0, 5.3, -30.0 + float(k) * 13.0), Vector3(10.0, 1.4, 10.5),
			_f(Color(0.30, 0.32, 0.34)))
	# DAMPFER (weiss, zwei Schornsteine) am Mittelpier
	var d1 := _rumpf(st, Vector2(kante + 110.0, -57.0), -PI * 0.5, 84.0, 13.0, 4.0, weiss,
		_f(Color(0.62, 0.50, 0.36)))
	_aufbau(st, d1, Vector3(0, 6.2, 4.0), Vector3(10.0, 4.4, 50.0), weiss)
	_aufbau(st, d1, Vector3(0, 9.6, 2.0), Vector3(8.0, 2.4, 34.0), weiss)
	for sz in [-8.0, 8.0]:
		_aufbau(st, d1, Vector3(0, 13.4, sz), Vector3(3.0, 5.4, 3.6), _f(Color(0.80, 0.42, 0.14)))
		_aufbau(st, d1, Vector3(0, 16.5, sz), Vector3(3.1, 0.9, 3.7), _f(Color(0.12, 0.12, 0.14)))
	# Schlepper
	var s1 := _rumpf(st, Vector2(kante + 160.0, -14.0), -1.9, 24.0, 7.5, 2.4,
		_f(Color(0.14, 0.15, 0.18)), _f(Color(0.50, 0.26, 0.20)))
	_aufbau(st, s1, Vector3(0, 4.2, 1.0), Vector3(5.0, 3.6, 8.0), _f(Color(0.86, 0.66, 0.20)))
	_aufbau(st, s1, Vector3(0, 7.2, 3.0), Vector3(1.6, 3.0, 1.6), _f(Color(0.12, 0.12, 0.14)))
	# FISCHKUTTER an den Holzstegen
	var kutter := [Color(0.20, 0.38, 0.62), Color(0.72, 0.26, 0.20), Color(0.24, 0.50, 0.36),
		Color(0.90, 0.88, 0.80), Color(0.86, 0.66, 0.20)]
	for p in PIERS:
		if not p[3]:
			continue
		var x := kante + 22.0
		var i := 0
		while x < kante + float(p[1]) - 6.0:
			var seite := 1.0 if i % 2 == 0 else -1.0
			if rng.randf() < 0.8:
				var k := _rumpf(st, Vector2(x, float(p[0]) + seite * (float(p[2]) * 0.5 + 3.4)),
					PI * 0.5 + rng.randf_range(-0.08, 0.08), 13.0, 4.4, 1.5,
					_f(kutter[rng.randi() % kutter.size()]), _f(Color(0.60, 0.50, 0.36)))
				_aufbau(st, k, Vector3(0, 2.3, 3.0), Vector3(2.2, 1.7, 2.4), weiss)
				_aufbau(st, k, Vector3(0, 3.3, 3.0), Vector3(2.5, 0.25, 2.8),
					_f(Color(0.30, 0.20, 0.14)))
				_aufbau(st, k, Vector3(0, 4.4, -1.4), Vector3(0.18, 5.8, 0.18), _f(C_HOLZ))
				_aufbau(st, k, Vector3(0, 1.75, -2.6), Vector3(2.0, 0.5, 2.6),
					_f(Color(0.52, 0.46, 0.38)))
			x += 15.0
			i += 1
	# SEGELBOOTE: vor Anker im Becken und unterwegs zur Statue
	var segler := [[Vector2(500, 60), 0.4], [Vector2(540, 200), 2.1], [Vector2(590, 110), -0.7],
		[Vector2(560, 300), 1.2], [Vector2(640, 220), -2.4], [Vector2(500, 395), 0.2],
		[Vector2(820, 120), 1.0], [Vector2(900, -90), -0.6], [Vector2(980, 230), 2.6],
		[Vector2(1180, -40), 0.3], [Vector2(760, -220), -1.3], [Vector2(1130, 210), 1.9]]
	for sg in segler:
		var b := _rumpf(st, sg[0], sg[1], 11.0, 3.4, 1.2, weiss, _f(Color(0.62, 0.50, 0.36)))
		_segel(st, b, -0.6, 12.5, 4.6, _f(Color(0.96, 0.95, 0.90)))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Schiffe"
	mi.mesh = st.commit()
	mi.material_override = _haus_material()
	wurzel.add_child(mi)
	# Ein Dreimaster als Museumsschiff am Altstadtkai (Landmarks), dazu einer vor der Insel
	Landmarks.build_ship(wurzel, Vector2(MITTE.x + kante + 6.0, MITTE.z + 70.0), 0.0)
	Landmarks.build_ship(wurzel, Vector2(MITTE.x + 900.0, MITTE.z + 420.0), 1.1)


# --- Baeume: Promenade, Markt, Stadtpark, Hoefe, Insel ------------------------------------------
static func _baeume(wurzel: Node3D, terrain, frei: Array) -> void:
	if terrain == null:
		return
	var flora: Variant = terrain.get("_flora")
	var mat: Variant = terrain.get("_flora_mat")
	if flora == null or mat == null or not (flora as Dictionary).has("Eiche"):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB4A
	var orte := {"Eiche": [], "Birke": [], "Busch": [], "Kiefer": []}
	# Allee an der Kaipromenade (Altstadt- und Fischerkai) und an der Hauptstrasse
	var z := -110.0
	while z < 440.0:
		(orte["Eiche"] as Array).append(Vector2(APRON_X + 14.0, z))
		z += 22.0
	var x := -440.0
	while x < 60.0:
		var kreuzung := false
		for sx in NS:
			if absf(x - float(sx)) < 12.0:
				kreuzung = true
		if not kreuzung:
			for s in [-1.0, 1.0]:
				# Strassenbaeume auf dem Gehweg des Boulevards
				(orte["Birke"] as Array).append(Vector2(x,
					s * (float(Stadtstrassen.FAHRBAHN[Stadtstrassen.BOULEVARD]) * 0.5 + 1.5)))
		x += 26.0
	# Markt: Baeume an den Ecken und vor der Kirche
	for p in [Vector2(84, -8), Vector2(110, -8), Vector2(84, -106), Vector2(176, -8),
			Vector2(104, -104), Vector2(178, -104)]:
		(orte["Eiche"] as Array).append(p)
	# Stadtpark (Block suedlich der Hauptstrasse): lockerer Hain mit Buschwerk
	for i in 46:
		var p := Vector2(rng.randf_range(-38.0, 58.0), rng.randf_range(14.0, 108.0))
		if p.distance_to(Vector2(12, 62)) < 12.0:
			continue
		var art: String = ["Eiche", "Eiche", "Birke", "Busch", "Kiefer"][rng.randi() % 5]
		(orte[art] as Array).append(p)
	# Hoefe und Gaerten: ueberall in der Stadt, wo weder Haus noch Strasse noch Platz ist
	var liste_str := strassen()
	for i in 900:
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * (sqrt(rng.randf()) * 540.0)
		if p.x > APRON_X - 14.0:
			continue
		var ok := true
		for r in frei:
			if (r as Rect2).grow(2.5).has_point(p):
				ok = false
				break
		if ok:
			for sg in liste_str:
				var saum: float = float(sg[4]) * 0.5 + 2.0
				var quer: float = (p.x if sg[3] else p.y) - float(sg[0])
				var laengs: float = p.y if sg[3] else p.x
				if absf(quer) < saum and laengs > float(sg[1]) - 4.0 and laengs < float(sg[2]) + 4.0:
					ok = false
					break
		if ok:
			var art2: String = ["Eiche", "Birke", "Birke", "Busch", "Eiche"][rng.randi() % 5]
			(orte[art2] as Array).append(p)
	# Statueninsel: ein Kranz Baeume um das Fort
	for i in 14:
		var a := TAU * float(i) / 14.0 + 0.2
		(orte["Eiche" if i % 3 else "Kiefer"] as Array).append(
			INSEL + Vector2(cos(a), sin(a)) * (INSEL_R - 12.0))
	for art in orte:
		var liste: Array = orte[art]
		if liste.is_empty() or not (flora as Dictionary).has(art):
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = (flora as Dictionary)[art]
		mm.instance_count = liste.size()
		for i in liste.size():
			var l: Vector2 = liste[i]
			var wx := MITTE.x + l.x
			var wz := MITTE.z + l.y
			var sc := rng.randf_range(0.8, 1.15) if art != "Busch" else rng.randf_range(0.9, 1.6)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(
				Vector3(sc, sc * rng.randf_range(0.95, 1.15), sc)),
				Vector3(wx, terrain.height_at(wx, wz) - 0.15, wz)))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Stadtbaum_" + String(art)
		mmi.multimesh = mm
		mmi.material_override = mat
		wurzel.add_child(mmi)


# --- Kollision der Statue (die Haeuser selbst haben keine) ---------------------------------------
static func _statue_kollision(wurzel: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "StatueKollision"
	body.position = insel_welt()
	body.rotation.y = STATUE_YAW
	wurzel.add_child(body)
	var m := STATUE_MASS
	# [Radius (0 = Kasten mit halber Kante), Unterkante, Oberkante] in Modellmetern
	for t in [[30.0, -2.0, 8.0, false], [15.0, 8.0, 20.0, true], [10.0, 20.0, 47.0, true],
			[5.6, 47.0, 77.0, false], [2.2, 77.0, 83.0, false]]:
		var cs := CollisionShape3D.new()
		var h: float = (float(t[2]) - float(t[1])) * m
		if t[3]:
			var bs := BoxShape3D.new()
			bs.size = Vector3(float(t[0]) * 2.0 * m, h, float(t[0]) * 2.0 * m)
			cs.shape = bs
		else:
			var zs := CylinderShape3D.new()
			zs.radius = float(t[0]) * m
			zs.height = h
			cs.shape = zs
		cs.position = Vector3(0.0, (float(t[1]) + float(t[2])) * 0.5 * m, 0.0)
		body.add_child(cs)
	# erhobener Arm mit Fackel
	var arm := CollisionShape3D.new()
	var az := CylinderShape3D.new()
	az.radius = 1.8 * m
	az.height = 19.0 * m
	arm.shape = az
	arm.position = Vector3(-4.8 * m, 84.0 * m, 0.6 * m)
	body.add_child(arm)
