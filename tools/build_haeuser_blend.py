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
# FUNDAMENT: alles, was auf z = 0 steht, reicht so tief in den Boden. CityBuilder setzt ein
# Haus auf die Gelaendehoehe seiner MITTE — am Hang schwebte die Talseite, und weil die
# Waende unten offen sind, sah man darunter durch.
FUNDAMENT = 1.6
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
    # Hochhaeuser und Industrie
    "glas_blau":    (0.38, 0.56, 0.70),
    "glas_gruen":   (0.38, 0.60, 0.56),
    "glas_dunkel":  (0.17, 0.24, 0.31),
    "kies":         (0.57, 0.56, 0.53),
    "asphalt":      (0.27, 0.27, 0.29),
    "signal_gelb":  (0.86, 0.66, 0.20),
    "signal_blau":  (0.20, 0.38, 0.66),
    # Garten und Hof
    "hecke":        (0.22, 0.38, 0.21),
    "erde":         (0.38, 0.28, 0.19),
    "beet":         (0.36, 0.52, 0.24),
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
        # GLAS UND FENSTER GLAENZEN: niedrige Rauheit + etwas Metall, dann spiegelt die Flaeche
        # im Spiel den Himmel und blitzt in der Sonne — matt (0.9) waren die Glasfassaden
        # stumpfe blaue Kisten und jedes Fenster ein schwarzes Loch.
        spiegel = key.startswith("glas") or key == "fenster"
        # (Metall nur 0.25: mit 0.45 schluckte die Spiegelung die Glasfarbe, die Tuerme
        # standen fast schwarz in der Stadt.)
        b.inputs["Roughness"].default_value = 0.2 if spiegel else 0.9
        b.inputs["Metallic"].default_value = (0.6 if key.startswith("metall")
                                              else 0.25 if spiegel else 0.0)
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
        # GESCHWUNGENE TRAUFE (Aufschiebling) der Satteldaecher: Anteil, um den der Ueberstand
        # flacher auslaeuft. Dorf- und Stadthaeuser setzen 0.55 — das gibt die weiche,
        # leicht geschweifte Dachlinie statt einer steifen Dreieckskante.
        self.schwung = 0.0

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
             dicke=None, details=True, schwung=None):
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
        sw = self.schwung if schwung is None else schwung
        if ins == 0.0 and sw > 0.0 and o >= 0.3:
            # Satteldach MIT SCHWUNG (Aufschiebling): Knick an der Wandlinie, der Ueberstand
            # laeuft flacher aus. Profil quer zum First: Traufe - Wandlinie - First - Wandlinie
            # - Traufe. Ueber den Waenden bleibt die Dachflaeche unveraendert (Gauben und
            # Kamine rechnen weiter mit h * (1 - |x| / hs)).
            zf = ze * (1.0 - sw)
            prof = [(-xe, zf), (-hs, 0.0), (0.0, h), (hs, 0.0), (xe, zf)]
            V = []
            for ly in (-ye, ye):
                V += [self._welt(info, (px, ly, pz + lift)) for px, pz in prof]
                V += [self._welt(info, (px, ly, pz + lift - t)) for px, pz in prof]
            F = [(0, 10, 15, 5), (4, 9, 19, 14)]                     # Traufkanten
            for k in range(4):
                F += [(k, k + 1, 10 + k + 1, 10 + k), (5 + k, 15 + k, 15 + k + 1, 5 + k + 1),
                      (k, 5 + k, 5 + k + 1, k + 1), (10 + k, 10 + k + 1, 15 + k + 1, 15 + k)]
        else:
            E = [(-xe, -ye, ze + lift), (xe, -ye, ze + lift), (xe, ye, ze + lift),
                 (-xe, ye, ze + lift)]
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
                      over=0.18, dicke=0.16, giebel=wk, details=False, schwung=0.0)
        else:
            self.dach(mitte[0], mitte[1], mitte[2], tiefe, breite, gh, info["key"], axis="x",
                      over=0.18, dicke=0.16, giebel=wk, details=False, schwung=0.0)
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
    def zyl(self, x, y, z, r0, r1, h, sides, key, cap_top=True, cap_bottom=False, achse="z",
            dreh=0.0):
        """dreh = Winkelversatz der Ecken. Mit dreh = pi/sides zeigt eine FLAECHE genau nach
        -y/+y/-x/+x (bei 4, 8, 12 ... Seiten) — noetig, um ein Feld (Tuer, Fenster) buendig
        aufzusetzen; ihr Abstand zur Mitte ist r * cos(pi/sides)."""
        sides = self.rund(sides)
        if dreh != 0.0 and self.hd:
            dreh *= 0.5                       # doppelte Seitenzahl -> halber Versatz
        V = []
        for i in range(sides):
            a = dreh + 2.0 * math.pi * i / sides
            V.append((math.cos(a) * r0, math.sin(a) * r0, 0.0))
        for i in range(sides):
            a = dreh + 2.0 * math.pi * i / sides
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
    def kegel(self, x, y, z, r, h, sides, key, dreh=0.0):
        sides = self.rund(sides)
        if dreh != 0.0 and self.hd:
            dreh *= 0.5
        V = []
        for i in range(sides):
            a = dreh + 2.0 * math.pi * i / sides
            V.append((x + math.cos(a) * r, y + math.sin(a) * r, z))
        V.append((x, y, z + h))
        self.add(V, [(i, (i + 1) % sides, sides) for i in range(sides)], key)

    # GEMALTER VERLAUF (Stil Zelda/Ghibli) als Vertexfarbe, die der Haus-Shader mit der
    # Materialfarbe multipliziert: Waende unten dunkler (Erdnaehe, Schmutz) und nach oben
    # heller, Daecher von der Traufe zum First heller. Glas und Fenster bleiben unveraendert.
    # Kostet nichts — die Flaechen sind dieselben, nur ihre Ecken tragen einen Faktor.
    def _verlauf(self, me):
        col = me.color_attributes.new("Color", 'FLOAT_COLOR', 'CORNER')
        zmax = max((v.co.z for v in me.vertices), default=1.0)
        wand_h = min(max(zmax, 3.0), 7.5)
        dz = [me.vertices[i].co.z for pl in me.polygons
              if self.mats[pl.material_index].startswith("dach") for i in pl.vertices]
        d0, d1 = (min(dz), max(dz)) if dz else (0.0, 1.0)
        for pl in me.polygons:
            key = self.mats[pl.material_index]
            for li in pl.loop_indices:
                z = me.vertices[me.loops[li].vertex_index].co.z
                if key.startswith(("glas", "fenster")):
                    k = 1.0
                elif key.startswith("dach"):
                    k = 0.84 + 0.16 * min(max((z - d0) / max(d1 - d0, 0.5), 0.0), 1.0)
                else:
                    t = min(max(z / wand_h, 0.0), 1.0)
                    k = 0.78 + 0.22 * (t * t * (3.0 - 2.0 * t))
                col.data[li].color = (k, k, k, 1.0)

    # --- GARTEN UND HOF (alles nur in der Nahstufe) -----------------------------------------
    # Die Fernstufe bleibt ohne Garten: ihr Umriss ist der Grundriss auf der Karte
    # (CityBuilder.karte_haeuser nimmt die Huelle des Fern-Meshes).
    def zaun(self, punkte, key="holz_hell", hoehe=1.0, abstand=2.2, geschlossen=False):
        """Zaun als Linienzug (x, y): Pfosten + zwei Riegel. Die Pfosten stehen auf z = 0 und
        reichen damit ueber das Fundament in den Boden (am Hang kein Schweben)."""
        if not self.hd:
            return
        pts = list(punkte) + ([punkte[0]] if geschlossen else [])
        for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
            n = max(1, int(round(math.hypot(x1 - x0, y1 - y0) / abstand)))
            for i in range(n):
                t = i / float(n)
                self.box(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, 0, 0.14, 0.14, hoehe, key)
            for z in (hoehe * 0.45, hoehe * 0.85):
                self.balken((x0, y0, z), (x1, y1, z), 0.06, 0.1, key)
        if not geschlossen:
            self.box(pts[-1][0], pts[-1][1], 0, 0.14, 0.14, hoehe, key)

    def hecke(self, x, y, sx, sy, h=1.2, key="hecke"):
        if self.hd:
            self.box(x, y, 0, sx, sy, h, key)

    def beet(self, x, y, sx, sy, reihen=3):
        """Gemuesebeet: Erdflaeche mit gruenen Reihen (laengs der laengeren Seite)."""
        if not self.hd:
            return
        self.box(x, y, 0, sx, sy, 0.18, "erde")
        for i in range(reihen):
            t = (i + 0.5) / reihen - 0.5
            if sx >= sy:
                self.box(x, y + t * sy, 0.18, sx * 0.9, sy / reihen * 0.45, 0.22, "beet")
            else:
                self.box(x + t * sx, y, 0.18, sx / reihen * 0.45, sy * 0.9, 0.22, "beet")

    def waescheleine(self, x0, x1, y, hoehe=1.9):
        """Zwei Pfosten, Leine, Waeschestuecke (zweiseitig) — laengs X."""
        if not self.hd:
            return
        for x in (x0, x1):
            self.box(x, y, 0, 0.1, 0.1, hoehe, "holz_hell")
        self.balken((x0, y, hoehe - 0.05), (x1, y, hoehe - 0.05), 0.03, 0.03, "metall_dunkel")
        farben = ("wand_weiss", "holz_blau", "wand_weiss", "dach_rot", "wand_creme")
        n = max(2, int((x1 - x0) / 0.9))
        for i in range(n):
            x = x0 + (x1 - x0) * (i + 0.5) / n
            self.feld((x, y, hoehe - 0.5), 0.6, 0.8 if i % 2 else 0.6, "-y", farben[i % 5],
                      eps=0.0, zweiseitig=True)

    def schirm(self, x, y, key="dach_rot"):
        """Biergartentisch mit Sonnenschirm und zwei Baenken."""
        if not self.hd:
            return
        self.zyl(x, y, 0, 0.55, 0.55, 0.75, 6, "holz_hell")
        self.zyl(x, y, 0.75, 0.05, 0.05, 1.5, 6, "holz_dunkel")
        self.kegel(x, y, 2.05, 1.5, 0.6, 8, key)
        for s in (-1, 1):
            self.box(x, y + s * 1.05, 0, 1.3, 0.3, 0.45, "holz_hell")

    def laterne(self, x, y, hoehe=3.4):
        if not self.hd:
            return
        self.zyl(x, y, 0, 0.09, 0.07, hoehe, 6, "metall_dunkel")
        self.box(x, y, hoehe, 0.36, 0.36, 0.42, "wand_weiss")
        self.spitze(x, y, hoehe + 0.42, 0.5, 0.5, 0.25, "metall_dunkel")

    def brunnen(self, x, y, r=1.4, dach=False):
        """Brunnen: Steinbecken mit Wasserflaeche; dach=True = Ziehbrunnen mit Galgen."""
        if not self.hd:
            return
        self.zyl(x, y, 0, r, r, 0.8, 8, "stein", cap_top=False)
        self.ring(x, y, 0.8, r, r - 0.3, 8, "stein")
        self.ring(x, y, 0.62, r - 0.3, 0.0, 8, "glas_blau")
        if dach:
            for s in (-1, 1):
                self.box(x + s * (r - 0.15), y, 0.8, 0.14, 0.14, 1.6, "holz_dunkel")
            self.dach(x, y, 2.4, 2 * r + 0.4, 1.2, 0.6, "dach_terra", axis="x", over=0.1,
                      dicke=0.12, giebel="holz_dunkel", details=False, schwung=0.0)
        else:
            self.zyl(x, y, 0.62, 0.22, 0.16, 1.1, 6, "stein")
            self.zyl(x, y, 1.72, 0.5, 0.5, 0.14, 8, "stein")

    def holzstapel(self, x, y, sx, sy, h=1.1):
        if self.hd:
            self.box(x, y, 0, sx, sy, h, "holz_hell")
            self.box(x, y, h, sx + 0.2, sy + 0.2, 0.08, "holz_dunkel")

    def heuballen(self, x, y, quer=False):
        if self.hd:
            if quer:
                self.zyl(x - 0.65, y, 0.7, 0.7, 0.7, 1.3, 8, "dach_stroh", cap_top=True,
                         cap_bottom=True, achse="y")
            else:
                self.zyl(x, y, 0, 0.75, 0.75, 1.2, 8, "dach_stroh")

    # --- Bausteine fuer Hochhaeuser und Industrie ------------------------------------------
    # Balken zwischen zwei Punkten in beliebiger Richtung (Foerderbruecke, Kranausleger,
    # Rohr, Strebe): geschlossener Quader, b = Breite quer, h = Hoehe.
    def balken(self, p0, p1, b, h, key):
        a, e = Vector(p0), Vector(p1)
        d = (e - a).normalized()
        seit = d.cross(Vector((0, 0, 1)))
        if seit.length < 1e-4:
            seit = Vector((1, 0, 0))
        seit.normalize()
        auf = seit.cross(d).normalized()
        V = []
        for pt in (a, e):
            for sx in (-0.5, 0.5):
                for sz in (-0.5, 0.5):
                    V.append(tuple(pt + seit * (sx * b) + auf * (sz * h)))
        self.add_koerper(V, [(0, 1, 3, 2), (4, 6, 7, 5), (0, 2, 6, 4), (1, 5, 7, 3),
                             (0, 4, 5, 1), (2, 3, 7, 6)], key)

    # Waagrechte Flaeche, zeigt nach OBEN (Dachbelag, Markierung, Spielfeld). `feld` kann nur
    # Wandflaechen: das "H" auf dem Krankenhaus-Helipad stand damit senkrecht wie ein Zaun.
    def boden(self, x, y, z, sx, sy, key, winkel=0.0):
        c, sn = math.cos(winkel), math.sin(winkel)
        pts = []
        for dx, dy in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)):
            px, py = dx * sx, dy * sy
            pts.append((x + px * c - py * sn, y + px * sn + py * c, z))
        self.add(self._nach(pts, (0, 0, 1)), [(0, 1, 2, 3)], key)

    # Kreisring bzw. Scheibe (ri = 0), nach oben oder unten; z_innen neigt den Ring
    # (Tribuene, Stadiondach).
    def ring(self, x, y, z, ra, ri, sides, key, z_innen=None, unten=False):
        sides = self.rund(sides)
        zi = z if z_innen is None else z_innen
        n = (0, 0, -1) if unten else (0, 0, 1)
        aussen = [(x + math.cos(2.0 * math.pi * i / sides) * ra,
                   y + math.sin(2.0 * math.pi * i / sides) * ra, z) for i in range(sides)]
        if ri <= 0.0:
            self.add(self._nach(aussen, n), [tuple(range(sides))], key)
            return
        innen = [(x + math.cos(2.0 * math.pi * i / sides) * ri,
                  y + math.sin(2.0 * math.pi * i / sides) * ri, zi) for i in range(sides)]
        for i in range(sides):
            j = (i + 1) % sides
            self.add(self._nach([aussen[i], aussen[j], innen[j], innen[i]], n), [(0, 1, 2, 3)],
                     key)

    # Rohr in Abschnitten wechselnder Farbe: rot-weisser Schornsteinkopf, Antennenmast.
    def ringel(self, x, y, z, r0, r1, h, sides, keys, teile):
        for i in range(teile):
            t0, t1 = i / float(teile), (i + 1) / float(teile)
            self.zyl(x, y, z + h * t0, r0 + (r1 - r0) * t0, r0 + (r1 - r0) * t1, h / teile, sides,
                     keys[i % len(keys)], cap_top=(i == teile - 1))

    # BOGENFELD auf einer Wand: Fenster, Tor oder Arkade mit Rund- oder Spitzbogen — EIN
    # Vieleck (3-5 Dreiecke). ctr = Mitte des umschreibenden Rechtecks wie bei `feld`.
    def bogen(self, ctr, w, h, facing, key, spitz=False, eps=0.04, seg=4):
        u, n = Bau.AX[facing]
        r = w * 0.5
        hb = min(r * (1.35 if spitz else 1.0), h * 0.6)
        zs = h - hb
        pts2 = [(-r, 0.0), (r, 0.0), (r, zs)]
        if spitz:
            pts2 += [(r * 0.55, zs + hb * 0.62), (0.0, h), (-r * 0.55, zs + hb * 0.62)]
        else:
            for k in range(1, seg):
                a = math.pi * k / seg
                pts2.append((r * math.cos(a), zs + hb * math.sin(a)))
        pts2.append((-r, zs))
        pts = [(ctr[0] + n[0] * eps + u[0] * px, ctr[1] + n[1] * eps + u[1] * px,
                ctr[2] - h * 0.5 + pz) for px, pz in pts2]
        self.add(self._nach(pts, n), [tuple(range(len(pts)))], key)

    # RUNDES FELD auf einer Wand: Zifferblatt, Rosette, Bullauge.
    def rundfeld(self, ctr, r, facing, key, eps=0.04, seiten=10):
        u, n = Bau.AX[facing]
        pts = []
        for k in range(seiten):
            a = 2.0 * math.pi * k / seiten
            pts.append((ctr[0] + n[0] * eps + u[0] * r * math.cos(a),
                        ctr[1] + n[1] * eps + u[1] * r * math.cos(a), ctr[2] + r * math.sin(a)))
        self.add(self._nach(pts, n), [tuple(range(seiten))], key)

    # KUPPEL / KUGEL: z = Hoehe des Kugelmittelpunkts. von = Startwinkel (0 = Aequator -> Halbkugel,
    # negativ = unter dem Aequator -> Radomkugel auf einem Sockel).
    def kuppel(self, x, y, z, r, sides, key, von=0.0, baender=3, dreh=0.0):
        for k in range(baender):
            a0 = von + (math.pi * 0.5 - von) * k / float(baender)
            a1 = von + (math.pi * 0.5 - von) * (k + 1) / float(baender)
            r0, z0, z1 = r * math.cos(a0), r * math.sin(a0), r * math.sin(a1)
            if k == baender - 1:
                self.kegel(x, y, z + z0, r0, z1 - z0, sides, key, dreh=dreh)
            else:
                self.zyl(x, y, z + z0, r0, r * math.cos(a1), z1 - z0, sides, key, cap_top=False,
                         dreh=dreh)

    # FLACHDACH MIT ATTIKA: Kranz um die Dachkante, innen der Belag (Kies/Asphalt). Ohne den
    # Kranz war ein Hochhaus oben einfach abgeschnitten. LOD: ein Gesimsquader + Belag darauf.
    def flachdach(self, x, y, z, sx, sy, key, hoehe=0.9, ueber=0.2, belag="kies"):
        ax, ay = sx + 2.0 * ueber, sy + 2.0 * ueber
        if not self.hd:
            self.box(x, y, z, ax, ay, hoehe, key)
            self.boden(x, y, z + hoehe + 0.03, ax - 0.9, ay - 0.9, belag)
            return
        d = 0.36
        self.box(x, y - ay * 0.5 + d * 0.5, z, ax, d, hoehe, key)
        self.box(x, y + ay * 0.5 - d * 0.5, z, ax, d, hoehe, key)
        self.box(x - ax * 0.5 + d * 0.5, y, z, d, ay - 2.0 * d, hoehe, key)
        self.box(x + ax * 0.5 - d * 0.5, y, z, d, ay - 2.0 * d, hoehe, key)
        self.boden(x, y, z + 0.06, ax - 2.0 * d, ay - 2.0 * d, belag)

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
        """Schmal (sx oder sy <= 1) = ein gerades Gelaender; sonst UMLAUFEND um das Rechteck.
        Die erste Fassung legte bei zwei grossen Massen den "Handlauf" als ganze PLATTE ueber
        die Flaeche — ueber dem Krankenhausdach schwebte so ein 30 x 16 m Deckel."""
        if not self.hd:
            return
        if min(sx, sy) > 1.0:
            for s in (-1, 1):
                self.gelaender(x, y + s * sy * 0.5, z, sx, 0.12, key, hoehe, n)
                self.gelaender(x + s * sx * 0.5, y, z, 0.12, sy, key, hoehe,
                               max(2, int(round(n * sy / sx))))
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
        """Schmal = eine Zinnenreihe; zwei grosse Masse = Kranz um das Rechteck (0.7 tief).
        Die erste Fassung zog die Zinnen dann als Balken quer ueber die ganze Plattform."""
        if not self.hd:
            return
        if min(sx, sy) > 3.5:
            for s in (-1, 1):
                self.zinnen(x, y + s * (sy * 0.5 - 0.35), z, sx, 0.7, key, n, hoehe)
                self.zinnen(x + s * (sx * 0.5 - 0.35), y, z, 0.7, sy, key,
                            max(2, int(round(n * sy / sx))), hoehe)
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
        # FUNDAMENT: jeder Eckpunkt auf z = 0 wandert FUNDAMENT tief in den Boden.
        verts = [(v[0], v[1], -FUNDAMENT if abs(v[2]) < 1e-5 else v[2]) for v in self.v]
        me.from_pydata(verts, [], [fc for fc, _ in self.f])
        me.update()
        for key in self.mats:
            me.materials.append(get_mat(key))
        for poly, (_, mi) in zip(me.polygons, self.f):
            poly.material_index = mi
        me.validate()
        self._verlauf(me)
        # WEICHE RUNDUNGEN: Flaechen, die flacher als 40 Grad aneinanderstossen, werden weich
        # schattiert — Tuerme, Silos, Kuppeln, Kuehlturm, Hallenbogen und Kegeldaecher sind
        # dann rund statt facettiert. Quader (90 Grad) und Dachfirste (ab 43 Grad) bleiben
        # hart. 40 Grad ist die Grenze: darueber wuerde der First flacher Daecher verschmiert.
        me.set_sharp_from_angle(angle=math.radians(40.0))
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
    b.schwung = 0.55
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
    # Hof (nur HD): Garten hinter dem Haus, Beete, Waescheleine, Holzstapel, Bank
    b.zaun([(-6.6, 4.0), (-6.6, 11.5), (6.6, 11.5), (6.6, 4.0)])
    b.beet(-3.4, 8.8, 4.0, 2.6)
    b.beet(2.2, 9.2, 3.0, 2.0, reihen=2)
    b.waescheleine(1.0, 5.6, 6.0)
    b.holzstapel(-4.2, 4.5, 2.4, 0.8)
    if b.hd:
        b.box(2.1, -4.5, 0, 1.8, 0.5, 0.45, "holz_hell")              # Bank


def fachwerkhaus(b):
    """Fachwerkhaus, GIEBEL zur Strasse, das Obergeschoss kragt vor. Das Fachwerk (Rahmen,
    Staender, Streben, Kehlbalken im Giebel) steht in beiden Stufen — es ist das Merkmal."""
    H = "holz_dunkel"
    b.schwung = 0.55
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
    b.hecke(-5.5, 0.0, 0.8, 7.0)
    b.zaun([(-4.9, 3.7), (-4.9, 9.0), (4.6, 9.0), (4.6, 3.7)])
    b.beet(0, 6.6, 5.0, 2.4)
    if b.hd:
        b.box(1.7, -4.25, 0, 1.6, 0.5, 0.45, "holz_hell")             # Bank
        b.zyl(3.6, -4.2, 0, 0.4, 0.4, 0.9, 8, "holz_dunkel")          # Regenfass


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
    # Vorgarten mit Luecke fuers Gartentor, Ziehbrunnen
    b.zaun([(-4.6, -2.7), (-4.6, -6.6), (0.6, -6.6)], hoehe=0.8)
    b.zaun([(2.4, -6.6), (4.6, -6.6), (4.6, -2.7)], hoehe=0.8)
    b.beet(-2.2, -4.9, 3.2, 1.6, reihen=2)
    b.brunnen(6.4, 1.0, r=0.9, dach=True)


def scheune(b):
    """Scheune: rote Bretterwaende, grosses Tor mit weissem Rahmen und Streben, Heuluken in den
    Giebeln, Lueftungsreiter auf dem First."""
    b.schwung = 0.55
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
    b.zaun([(-7.0, 4.5), (-7.0, 12.0), (5.0, 12.0), (5.0, 4.5)], hoehe=1.2, abstand=2.6)  # Koppel
    b.heuballen(8.7, -2.2)
    b.heuballen(8.7, 0.0)
    b.heuballen(10.4, -1.1, quer=True)
    if b.hd:                                                            # Leiterwagen
        b.box(-9.6, -1.5, 0.55, 3.4, 1.6, 0.6, "holz_hell", skip=())
        for dx in (-1.1, 1.1):
            for sy in (-1, 1):
                b.zyl(-9.6 + dx, -1.5 + sy * 0.86 - 0.06, 0.5, 0.5, 0.5, 0.12, 8, "holz_dunkel",
                      cap_top=True, cap_bottom=True, achse="y")
        b.balken((-7.9, -1.5, 0.7), (-6.4, -1.5, 0.35), 0.1, 0.1, "holz_dunkel")   # Deichsel


def stall(b):
    b.box(0, 0, 0, 10, 6, 2.9, "wand_taupe")
    b.pultdach(0, 0, 2.9, 10, 6, 1.3, "dach_schiefer")
    b.fenster_reihe("-y", -3.0, 0, 8.0, 1.9, 4, 1.0, 0.9)
    b.feld((3.6, -3.0, 1.1), 1.6, 2.2, "-y", "holz_hell")
    b.zaun([(5.0, -3.0), (11.0, -3.0), (11.0, 4.0), (5.0, 4.0)], hoehe=1.2, abstand=2.5)
    b.heuballen(9.2, 0.6)
    if b.hd:
        b.box(7.4, -2.4, 0, 2.0, 0.6, 0.5, "holz_dunkel")              # Trog


def silo(b):
    """Hofsilo: Stahlzylinder mit Kuppeldach, kleiner zweiter Silo, Schuppen, Foerderrohr."""
    b.zyl(0, 0, 0, 2.3, 2.3, 9.2, 10, "metall", cap_top=False)
    b.kuppel(0, 0, 9.2, 2.3, 10, "metall_dunkel", baender=2)
    b.zyl(0.4, 4.1, 0, 1.5, 1.5, 6.0, 8, "metall", cap_top=False)
    b.kuppel(0.4, 4.1, 6.0, 1.5, 8, "metall_dunkel", baender=2)
    b.box(3.9, 0, 0, 4.0, 5.0, 2.8, "wand_grau")
    b.pultdach(3.9, 0, 2.8, 4.0, 5.0, 0.9, "metall_dunkel")
    b.feld((3.9, -2.5, 1.2), 2.2, 2.2, "-y", "holz_dunkel")
    b.balken((0.0, 0.0, 11.3), (3.9, 0.6, 3.9), 0.35, 0.35, "metall_dunkel")   # Foerderrohr
    if b.hd:
        for z in (3.0, 6.2, 9.0):                                           # Ringanker
            b.zyl(0, 0, z, 2.38, 2.38, 0.26, 10, "metall_dunkel", cap_top=False)
        for z in (2.4, 5.2):
            b.zyl(0.4, 4.1, z, 1.56, 1.56, 0.22, 8, "metall_dunkel", cap_top=False)
        for i in range(9):                                                   # Steigleiter
            b.box(-2.38, 0, 0.6 + i * 1.0, 0.06, 0.6, 0.06, "metall_dunkel")
        for dy in (-0.3, 0.3):
            b.box(-2.42, dy, 0.4, 0.06, 0.06, 9.0, "metall_dunkel")
        b.box(-1.2, -2.4, 0.6, 1.0, 1.0, 1.8, "metall_dunkel")              # Auslauf


def wassermuehle(b):
    b.schwung = 0.55
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
    b.zaun([(4.5, 3.75), (4.5, 8.5), (-3.0, 8.5), (-3.0, 3.75)])
    b.beet(0.8, 6.2, 4.0, 2.2)
    b.holzstapel(5.1, 0.0, 0.8, 2.4)
    if b.hd:                                                            # Muehlgraben
        b.box(-5.9, 0, 0, 2.0, 9.6, 0.45, "stein")
        b.boden(-5.9, 0, 0.47, 1.3, 9.2, "glas_blau")
        for k in range(3):                                              # Mehlsaecke
            b.box(1.0 + k * 0.75, -4.2, 0, 0.6, 0.45, 0.75, "wand_creme")


def windmuehle(b):
    """Hollaenderwindmuehle: konischer Turm, Galerie, runde Haube mit Welle und Steert, vier
    Fluegel aus Rute + seitlich versetztem Gatter (ZWEISEITIG), Eingang als kleiner Vorbau
    (ein senkrechtes Tuerfeld schneidet die schraege Turmwand)."""
    b.zyl(0, 0, 0, 4.0, 2.7, 11.0, 10, "wand_weiss", cap_top=False)
    b.zyl(0, 0, 11.0, 2.95, 2.6, 1.0, 10, "holz_dunkel", cap_top=False)   # Haubenkranz
    b.kuppel(0, 0, 12.0, 2.6, 10, "dach_schiefer", baender=2)             # Haube
    b.zyl(0, 0, 5.2, 4.7, 4.7, 0.25, 10, "holz_dunkel")                   # Galerie
    b.balken((0, -2.0, 11.7), (0, -4.2, 11.3), 0.7, 0.7, "holz_dunkel")   # Welle
    b.balken((0, 2.2, 12.2), (0, 5.0, 9.4), 0.3, 0.3, "holz_dunkel")      # Steert
    for k in range(4):
        a = k * math.pi * 0.5 + 0.35
        ca, sa = math.cos(a), math.sin(a)
        b.feld((-3.7 * sa, -4.3, 11.3 + 3.7 * ca), 0.36, 7.4, "-y", "holz_dunkel", eps=0.0,
               winkel=a, zweiseitig=True)                                  # Rute
        gx, gz = 0.98 * ca - 4.5 * sa, 0.98 * sa + 4.5 * ca
        b.feld((gx, -4.25, 11.3 + gz), 1.6, 5.4, "-y", "holz_hell", eps=0.0, winkel=a,
               zweiseitig=True)                                            # Gatter
        if b.hd:
            for j in (-2.0, -0.7, 0.7, 2.0):                               # Scheiden
                hx, hz = 0.98 * ca - (4.5 + j) * sa, 0.98 * sa + (4.5 + j) * ca
                b.feld((hx, -4.2, 11.3 + hz), 1.7, 0.12, "-y", "holz_dunkel", eps=0.0, winkel=a,
                       zweiseitig=True)
    b.box(0, -3.9, 0, 1.9, 1.0, 2.7, "wand_weiss")                        # Eingangsvorbau
    b.feld((0, -4.4, 1.1), 1.1, 2.1, "-y", "holz_dunkel")
    if b.hd:
        for k in range(10):                                                # Galeriestreben
            a = 2.0 * math.pi * (k + 0.5) / 10.0
            ca, sa = math.cos(a), math.sin(a)
            b.balken((ca * 3.55, sa * 3.55, 3.4), (ca * 4.5, sa * 4.5, 5.2), 0.16, 0.16,
                     "holz_dunkel")
            b.balken((ca * 4.55, sa * 4.55, 5.45), (ca * 4.55, sa * 4.55, 6.3), 0.1, 0.1,
                     "holz_dunkel")
        b.zyl(0, 0, 6.25, 4.6, 4.6, 0.1, 10, "holz_dunkel", cap_top=False)   # Handlauf


def stadthaus2(b):
    """Buergerhaus, Giebel zur Strasse, zwei Vollgeschosse, Geschossgesims."""
    L = "holz_gruen"
    b.schwung = 0.55
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
    b.laterne(-5.4, -4.9)
    b.hecke(0, 9.0, 9.4, 0.4, h=1.6, key="stein")                       # Hofmauer
    for sx in (-1, 1):
        b.hecke(sx * 4.5, 6.5, 0.4, 5.0, h=1.6, key="stein")
    b.beet(-1.6, 6.6, 3.2, 2.2, reihen=2)
    b.holzstapel(3.2, 4.5, 1.8, 0.7)


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
    b.laterne(4.3, -5.5)
    b.hecke(0, 8.8, 7.0, 0.4, h=1.6, key="stein")
    for sx in (-1, 1):
        b.hecke(sx * 3.3, 6.65, 0.4, 4.3, h=1.6, key="stein")
    if b.hd:
        b.zyl(-2.4, 5.3, 0, 0.4, 0.4, 0.9, 8, "holz_dunkel")           # Regenfass


def reihenhaus(b):
    """Drei Reihenhaeuser unter einem Dach — je eigene Farbe, Tuer, Gaube, Kamin."""
    farben = ("wand_creme", "wand_mauve", "wand_blau")
    tueren = ("holz_rot", "holz_gruen", "holz_blau")
    for i, c in enumerate(farben):
        b.schwung = 0.55
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
    for i in range(3):                                                  # Vor- und Hintergaerten
        x = (i - 1) * 5.6
        b.zaun([(x - 2.7, -4.0), (x - 2.7, -6.4), (x - 2.1, -6.4)], hoehe=0.8)
        b.zaun([(x - 0.7, -6.4), (x + 2.7, -6.4), (x + 2.7, -4.0)], hoehe=0.8)
        b.hecke(x - 2.8, 7.5, 0.5, 7.0, h=1.3)
        b.beet(x + 0.4, 8.2, 3.2, 2.0, reihen=2)
    b.hecke(8.4, 7.5, 0.5, 7.0, h=1.3)
    b.waescheleine(-7.4, -4.6, 5.6)


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
    b.laterne(-7.4, -4.9)
    b.hecke(5.2, -4.0, 4.6, 0.4, h=1.1, key="stein")                    # Hofmauer im Winkel
    b.hecke(7.5, -2.0, 0.4, 4.4, h=1.1, key="stein")
    if b.hd:
        b.box(4.6, -0.5, 0, 1.6, 0.5, 0.45, "holz_hell")               # Bank im Hof


def gasthaus(b):
    """Gasthaus: Laube vor dem Erdgeschoss, zwei Gauben, zwei Kamine, Wirtshausschild."""
    L = "holz_gruen"
    b.schwung = 0.55
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
    # Biergarten neben dem Haus
    b.zaun([(6.0, -4.6), (14.4, -4.6), (14.4, 4.3), (6.0, 4.3)], hoehe=0.9)
    b.schirm(8.6, -2.2, "dach_rot")
    b.schirm(12.0, -2.2, "wand_weiss")
    b.schirm(8.6, 1.7, "wand_weiss")
    b.schirm(12.0, 1.7, "dach_rot")
    if b.hd:
        for k in range(2):                                              # Bierfaesser
            b.zyl(-6.7, -3.2 + k * 1.0, 0, 0.42, 0.42, 0.95, 8, "holz_dunkel")


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
    b.hecke(0, 13.6, 17.0, 0.9, h=1.6)                                  # Park hinter dem Haus
    for sx in (-1, 1):
        b.hecke(sx * 8.05, 9.4, 0.9, 9.3, h=1.6)
        b.beet(sx * 4.3, 9.4, 3.0, 3.0)
        b.laterne(sx * 5.2, -8.8)
    b.brunnen(0, 9.4, r=1.5)


def kirche(b):
    """Dorfkirche: Langhaus mit steilem Dach und Spitzbogenfenstern, Westturm mit Schalluken und
    Zifferblaettern auf drei Seiten, Kupferhelm mit vier Eckfialen, Apsis, Sakristei, Portal mit
    Rosette."""
    b.schwung = 0.4
    b.box(0, 2.0, 0, 11, 20, 8.6, "wand_creme")                           # Langhaus
    b.dach(0, 2.0, 8.6, 11, 20, 6.2, "dach_schiefer", axis="y", over=0.5)
    b.box(0, -10.0, 0, 6.6, 6.6, 19.0, "wand_creme")                      # Westturm
    b.box(0, -10.0, 19.0, 7.2, 7.2, 0.6, "stein")
    b.spitze(0, -10.0, 19.6, 6.4, 6.4, 11.0, "dach_kupfer")
    for ex in (-1, 1):                                                     # Eckfialen
        for ey in (-1, 1):
            b.spitze(ex * 2.9, -10.0 + ey * 2.9, 19.6, 1.3, 1.3, 3.4, "dach_kupfer")
    b.zyl(0, -10.0, 30.4, 0.16, 0.16, 1.9, 6, "metall")                   # Kreuz
    b.feld((0, -10.0, 31.6), 1.0, 0.2, "-y", "metall", eps=0.2, zweiseitig=True)
    b.zyl(0, 12.6, 0, 4.2, 4.2, 8.6, 8, "wand_creme", cap_top=False)      # Apsis
    b.kegel(0, 12.6, 8.6, 4.5, 3.6, 8, "dach_schiefer")
    for y in (-3.0, 2.0, 7.0):                                             # Spitzbogenfenster
        b.bogen((-5.5, y, 4.9), 1.4, 4.6, "-x", "glas_blau", spitz=True)
        b.bogen((5.5, y, 4.9), 1.4, 4.6, "+x", "glas_blau", spitz=True)
    for f, cx, cy in (("-y", 0.0, -13.3), ("-x", -3.3, -10.0), ("+x", 3.3, -10.0),
                      ("+y", 0.0, -6.7)):
        b.bogen((cx, cy, 16.4), 1.5, 2.8, f, "fenster")                    # Schalluken
        if f != "+y":
            b.rundfeld((cx, cy, 12.6), 1.2, f, "wand_weiss")               # Zifferblatt
            b.rundfeld((cx, cy, 12.6), 0.95, f, "fenster", eps=0.08)
    b.bogen((0, -13.3, 2.0), 2.7, 4.0, "-y", "stein", spitz=True, eps=0.03)   # Portal
    b.bogen((0, -13.3, 1.8), 2.0, 3.6, "-y", "holz_dunkel", spitz=True, eps=0.06)
    b.rundfeld((0, -13.3, 7.6), 1.1, "-y", "glas_blau")                    # Rosette
    b.box(7.2, 10.5, 0, 3.6, 5.0, 3.6, "wand_creme")                       # Sakristei
    b.dach(7.2, 10.5, 3.6, 3.6, 5.0, 1.8, "dach_schiefer", axis="x", over=0.25)
    b.feld((9.0, 10.5, 1.9), 1.0, 1.2, "+x", "fenster")


def kapelle(b):
    b.schwung = 0.55
    b.box(0, 0, 0, 5.4, 8, 4.2, "wand_weiss")
    b.dach(0, 0, 4.2, 5.4, 8, 2.8, "dach_terra", axis="y", over=0.4)
    b.box(0, -2.6, 6.2, 1.7, 1.7, 2.6, "wand_weiss")          # Dachreiter
    b.spitze(0, -2.6, 8.8, 1.9, 1.9, 2.6, "dach_kupfer")
    b.bogen((0, -4.0, 1.4), 1.3, 2.6, "-y", "holz_dunkel")
    b.rundfeld((0, -4.0, 4.9), 0.55, "-y", "glas_blau")
    b.bogen((0, -3.45, 7.5), 0.7, 1.1, "-y", "fenster")       # Glockenoeffnung
    for y in (-1.0, 2.0):
        b.bogen((-2.7, y, 2.5), 0.9, 2.4, "-x", "glas_blau", spitz=True)
        b.bogen((2.7, y, 2.5), 0.9, 2.4, "+x", "glas_blau", spitz=True)


def rathaus(b):
    """Rathaus: Arkaden im Erdgeschoss, hohe Fenster darueber, Balkon, Walmdach mit Gauben,
    Uhrturm mit Zifferblaettern auf drei Seiten, offener Glockenstube und Kupferhelm."""
    b.box(0, 0, 0, 15, 10, 8.4, "wand_sand")
    b.sockel(0, 0, 15, 10)
    d = b.dach(0, 0, 8.4, 15, 10, 3.6, "dach_schiefer", axis="x", inset=2.4, over=0.5)
    for u in (-3.9, 3.9):
        b.gaube(d, u, seite=1, breite=2.0, hoehe=1.3)
    b.box(0, -1.2, 0, 4.8, 4.8, 15.5, "wand_sand")                        # Uhrturm
    b.box(0, -1.2, 15.5, 5.4, 5.4, 0.5, "stein")
    b.box(0, -1.2, 16.0, 3.8, 3.8, 2.8, "wand_sand")                      # Glockenstube
    b.spitze(0, -1.2, 18.8, 4.4, 4.4, 4.6, "dach_kupfer")
    b.zyl(0, -1.2, 23.4, 0.12, 0.12, 1.6, 6, "metall")
    for f, cx, cy in (("-y", 0.0, -3.6), ("-x", -2.4, -1.2), ("+x", 2.4, -1.2)):
        b.rundfeld((cx, cy, 13.3), 1.15, f, "wand_weiss")                  # Uhr
        b.rundfeld((cx, cy, 13.3), 0.9, f, "fenster", eps=0.08)
    for f, cx, cy in (("-y", 0.0, -3.1), ("+y", 0.0, 0.7), ("-x", -1.9, -1.2), ("+x", 1.9, -1.2)):
        b.bogen((cx, cy, 17.3), 1.6, 2.0, f, "fenster")                    # Schalloeffnungen
    for x in (-6.0, -3.0, 3.0, 6.0):                                       # Arkaden
        b.bogen((x, -5.0, 2.1), 2.2, 3.6, "-y", "fenster")
        b.fenster((x, -5.0, 6.3), 1.3, 2.0, "-y")
    b.bogen((0, -5.0, 2.1), 2.4, 3.8, "-y", "holz_dunkel")                 # Portal
    b.fenster((0, -5.0, 6.3), 1.6, 2.2, "-y")
    b.box(0, -5.6, 4.5, 3.6, 1.2, 0.25, "stein")                          # Balkon
    b.box(0, -5.9, 0, 7.0, 1.8, 0.4, "stein", skip=())                    # Freitreppe
    for f, fx in (("-x", -7.5), ("+x", 7.5)):
        b.fenster_reihe(f, fx, 0, 6.0, 6.3, 2, 1.3, 2.0)
        b.fenster_reihe(f, fx, 0, 6.0, 2.4, 2, 1.3, 2.0)
    b.fenster_reihe("+y", 5.0, 0, 12.0, 6.3, 5, 1.3, 2.0)
    b.fenster_reihe("+y", 5.0, 0, 12.0, 2.4, 5, 1.3, 2.0)
    if b.hd:
        b.gelaender(0, -6.15, 4.75, 3.6, 0.12, "metall_dunkel", 0.9, 6)
        for x in (-7.3, -4.5, -1.5, 1.5, 4.5, 7.3):                        # Pilaster
            b.box(x, -5.0, 0.55, 0.5, 0.36, 7.85, "wand_weiss")
        b.box(0, -5.0, 4.4, 15.2, 0.4, 0.3, "wand_weiss")                  # Gurtgesims
        b.feld((0.9, -1.2, 24.5), 1.4, 0.9, "-y", "dach_rot", eps=0.0, zweiseitig=True)
    b.brunnen(0, -11.5, r=1.8)                                          # Marktbrunnen
    for sx in (-1, 1):
        b.laterne(sx * 5.6, -7.8)


def speicher(b):
    """Backsteinspeicher (vier Boeden): Giebel zur Strasse, Ladeluken mit Rundbogen uebereinander,
    Windenerker mit Ladebalken im Giebel, Fenster auf allen Seiten, Steinsockel, Dachgauben."""
    b.box(0, 0, 0, 10, 13, 11.0, "ziegel")
    b.box(0, 0, 0, 10.3, 13.3, 1.2, "stein")                              # Sockel
    d = b.dach(0, 0, 11.0, 10, 13, 5.0, "dach_schiefer", axis="y", over=0.3)
    for u in (-3.2, 3.2):
        for seite in (-1, 1):
            b.gaube(d, u, seite=seite, breite=1.8, hoehe=1.3, wand="ziegel")
    for z in (2.6, 5.6, 8.6):
        b.bogen((0, -6.5, z), 2.1, 2.6, "-y", "wand_weiss", eps=0.03)      # Ladeluken
        b.bogen((0, -6.5, z - 0.1), 1.6, 2.2, "-y", "holz_dunkel", eps=0.05)
        for x in (-3.2, 3.2):
            b.fenster((x, -6.5, z + 0.1), 1.1, 1.4, "-y")
        for f, fx in (("-x", -5.0), ("+x", 5.0)):
            b.fenster_reihe(f, fx, 0, 10.2, z + 0.1, 3, 1.1, 1.4)
        b.fenster_reihe("+y", 6.5, 0, 6.4, z + 0.1, 2, 1.1, 1.4)
    b.box(0, -6.95, 12.2, 2.2, 1.0, 2.2, "holz_dunkel", skip=())           # Windenerker
    b.dach(0, -6.95, 14.4, 2.2, 1.0, 0.9, "dach_schiefer", axis="y", over=0.2, dicke=0.14,
           giebel="holz_dunkel", details=False)
    b.balken((0, -7.3, 14.15), (0, -9.0, 14.15), 0.25, 0.25, "holz_dunkel")   # Ladebalken
    if b.hd:
        b.box(0, -8.8, 6.0, 0.06, 0.06, 8.1, "metall_dunkel")              # Seil
        b.box(0, -8.8, 5.6, 0.5, 0.5, 0.5, "holz_hell")                    # Ladung
        for ex in (-1, 1):                                                  # Ecklisenen
            for ey in (-1, 1):
                b.box(ex * 4.9, ey * 6.4, 1.2, 0.5, 0.5, 9.8, "ziegel_d")
        for z in (4.15, 7.15, 10.15):                                       # Geschossbaender
            b.box(0, 0, z, 10.14, 13.14, 0.18, "wand_weiss")


def werkstatt(b):
    """Werkstatt: Halle mit flachem Satteldach, zwei Rolltore, gelbes Schildband, Bueroanbau mit
    Flachdach, Abluftrohr. HD: Dachluefter, Paletten, Faesser, Reifenstapel, Lieferwagen."""
    b.box(0, 0, 0, 12, 8, 4.6, "wand_grau")
    b.dach(0, 0, 4.6, 12, 8, 1.7, "metall_dunkel", axis="x", over=0.35)
    for x in (-3.4, 1.4):
        b.feld((x, -4.0, 1.9), 3.8, 3.6, "-y", "metall")                   # Rolltore
    b.feld((-1.0, -4.0, 4.15), 9.0, 0.7, "-y", "signal_gelb", eps=0.05)    # Schildband
    b.fenster((4.6, -4.0, 2.4), 1.4, 1.4, "-y")
    b.fenster_reihe("+y", 4.0, 0, 10.0, 2.8, 4, 1.4, 1.2)
    b.fenster_reihe("+x", 6.0, 0, 5.0, 2.8, 2, 1.4, 1.2)
    b.zyl(4.6, 2.6, 4.2, 0.35, 0.35, 4.2, 6, "metall_dunkel")              # Abluftrohr
    b.box(-7.5, -0.8, 0, 3.0, 5.0, 3.2, "wand_creme")                      # Buero
    b.flachdach(-7.5, -0.8, 3.2, 3.0, 5.0, "wand_creme", hoehe=0.4)
    b.fenster((-7.5, -3.3, 1.9), 1.6, 1.2, "-y")
    b.tuer((-9.0, -0.8, 1.05), 1.0, 2.1, "-x", key="metall_dunkel")
    if b.hd:
        for x in (-3.4, 1.4):                                               # Rolltor-Lamellen
            for k in range(4):
                b.feld((x, -4.0, 0.7 + k * 0.85), 3.8, 0.1, "-y", "metall_dunkel", eps=0.06)
        for x in (-3.5, 0.0, 3.5):                                          # Dachluefter
            b.box(x, 1.2, 5.4, 1.2, 1.0, 0.8, "metall")
        b.zyl(4.6, 2.6, 8.4, 0.5, 0.5, 0.3, 6, "metall")                    # Kaminhut
        for k in range(3):                                                  # Paletten
            b.box(7.6, -2.8, k * 0.32, 1.3, 1.1, 0.24, "holz_hell", skip=())
        for x, y in ((7.2, 0.2), (8.1, 0.2), (7.65, 1.0)):                  # Faesser
            b.zyl(x, y, 0, 0.36, 0.36, 1.0, 8, "signal_blau")
        b.zyl(7.6, 2.6, 0, 0.55, 0.55, 0.9, 8, "metall_dunkel")             # Reifenstapel
        b.box(1.4, -7.4, 0.35, 2.0, 4.6, 1.9, "wand_weiss")                 # Lieferwagen
        b.box(1.4, -9.0, 0.35, 1.9, 1.4, 1.2, "wand_weiss")
        b.feld((1.4, -9.7, 1.25), 1.6, 0.6, "-y", "fenster", eps=0.02)


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
    """Kontrollturm: Betriebsgebaeude, achteckiger Schaft, Konsole mit Umgang, nach oben weiter
    werdende GLASKANZEL, Dach mit Radar, Antenne und Leuchtfeuer."""
    d8 = math.pi / 8.0
    b.box(0, 2.4, 0, 9.0, 7.0, 5.0, "beton")                              # Betriebsgebaeude
    b.flachdach(0, 2.4, 5.0, 9.0, 7.0, "beton", hoehe=0.5)
    for x in (-3.5, 3.5):
        b.fenster((x, -1.1, 1.9), 1.4, 1.2, "-y")
        b.fenster((x, -1.1, 3.9), 1.4, 1.0, "-y", bank=False)
    b.fenster_reihe("+y", 5.9, 0, 7.0, 3.0, 3, 1.4, 1.2)
    b.tuer((4.5, 2.4, 1.05), 1.1, 2.1, "+x", key="metall_dunkel", vordach="beton")
    b.zyl(0, 0, 0, 2.7, 2.3, 16.0, 8, "beton", cap_top=False, dreh=d8)   # Schaft
    b.zyl(0, 0, 15.4, 2.3, 4.7, 1.1, 8, "beton", cap_top=False, dreh=d8)  # Konsole
    b.zyl(0, 0, 16.5, 4.7, 4.7, 0.35, 8, "beton", dreh=d8)                # Umgang
    b.zyl(0, 0, 16.85, 3.3, 4.2, 3.0, 8, "glas_gruen", cap_top=False, dreh=d8)   # Kanzel
    b.zyl(0, 0, 19.85, 4.5, 4.3, 0.5, 8, "wand_weiss", dreh=d8)           # Dach
    b.zyl(1.8, 1.4, 20.35, 0.1, 0.1, 4.2, 6, "metall")                    # Antenne
    b.zyl(-1.2, -0.6, 20.35, 0.3, 0.3, 1.0, 6, "metall_dunkel")           # Radar
    b.box(-1.2, -0.6, 21.35, 3.2, 0.3, 0.8, "wand_weiss")
    b.box(1.4, -1.6, 20.35, 0.5, 0.5, 0.6, "dach_rot")                    # Leuchtfeuer
    k = math.cos(math.pi / (16.0 if b.hd else 8.0))    # Abstand der Flaeche nach -y
    for z in (6.5, 10.0, 13.2):                                            # Schaftfenster
        r = 2.7 - 0.4 * z / 16.0
        b.feld((0, -r * k, z), 0.7, 1.6, "-y", "fenster", eps=0.1)
    if b.hd:
        b.zyl(0, 0, 16.85, 4.62, 4.62, 1.0, 8, "metall_dunkel", cap_top=False, dreh=d8)  # Bruestung
        for i in range(8):                                                  # Kanzelpfosten
            a = d8 + 2.0 * math.pi * i / 8.0
            ca, sa = math.cos(a), math.sin(a)
            b.balken((ca * 3.3, sa * 3.3, 16.85), (ca * 4.2, sa * 4.2, 19.85), 0.18, 0.18,
                     "wand_weiss")
        _geraete(b, 5.0, ((-2.6, 4.0, 1.8, 1.4, 0.9), (2.6, 4.0, 1.8, 1.4, 0.9)))
        b.zyl(1.8, 1.4, 24.55, 0.18, 0.18, 0.25, 6, "dach_rot")


def tanklager(b):
    """Tanklager: zwei stehende Grosstanks (weiss, flaches Kegeldach) in einer Auffangwanne,
    zwei liegende Kessel, Pumpenhaus, Rohrleitungen."""
    b.box(0, -1.9, 0, 11.4, 19.4, 0.5, "beton", skip=())                 # Auffangwanne
    for y in (-6.7, 2.9):
        b.zyl(0, y, 0.5, 4.3, 4.3, 8.0, 12, "wand_weiss", cap_top=False)
        b.kegel(0, y, 8.5, 4.3, 0.9, 12, "metall")
    for x in (-3.0, 3.0):                                                 # liegende Kessel
        b.zyl(x, 13.6, 2.3, 1.3, 1.3, 5.2, 8, "metall", cap_top=True, cap_bottom=True, achse="y")
        for y in (9.6, 12.4):
            b.box(x, y, 0, 2.2, 0.7, 1.1, "beton")
    b.box(-4.4, -14.0, 0, 4.0, 3.6, 3.2, "wand_grau")                    # Pumpenhaus
    b.pultdach(-4.4, -14.0, 3.2, 4.0, 3.6, 0.7, "metall_dunkel")
    b.feld((-4.4, -15.8, 1.1), 1.2, 2.2, "-y", "metall_dunkel")
    b.balken((-4.4, -12.2, 1.2), (-4.4, 8.4, 1.2), 0.4, 0.4, "metall_dunkel")   # Sammelleitung
    if b.hd:
        for y in (-6.7, 2.9):
            b.zyl(0, y, 8.3, 4.4, 4.4, 0.3, 12, "metall_dunkel", cap_top=False)   # Randring
            b.zyl(0, y, 4.3, 4.36, 4.36, 0.2, 12, "metall_dunkel", cap_top=False)
            for k in range(11):                                           # Wendeltreppe
                a = 0.6 + k * 0.2
                b.box(math.cos(a) * 4.7, y + math.sin(a) * 4.7, 0.9 + k * 0.72, 0.8, 0.8, 0.12,
                      "metall_dunkel")
            b.balken((-4.4, y, 1.2), (-3.6, y, 1.2), 0.3, 0.3, "metall_dunkel")
        for s in (-1, 1):                                                  # Wannenrand
            b.box(s * 5.6, -1.9, 0.5, 0.25, 19.4, 0.6, "beton")
            b.box(0, -1.9 + s * 9.6, 0.5, 11.4, 0.25, 0.6, "beton")
        for x in (-3.0, 3.0):
            b.balken((x, 11.0, 3.4), (x, 11.0, 5.2), 0.2, 0.2, "metall")  # Entlueftung


def wasserturm(b):
    """Wasserturm: achteckiger Ziegelschaft, auskragender Behaelter mit Fensterband,
    Schieferhelm. (dreh = pi/8: eine Flaeche zeigt genau nach vorn, dort sitzt die Tuer.)"""
    d = math.pi / 8.0
    k = math.cos(d)
    b.zyl(0, 0, 0, 3.5, 2.9, 11.0, 8, "ziegel", cap_top=False, dreh=d)   # Schaft
    b.zyl(0, 0, 11.0, 2.9, 4.6, 1.7, 8, "ziegel", cap_top=False, dreh=d)  # Auskragung
    b.zyl(0, 0, 12.7, 4.6, 4.6, 4.6, 8, "wand_creme", dreh=d)            # Behaelter
    b.kegel(0, 0, 17.3, 5.0, 3.4, 8, "dach_schiefer", dreh=d)
    b.zyl(0, 0, 20.5, 0.12, 0.12, 2.0, 6, "metall")
    if not b.hd:
        b.feld((0, -3.5 * k + 0.1, 1.2), 1.3, 2.4, "-y", "holz_dunkel", eps=0.12)
        for f, n in (("-y", (0, -1)), ("+y", (0, 1)), ("-x", (-1, 0)), ("+x", (1, 0))):
            b.feld((n[0] * 4.6 * k, n[1] * 4.6 * k, 15.0), 2.2, 1.3, f, "fenster")
        return
    # HD hat 16 Seiten: die Flaeche nach -y liegt bei r*cos(pi/16)
    k2 = math.cos(math.pi / 16.0)
    b.feld((0, -3.5 * k2 + 0.16, 1.2), 1.1, 2.4, "-y", "holz_dunkel", eps=0.12)
    for f, n in (("-y", (0, -1)), ("+y", (0, 1)), ("-x", (-1, 0)), ("+x", (1, 0))):
        b.feld((n[0] * 4.6 * k2, n[1] * 4.6 * k2, 15.0), 1.5, 1.3, f, "fenster")
        b.feld((n[0] * 3.1 * k2, n[1] * 3.1 * k2, 6.5), 0.5, 1.3, f, "fenster", eps=0.05)
    b.zyl(0, 0, 12.5, 4.8, 4.8, 0.3, 8, "stein", cap_top=False, dreh=d)   # Gesimsring
    b.zyl(0, 0, 17.1, 4.85, 4.85, 0.25, 8, "stein", cap_top=False, dreh=d)
    b.zyl(0, 0, 0, 3.7, 3.6, 0.7, 8, "stein", cap_top=False, dreh=d)      # Sockel


def leuchtfeuer_haus(b):     # kleines Hafen-/Lotsenhaus mit Signalmast
    b.schwung = 0.55
    b.box(0, 0, 0, 7.5, 6, 3.6, "wand_weiss")
    b.sockel(0, 0, 7.5, 6)
    d = b.dach(0, 0, 3.6, 7.5, 6, 2.6, "dach_rot", axis="x", over=0.45)
    b.kamin(d, -2.0, -0.8)
    b.zyl(3.2, 1.6, 4.3, 0.14, 0.14, 7.5, 6, "metall")            # Signalmast
    for z in (8.2, 9.6):
        b.feld((3.2, 1.6, z), 1.6, 0.3, "-y", "dach_rot", eps=0.16, zweiseitig=True)
    b.fenster_reihe("-y", -3.0, 0.8, 4.4, 2.2, 2, 1.1, 1.2, laeden="holz_blau")
    b.tuer((-2.6, -3.0, 1.05), 1.1, 2.1, "-y", key="holz_blau", vordach="dach_rot")
    if b.hd:                                                            # Boot auf Boecken
        b.box(5.9, 0.4, 0.4, 1.3, 3.6, 0.55, "holz_blau", skip=())
        b.box(5.9, 0.4, 0.95, 0.9, 3.0, 0.2, "wand_weiss", skip=())
        for y in (-0.8, 1.6):
            b.box(5.9, y, 0, 1.5, 0.2, 0.4, "holz_dunkel")
    b.zaun([(-3.75, 3.0), (-3.75, 7.0), (3.75, 7.0), (3.75, 3.0)], hoehe=0.9)


# --- Hochhaeuser, Grossbauten & Sonderbauten ------------------------------------------------
def _baender(b, x, y, sx, sy, z0, dz, n, key="fenster", hoehe=1.6, rand=1.3,
             seiten=("-y", "+y", "-x", "+x"), sprossen=6, rahmen="wand_weiss"):
    """Fensterbaender: je Geschoss (ab z0, Abstand dz) und Fassade EIN Quad. HD: senkrechte
    Pfeilerstreifen ueber alle Geschosse (ein Quad je Achse) — zusammen ein Fensterraster,
    ohne ein einziges Einzelfenster zu bauen."""
    for i in range(n):
        z = z0 + i * dz
        for f in seiten:
            if f in ("-y", "+y"):
                b.feld((x, y + (sy * 0.5 if f == "+y" else -sy * 0.5), z), sx - rand * 2.0, hoehe,
                       f, key)
            else:
                b.feld((x + (sx * 0.5 if f == "+x" else -sx * 0.5), y, z), sy - rand * 2.0, hoehe,
                       f, key)
    if not b.hd or sprossen < 2:
        return
    zc = z0 + (n - 1) * dz * 0.5
    hh = (n - 1) * dz + hoehe + 0.3
    for f in seiten:
        br = (sx if f in ("-y", "+y") else sy) - rand * 2.0
        for k in range(1, sprossen):
            u = (k / float(sprossen) - 0.5) * br
            if f in ("-y", "+y"):
                ctr = (x + u, y + (sy * 0.5 if f == "+y" else -sy * 0.5), zc)
            else:
                ctr = (x + (sx * 0.5 if f == "+x" else -sx * 0.5), y + u, zc)
            b.feld(ctr, 0.24, hh, f, rahmen, eps=0.06)


def _geraete(b, z, liste):
    """Dachgeraete (nur HD): Klimakaesten mit dunklem Deckel. liste = (x, y, sx, sy, h)."""
    if not b.hd:
        return
    for x, y, sx, sy, h in liste:
        b.box(x, y, z, sx, sy, h, "metall")
        b.box(x, y, z + h, sx * 0.7, sy * 0.7, 0.12, "metall_dunkel")


def _auto(b, x, y, z, laengs_x, farbe):
    """Geparktes Auto (nur HD): Karosserie + Kabine."""
    sx, sy = (4.2, 1.8) if laengs_x else (1.8, 4.2)
    b.box(x, y, z, sx, sy, 0.75, farbe)
    b.box(x, y, z + 0.75, sx * (0.5 if laengs_x else 0.86), sy * (0.86 if laengs_x else 0.5), 0.55,
          "fenster")


def hochhaus_wohnturm(b):
    """Wohnhochhaus (40 m): heller Putz, Loggienachsen in Akzentfarbe vorn und hinten,
    Fensterraster an den Seiten, Dach mit Attika, Aufzugshaus, Wassertank und Antenne."""
    gh, n, z0 = 3.05, 12, 3.4
    z1 = z0 + n * gh                                                   # 40.0
    b.box(0, 0, 0, 14.6, 14.6, z0, "wand_grau")                        # Sockelgeschoss
    b.box(0, 0, z0, 14, 14, z1 - z0, "wand_weiss", skip=("bottom",))
    for s, f in ((-1, "-y"), (1, "+y")):
        fy = s * 7.0
        b.box(0, fy + s * 0.6, z0, 6.6, 1.2, z1 - z0, "wand_terra", skip=("bottom",))  # Loggien
        for i in range(n):
            z = z0 + i * gh + 1.75
            b.feld((0, fy + s * 1.2, z), 5.8, 1.7, f, "fenster")       # Loggia-Oeffnung
            for x in (-5.0, 5.0):
                b.feld((x, fy, z), 2.4, 1.5, f, "fenster")
            if b.hd:
                b.box(0, fy + s * 1.45, z - 1.55, 6.2, 0.5, 0.95, "wand_weiss")   # Bruestung
    _baender(b, 0, 0, 14, 14, z0 + 1.75, gh, n, hoehe=1.5, rand=1.6, seiten=("-x", "+x"),
             sprossen=4)
    b.flachdach(0, 0, z1, 14, 14, "wand_weiss")
    b.box(-3.2, 2.6, z1, 4.6, 4.6, 3.6, "wand_grau")                   # Aufzugshaus
    b.zyl(3.6, -3.0, z1, 1.3, 1.3, 3.0, 8, "metall")                    # Wassertank
    b.zyl(-3.2, 2.6, z1 + 3.6, 0.14, 0.14, 6.0, 6, "metall")           # Antenne
    b.feld((0, -7.3, 1.7), 4.2, 2.8, "-y", "glas_blau")                 # Eingang
    b.box(0, -8.3, 3.0, 5.4, 2.0, 0.28, "wand_weiss")                   # Vordach
    _geraete(b, z1, ((3.8, 3.6, 2.0, 1.6, 1.1), (0.6, -4.4, 1.6, 1.4, 0.9)))
    if b.hd:
        b.feld((-3.2, 0.3, z1 + 1.3), 1.0, 2.0, "-y", "metall_dunkel")  # Tuer Aufzugshaus


def hochhaus_buero(b):
    """Buerohochhaus (52 m): zwei verschraenkte GLASSCHEIBEN unterschiedlicher Hoehe auf einem
    Steinsockel, helle Geschossbaender, Technikkrone mit Mast."""
    b.box(0, 0, 0, 19.0, 16.0, 7.0, "stein")                           # Sockel
    b.feld((0, -8.0, 3.3), 10.0, 5.0, "-y", "glas_blau")                # Lobby
    b.box(0, -8.9, 5.9, 11.0, 1.8, 0.3, "metall")                       # Vordach
    scheiben = (((-2.5, 0.0, 12.0, 14.0, 7.0, 52.0), "glas_blau"),
                ((5.5, 0.0, 6.0, 10.5, 7.0, 43.0), "glas_dunkel"))
    schritt = 4.0 if b.hd else 12.0
    for (x, y, sx, sy, za, zb), glas in scheiben:
        b.box(x, y, za, sx, sy, zb - za, glas, skip=("bottom",))
        seiten = (("-y", (x, y - sy * 0.5), sx), ("+y", (x, y + sy * 0.5), sx),
                  ("-x", (x - sx * 0.5, y), sy), ("+x", (x + sx * 0.5, y), sy))
        z = za + schritt
        while z < zb - 1.0:                                              # Geschossbaender
            for f, (cx, cy), br in seiten:
                b.feld((cx, cy, z), br, 0.45, f, "metall")
            z += schritt
        if b.hd:                                                          # Pfosten
            for f, (cx, cy), br in seiten:
                for k in range(1, 4):
                    u = (k / 4.0 - 0.5) * br
                    ctr = (cx + u, cy, (za + zb) * 0.5) if f in ("-y", "+y") else \
                        (cx, cy + u, (za + zb) * 0.5)
                    b.feld(ctr, 0.16, zb - za, f, "metall", eps=0.05)
    b.box(-2.5, 0, 52.0, 12.6, 14.6, 1.0, "metall")                     # Krone
    b.box(-2.5, 0.5, 53.0, 7.0, 8.0, 3.0, "metall_dunkel")              # Technikgeschoss
    b.zyl(-2.5, 0.5, 56.0, 0.28, 0.08, 11.0, 6, "metall")               # Mast
    b.flachdach(5.5, 0, 43.0, 6.0, 10.5, "metall")
    _geraete(b, 43.0, ((6.0, 2.6, 2.2, 1.8, 1.2), (6.0, -2.4, 2.2, 1.8, 1.2)))
    if b.hd:
        for f, fy in (("-y", -3.5), ("+y", 4.5)):                        # Lamellen am Technikgeschoss
            for z in (53.6, 54.5, 55.4):
                b.feld((-2.5, fy, z), 6.4, 0.3, f, "metall", eps=0.05)


def wolkenkratzer(b):
    """Art-Deco-Turm (92 m): heller Stein, drei Ruecksprünge mit Gesims, SENKRECHTE
    Fensterachsen (ein Quad je Achse), kupferne Krone, Nadel."""
    S = "wand_sand"
    for w, z0, z1 in ((22.0, 0.0, 30.0), (17.0, 30.0, 56.0), (12.0, 56.0, 74.0),
                      (8.0, 74.0, 81.0)):
        b.box(0, 0, z0, w, w, z1 - z0, S, skip=("bottom",))
        b.box(0, 0, z1 - 0.7, w + 0.8, w + 0.8, 0.7, "stein")           # Gesims
        n = max(2, int(w // 3.6))
        if z0 == 0.0:
            hh, zc = z1 - 10.0, 8.0 + (z1 - 10.0) * 0.5
        else:
            hh, zc = z1 - z0 - 4.0, z0 + 2.0 + (z1 - z0 - 4.0) * 0.5
        for f, sg, quer in (("-y", -1, False), ("+y", 1, False), ("-x", -1, True),
                            ("+x", 1, True)):
            for i in range(n):
                u = ((i + 0.5) / n - 0.5) * (w - 2.4)
                ctr = (sg * w * 0.5, u, zc) if quer else (u, sg * w * 0.5, zc)
                b.feld(ctr, 1.5, hh, f, "fenster")
            if b.hd:                                    # Bruestungen quer ueber die Achsen
                k = max(2, int(hh // 3.3))
                for j in range(1, k):
                    zz = zc - hh * 0.5 + j * hh / k
                    ctr = (sg * w * 0.5, 0, zz) if quer else (0, sg * w * 0.5, zz)
                    b.feld(ctr, w - 1.8, 0.9, f, S, eps=0.06)
        if b.hd:                                        # Eckpfeiler
            for ex in (-1, 1):
                for ey in (-1, 1):
                    b.box(ex * (w * 0.5 - 0.3), ey * (w * 0.5 - 0.3), z0, 1.0, 1.0,
                          z1 - z0 - 0.7, "stein")
    b.spitze(0, 0, 81.0, 8.6, 8.6, 7.0, "dach_kupfer")                  # Krone
    b.zyl(0, 0, 87.6, 0.4, 0.1, 11.0, 6, "metall")                       # Nadel
    b.feld((0, -11.0, 4.2), 6.0, 7.4, "-y", "glas_blau", eps=0.07)       # Portal
    b.box(0, -11.8, 8.0, 8.0, 1.8, 0.4, "stein")
    if b.hd:
        for ex in (-1, 1):                              # Fialen auf dem dritten Ruecksprung
            for ey in (-1, 1):
                b.spitze(ex * 5.4, ey * 5.4, 74.0, 1.2, 1.2, 3.0, "dach_kupfer")
        b.feld((0, 0, 97.0), 1.8, 1.1, "-y", "dach_rot", eps=0.1, zweiseitig=True)


def plattenbau(b):
    """Plattenbau (6 Geschosse, 44 m lang): Fensterbaender, farbige Bruestungsbaender, drei
    verglaste Treppenhaus-Risalite mit Eingang, Aufzugshaeuser auf dem Dach. HD: Balkone."""
    b.box(0, 0, 0, 44, 12, 19.0, "beton")
    for i in range(6):
        z = 2.0 + i * 2.9
        b.feld((0, -6.0, z), 42.0, 1.5, "-y", "fenster")
        b.feld((0, 6.0, z), 42.0, 1.5, "+y", "fenster")
        for f, fx in (("-x", -22.0), ("+x", 22.0)):
            b.feld((fx, 0, z), 7.0, 1.5, f, "fenster")
        farbe = "wand_blau" if i % 2 else "wand_ocker"
        if b.hd:
            b.box(0, -6.55, z - 1.55, 42.0, 1.1, 0.2, "wand_grau")      # Balkonplatte
            b.box(0, -7.0, z - 1.35, 42.0, 0.14, 0.95, farbe)           # Bruestung
        else:
            b.feld((0, -6.0, z - 1.1), 42.0, 0.8, "-y", farbe, eps=0.06)
    for x in (-15.0, 0.0, 15.0):
        b.box(x, -6.7, 0, 3.4, 1.8, 19.6, "wand_weiss")                 # Treppenhaus-Risalit
        b.feld((x, -7.6, 11.0), 1.4, 15.0, "-y", "glas_blau")
        b.tuer((x, -7.6, 1.2), 1.8, 2.4, "-y", key="metall_dunkel", vordach="beton")
        b.box(x, 2.6, 19.0, 3.4, 3.4, 2.8, "wand_grau")                 # Aufzugshaus
    b.flachdach(0, 0, 19.0, 44, 12, "beton")
    if b.hd:
        for x in (-21.0, -10.0, -5.0, 5.0, 10.0, 21.0):                  # Balkon-Trennwaende
            b.box(x, -6.55, 0.45, 0.14, 1.1, 17.6, "wand_weiss")
        for x in (-7.5, 7.5):                                            # Plattenfugen hinten
            b.feld((x, 6.0, 9.5), 0.2, 19.0, "+y", "wand_grau", eps=0.06)


def hotel(b):
    """Hotel (27 m): Steinsockel mit Vorfahrt, sechs Zimmergeschosse mit Balkonbaendern,
    zurueckgesetztes Penthouse mit auskragendem Dach, Leuchtschrift auf der Attika."""
    b.box(0, 0, 0, 24.6, 15.6, 4.6, "stein")
    b.box(0, 0, 4.6, 24, 15, 19.4, "wand_creme", skip=("bottom",))
    for i in range(6):
        z = 6.3 + i * 3.1
        for s, f in ((-1, "-y"), (1, "+y")):
            b.feld((0, s * 7.5, z), 21.6, 1.7, f, "fenster")
            if b.hd:
                b.box(0, s * 8.0, z - 1.55, 21.6, 1.0, 0.18, "wand_weiss")     # Balkonplatte
                b.box(0, s * 8.45, z - 1.37, 21.6, 0.1, 0.9, "glas_blau")      # Glasbruestung
            else:
                b.feld((0, s * 7.5, z - 1.15), 21.6, 0.7, f, "wand_weiss", eps=0.06)
        for s, f in ((-1, "-x"), (1, "+x")):
            b.feld((s * 12.0, 0, z), 11.0, 1.6, f, "fenster")
    b.flachdach(0, 0, 24.0, 24, 15, "wand_creme")
    b.box(0, 1.2, 24.0, 15.0, 8.0, 3.4, "wand_weiss")                   # Penthouse
    b.feld((0, -2.8, 25.8), 13.0, 2.2, "-y", "glas_blau")
    b.box(0, 0.8, 27.4, 17.0, 10.0, 0.35, "wand_weiss")                 # auskragendes Dach
    b.box(0, -7.4, 24.9, 11.0, 0.4, 1.9, "dach_rot")                    # Leuchtschrift
    b.box(0, -9.4, 3.6, 12.0, 3.6, 0.35, "wand_weiss")                  # Vorfahrt-Vordach
    for x in (-5.0, 5.0):
        b.box(x, -10.8, 0, 0.4, 0.4, 3.6, "metall")
    b.feld((0, -7.8, 2.0), 8.0, 3.4, "-y", "glas_blau")
    _geraete(b, 24.0, ((9.6, 4.6, 2.2, 1.8, 1.1), (-9.6, 4.6, 2.2, 1.8, 1.1)))
    if b.hd:
        for x in (-10.8, -5.4, 0.0, 5.4, 10.8):                          # Balkon-Trennwaende
            for s in (-1, 1):
                b.box(x, s * 8.0, 4.75, 0.12, 1.0, 18.3, "wand_weiss")


def kaufhaus(b):
    """Kaufhaus: Schaufensterfront mit Markise, Fensterband im Obergeschoss, Schriftzug ueber der
    Attika, PARKDECK auf dem Dach mit Auffahrtsrampe (HD: geparkte Autos)."""
    b.box(0, 0, 0, 28, 20, 11.5, "wand_taupe")
    b.feld((0, -10.0, 2.5), 25.0, 4.2, "-y", "glas_blau")               # Schaufenster
    for s, f in ((-1, "-x"), (1, "+x")):
        b.feld((s * 14.0, -3.0, 2.5), 12.0, 4.2, f, "glas_blau")
        b.feld((s * 14.0, 0, 8.4), 17.0, 2.6, f, "fenster")
    b.box(0, -10.9, 4.8, 26.0, 1.8, 0.3, "dach_rot")                    # Markise
    b.feld((0, -10.0, 8.4), 25.0, 2.6, "-y", "fenster")
    b.feld((0, 10.0, 8.4), 25.0, 2.6, "+y", "fenster")
    b.box(0, -10.2, 12.4, 14.0, 0.5, 2.0, "dach_rot")                   # Schriftzug
    b.flachdach(0, 0, 11.5, 28, 20, "wand_taupe", belag="asphalt")
    b.box(9.5, 6.0, 11.5, 5.0, 5.0, 3.2, "wand_grau")                   # Treppenhaus
    b.balken((15.7, 8.5, 0.0), (15.7, -7.5, 11.6), 3.2, 0.5, "beton")   # Auffahrtsrampe
    b.box(15.7, 9.2, 0, 3.2, 1.4, 0.5, "beton")
    if b.hd:
        for x in (-12.5, -6.25, 0.0, 6.25, 12.5):                        # Schaufensterpfeiler
            b.box(x, -10.0, 0, 0.6, 0.5, 11.5, "wand_weiss")
        farben = ("dach_rot", "signal_blau", "wand_weiss", "signal_gelb", "metall_dunkel")
        k = 0
        for y in (-6.0, 1.5):                                            # geparkte Autos
            for x in (-11.0, -7.6, -4.2, -0.8, 2.6):
                if (k * 7) % 5 != 3:
                    _auto(b, x, y, 11.56, False, farben[k % 5])
                k += 1
        for x in (-12.7, -9.3, -5.9, -2.5, 0.9, 4.3):                    # Parkstreifen
            b.boden(x, -2.2, 11.58, 0.14, 12.5, "wand_weiss")


def parkhaus(b):
    """Parkhaus: fuenf offene Decks auf Stuetzen, Bruestungsbaender, Treppenturm, P-Schild.
    HD: Gelaender, Rampen, geparkte Autos auf dem obersten Deck."""
    for i in range(5):                                        # offene Decks
        b.box(0, 0, i * 3.3, 26, 18, 0.4, "beton", skip=())
    for x in (-11.5, 0.0, 11.5):                              # Stuetzen
        for y in (-8.0, 8.0):
            b.box(x, y, 0, 0.8, 0.8, 13.2, "beton", skip=("top", "bottom"))
    for i in range(4):                                        # Bruestungsbaender
        z = i * 3.3 + 2.6
        b.feld((0, -9.0, z), 25.0, 0.9, "-y", "metall_dunkel")
        b.feld((0, 9.0, z), 25.0, 0.9, "+y", "metall_dunkel")
    b.boden(0, 0, 13.63, 25.0, 17.0, "asphalt")
    b.box(-10.0, 7.0, 0, 4.4, 4.4, 17.0, "wand_grau")         # Treppenturm (durchgehend)
    b.feld((-10.0, 4.8, 8.5), 1.6, 15.0, "-y", "glas_blau")
    b.feld((0, -9.0, 1.4), 5.0, 2.6, "-y", "metall_dunkel")   # Einfahrt
    b.box(13.3, -7.0, 9.6, 0.3, 2.6, 2.6, "signal_blau")      # P-Schild
    b.feld((13.45, -7.0, 10.9), 1.5, 1.5, "+x", "wand_weiss", eps=0.02)
    if b.hd:
        for i in range(5):                                     # Gelaender je Deck
            z = i * 3.3 + 0.4
            if i < 4:
                b.gelaender(0, -9.0, z, 26.0, 0.3, "metall_dunkel", 1.05, 16)
                b.gelaender(0, 9.0, z, 26.0, 0.3, "metall_dunkel", 1.05, 16)
            b.gelaender(-13.0, 0, z, 0.3, 18.0, "metall_dunkel", 1.05, 11)
            b.gelaender(13.0, 0, z, 0.3, 18.0, "metall_dunkel", 1.05, 11)
        b.gelaender(0, -9.0, 13.6, 26.0, 0.3, "metall_dunkel", 1.05, 16)
        b.gelaender(0, 9.0, 13.6, 26.0, 0.3, "metall_dunkel", 1.05, 16)
        for i in range(4):                                     # Rampen zwischen den Decks
            b.balken((4.0, -4.0 + (i % 2) * 2.6, i * 3.3 + 0.4),
                     (12.0, -4.0 + (i % 2) * 2.6, (i + 1) * 3.3 + 0.4), 2.4, 0.3, "beton")
        farben = ("dach_rot", "signal_blau", "wand_weiss", "signal_gelb", "metall_dunkel")
        k = 0
        for y in (-5.5, 5.0):
            for x in (-6.0, -2.8, 0.4, 3.6, 6.8, 10.0):
                if (k * 3) % 4 != 1:
                    _auto(b, x, y, 13.66, False, farben[k % 5])
                k += 1
        for x in (-9.0, 9.0):                                  # Lichtmasten
            b.zyl(x, 0, 13.6, 0.14, 0.14, 3.4, 6, "metall_dunkel")


def krankenhaus(b):
    """Krankenhaus: weisser Riegel mit Fensterraster, Dach mit Attika, HELIPAD auf eigener
    Plattform (Ring und H liegen flach), Aufzugsturm mit rotem Kreuz, Notaufnahme mit Vordach."""
    b.box(0, 0, 0, 30, 16, 22.0, "wand_weiss")
    _baender(b, 0, 0, 30, 16, 3.4, 3.2, 6, hoehe=1.6, rand=1.4, sprossen=8)
    b.flachdach(0, 0, 22.0, 30, 16, "wand_weiss")
    b.zyl(-7.0, 0, 22.0, 6.4, 6.4, 1.4, 12, "beton")                    # Helipad-Plattform
    b.ring(-7.0, 0, 23.43, 5.6, 5.0, 12, "wand_weiss")
    for dx in (-1.0, 1.0):
        b.boden(-7.0 + dx, 0, 23.44, 0.6, 3.0, "wand_weiss")           # das H, FLACH
    b.boden(-7.0, 0, 23.44, 2.0, 0.6, "wand_weiss")
    b.box(9.5, 1.0, 22.0, 7.0, 7.0, 5.0, "wand_grau")                   # Aufzugsturm
    b.feld((9.5, -2.5, 24.7), 3.8, 3.8, "-y", "wand_weiss", eps=0.05)
    b.feld((9.5, -2.5, 24.7), 2.8, 0.9, "-y", "dach_rot", eps=0.08)     # rotes Kreuz
    b.feld((9.5, -2.5, 24.7), 0.9, 2.8, "-y", "dach_rot", eps=0.08)
    b.box(-11.0, -9.5, 0, 8.0, 5.0, 5.0, "wand_weiss")                  # Notaufnahme
    b.flachdach(-11.0, -9.5, 5.0, 8.0, 5.0, "wand_weiss", hoehe=0.5)
    b.box(-11.0, -12.9, 3.4, 6.4, 1.8, 0.3, "dach_rot")                 # Vordach
    b.feld((-11.0, -12.0, 1.7), 3.4, 3.0, "-y", "glas_blau")
    b.feld((6.0, -8.0, 1.8), 6.0, 3.2, "-y", "glas_blau", eps=0.07)     # Haupteingang
    b.box(6.0, -8.9, 3.6, 7.4, 1.8, 0.3, "wand_grau")
    _geraete(b, 22.0, ((3.0, 4.6, 2.4, 1.8, 1.2), (3.0, -4.6, 2.4, 1.8, 1.2),
                       (12.5, -5.0, 2.0, 1.6, 1.0)))


def bahnhof(b):
    """Bahnhof: Empfangsgebaeude mit Mittelbau (Giebel, Uhr, drei Bogenportale), Fluegel mit hohen
    Bogenfenstern, Vordach; dahinter Bahnsteig mit Bahnsteigdach auf Stuetzen und zwei Gleise im
    Schotterbett."""
    b.box(0, 0, 0, 30, 12, 9.0, "wand_sand")
    b.sockel(0, 0, 30, 12)
    b.dach(0, 0, 9.0, 30, 12, 3.2, "dach_schiefer", axis="x", inset=3.4, over=0.6)
    b.box(0, -1.0, 0, 9.0, 12.6, 13.5, "wand_sand")                       # Mittelbau
    b.dach(0, -1.0, 13.5, 9.0, 12.6, 3.0, "dach_schiefer", axis="y", over=0.5)
    b.rundfeld((0, -7.3, 11.6), 1.3, "-y", "wand_weiss")                   # Bahnhofsuhr
    b.rundfeld((0, -7.3, 11.6), 1.05, "-y", "fenster", eps=0.08)
    for x in (-2.8, 0.0, 2.8):
        b.bogen((x, -7.3, 2.3), 2.0, 4.4, "-y", "glas_blau")               # Portale
        b.fenster((x, -7.3, 7.6), 1.2, 1.8, "-y")
    for x in (-12.0, -8.0, 8.0, 12.0):
        b.bogen((x, -6.0, 4.2), 1.8, 4.6, "-y", "glas_blau")               # Fluegelfenster
        b.bogen((x, 6.0, 4.2), 1.8, 4.6, "+y", "glas_blau")
    for f, fx in (("-x", -15.0), ("+x", 15.0)):
        b.fenster_reihe(f, fx, 0, 7.0, 4.6, 2, 1.4, 2.4)
    b.box(0, -8.7, 5.2, 9.6, 2.8, 0.25, "metall_dunkel")                  # Vordach
    for x in (-4.4, 4.4):
        b.box(x, -9.8, 0, 0.25, 0.25, 5.2, "metall_dunkel")
    b.box(0, 9.0, 0, 34, 5.0, 0.9, "beton", skip=())                      # Bahnsteig
    b.dach(0, 9.0, 4.9, 34, 5.0, 1.0, "metall_dunkel", axis="x", over=0.4, dicke=0.18,
           giebel="metall_dunkel", details=False)
    for x in (-14.0, -7.0, 0.0, 7.0, 14.0):
        b.box(x, 9.0, 0.9, 0.35, 0.35, 4.0, "metall", skip=("top", "bottom"))
    b.box(0, 15.6, 0, 38, 6.6, 0.3, "kies", skip=())                      # Schotterbett
    for y in (13.5, 14.95, 16.25, 17.7):
        b.box(0, y, 0.3, 38, 0.16, 0.18, "metall_dunkel")                 # Schienen
    if b.hd:
        for gy in (14.225, 16.975):                                         # Schwellen
            for i in range(25):
                b.box(-18.0 + i * 1.5, gy, 0.3, 0.3, 2.3, 0.1, "holz_dunkel")
        b.box(0, -6.2, 5.6, 30.0, 0.5, 0.35, "wand_weiss")                  # Gurtgesims
        for x in (-10.5, 10.5):                                             # Baenke, Lampen
            b.box(x, 9.0, 0.9, 2.2, 0.6, 0.5, "holz_hell")
            b.zyl(x * 1.5, 11.0, 0.9, 0.08, 0.08, 3.0, 6, "metall_dunkel")
        b.feld((0, -7.3, 11.6), 0.1, 0.9, "-y", "wand_weiss", eps=0.12, winkel=0.5)   # Zeiger
        b.feld((0, -7.3, 11.6), 0.1, 0.6, "-y", "wand_weiss", eps=0.12, winkel=-1.3)
    for sx in (-1, 1):
        b.laterne(sx * 8.0, -9.6)
        b.laterne(sx * 13.0, -7.4)


def fabrik(b):
    """Fabrik: Ziegelhalle mit SHEDDACH (Glas nach Norden, Blech nach Sueden), Verwaltungsbau,
    Laderampe mit Rolltoren, hohe Hallenfenster, frei stehender Schornstein."""
    b.box(0, 0, 0, 30, 18, 8.0, "ziegel", skip=("bottom", "top"))
    for i in range(4):
        x0 = -15.0 + i * 7.5
        x1 = x0 + 7.5
        b.add(b._nach([(x0, -9, 8.0), (x0, 9, 8.0), (x0, 9, 11.0), (x0, -9, 11.0)], (-1, 0, 0)),
              [(0, 1, 2, 3)], "glas_blau")                               # Oberlicht
        b.add(b._nach([(x0, -9, 11.0), (x0, 9, 11.0), (x1, 9, 8.0), (x1, -9, 8.0)], (0.4, 0, 1)),
              [(0, 1, 2, 3)], "metall_dunkel")                           # Blechdach
        for s in (-1, 1):                                                # Giebeldreiecke
            b.add(b._nach([(x0, s * 9, 8.0), (x1, s * 9, 8.0), (x0, s * 9, 11.0)], (0, s, 0)),
                  [(0, 1, 2)], "ziegel")
    b.box(8.5, -11.5, 0, 12.0, 5.0, 7.0, "wand_creme")                  # Verwaltung
    b.flachdach(8.5, -11.5, 7.0, 12.0, 5.0, "wand_creme")
    for z in (2.2, 5.2):
        b.feld((9.3, -14.0, z), 8.6, 1.5, "-y", "fenster")
        b.feld((14.5, -11.5, z), 3.6, 1.5, "+x", "fenster")
    b.tuer((3.4, -14.0, 1.1), 1.4, 2.2, "-y", key="metall_dunkel", vordach="metall_dunkel")
    b.box(-7.5, -9.9, 0, 13.0, 1.8, 1.1, "beton")                       # Laderampe
    for x in (-11.5, -7.5, -3.5):
        b.feld((x, -9.0, 3.1), 3.2, 3.8, "-y", "metall")                # Rolltore
    b.box(-7.5, -10.2, 5.3, 13.6, 2.6, 0.25, "metall_dunkel")           # Rampendach
    for x in (-11.25, -3.75, 3.75, 11.25):
        b.feld((x, 9.0, 4.4), 3.0, 4.4, "+y", "fenster")                # Hallenfenster
    b.feld((15.0, 1.5, 4.4), 10.0, 4.4, "+x", "fenster")
    b.zyl(-18.0, 5.0, 0, 1.9, 1.2, 30.0, 10, "ziegel")                   # Schornstein
    b.zyl(-18.0, 5.0, 30.0, 1.45, 1.45, 0.9, 10, "metall_dunkel")
    if b.hd:
        for gx in (-11.0, -3.5, 4.0, 11.5):                              # Wandpfeiler
            b.box(gx, 0, 0, 0.7, 18.2, 8.0, "ziegel")
        for x in (-11.25, -3.75, 3.75, 11.25):                           # Fenstersprossen
            b.feld((x, 9.0, 4.4), 0.14, 4.4, "+y", "wand_weiss", eps=0.06)
            b.feld((x, 9.0, 4.4), 3.0, 0.14, "+y", "wand_weiss", eps=0.06)
        for x in (-11.5, -7.5, -3.5):                                    # Rolltor-Lamellen
            for k in range(4):
                b.feld((x, -9.0, 1.9 + k * 0.85), 3.2, 0.1, "-y", "metall_dunkel", eps=0.06)
        b.zyl(17.2, 5.0, 0, 1.5, 1.5, 6.0, 10, "metall")                 # Tank
        b.kegel(17.2, 5.0, 6.0, 1.5, 0.7, 10, "metall_dunkel")
        b.balken((17.2, 5.0, 4.6), (15.0, 5.0, 4.6), 0.3, 0.3, "metall_dunkel")
        for z in (10.0, 20.0):                                            # Schornsteinbaender
            b.zyl(-18.0, 5.0, z, 1.75 - z * 0.022, 1.75 - z * 0.022, 0.35, 10, "metall_dunkel")
        _geraete(b, 7.0, ((11.0, -11.5, 2.0, 1.6, 1.0),))


def kraftwerk(b):
    """Kraftwerk: hohes Kesselhaus mit Lamellenbaendern, Turbinenhalle mit hohen Fenstern, zwei
    Schornsteine mit ROT-WEISSEM Kopf, Kuehlturm als Hyperboloid mit dunklem Lufteinlass und
    offenem Inneren, schraege Foerderbruecke, Schaltwarte."""
    b.box(-12.5, 0.5, 0, 11.0, 14.0, 24.0, "beton")                     # Kesselhaus
    b.flachdach(-12.5, 0.5, 24.0, 11.0, 14.0, "beton")
    for z in (8.0, 15.0, 21.0):
        b.feld((-12.5, -6.5, z), 9.0, 2.2, "-y", "metall_dunkel")       # Lamellenbaender
        b.feld((-18.0, 0.5, z), 11.5, 2.2, "-x", "metall_dunkel")
        b.feld((-12.5, 7.5, z), 9.0, 2.2, "+y", "metall_dunkel")
    b.box(-1.5, 0.5, 0, 11.0, 14.0, 12.0, "wand_grau")                  # Turbinenhalle
    b.dach(-1.5, 0.5, 12.0, 11.0, 14.0, 2.2, "metall_dunkel", axis="y", over=0.3)
    for x in (-5.0, -1.5, 2.0):
        b.feld((x, -6.5, 6.0), 1.8, 8.0, "-y", "fenster")               # hohe Fenster
        b.feld((x, 7.5, 6.0), 1.8, 8.0, "+y", "fenster")
    for y in (-3.5, 0.5, 4.5):
        b.feld((4.0, y, 6.0), 1.8, 8.0, "+x", "fenster")
    for x in (-15.5, -9.5):                                               # Schornsteine
        b.zyl(x, 10.4, 0, 1.6, 1.25, 32.0, 8, "beton", cap_top=False)
        b.ringel(x, 10.4, 32.0, 1.25, 1.0, 14.0, 8, ("dach_rot", "wand_weiss"), 4)
    for r0, r1, z0, z1 in ((9.6, 8.0, 0.0, 6.5), (8.0, 6.7, 6.5, 13.0), (6.7, 6.5, 13.0, 19.5),
                           (6.5, 7.9, 19.5, 28.0)):                       # Kuehlturm
        b.zyl(13.0, 0, z0, r0, r1, z1 - z0, 12, "beton", cap_top=False)
    b.zyl(13.0, 0, 0, 9.75, 9.3, 2.4, 12, "fenster", cap_top=False)      # Lufteinlass
    b.ring(13.0, 0, 27.2, 7.72, 0.0, 12, "fenster")                       # dunkles Inneres
    b.balken((7.0, -10.5, 1.2), (-9.0, -7.0, 17.0), 2.0, 2.2, "metall")  # Foerderbruecke
    b.box(7.0, -10.5, 0, 3.0, 3.0, 2.4, "metall_dunkel")
    b.box(-2.0, -9.5, 0, 6.5, 4.0, 3.6, "wand_creme")                    # Schaltwarte
    b.flachdach(-2.0, -9.5, 3.6, 6.5, 4.0, "wand_creme", hoehe=0.5)
    b.feld((-2.0, -11.5, 2.0), 5.0, 1.4, "-y", "fenster")
    if b.hd:
        b.zyl(13.0, 0, 27.6, 8.0, 8.0, 0.5, 12, "beton", cap_top=False)   # Kronenring
        for x in (-5.0, -1.5, 2.0):                                       # Fenstersprossen
            for z in (3.5, 6.0, 8.5):
                b.feld((x, -6.5, z), 1.8, 0.14, "-y", "wand_weiss", eps=0.06)
        for t in (0.3, 0.62):                                             # Stuetzen der Bruecke
            px, py, pz = 7.0 - 16.0 * t, -10.5 + 3.5 * t, 1.2 + 15.8 * t
            b.box(px, py, 0, 0.5, 0.5, pz - 1.0, "metall_dunkel")
        for x in (6.5, 9.0):                                              # Trafos
            b.box(x, 11.0, 0, 1.8, 1.6, 2.2, "metall")
            b.zyl(x, 11.0, 2.2, 0.12, 0.12, 1.2, 6, "metall_dunkel")
        for x in (-15.5, -9.5):                                           # Rauchgaskanal
            b.balken((x, 7.6, 14.0), (x, 10.0, 14.0), 1.6, 1.6, "metall")
        _geraete(b, 24.0, ((-14.5, 3.0, 2.4, 2.0, 1.4), (-10.5, -2.0, 2.4, 2.0, 1.4)))


def funkturm(b):
    """Fernsehturm (57 m): Fussbau, schlanker Betonschaft, Kanzel mit umlaufendem Glasband,
    rot-weisser Antennenmast. (Vorher ein vierkantiger Stumpf mit aufgeklebten Kreuzen.)"""
    b.zyl(0, 0, 0, 6.2, 5.2, 3.2, 10, "beton")                           # Fussbau
    b.zyl(0, 0, 3.2, 3.1, 1.9, 26.0, 10, "beton", cap_top=False)         # Schaft
    b.zyl(0, 0, 29.2, 1.9, 5.3, 2.2, 10, "beton", cap_top=False)         # Kanzelkorb
    b.zyl(0, 0, 31.4, 5.3, 5.3, 2.6, 10, "glas_blau", cap_top=False)     # Glasband
    b.zyl(0, 0, 34.0, 5.6, 3.2, 1.3, 10, "wand_weiss")                   # Kanzeldach
    b.zyl(0, 0, 35.3, 3.0, 3.0, 1.7, 10, "wand_weiss")                   # oberes Deck
    b.ringel(0, 0, 37.0, 0.62, 0.22, 20.0, 6, ("dach_rot", "wand_weiss"), 5)
    b.feld((0, -5.95, 1.3), 1.6, 2.4, "-y", "metall_dunkel", eps=0.3)
    if b.hd:
        b.zyl(0, 0, 31.2, 5.5, 5.5, 0.22, 10, "metall_dunkel", cap_top=False)
        b.zyl(0, 0, 33.9, 5.5, 5.5, 0.22, 10, "metall_dunkel", cap_top=False)
        for k in range(10):                                               # Glasband-Pfosten
            a = 2.0 * math.pi * (k + 0.5) / 10.0
            b.balken((math.cos(a) * 5.34, math.sin(a) * 5.34, 31.4),
                     (math.cos(a) * 5.34, math.sin(a) * 5.34, 34.0), 0.16, 0.16, "wand_weiss")
        for a in (0.6, 2.2, 3.8, 5.4):                                    # Richtfunkschuesseln
            b.zyl(math.cos(a) * 3.3, math.sin(a) * 3.3, 36.0, 0.9, 0.9, 0.3, 8, "wand_weiss")


def hafenkran(b):
    """Portal-Hafenkran: vier gespreizte Beine mit Durchfahrt, Drehkranz, Maschinenhaus mit
    Kanzel, schraeger Ausleger mit Abspannung, Gegengewicht, Seil und Haken.
    (Vorher ein Kegelstumpf mit waagrechtem Balken.)"""
    K = "signal_gelb"
    for ex in (-1, 1):
        for ey in (-1, 1):
            b.balken((ex * 4.2, ey * 4.2, 0.6), (ex * 1.9, ey * 1.9, 12.4), 0.8, 0.8, K)  # Beine
            b.box(ex * 4.2, ey * 4.2, 0, 2.2, 1.2, 0.9, "metall_dunkel")                    # Fahrwerk
    b.box(0, 0, 11.8, 5.2, 5.2, 1.2, K)                                   # Portalkopf
    for ey in (-1, 1):
        b.balken((-4.2, ey * 4.2, 4.0), (4.2, ey * 4.2, 4.0), 0.4, 0.5, K)
    b.zyl(0, 0, 13.0, 2.2, 2.2, 0.8, 10, "metall_dunkel")                 # Drehkranz
    b.box(-1.6, 0, 13.8, 7.6, 4.0, 3.6, K)                                # Maschinenhaus
    b.box(-6.2, 0, 14.0, 2.6, 3.4, 2.8, "metall_dunkel")                  # Gegengewicht
    b.box(2.9, -1.5, 14.4, 1.8, 1.4, 2.2, "glas_blau")                    # Kanzel
    b.balken((1.8, 0, 17.0), (24.0, 0, 30.0), 1.5, 1.5, K)                # Ausleger
    b.balken((-2.5, 0, 17.4), (-1.0, 0, 24.0), 0.5, 0.5, K)               # A-Bock
    b.balken((-1.0, 0, 24.0), (23.6, 0, 30.4), 0.16, 0.16, "metall_dunkel")  # Abspannung
    b.balken((-1.0, 0, 24.0), (-5.6, 0, 17.0), 0.16, 0.16, "metall_dunkel")
    b.box(23.6, 0, 16.0, 0.16, 0.16, 13.6, "metall_dunkel")               # Hubseil
    b.box(23.6, 0, 14.6, 2.0, 1.6, 1.4, "metall_dunkel")                  # Haken/Spreader
    if b.hd:
        for t in (0.2, 0.4, 0.6, 0.8):                                    # Gitterstreben
            px, pz = 1.8 + 22.2 * t, 17.0 + 13.0 * t
            b.box(px, 0, pz - 0.9, 0.2, 1.7, 1.8, "metall_dunkel")
        for ex in (-1, 1):                                                 # Portal-Querriegel
            b.balken((ex * 4.2, -4.2, 4.0), (ex * 4.2, 4.2, 4.0), 0.4, 0.5, K)
        b.gelaender(-1.6, 0, 17.4, 7.4, 3.8, "metall_dunkel", 0.9, 8)
        for ey in (-1, 1):                                                 # Schienen
            b.box(0, ey * 4.2, 0, 11.0, 0.5, 0.2, "metall_dunkel")
        b.feld((-1.6, -2.0, 15.6), 1.4, 1.2, "-y", "fenster", eps=0.05)


def getreidesilo(b):
    """Getreidesilo: fuenf Betonzellen, Foerdergalerie mit Satteldach darauf, hoher
    Elevatorturm am Ende, Annahme mit Tor, Verladerohr."""
    for i in range(5):
        x = (i - 2) * 4.6
        b.zyl(x, 0, 0, 2.3, 2.3, 20.2, 10, "beton")
    b.box(0, 0, 20.2, 23.4, 3.8, 3.0, "metall")                          # Foerdergalerie
    b.dach(0, 0, 23.2, 23.4, 3.8, 1.0, "metall_dunkel", axis="x", over=0.25, giebel="metall")
    for s, f in ((-1, "-y"), (1, "+y")):
        b.feld((0, s * 1.9, 21.9), 21.0, 1.0, f, "fenster")
    b.box(-14.4, 0, 0, 5.4, 6.6, 31.0, "wand_grau")                      # Elevatorturm
    b.pultdach(-14.4, 0, 31.0, 5.4, 6.6, 1.2, "metall_dunkel")
    for z in (6.0, 12.0, 18.0, 27.0):
        b.feld((-14.4, -3.3, z), 1.2, 1.4, "-y", "fenster")
    b.box(-14.4, -5.6, 0, 5.4, 4.6, 6.0, "wand_grau")                    # Annahme
    b.pultdach(-14.4, -5.6, 6.0, 5.4, 4.6, 0.9, "metall_dunkel")
    b.feld((-14.4, -7.9, 2.3), 3.6, 4.2, "-y", "metall_dunkel")
    b.balken((11.6, 0, 21.0), (15.0, 0, 8.5), 0.9, 0.9, "metall_dunkel")  # Verladerohr
    if b.hd:
        for i in range(5):
            x = (i - 2) * 4.6
            for z in (6.5, 13.0, 19.4):                                   # Ringanker
                b.zyl(x, 0, z, 2.42, 2.42, 0.3, 10, "metall", cap_top=False)
        for k in range(18):                                                # Steigleiter
            b.box(11.75, -0.6, 1.0 + k * 1.05, 0.08, 0.6, 0.06, "metall_dunkel")
        b.box(11.75, -0.9, 0.6, 0.06, 0.06, 19.4, "metall_dunkel")
        b.box(11.75, -0.3, 0.6, 0.06, 0.06, 19.4, "metall_dunkel")
        b.zyl(15.0, 0, 6.6, 0.7, 0.4, 1.9, 8, "metall_dunkel")           # Verladetrichter


def stadion(b):
    """Stadion: Aussenwand, geneigte Tribuene in zwei Farbringen, umlaufendes Dach (Ober- und
    Unterseite, an der Aussenwand aufgehaengt), Spielfeld mit Laufbahn, vier Flutlichtmasten.
    (Vorher schwebten die Dachplatten einzeln ueber dem Rand.)"""
    n = 16
    R, hh = 38.0, 14.0
    b.zyl(0, 0, 0, R, R, hh, n, "beton", cap_top=False)                   # Aussenwand
    b.ring(0, 0, hh, R, 31.5, n, "wand_weiss", z_innen=8.6)               # Oberrang
    b.ring(0, 0, 8.6, 31.5, 25.0, n, "signal_blau", z_innen=2.4)          # Unterrang
    b.zyl(0, 0, 0, 25.0, 25.0, 2.4, n, "beton", cap_top=False)            # Bande (innen sichtbar)
    b.ring(0, 0, 0.3, 25.0, 20.5, n, "dach_terra")                        # Laufbahn
    b.ring(0, 0, 0.3, 20.5, 0.0, n, "gruen")                              # Rasen
    # Das Dach LIEGT AUF DER AUSSENWAND und steigt nach innen an (Kragdach) — so braucht es
    # auch in der Fernstufe keine Stuetzen und schwebt nicht.
    b.zyl(0, 0, hh, R + 1.4, R + 1.4, 0.6, n, "metall_dunkel", cap_top=False)     # Dachrand
    b.ring(0, 0, hh + 0.6, R + 1.4, 28.5, n, "metall", z_innen=17.6)      # Dach oben
    b.ring(0, 0, hh, R + 1.4, 28.5, n, "metall_dunkel", z_innen=17.3, unten=True)
    for k in range(4):                                                     # Flutlicht
        a = math.pi * 0.25 + k * math.pi * 0.5
        x, y = math.cos(a) * (R + 2.6), math.sin(a) * (R + 2.6)
        b.zyl(x, y, 0, 0.55, 0.35, 30.0, 6, "metall_dunkel")
        b.box(x - math.cos(a) * 0.6, y - math.sin(a) * 0.6, 30.0, 4.4, 1.0, 2.0, "wand_weiss")
    if b.hd:
        m = n * 2
        for i in range(m):                                                 # Dachtraeger
            a = 2.0 * math.pi * (i + 0.5) / m
            c, sa = math.cos(a), math.sin(a)
            b.balken((c * (R + 1.2), sa * (R + 1.2), hh + 0.75), (c * 28.8, sa * 28.8, 17.75),
                     0.4, 0.3, "metall_dunkel")
        b.boden(0, 0, 0.33, 30.0, 0.25, "wand_weiss")                      # Mittellinie
        b.ring(0, 0, 0.33, 4.8, 4.5, 12, "wand_weiss")                     # Mittelkreis
        for s in (-1, 1):
            b.boden(0, s * 13.0, 0.33, 30.0, 0.25, "wand_weiss")
            b.boden(s * 15.0, 0, 0.33, 0.25, 26.0, "wand_weiss")
        for a in (0.0, math.pi * 0.5, math.pi, math.pi * 1.5):             # Eingaenge
            b.box(math.cos(a) * R, math.sin(a) * R, 0, 5.0 if abs(math.sin(a)) > 0.5 else 1.0,
                  1.0 if abs(math.sin(a)) > 0.5 else 5.0, 4.6, "metall_dunkel")


def burg(b):
    """Burg: Ringmauer mit vier Ecktuermen, TORHAUS mit zwei Flankentuermen und Zugbruecke,
    Bergfried im Hof (seitlich, mit Wehrkranz und Fahne), Palas mit rotem Satteldach, Brunnen.
    HD: Zinnen auf Mauern, Tuermen, Bergfried und Torhaus, Wehrgang."""
    S = "stein"
    for s in (-1, 1):                                                       # Ringmauer
        b.box(s * 17.0, 0, 0, 3.0, 34.0, 9.0, S)
        b.box(0, s * 17.0, 0, 34.0, 3.0, 9.0, S)
    for ex in (-1, 1):                                                      # Ecktuerme
        for ey in (-1, 1):
            b.zyl(ex * 17.0, ey * 17.0, 0, 3.6, 3.2, 14.0, 8, S, cap_top=False)
            b.zyl(ex * 17.0, ey * 17.0, 14.0, 3.9, 3.9, 1.2, 8, S)
            b.kegel(ex * 17.0, ey * 17.0, 15.2, 3.5, 5.2, 8, "dach_rot")
    b.box(-7.0, 6.0, 0, 11, 11, 23.0, S)                                   # Bergfried
    b.box(-7.0, 6.0, 23.0, 12.4, 12.4, 1.4, S)                             # Wehrkranz
    b.spitze(-7.0, 6.0, 24.4, 10.4, 10.4, 6.5, "dach_schiefer")
    b.zyl(-7.0, 6.0, 30.6, 0.12, 0.12, 3.4, 6, "metall")                   # Fahnenmast
    b.feld((-6.0, 6.0, 33.2), 2.0, 1.2, "-y", "dach_rot", eps=0.0, zweiseitig=True)
    for z in (9.0, 14.0, 19.0):
        b.feld((-7.0, 0.5, z), 0.8, 2.2, "-y", "fenster")                  # Scharten
        b.feld((-1.5, 6.0, z), 0.8, 2.2, "+x", "fenster")
    b.box(6.5, 10.5, 0, 15, 8, 9.5, "wand_creme")                          # Palas
    d = b.dach(6.5, 10.5, 9.5, 15, 8, 4.4, "dach_rot", axis="x", over=0.3)
    b.kamin(d, 4.5, -1.0, key="stein")
    for x in (2.0, 5.0, 8.0, 11.0):
        b.bogen((x, 6.5, 6.4), 1.2, 2.6, "-y", "fenster")
    b.bogen((12.4, 6.5, 1.4), 1.6, 2.8, "-y", "holz_dunkel")
    b.box(0, -17.5, 0, 7.0, 5.0, 12.5, S)                                  # Torhaus
    b.box(0, -17.5, 12.5, 7.8, 5.8, 1.2, S)
    b.bogen((0, -20.0, 2.7), 3.6, 5.4, "-y", "holz_dunkel")                # Tor
    for s in (-1, 1):                                                       # Flankentuerme
        b.zyl(s * 5.0, -19.4, 0, 2.3, 2.1, 13.5, 8, S, cap_top=False)
        b.kegel(s * 5.0, -19.4, 13.5, 2.6, 4.2, 8, "dach_rot")
    b.box(0, -23.0, 0, 3.6, 6.0, 0.5, "holz_hell", skip=())                # Zugbruecke
    b.zyl(6.0, -5.0, 0, 1.3, 1.3, 1.0, 8, S)                               # Brunnen
    if b.hd:
        for s in (-1, 1):                                                   # Mauerzinnen, Wehrgang
            b.zinnen(s * 17.0, 0, 9.0, 3.0, 34.0, S, 9, 1.1)
            b.zinnen(0, s * 17.0, 9.0, 34.0, 3.0, S, 9, 1.1)
            b.box(s * 15.0, 0, 7.4, 1.4, 30.0, 0.4, "holz_dunkel")
            b.box(0, s * 15.0, 7.4, 30.0, 1.4, 0.4, "holz_dunkel")
        b.zinnen(-7.0, 6.0, 24.4, 12.4, 12.4, S, 5, 1.2)
        b.zinnen(0, -17.5, 13.7, 7.8, 5.8, S, 4, 1.0)
        for ex in (-1, 1):
            for ey in (-1, 1):
                b.feld((ex * 17.0, ey * 17.0 - 3.3, 10.5), 0.5, 1.6, "-y", "fenster", eps=0.3)
        for s in (-1, 1):                                                   # Ketten der Zugbruecke
            b.balken((s * 1.6, -20.0, 5.6), (s * 1.6, -25.6, 0.5), 0.08, 0.08, "metall_dunkel")
        b.zyl(6.0, -5.0, 1.0, 0.1, 0.1, 2.2, 6, "holz_dunkel")              # Brunnengalgen
        b.box(6.0, -5.0, 3.1, 2.4, 0.2, 0.2, "holz_dunkel")


def radarstation(b):
    """Radarstation: Betriebsgebaeude, weisse RADOMKUGEL auf Sockel, Parabolantenne (zeigt zum
    Himmel) auf Mast, Funkmast. HD: Zaun ringsum (vorher standen nur lose Pfosten)."""
    b.box(0, 0, 0, 12, 10, 4.6, "beton")
    b.flachdach(0, 0, 4.6, 12, 10, "beton", hoehe=0.5)
    b.feld((-1.0, -5.0, 2.5), 7.0, 1.5, "-y", "fenster")
    b.tuer((4.4, -5.0, 1.05), 1.1, 2.1, "-y", key="metall_dunkel", vordach="beton")
    b.fenster_reihe("+x", 6.0, 0, 7.0, 2.5, 3, 1.3, 1.3)
    b.fenster_reihe("+y", 5.0, 0, 9.0, 2.5, 4, 1.3, 1.3)
    b.zyl(1.5, 1.2, 4.6, 3.0, 3.0, 2.8, 10, "beton")                      # Radomsockel
    b.kuppel(1.5, 1.2, 9.6, 3.9, 10, "wand_weiss", von=-0.75, baender=4)  # Radom
    b.box(-8.6, 2.0, 0, 1.3, 1.3, 7.0, "metall_dunkel")                   # Antennenmast
    b.zyl(-8.6, 2.0, 7.0, 0.3, 2.5, 1.0, 10, "wand_weiss")                # Parabolspiegel
    b.zyl(-8.6, 2.0, 8.0, 0.07, 0.07, 1.5, 6, "metall_dunkel")            # Speisehorn
    b.zyl(-8.6, -3.6, 0, 0.24, 0.12, 15.0, 6, "metall")                   # Funkmast
    for z in (10.5, 12.5, 14.0):
        b.feld((-8.6, -3.6, z), 3.6 - (z - 10.5) * 0.5, 0.2, "-y", "metall_dunkel", eps=0.0,
               zweiseitig=True)
    if b.hd:
        b.gelaender(-1.3, 0, 0, 22.0, 15.0, "metall_dunkel", 2.0, 14)       # Zaun
        b.zyl(1.5, 1.2, 7.2, 3.15, 3.15, 0.25, 10, "metall_dunkel", cap_top=False)
        for i in range(4):                                                  # Leiter zum Sockel
            b.box(4.55, 1.2, 5.0 + i * 0.6, 0.06, 0.5, 0.06, "metall_dunkel")
        b.zyl(-8.6, 2.0, 9.5, 0.2, 0.2, 0.3, 6, "metall")
        _geraete(b, 4.6, ((-3.6, -2.6, 1.8, 1.4, 0.9), (-3.6, 2.6, 1.8, 1.4, 0.9)))


def bunker(b):
    """Bunker: abgeschraegter Betonkoerper mit GRASDACH (Tarnung), Schartenband, Panzerkuppel als
    Beobachtungsstand, Eingang hinter einer Splitterschutzmauer, Antenne. HD: Sandsaecke."""
    prof = [(-7.0, 0.0), (-5.2, 4.2), (5.2, 4.2), (7.0, 0.0)]   # abgeschraegte Waende
    b.profil(0, 0, 0, prof, 10.0, "beton")
    b.box(0, 0, 4.2, 11.2, 10.6, 0.8, "beton")                             # Deckenplatte
    b.boden(0, 0, 5.03, 10.0, 9.4, "gruen")                                 # Grasdach
    b.feld((0, -5.0, 2.6), 6.4, 0.9, "-y", "beton", eps=0.03)              # Schartenrahmen
    b.feld((0, -5.0, 2.6), 6.0, 0.55, "-y", "fenster", eps=0.06)           # Scharte
    b.zyl(0, 2.6, 5.0, 1.75, 1.75, 0.7, 8, "beton", cap_top=False)         # Kuppelkranz
    b.kuppel(0, 2.6, 5.7, 1.6, 8, "metall_dunkel", baender=2)              # Panzerkuppel
    b.box(5.6, -3.4, 0, 2.6, 2.6, 2.8, "beton")                            # Eingangsschleuse
    b.feld((5.6, -4.7, 1.1), 1.2, 2.0, "-y", "metall_dunkel")
    b.box(5.6, -6.6, 0, 4.4, 0.6, 2.4, "beton")                            # Splitterschutz
    b.zyl(-4.0, -3.0, 5.0, 0.12, 0.12, 5.0, 6, "metall")                   # Antenne
    if b.hd:
        for x in (-2.0, 0.0, 2.0):                                          # Schartenstege
            b.feld((x, -5.0, 2.6), 0.3, 0.55, "-y", "beton", eps=0.08)
        for i in range(6):                                                  # Sandsaecke
            b.box(-4.0 + i * 1.6, -6.0, 0, 1.4, 0.9, 0.55, "wand_sand")
            b.box(-3.2 + i * 1.6, -6.0, 0.55, 1.4, 0.9, 0.5, "wand_sand")
        for x in (2.4, -2.6):                                               # Lueftungsrohre
            b.zyl(x, 3.6, 5.0, 0.22, 0.22, 1.4, 6, "metall_dunkel")
        b.feld((0, 1.0, 6.2), 0.9, 0.22, "-y", "fenster", eps=0.02)        # Sehschlitz der Kuppel


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
    # Hochhaeuser: die Skyline besteht aus wenigen Typen, also zaehlt hier jede Variante
    "Haus_Wohnturm": [
        {"wand_terra": "wand_blau"},
        {"wand_weiss": "wand_creme", "wand_terra": "wand_ocker"}],
    "Haus_Bueroturm": [
        {"glas_blau": "glas_gruen", "glas_dunkel": "glas_blau"}],
    "Haus_Plattenbau": [
        {"wand_blau": "wand_mauve", "wand_ocker": "wand_gruen"}],
    "Haus_Hotel": [
        {"wand_creme": "wand_mauve", "dach_rot": "signal_blau"}],
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
            b.box(sx * 5.7, y, 0, 0.9, 1.4, 6.6, "wand_creme")
            b.dach(sx * 5.7, y, 6.6, 1.0, 1.5, 0.7, "dach_schiefer", axis="y", over=0.05,
                   details=False)
    b.box(0, -13.6, 0, 4.4, 1.2, 0.5, "stein")                   # Portalstufe
    for sx in (-1, 1):                                            # Ecklisenen am Turm
        for sy in (-1, 1):
            b.box(sx * 3.1, -10.0 + sy * 3.1, 0, 0.7, 0.7, 19.0, "stein")
    for f, cx, cy in (("-y", 0.0, -13.3), ("-x", -3.3, -10.0), ("+x", 3.3, -10.0)):   # Zeiger
        b.feld((cx, cy, 12.6), 0.1, 0.85, f, "wand_weiss", eps=0.12, winkel=0.5)
        b.feld((cx, cy, 12.6), 0.1, 0.55, f, "wand_weiss", eps=0.12, winkel=-1.3)
    for y in (-3.0, 2.0, 7.0):                                    # Masswerk (Mittelpfosten)
        b.feld((-5.5, y, 4.5), 0.12, 3.4, "-x", "stein", eps=0.07)
        b.feld((5.5, y, 4.5), 0.12, 3.4, "+x", "stein", eps=0.07)
    # KIRCHHOF: Mauer ringsum mit Tor vorn, Grabsteine
    for sx in (-1, 1):
        b.box(sx * 12.5, 2.0, 0, 0.5, 37.0, 1.3, "stein")
        b.box(sx * 7.4, -16.5, 0, 10.7, 0.5, 1.3, "stein")
        b.box(sx * 2.3, -16.5, 0, 0.7, 0.7, 2.0, "stein")               # Torpfeiler
    b.box(0, 20.5, 0, 25.5, 0.5, 1.3, "stein")
    for j in range(3):
        for i in range(5):
            b.box(-10.6 + j * 1.5, -8.0 + i * 4.2, 0, 0.6, 0.18, 0.85, "stein")
    for i in range(3):
        b.box(10.4, 0.0 + i * 3.6 - 9.0, 0, 0.6, 0.18, 0.85, "stein")


def hd_villa(b):
    b.box(0, -5.9, 0, 4.6, 1.6, 0.45, "stein")                    # Freitreppe
    for sx in (-1, 1):                                             # Ecklisenen (an den ECKEN)
        for sy in (-1, 1):
            b.box(sx * 6.4, sy * 4.9, 0, 0.5, 0.5, 7.8, "wand_weiss")
    b.box(0, 0, 7.5, 13.3, 10.3, 0.3, "wand_weiss")               # Traufgesims


def hd_hangar(b):
    prof = [(-11.0, 0.0), (-11.0, 4.6), (-8.2, 7.6), (0.0, 9.0), (8.2, 7.6), (11.0, 4.6), (11.0, 0.0)]
    rippe = [(px * 1.025, pz * 1.035) for px, pz in prof]              # Bogenbinder aussen
    for y in (-8.5, -3.0, 3.0, 8.5):
        b.profil(0, y, 0, rippe, 0.45, "metall_dunkel")
    b.box(0, -10.2, 7.0, 17.4, 0.5, 0.6, "metall_dunkel")           # Torschiene
    b.box(0, -10.4, 0, 18.0, 0.6, 0.4, "beton")                     # Vorfeldschwelle


def hd_gasthaus(b):
    for sx in (-1, 1):                                                  # Eckstaender
        for sy in (-1, 1):
            b.box(sx * 5.9, sy * 4.4, 0, 0.35, 0.35, 7.2, "holz_dunkel")
    for x in (-3.0, 3.0):                                               # Baenke unter der Laube
        b.box(x, -5.6, 0, 2.2, 0.5, 0.45, "holz_hell")


HD_EXTRAS = {
    "Haus_Fachwerk": hd_fachwerk, "Haus_Kirche": hd_kirche,
    "Haus_Villa": hd_villa, "Haus_Hangar": hd_hangar,
    "Haus_Gasthaus": hd_gasthaus,
}



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
    b.box(2.0, -4.7, 0, 1.6, 0.5, 0.45, "holz_hell")                    # Bank
    b.zaun([(-3.4, -4.0), (-3.4, 4.6), (3.4, 4.6), (3.4, -4.0)], hoehe=0.8)


def hd_stall(b):
    for x in (-4.2, -1.4, 1.4, 4.2):                                    # Holzstaender
        b.box(x, -3.05, 0, 0.28, 0.3, 2.9, "holz_dunkel")
    b.box(0, -3.05, 2.9, 10.2, 0.3, 0.28, "holz_dunkel")               # Rahmriegel
    b.box(0, 0, 2.9, 10.6, 6.6, 0.22, "holz_dunkel")
    for i in range(4):                                                   # Traenken/Tore
        b.box(-3.6 + i * 2.4, -3.2, 0, 1.8, 0.25, 1.1, "holz_hell")


HD_EXTRAS.update({ "Haus_Kate": hd_kate,
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
                              export_apply=True, export_vertex_color='ACTIVE')
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
                              export_apply=True, export_vertex_color='ACTIVE')
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
    # Ohne Schattenwurf: die Workbench-Schatten (Stencil-Volumen) zerkratzen offene Flaechen —
    # jedes Fensterband sah aus wie verrauscht. "Standard" statt AgX, sonst ist alles duester.
    scn.display.shading.show_shadows = False
    scn.display.shading.show_cavity = True
    scn.view_settings.view_transform = 'Standard'
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
        vfov = 2.0 * math.atan(0.5 * 36.0 * res[1] / res[0] / cam.data.lens)
        dist = max(breite * 0.5 / math.tan(fov * 0.5),
                   (hi.z - lo.z) * 0.62 / math.tan(vfov * 0.5)) + (hi.y - lo.y)
        d = (V(blick) if blick else V((-von_links, -1.0, hoehe))).normalized()
        cam.location = ctr + d * dist
        cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
        # Nahe Clipebene mit dem Abstand mitfuehren: bei 0.1 m reicht die Tiefenaufloesung in
        # 150 m Entfernung nicht fuer Felder, die 4 cm vor der Wand liegen (Fenster flimmerten).
        cam.data.clip_start = max(dist * 0.25, 0.5)
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
    hoch = ["Haus_Wohnturm", "Haus_Bueroturm", "Haus_Wolkenkratzer", "Haus_Hotel",
            "Haus_Krankenhaus"]
    block = ["Haus_Plattenbau", "Haus_Kaufhaus", "Haus_Parkhaus"]
    industrie = ["Haus_Fabrik", "Haus_Kraftwerk", "Haus_Getreidesilo", "Haus_Werkstatt",
                 "Haus_Tanklager", "Haus_Silo"]
    tuerme = ["Haus_Hafenkran", "Haus_Funkturm", "Haus_Wasserturm"]
    spezial = ["Haus_Hangar", "Haus_Tower", "Haus_Radarstation", "Haus_Bunker", "Haus_Stadion",
               "Haus_Burg"]
    hd = lambda l: [n + "_HD" for n in l]
    bilder = {
        "hd_dorf": (hd(dorf), {}), "hd_stadt": (hd(stadt), {}), "hd_gross": (hd(gross), {}),
        "lod_dorf": (dorf, {}), "lod_stadt": (stadt, {}),
        "varianten": ([n for n, _f, _t, g in alle_bauten()
                       if g in ("Haus_Bauernhaus", "Haus_Fachwerk", "Haus_Kate",
                                "Haus_Stadthaus2")], dict(hoehe=0.6)),
        "hd_hoch": (hd(hoch), dict(res=(1800, 1100), hoehe=0.30)),
        "lod_hoch": (hoch, dict(res=(1800, 1100), hoehe=0.30)),
        "hd_block": (hd(block), {}), "hd_industrie": (hd(industrie), {}),
        "lod_industrie": (industrie, {}),
        "hd_tuerme": (hd(tuerme), dict(res=(1500, 1100), hoehe=0.25)),
        "hd_spezial": (hd(spezial), {}),
        "hd_rest": (hd(["Haus_Werkstatt", "Haus_Silo", "Haus_Speicher", "Haus_Tower",
                        "Haus_Radarstation", "Haus_Bunker", "Haus_Hangar"]), {}),
        "hd_kirchen": (hd(["Haus_Kirche", "Haus_Kapelle", "Haus_Rathaus", "Haus_Bahnhof"]), {}),
        "hd_land": (hd(["Haus_Stall", "Haus_Wassermuehle", "Haus_Windmuehle", "Haus_Lotsenhaus",
                        "Haus_Burg"]), {}),
        "nah_bauernhaus": (["Haus_Bauernhaus_HD"], dict(res=(1200, 900), hoehe=0.35)),
        "nah_fachwerk": (["Haus_Fachwerk_HD"], dict(res=(1000, 1000), hoehe=0.25, von_links=0.6)),
    }
    # HAEUSER_BILDER=hd_hoch,hd_industrie: nur diese Bilder; nah:<Typ>[:hinten] = Einzelbild
    nur = os.environ.get("HAEUSER_BILDER", "")
    if nur:
        for w in nur.split(","):
            if w.startswith("nah:"):
                t = w.split(":")
                kw = dict(res=(1200, 1000), hoehe=0.32)
                if len(t) > 2:
                    kw["blick"] = (0.6, 1.0, 0.45)
                gruppe(["Haus_%s_HD" % t[1]], os.path.join(PREVIEW, "nah_%s%s.png" % (
                    t[1].lower(), "_hinten" if len(t) > 2 else "")), **kw)
            elif w in bilder:
                gruppe(bilder[w][0], os.path.join(PREVIEW, w + ".png"), **bilder[w][1])
        return
    for name, (namen, kw) in bilder.items():
        gruppe(namen, os.path.join(PREVIEW, name + ".png"), **kw)

main()
