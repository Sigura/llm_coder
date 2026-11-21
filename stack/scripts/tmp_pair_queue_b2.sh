#!/usr/bin/env bash
# One-off: after the Qwen stream (tmp_pair_matrix.sh q6:q8 q8:q6 q8:q8 q6:q6) finishes seeds 2,3, runs the protocol
# variants on the best setups: --tests-first on Qwen3.8 alone-like (q8:q8) and Q8+rDS-like (ds:q8), then
# --keep-unrevised on DeepSeek+DeepSeek. The ds runs share KT's 2 request slots with the DeepSeek stream.
set -euo pipefail
cd "$(dirname "$0")"
echo "== $(date +%T) step 1: wait for the Qwen stream"
while pgrep -f 'tmp_pair_matrix.sh q6:q8 q8:q6 q8:q8 q6:q6' >/dev/null; do sleep 60; done
echo "== $(date +%T) step 2: --tests-first q8:q8 ds:q8 seed 1"
EXTRA="--tests-first" TAG=tdd SEEDS=1 ./tmp_pair_matrix.sh q8:q8 ds:q8
echo "== $(date +%T) step 3: --keep-unrevised ds:ds seed 1"
EXTRA="--keep-unrevised" TAG=keep SEEDS=1 ./tmp_pair_matrix.sh ds:ds
echo "== $(date +%T) done"
