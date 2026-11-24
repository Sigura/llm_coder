#!/usr/bin/env bash
# One-off: resumes tmp_pair_queue_ds2.sh after the 2026-11-22 22:30 host hang. Its steps 1 and 3 are done; seeds 2,3
# of ds:ds run now. q8:ds needs Qwen3.8 on GPU 2, which the user is using: it waits until :8086 answers.
set -euo pipefail
cd "$(dirname "$0")"
echo "== $(date +%T) step 1: ds:ds seeds 2,3"
SEEDS="2 3" ./tmp_pair_ds_ds.sh
echo "== $(date +%T) step 2: wait for Qwen3.8 on :8086"
until curl -sf -m 10 -o /dev/null http://127.0.0.1:8086/health; do sleep 60; done
echo "== $(date +%T) step 3: q8:ds seeds 2,3"
SEEDS="2 3" ./tmp_pair_matrix.sh q8:ds
echo "== $(date +%T) done"
