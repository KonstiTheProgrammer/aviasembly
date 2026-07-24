## Zaehlt headless, was CityBuilder wirklich in die Welt gesetzt hat.
extends SceneTree
var f := 0
var m: Node
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var ps: PackedScene = load("res://scenes/Main.tscn")
		m = ps.instantiate()
		get_root().add_child(m)
		return false
	if f == 25:
		var txt := "has_lib=%s meshes=%d\n" % [CityBuilder.has_lib(), CityBuilder._meshes.size()]
		var ges := 0
		for n in m.fly_world.get_children():
			var typen := 0
			var inst := 0
			for c in n.get_children():
				var mmi := c as MultiMeshInstance3D
				if mmi != null and mmi.multimesh != null:
					typen += 1
					inst += mmi.multimesh.instance_count
			if typen > 0:
				txt += "%-28s %2d Typen %3d Gebaeude\n" % [n.name, typen, inst]
				ges += inst
		txt += "GESAMT %d Gebaeude\n" % ges
		var fh := FileAccess.open("user://city_count.txt", FileAccess.WRITE)
		fh.store_string(txt)
		fh.close()
		print(txt)
		quit()
	return false
