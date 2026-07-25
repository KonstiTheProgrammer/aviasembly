## Zaehlt ueber ein grosses Kartenfeld, welche Baumarten wo entstehen — belegt, dass die
## Verteilung greift (Biom + Hoehe) und nicht nur eine Art gesetzt wird.
extends SceneTree
func _process(_d: float) -> bool:
	var tw := TerrainWorld.new()
	root.add_child(tw)
	tw.setup(GameState.new().world_seed if false else 12345, [], [], [], [])
	var gesamt: Dictionary = {}
	var pro_hoehe: Dictionary = {}
	var chunks := 0
	for cy in range(-9, 10):
		for cx in range(-9, 10):
			var d: Dictionary = tw._make_chunk_data(Vector2i(cx, cy))
			chunks += 1
			var fl: Dictionary = d.get("flora", {})
			for art in fl.keys():
				gesamt[art] = int(gesamt.get(art, 0)) + fl[art].size()
				for xf in fl[art]:
					var y: float = xf.origin.y
					var stufe := "  0-24 m" if y < 24.0 else (" 24-42 m" if y < 42.0 else " ueber 42 m")
					var k: String = stufe + " " + art
					pro_hoehe[k] = int(pro_hoehe.get(k, 0)) + 1
	print("Chunks: ", chunks)
	var summe := 0
	for art in gesamt.keys():
		summe += int(gesamt[art])
	for art in ["Fichte", "Kiefer", "Birke", "Eiche", "Palme", "Totholz", "Busch"]:
		var n: int = int(gesamt.get(art, 0))
		print("  %-9s %6d  (%4.1f %%)" % [art, n, 100.0 * float(n) / maxf(float(summe), 1.0)])
	print("Baeume gesamt: ", summe, "  Meshes geladen: ", tw._flora.size())
	var keys: Array = pro_hoehe.keys()
	keys.sort()
	for k in keys:
		print("   ", k, ": ", pro_hoehe[k])
	quit()
	return true
