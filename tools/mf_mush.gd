## MUSH-Test (WT-Verhalten unter Stall-Speed): bei 22 m/s steil ziehen wollen ->
## der AoA-Limiter hält das Flugzeug am Limit, die Nase SACKT unter den Marker
## (Mush), kein Stall/Trudeln/Salto.
## Gates: max aoa < STALL_A (nie über den Abriss!), vert-Restfehler >= 0.08 rad (Nase unterm
## Marker), Stall-Flag < 20 % der Frames, maxW < 3, Höhe nach 10 s > 150 m.
## Start: Godot --headless --path . --script res://tools/mf_mush.gd
extends SceneTree
var fc: FlightController
var frame := 0
var t := 0.0
var aoa_max := 0.0
var stall_frames := 0
var total_frames := 0
var max_w := 0.0
var vert_min := 99.0
func _process(delta: float) -> bool:
	frame += 1
	if frame == 1: return false
	if frame == 2:
		var bc := BuildController.new(); root.add_child(bc)
		fc = FlightController.new(); root.add_child(fc)
		var f := FileAccess.open("res://designs/mig15.json", FileAccess.READ)
		var arr = JSON.parse_string(f.get_as_text()); f.close()
		var design: Array = []
		for it in arr:
			var a = it["xform"]
			var xf := Transform3D(Basis(Vector3(a[0],a[1],a[2]),Vector3(a[3],a[4],a[5]),Vector3(a[6],a[7],a[8])), Vector3(a[9],a[10],a[11]))
			var c = it.get("color",[0,0,0,0]); var sc = it.get("scale",[1,1,1])
			design.append({"id": it["id"], "xform": xf, "color": Color(c[0],c[1],c[2],c[3]), "scale": Vector3(sc[0],sc[1],sc[2]), "taper": it.get("taper",-1.0), "taper_front": it.get("taper_front",-1.0)})
		fc.build_from_design(design)
		fc.set_active(true)
		fc.mouse_fly = true
		var ac := fc.aircraft
		ac.global_transform = Transform3D(Basis(), Vector3(0, 300, 0))
		ac.linear_velocity = Vector3(0, 0, -22.0)
		fc.look_pitch = 0.5         # will steil hoch — kann er aber nicht halten
		fc._aim_cmd = -ac.global_transform.basis.z
		return false
	var ac2 := fc.aircraft
	fc.throttle = 0.35
	ac2.throttle = 0.35
	t += delta
	total_frames += 1
	aoa_max = maxf(aoa_max, absf(ac2.aoa_signed))
	if ac2.stall:
		stall_frames += 1
	max_w = maxf(max_w, ac2.angular_velocity.length())
	if t > 2.0:
		var e: Vector3 = ac2.global_transform.basis.transposed() * fc._aim_dir()
		vert_min = minf(vert_min, atan2(e.y, sqrt(e.x * e.x + e.z * e.z)))
	if t > 10.0:
		# Gate = "nie über den Stall-AoA": der Rest-AoA beim Mushen kommt vom SINKEN
		# (Physik), nicht vom Kommando — entscheidend ist, dass der Abriss nie kommt.
		var ok := aoa_max < 0.27 and vert_min >= 0.08 \
			and float(stall_frames) / maxf(total_frames, 1) < 0.2 and max_w < 3.0 \
			and ac2.altitude > 150.0
		print("aoaMax=%.3f (Limit %.3f)  vertRest=%.2f  stall%%=%.0f  maxW=%.2f  alt=%.0f" % [
			aoa_max, fc.AOA_MAX, vert_min, 100.0 * stall_frames / maxf(total_frames, 1), max_w, ac2.altitude])
		print("==> %s" % ("MUSH-TEST BESTANDEN ✓" if ok else "MUSH-TEST FEHLGESCHLAGEN ✗"))
		quit(0 if ok else 1)
		return true
	return false
