"""LAUB-ATLAS fuer die Baumkronen — Blattbueschel-Karten mit Alpha, selbst erzeugt
(Nutzerwunsch 2026-10-01: "billig, rueste es auf", Baeume mit aufruesten, Quelle selbst).

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


def laub(seed=1):
    """Laubbueschel: rund, in der Mitte dicht, am Rand locker; Blaetter zeigen nach aussen.
    Erste Fassung (ein Zweig mit grossen Blaettern oben im Feld) sah aus wie ein Busch-
    Symbol und fuellte die Karte schlecht."""
    f = Feld(seed)
    rng = f.rng
    holz = (0.42, 0.36, 0.30)
    for k in range(9):
        w = rng.random() * 2 * np.pi
        f.strich((256, 256), (256 + np.cos(w) * 190, 256 + np.sin(w) * 190), 3.0, 1.0, holz)
    blaetter = []
    for k in range(190):
        r = np.sqrt(rng.random()) * 205
        a = rng.random() * 2 * np.pi
        blaetter.append((r, a))
    blaetter.sort(key=lambda b: -b[0])          # aussen zuerst, die Mitte liegt vorne
    for (r, a) in blaetter:
        p = (256 + np.cos(a) * r, 256 + np.sin(a) * r)
        w = a + rng.normal(0, 0.55)
        L = 38 + rng.random() * 22
        ton = 0.80 + rng.random() * 0.40 - 0.10 * (r / 205)
        farbe = (ton * (0.92 + rng.random() * 0.16), ton, ton * (0.85 + rng.random() * 0.2))
        f.blatt(p, w, L, L * 0.32, farbe)
    return f.fertig()


def feinlaub(seed=2):
    """Birke: haengende, gebogene Zweiglein mit kleinen Blaettern, UNREGELMAESSIG verteilt
    (erste Fassung: neun gerade Zweige in gleichem Abstand — in der Krone lag das als
    Vorhang in Reihen)."""
    f = Feld(seed)
    rng = f.rng
    holz = (0.40, 0.36, 0.34)
    for k in range(16):
        x = 20 + rng.random() * 472
        y = 10 + rng.random() * 140
        pts = [(x, y)]
        drift = rng.normal(0, 4)
        schritte = 4 + int(rng.random() * 6)
        for s_ in range(schritte):
            px, py = pts[-1]
            pts.append((px + drift + rng.normal(0, 5), py + 34 + rng.random() * 14))
        for a, b in zip(pts[:-1], pts[1:]):
            f.strich(a, b, 1.5, 1.1, holz)
        for (px, py) in pts[1:]:
            for seite in (-1, 1):
                if py > 500 or rng.random() < 0.15:
                    continue
                w = np.pi / 2 + seite * (0.8 + rng.normal(0, 0.35))
                L = 22 + rng.random() * 12
                ton = 0.85 + rng.random() * 0.32
                farbe = (ton * (0.95 + rng.random() * 0.15), ton, ton * 0.85)
                f.blatt((px, py), w, L, L * 0.45, farbe, spitz=0.6)
    return f.fertig()


def nadelzweig(seed=3):
    """Fichte: flacher Zweig, Ansatz links (u = 0), Spitze rechts. Die Karte wird im Modell
    vom Stamm nach aussen gelegt. Dicht (erste Fassung 18 % Deckung = aus der Ferne Gitter)."""
    f = Feld(seed)
    rng = f.rng
    holz = (0.42, 0.36, 0.30)
    mitte = 256
    haupt = [(8, mitte), (504, mitte + rng.normal(0, 4))]
    f.strich(haupt[0], haupt[1], 3.5, 1.2, holz)
    zweige = [(haupt[0], haupt[1], 0.0, 1.0)]
    for s in np.linspace(0.05, 0.94, 17):
        x = 8 + s * 496
        for seite in (-1, 1):
            w = seite * (0.70 + rng.normal(0, 0.12))
            L = (1.0 - s) * 175 + 45
            a = (x, mitte)
            e = (x + np.cos(w) * L, mitte + np.sin(w) * L)
            f.strich(a, e, 1.8, 0.9, holz)
            zweige.append((a, e, w, L / 220))
    for (a, e, w, gr) in zweige:
        L = np.hypot(e[0] - a[0], e[1] - a[1])
        n = int(L / 2.0)
        for k in range(n):
            s = k / max(n - 1, 1)
            p = (a[0] + (e[0] - a[0]) * s, a[1] + (e[1] - a[1]) * s)
            for seite in (-1, 1):
                ww = w + seite * (0.95 + rng.normal(0, 0.18))
                ln = (16 + rng.random() * 7) * (0.75 + 0.25 * gr) * (1.0 - 0.35 * s)
                ton = 0.78 + rng.random() * 0.44
                farbe = (ton, ton, ton * (0.9 + rng.random() * 0.2))
                q = (p[0] + np.cos(ww) * ln, p[1] + np.sin(ww) * ln)
                f.strich(p, q, 1.6, 0.7, farbe)
    return f.fertig()


def kiefer(seed=4):
    """Kiefer: Nadelbueschel (Strahlen langer Nadeln um ein Zweigende)."""
    f = Feld(seed)
    rng = f.rng
    holz = (0.45, 0.33, 0.25)
    mitten = []
    for k in range(7):
        a = rng.random() * 2 * np.pi
        r = 80 + rng.random() * 120
        mitten.append((256 + np.cos(a) * r, 256 + np.sin(a) * r))
    mitten.append((256, 256))
    for (cx, cy) in mitten:
        f.strich((256, 400), (cx, cy), 3.0, 1.5, holz)
    for (cx, cy) in mitten:
        for k in range(190):
            w = rng.random() * 2 * np.pi
            ln = 45 + rng.random() * 50
            ton = 0.80 + rng.random() * 0.4
            q = (cx + np.cos(w) * ln, cy + np.sin(w) * ln * 0.85)
            f.strich((cx, cy), q, 1.7, 0.8, (ton, ton, ton * (0.9 + rng.random() * 0.2)))
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
