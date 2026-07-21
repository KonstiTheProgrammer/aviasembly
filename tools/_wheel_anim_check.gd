## Prueft die drei animierten Fahrwerks-glbs: AnimationPlayer? "retract" abspielbar?
## Bewegt sich der Pivot wirklich? (Anfang vs. Ende der Animation vergleichen)
extends SceneTree
func _process(_d: float) -> bool:
	for id in ["wheel_biplane_spoke", "wheel_biplane_disc", "wheel_spitfire"]:
		var ps: Resource = load("res://models/" + id + ".glb")
		if ps == null:
			print(id, ": LADEFEHLER"); continue
		var inst: Node = (ps as PackedScene).instantiate()
		get_root().add_child(inst)
		var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap == null:
			print(id, ": KEIN AnimationPlayer!"); continue
		var anims := ap.get_animation_list()
		var piv := inst.find_child("Pivot_*", true, false) as Node3D
		var r0: Vector3 = piv.rotation_degrees if piv else Vector3.INF
		var ok := false
		if anims.has("retract"):
			var a := ap.get_animation("retract")
			ap.play("retract")
			ap.seek(a.length, true)
			var r1: Vector3 = piv.rotation_degrees if piv else Vector3.INF
			ok = piv != null and (r1 - r0).length() > 45.0
			print("%s: Animationen=%s  Laenge=%.2fs  Pivot %v -> %v  BEWEGT=%s"
				% [id, anims, a.length, r0, r1, ok])
		else:
			print(id, ": 'retract' FEHLT, Animationen=", anims)
	quit(); return true
