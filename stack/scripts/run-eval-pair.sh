#!/usr/bin/env bash
# Runs eval_pair.py (navigator + driver) for each seed against an llm provider's servers, then idles so that a
# `devbox serve` service is not restarted when the runs end. Run it as such a service, since only those reach the
# model servers at llm-local:
#   devbox serve evalpair --llm <provider> -- stack/scripts/run-eval-pair.sh
# Stop it afterwards with: devbox serve stop evalpair
# Env: NAV_ID / DRIVER_ID (provider server IDs), NAV_MODEL / DRIVER_MODEL, SEEDS, LABEL, EXTRA (eval_pair.py args).
set -euo pipefail
cd "$(dirname "$0")"

NAV_ID=${NAV_ID:-deepseek-v4.1-flash}
DRIVER_ID=${DRIVER_ID:-qwen3.8-27b}
NAV_MODEL=${NAV_MODEL:-deepseek-v4.1-flash}
DRIVER_MODEL=${DRIVER_MODEL:-qwen3.8-27b}
SEEDS=${SEEDS:-1 2 3}
LABEL=${LABEL:-pair-qwen3.8-nav-deepseek}

server_var() { # <id> <URL|KEY> -> value of LLM_SERVER_<ID>_<what>
    local name
    name=LLM_SERVER_$(tr '[:lower:]' '[:upper:]' <<<"$1" | sed 's/[^A-Z0-9]/_/g')_$2
    printf '%s' "${!name:-}"
}

echo "== check prerequisites"
for tool in python3 bash kotlinc; do
    command -v "$tool" >/dev/null || { echo "missing $tool on PATH" >&2; exit 1; }
done
NAV_URL=$(server_var "$NAV_ID" URL)
DRIVER_URL=$(server_var "$DRIVER_ID" URL)
if [[ -z $NAV_URL || -z $DRIVER_URL ]]; then
    echo "no server URL for NAV_ID=$NAV_ID or DRIVER_ID=$DRIVER_ID; this container has:" >&2
    env | grep -o '^LLM_SERVER_[A-Z0-9_]*_URL' >&2 || echo "  none (not started with --llm?)" >&2
    exit 1
fi
read -ra extra <<<"${EXTRA:-}"
key_args=()
[[ -n $(server_var "$NAV_ID" KEY) ]] && key_args+=(--nav-key-file "$(server_var "$NAV_ID" KEY)")
[[ -n $(server_var "$DRIVER_ID" KEY) ]] && key_args+=(--driver-key-file "$(server_var "$DRIVER_ID" KEY)")
echo "navigator $NAV_MODEL at $NAV_URL, driver $DRIVER_MODEL at $DRIVER_URL, seeds $SEEDS"

for seed in $SEEDS; do
    echo "== seed $seed"
    python3 eval_pair.py --nav-url "$NAV_URL" --nav-model "$NAV_MODEL" --driver-url "$DRIVER_URL" \
        --driver-model "$DRIVER_MODEL" "${key_args[@]}" --seed "$seed" --label "$LABEL-s$seed" "${extra[@]}"
done
echo "== all seeds done; idling until devbox serve stop"
exec sleep infinity
