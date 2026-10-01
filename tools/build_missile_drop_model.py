"""Baut das Modell der Abwurf-Boost-Rakete (Teil `missile_drop`) als schlichtes Low-Poly-Netz.

Vorbild ist eine AGM-65 "Maverick": dicker Rumpf, stumpfe Nase mit dunklem IR-Suchkopf,
vier lange Deltafluegel in X-Stellung, direkt dahinter vier Ruder, oben drei Aufhaengungen.

Das Skript baut alles aus Zahlen neu und liest KEINE fremde Blend-Datei. Die Vorlage (ein
10 789-Dreiecke-Netz mit DDS-Texturen) wurde nur VERMESSEN — Laenge, Rumpfradius, Spannweite,
Lage von Suchkopf und Aufhaengungen stehen unten als Konstanten in den Einheiten der Vorlage
(Zoll, Laengsachse dort X, hier Y). Uebrig bleiben 888 Dreiecke und drei flache
Materialien wie bei missile.glb / missile_heavy.glb: `body` (lackierbar), `glass`, `dark`.

ZWEI BETRIEBSARTEN, je nachdem wie Blender laeuft:

1. IN DER OFFENEN SITZUNG (Reiter "Scripting" -> Text -> Oeffnen -> Skript ausfuehren):
   stellt das Modell NEBEN die Vorlage — gleiche Einheiten, gleiche Ausrichtung (Nase +X),
   Nase und Heck auf derselben Station, eigene Collection `missile_drop_lowpoly`. Die Szene
   wird nicht angefasst; nur ein frueheres Exemplar dieses Modells wird ersetzt.

2. IM HINTERGRUND: leert die Szene, baut in Metern mit dem Achsenvertrag der Bauteile
   (Blender +Y = Nase, wird Godot -Z; +Z = oben) und schreibt models/missile_drop.glb.
       blender --background --factory-startup --python tools/build_missile_drop_model.py
   Kontrollbilder dazu: Umgebungsvariable MISSILE_DROP_PREVIEW=<ordner> setzen.
   Danach: Godot --headless --editor --import
"""
import bpy
import json
import math
import os
from mathutils import Vector

NAME = "missile_drop"
NAME_DANEBEN = "missile_drop_lowpoly"
LAENGE = 2.9            # Meter, = size.z des Katalogteils
SEGMENTE = 24           # Rumpf-Umfang
BODY, GLASS, DARK = 0, 1, 2

# --- Masse der Vorlage (Zoll; y laeuft vom Heck -49.6 zur Nasenspitze +49.75) ----------
R = 6.10                # Rumpfradius
HECK = -49.60
GLAS_AB = 48.04         # hier beginnt die Suchkopf-Kuppel
SPITZE = 49.75
GLAS_R = 3.50
R_FLOSSE = 14.48        # Radius der Fluegel- und Ruderspitzen
R_WURZEL = 5.60         # Flossenwurzel steckt 0,5 unter der Haut -> kein Spalt am Rumpf
# Deltafluegel: Vorderkante laeuft GERADE von der Wurzel (y 17,1 auf der Haut) bis zur
# Spitze bei y -36,1 — der Fluegel beginnt also weit vor der Rumpfmitte. Die Wurzel ist
# auf derselben Geraden bis R_WURZEL unter die Haut verlaengert.
FLUEGEL = [(20.95, R_WURZEL), (-36.1, R_FLOSSE), (-36.6, 14.0), (-36.6, R_WURZEL)]
# Ruder: Rechteck hinter dem Fluegel, dazwischen 4,4 Luft.
RUDER = [(-41.0, R_WURZEL), (-41.0, R_FLOSSE), (-47.1, R_FLOSSE), (-47.1, R_WURZEL)]
# Aufhaengungen oben: (y hinten, y vorn, Laenge der Schraege). Es sind ZWEI, nicht drei:
# ein kurzer Traeger vorn und ein langer, der vom Fluegelende bis zur Rumpfmitte reicht.
# Jeder ist ein U — zwei Schienen aussen, dazwischen ein tieferer Boden.
HAKEN = [(14.8, 24.3, 3.6), (-37.3, -2.5, 3.0)]
HAKEN_BREIT = 3.3       # halbe Breite ueber beide Schienen
HAKEN_SCHIENE = 2.3     # Innenkante der Schienen
HAKEN_OBEN = 7.38
HAKEN_BODEN = 6.40      # Oberkante des Bodens zwischen den Schienen
HAKEN_UNTEN = 4.90      # unter der Rumpfhaut (bei x = 3,3 liegt die Haut auf 5,13)
ABSTAND_DANEBEN = 8.0   # Luft zwischen Vorlage und Modell in der offenen Sitzung


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
        self.faces = []      # (Indizes, Material, glatt)

    def teil(self, verts, faces, mats, glatt):
        if isinstance(mats, int):
            mats = [mats] * len(faces)
        if _volumen(verts, faces) < 0.0:
            faces = [tuple(reversed(f)) for f in faces]
        basis = len(self.verts)
        self.verts.extend(verts)
        for f, m in zip(faces, mats):
            self.faces.append((tuple(basis + i for i in f), m, glatt))


def rotationskoerper(profil, seg):
    """profil: [(y, r, Material des Bandes bis zum naechsten Punkt)], von Achse zu Achse.

    Ein Punkt mit r = 0 ist EIN Vertex (Faecher statt entarteter Vierecke). Weil das Profil
    auf der Achse beginnt und endet, ist die Flaeche geschlossen.
    """
    verts, start = [], []
    for y, r, _ in profil:
        start.append(len(verts))
        if r <= 1e-9:
            verts.append(Vector((0.0, y, 0.0)))
        else:
            for i in range(seg):
                a = math.tau * i / seg
                verts.append(Vector((r * math.cos(a), y, r * math.sin(a))))
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


def flosse(umriss, winkel, dicke_wurzel, dicke_spitze):
    """Platte mit dem Umriss [(y, r)] in der Ebene durch die Laengsachse, zur Spitze duenner."""
    richt = Vector((math.cos(winkel), 0.0, math.sin(winkel)))
    quer = Vector((-math.sin(winkel), 0.0, math.cos(winkel)))
    oben, unten = [], []
    for y, r in umriss:
        t = (r - R_WURZEL) / (R_FLOSSE - R_WURZEL)
        d = 0.5 * (dicke_wurzel + (dicke_spitze - dicke_wurzel) * t)
        mitte = richt * r + Vector((0.0, y, 0.0))
        oben.append(mitte + quer * d)
        unten.append(mitte - quer * d)
    n = len(umriss)
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((j, i, n + i, n + j))
    return oben + unten, faces


def hoecker(x0, x1, y0, y1, zt, c):
    """Klotz von x0..x1 mit angeschraegter Vorder- und Hinterkante (Schraege c lang)."""
    zb = HAKEN_UNTEN
    verts = [Vector(v) for v in (
        (x0, y0, zb), (x1, y0, zb), (x1, y1, zb), (x0, y1, zb),
        (x0, y0 + c, zt), (x1, y0 + c, zt), (x1, y1 - c, zt), (x0, y1 - c, zt))]
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (1, 0, 4, 5), (2, 1, 5, 6), (3, 2, 6, 7), (0, 3, 7, 4)]
    return verts, faces


def material(name, farbe, metall, rauh):
    # Werte wie in missile.glb / missile_heavy.glb, damit die Flugkoerper eine Familie
    # bleiben. `body` ueberschreibt das Spiel ohnehin mit Katalog- bzw. Lackfarbe.
    # Vorhandenes wiederverwenden: beim zweiten Lauf in der offenen Sitzung entstuende
    # sonst body.001, body.002 ...
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.diffuse_color = (*farbe, 1.0)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    if p is not None:
        p.inputs["Base Color"].default_value = (*farbe, 1.0)
        p.inputs["Metallic"].default_value = metall
        p.inputs["Roughness"].default_value = rauh
    return m


def baue_netz():
    netz = Netz()

    # RUMPF in einem Zug von der Duesenmitte bis zur Kuppelspitze: Duese (ein Stutzen, der
    # in einer Heckmulde steht — die Verfolgerkamera sieht Flugkoerper fast nur von hinten),
    # Heckfase, langer Zylinder, sich verjuengende Nase, dunkler Suchkopfring, Glaskuppel.
    profil = [
        (HECK + 1.5, 0.00, DARK),
        (HECK + 1.5, 1.70, DARK),
        (HECK, 2.20, DARK),
        (HECK + 2.8, 2.60, DARK),
        (HECK + 2.8, 5.30, DARK),
        (HECK, 5.75, BODY),
        (HECK + 0.6, R, BODY),
        (36.0, R, BODY),
        (39.5, 5.85, BODY),
        (42.5, 5.48, BODY),
        (44.5, 5.13, BODY),
        (46.0, 4.68, BODY),
        (47.2, 4.05, DARK),
        (GLAS_AB, GLAS_R, GLASS),
    ]
    hoehe = SPITZE - GLAS_AB                      # Kugelkappe ueber dem Ring GLAS_R
    kugel_r = (GLAS_R * GLAS_R + hoehe * hoehe) / (2.0 * hoehe)
    oeffnung = math.asin(GLAS_R / kugel_r)
    for k in (2, 1):
        th = oeffnung * k / 3.0
        profil.append((SPITZE - kugel_r + kugel_r * math.cos(th), kugel_r * math.sin(th), GLASS))
    profil.append((SPITZE, 0.0, GLASS))
    verts, faces, mats = rotationskoerper(profil, SEGMENTE)
    netz.teil(verts, faces, mats, True)

    # VIER FLUEGEL + VIER RUDER in X-Stellung. Fluegel in Rumpffarbe, Ruder dunkel
    # abgesetzt — sonst liest man den Schlitz dazwischen aus der Entfernung nicht.
    for q in range(4):
        w = math.radians(45.0 + 90.0 * q)
        v, f = flosse(FLUEGEL, w, 1.00, 0.45)
        netz.teil(v, f, BODY, False)
        v, f = flosse(RUDER, w, 0.90, 0.45)
        netz.teil(v, f, DARK, False)

    # AUFHAENGUNGEN: Boden in Rumpffarbe, Schienen dunkel. Der Boden ist niedriger, seine
    # Schraege im selben Winkel also entsprechend kuerzer.
    anteil = (HAKEN_BODEN - HAKEN_UNTEN) / (HAKEN_OBEN - HAKEN_UNTEN)
    for y0, y1, c in HAKEN:
        v, f = hoecker(-HAKEN_SCHIENE, HAKEN_SCHIENE, y0, y1, HAKEN_BODEN, c * anteil)
        netz.teil(v, f, BODY, False)
        for seite in (-1.0, 1.0):
            xa, xb = sorted((seite * HAKEN_SCHIENE, seite * HAKEN_BREIT))
            v, f = hoecker(xa, xb, y0, y1, HAKEN_OBEN, c)
            netz.teil(v, f, DARK, False)
    return netz


def mesh_anlegen(name, punkte, netz):
    me = bpy.data.meshes.new(name)
    me.from_pydata(punkte, [], [f[0] for f in netz.faces])
    for m in (material("body", (0.74, 0.75, 0.78), 0.55, 0.35),
              material("glass", (0.10, 0.13, 0.20), 0.30, 0.10),
              material("dark", (0.10, 0.10, 0.12), 0.55, 0.55)):
        me.materials.append(m)
    for poly, (_, mat, glatt) in zip(me.polygons, netz.faces):
        poly.material_index = mat
        poly.use_smooth = glatt
    korrigiert = me.validate()
    me.update()
    # Harte Kanten am Heck (Fase -> Stirnflaeche -> Duesentrichter); der Rumpfumfang
    # (15 Grad je Segment) und die Nasenstufen bleiben weich.
    me.set_sharp_from_angle(angle=math.radians(40.0))
    return me, bool(korrigiert)


def baue_daneben():
    """Offene Sitzung: Modell in den Einheiten der Vorlage neben sie stellen."""
    scene = bpy.context.scene
    alt = bpy.data.objects.get(NAME_DANEBEN)
    if alt is not None:
        altes_netz = alt.data
        bpy.data.objects.remove(alt, do_unlink=True)
        if altes_netz is not None and altes_netz.users == 0:
            bpy.data.meshes.remove(altes_netz)

    # Neben das, was schon da ist: groesstes +Y aller Netze der Szene, dazu Luft.
    rand = None
    for o in scene.objects:
        if o.type != "MESH":
            continue
        for ecke in o.bound_box:
            y = (o.matrix_world @ Vector(ecke)).y
            rand = y if rand is None else max(rand, y)
    halb = R_FLOSSE * math.sin(math.radians(45.0))
    versatz = 0.0 if rand is None else rand + ABSTAND_DANEBEN + halb

    netz = baue_netz()
    # Baukoordinaten (Nase +Y) -> Vorlage (Nase +X): Drehung um Z, keine Spiegelung.
    punkte = [(v.y, -v.x, v.z) for v in netz.verts]
    me, korrigiert = mesh_anlegen(NAME_DANEBEN, punkte, netz)
    obj = bpy.data.objects.new(NAME_DANEBEN, me)
    obj.location = (0.0, versatz, 0.0)

    coll = bpy.data.collections.get(NAME_DANEBEN)
    if coll is None:
        coll = bpy.data.collections.new(NAME_DANEBEN)
    if coll.name not in scene.collection.children:
        scene.collection.children.link(coll)
    coll.objects.link(obj)

    # Erst abgleichen: nach dem Entfernen des alten Exemplars liefert die Ansichtsebene
    # sonst einen leeren Eintrag (None) fuer das eben geloeschte, aktive Objekt.
    bpy.context.view_layer.update()
    for o in scene.objects:
        if o is not None and o.name in bpy.context.view_layer.objects:
            o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    ergebnis = {
        "objekt": obj.name, "collection": coll.name, "versatz_y": round(versatz, 2),
        "dreiecke": sum(len(p.vertices) - 2 for p in me.polygons),
        "vertices": len(me.vertices), "validate_korrigiert": korrigiert,
    }
    print("ERGEBNIS " + json.dumps(ergebnis))
    return ergebnis


def baue_export():
    """Hintergrund: leere Szene, Meter, Bauteil-Achsen, glb schreiben."""
    projekt = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    glb = os.path.join(projekt, "models", NAME + ".glb")
    ordner = os.environ.get("MISSILE_DROP_PREVIEW", "")

    bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"

    netz = baue_netz()
    # Zoll -> Meter und auf die Boxmitte zentrieren: Laenge exakt LAENGE, Achse durch 0.
    ys = [v.y for v in netz.verts]
    k = LAENGE / (max(ys) - min(ys))
    mitte = 0.5 * (max(ys) + min(ys))
    punkte = [(v.x * k, (v.y - mitte) * k, v.z * k) for v in netz.verts]
    me, korrigiert = mesh_anlegen(NAME, punkte, netz)

    obj = bpy.data.objects.new(NAME, me)
    scene.collection.objects.link(obj)
    bpy.context.view_layer.update()

    os.makedirs(os.path.dirname(glb), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=glb, export_format="GLB", use_selection=True, export_apply=True,
        export_materials="EXPORT", export_texcoords=False, export_normals=True)

    xs = [p[0] for p in punkte]
    zs = [p[2] for p in punkte]
    ergebnis = {
        "glb": glb,
        "dreiecke": sum(len(p.vertices) - 2 for p in me.polygons),
        "vertices": len(me.vertices),
        "validate_korrigiert": korrigiert,
        "groesse_blender_xyz": [round(max(xs) - min(xs), 4), round(LAENGE, 4),
                                round(max(zs) - min(zs), 4)],
        "rumpf_durchmesser": round(2.0 * R * k, 4),
        "massstab_m_je_zoll": round(k, 6),
    }
    if ordner:
        ergebnis["vorschau"] = vorschau(scene, ordner)
    print("ERGEBNIS " + json.dumps(ergebnis))
    return ergebnis


def vorschau(scene, ordner):
    """Kontrollbilder (Workbench, Materialfarben). Wird nicht mit exportiert."""
    # Absolut machen: einen relativen Renderpfad loest Blender gegen die Laufwerkswurzel
    # auf, nicht gegen das Arbeitsverzeichnis — die Bilder landeten in C:\blender_lib.
    ordner = os.path.abspath(ordner)
    os.makedirs(ordner, exist_ok=True)
    welt = bpy.data.worlds.new("Vorschau")
    welt.color = (0.045, 0.060, 0.085)
    scene.world = welt
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_cavity = True
    sh.show_shadows = True
    scene.display.render_aa = "16"
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"

    kd = bpy.data.cameras.new("VorschauKamera")
    kd.type = "ORTHO"
    kd.ortho_scale = 3.3
    kam = bpy.data.objects.new("VorschauKamera", kd)
    scene.collection.objects.link(kam)
    scene.camera = kam
    ziel = Vector((0.0, 0.0, 0.0))
    ansichten = {
        "schraeg_vorn": (3.0, 3.6, 1.9),
        "seite": (6.0, 0.0, 0.0),
        "oben": (0.0, 0.0, 6.0),
        "schraeg_hinten": (3.0, -3.6, 1.9),
        "vorn": (0.0, 6.0, 0.0),
    }
    bilder = []
    for name, ort in ansichten.items():
        kam.location = ort
        kam.rotation_euler = (ziel - kam.location).to_track_quat("-Z", "Y").to_euler()
        kd.ortho_scale = 1.1 if name == "vorn" else 3.3
        pfad = os.path.join(ordner, "missile_drop_" + name + ".png")
        scene.render.filepath = pfad
        bpy.ops.render.render(write_still=True)
        bilder.append(pfad)
    return bilder


# Im Hintergrund wird exportiert (und dafuer die Szene geleert). In einer offenen Sitzung
# waere genau das der Verlust der Arbeit dort — da wird nur danebengestellt.
if bpy.app.background:
    baue_export()
else:
    baue_daneben()
