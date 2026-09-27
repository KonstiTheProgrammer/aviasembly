## WAS KOSTET DIE CPU-SEITE EINES FLUGFRAMES?
##
## _bildzeit misst die GPU. Dieses Werkzeug misst das Gegenstueck: headless (kein Rendern)
## und mit --fixed-fps laeuft die Hauptschleife so schnell sie kann, die WANDZEIT zwischen
## zwei Frames ist also genau das, was Skripte + Physik + Streaming je Frame kosten.
## NICHT Performance.TIME_PROCESS nehmen: das ist das MAXIMUM der letzten Echtzeit-Sekunde
## und wird nur einmal je Sekunde erneuert — ein Median darueber ist bedeutungslos.
## Gemessen an mehreren Stellen im Geradeausflug mit 150 m/s, damit das Streamen mitlaeuft.
##
##   HOME=/tmp/avi_home Godot --headless --fixed-fps 60 --path . --script res://tools/_skriptzeit.gd
extends SceneTree

const STELLEN := [
	["Startbahn", Vector3(0, 60, 0), Vector3(0, 0, -1)],
	["Wald-Tiefland", Vector3(2600, 90, 1800), Vector3(1, 0, 0)],
	["Grossstadt", Vector3(-3000, 160, 2500), Vector3(0, 0, 1)],
	["Flakzone", Vector3(250, 250, -1900), Vector3(0, 0, -1)],
	["Hochtal", Vector3(-5000, 700, -8500), Vector3(-1, 0, -1)],
]
const WARM := 90
const PROBEN := 300

var m: Node = null
var f := 0
var idx := 0
var n := 0
var proc: Array = []
var _t_vor := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 1:
		return false
	if m == null:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
		return false
	if f == 20:
		m.call("_set_mode", 1)
		return false
	if f < 60:
		return false
	var fc = m.get("flight_ctrl")
	var ac: RigidBody3D = fc.get("aircraft")
	if n == 0:
		var st: Array = STELLEN[idx]
		var dir: Vector3 = (st[2] as Vector3).normalized()
		ac.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), st[1])
		ac.linear_velocity = dir * 150.0
		ac.angular_velocity = Vector3.ZERO
		fc.set("throttle", 0.8)
		fc.call("_reset_mouse_state")
		(m.get("terrain") as Node).call("build_now_around", ac.global_position, 1200.0)
		proc.clear()
	var jetzt := Time.get_ticks_usec()
	n += 1
	if n > WARM:
		proc.append(float(jetzt - _t_vor) / 1000.0)
	_t_vor = jetzt
	if n >= WARM + PROBEN:
		proc.sort()
		var summe := 0.0
		for v in proc:
			summe += v
		print("%-14s  Frame Median %5.2f ms  Mittel %5.2f  p95 %5.2f  max %6.2f   Knoten %d" % [
			STELLEN[idx][0], proc[int(proc.size() * 0.5)], summe / proc.size(),
			proc[int(proc.size() * 0.95)], proc[proc.size() - 1],
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		idx += 1
		n = 0
		if idx >= STELLEN.size():
			quit()
	return false
