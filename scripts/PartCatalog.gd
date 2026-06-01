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


# MeshInstance3D mit Material + Transform in einem Rutsch (gegen Boilerplate).
static func _mi(mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO,
		scl := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	if mat != null:
		m.material_override = mat
	m.position = pos
	m.rotation = rot
	m.scale = scl
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
			# Rumpfsegment als glatter, leicht abgerundeter Tubus (elliptischer
			# Querschnitt). Enden flach -> Segmente docken nahtlos aneinander.
			var tube := _revolve([
				Vector2(-0.5, 0.49), Vector2(-0.46, 0.5), Vector2(0.46, 0.5), Vector2(0.5, 0.49)
			], 18)
			root.add_child(_mi(tube, make_material(col, metal, rough), Vector3.ZERO,
				Vector3.ZERO, size))

		"wing":
			var mi := MeshInstance3D.new()
			mi.mesh = _wing_mesh(p.get("span", 4.0), p.get("root_chord", 1.5),
				p.get("tip_chord", 1.5), p.get("sweep", 0.0), p.get("thickness", 0.16))
			mi.material_override = make_material(col, metal, rough, true)
			root.add_child(mi)

		"cyl":
			# Tank mit gewölbten Enden (Kapselprofil), schön metallisch.
			var tank := _revolve(_capsule_profile(), 22)
			root.add_child(_mi(tank, make_material(col, metal, rough), Vector3.ZERO,
				Vector3.ZERO, size))

		"nose":
			# Glatte paraboloide Ogive. Standard: Spitze nach vorne (-Z),
			# reverse = Spitze nach hinten (Heckkonus).
			var og := _revolve(_ogive_profile(p.get("reverse", false)), 24)
			root.add_child(_mi(og, make_material(col, metal, rough), Vector3.ZERO,
				Vector3.ZERO, size))

		"cockpit":
			# Runder Rumpf-Körper, vorne leicht verjüngt (verrundet).
			var cbody := _revolve([
				Vector2(-0.5, 0.4), Vector2(-0.42, 0.48), Vector2(-0.2, 0.5),
				Vector2(0.46, 0.5), Vector2(0.5, 0.49)
			], 20)
			root.add_child(_mi(cbody, make_material(col, metal, rough), Vector3.ZERO,
				Vector3.ZERO, size))
			# Blasen-Kanzel (halb eingelassene Glaskuppel).
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = 24
			sm.rings = 12
			var glass := make_material(Color(0.13, 0.24, 0.4), 0.1, 0.05)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.albedo_color.a = 0.6
			glass.rim_enabled = true
			glass.rim = 0.6
			root.add_child(_mi(sm, glass, Vector3(0, size.y * 0.32, -size.z * 0.06),
				Vector3.ZERO, Vector3(size.x * 0.62, size.y * 0.7, size.z * 0.92)))

		"prop":
			# Gondel als runder Tubus, hinten verrundet.
			var nac := _revolve([
				Vector2(-0.5, 0.5), Vector2(0.34, 0.5), Vector2(0.46, 0.42), Vector2(0.5, 0.28)
			], 20)
			root.add_child(_mi(nac, make_material(col, metal, rough), Vector3(0, 0, size.z * 0.08),
				Vector3.ZERO, Vector3(size.x * 0.68, size.x * 0.68, size.z * 0.72)))
			# Spinner vorne (glatte Ogive, Spitze nach -Z).
			var spin := _revolve(_ogive_profile(false), 20)
			root.add_child(_mi(spin, make_material(Color(0.72, 0.12, 0.1), 0.5, 0.4),
				Vector3(0, 0, -size.z * 0.44), Vector3.ZERO,
				Vector3(size.x * 0.36, size.x * 0.36, size.x * 0.55)))
			# Propeller (dreht sich im Flug) — getwistete, sich verjüngende Blätter.
			var prop := Node3D.new()
			prop.name = "Prop"
			prop.position = Vector3(0, 0, -size.z * 0.52)
			var blade_mat := make_material(Color(0.08, 0.08, 0.09), 0.25, 0.5)
			var blade_len: float = size.x * 1.05
			for i in 3:
				var holder := Node3D.new()
				holder.rotation = Vector3(0, 0, deg_to_rad(120.0 * i))
				# Blatt: lang in Y (radial), dünn, mit Anstellwinkel (Twist um Y).
				var bbm := BoxMesh.new()
				bbm.size = Vector3(0.055, blade_len, 0.18)
				var blade := _mi(bbm, blade_mat, Vector3(0, blade_len * 0.5, 0),
					Vector3(0, deg_to_rad(22), 0))
				holder.add_child(blade)
				prop.add_child(holder)
			root.add_child(prop)
			# durchscheinende Propeller-Scheibe (Bewegungsunschärfe-Look)
			var dm := CylinderMesh.new()
			dm.top_radius = blade_len
			dm.bottom_radius = blade_len
			dm.height = 0.02
			dm.radial_segments = 24
			var dmat := make_material(Color(0.5, 0.5, 0.55), 0.1, 0.6)
			dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			dmat.albedo_color.a = 0.12
			dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
			dm.material = dmat
			root.add_child(_mi(dm, null, Vector3(0, 0, -size.z * 0.54), Vector3(PI * 0.5, 0, 0)))

		"jet":
			# Triebwerksgondel als runder Tubus (vorne/hinten leicht verrundet).
			var jbody := _revolve([
				Vector2(-0.5, 0.45), Vector2(-0.44, 0.5), Vector2(0.4, 0.5), Vector2(0.5, 0.42)
			], 22)
			root.add_child(_mi(jbody, make_material(col, metal, rough), Vector3.ZERO,
				Vector3.ZERO, Vector3(size.x, size.x, size.z)))
			# Einlauf-Lippe (Torus) vorne
			var lip := TorusMesh.new()
			lip.inner_radius = size.x * 0.4
			lip.outer_radius = size.x * 0.52
			lip.rings = 26
			lip.ring_segments = 12
			root.add_child(_mi(lip, make_material(Color(0.2, 0.21, 0.24), 0.75, 0.3),
				Vector3(0, 0, -size.z * 0.5), Vector3(PI * 0.5, 0, 0)))
			# dunkler Einlauf-Innenraum
			var face := CylinderMesh.new()
			face.top_radius = size.x * 0.4
			face.bottom_radius = size.x * 0.4
			face.height = 0.04
			root.add_child(_mi(face, make_material(Color(0.03, 0.03, 0.04), 0.2, 0.7),
				Vector3(0, 0, -size.z * 0.45), Vector3(PI * 0.5, 0, 0)))
			# Schubdüse hinten (konvergent)
			var noz := _revolve([
				Vector2(-0.5, 0.5), Vector2(0.2, 0.46), Vector2(0.5, 0.34)
			], 20)
			root.add_child(_mi(noz, make_material(Color(0.22, 0.22, 0.24), 0.7, 0.3),
				Vector3(0, 0, size.z * 0.5), Vector3.ZERO,
				Vector3(size.x, size.x, size.z * 0.22)))
			# Nachbrenner-Glühen
			var glow := CylinderMesh.new()
			glow.top_radius = size.x * 0.3
			glow.bottom_radius = size.x * 0.3
			glow.height = 0.04
			var em := make_material(Color(0.7, 0.3, 0.1), 0.3, 0.4)
			em.emission_enabled = true
			em.emission = Color(1.0, 0.45, 0.12)
			em.emission_energy_multiplier = 1.3
			root.add_child(_mi(glow, em, Vector3(0, 0, size.z * 0.6), Vector3(PI * 0.5, 0, 0)))

		"wheel":
			# Reifen als runder Torus (Achse entlang X), Felge + Nabe + Federbein.
			var r: float = size.z * 0.5
			var wpos := Vector3(0, -size.y * 0.5 + r, 0)
			var tire_w: float = size.x * 0.5
			var tire := TorusMesh.new()
			tire.inner_radius = r * 0.52
			tire.outer_radius = r
			tire.rings = 24
			tire.ring_segments = 14
			# Torus liegt in XZ (Loch-Achse Y); 90° um Z -> Loch-Achse X (Raddrehachse).
			root.add_child(_mi(tire, make_material(col, 0.05, 0.9),
				wpos, Vector3(0, 0, PI * 0.5)))
			# Felge/Radscheibe (metallisch)
			var rim := CylinderMesh.new()
			rim.top_radius = r * 0.56
			rim.bottom_radius = r * 0.56
			rim.height = tire_w * 0.7
			rim.radial_segments = 20
			root.add_child(_mi(rim, make_material(Color(0.7, 0.72, 0.78), 0.85, 0.3),
				wpos, Vector3(0, 0, PI * 0.5)))
			# Nabe
			var hub := CylinderMesh.new()
			hub.top_radius = r * 0.2
			hub.bottom_radius = r * 0.2
			hub.height = tire_w * 1.02
			root.add_child(_mi(hub, make_material(Color(0.3, 0.31, 0.34), 0.8, 0.35),
				wpos, Vector3(0, 0, PI * 0.5)))
			# Federbein (rundes Standrohr) + Achsschenkel
			var leg := _revolve(_capsule_profile(), 12)
			root.add_child(_mi(leg, make_material(Color(0.55, 0.57, 0.62), 0.8, 0.35),
				Vector3(0, size.y * 0.12, 0), Vector3(PI * 0.5, 0, 0),
				Vector3(0.16, 0.16, size.y * 0.72)))

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


# ---------------------------------------------------------------------------
# Rotationskörper um die Z-Achse. profile = Array[Vector2(z, radius)], radius>=0.
# Enden mit radius>0 werden flach gedeckelt. Outward gewickelt, glatte Normalen.
# Als EINHEITSform gedacht (r<=0.5, z in [-0.5,0.5]) und per Node-Skalierung gezogen.
# ---------------------------------------------------------------------------
static func _revolve(profile: Array, segs := 24) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var stride := segs + 1
	for ring in n:
		var z: float = profile[ring].x
		var rad: float = profile[ring].y
		for s in stride:
			var a: float = TAU * float(s) / float(segs)
			st.add_vertex(Vector3(cos(a) * rad, sin(a) * rad, z))
	for ring in n - 1:
		for s in segs:
			var i0 := ring * stride + s
			var i1 := ring * stride + s + 1
			var i2 := (ring + 1) * stride + s
			var i3 := (ring + 1) * stride + s + 1
			st.add_index(i0); st.add_index(i1); st.add_index(i2)
			st.add_index(i1); st.add_index(i3); st.add_index(i2)
	var verts := n * stride
	if float(profile[0].y) > 0.001:                  # vorderer Deckel (-Z)
		st.add_vertex(Vector3(0, 0, profile[0].x))
		var c0 := verts
		verts += 1
		for s in segs:
			st.add_index(c0); st.add_index(s + 1); st.add_index(s)
	if float(profile[n - 1].y) > 0.001:              # hinterer Deckel (+Z)
		st.add_vertex(Vector3(0, 0, profile[n - 1].x))
		var cn := verts
		var rb := (n - 1) * stride
		for s in segs:
			st.add_index(cn); st.add_index(rb + s); st.add_index(rb + s + 1)
	st.generate_normals()
	return st.commit()


# Ogiven-/Paraboloid-Nasenprofil (Spitze bei -Z). reverse -> Spitze bei +Z.
static func _ogive_profile(reverse: bool) -> Array:
	var pts: Array = []
	var steps := 10
	for i in steps + 1:
		var t: float = float(i) / float(steps)        # 0 = Spitze .. 1 = Basis
		var z: float = -0.5 + t
		var r: float = 0.5 * sqrt(t)                   # paraboloide Rundung
		pts.append(Vector2(z if not reverse else -z, r))
	if reverse:
		pts.reverse()                                  # z wieder aufsteigend
	return pts


# Tank-/Kapselprofil mit gewölbten Enden (Einheits-Radius 0.5, z in [-0.5,0.5]).
static func _capsule_profile() -> Array:
	return [
		Vector2(-0.5, 0.0), Vector2(-0.47, 0.3), Vector2(-0.42, 0.45), Vector2(-0.34, 0.5),
		Vector2(0.34, 0.5), Vector2(0.42, 0.45), Vector2(0.47, 0.3), Vector2(0.5, 0.0),
	]
