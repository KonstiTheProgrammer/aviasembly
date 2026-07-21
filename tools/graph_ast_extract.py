#!/usr/bin/env python3
"""AST-Extraktion (Schritt 1 der Graph-Pipeline) — MUSS mit dem Godot-Fork-venv laufen.

Extrahiert alle Code-Dateien (inkl. .gd/.tscn via tree-sitter-language-pack) nach
graphify-out/.graphify_ast.json. Kein LLM, kein API-Key, deterministisch.
Als eigene Datei statt Inline-Snippet: powershell.exe (5.1) zerlegt Anfuehrungszeichen
in -c Argumenten (Native-Arg-Mangling) — Datei + Pfad-Argument ist versionsfest.

Usage:  python tools/graph_ast_extract.py [projekt-wurzel]
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

from graphify.detect import detect
from graphify.extract import collect_files, extract


def main() -> int:
    root = (Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()).resolve()
    det = detect(root)
    files: list[Path] = []
    for f in det.get("files", {}).get("code", []):
        p = Path(f)
        files.extend(collect_files(p) if p.is_dir() else [p])
    if not files:
        print("FEHLER: keine Code-Dateien gefunden.", file=sys.stderr)
        return 1
    res = extract(files, cache_root=root)
    out = root / "graphify-out"
    out.mkdir(exist_ok=True)
    (out / ".graphify_ast.json").write_text(json.dumps(res, ensure_ascii=False), encoding="utf-8")
    print(f"AST: {len(res['nodes'])} Knoten, {len(res['edges'])} Kanten aus {len(files)} Dateien")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
