extends SceneTree
## GEGENPROBE: hat sich Gelaende AUSSERHALB des Hochtals geaendert?
##
## Warum nicht per Bildvergleich: die Fernschuerze haengt sich auf einem Thread
## nachtraeglich ein, und die Chunk-Streamer sind zeitabhaengig. Zwei Laeufe DERSELBEN
## Fassung unterscheiden sich am Horizont schon um hunderte Pixel (gemessen: pan2 28 px,
## spawn 750 px). Ein Pixeldiff kann also nicht zwischen "Gelaende geaendert" und
## "Schuerze war noch nicht da" trennen. height_at ist dagegen eine reine Funktion.
##
## Ausgabe ist eine Zahlenliste; zwei Laeufe (Arbeitsstand vs. HEAD-Worktree) werden
## ausserhalb verglichen. Das Hochtal wird ausgespart: alles im Umkreis von TAL_AUS um
## die Talachse gilt als "innen" und darf sich aendern.
##
## godot --headless --path . --script res://tools/_krit4_aussen.gd -- [schritt=250]
var f := 0

const TAL_START := Vector2(-11000.0, -2500.0)
const TAL_RICHTUNG := Vector2(0.6139, -0.7893)
const TAL_LAENGE := 12000.0
const TAL_AUS := 4000.0        # Sicherheitsabstand um die Achse — grosszuegig gewaehlt


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var schritt := 250.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("schritt="):
			schritt = float(a.substr(8))

	# Main.tscn instanzieren, nicht TerrainWorld.new(): das Rauschen wird erst beim
	# Aufbau der Szene gesetzt, sonst liefert height_at nur "get_noise_2d auf null".
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain

	var n := 0
	var summe := 0.0
	var zeilen: Array[String] = []
	var r := -14000.0
	while r <= 14000.0:
		var c := -14000.0
		while c <= 14000.0:
			var p := Vector2(c, r)
			# Abstand zur Talachse (Segment)
			var d := p - TAL_START
			var t: float = clampf(d.dot(TAL_RICHTUNG), 0.0, TAL_LAENGE)
			var abstand := (d - TAL_RICHTUNG * t).length()
			if abstand > TAL_AUS:
				var h: float = tw.height_at(c, r)
				zeilen.append("%.0f %.0f %.3f" % [c, r, h])
				summe += h
				n += 1
			c += schritt
		r += schritt
	print("PROBEN %d  SUMME %.3f" % [n, summe])
	for z in zeilen:
		print(z)
	quit()
	return true
