#!/usr/bin/env bash
# One-off: takes over the DeepSeek-bound stream from tmp_pair_queue_ds.sh once seed 1 of q6:ds and q8:ds is done:
# stops it (its seed 2 resumes later from the partial file), then runs the OpenCode sh-domain eval
# (eval_opencode.py), the --tests-first pair run of ds:ds seed 1, and the remaining seeds 2,3.
set -euo pipefail
cd "$(dirname "$0")"
OUT=/home/sigura/llm_coder/llm/results/pair-eval
COMBOS=(ds:q6 q6:ds q8:ds)

echo "== $(date +%T) step 1: wait for seed 1 of q6:ds and q8:ds"
for label in pair-deepseek-kt-nav-qwen3.6mtp-s1 pair-deepseek-kt-nav-qwen3.8-s1; do
    until ls "$OUT"/*-"$label".json >/dev/null 2>&1; do
        pgrep -f tmp_pair_queue_ds.sh >/dev/null || { echo "tmp_pair_queue_ds.sh died before $label" >&2; exit 1; }
        sleep 30
    done
done
pkill -f tmp_pair_queue_ds.sh || true
pkill -f tmp_pair_ds_ds.sh || true
pkill -f 'tmp_pair_matrix.sh ds:q6 q6:ds q8:ds' || true
pkill -f 'eval_pair.py .*--label pair-deepseek-nav-deepseek-kt-s2' || true
sleep 5

echo "== $(date +%T) step 2: OpenCode sh domain (build, review, fix)"
python3 eval_opencode.py --tasks 'sh_*' --langs bash --label opencode-sh-ds-s1
echo "== $(date +%T) step 3: --tests-first ds:ds seed 1"
EXTRA="--tests-first" TAG=tdd SEEDS=1 ./tmp_pair_matrix.sh ds:ds
echo "== $(date +%T) step 4: seeds 2,3"
SEEDS="2 3" ./tmp_pair_ds_ds.sh
SEEDS="2 3" ./tmp_pair_matrix.sh "${COMBOS[@]}"
echo "== $(date +%T) done"
