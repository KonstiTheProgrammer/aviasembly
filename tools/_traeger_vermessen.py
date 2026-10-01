"""Vermisst einen Flugzeugtraeger aus einem Modellpaket und schreibt den Zahlensatz fuer
tools/build_traeger_modelle.py (tools/traeger_modelle.json).

Die Vorlagen sind fertige, texturierte Netze (200 000 bis 550 000 Flaechen). Uebernommen
wird davon NICHTS als Geometrie — nur Masse:
  1. Alle Flaechen werden flaechentreu abgetastet (ZUFAELLIG mit festem Keim, nicht
     "mindestens ein Punkt je Dreieck": Antennen und Reling bestehen aus sehr vielen sehr
     kleinen Dreiecken und zaehlten sonst wie massive Waende).
  2. Draufsicht-Raster 1 m: hoechster Punkt je Zelle und ob er auf einer waagerechten
     Flaeche liegt. Das FLUGDECK ist die groesste zusammenhaengende waagerechte Flaeche;
     sie waechst von der haeufigsten Hoehe aus ueber sanfte Stufen (Sprungschanze), aber
     nicht die Inselwand hinauf.
  3. RUMPF je Meter Laenge: Deckbreite, Deckhoehe und die Huelle der Bordwand in sechs
     Hoehen (2./98. Perzentil — einzelne Antennen ragen weit hinaus und sollen nicht zaehlen).
     Daraus bleiben so viele Spanten, wie fuer 0,3 m Abweichung noetig sind.
  4. AUFBAU: was mehr als 1,5 m ueber dem Deck steht, zerfaellt in zusammenhaengende
     Flecken. Grosse hohe Flecken (Insel) werden in Hoehenstufen geschnitten, jede Stufe
     wird zum Prisma ueber ihrer konvexen Huelle; kleine werden Kisten.
Farben und Deckmarkierung sind HANDARBEIT und stehen im Zahlensatz unter "farben", "linien",
"bahn", "start", "name" — diese Schluessel bleiben beim erneuten Vermessen erhalten.

    blender --background --factory-startup --python tools/_traeger_vermessen.py -- \
        <ausgabe-ordner> id=<pfad zur .blend> ...
Je Traeger entstehen dort <id>_oben.png (Vorlage von oben, 4 Bildpunkte je Meter, Mitte der
Laenge in Bildmitte — daraus liest man die Markierung ab) und <id>_vergleich_*.png
(schlichtes Modell neben der Vorlage).
"""
import bpy
import json
import math
import os
import sys

import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_traeger_modelle as bau  # noqa: E402

ZOLL = 0.0254
DICHTE = 10.0          # Abtastpunkte je Quadratmeter
STUFE = 1.5            # Hoehe einer Inselstufe
TOL = 0.35             # zulaessige Abweichung beim Ausduennen der Spanten
MAX_SPANTEN = 64
PX_JE_M = 4.0
HAND = ("farben", "linien", "bahn", "start", "name")


def abtasten(scene):
    """-> Punkte (n,3) in Metern, |nz| der Flaeche je Punkt."""
    rng = np.random.default_rng(7)
    P, N = [], []
    for o in scene.objects:
        if o.type != "MESH" or o.name.startswith(("flag", "propeller", "rudder")):
            continue
        me = o.data
        me.calc_loop_triangles()
        nt = len(me.loop_triangles)
        if nt == 0:
            continue
        co = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        M = np.array(o.matrix_world)
        co = (co @ M[:3, :3].T + M[:3, 3]) * ZOLL
        tri = np.empty(nt * 3, dtype=np.int64)
        me.loop_triangles.foreach_get("vertices", tri)
        tri = tri.reshape(-1, 3)
        a, b, c = co[tri[:, 0]], co[tri[:, 1]], co[tri[:, 2]]
        kreuz = np.cross(b - a, c - a)
        doppelt = np.linalg.norm(kreuz, axis=1)
        nz = np.abs(kreuz[:, 2]) / np.maximum(doppelt, 1e-12)
        n = np.floor(doppelt * 0.5 * DICHTE + rng.random(nt)).astype(np.int64)
        idx = np.repeat(np.arange(nt), n)
        if len(idx) == 0:
            continue
        r1 = np.sqrt(rng.random(len(idx)))[:, None]
        r2 = rng.random(len(idx))[:, None]
        P.append(a[idx] * (1.0 - r1) + b[idx] * (r1 * (1.0 - r2)) + c[idx] * (r1 * r2))
        N.append(nz[idx])
    return np.vstack(P), np.concatenate(N)


def _schieben(feld, dx, dy, leer):
    aus = np.full_like(feld, leer)
    nx, ny = feld.shape
    aus[max(dx, 0):nx + min(dx, 0), max(dy, 0):ny + min(dy, 0)] = \
        feld[max(-dx, 0):nx + min(-dx, 0), max(-dy, 0):ny + min(-dy, 0)]
    return aus


NACHBARN4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
NACHBARN8 = NACHBARN4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))


def _weiten(maske):
    aus = maske.copy()
    for dx, dy in NACHBARN8:
        aus |= _schieben(maske, dx, dy, False)
    return aus


def _schrumpfen(maske):
    aus = maske.copy()
    for dx, dy in NACHBARN8:
        aus &= _schieben(maske, dx, dy, False)
    return aus


def _flecken(maske):
    """Zusammenhaengende Flecken (8er-Nachbarschaft) -> Feld mit Nummern, 0 = leer."""
    nr = np.where(maske, np.arange(1, maske.size + 1).reshape(maske.shape), 0)
    while True:
        neu = nr.copy()
        for dx, dy in NACHBARN8:
            s = _schieben(nr, dx, dy, 0)
            neu = np.where(maske & (s > neu), s, neu)
        if (neu == nr).all():
            return nr
        nr = neu


def _huelle(punkte):
    """Konvexe Huelle (Andrew), gegen den Uhrzeigersinn."""
    pts = sorted(set(map(tuple, punkte)))
    if len(pts) < 3:
        return pts

    def halb(folge):
        h = []
        for p in folge:
            while len(h) >= 2 and ((h[-1][0] - h[-2][0]) * (p[1] - h[-2][1])
                                   - (h[-1][1] - h[-2][1]) * (p[0] - h[-2][0])) <= 0:
                h.pop()
            h.append(p)
        return h

    unten = halb(pts)
    oben = halb(reversed(pts))
    return unten[:-1] + oben[:-1]


def _ausduennen(poly, tol, hoechstens):
    """Ecken streichen, die am wenigsten Flaeche tragen, bis tol erreicht oder genug weg sind."""
    poly = list(poly)
    while len(poly) > 4:
        beste, wert = -1, 1e18
        for i in range(len(poly)):
            a, b, c = poly[i - 1], poly[i], poly[(i + 1) % len(poly)]
            lae = math.hypot(c[0] - a[0], c[1] - a[1])
            abst = abs((c[0] - a[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (c[1] - a[1])) / max(lae, 1e-9)
            if abst < wert:
                beste, wert = i, abst
        if wert > tol and len(poly) <= hoechstens:
            break
        poly.pop(beste)
    return poly


def _flaeche(poly):
    return abs(bau._flaeche(poly))


def _schwerpunkt(poly):
    return (sum(p[0] for p in poly) / len(poly), sum(p[1] for p in poly) / len(poly))


def vermesse(P, NZ):
    lo = P.min(axis=0) - 3.0
    nx = int(math.ceil(P[:, 0].max() - lo[0])) + 3
    ny = int(math.ceil(P[:, 1].max() - lo[1])) + 3
    ix = np.floor(P[:, 0] - lo[0]).astype(np.int64)
    iy = np.floor(P[:, 1] - lo[1]).astype(np.int64)
    zelle = ix * ny + iy
    # hoechster Punkt je Zelle samt seiner Flaechenneigung
    ordnung = np.lexsort((P[:, 2], zelle))
    zs, ps, ns = zelle[ordnung], P[ordnung, 2], NZ[ordnung]
    letzter = np.r_[zs[1:] != zs[:-1], True]
    H = np.full(nx * ny, -99.0)
    F = np.zeros(nx * ny)
    H[zs[letzter]] = ps[letzter]
    F[zs[letzter]] = ns[letzter]
    anz = np.bincount(zelle, minlength=nx * ny).reshape(nx, ny)
    H = H.reshape(nx, ny)
    flach = (F.reshape(nx, ny) > 0.9) & (anz >= 2)

    # --- Flugdeck ---------------------------------------------------------------------
    kand = H[flach & (H > 4.0)]
    hist, kanten = np.histogram(kand, bins=np.arange(4.0, kand.max() + 0.5, 0.25))
    zd = float(kanten[np.argmax(hist)] + 0.125)
    deck = flach & (np.abs(H - zd) < 0.35)
    while True:
        neu = deck.copy()
        for dx, dy in NACHBARN4:
            neu |= _schieben(deck, dx, dy, False) & flach & (np.abs(H - _schieben(H, dx, dy, -99.0)) < 0.45)
        if (neu == deck).all():
            break
        deck = neu
    # nur der groesste Fleck ist das Deck (Plattformen gleicher Hoehe an der Bordwand nicht)
    nr = _flecken(deck)
    werte, zahl = np.unique(nr[nr > 0], return_counts=True)
    deck = nr == werte[np.argmax(zahl)]
    # Die Insel steht AUF dem Deck: ihre Grundflaeche zaehlt zur Deckbreite, sonst endet das
    # Deck an der Inselwand und die Insel steht in einer Stufe daneben.
    hoch0 = (H > zd + 1.5) & (anz >= 2) & ~deck
    hoch0 = _weiten(_schrumpfen(hoch0)) & hoch0
    nr = _flecken(hoch0)
    deck_breit = deck.copy()
    for wert in np.unique(nr[nr > 0]):
        if (nr == wert).sum() >= 60:
            deck_breit |= nr == wert

    # --- je Meter Laenge --------------------------------------------------------------
    stat_ordnung = np.argsort(ix, kind="stable")
    grenzen = np.searchsorted(ix[stat_ordnung], np.arange(nx + 1))
    nk = 8
    R = np.full((nx, nk, 3), np.nan)
    hat_deck = np.zeros(nx, dtype=bool)
    gueltig = np.zeros(nx, dtype=bool)
    for i in range(nx):
        sel = stat_ordnung[grenzen[i]:grenzen[i + 1]]
        if len(sel) < 40:
            continue
        y = P[sel, 1]
        z = P[sel, 2]
        dz = np.nonzero(deck[i])[0]
        if len(dz) >= 4:
            hat_deck[i] = True
            zt = float(np.median(H[i, dz]))
            db = np.nonzero(deck_breit[i])[0]
            y0, y1 = lo[1] + db.min(), lo[1] + db.max() + 1.0
        else:
            fl = np.nonzero(flach[i] & (H[i] > 2.0))[0]
            zt = float(np.median(H[i, fl])) if len(fl) >= 3 else float(np.percentile(z, 70))
            zt = min(zt, zd + 0.5)
            y0 = y1 = np.nan
        unter = z <= zt + 0.3
        if unter.sum() < 30:
            continue
        zb = max(-2.0, float(np.percentile(z[unter], 2)))
        oben = zt - 1.0
        if zb > oben - 0.5:
            zb = oben - 0.5
        z1 = min(max(0.8, zb), oben)
        stufen = [zb, z1] + [z1 + (oben - z1) * f for f in (0.25, 0.5, 0.75, 1.0)]
        for k, zk in enumerate(stufen):
            band = (z > zk - 0.55) & (z < zk + 0.55) if k < 5 else (z > zk - 0.8) & (z < zk + 0.2)
            if band.sum() >= 8:
                R[i, k] = (np.percentile(y[band], 2), np.percentile(y[band], 98), zk)
            else:
                R[i, k, 2] = zk
        if np.isnan(R[i, :6, 0]).all():
            continue
        # Luecken in der Hoehe aus der naechsten gemessenen Stufe fuellen
        for k in range(6):
            if np.isnan(R[i, k, 0]):
                nah = min((j for j in range(6) if not np.isnan(R[i, j, 0])), key=lambda j: abs(j - k))
                R[i, k, :2] = R[i, nah, :2]
        if not hat_deck[i]:
            y0, y1 = R[i, 5, 0], R[i, 5, 1]
        R[i, 6] = (y0, y1, oben)
        R[i, 7] = (y0, y1, zt)
        gueltig[i] = True

    # ENDEN: ein Spant zaehlt nur, wenn er die Schiffsmitte ueberdeckt. Am Heck der
    # Forrestal ragt ein drei Meter breiter Ausleger hinaus — als "Rumpf" gelesen wurde
    # daraus ein Dorn am Heck.
    quer = R[gueltig][:, 1, :2]
    mitte_roh = float(np.median(0.5 * (quer[:, 0] + quer[:, 1])))
    mittig = gueltig & (R[:, 7, 0] < mitte_roh - 1.0) & (R[:, 7, 1] > mitte_roh + 1.0)
    bereich = np.nonzero(mittig)[0]
    i0, i1 = bereich.min(), bereich.max()
    # einzelne ungueltige Meter dazwischen aus den Nachbarn
    for i in range(i0, i1 + 1):
        if not gueltig[i]:
            R[i] = R[i - 1]
            hat_deck[i] = hat_deck[i - 1]
    R = R[i0:i1 + 1]
    hat_deck = hat_deck[i0:i1 + 1]
    n = len(R)
    # DECKKANTE SCHLIESSEN: heruntergefahrene Aufzuege und der Winkel am Heck sind
    # Einschnitte von 15 m Laenge. Erst nach aussen weiten, dann zurueck — Buchten bis
    # 18 m verschwinden, die Kante selbst bleibt, wo sie ist.
    def schliessen(werte, nach_aussen):
        h = 9
        rand = np.pad(werte, (h, h), mode="edge")
        stapel = np.stack([rand[j:j + len(werte)] for j in range(2 * h + 1)])
        weit = stapel.min(axis=0) if nach_aussen < 0 else stapel.max(axis=0)
        rand = np.pad(weit, (h, h), mode="edge")
        stapel = np.stack([rand[j:j + len(werte)] for j in range(2 * h + 1)])
        return stapel.max(axis=0) if nach_aussen < 0 else stapel.min(axis=0)

    a = 0
    for i in range(1, n + 1):
        if i == n or hat_deck[i] != hat_deck[a]:
            if hat_deck[a] and i - a >= 3:
                for k in (6, 7):
                    R[a:i, k, 0] = schliessen(R[a:i, k, 0], -1)
                    R[a:i, k, 1] = schliessen(R[a:i, k, 1], 1)
            a = i

    # GLAETTEN je Abschnitt gleicher Art (Deck / kein Deck): Median ueber sieben Meter nimmt
    # Beiboote, Kraene und Gefechtsstaende heraus, die Mittelung danach die Treppchen des
    # Meterrasters. Ohne das standen an den Bordwaenden Zacken und Splitter.
    def glatt(feld, fenster):
        h = fenster // 2
        rand = np.pad(feld, [(h, h)] + [(0, 0)] * (feld.ndim - 1), mode="edge")
        med = np.median(np.stack([rand[j:j + len(feld)] for j in range(fenster)]), axis=0)
        rand = np.pad(med, [(1, 1)] + [(0, 0)] * (feld.ndim - 1), mode="edge")
        return (rand[:-2] + rand[1:-1] + rand[2:]) / 3.0

    a = 0
    for i in range(1, n + 1):
        if i == n or hat_deck[i] != hat_deck[a]:
            if i - a >= 3:
                R[a:i] = glatt(R[a:i], 7 if i - a >= 7 else 3)
            a = i
    # Die Bordwand wird nach oben nie schmaler: Bootsnischen und Hangaroeffnungen sind
    # Einschnitte, die ein Modell aus 60 Spanten nur als Dellen wiedergeben kann.
    for k in range(2, 6):
        R[:, k, 0] = np.minimum(R[:, k, 0], R[:, k - 1, 0])
        R[:, k, 1] = np.maximum(R[:, k, 1], R[:, k - 1, 1])
    for k in range(1, nk):
        R[:, k, 2] = np.maximum(R[:, k, 2], R[:, k - 1, 2])
    xm = lo[0] + i0 + 0.5 + np.arange(n)
    mitte_x = 0.5 * (xm[0] + xm[-1])
    mitte_y = float(np.median(0.5 * (R[:, 1, 0] + R[:, 1, 1])))

    # --- Spanten ausduennen -----------------------------------------------------------
    kurven = R.reshape(n, -1)
    gewaehlt = [0, n - 1]
    for i in range(1, n):
        if hat_deck[i] != hat_deck[i - 1]:
            gewaehlt += [i - 1, i]
    gewaehlt = sorted(set(gewaehlt))
    while len(gewaehlt) < MAX_SPANTEN:
        naeh = np.stack([np.interp(np.arange(n), gewaehlt, kurven[gewaehlt, j]) for j in range(kurven.shape[1])],
                        axis=1)
        fehler = np.abs(naeh - kurven).max(axis=1)
        j = int(np.argmax(fehler))
        if fehler[j] < TOL:
            break
        gewaehlt = sorted(set(gewaehlt + [j]))

    spec = {
        "laenge": round(float(xm[-1] - xm[0] + 1.0), 2),
        "stationen": [round(float(xm[i] - mitte_x), 2) for i in gewaehlt],
        "ringe": [[[round(float(R[i, k, 0] - mitte_y), 2), round(float(R[i, k, 1] - mitte_y), 2),
                    round(float(R[i, k, 2]), 2)] for k in range(nk)] for i in gewaehlt],
        "deck": [int(hat_deck[i]) for i in gewaehlt],
    }
    # Bug und Heck enden nicht auf der Zellmitte, sondern am Rand der Zelle
    spec["stationen"][0] = round(spec["stationen"][0] - 0.5, 2)
    spec["stationen"][-1] = round(spec["stationen"][-1] + 0.5, 2)

    # --- Aufbau -----------------------------------------------------------------------
    zt_stat = np.full(nx, 1e9)                     # ausserhalb des Rumpfs steht nichts
    zt_stat[i0:i1 + 1] = R[:, 7, 2]
    hoch = (H > zt_stat[:, None] + 1.5) & (anz >= 2) & ~deck
    nr = _flecken(_weiten(hoch))
    nr = np.where(hoch, nr, 0)

    def welt(cx, cy):
        return (round(float(lo[0] + cx - mitte_x), 2), round(float(lo[1] + cy - mitte_y), 2))

    def umriss(maske):
        zx, zy = np.nonzero(maske)
        ecken = np.concatenate([np.stack([zx + a, zy + b], axis=1) for a in (0, 1) for b in (0, 1)])
        return [welt(p[0], p[1]) for p in _ausduennen(_huelle(ecken), 0.6, 10)]

    aufbau, masten, kisten = [], [], []
    for wert in np.unique(nr[nr > 0]):
        fleck = nr == wert
        hoehe = H[fleck] - zd
        flaeche = int(fleck.sum())
        if flaeche >= 60 and np.percentile(hoehe, 98) >= 9.0:
            offen = []                                 # [poly, z0, z1] der wachsenden Prismen
            k = 0
            spitze = 0.0
            while True:
                stufe = fleck & (H - zd >= k * STUFE + STUFE * 0.5)
                fest = _weiten(_schrumpfen(stufe)) & stufe
                if not fest.any():
                    break
                teil_nr = _flecken(fest)
                for tw in np.unique(teil_nr[teil_nr > 0]):
                    teil = teil_nr == tw
                    if teil.sum() < 6:
                        continue
                    poly = umriss(teil)
                    z0 = zd + k * STUFE - (0.4 if k == 0 else 0.0)
                    z1 = zd + (k + 1) * STUFE
                    spitze = max(spitze, z1)
                    for o in offen:
                        gleich = (abs(o[2] - z0) < 0.01 and 0.88 < _flaeche(poly) / max(_flaeche(o[0]), 1e-6) < 1.14
                                  and math.dist(_schwerpunkt(poly), _schwerpunkt(o[0])) < 0.8)
                        if gleich:
                            o[2] = z1
                            break
                    else:
                        offen.append([poly, z0, z1])
                k += 1
            for poly, z0, z1 in offen:
                aufbau.append({"poly": [list(p) for p in poly], "z0": round(z0, 2), "z1": round(z1, 2)})
            gipfel = float(np.percentile(H[fleck], 99.5))
            if gipfel > spitze + 4.0:
                oben = fleck & (H > spitze + 0.6 * (gipfel - spitze))
                zx, zy = np.nonzero(oben if oben.any() else fleck)
                mx, my = welt(float(np.median(zx)) + 0.5, float(np.median(zy)) + 0.5)
                masten.append({"x": mx, "y": my, "z0": round(spitze - 1.0, 2), "z1": round(gipfel, 2)})
        elif flaeche >= 5 and np.percentile(hoehe, 80) >= 1.6:
            zx, zy = np.nonzero(fleck)
            a = welt(zx.min(), zy.min())
            b = welt(zx.max() + 1, zy.max() + 1)
            st = int(np.median(zx)) - i0
            my = lo[1] + 0.5 * (zy.min() + zy.max() + 1)
            if not (0 <= st < n and R[st, 7, 0] + 1.0 < my < R[st, 7, 1] - 1.0):
                continue                                # haengt aussenbords: steckt in der Bordwand
            unten = float(zt_stat[int(np.median(zx))]) - 0.3
            kisten.append([a[0], b[0], a[1], b[1], round(unten, 2), round(zd + float(np.percentile(hoehe, 80)), 2)])
    kisten.sort(key=lambda k: -(k[1] - k[0]) * (k[3] - k[2]) * (k[5] - k[4]))
    spec["aufbau"] = aufbau
    spec["masten"] = masten
    spec["kisten"] = kisten[:36]
    return spec, (mitte_x, mitte_y), zd


def vergleich(scene, ziel, tid, spec, mitte):
    """Schlichtes Modell neben die Vorlage stellen (deren Einheiten) und rendern."""
    netz = bau.baue_netz(spec)
    breite = max(r[7][1] - r[7][0] for r in spec["ringe"])
    versatz = breite * 1.25
    punkte = [((v.x + mitte[0]) / ZOLL, (v.y + mitte[1] + versatz) / ZOLL, v.z / ZOLL) for v in netz.verts]
    me = bau.mesh_anlegen("schlicht_" + tid, punkte, netz, spec)
    obj = bpy.data.objects.new("schlicht_" + tid, me)
    scene.collection.objects.link(obj)
    welt = bpy.data.worlds.new("w")
    welt.color = (0.10, 0.16, 0.22)
    scene.world = welt
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_cavity = True
    scene.display.render_aa = "8"
    scene.render.image_settings.file_format = "PNG"
    kd = bpy.data.cameras.new("k")
    kd.type = "ORTHO"
    lae = spec["laenge"] / ZOLL
    kd.clip_start = 1.0
    kd.clip_end = lae * 30
    kam = bpy.data.objects.new("k", kd)
    scene.collection.objects.link(kam)
    scene.camera = kam
    m = Vector((mitte[0] / ZOLL, (mitte[1] + versatz * 0.5) / ZOLL, 10.0 / ZOLL))
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 900
    for tag, richt, skala, oben in (("bug", Vector((0.60, -0.62, 0.50)), 1.10, "Z"),
                                    ("heck", Vector((-0.62, 0.55, 0.42)), 1.10, "Z"),
                                    ("oben", Vector((0.0, 0.0, 1.0)), 1.04, "Y")):
        kd.ortho_scale = lae * skala
        kam.location = m + richt.normalized() * lae * 5
        kam.rotation_euler = (m - kam.location).to_track_quat("-Z", oben).to_euler()
        scene.render.filepath = os.path.join(ziel, "%s_vergleich_%s.png" % (tid, tag))
        bpy.ops.render.render(write_still=True)
    # Vorlage allein von oben, massstaeblich: daraus liest man die Deckmarkierung ab.
    obj.hide_render = True
    lae_m = spec["laenge"] + 20.0
    scene.render.resolution_x = int(lae_m * PX_JE_M)
    scene.render.resolution_y = int(110.0 * PX_JE_M)
    kd.ortho_scale = lae_m / ZOLL
    m = Vector((mitte[0] / ZOLL, mitte[1] / ZOLL, 0.0))
    kam.location = m + Vector((0, 0, lae * 5))
    kam.rotation_euler = (m - kam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(ziel, "%s_oben.png" % tid)
    bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    ziel = os.path.abspath(args[0])
    os.makedirs(ziel, exist_ok=True)
    specs = {}
    if os.path.exists(bau.SPEC):
        with open(bau.SPEC, encoding="utf-8") as fh:
            specs = json.load(fh)
    for eintrag in args[1:]:
        tid, pfad = eintrag.split("=", 1)
        bpy.ops.wm.open_mainfile(filepath=pfad)
        scene = bpy.context.scene
        P, NZ = abtasten(scene)
        spec, mitte, zd = vermesse(P, NZ)
        alt = specs.get(tid, {})
        for schluessel in HAND:
            if schluessel in alt:
                spec[schluessel] = alt[schluessel]
        specs[tid] = spec
        print("VERMESSEN %s: %d Punkte, Laenge %.1f m, Deck %.2f m, %d Spanten, %d Prismen, %d Masten, %d Kisten"
              % (tid, len(P), spec["laenge"], zd, len(spec["stationen"]), len(spec["aufbau"]),
                 len(spec["masten"]), len(spec["kisten"])))
        vergleich(scene, ziel, tid, spec, mitte)
    with open(bau.SPEC, "w", encoding="utf-8", newline="\n") as fh:
        # ein Traeger je Zeile: bleibt im Diff lesbar, ohne 4000 Zeilen Zahlen zu werden
        zeilen = ['"%s":%s' % (k, json.dumps(specs[k], separators=(",", ":"), sort_keys=True))
                  for k in sorted(specs)]
        fh.write("{\n" + ",\n".join(zeilen) + "\n}\n")


if __name__ == "__main__":
    main()
