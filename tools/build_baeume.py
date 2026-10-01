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
# DRITTE FASSUNG (2026-10), nach Spielbildern: der Nadelwald (der Grossteil der Insel) stand
# als Stapel glatter Zackenkegel da — Papierhuetchen in einem einzigen Smaragdgruen —, die
# Laubkronen als drei bis fuenf Kugeln mit sechseckigem Umriss, die Birken neongelb.
#   * NADELBAEUME: `Baum.etage` statt des geraden Zackenkegels — jede Astlage ist eine
#     GLOCKE aus haengenden Zweigen mit Ruecken und Kerben; die Etagen sind flach und liegen
#     so weit auseinander, dass unter jeder ein Schattenspalt bleibt. Farbe nach der ROLLE
#     des Punkts (heller Ruecken, helle Spitze, dunkle Kerbe): von oben, im Flug, ein Stern
#     aus Zweigen. Gleiches Dreiecksbudget wie vorher (Fichte 236 statt 228).
#   * LAUBKRONEN: `Baum.krone` — ein grosser Kern (80 Dreiecke), drei bis vier Wolken und
#     ein, zwei Buckel aus der 60er-Kugel ("mittel"; die UV-Kugel 8x4 mit ihren flachen
#     Polen ist raus). Jeder zweite Ballen in der helleren Laubfarbe.
#   * Das LICHT (Schatten in den Fugen zwischen den Ballen, Verlauf, Normalen) entsteht
#     nicht hier, sondern beim Laden: TerrainWorld._weiche_krone. Hier nur Form und Farbe.
#   * Sichtprobe ohne Welt: tools/_baum_probe.gd (Nahaufnahmen, Probewald, Fernstufe).
#
# REGELN (seit der zweiten Fassung):
#   * Jedes Teil ist ein GESCHLOSSENER Koerper in einem eigenen bmesh (Ballen = Ikosaeder-
#     kugel, Etage = Glocke mit Unterseite, Rohr = Zylinderzug mit Deckeln). Nur auf einem
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
# NADELGRUEN in drei Stufen: tief im Inneren der Etage, Flaeche, frische Zweigspitze. Bewusst
# gedeckter und blauer als die Wiese (shaders/palette.gdshaderinc: GRAS_TIEF 0.11/0.28/0.21)
# — das alte 0.16/0.40/0.22 stand unter der warmen Sonne als Smaragd-Plastik im Bild.
NADEL_TIEF = (0.10, 0.26, 0.19)
NADEL = (0.17, 0.38, 0.22)
NADEL_SPITZE = (0.30, 0.49, 0.23)
KIEFERGRUEN = (0.20, 0.38, 0.21)
KIEFER_HELL = (0.28, 0.45, 0.22)
# Birke: frisches, aber nicht mehr neongelbes Gruen (0.50/0.66/0.26 leuchtete aus jedem
# Waldbild als gelbe Punkte heraus).
BIRKENLAUB = (0.36, 0.55, 0.25)
BIRKE_HELL = (0.45, 0.62, 0.27)
EICHE = (0.24, 0.43, 0.20)
EICHE_HELL = (0.32, 0.50, 0.21)
PALME = (0.28, 0.50, 0.24)
PALME_STAMM = (0.50, 0.40, 0.27)
KOKOS = (0.36, 0.30, 0.16)
BUSCH = (0.30, 0.47, 0.23)
NADEL_KALT = (0.09, 0.23, 0.18)
SCHNEE = (0.88, 0.91, 0.95)   # Gruen > Rot: zaehlt als Laub (Farbregel)
RINDE_URWALD = (0.47, 0.42, 0.34)
URWALD = (0.13, 0.36, 0.14)
URWALD_HELL = (0.21, 0.46, 0.17)
FARN = (0.26, 0.52, 0.20)
FARN_STAMM = (0.26, 0.20, 0.15)
AKAZIE = (0.34, 0.43, 0.19)
AKAZIE_HELL = (0.41, 0.48, 0.20)
RINDE_AKAZIE = (0.34, 0.26, 0.20)
MANGROVE = (0.17, 0.35, 0.18)
MANGROVE_HELL = (0.23, 0.42, 0.19)
MANGROVE_WURZEL = (0.36, 0.30, 0.24)
KAKTUS = (0.33, 0.47, 0.27)
FELS_TIEF = (0.34, 0.34, 0.35)   # Rot >= Gruen: zaehlt nicht als Laub
FELS_HELL = (0.56, 0.54, 0.50)
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
        """Runder Laubballen: Ikosaederkugel (fein=True: 80 Dreiecke, fein="mittel": 60,
        fein=False: UV-Kugel 8x4 = 48, fein="winzig": nacktes Ikosaeder = 20), leicht
        verbeult, Unterseite flacher
        (`unten`). kanten>0 macht daraus einen Fels (grobes, schollenartiges Rauschen statt
        sanfter Beulen).
        ACHTUNG Blender: create_icosphere(subdivisions=1) ist das NACKTE Ikosaeder (20
        Flaechen), erst 2 gibt die 80er-Kugel."""
        tb = bmesh.new()
        if fein == "winzig":
            bmesh.ops.create_icosphere(tb, subdivisions=1, radius=1.0)
        elif fein == "mittel":
            # 60 Dreiecke / 32 Eckpunkte: Ikosaeder, jede Flaeche mit einem Mittelpunkt auf
            # der Kugel. Deutlich runder als die UV-Kugel 8x4 (48 Dreiecke, zwei Pole mit
            # flachem Deckel — flachgedrueckt stand die als Sechseckteller im Bild).
            bmesh.ops.create_icosphere(tb, subdivisions=1, radius=1.0)
            bmesh.ops.poke(tb, faces=tb.faces[:])
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

    # --- Etage: eine Astlage als GLOCKE aus haengenden Zweigen -----------------------------
    def etage(self, z_fuss, z_kopf, r, farbe_fn, zweige=7, haengen=0.5, schulter=0.56,
              wulst=0.18, zacken=0.24, versatz=0.07):
        """Astetage eines Nadelbaums. Der alte `kranz` war ein gerader Kegel mit Zackenrand:
        im Spiel ein Stapel Papierhuetchen. Hier hat jeder Zweig einen RUECKEN (Schulterpunkt
        auf der Zweigachse, ueber der Geraden Kopf-Rand) und faellt von dort zur haengenden
        Spitze ab; zwischen den Zweigen liegt eine Kerbe. Das gibt im Profil eine Glocke und
        von oben einen Stern aus Lappen. Geschlossen (Unterseite), 6 Dreiecke je Zweig.
        farbe_fn(teil, rnd) -> (r, g, b) mit teil = "kopf", "ruecken", "spitze", "kerbe"
        oder "unter": die Farbe haengt an der ROLLE des Punkts, nicht nur am Abstand — helle
        Ruecken und Spitzen gegen dunkle Kerben zeichnen von oben (Flugblick) den Stern aus
        Zweigen; nach dem Abstand allein war die Etage von oben ein glattes Vieleck."""
        mx = self.rng.uniform(-versatz, versatz)
        my = self.rng.uniform(-versatz, versatz)
        hoch = z_kopf - z_fuss
        tb = bmesh.new()
        kopf = tb.verts.new((mx, my, z_kopf))
        z_unter = z_fuss + hoch * 0.16
        unterpunkt = tb.verts.new((mx, my, z_unter))
        phase = self.rng.uniform(0.0, 2.0 * math.pi)
        wink = []
        lang = []
        for i in range(zweige):
            wink.append(phase + 2.0 * math.pi * (i + self.rng.uniform(-0.17, 0.17)) / zweige)
            lang.append(self.rng.uniform(0.86, 1.10))
        schultern = []
        spitzen = []
        kerben = []
        for i in range(zweige):
            a = wink[i]
            la = lang[i]
            ca, sa = math.cos(a), math.sin(a)
            schultern.append(tb.verts.new((mx + ca * r * schulter * la, my + sa * r * schulter * la,
                                           z_fuss + hoch * (1.0 - schulter + wulst))))
            spitzen.append(tb.verts.new((mx + ca * r * la, my + sa * r * la,
                                         z_fuss - haengen * self.rng.uniform(0.8, 1.2))))
            j = (i + 1) % zweige
            a2 = wink[j] + (2.0 * math.pi if j == 0 else 0.0)
            am = (a + a2) * 0.5
            rk = r * (1.0 - zacken) * (la + lang[j]) * 0.5
            kerben.append(tb.verts.new((mx + math.cos(am) * rk, my + math.sin(am) * rk,
                                        z_fuss - haengen * 0.35)))
        for i in range(zweige):
            j = (i + 1) % zweige
            h = (i - 1) % zweige
            tb.faces.new([kopf, schultern[i], schultern[j]])
            tb.faces.new([schultern[i], kerben[h], spitzen[i]])
            tb.faces.new([schultern[i], spitzen[i], kerben[i]])
            tb.faces.new([schultern[i], kerben[i], schultern[j]])
            tb.faces.new([unterpunkt, spitzen[i], kerben[h]])
            tb.faces.new([unterpunkt, kerben[i], spitzen[i]])

        rolle = {}
        for v in schultern:
            rolle[v.co.copy().freeze()] = "ruecken"
        for v in spitzen:
            rolle[v.co.copy().freeze()] = "spitze"
        for v in kerben:
            rolle[v.co.copy().freeze()] = "kerbe"
        rolle[kopf.co.copy().freeze()] = "kopf"
        rolle[unterpunkt.co.copy().freeze()] = "unter"

        def f(p, _n, rnd):
            c = farbe_fn(rolle.get(p.copy().freeze(), "ruecken"), rnd)
            return (c[0], c[1], c[2], ALPHA_LAUB)

        self._uebernehmen(tb, f)

    def krone(self, ballen, farbe, unten=0.78, beulen=0.11, hell=None):
        """Laubkrone als WOLKE: Liste aus (mitte, radien, art) mit art "g" (80 Dreiecke),
        "m" (60) oder "k" (20, nacktes Ikosaeder — nur fuer kleine Buckel, die halb in einem
        grossen Ballen stecken und den Umriss brechen). `hell`: zweite Laubfarbe fuer jeden
        zweiten Ballen (Flecken von frischem Laub)."""
        art_fein = {"g": True, "m": "mittel", "k": "winzig"}
        for i, (m, r, art) in enumerate(ballen):
            c = hell if (hell is not None and i % 2 == 1) else farbe
            self.ballen(m, r, laub(c), fein=art_fein[art], beulen=beulen, unten=unten)

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
def nadel_farbe(tief, flaeche, spitze):
    """Farben einer Astetage nach der Rolle des Punkts (siehe Baum.etage)."""
    farben = {"kopf": _mix(tief, flaeche, 0.5), "ruecken": _mix(flaeche, spitze, 0.25),
              "spitze": spitze, "kerbe": _mix(tief, flaeche, 0.55), "unter": tief}

    def f(teil, rnd):
        return _mul(farben[teil], 0.96 + 0.08 * rnd)
    return f


def fichte():
    """Fichte: sechs GLOCKIGE Astetagen aus haengenden Zweigen (Baum.etage), nach oben
    schmaler, Wipfel als schlanke Spitze. Die Etagen sind flach (2,3 m hoch bei 2,7 m
    Radius) und liegen 1,5 m auseinander: unter jeder bleibt ein Schattenspalt, der Baum
    liest sich als geschichtet. Vorher sechs gerade Zackenkegel = ein Stapel Papierhuetchen."""
    b = Baum("Fichte", 11)
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.35), (0, 0, 3.2)],
           [0.44, 0.33, 0.20], holz(RINDE), segs=5, offen="uo")
    # (Fuss, Kopf, Radius, Haengen, Zweige)
    etagen = [(1.50, 3.9, 2.75, 0.42, 7), (3.10, 5.5, 2.36, 0.38, 7), (4.65, 6.95, 1.96, 0.33, 6),
              (6.10, 8.3, 1.56, 0.28, 6), (7.45, 9.55, 1.16, 0.22, 5), (8.70, 10.8, 0.76, 0.16, 5)]
    f = nadel_farbe(NADEL_TIEF, NADEL, NADEL_SPITZE)
    for z0, z1, r, haeng, n in etagen:
        b.etage(z0, z1, r, f, zweige=n, haengen=haeng)
    return b.objekt()


def schneetanne():
    """Nordland: schmale, dunkle Tanne. SCHNEE ALS FARBE, nicht als eigene Geometrie: der
    Ruecken jeder Etage traegt Weiss, die haengenden Zweigspitzen und die Unterseite bleiben
    dunkel. Von oben (so sieht man Baeume im Flug) ergibt das einen weissen Stern auf jeder
    Etage; die erste Fassung legte Baender NEBEN die Kraenze, die sichtbar in der Luft standen."""
    b = Baum("Schneetanne", 88)
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.35), (0, 0, 3.0)],
           [0.36, 0.27, 0.17], holz(RINDE), segs=5, offen="uo")

    # Der Ruecken jedes Zweigs und der Kopf tragen Schnee, Spitzen, Kerben und Unterseite
    # bleiben dunkel — von oben ein weisser Stern auf jeder Etage.
    farben = {"kopf": SCHNEE, "ruecken": _mix(NADEL_KALT, SCHNEE, 0.85),
              "spitze": NADEL_KALT, "kerbe": _mix(NADEL_KALT, SCHNEE, 0.22),
              "unter": _mul(NADEL_KALT, 0.85)}

    def schnee(teil, rnd):
        return farben[teil]

    etagen = [(1.30, 3.6, 2.20, 0.34, 6), (2.90, 5.2, 1.88, 0.30, 6), (4.45, 6.7, 1.56, 0.26, 6),
              (5.95, 8.1, 1.24, 0.22, 5), (7.35, 9.4, 0.92, 0.18, 5), (8.60, 10.6, 0.60, 0.14, 5)]
    for z0, z1, r, haeng, n in etagen:
        b.etage(z0, z1, r, schnee, zweige=n, haengen=haeng)
    return b.objekt()


def kiefer():
    """Waldkiefer: hoher, leicht gebogener Stamm (unten grau, oben fuchsrot), die Krone als
    flache Wolkenschichten ganz oben — ein Schirm aus drei breiten Polstern mit Buckeln."""
    b = Baum("Kiefer", 22)
    p = [(0, 0, UNTER_BODEN), (0.02, 0.0, 0.4), (0.14, 0.05, 3.0), (0.36, 0.02, 5.6),
         (0.38, -0.09, 8.2)]
    r = [0.40, 0.31, 0.25, 0.20, 0.13]

    def rinde(pos, _n, rnd):
        c = _mix(RINDE, RINDE_KIEFER, min(max((pos.z - 2.0) / 3.0, 0.0), 1.0))
        c = _mul(c, 0.92 + 0.16 * rnd)
        return (c[0], c[1], c[2], ALPHA_HOLZ)

    b.rohr(p, r, rinde, segs=5, offen="uo")
    kopf = Vector((0.38, -0.08, 7.3))
    polster = [((0.50, -0.30, 9.60), (1.95, 1.80, 1.22), "g"),
               ((1.80, 0.75, 8.55), (1.62, 1.45, 1.02), "m"),
               ((-1.40, -0.75, 8.25), (1.55, 1.40, 0.96), "m"),
               ((0.00, 1.60, 8.95), (1.40, 1.30, 0.92), "m"),
               ((-0.85, 0.50, 10.15), (1.10, 1.02, 0.78), "m")]
    for ziel, _rad, _art in polster[1:4]:
        z = Vector(ziel) - Vector((0, 0, 0.25))
        mid = kopf.lerp(z, 0.5) + Vector((0, 0, 0.35))
        b.rohr([kopf, mid, z], [0.13, 0.09, 0.06], rinde, segs=4, offen="uo")
    b.krone(polster, KIEFERGRUEN, unten=0.62, beulen=0.16, hell=KIEFER_HELL)
    return b.objekt()


def birke():
    """Birke: schlanker weisser Stamm mit dunklen Querflecken (Farbe je Flaeche), hohe,
    lockere Krone — ein Kern, drei seitliche Wolken, zwei kleine Buckel."""
    b = Baum("Birke", 33)
    pts = [(0, 0, UNTER_BODEN)]
    rad = [0.24]
    for k in range(5):
        z = 0.2 + k * 1.15
        pts.append((0.07 * math.sin(z * 0.9), 0.05 * math.sin(z * 0.6 + 1.0), z))
        rad.append(0.21 - z * 0.016)

    def rinde(pos, _n, rnd):
        # dunkle Flecken aus dem Eckpunkt-Zufall, unten (Borke) dunkel
        c = BIRKE_FLECK if (rnd < 0.30 or pos.z < 0.35) else _mul(BIRKE, 0.96 + 0.06 * rnd)
        return (c[0], c[1], c[2], ALPHA_HOLZ)

    b.rohr(pts, rad, rinde, segs=5, offen="uo")
    for ziel in ((0.9, 0.35, 5.5), (-0.8, 0.45, 5.4), (0.15, -0.85, 5.7)):
        b.rohr([(0.06, 0.02, 3.9), ziel], [0.08, 0.05], rinde, segs=4, offen="uo")
    b.krone([((0.08, 0.02, 6.45), (1.50, 1.42, 2.00), "g"),
             ((0.92, 0.34, 5.45), (1.08, 1.00, 1.22), "m"),
             ((-0.84, 0.48, 5.65), (1.02, 0.98, 1.18), "m"),
             ((0.16, -0.90, 6.05), (1.00, 0.94, 1.28), "m"),
             ((-0.30, -0.20, 7.85), (0.92, 0.88, 0.98), "m")],
            BIRKENLAUB, unten=0.85, beulen=0.12, hell=BIRKE_HELL)
    return b.objekt()


def eiche():
    """Eiche: kurzer, dicker Stamm mit Wurzelanlauf, kraeftige Aeste, breite Kuppel: ein
    grosser Kern, vier Laubwolken rundum, dazu Buckel, die den Umriss brechen."""
    b = Baum("Eiche", 44)
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.3), (0.05, 0.0, 1.5), (0.1, 0.05, 2.9)],
           [0.84, 0.58, 0.46, 0.40], holz(RINDE, 0.10), segs=6, offen="uo")
    kopf = Vector((0.1, 0.05, 2.6))
    wolken = [((0.15, 0.10, 6.05), (2.45, 2.30, 1.85), "g"),
              ((2.05, 0.60, 5.00), (1.80, 1.65, 1.38), "m"),
              ((-1.90, 0.90, 5.05), (1.75, 1.68, 1.34), "m"),
              ((0.35, -2.00, 5.15), (1.70, 1.60, 1.32), "m"),
              ((-0.70, -1.05, 6.85), (1.40, 1.34, 1.12), "m"),
              ((1.05, 1.30, 7.10), (1.25, 1.18, 1.00), "m"),
              ((2.20, -1.60, 5.55), (1.10, 1.05, 0.90), "m")]
    for m, _r, _a in wolken[1:4]:
        z = Vector(m) - Vector((0, 0, 0.6))
        mid = kopf.lerp(z, 0.45) + Vector((0, 0, 0.25))
        b.rohr([kopf, mid, z], [0.30, 0.20, 0.12], holz(RINDE_HELL), segs=4, offen="uo")
    b.krone(wolken, EICHE, hell=EICHE_HELL)
    return b.objekt()


def palme():
    """Kokospalme: geschwungener Stamm mit Ringen, Kokosnuesse, gefaltete Wedel (zweiseitig)
    in zwei Lagen — die obere steht, die untere haengt tief herab."""
    b = Baum("Palme", 55)
    pts = [(0, 0, UNTER_BODEN)]
    rad = [0.36]
    for k in range(7):
        t = k / 6.0
        pts.append((1.15 * t * t, 0.25 * t * t, 6.2 * t))
        rad.append(0.33 - 0.14 * t)

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
    for i in range(10):
        a = 2.0 * math.pi * i / 10 + 0.2 + b.rng.uniform(-0.12, 0.12)
        oben = i % 2 == 0
        d = Vector((math.cos(a), math.sin(a), 0.62 if oben else 0.10))
        f = PALME if oben else _mul(PALME, 0.84)
        b.wedel(kopf + Vector((0, 0, 0.15)), d, 3.3 if oben else 3.0, 0.60, f,
                knick=0.50 if oben else 0.72, stationen=4, falz=0.35)
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
    """Busch: ein runder Kern und zwei Buckel (200 statt 224 Dreiecke — Buesche sind
    die haeufigste Pflanze der Heide und nur 2 m gross)."""
    b = Baum("Busch", 77)
    b.krone([((0.0, 0.0, 0.62), (0.98, 0.92, 0.82), "g"),
             ((0.62, 0.34, 0.44), (0.68, 0.64, 0.58), "m"),
             ((-0.50, -0.42, 0.40), (0.64, 0.60, 0.55), "m")],
            BUSCH, unten=0.6, beulen=0.10, hell=_mul(BUSCH, 1.10))
    return b.objekt()


def urwaldbaum():
    """Suedland: Urwaldriese — Brettwurzeln, hoher glatter Stamm, breite Schirmkrone."""
    b = Baum("Urwaldbaum", 99)
    for k, a in enumerate((0.3, 1.9, 3.4, 4.9)):
        b.brett(a, 1.55 + 0.25 * (k % 2), 2.4 + 0.3 * (k % 2), 0.22, RINDE_URWALD)
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.0), (0.12, 0.06, 4.0), (0.2, 0.1, 7.5), (0.1, -0.1, 11.0)],
           [0.62, 0.60, 0.48, 0.40, 0.30], holz(RINDE_URWALD), segs=6, offen="uo")
    kopf = Vector((0.1, -0.1, 10.6))
    wolken = [((0.10, 0.25, 13.00), (2.90, 2.75, 1.30), "g"),
              ((2.70, 0.60, 11.90), (2.50, 2.30, 1.10), "m"),
              ((-2.35, 1.40, 11.65), (2.35, 2.25, 1.05), "m"),
              ((0.45, -2.60, 11.95), (2.40, 2.30, 1.10), "m"),
              ((-1.60, -1.80, 12.75), (1.75, 1.65, 0.92), "m"),
              ((1.90, 2.40, 12.50), (1.60, 1.52, 0.86), "m")]
    for m, _r, _a in wolken[1:4]:
        z = Vector(m) - Vector((0, 0, 0.4))
        b.rohr([kopf, kopf.lerp(z, 0.5) + Vector((0, 0, 0.3)), z], [0.24, 0.16, 0.10],
               holz(RINDE_URWALD), segs=4, offen="uo")
    b.krone(wolken, URWALD, unten=0.6, hell=URWALD_HELL)
    return b.objekt()


def baumfarn():
    """Suedland: schlanker Stamm, ein Stern aus gebogenen Wedeln (zweiseitig)."""
    b = Baum("Baumfarn", 111)
    b.rohr([(0, 0, UNTER_BODEN), (0, 0, 0.0), (0.15, 0.05, 2.4), (0.25, 0.0, 4.6)],
           [0.24, 0.23, 0.19, 0.16], holz(FARN_STAMM, 0.12), segs=5, offen="uo")
    kopf = Vector((0.25, 0.0, 4.6))
    b.ballen(kopf + Vector((0, 0, 0.1)), (0.34, 0.34, 0.30), laub(_mul(FARN, 0.8)), fein="winzig")
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
           [0.32, 0.29, 0.24, 0.21], f, segs=5, offen="uo")
    enden = ((1.5, 0.5, 4.7), (-1.3, 0.75, 4.55), (0.2, -1.4, 4.8))
    for e in enden:
        ev = Vector(e)
        b.rohr([(0.1, 0.0, 2.1), Vector((0.1, 0.0, 2.1)).lerp(ev, 0.5) + Vector((0, 0, -0.15)), ev],
               [0.15, 0.11, 0.08], f, segs=4, offen="uo")
    b.krone([((0.0, 0.0, 5.35), (2.75, 2.55, 0.66), "g"),
             ((1.45, 0.50, 5.05), (1.95, 1.80, 0.54), "m"),
             ((-1.35, 0.75, 4.95), (1.90, 1.75, 0.52), "m"),
             ((0.25, -1.40, 5.10), (1.90, 1.75, 0.54), "m"),
             ((-1.35, -1.55, 5.40), (1.25, 1.18, 0.44), "m")],
            AKAZIE, unten=0.55, hell=AKAZIE_HELL)
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
    b.krone([((0.10, -0.65, 4.70), (1.75, 1.65, 1.22), "g"),
             ((0.80, 0.25, 4.20), (1.68, 1.58, 1.16), "m"),
             ((-0.75, 0.55, 4.00), (1.58, 1.52, 1.10), "m"),
             ((0.00, 0.35, 5.15), (1.15, 1.10, 0.88), "m"),
             ((-1.25, -0.85, 4.45), (1.00, 0.95, 0.76), "m")],
            MANGROVE, unten=0.65, hell=MANGROVE_HELL)
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
    """Felsgruppe fuer Haenge und Hochlagen: ein kantiger Hauptblock und zwei kleine Brocken
    daneben (vorher eine einzelne verbeulte Kugel in dunklem Grau — auf der Wiese eine
    flache dunkle Scheibe). Farbe wie der Fels des Gelaendes (shaders/palette.gdshaderinc,
    FELS_TIEF -> FELS_HELL): unten kuehl und dunkel, oben und auf nach oben zeigenden
    Flaechen hell und warm, darauf ein Hauch Moos. Masse wie vorher: Radius ~1, Fuss im
    Boden, oben ~1.3; die Platzierung streckt je Achse 0.5..2.6."""
    b = Baum("Fels", 155)

    def farbe(mitte, rz):
        # "Zeigt nach oben" aus der LAGE des Punkts auf seinem Brocken, nicht aus der
        # Flaechennormale: mit der Normale bekam jede Flaeche an einem Punkt eine andere
        # Farbe, und der Export teilte jeden Eckpunkt (227 Eckpunkte fuer 120 Dreiecke).
        def f(p, _n, rnd):
            auf = min(max((p.z - mitte[2]) / rz, -1.0), 1.0)
            oben = min(max((p.z + 0.2) / 1.3, 0.0), 1.0) * 0.5 + max(auf, 0.0) * 0.5
            c = _mix(FELS_TIEF, FELS_HELL, oben)
            c = _mul(c, 0.94 + 0.10 * rnd)
            if auf > 0.55 and p.z > 0.45:
                c = _mix(c, MOOS, min((auf - 0.55) * 1.4, 0.45))
            return (c[0], c[1], c[2], ALPHA_HOLZ)
        return f

    for mitte, rad, fein, dreh in (((0.0, 0.0, 0.42), (0.98, 0.86, 1.08), True, 0.4),
                                   ((0.90, 0.40, 0.22), (0.48, 0.42, 0.52), "winzig", 1.3),
                                   ((-0.68, -0.70, 0.16), (0.40, 0.36, 0.44), "winzig", 2.1)):
        b.ballen(mitte, rad, farbe(mitte, rad[2]), fein=fein, kanten=0.26 if fein is True else 0.22,
                 unten=0.9, drehung=dreh)
    return b.objekt(kante_grad=66.0)


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
