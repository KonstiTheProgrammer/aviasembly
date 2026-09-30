# Baum-Baukasten fuer die Weltflora -> models/world_trees.glb
#
# DREIZEHN Arten mit eigener Silhouette (Fichte, Kiefer, Birke, Eiche, Palme, Totholz, Busch
# und fuer die Regionen Schneetanne, Urwaldbaum, Baumfarn, Akazie, Mangrove, Kaktus) plus
# ein Felsbrocken ("Fels"). Stil Zelda/Ghibli: Kronen als Wolken aus mehreren runden
# Ballen, weiche Formen, kein Rauschkorn (siehe CLAUDE.md "Welt-Look").
#
# ZWEITE FASSUNG (2026-09). Die erste baute Kronen und Kraenze aus OFFENEN Ringstreifen
# (jeder Streifen eigene Eckpunkte) und liess Blender die Wicklung raten
# (recalc_face_normals). Das ging bei jeder Laubkrone schief: gemessen zeigten in Eiche,
# Birke, Kiefer, Urwaldbaum und Akazie JE 144 Flaechen nach innen — die ganze untere
# Kronenhaelfte. Godot culled Rueckseiten, also waren die Kronen von der Seite und von
# unten HOHL (man sah durch den Ballen in den Himmel). Dazu: Palmwedel und Farnwedel
# einseitig (von unten unsichtbar), Birkenringe standen als Kragen vom duenner werdenden
# Stamm ab, der Schnee der Schneetanne schwebte als lose Baender neben den Kraenzen.
#
# REGELN DIESER FASSUNG:
#   * Jedes Teil ist ein GESCHLOSSENER Koerper in einem eigenen bmesh (Ballen = Ikosaeder-
#     kugel, Kranz = Kegel mit Unterseite, Rohr = Zylinderzug mit Deckeln). Nur auf einem
#     geschlossenen Koerper ist die Aussenseite eindeutig; die Ausrichtung wird danach
#     ueber das VORZEICHEN DES VOLUMENS geprueft und notfalls umgedreht (nicht geraten).
#   * Duenne Flaechen (Wedel) werden ausdruecklich ZWEISEITIG gebaut: eigene Eckpunkte
#     fuer die Rueckseite (bmesh verbietet zwei Flaechen ueber dieselben Eckpunkte — die
#     alte Fassung verschluckte genau das per `except ValueError`).
#   * Staemme reichen bis 0.8 m UNTER den Boden: die Platzierung senkt Baeume nur 0.15 m
#     ein, am Hang schwebte die Talseite des Stamms sonst sichtbar ueber dem Gelaende.
#   * Staemme/Aeste werden erst geschlossen ausgerichtet, dann fallen die verdeckten Deckel
#     weg (Fuss im Boden, Enden in der Krone) — sie kosteten nur Eckpunkte.
#
# VERTEX-FARBEN sind Pflicht: TerrainWorld zeichnet alle Flora-MultiMeshes mit dem Flora-
# Shader (ALBEDO = COLOR, sRGB). FLOAT-Farbebene, damit die Werte unveraendert (roh) durch
# den glTF-Export gehen — Byte-Farben haelt Blender fuer sRGB und rechnet sie um.
#
# FARBREGEL (TerrainWorld._ist_laub): Holz, Rinde, Fels haben ROT >= GRUEN, Laub, Nadeln und
# Schnee GRUEN > ROT. Nur Laub bekommt im Spiel weiche Kronennormalen und wird verschweisst.
# (Eine Marke im Alpha ging nicht: der glTF-Export schreibt die Farbe ohne Alpha.)
#
# GROESSEN: Grundmass wie die alten Meshes (Nadelbaum ~10.5 m); die Platzierung skaliert
# mit 1.1..2.0. Achsen: Blender Z = oben (Godot Y). Die Baeume stehen auf z = 0.
#
# Usage: blender --background --python tools/build_baeume.py
#        BAEUME_VORSCHAU=<ordner> ... rendert zusaetzlich eine Artentafel (Workbench)
import bpy
import bmesh
import math
import os
import random
from mathutils import Vector, Matrix, noise

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "models", "world_trees.glb")
BLEND = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     "blender_lib", "baeume.blend")
VORSCHAU = os.environ.get("BAEUME_VORSCHAU", "")

ALPHA_HOLZ = 1.0    # (Alpha kommt nicht durch den Export; die Farbregel oben entscheidet)
ALPHA_LAUB = 1.0

RINDE = (0.30, 0.21, 0.14)
RINDE_HELL = (0.42, 0.31, 0.20)
RINDE_KIEFER = (0.46, 0.26, 0.15)
BIRKE = (0.86, 0.85, 0.80)
BIRKE_FLECK = (0.22, 0.20, 0.19)
TOT = (0.42, 0.38, 0.32)
NADEL = (0.16, 0.40, 0.22)
NADEL_HELL = (0.22, 0.47, 0.26)
KIEFERGRUEN = (0.24, 0.42, 0.20)
BIRKENLAUB = (0.50, 0.66, 0.26)
EICHE = (0.28, 0.47, 0.20)
PALME = (0.30, 0.52, 0.24)
PALME_STAMM = (0.50, 0.40, 0.27)
KOKOS = (0.36, 0.30, 0.16)
BUSCH = (0.34, 0.50, 0.24)
NADEL_KALT = (0.10, 0.25, 0.17)
SCHNEE = (0.88, 0.91, 0.95)   # Gruen > Rot: zaehlt als Laub (Farbregel)
RINDE_URWALD = (0.47, 0.42, 0.34)
URWALD = (0.14, 0.38, 0.13)
URWALD_HELL = (0.22, 0.48, 0.17)
FARN = (0.28, 0.55, 0.20)
FARN_STAMM = (0.26, 0.20, 0.15)
AKAZIE = (0.36, 0.44, 0.19)
RINDE_AKAZIE = (0.34, 0.26, 0.20)
MANGROVE = (0.18, 0.35, 0.17)
MANGROVE_WURZEL = (0.36, 0.30, 0.24)
KAKTUS = (0.33, 0.47, 0.27)
FELS = (0.38, 0.385, 0.40)
MOOS = (0.40, 0.46, 0.30)

UNTER_BODEN = -0.8   # so weit reichen Staemme in den Boden (Hangfuss)


def _mul(c, f):
    return (max(c[0] * f, 0.0), max(c[1] * f, 0.0), max(c[2] * f, 0.0))


def _mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def _hash01(p):
    x = math.sin(p.x * 12.9898 + p.y * 78.233 + p.z * 37.719) * 43758.5453
    return x - math.floor(x)


def _vol(bm):
    """Vorzeichenbehaftetes Volumen (Divergenzsatz). > 0 = Flaechen zeigen nach aussen."""
    s = 0.0
    for f in bm.faces:
        vs = [v.co for v in f.verts]
        for k in range(1, len(vs) - 1):
            s += vs[0].dot(vs[k].cross(vs[k + 1]))
    return s / 6.0


class Baum:
    """Sammelt Teile in EINEM bmesh; jede Ecke bekommt ihre Farbe direkt."""

    def __init__(self, name, seed):
        self.name = name
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Color")
        self.rng = random.Random(seed)
        self.teile = 0

    # --- Einhaengen eines fertigen, GESCHLOSSENEN Teils -----------------------------------
    def _uebernehmen(self, tb, farbe, geschlossen=True, je_flaeche=False, weg=None):
        """tb: eigenes bmesh. farbe(pos, normale, rnd) -> (r, g, b, a) je Ecke.
        rnd (0..1) haengt an der LAGE des Eckpunkts, nicht an der Flaeche: nur dann haben
        alle Ecken an einem Punkt dieselbe Farbe, und der Export kann den Eckpunkt teilen.
        Mit einem Zufall je Flaeche zerfiel jeder weich schattierte Stamm in lauter
        Einzelecken (gemessen: Eiche 586 Eckpunkte statt ~380). je_flaeche=True nur, wo
        harte Flecken gewollt sind (Birkenrinde)."""
        if geschlossen:
            # Ausrichtung ueber das Volumen bestimmen: die Wicklung wird beim Bau schon
            # nach aussen gelegt, das hier faengt nur Fehler ab (nie raten lassen).
            bmesh.ops.recalc_face_normals(tb, faces=tb.faces[:])
            if _vol(tb) < 0.0:
                bmesh.ops.reverse_faces(tb, faces=tb.faces[:])
            tb.normal_update()
        if weg:
            # VERDECKTE DECKEL ERST NACH DEM AUSRICHTEN ENTFERNEN (Stammfuss im Boden, Astende
            # in der Krone): zum Ausrichten muss der Koerper geschlossen sein, sehen kann die
            # Deckel niemand — und an ihrer harten Kante teilte der Export jeden Randpunkt.
            bmesh.ops.delete(tb, geom=weg, context='FACES_ONLY')
        vmap = {}
        for v in tb.verts:
            vmap[v] = self.bm.verts.new(v.co)
        for f in tb.faces:
            try:
                nf = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            rnd_f = self.rng.random()
            n = f.normal.copy()
            for l in nf.loops:
                rnd = rnd_f if je_flaeche else _hash01(l.vert.co)
                l[self.col] = farbe(l.vert.co, n, rnd)
        tb.free()
        self.teile += 1

    @staticmethod
    def einfarbig(c, alpha, streuung=0.0):
        def f(_p, _n, rnd):
            k = 1.0 + (rnd * 2.0 - 1.0) * streuung
            cc = _mul(c, k)
            return (cc[0], cc[1], cc[2], alpha)
        return f

    # --- Rohr: Stamm, Ast, Wurzel, Kaktusarm ------------------------------------------------
    def rohr(self, punkte, radien, farbe, segs=6, rippen=0.0, drall=0.0, deckel=True,
             spitze_oben=False, je_flaeche=False, offen="u"):
        """offen: welche Deckel nach dem Ausrichten wegfallen ("u" unten, "o" oben) —
        Standard unten, weil fast jedes Rohr im Boden oder in einem Stamm beginnt."""
        """Zylinderzug durch `punkte` mit Radius je Punkt, beidseitig gedeckelt (geschlossen).
        Rahmen per Paralleltransport (kein Verdrehen in Kurven). rippen>0: Sternprofil
        (jede zweite Ecke um den Anteil nach innen, Kaktusrippen). spitze_oben: statt eines
        Deckels laeuft das Rohr in einen Punkt aus (Aststummel, Totholz)."""
        pts = [Vector(p) for p in punkte]
        n = len(pts)
        tb = bmesh.new()
        t_alt = None
        nrm = None
        ringe = []
        for i in range(n):
            t = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
            if nrm is None:
                hilf = Vector((1, 0, 0)) if abs(t.x) < 0.9 else Vector((0, 1, 0))
                nrm = t.cross(hilf).normalized()
            else:
                nrm = (t_alt.rotation_difference(t) @ nrm).normalized()
            t_alt = t
            bi = t.cross(nrm).normalized()
            ring = []
            for k in range(segs):
                a = 2.0 * math.pi * k / segs + drall * i
                r = radien[i] * (1.0 - rippen if (rippen > 0.0 and k % 2) else 1.0)
                ring.append(tb.verts.new(pts[i] + (nrm * math.cos(a) + bi * math.sin(a)) * r))
            ringe.append(ring)
        for i in range(n - 1):
            a, b = ringe[i], ringe[i + 1]
            for k in range(segs):
                j = (k + 1) % segs
                tb.faces.new([a[k], a[j], b[j], b[k]])
        weg = []
        if deckel:
            f_u = tb.faces.new(list(reversed(ringe[0])))
            if "u" in offen:
                weg.append(f_u)
            if spitze_oben:
                ende = tb.verts.new(pts[-1] + (pts[-1] - pts[-2]).normalized() * radien[-1] * 1.5)
                for k in range(segs):
                    tb.faces.new([ringe[-1][k], ringe[-1][(k + 1) % segs], ende])
            else:
                f_o = tb.faces.new(ringe[-1])
                if "o" in offen:
                    weg.append(f_o)
        self._uebernehmen(tb, farbe, je_flaeche=je_flaeche, weg=weg)

    # --- Ballen: Laubwolke, Busch, Fels -----------------------------------------------------
    def ballen(self, mitte, radien, farbe, fein=True, beulen=0.10, unten=0.80, drehung=None,
               kanten=0.0):
        """Runder Laubballen: Ikosaederkugel (fein=True: 80 Dreiecke, fein=False: UV-Kugel
        8x4 = 48, fein="winzig": nacktes Ikosaeder = 20), leicht verbeult, Unterseite flacher
        (`unten`). kanten>0 macht daraus einen Fels (grobes, schollenartiges Rauschen statt
        sanfter Beulen).
        ACHTUNG Blender: create_icosphere(subdivisions=1) ist das NACKTE Ikosaeder (20
        Flaechen), erst 2 gibt die 80er-Kugel."""
        tb = bmesh.new()
        if fein == "winzig":
            bmesh.ops.create_icosphere(tb, subdivisions=1, radius=1.0)
        elif fein:
            bmesh.ops.create_icosphere(tb, subdivisions=2, radius=1.0)
        else:
            bmesh.ops.create_uvsphere(tb, u_segments=8, v_segments=4, radius=1.0)
        off = Vector((self.rng.uniform(-50, 50), self.rng.uniform(-50, 50),
                      self.rng.uniform(-50, 50)))
        rx, ry, rz = radien
        dz = self.rng.uniform(0.0, 2.0 * math.pi) if drehung is None else drehung
        rot = Matrix.Rotation(dz, 3, 'Z')
        m = Vector(mitte)
        for v in tb.verts:
            d = v.co.normalized()
            if kanten > 0.0:
                k = 1.0 + kanten * noise.noise(d * 1.4 + off) + 0.35 * kanten * noise.noise(
                    d * 3.1 + off)
            else:
                k = 1.0 + beulen * noise.noise(d * 2.2 + off)
            p = d * k
            if p.z < 0.0:
                p.z *= unten
            v.co = m + rot @ Vector((p.x * rx, p.y * ry, p.z * rz))
        self._uebernehmen(tb, farbe)

    # --- Kranz: ein Astkranz eines Nadelbaums ---------------------------------------------
    def kranz(self, z0, z1, r, farbe, zweige=8, zacken=0.28, haengen=0.45, unter=0.22,
              farbe_fn=None):
        """Kegel mit gezacktem, haengendem Rand UND geschlossener Unterseite. Die Zweig-
        spitzen (aeussere Zacken) haengen tiefer als die Kerben dazwischen — so liest sich
        der Kranz als Astlage statt als gedrechselter Kegel."""
        tb = bmesh.new()
        spitze = tb.verts.new((0.0, 0.0, z1))
        unterpunkt = tb.verts.new((0.0, 0.0, z0 + (z1 - z0) * unter))
        phase = self.rng.uniform(0.0, 2.0 * math.pi)
        rand = []
        n = zweige * 2
        for i in range(n):
            a = phase + 2.0 * math.pi * (i + self.rng.uniform(-0.18, 0.18)) / n
            tip = i % 2 == 0
            rr = r * (1.0 if tip else 1.0 - zacken) * self.rng.uniform(0.92, 1.06)
            zz = z0 - (haengen if tip else haengen * 0.25) * self.rng.uniform(0.75, 1.25)
            rand.append(tb.verts.new((math.cos(a) * rr, math.sin(a) * rr, zz)))
        for i in range(n):
            j = (i + 1) % n
            tb.faces.new([rand[i], rand[j], spitze])
            tb.faces.new([rand[j], rand[i], unterpunkt])
        f = farbe_fn or self.einfarbig(farbe, ALPHA_LAUB, 0.08)
        self._uebernehmen(tb, f)

    # --- Wedel: Palme, Farn (duenn -> zweiseitig) ------------------------------------------
    def wedel(self, wurzel, richtung, laenge, breite, farbe, knick=0.5, stationen=4, falz=0.0):
        """Wedel als Band laengs einer abknickenden Mittelrippe, links/rechts spitz zulaufend.
        falz > 0 hebt die Mittelrippe an (V-Falte wie bei Palmblaettern). ZWEISEITIG: die
        Rueckseite bekommt eigene Eckpunkte und die umgekehrte Wicklung."""
        w = Vector(wurzel)
        d = Vector(richtung).normalized()
        seit = d.cross(Vector((0, 0, 1)))
        if seit.length < 0.01:
            seit = Vector((1, 0, 0))
        seit.normalize()
        auf = seit.cross(d).normalized()
        if auf.z < 0.0:
            auf = -auf
        mitte = []
        links = []
        rechts = []
        for k in range(stationen + 1):
            t = k / float(stationen)
            p = w + d * (laenge * t)
            p.z -= knick * laenge * t * t
            b = breite * math.sin(math.pi * min(0.12 + t * 0.95, 1.0)) * (1.0 - 0.35 * t)
            if k == 0:
                b = breite * 0.15
            mitte.append(p + auf * (falz * b))
            links.append(p - seit * b)
            rechts.append(p + seit * b)
        c = (farbe[0], farbe[1], farbe[2], ALPHA_LAUB)
        for seite in (0, 1):
            vm = [self.bm.verts.new(p) for p in mitte]
            vl = [self.bm.verts.new(p) for p in links]
            vr = [self.bm.verts.new(p) for p in rechts]
            flaechen = []
            for k in range(stationen):
                fl = [vl[k], vm[k], vm[k + 1], vl[k + 1]]
                fr = [vm[k], vr[k], vr[k + 1], vm[k + 1]]
                if seite == 1:
                    fl.reverse()
                    fr.reverse()
                flaechen.append(self.bm.faces.new(fl))
                flaechen.append(self.bm.faces.new(fr))
            for fa in flaechen:
                for l in fa.loops:
                    l[self.col] = c
        self.teile += 1

    # --- Brettwurzel: duenne, geschlossene Rippe am Stammfuss --------------------------------
    def brett(self, winkel, weit, hoch, dick, farbe):
        ca, sa = math.cos(winkel), math.sin(winkel)
        q = Vector((-sa, ca, 0.0)) * dick * 0.5
        a = Vector((ca * 0.25, sa * 0.25, hoch))
        b = Vector((ca * 0.25, sa * 0.25, UNTER_BODEN))
        c = Vector((ca * weit, sa * weit, UNTER_BODEN))
        tb = bmesh.new()
        v = [tb.verts.new(p) for p in (a + q, b + q, c + q, a - q, b - q, c - q)]
        tb.faces.new([v[0], v[1], v[2]])
        tb.faces.new([v[5], v[4], v[3]])
        tb.faces.new([v[0], v[2], v[5], v[3]])
        tb.faces.new([v[1], v[0], v[3], v[4]])
        tb.faces.new([v[2], v[1], v[4], v[5]])
        self._uebernehmen(tb, self.einfarbig(farbe, ALPHA_HOLZ, 0.06))

    def objekt(self, kante_grad=95.0):
        """kante_grad: Flaechen, die flacher als dieser Winkel aneinanderstossen, werden weich
        schattiert — 95 Grad, damit auch sechs- und vierseitige Staemme und Aeste rund wirken
        (bei 48 Grad blieben sie kantig und der Export teilte jeden Eckpunkt); der Fels nimmt
        62 Grad und behaelt seine Grate. Flach schattierte Sechseck-
        Staemme waren das letzte Low-Poly-Merkmal. Das Laub bekommt seine Normalen ohnehin in
        TerrainWorld._weiche_krone."""
        me = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(flora_material())
        me.set_sharp_from_angle(angle=math.radians(kante_grad))
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


def holz(c, streuung=0.08):
    return Baum.einfarbig(c, ALPHA_HOLZ, streuung)


def laub(c, streuung=0.06):
    return Baum.einfarbig(c, ALPHA_LAUB, streuung)


# --- die Arten --------------------------------------------------------------------------------
def fichte():
    b = Baum("Fichte", 11)
    # Stammfuss verbreitert (Wurzelanlauf), laeuft bis in die Spitze
    # Der Stamm reicht nur bis in den zweiten Kranz — darueber sieht ihn niemand.
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.0), (0, 0, 0.5), (0, 0, 3.4)],
           [0.40, 0.40, 0.27, 0.20], holz(RINDE), segs=6, offen="uo")
    kraenze = [(1.35, 4.7, 2.70), (2.65, 5.9, 2.35), (3.95, 7.1, 1.98), (5.25, 8.3, 1.58),
               (6.55, 9.5, 1.15), (7.85, 10.6, 0.74)]
    for i, (z0, z1, r) in enumerate(kraenze):
        f = NADEL if i % 2 == 0 else NADEL_HELL
        b.kranz(z0, z1, r, f, zweige=8, zacken=0.30, haengen=0.48 * (r / 2.7) + 0.12)
    return b.objekt()


def schneetanne():
    """Nordland: schmale, dunkle Tanne. SCHNEE ALS FARBE, nicht als eigene Geometrie: die
    Kerben zwischen den Zweigspitzen und die Spitze jedes Kranzes tragen Weiss, die haengenden
    Zweigspitzen und die Unterseite bleiben dunkel. Von oben (so sieht man Baeume im Flug)
    ergibt das einen weissen Stern auf jedem Kranz; die alte Fassung legte Baender NEBEN die
    Kraenze, die sichtbar in der Luft standen."""
    b = Baum("Schneetanne", 88)
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.0), (0, 0, 0.5), (0, 0, 3.0)],
           [0.34, 0.34, 0.22, 0.17], holz(RINDE), segs=6, offen="uo")

    def schnee_fn(z0, z1, r):
        def f(p, n, rnd):
            if n.z < -0.05:                      # Unterseite: tiefes Nadelgruen
                c = _mul(NADEL_KALT, 0.85)
            else:
                # Oberseite: die KERBEN (rr ~0.66) und die Spitze tragen Schnee, die
                # haengenden Zweigspitzen (rr ~1) bleiben dunkel. Ein Verlauf nach der Hoehe
                # zeigte nur die Spitze weiss — das Innere jedes Kranzes verdeckt der naechste.
                rr = math.hypot(p.x, p.y) / max(r, 0.01)
                s = min(max((0.95 - rr) / 0.22, 0.0), 1.0)
                c = _mix(NADEL_KALT, SCHNEE, s)
            return (c[0], c[1], c[2], ALPHA_LAUB)
        return f

    kraenze = [(1.2, 4.3, 2.15), (2.55, 5.6, 1.85), (3.9, 6.9, 1.52), (5.25, 8.2, 1.18),
               (6.6, 9.5, 0.84), (7.9, 10.6, 0.52)]
    for z0, z1, r in kraenze:
        b.kranz(z0, z1, r, NADEL_KALT, zweige=7, zacken=0.34, haengen=0.30,
                farbe_fn=schnee_fn(z0, z1, r))
    return b.objekt()


def kiefer():
    """Waldkiefer: hoher, leicht gebogener Stamm (unten grau, oben fuchsrot), die Krone
    als flache Wolkenschichten ganz oben."""
    b = Baum("Kiefer", 22)
    p = [(0, 0, UNTER_BODEN), (0, 0, 0.0), (0.12, 0.05, 2.6), (0.34, 0.02, 5.1),
         (0.40, -0.08, 7.2), (0.34, -0.10, 8.7)]
    r = [0.34, 0.33, 0.26, 0.21, 0.17, 0.12]

    def rinde(pos, _n, rnd):
        c = _mix(RINDE, RINDE_KIEFER, min(max((pos.z - 2.0) / 3.0, 0.0), 1.0))
        c = _mul(c, 0.92 + 0.16 * rnd)
        return (c[0], c[1], c[2], ALPHA_HOLZ)

    b.rohr(p, r, rinde, segs=6, offen="uo")
    kopf = Vector(p[4])
    aeste = [((1.55, 0.55, 8.5), (1.55, 1.35, 0.92)), ((-1.25, -0.7, 8.15), (1.45, 1.30, 0.86)),
             ((0.1, 1.40, 9.05), (1.35, 1.25, 0.84)), ((0.55, -0.40, 9.55), (1.70, 1.50, 0.98)),
             ((-0.55, 0.55, 9.95), (1.15, 1.10, 0.80))]
    for ziel, rad in aeste[:4]:
        z = Vector(ziel)
        mid = kopf.lerp(z, 0.5) + Vector((0, 0, 0.35))
        b.rohr([kopf, mid, z], [0.13, 0.09, 0.06], rinde, segs=4, offen="uo")
    for i, (ziel, rad) in enumerate(aeste):
        b.ballen(ziel, rad, laub(KIEFERGRUEN), unten=0.62, fein=(i == 3))
    return b.objekt()


def birke():
    """Birke: schlanker weisser Stamm mit dunklen Querflecken (Farbe je Flaeche, keine
    abstehenden Ringe mehr), lockere hohe Krone aus hellgruenen Ballen."""
    b = Baum("Birke", 33)
    pts = [(0, 0, UNTER_BODEN)]
    rad = [0.21]
    for k in range(7):
        z = k * 0.78
        pts.append((0.06 * math.sin(z * 0.9), 0.04 * math.sin(z * 0.6 + 1.0), z))
        rad.append(0.20 - z * 0.012)

    def rinde(pos, _n, rnd):
        # dunkle Flecken aus dem Eckpunkt-Zufall, unten (Borke) dunkel
        c = BIRKE_FLECK if (rnd < 0.30 or pos.z < 0.35) else _mul(BIRKE, 0.96 + 0.06 * rnd)
        return (c[0], c[1], c[2], ALPHA_HOLZ)

    b.rohr(pts, rad, rinde, segs=5, offen="uo")
    for ziel in ((0.9, 0.35, 5.6), (-0.8, 0.45, 5.3), (0.15, -0.85, 5.9)):
        b.rohr([(0.06, 0.02, 3.9), ziel], [0.08, 0.05], rinde, segs=4, offen="uo")
    # Hohes, lockeres Oval: ein grosser Kern, drei seitliche Wolken, die ihn nur wenig
    # ueberragen. Fuenf gleich grosse Kugeln sahen aus wie eine Weintraube.
    kronen = [((0.08, 0.02, 6.35), (1.45, 1.35, 2.05)), ((0.75, 0.30, 5.55), (1.05, 0.98, 1.20)),
              ((-0.70, 0.40, 5.75), (1.00, 0.95, 1.15)), ((0.20, -0.72, 6.85), (0.95, 0.90, 1.10))]
    for i, (m, r) in enumerate(kronen):
        b.ballen(m, r, laub(BIRKENLAUB), beulen=0.12, unten=0.85, fein=(i == 0))
    return b.objekt()


def eiche():
    """Eiche: kurzer, dicker Stamm mit Wurzelanlauf, kraeftige Aeste, breite Kuppel aus
    grossen Laubwolken."""
    b = Baum("Eiche", 44)
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.0), (0, 0, 0.3), (0.05, 0.0, 1.5), (0.1, 0.05, 2.7)],
           [0.80, 0.80, 0.58, 0.46, 0.40], holz(RINDE, 0.10), segs=6, offen="uo")
    kopf = Vector((0.1, 0.05, 2.6))
    wolken = [((0.15, 0.10, 6.15), (2.35, 2.20, 1.75)), ((1.95, 0.55, 5.05), (1.75, 1.60, 1.35)),
              ((-1.80, 0.85, 5.10), (1.70, 1.65, 1.30)), ((0.35, -1.90, 5.20), (1.65, 1.55, 1.30)),
              ((-0.60, -1.00, 6.60), (1.35, 1.30, 1.10))]
    for i, (m, r) in enumerate(wolken[:4]):
        z = Vector(m) - Vector((0, 0, 0.6))
        mid = kopf.lerp(z, 0.45) + Vector((0, 0, 0.25))
        b.rohr([kopf, mid, z], [0.30, 0.20, 0.12], holz(RINDE_HELL), segs=4, offen="uo")
    for i, (m, r) in enumerate(wolken):
        b.ballen(m, r, laub(EICHE), fein=(i == 0))
    return b.objekt()


def palme():
    """Kokospalme: geschwungener Stamm mit Ringen, Kokosnuesse, gefaltete Wedel (zweiseitig)."""
    b = Baum("Palme", 55)
    pts = [(0, 0, UNTER_BODEN)]
    rad = [0.34]
    for k in range(8):
        t = k / 7.0
        pts.append((1.15 * t * t, 0.25 * t * t, 6.2 * t))
        rad.append(0.32 - 0.13 * t)

    def ringe(pos, _n, rnd):
        band = int(max(pos.z, 0.0) / 0.45) % 2
        c = _mul(PALME_STAMM, 0.84 if band else 1.0)
        c = _mul(c, 0.95 + 0.08 * rnd)
        return (c[0], c[1], c[2], ALPHA_HOLZ)

    b.rohr(pts, rad, ringe, segs=5, offen="uo")
    kopf = Vector(pts[-1])
    for a in (0.3, 2.4, 4.4):
        b.ballen(kopf + Vector((math.cos(a) * 0.30, math.sin(a) * 0.30, -0.25)),
                 (0.22, 0.22, 0.24), holz(KOKOS, 0.1), fein="winzig")
    for i in range(9):
        a = 2.0 * math.pi * i / 9 + 0.2 + b.rng.uniform(-0.12, 0.12)
        hoch = 0.55 if i % 2 else 0.25
        d = Vector((math.cos(a), math.sin(a), hoch))
        f = PALME if i % 3 else _mul(PALME, 0.86)
        b.wedel(kopf + Vector((0, 0, 0.15)), d, 3.2, 0.62, f, knick=0.55, stationen=3, falz=0.35)
    return b.objekt()


def totholz():
    b = Baum("Totholz", 66)
    f = holz(TOT, 0.14)
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.0), (0.1, 0.06, 2.2), (0.24, 0.0, 4.2), (0.18, -0.12, 5.6)],
           [0.40, 0.38, 0.27, 0.18, 0.11], f, segs=5, spitze_oben=True)
    for start, mitte, ende, rr in (((0.1, 0.06, 2.3), (0.9, 0.3, 2.9), (1.55, 0.4, 3.6), 0.14),
                                   ((0.2, 0.0, 3.6), (-0.6, 0.4, 3.9), (-1.35, 0.75, 4.6), 0.12),
                                   ((0.22, 0.0, 4.4), (0.45, -0.6, 4.7), (0.65, -1.25, 5.3), 0.10),
                                   ((0.18, -0.1, 5.2), (-0.3, -0.35, 5.6), (-0.75, -0.55, 6.2), 0.08)):
        b.rohr([start, mitte, ende], [rr, rr * 0.7, rr * 0.4], f, segs=4, spitze_oben=True)
    return b.objekt()


def busch():
    b = Baum("Busch", 77)
    b.ballen((0.0, 0.0, 0.62), (0.95, 0.90, 0.80), laub(BUSCH), unten=0.6)
    for m, r in (((0.62, 0.28, 0.42), (0.66, 0.62, 0.56)), ((-0.52, 0.36, 0.38), (0.60, 0.58, 0.52)),
                 ((0.12, -0.58, 0.36), (0.58, 0.55, 0.50))):
        b.ballen(m, r, laub(_mul(BUSCH, 0.93)), fein=False, unten=0.6)
    return b.objekt()


def urwaldbaum():
    """Suedland: Urwaldriese — Brettwurzeln, hoher glatter Stamm, breite Schirmkrone."""
    b = Baum("Urwaldbaum", 99)
    for k, a in enumerate((0.3, 1.9, 3.4, 4.9)):
        b.brett(a, 1.55 + 0.25 * (k % 2), 2.4 + 0.3 * (k % 2), 0.22, RINDE_URWALD)
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.0), (0.12, 0.06, 4.0), (0.2, 0.1, 7.5), (0.1, -0.1, 11.0)],
           [0.62, 0.60, 0.48, 0.40, 0.30], holz(RINDE_URWALD), segs=6, offen="uo")
    kopf = Vector((0.1, -0.1, 10.6))
    wolken = [((2.6, 0.6, 11.9), (2.45, 2.25, 1.05), URWALD),
              ((-2.25, 1.35, 11.6), (2.30, 2.20, 1.00), URWALD_HELL),
              ((0.45, -2.5, 11.95), (2.35, 2.25, 1.05), URWALD),
              ((0.1, 0.25, 13.05), (2.75, 2.60, 1.20), URWALD_HELL),
              ((-1.3, -1.6, 12.6), (1.80, 1.70, 0.90), URWALD)]
    for m, r, c in wolken[:3]:
        z = Vector(m) - Vector((0, 0, 0.4))
        b.rohr([kopf, kopf.lerp(z, 0.5) + Vector((0, 0, 0.3)), z], [0.24, 0.16, 0.10],
               holz(RINDE_URWALD), segs=4, offen="uo")
    for i, (m, r, c) in enumerate(wolken):
        b.ballen(m, r, laub(c), unten=0.6, fein=(i == 3))
    return b.objekt()


def baumfarn():
    """Suedland: schlanker Stamm, ein Stern aus gebogenen Wedeln (zweiseitig)."""
    b = Baum("Baumfarn", 111)
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.0), (0.15, 0.05, 2.4), (0.25, 0.0, 4.6)],
           [0.24, 0.23, 0.19, 0.16], holz(FARN_STAMM, 0.12), segs=5, offen="uo")
    kopf = Vector((0.25, 0.0, 4.6))
    b.ballen(kopf + Vector((0, 0, 0.1)), (0.34, 0.34, 0.30), laub(_mul(FARN, 0.8)), fein=False)
    for i in range(10):
        a = 2.0 * math.pi * i / 10 + 0.15 + b.rng.uniform(-0.1, 0.1)
        d = Vector((math.cos(a), math.sin(a), 0.80 if i % 2 else 0.45))
        b.wedel(kopf, d, 2.5, 0.55, FARN if i % 2 else _mul(FARN, 0.86), knick=0.72,
                stationen=3, falz=0.12)
    return b.objekt()


def akazie():
    """Westland: kurzer Stamm, der sich gabelt, darauf eine flache Schirmkrone."""
    b = Baum("Akazie", 122)
    f = holz(RINDE_AKAZIE, 0.10)
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.0), (0.05, 0.0, 1.2), (0.1, 0.0, 2.2)],
           [0.30, 0.29, 0.24, 0.21], f, segs=6, offen="uo")
    enden = ((1.5, 0.5, 4.7), (-1.3, 0.75, 4.55), (0.2, -1.4, 4.8))
    for e in enden:
        ev = Vector(e)
        b.rohr([(0.1, 0.0, 2.1), Vector((0.1, 0.0, 2.1)).lerp(ev, 0.5) + Vector((0, 0, -0.15)), ev],
               [0.15, 0.11, 0.08], f, segs=4, offen="uo")
    for m, r in (((0.0, 0.0, 5.35), (2.70, 2.50, 0.62)), ((1.35, 0.45, 5.05), (1.90, 1.75, 0.52)),
                 ((-1.25, 0.70, 4.95), (1.85, 1.70, 0.50)), ((0.25, -1.30, 5.10), (1.85, 1.70, 0.52))):
        b.ballen(m, r, laub(AKAZIE), unten=0.55, fein=(m[2] > 5.3))
    return b.objekt()


def mangrove():
    """Suedland: Krone auf einem Buendel gebogener Stelzwurzeln ueber dem Schlamm."""
    b = Baum("Mangrove", 133)
    f = holz(MANGROVE_WURZEL, 0.10)
    # Stelzwurzeln als BOEGEN (vier Punkte), nicht mit Knick — mit Knick lasen sie sich
    # wie Spinnenbeine.
    for i in range(7):
        a = 2.0 * math.pi * i / 7 + 0.4 + b.rng.uniform(-0.15, 0.15)
        w = 1.55 + b.rng.uniform(-0.2, 0.25)
        ca, sa = math.cos(a), math.sin(a)
        b.rohr([(ca * w, sa * w, UNTER_BODEN), (ca * w * 0.92, sa * w * 0.92, 0.55),
                (ca * w * 0.62, sa * w * 0.62, 1.35), (ca * 0.22, sa * 0.22, 1.85)],
               [0.10, 0.10, 0.11, 0.14], f, segs=4, offen="uo")
    b.rohr([(0, 0, 1.5), (0.05, 0.05, 2.6), (0.1, 0.1, 3.5)], [0.24, 0.20, 0.16], f, segs=5,
           offen="uo")
    for m, r in (((0.75, 0.2, 4.2), (1.65, 1.55, 1.15)), ((-0.7, 0.5, 4.0), (1.55, 1.50, 1.10)),
                 ((0.1, -0.65, 4.7), (1.70, 1.60, 1.20)), ((0.0, 0.3, 5.1), (1.10, 1.05, 0.85))):
        b.ballen(m, r, laub(MANGROVE), unten=0.65, fein=(m[2] == 4.7))
    return b.objekt()


def kaktus():
    """Westland: Saguaro — gerippte Saeule mit zwei Armen, runde Koepfe."""
    b = Baum("Kaktus", 144)
    f = holz(KAKTUS, 0.05)
    # Die Saeule endet in einer Kuppel: zwei Ringe mit kleiner werdendem Radius
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.0), (0, 0, 2.6), (0, 0, 4.9), (0, 0, 5.25), (0, 0, 5.42)],
           [0.42, 0.42, 0.40, 0.37, 0.28, 0.12], f, segs=10, rippen=0.14)
    for seite, hoehe, laenge in ((1.0, 2.1, 1.9), (-1.0, 3.0, 1.45)):
        s = seite
        b.rohr([(0, 0, hoehe), (s * 0.62, 0, hoehe + 0.08), (s * 0.92, 0, hoehe + 0.45),
                (s * 0.95, 0, hoehe + 0.45 + laenge), (s * 0.95, 0, hoehe + 0.66 + laenge)],
               [0.25, 0.25, 0.24, 0.22, 0.09], f, segs=8, rippen=0.14, offen="u")
    return b.objekt()


def fels():
    """Felsbrocken fuer Haenge und Hochlagen (ersetzt den prozeduralen Doppelkegel in
    TerrainWorld._build_rock_mesh). Masse wie dort: Radius ~1, Fuss bei -0.5 im Boden, oben
    ~1.3; die Platzierung streckt ihn je Achse 0.5..2.6. Oben ein Hauch Moos."""
    b = Baum("Fels", 155)

    def farbe(p, n, rnd):
        c = _mul(FELS, 0.92 + 0.12 * rnd)
        if n.z > 0.45:
            c = _mix(c, MOOS, min((n.z - 0.45) * 1.6, 0.55))
        return (c[0], c[1], c[2], ALPHA_HOLZ)

    b.ballen((0.0, 0.0, 0.35), (1.05, 0.95, 0.95), farbe, kanten=0.20, unten=0.9, drehung=0.4)
    return b.objekt(kante_grad=62.0)


ARTEN = [fichte, kiefer, birke, eiche, palme, totholz, busch, schneetanne, urwaldbaum, baumfarn,
         akazie, mangrove, kaktus, fels]


def pruefen(obs):
    """Belegt die Regeln oben: jede geschlossene Insel mit POSITIVEM Volumen (nach aussen
    gewickelt), offene Kanten nur an den Wedeln."""
    fehler = 0
    for ob in obs:
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.faces.ensure_lookup_table()
        gesehen = set()
        innen = 0
        offen_inseln = 0
        for f in bm.faces:
            if f.index in gesehen:
                continue
            insel = []
            stapel = [f]
            gesehen.add(f.index)
            while stapel:
                g = stapel.pop()
                insel.append(g)
                for e in g.edges:
                    for h in e.link_faces:
                        if h.index not in gesehen:
                            gesehen.add(h.index)
                            stapel.append(h)
            offen = any(len(e.link_faces) != 2 for g in insel for e in g.edges)
            if offen:
                offen_inseln += 1
                continue
            s = 0.0
            for g in insel:
                vs = [v.co for v in g.verts]
                for k in range(1, len(vs) - 1):
                    s += vs[0].dot(vs[k].cross(vs[k + 1]))
            if s <= 0.0:
                innen += 1
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        hoch = max(v.co.z for v in ob.data.vertices)
        breit = max(max(abs(v.co.x), abs(v.co.y)) for v in ob.data.vertices)
        print("  %-12s %4d Tris  Hoehe %5.2f  Breite %4.2f  verkehrt %d  offene Inseln %d"
              % (ob.name, tris, hoch, breit * 2, innen, offen_inseln))
        fehler += innen
        bm.free()
    # Offene Inseln sind erwartet: Wedel (zweiseitig) und Rohre ohne verdeckte Deckel. Ihre
    # Wicklung wurde vor dem Entfernen am geschlossenen Koerper festgelegt (_uebernehmen).
    print("PRUEFUNG: %s" % ("OK — keine verkehrt gewickelte Insel" if fehler == 0
                            else "%d VERKEHRTE INSELN" % fehler))
    return fehler


def vorschau(obs):
    scn = bpy.context.scene
    x = 0.0
    for ob in obs:
        ob.location.x = x
        x += 9.0
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scn.collection.objects.link(cam)
    scn.camera = cam
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'VERTEX'
    scn.display.shading.show_shadows = True
    scn.render.resolution_x = 2400
    scn.render.resolution_y = 700
    mitte = Vector((x * 0.5 - 4.5, 0.0, 5.0))
    for name, rich in (("seite", Vector((0.0, -1.0, 0.08))), ("oben", Vector((0.0, -1.0, 0.9))),
                       ("unten", Vector((0.0, -1.0, -0.35)))):
        cam.location = mitte + rich.normalized() * 95.0
        cam.rotation_euler = (mitte - cam.location).to_track_quat('-Z', 'Y').to_euler()
        cam.data.lens = 50
        scn.render.filepath = os.path.join(VORSCHAU, "baeume_%s.png" % name)
        bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    obs = [fn() for fn in ARTEN]
    fehler = pruefen(obs)
    bpy.ops.object.select_all(action='SELECT')
    kw = dict(filepath=OUT, export_format='GLB', use_selection=False, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(export_vertex_color='ACTIVE', **kw)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    print("EXPORT", OUT, "(%d Arten)" % len(obs))
    # Zum Ansehen in Blender: dieselben Arten nebeneinander in blender_lib/baeume.blend (die
    # Datei ist nur Anschauung — das Spiel liest ausschliesslich das glb oben).
    for i, ob in enumerate(obs):
        ob.location.x = i * 9.0
    bpy.ops.wm.save_mainfile(filepath=BLEND)
    print("GESPEICHERT", BLEND)
    if VORSCHAU:
        vorschau(obs)
    if fehler:
        raise SystemExit(1)


main()
