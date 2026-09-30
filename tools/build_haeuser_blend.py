# blender_lib/haeuser.blend — EIGENSTAENDIGER Gebaeude-Baukasten (42 Typen, 2 Detailstufen)
#
# ZWEI STUFEN AUS EINEM CODE: jedes Haus wird zweimal gebaut — `hd=False` gibt die grobe
# Fernsilhouette (~94 Tris), `hd=True` dieselbe Form mit Nahdetails (Fensterrahmen mit
# Sprossen und Baenken, Traufbretter/Firstziegel/Ziegelreihen, Sockel- und Gesimsbaender,
# doppelte Rundungsaufloesung, Gelaender, Zinnen, Rohre ...). Weil BEIDE aus demselben
# Aufbau kommen, sind die Silhouetten deckungsgleich -> LOD-Umschalten ohne Formsprung.
#
# Baut die Datei KOMPLETT NEU aus einer LEEREN Szene: nur die hier generierten Haeuser,
# keine importierten Landmarks mehr (Wunsch: "clear die restlichen gebaeude").
# `blender_lib/gebaeude.blend` wird dadurch nicht einmal mehr GELESEN und kann somit
# unmoeglich veraendert werden (frueher: shutil.copyfile als Quelle).
# Stil wie im Spiel: Low-Poly, flat shaded, gedeckte Palette wie Landmarks.gd.
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
from mathutils import Vector

# Relativ zum Skript: das Projekt liegt je nach Geraet woanders (hier stand ein Windows-
# Pfad, auf dem Mac schrieb das Skript damit ins Leere).
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + "/"
OUT = ROOT + "blender_lib/haeuser.blend"
GLB = ROOT + "models/world_buildings.glb"
GLB_HD = ROOT + "models/world_buildings_hd.glb"
HD_VERSATZ = 46.0   # HD-Reihe leicht versetzt neben der LOD-Reihe
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
    # Fensterlaeden, Tueren, Blumenkaesten (Dorfhaeuser)
    "holz_gruen":   (0.30, 0.45, 0.32),
    "holz_blau":    (0.32, 0.43, 0.56),
    "blumen":       (0.80, 0.30, 0.32),
    "wand_gruen":   (0.72, 0.78, 0.66),
}


def srgb2lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def get_mat(key):
    """key + "_d" = derselbe Ton dunkler (Ziegelreihen, Firstziegel)."""
    name = "H_" + key
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    if key.endswith("_d"):
        rgb = tuple(c * 0.78 for c in PAL[key[:-2]])
    else:
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


def _lokbox(cx, cy, z, sx, sy, h):
    """Box in LOKALEN Dachkoordinaten -> (verts, faces); z = Unterkante."""
    x0, x1 = cx - sx * 0.5, cx + sx * 0.5
    y0, y1 = cy - sy * 0.5, cy + sy * 0.5
    z0, z1 = z, z + h
    V = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
         (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    F = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return V, F


# --- Geometrie-Baukasten -------------------------------------------------------------------
class Bau:
    """Sammelt Verts/Faces je Material und wird am Ende EIN Mesh-Objekt."""

    # Achsen je Wandseite: (horizontale Richtung in der Wandebene, Normale)
    AX = {"+x": ((0, 1, 0), (1, 0, 0)), "-x": ((0, 1, 0), (-1, 0, 0)),
          "+y": ((1, 0, 0), (0, 1, 0)), "-y": ((1, 0, 0), (0, -1, 0))}

    def __init__(self, name, hd=False, tausch=None):
        self.name = name
        self.hd = hd         # True = Nahansicht mit Details
        self.v = []
        self.f = []          # (indices, material_index)
        self.mats = []
        # FARBVARIANTE: jeder Materialschluessel wird beim Einsetzen hierueber getauscht
        # (siehe VARIANTEN) — dieselbe Form in anderen Farben, ohne die Hausfunktion anzufassen.
        self.tausch = tausch or {}
        # Wandfarbe des zuletzt gesetzten BAUKOERPERS: daraus werden die Giebel gemalt.
        self.wand_key = None

    def rund(self, n):
        """Rundungsaufloesung: in HD doppelt so fein."""
        return n * 2 if self.hd else n

    def _mi(self, key):
        dunkel = key.endswith("_d")
        basis = key[:-2] if dunkel else key
        key = self.tausch.get(basis, basis) + ("_d" if dunkel else "")
        if key not in self.mats:
            self.mats.append(key)
        return self.mats.index(key)

    def add(self, verts, faces, key):
        base = len(self.v)
        mi = self._mi(key)
        self.v.extend(tuple(p) for p in verts)
        for fc in faces:
            self.f.append(([base + i for i in fc], mi))

    # Wandkoerper mit HD-Zutaten: Sockelband unten, Gesims oben, Eckquader.
    def wand(self, x, y, z, sx, sy, h, key, sockel=None, gesims=None, skip=("bottom",)):
        self.box(x, y, z, sx, sy, h, key, skip=skip)
        if not self.hd:
            return
        if sockel is not None:
            self.box(x, y, z, sx + 0.34, sy + 0.34, 0.55, sockel)
        if gesims is not None:
            self.box(x, y, z + h - 0.34, sx + 0.40, sy + 0.40, 0.34, gesims)

    # Quader; z = UNTERKANTE. skip: 'bottom','top','-y','+y','-x','+x'
    def box(self, x, y, z, sx, sy, h, key, skip=("bottom",)):
        if h >= 2.2 and sx * sy >= 12.0 and not key.startswith(("dach", "metall", "glas")):
            self.wand_key = key
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

    # --- geschlossene Koerper: Wicklung ueber das Volumen, nicht von Hand ------------------
    def add_koerper(self, verts, faces, key):
        """Geschlossener Koerper (Dachplatte, Gaube ...). Die Flaechen werden ueber ein bmesh
        nach AUSSEN gelegt (recalc + Vorzeichen des Volumens) — von Hand gewickelte Schraegen
        sind genau die Stelle, an der man sich vertut."""
        import bmesh
        tb = bmesh.new()
        vs = [tb.verts.new(p) for p in verts]
        for fc in faces:
            tb.faces.new([vs[i] for i in fc])
        bmesh.ops.recalc_face_normals(tb, faces=tb.faces[:])
        vol = 0.0
        for f in tb.faces:
            ps = [v.co for v in f.verts]
            for k in range(1, len(ps) - 1):
                vol += ps[0].dot(ps[k].cross(ps[k + 1]))
        if vol < 0.0:
            bmesh.ops.reverse_faces(tb, faces=tb.faces[:])
        tb.verts.index_update()
        self.add([tuple(v.co) for v in tb.verts], [[v.index for v in f.verts] for f in tb.faces],
                 key)
        tb.free()

    @staticmethod
    def _nach(pts, n):
        """Ein ebenes Vieleck so wickeln, dass seine Normale nach n zeigt."""
        a, b, c = Vector(pts[0]), Vector(pts[1]), Vector(pts[2])
        if (b - a).cross(c - a).dot(Vector(n)) < 0.0:
            return list(reversed(pts))
        return list(pts)

    @staticmethod
    def _welt(info, p):
        """Dach-lokal (x quer zum First, y laengs, z ab Wandkrone) -> Welt."""
        lx, ly, lz = p
        if info["axis"] == "x":
            return (info["x"] + ly, info["y"] - lx, info["z"] + lz)
        return (info["x"] + lx, info["y"] + ly, info["z"] + lz)

    @staticmethod
    def _seite_facing(info, seite):
        """Wandrichtung ("-y" ...) der Dachseite lokal +x (seite=1) bzw. -x (seite=-1)."""
        if info["axis"] == "x":
            return "-y" if seite > 0 else "+y"
        return "+x" if seite > 0 else "-x"

    # Satteldach bzw. WALMDACH (inset > 0) auf einem Baukoerper w (X) x d (Y); axis = Richtung
    # des FIRSTS. over = Dachueberstand rundum, dicke = sichtbare Plattenstaerke.
    #
    # ZWEITE FASSUNG (2026-09). Die erste vertauschte bei axis="x" Laenge und Spannweite: das
    # Dach eines 11 x 8 m Hauses war 8.8 lang und 11.8 breit, lag also quer — vorn hing es
    # weit ueber, seitlich standen die Wandecken frei heraus (13 Daecher, praktisch jedes
    # Dorfhaus). Dazu stand der Giebel in DACHFARBE aussen am Ueberstand statt in Wandfarbe
    # buendig mit der Wand, und die Dachflaeche war hauchduenn.
    # Jetzt: die Dachflaeche laeuft durch die Wandkrone und endet UNTER ihr an der Traufe,
    # die Platte ist ein geschlossener Koerper mit sichtbarer Kante (Traufe, Ortgang), der
    # Giebel ist ein Dreieck in Wandfarbe in der Wandebene. HD: Firstziegel + Ziegelreihen.
    # Rueckgabe: Dachmasse fuer gaube()/kamin().
    def dach(self, x, y, z, w, d, h, key, axis="x", inset=0.0, over=0.45, giebel=None,
             dicke=None, details=True):
        S, L = (d, w) if axis == "x" else (w, d)
        hs, hl = S * 0.5, L * 0.5
        o = over
        t = dicke if dicke is not None else (0.30 if self.hd else 0.24)
        ze = -h * o / hs                      # Traufe liegt unter der Wandkrone
        xe = hs + o
        ins = min(inset, hl - 0.05) if inset > 0.0 else 0.0
        if ins > 0.0:
            ye = hl + o * ins / hs            # Walm: Ueberstand passend zur Walmneigung
            ry = hl - ins
        else:
            ye = hl + o
            ry = ye
        info = dict(x=x, y=y, z=z, axis=axis, hs=hs, hl=hl, h=h, ry=ry, ins=ins, key=key)
        # Die Platte liegt um die halbe Staerke HOEHER als die Linie durch die Wandkrone: die
        # Oberkante der Wand steckt dann mitten in der Platte. Lief die Dachflaeche genau durch
        # die Wandkante, flimmerte dort eine gepunktete Linie (gleiche Tiefe).
        lift = t * 0.5
        E = [(-xe, -ye, ze + lift), (xe, -ye, ze + lift), (xe, ye, ze + lift), (-xe, ye, ze + lift)]
        R = [(0.0, -ry, h + lift), (0.0, ry, h + lift)]
        U = [(p[0], p[1], p[2] - t) for p in E + R]
        V = [self._welt(info, p) for p in E + R + U]
        if ins > 0.0:
            F = [(0, 4, 5, 3), (1, 2, 5, 4), (0, 1, 4), (2, 3, 5),
                 (6, 9, 11, 10), (7, 10, 11, 8), (6, 10, 7), (8, 11, 9),
                 (0, 3, 9, 6), (1, 7, 8, 2), (0, 6, 7, 1), (2, 8, 9, 3)]
        else:
            F = [(0, 4, 5, 3), (1, 2, 5, 4), (6, 9, 11, 10), (7, 10, 11, 8),
                 (0, 3, 9, 6), (1, 7, 8, 2),
                 (0, 6, 10, 4), (4, 10, 7, 1), (3, 5, 11, 9), (5, 2, 8, 11)]
        self.add_koerper(V, F, key)
        if ins == 0.0:
            gk = giebel if giebel is not None else (self.wand_key or "wand_creme")
            for k, s in enumerate((-1, 1)):
                g = gk[k] if isinstance(gk, (tuple, list)) else gk
                pts = [self._welt(info, (-hs, s * hl, 0.0)), self._welt(info, (hs, s * hl, 0.0)),
                       self._welt(info, (0.0, s * hl, h - t + lift))]
                n = Vector(self._welt(info, (0.0, s, 0.0))) - Vector(self._welt(info, (0, 0, 0)))
                self.add(self._nach(pts, n), [(0, 1, 2)], g)
        if self.hd and details:
            # Firstziegel
            hf = h + lift
            fl = [(-0.24, -ry - 0.02, hf - 0.14), (0.24, -ry - 0.02, hf - 0.14),
                  (0.24, ry + 0.02, hf - 0.14), (-0.24, ry + 0.02, hf - 0.14),
                  (-0.24, -ry - 0.02, hf + 0.08), (0.24, -ry - 0.02, hf + 0.08),
                  (0.24, ry + 0.02, hf + 0.08), (-0.24, ry + 0.02, hf + 0.08)]
            self.add_koerper([self._welt(info, p) for p in fl],
                             [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5),
                              (2, 3, 7, 6), (3, 0, 4, 7)], key + "_d")
            # Ziegelreihen: dunklere Streifen in der Dachflaeche (aus der Naehe liest sich das
            # als Deckung, kostet je Streifen zwei Dreiecke)
            for sx in (-1, 1):
                nl = Vector((sx * (h - ze), 0.0, xe)).normalized()
                hang = Vector((-sx * xe, 0.0, h - ze)).normalized()
                for fr in (0.22, 0.47, 0.72):
                    c = Vector((sx * xe * (1.0 - fr), 0.0, ze + (h - ze) * fr + lift)) + nl * 0.03
                    ext = (ry + (ye - ry) * (1.0 - fr)) - 0.1
                    pts = [c - hang * 0.11 - Vector((0, ext, 0)), c - hang * 0.11 + Vector((0, ext, 0)),
                           c + hang * 0.11 + Vector((0, ext, 0)), c + hang * 0.11 - Vector((0, ext, 0))]
                    pw = [self._welt(info, tuple(q)) for q in pts]
                    nw = Vector(self._welt(info, tuple(nl))) - Vector(self._welt(info, (0, 0, 0)))
                    self.add(self._nach(pw, nw), [(0, 1, 2, 3)], key + "_d")
        return info

    # Giebelgaube auf der Dachseite `seite` (+1 = lokal +x) an der Firstposition u. Die Front
    # steht `rueck` hinter der Wandlinie auf der Dachflaeche, der Koerper laeuft nach hinten
    # in das Dach hinein (dort verdeckt); darauf ein kleines Satteldach quer zum First.
    def gaube(self, info, u, seite=1, breite=2.2, hoehe=1.5, rueck=0.75, wand=None,
              fenster_b=1.0, fenster_h=0.9, laeden=None):
        hs, h = info["hs"], info["h"]
        zb = h * rueck / hs
        zt = min(zb + hoehe, h - 0.7)
        lxf = hs - rueck
        lxb = max(hs * (1.0 - (zt + 0.4) / h), 0.1)
        wk = wand or self.wand_key or "wand_creme"
        V = []
        for lx in (lxb, lxf):
            for ly in (u - breite * 0.5, u + breite * 0.5):
                for lz in (zb - 0.6, zt):
                    V.append(self._welt(info, (seite * lx, ly, lz)))
        # Ecken: Index = ix*4 + iy*2 + iz
        F = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (1, 3, 7, 5), (0, 4, 6, 2)]
        self.add_koerper(V, F, wk)
        mitte = self._welt(info, (seite * (lxf + lxb) * 0.5, u, zt))
        tiefe = lxf - lxb + 0.1
        gh = breite * 0.42
        if info["axis"] == "x":
            self.dach(mitte[0], mitte[1], mitte[2], breite, tiefe, gh, info["key"], axis="y",
                      over=0.18, dicke=0.16, giebel=wk, details=False)
        else:
            self.dach(mitte[0], mitte[1], mitte[2], tiefe, breite, gh, info["key"], axis="x",
                      over=0.18, dicke=0.16, giebel=wk, details=False)
        fh = min(fenster_h, zt - zb - 0.4)
        ctr = self._welt(info, (seite * lxf, u, zb + 0.25 + fh * 0.5))
        self.fenster(ctr, fenster_b, fh, self._seite_facing(info, seite), laeden=laeden,
                     bank=False)

    # Schornstein, steht auf der Dachflaeche bei (lx quer, u laengs), ueberragt den First.
    def kamin(self, info, u, lx, key="ziegel", ueber=0.9, breite=0.8):
        zr = info["h"] * (1.0 - abs(lx) / info["hs"])
        c = self._welt(info, (lx, u, 0.0))
        z0 = info["z"] + zr - 0.7
        z1 = info["z"] + info["h"] + ueber
        self.box(c[0], c[1], z0, breite, breite, z1 - z0, key)
        if self.hd:
            self.box(c[0], c[1], z1, breite + 0.22, breite + 0.22, 0.14, "beton")
            self.box(c[0], c[1], z1 + 0.14, breite * 0.5, breite * 0.5, 0.16, key)

    # Tuer mit Vordach (Vordach in beiden Stufen: aus der Luft ist es der Schatten ueber der
    # Tuer, der den Eingang lesbar macht). HD: Zarge + Schwelle.
    def tuer(self, ctr, w, h, facing, key="holz_dunkel", vordach=None, rahmen="wand_weiss"):
        self.feld(ctr, w, h, facing, key)
        u, n = Bau.AX[facing]
        if vordach is not None:
            tief = 0.9
            zc = ctr[2] + h * 0.5 + 0.25
            cx = ctr[0] + n[0] * tief * 0.5
            cy = ctr[1] + n[1] * tief * 0.5
            if facing in ("+y", "-y"):
                self.box(cx, cy, zc, w + 0.9, tief, 0.16, vordach)
            else:
                self.box(cx, cy, zc, tief, w + 0.9, 0.16, vordach)
        if self.hd:
            t = 0.14
            self.feld((ctr[0], ctr[1], ctr[2] + h * 0.5 + t * 0.5), w + 2 * t, t, facing, rahmen,
                      eps=0.07)
            for du in (-0.5, 0.5):
                c = tuple(ctr[i] + u[i] * du * (w + t) for i in range(3))
                self.feld(c, t, h, facing, rahmen, eps=0.07)
            zb = ctr[2] - h * 0.5
            if facing in ("+y", "-y"):
                self.box(ctr[0], ctr[1] + n[1] * 0.25, zb - 0.02, w + 0.5, 0.5, 0.16, "stein")
            else:
                self.box(ctr[0] + n[0] * 0.25, ctr[1], zb - 0.02, 0.5, w + 0.5, 0.16, "stein")

    # Sockel (nur HD): Band um den Baukoerper
    def sockel(self, x, y, sx, sy, key="stein", h=0.55):
        if self.hd:
            self.box(x, y, 0, sx + 0.16, sy + 0.16, h, key)

    # Pyramidendach / Turmspitze
    def spitze(self, x, y, z, w, d, h, key, over=0.0):
        w += over * 2.0
        d += over * 2.0
        hw, hd = w * 0.5, d * 0.5
        V = [(x - hw, y - hd, z), (x + hw, y - hd, z), (x + hw, y + hd, z), (x - hw, y + hd, z),
             (x, y, z + h)]
        self.add(V, [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], key)

    # Pultdach (eine geneigte Platte), steigt in +y. Die Wand UNTER der Schraege wird in
    # Wandfarbe geschlossen (zwei Seitentrapeze, Rueckwand, Streifen vorn) — vorher klaffte
    # zwischen Wandkrone und Dachplatte ein Keil, durch den man ins Haus sah.
    def pultdach(self, x, y, z, w, d, h, key, over=0.3, wand=None):
        wo, do_ = w + over * 2.0, d + over * 2.0
        hw, hd = wo * 0.5, do_ * 0.5
        t = 0.25   # Dachstaerke
        V = [(x - hw, y - hd, z), (x + hw, y - hd, z), (x + hw, y + hd, z + h), (x - hw, y + hd, z + h),
             (x - hw, y - hd, z + t), (x + hw, y - hd, z + t), (x + hw, y + hd, z + h + t), (x - hw, y + hd, z + h + t)]
        self.add_koerper(V, [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6),
                             (3, 0, 4, 7)], key)
        wk = wand or self.wand_key
        if wk is None:
            return

        def zr(yy):
            return z + h * (yy - (y - hd)) / (2.0 * hd)
        x0, x1, y0, y1 = x - w * 0.5, x + w * 0.5, y - d * 0.5, y + d * 0.5
        for xs, n in ((x0, (-1, 0, 0)), (x1, (1, 0, 0))):
            pts = [(xs, y0, z), (xs, y1, z), (xs, y1, zr(y1)), (xs, y0, zr(y0))]
            self.add(self._nach(pts, n), [(0, 1, 2, 3)], wk)
        for ys, n in ((y1, (0, 1, 0)), (y0, (0, -1, 0))):
            pts = [(x0, ys, z), (x1, ys, z), (x1, ys, zr(ys)), (x0, ys, zr(ys))]
            self.add(self._nach(pts, n), [(0, 1, 2, 3)], wk)

    # n-seitiger Zylinder/Kegelstumpf; z = Unterkante.
    # achse="y" kippt ihn auf die Y-Achse (liegender Tank) — die Abbildung
    # (x,y,z)->(x,z,-y) ist eine ECHTE Drehung (det=+1), Wicklung bleibt gueltig.
    def zyl(self, x, y, z, r0, r1, h, sides, key, cap_top=True, cap_bottom=False, achse="z"):
        sides = self.rund(sides)
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
        sides = self.rund(sides)
        V = []
        for i in range(sides):
            a = 2.0 * math.pi * i / sides
            V.append((x + math.cos(a) * r, y + math.sin(a) * r, z))
        V.append((x, y, z + h))
        self.add(V, [(i, (i + 1) % sides, sides) for i in range(sides)], key)

    # Flaches Rechteck AUF einer Wand (Fenster/Tuer/Balken) — 2 Tris statt einer Box.
    def feld(self, ctr, w, h, facing, key, eps=0.04, winkel=0.0, zweiseitig=False):
        """zweiseitig: frei stehende Flaechen (Muehlenfluegel, Fahnen, Gelaenderfelder) —
        einseitig verschwanden sie von hinten (Godot zeichnet Rueckseiten nicht)."""
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
        if zweiseitig:
            self.add(pts[::-1], [(0, 1, 2, 3)], key)

    # Einzelfenster: LOD = ein Quad, HD = Glas + Rahmenleisten + Sprossenkreuz + Fensterbank.
    def fenster(self, ctr, w, h, facing, key="fenster", rahmen="wand_weiss", bank=True,
                laeden=None, kasten=False):
        """laeden = Holzfarbe der Fensterlaeden (beide Stufen: sie tragen die Farbe eines
        Dorfhauses bis in die Ferne), kasten = Blumenkasten unter dem Fenster (HD)."""
        u, n = Bau.AX[facing]
        if laeden is not None:
            for du in (-1.0, 1.0):
                c = tuple(ctr[i] + u[i] * du * (w * 0.5 + w * 0.28) for i in range(3))
                self.feld(c, w * 0.5, h, facing, laeden, eps=0.05 if self.hd else 0.04)
        if kasten and self.hd:
            bz = ctr[2] - h * 0.5 - 0.42
            if facing in ("+y", "-y"):
                self.box(ctr[0], ctr[1] + n[1] * 0.2, bz, w + 0.1, 0.34, 0.3, "holz_dunkel")
                self.box(ctr[0], ctr[1] + n[1] * 0.2, bz + 0.3, w - 0.05, 0.28, 0.2, "blumen")
            else:
                self.box(ctr[0] + n[0] * 0.2, ctr[1], bz, 0.34, w + 0.1, 0.3, "holz_dunkel")
                self.box(ctr[0] + n[0] * 0.2, ctr[1], bz + 0.3, 0.28, w - 0.05, 0.2, "blumen")
        if not self.hd:
            self.feld(ctr, w, h, facing, key)
            return
        t = 0.15
        self.feld(ctr, w - 2.0 * t, h - 2.0 * t, facing, key, eps=0.015)
        for dz in (0.5, -0.5):                              # Sturz + Bruestung
            c = (ctr[0], ctr[1], ctr[2] + dz * (h - t))
            self.feld(c, w, t, facing, rahmen, eps=0.07)
        for du in (0.5, -0.5):                              # Laibungen
            c = tuple(ctr[i] + u[i] * du * (w - t) for i in range(3))
            self.feld(c, t, h, facing, rahmen, eps=0.07)
        self.feld(ctr, 0.07, h - 2.0 * t, facing, rahmen, eps=0.05)   # Sprossenkreuz
        self.feld(ctr, w - 2.0 * t, 0.07, facing, rahmen, eps=0.05)
        if bank:
            bz = ctr[2] - h * 0.5 - 0.05
            if facing in ("+y", "-y"):
                self.box(ctr[0], ctr[1] + n[1] * 0.09, bz, w + 0.3, 0.28, 0.1, rahmen)
            else:
                self.box(ctr[0] + n[0] * 0.09, ctr[1], bz, 0.28, w + 0.3, 0.1, rahmen)

    def fenster_reihe(self, facing, fixed, u_ctr, u_span, z, n, w, h, key="fenster", **kw):
        for i in range(n):
            t = (i + 0.5) / n - 0.5
            u = u_ctr + t * u_span
            ctr = (u, fixed, z) if facing in ("+y", "-y") else (fixed, u, z)
            self.fenster(ctr, w, h, facing, key, **kw)

    # Gelaender (Balkon/Galerie/Terrasse): Handlauf + Pfosten, nur in HD.
    def gelaender(self, x, y, z, sx, sy, key, hoehe=1.0, n=6):
        if not self.hd:
            return
        self.box(x, y, z + hoehe - 0.09, sx, sy, 0.09, key)          # Handlauf
        for i in range(n):
            t = (i + 0.5) / n - 0.5
            if sx >= sy:
                self.box(x + t * sx, y, z, 0.09, sy * 0.8, hoehe, key)
            else:
                self.box(x, y + t * sy, z, sx * 0.8, 0.09, hoehe, key)

    # Zinnenkranz auf einer Mauerkrone (Burg) — nur HD.
    def zinnen(self, x, y, z, sx, sy, key, n=6, hoehe=1.1):
        if not self.hd:
            return
        for i in range(n):
            t = (i + 0.5) / n - 0.5
            if sx >= sy:
                self.box(x + t * sx, y, z, sx / (n * 2.1), sy, hoehe, key)
            else:
                self.box(x, y + t * sy, z, sx, sy / (n * 2.1), hoehe, key)

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
    """Anderthalbgeschossiges Bauernhaus, Traufe zur Strasse: zwei Gauben, Fensterlaeden,
    Vordach ueber der Tuer, Giebelfenster an beiden Enden."""
    L = "holz_gruen"
    b.box(0, 0, 0, 11, 8, 4.4, "wand_creme")
    b.sockel(0, 0, 11, 8)
    d = b.dach(0, 0, 4.4, 11, 8, 4.4, "dach_terra", axis="x", over=0.55)
    for u in (-2.4, 2.6):
        b.gaube(d, u, seite=1, laeden=L)
    b.kamin(d, 3.4, -1.0)
    b.tuer((-1.9, -4.0, 1.1), 1.2, 2.2, "-y", vordach="dach_terra")
    for x in (-4.2, 0.6, 3.6):
        b.fenster((x, -4.0, 2.2), 1.2, 1.35, "-y", laeden=L, kasten=True)
    for x in (-3.6, 0.0, 3.6):
        b.fenster((x, 4.0, 2.2), 1.2, 1.35, "+y", laeden=L)
    for f, fx in (("-x", -5.5), ("+x", 5.5)):
        b.fenster_reihe(f, fx, 0, 4.4, 2.2, 2, 1.1, 1.3, laeden=L)
        b.fenster((fx, 0, 6.1), 1.0, 1.1, f)                   # Giebelfenster


def fachwerkhaus(b):
    """Fachwerkhaus, GIEBEL zur Strasse, das Obergeschoss kragt vor. Das Fachwerk (Rahmen,
    Staender, Streben, Kehlbalken im Giebel) steht in beiden Stufen — es ist das Merkmal."""
    H = "holz_dunkel"
    b.box(0, 0, 0, 8, 7.4, 3.3, "wand_weiss")
    b.sockel(0, 0, 8, 7.4)
    b.box(0, -0.25, 3.3, 8.6, 7.9, 3.2, "wand_weiss")               # Obergeschoss
    d = b.dach(0, -0.25, 6.5, 8.6, 7.9, 5.4, "dach_terra", axis="y", over=0.45)
    b.kamin(d, 1.6, 1.3)
    yf = -4.2                                                         # Front OG + Giebel
    for z in (3.42, 6.38):                                            # Schwelle, Rahm
        b.feld((0, yf, z), 8.6, 0.24, "-y", H)
    for x in (-4.18, -2.1, 0.0, 2.1, 4.18):                           # Staender
        b.feld((x, yf, 4.9), 0.24, 3.0, "-y", H)
    for x, sg in ((-3.14, 1), (3.14, -1)):                            # Streben
        b.feld((x, yf, 4.9), 0.22, 3.3, "-y", H, winkel=sg * 0.56)
    b.feld((0, yf, 8.6), 5.0, 0.24, "-y", H)                          # Kehlbalken
    b.feld((0, yf, 8.85), 0.24, 4.5, "-y", H)                         # Giebelstiel
    for x, sg in ((-1.45, 1), (1.45, -1)):
        b.feld((x, yf, 7.55), 0.22, 1.9, "-y", H, winkel=sg * 0.72)
    for f, fx in (("-x", -4.3), ("+x", 4.3)):                         # Fachwerk seitlich
        for z in (3.42, 6.38):
            b.feld((fx, -0.25, z), 7.9, 0.24, f, H)
        for yy in (-3.8, -1.3, 1.3, 3.55):
            b.feld((fx, yy, 4.9), 0.24, 3.0, f, H)
        b.fenster_reihe(f, fx, -0.25, 5.2, 4.9, 2, 0.9, 1.2)
        b.fenster((fx * 0.93, 0.0, 1.8), 1.0, 1.2, f)
    for x in (-1.05, 1.05):
        b.fenster((x, yf, 4.9), 1.0, 1.3, "-y", kasten=True)
    for x in (-0.72, 0.72):
        b.fenster((x, yf, 9.6), 0.55, 0.8, "-y")
    b.tuer((-2.4, -3.7, 1.1), 1.1, 2.2, "-y", key="holz_hell")
    for x in (0.6, 2.7):
        b.fenster((x, -3.7, 1.8), 1.0, 1.2, "-y", kasten=True)
    b.fenster_reihe("+y", 3.7, 0, 5.0, 1.8, 2, 1.0, 1.2)
    b.fenster_reihe("+y", 3.7, 0, 5.0, 4.9, 2, 1.0, 1.2)


def kate(b):
    """Reetgedeckte Kate: niedrige Waende, dickes Walmdach weit heruntergezogen."""
    L = "holz_blau"
    b.box(0, 0, 0, 6.6, 5.4, 2.8, "wand_sand")
    b.sockel(0, 0, 6.6, 5.4, h=0.45)
    d = b.dach(0, 0, 2.8, 6.6, 5.4, 3.8, "dach_stroh", axis="x", inset=1.6, over=0.6,
               dicke=0.55)
    b.kamin(d, 1.1, -0.4, key="stein", ueber=0.6)
    b.tuer((1.5, -2.7, 1.0), 1.0, 2.0, "-y", key="holz_blau")
    b.fenster((-1.4, -2.7, 1.55), 0.9, 0.9, "-y", laeden=L, kasten=True)
    b.fenster((-1.3, 2.7, 1.55), 0.9, 0.9, "+y", laeden=L)
    b.fenster((1.3, 2.7, 1.55), 0.9, 0.9, "+y", laeden=L)
    for f, fx in (("-x", -3.3), ("+x", 3.3)):
        b.fenster((fx, 0, 1.55), 0.9, 0.9, f, laeden=L)


def scheune(b):
    """Scheune: rote Bretterwaende, grosses Tor mit weissem Rahmen und Streben, Heuluken in den
    Giebeln, Lueftungsreiter auf dem First."""
    b.box(0, 0, 0, 14, 9, 5.2, "holz_rot")
    b.sockel(0, 0, 14, 9, h=0.5)
    d = b.dach(0, 0, 5.2, 14, 9, 5.0, "dach_schiefer", axis="x", over=0.5)
    b.box(0, 0, 5.2 + 5.0 - 0.4, 1.6, 1.6, 1.4, "holz_rot")          # Dachreiter
    b.spitze(0, 0, 5.2 + 5.0 + 1.0, 2.2, 2.2, 1.1, "dach_schiefer")
    b.feld((0, -4.5, 2.2), 5.0, 4.4, "-y", "wand_weiss", eps=0.03)    # Tor
    for x in (-1.2, 1.2):
        b.feld((x, -4.5, 2.1), 2.2, 4.0, "-y", "holz_dunkel", eps=0.05)
        b.feld((x, -4.5, 2.1), 0.22, 4.4, "-y", "wand_weiss", eps=0.07,
               winkel=0.5 if x < 0 else -0.5)
    for f, fx in (("-x", -7.0), ("+x", 7.0)):                          # Heuluken
        b.feld((fx, 0, 6.9), 1.9, 2.1, f, "wand_weiss", eps=0.03)
        b.feld((fx, 0, 6.9), 1.6, 1.8, f, "holz_dunkel", eps=0.05)
        b.fenster((fx, -2.6, 2.9), 1.0, 1.0, f)
    for x in (-5.0, 5.0):
        b.fenster((x, -4.5, 3.4), 1.1, 1.1, "-y")
    b.fenster_reihe("+y", 4.5, 0, 9.0, 3.4, 3, 1.1, 1.1)
    if b.hd:                                                            # Bretterfugen
        for i in range(15):
            x = -6.5 + i * (13.0 / 14.0)
            for fy, f in ((-4.5, "-y"), (4.5, "+y")):
                b.feld((x, fy, 2.6), 0.07, 5.0, f, "holz_rot_d", eps=0.022)


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
    b.sockel(0, 0, 9, 7.5)
    d = b.dach(0, 0, 6.8, 9, 7.5, 3.8, "dach_schiefer", axis="x", over=0.5)
    b.kamin(d, -2.2, -1.0)
    b.box(-5.6, 0, 0, 2.4, 2.0, 1.4, "stein")               # Wasserlauf/Gerinne
    b.rad(-5.9, 0, 3.0, 2.8, 1.5, 10, "holz_dunkel")
    b.fenster_reihe("-y", -3.75, 0, 6.0, 4.8, 2, 1.1, 1.3, laeden="holz_dunkel")
    b.fenster_reihe("-y", -3.75, 0, 6.0, 2.0, 2, 1.1, 1.3, laeden="holz_dunkel")
    b.tuer((2.6, -3.75, 1.05), 1.2, 2.1, "-y", vordach="dach_schiefer")
    b.fenster((4.5, 0, 8.2), 0.9, 1.0, "+x")


def windmuehle(b):
    b.zyl(0, 0, 0, 4.0, 2.7, 11.0, 10, "wand_weiss", cap_top=False)
    b.kegel(0, 0, 11.0, 2.9, 2.6, 10, "dach_schiefer")
    b.zyl(0, 0, 5.4, 4.2, 4.2, 0.25, 10, "holz_dunkel")     # Umlaufgalerie
    b.box(0, -3.1, 10.4, 1.0, 1.6, 1.0, "holz_dunkel")      # Wellenkopf
    # ZWEI gekreuzte Fluegelbahnen = 4 Arme. (Vier Panels waeren zwei Duplikate:
    # ein um 180 Grad gedrehtes Rechteck ist mit sich selbst deckungsgleich -> Z-Fighting.)
    # ZWEISEITIG: von hinten verschwanden die Fluegel sonst.
    for k in range(2):
        a = k * math.pi * 0.5 + 0.35
        b.feld((0, -3.9, 10.9), 1.6, 14.0, "-y", "holz_hell", eps=0.0, winkel=a, zweiseitig=True)
        b.feld((0, -4.05, 10.9), 0.4, 14.4, "-y", "holz_dunkel", eps=0.0, winkel=a,
               zweiseitig=True)
    b.feld((0, -4.0, 2.0), 1.3, 2.4, "-y", "holz_dunkel", eps=0.1)


def stadthaus2(b):
    """Buergerhaus, Giebel zur Strasse, zwei Vollgeschosse, Geschossgesims."""
    L = "holz_gruen"
    b.box(0, 0, 0, 9, 8, 7.4, "wand_terra")
    b.sockel(0, 0, 9, 8)
    d = b.dach(0, 0, 7.4, 9, 8, 4.6, "dach_schiefer", axis="y", over=0.35)
    b.kamin(d, 2.2, -1.7)
    b.feld((0, -4.0, 3.75), 9.0, 0.22, "-y", "wand_weiss")            # Geschossgesims
    b.tuer((-2.7, -4.0, 1.15), 1.3, 2.3, "-y", vordach="dach_schiefer")
    for x in (0.2, 2.8):
        b.fenster((x, -4.0, 1.9), 1.2, 1.5, "-y", laeden=L, kasten=True)
    for x in (-2.8, 0.0, 2.8):
        b.fenster((x, -4.0, 5.5), 1.1, 1.5, "-y", laeden=L, kasten=True)
    b.fenster((0, -4.0, 9.0), 1.1, 1.2, "-y")                          # Giebelfenster
    for f, fx in (("-x", -4.5), ("+x", 4.5)):
        b.fenster_reihe(f, fx, 0, 4.0, 5.5, 2, 1.1, 1.5)
        b.fenster_reihe(f, fx, 0, 4.0, 1.9, 2, 1.1, 1.5)
    b.fenster_reihe("+y", 4.0, 0, 6.0, 5.5, 3, 1.1, 1.5)
    b.fenster_reihe("+y", 4.0, 0, 6.0, 1.9, 3, 1.1, 1.5)


def stadthaus3(b):
    """Schmales Giebelhaus mit TREPPENGIEBEL (Hansestil), drei Geschosse."""
    b.box(0, 0, 0, 6.6, 9, 10.6, "wand_ocker")
    b.sockel(0, 0, 6.6, 9)
    d = b.dach(0, 0, 10.6, 6.6, 9, 4.4, "dach_terra", axis="y", over=0.12)
    b.kamin(d, 2.8, 1.2)
    z = 10.6
    for k, (bw, bh) in enumerate(((7.0, 1.1), (5.4, 1.1), (3.8, 1.1), (2.2, 1.2))):
        b.box(0, -4.45, z, bw, 0.6, bh, "wand_ocker", skip=() if k == 0 else ("bottom",))
        z += bh
    for zz in (2.0, 5.3, 8.6):
        b.fenster_reihe("-y", -4.5, 0, 3.0, zz, 2, 1.0, 1.5, kasten=zz > 3.0)
        b.fenster_reihe("+y", 4.5, 0, 3.0, zz, 2, 1.0, 1.5)
    for zz in (3.6, 6.9):
        b.feld((0, -4.5, zz), 6.6, 0.2, "-y", "wand_weiss")            # Gesimsbaender
    for x in (-1.3, 1.3):
        b.fenster((x, -4.75, 11.2), 0.6, 0.7, "-y")                   # Speicherluken
    b.fenster((0, -4.75, 12.5), 0.6, 0.7, "-y")
    b.feld((0, -4.5, 1.2), 1.4, 2.4, "-y", "holz_dunkel")
    for f, fx in (("-x", -3.3), ("+x", 3.3)):
        b.fenster_reihe(f, fx, 0, 5.0, 8.6, 2, 0.9, 1.3)


def reihenhaus(b):
    """Drei Reihenhaeuser unter einem Dach — je eigene Farbe, Tuer, Gaube, Kamin."""
    farben = ("wand_creme", "wand_mauve", "wand_blau")
    tueren = ("holz_rot", "holz_gruen", "holz_blau")
    for i, c in enumerate(farben):
        b.box((i - 1) * 5.6, 0, 0, 5.6, 8, 7.2, c, skip=("bottom", "top"))
    b.sockel(0, 0, 16.8, 8)
    d = b.dach(0, 0, 7.2, 16.8, 8, 4.0, "dach_schiefer", axis="x", over=0.4,
               giebel=(farben[0], farben[2]))
    for i, c in enumerate(farben):
        x = (i - 1) * 5.6
        b.gaube(d, x + 0.9, seite=1, breite=2.0, wand=c)
        b.kamin(d, x - 1.9, -1.1)
        b.fenster_reihe("-y", -4.0, x, 3.4, 5.3, 2, 1.0, 1.4, kasten=True)
        b.fenster((x + 1.3, -4.0, 1.9), 1.1, 1.4, "-y", kasten=True)
        b.tuer((x - 1.4, -4.0, 1.1), 1.1, 2.2, "-y", key=tueren[i], vordach="dach_schiefer")
        b.fenster_reihe("+y", 4.0, x, 3.4, 5.3, 2, 1.0, 1.4)
        b.fenster_reihe("+y", 4.0, x, 3.4, 1.9, 2, 1.0, 1.4)


def eckhaus(b):
    L = "holz_dunkel"
    b.box(-2.0, 0, 0, 9, 8, 7.4, "wand_sand")
    b.box(4.0, 3.0, 0, 7, 6, 7.4, "wand_sand")
    b.sockel(-2.0, 0, 9, 8)
    b.sockel(4.0, 3.0, 7, 6)
    d = b.dach(-2.0, 0, 7.4, 9, 8, 3.2, "dach_terra", axis="x", inset=1.6, over=0.45)
    b.dach(4.0, 3.0, 7.4, 7, 6, 2.8, "dach_terra", axis="y", inset=1.4, over=0.45)
    b.kamin(d, -3.6, -1.2)
    b.fenster_reihe("-y", -4.0, -2.0, 6.2, 5.4, 3, 1.1, 1.4, laeden=L, kasten=True)
    b.fenster_reihe("-y", -4.0, -3.4, 3.6, 2.2, 2, 1.1, 1.4, laeden=L)
    b.tuer((0.8, -4.0, 1.1), 1.3, 2.2, "-y", vordach="dach_terra")
    b.fenster_reihe("-x", -6.5, 0, 5.4, 5.4, 2, 1.1, 1.4, laeden=L)
    b.fenster_reihe("-x", -6.5, 0, 5.4, 2.2, 2, 1.1, 1.4, laeden=L)
    b.fenster_reihe("-y", 0.0, 5.0, 4.0, 5.4, 2, 1.1, 1.4, laeden=L)
    b.fenster_reihe("-y", 0.0, 5.0, 4.0, 2.2, 2, 1.1, 1.4, laeden=L)
    b.fenster_reihe("+x", 7.5, 3.0, 4.0, 5.4, 2, 1.1, 1.4)


def gasthaus(b):
    """Gasthaus: Laube vor dem Erdgeschoss, zwei Gauben, zwei Kamine, Wirtshausschild."""
    L = "holz_gruen"
    b.box(0, 0, 0, 12, 9, 7.2, "wand_creme")
    b.sockel(0, 0, 12, 9)
    d = b.dach(0, 0, 7.2, 12, 9, 4.8, "dach_terra", axis="x", over=0.55)
    for u in (-3.2, 3.2):
        b.gaube(d, u, seite=1, breite=2.4, laeden=L)
    for u in (-4.2, 4.2):
        b.kamin(d, u, -1.3)
    b.box(0, -5.5, 3.1, 9.4, 2.2, 0.22, "holz_dunkel")                # Laube
    for x in (-4.5, -1.5, 1.5, 4.5):
        b.box(x, -6.45, 0, 0.26, 0.26, 3.1, "holz_dunkel")
    b.fenster_reihe("-y", -4.5, 0, 9.6, 5.4, 4, 1.1, 1.4, laeden=L, kasten=True)
    for x in (-3.2, 3.2):
        b.fenster((x, -4.5, 1.9), 1.3, 1.5, "-y", laeden=L)
    b.tuer((0, -4.5, 1.2), 1.6, 2.4, "-y")
    b.fenster_reihe("+y", 4.5, 0, 9.6, 5.4, 4, 1.1, 1.4, laeden=L)
    b.fenster_reihe("+y", 4.5, 0, 9.6, 1.9, 4, 1.1, 1.4)
    for f, fx in (("-x", -6.0), ("+x", 6.0)):
        b.fenster_reihe(f, fx, 0, 5.0, 5.4, 2, 1.1, 1.4, laeden=L)
        b.fenster((fx, 0, 8.9), 1.0, 1.0, f)
    b.box(5.3, -5.2, 4.9, 0.16, 1.4, 0.16, "holz_dunkel")             # Ausleger
    b.feld((5.3, -5.6, 4.3), 0.9, 1.0, "+x", "holz_gruen", eps=0.0, zweiseitig=True)


def villa(b):
    """Villa: Walmdach mit Gauben, Veranda mit Balkon, zwei Kamine."""
    b.box(0, 0, 0, 13, 10, 7.8, "wand_weiss")
    b.sockel(0, 0, 13, 10)
    d = b.dach(0, 0, 7.8, 13, 10, 3.8, "dach_schiefer", axis="x", inset=2.4, over=0.6)
    for u in (-2.4, 2.4):
        b.gaube(d, u, seite=1, breite=2.2)
    for u in (-3.4, 3.4):
        b.kamin(d, u, -1.6)
    b.box(0, -6.4, 3.6, 8.0, 3.0, 0.3, "wand_weiss")          # Veranda-Dach/Balkon
    for x in (-3.6, -1.2, 1.2, 3.6):
        b.box(x, -7.6, 0, 0.35, 0.35, 3.6, "wand_weiss")
    for x in (-3.8, 3.8):                                      # Balkongelaender
        b.feld((x, -7.9, 4.4), 0.2, 1.0, "-y", "wand_weiss", eps=0.0, zweiseitig=True)
    b.feld((0, -7.9, 4.35), 7.8, 0.9, "-y", "wand_weiss", eps=0.0, zweiseitig=True)
    b.fenster_reihe("-y", -5.0, 0, 9.6, 5.6, 4, 1.3, 1.7, laeden="holz_dunkel")
    b.fenster_reihe("-y", -5.0, -3.6, 4.0, 1.9, 2, 1.3, 1.9)
    b.fenster_reihe("-y", -5.0, 3.6, 4.0, 1.9, 2, 1.3, 1.9)
    b.tuer((0, -5.0, 1.2), 1.8, 2.4, "-y")
    for f, fx in (("-x", -6.5), ("+x", 6.5)):
        b.fenster_reihe(f, fx, 0, 6.0, 5.6, 2, 1.3, 1.7, laeden="holz_dunkel")
        b.fenster_reihe(f, fx, 0, 6.0, 1.9, 2, 1.3, 1.7)
    b.fenster_reihe("+y", 5.0, 0, 9.6, 5.6, 4, 1.3, 1.7)
    b.fenster_reihe("+y", 5.0, 0, 9.6, 1.9, 4, 1.3, 1.7)


def kirche(b):
    b.box(0, 2.0, 0, 11, 20, 8.4, "wand_creme")               # Langhaus
    b.dach(0, 2.0, 8.4, 11, 20, 4.6, "dach_schiefer", axis="y", over=0.5)
    b.box(0, -10.0, 0, 6.4, 6.4, 17.0, "wand_creme")          # Westturm
    b.box(0, -10.0, 17.0, 7.0, 7.0, 0.5, "stein")
    b.spitze(0, -10.0, 17.5, 6.0, 6.0, 9.5, "dach_kupfer")
    b.zyl(0, -10.0, 27.0, 0.16, 0.16, 1.8, 6, "metall")       # Kreuz
    b.feld((0, -10.0, 28.1), 1.0, 0.2, "-y", "metall", eps=0.2, zweiseitig=True)
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
    b.sockel(0, 0, 7.5, 6)
    d = b.dach(0, 0, 3.6, 7.5, 6, 2.6, "dach_rot", axis="x", over=0.45)
    b.kamin(d, -2.0, -0.8)
    b.zyl(3.2, 1.6, 4.3, 0.14, 0.14, 7.5, 6, "metall")            # Signalmast
    for z in (8.2, 9.6):
        b.feld((3.2, 1.6, z), 1.6, 0.3, "-y", "dach_rot", eps=0.16, zweiseitig=True)
    b.fenster_reihe("-y", -3.0, 0.8, 4.4, 2.2, 2, 1.1, 1.2, laeden="holz_blau")
    b.tuer((-2.6, -3.0, 1.05), 1.1, 2.1, "-y", key="holz_blau", vordach="dach_rot")


# --- Hochhaeuser, Grossbauten & Sonderbauten ------------------------------------------------
def _baender(b, x, y, sx, sy, z0, z1, n, key="fenster", hoehe=1.5, rand=1.4):
    """Umlaufende Fensterbaender: EIN Quad je Fassade und Band statt Einzelfenster —
    aus der Luft dieselbe Wirkung fuer einen Bruchteil der Dreiecke."""
    for i in range(n):
        z = z0 + (z1 - z0) * (i + 0.5) / max(n, 1)
        b.feld((x, y - sy * 0.5, z), sx - rand * 2.0, hoehe, "-y", key)
        b.feld((x, y + sy * 0.5, z), sx - rand * 2.0, hoehe, "+y", key)
        b.feld((x - sx * 0.5, y, z), sy - rand * 2.0, hoehe, "-x", key)
        b.feld((x + sx * 0.5, y, z), sy - rand * 2.0, hoehe, "+x", key)
        if b.hd:
            # Geschossbaender ober- und unterhalb der Fensterzone + senkrechte Pfeiler
            for dz in (0.5, -0.5):
                zz = z + dz * (hoehe + 0.22)
                b.box(x, y, zz - 0.11, sx + 0.16, sy + 0.16, 0.22, "wand_weiss")
            for k in range(4):
                t = (k + 0.5) / 4 - 0.5
                b.feld((x + t * (sx - rand * 2.0), y - sy * 0.5, z), 0.16, hoehe, "-y", "wand_weiss", eps=0.05)
                b.feld((x + t * (sx - rand * 2.0), y + sy * 0.5, z), 0.16, hoehe, "+y", "wand_weiss", eps=0.05)


def hochhaus_wohnturm(b):
    b.box(0, 0, 0, 14, 14, 40.0, "beton")
    _baender(b, 0, 0, 14, 14, 3.5, 37.0, 7, "fenster", 1.8)
    b.box(0, 0, 40.0, 15.2, 15.2, 0.7, "beton")             # Attika
    b.box(3.2, 3.2, 40.7, 5.0, 5.0, 2.8, "wand_grau")       # Technikaufbau
    b.zyl(-3.6, -3.6, 40.7, 0.16, 0.16, 5.5, 6, "metall")   # Antenne
    for z in (11.0, 22.0, 33.0):                            # Balkonbaender
        b.box(0, -7.5, z, 12.0, 1.8, 0.35, "wand_weiss")
    b.feld((0, -7.0, 1.6), 3.4, 3.0, "-y", "glas")          # Eingang


def hochhaus_buero(b):
    b.box(0, 0, 0, 18, 15, 52.0, "metall_dunkel")
    for i in range(5):                                       # senkrechte Glasbaender
        t = (i + 0.5) / 5 - 0.5
        b.feld((t * 15.0, -7.5, 27.0), 2.1, 46.0, "-y", "glas")
        b.feld((t * 15.0, 7.5, 27.0), 2.1, 46.0, "+y", "glas")
    for i in range(4):
        t = (i + 0.5) / 4 - 0.5
        b.feld((-9.0, t * 12.5, 27.0), 2.1, 46.0, "-x", "glas")
        b.feld((9.0, t * 12.5, 27.0), 2.1, 46.0, "+x", "glas")
    b.box(0, 0, 52.0, 19.0, 16.0, 0.8, "metall")            # Dachkranz
    b.box(0, 3.0, 52.8, 8.0, 6.0, 3.2, "metall_dunkel")
    b.zyl(0, -4.0, 52.8, 0.2, 0.2, 9.0, 6, "metall")        # Mast
    b.feld((0, -7.5, 3.0), 9.0, 5.0, "-y", "glas")          # Lobby


def wolkenkratzer(b):
    b.box(0, 0, 0, 22, 22, 34.0, "beton")                   # Sockelblock
    _baender(b, 0, 0, 22, 22, 4.0, 31.0, 6, "fenster", 2.0)
    b.box(0, 0, 34.0, 23.0, 23.0, 0.8, "wand_grau")
    b.box(0, 0, 34.8, 16, 16, 24.0, "beton")                # 1. Ruecksprung
    _baender(b, 0, 0, 16, 16, 37.0, 57.0, 4, "fenster", 2.0)
    b.box(0, 0, 58.8, 17.0, 17.0, 0.8, "wand_grau")
    b.box(0, 0, 59.6, 10, 10, 15.0, "beton")                # 2. Ruecksprung
    _baender(b, 0, 0, 10, 10, 62.0, 72.0, 3, "fenster", 1.6)
    b.spitze(0, 0, 74.6, 10.4, 10.4, 5.0, "metall")         # Krone
    b.zyl(0, 0, 79.6, 0.35, 0.12, 12.0, 6, "metall")        # Turmspitze
    b.feld((0, -11.0, 3.4), 7.0, 6.0, "-y", "glas")


def plattenbau(b):
    b.box(0, 0, 0, 44, 12, 19.0, "beton")
    for i in range(6):
        z = 2.0 + i * 2.9
        b.feld((0, -6.0, z), 40.0, 1.5, "-y", "fenster")
        b.feld((0, 6.0, z), 40.0, 1.5, "+y", "fenster")
    b.box(0, 0, 19.0, 45.0, 13.0, 0.5, "wand_grau")
    for x in (-15.0, 0.0, 15.0):                             # Hauseingaenge
        b.feld((x, -6.0, 1.3), 2.2, 2.6, "-y", "holz_dunkel")
    b.box(-9.0, 3.0, 19.5, 3.4, 3.4, 2.2, "wand_grau")       # Aufzugsturm


def hotel(b):
    b.box(0, 0, 0, 24, 15, 26.0, "wand_creme")
    _baender(b, 0, 0, 24, 15, 5.0, 23.5, 6, "fenster", 1.5)
    b.box(0, 0, 26.0, 25.0, 16.0, 0.6, "dach_terra")
    b.box(0, -8.8, 3.4, 12.0, 3.6, 0.35, "wand_weiss")       # Vorfahrt-Vordach
    for x in (-5.0, 5.0):
        b.box(x, -10.2, 0, 0.4, 0.4, 3.4, "metall")
    b.feld((0, -7.5, 1.8), 8.0, 3.4, "-y", "glas")
    b.feld((0, -7.5, 24.6), 10.0, 1.8, "-y", "dach_rot", eps=0.1)   # Leuchtschrift
    b.box(9.0, 4.0, 26.6, 4.0, 4.0, 2.0, "metall_dunkel")


def kaufhaus(b):
    b.box(0, 0, 0, 28, 20, 11.5, "wand_taupe")
    b.feld((0, -10.0, 2.4), 24.0, 4.0, "-y", "glas")         # Schaufensterfront
    b.feld((0, -10.0, 8.0), 24.0, 2.2, "-y", "fenster")
    b.feld((-14.0, 0, 6.0), 16.0, 6.0, "-x", "fenster")
    b.feld((14.0, 0, 6.0), 16.0, 6.0, "+x", "fenster")
    b.box(0, 0, 11.5, 29.0, 21.0, 0.6, "beton")
    b.box(7.0, 5.0, 12.1, 7.0, 6.0, 2.4, "metall_dunkel")    # Lueftungszentrale
    b.feld((0, -10.2, 10.2), 14.0, 1.8, "-y", "dach_rot", eps=0.12)


def parkhaus(b):
    for i in range(5):                                        # offene Decks
        b.box(0, 0, i * 3.3, 26, 18, 0.4, "beton", skip=())
    for x in (-11.5, 0.0, 11.5):                              # Stuetzen
        for y in (-8.0, 8.0):
            b.box(x, y, 0, 0.8, 0.8, 13.2, "beton", skip=("top", "bottom"))
    for i in range(4):                                        # Bruestungsbaender
        z = i * 3.3 + 2.6
        b.feld((0, -9.0, z), 25.0, 0.9, "-y", "metall_dunkel")
        b.feld((0, 9.0, z), 25.0, 0.9, "+y", "metall_dunkel")
    b.box(-10.0, 7.0, 13.6, 4.4, 4.4, 3.4, "wand_grau")       # Treppenhaus
    b.feld((0, -9.0, 1.4), 5.0, 2.6, "-y", "metall_dunkel")   # Einfahrt


def krankenhaus(b):
    b.box(0, 0, 0, 30, 16, 22.0, "wand_weiss")
    _baender(b, 0, 0, 30, 16, 3.6, 20.0, 6, "fenster", 1.5)
    b.box(0, 0, 22.0, 31.0, 17.0, 0.5, "wand_grau")
    b.zyl(0, 0, 22.5, 6.5, 6.5, 0.3, 12, "beton")             # Hubschrauberdeck
    b.feld((0, 0, 22.85), 3.0, 0.9, "-y", "wand_weiss", eps=0.0)   # "H"
    b.feld((0, 0, 22.85), 0.9, 3.0, "-y", "wand_weiss", eps=0.0)
    b.box(-11.0, -9.5, 0, 8.0, 5.0, 5.0, "wand_weiss")        # Notaufnahme-Vorbau
    b.pultdach(-11.0, -9.5, 5.0, 8.0, 5.0, 0.8, "dach_rot")
    b.feld((-11.0, -12.0, 1.8), 3.4, 3.0, "-y", "glas")
    b.feld((-11.0, -12.0, 4.4), 5.0, 0.9, "-y", "dach_rot", eps=0.1)


def bahnhof(b):
    b.box(0, 0, 0, 30, 12, 10.0, "wand_sand")
    b.dach(0, 0, 10.0, 30, 12, 2.8, "dach_schiefer", axis="x", inset=3.0, over=0.6)
    b.box(0, -1.0, 10.0, 8.0, 10.0, 5.0, "wand_sand")         # Mittelrisalit
    b.spitze(0, -1.0, 15.0, 8.4, 10.4, 3.4, "dach_kupfer")
    b.feld((0, -6.0, 12.6), 2.6, 2.6, "-y", "wand_weiss")     # Bahnhofsuhr
    b.feld((0, -6.0, 12.6), 2.0, 2.0, "-y", "fenster", eps=0.09)
    b.feld((0, -6.0, 2.4), 5.5, 4.6, "-y", "glas")            # Portal
    b.fenster_reihe("-y", -6.0, -10.0, 7.0, 5.8, 2, 1.6, 3.0, "glas")
    b.fenster_reihe("-y", -6.0, 10.0, 7.0, 5.8, 2, 1.6, 3.0, "glas")
    b.box(0, 13.0, 6.2, 34, 16, 0.4, "metall_dunkel")         # Bahnsteighalle
    for x in (-15.0, 0.0, 15.0):
        for y in (6.5, 19.5):
            b.box(x, y, 0, 0.6, 0.6, 6.2, "metall", skip=("top", "bottom"))
    b.box(0, 13.0, 0, 30, 4.0, 0.35, "beton")                 # Bahnsteig


def fabrik(b):
    b.box(0, 0, 0, 30, 18, 8.0, "ziegel", skip=("bottom", "top"))
    prof = [(-15.0, 0.0), (-15.0, 11.0)]                      # SHEDDACH (Saegezahn)
    x = -15.0
    for i in range(4):
        x += 7.5
        prof.append((x, 8.0))
        if i < 3:
            prof.append((x, 11.0))
    prof.append((15.0, 0.0))
    b.profil(0, 0, 0, prof, 18.0, "ziegel")
    for gx in (-7.5, 0.0, 7.5):                                # Nordlicht-Verglasung
        b.feld((gx, 0, 9.5), 17.0, 2.9, "-x", "glas")
    b.zyl(-12.0, 7.0, 8.0, 1.5, 1.2, 18.0, 8, "ziegel")        # Schornstein
    b.box(13.0, -11.0, 0, 5.0, 4.0, 4.0, "wand_grau")          # Pfoertner
    b.pultdach(13.0, -11.0, 4.0, 5.0, 4.0, 0.8, "metall_dunkel")
    b.feld((0, -9.0, 3.0), 6.0, 4.4, "-y", "metall_dunkel")    # Werkstor


def kraftwerk(b):
    b.box(-7.0, 0, 0, 22, 16, 15.0, "beton")                   # Maschinenhaus
    b.pultdach(-7.0, 0, 15.0, 22, 16, 1.6, "metall_dunkel")
    for x in (-14.0, -9.0):
        b.zyl(x, 6.0, 15.0, 1.4, 1.1, 20.0, 8, "ziegel")       # Doppelschornstein
    b.zyl(13.0, 0, 0, 9.5, 6.6, 13.0, 12, "beton", cap_top=False)   # Kuehlturm
    b.zyl(13.0, 0, 13.0, 6.6, 8.0, 15.0, 12, "beton", cap_top=False)
    b.feld((-7.0, -8.0, 7.0), 16.0, 7.0, "-y", "fenster")
    b.box(-7.0, -10.0, 0, 6.0, 4.0, 3.0, "wand_grau")          # Schaltwarte


def funkturm(b):
    b.zyl(0, 0, 0, 4.5, 2.6, 22.0, 4, "metall_dunkel", cap_top=False)
    b.zyl(0, 0, 22.0, 2.6, 1.5, 16.0, 4, "metall_dunkel", cap_top=False)
    for z, w, hh in ((6.0, 7.0, 11.0), (16.0, 4.6, 9.0), (28.0, 3.4, 8.0)):
        for f, fx in (("-y", -w * 0.30), ("+y", w * 0.30)):    # Kreuzstreben
            b.feld((0, fx, z), 0.5, hh, f, "metall", eps=0.0, winkel=0.6, zweiseitig=True)
            b.feld((0, fx, z), 0.5, hh, f, "metall", eps=0.0, winkel=-0.6, zweiseitig=True)
    b.zyl(0, 0, 30.0, 4.2, 4.2, 2.6, 10, "wand_weiss")         # Kanzel
    b.zyl(0, 0, 29.7, 4.5, 4.5, 0.3, 10, "metall_dunkel")
    for i in range(5):
        t = (i + 0.5) / 5 - 0.5
        b.feld((t * 7.0, -4.2, 31.4), 1.2, 1.4, "-y", "glas")
    b.zyl(0, 0, 38.0, 0.5, 0.15, 16.0, 6, "metall")            # Sendemast
    b.feld((0, 0, 46.0), 2.2, 0.25, "-y", "dach_rot", eps=0.3, zweiseitig=True)


def hafenkran(b):
    b.box(0, 0, 0, 9.0, 9.0, 2.0, "metall_dunkel")             # Portal/Fahrwerk
    for x in (-3.6, 3.6):
        for y in (-3.6, 3.6):
            b.zyl(x, y, 0, 0.7, 0.7, 1.4, 6, "metall_dunkel")
    b.zyl(0, 0, 2.0, 2.4, 1.4, 22.0, 6, "dach_rot", cap_top=False)   # Turm
    b.box(0, 0, 24.0, 4.0, 4.0, 2.6, "metall")                 # Drehkopf
    b.box(9.0, 0, 25.4, 26.0, 2.0, 1.4, "dach_rot")            # Ausleger
    b.box(-6.0, 0, 25.4, 8.0, 3.0, 2.6, "metall_dunkel")       # Gegengewicht
    b.box(0, -2.4, 24.2, 2.6, 1.6, 2.0, "glas")                # Fuehrerkanzel
    b.box(17.0, 0, 18.2, 0.25, 0.25, 7.2, "metall_dunkel")     # Hubseil
    b.box(17.0, 0, 16.6, 1.8, 1.6, 1.6, "metall_dunkel")       # Spreader


def getreidesilo(b):
    for i in range(5):
        x = (i - 2) * 4.6
        b.zyl(x, 0, 0, 2.3, 2.3, 20.0, 10, "beton", cap_top=False)
        b.kegel(x, 0, 20.0, 2.4, 1.6, 10, "metall_dunkel")
    b.box(0, 0, 20.0, 23.0, 5.6, 4.0, "metall")                # Kopfbau/Foerderbruecke
    b.pultdach(0, 0, 24.0, 23.0, 5.6, 1.0, "metall_dunkel")
    b.box(-13.5, 0, 0, 5.0, 7.0, 8.0, "wand_grau")             # Annahme
    b.pultdach(-13.5, 0, 8.0, 5.0, 7.0, 1.0, "metall_dunkel")
    b.feld((-13.5, -3.5, 2.6), 3.4, 4.6, "-y", "metall_dunkel")


def stadion(b):
    n = 16
    R, RT, RI, hh = 38.0, 29.0, 26.0, 17.0
    V = []
    for i in range(n):
        a = 2.0 * math.pi * i / n
        c, sa = math.cos(a), math.sin(a)
        V += [(c * R, sa * R, 0.0), (c * R, sa * R, hh),
              (c * RT, sa * RT, hh), (c * RI, sa * RI, 2.5)]
    F = []
    for i in range(n):
        j = (i + 1) % n
        a0, b0 = i * 4, j * 4
        F.append((a0 + 0, b0 + 0, b0 + 1, a0 + 1))     # Aussenwand
        F.append((a0 + 1, b0 + 1, b0 + 2, a0 + 2))     # Dachkante
        F.append((a0 + 2, b0 + 2, b0 + 3, a0 + 3))     # Raenge
    b.add(V, F, "beton")
    spielfeld = [(math.cos(2.0 * math.pi * i / n) * RI * 0.97,
                  math.sin(2.0 * math.pi * i / n) * RI * 0.97, 0.35) for i in range(n)]
    b.add(spielfeld, [tuple(range(n))], "gruen")
    for k in range(4):                                  # Flutlichtmasten
        a = math.pi * 0.25 + k * math.pi * 0.5
        x, y = math.cos(a) * (R - 1.5), math.sin(a) * (R - 1.5)
        b.zyl(x, y, hh, 0.5, 0.35, 12.0, 6, "metall_dunkel")
        b.box(x, y, hh + 12.0, 4.4, 1.0, 1.8, "wand_weiss")


def burg(b):
    b.box(0, 0, 0, 15, 15, 20.0, "stein")                      # Bergfried
    b.box(0, 0, 20.0, 16.4, 16.4, 1.2, "stein")                # Wehrkranz
    b.spitze(0, 0, 21.2, 15.0, 15.0, 7.0, "dach_schiefer")
    for sx in (-1, 1):                                          # Ringmauer
        b.box(sx * 17.0, 0, 0, 3.0, 34.0, 9.0, "stein")
        b.box(0, sx * 17.0, 0, 34.0, 3.0, 9.0, "stein")
    for sx in (-1, 1):                                          # Ecktuerme
        for sy in (-1, 1):
            b.zyl(sx * 17.0, sy * 17.0, 0, 3.4, 3.0, 13.0, 8, "stein", cap_top=False)
            b.kegel(sx * 17.0, sy * 17.0, 13.0, 3.6, 5.0, 8, "dach_rot")
    b.feld((0, -18.5, 2.6), 4.0, 5.2, "-y", "holz_dunkel")      # Torbau
    for z in (8.0, 13.0, 16.5):
        b.feld((0, -7.5, z), 1.0, 2.2, "-y", "fenster")


def radarstation(b):
    b.box(0, 0, 0, 12, 10, 5.0, "beton")                        # Betriebsgebaeude
    b.pultdach(0, 0, 5.0, 12, 10, 1.0, "metall_dunkel")
    b.feld((0, -5.0, 2.2), 8.0, 2.2, "-y", "fenster")
    b.zyl(0, 3.0, 6.0, 3.2, 3.2, 5.0, 10, "beton")              # Kuppelsockel
    b.zyl(0, 3.0, 11.0, 4.4, 3.1, 2.6, 10, "wand_weiss")        # Radom
    b.kegel(0, 3.0, 13.6, 3.1, 2.2, 10, "wand_weiss")
    b.zyl(-7.0, -3.0, 0, 0.25, 0.25, 14.0, 6, "metall")         # Antennenmast
    b.feld((-7.0, -3.0, 12.5), 3.0, 0.3, "-y", "metall_dunkel", eps=0.3)
    b.feld((-7.0, -3.0, 10.5), 2.4, 0.3, "-y", "metall_dunkel", eps=0.3)


def bunker(b):
    prof = [(-7.0, 0.0), (-5.2, 4.2), (5.2, 4.2), (7.0, 0.0)]   # abgeschraegte Waende
    b.profil(0, 0, 0, prof, 10.0, "beton")
    b.box(0, 0, 4.2, 11.2, 10.6, 0.9, "beton")                  # Deckenplatte
    b.feld((0, -5.0, 2.6), 6.0, 0.7, "-y", "fenster", eps=0.35)  # Schartenband
    b.box(0, 4.2, 5.1, 3.6, 3.6, 1.8, "beton")                  # Beobachtungskanzel
    b.zyl(0, 4.2, 6.9, 1.5, 1.1, 1.0, 8, "metall_dunkel")
    b.zyl(-4.0, -3.0, 5.1, 0.18, 0.18, 4.0, 6, "metall")
    b.box(4.6, -3.6, 0, 2.4, 2.2, 2.6, "beton")                 # Eingangsschleuse

HAEUSER = [
    # Reihe 1-2: Dorf & Kleinstadt
    ("Haus_Bauernhaus", bauernhaus), ("Haus_Fachwerk", fachwerkhaus), ("Haus_Kate", kate),
    ("Haus_Scheune", scheune), ("Haus_Stall", stall), ("Haus_Silo", silo),
    ("Haus_Wassermuehle", wassermuehle),
    ("Haus_Windmuehle", windmuehle), ("Haus_Stadthaus2", stadthaus2),
    ("Haus_Stadthaus3", stadthaus3), ("Haus_Reihenhaus", reihenhaus),
    ("Haus_Eckhaus", eckhaus), ("Haus_Gasthaus", gasthaus), ("Haus_Villa", villa),
    # Reihe 3: oeffentliche Bauten
    ("Haus_Kirche", kirche), ("Haus_Kapelle", kapelle), ("Haus_Rathaus", rathaus),
    ("Haus_Bahnhof", bahnhof), ("Haus_Krankenhaus", krankenhaus),
    ("Haus_Kaufhaus", kaufhaus), ("Haus_Hotel", hotel),
    # Reihe 4: HOCHHAEUSER
    ("Haus_Wohnturm", hochhaus_wohnturm), ("Haus_Bueroturm", hochhaus_buero),
    ("Haus_Wolkenkratzer", wolkenkratzer), ("Haus_Plattenbau", plattenbau),
    ("Haus_Parkhaus", parkhaus), ("Haus_Speicher", speicher), ("Haus_Werkstatt", werkstatt),
    # Reihe 5: Industrie & Infrastruktur
    ("Haus_Fabrik", fabrik), ("Haus_Kraftwerk", kraftwerk),
    ("Haus_Getreidesilo", getreidesilo), ("Haus_Hafenkran", hafenkran),
    ("Haus_Funkturm", funkturm), ("Haus_Wasserturm", wasserturm),
    ("Haus_Tanklager", tanklager),
    # Reihe 6: Flugplatz & Sonderbauten
    ("Haus_Hangar", hangar), ("Haus_Tower", tower), ("Haus_Radarstation", radarstation),
    ("Haus_Bunker", bunker), ("Haus_Stadion", stadion), ("Haus_Burg", burg),
    ("Haus_Lotsenhaus", leuchtfeuer_haus),
]

# FARBVARIANTEN der haeufigen Wohnhaeuser: dieselbe Form, andere Wand-/Dach-/Ladenfarben.
# Export als "<Typ>_2", "<Typ>_3"; CityBuilder waehlt je Bauplatz eine Variante (Hash der
# Lage) — ein Dorf aus zwanzig identischen Bauernhaeusern sah aus der Luft wie ein Stempel aus.
VARIANTEN = {
    "Haus_Bauernhaus": [
        {"wand_creme": "wand_weiss", "dach_terra": "dach_schiefer", "holz_gruen": "holz_blau"},
        {"wand_creme": "wand_ocker", "dach_terra": "dach_rot", "holz_gruen": "holz_dunkel"}],
    "Haus_Fachwerk": [
        {"dach_terra": "dach_schiefer", "holz_dunkel": "holz_rot"},
        {"wand_weiss": "wand_creme", "holz_dunkel": "holz_hell", "dach_terra": "dach_rot"}],
    "Haus_Kate": [
        {"wand_sand": "wand_weiss", "holz_blau": "holz_gruen"},
        {"wand_sand": "wand_terra", "holz_blau": "holz_dunkel"}],
    "Haus_Scheune": [
        {"holz_rot": "holz_dunkel"},
        {"holz_rot": "holz_hell", "dach_schiefer": "dach_terra"}],
    "Haus_Stadthaus2": [
        {"wand_terra": "wand_blau", "dach_schiefer": "dach_terra", "holz_gruen": "holz_dunkel"},
        {"wand_terra": "wand_creme", "holz_gruen": "holz_rot"}],
    "Haus_Stadthaus3": [
        {"wand_ocker": "wand_mauve", "dach_terra": "dach_schiefer"},
        {"wand_ocker": "wand_gruen"}],
    "Haus_Reihenhaus": [
        {"wand_creme": "wand_ocker", "wand_mauve": "wand_weiss", "wand_blau": "wand_terra",
         "dach_schiefer": "dach_terra"}],
    "Haus_Eckhaus": [
        {"wand_sand": "wand_terra", "dach_terra": "dach_schiefer"}],
    "Haus_Gasthaus": [
        {"wand_creme": "wand_ocker", "dach_terra": "dach_schiefer", "holz_gruen": "holz_rot"}],
    "Haus_Villa": [
        {"wand_weiss": "wand_sand", "dach_schiefer": "dach_terra"}],
}


def alle_bauten():
    """(Name, Hausfunktion, Farbtausch, Grundtyp) fuer jeden Typ und jede Variante."""
    out = []
    for name, fn in HAEUSER:
        out.append((name, fn, {}, name))
        for i, t in enumerate(VARIANTEN.get(name, [])):
            out.append(("%s_%d" % (name, i + 2), fn, t, name))
    return out


# --- HD-Extras: Zutaten, die es NUR in der Nahansicht gibt ---------------------------------
# Aufgerufen nach dem Grundaufbau; die Silhouette bleibt dadurch unveraendert (LOD-tauglich).
def hd_fachwerk(b):
    for x in (-3.6, -1.2, 1.2, 3.6):                             # Knaggen unter dem Vorsprung
        b.box(x, -3.95, 2.95, 0.28, 0.5, 0.35, "holz_dunkel")
    b.box(0, -4.35, 3.3, 8.6, 0.2, 0.14, "holz_dunkel")          # Stockwerksschwelle


def hd_kirche(b):
    for y in (-5.5, -0.5, 4.5, 9.5):                             # Strebepfeiler
        for sx in (-1, 1):
            b.box(sx * 5.7, y, 0, 0.9, 1.4, 6.4, "wand_creme")
            b.dach(sx * 5.7, y, 6.4, 1.0, 1.5, 0.7, "dach_schiefer", axis="y", over=0.05)
    b.box(0, -13.3, 0, 4.4, 0.9, 0.5, "stein")                   # Portalstufe
    b.zyl(0, -10.0, 16.6, 0.35, 0.35, 0.6, 8, "stein")
    for sx in (-1, 1):                                            # Ecklisenen am Turm
        for sy in (-1, 1):
            b.box(sx * 3.0, -10.0 + sy * 3.0, 0, 0.7, 0.7, 17.0, "stein")


def hd_villa(b):
    b.box(0, -5.9, 0, 4.6, 1.6, 0.45, "stein")                    # Freitreppe
    for sx in (-1, 1):                                             # Ecklisenen (an den ECKEN)
        for sy in (-1, 1):
            b.box(sx * 6.4, sy * 4.9, 0, 0.5, 0.5, 7.8, "wand_weiss")
    b.box(0, 0, 7.5, 13.3, 10.3, 0.3, "wand_weiss")               # Traufgesims


def hd_rathaus(b):
    b.gelaender(0, -5.1, 8.0, 15.0, 0.3, "wand_sand", 0.9, 14)
    for x in (-6.0, -2.0, 2.0, 6.0):                              # Pilaster
        b.box(x, -5.0, 0, 0.6, 0.4, 8.0, "wand_weiss")
    b.box(0, -4.4, 0.45, 5.2, 1.8, 0.45, "stein")


def hd_wohnturm(b):
    for z in (11.0, 22.0, 33.0):
        b.gelaender(0, -8.3, z + 0.35, 12.0, 0.3, "wand_weiss", 1.0, 10)
    for x in (-7.0, 7.0):                                          # Lisenen
        b.box(x, 0, 0, 0.5, 14.2, 40.0, "wand_grau")
    b.box(0, 0, 43.5, 1.2, 1.2, 1.4, "metall_dunkel")              # Aufzugsmaschinenraum
    b.zyl(3.6, -3.6, 40.7, 0.5, 0.5, 1.2, 8, "metall_dunkel")


def hd_bueroturm(b):
    for i in range(6):                                             # Geschossbaender
        z = 4.0 + i * 8.0
        b.box(0, 0, z, 18.3, 15.3, 0.28, "metall")
    b.box(0, 0, 0, 19.4, 16.4, 1.2, "beton")                       # Sockelgeschoss
    b.box(0, -8.4, 5.2, 10.0, 2.0, 0.3, "metall")                  # Vordach
    b.zyl(0, 3.0, 56.0, 0.9, 0.9, 1.2, 8, "metall_dunkel")


def hd_wolkenkratzer(b):
    for z, w in ((34.0, 23.0), (58.8, 17.0)):                      # Terrassenbruestungen
        b.gelaender(0, 0, z + 0.8, w, w, "wand_grau", 1.0, 10)
    for sx in (-1, 1):                                              # Ecklisenen Sockel
        for sy in (-1, 1):
            b.box(sx * 11.0, sy * 11.0, 0, 1.2, 1.2, 34.0, "wand_grau")
    b.zyl(0, 0, 91.6, 0.16, 0.16, 5.0, 6, "metall")                # Fahnenmast
    b.feld((0, 0, 94.6), 1.8, 1.1, "-y", "dach_rot", eps=0.1, zweiseitig=True)


def hd_burg(b):
    b.zinnen(0, 0, 21.2, 16.4, 16.4, "stein", 7, 1.2)              # Bergfried-Zinnen
    for sx in (-1, 1):                                              # Mauerkronen-Zinnen
        b.zinnen(sx * 17.0, 0, 9.0, 3.0, 34.0, "stein", 9, 1.1)
        b.zinnen(0, sx * 17.0, 9.0, 34.0, 3.0, "stein", 9, 1.1)
    for sx in (-1, 1):
        b.box(sx * 17.0, 0, 7.4, 4.4, 34.0, 0.5, "stein")          # Wehrgang
        b.box(0, sx * 17.0, 7.4, 34.0, 4.4, 0.5, "stein")
    b.box(0, -18.6, 8.0, 5.6, 2.2, 3.4, "stein")                   # Torturm-Aufsatz
    b.zinnen(0, -18.6, 11.4, 5.6, 2.2, "stein", 4, 0.9)


def hd_stadion(b):
    n = 16
    for i in range(n):                                              # Dachtraeger
        a = 2.0 * math.pi * i / n
        c, sa = math.cos(a), math.sin(a)
        b.box(c * 33.5, sa * 33.5, 17.0, 1.0, 1.0, 2.2, "metall_dunkel")
    for i in range(n):                                              # Vordach
        a = 2.0 * math.pi * (i + 0.5) / n
        b.box(math.cos(a) * 33.0, math.sin(a) * 33.0, 19.2, 6.0, 6.0, 0.4, "metall")


def hd_hangar(b):
    for y in (-8.0, -2.0, 4.0, 8.5):                                # Binder/Traeger
        b.box(0, y, 8.6, 21.0, 0.5, 0.5, "metall_dunkel")
    for x in (-10.4, 10.4):
        b.box(x, 0, 0, 0.6, 20.0, 4.6, "metall_dunkel")             # Wandpfosten
    b.box(0, -10.2, 7.0, 17.4, 0.5, 0.6, "metall_dunkel")           # Torschiene
    b.box(0, -10.4, 0, 18.0, 0.6, 0.4, "beton")                     # Vorfeldschwelle


def hd_bahnhof(b):
    for x in (-15.0, 0.0, 15.0):                                     # Bahnsteigdach-Traeger
        b.box(x, 13.0, 5.9, 1.0, 15.6, 0.4, "metall_dunkel")
    b.box(0, -6.4, 5.0, 30.0, 0.8, 0.4, "wand_weiss")               # Gurtgesims
    b.box(0, -6.6, 6.6, 7.0, 1.0, 0.3, "metall_dunkel")             # Vordach ueberm Portal
    for x in (-3.0, 3.0):
        b.box(x, -7.0, 0, 0.25, 0.25, 6.6, "metall_dunkel")


def hd_fabrik(b):
    for gx in (-11.0, -3.5, 4.0, 11.5):                              # Fassadenpfeiler
        b.box(gx, 0, 0, 0.7, 18.2, 8.0, "ziegel")
    for y in (-6.0, 0.0, 6.0):                                       # Dachlaufsteg
        b.box(0, y, 11.1, 30.0, 0.5, 0.25, "metall_dunkel")
    b.zyl(-12.0, 7.0, 26.0, 1.7, 1.7, 0.8, 8, "metall_dunkel")       # Schornsteinkrone
    b.box(9.0, 9.2, 0, 3.0, 0.5, 6.5, "metall_dunkel")               # Rohrbruecke


def hd_kraftwerk(b):
    for i in range(4):                                                # Rohrleitungen
        b.zyl(-1.0 + i * 1.2, -8.4, 4.0, 0.32, 0.32, 9.0, 8, "metall")
    b.box(-7.0, 0, 16.6, 22.4, 16.4, 0.5, "metall_dunkel")            # Dachrand
    b.zyl(13.0, 0, 27.8, 8.0, 8.0, 0.6, 12, "beton")                  # Kuehlturm-Krone
    for x in (-14.0, -9.0):
        b.zyl(x, 6.0, 34.6, 1.5, 1.5, 0.7, 8, "metall_dunkel")


def hd_windmuehle(b):
    for k in range(2):                                                 # Fluegel-Gitter
        a = k * math.pi * 0.5 + 0.35
        for j in (-1, 1):
            b.feld((0, -4.15, 10.9), 0.22, 13.0, "-y", "holz_dunkel",
                   eps=0.0, winkel=a + j * 0.10, zweiseitig=True)
    b.gelaender(0, 0, 5.65, 8.4, 8.4, "holz_dunkel", 0.9, 12)
    b.box(0, -3.4, 1.0, 2.2, 0.5, 0.25, "holz_dunkel")                # Tuerschwelle


def hd_kaufhaus(b):
    for x in (-13.0, -6.5, 0.0, 6.5, 13.0):                            # Schaufenster-Pfeiler
        b.box(x, -10.0, 0, 0.6, 0.5, 11.5, "wand_weiss")
    b.box(0, -10.6, 4.6, 25.0, 1.4, 0.35, "dach_rot")                  # Markise
    b.gelaender(0, 0, 12.1, 28.0, 20.0, "wand_grau", 0.9, 14)


def hd_krankenhaus(b):
    b.gelaender(0, 0, 22.8, 30.5, 16.5, "wand_grau", 1.0, 14)
    for x in (-14.0, 14.0):
        b.box(x, 0, 0, 0.6, 16.2, 22.0, "wand_grau")
    b.zyl(0, 0, 22.8, 6.6, 6.6, 0.12, 12, "metall_dunkel")             # Deckrand Helipad


def hd_getreidesilo(b):
    for i in range(5):
        x = (i - 2) * 4.6
        b.zyl(x, 0, 19.6, 2.45, 2.45, 0.5, 10, "metall")               # Ringanker
        b.zyl(x, 0, 9.8, 2.45, 2.45, 0.35, 10, "metall")
    b.box(0, -3.0, 6.0, 23.0, 0.4, 0.4, "metall_dunkel")               # Steigleiter-Schiene
    b.box(11.6, 0, 0, 0.5, 0.5, 20.0, "metall_dunkel")


def hd_gasthaus(b):
    for sx in (-1, 1):                                                  # Eckstaender
        for sy in (-1, 1):
            b.box(sx * 5.9, sy * 4.4, 0, 0.35, 0.35, 7.2, "holz_dunkel")
    for x in (-3.0, 3.0):                                               # Baenke unter der Laube
        b.box(x, -5.6, 0, 2.2, 0.5, 0.45, "holz_hell")


HD_EXTRAS = {
    "Haus_Fachwerk": hd_fachwerk, "Haus_Kirche": hd_kirche,
    "Haus_Villa": hd_villa, "Haus_Rathaus": hd_rathaus, "Haus_Wohnturm": hd_wohnturm,
    "Haus_Bueroturm": hd_bueroturm, "Haus_Wolkenkratzer": hd_wolkenkratzer,
    "Haus_Burg": hd_burg, "Haus_Stadion": hd_stadion, "Haus_Hangar": hd_hangar,
    "Haus_Bahnhof": hd_bahnhof, "Haus_Fabrik": hd_fabrik, "Haus_Kraftwerk": hd_kraftwerk,
    "Haus_Windmuehle": hd_windmuehle, "Haus_Kaufhaus": hd_kaufhaus,
    "Haus_Krankenhaus": hd_krankenhaus, "Haus_Getreidesilo": hd_getreidesilo,
    "Haus_Gasthaus": hd_gasthaus,
}



def hd_plattenbau(b):
    for i in range(6):                                              # Balkonbaender je Geschoss
        z = 2.0 + i * 2.9
        b.box(0, -6.5, z - 0.75, 40.0, 1.1, 0.22, "wand_grau")
        b.gelaender(0, -6.9, z - 0.53, 40.0, 0.3, "wand_weiss", 0.95, 26)
    for x in (-15.0, 0.0, 15.0):                                    # Eingangsvordaecher
        b.box(x, -6.9, 3.1, 3.4, 1.6, 0.25, "wand_grau")
        for dx in (-1.4, 1.4):
            b.box(x + dx, -7.5, 0, 0.16, 0.16, 3.1, "wand_grau")
    for x in (-22.0, -11.0, 0.0, 11.0, 22.0):                       # Fassadenfugen
        b.box(x, 0, 0, 0.22, 12.2, 19.0, "wand_grau")
    b.gelaender(0, 0, 19.5, 44.0, 12.0, "wand_grau", 0.8, 22)       # Dachattika
    b.box(9.0, 3.0, 19.5, 2.4, 2.4, 1.6, "wand_grau")               # Lueftungsaufbau


def hd_parkhaus(b):
    for i in range(4):                                               # Gelaender je Deck
        z = i * 3.3 + 0.4
        b.gelaender(0, -9.0, z, 26.0, 0.3, "metall_dunkel", 1.05, 16)
        b.gelaender(0, 9.0, z, 26.0, 0.3, "metall_dunkel", 1.05, 16)
        b.gelaender(-13.0, 0, z, 0.3, 18.0, "metall_dunkel", 1.05, 11)
        b.gelaender(13.0, 0, z, 0.3, 18.0, "metall_dunkel", 1.05, 11)
    for i in range(4):                                               # Auffahrtsrampe
        b.box(8.0, -4.0 + i * 2.4, i * 3.3, 8.0, 2.4, 0.3, "beton")
    b.gelaender(-10.0, 7.0, 17.0, 4.4, 4.4, "metall_dunkel", 0.9, 6)
    for x in (-9.0, 9.0):                                            # Lichtmasten
        b.zyl(x, 0, 13.6, 0.14, 0.14, 3.4, 6, "metall_dunkel")
        b.box(x, 0, 17.0, 1.4, 0.4, 0.24, "wand_weiss")


def hd_silo(b):
    for z in (3.0, 6.3, 9.0):                                        # Ringanker
        b.zyl(0, 0, z, 2.42, 2.42, 0.28, 10, "metall_dunkel")
    for i in range(9):                                               # Steigleiter
        b.box(2.35, 0, 0.6 + i * 1.0, 0.5, 0.06, 0.06, "metall_dunkel")
    b.box(2.5, 0, 0, 0.06, 0.7, 9.5, "metall_dunkel")
    b.zyl(0, 0, 9.5, 2.45, 2.45, 0.35, 10, "metall_dunkel")
    b.box(-1.4, -2.2, 1.2, 1.2, 1.2, 2.4, "metall_dunkel")           # Auslauf/Schurre
    b.gelaender(0, 0, 11.4, 2.0, 2.0, "metall_dunkel", 0.8, 6)


def hd_bunker(b):
    b.box(0, -5.1, 2.35, 6.6, 0.5, 1.2, "metall_dunkel")             # Scharten-Einfassung
    for x in (-2.0, 0.0, 2.0):
        b.box(x, -5.1, 2.35, 0.35, 0.6, 1.2, "beton")                # Zwischenstege
    for i in range(6):                                                # Sandsackreihe
        b.box(-4.0 + i * 1.6, -6.0, 0, 1.4, 0.9, 0.55, "wand_sand")
        b.box(-3.2 + i * 1.6, -6.0, 0.55, 1.4, 0.9, 0.5, "wand_sand")
    b.zyl(2.2, 3.4, 5.1, 0.22, 0.22, 1.6, 6, "metall_dunkel")        # Lueftungsrohre
    b.zyl(-2.6, 3.4, 5.1, 0.22, 0.22, 1.4, 6, "metall_dunkel")
    b.gelaender(0, 4.2, 6.9, 3.2, 3.2, "metall_dunkel", 0.8, 6)


def hd_werkstatt(b):
    for x in (-4.0, 0.0, 4.0):                                        # Dachlueftungshauben
        b.box(x, 1.5, 5.6, 1.6, 1.2, 0.7, "metall_dunkel")
    b.box(-2.0, -4.2, 3.7, 4.8, 0.6, 0.3, "metall_dunkel")           # Torsturz
    for x in (-4.5, 0.5):
        b.box(x, -4.3, 0, 0.22, 0.4, 3.7, "metall_dunkel")
    b.zyl(4.6, 2.4, 8.0, 0.5, 0.5, 0.4, 6, "metall")                 # Kaminhut
    b.box(6.2, -2.0, 0, 0.4, 3.0, 4.4, "metall_dunkel")              # Fallrohr/Leitung
    b.box(0, 0, 4.4, 12.4, 8.4, 0.28, "metall_dunkel")               # Traufblech


def hd_wasserturm(b):
    b.gelaender(0, 0, 14.2, 8.6, 8.6, "metall_dunkel", 1.0, 14)      # Behaelter-Umgang
    for a in (0.0, 1.5708, 3.1416, 4.7124):                          # Kreuzverbaende
        x, y = math.cos(a) * 1.9, math.sin(a) * 1.9
        b.box(x, y, 2.0, 0.22, 0.22, 7.0, "metall_dunkel")
    for i in range(8):                                                # Steigleiter
        b.box(2.9, 0, 1.0 + i * 1.0, 0.5, 0.06, 0.06, "metall_dunkel")
    b.zyl(0, 0, 8.6, 4.5, 4.5, 0.3, 10, "metall_dunkel")
    b.box(0, -4.2, 12.0, 2.6, 0.3, 1.2, "wand_weiss")                # Schriftfeld


def hd_funkturm(b):
    for z in (2.0, 9.0, 18.0, 25.0):                                  # Horizontalriegel
        w = 8.6 - z * 0.22
        b.box(0, 0, z, w, w, 0.26, "metall_dunkel")
    b.gelaender(0, 0, 32.6, 8.6, 8.6, "metall_dunkel", 1.0, 14)      # Kanzel-Umgang
    for a in (0.6, 2.2, 3.8, 5.4):                                    # Richtfunkschuesseln
        x, y = math.cos(a) * 2.4, math.sin(a) * 2.4
        b.zyl(x, y, 24.0, 0.9, 0.7, 0.5, 8, "wand_weiss", achse="y")
    for z in (40.0, 46.0):
        b.box(0, 0, z, 1.8, 0.2, 0.16, "metall_dunkel")


def hd_hafenkran(b):
    for i in range(6):                                                 # Auslegergitter
        x = -2.0 + i * 4.6
        b.box(x, 0, 25.4, 0.3, 2.2, 1.5, "dach_rot")
    b.box(9.0, 0, 26.8, 26.0, 0.3, 0.3, "dach_rot")                   # Obergurt
    for z in (6.0, 12.0, 18.0):                                        # Turmverbaende
        b.box(0, 0, z, 4.0, 4.0, 0.26, "dach_rot")
    b.gelaender(0, 0, 26.6, 4.4, 4.4, "metall_dunkel", 0.9, 6)
    b.box(17.0, 0, 21.0, 0.4, 0.4, 4.4, "metall_dunkel")              # zweites Seil
    for x in (-3.6, 3.6):                                              # Schienen
        b.box(x, 0, 0, 0.5, 11.0, 0.25, "metall_dunkel")


def hd_tanklager(b):
    for x in (-3.4, 3.4):
        b.gelaender(x, -5.5, 5.0, 4.0, 11.0, "metall_dunkel", 0.9, 9)  # Tank-Laufsteg
        b.box(x, -5.5, 4.9, 1.4, 11.0, 0.16, "metall_dunkel")
        for i in range(4):                                              # Spannringe
            b.zyl(x, -8.0 + i * 3.0, 3.1, 1.95, 1.95, 0.2, 10, "metall_dunkel", achse="y")
    b.box(0, -11.4, 0, 8.4, 0.5, 3.6, "metall_dunkel")                 # Treppenturm
    for i in range(5):
        b.box(-1.2, -11.4, 0.4 + i * 0.7, 1.6, 0.5, 0.12, "metall")
    for x in (-3.4, 3.4):                                               # Steigrohre
        b.zyl(x, 1.2, 1.0, 0.22, 0.22, 3.2, 6, "metall")


def hd_bueroturm(b):
    for i in range(12):                                                 # feines Fassadenraster
        z = 3.0 + i * 4.1
        b.box(0, 0, z, 18.25, 15.25, 0.2, "metall")
    for x in (-9.1, 9.1):
        b.box(x, 0, 0, 0.3, 15.3, 52.0, "metall")
    b.gelaender(0, 0, 52.8, 18.0, 15.0, "metall_dunkel", 0.9, 16)      # Dachumgang
    b.box(-5.0, -3.0, 52.8, 3.4, 3.4, 2.2, "metall_dunkel")            # Kuehlaggregate
    b.box(5.0, -3.0, 52.8, 2.6, 2.6, 1.8, "metall_dunkel")


def hd_tower(b):
    b.gelaender(0, 0, 14.95, 9.6, 9.6, "metall_dunkel", 1.0, 12)       # Dachumgang
    b.box(0, 0, 10.9, 9.4, 9.4, 0.3, "beton")                          # Kanzelsockel
    for a in (0.0, 1.5708, 3.1416, 4.7124):                            # Kanzelstuetzen
        x, y = math.cos(a) * 4.3, math.sin(a) * 4.3
        b.box(x, y, 11.0, 0.3, 0.3, 3.6, "metall_dunkel")
    b.zyl(-2.8, -2.8, 15.6, 1.1, 0.9, 0.7, 10, "wand_weiss")           # Radarhaube
    for i in range(7):                                                  # Aussentreppe
        b.box(3.6, -3.4, 1.2 + i * 1.4, 2.0, 1.0, 0.16, "metall_dunkel")
    b.box(0, 0, 3.6, 6.7, 6.7, 0.22, "beton")


def hd_radarstation(b):
    for i in range(8):                                                  # Zaun
        a = 2.0 * math.pi * i / 8
        b.box(math.cos(a) * 11.0, math.sin(a) * 11.0, 0, 0.16, 0.16, 2.0, "metall_dunkel")
    b.zyl(0, 3.0, 10.9, 3.35, 3.35, 0.3, 10, "metall_dunkel")          # Kuppelring
    b.gelaender(0, 3.0, 11.0, 6.8, 6.8, "metall_dunkel", 0.9, 10)
    for i in range(6):                                                  # Leiter zur Kuppel
        b.box(3.0, 3.0, 6.4 + i * 0.75, 0.45, 0.06, 0.06, "metall_dunkel")
    b.box(0, 0, 6.0, 12.2, 10.2, 0.25, "metall_dunkel")                # Dachrand
    for x in (-4.0, 4.0):
        b.box(x, -5.2, 5.2, 1.6, 0.4, 0.5, "metall_dunkel")            # Klimageraete


def hd_kate(b):
    for sx in (-1, 1):                                                  # Eckstaender
        for sy in (-1, 1):
            b.box(sx * 3.2, sy * 2.6, 0, 0.3, 0.3, 2.8, "holz_dunkel")
    b.box(-2.3, -3.2, 0, 1.6, 0.9, 0.5, "holz_hell")                    # Holzstapel


def hd_kapelle(b):
    for y in (-2.0, 1.6):                                               # Strebepfeiler
        for sx in (-1, 1):
            b.box(sx * 2.9, y, 0, 0.6, 0.9, 3.4, "wand_weiss")
    b.box(0, -4.2, 0, 2.6, 0.6, 0.35, "stein")                         # Portalstufe
    b.zyl(0, -2.6, 11.2, 0.14, 0.14, 1.0, 6, "metall")                 # Kreuz
    b.feld((0, -2.6, 11.9), 0.6, 0.12, "-y", "metall", eps=0.16, zweiseitig=True)
    b.box(0, 0, 4.2, 5.6, 8.2, 0.22, "wand_weiss")                     # Traufgesims


def hd_stall(b):
    for x in (-4.2, -1.4, 1.4, 4.2):                                    # Holzstaender
        b.box(x, -3.05, 0, 0.28, 0.3, 2.9, "holz_dunkel")
    b.box(0, -3.05, 2.9, 10.2, 0.3, 0.28, "holz_dunkel")               # Rahmriegel
    b.box(0, 0, 2.9, 10.6, 6.6, 0.22, "holz_dunkel")
    for i in range(4):                                                   # Traenken/Tore
        b.box(-3.6 + i * 2.4, -3.2, 0, 1.8, 0.25, 1.1, "holz_hell")


HD_EXTRAS.update({
    "Haus_Plattenbau": hd_plattenbau, "Haus_Parkhaus": hd_parkhaus, "Haus_Silo": hd_silo,
    "Haus_Bunker": hd_bunker, "Haus_Werkstatt": hd_werkstatt,
    "Haus_Wasserturm": hd_wasserturm, "Haus_Funkturm": hd_funkturm,
    "Haus_Hafenkran": hd_hafenkran, "Haus_Tanklager": hd_tanklager,
    "Haus_Bueroturm": hd_bueroturm, "Haus_Tower": hd_tower,
    "Haus_Radarstation": hd_radarstation, "Haus_Kate": hd_kate,
    "Haus_Kapelle": hd_kapelle, "Haus_Stall": hd_stall,
})

PER_ROW = 7
SPACING = 92.0
ORIGIN_Y = 0.0


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)   # leere Szene -> keine Alt-Gebaeude
    scn = bpy.context.scene

    top = bpy.data.collections.get("HAEUSER")
    if top is None:
        top = bpy.data.collections.new("HAEUSER")
        scn.collection.children.link(top)

    labels = bpy.data.collections.get("HAEUSER_Labels")
    if labels is None:
        labels = bpy.data.collections.new("HAEUSER_Labels")
        top.children.link(labels)

    top_hd = bpy.data.collections.get("HAEUSER_HD")
    if top_hd is None:
        top_hd = bpy.data.collections.new("HAEUSER_HD")
        scn.collection.children.link(top_hd)

    report = []
    for i, (name, fn, tausch, grund) in enumerate(alle_bauten()):
        col, row = i % PER_ROW, i // PER_ROW
        ort = (col * SPACING, ORIGIN_Y - row * SPACING)
        b = Bau(name, tausch=tausch)
        fn(b)
        ob = b.build(top, ort)
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)

        # HD-Stufe: gleicher Aufbau mit hd=True + optionale Zusatzdetails
        bh = Bau(name + "_HD", hd=True, tausch=tausch)   # eigener Name -> keine .001-Kollision
        fn(bh)
        extra = HD_EXTRAS.get(grund)
        if extra is not None:
            extra(bh)
        obh = bh.build(top_hd, (ort[0], ort[1] - HD_VERSATZ))
        tris_hd = sum(len(p.vertices) - 2 for p in obh.data.polygons)
        report.append((name, tris, tris_hd, len(ob.data.vertices), len(b.mats)))

        txt = bpy.data.curves.new(name + "_lbl", type='FONT')
        txt.body = name.replace("Haus_", "")
        txt.size = 2.4
        tob = bpy.data.objects.new(name + "_lbl", txt)
        tob.location = (ort[0] - 8.0, ort[1] - 16.0, 0.05)
        labels.objects.link(tob)

    bpy.ops.wm.save_mainfile(filepath=OUT)
    print("SAVED", OUT)

    # Fuers SPIEL: alle 42 Haeuser als EIN glb (scripts/CityBuilder.gd zieht daraus die
    # Meshes und setzt sie per MultiMesh in die Welt). Kein Teil-glb -> PartCatalog
    # (models/<part_id>.glb) fasst die Datei nicht an.
    bpy.ops.object.select_all(action='DESELECT')
    erste = None
    for nm, _fn, _t, _g in alle_bauten():
        ob = bpy.data.objects.get(nm)
        if ob is not None:
            ob.select_set(True)
            erste = erste or ob
    bpy.context.view_layer.objects.active = erste
    bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', use_selection=True,
                              export_apply=True)
    print("EXPORTED", GLB)

    # dasselbe fuer die HD-Stufe -> world_buildings_hd.glb. Die Knoten heissen dort
    # "<Typ>_HD"; CityBuilder schneidet das Suffix beim Einlesen ab (Umbenennen waere
    # riskant: der LOD-Knoten belegt den Namen schon, Blender haengt sonst .001 an).
    bpy.ops.object.select_all(action='DESELECT')
    erste = None
    for nm, _fn, _t, _g in alle_bauten():
        ob = bpy.data.objects.get(nm + "_HD")
        if ob is not None:
            ob.select_set(True)
            erste = erste or ob
    bpy.context.view_layer.objects.active = erste
    bpy.ops.export_scene.gltf(filepath=GLB_HD, export_format='GLB', use_selection=True,
                              export_apply=True)
    print("EXPORTED", GLB_HD)
    total = sum(r[1] for r in report)
    total_hd = sum(r[2] for r in report)
    print("HAEUSER: %d Stueck | LOD %d Tris (Schnitt %.0f) | HD %d Tris (Schnitt %.0f)"
          % (len(report), total, total / max(len(report), 1),
             total_hd, total_hd / max(len(report), 1)))
    for name, tris, tris_hd, verts, nm in sorted(report, key=lambda r: -r[2]):
        print("  %-20s LOD %4d  HD %5d Tris  (x%.1f)" % (name, tris, tris_hd,
                                                         tris_hd / max(tris, 1)))

    pruefen()
    if PREVIEW:
        render_previews(scn)


def pruefen():
    """Jede GESCHLOSSENE Insel (Dachplatten, Gauben, Kamine mit Deckel ...) muss ein positives
    Volumen haben (nach aussen gewickelt). Offene Teile (Waende ohne Boden, Felder) zaehlen
    nicht. Belegt, dass die neue Dachplatte nicht wieder verkehrt herum liegt."""
    import bmesh
    schlecht = 0
    for nm, _fn, _t, _g in alle_bauten():
        for n2 in (nm, nm + "_HD"):
            ob = bpy.data.objects.get(n2)
            bm = bmesh.new()
            bm.from_mesh(ob.data)
            bm.faces.ensure_lookup_table()
            gesehen = set()
            for f in bm.faces:
                if f.index in gesehen:
                    continue
                insel, stapel = [], [f]
                gesehen.add(f.index)
                while stapel:
                    g = stapel.pop()
                    insel.append(g)
                    for e in g.edges:
                        for h in e.link_faces:
                            if h.index not in gesehen:
                                gesehen.add(h.index)
                                stapel.append(h)
                if any(len(e.link_faces) != 2 for g in insel for e in g.edges):
                    continue
                vol = 0.0
                for g in insel:
                    ps = [v.co for v in g.verts]
                    for k in range(1, len(ps) - 1):
                        vol += ps[0].dot(ps[k].cross(ps[k + 1]))
                if vol <= 0.0:
                    schlecht += 1
                    print("  VERKEHRT: %s (%d Flaechen)" % (n2, len(insel)))
            bm.free()
    print("PRUEFUNG HAEUSER: %s" % ("OK" if schlecht == 0 else "%d verkehrte Inseln" % schlecht))


def render_previews(scn):
    """Gruppenbilder: die Haeuser einer Gruppe werden (nach dem Speichern/Export) in eine
    Reihe gestellt und aus 3/4-Sicht von vorn fotografiert. Die alte Vorschau nahm die
    Huelle aus `bound_box`, das direkt nach dem Bauen noch leer ist — die Bilder zeigten
    einen Ausschnitt irgendwo in der Szene."""
    from mathutils import Vector as V
    bpy.context.view_layer.update()
    cam = bpy.data.objects.new("PrevCam", bpy.data.cameras.new("PrevCam"))
    scn.collection.objects.link(cam)
    scn.camera = cam
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'MATERIAL'
    scn.display.shading.show_shadows = True
    scn.display.shading.show_cavity = True
    scn.world = scn.world or bpy.data.worlds.new("W")
    scn.world.color = (0.55, 0.68, 0.85)
    boden = bpy.data.objects.new("PrevBoden", bpy.data.meshes.new("PrevBoden"))
    boden.data.from_pydata([(-1e4, -1e4, 0), (1e4, -1e4, 0), (1e4, 1e4, 0), (-1e4, 1e4, 0)], [],
                           [(0, 1, 2, 3)])
    gm = bpy.data.materials.new("PrevGras")
    gm.diffuse_color = (0.30, 0.42, 0.20, 1.0)
    boden.data.materials.append(gm)
    scn.collection.objects.link(boden)

    def huelle(ob):
        ws = [ob.matrix_world @ v.co for v in ob.data.vertices]
        lo = V((min(w.x for w in ws), min(w.y for w in ws), min(w.z for w in ws)))
        hi = V((max(w.x for w in ws), max(w.y for w in ws), max(w.z for w in ws)))
        return lo, hi

    def gruppe(namen, pfad, res=(1800, 760), hoehe=0.42, von_links=0.45, blick=None):
        obs = [bpy.data.objects.get(n) for n in namen]
        obs = [o for o in obs if o is not None]
        x = 0.0
        for ob in obs:                                      # in eine Reihe stellen
            lo, hi = huelle(ob)
            ob.location.x += x - lo.x
            ob.location.y += 5000.0 - (lo.y + hi.y) * 0.5
            bpy.context.view_layer.update()
            x += (hi.x - lo.x) + 5.0
        lo = V((1e9, 1e9, 1e9))
        hi = V((-1e9, -1e9, -1e9))
        for ob in obs:
            a2, b2 = huelle(ob)
            lo = V(map(min, lo, a2))
            hi = V(map(max, hi, b2))
        ctr = (lo + hi) * 0.5
        cam.data.lens = 50
        scn.render.resolution_x, scn.render.resolution_y = res
        breite = (hi.x - lo.x) * 1.08
        fov = 2.0 * math.atan(0.5 * 36.0 / cam.data.lens)
        dist = breite * 0.5 / math.tan(fov * 0.5) + (hi.y - lo.y)
        d = (V(blick) if blick else V((-von_links, -1.0, hoehe))).normalized()
        cam.location = ctr + d * dist
        cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
        cam.data.clip_end = dist * 4.0
        scn.render.filepath = pfad
        bpy.ops.render.render(write_still=True)
        for ob in obs:                                      # zurueck aus dem Bild
            ob.location.y -= 20000.0
        bpy.context.view_layer.update()
        print("PREVIEW", pfad)

    dorf = ["Haus_Bauernhaus", "Haus_Fachwerk", "Haus_Kate", "Haus_Scheune", "Haus_Stall",
            "Haus_Gasthaus"]
    stadt = ["Haus_Stadthaus2", "Haus_Stadthaus3", "Haus_Reihenhaus", "Haus_Eckhaus",
             "Haus_Villa", "Haus_Lotsenhaus"]
    gross = ["Haus_Kirche", "Haus_Kapelle", "Haus_Rathaus", "Haus_Bahnhof", "Haus_Wassermuehle",
             "Haus_Windmuehle", "Haus_Speicher"]
    gruppe([n + "_HD" for n in dorf], os.path.join(PREVIEW, "hd_dorf.png"))
    gruppe([n + "_HD" for n in stadt], os.path.join(PREVIEW, "hd_stadt.png"))
    gruppe([n + "_HD" for n in gross], os.path.join(PREVIEW, "hd_gross.png"))
    gruppe(dorf, os.path.join(PREVIEW, "lod_dorf.png"))
    gruppe(stadt, os.path.join(PREVIEW, "lod_stadt.png"))
    gruppe([n for n, _f, _t, g in alle_bauten() if g in ("Haus_Bauernhaus", "Haus_Fachwerk",
                                                            "Haus_Kate", "Haus_Stadthaus2")],
           os.path.join(PREVIEW, "varianten.png"), hoehe=0.6)
    gruppe(["Haus_Bauernhaus_HD"], os.path.join(PREVIEW, "nah_bauernhaus.png"), res=(1200, 900),
           hoehe=0.35)
    gruppe(["Haus_Fachwerk_HD"], os.path.join(PREVIEW, "nah_fachwerk.png"), res=(1000, 1000),
           hoehe=0.25, von_links=0.6)
    gruppe(["Haus_Bauernhaus_HD"], os.path.join(PREVIEW, "nah_bauernhaus_hinten.png"),
           res=(1200, 900), blick=(0.6, 1.0, 0.5))

main()
