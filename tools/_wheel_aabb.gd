extends SceneTree
func _process(_d: float) -> bool:
	for id in ["wheel_biplane_spoke", "wheel_biplane_disc", "wheel_spitfire", "wheel", "wheel_retract"]:
		if not PartCatalog.has_model(id):
			print(id, ": kein glb"); continue
		var ps: Resource = load("res://models/" + id + ".glb")
		var inst: Node = (ps as PackedScene).instantiate()
		get_root().add_child(inst)
		var lo := Vector3.INF; var hi := -Vector3.INF
		var stack: Array = [inst]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				var ab := mi.get_aabb()
				for i in 8:
					var c := ab.position + Vector3(ab.size.x*(1.0 if i&1 else 0.0), ab.size.y*(1.0 if i&2 else 0.0), ab.size.z*(1.0 if i&4 else 0.0))
					var w: Vector3 = mi.global_transform * c
					lo = lo.min(w); hi = hi.max(w)
			for ch in n.get_children(): stack.append(ch)
		print("%s: size=%v  center=%v" % [id, hi - lo, (lo + hi) * 0.5])
		inst.queue_free()
	quit(); return true
