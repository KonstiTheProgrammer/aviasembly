## ZAEHLT DIE RIPPEN AUF DER VULKANFLANKE — die Frage, die "Hoehenstreuung" nicht beantwortet.
##
## _vulkan_form.gd meldet je Ring eine Spanne von Minimum zu Maximum. Diese Zahl war auf
## jedem Ring 170 bis 183 m gross, und trotzdem meldeten zwei unabhaengige Abnahmen die
## Flanke als glatt. Beides stimmt: eine SPANNE sagt, wie weit hoch und tief auseinander
## liegen, aber nicht, WIE OFT es zwischen ihnen wechselt. Zwei grosse Lappen und eine
## Scharte erzeugen dieselbe Spanne wie dreissig Rippen — im Bild sieht das eine glatt aus
## und das andere gerippt.
##
## Gemessen wird deshalb der WECHSEL: die Hoehe laengs eines Rings, von ihrem eigenen
## gleitenden Mittel abgezogen. Was uebrigbleibt, ist die Rippung ohne die grossen Lappen;
## ihre Nulldurchgaenge geteilt durch zwei sind die Zahl der Grat-Rinne-Paare.
##
## Godot --headless --path . --script res://tools/_vulkan_rippen.gd
extends SceneTree

const RINGE: Array[float] = [500.0, 700.0, 900.0, 1100.0]
const PROBEN := 1440                  # 0,25 Grad
const FENSTER := 60                   # gleitendes Mittel ueber +-15 Grad

var _f := 0


func _process(_d: float) -> bool:
	_f += 1
	if _f < 3:
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
		print("KEIN VULKAN GEFUNDEN")
		quit(1)
		return true
	var mp: Vector3 = vk["pos"]

	print("=== RIPPEN AUF DER FLANKE: Zahl der Grat-Rinne-Paare je Ring ===")
	print(" Radius   Paare   Amplitude (Spitze-Tal)   Standardabw.   Spanne roh")
	for r in RINGE:
		var h := PackedFloat32Array()
		h.resize(PROBEN)
		for i in PROBEN:
			var a := TAU * float(i) / float(PROBEN)
			h[i] = tw.height_at(mp.x + cos(a) * r, mp.z + sin(a) * r)
		# Gleitendes Mittel, zyklisch — das ist die GROSSFORM (Lappen, Scharte, Schieflage).
		var glatt := PackedFloat32Array()
		glatt.resize(PROBEN)
		for i in PROBEN:
			var s := 0.0
			for k in range(-FENSTER, FENSTER + 1):
				s += h[(i + k + PROBEN) % PROBEN]
			glatt[i] = s / float(2 * FENSTER + 1)
		# Was uebrigbleibt, ist die Rippung.
		var rest := PackedFloat32Array()
		rest.resize(PROBEN)
		var lo := INF
		var hi := -INF
		var quad := 0.0
		for i in PROBEN:
			rest[i] = h[i] - glatt[i]
			lo = minf(lo, rest[i])
			hi = maxf(hi, rest[i])
			quad += rest[i] * rest[i]
		# Nulldurchgaenge zaehlen. TOTBAND gegen Zittern: ein Wechsel zaehlt erst, wenn der
		# Rest seit dem letzten Wechsel um mehr als ein Zehntel der Amplitude ausgeschlagen
		# hat. Ohne das zaehlt jede Facettenkante des 8-m-Netzes als eigene Rippe.
		var schwelle := 0.10 * maxf(hi - lo, 0.001)
		var wechsel := 0
		var zeichen := 0
		var spitze := 0.0
		for i in PROBEN:
			var v := rest[i]
			if absf(v) > absf(spitze):
				spitze = v
			var z := 0
			if v > schwelle:
				z = 1
			elif v < -schwelle:
				z = -1
			if z != 0 and z != zeichen:
				if zeichen != 0:
					wechsel += 1
				zeichen = z
				spitze = 0.0
		var roh_lo := INF
		var roh_hi := -INF
		for i in PROBEN:
			roh_lo = minf(roh_lo, h[i])
			roh_hi = maxf(roh_hi, h[i])
		print("  %5.0f m   %5.1f   %8.1f m              %6.1f m       %6.1f m"
			% [r, float(wechsel) / 2.0, hi - lo, sqrt(quad / float(PROBEN)),
				roh_hi - roh_lo])
	print("")
	print("LESEHILFE: die Vorgabe der Abnahme sind 20 bis 30 Paare je Ring, mit einer")
	print("Amplitude, die von wenigen Metern am Kraterrand auf 25 bis 40 m auf halber")
	print("Flanke waechst. Wenige Paare bei grosser roher Spanne heisst: grosse Lappen,")
	print("glatte Flanke — genau der Befund, den zwei Abnahmen gemeldet haben.")
	quit()
	return true
