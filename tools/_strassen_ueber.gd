## Diagnose: an den Stellen, wo _strassen_check "Gelaende ueber dem Band" meldet — welche
## Strassen liegen dort in der Naehe, und auf welcher Hoehe? (Einmuendungen, Kreuzungen?)
##   HOME=<test-home> Godot --headless --fixed-fps 60 --path . --script res://tools/_strassen_ueber.gd
extends SceneTree
var f := 0
var m: Node = null
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
	if f == 10:
		var t: TerrainWorld = m.terrain
		var stellen: Array = []
		for pi in t.strassen_profile.size():
			var pr: Array = t.strassen_profile[pi]
			var pts: PackedVector2Array = pr[0]
			var hh: PackedFloat32Array = pr[1]
			var br: PackedByteArray = pr[2]
			var w: float = pr[3]
			for i in range(1, pts.size() - 1):
				if br[i] == 1:
					continue
				var d := (pts[i + 1] - pts[i - 1]).normalized()
				var q := Vector2(-d.y, d.x)
				for sgn: float in [-1.0, 0.0, 1.0]:
					var p := pts[i] + q * w * sgn
					var h := t.height_at(p.x, p.y)
					if h > hh[i] + 0.05:
						stellen.append([p, h, hh[i], pi, i, sgn])
		print("STELLEN ", stellen.size())
		for s: Array in stellen:
			var p: Vector2 = s[0]
			var sn: Vector4 = t._strasse_naechst(p.x, p.y)
			print("(%d, %d) Gelaende %.2f, Band %.2f (Strasse %d Punkt %d Seite %+d)  naechste: Abstand %.1f Hoehe %.2f Halbbreite %.1f Bruecke %.1f" % [
				p.x, p.y, s[1], s[2], s[3], s[4], int(s[5]), sn.x, sn.y, sn.z, sn.w])
			for pj in t.strassen_profile.size():
				var pr2: Array = t.strassen_profile[pj]
				var pts2: PackedVector2Array = pr2[0]
				var hh2: PackedFloat32Array = pr2[1]
				var best := INF
				var bh := 0.0
				for j in pts2.size():
					var dd := pts2[j].distance_to(p)
					if dd < best:
						best = dd
						bh = hh2[j]
				if best < 60.0:
					print("     Strasse %d: naechster Punkt %.1f m, Hoehe %.2f, Halbbreite %.1f" % [pj, best, bh, float(pr2[3])])
		quit()
	return false
