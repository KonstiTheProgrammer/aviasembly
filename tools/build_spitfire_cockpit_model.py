## Baut ein dediziertes Supermarine-Spitfire-Cockpit:
## gerahmte WWII-Kanzel, dunkler Innenraum, Sitz, Schienen und Rücken-Spine.
## Export: res://models/spitfire_cockpit.glb
##
## Achsen (glTF +Y up): Blender X->Godot X, Blender Z->Godot Y(oben),
## Blender +Y->Godot -Z (Nase vorne).
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "models"


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)
    for block in list(bpy.data.materials):
        bpy.data.materials.remove(block)


def mat(name, color, rough=0.55, metal=0.0, alpha=1.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.use_backface_culling = False
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], alpha)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        material.blend_method = "BLEND"
        material.use_screen_refraction = True
    return material


BODY = None
GLASS = None
FRAME = None
DARK = None
SEAT = None


def make_materials():
    global BODY, GLASS, FRAME, DARK, SEAT
    BODY = mat("cockpit_body", (0.26, 0.33, 0.22), 0.48, 0.10)
    GLASS = mat("glass", (0.36, 0.55, 0.78), 0.05, 0.0, 0.34)
    FRAME = mat("frame", (0.045, 0.052, 0.050), 0.46, 0.45)
    DARK = mat("cockpit_dark", (0.035, 0.037, 0.038), 0.86, 0.05)
    SEAT = mat("seat", (0.18, 0.105, 0.065), 0.72, 0.0)


def shade(obj, bevel=0.0, segments=3):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        bpy.ops.object.shade_smooth()
    except Exception:
        pass
    obj.select_set(False)
    if bevel > 0.0:
        mod = obj.modifiers.new("soft bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.affect = "EDGES"
    obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")


def apply_modifiers():
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            continue
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        for mod in list(obj.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=mod.name)
            except Exception:
                pass
        obj.select_set(False)


def full_loft(name, stations, material, segments=96, cap_front=True, cap_back=True):
    bm = bmesh.new()
    rings = []
    for y, half_width, top, bottom in stations:
        center = (top + bottom) * 0.5
        half_height = (top - bottom) * 0.5
        ring = []
        for i in range(segments):
            a = math.tau * i / segments
            ring.append(bm.verts.new((
                half_width * math.cos(a),
                y,
                center + half_height * math.sin(a),
            )))
        rings.append(ring)
    for i in range(len(rings) - 1):
        a = rings[i]
        b = rings[i + 1]
        for j in range(segments):
            j2 = (j + 1) % segments
            bm.faces.new((a[j], a[j2], b[j2], b[j]))
    if cap_front:
        bm.faces.new(rings[0][::-1])
    if cap_back:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "Mesh")
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    shade(obj, 0.004, 2)
    return obj


def arch_surface(name, stations, material, arch_steps=28, cap_ends=False):
    bm = bmesh.new()
    rows = []
    for y, half_width, base_z, height in stations:
        row = []
        for i in range(arch_steps + 1):
            t = math.pi * i / arch_steps
            row.append(bm.verts.new((
                half_width * math.cos(t),
                y,
                base_z + height * math.sin(t),
            )))
        rows.append(row)
    for i in range(len(rows) - 1):
        a = rows[i]
        b = rows[i + 1]
        for j in range(arch_steps):
            bm.faces.new((a[j], a[j + 1], b[j + 1], b[j]))
    if cap_ends:
        bm.faces.new(rows[0][::-1])
        bm.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "Mesh")
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    shade(obj, 0.002, 1)
    return obj


def curve_tube(name, pts, material, bevel=0.018, cyclic=False):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.resolution_u = 10
    cu.bevel_depth = bevel
    cu.bevel_resolution = 4
    spl = cu.splines.new("BEZIER")
    spl.bezier_points.add(len(pts) - 1)
    for point, co in zip(spl.bezier_points, pts):
        point.co = Vector(co)
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    spl.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def rounded_box(name, loc, scale, material, bevel=0.035):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    shade(obj, bevel, 5)
    return obj


def ellipse_top_at(y, x):
    stations = [
        (1.10, 0.46, 0.41, -0.42),
        (0.62, 0.55, 0.48, -0.51),
        (0.05, 0.59, 0.50, -0.54),
        (-0.58, 0.56, 0.50, -0.52),
        (-1.10, 0.48, 0.47, -0.44),
    ]
    for i in range(len(stations) - 1):
        y0, hw0, top0, bot0 = stations[i]
        y1, hw1, top1, bot1 = stations[i + 1]
        if y1 <= y <= y0:
            t = (y - y0) / (y1 - y0)
            hw = hw0 * (1.0 - t) + hw1 * t
            top = top0 * (1.0 - t) + top1 * t
            bot = bot0 * (1.0 - t) + bot1 * t
            center = (top + bot) * 0.5
            half_height = (top - bot) * 0.5
            k = max(0.0, 1.0 - (x / max(hw, 0.01)) ** 2)
            return center + half_height * math.sqrt(k)
    return 0.46


def station_arch(station, steps=36):
    y, half_width, base_z, height = station
    return [
        (
            half_width * math.cos(math.pi * i / steps),
            y,
            base_z + height * math.sin(math.pi * i / steps),
        )
        for i in range(steps + 1)
    ]


def add_body():
    full_loft("SpitfireCockpitBody", [
        (1.10, 0.46, 0.41, -0.42),
        (0.62, 0.55, 0.48, -0.51),
        (0.05, 0.59, 0.50, -0.54),
        (-0.58, 0.56, 0.50, -0.52),
        (-1.10, 0.48, 0.47, -0.44),
    ], BODY)

    # Schwarzes Anti-Glare-Panel vor der Frontscheibe.
    bm = bmesh.new()
    ys = [1.02, 0.82, 0.62, 0.46]
    xs = [-0.18, -0.08, 0.0, 0.08, 0.18]
    grid = []
    for y in ys:
        row = []
        for x in xs:
            row.append(bm.verts.new((x, y, ellipse_top_at(y, x) + 0.007)))
        grid.append(row)
    for i in range(len(grid) - 1):
        for j in range(len(xs) - 1):
            bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("AntiGlarePanelMesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("AntiGlarePanel", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(DARK)
    shade(obj, 0.0)


def add_spine():
    # Raised rear turtledeck/fairing, a key Spitfire silhouette cue.
    stations = [
        (-0.42, 0.34, 0.50, 0.13),
        (-0.68, 0.31, 0.51, 0.17),
        (-0.92, 0.24, 0.49, 0.13),
        (-1.10, 0.12, 0.47, 0.04),
    ]
    arch_surface("RearSpineFairing", stations, BODY, 24, True)
    curve_tube("spine_panel_line", [(0, -0.44, 0.63), (0, -0.78, 0.66), (0, -1.07, 0.51)], FRAME, 0.010)


def add_canopy():
    canopy = [
        (0.64, 0.22, 0.50, 0.075),
        (0.40, 0.34, 0.51, 0.235),
        (0.08, 0.40, 0.52, 0.315),
        (-0.25, 0.39, 0.52, 0.300),
        (-0.54, 0.28, 0.53, 0.170),
        (-0.70, 0.15, 0.53, 0.050),
    ]
    arch_surface("SpitfireFramedGlass", canopy, GLASS, 34, True)

    for idx, station in enumerate(canopy):
        bevel = 0.012 if idx in [0, len(canopy) - 1] else 0.009
        curve_tube("canopy_frame_%02d" % idx, station_arch(station), FRAME, bevel)

    # Sliding rails along both sides.
    for side in [-1, 1]:
        rail = []
        for y, hw, base, _height in canopy:
            rail.append((side * hw * 1.02, y, base + 0.012))
        curve_tube("canopy_side_rail_%d" % side, rail, FRAME, 0.012)

    # Central top spine and two subtle longitudinal frame lines.
    top = [(0.0, y, base + height + 0.015) for y, _hw, base, height in canopy]
    curve_tube("canopy_top_spine", top, FRAME, 0.008)
    for side in [-1, 1]:
        pts = []
        for y, hw, base, height in canopy:
            pts.append((side * hw * 0.43, y, base + height * 0.86 + 0.012))
        curve_tube("canopy_upper_longeron_%d" % side, pts, FRAME, 0.007)

    # Angled windscreen posts make the front read less like a bubble and more like a Spitfire canopy.
    for side in [-1, 1]:
        curve_tube("windscreen_post_%d" % side, [
            (side * 0.23, 0.64, 0.50),
            (side * 0.15, 0.52, 0.59),
            (0.0, 0.40, 0.73),
        ], FRAME, 0.010)


def add_interior():
    rounded_box("cockpit_tub", (0, -0.02, 0.405), (0.50, 0.76, 0.060), DARK, 0.025)
    rounded_box("seat_pan", (0, -0.19, 0.465), (0.30, 0.25, 0.060), SEAT, 0.022)
    back = rounded_box("seat_back", (0, -0.39, 0.585), (0.30, 0.052, 0.270), SEAT, 0.022)
    back.rotation_euler[0] = math.radians(-10)
    curve_tube("control_stick", [(0, 0.16, 0.46), (0.025, 0.20, 0.62)], FRAME, 0.010)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=18, ring_count=9, radius=0.026, location=(0.025, 0.20, 0.63))
    knob = bpy.context.object
    knob.name = "control_stick_grip"
    knob.data.materials.append(FRAME)
    shade(knob)


def export():
    apply_modifiers()
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    out = MODEL_DIR / "spitfire_cockpit.glb"
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )
    print("EXPORTED=" + str(out))


def main():
    clear()
    make_materials()
    add_body()
    add_spine()
    add_interior()
    add_canopy()
    export()


if __name__ == "__main__":
    main()
