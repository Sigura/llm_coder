#!/usr/bin/env bash
# One-off: thinking-check replays (2026-11-25), thinking on only for the checking role of each practice's best setup.
# Usage: tmp_thinking_check.sh tests|review|nav [off|think]
#   tests: Qwen3.8 test writer of the best tdd setup (nav Q8 + driver DS): plan + tests turns only, SEEDS (default
#          1 2 3); off on :8086 (thinking forced off), think on :8087 (tmp_qwen38_think_gpu3.sh)
#   review: DeepSeek reviewer of DS+rDS on stored DeepSeek drafts (review_replay.py --mode review), KT :8080
#   nav: DeepSeek navigator of the DS+DS pair, plan + review turns on the same drafts (--mode nav), KT :8080
# Env: EXTRA (more args), OUT (default $RESULTS_DIR/thinking-check).
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh
load_global
what=${1:?usage: $0 tests|review|nav [off|think]} mode=${2:-off}
OUT=${OUT:-$RESULTS_DIR/thinking-check}
read -ra extra <<<"${EXTRA:-}"
DRAFTS=(~/burnish/eval/coding/results/20261115-151845-deepseek-v4.1-flash-rec-s1-part.json
        ~/burnish/eval/coding/results/20261115-192814-deepseek-v4.1-flash-rec-s2.json
        ~/burnish/eval/coding/results/20261115-234512-deepseek-v4.1-flash-rec-s3.json)

echo "== step 1: check prerequisites"
for tool in python3 curl kotlinc; do command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }; done
for f in "${DRAFTS[@]}"; do [[ -r $f ]] || { echo "missing $f" >&2; exit 1; }; done
case $what:$mode in
    tests:off) url=http://127.0.0.1:8086 ;;
    tests:think) url=http://127.0.0.1:8087 ;;
    review:* | nav:*) url=http://127.0.0.1:8080 ;;
    *) echo "unknown: $what $mode" >&2; exit 2 ;;
esac
for try in $(seq 10); do
    curl -sf -m 60 -o /dev/null "$url/health" && break
    (( try < 10 )) || { echo "no server on $url" >&2; exit 1; }
    sleep 30
done

echo "== $(date +%T) step 2: $what $mode"
case $what in
    tests)
        think=() && [[ $mode == think ]] && think=(--nav-think --nav-max-tokens 16000 --tests-max-tokens 24000)
        Q8_URL=$url/v1 OUT=$OUT TAG=testsonly-$mode EXTRA="--tests-only ${think[*]} ${extra[*]}" \
            ./tmp_pair_matrix.sh q8:ds
        ;;
    review | nav)
        think=() && [[ $mode == think ]] && think=(--think --max-tokens 16000)
        python3 review_replay.py --mode "$what" --url "$url/v1" --model deepseek-v4.1-flash \
            --key-file "$SECRETS_DIR/deepseek-v4.1-flash-1017.key" --files "${DRAFTS[@]}" \
            --label "replay-$what-ds-$mode" --out-dir "$OUT" "${think[@]}" "${extra[@]}"
        ;;
esac
echo "== $(date +%T) done"
