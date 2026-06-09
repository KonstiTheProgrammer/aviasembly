## Baut ALLE Fahrwerks-Modelle parametrisch neu -> res://models/wheel*.glb
## Struktur je Modell: "Leg" (Origin am oberen Drehpunkt 0,0,0; Holm/Schere/Achse)
##   └─ "Wheel" (Origin an der RADACHSE): Reifen+Speichenfelge+Nabe+Bremsscheibe.
## Das "Wheel"-Kind dreht im Spiel beim Rollen (AircraftBody), "Leg" klappt beim Einfahren.
##   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_wheels.py
## Achsen (glTF +Y up): Blender X->Godot X (Radachse), Blender Z->Godot Y, +Y->Godot -Z (vorn).
import bpy
from math import radians, tau, cos, sin

OUT = "/Users/konstantinkanzler/Downloads/aviasembly/models/"


def mat(name, col, rough, metal):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.name = name
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


XR = (0, radians(90), 0)   # Zylinder-Achse von Z auf X (Radachse)


def build(name, tire_r, tire_w, axle_z, leg_r, leg_top=0.0, twin=False, oleo=True, scissor=True, spokes=6):
    # Szene leeren
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for mt in list(bpy.data.materials):
        bpy.data.materials.remove(mt)
    M_rubber = mat("rubber", (0.05, 0.05, 0.06), 0.88, 0.0)
    M_rim = mat("rim", (0.72, 0.74, 0.80), 0.22, 0.9)
    M_hub = mat("hub", (0.15, 0.15, 0.17), 0.45, 0.7)
    M_steel = mat("steel", (0.5, 0.52, 0.56), 0.3, 0.9)
    M_gun = mat("gunmetal", (0.17, 0.18, 0.21), 0.4, 0.7)
    M_piston = mat("piston", (0.64, 0.66, 0.70), 0.12, 0.95)

    leg_parts = []
    wheel_parts = []

    def cyl(r, depth, loc, rot=(0, 0, 0), material=None, v=32, into=None):
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=v)
        o = bpy.context.active_object
        o.data.materials.append(material)
        into.append(o)
        return o

    def torus(major, minor, loc, material, into):
        bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, location=loc,
			rotation=(0, radians(90), 0), major_segments=36, minor_segments=18)
        o = bpy.context.active_object
        o.data.materials.append(material)
        into.append(o)
        return o

    def box(scale, loc, rot, material, into):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
        o = bpy.context.active_object
        o.scale = scale
        o.data.materials.append(material)
        into.append(o)
        return o

    # --- RAD (alles um die Achse bei (x_off, 0, axle_z)) ---
    xs = [-tire_w * 0.78, tire_w * 0.78] if twin else [0.0]
    for x in xs:
        # Reifen: Torus (außen = tire_r) + flacher Lauffl.-Zylinder dazwischen -> satter Slick
        torus(tire_r * 0.76, tire_r * 0.24, (x, 0, axle_z), M_rubber, wheel_parts)
        cyl(tire_r * 0.94, tire_w * 0.66, (x, 0, axle_z), XR, M_rubber, 36, wheel_parts)
        # Felge: heller Teller + dunkler Tiefbett-Ring
        cyl(tire_r * 0.56, tire_w * 0.55, (x, 0, axle_z), XR, M_rim, 28, wheel_parts)
        cyl(tire_r * 0.60, tire_w * 0.28, (x, 0, axle_z), XR, M_hub, 28, wheel_parts)
        # Speichen (sichtbares Rollen!)
        for k in range(spokes):
            a = tau * k / spokes
            sp_len = tire_r * 0.46
            cy = cos(a) * tire_r * 0.30
            cz = sin(a) * tire_r * 0.30
            box((tire_w * 0.34, tire_r * 0.13, sp_len),
				(x + (tire_w * 0.30 if not twin else 0.0), cy, axle_z + cz),
				(a - radians(90), 0, 0), M_rim, wheel_parts)
        # Bremsscheibe innen
        cyl(tire_r * 0.40, tire_w * 0.10, (x - tire_w * 0.42, 0, axle_z), XR, M_steel, 30, wheel_parts)
    # Nabe quer über alles
    cyl(tire_r * 0.15, (tire_w * 2.6 if twin else tire_w * 1.1), (0, 0, axle_z), XR, M_hub, 18, wheel_parts)

    # --- BEIN (von der Teil-Oberkante leg_top zur Achse) ---
    span = leg_top - axle_z
    if oleo:
        cyl(leg_r, span * 0.58, (0, 0, leg_top - span * 0.29), material=M_gun, into=leg_parts)
        cyl(leg_r * 0.72, span * 0.52, (0, 0, leg_top - span * 0.72), material=M_piston, into=leg_parts)
    else:
        cyl(leg_r, span * 1.02, (0, 0, leg_top - span * 0.5), material=M_gun, into=leg_parts)
    # Achs-Stummel
    cyl(leg_r * 0.6, tire_w * (2.2 if twin else 1.4), (0, 0, axle_z), XR, M_gun, 16, leg_parts)
    if scissor:
        box((0.016, 0.03, span * 0.26), (0, leg_r + 0.035, leg_top - span * 0.40), (radians(18), 0, 0), M_gun, leg_parts)
        box((0.016, 0.03, span * 0.24), (0, leg_r + 0.035, leg_top - span * 0.66), (radians(-18), 0, 0), M_gun, leg_parts)

    # --- Zusammenfassen: "Leg" (Origin 0) + "Wheel" (Origin an der Achse), Wheel KIND von Leg ---
    bpy.ops.object.select_all(action='DESELECT')
    for o in leg_parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = leg_parts[0]
    bpy.ops.object.join()
    leg = bpy.context.active_object
    leg.name = "Leg"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)   # Origin -> Drehpunkt (0,0,0)
    bpy.ops.object.shade_smooth()

    bpy.ops.object.select_all(action='DESELECT')
    for o in wheel_parts:
        o.select_set(True)
    # aktiv = Nabe (zuletzt erzeugt, Origin GENAU auf der Achse) -> Join-Origin = Achse
    bpy.context.view_layer.objects.active = wheel_parts[-1]
    bpy.ops.object.join()
    wheel = bpy.context.active_object
    wheel.name = "Wheel"
    bpy.ops.object.transform_apply(rotation=True, scale=True)   # Location NICHT backen (Origin bleibt Achse!)
    bpy.ops.object.shade_smooth()
    # Kind von Leg (klappt beim Einfahren mit), Welt-Transform beibehalten
    wheel.parent = leg
    wheel.matrix_parent_inverse = leg.matrix_world.inverted()

    path = OUT + name + ".glb"
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
		export_yup=True, export_apply=False)
    print("EXPORTED", path)


# Geometrie passend zu den PartCatalog-Boxen (Boden der Kollisionsbox = Reifen-Unterkante):
#   name           tire_r  tire_w  axle_z   leg_r  Optionen
build("wheel_light", 0.30, 0.16, -0.20, 0.045, leg_top=0.5, twin=False, oleo=False, scissor=False, spokes=5)
build("wheel", 0.45, 0.20, -0.15, 0.060, leg_top=0.6, twin=False, oleo=True, scissor=True, spokes=6)
build("wheel_heavy", 0.525, 0.19, -0.175, 0.085, leg_top=0.7, twin=True, oleo=True, scissor=True, spokes=6)
build("wheel_retract", 0.30, 0.15, -0.745, 0.050, leg_top=0.0, twin=False, oleo=True, scissor=True, spokes=6)
build("wheel_jet", 0.25, 0.15, -0.80, 0.055, leg_top=0.0, twin=False, oleo=True, scissor=True, spokes=6)
print("ALLE FAHRWERKE EXPORTIERT")
