## Diagnose: welche Obergrenze bindet den Instructor wirklich?
## Vergleicht _auth_rates() (Steuerflaechen-Schaetzung), die Feel-Tabellen und das
## G-Budget w_gcap. Gemessen: auth.x bindet und deckelt die Kurvenrate weit unter
## das, was die Zelle physisch kann.
## Start: godot --headless --path . --script res://tools/_mf_auth.gd
extends SceneTree
var fc: FlightController
var frame := 0
func _process(_d: float) -> bool:
	frame += 1
	if frame == 1: return false
	if frame == 2:
		var bc := BuildController.new(); root.add_child(bc)
		fc = FlightController.new(); root.add_child(fc)
		var f := FileAccess.open("user://aircraft_design.json", FileAccess.READ)
		var arr = JSON.parse_string(f.get_as_text()); f.close()
		var design: Array = []
		for it in arr:
			var a = it["xform"]
			var xf := Transform3D(Basis(Vector3(a[0],a[1],a[2]),Vector3(a[3],a[4],a[5]),Vector3(a[6],a[7],a[8])), Vector3(a[9],a[10],a[11]))
			var c = it.get("color",[0,0,0,0]); var sc = it.get("scale",[1,1,1])
			design.append({"id": it["id"], "xform": xf, "color": Color(c[0],c[1],c[2],c[3]), "scale": Vector3(sc[0],sc[1],sc[2]), "taper": it.get("taper",-1.0), "taper_front": it.get("taper_front",-1.0)})
		fc.build_from_design(design)
		fc.set_active(true)
		var ac := fc.aircraft
		ac.global_transform = Transform3D(Basis(), Vector3(0, 4000, 0))
		ac.linear_velocity = Vector3(0,0,-160)
		return false
	var ac2 := fc.aircraft
	if frame == 60:
		ac2.linear_velocity = Vector3(0,0,-160)
	if frame == 90:
		var au: Vector3 = fc._auth_rates()
		print("v=%.0f pitch_area=%.3f yaw_area=%.3f roll_area=%.3f" % [ac2.airspeed, ac2.pitch_area, ac2.yaw_area, ac2.roll_area])
		print("auth = %.3f / %.3f / %.3f rad/s  (x0.85 -> %.3f / %.3f / %.3f)" % [au.x, au.y, au.z, au.x*0.85, au.y*0.85, au.z*0.85])
		print("PITCH_RATE_TAB@v=%.2f  ROLL_TAB@v=%.2f" % [fc._tab(ac2.airspeed, FlightController.PITCH_RATE_TAB), fc._tab(ac2.airspeed, FlightController.ROLL_RATE_TAB)])
		var g_lim: float = clampf(ac2.wing_capacity / maxf(ac2.mass*9.81,1.0), 3.0, 14.0)
		var n_turn: float = 0.75*g_lim
		print("g_lim=%.2f n_turn=%.2f w_gcap=%.3f rad/s (%.1f d/s)" % [g_lim, n_turn, 9.81*sqrt(n_turn*n_turn-1.0)/ac2.airspeed, rad_to_deg(9.81*sqrt(n_turn*n_turn-1.0)/ac2.airspeed)])
		quit(); return true
	return false
