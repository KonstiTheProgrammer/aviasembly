## PRUEFUNG DES STRASSENNETZES: Laengen, Bruecken (Lage/Laenge), groesste Einschnitte und
## Daemme, Steigungen, Haeuser je Dorf, Kosten von height_at mit/ohne Strassen, und ob
## irgendwo ein Baum auf der Fahrbahn steht (Chunks um drei Strassenpunkte gebaut).
##
##   HOME=<test-home> Godot --headless --path . --script res://tools/_strassen_check.gd
extends SceneTree
var m: Node
var f := 0


func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
	if f == 8:
		_pruefen()
		quit()
	return false


func _pruefen() -> void:
	var t: TerrainWorld = m.terrain
	var gesamt := 0.0
	var bruecken: Array = []
	var max_ein := 0.0
	var max_damm := 0.0
	var max_steig := 0.0
	var bei_ein := Vector2.ZERO
	var bei_damm := Vector2.ZERO
	t.set("_strassen_an", false)
	for pr in t.strassen_profile:
		var pts: PackedVector2Array = pr[0]
		var hh: PackedFloat32Array = pr[1]
		var br: PackedByteArray = pr[2]
		var i := 0
		while i < pts.size():
			if i > 0:
				gesamt += pts[i].distance_to(pts[i - 1])
				max_steig = maxf(max_steig, absf(hh[i] - hh[i - 1]) / maxf(pts[i].distance_to(pts[i - 1]), 1.0))
			var g := t.height_at(pts[i].x, pts[i].y)
			if br[i] == 0:
				if g - hh[i] > max_ein:
					max_ein = g - hh[i]
					bei_ein = pts[i]
				if hh[i] - g > max_damm:
					max_damm = hh[i] - g
					bei_damm = pts[i]
			i += 1
		i = 0
		while i < br.size():
			if br[i] == 1:
				var a := i
				while i < br.size() and br[i] == 1:
					i += 1
				bruecken.append([pts[a], pts[i - 1].distance_to(pts[a]) + 20.0, hh[a]])
			i += 1
	# Profil um den hoechsten Damm ausgeben (Gelaende ohne Strassen, Fahrbahn, Flussnaehe)
	for pr in t.strassen_profile:
		var pts: PackedVector2Array = pr[0]
		var hh: PackedFloat32Array = pr[1]
		var idx := -1
		for i in pts.size():
			if pts[i].distance_to(bei_damm) < 1.0:
				idx = i
		if idx < 0:
			continue
		for i in range(maxi(idx - 12, 0), mini(idx + 12, pts.size()), 2):
			var fl: Vector4 = t._fluss_naechst(pts[i].x, pts[i].y)
			print("  DAMM-PROFIL %3d (%.0f, %.0f) Gelaende %.1f  Fahrbahn %.1f  Fluss %.0f m  br %d" % [i,
				pts[i].x, pts[i].y, t.height_at(pts[i].x, pts[i].y), hh[i], fl.x, (pr[2] as PackedByteArray)[i]])
	t.set("_strassen_an", true)
	print("STRASSEN %d Strassen, %.1f km, max. Steigung %.1f %%" % [t.strassen_profile.size(),
		gesamt / 1000.0, max_steig * 100.0])
	print("STRASSEN tiefster Einschnitt %.1f m bei (%.0f, %.0f), hoechster Damm %.1f m bei (%.0f, %.0f)"
		% [max_ein, bei_ein.x, bei_ein.y, max_damm, bei_damm.x, bei_damm.y])
	print("STRASSEN %d Bruecken:" % bruecken.size())
	for b in bruecken:
		print("  Bruecke bei (%.0f, %.0f), %.0f m, Fahrbahn %.0f m" % [b[0].x, b[0].y, b[1], b[2]])
	# Dorfhoehen (nur lesen — Zonen zu veraendern, waehrend der Kartenfaden liest, liess das
	# Werkzeug abstuerzen)
	for z in m.get("_dorf_zonen"):
		var zp: Vector3 = z["pos"]
		print("  ZONE (%.0f, %.0f) y %.1f" % [zp.x, zp.z, float(z["y"])])
	# Haeuser je Dorf
	for d in StrassenDaten.DOERFER:
		var n: Node = m.fly_world.get_node_or_null("Dorf_" + String(d[0]))
		var z := 0
		if n != null:
			for c in n.get_children():
				if c is MultiMeshInstance3D and not String(c.name).ends_with("_HD"):
					z += (c as MultiMeshInstance3D).multimesh.instance_count
		print("DORF %-12s %2d Haeuser" % [d[0], z])
	# Gebaute Sichtteile
	var ls: Node = m.fly_world.get_node_or_null("Landstrassen")
	var baender := 0
	var bruecken_n := 0
	var koerper := 0
	if ls != null:
		for c in ls.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).material_override is StandardMaterial3D:
				bruecken_n += 1
			elif c is MeshInstance3D:
				baender += 1
			elif c is StaticBody3D:
				koerper += 1
		var erstes: MeshInstance3D = null
		for c in ls.get_children():
			if c is MeshInstance3D:
				erstes = c
				break
		if erstes != null:
			print("  erstes Band: Lage ", erstes.global_position, " AABB ", erstes.get_aabb(), " Flaechen ",
				erstes.mesh.get_surface_count() if erstes.mesh != null else -1)
	print("STRASSEN Sichtteile: %d Baender, %d Brueckenbauten, %d Kollisionskoerper" % [baender, bruecken_n, koerper])
	# Kosten von height_at: an Strassenpunkten, daneben, und weit weg
	var proben: Array[Vector2] = []
	for pr in t.strassen_profile:
		var pts: PackedVector2Array = pr[0]
		for i in range(0, pts.size(), 7):
			proben.append(pts[i] + Vector2(13.0, 7.0))
	for an in [false, true]:
		t.set("_strassen_an", an)
		var t0 := Time.get_ticks_usec()
		for p in proben:
			t.height_at(p.x, p.y)
		print("STRASSEN height_at nah an Strassen (%s): %.1f us" % ["mit" if an else "ohne",
			float(Time.get_ticks_usec() - t0) / float(proben.size())])
	# RASTER und EINSCHNITT: jeder Fahrbahnpunkt muss seine Strasse finden, und das Gelaende
	# darf an Mitte und Raendern nicht ueber dem Band liegen. (Die erste Fassung hatte ein
	# leeres Raster — und die Baumpruefung unten fragte strasse_abstand, das dann immer INF
	# lieferte: "0 Baeume auf der Fahrbahn" war wertlos.)
	var nicht_gefunden := 0
	var ueber := 0
	var proben_n := 0
	for pr in t.strassen_profile:
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
				proben_n += 1
				if t.strasse_abstand(p.x, p.y) > w + 0.5:
					nicht_gefunden += 1
				if t.height_at(p.x, p.y) > hh[i] + 0.05:
					ueber += 1
	print("STRASSEN Raster: %d Eintraege; Fahrbahnproben ohne Strasse %d, Gelaende ueber Band %d von %d" % [
		t._st_seg.size(), nicht_gefunden, ueber, proben_n])
	# Baeume auf der Fahrbahn? Chunks um drei Strassenpunkte bauen und zaehlen.
	var zu_nah := 0
	var geprueft := 0
	var pr0: Array = t.strassen_profile[t.strassen_profile.size() / 2]
	var pts0: PackedVector2Array = pr0[0]
	for q in [pts0[pts0.size() / 4], pts0[pts0.size() / 2], pts0[pts0.size() * 3 / 4]]:
		var key := Vector2i(floori(q.x / TerrainWorld.CHUNK), floori(q.y / TerrainWorld.CHUNK))
		var dat: Dictionary = t._make_chunk_data(key)
		for art in dat["flora"]:
			for xf in dat["flora"][art]:
				var o: Vector3 = (xf as Transform3D).origin
				geprueft += 1
				# Brute Force gegen die Profile statt strasse_abstand (das haengt am Raster)
				for prb in t.strassen_profile:
					var pb: PackedVector2Array = prb[0]
					for j in range(0, pb.size() - 1):
						var ab := pb[j + 1] - pb[j]
						var tt := clampf((Vector2(o.x, o.z) - pb[j]).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
						if Vector2(o.x, o.z).distance_to(pb[j] + ab * tt) < TerrainWorld.STRASSE_B_HAUPT + 1.0:
							zu_nah += 1
	print("STRASSEN Baeume auf der Fahrbahn: %d von %d geprueften" % [zu_nah, geprueft])
