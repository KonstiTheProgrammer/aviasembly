"""LAUB-ATLAS fuer die Baumkronen — gemalte Laubkarten mit Alpha, selbst erzeugt
(Nutzerwunsch 2026-10-01: "billig, rueste es auf", Baeume mit aufruesten, Quelle selbst).
ZWEITE FASSUNG (selber Tag): einzelne Blaetter mit Mittelrippe und Nadeln waren zu
realistisch — gewuenscht ist "zelda-maessig" (BotW): PUFFIGE, GEMALTE Laubwolken mit
gewelltem Rand und weichem Licht von oben links, Nadelzweige als weiche, ueberlappende
Lappen.

    python3 tools/build_laubtextur.py [--vorschau <png>]

Schreibt tools/bodentexturen/laub_atlas.png (1024 x 1024, vier Felder 512 x 512):
    Feld 0 (links oben)   LAUB       Laubzweig: ~50 Blaetter um einen Zweig (Eiche, Busch,
                                     Urwald, Akazie, Mangrove)
    Feld 1 (rechts oben)  FEINLAUB   Birke: kleine Blaetter an haengenden Zweiglein
    Feld 2 (links unten)  NADELZWEIG Fichte/Tanne: flacher Zweig von links (Ansatz) nach
                                     rechts (Spitze), Nadeln beidseitig, Seitenzweiglein
    Feld 3 (rechts unten) KIEFER     Kiefer: Nadelbueschel
RGB = Farbfaktor (Mittel 1 ueber die deckenden Pixel, also /2 gespeichert wie die Boden-
texturen), A = Deckung. Die GRUNDFARBE kommt weiter aus der Vertexfarbe des Modells
(tools/build_baeume.py) — so bleiben Artfarben, Instanztoenung, Fernstufe und die
Laub-Erkennung (Gruen > Rot) unveraendert.
tools/_laubtextur.gd packt es nach shaders/flora_laub.res.
"""

import os
import sys

import numpy as np
from PIL import Image

N = 512
ORDNER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bodentexturen")


class Feld:
    def __init__(self, seed):
        self.a = np.zeros((N, N))
        self.c = np.ones((N, N, 3))
        self.rng = np.random.default_rng(seed)

    def _patch(self, x0, x1, y0, y1):
        x0 = max(int(np.floor(x0)), 0)
        y0 = max(int(np.floor(y0)), 0)
        x1 = min(int(np.ceil(x1)) + 1, N)
        y1 = min(int(np.ceil(y1)) + 1, N)
        if x1 <= x0 or y1 <= y0:
            return None
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float64) + 0.5
        return x0, x1, y0, y1, xx, yy

    def strich(self, p0, p1, b0, b1, farbe):
        """Zweig/Nadel: Strecke p0->p1, Breite b0 -> b1, weich gerandet."""
        (ax, ay), (bx, by) = p0, p1
        r = max(b0, b1) + 2
        pt = self._patch(min(ax, bx) - r, max(ax, bx) + r, min(ay, by) - r, max(ay, by) + r)
        if pt is None:
            return
        x0, x1, y0, y1, xx, yy = pt
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy + 1e-9
        t = np.clip(((xx - ax) * dx + (yy - ay) * dy) / L2, 0, 1)
        px, py = ax + t * dx, ay + t * dy
        d = np.sqrt((xx - px) ** 2 + (yy - py) ** 2)
        b = b0 + (b1 - b0) * t
        m = np.clip(b - d + 0.5, 0, 1)
        self._setzen(x0, x1, y0, y1, m, farbe)

    def blatt(self, mitte, winkel, laenge, breite, farbe, rippe=0.55, spitz=0.8, licht=0.15):
        """Blatt mit Stiel am Ansatz (mitte = Ansatz), Spitze in Richtung winkel."""
        cx, cy = mitte
        r = laenge + 3
        pt = self._patch(cx - r, cx + r, cy - r, cy + r)
        if pt is None:
            return
        x0, x1, y0, y1, xx, yy = pt
        ca, sa = np.cos(winkel), np.sin(winkel)
        u = (xx - cx) * ca + (yy - cy) * sa          # laengs
        v = -(xx - cx) * sa + (yy - cy) * ca         # quer
        t = u / laenge
        prof = np.clip(np.sin(np.pi * np.clip(t, 0, 1)), 0, 1) ** spitz
        # leicht asymmetrisch, breiteste Stelle etwas vor der Mitte
        prof *= 1.0 - 0.25 * np.clip(t - 0.5, 0, 1)
        w = breite * prof
        m = np.clip((w - np.abs(v)) * 1.2 + 0.5, 0, 1) * ((t > 0.0) & (t < 1.0))
        # Farbe: Mittelrippe dunkler, eine Haelfte heller (Lichtfalte), zum Rand dunkler
        f = np.ones(xx.shape + (3,)) * np.array(farbe)[None, None, :]
        rip = np.exp(-(v / 0.9) ** 2) * (t < 0.95)
        f *= (1.0 - 0.25 * rip * rippe)[..., None]
        f *= (1.0 + licht * np.sign(v) * np.clip(np.abs(v) / (w + 1e-6), 0, 1))[..., None]
        f *= (0.88 + 0.12 * np.clip(1.0 - np.abs(v) / (w + 1e-6), 0, 1))[..., None]
        self._setzen(x0, x1, y0, y1, m, f)

    def puff(self, mitte, radius, farbe, wellen=9, welle=0.07, licht=(-0.55, -0.83),
             kontrast=0.30, spitz=0.0):
        """Gemalte Laubwolke: Kreis mit gewelltem Rand (wellen Lappen), Licht von oben links
        (hell oben, dunkel unten, Rand etwas dunkler). spitz > 0: gezackter Rand (Kiefer)."""
        cx, cy = mitte
        r = radius * (1.0 + welle + spitz) + 3
        pt = self._patch(cx - r, cx + r, cy - r, cy + r)
        if pt is None:
            return
        x0, x1, y0, y1, xx, yy = pt
        dx, dy = xx - cx, yy - cy
        d = np.sqrt(dx * dx + dy * dy) + 1e-6
        a = np.arctan2(dy, dx)
        ph = self.rng.random() * 6.28
        rand = radius * (1.0 + welle * np.sin(wellen * a + ph)
                         + welle * 0.2 * np.sin(wellen * 2.1 * a + ph * 1.7)
                         + spitz * np.abs(np.sin(wellen * 2.5 * a + ph)) ** 0.5 - spitz * 0.5)
        m = np.clip((rand - d) * 0.8 + 0.5, 0, 1)
        lx, ly = licht
        hell = np.clip((dx * lx + dy * ly) / radius, -1, 1)          # +1 zur Lichtseite
        rnd = np.clip(1.0 - d / rand, 0, 1)
        f = np.ones(xx.shape + (3,)) * np.asarray(farbe)[None, None, :]
        f *= (1.0 + kontrast * hell)[..., None]
        f *= (0.86 + 0.14 * rnd ** 0.5)[..., None]
        self._setzen(x0, x1, y0, y1, m, f)

    def lappen(self, ansatz, winkel, laenge, breite, farbe, haengen=0.25, kontrast=0.28):
        """Weicher, spitz zulaufender Lappen (Nadelzweig-Masse), leicht haengend gebogen,
        oben hell, unten dunkel."""
        cx, cy = ansatz
        r = laenge + breite + 3
        pt = self._patch(cx - r, cx + r, cy - r, cy + r)
        if pt is None:
            return
        x0, x1, y0, y1, xx, yy = pt
        ca, sa = np.cos(winkel), np.sin(winkel)
        u = (xx - cx) * ca + (yy - cy) * sa
        v = -(xx - cx) * sa + (yy - cy) * ca
        t = u / laenge
        v = v - haengen * laenge * np.clip(t, 0, 1) ** 2      # Biegung nach unten (Bild-v)
        prof = np.clip(np.sin(np.pi * np.clip(t, 0, 1) ** 0.8), 0, 1) ** 0.7
        w = breite * prof
        m = np.clip((w - np.abs(v)) * 0.9 + 0.5, 0, 1) * ((t > 0) & (t < 1))
        f = np.ones(xx.shape + (3,)) * np.asarray(farbe)[None, None, :]
        f *= (1.0 - kontrast * np.clip(v / (w + 1e-6), -1, 1))[..., None]
        f *= (0.9 + 0.1 * np.clip(1 - t, 0, 1))[..., None]
        self._setzen(x0, x1, y0, y1, m, f)

    def tupfer(self, mitte, radius, farbe):
        """Kleiner weicher Farbtupfer NUR auf schon gedeckten Pixeln (Pinselstruktur)."""
        cx, cy = mitte
        r = radius + 3
        pt = self._patch(cx - r, cx + r, cy - r, cy + r)
        if pt is None:
            return
        x0, x1, y0, y1, xx, yy = pt
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        m = np.clip((radius - d) / (radius * 0.5), 0, 1) * (self.a[y0:y1, x0:x1] > 0.5)
        sub_c = self.c[y0:y1, x0:x1]
        sub_c[...] = sub_c * (1.0 - m[..., None]) + sub_c * np.asarray(farbe)[None, None, :] * m[..., None]

    def _setzen(self, x0, x1, y0, y1, m, farbe):
        sub_a = self.a[y0:y1, x0:x1]
        sub_c = self.c[y0:y1, x0:x1]
        farbe = np.asarray(farbe, dtype=np.float64)
        if farbe.ndim == 1:
            farbe = np.broadcast_to(farbe, m.shape + (3,))
        # deckend ueber das Bisherige malen (spaeter gemalt = vorne)
        sub_c[...] = sub_c * (1.0 - m[..., None]) + farbe * m[..., None]
        sub_a[...] = np.maximum(sub_a, m)

    def fertig(self):
        # Farbfaktor auf Mittel 1 ueber die deckenden Pixel
        deck = self.a > 0.5
        mittel = self.c[deck].mean(0)
        c = self.c / mittel[None, None, :]
        # Unter transparenten Pixeln die Farbe der Nachbarn ausdehnen (sonst ziehen die
        # Mipmaps Schwarz/Weiss in den Rand)
        from scipy import ndimage
        idx = ndimage.distance_transform_edt(~deck, return_distances=False, return_indices=True)
        c = c[idx[0], idx[1]]
        return c, self.a


def _pinsel(f, rng, n, oben_hell=1.10, unten_dunkel=0.90):
    """Pinselstruktur: kleine helle Tupfer eher oben, dunkle eher unten."""
    for k in range(n):
        x, y = rng.random() * 512, rng.random() * 512
        r = 6 + rng.random() * 9
        oben = 1.0 - y / 512.0
        if rng.random() < 0.35 + 0.4 * oben:
            f.tupfer((x, y), r, (oben_hell, oben_hell, oben_hell * 0.95))
        else:
            f.tupfer((x, y), r, (unten_dunkel, unten_dunkel, unten_dunkel * 1.02))


def laub(seed=1):
    """Laubwolke (Eiche, Busch, Urwald ...): 10-14 puffige, gemalte Ballen mit gewelltem Rand,
    grosse hinten, kleinere vorn; Licht von oben links; darauf Pinseltupfer."""
    f = Feld(seed)
    rng = f.rng
    ballen = []
    for k in range(13):
        a = rng.random() * 2 * np.pi
        rr = np.sqrt(rng.random()) * 150
        ballen.append(((256 + np.cos(a) * rr, 262 + np.sin(a) * rr * 0.85), 62 + rng.random() * 48))
    ballen.sort(key=lambda b: -b[1])
    for (m, r) in ballen:
        ton = 0.90 + rng.random() * 0.22
        f.puff(m, r, (ton, ton, ton * 0.96), wellen=5 + int(rng.random() * 3), welle=0.06)
    _pinsel(f, rng, 420)
    return f.fertig()


def feinlaub(seed=2):
    """Birke: kleine Laubwoelkchen an haengenden, gebogenen Straengen (lockerer, heller)."""
    f = Feld(seed)
    rng = f.rng
    holz = (0.40, 0.36, 0.34)
    for k in range(11):
        x = 30 + rng.random() * 452
        y = 20 + rng.random() * 120
        pts = [(x, y)]
        drift = rng.normal(0, 5)
        for s_ in range(4 + int(rng.random() * 5)):
            px, py = pts[-1]
            pts.append((px + drift + rng.normal(0, 5), py + 40 + rng.random() * 14))
        for a, b in zip(pts[:-1], pts[1:]):
            f.strich(a, b, 1.5, 1.1, holz)
        for (px, py) in pts[1:]:
            if py > 490:
                continue
            ton = 0.92 + rng.random() * 0.22
            f.puff((px + rng.normal(0, 6), py), 20 + rng.random() * 14,
                   (ton, ton, ton * 0.94), wellen=5, welle=0.08)
    _pinsel(f, rng, 260)
    return f.fertig()


def nadelzweig(seed=3):
    """Fichte: weicher Nadelzweig wie gemalt — Ansatz links, Spitze rechts, symmetrisch um
    den Zweig: ueberlappende spitze Lappen schraeg nach vorn, ein Mittellappen, am Umriss
    kleine Fransen (keine einzelnen Nadeln)."""
    f = Feld(seed)
    rng = f.rng
    holz = (0.42, 0.36, 0.30)
    y0 = 256

    def breite(x):
        return (1.0 - x / 512.0) * 120 + 26

    f.strich((6, y0), (500, y0), 4.0, 1.5, holz)
    n = 13
    for k in range(n):
        x = 14 + k / (n - 1) * 440
        L = breite(x) * 1.25 + 30
        for seite in (-1, 1):
            w = seite * (0.62 + rng.normal(0, 0.06))
            ton = 0.90 + rng.random() * 0.16 + (0.08 if seite < 0 else -0.06)
            f.lappen((x, y0), w, L, breite(x) * 0.28 + 8, (ton, ton, ton * 0.96), haengen=0.06)
    f.lappen((8, y0), 0.0, 500, 26, (1.06, 1.06, 1.0), haengen=0.0)
    # Fransen am Umriss, nach aussen-vorn
    for k in range(90):
        x = 20 + rng.random() * 460
        seite = -1 if rng.random() < 0.5 else 1
        # innerhalb des Umrisses der grossen Lappen anfangen (sonst schweben Fransen frei)
        y = y0 + seite * breite(x) * 0.62 * (0.8 + 0.2 * rng.random())
        f.lappen((x - 10, y - seite * 8), seite * (0.75 + rng.normal(0, 0.15)),
                 18 + rng.random() * 16, 5.5, (0.98, 0.98, 0.95), haengen=0.0)
    _pinsel(f, rng, 300, oben_hell=1.12, unten_dunkel=0.88)
    return f.fertig()


def kiefer(seed=4):
    """Kiefer: puffige, gezackte Nadelbueschel (Sterne mit weichem Kern) an kurzen Zweigen."""
    f = Feld(seed)
    rng = f.rng
    holz = (0.45, 0.33, 0.25)
    mitten = [(256, 256)]
    for k in range(8):
        a = rng.random() * 2 * np.pi
        r = 70 + rng.random() * 120
        mitten.append((256 + np.cos(a) * r, 256 + np.sin(a) * r * 0.85))
    # Keine Zweigstriche: sie lagen als dunkle Linien quer ueber den Bueschelkarten (die
    # echten Aeste stehen ohnehin im Modell).
    mitten.sort(key=lambda m: m[1])
    for (cx, cy) in mitten:
        ton = 0.90 + rng.random() * 0.2
        f.puff((cx, cy), 58 + rng.random() * 26, (ton, ton, ton * 0.96), wellen=13,
               welle=0.03, spitz=0.09)
    _pinsel(f, rng, 260)
    return f.fertig()


def main():
    felder = [laub(), feinlaub(), nadelzweig(), kiefer()]
    atlas = np.zeros((2 * N, 2 * N, 4))
    for k, (c, a) in enumerate(felder):
        x, y = (k % 2) * N, (k // 2) * N
        atlas[y:y + N, x:x + N, :3] = np.clip(c * 0.5, 0, 1)
        atlas[y:y + N, x:x + N, 3] = a
        print("Feld %d Deckung %.0f %%, Faktor %.2f..%.2f" % (
            k, (a > 0.5).mean() * 100, c[a > 0.5].min(), c[a > 0.5].max()))
    os.makedirs(ORDNER, exist_ok=True)
    Image.fromarray((atlas * 255 + 0.5).astype(np.uint8)).save(
        os.path.join(ORDNER, "laub_atlas.png"))
    if "--vorschau" in sys.argv:
        pfad = sys.argv[sys.argv.index("--vorschau") + 1]
        grund = np.array([0.30, 0.48, 0.20])
        himmel = np.array([0.60, 0.75, 0.92])
        bild = atlas[..., :3] * 2.0 * grund[None, None, :]
        bild = bild * atlas[..., 3:4] + himmel[None, None, :] * (1 - atlas[..., 3:4])
        Image.fromarray((np.clip(bild, 0, 1) * 255).astype(np.uint8)).save(pfad)


if __name__ == "__main__":
    main()
