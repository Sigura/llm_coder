#!/usr/bin/env bash
# One-off: DeepSeek on a real coding workload with and without the MoE cache (--moe-cache-mib), serving arguments
# otherwise. Each config: start the server on BENCH_PORT, two chat requests (repo code as context), record the
# prompt and output speed. Needs GPUs 0,1 free (DeepSeek service unloaded or stopped).
# Usage: tmp_moe_cache_check.sh [config...]   config = label, one of the CONFIGS below (default: all)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

MODEL=deepseek-v4.1-flash-1017
ALL_EXPERTS_CPU="per_layer_token_embd.weight=CPU,ffn_(up|gate|down)_exps=CPU"
declare -A CONFIGS=(
    [base]="ot|"
    [cpu-23936-0.9]="cpu|--moe-cache-mib 23936 --moe-cache-cpu-share 0.9"
    [cpu-23936-0.95]="cpu|--moe-cache-mib 23936 --moe-cache-cpu-share 0.95"
    [cpu-23936-0.98]="cpu|--moe-cache-mib 23936 --moe-cache-cpu-share 0.98"
    [cpu-23936-1]="cpu|--moe-cache-mib 23936 --moe-cache-cpu-share 1"
)
ORDER=(base cpu-23936-0.95 cpu-23936-0.98 cpu-23936-1)
(($#)) && ORDER=("$@")

load_global
load_model "$MODEL"
require_cmd curl jq nvidia-smi
API_KEY=$(api_key)
BASE=http://127.0.0.1:$BENCH_PORT
OUT=$RESULTS_DIR/moe-cache-$(date +%F)/check
mkdir -p "$OUT"
ot_args=$EXTRA_ARGS

info "step 1: check GPUs 0,1 are free"
while IFS=, read -r idx used; do
    ((used < 2000)) || die "GPU $idx has $used MiB in use: stop or unload the DeepSeek service first"
done < <(nvidia-smi --query-gpu=index,memory.used --format=csv,noheader,nounits -i 0,1)

info "step 2: warm the page cache"
"$STACK_DIR/scripts/25-warm-cache.sh" "$MODEL"

info "step 3: build the two coding requests"
make_req() { # <file> <task> <out>
    jq -n --rawfile code "$1" --arg task "$2" '{
        model: "x", max_tokens: 1024, temperature: 0.6, top_p: 0.95,
        messages: [{role: "user", content: ("```\n" + $code + "\n```\n\n" + $task)}]}' >"$3"
}
make_req "$STACK_DIR/scripts/lib.sh" \
    "Add a function lock_set to this library that writes or replaces a versions.lock row, in the same style. Show only the new code." "$OUT/req-1.json"
make_req "$STACK_DIR/scripts/llm_panel.py" \
    "Write pytest tests for the serve-log parser in this file. Show only the test file." "$OUT/req-2.json"

SRV_PID=""
stop_server() {
    [[ -n $SRV_PID ]] || return 0
    kill "$SRV_PID" 2>/dev/null || true
    for _ in $(seq 120); do kill -0 "$SRV_PID" 2>/dev/null || break; sleep 1; done
    kill -9 "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
    SRV_PID=""
}
trap stop_server EXIT

RESULT=$OUT/results.tsv
[[ -s $RESULT ]] || printf 'config\trequest\tprompt_tokens\tprompt_tok_s\toutput_tokens\toutput_tok_s\n' >"$RESULT"
for label in "${ORDER[@]}"; do
    [[ -n ${CONFIGS[$label]:-} ]] || die "unknown config $label"
    layout=${CONFIGS[$label]%%|*}
    cache=${CONFIGS[$label]#*|}
    EXTRA_ARGS=$ot_args
    if [[ $layout == cpu ]]; then
        read -ra a <<<"$ot_args"
        for ((i = 0; i < ${#a[@]}; i++)); do [[ ${a[i]} == -ot ]] && a[i + 1]=$ALL_EXPERTS_CPU; done
        EXTRA_ARGS="${a[*]}"
    fi
    EXTRA_ARGS+=" $cache"
    SRV_PORT=$BENCH_PORT SRV_HOST=127.0.0.1 build_server_cmd
    log_file=$OUT/server-$label.log
    info "step 4/$label: start server: ${SERVER_CMD[*]}"
    "${SERVER_CMD[@]}" -lv 4 >"$log_file" 2>&1 &
    SRV_PID=$!
    wait_ready "$BASE" "$SERVER_READY_TIMEOUT" "$SRV_PID" || die "server $label did not start, see $log_file"
    # PARALLEL=1: both requests at once (the two slots), as two OpenCode sessions would
    tag=$label
    ((${PARALLEL:-0})) && tag=$label-par
    pids=()
    for r in 1 2; do
        api POST "$BASE" /v1/chat/completions "$OUT/req-$r.json" >"$OUT/resp-$tag-$r.json" &
        pids+=($!)
        ((${PARALLEL:-0})) || wait "${pids[-1]}"
    done
    for p in "${pids[@]}"; do wait "$p"; done
    for r in 1 2; do
        jq -r --arg l "$tag" --arg r "$r" '[$l, $r, .timings.prompt_n, (.timings.prompt_per_second*10|round/10),
            .timings.predicted_n, (.timings.predicted_per_second*100|round/100)] | @tsv' "$OUT/resp-$tag-$r.json" | tee -a "$RESULT"
    done
    stop_server
    grep -a "llama_moe_cache:" "$log_file" || info "$label: no MoE cache stats (cache off)"
done
info "done: $RESULT"
column -t "$RESULT"
