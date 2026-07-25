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
    (1.55, 0.14, 0.18, -0.20),
    (1.40, 0.36, 0.34, -0.18),
    (1.16, 0.61, 0.53, -0.12),
    (0.88, 0.83, 0.71, -0.03),
    (0.54, 0.99, 0.84, 0.04),
    (0.12, 1.08, 0.91, 0.07),
    (-0.50, 1.10, 0.93, 0.07),
    (-1.40, 1.10, 0.93, 0.07),
)

# Sieben Begrenzungslinien ergeben sechs symmetrische Scheiben. Die Z-Werte
# bilden die charakteristische geschwungene Fensterkrone und die tiefere
# Unterkante der seitlichen Scheiben.
WINDOW_X = (-0.97, -0.68, -0.36, 0.0, 0.36, 0.68, 0.97)
WINDOW_TOP_Z = (0.49, 0.66, 0.74, 0.77, 0.74, 0.66, 0.49)
WINDOW_BOTTOM_Z = (0.08, 0.18, 0.22, 0.23, 0.22, 0.18, 0.08)


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


def build_hull(materials):
    verts = []
    faces = []

    # Gemeinsame Ring-Vertices sorgen für eine geschlossene, überlappungsfreie Haut.
    for y, _rx, _rz, _zc in HULL_STATIONS:
        for segment in range(SEGMENTS):
            verts.append(section_point(y, segment))

    for row in range(len(HULL_STATIONS) - 1):
        front_y = HULL_STATIONS[row][0]
        rear_y = HULL_STATIONS[row + 1][0]
        for segment in range(SEGMENTS):
            nxt = (segment + 1) % SEGMENTS
            a = row * SEGMENTS + segment
            b = row * SEGMENTS + nxt
            c = (row + 1) * SEGMENTS + nxt
            d = (row + 1) * SEGMENTS + segment
            center = (
                Vector(verts[a]) + Vector(verts[b]) + Vector(verts[c]) + Vector(verts[d])
            ) * 0.25
            y_mid = (front_y + rear_y) * 0.5
            # Dunkler, kurzer Radombug mit ansteigender Trennlinie unter den Fenstern.
            dark_limit = 0.26 + max(0.0, 0.92 - y_mid) * 0.20
            dark = y_mid > 1.10 or (y_mid > 0.70 and center.z < dark_limit)
            faces.append(((a, b, c, d), 1 if dark else 0))

    front_center = len(verts)
    front = HULL_STATIONS[0]
    verts.append((0.0, front[0], front[3]))
    rear_center = len(verts)
    rear = HULL_STATIONS[-1]
    verts.append((0.0, rear[0], rear[3]))
    last_ring = (len(HULL_STATIONS) - 1) * SEGMENTS
    for segment in range(SEGMENTS):
        nxt = (segment + 1) % SEGMENTS
        faces.append(((front_center, segment, nxt), 1))
        faces.append(((rear_center, last_ring + nxt, last_ring + segment), 0))

    return mesh_object_multi(
        "Transport_Cockpit_Hull",
        verts,
        faces,
        (materials["body"], materials["detail"]),
    )


def bilerp(bl, br, tr, tl, u, v):
    bottom = bl.lerp(br, u)
    top = tl.lerp(tr, u)
    return bottom.lerp(top, v)


def window_vertex(x, z, offset_y):
    return Vector((x, front_surface_y(x, z) + offset_y, z))


def planar_window(bl, br, tr, tl):
    """Legt eine Scheibe auf ihre eigene saubere Tangentialfacette."""
    points = (bl, br, tr, tl)
    center = sum(points, Vector()) * 0.25
    right = ((br - bl) + (tr - tl)).normalized()
    up = ((tl - bl) + (tr - br)).normalized()
    normal = up.cross(right).normalized()
    if normal.y < 0.0:
        normal.negate()

    # Nicht nur die vier Ecken prüfen: Die konvexe Bughaut wölbt sich zwischen
    # ihnen weiter nach außen. Ein 9x9-Raster bestimmt den nötigen Versatz.
    maximum_bulge = -1000.0
    bl_xz = Vector((bl.x, bl.z))
    br_xz = Vector((br.x, br.z))
    tr_xz = Vector((tr.x, tr.z))
    tl_xz = Vector((tl.x, tl.z))
    for u_index in range(9):
        u = u_index / 8.0
        bottom = bl_xz.lerp(br_xz, u)
        top = tl_xz.lerp(tr_xz, u)
        for v_index in range(9):
            xz = bottom.lerp(top, v_index / 8.0)
            skin = Vector((xz.x, front_surface_y(xz.x, xz.y), xz.y))
            maximum_bulge = max(maximum_bulge, (skin - center).dot(normal))
    push = maximum_bulge + 0.006

    plane_points = []
    for point in points:
        projected = point - normal * (point - center).dot(normal)
        plane_points.append(projected + normal * push)
    return (*plane_points, normal)


def build_windows(materials):
    verts = []
    faces = []

    for pane in range(6):
        skin = (
            window_vertex(WINDOW_X[pane], WINDOW_BOTTOM_Z[pane], 0.0),
            window_vertex(WINDOW_X[pane + 1], WINDOW_BOTTOM_Z[pane + 1], 0.0),
            window_vertex(WINDOW_X[pane + 1], WINDOW_TOP_Z[pane + 1], 0.0),
            window_vertex(WINDOW_X[pane], WINDOW_TOP_Z[pane], 0.0),
        )
        bl, br, tr, tl, normal = planar_window(*skin)

        inset_u = 0.055
        inset_v = 0.060
        ibl = bilerp(bl, br, tr, tl, inset_u, inset_v)
        ibr = bilerp(bl, br, tr, tl, 1.0 - inset_u, inset_v)
        itr = bilerp(bl, br, tr, tl, 1.0 - inset_u, 1.0 - inset_v)
        itl = bilerp(bl, br, tr, tl, inset_u, 1.0 - inset_v)

        frame_outer = [point + normal * 0.003 for point in (bl, br, tr, tl)]
        frame_inner = [point + normal * 0.003 for point in (ibl, ibr, itr, itl)]
        glass = [point - normal * 0.002 for point in (ibl, ibr, itr, itl)]
        skin_outer = [point + normal * 0.002 for point in skin]

        base = len(verts)
        verts.extend(frame_outer)
        verts.extend(frame_inner)
        verts.extend(glass)
        verts.extend(skin_outer)
        faces.extend(
            (
                ((base + 0, base + 4, base + 5, base + 1), 0),
                ((base + 1, base + 5, base + 6, base + 2), 0),
                ((base + 2, base + 6, base + 7, base + 3), 0),
                ((base + 3, base + 7, base + 4, base + 0), 0),
                ((base + 8, base + 11, base + 10, base + 9), 1),
                # Facettierte Laibung zurück zur eigentlichen Außenhaut.
                ((base + 0, base + 1, base + 13, base + 12), 0),
                ((base + 1, base + 2, base + 14, base + 13), 0),
                ((base + 2, base + 3, base + 15, base + 14), 0),
                ((base + 3, base + 0, base + 12, base + 15), 0),
            )
        )

    return mesh_object_multi(
        "Windshield_Assembly",
        verts,
        faces,
        (materials["frame"], materials["glass"]),
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


def ring_strip(name, y_front, y_rear, mat, lift=1.004):
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


def front_plate(name, x0, x1, z0, z1, mat, offset=0.034):
    bl = window_vertex(x0, z0, offset)
    br = window_vertex(x1, z0, offset)
    tr = window_vertex(x1, z1, offset)
    tl = window_vertex(x0, z1, offset)
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata((bl, tl, tr, br), [], ((0, 1, 2, 3),))
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def side_outline(prefix, side, center_y, center_z, width_y, height_z, mat):
    x = side * 1.106
    thickness = 0.012
    line = 0.018
    return [
        box(
            prefix + "_oben",
            (thickness, width_y, line),
            (x, center_y, center_z + height_z * 0.5),
            mat,
            bevel=0.004,
        ),
        box(
            prefix + "_unten",
            (thickness, width_y, line),
            (x, center_y, center_z - height_z * 0.5),
            mat,
            bevel=0.004,
        ),
        box(
            prefix + "_vorn",
            (thickness, line, height_z),
            (x, center_y + width_y * 0.5, center_z),
            mat,
            bevel=0.004,
        ),
        box(
            prefix + "_hinten",
            (thickness, line, height_z),
            (x, center_y - width_y * 0.5, center_z),
            mat,
            bevel=0.004,
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
                (side * 1.116, -0.73, -0.04),
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

    # Dunkler, schmaler Sensor-/Lüftungsschlitz unter den mittleren Scheiben.
    details.append(
        front_plate(
            "Frontschlitz",
            -0.17,
            0.17,
            0.08,
            0.135,
            materials["detail"],
        )
    )

    # Flacher Dachkasten und kleiner Antennenzapfen aus der Nahaufnahme.
    details.append(
        box(
            "Dachkasten",
            (0.30, 0.25, 0.10),
            (0.0, -0.02, 1.035),
            materials["frame"],
            bevel=0.025,
        )
    )
    details.append(
        cylinder(
            "Dachantenne",
            0.026,
            0.105,
            (0.0, -0.43, 1.055),
            (0.0, 0.0, 1.0),
            materials["detail"],
            12,
        )
    )

    # Zwei kurze, unaufdringliche Messsonden geben dem Cockpit Maßstab.
    for side in (-1.0, 1.0):
        details.append(
            cylinder(
                "Pitot_" + ("R" if side > 0.0 else "L"),
                0.009,
                0.18,
                (side * 0.86, 0.57, -0.13),
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
    if not math.isclose(size.z, 1.86, abs_tol=0.0001):
        raise RuntimeError(f"Rumpfhöhe muss 1,86 m sein, erhalten: {size.z}")
    if not math.isclose(size.y, 2.95, abs_tol=0.0001):
        raise RuntimeError(f"Buglänge muss 2,95 m sein, erhalten: {size.y}")
    if not math.isclose(minimum.y, -1.40, abs_tol=0.0001):
        raise RuntimeError(f"Andockebene muss bei Y=-1,40 liegen, erhalten: {minimum.y}")
    if HULL_STATIONS[-1][1:] != HULL_STATIONS[-2][1:]:
        raise RuntimeError("Hinterer Rumpfkragen ist nicht gerade")
    glass_faces = sum(
        1
        for polygon in details.data.polygons
        if details.data.materials[polygon.material_index].name == "glass"
    )
    if glass_faces != 6:
        raise RuntimeError(f"Sechs Scheiben erwartet, erhalten: {glass_faces}")


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
        (3.75, 4.65, 2.25),
        (0.0, 0.30, 0.05),
        PREVIEW_OUT,
        67,
    )
    render_view(
        camera,
        (0.0, 5.25, 0.45),
        (0.0, 0.30, 0.02),
        FRONT_OUT,
        72,
    )
    render_view(
        camera,
        (5.20, 0.05, 0.55),
        (0.0, 0.10, 0.02),
        SIDE_OUT,
        72,
    )
    # Beim Öffnen erscheint wieder die aussagekräftige Dreiviertelansicht.
    camera.location = (3.75, 4.65, 2.25)
    camera.data.lens = 67
    camera.rotation_euler = (
        Vector((0.0, 0.30, 0.05)) - camera.location
    ).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    print("EXPORTED", GLB_OUT)
    print("SAVED", BLEND_OUT)
    print("RENDERED", PREVIEW_OUT, FRONT_OUT, SIDE_OUT)


if __name__ == "__main__":
    build()
