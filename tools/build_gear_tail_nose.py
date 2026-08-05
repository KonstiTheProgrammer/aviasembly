## Baut die beiden fehlenden Fahrwerks-Grundtypen -> res://models/wheel_tail.glb + wheel_nose.glb
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_gear_tail_nose.py
##
## Bis hierher waren ALLE neun Fahrwerke Hauptfahrwerke — es fehlte jedes Teil, das vorn
## oder hinten steht. Damit liess sich kein Flugzeug bauen, das korrekt auf drei Punkten
## aufsetzt. Diese beiden schliessen genau diese Luecke:
##   wheel_tail  Spornrad  — frei mitlaufend (Nachlauf!), fuer jeden Taildragger 1915-1945
##   wheel_nose  Bugfahrwerk — Doppelrad, Lenkkranz, fuer jeden Jet/Transporter
##
## STRUKTUR beider Teile wie bei wheel_f22 (siehe build_wheel_f22.py fuer die Begruendung):
##   Root -> Pivot(anim rot X) -> Leg(Node3D) -> LegMesh
##                                            -> [ScissorU -> ScissorL]   (nur Bugfahrwerk)
##                                            -> Extend(Editor-Beinlaenge)
##                                                -> Slider(anim Teleskop)
##                                                    -> SlideMesh + Wheel
## Achsen (glTF +Y up): Blender X -> Godot X (Radachse), Z -> Godot Y (oben),
##                      +Y -> Godot -Z (VORNE). Ruhepose Frame 1 = AUSGEFAHREN.
import bpy, math
from math import radians
from mathutils import Vector

OUT_DIR = "/Users/konstantinkanzler/Projects/aviasembly/models/"

XR = (0, radians(90), 0)          # Zylinder von Z- auf X-Achse drehen (= Radachse)


# =========================================================== gemeinsame Helfer
def mat(name, col, rough, metal):
    m = bpy.data.materials.new(name); m.name = name; m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def reset():
    """Szene komplett leeren — auch die Actions, sonst heisst die zweite 'retract.001'."""
    for o in list(bpy.data.objects):    bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):     bpy.data.meshes.remove(m)
    for mt in list(bpy.data.materials): bpy.data.materials.remove(mt)
    for a in list(bpy.data.actions):    bpy.data.actions.remove(a)
    sc = bpy.context.scene
    sc.render.fps = 30
    sc.frame_start, sc.frame_end = 1, 30
    M = {
        "rubber":   mat("rubber",  (0.050, 0.050, 0.058), 0.88, 0.0),
        "rim":      mat("rim",     (0.40, 0.42, 0.47),    0.30, 0.85),
        "hub":      mat("hub",     (0.17, 0.17, 0.19),    0.45, 0.70),
        "steel":    mat("steel",   (0.55, 0.57, 0.61),    0.22, 0.92),
        "gunmetal": mat("gunmetal",(0.165, 0.175, 0.205), 0.40, 0.72),
        "piston":   mat("piston",  (0.62, 0.64, 0.68),    0.20, 0.94),
        "dark":     mat("dark",    (0.135, 0.140, 0.160), 0.52, 0.55),
        "glass":    mat("glass",   (0.86, 0.88, 0.92),    0.08, 0.20),
    }
    return sc, M


def _bevel(o, width, segs=2):
    md = o.modifiers.new("bev", 'BEVEL')
    md.width, md.segments, md.limit_method = width, segs, 'ANGLE'
    md.angle_limit = radians(40)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=md.name)


def cyl(bag, r, depth, loc, rot=(0, 0, 0), material=None, v=32, bev=0.0):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=v)
    o = bpy.context.active_object
    if bev > 0: _bevel(o, bev, 2)
    if material: o.data.materials.append(material)
    bag.append(o); return o


def box(bag, scale, loc, material, rot=(0, 0, 0), bev=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object; o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bev > 0: _bevel(o, bev, 2)
    o.data.materials.append(material); bag.append(o); return o


def strut(bag, p0, p1, w, t, material, bev=0.005):
    a, b = Vector(p0), Vector(p1)
    d = b - a
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(a + b) / 2.0)
    o = bpy.context.active_object
    o.rotation_mode = 'QUATERNION'
    o.rotation_quaternion = d.to_track_quat('Z', 'Y')
    o.scale = (w, t, d.length)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bev > 0: _bevel(o, bev, 2)
    o.data.materials.append(material); bag.append(o); return o


def pin(bag, loc, r, w, material):
    return cyl(bag, r, w, loc, XR, material, v=14)


def join(sc, bag, name, origin):
    bpy.ops.object.select_all(action='DESELECT')
    for o in bag: o.select_set(True)
    bpy.context.view_layer.objects.active = bag[0]
    if len(bag) > 1: bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    sc.cursor.location = origin
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    sc.cursor.location = (0, 0, 0)
    return o


def empty(sc, name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    e.empty_display_size = 0.06
    e.location = loc
    if parent: e.parent = parent
    return e


def attach(child, parent):
    """Parenten OHNE das Kind zu versetzen — Blender rechnet die Kind-Transform sonst
    relativ zum Elternteil (faellt nur bei Eltern ausserhalb des Ursprungs auf)."""
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def glaetten(objs):
    """Nur Gummi und polierte Flaechen glatt — Struktur bleibt kantig (wie wheel_f22)."""
    for o in objs:
        for p in o.data.polygons:
            p.use_smooth = (o.data.materials[p.material_index].name in ("rubber", "piston", "glass"))


def anim_setup(objs):
    """EINE Action "retract" mit je einem Slot pro Objekt — AircraftBody sucht per
    has_animation("retract"), getrennte Actions ergaeben getrennte glTF-Animationen."""
    act = bpy.data.actions.new("retract")
    strip = act.layers.new("Layer").strips.new(type='KEYFRAME')
    slots = {}
    for ob in objs:
        ob.animation_data_create()
        ob.animation_data.action = act
        s = act.slots.new('OBJECT', ob.name)
        ob.animation_data.action_slot = s
        strip.channelbag(s, ensure=True)
        slots[ob] = s
    return act, strip, slots


def key(o, path, idx, frames):
    o.rotation_mode = 'XYZ'
    for fr, val in frames:
        vec = list(getattr(o, path))
        vec[idx] = val
        setattr(o, path, vec)
        o.keyframe_insert(data_path=path, index=idx, frame=fr)


def weich(strip, slots):
    for s in slots.values():
        for fc in strip.channelbag(s).fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = 'BEZIER'
                kp.easing = 'EASE_IN_OUT'


def export(sc, objs, fname):
    sc.frame_set(1)                                   # Ruhepose = ausgefahren
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=OUT_DIR + fname, export_format='GLB', use_selection=True,
        export_yup=True, export_apply=False,
        export_animations=True, export_animation_mode='ACTIONS',
        export_frame_range=True, export_bake_animation=True,
    )
    print("EXPORTED", fname)


# ============================================================================
#  1) SPORNRAD  — klein, frei mitlaufend, klappt nach vorn in den Rumpf
# ============================================================================
sc, M = reset()

Z_AX = -0.330          # Radachse
R_T  = 0.090           # -> Aufstandspunkt z = -0.420
NACH = -0.055          # NACHLAUF: Rad sitzt HINTER der Schwenkachse, sonst flattert
TELE_T = 0.045

UP, SL, WH, DR = [], [], [], []

# --- Anschluss + Federbein (LegMesh) ---------------------------------------
box(UP, (0.130, 0.150, 0.030), (0.0, 0.0, -0.014), M["gunmetal"], bev=0.006)
box(UP, (0.070, 0.086, 0.052), (0.0, 0.0, -0.048), M["gunmetal"], bev=0.006)
cyl(UP, 0.034, 0.115, (0, 0, -0.118), material=M["gunmetal"], v=24, bev=0.004)
cyl(UP, 0.040, 0.020, (0, 0, -0.172), material=M["steel"], v=24)
# Zugstrebe nach vorn — haelt den Sporn gegen das Bremsmoment
strut(UP, (0.0, 0.062, -0.028), (0.0, 0.022, -0.150), 0.016, 0.016, M["gunmetal"])
pin(UP, (0.0, 0.062, -0.026), 0.011, 0.048, M["steel"])

# --- Kolben + Schwenklager + Gabel (SlideMesh) ------------------------------
cyl(SL, 0.023, 0.115, (0, 0, -0.215), material=M["piston"], v=24)
cyl(SL, 0.036, 0.048, (0, 0, -0.262), material=M["gunmetal"], v=24, bev=0.004)  # Drehlager
cyl(SL, 0.044, 0.014, (0, 0, -0.240), material=M["steel"], v=24)                # Anlaufscheibe
# Gabel: sitzt schraeg nach HINTEN -> der Nachlauf laesst das Rad selbst nachlaufen
for sx in (-1.0, 1.0):
    strut(SL, (sx * 0.036, -0.006, -0.276), (sx * 0.036, NACH, Z_AX + 0.006),
          0.016, 0.030, M["gunmetal"], bev=0.004)
box(SL, (0.096, 0.052, 0.030), (0.0, -0.020, -0.278), M["gunmetal"], bev=0.005)
cyl(SL, 0.014, 0.098, (0, NACH, Z_AX), XR, M["steel"], v=16)                    # Achse

# --- Rad --------------------------------------------------------------------
cyl(WH, R_T, 0.058, (0, NACH, Z_AX), XR, M["rubber"], v=36, bev=0.010)
cyl(WH, 0.055, 0.064, (0, NACH, Z_AX), XR, M["rim"], v=28)
for sx in (-1.0, 1.0):
    cyl(WH, 0.062, 0.008, (sx * 0.030, NACH, Z_AX), XR, M["rim"], v=28)
cyl(WH, 0.020, 0.072, (0, NACH, Z_AX), XR, M["hub"], v=16)

# --- Klappe: deckt den Raum ab, in den das Bein nach VORN klappt --------------
# Flach gebaut = geschlossen. Der Scharnierpunkt liegt vorn bei y=0, die Klappe
# reicht nach hinten ueber den eingeklappten Sporn.
box(DR, (0.170, 0.400, 0.016), (0.0, 0.200, -0.008), M["dark"], bev=0.006)
box(DR, (0.022, 0.370, 0.020), (0.0, 0.200, 0.006), M["gunmetal"], bev=0.004)
for yy in (0.060, 0.330):
    box(DR, (0.150, 0.020, 0.018), (0.0, yy, 0.006), M["gunmetal"], bev=0.004)

legmesh = join(sc, UP, "LegMesh",   (0.0, 0.0, 0.0))
slide   = join(sc, SL, "SlideMesh", (0.0, 0.0, 0.0))
wheel   = join(sc, WH, "Wheel",     (0.0, NACH, Z_AX))     # Origin = Radachse -> rollt
door    = join(sc, DR, "Door",      (0.0, 0.0, -0.008))
glaetten([legmesh, slide, wheel, door])

root   = empty(sc, "Root_tail")
pivot  = empty(sc, "Pivot_tail", root)
leg    = empty(sc, "Leg", pivot)
extend = empty(sc, "Extend", leg)
slider = empty(sc, "Slider", extend)
bpy.context.view_layer.update()
attach(legmesh, leg); attach(slide, slider); attach(wheel, slider); attach(door, root)

act, strip, slots = anim_setup([pivot, door, slider])
key(pivot, "rotation_euler", 0, [(1, 0.0), (11, radians(20.0)), (24, radians(85.0)), (30, radians(82.0))])
key(door,  "rotation_euler", 0, [(1, radians(-84.0)), (8, radians(-88.0)), (30, 0.0)])
key(slider, "location", 2, [(1, 0.0), (7, 0.0), (16, TELE_T * 0.5), (26, TELE_T), (30, TELE_T)])
weich(strip, slots)

export(sc, [root, pivot, leg, extend, slider, legmesh, slide, wheel, door], "wheel_tail.glb")


# ============================================================================
#  2) BUGFAHRWERK — Doppelrad, Lenkkranz, Schere, Rollscheinwerfer, zwei Klappen
# ============================================================================
sc, M = reset()

Z_AX = -0.930          # Radachse
R_N  = 0.170           # -> Aufstandspunkt z = -1.100
DX   = 0.106           # halber Radabstand
TELE_N = 0.150

UP, SL, WH, SCU, SCL, DL, DRr = [], [], [], [], [], [], []

# --- Trunnion ---------------------------------------------------------------
box(UP, (0.290, 0.120, 0.072), (0.0, 0.004, -0.038), M["gunmetal"], bev=0.010)
box(UP, (0.250, 0.170, 0.024), (0.0, 0.010, 0.004), M["gunmetal"], bev=0.006)
for sx in (-1.0, 1.0):
    cyl(UP, 0.034, 0.080, (sx * 0.145, 0.004, -0.038), XR, M["gunmetal"], v=20)
    cyl(UP, 0.016, 0.094, (sx * 0.145, 0.004, -0.038), XR, M["steel"], v=14)

# --- Oleo-Zylinder ----------------------------------------------------------
cyl(UP, 0.076, 0.038, (0, 0, -0.092), material=M["steel"], v=32)
cyl(UP, 0.062, 0.300, (0, 0, -0.250), material=M["gunmetal"], v=32, bev=0.004)
cyl(UP, 0.068, 0.026, (0, 0, -0.386), material=M["steel"], v=32)
# Lenkkranz mit zwei Lenkzylindern — Bugraeder werden darueber gesteuert
cyl(UP, 0.082, 0.062, (0, 0, -0.432), material=M["gunmetal"], v=32, bev=0.005)
for sx in (-1.0, 1.0):
    cyl(UP, 0.020, 0.130, (sx * 0.070, -0.028, -0.432), (0, 0, 0), M["piston"], v=14)
    box(UP, (0.046, 0.044, 0.040), (sx * 0.070, -0.028, -0.372), M["gunmetal"], bev=0.005)
box(UP, (0.070, 0.046, 0.040), (0.0, 0.070, -0.470), M["gunmetal"], bev=0.006)   # Schereaufnahme

# --- Knickstrebe nach vorn (+Y) --------------------------------------------
KNEE = (0.118, 0.158, -0.330)
strut(UP, (0.0, 0.150, -0.048), KNEE, 0.026, 0.026, M["gunmetal"])
strut(UP, KNEE, (0.0, 0.052, -0.452), 0.024, 0.024, M["gunmetal"])
pin(UP, KNEE, 0.020, 0.062, M["steel"])
box(UP, (0.058, 0.055, 0.046), (0.0, 0.050, -0.456), M["gunmetal"], bev=0.006)

# --- Einzieh-Aktuator nach hinten (-Y) -------------------------------------
strut(UP, (0.0, -0.120, -0.036), (0.0, -0.082, -0.220), 0.042, 0.042, M["gunmetal"], bev=0.008)
strut(UP, (0.0, -0.084, -0.214), (0.0, -0.044, -0.372), 0.023, 0.023, M["piston"], bev=0.004)
pin(UP, (0.0, -0.120, -0.032), 0.017, 0.076, M["steel"])

# --- Rollscheinwerfer am Holm ----------------------------------------------
box(UP, (0.088, 0.052, 0.070), (0.0, 0.108, -0.235), M["gunmetal"], bev=0.008)
cyl(UP, 0.030, 0.016, (0.0, 0.136, -0.235), (radians(90), 0, 0), M["glass"], v=20)

# --- Kolben + Achse (SlideMesh) --------------------------------------------
cyl(SL, 0.044, 0.310, (0, 0, -0.640), material=M["piston"], v=32)
cyl(SL, 0.052, 0.040, (0, 0, -0.806), material=M["steel"], v=28)
box(SL, (0.070, 0.046, 0.040), (0.0, 0.062, -0.818), M["gunmetal"], bev=0.006)   # Schereaufnahme
box(SL, (0.116, 0.090, 0.120), (0.0, 0.0, Z_AX + 0.036), M["gunmetal"], bev=0.010)
cyl(SL, 0.034, 0.290, (0, 0, Z_AX), XR, M["gunmetal"], v=24)                     # Achse
for sx in (-1.0, 1.0):
    cyl(SL, 0.044, 0.022, (sx * 0.152, 0, Z_AX), XR, M["steel"], v=20)           # Achsmuttern

# --- Drehmomentschere (Zweigelenk, klappt beim Teleskopieren mit) ----------
SC_U = (0.070, -0.470)
SC_L = (0.062, -0.818)
SC_K = (0.146, -0.640)
L1 = math.dist(SC_K, SC_U)
L2 = math.dist(SC_L, SC_K)

def knie(dz):
    uy, uz = SC_U
    ly, lz = SC_L[0], SC_L[1] + dz
    vy, vz = ly - uy, lz - uz
    dist = math.hypot(vy, vz)
    a = (L1 * L1 - L2 * L2 + dist * dist) / (2.0 * dist)
    h = math.sqrt(max(L1 * L1 - a * a, 0.0))
    by, bz = uy + a * vy / dist, uz + a * vz / dist
    k1 = (by - h * vz / dist, bz + h * vy / dist)
    k2 = (by + h * vz / dist, bz - h * vy / dist)
    return k1 if k1[0] > k2[0] else k2

def winkel(p0, p1):
    return math.atan2(p1[1] - p0[1], p1[0] - p0[0])

W1_0 = winkel(SC_U, SC_K)
W2_0 = winkel(SC_K, SC_L)

strut(SCU, (0.0, SC_U[0], SC_U[1]), (0.0, SC_K[0], SC_K[1]), 0.022, 0.032, M["gunmetal"])
pin(SCU, (0.0, SC_U[0], SC_U[1]), 0.016, 0.062, M["steel"])
strut(SCL, (0.0, SC_K[0], SC_K[1]), (0.0, SC_L[0], SC_L[1]), 0.022, 0.032, M["gunmetal"])
pin(SCL, (0.0, SC_K[0], SC_K[1]), 0.019, 0.072, M["steel"])
pin(SCL, (0.0, SC_L[0], SC_L[1]), 0.016, 0.062, M["steel"])

# --- ZWEI Raeder in EINEM Knoten "Wheel" (AircraftBody dreht genau einen) ---
for sx in (-1.0, 1.0):
    cyl(WH, R_N, 0.108, (sx * DX, 0, Z_AX), XR, M["rubber"], v=44, bev=0.014)
    for yo in (-0.030, 0.0, 0.030):
        cyl(WH, R_N + 0.003, 0.022, (sx * DX + yo, 0, Z_AX), XR, M["rubber"], v=44)
    cyl(WH, 0.112, 0.118, (sx * DX, 0, Z_AX), XR, M["rim"], v=36)
    for so in (-0.056, 0.056):
        cyl(WH, 0.124, 0.014, (sx * DX + so, 0, Z_AX), XR, M["rim"], v=36)
    cyl(WH, 0.046, 0.132, (sx * DX, 0, Z_AX), XR, M["hub"], v=24)
    cyl(WH, 0.030, 0.146, (sx * DX, 0, Z_AX), XR, M["steel"], v=18)
    for i in range(8):
        a = i * (2.0 * math.pi / 8.0)
        cyl(WH, 0.008, 0.126, (sx * DX, math.cos(a) * 0.076, Z_AX + math.sin(a) * 0.076),
            XR, M["steel"], v=8)

# --- Zwei Klappen, seitlich angeschlagen (schwenken um Y) ------------------
# Das Bein klappt nach VORN und liegt eingefahren ueber 1.2 m weit vorne. Kurze,
# mittig sitzende Klappen lagen dadurch NEBEN statt UEBER dem Fahrwerk — also lang
# und nach vorn versetzt.
for bag, sx in ((DL, -1.0), (DRr, 1.0)):
    box(bag, (0.215, 1.080, 0.016), (sx * 0.218, 0.390, -0.010), M["dark"], bev=0.006)
    box(bag, (0.022, 1.040, 0.020), (sx * 0.302, 0.390, 0.006), M["gunmetal"], bev=0.004)
    for yy in (-0.080, 0.230, 0.540, 0.850):
        box(bag, (0.190, 0.022, 0.018), (sx * 0.220, yy, 0.006), M["gunmetal"], bev=0.004)

legmesh = join(sc, UP,  "LegMesh",   (0.0, 0.0, 0.0))
slide   = join(sc, SL,  "SlideMesh", (0.0, 0.0, 0.0))
wheel   = join(sc, WH,  "Wheel",     (0.0, 0.0, Z_AX))
scu     = join(sc, SCU, "ScissorU",  (0.0, SC_U[0], SC_U[1]))
scl     = join(sc, SCL, "ScissorL",  (0.0, SC_K[0], SC_K[1]))
doorL   = join(sc, DL,  "Door",      (-0.108, 0.0, -0.010))
doorR   = join(sc, DRr, "DoorR",     (0.108, 0.0, -0.010))
glaetten([legmesh, slide, wheel, scu, scl, doorL, doorR])

root   = empty(sc, "Root_nose")
pivot  = empty(sc, "Pivot_nose", root)
leg    = empty(sc, "Leg", pivot)
extend = empty(sc, "Extend", leg)
slider = empty(sc, "Slider", extend)
bpy.context.view_layer.update()
attach(legmesh, leg); attach(scu, leg); attach(scl, scu)      # scl: Kompensation noetig!
attach(slide, slider); attach(wheel, slider)
attach(doorL, root); attach(doorR, root)

act, strip, slots = anim_setup([pivot, doorL, doorR, slider, scu, scl])
key(pivot, "rotation_euler", 0, [(1, 0.0), (10, radians(22.0)), (24, radians(91.0)), (30, radians(88.0))])
# Klappen haengen ausgefahren offen nach unten und schliessen beim Einfahren buendig.
key(doorL, "rotation_euler", 1, [(1, radians(-95.0)), (9, radians(-98.0)), (30, 0.0)])
key(doorR, "rotation_euler", 1, [(1, radians(95.0)),  (9, radians(98.0)),  (30, 0.0)])

TELE_KEYS = [(1, 0.0), (6, 0.0), (14, TELE_N * 0.45), (26, TELE_N), (30, TELE_N)]
key(slider, "location", 2, TELE_KEYS)
scu_k, scl_k = [], []
for fr, dz in TELE_KEYS:
    k = knie(dz)
    l = (SC_L[0], SC_L[1] + dz)
    w1 = winkel(SC_U, k) - W1_0
    w2 = winkel(k, l) - W2_0
    scu_k.append((fr, w1))
    scl_k.append((fr, w2 - w1))            # lokal, da ScissorL Kind von ScissorU ist
key(scu, "rotation_euler", 0, scu_k)
key(scl, "rotation_euler", 0, scl_k)
weich(strip, slots)

export(sc, [root, pivot, leg, extend, slider, legmesh, slide, wheel, scu, scl, doorL, doorR],
       "wheel_nose.glb")

print("FERTIG — Spornrad Hoehe %.3f, Bugfahrwerk Hoehe %.3f" % (0.420, 1.100))
