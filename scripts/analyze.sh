#!/usr/bin/env bash
# Type-checks src/ with luau-lsp against the Roblox definitions.
#   LUAU_LSP=path/to/luau-lsp DEFS=path/to/globalTypes.d.luau scripts/analyze.sh
# LuauTinyControlFlowAnalysis enables early-return refinement (`if not x then return end`),
# which older luau-lsp builds leave off by default.
set -euo pipefail
LUAU_LSP="${LUAU_LSP:-luau-lsp}"
DEFS="${DEFS:-globalTypes.d.luau}"
rojo sourcemap default.project.json -o sourcemap.json
"$LUAU_LSP" analyze --platform roblox --sourcemap sourcemap.json --definitions "$DEFS" \
	--flag:LuauTinyControlFlowAnalysis=true src
