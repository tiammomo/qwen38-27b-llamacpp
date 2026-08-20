#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT_DIR
readonly ENV_FILE="$PROJECT_DIR/.env"

if [[ ! -r "$ENV_FILE" ]]; then
  printf 'Missing %s; copy .env.example to .env first.\n' "$ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${MODEL_REPOSITORY:?set MODEL_REPOSITORY in .env}"
: "${MODEL_REVISION:?set MODEL_REVISION in .env}"
: "${MODEL_FILE:?set MODEL_FILE in .env}"
: "${MODEL_SIZE_BYTES:?set MODEL_SIZE_BYTES in .env}"
: "${MODEL_SHA256:?set MODEL_SHA256 in .env}"

readonly MODEL_NAME="$MODEL_FILE"
readonly MODEL_URL="https://huggingface.co/${MODEL_REPOSITORY}/resolve/${MODEL_REVISION}/${MODEL_NAME}?download=true"
readonly EXPECTED_SIZE="$MODEL_SIZE_BYTES"
readonly EXPECTED_SHA256="$MODEL_SHA256"
readonly MODEL_DIR="$PROJECT_DIR/models"
readonly MODEL_PATH="$MODEL_DIR/$MODEL_NAME"
readonly PART_PATH="$MODEL_PATH.part"
readonly LOCK_PATH="$MODEL_DIR/.download.lock"

if (($# > 1)) || [[ ${1:-} != "" && ${1:-} != "--verify-only" ]]; then
  printf 'Usage: %s [--verify-only]\n' "$0" >&2
  exit 2
fi

mkdir -p "$MODEL_DIR"
exec 9>"$LOCK_PATH"
flock 9

verify_model() {
  local path="$1"
  local actual_size
  actual_size="$(stat -c '%s' "$path")"
  if [[ "$actual_size" != "$EXPECTED_SIZE" ]]; then
    printf 'Size mismatch for %s: expected %s, got %s bytes\n' "$path" "$EXPECTED_SIZE" "$actual_size" >&2
    return 1
  fi

  printf '%s  %s\n' "$EXPECTED_SHA256" "$path" | sha256sum --check --status
}

if [[ -f "$MODEL_PATH" ]]; then
  if verify_model "$MODEL_PATH"; then
    printf 'Model already present and verified: %s\n' "$MODEL_PATH"
    exit 0
  fi
  printf 'Existing final model failed verification; refusing to overwrite it.\n' >&2
  exit 1
fi

if [[ ${1:-} == "--verify-only" ]]; then
  printf 'Model is missing: %s\n' "$MODEL_PATH" >&2
  exit 1
fi

if [[ -f "$PART_PATH" ]] && (( $(stat -c '%s' "$PART_PATH") > EXPECTED_SIZE )); then
  printf 'Partial file is larger than expected; remove or inspect it before retrying: %s\n' "$PART_PATH" >&2
  exit 1
fi

printf 'Downloading %s (%s bytes) from pinned revision %s...\n' "$MODEL_NAME" "$EXPECTED_SIZE" "$MODEL_REVISION"
curl \
  --fail \
  --location \
  --retry 8 \
  --retry-delay 2 \
  --retry-all-errors \
  --continue-at - \
  --output "$PART_PATH" \
  "$MODEL_URL"

if ! verify_model "$PART_PATH"; then
  printf 'Downloaded artifact failed verification and remains at %s\n' "$PART_PATH" >&2
  exit 1
fi

mv -- "$PART_PATH" "$MODEL_PATH"
chmod 0444 "$MODEL_PATH"
printf 'Verified model ready: %s\n' "$MODEL_PATH"
