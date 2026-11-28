#!/usr/bin/env bash
# Usage: opencode-local.sh [--auto] [opencode args...]
# Starts OpenCode in the current directory against the local servers: DeepSeek V4.1 Flash (8080) as the default
# model (build and plan), Qwen3.8-27B (8086) as the "fast" primary agent (Tab switches agents) and the reviewer,
# Qwen3.6 MTP (8085) as small_model. The writer rules of the fast-feedback study (eval/writer-rules2.txt) are always on.
# Also registers the router (llm-router.sh, 8090) as model "local-auto/auto"; --auto makes it the default model.
# The default model is the KTransformers DeepSeek (deepseek-v4.1-flash-1017-fp8); OPENCODE_MAIN=deepseek-v4.1-flash-1017
# points it at the llama.cpp config instead (same port, alias and key).
# Config, sessions and logs live under $LLM_ROOT/state/opencode (the container's ~/.config is read-only);
# OPENCODE_STATE=<dir> uses another dir.
# The review: with devbox's OpenCode plugin at hand (OPENCODE_GATE_JS, default /usr/local/share/devbox/opencode-gate.js,
# in devbox's image), the harness runs it: a syntax check after each edit, scripts/check.sh when a turn ends, then
# Qwen3.8 reviews the diff in a session of its own (agent devbox-review). Without the plugin the model is told to
# run llm-review.sh (config/opencode-review.md); OPENCODE_REVIEW=0 leaves that instruction out.
# API keys are exported from the key files without printing them.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_cmd opencode jq curl
load_global
AUTO=0
[[ ${1:-} == --auto ]] && { AUTO=1; shift; }

MAIN=${OPENCODE_MAIN:-deepseek-v4.1-flash-1017-fp8} SMALL=qwen3.6-35b-a3b-mtp FAST=qwen3.8-27b
base=${OPENCODE_STATE:-$LLM_ROOT/state/opencode}
export XDG_CONFIG_HOME=$base/config XDG_DATA_HOME=$base/data XDG_STATE_HOME=$base/state XDG_CACHE_HOME=$base/cache
mkdir -p "$XDG_CONFIG_HOME/opencode" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
cfg=$XDG_CONFIG_HOME/opencode/opencode.json

echo "== registering models in $cfg" >&2
for id in $FAST $SMALL $MAIN; do
    flags=(--server-ip 127.0.0.1 --config "$cfg")
    [[ $id == "$MAIN" ]] && flags+=(--set-default)
    [[ $id == "$SMALL" ]] && flags+=(--set-small)
    "$(dirname "$0")/60-client-config.sh" "${flags[@]}" "$id" >/dev/null
    load_model "$id"
    curl -sf "http://127.0.0.1:$PORT/health" >/dev/null || warn "$id is not up on port $PORT"
    export "$CLIENT_KEY_ENV=$(api_key)"
done

# DeepSeek scores best on the coding eval (pass@2 24.7/29 vs 16.7 for Qwen3.8) at ~11 tok/s, so it builds and plans;
# its server has 2 slots, so plan and build don't wait for each other. Qwen3.8 (~35 tok/s) is the "fast" agent for
# quick edits. The review runs outside the agent's context on Qwen3.8 (short prompt, task + diff only): DeepSeek +
# Qwen3.8 review is the eval's best setup (docs/pair-eval-winners.md), and the compile gate the fast-feedback study's
# top finding (docs/ff-study.md): both come from devbox's plugin where it is installed.
gate=${OPENCODE_GATE_JS:-/usr/local/share/devbox/opencode-gate.js}
[[ -f $gate ]] || { warn "no OpenCode gate plugin at $gate: the model is told to run llm-review.sh instead"; gate=""; }
load_model $FAST
fast="local-$MODEL_ID/$ALIAS"
load_model $MAIN
jq --arg m "local-$MODEL_ID/$ALIAS" --arg fast "$fast" --arg instr "$STACK_DIR/config/opencode-review.md" \
    --arg rules "$STACK_DIR/eval/writer-rules2.txt" --arg gate "$gate" \
    --arg reviewer "{file:$STACK_DIR/config/opencode-reviewer.md}" \
    --arg plan "{file:$STACK_DIR/config/opencode-plan.md}" --arg review "${OPENCODE_REVIEW:-1}" '
    del(.agent.deep, .agent["devbox-review"])
  | .agent.fast = {mode: "primary", model: $fast,
      description: "Qwen3.8-27B: ~3x faster than DeepSeek but weaker; quick edits and simple tasks (64k context)"}
  | .agent.plan = {model: $m, prompt: $plan, tools: {write: false, edit: false, patch: false},
      description: "DeepSeek plans and advises in short answers; build writes the code"}
  | .plugin = ((.plugin // []) | map(select(endswith("/opencode-gate.js") | not)) + (if $gate == "" then [] else [$gate] end))
  | (if $gate == "" then . else .agent["devbox-review"] = {mode: "subagent", hidden: true, model: $fast, prompt: $reviewer,
      permission: {"*": "deny"}, description: "Qwen3.8 reviews the diff after a turn (devbox gate plugin)"} end)
  | .instructions = ((.instructions // []) - [$rules, $instr] + [$rules]
      + (if $review == "0" or $gate != "" then [] else [$instr] end))
  | .command.review = {description: "Independent review of the changes by Qwen3.8-27B (llm-review.sh)",
      template: "Run ~/llm_coder/stack/scripts/llm-review.sh on the code changed in this session (--diff in a git repo, else the changed files) with a --task that states what the code must do. Show its output, then fix the defects you agree with. Focus: $ARGUMENTS"}' \
    "$cfg" >"$cfg.tmp"
mv "$cfg.tmp" "$cfg"

router_port=${ROUTER_PORT:-8090}
curl -sf "http://127.0.0.1:$router_port/health" >/dev/null || warn "llm-router is not up on port $router_port"
LOCAL_ROUTER_KEY=$(<"$SECRETS_DIR/llm-router.key")
export LOCAL_ROUTER_KEY
jq --arg url "http://127.0.0.1:$router_port/v1" --argjson ctx "$SLOT_CTX" --argjson auto "$AUTO" '
    .provider["local-auto"] = {npm: "@ai-sdk/openai-compatible", name: "llm-router: Qwen3.8, DeepSeek for long prompts",
        options: {baseURL: $url, apiKey: "{env:LOCAL_ROUTER_KEY}", timeout: 3600000},
        models: {auto: {name: "auto (Qwen3.8 -> DeepSeek above ~48k prompt tokens)", tool_call: true, reasoning: true,
            temperature: true, limit: {context: $ctx, output: 16384}}}}
    | if $auto == 1 then .model = "local-auto/auto" else . end' "$cfg" >"$cfg.tmp"
mv "$cfg.tmp" "$cfg"

echo "== opencode in $PWD" >&2
exec opencode "$@"
