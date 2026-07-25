## Prueft das 45-Grad-Raster beim Drehen: dieselbe Rechnung wie im Zieh-Zweig, gegen
## eine Reihe von Mauswinkeln. Ohne SHIFT muss der Winkel exakt folgen, mit SHIFT auf
## Vielfache von 45 Grad einrasten.
extends SceneTree
func _process(_d: float) -> bool:
	print("  Mauswinkel   ohne SHIFT   mit SHIFT")
	var ok := true
	for grad in [0.0, 7.0, 22.0, 23.0, 44.0, 46.0, 67.0, 68.0, 100.0, 179.0, -33.0, -70.0]:
		var d := deg_to_rad(grad)
		var gerastert := roundf(d / (PI * 0.25)) * (PI * 0.25)
		var g := rad_to_deg(gerastert)
		print("  %8.1f     %8.1f    %8.1f" % [grad, rad_to_deg(d), g])
		if absf(fposmod(g, 45.0)) > 0.001 and absf(fposmod(g, 45.0) - 45.0) > 0.001:
			ok = false
		if absf(g - grad) > 22.51:
			ok = false        # nie weiter als eine halbe Rasterweite entfernt
	print("RASTER ", "OK" if ok else "FEHLER")
	quit()
	return true
