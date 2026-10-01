import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "models"


def mat(name, color, metallic=0.0, roughness=0.55, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.use_backface_culling = False
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], alpha)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        m.blend_method = "BLEND"
        m.use_screen_refraction = True
    return m


BODY = mat("cockpit_body", (0.94, 0.92, 0.88), 0.05, 0.46)
LEATHER = mat("leather", (0.50, 0.25, 0.15), 0.0, 0.62)
LEATHER_DARK = mat("cockpit_dark", (0.13, 0.08, 0.065), 0.0, 0.82)
SEAT = mat("seat", (0.40, 0.18, 0.10), 0.0, 0.68)
METAL = mat("dark", (0.12, 0.12, 0.13), 0.45, 0.42)
GLASS = mat("glass", (0.48, 0.64, 0.82), 0.0, 0.06, 0.34)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def shade(obj, bevel=0.0):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        bpy.ops.object.shade_smooth()
    except Exception:
        pass
    obj.select_set(False)
    if bevel > 0.0:
        be = obj.modifiers.new("soft bevel", "BEVEL")
        be.width = bevel
        be.segments = 5
        be.affect = "EDGES"
    obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")


def apply_modifiers(obj=None):
    objects = [obj] if obj is not None else list(bpy.context.scene.objects)
    for ob in objects:
        bpy.context.view_layer.objects.active = ob
        ob.select_set(True)
        for mod in list(ob.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=mod.name)
            except Exception:
                pass
        ob.select_set(False)


def make_body():
    seg = 144
    rings = 34
    rx = 0.60
    rz = 0.60
    length = 2.20
    verts = []
    faces = []
    for j in range(rings + 1):
        y = -length * 0.5 + length * j / rings
        for i in range(seg):
            a = math.tau * i / seg
            verts.append((math.cos(a) * rx, y, math.sin(a) * rz))
    for j in range(rings):
        for i in range(seg):
            ni = (i + 1) % seg
            faces.append((j * seg + i, (j + 1) * seg + i, (j + 1) * seg + ni, j * seg + ni))
    front_center = len(verts)
    verts.append((0, length * 0.5, 0))
    back_center = len(verts)
    verts.append((0, -length * 0.5, 0))
    front = rings * seg
    for i in range(seg):
        ni = (i + 1) % seg
        faces.append((front_center, front + ni, front + i))
        faces.append((back_center, i, ni))
    mesh = bpy.data.meshes.new("open_cockpit_bodyMesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("open_cockpit_body", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(BODY)
    shade(obj, 0.0)
    return obj


def rounded_box(name, loc, scale, material, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    shade(obj, bevel)
    apply_modifiers(obj)
    return obj


def cutter_box():
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.03, 0.68))
    obj = bpy.context.object
    obj.name = "cockpit_recess_cutter"
    obj.dimensions = (0.70, 0.98, 1.12)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    be = obj.modifiers.new("rounded aperture", "BEVEL")
    be.width = 0.31
    be.segments = 36
    obj.modifiers.new("smooth cutter normals", "WEIGHTED_NORMAL")
    apply_modifiers(obj)
    return obj


def cut_recess(body):
    cutter = cutter_box()
    mod = body.modifiers.new("open cockpit recess", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    body.select_set(False)
    bpy.data.objects.remove(cutter, do_unlink=True)
    shade(body, 0.018)
    apply_modifiers(body)


def curve_tube(name, pts, material, bevel=0.035, cyclic=False):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.resolution_u = 8
    cu.bevel_depth = bevel
    cu.bevel_resolution = 5
    spl = cu.splines.new("BEZIER")
    spl.bezier_points.add(len(pts) - 1)
    for p, co in zip(spl.bezier_points, pts):
        p.co = Vector(co)
        p.handle_left_type = "AUTO"
        p.handle_right_type = "AUTO"
    spl.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def surface_z_for_x(x):
    rx = 0.60
    rz = 0.60
    t = max(0.0, 1.0 - (x / rx) ** 2)
    return math.sqrt(t) * rz


def add_cockpit_details():
    # Cockpit tub fills the recess, so the cutout reads as an intentional cockpit,
    # not as a random hole through the fuselage.
    rounded_box("cockpit_floor", (0, 0.03, 0.16), (0.55, 0.74, 0.055), LEATHER_DARK, 0.025)
    # A soft dark liner hides the raw white boolean wall and makes the recess read
    # as a padded cockpit opening instead of a cut-through shell.
    liner_pts = []
    for i in range(128):
        a = math.tau * i / 128
        x = math.cos(a) * 0.395
        y = 0.03 + math.sin(a) * 0.530
        z = surface_z_for_x(x) - 0.070
        liner_pts.append((x, y, z))
    curve_tube("inner_shadow_liner", liner_pts, LEATHER_DARK, 0.016, True)
    rounded_box("seat_pan", (0, -0.18, 0.22), (0.40, 0.26, 0.08), SEAT, 0.03)
    back = rounded_box("seat_back", (0, -0.36, 0.34), (0.40, 0.075, 0.34), SEAT, 0.035)
    back.rotation_euler[0] = math.radians(-8)

    # Raised leather coaming around the opening.
    pts = []
    for i in range(144):
        a = math.tau * i / 144
        x = math.cos(a) * 0.43
        y = 0.03 + math.sin(a) * 0.57
        z = surface_z_for_x(x) + 0.030
        pts.append((x, y, z))
    curve_tube("leather_cockpit_rim", pts, LEATHER, 0.034, True)

    # Small vintage windscreen at the front of the opening.
    screen = rounded_box("small_windscreen", (0, 0.53, 0.56), (0.48, 0.025, 0.23), GLASS, 0.018)
    screen.rotation_euler[0] = math.radians(-16)

    # Simple metal control stick.
    curve_tube("control_stick", [(0, 0.20, 0.20), (0.03, 0.25, 0.39)], METAL, 0.013, False)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=18, ring_count=9, radius=0.035, location=(0.03, 0.25, 0.405))
    knob = bpy.context.object
    knob.name = "control_stick_knob"
    knob.data.materials.append(METAL)
    shade(knob, 0.0)


def export():
    apply_modifiers()
    out = MODEL_DIR / "cockpit.glb"
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", export_yup=True)
    print("EXPORTED=" + str(out))


def main():
    clear()
    body = make_body()
    cut_recess(body)
    add_cockpit_details()
    export()


if __name__ == "__main__":
    main()
