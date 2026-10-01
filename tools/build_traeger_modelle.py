"""Baut die schlichten Flugzeugtraeger aus tools/traeger_modelle.json.

Jeder Traeger ist dort als ZAHLENSATZ beschrieben, nicht als Netz:
  stationen  [x, ...]                 Spanten vom Heck (-x) zum Bug (+x), 0 = Mitte der Laenge.
  ringe      je Station acht Punkte [steuerbord_y, backbord_y, z] von unten nach oben:
             Kiel-/Unterkante, Wasserpass, vier Stufen der Bordwand, Unterkante der
             Deckplatte, Deck. Wo der Rumpf nicht bis ins Wasser reicht (ueberhaengender Bug,
             Heckgalerie), liegen die unteren Ringe aufeinander.
  deck       je Station 1 = hier liegt das Flugdeck (Deckfarbe), 0 = Back/Schanz.
  aufbau     [{poly, z0, z1}]         Insel als Stapel von Prismen; poly = Grundriss [[x, y]].
  masten     [{x, y, z0, z1}]         duenne, verjuengte Masten.
  kisten     [[x0, x1, y0, y1, z0, z1]]  alles Kleinere auf und am Deck (Tuerme, Kraene).
  linien     [{von, bis, breite, mat, strich}]  Deckmarkierung, von Hand gesetzt.
  farben     {material: "#rrggbb"}    sRGB, von Hand gesetzt.
Einheiten sind Meter, z = 0 ist die Wasserlinie, +y ist Backbord. Gemessen wurden die Zahlen
mit tools/_traeger_vermessen.py an Vorlagen, die NICHT im Repo liegen.

Export: Blender +Y = Bug (wird Godot -Z), +Z = oben, Ursprung auf der Wasserlinie in der Mitte
der Laenge.
    blender --background --factory-startup --python tools/build_traeger_modelle.py
    ... -- forrestal            nur dieser
Kontrollbilder: Umgebungsvariable TRAEGER_PREVIEW=<ordner>.
Danach: Godot --headless --editor --import
"""
import bpy
import json
import math
import os
import sys
from mathutils import Vector

HIER = os.path.dirname(os.path.abspath(__file__))
SPEC = os.path.join(HIER, "traeger_modelle.json")
MASSE = os.path.join(HIER, "traeger_modelle_masse.json")
LINIE_UEBER_DECK = 0.07     # Markierung liegt so weit ueber dem Deck (kein Flimmern)
WASSERPASS_BIS = 0.9        # Bordwand bis zu dieser Hoehe traegt den dunklen Wasserpass

STANDARD = {
    "rumpf": "#8a9296",
    "wasserpass": "#23262a",
    "deck": "#3f4447",
    "aufbau": "#959da1",
    "dunkel": "#2b2e31",
    "weiss": "#e8e8e2",
    "gelb": "#e0b326",
}


def srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexfarbe(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


class Netz:
    """Sammelt Dreiecke. Entartete (Flaeche ~ 0) fallen weg: dort liegen Ringe aufeinander."""

    def __init__(self):
        self.verts = []
        self.faces = []      # (Indizes, Materialname, glatt)

    def punkt(self, p):
        self.verts.append(Vector(p))
        return len(self.verts) - 1

    def dreieck(self, a, b, c, mat, glatt=False):
        va, vb, vc = self.verts[a], self.verts[b], self.verts[c]
        if (vb - va).cross(vc - va).length < 1e-5:
            return
        self.faces.append(((a, b, c), mat, glatt))

    def viereck(self, a, b, c, d, mat, glatt=False):
        self.dreieck(a, b, c, mat, glatt)
        self.dreieck(a, c, d, mat, glatt)


def rumpf(netz, spec):
    """Lofting ueber die Spanten: zwei Bordwaende, Deck, Boden, Bug- und Heckabschluss.

    Die Wicklung steht fest (x nach vorn, y nach Backbord, Ringe von unten nach oben) und
    wird NICHT nachtraeglich aus einem Bezugspunkt geraten: die Unterseite eines
    ueberhaengenden Decks liegt hoeher und weiter aussen als die Schiffsmitte und zeigt
    trotzdem nach unten."""
    xs = spec["stationen"]
    ringe = spec["ringe"]
    deck = spec["deck"]
    stb, bb = [], []
    for x, ring in zip(xs, ringe):
        stb.append([netz.punkt((x, r[0], r[2])) for r in ring])
        bb.append([netz.punkt((x, r[1], r[2])) for r in ring])
    nk = len(ringe[0])
    for i in range(len(xs) - 1):
        for k in range(nk - 1):
            z_oben = max(ringe[i][k + 1][2], ringe[i + 1][k + 1][2])
            mat = "wasserpass" if z_oben <= WASSERPASS_BIS else "rumpf"
            netz.viereck(stb[i][k], stb[i + 1][k], stb[i + 1][k + 1], stb[i][k + 1], mat, True)
            netz.viereck(bb[i][k], bb[i][k + 1], bb[i + 1][k + 1], bb[i + 1][k], mat, True)
        oben = "deck" if deck[i] and deck[i + 1] else "rumpf"
        netz.viereck(stb[i][-1], stb[i + 1][-1], bb[i + 1][-1], bb[i][-1], oben)
        netz.viereck(stb[i][0], bb[i][0], bb[i + 1][0], stb[i + 1][0], "wasserpass")
    letzte = len(xs) - 1
    for k in range(nk - 1):
        mat = "wasserpass" if ringe[0][k + 1][2] <= WASSERPASS_BIS else "rumpf"
        netz.viereck(stb[0][k], stb[0][k + 1], bb[0][k + 1], bb[0][k], mat)
        mat = "wasserpass" if ringe[letzte][k + 1][2] <= WASSERPASS_BIS else "rumpf"
        netz.viereck(stb[letzte][k], bb[letzte][k], bb[letzte][k + 1], stb[letzte][k + 1], mat)


def _interp(xs, werte, x):
    if x <= xs[0]:
        return werte[0]
    for i in range(len(xs) - 1):
        if x <= xs[i + 1]:
            d = xs[i + 1] - xs[i]
            t = 0.0 if d < 1e-9 else (x - xs[i]) / d
            return werte[i] + (werte[i + 1] - werte[i]) * t
    return werte[-1]


def deck_z(spec, x):
    return _interp(spec["stationen"], [r[-1][2] for r in spec["ringe"]], x)


def _flaeche(poly):
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                     for i in range(len(poly)))


def prisma(netz, poly, z0, z1, mat, poly_oben=None):
    """Grundriss gegen den Uhrzeigersinn -> Seiten nach aussen, Deckel nach oben. Ohne Boden."""
    if _flaeche(poly) < 0.0:
        poly = list(reversed(poly))
        if poly_oben is not None:
            poly_oben = list(reversed(poly_oben))
    oben = poly_oben if poly_oben is not None else poly
    n = len(poly)
    u = [netz.punkt((p[0], p[1], z0)) for p in poly]
    o = [netz.punkt((p[0], p[1], z1)) for p in oben]
    for j in range(n):
        k = (j + 1) % n
        netz.viereck(u[j], u[k], o[k], o[j], mat)
    for j in range(1, n - 1):
        netz.dreieck(o[0], o[j], o[j + 1], mat)


def mast(netz, m):
    r0 = float(m.get("r0", 0.9))
    r1 = float(m.get("r1", 0.3))
    ecken = 6
    unten = [(m["x"] + r0 * math.cos(math.tau * i / ecken), m["y"] + r0 * math.sin(math.tau * i / ecken))
             for i in range(ecken)]
    oben = [(m["x"] + r1 * math.cos(math.tau * i / ecken), m["y"] + r1 * math.sin(math.tau * i / ecken))
            for i in range(ecken)]
    prisma(netz, unten, m["z0"], m["z1"], "dunkel", oben)
    # Rah: ein Querbalken auf drei Vierteln der Hoehe macht aus dem Stift einen Mast.
    zr = m["z0"] + (m["z1"] - m["z0"]) * 0.72
    b = float(m.get("rah", 5.0))
    if b > 0.5:
        prisma(netz, [(m["x"] - 0.25, m["y"] - b), (m["x"] + 0.25, m["y"] - b),
                      (m["x"] + 0.25, m["y"] + b), (m["x"] - 0.25, m["y"] + b)], zr, zr + 0.5, "dunkel")


def linie(netz, spec, ln):
    """Deckmarkierung als schmale Vierecke knapp ueber dem Deck, an jedem Spant geteilt
    (das Deck knickt dort — ein durchgehendes Viereck taucht sonst unter)."""
    ax, ay = ln["von"]
    bx, by = ln["bis"]
    laenge = math.hypot(bx - ax, by - ay)
    if laenge < 0.01:
        return
    tx, ty = (bx - ax) / laenge, (by - ay) / laenge
    nx, ny = -ty * ln["breite"] * 0.5, tx * ln["breite"] * 0.5
    schnitte = {0.0, laenge}
    if abs(bx - ax) > 1e-6:
        for x in spec["stationen"]:
            t = (x - ax) / (bx - ax) * laenge
            if 0.0 < t < laenge:
                schnitte.add(t)
    strich = ln.get("strich")
    if strich:
        t = 0.0
        while t < laenge:
            schnitte.add(t)
            schnitte.add(min(t + strich[0], laenge))
            t += strich[0] + strich[1]
    schnitte = sorted(schnitte)

    def an(tm):
        if not strich:
            return True
        return (tm % (strich[0] + strich[1])) < strich[0]

    for t0, t1 in zip(schnitte[:-1], schnitte[1:]):
        if t1 - t0 < 0.02 or not an(0.5 * (t0 + t1)):
            continue
        ecken = []
        for t, s in ((t0, -1.0), (t1, -1.0), (t1, 1.0), (t0, 1.0)):
            x = ax + tx * t + nx * s
            y = ay + ty * t + ny * s
            ecken.append(netz.punkt((x, y, deck_z(spec, x) + LINIE_UEBER_DECK)))
        a, b, c, d = ecken
        # Normale nach oben erzwingen
        va, vb, vc = netz.verts[a], netz.verts[b], netz.verts[c]
        if (vb - va).cross(vc - va).z < 0.0:
            b, d = d, b
        netz.viereck(a, b, c, d, ln.get("mat", "weiss"))


def baue_netz(spec):
    netz = Netz()
    rumpf(netz, spec)
    for a in spec.get("aufbau", []):
        prisma(netz, a["poly"], a["z0"], a["z1"], a.get("mat", "aufbau"))
    for k in spec.get("kisten", []):
        prisma(netz, [(k[0], k[2]), (k[1], k[2]), (k[1], k[3]), (k[0], k[3])], k[4], k[5],
               k[6] if len(k) > 6 else "aufbau")
    for m in spec.get("masten", []):
        mast(netz, m)
    for ln in spec.get("linien", []):
        linie(netz, spec, ln)
    return netz


def material(name, spec):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    farbe = spec.get("farben", {}).get(name, STANDARD.get(name, "#808080"))
    lin = tuple(srgb2lin(c) for c in hexfarbe(farbe))
    metall, rauh = (0.0, 0.9) if name in ("deck", "weiss", "gelb") else (0.25, 0.6)
    m.diffuse_color = (*lin, 1.0)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    if p is not None:
        p.inputs["Base Color"].default_value = (*lin, 1.0)
        p.inputs["Metallic"].default_value = metall
        p.inputs["Roughness"].default_value = rauh
    return m


def mesh_anlegen(name, punkte, netz, spec):
    me = bpy.data.meshes.new(name)
    me.from_pydata(punkte, [], [f[0] for f in netz.faces])
    namen = []
    for _, mat, _ in netz.faces:
        if mat not in namen:
            namen.append(mat)
    for n in namen:
        me.materials.append(material(n, spec))
    for poly, (_, mat, glatt) in zip(me.polygons, netz.faces):
        poly.material_index = namen.index(mat)
        poly.use_smooth = glatt
    me.validate()
    me.update()
    me.set_sharp_from_angle(angle=math.radians(32.0))
    return me


def export_punkte(netz):
    """Quelle (x Bug, y Backbord, z oben) -> Blender (X Steuerbord, Y Bug, Z oben)."""
    return [(-v.y, v.x, v.z) for v in netz.verts]


def baue_alle(nur):
    with open(SPEC, encoding="utf-8") as fh:
        specs = json.load(fh)
    ordner = os.environ.get("TRAEGER_PREVIEW", "")
    masse = {}
    if os.path.exists(MASSE):
        with open(MASSE, encoding="utf-8") as fh:
            masse = json.load(fh)
    for tid, spec in specs.items():
        if nur and tid not in nur:
            continue
        bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
        scene = bpy.context.scene
        scene.unit_settings.system = "METRIC"
        netz = baue_netz(spec)
        punkte = export_punkte(netz)
        name = "traeger_" + tid
        me = mesh_anlegen(name, punkte, netz, spec)
        obj = bpy.data.objects.new(name, me)
        scene.collection.objects.link(obj)
        bpy.context.view_layer.update()
        glb = os.path.join(os.path.dirname(HIER), "models", name + ".glb")
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_scene.gltf(
            filepath=glb, export_format="GLB", use_selection=True, export_apply=True,
            export_materials="EXPORT", export_texcoords=False, export_normals=True)
        xs = [p[0] for p in punkte]
        ys = [p[1] for p in punkte]
        zs = [p[2] for p in punkte]
        st = spec["stationen"]
        # Deckhoehe und -breite in Schiffsmitte, dazu die Landebahn in Godot-Koordinaten
        # (x Steuerbord, z = -Bug) — daraus setzt das Spiel Startplatz und Karteneintrag.
        mitte = min(range(len(st)), key=lambda i: abs(st[i]))
        eintrag = {
            "name": spec.get("name", tid),
            "laenge": round(max(ys) - min(ys), 2),
            "breite": round(max(xs) - min(xs), 2),
            "hoehe": round(max(zs), 2),
            "deck": round(spec["ringe"][mitte][-1][2], 2),
            "dreiecke": len(me.polygons),
            "materialien": [m.name for m in me.materials],
        }
        for schluessel in ("bahn", "start"):
            if schluessel in spec:
                eintrag[schluessel] = [[round(-p[1], 2), round(deck_z(spec, p[0]), 2), round(-p[0], 2)]
                                       for p in spec[schluessel]]
        masse[tid] = eintrag
        if ordner:
            vorschau(scene, os.path.abspath(ordner), name, max(ys) - min(ys))
        print("GEBAUT %s %s" % (tid, json.dumps(eintrag)))
    with open(MASSE, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(masse, fh, indent=1, sort_keys=True)
        fh.write("\n")


def vorschau(scene, ordner, name, laenge):
    os.makedirs(ordner, exist_ok=True)
    welt = bpy.data.worlds.new("Vorschau")
    welt.color = (0.10, 0.16, 0.22)
    scene.world = welt
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_cavity = True
    sh.show_shadows = True
    scene.display.render_aa = "16"
    scene.render.resolution_x = 1700
    scene.render.resolution_y = 800
    scene.render.image_settings.file_format = "PNG"
    kd = bpy.data.cameras.new("VorschauKamera")
    kd.type = "ORTHO"
    kd.clip_end = laenge * 20
    kam = bpy.data.objects.new("VorschauKamera", kd)
    scene.collection.objects.link(kam)
    scene.camera = kam
    mitte = Vector((0.0, 0.0, 12.0))
    for tag, richt, skala, oben in (("schraeg", Vector((0.62, 0.55, 0.50)), 1.02, "Y"),
                                    ("heck", Vector((0.50, -0.70, 0.36)), 0.95, "Y"),
                                    ("oben", Vector((0.0, 0.0, 1.0)), 1.05, "X"),
                                    ("seite", Vector((1.0, 0.0, 0.0)), 1.05, "Y")):
        kd.ortho_scale = laenge * skala
        kam.location = mitte + richt.normalized() * laenge * 4.0
        kam.rotation_euler = (mitte - kam.location).to_track_quat("-Z", oben).to_euler()
        if tag == "oben":
            kam.rotation_euler = (0.0, 0.0, -math.pi * 0.5)     # Bug im Bild nach rechts
        scene.render.filepath = os.path.join(ordner, "%s_%s.png" % (name, tag))
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    if not bpy.app.background:
        raise RuntimeError("Nur mit --background starten (das Skript leert die Szene).")
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    baue_alle(set(args))
