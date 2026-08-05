## Studio-Renders des F-22-Fahrwerks zur Sichtpruefung (baut das Teil frisch auf).
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/_f22_gear_render.py -- <out_prefix>
import bpy, sys, math, os
from math import radians
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
exec(compile(open(os.path.join(HERE, "build_wheel_f22.py")).read(),
             "build_wheel_f22.py", "exec"), {"__name__": "build", "__file__": os.path.join(HERE, "build_wheel_f22.py")})

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREFIX = argv[0] if argv else "/tmp/f22_gear"
# Schattierung: "modell" = wie gebaut (nur Gummi/Kolben glatt, Struktur kantig),
#               "smooth" = ALLES glatt, "auto" = winkelabhaengig (harte Kanten bleiben hart).
SHADE = argv[1] if len(argv) > 1 else "modell"

MESHES = ["LegMesh", "SlideMesh", "Wheel", "ScissorU", "ScissorL", "Door"]
if SHADE != "modell":
    for nm in MESHES:
        o = bpy.data.objects[nm]
        bpy.ops.object.select_all(action='DESELECT')
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        if SHADE == "smooth":
            bpy.ops.object.shade_smooth()
        elif SHADE == "auto":
            bpy.ops.object.shade_auto_smooth(angle=radians(35))
        elif SHADE == "flat":
            bpy.ops.object.shade_flat()
    print("SCHATTIERUNG:", SHADE)

sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x, sc.render.resolution_y = 900, 1100
sc.render.resolution_percentage = 100
sc.render.film_transparent = False
sc.eevee.taa_render_samples = 64
# Standard statt AgX: die Materialfarben sollen ungefiltert beurteilbar sein.
sc.view_settings.view_transform = 'Standard'
sc.view_settings.look = 'None'
# Mitteldunkler Hintergrund — sonst spiegeln die Metallic-Materialien (0.7..0.96)
# nur die helle Welt und alles sieht identisch hellgrau aus.
sc.world = bpy.data.worlds.new("W")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.20, 0.22, 0.26, 1)
sc.world.node_tree.nodes["Background"].inputs[1].default_value = 1.0

# Studio-Licht
def lamp(name, loc, energy, size=4.0):
    d = bpy.data.lights.new(name, 'AREA'); d.energy = energy; d.size = size
    o = bpy.data.objects.new(name, d); sc.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector((0, 0, -0.55)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return o
lamp("Key",  (2.2, -2.6,  1.9), 420)
lamp("Fill", (-2.8, -1.4, 0.4), 150, 5.0)
lamp("Rim",  (-0.6,  3.0, 1.6), 260)

cam_d = bpy.data.cameras.new("Cam"); cam_d.lens = 78
cam = bpy.data.objects.new("Cam", cam_d); sc.collection.objects.link(cam)
sc.camera = cam

def shot(frame, az, el, dist, target, out, unfold=False):
    sc.frame_set(frame)
    pv = bpy.data.objects["Pivot_f22"]
    merk = None
    if unfold:
        # Fuer den Nahvergleich des Federbeins: Klapp-Drehung wegnehmen, damit man NUR
        # den Teleskop-Weg und die Schere sieht. Die Rotation einfach zu ueberschreiben
        # reicht NICHT — der Render wertet die Animation neu aus und setzt sie zurueck.
        # Also die Action fuer diesen Knoten kurz abhaengen und danach wieder binden.
        merk = (pv.animation_data.action, pv.animation_data.action_slot)
        pv.animation_data.action = None
        pv.rotation_euler[0] = 0.0
        bpy.data.objects["Door"].hide_render = True
    else:
        bpy.data.objects["Door"].hide_render = False
    bpy.context.view_layer.update()
    t = Vector(target)
    p = t + Vector((math.cos(radians(el)) * math.sin(radians(az)),
                    -math.cos(radians(el)) * math.cos(radians(az)),
                    math.sin(radians(el)))) * dist
    cam.location = p
    cam.rotation_euler = (t - p).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    if merk is not None:
        pv.animation_data.action, pv.animation_data.action_slot = merk
    print("RENDER", out)

shot(1,   38, 12, 2.9, (0, 0, -0.52), PREFIX + "_aus_34.png")     # ausgefahren, 3/4
shot(1,   90,  6, 2.7, (0, 0, -0.52), PREFIX + "_aus_seite.png")  # ausgefahren, Seite
shot(30,  40, 18, 2.9, (0, 0.30, -0.20), PREFIX + "_ein_34.png")  # eingefahren
shot(16,  40, 14, 3.0, (0, 0.15, -0.38), PREFIX + "_mitte.png")   # halb eingefahren
# Nahaufnahmen des Federbeins: Kolben ausgefahren vs. eingefahren — hier muss die
# Drehmomentschere sichtbar mitklappen, statt in der Luft zu haengen.
sc.render.resolution_x, sc.render.resolution_y = 900, 900
shot(1,  115, 4, 1.30, (0, 0.06, -0.60), PREFIX + "_bein_lang.png", unfold=True)
shot(30, 115, 4, 1.30, (0, 0.06, -0.60), PREFIX + "_bein_kurz.png", unfold=True)
print("FERTIG")
