## AUSBAU DER FELSENBASIS ADLERHORST (2026-10-02, Nutzer: „baue die Aircraft-Basis in den
## Bergen innen besser und viel detaillierter“).
##
## BEFUND vor dem Ausbau (Bilder aus der Halle, tools/_luftbild.gd): ein rohes, dunkles Fels-
## gewoelbe aus grossen Dreiecksfacetten, ueber dem ganzen Hallenboden verstreute Steinbrocken
## (lasen sich als Krater im Beton), dunkle Mini-Tonnenhallen an den Seiten, Kisten und
## Fahrzeuge als einzelne Quader — und zwischen Bahn und Wand vor allem Leere. Ein Flugplatz
## im Berg liest sich als BAUWERK erst durch das, was gebaut ist: Gewoelberippen mit Licht,
## Haeuser mit erleuchteten Fenstern an den Waenden, Standplaetze mit Geraet.
##
## Alles hier steht in den oertlichen Achsen der Felsenbasis (x quer, y ueber dem Hallen-
## boden, z ab Portal in den Berg) und wird in WENIGE Netze gesammelt: ein festes Netz mit
## Vertexfarben (lit), ein Leuchtnetz (Fenster, Lichtbaender, Warnlampen), Rohre glatt
## schattiert. Schilder sind Label3D. Gemessen mit tools/_gelaende_zeit.gd bzw. Bildern.
class_name Bergbasis
extends RefCounted

# Hallenboden (Oberkante der Bodenplatten in Landmarks._hb_einrichtung: 0,23 + 0,11).
const BODEN := 0.34
# Rippen: ab hier ist die Roehre auf voller Hallenweite (Landmarks._hb_masse, t > 0.2).
const RIPPE_AB := 228.0
const RIPPE_ABSTAND := 24.0
const RIPPE_AUSSEN := -0.6     # Aussenkante der Rippe (negativ = steckt im Fels)
const RIPPE_INNEN := 2.2       # Innenkante, eingerueckt gegen den Sollquerschnitt
const RIPPE_HALB := 1.1        # halbe Rippenbreite laengs
# Hallenhaeuser an beiden Waenden: Front bei |x| = HAUS_X0, Rueckseite bei HAUS_X1.
const HAUS_X0 := 63.2
const HAUS_X1 := 71.0
const STOCK := 3.4

# STANDPLAETZE (in Bauwerksmassen; Main._setup_world stellt dort die Maschinen ab).
# [Vorlage, x, z, Gier in Grad]. Die Flieger stehen mit der Nase zur Wand.
const STAENDE := [
	["spitfire", -30.0, 320.0, 90.0], ["me262", 30.0, 320.0, -90.0],
	["f86", -30.0, 450.0, 90.0], ["mig15", 30.0, 450.0, -90.0],
	["mig21", -30.0, 580.0, 90.0], ["mustang_p51", 30.0, 580.0, -90.0],
	["f86", -46.0, 190.0, 90.0], ["spitfire", 46.0, 190.0, -90.0],
	["mig15", -46.0, 700.0, 90.0], ["me262", 46.0, 830.0, -90.0],
]
# Die Flieger stehen 1,25-fach (Main._setup_world), Spannweite damit 10-12,6 m: Geraet bleibt
# laengs mindestens 7,4 m von der Standmitte weg.
const FLIEGER_MASSSTAB := 1.25
# Standplaetze mit Wartungsgeruest (Index in STAENDE).
const WARTUNG := [8, 9]

const C_BETON := Color(0.40, 0.395, 0.38)
const C_BETON_D := Color(0.24, 0.235, 0.23)
const C_STAHL := Color(0.26, 0.27, 0.29)
const C_GELB := Color(0.78, 0.56, 0.06)
const C_ROT := Color(0.62, 0.10, 0.07)
const C_OLIV := Color(0.24, 0.27, 0.18)
const C_REIFEN := Color(0.06, 0.06, 0.065)
const C_GLAS := Color(0.05, 0.07, 0.09)
const L_WARM := Color(1.0, 0.84, 0.58)
const L_KALT := Color(0.80, 0.90, 1.0)
const L_LED := Color(1.0, 0.93, 0.80)

static var _licht_mat: ShaderMaterial
static var _lauf_mat: ShaderMaterial
static var _blink_mat: ShaderMaterial
static var _font: Font

var node: Node3D
var st: SurfaceTool        # feste Teile, Vertexfarbe
var sl: SurfaceTool        # Leuchtteile
var sw: SurfaceTool        # Lauflicht (Alpha = Lage laengs)
var sb: SurfaceTool        # Blinklichter (Alpha = Phase)
var sa: SurfaceTool        # feste Teile DRAUSSEN vor dem Portal (bleiben in der Sonne)
var sr: SurfaceTool        # Rohre (glatt)
var koll: StaticBody3D
var rng := RandomNumberGenerator.new()
var tueren: Array = []      # [Lage vor der Tuer, Richtung zur Bahn (x)]


static func bauen(basis: Node3D) -> void:
	var b := Bergbasis.new()
	b.node = basis
	b._los()


func _los() -> void:
	rng.seed = 0xAD1E
	st = _neu(-1)
	sl = _neu(-1)
	sw = _neu(-1)
	sb = _neu(-1)
	sa = _neu(-1)
	sr = _neu(0)
	koll = StaticBody3D.new()
	koll.name = "AusbauKollision"
	koll.collision_layer = 1
	koll.collision_mask = 0
	node.add_child(koll)

	_rippen()
	_wandsockel()
	_deckenrohre()
	_hallenhaeuser()
	_leitstand()
	_wartungsplaetze()
	_standgeraet()
	_fahrzeugpark()
	_bodenmarken()
	_schilder()
	_lauflicht()
	_rundumleuchten()
	_wappen()
	_dunst()
	_portalschrift()
	_banner()
	_rollschilder()
	_portalbau()
	_figuren()

	_fertig(st, _fest_mat(), "AusbauFest")
	# Eigenes Netz fuer alles vor dem Portal: Main legt das Innere auf die Kavernen-Ebene
	# (ohne Sonne) — im selben Netz standen Fluegelmauern und Sturz schwarz im Tageslicht.
	_fertig(sa, _fest_mat(), "AusbauAussen")
	_fertig(sr, _fest_mat(), "AusbauRohre")
	_fertig(sl, _leucht_mat(), "AusbauLicht")
	_fertig(sw, _signal_mat(true), "AusbauLauflicht")
	_fertig(sb, _signal_mat(false), "AusbauBlinklicht")


# --- Netze und Materialien ------------------------------------------------------------------
func _neu(glatt: int) -> SurfaceTool:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	s.set_smooth_group(glatt)
	return s


func _fertig(s: SurfaceTool, m: Material, name: String) -> void:
	s.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = s.commit()
	mi.material_override = m
	if m is ShaderMaterial:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)


## Fest: Vertexfarbe als Albedo, BEIDSEITIG — die Teile werden aus vielen Einzelquadern mit
## gemischter Wicklung gebaut; Godot dreht die Normale der Rueckseite selbst, die
## Beleuchtung stimmt also von beiden Seiten.
static func _fest_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.82
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Wie die Schale (Landmarks._hb_mat): eine leise Eigenleuchte, sonst stehen die Teile
	# zwischen den Lichtkegeln schwarz.
	m.emission_enabled = true
	m.emission = Color(0.40, 0.36, 0.30)
	m.emission_energy_multiplier = 0.10
	return m


## Leuchtteile: Farbe aus der Vertexfarbe (sRGB), unbeleuchtet, mit Staerke ueber 1 — damit
## Fenster und Lichtbaender LEUCHTEN und nicht nur hell angestrichen sind.
static func _leucht_mat() -> ShaderMaterial:
	if _licht_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float staerke = 2.2;
void fragment() {
	vec3 c = COLOR.rgb;
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)) * staerke;
}
"""
		_licht_mat = ShaderMaterial.new()
		_licht_mat.shader = sh
	return _licht_mat


## SIGNALLICHTER mit Zeitverhalten, beide unbeleuchtet und mit Staerke weit ueber 1 (sie
## sollen im Lichtglanz gluehen, Schwelle 2,4 — in der Halle 1,15, Main._kavernen_stimmung):
##   lauf = true  LAUFLICHT: ein kurzer Blitz wandert die Bahn entlang IN DEN BERG (Alpha der
##                Vertexfarbe = Lage laengs, z / 1100). Takt 0,55/s, 520 m zwischen zwei
##                Blitzen, also 286 m/s — wie die Anflugblitzer eines echten Platzes.
##   lauf = false BLINKLICHT: Rundumleuchten, Alpha = Phase (jede Leuchte eigener Takt).
static func _signal_mat(lauf: bool) -> ShaderMaterial:
	if lauf and _lauf_mat != null:
		return _lauf_mat
	if not lauf and _blink_mat != null:
		return _blink_mat
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float grund = 0.35;
uniform float staerke = 9.0;
void fragment() {
	vec3 c = COLOR.rgb;
	c = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
#ifdef LAUF
	float k = fract(TIME * 0.55 - COLOR.a * 1100.0 / 520.0);
	float blitz = pow(max(0.0, 1.0 - k * 7.0), 2.0);
#else
	float k = fract(TIME * 0.9 + COLOR.a * 7.0);
	float blitz = smoothstep(0.0, 0.08, k) * (1.0 - smoothstep(0.30, 0.42, k));
#endif
	ALBEDO = c * (grund + staerke * blitz);
}
"""
	if lauf:
		sh.code = sh.code.replace("shader_type spatial;", "shader_type spatial;\n#define LAUF")
	var m := ShaderMaterial.new()
	m.shader = sh
	if lauf:
		_lauf_mat = m
	else:
		_blink_mat = m
	return m


func _phase(c: Color) -> Color:
	return Color(c.r, c.g, c.b, rng.randf())


func _kol(c: Vector3, s: Vector3, gier := 0.0) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	cs.transform = Transform3D(Basis(Vector3.UP, gier), c)
	koll.add_child(cs)


# --- Grundformen ------------------------------------------------------------------------------
## Quader, achsparallel.
func _q(s: SurfaceTool, c: Vector3, g: Vector3, col: Color) -> void:
	Landmarks._box_geo(s, c, g, col)


## Quader in einem eigenen Bezugssystem (Fahrzeuge, gedrehte Teile).
func _ob(s: SurfaceTool, xf: Transform3D, c: Vector3, g: Vector3, col: Color) -> void:
	var h := g * 0.5
	var p: Array[Vector3] = []
	for i in 8:
		p.append(xf * (c + Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y,
			h.z if i & 4 else -h.z)))
	var f := [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
	var ton := [0.86, 0.92, 0.80, 1.05, 0.90, 0.96]
	for k in 6:
		var q: Array = f[k]
		Landmarks._quad(s, p[q[0]], p[q[1]], p[q[2]], p[q[3]], Landmarks._shade(col, ton[k]))


## Zylinder von a nach b (Rohr, Rad, Tank).
func _zyl(s: SurfaceTool, a: Vector3, b: Vector3, r: float, seg: int, col: Color,
		deckel := true) -> void:
	var d := (b - a).normalized()
	var u := d.cross(Vector3.UP)
	if u.length() < 0.1:
		u = d.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := d.cross(u).normalized()
	var ra: Array[Vector3] = []
	var rb: Array[Vector3] = []
	for i in seg:
		var w := TAU * float(i) / float(seg)
		var o := (u * cos(w) + v * sin(w)) * r
		ra.append(a + o)
		rb.append(b + o)
	for i in seg:
		var j := (i + 1) % seg
		Landmarks._quad(s, ra[i], ra[j], rb[j], rb[i], col)
		if deckel:
			Landmarks._tri(s, a, ra[j], ra[i], Landmarks._shade(col, 0.85))
			Landmarks._tri(s, b, rb[i], rb[j], Landmarks._shade(col, 0.85))


func _rad(s: SurfaceTool, xf: Transform3D, c: Vector3, r: float, breite: float) -> void:
	_zyl(s, xf * (c - Vector3(breite * 0.5, 0, 0)), xf * (c + Vector3(breite * 0.5, 0, 0)), r,
		10, C_REIFEN)
	_zyl(s, xf * (c - Vector3(breite * 0.52, 0, 0)), xf * (c + Vector3(breite * 0.52, 0, 0)),
		r * 0.55, 8, Color(0.30, 0.30, 0.32))


# --- Gewoelberippen ---------------------------------------------------------------------------
## Betonrippen quer durch die Halle, alle 24 m, je mit einem LICHTBAND auf der Innenseite des
## Bogens. Sie machen aus der Hoehle ein Bauwerk und geben der Tiefe einen Takt — vorher lief
## die Halle als gleichfoermige Felsroehre ins Dunkel, und man sah ihr nicht an, wie lang sie
## ist. Die Schale ist im Hallenteil dafuer fast glatt (Landmarks: Ausbruch auf 6 %), damit
## die Rippen nicht in Felsbuckeln verschwinden.
func _rippen() -> void:
	var w: float = Landmarks.HB_W_HALLE
	var h: float = Landmarks.HB_H_HALLE
	var aussen := Landmarks._hb_ring(w - RIPPE_AUSSEN, h - RIPPE_AUSSEN)
	var innen := Landmarks._hb_ring(w - RIPPE_INNEN, h - RIPPE_INNEN)
	var band := Landmarks._hb_ring(w - RIPPE_INNEN - 0.04, h - RIPPE_INNEN - 0.04)
	var n := 42   # Waende + Bogen (der Rest des Rings ist der Boden)
	var z := RIPPE_AB
	var k := 0
	while z < Landmarks.HB_LAENGE - 20.0:
		var z0 := z - RIPPE_HALB
		var z1 := z + RIPPE_HALB
		var ton := 0.94 + 0.10 * Landmarks._hb_rau(float(k), 5.0)
		var c := Landmarks._shade(C_BETON, ton)
		for i in n - 1:
			var a0 := Vector3(aussen[i].x, aussen[i].y, z0)
			var a1 := Vector3(aussen[i + 1].x, aussen[i + 1].y, z0)
			var i0 := Vector3(innen[i].x, innen[i].y, z0)
			var i1 := Vector3(innen[i + 1].x, innen[i + 1].y, z0)
			var dz := Vector3(0, 0, z1 - z0)
			Landmarks._quad(st, i0, i1, i1 + dz, i0 + dz, c)
			Landmarks._quad(st, a0, a1, i1, i0, Landmarks._shade(c, 0.86))
			Landmarks._quad(st, a0 + dz, i0 + dz, i1 + dz, a1 + dz, Landmarks._shade(c, 0.86))
			# Lichtband nur im Bogen (nicht an den senkrechten Wangen)
			if i >= 9 and i < 33:
				var b0 := Vector3(band[i].x, band[i].y, z - 0.22)
				var b1 := Vector3(band[i + 1].x, band[i + 1].y, z - 0.22)
				Landmarks._quad(sl, b0, b1, b1 + Vector3(0, 0, 0.44), b0 + Vector3(0, 0, 0.44),
					L_LED)
		# Sockel der Rippe an beiden Waenden
		for sx: float in [-1.0, 1.0]:
			_q(st, Vector3(sx * (w - 1.9), 1.6, z), Vector3(3.4, 3.2, RIPPE_HALB * 2.0 + 0.8),
				C_BETON_D)
		z += RIPPE_ABSTAND
		k += 1


## WANDSOCKEL zwischen den Rippen: dunkle Betonplatten bis 4,2 m mit gelber Kante. Unten
## sieht man an den Waenden sonst nur Fels, und genau dort steht das Auge.
func _wandsockel() -> void:
	var w: float = Landmarks.HB_W_HALLE
	var frei := [420.0, 640.0, 860.0]   # Seitenstollen (Landmarks._hb_betrieb)
	var z := RIPPE_AB
	var nr := 0
	while z + RIPPE_ABSTAND < Landmarks.HB_LAENGE - 20.0:
		nr += 1
		var za := z + RIPPE_HALB + 0.4
		var ze := z + RIPPE_ABSTAND - RIPPE_HALB - 0.4
		var zm := (za + ze) * 0.5
		var gesperrt := false
		for f: float in frei:
			if absf(zm - f) < 14.0:
				gesperrt = true
		if not gesperrt:
			for sx: float in [-1.0, 1.0]:
				var x := sx * (w - 0.8)
				_q(st, Vector3(x, 2.1, zm), Vector3(1.2, 4.2, ze - za), C_BETON_D)
				_q(st, Vector3(x - sx * 0.62, 4.1, zm), Vector3(0.06, 0.22, ze - za), C_GELB)
				# Plattenfugen
				for f2 in 3:
					var fz := lerpf(za, ze, (float(f2) + 1.0) / 4.0)
					_q(st, Vector3(x - sx * 0.61, 2.0, fz), Vector3(0.04, 3.9, 0.08),
						Landmarks._shade(C_BETON_D, 0.6))
				# Abschnittsnummer, wie aufgespritzt
				_schild("A%02d" % nr, Vector3(x - sx * 0.66, 2.2, zm + 5.25), Vector3(-sx, 0, 0),
					0.02, Color(0.95, 0.80, 0.22))
		z += RIPPE_ABSTAND


## LUEFTUNG UNTER DEM SCHEITEL: zwei grosse Rohre die Halle entlang, mit Flanschen und
## Abhaengern — die Decke war sonst eine leere Flaeche ohne Massstab.
func _deckenrohre() -> void:
	var c_rohr := Color(0.36, 0.37, 0.38)
	var c_flansch := Color(0.22, 0.23, 0.24)
	var y := 50.0
	for sx: float in [-1.0, 1.0]:
		var x := 30.0 * sx
		_zyl(sr, Vector3(x, y, RIPPE_AB - 10.0), Vector3(x, y, Landmarks.HB_LAENGE - 24.0), 1.5,
			16, c_rohr)
		var z := RIPPE_AB - 6.0
		while z < Landmarks.HB_LAENGE - 26.0:
			_zyl(st, Vector3(x, y, z - 0.2), Vector3(x, y, z + 0.2), 1.72, 12, c_flansch)
			if int(z) % 12 == 0:
				_q(st, Vector3(x, y + 3.3, z), Vector3(0.14, 3.6, 0.14), c_flansch)
				_q(st, Vector3(x, y + 1.55, z), Vector3(3.6, 0.18, 0.4), c_flansch)
			z += 6.0
		# Auslaesse nach unten
		var z2 := RIPPE_AB + 30.0
		while z2 < Landmarks.HB_LAENGE - 40.0:
			_zyl(sr, Vector3(x, y - 1.2, z2), Vector3(x, y - 3.6, z2), 0.55, 10, c_rohr)
			_zyl(st, Vector3(x, y - 3.6, z2), Vector3(x, y - 3.9, z2), 0.8, 10, c_flansch)
			z2 += 72.0


# --- Hallenhaeuser ----------------------------------------------------------------------------
const HAUS_NAMEN := ["WERKSTATT", "BEREITSCHAFT", "FUNK", "LAGER", "SANITÄT", "KOMMANDO",
	"WETTER", "ELEKTRIK", "KANTINE", "BETANKUNG", "WACHE", "MUNITION", "TECHNIK", "PERSONAL",
	"ERSATZTEILE", "STAFFEL 1", "STAFFEL 2", "STAFFEL 3", "SCHLOSSEREI", "BÜRO"]
const HAUS_FARBEN := [Color(0.50, 0.50, 0.48), Color(0.56, 0.51, 0.42), Color(0.36, 0.40, 0.31),
	Color(0.44, 0.48, 0.52), Color(0.58, 0.56, 0.52)]


## An beiden Waenden eine Zeile aus zwei- und dreigeschossigen Bauten mit erleuchteten
## Fenstern, Tueren, Vordaechern, Laubengaengen und Schildern — die Halle als Ort, an dem
## gearbeitet wird. Die Luecken folgen dem, was dort schon steht (Gittertuerme bei z 240,
## 560, 880; Treppentuerme bei 300 und 720; Seitenstollen bei 420, 640, 860; die Kanzel
## links hinten).
func _hallenhaeuser() -> void:
	var rechts := [[247.0, 293.0], [307.0, 413.0], [426.0, 553.0], [567.0, 633.0],
		[646.0, 713.0], [727.0, 853.0], [887.0, 960.0]]
	var links := [[247.0, 293.0], [307.0, 413.0], [426.0, 553.0], [567.0, 633.0],
		[646.0, 713.0], [727.0, 853.0]]
	var nr := 0
	for seite in 2:
		var sx: float = 1.0 if seite == 0 else -1.0
		var abschnitte: Array = rechts if seite == 0 else links
		for ab: Array in abschnitte:
			var z: float = float(ab[0]) + 2.0
			var ende: float = float(ab[1]) - 2.0
			while ende - z >= 14.0:
				var lang := minf(rng.randf_range(16.0, 30.0), ende - z)
				if ende - z - lang < 14.0:
					lang = ende - z
				_haus(sx, z, z + lang, nr)
				nr += 1
				z += lang + rng.randf_range(3.0, 6.0)


func _haus(sx: float, za: float, ze: float, nr: int) -> void:
	var stock := 3 if rng.randf() < 0.45 else 2
	var hoehe := float(stock) * STOCK + 0.5
	var farbe: Color = HAUS_FARBEN[nr % HAUS_FARBEN.size()]
	var x0 := sx * HAUS_X0
	var x1 := sx * HAUS_X1
	var xm := (x0 + x1) * 0.5
	var tief := HAUS_X1 - HAUS_X0
	var lang := ze - za
	var zm := (za + ze) * 0.5
	var y0 := BODEN
	# Koerper, Sockel, Geschossbaender, Attika
	_q(st, Vector3(xm, y0 + hoehe * 0.5, zm), Vector3(tief, hoehe, lang), farbe)
	_q(st, Vector3(x0 - sx * 0.05, y0 + 0.35, zm), Vector3(0.12, 0.7, lang + 0.1),
		Landmarks._shade(farbe, 0.55))
	for s in range(1, stock):
		_q(st, Vector3(x0 - sx * 0.08, y0 + float(s) * STOCK, zm), Vector3(0.18, 0.3, lang + 0.2),
			Landmarks._shade(farbe, 0.80))
	for e in [[Vector3(x0 - sx * 0.1, 0, 0), Vector3(0.3, 0.7, lang + 0.3)],
			[Vector3(x1 + sx * 0.0, 0, 0), Vector3(0.3, 0.7, lang + 0.3)],
			[Vector3(xm, 0, -lang * 0.5 - 0.0), Vector3(tief + 0.3, 0.7, 0.3)],
			[Vector3(xm, 0, lang * 0.5), Vector3(tief + 0.3, 0.7, 0.3)]]:
		var o: Vector3 = e[0]
		_q(st, Vector3(o.x if o.x != 0.0 else xm, y0 + hoehe + 0.3, zm + o.z), e[1],
			Landmarks._shade(farbe, 0.7))
	_kol(Vector3(xm, y0 + hoehe * 0.5, zm), Vector3(tief, hoehe, lang))
	# Fenster: je Geschoss eine Reihe, alle 3 m. Ein Teil dunkel — ein Bau, in dem jedes
	# Fenster gleich hell ist, liest sich als Lampe und nicht als Haus.
	var tuer_z := za + 2.6 if rng.randf() < 0.5 else ze - 2.6
	var n_fenster := int((lang - 2.0) / 3.0)
	for s in stock:
		var lit_ton := L_WARM if rng.randf() < 0.65 else L_KALT
		for f in n_fenster:
			var fz := za + 1.0 + (float(f) + 0.5) * (lang - 2.0) / float(n_fenster)
			if s == 0 and absf(fz - tuer_z) < 2.0:
				continue
			var fy := y0 + float(s) * STOCK + 1.75
			var fx := x0 - sx * 0.04
			# Rahmen und Fensterbank
			_q(st, Vector3(fx - sx * 0.02, fy, fz), Vector3(0.06, 1.55, 2.05), C_STAHL)
			_q(st, Vector3(fx - sx * 0.16, fy - 0.82, fz), Vector3(0.3, 0.08, 2.2),
				Landmarks._shade(farbe, 0.75))
			if rng.randf() < 0.7:
				Landmarks._box_geo(sl, Vector3(fx - sx * 0.06, fy, fz), Vector3(0.02, 1.35, 1.85),
					Landmarks._shade(lit_ton, 0.80 + 0.25 * rng.randf()))
			else:
				_q(st, Vector3(fx - sx * 0.06, fy, fz), Vector3(0.02, 1.35, 1.85), C_GLAS)
			# Sprosse
			_q(st, Vector3(fx - sx * 0.08, fy, fz), Vector3(0.03, 1.35, 0.07), C_STAHL)
	# Tuer mit Vordach und Lampe
	var ty := y0 + 1.25
	_q(st, Vector3(x0 - sx * 0.06, ty, tuer_z), Vector3(0.1, 2.5, 1.6), Color(0.14, 0.15, 0.16))
	_q(st, Vector3(x0 - sx * 0.09, ty + 0.1, tuer_z), Vector3(0.04, 0.9, 0.06), C_STAHL)
	_q(st, Vector3(x0 - sx * 0.8, y0 + 2.9, tuer_z), Vector3(1.6, 0.14, 2.6), C_STAHL)
	Landmarks._box_geo(sl, Vector3(x0 - sx * 0.12, y0 + 2.7, tuer_z), Vector3(0.12, 0.18, 0.5),
		L_WARM)
	tueren.append([Vector3(x0 - sx * 1.8, y0, tuer_z), -sx])
	# Laubengang mit Treppe (dreigeschossig): Gang vor dem oberen Geschoss, Gelaender,
	# Treppe am Hausende hinauf.
	if stock == 3:
		for s in range(1, stock):
			var gy := y0 + float(s) * STOCK
			_q(st, Vector3(x0 - sx * 0.7, gy - 0.1, zm), Vector3(1.4, 0.2, lang), C_STAHL)
			_q(st, Vector3(x0 - sx * 1.35, gy + 1.0, zm), Vector3(0.07, 0.07, lang), C_STAHL)
			_q(st, Vector3(x0 - sx * 1.35, gy + 0.5, zm), Vector3(0.04, 0.04, lang), C_STAHL)
			var pz := za
			while pz <= ze + 0.01:
				_q(st, Vector3(x0 - sx * 1.35, gy + 0.5, pz), Vector3(0.06, 1.0, 0.06), C_STAHL)
				pz += 1.6
		# Treppe: Laeufe an der Stirnseite des Hauses (z-Ende), zickzack nach oben
		var tz := ze + 1.5
		for s in range(stock - 1):
			var ya := y0 + float(s) * STOCK
			var richt := 1.0 if s % 2 == 0 else -1.0
			var xa := x0 + sx * (0.4 if richt > 0 else tief - 0.4)
			var xe := x0 + sx * (tief - 0.4 if richt > 0 else 0.4)
			var n_st := 12
			for i in n_st:
				var t := (float(i) + 0.5) / float(n_st)
				_q(st, Vector3(lerpf(xa, xe, t), ya + t * STOCK, tz),
					Vector3(tief / float(n_st) * 1.1, 0.12, 1.4), C_STAHL)
			_q(st, Vector3(xm, ya + STOCK * 0.5 + 0.6, tz + 0.75), Vector3(tief, 0.06, 0.06),
				C_STAHL)
		for ex: float in [x0 + sx * 0.2, x1 - sx * 0.2]:
			_q(st, Vector3(ex, y0 + hoehe * 0.5, tz + 0.75), Vector3(0.12, hoehe, 0.12), C_STAHL)
		_kol(Vector3(xm, y0 + hoehe * 0.5, tz), Vector3(tief, hoehe, 1.6))
	# Dach: Klimageraete und Luefter
	for g in 1 + int(lang / 14.0):
		var gz := za + 3.0 + rng.randf() * (lang - 6.0)
		var gx := xm + sx * rng.randf_range(-1.5, 1.5)
		_q(st, Vector3(gx, y0 + hoehe + 0.7, gz), Vector3(2.2, 1.2, 1.6), Color(0.52, 0.53, 0.53))
		_zyl(st, Vector3(gx, y0 + hoehe + 1.32, gz), Vector3(gx, y0 + hoehe + 1.4, gz), 0.55, 10,
			Color(0.18, 0.18, 0.19))
	# Schild ueber der Tuer
	var name: String = HAUS_NAMEN[nr % HAUS_NAMEN.size()]
	var sy := y0 + float(stock) * STOCK - 0.4
	_q(st, Vector3(x0 - sx * 0.06, sy, zm), Vector3(0.08, 0.9, minf(lang - 2.0, 1.0 + 0.62 *
		float(name.length()))), Color(0.08, 0.09, 0.10))
	_schild(name, Vector3(x0 - sx * 0.12, sy, zm), Vector3(-sx, 0, 0), 0.0105, Color(0.98, 0.92, 0.70))
	# Hausnummer an der Ecke
	_schild("%02d" % (nr + 1), Vector3(x0 - sx * 0.1, y0 + 2.2, za + 0.7), Vector3(-sx, 0, 0),
		0.008, Color(0.95, 0.80, 0.20))


## FLUGLEITUNG hinten links: zweigeschossiger Sockel mit Fenstern nach drei Seiten, darauf
## eine auskragende GLASKANZEL mit Pultdach, Antennen und Schild — der Leitstand, von dem
## aus man die ganze Halle hinunter bis zum Portal sieht. Ersetzt den schwarzen Betonkasten
## (Landmarks: "Kanzel"). Hinten bleibt er vor Abzweigkasten (x 72,6) und Luftkanal (y 10,7).
func _leitstand() -> void:
	var xa := -60.0
	var xb := -71.5
	var za := 888.0
	var ze := 916.0
	var xm := (xa + xb) * 0.5
	var zm := (za + ze) * 0.5
	var farbe := Color(0.56, 0.55, 0.52)
	var h := 7.1
	_q(st, Vector3(xm, BODEN + h * 0.5, zm), Vector3(xa - xb, h, ze - za), farbe)
	_q(st, Vector3(xa + 0.06, BODEN + 0.35, zm), Vector3(0.12, 0.7, ze - za), Landmarks._shade(farbe, 0.55))
	_q(st, Vector3(xa + 0.08, BODEN + STOCK, zm), Vector3(0.18, 0.3, ze - za), Landmarks._shade(farbe, 0.8))
	_kol(Vector3(xm, BODEN + h * 0.5, zm), Vector3(xa - xb, h, ze - za))
	# Fenster: Front (zur Bahn, +x) und Stirn zum Portal (-z)
	for s in 2:
		var fy := BODEN + float(s) * STOCK + 1.75
		var fz := za + 2.0
		while fz < ze - 1.5:
			_q(st, Vector3(xa + 0.02, fy, fz), Vector3(0.06, 1.55, 2.05), C_STAHL)
			Landmarks._box_geo(sl, Vector3(xa + 0.06, fy, fz), Vector3(0.02, 1.35, 1.85),
				Landmarks._shade(L_KALT if s == 1 else L_WARM, 0.85 + 0.2 * rng.randf()))
			fz += 3.0
		var fx := xa - 2.0
		while fx > xb + 1.5:
			_q(st, Vector3(fx, fy, za - 0.02), Vector3(2.05, 1.55, 0.06), C_STAHL)
			Landmarks._box_geo(sl, Vector3(fx, fy, za - 0.06), Vector3(1.85, 1.35, 0.02),
				Landmarks._shade(L_WARM, 0.85 + 0.2 * rng.randf()))
			fx -= 3.0
	# Tuer zum Vorfeld
	_q(st, Vector3(xa + 0.06, BODEN + 1.25, zm), Vector3(0.1, 2.5, 2.4), Color(0.14, 0.15, 0.16))
	_q(st, Vector3(xa + 0.9, BODEN + 2.9, zm), Vector3(1.8, 0.14, 3.4), C_STAHL)
	# Kanzel: Boden ragt vor, Glasband rundum, auskragendes Pultdach
	var ky := BODEN + h
	var kxa := xa + 1.2
	var kxb := xb + 1.2
	var kza := za - 1.0
	var kze := ze + 1.0
	_q(st, Vector3((kxa + kxb) * 0.5, ky + 0.2, zm), Vector3(kxa - kxb, 0.4, kze - kza),
		C_BETON_D)
	_q(st, Vector3((kxa + kxb) * 0.5, ky + 0.8, zm), Vector3(kxa - kxb, 0.8, kze - kza),
		Landmarks._shade(farbe, 0.85))
	var gh := 3.0
	var gy := ky + 1.2 + gh * 0.5
	# Glas zur Halle (+x) und zum Portal (-z): leuchtend (Bildschirme, Licht im Raum)
	Landmarks._box_geo(sl, Vector3(kxa - 0.05, gy, zm), Vector3(0.04, gh, kze - kza - 0.4),
		Color(0.55, 0.78, 0.86))
	Landmarks._box_geo(sl, Vector3((kxa + kxb) * 0.5, gy, kza + 0.05), Vector3(kxa - kxb - 0.4, gh, 0.04),
		Color(0.55, 0.78, 0.86))
	Landmarks._box_geo(sl, Vector3((kxa + kxb) * 0.5, gy, kze - 0.05), Vector3(kxa - kxb - 0.4, gh, 0.04),
		Color(0.40, 0.58, 0.66))
	_q(st, Vector3(kxb + 0.1, gy, zm), Vector3(0.2, gh, kze - kza), Landmarks._shade(farbe, 0.8))
	var pz := kza
	while pz <= kze + 0.01:
		_q(st, Vector3(kxa, gy, pz), Vector3(0.18, gh, 0.18), C_STAHL)
		pz += 2.4
	var px2 := kxa
	while px2 >= kxb - 0.01:
		_q(st, Vector3(px2, gy, kza), Vector3(0.18, gh, 0.18), C_STAHL)
		_q(st, Vector3(px2, gy, kze), Vector3(0.18, gh, 0.18), C_STAHL)
		px2 -= 2.4
	var dy := ky + 1.2 + gh + 0.25
	_q(st, Vector3((kxa + kxb) * 0.5 + 0.8, dy, zm), Vector3(kxa - kxb + 2.2, 0.5, kze - kza + 2.0),
		C_STAHL)
	_kol(Vector3((kxa + kxb) * 0.5, ky + 2.4, zm), Vector3(kxa - kxb, 4.8, kze - kza))
	# Antennen und Radarschuessel auf dem Dach
	for a in [[-64.0, 893.0, 4.5], [-63.0, 910.0, 3.2], [-68.0, 902.0, 2.6]]:
		_q(st, Vector3(float(a[0]), dy + float(a[2]) * 0.5, float(a[1])),
			Vector3(0.12, float(a[2]), 0.12), C_STAHL)
		Landmarks._box_geo(sl, Vector3(float(a[0]), dy + float(a[2]) + 0.1, float(a[1])),
			Vector3(0.2, 0.2, 0.2), Color(1.0, 0.15, 0.1))
	_zyl(st, Vector3(-66.5, dy + 1.4, 898.0), Vector3(-65.6, dy + 1.9, 898.0), 0.9, 12, Color(0.8, 0.8, 0.78))
	_q(st, Vector3(-66.8, dy + 0.8, 898.0), Vector3(0.2, 1.4, 0.2), C_STAHL)
	# Schilder
	_q(st, Vector3(kxa + 1.0, dy + 0.7, zm), Vector3(0.1, 1.0, 9.0), Color(0.08, 0.09, 0.10))
	_schild("FLUGLEITUNG", Vector3(kxa + 1.08, dy + 0.7, zm), Vector3(1, 0, 0), 0.0105,
		Color(0.98, 0.92, 0.70))
	_schild("FLUGLEITUNG", Vector3((kxa + kxb) * 0.5, ky + 0.8, kza - 0.12), Vector3(0, 0, -1),
		0.0105, Color(0.98, 0.92, 0.70))
	# Aussentreppe an der Portalseite, zwei Laeufe bis aufs Kanzelgeschoss
	var tz := za - 2.4
	for s in 2:
		var ya := BODEN + float(s) * STOCK
		var richt := 1.0 if s % 2 == 0 else -1.0
		var x0 := xa - 0.6 if richt > 0 else xb + 2.0
		var x1 := xb + 2.0 if richt > 0 else xa - 0.6
		for i in 12:
			var t := (float(i) + 0.5) / 12.0
			_q(st, Vector3(lerpf(x0, x1, t), ya + t * STOCK, tz), Vector3(0.9, 0.12, 1.4), C_STAHL)
		_q(st, Vector3((x0 + x1) * 0.5, ya + STOCK * 0.5 + 0.6, tz - 0.75),
			Vector3(absf(x1 - x0), 0.06, 0.06), C_STAHL)
	_kol(Vector3(xm, BODEN + STOCK, tz), Vector3(xa - xb, STOCK * 2.0, 1.6))
	var l := OmniLight3D.new()
	l.position = Vector3(kxa + 4.0, ky + 3.0, zm)
	l.light_color = Color(0.70, 0.86, 1.0)
	l.light_energy = 1.6
	l.omni_range = 16.0
	l.shadow_enabled = false
	node.add_child(l)


# --- Wartungsplaetze --------------------------------------------------------------------------
## Stahlgeruest ueber zwei Standplaetzen: vier Stuetzen, Dachtraeger, Lichtbalken, Hebezeug,
## Arbeitsbuehne an der Nase und gelber Rahmen am Boden.
func _wartungsplaetze() -> void:
	for wi: int in WARTUNG:
		var s: Array = STAENDE[wi]
		var px: float = s[1]
		var pz: float = s[2]
		var sx := signf(px)
		var bx := 13.0      # halbe Ausdehnung quer
		var bz := 12.0      # halbe Ausdehnung laengs
		var h := 13.0
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				var p := Vector3(px + cx * bx, BODEN + h * 0.5, pz + cz * bz)
				_q(st, p, Vector3(0.55, h, 0.55), C_GELB)
				_q(st, Vector3(p.x, BODEN + 0.3, p.z), Vector3(1.0, 0.6, 1.0), C_BETON_D)
				_kol(p, Vector3(0.6, h, 0.6))
		# Laengs- und Quertraeger
		for cx: float in [-1.0, 1.0]:
			_q(st, Vector3(px + cx * bx, BODEN + h + 0.4, pz), Vector3(0.6, 0.9, bz * 2.0 + 0.6),
				C_GELB)
		var qz := -bz
		while qz <= bz + 0.01:
			_q(st, Vector3(px, BODEN + h + 0.4, pz + qz), Vector3(bx * 2.0 + 0.6, 0.7, 0.4),
				Landmarks._shade(C_GELB, 0.85))
			# Lichtbalken unter jedem zweiten Quertraeger
			if absf(qz) < bz - 1.0:
				_q(st, Vector3(px, BODEN + h - 0.4, pz + qz), Vector3(bx * 1.4, 0.25, 0.5), C_STAHL)
				Landmarks._box_geo(sl, Vector3(px, BODEN + h - 0.55, pz + qz),
					Vector3(bx * 1.3, 0.06, 0.35), L_KALT)
			qz += 4.0
		# Hebezeug (Laufkatze mit Haken)
		_q(st, Vector3(px - sx * 3.0, BODEN + h - 0.3, pz + 2.0), Vector3(1.4, 1.0, 1.6), C_ROT)
		_q(st, Vector3(px - sx * 3.0, BODEN + h - 4.0, pz + 2.0), Vector3(0.05, 6.6, 0.05),
			C_STAHL)
		_q(st, Vector3(px - sx * 3.0, BODEN + h - 7.4, pz + 2.0), Vector3(0.5, 0.4, 0.3),
			C_GELB)
		# Arbeitsbuehne an der Nase (Nase zeigt zur Wand)
		var nx := px + sx * 8.6
		for i in 7:
			var t := float(i) / 6.0
			_q(st, Vector3(nx + sx * (2.4 - t * 2.4), BODEN + 0.3 + t * 2.4, pz),
				Vector3(0.45, 0.12, 2.0), C_GELB)
		_q(st, Vector3(nx, BODEN + 2.7, pz), Vector3(1.6, 0.14, 2.2), C_GELB)
		for gz: float in [-1.05, 1.05]:
			_q(st, Vector3(nx, BODEN + 3.25, pz + gz), Vector3(1.6, 0.06, 0.06), C_STAHL)
			_q(st, Vector3(nx + sx * 1.2, BODEN + 1.5, pz + gz), Vector3(0.08, 3.0, 0.08), C_STAHL)
		# Gelber Rahmen am Boden und Lichter
		for e in [[Vector3(0, 0, -bz + 1.0), Vector3(bx * 2.0 - 2.0, 0.02, 0.3)],
				[Vector3(0, 0, bz - 1.0), Vector3(bx * 2.0 - 2.0, 0.02, 0.3)],
				[Vector3(-bx + 1.0, 0, 0), Vector3(0.3, 0.02, bz * 2.0 - 2.0)],
				[Vector3(bx - 1.0, 0, 0), Vector3(0.3, 0.02, bz * 2.0 - 2.0)]]:
			var o: Vector3 = e[0]
			_q(st, Vector3(px + o.x, BODEN + 0.02, pz + o.z), e[1], C_GELB)
		for lz: float in [-6.0, 6.0]:
			var l := OmniLight3D.new()
			l.position = Vector3(px, BODEN + h - 1.5, pz + lz)
			l.light_color = Color(0.92, 0.96, 1.0)
			l.light_energy = 2.4
			l.omni_range = 19.0
			l.shadow_enabled = false
			node.add_child(l)
		# Werkzeugwagen an den Ecken
		_werkzeugwagen(Transform3D(Basis(), Vector3(px - sx * 9.0, BODEN, pz - 9.0)))
		_werkzeugwagen(Transform3D(Basis(Vector3.UP, 1.2), Vector3(px + sx * 4.0, BODEN, pz + 9.5)))


# --- Geraet an den Standplaetzen --------------------------------------------------------------
func _standgeraet() -> void:
	for i in STAENDE.size():
		var s: Array = STAENDE[i]
		var px: float = s[1]
		var pz: float = s[2]
		var sx := signf(px)
		var bahnseitig := -sx
		# Stromaggregat vor dem linken Fluegel, Kabel zum Rumpf
		_aggregat(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(px, BODEN, pz - 8.6)))
		for k in 6:
			var t := float(k) / 5.0
			_q(st, Vector3(px, BODEN + 0.05, lerpf(pz - 7.2, pz - 2.0, t)),
				Vector3(0.09, 0.08, 1.0), Color(0.05, 0.05, 0.05))
		# Feuerloescher und Leiter auf der Wandseite, ausserhalb der Spannweite
		_loescher(Transform3D(Basis(), Vector3(px - bahnseitig * 4.5, BODEN, pz + 8.0)))
		_leiter(Transform3D(Basis(Vector3.UP, -sx * PI * 0.5), Vector3(px - bahnseitig * 2.0,
			BODEN, pz + 7.6)))
		# Bremskloetze
		for kz: float in [-1.3, 1.3]:
			_q(st, Vector3(px - bahnseitig * 1.0, BODEN + 0.15, pz + kz), Vector3(0.5, 0.3, 0.25),
				C_GELB)
		# Schlepper an jedem zweiten Stand, Tankwagen an zwei, Munition an zwei — immer neben
		# den Fluegelspitzen und diesseits der Bahnschulter (|x| >= 24)
		if i % 2 == 0:
			_schlepper(Transform3D(Basis(), Vector3(px + bahnseitig * 3.5, BODEN, pz + 9.6)))
		if i == 2 or i == 5:
			_tankwagen(Transform3D(Basis(Vector3.UP, 0.12 * sx),
				Vector3(px + bahnseitig * 4.0, BODEN, pz - 11.8)))
		if i == 3 or i == 4:
			_munitionswagen(Transform3D(Basis(Vector3.UP, PI * 0.5),
				Vector3(px - bahnseitig * 4.0, BODEN, pz - 9.2)))


func _aggregat(xf: Transform3D) -> void:
	_ob(st, xf, Vector3(0, 0.55, 0), Vector3(1.5, 0.25, 2.4), C_STAHL)
	_ob(st, xf, Vector3(0, 1.25, 0.1), Vector3(1.4, 1.2, 2.0), C_GELB)
	_ob(st, xf, Vector3(0, 1.25, 1.12), Vector3(1.1, 0.8, 0.05), Color(0.12, 0.12, 0.12))
	_ob(st, xf, Vector3(0, 0.55, -1.6), Vector3(0.12, 0.12, 1.0), C_STAHL)
	for wx: float in [-0.75, 0.75]:
		for wz: float in [-0.8, 0.8]:
			_rad(st, xf, Vector3(wx, 0.32, wz), 0.32, 0.22)
	_kol(xf * Vector3(0, 0.9, 0), Vector3(1.5, 1.8, 2.4), xf.basis.get_euler().y)


func _loescher(xf: Transform3D) -> void:
	_ob(st, xf, Vector3(0, 0.3, 0), Vector3(0.9, 0.08, 0.6), C_STAHL)
	for wx: float in [-0.22, 0.22]:
		_zyl(st, xf * Vector3(wx, 0.34, 0), xf * Vector3(wx, 1.35, 0), 0.2, 10, C_ROT)
		_zyl(st, xf * Vector3(wx, 1.35, 0), xf * Vector3(wx, 1.5, 0), 0.07, 6, C_STAHL)
	_rad(st, xf, Vector3(-0.5, 0.26, 0), 0.26, 0.1)
	_rad(st, xf, Vector3(0.5, 0.26, 0), 0.26, 0.1)


func _leiter(xf: Transform3D) -> void:
	var neig := Basis(Vector3.RIGHT, -0.32)
	var lx := Transform3D(xf.basis * neig, xf.origin)
	for wx: float in [-0.45, 0.45]:
		_ob(st, lx, Vector3(wx, 1.45, 0), Vector3(0.08, 3.0, 0.1), C_GELB)
	for i in 7:
		_ob(st, lx, Vector3(0, 0.3 + float(i) * 0.4, 0), Vector3(0.9, 0.05, 0.22), C_STAHL)
	_ob(st, xf, Vector3(0, 0.08, -0.6), Vector3(1.0, 0.12, 0.12), C_STAHL)


func _werkzeugwagen(xf: Transform3D) -> void:
	_ob(st, xf, Vector3(0, 0.6, 0), Vector3(1.1, 0.9, 0.6), C_ROT)
	for i in 4:
		_ob(st, xf, Vector3(0, 0.3 + float(i) * 0.22, 0.31), Vector3(1.0, 0.02, 0.02),
			Color(0.20, 0.05, 0.04))
	_ob(st, xf, Vector3(0, 1.1, 0), Vector3(1.15, 0.08, 0.65), C_STAHL)
	for wx: float in [-0.45, 0.45]:
		for wz: float in [-0.22, 0.22]:
			_rad(st, xf, Vector3(wx, 0.08, wz), 0.08, 0.05)


func _schlepper(xf: Transform3D) -> void:
	_ob(st, xf, Vector3(0, 0.75, 0), Vector3(2.3, 0.9, 4.6), C_GELB)
	_ob(st, xf, Vector3(0, 1.2, 1.6), Vector3(2.1, 0.06, 1.0), Color(0.16, 0.16, 0.16))
	_ob(st, xf, Vector3(0, 1.85, -1.3), Vector3(1.9, 1.3, 1.6), C_GLAS)
	_ob(st, xf, Vector3(0, 2.55, -1.3), Vector3(2.05, 0.14, 1.8), C_GELB)
	for ex: float in [-0.92, 0.92]:
		for ez: float in [-2.05, -0.55]:
			_ob(st, xf, Vector3(ex, 1.85, ez + 0.0), Vector3(0.1, 1.3, 0.1), C_GELB)
	_ob(st, xf, Vector3(0, 0.55, 2.5), Vector3(0.5, 0.25, 0.6), C_STAHL)
	_zyl(sb, xf * Vector3(0, 2.62, -1.3), xf * Vector3(0, 2.85, -1.3), 0.12, 8, _phase(Color(1.0, 0.55, 0.05)))
	for ex: float in [-0.7, 0.7]:
		Landmarks._box_geo(sl, xf * Vector3(ex, 0.9, 2.31), Vector3(0.25, 0.15, 0.04), L_KALT)
	for wx: float in [-1.15, 1.15]:
		for wz: float in [-1.5, 1.5]:
			_rad(st, xf, Vector3(wx, 0.48, wz), 0.48, 0.42)
	_kol(xf * Vector3(0, 1.3, 0), Vector3(2.3, 2.6, 4.6), xf.basis.get_euler().y)


func _tankwagen(xf: Transform3D) -> void:
	var c_kab := Color(0.30, 0.34, 0.24)
	var c_tank := Color(0.62, 0.62, 0.60)
	_ob(st, xf, Vector3(0, 0.95, 0), Vector3(2.4, 0.4, 9.2), C_STAHL)
	_ob(st, xf, Vector3(0, 1.9, 3.5), Vector3(2.5, 2.2, 2.0), c_kab)
	_ob(st, xf, Vector3(0, 2.35, 4.52), Vector3(2.2, 0.9, 0.04), C_GLAS)
	_ob(st, xf, Vector3(0, 1.0, 4.6), Vector3(2.5, 0.35, 0.2), C_STAHL)
	_zyl(st, xf * Vector3(0, 2.3, -4.3), xf * Vector3(0, 2.3, 2.2), 1.2, 14, c_tank)
	for rz: float in [-3.0, -0.9, 1.2]:
		_zyl(st, xf * Vector3(0, 2.3, rz - 0.06), xf * Vector3(0, 2.3, rz + 0.06), 1.25, 14,
			Landmarks._shade(c_tank, 0.7))
	_ob(st, xf, Vector3(0, 3.6, -1.0), Vector3(0.8, 0.06, 5.6), C_STAHL)
	_ob(st, xf, Vector3(0, 1.3, -4.7), Vector3(1.6, 1.0, 0.5), C_ROT)
	for ex: float in [-0.8, 0.8]:
		Landmarks._box_geo(sl, xf * Vector3(ex, 1.2, 4.72), Vector3(0.3, 0.18, 0.04), L_KALT)
	for wz: float in [-3.6, -2.4, 3.4]:
		for wx: float in [-1.15, 1.15]:
			_rad(st, xf, Vector3(wx, 0.55, wz), 0.55, 0.4)
	_kol(xf * Vector3(0, 1.75, 0), Vector3(2.5, 3.5, 9.4), xf.basis.get_euler().y)


func _munitionswagen(xf: Transform3D) -> void:
	_ob(st, xf, Vector3(0, 0.5, 0), Vector3(1.6, 0.15, 3.6), C_OLIV)
	for wx: float in [-0.5, 0.5]:
		_ob(st, xf, Vector3(wx, 0.7, 0), Vector3(0.12, 0.3, 3.4), C_STAHL)
		_zyl(st, xf * Vector3(wx, 0.98, -1.6), xf * Vector3(wx, 0.98, 1.5), 0.17, 8,
			Color(0.82, 0.82, 0.80))
		_zyl(st, xf * Vector3(wx, 0.98, 1.5), xf * Vector3(wx, 0.98, 1.85), 0.12, 8,
			Color(0.82, 0.82, 0.80))
		_zyl(st, xf * Vector3(wx, 0.98, 0.9), xf * Vector3(wx, 0.98, 1.0), 0.18, 8, C_GELB)
	_ob(st, xf, Vector3(0, 0.5, 2.3), Vector3(0.1, 0.1, 1.2), C_STAHL)
	for wx: float in [-0.7, 0.7]:
		for wz: float in [-1.2, 1.2]:
			_rad(st, xf, Vector3(wx, 0.28, wz), 0.28, 0.16)


func _gabelstapler(xf: Transform3D) -> void:
	_ob(st, xf, Vector3(0, 0.8, 0), Vector3(1.2, 1.0, 2.2), C_GELB)
	_ob(st, xf, Vector3(0, 0.9, -1.0), Vector3(1.2, 0.9, 0.5), Color(0.20, 0.20, 0.21))
	for ex: float in [-0.5, 0.5]:
		_ob(st, xf, Vector3(ex, 1.9, 1.2), Vector3(0.12, 3.2, 0.12), C_STAHL)
		_ob(st, xf, Vector3(ex * 0.6, 0.22, 1.85), Vector3(0.14, 0.06, 1.2), C_STAHL)
	for ex: float in [-0.5, 0.5]:
		for ez: float in [-0.8, 0.6]:
			_ob(st, xf, Vector3(ex, 1.7, ez), Vector3(0.07, 1.2, 0.07), C_STAHL)
	_ob(st, xf, Vector3(0, 2.3, -0.1), Vector3(1.15, 0.08, 1.6), C_STAHL)
	for wx: float in [-0.6, 0.6]:
		for wz: float in [-0.7, 0.75]:
			_rad(st, xf, Vector3(wx, 0.3, wz), 0.3, 0.22)


func _container(xf: Transform3D, farbe: Color) -> void:
	_ob(st, xf, Vector3(0, 1.3, 0), Vector3(2.44, 2.59, 6.06), farbe)
	for i in 13:
		var z := -2.7 + float(i) * 0.45
		for wx: float in [-1.24, 1.24]:
			_ob(st, xf, Vector3(wx, 1.3, z), Vector3(0.05, 2.4, 0.16), Landmarks._shade(farbe, 0.8))
	_ob(st, xf, Vector3(0, 1.3, 3.04), Vector3(2.3, 2.45, 0.04), Landmarks._shade(farbe, 0.75))
	for ex: float in [-0.5, 0.5]:
		_ob(st, xf, Vector3(ex, 1.3, 3.08), Vector3(0.06, 2.3, 0.06), C_STAHL)
	_kol(xf * Vector3(0, 1.3, 0), Vector3(2.44, 2.6, 6.06), xf.basis.get_euler().y)


func _paletten(xf: Transform3D) -> void:
	var holz := Color(0.45, 0.33, 0.20)
	_ob(st, xf, Vector3(0, 0.08, 0), Vector3(1.2, 0.15, 1.0), holz)
	var art := rng.randi() % 3
	if art == 0:
		for i in 4:
			var o := Vector3(-0.3 + float(i % 2) * 0.6, 0.0, -0.25 + float(i >> 1) * 0.5)
			_zyl(st, xf * (o + Vector3(0, 0.16, 0)), xf * (o + Vector3(0, 1.05, 0)), 0.28, 10,
				[Color(0.12, 0.22, 0.44), C_ROT, C_OLIV][rng.randi() % 3])
	elif art == 1:
		_ob(st, xf, Vector3(0, 0.6, 0), Vector3(1.15, 0.9, 0.95), Color(0.55, 0.45, 0.30))
		_ob(st, xf, Vector3(0.1, 1.3, 0), Vector3(0.8, 0.5, 0.7), Color(0.50, 0.40, 0.26))
	else:
		_ob(st, xf, Vector3(0, 0.55, 0), Vector3(1.15, 0.8, 0.95), C_OLIV)
		_ob(st, xf, Vector3(0, 0.96, 0), Vector3(1.0, 0.04, 0.8), Landmarks._shade(C_OLIV, 0.7))


## Fahrzeugpark und Lager zwischen Haeusern und Bahn: Container, Paletten, Stapler.
func _fahrzeugpark() -> void:
	var lager := [[1.0, 270.0], [-1.0, 380.0], [1.0, 500.0], [-1.0, 620.0], [1.0, 760.0],
		[-1.0, 790.0], [1.0, 930.0], [-1.0, 270.0]]
	for e: Array in lager:
		var sx: float = e[0]
		var z: float = e[1]
		var x := sx * 57.0
		for k in 5:
			_paletten(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)),
				Vector3(x + sx * rng.randf_range(-1.5, 1.5), BODEN, z + float(k) * 1.6 - 3.0)))
		_gabelstapler(Transform3D(Basis(Vector3.UP, sx * PI * 0.5 + 0.4),
			Vector3(x - sx * 4.5, BODEN, z + 3.0)))
	var cont := [[1.0, 375.0, Color(0.55, 0.28, 0.10)], [1.0, 382.0, Color(0.20, 0.30, 0.40)],
		[-1.0, 505.0, Color(0.30, 0.34, 0.22)], [-1.0, 760.0, Color(0.55, 0.28, 0.10)],
		[1.0, 640.0, Color(0.30, 0.34, 0.22)]]
	for c: Array in cont:
		var sx: float = c[0]
		_container(Transform3D(Basis(), Vector3(sx * 57.5, BODEN, float(c[1]))), c[2])
	# Loeschfahrzeug bereit am Hallenanfang
	_feuerwehr(Transform3D(Basis(Vector3.UP, PI), Vector3(-52.0, BODEN, 240.0)))


func _feuerwehr(xf: Transform3D) -> void:
	_ob(st, xf, Vector3(0, 1.0, 0), Vector3(2.5, 0.5, 8.4), C_STAHL)
	_ob(st, xf, Vector3(0, 2.2, 3.2), Vector3(2.5, 2.4, 2.0), C_ROT)
	_ob(st, xf, Vector3(0, 2.6, 4.22), Vector3(2.2, 0.9, 0.04), C_GLAS)
	_ob(st, xf, Vector3(0, 2.0, -1.0), Vector3(2.5, 2.2, 6.2), C_ROT)
	for k in 4:
		_ob(st, xf, Vector3(1.26, 1.8, -3.4 + float(k) * 1.5), Vector3(0.04, 1.6, 1.3),
			Landmarks._shade(C_ROT, 0.7))
	_ob(st, xf, Vector3(0, 3.25, -1.0), Vector3(2.0, 0.1, 5.8), C_STAHL)
	_zyl(st, xf * Vector3(0, 3.5, 0.5), xf * Vector3(0, 3.5, -3.8), 0.18, 8, C_STAHL)
	for ex: float in [-0.7, 0.7]:
		_zyl(sb, xf * Vector3(ex, 3.5, 3.6), xf * Vector3(ex, 3.75, 3.6), 0.13, 8, _phase(Color(0.25, 0.45, 1.0)))
		Landmarks._box_geo(sl, xf * Vector3(ex, 1.2, 4.24), Vector3(0.3, 0.18, 0.04), L_KALT)
	for wz: float in [-3.2, -1.9, 3.0]:
		for wx: float in [-1.15, 1.15]:
			_rad(st, xf, Vector3(wx, 0.58, wz), 0.58, 0.42)
	_kol(xf * Vector3(0, 1.8, 0), Vector3(2.5, 3.6, 8.6), xf.basis.get_euler().y)


# --- Aura: Lauflicht, Rundumleuchten, Wappen, Dunst, Portalschrift ---------------------------
## LAUFLICHT entlang der Bahn: beidseits knapp neben der Bahnkante alle 15 m, draussen im Tal
## auf der Achse alle 24 m bis 480 m vor das Portal (der Talboden liegt dort eben auf 90,0 m,
## also 0,7 m unter dem Hallenboden). Ein Blitz nach dem anderen laeuft in den Berg hinein.
func _lauflicht() -> void:
	var c := Color(1.0, 0.97, 0.90)
	var z := -480.0
	while z < -8.0:
		var col := Color(c.r, c.g, c.b, clampf((z + 500.0) / 1100.0, 0.0, 1.0))
		_q(sa, Vector3(0, -0.55, z), Vector3(0.9, 0.3, 0.9), C_STAHL)
		Landmarks._box_geo(sw, Vector3(0, -0.32, z), Vector3(0.55, 0.18, 0.55), col)
		z += 24.0
	z = 20.0
	while z < Landmarks.HB_BAHN_D1 + 1.0:
		for sx: float in [-1.0, 1.0]:
			var col := Color(c.r, c.g, c.b, clampf((z + 500.0) / 1100.0, 0.0, 1.0))
			_q(st, Vector3(sx * 16.5, 0.2, z), Vector3(0.7, 0.25, 0.7), C_STAHL)
			Landmarks._box_geo(sw, Vector3(sx * 16.5, 0.38, z), Vector3(0.45, 0.14, 0.45), col)
		z += 15.0


## RUNDUMLEUCHTEN: gelb an den Ecken der Wartungsgerueste, rot am Portal und an der
## Rueckwand, gelb auf den Gittertuermen.
func _rundumleuchten() -> void:
	for wi: int in WARTUNG:
		var s: Array = STAENDE[wi]
		var px: float = s[1]
		var pz: float = s[2]
		for cx: float in [-1.0, 1.0]:
			for cz: float in [-1.0, 1.0]:
				var p := Vector3(px + cx * 13.0, BODEN + 13.0 + 1.0, pz + cz * 12.0)
				_zyl(st, p - Vector3(0, 0.15, 0), p, 0.32, 8, C_STAHL)
				_zyl(sb, p, p + Vector3(0, 0.45, 0), 0.24, 8, _phase(Color(1.0, 0.62, 0.08)))
	for sx: float in [-1.0, 1.0]:
		for y: float in [3.0, 12.0]:
			var p := Vector3(sx * (Landmarks.HB_W_MUND - 1.0), y, 2.0)
			_zyl(sb, p, p + Vector3(0, 0.6, 0), 0.35, 8, _phase(Color(1.0, 0.14, 0.08)))
		for tz: float in [240.0, 560.0, 880.0]:
			var p := Vector3(sx * (Landmarks.HB_W_HALLE - 13.0), 40.4, tz)
			_zyl(sb, p, p + Vector3(0, 0.5, 0), 0.3, 8, _phase(Color(1.0, 0.62, 0.08)))


## DAS WAPPEN an der Rueckwand: ein Adler mit gestuften Schwingen in einem leuchtenden Ring,
## 30 m hoch — vom Portal aus am Ende der Halle zu sehen, 1 km tief im Berg. Aus Vierecken
## und Dreiecken gebaut (Schwungfedern als schraege Lamellen), leuchtend vor einer dunklen
## Stahlscheibe.
func _wappen() -> void:
	var z := Landmarks.HB_LAENGE - 7.0
	var m := Vector3(0, 37.0, z)
	var gold := Color(1.0, 0.80, 0.42)
	var weiss := Color(1.0, 0.95, 0.86)
	# Scheibe und Ring
	var n := 48
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		Landmarks._tri(st, m + Vector3(0, 0, 0.3), m + d0 * 15.6 + Vector3(0, 0, 0.3),
			m + d1 * 15.6 + Vector3(0, 0, 0.3), Color(0.07, 0.075, 0.085))
		Landmarks._quad(sl, m + d0 * 14.2, m + d0 * 15.2, m + d1 * 15.2, m + d1 * 14.2, gold)
		Landmarks._quad(sl, m + d0 * 12.6, m + d0 * 13.0, m + d1 * 13.0, m + d1 * 12.6, gold)
	# Rumpf (Raute), Kopf mit Schnabel, Schwanzfedern
	var f := m - Vector3(0, 0, 0.05)
	Landmarks._quad(sl, f + Vector3(0, 6.2, 0), f + Vector3(1.9, 1.5, 0), f + Vector3(0, -6.0, 0),
		f + Vector3(-1.9, 1.5, 0), weiss)
	Landmarks._quad(sl, f + Vector3(0, 9.6, 0), f + Vector3(1.3, 7.8, 0), f + Vector3(0, 5.8, 0),
		f + Vector3(-1.3, 7.8, 0), weiss)
	Landmarks._tri(sl, f + Vector3(-1.1, 8.6, 0), f + Vector3(-3.0, 8.0, 0), f + Vector3(-1.2, 7.4, 0),
		gold)
	for t in 3:
		var x := (float(t) - 1.0) * 1.3
		Landmarks._quad(sl, f + Vector3(x - 0.55, -5.6, 0), f + Vector3(x + 0.55, -5.6, 0),
			f + Vector3(x * 1.6 + 0.35, -10.6, 0), f + Vector3(x * 1.6 - 0.35, -10.6, 0), weiss)
	# Schwingen: je Seite sechs Federlamellen, nach aussen steigend, unten kuerzer
	for sx: float in [-1.0, 1.0]:
		for i in 6:
			var y0 := 4.6 - float(i) * 1.55
			var x0 := 1.7
			var lang := 10.6 - float(i) * 1.15
			var steig := 0.42 - float(i) * 0.03
			var dicke := 1.05
			var a := f + Vector3(sx * x0, y0, 0)
			var b := f + Vector3(sx * (x0 + lang), y0 + lang * steig, 0)
			var spitze := f + Vector3(sx * (x0 + lang + 1.2), y0 + lang * steig - 0.2, 0)
			var bu := b - Vector3(0, dicke, 0)
			var au := a - Vector3(0, dicke, 0)
			Landmarks._quad(sl, a, b, bu, au, weiss if i % 2 == 0 else Color(0.96, 0.88, 0.70))
			Landmarks._tri(sl, b, spitze, bu, weiss)
	# Licht auf die Wand
	var l := SpotLight3D.new()
	l.transform = Transform3D(Basis.looking_at(Vector3(0, 0.55, 1.0)), Vector3(0, 6.0, z - 40.0))
	l.light_color = Color(1.0, 0.82, 0.56)
	l.light_energy = 18.0
	l.spot_range = 80.0
	l.spot_angle = 26.0
	l.shadow_enabled = false
	node.add_child(l)


## DUNST IN DER HALLE (Godots volumetrischer Nebel, nur in diesem Volumen): darin werden die
## Lichtkegel der Pendelleuchten und Fluter sichtbar, und die Tiefe der Halle versinkt.
## Eingeschaltet wird der volumetrische Nebel nur, wenn die Kamera bei der Basis ist
## (Main._kavernen_stimmung) — er kostet sonst ueberall.
func _dunst() -> void:
	var fv := FogVolume.new()
	fv.name = "AusbauDunst"
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fv.size = Vector3(Landmarks.HB_W_HALLE * 2.0 + 6.0, Landmarks.HB_H_HALLE + 6.0,
		Landmarks.HB_LAENGE + 40.0)
	fv.position = Vector3(0, (Landmarks.HB_H_HALLE + 6.0) * 0.5 - 2.0, Landmarks.HB_LAENGE * 0.5 - 10.0)
	var fm := FogMaterial.new()
	fm.density = 0.0045
	fm.albedo = Color(0.86, 0.80, 0.72)
	fm.edge_fade = 0.08
	fv.material = fm
	node.add_child(fv)
	# NUR DIE SCHEINWERFER ZIEHEN LICHTBAHNEN. Die vielen Fuell-Omnis (Landmarks: je Pendel
	# eine, Reichweite 26 m) leuchteten den ganzen Dunst gleichmaessig aus — die Halle stand
	# milchig da statt mit Lichtkegeln im Dunkeln.
	for l in node.find_children("*", "Light3D", true, false):
		if l is SpotLight3D:
			(l as Light3D).light_volumetric_fog_energy = 2.2
		else:
			(l as Light3D).light_volumetric_fog_energy = 0.0


## SCHRIFTZUG UEBER DEM PORTAL: ein Betonsturz vor der Felsstirn mit dem Namen der Basis,
## im Anflug schon von weitem lesbar.
func _portalschrift() -> void:
	var y := 57.0
	var z := -11.0
	_q(sa, Vector3(0, y, z), Vector3(64.0, 9.0, 6.0), Color(0.13, 0.13, 0.14))
	_q(sa, Vector3(0, y - 4.7, z - 0.5), Vector3(65.0, 0.5, 7.0), Color(0.34, 0.33, 0.32))
	_q(sa, Vector3(0, y + 4.7, z - 0.5), Vector3(65.0, 0.5, 7.0), Color(0.34, 0.33, 0.32))
	# Leuchtschrift: Farbe ueber 1, damit sie auch im Tageslicht im Lichtglanz glueht
	_schild("ADLERHORST", Vector3(0, y + 0.2, z - 3.05), Vector3(0, 0, -1), 0.062,
		Color(3.2, 2.9, 2.4))
	for sx: float in [-1.0, 1.0]:
		Landmarks._box_geo(sl, Vector3(sx * 29.5, y, z - 3.1), Vector3(1.4, 1.4, 0.1),
			Color(1.0, 0.2, 0.12))


# --- Liebe zum Detail: Banner, Rollwegschilder, Portalbau, Figuren ---------------------------
const BANNER_FARBEN := [Color(0.50, 0.07, 0.06), Color(0.07, 0.12, 0.32), Color(0.20, 0.27, 0.14)]
const C_GOLD := Color(0.86, 0.66, 0.22)


## STAFFELBANNER: an fuenf Rippen je Seite ein 14 m langes Tuch mit Schwalbenschwanz, gold
## gesaeumt, mit Winkel-Abzeichen — von unten von einem kleinen Strahler angeleuchtet. Das
## gibt der Halle Farbe und Zugehoerigkeit; vorher war sie grau in grau.
func _banner() -> void:
	var rippen := [300.0, 444.0, 588.0, 732.0, 876.0]
	var n := 0
	for rz: float in rippen:
		for sx: float in [-1.0, 1.0]:
			var farbe: Color = BANNER_FARBEN[n % BANNER_FARBEN.size()]
			n += 1
			var x := sx * 44.0
			var z := rz - RIPPE_HALB - 0.6
			var oben := 46.0
			var unten := 32.0
			var b := 2.5
			# Stange und Seile
			_q(st, Vector3(x, oben + 0.25, z), Vector3(b * 2.0 + 0.6, 0.18, 0.18), C_STAHL)
			for ex: float in [-b, b]:
				_q(st, Vector3(x + ex, oben + 1.3, z), Vector3(0.05, 2.1, 0.05), C_STAHL)
			# Tuch in Streifen, leicht gewellt
			var streifen := 7
			for i in streifen:
				var y0 := oben - (oben - unten - 2.0) * float(i) / float(streifen)
				var y1 := oben - (oben - unten - 2.0) * float(i + 1) / float(streifen)
				var w0 := 0.18 * sin(float(i) * 1.7 + float(n))
				var w1 := 0.18 * sin(float(i + 1) * 1.7 + float(n))
				var ton := 0.92 + 0.10 * float(i % 2)
				Landmarks._quad(st, Vector3(x - b, y0, z + w0), Vector3(x + b, y0, z + w0),
					Vector3(x + b, y1, z + w1), Vector3(x - b, y1, z + w1), Landmarks._shade(farbe, ton))
				# Goldsaum an den Kanten (beidseitig sichtbar)
				for kx: float in [-b, b - 0.3]:
					for dz: float in [-0.03, 0.03]:
						Landmarks._quad(st, Vector3(x + kx, y0, z + w0 + dz), Vector3(x + kx + 0.3, y0, z + w0 + dz),
							Vector3(x + kx + 0.3, y1, z + w1 + dz), Vector3(x + kx, y1, z + w1 + dz), C_GOLD)
			var yf := unten + 2.0
			Landmarks._tri(st, Vector3(x - b, yf, z), Vector3(x, yf, z), Vector3(x - b, unten, z), farbe)
			Landmarks._tri(st, Vector3(x, yf, z), Vector3(x + b, yf, z), Vector3(x + b, unten, z), farbe)
			# Abzeichen: goldener Doppelwinkel und ein Stern, auf beiden Seiten
			for dz: float in [-0.06, 0.06]:
				for w in 2:
					var cy := 41.0 - float(w) * 1.6
					Landmarks._quad(st, Vector3(x - 1.6, cy + 1.0, z + dz), Vector3(x, cy, z + dz),
						Vector3(x, cy - 0.7, z + dz), Vector3(x - 1.6, cy + 0.3, z + dz), C_GOLD)
					Landmarks._quad(st, Vector3(x, cy, z + dz), Vector3(x + 1.6, cy + 1.0, z + dz),
						Vector3(x + 1.6, cy + 0.3, z + dz), Vector3(x, cy - 0.7, z + dz), C_GOLD)
				for k in 5:
					var a0 := PI * 0.5 + TAU * float(k) / 5.0
					var a1 := a0 + TAU / 10.0
					var a2 := a0 - TAU / 10.0
					var m := Vector3(x, 43.6, z + dz)
					Landmarks._tri(st, m + Vector3(cos(a0), sin(a0), 0) * 0.9,
						m + Vector3(cos(a1), sin(a1), 0) * 0.36, m + Vector3(cos(a2), sin(a2), 0) * 0.36, C_GOLD)
					Landmarks._tri(st, m, m + Vector3(cos(a1), sin(a1), 0) * 0.36,
						m + Vector3(cos(a2), sin(a2), 0) * 0.36, C_GOLD)
			var l := SpotLight3D.new()
			l.transform = Transform3D(Basis.looking_at(Vector3(0, 1.0, 0.45).normalized()),
				Vector3(x, 24.0, z - 7.0))
			l.light_color = Color(1.0, 0.86, 0.66)
			l.light_energy = 7.0
			l.spot_range = 28.0
			l.spot_angle = 16.0
			l.shadow_enabled = false
			node.add_child(l)


## ROLLWEGSCHILDER an der Bahnschulter vor jedem Stand: gelbe Leuchttafel mit Standnummer und
## Pfeil zur Standseite, zum Portal hin lesbar (wer einrollt, liest sie).
func _rollschilder() -> void:
	for i in STAENDE.size():
		var s: Array = STAENDE[i]
		var px: float = s[1]
		var pz: float = s[2]
		var sx := signf(px)
		var x := sx * 23.4
		var z := pz - 15.0
		for lx: float in [-2.2, 2.2]:
			_q(st, Vector3(x + lx, BODEN + 0.7, z), Vector3(0.14, 1.4, 0.14), C_STAHL)
		_q(st, Vector3(x, BODEN + 1.95, z), Vector3(5.6, 1.3, 0.3), Color(0.05, 0.05, 0.05))
		Landmarks._box_geo(sl, Vector3(x, BODEN + 1.95, z - 0.17), Vector3(5.4, 1.1, 0.02),
			Color(1.0, 0.80, 0.10))
		# Pfeil zur Standseite (Welt +x*sx; wer in den Berg rollt, hat +x links), schwarz vor
		# dem Leuchtgelb, am stand-seitigen Ende; die Schrift am anderen.
		var py := BODEN + 1.95
		var zz := z - 0.2
		var spitze := x + sx * 2.5
		Landmarks._tri(st, Vector3(spitze, py, zz), Vector3(spitze - sx * 0.6, py + 0.42, zz),
			Vector3(spitze - sx * 0.6, py - 0.42, zz), Color(0.03, 0.03, 0.03))
		_q(st, Vector3(spitze - sx * 1.05, py, zz), Vector3(0.9, 0.22, 0.02), Color(0.03, 0.03, 0.03))
		var l := Label3D.new()
		l.text = "STAND %d" % (i + 1)
		l.font = _schrift()
		l.font_size = 96
		l.pixel_size = 0.0068
		l.modulate = Color(0.02, 0.02, 0.02)
		l.outline_size = 0
		l.shaded = false
		l.double_sided = false
		l.position = Vector3(x - sx * 0.75, py, z - 0.21)
		l.rotation.y = PI
		node.add_child(l)
		_kol(Vector3(x, BODEN + 1.4, z), Vector3(5.6, 2.8, 0.4))


## PORTAL ALS BAUWERK: zwei gestufte Fluegelmauern aus Beton zu beiden Seiten des Rings,
## mit Pfeilern, Abdeckung und Flutern; die Panzertore im Mund mit Rippen, Warnkante und
## Torbezeichnung; draussen Wachhaeuschen und Flaggenmast.
func _portalbau() -> void:
	var c_beton := Color(0.30, 0.295, 0.285)
	var talboden := -0.7
	for sx: float in [-1.0, 1.0]:
		# VOR der Felsstirn (ihr Fuss liegt bei z -26 bis |x| 80): die Mauern rahmen das
		# Vorfeld wie ein Tor und stecken nicht im Fels.
		var a := Vector2(sx * 36.0, -28.0)
		var b := Vector2(sx * 82.0, -50.0)
		var d := (b - a)
		var lang := d.length()
		var dir := d / lang
		var gier := atan2(dir.x, dir.y) - PI * 0.5
		var stufen := 6
		for k in stufen:
			var t := (float(k) + 0.5) / float(stufen)
			var m := a + d * t
			var h := lerpf(27.0, 7.0, float(k) / float(stufen - 1))
			var xf := Transform3D(Basis(Vector3.UP, gier), Vector3(m.x, talboden, m.y))
			_ob(sa, xf, Vector3(0, h * 0.5, 0), Vector3(lang / float(stufen) + 0.05, h, 2.6), c_beton)
			_ob(sa, xf, Vector3(0, h + 0.25, 0), Vector3(lang / float(stufen) + 0.4, 0.5, 3.2),
				Landmarks._shade(c_beton, 0.8))
			# Pfeiler an der Stufe
			_ob(sa, xf, Vector3(-lang / float(stufen) * 0.5, h * 0.5, -1.5), Vector3(0.9, h, 0.6),
				Landmarks._shade(c_beton, 0.9))
			# Fugenbaender
			var fy := 3.0
			while fy < h - 1.0:
				_ob(sa, xf, Vector3(0, fy, -1.32), Vector3(lang / float(stufen), 0.08, 0.06),
					Landmarks._shade(c_beton, 0.7))
				fy += 3.0
			_kol(xf * Vector3(0, h * 0.5, 0), Vector3(lang / float(stufen), h, 2.6), gier)
		# Fluter auf der hoechsten Stufe, auf den Ring gerichtet
		var fx := Transform3D(Basis(Vector3.UP, gier), Vector3(a.x + d.x * 0.08, talboden, a.y + d.y * 0.08))
		_ob(sa, fx, Vector3(0, 28.0, -0.6), Vector3(1.4, 0.9, 0.9), C_STAHL)
		Landmarks._box_geo(sl, fx * Vector3(0, 28.0, -1.1), Vector3(1.0, 0.6, 0.1), L_KALT)
		# Panzertore: Rippen innen, Warnkante vorn, Bezeichnung
		var tx := sx * (Landmarks.HB_W_MUND - 3.2)
		var innen := tx - sx * 2.5
		var y := 2.0
		while y < 31.0:
			_q(st, Vector3(innen - sx * 0.2, y, 5.0), Vector3(0.4, 0.5, 15.2), C_STAHL)
			y += 3.2
		for k in 16:
			_q(st, Vector3(tx, 1.0 + float(k) * 2.0, -3.05), Vector3(5.0, 2.0, 0.08),
				C_GELB if k % 2 == 0 else Color(0.04, 0.04, 0.04))
		_q(st, Vector3(tx, 0.15, 5.0), Vector3(5.6, 0.3, 17.0), Color(0.12, 0.12, 0.13))
		var l := Label3D.new()
		l.text = "TOR %d" % (1 if sx < 0.0 else 2)
		l.font = _schrift()
		l.font_size = 96
		l.pixel_size = 0.03
		l.modulate = Color(0.85, 0.80, 0.70)
		l.shaded = true
		l.double_sided = false
		l.position = Vector3(innen - sx * 0.42, 18.0, 5.0)
		l.rotation.y = -sx * PI * 0.5
		node.add_child(l)
	# Wachhaeuschen mit Flaggenmast, links vor dem Portal
	var wx := -56.0
	var wz := -44.0
	_q(sa, Vector3(wx, talboden + 1.4, wz), Vector3(3.2, 2.8, 3.2), Color(0.62, 0.60, 0.55))
	_q(sa, Vector3(wx, talboden + 2.95, wz), Vector3(4.0, 0.3, 4.0), C_STAHL)
	Landmarks._box_geo(sl, Vector3(wx + 1.62, talboden + 1.75, wz), Vector3(0.04, 0.9, 2.4), L_WARM)
	Landmarks._box_geo(sl, Vector3(wx, talboden + 1.75, wz - 1.62), Vector3(2.4, 0.9, 0.04), L_WARM)
	_kol(Vector3(wx, talboden + 1.5, wz), Vector3(3.2, 3.0, 3.2))
	var mx := wx - 5.0
	_zyl(sa, Vector3(mx, talboden, wz), Vector3(mx, talboden + 15.0, wz), 0.14, 8, Color(0.8, 0.8, 0.78))
	_zyl(sa, Vector3(mx, talboden + 15.0, wz), Vector3(mx, talboden + 15.3, wz), 0.25, 8, C_GOLD)
	var fahne := BANNER_FARBEN[1] as Color
	for i in 4:
		var x0 := mx + float(i) * 0.9
		var x1 := x0 + 0.9
		var w0 := 0.25 * sin(float(i) * 1.4)
		var w1 := 0.25 * sin(float(i + 1) * 1.4)
		Landmarks._quad(sa, Vector3(x0, talboden + 14.6, wz + w0), Vector3(x1, talboden + 14.6, wz + w1),
			Vector3(x1, talboden + 12.4, wz + w1), Vector3(x0, talboden + 12.4, wz + w0), fahne)
	for dz: float in [-0.05, 0.05]:
		Landmarks._quad(sa, Vector3(mx + 1.2, talboden + 13.9, wz + dz), Vector3(mx + 1.8, talboden + 13.5, wz + dz),
			Vector3(mx + 1.8, talboden + 13.1, wz + dz), Vector3(mx + 1.2, talboden + 13.5, wz + dz), C_GOLD)
		Landmarks._quad(sa, Vector3(mx + 1.8, talboden + 13.5, wz + dz), Vector3(mx + 2.4, talboden + 13.9, wz + dz),
			Vector3(mx + 2.4, talboden + 13.5, wz + dz), Vector3(mx + 1.8, talboden + 13.1, wz + dz), C_GOLD)


## FIGUREN: Bodenpersonal mit Helm und Warnweste, Techniker, Piloten, Einweiser mit
## Leuchtstaeben, Wachen — an jedem Stand, vor den Haustueren, auf dem Gehweg.
func _figur(xf: Transform3D, rolle: String, ziel: SurfaceTool = null) -> void:
	var fs := st if ziel == null else ziel
	var hose := Color(0.12, 0.14, 0.22)
	var jacke := Color(0.14, 0.16, 0.26)
	var weste := Color(0.95, 0.78, 0.05)
	var helm := Color(0.95, 0.80, 0.10)
	var haut := Color(0.70, 0.52, 0.40) if rng.randf() < 0.6 else Color(0.48, 0.34, 0.25)
	match rolle:
		"techniker":
			hose = Color(0.30, 0.31, 0.33)
			jacke = hose
			weste = Color(0.98, 0.45, 0.06)
			helm = Color(0.16, 0.17, 0.20)
		"pilot":
			hose = Color(0.30, 0.34, 0.22)
			jacke = hose
			weste = hose
			helm = Color(0.92, 0.92, 0.90)
		"einweiser":
			weste = Color(0.98, 0.45, 0.06)
			helm = Color(0.95, 0.95, 0.92)
		"wache":
			hose = Color(0.20, 0.24, 0.16)
			jacke = hose
			weste = hose
			helm = Color(0.10, 0.10, 0.10)
	for bx: float in [-0.11, 0.11]:
		_ob(fs, xf, Vector3(bx, 0.06, 0.04), Vector3(0.15, 0.12, 0.28), Color(0.05, 0.05, 0.05))
		_ob(fs, xf, Vector3(bx, 0.52, 0), Vector3(0.16, 0.8, 0.19), hose)
	_ob(fs, xf, Vector3(0, 1.24, 0), Vector3(0.44, 0.62, 0.26), jacke)
	if weste != jacke:
		_ob(fs, xf, Vector3(0, 1.22, 0), Vector3(0.47, 0.46, 0.29), weste)
		_ob(fs, xf, Vector3(0, 1.10, 0), Vector3(0.48, 0.05, 0.30), Color(0.85, 0.86, 0.88))
	_ob(fs, xf, Vector3(0, 1.67, 0), Vector3(0.2, 0.24, 0.22), haut)
	_ob(fs, xf, Vector3(0, 1.82, 0.01), Vector3(0.25, 0.1, 0.28), helm)
	if rolle == "pilot":
		_ob(fs, xf, Vector3(0, 1.70, 0.12), Vector3(0.2, 0.07, 0.04), Color(0.1, 0.1, 0.1))
	for ax: float in [-1.0, 1.0]:
		var arm := Basis(Vector3.FORWARD, ax * 0.12)
		if rolle == "einweiser":
			arm = Basis(Vector3.FORWARD, ax * 2.5)
		var schulter := Vector3(ax * 0.28, 1.5, 0)
		var a_xf := Transform3D(xf.basis * arm, xf * schulter)
		_ob(fs, a_xf, Vector3(0, -0.3, 0), Vector3(0.12, 0.6, 0.13), jacke)
		if rolle == "einweiser":
			_zyl(sl, a_xf * Vector3(0, -0.6, 0), a_xf * Vector3(0, -1.15, 0), 0.05, 6,
				Color(1.0, 0.45, 0.05))


func _figuren() -> void:
	for i in STAENDE.size():
		var s: Array = STAENDE[i]
		var px: float = s[1]
		var pz: float = s[2]
		var sx := signf(px)
		var u := -sx
		_figur(Transform3D(Basis(Vector3.UP, PI * 0.5 * sx), Vector3(px - u * 1.4, BODEN, pz + 5.6)),
			"techniker")
		_figur(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(px + 1.2, BODEN, pz - 6.8)),
			"boden")
		if i % 3 == 0:
			_figur(Transform3D(Basis(Vector3.UP, -u * PI * 0.5 + 0.3),
				Vector3(px + u * 7.5, BODEN, pz + 2.5)), "pilot")
		if i == 0 or i == 5:
			# Einweiser auf der Fuehrungslinie, Blick zur Bahn, Staebe hoch
			_figur(Transform3D(Basis(Vector3.UP, -sx * PI * 0.5), Vector3(sx * 26.0, BODEN, pz)),
				"einweiser")
	# Vor den Haustueren: zu zweit
	var n := 0
	for t: Array in tueren:
		n += 1
		if n % 3 != 0:
			continue
		var p: Vector3 = t[0]
		var r: float = t[1]
		_figur(Transform3D(Basis(Vector3.UP, 0.4), p + Vector3(r * 0.3, 0, -0.5)), "boden")
		_figur(Transform3D(Basis(Vector3.UP, PI + 0.4), p + Vector3(r * 0.3, 0, 0.6)), "techniker")
	# Auf dem Gehweg
	for k in 10:
		var sx2: float = 1.0 if k % 2 == 0 else -1.0
		var z := 260.0 + float(k) * 68.0 + rng.randf_range(-10.0, 10.0)
		_figur(Transform3D(Basis(Vector3.UP, 0.0 if rng.randf() < 0.5 else PI),
			Vector3(sx2 * 60.4, BODEN, z)), "boden" if k % 3 else "pilot")
	# Wache am Portal
	_figur(Transform3D(Basis(Vector3.UP, PI), Vector3(-53.6, -0.7, -46.5)), "wache", sa)
	_figur(Transform3D(Basis(Vector3.UP, PI + 0.5), Vector3(-58.0, -0.7, -47.5)), "wache", sa)


# --- Boden und Schilder -----------------------------------------------------------------------
func _bodenmarken() -> void:
	# Fuehrungslinien von der Bahnkante zu jedem Stand, gelb mit schwarzem Rand
	for i in STAENDE.size():
		var s: Array = STAENDE[i]
		var px: float = s[1]
		var pz: float = s[2]
		var sx := signf(px)
		var xa := sx * 26.5
		var xe := px + sx * 4.0
		var xm := (xa + xe) * 0.5
		var l := absf(xe - xa)
		_q(st, Vector3(xm, BODEN + 0.012, pz), Vector3(l, 0.02, 0.62), Color(0.04, 0.04, 0.04))
		_q(st, Vector3(xm, BODEN + 0.022, pz), Vector3(l, 0.02, 0.32), C_GELB)
		# Haltebalken an der Nasenposition
		_q(st, Vector3(xe, BODEN + 0.022, pz), Vector3(0.4, 0.02, 3.2), C_GELB)
		# Standnummer auf dem Boden, lesbar von der Bahn aus
		_boden_schrift("%d" % (i + 1), Vector3(sx * 26.5 + sx * 3.2, BODEN + 0.05, pz + 3.2),
			-sx, 0.03, C_GELB)
	# Gehweg vor den Haeusern: weisse Linie
	for sx: float in [-1.0, 1.0]:
		_q(st, Vector3(sx * 61.9, BODEN + 0.02, 600.0), Vector3(0.22, 0.02, 740.0),
			Color(0.80, 0.80, 0.76))


## Haengetafel hinter der ersten Hallenrippe: zum Portal hin der Name der Basis, zur Halle
## hin die Ausfahrt. An Seilen unter dem Bogen.
func _schilder() -> void:
	var tz := RIPPE_AB + 4.0
	var c_tafel := Color(0.09, 0.10, 0.11)
	_q(st, Vector3(0, 44.5, tz), Vector3(48.0, 12.0, 0.4), c_tafel)
	_q(st, Vector3(0, 50.6, tz), Vector3(48.6, 0.3, 0.6), C_GELB)
	_q(st, Vector3(0, 38.4, tz), Vector3(48.6, 0.3, 0.6), C_GELB)
	for sx: float in [-1.0, 1.0]:
		_q(st, Vector3(sx * 20.0, 53.4, tz), Vector3(0.12, 5.4, 0.12), C_STAHL)
	_schild("ADLERHORST", Vector3(0, 46.2, tz - 0.25), Vector3(0, 0, -1), 0.07,
		Color(0.96, 0.92, 0.84))
	_schild("HALLE 1  ·  STANDPLÄTZE 1 – 10", Vector3(0, 40.4, tz - 0.25), Vector3(0, 0, -1),
		0.022, Color(0.95, 0.78, 0.25))
	_schild("AUSFAHRT", Vector3(0, 44.5, tz + 0.25), Vector3(0, 0, 1), 0.06,
		Color(0.40, 0.95, 0.55))
	_kol(Vector3(0, 44.5, tz), Vector3(48.0, 12.0, 0.4))


func _schild(text: String, pos: Vector3, zu: Vector3, pixel: float, farbe: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = _schrift()
	l.font_size = 96
	l.pixel_size = pixel
	l.modulate = farbe
	l.outline_size = 0
	l.position = pos
	l.rotation.y = atan2(zu.x, zu.z)
	l.double_sided = false
	l.shaded = false
	node.add_child(l)


## Schrift flach auf dem Boden, Fuss zur Bahn (zur_bahn = Vorzeichen der x-Richtung).
func _boden_schrift(text: String, pos: Vector3, zur_bahn: float, pixel: float,
		farbe: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = _schrift()
	l.font_size = 96
	l.pixel_size = pixel
	l.modulate = farbe
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	# liegt flach (Lesesicht nach oben); die Oberkante der Zeichen zeigt von der Bahn weg
	l.basis = Basis(Vector3.UP, zur_bahn * PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5)
	l.position = pos
	node.add_child(l)


static func _schrift() -> Font:
	if _font == null:
		_font = load("res://fonts/TitilliumWeb-Bold.ttf")
	return _font
