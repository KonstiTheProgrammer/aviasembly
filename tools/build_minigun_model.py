# models/minigun.glb — GAU-8-Gatling, LOW-POLY + FLAT (Projekt-Stil: kein shade_smooth).
#
# Anatomie (Blender: +Y = Muendung/vorne -> Godot -Z, Z = oben):
#   Munitionstrommel (12-seitig, hinten) -> 2 Zufuehrschaechte -> Aktionsgehaeuse (10-seitig)
#   -> Lagerplatte -> 7-LAUF-BUENDEL (Kreis r=0.085) mit 2 Laufklemmen + Muendungsklemme
#   + Zentralwelle. Obenauf ein Montage-Steg (Anbau ans Flugzeug).
# Node-Namen wie im alten glb: "GunBody" + "Barrels" (Drop-in; Barrels-Origin liegt auf der
# Laufachse x=z=0 -> ein spaeterer visueller Spin dreht sauber um die Achse).
# Masse wie Teil-Definition: Laenge 3.3 (y -1.65..+1.65), Durchmesser <= ~0.44.
#
# Usage:  blender --background --python tools/build_minigun_model.py
import bpy
import math
from mathutils import Vector

OUT = "C:/Users/Konst/Projects/aviasembly/models/minigun.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def lin(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def mat(name, col, metal, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*lin(col), 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*col, 1.0)
    return m


M_DARK = mat("gun_dark", (0.30, 0.32, 0.35), 0.6, 0.5)       # Gehaeuse/Trommel (Gunmetal)
M_STEEL = mat("gun_steel", (0.58, 0.60, 0.64), 0.9, 0.3)     # Laeufe (heller Stahl)
M_CLAMP = mat("gun_clamp", (0.42, 0.44, 0.47), 0.75, 0.4)    # Klemmen/Ringe
M_CHUTE = mat("gun_chute", (0.22, 0.23, 0.25), 0.5, 0.6)     # Zufuehrung/Steg (dunkler Absatz)


def cyl_y(y0, y1, r, m, name, verts=10, cx=0.0, cz=0.0):
    """Zylinder entlang +Y (Laufrichtung), FLAT."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=y1 - y0,
                                        location=(cx, (y0 + y1) * 0.5, cz),
                                        rotation=(math.radians(90), 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.data.materials.append(m)
    return o


def box(center, size, m, name):
    bpy.ops.mesh.primitive_cube_add(location=center)
    o = bpy.context.active_object
    o.scale = (size[0] * 0.5, size[1] * 0.5, size[2] * 0.5)
    o.name = name
    o.data.materials.append(m)
    return o


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    j = bpy.context.active_object
    j.name = name
    j.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return j


body = []
# --- Munitionstrommel (das ikonische Fass hinten) ---
body.append(cyl_y(-1.65, -0.78, 0.205, M_DARK, "drum", 12))
body.append(cyl_y(-1.66, -1.60, 0.215, M_CLAMP, "drum_cap_r", 12))   # Endkappen-Ring
body.append(cyl_y(-0.84, -0.78, 0.215, M_CLAMP, "drum_cap_f", 12))
body.append(cyl_y(-1.30, -1.22, 0.215, M_CLAMP, "drum_rib", 12))     # Mittelrippe
# --- Zufuehrschaechte (2 eckige Kanaele Trommel -> Gehaeuse) ---
body.append(box((0.10, -0.70, 0.10), (0.10, 0.28, 0.10), M_CHUTE, "chute_r"))
body.append(box((-0.10, -0.70, -0.10), (0.10, 0.28, 0.10), M_CHUTE, "chute_l"))
# --- Aktionsgehaeuse + Lagerplatte + Rueckstossring ---
body.append(cyl_y(-0.78, 0.02, 0.165, M_DARK, "housing", 10))
body.append(cyl_y(0.02, 0.09, 0.185, M_CLAMP, "bearing_plate", 10))
# --- Montage-Steg oben (Anbaupunkt ans Flugzeug) ---
body.append(box((0.0, -0.42, 0.20), (0.16, 0.55, 0.10), M_CHUTE, "mount_lug"))

barrels = []
# --- 7-Lauf-Buendel + Zentralwelle ---
for i in range(7):
    a = i * math.tau / 7
    bx, bz = math.cos(a) * 0.085, math.sin(a) * 0.085
    barrels.append(cyl_y(0.06, 1.52, 0.032, M_STEEL, f"barrel{i}", 6, bx, bz))
    barrels.append(cyl_y(1.50, 1.63, 0.040, M_CLAMP, f"muzzle{i}", 6, bx, bz))  # Muendungsstueck
barrels.append(cyl_y(0.06, 0.95, 0.030, M_DARK, "shaft", 6))
# Laufklemmen (binden das Buendel) + Muendungsklemme
barrels.append(cyl_y(0.52, 0.575, 0.128, M_CLAMP, "clamp_mid", 12))
barrels.append(cyl_y(1.08, 1.135, 0.128, M_CLAMP, "clamp_front", 12))
barrels.append(cyl_y(1.56, 1.615, 0.118, M_DARK, "clamp_muzzle", 12))

gun_body = join(body, "GunBody")
gun_barrels = join(barrels, "Barrels")
# FLAT ueberall (kein Gummi an einer Gatling) — Primitives sind flat, sicherstellen:
for o in (gun_body, gun_barrels):
    for p in o.data.polygons:
        p.use_smooth = False

root = bpy.data.objects.new("minigun", None)
sc.collection.objects.link(root)
for o in (gun_body, gun_barrels):
    o.parent = root

lo = [1e9] * 3
hi = [-1e9] * 3
for o in (gun_body, gun_barrels):
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        for i in range(3):
            lo[i] = min(lo[i], w[i])
            hi[i] = max(hi[i], w[i])
print("DIMS Blender:", [round(hi[i] - lo[i], 3) for i in range(3)],
      " y:", round(lo[1], 3), "..", round(hi[1], 3))
print("Polys:", len(gun_body.data.polygons) + len(gun_barrels.data.polygons))

bpy.ops.object.select_all(action='DESELECT')
root.select_set(True)
gun_body.select_set(True)
gun_barrels.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_yup=True)
print("EXPORTED", OUT)
