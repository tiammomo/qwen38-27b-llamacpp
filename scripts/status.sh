#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT_DIR

cd "$PROJECT_DIR"
set -a
# shellcheck disable=SC1091
source .env
set +a

docker compose ps

CLIENT_HOST="$BIND_ADDRESS"
if [[ "$CLIENT_HOST" == "0.0.0.0" ]]; then
  CLIENT_HOST="127.0.0.1"
fi
readonly CLIENT_HOST
readonly BASE_URL="http://${CLIENT_HOST}:${PUBLISH_PORT}"
AUTH_ARGS=()
if [[ -n ${LLAMA_API_KEY:-} ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer $LLAMA_API_KEY")
fi

printf '\nAPI: %s/v1\n' "$BASE_URL"
if curl --fail --silent --show-error --max-time 5 "${AUTH_ARGS[@]}" "$BASE_URL/health" 2>/dev/null | jq .; then
  :
else
  printf 'Health endpoint is unavailable.\n'
fi

printf '\nGPU memory:\n'
nvidia-smi --query-gpu=name,memory.used,memory.free --format=csv,noheader
