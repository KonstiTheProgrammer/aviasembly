## ABNAHME-PRUEFUNG (nur lesend): Zellendaten der Designs, gegen die gemessen wird.
## Zweck: das G-Limit der Messlatte (0.92 x Strukturlimit) ist nur pruefbar, wenn die
## Fluegelkapazitaet der jeweiligen Zelle bekannt ist. mf_speed.gd faehrt mig15.json,
## mf_design.gd/mf_track.gd das Spieler-Design.
extends SceneTree

var fc: FlightController
var frame := 0

func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		return false
	if frame == 2:
		var bc := BuildController.new()
		root.add_child(bc)
		fc = FlightController.new()
		root.add_child(fc)
		return false
	for pfad in ["res://designs/mig15.json", "user://aircraft_design.json"]:
		var d := _laden(pfad)
		if d.is_empty():
			print("%-34s NICHT LADBAR" % pfad)
			continue
		fc.build_from_design(d)
		var ac := fc.aircraft
		var cap: float = ac.wing_capacity / (ac.mass * 9.81)
		print("%-34s masse=%6.0f kg  wingcap=%5.2f g  0.92x=%5.2f g" % [pfad, ac.mass, cap, 0.92 * cap])
	quit()
	return true

func _laden(pfad: String) -> Array:
	var f := FileAccess.open(pfad, FileAccess.READ)
	if f == null:
		return []
	var j = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(j) != TYPE_ARRAY:
		return []
	var out: Array = []
	for it in j:
		var x = it["xform"]
		var xf := Transform3D(Basis(Vector3(x[0],x[1],x[2]), Vector3(x[3],x[4],x[5]), Vector3(x[6],x[7],x[8])), Vector3(x[9],x[10],x[11]))
		var c = it["color"]
		var sc = it["scale"]
		out.append({"id": it["id"], "xform": xf, "color": Color(c[0],c[1],c[2],c[3]), "scale": Vector3(sc[0],sc[1],sc[2]), "taper": it.get("taper",-1.0), "taper_front": it.get("taper_front",-1.0)})
	return out
