#!/usr/bin/env bash
# One-off: remeasure, DeepSeek-navigator stream on KT's first slot once tmp_pair_queue_ds3.sh (q8:ds) finishes:
# ds:q8 seeds 2,3, then --tests-first ds:q8 seeds 2,3. Qwen3.8 on :8086.
set -euo pipefail
cd "$(dirname "$0")"
echo "== $(date +%T) step 1: wait for tmp_pair_queue_ds3.sh"
while pgrep -f 'tmp_pair_queue_ds3[.]sh' >/dev/null; do sleep 60; done
echo "== $(date +%T) step 2: ds:q8 seeds 2,3"
SEEDS="2 3" ./tmp_pair_matrix.sh ds:q8
echo "== $(date +%T) step 3: --tests-first ds:q8 seeds 2,3"
EXTRA="--tests-first" TAG=tdd SEEDS="2 3" ./tmp_pair_matrix.sh ds:q8
echo "== $(date +%T) done"
