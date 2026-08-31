## WOHIN GEHOEREN DIE SCHIFFE?
##
## Nach jeder Aenderung der Kuestenlinie liegen sie falsch, und zwar reihum: erst nach
## der letzten Vergroesserung vier von ihnen an Land, jetzt nach dieser alle fuenf. Sie
## von Hand zu verschieben, heisst raten — die Kueste ist winkelabhaengig verrauscht, ein
## Schaetzwert liegt in der einen Peilung 3 km zu weit und in der naechsten wieder an
## Land.
##
## Dieses Werkzeug rechnet sie aus: es behaelt die PEILUNG jedes Schiffes bei (die Lage
## zur Insel soll sich nicht aendern), sucht auf diesem Strahl die Wasserlinie und setzt
## das Schiff mit festem Sicherheitsabstand dahinter. Ausgegeben wird fertiger GDScript.
##
## Godot --headless --path . --script res://tools/_seeplatz.gd
extends SceneTree

# Abstand hinter der Wasserlinie. 2500 m statt der frueheren 900: mit 900 hat die naechste
# Kuestenaenderung sie wieder auf den Strand gesetzt.
const RESERVE := 2500.0
const SCHIFFE := [
	["Segler 1", Vector2(23189, -7730), 0.7],
	["Segler 2", Vector2(19120, -15695), 2.4],
	["Segler 3", Vector2(-18051, 20268), -0.9],
	["Segler 4", Vector2(6843, -24695), 1.6],
	["Wrack", Vector2(23539, -6523), 0.8],
]

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if not has_meta("main"):
		var m: Node = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		set_meta("main", m)
		return false
	if f < 8:
		return false
	var main: Node = get_meta("main")
	var tw = main.get("terrain")
	var meer: float = tw.SEA_Y

	print("Objekt     | alt r | Wasserlinie | neu r |    neu x |    neu z | Grund neu")
	print("-----------+-------+-------------+-------+----------+----------+----------")
	for e in SCHIFFE:
		var v: Vector2 = e[1]
		var ri := v.normalized()
		var alt_r := v.length()
		# Wasserlinie auf diesem Strahl suchen: von innen nach aussen, erste Stelle, ab
		# der es auf 600 m Weiterfahrt NICHT mehr an Land geht. Die Zusatzpruefung ist
		# noetig, weil eine vorgelagerte Insel sonst als Kueste durchginge.
		var linie := 40000.0
		var r := 15000.0
		while r < 40000.0:
			if tw.height_at(ri.x * r, ri.y * r) <= meer - 3.0:
				var sauber := true
				for k in 6:
					var rr := r + float(k + 1) * 100.0
					if tw.height_at(ri.x * rr, ri.y * rr) > meer - 3.0:
						sauber = false
						break
				if sauber:
					linie = r
					break
			r += 100.0
		var neu_r := linie + RESERVE
		var np := ri * neu_r
		print("%-10s | %5.1f | %11.1f | %5.1f | %8.0f | %8.0f | %8.1f"
			% [e[0], alt_r / 1000.0, linie / 1000.0, neu_r / 1000.0, np.x, np.y,
				tw.height_at(np.x, np.y)])
	quit()
	return true
