extends SceneTree
func _process(_d: float) -> bool:
	for sp in ["res://scripts/FlightHud.gd", "res://scripts/Main.gd", "res://scripts/WorldMap.gd", "res://scripts/FlightController.gd", "res://scripts/PartCatalog.gd", "res://scripts/BuildController.gd"]:
		var r = load(sp)
		print(sp, " -> ", "OK" if r != null else "FEHLER")
	quit(); return true
