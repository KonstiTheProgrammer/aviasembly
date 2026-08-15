"""Build the faceted transport cockpit from a completely empty Blender scene.

The asset is authored in Blender coordinates (X width, Z up, +Y nose). Blender's
glTF conversion therefore produces the Aviassembly convention X width, Y up,
-Z nose.
"""

import bpy
from mathutils import Vector


BLEND_PATH = "/Users/konstantinkanzler/Projects/aviasembly/blender_lib/cockpit_faceted_transport.blend"
GLB_PATH = "/Users/konstantinkanzler/Projects/aviasembly/models/cockpit_faceted_transport.glb"
PREVIEW_PATH = "/Users/konstantinkanzler/Projects/aviasembly/blender_lib/cockpit_faceted_transport_preview.png"


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


def make_material(name, color, metallic=0.0, roughness=0.35, transmission=0.0, alpha=1.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = (*color[:3], alpha)
    material.metallic = metallic
    material.roughness = roughness
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        values = {
            "Base Color": (*color[:3], alpha),
            "Metallic": metallic,
            "Roughness": roughness,
            "Transmission Weight": transmission,
            "IOR": 1.46,
            "Alpha": alpha,
            "Coat Weight": 0.18,
            "Coat Roughness": 0.12,
        }
        for socket, value in values.items():
            if socket in bsdf.inputs:
                bsdf.inputs[socket].default_value = value
    if alpha < 1.0 and hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"
    return material


def mesh_object(name, mesh_name, vertices, faces, collection, material):
    mesh = bpy.data.meshes.new(mesh_name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def body_ring(y, width, top, bottom, vertical_shift, facet_twist):
    top += vertical_shift
    bottom += vertical_shift
    upper_chine = top * 0.58
    lower_chine = bottom * 0.52
    return [
        (-0.60 * width, y, top),
        (0.60 * width, y, top),
        ((1.00 + facet_twist) * width, y, upper_chine),
        ((1.00 - facet_twist) * width, y, lower_chine),
        (0.67 * width, y, bottom),
        (-0.67 * width, y, bottom),
        (-(1.00 - facet_twist) * width, y, lower_chine),
        (-(1.00 + facet_twist) * width, y, upper_chine),
    ]


def canopy_ring(station):
    base_y, roof_y, base_width, roof_width, base_z, roof_z, crown = station
    return [
        (-base_width, base_y, base_z),
        (-roof_width, roof_y, roof_z),
        (0.0, roof_y, roof_z + crown),
        (roof_width, roof_y, roof_z),
        (base_width, base_y, base_z),
    ]


def apply_modifier(obj, modifier):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def point_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


clear_scene()

scene = bpy.context.scene
scene.name = "Faceted_Transport_Cockpit"
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"

model_collection = bpy.data.collections.new("MODEL_Faceted_Cockpit")
scene.collection.children.link(model_collection)
presentation_collection = bpy.data.collections.new("PRESENTATION")
scene.collection.children.link(presentation_collection)

body_material = make_material("cockpit_body", (0.25, 0.29, 0.33, 1), metallic=0.12, roughness=0.60)
glass_material = make_material("glass", (0.012, 0.016, 0.020, 1), metallic=0.0, roughness=0.36, transmission=0.0, alpha=1.0)
frame_material = make_material("frame", (0.022, 0.026, 0.030, 1), metallic=0.0, roughness=0.64)
glass_bsdf = glass_material.node_tree.nodes.get("Principled BSDF")
if glass_bsdf:
    if "Specular IOR Level" in glass_bsdf.inputs:
        glass_bsdf.inputs["Specular IOR Level"].default_value = 0.06
    if "Coat Weight" in glass_bsdf.inputs:
        glass_bsdf.inputs["Coat Weight"].default_value = 0.0
frame_bsdf = frame_material.node_tree.nodes.get("Principled BSDF")
if frame_bsdf:
    if "Specular IOR Level" in frame_bsdf.inputs:
        frame_bsdf.inputs["Specular IOR Level"].default_value = 0.22
    if "Coat Weight" in frame_bsdf.inputs:
        frame_bsdf.inputs["Coat Weight"].default_value = 0.0
floor_material = make_material("Studio_Floor", (0.72, 0.75, 0.78, 1), roughness=0.78)

root = bpy.data.objects.new("Cockpit_Faceted_Root", None)
model_collection.objects.link(root)
root.empty_display_type = "ARROWS"
root.empty_display_size = 0.65
root["asset_type"] = "modular_aircraft_cockpit"
root["authoring"] = "created_from_scratch"
root["godot_forward"] = "-Z"
root["reference_style"] = "faceted_low_poly_transport_cockpit"

# Broad, blunt cockpit face flowing into a narrower modular rear section.
sections = [
    # The reference nose deck is almost level in side view.  Keep the blunt
    # front cap high and let it rise only slightly into the windshield brow.
    (2.42, 1.22, 0.90, -0.62, -0.02, 0.020),
    (1.78, 1.28, 0.96, -0.78, 0.00, -0.035),
    # Raised nose brow under the lower windshield edge. The reference side
    # sill then drops aft to the lower rectangular side-window baseline.
    (1.54, 1.25, 1.00, -0.84, 0.00, 0.015),
    (0.72, 1.29, 0.82, -0.88, 0.01, 0.028),
    (-0.38, 1.22, 0.82, -0.87, 0.01, -0.025),
    # The reference fuselage wraps up behind the greenhouse instead of
    # continuing as a low deck. Two close rings form the steep rear cockpit
    # bulkhead; the following ring begins the long descending tail shoulder.
    (-0.96, 1.16, 0.80, -0.83, 0.00, 0.018),
    (-1.07, 1.12, 1.18, -0.82, 0.00, -0.018),
    (-1.48, 0.90, 1.02, -0.74, 0.00, 0.025),
    (-2.30, 0.44, 0.80, -0.35, -0.02, -0.020),
]
body_vertices = []
body_rings = []
for section in sections:
    ring = body_ring(*section)
    body_rings.append(list(range(len(body_vertices), len(body_vertices) + len(ring))))
    body_vertices.extend(ring)

body_faces = []
ring_size = len(body_rings[0])
for section_index in range(len(body_rings) - 1):
    current = body_rings[section_index]
    following = body_rings[section_index + 1]
    for vertex_index in range(ring_size):
        next_index = (vertex_index + 1) % ring_size
        if (section_index + vertex_index) % 2 == 0:
            body_faces.append((current[vertex_index], following[vertex_index], following[next_index]))
            body_faces.append((current[vertex_index], following[next_index], current[next_index]))
        else:
            body_faces.append((current[vertex_index], following[vertex_index], current[next_index]))
            body_faces.append((current[next_index], following[vertex_index], following[next_index]))

front_center = len(body_vertices)
body_vertices.append((0, sections[0][0], -0.04))
rear_center = len(body_vertices)
body_vertices.append((0, sections[-1][0], -0.03))
for vertex_index in range(ring_size):
    next_index = (vertex_index + 1) % ring_size
    body_faces.append((front_center, body_rings[0][next_index], body_rings[0][vertex_index]))
    body_faces.append((rear_center, body_rings[-1][vertex_index], body_rings[-1][next_index]))

body = mesh_object(
    "Cockpit_Body",
    "Cockpit_Body_LowPoly_Mesh",
    body_vertices,
    body_faces,
    model_collection,
    body_material,
)
body.parent = root

# Long raised greenhouse canopy: raked windshield, four side bays, tapered rear.
canopy_stations = [
    # base Y, roof Y, base half-width, roof half-width, base Z, roof Z, crown
    # In plan view the greenhouse occupies only about three fifths of the
    # fuselage width.  The broader old values made it read as a full-width
    # cabin and disagreed with both oblique reference views.
    (1.54, 0.82, 0.66, 0.50, 1.00, 1.34, 0.045),
    # The reference mullions lean gently aft instead of standing perfectly
    # vertical.  The offset diminishes toward the rear bulkhead.
    (0.80, 0.90, 0.76, 0.58, 0.81, 1.36, 0.055),
    (0.11, 0.18, 0.77, 0.60, 0.82, 1.36, 0.060),
    (-0.47, -0.43, 0.73, 0.58, 0.80, 1.31, 0.052),
    (-1.04, -1.02, 0.59, 0.48, 0.76, 1.20, 0.040),
]
glass_vertices = []
glass_rings = []
for station in canopy_stations:
    ring = canopy_ring(station)
    glass_rings.append(list(range(len(glass_vertices), len(glass_vertices) + 5)))
    glass_vertices.extend(ring)

glass_faces = []
for station_index in range(len(glass_rings) - 1):
    current = glass_rings[station_index]
    following = glass_rings[station_index + 1]
    for strip in range(4):
        glass_faces.append((current[strip], following[strip], following[strip + 1], current[strip + 1]))

for ring_index, reverse in ((0, False), (len(glass_rings) - 1, True)):
    station = canopy_stations[ring_index]
    center_index = len(glass_vertices)
    ring_points = [Vector(glass_vertices[index]) for index in glass_rings[ring_index]]
    cap_center = sum(ring_points, Vector()) / len(ring_points)
    glass_vertices.append(tuple(cap_center))
    ring = glass_rings[ring_index]
    for strip in range(4):
        if reverse:
            glass_faces.append((center_index, ring[strip], ring[strip + 1]))
        else:
            glass_faces.append((center_index, ring[strip + 1], ring[strip]))
    # Close the lower edge of each end cap; the longitudinal bottom quad
    # shares this edge and turns the glazing into a true manifold volume.
    if reverse:
        glass_faces.append((center_index, ring[4], ring[0]))
    else:
        glass_faces.append((center_index, ring[0], ring[4]))
for station_index in range(len(glass_rings) - 1):
    glass_faces.append(
        (
            glass_rings[station_index][0],
            glass_rings[station_index + 1][0],
            glass_rings[station_index + 1][4],
            glass_rings[station_index][4],
        )
    )

glass = mesh_object(
    "Canopy_Glass",
    "Canopy_Glass_Mesh",
    glass_vertices,
    glass_faces,
    model_collection,
    glass_material,
)
glass.parent = root

frame_parts = []


def beam_between(name, start, end, thickness=0.066, second_thickness=None):
    start = Vector(start)
    end = Vector(end)
    direction = end - start
    if direction.length < 1e-5:
        return None
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(start + end) * 0.5)
    obj = bpy.context.object
    obj.name = name
    move_to_collection(obj, model_collection)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    # Use local scale, not Object.dimensions: dimensions is a world-aligned
    # bounding box and distorts diagonal bars after their rotation is set.
    obj.scale = (
        thickness,
        thickness if second_thickness is None else second_thickness,
        direction.length + thickness * 0.22,
    )
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(frame_material)
    bevel = obj.modifiers.new("Edge bevel", "BEVEL")
    bevel.width = thickness * 0.15
    bevel.segments = 1
    apply_modifier(obj, bevel)
    frame_parts.append(obj)
    return obj


canopy_points = [canopy_ring(station) for station in canopy_stations]
for rail_index in range(5):
    for station_index in range(len(canopy_points) - 1):
        thickness = 0.074 if rail_index in (0, 4) else (0.061 if rail_index == 2 else 0.066)
        beam_between(
            f"Frame_Long_{rail_index}_{station_index}",
            canopy_points[station_index][rail_index],
            canopy_points[station_index + 1][rail_index],
            thickness,
        )

for station_index, ring in enumerate(canopy_points):
    thickness = 0.086 if station_index in (0, len(canopy_points) - 1) else 0.070
    for edge_index in range(4):
        beam_between(
            f"Frame_Arch_{station_index}_{edge_index}",
            ring[edge_index],
            ring[edge_index + 1],
            thickness,
        )

for station_index in (0, len(canopy_points) - 1):
    ring = canopy_points[station_index]
    station = canopy_stations[station_index]
    center_post = beam_between(f"Frame_CenterPost_{station_index}", (0, station[0], station[4]), ring[2], 0.072)
    if station_index == 0:
        center_post.location += Vector((0.0, 0.038, 0.024))
    else:
        center_post.location += Vector((0.0, -0.035, 0.0))
    beam_between(f"Frame_Lower_{station_index}", ring[0], ring[4], 0.074, 0.064)

bpy.ops.object.select_all(action="DESELECT")
for part in frame_parts:
    part.select_set(True)
bpy.context.view_layer.objects.active = frame_parts[0]
bpy.ops.object.join()
frame = frame_parts[0]
frame.name = "Canopy_Frame"
frame.data.name = "Canopy_Frame_Mesh"
frame.parent = root

# Studio floor, camera and lights are deliberately outside the export collection.
studio_floor = mesh_object(
    "Studio_Floor",
    "Studio_Floor_Mesh",
    [(-7, -6, -0.94), (7, -6, -0.94), (7, 6, -0.94), (-7, 6, -0.94)],
    [(0, 1, 2, 3)],
    presentation_collection,
    floor_material,
)

camera_data = bpy.data.cameras.new("Camera")
camera = bpy.data.objects.new("Camera", camera_data)
presentation_collection.objects.link(camera)
camera.location = (6.35, 7.45, 4.25)
camera_data.lens = 64
point_at(camera, (0, 0.05, 0.30))
scene.camera = camera


def add_area(name, location, energy, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    presentation_collection.objects.link(obj)
    obj.location = location
    point_at(obj, (0, 0.15, 0.35))
    return obj


add_area("Key_Area", (4.8, 4.5, 7.5), 950, 5.0, (0.92, 0.96, 1.0))
add_area("Fill_Area", (-5.0, 3.0, 3.6), 650, 4.0, (0.78, 0.86, 1.0))
add_area("Rim_Area", (2.0, -5.2, 5.2), 620, 3.5, (0.88, 0.94, 1.0))

world = bpy.data.worlds.new("Studio_World")
scene.world = world
world.use_nodes = True
background = world.node_tree.nodes.get("Background")
background.inputs["Color"].default_value = (0.82, 0.84, 0.86, 1)
background.inputs["Strength"].default_value = 0.72

# Rebuilding collections inside a live Blender session needs an explicit
# dependency-graph update before the first export/render.
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
    "glass_polygons": len(glass.data.polygons),
    "frame_vertices": len(frame.data.vertices),
    "scene_objects": len(scene.objects),
    "blender_version": bpy.app.version_string,
}
