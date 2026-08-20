#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly MODEL_NAME="Qwen3.8-27B-UD-IQ3_XXS.gguf"
readonly MODEL_REVISION="27af057ecb382ddfea5d12837360a8980560e3ed"
readonly MODEL_URL="https://huggingface.co/unsloth/Qwen3.8-27B-GGUF/resolve/${MODEL_REVISION}/${MODEL_NAME}"
readonly EXPECTED_SIZE="10934860704"
readonly EXPECTED_SHA256="c0b7c3038681ed2e3040456c1dd45f9858b6c2290bed172c70388a94874f3eee"
readonly MODEL_DIR="$PROJECT_DIR/models"
readonly MODEL_PATH="$MODEL_DIR/$MODEL_NAME"
readonly PART_PATH="$MODEL_PATH.part"
readonly LOCK_PATH="$MODEL_DIR/.download.lock"

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
