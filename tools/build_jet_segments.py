## Baut den modularen JET-RUMPF als SEAMLESS ineinandersteckende Segmente:
##   jet_nose  (Lufteinlauf vorn + Steckzapfen hinten)
##   jet_body  (Buchse vorn + Steckzapfen hinten)
##   jet_cockpit (Buchse vorn + schwarze Bubble-Kanzel + Steckzapfen hinten)
##   jet_tail  (Buchse vorn + Heckkonus auf die Düse zulaufend)
## Alle Segmente teilen denselben Außen-Querschnitt (0.65 x 0.55). Jeder Steckzapfen ist
## leicht eingezogen (0.60 x 0.51) -> steckt UNSICHTBAR in der vollen Buchse des Nachbarn
## (keine deckungsgleichen Wände -> KEIN Z-Fighting / keine Zacken mehr). Vorn sitzt eine
## hauchdünne Lippe (0.655), die den Stoß als saubere Panel-Fuge überdeckt.
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_jet_segments.py
## Achsen (glTF +Y up): Blender X->Godot X, Z->Godot Y(oben), +Y->Godot -Z (Nase vorne).
import bpy, bmesh, math
MODELS = "/Users/konstantinkanzler/Downloads/aviasembly/models/"
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
MG = newmat("glass", (0.03, 0.03, 0.035), 0.08, 0.30)
MF = newmat("frame", (0.10, 0.10, 0.11), 0.5, 0.55)
MD = newmat("ductdark", (0.02, 0.02, 0.025), 1.0, 0.0)
MS = newmat("ductsplit", (0.20, 0.20, 0.22), 0.75, 0.15)
MD.use_backface_culling = False; MS.use_backface_culling = False

N = 30
def ering(bm, y, rw, rh, cz=0.0):
    return [bm.verts.new((rw*math.cos(math.tau*i/N), y, cz+rh*math.sin(math.tau*i/N))) for i in range(N)]
def bridge(bm, a, b, mi):
    for j in range(N):
        j2 = (j+1) % N; bm.faces.new((a[j], a[j2], b[j2], b[j])).material_index = mi
def loft(bm, prof, mi=0):
    rings = [ering(bm, *p) for p in prof]
    for i in range(len(rings)-1):
        bridge(bm, rings[i], rings[i+1], mi)
    return rings
def finish(bm, name, mats):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    for m in mats: ob.data.materials.append(m)
    return ob
def export(objnames, path):
    bpy.ops.object.select_all(action='DESELECT')
    for nm in objnames: bpy.data.objects[nm].select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
        export_yup=True, export_apply=True)
    print("EXPORTED", path)

# Gemeinsame Endstücke (Blender Y: +Y=vorne, -Y=hinten)
def lip_front(yf): return [(yf, 0.655, 0.555), (yf-0.05, 0.65, 0.55)]
def spigot_rear(yr): return [(yr, 0.65, 0.55), (yr-0.03, 0.60, 0.51), (yr-0.26, 0.60, 0.51)]

# ---------------- jet_nose : Lufteinlauf vorn + Steckzapfen hinten ----------------
bm = bmesh.new()
prof = [(0.95, 0.63, 0.53), (0.45, 0.655, 0.555), (-0.30, 0.66, 0.56)] + spigot_rear(-0.85)
rings = loft(bm, prof, 0)
# Einlauf: dünne Lippe -> tiefer matt-schwarzer Schacht -> Teiler
lip1 = ering(bm, 0.985, 0.615, 0.515); lip2 = ering(bm, 0.99, 0.59, 0.49); lip3 = ering(bm, 0.975, 0.58, 0.48)
bridge(bm, rings[0], lip1, 0); bridge(bm, lip1, lip2, 0); bridge(bm, lip2, lip3, 0)
d1 = ering(bm, 0.7, 0.57, 0.47); d2 = ering(bm, 0.05, 0.52, 0.43); d3 = ering(bm, -0.55, 0.46, 0.38)
bridge(bm, lip3, d1, 1); bridge(bm, d1, d2, 1); bridge(bm, d2, d3, 1)
bm.faces.new(d3[::-1]).material_index = 1
sv = [bm.verts.new(p) for p in [
    (0.02, 0.975, 0.46), (0.02, 0.975, -0.46), (0.02, -0.45, -0.36), (0.02, -0.45, 0.36),
    (-0.02, 0.975, 0.46), (-0.02, 0.975, -0.46), (-0.02, -0.45, -0.36), (-0.02, -0.45, 0.36)]]
for f in [(0,1,2,3),(7,6,5,4),(4,5,1,0),(5,6,2,1),(6,7,3,2),(7,4,0,3)]:
    bm.faces.new([sv[k] for k in f]).material_index = 2
finish(bm, "Nose", [MB, MD, MS])
export(["Nose"], MODELS + "jet_nose.glb")

# ---------------- jet_body : Buchse vorn + Steckzapfen hinten ----------------
bm = bmesh.new()
prof = lip_front(0.72) + [(0.0, 0.66, 0.56)] + spigot_rear(-0.66)
loft(bm, prof, 0)
finish(bm, "Body", [MB])
export(["Body"], MODELS + "jet_body.glb")

# ---------------- jet_cockpit : Buchse vorn + Bubble-Kanzel + Steckzapfen hinten ----------------
bm = bmesh.new()
prof = lip_front(0.92) + [(0.0, 0.66, 0.56)] + spigot_rear(-0.86)
loft(bm, prof, 0)
finish(bm, "CkBody", [MB])
bm = bmesh.new()
CAN = [(0.95,0.05,0.04,0.55),(0.62,0.22,0.20,0.66),(0.20,0.30,0.27,0.73),(-0.20,0.25,0.22,0.68),(-0.60,0.10,0.08,0.57)]
cr = loft(bm, CAN, 0)
bm.faces.new(cr[0][::-1]).material_index = 1
bm.faces.new(cr[-1]).material_index = 1
finish(bm, "Canopy", [MG, MF])
export(["CkBody", "Canopy"], MODELS + "jet_cockpit.glb")

# ---------------- jet_tail : Buchse vorn + Heckkonus auf die Düse ----------------
bm = bmesh.new()
prof = lip_front(0.85) + [(0.30, 0.65, 0.55), (-0.20, 0.62, 0.53), (-0.70, 0.50, 0.43), (-1.05, 0.38, 0.33)]
rings = loft(bm, prof, 0)
finish(bm, "Tail", [MB])
export(["Tail"], MODELS + "jet_tail.glb")
print("DONE")
