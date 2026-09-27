## WIE EBEN IST DER ANFLUG AUF ADLERHORST?
##
## Eine Anflugbefeuerung liegt auf dem Boden. Wo der Boden vor der Schwelle ansteigt oder
## abfaellt, schweben ihre Balken oder verschwinden im Gras — und zwar genau dort, wo man
## sie am dringendsten braucht. Vor dem Bauen also messen, wie weit die Ebene reicht.
##
## Godot --headless --path . --script res://tools/_anflug_profil.gd
extends SceneTree

const START := Vector2(-11000.0, -2500.0)
const RICHTUNG := Vector2(0.6139, -0.7893)
const SCHWELLE := 9370.0        # Bahnanfang im Berg
const SOLL := 90.0              # ADLERHORST_HOEHE

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if not has_meta("m"):
		var m: Node = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		set_meta("m", m)
		return false
	if f < 8:
		return false
	var tw = get_meta("m").get("terrain")
	var quer := Vector2(RICHTUNG.y, -RICHTUNG.x)
	print("Abstand vor der Schwelle | Hoehe auf der Achse und +-20 m | Abweichung")
	print("-------------------------+--------------------------------+-----------")
	for i in 17:
		var ab := float(i) * 60.0
		var l := SCHWELLE - ab
		var h: Array[float] = []
		for q: float in [-20.0, 0.0, 20.0]:
			var p := START + RICHTUNG * l + quer * q
			h.append(tw.height_at(p.x, p.y))
		var abw: float = maxf(absf(h[0] - SOLL), maxf(absf(h[1] - SOLL), absf(h[2] - SOLL)))
		print("%20.0f m | %7.1f %7.1f %7.1f          | %6.1f m %s"
			% [ab, h[0], h[1], h[2], abw, "" if abw < 1.5 else "<-- nicht mehr eben"])
	quit()
	return true
