"""Baut eine stilisierte B-29-Motorgondel mit Wright-R-3350-Anmutung.

Die Außenform folgt der B-29: lange runde Cowling, große Kühlluftöffnung,
Vierblattpropeller, hintere Kühlklappen und eine plane Montagefläche.

Blender-Koordinaten:
    X = Breite, Y = Flugrichtung/vorne, Z = oben.
Beim glTF-Export mit Y-up wird Blender +Y zu Godot -Z.
"""

import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[1]
BLEND_OUT = ROOT / "blender_lib" / "b29_engine.blend"
GLB_OUT = ROOT / "models" / "b29_engine.glb"
PREVIEW_OUT = ROOT / "tools" / "b29_engine_preview.png"
FRONT_OUT = ROOT / "tools" / "b29_engine_front.png"
SIDE_OUT = ROOT / "tools" / "b29_engine_side.png"

COWL_REAR = -0.82
COWL_FRONT = 0.62
COWL_RADIUS = 0.84
PROP_PLANE = 0.79
PROP_RADIUS = 1.48
COWL_PROFILE = (
    (COWL_REAR, 0.70),
    (-0.70, 0.79),
    (-0.38, COWL_RADIUS),
    (0.08, COWL_RADIUS),
    (0.34, 0.81),
    (0.52, 0.75),
    (COWL_FRONT, 0.68),
)


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


def make_materials():
    return {
        "engine": material("engine", (0.48, 0.53, 0.61, 1.0), 0.42, 0.38),
        "panel": material("engine_panel", (0.29, 0.33, 0.39, 1.0), 0.34, 0.48),
        "metal": material("engine_metal", (0.38, 0.42, 0.47, 1.0), 0.72, 0.28),
        "dark": material("engine_dark", (0.010, 0.014, 0.021, 1.0), 0.08, 0.86),
        "exhaust": material("engine_exhaust", (0.08, 0.065, 0.052, 1.0), 0.55, 0.60),
        "blade": material("propeller_black", (0.018, 0.022, 0.029, 1.0), 0.12, 0.54),
        "tip": material("propeller_tip", (0.95, 0.66, 0.055, 1.0), 0.08, 0.44),
        "rubber": material("engine_gasket", (0.018, 0.022, 0.028, 1.0), 0.0, 0.92),
    }


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


def set_flat(obj):
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = False


def add_bevel(obj, width, segments=2):
    if width <= 0.0 or obj.type != "MESH":
        return
    modifier = obj.modifiers.new("Kantenrundung", "BEVEL")
    modifier.width = width
    modifier.segments = segments


def mesh_object(name, verts, faces, materials, material_indices=None, parent=None):
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for mat in materials:
        obj.data.materials.append(mat)
    if material_indices is not None:
        for polygon, material_index in zip(obj.data.polygons, material_indices):
            polygon.material_index = material_index
    if parent is not None:
        obj.parent = parent
        # Die Meshpunkte sind bereits im lokalen Prop-Koordinatensystem gebaut.
        # Blender setzt beim nachträglichen Parenting sonst eine ausgleichende
        # Parent-Inverse-Matrix; im glTF sähe es richtig aus, Godot rotate_z würde
        # aber um die falsche lokale Achse drehen.
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_basis = Matrix.Identity(4)
    set_flat(obj)
    return obj


def revolve_y(name, profile, segments, mat):
    verts = []
    faces = []
    for y, radius in profile:
        for segment in range(segments):
            angle = math.tau * segment / segments
            verts.append((math.cos(angle) * radius, y, math.sin(angle) * radius))
    for row in range(len(profile) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = row * segments + segment
            b = row * segments + nxt
            c = (row + 1) * segments + segment
            d = (row + 1) * segments + nxt
            faces.extend(((a, c, b), (b, c, d)))
    return mesh_object(name, verts, faces, (mat,))


def revolve_prop_local(name, profile, segments, mat, parent):
    """Rotationskörper um Blender-Y; glTF wandelt ihn zur Godot-Z-Achse."""
    verts = []
    faces = []
    for depth, radius in profile:
        for segment in range(segments):
            angle = math.tau * segment / segments
            verts.append((math.cos(angle) * radius, depth, math.sin(angle) * radius))
    for row in range(len(profile) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = row * segments + segment
            b = row * segments + nxt
            c = (row + 1) * segments + segment
            d = (row + 1) * segments + nxt
            faces.extend(((a, b, c), (b, d, c)))
    return mesh_object(name, verts, faces, (mat,), parent=parent)


def cylinder(name, radius, depth, location, axis, mat, vertices=24, bevel=0.0):
    direction = Vector(axis).normalized()
    rotation = direction.to_track_quat("Z", "Y").to_euler()
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "Mesh"
    obj.data.materials.append(mat)
    set_flat(obj)
    add_bevel(obj, bevel)
    return obj


def sphere(name, radius, location, mat, scale=(1.0, 1.0, 1.0)):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=16,
        ring_count=8,
        radius=radius,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(mat)
    set_flat(obj)
    return obj


def box(name, size, location, mat, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    set_flat(obj)
    add_bevel(obj, bevel)
    return obj


def torus_y(name, y, major_radius, minor_radius, mat, major_segments=40):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=major_segments,
        minor_segments=8,
        major_radius=major_radius,
        minor_radius=minor_radius,
        location=(0.0, y, 0.0),
        rotation=(math.pi / 2.0, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    set_flat(obj)
    return obj


def cowl_radius_at(y):
    """Interpoliert den äußeren Cowling-Radius für bündige Details."""
    if y <= COWL_PROFILE[0][0]:
        return COWL_PROFILE[0][1]
    if y >= COWL_PROFILE[-1][0]:
        return COWL_PROFILE[-1][1]
    for rear, front in zip(COWL_PROFILE, COWL_PROFILE[1:]):
        if rear[0] <= y <= front[0]:
            t = (y - rear[0]) / (front[0] - rear[0])
            return rear[1] + (front[1] - rear[1]) * t
    raise RuntimeError(f"Kein Cowling-Radius für Y={y}")


def cylinder_between(name, start, end, radius, mat, vertices=12):
    start_v = Vector(start)
    end_v = Vector(end)
    delta = end_v - start_v
    return cylinder(
        name,
        radius,
        delta.length,
        tuple((start_v + end_v) * 0.5),
        tuple(delta),
        mat,
        vertices,
    )


def build_cowl_flaps(materials):
    """Vierzehn leicht geöffnete, direkt an der Cowling verankerte Kühlklappen."""
    count = 14
    gap = math.radians(1.8)
    verts = []
    faces = []
    for index in range(count):
        center = math.tau * index / count
        half = math.pi / count - gap
        front_a = center - half
        front_b = center + half
        front_radius = 0.785
        rear_radius = 0.835
        front_y = -0.64
        rear_y = -0.855
        base = len(verts)
        for radius, y, angle in (
            (front_radius, front_y, front_a),
            (front_radius, front_y, front_b),
            (rear_radius, rear_y, front_b),
            (rear_radius, rear_y, front_a),
        ):
            verts.append((math.cos(angle) * radius, y, math.sin(angle) * radius))
        # Rückseite liegt 12 mm radial weiter innen; dadurch ist jede Klappe ein
        # geschlossener dünner Körper und kann nicht wie eine lose Fläche wirken.
        for radius, y, angle in (
            (front_radius - 0.012, front_y, front_a),
            (front_radius - 0.012, front_y, front_b),
            (rear_radius - 0.012, rear_y, front_b),
            (rear_radius - 0.012, rear_y, front_a),
        ):
            verts.append((math.cos(angle) * radius, y, math.sin(angle) * radius))
        faces.extend(
            (
                (base + 0, base + 1, base + 2, base + 3),
                (base + 7, base + 6, base + 5, base + 4),
                (base + 0, base + 4, base + 5, base + 1),
                (base + 1, base + 5, base + 6, base + 2),
                (base + 2, base + 6, base + 7, base + 3),
                (base + 3, base + 7, base + 4, base + 0),
            )
        )
    return mesh_object("cowl_flaps", verts, faces, (materials["panel"],))


def build_propeller_blade(name, angle, parent, materials):
    """Breites, getwistetes Vierblattpropellerblatt mit gelber Spitze."""
    # Blender-X/Z wird beim glTF-Export zu Godot-X/Y. Die Blattgeometrie
    # liegt daher bereits lokal in X/Z; ihre Tiefenachse ist Blender-Y und
    # wird zu Godot-Z. So funktioniert AircraftBody.rotate_z(Prop) korrekt.
    radial = Vector((math.cos(angle), 0.0, math.sin(angle)))
    tangent = Vector((-math.sin(angle), 0.0, math.cos(angle)))
    axis = Vector((0.0, 1.0, 0.0))
    stations = (
        (0.18, 0.16, 0.052, math.radians(31.0)),
        (0.38, 0.23, 0.060, math.radians(27.0)),
        (0.72, 0.245, 0.054, math.radians(21.0)),
        (1.08, 0.185, 0.040, math.radians(15.0)),
        (1.30, 0.125, 0.028, math.radians(11.0)),
        (PROP_RADIUS, 0.040, 0.012, math.radians(8.0)),
    )
    ring = 10
    verts = []
    for radius, half_chord, half_thick, pitch in stations:
        chord_axis = tangent * math.cos(pitch) + axis * math.sin(pitch)
        thick_axis = -tangent * math.sin(pitch) + axis * math.cos(pitch)
        center = radial * radius + axis * PROP_PLANE
        for point in range(ring):
            section_angle = math.tau * point / ring
            verts.append(
                tuple(
                    center
                    + chord_axis * (math.cos(section_angle) * half_chord)
                    + thick_axis * (math.sin(section_angle) * half_thick)
                )
            )
    faces = []
    material_indices = []
    for row in range(len(stations) - 1):
        for point in range(ring):
            nxt = (point + 1) % ring
            a = row * ring + point
            b = row * ring + nxt
            c = (row + 1) * ring + point
            d = (row + 1) * ring + nxt
            faces.extend(((a, c, b), (b, c, d)))
            material_indices.extend((1 if row >= len(stations) - 2 else 0,) * 2)
    root_center = len(verts)
    verts.append(tuple(radial * stations[0][0] + axis * PROP_PLANE))
    tip_center = len(verts)
    verts.append(tuple(radial * stations[-1][0] + axis * PROP_PLANE))
    for point in range(ring):
        nxt = (point + 1) % ring
        faces.append((root_center, nxt, point))
        material_indices.append(0)
        a = (len(stations) - 1) * ring + point
        b = (len(stations) - 1) * ring + nxt
        faces.append((tip_center, a, b))
        material_indices.append(1)
    return mesh_object(
        name,
        verts,
        faces,
        (materials["blade"], materials["tip"]),
        material_indices,
        parent,
    )


def build_model(materials):
    # Lange, rundliche B-29-Cowling. Das hintere Drittel bleibt fast zylindrisch,
    # damit die Gondel glaubwürdig in eine Tragfläche oder ein Rumpfstück übergeht.
    cowl = revolve_y(
        "B29_Cowling",
        COWL_PROFILE,
        40,
        materials["engine"],
    )

    # Plane Montagefläche hinten samt elastischem Dichtungsring.
    cylinder(
        "rear_mount_face",
        0.705,
        0.025,
        (0.0, COWL_REAR + 0.010, 0.0),
        (0.0, 1.0, 0.0),
        materials["engine"],
        40,
    )
    torus_y("rear_mount_gasket", COWL_REAR - 0.002, 0.695, 0.017, materials["rubber"])

    # Kühlluftöffnung: dunkler Rückraum, kräftige Lippe und angedeutete
    # Luftleitbleche vor dem vollständig verkleideten Doppelsternmotor.
    cylinder(
        "cooling_inlet_shadow",
        0.615,
        0.030,
        (0.0, COWL_FRONT - 0.012, 0.0),
        (0.0, 1.0, 0.0),
        materials["dark"],
        40,
    )
    torus_y("cooling_inlet_lip", COWL_FRONT + 0.012, 0.625, 0.058, materials["engine"])
    cylinder(
        "gear_case",
        0.225,
        0.145,
        (0.0, 0.670, 0.0),
        (0.0, 1.0, 0.0),
        materials["metal"],
        28,
        0.008,
    )
    for index in range(9):
        angle = math.tau * index / 9
        radial = Vector((math.cos(angle), 0.0, math.sin(angle)))
        cylinder_between(
            "radial_cooling_baffle",
            radial * 0.245 + Vector((0.0, 0.637, 0.0)),
            radial * 0.570 + Vector((0.0, 0.637, 0.0)),
            0.028,
            materials["panel"],
            10,
        )

    # Blechstöße und eingelassene Befestiger. Die Kugeln schneiden die Haut um
    # mehr als ihren halben Radius und können daher nicht über ihr schweben.
    for seam_y in (-0.58, -0.24, 0.18):
        torus_y(
            "cowling_panel_seam",
            seam_y,
            cowl_radius_at(seam_y) + 0.002,
            0.006,
            materials["panel"],
        )
    for seam_y in (-0.57, 0.17):
        radius = cowl_radius_at(seam_y) + 0.003
        for index in range(16):
            angle = math.tau * index / 16
            sphere(
                "flush_fastener",
                0.014,
                (
                    math.cos(angle) * radius,
                    seam_y,
                    math.sin(angle) * radius,
                ),
                materials["metal"],
                (1.0, 0.55, 1.0),
            )

    build_cowl_flaps(materials)

    # Unterer Ölkühler: beide Kästen durchdringen die Cowling deutlich, nur Lippe
    # und dunkle Öffnung bleiben sichtbar.
    box(
        "oil_cooler_lip",
        (0.38, 0.27, 0.075),
        (0.0, 0.02, -0.820),
        materials["engine"],
        rotation=(0.04, 0.0, 0.0),
        bevel=0.018,
    )
    box(
        "oil_cooler_opening",
        (0.285, 0.060, 0.050),
        (0.0, 0.135, -0.852),
        materials["dark"],
        rotation=(0.04, 0.0, 0.0),
        bevel=0.010,
    )

    # Zwei kurze, in der Seitenhaut steckende Abgasstutzen.
    for side in (-1.0, 1.0):
        cylinder(
            "exhaust_outlet_" + ("R" if side > 0.0 else "L"),
            0.052,
            0.24,
            (side * 0.825, -0.32, -0.235),
            (side, -0.12, -0.18),
            materials["exhaust"],
            16,
            0.004,
        )
        cylinder(
            "exhaust_collar_" + ("R" if side > 0.0 else "L"),
            0.075,
            0.035,
            (side * 0.790, -0.315, -0.226),
            (side, 0.0, 0.0),
            materials["metal"],
            18,
            0.003,
        )

    # Schwerer Curtiss-Electric-Vierblattpropeller. Der Pivot bleibt in
    # Blender identisch; die glTF-Y-up-Konvertierung macht aus Blender-Y
    # automatisch Godot-Z und hält die lokale Animationsebene korrekt.
    prop = bpy.data.objects.new("Prop", None)
    prop.empty_display_type = "PLAIN_AXES"
    prop.empty_display_size = 0.18
    bpy.context.collection.objects.link(prop)
    for index in range(4):
        build_propeller_blade(
            "prop_blade_%d" % (index + 1),
            math.tau * index / 4,
            prop,
            materials,
        )
    revolve_prop_local(
        "prop_hub",
        (
            (0.665, 0.255),
            (0.735, 0.285),
            (0.820, 0.265),
            (0.915, 0.205),
            (1.015, 0.105),
            (1.075, 0.0),
        ),
        32,
        materials["metal"],
        prop,
    )
    revolve_prop_local(
        "prop_backplate",
        ((0.625, 0.0), (0.640, 0.300), (0.690, 0.300), (0.705, 0.0)),
        32,
        materials["panel"],
        prop,
    )
    for index in range(8):
        angle = math.tau * index / 8
        bolt = sphere(
            "hub_bolt",
            0.018,
            (math.cos(angle) * 0.225, PROP_PLANE + 0.075, math.sin(angle) * 0.225),
            materials["dark"],
            (1.0, 0.55, 1.0),
        )
        bolt.parent = prop
        bolt.matrix_parent_inverse = Matrix.Identity(4)

    return cowl, prop


def apply_modifiers():
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            continue
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)


def world_bounds(objects):
    minimum = Vector((math.inf, math.inf, math.inf))
    maximum = Vector((-math.inf, -math.inf, -math.inf))
    for obj in objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            minimum.x = min(minimum.x, point.x)
            minimum.y = min(minimum.y, point.y)
            minimum.z = min(minimum.z, point.z)
            maximum.x = max(maximum.x, point.x)
            maximum.y = max(maximum.y, point.y)
            maximum.z = max(maximum.z, point.z)
    return minimum, maximum


def validate_model(model_objects):
    cowl = bpy.data.objects.get("B29_Cowling")
    prop = bpy.data.objects.get("Prop")
    blades = [obj for obj in model_objects if obj.name.startswith("prop_blade_")]
    if cowl is None or prop is None:
        raise RuntimeError("Cowling oder Prop-Pivot fehlt")
    if len(blades) != 4:
        raise RuntimeError(f"B-29-Propeller braucht genau vier Blätter, erhalten: {len(blades)}")
    cowl_min, cowl_max = world_bounds([cowl])
    cowl_size = cowl_max - cowl_min
    if not 1.67 < cowl_size.x < 1.69 or not 1.67 < cowl_size.z < 1.69:
        raise RuntimeError(f"Cowling-Durchmesser muss 1,68 m sein: {tuple(cowl_size)}")
    minimum, maximum = world_bounds(model_objects)
    overall = maximum - minimum
    if overall.x < 2.94 or overall.z < 2.94:
        raise RuntimeError(f"Vierblattpropeller ist zu klein: {tuple(overall)}")
    if not any(
        mat is not None and mat.name == "engine"
        for obj in model_objects
        if obj.type == "MESH"
        for mat in obj.data.materials
    ):
        raise RuntimeError("Lackierbares engine-Material fehlt")
    if COWL_REAR >= -0.80:
        raise RuntimeError("Plane hintere Montagefläche ist zu kurz")


def export_model(model_objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in model_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects["B29_Cowling"]
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


def setup_preview():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.world.color = (0.10, 0.16, 0.25)
    scene.view_settings.look = "Medium High Contrast"

    add_area("Preview_Key", (4.5, 4.0, 5.2), 1300, 4.0, (0.86, 0.93, 1.0))
    add_area("Preview_Fill", (-4.0, 2.0, 2.4), 800, 3.2, (0.54, 0.68, 1.0))
    add_area("Preview_Rim", (0.0, -4.0, 3.0), 950, 3.0, (0.72, 0.82, 1.0))

    bpy.ops.mesh.primitive_plane_add(size=12.0, location=(0.0, 0.0, -1.535))
    floor = bpy.context.object
    floor.name = "Preview_Floor"
    floor.data.materials.append(
        material("preview_floor", (0.23, 0.32, 0.45, 1.0), 0.0, 0.84)
    )

    bpy.ops.object.camera_add()
    camera = bpy.context.object
    camera.name = "B29_Engine_Camera"
    scene.camera = camera
    return camera


def render_view(camera, location, target, filepath, lens):
    camera.location = location
    camera.data.lens = lens
    camera.rotation_euler = (
        Vector(target) - camera.location
    ).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.render.filepath = str(filepath)
    bpy.ops.render.render(write_still=True)


def build():
    clear()
    materials = make_materials()
    build_model(materials)
    apply_modifiers()
    model_objects = list(bpy.context.scene.objects)
    validate_model(model_objects)
    export_model(model_objects)

    camera = setup_preview()
    render_view(
        camera,
        (4.4, 4.9, 2.8),
        (0.0, 0.10, 0.0),
        PREVIEW_OUT,
        64,
    )
    render_view(
        camera,
        (0.0, 7.2, 0.10),
        (0.0, 0.15, 0.0),
        FRONT_OUT,
        64,
    )
    render_view(
        camera,
        (6.8, 0.0, 0.25),
        (0.0, 0.0, 0.0),
        SIDE_OUT,
        62,
    )

    camera.location = (4.4, 4.9, 2.8)
    camera.data.lens = 64
    camera.rotation_euler = (
        Vector((0.0, 0.10, 0.0)) - camera.location
    ).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    print("EXPORTED", GLB_OUT)
    print("SAVED", BLEND_OUT)
    print("RENDERED", PREVIEW_OUT, FRONT_OUT, SIDE_OUT)


if __name__ == "__main__":
    build()
