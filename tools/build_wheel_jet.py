## Baut ein modernes Kampfjet-Einziehfahrwerk (schlanker Öldämpfer-Beinholm, kleines
## Low-Profile-Rad, Bremsscheibe, Drehmomentschere) -> res://models/wheel_jet.glb.
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_wheel_jet.py
## Struktur: EIN Objekt "Leg" mit Ursprung am oberen Drehpunkt (0,0,0); Geometrie hängt
## nach unten (Rad-Aufstandspunkt ~Godot y=-1.0). Das "Leg"-Node klappt beim Einfahren hoch.
## Achsen (glTF +Y up): Blender X->Godot X (Radachse), Blender Z->Godot Y(oben), +Y->Godot -Z(vorne).
import bpy, math
from math import radians
for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
for m in list(bpy.data.meshes): bpy.data.meshes.remove(m)
for mt in list(bpy.data.materials): bpy.data.materials.remove(mt)

def mat(name, col, rough, metal):
    m = bpy.data.materials.new(name); m.name = name; m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
    return m
M_rubber = mat("rubber", (0.055, 0.055, 0.065), 0.85, 0.0)   # Reifen
M_rim    = mat("rim",    (0.40, 0.42, 0.47), 0.30, 0.85)      # Felge
M_hub    = mat("hub",    (0.17, 0.17, 0.19), 0.45, 0.7)       # Nabe
M_steel  = mat("steel",  (0.52, 0.54, 0.58), 0.25, 0.9)       # Bremsscheibe
M_gun    = mat("gunmetal",(0.17, 0.18, 0.21), 0.40, 0.7)      # Beinholm/Schere
M_piston = mat("piston", (0.62, 0.64, 0.68), 0.15, 0.95)      # Öldämpfer-Kolben (poliert; wird in-game gedämpft)

parts = []
def cyl(r, depth, loc, rot=(0, 0, 0), material=None, v=28):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=v)
    o = bpy.context.active_object
    if material: o.data.materials.append(material)
    parts.append(o); return o
def box(scale, loc, material):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    o = bpy.context.active_object; o.scale = scale
    o.data.materials.append(material); parts.append(o); return o

XR = (0, radians(90), 0)   # Zylinder von Z- auf X-Achse drehen (Radachse = X)
# Öldämpfer-Beinholm (oben am Drehpunkt 0, hängt nach -Z)
cyl(0.060, 0.46, (0, 0, -0.21), material=M_gun)        # oberes Bein
cyl(0.044, 0.42, (0, 0, -0.54), material=M_piston)     # polierter Kolben
# Achse + Gabel
cyl(0.034, 0.22, (0, 0, -0.80), XR, material=M_gun)
# Rad: Reifen + Felge + Nabe + Bremsscheibe (Achse entlang X)
cyl(0.250, 0.150, (0, 0, -0.80), XR, material=M_rubber, v=40)   # Reifen (Low-Profile)
cyl(0.150, 0.165, (0, 0, -0.80), XR, material=M_rim,    v=40)   # Felge
cyl(0.052, 0.185, (0, 0, -0.80), XR, material=M_hub,    v=22)   # Nabe
cyl(0.175, 0.022, (0.085, 0, -0.80), XR, material=M_steel, v=36)  # Bremsscheibe (Innenseite)
# Drehmomentschere vorn am Holm (+Y)
box((0.012, 0.022, 0.135), (0, 0.072, -0.40), M_gun)
box((0.012, 0.022, 0.125), (0, 0.072, -0.585), M_gun)

# Zu EINEM Objekt "Leg" verschmelzen, Transforms backen, Ursprung am Drehpunkt (0,0,0)
bpy.ops.object.select_all(action='DESELECT')
for o in parts: o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
leg = bpy.context.active_object; leg.name = "Leg"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.shade_smooth()

PATH = "/Users/konstantinkanzler/Downloads/aviasembly/models/wheel_jet.glb"
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=PATH, export_format='GLB', use_selection=True, export_yup=True, export_apply=True)
print("EXPORTED", PATH)
