extends SceneTree
var n := 0
var t0 := 0.0
func _process(delta: float) -> bool:
	if n == 0:
		t0 = Time.get_ticks_msec()
	n += 1
	if n >= 600:
		print("600 frames in %.2f s wall -> %.0f fps, mean delta %.4f" % [(Time.get_ticks_msec()-t0)/1000.0, 600.0/maxf((Time.get_ticks_msec()-t0)/1000.0,0.001), delta])
		quit()
		return true
	return false
