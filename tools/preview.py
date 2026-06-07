# Blender-Vorschau: rekonstruiert ein Aviassembly-Design (JSON) als Proxy-Formen
# in echten Godot-Koordinaten (Y oben, -Z vorne) und rendert es.
# Nutzung in Blender: exec(open('/Users/konstantinkanzler/Downloads/aviasembly/tools/preview.py').read())
#   build_preview('/Users/.../designs/fokker_dr1.json'); view('front')   dann render_viewport_to_path
import bpy, bmesh, math, mathutils, json
TAU = math.tau

def _clear():
    for o in list(bpy.data.objects):
        if o.type == 'MESH': bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes): bpy.data.meshes.remove(m)

def _mat(col):
    m = bpy.data.materials.new("m"); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1)
    b.inputs["Roughness"].default_value = 0.55
    return m

def _obj(bm, name, col, M):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(_mat(col))
    for p in o.data.polygons: p.use_smooth = True
    o.matrix_world = M
    return o

def _frustum(rxf, ryf, rxb, ryb, zf, zb, segs=18):
    bm = bmesh.new(); rf = []; rb = []
    for s in range(segs):
        a = TAU * s / segs
        rf.append(bm.verts.new((math.cos(a)*rxf, math.sin(a)*ryf, zf)))
        rb.append(bm.verts.new((math.cos(a)*rxb, math.sin(a)*ryb, zb)))
    for s in range(segs):
        s2 = (s+1) % segs; bm.faces.new((rf[s], rf[s2], rb[s2], rb[s]))
    cf = bm.verts.new((0, 0, zf)); cb = bm.verts.new((0, 0, zb))
    for s in range(segs):
        s2 = (s+1) % segs; bm.faces.new((cf, rf[s2], rf[s])); bm.faces.new((cb, rb[s], rb[s2]))
    return bm

def _wing(span, rc, tc, sweep, th=0.13):
    bm = bmesh.new()
    r = [bm.verts.new((0, -th/2, -rc/2)), bm.verts.new((0, th/2, -rc/2)), bm.verts.new((0, th/2, rc/2)), bm.verts.new((0, -th/2, rc/2))]
    t = [bm.verts.new((span, -th/2, sweep-tc/2)), bm.verts.new((span, th/2, sweep-tc/2)), bm.verts.new((span, th/2, sweep+tc/2)), bm.verts.new((span, -th/2, sweep+tc/2))]
    for q in [(r[0],r[1],r[2],r[3]), (t[3],t[2],t[1],t[0]), (r[0],r[3],t[3],t[0]), (r[1],r[0],t[0],t[1]), (r[2],r[1],t[1],t[2]), (r[3],r[2],t[2],t[3])]:
        bm.faces.new(q)
    return bm

def _cube(sx, sy, sz):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co = mathutils.Vector((v.co.x*sx, v.co.y*sy, v.co.z*sz))
    return bm

SPECS = {
 "cockpit": {"shape":"cock", "size":(1.3,1.1,2.2)}, "fuselage": {"shape":"box", "size":(1.3,1.1,2.0)},
 "fuselage_long": {"shape":"box", "size":(1.3,1.1,3.2)}, "fuselage_wide": {"shape":"box", "size":(1.85,1.0,2.6)},
 "fuselage_taper": {"shape":"box", "size":(1.45,1.05,2.8)}, "tailcone": {"shape":"nose", "size":(1.3,1.1,1.8)},
 "nose": {"shape":"noseF", "size":(1.3,1.1,1.8)}, "fueltank": {"shape":"cyl", "size":(1.2,1.2,2.0)},
 "prop_engine": {"shape":"prop", "size":(1.1,1.1,1.7)}, "prop_engine_big": {"shape":"prop", "size":(1.5,1.5,1.9)},
 "strut": {"shape":"box", "size":(0.2,1.5,0.5)}, "mg": {"shape":"gun", "size":(0.3,0.3,1.3)},
 "cannon": {"shape":"gun", "size":(0.42,0.42,1.6)},
 "wheel": {"shape":"wheel", "size":(0.6,1.2,0.9)}, "wheel_light": {"shape":"wheel", "size":(0.5,1.0,0.7)},
 "wheel_retract": {"shape":"wheel", "size":(0.62,1.25,0.9)},
 "wing_straight": {"shape":"wing", "span":4.4, "rc":1.7, "tc":1.7, "sweep":0.0},
 "wing_short": {"shape":"wing", "span":2.4, "rc":1.5, "tc":1.1, "sweep":0.2},
 "wing_tapered": {"shape":"wing", "span":4.6, "rc":1.9, "tc":1.0, "sweep":0.4},
 "h_stab": {"shape":"wing", "span":2.6, "rc":1.1, "tc":0.7, "sweep":0.25},
 "v_stab": {"shape":"wing", "span":1.8, "rc":1.3, "tc":0.7, "sweep":0.7},
}

def build_preview(path):
    _clear()
    data = json.load(open(path))
    for it in data:
        sp = SPECS.get(it["id"])
        if sp is None: continue
        a = it["xform"]; s = it.get("scale", [1,1,1]); c = it.get("color", [0.6,0.6,0.65,1])
        col = (c[0], c[1], c[2]) if c[3] > 0 else (0.6, 0.62, 0.66)
        M = mathutils.Matrix(((a[0],a[3],a[6],a[9]), (a[1],a[4],a[7],a[10]), (a[2],a[5],a[8],a[11]), (0,0,0,1))) @ mathutils.Matrix.Diagonal((s[0], s[1], s[2], 1.0))
        sh = sp["shape"]
        if sh == "wing":
            _obj(_wing(sp["span"], sp["rc"], sp["tc"], sp["sweep"]), it["id"], col, M)
        elif sh in ("box", "cock", "cyl"):
            sz = sp["size"]; tf = it.get("taper_front", 1.0); tb = it.get("taper", 1.0)
            tf = 1.0 if tf < 0 else tf; tb = 1.0 if tb < 0 else tb
            k = 0.85 if sh == "cock" else (0.9 if sh == "cyl" else 1.0)
            _obj(_frustum(sz[0]/2*tf, sz[1]/2*tf, sz[0]/2*tb*k, sz[1]/2*tb*k, -sz[2]/2, sz[2]/2), it["id"], col, M)
        elif sh == "nose":   # tailcone: Spitze hinten (+Z)
            sz = sp["size"]; _obj(_frustum(sz[0]/2, sz[1]/2, 0.02, 0.02, -sz[2]/2, sz[2]/2), it["id"], col, M)
        elif sh == "noseF":  # nose: Spitze vorne (-Z)
            sz = sp["size"]; _obj(_frustum(0.02, 0.02, sz[0]/2, sz[1]/2, -sz[2]/2, sz[2]/2), it["id"], col, M)
        elif sh == "prop":
            sz = sp["size"]
            _obj(_frustum(sz[0]/2, sz[1]/2, sz[0]/4, sz[1]/4, -sz[2]/2+0.3, sz[2]/2), "cowl", col, M)
            _obj(_frustum(0.02, 0.02, sz[0]*0.3, sz[1]*0.3, -sz[2]/2, -sz[2]/2+0.4), "spin", (0.62,0.64,0.68), M)
        elif sh == "gun":
            sz = sp["size"]; _obj(_frustum(sz[0]/2, sz[1]/2, sz[0]/2, sz[1]/2, -sz[2]/2, sz[2]/2, 8), it["id"], col, M)
        elif sh == "wheel":
            sz = sp["size"]; _obj(_cube(sz[0], sz[1]*0.82, sz[1]*0.82), it["id"], col, M)
    _setup_scene()

def _setup_scene():
    sc = bpy.context.scene
    for eng in ['BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'CYCLES']:
        try: sc.render.engine = eng; break
        except: pass
    if bpy.data.objects.get("Cam") is None:
        cd = bpy.data.cameras.new("Cam"); cam = bpy.data.objects.new("Cam", cd); sc.collection.objects.link(cam)
        sc.camera = cam
    sun = bpy.data.objects.get("Sun")
    if sun is None:
        ld = bpy.data.lights.new("Sun", 'SUN'); sun = bpy.data.objects.new("Sun", ld); sc.collection.objects.link(sun)
    sun.data.energy = 4.0; sun.rotation_euler = (math.radians(55), math.radians(20), math.radians(-40))
    w = sc.world or bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.52, 0.57, 0.64, 1)
    sc.render.resolution_x = 900; sc.render.resolution_y = 560

def view(name, aim=(0,0,0.4)):
    sc = bpy.context.scene; cam = bpy.data.objects.get("Cam")
    pos = {"front":(0,0.3,-13), "back":(0,0.3,13), "side":(14,0.6,0.4),
           "top":(0,15,0.4), "34":(8,4.5,-9), "34b":(-8,4,-9)}[name]
    cam.location = pos
    if name == "top":
        cam.rotation_euler = mathutils.Euler((math.radians(-90), 0, 0))
    else:
        cam.rotation_euler = (mathutils.Vector(aim) - mathutils.Vector(pos)).to_track_quat('-Z', 'Y').to_euler()
