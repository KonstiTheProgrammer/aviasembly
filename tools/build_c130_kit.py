# =============================================================================
# C-130-BAUKASTEN: erzeugt aus den beiden Blender-Quellen die Spiel-Teile.
#
#   blender_lib/c130_kit_flugzeug.blend   -> models/cockpit_c130.glb
#                                            models/fuselage_c130_long.glb
#                                            models/fuselage_c130_short.glb
#   blender_lib/c130_kit_triebwerk.blend  -> models/engine_c130.glb  (mit "Prop"-Knoten)
#
# Aufruf:
#   "C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" --background \
#       --python tools/build_c130_kit.py
#   danach ZWINGEND: Godot --headless --editor --import   (sonst liefert load() null)
#
# MASSSTAB: Der Quellrumpf hat 4.35 Blender-Einheiten Querschnitt (echte C-130-Masse).
# Das Cockpit soll laut Vorgabe etwas GROESSER sein als die uebrigen (Frachtflugzeug) —
# das groesste vorhandene ist cockpit_transport mit 2.20. Ziel also 2.55 => Faktor
# 2.55/4.35 = 0.5862. Das Cockpit wird UNIFORM skaliert (eine geformte Nase darf man
# nicht laengs ziehen).
#
# Die beiden Rumpfsegmente sind nachgemessen echte Roehren mit konstantem Querschnitt
# (alle Innenringe identisch, nur 0.04 Fase an den Enden) — sie duerfen laengs gestreckt
# werden, ohne die Form zu verzerren. In der Quelle sind sie mit 1.50 / 1.20 Einheiten
# sehr kurz (0.34 bzw. 0.28 Rumpfdurchmesser); man braeuchte ~15 Stueck fuer einen Rumpf.
# Darum EIN gemeinsamer Laengsfaktor, der das lange Segment auf 2.40 bringt (exakt die
# Laenge von fuselage_transport) — das Verhaeltnis lang:kurz aus der Quelle bleibt dabei
# erhalten (2.40 : 1.92).
# =============================================================================
import bpy
import os
import sys
from mathutils import Vector

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(HIER)
QUELLE_FLUGZEUG = os.path.join(WURZEL, "blender_lib", "c130_kit_flugzeug.blend")
QUELLE_TRIEBWERK = os.path.join(WURZEL, "blender_lib", "c130_kit_triebwerk.blend")
MODELLE = os.path.join(WURZEL, "models")

QUERSCHNITT_ZIEL = 2.55        # Godot-Einheiten, etwas ueber cockpit_transport (2.20)
QUERSCHNITT_QUELLE = 4.35      # Blender-Einheiten (nachgemessen)
S = QUERSCHNITT_ZIEL / QUERSCHNITT_QUELLE

SEGMENT_LANG_ZIEL = 2.40       # wie fuselage_transport
SEGMENT_LANG_QUELLE = 1.50
LAENGS = SEGMENT_LANG_ZIEL / SEGMENT_LANG_QUELLE

masse = {}                     # wird am Ende ausgegeben -> Zahlen fuer den PartCatalog


def nur_behalten(namen):
    behalten = set(namen)
    for o in list(bpy.data.objects):
        if o.name not in behalten:
            bpy.data.objects.remove(o, do_unlink=True)


def bbox(objs):
    """Direkt aus den VERTICES, nicht aus o.bound_box: bound_box wird erst beim
    naechsten Depsgraph-Durchlauf frisch. Wer direkt v.co schreibt und danach
    bound_box liest, misst die alten Werte — hier zuerst reingelaufen (die Teile
    kamen mit exakt der unskalierten Quellgroesse heraus)."""
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != 'MESH':
            continue
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def verts_verschieben(o, d):
    for v in o.data.vertices:
        v.co += d


def verts_skalieren(o, f):
    for v in o.data.vertices:
        v.co = Vector((v.co.x * f.x, v.co.y * f.y, v.co.z * f.z))


def transform_anwenden(o):
    """Alles in die Vertexdaten backen -> der glTF-Knoten kommt mit Identitaet an.
    Genau daran scheiterte der Reto-Motor, dessen Prop-Knoten eine falsche Rotation
    mitbrachte und in PartCatalog nachtraeglich gerade gebogen werden musste."""
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    # Die sechs Propellerblaetter sind Linked Duplicates (EIN Mesh-Datenblock fuer
    # alle) — transform_apply bricht darauf mit "Cannot apply to a multi user" ab.
    # Erst vereinzeln, sonst wuerde ohnehin jede Drehung alle Blaetter mitziehen.
    if o.data is not None and o.data.users > 1:
        bpy.ops.object.make_single_user(object=True, obdata=True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def material_umbenennen(o, alt, neu):
    """Lackierbar machen: das Spiel faerbt nur die Slots body/cockpit_body/engine/tankmetal."""
    for m in o.data.materials:
        if m is not None and m.name == alt:
            m.name = neu
            return True
    return False


def exportieren(objs, datei):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    pfad = os.path.join(MODELLE, datei)
    bpy.ops.export_scene.gltf(
        filepath=pfad,
        export_format='GLB',
        use_selection=True,
        export_apply=True,
        export_yup=True,           # Blender Z -> Godot Y, Blender +Y -> Godot -Z (vorne)
    )
    return pfad


def godot_masse(lo, hi):
    """Blender-AABB -> Godot-Masse (x = Blender x, y = Blender z, z = Blender y)."""
    d = hi - lo
    m = (hi + lo) * 0.5
    return {
        "size": (d.x, d.z, d.y),
        # Blender +Y ist Godot -Z: die Mitte kippt auf der Laengsachse das Vorzeichen
        "offset": (m.x, m.z, -m.y),
    }


# =============================================================================
# TEIL A — Cockpit und die beiden Rumpfsegmente aus dem Flugzeug
# =============================================================================
def bau_zelle(objekt, datei, y_faktor, hauptmaterial):
    bpy.ops.wm.open_mainfile(filepath=QUELLE_FLUGZEUG)
    if objekt not in bpy.data.objects:
        raise SystemExit("Objekt fehlt in der Quelle: " + objekt)
    nur_behalten([objekt])
    o = bpy.data.objects[objekt]
    transform_anwenden(o)

    # 1) auf den Ursprung zentrieren — die Box-Mitte ist der Teil-Ursprung (Projektregel).
    lo, hi = bbox([o])
    verts_verschieben(o, -(lo + hi) * 0.5)

    # 2) Querschnitt einheitlich, Laenge je nach Teil
    # y_faktor ist ABSOLUT (nicht x S): das Cockpit wird uniform skaliert, die
    # Segmente behalten den Querschnitt und werden auf Spiel-Laenge gestreckt.
    verts_skalieren(o, Vector((S, y_faktor, S)))

    material_umbenennen(o, "M_Body", hauptmaterial)
    o.name = objekt.replace("Fuselage_", "C130_Rumpf_").replace("Cockpit", "C130_Cockpit")
    o.data.name = o.name

    lo2, hi2 = bbox([o])
    masse[datei] = godot_masse(lo2, hi2)
    exportieren([o], datei)
    print("  %-30s Godot-Groesse %.3f x %.3f x %.3f"
          % (datei, hi2.x - lo2.x, hi2.z - lo2.z, hi2.y - lo2.y))


# =============================================================================
# TEIL B — Triebwerk mit drehendem "Prop"-Knoten
# =============================================================================
GONDEL = ["Cowl", "Exhaust", "Intake_Chin", "Cowl_Details"]
DREHT = ["Spinner", "Blade_1", "Blade_2", "Blade_3", "Blade_4", "Blade_5", "Blade_6"]


def verbinden(namen, ziel):
    teile = [bpy.data.objects[n] for n in namen if n in bpy.data.objects]
    if not teile:
        return None
    for t in teile:
        # Erst vom Eltern-Empty loesen (Weltlage behalten), dann backen — sonst
        # wandern die Blaetter beim Verbinden auf den Hub zusammen.
        if t.parent is not None:
            bpy.ops.object.select_all(action='DESELECT')
            t.select_set(True)
            bpy.context.view_layer.objects.active = t
            bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
        transform_anwenden(t)
    bpy.ops.object.select_all(action='DESELECT')
    for t in teile:
        t.select_set(True)
    bpy.context.view_layer.objects.active = teile[0]
    if len(teile) > 1:
        bpy.ops.object.join()
    verbund = bpy.context.view_layer.objects.active
    verbund.name = ziel
    verbund.data.name = ziel
    return verbund


def bau_triebwerk():
    bpy.ops.wm.open_mainfile(filepath=QUELLE_TRIEBWERK)
    nur_behalten(GONDEL + DREHT + ["BladeRoot_%d" % i for i in range(1, 7)]
                 + ["Prop_Root", "Prop_Control"])
    gondel = verbinden(GONDEL, "C130_Gondel")
    prop = verbinden(DREHT, "Prop")
    # die Empties werden nicht mehr gebraucht
    for o in list(bpy.data.objects):
        if o.type == 'EMPTY':
            bpy.data.objects.remove(o, do_unlink=True)
    if gondel is None or prop is None:
        raise SystemExit("Gondel oder Propeller fehlt in der Quelle")

    # 1) Gesamtes Triebwerk auf den Ursprung zentrieren
    lo, hi = bbox([gondel, prop])
    mitte = (lo + hi) * 0.5
    for o in (gondel, prop):
        verts_verschieben(o, -mitte)

    # 2) Massstab
    for o in (gondel, prop):
        verts_skalieren(o, Vector((S, S, S)))

    # 3) Der "Prop"-Knoten muss seinen URSPRUNG auf der Drehachse haben: das Spiel ruft
    #    rotate_z darauf (Godot-Z = Blender-Y = Propellerachse). Liegt der Ursprung
    #    daneben, eiert der Propeller statt zu drehen. Die Achse ist x=0/z=0; die
    #    Laengslage nehmen wir aus der Mitte des Propellers selbst.
    plo, phi = bbox([prop])
    hub = Vector((0.0, (plo.y + phi.y) * 0.5, 0.0))
    verts_verschieben(prop, -hub)
    prop.location = hub
    # matrix_world folgt erst nach einem Depsgraph-Durchlauf — ohne das misst die
    # naechste bbox den Propeller noch am alten Ort (die Gesamtbox kam dadurch
    # exakt so gross heraus wie die Gondel allein).
    bpy.context.view_layer.update()

    material_umbenennen(gondel, "N_Cowl", "engine")
    material_umbenennen(prop, "P_Spinner", "spinner")

    glo, ghi = bbox([gondel])
    lo2, hi2 = bbox([gondel, prop])
    masse["engine_c130.glb"] = godot_masse(lo2, hi2)
    masse["engine_c130_gondel"] = godot_masse(glo, ghi)
    exportieren([gondel, prop], "engine_c130.glb")
    print("  %-30s Godot-Groesse %.3f x %.3f x %.3f  (Gondel allein %.3f x %.3f x %.3f)"
          % ("engine_c130.glb", hi2.x - lo2.x, hi2.z - lo2.z, hi2.y - lo2.y,
             ghi.x - glo.x, ghi.z - glo.z, ghi.y - glo.y))
    print("     Prop-Ursprung (Blender) %.3f %.3f %.3f" % (hub.x, hub.y, hub.z))


# =============================================================================
print("=" * 74)
print("C-130-BAUKASTEN   Querschnitt-Faktor %.4f   Laengs-Faktor %.4f" % (S, LAENGS))
print("=" * 74)
bau_zelle("Cockpit", "cockpit_c130.glb", S, "cockpit_body")
# Die BEIDEN RUMPFRINGE werden bewusst NICHT mehr als glb exportiert. Ein glb-Teil
# steigt in PartCatalog._attach_model aus, bevor ueberhaupt ein Mesh gebaut wird —
# Enden-Skalierung, Enden-Versatz und Auto-Taper haetten Griffe ohne jede Wirkung
# gezeigt. Stattdessen loftet PartCatalog sie prozedural aus C130_PROFILE (Shape
# "c130_tube"); das Profil kommt aus tools/extract_c130_profile.py, gezogen aus
# genau diesen beiden Objekten. Wer die Ringe hier wieder exportiert, macht die
# Enden-Werkzeuge erneut wirkungslos.
bau_triebwerk()

print("")
print("=" * 74)
print("ZAHLEN FUER DEN PARTCATALOG (Godot-Achsen)")
print("=" * 74)
for k in sorted(masse.keys()):
    m = masse[k]
    print("  %-26s size=Vector3(%.3f, %.3f, %.3f)  offset=Vector3(%.3f, %.3f, %.3f)"
          % (k, m["size"][0], m["size"][1], m["size"][2],
             m["offset"][0], m["offset"][1], m["offset"][2]))
print("")
print("NICHT VERGESSEN: Godot --headless --editor --import")
