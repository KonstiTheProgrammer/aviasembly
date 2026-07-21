# reto_test.blend -> models/reto_engine.glb + Profil-Extraktion.
# 'Rumpf'=Motorkoerper, 'RotorBlade'=Propeller, 'Fuselage'=flaches Profil-Blatt.
# Nase = +X in der Datei -> Projekt-Konvention +Y (Godot -Z): +90 um Z.
# PROP robust: Scheiben-Ebene per PCA bestimmen (kleinste Varianz = Drehachse), auf +Y
# ausrichten, auf die Mittelachse zentrieren und die Nabe an die Cowl-Nase setzen -> der
# Godot-"Prop"-Knoten dreht sauber um die Schubachse, sitzt buendig vorn.
import bpy, json, math
import numpy as np
from mathutils import Matrix, Vector

SRC = "C:/Users/Konst/Downloads/reto_test.blend"
OUT = "C:/Users/Konst/Projects/aviasembly/models/reto_engine.glb"
PROFILE_OUT = "C:/Users/Konst/Projects/aviasembly/tools/reto_profile.json"
SPINNER_GAP = 0.10   # Nabe so weit VOR der Nase (m)

bpy.ops.wm.open_mainfile(filepath=SRC)
objs = bpy.data.objects
sheet, body, pivot, blade = objs["Fuselage"], objs["Rumpf"], objs["Pivot"], objs["RotorBlade"]

# --- 1) Profil aus dem Blatt (Y=Breite, Z=Hoehe), winkelsortiert, normiert ---
mw = sheet.matrix_world
pts = [(mw @ v.co) for v in sheet.data.vertices]
cy = (max(p.y for p in pts) + min(p.y for p in pts)) * 0.5
cz = (max(p.z for p in pts) + min(p.z for p in pts)) * 0.5
w_full = max(p.y for p in pts) - min(p.y for p in pts)
h_full = max(p.z for p in pts) - min(p.z for p in pts)
ordered = sorted(pts, key=lambda p: math.atan2(p.z - cz, p.y - cy))[::2]
norm = [[round((p.y - cy) / w_full, 4), round((p.z - cz) / h_full, 4)] for p in ordered]
json.dump({"w": round(w_full, 4), "h": round(h_full, 4), "points": norm}, open(PROFILE_OUT, "w"))
print("PROFIL: %d Punkte  w=%.3f h=%.3f" % (len(norm), w_full, h_full))
bpy.data.objects.remove(sheet, do_unlink=True)

# --- 2) Blade + Body von Parents/Modifiern/Transforms loesen (Geometrie = Weltkoordinaten) ---
mwb = blade.matrix_world.copy()
blade.parent = None
blade.matrix_world = mwb
bpy.data.objects.remove(pivot, do_unlink=True)
print("BLADE modifiers:", [(m.name, m.type) for m in blade.modifiers])
print("BODY modifiers:", [(m.name, m.type) for m in body.modifiers])
for o in (body, blade):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True); bpy.context.view_layer.objects.active = o
    # Modifier ANWENDEN (glTF wuerde sie sonst separat exportieren -> Geometrie/Orientierung kaputt)
    for m in list(o.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except Exception as ex:
            print("modifier_apply fail", m.name, ex); o.modifiers.remove(m)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- 3) +90 um Z (Nase +X -> +Y), Body-Boxmitte -> Ursprung; Blade zieht mit ---
rz = Matrix.Rotation(math.radians(90.0), 4, 'Z')
for o in (body, blade):
    o.matrix_world = rz @ o.matrix_world
bpy.context.view_layer.update()
bc = [body.matrix_world @ Vector(c) for c in body.bound_box]
lo = Vector((min(c[i] for c in bc) for i in range(3)))
hi = Vector((max(c[i] for c in bc) for i in range(3)))
center = (lo + hi) * 0.5
for o in (body, blade):
    o.matrix_world = Matrix.Translation(-center) @ o.matrix_world
bpy.context.view_layer.update()
body_front = (hi.y - center.y)   # Nase = +Y
print("BODY zentriert. Nase(+Y)=%.3f  dims=%s" % (body_front, tuple(round(hi[i]-lo[i],3) for i in range(3))))

# --- 4) PROP-Scheibe per PCA auf +Y ausrichten ---
def verts_world():
    m = blade.matrix_world
    return np.array([(m @ v.co)[:] for v in blade.data.vertices])

V = verts_world()
c0 = V.mean(axis=0)
cov = (V - c0).T @ (V - c0)
evals, evecs = np.linalg.eigh(cov)          # aufsteigend -> [:,0] = kleinste Varianz = Normale
normal = evecs[:, 0].astype(float)
if normal[1] < 0.0:
    normal = -normal
print("PCA: Scheiben-Normale=%s  Eigenwerte=%s" % (tuple(round(x,3) for x in normal), tuple(round(e,2) for e in evals)))
tgt = np.array([0.0, 1.0, 0.0])
ax = np.cross(normal, tgt); s = float(np.linalg.norm(ax)); cang = float(np.dot(normal, tgt))
if s > 1e-6:
    ax = ax / s
    R = Matrix.Rotation(math.atan2(s, cang), 4, Vector((float(ax[0]), float(ax[1]), float(ax[2]))))
    piv = Vector((float(c0[0]), float(c0[1]), float(c0[2])))
    blade.matrix_world = Matrix.Translation(piv) @ R @ Matrix.Translation(-piv) @ blade.matrix_world
    bpy.context.view_layer.update()

# --- 5) Auf Mittelachse (x=z=0) + Nabe an die Nase (Y = body_front + gap) ---
V = verts_world()
c1 = V.mean(axis=0)
hub_y = body_front + SPINNER_GAP
delta = Vector((-float(c1[0]), hub_y - float(c1[1]), -float(c1[2])))
blade.matrix_world = Matrix.Translation(delta) @ blade.matrix_world
bpy.context.view_layer.update()
V = verts_world()
print("PROP ausgerichtet: hub_y=%.3f  Blade-AABB Y=%.3f..%.3f  X=%.2f Z=%.2f" %
      (hub_y, V[:, 1].min(), V[:, 1].max(), V[:, 0].max() - V[:, 0].min(), V[:, 2].max() - V[:, 2].min()))

# ALLE Blade-Rotationen INS MESH backen (Objekt-Rotation -> Identitaet). Sonst komponiert die
# Objekt-Rotation ueber die glTF-Achsenkonvertierung falsch (Godot: Scheibe verdreht).
bpy.ops.object.select_all(action='DESELECT')
blade.select_set(True); bpy.context.view_layer.objects.active = blade
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- 6) Blade IST der "Prop"-Node. Objekt bleibt bei Origin (0,0,0) mit gebackenem Mesh
#         (genau wie das Body-Objekt -> saubere glTF-Konvertierung, KEINE Verkippung).
#         KEIN origin_set (das brachte eine Node-Translation, die die Scheibe verkippte).
#         Die Scheibe ist auf x=z=0 zentriert -> Godot rotate_z (um die Schubachse) dreht
#         trotz Origin-am-Ursprung symmetrisch. Nur umbenennen -> FlightController dreht ihn.
blade.name = "Prop"
blade.data.name = "Prop"

# --- 7) Materialien: Koerper WEISS (lackierbar 'body'), Blade dunkel ---
def ensure_mat(o, name, col, metal, rough, force=False):
    if force or len(o.data.materials) == 0 or all(m is None for m in o.data.materials):
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        if b:
            b.inputs["Base Color"].default_value = (*col, 1.0)
            b.inputs["Metallic"].default_value = metal
            b.inputs["Roughness"].default_value = rough
        o.data.materials.clear(); o.data.materials.append(m)
ensure_mat(body, "body", (0.80, 0.82, 0.85), 0.3, 0.55, force=True)
graphite = bpy.data.materials.get("Propeller_Graphite")
if graphite:
    for i, m in enumerate(blade.data.materials):
        if m is None:
            blade.data.materials[i] = graphite
if len(blade.data.materials) == 0:
    ensure_mat(blade, "dark", (0.08, 0.08, 0.09), 0.3, 0.6, force=True)

# --- 8) Export ---
bpy.ops.object.select_all(action='DESELECT')
for o in (body, blade):
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True)
print("EXPORTED", OUT)
