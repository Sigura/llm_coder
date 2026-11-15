#!/usr/bin/env bash
# Usage: opencode-local.sh [--auto] [opencode args...]
# Starts OpenCode in the current directory against the local servers: Qwen3.8-27B (8086) as the default model,
# Qwen3.6 MTP (8085) as small_model, DeepSeek V4.1 Flash (8080) as the "deep" primary agent (Tab switches agents).
# Also registers the router (llm-router.sh, 8090) as model "local-auto/auto"; --auto makes it the default model.
# Config, sessions and logs live under $LLM_ROOT/state/opencode (the container's ~/.config is read-only).
# API keys are exported from the key files without printing them.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_cmd opencode jq curl
load_global
AUTO=0
[[ ${1:-} == --auto ]] && { AUTO=1; shift; }

MAIN=qwen3.8-27b SMALL=qwen3.6-35b-a3b-mtp DEEP=deepseek-v4.1-flash-1017
base=$LLM_ROOT/state/opencode
export XDG_CONFIG_HOME=$base/config XDG_DATA_HOME=$base/data XDG_STATE_HOME=$base/state XDG_CACHE_HOME=$base/cache
mkdir -p "$XDG_CONFIG_HOME/opencode" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
cfg=$XDG_CONFIG_HOME/opencode/opencode.json

echo "== registering models in $cfg" >&2
for id in $DEEP $SMALL $MAIN; do
    flags=(--server-ip 127.0.0.1 --config "$cfg")
    [[ $id == "$MAIN" ]] && flags+=(--set-default)
    [[ $id == "$SMALL" ]] && flags+=(--set-small)
    "$(dirname "$0")/60-client-config.sh" "${flags[@]}" "$id" >/dev/null
    load_model "$id"
    curl -sf "http://127.0.0.1:$PORT/health" >/dev/null || warn "$id is not up on port $PORT"
    export "$CLIENT_KEY_ENV=$(api_key)"
done

load_model $DEEP
jq --arg m "local-$MODEL_ID/$ALIAS" '.agent.deep = {mode: "primary", model: $m,
    description: "DeepSeek V4.1 Flash: slower (~13 tok/s), for hard problems and long context (128k)"}' "$cfg" >"$cfg.tmp"
mv "$cfg.tmp" "$cfg"

router_port=${ROUTER_PORT:-8090}
curl -sf "http://127.0.0.1:$router_port/health" >/dev/null || warn "llm-router is not up on port $router_port"
LOCAL_ROUTER_KEY=$(<"$SECRETS_DIR/llm-router.key")
export LOCAL_ROUTER_KEY
jq --arg url "http://127.0.0.1:$router_port/v1" --argjson ctx "$CTX" --argjson auto "$AUTO" '
    .provider["local-auto"] = {npm: "@ai-sdk/openai-compatible", name: "llm-router: Qwen3.8, DeepSeek for long prompts",
        options: {baseURL: $url, apiKey: "{env:LOCAL_ROUTER_KEY}", timeout: 3600000},
        models: {auto: {name: "auto (Qwen3.8 -> DeepSeek above ~48k prompt tokens)", tool_call: true, reasoning: true,
            temperature: true, limit: {context: $ctx, output: 16384}}}}
    | if $auto == 1 then .model = "local-auto/auto" else . end' "$cfg" >"$cfg.tmp"
mv "$cfg.tmp" "$cfg"

echo "== opencode in $PWD" >&2
exec opencode "$@"
