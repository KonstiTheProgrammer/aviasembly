"""BODENTEXTUREN des Gelaende-Shaders — selbst erzeugt, kachelbar (Nutzerwunsch 2026-10-01:
"echte Texturen", Quelle "selbst erzeugen", kein Download).

    python3 tools/build_bodentexturen.py [--vorschau <png>]

Schreibt je Material zwei PNG nach tools/bodentexturen/ (der Ordner traegt .gdignore):
    <name>_farbe.png    RGB = Farbfaktor / 2 (0.5 = Faktor 1, Mittel je Kanal genau 1),
                        A   = Hoehe (fuer das Ueberblenden nach Hoehe)
    <name>_normale.png  RG  = Normale in Texturrichtung (u, v) * 0.5 + 0.5, B = Hohlkehle (AO)
tools/_bodentexturen.gd packt sie danach in shaders/boden_material_*.res (Texture2DArray).

DER GRUNDSATZ, gelernt an der ersten "glatten" Fassung mit Rauschkorn ("billig und alt"):
Rauschen allein ist keine Oberflaeche. Jedes Material hier wird aus STRUKTUR gebaut —
Halme, Bueschel, Kiesel, Klumpen, Platten, Schichten, Risse, Rippel —, und das Relief
(Normale) kommt aus derselben Hoehe wie die Farbe: was hell ist, steht vor, was dunkel ist,
liegt in der Kehle. Die Farbe ist ein FAKTOR um 1: die Palette des Spiels (palette.gdshaderinc)
und die Grossvariation aus den Vertexfarben bleiben die Grundfarbe, die Textur legt nur die
Oberflaeche darauf. Damit stimmen Karte, Fernschuerze und Nahbereich weiter ueberein.

Alles ist periodisch gerechnet (FFT-Rauschen, Abstaende mit Umlauf, np.roll), also nahtlos.
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


def ton(r, g, b):
    return np.array([r, g, b])[None, None, :]


# --- Materialien ------------------------------------------------------------------------
# Kachelgroessen (Weltmeter je Kachel) stehen im Shader (gelaende_kern: KACHEL_*).

def gras():
    """Wiese von oben, Kachel ~2,6 m: Bueschel, dazwischen dunklere Kehlen mit etwas Erde,
    darauf Halme in allen Richtungen, Spitzen heller und trockener."""
    f1, f2, idx, _, rng = zellen(11, 90, 0.9)
    buschel = norm01(1.0 - f1 / (f1.max() + 1e-9)) ** 0.8
    buschel = norm01(buschel + 0.25 * rausch(12, 2.0, 2, 40))
    halme, spitze, zufall = striche(13, 14000, 13.0, 1.25, gewicht=0.35 + 0.65 * buschel)
    fein, fspitze, fzufall = striche(14, 9000, 7.0, 0.9)
    halme = np.maximum(halme, fein * 0.8)
    spitze = np.maximum(spitze, fspitze * 0.8)
    zufall = np.where(fein > halme * 0.99, fzufall, zufall)
    hoehe = norm01(buschel * 0.55 + halme * 0.30 + spitze * 0.25)
    # Farbe: Kehle dunkel und kuehl, Halm satt, Spitze heller und gelblich; je Halm streut
    # der Ton (manche trocken, manche tiefgruen); kleine Erdflecken in den tiefsten Kehlen.
    kehle = ton(0.55, 0.62, 0.72)
    halm = ton(1.00, 1.00, 1.00)
    tip = ton(1.30, 1.22, 0.92)
    c = mische(np.broadcast_to(kehle, (N, N, 3)).copy(), np.broadcast_to(halm, (N, N, 3)),
               np.clip(halme * 0.85 + buschel * 0.35, 0, 1))
    c = mische(c, np.broadcast_to(tip, (N, N, 3)), np.clip(spitze, 0, 1) * 0.8)
    trocken = (zufall > 0.82) & (halme > 0.3)
    c[trocken] *= np.array([1.22, 1.08, 0.80])
    tief = (zufall < 0.15) & (halme > 0.3)
    c[tief] *= np.array([0.80, 0.92, 0.95])
    erde = np.clip((0.18 - hoehe) / 0.18, 0, 1) * np.clip(0.5 + 0.5 * rausch(15, 2.0, 4, 60), 0, 1)
    c = mische(c, np.broadcast_to(ton(0.95, 0.70, 0.45), (N, N, 3)), erde * 0.7)
    return speichern("gras", c, hoehe, 6.0, 2.5, 2.5)


def waldboden():
    """Nadel- und Laubstreu mit Moospolstern, Kachel ~3 m."""
    moos = norm01(rausch(21, 2.6, 2, 30))
    moos = np.clip((moos - 0.45) * 3.0, 0, 1)
    nadel, nspitze, nzuf = striche(22, 9000, 9.0, 0.8)
    # Blaetter: kleine Zellen mit Ellipsenform
    f1, f2, idx, _, rng = zellen(23, 900, 1.0)
    blatt = np.clip(1.0 - f1 / 6.5, 0, 1)
    blatt = blatt * (rng.random(idx.max() + 1)[idx] > 0.55)
    zweige, _, _ = striche(24, 160, 30.0, 1.1)
    hoehe = norm01(moos * 0.35 + nadel * 0.25 + blatt * 0.35 + zweige * 0.35
                   + 0.15 * rausch(25, 2.0, 2, 50))
    braun = ton(1.25, 0.95, 0.70)
    c = np.broadcast_to(ton(0.85, 0.85, 0.85), (N, N, 3)).copy()
    c = mische(c, np.broadcast_to(braun, (N, N, 3)), np.clip(nadel * 0.9, 0, 1))
    laub = rng.random(idx.max() + 1)[idx]
    c = mische(c, np.broadcast_to(ton(1.45, 1.05, 0.60), (N, N, 3)), blatt * (0.5 + 0.5 * laub))
    c = mische(c, np.broadcast_to(ton(0.90, 1.25, 0.70), (N, N, 3)), moos * 0.9)
    c = mische(c, np.broadcast_to(ton(0.80, 0.62, 0.45), (N, N, 3)), np.clip(zweige, 0, 1))
    c *= (0.65 + 0.35 * hoehe)[..., None]
    return speichern("waldboden", c, hoehe, 5.0, 3.0, 3.0)


def erde():
    """Ackerkrume und Feldweg, Kachel ~3 m: weiche Klumpen (verbogene Zellen, OHNE dunkle
    Fugen — die erste Fassung war ein Rissmuster wie getrockneter Schlamm bzw. Pflaster),
    feine Kruemel, wenige Kiesel, feuchte und trockene Stellen."""
    wx = rausch(36, 2.6, 2, 16) * 10.0
    wy = rausch(37, 2.6, 2, 16) * 10.0
    f1, f2, idx, _, rng = zellen(31, 260, 1.0)
    klumpen = norm01(verbiegen(1.0 - f1 / f1.max(), wx, wy)) ** 1.3
    k1, k2, kidx, _, krng = zellen(32, 1600, 1.0)
    kiesel = np.clip(1.0 - k1 / 2.6, 0, 1) ** 0.7 * (krng.random(kidx.max() + 1)[kidx] > 0.88)
    kruemel = norm01(rausch(33, 1.2, 40, 220))
    gross = norm01(rausch(34, 2.4, 1, 20))
    hoehe = norm01(klumpen * 0.45 + kiesel * 0.35 + kruemel * 0.15 + gross * 0.35)
    c = np.broadcast_to(ton(1.0, 1.0, 1.0), (N, N, 3)).copy()
    c *= (0.78 + 0.32 * hoehe)[..., None]
    c *= (0.92 + 0.16 * kruemel)[..., None]
    stein = krng.random(kidx.max() + 1)[kidx]
    kfarbe = mische(np.broadcast_to(ton(1.30, 1.28, 1.25), (N, N, 3)),
                    np.broadcast_to(ton(0.95, 0.92, 0.90), (N, N, 3)), stein)
    c = mische(c, kfarbe, np.clip(kiesel * 1.4, 0, 1))
    feucht = norm01(rausch(35, 2.4, 1, 12))
    c *= (0.82 + 0.30 * feucht)[..., None]
    c *= np.array([1.0, 0.98, 0.96])[None, None, :] + (gross[..., None] - 0.5) * np.array([0.06, 0.02, -0.04])
    return speichern("erde", c, hoehe, 4.0, 2.0, 3.0)


def sand():
    """Strand- und Wuestensand, Kachel ~6 m: Windrippel, feines Korn, vereinzelt Muscheln."""
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    wx = rausch(41, 2.8, 1, 8) * 9.0
    wy = rausch(42, 2.8, 1, 8) * 9.0
    phase = (xx * 0.6 + yy) / N * 2 * np.pi * 14 + wx * 0.35 + wy * 0.15
    # asymmetrisches Rippelprofil: flache Luvseite, steile Lee
    s = (phase / (2 * np.pi)) % 1.0
    rippel = np.where(s < 0.75, s / 0.75, (1.0 - s) / 0.25)
    rippel = weich(rippel, 1.2)
    staerke = np.clip(0.55 + 0.45 * rausch(43, 2.5, 1, 6), 0.1, 1.0)
    korn = rausch(44, 0.4, 60, 256)
    hoehe = norm01(rippel * staerke * 0.8 + korn * 0.05 + 0.3 * rausch(45, 3.0, 1, 10) * 0.2)
    c = np.broadcast_to(ton(1.0, 1.0, 1.0), (N, N, 3)).copy()
    c *= (0.88 + 0.24 * hoehe)[..., None]
    c *= (0.94 + 0.12 * norm01(korn))[..., None]
    dunkel = np.clip(rausch(46, 0.2, 80, 256) - 2.1, 0, 1)
    c *= (1.0 - 0.35 * dunkel)[..., None]
    return speichern("sand", c, hoehe, 3.0, 4.0, 2.0)


def fels():
    """Gestein fuer Waende UND Gipfelflaechen (triplanar), Kachel ~10 m. Zeilen = Hoehe: die
    Schichten laufen waagerecht. Erste Fassung (Zellen mit dunklen Fugen) sah aus wie
    Kopfsteinpflaster — jetzt: GESTUFTE SCHICHTEN (Simse und Absaetze, verbogen und
    unterbrochen), grosse KLUFTKOERPER aus verbogenen Zellen mit schraegen Flaechen,
    OFFENE Risse aus Graten eines Rauschfelds (keine geschlossenen Polygone),
    Verwitterung und vereinzelt Flechten."""
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    wx = rausch(59, 2.8, 1, 10) * 18.0
    wy = rausch(60, 2.8, 1, 10) * 6.0
    # Kluftkoerper: grosse verbogene Zellen, jede eine schraege Ebene
    f1, f2, idx, pts, rng = zellen(51, 30, 1.0)
    idx = np.rint(verbiegen(idx.astype(np.float64), wx, wy, 0)).astype(int) % (idx.max() + 1)
    neig = rng.normal(0, 1, (idx.max() + 1, 2)) * 0.006
    basis = rng.random(idx.max() + 1)
    p = pts[idx]
    ddx = (xx - p[..., 0] + N / 2) % N - N / 2
    ddy = (yy - p[..., 1] + N / 2) % N - N / 2
    platte = weich(basis[idx] * 0.6 + neig[idx, 0] * ddx + neig[idx, 1] * ddy, 1.0)
    # Gestufte Schichten: Treppenfunktion der (verbogenen) Hoehe
    lagen = 11.0
    z = (yy + wy * 2.0 + rausch(53, 3.0, 1, 5) * 14.0) / N * lagen
    stufe = np.floor(z) + np.clip((z - np.floor(z) - 0.82) / 0.18, 0, 1)   # steile Kante
    lage_id = np.floor(z).astype(int) % int(lagen)
    lage_ton = np.random.default_rng(54).random(int(lagen))[lage_id]
    stufe = stufe / lagen
    # Risse auf den KANTEN der Kluftkoerper, nur teilweise offen (ein Rauschen schaltet sie
    # ab). Erste Fassung: Nulllinien eines Rauschfelds — die sind zwangslaeufig geschlossene
    # Schleifen und lagen als Wuermer auf dem Stein.
    f1w = verbiegen(f1, wx, wy)
    f2w = verbiegen(f2, wx, wy)
    offen = np.clip(rausch(55, 2.4, 2, 24) * 1.2 + 0.3, 0, 1)
    riss = np.clip(1.0 - (f2w - f1w) / 2.2, 0, 1) ** 1.5 * offen
    # Feine Kluefte SENKRECHT (gestrecktes Rauschen) — richtungslos gaben sie Wurmlinien
    kl = weich(rausch(56, 1.8, 6, 90), (5.0, 0.6))
    kl = kl / (kl.std() + 1e-9)
    feinriss = np.clip(1.0 - np.abs(kl) / 0.07, 0, 1) ** 2 * np.clip(rausch(61, 2.0, 2, 20), 0, 1)
    rauh = rausch(57, 1.3, 6, 200) + 0.6 * np.clip(rausch(62, 0.8, 40, 256) - 1.2, 0, None)
    hoehe = norm01(platte * 0.45 + stufe * 0.55 - riss * 0.25 - feinriss * 0.08
                   + rauh * 0.025)
    c = np.broadcast_to(ton(1.0, 1.0, 1.0), (N, N, 3)).copy()
    c *= (0.84 + 0.26 * lage_ton)[..., None]               # Lagen unterschiedlich hell
    c *= (0.90 + 0.16 * basis[idx])[..., None]             # Kluftkoerper
    c = mische(c, np.broadcast_to(ton(1.06, 1.0, 0.92), (N, N, 3)),
               np.clip(lage_ton - 0.6, 0, 1) * 1.5)       # warme Baender
    c *= (1.0 - 0.45 * riss)[..., None]
    c *= (1.0 - 0.18 * feinriss)[..., None]
    c *= (0.93 + 0.10 * norm01(rauh))[..., None]
    # Unter jeder Stufe eine dunkle Spur (Wasser, Schatten der Kante)
    unter = np.clip(1.0 - (z - np.floor(z)) / 0.35, 0, 1) ** 2
    c *= (1.0 - 0.12 * unter)[..., None]
    # Flechten: wenige kleine Flecken
    fl = np.clip(rausch(58, 1.4, 20, 160) - 2.0, 0, 1)
    c = mische(c, np.broadcast_to(ton(1.20, 1.18, 0.90), (N, N, 3)), np.clip(fl * 2.0, 0, 1))
    return speichern("fels", c, hoehe, 7.0, 5.0, 3.0)


def schnee():
    """Schnee, Kachel ~8 m: weiche Verwehungen, Windgangeln, feines Korn; in den Mulden
    kuehler."""
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    weh = rausch(61, 3.2, 1, 12)
    gangeln = weich(rausch(62, 1.6, 6, 80), (0.6, 3.5))
    korn = rausch(63, 0.5, 80, 256)
    hoehe = norm01(weh * 0.7 + gangeln * 0.25 + korn * 0.02)
    c = np.broadcast_to(ton(1.0, 1.0, 1.0), (N, N, 3)).copy()
    kalt = 1.0 - hoehe
    c = mische(c, np.broadcast_to(ton(0.86, 0.92, 1.04), (N, N, 3)), np.clip(kalt * 0.8, 0, 1))
    c *= (0.96 + 0.06 * norm01(korn))[..., None]
    return speichern("schnee", c, hoehe, 2.5, 6.0, 1.5)


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
