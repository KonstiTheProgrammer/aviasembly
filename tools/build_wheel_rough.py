## Baut das Rohfeld-Fahrwerk -> res://models/wheel_rough.glb
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_wheel_rough.py
##
## Deckt die Ostblock-Familie ab: MiG-21, MiG-29, Su-27, Su-25 — Maschinen, die von
## unbefestigten Pisten operieren sollten.
##
## NEUE MECHANIK: HEBELFEDERUNG statt Teleskopbein. Das Rad sitzt am Ende einer
## Schwinge, die am Holmfuss angelenkt ist; gefedert wird ueber einen SCHRAEG
## liegenden Daempfer zwischen Holm und Schwinge. Alle bisherigen Fahrwerke im
## Projekt federn dagegen teleskopisch im Holm selbst (Slider-Knoten). Diese Bauart
## haelt Stoesse von grobem Untergrund besser aus — genau darum sitzt sie an diesen
## Flugzeugen.
##
## Der Daempfer muss der Schwinge FOLGEN: dreht die Schwinge, wandert sein unterer
## Anlenkpunkt mit. Winkel und Laenge werden darum pro Keyframe gerechnet (wie die
## Drehmomentschere bei den anderen Beinen), und er ist zweiteilig — Zylinder dreht,
## Kolben faehrt darin ein.
##
## STRUKTUR:
##   Root_rough -> Pivot_rough(anim rot X) -> Leg(Node3D) -> LegMesh
##                                                        -> Extend(Editor-Beinlaenge)
##                                                             -> Arm(anim rot X)
##                                                             |    -> ArmMesh + Wheel
##                                                             -> DampU(anim rot X)
##                                                                  -> DampL(anim pos Z)
## KEIN "Slider": es wird ja gerade NICHT teleskopiert.
##
## Der obere Daempferanschluss sitzt bewusst TIEF am Holm (z = -0.400). PartCatalog.
## _leg_stretched verschiebt alles unterhalb seiner Trennlinie starr nach unten — der
## Anschluss wandert damit gemeinsam mit dem Extend-Knoten, und Daempfer und Schwinge
## bleiben auch bei verlaengertem Bein zusammen.
##
## Achsen (glTF +Y up): Blender X -> Godot X (Radachse), Z -> Godot Y (oben),
##                      +Y -> Godot -Z (VORNE). Ruhepose Frame 1 = AUSGEFAHREN.
import bpy, bmesh, math
from math import radians
from mathutils import Vector

OUT = "/Users/konstantinkanzler/Projects/aviasembly/models/wheel_rough.glb"

Z_AXLE = -0.905
R_TIRE = 0.215          # dicker Niederdruckreifen -> Aufstandspunkt z = -1.120
A = (0.175, -0.815)     # Anlenkpunkt der Schwinge (y, z)
AX = (-0.090, Z_AXLE)   # Radachse (y, z) — HINTER dem Anlenkpunkt: nachlaufende Schwinge
DU = (0.045, -0.400)    # oberer Daempferanschluss am Holm
DL0 = (A[0] + 0.55 * (AX[0] - A[0]), A[1] + 0.55 * (AX[1] - A[1]))   # unterer, auf der Schwinge
SCHWENK = radians(-28.0)   # so weit klappt die Schwinge beim Einfahren hoch
XR = (0, radians(90), 0)

for o in list(bpy.data.objects):    bpy.data.objects.remove(o, do_unlink=True)
for m in list(bpy.data.meshes):     bpy.data.meshes.remove(m)
for mt in list(bpy.data.materials): bpy.data.materials.remove(mt)
for a in list(bpy.data.actions):    bpy.data.actions.remove(a)

sc = bpy.context.scene
sc.render.fps = 30
sc.frame_start, sc.frame_end = 1, 30


def mat(name, col, rough, metal):
    m = bpy.data.materials.new(name); m.name = name; m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m

M_rubber = mat("rubber",  (0.052, 0.052, 0.060), 0.92, 0.0)
M_rim    = mat("rim",     (0.33, 0.32, 0.28),    0.42, 0.70)   # Ostblock, aber gedaempft
M_hub    = mat("hub",     (0.17, 0.17, 0.19),    0.45, 0.70)
M_steel  = mat("steel",   (0.55, 0.57, 0.61),    0.22, 0.92)
M_gun    = mat("gunmetal",(0.165, 0.175, 0.205), 0.42, 0.70)
M_piston = mat("piston",  (0.62, 0.64, 0.68),    0.20, 0.94)
M_dark   = mat("dark",    (0.135, 0.140, 0.160), 0.52, 0.55)

UP, ARM, WH, D_U, D_L, DR = [], [], [], [], [], []


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


def pin(bag, loc, r, w, material=M_steel):
    return cyl(bag, r, w, loc, XR, material, v=16)


def prism(bag, prof, x0, thick, material, name, bev=0.006):
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


# ===================================================== HOLM (LegMesh)
box(UP, (0.290, 0.130, 0.080), (0.0, 0.004, -0.044), M_gun, bev=0.010)
box(UP, (0.250, 0.180, 0.026), (0.0, 0.008, 0.006), M_gun, bev=0.006)
for sx in (-1.0, 1.0):
    cyl(UP, 0.036, 0.086, (sx * 0.146, 0.004, -0.044), XR, M_gun, v=22)
    cyl(UP, 0.017, 0.100, (sx * 0.146, 0.004, -0.044), XR, M_steel, v=16)

# Der Holm ist hier ein reines TRAGROHR ohne Kolben — gefedert wird in der Schwinge.
cyl(UP, 0.072, 0.038, (0, 0, -0.096), material=M_steel, v=40)
cyl(UP, 0.058, 0.560, (0, 0, -0.370), material=M_gun,   v=40, bev=0.004)
cyl(UP, 0.066, 0.030, (0, 0, -0.664), material=M_steel, v=40)
# Anlenkbock der Schwinge am Holmfuss
box(UP, (0.128, 0.150, 0.100), (0.0, 0.090, -0.790), M_gun, bev=0.010)
# Oberer Daempferanschluss: TIEF gesetzt, damit er beim Verlaengern des Beins mit dem
# starr verschobenen Fussbereich wandert (siehe Kopfkommentar).
box(UP, (0.100, 0.086, 0.070), (0.0, DU[0], DU[1]), M_gun, bev=0.008)
pin(UP, (0.0, DU[0], DU[1]), 0.019, 0.116)

# Knickstrebe nach hinten + Einzieh-Aktuator nach vorn
KNEE = (0.112, -0.176, -0.360)
strut(UP, (0.0, -0.150, -0.056), KNEE, 0.026, 0.026, M_gun)
strut(UP, KNEE, (0.0, -0.052, -0.548), 0.024, 0.024, M_gun)
pin(UP, KNEE, 0.021, 0.062)
strut(UP, (0.0, 0.140, -0.048), (0.0, 0.086, -0.250), 0.042, 0.042, M_gun, bev=0.008)
strut(UP, (0.0, 0.088, -0.242), (0.0, 0.052, -0.420), 0.024, 0.024, M_piston, bev=0.004)
pin(UP, (0.0, 0.140, -0.044), 0.018, 0.078)


# ============================================== SCHWINGE (ArmMesh) + Rad
# Origin kommt spaeter auf den Anlenkpunkt A.
for sx in (-1.0, 1.0):
    strut(ARM, (sx * 0.062, A[0], A[1]), (sx * 0.062, AX[0], AX[1]), 0.030, 0.072, M_gun, bev=0.008)
pin(ARM, (0.0, A[0], A[1]), 0.026, 0.150)
box(ARM, (0.170, 0.080, 0.078), (0.0, DL0[0], DL0[1]), M_gun, bev=0.008)   # Daempferauge
pin(ARM, (0.0, DL0[0], DL0[1]), 0.019, 0.190)
cyl(ARM, 0.034, 0.230, (0, AX[0], AX[1]), XR, M_gun, v=26)                 # Achse
for sx in (-1.0, 1.0):
    cyl(ARM, 0.086, 0.030, (sx * 0.088, AX[0], AX[1]), XR, M_hub, v=30)    # Bremse

# SCHMUTZFAENGER: das Erkennungsmerkmal dieser Familie. Sitzt AN DER SCHWINGE und
# schwenkt darum mit dem Rad mit — er soll Steine und Schlamm abfangen, die der
# Reifen hochschleudert.
# Als sauberer Bogen ueber der OBEREN Radhaelfte. Die erste Fassung war eine frei
# gesetzte Punktfolge, die bis unter die Achse herunterreichte — das sah aus wie ein
# Hufeisen um das Rad statt wie ein Schild darueber.
def bogen(r, a0, a1, n):
    return [(AX[0] + math.cos(math.radians(a)) * r, AX[1] + math.sin(math.radians(a)) * r)
            for a in [a0 + (a1 - a0) * i / n for i in range(n + 1)]]

SF = bogen(0.256, -6.0, 132.0, 16) + list(reversed(bogen(0.232, -6.0, 132.0, 16)))
prism(ARM, SF, 0.098, 0.196, M_dark, "Schmutzfaenger", bev=0.008)
for sx in (-1.0, 1.0):                                                     # Halter
    strut(ARM, (sx * 0.070, AX[0] - 0.020, AX[1] + 0.070),
          (sx * 0.098, AX[0] - 0.030, AX[1] + 0.250), 0.014, 0.020, M_gun, bev=0.004)

# Rad: dicker Niederdruckreifen mit grober Laufflaeche
cyl(WH, R_TIRE, 0.168, (0, AX[0], AX[1]), XR, M_rubber, v=52, bev=0.020)
for yo in (-0.052, 0.0, 0.052):
    cyl(WH, R_TIRE + 0.005, 0.026, (yo, AX[0], AX[1]), XR, M_rubber, v=52)
cyl(WH, 0.112, 0.176, (0, AX[0], AX[1]), XR, M_rim, v=44)
for so in (-0.086, 0.086):
    cyl(WH, 0.128, 0.016, (so, AX[0], AX[1]), XR, M_rim, v=44)
cyl(WH, 0.052, 0.188, (0, AX[0], AX[1]), XR, M_hub, v=26)
cyl(WH, 0.030, 0.200, (0, AX[0], AX[1]), XR, M_steel, v=20)
for i in range(6):
    w = i * (2.0 * math.pi / 6.0)
    cyl(WH, 0.026, 0.030, (-0.092, AX[0] + math.cos(w) * 0.082,
                           AX[1] + math.sin(w) * 0.082), XR, M_gun, v=16)


# ==================================================== DAEMPFER (zweiteilig)
def dreh(p, theta):
    """Punkt (y,z) um den Schwingen-Anlenkpunkt A drehen."""
    vy, vz = p[0] - A[0], p[1] - A[1]
    c, s = math.cos(theta), math.sin(theta)
    return (A[0] + vy * c - vz * s, A[1] + vy * s + vz * c)


def damp_lage(theta):
    """Winkel und Laenge des Daempfers bei Schwingenstellung theta.
    Der Knoten wird um X gedreht; lokal -Z zeigt dann laengs des Daempfers."""
    l = dreh(DL0, theta)
    dy, dz = l[0] - DU[0], l[1] - DU[1]
    return math.atan2(dy, -dz), math.hypot(dy, dz)


A0, LEN0 = damp_lage(0.0)

# Geometrie laengs der lokalen -Z-Achse bauen, Origin bei DU.
cyl(D_U, 0.044, 0.250, (0, 0, -0.118), material=M_gun, v=32, bev=0.005)
cyl(D_U, 0.050, 0.028, (0, 0, -0.238), material=M_steel, v=32)
box(D_U, (0.086, 0.070, 0.056), (0.0, 0.0, -0.016), M_gun, bev=0.007)
cyl(D_L, 0.029, 0.300, (0, 0, -LEN0 + 0.150), material=M_piston, v=28)
box(D_L, (0.080, 0.066, 0.052), (0.0, 0.0, -LEN0 + 0.010), M_gun, bev=0.006)


# ================================================================ KLAPPE
HINGE = Vector((-0.250, 0.0, -0.026))
PROF_D = [(0.230, 0.010), (0.208, -0.420), (0.018, -0.700), (-0.238, -0.548), (-0.258, 0.010)]
prism(DR, PROF_D, 0.0, 0.022, M_dark, "DoorSkin", bev=0.008)
inset = [(y * 0.87, (z + 0.35) * 0.87 - 0.35) for (y, z) in PROF_D]
prism(DR, inset, 0.014, 0.012, M_gun, "DoorLip", bev=0.004)
for zz in (-0.160, -0.380, -0.570):
    box(DR, (0.018, 0.350, 0.026), (0.022, -0.016, zz), M_gun, bev=0.004)
for yy in (0.150, -0.170):
    box(DR, (0.090, 0.044, 0.044), (0.052, yy, 0.002), M_gun, bev=0.005)
    cyl(DR, 0.015, 0.100, (0.052, yy, 0.002), XR, M_steel, v=14)
for o in DR:
    o.location = o.location + HINGE


def join(bag, name, origin):
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


legmesh = join(UP,  "LegMesh",  (0.0, 0.0, 0.0))
armmesh = join(ARM, "ArmMesh",  (0.0, A[0], A[1]))
wheel   = join(WH,  "Wheel",    (0.0, AX[0], AX[1]))
dampu   = join(D_U, "DampU",    (0.0, 0.0, 0.0))
dampl   = join(D_L, "DampL",    (0.0, 0.0, 0.0))
door    = join(DR,  "Door",     tuple(HINGE))

for o in (legmesh, armmesh, wheel, dampu, dampl, door):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_auto_smooth(angle=radians(35))


def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    e.empty_display_size = 0.08
    e.location = loc
    if parent: e.parent = parent
    return e


root   = empty("Root_rough")
pivot  = empty("Pivot_rough", root)
leg    = empty("Leg", pivot)
extend = empty("Extend", leg)
arm    = empty("Arm", extend, (0.0, A[0], A[1]))
bpy.context.view_layer.update()


def attach(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


attach(legmesh, leg)
attach(armmesh, arm)
attach(wheel, arm)
attach(door, root)
# Daempfer: Zylinder haengt am Extend-Knoten (wandert also mit der Beinlaenge),
# Kolben als dessen Kind.
dampu.parent = extend
dampu.location = (0.0, DU[0], DU[1])
dampu.rotation_mode = 'XYZ'
dampu.rotation_euler = (A0, 0.0, 0.0)
dampl.parent = dampu
dampl.location = (0.0, 0.0, 0.0)
bpy.context.view_layer.update()


# ------------------------------------------------------------- Animation
act = bpy.data.actions.new("retract")
strip = act.layers.new("Layer").strips.new(type='KEYFRAME')
slots = {}
for ob in (pivot, door, arm, dampu, dampl):
    ob.animation_data_create()
    ob.animation_data.action = act
    s = act.slots.new('OBJECT', ob.name)
    ob.animation_data.action_slot = s
    strip.channelbag(s, ensure=True)
    slots[ob] = s


def key(o, path, idx, frames):
    o.rotation_mode = 'XYZ'
    for fr, val in frames:
        vec = list(getattr(o, path))
        vec[idx] = val
        setattr(o, path, vec)
        o.keyframe_insert(data_path=path, index=idx, frame=fr)


key(pivot, "rotation_euler", 0, [(1, 0.0), (11, radians(20.0)), (25, radians(90.0)), (30, radians(87.0))])
key(door,  "rotation_euler", 1, [(1, 0.0), (8, radians(-6.0)), (22, radians(-32.0)), (30, radians(-88.0))])

# Schwinge klappt beim Einfahren hoch — und der Daempfer folgt exakt.
ARM_KEYS = [(1, 0.0), (7, 0.0), (17, SCHWENK * 0.55), (27, SCHWENK), (30, SCHWENK)]
key(arm, "rotation_euler", 0, ARM_KEYS)
du_k, dl_k = [], []
for fr, th in ARM_KEYS:
    a, ln = damp_lage(th)
    du_k.append((fr, a))
    dl_k.append((fr, LEN0 - ln))       # Daempfer wird kuerzer -> Kolben faehrt ein
key(dampu, "rotation_euler", 0, du_k)
key(dampl, "location", 2, dl_k)

for s in slots.values():
    for fc in strip.channelbag(s).fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
            kp.easing = 'EASE_IN_OUT'

sc.frame_set(1)                                    # Ruhepose = ausgefahren

bpy.ops.object.select_all(action='DESELECT')
for o in (root, pivot, leg, extend, arm, legmesh, armmesh, wheel, dampu, dampl, door):
    o.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format='GLB', use_selection=True,
    export_yup=True, export_apply=False,
    export_animations=True, export_animation_mode='ACTIONS',
    export_frame_range=True, export_bake_animation=True,
)
print("EXPORTED", OUT)
print("Aufstand z=%.3f | Schwinge %.3f m | Daempfer %.3f -> %.3f m | Schwenk %.0f Grad"
      % (AX[1] - R_TIRE, math.dist(A, AX), LEN0, damp_lage(SCHWENK)[1], math.degrees(SCHWENK)))
