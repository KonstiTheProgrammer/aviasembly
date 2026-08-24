"""Build a smooth A-10-inspired cockpit module from an empty Blender scene.

The asset uses the Aviassembly authoring convention: X is width, Z is up and
+Y points toward the nose. Blender's glTF conversion maps +Y to Godot -Z.
"""

import math
import os

import bpy
from mathutils import Vector


PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLEND_PATH = os.path.join(PROJECT_ROOT, "blender_lib/cockpit_a10.blend")
GLB_PATH = os.path.join(PROJECT_ROOT, "models/cockpit_a10.glb")
PREVIEW_PATH = os.path.join(PROJECT_ROOT, "blender_lib/cockpit_a10_preview.png")
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


def make_material(name, color, metallic=0.0, roughness=0.4):
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
            "Coat Weight": 0.16,
            "Coat Roughness": 0.16,
        }
        for socket, value in values.items():
            if socket in bsdf.inputs:
                bsdf.inputs[socket].default_value = value
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


def arch_points(y, width, base_z, height, segments=12):
    points = []
    for index in range(segments + 1):
        angle = math.pi - math.pi * index / segments
        points.append((width * math.cos(angle), y, base_z + height * math.sin(angle)))
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
scene.name = "A10_Cockpit_Module"
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"

model_collection = bpy.data.collections.new("MODEL_A10_Cockpit")
scene.collection.children.link(model_collection)
presentation_collection = bpy.data.collections.new("PRESENTATION")
scene.collection.children.link(presentation_collection)

body_material = make_material("cockpit_body", (0.46, 0.49, 0.53, 1.0), metallic=0.32, roughness=0.43)
glass_material = make_material("glass", (0.008, 0.016, 0.026, 1.0), metallic=0.0, roughness=0.19)
frame_material = make_material("canopy_frame", (0.055, 0.063, 0.072, 1.0), metallic=0.55, roughness=0.36)
floor_material = make_material("Studio_Floor", (0.025, 0.060, 0.105, 1.0), metallic=0.0, roughness=0.82)

glass_bsdf = glass_material.node_tree.nodes.get("Principled BSDF")
if glass_bsdf:
    if "Specular IOR Level" in glass_bsdf.inputs:
        glass_bsdf.inputs["Specular IOR Level"].default_value = 0.34
    if "Coat Weight" in glass_bsdf.inputs:
        glass_bsdf.inputs["Coat Weight"].default_value = 0.28

root = bpy.data.objects.new("A10_Cockpit_Root", None)
model_collection.objects.link(root)
root.empty_display_type = "ARROWS"
root.empty_display_size = 0.42
root["asset_type"] = "modular_aircraft_cockpit"
root["aircraft_reference"] = "A-10-inspired single-seat armored cockpit"
root["style"] = "smooth rounded low-poly"
root["godot_forward"] = "-Z"
root["reference_image"] = os.path.relpath(REFERENCE_PATH, PROJECT_ROOT)

# Broad armored tub with a high shoulder and smoothly tapered nose. The first
# and last stations remain planar attachment faces for editor snapping.
body_sections = [
    (-1.35, 0.72, 0.65, -0.10, 2.45),
    (-1.12, 0.76, 0.69, -0.10, 2.45),
    (-0.68, 0.78, 0.72, -0.12, 2.38),
    (-0.18, 0.77, 0.71, -0.13, 2.30),
    (0.32, 0.74, 0.66, -0.14, 2.22),
    (0.76, 0.68, 0.58, -0.15, 2.14),
    (1.10, 0.52, 0.44, -0.17, 2.05),
    (1.35, 0.40, 0.34, -0.17, 2.00),
]
body = loft_closed("Cockpit_Body", body_sections, model_collection, body_material, segments=24)
body.parent = root

# A low integrated collar prevents the bubble canopy from reading as a pod
# glued onto the fuselage. It overlaps the body intentionally and stays clean.
sill_sections = [
    (-0.70, 0.42, 0.065, 0.505, 2.20),
    (-0.54, 0.50, 0.075, 0.510, 2.25),
    (-0.08, 0.53, 0.080, 0.515, 2.25),
    (0.34, 0.51, 0.075, 0.505, 2.20),
    (0.69, 0.40, 0.055, 0.465, 2.05),
]
sill = loft_closed("Canopy_Sill", sill_sections, model_collection, body_material, segments=24)
sill.parent = root

# Large rear bubble with a narrow base on the broad A-10-style shoulder.
bubble_stations = [
    (-0.61, 0.34, 0.54, 0.39),
    (-0.48, 0.43, 0.54, 0.56),
    (-0.08, 0.47, 0.55, 0.64),
    (0.27, 0.42, 0.55, 0.60),
]
bubble = canopy_surface("Canopy_Glass", bubble_stations, model_collection, glass_material, segments=16)
bubble.parent = root

# Steep wrapped windscreen. Its six broad strips make the real multi-pane
# construction legible without adding decorative grooves or greebles.
wind_t = [-1.0, -0.67, -0.34, 0.0, 0.34, 0.67, 1.0]
wind_vertices = []
wind_bottom = []
wind_top = []
for t in wind_t:
    abs_t = abs(t)
    bottom = (0.39 * t, 0.78 - 0.12 * abs_t, 0.48 + 0.025 * (1.0 - abs_t))
    top = (0.42 * t, 0.27 + 0.025 * abs_t, 0.55 + 0.60 * math.sqrt(max(0.0, 1.0 - t * t)))
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
frame_parts.append(
    create_poly_beam(
        "Frame_Left_Sill",
        [rear_arch[0], arch_points(*bubble_stations[1], segments=16)[0], arch_points(*bubble_stations[2], segments=16)[0], front_arch[0]],
        0.028,
        model_collection,
        frame_material,
    )
)
frame_parts.append(
    create_poly_beam(
        "Frame_Right_Sill",
        [rear_arch[-1], arch_points(*bubble_stations[1], segments=16)[-1], arch_points(*bubble_stations[2], segments=16)[-1], front_arch[-1]],
        0.028,
        model_collection,
        frame_material,
    )
)

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
camera.location = (5.35, 3.85, 3.10)
camera_data.lens = 66
point_at(camera, (0.0, 0.02, 0.16))
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
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

result = {
    "blend": BLEND_PATH,
    "glb": GLB_PATH,
    "preview": PREVIEW_PATH,
    "model_objects": len(model_collection.objects),
    "body_vertices": len(body.data.vertices),
    "body_polygons": len(body.data.polygons),
    "bubble_polygons": len(bubble.data.polygons),
    "windscreen_polygons": len(windscreen.data.polygons),
    "frame_vertices": len(frame.data.vertices),
    "scene_objects": len(scene.objects),
    "blender_version": bpy.app.version_string,
}
