#!/usr/bin/env bash
# One-off: seeds 2,3 of Qwen3.6 MTP navigating DeepSeek (q6:ds), which tied DeepSeek+DeepSeek on seed 1 (26/29) in 71%
# of the time; runs after tmp_pair_queue_b2.sh, sharing KT's 2 slots with the DeepSeek stream.
set -euo pipefail
cd "$(dirname "$0")"
echo "== $(date +%T) step 1: wait for tmp_pair_queue_b2.sh"
while pgrep -f 'tmp_pair_queue_b2[.]sh' >/dev/null; do sleep 60; done
echo "== $(date +%T) step 2: q6:ds seeds 2,3"
SEEDS="2 3" ./tmp_pair_matrix.sh q6:ds
echo "== $(date +%T) done"
