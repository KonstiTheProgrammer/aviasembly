"""Build the second, reference-faithful A-10 cockpit module in Blender.

The asset uses the Aviassembly authoring convention: X is width, Z is up and
+Y points toward the nose. Blender's glTF conversion maps +Y to Godot -Z.
"""

import math
import os

import bpy
from mathutils import Vector


PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLEND_PATH = os.path.join(PROJECT_ROOT, "blender_lib/cockpit_a10_v2.blend")
GLB_PATH = os.path.join(PROJECT_ROOT, "models/cockpit_a10_v2.glb")
PREVIEW_PATH = os.path.join(PROJECT_ROOT, "blender_lib/cockpit_a10_v2_preview.png")
SIDE_PREVIEW_PATH = os.path.join(PROJECT_ROOT, "blender_lib/cockpit_a10_v2_side_preview.png")
REFERENCE_PATH = os.path.join(PROJECT_ROOT, "blender_lib/a10_cockpit_reference.png")


def clear_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for scene in bpy.data.scenes:
        scene.world = None
    for collection in list(bpy.data.collections):
        bpy.data.collections.remove(collection)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
        bpy.data.worlds,
    ):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def move_to_collection(obj, collection):
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    collection.objects.link(obj)


def make_material(name, color, metallic=0.0, roughness=0.4, transmission=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = (*color[:3], color[3])
    material.metallic = metallic
    material.roughness = roughness
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        values = {
            "Base Color": color,
            "Metallic": metallic,
            "Roughness": roughness,
            "IOR": 1.46,
            "Alpha": color[3],
            "Transmission Weight": transmission,
            "Coat Weight": 0.16,
            "Coat Roughness": 0.16,
        }
        for socket, value in values.items():
            if socket in bsdf.inputs:
                bsdf.inputs[socket].default_value = value
    if color[3] < 0.999:
        # Blender 4.2+ replaced blend_method with surface_render_method.  The
        # guarded assignment also keeps the builder usable with older Blender.
        if hasattr(material, "surface_render_method"):
            material.surface_render_method = "DITHERED"
        elif hasattr(material, "blend_method"):
            material.blend_method = "BLEND"
        if hasattr(material, "use_transparency_overlap"):
            material.use_transparency_overlap = False
    return material


def mesh_object(name, mesh_name, vertices, faces, collection, material, smooth=True, side_faces=None):
    mesh = bpy.data.meshes.new(mesh_name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = smooth and (side_faces is None or polygon.index < side_faces)
    return obj


def create_beveled_box(name, location, dimensions, collection, material, bevel=0.025, rotation=(0.0, 0.0, 0.0)):
    """Create a compact, manifold low-poly interior component."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    move_to_collection(obj, collection)
    obj.dimensions = dimensions
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("Soft industrial edges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def superellipse_ring(y, rx, rz, center_z, power, segments=20):
    points = []
    exponent = 2.0 / power
    for index in range(segments):
        angle = 2.0 * math.pi * index / segments
        cos_a = math.cos(angle)
        sin_a = math.sin(angle)
        x = rx * math.copysign(abs(cos_a) ** exponent, cos_a)
        z = center_z + rz * math.copysign(abs(sin_a) ** exponent, sin_a)
        points.append((x, y, z))
    return points


def loft_closed(name, sections, collection, material, segments=20, smooth=True):
    vertices = []
    rings = []
    for section in sections:
        ring = superellipse_ring(*section, segments=segments)
        rings.append(list(range(len(vertices), len(vertices) + segments)))
        vertices.extend(ring)

    faces = []
    for station in range(len(rings) - 1):
        current = rings[station]
        following = rings[station + 1]
        for index in range(segments):
            next_index = (index + 1) % segments
            faces.append((current[index], following[index], following[next_index], current[next_index]))
    side_faces = len(faces)
    # Ring order points toward -Y. That is outward on the rear attachment;
    # the front cap therefore needs the opposite winding.
    faces.append(tuple(rings[0]))
    faces.append(tuple(reversed(rings[-1])))
    return mesh_object(
        name,
        f"{name}_Mesh",
        vertices,
        faces,
        collection,
        material,
        smooth=smooth,
        side_faces=side_faces,
    )


def a10_body_ring(y, half_width, top_z, bottom_z):
    """A broad-shouldered slab section with the A-10's nearly flat belly."""
    height = top_z - bottom_z
    return [
        (0.42 * half_width, y, top_z),
        (-0.42 * half_width, y, top_z),
        (-0.82 * half_width, y, top_z - 0.07 * height),
        (-1.00 * half_width, y, top_z - 0.22 * height),
        (-1.00 * half_width, y, bottom_z + 0.18 * height),
        (-0.82 * half_width, y, bottom_z),
        (0.82 * half_width, y, bottom_z),
        (1.00 * half_width, y, bottom_z + 0.18 * height),
        (1.00 * half_width, y, top_z - 0.22 * height),
        (0.82 * half_width, y, top_z - 0.07 * height),
    ]


def loft_a10_body(name, sections, collection, material):
    vertices = []
    rings = []
    for section in sections:
        ring = a10_body_ring(*section)
        rings.append(list(range(len(vertices), len(vertices) + len(ring))))
        vertices.extend(ring)

    faces = []
    ring_size = len(rings[0])
    for station in range(len(rings) - 1):
        for index in range(ring_size):
            following = (index + 1) % ring_size
            faces.append((rings[station][index], rings[station + 1][index], rings[station + 1][following], rings[station][following]))
    side_faces = len(faces)
    faces.append(tuple(rings[0]))
    faces.append(tuple(reversed(rings[-1])))
    return mesh_object(
        name,
        f"{name}_Mesh",
        vertices,
        faces,
        collection,
        material,
        smooth=True,
        side_faces=side_faces,
    )


def arch_points(y, width, base_z, height, segments=12):
    points = []
    for index in range(segments + 1):
        t = -1.0 + 2.0 * index / segments
        crown = max(0.0, 1.0 - t * t) ** 0.40
        points.append((width * t, y, base_z + height * crown))
    return points


def canopy_surface(name, stations, collection, material, segments=12):
    vertices = []
    rings = []
    for station in stations:
        ring = arch_points(*station, segments=segments)
        rings.append(list(range(len(vertices), len(vertices) + len(ring))))
        vertices.extend(ring)

    faces = []
    for station in range(len(rings) - 1):
        current = rings[station]
        following = rings[station + 1]
        for index in range(segments):
            faces.append((current[index], current[index + 1], following[index + 1], following[index]))
    side_faces = len(faces)
    faces.append(tuple(reversed(rings[0])))
    faces.append(tuple(rings[-1]))
    for station in range(len(rings) - 1):
        faces.append((rings[station][0], rings[station + 1][0], rings[station + 1][-1], rings[station][-1]))
    return mesh_object(
        name,
        f"{name}_Mesh",
        vertices,
        faces,
        collection,
        material,
        smooth=True,
        side_faces=side_faces,
    )


def create_poly_beam(name, points, radius, collection, material):
    points = [Vector(point) for point in points]
    tube_segments = 8
    overall = (points[-1] - points[0]).normalized()
    reference = Vector((0.0, 1.0, 0.0)) if abs(overall.y) < 0.85 else Vector((0.0, 0.0, 1.0))
    vertices = []
    rings = []

    for index, point in enumerate(points):
        if index == 0:
            tangent = points[1] - point
        elif index == len(points) - 1:
            tangent = point - points[index - 1]
        else:
            tangent = points[index + 1] - points[index - 1]
        tangent.normalize()
        local_reference = reference
        if abs(tangent.dot(local_reference)) > 0.96:
            local_reference = Vector((1.0, 0.0, 0.0))
        side = tangent.cross(local_reference).normalized()
        up = side.cross(tangent).normalized()
        ring = []
        for segment in range(tube_segments):
            angle = 2.0 * math.pi * segment / tube_segments
            coordinate = point + radius * (math.cos(angle) * side + math.sin(angle) * up)
            ring.append(len(vertices))
            vertices.append(tuple(coordinate))
        rings.append(ring)

    faces = []
    for index in range(len(rings) - 1):
        for segment in range(tube_segments):
            following = (segment + 1) % tube_segments
            faces.append((rings[index][segment], rings[index + 1][segment], rings[index + 1][following], rings[index][following]))
    side_faces = len(faces)
    faces.append(tuple(rings[0]))
    faces.append(tuple(reversed(rings[-1])))
    return mesh_object(
        name,
        f"{name}_Mesh",
        vertices,
        faces,
        collection,
        material,
        smooth=True,
        side_faces=side_faces,
    )


def point_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


clear_scene()

scene = bpy.context.scene
scene.name = "A10_Cockpit_Module_V2"
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"

model_collection = bpy.data.collections.new("MODEL_A10_Cockpit_V2")
scene.collection.children.link(model_collection)
presentation_collection = bpy.data.collections.new("PRESENTATION")
scene.collection.children.link(presentation_collection)

body_material = make_material("cockpit_body", (0.50, 0.53, 0.56, 1.0), metallic=0.32, roughness=0.45)
glass_material = make_material("glass", (0.035, 0.095, 0.135, 0.46), metallic=0.0, roughness=0.11, transmission=0.38)
frame_material = make_material("canopy_frame", (0.040, 0.047, 0.055, 1.0), metallic=0.24, roughness=0.48)
interior_material = make_material("cockpit_interior", (0.018, 0.022, 0.024, 1.0), metallic=0.10, roughness=0.68)
seat_material = make_material("ejection_seat", (0.040, 0.045, 0.033, 1.0), metallic=0.02, roughness=0.80)
instrument_material = make_material("instrument_glass", (0.015, 0.045, 0.052, 1.0), metallic=0.0, roughness=0.20)
floor_material = make_material("Studio_Floor", (0.025, 0.060, 0.105, 1.0), metallic=0.0, roughness=0.82)

glass_bsdf = glass_material.node_tree.nodes.get("Principled BSDF")
if glass_bsdf:
    if "Specular IOR Level" in glass_bsdf.inputs:
        glass_bsdf.inputs["Specular IOR Level"].default_value = 0.34
    if "Coat Weight" in glass_bsdf.inputs:
        glass_bsdf.inputs["Coat Weight"].default_value = 0.28

root = bpy.data.objects.new("A10_Cockpit_V2_Root", None)
model_collection.objects.link(root)
root.empty_display_type = "ARROWS"
root.empty_display_size = 0.42
root["asset_type"] = "modular_aircraft_cockpit"
root["aircraft_reference"] = "A-10-inspired single-seat armored cockpit"
root["style"] = "broad-shouldered reference-faithful low-poly"
root["godot_forward"] = "-Z"
root["reference_image"] = os.path.relpath(REFERENCE_PATH, PROJECT_ROOT)

# Broad armored tub with a genuinely flat upper deck and deep titanium-bath
# silhouette. This deliberately avoids the rejected oval capsule cross-section.
body_sections = [
    (-1.45, 0.72, 0.45, -0.55),
    (-1.10, 0.74, 0.48, -0.55),
    (-0.68, 0.76, 0.48, -0.55),
    (-0.18, 0.75, 0.45, -0.55),
    (0.34, 0.71, 0.38, -0.55),
    (0.76, 0.63, 0.25, -0.55),
    (1.18, 0.53, 0.10, -0.54),
    (1.52, 0.40, -0.03, -0.49),
    (1.74, 0.22, -0.15, -0.38),
    (1.86, 0.10, -0.21, -0.28),
]
body = loft_a10_body("Cockpit_Body", body_sections, model_collection, body_material)
body.parent = root

# Large rear bubble with a narrow base on the broad A-10-style shoulder.
bubble_stations = [
    (-0.84, 0.27, 0.505, 0.18),
    (-0.73, 0.34, 0.508, 0.34),
    (-0.55, 0.40, 0.512, 0.47),
    (-0.30, 0.44, 0.515, 0.55),
    (-0.04, 0.45, 0.508, 0.57),
    (0.19, 0.42, 0.492, 0.53),
    (0.38, 0.38, 0.460, 0.48),
]
bubble = canopy_surface("Canopy_Glass", bubble_stations, model_collection, glass_material, segments=16)
bubble.parent = root

# The reference photograph is readable as an actual cockpit because the seat,
# dark tub and coaming are visible through the canopy.  These shapes are kept
# deliberately simple so the part remains suitable for the editor preview.
deck_vertices = [
    (-0.28, -0.78, 0.512), (0.28, -0.78, 0.512),
    (-0.37, 0.30, 0.477), (0.37, 0.30, 0.477),
    (-0.28, -0.78, 0.486), (0.28, -0.78, 0.486),
    (-0.37, 0.30, 0.451), (0.37, 0.30, 0.451),
]
deck_faces = [
    (0, 2, 3, 1), (4, 5, 7, 6),
    (0, 1, 5, 4), (2, 6, 7, 3),
    (0, 4, 6, 2), (1, 3, 7, 5),
]
deck = mesh_object("Cockpit_Tub", "Cockpit_Tub_Mesh", deck_vertices, deck_faces, model_collection, interior_material, smooth=False)
deck.parent = root

interior_parts = []
interior_parts.append(create_beveled_box("Seat_Cushion", (0.0, -0.19, 0.585), (0.40, 0.37, 0.12), model_collection, seat_material, 0.035))
interior_parts.append(create_beveled_box("Seat_Back", (0.0, -0.42, 0.745), (0.43, 0.13, 0.45), model_collection, seat_material, 0.035, (math.radians(9.0), 0.0, 0.0)))
interior_parts.append(create_beveled_box("Seat_Headrest", (0.0, -0.46, 0.930), (0.29, 0.15, 0.15), model_collection, frame_material, 0.025, (math.radians(6.0), 0.0, 0.0)))
interior_parts.append(create_beveled_box("Left_Console", (-0.30, -0.05, 0.575), (0.13, 0.56, 0.10), model_collection, interior_material, 0.018))
interior_parts.append(create_beveled_box("Right_Console", (0.30, -0.05, 0.575), (0.13, 0.56, 0.10), model_collection, interior_material, 0.018))
interior_parts.append(create_beveled_box("Instrument_Coaming", (0.0, 0.25, 0.605), (0.55, 0.25, 0.12), model_collection, interior_material, 0.028, (math.radians(-7.0), 0.0, 0.0)))
interior_parts.append(create_beveled_box("Instrument_Face", (0.0, 0.205, 0.580), (0.39, 0.018, 0.15), model_collection, instrument_material, 0.012, (math.radians(-7.0), 0.0, 0.0)))
for part in interior_parts:
    part.parent = root

# Steep wrapped windscreen. Its six broad strips make the real multi-pane
# construction legible without adding decorative grooves or greebles.
wind_t = [-1.0, -0.67, -0.34, 0.0, 0.34, 0.67, 1.0]
wind_vertices = []
wind_bottom = []
wind_top = []
for t in wind_t:
    abs_t = abs(t)
    bottom = (0.39 * t, 0.74 - 0.10 * abs_t, 0.295 + 0.020 * (1.0 - abs_t))
    crown = max(0.0, 1.0 - t * t) ** 0.40
    top = (0.38 * t, 0.38 + 0.020 * abs_t, 0.460 + 0.48 * crown)
    wind_bottom.append(len(wind_vertices))
    wind_vertices.append(bottom)
    wind_top.append(len(wind_vertices))
    wind_vertices.append(top)
wind_faces = []
for index in range(len(wind_t) - 1):
    wind_faces.append((wind_bottom[index], wind_top[index], wind_top[index + 1], wind_bottom[index + 1]))
windscreen = mesh_object(
    "Windscreen_Glass",
    "Windscreen_Glass_Mesh",
    wind_vertices,
    wind_faces,
    model_collection,
    glass_material,
    smooth=False,
)
windscreen.parent = root
bpy.ops.object.select_all(action="DESELECT")
windscreen.select_set(True)
bpy.context.view_layer.objects.active = windscreen
solidify = windscreen.modifiers.new("Glass thickness", "SOLIDIFY")
solidify.thickness = 0.008
solidify.offset = -0.5
solidify.use_even_offset = True
bpy.ops.object.modifier_apply(modifier=solidify.name)

frame_parts = []

# Bubble rear and front arches, plus the two simple lower rails.
rear_arch = arch_points(*bubble_stations[0], segments=16)
front_arch = arch_points(*bubble_stations[-1], segments=16)
frame_parts.append(create_poly_beam("Frame_Rear_Arch", rear_arch, 0.030, model_collection, frame_material))
frame_parts.append(create_poly_beam("Frame_Front_Arch", front_arch, 0.033, model_collection, frame_material))
left_sill = [arch_points(*station, segments=16)[0] for station in bubble_stations]
right_sill = [arch_points(*station, segments=16)[-1] for station in bubble_stations]
frame_parts.append(create_poly_beam("Frame_Left_Sill", left_sill, 0.028, model_collection, frame_material))
frame_parts.append(create_poly_beam("Frame_Right_Sill", right_sill, 0.028, model_collection, frame_material))

# Windscreen borders and one central divider are the only forward mullions.
wind_bottom_points = [wind_vertices[index] for index in wind_bottom]
wind_top_points = [wind_vertices[index] for index in wind_top]
frame_parts.append(create_poly_beam("Frame_Windscreen_Lower", wind_bottom_points, 0.029, model_collection, frame_material))
frame_parts.append(create_poly_beam("Frame_Windscreen_Left", [wind_bottom_points[0], wind_top_points[0]], 0.031, model_collection, frame_material))
frame_parts.append(create_poly_beam("Frame_Windscreen_Right", [wind_bottom_points[-1], wind_top_points[-1]], 0.031, model_collection, frame_material))
center_index = wind_t.index(0.0)
frame_parts.append(
    create_poly_beam(
        "Frame_Windscreen_Center",
        [wind_bottom_points[center_index], wind_top_points[center_index]],
        0.028,
        model_collection,
        frame_material,
    )
)

bpy.ops.object.select_all(action="DESELECT")
for part in frame_parts:
    part.select_set(True)
bpy.context.view_layer.objects.active = frame_parts[0]
bpy.ops.object.join()
frame = bpy.context.object
frame.name = "Canopy_Frame"
frame.data.name = "Canopy_Frame_Mesh"
frame.parent = root

# Presentation objects stay outside MODEL_A10_Cockpit and are excluded from glTF.
bpy.ops.mesh.primitive_plane_add(size=18.0, location=(0.0, 0.0, -0.86))
studio_floor = bpy.context.object
studio_floor.name = "Studio_Floor"
move_to_collection(studio_floor, presentation_collection)
studio_floor.data.materials.append(floor_material)

camera_data = bpy.data.cameras.new("Camera")
camera = bpy.data.objects.new("Camera", camera_data)
presentation_collection.objects.link(camera)
camera.location = (5.15, 5.45, 4.05)
camera_data.lens = 72
point_at(camera, (0.0, 0.18, 0.08))
scene.camera = camera


def add_area(name, location, energy, size, color):
    light_data = bpy.data.lights.new(name, "AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light_data.color = color
    light_obj = bpy.data.objects.new(name, light_data)
    presentation_collection.objects.link(light_obj)
    light_obj.location = location
    point_at(light_obj, (0.0, 0.0, 0.20))
    return light_obj


add_area("Key_Area", (4.2, 4.6, 6.5), 1050, 4.5, (0.90, 0.96, 1.0))
add_area("Fill_Area", (-4.3, 3.2, 3.1), 720, 4.0, (0.58, 0.72, 1.0))
add_area("Rim_Area", (1.0, -4.8, 4.8), 860, 3.2, (0.70, 0.84, 1.0))

world = bpy.data.worlds.new("Blueprint_World")
scene.world = world
world.use_nodes = True
background = world.node_tree.nodes.get("Background")
background.inputs["Color"].default_value = (0.012, 0.035, 0.072, 1.0)
background.inputs["Strength"].default_value = 0.38

bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

bpy.ops.object.select_all(action="DESELECT")
for obj in model_collection.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.export_scene.gltf(
    filepath=GLB_PATH,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_materials="EXPORT",
    export_cameras=False,
    export_lights=False,
    export_extras=True,
    export_yup=True,
)

scene.render.filepath = PREVIEW_PATH
bpy.ops.render.render(write_still=True)

# A clean side silhouette is the quickest regression check against the A-10
# reference: low bubble, steep windscreen and almost flat belly.
camera.location = (6.35, 0.10, 0.55)
camera_data.lens = 86
point_at(camera, (0.0, 0.10, 0.05))
scene.render.filepath = SIDE_PREVIEW_PATH
bpy.ops.render.render(write_still=True)

camera.location = (5.15, 5.45, 4.05)
camera_data.lens = 72
point_at(camera, (0.0, 0.18, 0.08))
scene.render.filepath = PREVIEW_PATH
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

result = {
    "blend": BLEND_PATH,
    "glb": GLB_PATH,
    "preview": PREVIEW_PATH,
    "side_preview": SIDE_PREVIEW_PATH,
    "model_objects": len(model_collection.objects),
    "body_vertices": len(body.data.vertices),
    "body_polygons": len(body.data.polygons),
    "bubble_polygons": len(bubble.data.polygons),
    "windscreen_polygons": len(windscreen.data.polygons),
    "frame_vertices": len(frame.data.vertices),
    "scene_objects": len(scene.objects),
    "blender_version": bpy.app.version_string,
}
