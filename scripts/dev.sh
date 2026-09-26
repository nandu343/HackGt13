#!/usr/bin/env bash
# Mac/Linux convenience: setup (if needed) + run web + API
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d node_modules ]]; then
  echo "node_modules missing — running npm run setup…"
  npm run setup
fi

exec npm run dev
