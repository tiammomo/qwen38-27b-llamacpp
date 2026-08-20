#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT_DIR

cd "$PROJECT_DIR"
bash -n scripts/*.sh

python3 - <<'PY'
import ast
from pathlib import Path

for path in Path("scripts").glob("*.py"):
    ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
PY

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh
else
  printf 'warning: shellcheck is not installed; skipping shell lint\n' >&2
fi

docker compose --env-file .env.example config --quiet
git diff --check
printf 'Static checks passed.\n'
