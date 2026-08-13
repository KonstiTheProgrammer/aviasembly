"""Erzeugt den Aviassembly-Raketenantrieb komplett neu in Blender.

Achsenvertrag: +Y = Montage/Front, -Y = Auslass, +Z = oben.
Das Skript verwendet keine bestehende Blend-/GLB-Datei.
"""
import bpy
import bmesh
import math
import os
from mathutils import Vector

PROJECT = "/Users/konstantinkanzler/Projects/aviasembly"
BLEND = os.path.join(PROJECT, "blender_lib", "rocket_engine.blend")
GLB = os.path.join(PROJECT, "models", "rocket_engine.glb")
REVIEW = "/private/tmp/rocket_engine_final_review"
TAU = math.tau


def material(name, color, metallic, roughness):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1.0)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Metallic"].default_value = metallic
    p.inputs["Roughness"].default_value = roughness
    return m


def finish(obj, name, mat, bevel=0.0):
    obj.name = name
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new("Kantenradius", "BEVEL")
        mod.width = bevel
        mod.segments = 2
    return obj


def cylinder_y(name, loc, radius, depth, mat, vertices=32, bevel=0.004):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=loc,
        rotation=(math.pi / 2.0, 0.0, 0.0))
    return finish(bpy.context.view_layer.objects.active, name, mat, bevel)


def cylinder_axis(name, loc, axis, radius, depth, mat, vertices=24, bevel=0.004):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    obj = bpy.context.view_layer.objects.active
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(Vector(axis).normalized())
    return finish(obj, name, mat, bevel)


def box(name, loc, scale, mat, bevel=0.008, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rotation)
    obj = bpy.context.view_layer.objects.active
    obj.scale = tuple(v * 0.5 for v in scale)
    return finish(obj, name, mat, bevel)


def torus_y(name, loc, major, minor, mat, major_segments=48, minor_segments=8):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major, minor_radius=minor,
        major_segments=major_segments, minor_segments=minor_segments,
        location=loc, rotation=(math.pi / 2.0, 0.0, 0.0))
    return finish(bpy.context.view_layer.objects.active, name, mat)


def revolve(name, profile, mat, segments=64, smooth=True):
    verts = []
    for i in range(segments):
        a = TAU * i / segments
        for r, y in profile:
            verts.append((r * math.cos(a), y, r * math.sin(a)))
    n = len(profile)
    faces = []
    for i in range(segments):
        j = (i + 1) % segments
        for p in range(n - 1):
            faces.append((i*n+p, j*n+p, j*n+p+1, i*n+p+1))
    me = bpy.data.meshes.new(name + "Mesh")
    me.from_pydata(verts, [], faces)
    me.materials.append(mat)
    for f in me.polygons:
        f.use_smooth = smooth
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def pipe(name, points, radius, mat, resolution=2):
    cu = bpy.data.curves.new(name + "Curve", "CURVE")
    cu.dimensions = "3D"
    cu.resolution_u = resolution
    cu.bevel_depth = radius
    cu.bevel_resolution = 2
    sp = cu.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for bp, co in zip(sp.bezier_points, points):
        bp.co = co
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
    cu.materials.append(mat)
    obj = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def bell_radius(y):
    t = max(0.0, min(1.0, (-0.20 - y) / 0.82))
    return 0.18 + 0.35 * (0.08*t + 0.92*(t**1.58))


def hex_bolt_ring(prefix, y, radius, count, size, mat):
    for i in range(count):
        a = TAU * i / count
        cylinder_y(
            f"{prefix}_{i+1:02d}",
            (radius*math.cos(a), y, radius*math.sin(a)),
            size, size*0.72, mat, 6, 0.002)


def build():
    bpy.ops.wm.read_homefile(use_empty=True, use_factory_startup=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "METERS"
    os.makedirs(os.path.dirname(BLEND), exist_ok=True)
    os.makedirs(os.path.dirname(GLB), exist_ok=True)
    os.makedirs(REVIEW, exist_ok=True)

    mats = {
        "engine": material("engine", (0.185, 0.171, 0.153), 0.60, 0.52),
        "gunmetal": material("gunmetal", (0.034, 0.037, 0.040), 0.70, 0.42),
        "copper": material("copper", (0.258, 0.078, 0.036), 0.75, 0.46),
        "tube": material("tube", (0.159, 0.047, 0.026), 0.70, 0.50),
        "throat": material("throat", (0.021, 0.020, 0.021), 0.55, 0.55),
        "band": material("band", (0.060, 0.065, 0.068), 0.68, 0.38),
        "lip": material("lip", (0.091, 0.093, 0.102), 0.75, 0.36),
        "soot": material("soot", (0.009, 0.010, 0.010), 0.0, 0.72),
    }

    # Kompakter 12-facettierter Montagekörper mit offener, tiefer Frontbohrung.
    cylinder_y("Montagetrommel", (0, 0.70, 0), 0.455, 0.62, mats["engine"], 12, 0.012)
    revolve("Frontkragen", [(0.31, 0.98), (0.515, 0.98), (0.515, 1.105), (0.31, 1.105)], mats["engine"], 12, False)
    revolve("Frontbohrung_Tief", [(0.285, 0.76), (0.310, 0.76), (0.310, 1.106), (0.285, 1.106)], mats["soot"], 48)
    cylinder_y("Bohrung_Schatten", (0, 0.755, 0), 0.282, 0.018, mats["soot"], 48)
    hex_bolt_ring("Frontbolzen", 1.118, 0.415, 12, 0.045, mats["gunmetal"])
    for y in (0.47, 0.67, 0.87):
        revolve(f"Trommelband_{y:.2f}", [(0.452, y-.018), (0.472, y-.018), (0.472, y+.018), (0.452, y+.018)], mats["band"], 48)
        hex_bolt_ring(f"Bandbolzen_{y:.2f}", y, 0.48, 8, 0.020, mats["gunmetal"])

    # Facettierte Brennkammer und gestufter Hals.
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=1.0, location=(0, 0.12, 0))
    chamber = finish(bpy.context.view_layer.objects.active, "Facettierte_Brennkammer", mats["engine"])
    chamber.scale = (0.36, 0.41, 0.36)
    cylinder_y("Kammerflansch_vorn", (0, 0.43, 0), 0.385, 0.08, mats["band"], 48, 0.006)
    cylinder_y("Kammerflansch_hinten", (0, -0.19, 0), 0.285, 0.075, mats["band"], 48, 0.006)
    cylinder_y("Duesenhals", (0, -0.245, 0), 0.205, 0.12, mats["throat"], 48, 0.005)

    # Gebauchte Glocke: dunkle Haut, 48 durchgehende Außenkanäle, genau ein Band.
    ys = [-0.27 + i*(-0.75/24) for i in range(25)]
    outer = [(bell_radius(y), y) for y in ys]
    revolve("Glocken_Aussenhaut", outer, mats["throat"], 96)
    inner = [(max(0.135, bell_radius(y)-0.030), y) for y in ys]
    revolve("Glocken_Innenhaut", inner, mats["soot"], 96)
    for i in range(48):
        a = TAU*i/48
        pts = []
        inner_pts = []
        for y in ys:
            r = bell_radius(y) + 0.013
            pts.append((r*math.cos(a), y, r*math.sin(a)))
            ri = max(0.125, bell_radius(y)-0.043)
            inner_pts.append((ri*math.cos(a), y, ri*math.sin(a)))
        pipe(f"Kuehlkanal_Aussen_{i:02d}", pts, 0.0065, mats["tube"], 1)
        pipe(f"Kuehlkanal_Innen_{i:02d}", inner_pts, 0.0035, mats["copper"], 1)
    by = -0.68
    br = bell_radius(by)
    revolve("Glocke_Einzelband", [(br+.006, by-.025), (br+.026, by-.025), (br+.026, by+.025), (br+.006, by+.025)], mats["band"], 96)
    revolve("Auslasslippe", [(0.505,-1.050), (0.550,-1.050), (0.550,-0.985), (0.505,-0.985)], mats["lip"], 64, False)

    # Tiefer Halsabschluss/Injector für den axialen Auslassblick.
    cylinder_y("Injectorplatte", (0, -0.245, 0), 0.145, 0.018, mats["throat"], 32)
    for i in range(19):
        if i == 0:
            x = z = 0.0
        elif i <= 6:
            a = TAU*(i-1)/6; x, z = 0.052*math.cos(a), 0.052*math.sin(a)
        else:
            a = TAU*(i-7)/12; x, z = 0.102*math.cos(a), 0.102*math.sin(a)
        cylinder_y(f"Injectoroeffnung_{i:02d}", (x, -0.258, z), 0.010, 0.010, mats["soot"], 16)

    # Pumpenkrone: dominante gerippte Hauptvolute plus kleinere Nebenaggregate.
    cylinder_axis("Hauptpumpe", (0.32, 0.25, 0.27), (1,0,0), 0.145, 0.20, mats["gunmetal"], 40, 0.008)
    torus_y("Hauptpumpen_Volute", (0.425, 0.25, 0.27), 0.112, 0.036, mats["gunmetal"], 40, 10)
    for j in range(5):
        cylinder_axis(f"Pumpenrippe_{j}", (0.225+j*0.042, 0.25, 0.27), (1,0,0), 0.155, 0.012, mats["band"], 40)
    for i in range(10):
        a = TAU*i/10
        cylinder_axis(f"Pumpenbolzen_{i}", (0.438, 0.25+0.118*math.cos(a), 0.27+0.118*math.sin(a)), (1,0,0), 0.012, 0.022, mats["lip"], 6)
    cylinder_axis("Pumpen_Tangentialstutzen", (0.35, 0.22, 0.43), (0,0,1), 0.050, 0.24, mats["gunmetal"], 24, 0.006)
    cylinder_axis("Nebenpumpe", (-0.30, 0.17, -0.20), (1,0,0), 0.105, 0.22, mats["gunmetal"], 32, 0.006)
    cylinder_y("Ventildom", (-0.20, 0.18, 0.35), 0.10, 0.18, mats["gunmetal"], 32, 0.006)
    torus_y("Ventildomflansch", (-0.20, 0.09, 0.35), 0.10, 0.018, mats["band"], 32, 8)

    # Abschließende Kritik-Korrektur: kompakte obere Pumpen-/Ventilkrone statt
    # leerer Kammeroberseite. Zwei gestufte Pumpen und ein Verteiler, alle Bögen
    # enden sichtbar an einem Flansch und nicht im freien Raum.
    for side, x in (("L", -0.17), ("R", 0.16)):
        cylinder_axis(f"Oberpumpe_{side}", (x, 0.28, 0.43), (1,0,0), 0.085, 0.15,
                      mats["gunmetal"], 32, 0.005)
        cylinder_axis(f"Oberpumpe_{side}_Deckel", (x + (0.085 if side == "R" else -0.085), 0.28, 0.43),
                      (1,0,0), 0.105, 0.026, mats["band"], 32, 0.003)
        for j in range(3):
            cylinder_axis(f"Oberpumpe_{side}_Rippe_{j}", (x-0.045+j*0.045, 0.28, 0.43),
                          (1,0,0), 0.094, 0.009, mats["lip"], 32)
    box("Oberer_Ventilblock", (0.0, 0.27, 0.535), (0.26, 0.15, 0.095), mats["gunmetal"], 0.012)
    cylinder_y("Ventilblock_Dom", (0.0, 0.25, 0.595), 0.065, 0.10, mats["band"], 24, 0.004)
    crown_routes = [
        [(-.25,.28,.43),(-.31,.18,.50),(-.25,.02,.43),(-.13,-.08,.34)],
        [(.25,.28,.43),(.31,.17,.48),(.25,.00,.39),(.14,-.10,.31)],
        [(-.12,.27,.54),(-.20,.38,.50),(-.29,.43,.35),(-.34,.39,.22)],
        [(.12,.27,.54),(.20,.38,.50),(.30,.42,.35),(.36,.34,.24)],
        [(-.08,.22,.52),(-.10,.08,.47),(-.04,-.05,.38),(0,-.14,.27)],
        [(.08,.22,.52),(.12,.08,.45),(.08,-.04,.35),(.04,-.15,.26)],
        [(-.18,.31,.36),(-.28,.38,.26),(-.32,.31,.12),(-.30,.20,-.02)],
        [(.18,.31,.36),(.29,.37,.26),(.34,.30,.13),(.33,.22,.00)],
    ]
    for i, pts in enumerate(crown_routes):
        radius = 0.019 if i < 4 else 0.014
        pipe(f"Kronenbogen_{i+1:02d}", pts, radius, mats["gunmetal"], 2)
        for end, point in enumerate((pts[0], pts[-1])):
            cylinder_axis(f"Kronenbogen_{i+1:02d}_Flansch_{end}", point, (1,0,0),
                          radius*1.65, radius*0.75, mats["band"], 20, 0.002)

    # Vier nachvollziehbar angeflanschte Hauptleitungsenden und lokale Kreisläufe.
    routes = [
        ("Hauptleitung_oben", [(-.32,.25,.40),(-.42,.18,.52),(-.22,-.05,.50),(.10,-.12,.42),(.24,.05,.34)], .035),
        ("Hauptleitung_unten", [(.33,.26,-.18),(.43,.10,-.30),(.22,-.10,-.38),(-.12,-.13,-.35),(-.28,.06,-.24)], .033),
        ("Querleitung", [(.42,.25,.27),(.48,.08,.18),(.40,-.14,.08),(.25,-.22,.04)], .025),
        ("Bypass", [(-.30,.17,-.20),(-.43,.22,-.05),(-.39,.32,.15),(-.20,.18,.35)], .021),
    ]
    for name, pts, rad in routes:
        pipe(name, pts, rad, mats["gunmetal"])
        for n, point in enumerate((pts[0], pts[-1])):
            cylinder_axis(f"{name}_Flansch_{n}", point, (1,0,0), rad*1.7, rad*0.7, mats["band"], 24, 0.003)
    copper_routes = [
        [(-.34,.42,.18),(-.42,.30,.02),(-.38,.08,-.15),(-.25,-.06,-.23)],
        [(.12,.48,.32),(.02,.35,.45),(-.10,.18,.40),(-.20,.18,.35)],
        [(.33,.34,-.12),(.28,.18,-.30),(.10,-.05,-.36),(-.12,-.13,-.35)],
    ]
    for i, pts in enumerate(copper_routes):
        pipe(f"Kupferleitung_{i}", pts, 0.009, mats["copper"])

    # Tragrahmen, Pumpensättel und kurze Aktuatoren.
    for x in (-0.45, 0.45):
        box(f"Laengstraeger_{x:+.2f}", (x,0.24,0), (0.045,0.72,0.055), mats["band"], 0.006)
    for z in (-0.40, 0.40):
        box(f"Quertraeger_{z:+.2f}", (0,0.23,z), (0.82,0.055,0.045), mats["band"], 0.006)
    for i, a in enumerate((0, math.pi/2, math.pi, 3*math.pi/2)):
        x, z = 0.41*math.cos(a), 0.41*math.sin(a)
        box(f"Gimbalrippe_{i}", (x,-0.13,z), (0.075,0.28,0.075), mats["gunmetal"], 0.008, (0,a,0))
    cylinder_axis("Gimbaltrunnion_L", (-0.48,0.00,0), (1,0,0), 0.065, 0.16, mats["gunmetal"], 24, 0.006)
    cylinder_axis("Gimbaltrunnion_R", (0.48,0.00,0), (1,0,0), 0.065, 0.16, mats["gunmetal"], 24, 0.006)

    # Ausgewertete Geometrie direkt in acht Meshgruppen backen. Das funktioniert auch
    # im eingeschränkten Blender-MCP-Kontext ohne selectionsensitive Operatoren.
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    sources = [o for o in bpy.data.objects if o.type in {"MESH", "CURVE"}]
    outputs = []
    for mat_name, mat in mats.items():
        group = [o for o in sources if o.data.materials and o.data.materials[0].name == mat_name]
        if not group:
            continue
        bm = bmesh.new()
        for obj in group:
            evaluated = obj.evaluated_get(deps)
            mesh_copy = bpy.data.meshes.new_from_object(evaluated, depsgraph=deps)
            mesh_copy.transform(obj.matrix_world)
            bm.from_mesh(mesh_copy)
            bpy.data.meshes.remove(mesh_copy)
        merged = bpy.data.meshes.new(f"rocket_engine_{mat_name}Mesh")
        bm.to_mesh(merged)
        bm.free()
        merged.materials.append(mat)
        joined = bpy.data.objects.new(f"rocket_engine_{mat_name}", merged)
        scene.collection.objects.link(joined)
        outputs.append(joined)
    for obj in sources:
        bpy.data.objects.remove(obj, do_unlink=True)

    # Vertrag exakt normieren: radial maximal 1,10 m, axial 2,155 m.
    vertices = [v.co for obj in outputs for v in obj.data.vertices]
    min_y = min(v.y for v in vertices)
    max_y = max(v.y for v in vertices)
    radial = max(max(abs(v.x), abs(v.z)) for v in vertices)
    radial_scale = 0.55 / radial
    axial_scale = 2.155 / (max_y - min_y)
    for obj in outputs:
        for v in obj.data.vertices:
            v.co.x *= radial_scale
            v.co.z *= radial_scale
            v.co.y = -1.05 + (v.co.y - min_y) * axial_scale
        obj.data.update()

    # Dauerhaft speichern und nur die acht Asset-Meshes exportieren.
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    bpy.ops.object.select_all(action="DESELECT")
    for o in outputs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=GLB, export_format="GLB", use_selection=True,
        export_apply=True, export_materials="EXPORT")

    # Acht kompakte Kontrollbilder; Studio wird nicht in der Quelldatei gespeichert.
    world = bpy.data.worlds.new("ReviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012,0.018,0.028,1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
    scene.world = world
    target = Vector((0,0.02,0.02))
    for i, (loc, energy, size) in enumerate([
        ((-2.5,-1.5,2.8),900,2.4), ((2.2,1.0,1.8),650,2.0), ((0,-1.5,-1.2),350,1.6)]):
        data = bpy.data.lights.new(f"ReviewLight{i}", "AREA")
        data.energy = energy; data.shape = "DISK"; data.size = size
        light = bpy.data.objects.new(f"ReviewLight{i}", data)
        scene.collection.objects.link(light); light.location = loc
        light.rotation_euler = (target-light.location).to_track_quat("-Z","Y").to_euler()
    cd = bpy.data.cameras.new("ReviewCameraData"); cd.lens = 62
    cam = bpy.data.objects.new("ReviewCamera", cd); scene.collection.objects.link(cam); scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512; scene.render.resolution_y = 512; scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    poses = {
        "000":(-3.4,0.0,.52), "045":(-2.9,1.8,.52), "090":(-3.4,0.0,-.42), "135":(-2.9,-1.8,.52),
        "180":(3.4,0.0,.52), "225":(2.9,-1.8,.52), "270":(3.4,0.0,-.42), "315":(2.9,1.8,.52),
    }
    for name, loc in poses.items():
        cam.location = loc
        cam.rotation_euler = (target-cam.location).to_track_quat("-Z","Y").to_euler()
        scene.render.filepath = os.path.join(REVIEW, name + ".png")
        bpy.ops.render.render(write_still=True)

    result = {
        "blend": BLEND, "glb": GLB, "review": REVIEW,
        "meshes": len([o for o in bpy.data.objects if o.type == "MESH"]),
        "triangles": sum(len(p.vertices)-2 for o in bpy.data.objects if o.type == "MESH" for p in o.data.polygons),
    }
    return result


result = build()
