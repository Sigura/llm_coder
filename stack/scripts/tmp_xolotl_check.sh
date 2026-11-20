#!/usr/bin/env bash
# One-off: DeepSeek V4.1 (our UD-Q2_K_XL) on Xolotl's engine (llm/engines/alt/xolotl) on one GPU, with the coding
# requests of the 2026-11-19 MoE cache check (req-2: 8k tokens, req-3: 35k tokens), for a speed comparison with
# llama.cpp. Xolotl cannot read Unsloth's Q5_K Engram tables, so --engram points at the FP8 repo's shards 47+48.
# Usage: tmp_xolotl_check.sh [config...]   config = exact (route bias 0, same routing as the model) | bias (Xolotl's
# default decode route bias 1.0 / file penalty 0.6: faster, lossy). KEEP=1 leaves the last server running on PORT
# for a quality run against it. A rerun skips the config/request pairs already in results.tsv.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_global

XOL=$LLM_ROOT/engines/alt/xolotl
GGUF=$LLM_ROOT/models/deepseek-v4.1-flash-1017/current/UD-Q2_K_XL/DeepSeek-V4.1-Flash-1017-UD-Q2_K_XL-00001-of-00007.gguf
FP8=$LLM_ROOT/models/deepseek-v4.1-flash-1017-fp8/08c8657f02291e11b6f6b63e0e16014f8e748518
TOK=$LLM_ROOT/models/xolotl-ds41-tokenizer
REQ_DIR=$LLM_ROOT/results/moe-cache-2026-11-19/check
GPU=${GPU:-}
PORT=${PORT:-8150}
CTX=${CTX:-65536}
ARENA_GIB=${ARENA_GIB:-128}
REQS=(${REQS:-2 3})
OUT=$(realpath -m "${OUT:-$RESULTS_DIR/xolotl-$(date +%F)}")
declare -A ROUTE=([exact]="--route-bias 0 --route-bias-file 0" [bias]="--route-bias 1.0 --route-bias-file 0.6")
ORDER=(exact bias)
(($#)) && ORDER=("$@")
BASE=http://127.0.0.1:$PORT

info "step 1: check prerequisites"
require_cmd curl jq nvidia-smi
[[ -x $XOL/build-xolotl/ds41_generate ]] || die "no $XOL/build-xolotl/ds41_generate"
[[ -x $XOL/.venv/bin/python ]] || die "no $XOL/.venv (uv venv + uv pip install -r requirements.txt)"
[[ -f $GGUF ]] || die "no $GGUF"
[[ -f $TOK/vocab.json ]] || die "no $TOK: run tools/v41/serve/export_tokenizer.py $FP8 $TOK"
for s in 47 48; do
    f=$FP8/model-000$s-of-00048.safetensors
    [[ -f $f && ! -e $f.aria2 ]] || die "FP8 shard $s not complete (Engram tables)"
done
for r in "${REQS[@]}"; do [[ -f $REQ_DIR/req-$r.json ]] || die "no $REQ_DIR/req-$r.json"; done
if [[ -z $GPU ]]; then
    # the GPU with the most free memory; a 4090 over the power-capped 3090 Ti when equal
    GPU=$(nvidia-smi --query-gpu=index,memory.free,name --format=csv,noheader,nounits |
        awk -F', ' '{print $2 + ($3 ~ /4090/ ? 1 : 0), $1}' | sort -rn | head -1 | cut -d' ' -f2)
fi
free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i "$GPU")
((free > 16000)) || die "GPU $GPU has only $free MiB free"
info "using GPU $GPU ($free MiB free)"
mkdir -p "$OUT"

SRV_PID=""
stop_server() {
    [[ -n $SRV_PID ]] || return 0
    kill "$SRV_PID" 2>/dev/null || true
    for _ in $(seq 120); do kill -0 "$SRV_PID" 2>/dev/null || break; sleep 1; done
    kill -9 "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
    SRV_PID=""
}
trap '[[ ${KEEP:-0} == 1 ]] || stop_server' EXIT

RESULT=$OUT/results.tsv
[[ -s $RESULT ]] || printf 'config\trequest\tprompt_tokens\tprompt_tok_s\toutput_tokens\toutput_tok_s\n' >"$RESULT"
for label in "${ORDER[@]}"; do
    [[ -n ${ROUTE[$label]:-} ]] || die "unknown config $label"
    todo=()
    for r in "${REQS[@]}"; do
        awk -F'\t' -v l="$label" -v r="$r" '$1 == l && $2 == r { f = 1 } END { exit !f }' "$RESULT" || todo+=("$r")
    done
    ((${#todo[@]})) || { info "$label: all requests in $RESULT, skipped"; continue; }
    cfg=$OUT/xolotl-$label.json
    jq -n --arg exe "$XOL/build-xolotl/ds41_generate" --arg cwd "$XOL" --arg m "$GGUF" --arg engram "$FP8" \
        --arg tok "$TOK" --arg log "$OUT/engine-$label.log" --argjson gpu "$GPU" --argjson port "$PORT" \
        --arg ctx "$CTX" --arg arena "$ARENA_GIB" --arg route "${ROUTE[$label]}" '{
        exe: $exe, cwd: $cwd, tokenizer: $tok, model_name: "deepseek-v4.1-flash-xolotl", log: $log, port: $port,
        gpu: $gpu, api_monitor: false,
        args: (["-m", $m, "--backend", "cuda", "--experts", "gpu", "--engram", $engram, "--ctx", $ctx, "--stop", "1",
                "--arena-gib", $arena, "--arena-adapt", "--prompt-batch", "4096"] + ($route | split(" "))),
        env: {STRATA_NO_LARGEPAGES: "1", STRATA_SERVE_STEP_MAX: "96", STRATA_SERVE_PASS_BIAS: "0",
              STRATA_SERVE_DSPARK: ""}}' >"$cfg"
    log_file=$OUT/server-$label.log
    info "step 2/$label: start Xolotl on GPU $GPU, port $PORT ($cfg)"
    (cd "$XOL" && exec .venv/bin/python tools/v41/serve/serve_ds41.py --engine strata --config "$cfg" \
        --port "$PORT" --host 127.0.0.1) >"$log_file" 2>&1 &
    SRV_PID=$!
    info "step 3/$label: wait for the model to load (log $log_file)"
    for _ in $(seq 1800); do
        kill -0 "$SRV_PID" 2>/dev/null || die "server $label exited, see $log_file"
        [[ $(curl -sf -m 5 "$BASE/health" | jq -r .loaded 2>/dev/null) == true ]] && break
        sleep 2
    done
    [[ $(curl -sf -m 5 "$BASE/health" | jq -r .loaded 2>/dev/null) == true ]] || die "server $label not loaded after 1 h"
    info "step 4/$label: requests ${todo[*]}"
    for r in "${todo[@]}"; do
        jq '.model = "deepseek-v4.1-flash-xolotl"' "$REQ_DIR/req-$r.json" |
            curl -sf -m 3600 -H 'Content-Type: application/json' -d @- "$BASE/v1/chat/completions" \
                >"$OUT/resp-$label-$r.json" || die "request $r failed, see $log_file"
        jq -r --arg l "$label" --arg r "$r" '[$l, $r, .timings.prompt_n, .timings.prompt_per_second,
            .timings.predicted_n, .timings.predicted_per_second] | @tsv' "$OUT/resp-$label-$r.json" | tee -a "$RESULT"
    done
    [[ ${KEEP:-0} == 1 && $label == "${ORDER[-1]}" ]] || stop_server
done
info "done: $RESULT"
column -t "$RESULT"
