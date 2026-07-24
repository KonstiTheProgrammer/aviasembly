"""Build the dedicated MiG-21 delta-wing visual and export it as glTF.

Run inside Blender:
    blender --background --python tools/build_mig21_wing_model.py

Coordinate convention before glTF export:
    Blender X = span, Blender +Y = aircraft front, Blender Z = up.
    Godot receives that as X = span, -Z = front, Y = up.

The gameplay collision and aerodynamic data remain in PartCatalog.gd.  This file
only creates the high-quality visual that replaces the old 60-vertex wedge.
"""

from __future__ import annotations

import math
import os

import bpy
from mathutils import Vector


PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUTPUT_PATH = os.path.join(PROJECT_ROOT, "models", "mig21_wing.glb")

SPAN = 1.75
ROOT_CHORD = 2.90
LEADING_EDGE_SWEEP = 2.65
TIP_TRAILING_ADVANCE = 0.04

SPAN_STATIONS = (
    0.00,
    0.06,
    0.14,
    0.24,
    0.35,
    0.47,
    0.59,
    0.70,
    0.80,
    0.88,
    0.94,
    0.975,
    1.00,
)

# Profile runs from trailing edge (0) to leading edge (1).  Dense points near
# both sharp edges keep the thin supersonic section crisp without looking faceted.
CHORD_STATIONS = (
    0.000,
    0.018,
    0.045,
    0.085,
    0.140,
    0.220,
    0.320,
    0.430,
    0.550,
    0.670,
    0.780,
    0.870,
    0.930,
    0.970,
    0.992,
    1.000,
)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def make_material(
    name: str,
    color: tuple[float, float, float, float],
    metallic: float,
    roughness: float,
) -> bpy.types.Material:
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def planform(span_fraction: float) -> tuple[float, float, float]:
    """Return x, trailing-y and leading-y for one span station."""
    s = max(0.0, min(1.0, span_fraction))
    x = SPAN * s
    trailing = -ROOT_CHORD * 0.5 + TIP_TRAILING_ADVANCE * s
    leading = ROOT_CHORD * 0.5 - LEADING_EDGE_SWEEP * s

    # The real wing is clipped, but its corners are not mathematical razor
    # points.  A tiny easing over the final six percent gives the tip a
    # manufactured, softly radiused silhouette while preserving its chord.
    if s > 0.94:
        t = (s - 0.94) / 0.06
        ease = t * t * (3.0 - 2.0 * t)
        trailing += 0.006 * ease
        leading -= 0.006 * ease
    return x, trailing, leading


def section_values(
    span_fraction: float, chord_fraction: float
) -> tuple[float, float]:
    """Return camber line and half-thickness at a planform point."""
    s = max(0.0, min(1.0, span_fraction))
    u = max(0.0, min(1.0, chord_fraction))

    # A thin, almost symmetric, double-curved supersonic section.  Root
    # half-thickness stays compatible with the old visual/collision, then tapers
    # hard toward the clipped tip.  A very small camber avoids a dead flat slab.
    root_half_t = 0.058
    tip_half_t = 0.014
    half_t = root_half_t * (1.0 - s) ** 0.72 + tip_half_t * s
    shape = math.sin(math.pi * u) ** 0.78
    shape *= 0.92 + 0.08 * u
    camber = 0.0065 * (1.0 - 0.45 * s) * math.sin(math.pi * u)
    return camber, half_t * shape


def surface_z(x: float, y: float, upper: bool = True) -> float:
    s = max(0.0, min(1.0, x / SPAN))
    _, trailing, leading = planform(s)
    chord = max(leading - trailing, 0.001)
    u = max(0.0, min(1.0, (y - trailing) / chord))
    camber, half_t = section_values(s, u)
    return camber + half_t if upper else camber - half_t


def build_wing_skin(root: bpy.types.Object, body: bpy.types.Material) -> bpy.types.Object:
    # One closed perimeter ring per span station:
    # upper trailing->leading, then lower leading->trailing (without duplicates).
    profile = [(u, 1.0) for u in CHORD_STATIONS]
    profile += [(u, -1.0) for u in reversed(CHORD_STATIONS[1:-1])]
    ring_size = len(profile)

    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for s in SPAN_STATIONS:
        x, trailing, leading = planform(s)
        chord = leading - trailing
        for u, side in profile:
            y = trailing + chord * u
            camber, half_t = section_values(s, u)
            verts.append((x, y, camber + side * half_t))

    for station in range(len(SPAN_STATIONS) - 1):
        a0 = station * ring_size
        b0 = (station + 1) * ring_size
        for j in range(ring_size):
            j1 = (j + 1) % ring_size
            faces.append((a0 + j, b0 + j, b0 + j1, a0 + j1))

    # Closed root and clipped wingtip.
    faces.append(tuple(reversed(range(ring_size))))
    tip0 = (len(SPAN_STATIONS) - 1) * ring_size
    faces.append(tuple(tip0 + j for j in range(ring_size)))

    mesh = bpy.data.meshes.new("mig21_wing_skin")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(body)
    mesh.update()

    obj = bpy.data.objects.new("WingSkin", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = root

    # Smooth the loft while retaining crisp caps, leading edge and trailing edge.
    for poly in mesh.polygons:
        poly.use_smooth = len(poly.vertices) == 4
    leading_idx = len(CHORD_STATIONS) - 1
    for station in range(len(SPAN_STATIONS) - 1):
        a0 = station * ring_size
        b0 = (station + 1) * ring_size
        wanted = {
            frozenset((a0, b0)),
            frozenset((a0 + leading_idx, b0 + leading_idx)),
        }
        for edge in mesh.edges:
            if frozenset(edge.vertices) in wanted:
                edge.use_edge_sharp = True

    return obj


def add_surface_ribbon(
    root: bpy.types.Object,
    name: str,
    points: list[tuple[float, float]],
    width: float,
    material: bpy.types.Material,
    upper: bool = True,
    lift: float = 0.0025,
) -> bpy.types.Object:
    """Make a narrow conforming strip for panel seams and hinge gaps."""
    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int, int]] = []
    for i, point in enumerate(points):
        p = Vector(point)
        prev = Vector(points[max(0, i - 1)])
        nxt = Vector(points[min(len(points) - 1, i + 1)])
        tangent = (nxt - prev).normalized()
        normal = Vector((-tangent.y, tangent.x))
        for sign in (-1.0, 1.0):
            q = p + normal * (width * 0.5 * sign)
            z = surface_z(q.x, q.y, upper)
            z += lift if upper else -lift
            verts.append((q.x, q.y, z))
    for i in range(len(points) - 1):
        a = i * 2
        faces.append((a, a + 2, a + 3, a + 1))

    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = root
    return obj


def add_panel_details(
    root: bpy.types.Object, seam: bpy.types.Material
) -> list[bpy.types.Object]:
    details: list[bpy.types.Object] = []

    # Trailing-edge flap and outer aileron.  These are closed, conforming hinge
    # outlines rather than raised boxes, so the wing still reads as one thin skin.
    flap = [
        (0.11, -1.414),
        (0.82, -1.401),
        (0.79, -1.175),
        (0.15, -1.035),
        (0.11, -1.414),
    ]
    aileron = [
        (0.82, -1.401),
        (1.56, -1.382),
        (1.47, -1.185),
        (0.79, -1.175),
        (0.82, -1.401),
    ]
    details.append(add_surface_ribbon(root, "FlapGap", flap, 0.010, seam))
    details.append(add_surface_ribbon(root, "AileronGap", aileron, 0.010, seam))

    # Primary spars and a restrained set of skin panels.  Lines follow the delta
    # sweep instead of forming a generic rectangular grid.
    line_specs = [
        ("FrontSpar", [(0.05, 0.48), (0.45, -0.05), (0.92, -0.60), (1.43, -1.08)], 0.008),
        ("RearSpar", [(0.06, -0.72), (0.48, -0.87), (0.95, -1.04), (1.45, -1.22)], 0.008),
        ("RootPanel", [(0.12, 0.88), (0.38, 0.51), (0.42, -0.40), (0.14, -0.52)], 0.007),
        ("MidRib", [(0.58, -0.91), (0.58, -0.20), (0.58, 0.49)], 0.006),
        ("OuterRib", [(1.18, -1.25), (1.18, -0.91), (1.18, -0.44)], 0.006),
    ]
    for name, points, width in line_specs:
        details.append(add_surface_ribbon(root, name, points, width, seam))

    # Two circular inspection hatches near the root.
    for idx, (cx, cy, rx, ry) in enumerate(
        ((0.33, 0.12, 0.105, 0.15), (0.52, -0.48, 0.075, 0.115))
    ):
        circle = []
        for i in range(33):
            a = math.tau * i / 32.0
            circle.append((cx + math.cos(a) * rx, cy + math.sin(a) * ry))
        details.append(
            add_surface_ribbon(root, f"InspectionHatch{idx + 1}", circle, 0.006, seam)
        )
    return details


def add_rivets(
    root: bpy.types.Object,
    seam: bpy.types.Material,
    strips: list[tuple[tuple[float, float], tuple[float, float], int]],
) -> bpy.types.Object:
    """Combine subtle six-sided rivets into one cheap detail mesh."""
    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    radius = 0.006
    for start, end, count in strips:
        a = Vector(start)
        b = Vector(end)
        for i in range(count):
            t = (i + 0.5) / count
            p = a.lerp(b, t)
            base = len(verts)
            z = surface_z(p.x, p.y, True) + 0.0032
            verts.append((p.x, p.y, z))
            for j in range(6):
                ang = math.tau * j / 6.0
                verts.append(
                    (
                        p.x + math.cos(ang) * radius,
                        p.y + math.sin(ang) * radius,
                        z,
                    )
                )
            faces.append(tuple([base] + [base + j + 1 for j in range(6)]))

    mesh = bpy.data.meshes.new("RivetRows_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(seam)
    mesh.update()
    obj = bpy.data.objects.new("RivetRows", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = root
    return obj


def add_fence(
    root: bpy.types.Object,
    body: bpy.types.Material,
    seam: bpy.types.Material,
) -> bpy.types.Object:
    """Build the characteristic thin chordwise boundary-layer fence."""
    x = 1.045
    half_width = 0.006
    ys = (-0.58, -0.35, -0.08, 0.20, 0.47)
    verts: list[tuple[float, float, float]] = []
    for i, y in enumerate(ys):
        t = i / (len(ys) - 1)
        base = surface_z(x, y, True) + 0.003
        height = 0.030 + 0.045 * math.sin(math.pi * t) ** 0.7
        for dx, top in (
            (-half_width, False),
            (half_width, False),
            (-half_width, True),
            (half_width, True),
        ):
            verts.append((x + dx, y, base + (height if top else 0.0)))

    faces: list[tuple[int, int, int, int]] = []
    for i in range(len(ys) - 1):
        a = i * 4
        b = (i + 1) * 4
        faces.extend(
            [
                (a, b, b + 2, a + 2),
                (a + 1, a + 3, b + 3, b + 1),
                (a + 2, b + 2, b + 3, a + 3),
                (a, a + 1, b + 1, b),
            ]
        )
    faces.extend([(0, 2, 3, 1), (len(verts) - 4, len(verts) - 3, len(verts) - 1, len(verts) - 2)])

    mesh = bpy.data.meshes.new("BoundaryLayerFence_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(body)
    mesh.update()
    obj = bpy.data.objects.new("BoundaryLayerFence", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = root

    bevel = obj.modifiers.new("SoftenedStampedEdges", "BEVEL")
    bevel.width = 0.003
    bevel.segments = 2

    add_surface_ribbon(
        root,
        "FenceBaseSeam",
        [(x, y) for y in ys],
        0.023,
        seam,
        lift=0.0018,
    )
    return obj


def add_root_fairing(
    root: bpy.types.Object, body: bpy.types.Material
) -> bpy.types.Object:
    """A subtle wheel/structure blister prevents the root from reading as a flat card."""
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=32,
        ring_count=12,
        location=(0.255, -0.31, surface_z(0.255, -0.31, True) + 0.012),
    )
    obj = bpy.context.object
    obj.name = "RootStructureFairing"
    obj.scale = (0.125, 0.34, 0.050)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(body)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.parent = root
    return obj


def add_pylon_pad(
    root: bpy.types.Object,
    name: str,
    x: float,
    y: float,
    body: bpy.types.Material,
) -> bpy.types.Object:
    bottom = surface_z(x, y, False)
    bpy.ops.mesh.primitive_cube_add(location=(x, y, bottom - 0.018))
    obj = bpy.context.object
    obj.name = name
    obj.scale = (0.080, 0.235, 0.022)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(body)
    bevel = obj.modifiers.new("StampedPadBevel", "BEVEL")
    bevel.width = 0.018
    bevel.segments = 3
    obj.parent = root
    return obj


def apply_export_modifiers(objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        if obj.type != "MESH":
            continue
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)


def build() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    clear_scene()

    # "body" is deliberately paintable by PartCatalog._recolor_model.
    # Match the dedicated MiG-21 fuselage: satin aircraft aluminium instead of
    # chrome.  This keeps both mirrored wings readable under asymmetric hangar light.
    body = make_material("body", (0.70, 0.72, 0.75, 1.0), 0.48, 0.52)
    seam = make_material("dark", (0.12, 0.13, 0.15, 1.0), 0.58, 0.50)

    root = bpy.data.objects.new("mig21_wing", None)
    bpy.context.scene.collection.objects.link(root)

    objects = [build_wing_skin(root, body)]
    objects.extend(add_panel_details(root, seam))
    objects.append(
        add_rivets(
            root,
            seam,
            [
                ((0.13, -1.02), (0.79, -1.17), 22),
                ((0.08, -0.70), (1.43, -1.21), 31),
                ((0.08, 0.45), (1.40, -1.05), 32),
            ],
        )
    )
    objects.append(add_fence(root, body, seam))
    objects.append(add_root_fairing(root, body))
    objects.append(add_pylon_pad(root, "InnerPylonPad", 0.54, -0.22, body))
    objects.append(add_pylon_pad(root, "OuterPylonPad", 1.23, -0.82, body))
    apply_export_modifiers(objects)

    return root, objects


def export(root: bpy.types.Object, objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root

    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_PATH,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )


if __name__ == "__main__":
    wing_root, wing_objects = build()
    export(wing_root, wing_objects)
    mesh_objects = [obj for obj in wing_objects if obj.type == "MESH"]
    vertex_count = sum(len(obj.data.vertices) for obj in mesh_objects)
    face_count = sum(len(obj.data.polygons) for obj in mesh_objects)
    print(
        f"MiG-21 wing exported: {OUTPUT_PATH} "
        f"({len(mesh_objects)} meshes, {vertex_count} vertices, {face_count} faces)"
    )
