#!/usr/bin/env bash
# One-off: KTransformers DeepSeek with two running requests (two OpenCode sessions), 2026-11-21. One 4090 with 36,864-token
# prefill chunks ran out of VRAM on the 44.5k prompt with two running requests, so per config: one request at a time
# (does a lone session keep its speed?), then both requests at once. Configs (default: both):
#   1gpu-c16k  GPU 0, 64 threads, prefill chunk capped at 16384 (KT_PREFILL_PLAN_CAP, DSV41_LEND_MAX_CHUNK; the Qwens keep GPUs 2,3)
#   2gpu-t48   GPUs 0,3, 48 threads (one Qwen gives up its 4090)
# Resumable: tmp_kt_check.sh skips rows already in results.tsv. Needs deepseek and qwen stopped.
set -euo pipefail
cd "$(dirname "$0")"
OUT=${OUT:-/home/sigura/llm_coder/llm/results/kt-review-2026-11-21}
export OUT
declare -A ENVS=(
    [1gpu-c16k]="GPUS=0 KT_PREFILL_PLAN_CAP=16384 DSV41_LEND_MAX_CHUNK=16384"
    [2gpu-t48]="GPUS=0,3 KT_CPU_THREADS=48"
)
ORDER=(1gpu-c16k 2gpu-t48)
(($#)) && ORDER=("$@")

PGID=""
stop() {
    [[ -n $PGID || ! -s $OUT/server-${label:-none}.pgid ]] || PGID=$(cat "$OUT/server-$label.pgid")
    [[ -n $PGID ]] || return 0
    kill -TERM -- "-$PGID" 2>/dev/null || true
    for _ in $(seq 120); do kill -0 -- "-$PGID" 2>/dev/null || break; sleep 1; done
    kill -KILL -- "-$PGID" 2>/dev/null || true
    PGID=""
}
trap stop EXIT

for cfg in "${ORDER[@]}"; do
    [[ -n ${ENVS[$cfg]:-} ]] || { echo "unknown config $cfg"; exit 1; }
    label=kt-two-$cfg
    echo "== $(date +%T) $cfg: one request at a time, then two at once (${ENVS[$cfg]})"
    rm -f "$OUT/server-$label.pgid"
    # a config that fails (out of VRAM) is reported and the next one still runs
    if env ${ENVS[$cfg]} SGLANG_MAX_RUNNING_REQUESTS=2 LABEL=$label WARMUP=1 KEEP=1 ./tmp_kt_check.sh; then
        ATTACH=1 LABEL=$label-par PARALLEL=1 ./tmp_kt_check.sh || echo "== $cfg: two at once FAILED"
    else
        echo "== $cfg: one at a time FAILED"
    fi
    stop
done
echo "== $(date +%T) done"
grep -E '^(config|kt-two)' "$OUT/results.tsv" | column -t
