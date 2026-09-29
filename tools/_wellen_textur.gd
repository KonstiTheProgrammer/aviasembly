## ERZEUGT shaders/wasser_wellen.res — die Wellentextur des Wasser-Shaders.
##
## Warum eine Textur statt Rauschen im Shader: der alte Shader rechnete je Wasserpixel
## neun Value-Noise-Auswertungen (drei Oktaven, dreimal fuer die Ableitung), und in der
## Ferne flimmerte das Muster, weil Rauschen keine Mipmaps hat. Eine Textur traegt HOEHE
## UND ABLEITUNG zugleich (ein Abruf je Oktave statt drei) und wird von der GPU je nach
## Entfernung gefiltert — die Wellen laufen in der Ferne von selbst glatt aus.
##
## INHALT (RGBA, Halbfloat, kachelbar, 256 x 256, mit Mipmaps):
##   R = dh/du, G = dh/dv   Ableitung in KACHEL-Einheiten (u, v laufen 0..1 ueber die Kachel)
##   B = h                  Hoehe, etwa -1..1
##   A = Schaum             Zellnetz (Worley F2-F1), 1 auf den Zellraendern — so sieht
##                          Gischt auf dem Wasser aus: ein Netz, keine Flecken
##
## DIE WELLEN: Summe aus Sinuswellen mit GANZZAHLIGEN Wellenvektoren (dadurch exakt
## kachelbar), Richtungen um +u gestreut (cos^4), Wellenzahl um ZYKLEN = 10 je Kachel.
## Die Wellen laufen also entlang u — der Shader dreht jede Oktave in ihre Windrichtung.
## Kaemme werden ueber exp() angespitzt: Wellentaeler breit, Kaemme schmal, wie auf See.
##
## Godot --headless --path . --script res://tools/_wellen_textur.gd
extends SceneTree

const N := 256
const ZYKLEN := 10.0            # muss mit ZYKLEN in shaders/wasser_kern.gdshaderinc passen
const WELLEN := 56
const SCHAUM_ZELLEN := 9
const ZIEL := "res://shaders/wasser_wellen.res"


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	# --- Spektrum --------------------------------------------------------------------
	var ks: Array[Vector2i] = []
	var amps := PackedFloat32Array()
	var phasen := PackedFloat32Array()
	var tries := 0
	while ks.size() < WELLEN and tries < 10000:
		tries += 1
		# Richtung: cos^4-Streuung um +u (Verwerfungsverfahren)
		var th := rng.randf_range(-PI * 0.5, PI * 0.5)
		if rng.randf() > pow(cos(th), 4.0):
			continue
		# Wellenzahl log-gleichverteilt zwischen 0.5x und 2.2x ZYKLEN
		var k := ZYKLEN * exp(rng.randf_range(log(0.5), log(2.2)))
		var kv := Vector2i(roundi(k * cos(th)), roundi(k * sin(th)))
		if kv == Vector2i.ZERO or ks.has(kv) or ks.has(-kv):
			continue
		ks.append(kv)
		# Amplitude faellt mit der Wellenzahl; die Steigung (a*k) faellt dadurch langsamer
		amps.append(pow(Vector2(kv).length(), -1.6))
		phasen.append(rng.randf() * TAU)
	# --- Hoehe + Ableitung ---------------------------------------------------------------
	var h := PackedFloat32Array()
	var du := PackedFloat32Array()
	var dv := PackedFloat32Array()
	h.resize(N * N); du.resize(N * N); dv.resize(N * N)
	for y in N:
		var v := float(y) / float(N)
		for x in N:
			var u := float(x) / float(N)
			var s := 0.0
			var gu := 0.0
			var gv := 0.0
			for i in ks.size():
				var kv: Vector2i = ks[i]
				var arg := TAU * (float(kv.x) * u + float(kv.y) * v) + phasen[i]
				s += amps[i] * sin(arg)
				var c := amps[i] * cos(arg) * TAU
				gu += c * float(kv.x)
				gv += c * float(kv.y)
			var o := y * N + x
			h[o] = s; du[o] = gu; dv[o] = gv
	# Normieren auf Standardabweichung, dann Kaemme anspitzen
	var summe := 0.0
	var quad := 0.0
	for o in N * N:
		summe += h[o]
		quad += h[o] * h[o]
	var mittel := summe / float(N * N)
	var sigma := sqrt(quad / float(N * N) - mittel * mittel)
	const SPITZE := 0.4
	var e_mittel := 0.0
	for o in N * N:
		e_mittel += exp(SPITZE * (h[o] - mittel) / sigma)
	e_mittel /= float(N * N)
	# Nach dem Anspitzen wieder auf etwa -1..1 bringen (Skalierung aus dem Maximum)
	var hs := PackedFloat32Array()
	hs.resize(N * N)
	var hmax := 0.0
	for o in N * N:
		var z := (h[o] - mittel) / sigma
		var e := exp(SPITZE * z)
		hs[o] = e - e_mittel
		hmax = maxf(hmax, absf(hs[o]))
		var f := SPITZE * e / sigma
		du[o] *= f
		dv[o] *= f
	# --- Schaumnetz (Worley F2-F1, kachelbar) -----------------------------------------
	var pkt: Array[Vector2] = []
	for j in SCHAUM_ZELLEN:
		for i in SCHAUM_ZELLEN:
			pkt.append(Vector2(i + rng.randf_range(0.1, 0.9), j + rng.randf_range(0.1, 0.9)))
	var schaum := PackedFloat32Array()
	schaum.resize(N * N)
	for y in N:
		for x in N:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5) / float(N) * float(SCHAUM_ZELLEN)
			var ci := Vector2i(floori(p.x), floori(p.y))
			var f1 := 1e9
			var f2 := 1e9
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var c := ci + Vector2i(ox, oy)
					var w := Vector2i(posmod(c.x, SCHAUM_ZELLEN), posmod(c.y, SCHAUM_ZELLEN))
					var q: Vector2 = pkt[w.y * SCHAUM_ZELLEN + w.x] + Vector2(c - w)
					var d := p.distance_to(q)
					if d < f1:
						f2 = f1
						f1 = d
					elif d < f2:
						f2 = d
			var rand := f2 - f1
			schaum[y * N + x] = 1.0 - smoothstep(0.0, 0.16, rand)
	# --- Schreiben ---------------------------------------------------------------------
	var daten := PackedFloat32Array()
	daten.resize(N * N * 4)
	for o in N * N:
		daten[o * 4 + 0] = du[o] / hmax
		daten[o * 4 + 1] = dv[o] / hmax
		daten[o * 4 + 2] = hs[o] / hmax
		daten[o * 4 + 3] = schaum[o]
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RGBAF, daten.to_byte_array())
	img.convert(Image.FORMAT_RGBAH)
	img.generate_mipmaps()
	var err := ResourceSaver.save(img, ZIEL)
	var gmax := 0.0
	for o in N * N:
		gmax = maxf(gmax, Vector2(du[o], dv[o]).length() / hmax)
	print("WELLEN %d Wellen, max |grad| %.2f je Kachel, Mipmaps %d, gespeichert: %s (%d)"
		% [ks.size(), gmax, img.get_mipmap_count(), ZIEL, err])
	quit()
