#!/usr/bin/env bash
# One-off: re-check our llama.cpp findings on SGLang + KTransformers before DeepSeek serving moves to it (2026-11-21).
# Steps (each skips what results.tsv / its output already holds, so a rerun resumes):
#   1 one 4090 vs two            2 48 vs 64 CPU expert threads
#   3 likely serving config, one 4090 (GPU 0) and 48 threads (steps 1-2), 1 running request, kept up for 4-7:
#     warm speed, repeated prompt (prefix cache)
#   4 two requests at once       5 checkpoint evicted from the page cache   6 tool calls (KT's tool-call-check.py)
#   7 one evalpair seed: navigator DeepSeek on KT, driver Qwen3.8 (llm-serve.sh, GPU 2, port 8086), vs seed 1 on llama.cpp
# Needs deepseek and qwen stopped (devbox serve stop ...); keep stack/scripts/telemetry.sh running.
set -euo pipefail
cd "$(dirname "$0")"
OUT=${OUT:-/home/sigura/llm_coder/llm/results/kt-review-$(date +%F)}
export OUT
KT=/home/sigura/llm_coder/llm/engines/alt/kt-wrapper
PORT=8160
SEED=${SEED:-1}
mkdir -p "$OUT"

KT_PGID=""
QWEN_PID=""
cleanup() {
    [[ -n $KT_PGID || ! -s $OUT/server-kt-serve.pgid ]] || KT_PGID=$(cat "$OUT/server-kt-serve.pgid")
    [[ -z $QWEN_PID ]] || { kill -TERM -- "-$QWEN_PID" 2>/dev/null || true; }
    [[ -z $KT_PGID ]] || { kill -TERM -- "-$KT_PGID" 2>/dev/null || true; }
    sleep 20
    [[ -z $QWEN_PID ]] || { kill -KILL -- "-$QWEN_PID" 2>/dev/null || true; }
    [[ -z $KT_PGID ]] || { kill -KILL -- "-$KT_PGID" 2>/dev/null || true; }
}
trap cleanup EXIT

echo "== $(date +%T) check prerequisites"
pgrep -f telemetry.sh >/dev/null || echo "warning: telemetry.sh is not running"

echo "== $(date +%T) 1: one 4090 (GPU 0)"
GPUS=0 LABEL=kt-1gpu WARMUP=1 ./tmp_kt_check.sh

echo "== $(date +%T) 2: 48 CPU expert threads, GPUs 0,3"
GPUS=0,3 LABEL=kt-t48 KT_CPU_THREADS=48 WARMUP=1 ./tmp_kt_check.sh

echo "== $(date +%T) 3: serving config, GPU 0, 48 threads, 1 running request (2 run out of GPU memory on a 44.5k prompt); repeat = prefix cache"
rm -f "$OUT/server-kt-serve.pgid"
GPUS=0 LABEL=kt-serve KT_CPU_THREADS=48 SGLANG_MAX_RUNNING_REQUESTS=1 WARMUP=1 REPEAT=1 KEEP=1 ./tmp_kt_check.sh
KT_PGID=$(cat "$OUT/server-kt-serve.pgid")

echo "== $(date +%T) 4: two requests at once"
ATTACH=1 LABEL=kt-par PARALLEL=1 ./tmp_kt_check.sh

echo "== $(date +%T) 5: checkpoint evicted from the page cache before each request"
ATTACH=1 LABEL=kt-evict EVICT=1 ./tmp_kt_check.sh

echo "== $(date +%T) 6: tool calls"
if ! grep -q '^PASS' "$OUT/tool-call-check.txt" 2>/dev/null; then
    status=0
    "$KT/.venv/bin/python" -I "$KT/tools/tool-call-check.py" "http://127.0.0.1:$PORT" >"$OUT/tool-call-check.txt" 2>&1 || status=$?
    ((status)) && echo "FAIL (exit $status)" >>"$OUT/tool-call-check.txt" || echo "PASS" >>"$OUT/tool-call-check.txt"
fi
tail -15 "$OUT/tool-call-check.txt"

echo "== $(date +%T) 7: evalpair seed $SEED, navigator DeepSeek on KT, driver Qwen3.8"
label=pair-qwen3.8-nav-deepseek-kt-s$SEED
if ls /home/sigura/llm_coder/llm/results/pair-eval/*-"$label".json >/dev/null 2>&1; then
    echo "seed $SEED already done"
else
    setsid ./llm-serve.sh qwen3.8-27b >"$OUT/qwen.log" 2>&1 &
    QWEN_PID=$!
    for _ in $(seq 120); do
        curl -s -m 3 -o /dev/null http://127.0.0.1:8086/health && break
        kill -0 "$QWEN_PID" 2>/dev/null || { echo "qwen server exited, see $OUT/qwen.log"; exit 1; }
        sleep 5
    done
    python3 eval_pair.py --nav-url "http://127.0.0.1:$PORT/v1" --nav-model deepseek-v4.1-flash-kt \
        --driver-url http://127.0.0.1:8086/v1 --driver-model qwen3.8-27b \
        --driver-key-file /home/sigura/llm_coder/llm/secrets/qwen3.8-27b.key --seed "$SEED" --label "$label"
fi
echo "== $(date +%T) done: $OUT/results.tsv"
column -t "$OUT/results.tsv"
