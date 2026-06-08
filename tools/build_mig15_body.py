## Baut den Mikojan-Gurewitsch MiG-15-Rumpf (gedrungener Tonnen-Rumpf, runder Nasen-
## Lufteinlauf mit senkrechtem Teiler, Bubble-Kanzel) -> res://models/mig15_body.glb.
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_mig15_body.py
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
MB = newmat("body", (0.80, 0.81, 0.84), 0.40, 0.55)
MG = newmat("glass", (0.03, 0.03, 0.035), 0.08, 0.1)
MF = newmat("frame", (0.12, 0.12, 0.13), 0.5, 0.55)
MD = newmat("ductdark", (0.025, 0.025, 0.03), 0.6, 0.3)

N = 26
def ering(bm, y, rw, rh, cz):
    return [bm.verts.new((rw*math.cos(math.tau*i/N), y, cz+rh*math.sin(math.tau*i/N))) for i in range(N)]
def bridge(bm, a, b, mi):
    for j in range(N):
        j2 = (j+1) % N; bm.faces.new((a[j], a[j2], b[j2], b[j])).material_index = mi

# --- Gedrungener Tonnen-Rumpf, runder Querschnitt, vorne Einlauf, hinten Düse ---
FUSE = [(2.55,0.44,0.44,0.0),(2.0,0.50,0.50,0.0),(1.0,0.55,0.55,0.0),(0.15,0.56,0.56,0.02),
 (-0.75,0.53,0.53,0.03),(-1.7,0.44,0.45,0.06),(-2.5,0.35,0.36,0.09),(-3.0,0.30,0.31,0.11),(-3.35,0.27,0.28,0.12)]
bm = bmesh.new()
rings = [ering(bm, *r) for r in FUSE]
for i in range(len(rings)-1):
    bridge(bm, rings[i], rings[i+1], 0)
# Gerundete Einlauf-Lippe: Nasenring nach VORNE und nach INNEN gewölbt (echte Intake-Lippe)
lip1 = ering(bm, 2.63, 0.425, 0.425, 0.0)
lip2 = ering(bm, 2.65, 0.385, 0.385, 0.0)
lip3 = ering(bm, 2.60, 0.350, 0.350, 0.0)
bridge(bm, rings[0], lip1, 0)
bridge(bm, lip1, lip2, 0)
bridge(bm, lip2, lip3, 0)
# Tiefer, sehr dunkler Einlaufschacht (kein sichtbarer Boden -> wirkt wie ein echter Kanal)
d1 = ering(bm, 2.30, 0.345, 0.345, 0.0)
d2 = ering(bm, 1.45, 0.325, 0.325, 0.0)
d3 = ering(bm, 0.55, 0.300, 0.300, 0.0)
bridge(bm, lip3, d1, 1); bridge(bm, d1, d2, 1); bridge(bm, d2, d3, 1)
bm.faces.new(d3[::-1]).material_index = 1
bm.faces.new(rings[-1]).material_index = 1   # Heck: dunkle Düsen-Stirnfläche
# Senkrechter Einlauf-Teiler (durchgehende Wand, MiG-Merkmal), mit angeschrägter Vorderkante
sv = [bm.verts.new(p) for p in [
    (0.017, 2.60, 0.33), (0.017, 2.60, -0.33), (0.017, 0.85, -0.29), (0.017, 0.85, 0.29),
    (-0.017, 2.60, 0.33), (-0.017, 2.60, -0.33), (-0.017, 0.85, -0.29), (-0.017, 0.85, 0.29)]]
for f in [(0,1,2,3),(7,6,5,4),(4,5,1,0),(5,6,2,1),(6,7,3,2),(7,4,0,3)]:
    bm.faces.new([sv[k] for k in f]).material_index = 0
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("Fuselage"); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
fo = bpy.data.objects.new("Fuselage", me); bpy.context.scene.collection.objects.link(fo)
fo.data.materials.append(MB); fo.data.materials.append(MD)

# --- Bubble-Kanzel (sitzt hoch, weiter vorn) ---
bm = bmesh.new()
CAN = [(1.05,0.10,0.07,0.55),(0.55,0.20,0.19,0.62),(0.0,0.22,0.23,0.64),(-0.55,0.18,0.19,0.60),(-1.1,0.07,0.07,0.53)]
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

PATH = "/Users/konstantinkanzler/Downloads/aviasembly/models/mig15_body.glb"
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=PATH, export_format='GLB', use_selection=True, export_yup=True, export_apply=True)
print("EXPORTED", PATH)
