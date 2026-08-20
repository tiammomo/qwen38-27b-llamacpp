#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"
docker compose ps
printf '\nGPU memory:\n'
nvidia-smi --query-gpu=name,memory.used,memory.free --format=csv,noheader

