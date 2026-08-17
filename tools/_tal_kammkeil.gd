## MISST DEN KEIL NICHT AM BODEN, SONDERN AN DER SILHOUETTE.
##
## WARUM ES DIESES WERKZEUG BRAUCHT. tools/_tal_keil.gd und tools/_krit_keil.gd messen den
## Talboden (Gelaende unter 200 m). Der kann sich sauber verjuengen, waehrend die KAMMLINIE
## — die Linie, die man aus dem Cockpit gegen den Himmel sieht — parallel bleibt oder sich
## sogar oeffnet. Genau das war der Zustand vor dieser Fassung: Boden 1.62 : 1, aber die
## 800-m-Hoehenlinie am Talschluss BREITER als in der Mitte.
##
## DIE URSACHE, DIE MAN HIER SIEHT: bei geradem Kegel (schaerfe ~ 1) liegt die Hoehenlinie h
## bei r * (1 - h / peak) vom Massivmittelpunkt. Die Querlage der Hoehenlinie haengt also
## nicht nur an der Sollinie _tal_halbbreite, sondern GENAUSO STARK an der Gipfelhoehe des
## Massivs. 2200 m Radius mal der Differenz zwischen 850 und 1250 m Gipfel sind 663 m
## Schwankung — mehr, als der ganze Keil (370 m Sollinie) ausmacht. Eine Gipfelliste, die
## nach hinten ABFAELLT, dreht den Keil oben also um.
##
## Godot --headless --path . --script res://tools/_tal_kammkeil.gd
extends SceneTree
var f := 0

const RASTER := 25.0        # Querschrittweite
const WEIT := 4200.0        # wie weit quer gesucht wird
const SCHRITT := 250.0      # Laengsschrittweite

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var quer := Vector2(-dir.y, dir.x)

	print("=== HOEHENLINIEN QUER (Halbbreite je Seite, Raster %d m) ===" % int(RASTER))
	print("laengs | Soll |  H200 l/r  |  H400 l/r  |  H600 l/r  | Kamm links      Kamm rechts")
	var reihe: Array = []
	for i in range(0, 39):
		var lg := float(i) * SCHRITT
		var p := start + dir * lg
		var soll: float = main._tal_halbbreite(lg)
		var h200 := _kontur(tw, p, quer, 200.0)
		var h400 := _kontur(tw, p, quer, 400.0)
		var h600 := _kontur(tw, p, quer, 600.0)
		var kl := _kamm(tw, p, quer, 1.0, soll)
		var kr := _kamm(tw, p, quer, -1.0, soll)
		reihe.append({"lg": lg, "h200": h200, "h400": h400, "h600": h600,
			"kl": kl, "kr": kr, "soll": soll})
		print("%6.0f | %4.0f | %4.0f/%4.0f | %4.0f/%4.0f | %4.0f/%4.0f | %4.0f m @%4.0f  %4.0f m @%4.0f"
			% [lg, soll, h200.x, h200.y, h400.x, h400.y, h600.x, h600.y,
				kl.y, kl.x, kr.y, kr.x])

	print("\n=== KEILMASS je Hoehenlinie (Summe beider Seiten) ===")
	# WARUM 600 UND NICHT 800 M die oberste gemessene Linie ist: am Talmund stehen die
	# Ketten bewusst niedrig, dort gibt es GAR KEINE 800-m-Linie. Die Suche laeuft dann
	# bis zum Anschlag WEIT (4200 m) und der Mittelwert vorn wird vom Anschlag bestimmt
	# statt vom Gelaende — ein Keilmass, das umso besser aussieht, je weniger Berg da ist.
	# Deshalb steht hier zusaetzlich, wie viele Proben ueberhaupt getroffen haben.
	for schl: String in ["h200", "h400", "h600"]:
		var vorn := _mittel(reihe, schl, 500.0, 2500.0)
		var mitte := _mittel(reihe, schl, 3500.0, 5500.0)
		var hinten := _mittel(reihe, schl, 6500.0, 8500.0)
		print("  %s: vorn %5.0f  mitte %5.0f  hinten %5.0f  -> %.2f : 1   (%d Anschlaege)"
			% [schl.to_upper(), vorn, mitte, hinten, vorn / maxf(hinten, 1.0),
				_anschlaege(reihe, schl)])

	# Monotonie der 600-m-Linie: wie viel Aufweitung sammelt sich auf dem Weg nach innen?
	var auf := 0.0
	var stellen := 0
	for i in range(1, reihe.size()):
		if float(reihe[i]["lg"]) > 9000.0:
			break
		var a: Vector2 = reihe[i]["h600"]
		var b: Vector2 = reihe[i - 1]["h600"]
		var d := (a.x + a.y) - (b.x + b.y)
		if d > 0.0:
			auf += d
			stellen += 1
	print("  H600 Aufweitungen bis 9000 m: %.0f m an %d Stellen" % [auf, stellen])

	# LAENGS 3250..4000 BLEIBT DRAUSSEN: dort steht die Felsrippe des Tors quer im Tal,
	# ihr Fuss ist die groesste Einzelunstetigkeit der ganzen Reihe (Boden 700 -> 300 ->
	# 625 m). Sie gehoert zum Tor, nicht zur Kette, und wuerde die Streuung allein tragen.
	print("\n=== KAMM GEGEN SOLLINIE (Schwebung, ohne Rippenfuss 3250..4000) ===")
	var mn := 1e9
	var mx := -1e9
	var betrag := 0.0
	var n := 0
	for e in reihe:
		if float(e["lg"]) > 9250.0:
			break
		if float(e["lg"]) >= 3250.0 and float(e["lg"]) <= 4000.0:
			continue
		for s: String in ["kl", "kr"]:
			var k: Vector2 = e[s]
			var abw: float = k.x - float(e["soll"])
			mn = minf(mn, abw)
			mx = maxf(mx, abw)
			betrag += absf(abw)
			n += 1
	print("  %.0f .. %+.0f m, Spanne %.0f m, mittlerer Betrag %.0f m"
		% [mn, mx, mx - mn, betrag / maxf(float(n), 1.0)])

	print("\n=== KAMMHOEHE laengs (steigt sie zum Talschluss?) ===")
	var kh_vorn := 0.0
	var kh_hint := 0.0
	var n1 := 0
	var n2 := 0
	for e in reihe:
		var g: float = maxf(float(e["kl"].y), float(e["kr"].y))
		if float(e["lg"]) >= 500.0 and float(e["lg"]) <= 2500.0:
			kh_vorn += g
			n1 += 1
		if float(e["lg"]) >= 7000.0 and float(e["lg"]) <= 9250.0:
			kh_hint += g
			n2 += 1
	print("  hoechster Kamm vorn 500..2500: %.0f m   hinten 7000..9250: %.0f m"
		% [kh_vorn / maxf(float(n1), 1.0), kh_hint / maxf(float(n2), 1.0)])
	quit()
	return true

## Querentfernung je Seite, ab der das Gelaende die Hoehe zum ersten Mal erreicht.
## x = linke Seite (+quer), y = rechte Seite (-quer).
func _kontur(tw: TerrainWorld, p: Vector2, quer: Vector2, hoehe: float) -> Vector2:
	var r := Vector2(WEIT, WEIT)
	for k in 2:
		var vz := 1.0 if k == 0 else -1.0
		var d := 0.0
		while d < WEIT:
			d += RASTER
			if tw.height_at(p.x + quer.x * vz * d, p.y + quer.y * vz * d) >= hoehe:
				break
		r[k] = d
	return r

## Hoechster Punkt einer Seite: x = Querentfernung, y = Hoehe.
## NUR IM FENSTER 0.70 .. 1.35 * soll gesucht. Ohne das Fenster gewinnt am Talmund ein
## fremder Berg 4 km draussen und am Talschluss die Querkette — der gemessene "Kamm"
## springt dann um ueber 1 km, ohne dass sich an der Talwand etwas geaendert haette.
func _kamm(tw: TerrainWorld, p: Vector2, quer: Vector2, vz: float, soll: float) -> Vector2:
	var best := Vector2(soll, -1e9)
	var d := soll * 0.70
	while d < soll * 1.35:
		d += RASTER
		var h := tw.height_at(p.x + quer.x * vz * d, p.y + quer.y * vz * d)
		if h > best.y:
			best = Vector2(d, h)
	return best

## Wie viele der 2 * n Proben sind auf den Suchanschlag WEIT gelaufen, haben also gar
## keine Hoehenlinie gefunden? Ohne diese Zahl liest sich fehlender Berg wie weites Tal.
func _anschlaege(reihe: Array, schl: String) -> int:
	var n := 0
	for e in reihe:
		var v: Vector2 = e[schl]
		if v.x >= WEIT:
			n += 1
		if v.y >= WEIT:
			n += 1
	return n

func _mittel(reihe: Array, schl: String, a: float, b: float) -> float:
	var s := 0.0
	var n := 0
	for e in reihe:
		var lg: float = e["lg"]
		if lg >= a and lg <= b:
			var v: Vector2 = e[schl]
			s += v.x + v.y
			n += 1
	return s / maxf(float(n), 1.0)
