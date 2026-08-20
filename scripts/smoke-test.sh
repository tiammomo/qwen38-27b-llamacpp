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

CLIENT_HOST="$BIND_ADDRESS"
if [[ "$CLIENT_HOST" == "0.0.0.0" ]]; then
  CLIENT_HOST="127.0.0.1"
fi
readonly CLIENT_HOST
readonly BASE_URL="http://${CLIENT_HOST}:${PUBLISH_PORT}"
RESPONSE_FILE="$(mktemp)"
readonly RESPONSE_FILE
trap 'rm -f "$RESPONSE_FILE"' EXIT

AUTH_ARGS=()
if [[ -n ${LLAMA_API_KEY:-} ]]; then
  AUTH_ARGS=(-H "Authorization: Bearer $LLAMA_API_KEY")
fi

printf 'Waiting for %s/health' "$BASE_URL"
for _ in $(seq 1 180); do
  if curl --fail --silent --max-time 2 "${AUTH_ARGS[@]}" "$BASE_URL/health" >/dev/null 2>&1; then
    printf ' ready\n'
    break
  fi
  printf '.'
  sleep 2
done

curl --fail --silent --show-error --max-time 5 "${AUTH_ARGS[@]}" "$BASE_URL/health" | jq .
curl --fail --silent --show-error --max-time 5 "${AUTH_ARGS[@]}" "$BASE_URL/v1/models" \
  | jq --arg model "$SERVED_MODEL_ID" -e '{models: [.data[].id]} | select(.models | index($model))'

curl --fail --silent --show-error --max-time 180 \
  "$BASE_URL/v1/chat/completions" \
  "${AUTH_ARGS[@]}" \
  -H 'Content-Type: application/json' \
  --data "$(jq -n --arg model "$SERVED_MODEL_ID" '{model:$model,messages:[{role:"user",content:"只回答数字：2+2等于几？"}],max_tokens:64,temperature:0,chat_template_kwargs:{enable_thinking:false}}')" \
  >"$RESPONSE_FILE"

jq '{model, answer: .choices[0].message.content, reasoning: .choices[0].message.reasoning_content, usage}' "$RESPONSE_FILE"
jq -e --arg model "$SERVED_MODEL_ID" '.model == $model' "$RESPONSE_FILE" >/dev/null
jq -e '.choices | length == 1' "$RESPONSE_FILE" >/dev/null
jq -e '.choices[0].message.content | strings | gsub("\\s"; "") == "4"' "$RESPONSE_FILE" >/dev/null
