# Engine.blend -> models/engine_radial.glb + Profil-Extraktion (tools/radial_profile.json).
#
# Quelle (Downloads/Engine.blend):
#   'engine_full' = freistehende Motorgondel (eigenes geschlossenes Heck)
#   'engine_half' = dieselbe Vordersektion, hinten FLACH abgeschnitten -> hier dockt der Rumpf an
#   'Fuselage'    = flaches Blatt = Querschnitt GENAU an dieser Schnittebene
#   'propeller'   = 2-Blatt-Holzprop
#
# Nase liegt in der Datei bei -Y -> Projekt-Konvention (+Y = vorne, Godot -Z): 180° um Z.
# Beide Varianten teilen Nasenebene + Achse -> im Spiel per Sichtbarkeit umschaltbar, ohne
# dass sich irgendwas verschiebt. Ursprung = Mitte der HALF-Box, damit ein andockendes
# Rumpfsegment (generischer _fuselage_fit ueber col_size/col_offset) exakt auf der
# Schnittebene landet -> kein Sonderfall noetig.
import bpy, json, math
import numpy as np
from mathutils import Matrix, Vector

SRC = "C:/Users/Konst/Downloads/Engine.blend"
OUT = "C:/Users/Konst/Projects/aviasembly/models/engine_radial.glb"
PROFILE_OUT = "C:/Users/Konst/Projects/aviasembly/tools/radial_profile.json"
TARGET_W = 1.2   # Spiel-Breite des Querschnitts = Standard-Rumpfbreite (fuselage: 1.2 x 1.2)

bpy.ops.wm.open_mainfile(filepath=SRC)
objs = bpy.data.objects
full, half, sheet, prop = objs["engine_full"], objs["engine_half"], objs["Fuselage"], objs["propeller"]


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
hx = (wverts(half)[:, 0].max() + wverts(half)[:, 0].min()) * 0.5   # HALF-Achse X
fx = (wverts(full)[:, 0].max() + wverts(full)[:, 0].min()) * 0.5   # FULL-Achse X
half.matrix_world = Matrix.Translation(Vector((fx - hx, 0.0, 0.0))) @ half.matrix_world
bake(half)
print("HALF koaxial geschoben: dx=%+.4f" % (fx - hx))

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
print("FULL-Materialien:", [m.name if m else None for m in full.data.materials])
print("HALF-Materialien:", [m.name if m else None for m in half.data.materials])
print("PROP-Materialien:", [m.name if m else None for m in prop.data.materials])

# --- 9) Namen fuer Godot -------------------------------------------------------------------
for o, nm in ((full, "Full"), (half, "Half"), (prop, "Prop")):
    o.name = nm
    o.data.name = nm

# --- 10) Export ----------------------------------------------------------------------------
bpy.ops.object.select_all(action='DESELECT')
for o in (full, half, prop):
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True)

for o, nm in ((full, "Full"), (half, "Half"), (prop, "Prop")):
    V = wverts(o)
    lo, hi = V.min(axis=0), V.max(axis=0)
    print("%-5s Blender X %+.3f..%+.3f  Y %+.3f..%+.3f  Z %+.3f..%+.3f   -> Godot size(%.3f, %.3f, %.3f)"
          % (nm, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1]))
print("EXPORTED", OUT)
