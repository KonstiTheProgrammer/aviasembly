# blender_lib/gebaeude.blend  ->  blender_lib/haeuser.blend  (Kopie + viele neue Haeuser)
#
# Baut 22 zusaetzliche Gebaeude-Varianten im STIL DES SPIELS (Low-Poly, flat shaded,
# gedeckte Palette wie Landmarks.gd) direkt neben die bereits exportierten Original-
# Bauwerke — so kann man Proportion/Farbe/Detailgrad im selben File vergleichen.
#
# PERFORMANCE-REGELN (bewusst eingehalten, das Terrain streamt schon genug):
#   * EIN Mesh-Objekt je Haus (Multi-Material statt vieler Objekte) -> MultiMesh-tauglich
#   * verdeckte Flaechen (Bodenplatten, Dachunterseiten) werden NICHT erzeugt
#   * Fenster/Tueren/Balken sind FLACHE QUADS (2 Tris) minimal vor der Wand, keine Boxen
#   * flat shading, keine Texturen/UVs — Farbe kommt aus dem Material wie im Spiel
#   * Zielbudget: Wohnhaus 40-120 Tris, Wahrzeichen (Kirche/Muehle/Hangar) < 400 Tris
#
# Blender ist Z-up; glTF-Export (+Y up) macht daraus Godot-Y -> Haeuser stehen richtig.
# Alle Haeuser schauen nach -Y (Vorderseite), damit man sie einheitlich platzieren kann.
#
# Usage:  blender --background --python tools/build_haeuser_blend.py
#         HAEUSER_PREVIEW=<ordner> blender --background --python tools/build_haeuser_blend.py
import bpy
import math
import os
import shutil
from mathutils import Vector

ROOT = "C:/Users/Konst/Projects/aviasembly/"
SRC = ROOT + "blender_lib/gebaeude.blend"
OUT = ROOT + "blender_lib/haeuser.blend"
PREVIEW = os.environ.get("HAEUSER_PREVIEW", "")

# --- Palette (sRGB wie im Spiel; Blender-BaseColor ist LINEAR -> umrechnen) ---------------
PAL = {
    "wand_creme":   (0.87, 0.83, 0.74),
    "wand_sand":    (0.86, 0.79, 0.62),
    "wand_terra":   (0.80, 0.55, 0.42),
    "wand_grau":    (0.72, 0.74, 0.69),
    "wand_taupe":   (0.68, 0.64, 0.62),
    "wand_mauve":   (0.78, 0.70, 0.66),
    "wand_weiss":   (0.93, 0.92, 0.89),
    "wand_ocker":   (0.82, 0.70, 0.45),
    "wand_blau":    (0.70, 0.76, 0.80),
    "stein":        (0.60, 0.59, 0.56),
    "beton":        (0.66, 0.66, 0.64),
    "ziegel":       (0.66, 0.36, 0.28),
    "dach_terra":   (0.47, 0.27, 0.22),
    "dach_schiefer": (0.34, 0.36, 0.41),
    "dach_stroh":   (0.68, 0.56, 0.32),
    "dach_kupfer":  (0.30, 0.55, 0.48),
    "dach_rot":     (0.55, 0.24, 0.19),
    "holz_dunkel":  (0.34, 0.27, 0.18),
    "holz_hell":    (0.55, 0.42, 0.26),
    "holz_rot":     (0.50, 0.24, 0.20),
    "fenster":      (0.14, 0.17, 0.22),
    "metall":       (0.55, 0.57, 0.60),
    "metall_dunkel": (0.30, 0.32, 0.35),
    "gruen":        (0.32, 0.42, 0.28),
    "glas":         (0.30, 0.45, 0.52),
}


def srgb2lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def get_mat(key):
    name = "H_" + key
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    rgb = PAL[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    lin = srgb2lin(rgb)
    if b:
        b.inputs["Base Color"].default_value = (*lin, 1.0)
        b.inputs["Roughness"].default_value = 0.9
        b.inputs["Metallic"].default_value = 0.6 if key.startswith("metall") else 0.0
    m.diffuse_color = (*lin, 1.0)   # Workbench/Viewport
    return m


# --- Geometrie-Baukasten -------------------------------------------------------------------
class Bau:
    """Sammelt Verts/Faces je Material und wird am Ende EIN Mesh-Objekt."""

    def __init__(self, name):
        self.name = name
        self.v = []
        self.f = []          # (indices, material_index)
        self.mats = []

    def _mi(self, key):
        if key not in self.mats:
            self.mats.append(key)
        return self.mats.index(key)

    def add(self, verts, faces, key):
        base = len(self.v)
        mi = self._mi(key)
        self.v.extend(tuple(p) for p in verts)
        for fc in faces:
            self.f.append(([base + i for i in fc], mi))

    # Quader; z = UNTERKANTE. skip: 'bottom','top','-y','+y','-x','+x'
    def box(self, x, y, z, sx, sy, h, key, skip=("bottom",)):
        x0, x1 = x - sx * 0.5, x + sx * 0.5
        y0, y1 = y - sy * 0.5, y + sy * 0.5
        z0, z1 = z, z + h
        V = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
             (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        F = []
        if "bottom" not in skip:
            F.append((0, 3, 2, 1))
        if "top" not in skip:
            F.append((4, 5, 6, 7))
        if "-y" not in skip:
            F.append((0, 1, 5, 4))
        if "+x" not in skip:
            F.append((1, 2, 6, 5))
        if "+y" not in skip:
            F.append((2, 3, 7, 6))
        if "-x" not in skip:
            F.append((3, 0, 4, 7))
        self.add(V, F, key)

    # Satteldach (First laengs 'axis'); inset > 0 macht daraus ein WALMDACH.
    # over = Dachueberstand rundum. Unterseite entfaellt (unsichtbar).
    def dach(self, x, y, z, w, d, h, key, axis="x", inset=0.0, over=0.4):
        w += over * 2.0
        d += over * 2.0
        hw, hd = w * 0.5, d * 0.5
        ins = min(inset, hd - 0.01)
        V = [(-hw, -hd, 0.0), (hw, -hd, 0.0), (hw, hd, 0.0), (-hw, hd, 0.0),
             (0.0, -hd + ins, h), (0.0, hd - ins, h)]
        F = [(0, 4, 5, 3), (1, 2, 5, 4), (0, 1, 4), (3, 5, 2)]
        if axis == "x":   # First laeuft in X -> lokales System drehen
            V = [(p[1], p[0], p[2]) for p in V]
            F = [tuple(reversed(fc)) for fc in F]
        self.add([(x + p[0], y + p[1], z + p[2]) for p in V], F, key)

    # Pyramidendach / Turmspitze
    def spitze(self, x, y, z, w, d, h, key, over=0.0):
        w += over * 2.0
        d += over * 2.0
        hw, hd = w * 0.5, d * 0.5
        V = [(x - hw, y - hd, z), (x + hw, y - hd, z), (x + hw, y + hd, z), (x - hw, y + hd, z),
             (x, y, z + h)]
        self.add(V, [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], key)

    # Pultdach (eine geneigte Flaeche), steigt in +y
    def pultdach(self, x, y, z, w, d, h, key, over=0.3):
        w += over * 2.0
        d += over * 2.0
        hw, hd = w * 0.5, d * 0.5
        t = 0.25   # Dachstaerke
        V = [(x - hw, y - hd, z), (x + hw, y - hd, z), (x + hw, y + hd, z + h), (x - hw, y + hd, z + h),
             (x - hw, y - hd, z + t), (x + hw, y - hd, z + t), (x + hw, y + hd, z + h + t), (x - hw, y + hd, z + h + t)]
        self.add(V, [(4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], key)

    # n-seitiger Zylinder/Kegelstumpf; z = Unterkante.
    # achse="y" kippt ihn auf die Y-Achse (liegender Tank) — die Abbildung
    # (x,y,z)->(x,z,-y) ist eine ECHTE Drehung (det=+1), Wicklung bleibt gueltig.
    def zyl(self, x, y, z, r0, r1, h, sides, key, cap_top=True, cap_bottom=False, achse="z"):
        V = []
        for i in range(sides):
            a = 2.0 * math.pi * i / sides
            V.append((math.cos(a) * r0, math.sin(a) * r0, 0.0))
        for i in range(sides):
            a = 2.0 * math.pi * i / sides
            V.append((math.cos(a) * r1, math.sin(a) * r1, h))
        F = []
        for i in range(sides):
            j = (i + 1) % sides
            F.append((i, j, sides + j, sides + i))
        if cap_top:
            F.append(tuple(range(sides, sides * 2)))
        if cap_bottom:
            F.append(tuple(reversed(range(sides))))
        if achse == "y":
            V = [(p[0], p[2], -p[1]) for p in V]
        self.add([(x + p[0], y + p[1], z + p[2]) for p in V], F, key)

    # Kegel (Turmdach/Silodach)
    def kegel(self, x, y, z, r, h, sides, key):
        V = []
        for i in range(sides):
            a = 2.0 * math.pi * i / sides
            V.append((x + math.cos(a) * r, y + math.sin(a) * r, z))
        V.append((x, y, z + h))
        self.add(V, [(i, (i + 1) % sides, sides) for i in range(sides)], key)

    # Flaches Rechteck AUF einer Wand (Fenster/Tuer/Balken) — 2 Tris statt einer Box.
    def feld(self, ctr, w, h, facing, key, eps=0.04, winkel=0.0):
        n = {"+x": (1, 0, 0), "-x": (-1, 0, 0), "+y": (0, 1, 0), "-y": (0, -1, 0)}[facing]
        u = (1, 0, 0) if facing in ("+y", "-y") else (0, 1, 0)
        v = (0, 0, 1)
        cw, sw = math.cos(winkel), math.sin(winkel)
        U = tuple(u[i] * cw + v[i] * sw for i in range(3))
        V2 = tuple(-u[i] * sw + v[i] * cw for i in range(3))
        o = tuple(ctr[i] + n[i] * eps for i in range(3))
        pts = [tuple(o[i] + U[i] * du * w * 0.5 + V2[i] * dv * h * 0.5 for i in range(3))
               for du, dv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        nn = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[0]))
        if nn.dot(Vector(n)) < 0:
            pts = pts[::-1]
        self.add(pts, [(0, 1, 2, 3)], key)

    def fenster_reihe(self, facing, fixed, u_ctr, u_span, z, n, w, h, key="fenster"):
        for i in range(n):
            t = (i + 0.5) / n - 0.5
            u = u_ctr + t * u_span
            ctr = (u, fixed, z) if facing in ("+y", "-y") else (fixed, u, z)
            self.feld(ctr, w, h, facing, key)

    # Profil (Liste (x,z)) entlang Y extrudiert — fuer Hallenbogen/Tonnendach.
    def profil(self, x, y, z, prof, laenge, key, caps=True):
        n = len(prof)
        y0, y1 = y - laenge * 0.5, y + laenge * 0.5
        V = [(x + px, y0, z + pz) for px, pz in prof] + [(x + px, y1, z + pz) for px, pz in prof]
        F = [(i, i + 1, n + i + 1, n + i) for i in range(n - 1)]
        if caps:
            F.append(tuple(reversed(range(n))))
            F.append(tuple(range(n, 2 * n)))
        self.add(V, F, key)

    # Rad (Wasserrad/Muehlrad): zwei Felgenringe + Schaufeln
    def rad(self, x, y, z, r, breite, sides, key_holz):
        ri = r * 0.62
        for s in (-1, 1):
            yy = y + s * breite * 0.5
            V = []
            for i in range(sides):
                a = 2.0 * math.pi * i / sides
                V.append((x + math.cos(a) * ri, yy, z + math.sin(a) * ri))
                V.append((x + math.cos(a) * r, yy, z + math.sin(a) * r))
            F = []
            for i in range(sides):
                j = (i + 1) % sides
                F.append((i * 2, i * 2 + 1, j * 2 + 1, j * 2))
            self.add(V, F, key_holz)
        for i in range(sides):
            a = 2.0 * math.pi * i / sides
            cx, cz = math.cos(a), math.sin(a)
            V = [(x + cx * ri, y - breite * 0.5, z + cz * ri), (x + cx * r, y - breite * 0.5, z + cz * r),
                 (x + cx * r, y + breite * 0.5, z + cz * r), (x + cx * ri, y + breite * 0.5, z + cz * ri)]
            self.add(V, [(0, 1, 2, 3)], key_holz)

    def build(self, parent_col, ort):
        me = bpy.data.meshes.new(self.name)
        me.from_pydata(self.v, [], [fc for fc, _ in self.f])
        me.update()
        for key in self.mats:
            me.materials.append(get_mat(key))
        for poly, (_, mi) in zip(me.polygons, self.f):
            poly.material_index = mi
            poly.use_smooth = False
        me.validate()
        ob = bpy.data.objects.new(self.name, me)
        ob.location = (ort[0], ort[1], 0.0)
        col = bpy.data.collections.new(self.name)
        parent_col.children.link(col)
        col.objects.link(ob)
        return ob


# --- Die Haeuser ---------------------------------------------------------------------------
def bauernhaus(b):
    b.box(0, 0, 0, 11, 8, 4.2, "wand_creme")
    b.dach(0, 0, 4.2, 11, 8, 3.2, "dach_terra", axis="x")
    b.box(3.0, 1.2, 7.0, 0.9, 0.9, 1.9, "ziegel")
    b.fenster_reihe("-y", -4.0, 0, 8.0, 2.5, 3, 1.3, 1.4)
    b.fenster_reihe("+y", 4.0, 0, 8.0, 2.5, 3, 1.3, 1.4)
    b.feld((-3.0, -4.0, 1.05), 1.3, 2.1, "-y", "holz_dunkel")
    b.feld((0.0, -4.0, 5.6), 1.6, 1.2, "-y", "fenster")   # Giebelluke


def fachwerkhaus(b):
    b.box(0, 0, 0, 8, 7, 7.4, "wand_weiss")
    b.dach(0, 0, 7.4, 8, 7, 3.8, "dach_terra", axis="x", over=0.5)
    b.box(2.2, 0.8, 10.2, 0.8, 0.8, 1.6, "ziegel")
    for facing, fx in (("-y", -3.5), ("+y", 3.5)):
        for z in (0.15, 3.6, 7.1):                       # Geschossbaender
            b.feld((0, fx, z), 8.0, 0.32, facing, "holz_dunkel")
        for x in (-3.6, -1.2, 1.2, 3.6):                 # Staender
            b.feld((x, fx, 3.7), 0.3, 7.2, facing, "holz_dunkel")
        for x, s in ((-2.4, 1), (2.4, -1)):              # Andreaskreuz-Streben
            b.feld((x, fx, 5.4), 0.28, 3.9, facing, "holz_dunkel", winkel=s * 0.55)
            b.feld((x, fx, 1.9), 0.28, 3.9, facing, "holz_dunkel", winkel=-s * 0.55)
    b.fenster_reihe("-y", -3.5, 0, 4.9, 5.4, 2, 1.1, 1.3)
    b.fenster_reihe("-y", -3.5, 0, 4.9, 1.9, 2, 1.1, 1.3)
    b.feld((0.0, -3.5, 1.0), 1.2, 2.0, "-y", "holz_hell")


def kate(b):
    b.box(0, 0, 0, 6.5, 5.5, 2.9, "wand_sand")
    b.dach(0, 0, 2.9, 6.5, 5.5, 2.9, "dach_stroh", axis="x", over=0.7)
    b.box(1.6, 0.6, 5.3, 0.7, 0.7, 1.3, "stein")
    b.fenster_reihe("-y", -2.75, -1.4, 2.0, 1.6, 1, 1.0, 1.0)
    b.feld((1.5, -2.75, 0.95), 1.0, 1.9, "-y", "holz_dunkel")


def scheune(b):
    b.box(0, 0, 0, 14, 9, 5.0, "holz_rot")
    b.dach(0, 0, 5.0, 14, 9, 4.2, "dach_schiefer", axis="x", over=0.5)
    b.feld((0, -4.5, 2.1), 5.0, 4.2, "-y", "holz_dunkel")      # Tor
    b.feld((0, -4.5, 2.1), 0.3, 4.2, "-y", "wand_weiss")       # Torbalken
    b.feld((0, -4.5, 3.6), 5.0, 0.3, "-y", "wand_weiss")
    b.fenster_reihe("-y", -4.5, -4.6, 3.0, 3.4, 1, 1.1, 1.1)
    b.fenster_reihe("-y", -4.5, 4.6, 3.0, 3.4, 1, 1.1, 1.1)
    b.fenster_reihe("+y", 4.5, 0, 9.0, 3.4, 3, 1.1, 1.1)


def stall(b):
    b.box(0, 0, 0, 10, 6, 2.9, "wand_taupe")
    b.pultdach(0, 0, 2.9, 10, 6, 1.3, "dach_schiefer")
    b.fenster_reihe("-y", -3.0, 0, 8.0, 1.9, 4, 1.0, 0.9)
    b.feld((3.6, -3.0, 1.1), 1.6, 2.2, "-y", "holz_hell")


def silo(b):
    b.zyl(0, 0, 0, 2.3, 2.3, 9.5, 10, "metall")
    b.kegel(0, 0, 9.5, 2.3, 2.1, 10, "metall_dunkel")
    b.box(3.9, 0, 0, 4.0, 5.0, 2.8, "wand_grau")
    b.pultdach(3.9, 0, 2.8, 4.0, 5.0, 0.9, "metall_dunkel")
    for z in (2.6, 5.2, 7.8):
        b.feld((0, -2.3, z), 3.2, 0.18, "-y", "metall_dunkel", eps=0.05)


def wassermuehle(b):
    b.box(0, 0, 0, 9, 7.5, 6.8, "wand_creme")
    b.dach(0, 0, 6.8, 9, 7.5, 3.4, "dach_schiefer", axis="x", over=0.5)
    b.box(-2.0, 1.0, 10.2, 0.8, 0.8, 1.4, "ziegel")
    b.box(-5.6, 0, 0, 2.4, 2.0, 1.4, "stein")               # Wasserlauf/Gerinne
    b.rad(-5.9, 0, 3.0, 2.8, 1.5, 10, "holz_dunkel")
    b.fenster_reihe("-y", -3.75, 0, 6.0, 4.8, 2, 1.1, 1.3)
    b.fenster_reihe("-y", -3.75, 0, 6.0, 2.0, 2, 1.1, 1.3)
    b.feld((2.6, -3.75, 1.05), 1.2, 2.1, "-y", "holz_dunkel")


def windmuehle(b):
    b.zyl(0, 0, 0, 4.0, 2.7, 11.0, 10, "wand_weiss", cap_top=False)
    b.kegel(0, 0, 11.0, 2.9, 2.6, 10, "dach_schiefer")
    b.zyl(0, 0, 5.4, 4.2, 4.2, 0.25, 10, "holz_dunkel")     # Umlaufgalerie
    b.box(0, -3.1, 10.4, 1.0, 1.6, 1.0, "holz_dunkel")      # Wellenkopf
    # ZWEI gekreuzte Fluegelbahnen = 4 Arme. (Vier Panels waeren zwei Duplikate:
    # ein um 180 Grad gedrehtes Rechteck ist mit sich selbst deckungsgleich -> Z-Fighting.)
    for k in range(2):
        a = k * math.pi * 0.5 + 0.35
        b.feld((0, -3.9, 10.9), 1.6, 14.0, "-y", "holz_hell", eps=0.0, winkel=a)
        b.feld((0, -4.05, 10.9), 0.4, 14.4, "-y", "holz_dunkel", eps=0.0, winkel=a)
    b.feld((0, -4.0, 2.0), 1.3, 2.4, "-y", "holz_dunkel", eps=0.1)


def stadthaus2(b):
    b.box(0, 0, 0, 9, 8, 7.6, "wand_terra")
    b.dach(0, 0, 7.6, 9, 8, 3.4, "dach_schiefer", axis="y", over=0.35)
    b.box(0, 2.6, 10.6, 0.8, 0.8, 1.5, "ziegel")
    b.fenster_reihe("-y", -4.0, 0, 6.4, 5.6, 3, 1.2, 1.5)
    b.fenster_reihe("-y", -4.0, 2.2, 4.2, 2.0, 2, 1.2, 1.5)
    b.feld((-2.6, -4.0, 1.1), 1.3, 2.2, "-y", "holz_dunkel")
    b.feld((0, -4.0, 9.0), 1.2, 1.1, "-y", "fenster")


def stadthaus3(b):
    b.box(0, 0, 0, 6.5, 9, 10.8, "wand_ocker")
    b.dach(0, 0, 10.8, 6.5, 9, 3.0, "dach_terra", axis="y", over=0.3)
    b.box(0, 3.0, 13.8, 0.7, 0.7, 1.4, "ziegel")
    for z in (2.6, 5.6, 8.6):
        b.fenster_reihe("-y", -4.5, 0, 4.6, z, 2, 1.1, 1.6)
        b.feld((0, -4.5, z + 1.15), 4.9, 0.16, "-y", "wand_weiss")   # Gesimsband
    b.feld((0, -4.5, 1.15), 1.4, 2.3, "-y", "holz_dunkel")
    b.feld((0, -4.5, 12.0), 1.1, 1.0, "-y", "fenster")


def reihenhaus(b):
    farben = ("wand_creme", "wand_mauve", "wand_blau")
    for i, c in enumerate(farben):
        x = (i - 1) * 5.6
        b.box(x, 0, 0, 5.6, 8, 7.4, c, skip=("bottom", "top"))
        b.fenster_reihe("-y", -4.0, x, 3.4, 5.4, 2, 1.0, 1.4)
        b.fenster_reihe("-y", -4.0, x + 1.4, 0.1, 2.0, 1, 1.0, 1.4)
        b.feld((x - 1.5, -4.0, 1.05), 1.2, 2.1, "-y", "holz_dunkel")
        b.box(x + 1.8, 2.4, 9.8, 0.7, 0.7, 1.3, "ziegel")
    b.dach(0, 0, 7.4, 16.8, 8, 3.0, "dach_schiefer", axis="x", over=0.4)


def eckhaus(b):
    b.box(-2.0, 0, 0, 9, 8, 7.4, "wand_sand")
    b.box(4.0, 3.0, 0, 7, 6, 7.4, "wand_sand")
    b.dach(-2.0, 0, 7.4, 9, 8, 2.8, "dach_terra", axis="x", inset=1.4, over=0.4)
    b.dach(4.0, 3.0, 7.4, 7, 6, 2.4, "dach_terra", axis="y", inset=1.2, over=0.4)
    b.fenster_reihe("-y", -4.0, -2.0, 6.2, 5.4, 3, 1.1, 1.4)
    b.fenster_reihe("-y", -4.0, -2.0, 6.2, 2.2, 3, 1.1, 1.4)
    b.fenster_reihe("-x", -6.5, 0, 5.4, 5.4, 2, 1.1, 1.4)
    b.feld((-2.0, -4.0, 1.1), 1.4, 2.2, "-y", "holz_dunkel")
    b.box(1.0, 4.4, 8.6, 0.8, 0.8, 1.4, "ziegel")


def gasthaus(b):
    b.box(0, 0, 0, 12, 9, 7.4, "wand_creme")
    b.dach(0, 0, 7.4, 12, 9, 3.6, "dach_terra", axis="x", over=0.5)
    b.box(-3.4, 2.8, 10.4, 0.9, 0.9, 1.6, "ziegel")
    b.box(0, -5.6, 3.0, 9.0, 2.4, 0.25, "holz_dunkel")        # Vordach
    for x in (-4.0, 0.0, 4.0):
        b.box(x, -6.5, 0, 0.28, 0.28, 3.0, "holz_dunkel")
    b.fenster_reihe("-y", -4.5, 0, 8.4, 5.6, 4, 1.1, 1.4)
    b.fenster_reihe("-y", -4.5, -3.2, 3.2, 1.9, 2, 1.2, 1.5)
    b.feld((2.4, -4.5, 1.15), 1.5, 2.3, "-y", "holz_dunkel")
    b.box(6.4, -3.6, 3.4, 0.2, 2.4, 0.2, "holz_dunkel")       # Ausleger + Schild
    b.feld((6.4, -4.7, 2.6), 0.1, 1.4, "-x", "gruen", eps=0.6)


def villa(b):
    b.box(0, 0, 0, 13, 10, 7.8, "wand_weiss")
    b.dach(0, 0, 7.8, 13, 10, 3.0, "dach_schiefer", axis="x", inset=2.2, over=0.6)
    b.box(-4.2, 3.4, 10.8, 0.8, 0.8, 1.5, "ziegel")
    b.box(0, -6.4, 3.6, 8.0, 3.0, 0.3, "wand_weiss")          # Veranda-Dach/Balkon
    for x in (-3.6, -1.2, 1.2, 3.6):
        b.box(x, -6.6, 0, 0.35, 0.35, 3.6, "wand_weiss")
    for x in (-3.6, 3.6):                                      # Balkongelaender
        b.feld((x, -7.9, 4.4), 0.2, 1.0, "-y", "wand_weiss", eps=0.0)
    b.feld((0, -7.9, 4.3), 8.0, 0.9, "-y", "wand_weiss", eps=0.0)
    b.fenster_reihe("-y", -5.0, 0, 9.6, 5.6, 4, 1.3, 1.7)
    b.fenster_reihe("-y", -5.0, -3.6, 4.0, 1.9, 2, 1.3, 1.9)
    b.feld((0, -5.0, 1.2), 1.8, 2.4, "-y", "holz_dunkel")


def kirche(b):
    b.box(0, 2.0, 0, 11, 20, 8.4, "wand_creme")               # Langhaus
    b.dach(0, 2.0, 8.4, 11, 20, 4.6, "dach_schiefer", axis="y", over=0.5)
    b.box(0, -10.0, 0, 6.4, 6.4, 17.0, "wand_creme")          # Westturm
    b.box(0, -10.0, 17.0, 7.0, 7.0, 0.5, "stein")
    b.spitze(0, -10.0, 17.5, 6.0, 6.0, 9.5, "dach_kupfer")
    b.zyl(0, -10.0, 27.0, 0.16, 0.16, 1.8, 6, "metall")       # Kreuz
    b.feld((0, -10.0, 28.1), 1.0, 0.2, "-y", "metall", eps=0.2)
    b.zyl(0, 12.6, 0, 4.2, 4.2, 8.4, 8, "wand_creme", cap_top=False)   # Apsis
    b.kegel(0, 12.6, 8.4, 4.4, 3.2, 8, "dach_schiefer")
    for y in (-3.5, 1.5, 6.5):                                 # Kirchenfenster
        b.feld((-5.5, y, 5.0), 1.3, 3.4, "-x", "glas")
        b.feld((5.5, y, 5.0), 1.3, 3.4, "+x", "glas")
    b.feld((0, -13.2, 15.0), 1.6, 2.2, "-y", "fenster")       # Schallluke
    b.feld((0, -13.2, 11.4), 2.2, 2.2, "-y", "wand_weiss")    # Zifferblatt
    b.feld((0, -13.2, 11.4), 1.7, 1.7, "-y", "fenster", eps=0.08)
    b.feld((0, -13.2, 1.6), 2.2, 3.2, "-y", "holz_dunkel")    # Portal


def kapelle(b):
    b.box(0, 0, 0, 5.4, 8, 4.2, "wand_weiss")
    b.dach(0, 0, 4.2, 5.4, 8, 2.4, "dach_terra", axis="y", over=0.4)
    b.box(0, -2.6, 6.6, 1.7, 1.7, 2.2, "wand_weiss")          # Dachreiter
    b.spitze(0, -2.6, 8.8, 1.9, 1.9, 2.4, "dach_kupfer")
    b.feld((0, -4.0, 1.4), 1.2, 2.4, "-y", "holz_dunkel")
    b.feld((0, -4.0, 4.6), 0.9, 1.1, "-y", "glas")
    for y in (-1.0, 2.0):
        b.feld((-2.7, y, 2.6), 0.9, 2.2, "-x", "glas")
        b.feld((2.7, y, 2.6), 0.9, 2.2, "+x", "glas")


def rathaus(b):
    b.box(0, 0, 0, 15, 10, 8.0, "wand_sand")
    b.dach(0, 0, 8.0, 15, 10, 3.0, "dach_schiefer", axis="x", inset=2.0, over=0.5)
    b.box(0, -1.0, 0, 4.6, 4.6, 15.0, "wand_sand")            # Uhrturm
    b.spitze(0, -1.0, 15.0, 5.0, 5.0, 5.0, "dach_kupfer", over=0.2)
    b.zyl(0, -1.0, 20.0, 0.12, 0.12, 1.4, 6, "metall")
    b.feld((0, -3.3, 12.6), 2.0, 2.0, "-y", "wand_weiss")     # Uhr
    b.feld((0, -3.3, 12.6), 1.5, 1.5, "-y", "fenster", eps=0.08)
    b.fenster_reihe("-y", -5.0, -5.0, 3.6, 5.6, 2, 1.2, 1.8)
    b.fenster_reihe("-y", -5.0, 5.0, 3.6, 5.6, 2, 1.2, 1.8)
    b.fenster_reihe("-y", -5.0, -5.0, 3.6, 2.2, 2, 1.2, 1.8)
    b.fenster_reihe("-y", -5.0, 5.0, 3.6, 2.2, 2, 1.2, 1.8)
    b.feld((0, -3.3, 1.4), 2.0, 2.8, "-y", "holz_dunkel")
    b.box(0, -4.4, 0, 6.0, 2.2, 0.45, "stein")                # Freitreppe


def speicher(b):
    b.box(0, 0, 0, 10, 13, 11.0, "ziegel")
    b.dach(0, 0, 11.0, 10, 13, 4.4, "dach_schiefer", axis="y", over=0.3)
    b.box(0, -7.4, 13.4, 0.35, 2.6, 0.35, "holz_dunkel")      # Ladebalken
    for z in (2.0, 5.2, 8.4):                                  # Ladeluken uebereinander
        b.feld((0, -6.5, z), 2.0, 2.4, "-y", "holz_dunkel")
        b.fenster_reihe("-y", -6.5, -3.2, 2.6, z + 0.2, 2, 1.0, 1.3)
        b.fenster_reihe("-y", -6.5, 3.2, 2.6, z + 0.2, 2, 1.0, 1.3)
    b.feld((0, -6.5, 12.6), 1.6, 1.8, "-y", "holz_dunkel")


def werkstatt(b):
    b.box(0, 0, 0, 12, 8, 4.4, "beton")
    b.pultdach(0, 0, 4.4, 12, 8, 1.8, "metall_dunkel")
    b.box(-7.4, -1.0, 0, 3.0, 4.5, 3.0, "wand_grau")          # Anbau
    b.pultdach(-7.4, -1.0, 3.0, 3.0, 4.5, 0.8, "metall_dunkel")
    b.zyl(4.6, 2.4, 4.6, 0.4, 0.4, 3.4, 6, "metall_dunkel")   # Abluftrohr
    b.feld((-2.0, -4.0, 1.8), 4.4, 3.6, "-y", "metall")       # Rolltor
    for i in range(5):
        b.feld((-2.0, -4.0, 0.5 + i * 0.75), 4.4, 0.12, "-y", "metall_dunkel", eps=0.06)
    b.fenster_reihe("-y", -4.0, 3.4, 4.4, 3.0, 3, 1.1, 1.4)


def hangar(b):
    prof = [(-11.0, 0.0), (-11.0, 4.6), (-8.2, 7.6), (0.0, 9.0), (8.2, 7.6), (11.0, 4.6), (11.0, 0.0)]
    b.profil(0, 0, 0, prof, 20.0, "metall")
    b.feld((0, -10.0, 3.4), 17.0, 6.8, "-y", "metall_dunkel")     # Schiebetor
    for x in (-5.6, 0.0, 5.6):
        b.feld((x, -10.0, 3.4), 0.25, 6.8, "-y", "metall", eps=0.06)
    b.feld((0, -10.0, 8.0), 6.0, 1.0, "-y", "wand_weiss")         # Beschriftungsband
    for s in (-1, 1):
        b.fenster_reihe("+x" if s > 0 else "-x", s * 11.0, 0, 15.0, 5.6, 5, 1.6, 1.2, "glas")


def tower(b):
    b.box(0, 0, 0, 6.5, 6.5, 11.0, "beton")
    b.box(0, 0, 11.0, 9.0, 9.0, 3.6, "metall_dunkel")             # Kanzel
    for f, fx in (("-y", -4.5), ("+y", 4.5)):
        b.feld((0, fx, 12.9), 8.4, 2.4, f, "glas")
    for f, fx in (("-x", -4.5), ("+x", 4.5)):
        b.feld((fx, 0, 12.9), 8.4, 2.4, f, "glas")
    b.box(0, 0, 14.6, 9.6, 9.6, 0.35, "beton")
    b.zyl(2.8, 2.8, 14.9, 0.12, 0.12, 4.0, 6, "metall")           # Antenne
    b.zyl(-2.8, -2.8, 14.9, 0.5, 0.5, 0.7, 8, "metall_dunkel")    # Radar-Sockel
    b.fenster_reihe("-y", -3.25, 0, 4.0, 3.4, 2, 1.0, 1.3)
    b.fenster_reihe("-y", -3.25, 0, 4.0, 7.0, 2, 1.0, 1.3)
    b.feld((0, -3.25, 1.1), 1.3, 2.2, "-y", "metall_dunkel")


def tanklager(b):
    for x in (-3.4, 3.4):                                          # zwei LIEGENDE Kesseltanks
        b.zyl(x, -5.5, 3.1, 1.9, 1.9, 11.0, 10, "metall", cap_top=True, cap_bottom=True,
              achse="y")
        for y in (-3.6, 1.6):                                      # Sattelboecke
            b.box(x, y, 0, 3.6, 1.1, 1.5, "beton")
        b.box(x, 0, 0, 5.0, 12.0, 0.35, "beton")                   # Auffangwanne
    b.box(0, 6.4, 0, 4.0, 5.0, 3.0, "wand_grau")                   # Pumpenhaus
    b.pultdach(0, 6.4, 3.0, 4.0, 5.0, 0.8, "metall_dunkel")
    b.feld((0, 3.9, 1.1), 1.3, 2.2, "-y", "metall_dunkel")
    b.box(0, 0, 1.0, 7.0, 0.4, 0.4, "metall_dunkel")               # Sammelleitung
    b.zyl(0, 6.4, 3.8, 0.3, 0.3, 3.2, 6, "metall")                 # Entlueftung


def wasserturm(b):
    for a in (0.0, math.pi * 0.5, math.pi, math.pi * 1.5):        # 4 Stuetzen
        b.box(math.cos(a) * 2.6, math.sin(a) * 2.6, 0, 0.55, 0.55, 9.0, "metall_dunkel")
    b.box(0, 0, 4.4, 6.2, 6.2, 0.3, "metall_dunkel")              # Querverband
    b.zyl(0, 0, 9.0, 4.2, 3.8, 5.2, 10, "metall")                 # Behaelter
    b.kegel(0, 0, 14.2, 3.9, 1.8, 10, "metall_dunkel")
    b.zyl(0, 0, 8.4, 4.4, 4.4, 0.35, 10, "metall_dunkel")
    b.feld((0, -4.0, 11.4), 3.0, 1.6, "-y", "wand_weiss", eps=0.1)


def leuchtfeuer_haus(b):     # kleines Hafen-/Lotsenhaus mit Signalmast
    b.box(0, 0, 0, 7.5, 6, 3.6, "wand_weiss")
    b.dach(0, 0, 3.6, 7.5, 6, 2.2, "dach_rot", axis="x", over=0.45)
    b.box(-2.0, 0.8, 5.8, 0.7, 0.7, 1.2, "ziegel")
    b.zyl(3.2, 1.6, 5.8, 0.14, 0.14, 6.0, 6, "metall")            # Signalmast
    for z in (8.2, 9.6):
        b.feld((3.2, 1.6, z), 1.6, 0.3, "-y", "dach_rot", eps=0.16)
    b.fenster_reihe("-y", -3.0, 0, 5.2, 2.2, 3, 1.1, 1.2)
    b.feld((-2.6, -3.0, 1.05), 1.1, 2.1, "-y", "holz_dunkel")


HAEUSER = [
    ("Haus_Bauernhaus", bauernhaus), ("Haus_Fachwerk", fachwerkhaus), ("Haus_Kate", kate),
    ("Haus_Scheune", scheune), ("Haus_Stall", stall), ("Haus_Silo", silo),
    ("Haus_Wassermuehle", wassermuehle), ("Haus_Windmuehle", windmuehle),
    ("Haus_Stadthaus2", stadthaus2), ("Haus_Stadthaus3", stadthaus3),
    ("Haus_Reihenhaus", reihenhaus), ("Haus_Eckhaus", eckhaus),
    ("Haus_Gasthaus", gasthaus), ("Haus_Villa", villa),
    ("Haus_Kirche", kirche), ("Haus_Kapelle", kapelle), ("Haus_Rathaus", rathaus),
    ("Haus_Speicher", speicher), ("Haus_Werkstatt", werkstatt),
    ("Haus_Hangar", hangar), ("Haus_Tower", tower), ("Haus_Tanklager", tanklager),
    ("Haus_Wasserturm", wasserturm), ("Haus_Lotsenhaus", leuchtfeuer_haus),
]

PER_ROW = 6
SPACING = 44.0
ORIGIN_Y = -260.0


def main():
    shutil.copyfile(SRC, OUT)          # "kopiere das blender file"
    bpy.ops.wm.open_mainfile(filepath=OUT)
    scn = bpy.context.scene

    top = bpy.data.collections.get("HAEUSER")
    if top is None:
        top = bpy.data.collections.new("HAEUSER")
        scn.collection.children.link(top)

    labels = bpy.data.collections.get("HAEUSER_Labels")
    if labels is None:
        labels = bpy.data.collections.new("HAEUSER_Labels")
        top.children.link(labels)

    report = []
    for i, (name, fn) in enumerate(HAEUSER):
        col, row = i % PER_ROW, i // PER_ROW
        ort = (col * SPACING, ORIGIN_Y - row * SPACING)
        b = Bau(name)
        fn(b)
        ob = b.build(top, ort)
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        report.append((name, tris, len(ob.data.vertices), len(b.mats)))

        txt = bpy.data.curves.new(name + "_lbl", type='FONT')
        txt.body = name.replace("Haus_", "")
        txt.size = 2.4
        tob = bpy.data.objects.new(name + "_lbl", txt)
        tob.location = (ort[0] - 8.0, ort[1] - 16.0, 0.05)
        labels.objects.link(tob)

    bpy.ops.wm.save_mainfile(filepath=OUT)
    print("SAVED", OUT)
    total = sum(r[1] for r in report)
    print("HAEUSER: %d Stueck, %d Tris gesamt, Schnitt %.0f Tris"
          % (len(report), total, total / max(len(report), 1)))
    for name, tris, verts, nm in sorted(report, key=lambda r: -r[1]):
        print("  %-20s %4d Tris  %4d Verts  %d Materialien" % (name, tris, verts, nm))

    if PREVIEW:
        render_previews(scn)


def render_previews(scn):
    from mathutils import Vector as V
    cam = bpy.data.objects.new("PrevCam", bpy.data.cameras.new("PrevCam"))
    scn.collection.objects.link(cam)
    scn.camera = cam
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'MATERIAL'
    scn.display.shading.show_shadows = True
    scn.render.film_transparent = False
    scn.world = scn.world or bpy.data.worlds.new("W")
    scn.render.resolution_x = 1920
    scn.render.resolution_y = 1000

    def shot(names, path, hoehe=0.45, res=(1920, 780)):
        lo = V((1e9, 1e9, 1e9))
        hi = V((-1e9, -1e9, -1e9))
        for n in names:
            ob = bpy.data.objects.get(n)
            if ob is None:
                continue
            for c in ob.bound_box:
                w = ob.matrix_world @ V(c)
                lo = V(map(min, lo, w))
                hi = V(map(max, hi, w))
        ctr = (lo + hi) * 0.5
        r = max((hi - lo).length * 0.5, 1.0)
        cam.data.lens = 42
        scn.render.resolution_x, scn.render.resolution_y = res
        # Bildfuellend einpassen: Abstand aus Bounding-Sphere + halbem Oeffnungswinkel
        fov = 2.0 * math.atan(0.5 * 36.0 / cam.data.lens)
        dist = r / math.sin(fov * 0.5) * 1.12
        d = V((-0.34, -0.90, hoehe)).normalized()
        cam.location = ctr + d * dist
        cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
        cam.data.clip_end = dist * 4.0
        scn.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", path)

    alle = [n for n, _ in HAEUSER]
    shot(alle, os.path.join(PREVIEW, "haeuser_uebersicht.png"), hoehe=0.85, res=(1800, 1100))
    for r in range(0, (len(alle) + PER_ROW - 1) // PER_ROW):
        shot(alle[r * PER_ROW:(r + 1) * PER_ROW],
             os.path.join(PREVIEW, "haeuser_reihe%d.png" % (r + 1)), hoehe=0.34)
    # Nahaufnahmen der aufwendigsten Modelle (dort faellt ein Geometriefehler auf)
    shot(["Haus_Kirche", "Haus_Rathaus"], os.path.join(PREVIEW, "detail_wahrzeichen.png"),
         hoehe=0.28, res=(1500, 900))
    shot(["Haus_Windmuehle", "Haus_Wassermuehle"], os.path.join(PREVIEW, "detail_muehlen.png"),
         hoehe=0.28, res=(1500, 900))
    shot(["Haus_Hangar", "Haus_Tower"], os.path.join(PREVIEW, "detail_flugplatz.png"),
         hoehe=0.30, res=(1500, 900))
    shot(["Haus_Fachwerk", "Haus_Villa"], os.path.join(PREVIEW, "detail_wohnen.png"),
         hoehe=0.26, res=(1500, 900))


main()
