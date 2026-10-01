## HAFENSTADT-PRUEFUNG (headless): Gelaende (Stadtflaeche eben, Kaikante, Wasser vor Kai und
## Piers, Statueninsel), Bauplan (Anzahl je Typ, keine Ueberschneidung der Haeuser, kein Haus
## auf einer Strasse — unabhaengig vom Plan per Brute Force nachgerechnet) und die gebauten
## Knoten. Urteilszeile "HAFENSTADT OK" / "HAFENSTADT FEHLER".
##   HOME=<test-home> Godot --headless --path . --script res://tools/_hafenstadt_check.gd
extends SceneTree
var f := 0
var m: Node
var _fehler := 0

func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		m = load("res://scenes/Main.tscn").instantiate()
		root.add_child(m)
	if f == 6:
		var fehler := 0
		var tw: TerrainWorld = m.terrain
		var mi := Hafenstadt.MITTE
		# --- Gelaende ---
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var schief := 0
		for i in 400:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * (Hafenstadt.R_FLACH - 6.0)
			var l := Vector2(cos(a), sin(a)) * r
			if l.x > Hafenstadt.KAI_X - 2.0:
				continue
			if absf(tw.height_at(mi.x + l.x, mi.z + l.y) - Hafenstadt.STADT_Y) > 0.05:
				schief += 1
		print("Stadtflaeche: %d von 400 Proben nicht auf %.1f m" % [schief, Hafenstadt.STADT_Y])
		fehler += schief
		var nass := 0
		var trocken := 0
		var z := -Hafenstadt.KAI_HALB
		while z <= Hafenstadt.KAI_HALB:
			for vor in [Hafenstadt.KAI_VOR + 2.0, 40.0, 120.0, 220.0]:
				var h := tw.height_at(mi.x + Hafenstadt.KAI_X + float(vor), mi.z + z)
				if h < TerrainWorld.SEA_Y - 2.5:
					nass += 1
				else:
					trocken += 1
			z += 26.0
		print("Hafenbecken: %d Proben tief genug, %d zu flach/trocken" % [nass, trocken])
		fehler += trocken
		for zug in [Hafenstadt.MOLE_SUED, Hafenstadt.MOLE_NORD]:
			for p in zug:
				var h := tw.height_at(mi.x + (p as Vector2).x, mi.z + (p as Vector2).y)
				if (p as Vector2).x > Hafenstadt.KAI_X + 20.0 and h > TerrainWorld.SEA_Y - 1.0:
					print("  Molenpunkt ", p, " steht auf Land (", h, ")")
					fehler += 1
		var ins := Hafenstadt.insel_welt()
		var hi := tw.height_at(ins.x, ins.z)
		var ring_nass := 0
		for k in 16:
			var a := TAU * float(k) / 16.0
			if tw.height_at(ins.x + cos(a) * 140.0, ins.z + sin(a) * 140.0) < TerrainWorld.SEA_Y - 2.0:
				ring_nass += 1
		print("Statueninsel: Hoehe %.2f (Soll %.2f), Wasser ringsum %d/16" % [hi, Hafenstadt.INSEL_Y, ring_nass])
		if absf(hi - Hafenstadt.INSEL_Y) > 0.05 or ring_nass < 16:
			fehler += 1
		# --- Bauplan ---
		CityBuilder.has_lib()
		var frei: Array = []
		var plan := Hafenstadt.plan(frei)
		var je := {}
		for e in plan:
			je[e["typ"]] = int(je.get(e["typ"], 0)) + 1
		var ks := je.keys()
		ks.sort()
		var zeile := ""
		for k in ks:
			zeile += "%s %d  " % [String(k).replace("Haus_", ""), je[k]]
		print("Bauplan: %d Bauten — %s" % [plan.size(), zeile])
		# Grundrisse aus den ECHTEN Netzen (nicht aus den Planmassen) und gegeneinander pruefen
		var rects: Array[Rect2] = []
		for e in plan:
			var mesh: Mesh = CityBuilder._meshes.get(e["typ"])
			if mesh == null:
				print("  Typ fehlt: ", e["typ"])
				fehler += 1
				continue
			var ab := mesh.get_aabb()
			var lo := Vector2(INF, INF)
			var hh := Vector2(-INF, -INF)
			var b := Basis(Vector3.UP, float(e["yaw"]))
			for ex in [ab.position.x, ab.end.x]:
				for ez in [ab.position.z, ab.end.z]:
					var q: Vector3 = b * Vector3(ex, 0.0, ez)
					lo = lo.min(Vector2(q.x, q.z))
					hh = hh.max(Vector2(q.x, q.z))
			var pos: Vector2 = e["pos"]
			rects.append(Rect2(pos + lo, hh - lo))
		var ueber := 0
		for i in rects.size():
			if (plan[i]["pos"] as Vector2).length() > Hafenstadt.R_FLACH:
				continue                       # Hanghaeuser stehen frei, schraeg gedreht
			for j in range(i + 1, rects.size()):
				if rects[i].grow(-0.6).intersects(rects[j].grow(-0.6)):
					ueber += 1
					if ueber <= 6:
						print("  Ueberschneidung: ", plan[i]["typ"], plan[i]["pos"], " / ", plan[j]["typ"], plan[j]["pos"])
		var auf_strasse := 0
		for i in rects.size():
			if (plan[i]["pos"] as Vector2).length() > Hafenstadt.R_FLACH:
				continue
			for sg in Hafenstadt.strassen():
				var a: float = sg[0]
				var hb: float = float(sg[4]) * 0.5
				var band := Rect2(Vector2(a - hb, float(sg[1])), Vector2(hb * 2.0, float(sg[2]) - float(sg[1]))) \
					if sg[3] else Rect2(Vector2(float(sg[1]), a - hb), Vector2(float(sg[2]) - float(sg[1]), hb * 2.0))
				if band.intersects(rects[i]):
					auf_strasse += 1
					if auf_strasse <= 6:
						print("  auf der Strasse: ", plan[i]["typ"], plan[i]["pos"], " Achse ", a)
					break
		print("Haeuser: %d Ueberschneidungen, %d auf einer Strasse" % [ueber, auf_strasse])
		fehler += ueber + auf_strasse
		# --- gebaute Knoten ---
		var hs: Node = (m.get("fly_world") as Node).get_node_or_null("Hafenstadt")
		if hs == null:
			print("Knoten Hafenstadt fehlt")
			fehler += 1
		else:
			var inst := 0
			var mm_n := 0
			var tris := 0
			for n in hs.find_children("*", "MultiMeshInstance3D", true, false):
				var mmi := n as MultiMeshInstance3D
				mm_n += 1
				if not String(mmi.name).ends_with("_HD"):
					inst += mmi.multimesh.instance_count
			for n in hs.find_children("*", "MeshInstance3D", true, false):
				var me := (n as MeshInstance3D).mesh
				if me != null and me.get_surface_count() > 0:
					var arr := me.surface_get_arrays(0)
					var vv: Variant = arr[Mesh.ARRAY_VERTEX]
					if vv != null:
						@warning_ignore("integer_division")
						tris += (vv as PackedVector3Array).size() / 3
			var koll := 0
			for n in hs.find_children("*", "CollisionShape3D", true, false):
				koll += 1
			print("Gebaut: %d MultiMeshes, %d Instanzen (Haeuser, Statue, Baeume), %d Dreiecke in Kai/Schiffen/Pflaster, %d Kollisionskoerper"
				% [mm_n, inst, tris, koll])
			if hs.get_node_or_null("Freiheitsstatue") == null:
				print("Freiheitsstatue fehlt")
				fehler += 1
		# --- Anschluss ans Landstrassennetz: an jedem Ortsausgang beginnt eine Landstrasse, und
		# ihr anderes Ende liegt auf einer Strasse des alten Netzes (StrassenDaten) ---
		for auftrag in Hafenstadt.anschluesse():
			var start: Vector2 = auftrag[0]
			var gefunden := false
			for st in StrassenZusatz.STRASSEN:
				var sp: Array = st[1]
				if (sp[0] as Vector2).distance_to(start) > 1.5:
					continue
				gefunden = true
				var ende: Vector2 = sp[sp.size() - 1]
				var nah := INF
				for alt in StrassenDaten.STRASSEN:
					var ap: Array = alt[1]
					for k in range(ap.size() - 1):
						nah = minf(nah, Geometry2D.get_closest_point_to_segment(ende, ap[k], ap[k + 1]).distance_to(ende))
				var lang := 0.0
				for k in range(1, sp.size()):
					lang += (sp[k] as Vector2).distance_to(sp[k - 1])
				print("Anschluss ab %s: %.1f km, Ende %s liegt %.0f m neben dem alten Netz %s" % [
					start, lang / 1000.0, ende, nah, "ok" if nah < 60.0 else "NICHT VERBUNDEN"])
				if nah >= 60.0:
					fehler += 1
				# das Stadtnetz reicht bis genau an den Anfang der Landstrasse
				var am_netz := false
				for kp in Hafenstadt.netz()["p"]:
					if ((kp as Vector2) + Vector2(mi.x, mi.z)).distance_to(start) < 0.5:
						am_netz = true
				if not am_netz:
					print("  Stadtnetz endet nicht am Anschlusspunkt ", start)
					fehler += 1
			if not gefunden:
				print("Anschluss ab %s: KEINE Landstrasse (tools/_dorf_planer.gd -- anschluss laufen lassen)" % start)
				fehler += 1
		# Hanghaeuser nicht auf einer Landstrasse (wie Hafenstadt.bauen filtert)
		var hang_auf := 0
		var hk: Node = (m.get("fly_world") as Node).get_node_or_null("Hafenstadt/Freihafen")
		if hk != null:
			for n in hk.get_children():
				var mmi := n as MultiMeshInstance3D
				if mmi == null or String(mmi.name).ends_with("_HD"):
					continue
				for k in mmi.multimesh.instance_count:
					var o := mmi.multimesh.get_instance_transform(k).origin
					if tw.strasse_abstand(mi.x + o.x, mi.z + o.z) < 12.0:
						hang_auf += 1
		print("Haeuser auf einer Landstrasse: %d" % hang_auf)
		fehler += hang_auf
		_fehler = fehler
	if f == 24:
		# --- Kollision (braucht ein paar Physikschritte): Strahl von oben auf Kai, Pier, Mole,
		# Uferweg der Insel und auf die Statue (Kopf und Fackelarm) ---
		var raum := (m as Node3D).get_world_3d().direct_space_state
		var mi2 := Hafenstadt.MITTE
		var ins2 := Hafenstadt.insel_welt()
		var b2 := Basis(Vector3.UP, Hafenstadt.STATUE_YAW)
		var ms := Hafenstadt.STATUE_MASS
		var soll := [
			["Kaimauer", mi2 + Vector3(Hafenstadt.KAI_X + 6.0, 0, 200.0), Hafenstadt.STADT_Y + 0.42],
			["Mittelpier", mi2 + Vector3(Hafenstadt.KAI_X + 120.0, 0, -40.0), Hafenstadt.STADT_Y + 0.42],
			["Suedmole", mi2 + Vector3(600.0, 0, 435.0), Hafenstadt.STADT_Y + 0.42],
			["Uferweg Insel", ins2 + Vector3(Hafenstadt.INSEL_UFER - 8.0, 0, 0), Hafenstadt.INSEL_Y + 0.3],
			["Statue Kopf", ins2, Hafenstadt.INSEL_Y + 83.0 * ms],
			["Fackelarm", ins2 + b2 * Vector3(-4.8 * ms, 0, 0.6 * ms), Hafenstadt.INSEL_Y + 93.5 * ms],
		]
		for e in soll:
			var p: Vector3 = e[1]
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 400.0, p.z), Vector3(p.x, -40.0, p.z), 1)
			var t := raum.intersect_ray(q)
			var y: float = (t["position"] as Vector3).y if not t.is_empty() else -999.0
			var ok := absf(y - float(e[2])) < 1.0
			print("Kollision %-14s y %7.2f (Soll %7.2f) %s" % [e[0], y, float(e[2]), "ok" if ok else "FEHLT"])
			if not ok:
				_fehler += 1
		print("HAFENSTADT OK" if _fehler == 0 else "HAFENSTADT FEHLER (%d)" % _fehler)
		quit()
	return false
