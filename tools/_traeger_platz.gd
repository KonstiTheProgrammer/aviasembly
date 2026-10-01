## WOHIN MIT DEN FLUGZEUGTRAEGERN?
##
## Die Traeger bekommen KEINEN Kuestenanker (jeder Anker kostet in height_at und verschiebt
## die Kueste der Hauptinsel, also deren Pruefsumme). Dafuer muessen sie von sich aus weit
## genug im Tiefen liegen. Dieses Werkzeug sucht je Peilung ab HEIMAT den ersten Punkt, um
## den herum 1,2 km weit nur tiefes Wasser ist, und gibt die Liste aus — oder prueft mit
## Argumenten feste Punkte nach:
##   Godot --headless --path . --script res://tools/_traeger_platz.gd
##   ... -- x1 z1 x2 z2 ...        nur diese Punkte pruefen
## Laedt Main: NUR mit umgebogenem Spielstand-Ordner (Windows APPDATA, macOS HOME).
extends SceneTree

const FREI_R := 1200.0        # so weit ringsum muss Wasser sein
const TIEFE := 10.0           # mindestens so tief unter dem Meeresspiegel
var f := 0
var m: Node = null


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f < 8:
		return false
	var tw = m.get("terrain")
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		for i in range(0, args.size() - 1, 2):
			var p := Vector2(float(args[i]), float(args[i + 1]))
			print("%8.0f %8.0f  flachste Stelle im Umkreis: %6.1f m unter dem Meer  %s" % [p.x, p.y,
				_tiefe(tw, p), "OK" if _tiefe(tw, p) >= TIEFE else "ZU FLACH"])
		quit()
		return true
	print("Peilung | erster freier Punkt r |        x |        z | flachste Stelle")
	for grad in range(0, 360, 10):
		var ri := Vector2(sin(deg_to_rad(float(grad))), -cos(deg_to_rad(float(grad))))
		var r := 6000.0
		var gefunden := false
		while r < 60000.0:
			if _tiefe(tw, ri * r) >= TIEFE:
				gefunden = true
				break
			r += 400.0
		if gefunden:
			var p := ri * r
			print("  %3d   | %8.0f | %8.0f | %8.0f | %6.1f" % [grad, r, p.x, p.y, _tiefe(tw, p)])
		else:
			print("  %3d   | kein Wasser bis 60 km" % grad)
	quit()
	return true


## Kleinste Wassertiefe im Umkreis FREI_R (negativ = dort ist Land).
func _tiefe(tw, p: Vector2) -> float:
	var flach := 1e9
	for ring: float in [0.0, 0.34, 0.67, 1.0]:
		var n := 1 if ring == 0.0 else 12
		for k in n:
			var w := TAU * float(k) / float(n)
			var q: Vector2 = p + Vector2(cos(w), sin(w)) * FREI_R * ring
			flach = minf(flach, float(tw.SEA_Y) - float(tw.height_at(q.x, q.y)))
	return flach
