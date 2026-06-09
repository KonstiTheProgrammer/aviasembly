## Hochwertiges JET-NASENTEIL (MiG-15-Stil) -> res://models/jet_nose.glb
## Kern: ein ECHTER Einlauf mit gerundeter Lippe — die Außenhaut rollt über eine runde
## Vorderkante (Apex) nach innen und wird zur Innenwand des tiefen, matt-schwarzen Schachts.
## Querschnitt hinten = generisches Rumpfsegment (0.65 x 0.55 ellipt.) -> stoßbündig.
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_jet_nose.py
## Achsen (glTF +Y up): Blender X->Godot X, Z->Godot Y(oben), +Y->Godot -Z (Nase vorne).
import bpy, bmesh, math
for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
for me in list(bpy.data.meshes): bpy.data.meshes.remove(me)
for mt in list(bpy.data.materials): bpy.data.materials.remove(mt)

def newmat(name, col, rough, metal):
    m = bpy.data.materials.new(name); m.name = name; m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
    return m
MB = newmat("body", (0.80, 0.81, 0.84), 0.34, 0.6)        # blanke Alu-Haut (lackierbar)
MD = newmat("ductdark", (0.02, 0.02, 0.025), 1.0, 0.0)    # Schacht (Godot erzwingt beidseitig)
MD.use_backface_culling = False

N = 48
def ering(bm, y, rw, rh):
    return [bm.verts.new((rw * math.cos(math.tau * i / N), y, rh * math.sin(math.tau * i / N))) for i in range(N)]
def bridge(bm, a, b, mi):
    for j in range(N):
        j2 = (j + 1) % N
        bm.faces.new((a[j], a[j2], b[j2], b[j])).material_index = mi

bm = bmesh.new()
# --- Außenhaut: glatte Nase, hinten auf den Rumpf-Querschnitt (0.65 x 0.55), vorne zum Mund.
OUTER = [
    (-0.95, 0.650, 0.550),   # Andock-Ring hinten (offen)
    (-0.45, 0.662, 0.566),
    (0.10,  0.668, 0.575),   # größter Querschnitt
    (0.55,  0.652, 0.566),
    (0.84,  0.622, 0.548),   # Mund-Außenrand
]
orings = [ering(bm, y, rw, rh) for (y, rw, rh) in OUTER]
for i in range(len(orings) - 1):
    bridge(bm, orings[i], orings[i + 1], 0)
# --- Gerundete Einlauf-Lippe: vom Mund-Außenrand über den Apex (vorderster, runder Punkt)
#     nach innen zur Schachtwand. Glatte 180°-Rolle = echte Intake-Lippe.
LIP = [
    (0.84,  0.622, 0.548),
    (0.905, 0.612, 0.540),
    (0.945, 0.592, 0.522),   # Apex: vorderste, gerundete Kante
    (0.928, 0.565, 0.498),
    (0.885, 0.545, 0.480),   # Innenkante -> Schacht
]
lrings = [ering(bm, y, rw, rh) for (y, rw, rh) in LIP]
bridge(bm, orings[-1], lrings[0], 0)            # Mund-Außenrand = LIP[0]
for i in range(len(lrings) - 1):
    bridge(bm, lrings[i], lrings[i + 1], 0)
# --- Tiefer, matt-schwarzer Einlaufschacht (leicht verjüngt) ab Lippen-Innenkante, dunkel gekappt.
DUCT = [
    (0.885, 0.545, 0.480),
    (0.45,  0.515, 0.455),
    (-0.15, 0.470, 0.420),
    (-0.62, 0.395, 0.355),
]
drings = [ering(bm, y, rw, rh) for (y, rw, rh) in DUCT]
bridge(bm, lrings[-1], drings[0], 1)
for i in range(len(drings) - 1):
    bridge(bm, drings[i], drings[i + 1], 1)
bm.faces.new(drings[-1][::-1]).material_index = 1   # dunkle Schacht-Stirnkappe (Tiefe, kein Durchblick)

bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("Nose"); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
ob = bpy.data.objects.new("Nose", me); bpy.context.scene.collection.objects.link(ob)
ob.data.materials.append(MB); ob.data.materials.append(MD)
# Etwas Glättung für hochwertige, runde Lippe
mod = ob.modifiers.new("bevel", 'BEVEL'); mod.width = 0.012; mod.segments = 2

PATH = "/Users/konstantinkanzler/Downloads/aviasembly/models/jet_nose.glb"
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=PATH, export_format='GLB', use_selection=True, export_yup=True, export_apply=True)
print("EXPORTED", PATH)
