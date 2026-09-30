## Farbvarianten der Haeuser (tools/build_haeuser_blend.py VARIANTEN -> CityBuilder):
## jede Variante hat Fern- UND Nahstufe, die Wahl je Bauplatz ist fest und verteilt sich.
##   Godot --headless --path . --script res://tools/_haus_varianten_check.gd
extends SceneTree


func _initialize() -> void:
	var ok := CityBuilder.has_lib()
	print("Haeuser (Fernstufe): ", CityBuilder._meshes.size(), "  Nahstufe: ",
		CityBuilder._meshes_hd.size())
	for grund in CityBuilder._varianten:
		var liste: Array = CityBuilder._varianten[grund]
		var zahl := {}
		for v in liste:
			zahl[v] = 0
			if not CityBuilder._meshes_hd.has(v):
				print("  FEHLT NAHSTUFE: ", v)
				ok = false
		# 400 Bauplaetze im 12-m-Raster: wie oft kommt jede Variante dran?
		for i in 20:
			for j in 20:
				zahl[CityBuilder.variante(grund, 1000.0 + i * 12.0, -500.0 + j * 12.0)] += 1
		var teile := []
		for v in liste:
			teile.append("%s %d" % [String(v).trim_prefix(grund).trim_prefix("_"), zahl[v]])
		print("  %-18s %s" % [String(grund).trim_prefix("Haus_"), ", ".join(teile)])
		for v in liste:
			if zahl[v] < 60:
				print("  UNGLEICH verteilt: ", v)
				ok = false
		# gleiche Lage -> gleiche Wahl
		if CityBuilder.variante(grund, 123.4, 567.8) != CityBuilder.variante(grund, 123.4, 567.8):
			ok = false
	# Grundtypen ohne Varianten bleiben unveraendert
	if CityBuilder.variante("Haus_Kirche", 10.0, 20.0) != "Haus_Kirche":
		ok = false
	print("URTEIL: ", "OK" if ok else "FEHLER")
	quit()
