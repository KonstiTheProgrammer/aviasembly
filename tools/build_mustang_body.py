## Baut das dedizierte P-51-Mustang-Rumpfmodell (Rumpf + Bubble-Kanzel + Bauch-Kühler
## + Anti-Glare-Panel) und exportiert es nach res://models/mustang_body.glb.
## Headless ausführen:
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_mustang_body.py
## Danach in Godot reimportieren:  Godot --headless --import --path .
## Achsen (glTF +Y up): Blender X->Godot X, Blender Z->Godot Y(oben), Blender +Y->Godot -Z (Nase vorne).
import bpy, bmesh, math
for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
for me in list(bpy.data.meshes): bpy.data.meshes.remove(me)
for mt in list(bpy.data.materials): bpy.data.materials.remove(mt)

def newmat(name, col, rough, metal, alpha=1.0):
    m = bpy.data.materials.new(name); m.name = name; m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        b.inputs["Alpha"].default_value = alpha; m.blend_method = 'BLEND'
    return m
MB = newmat("body", (0.80, 0.81, 0.84), 0.45, 0.5)        # lackierbares Aluminium
MG = newmat("glass", (0.03, 0.03, 0.035), 0.08, 0.1)       # Kanzelglas: glänzend SCHWARZ (Design-Sprache)
MF = newmat("frame", (0.13, 0.13, 0.14), 0.5, 0.55)        # Kanzelrahmen
MS = newmat("scoopin", (0.035, 0.035, 0.04), 0.7, 0.2)     # Kühler-Einlauf (dunkel)
MA = newmat("antiglare", (0.05, 0.05, 0.06), 0.6, 0.1)     # Sichtschutz/Anti-Glare: SCHWARZ

def loft(name, rings, mats, N=22, cap_front=True, cap_back=True, front_mat=0, back_mat=0):
    bm = bmesh.new(); rv = []
    for (y, hw, hh, cz) in rings:
        rv.append([bm.verts.new((hw*math.cos(math.tau*i/N), y, cz+hh*math.sin(math.tau*i/N))) for i in range(N)])
    for i in range(len(rv)-1):
        a = rv[i]; b = rv[i+1]
        for j in range(N):
            j2 = (j+1) % N; bm.faces.new((a[j], a[j2], b[j2], b[j])).material_index = 0
    if cap_front: bm.faces.new(rv[0][::-1]).material_index = front_mat
    if cap_back: bm.faces.new(rv[-1]).material_index = back_mat
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    for m in mats: ob.data.materials.append(m)
    return ob
def conv(rs): return [(y, hw, (top-bot)/2.0, (top+bot)/2.0) for (y, hw, top, bot) in rs]

# Rumpf: getrennte Deck- (top) und Kiel-Linie (bot). Tiefer Bauch vorn, Heck-Boom hebt sich.
FUSE = conv([(1.62, 0.40, 0.34, -0.36), (1.10, 0.45, 0.40, -0.46), (0.45, 0.47, 0.44, -0.52),
 (-0.10, 0.46, 0.46, -0.52), (-0.85, 0.42, 0.42, -0.46), (-1.65, 0.34, 0.40, -0.30),
 (-2.45, 0.24, 0.40, -0.10), (-3.10, 0.13, 0.42, 0.08), (-3.55, 0.05, 0.44, 0.24)])
loft("Fuselage", FUSE, [MB])
# Bubble-Kanzel (Teardrop, hinten ins Deck auslaufend)
CAN = [(0.58, 0.11, 0.09, 0.49), (0.20, 0.18, 0.20, 0.57), (-0.30, 0.19, 0.23, 0.60),
 (-0.80, 0.16, 0.18, 0.56), (-1.25, 0.10, 0.11, 0.50), (-1.72, 0.03, 0.04, 0.45)]
loft("Canopy", CAN, [MG, MF])
# Bauch-Kühlerschacht (Einlauf vorne dunkel)
SCOOP = [(-0.5, 0.20, 0.13, -0.50), (-1.05, 0.26, 0.18, -0.56), (-1.75, 0.25, 0.18, -0.55), (-2.35, 0.15, 0.11, -0.42)]
loft("Scoop", SCOOP, [MB, MS], front_mat=1)

# Anti-Glare-Panel (Sichtschutz): schwarzer Streifen auf dem Nasendeck vor der Scheibe (folgt der Wölbung)
def fuse_at(y):
    for i in range(len(FUSE)-1):
        y0 = FUSE[i][0]; y1 = FUSE[i+1][0]
        if y1 <= y <= y0:
            t = (y-y0)/(y1-y0)
            return [FUSE[i][k]*(1-t)+FUSE[i+1][k]*t for k in (1, 2, 3)]
    return [FUSE[0][1], FUSE[0][2], FUSE[0][3]]
bm = bmesh.new()
ys = [1.5, 1.15, 0.78, 0.55]; xs = [-0.14, -0.07, 0.0, 0.07, 0.14]
grid = []
for y in ys:
    hw, hh, cz = fuse_at(y); row = []
    for x in xs:
        r = max(0.0, 1.0-(x/hw)**2); z = cz+hh*math.sqrt(r)+0.006
        row.append(bm.verts.new((x, y, z)))
    grid.append(row)
for i in range(len(ys)-1):
    for j in range(len(xs)-1):
        bm.faces.new((grid[i][j], grid[i][j+1], grid[i+1][j+1], grid[i+1][j]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("AntiGlare"); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
ob = bpy.data.objects.new("AntiGlare", me); bpy.context.scene.collection.objects.link(ob); ob.data.materials.append(MA)

PATH = "/Users/konstantinkanzler/Downloads/aviasembly/models/mustang_body.glb"
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=PATH, export_format='GLB', use_selection=True, export_yup=True, export_apply=True)
print("EXPORTED", PATH)
