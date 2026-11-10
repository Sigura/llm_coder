#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: $0 [--dry-run] [--print-only] [--config <opencode.json>] [--server-ip IP] [--set-default] <model-id>

Writes an OpenCode provider for <model-id> (@ai-sdk/openai-compatible, "provider" key of the stable releases) and
merges it into the OpenCode config (default: \${XDG_CONFIG_HOME:-~/.config}/opencode/opencode.json).
Other providers and settings are kept; the old file is backed up when it changes.
The API key is not written: the config references {env:CLIENT_KEY_ENV}. Run as the OpenCode user.
  --print-only   print the snippet, change nothing
  --set-default  also set the top-level "model" to this model
  --server-ip    address in baseURL (default: SERVER_IP from global.env, else first "hostname -I")
EOF
}

MODEL=""
PRINT_ONLY=0
SET_DEFAULT=0
TARGET=${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json
IP=""
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    --print-only) PRINT_ONLY=1 ;;
    --set-default) SET_DEFAULT=1 ;;
    --config) TARGET=$2; shift ;;
    --server-ip) IP=$2; shift ;;
    -*) die "unknown option $1" ;;
    *) MODEL=$1 ;;
    esac
    shift
done
[[ -n $MODEL ]] || { usage; exit 2; }

load_global
load_model "$MODEL"
init_logging "$MODEL_ID"
require_cmd jq
require_vars CLIENT_KEY_ENV OUTPUT_LIMIT
IP=${IP:-$SERVER_IP}
[[ -n $IP ]] || IP=$(hostname -I | awk '{ print $1 }')
[[ -n $IP ]] || die "could not determine the server IP; pass --server-ip"
PROVIDER=${CLIENT_PROVIDER_ID:-local-$MODEL_ID}

snippet=$(jq -n \
    --arg p "$PROVIDER" --arg url "http://$IP:$PORT/v1" --arg env "$CLIENT_KEY_ENV" \
    --arg alias "$ALIAS" --arg name "${CLIENT_MODEL_NAME:-$ALIAS}" \
    --argjson ctx "$CTX" --argjson out "$OUTPUT_LIMIT" --argjson timeout "$CLIENT_TIMEOUT_MS" \
    --argjson reasoning "$([[ ${REASONING:-0} == 1 ]] && echo true || echo false)" '
    {"$schema": "https://opencode.ai/config.json",
     provider: {($p): {
        npm: "@ai-sdk/openai-compatible",
        name: ("llama.cpp: " + $name),
        options: {baseURL: $url, apiKey: ("{env:" + $env + "}"), timeout: $timeout},
        models: {($alias): {
            name: $name,
            tool_call: true,
            reasoning: $reasoning,
            temperature: true,
            limit: {context: $ctx, output: $out}}}}}}')

if ((PRINT_ONLY)); then
    printf '%s\n' "$snippet"
    exit 0
fi

current='{}'
if [[ -s $TARGET ]]; then
    current=$(jq . "$TARGET" 2>/dev/null) || die "$TARGET is not plain JSON (JSONC comments?); merge this by hand: $0 --print-only $MODEL"
fi
merged=$(jq --argjson s "$snippet" --arg p "$PROVIDER" --arg m "$PROVIDER/$ALIAS" --argjson def "$SET_DEFAULT" '
    .["$schema"] = $s["$schema"]
    | .provider[$p] = $s.provider[$p]
    | if $def == 1 then .model = $m else . end' <<<"$current")

if [[ $merged == "$current" ]]; then
    info "$TARGET already up to date ($PROVIDER/$ALIAS)"
elif ((DRY_RUN)); then
    info "[dry-run] would write $TARGET:"
    diff <(printf '%s\n' "$current") <(printf '%s\n' "$merged") || true
else
    mkdir -p "$(dirname "$TARGET")"
    [[ -f $TARGET ]] && cp -p "$TARGET" "$TARGET.bak-$(date +%Y%m%d-%H%M%S)"
    printf '%s\n' "$merged" >"$TARGET.tmp"
    mv -f "$TARGET.tmp" "$TARGET"
    info "wrote $TARGET (provider $PROVIDER, model $PROVIDER/$ALIAS, baseURL http://$IP:$PORT/v1)"
fi

info "next: export $CLIENT_KEY_ENV=\"\$(sudo cat $KEY_FILE)\"   # then: opencode run -m $PROVIDER/$ALIAS 'hello'"
