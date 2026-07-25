# Baum-Baukasten fuer die Weltflora -> models/world_trees.glb
#
# WARUM: die bisherigen Baeume waren zwei Formen (Kegelstapel + Knolle) aus GDScript.
# Hier entstehen SIEBEN Arten mit eigener Silhouette, damit ein Wald aus der Luft nicht
# wie ein Muster aussieht: Fichte, Kiefer, Birke, Eiche, Palme, Totholz, Busch.
#
# VERTEX-FARBEN sind Pflicht: TerrainWorld zeichnet alle Flora-MultiMeshes mit dem
# Terrain-Shader (material_override, ALBEDO = COLOR). Ohne Farbattribut waeren die
# Baeume schwarz. Die Werte werden RAW uebernommen (kein srgb2lin), weil auch das
# GDScript sie roh als Vertex-Farbe setzt — sonst passen alte und neue Flora nicht
# zusammen. Damit der glTF-Exporter sie mitnimmt, benutzt das Material einen
# Color-Attribute-Knoten (dann exportiert schon die Standardeinstellung COLOR_0).
#
# GROESSEN: Grundmass wie die alten Meshes (Nadelbaum ~10 m), die Platzierung
# skaliert danach mit 1.1..2.0.
#
# Achsen: Blender Z = oben (in Godot Y). Die Baeume stehen auf z=0.
#
# Usage: blender --background --python tools/build_baeume.py
import bpy
import bmesh
import math
import mathutils
import random

OUT = "C:/Users/Konst/Projects/aviasembly/models/world_trees.glb"

RINDE = (0.30, 0.21, 0.14)
RINDE_HELL = (0.42, 0.31, 0.20)
RINDE_KIEFER = (0.42, 0.24, 0.15)
BIRKE = (0.86, 0.85, 0.80)
TOT = (0.40, 0.36, 0.30)
NADEL = (0.16, 0.40, 0.22)
NADEL_HELL = (0.22, 0.47, 0.26)
KIEFERGRUEN = (0.24, 0.42, 0.20)
LAUB = (0.33, 0.55, 0.24)
BIRKENLAUB = (0.50, 0.66, 0.26)
EICHE = (0.28, 0.47, 0.20)
PALME = (0.30, 0.52, 0.24)
BUSCH = (0.34, 0.50, 0.24)


def _fmul(c, f):
    return (max(c[0] * f, 0.0), max(c[1] * f, 0.0), max(c[2] * f, 0.0))


class Baum:
    """Sammelt Geometrie in EINEM bmesh; jede Flaeche bekommt ihre Farbe direkt."""

    def __init__(self, name, seed):
        self.name = name
        self.bm = bmesh.new()
        # FLOAT-Farbebene, nicht die Byte-Ebene: Blender haelt Byte-Farben fuer sRGB
        # und rechnet sie beim glTF-Export nach Linear um — die Rinde 0.30 kam in
        # Godot als 0.07 an, alle Baeume waeren fast schwarz gewesen. Float-Farben
        # sind bereits linear und gehen unveraendert durch, also exakt die Werte,
        # die auch das GDScript als Vertex-Farbe setzt.
        self.col = self.bm.loops.layers.float_color.new("Color")
        self.rng = random.Random(seed)

    # --- Grundbausteine ---------------------------------------------------------------
    def _faerbe(self, faces, farbe, streuung=0.0):
        for f in faces:
            k = 1.0 + (self.rng.uniform(-streuung, streuung) if streuung > 0.0 else 0.0)
            c = _fmul(farbe, k)
            for l in f.loops:
                l[self.col] = (c[0], c[1], c[2], 1.0)

    def _ring(self, mitte, r, segs, achse=None, phase=0.0, zacken=0.0):
        """Punktring um `mitte`, senkrecht zu `achse` (Standard: Z)."""
        if achse is None:
            achse = mathutils.Vector((0, 0, 1))
        achse = achse.normalized()
        hilf = mathutils.Vector((1, 0, 0))
        if abs(achse.x) > 0.9:
            hilf = mathutils.Vector((0, 1, 0))
        ex = achse.cross(hilf).normalized()
        ey = achse.cross(ex).normalized()
        pts = []
        for i in range(segs):
            a = phase + 2.0 * math.pi * i / segs
            rr = r * (1.0 - zacken if i % 2 else 1.0)
            pts.append(mathutils.Vector(mitte) + ex * (math.cos(a) * rr)
                       + ey * (math.sin(a) * rr))
        return pts

    def _bruecke(self, r0, r1, farbe, streuung=0.06, deckel=False):
        """Zwei Ringe zu einem Mantel verbinden."""
        neu = []
        n = len(r0)
        v0 = [self.bm.verts.new(p) for p in r0]
        v1 = [self.bm.verts.new(p) for p in r1]
        for i in range(n):
            j = (i + 1) % n
            try:
                neu.append(self.bm.faces.new([v0[i], v0[j], v1[j], v1[i]]))
            except ValueError:
                pass
        if deckel:
            try:
                neu.append(self.bm.faces.new(v1))
            except ValueError:
                pass
        self._faerbe(neu, farbe, streuung)

    def stamm(self, p0, p1, r0, r1, farbe, segs=5, streuung=0.10):
        a = mathutils.Vector(p0)
        b = mathutils.Vector(p1)
        d = (b - a)
        self._bruecke(self._ring(a, r0, segs, d), self._ring(b, r1, segs, d), farbe, streuung)

    def kegel(self, z0, z1, r, farbe, segs=7, zacken=0.18, streuung=0.14, hang=0.0):
        """Nadelbaum-Kranz: Ring unten (leicht gezackt) auf eine Spitze."""
        unten = self._ring((0, 0, z0 - hang), r, segs, zacken=zacken)
        mitte = self._ring((0, 0, z0 + (z1 - z0) * 0.12), r * 0.92, segs, zacken=zacken)
        spitze = self.bm.verts.new((0, 0, z1))
        self._bruecke(unten, mitte, farbe, streuung)
        vs = [self.bm.verts.new(p) for p in mitte]
        neu = []
        for i in range(len(vs)):
            j = (i + 1) % len(vs)
            try:
                neu.append(self.bm.faces.new([vs[i], vs[j], spitze]))
            except ValueError:
                pass
        self._faerbe(neu, farbe, streuung)

    def knolle(self, mitte, r, farbe, segs=7, ringe=2, quetsch=1.0, streuung=0.13):
        """Kantige Laubkrone: gestapelte Ringe mit zufaellig gestoertem Radius."""
        m = mathutils.Vector(mitte)
        stufen = []
        for k in range(ringe + 2):
            t = float(k) / (ringe + 1)
            rr = r * math.sin(math.pi * min(max(t, 0.06), 0.94)) ** 0.65
            rr *= self.rng.uniform(0.88, 1.12)
            z = m.z + (t - 0.5) * 2.0 * r * quetsch
            stufen.append(self._ring((m.x, m.y, z), rr, segs,
                                     phase=self.rng.uniform(0, 1.0)))
        for k in range(len(stufen) - 1):
            self._bruecke(stufen[k], stufen[k + 1], farbe, streuung)
        # Deckel oben und unten
        for pts, oben in ((stufen[-1], True), (stufen[0], False)):
            vs = [self.bm.verts.new(p) for p in (pts if oben else list(reversed(pts)))]
            try:
                self._faerbe([self.bm.faces.new(vs)], farbe, streuung)
            except ValueError:
                pass

    def wedel(self, wurzel, richtung, laenge, breite, farbe, knick=0.45):
        """Palmwedel: Mittelrippe die abknickt, links und rechts je ein Blattdreieck."""
        w = mathutils.Vector(wurzel)
        d = mathutils.Vector(richtung).normalized()
        seit = d.cross(mathutils.Vector((0, 0, 1)))
        if seit.length < 0.01:                     # mathutils: length ist eine Eigenschaft
            seit = mathutils.Vector((1, 0, 0))
        seit.normalize()
        pkt = [w]
        for k in range(1, 4):
            t = k / 3.0
            p = w + d * (laenge * t)
            p.z -= knick * laenge * t * t          # haengt nach aussen ab
            pkt.append(p)
        neu = []
        for k in range(3):
            b = breite * (1.0 - k * 0.28)
            for s in (-1.0, 1.0):
                try:
                    neu.append(self.bm.faces.new([
                        self.bm.verts.new(pkt[k]),
                        self.bm.verts.new(pkt[k + 1]),
                        self.bm.verts.new(pkt[k + 1] + seit * (s * b * 0.6)),
                        self.bm.verts.new(pkt[k] + seit * (s * b))]))
                except ValueError:
                    pass
        self._faerbe(neu, farbe, 0.12)

    def objekt(self):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(flora_material())
        for p in me.polygons:
            p.use_smooth = False
        return ob


def flora_material():
    m = bpy.data.materials.get("flora")
    if m is not None:
        return m
    m = bpy.data.materials.new("flora")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Color"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return m


# --- die sieben Arten -----------------------------------------------------------------
def fichte():
    b = Baum("Fichte", 11)
    b.stamm((0, 0, 0), (0, 0, 2.4), 0.26, 0.17, RINDE)
    hoehen = [(1.7, 5.2, 2.55), (3.6, 6.9, 2.05), (5.3, 8.4, 1.55), (6.9, 10.2, 0.95)]
    for i, (z0, z1, r) in enumerate(hoehen):
        f = NADEL if i % 2 == 0 else NADEL_HELL
        b.kegel(z0, z1, r, f, segs=7, zacken=0.22, hang=0.28)
    return b.objekt()


def kiefer():
    b = Baum("Kiefer", 22)
    # gebogener, astfreier Stamm — die Krone sitzt erst ganz oben (Schirmkiefer)
    p = [(0, 0, 0), (0.15, 0.05, 2.6), (0.35, 0.02, 5.2), (0.30, -0.10, 7.4)]
    r = [0.30, 0.24, 0.19, 0.15]
    for i in range(3):
        b.stamm(p[i], p[i + 1], r[i], r[i + 1], RINDE_KIEFER)
    for ast, hoch in (((1.05, 0.5, 8.4), 1.5), ((-0.9, -0.6, 8.1), 1.3), ((0.1, 1.0, 8.8), 1.4)):
        b.stamm(p[3], ast, 0.12, 0.07, RINDE_KIEFER)
        b.knolle(ast, hoch, KIEFERGRUEN, segs=7, ringe=1, quetsch=0.55)
    b.knolle((0.2, 0.0, 8.9), 1.7, KIEFERGRUEN, segs=8, ringe=2, quetsch=0.5)
    return b.objekt()


def birke():
    b = Baum("Birke", 33)
    b.stamm((0, 0, 0), (0.1, 0.05, 4.2), 0.18, 0.12, BIRKE, segs=5, streuung=0.04)
    # dunkle Rindenflecken: kurze Ringe in dunklerem Ton ueber dem hellen Stamm
    for z in (0.8, 1.9, 3.0):
        b.stamm((0.02, 0.02, z), (0.03, 0.03, z + 0.22), 0.185, 0.183,
                (0.20, 0.19, 0.18), segs=5, streuung=0.02)
    aeste = [((0.9, 0.3, 6.2), 1.25), ((-0.8, 0.5, 5.9), 1.15), ((0.1, -0.9, 6.6), 1.20)]
    for spitze, rr in aeste:
        b.stamm((0.1, 0.05, 4.0), spitze, 0.09, 0.05, BIRKE, segs=4, streuung=0.04)
        b.knolle(spitze, rr, BIRKENLAUB, segs=7, ringe=2, quetsch=0.85)
    b.knolle((0.1, 0.0, 7.0), 1.35, BIRKENLAUB, segs=7, ringe=2, quetsch=0.9)
    return b.objekt()


def eiche():
    b = Baum("Eiche", 44)
    b.stamm((0, 0, 0), (0, 0, 2.6), 0.52, 0.36, RINDE, segs=6)
    aeste = [((1.5, 0.4, 4.6), 1.9), ((-1.3, 0.9, 4.3), 1.8), ((0.3, -1.5, 4.5), 1.75),
             ((0.0, 0.2, 5.6), 2.1)]
    for spitze, rr in aeste:
        b.stamm((0, 0, 2.4), spitze, 0.22, 0.12, RINDE_HELL, segs=5)
        b.knolle(spitze, rr, EICHE, segs=8, ringe=2, quetsch=0.72)
    return b.objekt()


def palme():
    b = Baum("Palme", 55)
    p = [(0, 0, 0)]
    for k in range(1, 6):
        t = k / 5.0
        p.append((1.1 * t * t, 0.25 * t * t, 6.0 * t))
    for i in range(5):
        b.stamm(p[i], p[i + 1], 0.30 - i * 0.035, 0.27 - i * 0.035,
                RINDE_HELL, segs=6, streuung=0.12)
    kopf = mathutils.Vector(p[-1])
    for i in range(8):
        a = 2.0 * math.pi * i / 8 + 0.2
        d = mathutils.Vector((math.cos(a), math.sin(a), 0.55))
        b.wedel(kopf, d, 2.9, 0.62, PALME, knick=0.60)
    b.knolle((kopf.x, kopf.y, kopf.z + 0.15), 0.42, _fmul(PALME, 0.75), segs=6, ringe=1)
    return b.objekt()


def totholz():
    b = Baum("Totholz", 66)
    p = [(0, 0, 0), (0.1, 0.06, 2.2), (0.22, 0.0, 4.3), (0.18, -0.12, 5.6)]
    r = [0.34, 0.26, 0.18, 0.10]
    for i in range(3):
        b.stamm(p[i], p[i + 1], r[i], r[i + 1], TOT, segs=5, streuung=0.16)
    for start, ende, rr in (((0.1, 0.06, 2.3), (1.5, 0.4, 3.4), 0.13),
                            ((0.2, 0.0, 3.6), (-1.3, 0.7, 4.5), 0.11),
                            ((0.22, 0.0, 4.4), (0.6, -1.2, 5.2), 0.09),
                            ((0.18, -0.1, 5.2), (-0.7, -0.5, 6.1), 0.07)):
        b.stamm(start, ende, rr, rr * 0.35, TOT, segs=4, streuung=0.16)
    return b.objekt()


def busch():
    b = Baum("Busch", 77)
    for dx, dy, dz, rr in ((0.0, 0.0, 0.75, 0.85), (0.55, 0.25, 0.55, 0.62),
                           (-0.45, 0.35, 0.50, 0.55), (0.15, -0.55, 0.48, 0.52)):
        b.knolle((dx, dy, dz), rr, BUSCH, segs=6, ringe=1, quetsch=0.8)
    return b.objekt()


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    obs = [fichte(), kiefer(), birke(), eiche(), palme(), totholz(), busch()]
    bpy.ops.object.select_all(action='SELECT')
    kw = dict(filepath=OUT, export_format='GLB', use_selection=False,
              export_apply=True, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
        print("Export mit export_vertex_color='ACTIVE'")
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
        print("Export mit Standardeinstellungen (Material nutzt Color-Attribute)")
    for ob in obs:
        me = ob.data
        hoch = max((ob.matrix_world @ v.co).z for v in me.vertices)
        print("  %-10s %4d Tris  Hoehe %.2f m  Farbattribute: %s"
              % (ob.name, sum(len(p.vertices) - 2 for p in me.polygons), hoch,
                 ",".join(a.name for a in me.color_attributes)))


main()
