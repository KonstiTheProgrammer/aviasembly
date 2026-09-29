## WAS KOSTET DAS NACHFUEHREN DER WASSERTIEFE? (TerrainWorld._tiefe_hochladen)
##
## Im Fenster, nicht headless: headless ist ImageTexture.update ein Leerlauf. Fliegt 25 s
## geradeaus mit 170 m/s (Flugzeug je Frame versetzt, das Streaming laeuft mit) und
## meldet Zahl und Dauer der Uploads sowie den Anteil an der Frame-Wandzeit.
##
## HOME=<test-home> Godot --path . --script res://tools/_tiefe_upload_zeit.gd
extends SceneTree

var m: Node
var f := 0
var t_start := 0
var pos := Vector3(0, 300, 0)
var frames := 0
var wand := PackedFloat32Array()
var t_last := 0


func _process(d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		get_root().add_child(m)
		return false
	if f == 30:
		m._set_mode(1)
		return false
	if f < 200:
		return false
	if f == 200:
		m.terrain.profil_an = true
		m.terrain.profil = {}
		t_start = Time.get_ticks_msec()
		t_last = Time.get_ticks_usec()
	var ac = m.flight_ctrl.aircraft
	pos += Vector3(0.6, 0, -0.8) * 170.0 * (1.0 / 60.0)
	if is_instance_valid(ac):
		ac.global_position = pos
		ac.linear_velocity = Vector3(0.6, 0, -0.8) * 170.0
	var jetzt := Time.get_ticks_usec()
	wand.append(float(jetzt - t_last) / 1000.0)
	t_last = jetzt
	frames += 1
	if Time.get_ticks_msec() - t_start > 25000:
		var p: Dictionary = m.terrain.profil
		var n := float(p.get("tiefe_upload_n", 0.0))
		var us := float(p.get("tiefe_upload", 0.0))
		wand.sort()
		print("TIEFE_UPLOAD %d Uploads in %d Frames, je Upload %.3f ms, je Frame %.3f ms (Median-Frame %.2f ms)"
			% [int(n), frames, us / 1000.0 / maxf(n, 1.0), us / 1000.0 / float(frames),
				wand[wand.size() / 2]])
		quit()
		return true
	return false
