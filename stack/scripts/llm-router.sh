#!/usr/bin/env bash
# Usage: llm-router.sh [<model-id>:<max-prompt-tokens>... <last-model-id>]
# Runs llm_router.py in the foreground on ROUTER_PORT (default 8090): one OpenAI-compatible model "auto" that sends
# each chat request to the first model whose prompt limit fits, and keeps a conversation on the bigger model once it
# has moved there. Default: qwen3.8-27b up to 48000 prompt tokens, then deepseek-v4.1-flash-1017.
# Clients use the key in $LLM_ROOT/secrets/llm-router.key.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_cmd python3
load_global

(($#)) || set -- qwen3.8-27b:48000 deepseek-v4.1-flash-1017
port=${ROUTER_PORT:-8090}
# Where the model servers are reached: 127.0.0.1 in the same container; the host gateway (llm-local) from a service.
upstream=${ROUTER_UPSTREAM_HOST:-127.0.0.1}
router_key=$SECRETS_DIR/llm-router.key
[[ -f $router_key ]] || die "missing $router_key; create it: ( umask 077; openssl rand -hex 32 > $router_key )"

tiers=()
for spec in "$@"; do
    id=${spec%%:*} limit=0
    [[ $spec == *:* ]] && limit=${spec#*:}
    load_model "$id"
    tiers+=(--tier "$id=http://$upstream:$PORT,$ALIAS,$KEY_FILE,$limit")
    ctx=$CTX
    info "tier $id: port $PORT, alias $ALIAS, prompt limit ${limit/#0/none}"
done

exec python3 -I "$(dirname "$0")/llm_router.py" --host "$BIND_HOST" --port "$port" --key-file "$router_key" \
    --context "$ctx" "${tiers[@]}"
