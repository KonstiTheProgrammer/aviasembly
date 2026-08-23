## EIN STICH DURCH DAS BILD: welche Regel faerbt diesen einen Bildpunkt?
##
## WOFUER: im Abnahmebild lag ein heller Streifen auf der Ascheschuerze, und drei Vermutungen
## hintereinander (Fernschuerze, Felsregel der Welt, Duenensand) waren alle falsch. Ein Render
## sagt WIE es aussieht, aber nicht WARUM — und die Farbe eines Punktes entsteht in
## _face_color aus einem halben Dutzend Regeln, die sich gegenseitig ueberschreiben.
## Dieses Werkzeug schiesst einen Strahl aus der Abnahmekamera durch einen Bildpunkt, sucht
## den Gelaendeschnitt und druckt ALLE Zwischengroessen, die dort gelten.
##
## Godot --headless --path . --script res://tools/_vulkan_stich.gd -- px,py [px,py ...]
extends SceneTree
var f := 0

# Kamera "vulkan_ref" aus tools/_terrain_render.gd — dieselben Zahlen, sonst trifft der
# Strahl einen anderen Punkt als das Bild.
const CAM := Vector3(11800, 1500, -2100)
const ZIEL := Vector3(11800, 330, -5600)
const VFOV := 64.0
const BREIT := 1280.0
const HOCH := 720.0


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

	var punkte: Array = []
	for a in OS.get_cmdline_user_args():
		var t := String(a).split(",")
		if t.size() == 2:
			punkte.append(Vector2(float(t[0]), float(t[1])))
	if punkte.is_empty():
		punkte = [Vector2(760, 690), Vector2(690, 660), Vector2(600, 600)]

	var dir := (ZIEL - CAM).normalized()
	var rechts := Vector3.UP.cross(dir).normalized() * -1.0
	var oben := dir.cross(rechts).normalized() * -1.0
	var ty := tan(deg_to_rad(VFOV * 0.5))
	var tx := ty * BREIT / HOCH

	for pt_v in punkte:
		var pt: Vector2 = pt_v
		var nx := (pt.x - BREIT * 0.5) / (BREIT * 0.5)
		var ny := (HOCH * 0.5 - pt.y) / (HOCH * 0.5)
		var r := (dir + rechts * (nx * tx) + oben * (ny * ty)).normalized()
		# Gelaendeschnitt: grob vorlaufen, dann halbieren.
		var t := 50.0
		var treffer := -1.0
		while t < 9000.0:
			var q := CAM + r * t
			if q.y <= tw.height_at(q.x, q.z):
				treffer = t
				break
			t += 12.0
		if treffer < 0.0:
			print("Bildpunkt (%.0f, %.0f): kein Gelaendeschnitt" % [pt.x, pt.y])
			continue
		var lo := treffer - 12.0
		var hi := treffer
		for i in 24:
			var m := (lo + hi) * 0.5
			var q := CAM + r * m
			if q.y <= tw.height_at(q.x, q.z):
				hi = m
			else:
				lo = m
		var w := CAM + r * hi
		var h := tw.height_at(w.x, w.z)
		var cen := Vector3(w.x, h, w.z)
		# Flaechennormale aus dem Hoehenfeld, mit derselben Zellweite wie das Netz (8 m).
		var hx := tw.height_at(w.x + 8.0, w.z) - tw.height_at(w.x - 8.0, w.z)
		var hz := tw.height_at(w.x, w.z + 8.0) - tw.height_at(w.x, w.z - 8.0)
		var n := Vector3(-hx, 16.0, -hz).normalized()
		var md := Vector2(w.x - p.x, w.z - p.z).length()
		var c: Color = tw._face_color(cen, n.y)
		print("\nBildpunkt (%.0f, %.0f)  ->  Welt (%.0f, %.0f)  Hoehe %.1f m  Abstand %.0f m"
			% [pt.x, pt.y, w.x, w.z, h, md])
		print("   Farbe            %.3f %.3f %.3f   (Alpha %.2f)" % [c.r, c.g, c.b, c.a])
		print("   Normale ny       %.3f" % n.y)
		print("   Biom             %s" % ["WALD", "WUESTE", "HOCHLAND", "HEIDE"][
			tw.biome_at(w.x, w.z)])
		print("   Waldanteil       %.3f" % tw.wald_anteil(w.x, w.z, h, n.y))
		print("   Vulkanbewuchs    %.3f" % tw.vulkan_bewuchs(w.x, w.z, h))
		print("   Kragen           %.3f" % tw.vulkan_kragen(w.x, w.z, h))
		print("   Lavastrom        %.3f" % tw.vulkan_strom_bei(w.x, w.z))
		print("   Haut-Radius      %.0f m   Schuerzensaum %.0f m"
			% [float(vk["r"]) * TerrainWorld.VULKAN_APRON_ASCHE_AB,
				float(vk["r"]) * TerrainWorld.VULKAN_APRON_WEIT])
	quit()
	return true
