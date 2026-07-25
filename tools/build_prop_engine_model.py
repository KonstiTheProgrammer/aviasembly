import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
OUT_FULL = ROOT / "models" / "prop_engine.glb"
OUT_CUT = ROOT / "models" / "prop_engine_nose.glb"


def mat(name, color, metallic=0.0, roughness=0.45):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.use_backface_culling = False
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return m


# Die große Verkleidung ist bewusst lackiertes, fast nicht-metallisches Weiß.
# Der Materialname "engine" bleibt erhalten, damit die Lackierfunktion in Godot
# weiterhin nur die Verkleidung (und nicht Holz, Auspuff oder Gummi) umfärbt.
ENGINE = mat("engine", (0.92, 0.94, 0.95, 1), 0.04, 0.40)
ENGINE_DARK = mat("engine_dark", (0.20, 0.22, 0.24, 1), 0.18, 0.62)
METAL = mat("metal", (0.42, 0.44, 0.46, 1), 0.68, 0.34)
DARK = mat("dark", (0.012, 0.014, 0.017, 1), 0.08, 0.88)
EXHAUST = mat("exhaust", (0.075, 0.060, 0.052, 1), 0.48, 0.66)
RUBBER = mat("rubber", (0.025, 0.027, 0.030, 1), 0.0, 0.92)
BRASS = mat("brass", (0.82, 0.58, 0.20, 1), 0.48, 0.34)
WOOD = mat("wood", (0.50, 0.28, 0.105, 1), 0.04, 0.38)
WOOD_GRAIN = mat("wood_grain", (0.19, 0.095, 0.032, 1), 0.02, 0.54)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def shade(obj, bevel=0.0, weighted=True):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        bpy.ops.object.shade_smooth()
    except Exception:
        pass
    obj.select_set(False)
    if bevel > 0.0:
        be = obj.modifiers.new("soft bevel", "BEVEL")
        be.width = bevel
        be.segments = 3
        be.affect = "EDGES"
        obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")
    elif weighted:
        obj.modifiers.new("weighted normals", "WEIGHTED_NORMAL")


def revolve_y(name, profile, segments, material):
    verts = []
    faces = []
    for yi, r in profile:
        for s in range(segments):
            a = math.tau * s / segments
            verts.append((math.cos(a) * r, yi, math.sin(a) * r))
    rows = len(profile)
    for row in range(rows - 1):
        for s in range(segments):
            a = row * segments + s
            b = row * segments + (s + 1) % segments
            c = (row + 1) * segments + s
            d = (row + 1) * segments + (s + 1) % segments
            faces.append((a, c, b))
            faces.append((b, c, d))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    shade(obj, 0.012)
    return obj


def cyl(name, radius, depth, loc, axis, material, vertices=32, bevel=0.0, parent=None):
    axis = Vector(axis).normalized()
    rot = axis.to_track_quat("Z", "Y").to_euler()
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "Mesh"
    obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    shade(obj, bevel)
    return obj


def sphere(name, radius, loc, material, scale=(1, 1, 1), parent=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=radius, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    shade(obj, 0.003)
    return obj


def box(name, size, loc, material, rotation=(0, 0, 0), bevel=0.0, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    shade(obj, bevel)
    return obj


def torus_y(name, loc, major, minor, material, parent=None):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=72,
        minor_segments=12,
        major_radius=major,
        minor_radius=minor,
        location=loc,
        rotation=(math.pi / 2, 0, 0),
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    shade(obj)
    return obj


def curve_tube(name, points, material, bevel=0.008, parent=None):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.resolution_u = 3
    cu.bevel_depth = bevel
    cu.bevel_resolution = 3
    spl = cu.splines.new("POLY")
    spl.points.add(len(points) - 1)
    for p, co in zip(spl.points, points):
        p.co = (co[0], co[1], co[2], 1.0)
    obj = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def curve_tube_local(name, points, material, bevel=0.008, parent=None):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.resolution_u = 4
    cu.bevel_depth = bevel
    cu.bevel_resolution = 2
    spl = cu.splines.new("BEZIER")
    spl.bezier_points.add(len(points) - 1)
    for p, co in zip(spl.bezier_points, points):
        p.co = co
        p.handle_left_type = "AUTO"
        p.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    if parent is not None:
        obj.parent = parent
    return obj


def blade_mesh(name, angle, parent):
    # Geloftetes Holzblatt mit elliptischem Querschnitt. Das bleibt aus jeder
    # Blickrichtung ein runder 3D-Körper statt einer einseitigen flachen Fläche.
    # Wichtig: Die Geometrie liegt im LOKALEN XY-Kreis des "Prop"-Nodes; dessen
    # lokale Z-Achse ist die Propellerachse. Dadurch bleiben beide Blätter beim
    # glTF-Export sauber in einer Ebene und Godot kann den Node per rotate_z drehen.
    radial = Vector((math.cos(angle), math.sin(angle), 0))
    tangent = Vector((-math.sin(angle), math.cos(angle), 0))
    stations = [
        (0.10, 0.085, 0.018, 0.034),
        (0.26, 0.160, 0.030, 0.023),
        (0.58, 0.200, 0.034, 0.004),
        (0.95, 0.145, 0.026, -0.014),
        (1.28, 0.032, 0.010, -0.030),
    ]
    ring = 16
    verts = []
    for r, half_chord, thick, yoff in stations:
        center = radial * r + Vector((0, 0, 0.79 + yoff))
        for k in range(ring):
            t = math.tau * k / ring
            verts.append(tuple(center + tangent * (math.cos(t) * half_chord) + Vector((0, 0, math.sin(t) * thick))))
    faces = []
    for i in range(len(stations) - 1):
        for k in range(ring):
            a = i * ring + k
            b = i * ring + (k + 1) % ring
            c = (i + 1) * ring + k
            d = (i + 1) * ring + (k + 1) % ring
            faces.append((a, c, b))
            faces.append((b, c, d))
    root_center = len(verts)
    verts.append(tuple(radial * stations[0][0] + Vector((0, 0, 0.79 + stations[0][3]))))
    tip_center = len(verts)
    verts.append(tuple(radial * stations[-1][0] + Vector((0, 0, 0.79 + stations[-1][3]))))
    for k in range(ring):
        faces.append((root_center, k, (k + 1) % ring))
        a = (len(stations) - 1) * ring + k
        b = (len(stations) - 1) * ring + (k + 1) % ring
        faces.append((tip_center, b, a))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(WOOD)
    obj.parent = parent
    shade(obj, 0.010)

    return obj


def blade_grain(angle, parent):
    radial = Vector((math.cos(angle), math.sin(angle), 0))
    tangent = Vector((-math.sin(angle), math.cos(angle), 0))
    # Vorderseite der Blätter: lokale +Z-Richtung liegt nach der Prop-Rotation
    # in Blender vorne (+Y). Kleine Rohre lesen im Spiel wie lackierte Holzmaserung.
    for line_i, off in enumerate((-0.060, -0.020, 0.028, 0.066)):
        pts = []
        for r, wiggle, z in (
            (0.25, 0.000, 0.862),
            (0.48, 0.014, 0.850),
            (0.76, -0.012, 0.834),
            (1.05, 0.010, 0.814),
        ):
            pts.append(radial * r + tangent * (off + wiggle) + Vector((0, 0, z)))
        curve_tube_local("blade_wood_grain", pts, WOOD_GRAIN, 0.0055, parent)


def blade_tip(name, angle, parent):
    radial = Vector((math.cos(angle), math.sin(angle), 0))
    tangent = Vector((-math.sin(angle), math.cos(angle), 0))
    r = 1.165
    half_chord = 0.064
    thick = 0.011
    yoff = -0.025
    ring = 14
    verts = []
    for rr, scale in ((r, 1.0), (1.285, 0.18)):
        center = radial * rr + Vector((0, 0, 0.79 + yoff))
        for k in range(ring):
            t = math.tau * k / ring
            verts.append(tuple(center + tangent * (math.cos(t) * half_chord * scale) + Vector((0, 0, math.sin(t) * thick * scale))))
    faces = []
    for k in range(ring):
        a = k
        b = (k + 1) % ring
        c = ring + k
        d = ring + (k + 1) % ring
        faces.append((a, c, b))
        faces.append((b, c, d))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(BRASS)
    obj.parent = parent
    shade(obj, 0.004)
    return obj


def build(cut_for_fuselage=False):
    clear()

    # Blender +Y ist Godot -Z / vorne. Die angedockte Variante endet bei
    # y=-0.54 in einer echten planen Schnittfläche; die freistehende Gondel
    # läuft weiter nach hinten und bekommt einen runden Abschluss.
    rear = -0.54 if cut_for_fuselage else -0.80
    profile = (
        [
            (rear, 0.545), (-0.43, 0.555), (-0.12, 0.565),
            (0.22, 0.552), (0.39, 0.505), (0.50, 0.425), (0.55, 0.345),
        ]
        if cut_for_fuselage
        else [
            (rear, 0.10), (-0.74, 0.32), (-0.62, 0.49), (-0.43, 0.555),
            (-0.12, 0.565), (0.22, 0.552), (0.39, 0.505),
            (0.50, 0.425), (0.55, 0.345),
        ]
    )
    revolve_y(
        "painted_cowl",
        profile,
        96,
        ENGINE,
    )
    # Geschlossene Stirn statt sichtbarem Sternmotor: weißes Getriebegehäuse,
    # schmaler Kühlluftspalt und zentrale dunkle Wellenaufnahme.
    cyl("front_face", 0.350, 0.055, (0, 0.568, 0), (0, 1, 0), ENGINE, 72, 0.008)
    torus_y("front_rolled_lip", (0, 0.554, 0), 0.408, 0.036, ENGINE)
    torus_y("annular_cooling_slot", (0, 0.577, 0), 0.318, 0.022, DARK)
    cyl("gearbox_face", 0.205, 0.070, (0, 0.606, 0), (0, 1, 0), ENGINE_DARK, 64, 0.007)
    cyl("shaft_bearing", 0.105, 0.100, (0, 0.653, 0), (0, 1, 0), METAL, 48, 0.006)

    # Klare Blechstöße, mittige Teilfuge und ein sauberer Anschlussring.
    torus_y("front_panel_seam", (0, 0.335, 0), 0.526, 0.006, ENGINE_DARK)
    torus_y("rear_panel_seam", (0, -0.405, 0), 0.548, 0.006, ENGINE_DARK)
    if cut_for_fuselage:
        cyl("flat_fuselage_cut", 0.545, 0.018, (0, rear + 0.009, 0), (0, 1, 0), ENGINE, 96)
        torus_y("fuselage_cut_gasket", (0, rear - 0.002, 0), 0.522, 0.018, RUBBER)
    else:
        torus_y("rear_mount_ring", (0, -0.650, 0), 0.475, 0.018, ENGINE_DARK)

    # Befestiger rund um die Stirn und den hinteren Wartungsring.
    for ring_y, rad, count in ((0.574, 0.455, 20), (-0.405, 0.553, 18)):
        for i in range(count):
            a = math.tau * i / count
            sphere("flush_fastener", 0.011, (math.cos(a) * rad, ring_y, math.sin(a) * rad),
                   METAL, (1, 0.42, 1))

    # Seitliche Kühlkiemen: dunkle Öffnung plus jeweils eine leicht vorstehende
    # weiße Lamelle. Das liest auch aus Paletten-Distanz als echter Reihenmotor.
    for side in (-1, 1):
        for i in range(5):
            y = -0.16 + i * 0.105
            box("cooling_louver_shadow", (0.020, 0.075, 0.068),
                (side * 0.557, y, 0.105), DARK, bevel=0.006)
            box("cooling_louver", (0.027, 0.092, 0.016),
                (side * 0.568, y - 0.012, 0.147), ENGINE, rotation=(0.12, 0, 0), bevel=0.004)

    # Wartungsklappe oben mit Scharnier, Schnellverschlüssen und Öleinfülldeckel.
    box("service_panel", (0.36, 0.34, 0.014), (0, -0.105, 0.557),
        ENGINE_DARK, bevel=0.010)
    box("service_panel_inset", (0.335, 0.315, 0.012), (0, -0.105, 0.565),
        ENGINE, bevel=0.008)
    for x in (-0.135, 0.135):
        for y in (-0.22, 0.01):
            sphere("service_panel_fastener", 0.013, (x, y, 0.577), METAL, (1, 1, 0.45))
    cyl("service_hinge", 0.018, 0.245, (-0.185, -0.105, 0.575), (0, 1, 0),
        ENGINE_DARK, 18, 0.002)
    cyl("oil_cap", 0.045, 0.030, (0.12, -0.255, 0.587), (0, 0, 1),
        ENGINE_DARK, 24, 0.003)

    # Vier Abgasstutzen pro Seite: dunkles brüniertes Metall, klar als
    # Reihen-/Boxermotor-Detail und nicht als radial angeordnete Zylinder.
    for side in (-1, 1):
        for i in range(4):
            y = -0.22 + i * 0.14
            cyl("exhaust_stack", 0.027, 0.135, (side * 0.607, y, -0.145),
                (side, 0.10, -0.04), EXHAUST, 18, 0.003)
            cyl("exhaust_collar", 0.041, 0.025, (side * 0.552, y - side * 0.003, -0.14),
                (side, 0, 0), METAL, 20, 0.002)

    # Unterer Kühllufteinlauf mit echter schwarzer Öffnung und lackierter Lippe.
    box("lower_intake_lip", (0.34, 0.22, 0.085), (0, 0.13, -0.548),
        ENGINE, rotation=(0.04, 0, 0), bevel=0.025)
    box("lower_intake_opening", (0.265, 0.055, 0.060), (0, 0.225, -0.575),
        DARK, rotation=(0.04, 0, 0), bevel=0.018)

    # Prop group. Rotate the empty so its local Z axis is Blender +Y; Godot rotate_z spins around the prop axis.
    prop = bpy.data.objects.new("Prop", None)
    prop.empty_display_type = "PLAIN_AXES"
    prop.empty_display_size = 0.2
    prop.location = (0, 0, 0)
    prop.rotation_euler = (-math.pi / 2, 0, 0)
    bpy.context.collection.objects.link(prop)
    blade_angles = (math.pi / 2, math.pi * 1.5)
    for ba in blade_angles:
        blade_mesh("wood_blade", ba, prop)
        blade_grain(ba, prop)
        blade_tip("painted_blade_tip", ba, prop)
    cyl("prop_back_plate", 0.245, 0.058, (0, 0.708, 0), (0, 1, 0), DARK, 64, 0.004, prop)
    cyl("prop_hub_metal", 0.182, 0.122, (0, 0.752, 0), (0, 1, 0), METAL, 64, 0.007, prop)
    sphere("painted_spinner", 0.185, (0, 0.838, 0), ENGINE, (1, 0.82, 1), prop)
    sphere("spinner_cap", 0.060, (0, 0.966, 0), METAL, (1, 0.60, 1), prop)
    for i in range(6):
        a = math.tau * i / 6
        sphere("hub_bolt", 0.019, (math.cos(a) * 0.153, 0.817, math.sin(a) * 0.153),
               BRASS, (1, 0.65, 1), prop)

    # Kleine gerundete Montageösen oben.
    for x in (-0.23, 0.23):
        cyl("top_mount", 0.036, 0.14, (x, -0.37, 0.565), (1, 0, 0),
            ENGINE_DARK, 18, 0.003)

    # Apply modifiers for exported smooth/beveled geometry.
    for obj in list(bpy.context.scene.objects):
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        for mod in list(obj.modifiers):
            try:
                bpy.ops.object.modifier_apply(modifier=mod.name)
            except Exception:
                pass
        obj.select_set(False)

    out = OUT_CUT if cut_for_fuselage else OUT_FULL
    bpy.ops.export_scene.gltf(filepath=str(out), export_format="GLB", export_yup=True)
    print("EXPORTED", out)


def build_all():
    build(False)
    build(True)


if __name__ == "__main__":
    build_all()
