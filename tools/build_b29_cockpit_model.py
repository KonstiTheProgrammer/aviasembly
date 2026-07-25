"""Baut die stilisierte B-29-Glasnase als Blender/glTF-Spielbauteil.

Blender-Koordinaten:
    X = Breite, Y = Flugrichtung/vorne, Z = oben.
Beim glTF-Export mit Y-up wird Blender +Y zu Godot -Z (Flugrichtung).
"""
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "models" / "cockpit_b29.glb"
NOSE_SEGMENTS = 12


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
# Fast schwarzes, blickdichtes Jet-Glas wie im neuen Referenzobjekt. Die niedrige
# Rauheit erhält den Bubble-Glanz, ohne dass der Innenraum durchscheint.
GLASS = material("glass", (0.015, 0.025, 0.055, 1.0), 0.25, 0.12)
INTERIOR = material("interior", (0.055, 0.065, 0.075, 1.0), 0.18, 0.76)
SEAT = material("seat", (0.16, 0.18, 0.17, 1.0), 0.05, 0.82)
LEATHER = material("leather", (0.19, 0.11, 0.065, 1.0), 0.02, 0.72)
GAUGE = material("gauge", (0.18, 0.62, 0.78, 1.0), 0.08, 0.22)
RUBBER = material("rubber", (0.018, 0.022, 0.028, 1.0), 0.0, 0.92)
MAP = material("map", (0.58, 0.53, 0.36, 1.0), 0.0, 0.78)
SWITCH = material("switch", (0.76, 0.19, 0.08, 1.0), 0.12, 0.42)


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


def torus_y(name, y, major, minor, mat, z_scale=1.0, z=0.0, x=0.0):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=32,
        minor_segments=8,
        major_radius=major,
        minor_radius=minor,
        location=(x, y, z),
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


def ellipse_disc_y(name, y, zc, rx, rz, mat, segments=32):
    """Flache elliptische Scheibe senkrecht zur Flugrichtung."""
    verts = [(0.0, y, zc)]
    for i in range(segments):
        angle = math.tau * i / segments
        verts.append((math.cos(angle) * rx, y, zc + math.sin(angle) * rz))
    faces = []
    for i in range(segments):
        faces.append((0, 1 + i, 1 + (i + 1) % segments))
    return mesh_object(name, verts, faces, mat, True)


def ellipse_beveled_ring_y(name, zc, rings, mat, segments=32):
    """Kurze konische Ringlippe, die außen exakt aus der Nasenkontur wächst."""
    verts = []
    for y, rx, rz in rings:
        for i in range(segments):
            angle = math.tau * i / segments
            verts.append((math.cos(angle) * rx, y, zc + math.sin(angle) * rz))
    faces = []
    for row in range(len(rings) - 1):
        a = row * segments
        b = (row + 1) * segments
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((a + i, a + j, b + j, b + i))
    return mesh_object(name, verts, faces, mat, True)


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
    """Gerader Metallrumpf hinter der kompakten B-29-Glasnase."""
    stations = [
        (-1.40, 0.84, 0.74, 0.04),
        (-1.05, 0.84, 0.74, 0.04),
        (-0.70, 0.84, 0.74, 0.04),
        (-0.34, 0.84, 0.74, 0.04),
    ]
    body_length = stations[-1][0] - stations[0][0]
    if not math.isclose(body_length, 1.06, abs_tol=0.0001):
        raise RuntimeError("Gerader B-29-Metallrumpf muss exakt 1,06 m lang sein")
    if any(station[1:] != stations[0][1:] for station in stations[1:]):
        raise RuntimeError("B-29-Metallrumpf muss über die ganze Länge gerade bleiben")
    # Gleiche Ringteilung wie die Nasenhaut: dadurch treffen sich beide Polygone
    # an der gemeinsamen Endkante exakt und lassen keine dreieckigen Spalten.
    segs = NOSE_SEGMENTS
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
    (1.08, 0.39, 0.34, -0.03),
    (0.82, 0.60, 0.50, 0.01),
    (0.49, 0.75, 0.63, 0.04),
    (0.13, 0.83, 0.71, 0.05),
    (-0.18, 0.84, 0.74, 0.04),
    (-0.34, 0.84, 0.74, 0.04),
)
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
    """Rundumglas vorn, nach hinten nur die obere Druckkabinen-Hälfte."""
    angle = math.tau * (segment + 0.5) / NOSE_SEGMENTS
    lower = math.sin(angle)
    thresholds = (-1.1, -0.70, -0.38, -0.12, 0.04, 0.10)
    return lower > thresholds[row]


def faceted_glass_nose():
    """Eine zusammenhängende Nasenhaut aus Metall, Rahmen und bündigen Scheiben."""
    nose_length = NOSE_STATIONS[0][0] - NOSE_STATIONS[-1][0]
    if nose_length > 1.60:
        raise RuntimeError("B-29-Glasnase ist wieder zu langgezogen")
    rear_bottoms = [station[3] - station[2] for station in NOSE_STATIONS[-4:]]
    rear_steps = [
        abs(rear_bottoms[i + 1] - rear_bottoms[i])
        for i in range(len(rear_bottoms) - 1)
    ]
    if max(rear_steps) > 0.09:
        raise RuntimeError("Unterer Übergang zum geraden B-29-Rumpf ist nicht weich genug")
    rear_row = len(NOSE_STATIONS) - 2
    rear_glass_cells = sum(
        1 for segment in range(NOSE_SEGMENTS) if is_glass_cell(rear_row, segment)
    )
    if rear_glass_cells != 6:
        raise RuntimeError("Hinterste B-29-Fensterreihe muss aus sechs Scheiben bestehen")
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

    # Bombenschützen-Frontscheibe mit kurzer, sauberer Ringlippe. Außenring,
    # Vorderkante und Scheibe sind echte Zwölfecke; die Scheibe sitzt leicht
    # zurückgesetzt hinter der vorderen Kante.
    front_y = NOSE_STATIONS[0][0]
    front_glass = ellipse_disc_y(
        "Bombenschuetze_Frontglas", front_y + 0.026, -0.05,
        0.126, 0.126, GLASS, NOSE_SEGMENTS
    )
    if len(front_glass.data.polygons) != NOSE_SEGMENTS:
        raise RuntimeError("Bombenschützen-Frontglas ist kein echtes Zwölfeck")
    ellipse_beveled_ring_y(
        "Bombenschuetze_Frontring", -0.05,
        (
            (front_y, 0.200, 0.180),
            (front_y + 0.015, 0.165, 0.155),
            (front_y + 0.030, 0.138, 0.138),
        ),
        FRAME, NOSE_SEGMENTS
    )


def cockpit_interior():
    """Stilisierter, räumlich korrekter B-29-Vorderdruckraum."""
    # Gemeinsamer Flugdeckboden. Der Bombenschütze sitzt davor und etwas tiefer,
    # Pilot und Copilot nebeneinander auf dem erhöhten Deck.
    box("Cockpitboden", (1.14, 1.54, 0.060), (0.0, -0.30, -0.36),
        INTERIOR, bevel=0.025)
    box("Bombenschuetze_Boden", (0.62, 0.52, 0.055), (0.0, 0.66, -0.39),
        INTERIOR, rotation=(math.radians(4), 0.0, 0.0), bevel=0.025)

    # Zwei getrennte Instrumententafeln statt eines generischen durchgehenden
    # Bretts. Dazwischen sitzt der typische hohe Mittel-/Gashebelblock.
    for side in (-1.0, 1.0):
        x = side * 0.30
        box(
            "Instrumententafel_Pilot" if side < 0 else "Instrumententafel_Copilot",
            (0.48, 0.075, 0.36),
            (x, 0.12, -0.005),
            INTERIOR,
            rotation=(math.radians(-9), 0.0, 0.0),
            bevel=0.025,
        )
        for row, z in enumerate((0.070, -0.035)):
            for col, dx in enumerate((-0.15, -0.05, 0.05, 0.15)):
                cylinder(
                    "Cockpitinstrument_%s_%d_%d"
                    % ("L" if side < 0 else "R", row, col),
                    0.037,
                    0.018,
                    (x + dx, 0.164, z),
                    (0.0, 1.0, 0.0),
                    GAUGE,
                    16,
                    0.002,
                )

    box("Mittelkonsole", (0.17, 0.68, 0.19), (0.0, -0.12, -0.285),
        INTERIOR, bevel=0.025)
    box("Gashebelquadrant", (0.15, 0.20, 0.095), (0.0, 0.035, -0.145),
        INTERIOR, rotation=(math.radians(-10), 0.0, 0.0), bevel=0.018)
    for lever, x in enumerate((-0.055, -0.018, 0.018, 0.055)):
        curve_tube(
            "Gashebel_%d" % lever,
            [
                Vector((x, 0.035, -0.115)),
                Vector((x, 0.075, -0.035)),
            ],
            INTERIOR,
            0.010,
        )
        sphere("Gashebelknauf_%d" % lever, 0.019, (x, 0.078, -0.026),
               (1.0, 0.80, 1.0), SWITCH)

    for side in (-1.0, 1.0):
        x = side * 0.30
        role = "Pilot" if side < 0 else "Copilot"
        box("%s_Sitzflaeche" % role, (0.31, 0.38, 0.10), (x, -0.34, -0.25),
            SEAT, bevel=0.035)
        box("%s_Sitzlehne" % role, (0.32, 0.12, 0.46), (x, -0.54, -0.04),
            SEAT, rotation=(math.radians(-7), 0.0, 0.0), bevel=0.045)
        box("%s_Rueckenpolster" % role, (0.25, 0.055, 0.33), (x, -0.475, -0.025),
            LEATHER, rotation=(math.radians(-7), 0.0, 0.0), bevel=0.04)
        box("%s_Kopfstuetze" % role, (0.24, 0.075, 0.12), (x, -0.51, 0.19),
            LEATHER, bevel=0.035)

        # B-29-Steuersäule mit großem rundem Steuerhorn statt T-Griff.
        curve_tube(
            "%s_Steuersaeule" % role,
            [
                Vector((x, -0.25, -0.35)),
                Vector((x, -0.17, -0.21)),
                Vector((x, -0.08, -0.085)),
            ],
            INTERIOR,
            0.018,
        )
        torus_y("%s_Steuerhorn" % role, -0.045, 0.105, 0.013, RUBBER,
                z_scale=0.78, z=-0.065, x=x)
        cylinder("%s_Steuerhornnabe" % role, 0.026, 0.052,
                 (x, -0.045, -0.065), (0.0, 1.0, 0.0), INTERIOR, 16)
        for dx, dz in ((-0.080, 0.0), (0.080, 0.0), (0.0, 0.064), (0.0, -0.064)):
            curve_tube(
                "%s_Steuerhornspeiche" % role,
                [Vector((x, -0.045, -0.065)),
                 Vector((x + dx, -0.045, -0.065 + dz))],
                INTERIOR,
                0.009,
            )

        # Je zwei Pedale unter der Instrumententafel.
        for pedal in (-1.0, 1.0):
            box(
                "%s_Ruderpedal" % role,
                (0.075, 0.035, 0.115),
                (x + pedal * 0.060, 0.145, -0.295),
                RUBBER,
                rotation=(math.radians(-18), 0.0, 0.0),
                bevel=0.012,
            )

    # Bombenschützenplatz ganz vorn und tiefer: Klappsitz, Arbeitstisch und
    # detaillierter Norden-Bombensichtkopf direkt hinter der Rundscheibe.
    box("Bombenschuetze_Sitz", (0.30, 0.28, 0.07), (0.0, 0.56, -0.35),
        LEATHER, bevel=0.04)
    box("Bombenschuetze_Lehne", (0.28, 0.075, 0.30), (0.0, 0.43, -0.19),
        SEAT, rotation=(math.radians(-8), 0.0, 0.0), bevel=0.035)
    box("Bombenschuetze_Tisch", (0.44, 0.26, 0.040), (0.0, 0.70, -0.15),
        INTERIOR, rotation=(math.radians(8), 0.0, 0.0), bevel=0.018)
    cylinder("Norden_Stativ", 0.028, 0.25, (0.0, 0.84, -0.235),
             (0.0, 0.0, 1.0), INTERIOR, 16, 0.003)
    box("Norden_Gyrogehaeuse", (0.16, 0.15, 0.12), (0.0, 0.87, -0.08),
        INTERIOR, bevel=0.025)
    cylinder("Norden_Optik", 0.045, 0.22, (0.0, 0.99, -0.065),
             (0.0, 1.0, 0.0), INTERIOR, 20, 0.003)
    cylinder("Norden_Okular", 0.058, 0.050, (0.0, 1.105, -0.065),
             (0.0, 1.0, 0.0), RUBBER, 20, 0.003)
    for side in (-1.0, 1.0):
        curve_tube(
            "Norden_Handgriff",
            [
                Vector((side * 0.065, 0.87, -0.08)),
                Vector((side * 0.105, 0.92, -0.10)),
            ],
            RUBBER,
            0.012,
        )

    # Navigator links hinter dem Piloten: Kartentisch, Kartenblatt und Leselampe.
    box("Navigator_Kartentisch", (0.44, 0.48, 0.045), (-0.43, -0.83, -0.08),
        INTERIOR, bevel=0.022)
    box("Navigator_Karte", (0.34, 0.36, 0.009), (-0.43, -0.80, -0.052),
        MAP, bevel=0.008)
    cylinder("Navigator_Leselampe", 0.025, 0.22, (-0.60, -0.77, 0.05),
             (0.0, 0.0, 1.0), INTERIOR, 12, 0.002)
    sphere("Navigator_Lampenkopf", 0.040, (-0.60, -0.77, 0.17),
           (1.0, 1.0, 0.75), GAUGE)

    # Flugingenieur rechts hinter dem Copiloten, zur hohen Seitenwand gedreht.
    box("Flugingenieur_Panel", (0.055, 0.58, 0.62), (0.62, -0.77, 0.025),
        INTERIOR, bevel=0.025)
    for row, z in enumerate((-0.14, -0.01, 0.12, 0.25)):
        for col, y in enumerate((-0.96, -0.82, -0.68, -0.54)):
            cylinder(
                "Flugingenieur_Instrument_%d_%d" % (row, col),
                0.030,
                0.020,
                (0.585, y, z),
                (1.0, 0.0, 0.0),
                GAUGE,
                14,
                0.002,
            )
    box("Flugingenieur_Sitz", (0.26, 0.26, 0.075), (0.35, -0.78, -0.29),
        SEAT, bevel=0.035)

    # Schmale Dachkonsole und der runde Zugang zum Drucktunnel über den
    # Bombenschächten, zwei besonders charakteristische B-29-Merkmale.
    box("Dachkonsole", (0.42, 0.44, 0.050), (0.0, -0.04, 0.57),
        INTERIOR, rotation=(math.radians(4), 0.0, 0.0), bevel=0.018)
    for i, x in enumerate((-0.12, -0.04, 0.04, 0.12)):
        box("Dachschalter_%d" % i, (0.025, 0.055, 0.025), (x, -0.02, 0.535),
            SWITCH, bevel=0.006)
    torus_y("Drucktunnel_Rahmen", -1.31, 0.185, 0.028, INTERIOR,
            z_scale=1.0, z=0.10)
    ellipse_disc_y("Drucktunnel_Dunkel", -1.335, 0.10, 0.157, 0.157,
                   RUBBER, 24)

    required = {
        "Instrumententafel_Pilot",
        "Instrumententafel_Copilot",
        "Pilot_Steuerhorn",
        "Copilot_Steuerhorn",
        "Norden_Gyrogehaeuse",
        "Navigator_Kartentisch",
        "Flugingenieur_Panel",
        "Drucktunnel_Rahmen",
    }
    missing = sorted(name for name in required if bpy.data.objects.get(name) is None)
    if missing:
        raise RuntimeError("B-29-Cockpitstationen fehlen: " + ", ".join(missing))


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
    reserved = {"B29_Nasenhaut"}
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
        elif names and names <= {"glass"}:
            groups["B29_Glasdetails"].append(obj)
        elif names and names <= {"frame"}:
            groups["B29_Rahmendetails"].append(obj)
        else:
            groups["B29_Innenraum"].append(obj)
    for name, objects in groups.items():
        join_group(objects, name)


def weld_nose_to_fuselage():
    """Nasenhaut und Zylinder an ihrem identischen 12er-Ring wirklich verschweißen."""
    nose = bpy.data.objects.get("B29_Nasenhaut")
    fuselage = bpy.data.objects.get("B29_Rumpf_komplett")
    if nose is None or fuselage is None:
        raise RuntimeError("B-29-Nasenhaut oder Rumpfgruppe fehlt vor dem Verschweißen")
    bpy.ops.object.select_all(action="DESELECT")
    nose.select_set(True)
    fuselage.select_set(True)
    bpy.context.view_layer.objects.active = nose
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = "B29_Rumpf_mit_Nase"

    # Die beiden Anschlussringe besitzen exakt dieselben zwölf Koordinaten.
    # remove_doubles macht daraus gemeinsame Vertices; anschließend ist die
    # Außenhaut topologisch ein einziges geschlossenes Mesh.
    bm = bmesh.new()
    bm.from_mesh(joined.data)
    before = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.00001)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    after = len(bm.verts)
    bm.to_mesh(joined.data)
    bm.free()
    joined.data.update()
    if before - after < NOSE_SEGMENTS:
        raise RuntimeError(
            "Mindestens %d verschweißte Nahtpunkte erwartet, erhalten: %d"
            % (NOSE_SEGMENTS, before - after)
        )


def build():
    clear()
    fuselage_shell()
    cockpit_interior()
    faceted_glass_nose()
    apply_modifiers()
    consolidate_objects()
    weld_nose_to_fuselage()
    bpy.ops.export_scene.gltf(filepath=str(OUT), export_format="GLB", export_yup=True)
    print("EXPORTED", OUT)


if __name__ == "__main__":
    build()
