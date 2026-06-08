## Lädt ein Vorlagen-Design und gibt compute_stats() aus (Flugbarkeits-Check).
## Godot --headless --path . --script res://tools/stats_check.gd -- <id>
extends SceneTree
var frame := 0
func _process(_d: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	var ua := OS.get_cmdline_user_args()
	var id := ua[0] if ua.size() >= 1 and ua[0] != "" else "mig15"
	var f := FileAccess.open("res://designs/%s.json" % id, FileAccess.READ)
	if f == null:
		print("FEHLER: kein Design ", id); quit(); return true
	var arr = JSON.parse_string(f.get_as_text()); f.close()
	var design: Array = []
	for it in arr:
		var a = it.get("xform", [])
		var xf := Transform3D()
		if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 12:
			xf = Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]),
				Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))
		var c = it.get("color", [0, 0, 0, 0])
		var col := Color(c[0], c[1], c[2], c[3]) if typeof(c) == TYPE_ARRAY and (c as Array).size() >= 4 else Color(0, 0, 0, 0)
		var sc = it.get("scale", [1, 1, 1])
		var scl := Vector3(sc[0], sc[1], sc[2]) if typeof(sc) == TYPE_ARRAY and (sc as Array).size() >= 3 else Vector3.ONE
		design.append({"id": it.get("id", ""), "xform": xf, "color": col, "scale": scl,
			"taper": it.get("taper", -1.0), "taper_front": it.get("taper_front", -1.0)})
	var bc := BuildController.new()
	root.add_child(bc)
	bc.load_design(design)
	var s := bc.compute_stats()
	print("== %s ==" % id)
	print("  Teile=%d  Masse=%.0f kg  schwebend=%d" % [s["parts"], s["mass"], bc.floating_count()])
	print("  TW(vorwärts)=%.2f  up_tw=%.2f  Schub=%.0f N  thrust_offset=%.3f m" % [
		s["tw"], s["up_tw"], s["thrust"], s["thrust_offset"]])
	print("  Flügelfläche=%.2f  max_G=%.1f  hat_Flügel=%s  hat_Fahrwerk=%s  Überlast=%s" % [
		s["area"], s["max_g"], s["has_wings"], s["has_gear"], s["gear_overload"]])
	var com: Vector3 = s["com"]; var col: Vector3 = s["col"]
	print("  COM.z=%.2f  COL.z=%.2f  d(stab=COL.z-COM.z)=%.2f" % [com.z, col.z, col.z - com.z])
	quit()
	return true
