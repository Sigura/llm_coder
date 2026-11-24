#!/usr/bin/env bash
# One-off (Nov 24 12:30): restart of tmp_pair_queue_r6.sh stream B after --tests-first q8:ds s1 died at 12:03 on a
# driver request past eval_pair.py's 1 h timeout (now 2 h). s1 resumes from its partial; then s2, s3.
set -euo pipefail
cd "$(dirname "$0")"
echo "== $(date +%T) B' step 1: --tests-first q8:ds seeds 1,2,3 (s1 resumes)"
EXTRA="--tests-first" TAG=tdd SEEDS="1 2 3" ./tmp_pair_matrix.sh q8:ds
echo "== $(date +%T) B' done"
