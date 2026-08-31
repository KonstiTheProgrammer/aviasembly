## WAS STEHT TATSAECHLICH IN DER KAVERNE?
##
## Im Bild sassen ein gruener Buckel und ein heller Zylinder am Wandfuss, und drei
## Vermutungen nacheinander (Baum, Bausatz, Findling) waren alle falsch — zweimal
## bewiesen durch ein pixelgleiches Bild nach dem angeblichen Fix. Diese Liste beendet
## das Raten: sie laeuft ueber ALLE MeshInstance3D der Flugwelt und meldet jede, deren
## Mittelpunkt im Lichtraum der Roehre liegt, mit Name, Pfad und Lage in Roehrenkoordinaten
## (laengs = Tiefe ab Portal, quer = Abstand von der Achse, hoch = ueber der Sohle).
##
## Godot --headless --path . --script res://tools/_kaverne_inventar.gd
extends SceneTree

const START := Vector2(-11000.0, -2500.0)
const RICHTUNG := Vector2(0.6139, -0.7893)
const PORTAL_LAENGS := 9310.0
const TIEFE := 1080.0
const HALB_B := 60.0      # etwas ueber HB_W_HALLE, damit auch die Wand selbst mitkommt
const HOCH := 70.0

var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var quer := Vector2(RICHTUNG.y, -RICHTUNG.x)
	var p0: Vector2 = START + RICHTUNG * PORTAL_LAENGS
	var treffer: Array = []
	_sammeln(main, p0, quer, treffer)
	treffer.sort_custom(func(a, b): return a["l"] < b["l"])
	print("Objekte im Lichtraum der Roehre: %d" % treffer.size())
	# NUR DIE GROSSEN: 857 Zeilen sind keine Antwort. Ein Ding, das im Bild auffaellt,
	# misst mehrere Meter — Lampen, Markierungen und Bahnfugen faellt damit weg.
	print("  laengs   quer   hoch |    Groesse (m)    | Albedo            | Klasse / Pfad")
	for t in treffer:
		var g: Vector3 = t["g"]
		if maxf(g.x, maxf(g.y, g.z)) < 6.0:
			continue
		var c: Color = t["c"]
		print("  %6.0f %6.1f %6.1f | %5.1f %5.1f %5.1f | %.2f %.2f %.2f  %s | %s"
			% [t["l"], t["q"], t["h"], g.x, g.y, g.z, c.r, c.g, c.b,
				"GRUEN" if c.g > c.r + 0.02 and c.g > c.b + 0.02 else "     ", t["n"]])
	quit()
	return true


func _sammeln(n: Node, p0: Vector2, quer: Vector2, aus: Array) -> void:
	if n is VisualInstance3D:
		var g: Vector3 = (n as VisualInstance3D).global_position
		var d := Vector2(g.x, g.z) - p0
		var l := d.dot(RICHTUNG)
		var q := d.dot(quer)
		var h := g.y - 90.0
		if l > 5.0 and l < TIEFE and absf(q) < HALB_B and h > -5.0 and h < HOCH:
			# NAME UND PFAD REICHEN NICHT: alle Knoten heissen @MeshInstance3D@NNNN. Was
			# ein Ding identifiziert, ist seine Groesse und seine Farbe — danach laesst es
			# sich im Bild wiederfinden.
			var groesse := Vector3.ZERO
			var farbe := Color(0, 0, 0, 0)
			var mi := n as MeshInstance3D
			if mi != null:
				groesse = (n as VisualInstance3D).get_aabb().size * mi.global_basis.get_scale()
				var mat := mi.get_active_material(0)
				if mat is BaseMaterial3D:
					farbe = (mat as BaseMaterial3D).albedo_color
			aus.append({"l": l, "q": q, "h": h, "g": groesse, "c": farbe,
				"n": "%s  (%s)" % [n.get_class(), String(n.get_path()).substr(6, 60)]})
	for c in n.get_children():
		_sammeln(c, p0, quer, aus)
