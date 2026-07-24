# Landmarks-Gebaeude -> blender_lib/gebaeude.blend
# Quelle: blender_lib/_gebaeude_export.glb (erzeugt von tools/_export_buildings.gd —
# exportiert die ECHTE prozedurale Godot-Geometrie, daher immer synchron zum Spiel).
# Je Bauwerk eine Collection: Stadt / Bergdorf / Leuchtturm / Windrad / Bruecke / Haus_A..F.
# Usage: [Godot-Export laufen lassen, dann] blender --background --python tools/build_gebaeude_blend.py
import bpy
import os

SRC = "C:/Users/Konst/Projects/aviasembly/blender_lib/_gebaeude_export.glb"
OUT = "C:/Users/Konst/Projects/aviasembly/blender_lib/gebaeude.blend"
PREVIEW = os.environ.get("GEBAEUDE_PREVIEW", "")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
scn = bpy.context.scene

# Godot exportiert einen namenlosen Wurzelknoten -> dessen Kinder sind die Gruppen.
roots = [o for o in scn.collection.objects if o.parent is None]
groups = roots
if len(roots) == 1 and roots[0].type == 'EMPTY' and roots[0].children:
    groups = list(roots[0].children)

for g in sorted(groups, key=lambda o: o.name):
    col = bpy.data.collections.new(g.name)
    scn.collection.children.link(col)
    stack = [g]
    while stack:
        o = stack.pop()
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
        stack.extend(o.children)

# Viewport-/Workbench-Farben aus den glTF-Materialien uebernehmen (sonst alles grau)
for m in bpy.data.materials:
    if m.use_nodes:
        b = m.node_tree.nodes.get("Principled BSDF")
        if b:
            m.diffuse_color = b.inputs["Base Color"].default_value[:]

bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("SAVED", OUT)
print("COLLECTIONS:", sorted(c.name for c in bpy.data.collections))
print("OBJEKTE:", len([o for o in bpy.data.objects if o.type == 'MESH']))

if PREVIEW:
    # Workbench-Uebersichtsrender zur Sichtpruefung
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scn.collection.objects.link(cam)
    scn.camera = cam
    from mathutils import Vector
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in bpy.data.objects:
        if o.type != 'MESH':
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    ctr = (lo + hi) * 0.5
    ext = max((hi - lo).length, 1.0)
    cam.location = ctr + Vector((-0.45, -1.0, 0.5)) * ext * 0.62
    d = ctr - cam.location
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    cam.data.clip_end = ext * 4.0
    cam.data.lens = 32
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'MATERIAL'
    scn.render.resolution_x = 1920
    scn.render.resolution_y = 800
    scn.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", PREVIEW)
