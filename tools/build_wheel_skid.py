## Baut die Spornkufe -> res://models/wheel_skid.glb
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_wheel_skid.py
##
## Deckt die echte Frühzeit ab: Blériot XI, Fokker E.III, Sopwith Camel, SE.5a — alles
## vor der Zeit, in der man hinten ein Rad montierte. Auf Grasplaetzen schleift die
## Kufe einfach mit und bremst beim Ausrollen sogar.
##
## ERSTES TEIL OHNE RAD-KNOTEN. Alle anderen Fahrwerke bringen einen Knoten "Wheel"
## mit, den AircraftBody beim Rollen dreht. Eine Kufe dreht sich nicht — sie hat
## darum bewusst KEINEN. FlightController sammelt dann eine leere Rad-Liste und
## AircraftBody haengt keinen Roll-Eintrag an; das faellt sauber durch, seit die
## Rad-Suche fuer das Drehgestell auf mehrere Knoten umgestellt wurde.
##
## Ebenfalls ohne: Pivot und Animation (1915 fuhr nichts ein) sowie Slider. Gefedert
## wird ueber ein GUMMISEIL zwischen Kufenarm und Pylon — dieselbe Technik wie an den
## Doppeldecker-Raedern des Projekts.
##
## STRUKTUR:
##   Root_skid -> Leg(Node3D) -> LegMesh    Anschluss, Pylon, Gummiseil-Wicklung
##                            -> Extend     Editor-Beinlaenge
##                                 -> SkidMesh   Kufenarm samt Stahlschuh
##
## Achsen (glTF +Y up): Blender X -> Godot X, Z -> Godot Y (oben),
##                      +Y -> Godot -Z (VORNE).
import bpy, bmesh, math
from math import radians
from mathutils import Vector

OUT = "/Users/konstantinkanzler/Projects/aviasembly/models/wheel_skid.glb"

Z_UNTEN = -0.360        # Aufstandspunkt der Kufe
DREH = (0.062, -0.182)  # Anlenkpunkt des Kufenarms (y, z)
XR = (0, radians(90), 0)

for o in list(bpy.data.objects):    bpy.data.objects.remove(o, do_unlink=True)
for m in list(bpy.data.meshes):     bpy.data.meshes.remove(m)
for mt in list(bpy.data.materials): bpy.data.materials.remove(mt)
for a in list(bpy.data.actions):    bpy.data.actions.remove(a)

sc = bpy.context.scene


def mat(name, col, rough, metal):
    m = bpy.data.materials.new(name); m.name = name; m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m

# "wood" ist ein neuer Materialname und steht NICHT in PartCatalog.PAINT_MATS — die
# Kufe bleibt also naturbelassen, auch wenn der Spieler die Zelle umlackiert.
M_wood  = mat("wood",    (0.324, 0.216, 0.124), 0.72, 0.0)
M_gun   = mat("gunmetal",(0.165, 0.175, 0.205), 0.42, 0.70)
M_steel = mat("steel",   (0.52, 0.54, 0.58),    0.28, 0.90)
M_rub   = mat("rubber",  (0.108, 0.098, 0.086), 0.88, 0.0)   # Gummiseil

UP, SK = [], []


def _bevel(o, width, segs=2, winkel=40):
    md = o.modifiers.new("bev", 'BEVEL')
    md.width, md.segments, md.limit_method = width, segs, 'ANGLE'
    md.angle_limit = radians(winkel)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=md.name)


def cyl(bag, r, depth, loc, rot=(0, 0, 0), material=None, v=28, bev=0.0):
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


def strut(bag, p0, p1, w, t, material, bev=0.004):
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


def prism(bag, prof, x0, thick, material, name, bev=0.005):
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


# ===================================================== PYLON (LegMesh)
box(UP, (0.112, 0.190, 0.026), (0.0, 0.0, -0.013), M_gun, bev=0.005)      # Anschlussplatte
box(UP, (0.062, 0.086, 0.040), (0.0, 0.010, -0.042), M_gun, bev=0.005)
# Der Pylon ist bewusst kurz: die Kufe soll dicht am Rumpf sitzen.
strut(UP, (0.0, 0.030, -0.052), (0.0, DREH[0], DREH[1]), 0.030, 0.038, M_gun)
strut(UP, (0.0, -0.052, -0.046), (0.0, 0.028, -0.164), 0.020, 0.020, M_gun)   # Strebe
box(UP, (0.086, 0.058, 0.048), (0.0, DREH[0], DREH[1]), M_gun, bev=0.006)     # Lagerbock
cyl(UP, 0.013, 0.100, (0.0, DREH[0], DREH[1]), XR, M_steel, v=16)             # Bolzen
# Oberer Anschlag, gegen den das Gummiseil zieht
box(UP, (0.070, 0.040, 0.030), (0.0, -0.062, -0.070), M_gun, bev=0.005)
cyl(UP, 0.011, 0.084, (0.0, -0.062, -0.070), XR, M_steel, v=14)


# ============================================== KUFE (SkidMesh) + Gummiseil
# Laengsprofil: vorn am Lager dick, nach hinten schlanker, Spitze leicht hochgezogen —
# so schleift sie im Gras, ohne sich einzugraben.
KUFE = [(DREH[0] + 0.020, DREH[1] + 0.026), (DREH[0] + 0.026, DREH[1] - 0.030),
        (-0.062, -0.286), (-0.170, -0.336), (-0.244, -0.352), (-0.276, -0.336),
        (-0.268, -0.312), (-0.196, -0.306), (-0.096, -0.276), (0.008, -0.212),
        (DREH[0] - 0.030, DREH[1] - 0.020)]
prism(SK, KUFE, 0.026, 0.052, M_wood, "Kufe", bev=0.007)
# Stahlschuh unter dem hinteren Teil — das Holz allein waere in einer Saison durch
# Mit strut() statt einer gedrehten Box: der Schuh folgt damit automatisch der
# Kufenlinie. Von Hand angesetzt hatte er 9.5 Grad, die Kufe faellt aber mit 20 —
# er stand sichtbar schief darunter.
strut(SK, (0.0, -0.056, -0.291), (0.0, -0.246, -0.353), 0.062, 0.017, M_steel, bev=0.004)
box(SK, (0.058, 0.040, 0.026), (0.0, -0.250, -0.346), M_steel, rot=(radians(20.0), 0, 0), bev=0.005)
# Beschlag am Lagerauge
box(SK, (0.062, 0.058, 0.052), (0.0, DREH[0], DREH[1]), M_gun, bev=0.005)

# GUMMISEIL: mehrere Windungen zwischen Kufenarm und oberem Anschlag. Das ist die
# gesamte Federung — dieselbe Technik wie an den Doppeldecker-Raedern.
for i in range(5):
    xo = (i - 2) * 0.011
    strut(SK, (xo, -0.062, -0.070), (xo, -0.036, -0.246), 0.007, 0.007, M_rub, bev=0.002)
for zz, yy in ((-0.084, -0.060), (-0.230, -0.040)):
    cyl(SK, 0.019, 0.058, (0.0, yy, zz), XR, M_rub, v=18)          # Wicklung


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


legmesh = join(UP, "LegMesh",  (0.0, 0.0, 0.0))
skid    = join(SK, "SkidMesh", (0.0, DREH[0], DREH[1]))

for o in (legmesh, skid):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.shade_auto_smooth(angle=radians(35))


def empty(name, parent=None):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    e.empty_display_size = 0.05
    e.location = (0, 0, 0)
    if parent: e.parent = parent
    return e


root   = empty("Root_skid")
leg    = empty("Leg", root)
extend = empty("Extend", leg)
bpy.context.view_layer.update()

for kind, elt in ((legmesh, leg), (skid, extend)):
    kind.parent = elt
    kind.matrix_parent_inverse = elt.matrix_world.inverted()

bpy.ops.object.select_all(action='DESELECT')
for o in (root, leg, extend, legmesh, skid):
    o.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format='GLB', use_selection=True,
    export_yup=True, export_apply=False, export_animations=False,
)
print("EXPORTED", OUT)
print("Aufstand z=%.3f | Kufenlaenge %.3f m | KEIN Rad-Knoten (schleift, rollt nicht)"
      % (Z_UNTEN, DREH[0] + 0.276))
