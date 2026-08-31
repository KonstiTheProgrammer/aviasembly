## WIE GROSS IST DIE INSEL WIRKLICH? Sucht in 16 Richtungen die Kuestenlinie.
##
## Die Kuestenformel in height_at nennt einen Radius, aber was zaehlt, ist die Stelle, an
## der das Gelaende tatsaechlich unter den Meeresspiegel faellt — dort wirken Massive,
## Vulkan und Grundrauschen mit. Ohne diese Messung ist "die Insel ist doppelt so gross"
## eine Behauptung ueber eine Konstante, keine ueber die Welt.
extends SceneTree
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw = main.terrain
	var summe := 0.0
	var lo := 1.0e9
	var hi := 0.0
	print("Richtung | Kueste (km) | Landflaeche im Sektor")
	for i in 16:
		var a := TAU * float(i) / 16.0
		var dx := sin(a)
		var dz := -cos(a)
		var r := 4000.0
		var kueste := 0.0
		while r < 40000.0:
			if tw.height_at(dx * r, dz * r) < TerrainWorld.SEA_Y:
				kueste = r
				break
			r += 200.0
		summe += kueste
		lo = minf(lo, kueste)
		hi = maxf(hi, kueste)
		if i % 2 == 0:
			print("%7.0f° | %10.1f" % [rad_to_deg(a), kueste / 1000.0])
	var mittel := summe / 16.0
	print("\nMittlerer Kuestenradius: %.1f km   (min %.1f, max %.1f)"
		% [mittel / 1000.0, lo / 1000.0, hi / 1000.0])
	print("Landflaeche rund %.0f km2" % (PI * mittel * mittel / 1.0e6))
	quit()
	return true
