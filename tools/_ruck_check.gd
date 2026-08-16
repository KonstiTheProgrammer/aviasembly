## MISST DEN NACHLADE-RUCK — und zwar aufgeschluesselt, nicht als eine Zahl.
##
## Fliegt eine Gerade ueber Land und treibt dabei GENAU den Pfad an, den Main im Flug
## faehrt: update_center() je Frame, danach TerrainWorld._process(). Beide werden hier
## von Hand gerufen (set_process(false)), damit die Stoppuhr wirklich nur um diesen
## Abschnitt liegt und nicht um irgendetwas anderes im Frame.
##
## WARUM AUFGESCHLUESSELT: der Ruck ist die Summe aus Einhaengen, Physik-Einfuegen,
## Abbauen ferner Chunks, Flora-Nachzug und den beiden Schleifen, die JEDEN Frame ueber
## alle Chunks bzw. alle Flora-MultiMeshes laufen. Eine Gesamtzahl sagt nicht, welcher
## davon den Frame reisst — und die teuerste Vermutung war hier schon zweimal falsch.
##
## Godot --headless --path . --script res://tools/_ruck_check.gd -- [s=60] [v=170] [h=400]
##
## HEADLESS MISST KEINE GPU. Was hier steht, ist reine Main-Thread-Zeit. Genau die
## erzeugt aber den Ruck: ein gerissener Frame entsteht, weil der Main-Thread steht,
## nicht weil die Grafikkarte langsam ist.
##
## WAS DIESE DATEI NICHT MESSEN KANN — bitte nicht darauf hereinfallen:
## Die Frames laufen so schnell durch, wie die CPU kann, waehrend der WORKER-THREAD in
## echter Zeit rechnet. Aus seiner Sicht fliegt der Flug also um ein Vielfaches schneller
## als die angegebenen m/s. Alle Zahlen zum RUECKSTAND (bestellte, noch nicht gelieferte
## Chunks) sind deshalb viel zu schlecht und taugen nur als obere Schranke. Wer wissen
## will, ob der Worker mitkommt, nimmt tools/_worker_takt.gd — das vergleicht Liefertakt
## und Bedarf direkt und kommt ohne Zeitachse aus.
## Die Zeiten JE FRAME sind davon unberuehrt: sie messen Arbeit, nicht Wartezeit.
extends SceneTree

const DT := 1.0 / 60.0

var _tw: TerrainWorld
var _pos := Vector3(1200, 400, -900)
var _dir := Vector3(0.82, 0.0, 0.57).normalized()
var _v := 170.0
var _sek := 60.0
var _frames := 0
var _warm := 0
var _start := false
var _proben: Array = []          # je Frame {t, gesamt, abschnitte}
var _wq_max := 0                 # laengste Flora-Warteschlange im Flug
var _wq_sum := 0
var _wq_leer := 0                # Frames, in denen nichts mehr aussteht
var _pd_max := 0                 # groesster Rueckstand des Worker-Threads
var _pd_sum := 0
var _fehl_max := 0               # fehlende Chunks INNERHALB der Baumreichweite
var _fehl_sum := 0
var _letzte_uhr := 0            # Uhr am Ende des vorigen Durchlaufs (volle Framedauer)


func _process(_d: float) -> bool:
	if not _start:
		_start = true
		var ua := OS.get_cmdline_user_args()
		for a in ua:
			if a.begins_with("s="):
				_sek = float(a.substr(2))
			elif a.begins_with("v="):
				_v = float(a.substr(2))
			elif a.begins_with("h="):
				_pos.y = float(a.substr(2))
		_tw = TerrainWorld.new()
		root.add_child(_tw)
		_tw.setup(1337, [{"pos": Vector3.ZERO, "r_flat": 240.0, "r_blend": 620.0}], [], [], [])
		# Startbereich wie im Spiel synchron stellen, damit die Messung nicht den
		# einmaligen Spawn-Aufbau mitzaehlt.
		_tw.build_now_around(_pos, 900.0)
		_tw.set_process(false)
		_tw.profil_an = true
		print("Reiseflug %.0f s bei %.0f m/s in %.0f m Hoehe (%.1f km Strecke)"
			% [_sek, _v, _pos.y, _sek * _v / 1000.0])
		return false
	# Ein paar Frames laufen lassen, bis der Worker die Startumgebung nachgeliefert hat.
	_warm += 1
	if _warm < 120:
		_tw.profil.clear()
		_tw.update_center(_pos)
		_tw._process(DT)
		return false

	var soll := int(_sek / DT)
	if _frames >= soll:
		_auswerten()
		_tw.queue_free()
		quit()
		return true

	_frames += 1
	_pos += _dir * _v * DT
	_tw.profil.clear()
	var t0 := Time.get_ticks_usec()
	_tw.update_center(_pos)
	var t1 := Time.get_ticks_usec()
	_tw._process(DT)
	var t2 := Time.get_ticks_usec()
	# Die beiden Haelften getrennt festhalten, damit sich unerklaerte Spitzen zuordnen
	# lassen: was in KEINEM der inneren Abschnitte steht, muss in einer der beiden liegen.
	var ab: Dictionary = _tw.profil.duplicate()
	ab["_update_center"] = float(t1 - t0)
	ab["_process"] = float(t2 - t1)
	# VOLLE FRAMEDAUER — Abstand zweier Durchlaeufe. Sie enthaelt alles, was mein
	# Messfenster NICHT sieht: das Zeichnen, das Hochladen frischer Netze in den
	# Grafikspeicher, das Abraeumen weggefallener Knoten am Frameende.
	# WICHTIG: nur aussagekraeftig, wenn OHNE --headless gelaufen wird. Headless zeichnet
	# nicht, und genau daran ist die erste Runde dieser Messung vorbeigegangen.
	if _letzte_uhr > 0:
		ab["_ganzer_frame"] = float(t0 - _letzte_uhr)
	_letzte_uhr = t2
	_proben.append({"f": _frames, "gesamt": float(t2 - t0), "ab": ab})
	# BAEUME: die zweite Haelfte der Beschwerde. Die Warteschlange sagt, ob die Bepflanzung
	# ueberhaupt hinterherkommt — eine lange Schlange heisst, dass Chunks laenger kahl
	# dastehen, egal wie glatt die Bildrate ist.
	_wq_max = maxi(_wq_max, _tw._flora_warteschlange.size())
	_wq_sum += _tw._flora_warteschlange.size()
	if _tw._flora_warteschlange.is_empty():
		_wq_leer += 1
	# RUECKSTAND DES WORKERS. Kahle Stellen entstehen nicht nur, wenn die Bepflanzung
	# haengt, sondern schon wenn der CHUNK selbst noch nicht da ist — dann fehlt mit ihm
	# auch sein Wald. _pending sind die bestellten, noch nicht gelieferten Chunks.
	_pd_max = maxi(_pd_max, _tw._pending.size())
	_pd_sum += _tw._pending.size()
	# Wie viele Chunks in Sichtweite fehlen gerade ganz?
	var fehlt := 0
	for k in _tw._pending:
		if _tw._chunk_center(k).distance_to(Vector2(_pos.x, _pos.z)) <= TerrainWorld.FLORA_DIST:
			fehlt += 1
	_fehl_max = maxi(_fehl_max, fehlt)
	_fehl_sum += fehlt
	return false


## Perzentil aus einer bereits sortierten Liste.
static func _pz(sortiert: Array, q: float) -> float:
	if sortiert.is_empty():
		return 0.0
	var i := clampi(int(round(q * (sortiert.size() - 1))), 0, sortiert.size() - 1)
	return float(sortiert[i])


func _auswerten() -> void:
	var alle: Array = []
	for p in _proben:
		alle.append(p["gesamt"])
	alle.sort()
	var summe := 0.0
	for v in alle:
		summe += v
	print("\n=== STREAMING-ZEIT AM MAIN-THREAD (us je Frame, %d Frames) ===" % _proben.size())
	print("  Mittel %.0f   p50 %.0f   p90 %.0f   p99 %.0f   MAX %.0f"
		% [summe / maxf(alle.size(), 1), _pz(alle, 0.5), _pz(alle, 0.9), _pz(alle, 0.99),
			alle[alle.size() - 1]])
	# Wie viele Frames reissen ein 60-Hz- bzw. 120-Hz-Budget allein durchs Streaming?
	var ueber16 := 0
	var ueber8 := 0
	var ueber4 := 0
	for v in alle:
		if v > 16667.0:
			ueber16 += 1
		if v > 8333.0:
			ueber8 += 1
		if v > 4000.0:
			ueber4 += 1
	print("  Frames ueber 4 ms: %d   ueber 8,3 ms (120 Hz): %d   ueber 16,7 ms (60 Hz): %d"
		% [ueber4, ueber8, ueber16])

	# Anteile: Summe je Abschnitt ueber den ganzen Flug, plus der schlimmste Einzelframe.
	var sum_ab := {}
	var max_ab := {}
	for p in _proben:
		for k in (p["ab"] as Dictionary):
			var v := float(p["ab"][k])
			sum_ab[k] = float(sum_ab.get(k, 0.0)) + v
			max_ab[k] = maxf(float(max_ab.get(k, 0.0)), v)
	var keys: Array = sum_ab.keys()
	keys.sort_custom(func(a, b): return float(sum_ab[a]) > float(sum_ab[b]))
	# MEDIAN UND p90 STATT SPITZE. Mit Fenster (also mit GPU) drosselt macOS den Prozess,
	# sobald er im Hintergrund liegt; einzelne Frames dehnen sich dann auf ueber eine
	# Sekunde, ohne dass der Code etwas dafuer kann. Die Spitze misst dann die Drosselung,
	# nicht die Arbeit. Median und p90 ueberstehen das.
	print("\n=== ABSCHNITTE (Mittel / Median / p90 je Frame, Spitze nur zur Info) ===")
	for k in keys:
		var w: Array = []
		for p in _proben:
			w.append(float((p["ab"] as Dictionary).get(k, 0.0)))
		w.sort()
		print("  %-16s Mittel %6.0f   Median %6.0f   p90 %6.0f   (Spitze %7.0f)"
			% [k, float(sum_ab[k]) / maxf(_proben.size(), 1), _pz(w, 0.5), _pz(w, 0.9),
				float(max_ab[k])])

	# --- BAEUME ---
	var n := maxf(_proben.size(), 1)
	print("\n=== BEPFLANZUNG ===")
	print("  Warteschlange: Mittel %.1f Eintraege, laengste %d, leer in %.0f %% der Frames"
		% [float(_wq_sum) / n, _wq_max, 100.0 * float(_wq_leer) / n])
	# Was steht am Ende wirklich da? Ein Chunk in Sichtweite ohne MultiMesh ist ein kahler.
	var eye := Vector2(_pos.x, _pos.z)
	var nah := 0
	var nah_kahl := 0
	var inst := 0
	for key in _tw._chunks:
		var roh: Variant = _tw._chunks.get(key)
		if roh == null or not is_instance_valid(roh):
			continue
		var node: Node3D = roh
		var c := Vector2((float(key.x) + 0.5) * TerrainWorld.CHUNK,
			(float(key.y) + 0.5) * TerrainWorld.CHUNK)
		if c.distance_to(eye) > TerrainWorld.FLORA_DIST:
			continue
		nah += 1
		var mm := 0
		for g in node.get_children():
			if g is MultiMeshInstance3D:
				mm += 1
				inst += (g as MultiMeshInstance3D).multimesh.instance_count
		if mm == 0:
			nah_kahl += 1
	print("  In Baumreichweite: %d Chunks, davon %d ohne jede Pflanze, %d Instanzen gesamt"
		% [nah, nah_kahl, inst])
	print("  Worker-Rueckstand: Mittel %.1f bestellte Chunks, hoechstens %d"
		% [float(_pd_sum) / n, _pd_max])
	print("  Davon IN Baumreichweite (= sichtbar kahle Stellen): Mittel %.2f, hoechstens %d"
		% [float(_fehl_sum) / n, _fehl_max])

	# Die zehn schlimmsten Frames einzeln — dort entscheidet sich der sichtbare Ruck.
	var sortiert := _proben.duplicate()
	sortiert.sort_custom(func(a, b): return float(a["gesamt"]) > float(b["gesamt"]))
	print("\n=== DIE 10 SCHLIMMSTEN FRAMES ===")
	for i in mini(10, sortiert.size()):
		var p: Dictionary = sortiert[i]
		var teile: Array = []
		var ab: Dictionary = p["ab"]
		var kk: Array = ab.keys()
		kk.sort_custom(func(a, b): return float(ab[a]) > float(ab[b]))
		for k in kk:
			if float(ab[k]) >= 100.0:
				teile.append("%s %.0f" % [k, float(ab[k])])
		print("  Frame %5d  %7.0f us   <- %s" % [p["f"], p["gesamt"], ", ".join(teile)])
