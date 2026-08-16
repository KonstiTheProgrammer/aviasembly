## WIE SCHNELL LIEFERT DER WORKER-THREAD CHUNKS — und reicht das im Flug?
##
## Der Ruck ist eine Sache, die kahlen Stellen am Rand sind eine andere: dort fehlt der
## CHUNK, nicht nur sein Bewuchs. Ob das passiert, entscheidet ein Verhaeltnis:
##   Bedarf  = wie viele Chunks je Sekunde beim Fliegen neu bestellt werden
##   Angebot = wie viele der Worker in derselben Zeit fertigstellt
## Diese Datei misst beides und stellt sie gegenueber.
##
## Godot --headless --path . --script res://tools/_worker_takt.gd -- [n=40] [v=170]
extends SceneTree

var _tw: TerrainWorld
var _n := 40
var _v := 170.0
var _start := false


func _process(_d: float) -> bool:
	if not _start:
		_start = true
		for a in OS.get_cmdline_user_args():
			if a.begins_with("n="):
				_n = int(a.substr(2))
			elif a.begins_with("v="):
				_v = float(a.substr(2))
		_tw = TerrainWorld.new()
		root.add_child(_tw)
		_tw.setup(1337, [{"pos": Vector3.ZERO, "r_flat": 240.0, "r_blend": 620.0}], [], [], [])
		return false

	# --- ANGEBOT: was kostet ein Chunk im Worker? ---
	# Ueber Land messen, nicht ueber See: ein Meereschunk hat keinen Bewuchs und waere
	# damit ein geschoenter Wert (dieselbe Falle ist hier schon einmal zugeschnappt).
	var land := 0
	var zeiten: Array = []
	var k := 0
	while land < _n and k < _n * 6:
		var key := Vector2i(6 + (k % 24), -4 + int(k / 24))
		k += 1
		var t0 := Time.get_ticks_usec()
		var d := _tw._make_chunk_data(key)
		var us := float(Time.get_ticks_usec() - t0)
		var pflanzen := 0
		for art in (d["flora"] as Dictionary):
			pflanzen += (d["flora"][art] as Array).size()
		if pflanzen == 0:
			continue          # See oder Fels -> nicht repraesentativ
		land += 1
		zeiten.append(us)
	zeiten.sort()
	var summe := 0.0
	for z in zeiten:
		summe += z
	var mittel := summe / maxf(zeiten.size(), 1)
	print("=== ANGEBOT: %d bewachsene Chunks im Worker ===" % zeiten.size())
	print("  je Chunk: Mittel %.2f ms   Median %.2f ms   schlimmster %.2f ms"
		% [mittel / 1000.0, zeiten[zeiten.size() / 2] / 1000.0,
			zeiten[zeiten.size() - 1] / 1000.0])
	var pro_sek := 1_000_000.0 / maxf(mittel, 1.0)
	print("  ein Worker schafft damit %.1f Chunks je Sekunde" % pro_sek)

	# --- BEDARF: wie viele Chunks fordert der Flug an? ---
	# Beim Ueberqueren einer Chunkzelle kommt eine ganze REIHE des Sichtkreises neu dazu.
	# Laenge der Reihe = Durchmesser des Kreises in Chunks; Zeit = Kantenlaenge / Tempo.
	var reihe := 2.0 * TerrainWorld.VIEW_DIST / TerrainWorld.CHUNK
	var sek_pro_zelle := TerrainWorld.CHUNK / _v
	var bedarf := reihe / sek_pro_zelle
	print("\n=== BEDARF bei %.0f m/s ===" % _v)
	print("  eine Chunkzelle alle %.2f s, dabei rund %.0f neue Chunks -> %.1f je Sekunde"
		% [sek_pro_zelle, reihe, bedarf])
	print("\n=== VERHAELTNIS ===")
	print("  Angebot/Bedarf = %.2f   (unter 1 heisst: die Welt bleibt hinter dem Flug zurueck)"
		% [pro_sek / maxf(bedarf, 0.01)])
	var v_max := pro_sek * TerrainWorld.CHUNK / reihe
	print("  ein Worker reicht bis rund %.0f m/s; darueber reisst der Rand auf." % v_max)
	_tw.queue_free()
	quit()
	return true
