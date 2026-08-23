## WAS RINGS UM DEN VULKAN STEHT — die Probe VOR jeder Vergroesserung des Fussabdrucks.
##
## Der Kegel soll breiter werden, und "breiter" heisst hier: die Schuerze traegt Gelaende
## auf, wo bisher Vorland war. Das ist harmlos, solange dort Wiese liegt, und es ist ein
## Fehler, sobald dort Wasser liegt — eine Schuerze, die den Meeresgrund anhebt, macht aus
## der Bucht eine Sandbank, und aus einem See eine Pfuetze. Deshalb misst dieses Werkzeug,
## wie weit das Land um den Vulkan ueberhaupt reicht, bevor irgendeine Zahl in der
## Massivtabelle wandert.
##
## Godot --headless --path . --script res://tools/_vulkan_umland.gd
extends SceneTree
var f := 0

func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	var tw: TerrainWorld = main.terrain
	var vk: Dictionary = {}
	for ms in tw.massifs:
		if String(ms.get("type", "")) == "vulkan":
			vk = ms
			break
	var p: Vector3 = vk["pos"]
	var mr := float(vk["r"])
	print("Vulkan (%.0f, %.0f)  r=%.0f  peak=%.0f  Meeresspiegel %.1f m"
		% [p.x, p.z, mr, float(vk["peak"]), TerrainWorld.SEA_Y])

	print("\n=== UMLAND: Hoehe je Richtung und Abstand ===")
	print(" Winkel " + "".join(PackedStringArray([])))
	var kopf := " Winkel "
	var rr: Array[float] = []
	var d := 1400.0
	while d <= 4200.0:
		rr.append(d)
		kopf += "%7.0f" % d
		d += 200.0
	print(kopf)
	var nass := {}
	for k in 24:
		var a := float(k) * TAU / 24.0
		var ca := cos(a)
		var sa := sin(a)
		var zeile := " %5.0f  " % rad_to_deg(a)
		for r in rr:
			var hh := tw.height_at(p.x + ca * r, p.z + sa * r)
			zeile += "%7.0f" % hh
			if hh < TerrainWorld.SEA_Y + 3.0 and not nass.has(k):
				nass[k] = r
		print(zeile)
	print("\nRichtungen mit Wasser/Kueste innerhalb 4200 m:")
	if nass.is_empty():
		print("  KEINE — der Fussfaecher darf rundum bis 4200 m auslaufen.")
	else:
		for k in nass:
			print("  %5.0f Grad ab %.0f m" % [float(k) * 360.0 / 24.0, nass[k]])

	quit()
	return true
