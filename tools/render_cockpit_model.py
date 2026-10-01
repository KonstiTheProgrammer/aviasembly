from pathlib import Path
import math

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "models"
OUT_DIR = ROOT / "tools"


VIEWS = {
    "side": Vector((2.8, -0.25, 0.8)),
    "threequarter": Vector((1.9, -2.4, 1.35)),
    "top": Vector((0.02, -0.35, 3.0)),
}


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def setup_scene():
    try:
        bpy.context.scene.render.engine = "BLENDER_EEVEE_NEXT"
        bpy.context.scene.eevee.taa_render_samples = 64
    except Exception:
        pass
    bpy.context.scene.view_settings.view_transform = "Filmic"
    bpy.context.scene.view_settings.look = "Medium High Contrast"
    bpy.context.scene.render.resolution_x = 980
    bpy.context.scene.render.resolution_y = 700
    bpy.context.scene.world = bpy.data.worlds.new("cockpit_world")
    bpy.context.scene.world.color = (0.62, 0.68, 0.78)


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
    bpy.ops.import_scene.gltf(filepath=str(MODEL_DIR / "cockpit.glb"))
    lo, hi = bounds()
    center = (lo + hi) * 0.5
    size = hi - lo
    max_dim = max(size.x, size.y, size.z, 0.1)

    add_light("key", center + Vector((2.4, -3.0, 3.1)), 620)
    add_light("fill", center + Vector((-2.6, 2.4, 1.8)), 130)

    bpy.ops.mesh.primitive_cube_add(size=1, location=(center.x, center.y, lo.z - 0.02))
    ground = bpy.context.object
    ground.name = "inspection_floor"
    ground.dimensions = (max_dim * 1.7, max_dim * 1.7, 0.012)
    mat = bpy.data.materials.new("matte_floor")
    mat.diffuse_color = (0.46, 0.50, 0.55, 1)
    ground.data.materials.append(mat)

    bpy.ops.object.camera_add()
    cam = bpy.context.object
    bpy.context.scene.camera = cam
    cam.data.type = "ORTHO"

    for name, direction in VIEWS.items():
        d = direction.normalized()
        cam.location = center + d * (max_dim * 4.0)
        look_at(cam, center + Vector((0, 0, 0.08)))
        cam.data.ortho_scale = max_dim * (1.10 if name != "top" else 1.20)
        bpy.context.scene.render.filepath = str(OUT_DIR / f"cockpit_open_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("RENDERED=" + bpy.context.scene.render.filepath)


if __name__ == "__main__":
    render()
