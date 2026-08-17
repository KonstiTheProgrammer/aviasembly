## Baut das Traeger-Bugfahrwerk -> res://models/wheel_carrier.glb
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_wheel_carrier.py
##
## Deckt die komplette Traegerflotte ab: F-4, F-14, F/A-18, A-4, A-6, Rafale M.
##
## KENNZEICHEN gegenueber dem normalen Bugfahrwerk (wheel_nose):
##  - KATAPULTSTANGE als eigener animierter Knoten. Ausgefahren zeigt sie nach vorn
##    unten zum Schlitten, beim Einfahren legt sie sich an den Holm. Ohne eigenen
##    Knoten muesste sie starr abstehen und wuerde im Schacht durch die Struktur ragen.
##  - RUECKHALTEKLINKE hinten an der Gabel — haelt das Flugzeug beim Aufziehen der
##    Katapultspannung fest und reisst beim Schuss ab.
##  - Deutlich laengerer Federweg (18 statt 15 cm): Traegerlandungen sind gesetzte
##    Bruchlandungen, nicht Ausschweben.
##
## STRUKTUR (Begruendung in build_wheel_f22.py):
##   Root_carrier -> Pivot_carrier(anim rot X) -> Leg(Node3D) -> LegMesh
##                                                            -> ScissorU -> ScissorL
##                                                            -> Extend -> Slider(anim Teleskop)
##                                                                          -> SlideMesh
##                                                                          -> LaunchBar(anim rot X)
##                                                                          -> Wheel
##
## Achsen (glTF +Y up): Blender X -> Godot X (Radachse), Z -> Godot Y (oben),
##                      +Y -> Godot -Z (VORNE). Ruhepose Frame 1 = AUSGEFAHREN.
import bpy, bmesh, math
from math import radians
from mathutils import Vector
import os

# PROJEKTWURZEL AUS DEM SKRIPTORT statt eines absoluten Pfads. Hier standen fest
# verdrahtete Pfade, und zehn Skripte zeigten noch auf die alte Projektkopie unter
# ~/Downloads/aviasembly — sie schrieben ihr Modell also dorthin, wo das Spiel es nicht
# mehr laedt. Der Fehler faellt nicht auf: Blender meldet einen erfolgreichen Export,
# im Spiel aendert sich nur nichts.
PROJEKT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


OUT = os.path.join(PROJEKT, "models/wheel_carrier.glb")

Z_AXLE = -1.000
R_TIRE = 0.180          # -> Aufstandspunkt z = -1.180
DX = 0.098              # halber Radabstand
TELE = 0.180
Z_BAR = Z_AXLE + 0.022  # Drehpunkt der Katapultstange
Y_BAR = 0.084
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

M_rubber = mat("rubber",  (0.050, 0.050, 0.058), 0.88, 0.0)
M_rim    = mat("rim",     (0.40, 0.42, 0.47),    0.30, 0.85)
M_hub    = mat("hub",     (0.17, 0.17, 0.19),    0.45, 0.70)
M_steel  = mat("steel",   (0.55, 0.57, 0.61),    0.22, 0.92)
M_gun    = mat("gunmetal",(0.165, 0.175, 0.205), 0.40, 0.72)
M_piston = mat("piston",  (0.62, 0.64, 0.68),    0.20, 0.94)
M_dark   = mat("dark",    (0.135, 0.140, 0.160), 0.52, 0.55)
M_glass  = mat("glass",   (0.86, 0.88, 0.92),    0.08, 0.20)

UP, SL, WH, SCU, SCL, LB, DL, DRr = [], [], [], [], [], [], [], []


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


# ===================================================== OBERES BEIN (LegMesh)
box(UP, (0.310, 0.132, 0.082), (0.0, 0.004, -0.044), M_gun, bev=0.010)
box(UP, (0.268, 0.185, 0.026), (0.0, 0.010, 0.006), M_gun, bev=0.006)
for sx in (-1.0, 1.0):
    cyl(UP, 0.038, 0.088, (sx * 0.156, 0.004, -0.044), XR, M_gun, v=22)
    cyl(UP, 0.018, 0.104, (sx * 0.156, 0.004, -0.044), XR, M_steel, v=16)

# Oleo — dicker als am Landfahrwerk, Traegerlandungen sind gesetzte Bruchlandungen
cyl(UP, 0.086, 0.042, (0, 0, -0.100), material=M_steel, v=40)
cyl(UP, 0.070, 0.320, (0, 0, -0.270), material=M_gun,   v=40, bev=0.004)
cyl(UP, 0.076, 0.028, (0, 0, -0.446), material=M_steel, v=40)
# Lenkkranz mit zwei Lenkzylindern
cyl(UP, 0.092, 0.068, (0, 0, -0.496), material=M_gun, v=40, bev=0.005)
for sx in (-1.0, 1.0):
    cyl(UP, 0.022, 0.140, (sx * 0.078, -0.030, -0.496), (0, 0, 0), M_piston, v=16)
    box(UP, (0.050, 0.048, 0.044), (sx * 0.078, -0.030, -0.430), M_gun, bev=0.005)
box(UP, (0.076, 0.050, 0.044), (0.0, 0.078, -0.538), M_gun, bev=0.006)   # Schereaufnahme

# Knickstrebe nach vorn + Einzieh-Aktuator nach hinten
KNEE = (0.126, 0.170, -0.360)
strut(UP, (0.0, 0.162, -0.056), KNEE, 0.028, 0.028, M_gun)
strut(UP, KNEE, (0.0, 0.058, -0.500), 0.026, 0.026, M_gun)
pin(UP, KNEE, 0.022, 0.066)
strut(UP, (0.0, -0.132, -0.042), (0.0, -0.090, -0.238), 0.046, 0.046, M_gun, bev=0.008)
strut(UP, (0.0, -0.092, -0.230), (0.0, -0.048, -0.404), 0.025, 0.025, M_piston, bev=0.004)
pin(UP, (0.0, -0.132, -0.038), 0.018, 0.080)

# Anflug-Lichter am Holm: beim Traegeranflug zeigen sie dem Landeoffizier die Anstellung
box(UP, (0.094, 0.056, 0.076), (0.0, 0.116, -0.250), M_gun, bev=0.008)
for zo in (-0.020, 0.020):
    cyl(UP, 0.017, 0.014, (0.0, 0.146, -0.250 + zo), (radians(90), 0, 0), M_glass, v=18)


# ================================================ SCHIEBENDER TEIL (SlideMesh)
cyl(SL, 0.050, 0.360, (0, 0, -0.716), material=M_piston, v=40)
cyl(SL, 0.058, 0.044, (0, 0, -0.892), material=M_steel, v=32)
box(SL, (0.076, 0.050, 0.044), (0.0, 0.074, -0.902), M_gun, bev=0.006)     # Schereaufnahme
box(SL, (0.124, 0.096, 0.130), (0.0, 0.0, Z_AXLE + 0.042), M_gun, bev=0.010)
cyl(SL, 0.036, 0.272, (0, 0, Z_AXLE), XR, M_gun, v=26)                     # Achse
for sx in (-1.0, 1.0):
    cyl(SL, 0.046, 0.022, (sx * 0.142, 0, Z_AXLE), XR, M_steel, v=22)
# Lagerbock der Katapultstange
box(SL, (0.108, 0.062, 0.056), (0.0, Y_BAR, Z_BAR), M_gun, bev=0.007)
pin(SL, (0.0, Y_BAR, Z_BAR), 0.020, 0.116)
# RUECKHALTEKLINKE hinten: haelt gegen die Katapultspannung und reisst beim Schuss ab
strut(SL, (0.0, -0.070, Z_AXLE + 0.030), (0.0, -0.196, Z_AXLE - 0.048), 0.030, 0.030, M_gun)
box(SL, (0.062, 0.066, 0.050), (0.0, -0.212, Z_AXLE - 0.058), M_steel, bev=0.008)
cyl(SL, 0.026, 0.030, (0.0, -0.236, Z_AXLE - 0.062), (0, radians(90), 0), M_steel, v=20)


# ================================================= KATAPULTSTANGE (LaunchBar)
# In AUSGEFAHRENER Stellung gebaut: zeigt nach vorn unten zum Schlitten im Deck.
# Die Stange muss bis KNAPP UEBERS DECK reichen (Aufstandspunkt liegt bei
# Z_AXLE - R_TIRE), sonst greift sie im Bild ueber den Schlitten hinweg und liest
# sich als Stummel statt als Katapultstange.
BAR_T = (0.0, 0.610, Z_AXLE - R_TIRE + 0.038)     # Spitze, 3.8 cm ueber Deck
for sx in (-1.0, 1.0):
    strut(LB, (sx * 0.032, Y_BAR, Z_BAR), (sx * 0.020, BAR_T[1], BAR_T[2]),
          0.024, 0.038, M_gun, bev=0.005)
box(LB, (0.098, 0.076, 0.052), (0.0, 0.226, Z_AXLE - 0.048), M_gun, bev=0.006)   # Spreize
box(LB, (0.086, 0.062, 0.044), (0.0, 0.420, Z_AXLE - 0.106), M_gun, bev=0.005)   # zweite Spreize
# Schuh am Ende, der in den Katapultschlitten greift
box(LB, (0.142, 0.092, 0.048), (0.0, BAR_T[1] + 0.016, BAR_T[2] - 0.012), M_steel, bev=0.008)
cyl(LB, 0.024, 0.158, (0.0, BAR_T[1] + 0.034, BAR_T[2] - 0.030), XR, M_steel, v=22)
pin(LB, (0.0, Y_BAR, Z_BAR), 0.023, 0.108)


# ============================================ DREHMOMENTSCHERE (Zweigelenk)
SC_U = (0.078, -0.538)
SC_L = (0.074, -0.902)
SC_K = (0.158, -0.716)
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

strut(SCU, (0.0, SC_U[0], SC_U[1]), (0.0, SC_K[0], SC_K[1]), 0.024, 0.034, M_gun)
pin(SCU, (0.0, SC_U[0], SC_U[1]), 0.017, 0.066)
strut(SCL, (0.0, SC_K[0], SC_K[1]), (0.0, SC_L[0], SC_L[1]), 0.024, 0.034, M_gun)
pin(SCL, (0.0, SC_K[0], SC_K[1]), 0.021, 0.078)
pin(SCL, (0.0, SC_L[0], SC_L[1]), 0.017, 0.066)


# ============================================= ZWEI RAEDER in EINEM Knoten
for sx in (-1.0, 1.0):
    cyl(WH, R_TIRE, 0.110, (sx * DX, 0, Z_AXLE), XR, M_rubber, v=52, bev=0.014)
    for yo in (-0.030, 0.0, 0.030):
        cyl(WH, R_TIRE + 0.003, 0.022, (sx * DX + yo, 0, Z_AXLE), XR, M_rubber, v=52)
    cyl(WH, 0.116, 0.120, (sx * DX, 0, Z_AXLE), XR, M_rim, v=44)
    for so in (-0.058, 0.058):
        cyl(WH, 0.128, 0.014, (sx * DX + so, 0, Z_AXLE), XR, M_rim, v=44)
    cyl(WH, 0.048, 0.134, (sx * DX, 0, Z_AXLE), XR, M_hub, v=26)
    cyl(WH, 0.030, 0.148, (sx * DX, 0, Z_AXLE), XR, M_steel, v=20)
    for i in range(8):
        a = i * (2.0 * math.pi / 8.0)
        cyl(WH, 0.009, 0.128, (sx * DX, math.cos(a) * 0.078,
                               Z_AXLE + math.sin(a) * 0.078), XR, M_steel, v=10)


# ============================================================ ZWEI KLAPPEN
for bag, sx in ((DL, -1.0), (DRr, 1.0)):
    box(bag, (0.220, 1.020, 0.018), (sx * 0.222, 0.360, -0.012), M_dark, bev=0.006)
    box(bag, (0.022, 0.980, 0.022), (sx * 0.308, 0.360, 0.006), M_gun, bev=0.004)
    for yy in (-0.060, 0.230, 0.520, 0.790):
        box(bag, (0.196, 0.024, 0.020), (sx * 0.224, yy, 0.006), M_gun, bev=0.004)


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


legmesh = join(UP,  "LegMesh",   (0.0, 0.0, 0.0))
slide   = join(SL,  "SlideMesh", (0.0, 0.0, 0.0))
wheel   = join(WH,  "Wheel",     (0.0, 0.0, Z_AXLE))
scu     = join(SCU, "ScissorU",  (0.0, SC_U[0], SC_U[1]))
scl     = join(SCL, "ScissorL",  (0.0, SC_K[0], SC_K[1]))
bar     = join(LB,  "LaunchBar", (0.0, Y_BAR, Z_BAR))     # Origin = Drehpunkt
doorL   = join(DL,  "Door",      (-0.112, 0.0, -0.012))
doorR   = join(DRr, "DoorR",     (0.112, 0.0, -0.012))

for o in (legmesh, slide, wheel, scu, scl, bar, doorL, doorR):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_auto_smooth(angle=radians(35))


def empty(name, parent=None):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    e.empty_display_size = 0.08
    e.location = (0, 0, 0)
    if parent: e.parent = parent
    return e


root   = empty("Root_carrier")
pivot  = empty("Pivot_carrier", root)
leg    = empty("Leg", pivot)
extend = empty("Extend", leg)
slider = empty("Slider", extend)
bpy.context.view_layer.update()


def attach(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


attach(legmesh, leg)
attach(scu, leg)
attach(scl, scu)
attach(slide, slider)
attach(bar, slider)
attach(wheel, slider)
attach(doorL, root)
attach(doorR, root)


# ------------------------------------------------------------- Animation
act = bpy.data.actions.new("retract")
strip = act.layers.new("Layer").strips.new(type='KEYFRAME')
slots = {}
for ob in (pivot, doorL, doorR, slider, bar, scu, scl):
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


key(pivot, "rotation_euler", 0, [(1, 0.0), (10, radians(21.0)), (24, radians(91.0)), (30, radians(88.0))])
key(doorL, "rotation_euler", 1, [(1, radians(-95.0)), (9, radians(-98.0)), (30, 0.0)])
key(doorR, "rotation_euler", 1, [(1, radians(95.0)),  (9, radians(98.0)),  (30, 0.0)])

# KATAPULTSTANGE: legt sich als ERSTES an den Holm — sie ragt ausgefahren so weit nach
# vorn, dass sie beim Klappen sonst durch die eigene Struktur fahren wuerde.
key(bar, "rotation_euler", 0, [(1, 0.0), (9, radians(38.0)), (17, radians(62.0)), (30, radians(62.0))])

TELE_KEYS = [(1, 0.0), (6, 0.0), (15, TELE * 0.45), (26, TELE), (30, TELE)]
key(slider, "location", 2, TELE_KEYS)
scu_k, scl_k = [], []
for fr, dz in TELE_KEYS:
    k = knie(dz)
    l = (SC_L[0], SC_L[1] + dz)
    w1 = winkel(SC_U, k) - W1_0
    w2 = winkel(k, l) - W2_0
    scu_k.append((fr, w1))
    scl_k.append((fr, w2 - w1))
key(scu, "rotation_euler", 0, scu_k)
key(scl, "rotation_euler", 0, scl_k)

for s in slots.values():
    for fc in strip.channelbag(s).fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
            kp.easing = 'EASE_IN_OUT'

sc.frame_set(1)                                    # Ruhepose = ausgefahren

bpy.ops.object.select_all(action='DESELECT')
for o in (root, pivot, leg, extend, slider, legmesh, slide, wheel, scu, scl, bar, doorL, doorR):
    o.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format='GLB', use_selection=True,
    export_yup=True, export_apply=False,
    export_animations=True, export_animation_mode='ACTIONS',
    export_frame_range=True, export_bake_animation=True,
)
print("EXPORTED", OUT)
print("Aufstand z=%.3f | Stange reicht %.3f m nach vorn | Teleskop %.3f"
      % (Z_AXLE - R_TIRE, BAR_T[1], TELE))
