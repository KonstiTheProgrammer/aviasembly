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


BODY = material("cockpit_body", (0.52, 0.57, 0.65, 1.0), 0.52, 0.40)
BODY_DARK = material("body_detail", (0.27, 0.30, 0.35, 1.0), 0.48, 0.46)
FRAME = material("frame", (0.40, 0.45, 0.52, 1.0), 0.68, 0.34)
GLASS = material("glass", (0.025, 0.075, 0.16, 0.84), 0.10, 0.18)
GLASS_DARK = material("glass_dark", (0.015, 0.045, 0.11, 0.88), 0.08, 0.20)
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
    """Elliptischer Metallrumpf mit flacher Rückseite und offenem Glasanschluss."""
    stations = [
        (-1.35, 0.84, 0.78),
        (-1.05, 0.85, 0.79),
        (-0.58, 0.85, 0.79),
        (-0.12, 0.83, 0.78),
        (0.08, 0.80, 0.76),
    ]
    segs = 48
    verts = []
    for y, rx, rz in stations:
        for i in range(segs):
            angle = math.tau * i / segs
            verts.append((math.cos(angle) * rx, y, math.sin(angle) * rz))
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
    return mesh_object("B29_Rumpfschale", verts, faces, BODY)


GLASS_BASE_Y = 0.06
GLASS_LENGTH = 1.23
GLASS_RX = 0.805
GLASS_RZ = 0.755


def glass_point(theta, angle, lift=0.0):
    radial = math.sin(theta)
    return Vector(
        (
            math.cos(angle) * GLASS_RX * radial * (1.0 + lift),
            GLASS_BASE_Y + GLASS_LENGTH * math.cos(theta),
            math.sin(angle) * GLASS_RZ * radial * (1.0 + lift),
        )
    )


def glass_hemisphere():
    """Vordere Ellipsoid-Halbschale; die hintere Ringfläche bleibt offen."""
    us = 48
    vs = 18
    verts = []
    for iv in range(vs + 1):
        theta = (math.pi * 0.5) * iv / vs
        for iu in range(us):
            angle = math.tau * iu / us
            verts.append(tuple(glass_point(theta, angle)))
    faces = []
    for iv in range(vs):
        for iu in range(us):
            a = iv * us + iu
            b = iv * us + (iu + 1) % us
            c = (iv + 1) * us + iu
            d = (iv + 1) * us + (iu + 1) % us
            faces.append((a, c, b))
            faces.append((b, c, d))
    return mesh_object("B29_Glasnase", verts, faces, GLASS)


def canopy_frames():
    """B-29-typisches Sprossennetz: Querspanten und Längsrippen."""
    # Drei dünne Querspanten definieren große, klar lesbare Fensterscheiben.
    for idx, fraction in enumerate((0.31, 0.58, 0.82)):
        theta = math.pi * 0.5 * fraction
        points = [
            glass_point(theta, math.tau * i / 64, 0.012)
            for i in range(64)
        ]
        curve_tube("Fenster_Querspant_%02d" % idx, points, FRAME, 0.013, True)

    # Acht schlanke Längsstege laufen erst außerhalb der kleinen Frontscheibe an.
    angles = (
        0.0,
        math.radians(45),
        math.radians(90),
        math.radians(135),
        math.pi,
        math.radians(225),
        math.radians(270),
        math.radians(315),
    )
    for idx, angle in enumerate(angles):
        points = [
            glass_point(math.pi * 0.5 * (0.16 + 0.84 * i / 18), angle, 0.010)
            for i in range(19)
        ]
        curve_tube("Fenster_Laengsrippe_%02d" % idx, points, FRAME, 0.012)

    # Massiver Anschlussring zum Metallrumpf.
    base_points = [
        Vector(
            (
                math.cos(math.tau * i / 72) * GLASS_RX * 1.014,
                GLASS_BASE_Y,
                math.sin(math.tau * i / 72) * GLASS_RZ * 1.014,
            )
        )
        for i in range(72)
    ]
    curve_tube("Glasnase_Anschlussring", base_points, FRAME, 0.022, True)

    # Runde Frontscheibe des Bombenschützenplatzes.
    front_y = GLASS_BASE_Y + GLASS_LENGTH + 0.008
    cylinder("Bombenschuetze_Frontglas", 0.135, 0.018, (0.0, front_y, 0.0),
             (0.0, 1.0, 0.0), GLASS_DARK, 40)
    torus_y("Bombenschuetze_Frontring", front_y + 0.012, 0.150, 0.016, FRAME)


def greenhouse_extension():
    """Die obere Pilotenverglasung reicht wie auf der Referenz in den Rumpf zurück."""
    # Vier dunkle Dach-/Seitenscheiben je Seite, als leicht gewölbte Platten.
    for side in (-1.0, 1.0):
        for idx in range(3):
            y0 = 0.02 - idx * 0.22
            x0 = side * (0.25 + idx * 0.10)
            box(
                "Pilotenfenster_%s_%d" % ("L" if side < 0 else "R", idx),
                (0.30, 0.25, 0.025),
                (x0, y0 - 0.10, 0.63 - idx * 0.035),
                GLASS_DARK,
                rotation=(math.radians(-7), 0.0, side * math.radians(12)),
                bevel=0.018,
            )
    # Mittlere Dachscheiben und helle Trennstege.
    for idx in range(3):
        y = -0.08 - idx * 0.22
        box("Pilotenfenster_Dach_%d" % idx, (0.34, 0.24, 0.025),
            (0.0, y, 0.742 - idx * 0.015), GLASS_DARK,
            rotation=(math.radians(-4), 0.0, 0.0), bevel=0.016)
        box("Pilotenfenster_Steg_%d" % idx, (0.025, 0.255, 0.035),
            (0.0, y, 0.765 - idx * 0.015), FRAME, bevel=0.008)


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

    # Kleiner Astrodome, Antenne und die charakteristische Kinn-/Fahrwerksaufnahme.
    sphere("Astrodome", 1.0, (0.0, -0.47, 0.735), (0.22, 0.28, 0.16), GLASS)
    torus_z("Astrodome_Rahmen", (0.0, -0.47, 0.735), 0.215, 0.018, FRAME, 1.25)
    cylinder("Funkantenne", 0.012, 0.34, (0.0, -0.92, 0.82),
             (0.0, 0.0, 1.0), BODY_DARK, 12)
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


def build():
    clear()
    fuselage_shell()
    cockpit_interior()
    glass_hemisphere()
    canopy_frames()
    greenhouse_extension()
    exterior_details()
    apply_modifiers()
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB", export_yup=True)
    print("EXPORTED", OUT)


if __name__ == "__main__":
    build()
