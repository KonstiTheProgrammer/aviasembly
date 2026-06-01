## Headless-Test des Windkanal-Verdeckungs-Raycasts (temporär).
## Start: Godot --headless --path . --script res://tools/occlusion_test.gd
## Prüft: zwei Boxen hintereinander entlang +Z -> nur die VORDERE (windzugewandte)
## bekommt Exposition; die hintere liegt im Windschatten (~0). Eine breitere
## Heckbox schaut seitlich heraus und bekommt genau diesen Anteil.
## (SceneTree._process: return true = QUIT, false = weiter.)
extends SceneTree

var frame := 0
var a: StaticBody3D
var b: StaticBody3D
var ok1 := false
var ok2 := false
const LAYER := 2


func _make_box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.position = pos
	root.add_child(body)
	return body


# Exponierte Fläche je Body per Strahlengitter aus -Z (gleiche Logik wie im Editor).
func _expose(bodies: Array, w: float, h: float) -> Dictionary:
	var space := root.get_world_3d().direct_space_state
	var nx := 40
	var ny := 40
	var cell := (w / nx) * (h / ny)
	var out := {}
	for bd in bodies:
		out[bd] = 0.0
	var q := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO)
	q.collision_mask = LAYER
	for i in nx:
		var x: float = -w * 0.5 + (float(i) + 0.5) / nx * w
		for j in ny:
			var y: float = -h * 0.5 + (float(j) + 0.5) / ny * h
			q.from = Vector3(x, y, -10.0)
			q.to = Vector3(x, y, 10.0)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				continue
			var c = hit.get("collider")
			if c != null and out.has(c):
				out[c] += cell
	return out


func _process(_delta: float) -> bool:
	frame += 1
	match frame:
		1:
			print("=== Test 1: gleich große Boxen hintereinander (A vorne -Z, B hinten +Z) ===")
			a = _make_box(Vector3(0, 0, -1.5), Vector3(2, 2, 1))
			b = _make_box(Vector3(0, 0, 1.5), Vector3(2, 2, 1))
		5:
			var e1 := _expose([a, b], 2.0, 2.0)
			print("  A (vorne):  %.2f m²" % e1[a])
			print("  B (hinten): %.2f m²" % e1[b])
			ok1 = e1[a] > 3.5 and e1[b] < 0.1
			print("  -> ", "OK ✓ (Heck im Windschatten)" if ok1 else "FEHLER ✗")
			a.free()
			b.free()
		6:
			print("=== Test 2: schmale Box vorne (1x1), BREITE Box hinten (3x3) ===")
			a = _make_box(Vector3(0, 0, -1.5), Vector3(1, 1, 1))
			b = _make_box(Vector3(0, 0, 1.5), Vector3(3, 3, 1))
		10:
			var e2 := _expose([a, b], 3.0, 3.0)
			print("  A schmal vorne: %.2f m²  (erwartet ~1.0)" % e2[a])
			print("  B breit hinten: %.2f m²  (erwartet ~8.0 = 9 − 1 verdeckt)" % e2[b])
			ok2 = absf(e2[a] - 1.0) < 0.4 and e2[b] > 7.0
			print("  -> ", "OK ✓ (nur der herausschauende Rand zählt)" if ok2 else "FEHLER ✗")
			print("=== FERTIG: ", "ALLE TESTS BESTANDEN ✓" if (ok1 and ok2) else "TEST FEHLGESCHLAGEN ✗", " ===")
			quit()
			return true
	return false
