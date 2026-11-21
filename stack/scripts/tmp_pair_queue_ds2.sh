#!/usr/bin/env bash
# One-off: the DeepSeek-bound stream after tmp_pair_queue_ds.sh: finishes seed 1 of q6:ds and q8:ds, then runs the
# OpenCode sh-domain eval
# (eval_opencode.py), the --tests-first pair run of ds:ds seed 1, and seeds 2,3 of ds:ds and q8:ds. Pairs with
# Qwen3.6 MTP get no more seeds (user, 2026-11-21: no winners there).
set -euo pipefail
cd "$(dirname "$0")"
OUT=/home/sigura/llm_coder/llm/results/pair-eval

echo "== $(date +%T) step 1: seed 1 of q6:ds and q8:ds (resumes after the 2026-11-22 01:12 host hang)"
SEEDS=1 ./tmp_pair_matrix.sh q6:ds q8:ds

echo "== $(date +%T) step 2: OpenCode sh domain (build, review, fix)"
python3 eval_opencode.py --tasks 'sh_*' --langs bash --label opencode-sh-ds-s1
echo "== $(date +%T) step 3: --tests-first ds:ds seed 1"
EXTRA="--tests-first" TAG=tdd SEEDS=1 ./tmp_pair_matrix.sh ds:ds
echo "== $(date +%T) step 4: seeds 2,3"
SEEDS="2 3" ./tmp_pair_ds_ds.sh
SEEDS="2 3" ./tmp_pair_matrix.sh q8:ds
echo "== $(date +%T) done"
