## Baut das Fahrradfahrwerk -> res://models/wheel_tandem.glb + wheel_outrigger.glb
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_gear_tandem.py
##
## Deckt B-47, Harrier, U-2 und M-4 ab — Flugzeuge, deren Hauptfahrwerk NICHT in den
## Fluegeln sitzt, sondern hintereinander auf der Rumpfmittellinie.
##
## ZWEI TEILE, weil die Bauart nur als Paar funktioniert:
##   wheel_tandem     Mittellinien-Einheit. Traegt das GESAMTE Gewicht (zwei davon,
##                    vorn und hinten). Ohne Fluegel zum Abstuetzen wird sie QUER
##                    verstrebt statt laengs — das ist der sichtbare Unterschied zu
##                    allen anderen Hauptfahrwerken im Katalog.
##   wheel_outrigger  Stuetzrad an der Fluegelspitze. Traegt fast nichts (180 kg) und
##                    haelt die Maschine nur aufrecht. Duennes Bein, winziges Rad.
##
## Spielerisch ist das ein echter Bruch: mit zwei Mittellinien-Einheiten steht der Bau
## auf einer LINIE und kippt ohne Stuetzraeder seitlich weg.
##
## STRUKTUR beider Teile wie gehabt (Begruendung in build_wheel_f22.py):
##   Root -> Pivot(anim rot X) -> Leg(Node3D) -> LegMesh
##                                            -> [ScissorU -> ScissorL]  (nur Tandem)
##                                            -> Extend -> Slider -> SlideMesh + Wheel
##
## Achsen (glTF +Y up): Blender X -> Godot X (Radachse), Z -> Godot Y (oben),
##                      +Y -> Godot -Z (VORNE). Ruhepose Frame 1 = AUSGEFAHREN.
import bpy, bmesh, math
from math import radians
from mathutils import Vector

OUT_DIR = "/Users/konstantinkanzler/Projects/aviasembly/models/"
XR = (0, radians(90), 0)


# =========================================================== gemeinsame Helfer
def mat(name, col, rough, metal):
    m = bpy.data.materials.new(name); m.name = name; m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


def reset():
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
        "gunmetal": mat("gunmetal",(0.165, 0.175, 0.205), 0.42, 0.70),
        "piston":   mat("piston",  (0.62, 0.64, 0.68),    0.20, 0.94),
        "dark":     mat("dark",    (0.135, 0.140, 0.160), 0.52, 0.55),
    }
    return sc, M


def _bevel(o, width, segs=2, winkel=40):
    md = o.modifiers.new("bev", 'BEVEL')
    md.width, md.segments, md.limit_method = width, segs, 'ANGLE'
    md.angle_limit = radians(winkel)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=md.name)


def cyl(bag, r, depth, loc, rot=(0, 0, 0), material=None, v=36, bev=0.0):
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
    return cyl(bag, r, w, loc, XR, material, v=16)


def prism(sc, bag, prof, x0, thick, material, name, bev=0.006):
    me = bpy.data.meshes.new(name + "Mesh")
    bm = bmesh.new()
    f = bm.faces.new([bm.verts.new((x0, y, z)) for (y, z) in prof])
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.x -= thick
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    o.data.materials.append(material)
    bpy.context.view_layer.objects.active = o
    if bev > 0: _bevel(o, bev, 2, 30)
    bag.append(o); return o


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


def glaetten(objs):
    for o in objs:
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_auto_smooth(angle=radians(35))


def empty(sc, name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    e.empty_display_size = 0.08
    e.location = loc
    if parent: e.parent = parent
    return e


def attach(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


def anim_setup(objs):
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
    return strip, slots


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
    sc.frame_set(1)
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


def schere(SC_U, SC_L, SC_K):
    """Zweigelenk-Kinematik der Drehmomentschere (wie bei den uebrigen Beinen)."""
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

    return knie, L1, L2


def winkel(p0, p1):
    return math.atan2(p1[1] - p0[1], p1[0] - p0[0])


# ============================================================================
#  1) MITTELLINIEN-EINHEIT — traegt alles, QUER verstrebt
# ============================================================================
sc, M = reset()

Z_AXLE = -0.860
R_TIRE = 0.190          # -> Aufstandspunkt z = -1.050
DX = 0.118
TELE = 0.150

UP, SL, WH, SCU, SCL, DL, DRr = [], [], [], [], [], [], []

# QUERTRAEGER: sitzt auf dem Rumpfboden und ist deutlich breiter als hoch. Weil kein
# Fluegel zum Abstuetzen da ist, geht die gesamte Seitenlast hier hinein.
box(UP, (0.470, 0.150, 0.070), (0.0, 0.004, -0.040), M["gunmetal"], bev=0.010)
box(UP, (0.390, 0.220, 0.028), (0.0, 0.008, 0.006), M["gunmetal"], bev=0.008)
for sx in (-1.0, 1.0):
    cyl(UP, 0.042, 0.095, (sx * 0.222, 0.004, -0.040), XR, M["gunmetal"], v=24)
    cyl(UP, 0.020, 0.112, (sx * 0.222, 0.004, -0.040), XR, M["steel"], v=18)

cyl(UP, 0.092, 0.042, (0, 0, -0.104), material=M["steel"], v=40)
cyl(UP, 0.076, 0.330, (0, 0, -0.282), material=M["gunmetal"], v=40, bev=0.004)
cyl(UP, 0.082, 0.030, (0, 0, -0.462), material=M["steel"], v=40)
box(UP, (0.082, 0.052, 0.046), (0.0, 0.086, -0.436), M["gunmetal"], bev=0.006)

# QUER-V statt Laengsstrebe — der auffaelligste Unterschied zu den Fluegelfahrwerken
for sx in (-1.0, 1.0):
    strut(UP, (sx * 0.218, 0.010, -0.074), (sx * 0.048, 0.002, -0.470), 0.030, 0.030, M["gunmetal"])
    pin(UP, (sx * 0.218, 0.010, -0.070), 0.022, 0.070, M["steel"])
box(UP, (0.320, 0.052, 0.044), (0.0, 0.004, -0.300), M["gunmetal"], bev=0.007)   # Querriegel

# Einzieh-Aktuator nach hinten
strut(UP, (0.0, -0.152, -0.046), (0.0, -0.100, -0.244), 0.048, 0.048, M["gunmetal"], bev=0.009)
strut(UP, (0.0, -0.102, -0.236), (0.0, -0.056, -0.418), 0.027, 0.027, M["piston"], bev=0.004)
pin(UP, (0.0, -0.152, -0.042), 0.020, 0.086, M["steel"])

# --- Kolben + Achse ---
cyl(SL, 0.056, 0.360, (0, 0, -0.640), material=M["piston"], v=36)
cyl(SL, 0.064, 0.044, (0, 0, -0.812), material=M["steel"], v=32)
box(SL, (0.082, 0.052, 0.046), (0.0, 0.082, -0.800), M["gunmetal"], bev=0.006)
box(SL, (0.140, 0.104, 0.140), (0.0, 0.0, Z_AXLE + 0.046), M["gunmetal"], bev=0.010)
cyl(SL, 0.040, 0.330, (0, 0, Z_AXLE), XR, M["gunmetal"], v=28)
for sx in (-1.0, 1.0):
    cyl(SL, 0.100, 0.036, (sx * 0.070, 0, Z_AXLE), XR, M["hub"], v=32, bev=0.004)
    cyl(SL, 0.050, 0.024, (sx * 0.172, 0, Z_AXLE), XR, M["steel"], v=22)

# --- Drehmomentschere ---
SC_U, SC_L, SC_K = (0.086, -0.436), (0.082, -0.800), (0.176, -0.614)
knie, L1, L2 = schere(SC_U, SC_L, SC_K)
W1_0, W2_0 = winkel(SC_U, SC_K), winkel(SC_K, SC_L)
strut(SCU, (0.0, SC_U[0], SC_U[1]), (0.0, SC_K[0], SC_K[1]), 0.026, 0.038, M["gunmetal"])
pin(SCU, (0.0, SC_U[0], SC_U[1]), 0.019, 0.072, M["steel"])
strut(SCL, (0.0, SC_K[0], SC_K[1]), (0.0, SC_L[0], SC_L[1]), 0.026, 0.038, M["gunmetal"])
pin(SCL, (0.0, SC_K[0], SC_K[1]), 0.023, 0.084, M["steel"])
pin(SCL, (0.0, SC_L[0], SC_L[1]), 0.019, 0.072, M["steel"])

# --- Raeder ---
for sx in (-1.0, 1.0):
    cyl(WH, R_TIRE, 0.126, (sx * DX, 0, Z_AXLE), XR, M["rubber"], v=52, bev=0.016)
    cyl(WH, 0.122, 0.134, (sx * DX, 0, Z_AXLE), XR, M["rim"], v=44)
    for so in (-0.066, 0.066):
        cyl(WH, 0.136, 0.015, (sx * DX + so, 0, Z_AXLE), XR, M["rim"], v=44)
    cyl(WH, 0.088, 0.018, (sx * (DX + 0.072), 0, Z_AXLE), XR, M["hub"], v=36)
    for i in range(7):
        a = i * (2.0 * math.pi / 7.0)
        cyl(WH, 0.022, 0.026, (sx * (DX + 0.076), math.cos(a) * 0.058,
                               Z_AXLE + math.sin(a) * 0.058), XR, M["gunmetal"], v=14)
    cyl(WH, 0.050, 0.146, (sx * DX, 0, Z_AXLE), XR, M["hub"], v=26)

# --- Zwei Klappen ---
for bag, sx in ((DL, -1.0), (DRr, 1.0)):
    box(bag, (0.230, 1.000, 0.018), (sx * 0.238, 0.330, -0.012), M["dark"], bev=0.006)
    box(bag, (0.022, 0.960, 0.022), (sx * 0.330, 0.330, 0.006), M["gunmetal"], bev=0.004)
    for yy in (-0.080, 0.200, 0.480, 0.750):
        box(bag, (0.206, 0.024, 0.020), (sx * 0.240, yy, 0.006), M["gunmetal"], bev=0.004)

legmesh = join(sc, UP,  "LegMesh",   (0.0, 0.0, 0.0))
slide   = join(sc, SL,  "SlideMesh", (0.0, 0.0, 0.0))
wheel   = join(sc, WH,  "Wheel",     (0.0, 0.0, Z_AXLE))
scu     = join(sc, SCU, "ScissorU",  (0.0, SC_U[0], SC_U[1]))
scl     = join(sc, SCL, "ScissorL",  (0.0, SC_K[0], SC_K[1]))
doorL   = join(sc, DL,  "Door",      (-0.122, 0.0, -0.012))
doorR   = join(sc, DRr, "DoorR",     (0.122, 0.0, -0.012))
glaetten([legmesh, slide, wheel, scu, scl, doorL, doorR])

root   = empty(sc, "Root_tandem")
pivot  = empty(sc, "Pivot_tandem", root)
leg    = empty(sc, "Leg", pivot)
extend = empty(sc, "Extend", leg)
slider = empty(sc, "Slider", extend)
bpy.context.view_layer.update()
attach(legmesh, leg); attach(scu, leg); attach(scl, scu)
attach(slide, slider); attach(wheel, slider)
attach(doorL, root); attach(doorR, root)

strip, slots = anim_setup([pivot, doorL, doorR, slider, scu, scl])
key(pivot, "rotation_euler", 0, [(1, 0.0), (11, radians(19.0)), (25, radians(90.0)), (30, radians(87.0))])
key(doorL, "rotation_euler", 1, [(1, radians(-95.0)), (9, radians(-98.0)), (30, 0.0)])
key(doorR, "rotation_euler", 1, [(1, radians(95.0)),  (9, radians(98.0)),  (30, 0.0)])
TK = [(1, 0.0), (7, 0.0), (16, TELE * 0.44), (27, TELE), (30, TELE)]
key(slider, "location", 2, TK)
su, sl_ = [], []
for fr, dz in TK:
    k = knie(dz)
    w1 = winkel(SC_U, k) - W1_0
    w2 = winkel(k, (SC_L[0], SC_L[1] + dz)) - W2_0
    su.append((fr, w1)); sl_.append((fr, w2 - w1))
key(scu, "rotation_euler", 0, su)
key(scl, "rotation_euler", 0, sl_)
weich(strip, slots)

export(sc, [root, pivot, leg, extend, slider, legmesh, slide, wheel, scu, scl, doorL, doorR],
       "wheel_tandem.glb")


# ============================================================================
#  2) STUETZRAD — duenn, winziges Rad, klappt nach HINTEN in die Fluegelspitze
# ============================================================================
sc, M = reset()

Z_AXLE = -0.772
R_TIRE = 0.084          # -> Aufstandspunkt z = -0.856
TELE = 0.055

UP, SL, WH, DR = [], [], [], []

box(UP, (0.128, 0.180, 0.032), (0.0, 0.0, -0.015), M["gunmetal"], bev=0.006)
box(UP, (0.076, 0.104, 0.058), (0.0, 0.0, -0.052), M["gunmetal"], bev=0.006)
# Sehr schlankes Bein — es traegt nur die Seitenlast, nicht das Gewicht
cyl(UP, 0.030, 0.040, (0, 0, -0.096), material=M["steel"], v=28)
cyl(UP, 0.025, 0.400, (0, 0, -0.300), material=M["gunmetal"], v=28, bev=0.003)
cyl(UP, 0.030, 0.022, (0, 0, -0.508), material=M["steel"], v=28)
# Knickstrebe nach vorn, damit das duenne Bein nicht knickt
strut(UP, (0.0, 0.104, -0.052), (0.0, 0.030, -0.330), 0.016, 0.016, M["gunmetal"])
pin(UP, (0.0, 0.104, -0.048), 0.012, 0.052, M["steel"])
strut(UP, (0.0, -0.096, -0.050), (0.0, -0.028, -0.290), 0.026, 0.026, M["gunmetal"], bev=0.005)
strut(UP, (0.0, -0.030, -0.284), (0.0, -0.016, -0.404), 0.015, 0.015, M["piston"], bev=0.003)

cyl(SL, 0.018, 0.300, (0, 0, -0.660), material=M["piston"], v=24)
cyl(SL, 0.024, 0.028, (0, 0, -0.796 + 0.088), material=M["steel"], v=24)
box(SL, (0.070, 0.052, 0.070), (0.0, 0.0, Z_AXLE + 0.034), M["gunmetal"], bev=0.007)
cyl(SL, 0.014, 0.088, (0, 0, Z_AXLE), XR, M["gunmetal"], v=18)

cyl(WH, R_TIRE, 0.052, (0, 0, Z_AXLE), XR, M["rubber"], v=36, bev=0.010)
cyl(WH, 0.050, 0.058, (0, 0, Z_AXLE), XR, M["rim"], v=28)
cyl(WH, 0.018, 0.066, (0, 0, Z_AXLE), XR, M["hub"], v=16)

# Kleine Verkleidung, wie sie an Fluegelspitzen ueblich ist
box(DR, (0.130, 0.300, 0.016), (0.0, -0.060, -0.010), M["dark"], bev=0.006)
box(DR, (0.020, 0.270, 0.020), (0.0, -0.060, 0.006), M["gunmetal"], bev=0.004)

legmesh = join(sc, UP, "LegMesh",   (0.0, 0.0, 0.0))
slide   = join(sc, SL, "SlideMesh", (0.0, 0.0, 0.0))
wheel   = join(sc, WH, "Wheel",     (0.0, 0.0, Z_AXLE))
# Scharnier an die VORDERkante: mit dem Ursprung in der Klappenmitte schwenkte
# die Vorderkante beim Oeffnen nach OBEN statt dass die Klappe herunterhaengt.
door    = join(sc, DR, "Door",      (0.0, 0.090, -0.010))
glaetten([legmesh, slide, wheel, door])

root   = empty(sc, "Root_outrigger")
pivot  = empty(sc, "Pivot_outrigger", root)
leg    = empty(sc, "Leg", pivot)
extend = empty(sc, "Extend", leg)
slider = empty(sc, "Slider", extend)
bpy.context.view_layer.update()
attach(legmesh, leg); attach(slide, slider); attach(wheel, slider); attach(door, root)

strip, slots = anim_setup([pivot, door, slider])
# NEGATIVE Drehung: dieses Bein klappt nach HINTEN in die Fluegelspitze, nicht nach
# vorn wie die uebrigen — vorn ist an der Spitze kein Platz.
key(pivot, "rotation_euler", 0, [(1, 0.0), (11, radians(-20.0)), (25, radians(-88.0)), (30, radians(-85.0))])
key(door,  "rotation_euler", 0, [(1, radians(84.0)), (8, radians(88.0)), (30, 0.0)])
key(slider, "location", 2, [(1, 0.0), (7, 0.0), (17, TELE * 0.5), (27, TELE), (30, TELE)])
weich(strip, slots)

export(sc, [root, pivot, leg, extend, slider, legmesh, slide, wheel, door],
       "wheel_outrigger.glb")

print("FERTIG — Tandem Aufstand -1.050 | Stuetzrad Aufstand -0.856")
