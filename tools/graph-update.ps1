# Aktualisiert den graphify-Wissensgraphen (graphify-out/) fuer DIESES Godot-Projekt.
# Volle deterministische Pipeline — jeder Schritt ohne LLM/API-Key:
#   1. AST-Extraktion ueber den GODOT-FORK (die globale graphify 0.9.22 hat KEIN GDScript
#      und wuerde alle .gd als "not classified" ueberspringen -> Graph nur noch Python-Tools!)
#   2. Merge mit der semantischen Doku-Schicht (CLAUDE.md/README.md; aus graphify-out/-Chunks
#      oder der getrackten Kopie tools/semantic_docs_chunk.json) -> graph.json
#   3. Communities deterministisch benennen -> COMMUNITIES.md + Report + graph.html
#   4. Regressions-Testsuite (12 Pruefungen) — schlaegt der Graph fehl, Exit-Code != 0.
# Fork = graphifyy 0.5.0+godot1 (tree-sitter-language-pack), isoliert im eigenen venv.
$fork = "C:\Users\Konst\graphify-godot\.venv\Scripts\python.exe"
$proj = Split-Path -Parent $PSScriptRoot   # tools/ -> Projektwurzel
if (-not (Test-Path $fork)) {
    Write-Error "Godot-Fork-venv fehlt: $fork  (Repo: https://github.com/hidalgob/graphify-godot)"
    exit 1
}

Write-Host "[1/4] AST-Extraktion (Godot-Fork) ..."
& $fork "$PSScriptRoot\graph_ast_extract.py" $proj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[2/4] Merge Code + Doku-Schicht ..."
& $fork "$PSScriptRoot\graph_merge_semantic.py" $proj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "[3/4] Communities benennen ..."
& $fork "$PSScriptRoot\graph_label.py" $proj

Write-Host "[4/4] Testsuite ..."
& $fork "$PSScriptRoot\graph_check.py" $proj
exit $LASTEXITCODE
