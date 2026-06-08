## Baut den North American F-86 Sabre-Rumpf (runder Nasen-Lufteinlauf + Bubble-Kanzel)
## -> res://models/f86_body.glb.
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_f86_body.py
## Achsen (glTF +Y up): Blender X->Godot X, Blender Z->Godot Y(oben), +Y->Godot -Z (Nase vorne).
import bpy, bmesh, math
for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
for me in list(bpy.data.meshes): bpy.data.meshes.remove(me)
for mt in list(bpy.data.materials): bpy.data.materials.remove(mt)

def newmat(name, col, rough, metal, alpha=1.0):
    m = bpy.data.materials.new(name); m.name = name; m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha; m.blend_method = 'BLEND'
    return m
MB = newmat("body", (0.82, 0.83, 0.86), 0.40, 0.55)       # helles blankes Aluminium (lackierbar)
MG = newmat("glass", (0.03, 0.03, 0.035), 0.08, 0.1)      # Kanzelglas: glänzend schwarz
MF = newmat("frame", (0.12, 0.12, 0.13), 0.5, 0.55)
MD = newmat("ductdark", (0.025, 0.025, 0.03), 0.6, 0.3)   # Einlauf-/Düsen-Innenraum (dunkel)

N = 26
def ering(bm, y, rw, rh, cz):
    return [bm.verts.new((rw*math.cos(math.tau*i/N), y, cz+rh*math.sin(math.tau*i/N))) for i in range(N)]
def bridge(bm, a, b, mi):
    for j in range(N):
        j2 = (j+1) % N; bm.faces.new((a[j], a[j2], b[j2], b[j])).material_index = mi

# --- Rumpf: runder Querschnitt, vorne offener Einlauf, hinten Düse ---
FUSE = [(3.0,0.42,0.42,0.0),(2.4,0.46,0.46,0.0),(1.4,0.50,0.50,0.0),(0.5,0.52,0.52,0.02),
 (-0.4,0.50,0.50,0.02),(-1.4,0.44,0.45,0.04),(-2.4,0.37,0.38,0.06),(-3.2,0.31,0.32,0.07),(-3.6,0.27,0.28,0.07)]
bm = bmesh.new()
rings = [ering(bm, *r) for r in FUSE]
for i in range(len(rings)-1):
    bridge(bm, rings[i], rings[i+1], 0)
# Nasen-Lippe: äußerer Nasenring -> innerer Ring (etwas zurück & kleiner)
lip_in = ering(bm, 2.9, 0.34, 0.34, 0.0)
for j in range(N):
    j2 = (j+1) % N
    bm.faces.new((rings[0][j2], rings[0][j], lip_in[j], lip_in[j2])).material_index = 0
# dunkler Einlauf-Schacht hinter der Lippe (rezessiert) + dunkle Stirnfläche (Verdichter)
duct = ering(bm, 2.35, 0.30, 0.30, 0.0)
bridge(bm, lip_in, duct, 1)
bm.faces.new(duct[::-1]).material_index = 1
# Heck: dunkle Düsen-Stirnfläche (das Triebwerk steckt seine Düse hier rein)
bm.faces.new(rings[-1]).material_index = 1
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("Fuselage"); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
fo = bpy.data.objects.new("Fuselage", me); bpy.context.scene.collection.objects.link(fo)
fo.data.materials.append(MB); fo.data.materials.append(MD)

# --- Bubble-Kanzel ---
bm = bmesh.new()
CAN = [(0.95,0.10,0.07,0.50),(0.45,0.20,0.20,0.57),(-0.05,0.22,0.24,0.59),(-0.60,0.18,0.19,0.55),(-1.15,0.07,0.07,0.49)]
cr = [ering(bm, *r) for r in CAN]
for i in range(len(cr)-1):
    bridge(bm, cr[i], cr[i+1], 0)
bm.faces.new(cr[0][::-1]).material_index = 1
bm.faces.new(cr[-1]).material_index = 1
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("Canopy"); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
co = bpy.data.objects.new("Canopy", me); bpy.context.scene.collection.objects.link(co)
co.data.materials.append(MG); co.data.materials.append(MF)

PATH = "/Users/konstantinkanzler/Downloads/aviasembly/models/f86_body.glb"
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=PATH, export_format='GLB', use_selection=True, export_yup=True, export_apply=True)
print("EXPORTED", PATH)
