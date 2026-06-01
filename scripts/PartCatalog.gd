## PartCatalog.gd
## Zentrale Definition aller Bauteile + prozedurale Mesh-/Material-Erzeugung.
## Jede Teil-Definition ist ein Dictionary. Meshes werden im Code erzeugt,
## damit das Spiel ohne externe 3D-Assets läuft.
class_name PartCatalog
extends RefCounted

# Kategorien (Reihenfolge = Reihenfolge im Bau-Menü)
const CAT_BODY := "Rumpf"
const CAT_WING := "Tragflächen"
const CAT_CTRL := "Leitwerk & Steuerung"
const CAT_PROP := "Antrieb"
const CAT_GEAR := "Fahrwerk"

const CATEGORY_ORDER := [CAT_BODY, CAT_WING, CAT_CTRL, CAT_PROP, CAT_GEAR]

# Farben (klassisches Flugzeug-Look)
const C_BODY := Color(0.80, 0.82, 0.85)
const C_COCKPIT := Color(0.30, 0.45, 0.62)
const C_WING := Color(0.84, 0.28, 0.24)
const C_CTRL := Color(0.95, 0.62, 0.15)
const C_ENGINE := Color(0.26, 0.28, 0.32)
const C_GEAR := Color(0.10, 0.10, 0.12)

static var _parts: Dictionary = {}
static var _order: Array = []
static var _built := false

# ---------------------------------------------------------------------------
# Aufbau des Katalogs
# ---------------------------------------------------------------------------
static func _build() -> void:
	if _built:
		return
	_built = true
	_parts.clear()
	_order.clear()

	# --- Rumpf -------------------------------------------------------------
	_add({
		"id": "cockpit", "name": "Cockpit", "category": CAT_BODY,
		"mass": 180.0, "color": C_COCKPIT, "shape": "cockpit",
		"size": Vector3(1.3, 1.1, 2.2), "root": true,
		"desc": "Das Herz des Flugzeugs. Hier startet jeder Bau.",
	})
	_add({
		"id": "fuselage", "name": "Rumpfsegment", "category": CAT_BODY,
		"mass": 120.0, "color": C_BODY, "shape": "box",
		"size": Vector3(1.3, 1.1, 2.0),
	})
	_add({
		"id": "fuselage_long", "name": "Langes Rumpfsegment", "category": CAT_BODY,
		"mass": 175.0, "color": C_BODY, "shape": "box",
		"size": Vector3(1.3, 1.1, 3.2),
	})
	_add({
		"id": "nose", "name": "Nasenkonus", "category": CAT_BODY,
		"mass": 70.0, "color": C_BODY, "shape": "nose",
		"size": Vector3(1.3, 1.1, 1.8),
	})
	_add({
		"id": "tailcone", "name": "Heckkonus", "category": CAT_BODY,
		"mass": 60.0, "color": C_BODY, "shape": "nose", "reverse": true,
		"size": Vector3(1.3, 1.1, 1.8),
	})
	_add({
		"id": "fueltank", "name": "Treibstofftank", "category": CAT_BODY,
		"mass": 240.0, "color": Color(0.7, 0.72, 0.75), "shape": "cyl",
		"size": Vector3(1.2, 1.2, 2.0), "metal": 0.6, "rough": 0.3,
	})

	# --- Tragflächen -------------------------------------------------------
	_wing("wing_straight", "Gerade Tragfläche", CAT_WING, 70.0, C_WING, 4.4, 1.7, 1.7, 0.0, 1.05)
	_wing("wing_tapered", "Trapezflügel", CAT_WING, 62.0, C_WING, 4.6, 1.9, 1.0, 0.4, 1.0)
	_wing("wing_swept", "Pfeilflügel", CAT_WING, 66.0, C_WING, 4.6, 1.7, 1.0, 1.5, 0.95)
	_wing("wing_delta", "Deltaflügel", CAT_WING, 88.0, C_WING, 3.6, 3.2, 0.4, 2.7, 0.9)
	_wing("wing_short", "Stummelflügel", CAT_WING, 42.0, C_WING, 2.4, 1.5, 1.1, 0.2, 1.0)
	_wing("wing_glider", "Segler-Flügel (lang)", CAT_WING, 95.0, C_WING, 6.8, 1.3, 0.75, 0.3, 1.25)
	_wing("canard", "Canard-Flügel", CAT_WING, 30.0, C_WING, 1.8, 1.0, 0.6, 0.15, 1.0)
	_wing("winglet", "Winglet", CAT_WING, 14.0, C_WING, 1.0, 0.8, 0.45, 0.25, 0.6)

	# --- Leitwerk & Steuerung ---------------------------------------------
	_wing("h_stab", "Höhenleitwerk (Pitch)", CAT_CTRL, 32.0, C_CTRL, 2.6, 1.1, 0.7, 0.25, 0.85, "pitch")
	_wing("v_stab", "Seitenleitwerk (Yaw)", CAT_CTRL, 30.0, C_CTRL, 1.8, 1.3, 0.7, 0.7, 0.8, "yaw")
	_wing("aileron", "Querruder (Roll)", CAT_CTRL, 16.0, C_CTRL, 1.8, 0.7, 0.55, 0.05, 0.7, "roll")
	_wing("elevator", "Höhenruder klein", CAT_CTRL, 14.0, C_CTRL, 1.6, 0.7, 0.55, 0.05, 0.7, "pitch")

	# --- Antrieb -----------------------------------------------------------
	_add({
		"id": "prop_engine", "name": "Propellermotor", "category": CAT_PROP,
		"mass": 160.0, "color": C_ENGINE, "shape": "prop", "thrust": 6500.0,
		"size": Vector3(1.1, 1.1, 1.7), "metal": 0.7, "rough": 0.35,
	})
	_add({
		"id": "prop_engine_big", "name": "Großer Propeller", "category": CAT_PROP,
		"mass": 250.0, "color": C_ENGINE, "shape": "prop", "thrust": 11000.0,
		"size": Vector3(1.5, 1.5, 1.9), "metal": 0.7, "rough": 0.35,
	})
	_add({
		"id": "jet_engine", "name": "Düsentriebwerk", "category": CAT_PROP,
		"mass": 300.0, "color": C_ENGINE, "shape": "jet", "thrust": 20000.0, "jet": true,
		"size": Vector3(1.2, 1.2, 2.6), "metal": 0.8, "rough": 0.25,
	})
	_add({
		"id": "thruster", "name": "Hilfstriebwerk", "category": CAT_PROP,
		"mass": 95.0, "color": C_ENGINE, "shape": "jet", "thrust": 4200.0, "jet": true,
		"size": Vector3(0.8, 0.8, 1.4), "metal": 0.8, "rough": 0.25,
	})

	# --- Fahrwerk (mit Traglast in kg; Summe muss das Gewicht tragen) ------
	_add({
		"id": "wheel_light", "name": "Leichtes Fahrwerk", "category": CAT_GEAR,
		"mass": 28.0, "color": C_GEAR, "shape": "wheel", "gear_capacity": 450.0,
		"size": Vector3(0.5, 1.0, 0.7), "metal": 0.1, "rough": 0.8,
		"desc": "Leicht, aber nur ~450 kg Traglast.",
	})
	_add({
		"id": "wheel", "name": "Standard-Fahrwerk", "category": CAT_GEAR,
		"mass": 45.0, "color": C_GEAR, "shape": "wheel", "gear_capacity": 850.0,
		"size": Vector3(0.6, 1.2, 0.9), "metal": 0.1, "rough": 0.8,
		"desc": "Ausgewogen, ~850 kg Traglast.",
	})
	_add({
		"id": "wheel_heavy", "name": "Schweres Fahrwerk", "category": CAT_GEAR,
		"mass": 85.0, "color": C_GEAR, "shape": "wheel", "gear_capacity": 1750.0,
		"size": Vector3(0.78, 1.4, 1.05), "metal": 0.15, "rough": 0.75,
		"desc": "Robust, ~1750 kg Traglast — für schwere Jets.",
	})
	_add({
		"id": "wheel_retract", "name": "Einziehfahrwerk (G)", "category": CAT_GEAR,
		"mass": 60.0, "color": Color(0.16, 0.16, 0.2), "shape": "wheel", "gear_capacity": 1050.0,
		"size": Vector3(0.62, 1.25, 0.9), "metal": 0.5, "rough": 0.45, "retract": true,
		"desc": "Im Flug mit G einfahren -> weniger Widerstand. ~1050 kg.",
	})


static func _add(p: Dictionary) -> void:
	# Standardwerte
	var d := {
		"shape": "box", "color": Color.WHITE, "mass": 50.0,
		"size": Vector3.ONE, "is_wing": false, "thrust": 0.0,
		"control": "", "orient_normal": false, "area": 0.0, "lift": 1.0,
		"metal": 0.3, "rough": 0.55, "root": false, "reverse": false,
		"gear_capacity": 0.0, "retract": false,
	}
	for k in p.keys():
		d[k] = p[k]
	_parts[d["id"]] = d
	_order.append(d["id"])


static func _wing(id: String, name: String, cat: String, mass: float, color: Color,
		span: float, rc: float, tc: float, sweep: float, lift: float, control: String = "") -> void:
	var thick := 0.16
	var maxc: float = max(rc, tc)
	var area := (rc + tc) * 0.5 * span
	_add({
		"id": id, "name": name, "category": cat, "mass": mass, "color": color,
		"shape": "wing", "span": span, "root_chord": rc, "tip_chord": tc,
		"sweep": sweep, "thickness": thick, "is_wing": true, "area": area,
		"lift": lift, "control": control, "orient_normal": true,
		"col_size": Vector3(span, thick + 0.1, maxc + absf(sweep)),
		"col_offset": Vector3(span * 0.5, 0.0, sweep * 0.5),
		"metal": 0.15, "rough": 0.6,
	})


# ---------------------------------------------------------------------------
# Zugriff
# ---------------------------------------------------------------------------
static func all() -> Dictionary:
	_build()
	return _parts

static func get_part(id: String) -> Dictionary:
	_build()
	return _parts.get(id, {})

static func has(id: String) -> bool:
	_build()
	return _parts.has(id)

static func categories() -> Array:
	return CATEGORY_ORDER

static func parts_in(cat: String) -> Array:
	_build()
	var out: Array = []
	for id in _order:
		if _parts[id]["category"] == cat:
			out.append(_parts[id])
	return out

## Strukturelle Belastbarkeit pro m² Flügelfläche (N) — für die G-Last-Grenze
const WING_STRESS := 3600.0

## Parasitärer Luftwiderstand eines Teils (cW·A in m²), grob aus Stirnfläche+Form
# Form-Widerstandsbeiwert (cd) eines Teils — eine Quelle für Flug & Windkanal.
static func part_cd(p: Dictionary) -> float:
	match p.get("shape", "box"):
		"nose": return 0.10
		"wing": return 0.06
		"cockpit": return 0.30
		"cyl", "jet", "prop": return 0.32
		"wheel": return 0.65
		"box": return 0.55
	return 0.5


static func part_drag(p: Dictionary) -> float:
	var s: Vector3 = col_size(p)
	var frontal: float = s.x * s.y      # Querschnitt in Flugrichtung (-Z)
	return frontal * part_cd(p)


static func col_size(p: Dictionary) -> Vector3:
	return p.get("col_size", p.get("size", Vector3.ONE))

static func col_offset(p: Dictionary) -> Vector3:
	return p.get("col_offset", Vector3.ZERO)


# ---------------------------------------------------------------------------
# Material-Helfer
# ---------------------------------------------------------------------------
static func make_material(c: Color, metal := 0.3, rough := 0.55, double_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.metallic_specular = 0.6
	m.roughness = rough
	# leichter Kanten-Glanz für mehr Plastizität
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.35
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# Glüh-Material (Auspuff/Akzente)
static func glow_material(c: Color, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


# ---------------------------------------------------------------------------
# Visuelle Erzeugung — gibt einen Node3D zurück (kann mehrere Meshes enthalten)
# ---------------------------------------------------------------------------
static func build_visual(p: Dictionary, col_override := Color(0, 0, 0, 0)) -> Node3D:
	var root := Node3D.new()
	var shape: String = p.get("shape", "box")
	var col: Color = p.get("color", Color.WHITE)
	if col_override.a > 0.0:   # Lackierung überschreibt die Standardfarbe
		col = col_override
	var metal: float = p.get("metal", 0.3)
	var rough: float = p.get("rough", 0.55)
	var size: Vector3 = p.get("size", Vector3.ONE)

	match shape:
		"box":
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm
			mi.material_override = make_material(col, metal, rough)
			root.add_child(mi)

		"wing":
			var mi := MeshInstance3D.new()
			mi.mesh = _wing_mesh(p.get("span", 4.0), p.get("root_chord", 1.5),
				p.get("tip_chord", 1.5), p.get("sweep", 0.0), p.get("thickness", 0.16))
			mi.material_override = make_material(col, metal, rough, true)
			root.add_child(mi)

		"cyl":
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = size.x * 0.5
			cm.bottom_radius = size.x * 0.5
			cm.height = size.z
			cm.radial_segments = 20
			mi.mesh = cm
			mi.rotation = Vector3(PI * 0.5, 0, 0) # Achse Y -> Z
			mi.material_override = make_material(col, metal, rough)
			root.add_child(mi)

		"nose":
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = size.x * 0.5
			cm.bottom_radius = 0.04
			cm.height = size.z
			cm.radial_segments = 20
			mi.mesh = cm
			# Standard: Spitze zeigt nach vorne (-Z). reverse = Spitze nach hinten.
			if p.get("reverse", false):
				mi.rotation = Vector3(-PI * 0.5, 0, 0)
			else:
				mi.rotation = Vector3(PI * 0.5, 0, 0)
			mi.material_override = make_material(col, metal, rough)
			root.add_child(mi)

		"cockpit":
			var body := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			body.mesh = bm
			body.material_override = make_material(col, metal, rough)
			root.add_child(body)
			# Kanzel (Glas)
			var canopy := MeshInstance3D.new()
			var cb := BoxMesh.new()
			cb.size = Vector3(size.x * 0.7, size.y * 0.55, size.z * 0.6)
			canopy.mesh = cb
			canopy.position = Vector3(0, size.y * 0.5, -size.z * 0.12)
			var glass := make_material(Color(0.12, 0.22, 0.38), 0.0, 0.05)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.albedo_color.a = 0.55
			canopy.material_override = glass
			root.add_child(canopy)

		"prop":
			# Gondel
			var nac := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = size.x * 0.34
			cm.bottom_radius = size.x * 0.34
			cm.height = size.z * 0.7
			cm.radial_segments = 18
			nac.mesh = cm
			nac.rotation = Vector3(PI * 0.5, 0, 0)
			nac.position = Vector3(0, 0, size.z * 0.1)
			nac.material_override = make_material(col, metal, rough)
			root.add_child(nac)
			# Spinner vorne
			var spin := MeshInstance3D.new()
			var sc := CylinderMesh.new()
			sc.top_radius = size.x * 0.18
			sc.bottom_radius = 0.02
			sc.height = size.x * 0.4
			spin.mesh = sc
			spin.rotation = Vector3(PI * 0.5, 0, 0)
			spin.position = Vector3(0, 0, -size.z * 0.42)
			spin.material_override = make_material(Color(0.7, 0.1, 0.1), 0.5, 0.4)
			root.add_child(spin)
			# Propeller (dreht sich im Flug)
			var prop := Node3D.new()
			prop.name = "Prop"
			prop.position = Vector3(0, 0, -size.z * 0.5)
			var blade_mat := make_material(Color(0.08, 0.08, 0.09), 0.2, 0.5)
			var blade_len: float = size.x * 1.05
			for i in 3:
				var holder := Node3D.new()
				holder.rotation = Vector3(0, 0, deg_to_rad(120.0 * i))
				var blade := MeshInstance3D.new()
				var bbm := BoxMesh.new()
				bbm.size = Vector3(0.07, blade_len, 0.2)
				blade.mesh = bbm
				blade.position = Vector3(0, blade_len * 0.5, 0)
				blade.material_override = blade_mat
				holder.add_child(blade)
				prop.add_child(holder)
			root.add_child(prop)
			# durchscheinende Propeller-Scheibe (Bewegungsunschärfe-Look)
			var disc := MeshInstance3D.new()
			var dm := CylinderMesh.new()
			dm.top_radius = blade_len
			dm.bottom_radius = blade_len
			dm.height = 0.02
			dm.radial_segments = 24
			disc.mesh = dm
			disc.rotation = Vector3(PI * 0.5, 0, 0)
			disc.position = Vector3(0, 0, -size.z * 0.52)
			var dmat := make_material(Color(0.5, 0.5, 0.55), 0.1, 0.6)
			dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			dmat.albedo_color.a = 0.12
			dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
			disc.mesh.material = dmat
			root.add_child(disc)

		"jet":
			var nac := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = size.x * 0.5
			cm.bottom_radius = size.x * 0.46
			cm.height = size.z
			cm.radial_segments = 22
			nac.mesh = cm
			nac.rotation = Vector3(PI * 0.5, 0, 0)
			nac.material_override = make_material(col, metal, rough)
			root.add_child(nac)
			# dunkler Einlassring vorne
			var intake := MeshInstance3D.new()
			var ic := CylinderMesh.new()
			ic.top_radius = size.x * 0.52
			ic.bottom_radius = size.x * 0.52
			ic.height = size.z * 0.12
			intake.mesh = ic
			intake.rotation = Vector3(PI * 0.5, 0, 0)
			intake.position = Vector3(0, 0, -size.z * 0.46)
			intake.material_override = make_material(Color(0.05, 0.05, 0.06), 0.3, 0.6)
			root.add_child(intake)
			# Auspuff (leuchtet leicht)
			var ex := MeshInstance3D.new()
			var ec := CylinderMesh.new()
			ec.top_radius = size.x * 0.3
			ec.bottom_radius = size.x * 0.42
			ec.height = size.z * 0.18
			ex.mesh = ec
			ex.rotation = Vector3(PI * 0.5, 0, 0)
			ex.position = Vector3(0, 0, size.z * 0.5)
			var em := make_material(Color(0.6, 0.25, 0.08), 0.4, 0.4)
			em.emission_enabled = true
			em.emission = Color(1.0, 0.4, 0.1)
			em.emission_energy_multiplier = 0.6
			ex.material_override = em
			root.add_child(ex)

		"wheel":
			# Rad (Achse entlang X)
			var wheel := MeshInstance3D.new()
			var wc := CylinderMesh.new()
			var r: float = size.z * 0.5
			wc.top_radius = r
			wc.bottom_radius = r
			wc.height = size.x * 0.6
			wc.radial_segments = 18
			wheel.mesh = wc
			wheel.rotation = Vector3(0, 0, PI * 0.5) # Achse Y -> X
			wheel.position = Vector3(0, -size.y * 0.5 + r, 0)
			wheel.material_override = make_material(col, 0.1, 0.85)
			root.add_child(wheel)
			# Strebe
			var strut := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(0.14, size.y * 0.55, 0.14)
			strut.mesh = sb
			strut.position = Vector3(0, size.y * 0.12, 0)
			strut.material_override = make_material(Color(0.5, 0.5, 0.55), 0.7, 0.4)
			root.add_child(strut)

		_:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm
			mi.material_override = make_material(col, metal, rough)
			root.add_child(mi)

	return root


# ---------------------------------------------------------------------------
# Tragflächen-Mesh (Trapez mit Pfeilung), Spannweite entlang +X, Sehne entlang Z
# ---------------------------------------------------------------------------
static func _wing_mesh(span: float, rc: float, tc: float, sweep: float, _thick: float) -> ArrayMesh:
	# Gewölbtes Airfoil-Profil (NACA-0012-Dickenverteilung), als Skin von Wurzel
	# zur (verrundeten) Spitze gelofted. Geglättete Normalen für weiche Optik.
	# Profilrundgang: f = Sehnenanteil (0 Nase .. 1 Hinterkante), side: +oben/-unten
	var prof := [
		[0.0, 0.0], [0.04, 1.0], [0.10, 1.0], [0.20, 1.0], [0.35, 1.0],
		[0.55, 1.0], [0.75, 1.0], [0.90, 1.0], [1.0, 0.0],
		[0.90, -1.0], [0.75, -1.0], [0.55, -1.0], [0.35, -1.0],
		[0.20, -1.0], [0.10, -1.0], [0.04, -1.0],
	]
	var m := prof.size()
	var secs := [
		[0.0, rc], [0.55, lerpf(rc, tc, 0.55)],
		[0.85, lerpf(rc, tc, 0.85)], [1.0, maxf(tc * 0.4, 0.25)],
	]
	var tratio := 0.12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in secs.size():
		var u: float = secs[s][0]
		var chord: float = secs[s][1]
		var cx: float = u * span
		var cz: float = lerpf(0.0, sweep, u)
		for i in m:
			var f: float = prof[i][0]
			var yt: float = _airfoil_y(f, tratio) * chord
			st.add_vertex(Vector3(cx, prof[i][1] * yt, (cz - chord * 0.5) + f * chord))
	for s in secs.size() - 1:
		var b0 := s * m
		var b1 := (s + 1) * m
		for i in m:
			var j := (i + 1) % m
			st.add_index(b0 + i); st.add_index(b1 + i); st.add_index(b1 + j)
			st.add_index(b0 + i); st.add_index(b1 + j); st.add_index(b0 + j)
	var lb := (secs.size() - 1) * m
	for i in range(1, m - 1):       # Spitzen-Kappe
		st.add_index(lb); st.add_index(lb + i); st.add_index(lb + i + 1)
	for i in range(1, m - 1):       # Wurzel-Kappe
		st.add_index(0); st.add_index(i + 1); st.add_index(i)
	st.generate_normals()
	return st.commit()


static func _airfoil_y(f: float, t: float) -> float:
	f = clampf(f, 0.0, 1.0)
	return (t / 0.2) * (0.2969 * sqrt(f) - 0.1260 * f - 0.3516 * f * f + 0.2843 * f * f * f - 0.1015 * f * f * f * f)
