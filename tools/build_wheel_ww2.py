## Baut das WW2-Jaegerfahrwerk -> res://models/wheel_ww2.glb
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_wheel_ww2.py
##
## Deckt die MEHRHEIT aller WW2-Jaeger ab (P-51, Fw 190, P-47, F6F, Jak, La, A6M):
## Bein im Fluegel, klappt NACH INNEN zum Rumpf. Das vorhandene wheel_spitfire klappt
## als Ausnahme nach AUSSEN — beide zusammen decken damit beide Bauarten ab.
##
## KLAPPACHSE: anders als bei Bug-/Spornrad und F-22 (die um X nach vorn klappen) dreht
## dieses Bein um die LAENGSACHSE Y. +85 Grad um Y kippt das haengende Bein nach -X, also
## zum Rumpf. Die gespiegelte Haelfte (improper Basis) klappt dadurch automatisch zur
## Gegenseite — ebenfalls nach innen.
##
## STRUKTUR wie bei den uebrigen animierten Fahrwerken (Begruendung in build_wheel_f22.py):
##   Root_ww2 -> Pivot_ww2(anim rot Y) -> Leg(Node3D) -> LegMesh
##                                                    -> ScissorU -> ScissorL
##                                                    -> Extend -> Slider -> SlideMesh + Wheel
## Eine separate Klappe gibt es bewusst NICHT: bei Fw 190 und P-51 sitzt die Verkleidung
## AM BEIN und klappt mit ein — sie ist darum Teil von LegMesh.
##
## Achsen (glTF +Y up): Blender X -> Godot X (Radachse), Z -> Godot Y (oben),
##                      +Y -> Godot -Z (VORNE). Ruhepose Frame 1 = AUSGEFAHREN.
import bpy, bmesh, math
from math import radians
from mathutils import Vector

OUT = "/Users/konstantinkanzler/Projects/aviasembly/models/wheel_ww2.glb"

Z_AXLE = -0.840
R_TIRE = 0.195          # -> Aufstandspunkt z = -1.035
TELE = 0.115
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
M_rim    = mat("rim",     (0.38, 0.40, 0.45),    0.35, 0.80)
M_hub    = mat("hub",     (0.17, 0.17, 0.19),    0.45, 0.70)
M_steel  = mat("steel",   (0.55, 0.57, 0.61),    0.22, 0.92)
M_gun    = mat("gunmetal",(0.165, 0.175, 0.205), 0.42, 0.70)
M_piston = mat("piston",  (0.62, 0.64, 0.68),    0.20, 0.94)
# Die Beinverkleidung heisst "body" und steht damit in PartCatalog.PAINT_MATS: sie wird
# beim Lackieren MITGEFAERBT — genau wie am echten Flugzeug, wo die Fahrwerksklappe die
# Tarnfarbe der Zelle traegt. Alle uebrigen Fahrwerke bleiben unlackiert.
M_body   = mat("body",    (0.42, 0.45, 0.42),    0.55, 0.15)

UP, SL, WH, SCU, SCL = [], [], [], [], []


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


def pin(bag, loc, r, w, material=M_steel):
    return cyl(bag, r, w, loc, XR, material, v=14)


def prism(bag, prof, x0, thick, material, name="Panel", bev=0.006):
    """Profil in der YZ-Ebene, in X aufgedickt — fuer die Beinverkleidung."""
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
    if bev > 0: _bevel(o, bev, 2)
    bag.append(o); return o


# ===================================================== OBERES BEIN (LegMesh)
# Trunnion: die Klappachse liegt LAENGS (Y), die Lageraugen sitzen darum vorn/hinten
# statt seitlich wie bei den nach vorn klappenden Beinen.
box(UP, (0.105, 0.290, 0.078), (0.0, 0.0, -0.040), M_gun, bev=0.010)
box(UP, (0.150, 0.230, 0.026), (0.0, 0.0, 0.004), M_gun, bev=0.006)
for sy in (-1.0, 1.0):
    cyl(UP, 0.036, 0.080, (0.0, sy * 0.150, -0.040), (radians(90), 0, 0), M_gun, v=20)
    cyl(UP, 0.017, 0.096, (0.0, sy * 0.150, -0.040), (radians(90), 0, 0), M_steel, v=14)

# Oleo-Zylinder
cyl(UP, 0.078, 0.036, (0, 0, -0.098), material=M_steel, v=32)
cyl(UP, 0.064, 0.300, (0, 0, -0.255), material=M_gun,   v=32, bev=0.004)
cyl(UP, 0.070, 0.028, (0, 0, -0.392), material=M_steel, v=32)
box(UP, (0.072, 0.046, 0.040), (0.0, 0.068, -0.360), M_gun, bev=0.006)   # Schereaufnahme oben

# Knickstrebe nach hinten + Einzieh-Aktuator nach vorn
KNEE = (0.096, -0.150, -0.320)
strut(UP, (0.070, -0.120, -0.052), KNEE, 0.026, 0.026, M_gun)
strut(UP, KNEE, (0.020, -0.040, -0.420), 0.024, 0.024, M_gun)
pin(UP, KNEE, 0.020, 0.060)
strut(UP, (0.0, 0.132, -0.040), (0.0, 0.078, -0.215), 0.040, 0.040, M_gun, bev=0.008)
strut(UP, (0.0, 0.080, -0.208), (0.0, 0.046, -0.352), 0.022, 0.022, M_piston, bev=0.004)
pin(UP, (0.0, 0.132, -0.036), 0.017, 0.074)

# BEINVERKLEIDUNG (lackierbar): die Radkastenklappe sitzt AM BEIN und klappt mit ein —
# bei Fw 190 und P-51 genau so. Sie liegt bei +X und wandert beim Einklappen um Y nach
# unten, schliesst also buendig mit der Fluegelunterseite ab.
# Rundum abgesetzte Kontur statt der frueheren spitz zulaufenden Platte: die sah aus wie
# ein angeklebtes Brett statt wie ein Blechteil.
VERK = [(0.148, -0.018), (0.156, -0.215), (0.132, -0.420), (0.070, -0.575),
        (-0.020, -0.628), (-0.108, -0.560), (-0.148, -0.380), (-0.152, -0.150),
        (-0.132, -0.018)]
prism(UP, VERK, 0.100, 0.014, M_body, "Verkleidung", bev=0.010)
# Randfalz: schmaler, leicht versetzter Streifen -> die Klappe liest sich als Blech
# mit Kante statt als Volumenscheibe.
FALZ = [(y * 0.87, (z + 0.32) * 0.87 - 0.32) for (y, z) in VERK]
prism(UP, FALZ, 0.086, 0.010, M_gun, "VerkFalz", bev=0.004)
box(UP, (0.012, 0.026, 0.520), (0.082, 0.006, -0.320), M_gun, bev=0.003)   # Laengsversteifung
for zz in (-0.140, -0.330, -0.500):
    box(UP, (0.012, 0.230, 0.020), (0.082, 0.006, zz), M_gun, bev=0.003)


# ================================================ SCHIEBENDER TEIL (SlideMesh)
cyl(SL, 0.046, 0.300, (0, 0, -0.605), material=M_piston, v=32)
cyl(SL, 0.054, 0.038, (0, 0, -0.752), material=M_steel, v=28)
box(SL, (0.072, 0.046, 0.040), (0.0, 0.062, -0.744), M_gun, bev=0.006)     # Schereaufnahme unten
box(SL, (0.110, 0.096, 0.130), (0.0, 0.0, Z_AXLE + 0.040), M_gun, bev=0.010)   # Gabelkopf
cyl(SL, 0.038, 0.150, (0.0, 0, Z_AXLE), XR, M_gun, v=24)                    # Achse
# Die Achse ragte vorher 9 cm ueber den Reifen hinaus und stand als blanker
# Stift heraus — sie endet jetzt buendig mit der Reifenflanke.
# BREMSE — WW2 hat Trommelbremsen, keine Scheibenpakete wie die F-22. Sichtbar ist
# davon nur der ANKERBLECH-Teller an der Innenseite des Rades; die Trommel selbst
# steckt in der Felge. Als dicker Zylinder AUSSEN am Rad sah das aus wie ein
# angeflanschter Topf statt wie eine Bremse.
cyl(SL, 0.100, 0.016, (0.078, 0, Z_AXLE), XR, M_hub, v=32, bev=0.004)      # Ankerblech
cyl(SL, 0.040, 0.022, (0.086, 0, Z_AXLE), XR, M_gun, v=20, bev=0.003)      # Nabenkappe
strut(SL, (0.082, 0.068, Z_AXLE + 0.030), (0.050, 0.070, -0.700), 0.011, 0.011, M_steel, bev=0.003)


# ============================================ DREHMOMENTSCHERE (Zweigelenk)
SC_U = (0.068, -0.360)
SC_L = (0.062, -0.744)
SC_K = (0.142, -0.545)
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

strut(SCU, (0.0, SC_U[0], SC_U[1]), (0.0, SC_K[0], SC_K[1]), 0.022, 0.032, M_gun)
pin(SCU, (0.0, SC_U[0], SC_U[1]), 0.016, 0.060)
strut(SCL, (0.0, SC_K[0], SC_K[1]), (0.0, SC_L[0], SC_L[1]), 0.022, 0.032, M_gun)
pin(SCL, (0.0, SC_K[0], SC_K[1]), 0.019, 0.070)
pin(SCL, (0.0, SC_L[0], SC_L[1]), 0.016, 0.060)


# ==================================================================== RAD
# WW2-Reifen sind dick und glatt (Ballonreifen), keine Laufrillen wie am Jet.
# Breiter und mit kleinerer Felge als zuvor: so zeigt sich mehr Gummi und das Rad
# wirkt wie ein WW2-Ballonreifen statt wie eine Nabe mit duennem Gummiring.
cyl(WH, R_TIRE, 0.152, (0, 0, Z_AXLE), XR, M_rubber, v=48, bev=0.030)
cyl(WH, 0.118, 0.158, (0, 0, Z_AXLE), XR, M_rim, v=40)
for sx in (-1.0, 1.0):
    cyl(WH, 0.132, 0.016, (sx * 0.076, 0, Z_AXLE), XR, M_rim, v=40)
cyl(WH, 0.092, 0.018, (-0.078, 0, Z_AXLE), XR, M_hub, v=36)                # Nabendeckel aussen
for i in range(6):                                                          # Erleichterungsloecher
    a = i * (2.0 * math.pi / 6.0)
    cyl(WH, 0.024, 0.026, (-0.080, math.cos(a) * 0.058, Z_AXLE + math.sin(a) * 0.058),
        XR, M_gun, v=14)
cyl(WH, 0.042, 0.150, (0, 0, Z_AXLE), XR, M_hub, v=24)


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

for o in (legmesh, slide, wheel, scu, scl):
    for p in o.data.polygons:
        p.use_smooth = (o.data.materials[p.material_index].name in ("rubber", "piston"))


def empty(name, parent=None):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    e.empty_display_size = 0.08
    e.location = (0, 0, 0)
    if parent: e.parent = parent
    return e


root   = empty("Root_ww2")
pivot  = empty("Pivot_ww2", root)
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


# ------------------------------------------------------------- Animation
act = bpy.data.actions.new("retract")
strip = act.layers.new("Layer").strips.new(type='KEYFRAME')
slots = {}
for ob in (pivot, slider, scu, scl):
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


# Index 1 = Drehung um Y: kippt das Bein nach -X, also ZUM RUMPF (nach innen).
key(pivot, "rotation_euler", 1, [(1, 0.0), (10, radians(21.0)), (24, radians(88.0)), (30, radians(85.0))])

TELE_KEYS = [(1, 0.0), (6, 0.0), (14, TELE * 0.45), (26, TELE), (30, TELE)]
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
for o in (root, pivot, leg, extend, slider, legmesh, slide, wheel, scu, scl):
    o.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format='GLB', use_selection=True,
    export_yup=True, export_apply=False,
    export_animations=True, export_animation_mode='ACTIONS',
    export_frame_range=True, export_bake_animation=True,
)
print("EXPORTED", OUT)
print("Aufstand z=%.3f | Teleskop %.3f | Schere L1=%.3f L2=%.3f"
      % (Z_AXLE - R_TIRE, TELE, L1, L2))
