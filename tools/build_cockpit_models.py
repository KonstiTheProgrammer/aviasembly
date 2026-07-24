# Die vier GENERISCHEN Kanzeln neu und hochwertig modellieren:
#   models/cockpit_bubble.glb · cockpit_jet.glb · cockpit_frame.glb · cockpit_tandem.glb
# und dazu die Querschnitte fuer die passenden Rumpfsegmente
#   -> tools/cockpit_profiles.json (wird als PartCatalog-Konstanten eingespielt)
#
# WARUM NEU: die alten Teile waren rundum geschlossene Tuben mit aufgesetzter Blase (~2000
# Tris, kein Innenraum, gewoelbte Enden -> ein andockendes Rumpfsegment stiess an eine
# Rundung). Jetzt:
#   * ABGEFLACHTE ENDEN: Vorder- und Rueckseite sind ebene Deckel auf EINEM definierten
#     Profil. Das gleiche Profil bekommt das zugehoerige Rumpfsegment (fuselage_<stil>),
#     dadurch geht die Haut ohne Absatz weiter.
#   * ECHTER INNENRAUM: die Oeffnung wird aus der Haut herausgeschnitten und die Kante zu
#     einer Wanne heruntergezogen (bmesh: Randschleife extrudieren + Boden fuellen) —
#     kein aufgesetzter Kasten, sondern eine wirkliche Vertiefung.
#   * EINRICHTUNG: Sitz mit Lehne/Kopfstuetze/Gurten, Instrumentenbrett mit Rundinstrumenten,
#     Steuerknueppel, Pedale, Seitenkonsolen, Ueberrollbuegel.
#   * KANZEL: Scheibe + Rahmenprofil je Stil (Blase, Tropfen, Sprossen, Tandem mit Mittelsteg).
#
# Achsen (Projektkonvention): Blender +Y = Godot -Z = VORNE. Querschnitt liegt in X (Breite)
# und Z (Hoehe). Godot-size = (X, Z, Y).
#
# Usage: blender --background --python tools/build_cockpit_models.py
#        COCKPIT_PREVIEW=<ordner> ... rendert Kontrollbilder
import bpy
import bmesh
import json
import math
import os
from mathutils import Vector

ROOT = "C:/Users/Konst/Projects/aviasembly/"
OUT_MODELS = ROOT + "models/"
PROFILE_JSON = ROOT + "tools/cockpit_profiles.json"
PREVIEW = os.environ.get("COCKPIT_PREVIEW", "")

PROFIL_PUNKTE = 32          # Querschnittsaufloesung (auch fuer das Rumpfsegment)


# --- Material ------------------------------------------------------------------------------
def srgb2lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


MATS = {
    # Name -> (sRGB, metallic, roughness, alpha)
    "cockpit_body": ((0.78, 0.79, 0.82), 0.35, 0.42, 1.0),   # lackierbar (PAINT_MATS)
    "glass":        ((0.62, 0.76, 0.84), 0.05, 0.06, 0.30),
    "frame":        ((0.30, 0.32, 0.36), 0.70, 0.35, 1.0),
    "dark":         ((0.10, 0.11, 0.13), 0.30, 0.60, 1.0),
    "seat":         ((0.24, 0.26, 0.30), 0.10, 0.75, 1.0),
    "leather":      ((0.29, 0.18, 0.12), 0.00, 0.72, 1.0),
    "dash":         ((0.13, 0.14, 0.16), 0.20, 0.55, 1.0),
    "gauge":        ((0.72, 0.76, 0.80), 0.10, 0.25, 1.0),
    "metal":        ((0.55, 0.57, 0.61), 0.80, 0.30, 1.0),
}


def get_mat(name):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    col, met, rough, alpha = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    lin = srgb2lin(col)
    if b:
        b.inputs["Base Color"].default_value = (*lin, alpha)
        b.inputs["Metallic"].default_value = met
        b.inputs["Roughness"].default_value = rough
        if alpha < 1.0:
            b.inputs["Alpha"].default_value = alpha
            m.blend_method = 'BLEND'
    m.diffuse_color = (*lin, alpha)
    return m


# --- Geometrie-Helfer ----------------------------------------------------------------------
def superellipse(n, ax, az, exp, flach_unten=0.0):
    """Geschlossener CCW-Punktzug in [-0.5,0.5]^2 (x, z). exp>2 = kastiger."""
    pts = []
    for i in range(n):
        a = 2.0 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        x = math.copysign(abs(c) ** (2.0 / exp), c) * ax
        z = math.copysign(abs(s) ** (2.0 / exp), s) * az
        if flach_unten > 0.0 and z < -az * (1.0 - flach_unten):
            z = -az * (1.0 - flach_unten)          # Rumpfunterseite abflachen
        pts.append((x, z))
    return pts


def neues_objekt(name, mat_namen):
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for mn in mat_namen:
        me.materials.append(get_mat(mn))
    return ob


def bm_box(bm, ctr, size, mat_idx, rot_x=0.0):
    """Achsparallele Box (optional um X gekippt) in das bmesh legen."""
    cx, cy, cz = ctr
    sx, sy, sz = size
    ecken = []
    for dx in (-0.5, 0.5):
        for dy in (-0.5, 0.5):
            for dz in (-0.5, 0.5):
                y, z = dy * sy, dz * sz
                if rot_x:
                    ca, sa = math.cos(rot_x), math.sin(rot_x)
                    y, z = y * ca - z * sa, y * sa + z * ca
                ecken.append(bm.verts.new((cx + dx * sx, cy + y, cz + z)))
    idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for f in idx:
        try:
            face = bm.faces.new([ecken[i] for i in f])
            face.material_index = mat_idx
        except ValueError:
            pass


def bm_zyl(bm, ctr, r, laenge, achse, mat_idx, seiten=12, r2=None):
    """Zylinder entlang 'x'/'y'/'z'."""
    r2 = r if r2 is None else r2
    ringe = []
    for e, rr in ((-0.5, r), (0.5, r2)):
        ring = []
        for i in range(seiten):
            a = 2.0 * math.pi * i / seiten
            c, s = math.cos(a) * rr, math.sin(a) * rr
            if achse == "y":
                p = (ctr[0] + c, ctr[1] + e * laenge, ctr[2] + s)
            elif achse == "x":
                p = (ctr[0] + e * laenge, ctr[1] + c, ctr[2] + s)
            else:
                p = (ctr[0] + c, ctr[1] + s, ctr[2] + e * laenge)
            ring.append(bm.verts.new(p))
        ringe.append(ring)
    for i in range(seiten):
        j = (i + 1) % seiten
        try:
            f = bm.faces.new([ringe[0][i], ringe[0][j], ringe[1][j], ringe[1][i]])
            f.material_index = mat_idx
        except ValueError:
            pass
    for ring, umdrehen in ((ringe[0], True), (ringe[1], False)):
        try:
            f = bm.faces.new(list(reversed(ring)) if umdrehen else list(ring))
            f.material_index = mat_idx
        except ValueError:
            pass


def rumpfhaut(bm, profil, breite, hoehe, y0, y1, segs, mat_idx):
    """Gelofteter Rumpf mit EBENEN Deckeln bei y0/y1 (das sind die Andockflaechen)."""
    n = len(profil)
    ringe = []
    for k in range(segs + 1):
        y = y0 + (y1 - y0) * k / segs
        ring = [bm.verts.new((px * breite, y, pz * hoehe)) for px, pz in profil]
        ringe.append(ring)
    for k in range(segs):
        for i in range(n):
            j = (i + 1) % n
            f = bm.faces.new([ringe[k][i], ringe[k][j], ringe[k + 1][j], ringe[k + 1][i]])
            f.material_index = mat_idx
    f = bm.faces.new(list(reversed(ringe[0])))          # vorderer Deckel (flach!)
    f.material_index = mat_idx
    f = bm.faces.new(list(ringe[-1]))                   # hinterer Deckel (flach!)
    f.material_index = mat_idx
    return ringe


def panelband(bm, profil, breite, hoehe, y, dicke, mat_idx, aufmass=1.006):
    """Umlaufende Stossnaht, die dem PROFIL folgt (ein Kreisring stuende auf einem
    kastigen Querschnitt an den flachen Seiten ab)."""
    n = len(profil)
    ringe = []
    for e in (-0.5, 0.5):
        ringe.append([bm.verts.new((px * breite * aufmass, y + e * dicke, pz * hoehe * aufmass))
                      for px, pz in profil])
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new([ringe[0][i], ringe[0][j], ringe[1][j], ringe[1][i]])
        f.material_index = mat_idx


def oeffnung_schneiden(bm, y_von, y_bis, z_min, x_max, tiefe, mat_idx):
    """Deckel-Flaechen ueber z_min im Bereich [y_von,y_bis] entfernen und die entstandene
    Randschleife zu einer WANNE herunterziehen (echte Vertiefung statt aufgesetztem Kasten)."""
    bm.normal_update()          # FALLE: nach faces.new() ist f.normal noch (0,0,0) —
    bm.faces.ensure_lookup_table()   # ohne das trifft der Filter unten NICHTS.
    weg = [f for f in bm.faces
           if y_von <= f.calc_center_median().y <= y_bis
           and f.calc_center_median().z > z_min
           and abs(f.calc_center_median().x) < x_max
           and f.normal.z > 0.05]
    print("   Ausschnitt y=%.2f..%.2f: %d Flaechen entfernt" % (y_von, y_bis, len(weg)))
    if not weg:
        return
    bmesh.ops.delete(bm, geom=weg, context='FACES')
    rand = [e for e in bm.edges if len(e.link_faces) == 1]
    if not rand:
        return
    ext = bmesh.ops.extrude_edge_only(bm, edges=rand)
    neue = [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]
    for v in neue:                                       # nach innen und unten
        v.co.z = tiefe
        v.co.x *= 0.82
        v.co.y += -0.02 if v.co.y > (y_von + y_bis) * 0.5 else 0.02
    for f in ext["geom"]:
        if isinstance(f, bmesh.types.BMFace):
            f.material_index = mat_idx
    boden = [e for e in bm.edges if len(e.link_faces) == 1]
    res = bmesh.ops.holes_fill(bm, edges=boden)
    for f in res.get("faces", []):
        f.material_index = mat_idx
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def laengs_faktor(t, spitz):
    """Hoehenverlauf der Haube ueber die Laenge. t=0 hinten, t=1 VORNE (+Y = Nase).
    Vorne faellt sie zum Windschutz ab, hinten laeuft sie in den Ruecken aus."""
    def weich(u):                                 # Smoothstep -> gerundete Uebergaenge
        u = min(max(u, 0.0), 1.0)
        return u * u * (3.0 - 2.0 * u)
    f = 1.0
    if t > 0.72:                                  # Windschutz-Schraege nach vorn
        f = 0.16 + 0.84 * weich((1.0 - t) / 0.28)
    if spitz and t < 0.30:                        # Auslauf in den Ruecken
        f = min(f, 0.05 + 0.95 * weich(t / 0.30))
    return f


def haube(bm, sill, y0, y1, hoehe, breite, rundung, spitz, mi_glas, mi_rahmen,
          spanten=2, dicke=0.021):
    """Kanzel: Glasschale plus Spanten, beide aus DEMSELBEN Laengsprofil — dadurch sitzen
    die Buegel exakt auf der Scheibe statt daneben."""
    bogen, segs = 14, 20

    def punkt(t, i, aufmass=0.0):
        f = laengs_faktor(t, spitz)
        a = math.pi * i / bogen
        x = -math.cos(a) * (breite + aufmass) * (0.62 + 0.38 * f)
        z = sill + math.sin(a) ** rundung * (hoehe + aufmass) * f
        return (x, y0 + (y1 - y0) * t, z)

    ringe = []
    for k in range(segs + 1):
        t = k / segs
        ringe.append([bm.verts.new(punkt(t, i)) for i in range(bogen + 1)])
    for k in range(segs):
        for i in range(bogen):
            f = bm.faces.new([ringe[k][i], ringe[k][i + 1],
                              ringe[k + 1][i + 1], ringe[k + 1][i]])
            f.material_index = mi_glas

    # Spanten: Randbogen vorn/hinten + gleichmaessig verteilte Zwischenspanten
    ts = [0.02, 0.985]
    for k in range(spanten):
        ts.append(0.14 + (0.72) * (k + 1) / (spanten + 1))
    for t in ts:
        vor = None
        for i in range(bogen + 1):
            p = punkt(t, i, aufmass=0.004)
            if vor is not None:
                mx, mz = (vor[0] + p[0]) * 0.5, (vor[2] + p[2]) * 0.5
                laenge = math.dist((vor[0], vor[2]), (p[0], p[2])) + dicke * 0.5
                w = math.atan2(p[2] - vor[2], p[0] - vor[0])
                ca, sa = math.cos(w), math.sin(w)
                ecken = []
                for dl in (-0.5, 0.5):
                    for dq in (-0.5, 0.5):
                        for dy in (-0.5, 0.5):
                            lx, lz = dl * laenge, dq * dicke
                            ecken.append(bm.verts.new(
                                (mx + lx * ca - lz * sa, p[1] + dy * dicke * 1.5,
                                 mz + lx * sa + lz * ca)))
                for fc in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
                           (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
                    try:
                        face = bm.faces.new([ecken[i2] for i2 in fc])
                        face.material_index = mi_rahmen
                    except ValueError:
                        pass
            vor = p
    # Laengsholm auf dem Suellrand (verbindet die Spanten)
    for sx in (-1, 1):
        p0 = punkt(0.0, 0 if sx < 0 else bogen)
        p1 = punkt(1.0, 0 if sx < 0 else bogen)
        bm_box(bm, ((p0[0] + p1[0]) * 0.5, (p0[1] + p1[1]) * 0.5, sill + 0.012),
               (dicke * 1.6, abs(p1[1] - p0[1]), dicke * 1.2), mi_rahmen)


def einrichtung(bm, y_sitz, sill, boden, mi):
    """Sitz, Instrumentenbrett mit Rundinstrumenten, Knueppel, Pedale, Konsolen."""
    m_seat, m_leather, m_dash, m_gauge, m_dark, m_metal = mi
    # Sitzwanne + Lehne + Kopfstuetze
    bm_box(bm, (0.0, y_sitz, boden + 0.10), (0.42, 0.40, 0.10), m_seat)
    bm_box(bm, (0.0, y_sitz - 0.20, boden + 0.36), (0.42, 0.09, 0.52), m_seat, rot_x=-0.14)
    bm_box(bm, (0.0, y_sitz - 0.24, boden + 0.66), (0.30, 0.11, 0.16), m_leather)
    for sx in (-1, 1):                                    # Gurte
        bm_box(bm, (sx * 0.13, y_sitz - 0.16, boden + 0.40), (0.07, 0.03, 0.44), m_leather,
               rot_x=-0.14)
    # Instrumentenbrett schraeg vor dem Sitz
    y_dash = y_sitz + 0.46
    bm_box(bm, (0.0, y_dash, sill - 0.16), (0.62, 0.10, 0.34), m_dash, rot_x=0.30)
    for k in range(3):                                    # Rundinstrumente
        bm_zyl(bm, (-0.18 + k * 0.18, y_dash - 0.06, sill - 0.13), 0.055, 0.03, "y", m_gauge, 10)
    for k in range(2):
        bm_zyl(bm, (-0.10 + k * 0.20, y_dash - 0.06, sill - 0.26), 0.045, 0.03, "y", m_gauge, 10)
    # Steuerknueppel + Griff
    bm_zyl(bm, (0.0, y_sitz + 0.24, boden + 0.20), 0.022, 0.34, "z", m_metal, 8)
    bm_box(bm, (0.0, y_sitz + 0.24, boden + 0.40), (0.05, 0.06, 0.10), m_dark)
    # Pedale
    for sx in (-1, 1):
        bm_box(bm, (sx * 0.11, y_sitz + 0.52, boden + 0.07), (0.09, 0.14, 0.04), m_dark, rot_x=0.25)
    # Seitenkonsolen
    for sx in (-1, 1):
        bm_box(bm, (sx * 0.26, y_sitz + 0.10, boden + 0.16), (0.10, 0.52, 0.16), m_dark)
    bm_box(bm, (-0.26, y_sitz + 0.30, boden + 0.28), (0.05, 0.14, 0.05), m_metal)   # Schubhebel


# --- Die vier Kanzeln ----------------------------------------------------------------------
# size = Godot (x=Breite, y=Hoehe, z=Laenge); in Blender: X=Breite, Z=Hoehe, Y=Laenge
STILE = {
    "cockpit_bubble": {
        "size": (1.3, 1.3, 2.4), "exp": 2.15, "flach_unten": 0.10,
        "sill": 0.26, "boden": -0.16, "oeff": (-0.20, 0.28), "x_off": 0.30,
        "haube": {"hoehe": 0.46, "breite": 0.40, "rundung": 0.85, "spitz": True},
        "spanten": 1, "buegel": True, "tandem": False,
    },
    "cockpit_jet": {
        "size": (1.1, 1.1, 2.6), "exp": 2.6, "flach_unten": 0.06,
        "sill": 0.24, "boden": -0.14, "oeff": (-0.14, 0.34), "x_off": 0.26,
        "haube": {"hoehe": 0.34, "breite": 0.32, "rundung": 1.25, "spitz": True},
        "spanten": 0, "buegel": False, "tandem": False,
    },
    "cockpit_frame": {
        "size": (1.35, 1.35, 2.25), "exp": 3.1, "flach_unten": 0.12,
        "sill": 0.22, "boden": -0.18, "oeff": (-0.20, 0.26), "x_off": 0.31,
        "haube": {"hoehe": 0.42, "breite": 0.42, "rundung": 0.70, "spitz": False},
        "spanten": 4, "buegel": True, "tandem": False,
    },
    "cockpit_tandem": {
        "size": (1.225, 1.225, 3.1), "exp": 2.35, "flach_unten": 0.10,
        "sill": 0.25, "boden": -0.16, "oeff": (-0.34, 0.36), "x_off": 0.28,
        "haube": {"hoehe": 0.42, "breite": 0.38, "rundung": 0.90, "spitz": True},
        "spanten": 1, "buegel": True, "tandem": True,
    },
}


def baue(pid, spec):
    sx, sz, sy = spec["size"]                    # Godot x,y,z -> Blender X,Z,Y
    profil = superellipse(PROFIL_PUNKTE, 0.5, 0.5, spec["exp"], spec["flach_unten"])
    breite, hoehe, laenge = sx, sz, sy
    y0, y1 = -laenge * 0.5, laenge * 0.5

    matn = ["cockpit_body", "glass", "frame", "dark", "seat", "leather", "dash", "gauge", "metal"]
    ob = neues_objekt(pid, matn)
    M = {n: i for i, n in enumerate(matn)}

    bm = bmesh.new()
    rumpfhaut(bm, profil, breite, hoehe, y0, y1, 20, M["cockpit_body"])
    # Wicklung EINMAL zentral richten: von Hand gebaute Ringe zeigten nach INNEN, dadurch
    # fand der Ausschnitt-Filter (normal.z > 0) keine einzige Deckflaeche.
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    sill_z = spec["sill"] * hoehe
    boden_z = spec["boden"] * hoehe
    oeff = spec["oeff"]
    x_max = spec["x_off"] * breite

    if spec["tandem"]:
        mitte = (oeff[0] + oeff[1]) * 0.5
        oeffnung_schneiden(bm, oeff[0] * laenge, (mitte - 0.06) * laenge, sill_z, x_max,
                           boden_z, M["dark"])
        oeffnung_schneiden(bm, (mitte + 0.06) * laenge, oeff[1] * laenge, sill_z, x_max,
                           boden_z, M["dark"])
    else:
        oeffnung_schneiden(bm, oeff[0] * laenge, oeff[1] * laenge, sill_z, x_max,
                           boden_z, M["dark"])

    # Einrichtung (bei Tandem zweimal)
    mi = (M["seat"], M["leather"], M["dash"], M["gauge"], M["dark"], M["metal"])
    if spec["tandem"]:
        einrichtung(bm, oeff[1] * laenge - 0.42, sill_z, boden_z, mi)
        einrichtung(bm, (oeff[0] + oeff[1]) * 0.5 * laenge - 0.34, sill_z, boden_z, mi)
    else:
        einrichtung(bm, (oeff[0] * 0.35 + oeff[1] * 0.65) * laenge - 0.12, sill_z, boden_z, mi)

    # Kanzelrand (Suellrand) rundum die Oeffnung
    for sx2 in (-1, 1):
        bm_box(bm, (sx2 * x_max, (oeff[0] + oeff[1]) * 0.5 * laenge, sill_z),
               (0.06, (oeff[1] - oeff[0]) * laenge, 0.07), M["frame"])
    for yy in (oeff[0] * laenge, oeff[1] * laenge):
        bm_box(bm, (0.0, yy, sill_z), (x_max * 2.0, 0.06, 0.07), M["frame"])

    # Ueberrollbuegel hinter dem Sitz
    if spec["buegel"]:
        yb = oeff[0] * laenge + 0.16
        bm_box(bm, (0.0, yb, sill_z + 0.12), (x_max * 1.5, 0.07, 0.24), M["frame"])

    # Rumpfdetails: Panellinien, Griff, Trittstufe, Antenne
    for yy in (y0 + laenge * 0.20, y1 - laenge * 0.20):
        panelband(bm, profil, breite, hoehe, yy, 0.035, M["frame"])
    bm_box(bm, (breite * 0.42, oeff[0] * laenge + 0.10, sill_z - 0.16), (0.05, 0.18, 0.05),
           M["metal"])                                          # Haltegriff
    bm_box(bm, (breite * 0.44, oeff[0] * laenge - 0.14, -hoehe * 0.10), (0.04, 0.16, 0.03),
           M["dark"])                                           # Trittstufe
    bm_zyl(bm, (0.0, y0 + 0.20, hoehe * 0.48), 0.018, 0.30, "z", M["metal"], 6)   # Antenne

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])   # auch Sitz/Instrumente/Rohre
    bm.normal_update()
    bm.to_mesh(ob.data)
    bm.free()

    # Haube als EIGENES Objekt (transparentes Material sauber getrennt)
    hb = spec["haube"]
    gl = neues_objekt(pid + "_Glas", ["glass", "frame"])
    bg = bmesh.new()
    hs = sill_z + 0.015
    if spec["tandem"]:
        mitte = (oeff[0] + oeff[1]) * 0.5
        haube(bg, hs, oeff[0] * laenge, (mitte - 0.03) * laenge, hb["hoehe"] * hoehe,
              hb["breite"] * breite, hb["rundung"], hb["spitz"], 0, 1, spec["spanten"])
        haube(bg, hs, (mitte + 0.03) * laenge, oeff[1] * laenge, hb["hoehe"] * hoehe,
              hb["breite"] * breite, hb["rundung"], hb["spitz"], 0, 1, spec["spanten"])
    else:
        haube(bg, hs, oeff[0] * laenge, oeff[1] * laenge, hb["hoehe"] * hoehe,
              hb["breite"] * breite, hb["rundung"], hb["spitz"], 0, 1, spec["spanten"])
    bmesh.ops.recalc_face_normals(bg, faces=bg.faces[:])
    bg.normal_update()
    bg.to_mesh(gl.data)
    bg.free()
    gl.parent = ob
    return ob, gl, profil


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    profile_out = {}
    bericht = []
    for pid, spec in STILE.items():
        ob, gl, profil = baue(pid, spec)
        profile_out[pid] = [[round(x, 4), round(z, 4)] for x, z in profil]

        for o in (ob, gl):
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.shade_auto_smooth(angle=math.radians(38))
            o.select_set(False)

        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        gl.select_set(True)
        bpy.context.view_layer.objects.active = ob
        pfad = OUT_MODELS + pid + ".glb"
        bpy.ops.export_scene.gltf(filepath=pfad, export_format='GLB', use_selection=True,
                                  export_apply=True)
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons) + \
            sum(len(p.vertices) - 2 for p in gl.data.polygons)
        bericht.append((pid, tris))
        print("EXPORTED %s  %d Tris" % (pfad, tris))
        bpy.ops.object.select_all(action='DESELECT')

    with open(PROFILE_JSON, "w") as f:
        json.dump(profile_out, f, indent=1)
    print("PROFILE ->", PROFILE_JSON)
    for pid, t in bericht:
        print("  %-18s %5d Tris" % (pid, t))

    if PREVIEW:
        render(bericht)


def render(bericht):
    scn = bpy.context.scene
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scn.collection.objects.link(cam)
    scn.camera = cam
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'MATERIAL'
    scn.render.resolution_x, scn.render.resolution_y = 1200, 900
    for pid, _t in bericht:
        objs = [bpy.data.objects[pid], bpy.data.objects[pid + "_Glas"]]
        lo = Vector((1e9,) * 3)
        hi = Vector((-1e9,) * 3)
        for o in objs:
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
        ctr = (lo + hi) * 0.5
        r = max((hi - lo).length * 0.5, 0.5)
        cam.data.lens = 50
        fov = 2.0 * math.atan(0.5 * 36.0 / cam.data.lens)
        dist = r / math.sin(fov * 0.5) * 1.05
        cam.location = ctr + Vector((-0.62, -0.72, 0.36)).normalized() * dist
        cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scn.render.filepath = os.path.join(PREVIEW, "cp_%s.png" % pid.replace("cockpit_", ""))
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", scn.render.filepath)


main()
