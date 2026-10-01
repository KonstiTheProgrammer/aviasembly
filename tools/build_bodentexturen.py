"""BODENTEXTUREN des Gelaende-Shaders — selbst erzeugt, kachelbar, GEMALT im Stil von Zelda
Breath of the Wild (Nutzer 2026-10-01: die erste, realistische Fassung mit Halmen, Kieseln
und Gesteinsschichten war "nicht passend", gewuenscht ist "zelda-maessig").

    python3 tools/build_bodentexturen.py [--vorschau <png>]

Schreibt je Material zwei PNG nach tools/bodentexturen/ (der Ordner traegt .gdignore):
    <name>_farbe.png    RGB = Farbfaktor / 2 (0.5 = Faktor 1, Mittel je Kanal genau 1),
                        A   = Hoehe (fuer das Ueberblenden nach Hoehe)
    <name>_normale.png  RG  = Normale in Texturrichtung (u, v) * 0.5 + 0.5, B = Hohlkehle (AO)
tools/_bodentexturen.gd packt sie danach nach shaders/boden/.

STIL: keine einzelnen Halme, Kiesel oder Risse — die Flaechen bestehen aus PINSELTUPFEN in drei
bis vier Toenen (dunkel zuerst, hell zuletzt und sparsamer), laengs eines weichen
Stroemungsfelds ausgerichtet, so wie ein Maler eine Wiese anlegt. Fels sind FACETTEN: grosse
ebene Flaechen mit eigenem Ton, an der Oberkante eine helle Lichtkante, wenige dunkle Fugen.
Relief nur schwach (die Form erzaehlt das Licht, nicht die Normale). Die Farbe ist ein FAKTOR
um 1: die Palette des Spiels bleibt die Grundfarbe.

Alles periodisch gerechnet (FFT-Rauschen, Zellen mit Umlauf, Tupfen mit Umlauf) -> nahtlos.
"""

import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

N = 512
ORDNER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bodentexturen")


# --- Bausteine -------------------------------------------------------------------------

def rausch(seed, beta=2.0, fmin=1.0, fmax=None):
    """Kachelbares Rauschen mit Spektrum 1/f^beta zwischen fmin und fmax (Zyklen je Kachel),
    auf Mittel 0 / Sigma 1 gebracht."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((N, N))
    F = np.fft.fft2(w)
    fy = np.fft.fftfreq(N) * N
    fx = np.fft.fftfreq(N) * N
    f = np.sqrt(fx[None, :] ** 2 + fy[:, None] ** 2)
    f[0, 0] = 1.0
    filt = 1.0 / f ** (beta / 2.0)
    filt[f < fmin] = 0.0
    if fmax is not None:
        filt *= np.exp(-(f / fmax) ** 4)
    filt[0, 0] = 0.0
    r = np.real(np.fft.ifft2(F * filt))
    return (r - r.mean()) / (r.std() + 1e-9)


def zellen(seed, anzahl, jitter=1.0):
    """Kachelbares Zellmuster (Worley): F1, F2 in Pixeln und die Zellnummer je Pixel."""
    rng = np.random.default_rng(seed)
    g = int(np.sqrt(anzahl))
    gx, gy = np.meshgrid(np.arange(g), np.arange(g))
    pts = (np.stack([gx.ravel(), gy.ravel()], 1) + 0.5
           + (rng.random((g * g, 2)) - 0.5) * jitter) / g * N
    pts %= N
    baum = cKDTree(pts, boxsize=N)
    yy, xx = np.mgrid[0:N, 0:N]
    q = np.stack([xx.ravel() + 0.5, yy.ravel() + 0.5], 1)
    d, idx = baum.query(q, k=2)
    return (d[:, 0].reshape(N, N), d[:, 1].reshape(N, N), idx[:, 0].reshape(N, N),
            pts, rng)


def verbiegen(feld, dx, dy, ordnung=1):
    """Domain-Warp mit Umlauf. ordnung=0 fuer Zellnummern — interpoliert entstanden an jeder
    Zellgrenze duenne Linien mit fremden Nummern (Schnoerkel im Fels)."""
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    return ndimage.map_coordinates(feld, [yy + dy, xx + dx], order=ordnung, mode="grid-wrap")


def weich(feld, sigma):
    return ndimage.gaussian_filter(feld, sigma, mode="wrap")


def norm01(a):
    lo, hi = np.percentile(a, 0.5), np.percentile(a, 99.5)
    return np.clip((a - lo) / (hi - lo + 1e-9), 0.0, 1.0)


def striche(seed, anzahl, laenge, breite, richtung=None, streu=np.pi, gewicht=None):
    """Kurze Striche (Halme, Nadeln) mit Umlauf aufgestempelt. Liefert die Summe der
    Strichstaerke und je Pixel die Hoehe entlang des Strichs (0 Fuss .. 1 Spitze)."""
    rng = np.random.default_rng(seed)
    feld = np.zeros((N, N))
    spitze = np.zeros((N, N))
    farbe = np.zeros((N, N))
    r = int(laenge) + 3
    oy, ox = np.mgrid[-r:r + 1, -r:r + 1].astype(np.float64)
    for i in range(anzahl):
        cx, cy = rng.random(2) * N
        if gewicht is not None:
            # dichter, wo das Gewicht hoch ist (Bueschel)
            if rng.random() > gewicht[int(cy) % N, int(cx) % N]:
                continue
        w = (richtung if richtung is not None else 0.0) + (rng.random() - 0.5) * 2 * streu
        L = laenge * (0.55 + 0.9 * rng.random())
        d = np.array([np.cos(w), np.sin(w)])
        px = ox - (cx - np.floor(cx))
        py = oy - (cy - np.floor(cy))
        t = px * d[0] + py * d[1]
        s = -px * d[1] + py * d[0]
        tt = np.clip(t / L, 0.0, 1.0)
        b = breite * (1.0 - 0.75 * tt)          # zur Spitze schmaler
        m = np.exp(-(s / np.maximum(b, 0.3)) ** 2) * ((t > 0) & (t < L))
        ix = (np.arange(-r, r + 1) + int(np.floor(cx))) % N
        iy = (np.arange(-r, r + 1) + int(np.floor(cy))) % N
        sub = np.ix_(iy, ix)
        feld[sub] = np.maximum(feld[sub], m)
        spitze[sub] = np.where(m > 0.3, np.maximum(spitze[sub], tt * m), spitze[sub])
        farbe[sub] = np.where(m > 0.3, rng.random(), farbe[sub])
    return feld, spitze, farbe


def normale_aus(hoehe, staerke):
    """Normale (u, v) aus der Hoehe, zentrale Differenzen mit Umlauf."""
    du = (np.roll(hoehe, -1, 1) - np.roll(hoehe, 1, 1)) * 0.5
    dv = (np.roll(hoehe, -1, 0) - np.roll(hoehe, 1, 0)) * 0.5
    nx = -du * staerke
    ny = -dv * staerke
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return nx / ln, ny / ln, nz / ln


def hohlkehle(hoehe, sigma, staerke):
    """Umgebungsverdeckung: tiefer als die Umgebung = dunkler."""
    um = weich(hoehe, sigma)
    return np.clip(1.0 - np.maximum(um - hoehe, 0.0) * staerke, 0.0, 1.0)


def speichern(name, farbe, hoehe, normale_staerke, ao_sigma=3.0, ao_staerke=3.0):
    """farbe: (N, N, 3) Faktor — wird je Kanal auf Mittel 1 gebracht."""
    farbe = np.clip(farbe, 0.0, None)
    farbe = farbe / farbe.reshape(-1, 3).mean(0)[None, None, :]
    ao = hohlkehle(hoehe, ao_sigma, ao_staerke)
    nx, ny, _ = normale_aus(hoehe, normale_staerke)
    rgba = np.zeros((N, N, 4))
    rgba[..., :3] = np.clip(farbe * 0.5, 0.0, 1.0)
    rgba[..., 3] = np.clip(hoehe, 0.0, 1.0)
    nrm = np.zeros((N, N, 3))
    nrm[..., 0] = nx * 0.5 + 0.5
    nrm[..., 1] = ny * 0.5 + 0.5
    nrm[..., 2] = ao
    os.makedirs(ORDNER, exist_ok=True)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8)).save(
        os.path.join(ORDNER, name + "_farbe.png"))
    Image.fromarray((nrm * 255 + 0.5).astype(np.uint8)).save(
        os.path.join(ORDNER, name + "_normale.png"))
    print("%-10s Faktor min %.2f max %.2f  Hoehe %.2f..%.2f" % (
        name, farbe.min(), farbe.max(), hoehe.min(), hoehe.max()))
    return farbe, hoehe, ao


def mische(a, b, t):
    return a + (b - a) * t[..., None]


# --- Pinsel --------------------------------------------------------------------------------

def tupfen(feld_c, feld_h, rng, anzahl, laenge, breite, ton, hoehe, winkel_feld=None,
           streu=0.35, ton_streu=0.05, weich_rand=0.45):
    """Pinseltupfen mit Umlauf aufmalen: Ellipse laenge x breite (Pixel), Richtung aus
    winkel_feld (Bogenmass je Pixel) plus Streuung, Farbe ton (Faktor) +- ton_streu, Hoehe
    hoehe. Weicher Rand, deckend (spaeter gemalt = oben)."""
    r = int(laenge) + 3
    oy, ox = np.mgrid[-r:r + 1, -r:r + 1].astype(np.float64)
    ton = np.asarray(ton, dtype=np.float64)
    for _ in range(anzahl):
        cx, cy = rng.random(2) * N
        w = (winkel_feld[int(cy) % N, int(cx) % N] if winkel_feld is not None else 0.0) \
            + rng.normal(0.0, streu)
        L = laenge * (0.7 + 0.6 * rng.random())
        B = breite * (0.75 + 0.5 * rng.random())
        px = ox - (cx - np.floor(cx))
        py = oy - (cy - np.floor(cy))
        u = px * np.cos(w) + py * np.sin(w)
        v = -px * np.sin(w) + py * np.cos(w)
        d = np.sqrt((u / (L * 0.5)) ** 2 + (v / (B * 0.5)) ** 2)
        m = np.clip((1.0 - d) / weich_rand, 0.0, 1.0)
        ix = (np.arange(-r, r + 1) + int(np.floor(cx))) % N
        iy = (np.arange(-r, r + 1) + int(np.floor(cy))) % N
        sub = np.ix_(iy, ix)
        # Helligkeit je Tupfen, nicht je Kanal: mit Streuung je Kanal lagen auf Sand und
        # Schnee bunte Pastellflecken (Regenbogen).
        t = ton * (1.0 + rng.normal(0.0, ton_streu))
        feld_c[sub] = feld_c[sub] * (1.0 - m[..., None]) + t[None, None, :] * m[..., None]
        feld_h[sub] = feld_h[sub] * (1.0 - m) + hoehe * m


def stroemung(seed, skala=2.6, staerke=1.4, grund=0.0):
    """Weiches Richtungsfeld (Bogenmass) fuer die Pinselrichtung."""
    return grund + rausch(seed, skala, 1, 6) * staerke


def grund(ton):
    c = np.empty((N, N, 3))
    c[...] = np.asarray(ton)[None, None, :]
    return c


def ton(r, g, b):
    return np.array([r, g, b])


# --- Materialien ------------------------------------------------------------------------
# Kachelgroessen (Weltmeter je Kachel) stehen im Shader (gelaende_kern: KACHEL_*).

def gras():
    """Wiese, gemalt: viele laengliche Tupfen in vier Toenen (tiefes Gruen in den Kehlen,
    Mittelgruen, helles Gelbgruen, wenige sonnige Spitzlichter), schraeg ausgerichtet wie
    Pinselstriche, die der Wind gekaemmt hat."""
    rng = np.random.default_rng(101)
    w = stroemung(102, grund=-0.9)
    c = grund(ton(0.80, 0.84, 0.86))
    h = np.full((N, N), 0.2)
    tupfen(c, h, rng, 1400, 30, 11, ton(0.80, 0.86, 0.90), 0.25, w)
    tupfen(c, h, rng, 2200, 26, 9, ton(1.00, 1.00, 1.00), 0.55, w)
    tupfen(c, h, rng, 1300, 22, 7, ton(1.16, 1.12, 0.92), 0.8, w)
    tupfen(c, h, rng, 260, 16, 5, ton(1.30, 1.24, 0.86), 1.0, w)
    c = weich(c, (0.7, 0.7, 0))
    h = norm01(weich(h, 1.2))
    return speichern("gras", c, h, 1.6, 4.0, 1.0)


def waldboden():
    """Waldboden, gemalt: dunkles Gruen mit Moospolstern (runde helle Tupfen) und warmem
    Laub (wenige braune Tupfen)."""
    rng = np.random.default_rng(111)
    w = stroemung(112)
    c = grund(ton(0.86, 0.88, 0.92))
    h = np.full((N, N), 0.2)
    tupfen(c, h, rng, 900, 34, 18, ton(0.80, 0.86, 0.92), 0.2, w, streu=1.0)
    tupfen(c, h, rng, 700, 26, 20, ton(1.02, 1.10, 0.96), 0.6, w, streu=1.5)
    tupfen(c, h, rng, 240, 20, 14, ton(1.30, 1.05, 0.72), 0.5, w, streu=2.0)
    tupfen(c, h, rng, 260, 16, 12, ton(1.18, 1.28, 0.90), 0.9, w, streu=1.5)
    c = weich(c, (0.8, 0.8, 0))
    h = norm01(weich(h, 1.5))
    return speichern("waldboden", c, h, 1.6, 4.0, 1.0)


def erde():
    """Erde/Acker/Weg, gemalt: runde, weiche Tupfen in warmen Toenen ohne Vorzugsrichtung
    (laengliche Striche lasen sich als Fell), vereinzelt helle Steinchen."""
    rng = np.random.default_rng(121)
    c = grund(ton(0.92, 0.92, 0.94))
    h = np.full((N, N), 0.3)
    tupfen(c, h, rng, 700, 34, 22, ton(0.86, 0.85, 0.88), 0.2, None, streu=3.0)
    tupfen(c, h, rng, 900, 28, 18, ton(1.02, 1.0, 0.98), 0.55, None, streu=3.0)
    tupfen(c, h, rng, 420, 22, 14, ton(1.12, 1.07, 1.0), 0.8, None, streu=3.0)
    tupfen(c, h, rng, 110, 9, 8, ton(1.28, 1.26, 1.22), 1.0, None, streu=3.0)
    c = weich(c, (1.2, 1.2, 0))
    h = norm01(weich(h, 1.8))
    return speichern("erde", c, h, 1.2, 4.0, 1.0)


def sand():
    """Sand, gemalt: glatte Flaeche mit weichen, verbogenen Rippelbaendern und sehr wenig
    Kontrast (Striche lasen sich auf Sand als Fell)."""
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    wx = rausch(133, 2.8, 1, 6) * 10.0
    phase = (xx * 0.35 + yy) / N * 2 * np.pi * 9 + wx * 0.45
    rip = 0.5 + 0.5 * np.sin(phase)
    rip = rip ** 1.6
    staerke = np.clip(0.5 + 0.5 * rausch(134, 2.5, 1, 6), 0.0, 1.0)
    h = norm01(rip * staerke * 0.6 + 0.4 * norm01(rausch(135, 3.0, 1, 8)))
    c = grund(ton(1.0, 1.0, 1.0))
    c *= (0.94 + 0.10 * h)[..., None]
    c = weich(c, (1.0, 1.0, 0))
    return speichern("sand", c, h, 0.8, 6.0, 0.5)


def fels():
    """Fels im Zelda-Stil, Zeilen = Hoehe (triplanar): grosse FACETTEN (Zellen, jede eine
    schraege Ebene mit eigenem Ton und weichem Verlauf), an der OBERKANTE jeder Facette eine
    helle Lichtkante, an der Unterkante ein Schatten, wenige dunkle Fugen. Dazu sehr weiche
    waagerechte Baender. Kein Korn, keine feinen Risse."""
    # FLACHE BLOECKE: Zellen in einem Raum, dessen Hoehe doppelt zaehlt -> die Facetten sind
    # breiter als hoch und liegen wie Baenke (rund = Pflastersteine, erste Fassung).
    rng = np.random.default_rng(141)
    anzahl = 28
    pts = rng.random((anzahl, 2)) * np.array([N, 2 * N])
    baum = cKDTree(pts, boxsize=[N, 2 * N])
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    q = np.stack([xx.ravel() + 0.5, (yy.ravel() + 0.5) * 2.0], 1)
    dd, ii = baum.query(q, k=2)
    f1 = dd[:, 0].reshape(N, N)
    f2 = dd[:, 1].reshape(N, N)
    idx = ii[:, 0].reshape(N, N)
    pts = pts / np.array([1.0, 2.0])
    wx = rausch(142, 2.8, 1, 8) * 14.0
    wy = rausch(143, 2.8, 1, 8) * 6.0
    idx = np.rint(verbiegen(idx.astype(np.float64), wx, wy, 0)).astype(int) % (idx.max() + 1)
    f1w = verbiegen(f1, wx, wy)
    f2w = verbiegen(f2, wx, wy)
    n_z = idx.max() + 1
    neig = rng.normal(0, 1, (n_z, 2)) * 0.010
    neig[:, 1] -= 0.006                      # Facetten neigen sich eher nach oben (Licht)
    basis = rng.random(n_z)
    p = pts[idx]
    ddx = (xx - p[..., 0] + N / 2) % N - N / 2
    ddy = (yy - p[..., 1] + N / 2) % N - N / 2
    ebene = basis[idx] * 0.4 + neig[idx, 0] * ddx + neig[idx, 1] * ddy
    kante = np.clip(1.0 - (f2w - f1w) / 9.0, 0.0, 1.0)   # 1 an der Fuge
    # Oben/unten an der Fuge: Richtung zur Zellmitte (dy < 0 = Zelle liegt oberhalb)
    oben = np.clip(-ddy / 30.0, -1.0, 1.0)
    hoehe = norm01(ebene - kante ** 2 * 0.25)
    c = grund(ton(1.0, 1.0, 1.0))
    c *= (0.86 + 0.26 * basis[idx])[..., None]
    # weicher Verlauf je Facette (oben heller)
    c *= (1.0 + 0.10 * np.clip(-ddy / 40.0, -1.0, 1.0))[..., None]
    # Lichtkante an der Oberkante, Schatten an der Unterkante
    licht = kante ** 1.5 * np.clip(-oben, 0, 1)
    schatten = kante ** 1.5 * np.clip(oben, 0, 1)
    c = c * (1.0 + 0.30 * licht)[..., None]
    c = c * (1.0 - 0.32 * schatten)[..., None]
    fuge = np.clip(1.0 - (f2w - f1w) / 2.0, 0.0, 1.0) * np.clip(rausch(144, 2.0, 2, 12) - 0.1, 0, 1)
    c *= (1.0 - 0.25 * fuge)[..., None]
    band = np.sin((yy + wy * 2.0) / N * 2 * np.pi * 5 + rausch(145, 3.0, 1, 4))
    c *= (0.97 + 0.05 * band)[..., None]
    c = mische(c, grund(ton(1.04, 1.0, 0.94)), np.clip(basis[idx] - 0.65, 0, 1))
    c = weich(c, (0.8, 0.8, 0))
    return speichern("fels", c, hoehe, 5.0, 6.0, 1.2)


def schnee():
    """Schnee, gemalt: weiche, breite Verwehungen, kuehle blaue Kehlen, wenig Kontrast."""
    rng = np.random.default_rng(151)
    w = stroemung(152, staerke=0.8, grund=0.3)
    c = grund(ton(0.94, 0.96, 1.02))
    h = np.full((N, N), 0.3)
    tupfen(c, h, rng, 260, 110, 40, ton(0.88, 0.92, 1.04), 0.2, w, streu=0.3, ton_streu=0.02)
    tupfen(c, h, rng, 380, 90, 34, ton(1.03, 1.03, 1.0), 0.75, w, streu=0.3, ton_streu=0.02)
    c = weich(c, (3.0, 3.0, 0))
    h = norm01(weich(h, 4.0))
    return speichern("schnee", c, h, 1.2, 8.0, 0.8)


MATERIALIEN = [gras, waldboden, erde, sand, fels, schnee]   # Reihenfolge = Ebene im Array


def vorschau(pfad):
    kacheln = []
    for name in ["gras", "waldboden", "erde", "sand", "fels", "schnee"]:
        f = Image.open(os.path.join(ORDNER, name + "_farbe.png")).convert("RGB")
        n = Image.open(os.path.join(ORDNER, name + "_normale.png")).convert("RGB")
        # Farbe als Beispiel auf einer typischen Grundfarbe, dazu "beleuchtet" (Normale)
        grund = {"gras": (0.30, 0.48, 0.18), "waldboden": (0.16, 0.26, 0.15),
                 "erde": (0.45, 0.33, 0.22), "sand": (0.86, 0.78, 0.58),
                 "fels": (0.46, 0.45, 0.43), "schnee": (0.93, 0.95, 0.98)}[name]
        fa = np.asarray(f).astype(np.float64) / 255 * 2.0
        na = np.asarray(n).astype(np.float64) / 255 * 2.0 - 1.0
        nz = np.sqrt(np.clip(1 - na[..., 0] ** 2 - na[..., 1] ** 2, 0, 1))
        l = np.array([-0.5, -0.45, 0.74])
        l /= np.linalg.norm(l)
        licht = np.clip(na[..., 0] * l[0] + na[..., 1] * l[1] + nz * l[2], 0, 1) * 0.85 + 0.25
        ao = np.asarray(n).astype(np.float64)[..., 2] / 255
        bild = np.clip(fa * np.array(grund)[None, None, :] * licht[..., None] * ao[..., None], 0, 1)
        kacheln.append(Image.fromarray((bild * 255).astype(np.uint8)))
    W = Image.new("RGB", (N * 3, N * 2))
    for k, im in enumerate(kacheln):
        W.paste(im, ((k % 3) * N, (k // 3) * N))
    W.save(pfad)


if __name__ == "__main__":
    for m in MATERIALIEN:
        m()
    with open(os.path.join(ORDNER, ".gdignore"), "w") as fh:
        fh.write("")
    if "--vorschau" in sys.argv:
        vorschau(sys.argv[sys.argv.index("--vorschau") + 1])
