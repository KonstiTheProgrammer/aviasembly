# C-130-artiges Transporter-Cockpit — EIGENE Datei, unabhaengig von allen bestehenden
# Kanzeln:  blender_lib/c130_cockpit.blend  +  models/cockpit_c130.glb
#
# Vorbild ist der Herkules-Bug: rundes Radom unten vorn, darueber ein umlaufendes
# Kanzelband aus EBENEN, gegeneinander abgewinkelten Scheiben, darunter die typischen
# schraeg nach unten blickenden Kinnfenster, oben eine Dachluke, hinten ein gerader
# Rumpfabschnitt mit ebener Andockflaeche.
#
# BAUPRINZIP: ein gelofteter Rumpf aus Querschnitts-RINGEN (16-Eck). Die Scheiben sind
# keine aufgesetzten Platten, sondern GENAU die Vierecke des Rumpfrasters — dieselben
# vier Eckpunkte, nur ein Stueck nach aussen versetzt. Dadurch folgt jede Scheibe der
# Rumpfkruemmung, sitzt buendig im Rahmen und kann nicht schief in der Haut haengen.
# Zwischen den Scheiben bleibt die Haut stehen und bildet die Rahmenstege.
#
# Achsen (Projektkonvention): Blender +Y = Godot -Z (VORNE), Blender Z = Godot Y (oben).
# Die Nase zeigt also nach +Y, die ebene Andockflaeche liegt hinten bei -Y.
#
# Usage: blender --background --python tools/build_c130_cockpit.py
#        C130_PREVIEW=<ordner>  rendert zusaetzlich Ansichten
import bpy
import bmesh
import math
import mathutils
import os

ROOT = "C:/Users/Konst/Projects/aviasembly/"
BLEND = ROOT + "blender_lib/c130_cockpit.blend"
GLB = ROOT + "models/cockpit_c130.glb"
PREVIEW = os.environ.get("C130_PREVIEW", "")

SEITEN = 16          # Ringteilung
HECK_Y = -1.55       # ebene Andockflaeche
NASE_Y = 2.38


def srgb2lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


MATS = {
    # "cockpit_body" steht in PartCatalog.PAINT_MATS -> lackierbar
    "cockpit_body": ((0.615, 0.630, 0.655), 0.35, 0.52),
    "radome":       ((0.335, 0.345, 0.365), 0.15, 0.62),
    "frame":        ((0.455, 0.470, 0.495), 0.40, 0.50),
    "glass":        ((0.055, 0.070, 0.095), 0.30, 0.14),
    "dark":         ((0.120, 0.130, 0.150), 0.35, 0.55),
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


# --- Querschnitt ------------------------------------------------------------------------
# STATIONEN: (y, Halbbreite, Halbhoehe, Mitte z). Hinten konstanter Rumpf, dann der
# Kanzelbereich, davor faellt die Kontur zum Radom ab. Die Mitte wandert nach unten,
# damit die Nase wie beim Original TIEF sitzt und das Dach lange hoch bleibt.
STATIONEN = [
    # (y, Halbbreite, Oberkante z, Unterkante z)
    (HECK_Y, 0.960, 0.940, -0.940),
    (-0.62, 0.960, 0.940, -0.940),
    (0.06, 0.952, 0.940, -0.920),
    (0.52, 0.936, 0.936, -0.884),     # Seitenscheiben
    (0.80, 0.906, 0.930, -0.846),     # Brauenkante: bis hierher bleibt das Dach oben
    (1.04, 0.858, 0.790, -0.812),     # Windschutz: Dach faellt STEIL
    (1.28, 0.782, 0.588, -0.774),
    (1.60, 0.712, 0.318, -0.690),     # Radom: bleibt lange dick ...
    (1.86, 0.628, 0.176, -0.606),
    (2.06, 0.512, 0.052, -0.520),
    (2.20, 0.372, -0.044, -0.446),
    (2.30, 0.208, -0.116, -0.386),    # ... und rundet erst hier ab
    (NASE_Y, 0.078, -0.166, -0.344),
]

# Ringindex: k=0 rechts (+X), k=4 oben (+Z), k=8 links (-X), k=12 unten (-Z).
OBEN = 4

# GLASFELDER als (Stationsindex, Ringindex): genau diese Rumpf-Vierecke werden zu
# Scheiben. Stationen 6..7 = Frontscheiben (das Band ueber dem Radom), 4..5 = die
# zurueckgesetzten Seitenscheiben, 4..5 weiter unten = die Kinnfenster.
def glasfelder():
    felder = set()
    # Frontscheiben: die beiden STEIL abfallenden Baender direkt hinter der Braue.
    # Nur die oberen fuenf Felder — laeuft das Band weiter herum, sieht es aus wie ein
    # Insektenauge statt wie eine Kanzel (genau das war der erste Versuch).
    for si in (4, 5):
        for k in (OBEN - 2, OBEN - 1, OBEN, OBEN + 1, OBEN + 2):
            felder.add((si, k % SEITEN))
    for k in (OBEN - 4, OBEN - 3, OBEN + 3, OBEN + 4):  # Seitenscheiben, klar dahinter
        felder.add((3, k % SEITEN))
    for k in (OBEN - 5, OBEN + 5):                      # Kinnfenster, nur eine Reihe
        felder.add((4, k % SEITEN))
    return felder


GLAS = glasfelder()


def ring(y, bx, oben_z, unten_z):
    """Querschnitt aus Ober- und Unterkante — so laesst sich das Dach unabhaengig vom
    Bauch absenken, und genau daraus entsteht die Braue vor dem Windschutz."""
    mitte = (oben_z + unten_z) * 0.5
    hoch = (oben_z - unten_z) * 0.5
    pts = []
    for k in range(SEITEN):
        t = 2.0 * math.pi * k / SEITEN
        pts.append(mathutils.Vector((bx * math.cos(t), y, mitte + hoch * math.sin(t))))
    return pts


def ring_mitte(st):
    return (st[2] + st[3]) * 0.5


def achse_bei(y):
    """Hoehe der Rumpfachse bei y — sie wandert zur Nase hin nach unten."""
    for i in range(len(STATIONEN) - 1):
        a = STATIONEN[i]
        b = STATIONEN[i + 1]
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / max(b[0] - a[0], 1e-6)
            return ring_mitte(a) + (ring_mitte(b) - ring_mitte(a)) * t
    return ring_mitte(STATIONEN[-1] if y > STATIONEN[-1][0] else STATIONEN[0])


def flaeche(bm, verts, mi):
    try:
        f = bm.faces.new(verts)
        f.material_index = mi
        return f
    except ValueError:
        return None


def scheibe_auf(bm, ecken, n, tiefe_rahmen=0.012, tiefe_glas=0.026, rand=0.17):
    """Fensterfeld auf ein bereits ausgerichtetes Hautviereck setzen.

    Die vier Ecken sind DIESELBEN wie das Rumpfviereck darunter, nur entlang dessen
    Normale nach aussen versetzt — so liegt das Fenster garantiert in der Haut. Die
    Normale kommt von der Haut, nicht aus einer eigenen Rechnung: sonst dreht
    recalc_face_normals einzelne Platten um und man sieht die helle Rahmenplatte.
    """
    mitte = (ecken[0] + ecken[1] + ecken[2] + ecken[3]) * 0.25
    flaeche(bm, [bm.verts.new(p + n * tiefe_rahmen) for p in ecken], MI["frame"])
    innen = [p + (mitte - p) * rand + n * tiefe_glas for p in ecken]
    flaeche(bm, [bm.verts.new(p) for p in innen], MI["glass"])


def kasten(bm, mitte, groesse, mi):
    cx, cy, cz = mitte
    sx, sy, sz = groesse
    v = []
    for dx in (-0.5, 0.5):
        for dy in (-0.5, 0.5):
            for dz in (-0.5, 0.5):
                v.append(bm.verts.new((cx + dx * sx, cy + dy * sy, cz + dz * sz)))
    for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6),
              (0, 2, 6, 4), (1, 5, 7, 3)):
        flaeche(bm, [v[i] for i in f], mi)


def platte(bm, ecken, mi, hoehe=0.008):
    """Duenne aufliegende Platte (Tuerumriss, Panel) — leicht ueber der Haut."""
    n = mathutils.geometry.normal(ecken)
    mitte = (ecken[0] + ecken[1] + ecken[2] + ecken[3]) * 0.25
    if n.dot(mitte - mathutils.Vector((0.0, mitte.y, 0.0))) < 0.0:
        n = -n
    flaeche(bm, [bm.verts.new(p + n * hoehe) for p in ecken], mi)


def bauen():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    me = bpy.data.meshes.new("C130_Cockpit")
    ob = bpy.data.objects.new("C130_Cockpit", me)
    bpy.context.scene.collection.objects.link(ob)
    for n in MATN:
        me.materials.append(mat(n))

    bm = bmesh.new()
    ringe = [ring(*st) for st in STATIONEN]

    # --- Aussenhaut -------------------------------------------------------------------
    haut = []
    glasfeld = []
    for si in range(len(ringe) - 1):
        for k in range(SEITEN):
            j = (k + 1) % SEITEN
            ecken = [ringe[si][k], ringe[si][j], ringe[si + 1][j], ringe[si + 1][k]]
            m = MI["radome"] if si >= 7 else MI["cockpit_body"]
            if (si, k) in GLAS:
                m = MI["frame"]
            f = flaeche(bm, [bm.verts.new(p) for p in ecken], m)
            if f is not None:
                haut.append(f)
                if (si, k) in GLAS:
                    glasfeld.append(f)

    # Haut ausrichten, BEVOR die Fenster daraufgesetzt werden. NICHT ueber
    # recalc_face_normals: das richtet eine OFFENE Roehre nur KONSISTENT aus, nicht
    # zwingend nach aussen — im Versuch zeigte danach die ganze Haut nach innen und
    # saemtliche Fensterplatten verschwanden im Rumpf. Stattdessen wird je Flaeche
    # gegen die Rumpfachse auf ihrer Hoehe geprueft und nur das Noetige gedreht.
    bm.normal_update()
    falsch = []
    for f in haut:
        m = f.calc_center_median()
        aussen = mathutils.Vector((m.x, 0.0, m.z - achse_bei(m.y)))
        if aussen.length < 1e-6 or f.normal.dot(aussen) < 0.0:
            falsch.append(f)
    if falsch:
        bmesh.ops.reverse_faces(bm, faces=falsch)
    bm.normal_update()
    print("    Haut: %d von %d Flaechen umgedreht" % (len(falsch), len(haut)))
    for f in glasfeld:
        ecken = [v.co.copy() for v in f.verts]
        scheibe_auf(bm, ecken, f.normal.copy())

    # --- ebene Andockflaeche hinten + Nasenkappe --------------------------------------
    flaeche(bm, [bm.verts.new(p) for p in ringe[0]], MI["cockpit_body"])
    spitze = bm.verts.new((0.0, NASE_Y + 0.05, ring_mitte(STATIONEN[-1])))
    for k in range(SEITEN):
        j = (k + 1) % SEITEN
        flaeche(bm, [bm.verts.new(ringe[-1][j]), bm.verts.new(ringe[-1][k]), spitze],
                MI["radome"])

    # --- Aufbauten --------------------------------------------------------------------
    # Dachluke ueber dem Flugdeck + kleine Antenne dahinter (wie im Vorbild)
    kasten(bm, (0.0, 0.30, 0.95), (0.40, 0.46, 0.10), MI["cockpit_body"])
    kasten(bm, (0.0, 0.30, 1.00), (0.30, 0.34, 0.03), MI["dark"])
    kasten(bm, (0.0, -0.62, 0.97), (0.10, 0.16, 0.14), MI["cockpit_body"])
    # Pitotrohre seitlich vorn
    for sx in (-1.0, 1.0):
        kasten(bm, (sx * 0.70, 1.02, 0.02), (0.05, 0.42, 0.05), MI["dark"])
    # Tuerumriss + zwei kleine Kabinenfenster hinten seitlich
    for sx in (-1.0, 1.0):
        y0, y1 = -1.30, -0.72
        z0, z1 = -0.42, 0.34
        ecken = [mathutils.Vector((sx * 0.955, y0, z0)),
                 mathutils.Vector((sx * 0.955, y1, z0)),
                 mathutils.Vector((sx * 0.955, y1, z1)),
                 mathutils.Vector((sx * 0.955, y0, z1))]
        platte(bm, ecken, MI["frame"], 0.006)
        for yy in (-0.30, -0.05):
            f = [mathutils.Vector((sx * 0.952, yy - 0.10, 0.26)),
                 mathutils.Vector((sx * 0.952, yy + 0.10, 0.26)),
                 mathutils.Vector((sx * 0.952, yy + 0.10, 0.46)),
                 mathutils.Vector((sx * 0.952, yy - 0.10, 0.46))]
            scheibe_auf(bm, f, mathutils.Vector((sx, 0.0, 0.0)), 0.006, 0.011, 0.20)

    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    return ob


def main():
    ob = bauen()
    os.makedirs(ROOT + "blender_lib", exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=GLB, export_format='GLB', use_selection=True,
                              export_apply=True)
    me = ob.data
    lo = [min((ob.matrix_world @ v.co)[i] for v in me.vertices) for i in range(3)]
    hi = [max((ob.matrix_world @ v.co)[i] for v in me.vertices) for i in range(3)]
    print("=== C-130-Cockpit: %d Tris" % sum(len(p.vertices) - 2 for p in me.polygons))
    print("    X %+.3f..%+.3f  Y %+.3f..%+.3f  Z %+.3f..%+.3f"
          % (lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
    print("    Andockflaeche hinten: %.3f breit x %.3f hoch"
          % (STATIONEN[0][1] * 2.0, STATIONEN[0][2] * 2.0))
    print("    blend: " + BLEND)
    print("    glb:   " + GLB)

    if PREVIEW:
        os.makedirs(PREVIEW, exist_ok=True)
        sc = bpy.context.scene
        sc.render.engine = 'BLENDER_WORKBENCH'
        sc.render.resolution_x = 1400
        sc.render.resolution_y = 900
        sc.display.shading.light = 'STUDIO'
        sc.display.shading.color_type = 'MATERIAL'
        cam_d = bpy.data.cameras.new("Cam")
        cam = bpy.data.objects.new("Cam", cam_d)
        sc.collection.objects.link(cam)
        sc.camera = cam
        for name, pos, ziel in (
                ("c130_schraeg", (3.4, 3.6, 2.3), (0.0, 0.35, -0.05)),
                ("c130_seite", (5.2, 0.2, 0.4), (0.0, 0.1, 0.0)),
                ("c130_vorn", (1.6, 5.0, 1.4), (0.0, 1.0, -0.05))):
            cam.location = pos
            d = mathutils.Vector(ziel) - mathutils.Vector(pos)
            cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(PREVIEW, name + ".png")
            bpy.ops.render.render(write_still=True)
            print("    Bild: " + sc.render.filepath)


main()
