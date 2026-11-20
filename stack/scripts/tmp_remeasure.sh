#!/usr/bin/env bash
# One-off: remeasure after the host's power changes (2026-11-20: C2 off, undervolting). Waits until GPUs 0,1 are free
# (deepseek service stopped), then llama.cpp DeepSeek (no cache, MoE cache, current env) and Xolotl (exact, bias) on
# the same two requests. Both steps skip rows already in their results.tsv, so a rerun resumes.
set -euo pipefail
cd "$(dirname "$0")"
OUT=${OUT:-/home/sigura/llm_coder/llm/results/remeasure-$(date +%F)}

echo "== $(date +%T) wait for GPUs 0,1 to be free"
while nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -i 0,1 | awk '$1 >= 2000 { busy = 1 } END { exit !busy }'; do
    sleep 30
done
echo "== $(date +%T) llama.cpp DeepSeek"
OUT=$OUT/llama REQS="2 3" ./tmp_moe_cache_check.sh base cpu-23936-0.95 ub4096-17920
echo "== $(date +%T) Xolotl"
OUT=$OUT/xolotl ARENA_GIB=${ARENA_GIB:-190} ./tmp_xolotl_check.sh exact bias
echo "== $(date +%T) done: $OUT; start the deepseek service again"
