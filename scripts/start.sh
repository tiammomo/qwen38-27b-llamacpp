#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/preflight.sh"
"$SCRIPT_DIR/download-model.sh"
mkdir -p "$PROJECT_DIR/cache/cuda"

cd "$PROJECT_DIR"
set -a
# shellcheck disable=SC1091
source .env
set +a

export RUNTIME_UID="${RUNTIME_UID:-$(id -u)}"
export RUNTIME_GID="${RUNTIME_GID:-$(id -g)}"

docker compose up --detach --wait --wait-timeout "$START_TIMEOUT_SECONDS"

CLIENT_HOST="$BIND_ADDRESS"
if [[ "$CLIENT_HOST" == "0.0.0.0" ]]; then
  CLIENT_HOST="127.0.0.1"
fi
readonly CLIENT_HOST
printf 'llama.cpp server is healthy. API: http://%s:%s/v1\n' "$CLIENT_HOST" "$PUBLISH_PORT"
