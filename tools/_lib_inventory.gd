extends SceneTree
func _process(_d: float) -> bool:
	for cat in PartCatalog.categories():
		var ids := []
		for p in PartCatalog.parts_in(cat):
			var id: String = p.get("id", "")
			var model_id: String = p.get("model", id)
			if PartCatalog.has_model(model_id) and not p.get("force_proc", false):
				ids.append(model_id if model_id == id else id + ">" + model_id)
		print(cat, " :: ", ", ".join(ids))
	quit(); return true
