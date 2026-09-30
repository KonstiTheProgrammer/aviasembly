## EINSCHNITTE UND DAEMME DES STRASSENNETZES: jede zusammenhaengende Strecke, auf der die
## Fahrbahn mehr als SCHWELLE m unter (Einschnitt) bzw. ueber (Damm) dem gewachsenen
## Gelaende liegt — Lage, Laenge, groesste Tiefe. Schaltet nur den Strassen-Schalter kurz aus (ein bool,
## kein geteilter Container — der Kartenfaden liest weiter).
##
##   HOME=<test-home> Godot --headless --path . --script res://tools/_strassen_einschnitte.gd
extends SceneTree
const SCHWELLE := 8.0
var m: Node
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
	if f == 8:
		_pruefen()
		quit()
	return false


func _pruefen() -> void:
	var t: TerrainWorld = m.terrain
	var liste: Array = []
	t.set("_strassen_an", false)
	for pr in t.strassen_profile:
		var pts: PackedVector2Array = pr[0]
		var hh: PackedFloat32Array = pr[1]
		var br: PackedByteArray = pr[2]
		var roh := PackedFloat32Array()
		roh.resize(pts.size())
		for i in pts.size():
			roh[i] = t.height_at(pts[i].x, pts[i].y)
		for art: float in [1.0, -1.0]:
			var i := 0
			while i < pts.size():
				var d: float = (roh[i] - hh[i]) * art
				if br[i] == 1 or d < SCHWELLE:
					i += 1
					continue
				var a := i
				var tief := 0.0
				var bei := pts[i]
				while i < pts.size() and br[i] == 0 and (roh[i] - hh[i]) * art >= SCHWELLE:
					if (roh[i] - hh[i]) * art > tief:
						tief = (roh[i] - hh[i]) * art
						bei = pts[i]
					i += 1
				liste.append([tief, "EINSCHNITT" if art > 0.0 else "DAMM", bei, pts[a].distance_to(pts[i - 1]) + 20.0])
	t.set("_strassen_an", true)
	liste.sort_custom(func(x, y): return x[0] > y[0])
	var summe := {"EINSCHNITT": 0.0, "DAMM": 0.0}
	for e in liste:
		summe[e[1]] += e[3]
	print("STRASSEN-EINSCHNITTE: %d Strecken ueber %.0f m, Einschnitt %.1f km, Damm %.1f km" % [liste.size(),
		SCHWELLE, summe["EINSCHNITT"] / 1000.0, summe["DAMM"] / 1000.0])
	for e in liste.slice(0, 25):
		print("  %-10s %5.1f m bei (%.0f, %.0f), %4.0f m lang" % [e[1], e[0], e[2].x, e[2].y, e[3]])
