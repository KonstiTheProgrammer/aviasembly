## Baut einen flachen roten Sowjet-Stern (5-zackig) als Markierung -> res://models/red_star.glb.
## Normale = +X (liegt in der Godot-YZ-Ebene), zeigt also per Default nach rechts -> passt
## direkt auf die rechte Rumpfseite; Symmetrie spiegelt nach links.
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_red_star.py
## Achsen (glTF +Y up): Blender X->Godot X, Z->Godot Y(oben), +Y->Godot -Z.
import bpy, bmesh, math
for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
for me in list(bpy.data.meshes): bpy.data.meshes.remove(me)
for mt in list(bpy.data.materials): bpy.data.materials.remove(mt)

m = bpy.data.materials.new("starred"); m.name = "starred"; m.use_nodes = True
b = m.node_tree.nodes.get("Principled BSDF")
b.inputs["Base Color"].default_value = (0.66, 0.045, 0.05, 1.0)
b.inputs["Roughness"].default_value = 0.45; b.inputs["Metallic"].default_value = 0.1
# leichte Eigenleuchtkraft -> bleibt unter Filmic/hellem Ambient ein sattes Rot (kein Rosa)
b.inputs["Emission Color"].default_value = (0.42, 0.02, 0.02, 1.0)
b.inputs["Emission Strength"].default_value = 0.55

OUT = 0.30; INN = 0.125; TH = 0.02
bm = bmesh.new()
# Rand: 10 Punkte (außen/innen), in der YZ-Ebene; "oben" = +Z (Blender) -> Godot +Y.
top = []; bot = []
for k in range(10):
    a = math.radians(90 + 36 * k)
    r = OUT if k % 2 == 0 else INN
    y = r * math.cos(a); z = r * math.sin(a)
    top.append(bm.verts.new((TH, y, z)))
    bot.append(bm.verts.new((-TH, y, z)))
ct = bm.verts.new((TH, 0, 0)); cb = bm.verts.new((-TH, 0, 0))
for k in range(10):
    k2 = (k + 1) % 10
    bm.faces.new((ct, top[k], top[k2]))           # Vorderseite (+X)
    bm.faces.new((cb, bot[k2], bot[k]))           # Rückseite (-X)
    bm.faces.new((top[k], bot[k], bot[k2], top[k2]))  # Kante
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("Star"); bm.to_mesh(me); bm.free()
ob = bpy.data.objects.new("Star", me); bpy.context.scene.collection.objects.link(ob)
ob.data.materials.append(m)

PATH = "/Users/konstantinkanzler/Downloads/aviasembly/models/red_star.glb"
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=PATH, export_format='GLB', use_selection=True, export_yup=True, export_apply=True)
print("EXPORTED", PATH)
