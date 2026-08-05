## Studio-Render eines FERTIG EXPORTIERTEN Fahrwerks-glb — prueft also das echte
## Endprodukt samt Animation, nicht nur die Blender-Bauszene.
##   /Applications/Blender.app/Contents/MacOS/Blender --background \
##       --python tools/_gear_render_glb.py -- <glb> <out_prefix> [hoehe]
import bpy, sys, math, os
from math import radians
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
GLB = argv[0]
PREFIX = argv[1] if len(argv) > 1 else "/tmp/gear"
H = float(argv[2]) if len(argv) > 2 else 1.1          # Bauhoehe -> Kameraabstand

for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=GLB)

# ACHTUNG Bildrate: glTF speichert Zeiten in SEKUNDEN, der Import rechnet sie mit der
# Bildrate der Zielszene (Blender-Standard 24) in Frames um — die mit 30 fps gebaute
# 30-Frame-Animation endet hier also bei Frame 24. Den Bereich darum aus der Action
# lesen statt zu raten, sonst rendert man ins Leere hinter dem letzten Key.
F0, F1 = None, None
for a in bpy.data.actions:
    r = a.frame_range
    F0 = r[0] if F0 is None else min(F0, r[0])
    F1 = r[1] if F1 is None else max(F1, r[1])
F0, F1 = int(math.ceil(F0)) if F0 is not None else 1, int(math.floor(F1)) if F1 is not None else 30
print("ANIMATION Frames %d..%d bei %d fps" % (F0, F1, bpy.context.scene.render.fps))

sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x, sc.render.resolution_y = 820, 1000
sc.render.film_transparent = False
sc.eevee.taa_render_samples = 64
sc.view_settings.view_transform = 'Standard'
sc.view_settings.look = 'None'
sc.world = bpy.data.worlds.new("W")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.20, 0.22, 0.26, 1)

def lamp(name, loc, energy, size=4.0):
    d = bpy.data.lights.new(name, 'AREA'); d.energy = energy; d.size = size
    o = bpy.data.objects.new(name, d); sc.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector((0, 0, -H * 0.5)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
lamp("Key",  (2.2 * H, -2.6 * H,  1.9 * H), 420 * H * H)
lamp("Fill", (-2.8 * H, -1.4 * H, 0.4 * H), 150 * H * H, 5.0)
lamp("Rim",  (-0.6 * H,  3.0 * H, 1.6 * H), 260 * H * H)

cam_d = bpy.data.cameras.new("Cam"); cam_d.lens = 55
cam = bpy.data.objects.new("Cam", cam_d); sc.collection.objects.link(cam)
sc.camera = cam

sc.frame_start, sc.frame_end = F0, F1

def shot(frame, az, el, dist, ty, out):
    sc.frame_set(frame)
    bpy.context.view_layer.update()
    t = Vector((0, 0, ty))
    p = t + Vector((math.cos(radians(el)) * math.sin(radians(az)),
                    -math.cos(radians(el)) * math.cos(radians(az)),
                    math.sin(radians(el)))) * dist
    cam.location = p
    cam.rotation_euler = (t - p).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("RENDER", out)

shot(F0,          38, 12, 2.7 * H, -H * 0.48, PREFIX + "_aus_34.png")
shot(F0,          90,  6, 2.5 * H, -H * 0.48, PREFIX + "_aus_seite.png")
shot((F0 + F1) // 2, 40, 16, 2.8 * H, -H * 0.32, PREFIX + "_mitte.png")
shot(F1,          42, 20, 2.7 * H, -H * 0.18, PREFIX + "_ein_34.png")
# Frontansicht: nur so sieht man, ob ein um die Laengsachse klappendes Bein
# (wheel_ww2) nach INNEN oder nach AUSSEN einfaehrt.
# ACHTUNG Blickrichtung: die Kamera steht bei Azimut 0 auf -Y, und +Y ist im Projekt
# VORNE. az=0 zeigt also das HECK, az=180 die Nase. Frueher hiessen diese Bilder
# "_vorn" und zeigten in Wirklichkeit die Rueckseite — dadurch war z. B. die
# Katapultstange des Traegerbugbeins auf keinem einzigen Render zu sehen.
shot(F0, 178, 8, 2.6 * H, -H * 0.45, PREFIX + "_aus_vorn.png")
shot(F1, 178, 8, 2.6 * H, -H * 0.45, PREFIX + "_ein_vorn.png")
shot(F0,   2, 6, 2.6 * H, -H * 0.45, PREFIX + "_aus_hinten.png")
print("FERTIG")
