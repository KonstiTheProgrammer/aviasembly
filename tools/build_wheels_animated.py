# tools/wheels_animated.blend -> models/wheel_biplane_spoke|wheel_biplane_disc|wheel_spitfire.glb
#   /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/build_wheels_animated.py
#
# Die drei animierten Fahrwerks-Raeder (Szene "Wheels", via Blender-MCP designt):
#   Root_*  = Aufhaengepunkt (im Blend zur Uebersicht bei x=-2/0/+2 GEPARKT -> hier nullen!)
#   Pivot_* = animiert (Action retract_*, 30f @30fps, Overshoot-Einrasten)
#   *Gear / *Wheel = Meshes (flat; NUR gear_rubber-Polys smooth)
#
# WARUM NEU GESCHRIEBEN: die frueheren Pfade zeigten auf ein Windows-Laufwerk, das
# Skript lief auf diesem Rechner nie. Die drei glbs im Repo stammten darum aus einem
# aelteren Export OHNE Animation und OHNE Pivot — AircraftBody fand keine "retract"-
# Animation und fiel still auf das prozedurale Klappen zurueck.
#
# Zwei Fallen, die beim Neuaufsetzen aufgefallen sind:
#  1) RADACHSE: die *Wheel-Objekte tragen eine Objektdrehung von 90 Grad um Y. In der
#     WELT stimmt die Achse damit, die LOKALE X-Achse zeigt aber nach unten — und genau
#     die liest AircraftBody aus (`wn.global_transform.basis.x`), um das Rad beim Rollen
#     zu drehen. Darum wird die Drehung vor dem Export ins Mesh gebacken.
#  2) BEINLAENGE: PartCatalog.set_gear_length braucht "Leg" + "LegMesh". Ein blosser
#     Export der Blend-Hierarchie haette den Regler fuer diese drei kaputtgemacht.
#     Darum hier dieselbe Struktur wie bei wheel_f22/_nose/_tail:
#       Root -> Pivot(anim) -> Leg(Node3D) -> LegMesh
#                                          -> Extend(Editor-Beinlaenge) -> Wheel
#     Kein "Slider": diese drei haben kein Oleo zum Teleskopieren (Gummiseil-Federung
#     beim Doppeldecker), die Beine bleiben in sich starr.
import bpy

SRC = "/Users/konstantinkanzler/Projects/aviasembly/tools/wheels_animated.blend"
OUT = "/Users/konstantinkanzler/Projects/aviasembly/models/"

bpy.ops.wm.open_mainfile(filepath=SRC)
sc = bpy.data.scenes["Wheels"]
bpy.context.window.scene = sc
sc.frame_set(1)                      # Ruhepose = ausgefahren

SETS = [
    ("Root_spoke", "Pivot_spoke", "retract_spoke", "SpokeGear", "SpokeWheel", "wheel_biplane_spoke.glb"),
    ("Root_disc",  "Pivot_disc",  "retract_disc",  "DiscGear",  "DiscWheel",  "wheel_biplane_disc.glb"),
    ("Root_spit",  "Pivot_spit",  "retract_spit",  "SpitGear",  "SpitWheel",  "wheel_spitfire.glb"),
]


def tree(o):
    yield o
    for c in o.children:
        yield from tree(c)


def backen(o):
    """Objektdrehung/-skalierung ins Mesh backen, Ursprung bleibt liegen."""
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def setze_ursprung(o, welt):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    sc.cursor.location = welt
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    sc.cursor.location = (0, 0, 0)


def leer(name, parent):
    e = bpy.data.objects.new(name, None)
    sc.collection.objects.link(e)
    e.empty_display_size = 0.08
    e.parent = parent
    e.matrix_parent_inverse = parent.matrix_world.inverted()
    e.location = (0, 0, 0)
    return e


def anhaengen(child, parent):
    """Umhaengen OHNE das Kind zu versetzen."""
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()


for root_n, piv_n, act_n, gear_n, wheel_n, fname in SETS:
    root = bpy.data.objects[root_n]
    piv = bpy.data.objects[piv_n]
    gear = bpy.data.objects[gear_n]
    rad = bpy.data.objects[wheel_n]

    root.location = (0, 0, 0)        # Ursprung = Aufhaengepunkt, kein Layout-Versatz
    bpy.context.view_layer.update()

    act = bpy.data.actions.get(act_n)
    if act is None:
        raise RuntimeError(f"Action {act_n} fehlt")
    act.name = "retract"

    # (1) Radachse ins Mesh backen -> lokale X wird zur echten Radachse
    backen(rad)
    backen(gear)

    # (2) Beinnetz: Ursprung auf den Aufhaengepunkt, damit _leg_stretched das Rohr an
    #     der richtigen Stelle dehnt — die Funktion rechnet ab y=0 nach unten.
    merk_gear, merk_rad = gear.name, rad.name
    setze_ursprung(gear, (0, 0, 0))

    # (3) Struktur der neuen Fahrwerke aufbauen
    bein = leer("Leg", piv)
    ausz = leer("Extend", bein)
    gear.name = "LegMesh"
    rad.name = "Wheel"
    anhaengen(gear, bein)
    anhaengen(rad, ausz)
    bpy.context.view_layer.update()

    sc.frame_set(1)
    bpy.ops.object.select_all(action='DESELECT')
    for o in tree(root):
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=OUT + fname, export_format='GLB', use_selection=True,
                              export_animations=True, export_animation_mode='ACTIONS',
                              export_frame_range=True, export_bake_animation=True,
                              export_yup=True, export_apply=False)
    print("EXPORTED", fname)

    # Zurueckbauen, damit der naechste Durchlauf eine saubere Struktur vorfindet
    act.name = act_n
    anhaengen(gear, piv)
    anhaengen(rad, piv)
    gear.name, rad.name = merk_gear, merk_rad
    bpy.data.objects.remove(ausz, do_unlink=True)
    bpy.data.objects.remove(bein, do_unlink=True)

print("FERTIG")
