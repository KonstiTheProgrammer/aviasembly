## WIEVIEL HELLIGKEITSUNTERSCHIED STEHT ZWISCHEN BENACHBARTEN FACETTEN?
##
## WARUM ES DIESES WERKZEUG GIBT. Neun Abnahmerunden haben "glatte Flanke" gemeldet, und
## dreimal wurde daraufhin mehr Gelaende eingebaut. Am Bild gemessen half das nicht. Eine
## SCHWARZPROBE (alle Gesteinsfarben des Kegels auf null, ein Renderlauf) hat den Grund
## gezeigt: bei 3,5 km Kameraabstand misst der Kegel dann immer noch 0.254 mittlere
## Leuchtdichte, und seine lokale Streuung faellt auf 0.0019. Der Nebelsockel ist also
## additiv und die Form allein erzeugt UEBERHAUPT KEINEN Kontrast — sichtbar wird
## Schattierung nur dort, wo auch Albedo steht.
##
## Ein Renderlauf dauert rund 100 s, das Werkzeug hier zehn. Es tastet dieselbe Flanke ab,
## die die Abnahmekamera sieht, baut die Dreiecke GENAU wie _chunk_mesh (8 m, Diagonale
## v00-v11), holt fuer jedes die echte Hautfarbe aus _face_color und rechnet dieselbe
## Beleuchtung wie die Szene. Zwei Zahlen kommen heraus:
##
##   MITTEL       mittlere Flaechenleuchtdichte. Sie landet im Bild als Sockel + k * Mittel.
##   STREUUNG55   Streuung in einem 55-m-Fenster (7x7 Zellen). 55 m sind bei 6,07 m je
##                Bildpunkt genau das 9x9-Fenster, das vk/kontrast.py am Bild auswertet.
##
## DER QUOTIENT AUS BEIDEN IST DIE ZAHL, AUF DIE ES ANKOMMT. Weil der Nebelsockel additiv
## ist, gilt im Bild naeherungsweise
##       Bildmittel   = 0.254 + k * Mittel
##       Bildstreuung = k * Streuung55
## und daraus folgt: nur wer die Streuung SCHNELLER hebt als das Mittel, macht den Kegel
## kontrastreicher, ohne ihn zugleich aufzuhellen. Der Stand vor dieser Runde lag bei
## Quotient 0.42; fuer Bildstreuung 0.030 bei Bildmittel unter 0.30 braucht es rund 0.8.
##
## Godot --headless --path . --script res://tools/_vulkan_fein.gd
extends SceneTree

const SCHRITT := 8.0        # Netzweite des Gelaendes
# DAS FELD MUSS DENSELBEN AUSSCHNITT ABDECKEN WIE DER MESSKASTEN, und das ist teuer erkauft:
# der erste Anlauf tastete ein 768-m-Quadrat auf der Oberflanke ab und sagte fuer den
# fertigen Renderlauf 0.284 Bildmittel voraus, gemessen wurden 0.303. Der Grund war nicht
# das Modell, sondern der ORT — seit der Kegelfuss von 3000 auf 1958 m Radius zusammengezogen
# ist, sieht der Kasten der Abnahme nicht mehr nur die Oberflanke, sondern die halbe
# Schuerze dazu, und die ist glatter und heller. Wer auf der Oberflanke misst und ueber den
# Kasten redet, misst am Motiv vorbei.
const N := 224              # 224 * 8 m = 1792 m Kantenlaenge — Lippe bis Schuerzensaum
const FENSTER := 7          # 7 Zellen = 56 m ~ das 9x9-Fenster von kontrast.py
const BAND_AB := 1.02       # Innenrand des Bandes, in Kraterradien
const BAND_ZU := 1.30       # Aussenrand, in Fussradien (die Schuerze zaehlt mit)

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var vk: Dictionary = {}
	for ms in tw.massifs:
		if String(ms.get("type", "")) == "vulkan":
			vk = ms
			break
	if vk.is_empty():
		print("KEIN VULKAN")
		quit()
		return true
	var p: Vector3 = vk["pos"]
	var mr := float(vk["r"])
	var peak := float(vk["peak"])

	# LICHT WIE IN DER SZENE (Main._setup_sky_and_light). Die Sonne zeigt in +z ihrer
	# eigenen Basis, das Fuelllicht ebenso; beide ohne Schatten — und das ist hier nicht
	# geschlampt, sondern richtig: die Schattenkaskade der Sonne reicht 3000 m weit
	# (Main: directional_shadow_max_distance), der Kegel steht im Abnahmebild aber 3300 bis
	# 4000 m vor der Kamera. Auf DIESEM Bild gibt es also gar keinen Schlagschatten, nur
	# Lambert — und genau deshalb muss die Facette selbst hell oder dunkel sein.
	var sonne := Basis.from_euler(Vector3(deg_to_rad(-50.0), deg_to_rad(-50.0), 0.0)).z
	var fuell := Basis.from_euler(Vector3(deg_to_rad(58.0), deg_to_rad(130.0), 0.0)).z

	# DAS ABGETASTETE FELD LIEGT DORT, WO DER MESSKASTEN VON kontrast.py STEHT: auf der der
	# Kamera zugewandten Seite (die Abnahmekamera steht bei +z), von der Lippe bis in die
	# Schuerze hinaus.
	var cr := float(vk.get("crater_r", mr * 0.16))
	var mitte := Vector3(p.x, 0.0, p.z + mr * 0.62)
	var werte := PackedFloat32Array()
	werte.resize(N * N)
	var gueltig := PackedByteArray()
	gueltig.resize(N * N)
	var toene := PackedFloat32Array()
	toene.resize(N * N)
	# AUFWAERTSANTEIL DER FLAECHENNORMALE je Zelle — die Groesse, mit der die Haut das
	# Anstehende von der Aschelage trennt. Nur zur Diagnose: ohne ihre Verteilung laesst sich
	# nicht sagen, ob eine Schwelle darauf die halbe Flanke trifft oder ein Prozent.
	var nys := PackedFloat32Array()
	nys.resize(N * N)

	for j in N:
		for i in N:
			var x := mitte.x + (float(i) - N * 0.5) * SCHRITT
			var z := mitte.z + (float(j) - N * 0.5) * SCHRITT
			var h00 := tw.height_at(x, z)
			var h10 := tw.height_at(x + SCHRITT, z)
			var h01 := tw.height_at(x, z + SCHRITT)
			var h11 := tw.height_at(x + SCHRITT, z + SCHRITT)
			var v00 := Vector3(x, h00, z)
			var v10 := Vector3(x + SCHRITT, h10, z)
			var v01 := Vector3(x, h01, z + SCHRITT)
			var v11 := Vector3(x + SCHRITT, h11, z + SCHRITT)
			var s := 0.0
			var a := 0.0
			var nyz := 0.0
			for tri in [[v00, v10, v11], [v00, v11, v01]]:
				var va: Vector3 = tri[0]
				var vb: Vector3 = tri[1]
				var vc: Vector3 = tri[2]
				var n := (vb - va).cross(vc - va).normalized()
				if n.y < 0.0:
					n = -n
				var cen := (va + vb + vc) / 3.0
				nyz += absf(n.y) * 0.5
				var col := tw._face_color(cen, absf(n.y))
				# GLUT AUSSERHALB DER MESSUNG: kontrast.py maskiert die Lava weg (rot und
				# hell), sonst zoege sie den Mittelwert nach oben und die Streuung erst recht.
				if col.a < 0.999:
					continue
				var lin := Vector3(_lin(col.r), _lin(col.g), _lin(col.b))
				var alb := 0.2126 * lin.x + 0.7152 * lin.y + 0.0722 * lin.z
				var licht := 1.30 * maxf(n.dot(sonne), 0.0) \
					+ 0.24 * maxf(n.dot(fuell), 0.0) \
					+ 0.85 * (0.55 + 0.45 * n.y)
				s += alb * licht
				a += alb
			var idx := j * N + i
			var dm := Vector2(x - p.x, z - p.z).length()
			# Kamera-zugewandte Seite, Lippe bis Schuerzensaum. Der Halbraum z > Achse ist
			# genau die Haelfte, die das Abnahmebild zeigt — die abgewandte steht im
			# Gegenlicht und kommt im Kasten gar nicht vor.
			if dm > cr * BAND_AB and dm < mr * BAND_ZU and z > p.z:
				gueltig[idx] = 1
			werte[idx] = s * 0.5
			toene[idx] = a * 0.5
			nys[idx] = nyz

	# --- MITTEL UND FENSTERSTREUUNG ------------------------------------------------------
	var sum := 0.0
	var cnt := 0
	for k in N * N:
		if gueltig[k] == 1:
			sum += werte[k]
			cnt += 1
	if cnt < 200:
		print("ZU WENIG FLANKE IM FELD (%d Zellen) — Mitte/Hoehenband pruefen" % cnt)
		quit()
		return true
	var mittel := sum / float(cnt)

	var sdsum := 0.0
	var sdn := 0
	var r := FENSTER / 2
	for j in range(r, N - r):
		for i in range(r, N - r):
			var ok := true
			var s1 := 0.0
			var s2 := 0.0
			for dj in range(-r, r + 1):
				for di in range(-r, r + 1):
					var idx := (j + dj) * N + (i + di)
					if gueltig[idx] == 0:
						ok = false
						break
					s1 += werte[idx]
					s2 += werte[idx] * werte[idx]
				if not ok:
					break
			if not ok:
				continue
			var m := float(FENSTER * FENSTER)
			sdsum += sqrt(maxf(s2 / m - (s1 / m) * (s1 / m), 0.0))
			sdn += 1
	var streu := 0.0 if sdn == 0 else sdsum / float(sdn)

	print("=== FEINRELIEF UND HELLIGKEITSSTREUUNG DER FLANKE ===")
	print("Zellen im Band: %d, Fenster: %d" % [cnt, sdn])
	print("MITTEL      %.5f" % mittel)
	print("STREUUNG55  %.5f" % streu)
	print("QUOTIENT    %.3f   (Stand vor dieser Runde 0.42, gebraucht rund 0.8)" % (streu / maxf(mittel, 1e-6)))
	print("VORHERSAGE  Bildmittel %.3f   Bildstreuung %.4f   (Ziel 0.17-0.22 / >= 0.030)"
		% [_bild(mittel), _bildstreu(mittel, streu)])

	# --- DER NACHBARSPRUNG: DIE ZAHL, AUF DIE ES WIRKLICH ANKOMMT ------------------------
	# WARUM ES IHN BRAUCHT, OBWOHL DIE FENSTERSTREUUNG SCHON DASTEHT. Der erste Renderlauf
	# dieser Runde hat die Vorhersage im Mittel getroffen (0.316 gegen 0.303) und in der
	# Streuung um das Vierfache verfehlt (0.038 gegen 0.0099). Am Bild nachgemessen liegt der
	# Grund in der WELLENLAENGE, nicht in der Amplitude: misst man die Streuung ueber
	# verschieden grosse Fenster, waechst sie bei der Vorlage von 0.031 (3x3) auf 0.058
	# (33x33), bei uns nur von 0.008 auf 0.011. Die Vorlage hat ihren Kontrast also schon
	# ZWISCHEN BENACHBARTEN BILDPUNKTEN — und ein Bildpunkt ist bei 5 bis 6 m Aufloesung
	# ungefaehr eine Gelaendezelle. Uns fehlt nicht die grosse Amplitude, uns fehlt der
	# Sprung von Facette zu Facette; eine Fensterstreuung, die aus wenigen sehr hellen
	# Flecken kommt, sieht in der Zahl gut aus und im Bild nach glatt.
	# Gemessen wird deshalb der mittlere Betrag der Differenz zu den beiden Nachbarn.
	var spr := 0.0
	var sprn := 0
	for j in range(1, N - 1):
		for i in range(1, N - 1):
			var idx := j * N + i
			if gueltig[idx] == 0 or gueltig[idx + 1] == 0 or gueltig[idx + N] == 0:
				continue
			spr += absf(werte[idx] - werte[idx + 1]) + absf(werte[idx] - werte[idx + N])
			sprn += 2
	var sprung := 0.0 if sprn == 0 else spr / float(sprn)
	print("NACHBARSPRUNG  Flaeche %.5f  ->  im Bild rund %.4f   (Vorlage 0.031, wir zuletzt 0.008)"
		% [sprung, _bildstreu(mittel, sprung) - 0.0019])

	# --- DIE VORHERSAGE IM BILDRAUM, UND WARUM SIE DIE ALTE ABLOEST ----------------------
	# Die Zeilen darueber rechnen die Flaechenstreuung mit der STEIGUNG der Kennlinie ins
	# Bild um. Das ist eine Linearisierung, und die Kennlinie ist stark KONKAV: eine Facette,
	# die zehnmal so hell ist wie ihre Nachbarin, steht im Bild nur rund doppelt so hell da.
	# Gemessen hat die alte Umrechnung deshalb um den Faktor 2,4 zu viel versprochen
	# (0.0563 vorhergesagt, 0.0238 gerendert). Hier wird stattdessen JEDE Zelle EINZELN durch
	# die Kennlinie geschickt und erst danach die Streuung gebildet — dieselbe Reihenfolge
	# wie im Renderer, und damit faellt der Fehler weg.
	# DER MASSSTAB (BILD_K) HAENGT NICHT AN DER KENNLINIE, sondern an der Kamera: eine
	# Gelaendezelle ist im Abnahmebild rund einen Bildpunkt gross, durch die Verkuerzung der
	# geneigten Flanke eher weniger, und was in einen Bildpunkt faellt, wird gemittelt.
	# Er ist an EINEM gerenderten Stand geeicht (Bild 0.318 / 0.0238) und dient nur dazu,
	# zwei Staende ohne Renderlauf zu vergleichen.
	var bild := PackedFloat32Array()
	bild.resize(N * N)
	for k in N * N:
		bild[k] = _bild(werte[k])
	var bm := 0.0
	for k in N * N:
		if gueltig[k] == 1:
			bm += bild[k]
	bm /= float(cnt)
	print("BILDMITTEL (je Zelle durch die Kennlinie)  %.4f" % bm)
	print("BILDSTREUUNG  3x3 %.4f   7x7 %.4f   17x17 %.4f   global %.4f"
		% [_fstreu(bild, gueltig, 1), _fstreu(bild, gueltig, 3), _fstreu(bild, gueltig, 8),
			_global(bild, gueltig, bm, cnt)])
	print("ROH * %.2f  ->  7x7 %.4f   (Ziel >= 0.030)"
		% [BILD_K, BILD_K * _fstreu(bild, gueltig, 3)])
	var bsrt := PackedFloat32Array()
	for k in N * N:
		if gueltig[k] == 1:
			bsrt.append(bild[k])
	bsrt.sort()
	print("BILDWERTE p05 %.3f  p25 %.3f  Median %.3f  p75 %.3f  p95 %.3f  p99 %.3f"
		% [_pz(bsrt, 0.05), _pz(bsrt, 0.25), _pz(bsrt, 0.50), _pz(bsrt, 0.75),
			_pz(bsrt, 0.95), _pz(bsrt, 0.99)])

	# --- WIE DIE ALBEDO GESTAFFELT IST ---------------------------------------------------
	# Die zweite Haelfte der Antwort: eine Flanke, die ueberall denselben Ton traegt, kann
	# keine Nachbarfacetten verschieden hell machen, egal wie zerklueftet sie ist.
	var srt := PackedFloat32Array()
	for k in N * N:
		if gueltig[k] == 1:
			srt.append(toene[k])
	srt.sort()
	print("ALBEDO (linear) p05 %.4f  p25 %.4f  Median %.4f  p75 %.4f  p95 %.4f  p99 %.4f"
		% [_pz(srt, 0.05), _pz(srt, 0.25), _pz(srt, 0.50), _pz(srt, 0.75),
			_pz(srt, 0.95), _pz(srt, 0.99)])

	# --- WIE STARK DIE FACETTEN GEGENEINANDER KIPPEN -------------------------------------
	# Die Gegenprobe zur Farbe: kippen die Nachbardreiecke ueberhaupt? Gemessen wird der
	# Winkel zwischen der Zellnormalen und der ihrer vier Nachbarn.
	var kipp := 0.0
	var kippn := 0
	for j in range(1, N - 1):
		for i in range(1, N - 1):
			var idx := j * N + i
			if gueltig[idx] == 0:
				continue
			var x := mitte.x + (float(i) - N * 0.5) * SCHRITT
			var z := mitte.z + (float(j) - N * 0.5) * SCHRITT
			var hx := tw.height_at(x + SCHRITT, z) - tw.height_at(x - SCHRITT, z)
			var hz := tw.height_at(x, z + SCHRITT) - tw.height_at(x, z - SCHRITT)
			kipp += rad_to_deg(atan2(sqrt(hx * hx + hz * hz), 2.0 * SCHRITT))
			kippn += 1
	var nsrt := PackedFloat32Array()
	for k in N * N:
		if gueltig[k] == 1:
			nsrt.append(nys[k])
	nsrt.sort()
	print("NY (Aufwaertsanteil) p05 %.3f  p25 %.3f  Median %.3f  p75 %.3f  p95 %.3f"
		% [_pz(nsrt, 0.05), _pz(nsrt, 0.25), _pz(nsrt, 0.50), _pz(nsrt, 0.75), _pz(nsrt, 0.95)])
	# WELLENLAENGE STATT AMPLITUDE: eine Groesse taugt nur dann als Treiber der Hautfarbe,
	# wenn sie sich schon zwischen NACHBARN aendert. Steht die 3x3-Streuung nahe an der
	# globalen, ist sie das; liegt sie weit darunter, sitzt ihre Amplitude in langen Wellen
	# und ein 55-m-Fenster sieht davon nichts.
	var nym := 0.0
	for k in N * N:
		if gueltig[k] == 1:
			nym += nys[k]
	nym /= float(cnt)
	print("NY-STREUUNG 3x3 %.4f  7x7 %.4f  global %.4f   (nah beieinander = taugt als Treiber)"
		% [_fstreu(nys, gueltig, 1), _fstreu(nys, gueltig, 3), _global(nys, gueltig, nym, cnt)])
	print("MITTLERE ZELLNEIGUNG  %.1f Grad" % (kipp / maxf(float(kippn), 1.0)))
	quit()
	return true


# --- VON DER FLAECHENHELLIGKEIT AUF DEN BILDWERT ------------------------------------------
# ZWEI RENDERLAEUFE HABEN DIESE KURVE FESTGELEGT, sie ist nicht geraten:
#   Schwarzprobe (alle Gesteinsfarben null)   Flaeche 0      -> Bild 0.254
#   Stand vor dieser Runde                    Flaeche 0.0102 -> Bild 0.283
# Daraus die zwei Zahlen unten. Der Sockel ist der NEBEL: er liegt additiv unter der Flanke
# und skaliert nicht mit dem Albedo. Die Wurzel ist die sRGB-Kennlinie des Bildes.
# GEGENPROBE, die die Kurve erst glaubwuerdig macht: mit denselben zwei Zahlen sagt sie fuer
# den Stand vor dieser Runde eine Bildstreuung von 0.0132 voraus; gemessen wurden 0.0141
# abzueglich der 0.0019, die schon die Schwarzprobe zeigt, also 0.0122. Acht Prozent daneben.
const SOCKEL := 0.05066     # 0.254 hoch 2.2 — der Nebel bei 3,5 km Kameraabstand
const HANG := 1.2441        # Durchlass der Atmosphaere mal Belichtung


func _bild(s: float) -> float:
	return pow(HANG * s + SOCKEL, 1.0 / 2.2)


func _bildstreu(s: float, sd: float) -> float:
	# Steigung der Kennlinie an der Stelle s, mal der Flaechenstreuung. Die 0.0019 sind das,
	# was die Schwarzprobe an Restunruhe zeigt (Renderrauschen, Kanten im Ausschnitt).
	var v := _bild(s)
	return 0.0019 + (HANG / 2.2) * pow(v, -1.2) * sd


# BILDPUNKT GEGEN GELAENDEZELLE. Eine 8-m-Zelle ist im Abnahmebild rund einen Bildpunkt
# gross, durch die Verkuerzung der geneigten Flanke eher weniger — was in einen Bildpunkt
# faellt, wird gemittelt, und das nimmt Streuung weg. Der Faktor ist an EINEM gerenderten
# Stand geeicht und ueber die Fenstergroessen hinweg stabil:
#   Werkzeug 3x3 0.0319 / 7x7 0.0445   gerendert 3x3 0.0184 / 9x9 0.0238
# also 0.577 und 0.535. Die Bildmittel stimmen dabei ohne jede Eichung (0.3216 gegen 0.318).
const BILD_K := 0.55
# ACHTUNG, UND ZWAR EINE TEURE: DIESER FAKTOR GILT NUR INNERHALB EINES FARBSCHEMAS.
# vk/kontrast.py wirft jeden Bildpunkt weg, der "himmel" ist (b > r + 0.05 und Leuchtdichte
# ueber 0.42), und verlangt, dass ein 9x9-Fenster VOLLSTAENDIG auf Fels liegt. Das
# Umgebungslicht dieser Welt kommt vom Himmel und ist blau — ein heller, sonnenabgewandter
# Fels faellt damit in genau diese Bedingung. Gemessen an drei Renderlaeufen mit demselben
# Relief und nur anderem Gesteinston: gueltige Fenster 42, 30, 18 Prozent, und die
# ausgewiesene Streuung sank auf 0.0286, obwohl die Streuung um die Fenstermitte von 0.048
# auf 0.075 gestiegen war. Ein waermerer Anstehendton (r ueber b) hat die gueltigen Fenster
# auf 45 Prozent zurueckgeholt und die ausgewiesene Streuung von 0.0286 auf 0.0662 gehoben —
# ohne dass sich an der Form oder an der Helligkeit etwas geaendert haette.
# WER ALSO DIE GESTEINSFARBE ANFASST, DARF DIESEM WERKZEUG NICHT GLAUBEN, sondern muss
# rendern. Fuer reine Schwellen- und Amplitudenaenderungen innerhalb eines Tons ist es
# weiter brauchbar, und das Bildmittel sagt es ohnehin auf etwa 0.01 genau voraus.


## Mittlere Fensterstreuung im Bildraum, Radius r in Zellen (r=3 ist das 7x7-Fenster).
func _fstreu(bild: PackedFloat32Array, gueltig: PackedByteArray, r: int) -> float:
	var sdsum := 0.0
	var sdn := 0
	for j in range(r, N - r):
		for i in range(r, N - r):
			var ok := true
			var s1 := 0.0
			var s2 := 0.0
			for dj in range(-r, r + 1):
				for di in range(-r, r + 1):
					var idx := (j + dj) * N + (i + di)
					if gueltig[idx] == 0:
						ok = false
						break
					s1 += bild[idx]
					s2 += bild[idx] * bild[idx]
				if not ok:
					break
			if not ok:
				continue
			var m := float((2 * r + 1) * (2 * r + 1))
			sdsum += sqrt(maxf(s2 / m - (s1 / m) * (s1 / m), 0.0))
			sdn += 1
	return 0.0 if sdn == 0 else sdsum / float(sdn)


func _global(bild: PackedFloat32Array, gueltig: PackedByteArray, m: float, cnt: int) -> float:
	var s := 0.0
	for k in N * N:
		if gueltig[k] == 1:
			s += (bild[k] - m) * (bild[k] - m)
	return sqrt(s / float(cnt))


func _lin(c: float) -> float:
	# Derselbe sRGB->linear-Schritt wie im Gelaendeshader (TerrainWorld, _mat).
	return c / 12.92 if c < 0.04045 else pow((c + 0.055) / 1.055, 2.4)


func _pz(a: PackedFloat32Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	return a[clampi(int(float(a.size() - 1) * q), 0, a.size() - 1)]
