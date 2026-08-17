## Baut das schwere Bomber-Hauptfahrwerk -> res://models/wheel_bomber.glb
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_wheel_bomber.py
##
## Deckt die schwere Propellerklasse ab: B-17, B-29, Lancaster, He 111, Halifax.
## EIN Bein, ZWEI grosse Raeder auf durchgehender Achse — das unterscheidet es vom
## Bugfahrwerk (dort sind die Doppelraeder klein und lenkbar) und von allen Jaeger-
## fahrwerken (Einzelrad). Dazu die typische A-Bock-Abstuetzung.
##
## STRUKTUR wie bei den uebrigen animierten Fahrwerken (Begruendung in build_wheel_f22.py):
##   Root_bomber -> Pivot_bomber(anim rot X) -> Leg(Node3D) -> LegMesh
##                                                          -> ScissorU -> ScissorL
##                                                          -> Extend -> Slider
##                                                                        -> SlideMesh + Wheel
## BEIDE Raeder sitzen in EINEM Knoten "Wheel": AircraftBody dreht beim Rollen genau
## einen Knoten um dessen lokale X-Achse — als getrennte Knoten wuerde nur eines drehen.
##
## SCHATTIERUNG: winkelabhaengiges Auto-Smooth (35 Grad) wie beim Hosenbein. Zylinder
## und Kolben laufen dadurch rund durch, Kanten an Trunnion und Streben bleiben scharf.
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


OUT = os.path.join(PROJEKT, "models/wheel_bomber.glb")

Z_AXLE = -1.010
R_TIRE = 0.240          # -> Aufstandspunkt z = -1.250
DX = 0.158              # halber Radabstand
TELE = 0.160
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

UP, SL, WH, SCU, SCL, DR = [], [], [], [], [], []


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


# ===================================================== OBERES BEIN (LegMesh)
# Trunnion: deutlich massiver als bei den Jaegerbeinen — dieses Fahrwerk traegt das
# Mehrfache und haengt an einer Motorgondel.
box(UP, (0.380, 0.150, 0.098), (0.0, 0.004, -0.052), M_gun, bev=0.012)
box(UP, (0.320, 0.215, 0.030), (0.0, 0.008, 0.006), M_gun, bev=0.008)
for sx in (-1.0, 1.0):
    cyl(UP, 0.046, 0.105, (sx * 0.190, 0.004, -0.052), XR, M_gun, v=24)
    cyl(UP, 0.022, 0.124, (sx * 0.190, 0.004, -0.052), XR, M_steel, v=18)

# Oleo-Zylinder, entsprechend dick
cyl(UP, 0.102, 0.048, (0, 0, -0.122), material=M_steel, v=44)
cyl(UP, 0.086, 0.400, (0, 0, -0.340), material=M_gun,   v=44, bev=0.005)
cyl(UP, 0.094, 0.034, (0, 0, -0.552), material=M_steel, v=44)
cyl(UP, 0.098, 0.062, (0, 0, -0.624), material=M_gun,   v=44, bev=0.006)   # Dichtungspaket
box(UP, (0.086, 0.056, 0.048), (0.0, 0.092, -0.560), M_gun, bev=0.007)     # Schereaufnahme

# A-BOCK: zwei Streben von den Trunnion-Enden schraeg herunter an den Zylinderfuss.
# Kennzeichen der schweren Vorkriegs-/WW2-Bomber und der auffaelligste Unterschied
# zu den schlanken Jaegerbeinen. Sie sitzen am ZYLINDER, nicht an der Achse — sonst
# muessten sie beim Teleskopieren mitwandern.
for sx in (-1.0, 1.0):
    strut(UP, (sx * 0.186, -0.030, -0.086), (sx * 0.052, -0.008, -0.585), 0.030, 0.030, M_gun)
    pin(UP, (sx * 0.186, -0.030, -0.082), 0.024, 0.070)
box(UP, (0.230, 0.060, 0.052), (0.0, -0.014, -0.598), M_gun, bev=0.008)    # Querjoch unten

# Knickstrebe nach vorn + Einzieh-Aktuator nach hinten
KNEE = (0.140, 0.212, -0.430)
strut(UP, (0.0, 0.198, -0.062), KNEE, 0.032, 0.032, M_gun)
strut(UP, KNEE, (0.0, 0.070, -0.590), 0.030, 0.030, M_gun)
pin(UP, KNEE, 0.026, 0.076)
strut(UP, (0.0, -0.170, -0.048), (0.0, -0.112, -0.300), 0.052, 0.052, M_gun, bev=0.010)
strut(UP, (0.0, -0.114, -0.292), (0.0, -0.060, -0.505), 0.030, 0.030, M_piston, bev=0.005)
pin(UP, (0.0, -0.170, -0.044), 0.022, 0.092)


# ================================================ SCHIEBENDER TEIL (SlideMesh)
cyl(SL, 0.062, 0.420, (0, 0, -0.830), material=M_piston, v=40)
cyl(SL, 0.072, 0.048, (0, 0, -1.028), material=M_steel, v=36)
box(SL, (0.086, 0.056, 0.048), (0.0, 0.086, -1.016), M_gun, bev=0.007)     # Schereaufnahme
box(SL, (0.170, 0.132, 0.180), (0.0, 0.0, Z_AXLE + 0.052), M_gun, bev=0.012)  # Achstraeger
cyl(SL, 0.052, 0.440, (0, 0, Z_AXLE), XR, M_gun, v=32)                     # durchgehende Achse
# Grosse Trommelbremsen zwischen Holm und Raedern — WW2 hat keine Scheibenpakete
for sx in (-1.0, 1.0):
    cyl(SL, 0.132, 0.048, (sx * 0.076, 0, Z_AXLE), XR, M_hub, v=36, bev=0.005)
    cyl(SL, 0.070, 0.020, (sx * 0.104, 0, Z_AXLE), XR, M_steel, v=24)
    strut(SL, (sx * 0.086, 0.104, Z_AXLE + 0.040), (sx * 0.030, 0.092, -0.900),
          0.013, 0.013, M_steel, bev=0.003)


# ============================================ DREHMOMENTSCHERE (Zweigelenk)
SC_U = (0.092, -0.560)
SC_L = (0.086, -1.016)
SC_K = (0.190, -0.790)
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
pin(SCU, (0.0, SC_U[0], SC_U[1]), 0.020, 0.076)
strut(SCL, (0.0, SC_K[0], SC_K[1]), (0.0, SC_L[0], SC_L[1]), 0.028, 0.040, M_gun)
pin(SCL, (0.0, SC_K[0], SC_K[1]), 0.024, 0.088)
pin(SCL, (0.0, SC_L[0], SC_L[1]), 0.020, 0.076)


# =========================================== ZWEI RAEDER in EINEM Knoten "Wheel"
for sx in (-1.0, 1.0):
    # Fase bewusst knapp: bei 0.034 verschliff Auto-Smooth die Reifenschulter komplett
    # und das Rad sah aus wie ein Marshmallow statt wie ein Reifen.
    cyl(WH, R_TIRE, 0.160, (sx * DX, 0, Z_AXLE), XR, M_rubber, v=56, bev=0.016)
    cyl(WH, 0.146, 0.168, (sx * DX, 0, Z_AXLE), XR, M_rim, v=48)
    for so in (-0.082, 0.082):
        cyl(WH, 0.162, 0.018, (sx * DX + so, 0, Z_AXLE), XR, M_rim, v=48)
    # Deckel und Erleichterungsloecher gehoeren auf die AUSSENseite (groesseres |x|).
    # Mit sx*(DX - 0.086) lagen sie zwischen den Raedern und waren unsichtbar.
    cyl(WH, 0.108, 0.020, (sx * (DX + 0.086), 0, Z_AXLE), XR, M_hub, v=40)
    for i in range(8):
        a = i * (2.0 * math.pi / 8.0)
        cyl(WH, 0.030, 0.030, (sx * (DX + 0.090), math.cos(a) * 0.070,
                               Z_AXLE + math.sin(a) * 0.070), XR, M_gun, v=16)
    cyl(WH, 0.058, 0.176, (sx * DX, 0, Z_AXLE), XR, M_hub, v=28)
    cyl(WH, 0.034, 0.190, (sx * DX, 0, Z_AXLE), XR, M_steel, v=20)


# ================================================================ KLAPPE
HINGE = Vector((-0.300, 0.0, -0.030))
PROF_D = [(0.255, 0.012), (0.230, -0.470), (0.020, -0.790), (-0.265, -0.620), (-0.290, 0.012)]
prism(DR, PROF_D, 0.0, 0.024, M_dark, "DoorSkin", bev=0.008)
inset = [(y * 0.87, (z + 0.39) * 0.87 - 0.39) for (y, z) in PROF_D]
prism(DR, inset, 0.016, 0.014, M_gun, "DoorLip", bev=0.005)
for zz in (-0.180, -0.420, -0.640):
    box(DR, (0.020, 0.400, 0.030), (0.026, -0.020, zz), M_gun, bev=0.005)
box(DR, (0.020, 0.046, 0.700), (0.026, 0.170, -0.370), M_gun, bev=0.005)
for yy in (0.170, -0.190):
    box(DR, (0.100, 0.050, 0.050), (0.060, yy, 0.004), M_gun, bev=0.006)
    cyl(DR, 0.017, 0.112, (0.060, yy, 0.004), XR, M_steel, v=16)
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


legmesh = join(UP,  "LegMesh",   (0.0, 0.0, 0.0))
slide   = join(SL,  "SlideMesh", (0.0, 0.0, 0.0))
wheel   = join(WH,  "Wheel",     (0.0, 0.0, Z_AXLE))     # Origin = Radachse -> rollt
scu     = join(SCU, "ScissorU",  (0.0, SC_U[0], SC_U[1]))
scl     = join(SCL, "ScissorL",  (0.0, SC_K[0], SC_K[1]))
door    = join(DR,  "Door",      tuple(HINGE))

for o in (legmesh, slide, wheel, scu, scl, door):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_auto_smooth(angle=radians(35))


def empty(name, parent=None):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    e.empty_display_size = 0.10
    e.location = (0, 0, 0)
    if parent: e.parent = parent
    return e


root   = empty("Root_bomber")
pivot  = empty("Pivot_bomber", root)
leg    = empty("Leg", pivot)
extend = empty("Extend", leg)
slider = empty("Slider", extend)
bpy.context.view_layer.update()


def attach(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


attach(legmesh, leg)
attach(scu, leg)
attach(scl, scu)          # ScissorU sitzt ausserhalb des Ursprungs -> Kompensation noetig
attach(slide, slider)
attach(wheel, slider)
attach(door, root)        # gondelfest, NICHT am Bein


# ------------------------------------------------------------- Animation
act = bpy.data.actions.new("retract")
strip = act.layers.new("Layer").strips.new(type='KEYFRAME')
slots = {}
for ob in (pivot, door, slider, scu, scl):
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


# Traeger Anlauf, dann zuegig: die Masse soll man dem Einfahren ansehen.
key(pivot, "rotation_euler", 0, [(1, 0.0), (12, radians(18.0)), (26, radians(90.0)), (30, radians(87.0))])
# Klappe haengt ausgefahren offen (0 Grad, so gebaut) und schwenkt beim Einfahren zu.
key(door, "rotation_euler", 1, [(1, 0.0), (8, radians(-5.0)), (22, radians(-34.0)), (30, radians(-88.0))])

TELE_KEYS = [(1, 0.0), (7, 0.0), (16, TELE * 0.42), (27, TELE), (30, TELE)]
key(slider, "location", 2, TELE_KEYS)
scu_k, scl_k = [], []
for fr, dz in TELE_KEYS:
    k = knie(dz)
    l = (SC_L[0], SC_L[1] + dz)
    w1 = winkel(SC_U, k) - W1_0
    w2 = winkel(k, l) - W2_0
    scu_k.append((fr, w1))
    scl_k.append((fr, w2 - w1))          # lokal, da ScissorL Kind von ScissorU ist
key(scu, "rotation_euler", 0, scu_k)
key(scl, "rotation_euler", 0, scl_k)

for s in slots.values():
    for fc in strip.channelbag(s).fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
            kp.easing = 'EASE_IN_OUT'

sc.frame_set(1)                                    # Ruhepose = ausgefahren

bpy.ops.object.select_all(action='DESELECT')
for o in (root, pivot, leg, extend, slider, legmesh, slide, wheel, scu, scl, door):
    o.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format='GLB', use_selection=True,
    export_yup=True, export_apply=False,
    export_animations=True, export_animation_mode='ACTIONS',
    export_frame_range=True, export_bake_animation=True,
)
print("EXPORTED", OUT)
print("Aufstand z=%.3f | Spurweite %.3f | Teleskop %.3f | Schere L1=%.3f L2=%.3f"
      % (Z_AXLE - R_TIRE, 2 * DX, TELE, L1, L2))
