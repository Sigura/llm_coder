#!/usr/bin/env bash
# One-off: resume the remeasure (tmp_pair_queue_r3.sh, tmp_pair_queue_r4.sh, paused Nov 23 18:30) once the DeepSeek +
# reviewer seeds (tmp_review_seeds.sh ds:q8 and ds:ds, seeds 1-3) have all written their result files.
set -euo pipefail
cd "$(dirname "$0")"
RES=$HOME/burnish/eval/coding/results
LOG=/home/sigura/llm_coder/llm/results/pair-eval
labels=()
for r in qwen3.8-27b deepseek-v4.1-flash; do for s in 1 2 3; do labels+=("deepseek-v4.1-flash-review-$r-s$s"); done; done
echo "== $(date +%T) step 1: wait for ${#labels[@]} review results"
while :; do
    missing=0
    for l in "${labels[@]}"; do ls "$RES"/*-"$l".json >/dev/null 2>&1 || missing=$((missing + 1)); done
    ((missing == 0)) && break
    sleep 300
done
echo "== $(date +%T) step 2: restart r3 and r4"
nohup setsid ./tmp_pair_queue_r3.sh >>"$LOG/queue-r3.log" 2>&1 &
nohup setsid ./tmp_pair_queue_r4.sh >>"$LOG/queue-r4.log" 2>&1 &
echo "== $(date +%T) done"
