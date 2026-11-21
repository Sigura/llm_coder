#!/usr/bin/env bash
# One-off: the DeepSeek-bound queue of the pair-programming matrix, seed 1 of every combination first. Waits for the
# running tmp_pair_ds_ds.sh to finish its seed 1 and stops it, then runs ds:q6, q6:ds, q8:ds seed 1, then seeds 2,3
# of DeepSeek+DeepSeek and of those three. Everything resumes from eval_pair.py's partial files.
set -euo pipefail
cd "$(dirname "$0")"
OUT=/home/sigura/llm_coder/llm/results/pair-eval
COMBOS=(ds:q6 q6:ds q8:ds)

echo "== $(date +%T) step 1: wait for DeepSeek+DeepSeek seed 1"
until ls "$OUT"/*-pair-deepseek-nav-deepseek-kt-s1.json >/dev/null 2>&1; do
    pgrep -f tmp_pair_ds_ds.sh >/dev/null || { echo "tmp_pair_ds_ds.sh is not running and seed 1 is not done" >&2; exit 1; }
    sleep 30
done
# its seed 2 has just started; it resumes from the partial file below
pkill -f 'tmp_pair_ds_ds.sh' || true
pkill -f 'eval_pair.py .*--label pair-deepseek-nav-deepseek-kt-s2' || true
sleep 5

echo "== $(date +%T) step 2: seed 1 of ${COMBOS[*]}"
SEEDS=1 ./tmp_pair_matrix.sh "${COMBOS[@]}"
echo "== $(date +%T) step 3: seeds 2,3"
SEEDS="2 3" ./tmp_pair_ds_ds.sh
SEEDS="2 3" ./tmp_pair_matrix.sh "${COMBOS[@]}"
echo "== $(date +%T) done"
