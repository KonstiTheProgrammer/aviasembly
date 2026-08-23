class_name CloudField
extends RefCounted

# WolkenMEER: eine dichte, rollende Kumulus-Decke (wie aus dem Flugzeug über den Wolken).
# Statt verstreuter Einzelwolken eine zusammenhängende Decke: Noise ballt die Wolken zu
# großen Feldern mit Löchern (Durchblick zum Boden), ein zweites Noise lässt die Deckenhöhe
# rollen (Hügel & Täler). KEINE Kollision -> man fliegt hindurch. Lebt in der Flug-Welt.
#
# DIE EINZELNE WOLKE hat zwei Haelften, die getrennt beschrieben sind:
#   FORM      -> _puff_mesh und _nachbearbeiten. Ein grosser Kern mit Schultern und
#                Knubbeln auf einer flachen Basis, dazu "globalisierte" Normalen.
#   MATERIAL  -> PUFF_SHADER. Wrap-Beleuchtung, kuehle Basis, Krume, Nahausblendung.
#
# WARUM DAS UEBERARBEITET WURDE (Stand vorher: /tmp/puffref/vor_*.png). Die Puffs lasen
# sich nicht als Kumulus, sondern als Kies- oder Popcornhaufen aus flach facettierten
# Kugeln, mit dunkelblaugrauer Schattenseite und einem sichtbaren Punktraster beim
# Annaehern. MASSSTAB war und ist der bereits abgenommene Himmels-Shader mit den gemalten
# Fernwolken: gemalte und volumetrische Wolken muessen sich in der Helligkeit treffen,
# sonst zerfaellt der Himmel in zwei Materialien. Gemessen wurde als mittlere Luma aller
# hellen, wenig gesaettigten Bildpunkte in je einem festen Rechteck pro Sorte:
#                 vorher                     jetzt
#   unter_decke   +1,9 Luma                  +4,3
#   ueber_decke   -9,3                       +8,4
#   hoch          -6,9                       +3,8
# Der Abstand bleibt damit auf beiden Seiten unter zehn Luma. Ausserdem stieg die
# Streuung auf der Wolke selbst (ein Mass dafuer, dass sie ueberhaupt Form hat) in
# ueber_decke von sd 26 — das waren zum guten Teil die harten Schattenflecken — auf eine
# gleichmaessige sd 22, bei den gemalten Wolken sd 18.
#
# KOSTEN, gemessen mit tools/_puff_mess.gd (M4 Pro, 1280x720, MSAA 4x, Kamera in der
# Decke, Sonne mit vier Schattenkaskaden):
#   Dreiecke je Wolke   1344 -> 1772 (+32 %); bei 520 gleichzeitigen Wolken 699k -> 922k
#   Bildzeit            1,73 ms -> 1,80 ms ueber je sechs Laeufe (+4 %). Die Streuung
#                       zwischen zwei Laeufen betraegt bis zu 0,2 ms — der Unterschied
#                       liegt also im Rauschen und ist keine belastbare Verschlechterung.
#   Bauzeit des Felds   80 ms -> 102 ms, einmalig beim Laden der Flugwelt
#   Zeichenaufrufe      unveraendert
# Die zusaetzlichen Dreiecke stecken NUR im Kern und in den Schultern, also genau in den
# beiden Lappenklassen, die aus der Naehe auf der Silhouette stehen und deren Facetten man
# in vor_zenit.png abzaehlen konnte.
#
# ---------------------------------------------------------------------------------------
# WAS AUS DER NAEHE NOCH NICHT STIMMT — hier stand vorher die Behauptung, die
# Oberflaechenstruktur komme aus der Beleuchtung ("Krume" im Shader) und das sei in einem
# Low-Poly-Spiel der billigere Hebel. Ein Kritiker hat das widerlegt und gemessen: die
# Krume traegt sd 1,2 bis 2,1 Luma auf einer Flaeche, deren Gesamtspanne 90 Luma betraegt,
# und aus 70 m sogar nur EINSEITIG, weil die Schulter des Tonemappers die helle Haelfte
# verschluckt. Aus 70 bis 160 m ist der Puff deshalb eine strukturlose weisse Wand mit
# geradkantiger Silhouette.
#
# Daraufhin sind BEULEN in die Geometrie gekommen (siehe _nachbearbeiten). Die sind
# nachweislich da — und trotzdem im Bild NICHT zu sehen. Der Grund ist gemessen, nicht
# vermutet: ein Probeschuss mit streuung = 0.02 statt 0.60
#     godot --path . --script res://tools/_sky_render.gd -- /tmp/p nur=puff_160 \
#           set=streuung:0.02 set=silber:0.0
# zeigt auf DERSELBEN Geometrie sofort kraeftige Schattierung und Facetten. Die
# Wrap-Beleuchtung mit streuung = 0.60 buegelt also jede Normalenvariation weg — sie war
# der Hebel gegen die harten Schattenflecken der alten Fassung, nimmt aber im selben Zug
# der Oberflaeche jede Form. WER HIER WEITERMACHT, muss an dieser Stelle ansetzen: eine
# Beleuchtung finden, die auf der SCHATTENSEITE weich bleibt (das war der Gewinn) und
# trotzdem auf mittlere Normalenunterschiede reagiert. Mehr Geometrie hilft nicht,
# solange das Licht sie nicht zeigt.
# Fuer diese Probe gibt es jetzt zwei feste Nahansichten im Werkzeug: puff_160 und
# puff_70 SUCHEN sich die groesste Wolke in der Naehe, statt auf eine feste Kamerapose zu
# hoffen — die alte Nahprobe "zenit" war wertlos geworden, weil dort nach einer
# Formaenderung gar keine Volumenwolke mehr stand.

# ---------------------------------------------------------------------------------------
# WOLKENSORTEN. Jede Sorte ist eine eigene Schicht mit eigener Hoehe, eigenem Raster und
# eigener Form; sie werden als getrennte Felder gebaut und getrennt mitgefuehrt.
#
# WARUM GETRENNTE FELDER statt einer Schicht mit gemischten Formen: das Raster bestimmt,
# wie dicht die Sorte steht, und die Sorten sind sehr unterschiedlich dicht. Haette man
# EIN Raster, muesste es das feinste sein — und die hohen, duennen Schichten haetten
# zehntausende Knoten, von denen fast alle unsichtbar waeren. Mit eigenem `spacing` je
# Sorte kostet eine seltene Schicht auch nur wenige hundert Knoten.
#
# HORIZONTALER HALBMESSER: er darf bei KEINER Sorte ueber 200 m gehen. In
# Main.WOLKEN_AREA stecken 207 m als Reserve, damit das Umschlagen ausserhalb des
# Sichtvolumens bleibt (Herleitung dort). Die Tuerme wachsen deshalb nach OBEN, nicht in
# die Breite.
const TYPEN := {
	# Schoenwetterkumulus — die Hauptdecke. Flache Basis, ballt sich zu Feldern.
	# HOEHE: stand auf 320 m und lag damit mitten im normalen Reiseflug — die Decke klebte
	# ueber dem Boden statt darueber zu haengen. Mit 900 m (Streuung ergibt Wolkenkoerper
	# von rund 570 bis 1230 m) ist sie da, wo eine Kumulusbasis hingehoert: deutlich ueber
	# dem Spieler, erreichbar nur, wenn er steigt.
	"kumulus": {
		"form": "kumulus", "spacing": 340.0, "layer_y": 900.0,
		"billow": 60.0, "layer_jitter": 130.0, "cover_thresh": -0.20,
	},
	# Quellwolken: hoch aufgetuermt, seltener als der Kumulus. Sie geben dem Luftraum eine
	# senkrechte Ausdehnung — man fliegt an ihnen VORBEI, nicht nur unter ihnen durch.
	# DICHTE GEMESSEN NACHGEZOGEN: mit spacing 1150 und cover_thresh 0.34 standen im
	# ganzen 34-km-Feld 130 sichtbare Tuerme, also einer je 9 km². Entlang einer 42-km-
	# Geraden waere man rechnerisch NICHT EIN EINZIGES MAL durch einen geflogen — als
	# Spielelement damit wertlos.
	"turm": {
		"form": "turm", "spacing": 860.0, "layer_y": 700.0,
		"billow": 130.0, "layer_jitter": 260.0, "cover_thresh": 0.02,
	},
	# Schaefchenwolken: kleine flache Ballen in grosser Hoehe. Sie machen Steigflug
	# lesbar — man sieht, dass man hoeher kommt, weil eine zweite Decke naeherrueckt.
	"schaefchen": {
		"form": "schaefchen", "spacing": 520.0, "layer_y": 2300.0,
		"billow": 90.0, "layer_jitter": 150.0, "cover_thresh": 0.10,
	},
	# Linsenwolken: glatte, liegende Linsen ganz oben. Selten, dafuer auffaellig.
	"linse": {
		"form": "linse", "spacing": 1900.0, "layer_y": 3400.0,
		"billow": 160.0, "layer_jitter": 320.0, "cover_thresh": 0.42,
	},
}


# --- DAMPFFAHNE UEBER EINEM KRATER -------------------------------------------------------
# WOFUER: ein Vulkan ohne Fahne ist ein schwarzer Berg. Von den drei Merkmalen, die ihn
# ueberhaupt als taetig lesbar machen — Asche, Glut, Fahne — ist die Fahne das einzige, das
# man noch aus zwanzig Kilometern sieht; die Glutrinnen sind dort laengst unter einem
# Bildpunkt breit. Sie ist damit die Silhouette des Wahrzeichens und nicht sein Detail.
#
# WARUM DIESELBEN PUFFS WIE DIE WOLKENDECKE und keine Partikel: die Fahne steht mit den
# Wolken im selben Bild. Zwei verschiedene Wolkenmaterialien in einer Ansicht fallen sofort
# auf (dieselbe Erfahrung wie bei den drei Wasser-Looks im Terrain), und der Puff-Shader
# traegt bereits alles, was hier gebraucht wird: Wrap-Licht, Silberrand gegen die Sonne und
# die Nahausblendung, damit man hindurchfliegen kann, ohne in eine weisse Wand zu geraten.
#
# SIE STEHT STILL. Aufsteigen und Verwehen waeren eine Animation je Frame fuer ein Objekt,
# das der Spieler fast immer aus mehreren Kilometern sieht — dort bewegt sich nichts
# sichtbar. Was die Saeule lebendig macht, ist ihre FORM: Halbmesser nach oben wachsend,
# seitlich abgetrieben und in der Achse versetzt.
static func fahne(parent: Node3D, opts := {}) -> Node3D:
	var fuss: Vector3 = opts.get("fuss", Vector3.ZERO)
	var hoehe := float(opts.get("hoehe", 1300.0))
	var r_unten := float(opts.get("r_unten", 110.0))
	var r_oben := float(opts.get("r_oben", 430.0))
	# Seitlicher Abtrieb, als Anteil der Fahnenhoehe. Senkrecht steht eine Fahne nur bei
	# absoluter Windstille, und im Bild liest sich eine senkrechte Saeule als Rauchsignal.
	# 0.8 sind rund 39 Grad Neigung. WENIGER GING NICHT: mit 0.34 stand die Saeule fast
	# senkrecht ueber dem Krater und verdeckte im Abnahmebild genau das, was man dort
	# pruefen will — Schuessel, Schlund und Innenwand. Jetzt zieht sie ueber den Rand
	# hinaus ab, und der Krater bleibt frei.
	var drift: Vector2 = opts.get("drift", Vector2(0.80, -0.10))
	var stufen := int(opts.get("stufen", 21))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 20260817))
	var root := Node3D.new()
	root.name = String(opts.get("name", "Fahne"))
	parent.add_child(root)
	var mat := _cloud_material()
	# Dampf mit Asche darin, nicht Schoenwetterkumulus: warmes Grau statt des kuehlen
	# Blaus, das eine Wolkenbasis vom Himmel zurueckbekommt.
	mat.set_shader_parameter("farbe_krone", Color(0.80, 0.79, 0.77))
	mat.set_shader_parameter("farbe_basis", Color(0.31, 0.30, 0.30))
	# Dunkler als die Decke (0.52). Eine Fahne in Kumulusweiss steht als hellster Fleck im
	# ganzen Bild und zieht das Auge vom Berg weg — sie soll aus ihm aufsteigen, nicht ihn
	# ueberstrahlen.
	mat.set_shader_parameter("helligkeit", 0.44)
	var src_kern := _kugel(20, 10)
	var src_schulter := _kugel(14, 7)
	var src_knubbel := _kugel(8, 4)
	var formen: Array = []
	for i in 4:
		formen.append(_puff_mesh("kumulus", src_kern, src_schulter, src_knubbel, rng))
	for i in stufen:
		var f := float(i) / float(maxi(stufen - 1, 1))
		var mesh: ArrayMesh = formen[rng.randi() % formen.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		# Kein Schattenwurf. Eine Fahne dieser Groesse legt sonst einen harten dunklen
		# Fleck ueber den halben Kegel — und ausgerechnet ueber den Teil, dessen Glut man
		# sehen soll.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.lod_bias = PUFF_LOD_BIAS
		mi.rotation.y = rng.randf() * TAU
		# DER HALBMESSER WAECHST MIT DER WURZEL. Linear waere ein Trichter mit geraden
		# Kanten; in Wirklichkeit reisst die Saeule gleich ueber dem Krater auf und wird
		# nach oben nur noch langsam breiter.
		# DIE STREUUNG JE STUFE IST NICHT KOSMETIK: mit gleich grossen Ballen auf einer
		# Achse las sich die Fahne als PERLENKETTE — man zaehlte die Kugeln. Erst wenn
		# benachbarte Ballen verschieden gross sind und einander seitlich verdecken,
		# verschmelzen sie zu einer Saeule.
		var r := lerpf(r_unten, r_oben, sqrt(f)) * rng.randf_range(0.78, 1.30)
		# EIGENMASS AUS DEM MESH statt einer Konstanten: _puff_mesh wuerfelt sein Grundmass
		# zwischen 54 und 78 aus, und wer dort etwas aendert, soll die Fahne nicht
		# stillschweigend umbauen.
		var ab := mesh.get_aabb()
		mi.scale = Vector3.ONE * (r / maxf(maxf(ab.size.x, ab.size.z) * 0.5, 1.0))
		# Die Stufen stehen unten DICHTER (Exponent > 1): dort ist der Halbmesser klein,
		# und mit gleichem Abstand klaffte zwischen den ersten beiden Ballen eine Luecke,
		# durch die man den Kraterrand sah.
		var y := hoehe * pow(f, 1.25)
		mi.position = fuss + Vector3(drift.x * y + rng.randf_range(-0.42, 0.42) * r, y,
			drift.y * y + rng.randf_range(-0.42, 0.42) * r)
		root.add_child(mi)
	return root


static func build(parent: Node3D, opts := {}) -> Node3D:
	var typ := String(opts.get("typ", "kumulus"))
	# Sortenvorgaben unterlegen: was in opts steht, gewinnt.
	var vorgabe: Dictionary = TYPEN.get(typ, TYPEN["kumulus"])
	for k in vorgabe:
		if not opts.has(k):
			opts[k] = vorgabe[k]
	var rng := RandomNumberGenerator.new()
	# Jede Sorte braucht einen EIGENEN Seed, sonst stehen alle Schichten senkrecht
	# uebereinander — dasselbe Ballungs-Noise, dieselben Loecher.
	rng.seed = int(opts.get("seed", 20240617)) + typ.hash()
	var root := Node3D.new()
	root.name = "CloudField_" + typ
	parent.add_child(root)

	var area: float = opts.get("area", 4400.0)            # halbe Kantenlänge des Felds (m) -> weit gestreut
	var spacing: float = opts.get("spacing", 340.0)       # Rasterabstand (größer -> mehr Abstand)
	var layer_y: float = opts.get("layer_y", 175.0)       # mittlere Höhe
	var billow: float = opts.get("billow", 30.0)          # sanftes Höhen-Rollen
	var layer_jitter: float = opts.get("layer_jitter", 55.0)  # Höhenstreuung je Wolke (3D-Verteilung)
	var cover_thresh: float = opts.get("cover_thresh", -0.05)  # höher = weniger/mehr verstreute Wolken

	# Ballungs-Noise (wo ist Wolke, wo Loch) + Höhen-Noise (rollende Höhe).
	var cov := FastNoiseLite.new()
	cov.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cov.frequency = 0.0021                                  # kleinere Ballungen -> mehr aufgelockert
	cov.seed = rng.seed
	var hgt := FastNoiseLite.new()
	hgt.noise_type = FastNoiseLite.TYPE_SIMPLEX
	hgt.frequency = 0.00085
	hgt.seed = rng.seed + 7

	var mat := _cloud_material()
	# DREI Kugel-Aufloesungen statt einer. Begruendung bei _puff_mesh: nur Kern und
	# Schultern stehen je gross auf der Silhouette, die Knubbel nie.
	var src_kern := _kugel(20, 10)         # 440 Dreiecke
	var src_schulter := _kugel(14, 7)      # 224 Dreiecke
	var src_knubbel := _kugel(8, 4)        #  80 Dreiecke

	# Mehrere Puff-Mesh-Varianten vorbauen und zufällig wiederverwenden.
	# EIGENER ZUFALLSSTROM FUER DIE FORM. Vorher zogen Formbau und Platzierung aus
	# demselben rng. Jede Aenderung an _puff_mesh — eine Kugel mehr, ein Wurf anders —
	# verschob damit ALLE folgenden Wuerfe und setzte die ganze Decke neu. Ein Kritiker
	# ist genau darueber gestolpert: nach einer reinen Formaenderung stand in der
	# Nahansicht "zenit" ueberhaupt keine Wolke mehr, und die Referenzbilder taugten
	# nicht mehr zum Vergleich. Mit getrennten Stroemen aendert Formarbeit nur die Form.
	var rng_form := RandomNumberGenerator.new()
	rng_form.seed = rng.seed ^ 0x5EED_F0F0
	var variants: Array = []
	for i in 10:
		variants.append(_puff_mesh(String(opts["form"]), src_kern, src_schulter,
			src_knubbel, rng_form))

	var half := int(area / spacing)
	var puffs: Array[MeshInstance3D] = []
	var zellen := {}
	for ix in range(-half, half + 1):
		for iz in range(-half, half + 1):
			var x := float(ix) * spacing + rng.randf_range(-0.4, 0.4) * spacing
			var z := float(iz) * spacing + rng.randf_range(-0.4, 0.4) * spacing
			var mi := MeshInstance3D.new()
			mi.mesh = variants[rng.randi() % variants.size()]
			mi.material_override = mat
			mi.rotation.y = rng.randf() * TAU
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# LOD AGGRESSIVER ALS ANDERE GEOMETRIE. generate_lods() legt die Stufen an
			# (siehe _nachbearbeiten); lod_bias bestimmt, wie frueh umgeschaltet wird —
			# und zwar NUR fuer die Wolken, Gelaende und Flugzeug behalten ihre Vorgabe.
			# ACHTUNG, DIE RICHTUNG IST KONTRAINTUITIV: ein HOEHERER lod_bias haelt die
			# Stufe HOEHER, also detaillierter. Aggressiv ist KLEIN. Gemessen in einer
			# reinen Wolkenansicht (1280x720, Kamera unter der Decke):
			#   lod_bias 1.0   89404 Primitive je Bild
			#   lod_bias 0.5   77944   (-13 %)
			#   lod_bias 0.3   62626   (-30 %)
			#   lod_bias 0.2   58138   (-35 %)
			# Eine Wolke ist eine weiche Form ohne Kanten, deren Silhouette in der Ferne
			# nur ein paar Bildpunkte gross ist — hier ist Detail am billigsten zu opfern.
			mi.lod_bias = PUFF_LOD_BIAS
			# KEIN visibility_range hier — siehe mitfuehren(), Absatz "Was nicht half".
			# Persoenliche Streuung der Wolke: sie ueberlebt das Umschlagen, damit dieselbe
			# Wolke am neuen Platz nicht ploetzlich eine andere Groesse und Hoehe hat.
			mi.set_meta("sk", rng.randf_range(0.8, 1.2))
			mi.set_meta("yj", rng.randf_range(-layer_jitter, layer_jitter))
			# WARUM AUCH LOECHER EINEN KNOTEN BEKOMMEN: beim Umschlagen (siehe mitfuehren)
			# wird das Ballungs-Noise am NEUEN Platz neu ausgewertet. Gaebe es an Loch-Plaetzen
			# gar keinen Knoten, koennte dort spaeter auch keine Wolke entstehen — nur
			# verschwinden. Die Decke waere nach ein paar Dutzend Kilometern Flug auf die
			# Haelfte ausgeduennt. Ein unsichtbarer MeshInstance3D kostet dagegen fast nichts.
			root.add_child(mi)
			puffs.append(mi)
			_setze_puff(mi, x, z, cov, hgt, layer_y, billow, cover_thresh, zellen, spacing)

	# Fuer mitfuehren(): Feldmasse, Noise und die fertige Kinderliste am Wurzelknoten
	# ablegen. Die Liste EINMAL bauen spart pro Aufruf ein get_children() ueber 3000 Knoten.
	root.set_meta("area", area)
	root.set_meta("layer_y", layer_y)
	root.set_meta("billow", billow)
	root.set_meta("cover_thresh", cover_thresh)
	root.set_meta("cov", cov)
	root.set_meta("hgt", hgt)
	root.set_meta("puffs", puffs)
	root.set_meta("mitte", Vector2.ZERO)
	root.set_meta("zellen", zellen)
	root.set_meta("spacing", spacing)
	return root


# Setzt eine Wolke auf einen Weltplatz und liest Loch, Groesse und Hoehe dort neu aus.
static func _setze_puff(mi: MeshInstance3D, x: float, z: float, cov: FastNoiseLite,
		hgt: FastNoiseLite, layer_y: float, billow: float, cover_thresh: float,
		zellen = null, spacing: float = 340.0) -> void:
	var c := cov.get_noise_2d(x, z)                     # -1..1
	mi.visible = c >= cover_thresh                      # darunter: Loch in der Decke
	# Dichte: an den Rändern der Wolkenfelder dünn/klein, in den Zentren dick/groß.
	var dens := smoothstep(cover_thresh, cover_thresh + 0.55, c)
	# Höhe rollt sanft + je Wolke gestreut -> die Wolken liegen NICHT in einer flachen
	# Ebene, sondern verteilt über verschiedene Höhen (wirkt natürlicher, weniger "Block").
	var cy: float = layer_y + hgt.get_noise_2d(x, z) * billow + float(mi.get_meta("yj", 0.0))
	mi.position = Vector3(x, cy, z)
	mi.scale = Vector3.ONE * lerp(0.65, 1.4, dens) * float(mi.get_meta("sk", 1.0))

	# --- Zellenregister fuer dichte_bei() ---------------------------------------------
	# Ohne das muesste jede Abfrage "steckt der Spieler in einer Wolke" ueber alle 15892
	# Knoten laufen — jeden Frame, fuer Turbulenz, Sicht und Flak. Mit dem Register sind
	# es die neun Zellen um den Punkt. Gepflegt wird es genau hier, weil dies die EINZIGE
	# Stelle ist, an der eine Wolke ihren Platz wechselt.
	# `null` heisst "kein Register gewuenscht". Vorher stand hier eine Pruefung auf
	# is_empty() — die hat beim ALLERERSTEN Puff zugeschlagen, weil ein frisches Register
	# nun einmal leer ist, und damit blieb es fuer immer leer. Die Abfrage fand daraufhin
	# an keiner einzigen Wolkenmitte eine Wolke.
	if zellen == null:
		return
	var reg: Dictionary = zellen
	var neu := Vector2i(int(floorf(x / spacing)), int(floorf(z / spacing)))
	var alt: Vector2i = mi.get_meta("zelle", Vector2i(2147483647, 0))
	if alt == neu:
		return
	if reg.has(alt):
		(reg[alt] as Array).erase(mi)
		if (reg[alt] as Array).is_empty():
			reg.erase(alt)
	if not reg.has(neu):
		reg[neu] = []
	(reg[neu] as Array).append(mi)
	mi.set_meta("zelle", neu)
	# Wirkkoerper EINMAL merken statt bei jeder Abfrage aus der AABB zu holen.
	# ALS ECHTES ELLIPSOID mit eigener Hoehe, nicht als Kugel mit pauschaler Stauchung:
	# ein Turm ist dreimal so hoch wie breit, eine Linse ein Drittel so hoch. Mit einem
	# festen Stauchfaktor waere der Turm oben und unten offen und die Linse ein Ballon.
	# Auch der MITTELPUNKT muss mit: die Meshes sitzen nicht auf ihrem Knotenursprung,
	# sondern haben eine flache Basis darunter.
	if mi.mesh != null:
		var bb := mi.mesh.get_aabb()
		mi.set_meta("wc", bb.get_center() * mi.scale.x)
		mi.set_meta("wr", bb.size * 0.5 * mi.scale.x)


## Wie tief steckt `pos` in einer Wolke dieses Feldes? 0 = freie Luft, 1 = mitten drin.
##
## Bewusst eine WEICHE Zahl und keine Ja/Nein-Antwort: Turbulenz, Sichtverlust und
## Flak-Deckung sollen beim Ein- und Ausfliegen an- und abschwellen, nicht umschalten.
## Die Wolke wird dabei als liegendes Ellipsoid genaehert (waagerecht der gemessene
## Wirkradius, senkrecht 0,62 davon) — genau genug fuer Spielmechanik und ohne jede
## Geometrieabfrage.
static func dichte_bei(root: Node3D, pos: Vector3) -> float:
	if root == null or not is_instance_valid(root) or not root.has_meta("zellen"):
		return 0.0
	var zellen: Dictionary = root.get_meta("zellen")
	var spacing: float = root.get_meta("spacing", 340.0)
	var zx := int(floorf(pos.x / spacing))
	var zz := int(floorf(pos.z / spacing))
	var beste := 0.0
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var liste = zellen.get(Vector2i(zx + dx, zz + dz))
			if liste == null:
				continue
			for mi: MeshInstance3D in liste:
				if not mi.visible:
					continue
				var r: Vector3 = mi.get_meta("wr", Vector3.ZERO)
				if r.x <= 0.0 or r.y <= 0.0 or r.z <= 0.0:
					continue
				var d: Vector3 = pos - (mi.position + mi.get_meta("wc", Vector3.ZERO))
				var q := Vector3(d.x / r.x, d.y / r.y, d.z / r.z).length()
				# Die AABB ist grosszuegiger als die Wolke — ein Kumulus fuellt seinen
				# Kasten nicht aus. Deshalb sitzt der Vollwert schon bei q = 0.45 und die
				# Null erst bei q = 1.0, statt beides an den Kastenrand zu legen.
				beste = maxf(beste, 1.0 - smoothstep(0.45, 1.0, q))
	return beste


## Dieselbe Frage ueber MEHRERE Schichten. Liefert den groessten Wert.
static func dichte_bei_allen(felder: Array, pos: Vector3) -> float:
	var d := 0.0
	for f in felder:
		d = maxf(d, dichte_bei(f as Node3D, pos))
		if d >= 0.999:
			break
	return d


## Haelt die Decke um `mitte` herum geschlossen. Gibt zurueck, wie viele Wolken
## umgeschlagen sind (0 = nichts zu tun).
##
## WARUM NICHT MEHR NACHZIEHEN: vorher driftete der GANZE Block gedaempft hinter dem
## Spieler her. Das kann per Konstruktion nie aufholen — im Gleichgewicht bleibt ein
## Rueckstand von TOTZONE + Tempo/RATE stehen, gemessen 4,2 km bei 60 m/s bis 4,6 km bei
## 170 m/s. Bei einer halben Kantenlaenge von 9,5 km endete die Decke damit rund 5 km VOR
## der Nase, und zwischen der letzten Wolke und dem Horizont klaffte ein leeres Band.
## Einen hoeheren Deckel zu setzen half nicht: der Deckel bestimmt nur, OB ein
## Gleichgewicht erreicht wird, nicht WO es liegt.
##
## Stattdessen steht jetzt jede Wolke bombenfest auf ihrem Weltplatz — die Parallaxe ist
## damit vollstaendig, auch im Tiefflug. Nur die einzelne Wolke, die weiter als eine halbe
## Kantenlaenge zuruecksteht, springt um eine ganze Kantenlaenge nach vorn. Am neuen Platz
## werden Ballung und Hoehe neu ausgewertet, sonst waere die Decke eine Kachel, die sich
## alle zwei Kantenlaengen wiederholt.
##
## WIE GROSS `area` SEIN MUSS, DAMIT MAN DEN SPRUNG NICHT SIEHT:
## Die Umschlaggrenze ist eine an den WELTACHSEN ausgerichtete Box (|dx| > area), das
## Sichtvolumen dagegen ein Pyramidenstumpf entlang der Blickachse. Es genuegt deshalb
## NICHT, area mit der Fernebene zu vergleichen — beide fallen nur zusammen, wenn man
## exakt parallel zu einer Weltachse fliegt. Schraeg liegt dieselbe Boxflaeche nur noch
## area*cos(Gierwinkel) tief. Gemessen mit area = 10500 gegen eine 9-km-Fernebene:
## achsenparallel 0 von 165 Umschlaegen sichtbar, bei 21,9 Grad (der Peilung der Route
## zur Vulkaninsel!) 87,9 %, bei 45 Grad 90,9 % — rund 2,9 auftauchende Wolken je
## Sekunde bei 140 m/s.
##
## Massgeblich ist die am weitesten entfernte ECKE der Fernebene, nicht die Fernebene.
## Sie haengt am Seitenverhaeltnis — aber nur scheinbar: ViewUtil.apply_vfov nagelt fuer
## Schirme breiter als 16:9 den HORIZONTALEN Sichtwinkel fest und laesst stattdessen den
## vertikalen schrumpfen. Damit liegt das Maximum ausgerechnet bei 16:9, und eine einzige
## Konstante deckt jeden Schirm ab.
##
## Sie haengt aber sehr wohl am SICHTWINKEL, und der ist nicht fest: FlightController
## weitet die Kamera mit der Geschwindigkeit von 64 auf 74 Grad auf (FOV_MAX bei
## 170 m/s). Bei 9 km Fernebene und 16:9:
##   64 Grad -> 14580 m      74 Grad -> 16503 m
## Wer mit 64 rechnet, sieht den Umschlag also genau dann, wenn er schnell fliegt.
##
## WAS NICHT HALF: die Puffs ueber visibility_range_end ausblenden zu lassen, statt das
## Feld zu vergroessern. Zwei Gruende, beide gemessen:
##   - VISIBILITY_RANGE_FADE_SELF wirkt auf dem opaken Wolkenmaterial gar nicht. Die
##     Wolke steht bei 8900 m voll im Bild, wo die Rampe schon bei 8 Prozent Deckung
##     sein muesste; die Pixelzahl folgt reinem 1/d^2, ohne jede Ausduennung.
##   - visibility_range_end_margin verlaengert den Schnitt nach AUSSEN: die echte
##     Cull-Schale liegt bei end + margin. Aus 9000 + 1200 wurden 10200 m, und weil auch
##     eine KUGELschale nicht zum Pyramidenstumpf passt, poppten dort gemessene 4,1
##     Wolken je Sekunde. Der Sprung war damit nicht weg, nur um 300 m verschoben.
##
## `pass_weg` ist die Strecke, nach der jede Wolke einmal geprueft wurde. Sie geht als
## Reserve in `area` ein: eine Wolke kann bis zu `pass_weg` Meter zu spaet umschlagen und
## landet dann entsprechend naeher.
static func mitfuehren(root: Node3D, mitte: Vector3, pass_weg := 200.0) -> int:
	if root == null or not is_instance_valid(root) or not root.has_meta("puffs"):
		return 0
	var m2 := Vector2(mitte.x, mitte.z)
	var alt: Vector2 = root.get_meta("mitte", Vector2.ZERO)
	var gefahren := m2.distance_to(alt)
	root.set_meta("mitte", m2)

	var area: float = root.get_meta("area", 4400.0)
	var kante := area * 2.0
	var layer_y: float = root.get_meta("layer_y", 175.0)
	var billow: float = root.get_meta("billow", 30.0)
	var cover_thresh: float = root.get_meta("cover_thresh", -0.05)
	var cov: FastNoiseLite = root.get_meta("cov")
	var hgt: FastNoiseLite = root.get_meta("hgt")
	var puffs: Array = root.get_meta("puffs")
	var zellen: Dictionary = root.get_meta("zellen", {})
	var spacing: float = root.get_meta("spacing", 340.0)

	# NICHT alle Wolken auf einmal pruefen, sondern einen ueber die Strecke wandernden
	# Ausschnitt. Ein voller Durchlauf ueber 10201 Knoten kostet rund 1,9 ms; als Zacken
	# alle paar hundert Meter ist das ein Achtel Frame. Verteilt auf die Strecke bleiben
	# je Frame ein paar Dutzend Knoten uebrig, und die Kosten sind gleichmaessig.
	# An der Strecke und nicht an der Bildrate ausgerichtet: sonst haenge die Reserve, die
	# `area` einplant, von der Bildrate ab.
	var n := puffs.size()
	var anteil := clampf(gefahren / maxf(pass_weg, 1.0), 0.0, 1.0)
	var wieviel := int(ceil(float(n) * anteil))
	if wieviel <= 0:
		return 0
	var cursor: int = root.get_meta("cursor", 0)

	var umgeschlagen := 0
	for i in wieviel:
		var mi: MeshInstance3D = puffs[(cursor + i) % n]
		var p := mi.position
		# roundi statt einer Schwellenabfrage: faengt auch einen Sprung ueber mehrere
		# Kantenlaengen in einem Schritt ab (Respawn, Schnellreise).
		var kx := roundi((p.x - m2.x) / kante)
		var kz := roundi((p.z - m2.y) / kante)
		if kx == 0 and kz == 0:
			continue
		_setze_puff(mi, p.x - float(kx) * kante, p.z - float(kz) * kante,
			cov, hgt, layer_y, billow, cover_thresh, zellen, spacing)
		umgeschlagen += 1
	root.set_meta("cursor", (cursor + wieviel) % n)
	return umgeschlagen


# Wert-Rauschen im Objektraum, Rueckgabe rund -1..1. Bewusst ohne FastNoiseLite: das
# laeuft hier nur beim Bauen der zehn Formvarianten, und ein eigener Hash haelt das
# Ergebnis unabhaengig von Godot-Versionsdetails reproduzierbar.
static func _beule(p: Vector3) -> float:
	var i := Vector3(floorf(p.x), floorf(p.y), floorf(p.z))
	var f := p - i
	f = f * f * (Vector3(3.0, 3.0, 3.0) - 2.0 * f)     # weiche Kante zwischen den Zellen
	var v := 0.0
	for k in 8:
		var o := Vector3(float(k & 1), float((k >> 1) & 1), float((k >> 2) & 1))
		var w := ((1.0 - o.x) + (2.0 * o.x - 1.0) * f.x) \
			* ((1.0 - o.y) + (2.0 * o.y - 1.0) * f.y) \
			* ((1.0 - o.z) + (2.0 * o.z - 1.0) * f.z)
		var g := i + o
		var h := sin(g.x * 127.1 + g.y * 311.7 + g.z * 74.7) * 43758.5453
		v += (h - floorf(h)) * w
	return v * 2.0 - 1.0


static func _kugel(segmente: int, ringe: int) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = segmente
	s.rings = ringe
	return s


# ---------------------------------------------------------------------------------------
# EIN KUMULUS. Vorher: 7 bis 11 gleich grosse Kugeln, flach in einer Scheibe verteilt
# (rad = sqrt(zufall) * base * 1.25 verteilt GLEICHVERTEILT AUF DER FLAECHE, also
# ueberwiegend nach AUSSEN). Ergebnis war in /tmp/puffref/vor_ueber_decke.png und
# vor_hoch.png als Haufen einzeln abzaehlbarer Kugeln zu sehen — "Kieshaufen", "Popcorn".
# Zwei Ursachen, beide hier behoben:
#
#  1. KEIN VORHERRSCHENDER KOERPER. Wenn alle Lappen gleich gross sind und einander nur
#     streifen, liest das Auge N Kugeln statt EINER Wolke. Jetzt gibt es eine Rangordnung:
#     ein grosser Kern traegt das Volumen, 3 bis 4 Schultern haengen sich mit starker
#     Ueberlappung daran (ihre Mitten liegen innerhalb von 1,06*S, ihre Halbmesser gehen
#     bis 0,80*S — sie durchdringen den Kern also tief), und 5 bis 7 kleine Knubbel sitzen
#     auf Kuppe und Flanken und geben die Blumenkohl-Krume. Die Silhouette gehoert damit
#     fast immer dem Kern; die Knubbel brechen sie nur auf.
#
#  2. FLACHE BASIS. Kumulus haben eine flache Unterseite (das Kondensationsniveau ist eine
#     Ebene). Vorher hingen die Lappen bis 1,03*S unter den Ursprung und die Wolke war
#     unten so rund wie oben — das ist die Form eines Steins, nicht die einer Quellwolke.
#     Alles unter der Basisebene wird jetzt auf 30 % gestaucht: flach genug, dass es als
#     Kondensationsniveau liest, aber ohne die rasierklingenscharfe Kante, die ein hartes
#     Abschneiden ergaebe.
#
# HALBMESSER: der groesste waagerechte Abstand vom Ursprung ist jetzt 1,98*S bei S <= 56,
# also 111 m; mal der groessten Skalierung (1,4 aus der Dichte * 1,2 persoenlich) 186 m.
# VORHER waren es 192 m. Der Puff ist also NICHT groesser geworden — die 207 m Reserve in
# Main.WOLKEN_AREA bleiben unangetastet. (Hoehe dagegen: 1,79*S statt 2,6*S mal einer
# kleineren Basis — gemessen 168 m statt 135 m, die Wolken sind also hoeher als breit
# geworden, was fuer Kumulus richtig ist. Die Hoehe geht in keine Feldrechnung ein.)
#
# BASISEBENE bei -0,50*S: die Wolke wird an ihrem Ursprung aufgehaengt, und der Ursprung
# soll dort bleiben, wo er war, sonst wandert die ganze Decke in der Hoehe. Alter
# Schwerpunkt lag bei rund 0,29*S ueber dem Ursprung, neuer bei 0,32*S.
static func _puff_mesh(form: String, src_kern: SphereMesh, src_schulter: SphereMesh,
		src_knubbel: SphereMesh, rng: RandomNumberGenerator) -> ArrayMesh:
	match form:
		"turm":
			return _form_turm(src_kern, src_schulter, src_knubbel, rng)
		"schaefchen":
			return _form_schaefchen(src_schulter, src_knubbel, rng)
		"linse":
			return _form_linse(src_kern, src_knubbel, rng)
	# Vorgabe: Schoenwetterkumulus.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := rng.randf_range(54.0, 78.0)       # Grundmass der Wolke
	var basis_y := -0.50 * s                   # Hoehe des Kondensationsniveaus im Mesh
	var traeger: Array = []                    # [Mitte, Halbmesser] von Kern und Schultern

	# Kern: das Volumen. Leicht aus der Mitte gerueckt, damit die Wolke nicht
	# rotationssymmetrisch wird.
	var kern_m := Vector3(rng.randf_range(-0.10, 0.10) * s, basis_y + 0.66 * s,
		rng.randf_range(-0.10, 0.10) * s)
	var kern_r := Vector3(0.98 * s, 0.92 * s, 0.98 * s)
	traeger.append([kern_m, kern_r])
	st.append_from(src_kern, 0, Transform3D(Basis().scaled(kern_r), kern_m))

	# Schultern: gleichmaessig um den Kern verteilt (plus Streuung), damit keine Seite leer
	# bleibt. Sie sitzen TIEFER als der Kern -> die Wolke laeuft nach aussen keilfoermig
	# auf die Basisebene zu, statt als Kugel auszulaufen.
	var n_schulter := rng.randi_range(3, 4)
	var a0 := rng.randf() * TAU
	for i in n_schulter:
		var ang := a0 + TAU / float(n_schulter) * float(i) + rng.randf_range(-0.35, 0.35)
		var rad := rng.randf_range(0.78, 1.06) * s
		var r := rng.randf_range(0.58, 0.80) * s
		var m := Vector3(cos(ang) * rad, basis_y + rng.randf_range(0.30, 0.52) * s,
			sin(ang) * rad)
		var hr := Vector3(r, r * rng.randf_range(0.82, 0.96), r)
		traeger.append([m, hr])
		st.append_from(src_schulter, 0, Transform3D(Basis().scaled(hr), m))

	# Knubbel: sitzen auf der oberen Haelfte und den FLANKEN eines Traegers (t ab -0.10,
	# also knapp unter dessen Aequator) und ragen nur zu 72 % seines Halbmessers heraus.
	# Sie sind Krume, keine eigenen Wolken.
	# WARUM AUCH DIE FLANKEN: mit t >= 0.50 sassen sie ausschliesslich obenauf. Von UNTEN
	# — und das ist der Blick, den man aus dem Cockpit die meiste Zeit hat — war eine nahe
	# Wolke dann eine voellig glatte Kuppel ohne einen einzigen Anhaltspunkt. Der
	# Basisebene kommen sie trotzdem nicht ins Gehege: was unter sie gerutscht ist,
	# staucht der Durchgang unten mit weg.
	for i in rng.randi_range(5, 7):
		var host: Array = traeger[rng.randi() % traeger.size()]
		var hm: Vector3 = host[0]
		var hr: Vector3 = host[1]
		var phi := rng.randf() * TAU
		var t := rng.randf_range(-0.10, 0.95)
		var q := sqrt(1.0 - t * t)
		var d := Vector3(cos(phi) * q, t, sin(phi) * q)
		var r := rng.randf_range(0.26, 0.42) * s
		st.append_from(src_knubbel, 0, Transform3D(Basis().scaled(Vector3(r, r, r)),
			hm + Vector3(d.x * hr.x, d.y * hr.y, d.z * hr.z) * 0.72))

	st.generate_normals()
	return _nachbearbeiten(st.commit(), s, basis_y)


# QUELLWOLKE (Cumulus congestus). Waechst nach OBEN, nicht in die Breite: der
# horizontale Halbmesser muss unter 200 m bleiben (siehe TYPEN), die Hoehe darf das
# Mehrfache davon sein. Aufbau ist ein Stapel aus drei bis vier Ballen mit nach oben
# abnehmendem Halbmesser, seitlich leicht versetzt — das gibt die typische
# Blumenkohl-Saeule statt eines Zylinders. Unten breit und flach aufsitzend.
static func _form_turm(src_kern: SphereMesh, src_schulter: SphereMesh,
		src_knubbel: SphereMesh, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := rng.randf_range(44.0, 60.0)
	var basis_y := -0.50 * s
	var traeger: Array = []
	var n := rng.randi_range(3, 4)
	var y := basis_y + 0.62 * s
	var drift := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	for i in n:
		# Der Stapel verjuengt sich nach oben und lehnt sich leicht in eine Richtung —
		# senkrecht uebereinander gesetzte Kugeln lesen sich als Schneemann.
		var f := 1.0 - 0.20 * float(i)
		var r := Vector3(0.92 * s * f, 0.86 * s * f, 0.92 * s * f)
		var seit := drift * (float(i) * rng.randf_range(0.10, 0.26) * s)
		var m := Vector3(seit.x, y, seit.y)
		traeger.append([m, r])
		st.append_from(src_kern if i == 0 else src_schulter, 0,
			Transform3D(Basis().scaled(r), m))
		y += r.y * rng.randf_range(1.05, 1.30)
	# Schultern nur unten: die Saeule soll auf einem breiten Fuss stehen.
	for i in rng.randi_range(2, 3):
		var ang := rng.randf() * TAU
		var r := rng.randf_range(0.44, 0.62) * s
		var m := Vector3(cos(ang) * rng.randf_range(0.70, 0.95) * s,
			basis_y + rng.randf_range(0.22, 0.44) * s, sin(ang) * rng.randf_range(0.70, 0.95) * s)
		var hr := Vector3(r, r * 0.86, r)
		traeger.append([m, hr])
		st.append_from(src_schulter, 0, Transform3D(Basis().scaled(hr), m))
	_knubbel_streuen(st, src_knubbel, traeger, s, rng, 6, 9, 0.22, 0.36)
	st.generate_normals()
	return _nachbearbeiten(st.commit(), s, basis_y)


# SCHAEFCHEN (Altocumulus). Klein, flach, in grosser Hoehe. Bewusst wenig Geometrie —
# aus 2000 m Entfernung ist so eine Wolke nur ein paar Dutzend Pixel gross.
static func _form_schaefchen(src_schulter: SphereMesh, src_knubbel: SphereMesh,
		rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := rng.randf_range(16.0, 26.0)
	var basis_y := -0.28 * s
	var traeger: Array = []
	for i in rng.randi_range(2, 3):
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(0.0, 0.55) * s
		var r := rng.randf_range(0.62, 0.92) * s
		# Deutlich gestaucht: Altocumulus sind Ballen, keine Kugeln.
		var hr := Vector3(r, r * rng.randf_range(0.42, 0.58), r)
		var m := Vector3(cos(ang) * rad, basis_y + hr.y * 0.9, sin(ang) * rad)
		traeger.append([m, hr])
		st.append_from(src_schulter, 0, Transform3D(Basis().scaled(hr), m))
	_knubbel_streuen(st, src_knubbel, traeger, s, rng, 2, 4, 0.24, 0.36)
	st.generate_normals()
	return _nachbearbeiten(st.commit(), s, basis_y)


# LINSENWOLKE (Altocumulus lenticularis). Eine glatte, stark abgeflachte Linse, in einer
# Richtung gestreckt. Sie bekommt ABSICHTLICH kaum Knubbel: das Glatte ist ihr Merkmal.
static func _form_linse(src_kern: SphereMesh, src_knubbel: SphereMesh,
		rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := rng.randf_range(40.0, 58.0)
	var basis_y := -0.16 * s
	var traeger: Array = []
	var laengs := rng.randf_range(1.35, 1.85)          # Streckung in eine Richtung
	for i in 2:
		var f := 1.0 - 0.34 * float(i)                 # zweite, kleinere Linse obenauf
		var hr := Vector3(1.05 * s * laengs * f, 0.30 * s * f, 0.78 * s * f)
		var m := Vector3(0.0, basis_y + hr.y * (0.85 + 0.9 * float(i)), 0.0)
		traeger.append([m, hr])
		st.append_from(src_kern, 0, Transform3D(Basis().scaled(hr), m))
	_knubbel_streuen(st, src_knubbel, traeger, s, rng, 1, 2, 0.14, 0.22)
	st.generate_normals()
	return _nachbearbeiten(st.commit(), s, basis_y)


# Knubbel auf die obere Haelfte und die Flanken der Traeger streuen. Gemeinsam genutzt,
# damit alle Sorten dieselbe Regel benutzen (Begruendung siehe Kumulus).
static func _knubbel_streuen(st: SurfaceTool, src: SphereMesh, traeger: Array, s: float,
		rng: RandomNumberGenerator, n_min: int, n_max: int, r_min: float, r_max: float) -> void:
	for i in rng.randi_range(n_min, n_max):
		var host: Array = traeger[rng.randi() % traeger.size()]
		var hm: Vector3 = host[0]
		var hr: Vector3 = host[1]
		var phi := rng.randf() * TAU
		var t := rng.randf_range(-0.10, 0.95)
		var q := sqrt(maxf(1.0 - t * t, 0.0))
		var d := Vector3(cos(phi) * q, t, sin(phi) * q)
		var r := rng.randf_range(r_min, r_max) * s
		st.append_from(src, 0, Transform3D(Basis().scaled(Vector3(r, r, r)),
			hm + Vector3(d.x * hr.x, d.y * hr.y, d.z * hr.z) * 0.72))


# Zweiter Durchgang ueber die Ecken: flache Basis, "globalisierte" Normalen, Hoehenwert
# in die Eckenfarbe. Laeuft nur beim Bauen (10 Varianten), kostet zur Laufzeit nichts.
#
# WARUM DIE NORMALEN GEDREHT WERDEN — das ist der eigentliche Hebel gegen den
# Kieshaufen-Eindruck: generate_normals() gibt jeder Kugel ihre EIGENE Normale, also jedem
# Lappen einen vollen Hell-Dunkel-Verlauf von der Sonnenseite zur Schattenseite. Das Auge
# liest daraus N Koerper. Eine echte Wolke streut das Licht im Inneren so oft, dass die
# Beleuchtung der GESAMTFORM folgt und die Lappen nur noch eine Kruemelstruktur
# obendrauf sind. Genau das macht die Mischung mit der Normalen eines umschliessenden
# Ellipsoids. Kostet kein einziges Dreieck.
# WERT GEMESSEN: bei 0,5 war die Wolke eine strukturlose weisse Masse (Streuung der
# Bildwerte auf der Wolke sd 11,1 gegen sd 17,6 bei den gemalten Wolken); 0,35 laesst die
# Lappen wieder erkennen, ohne dass sie einzeln lesen.
const NORMALEN_MISCHUNG := 0.35
# Beulen: Tiefe als Anteil des Grundmasses s, Frequenz in Perioden je s.
# GEMESSEN NACHGEZOGEN: mit 0.085 waren die Beulen rund 3 Prozent des Lappenhalbmessers
# und im Bild aus 160 m nicht zu finden — die Wolke stand weiter als glatter Ballon da.
# 0.18 bleibt im Rahmen: der groesste Puff-Halbmesser lag gemessen bei 160,7 m gegen
# 207 m Reserve in Main.WOLKEN_AREA, die Beulen legen hoechstens 0.18 * 56 * 1,68 =
# 16,9 m drauf, macht 178 m.
const BEULEN_TIEFE := 0.18
const BEULEN_MASS := 2.4
# Wie frueh die Wolken auf gröbere LOD-Stufen umschalten. KLEINER = frueher = billiger;
# 1.0 waere wie alle andere Geometrie. Siehe Messreihe an der Zuweisung.
const PUFF_LOD_BIAS := 0.35

static func _nachbearbeiten(roh: ArrayMesh, s: float, basis_y: float) -> ArrayMesh:
	var arr := roh.surface_get_arrays(0)
	var ecken: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var mitte := Vector3(0.0, basis_y + 0.55 * s, 0.0)

	# --- BEULEN: die Kugeln entregelmaessigen ------------------------------------------
	# WARUM DAS HIER STEHT UND NICHT IM SHADER: die Oberflaechen-"Krume" des Shaders war
	# nachweislich wirkungslos — gemessen sd 1,2 bis 2,1 Luma auf einer Flaeche, deren
	# Gesamtspanne 90 Luma betraegt, und aus 70 m sogar EINSEITIG, weil die Schulter des
	# Tonemappers die helle Haelfte des Rauschens verschluckt. Sie konnte gar nicht
	# wirken: die Normalen werden weiter unten zur Wolkenmitte hin gedreht, und genau das
	# loescht jede Oberflaechenschattierung, die die Krume danach herstellen soll.
	# Echte Beulen loesen beides auf einmal und kosten KEIN einziges Dreieck:
	#   - Sie erzeugen Schattierung, die das Tonemapping nicht wegbuegeln kann, weil sie
	#     aus der Geometrie kommt und nicht aus einem Farbaufschlag.
	#   - Sie brechen die REGELMAESSIGKEIT der Silhouette. Ein Zwanzigeck liest sich als
	#     Vieleck, weil jede Ecke gleich gross ist und gleich weit von der naechsten
	#     entfernt; sitzt jede Ecke auf einem anderen Halbmesser, liest dieselbe Kantenzahl
	#     als unregelmaessige Kontur. Die Zahl der Ecken sinkt dadurch NICHT — wer sie
	#     zaehlt, findet weiter welche.
	# Wellenlaenge rund 0,3*s, also ungefaehr eine Kugelfacette breit: kuerzer waere unter
	# der Aufloesung des Gitters, laenger verschoebe nur ganze Lappen.
	for i in ecken.size():
		var p := ecken[i]
		var d := p - mitte
		var l := d.length()
		if l > 0.001:
			ecken[i] = p + (d / l) * _beule(p / s * BEULEN_MASS) * BEULEN_TIEFE * s
	arr[Mesh.ARRAY_VERTEX] = ecken
	# Normalen aus der VERFORMTEN Flaeche neu bilden. Ohne das beleuchtet der Shader
	# weiter die glatte Kugel und die Beulen waeren unsichtbar.
	var zwischen := ArrayMesh.new()
	zwischen.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st_n := SurfaceTool.new()
	st_n.create_from(zwischen, 0)
	st_n.generate_normals()
	arr = st_n.commit().surface_get_arrays(0)
	ecken = arr[Mesh.ARRAY_VERTEX]

	var norm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var farbe := PackedColorArray()
	farbe.resize(ecken.size())
	var halb := Vector3(1.6 * s, 1.0 * s, 1.6 * s)
	# Basis stauchen und dabei gleich die TATSAECHLICHE Hoehenspanne einsammeln. Sie
	# vorher zu schaetzen ging schief: geschaetzt 2,05*s, tatsaechlich 1,66*s — die
	# Wolkenbasis kam dadurch bei COLOR.r = 0,11 statt 0 an und blieb fast weiss.
	var y_lo := INF
	var y_hi := -INF
	for i in ecken.size():
		var p := ecken[i]
		if p.y < basis_y:
			p.y = basis_y - (basis_y - p.y) * 0.30
			ecken[i] = p
		y_lo = minf(y_lo, p.y)
		y_hi = maxf(y_hi, p.y)
	var spanne := maxf(y_hi - y_lo, 0.001)
	for i in ecken.size():
		var p := ecken[i]
		var g := ((p - mitte) / halb).normalized()
		if g.length_squared() > 0.5:
			norm[i] = norm[i].lerp(g, NORMALEN_MISCHUNG).normalized()
		# COLOR.r = 0 an der Basis, 1 an der Krone. Der Shader faerbt danach.
		farbe[i] = Color((p.y - y_lo) / spanne, 0.0, 0.0, 1.0)
	arr[Mesh.ARRAY_VERTEX] = ecken
	arr[Mesh.ARRAY_NORMAL] = norm
	arr[Mesh.ARRAY_COLOR] = farbe

	# --- LOD: vereinfachte Stufen fuer die Ferne ---------------------------------------
	# Ohne das zeichnet JEDE Wolke ihre vollen rund 1800 Dreiecke, auch wenn sie in 8 km
	# Entfernung 30 Bildpunkte gross ist. Bei ueber 7500 sichtbaren Kumulus ist das der
	# groesste einzelne Posten der Flugansicht.
	#
	# WARUM ImporterMesh UND NICHT ZWEI MESHES MIT visibility_range: eine selbstgebaute
	# Umschaltung poppt, weil zwei verschiedene Koerper hart getauscht werden — und die
	# Ausblendung ueber FADE_SELF wirkt auf diesem opaken Material nachweislich gar nicht
	# (Messung im Kopf dieser Datei). generate_lods() dagegen dezimiert dieselbe
	# Indexliste; Godot waehlt die Stufe nach dem Fehler in BILDPUNKTEN und wechselt
	# dadurch dort, wo man es nicht sieht. Es kostet nur Bauzeit, keine Laufzeit.
	#
	# 25 Grad Verschmelzungswinkel: darunter darf der Vereinfacher Ecken zusammenlegen.
	# Die Wolke ist eine weiche Form ohne Kanten, die erhalten werden muessten — genau
	# der Fall, fuer den ein grosszuegiger Winkel gedacht ist.
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, null, "", 0)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


# ---------------------------------------------------------------------------------------
# DER SHADER STEHT ABSICHTLICH HIER ALS TEXT und nicht in shaders/: in dieser Runde darf
# nur diese eine Datei geaendert werden. Vorbild ist FlakGun.gd, das es genauso macht.
const PUFF_SHADER := """
shader_type spatial;
// EMPFAENGT KEINE SCHATTEN. Werfen tut die Wolke weiter — das haengt am MeshInstance
// (Main.gd schaltet cast_shadow ON), nicht am Material. Warum sie keine mehr empfaengt:
// die Schattenparameter der Sonne sind auf das 8-m-Raster des Low-Poly-Gelaendes
// eingestellt (bias 0.09, normal_bias 1.6, blur 1.1). Auf einer 100-m-Kugel ergeben sie
// unregelmaessige dunkelblaue Flecken mit harten Raendern — das sind die Flecken auf dem
// grossen Puff in /tmp/puffref/vor_zenit.png, und sie sind der Hauptgrund, warum er wie
// ein Felsbrocken liest. specular_disabled: eine Wolke hat kein Glanzlicht.
render_mode cull_back, specular_disabled, shadows_disabled;

uniform vec3 farbe_krone : source_color = vec3(0.88, 0.89, 0.92);
uniform vec3 farbe_basis : source_color = vec3(0.50, 0.57, 0.71);
uniform float streuung = 0.60;      // Wrap-Weite: wie weit das Licht um die Wolke laeuft
uniform float sockel = 0.16;        // Restlicht auf der sonnenabgewandten Seite
uniform float silber = 0.40;        // Vorwaertsstreuung (Silberrand gegen die Sonne)
// HELLIGKEIT IST KEIN GESCHMACKSWERT. Wrap-Licht hebt jede Flaeche an, die nicht genau
// zur Sonne zeigt: eine waagerechte Wolkenkrone hat bei 50 Grad Sonnenhoehe dot = 0,766
// und bekam mit Lambert genau 0,766, mit Wrap aber 0,96. Zusammen mit dem Wegfall der
// empfangenen Schatten stand die Decke dadurch 30 bis 36 Luma zu hell (gemessen in
// ueber_decke und hoch gegen die abgenommenen gemalten Wolken). Der Faktor holt das
// zurueck, ohne die weiche Kante wieder zu verlieren.
uniform float helligkeit = 0.52;
// NAHBEREICH: dieselbe Spanne wie der alte Dither (8 bis 40 m) plus ein knapper
// Zuschlag. Sie war zwischendurch auf 14 bis 65 m gestellt — damit verschwand in der
// Ansicht "zenit" die grosse nahe Wolke KOMPLETT aus dem Bild (a1_zenit.png und
// a3_zenit.png waren bitgleich, obwohl der Shader dazwischen dreimal geaendert wurde).
// Das haette die Nahaufnahme aus der Pruefung herausdefiniert statt sie zu verbessern.
uniform float nah_weg = 10.0;       // hier ist die Wolke ganz verschwunden
uniform float nah_voll = 48.0;      // ab hier steht sie in voller Groesse
uniform float krume = 0.22;         // Staerke der Oberflaechen-Krume
uniform float krume_mass = 0.07;    // Grundfrequenz der Krume (1/Meter im Objektraum)
uniform float krume_fern = 2600.0;  // ab hier ist die Krume ausgeblendet (m)

varying float krone;
varying vec3 lokal;                 // Ort im Objektraum, fuer die Krume
varying float nah;                  // 1 = Krume voll, 0 = zu weit weg

// Wert-Rauschen. Es sitzt im OBJEKTRAUM, damit die Krume auf der Wolke klebt und nicht
// durch sie hindurchschwimmt, wenn die Wolke umschlaegt oder sich der Blick dreht.
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float wrausch(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i + vec3(0, 0, 0)), hash13(i + vec3(1, 0, 0)), f.x);
	float b = mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x);
	float c = mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x);
	float d = mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

void vertex() {
	krone = COLOR.r;
	lokal = VERTEX;
	nah = 1.0 - smoothstep(krume_fern * 0.45, krume_fern, length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
	// DURCHFLIEGEN OHNE PUNKTRASTER. Vorher machte das der Dither von
	// DISTANCE_FADE_PIXEL_DITHER, und weil die Wolke dabei das halbe Bild fuellt, war das
	// ein grob sichtbares Punktraster (vor_zenit.png, rechte Bildhaelfte). Stattdessen
	// schrumpft die Wolke jetzt zu ihrem eigenen Ursprung zusammen. Das ist deckend,
	// braucht keine Sortierung und hat keine Struktur, die auffallen koennte.
	// NUR IM KAMERAPASS: im Schattenpass ist die "Kamera" die Sonne, dort wuerde derselbe
	// Abstand die falschen Wolken schrumpfen lassen und Schatten ausloeschen. Der
	// Schattenwurf der Sonne ist orthografisch, die Spielkamera perspektivisch — genau
	// daran laesst sich der Pass unterscheiden.
	if (PROJECTION_MATRIX[3][3] < 0.5) {
		VERTEX *= smoothstep(nah_weg, nah_voll, distance(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD));
	}
}

void fragment() {
	// Basis kuehler und dunkler als die Krone. In einer echten Quellwolke kommt an der
	// Unterseite nur noch mehrfach gestreutes Himmelslicht an — das ist blau, nicht grau.
	vec3 c = mix(farbe_basis, farbe_krone, smoothstep(0.0, 0.55, krone));
	// KRUME. Aus der Naehe fuellt eine Wolke das halbe Bild (siehe unter_decke und
	// land_gegen), und dort war sie nach der Normalen-Mischung eine voellig strukturlose
	// weisse Kuppel — eine andere Art, falsch auszusehen als der Felsbrocken vorher.
	// Struktur ueber GEOMETRIE zu holen ist in einem Low-Poly-Spiel der falsche Hebel: das
	// kostet Dreiecke ueberall, auch dort, wo die Wolke 20 Pixel gross ist. Zwei Oktaven
	// Wert-Rauschen kosten nur dort, wo die Wolke wirklich Flaeche hat, und sind ab
	// krume_fern ganz abgeschaltet (sonst flimmern die fernen Wolken).
	// SIE SITZT HIER UND NICHT IN light(): light() laeuft je Lichtquelle, und im Flug
	// stehen zwei gerichtete Lichter (Sonne und Fuelllicht) — das Rauschen waere sonst
	// doppelt gerechnet. Auf dem ALBEDO wirkt es ausserdem auch auf das Himmelslicht,
	// was richtiger ist: es ist eine Dichteschwankung, keine Eigenschaft der Sonne.
	if (nah > 0.0) {
		vec3 q = lokal * krume_mass;
		float k = wrausch(q) * 0.65 + wrausch(q * 2.7) * 0.35;
		c *= 1.0 + krume * nah * (k - 0.5) * 2.0;
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}

void light() {
	// WRAP-BELEUCHTUNG statt Lambert. Lambert setzt die Terminatorkante bei 90 Grad und
	// laesst alles dahinter auf 0 fallen — deshalb liefen die Puffs auf der
	// sonnenabgewandten Seite ins Dunkelgrau-Blaue und wirkten wie Steine. In einer
	// Kumuluswolke wird das Licht so oft gestreut, dass auch die Rueckseite noch leuchtet.
	// (streuung + 1) verschiebt die Kante nach hinten, smoothstep nimmt ihr die Haerte,
	// der Sockel setzt einen Boden, unter den nichts faellt.
	float w = clamp((dot(normalize(NORMAL), normalize(LIGHT)) + streuung) / (1.0 + streuung), 0.0, 1.0);
	w = w * w * (3.0 - 2.0 * w);
	w = mix(sockel, 1.0, w);
	// Vorwaertsstreuung: schaut man gegen die Sonne, leuchtet die Wolke auf.
	float vorwaerts = pow(clamp(dot(normalize(LIGHT), -normalize(VIEW)), 0.0, 1.0), 5.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (w + silber * vorwaerts) * helligkeit;
}
"""


static func _cloud_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = PUFF_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	return m
