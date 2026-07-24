# Engine.blend -> models/engine_radial.glb + models/cockpit_radial.glb
#                + Profil-Extraktion (tools/radial_profile.json).
#
# Quelle (Downloads/Engine.blend):
#   'engine_full' = freistehende Motorgondel (eigenes geschlossenes Heck)
#   'engine_half' = dieselbe Vordersektion, hinten FLACH abgeschnitten -> hier dockt der Rumpf an
#   'Fuselage'    = flaches Blatt = Querschnitt GENAU an dieser Schnittebene
#   'propeller'   = 2-Blatt-Holzprop
#   'Cockpit_Shell' + 'Cockpit_LeatherRim' = offenes Doppeldecker-Cockpit im selben Profil
#     (Rim ist eine CURVE mit Bevel -> vor dem Export in Mesh konvertieren!)
#
# Nase liegt in der Datei bei -Y -> Projekt-Konvention (+Y = vorne, Godot -Z): 180° um Z.
# Beide Engine-Varianten teilen Nasenebene + Achse -> im Spiel per Sichtbarkeit umschaltbar,
# ohne dass sich irgendwas verschiebt. Ursprung = Mitte der HALF-Box, damit ein andockendes
# Rumpfsegment (generischer _fuselage_fit ueber col_size/col_offset) exakt auf der
# Schnittebene landet -> kein Sonderfall noetig. Cockpit = eigenes glb, Box-zentriert.
#
# FALLE (Cockpit): ALLE Cockpit_*-Materialien liegen als unkonfiguriertes Default-Grau (0.8)
# in der Datei — nur die NAMEN beschreiben die Absicht. Farben werden hier aus den Namen
# gesetzt, sonst kaeme das Cockpit komplett grau raus.
import bpy, bmesh, json, math
import numpy as np
from mathutils import Matrix, Vector

SRC = "C:/Users/Konst/Downloads/Engine.blend"
OUT = "C:/Users/Konst/Projects/aviasembly/models/engine_radial.glb"
OUT_CP = "C:/Users/Konst/Projects/aviasembly/models/cockpit_radial.glb"
OUT_CP_FRAME = "C:/Users/Konst/Projects/aviasembly/models/cockpit_radial_frame.glb"
PROFILE_OUT = "C:/Users/Konst/Projects/aviasembly/tools/radial_profile.json"
TARGET_W = 1.2   # Spiel-Breite des Querschnitts = Standard-Rumpfbreite (fuselage: 1.2 x 1.2)

bpy.ops.wm.open_mainfile(filepath=SRC)
objs = bpy.data.objects
# Namen nach dem Aufraeum-Pass (Collection STERNMOTOR, deutsch benannt); Fallback auf die
# alten Namen, falls jemand eine aeltere Engine.blend einspielt.
def _obj(*names):
    for n in names:
        if n in objs:
            return objs[n]
    raise KeyError(f"Objekt fehlt: {names}")

full = _obj("Motor_Gondel", "engine_full")
half = _obj("Motor_Vorderteil", "engine_half")
sheet = _obj("Rumpf_Profilblatt", "Fuselage")
prop = _obj("Motor_Propeller", "propeller")
cp_shell, cp_rim = objs.get("Cockpit_Shell"), objs.get("Cockpit_LeatherRim")

# Propeller haengt (seit dem Cleanup) als Kind an der Gondel -> fuer die eigenstaendige
# Transform-Pipeline loesen, Welt-Pose beibehalten (wie beim Reto-Skript).
if prop.parent is not None:
    mw = prop.matrix_world.copy()
    prop.parent = None
    prop.matrix_world = mw


# SHADING-UEBERNAHME: die Quelle nutzt "Shade Auto Smooth" = ein "Smooth by Angle"-
# NODES-Modifier (glatt, harte Kanten ab Winkel). Der ging beim Export bisher VERLOREN
# (glb kam fast komplett flat raus). Modifier hier ANWENDEN -> der Look wird als Custom
# Split Normals ins Mesh gebacken und uebersteht Transforms + glTF-Export exakt.
def apply_modifiers(o):
    if o is None or o.type != 'MESH' or not o.modifiers:
        return
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except Exception as ex:  # noqa: BLE001
            print("modifier_apply fail:", o.name, m.name, ex)
            o.modifiers.remove(m)


for _o in (full, half, prop, cp_shell):
    apply_modifiers(_o)


def sel(o):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o


def bake(o):
    sel(o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def wverts(o):
    m = o.matrix_world
    return np.array([(m @ v.co)[:] for v in o.data.vertices])


# --- 1) PROFIL aus dem Blatt: n-gon-Schleife = echte Umrissreihenfolge (kein Winkel-Sortieren) --
# Blatt liegt in X-Z (Y-Dim = 0) und ist auf seinen eigenen Ursprung zentriert.
# Godot-Profil: x = Godot-X, y = Godot-Y(oben) = Blender-Z. Die spaetere 180°-Z-Drehung
# spiegelt X -> hier gleich mit anwenden, damit Profil und Modell zusammenpassen.
poly = sheet.data.polygons[0]
loop = [sheet.data.vertices[vi].co for vi in poly.vertices]
w_full = max(p.x for p in loop) - min(p.x for p in loop)
h_full = max(p.z for p in loop) - min(p.z for p in loop)
cx = (max(p.x for p in loop) + min(p.x for p in loop)) * 0.5
cz = (max(p.z for p in loop) + min(p.z for p in loop)) * 0.5
pts = [(-(p.x - cx) / w_full, (p.z - cz) / h_full) for p in loop]   # -x = 180°-Drehung
area2 = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
            for i in range(len(pts)))
if area2 < 0.0:                       # _profile_tube erwartet CCW
    pts = pts[::-1]
norm = [[round(x, 4), round(y, 4)] for x, y in pts]
S = TARGET_W / w_full
json.dump({"w": round(w_full, 4), "h": round(h_full, 4), "scale": round(S, 6), "points": norm},
          open(PROFILE_OUT, "w"))
print("PROFIL: %d Punkte  Blatt %.3f x %.3f  ->  Spiel %.3f x %.3f  (S=%.5f)"
      % (len(norm), w_full, h_full, w_full * S, h_full * S, S))
bpy.data.objects.remove(sheet, do_unlink=True)

# --- 2) Transforms einbacken, HALF koaxial zu FULL schieben (im Blend nur zur Seite geparkt) --
for o in (full, half, prop):
    bake(o)
# HALF liegt im Blend nur GEPARKT (Position aendert sich zwischen Datei-Versionen!) ->
# in ALLEN Achsen an FULL ausrichten: X/Z auf die Achse, Y an der NASE ankern (min Y).
VH0, VF0 = wverts(half), wverts(full)
dx = (VF0[:, 0].max() + VF0[:, 0].min()) * 0.5 - (VH0[:, 0].max() + VH0[:, 0].min()) * 0.5
dz = (VF0[:, 2].max() + VF0[:, 2].min()) * 0.5 - (VH0[:, 2].max() + VH0[:, 2].min()) * 0.5
dy = VF0[:, 1].min() - VH0[:, 1].min()
half.matrix_world = Matrix.Translation(Vector((dx, dy, dz))) @ half.matrix_world
bake(half)
print("HALF an FULL ausgerichtet: d=(%+.4f, %+.4f, %+.4f)" % (dx, dy, dz))

# --- 3) Deckungs-Check: ist HALF wirklich die vordere Teilmenge von FULL? ------------------
VF, VH = wverts(full), wverts(half)
cut_y = VH[:, 1].max()            # Schnittebene (Nase = -Y, Heck = +Y)
print("NASE  full=%.3f half=%.3f   SCHNITT(half hinten)=%.3f   HECK full=%.3f"
      % (VF[:, 1].min(), VH[:, 1].min(), cut_y, VF[:, 1].max()))
for t in (0.15, 0.5, 0.85):
    y = VH[:, 1].min() + (cut_y - VH[:, 1].min()) * t
    mf = VF[np.abs(VF[:, 1] - y) < 0.09]
    mh = VH[np.abs(VH[:, 1] - y) < 0.09]
    if len(mf) and len(mh):
        wf, wh = float(np.ptp(mf[:, 0])), float(np.ptp(mh[:, 0]))
        print("   y=%+.2f  FULL-Breite=%.3f  HALF-Breite=%.3f  (Delta %.3f)" % (y, wf, wh, abs(wf - wh)))

# --- 4) 180° um Z (Nase -Y -> +Y) ---------------------------------------------------------
rz = Matrix.Rotation(math.radians(180.0), 4, 'Z')
for o in (full, half, prop):
    o.matrix_world = rz @ o.matrix_world
    bake(o)

# --- 5) Ursprung: Achse -> X=Z=0, Y so dass die HALF-Box mittig auf 0 sitzt ----------------
VH = wverts(half)
ax_x = (VH[:, 0].max() + VH[:, 0].min()) * 0.5
ax_z = (VH[:, 2].max() + VH[:, 2].min()) * 0.5
ax_y = (VH[:, 1].max() + VH[:, 1].min()) * 0.5
shift = Matrix.Translation(Vector((-ax_x, -ax_y, -ax_z)))
for o in (full, half, prop):
    o.matrix_world = shift @ o.matrix_world
    bake(o)

# --- 6) PROP-Blatt senkrecht stellen (im Blend ~38° verdreht; im Hangar steht er still) ----
VP = wverts(prop)
xz = VP[:, [0, 2]] - VP[:, [0, 2]].mean(axis=0)
evals, evecs = np.linalg.eigh(xz.T @ xz)
span = evecs[:, -1]                                   # groesste Varianz = Blattlaengsachse
ang = math.atan2(float(span[0]), float(span[1]))      # -> auf +Z (senkrecht) drehen
prop.matrix_world = Matrix.Rotation(-ang, 4, 'Y') @ prop.matrix_world
bake(prop)
print("PROP-Blatt gerichtet: %+.1f°" % math.degrees(ang))

# --- 7) Auf Spielmassstab skalieren --------------------------------------------------------
for o in (full, half, prop):
    o.matrix_world = Matrix.Scale(S, 4) @ o.matrix_world
    bake(o)

# --- 7b) COCKPIT: roter Rumpf und verschraubter Metall-Anschluss werden ZWEI Teile --------
# Der Quell-Mesh mischt beides über Material-Slots. Der rote Körper war an beiden
# Anschlussenden 1.228 x 1.157 statt des echten RADIAL_PROFILE 1.200 x 1.129 und
# der Metallrahmen war untrennbar mitgebacken. Jetzt:
#   cockpit_radial.glb       = maßhaltiger Cockpit-Rumpf OHNE Metallrahmen
#   cockpit_radial_frame.glb = nur der verschraubte Metallrahmen, eigenes Spielteil
def filter_material_faces(o, material_name, keep):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    remove = []
    for f in bm.faces:
        mat = o.data.materials[f.material_index] if f.material_index < len(o.data.materials) else None
        match = mat is not None and mat.name == material_name
        if match != keep:
            remove.append(f)
    if remove:
        bmesh.ops.delete(bm, geom=remove, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()


def remove_central_frame_details(o):
    """Entfernt die drei Cockpit-Schraubenköpfe, die nur zufällig dasselbe Material
    wie der Anschlussrahmen tragen. Rahmen und Randnieten liegen am Profilrand."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    xs = [v.co.x for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    cx = (min(xs) + max(xs)) * 0.5
    cz = (min(zs) + max(zs)) * 0.5
    hx = max((max(xs) - min(xs)) * 0.5, 1e-6)
    hz = max((max(zs) - min(zs)) * 0.5, 1e-6)

    seen = set()
    remove = []
    removed_islands = 0
    for seed in bm.faces:
        if seed in seen:
            continue
        island = []
        stack = [seed]
        seen.add(seed)
        while stack:
            face = stack.pop()
            island.append(face)
            for edge in face.edges:
                for neighbor in edge.link_faces:
                    if neighbor not in seen:
                        seen.add(neighbor)
                        stack.append(neighbor)
        verts = {v for face in island for v in face.verts}
        edge_radius = max(max(abs(v.co.x - cx) / hx, abs(v.co.z - cz) / hz)
                          for v in verts)
        if edge_radius < 0.55:
            remove.extend(island)
            removed_islands += 1
    if remove:
        bmesh.ops.delete(bm, geom=remove, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    print("RAHMEN: %d mittige Fremd-Inseln entfernt" % removed_islands)


def material_bounds(o, material_name):
    ids = set()
    for p in o.data.polygons:
        mat = o.data.materials[p.material_index] if p.material_index < len(o.data.materials) else None
        if mat is not None and mat.name == material_name:
            ids.update(p.vertices)
    if not ids:
        raise RuntimeError("Material-Geometrie fehlt: %s / %s" % (o.name, material_name))
    pts = np.array([(o.matrix_world @ o.data.vertices[i].co)[:] for i in ids])
    return pts.min(axis=0), pts.max(axis=0)


def seal_profile_cap(o, profile, width, height, material_name):
    """Ersetzt die löchrige +Y-Stirnseite durch einen vollständigen roten Profildeckel."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    y = max(v.co.y for v in bm.verts)
    eps = 1e-4
    old_cap = [f for f in bm.faces if all(abs(v.co.y - y) <= eps for v in f.verts)]
    if old_cap:
        bmesh.ops.delete(bm, geom=old_cap, context='FACES_ONLY')
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')

    cap_verts = [bm.verts.new((float(px) * width, y, float(pz) * height))
                 for px, pz in profile]
    cap = bm.faces.new(cap_verts)
    cap.normal_update()
    if cap.normal.y < 0.0:
        cap.normal_flip()
    cap.material_index = next(i for i, mat in enumerate(o.data.materials)
                              if mat is not None and mat.name == material_name)
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    print("COCKPIT: +Y-Profildeckel geschlossen (%d alte Stirnflächen ersetzt)"
          % len(old_cap))


cockpit = None
cockpit_frame = None
auto_frames = []   # Rahmen-Instanzen IM Cockpit-glb (FrameF/FrameB), pro Seite abschaltbar
if cp_shell is not None:
    # Rahmen als echte Geometrie-Kopie isolieren, aus dem Cockpit selbst entfernen.
    cockpit_frame = cp_shell.copy()
    cockpit_frame.data = cp_shell.data.copy()
    cp_shell.users_collection[0].objects.link(cockpit_frame)
    filter_material_faces(cockpit_frame, "Cockpit_ConnectorMetal", True)
    remove_central_frame_details(cockpit_frame)
    filter_material_faces(cp_shell, "Cockpit_ConnectorMetal", False)

    # Lederwulst bleibt Teil des Cockpits, nicht des optionalen Metallrahmens.
    if cp_rim is not None:
        sel(cp_rim)
        bpy.ops.object.convert(target='MESH')        # Curve mit Bevel -> echtes Mesh
        cp_rim = bpy.context.view_layer.objects.active
        bpy.ops.object.select_all(action='DESELECT')
        cp_rim.select_set(True)
        cp_shell.select_set(True)
        bpy.context.view_layer.objects.active = cp_shell
        bpy.ops.object.join()                        # ein Objekt, Materialslots bleiben
    cockpit = cp_shell

    # Gleiche Achsenkonvention und Grundskalierung wie Motor/Rumpf.
    for o in (cockpit, cockpit_frame):
        bake(o)
        o.matrix_world = rz @ o.matrix_world         # Nase -Y -> +Y wie Motor/Rumpf
        bake(o)
        o.matrix_world = Matrix.Scale(S, 4) @ o.matrix_world
        bake(o)

    # Cockpit am ROTEN RUMPF zentrieren (nicht am ehemals vorstehenden Rahmen) und
    # nur X/Z exakt auf das Stern-Rumpfprofil korrigieren. Innenausbau/Leder folgt mit.
    blo, bhi = material_bounds(cockpit, "Cockpit_RedPaint")
    bc = Vector((float((blo[i] + bhi[i]) * 0.5) for i in range(3)))
    cockpit.matrix_world = Matrix.Translation(-bc) @ cockpit.matrix_world
    bake(cockpit)
    blo, bhi = material_bounds(cockpit, "Cockpit_RedPaint")
    target_h = h_full * S
    sx = TARGET_W / float(bhi[0] - blo[0])
    sz = target_h / float(bhi[2] - blo[2])
    cockpit.matrix_world = Matrix.Diagonal(Vector((sx, 1.0, sz, 1.0))) @ cockpit.matrix_world
    bake(cockpit)
    seal_profile_cap(cockpit, norm, TARGET_W, target_h, "Cockpit_RedPaint")
    print("COCKPIT-Profil korrigiert: sx=%.5f sz=%.5f -> %.3f x %.3f"
          % (sx, sz, TARGET_W, target_h))

    # --- AUTO-Rahmen ins Cockpit-glb: an BEIDEN Anschlussenden eine Instanz ---------------
    # Der Editor zeigt sie standardmaessig und blendet sie PRO SEITE aus, sobald dort ein
    # Rumpf/Motor andockt (wie Motor Full/Half). Es wird nur die -bc-Zentrierung des
    # Cockpits nachgezogen — die sx/sz-Profilkorrektur galt dem falsch bemessenen roten
    # Rumpf, der Rahmen traegt bereits das masshaltige 1.200x1.129-Profil. Die zweite
    # Instanz entsteht per 180-Grad-Drehung um Z (Position UND Schraubenseite ans
    # Gegenende, keine Spiegelung -> Geometrie bleibt proper).
    for tag in ("A", "B"):
        c = cockpit_frame.copy()
        c.data = cockpit_frame.data.copy()
        cockpit_frame.users_collection[0].objects.link(c)
        c.matrix_world = Matrix.Translation(-bc) @ c.matrix_world
        if tag == "B":
            c.matrix_world = Matrix.Rotation(math.pi, 4, 'Z') @ c.matrix_world
        bake(c)
        auto_frames.append(c)
    ya = float(np.mean(wverts(auto_frames[0])[:, 1]))
    front, back = (auto_frames[0], auto_frames[1]) if ya >= 0.0 else (auto_frames[1], auto_frames[0])
    for o, nm in ((front, "FrameF"), (back, "FrameB")):   # Blender +Y = Godot -Z = VORNE
        o.name = nm
        o.data.name = nm
    print("AUTO-RAHMEN: FrameF y-Mitte %+.3f / FrameB y-Mitte %+.3f (Blender, +Y=vorn)"
          % (float(np.mean(wverts(front)[:, 1])), float(np.mean(wverts(back)[:, 1]))))

    # Rahmen ist ein selbstständiger Adapter: eigener Mittelpunkt, ursprüngliches
    # maßhaltiges 1.200-x-1.129-Profil, im Editor normal ansteck-/skalierbar.
    VFRA = wverts(cockpit_frame)
    fc = Vector((float((VFRA[:, i].max() + VFRA[:, i].min()) * 0.5) for i in range(3)))
    cockpit_frame.matrix_world = Matrix.Translation(-fc) @ cockpit_frame.matrix_world
    bake(cockpit_frame)

# --- 8) Materialien ------------------------------------------------------------------------
# ZUERST die .001-Duplikate von engine_half auf die Originale umhaengen — danach werden die
# Originale umbenannt, dann findet sie ein Namens-Lookup nicht mehr (Reihenfolge zaehlt!).
for i, m in enumerate(half.data.materials):
    if m is None or not m.name.endswith(".001"):
        continue
    base = bpy.data.materials.get(m.name[:-4])
    if base is not None:
        half.data.materials[i] = base

# Cowl -> "body": lackierbar (PAINT_MATS) + weiss wie die Rumpfsegmente.
# Die prozedurale Holz-Maserung (Wave-Texture + Color-Ramp) exportiert glTF NICHT -> aus der
# Color-Ramp einen flachen Holzton mitteln, sonst kommt das Blatt flach weiss raus.
def setmat(name, newname, col, metal, rough):
    m = bpy.data.materials.get(name)
    if m is None:
        return
    m.name = newname
    if not m.use_nodes:
        m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    if b is None:
        return
    for ln in list(b.inputs["Base Color"].links):
        m.node_tree.links.remove(ln)
    b.inputs["Base Color"].default_value = (*col, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough


wood = bpy.data.materials.get("EngineLP_CalculatedWood")
wcol = (0.36, 0.20, 0.09)
if wood and wood.use_nodes:
    ramp = wood.node_tree.nodes.get("Color Ramp")
    if ramp:
        s = [ramp.color_ramp.evaluate(t) for t in (0.2, 0.4, 0.6, 0.8)]
        wcol = tuple(sum(c[i] for c in s) / len(s) for i in range(3))
        print("HOLZ aus Color-Ramp gemittelt: (%.3f, %.3f, %.3f)" % wcol)

setmat("EngineLP_Cowl", "body", (0.80, 0.82, 0.85), 0.45, 0.38)          # lackierbar, weiss
setmat("EngineLP_CalculatedWood", "propwood", wcol, 0.0, 0.42)
setmat("EngineLP_WoodGrainEmbedded", "propwood_dark",
       tuple(c * 0.62 for c in wcol), 0.0, 0.5)
setmat("EngineLP_DarkHubMetal", "hub", (0.09, 0.10, 0.12), 0.75, 0.35)   # Name sagt dunkel
for nm, col, me, ro in (("LP_Interior", (0.05, 0.055, 0.06), 0.2, 0.85),
                        ("LP_EdgeMetal", (0.30, 0.32, 0.35), 0.7, 0.35),
                        ("LP_Mechanism", (0.16, 0.17, 0.19), 0.6, 0.45),
                        ("LP_Caps", (0.22, 0.235, 0.26), 0.55, 0.42),
                        ("LP_Pipes", (0.26, 0.27, 0.30), 0.7, 0.38)):
    setmat(nm, nm.lower(), col, me, ro)
# COCKPIT-Materialien: liegen ALLE als Default-Grau in der Datei (nur Namen gesetzt) ->
# Farben aus den Namen ableiten. RedPaint -> "cockpit_body" = lackierbar (PAINT_MATS).
# WICHTIG: Blender-Base-Color ist LINEAR, Godot zeigt sRGB — Zielfarben (sRGB) hier
# nach linear wandeln, sonst kommt z. B. sattes Rot als blasses Lachsrosa raus.
def srgb2lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)

setmat("Cockpit_RedPaint", "cockpit_body", srgb2lin((0.58, 0.10, 0.08)), 0.25, 0.45)
for nm, col, me, ro in (("Cockpit_ConnectorMetal", (0.45, 0.47, 0.50), 0.80, 0.30),
                        ("Cockpit_StructureWood", (0.42, 0.26, 0.13), 0.00, 0.55),
                        ("Cockpit_InteriorLinen", (0.70, 0.63, 0.50), 0.00, 0.85),
                        ("Cockpit_FrameGreen", (0.20, 0.30, 0.18), 0.15, 0.50),
                        ("Cockpit_DullAluminum", (0.55, 0.57, 0.60), 0.75, 0.50),
                        ("Cockpit_GaugeGlass", (0.07, 0.08, 0.10), 0.20, 0.12),
                        ("Cockpit_WornLeather", (0.30, 0.18, 0.10), 0.00, 0.70),
                        ("Cockpit_InteriorDark", (0.06, 0.06, 0.07), 0.10, 0.85)):
    setmat(nm, nm.replace("Cockpit_", "cp_").lower(), srgb2lin(col), me, ro)
print("FULL-Materialien:", [m.name if m else None for m in full.data.materials])
print("HALF-Materialien:", [m.name if m else None for m in half.data.materials])
print("PROP-Materialien:", [m.name if m else None for m in prop.data.materials])
if cockpit is not None:
    print("COCKPIT-Materialien:", [m.name if m else None for m in cockpit.data.materials])
if cockpit_frame is not None:
    print("RAHMEN-Materialien:", [m.name if m else None for m in cockpit_frame.data.materials])

# --- 9) Namen fuer Godot -------------------------------------------------------------------
for o, nm in ((full, "Full"), (half, "Half"), (prop, "Prop")):
    o.name = nm
    o.data.name = nm

# --- 10) Export ----------------------------------------------------------------------------
bpy.ops.object.select_all(action='DESELECT')
for o in (full, half, prop):
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_apply=True)

if cockpit is not None:
    cockpit.name = "Cockpit"
    cockpit.data.name = "Cockpit"
    bpy.ops.object.select_all(action='DESELECT')
    cockpit.select_set(True)
    for fr in auto_frames:   # FrameF/FrameB als Geschwister mit exportieren
        fr.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT_CP, export_format='GLB', use_selection=True, export_apply=True)

if cockpit_frame is not None:
    cockpit_frame.name = "CockpitRadialFrame"
    cockpit_frame.data.name = "CockpitRadialFrame"
    bpy.ops.object.select_all(action='DESELECT')
    cockpit_frame.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT_CP_FRAME, export_format='GLB',
                              use_selection=True, export_apply=True)

report = [(full, "Full"), (half, "Half"), (prop, "Prop")]
if cockpit is not None:
    report.append((cockpit, "Cockpit"))
if cockpit_frame is not None:
    report.append((cockpit_frame, "Frame"))
for o, nm in report:
    V = wverts(o)
    lo, hi = V.min(axis=0), V.max(axis=0)
    print("%-7s Blender X %+.3f..%+.3f  Y %+.3f..%+.3f  Z %+.3f..%+.3f   -> Godot size(%.3f, %.3f, %.3f)"
          % (nm, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1]))
print("EXPORTED", OUT,
      "+", OUT_CP if cockpit is not None else "(kein Cockpit)",
      "+", OUT_CP_FRAME if cockpit_frame is not None else "(kein Rahmen)")
