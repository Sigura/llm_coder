#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: $0 [--dry-run] [--port N] [--skip-long] <model-id>

Checks a running server (default 127.0.0.1:PORT from the model config):
  1. GET /v1/models lists ALIAS
  2. simple chat completion returns the expected word
  3. tool call: valid tool_calls with JSON arguments, then a final answer using the tool result
  4. long context: ~HEALTH_LONG_CTX_TOKENS-token prompt, a code hidden in the middle must be found
Exits non-zero if any check fails. --skip-long skips check 4 (reported as SKIPPED, not PASS).
Needs read access to the model's API key (run as LLM_USER or root).
EOF
}

MODEL=""
PORT_OVERRIDE=""
SKIP_LONG=0
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    --port) PORT_OVERRIDE=$2; shift ;;
    --skip-long) SKIP_LONG=1 ;;
    -*) die "unknown option $1" ;;
    *) MODEL=$1 ;;
    esac
    shift
done
[[ -n $MODEL ]] || { usage; exit 2; }

load_global
load_model "$MODEL"
init_logging "$MODEL_ID"
require_cmd curl jq
BASE=http://127.0.0.1:${PORT_OVERRIDE:-$PORT}
if ((DRY_RUN)); then
    info "[dry-run] would run 4 checks against $BASE (alias $ALIAS, long context $HEALTH_LONG_CTX_TOKENS tokens, skip-long=$SKIP_LONG)"
    exit 0
fi
API_KEY=$(api_key)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FAILED=0
RESULTS=()
result() { # <name> <PASS|FAIL|SKIPPED> <detail>
    RESULTS+=("$(printf '%-14s %-7s %s' "$1" "$2" "$3")")
    if [[ $2 == FAIL ]]; then
        FAILED=1
        log FAIL "$1: $3"
    else
        info "$1: $2 $3"
    fi
}

chat() { # <request json file> -> response json on stdout
    api POST "$BASE" /v1/chat/completions "$1"
}

wait_ready "$BASE" 60 || die "server at $BASE is not healthy (GET /health)"

# 1. models
if out=$(api GET "$BASE" /v1/models) && jq -e --arg a "$ALIAS" '[.data[].id] | index($a) != null' <<<"$out" >/dev/null; then
    result models PASS "$(jq -r '[.data[].id] | join(",")' <<<"$out")"
else
    result models FAIL "alias $ALIAS not listed: ${out:0:300}"
fi

# 2. simple chat
jq -n --arg m "$ALIAS" '{model: $m, max_tokens: 4096, temperature: 0,
    messages: [{role: "user", content: "Reply with exactly one word: pong"}]}' >"$WORK/chat.json"
start=$SECONDS
if out=$(chat "$WORK/chat.json") && [[ $(jq -r '.choices[0].message.content // ""' <<<"$out") =~ [Pp][Oo][Nn][Gg] ]]; then
    result chat PASS "$((SECONDS - start))s, $(jq -r '.usage.completion_tokens' <<<"$out") tokens, reasoning $(jq -r '.choices[0].message.reasoning_content // "" | length' <<<"$out") chars"
else
    result chat FAIL "unexpected reply: ${out:0:500}"
fi

# 3. tool call, then feed the tool result back
jq -n --arg m "$ALIAS" '{model: $m, max_tokens: 4096, temperature: 0,
    tools: [{type: "function", function: {name: "get_weather", description: "Current weather for a city",
        parameters: {type: "object", properties: {city: {type: "string"}}, required: ["city"]}}}],
    messages: [{role: "user", content: "What is the weather in Paris right now? Use the get_weather tool."}]}' >"$WORK/tool1.json"
start=$SECONDS
if out=$(chat "$WORK/tool1.json") &&
    jq -e '.choices[0].message.tool_calls[0].function | .name == "get_weather" and ((.arguments | fromjson | .city) | test("paris"; "i"))' <<<"$out" >/dev/null 2>&1; then
    jq --argjson resp "$out" '.messages += [$resp.choices[0].message | del(.reasoning_content),
        {role: "tool", tool_call_id: $resp.choices[0].message.tool_calls[0].id, content: "{\"temp_c\": 17, \"sky\": \"overcast\"}"}]' \
        "$WORK/tool1.json" >"$WORK/tool2.json"
    if out2=$(chat "$WORK/tool2.json") && [[ $(jq -r '.choices[0].message.content // ""' <<<"$out2") == *17* ]]; then
        result tool_calls PASS "$((SECONDS - start))s, args $(jq -c '.choices[0].message.tool_calls[0].function.arguments' <<<"$out")"
    else
        result tool_calls FAIL "tool result not used in final answer: ${out2:0:500}"
    fi
else
    result tool_calls FAIL "no valid get_weather tool call: ${out:0:500}"
fi

# 4. long context needle
if ((SKIP_LONG)); then
    result long_context SKIPPED "--skip-long"
else
    target=$HEALTH_LONG_CTX_TOKENS
    ((target + 4096 < CTX)) || die "HEALTH_LONG_CTX_TOKENS=$target does not fit CTX=$CTX"
    gen_filler 400 7 >"$WORK/sample.txt"
    jq -Rs --arg m "$ALIAS" '{model: $m, content: .}' "$WORK/sample.txt" >"$WORK/tok.json"
    per100=$(api POST "$BASE" /tokenize "$WORK/tok.json" | jq '.tokens | length / 4')
    lines=$(awk -v t="$target" -v p="$per100" 'BEGIN { printf "%d", t / p * 100 * 0.97 }')
    code="NEEDLE-$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')"
    {
        gen_filler "$((lines / 2))" 11
        echo "Important: the secret access code is $code. Remember it."
        gen_filler "$((lines - lines / 2))" 13
    } >"$WORK/haystack.txt"
    jq -n --arg m "$ALIAS" --rawfile h "$WORK/haystack.txt" '{model: $m, max_tokens: 4096, temperature: 0,
        messages: [{role: "user", content: ($h + "\n\nWhat is the secret access code mentioned in the text above? Answer with the code only.")}]}' >"$WORK/long.json"
    info "long context: $lines lines, ~$target tokens; this can take several minutes"
    start=$SECONDS
    if out=$(chat "$WORK/long.json"); then
        ptok=$(jq -r '.usage.prompt_tokens' <<<"$out")
        if [[ $(jq -r '.choices[0].message.content // ""' <<<"$out") == *"$code"* ]] && ((ptok >= target * 9 / 10)); then
            result long_context PASS "$ptok prompt tokens, $((SECONDS - start))s, $(jq -r '.timings.prompt_per_second // 0 | floor' <<<"$out") tok/s prefill"
        else
            result long_context FAIL "$ptok prompt tokens, code $code not found in: $(jq -r '.choices[0].message.content' <<<"$out" | head -c 300)"
        fi
    else
        result long_context FAIL "request failed: ${out:0:500}"
    fi
fi

info "==== health $MODEL_ID @ $BASE"
for r in "${RESULTS[@]}"; do info "$r"; done
((FAILED == 0)) || die "health check FAILED"
info "health check passed"
