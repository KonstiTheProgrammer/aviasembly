## Baut den Me-262-RUMPFBAUSATZ aus DREI Modulen:
##   models/me262_nose.glb     Nasenkonus
##   models/me262_cockpit.glb  Cockpitsektion mit Rahmenkanzel
##   models/me262_tail.glb     Heckkonus
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_me262_kit.py
## Achsen (glTF +Y up): Blender X->Godot X, Blender Z->Godot Y (oben), Blender +Y->Godot -Z.
##
## WARUM ALLE DREI AUS EINER DATEI: die Nahtstellen muessen auf den Punkt passen. Wenn
## Nase, Cockpit und Heck aus getrennten Skripten kaemen, waere jede Naht eine Zahl, die
## an zwei Stellen gepflegt werden muss — und genau daran ist der erste Anlauf gescheitert.
## Hier gibt es EIN durchgehendes Laengsprofil (STATIONEN) ueber den ganzen Rumpf; die
## Module sind Abschnitte daraus. Eine Naht ist damit derselbe Eintrag fuer beide Nachbarn
## und kann per Konstruktion nicht auseinanderlaufen.
##
## VORGESCHICHTE: Vorher war die Cockpitsektion an den Querschnitt des generischen Teils
## "fuselage" gebunden (Kreis, Radius 0.600). Das Ergebnis war zwangslaeufig gedrungen —
## 2.0 lang bei 1.2 dick — und traf die Vorlage nicht. Jetzt bringt der Bausatz seine
## eigenen Anschlussmasse mit; dafuer stimmen Verjuengung und Kanzelsitz.
##
## Was die Vorlage zeigt und was hier daraus folgt:
##   * Der Rumpf ist vorne am dicksten und verjuengt sich deutlich nach hinten.
##   * Die Kanzel sitzt in der VORDEREN Haelfte und beginnt fast an der Stirnkante.
##   * Der Querschnitt ist dreieckig: schmaler Ruecken, breite Schultern, Kiel unten.
import bpy, bmesh, math, os

for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
for me in list(bpy.data.meshes): bpy.data.meshes.remove(me)
for mt in list(bpy.data.materials): bpy.data.materials.remove(mt)

def newmat(name, col, rough, metal):
    m = bpy.data.materials.new(name); m.name = name; m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
    return m
# "body" steht in PartCatalog.PAINT_MATS -> vom Spieler lackierbar. Glas und Rahmen nicht.
MB = newmat("body",  (0.64, 0.67, 0.69), 0.42, 0.45)
MG = newmat("glass", (0.03, 0.03, 0.035), 0.08, 0.10)
MF = newmat("frame", (0.34, 0.36, 0.38), 0.45, 0.50)   # deutlich heller als das Glas,
                                                        # sonst verschwinden die Streben

N = 24
# Hai-Querschnitt als Polygon, normiert auf halbe Breite/Hoehe 1, gegen den Uhrzeigersinn
# ab +x. Dreieck mit der Spitze unten: schmaler runder Ruecken, breiteste Stelle weit oben,
# von dort zwei LANGE GERADE FLANKEN zum Kiel.
# WARUM DIE LANGEN GERADEN entscheidend sind: jede konvexe Form, die auf ein
# Einheitsquadrat normiert ist, hat ECKradien nahe 1 — daran laesst sich ein Dreieck nicht
# von einem Kreis unterscheiden. Der Unterschied entsteht ZWISCHEN den Ecken: auf einer
# langen Geraden faellt der Radius zur Mitte hin ab (hier 0.66 gegen 1.09 an den
# Schultern). Zwei Anlaeufe haben hier eine Tonne produziert, weil ihre Polygone fast auf
# dem Einheitskreis lagen.
## GEMESSENE SPANNE der Radien ueber die 24 Abtastwinkel — das ist der Pruefwert dafuer,
## ob die Form ueberhaupt dreieckig BLEIBT:
##      Tonne (frueherer Fehlversuch)  8 %
##      scharfer Kiel                 65 %   -> sah aus wie eine Messerschneide
##      dieser weiche Kiel            40 %   -> Dreieck bleibt klar erkennbar
HAI_ECKEN = [
    ( 1.00,  0.40),   # rechte Schulter (breiteste Stelle, deutlich ueber der Mitte)
    ( 0.74,  0.82),   # Knick zum Ruecken
    ( 0.28,  0.97),
    ( 0.00,  1.00),   # schmaler runder Ruecken
    (-0.28,  0.97),
    (-0.74,  0.82),
    (-1.00,  0.40),   # linke Schulter
    (-0.78, -0.22),   # lange gerade Flanke hinunter
    (-0.40, -0.82),   # Kielknick
    ( 0.00, -0.95),   # flacher Bauch statt Messerschneide
    ( 0.40, -0.82),
    ( 0.78, -0.22),
]

def strahl_schnitt(poly, ang):
    """Radius des Polygons in Richtung ang (Strahl vom Ursprung)."""
    dx, dy = math.cos(ang), math.sin(ang)
    best = None
    for k in range(len(poly)):
        ax, ay = poly[k]; bx, by = poly[(k + 1) % len(poly)]
        ex, ey = bx - ax, by - ay
        den = dx * ey - dy * ex
        if abs(den) < 1e-12: continue
        t = (ax * ey - ay * ex) / den
        u = (ax * dy - ay * dx) / den
        if t > 1e-9 and -1e-9 <= u <= 1 + 1e-9:
            if best is None or t < best: best = t
    return best if best else 1.0

# 24 Abtastungen auf gleichmaessigen Winkeln, danach jede Polygonecke exakt auf ihren
# naechstgelegenen Abtastpunkt gezogen — sonst rundet die Abtastung genau die Knicke weg,
# die die Form ausmachen.
HAI = []
for i in range(N):
    a = math.tau * i / N
    r = strahl_schnitt(HAI_ECKEN, a)
    HAI.append((r * math.cos(a), r * math.sin(a)))
for (cx, cy) in HAI_ECKEN:
    ca = math.atan2(cy, cx) % math.tau
    j = min(range(N), key=lambda i: min(abs(math.tau * i / N - ca),
                                        math.tau - abs(math.tau * i / N - ca)))
    HAI[j] = (cx, cy)

# --- DURCHGEHENDES LAENGSPROFIL -------------------------------------------------------
# (y, halbe Breite, halbe Hoehe, Mitte z). y = 0 ist die Mitte der Cockpitsektion,
# +y zeigt zur Nase. Die beiden NAHTSTATIONEN stehen hier genau einmal.
NAHT_VORN  = ( 1.60, 0.630, 0.650,  0.000)
NAHT_HINTEN = (-1.60, 0.425, 0.445, -0.040)
# Die Nase ist STUMPF abgeschlossen, keine Nadel: in der echten Me 262 stecken dort vier
# MK 108, und eine ausgezogene Spitze sah im Zusammenbau aus wie ein Speer.
NASE = [
    ( 3.80, 0.115, 0.125,  0.030),   # abgeflachte Spitze
    ( 3.55, 0.230, 0.245,  0.028),
    ( 3.10, 0.390, 0.415,  0.022),
    ( 2.45, 0.545, 0.575,  0.012),
    NAHT_VORN,
]
COCKPIT = [
    NAHT_VORN,
    ( 1.15, 0.658, 0.678,  0.000),   # breiteste Stelle, kurz hinter der Stirnkante
    ( 0.50, 0.628, 0.650, -0.010),
    (-0.20, 0.566, 0.588, -0.020),
    (-0.90, 0.494, 0.514, -0.030),
    NAHT_HINTEN,
]
# Das Heck laeuft NICHT spitz aus: hier sitzt der Leitwerkstraeger. Mit 0.095 halber
# Breite war das Ende eine Klinge, an die sich keine Flosse anbauen laesst.
HECK = [
    NAHT_HINTEN,
    (-2.30, 0.360, 0.378, -0.050),
    (-3.00, 0.298, 0.314, -0.060),
    (-3.75, 0.242, 0.256, -0.068),
    (-4.40, 0.205, 0.218, -0.074),
]

def loft(name, rings, sec_of_ring, mats, mat_of_band, versatz_y):
    """rings: y-Werte. sec_of_ring(k) -> [(x, z)]. versatz_y verschiebt das Modul so,
    dass sein Mittelpunkt auf y = 0 liegt (jedes Teil hat in Godot seinen eigenen Ursprung)."""
    bm = bmesh.new(); rv = []
    for k, y in enumerate(rings):
        rv.append([bm.verts.new((x, y + versatz_y, z)) for (x, z) in sec_of_ring(k)])
    for k in range(len(rv) - 1):
        a, b = rv[k], rv[k + 1]; M = len(a)
        for j in range(M):
            j2 = (j + 1) % M
            bm.faces.new((a[j], a[j2], b[j2], b[j])).material_index = mat_of_band(k)
    bm.faces.new(rv[0][::-1]).material_index = mat_of_band(0)
    bm.faces.new(rv[-1]).material_index = mat_of_band(len(rv) - 2)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = False      # Flatshading: sichtbare Facetten
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    for m in mats: ob.data.materials.append(m)
    return ob

def rumpf_loft(name, stationen, versatz_y):
    def sec(k):
        _, hw, hh, cz = stationen[k]
        return [(x * hw, cz + z * hh) for (x, z) in HAI]
    return loft(name, [s[0] for s in stationen], sec, [MB], lambda k: 0, versatz_y)

# --- KANZEL ---------------------------------------------------------------------------
# Querschnitt oben abgeflacht (die Me 262 hat ebene Glasfelder, keine Blase); die untere
# Haelfte verschwindet im Rumpfruecken.
KAN_SEC = [(1.00, 0.00), (0.94, 0.52), (0.66, 0.90), (0.24, 1.00),
           (-0.24, 1.00), (-0.66, 0.90), (-0.94, 0.52), (-1.00, 0.00),
           (-0.80, -0.75), (-0.34, -1.15), (0.34, -1.15), (0.80, -0.75)]
# (y, halbe Breite, halbe Hoehe, Mitte z, Spantring?).
# Die Kanzel beginnt fast an der Stirnkante (Naht bei y = 1.60) und endet vor der Mitte —
# so zeigt es die Vorlage. Meine erste Fassung hatte sie mittig sitzen.
# Ein Spantring bildet mit seinem VORGAENGER ein schmales Band von 0.07: das ist die
# Strebe. Rahmen wird deshalb NUR das Band, das AUF einem Spantring endet.
KANZEL = [
    ( 1.44, 0.120, 0.062, 0.652, False),   # Ansatz der Frontscheibe
    ( 1.16, 0.250, 0.150, 0.688, False),   # Oberkante Frontscheibe (steil angestellt)
    ( 1.09, 0.264, 0.164, 0.694, True),    # Spant hinter der Frontscheibe
    ( 0.74, 0.296, 0.196, 0.702, False),
    ( 0.67, 0.298, 0.198, 0.702, True),    # Spant
    ( 0.30, 0.300, 0.200, 0.700, False),
    ( 0.23, 0.298, 0.198, 0.699, True),    # Spant
    (-0.12, 0.284, 0.188, 0.692, False),
    (-0.19, 0.280, 0.184, 0.690, True),    # Spant
    (-0.56, 0.234, 0.148, 0.674, False),
    (-1.02, 0.140, 0.078, 0.640, False),
    (-1.42, 0.050, 0.026, 0.610, False),   # laeuft in den Ruecken aus
]

# --- BAUEN ----------------------------------------------------------------------------
MODELS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models")

def export(objs, dateiname):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    pfad = os.path.join(MODELS, dateiname)
    bpy.ops.export_scene.gltf(filepath=pfad, export_format='GLB', use_selection=True,
                              export_yup=True, export_apply=True)
    print("EXPORTED", pfad)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)

# Nase: Stationen 1.60..3.80 -> Mitte 2.70
export([rumpf_loft("Nose", NASE, -2.70)], "me262_nose.glb")

# Cockpit: Stationen -1.60..1.60 -> schon mittig
kanzel = loft("Canopy", [r[0] for r in KANZEL],
              lambda k: [(x * KANZEL[k][1], KANZEL[k][3] + z * KANZEL[k][2])
                         for (x, z) in KAN_SEC],
              [MG, MF],
              lambda k: 1 if KANZEL[k + 1][4] else 0,
              0.0)
export([rumpf_loft("Fuselage", COCKPIT, 0.0), kanzel], "me262_cockpit.glb")

# Heck: Stationen -4.40..-1.60 -> Mitte -3.00
export([rumpf_loft("Tail", HECK, 3.00)], "me262_tail.glb")
