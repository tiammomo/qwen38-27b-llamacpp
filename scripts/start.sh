#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/download-model.sh"
mkdir -p "$PROJECT_DIR/cache/cuda"

cd "$PROJECT_DIR"
docker compose config --quiet
docker compose up --detach

printf 'llama.cpp server started. API: http://127.0.0.1:%s/v1\n' "${PUBLISH_PORT:-$(sed -n 's/^PUBLISH_PORT=//p' .env)}"

