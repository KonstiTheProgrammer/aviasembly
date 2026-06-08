## Baut den dedizierten Me-262-Rumpf (dreieckiger "Hai"-Querschnitt, spitze Nase,
## flache Rahmen-Kanzel) -> res://models/me262_body.glb.
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_me262_body.py
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
MB = newmat("body", (0.64, 0.67, 0.69), 0.42, 0.45)        # lackierbar (RLM-Grau)
MG = newmat("glass", (0.03, 0.03, 0.035), 0.08, 0.1)       # Kanzelglas: glänzend schwarz
MF = newmat("frame", (0.12, 0.12, 0.13), 0.5, 0.55)        # Kanzelrahmen

# Dreieckiger Querschnitt (Einheitsform, X-Z): runder Rücken, breite Schultern, Kiel unten.
TRI = [(0.0,1.0),(0.5,0.85),(0.85,0.45),(1.0,0.0),(0.7,-0.55),(0.32,-0.85),
 (0.0,-1.0),(-0.32,-0.85),(-0.7,-0.55),(-1.0,0.0),(-0.85,0.45),(-0.5,0.85)]
ELL = [(math.cos(math.tau*i/16), math.sin(math.tau*i/16)) for i in range(16)]

def loft(name, SEC, rings, mats, cap_front=True, cap_back=True, front_mat=0, back_mat=0):
    bm = bmesh.new(); rv = []
    for (y, hw, hh, cz) in rings:
        rv.append([bm.verts.new((sx*hw, y, cz+sz*hh)) for (sx, sz) in SEC])
    M = len(SEC)
    for i in range(len(rv)-1):
        a = rv[i]; b = rv[i+1]
        for j in range(M):
            j2 = (j+1) % M; bm.faces.new((a[j], a[j2], b[j2], b[j])).material_index = 0
    if cap_front: bm.faces.new(rv[0][::-1]).material_index = front_mat
    if cap_back: bm.faces.new(rv[-1]).material_index = back_mat
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    for m in mats: ob.data.materials.append(m)
    return ob

# Rumpf: spitze Nase (+Y) -> Heck (-Y), dreieckiger Querschnitt
FUSE = [(2.50,0.03,0.03,0.0),(2.10,0.13,0.15,-0.02),(1.50,0.26,0.32,-0.02),(0.80,0.36,0.46,-0.02),
 (0.0,0.39,0.50,0.0),(-0.90,0.35,0.46,0.03),(-1.90,0.26,0.36,0.08),(-2.90,0.15,0.24,0.14),(-3.70,0.055,0.13,0.21)]
loft("Fuselage", TRI, FUSE, [MB])
# Flache Rahmen-Kanzel (schwarzes Glas), weit vorn
CAN = [(1.62,0.09,0.06,0.34),(1.18,0.17,0.16,0.42),(0.68,0.18,0.19,0.46),(0.18,0.14,0.15,0.44),(-0.22,0.05,0.06,0.40)]
loft("Canopy", ELL, CAN, [MG, MF])

PATH = "/Users/konstantinkanzler/Downloads/aviasembly/models/me262_body.glb"
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=PATH, export_format='GLB', use_selection=True, export_yup=True, export_apply=True)
print("EXPORTED", PATH)
