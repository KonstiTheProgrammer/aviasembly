#!/usr/bin/env python3
"""Exportiert den graphify-Wissensgraphen als OBSIDIAN-VAULT (graphify-out/obsidian/).

Nutzt graphify.export.to_obsidian (ein Note pro Knoten, [[Wikilinks]], Community-Notes)
und schliesst drei Luecken fuer DIESEN Graphen:
  1. KURZE Community-Namen: die langen Themen ("Bau-Editor (Drag&Snap, ...)") enthalten
     (),&,Kommas — in Obsidian-Tags unzulaessig -> Tag-Panel/Farbgruppen kaputt. Hier
     wird ein tag-sicherer Kurzname erzeugt (community/Bau-Editor).
  2. RATIONALE in die Notes: to_obsidian schreibt das Warum-Attribut nicht raus — ein
     Post-Pass haengt es als "## Warum (Design-Rationale)" an (dieselbe Dateinamens-
     Logik wie to_obsidian, inkl. Dedup-Reihenfolge!).
  3. FARBEN: .obsidian/graph.json wird mit einer Farbgruppe je Community vorbelegt
     (goldener-Winkel-Palette) — die Graphansicht ist beim ersten Oeffnen eingefaerbt.
     Nur wenn die Datei fehlt -> manuelle Anpassungen des Nutzers bleiben erhalten.

Usage:  python tools/graph_obsidian.py [projekt-wurzel]   (Fork-venv, wie die Pipeline)
"""
from __future__ import annotations
import colorsys
import json
import re
import sys
from pathlib import Path


def short_label(topic: str) -> str:
    """Tag-sicherer Kurzname: bis zur ersten Klammer, Sonderzeichen raus, - statt Space."""
    s = topic.split("(")[0].strip()
    s = s.replace("↔", "-").replace("&", "und").replace("/", "-")
    s = re.sub(r"[^0-9A-Za-zÄÖÜäöüß \-]", "", s).strip()
    s = re.sub(r"\s+", "-", s)
    return s or "Sonstiges"


def main() -> int:
    root = (Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()).resolve()
    out = root / "graphify-out"
    gp = out / "graph.json"
    if not gp.exists():
        print(f"graph.json fehlt: {gp}", file=sys.stderr)
        return 1
    d = json.loads(gp.read_text(encoding="utf-8"))
    nodes = [n for n in d.get("nodes", []) if isinstance(n, dict)]
    links = [e for e in d.get("links", []) if isinstance(e, dict)]

    # Communities + Kurznamen (aus den Themen des Labelers)
    comm_members: dict[int, list[str]] = {}
    for n in nodes:
        comm_members.setdefault(int(n.get("community", -1)), []).append(n["id"])
    topics = {}
    lp = out / ".graphify_labels.json"
    if lp.exists():
        topics = {int(k): v for k, v in json.loads(lp.read_text(encoding="utf-8")).items()}
    labels = {cid: short_label(topics.get(cid, f"Community {cid}")) for cid in comm_members}
    # Kollisionen (mehrere Blender-Pipeline-Cluster) durchnummerieren
    seen: dict[str, int] = {}
    for cid in sorted(labels):
        base = labels[cid]
        if base in seen:
            seen[base] += 1
            labels[cid] = f"{base}-{seen[base]}"
        else:
            seen[base] = 0

    from graphify.build import build_from_json
    from graphify.export import to_obsidian

    G = build_from_json({"nodes": nodes, "edges": links, "hyperedges": []}, directed=False)
    vault = out / "obsidian"
    written = to_obsidian(G, comm_members, str(vault), community_labels=labels)
    print(f"Vault: {written} Notes -> {vault}")

    # --- Post-Pass: Rationale anhaengen (Dateinamens-Logik EXAKT wie to_obsidian) -------
    def safe_name(label: str) -> str:
        cleaned = re.sub(r'[\\/*?:"<>|#^[\]]', "",
                         label.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")).strip()
        cleaned = re.sub(r"\.(md|mdx|markdown)$", "", cleaned, flags=re.IGNORECASE)
        return cleaned or "unnamed"

    fname: dict[str, str] = {}
    seen_names: dict[str, int] = {}
    for nid, data in G.nodes(data=True):
        base = safe_name(data.get("label", nid))
        if base in seen_names:
            seen_names[base] += 1
            fname[nid] = f"{base}_{seen_names[base]}"
        else:
            seen_names[base] = 0
            fname[nid] = base

    rats = 0
    for n in nodes:
        rat = n.get("rationale")
        if not rat:
            continue
        f = vault / (fname.get(n["id"], "") + ".md")
        if not f.exists():
            continue
        txt = f.read_text(encoding="utf-8")
        block = f"\n## Warum (Design-Rationale)\n\n> {rat}\n"
        # vor den Inline-Tags (letzte Zeile) einschieben
        lines = txt.rstrip().rsplit("\n", 1)
        f.write_text((lines[0] + block + "\n" + lines[1] + "\n") if len(lines) == 2
                     else txt + block, encoding="utf-8")
        rats += 1
    print(f"Rationale-Bloecke in Notes eingefuegt: {rats}")

    # --- Farbgruppen fuer die Graphansicht vorbelegen (nur wenn nicht vorhanden) --------
    cfgdir = vault / ".obsidian"
    cfgdir.mkdir(exist_ok=True)
    gcfg = cfgdir / "graph.json"
    if not gcfg.exists():
        groups = []
        order = sorted(comm_members, key=lambda c: -len(comm_members[c]))
        for i, cid in enumerate(order):
            h = (i * 0.618033988749895) % 1.0          # goldener Winkel -> gut trennbare Farben
            r, g, b = (int(x * 255) for x in colorsys.hsv_to_rgb(h, 0.72, 0.92))
            groups.append({"query": f"tag:#community/{labels[cid]}",
                           "color": {"a": 1, "rgb": (r << 16) + (g << 8) + b}})
        gcfg.write_text(json.dumps({
            "colorGroups": groups,
            "showTags": False, "showAttachments": False, "hideUnresolved": True,
            "showOrphans": True, "centerStrength": 0.45, "repelStrength": 12.5,
            "linkStrength": 0.85, "linkDistance": 160, "scale": 0.35,
            "close": False,
        }, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"Graphansicht vorkonfiguriert: {len(groups)} Community-Farbgruppen")
    else:
        print("Graphansicht-Konfig existiert — nicht angefasst (Nutzer-Einstellungen).")

    # Start-Note immer (re)generieren — Orientierung beim ersten Oeffnen; sortiert per
    # Unterstrich nach oben. Gehoert zum generierten Vault, darf ueberschrieben werden.
    (vault / "_START HIER.md").write_text("\n".join([
        "---", "tags:", "  - graphify/start", "---", "",
        "# Aviassembly-Wissensgraph in Obsidian", "",
        "**Generierter** Wissensgraph: GDScript-Code (Klassen, Funktionen, Signale, Aufrufe)",
        "plus Doku-Schicht aus CLAUDE.md/README — 52 Knoten tragen das Design-Warum als",
        "„## Warum (Design-Rationale)“.", "",
        "## Graph ansehen", "",
        "1. **Strg+G** — Graph-Ansicht. Farben = vorkonfiguriert, eine pro Community.",
        "2. Filter: `tag:#community/Flugmodell-und-Schaden` (ein Thema),",
        "   `tag:#graphify/rationale` (nur Warum-Traeger), Suche: `Fluegelbruch`, `Sternmotor` …",
        "3. Rechtsklick auf eine Note -> **Lokale Graph-Ansicht** = nur die Umgebung des Knotens.", "",
        "## Navigation", "",
        "- `_COMMUNITY_*`-Notes (oben) = Uebersicht pro Thema.",
        "- Jede Note verlinkt Nachbarn mit Relation (`calls`, `references`, `rationale_for` …).", "",
        "## Wichtig", "",
        "Der Vault wird von `tools/graph-update.ps1` NEU generiert — eigene Notizen gehen",
        "beim Refresh verloren; nur `.obsidian/graph.json` (Ansicht-Einstellungen) bleibt.",
    ]), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
