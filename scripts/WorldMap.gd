class_name WorldMap
extends Control
## Die KARTE (Taste M im Flug): Reliefkarte der ganzen Insel mit Vektor-Ebenen darueber.
##
## ZWEI SCHICHTEN:
##   1. RASTER (generate_image, einmal im Hintergrund-Thread): Gelaendefarben, Relief,
##      Hoehenlinien, Meerestiefe, Kueste, Seen. Main erzeugt erst 512 px, dann 1024 px.
##   2. VEKTOREN (zeichne_ebenen, jedes Bild neu): Fluesse, Strassen und die ECHTEN
##      Hausgrundrisse aus CityBuilder, Start- und Landebahnen mit ihrem wahren Kurs,
##      Reichweiten der Flugabwehr (verschwinden, sobald die Stellung zerstoert ist),
##      Ziele, die eigene Flugspur und eine Kurslinie. Was davon gezeichnet wird, haengt am
##      Massstab (Meter je Bildpunkt), nicht an der Zoomstufe — so nutzt die Eck-Minimap
##      im HUD dieselbe Funktion und zeigt automatisch das, was bei ihrem Massstab traegt.
##
## DESIGN-SPRACHE (crisp auf 1440p+): alle Masse skalieren mit Viewport-Hoehe (ui = vh/1080),
## Projekt-Font Titillium, gerundetes Panel mit interner Titelleiste, Planquadrate (A-N,
## 1-14, je 5 km) statt nacktem Gitter, Windrose, Massstab mit Wechselfeldern, Legende.

const WORLD_R := 34000.0       # halbe Kartenbreite (Sturmkap bis 32,1 km + Rand)
const F_BOLD := preload("res://fonts/TitilliumWeb-Bold.ttf")
const F_SEMI := preload("res://fonts/TitilliumWeb-SemiBold.ttf")

const C_PANEL := Color(0.055, 0.065, 0.085, 0.97)
const C_HEADER := Color(0.085, 0.10, 0.13, 1.0)
const C_BORDER := Color(0.90, 0.93, 0.97, 0.75)
const C_TEXT := Color(0.95, 0.97, 1.0)
const C_MUTED := Color(0.62, 0.68, 0.78)
const C_PLAYER := Color(1.0, 0.36, 0.22)
const C_FLUSS := Color(0.22, 0.50, 0.68)
const C_STRASSE := Color(0.20, 0.19, 0.19)
const C_HAUS := Color(0.78, 0.72, 0.64)
const C_HAUS_RAND := Color(0.30, 0.26, 0.24)
const C_BAHN := Color(0.20, 0.21, 0.23)
const C_GEFAHR := Color(1.0, 0.24, 0.18)
const C_ZIEL := Color(1.0, 0.82, 0.25)
const C_SPUR := Color(1.0, 0.62, 0.30)
const QUADRAT := 5000.0        # Planquadrat-Kante (m)
const BUCHSTABEN := "ABCDEFGHIJKLMN"
const BAHN_LEN := 900.0        # = Main.RWY_LEN
const BAHN_B := 45.0           # Bahn + Schultern (Main.RWY_W + 2 * RWY_SHOULDER)

var _tex: ImageTexture
var _airfields: Array = []
var _pois: Array = []
var _player: Node3D = null
var _flug: Node = null         # FlightController: liefert das aktuelle Flugzeug (.aircraft)
var _fluesse: Array = []       # [PackedVector2Array (Welt x/z), Breite m, Rect2 Huelle]
var _spur := PackedVector2Array()
var _orte: Array = []          # [Vector2 Mitte, Radius m] der Siedlungs-POIs
var _gr_strassen: Array = []   # [Rect2 Huelle, Array Strassen] je Viertel (siehe _gruppen_pruefen)
var _gr_haeuser: Array = []
var _n_strassen := -1
var _n_haeuser := -1
var _spur_id := 0
var _map_rect := Rect2()
# Zoom (Mausrad / +-): 1 = ganze Insel, gezoomt = spielerzentriert (geklemmt)
const ZOOMS := [1.0, 2.5, 6.0]
var _zoom_i := 0
var _win_min := Vector2.ZERO   # sichtbares Weltfenster in UV [0..1]
var _win_size := Vector2.ONE
var _label_rects: Array = []   # Label-Entzerrung (Overview-Cluster)


## Das Kartenbild: eine RELIEFKARTE der echten Welt.
##
## FARBEN AUS DER WELT SELBST: eingefaerbt wird mit TerrainWorld._face_color und
## wald_anteil — denselben Funktionen, die Chunks und Fernschuerze faerben. Die Karte zeigt
## damit, was man aus dem Cockpit sieht: Biome, Fels, Schnee, den Vulkankegel, Waelder.
##
## FARBE GROB, FORM FEIN. Die Farben liegen auf einem eigenen Raster von FARB_RASTER Metern
## und werden bilinear dazwischen gemischt; Hoehe, Kueste, Relief und Hoehenlinien kommen
## aus dem feinen Raster je Bildpunkt. Das ist zweimal richtig:
##   - SCHOENER: die Bodenfarben tragen Flecken von wenigen Dutzend Metern (Erdflecken,
##     Waldraender, Heide). Punktweise abgetastet bei 66-133 m je Bildpunkt wurde daraus
##     Salz und Pfeffer — die Karte sah aus wie verrauschtes Satellitenbild, nicht wie Karte.
##   - SCHNELLER: _face_color und wald_anteil sind der teure Teil, und sie skalieren nicht
##     ueber vier Faeden hinaus (sie laufen je Punkt durch geteilte Arrays aus
##     Woerterbuechern, jeder Zugriff zaehlt Referenzen atomar; gemessen 1 Faden 5,6 s,
##     4 Faeden 3,9 s, 12 Faeden 5,6 s bei 512 px). Auf dem Grobraster sind es ein
##     Sechzehntel der Aufrufe.
##
## DARAUF: Reliefschattierung (Licht aus Nordwest, Schatten leicht blau, Licht leicht warm
## wie auf einer topografischen Karte), Hoehenlinien alle 50 m (jede fuenfte kraeftiger),
## Tiefenverlauf im Meer, heller Brandungssaum, Strandsaum, dunkle Kuestenlinie und die
## Inlandseen. Fluesse, Bahnen, Orte und Gefahrenzonen zeichnet _draw als Vektoren
## darueber — die bleiben in jeder Zoomstufe scharf.
##
## ZUSTAENDE JE PUNKT (Klasse): 0 Meer, 1 See, 2 Land.

## Laufzeit der letzten Erzeugung je Stufe (kumuliert, ms) — fuer tools/_karte_zeit.gd.
static var stufen_ms: Array = []

const FARB_RASTER := 250.0     # m zwischen zwei Farbproben
const RELIEF_BASIS := 130.0    # m Messbasis der Schattierung (unabhaengig von der Aufloesung)
const UEBERHOEHUNG := 3.2      # Relief ueberhoeht, sonst verschwinden 100-m-Huegel
const LINIEN_M := 50.0         # Hoehenlinien-Abstand
const GLATT_M := 200.0         # Glaettung der Hoehen fuer Relief/Hoehenlinien
const FARB_RUHE := 0.4         # Anteil des weichen Farbfelds (siehe generate_image)


## `stopp` = [bool], von aussen auf true gesetzt bricht die Erzeugung ab (jede Zeile
## kehrt sofort zurueck, Rueckgabe null). Sonst wartete Main beim Beenden bis zu einer
## Minute auf eine Karte, die niemand mehr sieht.
static func generate_image(t: TerrainWorld, kante := 1024, world_r := WORLD_R,
		vorrang := true, faeden := 4, stopp: Array = [false]) -> Image:
	var zelle := 2.0 * world_r / float(kante - 1)
	var sperre := Mutex.new()
	var t0 := Time.get_ticks_usec()
	stufen_ms.clear()
	# Seen: [x, z, r^2, Spiegel]. _rmax statt r beim gelappten Bergsee (sein Arm reicht
	# ueber r hinaus) — wie TerrainWorld._submerged.
	var seen: Array = []
	for l in t.lakes:
		var lp: Vector3 = l["pos"]
		var rr: float = float(l.get("_rmax", l["r"]))
		seen.append([lp.x, lp.z, rr * rr, float(l["surf"])])

	# --- 1. Hoehen + Klasse, fein (height_at ist frei von Zaehler-Konkurrenz: alle Faeden)
	var zeilen_h: Array = []
	zeilen_h.resize(kante)
	var zeilen_k: Array = []
	zeilen_k.resize(kante)
	var g1 := WorkerThreadPool.add_group_task(func(py: int) -> void:
		if stopp[0]:
			return
		var r := PackedFloat32Array()
		r.resize(kante)
		var k := PackedByteArray()
		k.resize(kante)
		var wz := (float(py) / float(kante - 1) * 2.0 - 1.0) * world_r
		for px in kante:
			var wx := (float(px) / float(kante - 1) * 2.0 - 1.0) * world_r
			var h := t.height_at(wx, wz)
			r[px] = h
			var art := 2
			if h < TerrainWorld.SEA_Y:
				art = 0
			else:
				for se in seen:
					var dx: float = wx - float(se[0])
					var dz: float = wz - float(se[1])
					if h < float(se[3]) and dx * dx + dz * dz < float(se[2]):
						art = 1
						break
			k[px] = art
		sperre.lock()
		zeilen_h[py] = r
		zeilen_k[py] = k
		sperre.unlock(), kante, -1, vorrang, "Weltkarte Hoehen")
	WorkerThreadPool.wait_for_group_task_completion(g1)
	if stopp[0]:
		return null
	var hs := PackedFloat32Array()
	var ks := PackedByteArray()
	for i in kante:
		hs.append_array(zeilen_h[i])
		ks.append_array(zeilen_k[i])
	stufen_ms.append((Time.get_ticks_usec() - t0) / 1000.0)

	# GEGLAETTETE HOEHEN (fuer Relief, Hoehenlinien UND die Farbwahl): auf GLATT_M
	# herunter und kubisch wieder hoch.
	# Punktgenau schattiert sah jeder 20-m-Huegel wie zerknitterte Alufolie aus, die
	# Hoehenlinien zerfielen im welligen Gelaende zu Kruemeln, und _face_color machte aus
	# jeder steilen 60-m-Flanke einen Felsfleck — die ganze Insel war braun gesprenkelt.
	# Eine Karte GENERALISIERT: Fels ist, was auf 200 m steil ist. Kueste und Wasser
	# kommen weiter aus dem feinen Raster.
	var h_img := Image.create_from_data(kante, kante, false, Image.FORMAT_RF, hs.to_byte_array())
	var klein := clampi(roundi(2.0 * world_r / GLATT_M), 16, kante)
	h_img.resize(klein, klein, Image.INTERPOLATE_LANCZOS)
	h_img.resize(kante, kante, Image.INTERPOLATE_CUBIC)
	var hg := h_img.get_data().to_float32_array()

	# --- 2. Farben, grob (teuer, nur vier Faeden — Begruendung oben) ------------------
	var schritt := maxi(1, roundi(FARB_RASTER / zelle))
	var n := ceili(float(kante - 1) / float(schritt)) + 1
	var zeilen_c: Array = []
	zeilen_c.resize(n)
	var g2 := WorkerThreadPool.add_group_task(func(j: int) -> void:
		if stopp[0]:
			return
		var z := _grobfarben(t, hs, hg, ks, j, n, schritt, kante, world_r, zelle)
		sperre.lock()
		zeilen_c[j] = z
		sperre.unlock(), n, faeden, vorrang, "Weltkarte Farben")
	WorkerThreadPool.wait_for_group_task_completion(g2)
	if stopp[0]:
		return null
	var cs := PackedColorArray()
	for z in zeilen_c:
		cs.append_array(z)
	stufen_ms.append((Time.get_ticks_usec() - t0) / 1000.0)

	# --- 2b. Glaetten, nativ ueber Image.resize (C++, Millisekunden) --------------------
	# FARBEN: vormultipliziert mit der Landmaske, kubisch auf volle Groesse — bilinear
	# zeichnete das Grobraster als Karomuster nach. Beim Zurueckteilen durch Alpha zaehlen
	# dann nur Landproben, das Meerblau laeuft nicht in die Kueste.
	var f_img := Image.create(n, n, false, Image.FORMAT_RGBAF)
	for j in n:
		for i in n:
			var c := cs[j * n + i]
			f_img.set_pixel(i, j, Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a))
	# RUHIGER: ein zweites, stark weichgezeichnetes Farbfeld (~1 km), zu FARB_RUHE
	# untergemischt. Die Insel ist ueberall huegelig, und jede Kuppe ueber 50 m traegt
	# Fels — punktgenau gibt das ein Tarnmuster. Gemischt bleiben Biome, Waelder und
	# Gebirge lesbar, nur das Gesprenkel dazwischen tritt zurueck.
	var f_weich := f_img.duplicate() as Image
	f_weich.resize(maxi(8, int(n / 4.0)), maxi(8, int(n / 4.0)), Image.INTERPOLATE_LANCZOS)
	f_weich.resize(kante, kante, Image.INTERPOLATE_CUBIC)
	f_img.resize(kante, kante, Image.INTERPOLATE_CUBIC)
	var fs := f_img.get_data().to_float32_array()
	var fw := f_weich.get_data().to_float32_array()
	for i in fs.size():
		fs[i] = lerpf(fs[i], fw[i], FARB_RUHE)
	stufen_ms.append((Time.get_ticks_usec() - t0) / 1000.0)

	# --- 3. Zusammensetzen (billig, alle Faeden) --------------------------------------
	var basis := maxi(1, roundi(RELIEF_BASIS / zelle))
	var zeilen: Array = []
	zeilen.resize(kante)
	var g3 := WorkerThreadPool.add_group_task(func(py: int) -> void:
		if stopp[0]:
			return
		var z := _zeile(hs, hg, ks, fs, py, kante, basis, zelle)
		sperre.lock()
		zeilen[py] = z
		sperre.unlock(), kante, -1, vorrang, "Weltkarte Relief")
	WorkerThreadPool.wait_for_group_task_completion(g3)
	if stopp[0]:
		return null
	var daten := PackedByteArray()
	for z in zeilen:
		daten.append_array(z)
	var img := Image.create_from_data(kante, kante, false, Image.FORMAT_RGB8, daten)
	# MIPMAPS GLEICH HIER IM THREAD: in der Uebersicht wird das Bild fast auf die Haelfte
	# verkleinert, ohne Mipmaps flimmern dort Hoehenlinien und Kueste.
	img.generate_mipmaps()
	stufen_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
	return img


# Kartenpalette (sRGB, wie die Vertexfarben des Gelaendes).
const K_TIEF := Color(0.07, 0.21, 0.38)
const K_FLACH := Color(0.20, 0.52, 0.63)
const K_SEE := Color(0.24, 0.52, 0.66)
const K_BRANDUNG := Color(0.70, 0.88, 0.88)
const K_STRAND := Color(0.90, 0.83, 0.62)
const K_WALD := Color(0.13, 0.27, 0.15)        # etwas heller als Main.FERN_WALD: Karte, nicht Nacht
const K_SCHATTEN := Color(0.78, 0.84, 1.0)     # Tint der Schattenseite
const K_SONNE := Color(1.0, 0.97, 0.90)        # Tint der Lichtseite
const K_LICHT := Vector3(-0.55, 0.62, -0.55)   # Licht aus Nordwest (-x West, -z Nord)


## Eine Zeile des Farb-Grobrasters. Wasserpunkte bekommen Alpha 0 und zaehlen beim
## Mischen nicht mit — sonst liefe Meerblau in die Kueste.
static func _grobfarben(t: TerrainWorld, hs: PackedFloat32Array, hg: PackedFloat32Array,
		ks: PackedByteArray, j: int, n: int, schritt: int, kante: int, world_r: float,
		zelle: float) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(n)
	var py := mini(j * schritt, kante - 1)
	var wz := (float(py) / float(kante - 1) * 2.0 - 1.0) * world_r
	var o := py * kante
	var o_hoch := maxi(py - 1, 0) * kante
	var o_tief := mini(py + 1, kante - 1) * kante
	for i in n:
		var px := mini(i * schritt, kante - 1)
		if ks[o + px] != 2:
			out[i] = Color(0, 0, 0, 0)
			continue
		var wx := (float(px) / float(kante - 1) * 2.0 - 1.0) * world_r
		# Hoehe fein nur am Wasser (Strand, Uferkies), sonst geglaettet; Neigung immer
		# aus dem geglaetteten Raster.
		var h := hs[o + px]
		if h > TerrainWorld.SEA_Y + 8.0:
			h = maxf(hg[o + px], TerrainWorld.SEA_Y + 8.0)
		var nt := Vector3(hg[o + maxi(px - 1, 0)] - hg[o + mini(px + 1, kante - 1)],
			2.0 * zelle, hg[o_hoch + px] - hg[o_tief + px]).normalized()
		var c := t._face_color(Vector3(wx, h, wz), nt.y, zelle, nt)
		var w := t.wald_anteil(wx, wz, h, nt.y)
		if w > 0.0:
			c = c.lerp(K_WALD, clampf(w * 0.9, 0.0, 0.9))
		out[i] = Color(c.r, c.g, c.b, 1.0)
	return out


## Fertige Kartenzeile: Wasser/Kueste aus dem feinen Raster (hs, ks), Farbe aus dem
## geglaetteten Farbfeld (fs, vormultipliziert), Relief und Hoehenlinien aus den
## geglaetteten Hoehen (hg).
static func _zeile(hs: PackedFloat32Array, hg: PackedFloat32Array, ks: PackedByteArray,
		fs: PackedFloat32Array, py: int, kante: int, basis: int, zelle: float) -> PackedByteArray:
	var reihe := Image.create(kante, 1, false, Image.FORMAT_RGB8)
	var licht := K_LICHT.normalized()
	var o := py * kante
	var o_hoch := maxi(py - 1, 0) * kante
	var o_tief := mini(py + 1, kante - 1) * kante
	var o_bn := maxi(py - basis, 0) * kante
	var o_bs := mini(py + basis, kante - 1) * kante
	var fallback := Color(0.42, 0.55, 0.30)   # Wiese, falls ringsum nur Wasser
	for px in kante:
		var art := ks[o + px]
		var h := hs[o + px]
		var pl := maxi(px - 1, 0)
		var pr := mini(px + 1, kante - 1)
		var nb_min := mini(mini(ks[o + pl], ks[o + pr]), mini(ks[o_hoch + px], ks[o_tief + px]))
		var nb_max := maxi(maxi(ks[o + pl], ks[o + pr]), maxi(ks[o_hoch + px], ks[o_tief + px]))
		var c: Color
		if art == 0:
			# MEER: Tiefe als Verlauf, an der Kueste heller Brandungssaum.
			c = K_FLACH.lerp(K_TIEF, smoothstep(0.0, 40.0, TerrainWorld.SEA_Y - h))
			if nb_max == 2:
				c = c.lerp(K_BRANDUNG, 0.6)
		elif art == 1:
			c = K_SEE
			if nb_max == 2:
				c = c.darkened(0.30)
		else:
			var fi := (o + px) * 4
			var a := fs[fi + 3]
			if a > 0.03:
				c = Color(clampf(fs[fi] / a, 0.0, 1.0), clampf(fs[fi + 1] / a, 0.0, 1.0),
					clampf(fs[fi + 2] / a, 0.0, 1.0))
			else:
				c = fallback
			# Strandsaum: das Farbfeld ist zu grob fuer den schmalen Sand am Wasser.
			if h < TerrainWorld.SEA_Y + 2.6:
				c = c.lerp(K_STRAND, 1.0 - smoothstep(TerrainWorld.SEA_Y + 0.8,
					TerrainWorld.SEA_Y + 2.6, h))
			# Relief: Normale aus den geglaetteten Hoehen ueber eine feste Weltbasis
			var g := hg[o + px]
			var hl := hg[o + maxi(px - basis, 0)]
			var hr := hg[o + mini(px + basis, kante - 1)]
			var ns := Vector3((hl - hr) * UEBERHOEHUNG, 2.0 * zelle * float(basis),
				(hg[o_bn + px] - hg[o_bs + px]) * UEBERHOEHUNG).normalized()
			var hell := clampf(1.0 + (ns.dot(licht) - licht.y) * 1.3, 0.55, 1.25)
			if hell < 1.0:
				var k := 1.0 - hell
				c = Color(c.r * hell * lerpf(1.0, K_SCHATTEN.r, k),
					c.g * hell * lerpf(1.0, K_SCHATTEN.g, k),
					c.b * hell * lerpf(1.0, K_SCHATTEN.b, k))
			else:
				var k := (hell - 1.0) / 0.25
				c = Color(c.r * hell, c.g * hell, c.b * hell).lerp(
					Color(c.r * K_SONNE.r, c.g * K_SONNE.g, c.b * K_SONNE.b) * hell, k)
			# Hoehenlinien (geglaettet), jede fuenfte kraeftiger. AUSGEDUENNT, wo sie enger
			# als drei Bildpunkte laegen — sonst werden steile Flanken zu Holzmaserung
			# (so macht es jede Wanderkarte: im Steilen bleiben nur die Zaehllinien).
			if g > 2.0:
				var stufe := floori(g / LINIEN_M)
				var s_r := floori(hg[o + pr] / LINIEN_M)
				var s_s := floori(hg[o_tief + px] / LINIEN_M)
				if stufe != s_r or stufe != s_s:
					var oben := maxi(stufe, maxi(s_r, s_s))
					var steig := Vector2(hl - hr, hg[o_bn + px] - hg[o_bs + px]).length() \
						/ (2.0 * zelle * float(basis))
					var abstand := LINIEN_M / maxf(steig * zelle, 0.0001)
					if oben % 5 == 0:
						c = c.darkened(0.24 * clampf((abstand * 5.0 - 2.0) / 3.0, 0.0, 1.0))
					else:
						c = c.darkened(0.10 * clampf((abstand - 2.5) / 3.0, 0.0, 1.0))
			# Kuesten- und Uferlinie
			if nb_min == 0:
				c = c.darkened(0.45)
			elif nb_min == 1:
				c = c.darkened(0.25)
		reihe.set_pixel(px, 0, c)
	return reihe.get_data()


func setup(map_img: Image, airfields: Array, pois: Array, player: Node3D,
		terrain: TerrainWorld = null, flug: Node = null) -> void:
	set_image(map_img)
	_airfields = airfields
	_pois = pois
	_orte.clear()
	for poi in pois:
		if float(poi.get("radius", 0.0)) > 0.0:
			var pw: Vector3 = poi["pos"]
			_orte.append([Vector2(pw.x, pw.z), float(poi["radius"])])
	_player = player
	_flug = flug
	_fluesse.clear()
	if terrain != null:
		for rv in terrain.rivers:
			var pts: PackedVector3Array = rv["pts"]
			var p2 := PackedVector2Array()
			var huelle := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
			for q in pts:
				p2.append(Vector2(q.x, q.z))
				huelle = huelle.expand(Vector2(q.x, q.z))
			_fluesse.append([p2, float(rv.get("w", 20.0)), huelle.grow(200.0)])
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	visible = false


## Kartenbild austauschen (die feine Stufe ersetzt die grobe, siehe Main).
func set_image(map_img: Image) -> void:
	_tex = ImageTexture.create_from_image(map_img)
	queue_redraw()


func textur() -> Texture2D:
	return _tex


func set_player(p: Node3D) -> void:
	_player = p


## Das Flugzeug, das gerade fliegt — ueber den FlightController, denn der baut es bei
## jedem Start und jedem Reset neu; ein einmal gemerkter Knoten waere danach tot.
func flieger() -> Node3D:
	if _flug != null and is_instance_valid(_flug):
		var ac = _flug.get("aircraft")
		if ac is Node3D and is_instance_valid(ac) and (ac as Node3D).is_inside_tree():
			return ac
	if _player != null and is_instance_valid(_player) and _player.is_inside_tree():
		return _player
	return null


func _process(_dt: float) -> void:
	_spur_aufzeichnen()
	if visible:
		queue_redraw()   # Spieler-Pfeil bewegt sich live


## FLUGSPUR: alle 120 m ein Punkt, je Flug (neues Flugzeug = neue Spur, also auch nach
## Reset). Gedeckelt auf 2400 Punkte = fast 300 km, aeltere fallen vorne heraus.
func _spur_aufzeichnen() -> void:
	var ac := flieger()
	if ac == null:
		return
	if ac.get_instance_id() != _spur_id:
		_spur_id = ac.get_instance_id()
		_spur.clear()
	var p := Vector2(ac.global_position.x, ac.global_position.z)
	var letzte := _spur[_spur.size() - 1] if not _spur.is_empty() else Vector2.INF
	if not letzte.is_finite() or p.distance_squared_to(letzte) > 120.0 * 120.0:
		# SPRUNG (Teleport, Respawn am Platz): Luecke statt eines Strichs quer ueber die
		# Insel. Eine Luecke ist ein Punkt im Unendlichen, den das Zeichnen ueberspringt.
		if letzte.is_finite() and p.distance_squared_to(letzte) > 1500.0 * 1500.0:
			_spur.append(Vector2.INF)
		_spur.append(p)
		if _spur.size() > 2400:
			_spur = _spur.slice(400)


func _world_to_map(w: Vector3) -> Vector2:
	var uv := Vector2(w.x / WORLD_R * 0.5 + 0.5, w.z / WORLD_R * 0.5 + 0.5)
	return _map_rect.position + (uv - _win_min) / _win_size * _map_rect.size


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_i = mini(_zoom_i + 1, ZOOMS.size() - 1)
			get_viewport().set_input_as_handled()   # nicht an die Flug-Kamera durchreichen
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_i = maxi(_zoom_i - 1, 0)
			get_viewport().set_input_as_handled()


## Sichtfenster (UV) aus Zoom + Spielerposition bestimmen; am Weltrand geklemmt.
func _update_window() -> void:
	var z: float = ZOOMS[_zoom_i]
	var half := 0.5 / z
	var c := Vector2(0.5, 0.5)
	var ac := flieger()
	if z > 1.0 and ac != null:
		var pp := ac.global_position
		c = Vector2(pp.x / WORLD_R * 0.5 + 0.5, pp.z / WORLD_R * 0.5 + 0.5)
	c = c.clamp(Vector2(half, half), Vector2(1.0 - half, 1.0 - half))
	_win_min = c - Vector2(half, half)
	_win_size = Vector2(half, half) * 2.0


## Planquadrat einer Weltposition, z. B. "F7" (Spalten A-N von West, Zeilen 1-14 von Nord).
static func planquadrat(w: Vector3) -> String:
	var sp := clampi(floori((w.x + WORLD_R) / QUADRAT), 0, BUCHSTABEN.length() - 1)
	var ze := clampi(floori((w.z + WORLD_R) / QUADRAT), 0, 13)
	return "%s%d" % [BUCHSTABEN[sp], ze + 1]


# --- Zeichenhelfer mit Beschnitt ------------------------------------------------------
# CanvasItem kennt keinen Beschnitt je Zeichenaufruf. Was ueber den Kartenrand ragt
# (ein Fluss, ein Gefahrenkreis, die Spur), laege sonst auf dem Panelrand oder — bei der
# Minimap — mitten im HUD. Deshalb wird jede Geometrie selbst auf das Rechteck geschnitten.

## Strecke a-b auf das Rechteck schneiden (Liang-Barsky). Leer = ganz draussen.
## Laeuft in der Minimap hunderte Male je Bild: der haeufigste Fall (ganz innen) geht
## ohne Rechnung durch, der Rest ohne Hilfs-Arrays.
static func _clip_strecke(a: Vector2, b: Vector2, r: Rect2) -> PackedVector2Array:
	if r.has_point(a) and r.has_point(b):
		return PackedVector2Array([a, b])
	if (a.x < r.position.x and b.x < r.position.x) or (a.x > r.end.x and b.x > r.end.x) \
			or (a.y < r.position.y and b.y < r.position.y) or (a.y > r.end.y and b.y > r.end.y):
		return PackedVector2Array()
	var t := Vector2(0.0, 1.0)
	var dx := b.x - a.x
	var dy := b.y - a.y
	t = _lb(-dx, a.x - r.position.x, t)
	t = _lb(dx, r.end.x - a.x, t)
	t = _lb(-dy, a.y - r.position.y, t)
	t = _lb(dy, r.end.y - a.y, t)
	if t.x > t.y:
		return PackedVector2Array()
	var d := b - a
	return PackedVector2Array([a + d * t.x, a + d * t.y])


## Ein Liang-Barsky-Schritt auf (t0, t1); verworfen = t0 > t1.
static func _lb(p: float, q: float, t: Vector2) -> Vector2:
	if absf(p) < 1e-9:
		return t if q >= 0.0 else Vector2(1.0, 0.0)
	var k := q / p
	if p < 0.0:
		t.x = maxf(t.x, k)
	else:
		t.y = minf(t.y, k)
	return t


## Linienzug auf das Rechteck geschnitten, als Liste zusammenhaengender Stuecke (je ein
## Zug: saubere Gelenke statt Luecken zwischen Einzelstrichen). Liegt alles innen, geht
## der Zug unveraendert durch.
static func _laeufe(pts: PackedVector2Array, r: Rect2) -> Array:
	var innen := true
	for q in pts:
		if not r.has_point(q):
			innen = false
			break
	if innen:
		return [pts]
	var out: Array = []
	var lauf := PackedVector2Array()
	for i in pts.size() - 1:
		var s := _clip_strecke(pts[i], pts[i + 1], r)
		if s.is_empty():
			if lauf.size() > 1:
				out.append(lauf)
			lauf = PackedVector2Array()
			continue
		if lauf.is_empty() or not lauf[lauf.size() - 1].is_equal_approx(s[0]):
			if lauf.size() > 1:
				out.append(lauf)
			lauf = PackedVector2Array([s[0]])
		lauf.append(s[1])
	if lauf.size() > 1:
		out.append(lauf)
	return out


## Flaeche beschnitten fuellen.
static func _flaeche(ci: CanvasItem, pts: PackedVector2Array, r: Rect2, col: Color) -> void:
	var box := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		box = box.expand(q)
	if not r.intersects(box):
		return
	if r.encloses(box):
		_poly(ci, pts, col)
		return
	var rp := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y)])
	for teil in Geometry2D.intersect_polygons(pts, rp):
		if (teil as PackedVector2Array).size() >= 3:
			_poly(ci, teil, col)


## Nur zeichnen, was sich triangulieren laesst. Beschnittene Kreise und winzige Grundrisse
## (unter einem Bildpunkt) liefern gelegentlich entartete Polygone; draw_colored_polygon
## meldet dann je Bild "triangulation failed" ins Log, und das waeren im Flug sechzig
## Meldungen pro Sekunde aus der Minimap.
static func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if Geometry2D.triangulate_polygon(pts).is_empty():
		return
	ci.draw_colored_polygon(pts, col)


static func _kreis_pts(m: Vector2, rad: float, n := 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(m + Vector2(cos(a), sin(a)) * rad)
	return pts


static func _gestrichelt(ci: CanvasItem, pts: PackedVector2Array, r: Rect2, col: Color,
		breite: float, geschlossen: bool) -> void:
	var n := pts.size() if geschlossen else pts.size() - 1
	for i in n:
		if i % 2 == 1:
			continue
		var s := _clip_strecke(pts[i], pts[(i + 1) % pts.size()], r)
		if not s.is_empty():
			ci.draw_line(s[0], s[1], col, breite, true)


## Gedrehtes Rechteck (Mitte, halbe Groesse, Winkel) in Kartenpunkten.
static func _box(m: Vector2, halb: Vector2, winkel: float) -> PackedVector2Array:
	var ax := Vector2(cos(winkel), sin(winkel))
	var ay := Vector2(-ax.y, ax.x)
	return PackedVector2Array([m - ax * halb.x - ay * halb.y, m + ax * halb.x - ay * halb.y,
		m + ax * halb.x + ay * halb.y, m - ax * halb.x + ay * halb.y])


## ALLE VEKTOR-EBENEN in ein Kartenrechteck zeichnen — fuer die grosse Karte UND die
## Eck-Minimap (FlightHud ruft das mit sich selbst als `ci` auf). Welche Ebene erscheint,
## entscheidet der Massstab `mpp` (Meter je Bildpunkt): Strassen und Hausgrundrisse erst,
## wenn sie mehr als Rauschen sind; Bahnen als echtes Rechteck, sobald sie laenger als
## ein Symbol waeren. Rueckgabe: [Platzname, belegtes Rechteck] je gezeichnetem Platz,
## damit Namen ausweichen — und der eigene Name neben SEINER Bahn landet statt darauf.
func zeichne_ebenen(ci: CanvasItem, rect: Rect2, win_min: Vector2, win_size: Vector2,
		ui: float, eck := false) -> Array:
	var belegt: Array = []
	var mpp := win_size.x * WORLD_R * 2.0 / rect.size.x
	var sicht := Rect2(win_min.x * 2.0 * WORLD_R - WORLD_R, win_min.y * 2.0 * WORLD_R - WORLD_R,
		win_size.x * 2.0 * WORLD_R, win_size.y * 2.0 * WORLD_R)
	# Welt (x, z) -> Kartenpunkt = o + Vector2(x, z) * k2. Bewusst KEIN Lambda: die
	# Minimap zeichnet jedes Bild, und ein Callable-Aufruf je Punkt kostete dort messbar.
	var k2 := rect.size / sicht.size
	var o := rect.position - sicht.position * k2
	_gruppen_pruefen()

	# --- Fluesse: Breite nach Massstab, nie duenner als ein feiner Strich ----------------
	for fl in _fluesse:
		if not sicht.intersects(fl[2]):
			continue
		var welt: PackedVector2Array = fl[0]
		var pts := PackedVector2Array()
		for q in welt:
			pts.append((o + Vector2(q.x, q.y) * k2))
		var b := clampf(float(fl[1]) / mpp, 1.2 * ui, 6.0 * ui)
		var laeufe := _laeufe(pts, rect)   # EINMAL schneiden, zweimal zeichnen
		for lauf in laeufe:
			ci.draw_polyline(lauf, C_FLUSS.darkened(0.25), b + 1.2 * ui, true)
		for lauf in laeufe:
			ci.draw_polyline(lauf, C_FLUSS.lightened(0.12), b, true)

	# --- Orte: Flaeche in der Uebersicht, echte Strassen + Haeuser beim Hineinzoomen -----
	var nah := mpp < 32.0
	for ot in _orte:
		var pw: Vector2 = ot[0]
		var ort: float = ot[1]
		if not sicht.grow(ort).has_point(pw):
			continue
		var m: Vector2 = o + pw * k2
		var rad := maxf(ort / mpp, 2.5 * ui)
		_flaeche(ci, _kreis_pts(m, rad, 28), rect, Color(0.62, 0.56, 0.50, 0.30 if nah else 0.55))
	if mpp < 70.0:
		for gr in _gr_strassen:
			if not sicht.intersects(gr[0]):
				continue
			for st in gr[1]:
				var a: Vector2 = st[0]
				var b: Vector2 = st[1]
				var br: float = st[2]
				if br < 10.0 and not nah:
					continue   # Wohnstrassen erst nah — sonst wird der Kern ein grauer Fleck
				var s := _clip_strecke(o + a * k2, o + b * k2, rect)
				if not s.is_empty():
					ci.draw_line(s[0], s[1], C_STRASSE, maxf(br / mpp, 1.0 * ui), true)
	if nah:
		var sh := sicht.grow(60.0)
		for gr in _gr_haeuser:
			if not sicht.intersects(gr[0]):
				continue
			for h in gr[1]:
				_haus(ci, h, sh, o, k2, mpp, rect, ui)

	# --- Start- und Landebahnen ------------------------------------------------------
	var bahn_px := BAHN_LEN / mpp
	for af in _airfields:
		var ap: Vector3 = af["pos"]
		var m: Vector2 = (o + Vector2(ap.x, ap.z) * k2)
		if not rect.grow(bahn_px).has_point(m):
			continue
		var hd: float = float(af.get("heading", 0.0))
		# Bahn laeuft im lokalen Z des Platzes: Welt (sin hd, cos hd)
		var laengs := Vector2(sin(hd), cos(hd))
		var winkel := laengs.angle()
		var farbe: Color = af.get("color", Color.WHITE)
		if bahn_px > 16.0 * ui:
			var halb := Vector2(BAHN_LEN * 0.5 / mpp, maxf(BAHN_B * 0.5 / mpp, 1.6 * ui))
			_flaeche(ci, _box(m, halb + Vector2(1.5, 1.5) * ui, winkel), rect, farbe.darkened(0.2))
			_flaeche(ci, _box(m, halb, winkel), rect, C_BAHN)
			if bahn_px > 40.0 * ui:
				var e := laengs * (halb.x * 0.86)
				_gestrichelt(ci, PackedVector2Array([m - e, m - e * 0.6, m - e * 0.2, m + e * 0.2,
					m + e * 0.6, m + e]), rect, Color(1, 1, 1, 0.85), maxf(1.0, 1.0 * ui), false)
			var ausdehnung := Vector2(absf(laengs.x), absf(laengs.y)) * halb.x + Vector2(4, 4) * ui
			belegt.append([String(af["name"]), Rect2(m - ausdehnung, ausdehnung * 2.0)])
		else:
			# FLUGKARTEN-SYMBOL: Kreis in der Platzfarbe, die Bahn als Balken im wahren Kurs.
			var r := (4.5 if eck else 7.0) * ui
			if not rect.has_point(m):
				continue
			ci.draw_circle(m, r + 1.6 * ui, Color(0, 0, 0, 0.85))
			ci.draw_circle(m, r, farbe)
			var e := laengs * (r + 3.5 * ui)
			ci.draw_line(m - e, m + e, Color(0, 0, 0, 0.9), 4.2 * ui, true)
			ci.draw_line(m - e, m + e, Color(1, 1, 1, 0.97), 2.2 * ui, true)
			belegt.append([String(af["name"]), Rect2(m - Vector2(r + 4.0 * ui, r + 4.0 * ui),
				Vector2(r + 4.0 * ui, r + 4.0 * ui) * 2.0)])

	# --- Flugabwehr: Reichweitenkreise, solange die Stellung steht ---------------------
	var zonen: Dictionary = {}
	for n in get_tree().get_nodes_in_group("target"):
		if not (n is Node3D) or not is_instance_valid(n) or n.get("_tot") == true:
			continue
		var np := (n as Node3D).global_position
		if n is SamSite:
			var reich: float = float(SamSite.WERTE[String(n.get("art"))]["reichweite"])
			zonen[n.get_instance_id()] = [Vector2(np.x, np.z), reich, "sam"]
		elif n is FlakGun:
			# Alle Geschuetze einer Zone teilen Mitte und Radius: EIN Kreis je Zone.
			var zc: Vector3 = n.get("zone_center")
			var zk := Vector2(zc.x, zc.z)
			if not zonen.has(zk):
				zonen[zk] = [zk, float(n.get("zone_radius")) + 150.0, "flak"]
		elif n is Target:
			if n.get("_dead") == true:
				continue
			var tm: Vector2 = (o + Vector2(np.x, np.z) * k2)
			if rect.grow(-3.0 * ui).has_point(tm):
				var d := (3.2 if eck else 4.5) * ui
				var raute := PackedVector2Array([tm + Vector2(0, -d), tm + Vector2(d, 0),
					tm + Vector2(0, d), tm + Vector2(-d, 0)])
				ci.draw_colored_polygon(raute, C_ZIEL)
				ci.draw_polyline(raute + PackedVector2Array([raute[0]]), Color(0, 0, 0, 0.8),
					1.0 * ui, true)
	for z in zonen.values():
		var zm: Vector2 = o + (z[0] as Vector2) * k2
		var zr: float = float(z[1]) / mpp
		# Ausserhalb des Ausschnitts gar nicht erst 64 Punkte bauen und schneiden — das
		# war der teuerste Posten der Minimap.
		if zr < 2.0 or not rect.intersects(Rect2(zm - Vector2(zr, zr), Vector2(zr, zr) * 2.0)):
			continue
		var kreis := _kreis_pts(zm, zr, 64)
		_flaeche(ci, kreis, rect, Color(C_GEFAHR.r, C_GEFAHR.g, C_GEFAHR.b, 0.13))
		_gestrichelt(ci, kreis, rect, Color(C_GEFAHR.r, C_GEFAHR.g, C_GEFAHR.b, 0.9),
			maxf(1.2, 1.6 * ui), true)
		if rect.has_point(zm):
			var d := (3.5 if eck else 5.0) * ui
			if z[2] == "sam":
				var dreieck := PackedVector2Array([zm + Vector2(0, -d * 1.2), zm + Vector2(d, d * 0.8),
					zm + Vector2(-d, d * 0.8)])
				ci.draw_colored_polygon(dreieck, C_GEFAHR)
				ci.draw_polyline(dreieck + PackedVector2Array([dreieck[0]]), Color(0, 0, 0, 0.85),
					1.0 * ui, true)
			else:
				ci.draw_line(zm - Vector2(d, d), zm + Vector2(d, d), Color(0, 0, 0, 0.85), 3.4 * ui)
				ci.draw_line(zm - Vector2(d, -d), zm + Vector2(d, -d), Color(0, 0, 0, 0.85), 3.4 * ui)
				ci.draw_line(zm - Vector2(d, d), zm + Vector2(d, d), C_GEFAHR, 1.8 * ui)
				ci.draw_line(zm - Vector2(d, -d), zm + Vector2(d, -d), C_GEFAHR, 1.8 * ui)

	# --- Flugspur (aeltere Teile blasser) + Kurslinie ---------------------------------
	var ac := flieger()
	if _spur.size() > 1:
		var n := _spur.size()
		# DIE MINIMAP LAEUFT JEDES BILD: dort nur die letzten 150 Punkte (18 km) — in einem
		# 7-km-Ausschnitt liegt aeltere Spur ohnehin fast nie, aber 2400 Durchlaeufe je Bild
		# kosteten spuerbar Zeit im Flug.
		for i in range(maxi(0, n - 151) if eck else 0, n - 1):
			var a := _spur[i]
			var b := _spur[i + 1]
			if not a.is_finite() or not b.is_finite():
				continue
			if not sicht.has_point(a) and not sicht.has_point(b):
				continue
			var s := _clip_strecke((o + Vector2(a.x, a.y) * k2), (o + Vector2(b.x, b.y) * k2), rect)
			if not s.is_empty():
				var alpha := lerpf(0.25, 0.95, float(i) / float(n - 1))
				ci.draw_line(s[0], s[1], Color(C_SPUR.r, C_SPUR.g, C_SPUR.b, alpha),
					(1.6 if eck else 2.2) * ui, true)
	if ac != null:
		var pp := ac.global_position
		var fwd := -ac.global_transform.basis.z
		var flach := Vector2(fwd.x, fwd.z)
		if flach.length() > 0.05:
			flach = flach.normalized()
			var weit := 2500.0 if eck else 6000.0
			var pts := PackedVector2Array()
			for k in 13:
				var q := Vector2(pp.x, pp.z) + flach * (weit * float(k) / 12.0)
				pts.append((o + Vector2(q.x, q.y) * k2))
			_gestrichelt(ci, pts, rect, Color(1, 1, 1, 0.75), maxf(1.0, 1.3 * ui), false)
	return belegt


## Ein Hausgrundriss (gedrehtes Rechteck mit dunkler Kante), mindestens gut ein
## Bildpunkt gross, damit auch kleine Haeuser als Koernung erscheinen.
func _haus(ci: CanvasItem, h: Array, sh: Rect2, o: Vector2, k2: Vector2, mpp: float,
		rect: Rect2, ui: float) -> void:
	var hm: Vector2 = h[0]
	if not sh.has_point(hm):
		return
	var hb: Vector2 = h[1]
	var halb := Vector2(maxf(hb.x / mpp, 1.2 * ui), maxf(hb.y / mpp, 1.2 * ui))
	var m := o + hm * k2
	_flaeche(ci, _box(m, halb + Vector2(0.8, 0.8) * ui, -float(h[2])), rect, C_HAUS_RAND)
	_flaeche(ci, _box(m, halb, -float(h[2])), rect, C_HAUS)


## Strassen und Haeuser in raeumliche GRUPPEN buendeln (je Viertel eine, mit Huelle).
## Die Minimap zeigt fast immer hoechstens ein Viertel; so wird der Rest mit einem
## Rechteckvergleich je Viertel uebersprungen statt Strasse fuer Strasse.
## Neu gebaut, sobald CityBuilder mehr oder weniger Eintraege hat.
func _gruppen_pruefen() -> void:
	if _n_strassen == CityBuilder.karte_strassen.size() \
			and _n_haeuser == CityBuilder.karte_haeuser.size():
		return
	_n_strassen = CityBuilder.karte_strassen.size()
	_n_haeuser = CityBuilder.karte_haeuser.size()
	_gr_strassen = _gruppieren(CityBuilder.karte_strassen, 60.0, true)
	_gr_haeuser = _gruppieren(CityBuilder.karte_haeuser, 80.0, false)


## Eintraege [Vector2 punkt, ...] (Strecken: [a, b, ...]) nach Naehe in Gruppen; die
## Reihenfolge der Quelle ist schon viertelweise, also reicht ein Durchlauf.
static func _gruppieren(liste: Array, rand: float, strecke: bool) -> Array:
	var gruppen: Array = []
	var huelle := Rect2()
	var teil: Array = []
	for e in liste:
		var p: Vector2 = e[0]
		var box := Rect2(p, Vector2.ZERO)
		if strecke:
			box = box.expand(e[1])
		if teil.is_empty() or not huelle.grow(2500.0).encloses(box):
			if not teil.is_empty():
				gruppen.append([huelle.grow(rand), teil])
			teil = []
			huelle = box
		teil.append(e)
		huelle = huelle.merge(box)
	if not teil.is_empty():
		gruppen.append([huelle.grow(rand), teil])
	return gruppen


## Windrose: Kreis, Nordnadel rot, Suednadel weiss.
func _windrose(m: Vector2, r: float, ui: float) -> void:
	draw_circle(m, r + 2.0 * ui, Color(0, 0, 0, 0.45))
	draw_arc(m, r, 0.0, TAU, 40, Color(1, 1, 1, 0.75), maxf(1.0, 1.4 * ui), true)
	var q := r * 0.28
	draw_colored_polygon(PackedVector2Array([m + Vector2(0, -r * 0.92), m + Vector2(q, 0),
		m + Vector2(-q, 0)]), Color(0.95, 0.30, 0.25))
	draw_colored_polygon(PackedVector2Array([m + Vector2(0, r * 0.92), m + Vector2(-q, 0),
		m + Vector2(q, 0)]), Color(0.92, 0.94, 0.97))
	for k in 4:
		var d := Vector2.UP.rotated(TAU * float(k) / 4.0 + TAU / 8.0)
		draw_line(m + d * r * 0.55, m + d * r * 0.85, Color(1, 1, 1, 0.55), maxf(1.0, 1.2 * ui))
	var fs := int(15.0 * ui)
	var w := F_BOLD.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	_shadow_text(F_BOLD, m + Vector2(-w * 0.5, -r - 5.0 * ui), "N", fs, C_TEXT)


## Legende unten rechts in der Karte. Liefert ihr Rechteck (Namen weichen aus).
func _legende(ui: float) -> Rect2:
	var fs := int(14.0 * ui)
	var zeile := 21.0 * ui
	var eintraege := ["Flugplatz", "Ort", "Wahrzeichen", "Natur", "Flugabwehr", "Ziel",
		"Fluss", "Flugspur"]
	var breit := 0.0
	for e in eintraege:
		breit = maxf(breit, F_SEMI.get_string_size(e, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x)
	var pad := 10.0 * ui
	var groesse := Vector2(pad * 2.0 + 26.0 * ui + breit, pad * 2.0 + zeile * eintraege.size()
		+ 20.0 * ui)
	var r := Rect2(_map_rect.end - groesse - Vector2(12, 12) * ui, groesse)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.78)
	sb.set_corner_radius_all(int(8.0 * ui))
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	draw_style_box(sb, r)
	for i in eintraege.size():
		var y := r.position.y + pad + zeile * (float(i) + 0.5)
		var ic := Vector2(r.position.x + pad + 9.0 * ui, y)
		match i:
			0:
				draw_circle(ic, 6.0 * ui, Color(0.9, 0.9, 0.95))
				draw_line(ic - Vector2(9, -5) * ui, ic + Vector2(9, -5) * ui, Color(0, 0, 0, 0.9), 3.6 * ui)
				draw_line(ic - Vector2(9, -5) * ui, ic + Vector2(9, -5) * ui, Color.WHITE, 1.8 * ui)
			1:
				draw_rect(Rect2(ic - Vector2(6, 6) * ui, Vector2(12, 12) * ui), Color(0, 0, 0, 0.85))
				draw_rect(Rect2(ic - Vector2(4.5, 4.5) * ui, Vector2(9, 9) * ui), Color(0.95, 0.88, 0.55))
			2:
				draw_circle(ic, 6.0 * ui, Color(0, 0, 0, 0.85))
				draw_circle(ic, 4.5 * ui, Color(0.58, 0.76, 0.82))
			3:
				_dreieck_icon(self, ic, 6.5 * ui, Color(0.90, 0.62, 0.30), ui)
			4:
				draw_circle(ic, 7.0 * ui, Color(C_GEFAHR.r, C_GEFAHR.g, C_GEFAHR.b, 0.22))
				draw_arc(ic, 7.0 * ui, 0.0, TAU, 20, C_GEFAHR, 1.5 * ui, true)
			5:
				var d := 4.5 * ui
				draw_colored_polygon(PackedVector2Array([ic + Vector2(0, -d), ic + Vector2(d, 0),
					ic + Vector2(0, d), ic + Vector2(-d, 0)]), C_ZIEL)
			6:
				draw_line(ic - Vector2(9, 2) * ui, ic + Vector2(9, -2) * ui, C_FLUSS.lightened(0.12), 3.0 * ui, true)
			7:
				draw_line(ic - Vector2(9, 0) * ui, ic + Vector2(9, 0) * ui, C_SPUR, 2.4 * ui, true)
		_shadow_text(F_SEMI, Vector2(r.position.x + pad + 26.0 * ui, y + fs * 0.36),
			eintraege[i], fs, C_TEXT)
	var fuss := "Höhenlinien alle %d m" % int(LINIEN_M)
	draw_string(F_SEMI, Vector2(r.position.x + pad, r.end.y - pad + 2.0 * ui), fuss,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, int(12.0 * ui), C_MUTED)
	return r


static func _dreieck_icon(ci: CanvasItem, m: Vector2, d: float, col: Color, ui: float) -> void:
	var pts := PackedVector2Array([m + Vector2(0, -d), m + Vector2(d, d * 0.8),
		m + Vector2(-d, d * 0.8)])
	ci.draw_colored_polygon(pts, col)
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.85), 1.3 * ui, true)


## Label nur zeichnen, wenn es nicht mit einem bereits gezeichneten kollidiert (Marker bleibt).
## Einen Namen neben seinen Marker setzen: rechts, sonst links, oben, unten. Nur wenn die
## Stelle frei UND ganz in der Karte ist; sonst entfaellt der Name (Zoomen schafft Platz).
## `weitere` = zusaetzliche Hindernisse neben den gesetzten Namen und Platzmarkern.
func _name_setzen(p: Vector2, halb: float, txt: String, fs: int, col: Color, ui: float,
		weitere: Array, f: Font = F_SEMI) -> void:
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var h := fs * 1.1
	var abstand := halb + 4.0 * ui
	var kandidaten := [
		Vector2(p.x + abstand, p.y - h * 0.5),            # rechts
		Vector2(p.x - abstand - w, p.y - h * 0.5),        # links
		Vector2(p.x - w * 0.5, p.y - abstand - h),        # oben
		Vector2(p.x - w * 0.5, p.y + abstand),            # unten
	]
	for ecke: Vector2 in kandidaten:
		var r := Rect2(ecke, Vector2(w, h))
		if not _map_rect.encloses(r):
			continue
		var frei := true
		for other in _label_rects + weitere:
			if r.intersects(other):
				frei = false
				break
		if frei:
			_label_rects.append(r)
			_shadow_text(f, ecke + Vector2(0, fs * 0.8), txt, fs, col)
			return


func _shadow_text(f: Font, pos: Vector2, txt: String, fs: int, col: Color) -> void:
	# Kontur statt nur Schlagschatten: auf hellem Fels und dunklem Wald gleich gut lesbar.
	draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
		maxi(3, int(fs * 0.22)), Color(0, 0, 0, 0.72))
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)


func _draw() -> void:
	if _tex == null:
		return
	var vs := get_viewport_rect().size
	var ui := vs.y / 1080.0                              # Skalierung: crisp auf 1440p/4K
	var s := floorf(minf(vs.y * 0.74, vs.x * 0.55))
	var head := floorf(52.0 * ui)
	var panel := Rect2(floorf((vs.x - s) * 0.5), floorf((vs.y - s - head) * 0.5),
		s, s + head)
	_map_rect = Rect2(panel.position + Vector2(0, head), Vector2(s, s)).grow(-floorf(10.0 * ui))
	_map_rect.position = _map_rect.position.floor()
	var ac := flieger()

	# Hintergrund kraeftig abdunkeln -> das HUD dahinter lenkt nicht mehr ab
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.05, 0.72))

	# Panel: gerundet + Rand + interne Titelleiste (keine Kollision mit dem Kompass-HUD)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.set_corner_radius_all(int(12.0 * ui))
	sb.border_color = C_BORDER
	sb.set_border_width_all(maxi(2, int(2.0 * ui)))
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = int(18.0 * ui)
	draw_style_box(sb, panel)
	var hb := StyleBoxFlat.new()
	hb.bg_color = C_HEADER
	hb.corner_radius_top_left = int(12.0 * ui)
	hb.corner_radius_top_right = int(12.0 * ui)
	draw_style_box(hb, Rect2(panel.position, Vector2(panel.size.x, head)))
	var fs_title := int(26.0 * ui)
	var titel_x := panel.position.x + 18.0 * ui
	var mitte_y := panel.position.y + head * 0.5
	_shadow_text(F_BOLD, Vector2(titel_x, mitte_y + fs_title * 0.36), "KARTE", fs_title, C_TEXT)
	titel_x += F_BOLD.get_string_size("KARTE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_title).x + 16.0 * ui
	# Zoomstufen als Pillen, die aktive hervorgehoben
	var fs_chip := int(15.0 * ui)
	for i in ZOOMS.size():
		var txt := ("%.1f×" % ZOOMS[i]).replace(".0×", "×").replace(".", ",")
		var tw := F_SEMI.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_chip).x
		var chip := Rect2(titel_x, mitte_y - 12.0 * ui, tw + 16.0 * ui, 24.0 * ui)
		var cb := StyleBoxFlat.new()
		cb.set_corner_radius_all(int(12.0 * ui))
		cb.bg_color = Color(0.25, 0.75, 0.95, 0.9) if i == _zoom_i else Color(1, 1, 1, 0.08)
		draw_style_box(cb, chip)
		draw_string(F_SEMI, Vector2(chip.position.x + 8.0 * ui, mitte_y + fs_chip * 0.36), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_chip,
			Color(0.02, 0.05, 0.08) if i == _zoom_i else C_MUTED)
		titel_x = chip.end.x + 6.0 * ui
	# Position des Spielers: Planquadrat + Hoehe
	if ac != null:
		var pos_txt := "%s  ·  %d m" % [planquadrat(ac.global_position), roundi(ac.global_position.y)]
		_shadow_text(F_SEMI, Vector2(titel_x + 12.0 * ui, mitte_y + fs_chip * 0.36), pos_txt,
			fs_chip, C_PLAYER.lightened(0.35))
	var hint := "Mausrad — Zoom  ·  M — schließen"
	var fs_hint := int(16.0 * ui)
	var hw := F_SEMI.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_hint).x
	_shadow_text(F_SEMI, Vector2(panel.end.x - hw - 18.0 * ui, mitte_y + fs_hint * 0.36), hint,
		fs_hint, C_MUTED)

	# Karte (sichtbares Fenster je Zoom)
	_update_window()
	_label_rects.clear()
	var ts := Vector2(_tex.get_width(), _tex.get_height())
	draw_texture_rect_region(_tex, _map_rect, Rect2(_win_min * ts, _win_size * ts))
	var win_world := _win_size.x * WORLD_R * 2.0
	var px_m := _map_rect.size.x / win_world

	# PLANQUADRATE (5 km) — beim Hineinzoomen zusaetzlich ein feines 1-km-Netz.
	var x0 := _win_min.x * 2.0 * WORLD_R - WORLD_R
	var z0 := _win_min.y * 2.0 * WORLD_R - WORLD_R
	if _zoom_i > 0:
		var k := ceilf(x0 / 1000.0) * 1000.0
		while k < x0 + win_world:
			var gx := _map_rect.position.x + (k - x0) * px_m
			draw_line(Vector2(gx, _map_rect.position.y), Vector2(gx, _map_rect.end.y), Color(1, 1, 1, 0.05), 1.0)
			k += 1000.0
		k = ceilf(z0 / 1000.0) * 1000.0
		while k < z0 + win_world:
			var gy := _map_rect.position.y + (k - z0) * px_m
			draw_line(Vector2(_map_rect.position.x, gy), Vector2(_map_rect.end.x, gy), Color(1, 1, 1, 0.05), 1.0)
			k += 1000.0
	var q0 := ceilf((x0 + WORLD_R) / QUADRAT) * QUADRAT - WORLD_R
	var q := q0
	while q < x0 + win_world:
		var gx := _map_rect.position.x + (q - x0) * px_m
		draw_line(Vector2(gx, _map_rect.position.y), Vector2(gx, _map_rect.end.y), Color(1, 1, 1, 0.14), 1.0)
		q += QUADRAT
	q = ceilf((z0 + WORLD_R) / QUADRAT) * QUADRAT - WORLD_R
	while q < z0 + win_world:
		var gy := _map_rect.position.y + (q - z0) * px_m
		draw_line(Vector2(_map_rect.position.x, gy), Vector2(_map_rect.end.x, gy), Color(1, 1, 1, 0.14), 1.0)
		q += QUADRAT

	# VEKTOR-EBENEN
	var belegt := zeichne_ebenen(self, _map_rect, _win_min, _win_size, ui)

	# Innenschatten am Kartenrand: gibt der Karte Tiefe, als laege sie unter Glas
	var schatten := 14.0 * ui
	var dunkel := Color(0, 0, 0, 0.38)
	var klar := Color(0, 0, 0, 0.0)
	var r := _map_rect
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y),
		Vector2(r.end.x, r.position.y + schatten), Vector2(r.position.x, r.position.y + schatten)]),
		PackedColorArray([dunkel, dunkel, klar, klar]))
	draw_polygon(PackedVector2Array([Vector2(r.position.x, r.end.y - schatten),
		Vector2(r.end.x, r.end.y - schatten), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([klar, klar, dunkel, dunkel]))
	draw_polygon(PackedVector2Array([r.position, Vector2(r.position.x + schatten, r.position.y),
		Vector2(r.position.x + schatten, r.end.y), Vector2(r.position.x, r.end.y)]),
		PackedColorArray([dunkel, klar, klar, dunkel]))
	draw_polygon(PackedVector2Array([Vector2(r.end.x - schatten, r.position.y),
		Vector2(r.end.x, r.position.y), r.end, Vector2(r.end.x - schatten, r.end.y)]),
		PackedColorArray([klar, dunkel, dunkel, klar]))
	draw_rect(_map_rect, Color(0, 0, 0, 0.6), false, maxf(1.0, 1.5 * ui))

	# Planquadrat-Beschriftung: Buchstaben oben, Zahlen links, je in Feldmitte
	var fs_q := int(13.0 * ui)
	var qc := Color(1, 1, 1, 0.62)
	var sp := floorf((x0 + WORLD_R) / QUADRAT)
	while true:
		var mx := (sp + 0.5) * QUADRAT - WORLD_R
		if mx > x0 + win_world:
			break
		if sp >= 0 and sp < BUCHSTABEN.length() and mx > x0 + 6.0 / px_m \
				and mx < x0 + win_world - 14.0 / px_m:
			var gx := _map_rect.position.x + (mx - x0) * px_m
			var t := BUCHSTABEN[int(sp)]
			_shadow_text(F_BOLD, Vector2(gx - 4.0 * ui, _map_rect.position.y + fs_q + 3.0 * ui), t, fs_q, qc)
		sp += 1.0
	var ze := floorf((z0 + WORLD_R) / QUADRAT)
	while true:
		var mz := (ze + 0.5) * QUADRAT - WORLD_R
		if mz > z0 + win_world:
			break
		if ze >= 0 and ze < 14 and mz > z0 + 14.0 / px_m and mz < z0 + win_world - 10.0 / px_m:
			var gy := _map_rect.position.y + (mz - z0) * px_m
			_shadow_text(F_BOLD, Vector2(_map_rect.position.x + 5.0 * ui, gy + fs_q * 0.36), str(int(ze) + 1), fs_q, qc)
		ze += 1.0

	# Windrose oben rechts
	var rose_r := 24.0 * ui
	var rose_m := Vector2(_map_rect.end.x - rose_r - 18.0 * ui, _map_rect.position.y + rose_r + 26.0 * ui)
	_windrose(rose_m, rose_r, ui)
	_label_rects.append(Rect2(rose_m - Vector2(rose_r + 6.0 * ui, rose_r + 22.0 * ui),
		Vector2(rose_r + 6.0 * ui, rose_r + 14.0 * ui) * 2.0))

	# MASSSTAB unten links: vier Wechselfelder wie auf einer Wanderkarte
	var grid_km := 5000.0 if _zoom_i == 0 else (2000.0 if _zoom_i == 1 else 1000.0)
	var feld := grid_km * px_m / 4.0
	var bar_y := _map_rect.end.y - 24.0 * ui
	var bar_x := _map_rect.position.x + 20.0 * ui
	var bh := 6.0 * ui
	draw_rect(Rect2(bar_x - 1.5 * ui, bar_y - 1.5 * ui, feld * 4.0 + 3.0 * ui, bh + 3.0 * ui), Color(0, 0, 0, 0.8))
	for i in 4:
		draw_rect(Rect2(bar_x + feld * i, bar_y, feld, bh), Color(1, 1, 1, 0.95) if i % 2 == 0 else Color(0.12, 0.13, 0.15))
	var fs_bar := int(14.0 * ui)
	_shadow_text(F_SEMI, Vector2(bar_x - 3.0 * ui, bar_y - 6.0 * ui), "0", fs_bar, C_TEXT)
	var km_txt := "%d km" % int(grid_km / 1000.0)
	_shadow_text(F_SEMI, Vector2(bar_x + feld * 4.0 - 6.0 * ui, bar_y - 6.0 * ui), km_txt, fs_bar, C_TEXT)
	_label_rects.append(Rect2(bar_x - 6.0 * ui, bar_y - 24.0 * ui, feld * 4.0 + 50.0 * ui, 36.0 * ui))

	# Legende unten rechts
	_label_rects.append(_legende(ui))

	# MARKER ZUERST, BESCHRIFTUNGEN DANACH — und beide durch die Entzerrung.
	# Reihenfolge: alle Marker als belegte Flaeche eintragen (kein Name ueberdeckt einen
	# Punkt), dann Flugplatznamen (Vorrang), dann POI-Namen. Passt ein Name rechts nicht,
	# wird links, oben und unten probiert; passt er nirgends, entfaellt er — beim
	# Hineinzoomen hat er dann Platz. Flugplaetze zeichnet zeichne_ebenen (Symbol oder
	# echte Bahn); ihre Flaeche kommt als `belegt` zurueck.
	var fs_af := int(18.0 * ui)
	var fs_poi := int(16.0 * ui)
	var namen: Array = []     # [marker_pos, halbe_markergroesse, text, fs, farbe, ist_platz]
	var punkte: Array = []    # Rechtecke der POI-Punkte (nur fuer POI-Namen ein Hindernis)
	var eigene: Dictionary = {}
	for b in belegt:
		_label_rects.append(b[1])
		eigene[b[0]] = b[1]
	for af in _airfields:
		var p := _world_to_map(af["pos"])
		if not _map_rect.has_point(p):
			continue
		# Abstand = halbe Ausdehnung der eigenen Bahn: beim Hineinzoomen ist die Bahn
		# laenger als der Name, und mit festen 9 px laege jeder Kandidat auf ihr — der
		# Name fiel dann ganz weg.
		var halb := 9.0 * ui
		if eigene.has(String(af["name"])):
			var er: Rect2 = eigene[String(af["name"])]
			halb = maxf(halb, maxf(er.size.x, er.size.y) * 0.5 - 2.0 * ui)
		namen.append([p, halb, String(af["name"]), fs_af, C_TEXT, true])
	for poi in _pois:
		var p := _world_to_map(poi["pos"])
		if not _map_rect.grow(-4.0).has_point(p):
			continue
		var art := String(poi.get("art", "wahrz"))
		var col: Color = poi.get("color", Color(0.95, 0.85, 0.3))
		var halb := 6.5 * ui
		match art:
			"ort":
				draw_rect(Rect2(p - Vector2(6, 6) * ui, Vector2(12, 12) * ui), Color(0, 0, 0, 0.85))
				draw_rect(Rect2(p - Vector2(4.5, 4.5) * ui, Vector2(9, 9) * ui), col)
			"natur":
				_dreieck_icon(self, p, 6.5 * ui, col, ui)
			"gefahr":
				pass       # kein Punkt: die Zone steht als Reichweitenkreis auf der Karte
			_:
				draw_circle(p, 6.5 * ui, Color(0, 0, 0, 0.8))
				draw_circle(p, 5.0 * ui, col)
		punkte.append(Rect2(p - Vector2(halb, halb), Vector2(halb, halb) * 2.0))
		var gross := art == "ort" and String(poi["name"]) == String(poi["name"]).to_upper()
		var name_farbe := Color(0.88, 0.92, 0.98, 0.9)
		if art == "ort":
			name_farbe = Color(0.95, 0.97, 1.0, 0.97)
		elif art == "gefahr":
			name_farbe = C_GEFAHR.lightened(0.25)
		namen.append([p, halb, String(poi["name"]), fs_poi + (2 if gross else 0), name_farbe, false])
	# FLUGPLAETZE HABEN VORRANG: ihre Namen duerfen einen POI-Punkt streifen (zum Landen
	# sucht man den Platz, nicht das Windrad daneben), aber keinen anderen Namen und keinen
	# Platzmarker. POI-Namen muessen allem ausweichen.
	for n in namen:
		if n[5]:
			_name_setzen(n[0], n[1], n[2], n[3], n[4], ui, [], F_BOLD)
	for n in namen:
		if not n[5]:
			_name_setzen(n[0], n[1], n[2], n[3], n[4], ui, punkte)
	# Spieler: grosser Pfeil mit weisser Kontur
	if ac != null:
		var p := _world_to_map(ac.global_position)
		var fwd := -ac.global_transform.basis.z
		var a := atan2(fwd.x, fwd.z)
		var dirv := Vector2(sin(a), cos(a))
		var side := Vector2(-dirv.y, dirv.x)
		var L := 16.0 * ui
		var pts := PackedVector2Array([p + dirv * L, p - dirv * L * 0.55 + side * L * 0.62,
			p - dirv * L * 0.27, p - dirv * L * 0.55 - side * L * 0.62])
		draw_colored_polygon(pts, C_PLAYER)
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.95), maxf(1.5, 2.0 * ui))


func toggle() -> void:
	visible = not visible
