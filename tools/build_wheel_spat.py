## Baut das starre Hosenbein-Fahrwerk -> res://models/wheel_spat.glb
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_wheel_spat.py
##
## Deckt die ganze Generation der 1930er mit FESTEM Fahrwerk ab: Ju 87 Stuka, Fi 156
## Storch, He 51, I-15/I-16 und praktisch jedes Schulflugzeug der Zeit.
##
## ERSTES FAHRWERK OHNE EINZIEHMECHANIK — darum bewusst anders aufgebaut als die
## uebrigen: kein Pivot, keine "retract"-Animation, kein Slider. Was BLEIBT, ist die
## Editor-Beinlaenge, denn genau die braucht dieser Typ am dringendsten (grosse
## Propeller wollen Bodenfreiheit):
##   Root_spat -> Leg(Node3D) -> LegMesh          Hose + Holm + Anschluss
##                            -> Extend           Editor-Beinlaenge
##                                -> SpatMesh     Radschuh, dreht NICHT mit
##                                -> Wheel        rollt um lokal X
## Der Radschuh haengt unter Extend statt unter LegMesh: sonst bliebe er beim
## Verlaengern des Beins oben stehen und das Rad fiele unten heraus.
##
## RUNDUNG — die erste Fassung wirkte kantig, weil beide Verkleidungen zu grob waren:
## die Hose hatte 12 Profilpunkte auf 5 Ebenen (sichtbare Laengsfacetten und Quer-
## knicke), der Radschuh war ein FLACH in X ausgezogenes Prisma mit geraden Seiten.
## Jetzt:
##   - Hose: NACA-Tropfenprofil mit 32 Punkten auf 11 Ebenen, Kosinus-Verteilung
##     (dichter an Nase und Endleiste, wo die Kruemmung sitzt)
##   - Radschuh: ebenfalls ein Loft, aber ENTLANG X — dadurch ein gewoelbter Koerper
##     statt einer Scheibe mit abgefaster Kante
##   - Schattierung: winkelabhaengiges Auto-Smooth (35 Grad) statt materialweise.
##     Rundungen laufen dadurch durch, echte Kanten bleiben scharf.
##
## Achsen (glTF +Y up): Blender X -> Godot X (Radachse), Z -> Godot Y (oben),
##                      +Y -> Godot -Z (VORNE).
import bpy, bmesh, math
from math import radians
from mathutils import Vector

OUT = "/Users/konstantinkanzler/Projects/aviasembly/models/wheel_spat.glb"

Z_AXLE = -0.775
R_TIRE = 0.175          # -> Aufstandspunkt z = -0.950
Z_SCHUH_U = -0.815      # Unterkante Radschuh; darunter schaut der Reifen heraus
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

M_rubber = mat("rubber",  (0.048, 0.048, 0.056), 0.90, 0.0)
M_rim    = mat("rim",     (0.38, 0.40, 0.45),    0.35, 0.80)
M_hub    = mat("hub",     (0.17, 0.17, 0.19),    0.45, 0.70)
M_steel  = mat("steel",   (0.55, 0.57, 0.61),    0.22, 0.92)
M_gun    = mat("gunmetal",(0.165, 0.175, 0.205), 0.42, 0.70)
# Hose UND Radschuh heissen "body" und stehen damit in PartCatalog.PAINT_MATS: beide
# nehmen die Lackierung der Zelle an. Bei diesem Typ ist das der halbe Reiz — an Stuka
# und Storch sind die Verkleidungen das groesste sichtbare Farbfeld am Fahrwerk.
M_body   = mat("body",    (0.40, 0.44, 0.40),    0.55, 0.15)

UP, SP, WH = [], [], []


def _bevel(o, width, segs=2, winkel=40):
    md = o.modifiers.new("bev", 'BEVEL')
    md.width, md.segments, md.limit_method = width, segs, 'ANGLE'
    md.angle_limit = radians(winkel)
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


# --------------------------------------------------------------- Konturen
def tropfen(m, y_nase, y_ende, dicke_rel):
    """Symmetrische NACA-Tropfenkontur in der XY-Ebene: Nase bei +Y, Endleiste bei -Y,
    Dicke in X. Kosinus-Verteilung der Stuetzstellen, damit die stark gekruemmte Nase
    genug Punkte bekommt und nicht facettiert."""
    C = y_nase - y_ende
    oben, unten = [], []
    for i in range(m + 1):
        s = 0.5 * (1.0 - math.cos(math.pi * i / m))          # 0 (Nase) .. 1 (Ende)
        t = 5.0 * dicke_rel * C * (0.2969 * math.sqrt(s) - 0.1260 * s - 0.3516 * s * s
                                   + 0.2843 * s ** 3 - 0.1015 * s ** 4)
        y = y_nase - s * C
        oben.append((t, y))
        unten.append((-t, y))
    return oben + list(reversed(unten[1:-1]))                # geschlossener Umlauf


def catmull(pts, n, z_min=None):
    """Geschlossene Catmull-Rom-Kurve durch pts, auf n Punkte abgetastet.
    z_min klemmt die Unterkante wieder gerade — die Kurve wuerde sie sonst aufrunden."""
    m = len(pts)
    out = []
    for i in range(n):
        u = i / n * m
        k = int(u) % m
        t = u - int(u)
        p0, p1, p2, p3 = pts[(k - 1) % m], pts[k], pts[(k + 1) % m], pts[(k + 2) % m]
        q = []
        for d in range(2):
            q.append(0.5 * (2 * p1[d] + (-p0[d] + p2[d]) * t
                            + (2 * p0[d] - 5 * p1[d] + 4 * p2[d] - p3[d]) * t * t
                            + (-p0[d] + 3 * p1[d] - 3 * p2[d] + p3[d]) * t ** 3))
        if z_min is not None:
            q[1] = max(q[1], z_min)
        out.append(tuple(q))
    return out


def _mesh_aus_ringen(bm_ringe, name, material, bev, winkel):
    me = bpy.data.meshes.new(name + "Mesh")
    bm = bmesh.new()
    ringe = [[bm.verts.new(p) for p in ring] for ring in bm_ringe]
    n = len(bm_ringe[0])
    for a, b in zip(ringe, ringe[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new([a[i], a[j], b[j], b[i]])
    bm.faces.new(ringe[0])
    bm.faces.new(ringe[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me)
    sc.collection.objects.link(o)
    o.data.materials.append(material)
    bpy.context.view_layer.objects.active = o
    if bev > 0: _bevel(o, bev, 2, winkel)
    return o


def loft_z(bag, prof, ebenen, material, name, bev=0.0):
    """Profil (x,y) auf mehreren Z-Ebenen skaliert — die stehende Hose."""
    ringe = [[(x * s, y * s, z) for (x, y) in prof] for (z, s) in ebenen]
    bag.append(_mesh_aus_ringen(ringe, name, material, bev, 30)); return bag[-1]


def loft_x(bag, prof, ebenen, material, name, bev=0.0):
    """Profil (y,z) auf mehreren X-Ebenen skaliert — der liegende Radschuh.
    Gegenueber einem in X ausgezogenen Prisma bekommt der Schuh dadurch eine echte
    Woelbung statt gerader Seitenwaende mit Fase."""
    ringe = [[(x, y * s, Z_AXLE + (z - Z_AXLE) * s) for (y, z) in prof] for (x, s) in ebenen]
    bag.append(_mesh_aus_ringen(ringe, name, material, bev, 30)); return bag[-1]


# ===================================================== HOSE + HOLM (LegMesh)
box(UP, (0.150, 0.230, 0.030), (0.0, 0.0, -0.014), M_gun, bev=0.006)     # Anschlussplatte
box(UP, (0.100, 0.150, 0.055), (0.0, 0.0, -0.046), M_gun, bev=0.006)

# Tragender Holm INNEN — die Hose ist nur Verkleidung darum herum
cyl(UP, 0.036, 0.560, (0, 0, -0.330), material=M_gun, v=24)
strut(UP, (0.0, 0.090, -0.060), (0.0, 0.040, -0.300), 0.024, 0.024, M_gun)

# DIE HOSE: 32-Punkt-Tropfen, 15 cm dick auf 36 cm Tiefe.
PROF = tropfen(16, 0.148, -0.215, 0.42)
# 11 Ebenen mit weicher Verjuengung: leichte Bauchung oben, nach unten schlanker.
EBENEN = []
for i in range(11):
    t = i / 10.0
    z = -0.020 + (-0.640 + 0.020) * t
    s = (1.0 + 0.035 * math.sin(math.pi * min(t / 0.45, 1.0))) * (1.0 - 0.13 * t ** 1.7)
    EBENEN.append((z, s))
loft_z(UP, PROF, EBENEN, M_body, "Hose", bev=0.008)
# Wartungsklappe + Nietreihen, knapp AUSSERHALB der Huelle (max. Halbdicke ~0.078):
# weiter innen steckten sie halb in der Woelbung und rissen an den Raendern auf.
box(UP, (0.006, 0.090, 0.140), (0.079, 0.014, -0.300), M_gun, bev=0.004)
for zz in (-0.150, -0.460):
    box(UP, (0.005, 0.130, 0.010), (0.078, 0.006, zz), M_gun, bev=0.002)


# ================================================== RADSCHUH (SpatMesh)
# Seitenkontur um das Rad, unten offen: der Reifen schaut unter der Kante hervor und
# beruehrt den Boden. Vorn rund, nach hinten ausgezogen.
SCHUH_ECK = [(0.225, Z_SCHUH_U), (0.245, -0.750), (0.232, -0.678), (0.170, -0.616),
             (0.050, -0.588), (-0.090, -0.600), (-0.200, -0.652), (-0.272, -0.722),
             (-0.295, -0.790), (-0.290, Z_SCHUH_U)]
SCHUH = catmull(SCHUH_ECK, 48, z_min=Z_SCHUH_U)
# Querschnitte ueber die Breite: in der Mitte voll, zu den Seiten eingezogen.
# Aussenringe nicht zu stark einziehen: bei 0.72 lief die Unterkante als duenner
# Grat aus, weil sie zu den Seiten deutlich hoeher wanderte als in der Mitte.
BREIT = [(-0.090, 0.84), (-0.074, 0.925), (-0.046, 0.980), (-0.016, 1.0),
         (0.016, 1.0), (0.046, 0.980), (0.074, 0.925), (0.090, 0.84)]
loft_x(SP, SCHUH, BREIT, M_body, "Schuh", bev=0.006)
cyl(SP, 0.030, 0.230, (0, 0, Z_AXLE), XR, M_gun, v=24)     # Achsstummel


# ==================================================================== RAD
cyl(WH, R_TIRE, 0.128, (0, 0, Z_AXLE), XR, M_rubber, v=56, bev=0.026)
cyl(WH, 0.104, 0.134, (0, 0, Z_AXLE), XR, M_rim, v=48)
cyl(WH, 0.070, 0.016, (-0.066, 0, Z_AXLE), XR, M_hub, v=36)
cyl(WH, 0.036, 0.146, (0, 0, Z_AXLE), XR, M_hub, v=24)
cyl(WH, 0.020, 0.158, (0, 0, Z_AXLE), XR, M_steel, v=18)


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
spat    = join(SP, "SpatMesh", (0.0, 0.0, 0.0))
wheel   = join(WH, "Wheel",    (0.0, 0.0, Z_AXLE))     # Origin = Radachse -> rollt

# WINKELABHAENGIGES Auto-Smooth statt materialweise: Rundungen laufen durch, echte
# Kanten (Anschlussplatte, Nietreihen, Klappenrand) bleiben scharf. Materialweise
# Glaettung liess die Facetten der Verkleidungen stehen, weil die Uebergaenge zwischen
# den Loft-Ringen als eigene Flaechen behandelt wurden.
for o in (legmesh, spat, wheel):
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


root   = empty("Root_spat")
leg    = empty("Leg", root)
extend = empty("Extend", leg)
bpy.context.view_layer.update()

for kind, elt in ((legmesh, leg), (spat, extend), (wheel, extend)):
    kind.parent = elt
    kind.matrix_parent_inverse = elt.matrix_world.inverted()

bpy.ops.object.select_all(action='DESELECT')
for o in (root, leg, extend, legmesh, spat, wheel):
    o.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format='GLB', use_selection=True,
    export_yup=True, export_apply=False, export_animations=False,
)
print("EXPORTED", OUT)
print("Aufstand z=%.3f | Hose %d Profilpunkte x %d Ebenen | Schuh %d x %d"
      % (Z_AXLE - R_TIRE, len(PROF), len(EBENEN), len(SCHUH), len(BREIT)))
