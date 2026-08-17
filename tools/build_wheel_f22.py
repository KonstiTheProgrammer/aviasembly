## Baut das hochdetaillierte, ANIMIERTE F-22-Hauptfahrwerk -> res://models/wheel_f22.glb
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_wheel_f22.py
## oder via Blender-MCP:  exec(open("<abs>/tools/build_wheel_f22.py").read())
##
## STRUKTUR — zwei Laengen-Mechaniken, die sich NICHT ins Gehege kommen duerfen:
##   Root_f22                Ursprung = Aufhaengepunkt am Rumpf (0,0,0)
##    |- Pivot_f22           ANIMIERT (rot X) — klappt nach VORN hoch
##    |   \- Leg             Node3D (KEIN Mesh!) — der Drehpunkt, den PartCatalog erwartet.
##    |       |              Weil "Leg" schon ein Node3D ist, laesst set_gear_length seinen
##    |       |              Umbau-Zweig aus und findet LegMesh/Extend direkt vor.
##    |       |- LegMesh     Oberes Bein: Trunnion, Oleo-Zylinder, Knickstrebe, Aktuator.
##    |       |              DIESES Netz streckt set_gear_length fuer die Editor-Beinlaenge.
##    |       |- ScissorU    ANIMIERT (rot X) — oberer Scherenlenker, Drehpunkt am Zylinder
##    |       |   \- ScissorL ANIMIERT (rot X) — unterer Lenker, Drehpunkt am Knie
##    |       \- Extend      NUR Editor-Beinlaenge (von set_gear_length gesetzt)
##    |           \- Slider  NUR Animation (Teleskop, pos Z) — Kolben faehrt ein/aus
##    |               |- SlideMesh  Kolben, Gabel, Achse, Bremstraeger
##    |               \- Wheel      Rad; Origin = Radachse -> rollt um lokal X
##    \- Door                Fahrwerksklappe, rumpffest, eigene Schwenkbewegung
##
## Achsen (glTF +Y up):  Blender X -> Godot X (Radachse)
##                       Blender Z -> Godot Y (oben)
##                       Blender +Y -> Godot -Z (VORNE)
## Ruhepose (Frame 1) = AUSGEFAHREN. Radaufstandspunkt bei Blender z = -1.055.
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


OUT = os.path.join(PROJEKT, "models/wheel_f22.glb")

Z_AXLE = -0.845         # Radachse (ausgefahren)
R_TIRE = 0.210          # -> Aufstandspunkt z = -1.055 (wie wheel_jet: Godot y ~ -1.05)
TELE = 0.130            # Teleskopweg: so weit faehrt der Kolben beim Einfahren ein

# ---------------------------------------------------------------- Szene leeren
for o in list(bpy.data.objects):   bpy.data.objects.remove(o, do_unlink=True)
for m in list(bpy.data.meshes):    bpy.data.meshes.remove(m)
for mt in list(bpy.data.materials):bpy.data.materials.remove(mt)
for a in list(bpy.data.actions):   bpy.data.actions.remove(a)

sc = bpy.context.scene
sc.name = "retract"
sc.render.fps = 30
sc.frame_start, sc.frame_end = 1, 30


# ---------------------------------------------------------------- Materialien
def mat(name, col, rough, metal):
    m = bpy.data.materials.new(name); m.name = name; m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m

# Namen bewusst wie in tools/build_wheel_jet.py — gleiche Optik im Hangar.
# Keiner davon steht in PartCatalog.PAINT_MATS, das Fahrwerk bleibt also unlackiert.
M_rubber = mat("rubber",  (0.050, 0.050, 0.058), 0.88, 0.0)
M_rim    = mat("rim",     (0.40, 0.42, 0.47),    0.30, 0.85)
M_hub    = mat("hub",     (0.17, 0.17, 0.19),    0.45, 0.70)
M_steel  = mat("steel",   (0.55, 0.57, 0.61),    0.22, 0.92)
M_gun    = mat("gunmetal",(0.165, 0.175, 0.205), 0.40, 0.72)
M_piston = mat("piston",  (0.62, 0.64, 0.68),    0.20, 0.94)
M_door   = mat("dark",    (0.135, 0.140, 0.160), 0.52, 0.55)

UP, SLIDE, WHEEL, DOOR, SCU, SCL = [], [], [], [], [], []
XR = (0, radians(90), 0)                 # Zylinder von Z- auf X-Achse (= Radachse)


# ------------------------------------------------------------------ Primitive
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

def strut(bag, p0, p1, w, t, material, bev=0.006):
    """Streben-/Lenkerbalken von p0 nach p1 (lokale Z spannt die Strecke auf)."""
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

def pin(bag, loc, r=0.020, w=0.075, material=M_steel):
    return cyl(bag, r, w, loc, XR, material, v=16)


# ====================================================== OBERES BEIN (LegMesh)
# --- Trunnion: Quertraeger mit Anlenkaugen, Drehpunkt des ganzen Beins -------
box(UP, (0.300, 0.115, 0.075), (0.0,  0.005, -0.038), M_gun, bev=0.010)
box(UP, (0.262, 0.165, 0.024), (0.0,  0.010,  0.006), M_gun, bev=0.006)
box(UP, (0.130, 0.100, 0.105), (0.0, -0.082, -0.062), M_gun, bev=0.008)   # Aktuator-Konsole
for sx in (-1.0, 1.0):
    cyl(UP, 0.036, 0.085, (sx * 0.150, 0.005, -0.038), XR, M_gun, v=20)   # Lagerauge
    cyl(UP, 0.017, 0.098, (sx * 0.150, 0.005, -0.038), XR, M_steel, v=14) # Bolzen
box(UP, (0.115, 0.090, 0.115), (0.0, 0.052, -0.075), M_gun, bev=0.008)    # Holmschulter

# --- Oleo-Zylinder (das feste Rohr; der Kolben darin sitzt im Slider) -------
cyl(UP, 0.080, 0.040, (0, 0, -0.098), material=M_steel, v=32)             # Flansch oben
cyl(UP, 0.066, 0.330, (0, 0, -0.270), material=M_gun,   v=32, bev=0.004)  # Zylinder
cyl(UP, 0.072, 0.030, (0, 0, -0.352), material=M_steel, v=32)             # Ring
cyl(UP, 0.075, 0.055, (0, 0, -0.448), material=M_gun,   v=32, bev=0.005)  # Dichtungspaket
box(UP, (0.074, 0.048, 0.042), (0.0, 0.064, -0.395), M_gun, bev=0.006)    # Schereaufnahme oben
# Hydraulikleitung mit Schellen
strut(UP, (0.060, -0.048, -0.130), (0.060, -0.048, -0.430), 0.009, 0.009, M_steel, bev=0.003)
cyl(UP, 0.014, 0.030, (0.060, -0.048, -0.128), material=M_gun, v=12)
for zc in (-0.190, -0.310, -0.416):
    box(UP, (0.030, 0.026, 0.016), (0.056, -0.044, zc), M_gun, bev=0.003)

# --- Knickstrebe (hinten, -Y) ----------------------------------------------
KNEE_B = (0.112, -0.140, -0.352)
strut(UP, (0.168, -0.020, -0.060), KNEE_B, 0.026, 0.026, M_gun)
strut(UP, KNEE_B, (0.040, -0.038, -0.470), 0.024, 0.024, M_gun)
pin(UP, KNEE_B, r=0.022, w=0.068)
box(UP, (0.060, 0.060, 0.048), (0.040, -0.036, -0.472), M_gun, bev=0.006)

# --- Einzieh-Aktuator (hinten, -Y) -----------------------------------------
strut(UP, (0.0, -0.128, -0.030), (0.0, -0.088, -0.235), 0.044, 0.044, M_gun, bev=0.010)
strut(UP, (0.0, -0.090, -0.228), (0.0, -0.046, -0.400), 0.024, 0.024, M_piston, bev=0.005)
pin(UP, (0.0, -0.128, -0.026), r=0.018, w=0.080)
box(UP, (0.060, 0.055, 0.045), (0.0, -0.046, -0.404), M_gun, bev=0.006)


# ================================================ SCHIEBENDER TEIL (SlideMesh)
cyl(SLIDE, 0.048, 0.345, (0, 0, -0.632), material=M_piston, v=32)          # POLIERTER KOLBEN
cyl(SLIDE, 0.056, 0.045, (0, 0, -0.782), material=M_steel, v=28)           # unterer Ring
box(SLIDE, (0.074, 0.048, 0.042), (0.0, 0.058, -0.794), M_gun, bev=0.006)  # Schereaufnahme unten
box(SLIDE, (0.108, 0.092, 0.125), (0.0, 0.0, Z_AXLE + 0.030), M_gun, bev=0.010)  # Achsgabel
cyl(SLIDE, 0.040, 0.300, (0.045, 0, Z_AXLE), XR, M_gun, v=24)              # Achse
cyl(SLIDE, 0.050, 0.026, (-0.092, 0, Z_AXLE), XR, M_steel, v=20)           # Achsmutter aussen
# Bremstraeger + Sattel: sitzen am BEIN, drehen also nicht mit dem Rad mit
cyl(SLIDE, 0.076, 0.026, (0.188, 0, Z_AXLE), XR, M_gun, v=28)
box(SLIDE, (0.050, 0.070, 0.078), (0.152, 0.0, Z_AXLE + 0.112), M_gun, bev=0.008)
strut(SLIDE, (0.152, 0.0, Z_AXLE + 0.085), (0.035, 0.0, Z_AXLE + 0.055), 0.022, 0.022, M_gun)


# ============================================ DREHMOMENTSCHERE (zwei Lenker)
# Oben am Zylinder fest, unten am Kolben — faehrt der Kolben ein, MUSS die Schere
# zuklappen, sonst haengt sie in der Luft. Kniepunkt wird darum pro Frame aus der
# Zweigelenk-Kinematik gerechnet (siehe knie()).
SC_U = (0.076, -0.398)          # oberer Drehpunkt (y, z) am Zylinder
SC_L = (0.068, -0.792)          # unterer Drehpunkt (y, z) am Kolben, faehrt mit
SC_K = (0.152, -0.556)          # Knie in Ruhe

L1 = math.dist(SC_K, SC_U)
L2 = math.dist(SC_L, SC_K)

def knie(dz):
    """Kniepunkt, wenn der untere Drehpunkt um dz nach OBEN gewandert ist."""
    uy, uz = SC_U
    ly, lz = SC_L[0], SC_L[1] + dz
    vy, vz = ly - uy, lz - uz
    dist = math.hypot(vy, vz)
    a = (L1 * L1 - L2 * L2 + dist * dist) / (2.0 * dist)
    h = math.sqrt(max(L1 * L1 - a * a, 0.0))
    by, bz = uy + a * vy / dist, uz + a * vz / dist
    k1 = (by - h * vz / dist, bz + h * vy / dist)
    k2 = (by + h * vz / dist, bz - h * vy / dist)
    return k1 if k1[0] > k2[0] else k2      # Knie zeigt nach VORN (groesseres y)

def winkel(p0, p1):
    return math.atan2(p1[1] - p0[1], p1[0] - p0[0])   # Drehung um X: +Y -> +Z

W1_0 = winkel(SC_U, SC_K)
W2_0 = winkel(SC_K, SC_L)

# Geometrie in Ruhelage bauen; Origin kommt spaeter auf den jeweiligen Drehpunkt.
strut(SCU, (0.0, SC_U[0], SC_U[1]), (0.0, SC_K[0], SC_K[1]), 0.024, 0.034, M_gun)
pin(SCU, (0.0, SC_U[0], SC_U[1]), r=0.017, w=0.066)
strut(SCL, (0.0, SC_K[0], SC_K[1]), (0.0, SC_L[0], SC_L[1]), 0.024, 0.034, M_gun)
pin(SCL, (0.0, SC_K[0], SC_K[1]), r=0.020, w=0.076)
pin(SCL, (0.0, SC_L[0], SC_L[1]), r=0.017, w=0.066)


# ================================================================== RAD
cyl(WHEEL, R_TIRE, 0.145, (0, 0, Z_AXLE), XR, M_rubber, v=48, bev=0.018)   # Reifen
for xo in (-0.045, 0.0, 0.045):                                            # Laufflaechen-Rippen
    cyl(WHEEL, R_TIRE + 0.004, 0.030, (xo, 0, Z_AXLE), XR, M_rubber, v=48)
cyl(WHEEL, 0.140, 0.160, (0, 0, Z_AXLE), XR, M_rim, v=40)                  # Felgenbett
for sx in (-1.0, 1.0):
    cyl(WHEEL, 0.155, 0.018, (sx * 0.076, 0, Z_AXLE), XR, M_rim, v=40)     # Felgenhorn
cyl(WHEEL, 0.058, 0.175, (0, 0, Z_AXLE), XR, M_hub, v=28)                  # Nabe
cyl(WHEEL, 0.040, 0.192, (0, 0, Z_AXLE), XR, M_steel, v=20)                # Nabenkappe
for i in range(10):
    a = i * (2.0 * math.pi / 10.0)
    cyl(WHEEL, 0.010, 0.168, (0.0, math.cos(a) * 0.095, Z_AXLE + math.sin(a) * 0.095),
        XR, M_steel, v=10)
# Bremsscheiben-Stapel innen (+X); Uebergangsring schliesst die Luecke zur Felge
cyl(WHEEL, 0.098, 0.030, (0.078, 0, Z_AXLE), XR, M_hub, v=32)
for i in range(4):
    cyl(WHEEL, 0.106, 0.012, (0.096 + i * 0.016, 0, Z_AXLE), XR, M_steel, v=36)
cyl(WHEEL, 0.084, 0.018, (0.166, 0, Z_AXLE), XR, M_hub, v=28)


# ================================================================ KLAPPE
HINGE = Vector((-0.148, 0.0, -0.020))
PROF = [(0.175, 0.010), (0.150, -0.330), (0.010, -0.560), (-0.190, -0.435), (-0.205, 0.010)]

def prism(bag, prof, x0, thick, material, name="Panel", bev=0.006):
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

prism(DOOR, PROF, 0.0, 0.020, M_door, "DoorSkin", bev=0.007)               # Aussenhaut glatt
inset = [(y * 0.86, (z + 0.28) * 0.86 - 0.28) for (y, z) in PROF]
prism(DOOR, inset, 0.013, 0.013, M_gun, "DoorLip", bev=0.004)              # Randfalz
for zz in (-0.120, -0.300, -0.455):                                        # Innenspanten
    box(DOOR, (0.018, 0.300, 0.026), (0.022, -0.012, zz), M_gun, bev=0.004)
box(DOOR, (0.018, 0.036, 0.500), (0.022, 0.112, -0.258), M_gun, bev=0.004) # Laengsspant
for yy in (0.118, -0.142):                                                 # Scharnierboecke
    box(DOOR, (0.088, 0.042, 0.042), (0.052, yy, 0.002), M_gun, bev=0.005)
    cyl(DOOR, 0.014, 0.100, (0.052, yy, 0.002), XR, M_steel, v=12)
for o in DOOR:
    o.location = o.location + HINGE


# ------------------------------------------------- zu Objekten verschmelzen
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

legmesh = join(UP,    "LegMesh",   (0.0, 0.0, 0.0))
slide   = join(SLIDE, "SlideMesh", (0.0, 0.0, 0.0))
wheel   = join(WHEEL, "Wheel",     (0.0, 0.0, Z_AXLE))    # Origin = Radachse (Rollen!)
scu     = join(SCU,   "ScissorU",  (0.0, SC_U[0], SC_U[1]))
scl     = join(SCL,   "ScissorL",  (0.0, SC_K[0], SC_K[1]))
door    = join(DOOR,  "Door",      tuple(HINGE))

# Nur Gummi und polierte Flaechen glatt, Struktur kantig lassen
for o in (legmesh, slide, wheel, scu, scl, door):
    for p in o.data.polygons:
        p.use_smooth = (o.data.materials[p.material_index].name in ("rubber", "piston"))

# ------------------------------------------------------------ Hierarchie
def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    e.empty_display_size = 0.10
    e.location = loc
    if parent: e.parent = parent
    return e

root   = empty("Root_f22")
pivot  = empty("Pivot_f22", root)
leg    = empty("Leg", pivot)          # Node3D — set_gear_length laesst den Umbau dadurch aus
extend = empty("Extend", leg)         # NUR Editor-Beinlaenge
slider = empty("Slider", extend)      # NUR Teleskop-Animation

bpy.context.view_layer.update()       # matrix_world muss aktuell sein, sonst greift attach daneben

def attach(child, parent):
    """Parenten OHNE das Kind zu versetzen. Blender rechnet die Kind-Transform sonst
    RELATIV zum Elternteil — bei Eltern im Ursprung faellt das nicht auf, ScissorU sitzt
    aber am Drehpunkt und wuerde ScissorL genau um dessen Versatz nach unten ziehen."""
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()

attach(legmesh, leg)
attach(scu, leg)
attach(scl, scu)                      # <- hier ist die Kompensation entscheidend
attach(slide, slider)
attach(wheel, slider)
attach(door, root)                    # rumpffest, NICHT am Bein


# ------------------------------------------------------------- Animation
# Frame 1 = ausgefahren (Ruhepose), Frame 30 = eingefahren.
# AircraftBody scrubbt per seek() -> laeuft synchron vor UND rueckwaerts.
#
# WICHTIG: ALLE animierten Objekte muessen in EINER Animation "retract" landen
# (AircraftBody sucht per has_animation("retract")). Getrennte Actions ergaeben
# getrennte glTF-Animationen — auch export_animation_mode='SCENE' fuehrt sie NICHT
# zusammen. Loesung: eine Action mit je einem SLOT pro Objekt (Blender 4.4+).
act = bpy.data.actions.new("retract")
strip = act.layers.new("Layer").strips.new(type='KEYFRAME')

def bind(ob):
    ob.animation_data_create()
    ob.animation_data.action = act
    slot = act.slots.new('OBJECT', ob.name)
    ob.animation_data.action_slot = slot
    strip.channelbag(slot, ensure=True)
    return slot

ANIMIERT = (pivot, door, slider, scu, scl)
SLOTS = {ob: bind(ob) for ob in ANIMIERT}

def key(o, path, idx, frames):
    o.rotation_mode = 'XYZ'
    for fr, val in frames:
        vec = list(getattr(o, path))
        vec[idx] = val
        setattr(o, path, vec)
        o.keyframe_insert(data_path=path, index=idx, frame=fr)

# Bein klappt um X nach VORN hoch, mit Ueberschwinger/Einrasten
FOLD = [(1, 0.0), (10, radians(24.0)), (24, radians(91.5)), (30, radians(88.0))]
key(pivot, "rotation_euler", 0, FOLD)
# Klappe: haengt ausgefahren nach unten, schwenkt beim Einfahren nach innen zu
key(door, "rotation_euler", 1, [(1, 0.0), (7, radians(-6.0)), (20, radians(-30.0)), (30, radians(-88.0))])

# Teleskop: der Kolben faehrt ein, sobald das Rad frei haengt (etwas nach dem Klappen).
TELE_KEYS = [(1, 0.0), (6, 0.0), (14, TELE * 0.45), (26, TELE), (30, TELE)]
key(slider, "location", 2, TELE_KEYS)
# ... und die Schere klappt exakt dazu passend zu (Zweigelenk-Kinematik).
scu_keys, scl_keys = [], []
for fr, dz in TELE_KEYS:
    k = knie(dz)
    l = (SC_L[0], SC_L[1] + dz)
    w1 = winkel(SC_U, k) - W1_0
    w2 = winkel(k, l) - W2_0
    scu_keys.append((fr, w1))
    scl_keys.append((fr, w2 - w1))        # lokal, da ScissorL Kind von ScissorU ist
key(scu, "rotation_euler", 0, scu_keys)
key(scl, "rotation_euler", 0, scl_keys)

for ob, slot in SLOTS.items():
    for fc in strip.channelbag(slot).fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'
            kp.easing = 'EASE_IN_OUT'

sc.frame_set(1)                                       # Ruhepose = ausgefahren

# ---------------------------------------------------------------- Export
bpy.ops.object.select_all(action='DESELECT')
for o in (root, pivot, leg, extend, slider, legmesh, slide, wheel, scu, scl, door):
    o.select_set(True)
bpy.context.view_layer.objects.active = root
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format='GLB', use_selection=True,
    export_yup=True, export_apply=False,
    export_animations=True, export_animation_mode='ACTIONS',   # 1 Action -> 1 Animation
    export_frame_range=True, export_bake_animation=True,
)
print("EXPORTED", OUT)
print("Teleskopweg %.3f m | Schere: L1=%.3f L2=%.3f" % (TELE, L1, L2))
