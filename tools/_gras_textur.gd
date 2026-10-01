## ERZEUGT shaders/gras_fern.res — die Bueschelkarte des FERNGRASES (gelaende_kern).
##
## Echte Grasbueschel stehen nur bis 105 m um die Kamera (TerrainWorld.GRAS_FERN_R). Dahinter
## malt der Gelaende-Shader sie auf den Boden: er schneidet diese Karte in mehreren Hoehen
## und versetzt jeden Schnitt um die Sichtlinie, sodass die Bueschel wie stehende Koerper
## erscheinen. Die Karte bildet den AEUSSEREN HALMRING nach (shaders/gras_bahn.gdshader):
## ein Bueschel je 1,92-m-Zelle, in der Zelle verwuerfelt, Groesse 1,45 * (0,60 + 0,75 z1 z2).
##
## INHALT (RGBA8, 1024 x 1024, kachelbar ueber KACHEL Meter, mit Mipmaps):
##   R = Hoehe des Bueschels an dieser Stelle (0..1 = 0..H_MAX m), Kuppel mit Sternumriss
##   G = Gipfelhoehe des Bueschels (0..1), im ganzen Umfeld gleich — daraus die Lage am Halm
##   B = Ton (Zufall je Bueschel): Spitzenaufhellung und Helligkeit wie bei den Halmen
##   A = Rang (gleichverteilt 0..1): das Bueschel steht, wenn Rang < Dichte der Wiese
## G, B, A gelten in einem Saum um das Bueschel (naechstes gewinnt), damit die Filterung am
## Rand nicht die Werte des leeren Bodens einmischt.
##
## Godot --headless --path . --script res://tools/_gras_textur.gd
## Gibt die Deckung je Schnitthoehe aus (Grundlage fuer FG_DECK_OBEN im Shader).
extends SceneTree

const N := 1024
const KACHEL := 48.0          # m — = FG_KACHEL in gelaende_kern
const ZELLEN := 25            # Bueschel je Kante: 1,92 m (aeusserer Halmring 1,9 m)
const H_MAX := 2.2            # m — = FG_HOEHE in gelaende_kern
const SAUM := 0.6             # m um das Bueschel, in dem G/B/A gelten
const ZIEL := "res://shaders/gras_fern.res"


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var hoehe := PackedFloat32Array()
	hoehe.resize(N * N)
	var naechst := PackedFloat32Array()
	naechst.resize(N * N)
	naechst.fill(1.0e9)
	var gba := PackedByteArray()
	gba.resize(N * N * 3)
	for o in N * N:
		gba[o * 3] = 128
		gba[o * 3 + 1] = 128
		gba[o * 3 + 2] = 255      # Rang 1 = steht nie
	# Raenge gleichverteilt und gemischt: bei Dichte d steht genau der Anteil d.
	var anzahl := ZELLEN * ZELLEN
	var rang: Array[float] = []
	for i in anzahl:
		rang.append((float(i) + 0.5) / float(anzahl))
	for i in range(anzahl - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := rang[i]
		rang[i] = rang[j]
		rang[j] = t
	var zelle := KACHEL / float(ZELLEN)
	var m_px := KACHEL / float(N)
	for cz in ZELLEN:
		for cx in ZELLEN:
			var z1 := rng.randf()
			var z2 := rng.randf()
			var z3 := rng.randf()
			var s := 1.45 * (0.60 + 0.75 * z1 * z2)
			var rad := 0.30 * s
			var gipfel := minf(0.70 * s * (0.75 + 0.55 * z3), H_MAX) / H_MAX
			var mx := (float(cx) + rng.randf()) * zelle
			var mz := (float(cz) + rng.randf()) * zelle
			var phase := rng.randf() * TAU
			var reich := rad + SAUM
			var r_i := rang[cz * ZELLEN + cx]
			var x0 := int(floor((mx - reich) / m_px))
			var x1 := int(ceil((mx + reich) / m_px))
			var y0 := int(floor((mz - reich) / m_px))
			var y1 := int(ceil((mz + reich) / m_px))
			for py in range(y0, y1 + 1):
				for px in range(x0, x1 + 1):
					var dx := (float(px) + 0.5) * m_px - mx
					var dz := (float(py) + 0.5) * m_px - mz
					var d := sqrt(dx * dx + dz * dz)
					if d > reich:
						continue
					var o := posmod(py, N) * N + posmod(px, N)
					# Fuenf Halme: der Umriss ist ein weicher Stern, die Form eine Kuppel
					# (auf halber Hoehe noch drei Viertel so breit wie am Fuss).
					var stern := 0.62 + 0.38 * cos(5.0 * atan2(dz, dx) + phase)
					var prof := maxf(1.0 - d / (rad * stern), 0.0)
					var hv := gipfel * sqrt(prof)
					if hv > hoehe[o]:
						hoehe[o] = hv
					var rel := d / rad
					if rel < naechst[o]:
						naechst[o] = rel
						gba[o * 3] = clampi(roundi(gipfel * 255.0), 0, 255)
						gba[o * 3 + 1] = clampi(roundi(z3 * 255.0), 0, 255)
						gba[o * 3 + 2] = clampi(roundi(r_i * 255.0), 0, 255)
	var daten := PackedByteArray()
	daten.resize(N * N * 4)
	for o in N * N:
		daten[o * 4] = clampi(roundi(hoehe[o] * 255.0), 0, 255)
		daten[o * 4 + 1] = gba[o * 3]
		daten[o * 4 + 2] = gba[o * 3 + 1]
		daten[o * 4 + 3] = gba[o * 3 + 2]
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, daten)
	img.generate_mipmaps()
	var err := ResourceSaver.save(img, ZIEL, ResourceSaver.FLAG_COMPRESS)
	print("GRASKARTE %dx%d, %d Bueschel, Mipmaps %d, gespeichert: %s (%d)"
		% [N, N, anzahl, img.get_mipmap_count(), ZIEL, err])
	for h in [0.05, 0.12, 0.19, 0.27, 0.36, 0.46]:      # = FG_SCHICHT in gelaende_kern
		var n := 0
		for o in N * N:
			if hoehe[o] > h:
				n += 1
		print("  Deckung ueber %.2f (%.2f m): %.3f" % [h, h * H_MAX, float(n) / float(N * N)])
	quit()
