# Die vier GENERISCHEN Kanzeln modellieren:
#   models/cockpit_bubble.glb · cockpit_jet.glb · cockpit_frame.glb · cockpit_tandem.glb
#   + tools/cockpit_profiles.json (Querschnitte fuer die Rumpfsegmente fuselage_<stil>)
#   + blender_lib/kanzeln.blend (Kanzel samt angedocktem Segment zum Anschauen)
#
# ENTWURF — die erste Fassung sah aus wie ein Fass mit aufgeklebter Blase. Ursache: der
# Querschnitt war ueber die GANZE Laenge konstant. Abgeflachte Enden sind aber nur an ZWEI
# Stellen Pflicht (y = ±L/2). Daher jetzt:
#   * AUFGEHENDES DECK (`deck_hub`): der Ruecken steigt zwischen den Enden an und laeuft zu
#     beiden Stirnflaechen exakt aufs Profil zurueck -> Silhouette statt Fasskontur, das
#     Andocken bleibt spaltfrei.
#   * SUELLRAND: die Oeffnungskante wird erst nach OBEN zu einer Lippe gezogen und dann nach
#     innen in die Wanne — kein danebenstehender Kastenrahmen mehr.
#   * Die HAUBE sitzt auf dieser Lippe auf, ist fast so breit wie der Rumpf, hat vorne eine
#     abgesetzte Windschutzscheibe und laeuft hinten ins Deck aus.
#   * BLENDSCHUTZHAUBE ueber dem Instrumentenbrett — das Detail, das ein Cockpit lesbar macht.
#   * Die RAHMEN-Kanzel ist FACETTIERT (flache Scheiben, Sprossen auf jeder Kante); eine
#     Sprossenhaube ist eckig, nicht rundgelutscht.
#   * Panelnaehte duenn und dem Profil folgend (dicke Kreisringe sahen aus wie Fassreifen).
#
# Achsen (Projektkonvention): Blender +Y = Godot -Z = VORNE. Querschnitt in X (Breite) und
# Z (Hoehe). Godot-size = (X, Z, Y).  t laeuft 0 = HINTEN .. 1 = VORNE.
#
# Usage: blender --background --python tools/build_cockpit_models.py
import bpy
import bmesh
import json
import math

ROOT = "C:/Users/Konst/Projects/aviasembly/"
OUT_MODELS = ROOT + "models/"
PROFILE_JSON = ROOT + "tools/cockpit_profiles.json"
BLEND_OUT = ROOT + "blender_lib/kanzeln.blend"
PROFIL_PUNKTE = 32
SEGS = 30                     # Laengsstationen des Rumpfs


def srgb2lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


MATS = {
    "cockpit_body": ((0.78, 0.79, 0.82), 0.35, 0.42, 1.0),
    "glass":        ((0.60, 0.75, 0.84), 0.05, 0.06, 0.28),
    "frame":        ((0.26, 0.28, 0.32), 0.70, 0.35, 1.0),
    "dark":         ((0.09, 0.10, 0.12), 0.25, 0.62, 1.0),
    "seat":         ((0.22, 0.25, 0.29), 0.10, 0.75, 1.0),
    "leather":      ((0.29, 0.18, 0.12), 0.00, 0.72, 1.0),
    "dash":         ((0.12, 0.13, 0.15), 0.20, 0.55, 1.0),
    "gauge":        ((0.74, 0.78, 0.82), 0.10, 0.25, 1.0),
    "metal":        ((0.55, 0.57, 0.61), 0.80, 0.30, 1.0),
    "cp_gruen":     ((0.26, 0.31, 0.24), 0.05, 0.70, 1.0),   # britisches Innen-Gruengrau
}
MATN = list(MATS.keys())
MI = {n: i for i, n in enumerate(MATN)}


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


def weich(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3.0 - 2.0 * u)


def superellipse(n, exp, flach_unten=0.0):
    pts = []
    for i in range(n):
        a = 2.0 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        x = math.copysign(abs(c) ** (2.0 / exp), c) * 0.5
        z = math.copysign(abs(s) ** (2.0 / exp), s) * 0.5
        if flach_unten > 0.0 and z < -0.5 * (1.0 - flach_unten):
            z = -0.5 * (1.0 - flach_unten)
        pts.append((x, z))
    return pts


# --- bmesh-Grundformen ---------------------------------------------------------------------
def bx(bm, ctr, size, mi, rot_x=0.0):
    cx, cy, cz = ctr
    sx, sy, sz = size
    v = []
    for dx in (-0.5, 0.5):
        for dy in (-0.5, 0.5):
            for dz in (-0.5, 0.5):
                y, z = dy * sy, dz * sz
                if rot_x:
                    ca, sa = math.cos(rot_x), math.sin(rot_x)
                    y, z = y * ca - z * sa, y * sa + z * ca
                v.append(bm.verts.new((cx + dx * sx, cy + y, cz + z)))
    for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        try:
            bm.faces.new([v[i] for i in f]).material_index = mi
        except ValueError:
            pass


def zyl(bm, ctr, r, laenge, achse, mi, seiten=12):
    ringe = []
    for e in (-0.5, 0.5):
        ring = []
        for i in range(seiten):
            a = 2.0 * math.pi * i / seiten
            c, s = math.cos(a) * r, math.sin(a) * r
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
            bm.faces.new([ringe[0][i], ringe[0][j], ringe[1][j], ringe[1][i]]).material_index = mi
        except ValueError:
            pass
    for ring, um in ((ringe[0], True), (ringe[1], False)):
        try:
            bm.faces.new(list(reversed(ring)) if um else list(ring)).material_index = mi
        except ValueError:
            pass


# --- Rumpf mit aufgehendem Deck -------------------------------------------------------------
def deck_hub(t, hoehe, spec):
    """Anhebung des Ruckens an Laengsposition t. MUSS an beiden Enden 0 sein, sonst passt
    die Stirnflaeche nicht mehr zum Rumpfsegment."""
    if t <= 0.001 or t >= 0.999:
        return 0.0
    hinten = weich(t / 0.16)
    vorne = 1.0 - weich((t - 0.80) / 0.20)
    return hoehe * spec["deck"] * hinten * vorne


def ring_punkte(profil, breite, hoehe, hub):
    """Querschnitt einer Station: nur die OBERE Haelfte wird angehoben, Bauch bleibt."""
    out = []
    for px, pz in profil:
        z = pz * hoehe
        if pz > 0.0:
            z += hub * (pz / 0.5)
        out.append((px * breite, z))
    return out


def rumpf(bm, profil, breite, hoehe, laenge, spec, mi):
    n = len(profil)
    y0, y1 = -laenge * 0.5, laenge * 0.5
    ringe = []
    for k in range(SEGS + 1):
        t = k / SEGS
        y = y0 + (y1 - y0) * t
        pts = ring_punkte(profil, breite, hoehe, deck_hub(t, hoehe, spec))
        ringe.append([bm.verts.new((x, y, z)) for x, z in pts])
    for k in range(SEGS):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new([ringe[k][i], ringe[k][j],
                          ringe[k + 1][j], ringe[k + 1][i]]).material_index = mi
    bm.faces.new(list(reversed(ringe[0]))).material_index = mi      # ebener Heckdeckel
    bm.faces.new(list(ringe[-1])).material_index = mi               # ebener Nasendeckel


def panelnaht(bm, profil, breite, hoehe, spec, t, mi, dicke=0.016, auf=1.004):
    laenge = spec["laenge"]
    y = -laenge * 0.5 + laenge * t
    pts = ring_punkte(profil, breite * auf, hoehe * auf, deck_hub(t, hoehe, spec) * auf)
    n = len(pts)
    ringe = [[bm.verts.new((x, y + e * dicke, z)) for x, z in pts] for e in (-0.5, 0.5)]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new([ringe[0][i], ringe[0][j], ringe[1][j], ringe[1][i]]).material_index = mi


# --- Cockpit-Oeffnung: Lippe hoch, dann Wanne hinunter --------------------------------------
def oeffnung(bm, y_von, y_bis, z_min, x_max, boden, mi_lippe, mi_innen):
    bm.normal_update()
    bm.faces.ensure_lookup_table()
    weg = [f for f in bm.faces
           if y_von <= f.calc_center_median().y <= y_bis
           and f.calc_center_median().z > z_min
           and abs(f.calc_center_median().x) < x_max
           and f.normal.z > 0.05]
    if not weg:
        print("   WARNUNG: Ausschnitt traf keine Flaeche")
        return
    bmesh.ops.delete(bm, geom=weg, context='FACES')

    rand = [e for e in bm.edges if len(e.link_faces) == 1]
    ext = bmesh.ops.extrude_edge_only(bm, edges=rand)          # 1) Suellrand-Lippe
    for v in [v for v in ext["geom"] if isinstance(v, bmesh.types.BMVert)]:
        v.co.x *= 1.035
        v.co.z += 0.045
    for f in ext["geom"]:
        if isinstance(f, bmesh.types.BMFace):
            f.material_index = mi_lippe

    rand2 = [e for e in bm.edges if len(e.link_faces) == 1]
    ext2 = bmesh.ops.extrude_edge_only(bm, edges=rand2)        # 2) hinunter in die Wanne
    for v in [v for v in ext2["geom"] if isinstance(v, bmesh.types.BMVert)]:
        v.co.x *= 0.80
        v.co.z = boden
        v.co.y += -0.03 if v.co.y > (y_von + y_bis) * 0.5 else 0.03
    for f in ext2["geom"]:
        if isinstance(f, bmesh.types.BMFace):
            f.material_index = mi_innen
    for f in bmesh.ops.holes_fill(
            bm, edges=[e for e in bm.edges if len(e.link_faces) == 1]).get("faces", []):
        f.material_index = mi_innen
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()


# --- Innenausbau ----------------------------------------------------------------------------
def innenausbau(bm, y_sitz, sill, boden, b):
    bx(bm, (0.0, y_sitz + 0.02, boden + 0.05), (0.30 * b, 0.34, 0.10), MI["dark"])
    bx(bm, (0.0, y_sitz + 0.02, boden + 0.13), (0.34 * b, 0.36, 0.07), MI["seat"])
    bx(bm, (0.0, y_sitz - 0.19, boden + 0.40), (0.34 * b, 0.09, 0.56), MI["seat"], rot_x=-0.13)
    for sx in (-1, 1):
        bx(bm, (sx * 0.15 * b, y_sitz - 0.17, boden + 0.38), (0.05 * b, 0.10, 0.50),
           MI["seat"], rot_x=-0.13)
        bx(bm, (sx * 0.10 * b, y_sitz - 0.145, boden + 0.42), (0.055 * b, 0.03, 0.46),
           MI["leather"], rot_x=-0.13)
    bx(bm, (0.0, y_sitz - 0.235, boden + 0.70), (0.24 * b, 0.10, 0.15), MI["leather"])

    y_d = y_sitz + 0.44                                    # Brett + BLENDSCHUTZ
    bx(bm, (0.0, y_d, sill - 0.20), (0.54 * b, 0.09, 0.30), MI["dash"], rot_x=0.34)
    bx(bm, (0.0, y_d - 0.09, sill - 0.035), (0.60 * b, 0.22, 0.05), MI["dark"], rot_x=0.16)
    for sx in (-1, 1):
        bx(bm, (sx * 0.29 * b, y_d - 0.06, sill - 0.10), (0.05 * b, 0.16, 0.13), MI["dark"])
    for k in range(3):
        zyl(bm, (-0.14 * b + k * 0.14 * b, y_d - 0.055, sill - 0.17), 0.048, 0.03, "y",
            MI["gauge"], 10)
    for k in range(2):
        zyl(bm, (-0.07 * b + k * 0.14 * b, y_d - 0.055, sill - 0.29), 0.038, 0.03, "y",
            MI["gauge"], 10)

    zyl(bm, (0.0, y_sitz + 0.22, boden + 0.20), 0.020, 0.32, "z", MI["metal"], 8)
    bx(bm, (0.0, y_sitz + 0.22, boden + 0.39), (0.045 * b, 0.055, 0.09), MI["dark"])
    for sx in (-1, 1):
        bx(bm, (sx * 0.09 * b, y_sitz + 0.48, boden + 0.06), (0.075 * b, 0.13, 0.035),
           MI["dark"], rot_x=0.25)
        bx(bm, (sx * 0.24 * b, y_sitz + 0.06, boden + 0.14), (0.07 * b, 0.50, 0.14), MI["dark"])
    bx(bm, (-0.24 * b, y_sitz + 0.26, boden + 0.25), (0.04 * b, 0.12, 0.045), MI["metal"])


# --- Haube -----------------------------------------------------------------------------------
def hauben_hoehe(u, hp):
    """u = 0 hinten .. 1 vorne INNERHALB des Haubenabschnitts."""
    f = 1.0
    if u > hp["ws_ab"]:
        f = hp["ws_rest"] + (1.0 - hp["ws_rest"]) * weich((1.0 - u) / (1.0 - hp["ws_ab"]))
    if u < hp["heck_ab"]:
        f = min(f, hp["heck_rest"] + (1.0 - hp["heck_rest"]) * weich(u / hp["heck_ab"]))
    return f


def hp_von(spec, **ueber):
    """Haubenparameter aus dem Stil, einzeln ueberschreibbar."""
    hp = dict(rundung=spec["rundung"], ws_ab=spec["ws_ab"], ws_rest=spec["ws_rest"],
              heck_ab=spec["heck_ab"], heck_rest=spec["heck_rest"],
              facetten=spec["facetten"], alle_ringe=spec["alle_ringe"],
              spanten=spec["spanten"], holme=True)
    hp.update(ueber)
    return hp


def haube(bm, hp, y0, y1, basis_z, breite, hoehe, mi_glas, mi_rahmen):
    facetten = hp["facetten"]
    bogen = 6 if facetten else 14
    segs = 4 if facetten else 20
    rundung = hp["rundung"]

    def p(u, i, auf=0.0):
        f = hauben_hoehe(u, hp)
        a = math.pi * i / bogen
        x = -math.cos(a) * (breite + auf) * (0.70 + 0.30 * f)
        z = basis_z + math.sin(a) ** rundung * (hoehe + auf) * f
        return (x, y0 + (y1 - y0) * u, z)

    ringe = [[bm.verts.new(p(k / segs, i)) for i in range(bogen + 1)] for k in range(segs + 1)]
    for k in range(segs):
        for i in range(bogen):
            bm.faces.new([ringe[k][i], ringe[k][i + 1],
                          ringe[k + 1][i + 1], ringe[k + 1][i]]).material_index = mi_glas

    us = [0.008, 0.992]
    if hp["alle_ringe"]:
        us += [k / segs for k in range(1, segs)]
    else:
        for k in range(hp["spanten"]):
            us.append(0.16 + 0.68 * (k + 1) / (hp["spanten"] + 1))
    dicke = 0.024
    for u in us:
        vor = None
        for i in range(bogen + 1):
            q = p(u, i, auf=0.006)
            if vor is not None:
                mx, mz = (vor[0] + q[0]) * 0.5, (vor[2] + q[2]) * 0.5
                lg = math.dist((vor[0], vor[2]), (q[0], q[2])) + dicke * 0.4
                w = math.atan2(q[2] - vor[2], q[0] - vor[0])
                ca, sa = math.cos(w), math.sin(w)
                v = []
                for dl in (-0.5, 0.5):
                    for dq in (-0.5, 0.5):
                        for dy in (-0.5, 0.5):
                            lx, lz = dl * lg, dq * dicke
                            v.append(bm.verts.new((mx + lx * ca - lz * sa,
                                                   q[1] + dy * dicke * 1.4,
                                                   mz + lx * sa + lz * ca)))
                for fc in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
                           (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
                    try:
                        bm.faces.new([v[i2] for i2 in fc]).material_index = mi_rahmen
                    except ValueError:
                        pass
            vor = q
    if hp["holme"]:
        for i_rand in (0, bogen):                   # Laengsholme auf dem Suellrand
            a = p(0.0, i_rand)
            b2 = p(1.0, i_rand)
            bx(bm, ((a[0] + b2[0]) * 0.5, (a[1] + b2[1]) * 0.5, basis_z + 0.012),
               (dicke * 1.5, abs(b2[1] - a[1]), dicke * 1.1), mi_rahmen)


def spitfire_extras(bm, spec, breite, hoehe, laenge, y0, sill, boden):
    """Die Merkmale, an denen man eine Spitfire erkennt."""
    o0, o1 = spec["oeff"]
    y_sitz = y0 + laenge * (o0 * 0.30 + o1 * 0.70) - 0.16

    # HALBTUER links (-X): umlaufender Rahmen, leicht vorstehend
    yd = y0 + laenge * (o0 + o1) * 0.5
    tw, th = 0.62, 0.40
    xw = -breite * 0.5 - 0.004
    for dy, dz, sy2, sz2 in ((-tw * 0.5, 0.0, 0.035, th), (tw * 0.5, 0.0, 0.035, th),
                             (0.0, -th * 0.5, tw, 0.035), (0.0, th * 0.5, tw, 0.035)):
        bx(bm, (xw, yd + dy, sill - 0.30 + dz), (0.02, sy2, sz2), MI["frame"])
    bx(bm, (xw - 0.012, yd + tw * 0.30, sill - 0.30), (0.03, 0.09, 0.05), MI["metal"])

    # RUECKSPIEGEL auf dem Scheibenrahmen
    y_ws = y0 + laenge * (o0 + (o1 - o0) * 0.70)
    zt = sill + 0.05 + spec["h_hoehe"] * hoehe * 0.86
    zyl(bm, (0.0, y_ws + 0.04, zt + 0.05), 0.012, 0.10, "z", MI["frame"], 6)
    bx(bm, (0.0, y_ws + 0.04, zt + 0.115), (0.11, 0.05, 0.055), MI["frame"])
    bx(bm, (0.0, y_ws + 0.062, zt + 0.115), (0.09, 0.012, 0.04), MI["gauge"])

    # REFLEXVISIER ueber dem Instrumentenbrett
    y_d = y_sitz + 0.44
    bx(bm, (0.0, y_d - 0.02, sill + 0.02), (0.10, 0.14, 0.09), MI["dark"])
    bx(bm, (0.0, y_d - 0.10, sill + 0.10), (0.09, 0.015, 0.10), MI["glass"])

    # SPATENGRIFF am Knueppel (statt Pistolengriff)
    zyl(bm, (0.0, y_sitz + 0.22, boden + 0.44), 0.062, 0.022, "y", MI["dark"], 12)
    zyl(bm, (0.0, y_sitz + 0.235, boden + 0.44), 0.036, 0.020, "y", MI["cp_gruen"], 10)

    # Bodenbrett + gruengraue Seitenverkleidung
    bx(bm, (0.0, y_sitz + 0.10, boden + 0.015), (0.36 * breite, 0.72, 0.03), MI["cp_gruen"])
    for sx in (-1, 1):
        bx(bm, (sx * 0.30 * breite, y_sitz + 0.10, boden + 0.26), (0.02, 0.78, 0.34),
           MI["cp_gruen"])


# --- Stile ------------------------------------------------------------------------------------
STILE = {
    "cockpit_bubble": dict(
        size=(1.3, 1.3, 2.4), exp=2.15, flach_unten=0.10, deck=0.085,
        oeff=(0.30, 0.72), x_off=0.34, sill=0.30, boden=-0.14,
        h_breite=0.40, h_hoehe=0.44, rundung=0.78,
        ws_ab=0.74, ws_rest=0.30, heck_ab=0.26, heck_rest=0.16,
        spanten=1, facetten=False, alle_ringe=False, tandem=False),
    "cockpit_jet": dict(
        size=(1.1, 1.1, 2.6), exp=2.7, flach_unten=0.06, deck=0.070,
        oeff=(0.34, 0.80), x_off=0.30, sill=0.28, boden=-0.12,
        h_breite=0.36, h_hoehe=0.34, rundung=1.15,
        ws_ab=0.62, ws_rest=0.22, heck_ab=0.30, heck_rest=0.10,
        spanten=1, facetten=False, alle_ringe=False, tandem=False),
    "cockpit_frame": dict(
        size=(1.35, 1.35, 2.25), exp=3.1, flach_unten=0.12, deck=0.075,
        oeff=(0.30, 0.70), x_off=0.35, sill=0.27, boden=-0.16,
        h_breite=0.42, h_hoehe=0.40, rundung=0.62,
        ws_ab=0.76, ws_rest=0.42, heck_ab=0.22, heck_rest=0.30,
        spanten=3, facetten=True, alle_ringe=True, tandem=False),
    "cockpit_spitfire": dict(
        # schmal und hoch (die Spitfire war eng und tief), starker Razorback
        size=(1.15, 1.28, 2.5), exp=2.05, flach_unten=0.08, deck=0.115,
        oeff=(0.26, 0.68), x_off=0.31, sill=0.28, boden=-0.15,
        h_breite=0.38, h_hoehe=0.42, rundung=0.80,
        ws_ab=0.74, ws_rest=0.34, heck_ab=0.30, heck_rest=0.18,
        spanten=1, facetten=False, alle_ringe=False, tandem=False,
        ws_getrennt=True, extras="spitfire"),
    "cockpit_tandem": dict(
        size=(1.225, 1.225, 3.1), exp=2.35, flach_unten=0.10, deck=0.080,
        oeff=(0.20, 0.84), x_off=0.32, sill=0.29, boden=-0.14,
        h_breite=0.38, h_hoehe=0.40, rundung=0.82,
        ws_ab=0.80, ws_rest=0.30, heck_ab=0.18, heck_rest=0.14,
        spanten=1, facetten=False, alle_ringe=False, tandem=True),
}


def neues_objekt(name, mats):
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for mn in mats:
        me.materials.append(get_mat(mn))
    return ob


def baue(pid, spec):
    sx, sz, sy = spec["size"]
    spec["laenge"] = sy
    breite, hoehe, laenge = sx, sz, sy
    profil = superellipse(PROFIL_PUNKTE, spec["exp"], spec["flach_unten"])
    ob = neues_objekt(pid, MATN)
    bm = bmesh.new()
    rumpf(bm, profil, breite, hoehe, laenge, spec, MI["cockpit_body"])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()

    y0 = -laenge * 0.5
    o0, o1 = spec["oeff"]
    sill_z = spec["sill"] * hoehe + deck_hub(0.5, hoehe, spec)
    boden_z = spec["boden"] * hoehe
    x_max = spec["x_off"] * breite

    if spec["tandem"]:
        m = (o0 + o1) * 0.5
        oeffnung(bm, y0 + laenge * o0, y0 + laenge * (m - 0.05), sill_z, x_max, boden_z,
                 MI["frame"], MI["dark"])
        oeffnung(bm, y0 + laenge * (m + 0.05), y0 + laenge * o1, sill_z, x_max, boden_z,
                 MI["frame"], MI["dark"])
        innenausbau(bm, y0 + laenge * (o1 - 0.10) - 0.30, sill_z, boden_z, breite)
        innenausbau(bm, y0 + laenge * (m - 0.09) - 0.30, sill_z, boden_z, breite)
    else:
        oeffnung(bm, y0 + laenge * o0, y0 + laenge * o1, sill_z, x_max, boden_z,
                 MI["frame"], MI["dark"])
        innenausbau(bm, y0 + laenge * (o0 * 0.30 + o1 * 0.70) - 0.16, sill_z, boden_z, breite)

    if spec.get("extras") == "spitfire":
        spitfire_extras(bm, spec, breite, hoehe, laenge, y0, sill_z, boden_z)
    for t in (0.14, 0.90):
        panelnaht(bm, profil, breite, hoehe, spec, t, MI["frame"])
    bx(bm, (breite * 0.40, y0 + laenge * (o0 + 0.03), sill_z - 0.22), (0.04, 0.16, 0.045),
       MI["metal"])                                              # Haltegriff
    bx(bm, (breite * 0.43, y0 + laenge * (o0 - 0.05), -hoehe * 0.12), (0.035, 0.15, 0.028),
       MI["dark"])                                               # Trittstufe
    zyl(bm, (0.0, y0 + laenge * 0.06, hoehe * 0.47), 0.016, 0.26, "z", MI["metal"], 6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    bm.to_mesh(ob.data)
    bm.free()

    gl = neues_objekt(pid + "_Glas", ["glass", "frame"])
    bg = bmesh.new()
    basis = sill_z + 0.050
    hb, hh = spec["h_breite"] * breite, spec["h_hoehe"] * hoehe
    if spec["tandem"]:
        m = (o0 + o1) * 0.5
        haube(bg, hp_von(spec), y0 + laenge * o0, y0 + laenge * (m - 0.02), basis, hb, hh, 0, 1)
        haube(bg, hp_von(spec), y0 + laenge * (m + 0.02), y0 + laenge * o1, basis, hb, hh, 0, 1)
    elif spec.get("ws_getrennt"):
        # SPITFIRE: gewoelbte Schiebehaube und davor ein EIGENER, facettierter Windschutz
        # mit flacher Panzerglas-Frontscheibe und abgewinkelten Seitenscheiben.
        u_ws = o0 + (o1 - o0) * 0.70
        haube(bg, hp_von(spec, ws_ab=0.90, ws_rest=0.86),
              y0 + laenge * o0, y0 + laenge * u_ws, basis, hb, hh, 0, 1)
        haube(bg, hp_von(spec, facetten=True, alle_ringe=True, heck_ab=0.02, heck_rest=0.98,
                         ws_ab=0.10, ws_rest=0.32, rundung=0.45, holme=False),
              y0 + laenge * u_ws, y0 + laenge * o1, basis, hb * 0.93, hh * 0.96, 0, 1)
    else:
        haube(bg, hp_von(spec), y0 + laenge * o0, y0 + laenge * o1, basis, hb, hh, 0, 1)
    bmesh.ops.recalc_face_normals(bg, faces=bg.faces[:])
    bg.normal_update()
    bg.to_mesh(gl.data)
    bg.free()
    gl.parent = ob
    return ob, gl, profil


def glatt(ob, winkel=38.0, flach=False):
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    if flach:
        bpy.ops.object.shade_flat()
    else:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(winkel))
    ob.select_set(False)


def blend_bibliothek(profile):
    ab = 0.0
    for pid, spec in STILE.items():
        sx, sz, sy = spec["size"]
        ob = bpy.data.objects[pid]
        ob.location.x = ab
        fu = neues_objekt(pid.replace("cockpit_", "fuselage_"), ["cockpit_body", "frame"])
        bmf = bmesh.new()
        prof = profile[pid]
        n = len(prof)
        yh = -sy * 0.5
        ringe = []
        for k in range(9):
            y = yh - 2.0 + 2.0 * k / 8
            ringe.append([bmf.verts.new((px * sx, y, pz * sz)) for px, pz in prof])
        for k in range(8):
            for i in range(n):
                j = (i + 1) % n
                bmf.faces.new([ringe[k][i], ringe[k][j],
                               ringe[k + 1][j], ringe[k + 1][i]]).material_index = 0
        bmf.faces.new(list(reversed(ringe[0]))).material_index = 0
        bmf.faces.new(list(ringe[-1])).material_index = 0
        bmesh.ops.recalc_face_normals(bmf, faces=bmf.faces[:])
        bmf.normal_update()
        bmf.to_mesh(fu.data)
        bmf.free()
        fu.location.x = ab
        glatt(fu)
        col = bpy.data.collections.new(pid.replace("cockpit_", ""))
        bpy.context.scene.collection.children.link(col)
        for o in (ob, bpy.data.objects[pid + "_Glas"], fu):
            for c in list(o.users_collection):
                c.objects.unlink(o)
            col.objects.link(o)
        txt = bpy.data.curves.new(pid + "_lbl", type='FONT')
        txt.body = pid.replace("cockpit_", "")
        txt.size = 0.42
        tob = bpy.data.objects.new(pid + "_lbl", txt)
        tob.location = (ab - 0.7, -sy * 0.5 - 2.8, 0.0)
        col.objects.link(tob)
        ab += 3.4
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
    print("SAVED", BLEND_OUT)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    profile_out = {}
    profile_roh = {}
    bericht = []
    for pid, spec in STILE.items():
        ob, gl, profil = baue(pid, spec)
        profile_roh[pid] = profil
        profile_out[pid] = [[round(x, 4), round(z, 4)] for x, z in profil]
        glatt(ob, 34.0)
        glatt(gl, 40.0, flach=spec["facetten"])   # Sprossenhaube: flache Scheiben
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        gl.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.export_scene.gltf(filepath=OUT_MODELS + pid + ".glb", export_format='GLB',
                                  use_selection=True, export_apply=True)
        bericht.append((pid, sum(len(p.vertices) - 2 for p in ob.data.polygons) +
                        sum(len(p.vertices) - 2 for p in gl.data.polygons)))
        bpy.ops.object.select_all(action='DESELECT')
    with open(PROFILE_JSON, "w") as f:
        json.dump(profile_out, f, indent=1)
    blend_bibliothek(profile_roh)
    for pid, t in bericht:
        print("  %-18s %5d Tris" % (pid, t))


main()
