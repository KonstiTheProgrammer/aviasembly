## Baut ein JET-COCKPIT-SEGMENT: elliptischer Rumpf-Tubus (GLEICHER Querschnitt wie das
## generische Rumpfsegment + jet_nose: 0.65 x 0.55) mit schwarz verglaster Bubble-Kanzel
## obendrauf -> res://models/jet_cockpit.glb. So docken Nase, Rumpf & Cockpit NAHTLOS an.
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_jet_cockpit.py
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
MB = newmat("body", (0.80, 0.81, 0.84), 0.40, 0.55)
MG = newmat("glass", (0.03, 0.03, 0.035), 0.08, 0.30)   # schwarzes Glas (Design-Sprache)
MF = newmat("frame", (0.10, 0.10, 0.11), 0.5, 0.55)

N = 28
def ering(bm, y, rw, rh, cz=0.0):
    return [bm.verts.new((rw*math.cos(math.tau*i/N), y, cz+rh*math.sin(math.tau*i/N))) for i in range(N)]
def bridge(bm, a, b, mi):
    for j in range(N):
        j2 = (j+1) % N; bm.faces.new((a[j], a[j2], b[j2], b[j])).material_index = mi

# --- Rumpf-Tubus, elliptisch 0.65 x 0.55 (deckungsgleich mit fuselage/jet_nose) ---
bm = bmesh.new()
TUBE = [(1.0,0.65,0.55),(0.35,0.66,0.555),(-0.4,0.66,0.555),(-1.0,0.65,0.55)]
rings = [ering(bm, *r) for r in TUBE]
for i in range(len(rings)-1):
    bridge(bm, rings[i], rings[i+1], 0)
bm.faces.new(rings[0][::-1]).material_index = 0    # Enden gedeckelt (Rumpf deckt sie eh)
bm.faces.new(rings[-1]).material_index = 0
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("Body"); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
bo = bpy.data.objects.new("Body", me); bpy.context.scene.collection.objects.link(bo)
bo.data.materials.append(MB)

# --- Bubble-Kanzel (schwarzes Glas), leicht nach VORNE (+Y) versetzt, in den Rumpf eingelassen ---
bm = bmesh.new()
CAN = [(0.92,0.05,0.04,0.55),(0.60,0.22,0.20,0.66),(0.20,0.30,0.27,0.73),(-0.20,0.25,0.22,0.68),(-0.58,0.10,0.08,0.57)]
cr = [ering(bm, *r) for r in CAN]
for i in range(len(cr)-1):
    bridge(bm, cr[i], cr[i+1], 0)
bm.faces.new(cr[0][::-1]).material_index = 1       # Front-/Heckscheibe als Rahmen
bm.faces.new(cr[-1]).material_index = 1
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("Canopy"); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
co = bpy.data.objects.new("Canopy", me); bpy.context.scene.collection.objects.link(co)
co.data.materials.append(MG); co.data.materials.append(MF)

PATH = "/Users/konstantinkanzler/Downloads/aviasembly/models/jet_cockpit.glb"
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=PATH, export_format='GLB', use_selection=True, export_yup=True, export_apply=True)
print("EXPORTED", PATH)
