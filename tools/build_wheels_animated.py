# tools/wheels_animated.blend -> models/wheel_biplane_spoke|wheel_biplane_disc|wheel_spitfire.glb
#
# Die drei animierten Fahrwerks-Raeder (Szene "Wheels", via Blender-MCP designt):
#   Root_*  = Aufhaengepunkt (im Blend zur Uebersicht bei x=-2/0/+2 GEPARKT -> hier nullen!)
#   Pivot_* = animiert (Action retract_*, 30f @30fps, Overshoot-Einrasten)
#   *Gear/*Wheel = Meshes (flat; NUR gear_rubber-Polys smooth)
# Export je Rad mit Animation "retract" (Actions sind global -> vor jedem Export umbenennen).
import bpy

SRC = "C:/Users/Konst/Projects/aviasembly/tools/wheels_animated.blend"
OUT = "C:/Users/Konst/Projects/aviasembly/models/"

bpy.ops.wm.open_mainfile(filepath=SRC)
sc = bpy.data.scenes["Wheels"]
bpy.context.window.scene = sc
sc.frame_set(1)                      # Ruhepose = ausgefahren

SETS = [
    ("Root_spoke", "retract_spoke", "wheel_biplane_spoke.glb"),
    ("Root_disc",  "retract_disc",  "wheel_biplane_disc.glb"),
    ("Root_spit",  "retract_spit",  "wheel_spitfire.glb"),
]


def tree(o):
    yield o
    for c in o.children:
        yield from tree(c)


for root_n, act_n, fname in SETS:
    root = bpy.data.objects[root_n]
    root.location = (0, 0, 0)        # Ursprung = Aufhaengepunkt, kein Layout-Versatz
    act = bpy.data.actions.get(act_n)
    if act is None:
        raise RuntimeError(f"Action {act_n} fehlt")
    act.name = "retract"
    # Rad-Mesh -> "Wheel": AircraftBody dreht diesen Node beim Rollen um seine lokale
    # X-Achse (Radachse). Objekt-Origin liegt im Radzentrum -> dreht um die Achse.
    wheel_obj = next(o for o in tree(root) if o.type == 'MESH' and o.name.endswith("Wheel"))
    wname = wheel_obj.name
    wheel_obj.name = "Wheel"
    for o in sc.collection.all_objects:
        o.select_set(False)
    for o in tree(root):
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT + fname, export_format='GLB', use_selection=True,
                              export_animations=True, export_yup=True)
    act.name = act_n
    wheel_obj.name = wname
    print("EXPORTED", fname)
print("FERTIG")
