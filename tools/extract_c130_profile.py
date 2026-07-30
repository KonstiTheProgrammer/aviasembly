# Zieht den QUERSCHNITT des C-130-Rumpfs aus blender_lib/c130_kit_flugzeug.blend und
# gibt ihn als GDScript-Konstante aus (wie RETO_PROFILE / RADIAL_PROFILE).
#
# Warum ueberhaupt: Solange die Rumpfringe aus einem .glb kamen, stieg build_visual in
# _attach_model aus, bevor irgendein prozeduraler Mesh gebaut wird — Enden-Skalierung,
# Enden-Versatz und Auto-Taper konnten also gar nicht wirken. Mit dem echten Profil
# baut _profile_tube dieselbe Roehre selbst, und alle Enden-Werkzeuge greifen.
#
# Aufruf:
#   blender --background --python tools/extract_c130_profile.py
import bpy
import os
import math
from mathutils import Vector

HIER = os.path.dirname(os.path.abspath(__file__))
WURZEL = os.path.dirname(HIER)
QUELLE = os.path.join(WURZEL, "blender_lib", "c130_kit_flugzeug.blend")

bpy.ops.wm.open_mainfile(filepath=QUELLE)
o = bpy.data.objects["Fuselage_long"]
mw = o.matrix_world

# --- den mittleren Ring nehmen (die aeusseren beiden Ebenen tragen die 0.04er Fase) ---
ebenen = {}
for v in o.data.vertices:
    w = mw @ v.co
    ebenen.setdefault(round(w.y, 3), []).append(w)
ys = sorted(ebenen.keys())
ymitte = ys[len(ys) // 2]
ring = ebenen[ymitte]
print("Ring bei Y=%.3f mit %d Punkten" % (ymitte, len(ring)))

# --- normieren: Mitte auf 0, groesste Ausdehnung auf [-0.5, 0.5] ---
xs = [p.x for p in ring]
zs = [p.z for p in ring]
cx = (min(xs) + max(xs)) * 0.5
cz = (min(zs) + max(zs)) * 0.5
breite = max(xs) - min(xs)
hoehe = max(zs) - min(zs)
print("Querschnitt roh: Breite %.4f  Hoehe %.4f  Mitte x=%.4f z=%.4f" % (breite, hoehe, cx, cz))

# x und y jeweils EIGENSTAENDIG auf [-0.5, 0.5] — die echten Masse stecken in der
# size des Teils, genau wie bei RETO_PROFILE.
pts = [((p.x - cx) / breite, (p.z - cz) / hoehe) for p in ring]

# --- gegen den Uhrzeigersinn sortieren ---
pts.sort(key=lambda p: math.atan2(p[1], p[0]))

# doppelte Punkte raus (die Naht des Rings liegt oft doppelt vor)
sauber = []
for p in pts:
    if not sauber or (abs(p[0] - sauber[-1][0]) > 1e-5 or abs(p[1] - sauber[-1][1]) > 1e-5):
        sauber.append(p)
if len(sauber) > 1 and abs(sauber[0][0] - sauber[-1][0]) < 1e-5 \
        and abs(sauber[0][1] - sauber[-1][1]) < 1e-5:
    sauber.pop()
print("nach Entdoppeln: %d Punkte" % len(sauber))


def abstand_zur_sehne(a, b, c):
    """Wie weit liegt b neben der Geraden a..c?"""
    ax, ay = a
    bx, by = b
    cx2, cy2 = c
    dx, dy = cx2 - ax, cy2 - ay
    laenge = math.hypot(dx, dy)
    if laenge < 1e-9:
        return math.hypot(bx - ax, by - ay)
    return abs(dy * (bx - ax) - dx * (by - ay)) / laenge


# --- ausduennen: Punkte auf glatten Boegen weglassen, Knicke behalten -------------
# Nicht gleichmaessig neu abtasten! Der C-130-Querschnitt hat einen abgeflachten
# Frachtboden; gleichmaessiges Resampling wuerde die Kanten dorthin verrunden.
def ausduennen(punkte, toleranz):
    behalten = [True] * len(punkte)
    n = len(punkte)
    geaendert = True
    while geaendert:
        geaendert = False
        for i in range(n):
            if not behalten[i]:
                continue
            vorher = (i - 1) % n
            while not behalten[vorher]:
                vorher = (vorher - 1) % n
            nachher = (i + 1) % n
            while not behalten[nachher]:
                nachher = (nachher + 1) % n
            if vorher == i or nachher == i:
                continue
            if sum(behalten) <= 12:
                break
            if abstand_zur_sehne(punkte[vorher], punkte[i], punkte[nachher]) < toleranz:
                behalten[i] = False
                geaendert = True
    return [p for p, k in zip(punkte, behalten) if k]


ziel = 32
tol = 0.0005
ergebnis = sauber
while len(ergebnis) > ziel and tol < 0.05:
    ergebnis = ausduennen(sauber, tol)
    tol *= 1.35
print("ausgeduennt auf %d Punkte (Toleranz %.5f)" % (len(ergebnis), tol / 1.35))

# --- als GDScript ausgeben --------------------------------------------------------
print("")
print("# ---- hier einfuegen ----")
print("const C130_PROFILE: Array = [")
zeile = "\t"
for i, (x, y) in enumerate(ergebnis):
    stueck = "Vector2(%.4f, %.4f), " % (x, y)
    if len(zeile) + len(stueck) > 92:
        print(zeile.rstrip())
        zeile = "\t"
    zeile += stueck
if zeile.strip():
    print(zeile.rstrip().rstrip(","))
print("]")
print("")
print("ECHTE MASSE (fuer die size des Teils): Breite %.4f  Hoehe %.4f" % (breite, hoehe))
