#!/usr/bin/env bash
# One-off (replaces tmp_pair_queue_r5.sh, Nov 23 21:30; user: headline DeepSeek-written setups first, other practices
# to n=3). KT's two slots, each stream starts when its DeepSeek + reviewer run (tmp_review_seeds.sh) has all 3 seeds:
#   A: after ds:q8 review -> --tests-first ds:ds seeds 2,3 (s2 resumes from its partial), then tmp_pair_queue_r3.sh
#      (ds:q8 s3 resumes, --tests-first ds:q8 s2,s3: Qwen3.8-written, last)
#   B: after ds:ds review -> --tests-first q8:ds seeds 1,2,3 (Qwen3.8 navigates, DeepSeek writes)
set -euo pipefail
cd "$(dirname "$0")"
RES=$HOME/burnish/eval/coding/results
LOG=/home/sigura/llm_coder/llm/results/pair-eval

wait_review() { # <reviewer model>
    local s
    for s in 1 2 3; do
        until ls "$RES"/*-deepseek-v4.1-flash-review-"$1"-s"$s".json >/dev/null 2>&1; do sleep 300; done
    done
}

stream_a() {
    echo "== $(date +%T) A step 1: wait for ds:q8 review seeds 1-3"
    wait_review qwen3.8-27b
    echo "== $(date +%T) A step 2: --tests-first ds:ds seeds 2,3"
    EXTRA="--tests-first" TAG=tdd SEEDS="2 3" ./tmp_pair_matrix.sh ds:ds
    echo "== $(date +%T) A step 3: tmp_pair_queue_r3.sh"
    ./tmp_pair_queue_r3.sh
    echo "== $(date +%T) A done"
}

stream_b() {
    echo "== $(date +%T) B step 1: wait for ds:ds review seeds 1-3"
    wait_review deepseek-v4.1-flash
    echo "== $(date +%T) B step 2: --tests-first q8:ds seeds 1,2,3"
    EXTRA="--tests-first" TAG=tdd SEEDS="1 2 3" ./tmp_pair_matrix.sh q8:ds
    echo "== $(date +%T) B done"
}

stream_a >>"$LOG/queue-r6a.log" 2>&1 &
stream_b >>"$LOG/queue-r6b.log" 2>&1 &
wait
echo "== $(date +%T) done"
