#!/usr/bin/env python3
"""Bessere Freitext-Abfrage fuer den graphify-Graphen — behebt die zwei Schwaechen des
Standard-`graphify query`:
  1. Startknoten-Wahl ist dort Keyword-fuzzy und scheitert an Umlauten (Labels sind
     ue/ae/oe-transliteriert) -> hier: Normalisierung auf beiden Seiten + Scoring ueber
     Label UND Rationale-Text (stdlib difflib, kein Extra-Paket).
  2. Das `rationale`-Attribut (das WARUM aus CLAUDE.md) wird dort gar nicht angezeigt ->
     hier steht es direkt in der Ausgabe.

Usage:  python tools/graph_query.py "warum gebuendelte koeffizienten" [--top 4] [--depth 2]
"""
from __future__ import annotations
import argparse
import json
import sys
from collections import defaultdict, deque
from difflib import SequenceMatcher
from pathlib import Path

STOP = {"der", "die", "das", "und", "oder", "ein", "eine", "im", "in", "am", "an", "auf",
        "mit", "von", "zu", "bei", "ist", "sind", "wird", "warum", "wie", "was", "wo",
        "the", "a", "an", "of", "to", "is", "how", "why", "what", "does", "kein", "keine"}


def norm(s: str) -> str:
    s = s.lower()
    for a, b in (("ü", "ue"), ("ä", "ae"), ("ö", "oe"), ("ß", "ss")):
        s = s.replace(a, b)
    return s


def tokens(s: str) -> set[str]:
    out = set()
    for t in "".join(c if c.isalnum() else " " for c in norm(s)).split():
        if len(t) > 2 and t not in STOP:
            out.add(t)
    return out


def score(qtok: set[str], qn: str, n: dict) -> float:
    """Token-Ueberlappung (Label + Rationale) + Sequenz-Aehnlichkeit aufs Label."""
    label = str(n.get("label", ""))
    rat = str(n.get("rationale") or "")
    ltok = tokens(label)
    rtok = tokens(rat[:400])
    s = 0.0
    for t in qtok:
        if t in ltok:
            s += 2.0                                   # Treffer im Label zaehlt doppelt
        elif any(t in lt or lt in t for lt in ltok):
            s += 1.2                                   # Teilwort (Fluegelbruch ~ fluegel)
        if t in rtok:
            s += 1.0
        elif rat and t in norm(rat):
            s += 0.6
    s += SequenceMatcher(None, qn, norm(label)).ratio() * 1.5
    if n.get("rationale"):
        s *= 1.15                                      # Warum-Traeger leicht bevorzugen
    return s


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("frage")
    ap.add_argument("--top", type=int, default=4, help="Startknoten (default 4)")
    ap.add_argument("--depth", type=int, default=2, help="BFS-Tiefe (default 2)")
    ap.add_argument("--graph", default="graphify-out/graph.json")
    a = ap.parse_args()

    gp = Path(a.graph)
    if not gp.exists():
        print(f"graph.json fehlt: {gp} — erst tools/graph-update.ps1 laufen lassen.", file=sys.stderr)
        return 1
    d = json.loads(gp.read_text(encoding="utf-8"))
    nodes = [n for n in d.get("nodes", []) if isinstance(n, dict)]
    links = [e for e in d.get("links", []) if isinstance(e, dict)]
    by_id = {n.get("id"): n for n in nodes}
    adj: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for e in links:
        s, t = e.get("source"), e.get("target")
        r = str(e.get("relation", ""))
        if s in by_id and t in by_id:
            adj[s].append((t, r))
            adj[t].append((s, "<" + r))

    qn = norm(a.frage)
    qtok = tokens(a.frage)
    ranked = sorted(nodes, key=lambda n: -score(qtok, qn, n))
    starts = [n for n in ranked[:a.top] if score(qtok, qn, n) > 0.8]
    if not starts:
        print("Kein passender Einstieg gefunden — Frage umformulieren oder COMMUNITIES.md lesen.")
        return 2

    print(f"Frage: {a.frage}")
    print(f"Einstieg ueber {len(starts)} Knoten (Fuzzy-Match auf Label+Rationale):\n")
    seen_ids: set[str] = set()
    for st in starts:
        sid = st.get("id")
        loc = f"{st.get('source_file', '?')}" + (f" {st.get('source_location')}" if st.get("source_location") else "")
        print(f"### {st.get('label')}   [{loc}]")
        if st.get("rationale"):
            print(f"    WARUM: {st['rationale']}")
        # BFS-Nachbarschaft
        q = deque([(sid, 0)])
        local_seen = {sid}
        hops: dict[int, list[str]] = defaultdict(list)
        while q:
            cur, dep = q.popleft()
            if dep >= a.depth:
                continue
            for nb, rel in adj.get(cur, []):
                if nb in local_seen:
                    continue
                local_seen.add(nb)
                nn = by_id[nb]
                mark = " ✎" if nn.get("rationale") else ""
                hops[dep + 1].append(f"{rel:>28}  {nn.get('label')}{mark}  [{nn.get('source_file','?')}]")
                q.append((nb, dep + 1))
        for dep in sorted(hops):
            shown = hops[dep][:10 if dep == 1 else 6]
            print(f"    -- {dep} Hop{'s' if dep > 1 else ''} ({len(hops[dep])}) --")
            for line in shown:
                print(f"    {line}")
            if len(hops[dep]) > len(shown):
                print(f"       ... +{len(hops[dep]) - len(shown)} weitere")
        seen_ids |= local_seen
        print()
    # verwandte Warum-Traeger im erreichten Teilgraph
    extra = [by_id[i] for i in seen_ids
             if by_id[i].get("rationale") and by_id[i] not in starts]
    if extra:
        print("Weitere WARUM-Traeger im Umfeld (✎):")
        for n in extra[:6]:
            print(f"  - {n.get('label')}: {str(n['rationale'])[:140]}...")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
