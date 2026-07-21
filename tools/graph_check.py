#!/usr/bin/env python3
"""Regressions-Testsuite fuer den graphify-Wissensgraphen (graphify-out/graph.json).

Jede Pruefung deckt eine Fehlerklasse ab, in die dieses Projekt REAL gelaufen ist:
GDScript uebersprungen (falsches graphify), Geisterkanten, ungueltige file_types,
Doku-Schicht beim Code-Refresh verloren (watch.py-Filter), Platzhalter-Communities.

Usage:  python tools/graph_check.py [projekt-wurzel]     (Exit 0 = alles gruen)
"""
from __future__ import annotations
import json
import sys
from collections import Counter
from pathlib import Path

FAILS: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f"  — {detail}" if detail else ""))
    if not ok:
        FAILS.append(name)


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    gp = root / "graphify-out" / "graph.json"
    if not gp.exists():
        print(f"FEHLER: {gp} fehlt.", file=sys.stderr)
        return 1
    d = json.loads(gp.read_text(encoding="utf-8"))
    nodes = [n for n in d.get("nodes", []) if isinstance(n, dict)]
    links = [e for e in d.get("links", []) if isinstance(e, dict)]
    ids = {n.get("id") for n in nodes}
    by_label: dict[str, list] = {}
    for n in nodes:
        by_label.setdefault(str(n.get("label", "")), []).append(n)

    print(f"Graph: {len(nodes)} Knoten, {len(links)} Kanten\n")

    # T1 Groesse (GDScript drin? Ohne .gd waeren es ~180 Knoten — das Tools-only-Desaster)
    gd_nodes = [n for n in nodes if str(n.get("source_file", "")).endswith(".gd")]
    check("T1 GDScript-Code im Graph", len(gd_nodes) > 400,
          f"{len(gd_nodes)} Knoten aus .gd-Dateien")

    # T2 keine Geisterkanten
    dang = [e for e in links if e.get("source") not in ids or e.get("target") not in ids]
    check("T2 keine haengenden Kanten", len(dang) == 0, f"{len(dang)} haengend")

    # T3 Kern-Klassen vorhanden
    want = {"aircraftbody", "buildcontroller", "partcatalog", "flightcontroller", "terrainworld", "gamestate"}
    missing = want - ids
    check("T3 Kern-Klassen als Knoten", not missing, f"fehlen: {missing}" if missing else "alle 6")

    # T4 pro-Datei-Trennung gleichnamiger Symbole (keine Sammelknoten)
    procs = by_label.get("_process()", [])
    srcs = {n.get("source_file") for n in procs}
    check("T4 _process() pro Datei getrennt", len(procs) >= 10 and len(srcs) == len(procs),
          f"{len(procs)} Knoten / {len(srcs)} Dateien")

    # T5 Cross-File-Calls aufgeloest
    x = [e for e in links if e.get("target") == "partcatalog_get_part"
         and "buildcontroller" in str(e.get("source", ""))]
    check("T5 Cross-File-Call BuildController->get_part", len(x) >= 5, f"{len(x)} Kanten")

    # T6 Vererbung
    inh = [e for e in links if e.get("relation") == "inherits"]
    check("T6 inherits-Kanten (extends)", len(inh) >= 15, f"{len(inh)}")

    # T7 Signale (Fork-Feature — geht bei falschem Extraktor verloren)
    sigs = [n for n in nodes if "_signal_" in str(n.get("id", ""))]
    emits = [e for e in links if e.get("relation") == "emits"]
    check("T7 Signal-Knoten + emits", len(sigs) >= 4 and len(emits) >= 6,
          f"{len(sigs)} Signale, {len(emits)} emits")

    # T8 Szenen-Link
    t8 = any(e.get("source") == "scenes_main_tscn" and e.get("target") == "scripts_main_gd"
             for e in links) or any(e.get("target") == "scenes_main_tscn"
                                    and e.get("source") == "scripts_main_gd" for e in links)
    check("T8 Main.tscn <-> Main.gd verlinkt", t8)

    # T9 Doku-Schicht (CLAUDE.md/README.md eingemerged, Rationale abrufbar)
    doc_nodes = [n for n in nodes if str(n.get("source_file", "")).lower() in ("claude.md", "readme.md")]
    rationale = [n for n in doc_nodes if n.get("rationale")]
    check("T9 Doku-Schicht + Rationale", len(doc_nodes) >= 100 and len(rationale) >= 40,
          f"{len(doc_nodes)} Doku-Knoten, {len(rationale)} mit Rationale")

    # T10 HALTBARKEIT: Doku->Code-Kanten muessen INFERRED/AMBIGUOUS sein, sonst loescht sie
    # der naechste `graphify update` (watch.py behaelt nur diese; EXTRACTED an Code = weg)
    doc_ids = {n.get("id") for n in doc_nodes}
    code_ids = {n.get("id") for n in nodes if n.get("file_type") == "code"}
    bad = [e for e in links
           if e.get("confidence") == "EXTRACTED"
           and ((e.get("source") in doc_ids and e.get("target") in code_ids)
                or (e.get("target") in doc_ids and e.get("source") in code_ids))]
    check("T10 Doku->Code-Kanten update-fest (INFERRED)", len(bad) == 0,
          f"{len(bad)} EXTRACTED-Kanten wuerden beim Refresh verloren gehen")

    # T11 file_type-Werte gueltig (Fork-Validator: code/document/image/paper/rationale)
    allowed = {"code", "document", "image", "paper", "rationale"}
    badft = Counter(str(n.get("file_type")) for n in nodes if n.get("file_type") not in allowed)
    check("T11 file_types gueltig", not badft, f"ungueltig: {dict(badft)}" if badft else "")

    # T12 Communities benannt (COMMUNITIES.md existiert, Report ohne nackte Platzhalter-Hubs)
    cm = root / "graphify-out" / "COMMUNITIES.md"
    rep = root / "graphify-out" / "GRAPH_REPORT.md"
    t12 = cm.exists() and rep.exists() and "|Community 0]]" not in rep.read_text(encoding="utf-8")
    check("T12 Communities benannt (Report + Karte)", t12)

    # T13 Wiki generiert (Index + Artikel je Community)
    widx = root / "graphify-out" / "wiki" / "index.md"
    arts = list((root / "graphify-out" / "wiki").glob("community_*.md")) if widx.exists() else []
    check("T13 Wiki (Index + Artikel)", widx.exists() and len(arts) >= 10, f"{len(arts)} Artikel")

    # T14 Query-Tool beantwortet eine Warum-Frage (Umlaut-Query gegen transliterierte Labels!)
    import os
    import subprocess
    # PYTHONUTF8=1: sonst schreibt das Kind auf Windows cp1252 (0xfc fuer "ue") und der
    # utf-8-Decode des Parents wirft UnicodeDecodeError im Reader-Thread.
    r = subprocess.run([sys.executable, str(root / "tools" / "graph_query.py"),
                        "warum gebündelte koeffizienten statt streifentheorie",
                        "--graph", str(gp)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       cwd=str(root), env={**os.environ, "PYTHONUTF8": "1"})
    check("T14 graph_query.py liefert das WARUM", "numerisch instabil" in (r.stdout or ""),
          "Rationale in Ausgabe" if "numerisch instabil" in (r.stdout or "") else f"rc={r.returncode}")

    # T15 aufgeloeste README-Widersprueche sind raus (Chunk-Chirurgie nach dem README-Fix)
    stale = {"readme_fly_by_wire_assist", "readme_windkanal_ansicht", "readme_prozedural_keine_assets"}
    left = stale & ids
    check("T15 keine stalen Widerspruchsknoten", not left, f"noch da: {left}" if left else "")

    print()
    if FAILS:
        print(f"ERGEBNIS: {len(FAILS)} Pruefung(en) ROT: {FAILS}")
        return 1
    print("ERGEBNIS: alle 15 Pruefungen GRUEN.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
