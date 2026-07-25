"""Baut die stilisierte B-29-Glasnase als Blender/glTF-Spielbauteil.

Blender-Koordinaten:
    X = Breite, Y = Flugrichtung/vorne, Z = oben.
Beim glTF-Export mit Y-up wird Blender +Y zu Godot -Z (Flugrichtung).
"""
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "models" / "cockpit_b29.glb"


def material(name, color, metallic=0.0, roughness=0.45):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if color[3] < 0.999:
        bsdf.inputs["Alpha"].default_value = color[3]
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "DITHERED"
        elif hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
        mat.diffuse_color = color
    return mat


BODY = material("cockpit_body", (0.29, 0.34, 0.42, 1.0), 0.40, 0.48)
BODY_DARK = material("body_detail", (0.27, 0.30, 0.35, 1.0), 0.48, 0.46)
FRAME = material("frame", (0.31, 0.36, 0.43, 1.0), 0.52, 0.42)
GLASS = material("glass", (0.012, 0.045, 0.115, 1.0), 0.04, 0.34)
GLASS_DARK = material("glass_dark", (0.006, 0.022, 0.065, 1.0), 0.02, 0.38)
INTERIOR = material("interior", (0.055, 0.065, 0.075, 1.0), 0.18, 0.76)
SEAT = material("seat", (0.16, 0.18, 0.17, 1.0), 0.05, 0.82)
LEATHER = material("leather", (0.19, 0.11, 0.065, 1.0), 0.02, 0.72)
GAUGE = material("gauge", (0.18, 0.62, 0.78, 1.0), 0.08, 0.22)
RUBBER = material("rubber", (0.018, 0.022, 0.028, 1.0), 0.0, 0.92)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def smooth(obj, bevel=0.0):
    if obj.type == "MESH":
        for poly in obj.data.polygons:
            poly.use_smooth = True
    if bevel > 0.0:
        mod = obj.modifiers.new("Kantenrundung", "BEVEL")
        mod.width = bevel
        mod.segments = 3


def mesh_object(name, verts, faces, mat, smooth_mesh=True):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    if smooth_mesh:
        smooth(obj)
    return obj


def mesh_object_multi(name, verts, face_data, materials, smooth_mesh=False):
    """Mesh mit Materialindex pro Fläche; vermeidet übereinanderliegende Teilplatten."""
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], [face for face, _material_index in face_data])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        obj.data.materials.append(mat)
    for polygon, (_face, material_index) in zip(obj.data.polygons, face_data):
        polygon.material_index = material_index
        polygon.use_smooth = smooth_mesh
    return obj


def box(name, size, loc, mat, rotation=(0.0, 0.0, 0.0), bevel=0.0, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    smooth(obj, bevel)
    return obj


def cylinder(name, radius, depth, loc, axis, mat, vertices=24, bevel=0.0, parent=None):
    direction = Vector(axis).normalized()
    rotation = direction.to_track_quat("Z", "Y").to_euler()
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    smooth(obj, bevel)
    return obj


def sphere(name, radius, loc, scale, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=32, ring_count=16, radius=radius, location=loc
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(mat)
    smooth(obj)
    return obj


def torus_y(name, y, major, minor, mat, z_scale=1.0):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=64,
        minor_segments=10,
        major_radius=major,
        minor_radius=minor,
        location=(0.0, y, 0.0),
        rotation=(math.pi * 0.5, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    # Nach der X-Rotation liegt die lokale Y-Achse in Blender-Welt-Z.
    obj.scale.y = z_scale
    obj.data.materials.append(mat)
    smooth(obj)
    return obj


def torus_z(name, loc, major, minor, mat, y_scale=1.0):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=48,
        minor_segments=10,
        major_radius=major,
        minor_radius=minor,
        location=loc,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale.y = y_scale
    obj.data.materials.append(mat)
    smooth(obj)
    return obj


def curve_tube(name, points, mat, radius=0.018, cyclic=False, resolution=2):
    curve = bpy.data.curves.new(name + "Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = resolution
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("NURBS" if len(points) > 3 else "POLY")
    spline.points.add(len(points) - 1)
    for point, co in zip(spline.points, points):
        point.co = (*co, 1.0)
    if spline.type == "NURBS":
        spline.order_u = min(3, len(points))
        spline.use_endpoint_u = not cyclic
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def fuselage_shell():
    """Langer, fast zylindrischer Metallrumpf wie auf der Referenz."""
    stations = [
        (-1.40, 0.82, 0.72, -0.04),
        (-1.05, 0.84, 0.74, -0.03),
        (-0.62, 0.85, 0.75, -0.02),
        (-0.25, 0.84, 0.74, 0.00),
        (0.04, 0.80, 0.70, 0.03),
    ]
    segs = 24
    verts = []
    for y, rx, rz, zc in stations:
        for i in range(segs):
            angle = math.tau * i / segs
            verts.append((math.cos(angle) * rx, y, zc + math.sin(angle) * rz))
    faces = []
    for row in range(len(stations) - 1):
        for i in range(segs):
            a = row * segs + i
            b = row * segs + (i + 1) % segs
            c = (row + 1) * segs + i
            d = (row + 1) * segs + (i + 1) % segs
            faces.append((a, c, b))
            faces.append((b, c, d))
    rear_center = len(verts)
    verts.append((0.0, stations[0][0], 0.0))
    for i in range(segs):
        faces.append((rear_center, (i + 1) % segs, i))
    return mesh_object("B29_Rumpfschale", verts, faces, BODY, False)


# Axiale Querschnitte der facettierten Glasnase: y, Breite, Höhe, Mittelpunkt-Z.
NOSE_STATIONS = (
    (1.24, 0.20, 0.18, -0.05),
    (1.08, 0.36, 0.31, -0.02),
    (0.84, 0.54, 0.46, 0.02),
    (0.54, 0.69, 0.59, 0.05),
    (0.20, 0.79, 0.68, 0.07),
    (-0.12, 0.81, 0.70, 0.07),
)
NOSE_SEGMENTS = 10


def nose_point(row, segment_f, axial_f=0.0, lift=1.0):
    """Punkt auf einem linear geführten, bewusst kantigen Nasen-Panel."""
    row2 = min(row + 1, len(NOSE_STATIONS) - 1)
    a = NOSE_STATIONS[row]
    b = NOSE_STATIONS[row2]
    y = a[0] + (b[0] - a[0]) * axial_f
    rx = (a[1] + (b[1] - a[1]) * axial_f) * lift
    rz = (a[2] + (b[2] - a[2]) * axial_f) * lift
    zc = a[3] + (b[3] - a[3]) * axial_f
    angle = math.tau * segment_f / NOSE_SEGMENTS
    return (math.cos(angle) * rx, y, zc + math.sin(angle) * rz)


def is_glass_cell(row, segment):
    """Die Metall-Kinnlinie steigt nach hinten wie im Referenzbild an."""
    angle = math.tau * (segment + 0.5) / NOSE_SEGMENTS
    lower = math.sin(angle)
    thresholds = (-1.1, -0.78, -0.55, -0.25, 0.00)
    return lower > thresholds[row]


def faceted_glass_nose():
    """Eine zusammenhängende Nasenhaut aus Metall, Rahmen und bündigen Scheiben."""
    verts = []
    faces = []

    for row in range(len(NOSE_STATIONS) - 1):
        for segment in range(NOSE_SEGMENTS):
            corners = (
                nose_point(row, segment, 0.0),
                nose_point(row, segment + 1, 0.0),
                nose_point(row, segment + 1, 1.0),
                nose_point(row, segment, 1.0),
            )
            if not is_glass_cell(row, segment):
                base = len(verts)
                verts.extend(corners)
                faces.append(((base, base + 1, base + 2, base + 3), 0))
                continue

            # Außen- und Innenkanten teilen sich eine Fläche: keine Überlappungen,
            # keine schwebenden Rahmen und kein Flimmern zwischen Einzelteilen.
            inset = 0.085
            pane = (
                nose_point(row, segment + inset, inset, 1.003),
                nose_point(row, segment + 1.0 - inset, inset, 1.003),
                nose_point(row, segment + 1.0 - inset, 1.0 - inset, 1.003),
                nose_point(row, segment + inset, 1.0 - inset, 1.003),
            )
            base = len(verts)
            verts.extend(corners)
            verts.extend(pane)
            faces.extend((
                ((base + 4, base + 5, base + 6, base + 7), 2),
                ((base + 0, base + 1, base + 5, base + 4), 1),
                ((base + 1, base + 2, base + 6, base + 5), 1),
                ((base + 2, base + 3, base + 7, base + 6), 1),
                ((base + 3, base + 0, base + 4, base + 7), 1),
            ))

    mesh_object_multi("B29_Nasenhaut", verts, faces, (BODY, FRAME, GLASS))

    # Kleine, klar gefasste Bombenschützen-Frontscheibe.
    front_y = NOSE_STATIONS[0][0] + 0.014
    cylinder("Bombenschuetze_Frontglas", 0.135, 0.018, (0.0, front_y, -0.05),
             (0.0, 1.0, 0.0), GLASS_DARK, 24)
    torus_y("Bombenschuetze_Frontring", front_y + 0.012, 0.151, 0.018, FRAME, 0.92)


def greenhouse_extension():
    """Eine gemeinsame Pilotenverglasung läuft in die obere Rumpfschale zurück."""
    y_rows = (-0.10, -0.36, -0.63, -0.89)
    angle_edges = tuple(math.radians(a) for a in (28, 58, 88, 118, 148))
    rx = 0.825
    rz = 0.725
    verts = []
    faces = []

    def point(y, angle, lift=1.0):
        return (math.cos(angle) * rx * lift, y,
                0.03 + math.sin(angle) * rz * lift)

    for iy in range(len(y_rows) - 1):
        for ia in range(len(angle_edges) - 1):
            a0 = angle_edges[ia]
            a1 = angle_edges[ia + 1]
            y0 = y_rows[iy]
            y1 = y_rows[iy + 1]
            frame_corners = (
                point(y0, a0, 1.004), point(y0, a1, 1.004),
                point(y1, a1, 1.004), point(y1, a0, 1.004),
            )
            inset = 0.10
            pa0 = a0 + (a1 - a0) * inset
            pa1 = a1 - (a1 - a0) * inset
            py0 = y0 + (y1 - y0) * inset
            py1 = y1 - (y1 - y0) * inset
            pane = (
                point(py0, pa0, 1.008), point(py0, pa1, 1.008),
                point(py1, pa1, 1.008), point(py1, pa0, 1.008),
            )
            base = len(verts)
            verts.extend(frame_corners)
            verts.extend(pane)
            faces.extend((
                ((base + 4, base + 5, base + 6, base + 7), 1),
                ((base + 0, base + 1, base + 5, base + 4), 0),
                ((base + 1, base + 2, base + 6, base + 5), 0),
                ((base + 2, base + 3, base + 7, base + 6), 0),
                ((base + 3, base + 0, base + 4, base + 7), 0),
            ))
    mesh_object_multi("B29_Pilotenverglasung", verts, faces, (FRAME, GLASS_DARK))


def cockpit_interior():
    """Lesbarer Innenausbau hinter dem dunklen Glas."""
    box("Cockpitboden", (1.24, 1.35, 0.075), (0.0, -0.16, -0.43),
        INTERIOR, bevel=0.025)
    box("Instrumentenbrett", (1.12, 0.075, 0.33), (0.0, 0.18, 0.02),
        INTERIOR, rotation=(math.radians(-8), 0.0, 0.0), bevel=0.025)
    box("Mittelkonsole", (0.18, 0.62, 0.18), (0.0, -0.04, -0.32),
        INTERIOR, bevel=0.025)

    for side in (-1.0, 1.0):
        x = side * 0.30
        box("Pilotensitz_Flaeche", (0.31, 0.38, 0.10), (x, -0.28, -0.24),
            SEAT, bevel=0.035)
        box("Pilotensitz_Lehne", (0.32, 0.12, 0.46), (x, -0.46, -0.04),
            SEAT, rotation=(math.radians(-7), 0.0, 0.0), bevel=0.045)
        box("Pilotensitz_Polster", (0.25, 0.055, 0.33), (x, -0.395, -0.025),
            LEATHER, rotation=(math.radians(-7), 0.0, 0.0), bevel=0.04)

        # Steuerhorn: Säule, Quergriff und zwei Griffenden.
        curve_tube(
            "Steuerhorn_Saeule",
            [
                Vector((x, -0.05, -0.34)),
                Vector((x, 0.02, -0.12)),
                Vector((x, 0.08, -0.02)),
            ],
            FRAME,
            0.018,
        )
        curve_tube(
            "Steuerhorn_Griff",
            [
                Vector((x - 0.11, 0.09, -0.01)),
                Vector((x, 0.10, 0.035)),
                Vector((x + 0.11, 0.09, -0.01)),
            ],
            RUBBER,
            0.024,
        )

    # Instrumente mit hellblauen Gläsern.
    for row, z in enumerate((0.055, -0.055)):
        for col in range(5):
            x = -0.42 + col * 0.21
            cylinder(
                "Rundinstrument_%d_%d" % (row, col),
                0.045,
                0.018,
                (x, 0.222, z),
                (0.0, 1.0, 0.0),
                GAUGE,
                20,
                0.002,
            )

    # Bombenschützenplatz vorn: Sitzkissen, Visier und kleiner Arbeitstisch.
    box("Bombenschuetze_Sitz", (0.34, 0.34, 0.08), (0.0, 0.66, -0.45),
        LEATHER, bevel=0.04)
    box("Bombenschuetze_Tisch", (0.46, 0.30, 0.045), (0.0, 0.70, -0.20),
        INTERIOR, rotation=(math.radians(8), 0.0, 0.0), bevel=0.018)
    cylinder("Bombenvisier", 0.055, 0.28, (0.0, 0.94, -0.12),
             (0.0, 1.0, 0.0), FRAME, 24, 0.004)
    cylinder("Bombenvisier_Okular", 0.075, 0.055, (0.0, 1.08, -0.12),
             (0.0, 1.0, 0.0), RUBBER, 24, 0.004)


def exterior_details():
    # Blechstoß und Nieten am hinteren Anschluss.
    torus_y("Rumpf_Blechstoss", -0.70, 0.805, 0.008, BODY_DARK, 0.90)
    for idx in range(24):
        angle = math.tau * idx / 24
        cylinder(
            "Anschlussniete",
            0.011,
            0.012,
            (
                math.cos(angle) * 0.812,
                -0.70,
                math.sin(angle) * 0.718,
            ),
            (0.0, 1.0, 0.0),
            FRAME,
            12,
        )

    # Charakteristische Kinn-/Fahrwerksaufnahme unterhalb der Glasnase.
    box("Kinnverkleidung", (0.34, 0.52, 0.18), (0.0, -0.04, -0.685),
        BODY, bevel=0.045)
    box("Bugfahrwerk_Aufnahme", (0.18, 0.24, 0.08), (0.0, -0.12, -0.79),
        BODY_DARK, bevel=0.025)


def apply_modifiers():
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            continue
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        for modifier in list(obj.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=modifier.name)
            except Exception:
                pass
        obj.select_set(False)


def convert_curves():
    """Kurven vor dem Zusammenfassen in echte Meshes umwandeln."""
    for obj in list(bpy.context.scene.objects):
        if obj.type != "CURVE":
            continue
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target="MESH")


def join_group(objects, name):
    if not objects:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    return result


def consolidate_objects():
    """Aus vielen Konstruktionshilfen werden wenige saubere Blender-Baugruppen."""
    convert_curves()
    reserved = {"B29_Nasenhaut", "B29_Pilotenverglasung"}
    groups = {
        "B29_Rumpf_komplett": [],
        "B29_Glasdetails": [],
        "B29_Rahmendetails": [],
        "B29_Innenraum": [],
    }
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH" or obj.name in reserved:
            continue
        names = {slot.material.name for slot in obj.material_slots if slot.material}
        if names and names <= {"cockpit_body", "body_detail"}:
            groups["B29_Rumpf_komplett"].append(obj)
        elif names and names <= {"glass", "glass_dark"}:
            groups["B29_Glasdetails"].append(obj)
        elif names and names <= {"frame"}:
            groups["B29_Rahmendetails"].append(obj)
        else:
            groups["B29_Innenraum"].append(obj)
    for name, objects in groups.items():
        join_group(objects, name)


def build():
    clear()
    fuselage_shell()
    cockpit_interior()
    faceted_glass_nose()
    greenhouse_extension()
    exterior_details()
    apply_modifiers()
    consolidate_objects()
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB", export_yup=True)
    print("EXPORTED", OUT)


if __name__ == "__main__":
    build()
