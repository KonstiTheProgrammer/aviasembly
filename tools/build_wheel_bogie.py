## Baut das Vierrad-Drehgestell -> res://models/wheel_bogie.glb
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_wheel_bogie.py
##
## Deckt die schweren Strahlflugzeuge ab: B-52, Tu-95, KC-135, C-5, An-124.
##
## ZWEI NEUERUNGEN gegenueber allen bisherigen Fahrwerken:
##
##  1) KIPPENDES DREHGESTELL. Der Achstraeger haengt in einem Querlager unter dem
##     Holm und kippt um X. Das ist eine Bewegungsart, die es im Projekt noch nicht
##     gab — alle anderen Fahrwerke bestehen aus Klappen, Teleskopieren und Scheren.
##     Ruhelage ist WAAGERECHT, damit alle vier Raeder den Boden beruehren; beim
##     Einfahren kippt der Traeger hoch und macht das Paket kuerzer.
##
##  2) ZWEI RAD-KNOTEN ("Wheel" vorn, "Wheel2" hinten). AircraftBody dreht jeden
##     Rad-Knoten um DESSEN lokale X-Achse. Steckten alle vier Raeder in einem Knoten,
##     wuerde das vordere Paar beim Rollen um die HINTERE Achse kreisen statt sich um
##     die eigene zu drehen. Dafuer wurden FlightController (sammelt "Wheel".."Wheel4")
##     und AircraftBody (haengt je Knoten einen Eintrag an) erweitert.
##
## STRUKTUR:
##   Root_bogie -> Pivot_bogie(anim rot X) -> Leg(Node3D) -> LegMesh
##                                                        -> ScissorU -> ScissorL
##                                                        -> Extend -> Slider(anim Teleskop)
##                                                                      -> SlideMesh
##                                                                      -> Bogie(anim rot X)
##                                                                           -> BogieMesh
##                                                                           -> Wheel + Wheel2
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


OUT = os.path.join(PROJEKT, "models/wheel_bogie.glb")

Z_AXLE = -1.055         # beide Achsen
R_TIRE = 0.185          # -> Aufstandspunkt z = -1.240
Z_BOGIE = -0.990        # Querlager, 6.5 cm ueber den Achsen
YB = 0.215              # halber Achsabstand (Radstand 0.43)
DX = 0.132              # halber Radabstand je Achse
TELE = 0.150
KIPP = radians(22.0)    # Kippwinkel des Traegers beim Einfahren
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

M_rubber = mat("rubber",  (0.048, 0.048, 0.056), 0.90, 0.0)
M_rim    = mat("rim",     (0.38, 0.40, 0.45),    0.34, 0.82)
M_hub    = mat("hub",     (0.17, 0.17, 0.19),    0.45, 0.70)
M_steel  = mat("steel",   (0.55, 0.57, 0.61),    0.22, 0.92)
M_gun    = mat("gunmetal",(0.165, 0.175, 0.205), 0.42, 0.70)
M_piston = mat("piston",  (0.62, 0.64, 0.68),    0.20, 0.94)
M_dark   = mat("dark",    (0.135, 0.140, 0.160), 0.52, 0.55)

UP, SL, BG, WV, WH2, SCU, SCL, DR = [], [], [], [], [], [], [], []


def _bevel(o, width, segs=2, winkel=40):
    md = o.modifiers.new("bev", 'BEVEL')
    md.width, md.segments, md.limit_method = width, segs, 'ANGLE'
    md.angle_limit = radians(winkel)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=md.name)


def cyl(bag, r, depth, loc, rot=(0, 0, 0), material=None, v=40, bev=0.0):
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


def strut(bag, p0, p1, w, t, material, bev=0.006):
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


def rad(bag, x, y):
    """Ein komplettes Rad an (x, y, Z_AXLE). Nabendeckel zeigt nach AUSSEN."""
    a = 1.0 if x >= 0 else -1.0
    cyl(bag, R_TIRE, 0.126, (x, y, Z_AXLE), XR, M_rubber, v=52, bev=0.014)
    cyl(bag, 0.112, 0.134, (x, y, Z_AXLE), XR, M_rim, v=44)
    for so in (-0.064, 0.064):
        cyl(bag, 0.124, 0.015, (x + so, y, Z_AXLE), XR, M_rim, v=44)
    cyl(bag, 0.084, 0.018, (x + a * 0.070, y, Z_AXLE), XR, M_hub, v=36)
    for i in range(7):
        w = i * (2.0 * math.pi / 7.0)
        cyl(bag, 0.024, 0.026, (x + a * 0.074, y + math.cos(w) * 0.054,
                                Z_AXLE + math.sin(w) * 0.054), XR, M_gun, v=14)
    cyl(bag, 0.046, 0.142, (x, y, Z_AXLE), XR, M_hub, v=24)
    cyl(bag, 0.026, 0.154, (x, y, Z_AXLE), XR, M_steel, v=18)


# ===================================================== OBERES BEIN (LegMesh)
box(UP, (0.360, 0.150, 0.096), (0.0, 0.004, -0.052), M_gun, bev=0.012)
box(UP, (0.300, 0.220, 0.030), (0.0, 0.008, 0.006), M_gun, bev=0.008)
for sx in (-1.0, 1.0):
    cyl(UP, 0.046, 0.100, (sx * 0.180, 0.004, -0.052), XR, M_gun, v=24)
    cyl(UP, 0.022, 0.120, (sx * 0.180, 0.004, -0.052), XR, M_steel, v=18)

cyl(UP, 0.106, 0.046, (0, 0, -0.122), material=M_steel, v=44)
cyl(UP, 0.090, 0.420, (0, 0, -0.348), material=M_gun,   v=44, bev=0.005)
cyl(UP, 0.098, 0.034, (0, 0, -0.572), material=M_steel, v=44)
cyl(UP, 0.102, 0.062, (0, 0, -0.646), material=M_gun,   v=44, bev=0.006)
box(UP, (0.090, 0.058, 0.048), (0.0, 0.096, -0.580), M_gun, bev=0.007)

# Knickstrebe nach vorn + Einzieh-Aktuator nach hinten
KNEE = (0.146, 0.222, -0.446)
strut(UP, (0.0, 0.206, -0.064), KNEE, 0.034, 0.034, M_gun)
strut(UP, KNEE, (0.0, 0.074, -0.612), 0.032, 0.032, M_gun)
pin(UP, KNEE, 0.027, 0.080)
strut(UP, (0.0, -0.176, -0.050), (0.0, -0.116, -0.312), 0.054, 0.054, M_gun, bev=0.010)
strut(UP, (0.0, -0.118, -0.304), (0.0, -0.062, -0.524), 0.031, 0.031, M_piston, bev=0.005)
pin(UP, (0.0, -0.176, -0.046), 0.023, 0.096)
# Seitliche Abstuetzung
for sx in (-1.0, 1.0):
    strut(UP, (sx * 0.176, -0.026, -0.088), (sx * 0.056, -0.008, -0.600), 0.026, 0.026, M_gun)


# ================================================ SCHIEBENDER TEIL (SlideMesh)
cyl(SL, 0.066, 0.430, (0, 0, -0.850), material=M_piston, v=40)
cyl(SL, 0.076, 0.046, (0, 0, -1.052 + 0.098), material=M_steel, v=36)
box(SL, (0.090, 0.058, 0.048), (0.0, 0.090, -0.958), M_gun, bev=0.007)     # Schereaufnahme
# QUERLAGER: hier haengt der Achstraeger und kippt darin um X.
box(SL, (0.190, 0.130, 0.110), (0.0, 0.0, Z_BOGIE + 0.028), M_gun, bev=0.012)
cyl(SL, 0.038, 0.230, (0, 0, Z_BOGIE), XR, M_steel, v=28)                  # Lagerbolzen


# ============================================== ACHSTRAEGER (BogieMesh)
# Der Balken zwischen den beiden Achsen. Kippt als Ganzes um den Lagerbolzen.
box(BG, (0.122, 0.560, 0.104), (0.0, 0.0, Z_BOGIE - 0.006), M_gun, bev=0.012)
for sx in (-1.0, 1.0):
    box(BG, (0.024, 0.500, 0.060), (sx * 0.074, 0.0, Z_BOGIE - 0.020), M_gun, bev=0.006)
cyl(BG, 0.056, 0.150, (0, 0, Z_BOGIE), XR, M_gun, v=28)                    # Lagerauge
for sy in (-1.0, 1.0):
    yy = sy * YB
    box(BG, (0.130, 0.110, 0.130), (0.0, yy, Z_AXLE + 0.040), M_gun, bev=0.010)  # Achsbock
    cyl(BG, 0.040, 0.400, (0, yy, Z_AXLE), XR, M_gun, v=28)                      # Achse
    for sx in (-1.0, 1.0):                                                       # Bremsen
        cyl(BG, 0.096, 0.040, (sx * 0.062, yy, Z_AXLE), XR, M_hub, v=32, bev=0.004)
        cyl(BG, 0.052, 0.018, (sx * 0.084, yy, Z_AXLE), XR, M_steel, v=22)
# Bremsleitungen laengs am Balken
for sx in (-1.0, 1.0):
    strut(BG, (sx * 0.090, 0.230, Z_BOGIE - 0.030), (sx * 0.090, -0.230, Z_BOGIE - 0.030),
          0.011, 0.011, M_steel, bev=0.003)


# ============================================ DREHMOMENTSCHERE (Zweigelenk)
SC_U = (0.096, -0.580)
SC_L = (0.090, -0.958)
SC_K = (0.194, -0.780)
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

strut(SCU, (0.0, SC_U[0], SC_U[1]), (0.0, SC_K[0], SC_K[1]), 0.028, 0.040, M_gun)
pin(SCU, (0.0, SC_U[0], SC_U[1]), 0.021, 0.078)
strut(SCL, (0.0, SC_K[0], SC_K[1]), (0.0, SC_L[0], SC_L[1]), 0.028, 0.040, M_gun)
pin(SCL, (0.0, SC_K[0], SC_K[1]), 0.025, 0.090)
pin(SCL, (0.0, SC_L[0], SC_L[1]), 0.021, 0.078)


# ===================================== VIER RAEDER in ZWEI Knoten (vorn / hinten)
for sx in (-1.0, 1.0):
    rad(WV,  sx * DX,  YB)
    rad(WH2, sx * DX, -YB)


# ================================================================ KLAPPE
HINGE = Vector((-0.290, 0.0, -0.030))
PROF_D = [(0.300, 0.012), (0.270, -0.480), (0.020, -0.800), (-0.300, -0.630), (-0.320, 0.012)]
prism(DR, PROF_D, 0.0, 0.024, M_dark, "DoorSkin", bev=0.008)
inset = [(y * 0.87, (z + 0.40) * 0.87 - 0.40) for (y, z) in PROF_D]
prism(DR, inset, 0.016, 0.014, M_gun, "DoorLip", bev=0.005)
for zz in (-0.190, -0.440, -0.660):
    box(DR, (0.020, 0.460, 0.030), (0.026, -0.020, zz), M_gun, bev=0.005)
box(DR, (0.020, 0.048, 0.720), (0.026, 0.190, -0.380), M_gun, bev=0.005)
for yy in (0.190, -0.210):
    box(DR, (0.100, 0.050, 0.050), (0.058, yy, 0.004), M_gun, bev=0.006)
    cyl(DR, 0.017, 0.110, (0.058, yy, 0.004), XR, M_steel, v=16)
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


legmesh  = join(UP,  "LegMesh",   (0.0, 0.0, 0.0))
slide    = join(SL,  "SlideMesh", (0.0, 0.0, 0.0))
bogmesh  = join(BG,  "BogieMesh", (0.0, 0.0, Z_BOGIE))
wheel_v  = join(WV,  "Wheel",     (0.0,  YB, Z_AXLE))   # Origin = VORDERE Achse
wheel_h  = join(WH2, "Wheel2",    (0.0, -YB, Z_AXLE))   # Origin = HINTERE Achse
scu      = join(SCU, "ScissorU",  (0.0, SC_U[0], SC_U[1]))
scl      = join(SCL, "ScissorL",  (0.0, SC_K[0], SC_K[1]))
door     = join(DR,  "Door",      tuple(HINGE))

for o in (legmesh, slide, bogmesh, wheel_v, wheel_h, scu, scl, door):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_auto_smooth(angle=radians(35))


def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    e.empty_display_size = 0.10
    e.location = loc
    if parent: e.parent = parent
    return e


root   = empty("Root_bogie")
pivot  = empty("Pivot_bogie", root)
leg    = empty("Leg", pivot)
extend = empty("Extend", leg)
slider = empty("Slider", extend)
bogie  = empty("Bogie", slider, (0.0, 0.0, Z_BOGIE))     # sitzt im Querlager
bpy.context.view_layer.update()


def attach(child, parent):
    """Parenten OHNE Versatz — bei Eltern ausserhalb des Ursprungs (ScissorU, Bogie)
    wuerde Blender das Kind sonst um deren Transform verschieben."""
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


attach(legmesh, leg)
attach(scu, leg)
attach(scl, scu)
attach(slide, slider)
attach(bogmesh, bogie)
attach(wheel_v, bogie)
attach(wheel_h, bogie)
attach(door, root)


# ------------------------------------------------------------- Animation
act = bpy.data.actions.new("retract")
strip = act.layers.new("Layer").strips.new(type='KEYFRAME')
slots = {}
for ob in (pivot, door, slider, bogie, scu, scl):
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


key(pivot, "rotation_euler", 0, [(1, 0.0), (12, radians(17.0)), (26, radians(90.0)), (30, radians(87.0))])
key(door,  "rotation_euler", 1, [(1, 0.0), (8, radians(-5.0)), (22, radians(-34.0)), (30, radians(-88.0))])

# DREHGESTELL: Ruhelage waagerecht (alle vier Raeder am Boden), kippt beim Einfahren
# frueh hoch — noch bevor das Bein richtig klappt, so wie es die Hydraulik am Original
# auch macht, damit das Paket in den Schacht passt.
key(bogie, "rotation_euler", 0, [(1, 0.0), (5, 0.0), (15, KIPP * 0.75), (24, KIPP), (30, KIPP)])

TELE_KEYS = [(1, 0.0), (7, 0.0), (16, TELE * 0.42), (27, TELE), (30, TELE)]
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
for o in (root, pivot, leg, extend, slider, bogie, legmesh, slide, bogmesh,
          wheel_v, wheel_h, scu, scl, door):
    o.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format='GLB', use_selection=True,
    export_yup=True, export_apply=False,
    export_animations=True, export_animation_mode='ACTIONS',
    export_frame_range=True, export_bake_animation=True,
)
print("EXPORTED", OUT)
print("Aufstand z=%.3f | Radstand %.3f | Spur %.3f | Kippung %.0f Grad | Teleskop %.3f"
      % (Z_AXLE - R_TIRE, 2 * YB, 2 * DX, math.degrees(KIPP), TELE))
