from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "models" / "spitfire_cockpit.glb"
OUT_DIR = ROOT / "tools"

VIEWS = {
    "side": Vector((2.6, -0.15, 0.7)),
    "threequarter": Vector((2.0, 2.7, 1.45)),
    "top": Vector((0.02, 0.10, 3.0)),
}


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def setup_scene():
    try:
        bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
        bpy.context.scene.eevee.taa_render_samples = 80
    except Exception:
        pass
    bpy.context.scene.view_settings.view_transform = "Filmic"
    bpy.context.scene.view_settings.look = "Medium High Contrast"
    bpy.context.scene.render.resolution_x = 1100
    bpy.context.scene.render.resolution_y = 760
    bpy.context.scene.world = bpy.data.worlds.new("spitfire_cockpit_world")
    bpy.context.scene.world.color = (0.58, 0.64, 0.72)


def add_light(name, loc, energy):
    bpy.ops.object.light_add(type="AREA", location=loc)
    light = bpy.context.object
    light.name = name
    light.data.energy = energy
    light.data.size = 3.5


def bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    found = False
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            co = obj.matrix_world @ Vector(corner)
            for i in range(3):
                lo[i] = min(lo[i], co[i])
                hi[i] = max(hi[i], co[i])
            found = True
    return (lo, hi) if found else (Vector((-1, -1, -1)), Vector((1, 1, 1)))


def look_at(obj, target):
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render():
    clear_scene()
    setup_scene()
    bpy.ops.import_scene.gltf(filepath=str(MODEL))
    lo, hi = bounds()
    center = (lo + hi) * 0.5
    size = hi - lo
    max_dim = max(size.x, size.y, size.z, 0.1)

    add_light("key", center + Vector((2.5, 3.1, 3.0)), 720)
    add_light("fill", center + Vector((-2.7, -2.4, 1.7)), 170)
    add_light("rim", center + Vector((0.2, -3.0, 2.6)), 260)

    bpy.ops.mesh.primitive_cube_add(size=1, location=(center.x, center.y, lo.z - 0.025))
    ground = bpy.context.object
    ground.name = "inspection_floor"
    ground.dimensions = (max_dim * 1.9, max_dim * 1.9, 0.012)
    mat = bpy.data.materials.new("matte_floor")
    mat.diffuse_color = (0.43, 0.47, 0.52, 1)
    ground.data.materials.append(mat)

    bpy.ops.object.camera_add()
    cam = bpy.context.object
    bpy.context.scene.camera = cam
    cam.data.type = "ORTHO"

    for name, direction in VIEWS.items():
        d = direction.normalized()
        cam.location = center + d * (max_dim * 4.1)
        look_at(cam, center + Vector((0, 0, 0.10)))
        cam.data.ortho_scale = max_dim * (1.08 if name != "top" else 1.20)
        bpy.context.scene.render.filepath = str(OUT_DIR / f"spitfire_cockpit_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("RENDERED=" + bpy.context.scene.render.filepath)


if __name__ == "__main__":
    render()
