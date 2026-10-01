"""LAUB-ATLAS fuer die Baumkronen — gemalte Laubkarten mit Alpha, selbst erzeugt
(Nutzerwunsch 2026-10-01: "billig, rueste es auf", Baeume mit aufruesten, Quelle selbst).
ZWEITE FASSUNG (selber Tag): einzelne Blaetter mit Mittelrippe und Nadeln waren zu
realistisch — gewuenscht ist "zelda-maessig" (BotW): PUFFIGE, GEMALTE Laubwolken mit
gewelltem Rand und weichem Licht von oben links, Nadelzweige als weiche, ueberlappende
Lappen.

    python3 tools/build_laubtextur.py [--vorschau <png>]

Schreibt tools/bodentexturen/laub_atlas.png (2048 x 1024):
    links vier Felder 512 x 512
      LAUB      (0, 0)     rundes Laubbueschel aus spitzen Blaettern (Eiche, Busch, Urwald,
                           Mangrove)
      FEINLAUB  (512, 0)   luftiges Bueschel aus kleinen Blaettern (Birke, Akazie)
      NADEL     (0, 512)   Band einer Astetage fuer Fichte/Tanne, in x kachelbar: oben
                           deckend, unten haengende Zweigspitzen
      KIEFER    (512, 512) stachliges Nadelbueschel
    rechts zwei Felder 1024 x 512
      WEDEL     (1024, 0)   Palmwedel: Ansatz links, Spitze rechts, einzelne lange Fiedern
      FARN      (1024, 512) Farnwedel: viele kurze Fiedern, Lanzettform
Laub, Feinlaub und Kiefer sitzen auf Karten, die sich im Spiel zur Kamera drehen (Bueschel),
Nadel auf den festen Schuerzen der Nadelbaeume, Wedel und Farn auf gebogenen, gefalteten
Wedelflaechen (tools/build_baeume.py).
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
    def __init__(self, seed, breite=N):
        self.w = breite
        self.a = np.zeros((N, breite))
        self.c = np.ones((N, breite, 3))
        self.rng = np.random.default_rng(seed)

    def _patch(self, x0, x1, y0, y1):
        x0 = max(int(np.floor(x0)), 0)
        y0 = max(int(np.floor(y0)), 0)
        x1 = min(int(np.ceil(x1)) + 1, self.w)
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
    """Pinselstruktur: kleine helle und dunkle Tupfer (nur auf gedeckten Pixeln)."""
    for k in range(n):
        x, y = rng.random() * 512, rng.random() * 512
        r = 6 + rng.random() * 9
        if rng.random() < 0.5:
            f.tupfer((x, y), r, (oben_hell, oben_hell, oben_hell * 0.95))
        else:
            f.tupfer((x, y), r, (unten_dunkel, unten_dunkel, unten_dunkel * 1.02))


# DRITTE FASSUNG (2026-10-01 nachts, "baue die Baeume auch auf den Zelda-Look um"): die
# Felder 0, 1 und 3 sind jetzt BUESCHEL fuer Karten, die sich IMMER ZUR KAMERA drehen
# (TerrainWorld: Flora-Shader, `ecke`). Ein Bueschel ist deshalb rund und hat KEIN
# gemaltes Licht aus einer Richtung (das Licht kommt aus der Kronennormale): ein dichter
# Kern, nach aussen Blaetter, die den Umriss als Laubkante zeichnen — innen hell, aussen
# dunkler, so liest sich jedes Bueschel als kleine Kuppel. Die zweite Fassung (Laubwolke
# aus Kreisen mit Licht von oben links, auf fest stehenden Karten) stand im Spiel als
# Haufen getupfter Plaettchen da, von der Seite sah man die Karten als Striche.
def _bueschel(f, rng, mitte, r_kern, ringe, blatt_l, blatt_b, spitz, streu=0.45, kern_ton=0.80):
    """ringe: Liste (Radius des Blattansatzes, Anzahl, Ton). Aussen zuerst (liegt hinten)."""
    cx, cy = mitte
    f.puff((cx, cy), r_kern, (kern_ton, kern_ton, kern_ton * 0.98), wellen=7, welle=0.05,
           kontrast=0.0)
    for (rr, n, ton) in ringe:
        ph = rng.random() * 6.28
        for k in range(n):
            a = ph + 2 * np.pi * (k + rng.normal(0, 0.18)) / n
            r0 = rr * (0.88 + 0.24 * rng.random())
            w = a + rng.normal(0, streu)
            L = blatt_l * (0.80 + 0.40 * rng.random())
            t = ton * (0.92 + 0.16 * rng.random())
            f.blatt((cx + np.cos(a) * r0, cy + np.sin(a) * r0), w, L,
                    blatt_b * (0.85 + 0.3 * rng.random()), (t, t, t * 0.97), rippe=0.0,
                    spitz=spitz, licht=0.07)


def laub(seed=1):
    """Laubbueschel (Eiche, Busch, Urwald, Akazie, Mangrove): spitze Blaetter in fuenf
    Ringen um einen dichten Kern, die aeusseren ragen als Laubkante ueber den Umriss."""
    f = Feld(seed)
    rng = f.rng
    _bueschel(f, rng, (256, 256), 172,
              [(150, 22, 0.80), (118, 19, 0.90), (84, 15, 1.00), (48, 10, 1.10), (8, 6, 1.20)],
              blatt_l=92, blatt_b=27, spitz=0.75)
    _pinsel(f, rng, 120, oben_hell=1.06, unten_dunkel=0.94)
    return f.fertig()


def feinlaub(seed=2):
    """Birke: kleine rundliche Blaetter, lockerer Rand (einzelne Blaetter stehen frei ab),
    kleinerer Kern — das Bueschel wirkt luftig."""
    f = Feld(seed)
    rng = f.rng
    _bueschel(f, rng, (256, 256), 128,
              [(178, 28, 0.82), (150, 28, 0.86), (116, 25, 0.94), (82, 20, 1.02),
               (46, 13, 1.10), (8, 7, 1.18)],
              blatt_l=50, blatt_b=21, spitz=0.55, streu=0.7, kern_ton=0.84)
    _pinsel(f, rng, 90, oben_hell=1.06, unten_dunkel=0.94)
    return f.fertig()


def nadelschuerze(seed=3):
    """Fichte/Tanne: das Band einer ASTETAGE, in x kachelbar (laeuft um den Kegel der Etage).
    Oben (am Stamm) deckend und dunkel, nach unten haengende Zweigspitzen verschiedener
    Laenge, zur Spitze hin heller. Vier grosse Zweige je Feld, dazwischen kurze.
    Jedes Element wird dreimal gemalt (x - 512, x, x + 512) — die Zufallswerte dafuer VOR
    der Schleife ziehen, sonst passt der linke Rand nicht an den rechten."""
    f = Feld(seed)
    rng = f.rng

    def strich3(p0, p1, b0, b1, farbe):
        for dx in (-512, 0, 512):
            f.strich((p0[0] + dx, p0[1]), (p1[0] + dx, p1[1]), b0, b1, farbe)

    def lappen3(ansatz, winkel, laenge, breite, farbe):
        for dx in (-512, 0, 512):
            f.lappen((ansatz[0] + dx, ansatz[1]), winkel, laenge, breite, farbe, haengen=0.0,
                     kontrast=0.10)

    # deckender Grund: senkrechte Bahnen, oben dunkel
    for k in range(40):
        x = rng.random() * 512
        ton = 0.70 + 0.12 * rng.random()
        strich3((x, -20), (x + rng.normal(0, 8), 240 + rng.random() * 70), 26, 20,
                (ton, ton, ton * 0.98))
    # haengende Zweige: lange (vier je Feld) und kurze dazwischen, jeder aus vier
    # uebereinanderliegenden Lappen (der unterste der hellste) mit Seitenfransen
    zweige = []
    for k in range(4):
        zweige.append((64 + k * 128 + rng.normal(0, 12), 452 + rng.random() * 44, 44))
    for k in range(4):
        zweige.append((128 + k * 128 + rng.normal(0, 16), 372 + rng.random() * 40, 34))
    for k in range(10):
        zweige.append((rng.random() * 512, 318 + rng.random() * 46, 24))
    zweige.sort(key=lambda z: z[1])
    for (x, y_spitze, b) in zweige:
        stufen = 4
        for st in range(stufen):
            t = (st + 1) / stufen
            ya = 150 + (y_spitze - 150) * (t - 0.42)
            L = max(150 + (y_spitze - 150) * t - ya, 30)
            ton = 0.82 + 0.36 * t + rng.normal(0, 0.03)
            bb = b * (1.20 - 0.50 * t)
            xs = x + rng.normal(0, 3)
            # Seitenfransen zuerst (liegen hinter dem Lappen): schmal, schraeg nach unten
            for seite in (-1, 1):
                for q in range(3):
                    yy = ya + L * (0.15 + 0.24 * q)
                    lappen3((xs + seite * bb * 0.30, yy),
                            np.pi * 0.5 - seite * (0.42 + rng.normal(0, 0.08)),
                            bb * 1.9, bb * 0.30, (ton * 0.95, ton * 0.95, ton * 0.93))
            lappen3((xs, ya), np.pi * 0.5 + rng.normal(0, 0.05), L, bb, (ton, ton, ton * 0.97))
    return f.fertig()


def kiefer(seed=4):
    """Kiefer: Nadelbueschel — lange, schmale Nadelfaecher um einen dichten Kern, stachliger
    Umriss."""
    f = Feld(seed)
    rng = f.rng
    _bueschel(f, rng, (256, 256), 150,
              [(150, 46, 0.80), (124, 40, 0.88), (92, 32, 0.98), (58, 22, 1.08), (22, 12, 1.18)],
              blatt_l=70, blatt_b=9.5, spitz=0.45, streu=0.55, kern_ton=0.80)
    _pinsel(f, rng, 90, oben_hell=1.06, unten_dunkel=0.94)
    return f.fertig()


def _wedel(seed, n_je_seite, l_max, breite, winkel_fuss, winkel_spitze, form, spitz,
           rippe_ton=(1.16, 1.14, 0.92)):
    """Gemalter Wedel, 1024 x 512: Ansatz links, Spitze rechts, Mittelrippe waagerecht.
    Fiedern beidseitig schraeg zur Spitze, an der Rippe dicht (deckend), aussen einzeln
    (gefiederter Umriss). form(t) = Fiederlaenge laengs des Wedels (0..1)."""
    f = Feld(seed, 1024)
    rng = f.rng
    y0 = 256
    x_a, x_e = 26, 930
    # von der Spitze zum Ansatz malen: die Fiedern weiter innen liegen obenauf
    for k in range(n_je_seite - 1, -1, -1):
        t = (k + 0.5) / n_je_seite
        x = x_a + (x_e - x_a) * t
        for seite in (-1, 1):
            w = seite * (winkel_fuss + (winkel_spitze - winkel_fuss) * t + rng.normal(0, 0.05))
            L = l_max * form(t) * (0.90 + 0.20 * rng.random())
            ton = 0.90 + 0.22 * rng.random() + (0.05 if seite < 0 else -0.05)
            f.blatt((x + rng.normal(0, 3), y0 + seite * 2), w, L, breite * (0.85 + 0.3 * rng.random()),
                    (ton, ton, ton * 0.96), rippe=0.0, spitz=spitz, licht=0.10)
    # Endfieder und Mittelrippe
    f.blatt((x_e - 30, y0), 0.0, min(l_max * form(1.0) * 1.1 + 40, 1010 - x_e + 30), breite, (1.08, 1.08, 1.0),
            rippe=0.0, spitz=spitz, licht=0.08)
    f.strich((4, y0), (x_e, y0), 8.0, 2.0, rippe_ton)
    return f.fertig()


def palmwedel(seed=5):
    """Palme: lange, schmale Fiedern, in der Mitte am laengsten, deutlich einzeln."""
    return _wedel(seed, 38, 290, 15.0, 1.02, 0.55,
                  lambda t: (np.sin(np.pi * min(0.10 + 0.86 * t, 1.0)) ** 0.6) * (1.0 - 0.30 * t),
                  spitz=0.55)


def farnwedel(seed=6):
    """Baumfarn: viele kurze, breitere Fiedern fast quer zur Rippe, zur Spitze gleichmaessig
    kuerzer (Lanzettform), dichter Umriss."""
    return _wedel(seed, 54, 212, 13.0, 1.18, 0.85,
                  lambda t: min(t / 0.10, 1.0) ** 0.7 * (1.0 - t) ** 0.62 + 0.10,
                  spitz=0.80, rippe_ton=(1.05, 1.02, 0.86))


def main():
    # ATLAS 2048 x 1024: vier Felder 512 x 512 links (Laub, Feinlaub / Nadel, Kiefer), rechts
    # zwei Felder 1024 x 512 fuer die Wedel (Palme oben, Farn unten).
    felder = [(laub(), 0, 0), (feinlaub(), N, 0), (nadelschuerze(), 0, N), (kiefer(), N, N),
              (palmwedel(), 2 * N, 0), (farnwedel(), 2 * N, N)]
    atlas = np.zeros((2 * N, 4 * N, 4))
    for k, ((c, a), x, y) in enumerate(felder):
        h, w = a.shape
        atlas[y:y + h, x:x + w, :3] = np.clip(c * 0.5, 0, 1)
        atlas[y:y + h, x:x + w, 3] = a
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
