"""Vermisst Vorlagen aus einem Waffenpaket und schreibt daraus die Zahlensaetze fuer
tools/build_waffen_modelle.py (tools/waffen_modelle.json).

Die Vorlagen sind fertige, texturierte Netze (10 000+ Dreiecke). Uebernommen wird davon
NICHTS als Geometrie — nur Masse:
  1. Jede Flaeche wird dicht abgetastet (Punkt + Farbe aus der Textur + "ist Glas").
  2. Laengsachse = Mitte der Huelle je Station (Median ueber alle Stationen — einzelne
     Aufhaengungen verschieben ihn nicht).
  3. Rumpfradius je Station = 40. Perzentil der groessten Radien ueber 72 Winkelsektoren.
     Flossen belegen nur wenige Sektoren und fallen heraus.
  4. Was deutlich ueber dem Rumpf liegt, wird nach WINKEL gebuendelt (Flossenebenen) und
     je Ebene nach Stationen getrennt (Canard vorn, Ruder hinten). Je Teil entsteht ein
     Umriss aus oberer und unterer Huellkurve.
  5. Farben: Median je Station, zu hoechstens sechs Flaechenfarben zusammengefasst; die
     haeufigste wird `body`.
Zum Pruefen stellt das Skript das schlichte Modell NEBEN die Vorlage und rendert beide.

    blender --background --factory-startup --python tools/_waffen_vermessen.py -- \
        <paket-ordner> <ausgabe-ordner> id=vorlagenname[:duese] ...
Vorhandene Eintraege in waffen_modelle.json mit "hand": true werden NICHT ueberschrieben.
"""
import bpy
import json
import math
import os
import sys

import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_waffen_modelle as bau  # noqa: E402

NB = 240            # Stationen entlang der Laenge
NS = 72             # Winkelsektoren fuer den Rumpfradius


def finde(paket, name):
    for kat in sorted(os.listdir(paket)):
        p = os.path.join(paket, kat)
        if not os.path.isdir(p):
            continue
        for d in os.listdir(p):
            if d.split(" [")[0] == name:
                # KEIN glob: die Ordner heissen "... [1989]", und [] ist dort ein Zeichensatz.
                bl = [f for f in os.listdir(os.path.join(p, d)) if f.endswith(".blend")]
                return os.path.join(p, d, bl[0]) if bl else None
    return None


def _bild(mat):
    """Farbtextur eines Materials als (h, w, 3)-Feld oder None."""
    if mat is None or not mat.use_nodes:
        return None
    kandidaten = [n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]
    wahl = None
    for img in kandidaten:
        n = img.name.lower()
        if n.endswith("_n.dds") or "_n." in n:
            continue
        wahl = img
        break
    # NICHT auf has_data pruefen: das ist False, bis jemand die Pixel wirklich liest.
    if wahl is None or wahl.size[0] == 0:
        return None
    w, h = wahl.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    wahl.pixels.foreach_get(buf)
    return buf.reshape(h, w, 4)[:, :, :3]


def abtasten(scene):
    """Alle Netze der Szene -> Punkte (n,3), Farbe (n,3), Glas (n,)."""
    P, C, G = [], [], []
    alle = [o for o in scene.objects if o.type == "MESH" and not o.name.startswith("flare")]
    lo = np.full(3, 1e18)
    hi = np.full(3, -1e18)
    netze = []
    for o in alle:
        me = o.data
        me.calc_loop_triangles()
        nv = len(me.vertices)
        co = np.empty(nv * 3)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        M = np.array(o.matrix_world)
        co = co @ M[:3, :3].T + M[:3, 3]
        lo = np.minimum(lo, co.min(axis=0))
        hi = np.maximum(hi, co.max(axis=0))
        netze.append((o, me, co))
    schritt = float(hi[0] - lo[0]) / 320.0
    gitter = {}
    for o, me, co in netze:
        nt = len(me.loop_triangles)
        tri = np.empty(nt * 3, dtype=np.int64)
        me.loop_triangles.foreach_get("vertices", tri)
        tri = tri.reshape(-1, 3)
        tl = np.empty(nt * 3, dtype=np.int64)
        me.loop_triangles.foreach_get("loops", tl)
        tl = tl.reshape(-1, 3)
        tm = np.empty(nt, dtype=np.int64)
        me.loop_triangles.foreach_get("material_index", tm)
        uv = None
        if me.uv_layers.active is not None:
            uv = np.empty(len(me.loops) * 2)
            me.uv_layers.active.data.foreach_get("uv", uv)
            uv = uv.reshape(-1, 2)
        mats = []
        for m in me.materials:
            name = (m.name if m else "").lower()
            mats.append(("glass" in name, _bild(m)))
        if not mats:
            mats = [(False, None)]
        a, b, c = co[tri[:, 0]], co[tri[:, 1]], co[tri[:, 2]]
        nu = np.clip(np.ceil(np.linalg.norm(b - a, axis=1) / schritt), 1, 300).astype(int)
        nw = np.clip(np.ceil(np.linalg.norm(c - a, axis=1) / schritt), 1, 300).astype(int)
        for i in range(nt):
            key = (int(nu[i]), int(nw[i]))
            g = gitter.get(key)
            if g is None:
                uu, ww = np.meshgrid(np.arange(key[0] + 1) / key[0], np.arange(key[1] + 1) / key[1])
                ok = (uu + ww) <= 1.0 + 1e-9
                g = np.stack([uu[ok], ww[ok]], axis=1)
                g = np.vstack([g, [[1.0 / 3.0, 1.0 / 3.0]]])
                gitter[key] = g
            u, w = g[:, 0:1], g[:, 1:2]
            pts = a[i] + u * (b[i] - a[i]) + w * (c[i] - a[i])
            glas, bild = mats[min(int(tm[i]), len(mats) - 1)]
            if bild is not None and uv is not None:
                t0, t1, t2 = uv[tl[i, 0]], uv[tl[i, 1]], uv[tl[i, 2]]
                tt = t0 + u * (t1 - t0) + w * (t2 - t0)
                h, wd = bild.shape[0], bild.shape[1]
                px = np.floor(tt[:, 0] * wd).astype(int) % wd
                py = np.floor(tt[:, 1] * h).astype(int) % h
                col = bild[py, px]
            else:
                col = np.full((len(pts), 3), 0.5, dtype=np.float32)
            P.append(pts)
            C.append(col)
            G.append(np.full(len(pts), glas))
    return np.vstack(P), np.vstack(C), np.concatenate(G)


def _dp(pts, tol):
    """Douglas-Peucker auf [(x, y)]."""
    if len(pts) < 3:
        return list(pts)
    a, b = np.array(pts[0], float), np.array(pts[-1], float)
    ab = b - a
    n = np.linalg.norm(ab)
    best, wo = -1.0, -1
    for i in range(1, len(pts) - 1):
        p = np.array(pts[i], float) - a
        d = abs(ab[0] * p[1] - ab[1] * p[0]) / n if n > 1e-9 else np.linalg.norm(p)
        if d > best:
            best, wo = d, i
    if best <= tol:
        return [pts[0], pts[-1]]
    return _dp(pts[:wo + 1], tol)[:-1] + _dp(pts[wo:], tol)


def _merkmal(c):
    """Farbe -> Vergleichsraum: Helligkeit zaehlt halb, Farbton voll. Die Texturen tragen
    eingebackenen Schmutz und Schatten; ohne die Abwertung zerfiel ein weisser Rumpf in
    fuenf Grautoene und das Profil in 47 Baender."""
    c = np.asarray(c, dtype=float)
    hell = c.mean(axis=-1, keepdims=True)
    return np.concatenate([0.5 * hell, c - hell], axis=-1)


def _palette(farben, gewicht, kmax=5, nah=0.085, klein=0.012):
    """Fasst Stationsfarben zu wenigen Flaechenfarben zusammen. -> (Farben, Label, Anteil)."""
    F = _merkmal(farben)
    gilt = gewicht > 0
    idx = [int(np.argmax(gewicht))]
    for _ in range(kmax - 1):
        d = np.min(np.linalg.norm(F[:, None, :] - F[idx][None, :, :], axis=2), axis=1)
        idx.append(int(np.argmax(d * gilt)))
    zen = F[idx].copy()
    for _ in range(12):
        lab = np.argmin(np.linalg.norm(F[:, None, :] - zen[None, :, :], axis=2), axis=1)
        for k in range(len(zen)):
            m = (lab == k) & gilt
            if m.any():
                zen[k] = np.median(F[m], axis=0)
    aktiv = list(range(len(zen)))
    while True:
        lab = np.array(aktiv)[np.argmin(np.linalg.norm(F[:, None, :] - zen[aktiv][None, :, :], axis=2), axis=1)]
        anteil = {k: float(gewicht[lab == k].sum()) / max(float(gewicht.sum()), 1e-9) for k in aktiv}
        raus = None
        for i in aktiv:
            for j in aktiv:
                if i < j and np.linalg.norm(zen[i] - zen[j]) < nah:
                    raus = i if anteil[i] < anteil[j] else j
        if raus is None:
            kl = [k for k in aktiv if anteil[k] < klein]
            if kl and len(aktiv) > 1:
                raus = min(kl, key=lambda k: anteil[k])
        if raus is None:
            break
        aktiv.remove(raus)
    haupt = max(anteil, key=lambda k: anteil[k])
    rgb = {}
    for k in aktiv:
        m = (lab == k) & gilt
        if not m.any():
            rgb[k] = np.array([0.5, 0.5, 0.5])
            continue
        if k != haupt:
            # Ein schmales Band liegt nur mit der Mitte ganz in einer Station; die Raender
            # sind mit der Rumpffarbe verschnitten. Die reinere Haelfte nehmen.
            ab = np.linalg.norm(F[m] - zen[haupt], axis=1)
            wahl = ab >= np.median(ab)
            rgb[k] = np.median(farben[m][wahl], axis=0)
        else:
            rgb[k] = np.median(farben[m], axis=0)
    return rgb, lab, anteil


def _hex(c):
    return "#%02x%02x%02x" % tuple(int(round(max(0.0, min(1.0, float(v))) * 255)) for v in c)


def _komponenten(occ):
    """Zusammenhaengende Felder im Raster Station x Winkel (Winkel laeuft rundum)."""
    nb, ng = occ.shape
    lab = -np.ones(occ.shape, dtype=int)
    comps = []
    for b0, g0 in zip(*np.nonzero(occ)):
        if lab[b0, g0] >= 0:
            continue
        cid = len(comps)
        stapel = [(int(b0), int(g0))]
        lab[b0, g0] = cid
        zellen = []
        while stapel:
            bb, gg = stapel.pop()
            zellen.append((bb, gg))
            for db in (-1, 0, 1):
                for dg in (-1, 0, 1):
                    n1, n2 = bb + db, (gg + dg) % ng
                    if 0 <= n1 < nb and occ[n1, n2] and lab[n1, n2] < 0:
                        lab[n1, n2] = cid
                        stapel.append((n1, n2))
        comps.append(zellen)
    return lab, comps


def vermesse(P, C, G, duese):
    X = P[:, 0]
    xmin, xmax = float(X.min()), float(X.max())
    L = xmax - xmin
    bw = L / NB
    b = np.clip(((X - xmin) / L * NB).astype(int), 0, NB - 1)
    xc = xmin + (np.arange(NB) + 0.5) * bw

    # --- Laengsachse ---
    ymx = np.full(NB, -1e18); np.maximum.at(ymx, b, P[:, 1])
    ymn = np.full(NB, 1e18); np.minimum.at(ymn, b, P[:, 1])
    zmx = np.full(NB, -1e18); np.maximum.at(zmx, b, P[:, 2])
    zmn = np.full(NB, 1e18); np.minimum.at(zmn, b, P[:, 2])
    voll = ymx > -1e17
    yc = float(np.median(0.5 * (ymx + ymn)[voll]))
    zc = float(np.median(0.5 * (zmx + zmn)[voll]))
    y, z = P[:, 1] - yc, P[:, 2] - zc
    r = np.hypot(y, z)
    th = np.arctan2(z, y)

    # --- Rumpfradius je Station ---
    s = (np.floor((th + math.pi) / math.tau * NS).astype(int)) % NS
    env = np.zeros((NB, NS))
    np.maximum.at(env, (b, s), r)
    rumpf = np.full(NB, np.nan)
    for i in range(NB):
        hat = env[i] > 0
        if hat.sum() >= NS * 0.5:
            rumpf[i] = np.percentile(env[i][hat], 40)
    gut = ~np.isnan(rumpf)
    erst, letzt = int(np.argmax(gut)), int(NB - 1 - np.argmax(gut[::-1]))
    # Luecken IM Rumpf interpolieren; vor/hinter dem Rumpf (nur Flossen) bleibt 0.
    innen = np.arange(erst, letzt + 1)
    rumpf[innen] = np.interp(xc[innen], xc[gut], rumpf[gut])
    rumpf[:erst] = 0.0
    rumpf[letzt + 1:] = 0.0

    # --- Heckmantel: Ring oder Kasten um das Leitwerk -------------------------------------
    # Ein Mantel belegt alle Winkel und waere damit "Rumpf" — als massive Trommel. Erkennbar
    # ist er daran, dass der Radius am Heck gross ist, kurz davor abrupt klein wird UND
    # innen noch etwas liegt (der Heckkonus). Der Mantel wird ein eigenes, hohles Bauteil;
    # sein Querschnitt wird in NM Richtungen gemessen, damit Ring, Kasten und alles
    # dazwischen (vier Boegen zwischen den Flossen) denselben Weg gehen.
    NM = 24
    schale = np.zeros(len(X), dtype=bool)
    mantel = None
    ende, hoechst = None, 0.0
    for k in range(erst, min(erst + int(0.35 * NB), letzt - 3)):
        hoechst = max(hoechst, float(rumpf[k]))
        if k > erst + 1 and rumpf[k] < 0.60 * hoechst:
            ende = k
            break
    if ende is not None:
        D = np.array([i for i in range(erst, ende) if rumpf[i] >= 0.60 * hoechst])
        imD = (b >= D[0]) & (b <= D[-1])
        je_sektor = np.median(env[D], axis=0)                 # Mantelradius je 5-Grad-Sektor
        schale = imD & (r >= 0.94 * je_sektor[s])
        emin = np.full((NB, NS), np.inf)
        m = imD & (~schale)
        np.minimum.at(emin, (b[m], s[m]), r[m])
        innen_r = np.zeros(NB)
        for i in D:
            # "Innen" heisst DEUTLICH innerhalb der Wand. Sonst zaehlen Reste der Wand und
            # Flossen, die nur aussen stehen, als Rumpf — der Kasten der AN-M64 ist hinten
            # ganz hohl, galt aber als gefuellt.
            f = emin[i] < 0.75 * je_sektor
            if f.sum() >= NS * 0.30:
                innen_r[i] = np.percentile(emin[i][f], 25)
        if schale.any() and float(np.median(innen_r[D])) < 0.70 * hoechst:
            rumpf[D] = innen_r[D]
            # Median ueber +-10 Grad: eine Flosse, die durch den Mantel ragt, belegt nur ein,
            # zwei Sektoren und darf ihn nicht zum Stern machen. (Kostet an Kastenecken 4 %.)
            radien = []
            for j in range(NM):
                sek = int(round((math.radians(j * 360.0 / NM) + math.pi) / math.tau * NS)) % NS
                radien.append(float(np.median([je_sektor[(sek + q) % NS] for q in (-2, -1, 0, 1, 2)])))
            xs_sch = X[schale]
            mantel = {"x0": float(xs_sch.min()), "x1": float(xs_sch.max()), "radien": radien,
                      "farbe": [float(v) for v in np.median(C[schale], axis=0)]}
            erst = int(np.nonzero(rumpf > 0)[0][0])
        else:
            schale[:] = False

    rmax = float(rumpf.max())
    x_heck = xmin + erst * bw
    x_nase = xmin + (letzt + 1) * bw

    # --- alles deutlich ueber dem Rumpf: Felder im Raster Station x Winkel ---------------
    # Frueher wurde nur nach WINKEL gebuendelt. Eine Schelle, die rundum laeuft, belegt dann
    # jeden Winkel, und alle Flossen der Waffe verschmolzen zu einem einzigen Klotz.
    NG = 180
    g = (np.floor((np.degrees(th) + 360.0) / 2.0).astype(int)) % NG
    for durchgang in range(3):
        rb = np.maximum(np.interp(X, xc, rumpf), rumpf[b])
        rand = rb * 1.07 + 0.30 * bw + 0.02 * rmax + 0.05
        ueber = (r > rand) & (~schale)
        zahl = np.zeros((NB, NG), dtype=int)
        np.add.at(zahl, (b[ueber], g[ueber]), 1)
        lab, comps = _komponenten(zahl >= 2)
        # Baender (Schellen, Wuelste) laufen fast rundum: die gehoeren in das PROFIL.
        angehoben = False
        for zellen in comps:
            je = {}
            for bb, gg in zellen:
                je[bb] = je.get(bb, 0) + 1
            for bb, anz in je.items():
                if anz >= 75 and rumpf[bb] > 0:
                    hoch = env[bb][env[bb] > rumpf[bb] * 1.05]
                    if len(hoch):
                        rumpf[bb] = max(rumpf[bb], float(np.percentile(hoch, 40)))
                        angehoben = True
        if not angehoben or durchgang == 2:
            break
    rmax = float(rumpf.max())

    teile = []
    idx_ueber = np.nonzero(ueber)[0]
    comp_von = lab[b[idx_ueber], g[idx_ueber]]
    for cid, zellen in enumerate(comps):
        sel = idx_ueber[comp_von == cid]
        if len(sel) < 30:
            continue
        gew = r[sel] - rb[sel]
        wmit = math.atan2(float((np.sin(th[sel]) * gew).sum()), float((np.cos(th[sel]) * gew).sum()))
        dth = th[sel] - wmit
        u = r[sel] * np.cos(dth)
        w = r[sel] * np.sin(dth)
        i0 = min(zz[0] for zz in zellen)
        i1 = max(zz[0] for zz in zellen)
        teil = _teil(X[sel], u, w, b[sel], rb[sel], rand[sel], C[sel],
                     i0, i1, xc, bw, rmax, L, math.degrees(wmit))
        if teil is not None:
            teile.append(teil)

    # --- Profil ---
    pts = [(x_heck, float(rumpf[erst]))]
    for i in range(erst, letzt + 1):
        pts.append((float(xc[i]), float(rumpf[i])))
    pts.append((x_nase, float(rumpf[letzt]) * 0.5))
    tol = 0.018 * rmax
    prof = _dp(pts, tol)
    while len(prof) > 18:
        tol *= 1.3
        prof = _dp(pts, tol)

    # --- Farben je Station ---
    haut = (~ueber) & (~schale) & (r > 0.80 * rb)
    farbe = np.zeros((NB, 3))
    gewicht = np.zeros(NB)
    glas = np.zeros(NB)
    for i in range(erst, letzt + 1):
        m = haut & (b == i)
        if m.sum() >= 3:
            glas[i] = float(G[m].mean())
            ohne = m & (~G)
            if glas[i] <= 0.5 and ohne.sum() >= 3:      # Glas traegt keine Textur
                farbe[i] = np.median(C[ohne], axis=0)
                gewicht[i] = 1.0
    zen, lab_f, anteil = _palette(farbe, gewicht)
    # Stationen ohne Farbprobe uebernehmen die Farbe der naechsten gueltigen
    gueltig = np.where(gewicht > 0)[0]
    for i in range(NB):
        if gewicht[i] == 0 and len(gueltig):
            lab_f[i] = lab_f[gueltig[int(np.argmin(np.abs(gueltig - i)))]]
    # Sprenkel glaetten
    lab2 = lab_f.copy()
    for i in range(erst + 1, letzt):
        if lab_f[i - 1] == lab_f[i + 1] != lab_f[i]:
            lab2[i] = lab_f[i - 1]
    lab_f = lab2
    # Baender unter drei Stationen (1,25 % der Laenge) gehen im Nachbarn auf. Eine Python 4
    # traegt ein Dutzend schmaler Warnstreifen; jeder kostete zwei Profilringe, zusammen
    # 53 Ringe und 2500 Dreiecke.
    i = erst
    while i <= letzt:
        j = i
        while j + 1 <= letzt and lab_f[j + 1] == lab_f[i]:
            j += 1
        if j - i + 1 < 3 and i > erst and glas[i] <= 0.5:
            lab_f[i:j + 1] = lab_f[i - 1]
        i = j + 1
    haupt = max(anteil, key=lambda k: anteil[k])
    namen = {haupt: "body"}
    zaehler = [1]
    for k in sorted(anteil, key=lambda k: -anteil[k]):
        if k not in namen:
            namen[k] = "akzent%d" % zaehler[0]
            zaehler[0] += 1
    farben = {namen[k]: _hex(zen[k]) for k in namen}
    rgb_nach_name = {namen[k]: zen[k] for k in namen}

    def mat_bei(x):
        i = int(np.clip((x - xmin) / L * NB, erst, letzt))
        if glas[i] > 0.5:
            return "glass"
        return namen[int(lab_f[i])]

    # Farbgrenzen als zusaetzliche Profilpunkte
    grenzen = []
    for i in range(erst + 1, letzt + 1):
        if mat_bei(xc[i]) != mat_bei(xc[i - 1]):
            grenzen.append(xmin + i * bw)
    xs = sorted(set([p[0] for p in prof] + grenzen))
    xs = [xs[0]] + [x for k, x in enumerate(xs[1:], 1) if x - xs[k - 1] > 0.15 * bw]
    px = np.array([p[0] for p in prof])
    pr = np.array([p[1] for p in prof])
    profil = []
    for k, x in enumerate(xs):
        nxt = xs[k + 1] if k + 1 < len(xs) else x
        profil.append([round(float(x), 2), round(float(np.interp(x, px, pr)), 2), mat_bei(0.5 * (x + nxt))])

    def farbname(c):
        c = np.array(c)
        best, name = 9.0, None
        for nm, cc in rgb_nach_name.items():
            d = float(np.linalg.norm(_merkmal(cc) - _merkmal(c)))
            if d < best:
                best, name = d, nm
        if best > 0.10 and len(farben) < 7:
            name = "akzent%d" % zaehler[0]
            zaehler[0] += 1
            farben[name] = _hex(c)
            rgb_nach_name[name] = c
        return name

    for t in teile:
        t["mat"] = farbname(t.pop("farbe"))
    teile = _gruppiere(teile, bw, rmax)

    spec = {
        "laenge_zoll": round(L, 2), "achse": [round(yc, 2), round(zc, 2)],
        "segmente": 12 if rmax * bau.ZOLL < 0.075 else (16 if rmax * bau.ZOLL < 0.20 else 20),
        "duese": bool(duese), "farben": farben,
        "profil": profil, "teile": teile,
    }
    benutzt = set(p[2] for p in profil) | set(t["mat"] for t in teile)
    if mantel is not None:
        mat = farbname(mantel["farbe"])
        benutzt.add(mat)
        rr = max(mantel["radien"])
        spec["mantel"] = [{"x0": round(mantel["x0"], 2), "x1": round(mantel["x1"], 2),
                           "radien": [round(v, 2) for v in mantel["radien"]],
                           "dicke": round(max(0.045 * rr, 0.30), 2), "mat": mat}]
    spec["farben"] = {k: v for k, v in farben.items() if k in benutzt}
    return spec


def _teil(xm, u, w, bm, rbm, randm, cm, i0, i1, xc, bw, rmax, L, winkel):
    """Ein zusammenhaengendes Teil in einer Winkelebene -> Umriss oder None."""
    n = i1 - i0 + 1
    h = np.full(n, -1e18); np.maximum.at(h, bm - i0, u)
    lw = np.full(n, 1e18); np.minimum.at(lw, bm - i0, u)
    rr = np.full(n, 0.0); np.maximum.at(rr, bm - i0, randm)
    hat = h > -1e17
    if hat.sum() < 1:
        return None
    idx = np.arange(n)
    h = np.interp(idx, idx[hat], h[hat])
    lw = np.interp(idx, idx[hat], lw[hat])
    rr = np.interp(idx, idx[hat], rr[hat])
    x0, x1 = float(xm.min()), float(xm.max())
    xs = xc[i0:i1 + 1].copy()
    xs[0], xs[-1] = x0, x1
    if n == 1:
        xs = np.array([x0, x1]); h = np.array([h[0], h[0]]); lw = np.array([lw[0], lw[0]]); rr = np.array([rr[0], rr[0]])
    hoch = np.maximum(h - np.maximum(lw, rr), 0.0)
    flaeche = float((0.5 * (hoch[1:] + hoch[:-1]) * np.diff(xs)).sum())
    hoehe = float((h - rr).max())
    dicke = 2.0 * float(np.percentile(np.abs(w), 97))
    if flaeche < 0.0035 * L * rmax or hoehe < 0.10 * rmax or (x1 - x0) < 0.006 * L:
        return None
    tol = max(0.02 * rmax, 0.08)
    oben = _dp([(float(a), float(c)) for a, c in zip(xs, h)], tol)
    wurzel = lw <= rr + 0.03 * rmax + 0.25
    unten = []
    k = len(xs) - 1
    while k >= 0:                                   # von hinten nach vorn (x absteigend)
        if wurzel[k]:
            e = k
            while k - 1 >= 0 and wurzel[k - 1]:
                k -= 1
            unten.append([float(xs[e]), 0.0, 1])
            if k != e:
                unten.append([float(xs[k]), 0.0, 1])
        else:
            e = k
            while k - 1 >= 0 and not wurzel[k - 1]:
                k -= 1
            frei = _dp([(float(xs[q]), float(lw[q])) for q in range(e, k - 1, -1)], tol)
            unten += [[p[0], p[1], 0] for p in frei]
        k -= 1
    umriss = [[round(p[0], 2), round(p[1], 2), 0] for p in oben]
    for p in unten:
        letzter = umriss[-1]
        if abs(letzter[0] - p[0]) < 1e-6 and (p[2] == 0 and abs(letzter[1] - p[1]) < 1e-6):
            continue
        umriss.append([round(p[0], 2), round(p[1], 2), int(p[2])])
    # entartete Doppelpunkte am Schluss entfernen
    if len(umriss) > 3 and umriss[0][:2] == umriss[-1][:2] and umriss[-1][2] == 0:
        umriss.pop()
    if len(umriss) < 3:
        return None
    return {"winkel": [round(winkel, 1)], "umriss": umriss, "dicke": round(dicke, 2),
            "farbe": [float(v) for v in np.median(cm, axis=0)],
            "_x": (x0, x1), "_h": float(h.max())}


def _gruppiere(teile, bw, rmax):
    """Gleiche Teile in mehreren Winkelebenen (vier Flossen) zu EINEM Eintrag."""
    aus = []
    for t in teile:
        for a in aus:
            if (abs(a["_x"][0] - t["_x"][0]) < 2.5 * bw and abs(a["_x"][1] - t["_x"][1]) < 2.5 * bw
                    and abs(a["_h"] - t["_h"]) < 0.06 * rmax + 0.05 * a["_h"]
                    and abs(a["dicke"] - t["dicke"]) < 0.5 * max(a["dicke"], t["dicke"], 0.6)
                    and a["mat"] == t["mat"]):
                a["winkel"] += t["winkel"]
                break
        else:
            aus.append(t)
    for a in aus:
        a.pop("_x"); a.pop("_h")
        a["winkel"] = sorted(a["winkel"])
    return aus


def bild(scene, ziel, lo, hi, name):
    welt = bpy.data.worlds.new("w")
    welt.color = (0.045, 0.060, 0.085)
    scene.world = welt
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    sh.show_cavity = True
    scene.display.render_aa = "8"
    scene.render.resolution_x = 1500
    scene.render.resolution_y = 760
    scene.render.image_settings.file_format = "PNG"
    kd = bpy.data.cameras.new("k")
    kd.type = "ORTHO"
    mitte = (lo + hi) * 0.5
    groesse = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
    kd.ortho_scale = groesse * 1.45
    kd.clip_end = groesse * 30
    kam = bpy.data.objects.new("k", kd)
    scene.collection.objects.link(kam)
    scene.camera = kam
    for tag, richt in (("a", Vector((0.50, -0.42, 0.75))), ("b", Vector((-0.55, -0.60, 0.40)))):
        kam.location = mitte + richt.normalized() * groesse * 5
        kam.rotation_euler = (mitte - kam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(ziel, "%s_%s.png" % (name, tag))
        bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    paket, ziel = args[0], os.path.abspath(args[1])
    os.makedirs(ziel, exist_ok=True)
    specs = {}
    if os.path.exists(bau.SPEC):
        with open(bau.SPEC, encoding="utf-8") as fh:
            specs = json.load(fh)
    for eintrag in args[2:]:
        wid, quelle = eintrag.split("=")
        duese = quelle.endswith(":duese")
        quelle = quelle.split(":")[0]
        pfad = finde(paket, quelle)
        if pfad is None:
            print("FEHLT", quelle)
            continue
        bpy.ops.wm.open_mainfile(filepath=pfad)
        scene = bpy.context.scene
        P, C, G = abtasten(scene)
        if wid in specs and specs[wid].get("hand"):
            spec = specs[wid]
            print("HAND", wid, "(unveraendert)")
        else:
            spec = vermesse(P, C, G, duese)
            spec["quelle"] = quelle
            alt = specs.get(wid, {})
            for k in ("name", "segmente"):
                if k in alt:
                    spec[k] = alt[k]
            specs[wid] = spec
        # schlichtes Modell neben die Vorlage stellen
        netz = bau.baue_netz(spec)
        yc, zc = spec["achse"]
        breite = float(P[:, 1].max() - P[:, 1].min())
        seit = float(P[:, 1].max()) + breite + 2.0      # Achse des schlichten Modells
        punkte = [(v.x, v.y + seit, v.z + zc) for v in netz.verts]
        me = bau.mesh_anlegen(wid, punkte, netz, spec)
        obj = bpy.data.objects.new(wid, me)
        scene.collection.objects.link(obj)
        lo = Vector((float(P[:, 0].min()), float(P[:, 1].min()), float(P[:, 2].min())))
        hi = Vector((float(P[:, 0].max()), max(p[1] for p in punkte), float(P[:, 2].max())))
        bild(scene, ziel, lo, hi, wid)
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        print("VERMESSEN %s  L=%.1f  Profil=%d  Teile=%d  Farben=%s  Dreiecke=%d" % (
            wid, spec["laenge_zoll"], len(spec["profil"]),
            sum(len(t["winkel"]) for t in spec["teile"]), spec["farben"], tris))
    with open(bau.SPEC, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(specs, fh, indent=1)
        fh.write("\n")


main()
