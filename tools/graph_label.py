#!/usr/bin/env python3
"""Deterministischer Community-Labeler fuer den graphify-Graphen (kein LLM/Backend noetig).

graphify clustert den Code in Communities, laesst sie aber "Community 0..29" heissen (echtes
Benennen kostet sonst einen LLM-Backend-Call). Dieses Skript liest graphify-out/graph.json und
benennt jede Community nach ihrem DOMINANTEN Modul + zentralen Symbolen (nach Knotengrad), und
schreibt eine navigierbare graphify-out/COMMUNITIES.md. Deterministisch -> laeuft bei jedem
Refresh identisch mit (in tools/graph-update.ps1 nach der Extraktion eingehaengt).

Usage:  python tools/graph_label.py [projekt-wurzel]
"""
from __future__ import annotations
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

# Kuratierte Themennamen fuer die stabilen Kern-Module (Basename -> Klartext). Alles andere
# faellt automatisch auf "<Basename> (<Ordner>)" zurueck, bleibt also auch fuer neue Dateien korrekt.
FILE_TOPICS: dict[str, str] = {
    "AircraftBody.gd": "Flugmodell & Schaden (RigidBody-Physik, Flügelbruch, Landung)",
    "BuildController.gd": "Bau-Editor (Drag&Snap, Gizmos, Symmetrie, Windkanal, Docking)",
    "FlightController.gd": "Flugsteuerung, Maus-Flug-Instructor & Verfolgerkamera",
    "PartCatalog.gd": "Bauteil-Katalog & prozedurale/glTF-Visuals",
    "TerrainWorld.gd": "Terrain-Generierung (Chunks, Biome, Flüsse, Flora)",
    "Main.gd": "Welt, UI (Bau-Panel/HUD), Modus BUILD↔FLY, Speichern/Laden",
    "GameState.gd": "Modi, Geld & Upgrades (Persistenz)",
    "Projectile.gd": "Geschosse (Kugel/Rakete/Bombe)",
    "Target.gd": "Ziele (Ballon/Luftschiff)",
    "FlakGun.gd": "Flak-Geschütz (Intercept-Lead, Explosion)",
    "Landmarks.gd": "Wahrzeichen/POIs (Dorf, Brücke, Leuchtturm)",
    "ViewUtil.gd": "Kamera-FOV-Helfer (Ultrawide KEEP_WIDTH)",
    "FlightHud.gd": "Flug-HUD-Anzeige",
    "CLAUDE.md": "Projekt-Doku: Architektur, Rationale & Fallstricke",
    "README.md": "Spieler-Doku (Steuerung & Features)",
}


def _dir_topic(source_file: str) -> str:
    """Fallback-Thema aus dem Ordner, wenn kein kuratierter Name greift."""
    p = source_file.replace("\\", "/")
    if p.startswith("tools/"):
        return "Blender-Build-Pipeline (Modelle/Renders/Dev-Tools)"
    if p.startswith("scenes/") or p.endswith(".tscn") or p.endswith(".tres"):
        return "Szenen & Ressourcen (Godot .tscn/.tres)"
    return ""


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    gp = root / "graphify-out" / "graph.json"
    if not gp.exists():
        print(f"graph.json fehlt: {gp}", file=sys.stderr)
        return 1
    d = json.loads(gp.read_text(encoding="utf-8"))
    nodes = [n for n in d.get("nodes", []) if isinstance(n, dict)]
    links = [e for e in d.get("links", []) if isinstance(e, dict)]

    # Knotengrad (Hub-Score) aus den Kanten
    deg: Counter = Counter()
    for e in links:
        for k in ("source", "target", "_src", "_tgt"):
            v = e.get(k)
            if isinstance(v, str):
                deg[v] += 1

    # Communities sammeln
    by_comm: dict[int, list[dict]] = defaultdict(list)
    for n in nodes:
        by_comm[n.get("community", -1)].append(n)

    def topic_for(source_file: str) -> str:
        base = source_file.replace("\\", "/").split("/")[-1]
        return FILE_TOPICS.get(base) or _dir_topic(source_file) or base

    rows = []
    for comm, members in sorted(by_comm.items(), key=lambda kv: -len(kv[1])):
        # dominante Datei (nur echte Quelldateien zaehlen)
        files = Counter(m.get("source_file", "") for m in members if m.get("source_file"))
        dom_file, dom_n = (files.most_common(1)[0] if files else ("?", 0))
        topic = topic_for(dom_file)
        share = f"{dom_n}/{len(members)}"
        # zentrale Symbole: Funktions-Knoten (label endet auf ")") nach Grad
        funcs = [m for m in members if str(m.get("label", "")).endswith(")")]
        funcs.sort(key=lambda m: -deg.get(m.get("id", ""), 0))
        key_syms = ", ".join(f"`{m.get('label')}`" for m in funcs[:6]) or "—"
        # Nebendateien
        others = [f"{f.split('/')[-1]} ({c})" for f, c in files.most_common(4)[1:]]
        rows.append((comm, len(members), topic, dom_file, share, key_syms, others))

    out = ["# Community-Karte — aviasembly", "",
           f"Automatisch aus `graphify-out/graph.json` benannt (deterministisch, kein LLM). "
           f"{len(nodes)} Knoten in {len(by_comm)} Communities. Nummern = die `Community N` aus GRAPH_REPORT.md.",
           "", "| # | Größe | Thema | Dominantes Modul | Zentrale Symbole |",
           "|---|------:|-------|------------------|------------------|"]
    for comm, size, topic, dom_file, share, key_syms, others in rows:
        out.append(f"| {comm} | {size} | {topic} | `{dom_file}` ({share}) | {key_syms} |")
    out.append("")
    (root / "graphify-out" / "COMMUNITIES.md").write_text("\n".join(out), encoding="utf-8")
    print(f"COMMUNITIES.md geschrieben: {len(rows)} Communities benannt.")

    # --- Labels ueberall durchreichen, wo sonst "Community N" stuende --------------------
    labels = {comm: topic for comm, _s, topic, _df, _sh, _ks, _o in rows}

    # 1) .graphify_labels.json — die Konvention, die graphify-CLI/Exporte lesen
    (root / "graphify-out" / ".graphify_labels.json").write_text(
        json.dumps({str(k): v for k, v in labels.items()}, ensure_ascii=False), encoding="utf-8")

    # 2) GRAPH_REPORT.md: Platzhalter "Community N" durch die echten Themen ersetzen
    rp = root / "graphify-out" / "GRAPH_REPORT.md"
    if rp.exists():
        txt = rp.read_text(encoding="utf-8")
        for comm, topic in sorted(labels.items(), key=lambda kv: -kv[0]):  # 29 vor 2 (Praefix!)
            txt = txt.replace(f"|Community {comm}]]", f"|{topic}]]")
            txt = txt.replace(f"### Community {comm}\n", f"### {topic} (Community {comm})\n")
            txt = txt.replace(f"**Community {comm}**", f"**{topic}**")
        rp.write_text(txt, encoding="utf-8")
        print("GRAPH_REPORT.md: Community-Platzhalter durch Themen ersetzt.")

    # 3) graph.html mit echten Community-Namen neu rendern (Fork-to_html nimmt labels)
    try:
        from graphify.build import build_from_json  # noqa: PLC0415
        from graphify.export import to_html  # noqa: PLC0415
        links = d.get("links", [])
        extraction = {"nodes": nodes, "edges": [
            {**e, "source": e.get("source"), "target": e.get("target")} for e in links],
            "hyperedges": d.get("hyperedges", [])}
        G = build_from_json(extraction, directed=False)
        comm_map = {c: [m.get("id") for m in ms] for c, ms in by_comm.items()}
        to_html(G, comm_map, str(root / "graphify-out" / "graph.html"), community_labels=labels)
        print("graph.html mit echten Community-Namen regeneriert.")
    except Exception as e:  # noqa: BLE001 — HTML ist nice-to-have, nie den Lauf abbrechen
        print(f"Hinweis: graph.html uebersprungen ({e})")

    # 4) Agent-crawlbares Wiki: ein Artikel pro Community, MIT den Rationale-Texten.
    #    (Erfuellt die CLAUDE.md-Regel "if graphify-out/wiki/index.md exists, use it".)
    wiki = root / "graphify-out" / "wiki"
    wiki.mkdir(exist_ok=True)
    idx = ["# Wissensgraph-Wiki — aviasembly", "",
           "Ein Artikel pro Community (Thema). ✎ = Knoten traegt Design-Rationale (das WARUM).", ""]
    for comm, size, topic, dom_file, share, _ks, _o in rows:
        fn = f"community_{comm:02d}.md"
        idx.append(f"- [{topic}]({fn}) — {size} Knoten, dominiert von `{dom_file}`")
        members = by_comm.get(comm, [])
        files = Counter(m.get("source_file", "") for m in members if m.get("source_file"))
        art = [f"# {topic}", "", f"Community {comm} — {size} Knoten.", "", "## Dateien", ""]
        art += [f"- `{f}` ({c} Knoten)" for f, c in files.most_common(8)]
        funcs = sorted((m for m in members if str(m.get("label", "")).endswith(")")),
                       key=lambda m: -deg.get(m.get("id", ""), 0))
        if funcs:
            art += ["", "## Zentrale Symbole (nach Vernetzung)", ""]
            art += [f"- `{m.get('label')}` — {deg.get(m.get('id'), 0)} Kanten "
                    f"[{m.get('source_file')}{' ' + str(m.get('source_location')) if m.get('source_location') else ''}]"
                    for m in funcs[:12]]
        rats = [m for m in members if m.get("rationale")]
        if rats:
            art += ["", "## Konzepte & Design-Rationale ✎", ""]
            for m in sorted(rats, key=lambda m: -deg.get(m.get("id", ""), 0)):
                art += [f"### {m.get('label')}", f"{m['rationale']}", ""]
        (wiki / fn).write_text("\n".join(art), encoding="utf-8")
    (wiki / "index.md").write_text("\n".join(idx) + "\n", encoding="utf-8")
    print(f"Wiki geschrieben: {len(rows)} Artikel -> graphify-out/wiki/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
