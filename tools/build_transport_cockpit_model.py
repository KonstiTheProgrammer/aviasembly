"""Baut ein eigenständiges modernes Transportflugzeug-Cockpit im Aviassembly-Stil.

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
SEGMENTS = 12


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


# Blender speichert die Basisfarben linear; diese Werte ergeben im Godot-Import
# etwa das kühle Mittelgrau und das fast schwarze Blau des Konzeptbilds.
BODY = material("cockpit_body", (0.105, 0.135, 0.180, 1.0), 0.28, 0.50)
BODY_DARK = material("body_detail", (0.035, 0.050, 0.075, 1.0), 0.22, 0.58)
FRAME = material("frame", (0.060, 0.080, 0.110, 1.0), 0.34, 0.42)
GLASS = material("glass", (0.0012, 0.0025, 0.0060, 1.0), 0.0, 0.55)
RUBBER = material("rubber", (0.018, 0.022, 0.028, 1.0), 0.0, 0.88)


# y, horizontaler Radius, vertikaler Radius, Z-Mitte.
# Die letzten beiden Querschnitte sind identisch: gerader Rumpfkragen mit
# ebener Rückseite. Die vorderen Stationen formen die kurze, tiefe Transportnase.
HULL_STATIONS = (
    (1.55, 0.13, 0.17, -0.23),
    (1.30, 0.45, 0.38, -0.18),
    (0.98, 0.73, 0.58, -0.10),
    (0.36, 0.98, 0.80, 0.02),
    (-0.10, 1.08, 0.91, 0.06),
    (-0.55, 1.10, 0.93, 0.07),
    (-1.40, 1.10, 0.93, 0.07),
)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def mesh_object_multi(name, verts, face_data, materials):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], [face for face, _material_index in face_data])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        obj.data.materials.append(mat)
    for polygon, (_face, material_index) in zip(obj.data.polygons, face_data):
        polygon.material_index = material_index
        polygon.use_smooth = False
    return obj


def box(name, size, loc, mat, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel > 0.0:
        mod = obj.modifiers.new("Kantenrundung", "BEVEL")
        mod.width = bevel
        mod.segments = 2
    return obj


def cylinder(name, radius, depth, loc, axis, mat, vertices=12):
    direction = Vector(axis).normalized()
    rotation = direction.to_track_quat("Z", "Y").to_euler()
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rotation
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    return obj


def fin_wedge(name, size, loc, mat):
    """Niedrige dreieckige Antenne statt eines aufgesetzten Würfels."""
    width, length, height = size
    x0 = -width * 0.5
    x1 = width * 0.5
    y0 = -length * 0.5
    y1 = length * 0.5
    verts = (
        (x0, y0, 0.0), (x1, y0, 0.0),
        (x0, y1, 0.0), (x1, y1, 0.0),
        (x0, y0 + length * 0.34, height),
        (x1, y0 + length * 0.34, height),
    )
    faces = (
        (0, 1, 3, 2),
        (0, 4, 5, 1),
        (2, 3, 5, 4),
        (0, 2, 4),
        (1, 5, 3),
    )
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    obj.data.materials.append(mat)
    return obj


def squircle(value, power=0.70):
    """Leicht abgeflachte Superellipse für einen modernen Frachtrumpf."""
    if abs(value) < 0.000001:
        return 0.0
    return math.copysign(abs(value) ** power, value)


def hull_point(row, segment_f, axial_f=0.0, lift=1.0):
    row2 = min(row + 1, len(HULL_STATIONS) - 1)
    a = HULL_STATIONS[row]
    b = HULL_STATIONS[row2]
    y = a[0] + (b[0] - a[0]) * axial_f
    rx = (a[1] + (b[1] - a[1]) * axial_f) * lift
    rz = (a[2] + (b[2] - a[2]) * axial_f) * lift
    zc = a[3] + (b[3] - a[3]) * axial_f
    angle = math.tau * segment_f / SEGMENTS
    return (
        squircle(math.cos(angle)) * rx,
        y,
        zc + squircle(math.sin(angle)) * rz,
    )


def is_window(row, segment):
    # Ein einziges, umlaufendes Band aus sechs Front-/Seitenscheiben.
    return row == 2 and segment in range(6)


def build_hull():
    verts = []
    faces = []
    window_count = 0

    for row in range(len(HULL_STATIONS) - 1):
        for segment in range(SEGMENTS):
            corners = (
                hull_point(row, segment, 0.0),
                hull_point(row, segment + 1, 0.0),
                hull_point(row, segment + 1, 1.0),
                hull_point(row, segment, 1.0),
            )
            if not is_window(row, segment):
                base = len(verts)
                verts.extend(corners)
                # Die kurze Radomspitze ist dunkler, aber Teil derselben Außenhaut.
                mat_index = 3 if row <= 1 else 0
                faces.append(((base, base + 1, base + 2, base + 3), mat_index))
                continue

            window_count += 1
            inset = 0.095
            pane = (
                hull_point(row, segment + inset, inset, 1.004),
                hull_point(row, segment + 1.0 - inset, inset, 1.004),
                hull_point(row, segment + 1.0 - inset, 1.0 - inset, 1.004),
                hull_point(row, segment + inset, 1.0 - inset, 1.004),
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

    # Blunt geschlossene Front und ebene Rumpf-Andockfläche.
    front_center = len(verts)
    fy, _frx, _frz, fzc = HULL_STATIONS[0]
    verts.append((0.0, fy, fzc))
    rear_ring = (len(HULL_STATIONS) - 1) * SEGMENTS
    # Für die Kappen separate Ringpunkte anlegen, weil die Panelzellen bewusst
    # unabhängige Vertices besitzen.
    front_cap_ring = []
    rear_cap_ring = []
    for segment in range(SEGMENTS):
        front_cap_ring.append(len(verts))
        verts.append(hull_point(0, segment, 0.0))
        rear_cap_ring.append(len(verts))
        verts.append(hull_point(len(HULL_STATIONS) - 1, segment, 0.0))
    rear_center = len(verts)
    ry, _rrx, _rrz, rzc = HULL_STATIONS[-1]
    verts.append((0.0, ry, rzc))
    for segment in range(SEGMENTS):
        nxt = (segment + 1) % SEGMENTS
        faces.append(((front_center, front_cap_ring[segment], front_cap_ring[nxt]), 3))
        faces.append(((rear_center, rear_cap_ring[nxt], rear_cap_ring[segment]), 0))

    if window_count != 6:
        raise RuntimeError(f"Sechs Transport-Cockpitfenster erwartet, erhalten: {window_count}")
    hull = mesh_object_multi(
        "Transport_Cockpit_Hull", verts, faces, (BODY, FRAME, GLASS, BODY_DARK)
    )
    return hull


def build_details():
    details = []

    # Crew-Türkonturen auf beiden Seiten des geraden Rumpfkragens.
    for side in (-1.0, 1.0):
        x = side * 1.106
        for name, size, loc in (
            ("oben", (0.012, 0.48, 0.018), (x, -0.88, 0.27)),
            ("unten", (0.012, 0.48, 0.018), (x, -0.88, -0.35)),
            ("vorn", (0.012, 0.018, 0.62), (x, -0.65, -0.04)),
            ("hinten", (0.012, 0.018, 0.62), (x, -1.11, -0.04)),
        ):
            details.append(box(
                f"Seitentuer_{'R' if side > 0 else 'L'}_{name}",
                size, loc, BODY_DARK, bevel=0.004
            ))
        details.append(box(
            f"Seitentuergriff_{'R' if side > 0 else 'L'}",
            (0.018, 0.085, 0.022), (x + side * 0.007, -0.72, -0.01),
            FRAME, bevel=0.004
        ))

    # Zwei niedrige Antennen und kurze Pitotrohre geben Maßstab, ohne die Form zu überladen.
    details.append(fin_wedge(
        "Dachantenne_vorn", (0.065, 0.18, 0.11), (0.0, -0.05, 1.015),
        BODY_DARK
    ))
    details.append(fin_wedge(
        "Dachantenne_hinten", (0.055, 0.14, 0.085), (0.0, -0.48, 1.015),
        BODY_DARK
    ))
    for side in (-1.0, 1.0):
        details.append(cylinder(
            f"Pitot_{'R' if side > 0 else 'L'}", 0.010, 0.22,
            (side * 0.82, 1.01, -0.20), (0.0, 1.0, 0.0), FRAME, 10
        ))
        details.append(box(
            f"Pitotbasis_{'R' if side > 0 else 'L'}",
            (0.038, 0.07, 0.035), (side * 0.82, 0.89, -0.20),
            BODY_DARK, bevel=0.006
        ))

    apply_modifiers(details)
    return join_objects(details, "Transport_Cockpit_Details")


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
    return result


def validate_model(hull, details):
    if hull is None or details is None:
        raise RuntimeError("Transport-Cockpit konnte nicht vollständig gebaut werden")
    if len(hull.data.materials) != 4:
        raise RuntimeError("Außenhaut muss vier klar getrennte Materialslots besitzen")
    rear = HULL_STATIONS[-1]
    previous = HULL_STATIONS[-2]
    if rear[1:] != previous[1:]:
        raise RuntimeError("Rumpfkragen ist nicht gerade")
    if not math.isclose(rear[0], -1.40, abs_tol=0.0001):
        raise RuntimeError("Rückseitige Andockebene liegt nicht bei Y=-1.40")


def export_model():
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT),
        export_format="GLB",
        export_yup=True,
    )


def add_area(name, location, energy, size):
    bpy.ops.object.light_add(type="AREA", location=location)
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    return light


def setup_preview():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 980
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_OUT)
    scene.world.color = (0.035, 0.045, 0.065)
    scene.view_settings.look = "AgX - Medium High Contrast"

    add_area("Preview_Key", (4.2, 4.8, 4.6), 950, 4.0)
    add_area("Preview_Fill", (-4.0, 1.0, 2.5), 520, 3.5)
    add_area("Preview_Rim", (0.0, -4.0, 3.0), 700, 3.0)

    bpy.ops.mesh.primitive_plane_add(size=14.0, location=(0.0, 0.0, -0.875))
    floor = bpy.context.object
    floor.name = "Preview_Floor"
    floor_mat = material("preview_floor", (0.18, 0.21, 0.26, 1.0), 0.0, 0.78)
    floor.data.materials.append(floor_mat)

    bpy.ops.object.camera_add(location=(4.1, 4.9, 2.55))
    camera = bpy.context.object
    camera.name = "Transport_Cockpit_Camera"
    camera.data.lens = 58
    target = Vector((0.0, 0.02, 0.02))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera


def build():
    clear()
    hull = build_hull()
    details = build_details()
    validate_model(hull, details)

    # Vor dem Preview-Aufbau enthält die Szene ausschließlich die beiden Exportgruppen.
    export_model()
    setup_preview()
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    print("EXPORTED", GLB_OUT)
    print("SAVED", BLEND_OUT)
    print("RENDERED", PREVIEW_OUT)


if __name__ == "__main__":
    build()
