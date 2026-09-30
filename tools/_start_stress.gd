## STARTLAST: laedt Main, laesst ~20 s laufen (Kartenfaden, Schuerze, Chunk-Worker parallel)
## und beendet sich. Zum Aufspueren seltener Abstuerze beim Start: mehrfach parallel starten
## und die Exit-Codes zaehlen (134 = Absturz).
##   HOME=<test-home> Godot --headless --fixed-fps 60 --path . --script res://tools/_start_stress.gd
extends SceneTree
var f := 0
var t0 := 0
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		t0 = Time.get_ticks_msec()
		root.add_child(load("res://scenes/Main.tscn").instantiate())
	if f > 2:
		OS.delay_msec(10)
		if Time.get_ticks_msec() - t0 > 20000:
			print("STRESS ok")
			quit()
			return true
	return false
