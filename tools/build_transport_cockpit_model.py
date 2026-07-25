"""Baut das moderne Transportflugzeug-Cockpit vollständig neu.

Die Form folgt der engen Front-Dreiviertel-Referenz:
kurzer dunkler Radombug, sechs umlaufende Scheiben, facettierte Dachschulter,
gerader Frachtrumpf-Anschluss und wenige klar lesbare Außendetails.

Blender-Koordinaten:
    X = Breite, Y = Flugrichtung/vorne, Z = oben.
Beim glTF-Export mit Y-up wird Blender +Y zu Godot -Z.
"""

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
BLEND_OUT = ROOT / "blender_lib" / "transport_cockpit.blend"
GLB_OUT = ROOT / "models" / "cockpit_transport.glb"
PREVIEW_OUT = ROOT / "tools" / "transport_cockpit_preview.png"
FRONT_OUT = ROOT / "tools" / "transport_cockpit_front.png"
SIDE_OUT = ROOT / "tools" / "transport_cockpit_side.png"

SEGMENTS = 12
SQUIRCLE_POWER = 0.70

# y, horizontaler Radius, vertikaler Radius, Z-Mitte.
# Die letzten beiden Stationen sind identisch und bilden den exakt geraden
# Rumpfkragen. Gesamtlänge 2,95 m; Heckebene bei Y=-1,40.
HULL_STATIONS = (
    (1.55, 0.13, 0.18, -0.20),
    (1.38, 0.31, 0.35, -0.15),
    (1.12, 0.57, 0.59, -0.05),
    (0.84, 0.80, 0.82, 0.03),
    (0.50, 0.98, 0.98, 0.08),
    (0.12, 1.08, 1.04, 0.09),
    (-0.50, 1.10, 1.06, 0.09),
    (-1.40, 1.10, 1.06, 0.09),
)

# Sieben Begrenzungslinien ergeben sechs symmetrische Scheiben. Die Z-Werte
# bilden die charakteristische geschwungene Fensterkrone und die tiefere
# Unterkante der seitlichen Scheiben.
WINDOW_X = (-1.035, -0.74, -0.40, 0.0, 0.40, 0.74, 1.035)
WINDOW_TOP_Z = (0.52, 0.68, 0.76, 0.79, 0.76, 0.68, 0.52)
WINDOW_BOTTOM_Z = (0.19, 0.29, 0.33, 0.34, 0.33, 0.29, 0.19)


def material(name, color, metallic=0.0, roughness=0.45):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = False
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    mat.diffuse_color = color
    return mat


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.materials,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def make_materials():
    # Die linearen Blender-Werte ergeben das kühle Mittelgrau des Spielstils.
    materials = {
        "body": material("cockpit_body", (0.155, 0.178, 0.215, 1.0), 0.26, 0.52),
        "detail": material("body_detail", (0.035, 0.047, 0.065, 1.0), 0.18, 0.62),
        "frame": material("frame", (0.105, 0.122, 0.145, 1.0), 0.30, 0.44),
        "glass": material("glass", (0.0012, 0.0025, 0.0060, 1.0), 0.0, 0.72),
        "rubber": material("rubber", (0.012, 0.016, 0.022, 1.0), 0.0, 0.88),
    }
    glass_bsdf = materials["glass"].node_tree.nodes.get("Principled BSDF")
    specular = (
        glass_bsdf.inputs.get("Specular IOR Level")
        or glass_bsdf.inputs.get("IOR Level")
    )
    if specular is not None:
        specular.default_value = 0.0
    return materials


def squircle(value, power=SQUIRCLE_POWER):
    if abs(value) < 0.000001:
        return 0.0
    return math.copysign(abs(value) ** power, value)


def station_values(y):
    """Interpoliert den Rumpfquerschnitt an einer beliebigen Y-Position."""
    if y >= HULL_STATIONS[0][0]:
        return HULL_STATIONS[0][1:]
    if y <= HULL_STATIONS[-1][0]:
        return HULL_STATIONS[-1][1:]
    for front, rear in zip(HULL_STATIONS, HULL_STATIONS[1:]):
        if front[0] >= y >= rear[0]:
            span = front[0] - rear[0]
            t = 0.0 if span <= 0.000001 else (front[0] - y) / span
            return tuple(
                front[index] + (rear[index] - front[index]) * t
                for index in range(1, 4)
            )
    raise RuntimeError(f"Kein Rumpfquerschnitt für Y={y}")


def section_point(y, segment_f, lift=1.0):
    rx, rz, zc = station_values(y)
    angle = math.tau * segment_f / SEGMENTS
    return (
        squircle(math.cos(angle)) * rx * lift,
        y,
        zc + squircle(math.sin(angle)) * rz * lift,
    )


def section_point_angle(y, angle, lift=1.0):
    rx, rz, zc = station_values(y)
    return Vector(
        (
            squircle(math.cos(angle)) * rx * lift,
            y,
            zc + squircle(math.sin(angle)) * rz * lift,
        )
    )


def cross_section_error(y, x, z):
    rx, rz, zc = station_values(y)
    exponent = 2.0 / SQUIRCLE_POWER
    return (abs(x / rx) ** exponent) + (abs((z - zc) / rz) ** exponent) - 1.0


def side_surface_x(y, z, side, outset=0.0):
    """Projiziert ein Seitendetail exakt auf die örtliche Außenhaut."""
    rx, rz, zc = station_values(y)
    exponent = 2.0 / SQUIRCLE_POWER
    ratio = min(abs((z - zc) / rz), 1.0)
    x_abs = rx * max(0.0, 1.0 - ratio**exponent) ** (1.0 / exponent)
    return side * (x_abs + outset)


def roof_surface_z(y, x=0.0):
    """Liefert die Dachhöhe des Superellipse-Querschnitts."""
    rx, rz, zc = station_values(y)
    exponent = 2.0 / SQUIRCLE_POWER
    ratio = min(abs(x / rx), 1.0)
    z_abs = rz * max(0.0, 1.0 - ratio**exponent) ** (1.0 / exponent)
    return zc + z_abs


def front_surface_y(x, z):
    """Findet die vorderste Außenhautposition für einen X/Z-Punkt."""
    low = HULL_STATIONS[-2][0]
    high = HULL_STATIONS[0][0]
    if cross_section_error(low, x, z) > 0.0:
        raise RuntimeError(f"Fensterpunkt liegt außerhalb des Rumpfes: {(x, z)}")
    for _index in range(64):
        mid = (low + high) * 0.5
        if cross_section_error(mid, x, z) <= 0.0:
            low = mid
        else:
            high = mid
    return low


def mesh_object_multi(name, verts, face_data, materials):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], [face for face, _mat_index in face_data])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        obj.data.materials.append(mat)
    for polygon, (_face, material_index) in zip(mesh.polygons, face_data):
        polygon.material_index = material_index
        polygon.use_smooth = False
    return obj


def front_boundary_z(x, upper):
    """Z-Wert des vorderen Anschlussquerschnitts bei Y=0,12."""
    rx, rz, zc = station_values(0.12)
    exponent = 2.0 / SQUIRCLE_POWER
    ratio = min(abs(x / rx), 1.0)
    z_abs = rz * max(0.0, 1.0 - ratio**exponent) ** (1.0 / exponent)
    return zc + z_abs * (1.0 if upper else -1.0)


def skin_material(center):
    """Materialindex der Metallhaut: 0 Körper, 1 dunkler Radombug."""
    dark_limit = 0.22 + max(0.0, 0.90 - center.y) * 0.16
    dark = center.y > 1.04 or (center.y > 0.62 and center.z < dark_limit)
    return 1 if dark else 0


def bridge_loops(front_loop, rear_loop, faces, material_index=0):
    """Verbindet zwei gleich ausgerichtete Ringe mit beliebiger Eckenzahl."""
    front_count = len(front_loop)
    rear_count = len(rear_loop)
    front_index = 0
    rear_index = 0
    epsilon = 0.000001
    while front_index < front_count or rear_index < rear_count:
        front_next = (
            (front_index + 1) / front_count
            if front_index < front_count
            else float("inf")
        )
        rear_next = (
            (rear_index + 1) / rear_count
            if rear_index < rear_count
            else float("inf")
        )
        front_now_vertex = front_loop[front_index % front_count]
        rear_now_vertex = rear_loop[rear_index % rear_count]
        if abs(front_next - rear_next) <= epsilon:
            faces.append(
                (
                    (
                        front_now_vertex,
                        front_loop[(front_index + 1) % front_count],
                        rear_loop[(rear_index + 1) % rear_count],
                        rear_now_vertex,
                    ),
                    material_index,
                )
            )
            front_index += 1
            rear_index += 1
        elif front_next < rear_next:
            faces.append(
                (
                    (
                        front_now_vertex,
                        front_loop[(front_index + 1) % front_count],
                        rear_now_vertex,
                    ),
                    material_index,
                )
            )
            front_index += 1
        else:
            faces.append(
                (
                    (
                        front_now_vertex,
                        rear_loop[(rear_index + 1) % rear_count],
                        rear_now_vertex,
                    ),
                    material_index,
                )
            )
            rear_index += 1


def build_hull(materials):
    """Baut eine einzige Außenhaut, in der das Glas echte Hautflächen ersetzt."""
    verts = []
    faces = []
    grid = []

    # Die Front ist ein strukturiertes X/Z-Netz. Fensterunter- und -oberkante
    # sind echte Netzzeilen; dadurch entstehen exakt sechs bündige Glasflächen.
    for x, window_bottom, window_top in zip(
        WINDOW_X, WINDOW_BOTTOM_Z, WINDOW_TOP_Z
    ):
        z_min = front_boundary_z(x, False)
        z_max = front_boundary_z(x, True)
        nose_row = -0.22 + 0.14 * abs(x / WINDOW_X[-1])
        z_rows = (
            z_min,
            (z_min + nose_row) * 0.5,
            nose_row,
            nose_row * 0.35 + window_bottom * 0.65,
            window_bottom,
            window_top,
            (window_top + z_max) * 0.5,
            z_max,
        )
        column = []
        for z in z_rows:
            column.append(len(verts))
            verts.append((x, front_surface_y(x, z), z))
        grid.append(column)

    band_count = len(grid[0]) - 1
    for column in range(len(grid) - 1):
        for row in range(band_count):
            a = grid[column][row]
            b = grid[column + 1][row]
            c = grid[column + 1][row + 1]
            d = grid[column][row + 1]
            if row == 4:
                material_index = 2
            else:
                center = (
                    Vector(verts[a])
                    + Vector(verts[b])
                    + Vector(verts[c])
                    + Vector(verts[d])
                ) * 0.25
                if row < 4 and center.y > 0.58:
                    material_index = 1
                else:
                    material_index = skin_material(center)
            # Blickrichtung der Frontflächen ist +Y.
            faces.append(((a, d, c, b), material_index))

    rx, _rz, zc = station_values(0.12)
    left_extreme = len(verts)
    verts.append((-rx, 0.12, zc))
    right_extreme = len(verts)
    verts.append((rx, 0.12, zc))
    for row in range(band_count):
        left_lower = grid[0][row]
        left_upper = grid[0][row + 1]
        left_center = (
            Vector(verts[left_extreme])
            + Vector(verts[left_lower])
            + Vector(verts[left_upper])
        ) / 3.0
        faces.append(
            (
                (left_extreme, left_lower, left_upper),
                skin_material(left_center),
            )
        )

        right_lower = grid[-1][row]
        right_upper = grid[-1][row + 1]
        right_center = (
            Vector(verts[right_extreme])
            + Vector(verts[right_lower])
            + Vector(verts[right_upper])
        ) / 3.0
        faces.append(
            (
                (right_extreme, right_upper, right_lower),
                skin_material(right_center),
            )
        )

    # Umlaufender 16-Eck-Rand der neuen Fronttopologie.
    front_boundary = [right_extreme]
    front_boundary.extend(grid[column][-1] for column in range(len(grid) - 1, -1, -1))
    front_boundary.append(left_extreme)
    front_boundary.extend(grid[column][0] for column in range(len(grid)))

    # Kurzer Übergang auf den exakten 12-Eck-Rumpfkragen; dessen hintere
    # 0,90 m bleiben vollständig gerade und passen zum Spiel-Rumpfsegment.
    transition_ring = []
    for segment in range(SEGMENTS):
        transition_ring.append(len(verts))
        verts.append(section_point(-0.50, segment))
    bridge_loops(front_boundary, transition_ring, faces)

    rear_ring = []
    for segment in range(SEGMENTS):
        rear_ring.append(len(verts))
        verts.append(section_point(-1.40, segment))
    for segment in range(SEGMENTS):
        nxt = (segment + 1) % SEGMENTS
        faces.append(
            (
                (
                    transition_ring[segment],
                    transition_ring[nxt],
                    rear_ring[nxt],
                    rear_ring[segment],
                ),
                0,
            )
        )

    rear_center = len(verts)
    rear = HULL_STATIONS[-1]
    verts.append((0.0, rear[0], rear[3]))
    for segment in range(SEGMENTS):
        nxt = (segment + 1) % SEGMENTS
        faces.append(((rear_center, rear_ring[nxt], rear_ring[segment]), 0))

    return mesh_object_multi(
        "Transport_Cockpit_Hull",
        verts,
        faces,
        (materials["body"], materials["detail"], materials["glass"]),
    )


def bilerp(bl, br, tr, tl, u, v):
    bottom = bl.lerp(br, u)
    top = tl.lerp(tr, u)
    return bottom.lerp(top, v)


def window_vertex(x, z, offset_y):
    return Vector((x, front_surface_y(x, z) + offset_y, z))


def build_windows(materials):
    """Baut nur noch die dünnen Rahmen; das Glas steckt bereits in der Haut."""
    verts = []
    faces = []

    for pane in range(6):
        bl = window_vertex(WINDOW_X[pane], WINDOW_BOTTOM_Z[pane], 0.0025)
        br = window_vertex(
            WINDOW_X[pane + 1], WINDOW_BOTTOM_Z[pane + 1], 0.0025
        )
        tr = window_vertex(WINDOW_X[pane + 1], WINDOW_TOP_Z[pane + 1], 0.0025)
        tl = window_vertex(WINDOW_X[pane], WINDOW_TOP_Z[pane], 0.0025)

        inset_u = 0.050
        inset_v = 0.055
        ibl = bilerp(bl, br, tr, tl, inset_u, inset_v)
        ibr = bilerp(bl, br, tr, tl, 1.0 - inset_u, inset_v)
        itr = bilerp(bl, br, tr, tl, 1.0 - inset_u, 1.0 - inset_v)
        itl = bilerp(bl, br, tr, tl, inset_u, 1.0 - inset_v)

        base = len(verts)
        verts.extend((bl, br, tr, tl, ibl, ibr, itr, itl))
        faces.extend(
            (
                ((base + 0, base + 4, base + 5, base + 1), 0),
                ((base + 1, base + 5, base + 6, base + 2), 0),
                ((base + 2, base + 6, base + 7, base + 3), 0),
                ((base + 3, base + 7, base + 4, base + 0), 0),
            )
        )

    return mesh_object_multi(
        "Windshield_Assembly",
        verts,
        faces,
        (materials["frame"],),
    )


def box(name, size, loc, mat, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Kantenrundung", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    return obj


def cylinder(name, radius, depth, loc, axis, mat, vertices=12):
    direction = Vector(axis).normalized()
    rotation = direction.to_track_quat("Z", "Y").to_euler()
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=loc,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def ring_strip(name, y_front, y_rear, mat, lift=1.0015):
    verts = []
    faces = []
    for y in (y_front, y_rear):
        for segment in range(SEGMENTS):
            verts.append(section_point(y, segment, lift))
    for segment in range(SEGMENTS):
        nxt = (segment + 1) % SEGMENTS
        faces.append(
            (
                segment,
                nxt,
                SEGMENTS + nxt,
                SEGMENTS + segment,
            )
        )
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def side_patch(name, side, y_min, y_max, z_min, z_max, mat, z_steps=1):
    """Dünner Nahtstreifen, dessen vier Ecken auf der Seitenhaut liegen."""
    verts = []
    faces = []
    for step in range(z_steps + 1):
        z = z_min + (z_max - z_min) * step / z_steps
        for y in (y_min, y_max):
            verts.append((side_surface_x(y, z, side, 0.0015), y, z))
    for step in range(z_steps):
        base = step * 2
        if side > 0.0:
            faces.append(((base, base + 1, base + 3, base + 2), 0))
        else:
            faces.append(((base, base + 2, base + 3, base + 1), 0))
    return mesh_object_multi(name, verts, faces, (mat,))


def side_outline(prefix, side, center_y, center_z, width_y, height_z, mat):
    """Projizierter Tür-/Deckelrahmen ohne schwebende Kastenfragmente."""
    line = 0.018
    y_min = center_y - width_y * 0.5
    y_max = center_y + width_y * 0.5
    z_min = center_z - height_z * 0.5
    z_max = center_z + height_z * 0.5
    return [
        side_patch(
            prefix + "_oben",
            side,
            y_min,
            y_max,
            z_max - line,
            z_max,
            mat,
        ),
        side_patch(
            prefix + "_unten",
            side,
            y_min,
            y_max,
            z_min,
            z_min + line,
            mat,
        ),
        side_patch(
            prefix + "_vorn",
            side,
            y_max - line,
            y_max,
            z_min + line,
            z_max - line,
            mat,
            4,
        ),
        side_patch(
            prefix + "_hinten",
            side,
            y_min,
            y_min + line,
            z_min + line,
            z_max - line,
            mat,
            4,
        ),
    ]


def apply_modifiers(objects):
    for obj in objects:
        if obj.type != "MESH":
            continue
        bpy.context.view_layer.objects.active = obj
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)


def join_objects(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    for polygon in result.data.polygons:
        polygon.use_smooth = False
    return result


def build_details(materials):
    details = [build_windows(materials)]

    # Zwei feine Segmentringe gliedern den geraden Anschluss wie in der Referenz.
    details.extend(
        (
            ring_strip("Rumpfnaht_vorn", -0.515, -0.535, materials["detail"]),
            ring_strip("Rumpfnaht_hinten", -1.315, -1.335, materials["detail"]),
        )
    )

    # Seitliche Crew-Türen samt Griff; beidseitig für ein vollständiges Spielteil.
    for side in (-1.0, 1.0):
        suffix = "R" if side > 0.0 else "L"
        details.extend(
            side_outline(
                "Crew_Tuer_" + suffix,
                side,
                -0.87,
                -0.08,
                0.46,
                0.64,
                materials["detail"],
            )
        )
        details.append(
            box(
                "Crew_Tuergriff_" + suffix,
                (0.018, 0.078, 0.024),
                (
                    side_surface_x(-0.73, -0.04, side)
                    + side * (0.009 - 0.004),
                    -0.73,
                    -0.04,
                ),
                materials["frame"],
                bevel=0.005,
            )
        )

        # Kleiner Wartungsdeckel direkt hinter/unter dem seitlichen Fenster.
        details.extend(
            side_outline(
                "Wartungsdeckel_" + suffix,
                side,
                -0.22,
                -0.38,
                0.22,
                0.22,
                materials["detail"],
            )
        )

    # Flacher Dachkasten und kleiner Antennenzapfen aus der Nahaufnahme.
    roof_box_size = (0.30, 0.25, 0.10)
    roof_box_bottom = min(
        roof_surface_z(y, x)
        for y in (-0.145, 0.105)
        for x in (-0.15, 0.15)
    ) - 0.003
    details.append(
        box(
            "Dachkasten",
            roof_box_size,
            (0.0, -0.02, roof_box_bottom + roof_box_size[2] * 0.5),
            materials["frame"],
            bevel=0.025,
        )
    )
    antenna_depth = 0.105
    antenna_bottom = roof_surface_z(-0.43) - 0.008
    details.append(
        cylinder(
            "Dachantenne",
            0.026,
            antenna_depth,
            (0.0, -0.43, antenna_bottom + antenna_depth * 0.5),
            (0.0, 0.0, 1.0),
            materials["detail"],
            12,
        )
    )

    # Zwei kurze, unaufdringliche Messsonden geben dem Cockpit Maßstab.
    for side in (-1.0, 1.0):
        pitot_x = side * 0.86
        pitot_z = -0.13
        pitot_depth = 0.18
        pitot_surface = front_surface_y(pitot_x, pitot_z)
        details.append(
            cylinder(
                "Pitot_" + ("R" if side > 0.0 else "L"),
                0.009,
                pitot_depth,
                (pitot_x, pitot_surface + pitot_depth * 0.5 - 0.012, pitot_z),
                (0.0, 1.0, 0.0),
                materials["frame"],
                10,
            )
        )

    apply_modifiers(details)
    return join_objects(details, "Transport_Cockpit_Details")


def mesh_bounds(obj):
    coords = [vertex.co for vertex in obj.data.vertices]
    minimum = Vector(
        (
            min(point.x for point in coords),
            min(point.y for point in coords),
            min(point.z for point in coords),
        )
    )
    maximum = Vector(
        (
            max(point.x for point in coords),
            max(point.y for point in coords),
            max(point.z for point in coords),
        )
    )
    return minimum, maximum


def validate_model(hull, details):
    if hull is None or details is None:
        raise RuntimeError("Transport-Cockpit konnte nicht vollständig gebaut werden")
    minimum, maximum = mesh_bounds(hull)
    size = maximum - minimum
    if not math.isclose(size.x, 2.20, abs_tol=0.0001):
        raise RuntimeError(f"Rumpfbreite muss 2,20 m sein, erhalten: {size.x}")
    if not math.isclose(size.z, 2.12, abs_tol=0.0001):
        raise RuntimeError(f"Rumpfhöhe muss 2,12 m sein, erhalten: {size.z}")
    if not math.isclose(size.y, 2.95, abs_tol=0.0001):
        raise RuntimeError(f"Buglänge muss 2,95 m sein, erhalten: {size.y}")
    if not math.isclose(minimum.y, -1.40, abs_tol=0.0001):
        raise RuntimeError(f"Andockebene muss bei Y=-1,40 liegen, erhalten: {minimum.y}")
    if HULL_STATIONS[-1][1:] != HULL_STATIONS[-2][1:]:
        raise RuntimeError("Hinterer Rumpfkragen ist nicht gerade")
    glass_faces = sum(
        1
        for polygon in hull.data.polygons
        if hull.data.materials[polygon.material_index].name == "glass"
    )
    if glass_faces != 6:
        raise RuntimeError(
            f"Sechs bündige Glasflächen in der Außenhaut erwartet, erhalten: {glass_faces}"
        )
    if any(
        material.name == "glass"
        for material in details.data.materials
        if material is not None
    ):
        raise RuntimeError("Glas darf nicht mehr als aufgesetztes Detailmesh existieren")


def export_model(hull, details):
    bpy.ops.object.select_all(action="DESELECT")
    hull.select_set(True)
    details.select_set(True)
    bpy.context.view_layer.objects.active = hull
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT),
        export_format="GLB",
        export_yup=True,
        use_selection=True,
    )


def add_area(name, location, energy, size, color):
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.data.color = color
    return light


def setup_preview(materials):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world.color = (0.12, 0.20, 0.32)
    scene.view_settings.look = "AgX - Medium High Contrast"

    add_area("Preview_Key", (4.5, 5.2, 4.8), 1150, 4.2, (0.84, 0.92, 1.0))
    add_area("Preview_Fill", (-4.2, 2.0, 2.6), 700, 3.6, (0.58, 0.72, 1.0))
    add_area("Preview_Rim", (0.0, -4.5, 3.5), 850, 3.0, (0.74, 0.84, 1.0))

    bpy.ops.mesh.primitive_plane_add(size=14.0, location=(0.0, 0.0, -0.875))
    floor = bpy.context.object
    floor.name = "Preview_Floor"
    floor_mat = material("preview_floor", (0.25, 0.36, 0.50, 1.0), 0.0, 0.82)
    floor.data.materials.append(floor_mat)

    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.name = "Transport_Cockpit_Camera"
    scene.camera = camera
    return camera


def render_view(camera, location, target, filepath, lens):
    scene = bpy.context.scene
    camera.location = location
    camera.data.lens = lens
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(filepath)
    bpy.ops.render.render(write_still=True)


def build():
    clear()
    materials = make_materials()
    hull = build_hull(materials)
    details = build_details(materials)
    validate_model(hull, details)
    export_model(hull, details)

    camera = setup_preview(materials)
    render_view(
        camera,
        (4.35, 5.35, 2.65),
        (0.0, 0.25, 0.08),
        PREVIEW_OUT,
        65,
    )
    render_view(
        camera,
        (0.0, 6.15, 0.58),
        (0.0, 0.25, 0.08),
        FRONT_OUT,
        68,
    )
    render_view(
        camera,
        (6.30, 0.05, 0.72),
        (0.0, 0.10, 0.07),
        SIDE_OUT,
        65,
    )
    # Beim Öffnen erscheint wieder die aussagekräftige Dreiviertelansicht.
    camera.location = (4.35, 5.35, 2.65)
    camera.data.lens = 65
    camera.rotation_euler = (
        Vector((0.0, 0.25, 0.08)) - camera.location
    ).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    print("EXPORTED", GLB_OUT)
    print("SAVED", BLEND_OUT)
    print("RENDERED", PREVIEW_OUT, FRONT_OUT, SIDE_OUT)


if __name__ == "__main__":
    build()
