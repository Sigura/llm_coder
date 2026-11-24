#!/usr/bin/env bash
# One-off: seeds of the solo + reviewer setups (burnish run_coding_eval.py --review-url); writer sampling as in the
# solo runs (Qwen: seed-1 review settings of 2026-11-15, DeepSeek: the deepseek-v4.1-flash-rec runs). API keys come
# from $SECRETS_DIR via run_coding_eval.py --key-file / --review-key-file.
# Usage: tmp_review_seeds.sh [WRITER:]REVIEWER   WRITER q8 (default) | ds | q6, REVIEWER q8 | q6 | ds
#   Env: SEEDS (default 2 3), Q8_URL (Qwen3.8 server, default :8086)
#   q8 = Qwen3.8 (:8086), q6 = Qwen3.6 MTP (:8085), ds = DeepSeek (KT :8080; the q8:ds seed 1 had llama.cpp)
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh
load_global
SEEDS=${SEEDS:-2 3}
EVAL=$HOME/burnish/eval/coding/run_coding_eval.py
RES=$HOME/burnish/eval/coding/results
q8url=${Q8_URL:-http://127.0.0.1:8086/v1}
q8url=${q8url%/v1}
spec=${1:-}
[[ $spec == *:* ]] || spec=q8:$spec
writer=${spec%%:*} reviewer=${spec#*:}
qwen_sampling=(--temperature 0.7 --top-p 0.8 --top-k 20 --min-p 0 --presence-penalty 1.5)
case $writer in
    q8) wurl=$q8url wmodel=qwen3.8-27b wkey=qwen3.8-27b sampling=("${qwen_sampling[@]}") ;;
    q6) wurl=http://127.0.0.1:8085 wmodel=qwen3.6-35b-a3b-mtp wkey=qwen3.6-35b-a3b-mtp sampling=("${qwen_sampling[@]}") ;;
    ds) wurl=http://127.0.0.1:8080 wmodel=deepseek-v4.1-flash wkey=deepseek-v4.1-flash-1017 sampling=(--temperature 1.0 --top-p 1.0) ;;
    *) echo "usage: $0 [q8|ds|q6:]q8|q6|ds" >&2; exit 2 ;;
esac
case $reviewer in
    q8) rurl=$q8url rmodel=qwen3.8-27b rkey=qwen3.8-27b ;;
    q6) rurl=http://127.0.0.1:8085 rmodel=qwen3.6-35b-a3b-mtp rkey=qwen3.6-35b-a3b-mtp ;;
    ds) rurl=http://127.0.0.1:8080 rmodel=deepseek-v4.1-flash rkey=deepseek-v4.1-flash-1017 ;;
    *) echo "usage: $0 [q8|ds|q6:]q8|q6|ds" >&2; exit 2 ;;
esac
echo "== $(date +%T) step 1: check prerequisites ($writer writes, $reviewer reviews)"
for tool in python3 bash kotlinc curl; do command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }; done
[[ -f $EVAL ]] || { echo "missing $EVAL" >&2; exit 1; }
wkey=$SECRETS_DIR/$wkey.key rkey=$SECRETS_DIR/$rkey.key
for k in "$wkey" "$rkey"; do [[ -r $k ]] || { echo "no key file $k" >&2; exit 1; }; done
# KT answers 503 to /health while a long prefill blocks its detokenizer heartbeat: retry before giving up
for u in "$wurl" "$rurl"; do
    for try in $(seq 10); do
        curl -sf -m 60 -o /dev/null "$u/health" && break
        (( try < 10 )) || { echo "no server on $u" >&2; exit 1; }
        sleep 30
    done
done
for seed in $SEEDS; do
    label=$wmodel-review-$rmodel-s$seed
    if ls "$RES"/*-"$label".json >/dev/null 2>&1; then
        echo "== $label already done"
        continue
    fi
    echo "== $(date +%T) step 2: $label"
    python3 "$EVAL" --url "$wurl" --model "$wmodel" --label "$label" --langs python,bash,kotlin --attempts 2 \
        --seed "$seed" "${sampling[@]}" --max-tokens 32768 \
        --key-file "$wkey" --review-url "$rurl" --review-model "$rmodel" --review-key-file "$rkey" --no-think
done
echo "== $(date +%T) done ($spec)"
