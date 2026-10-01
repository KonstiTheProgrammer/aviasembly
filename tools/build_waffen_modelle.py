"""Baut die schlichten Waffenmodelle (Lenkwaffen, Raketen, Bomben) aus tools/waffen_modelle.json.

Jede Waffe ist dort als ZAHLENSATZ beschrieben, nicht als Netz:
  profil   [[x, r, material], ...]   Rumpf als Rotationskoerper, vom Heck zur Nase. Das
                                     Material gilt fuer das Band bis zum naechsten Punkt.
  teile    [{winkel, umriss, dicke, mat}]  Platten in Ebenen durch die Laengsachse: Fluegel,
                                     Ruder, Aufhaengungen. umriss = [[x, hoehe, wurzel]];
                                     wurzel = 1 heisst "sitzt auf dem Rumpf" — die Hoehe
                                     rechnet der Bauer dann selbst knapp UNTER die Haut.
  mantel   [{x0, x1, radien, dicke, mat}] hohles Rohr ums Leitwerk; radien = Abstand der
                                     Wand in 24 Richtungen, also Ring ODER Kasten.
  farben   {material: "#rrggbb"}     sRGB. `body` ist die Hauptfarbe (im Spiel lackierbar),
                                     `glass` der Suchkopf, alles andere bleibt wie gebaut.
  duese    true = dunkle Duesenmulde im Heck (Flugkoerper), false = glatter Abschluss.
Einheiten sind Zoll mit der Nase bei +x; so wurden die Vorlagen vermessen
(tools/_waffen_vermessen.py). Die Vorlagen selbst liegen NICHT im Repo.

Export: Meter, Blender +Y = Nase (wird Godot -Z), +Z = oben, Ursprung auf der Laengsachse
in der Mitte der Laenge.
    blender --background --factory-startup --python tools/build_waffen_modelle.py
    ... -- r73 mk82          nur diese
Kontrollbilder: Umgebungsvariable WAFFEN_PREVIEW=<ordner>.
Danach: Godot --headless --editor --import
"""
import bpy
import json
import math
import os
import sys
from mathutils import Vector

HIER = os.path.dirname(os.path.abspath(__file__))
SPEC = os.path.join(HIER, "waffen_modelle.json")
MASSE = os.path.join(HIER, "waffen_modelle_masse.json")
ZOLL = 0.0254
MIN_DICKE = 0.55        # duennere Platten flimmern im Spiel — echte Flossen haben 0,2


def srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexfarbe(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def _volumen(verts, faces):
    """Vorzeichenbehaftetes Volumen: > 0 heisst, die Flaechen zeigen nach aussen."""
    vol = 0.0
    for f in faces:
        a = verts[f[0]]
        for i in range(1, len(f) - 1):
            vol += a.dot(verts[f[i]].cross(verts[f[i + 1]]))
    return vol / 6.0


class Netz:
    """Sammelt geschlossene Teile; jedes Teil richtet seine Wicklung selbst nach aussen."""

    def __init__(self):
        self.verts = []
        self.faces = []      # (Indizes, Materialname, glatt)

    def teil(self, verts, faces, mats, glatt):
        if isinstance(mats, str):
            mats = [mats] * len(faces)
        if _volumen(verts, faces) < 0.0:
            faces = [tuple(reversed(f)) for f in faces]
        basis = len(self.verts)
        self.verts.extend(verts)
        for f, m in zip(faces, mats):
            self.faces.append((tuple(basis + i for i in f), m, glatt))


def rotationskoerper(profil, seg):
    """profil: [(x, r, Material des Bandes bis zum naechsten Punkt)], von Achse zu Achse."""
    verts, start = [], []
    for x, r, _ in profil:
        start.append(len(verts))
        if r <= 1e-9:
            verts.append(Vector((x, 0.0, 0.0)))
        else:
            for i in range(seg):
                a = math.tau * i / seg
                verts.append(Vector((x, r * math.cos(a), r * math.sin(a))))
    faces, mats = [], []
    for p in range(len(profil) - 1):
        r0, r1, mat = profil[p][1], profil[p + 1][1], profil[p][2]
        for i in range(seg):
            j = (i + 1) % seg
            if r0 <= 1e-9 and r1 <= 1e-9:
                continue
            if r0 <= 1e-9:
                faces.append((start[p], start[p + 1] + i, start[p + 1] + j))
            elif r1 <= 1e-9:
                faces.append((start[p] + i, start[p + 1], start[p] + j))
            else:
                faces.append((start[p] + i, start[p + 1] + i, start[p + 1] + j, start[p] + j))
            mats.append(mat)
    return verts, faces, mats


def rumpfradius(profil, x):
    """Radius des Rumpfs an der Station x (linear zwischen den Profilpunkten)."""
    if x <= profil[0][0]:
        return profil[0][1]
    for a, b in zip(profil, profil[1:]):
        if x <= b[0]:
            if b[0] - a[0] < 1e-9:
                return max(a[1], b[1])
            t = (x - a[0]) / (b[0] - a[0])
            return a[1] + (b[1] - a[1]) * t
    return profil[-1][1]


def platte(umriss, winkel_grad, dicke, profil):
    """Platte mit dem Umriss [(x, hoehe, wurzel)] in der Ebene durch die Laengsachse."""
    a = math.radians(winkel_grad)
    richt = Vector((0.0, math.cos(a), math.sin(a)))
    quer = Vector((0.0, -math.sin(a), math.cos(a)))
    halb = 0.5 * dicke
    oben, unten = [], []
    for p in umriss:
        x, u = p[0], p[1]
        if len(p) > 2 and p[2]:
            # Wurzelpunkt: so tief, dass auch die KANTEN der Platte (halbe Dicke seitlich)
            # noch unter der runden Haut liegen — sonst klafft bei breiten Aufhaengungen
            # ein Spalt.
            rr = rumpfradius(profil, x)
            u = math.sqrt(max(rr * rr - halb * halb, 0.0)) - (0.05 * rr + 0.08)
            u = max(u, 0.0)
        mitte = Vector((x, 0.0, 0.0)) + richt * u
        oben.append(mitte + quer * halb)
        unten.append(mitte - quer * halb)
    n = len(umriss)
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((j, i, n + i, n + j))
    return oben + unten, faces


def mantelrohr(x0, x1, radien, dicke, mat):
    """Hohles Rohr mit dem Querschnitt radien[j] in Richtung j*360/n Grad (Ring ODER Kasten)."""
    n = len(radien)
    schleife = [(x0, -dicke, mat), (x0, 0.0, mat), (x1, 0.0, mat), (x1, -dicke, "dark"), (x0, -dicke, mat)]
    verts = []
    for x, versatz, _ in schleife:
        for j in range(n):
            a = math.tau * j / n
            rad = radien[j] + versatz
            verts.append(Vector((x, rad * math.cos(a), rad * math.sin(a))))
    faces, mats = [], []
    for p in range(len(schleife) - 1):
        for j in range(n):
            k = (j + 1) % n
            faces.append((p * n + j, (p + 1) * n + j, (p + 1) * n + k, p * n + k))
            mats.append(schleife[p][2])
    return verts, faces, mats


def baue_netz(spec):
    netz = Netz()
    seg = int(spec.get("segmente", 16))
    prof = [(float(p[0]), float(p[1]), p[2]) for p in spec["profil"]]

    pts = []
    x0, r0, m0 = prof[0]
    if r0 > 1e-6:
        if spec.get("duese"):
            tief = 0.9 * r0
            pts += [(x0 + tief, 0.0, "dark"), (x0 + tief, 0.50 * r0, "dark"), (x0, 0.80 * r0, m0)]
        else:
            pts.append((x0, 0.0, m0))
    pts += prof
    xn, rn, mn = prof[-1]
    if rn > 1e-6:
        pts.append((xn, 0.0, mn))
    v, f, m = rotationskoerper(pts, seg)
    netz.teil(v, f, m, True)

    for t in spec.get("teile", []):
        dicke = max(float(t["dicke"]), MIN_DICKE)
        for w in t["winkel"]:
            v, f = platte(t["umriss"], w, dicke, prof)
            netz.teil(v, f, t.get("mat", "body"), False)

    # HECKMANTEL: hohles Rohr um das Leitwerk, rund (Ring) oder eckig (Kasten). Die
    # Innenwand ist dunkel — so liest man die Oeffnung auch ohne Licht darin.
    for mt in spec.get("mantel", []):
        v, f, mm = mantelrohr(float(mt["x0"]), float(mt["x1"]), [float(q) for q in mt["radien"]],
                              float(mt["dicke"]), mt.get("mat", "body"))
        netz.teil(v, f, mm, True)
    return netz


STANDARD = {
    "glass": ((0.10, 0.13, 0.20), 0.30, 0.10, True),      # linear, wie missile.glb
    "dark": ((0.10, 0.10, 0.12), 0.55, 0.55, True),
}


def material(name, spec):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    farben = spec.get("farben", {})
    if name in farben:
        lin = tuple(srgb2lin(c) for c in hexfarbe(farben[name]))
        metall, rauh = (0.35, 0.50) if name == "body" else (0.25, 0.55)
    elif name in STANDARD:
        lin, metall, rauh, _ = STANDARD[name]
    else:
        lin, metall, rauh = (0.5, 0.5, 0.5), 0.3, 0.5
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
    if "body" in namen:                      # body zuerst, wie bei den anderen Modellen
        namen.remove("body")
        namen.insert(0, "body")
    for n in namen:
        me.materials.append(material(n, spec))
    for poly, (_, mat, glatt) in zip(me.polygons, netz.faces):
        poly.material_index = namen.index(mat)
        poly.use_smooth = glatt
    me.validate()
    me.update()
    me.set_sharp_from_angle(angle=math.radians(40.0))
    return me


def export_punkte(netz):
    """Vorlagen-Koordinaten (Nase +x, Zoll) -> Bauteil-Koordinaten (Nase +Y, Meter)."""
    xs = [v.x for v in netz.verts]
    mitte = 0.5 * (max(xs) + min(xs))
    return [(-v.y * ZOLL, (v.x - mitte) * ZOLL, v.z * ZOLL) for v in netz.verts]


def baue_alle(nur):
    with open(SPEC, encoding="utf-8") as fh:
        specs = json.load(fh)
    ordner = os.environ.get("WAFFEN_PREVIEW", "")
    masse = {}
    if os.path.exists(MASSE):
        with open(MASSE, encoding="utf-8") as fh:
            masse = json.load(fh)
    for wid, spec in specs.items():
        if nur and wid not in nur:
            continue
        bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
        scene = bpy.context.scene
        scene.unit_settings.system = "METRIC"
        netz = baue_netz(spec)
        punkte = export_punkte(netz)
        me = mesh_anlegen(wid, punkte, netz, spec)
        obj = bpy.data.objects.new(wid, me)
        scene.collection.objects.link(obj)
        bpy.context.view_layer.update()
        glb = os.path.join(os.path.dirname(HIER), "models", wid + ".glb")
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_scene.gltf(
            filepath=glb, export_format="GLB", use_selection=True, export_apply=True,
            export_materials="EXPORT", export_texcoords=False, export_normals=True)
        xs = [abs(p[0]) for p in punkte]
        ys = [p[1] for p in punkte]
        zs = [abs(p[2]) for p in punkte]
        # Katalogbox (Godot x, y, z): symmetrisch um die Laengsachse, damit der Ursprung
        # auf der Achse bleiben kann — der Bau-Snap rechnet ohne col_offset.
        masse[wid] = {
            "size": [round(2.0 * max(xs), 3), round(2.0 * max(zs), 3), round(max(ys) - min(ys), 3)],
            "dreiecke": sum(len(p.vertices) - 2 for p in me.polygons),
            "farbe": spec.get("farben", {}).get("body", "#808080"),
            "materialien": [m.name for m in me.materials],
        }
        if ordner:
            vorschau(scene, os.path.abspath(ordner), wid, max(ys) - min(ys))
        print("GEBAUT %s %s" % (wid, json.dumps(masse[wid])))
    with open(MASSE, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(masse, fh, indent=1, sort_keys=True)
        fh.write("\n")


def vorschau(scene, ordner, wid, laenge):
    os.makedirs(ordner, exist_ok=True)
    welt = bpy.data.worlds.new("Vorschau")
    welt.color = (0.045, 0.060, 0.085)
    scene.world = welt
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_cavity = True
    scene.display.render_aa = "16"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 520
    scene.render.image_settings.file_format = "PNG"
    kd = bpy.data.cameras.new("VorschauKamera")
    kd.type = "ORTHO"
    kd.ortho_scale = laenge * 1.12
    kam = bpy.data.objects.new("VorschauKamera", kd)
    scene.collection.objects.link(kam)
    scene.camera = kam
    kam.location = Vector((0.75, 0.55, 0.42)).normalized() * laenge * 4.0
    kam.rotation_euler = (-kam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(ordner, wid + ".png")
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    if not bpy.app.background:
        raise RuntimeError("Nur mit --background starten (das Skript leert die Szene).")
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    baue_alle(set(args))
