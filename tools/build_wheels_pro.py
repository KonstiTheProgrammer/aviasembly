# Alle acht Fahrwerksraeder neu und hochwertig modellieren.
#
# WARUM NEU: die alten Raeder waren im Kern einteilige Rotationskoerper — Reifen ohne Profil,
# Felge ohne Struktur, Bein ohne erkennbaren Federweg. Jetzt hat jedes Rad einen echten Aufbau:
#   * REIFEN als revolviertes Profil: Wulst, Flanke, Schulter und drei UMLAUFENDE RILLEN
#     (Laufflaechenprofil). Nur der Gummi ist smooth shaded, alles Metall bleibt flat.
#   * FELGE in fuenf Stilen — Nabe mit Radmuttern, Speichenrad, Scheibenrad, Loch-, Schlitzfelge.
#     Dadurch unterscheiden sich die acht Raeder sichtbar, nicht nur in der Groesse.
#   * BREMSE (Scheibe + Sattel) bei allen Raedern mit genug Traglast.
#   * BEIN in vier Stilen: einfaches Oleo, Gabel, Oleo mit Drehmomentschere, Achsstummel mit
#     V-Verspannung (Doppeldecker).
#
# KNOTENNAMEN sind Vertrag mit dem Spiel:
#   "Wheel" = der drehende Teil (wird beim Rollen gedreht)
#   "Leg"   = das Bein; AircraftBody.gd sucht find_child("Leg") und klappt es beim Einfahren.
#             Das Rad haengt UNTER dem Bein und klappt deshalb mit. Eine gebackene
#             Animation braucht es dadurch nicht — das Verschwinden macht die Blob-Animation.
#
# EINPASSUNG: vor dem Ueberschreiben wird das ALTE glb importiert und seine Bounding-Box
# vermessen. Das neue Rad wird uniform skaliert und zentriert, sodass es genau dasselbe
# Volumen einnimmt. Sonst schwebt oder versinkt das Fahrwerk in allen bestehenden Presets.
#
# Achsen (Projektkonvention): Blender +Y = Godot -Z (vorne), Blender Z = Godot Y (oben).
# Die Raddrehachse ist X (links-rechts).
#
# Usage: blender --background --python tools/build_wheels_pro.py
import bpy
import bmesh
import math
import mathutils

OUT = "C:/Users/Konst/Projects/aviasembly/models/"


def srgb2lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


MATS = {
    "rubber": ((0.082, 0.085, 0.092), 0.04, 0.86),
    "rim":    ((0.66, 0.675, 0.70), 0.55, 0.42),
    "hub":    ((0.36, 0.38, 0.41), 0.55, 0.45),
    "strut":  ((0.60, 0.62, 0.65), 0.60, 0.36),
    "dark":   ((0.12, 0.13, 0.15), 0.40, 0.58),
    "brake":  ((0.34, 0.32, 0.30), 0.62, 0.47),
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


def neu(name):
    me = bpy.data.meshes.new(name)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for n in MATN:
        me.materials.append(mat(n))
    return ob


# --- Grundformen (Drehachse durchweg X) ------------------------------------------------
def revolve_x(bm, profil, segs, mi):
    """profil = [(x, r)] wird um die X-Achse revolviert; r = Abstand von der Achse."""
    n = len(profil)
    ringe = []
    for i in range(segs):
        a = 2.0 * math.pi * i / segs
        ca, sa = math.cos(a), math.sin(a)
        ringe.append([bm.verts.new((px, r * ca, r * sa)) for px, r in profil])
    for i in range(segs):
        j = (i + 1) % segs
        for k in range(n - 1):
            try:
                bm.faces.new([ringe[i][k], ringe[j][k],
                              ringe[j][k + 1], ringe[i][k + 1]]).material_index = mi
            except ValueError:
                pass


def zyl_x(bm, x0, x1, r0, r1, segs, mi, deckel=True, off=(0.0, 0.0)):
    oy, oz = off
    ringe = []
    for x, r in ((x0, r0), (x1, r1)):
        ring = []
        for i in range(segs):
            a = 2.0 * math.pi * i / segs
            ring.append(bm.verts.new((x, oy + math.cos(a) * r, oz + math.sin(a) * r)))
        ringe.append(ring)
    for i in range(segs):
        j = (i + 1) % segs
        try:
            bm.faces.new([ringe[0][i], ringe[0][j], ringe[1][j], ringe[1][i]]).material_index = mi
        except ValueError:
            pass
    if deckel:
        try:
            bm.faces.new(list(reversed(ringe[0]))).material_index = mi
        except ValueError:
            pass
        try:
            bm.faces.new(list(ringe[1])).material_index = mi
        except ValueError:
            pass


def strebe(bm, p0, p1, dicke, mi, breite=None):
    """Kantiger Balken zwischen zwei Punkten — fuer Speichen, Streben, Gabelbeine."""
    a = mathutils.Vector(p0)
    b = mathutils.Vector(p1)
    d = b - a
    L = d.length
    if L < 1e-6:
        return
    ez = d / L
    hilf = mathutils.Vector((1, 0, 0)) if abs(ez.x) < 0.9 else mathutils.Vector((0, 0, 1))
    ex = ez.cross(hilf).normalized()
    ey = ez.cross(ex).normalized()
    hd = dicke * 0.5
    hb = (breite if breite is not None else dicke) * 0.5
    v = []
    for tz in (0.0, L):
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            v.append(bm.verts.new(a + ex * (sx * hb) + ey * (sy * hd) + ez * tz))
    for f in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2),
              (2, 6, 7, 3), (3, 7, 4, 0)):
        try:
            bm.faces.new([v[i] for i in f]).material_index = mi
        except ValueError:
            pass


def box(bm, ctr, size, mi):
    cx, cy, cz = ctr
    sx, sy, sz = size
    v = []
    for dx in (-0.5, 0.5):
        for dy in (-0.5, 0.5):
            for dz in (-0.5, 0.5):
                v.append(bm.verts.new((cx + dx * sx, cy + dy * sy, cz + dz * sz)))
    for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6),
              (0, 2, 6, 4), (1, 5, 7, 3)):
        try:
            bm.faces.new([v[i] for i in f]).material_index = mi
        except ValueError:
            pass


# --- Reifen ----------------------------------------------------------------------------
def reifen_profil(R, W, rillen=3):
    """Querschnitt: Wulst -> Flanke -> Schulter -> Lauffläche mit umlaufenden RILLEN."""
    hw = W * 0.5
    # Die Lauffläche muss als eigenes BAND lesbar sein: Flanke steil hoch, dann eine
    # kantige Schulter, dann erst das Profil. Rillen mit 8 % Tiefe (vorher 4.8 % =
    # unsichtbar) und senkrechten Wänden, damit sie Schatten werfen.
    p = [(-hw * 0.58, R * 0.55), (-hw * 0.96, R * 0.63), (-hw, R * 0.78),
         (-hw, R * 0.92), (-hw * 0.96, R * 0.975), (-hw * 0.90, R * 0.998)]
    n = rillen * 2 + 1
    for k in range(n + 1):
        t = float(k) / n
        x = -hw * 0.87 + t * hw * 1.74
        r = R if k % 2 == 0 else R * 0.920
        if k % 2 == 1:                     # Rille: senkrecht rein und raus
            p.append((x - hw * 0.055, R))
        p.append((x, r))
        if k % 2 == 1:
            p.append((x + hw * 0.055, R))
    p += [(hw * 0.90, R * 0.998), (hw * 0.96, R * 0.975), (hw, R * 0.92),
          (hw, R * 0.78), (hw * 0.96, R * 0.63), (hw * 0.58, R * 0.55)]
    return p


def kappe_x(r, R, W):
    """x der gewoelbten Radkappe beim Radius r — Aufsaetze muessen der Woelbung folgen."""
    stuetz = [(0.001, W * 0.44), (0.20, W * 0.40), (0.26, W * 0.21),
              (0.44, W * 0.32), (0.575, W * 0.42)]
    t = r / max(R, 1e-6)
    for i in range(len(stuetz) - 1):
        r0, x0 = stuetz[i]
        r1, x1 = stuetz[i + 1]
        if r0 <= t <= r1:
            f = (t - r0) / max(r1 - r0, 1e-6)
            return x0 + (x1 - x0) * f
    return W * 0.42


def baue_rad(s):
    R, W = s["R"], s["W"]
    segs = 40
    rad = neu("Wheel")
    bm = bmesh.new()
    revolve_x(bm, reifen_profil(R, W, 3), segs, MI["rubber"])
    zyl_x(bm, -W * 0.44, W * 0.44, R * 0.575, R * 0.575, segs, MI["rim"], False)  # Felgenkranz
    stil = s["felge"]
    if stil == "speichen":
        zyl_x(bm, -W * 0.62, W * 0.62, R * 0.155, R * 0.155, 12, MI["hub"])
        for k in range(16):
            a = 2.0 * math.pi * k / 16
            for sx in (-1, 1):
                strebe(bm, (sx * W * 0.44, math.cos(a) * R * 0.16, math.sin(a) * R * 0.16),
                       (0.0, math.cos(a) * R * 0.565, math.sin(a) * R * 0.565),
                       0.016, MI["hub"])
    elif stil in ("scheibe", "schlitze", "loecher"):
        for sx in (-1, 1):                 # gewoelbte Radkappe beidseitig
            revolve_x(bm, [(sx * W * 0.42, R * 0.575), (sx * W * 0.32, R * 0.44),
                           (sx * W * 0.21, R * 0.19), (sx * W * 0.26, R * 0.001)],
                      segs, MI["rim"])
        zyl_x(bm, -W * 0.34, W * 0.34, R * 0.145, R * 0.145, 12, MI["hub"])
        if stil == "schlitze":             # Spitfire: erhabene Rippen auf der Radkappe
            for k in range(6):
                a = 2.0 * math.pi * k / 6
                ca, sa = math.cos(a), math.sin(a)
                r0, r1 = R * 0.24, R * 0.52
                strebe(bm, (kappe_x(r0, R, W) + 0.006, ca * r0, sa * r0),
                       (kappe_x(r1, R, W) + 0.006, ca * r1, sa * r1),
                       0.012, MI["hub"], breite=R * 0.10)
        elif stil == "loecher":            # Jet: Kuehlloecher, mittig in der Kappe
            for k in range(8):
                a = 2.0 * math.pi * k / 8
                rr = R * 0.37
                xm = kappe_x(rr, R, W)
                zyl_x(bm, xm - 0.03, xm + 0.03, R * 0.080, R * 0.080, 10, MI["dark"],
                      True, (math.cos(a) * rr, math.sin(a) * rr))
    else:                                  # "nabe": geschlossene Felge mit Radmuttern
        # Innenseite dicht (sonst schaut man quer durch das Rad auf die Bremse),
        # Aussenseite als flache Schuessel mit Radmuttern auf dem Bolzenkranz.
        revolve_x(bm, [(-W * 0.44, R * 0.575), (-W * 0.40, R * 0.30),
                       (-W * 0.36, R * 0.001)], segs, MI["rim"])
        revolve_x(bm, [(W * 0.44, R * 0.575), (W * 0.34, R * 0.42),
                       (W * 0.30, R * 0.26), (W * 0.40, R * 0.20),
                       (W * 0.44, R * 0.001)], segs, MI["rim"])
        lug = s.get("lug", 5)
        for k in range(lug):
            a = 2.0 * math.pi * k / lug
            rr = R * 0.325
            zyl_x(bm, W * 0.30, W * 0.40, R * 0.052, R * 0.052, 6, MI["hub"],
                  True, (math.cos(a) * rr, math.sin(a) * rr))
    if s["bremse"]:                        # Bremsscheibe innen + Sattel am Traeger
        revolve_x(bm, [(-W * 0.56, R * 0.19), (-W * 0.56, R * 0.48),
                       (-W * 0.49, R * 0.48), (-W * 0.49, R * 0.19)], 24, MI["brake"])
        # Der Sattel muss den Scheibenrand UMGREIFEN und an einem Traeger zur Achse
        # sitzen — frei in der Luft schwebend wirkte er wie ein verlorener Klotz.
        box(bm, (-W * 0.58, 0.0, R * 0.42), (W * 0.30, R * 0.19, R * 0.15), MI["dark"])
        strebe(bm, (-W * 0.60, 0.0, R * 0.36), (-W * 0.60, 0.0, R * 0.11),
               0.020, MI["dark"], breite=R * 0.13)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    bm.to_mesh(rad.data)
    bm.free()

    bein = neu("Leg")
    bl = bmesh.new()
    st = s["strebe"]
    if st == "gabel":                      # Gabel beidseitig + Oleo darueber
        for sx in (-1, 1):
            # x bleibt AUSSERHALB der halben Reifenbreite (W*0.5), sonst steckt das
            # Gabelblech im Gummi — beim ersten Render genau so passiert.
            strebe(bl, (sx * (W * 0.5 + 0.022), 0.0, 0.0),
                   (sx * (W * 0.5 + 0.022), 0.0, R * 1.06),
                   0.032, MI["strut"], breite=R * 0.52)
        box(bl, (0.0, 0.0, R * 1.12), (W + 0.09, R * 0.46, R * 0.16), MI["strut"])
        zyl_x(bl, -(W * 0.5 + 0.05), W * 0.5 + 0.05, R * 0.075, R * 0.075, 10, MI["strut"])
        strebe(bl, (0.0, 0.0, R * 1.10), (0.0, 0.0, R * 2.05), R * 0.30, MI["strut"])
        strebe(bl, (0.0, 0.0, R * 1.98), (0.0, 0.0, R * 2.60), R * 0.40, MI["strut"])
    elif st == "achse":                    # Doppeldecker: Achsstummel + V-Verspannung
        # Die V spannt LAENGS auf (vor und hinter dem Rad), nicht quer: quer laufen die
        # Streben ueber die Reifenflanke und treffen in der Nabenmitte zusammen — genau
        # das sah im ersten Render falsch aus. So bleibt alles seitlich frei vom Gummi.
        xa = W * 0.5 + 0.055
        zyl_x(bl, -xa, xa, R * 0.062, R * 0.062, 10, MI["strut"])
        for sy in (-1, 1):
            strebe(bl, (xa * 0.55, 0.0, 0.0), (xa * 0.30, sy * R * 0.62, R * 1.72),
                   0.028, MI["strut"])
        strebe(bl, (xa * 0.30, -R * 0.62, R * 1.72), (xa * 0.30, R * 0.62, R * 1.72),
               0.030, MI["strut"])          # Querholm oben
        strebe(bl, (xa * 0.42, 0.0, R * 0.86), (xa * 0.30, R * 0.30, R * 1.72),
               0.020, MI["dark"])           # Spanndraht
    else:                                  # "einfach" / "oleo": Teleskopbein auf Gabel
        # Ein Rohr auf der Radmitte laeuft optisch DURCH die Felge — es sah aus, als
        # waere das Rad aufgespiesst. Darum unten eine kurze Gabel neben dem Gummi und
        # erst darueber das Teleskoprohr; der Aufhaengepunkt bleibt dadurch zentriert.
        xg = W * 0.5 + 0.022
        for sx in (-1, 1):
            strebe(bl, (sx * xg, 0.0, 0.0), (sx * xg, 0.0, R * 1.02),
                   0.030, MI["strut"], breite=R * 0.40)
        box(bl, (0.0, 0.0, R * 1.10), (W + 0.08, R * 0.40, R * 0.16), MI["strut"])
        zyl_x(bl, -(xg + 0.03), xg + 0.03, R * 0.075, R * 0.075, 10, MI["strut"])
        # Kolbenrohr duenn, Zylinder darueber dick: so liest man den Federweg ab.
        strebe(bl, (0.0, 0.0, R * 1.06), (0.0, 0.0, R * 1.72), R * 0.26, MI["strut"])
        strebe(bl, (0.0, 0.0, R * 1.64), (0.0, 0.0, R * 2.34), R * 0.38, MI["strut"])
        strebe(bl, (0.0, 0.0, R * 2.26), (0.0, 0.0, R * 2.60), R * 0.48, MI["strut"])
        if st == "oleo":                   # Drehmomentschere VORNE am Federbein
            y0 = R * 0.15
            strebe(bl, (0.0, y0, R * 1.14), (0.0, y0 + R * 0.24, R * 1.62),
                   0.030, MI["dark"], breite=R * 0.13)
            strebe(bl, (0.0, y0 + R * 0.24, R * 1.62), (0.0, y0 + R * 0.02, R * 2.14),
                   0.030, MI["dark"], breite=R * 0.13)
    bmesh.ops.recalc_face_normals(bl, faces=bl.faces[:])
    bl.normal_update()
    bl.to_mesh(bein.data)
    bl.free()

    rad.parent = bein                      # Rad haengt unter dem Bein -> klappt mit
    return bein, rad


SPEC = {
    "wheel_light":         dict(R=0.26, W=0.10, felge="scheibe", strebe="einfach", bremse=False),
    "wheel":               dict(R=0.36, W=0.17, felge="nabe", strebe="gabel", bremse=True, lug=5),
    "wheel_heavy":         dict(R=0.50, W=0.26, felge="nabe", strebe="gabel", bremse=True, lug=8),
    "wheel_retract":       dict(R=0.38, W=0.18, felge="nabe", strebe="oleo", bremse=True, lug=6),
    "wheel_jet":           dict(R=0.34, W=0.16, felge="loecher", strebe="oleo", bremse=True),
    "wheel_biplane_spoke": dict(R=0.40, W=0.09, felge="speichen", strebe="achse", bremse=False),
    "wheel_biplane_disc":  dict(R=0.40, W=0.10, felge="scheibe", strebe="achse", bremse=False),
    "wheel_spitfire":      dict(R=0.38, W=0.14, felge="schlitze", strebe="oleo", bremse=True),
}


def leeren():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def bbox_welt(objekte):
    lo = mathutils.Vector((1e9, 1e9, 1e9))
    hi = mathutils.Vector((-1e9, -1e9, -1e9))
    for ob in objekte:
        if ob.type != 'MESH':
            continue
        for c in ob.bound_box:
            p = ob.matrix_world @ mathutils.Vector(c)
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    return lo, hi


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bericht = []
    for name, s in SPEC.items():
        # 1) altes glb vermessen, damit das neue Rad genau dasselbe Volumen einnimmt
        leeren()
        alt_lo = alt_hi = None
        try:
            bpy.ops.import_scene.gltf(filepath=OUT + name + ".glb")
            alt_lo, alt_hi = bbox_welt(list(bpy.data.objects))
        except Exception as e:
            print("  (kein Altmodell fuer %s: %s)" % (name, e))
        leeren()

        # 2) neues Rad bauen
        bein, rad = baue_rad(s)
        for ob, glatt in ((rad, True), (bein, False)):
            bpy.ops.object.select_all(action='DESELECT')
            ob.select_set(True)
            bpy.context.view_layer.objects.active = ob
            if glatt:
                bpy.ops.object.shade_auto_smooth(angle=math.radians(44))
            else:
                bpy.ops.object.shade_flat()

        # 3) in die alte Bounding-Box einpassen: uniform skalieren + Mittelpunkt treffen
        wurzel = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(wurzel)
        bein.parent = wurzel
        bpy.context.view_layer.update()
        if alt_lo is not None:
            neu_lo, neu_hi = bbox_welt([rad, bein])
            alt_gr = alt_hi - alt_lo
            neu_gr = neu_hi - neu_lo
            f = min(alt_gr[i] / max(neu_gr[i], 1e-6) for i in range(3))
            wurzel.scale = (f, f, f)
            bpy.context.view_layer.update()
            neu_lo, neu_hi = bbox_welt([rad, bein])
            wurzel.location = (alt_lo + alt_hi) * 0.5 - (neu_lo + neu_hi) * 0.5
            bpy.context.view_layer.update()
            print("  %s: Box alt %.3f x %.3f x %.3f -> Faktor %.3f"
                  % (name, alt_gr.x, alt_gr.y, alt_gr.z, f))

        bpy.ops.object.select_all(action='DESELECT')
        for ob in (wurzel, bein, rad):
            ob.select_set(True)
        bpy.context.view_layer.objects.active = wurzel
        bpy.ops.export_scene.gltf(filepath=OUT + name + ".glb", export_format='GLB',
                                  use_selection=True, export_apply=True)
        tris = sum(len(p.vertices) - 2 for p in rad.data.polygons) \
            + sum(len(p.vertices) - 2 for p in bein.data.polygons)
        bericht.append((name, tris))
    print("=== FERTIG ===")
    for n, t in bericht:
        print("  %-22s %5d Tris" % (n, t))


main()
