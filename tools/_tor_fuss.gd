## FUSSBEREICH DES FELSENTORS: greift die Bewuchssperre der Schutthalde?
##
## Tastet quer zur Talachse (lokales +X des Tors, dicke Seite positiv) ab und meldet je
## Stelle die Haldendichte, den Freiwert aus TerrainWorld._halde_frei und den daraus
## folgenden Wiesenhub. Damit laesst sich ohne Bild entscheiden, ob am Rand der
## Blockschuerze noch Gras steht — genau der Fehler, wegen dem die vorige Fassung
## "helle Quader auf gruener Wiese" zeigte.
##
## Godot --headless --path . --script res://tools/_tor_fuss.gd -- [laengs=0]
extends SceneTree
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 4:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	if f < 8:
		return false

	var laengs := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("laengs="):
			laengs = float(a.substr(7))

	var tw: TerrainWorld = main.terrain
	var K: Dictionary = main.get_script().get_script_constant_map()
	var start: Vector2 = K["TAL_START"]
	var dir: Vector2 = K["TAL_RICHTUNG"]
	var s_w: float = float(K["TOR_SPANN"])
	var p: Vector2 = start + dir * float(K["TOR_LAENGS"])
	var quer := Vector2(dir.y, -dir.x)             # lokales +X in Weltkoordinaten

	var zone: Dictionary = tw.schutthalden[0]
	var roh: Callable = zone["roh"]
	print("FELSENTOR-FUSS, Schnitt bei laengs = %.0f m (lokales z)." % laengs)
	print("  lokal x   Dichte   frei   offen   Wiese   Hoehe")
	var lx := -1.7 * s_w
	while lx <= 1.7 * s_w + 1.0:
		var w: Vector2 = p + quer * lx + dir * laengs
		var d: float = float(roh.call(lx, laengs))
		var frei: float = tw._halde_frei(w.x, w.y)
		var offen: float = tw._open_ground(w.x, w.y)
		var h: float = tw.height_at(w.x, w.y)
		# Wiesenanteil auf ebener Flaeche (ny = 1) — so, wie _face_color ihn benutzt.
		var wi: float = tw._tal_wiese(Vector3(w.x, h, w.y), 1.0) * frei
		print("  %+7.0f   %6.3f  %5.3f  %5.3f  %6.3f  %6.1f"
			% [lx, d, frei, offen, wi, h])
		lx += 40.0
	quit()
	return true
