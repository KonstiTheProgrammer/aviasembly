#!/usr/bin/env python3
"""Merged die semantische Doc-Extraktion in den Code-Graphen und baut graph.json neu.

Hintergrund: `graphify update` (tools/graph-update.ps1) extrahiert nur CODE (AST, deterministisch).
Das Architekturwissen aus CLAUDE.md/README.md (Designentscheidungen, Tuning-Konstanten, Fallstricke,
"GESCHICHTE (nicht wiederholen!)") steckt aber NICHT im Code und kommt nur ueber eine semantische
LLM-Extraktion rein. graphify braucht dafuer KEINEN API-Key: ist keiner gesetzt, ist der Host-Agent
selbst das LLM (Claude Code dispatcht Subagenten, die graphify-out/.graphify_chunk_*.json schreiben).

Dieses Skript nimmt:
  graphify-out/.graphify_ast.json      <- Code-Extraktion (Fork, inkl. .gd/.tscn)
  graphify-out/.graphify_chunk_*.json  <- semantische Chunks (Subagenten)
und baut daraus graph.json + GRAPH_REPORT.md neu.

FALLEN, die hier abgefangen werden:
  1. Der Godot-Fork (0.5.0) hat KEIN `root=` in build_from_json -> nicht uebergeben.
  2. Subagenten schreiben ABSOLUTE source_file-Pfade, der AST relative -> sonst zerfaellt der Graph
     in zwei Pfad-Welten (Report/Labeler gruppieren dann falsch). Wird hier relativiert.
  3. Kanten auf nicht existierende Knoten-IDs (Geisterknoten) werden gezaehlt und gemeldet, statt
     still den Graphen zu verschmutzen.

Usage:  python tools/graph_merge_semantic.py [projekt-wurzel]
"""
from __future__ import annotations
import glob
import json
import sys
from pathlib import Path


def _rel(p: str, root: Path) -> str:
    """Absoluten source_file-Pfad auf projekt-relative Posix-Form bringen (siehe Falle 2)."""
    if not p:
        return p
    s = str(p).replace("\\", "/")
    r = str(root.resolve()).replace("\\", "/").rstrip("/")
    if s.lower().startswith(r.lower() + "/"):
        return s[len(r) + 1:]
    return s


def main() -> int:
    root = (Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()).resolve()
    out = root / "graphify-out"
    ast_p = out / ".graphify_ast.json"
    if not ast_p.exists():
        print(f"FEHLER: {ast_p} fehlt — zuerst die AST-Extraktion laufen lassen.", file=sys.stderr)
        return 1

    ast = json.loads(ast_p.read_text(encoding="utf-8"))
    nodes = list(ast.get("nodes", []))
    edges = list(ast.get("edges", []))
    hyper = list(ast.get("hyperedges", []))
    n_ast_nodes, n_ast_edges = len(nodes), len(edges)

    # --- semantische Chunks einsammeln ---
    # Primaer aus graphify-out/ (frische Extraktion); Fallback: die in git GETRACKTE Kopie
    # tools/semantic_docs_chunk.json — so ist der volle Graph (AST frei + Doku-Schicht) auch
    # nach einem "graphify-out/ loeschen" ohne neuen LLM-Lauf reproduzierbar.
    chunks = sorted(glob.glob(str(out / ".graphify_chunk_*.json")))
    tracked = root / "tools" / "semantic_docs_chunk.json"
    if not chunks and tracked.exists():
        chunks = [str(tracked)]
        print(f"kein frischer Chunk — nutze getrackte Kopie {tracked.name}")
    sem_nodes = sem_edges = 0
    for c in chunks:
        try:
            d = json.loads(Path(c).read_text(encoding="utf-8"))
        except Exception as e:
            print(f"  WARNUNG: {Path(c).name} unlesbar ({e}) — uebersprungen.")
            continue
        for n in d.get("nodes", []):
            n["source_file"] = _rel(n.get("source_file", ""), root)
            # Der Fork-Validator kennt nur code/document/image/paper/rationale — 'concept'
            # (aus der neueren Skill-Spec) wuerde 86 Warnungen spammen. Fachlich sind die
            # Konzept-Knoten hier Doku-Wissen -> 'rationale' ist die passende Kategorie.
            if n.get("file_type") == "concept":
                n["file_type"] = "rationale"
            nodes.append(n)
            sem_nodes += 1
        for e in d.get("edges", []):
            e["source_file"] = _rel(e.get("source_file", ""), root)
            edges.append(e)
            sem_edges += 1
        for h in d.get("hyperedges", []):
            h["source_file"] = _rel(h.get("source_file", ""), root)
            hyper.append(h)
    print(f"AST: {n_ast_nodes} Knoten / {n_ast_edges} Kanten"
          f"  +  semantisch: {sem_nodes} Knoten / {sem_edges} Kanten  aus {len(chunks)} Chunk(s)")

    # --- dedupe by id (AST gewinnt: strukturelle Wahrheit schlaegt LLM-Interpretation) ---
    seen: set[str] = set()
    deduped = []
    for n in nodes:
        nid = n.get("id")
        if nid and nid not in seen:
            seen.add(nid)
            deduped.append(n)
    dropped = len(nodes) - len(deduped)

    # --- Qualitaetspruefung: zeigen semantische Kanten auf echte Knoten? (Falle 3) ---
    dangling = [e for e in edges
                if e.get("source") not in seen or e.get("target") not in seen]
    doc_to_code = 0
    ast_ids = {n.get("id") for n in ast.get("nodes", [])}
    sem_ids = seen - ast_ids
    for e in edges:
        s, t = e.get("source"), e.get("target")
        if (s in sem_ids and t in ast_ids) or (t in sem_ids and s in ast_ids):
            doc_to_code += 1
    print(f"dedupe: {dropped} doppelte IDs verworfen -> {len(deduped)} Knoten")
    print(f"VERLINKUNG Doku->Code: {doc_to_code} Kanten treffen echte Code-Knoten")
    if dangling:
        # EXTRACTED-Kanten (= AST-Wahrheit) auf fehlende Ziele sind ECHTE Abhaengigkeiten auf
        # nicht indexierte Dateien (Shader, Fonts, externe Python-Module wie bpy/numpy) — dafuer
        # Stub-Knoten anlegen statt die Information wegzuwerfen (Main.gd -> Sky-Shader,
        # TerrainWorld -> Water-Shader, tools -> Blender-API sind reale Architektur-Kanten).
        # INFERRED/AMBIGUOUS-Geister (= LLM-Fehler) werden weiterhin verworfen.
        stubs = 0
        kept_edges = []
        for e in edges:
            s, t = e.get("source"), e.get("target")
            ok_s, ok_t = s in seen, t in seen
            if ok_s and ok_t:
                kept_edges.append(e)
                continue
            if e.get("confidence") == "EXTRACTED" and (ok_s or ok_t):
                missing = t if ok_s else s
                label = missing.replace("_", ".") if "." not in missing else missing
                # Kategorie: Shader = Code, alles andere = externes Artefakt/Modul
                ftype = "code" if "gdshader" in missing else "document"
                deduped.append({"id": missing, "label": label, "file_type": ftype,
                                "source_file": e.get("source_file", ""),
                                "source_location": None, "stub": True})
                seen.add(missing)
                stubs += 1
                kept_edges.append(e)
            # sonst: Geisterkante verwerfen
        print(f"Stub-Knoten fuer nicht indexierte Ziele angelegt: {stubs} "
              f"(Shader/Fonts/externe Module) — {len(edges) - len(kept_edges)} echte Geisterkanten verworfen")
        edges = kept_edges

    # --- HALTBARKEIT: Doc->Code-Kanten von EXTRACTED auf INFERRED heben -------------------
    # watch.py::_rebuild_code behaelt beim naechsten `graphify update` nur Kanten, die
    # INFERRED/AMBIGUOUS sind ODER deren BEIDE Endpunkte Nicht-Code sind. Eine Doc->Code-Kante
    # mit EXTRACTED erfuellt keins von beidem -> sie wuerde beim ersten Code-Refresh STILL
    # geloescht (der Filter nimmt an, EXTRACTED-Kanten an Code kaemen vom AST und wuerden neu
    # erzeugt — was fuer aus Dokumenten gewonnene Kanten nicht stimmt).
    # Fachlich ist INFERRED hier ohnehin korrekter: was ein DOKUMENT ueber Code behauptet, ist
    # eine Inferenz (Doku kann veralten), kein aus dem AST extrahierter Fakt.
    regraded = 0
    for e in edges:
        s, t = e.get("source"), e.get("target")
        crosses = (s in sem_ids and t in ast_ids) or (t in sem_ids and s in ast_ids)
        if crosses and e.get("confidence") == "EXTRACTED":
            e["confidence"] = "INFERRED"
            e["confidence_score"] = max(float(e.get("confidence_score") or 0.0), 0.95)
            regraded += 1
    if regraded:
        print(f"haltbar gemacht: {regraded} Doku->Code-Kante(n) EXTRACTED -> INFERRED(0.95), "
              f"sonst haette sie der naechste `graphify update` verworfen")

    merged = {"nodes": deduped, "edges": edges, "hyperedges": hyper,
              "input_tokens": 0, "output_tokens": 0}
    (out / ".graphify_extract.json").write_text(json.dumps(merged, ensure_ascii=False), encoding="utf-8")

    # --- bauen / clustern / berichten (Fork-API: KEIN root=, siehe Falle 1) ---
    from graphify.build import build_from_json
    from graphify.cluster import cluster, score_all
    from graphify.analyze import god_nodes, surprising_connections
    from graphify.report import generate
    from graphify.export import to_json

    G = build_from_json(merged, directed=False)
    if G.number_of_nodes() == 0:
        print("FEHLER: leerer Graph — nichts geschrieben.", file=sys.stderr)
        return 1
    communities = cluster(G)
    cohesion = score_all(G, communities)
    labels = {cid: f"Community {cid}" for cid in communities}   # tools/graph_label.py benennt sie danach
    gods = god_nodes(G)
    surprises = surprising_connections(G, communities)

    to_json(G, communities, str(out / "graph.json"), force=True)
    detection = {"total_files": 0, "total_words": 0, "files": {}}
    try:
        report = generate(G, communities, cohesion, labels, gods, surprises, detection,
                          {"input": 0, "output": 0}, str(root))
        (out / "GRAPH_REPORT.md").write_text(report, encoding="utf-8")
    except Exception as e:
        print(f"  Hinweis: Report-Generierung uebersprungen ({e})")

    print(f"GEBAUT: {G.number_of_nodes()} Knoten, {G.number_of_edges()} Kanten, "
          f"{len(communities)} Communities -> graphify-out/graph.json")

    # Referenzliste der Code-Knoten-IDs aktuell halten: das ist die Verlinkungs-Grundlage fuer
    # jede kuenftige semantische (Doku-)Extraktion — der Subagent darf nur ECHTE IDs benutzen,
    # sonst entstehen Geisterknoten (die Skill-Spec-IDs passen NICHT zum Fork-Schema!).
    code_rows = [f"{n.get('id')}\t{n.get('label','')}\t{n.get('source_file','')}"
                 for n in deduped
                 if str(n.get('source_file', '')).endswith(('.gd', '.tscn')) and not n.get('stub')]
    (out / ".existing_nodes.tsv").write_text("\n".join(sorted(code_rows)), encoding="utf-8")
    print(f"Referenz aktualisiert: {len(code_rows)} Code-Knoten-IDs -> .existing_nodes.tsv")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
