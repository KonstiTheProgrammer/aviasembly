# B-29-Rumpfsegment (models/fuselage_b29.glb).
#
# WARUM EIGENES TEIL: die B-29-Kanzel ist NICHT rund. Ihre hintere Andockflaeche ist ein
# ZWOELFECK — 12 Punkte auf einer Ellipse mit den Halbachsen 0.84 (Breite) und 0.74 (Hoehe),
# Mittelpunkt 0.04 ueber der Teilmitte. Aus models/cockpit_b29.glb nachgemessen:
#   t=0    -> (+0.8400, +0.0400)      t=30  -> (+0.7275, +0.4100)
#   t=60   -> (+0.4200, +0.6809)      t=90  -> (+0.0000, +0.7800)
# Das generische Rumpfsegment (shape "box") trifft diesen Querschnitt nicht, an der Naht
# blieb eine Kante. Dieses Segment traegt genau dasselbe Zwoelfeck an BEIDEN Enden und
# schliesst deshalb bundig an — und laesst sich beliebig weiterketten.
#
# Achsen (Projektkonvention): Blender +Y = Godot -Z (vorne), Blender Z = Godot Y (oben).
# Der Querschnitt liegt also in Blender X/Z, die Laenge geht entlang Y.
#
# Usage: blender --background --python tools/build_fuselage_b29.py
import bpy
import bmesh
import math
import mathutils

OUT = "C:/Users/Konst/Projects/aviasembly/models/fuselage_b29.glb"

A = 0.84          # halbe Breite  (Godot X)
B = 0.74          # halbe Hoehe   (Godot Y)
CZ = 0.04         # Mittelpunkt der Ellipse ueber der Teilmitte
LEN = 2.0         # Laenge in Godot Z
SEITEN = 12       # Zwoelfeck wie an der Kanzel


def srgb2lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


MATS = {
    # "body" steht in PartCatalog.PAINT_MATS -> wird beim Lackieren umgefaerbt.
    "body":  ((0.615, 0.635, 0.665), 0.55, 0.42),
    "frame": ((0.30, 0.315, 0.34), 0.50, 0.50),
    "glass": ((0.045, 0.05, 0.065), 0.25, 0.14),
}
MATN = list(MATS.keys())
MI = {n: i for i, n in enumerate(MATN)}


def mat(name):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    col, met, rough = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    lin = srgb2lin(col)
    if b:
        b.inputs["Base Color"].default_value = (*lin, 1.0)
        b.inputs["Metallic"].default_value = met
        b.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*lin, 1.0)
    return m


def profil(f=1.0):
    """Zwoelfeck-Querschnitt, f skaliert radial (fuer eingezogene Fugen)."""
    p = []
    for k in range(SEITEN):
        t = 2.0 * math.pi * k / SEITEN
        p.append((A * f * math.cos(t), CZ + B * f * math.sin(t)))
    return p


def stationen():
    """Laengsstationen: Enden plus je zwei Kanten pro Spantfuge."""
    st = [(-LEN * 0.5, 1.0)]
    for y in (-0.60, 0.0, 0.60):
        st += [(y - 0.030, 1.0), (y - 0.014, 0.985), (y + 0.014, 0.985), (y + 0.030, 1.0)]
    st.append((LEN * 0.5, 1.0))
    return st


def fenster(bm, y, oben):
    """Versenktes Bullauge auf der Facette zwischen t=0 und t=30 Grad (bzw. gespiegelt).

    Auf einem facettierten Rumpf darf das Fenster NICHT auf einer Kante sitzen, sonst
    knickt es. Darum genau auf die Mitte einer Facette gesetzt und dort eingesenkt.
    """
    t0, t1 = 0.0, 2.0 * math.pi / SEITEN
    for sx in (-1.0, 1.0):
        v0 = mathutils.Vector((sx * A * math.cos(t0), 0.0, CZ + B * math.sin(t0)))
        v1 = mathutils.Vector((sx * A * math.cos(t1), 0.0,
                               CZ + B * math.sin(t1) * (1.0 if oben else -1.0)))
        m = (v0 + v1) * 0.5
        d = (v1 - v0).normalized()                       # in der Facette, quer
        n = mathutils.Vector((d.z, 0.0, -d.x)).normalized()
        if n.dot(mathutils.Vector((m.x, 0.0, m.z - CZ))) < 0:
            n = -n                                       # nach AUSSEN zeigen
        e_lang = mathutils.Vector((0.0, 1.0, 0.0))       # entlang des Rumpfs
        r = 0.115
        aussen, innen = [], []
        for k in range(8):
            a = 2.0 * math.pi * k / 8 + math.pi / 8.0
            off = e_lang * (math.cos(a) * r) + d * (math.sin(a) * r * 0.85)
            p = mathutils.Vector((m.x, y, m.z)) + off
            aussen.append(bm.verts.new(p + n * 0.004))
            innen.append(bm.verts.new(p - n * 0.045))
        for k in range(8):
            j = (k + 1) % 8
            try:                                          # Laibung
                bm.faces.new([aussen[k], aussen[j], innen[j], innen[k]]).material_index = MI["frame"]
            except ValueError:
                pass
        try:                                              # Scheibe
            bm.faces.new(list(reversed(innen))).material_index = MI["glass"]
        except ValueError:
            pass


def stringer(bm, t_grad):
    """Aufliegender Laengsstringer auf der Facettenmitte — bricht die kahle Roehre auf."""
    t0 = math.radians(t_grad)
    t1 = t0 + 2.0 * math.pi / SEITEN
    v0 = mathutils.Vector((A * math.cos(t0), 0.0, CZ + B * math.sin(t0)))
    v1 = mathutils.Vector((A * math.cos(t1), 0.0, CZ + B * math.sin(t1)))
    m = (v0 + v1) * 0.5
    d = (v1 - v0).normalized()
    n = mathutils.Vector((d.z, 0.0, -d.x)).normalized()
    if n.dot(mathutils.Vector((m.x, 0.0, m.z - CZ))) < 0:
        n = -n
    # Material "body" statt "frame": ein dunkler Streifen ueber den ganzen Rumpf sah bei
    # blankem Alu wie aufgeklebtes Klebeband aus. Als erhabene Blechrippe in Rumpffarbe
    # zeichnet ihn nur die Kantenlichtung — so sehen echte Stringer aus.
    hb = 0.028
    ring = []
    for y in (-LEN * 0.5 + 0.02, LEN * 0.5 - 0.02):
        vs = []
        for off in ((-hb, 0.0), (hb, 0.0), (hb, 0.011), (-hb, 0.011)):
            p = mathutils.Vector((m.x, y, m.z)) + d * off[0] + n * off[1]
            vs.append(bm.verts.new(p))
        ring.append(vs)
    for k in range(4):
        j = (k + 1) % 4
        try:
            bm.faces.new([ring[0][k], ring[0][j], ring[1][j], ring[1][k]]).material_index = MI["body"]
        except ValueError:
            pass
    for vs, um in ((ring[0], True), (ring[1], False)):
        try:
            bm.faces.new(list(reversed(vs)) if um else list(vs)).material_index = MI["body"]
        except ValueError:
            pass


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    me = bpy.data.meshes.new("B29_Fuselage")
    ob = bpy.data.objects.new("B29_Fuselage", me)
    bpy.context.scene.collection.objects.link(ob)
    for n in MATN:
        me.materials.append(mat(n))

    bm = bmesh.new()
    st = stationen()
    ringe = []
    for y, f in st:
        p = profil(f)
        ringe.append([bm.verts.new((x, y, z)) for x, z in p])
    for i in range(len(ringe) - 1):
        for k in range(SEITEN):
            j = (k + 1) % SEITEN
            try:
                bm.faces.new([ringe[i][k], ringe[i][j],
                              ringe[i + 1][j], ringe[i + 1][k]]).material_index = MI["body"]
            except ValueError:
                pass
    # Ebene Stirnflaechen an BEIDEN Enden: das Segment dockt vorne UND hinten an.
    try:
        bm.faces.new(list(ringe[0])).material_index = MI["body"]
    except ValueError:
        pass
    try:
        bm.faces.new(list(reversed(ringe[-1]))).material_index = MI["body"]
    except ValueError:
        pass

    for y in (-0.30, 0.30):
        fenster(bm, y, True)
    # Stringer NUR auf Vielfachen von 360/12 = 30 Grad: nur dann ist die Strecke v0->v1
    # eine echte Facette. Bei 75 Grad lief die Sehne ueber die Kante am Scheitel hinweg,
    # der Streifen sank dadurch in die Haut ein und las sich als Fuge statt als Profil.
    for t in (30.0, 120.0, 210.0, 300.0):
        stringer(bm, t)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()

    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.shade_flat()             # facettiert wie das Zwoelfeck der Kanzel
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB',
                              use_selection=True, export_apply=True)
    lo = [min((ob.matrix_world @ v.co)[i] for v in me.vertices) for i in range(3)]
    hi = [max((ob.matrix_world @ v.co)[i] for v in me.vertices) for i in range(3)]
    print("=== fuselage_b29: %d Tris" % sum(len(p.vertices) - 2 for p in me.polygons))
    print("    X %+.4f..%+.4f  Y %+.4f..%+.4f  Z %+.4f..%+.4f"
          % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))


main()
