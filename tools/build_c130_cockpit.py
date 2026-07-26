# C-130-artiges Transporter-Cockpit — eigene Datei, unabhaengig von allen anderen Kanzeln:
#   blender_lib/c130_cockpit.blend  +  models/cockpit_c130.glb
#
# ZWEITER ANLAUF. Der erste war ein glatter Ellipsoid mit Fensterfeldern im Ringraster —
# das las sich als Ei mit Insektenauge, nicht als Herkules. Die drei Ursachen und was
# jetzt anders ist:
#
#   1. KONTUR: frueher schrumpfte der Querschnitt schon ab y=0.06 kontinuierlich (bei
#      y=0.52 noch 97 %, bei 1.04 nur 89 %) — deshalb wirkte alles weich und aufgeblasen.
#      Jetzt haelt die VOLLE Rumpfroehre bis KANZEL_Y0 und knickt dort ab; der Bauch
#      bleibt lange tief und schwenkt erst kurz vor dem Radom hoch.
#   2. KANZEL: frueher Fensterfelder im Ringraster, dadurch zickzackten Ober- und
#      Unterkante. Jetzt ein echter AUFBAU: das Rumpfdach wird im Kanzelbereich FLACH
#      abgeschnitten (Bruestungsdeck), darauf steht ein Kranz ebener Scheiben zwischen
#      einer waagerechten Brauenlinie oben und der Deckkante unten. Beide Randlinien sind
#      damit von Natur aus gerade, die Scheiben nach innen geneigte Trapeze.
#   3. RADOM: frueher nur ein Materialwechsel mitten auf glatter Haut (sah aus wie Lack).
#      Jetzt sitzt an der Naht ein DOPPELRING mit Radiussprung -> echte umlaufende Kante.
#
# Achsen (Projektkonvention): Blender +Y = Godot -Z (VORNE), Blender Z = Godot Y (oben).
#
# Usage: blender --background --python tools/build_c130_cockpit.py
#        C130_PREVIEW=<ordner>  rendert zusaetzlich drei Ansichten
import bpy
import bmesh
import math
import mathutils
import os

ROOT = "C:/Users/Konst/Projects/aviasembly/"
BLEND = ROOT + "blender_lib/c130_cockpit.blend"
GLB = ROOT + "models/cockpit_c130.glb"
PREVIEW = os.environ.get("C130_PREVIEW", "")

SEITEN = 16
HECK_Y = -1.55        # ebene Andockflaeche
KANZEL_Y0 = 0.30      # Kanzel hinten
KANZEL_Y1 = 1.08      # Kanzel vorn
BRAUE_Z = 0.90        # Oberkante der Scheiben — WAAGERECHT
DECK_HINTEN = 0.60    # Bruestung hinten
DECK_VORN = 0.46      # Bruestung vorn (faellt zur Nase ab)
NEIGUNG = 0.12        # wie stark die Scheiben nach innen kippen


def srgb2lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


MATS = {
    "cockpit_body": ((0.615, 0.630, 0.655), 0.35, 0.52),   # in PAINT_MATS -> lackierbar
    "radome":       ((0.335, 0.345, 0.365), 0.15, 0.62),
    "frame":        ((0.470, 0.485, 0.510), 0.40, 0.50),
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


# --- Rumpfstationen: (y, Halbbreite, Oberkante, Unterkante) ------------------------------
STATIONEN = [
    (HECK_Y, 0.960, 0.940, -0.940),
    (-0.40, 0.960, 0.940, -0.940),
    (0.28, 0.960, 0.940, -0.940),       # bis hier volle Roehre
    (KANZEL_Y0, 0.958, 0.938, -0.936),
    (0.64, 0.950, 0.930, -0.930),
    (0.98, 0.934, 0.910, -0.916),
    (KANZEL_Y1, 0.900, 0.872, -0.892),  # Kanzelvorderkante
    (1.20, 0.884, 0.792, -0.884),       # Nasenruecken
    (1.46, 0.836, 0.612, -0.844),       # Radomnaht aussen
    (1.47, 0.782, 0.560, -0.812),       # Radomnaht innen -> sichtbare Kante
    (1.62, 0.712, 0.408, -0.744),
    (1.90, 0.574, 0.200, -0.626),
    (2.12, 0.408, 0.022, -0.508),
    (2.28, 0.224, -0.106, -0.414),
    (2.38, 0.084, -0.192, -0.350),
]
NASE_Y = STATIONEN[-1][0]
RADOM_AB = 9          # ab diesem Stationsindex ist die Haut Radom


def station_bei(y):
    for i in range(len(STATIONEN) - 1):
        a, b = STATIONEN[i], STATIONEN[i + 1]
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / max(b[0] - a[0], 1e-9)
            return (a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t,
                    a[3] + (b[3] - a[3]) * t)
    st = STATIONEN[-1] if y > STATIONEN[-1][0] else STATIONEN[0]
    return (st[1], st[2], st[3])


def deck_z(y):
    """Hoehe der Bruestung (Fensterunterkante) — faellt zur Nase hin ab."""
    t = (y - KANZEL_Y0) / max(KANZEL_Y1 - KANZEL_Y0, 1e-9)
    return DECK_HINTEN + (DECK_VORN - DECK_HINTEN) * min(max(t, 0.0), 1.0)


def breite_bei_z(y, z):
    """Halbe Rumpfbreite an der Stelle y auf der Hoehe z."""
    bx, oz, uz = station_bei(y)
    mitte = (oz + uz) * 0.5
    hoch = (oz - uz) * 0.5
    t = (z - mitte) / max(hoch, 1e-9)
    if abs(t) >= 1.0:
        return 0.0
    return bx * math.sqrt(max(1.0 - t * t, 0.0))


def deck_breite(y):
    return breite_bei_z(y, deck_z(y))


def ring(y, bx, oben_z, unten_z, kappen=False):
    """Querschnitt. Im Kanzelbereich oben FLACH abgeschnitten — dieses Deck traegt die
    Kanzel, und seine Kante ist zugleich die gerade Fensterunterkante."""
    mitte = (oben_z + unten_z) * 0.5
    hoch = (oben_z - unten_z) * 0.5
    grenze = deck_z(y) if kappen else 1e9
    dbr = deck_breite(y) if kappen else 0.0
    pts = []
    for k in range(SEITEN):
        t = 2.0 * math.pi * k / SEITEN
        z = mitte + hoch * math.sin(t)
        x = bx * math.cos(t)
        if z > grenze:
            z = grenze
            if abs(x) > dbr:
                x = math.copysign(dbr, x)
        pts.append(mathutils.Vector((x, y, z)))
    return pts


def flaeche(bm, verts, mi):
    try:
        f = bm.faces.new(verts)
        f.material_index = mi
        return f
    except ValueError:
        return None


def quad(bm, ecken, mi):
    return flaeche(bm, [bm.verts.new(p) for p in ecken], mi)


def scheibe(bm, ecken, n, tiefe=0.014, rand=0.13):
    """Rahmenfeld mit eingesetzter Scheibe; der stehen bleibende Rand IST der Steg."""
    mitte = (ecken[0] + ecken[1] + ecken[2] + ecken[3]) * 0.25
    quad(bm, ecken, MI["frame"])
    quad(bm, [p + (mitte - p) * rand + n * tiefe for p in ecken], MI["glass"])


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


def spantlinie(bm, y, breite=0.012, tiefe=0.003):
    """Umlaufende Panellinie — erst solche Linien machen die nackte Haut zum Flugzeug."""
    bx, oz, uz = station_bei(y)
    mitte = (oz + uz) * 0.5
    hoch = (oz - uz) * 0.5
    for k in range(SEITEN):
        t0 = 2.0 * math.pi * k / SEITEN
        t1 = 2.0 * math.pi * (k + 1) / SEITEN
        ps = []
        for t in (t0, t1):
            r = mathutils.Vector((math.cos(t), 0.0, math.sin(t)))
            n = mathutils.Vector((r.x / max(bx, 1e-6), 0.0, r.z / max(hoch, 1e-6)))
            n.normalize()
            p = mathutils.Vector((bx * math.cos(t), y, mitte + hoch * math.sin(t)))
            ps.append((p, n))
        (p0, n0), (p1, n1) = ps
        q = mathutils.Vector((0.0, breite * 0.5, 0.0))
        quad(bm, [p0 - q + n0 * tiefe, p1 - q + n1 * tiefe,
                  p1 + q + n1 * tiefe, p0 + q + n0 * tiefe], MI["frame"])


def kanzel_umriss():
    """Deckkante von vorn-Mitte ueber rechts nach hinten; links wird gespiegelt."""
    ys = [KANZEL_Y1, 0.96, 0.78, 0.56, KANZEL_Y0]
    rechts = [(deck_breite(y), y) for y in ys]
    return [(0.0, KANZEL_Y1 + 0.05)] + rechts


def bauen():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    me = bpy.data.meshes.new("C130_Cockpit")
    ob = bpy.data.objects.new("C130_Cockpit", me)
    bpy.context.scene.collection.objects.link(ob)
    for n in MATN:
        me.materials.append(mat(n))
    bm = bmesh.new()

    # --- Rumpfhaut ---------------------------------------------------------------------
    ringe = []
    for st in STATIONEN:
        kappen = KANZEL_Y0 - 0.001 <= st[0] <= KANZEL_Y1 + 0.001
        ringe.append(ring(st[0], st[1], st[2], st[3], kappen))
    for si in range(len(ringe) - 1):
        for k in range(SEITEN):
            j = (k + 1) % SEITEN
            ecken = [ringe[si][k], ringe[si][j], ringe[si + 1][j], ringe[si + 1][k]]
            if (ecken[0] - ecken[1]).length < 1e-6 and (ecken[3] - ecken[2]).length < 1e-6:
                continue                       # entartet auf der Deckkante
            m = MI["radome"] if si >= RADOM_AB else MI["cockpit_body"]
            quad(bm, ecken, m)
    flaeche(bm, [bm.verts.new(p) for p in ringe[0]], MI["cockpit_body"])
    spitze = bm.verts.new((0.0, NASE_Y + 0.05,
                           (STATIONEN[-1][2] + STATIONEN[-1][3]) * 0.5))
    for k in range(SEITEN):
        j = (k + 1) % SEITEN
        flaeche(bm, [bm.verts.new(ringe[-1][j]), bm.verts.new(ringe[-1][k]), spitze],
                MI["radome"])

    # Haut nach AUSSEN drehen. NICHT ueber recalc_face_normals: das richtet eine OFFENE
    # Roehre nur KONSISTENT aus — gemessen zeigten so 192 von 192 Flaechen nach innen und
    # alle Aufsaetze verschwanden im Rumpf. Darum je Flaeche gegen die Rumpfachse pruefen.
    bm.normal_update()
    falsch = []
    for f in bm.faces:
        m = f.calc_center_median()
        bx, oz, uz = station_bei(m.y)
        aussen = mathutils.Vector((m.x, 0.0, m.z - (oz + uz) * 0.5))
        if aussen.length > 1e-6 and f.normal.dot(aussen) < 0.0:
            falsch.append(f)
    if falsch:
        bmesh.ops.reverse_faces(bm, faces=falsch)
    bm.normal_update()
    print("    Haut: %d von %d Flaechen gedreht" % (len(falsch), len(bm.faces)))

    # --- KANZELAUFBAU --------------------------------------------------------------------
    halb = kanzel_umriss()
    umriss = [(-x, y) for x, y in reversed(halb[1:])] + halb    # links -> vorn -> rechts
    unten = [mathutils.Vector((x, y, deck_z(y))) for x, y in umriss]
    oben = []
    for x, y in umriss:
        bz = breite_bei_z(y, BRAUE_Z)
        sx = 0.0 if abs(x) < 1e-6 else math.copysign(1.0, x)
        # x auf die Rumpfkontur ziehen, y leicht zurueck -> die Scheiben legen sich an
        oben.append(mathutils.Vector((sx * min(abs(x), bz), y - NEIGUNG * 0.55, BRAUE_Z)))
    n_seg = len(umriss) - 1
    for i in range(n_seg):
        ecken = [unten[i], unten[i + 1], oben[i + 1], oben[i]]
        mitte = (ecken[0] + ecken[1] + ecken[2] + ecken[3]) * 0.25
        n = mathutils.Vector((mitte.x, mitte.y - KANZEL_Y0, 0.30))
        if n.length < 1e-6:
            n = mathutils.Vector((0.0, 1.0, 0.30))
        n.normalize()
        if i == 0 or i == n_seg - 1:
            quad(bm, ecken, MI["cockpit_body"])      # hinterste Felder: Blech
        else:
            scheibe(bm, ecken, n)
    # Dach auf Brauenhoehe + Keil nach hinten auf den Rumpfruecken
    for i in range(n_seg):
        a, b = oben[i], oben[i + 1]
        fa = mathutils.Vector((0.0, a.y, station_bei(a.y)[1]))
        fb = mathutils.Vector((0.0, b.y, station_bei(b.y)[1]))
        if (fa - fb).length < 1e-6:
            flaeche(bm, [bm.verts.new(a), bm.verts.new(b), bm.verts.new(fa)],
                    MI["cockpit_body"])
        else:
            quad(bm, [a, b, fb, fa], MI["cockpit_body"])
    ruecken_z = station_bei(KANZEL_Y0 - 0.30)[1]
    kl = mathutils.Vector((oben[0].x, oben[0].y, BRAUE_Z))
    kr = mathutils.Vector((oben[-1].x, oben[-1].y, BRAUE_Z))
    hl = mathutils.Vector((kl.x * 0.70, KANZEL_Y0 - 0.34, ruecken_z - 0.02))
    hr = mathutils.Vector((kr.x * 0.70, KANZEL_Y0 - 0.34, ruecken_z - 0.02))
    quad(bm, [kl, kr, hr, hl], MI["cockpit_body"])
    for ecke, hint in ((kr, hr), (kl, hl)):
        flaeche(bm, [bm.verts.new(ecke), bm.verts.new(hint),
                     bm.verts.new(mathutils.Vector((ecke.x, KANZEL_Y0,
                                                    deck_z(KANZEL_Y0))))],
                MI["cockpit_body"])

    # --- Anbauten ------------------------------------------------------------------------
    kasten(bm, (0.0, 0.60, BRAUE_Z + 0.03), (0.34, 0.40, 0.06), MI["cockpit_body"])
    kasten(bm, (0.0, 0.60, BRAUE_Z + 0.06), (0.25, 0.30, 0.02), MI["dark"])
    kasten(bm, (0.0, -0.78, 0.96), (0.09, 0.14, 0.13), MI["cockpit_body"])
    for sx in (-1.0, 1.0):
        kasten(bm, (sx * 0.74, 1.06, 0.00), (0.045, 0.38, 0.045), MI["dark"])
    # kleine Beobachtungsfenster tief an der Nasenseite (statt der zu grossen Kinnfelder)
    for sx in (-1.0, 1.0):
        for yy in (0.60, 0.92):
            bx = station_bei(yy)[0]
            f = [mathutils.Vector((sx * bx, yy - 0.12, -0.14)),
                 mathutils.Vector((sx * bx, yy + 0.12, -0.14)),
                 mathutils.Vector((sx * bx, yy + 0.12, 0.10)),
                 mathutils.Vector((sx * bx, yy - 0.12, 0.10))]
            scheibe(bm, f, mathutils.Vector((sx, 0.0, 0.0)), 0.012, 0.16)
    # Tuer und Kabinenfenster hinten
    for sx in (-1.0, 1.0):
        quad(bm, [mathutils.Vector((sx * 0.966, -1.26, -0.38)),
                  mathutils.Vector((sx * 0.966, -0.76, -0.38)),
                  mathutils.Vector((sx * 0.966, -0.76, 0.32)),
                  mathutils.Vector((sx * 0.966, -1.26, 0.32))], MI["frame"])
        for yy in (-0.34, -0.06):
            f = [mathutils.Vector((sx * 0.962, yy - 0.09, 0.22)),
                 mathutils.Vector((sx * 0.962, yy + 0.09, 0.22)),
                 mathutils.Vector((sx * 0.962, yy + 0.09, 0.40)),
                 mathutils.Vector((sx * 0.962, yy - 0.09, 0.40))]
            scheibe(bm, f, mathutils.Vector((sx, 0.0, 0.0)), 0.008, 0.18)
    for yy in (-1.02, -0.52, 0.04):
        spantlinie(bm, yy)

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
    print("    Andockflaeche %.2f x %.2f | Deck %.2f..%.2f | Braue %.2f | Deckbreite vorn %.2f"
          % (STATIONEN[0][1] * 2, STATIONEN[0][2] * 2, DECK_HINTEN, DECK_VORN, BRAUE_Z,
             deck_breite(KANZEL_Y1) * 2))

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
                ("c130_schraeg", (3.6, 3.9, 2.4), (0.0, 0.45, 0.0)),
                ("c130_seite", (5.4, 0.3, 0.4), (0.0, 0.2, 0.05)),
                ("c130_vorn", (1.7, 5.2, 1.5), (0.0, 1.1, 0.1))):
            cam.location = pos
            d = mathutils.Vector(ziel) - mathutils.Vector(pos)
            cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(PREVIEW, name + ".png")
            bpy.ops.render.render(write_still=True)


main()
