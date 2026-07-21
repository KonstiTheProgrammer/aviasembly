# Baut die Blender-MODELLBIBLIOTHEK: eine .blend pro Teil-Kategorie, alle glbs der
# Kategorie nebeneinander im Raster, je Teil eine eigene Collection + Text-Label.
#
#   blender_lib/motoren.blend           alle Antriebe
#   blender_lib/fahrwerke.blend         alle Raeder (inkl. der drei animierten)
#   blender_lib/cockpits.blend          alle Kanzeln
#   blender_lib/ruempfe.blend           Rumpfsektionen/Nasen/Hecks/Tank
#   blender_lib/fluegel_leitwerk.blend  Fluegel + Leitwerke
#   blender_lib/waffen.blend            Kanonen/MGs/Raketen + Bombe
#
# Quelle sind die models/*.glb (die Wahrheit, aus der auch das Spiel laedt) -> die
# Bibliothek ist jederzeit regenerierbar und immer synchron zum Spiel.
# blender_lib/ traegt eine .gdignore, sonst wuerde Godot die .blends importieren.
#
# Usage:  blender --background --python tools/build_blender_lib.py
import bpy
import os
from mathutils import Vector

MODELS = "C:/Users/Konst/Projects/aviasembly/models/"
OUT = "C:/Users/Konst/Projects/aviasembly/blender_lib/"

LIB = {
    "motoren": ["prop_engine", "prop_engine_big", "prop_engine_nose", "spitfire_engine",
                "reto_engine", "engine_radial", "jet_engine", "jet_square", "thruster",
                "f14_nacelle", "f22_engine"],
    "fahrwerke": ["wheel", "wheel_light", "wheel_heavy", "wheel_jet", "wheel_retract",
                  "wheel_biplane_spoke", "wheel_biplane_disc", "wheel_spitfire"],
    "cockpits": ["cockpit", "cockpit_bubble", "cockpit_jet", "cockpit_frame",
                 "cockpit_tandem", "cockpit_radial", "spitfire_cockpit", "mig21_cockpit"],
    "ruempfe": ["nose", "tailcone", "fueltank", "jet_nose", "jet_nose_point", "red_star",
                "mustang_body", "me262_body", "mig15_body", "f86_body",
                "f22_body", "f22_head",
                "mig21_nose", "mig21_front", "mig21_body", "mig21_tail", "mig21_rear",
                "f4_nose", "f4_front", "f4_intake", "f14_front"],
    "fluegel_leitwerk": ["mig21_wing", "spitfire_wing", "mig21_stab", "mig21_fin"],
    "waffen": ["cannon", "autocannon", "heavy_cannon", "mg", "wing_gun", "minigun",
               "rocket", "rocket_pod", "missile", "missile_heavy", "bomb"],
}

PER_ROW = 6
GAP = 0.9

os.makedirs(OUT, exist_ok=True)
gdi = os.path.join(OUT, ".gdignore")
if not os.path.exists(gdi):
    open(gdi, "w").close()          # Godot: Ordner komplett ignorieren


def world_bounds(objs):
    lo = [1e9] * 3
    hi = [-1e9] * 3
    for o in objs:
        if o.type != 'MESH':
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


for libname, ids in LIB.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.name = libname
    x_cursor = 0.0
    row_z = 0.0
    row_depth = 0.0
    n_ok = 0
    for idx, pid in enumerate(ids):
        path = MODELS + pid + ".glb"
        if not os.path.exists(path):
            print("  FEHLT:", pid)
            continue
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = [o for o in bpy.data.objects if o not in before]
        # eigene Collection pro Teil
        col = bpy.data.collections.new(pid)
        sc.collection.children.link(col)
        for o in new:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            col.objects.link(o)
        # Raster-Platzierung (nur Top-Level verschieben, Kinder folgen)
        lo, hi = world_bounds(new)
        w = max(hi[0] - lo[0], 0.6)
        d = max(hi[1] - lo[1], 0.6)
        if idx % PER_ROW == 0 and idx > 0:
            row_z -= row_depth + 2.0
            x_cursor = 0.0
            row_depth = 0.0
        shift_x = x_cursor - lo[0]
        shift_y = row_z - lo[1]
        for o in new:
            if o.parent is None:
                o.location.x += shift_x
                o.location.y += shift_y
                o.location.z += -lo[2] if lo[2] < -1e8 else 0.0
        # Text-Label vor das Modell
        txt = bpy.data.curves.new(pid, type='FONT')
        txt.body = pid
        txt.size = 0.28
        to = bpy.data.objects.new(pid + "_label", txt)
        to.location = (x_cursor + w * 0.5 - 0.4, row_z - 0.55, 0.0)
        col.objects.link(to)
        x_cursor += w + GAP
        row_depth = max(row_depth, d)
        n_ok += 1
    out = OUT + libname + ".blend"
    bpy.ops.wm.save_as_mainfile(filepath=out)
    print(f"GESPEICHERT {libname}.blend: {n_ok}/{len(ids)} Modelle, "
          f"{len(bpy.data.objects)} Objekte, {len(bpy.data.materials)} Materialien")
print("FERTIG")
