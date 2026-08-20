#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT_DIR
readonly ENV_FILE="$PROJECT_DIR/.env"

fail() {
  printf 'Preflight failed: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

for command_name in curl docker flock nvidia-smi sha256sum stat; do
  require_command "$command_name"
done

[[ -r "$ENV_FILE" ]] || fail "missing $ENV_FILE; run: cp .env.example .env"
ENV_MODE="$(stat -c '%a' "$ENV_FILE")"
readonly ENV_MODE
(( (8#$ENV_MODE & 077) == 0 )) \
  || fail ".env is readable by group/others; run: chmod 600 .env"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

for variable_name in \
  LLAMA_IMAGE MODEL_REPOSITORY MODEL_REVISION MODEL_FILE MODEL_SIZE_BYTES MODEL_SHA256 \
  SERVED_MODEL_ID BIND_ADDRESS PUBLISH_PORT CTX_SIZE N_PREDICT PARALLEL GPU_LAYERS \
  CACHE_TYPE_K CACHE_TYPE_V BATCH_SIZE UBATCH_SIZE THREADS THREADS_BATCH START_TIMEOUT_SECONDS; do
  [[ -n ${!variable_name:-} ]] || fail "$variable_name is empty in .env"
done

[[ "$LLAMA_IMAGE" =~ @sha256:[[:xdigit:]]{64}$ ]] \
  || fail "LLAMA_IMAGE must be pinned by a sha256 digest"
[[ "$MODEL_REPOSITORY" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] \
  || fail "MODEL_REPOSITORY must use owner/repository format"
[[ "$MODEL_REVISION" =~ ^[[:xdigit:]]{40,64}$ ]] \
  || fail "MODEL_REVISION must be an immutable 40-64 character hexadecimal revision"
[[ "$MODEL_FILE" == "${MODEL_FILE##*/}" && "$MODEL_FILE" == *.gguf ]] \
  || fail "MODEL_FILE must be a plain .gguf filename"
[[ "$MODEL_SHA256" =~ ^[[:xdigit:]]{64}$ ]] \
  || fail "MODEL_SHA256 must contain 64 hexadecimal characters"

for numeric_name in MODEL_SIZE_BYTES PUBLISH_PORT CTX_SIZE N_PREDICT PARALLEL BATCH_SIZE UBATCH_SIZE THREADS THREADS_BATCH START_TIMEOUT_SECONDS; do
  numeric_value="${!numeric_name}"
  [[ "$numeric_value" =~ ^[1-9][0-9]*$ ]] || fail "$numeric_name must be a positive integer"
done

((PUBLISH_PORT <= 65535)) || fail "PUBLISH_PORT must be at most 65535"
((UBATCH_SIZE <= BATCH_SIZE)) || fail "UBATCH_SIZE cannot exceed BATCH_SIZE"

if [[ "$BIND_ADDRESS" != "127.0.0.1" && -z ${LLAMA_API_KEY:-} ]]; then
  fail "non-loopback BIND_ADDRESS requires a non-empty LLAMA_API_KEY"
fi

docker info >/dev/null 2>&1 || fail "Docker Engine is unavailable"
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is unavailable"
DOCKER_RUNTIMES="$(docker info --format '{{json .Runtimes}}')"
readonly DOCKER_RUNTIMES
[[ "$DOCKER_RUNTIMES" == *'"nvidia"'* ]] || fail "Docker NVIDIA runtime is unavailable"
nvidia-smi >/dev/null 2>&1 || fail "NVIDIA driver is unavailable"

cd "$PROJECT_DIR"
docker compose config --quiet || fail "Compose configuration is invalid"

if command -v ss >/dev/null 2>&1 && ss -H -ltn "sport = :$PUBLISH_PORT" | grep -q .; then
  own_port="$(docker port qwen38-27b-iq3-xxs 8080/tcp 2>/dev/null || true)"
  [[ "$own_port" == *":$PUBLISH_PORT" ]] \
    || fail "port $PUBLISH_PORT is already listening and is not owned by qwen38-27b-iq3-xxs"
fi

readonly MODEL_PATH="$PROJECT_DIR/models/$MODEL_FILE"
if [[ ! -f "$MODEL_PATH" ]]; then
  AVAILABLE_BYTES="$(df --output=avail -B1 "$PROJECT_DIR/models" | tail -n 1 | tr -d '[:space:]')"
  readonly AVAILABLE_BYTES
  ((AVAILABLE_BYTES >= MODEL_SIZE_BYTES)) \
    || fail "insufficient disk space for $MODEL_FILE"
fi

printf 'Preflight OK: NVIDIA Docker is usable; target=%s:%s; model=%s\n' \
  "$BIND_ADDRESS" "$PUBLISH_PORT" "$MODEL_FILE"
