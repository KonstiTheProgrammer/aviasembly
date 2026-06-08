## Baut ein dediziertes JET-NASENTEIL (runder Lufteinlauf mit Lippe, tiefem Schacht
## und senkrechtem Teiler) -> res://models/jet_nose.glb. Querschnitt = generisches
## Rumpfsegment (1.3 x 1.1 ellipt.), damit es bündig an "fuselage" andockt.
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
MB = newmat("body", (0.80, 0.81, 0.84), 0.40, 0.55)
MD = newmat("ductdark", (0.02, 0.02, 0.025), 1.0, 0.0)   # Schacht (Godot erzwingt zusätzlich beidseitig)
MS = newmat("ductsplit", (0.20, 0.20, 0.22), 0.75, 0.15)
MD.use_backface_culling = False; MS.use_backface_culling = False

N = 28
def ering(bm, y, rw, rh):
    return [bm.verts.new((rw*math.cos(math.tau*i/N), y, rh*math.sin(math.tau*i/N))) for i in range(N)]
def bridge(bm, a, b, mi):
    for j in range(N):
        j2 = (j+1) % N; bm.faces.new((a[j], a[j2], b[j2], b[j])).material_index = mi

# Kurzer elliptischer Nasen-Tubus (Nase +Y -> Andock-Querschnitt -Y), ~konstant 0.65x0.55
TUBE = [(0.95,0.63,0.53),(0.4,0.655,0.555),(-0.3,0.66,0.56),(-1.0,0.65,0.55)]
bm = bmesh.new()
rings = [ering(bm, *r) for r in TUBE]
for i in range(len(rings)-1):
    bridge(bm, rings[i], rings[i+1], 0)
bm.faces.new(rings[-1]).material_index = 0   # Andock-Ende geschlossen (Rumpf deckt es)
# DÜNNE Lippe -> große Öffnung
lip1 = ering(bm, 0.985, 0.615, 0.515); lip2 = ering(bm, 0.99, 0.59, 0.49); lip3 = ering(bm, 0.975, 0.58, 0.48)
bridge(bm, rings[0], lip1, 0); bridge(bm, lip1, lip2, 0); bridge(bm, lip2, lip3, 0)
# Tiefer, matt-schwarzer Schacht
d1 = ering(bm, 0.7, 0.57, 0.47); d2 = ering(bm, 0.05, 0.52, 0.43); d3 = ering(bm, -0.55, 0.46, 0.38)
bridge(bm, lip3, d1, 1); bridge(bm, d1, d2, 1); bridge(bm, d2, d3, 1)
bm.faces.new(d3[::-1]).material_index = 1
# Senkrechter Teiler über die volle Einlaufhöhe
sv = [bm.verts.new(p) for p in [
    (0.02, 0.975, 0.46), (0.02, 0.975, -0.46), (0.02, -0.45, -0.36), (0.02, -0.45, 0.36),
    (-0.02, 0.975, 0.46), (-0.02, 0.975, -0.46), (-0.02, -0.45, -0.36), (-0.02, -0.45, 0.36)]]
for f in [(0,1,2,3),(7,6,5,4),(4,5,1,0),(5,6,2,1),(6,7,3,2),(7,4,0,3)]:
    bm.faces.new([sv[k] for k in f]).material_index = 2
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("Nose"); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
ob = bpy.data.objects.new("Nose", me); bpy.context.scene.collection.objects.link(ob)
ob.data.materials.append(MB); ob.data.materials.append(MD); ob.data.materials.append(MS)

PATH = "/Users/konstantinkanzler/Downloads/aviasembly/models/jet_nose.glb"
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=PATH, export_format='GLB', use_selection=True, export_yup=True, export_apply=True)
print("EXPORTED", PATH)
