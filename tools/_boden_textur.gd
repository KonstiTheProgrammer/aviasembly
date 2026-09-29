## ERZEUGT shaders/boden_detail.res — die Detailtextur des Gelaende-Shaders.
##
## Warum eine Textur: das Gelaende traegt seine Farbe als Vertexfarbe auf einem 8-m-Raster
## (Fernschuerze 32/64 m). Mehr kann das Netz nicht aufloesen — aus der Naehe ist jede
## Wiese eine einzige glatte Farbflaeche, aus der Hoehe liegt dieselbe Farbe ueber
## Kilometer gleichmaessig da. Die Textur liefert beides nach, was fehlt: Koernung und
## Relief im Nahbereich, grosse Flecken (trockener, feuchter, heller, dunkler) in der Ferne.
## Kachelbar, mit Mipmaps — in der Ferne filtert die GPU das Korn von selbst weg.
##
## INHALT (RGBA8, 512 x 512, kachelbar):
##   R = Korn       feines, klumpiges Muster (fBm + Zellrauschen): Grasbueschel, Erde, Fels
##   G = Flecken    weiches fBm mit wenigen grossen Formen, fuer die Grossvariation
##   B, A = Relief  Ableitung d(Korn)/du, d(Korn)/dv, um 0.5 kodiert — das Korn ist also
##                  zugleich die Hoehe der Unebenheit, Farbe und Licht passen zusammen
##
## Godot --headless --path . --script res://tools/_boden_textur.gd
extends SceneTree

const N := 512
const ZIEL := "res://shaders/boden_detail.res"


func _initialize() -> void:
	var korn_a := FastNoiseLite.new()
	korn_a.seed = 7101
	korn_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	korn_a.fractal_type = FastNoiseLite.FRACTAL_FBM
	korn_a.fractal_octaves = 5
	korn_a.fractal_gain = 0.55
	korn_a.frequency = 1.0 / 42.0
	var korn_b := FastNoiseLite.new()
	korn_b.seed = 7102
	korn_b.noise_type = FastNoiseLite.TYPE_CELLULAR
	korn_b.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	korn_b.cellular_jitter = 0.9
	korn_b.fractal_type = FastNoiseLite.FRACTAL_FBM
	korn_b.fractal_octaves = 2
	korn_b.frequency = 1.0 / 26.0
	var flecken := FastNoiseLite.new()
	flecken.seed = 7103
	flecken.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	flecken.fractal_type = FastNoiseLite.FRACTAL_FBM
	flecken.fractal_octaves = 4
	flecken.fractal_gain = 0.5
	flecken.frequency = 1.0 / 150.0
	var ia := korn_a.get_seamless_image(N, N, false, false, 0.12, true)
	var ib := korn_b.get_seamless_image(N, N, false, false, 0.12, true)
	var ig := flecken.get_seamless_image(N, N, false, false, 0.12, true)
	var korn := _normiert(ia, ib, 0.62)
	var fleck := _normiert(ig, null, 1.0)
	# Relief: zentrale Differenzen mit Umlauf (kachelbar), dann auf -1..1 skaliert.
	var du := PackedFloat32Array()
	var dv := PackedFloat32Array()
	du.resize(N * N)
	dv.resize(N * N)
	var gmax := 0.0
	for y in N:
		for x in N:
			var o := y * N + x
			du[o] = korn[y * N + (x + 1) % N] - korn[y * N + (x + N - 1) % N]
			dv[o] = korn[((y + 1) % N) * N + x] - korn[((y + N - 1) % N) * N + x]
			gmax = maxf(gmax, maxf(absf(du[o]), absf(dv[o])))
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var o := y * N + x
			img.set_pixel(x, y, Color(korn[o], fleck[o],
				0.5 + 0.5 * du[o] / gmax, 0.5 + 0.5 * dv[o] / gmax))
	img.generate_mipmaps()
	var err := ResourceSaver.save(img, ZIEL)
	print("BODEN %dx%d, Mipmaps %d, gespeichert: %s (%d)" % [N, N, img.get_mipmap_count(), ZIEL, err])
	quit()


## Mischt zwei Graustufenbilder und bringt das Ergebnis auf Mittel 0.5, +-3 Sigma = 0..1.
func _normiert(a: Image, b: Image, anteil_a: float) -> PackedFloat32Array:
	var roh := PackedFloat32Array()
	roh.resize(N * N)
	var summe := 0.0
	var quad := 0.0
	for y in N:
		for x in N:
			var v := a.get_pixel(x, y).r * anteil_a
			if b != null:
				v += b.get_pixel(x, y).r * (1.0 - anteil_a)
			roh[y * N + x] = v
			summe += v
			quad += v * v
	var mittel := summe / float(N * N)
	var sigma := sqrt(maxf(quad / float(N * N) - mittel * mittel, 1e-8))
	for o in N * N:
		roh[o] = clampf(0.5 + (roh[o] - mittel) / (6.0 * sigma), 0.0, 1.0)
	return roh
