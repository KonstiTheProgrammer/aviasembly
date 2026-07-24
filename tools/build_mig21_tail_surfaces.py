"""Build the dedicated MiG-21 stabilator and vertical-tail visuals.

Run inside Blender:
    blender --background --python tools/build_mig21_tail_surfaces.py

Coordinate convention before glTF export:
    Blender X = aircraft right, Blender +Y = aircraft front, Blender Z = up.
    Godot receives that as X = right, -Z = front, Y = up.

Origins and outer dimensions intentionally match the original game parts.  The
collision boxes and aerodynamic data continue to come from PartCatalog.gd.
"""

from __future__ import annotations

import math
import os

import bpy
from mathutils import Vector


PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
STAB_OUTPUT = os.path.join(PROJECT_ROOT, "models", "mig21_stab.glb")
FIN_OUTPUT = os.path.join(PROJECT_ROOT, "models", "mig21_fin.glb")

BODY_COLOR = (0.70, 0.72, 0.75, 1.0)
DARK_COLOR = (0.12, 0.13, 0.15, 1.0)

PROFILE_STATIONS = (
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

STAB_SPAN = 0.95
STAB_SPAN_STATIONS = (
    0.00,
    0.07,
    0.16,
    0.27,
    0.39,
    0.51,
    0.63,
    0.74,
    0.83,
    0.90,
    0.95,
    0.985,
    1.00,
)

FIN_HEIGHT = 1.30
FIN_HEIGHT_STATIONS = (
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
    0.98,
    1.00,
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


def smooth_closed_loft(
    name: str,
    root: bpy.types.Object,
    rings: list[list[tuple[float, float, float]]],
    material: bpy.types.Material,
    sharp_indices: tuple[int, int],
) -> bpy.types.Object:
    """Create a closed loft from equal-sized perimeter rings."""
    ring_size = len(rings[0])
    verts = [co for ring in rings for co in ring]
    faces: list[tuple[int, ...]] = []

    for station in range(len(rings) - 1):
        a0 = station * ring_size
        b0 = (station + 1) * ring_size
        for j in range(ring_size):
            j1 = (j + 1) % ring_size
            faces.append((a0 + j, b0 + j, b0 + j1, a0 + j1))
    faces.append(tuple(reversed(range(ring_size))))
    tip0 = (len(rings) - 1) * ring_size
    faces.append(tuple(tip0 + j for j in range(ring_size)))

    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = root

    for poly in mesh.polygons:
        poly.use_smooth = len(poly.vertices) == 4

    for station in range(len(rings) - 1):
        a0 = station * ring_size
        b0 = (station + 1) * ring_size
        wanted = {
            frozenset((a0 + sharp_indices[0], b0 + sharp_indices[0])),
            frozenset((a0 + sharp_indices[1], b0 + sharp_indices[1])),
        }
        for edge in mesh.edges:
            if frozenset(edge.vertices) in wanted:
                edge.use_edge_sharp = True
    return obj


# ---------------------------------------------------------------------------
# All-moving horizontal stabilizer
# ---------------------------------------------------------------------------


def stab_planform(span_fraction: float) -> tuple[float, float, float]:
    s = max(0.0, min(1.0, span_fraction))
    x = STAB_SPAN * s
    trailing = -0.55 - 0.05 * s
    leading = 0.55 - 0.90 * s

    # Rounded manufactured corners without changing the original outer bounds.
    if s > 0.94:
        t = (s - 0.94) / 0.06
        ease = t * t * (3.0 - 2.0 * t)
        trailing += 0.004 * ease
        leading -= 0.004 * ease
    return x, trailing, leading


def stab_section(
    span_fraction: float, chord_fraction: float
) -> tuple[float, float]:
    s = max(0.0, min(1.0, span_fraction))
    u = max(0.0, min(1.0, chord_fraction))
    half_t = 0.030 * (1.0 - s) ** 0.72 + 0.010 * s
    shape = math.sin(math.pi * u) ** 0.80
    shape *= 0.94 + 0.06 * u
    camber = 0.0018 * (1.0 - 0.45 * s) * math.sin(math.pi * u)
    return camber, half_t * shape


def stab_surface_z(x: float, y: float, upper: bool = True) -> float:
    s = max(0.0, min(1.0, x / STAB_SPAN))
    _, trailing, leading = stab_planform(s)
    chord = max(leading - trailing, 0.001)
    u = max(0.0, min(1.0, (y - trailing) / chord))
    camber, half_t = stab_section(s, u)
    return camber + half_t if upper else camber - half_t


def build_stab_skin(
    root: bpy.types.Object, body: bpy.types.Material
) -> bpy.types.Object:
    profile = [(u, 1.0) for u in PROFILE_STATIONS]
    profile += [(u, -1.0) for u in reversed(PROFILE_STATIONS[1:-1])]
    rings: list[list[tuple[float, float, float]]] = []
    for s in STAB_SPAN_STATIONS:
        x, trailing, leading = stab_planform(s)
        chord = leading - trailing
        ring = []
        for u, side in profile:
            y = trailing + chord * u
            camber, half_t = stab_section(s, u)
            ring.append((x, y, camber + side * half_t))
        rings.append(ring)
    return smooth_closed_loft(
        "StabilatorSkin",
        root,
        rings,
        body,
        (0, len(PROFILE_STATIONS) - 1),
    )


def add_stab_ribbon(
    root: bpy.types.Object,
    name: str,
    points: list[tuple[float, float]],
    width: float,
    material: bpy.types.Material,
    upper: bool = True,
    lift: float = 0.0022,
) -> bpy.types.Object:
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
            z = stab_surface_z(q.x, q.y, upper)
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


def add_stab_details(
    root: bpy.types.Object, seam: bpy.types.Material
) -> list[bpy.types.Object]:
    details: list[bpy.types.Object] = []
    specs = [
        ("StabFrontSpar", [(0.055, 0.28), (0.34, -0.03), (0.68, -0.31), (0.88, -0.45)], 0.006),
        ("StabRearSpar", [(0.050, -0.33), (0.36, -0.40), (0.68, -0.48), (0.87, -0.54)], 0.007),
        ("StabInnerRib", [(0.28, -0.39), (0.28, -0.05), (0.28, 0.16)], 0.0055),
        ("StabMidRib", [(0.55, -0.46), (0.55, -0.27), (0.55, -0.08)], 0.0055),
        ("StabOuterRib", [(0.78, -0.52), (0.78, -0.42), (0.78, -0.29)], 0.0055),
    ]
    for name, points, width in specs:
        details.append(add_stab_ribbon(root, name, points, width, seam))

    # Circular all-moving-tail pivot/inspection cover.
    circle = []
    for i in range(33):
        a = math.tau * i / 32.0
        circle.append((0.15 + math.cos(a) * 0.075, -0.05 + math.sin(a) * 0.105))
    details.append(add_stab_ribbon(root, "StabilatorPivot", circle, 0.006, seam))

    # Repeat the structural lines on the underside, more subtly.
    details.append(
        add_stab_ribbon(
            root,
            "StabLowerRearSpar",
            [(0.06, -0.33), (0.42, -0.42), (0.83, -0.53)],
            0.005,
            seam,
            upper=False,
        )
    )
    return details


def add_stab_rivets(
    root: bpy.types.Object, seam: bpy.types.Material
) -> bpy.types.Object:
    strips = [
        ((0.07, 0.26), (0.86, -0.43), 28),
        ((0.07, -0.32), (0.84, -0.53), 25),
    ]
    verts: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    radius = 0.0048
    for start, end, count in strips:
        a = Vector(start)
        b = Vector(end)
        for i in range(count):
            p = a.lerp(b, (i + 0.5) / count)
            z = stab_surface_z(p.x, p.y, True) + 0.003
            base = len(verts)
            verts.append((p.x, p.y, z))
            for j in range(6):
                angle = math.tau * j / 6.0
                verts.append((p.x + math.cos(angle) * radius, p.y + math.sin(angle) * radius, z))
            faces.append(tuple([base] + [base + j + 1 for j in range(6)]))

    mesh = bpy.data.meshes.new("StabilatorRivets_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(seam)
    mesh.update()
    obj = bpy.data.objects.new("StabilatorRivets", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = root
    return obj


def build_stabilator(
    body: bpy.types.Material, seam: bpy.types.Material
) -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    root = bpy.data.objects.new("mig21_stab", None)
    bpy.context.scene.collection.objects.link(root)
    objects = [build_stab_skin(root, body)]
    objects.extend(add_stab_details(root, seam))
    objects.append(add_stab_rivets(root, seam))
    return root, objects


# ---------------------------------------------------------------------------
# Vertical fin and rudder
# ---------------------------------------------------------------------------


def fin_planform(height_fraction: float) -> tuple[float, float, float]:
    s = max(0.0, min(1.0, height_fraction))
    z = FIN_HEIGHT * s
    trailing = -0.86 - 0.06 * s
    leading = 0.94 - 1.50 * s

    # A slightly convex leading-edge fairing at the root and rounded fin cap.
    leading += 0.055 * math.sin(math.pi * min(s / 0.30, 1.0)) if s < 0.30 else 0.0
    if s > 0.94:
        t = (s - 0.94) / 0.06
        ease = t * t * (3.0 - 2.0 * t)
        trailing += 0.006 * ease
        leading -= 0.006 * ease
    return z, trailing, leading


def fin_section(
    height_fraction: float, chord_fraction: float
) -> float:
    s = max(0.0, min(1.0, height_fraction))
    u = max(0.0, min(1.0, chord_fraction))
    half_t = 0.050 * (1.0 - s) ** 0.70 + 0.016 * s
    shape = math.sin(math.pi * u) ** 0.78
    shape *= 0.93 + 0.07 * u
    return half_t * shape


def fin_surface_x(y: float, z: float, positive: bool = True) -> float:
    s = max(0.0, min(1.0, z / FIN_HEIGHT))
    _, trailing, leading = fin_planform(s)
    chord = max(leading - trailing, 0.001)
    u = max(0.0, min(1.0, (y - trailing) / chord))
    thickness = fin_section(s, u)
    return thickness if positive else -thickness


def build_fin_skin(
    root: bpy.types.Object, body: bpy.types.Material
) -> bpy.types.Object:
    profile = [(u, 1.0) for u in PROFILE_STATIONS]
    profile += [(u, -1.0) for u in reversed(PROFILE_STATIONS[1:-1])]
    rings: list[list[tuple[float, float, float]]] = []
    for s in FIN_HEIGHT_STATIONS:
        z, trailing, leading = fin_planform(s)
        chord = leading - trailing
        ring = []
        for u, side in profile:
            y = trailing + chord * u
            ring.append((side * fin_section(s, u), y, z))
        rings.append(ring)
    return smooth_closed_loft(
        "VerticalFinSkin",
        root,
        rings,
        body,
        (0, len(PROFILE_STATIONS) - 1),
    )


def add_fin_ribbon(
    root: bpy.types.Object,
    name: str,
    points: list[tuple[float, float]],
    width: float,
    material: bpy.types.Material,
    positive: bool,
    lift: float = 0.0022,
) -> bpy.types.Object:
    """Create a conforming seam on one side of the fin; points are (y, z)."""
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
            x = fin_surface_x(q.x, q.y, positive)
            x += lift if positive else -lift
            verts.append((x, q.x, q.y))
    for i in range(len(points) - 1):
        a = i * 2
        if positive:
            faces.append((a, a + 2, a + 3, a + 1))
        else:
            faces.append((a + 1, a + 3, a + 2, a))

    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(material)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = root
    return obj


def add_fin_details(
    root: bpy.types.Object, seam: bpy.types.Material
) -> list[bpy.types.Object]:
    details: list[bpy.types.Object] = []
    specs = [
        ("RudderHinge", [(-0.70, 0.07), (-0.72, 0.36), (-0.75, 0.72), (-0.79, 1.13)], 0.010),
        ("RudderTipGap", [(-0.79, 1.13), (-0.84, 1.22), (-0.90, 1.27)], 0.009),
        ("FinFrontSpar", [(0.58, 0.08), (0.28, 0.38), (-0.06, 0.72), (-0.46, 1.16)], 0.007),
        ("FinLowerRib", [(-0.72, 0.36), (-0.20, 0.36), (0.29, 0.36)], 0.006),
        ("FinUpperRib", [(-0.76, 0.74), (-0.42, 0.74), (-0.08, 0.74)], 0.006),
    ]
    for positive in (True, False):
        side_name = "R" if positive else "L"
        for name, points, width in specs:
            details.append(
                add_fin_ribbon(
                    root,
                    name + side_name,
                    points,
                    width,
                    seam,
                    positive,
                )
            )

        circle = []
        for i in range(33):
            a = math.tau * i / 32.0
            circle.append((-0.02 + math.cos(a) * 0.13, 0.38 + math.sin(a) * 0.105))
        details.append(
            add_fin_ribbon(
                root,
                "FinInspection" + side_name,
                circle,
                0.006,
                seam,
                positive,
            )
        )
    return details


def add_fin_rivets(
    root: bpy.types.Object, seam: bpy.types.Material
) -> list[bpy.types.Object]:
    objects: list[bpy.types.Object] = []
    strips = [
        ((0.56, 0.09), (-0.44, 1.14), 35),
        ((-0.69, 0.09), (-0.79, 1.10), 30),
    ]
    for positive in (True, False):
        verts: list[tuple[float, float, float]] = []
        faces: list[tuple[int, ...]] = []
        radius = 0.0048
        for start, end, count in strips:
            a = Vector(start)
            b = Vector(end)
            for i in range(count):
                p = a.lerp(b, (i + 0.5) / count)
                x = fin_surface_x(p.x, p.y, positive)
                x += 0.003 if positive else -0.003
                base = len(verts)
                verts.append((x, p.x, p.y))
                for j in range(6):
                    angle = math.tau * j / 6.0
                    verts.append(
                        (
                            x,
                            p.x + math.cos(angle) * radius,
                            p.y + math.sin(angle) * radius,
                        )
                    )
                if positive:
                    faces.append(tuple([base] + [base + j + 1 for j in range(6)]))
                else:
                    faces.append(tuple([base] + [base + j + 1 for j in reversed(range(6))]))

        mesh = bpy.data.meshes.new(
            "FinRivetsR_mesh" if positive else "FinRivetsL_mesh"
        )
        mesh.from_pydata(verts, [], faces)
        mesh.materials.append(seam)
        mesh.update()
        obj = bpy.data.objects.new("FinRivetsR" if positive else "FinRivetsL", mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.parent = root
        objects.append(obj)
    return objects


def build_fin(
    body: bpy.types.Material, seam: bpy.types.Material
) -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    root = bpy.data.objects.new("mig21_fin", None)
    bpy.context.scene.collection.objects.link(root)
    objects = [build_fin_skin(root, body)]
    objects.extend(add_fin_details(root, seam))
    objects.extend(add_fin_rivets(root, seam))
    return root, objects


def export_part(
    root: bpy.types.Object,
    objects: list[bpy.types.Object],
    output_path: str,
) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )


def build() -> tuple[
    tuple[bpy.types.Object, list[bpy.types.Object]],
    tuple[bpy.types.Object, list[bpy.types.Object]],
]:
    clear_scene()
    body = make_material("body", BODY_COLOR, 0.48, 0.52)
    seam = make_material("dark", DARK_COLOR, 0.58, 0.50)
    stab = build_stabilator(body, seam)
    fin = build_fin(body, seam)
    return stab, fin


if __name__ == "__main__":
    stabilator, vertical_fin = build()
    export_part(stabilator[0], stabilator[1], STAB_OUTPUT)
    export_part(vertical_fin[0], vertical_fin[1], FIN_OUTPUT)
    stab_verts = sum(len(obj.data.vertices) for obj in stabilator[1])
    stab_faces = sum(len(obj.data.polygons) for obj in stabilator[1])
    fin_verts = sum(len(obj.data.vertices) for obj in vertical_fin[1])
    fin_faces = sum(len(obj.data.polygons) for obj in vertical_fin[1])
    print(
        f"MiG-21 stabilator exported: {STAB_OUTPUT} "
        f"({stab_verts} vertices, {stab_faces} faces)"
    )
    print(
        f"MiG-21 vertical fin exported: {FIN_OUTPUT} "
        f"({fin_verts} vertices, {fin_faces} faces)"
    )
