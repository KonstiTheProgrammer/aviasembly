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
const C_WEG := Color(1.0, 0.86, 0.32)
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
var _label_rects: Array = []   # Label-Entzerrung (Overview-Cluster)
var _terrain: TerrainWorld = null

# ANSICHT: stufenloser Zoom (Mausrad/Pinch, zum Cursor hin), Ziehen verschiebt.
const ZOOM_MIN := 1.0
const ZOOM_MAX := 14.0
const ZOOM_SCHRITT := 1.3
var _zoom := 1.0
var _zoom_ziel := 1.0
var _mitte := Vector2.ZERO             # Weltmitte der Ansicht (x, z)
var _folgen := true                    # Ansicht haengt am Flugzeug
var _anker_welt := Vector2.ZERO
var _anker_schirm := Vector2(-1, -1)
var _ziehen := false
var _zieh_weg := 0.0
var _maus := Vector2(-1, -1)           # letzte Mausposition (Tooltip)
var _maus_vorher := Input.MOUSE_MODE_VISIBLE
var _knopf_folgen := Rect2()
var _seiten_klick: Array = []          # [Rect2, Flugplatz] der Liste in der Seitenleiste

# WEGPUNKT (Welt x/z; INF = keiner)
const WEGPUNKT_ERREICHT := 350.0
signal wegpunkt_erreicht(titel: String)
var wegpunkt := Vector2.INF
var wegpunkt_name := ""

# DETAILKACHELN
const KEINE_KACHEL := Vector3i(-1, -1, -1)
var _kacheln: Dictionary = {}          # Vector3i (Spalte, Zeile, Stufe) -> ImageTexture
var _kachel_alter: Dictionary = {}     # Vector3i -> Zugriffszaehler (LRU)
var _kachel_zaehler := 0
var _kachel_wunsch: Array = []
var _kachel_laeuft := KEINE_KACHEL
var _rand_farbe := Color(0.1, 0.3, 0.5)  # Meer am Weltrand (aus dem Kartenbild)
var _mini_sicht := Rect2()             # Ausschnitt der Minimap (zuletzt gezeichnet)
var _mini_mpp := 100.0
var _mini_frame := -100
var _kachel_thread: Thread = null
var _kachel_stopp := [false]


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
# Detailkacheln: dieselbe Karte, nur weniger generalisiert (siehe erzeuge_kachel).
# ZWEI STUFEN: Stufe 1 = 8 x 8 Kacheln (8,5 km, 16,6 m je Punkt), Stufe 2 = 16 x 16
# (4,25 km, 8,3 m je Punkt) fuer das starke Hineinzoomen. Stufe 0 ist die Grundkarte.
const KACHEL_PX := 512
const KACHEL_RAND := 24
const KACHEL_AB := 40.0                        # m je echtem Bildpunkt: darunter Stufe 1
const KACHEL_AB2 := 12.0                       # ... darunter Stufe 2
const KACHEL_MAX := 48                         # so viele bleiben im Speicher (je ~1 MB)
# Generalisierung je Stufe [Grundkarte, Stufe 1, Stufe 2]: je naeher, desto feiner.
const STUFE_FARB := [250.0, 70.0, 32.0]        # Farbraster (m)
const STUFE_GLATT := [200.0, 50.0, 24.0]       # Glaettung der Hoehen (m)
const STUFE_RELIEF := [130.0, 55.0, 28.0]      # Messbasis der Schattierung (m)
const STUFE_RUHE := [0.4, 0.2, 0.12]           # Anteil des weichen Farbfelds


## `stopp` = [bool], von aussen auf true gesetzt bricht die Erzeugung ab (jede Zeile
## kehrt sofort zurueck, Rueckgabe null). Sonst wartete Main beim Beenden bis zu einer
## Minute auf eine Karte, die niemand mehr sieht.
## `mitte` verschiebt den Ausschnitt (Detailkacheln), `detail` (Stufe 1/2) schaltet auf
## die feineren Generalisierungswerte der Kacheln (STUFE_*) und laesst die Mipmaps weg —
## die Kachel wird danach noch beschnitten.
static func generate_image(t: TerrainWorld, kante := 1024, world_r := WORLD_R,
		vorrang := true, faeden := 4, stopp: Array = [false], mitte := Vector2.ZERO,
		detail := 0) -> Image:
	var zelle := 2.0 * world_r / float(kante - 1)
	var sperre := Mutex.new()
	var t0 := Time.get_ticks_usec()
	var zeiten: Array = []
	var farb_m: float = FARB_RASTER if detail == 0 else STUFE_FARB[detail]
	var glatt_m: float = GLATT_M if detail == 0 else STUFE_GLATT[detail]
	var relief_m: float = RELIEF_BASIS if detail == 0 else STUFE_RELIEF[detail]
	var ruhe: float = FARB_RUHE if detail == 0 else STUFE_RUHE[detail]
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
		var wz := mitte.y + (float(py) / float(kante - 1) * 2.0 - 1.0) * world_r
		for px in kante:
			var wx := mitte.x + (float(px) / float(kante - 1) * 2.0 - 1.0) * world_r
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
	zeiten.append((Time.get_ticks_usec() - t0) / 1000.0)

	# GEGLAETTETE HOEHEN (fuer Relief, Hoehenlinien UND die Farbwahl): auf GLATT_M
	# herunter und kubisch wieder hoch.
	# Punktgenau schattiert sah jeder 20-m-Huegel wie zerknitterte Alufolie aus, die
	# Hoehenlinien zerfielen im welligen Gelaende zu Kruemeln, und _face_color machte aus
	# jeder steilen 60-m-Flanke einen Felsfleck — die ganze Insel war braun gesprenkelt.
	# Eine Karte GENERALISIERT: Fels ist, was auf 200 m steil ist. Kueste und Wasser
	# kommen weiter aus dem feinen Raster.
	var h_img := Image.create_from_data(kante, kante, false, Image.FORMAT_RF, hs.to_byte_array())
	var klein := clampi(roundi(2.0 * world_r / glatt_m), 16, kante)
	h_img.resize(klein, klein, Image.INTERPOLATE_LANCZOS)
	h_img.resize(kante, kante, Image.INTERPOLATE_CUBIC)
	var hg := h_img.get_data().to_float32_array()

	# --- 2. Farben, grob (teuer, nur vier Faeden — Begruendung oben) ------------------
	var schritt := maxi(1, roundi(farb_m / zelle))
	var n := ceili(float(kante - 1) / float(schritt)) + 1
	var zeilen_c: Array = []
	zeilen_c.resize(n)
	var g2 := WorkerThreadPool.add_group_task(func(j: int) -> void:
		if stopp[0]:
			return
		var z := _grobfarben(t, hs, hg, ks, j, n, schritt, kante, world_r, zelle, mitte)
		sperre.lock()
		zeilen_c[j] = z
		sperre.unlock(), n, faeden, vorrang, "Weltkarte Farben")
	WorkerThreadPool.wait_for_group_task_completion(g2)
	if stopp[0]:
		return null
	var cs := PackedColorArray()
	for z in zeilen_c:
		cs.append_array(z)
	zeiten.append((Time.get_ticks_usec() - t0) / 1000.0)

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
		fs[i] = lerpf(fs[i], fw[i], ruhe)
	zeiten.append((Time.get_ticks_usec() - t0) / 1000.0)

	# --- 3. Zusammensetzen (billig, alle Faeden) --------------------------------------
	var basis := maxi(1, roundi(relief_m / zelle))
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
	if detail == 0:
		img.generate_mipmaps()
	zeiten.append((Time.get_ticks_usec() - t0) / 1000.0)
	if detail == 0:
		stufen_ms = zeiten   # Kacheln laufen nebenher und sollen die Messung nicht stoeren
	return img


## DETAILKACHEL (key = Spalte, Zeile, Stufe), scharf fuer das Hineinzoomen.
## Erzeugt mit KACHEL_RAND Punkten Ueberstand und danach beschnitten: Glaettung und
## Reliefnachbarn laufen sonst am Kachelrand ins Leere, und die Naehte waeren zu sehen.
## Pixelmitten liegen bei kachel_min + (i + 0.5) * zelle, genau wie beim Zeichnen.
static func erzeuge_kachel(t: TerrainWorld, key: Vector3i, stopp: Array) -> Image:
	var km := kachel_m(key.z)
	var zelle := km / float(KACHEL_PX)
	var k := KACHEL_PX + 2 * KACHEL_RAND
	var halb := zelle * float(k - 1) * 0.5
	var mitte := _kachel_mitte(key)
	var img := generate_image(t, k, halb, false, 4, stopp, mitte, key.z)
	if img == null:
		return null
	var aus := img.get_region(Rect2i(KACHEL_RAND, KACHEL_RAND, KACHEL_PX, KACHEL_PX))
	aus.generate_mipmaps()
	return aus


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
		zelle: float, mitte: Vector2) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(n)
	var py := mini(j * schritt, kante - 1)
	var wz := mitte.y + (float(py) / float(kante - 1) * 2.0 - 1.0) * world_r
	var o := py * kante
	var o_hoch := maxi(py - 1, 0) * kante
	var o_tief := mini(py + 1, kante - 1) * kante
	for i in n:
		var px := mini(i * schritt, kante - 1)
		if ks[o + px] != 2:
			out[i] = Color(0, 0, 0, 0)
			continue
		var wx := mitte.x + (float(px) / float(kante - 1) * 2.0 - 1.0) * world_r
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
	_terrain = terrain
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
	# Jenseits des Weltrands wird mit genau der Farbe des Kartenrands weitergemalt — mit
	# einer festen Palettenfarbe stand dort eine sichtbare Kante (das Randmeer ist nur
	# 18 m tief, also heller als K_TIEF).
	_rand_farbe = map_img.get_pixel(0, map_img.get_height() >> 1)
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


func _process(dt: float) -> void:
	_spur_aufzeichnen()
	_wegpunkt_pruefen()
	if not visible:
		# Minimap: die Kacheln um das Flugzeug still vorladen (nur Stufe 1), solange sie
		# ueberhaupt gezeichnet wird.
		_kachel_wunsch.clear()
		if Engine.get_process_frames() - _mini_frame < 5:
			_kacheln_planen(_mini_sicht.grow(1500.0), _mini_mpp, 1)
		return
	# WEICHES ZOOMEN: _zoom laeuft dem Ziel nach; der Weltpunkt unter dem Anker (Cursor
	# beim Mausrad) bleibt dabei stehen — so zoomt man GENAU dorthin, wo man hinzeigt.
	if absf(_zoom - _zoom_ziel) > 0.0005:
		_zoom = lerpf(_zoom, _zoom_ziel, 1.0 - exp(-14.0 * dt))
		if absf(_zoom - _zoom_ziel) < 0.001:
			_zoom = _zoom_ziel
		if not _folgen and _anker_schirm.x >= 0.0:
			_mitte = _anker_welt - (_anker_schirm - _map_rect.get_center()) * _mpp()
	if _folgen:
		var ac := flieger()
		if ac != null:
			_mitte = Vector2(ac.global_position.x, ac.global_position.z)
	_klemmen()
	_kacheln_planen(_sicht(), _mpp() / _skala(), 2)
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


# --- WEGPUNKT ----------------------------------------------------------------------
# Klick in die Karte setzt ihn, Rechtsklick loescht ihn, ein Klick auf einen Flugplatz in
# der Seitenleiste legt ihn dorthin. Das HUD fuehrt dann statt zum naechsten Flugplatz
# zum Wegpunkt (Main._on_hud_changed), Karte und Minimap zeigen Linie und Fahne. Beim
# Ueberfliegen (unter WEGPUNKT_ERREICHT) loest er sich auf und meldet sich per Signal.

func hat_wegpunkt() -> bool:
	return wegpunkt.is_finite()


func setze_wegpunkt(w: Vector2, titel := "") -> void:
	wegpunkt = w
	wegpunkt_name = titel
	queue_redraw()


func loesche_wegpunkt() -> void:
	wegpunkt = Vector2.INF
	wegpunkt_name = ""
	queue_redraw()


## "WEGPUNKT   3.2 km   045°" fuer die NAV-Pille im HUD.
func wegpunkt_text(von: Vector3) -> String:
	var d := wegpunkt - Vector2(von.x, von.z)
	var brg := fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)
	var n := wegpunkt_name if wegpunkt_name != "" else "WEGPUNKT"
	return "%s   %.1f km   %03d°" % [n, d.length() / 1000.0, int(round(brg)) % 360]


func _wegpunkt_pruefen() -> void:
	if not hat_wegpunkt():
		return
	var ac := flieger()
	if ac == null:
		return
	if Vector2(ac.global_position.x, ac.global_position.z).distance_to(wegpunkt) < WEGPUNKT_ERREICHT:
		var n := wegpunkt_name
		loesche_wegpunkt()
		wegpunkt_erreicht.emit(n)


# --- ANSICHT: Mitte (Welt x/z) + Zoom -> Ausschnitt im Kartenrechteck ----------------
# Zoom 1 = die ganze Welthoehe (68 km) passt ins Rechteck. Das Rechteck ist BREITER als
# hoch; seitlich jenseits des Weltrands zeigt die Karte offenes Meer.

func _mpp() -> float:
	if _map_rect.size.y <= 1.0:
		return 1.0
	return 2.0 * WORLD_R / _zoom / _map_rect.size.y


## Sichtbarer Weltausschnitt (x, z) als Rechteck.
func _sicht() -> Rect2:
	var groesse := _map_rect.size * _mpp()
	return Rect2(_mitte - groesse * 0.5, groesse)


func _klemmen() -> void:
	var halb := _map_rect.size * _mpp() * 0.5
	for ax in 2:
		if halb[ax] >= WORLD_R:
			_mitte[ax] = 0.0
		else:
			_mitte[ax] = clampf(_mitte[ax], -WORLD_R + halb[ax], WORLD_R - halb[ax])


func _welt_zu_schirm(w: Vector2) -> Vector2:
	return _map_rect.get_center() + (w - _mitte) / _mpp()


func _schirm_zu_welt(p: Vector2) -> Vector2:
	return _mitte + (p - _map_rect.get_center()) * _mpp()


func _world_to_map(w: Vector3) -> Vector2:
	return _welt_zu_schirm(Vector2(w.x, w.z))


## Zoom auf `ziel`, wobei der Weltpunkt unter `schirm` stehen bleibt (schirm.x < 0: Mitte).
func _zoom_auf(ziel: float, schirm := Vector2(-1, -1)) -> void:
	_zoom_ziel = clampf(ziel, ZOOM_MIN, ZOOM_MAX)
	if schirm.x < 0.0 or _folgen:
		_anker_schirm = Vector2(-1, -1)
		return
	_anker_schirm = schirm
	_anker_welt = _schirm_zu_welt(schirm)


## Von aussen (Werkzeuge, Main): Zoomstufe direkt setzen, auf den Spieler zentriert.
func set_zoom(z: float) -> void:
	_folgen = true
	_zoom_ziel = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_zoom = _zoom_ziel
	_anker_schirm = Vector2(-1, -1)


func zoom() -> float:
	return _zoom


# --- EINGABE ----------------------------------------------------------------------
# Solange die Karte offen ist, ist die Maus FREI (toggle) und die Karte faengt alle
# Mausereignisse ab (mouse_filter STOP) — sonst lenkte jede Kartenbewegung im Maus-Flug
# das Flugzeug, und das Mausrad zoomte die Flugkamera mit.

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_auf(_zoom_ziel * ZOOM_SCHRITT, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_auf(_zoom_ziel / ZOOM_SCHRITT, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_ziehen = _map_rect.has_point(mb.position)
				_zieh_weg = 0.0
			else:
				if _zieh_weg < 5.0 and mb.button_index == MOUSE_BUTTON_LEFT:
					_klick(mb.position)
				_ziehen = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _map_rect.has_point(mb.position):
				loesche_wegpunkt()
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_maus = mm.position
		if _ziehen:
			_zieh_weg += mm.relative.length()
			if _zieh_weg >= 5.0:
				_folgen = false
				_anker_schirm = Vector2(-1, -1)
				_mitte -= mm.relative * _mpp()
				_klemmen()
		accept_event()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_auf(_zoom_ziel * mg.factor, mg.position)
		accept_event()
	elif event is InputEventPanGesture:
		# Zwei-Finger-Wischen auf dem Trackpad verschiebt die Karte
		var pg := event as InputEventPanGesture
		_folgen = false
		_anker_schirm = Vector2(-1, -1)
		_mitte += pg.delta * 12.0 * _mpp()
		_klemmen()
		accept_event()


func _klick(pos: Vector2) -> void:
	# Knopf "Zu mir" im Kopf
	if _knopf_folgen.has_point(pos):
		_folgen = true
		_anker_schirm = Vector2(-1, -1)
		return
	# Flugplatzliste in der Seitenleiste
	for zeile in _seiten_klick:
		if (zeile[0] as Rect2).has_point(pos):
			var af: Dictionary = zeile[1]
			var ap: Vector3 = af["pos"]
			setze_wegpunkt(Vector2(ap.x, ap.z), String(af["name"]))
			return
	if _map_rect.has_point(pos):
		setze_wegpunkt(_schirm_zu_welt(pos))


func toggle() -> void:
	if visible:
		schliessen()
	else:
		oeffnen()


func oeffnen() -> void:
	if visible:
		return
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_maus_vorher = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Beim Oeffnen auf das Flugzeug zentriert; ein gewaehlter Zoom bleibt erhalten.
	_folgen = true
	_ziehen = false
	_maus = Vector2(-1, -1)
	queue_redraw()


func schliessen() -> void:
	if not visible:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ziehen = false
	_kachel_wunsch.clear()
	Input.mouse_mode = _maus_vorher


func offen() -> bool:
	return visible


# --- DETAILKACHELN -----------------------------------------------------------------
# Die Grundkarte hat 66 m je Bildpunkt. Beim Hineinzoomen wird sie weich; dann kommen
# scharfe Kacheln mit 16,6 m je Punkt dazu, EINE nach der anderen im Hintergrund, die
# naechstgelegene zuerst. Bis eine fertig ist, liegt dort die Grundkarte — man sieht also
# nie ein Loch, nur wie es schaerfer wird. Fertige Kacheln bleiben im Speicher
# (hoechstens KACHEL_MAX, die am laengsten ungenutzten fliegen zuerst).

## Kacheln fuer den Ausschnitt `sicht` anfordern. `mpp` = Meter je ECHTEM Bildpunkt
## (nicht je virtuellem UI-Punkt): auf einem Retina-Schirm ist derselbe Zoom doppelt so
## fein aufgeloest und braucht die schaerfere Stufe frueher.
func _kacheln_planen(sicht: Rect2, mpp: float, max_stufe: int) -> void:
	_kachel_wunsch.clear()
	if _terrain == null or mpp >= KACHEL_AB:
		return
	var stufe := 2 if mpp < KACHEL_AB2 and max_stufe >= 2 else 1
	var km := kachel_m(stufe)
	var n := kachel_n(stufe)
	var i0 := clampi(floori((sicht.position.x + WORLD_R) / km), 0, n - 1)
	var i1 := clampi(floori((sicht.end.x + WORLD_R) / km), 0, n - 1)
	var j0 := clampi(floori((sicht.position.y + WORLD_R) / km), 0, n - 1)
	var j1 := clampi(floori((sicht.end.y + WORLD_R) / km), 0, n - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var key := Vector3i(i, j, stufe)
			if _kacheln.has(key):
				_kachel_zaehler += 1
				_kachel_alter[key] = _kachel_zaehler
			elif key != _kachel_laeuft:
				_kachel_wunsch.append(key)
	# Naechste zur Bildmitte zuerst
	var m := _mitte
	_kachel_wunsch.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _kachel_mitte(a).distance_squared_to(m) < _kachel_mitte(b).distance_squared_to(m))
	if not _kachel_wunsch.is_empty() and (_kachel_thread == null or not _kachel_thread.is_alive()):
		if _kachel_thread != null:
			_kachel_thread.wait_to_finish()
		var key: Vector3i = _kachel_wunsch[0]
		_kachel_laeuft = key
		var t := _terrain
		var stopp := _kachel_stopp
		_kachel_thread = Thread.new()
		_kachel_thread.start(func() -> void:
			var img := WorldMap.erzeuge_kachel(t, key, stopp)
			if img != null:
				call_deferred("_kachel_fertig", key, img))


static func kachel_n(stufe: int) -> int:
	return 8 if stufe == 1 else 16


static func kachel_m(stufe: int) -> float:
	return 2.0 * WORLD_R / float(kachel_n(stufe))


static func _kachel_mitte(key: Vector3i) -> Vector2:
	var km := kachel_m(key.z)
	return Vector2(-WORLD_R + (float(key.x) + 0.5) * km, -WORLD_R + (float(key.y) + 0.5) * km)


func _kachel_fertig(key: Vector3i, img: Image) -> void:
	_kachel_laeuft = KEINE_KACHEL
	_kacheln[key] = ImageTexture.create_from_image(img)
	_kachel_zaehler += 1
	_kachel_alter[key] = _kachel_zaehler
	while _kacheln.size() > KACHEL_MAX:
		var alt := key
		var alt_n := _kachel_zaehler + 1
		for k in _kachel_alter:
			if int(_kachel_alter[k]) < alt_n:
				alt_n = int(_kachel_alter[k])
				alt = k
		_kacheln.erase(alt)
		_kachel_alter.erase(alt)
	queue_redraw()


## Fertig = fuer den aktuellen Ausschnitt liegt keine Kachel mehr in der Warteschlange
## (auch wenn gar keine noetig sind). Fuer Werkzeuge, die auf die scharfe Karte warten.
func kacheln_bereit() -> bool:
	return _kachel_wunsch.is_empty() and _kachel_laeuft == KEINE_KACHEL


func _exit_tree() -> void:
	_kachel_stopp[0] = true
	if _kachel_thread != null and _kachel_thread.is_started():
		_kachel_thread.wait_to_finish()
	_kachel_thread = null


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

	# --- Wegpunkt: gestrichelte Linie vom Flugzeug, Fahne am Ziel -----------------------
	if hat_wegpunkt():
		var wm := o + wegpunkt * k2
		if ac != null:
			var pa := o + Vector2(ac.global_position.x, ac.global_position.z) * k2
			var n_str := clampi(int(pa.distance_to(wm) / (7.0 * ui)), 2, 240)
			var lin := PackedVector2Array()
			for k in n_str + 1:
				lin.append(pa.lerp(wm, float(k) / float(n_str)))
			_gestrichelt(ci, lin, rect, Color(0, 0, 0, 0.6), maxf(2.0, 3.2 * ui), false)
			_gestrichelt(ci, lin, rect, C_WEG, maxf(1.2, 1.8 * ui), false)
		if rect.grow(-2.0).has_point(wm):
			var g := (0.7 if eck else 1.0) * ui
			var fuss := wm
			var spitze := wm + Vector2(0, -20.0 * g)
			ci.draw_line(fuss, spitze, Color(0, 0, 0, 0.85), 3.4 * g)
			ci.draw_line(fuss, spitze, Color(1, 1, 1, 0.95), 1.6 * g)
			var fahne := PackedVector2Array([spitze, spitze + Vector2(13.0 * g, 4.5 * g),
				spitze + Vector2(0, 9.0 * g)])
			ci.draw_colored_polygon(fahne, C_WEG)
			ci.draw_polyline(fahne + PackedVector2Array([fahne[0]]), Color(0, 0, 0, 0.85), 1.2 * g, true)
			ci.draw_circle(fuss, 3.2 * g, Color(0, 0, 0, 0.85))
			ci.draw_circle(fuss, 2.0 * g, C_WEG)
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


const LEGENDE := ["Flugplatz", "Ort", "Wahrzeichen", "Natur", "Flugabwehr", "Ziel",
	"Fluss", "Flugspur", "Wegpunkt", "Kurs"]


## Zeichen Nummer i der Legende an Stelle ic (dieselben Zeichen wie auf der Karte).
func _legende_icon(i: int, ic: Vector2, ui: float) -> void:
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
		8:
			var sp := ic + Vector2(-3, 7) * ui
			draw_line(sp, sp + Vector2(0, -14) * ui, Color(1, 1, 1, 0.95), 1.6 * ui)
			draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -14) * ui,
				sp + Vector2(10, -10.5) * ui, sp + Vector2(0, -7) * ui]), C_WEG)
		9:
			for k in 3:
				var x0 := -9.0 + 7.0 * k
				draw_line(ic + Vector2(x0, 0) * ui, ic + Vector2(x0 + 4.0, 0) * ui,
					Color(1, 1, 1, 0.8), 1.4 * ui)


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
	var ac := flieger()

	# GROSSES LAYOUT: fast bildschirmfuellend, rechts eine Seitenleiste. Vorher war die
	# Karte ein Quadrat von 74 % der Bildhoehe mitten im Bild, links und rechts lag das
	# abgedunkelte HUD brach.
	var rand := floorf(18.0 * ui)
	var pad := floorf(12.0 * ui)
	var head := floorf(50.0 * ui)
	var panel := Rect2(rand, rand, vs.x - 2.0 * rand, vs.y - 2.0 * rand)
	var seite_b := floorf(clampf(340.0 * ui, 0.0, panel.size.x * 0.32))
	_map_rect = Rect2(panel.position + Vector2(pad, head),
		Vector2(panel.size.x - 3.0 * pad - seite_b, panel.size.y - head - pad)).abs()
	_map_rect.position = _map_rect.position.floor()
	_map_rect.size = _map_rect.size.floor()
	var seite := Rect2(_map_rect.end.x + pad, _map_rect.position.y, seite_b, _map_rect.size.y)
	_klemmen()

	# Hintergrund kraeftig abdunkeln -> das HUD dahinter lenkt nicht mehr ab
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.05, 0.72))
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
	draw_style_box(hb, Rect2(panel.position, Vector2(panel.size.x, head - 6.0 * ui)))
	_kopf(panel, head - 6.0 * ui, ui)

	# --- Karte ------------------------------------------------------------------------
	var sicht := _sicht()
	var mpp := _mpp()
	zeichne_raster(self, _map_rect, sicht)

	# PLANQUADRATE (5 km) — beim Hineinzoomen zusaetzlich ein feines 1-km-Netz.
	if mpp < 26.0:
		_netz(sicht, 1000.0, Color(1, 1, 1, 0.06))
	_netz(sicht, QUADRAT, Color(1, 1, 1, 0.15))

	# VEKTOR-EBENEN
	var win_min := (sicht.position + Vector2(WORLD_R, WORLD_R)) / (2.0 * WORLD_R)
	var win_size := sicht.size / (2.0 * WORLD_R)
	var belegt := zeichne_ebenen(self, _map_rect, win_min, win_size, ui)
	_label_rects.clear()

	# Innenschatten am Kartenrand: gibt der Karte Tiefe, als laege sie unter Glas
	var schatten := 16.0 * ui
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

	_netz_beschriften(ui)

	# Windrose oben rechts
	var rose_r := 26.0 * ui
	var rose_m := Vector2(_map_rect.end.x - rose_r - 20.0 * ui, _map_rect.position.y + rose_r + 30.0 * ui)
	_windrose(rose_m, rose_r, ui)
	_label_rects.append(Rect2(rose_m - Vector2(rose_r + 6.0 * ui, rose_r + 22.0 * ui),
		Vector2(rose_r + 6.0 * ui, rose_r + 14.0 * ui) * 2.0))

	_label_rects.append(_massstab(mpp, ui))

	# MARKER ZUERST, BESCHRIFTUNGEN DANACH — und beide durch die Entzerrung.
	# Reihenfolge: alle Marker als belegte Flaeche eintragen (kein Name ueberdeckt einen
	# Punkt), dann Flugplatznamen (Vorrang), dann POI-Namen. Passt ein Name rechts nicht,
	# wird links, oben und unten probiert; passt er nirgends, entfaellt er — beim
	# Hineinzoomen hat er dann Platz. Flugplaetze zeichnet zeichne_ebenen (Symbol oder
	# echte Bahn); ihre Flaeche kommt als `belegt` zurueck.
	var fs_af := int(19.0 * ui)
	var fs_poi := int(17.0 * ui)
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
		if _map_rect.grow(-2.0).has_point(p):
			var fwd := -ac.global_transform.basis.z
			var a := atan2(fwd.x, fwd.z)
			var dirv := Vector2(sin(a), cos(a))
			var side := Vector2(-dirv.y, dirv.x)
			var L := 17.0 * ui
			var pts := PackedVector2Array([p + dirv * L, p - dirv * L * 0.55 + side * L * 0.62,
				p - dirv * L * 0.27, p - dirv * L * 0.55 - side * L * 0.62])
			draw_colored_polygon(pts, C_PLAYER)
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.95), maxf(1.5, 2.0 * ui))

	_tooltip(ac, ui)
	_seitenleiste(seite, ac, ui)


## RASTER in ein Kartenrechteck: Meer jenseits des Weltrands, Grundkarte, darueber die
## fertigen Detailkacheln (Stufe 1, dann 2 — was fehlt, faellt auf die groebere Stufe
## zurueck statt auf ein Loch). Fuer die grosse Karte UND die Minimap (`eck`); die
## Minimap meldet dabei ihren Ausschnitt, damit _process dort Kacheln vorlaedt.
func zeichne_raster(ci: CanvasItem, rect: Rect2, sicht: Rect2, eck := false) -> void:
	if _tex == null:
		return
	var k2 := rect.size / sicht.size
	var o := rect.position - sicht.position * k2
	ci.draw_rect(rect, _rand_farbe)
	var welt := Rect2(-WORLD_R, -WORLD_R, 2.0 * WORLD_R, 2.0 * WORLD_R)
	var g := sicht.intersection(welt)
	if g.has_area():
		var ts := Vector2(_tex.get_width(), _tex.get_height())
		ci.draw_texture_rect_region(_tex, Rect2(o + g.position * k2, g.size * k2),
			Rect2((g.position - welt.position) / welt.size * ts, g.size / welt.size * ts))
	var mpp := sicht.size.x / rect.size.x / _skala()
	if eck:
		_mini_sicht = sicht
		_mini_mpp = mpp
		_mini_frame = Engine.get_process_frames()
	if mpp >= KACHEL_AB:
		return
	var kpx := float(KACHEL_PX)
	for stufe in [1, 2]:
		var km := kachel_m(stufe)
		for key in _kacheln:
			if key.z != stufe:
				continue
			var kr := Rect2(-WORLD_R + float(key.x) * km, -WORLD_R + float(key.y) * km, km, km)
			var teil := kr.intersection(sicht)
			if not teil.has_area():
				continue
			ci.draw_texture_rect_region(_kacheln[key], Rect2(o + teil.position * k2, teil.size * k2),
				Rect2((teil.position - kr.position) / km * kpx, teil.size / km * kpx))


## Echte Bildpunkte je virtuellem UI-Punkt (Fensterskalierung canvas_items).
func _skala() -> float:
	if not is_inside_tree():
		return 1.0
	return maxf(0.25, get_viewport().get_final_transform().get_scale().x)


func _welt_rect_zu_schirm(w: Rect2) -> Rect2:
	var a := _welt_zu_schirm(w.position)
	var b := _welt_zu_schirm(w.end)
	return Rect2(a, b - a)


## Gitterlinien im Abstand `schritt` (Welt, vom Weltrand -R aus gezaehlt).
func _netz(sicht: Rect2, schritt: float, col: Color) -> void:
	var k := ceilf((sicht.position.x + WORLD_R) / schritt) * schritt - WORLD_R
	while k < minf(sicht.end.x, WORLD_R + 1.0):
		if k >= -WORLD_R:
			var gx := _welt_zu_schirm(Vector2(k, 0)).x
			draw_line(Vector2(gx, _map_rect.position.y), Vector2(gx, _map_rect.end.y), col, 1.0)
		k += schritt
	k = ceilf((sicht.position.y + WORLD_R) / schritt) * schritt - WORLD_R
	while k < minf(sicht.end.y, WORLD_R + 1.0):
		if k >= -WORLD_R:
			var gy := _welt_zu_schirm(Vector2(0, k)).y
			var x0 := maxf(_map_rect.position.x, _welt_zu_schirm(Vector2(-WORLD_R, 0)).x)
			var x1 := minf(_map_rect.end.x, _welt_zu_schirm(Vector2(WORLD_R, 0)).x)
			draw_line(Vector2(x0, gy), Vector2(x1, gy), col, 1.0)
		k += schritt


## Planquadrat-Beschriftung: Buchstaben oben, Zahlen links, je in Feldmitte.
func _netz_beschriften(ui: float) -> void:
	var fs_q := int(14.0 * ui)
	var qc := Color(1, 1, 1, 0.66)
	var links := maxf(_map_rect.position.x, _welt_zu_schirm(Vector2(-WORLD_R, 0)).x)
	for sp in BUCHSTABEN.length():
		var mx := (float(sp) + 0.5) * QUADRAT - WORLD_R
		var gx := _welt_zu_schirm(Vector2(mx, 0)).x
		if gx < _map_rect.position.x + 10.0 * ui or gx > _map_rect.end.x - 90.0 * ui:
			continue
		_shadow_text(F_BOLD, Vector2(gx - 4.0 * ui, _map_rect.position.y + fs_q + 4.0 * ui),
			BUCHSTABEN[sp], fs_q, qc)
	for ze in 14:
		var mz := (float(ze) + 0.5) * QUADRAT - WORLD_R
		var gy := _welt_zu_schirm(Vector2(0, mz)).y
		if gy < _map_rect.position.y + 24.0 * ui or gy > _map_rect.end.y - 50.0 * ui:
			continue
		_shadow_text(F_BOLD, Vector2(links + 6.0 * ui, gy + fs_q * 0.36), str(ze + 1), fs_q, qc)


## Massstab unten links: runde Laenge (0,5/1/2/5/10 km), die auf ~150 px passt, in vier
## Wechselfeldern wie auf einer Wanderkarte. Liefert das belegte Rechteck.
func _massstab(mpp: float, ui: float) -> Rect2:
	var soll := 150.0 * ui * mpp
	var laenge := 500.0
	for kand in [500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0]:
		if kand <= soll:
			laenge = kand
	var feld := laenge / mpp / 4.0
	var bar_y := _map_rect.end.y - 26.0 * ui
	var bar_x := _map_rect.position.x + 22.0 * ui
	var bh := 6.0 * ui
	draw_rect(Rect2(bar_x - 1.5 * ui, bar_y - 1.5 * ui, feld * 4.0 + 3.0 * ui, bh + 3.0 * ui), Color(0, 0, 0, 0.8))
	for i in 4:
		draw_rect(Rect2(bar_x + feld * i, bar_y, feld, bh),
			Color(1, 1, 1, 0.95) if i % 2 == 0 else Color(0.12, 0.13, 0.15))
	var fs_bar := int(15.0 * ui)
	_shadow_text(F_SEMI, Vector2(bar_x - 3.0 * ui, bar_y - 7.0 * ui), "0", fs_bar, C_TEXT)
	var txt := ("%.1f km" % (laenge / 1000.0)).replace(".0 km", " km").replace(".", ",")
	_shadow_text(F_SEMI, Vector2(bar_x + feld * 4.0 - 8.0 * ui, bar_y - 7.0 * ui), txt, fs_bar, C_TEXT)
	return Rect2(bar_x - 6.0 * ui, bar_y - 26.0 * ui, feld * 4.0 + 60.0 * ui, 40.0 * ui)


## Kopfzeile: Titel, Zoomfaktor, Knopf "Zu mir", Hinweis.
func _kopf(panel: Rect2, head: float, ui: float) -> void:
	var fs_title := int(27.0 * ui)
	var x := panel.position.x + 20.0 * ui
	var mitte_y := panel.position.y + head * 0.5
	_shadow_text(F_BOLD, Vector2(x, mitte_y + fs_title * 0.36), "KARTE", fs_title, C_TEXT)
	x += F_BOLD.get_string_size("KARTE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_title).x + 18.0 * ui
	var fs := int(16.0 * ui)
	var ztxt := ("%.1f×" % _zoom).replace(".", ",")
	var zb := StyleBoxFlat.new()
	zb.set_corner_radius_all(int(12.0 * ui))
	zb.bg_color = Color(1, 1, 1, 0.08)
	var zw := F_SEMI.get_string_size(ztxt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x + 20.0 * ui
	var zr := Rect2(x, mitte_y - 13.0 * ui, zw, 26.0 * ui)
	draw_style_box(zb, zr)
	draw_string(F_SEMI, Vector2(zr.position.x + 10.0 * ui, mitte_y + fs * 0.36), ztxt,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, C_TEXT)
	x = zr.end.x + 10.0 * ui
	# Knopf: zurueck zum Flugzeug (leuchtet, solange die Karte ihm folgt)
	var ktxt := "◎  ZU MIR"
	var kw := F_SEMI.get_string_size(ktxt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x + 24.0 * ui
	_knopf_folgen = Rect2(x, mitte_y - 13.0 * ui, kw, 26.0 * ui)
	var kb := StyleBoxFlat.new()
	kb.set_corner_radius_all(int(12.0 * ui))
	var ueber := _knopf_folgen.has_point(_maus)
	kb.bg_color = Color(0.25, 0.75, 0.95, 0.92) if _folgen else (Color(1, 1, 1, 0.22) if ueber else Color(1, 1, 1, 0.10))
	draw_style_box(kb, _knopf_folgen)
	draw_string(F_SEMI, Vector2(_knopf_folgen.position.x + 12.0 * ui, mitte_y + fs * 0.36), ktxt,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(0.02, 0.05, 0.08) if _folgen else C_TEXT)
	var hint := "M / Esc — schließen"
	var fs_hint := int(16.0 * ui)
	var hw := F_SEMI.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_hint).x
	_shadow_text(F_SEMI, Vector2(panel.end.x - hw - 20.0 * ui, mitte_y + fs_hint * 0.36), hint,
		fs_hint, C_MUTED)


## Tooltip am Cursor: Planquadrat, Entfernung und Peilung vom Flugzeug, Gelaendehoehe.
func _tooltip(ac: Node3D, ui: float) -> void:
	if _ziehen or not _map_rect.grow(-2.0).has_point(_maus):
		return
	var w := _schirm_zu_welt(_maus)
	if absf(w.x) > WORLD_R or absf(w.y) > WORLD_R:
		return
	var teile: Array = [planquadrat(Vector3(w.x, 0, w.y))]
	if ac != null:
		var d := w - Vector2(ac.global_position.x, ac.global_position.z)
		var brg := fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)
		teile.append(("%.1f km" % (d.length() / 1000.0)).replace(".", ","))
		teile.append("%03d°" % (int(round(brg)) % 360))
	if _terrain != null:
		var h := _terrain.height_at(w.x, w.y)
		teile.append("Meer" if h < TerrainWorld.SEA_Y else "%d m" % roundi(h - TerrainWorld.SEA_Y))
	var txt := "  ·  ".join(teile)
	var fs := int(15.0 * ui)
	var tw := F_SEMI.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	var box := Rect2(_maus + Vector2(16, 14) * ui, Vector2(tw + 20.0 * ui, 28.0 * ui))
	if box.end.x > _map_rect.end.x:
		box.position.x = _maus.x - box.size.x - 12.0 * ui
	if box.end.y > _map_rect.end.y:
		box.position.y = _maus.y - box.size.y - 12.0 * ui
	# Fadenkreuz
	draw_line(_maus + Vector2(-9, 0) * ui, _maus + Vector2(-3, 0) * ui, Color.WHITE, 1.5 * ui)
	draw_line(_maus + Vector2(3, 0) * ui, _maus + Vector2(9, 0) * ui, Color.WHITE, 1.5 * ui)
	draw_line(_maus + Vector2(0, -9) * ui, _maus + Vector2(0, -3) * ui, Color.WHITE, 1.5 * ui)
	draw_line(_maus + Vector2(0, 3) * ui, _maus + Vector2(0, 9) * ui, Color.WHITE, 1.5 * ui)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.9)
	sb.set_corner_radius_all(int(7.0 * ui))
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.set_border_width_all(1)
	draw_style_box(sb, box)
	draw_string(F_SEMI, Vector2(box.position.x + 10.0 * ui, box.position.y + 19.0 * ui), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, C_TEXT)


## SEITENLEISTE: Position, Wegpunkt, Flugplaetze (anklickbar), Legende, Bedienung.
func _seitenleiste(r: Rect2, ac: Node3D, ui: float) -> void:
	if r.size.x < 120.0:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.09, 0.115, 1.0)
	sb.set_corner_radius_all(int(9.0 * ui))
	draw_style_box(sb, r)
	var x := r.position.x + 16.0 * ui
	var xr := r.end.x - 16.0 * ui
	var y := r.position.y + 12.0 * ui
	var zeile := 27.0 * ui
	var fs := int(16.0 * ui)
	var fs_t := int(14.0 * ui)
	_seiten_klick.clear()

	# --- Position ---
	y = _abschnitt("POSITION", x, xr, y, ui)
	if ac != null:
		var gp := ac.global_position
		var f := -ac.global_transform.basis.z
		var kurs := fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)
		var v := 0.0
		if ac is RigidBody3D:
			v = (ac as RigidBody3D).linear_velocity.length() * 3.6
		for paar in [["Planquadrat", planquadrat(gp)], ["Höhe", "%d m" % roundi(gp.y)],
				["Kurs", "%03d°" % (int(round(kurs)) % 360)], ["Tempo", "%d km/h" % roundi(v)]]:
			_wertzeile(paar[0], paar[1], x, xr, y, fs, ui)
			y += zeile
	else:
		draw_string(F_SEMI, Vector2(x, y + 18.0 * ui), "kein Flugzeug", HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, fs, C_MUTED)
		y += zeile
	y += 8.0 * ui

	# --- Wegpunkt ---
	y = _abschnitt("WEGPUNKT", x, xr, y, ui)
	if hat_wegpunkt() and ac != null:
		var d := wegpunkt - Vector2(ac.global_position.x, ac.global_position.z)
		var brg := fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)
		var n := wegpunkt_name if wegpunkt_name != "" else planquadrat(Vector3(wegpunkt.x, 0, wegpunkt.y))
		_wertzeile(n, ("%.1f km  ·  %03d°" % [d.length() / 1000.0, int(round(brg)) % 360]).replace(".", ","),
			x, xr, y, fs, ui, C_WEG)
		y += zeile
		draw_string(F_SEMI, Vector2(x, y + 16.0 * ui), "Rechtsklick in die Karte: löschen",
			HORIZONTAL_ALIGNMENT_LEFT, xr - x, fs_t, C_MUTED)
		y += zeile
	else:
		draw_string(F_SEMI, Vector2(x, y + 16.0 * ui), "Klick in die Karte oder auf einen",
			HORIZONTAL_ALIGNMENT_LEFT, xr - x, fs_t, C_MUTED)
		y += 20.0 * ui
		draw_string(F_SEMI, Vector2(x, y + 16.0 * ui), "Flugplatz setzt einen Wegpunkt.",
			HORIZONTAL_ALIGNMENT_LEFT, xr - x, fs_t, C_MUTED)
		y += zeile
	y += 8.0 * ui

	# --- Flugplaetze, naechster zuerst; Klick = Wegpunkt ---
	y = _abschnitt("FLUGPLÄTZE", x, xr, y, ui)
	var liste: Array = []
	var von := Vector2.ZERO
	if ac != null:
		von = Vector2(ac.global_position.x, ac.global_position.z)
	for af in _airfields:
		var ap: Vector3 = af["pos"]
		liste.append([Vector2(ap.x, ap.z).distance_to(von), af])
	liste.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var legende_h := 36.0 * ui + ceilf(LEGENDE.size() / 2.0) * 24.0 * ui + 8.0 * ui
	var fuss_h := 3.0 * 21.0 * ui + 10.0 * ui
	var lage_h := 34.0 * ui + 2.0 * zeile
	var platz_bis := r.end.y - legende_h - fuss_h - lage_h - 10.0 * ui
	for e in liste:
		if y + zeile > platz_bis:
			break
		var af: Dictionary = e[1]
		var zr := Rect2(r.position.x + 6.0 * ui, y, r.size.x - 12.0 * ui, zeile)
		var ist_ziel: bool = hat_wegpunkt() and wegpunkt_name == String(af["name"])
		if zr.has_point(_maus) or ist_ziel:
			var hl := StyleBoxFlat.new()
			hl.set_corner_radius_all(int(6.0 * ui))
			hl.bg_color = Color(C_WEG.r, C_WEG.g, C_WEG.b, 0.18) if ist_ziel else Color(1, 1, 1, 0.08)
			draw_style_box(hl, zr)
		_seiten_klick.append([zr, af])
		var ap: Vector3 = af["pos"]
		var d := Vector2(ap.x, ap.z) - von
		var brg := fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)
		draw_circle(Vector2(x + 6.0 * ui, y + zeile * 0.5), 5.5 * ui, af.get("color", Color.WHITE))
		draw_string(F_SEMI, Vector2(x + 20.0 * ui, y + 19.0 * ui), String(af["name"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, C_TEXT)
		var wert := ("%.1f km  %03d°" % [float(e[0]) / 1000.0, int(round(brg)) % 360]).replace(".", ",")
		var ww := F_SEMI.get_string_size(wert, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_t).x
		draw_string(F_SEMI, Vector2(xr - ww, y + 19.0 * ui), wert, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			fs_t, C_MUTED)
		y += zeile

	# --- Lage: was noch steht (Flugabwehr) und was abzuschiessen ist (Ziele) ---
	var sam := 0
	var flak := 0
	var ziele := 0
	for nd in get_tree().get_nodes_in_group("target"):
		if nd is SamSite:
			if nd.get("_tot") != true:
				sam += 1
		elif nd is FlakGun:
			flak += 1       # zerstoerte Flak verlaesst die Gruppe sofort
		elif nd is Target:
			if nd.get("_dead") != true:
				ziele += 1
	y += 8.0 * ui
	y = _abschnitt("LAGE", x, xr, y, ui)
	_wertzeile("Flugabwehr", "%d Raketen  ·  %d Flak" % [sam, flak], x, xr, y, fs, ui,
		C_GEFAHR.lightened(0.35) if sam + flak > 0 else C_TEXT)
	y += zeile
	_wertzeile("Ziele in der Luft", str(ziele), x, xr, y, fs, ui, C_ZIEL)
	y += zeile

	# --- Legende (zwei Spalten) und Bedienung, unten angeschlagen ---
	var yl := r.end.y - legende_h - fuss_h
	yl = _abschnitt("LEGENDE", x, xr, yl, ui)
	var spalte := (xr - x) * 0.5
	for i in LEGENDE.size():
		var cx := x + spalte * float(i % 2)
		var cy := yl + 24.0 * ui * floorf(i / 2.0) + 12.0 * ui
		_legende_icon(i, Vector2(cx + 9.0 * ui, cy), ui)
		draw_string(F_SEMI, Vector2(cx + 26.0 * ui, cy + fs_t * 0.36), LEGENDE[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs_t, C_TEXT)
	var yf := r.end.y - fuss_h + 4.0 * ui
	for t in ["Ziehen: verschieben  ·  Rad: Zoom", "Klick: Wegpunkt  ·  Rechts: löschen",
			"Höhenlinien alle %d m" % int(LINIEN_M)]:
		draw_string(F_SEMI, Vector2(x, yf + 15.0 * ui), t, HORIZONTAL_ALIGNMENT_LEFT, xr - x,
			int(13.0 * ui), C_MUTED)
		yf += 21.0 * ui


## Abschnittstitel mit feiner Linie; gibt die y-Position darunter zurueck.
func _abschnitt(titel: String, x: float, xr: float, y: float, ui: float) -> float:
	var fs := int(13.0 * ui)
	draw_string(F_BOLD, Vector2(x, y + 16.0 * ui), titel, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs,
		Color(0.45, 0.80, 1.0, 0.95))
	var tw := F_BOLD.get_string_size(titel, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	draw_line(Vector2(x + tw + 10.0 * ui, y + 11.0 * ui), Vector2(xr, y + 11.0 * ui),
		Color(1, 1, 1, 0.12), 1.0)
	return y + 26.0 * ui


func _wertzeile(links: String, rechts: String, x: float, xr: float, y: float, fs: int,
		ui: float, farbe := C_TEXT) -> void:
	draw_string(F_SEMI, Vector2(x, y + 19.0 * ui), links, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, C_MUTED)
	var w := F_SEMI.get_string_size(rechts, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	draw_string(F_SEMI, Vector2(xr - w, y + 19.0 * ui), rechts, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, farbe)
