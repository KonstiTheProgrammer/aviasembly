class_name Flussleben
extends RefCounted
## LEBEN AM FLUSS (2026-10, Nutzer: „steck mehr Liebe in die Fluesse"). Alles, was an und auf
## den Fluessen steht, nachdem TerrainWorld Bett, Ufer und Wasserband gebaut hat:
##   * GISCHT am Fuss jedes Absturzes (TerrainWorld STUFE_*, rv["faelle"]), GPU-Partikel;
##   * FELSBROCKEN im Wildbach (steile Abschnitte) und an den Kanten der Faelle;
##   * SCHILF an ruhigen Ufern im Tiefland, SEEROSEN in stillen Buchten vor den Sandbaenken;
##   * REIHER auf den Sandbaenken, ENTENFAMILIEN, die im Kreis paddeln;
##   * BOOTSSTEGE mit Ruderboot, Bootsschuppen, Laterne und Angler, wo eine Strasse nahe ist;
##   * eine MUEHLE mit drehendem Wasserrad und ein Holzsteg am Muehlbach.
## Die Lage am Ufer rechnet `_ufer` mit denselben Zahlen wie TerrainWorld._river_carve
## (Wasserlinie d0, Ende der Bank e) — wer dort die UFER_*-Werte aendert, aendert sie hier mit.
## Bewegung (Wind, Schaukeln, Kreisen, Muehlrad) steckt in den Shadern, kein Knoten tickt.
## Instanzen liegen je KACHEL (km) in eigenen MultiMeshes, damit die Sichtweite greift.

const KACHEL := 1000.0
const TIEFLAND_BIS := 30.0           # Wasserhoehe, bis zu der Schilf, Rosen, Enten wohnen
const RUHIG_BIS := 0.006             # Gefaelle, bis zu dem das Wasser ruhig genug ist
const WILD_AB := 0.012               # Gefaelle, ab dem Steine im Bach liegen

const SCHILF_SICHT := 520.0
const ROSEN_SICHT := 360.0
const STEINE_SICHT := 1400.0
const TIERE_SICHT := 650.0
const STEG_SICHT := 1500.0
const GISCHT_SICHT := 1800.0


## Vor dem ersten Chunk (Main, direkt nach strassen_fertigstellen): wo Stege und Muehle
## stehen — und dort Lichtungen ins Gelaende setzen, damit kein Baum durch die Haeuser waechst.
static func planen(terrain: TerrainWorld) -> Dictionary:
	var stege: Array = []
	for rv: Dictionary in terrain.rivers:
		var pts: PackedVector3Array = rv["pts"]
		var formen: PackedFloat32Array = rv["form"]
		if pts.size() < 3:
			continue
		var l := 0.0
		var naechster := 1500.0
		for i in range(1, pts.size() - 1):
			l += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
			if l < naechster or formen[i] < 0.5 or pts[i].y > TIEFLAND_BIS \
					or pts[i].y <= TerrainWorld.SEA_Y + 0.4 or _gefaelle(pts, i) > RUHIG_BIS:
				continue
			for seite: float in [1.0, -1.0]:
				var u := _ufer(rv, i, seite)
				# STEG: wo eine Strasse in der Naehe ist (Leute kommen hin), nicht unter der
				# Bruecke, auf der Seite ohne Bank (tiefes Wasser am Ufer).
				if float(u["gb"]) >= 0.1 or l < naechster:
					continue
				var c: Vector3 = u["c"]
				var sa := terrain.strasse_abstand(c.x, c.z)
				if sa > 60.0 and sa < 900.0:
					naechster = l + 2200.0 + float(hash(i) % 1400)
					stege.append(u)
					var m: Vector3 = c + (u["n"] as Vector3) * (float(u["d0"]) + 9.0)
					terrain.lichtung_setzen(m.x, m.z, 22.0)
	var muehle := _muehle_ort(terrain)
	if not muehle.is_empty():
		var u2: Dictionary = muehle["u"]
		var m2: Vector3 = (u2["c"] as Vector3) + (u2["n"] as Vector3) * (float(u2["d0"]) + 6.0)
		terrain.lichtung_setzen(m2.x, m2.z, 20.0)
	return {"stege": stege, "muehle": muehle}


static func bauen(welt: Node3D, terrain: TerrainWorld, plan: Dictionary = {}) -> void:
	var t0 := Time.get_ticks_msec()
	var wurzel := Node3D.new()
	wurzel.name = "Flussleben"
	wurzel.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	welt.add_child(wurzel)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5F1055
	var steine := {}
	var schilf := {}
	var rosen := {}
	var bluete := {}
	var reiher := {}
	var enten := {}
	var stege: Array = plan.get("stege", [])
	var n_gischt := 0
	var n_vorhang := 0
	for rv: Dictionary in terrain.rivers:
		var pts: PackedVector3Array = rv["pts"]
		if pts.size() < 3:
			continue
		n_gischt += _gischt(wurzel, rv)
		n_vorhang += _vorhaenge(wurzel, rv, terrain)
		_steine_sammeln(rv, terrain, rng, steine)
		_ufer_sammeln(rv, terrain, rng, schilf, rosen, bluete, reiher, enten)
	var fels: Mesh = terrain.get("_mesh_rock")
	var fels_mat: Material = terrain.get("_flora_mat")
	var n_steine := _kacheln(wurzel, "Steine", fels, fels_mat, steine, STEINE_SICHT, true)
	var n_schilf := _kacheln(wurzel, "Schilf", _schilf_netz(), _schilf_mat(), schilf, SCHILF_SICHT, false)
	var lm := _mat(1.0)
	var n_rosen := _kacheln(wurzel, "Seerosen", _rosen_netz(false), lm, rosen, ROSEN_SICHT, false)
	n_rosen += _kacheln(wurzel, "Seerosen", _rosen_netz(true), lm, bluete, ROSEN_SICHT, false)
	var n_reiher := _kacheln(wurzel, "Reiher", _reiher_netz(), _mat(0.0), reiher, TIERE_SICHT, true)
	var em := _mat(0.6)
	em.set_shader_parameter("kreisen", -0.16)
	em.set_shader_parameter("drehpunkt", Vector3(ENTEN_R, 0.0, 0.0))
	var n_enten := _kacheln(wurzel, "Enten", _enten_netz(), em, enten, TIERE_SICHT, false)
	var n_stege := _stege_bauen(wurzel, terrain, stege, rng)
	var muehle := _muehle(wurzel, terrain, plan.get("muehle", {}))
	if OS.get_environment("FLUSSLEBEN_ZEIGEN") != "":
		for u: Dictionary in stege:
			print("  STEG bei %s Richtung Land %s" % [u["c"], u["n"]])
		for k: Vector2i in reiher:
			for x: Transform3D in reiher[k]:
				print("  REIHER bei %s" % x.origin)
		for k: Vector2i in enten:
			print("  ENTEN Kachel %s: %s" % [k, (enten[k][0] as Transform3D).origin])
		for k: Vector2i in bluete:
			print("  SEEROSE Kachel %s: %s" % [k, (bluete[k][0] as Transform3D).origin])
		for n2 in wurzel.get_children():
			if n2.name.begins_with("Muehle") or n2.name.begins_with("Gischt"):
				print("  %s bei %s" % [n2.name, (n2 as Node3D).global_position])
	print("Flussleben: %d Faelle, %d Gischt, %d Steine, %d Schilf, %d Seerosen, %d Reiher, %d Entenfamilien, %d Stege%s, %d ms"
		% [n_vorhang, n_gischt, n_steine, n_schilf, n_rosen, n_reiher, n_enten, n_stege,
		", Muehle" if muehle else "", Time.get_ticks_msec() - t0])


# --- Geometrie des Ufers ---------------------------------------------------------------

## Querlage am Stuetzpunkt i auf der Seite `seite` (+1 = Normalenseite (-dz, dx), -1 = die
## andere): Mitte, Laufrichtung, Normale nach aussen, Breite, Wasserlinie d0, Ende der Bank e,
## Bankstaerke gb, Prallhang go — wie TerrainWorld._river_carve.
static func _ufer(rv: Dictionary, i: int, seite: float) -> Dictionary:
	var pts: PackedVector3Array = rv["pts"]
	var n := pts.size()
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, n - 1)]
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var nor := Vector3(-dir.z, 0.0, dir.x) * seite
	var bg: float = (rv["bogen"] as PackedFloat32Array)[i] * seite
	var gi := maxf(bg, 0.0)
	var go := maxf(-bg, 0.0)
	var gb := smoothstep(0.15, 0.6, gi)
	var w: float = (rv["breite"] as PackedFloat32Array)[i]
	return {"c": pts[i], "dir": dir, "n": nor, "w": w,
		"d0": w * (1.0 - TerrainWorld.UFER_BANK_HINEIN * gb),
		"e": w * (1.0 + TerrainWorld.UFER_BANK_WEIT * gb), "gb": gb, "go": go}


## Gefaelle am Punkt i OHNE Abstuerze (wie das Wasserband).
static func _gefaelle(pts: PackedVector3Array, i: int) -> float:
	var s := 0.0
	var k := 0.0
	for j in [i - 1, i]:
		if j < 0 or j >= pts.size() - 1:
			continue
		var lh := Vector2(pts[j + 1].x - pts[j].x, pts[j + 1].z - pts[j].z).length()
		if lh < TerrainWorld.STUFE_L * 2.0:
			continue
		s += (pts[j].y - pts[j + 1].y) / maxf(lh, 0.01)
		k += 1.0
	return s / k if k > 0.0 else 0.0


static func _in_kachel(d: Dictionary, p: Vector3, x: Transform3D) -> void:
	var key := Vector2i(int(floorf(p.x / KACHEL)), int(floorf(p.z / KACHEL)))
	if not d.has(key):
		d[key] = []
	(d[key] as Array).append(x)


## Je Kachel eine MultiMeshInstance3D mit Sichtweite. Liefert die Zahl der Instanzen.
static func _kacheln(wurzel: Node3D, name: String, mesh: Mesh, mat: Material, d: Dictionary,
		sicht: float, schatten: bool) -> int:
	if mesh == null:
		return 0
	var summe := 0
	for key: Vector2i in d:
		var liste: Array = d[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = liste.size()
		var r := RandomNumberGenerator.new()
		r.seed = hash(key)
		for k in liste.size():
			mm.set_instance_transform(k, liste[k])
			mm.set_instance_custom_data(k, Color(r.randf(), r.randf(), r.randf(), 1.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [name, key.x, key.y]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.visibility_range_end = sicht
		mmi.visibility_range_end_margin = sicht * 0.1
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if schatten \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wurzel.add_child(mmi)
		summe += liste.size()
	return summe


# --- Gischt -------------------------------------------------------------------------------

static func _gischt(wurzel: Node3D, rv: Dictionary) -> int:
	var pts: PackedVector3Array = rv["pts"]
	var br: PackedFloat32Array = rv["breite"]
	var anz := 0
	for fl in rv.get("faelle", []):
		var unten: int = int(fl[1])
		var oben: int = int(fl[0])
		var hoch: float = float(fl[2])
		if hoch < 3.0 or unten >= pts.size():
			continue
		var p := pts[unten]
		var dir := Vector3(p.x - pts[oben].x, 0.0, p.z - pts[oben].z).normalized()
		var w: float = br[unten]
		var gp := GPUParticles3D.new()
		gp.name = "Gischt"
		var gross := clampf(hoch / 10.0, 0.6, 3.0)
		gp.amount = int(clampf(14.0 + hoch * 2.0, 18.0, 110.0))
		gp.lifetime = 3.2
		gp.preprocess = 3.2
		gp.randomness = 0.4
		gp.fixed_fps = 30
		gp.local_coords = false
		gp.visibility_aabb = AABB(Vector3(-w * 1.5 - 10.0, -4.0, -w * 1.5 - 10.0),
			Vector3(w * 3.0 + 20.0, hoch + 16.0, w * 3.0 + 20.0))
		gp.visibility_range_end = GISCHT_SICHT
		gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(w * 0.7 + 1.0, 0.8 + hoch * 0.10, 2.5 + hoch * 0.10)
		pm.direction = Vector3(dir.x * 0.6, 1.0, dir.z * 0.6)
		pm.spread = 40.0
		pm.initial_velocity_min = 0.8 + hoch * 0.06
		pm.initial_velocity_max = 2.2 + hoch * 0.14
		pm.gravity = Vector3(0, -0.35, 0)
		pm.damping_min = 0.4
		pm.damping_max = 0.9
		pm.scale_min = 2.6 * gross
		pm.scale_max = 5.5 * gross
		var sk := Curve.new()
		sk.add_point(Vector2(0.0, 0.35))
		sk.add_point(Vector2(0.5, 0.85))
		sk.add_point(Vector2(1.0, 1.0))
		var skt := CurveTexture.new()
		skt.curve = sk
		pm.scale_curve = skt
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 0.0))
		gr.set_color(1, Color(1, 1, 1, 0.0))
		gr.add_point(0.15, Color(1, 1, 1, 0.42))
		gr.add_point(0.55, Color(1, 1, 1, 0.24))
		var grt := GradientTexture1D.new()
		grt.gradient = gr
		pm.color_ramp = grt
		gp.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/gischt.gdshader")
		q.material = sm
		gp.draw_pass_1 = q
		wurzel.add_child(gp)
		gp.global_position = Vector3(p.x, p.y + 0.6, p.z) + dir * 1.5
		anz += 1
	return anz


# --- Wasserfall-Vorhaenge -----------------------------------------------------------------

## Je Absturz ein durchsichtiges Band (shaders/wasserfall.gdshader) ueber dem Wasserband:
## an kurzen Stufen im BOGEN ueber die Kante (Wurfparabel: waagerecht ~ Wurzel der Fallhoehe),
## an Waenden (rv["faelle"] mit langem Abschnitt) die Rampe entlang, eine Handbreit darueber.
## Leicht nach vorn gewoelbt und zum Fuss hin etwas schmaler. Ein Netz je Fluss.
static func _vorhaenge(wurzel: Node3D, rv: Dictionary, terrain: TerrainWorld) -> int:
	var pts: PackedVector3Array = rv["pts"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var anz := 0
	for fl in rv.get("faelle", []):
		var io: int = int(fl[0])
		var iu: int = int(fl[1])
		var hoch: float = float(fl[2])
		if hoch < 1.2 or iu >= pts.size():
			continue
		var a := pts[io]
		var b := pts[iu]
		var dh := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var lh := dh.length()
		var dir := dh / maxf(lh, 0.001)
		var nor := Vector3(-dir.z, 0.0, dir.x)
		var ul := _ufer(rv, io, 1.0)
		var ur := _ufer(rv, io, -1.0)
		var wand := lh > TerrainWorld.STUFE_L * 2.0
		# An Waenden breiter als das Gerinne: das Wasser faechert sich ueber den Fels.
		var halb := minf(float(ul["d0"]), float(ur["d0"])) * (1.25 if wand else 0.92)
		var zeilen := 8 if hoch > 6.0 else 5
		var vorher: Array = []
		var lauf := 0.0
		var p_alt := Vector3.ZERO
		var gesamt := 0.0
		# Laenge vorab (fuer den Fuss im Shader)
		var punkte: Array = []
		for k in zeilen + 1:
			var t := float(k) / float(zeilen)
			var p: Vector3
			# OBEN UND UNTEN UNTER DEM WASSER: die erste Zeile liegt knapp unter dem Spiegel
			# des oberen Beckens, die letzte unter dem des unteren — das undurchsichtige
			# Wasserband verdeckt so beide Kanten (vorher standen sie als gerade Linien da).
			if wand:
				# die Rampe entlang, 0,35 m ueber der Wasserflaeche (senkrecht zu ihr)
				var r_dir := (b - a).normalized()
				var auf := r_dir.cross(nor).normalized()
				if auf.y < 0.0:
					auf = -auf
				p = a.lerp(b, t) + Vector3(0, 0.15, 0) + auf * 0.35 * sin(t * PI)
				if k == 0:
					p = a - dir * 2.0 + Vector3(0, 0.02, 0)
				elif k == zeilen:
					p = b + dir * 2.0 - Vector3(0, 0.5, 0)
			else:
				p = a + dir * (lh * sqrt(t) + 0.25) + Vector3(0, 0.25 - hoch * t, 0)
				if k == 0:
					p = a - dir * 1.5 + Vector3(0, 0.02, 0)
				elif k == zeilen:
					p.y -= 0.6
			punkte.append(p)
			if k > 0:
				gesamt += p.distance_to(punkte[k - 1])
		for k in zeilen + 1:
			var t := float(k) / float(zeilen)
			var p: Vector3 = punkte[k]
			if k > 0:
				lauf += p.distance_to(p_alt)
			p_alt = p
			# an Waenden faechert der Fall nach unten auf, an Stufen zieht er sich etwas zusammen
			var hw := halb * ((1.0 + 0.45 * t) if wand else (1.0 - 0.10 * t))
			var bauch := dir * (0.35 + 0.02 * hoch) * sin(t * PI) * (0.0 if wand else 1.0)
			var reihe := [[p - nor * hw, -hw, lauf, hw], [p + bauch, 0.0, lauf, hw],
				[p + nor * hw, hw, lauf, hw]]
			if not vorher.is_empty():
				for s2 in 2:
					var q := [vorher[s2], reihe[s2], reihe[s2 + 1], vorher[s2 + 1]]
					for idx in [0, 1, 2, 0, 2, 3]:
						var e: Array = q[idx]
						st.set_uv(Vector2(float(e[1]), float(e[2])))
						st.set_uv2(Vector2(float(e[3]), gesamt))
						st.add_vertex(e[0])
			vorher = reihe
		anz += 1
	if anz == 0:
		return 0
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Wasserfaelle"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/wasserfall.gdshader")
	m.set_shader_parameter("wellen_tex", terrain.get("_wellen_tex"))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 6000.0
	wurzel.add_child(mi)
	return anz


# --- Steine im Wildbach ------------------------------------------------------------------

static func _steine_sammeln(rv: Dictionary, terrain: TerrainWorld, rng: RandomNumberGenerator,
		steine: Dictionary) -> void:
	var pts: PackedVector3Array = rv["pts"]
	var mesh: Mesh = terrain.get("_mesh_rock")
	if mesh == null:
		return
	var bb := mesh.get_aabb()
	var gr := maxf(bb.size.x, bb.size.z)
	var n := pts.size()
	# Felsen an den Kanten der Abstuerze: sie brechen die gerade Lippe und rahmen den Fall.
	for fl in rv.get("faelle", []):
		var oben: int = int(fl[0])
		var hoch: float = float(fl[2])
		if hoch < 2.0:
			continue
		for seite: float in [1.0, -1.0]:
			var u := _ufer(rv, oben, seite)
			var anz := 1 + int(hoch > 8.0) + rng.randi() % 2
			for k in anz:
				var d: float = float(u["d0"]) * rng.randf_range(0.55, 1.05)
				var vor := rng.randf_range(-2.5, 3.5)
				var p: Vector3 = (u["c"] as Vector3) + (u["n"] as Vector3) * d + (u["dir"] as Vector3) * vor
				var s := clampf(float(u["w"]) * 0.22, 0.9, 3.2) * rng.randf_range(0.7, 1.3)
				_stein(steine, p, (u["c"] as Vector3).y + s * rng.randf_range(0.15, 0.55), s, gr, bb, rng,
					terrain)
	# Im Bett steiler Abschnitte: Brocken, die aus dem Wasser ragen, und Geroell am Ufer.
	var l := 0.0
	var naechst := 0.0
	for i in range(1, n - 1):
		var lh := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		l += lh
		if l < naechst:
			continue
		var g := _gefaelle(pts, i)
		if g < WILD_AB:
			naechst = l + 40.0
			continue
		naechst = l + rng.randf_range(6.0, 14.0) / clampf(g * 8.0, 0.6, 1.6)
		var seite := 1.0 if rng.randf() < 0.5 else -1.0
		var u := _ufer(rv, i, seite)
		var t := rng.randf()
		var c: Vector3 = (u["c"] as Vector3).lerp(pts[i + 1], t * 0.5)
		var w: float = u["w"]
		var quer := rng.randf_range(0.0, 1.25)
		var p := c + (u["n"] as Vector3) * (w * quer)
		var s := clampf(w * 0.16, 0.5, 2.4) * rng.randf_range(0.6, 1.4)
		var top: float
		var wasser := -INF
		if quer < 0.9:
			top = c.y + s * rng.randf_range(-0.10, 0.45)      # im Wasser, ragt heraus
			wasser = c.y + 0.15                               # Spiegel des Wasserbands
		else:
			top = terrain.height_at(p.x, p.z) + s * rng.randf_range(0.25, 0.6)   # am Ufer
		_stein(steine, p, top, s, gr, bb, rng, terrain, wasser)


## Stein mit der Oberkante `top` — aber immer AUF dem Gelaende: haengt die Unterkante ueber dem
## Boden (vor der Lippe eines Falls liegt das Gelaende schon Meter tiefer, im Becken der Grund),
## sinkt er, bis sie ein Siebtel seiner Hoehe im tiefsten Punkt unter ihm steckt. Vorher
## schwebten 144 von 314 Brocken, an der Quellwand bis 18 m hoch. Mit `wasser` entfaellt ein
## Stein, der danach ganz unter dem Spiegel laege (man saehe ihn nicht).
static func _stein(steine: Dictionary, p: Vector3, top: float, s: float, gr: float, bb: AABB,
		rng: RandomNumberGenerator, terrain: TerrainWorld, wasser := -INF) -> void:
	var k := s / maxf(gr, 0.01)
	var bas := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
	bas = bas.scaled(Vector3(k, k * rng.randf_range(0.6, 0.95), k))
	var sy := bas.get_scale().y
	var y := top - bb.end.y * sy
	var boden := terrain.height_at(p.x, p.z)
	var r := s * 0.4
	for o: Vector2 in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		boden = minf(boden, terrain.height_at(p.x + o.x, p.z + o.y))
	var unten := y + bb.position.y * sy
	var soll := boden - bb.size.y * sy / 7.0
	if unten > soll:
		y -= unten - soll
	if y + bb.end.y * sy < wasser + 0.05:
		return
	_in_kachel(steine, p, Transform3D(bas, Vector3(p.x, y, p.z)))


# --- Ufer: Schilf, Seerosen, Reiher, Enten, Stege -------------------------------------------

static func _ufer_sammeln(rv: Dictionary, terrain: TerrainWorld, rng: RandomNumberGenerator,
		schilf: Dictionary, rosen: Dictionary, bluete: Dictionary, reiher: Dictionary,
		enten: Dictionary) -> void:
	var pts: PackedVector3Array = rv["pts"]
	var formen: PackedFloat32Array = rv["form"]
	var n := pts.size()
	var rausch := FastNoiseLite.new()
	rausch.seed = 4711 + n
	rausch.frequency = 1.0 / 140.0
	var l := 0.0
	var naechster_reiher := 400.0
	var naechste_ente := 300.0
	for i in range(1, n - 1):
		var lh := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
		var l0 := l
		l += lh
		if formen[i] < 0.5 or pts[i].y > TIEFLAND_BIS or pts[i].y <= TerrainWorld.SEA_Y + 0.4:
			continue
		var g := _gefaelle(pts, i)
		if g > RUHIG_BIS:
			continue
		for seite: float in [1.0, -1.0]:
			var u := _ufer(rv, i, seite)
			var c: Vector3 = u["c"]
			var dir: Vector3 = u["dir"]
			var nor: Vector3 = u["n"]
			var d0: float = u["d0"]
			var go: float = u["go"]
			var gb: float = u["gb"]
			# SCHILF in Flecken (Rauschen laengs des Laufs), nicht am Prallhang.
			var s := 0.0
			while s < lh:
				var lauf := l0 + s
				var fleck := rausch.get_noise_2d(lauf, seite * 37.0)
				var ds := rng.randf_range(0.9, 1.5)
				if fleck > 0.22 and go < 0.35:
					# SCHILFGUERTEL: dicht in zwei, drei Reihen, nicht einzelne Halme
					var q := d0 + rng.randf_range(-3.0, 1.2)
					var p := c + dir * (s - lh * 0.5) + nor * q
					if terrain.strasse_abstand(p.x, p.z) > 22.0:
						var h := terrain.height_at(p.x, p.z)
						if h > c.y - 0.7 and h < c.y + 0.9:
							var k := rng.randf_range(0.75, 1.25)
							var bas := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k * rng.randf_range(0.85, 1.15), k))
							_in_kachel(schilf, p, Transform3D(bas, Vector3(p.x, h - 0.05, p.z)))
				# SEEROSEN in stillen Buchten vor der Bank (Gleithang) und in ruhigen Strecken.
				if fleck < -0.25 and g < 0.0035 and go < 0.2 and rng.randf() < 0.35:
					var q2 := d0 - rng.randf_range(1.0, 4.5)
					var p2 := c + dir * (s - lh * 0.5) + nor * q2
					var h2 := terrain.height_at(p2.x, p2.z)
					# Spiegel AN DER ROSE, nicht am Stuetzpunkt: ein halber Abschnitt weiter
					# liegt er schon Dezimeter tiefer (an der Klammbach-Muendung lagen Rosen
					# auf dem Trockenen).
					var fn := terrain._fluss_naechst(p2.x, p2.z)
					var wy: float = fn.y if fn.x < INF else c.y
					if wy - h2 > 0.25 and wy - h2 < 2.2:
						var k2 := rng.randf_range(0.8, 1.3)
						var x2 := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k2, 1.0, k2)),
							Vector3(p2.x, wy + 0.17, p2.z))
						_in_kachel(bluete if rng.randf() < 0.18 else rosen, p2, x2)
				s += ds
			# REIHER auf der Sandbank (Innenseite), Blick zum Wasser.
			if gb > 0.3 and l > naechster_reiher and rng.randf() < 0.6:
				naechster_reiher = l + rng.randf_range(700.0, 1600.0)
				# Die echte Wasserlinie wandert (TerrainWorld UFER_WANDERN), d0 ist nur die
				# geplante: vom Wunschplatz landwaerts suchen, bis der Grund hoechstens knoechel-
				# tief unter dem Spiegel liegt. Vorher stand ein Reiher auf 1,8 m tiefem Wasser.
				var q3 := d0 + rng.randf_range(0.3, 1.6)
				var blick := (-nor).rotated(Vector3.UP, rng.randf_range(-0.9, 0.9))
				var wy3 := c.y + 0.15
				var p3 := c + nor * q3
				var h3 := terrain.height_at(p3.x, p3.z)
				while h3 < wy3 - 0.2 and q3 < float(u["e"]) + 6.0:
					q3 += 0.6
					p3 = c + nor * q3
					h3 = terrain.height_at(p3.x, p3.z)
				if h3 >= wy3 - 0.2 and h3 < wy3 + 1.2:
					var bas3 := Basis.looking_at(-blick, Vector3.UP)
					_in_kachel(reiher, p3, Transform3D(bas3, Vector3(p3.x, h3, p3.z)))
			# ENTEN: paddeln in ruhigem Wasser im Kreis (Drehpunkt im Netz, ENTEN_R).
			if l > naechste_ente and go < 0.3 and rng.randf() < 0.3:
				naechste_ente = l + rng.randf_range(700.0, 1600.0)
				# Der ganze Kreis muss Wasser sein — sonst zur Flussmitte ruecken (die echte
				# Wasserlinie wandert gegen die geplante d0), notfalls keine Familie hier.
				var q4 := maxf(d0 - ENTEN_R - 2.5, ENTEN_R + 1.0)
				var p4 := c + nor * q4
				var nass := false
				for _versuch in 4:
					p4 = c + nor * q4
					if _rundum_nass(terrain, p4, c.y + 0.15, ENTEN_R + 0.6):
						nass = true
						break
					q4 *= 0.55
				var bas4 := Basis(Vector3.UP, rng.randf() * TAU)
				if not nass:
					continue
				# Der Drehpunkt liegt im Netz bei (ENTEN_R, 0, 0): die Instanz so verschieben,
				# dass er auf p4 faellt.
				var o4 := Vector3(p4.x, c.y + 0.15, p4.z) - bas4 * Vector3(ENTEN_R, 0.0, 0.0)
				_in_kachel(enten, p4, Transform3D(bas4, o4))


## Liegt rund um p (Radius r) ueberall mindestens 0,25 m Wasser ueber dem Grund?
static func _rundum_nass(terrain: TerrainWorld, p: Vector3, spiegel: float, r: float) -> bool:
	for k in 12:
		var a := TAU * float(k) / 12.0
		if spiegel - terrain.height_at(p.x + cos(a) * r, p.z + sin(a) * r) < 0.25:
			return false
	return spiegel - terrain.height_at(p.x, p.z) >= 0.25


# --- Netze ----------------------------------------------------------------------------------

static func _mat(schwimmen: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/flussleben.gdshader")
	m.set_shader_parameter("schwimmen", schwimmen)
	return m


static func _schilf_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/schilf.gdshader")
	return m


static func _lin(c: Color) -> Color:
	return c.srgb_to_linear()


## Ein Dreieck, von aussen (Normale n) IM UHRZEIGERSINN gewickelt — so zeichnet Godot die
## Vorderseite (die erste Fassung hatte es andersherum: man sah in jedes Haus hinein).
static func _dreieck(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	var v := [[a, ca], [b, cb], [c, cc]]
	if (b - a).cross(c - a).dot(n) > 0.0:
		v = [[a, ca], [c, cc], [b, cb]]
	for e: Array in v:
		st.set_color(e[1])
		st.set_uv(Vector2.ZERO)
		st.set_normal(n)
		st.add_vertex(e[0])


## Ein Halm als gebogenes, spitz zulaufendes Band (UV.y = Hoehe 0..1 fuer den Wind).
static func _halm(st: SurfaceTool, fuss: Vector3, aus: Vector3, h: float, breit: float,
		c0: Color, c1: Color, c2: Color, seg := 3) -> void:
	var quer := aus.cross(Vector3.UP).normalized()
	if quer.length() < 0.1:
		quer = Vector3.RIGHT
	var vorher: Array = []
	for k in seg + 1:
		var t := float(k) / float(seg)
		var p := fuss + Vector3.UP * (h * t) + aus * (h * t * t)
		var b := breit * (1.0 - t * 0.92)
		var col := c0.lerp(c1, minf(t * 1.6, 1.0)) if t < 0.62 else c1.lerp(c2, (t - 0.62) / 0.38)
		var nrm := (aus.normalized() * 0.6 + Vector3.UP * 0.4).normalized()
		var paar := [[p - quer * b * 0.5, col, t, nrm], [p + quer * b * 0.5, col, t, nrm]]
		if not vorher.is_empty():
			for idx in [0, 1, 3, 0, 3, 2]:
				var e: Array = (vorher + paar)[idx]
				st.set_color(e[1])
				st.set_uv(Vector2(0.0, float(e[2])))
				st.set_normal(e[3])
				st.add_vertex(e[0])
		vorher = paar


static func _schilf_netz() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var c0 := _lin(Color(0.16, 0.27, 0.11))
	var c1 := _lin(Color(0.34, 0.50, 0.19))
	var c2 := _lin(Color(0.66, 0.64, 0.33))
	for b in 14:
		var a := TAU * float(b) / 14.0 + rng.randf_range(-0.3, 0.3)
		var r0 := rng.randf_range(0.0, 0.45)
		var fuss := Vector3(cos(a) * r0, 0.0, sin(a) * r0)
		var aus := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.10, 0.36)
		_halm(st, fuss, aus, rng.randf_range(1.2, 2.4), rng.randf_range(0.10, 0.16), c0, c1, c2)
	# Rohrkolben: duenner Stiel und ein brauner Kolben
	var braun := _lin(Color(0.36, 0.22, 0.12))
	for k in 3:
		var a2 := rng.randf() * TAU
		var fuss2 := Vector3(cos(a2), 0.0, sin(a2)) * rng.randf_range(0.05, 0.2)
		var h2 := rng.randf_range(1.7, 2.3)
		_halm(st, fuss2, Vector3(cos(a2), 0, sin(a2)) * 0.03, h2, 0.035, c0, c1, c1, 2)
		var oben := fuss2 + Vector3(cos(a2), 0, sin(a2)) * 0.03 * h2 + Vector3.UP * (h2 * 0.80)
		_saeule(st, oben, oben + Vector3.UP * 0.30, 0.045, 6, braun, h2 * 0.8 / 2.3)
	st.index()
	return st.commit()


## Senkrechte Saeule (n Seiten) von a nach b mit Radius r; uvy fuer den Wind.
static func _saeule(st: SurfaceTool, a: Vector3, b: Vector3, r: float, n: int, col: Color,
		uvy := 0.0) -> void:
	var achse := (b - a).normalized()
	var q1 := achse.cross(Vector3.FORWARD if absf(achse.y) > 0.9 else Vector3.UP).normalized()
	var q2 := achse.cross(q1).normalized()
	for k in n:
		var w0 := TAU * float(k) / float(n)
		var w1 := TAU * float(k + 1) / float(n)
		var o0 := q1 * cos(w0) * r + q2 * sin(w0) * r
		var o1 := q1 * cos(w1) * r + q2 * sin(w1) * r
		var nr := (o0 + o1).normalized()
		for v: Vector3 in [a + o0, b + o0, b + o1, a + o0, b + o1, a + o1]:
			st.set_color(col)
			st.set_uv(Vector2(0.0, uvy))
			st.set_normal(nr)
			st.add_vertex(v)


## Flache Scheibe (Seerosenblatt) mit Kerbe, Mitte `m`, Radius r.
static func _blatt(st: SurfaceTool, m: Vector3, r: float, dreh: float, col: Color, rand: Color) -> void:
	var n := 10
	for k in n:
		if k == 0:
			continue   # die Kerbe
		var w0 := dreh + TAU * float(k) / float(n)
		var w1 := dreh + TAU * float(k + 1) / float(n)
		var p0 := m + Vector3(cos(w0), 0.0, sin(w0)) * r
		var p1 := m + Vector3(cos(w1), 0.0, sin(w1)) * r
		_dreieck(st, m, p0, p1, Vector3.UP, col, rand, rand)


static func _rosen_netz(mit_bluete: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31 if mit_bluete else 13
	var gruen := [_lin(Color(0.22, 0.44, 0.15)), _lin(Color(0.30, 0.52, 0.18)), _lin(Color(0.18, 0.38, 0.17))]
	for k in 5:
		var a := rng.randf() * TAU
		var m := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, 0.9) + Vector3(0, 0.005 * k, 0)
		var c: Color = gruen[k % 3]
		_blatt(st, m, rng.randf_range(0.22, 0.42), rng.randf() * TAU, c, c.darkened(0.25))
	if mit_bluete:
		var weiss := _lin(Color(0.98, 0.95, 0.97))
		var rosa := _lin(Color(0.96, 0.70, 0.80))
		var gelb := _lin(Color(0.98, 0.82, 0.25))
		var m2 := Vector3(0.15, 0.05, 0.1)
		var farbe: Color = weiss if rng.randf() < 0.5 else rosa
		for lage in 2:
			for k in 7:
				var w := TAU * float(k) / 7.0 + float(lage) * 0.45
				var lang := 0.16 - 0.04 * float(lage)
				var spitze := m2 + Vector3(cos(w) * lang, 0.07 + 0.05 * float(lage), sin(w) * lang)
				var l0 := m2 + Vector3(cos(w - 0.35), 0.0, sin(w - 0.35)) * 0.03
				var l1 := m2 + Vector3(cos(w + 0.35), 0.0, sin(w + 0.35)) * 0.03
				var nr := (Vector3(cos(w), 1.4, sin(w))).normalized()
				var fb: Color = farbe if lage == 0 else farbe.lightened(0.15)
				_dreieck(st, l0, spitze, l1, nr, fb, fb, fb)
		_saeule(st, m2 + Vector3(0, 0.02, 0), m2 + Vector3(0, 0.09, 0), 0.035, 6, gelb)
	return st.commit()


## Ein Koerper aus Ringen (Rumpf, Hals): Ringe [Mitte, Radius quer, Radius hoch], n Seiten.
static func _koerper(st: SurfaceTool, ringe: Array, n: int, col: Color) -> void:
	for r in ringe.size() - 1:
		var a: Array = ringe[r]
		var b: Array = ringe[r + 1]
		var ma: Vector3 = a[0]
		var mb: Vector3 = b[0]
		var achse := (mb - ma).normalized()
		var q1 := achse.cross(Vector3.UP).normalized()
		if q1.length() < 0.1:
			q1 = Vector3.RIGHT
		var q2 := q1.cross(achse).normalized()
		for k in n:
			var w0 := TAU * float(k) / float(n)
			var w1 := TAU * float(k + 1) / float(n)
			var pa0: Vector3 = ma + q1 * cos(w0) * float(a[1]) + q2 * sin(w0) * float(a[2])
			var pa1: Vector3 = ma + q1 * cos(w1) * float(a[1]) + q2 * sin(w1) * float(a[2])
			var pb0: Vector3 = mb + q1 * cos(w0) * float(b[1]) + q2 * sin(w0) * float(b[2])
			var pb1: Vector3 = mb + q1 * cos(w1) * float(b[1]) + q2 * sin(w1) * float(b[2])
			var nr := (q1 * cos((w0 + w1) * 0.5) + q2 * sin((w0 + w1) * 0.5)).normalized()
			_dreieck(st, pa0, pb0, pb1, nr, col, col, col)
			_dreieck(st, pa0, pb1, pa1, nr, col, col, col)


## Graureiher, gut 1,5 m (stilisiert wie die Voegel der Welt), Blick nach -Z.
static func _reiher_netz() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grau := _lin(Color(0.55, 0.59, 0.64))
	var dunkel := _lin(Color(0.30, 0.33, 0.38))
	var weiss := _lin(Color(0.92, 0.93, 0.92))
	var gelb := _lin(Color(0.88, 0.70, 0.22))
	var bein := _lin(Color(0.55, 0.45, 0.25))
	# Rumpf schraeg, Schwanz nach hinten unten
	_koerper(st, [[Vector3(0, 0.98, 0.42), 0.02, 0.02], [Vector3(0, 1.02, 0.25), 0.14, 0.12],
		[Vector3(0, 1.10, 0.0), 0.17, 0.16], [Vector3(0, 1.20, -0.18), 0.12, 0.12],
		[Vector3(0, 1.26, -0.24), 0.05, 0.05]], 6, grau)
	# Fluegel als dunklere Decke oben
	_koerper(st, [[Vector3(0, 1.14, 0.36), 0.03, 0.02], [Vector3(0, 1.16, 0.12), 0.18, 0.10],
		[Vector3(0, 1.22, -0.12), 0.13, 0.08]], 6, dunkel)
	# S-Hals, weiss
	_koerper(st, [[Vector3(0, 1.24, -0.22), 0.05, 0.05], [Vector3(0, 1.36, -0.30), 0.045, 0.045],
		[Vector3(0, 1.46, -0.26), 0.04, 0.04], [Vector3(0, 1.56, -0.30), 0.04, 0.04],
		[Vector3(0, 1.62, -0.36), 0.05, 0.05], [Vector3(0, 1.64, -0.44), 0.03, 0.03]], 5, weiss)
	# Schnabel, Schopf
	_koerper(st, [[Vector3(0, 1.64, -0.43), 0.025, 0.025], [Vector3(0, 1.61, -0.66), 0.002, 0.002]], 4, gelb)
	_koerper(st, [[Vector3(0, 1.67, -0.38), 0.012, 0.012], [Vector3(0, 1.64, -0.18), 0.002, 0.002]], 3, dunkel)
	# Beine
	for x: float in [-0.06, 0.06]:
		_saeule(st, Vector3(x, 0.0, 0.0), Vector3(x, 0.98, 0.04), 0.014, 4, bein)
	st.index()
	return st.commit()


const ENTEN_R := 2.4   # Radius des Kreises, den die Familie paddelt (Drehpunkt im Netz)


## Entenfamilie: Mutter vorn, vier Kueken dahinter auf einem Kreisbogen um (ENTEN_R, 0, 0) —
## der Shader dreht das Netz um diesen Punkt, also schwimmen sie einander nach.
static func _enten_netz() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var braun := _lin(Color(0.52, 0.38, 0.24))
	var kopf := _lin(Color(0.42, 0.30, 0.18))
	var kueken := _lin(Color(0.86, 0.74, 0.32))
	var schnabel := _lin(Color(0.92, 0.58, 0.18))
	var mitte := Vector3(ENTEN_R, 0.0, 0.0)
	for k in 5:
		# Bogenwinkel: Mutter vorn (Bewegung um +Y gegen den Uhrzeiger -> Richtung -Z am
		# Punkt (0,0,0)), Kueken dahinter
		var a := float(k) * 0.42
		var pos := mitte + Vector3(-cos(a), 0.0, sin(a)) * ENTEN_R
		var vor := Vector3(-sin(a), 0.0, -cos(a))
		var s := 1.0 if k == 0 else 0.55
		var c: Color = braun if k == 0 else kueken
		var hinten := pos - vor * 0.22 * s
		var vorn := pos + vor * 0.20 * s
		_koerper(st, [[hinten + Vector3(0, 0.06 * s, 0), 0.04 * s, 0.03 * s],
			[pos - vor * 0.08 * s + Vector3(0, 0.08 * s, 0), 0.13 * s, 0.09 * s],
			[pos + vor * 0.08 * s + Vector3(0, 0.08 * s, 0), 0.12 * s, 0.08 * s],
			[vorn + Vector3(0, 0.08 * s, 0), 0.04 * s, 0.04 * s]], 6, c)
		var hk := pos + vor * 0.16 * s + Vector3(0, 0.20 * s, 0)
		_koerper(st, [[hk - Vector3(0, 0.06 * s, 0), 0.04 * s, 0.04 * s],
			[hk, 0.065 * s, 0.065 * s], [hk + Vector3(0, 0.05 * s, 0), 0.02 * s, 0.02 * s]], 6,
			kopf if k == 0 else c)
		_koerper(st, [[hk + vor * 0.05 * s, 0.025 * s, 0.015 * s], [hk + vor * 0.13 * s - Vector3(0, 0.01, 0), 0.01 * s, 0.006 * s]], 4, schnabel)
	st.index()
	return st.commit()


# --- Stege, Boote, Angler -----------------------------------------------------------------------

## Quader mit Basis b (Mitte m, Halbmasse h) — Flaechen selbst gewickelt.
static func _quader(st: SurfaceTool, m: Vector3, h: Vector3, b: Basis, col: Color, oben: Variant = null) -> void:
	var x := b.x * h.x
	var y := b.y * h.y
	var z := b.z * h.z
	var flaechen := [[y, x, z], [-y, z, x], [x, z, y], [-x, y, z], [z, y, x], [-z, x, y]]
	for f: Array in flaechen:
		var nn: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := m + nn
		var p0 := c - u - v
		var p1 := c + u - v
		var p2 := c + u + v
		var p3 := c - u + v
		var cc: Color = oben if (oben != null and nn.normalized().dot(Vector3.UP) > 0.7) else col
		var nrm := nn.normalized()
		_dreieck(st, p0, p1, p2, nrm, cc, cc, cc)
		_dreieck(st, p0, p2, p3, nrm, cc, cc, cc)


static func _stege_bauen(wurzel: Node3D, terrain: TerrainWorld, stege: Array,
		rng: RandomNumberGenerator) -> int:
	var anz := 0
	var holz := _lin(Color(0.55, 0.40, 0.26))
	var holz_hell := _lin(Color(0.66, 0.50, 0.33))
	var holz_dunkel := _lin(Color(0.33, 0.23, 0.15))
	var dach := _lin(Color(0.58, 0.24, 0.18))
	var weiss := _lin(Color(0.90, 0.88, 0.82))
	var blau := _lin(Color(0.22, 0.42, 0.62))
	var gruen := _lin(Color(0.26, 0.48, 0.30))
	for u: Dictionary in stege:
		var c: Vector3 = u["c"]
		var nor: Vector3 = u["n"]
		var d0: float = u["d0"]
		# Bezugssystem: Ursprung an der Wasserlinie, -Z zeigt ins Wasser (vom Ufer weg)
		var ursprung := c + nor * d0
		var b := Basis(Vector3.UP.cross(nor), Vector3.UP, nor)   # z = landwaerts, rechtshaendig
		var knoten := Node3D.new()
		knoten.name = "Bootssteg"
		wurzel.add_child(knoten)
		knoten.global_position = Vector3(ursprung.x, c.y, ursprung.z)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var deck_y := 0.85
		# Boden relativ zu c.y an einer Stelle im Steg-System (x quer, z landwaerts)
		var boden_bei := func(q: Vector3) -> float:
			var w := ursprung + b * q
			return terrain.height_at(w.x, w.z) - c.y
		# So weit ins Land beginnt der Steg — hoechstens 7 m, aber nur bis dorthin, wo die
		# Boeschung die Deckhoehe erreicht: mit festen 7 m steckte der Stegkopf an beiden Stegen
		# im Uferhang (Boden 0,1 bzw. 0,4 m ueber dem Deck).
		var land := 0.5
		while land < 7.0 and float(boden_bei.call(Vector3(0, 0, land + 0.5))) < deck_y - 0.10:
			land += 0.5
		land = maxf(land, 1.5)
		knoten.set_meta("steg_land", land)      # fuer tools/_flussleben_check.gd
		var lang := 11.0 + rng.randf_range(0.0, 4.0)
		var breit := 1.1
		# Laufbretter quer, abwechselnd hell/dunkel, mit Fugen
		var z := land
		var k := 0
		while z > -lang:
			var col := holz if k % 3 else holz_hell
			_quader(st, Vector3(0, deck_y, z - 0.16), Vector3(breit, 0.04, 0.14), Basis(), col)
			z -= 0.34
			k += 1
		# Laengstraeger und Pfaehle
		for sx: float in [-breit + 0.1, breit - 0.1]:
			_quader(st, Vector3(sx, deck_y - 0.1, (land - lang) * 0.5), Vector3(0.07, 0.07, (land + lang) * 0.5), Basis(), holz_dunkel)
			var pz := land - 0.4
			while pz > -lang - 0.1:
				var boden := terrain.height_at(ursprung.x + (b * Vector3(sx, 0, pz)).x, ursprung.z + (b * Vector3(sx, 0, pz)).z) - c.y
				var unten := minf(boden, -0.2) - 0.6
				_saeule(st, Vector3(sx, unten, pz), Vector3(sx, deck_y + (0.35 if pz < -lang + 0.6 else 0.0), pz), 0.09, 6, holz_dunkel)
				pz -= 2.6
		# Poller und eine Bank am Ende
		_quader(st, Vector3(-0.6, deck_y + 0.25, -lang + 0.5), Vector3(0.5, 0.05, 0.18), Basis(), holz_hell)
		_quader(st, Vector3(-0.6, deck_y + 0.12, -lang + 0.5), Vector3(0.45, 0.12, 0.05), Basis(), holz_dunkel)
		# Laterne am Stegkopf
		_saeule(st, Vector3(breit - 0.1, deck_y, land - 0.6), Vector3(breit - 0.1, deck_y + 2.4, land - 0.6), 0.05, 6, holz_dunkel)
		_quader(st, Vector3(breit - 0.1, deck_y + 2.5, land - 0.6), Vector3(0.12, 0.16, 0.12), Basis(), _lin(Color(1.0, 0.86, 0.55)))
		# BOOTSSCHUPPEN am Ufer: Holzwand, rotes Satteldach
		var sp := Vector3(-5.5, 0.0, land + 5.0)
		var sh := terrain.height_at(ursprung.x + (b * sp).x, ursprung.z + (b * sp).z) - c.y
		_quader(st, sp + Vector3(0, sh + 1.2, 0), Vector3(2.4, 1.5, 3.0), Basis(), holz)
		var dy := sh + 2.7
		for seite: float in [-1.0, 1.0]:
			var neig := Basis(Vector3(0, 0, 1), seite * -0.62)
			_quader(st, sp + Vector3(seite * 1.35, dy + 0.75, 0), Vector3(1.6, 0.06, 3.3), neig, dach)
		_quader(st, sp + Vector3(0, sh + 0.9, -3.02), Vector3(1.0, 0.9, 0.04), Basis(), holz_dunkel)  # Tor
		# Fass und zwei Kisten — jedes auf seinem eigenen Boden (vorher ein Bruchteil der
		# Schuppenhoehe: am Hang schwebten sie oder steckten im Boden)
		var fy: float = boden_bei.call(Vector3(1.6, 0, land + 1.2)) - 0.05
		_saeule(st, Vector3(1.6, fy, land + 1.2), Vector3(1.6, fy + 0.9, land + 1.2), 0.32, 8, holz_dunkel)
		var ky: float = boden_bei.call(Vector3(2.4, 0, land + 2.0)) - 0.05
		_quader(st, Vector3(2.4, ky + 0.3, land + 2.0), Vector3(0.3, 0.3, 0.3), Basis(Vector3.UP, 0.4), holz_hell)
		# Ein zweites Boot kieloben am Ufer
		var by: float = maxf(boden_bei.call(Vector3(-3.5, 0, land - 1.0)), 0.15)
		_boot(st, Vector3(-3.5, by + 0.35, land - 1.0), Basis(Vector3.UP, 0.3) * Basis(Vector3(0, 0, 1), PI), weiss, gruen, 0.9)
		# Angler auf der Bank, Rute uebers Wasser
		_angler(st, Vector3(-0.6, deck_y, -lang + 0.5), rng)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _mat(0.0)
		mi.visibility_range_end = STEG_SICHT
		knoten.add_child(mi)
		mi.basis = b
		# RUDERBOOT am Steg, schaukelt
		var st2 := SurfaceTool.new()
		st2.begin(Mesh.PRIMITIVE_TRIANGLES)
		_boot(st2, Vector3.ZERO, Basis(), weiss, blau if rng.randf() < 0.5 else gruen, 1.0)
		var boot := MeshInstance3D.new()
		boot.mesh = st2.commit()
		boot.material_override = _mat(1.0)
		boot.visibility_range_end = STEG_SICHT
		knoten.add_child(boot)
		boot.position = b * Vector3(breit + 1.2, 0.15, -lang * 0.6)
		boot.basis = b * Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.15, 0.15))
		anz += 1
	return anz


## Ruderboot (~4 m) laengs X, Kiel unten. Spant-Ringe als offene Schale + Duchten.
static func _boot(st: SurfaceTool, m: Vector3, b: Basis, innen: Color, aussen: Color, k: float) -> void:
	var halb := 2.0 * k
	var ringe: Array = []
	for i in 7:
		var t := float(i) / 6.0
		var x := lerpf(-halb, halb, t)
		var bw := (0.62 * (1.0 - pow(absf(t - 0.45) * 2.0, 2.2) * 0.85)) * k
		var tief := 0.42 * (1.0 - pow(absf(t - 0.5) * 2.0, 3.0) * 0.5) * k
		var spring := pow(absf(t - 0.5) * 2.0, 2.0) * 0.18 * k
		ringe.append([x, bw, tief, spring])
	for i in ringe.size() - 1:
		var r0: Array = ringe[i]
		var r1: Array = ringe[i + 1]
		# Profil je Ring: Bordwand links, Kiel, Bordwand rechts
		var pa := [Vector3(r0[0], 0.25 * k + float(r0[3]), -float(r0[1])), Vector3(r0[0], 0.25 * k - float(r0[2]), 0.0),
			Vector3(r0[0], 0.25 * k + float(r0[3]), float(r0[1]))]
		var pb := [Vector3(r1[0], 0.25 * k + float(r1[3]), -float(r1[1])), Vector3(r1[0], 0.25 * k - float(r1[2]), 0.0),
			Vector3(r1[0], 0.25 * k + float(r1[3]), float(r1[1]))]
		for s in 2:
			var q: Array[Vector3] = [pa[s], pb[s], pb[s + 1], pa[s + 1]]
			var nr: Vector3 = ((q[1] - q[0]).cross(q[3] - q[0])).normalized()
			var mitte: Vector3 = (q[0] + q[2]) * 0.5
			var raus: Vector3 = (mitte - Vector3(mitte.x, 0.6 * k, 0.0)).normalized()
			if nr.dot(raus) < 0.0:
				nr = -nr
			var w: Array[Vector3] = [m + b * q[0], m + b * q[1], m + b * q[2], m + b * q[3]]
			var nw := b * nr
			_dreieck(st, w[0], w[1], w[2], nw, aussen, aussen, aussen)
			_dreieck(st, w[0], w[2], w[3], nw, aussen, aussen, aussen)
			_dreieck(st, w[0], w[1], w[2], -nw, innen, innen, innen)
			_dreieck(st, w[0], w[2], w[3], -nw, innen, innen, innen)
	# Duchten (Sitzbaenke) und Ruder
	var holz := _lin(Color(0.60, 0.45, 0.30))
	for x: float in [-0.7 * k, 0.5 * k]:
		_quader(st, m + b * Vector3(x, 0.18 * k, 0), Vector3(0.12, 0.025, 0.5 * k), b, holz)
	for s: float in [-1.0, 1.0]:
		_quader(st, m + b * Vector3(-0.1 * k, 0.32 * k, s * 0.55 * k), Vector3(0.9 * k, 0.025, 0.05), b * Basis(Vector3.UP, s * 0.12), holz)


## Sitzender Angler mit Hut und Rute, Blick nach -Z (aufs Wasser).
static func _angler(st: SurfaceTool, sitz: Vector3, rng: RandomNumberGenerator) -> void:
	var jacke := _lin([Color(0.75, 0.30, 0.20), Color(0.30, 0.45, 0.65), Color(0.85, 0.65, 0.22)][rng.randi() % 3])
	var hose := _lin(Color(0.28, 0.30, 0.36))
	var haut := _lin(Color(0.93, 0.74, 0.60))
	var hut := _lin(Color(0.80, 0.72, 0.45))
	var p := sitz + Vector3(0, 0.30, 0)
	_quader(st, p + Vector3(0, 0.05, -0.18), Vector3(0.18, 0.08, 0.24), Basis(), hose)        # Oberschenkel
	_quader(st, p + Vector3(0, -0.28, -0.42), Vector3(0.16, 0.30, 0.08), Basis(), hose)       # Unterschenkel
	_quader(st, p + Vector3(0, 0.38, 0.02), Vector3(0.21, 0.30, 0.13), Basis(Vector3.RIGHT, -0.12), jacke)   # Rumpf
	_quader(st, p + Vector3(0, 0.80, -0.02), Vector3(0.11, 0.12, 0.11), Basis(), haut)        # Kopf
	_quader(st, p + Vector3(0, 0.94, -0.02), Vector3(0.20, 0.025, 0.20), Basis(), hut)
	_quader(st, p + Vector3(0, 1.00, -0.02), Vector3(0.10, 0.06, 0.10), Basis(), hut)
	_quader(st, p + Vector3(0.1, 0.42, -0.25), Vector3(0.06, 0.06, 0.20), Basis(), jacke)     # Arm
	var griff := p + Vector3(0.1, 0.42, -0.42)
	_saeule(st, griff, griff + Vector3(0.3, 1.6, -2.4), 0.015, 4, _lin(Color(0.25, 0.20, 0.15)))


# --- Muehle am Muehlbach --------------------------------------------------------------------

## Die Muehle steht am ersten Absturz des Muehlbachs zwischen 1,8 und 7 m Hoehe: Haus am Ufer,
## Rad daneben im Fall (dreht im Shader), dazu ein Holzsteg ueber den Bach etwas weiter unten.
static func _muehle_ort(terrain: TerrainWorld) -> Dictionary:
	var rv: Dictionary = {}
	for r: Dictionary in terrain.rivers:
		if String(r.get("name", "")) == "Muehlbach":
			rv = r
	if rv.is_empty():
		return {}
	var pts: PackedVector3Array = rv["pts"]
	for fl in rv.get("faelle", []):
		var hoch: float = float(fl[2])
		if hoch >= 1.8 and hoch <= 7.0 and int(fl[1]) > (pts.size() >> 2):
			return {"rv": rv, "fall": fl, "u": _ufer(rv, int(fl[0]), 1.0)}
	return {}


static func _muehle(wurzel: Node3D, terrain: TerrainWorld, ort: Dictionary) -> bool:
	if ort.is_empty():
		return false
	var rv: Dictionary = ort["rv"]
	var pts: PackedVector3Array = rv["pts"]
	var wahl: Array = ort["fall"]
	var unten: int = int(wahl[1])
	var hoch: float = float(wahl[2])
	var u: Dictionary = ort["u"]
	var c: Vector3 = u["c"]
	var dir: Vector3 = u["dir"]
	var nor: Vector3 = u["n"]
	var d0: float = u["d0"]
	var knoten := Node3D.new()
	knoten.name = "Muehle"
	wurzel.add_child(knoten)
	var fuss := pts[unten]
	knoten.global_position = Vector3(c.x, fuss.y, c.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stein := _lin(Color(0.62, 0.60, 0.55))
	var putz := _lin(Color(0.93, 0.88, 0.76))
	var balken := _lin(Color(0.38, 0.25, 0.16))
	var dach := _lin(Color(0.55, 0.26, 0.18))
	var holz := _lin(Color(0.50, 0.36, 0.22))
	# Haus auf der Normalenseite, laengs zum Bach
	var haus_q := d0 + 4.6
	var hm := nor * haus_q
	var hb := Basis(dir, Vector3.UP, dir.cross(Vector3.UP).normalized())
	var lm := Vector3(hm.x, 0.0, hm.z)
	# AM HANG: Boden = Mitte zwischen tiefster und hoechster Ecke; zur Bachseite hin ein
	# gemauerter Sockel bis unter die tiefste Ecke (die Muehle steht an der Klammwand).
	var tief := INF
	var hoechst := -INF
	for ex: float in [-5.0, 5.0]:
		for ez: float in [-3.6, 3.6]:
			var ec := c + hm + hb * Vector3(ex, 0, ez)
			var eh := terrain.height_at(ec.x, ec.z) - fuss.y
			tief = minf(tief, eh)
			hoechst = maxf(hoechst, eh)
	var boden := maxf(lerpf(tief, hoechst, 0.5), 1.2)
	var sockel_u := minf(tief, 0.0) - 1.0
	var sockel_h := boden + 2.4 - sockel_u
	_quader(st, lm + Vector3(0, sockel_u + sockel_h * 0.5, 0), Vector3(5.0, sockel_h * 0.5, 3.6), hb, stein)   # Sockel
	_quader(st, lm + Vector3(0, boden + 3.4, 0), Vector3(4.9, 1.6, 3.5), hb, putz)              # Obergeschoss
	for xx: float in [-4.6, -1.6, 1.6, 4.6]:
		_quader(st, lm + hb * Vector3(xx, 0, 0) + Vector3(0, boden + 3.4, 0), Vector3(0.12, 1.6, 3.56), hb, balken)
	for seite2: float in [-1.0, 1.0]:
		var neig := hb * Basis(Vector3(1, 0, 0), seite2 * 0.70)
		_quader(st, lm + hb * Vector3(0, 0, seite2 * 1.9) + Vector3(0, boden + 6.25, 0), Vector3(5.5, 0.10, 2.6), neig, dach)
	_quader(st, lm + hb * Vector3(-2.5, 0, 0) + Vector3(0, boden + 7.2, 0), Vector3(0.35, 1.1, 0.35), hb, stein)   # Kamin
	# Fenster und Tuer zur Landseite
	var fenster := _lin(Color(0.25, 0.32, 0.40))
	for xx2: float in [-2.8, 0.0, 2.8]:
		_quader(st, lm + hb * Vector3(xx2, 0, 3.58) + Vector3(0, boden + 3.6, 0), Vector3(0.45, 0.55, 0.03), hb, fenster)
	var tuer_y := clampf(hoechst + 1.1, boden + 0.6, boden + 2.9)
	_quader(st, lm + hb * Vector3(1.0, 0, 3.62) + Vector3(0, tuer_y, 0), Vector3(0.6, 1.1, 0.04), hb, balken)
	# Radlager auf der Bachseite
	var rad_q := d0 * 0.55
	var r := clampf(hoch * 0.55 + 1.2, 2.2, 4.5)
	var rad_m := nor * rad_q + Vector3(0, r * 0.75, 0)
	_quader(st, Vector3(rad_m.x, rad_m.y * 0.5, rad_m.z) + nor * 0.9, Vector3(0.2, rad_m.y * 0.5 + 0.2, 0.2), hb, balken)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(0.0)
	mi.visibility_range_end = STEG_SICHT
	knoten.add_child(mi)
	# Das RAD: eigenes Netz um seine Achse (lokales X = quer zum Bach), Shader dreht es.
	var sr := SurfaceTool.new()
	sr.begin(Mesh.PRIMITIVE_TRIANGLES)
	var breite := 1.2
	for s3: float in [-breite * 0.5, breite * 0.5]:
		for k in 16:
			var w0 := TAU * float(k) / 16.0
			var w1 := TAU * float(k + 1) / 16.0
			var a0 := Vector3(s3, cos(w0) * r, sin(w0) * r)
			var a1 := Vector3(s3, cos(w1) * r, sin(w1) * r)
			_quader(sr, (a0 + a1) * 0.5, Vector3(0.08, 0.12, a0.distance_to(a1) * 0.5), Basis(Vector3.RIGHT, (w0 + w1) * 0.5), holz)
		for k in 6:
			var w := TAU * float(k) / 6.0
			_quader(sr, Vector3(s3, cos(w) * r * 0.5, sin(w) * r * 0.5), Vector3(0.06, r * 0.5, 0.07), Basis(Vector3.RIGHT, w), balken)
	for k in 16:
		var w := TAU * float(k) / 16.0
		_quader(sr, Vector3(0, cos(w) * r * 0.93, sin(w) * r * 0.93), Vector3(breite * 0.5, 0.05, 0.28), Basis(Vector3.RIGHT, w - PI * 0.5), holz)
	_saeule(sr, Vector3(-breite, 0, 0), Vector3(breite + 1.0, 0, 0), 0.16, 8, balken)
	sr.generate_normals()
	var rad := MeshInstance3D.new()
	rad.mesh = sr.commit()
	var rm := _mat(0.0)
	rm.set_shader_parameter("drehen", -0.9)
	rad.material_override = rm
	rad.visibility_range_end = STEG_SICHT
	knoten.add_child(rad)
	rad.position = rad_m
	rad.basis = Basis(nor, Vector3.UP, nor.cross(Vector3.UP))
	# HOLZSTEG ueber den Bach, etwa 35 m flussab
	var j := unten
	var weg := 0.0
	while j < pts.size() - 2 and weg < 35.0:
		weg += pts[j].distance_to(pts[j + 1])
		j += 1
	var us := _ufer(rv, j, 1.0)
	var sc: Vector3 = us["c"]
	var snor: Vector3 = us["n"]
	var halb := float(us["w"]) * 1.25 + 2.5
	var sst := SurfaceTool.new()
	sst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sb := Basis(snor, Vector3.UP, snor.cross(Vector3.UP))   # x quer ueber den Bach
	var n_brett := int(halb * 2.0 / 0.32)
	for k in n_brett:
		var q := -halb + (float(k) + 0.5) * (halb * 2.0 / float(n_brett))
		var bogen_y := 1.6 * (1.0 - pow(q / halb, 2.0)) + 0.6
		_quader(sst, sb * Vector3(q, bogen_y, 0), Vector3(0.15, 0.05, 0.85), sb, holz if k % 3 else balken)
	for s4: float in [-0.85, 0.85]:
		for k in 9:
			var q2 := lerpf(-halb, halb, float(k) / 8.0)
			var yy := 1.6 * (1.0 - pow(q2 / halb, 2.0)) + 0.6
			_saeule(sst, sb * Vector3(q2, yy, s4), sb * Vector3(q2, yy + 0.95, s4), 0.04, 4, balken)
		for k in 12:
			var qa := lerpf(-halb, halb, float(k) / 12.0)
			var qb := lerpf(-halb, halb, float(k + 1) / 12.0)
			var ya := 1.6 * (1.0 - pow(qa / halb, 2.0)) + 1.55
			var yb := 1.6 * (1.0 - pow(qb / halb, 2.0)) + 1.55
			_saeule(sst, sb * Vector3(qa, ya, s4), sb * Vector3(qb, yb, s4), 0.04, 4, holz)
	sst.generate_normals()
	var steg := MeshInstance3D.new()
	steg.mesh = sst.commit()
	steg.material_override = _mat(0.0)
	steg.visibility_range_end = STEG_SICHT
	wurzel.add_child(steg)
	steg.global_position = Vector3(sc.x, sc.y, sc.z)
	return true
