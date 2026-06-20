# prop_engine.glb importieren, Heck flach wegschneiden (bisect + fill), als prop_engine_nose.glb
# exportieren. So ist das Modell wirklich durchgeschnitten (nichts steckt im Rumpf).
import bpy, bmesh
SRC = "C:/Users/Konst/Projects/aviasembly/models/prop_engine.glb"
OUT = "C:/Users/Konst/Projects/aviasembly/models/prop_engine_nose.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in meshes:
    print("OBJ", o.name, "dims", tuple(round(d, 3) for d in o.dimensions), "loc", tuple(round(c, 3) for c in o.location))

bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

prop = next((o for o in meshes if 'Prop' in o.name), None)
bodies = [o for o in meshes if o is not prop]
bpy.ops.object.select_all(action='DESELECT')
for b in bodies:
    b.select_set(True)
bpy.context.view_layer.objects.active = bodies[0]
if len(bodies) > 1:
    bpy.ops.object.join()
body = bpy.context.active_object

dims = body.dimensions
axis = max(range(3), key=lambda i: dims[i])
bm = bmesh.new(); bm.from_mesh(body.data)
vals = [v.co[axis] for v in bm.verts]
lo, hi = min(vals), max(vals)
prop_a = (prop.location[axis] if prop else hi)
front_hi = abs(prop_a - hi) < abs(prop_a - lo)
front = hi if front_hi else lo
back = lo if front_hi else hi
cut = front + (back - front) * 0.80   # 80 % ab Front behalten, hinteres Fünftel weg
print("AXIS", axis, "lo", round(lo, 3), "hi", round(hi, 3), "front_hi", front_hi, "cut", round(cut, 3))

pco = [0.0, 0.0, 0.0]; pco[axis] = cut
pno = [0.0, 0.0, 0.0]; pno[axis] = (1.0 if front_hi else -1.0)   # zeigt zur Front
geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
res = bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=pco, plane_no=pno,
                             clear_inner=True, clear_outer=False)
cut_edges = [g for g in res['geom_cut'] if isinstance(g, bmesh.types.BMEdge)]
print("cut_edges", len(cut_edges))
try:
    bmesh.ops.edgeloop_fill(bm, edges=cut_edges)
except Exception as ex:
    print("edgeloop_fill fail:", ex)
    try:
        bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)
    except Exception as ex2:
        print("holes_fill fail:", ex2)
bm.normal_update()
bm.to_mesh(body.data); bm.free()

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True)
print("EXPORTED", OUT)
