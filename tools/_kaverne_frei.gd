## GREIFT DIE FREIHALTUNG IN DER KAVERNE?
##
## Im Bild standen Nadelbaeume im Bereich des Tunnelmunds. Ob sie INNEN stehen (Fehler)
## oder draussen im Tal (richtig), ist aus der Kamera nicht zu entscheiden — die Vorlage
## fuer beides ist derselbe dunkle Baum vor hellem Grund. _open_ground beantwortet es
## direkt: 0 heisst "hier waechst nichts", 1 heisst voller Bewuchs.
##
## Godot --headless --path . --script res://tools/_kaverne_frei.gd
extends SceneTree

const START := Vector2(-11000.0, -2500.0)
const RICHTUNG := Vector2(0.6139, -0.7893)

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var quer := Vector2(RICHTUNG.y, -RICHTUNG.x)
	print(" laengs | quer 0   +-40   +-90  +-160 | 0 = frei, 1 = voller Bewuchs")
	# Bis 10450: die Roehre reicht seit der Verlaengerung auf HB_LAENGE = 1080 bis
	# laengs 10390, und genau hinter der alten Messgrenze standen die Straeucher.
	for i in 18:
		var l := 9250.0 + float(i) * 70.0
		var zeile := "%7.0f |" % l
		for d in [0.0, 40.0, 90.0, 160.0]:
			var p: Vector2 = START + RICHTUNG * l + quer * d
			zeile += "  %4.2f" % tw._open_ground(p.x, p.y)
		var lage := ""
		if l > 9310.0:
			lage = "   <- IM BERG"
		elif l > 9270.0:
			lage = "   <- Schwelle"
		print(zeile, lage)
	quit()
	return true
