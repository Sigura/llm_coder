#!/usr/bin/env bash
# One-off: pair-programming eval (eval_pair.py) over navigator:driver combinations of the local models, seeds in
# turn. Usage: tmp_pair_matrix.sh NAV:DRIVER [NAV:DRIVER ...]   with NAV/DRIVER in ds, q8, q6
#   ds = DeepSeek V4.1 Flash on KTransformers :8080, q8 = Qwen3.8-27B :8086, q6 = Qwen3.6-35B-A3B MTP :8085
# Each model gets the sampling of its solo eval runs in either role. Env: SEEDS (default 1 2 3), EXTRA (more
# eval_pair.py args), TAG (label suffix for protocol variants), Q8_URL (another Qwen3.8 server). A finished seed is skipped, an interrupted one resumes.
set -euo pipefail
cd "$(dirname "$0")"
SEEDS=${SEEDS:-1 2 3}
SECRETS=/home/sigura/llm_coder/llm/secrets
OUT=/home/sigura/llm_coder/llm/results/pair-eval
declare -A URL=([ds]=http://127.0.0.1:8080/v1 [q8]=${Q8_URL:-http://127.0.0.1:8086/v1} [q6]=http://127.0.0.1:8085/v1)
declare -A MODEL=([ds]=deepseek-v4.1-flash [q8]=qwen3.8-27b [q6]=qwen3.6-35b-a3b-mtp)
declare -A KEY=([ds]=$SECRETS/deepseek-v4.1-flash-1017.key [q8]=$SECRETS/qwen3.8-27b.key [q6]=$SECRETS/qwen3.6-35b-a3b-mtp.key)
declare -A NAME=([ds]=deepseek-kt [q8]=qwen3.8 [q6]=qwen3.6mtp)
declare -A SAMPLING=(
    [ds]="temperature 1.0 top-p 1.0 top-k -1 min-p 0 presence-penalty 0"
    [q8]="temperature 0.7 top-p 0.8 top-k 20 min-p 0 presence-penalty 1.5"
    [q6]="temperature 0.7 top-p 0.8 top-k 20 min-p 0 presence-penalty 1.5"
)
(($#)) || { echo "usage: $0 NAV:DRIVER ..." >&2; exit 2; }
read -ra extra <<<"${EXTRA:-}"

role_args() { # <role nav|driver> <model id>
    local -a kv
    read -ra kv <<<"${SAMPLING[$2]}"
    printf '%s\n' "--$1-url" "${URL[$2]}" "--$1-model" "${MODEL[$2]}" "--$1-key-file" "${KEY[$2]}"
    for ((i = 0; i < ${#kv[@]}; i += 2)); do printf '%s\n' "--$1-${kv[i]}" "${kv[i + 1]}"; done
}

echo "== step 1: check prerequisites"
for tool in python3 bash kotlinc curl; do command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }; done
for combo in "$@"; do
    for id in ${combo/:/ }; do
        [[ -n ${URL[$id]:-} ]] || { echo "unknown model id '$id' in $combo" >&2; exit 1; }
        [[ -r ${KEY[$id]} ]] || { echo "no key file ${KEY[$id]}" >&2; exit 1; }
        curl -sf -m 60 -o /dev/null "${URL[$id]%/v1}/health" || { echo "no server for $id on ${URL[$id]}" >&2; exit 1; }
    done
done

for combo in "$@"; do
    nav=${combo%%:*} drv=${combo##*:}
    mapfile -t args < <(role_args nav "$nav"; role_args driver "$drv")
    for seed in $SEEDS; do
        label=pair-${NAME[$drv]}-nav-${NAME[$nav]}${TAG:+-$TAG}-s$seed
        if ls "$OUT"/*-"$label".json >/dev/null 2>&1; then
            echo "== $label already done"
            continue
        fi
        echo "== $(date +%T) $label"
        python3 eval_pair.py "${args[@]}" --seed "$seed" --label "$label" "${extra[@]}"
    done
done
echo "== $(date +%T) done"
