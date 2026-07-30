## Listet alle Fluegel-Teile mit den Massen, die fuers Snapping zaehlen.
extends SceneTree

func _initialize() -> void:
	print("%-18s %-26s %-6s %-22s %-22s" % ["id", "name", "ctrl", "col_size", "col_offset"])
	print("-".repeat(100))
	for id in PartCatalog.all().keys():
		var p: Dictionary = PartCatalog.all()[id]
		if not bool(p.get("is_wing", false)):
			continue
		var cs: Vector3 = PartCatalog.col_size(p)
		var co: Vector3 = PartCatalog.col_offset(p)
		print("%-18s %-26s %-6s (%5.2f %5.2f %5.2f)      (%5.2f %5.2f %5.2f)" % [
			id, String(p.get("name", "")), String(p.get("control", "-")),
			cs.x, cs.y, cs.z, co.x, co.y, co.z])
	quit()
