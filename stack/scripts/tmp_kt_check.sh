#!/usr/bin/env bash
# One-off: DeepSeek V4.1-1017 FP8 on SGLang + KTransformers (llm/engines/alt/kt-wrapper) with the coding requests of
# the 2026-11-19 MoE cache check (req-2: 8k tokens, req-3: 35k tokens), for a speed comparison with llama.cpp.
# Needs ~420 GiB of RAM: stop deepseek/qwen/evalpair first. One or two 4090s (KT's attention needs SM89; the 3090 Ti does
# not run) with 16 GB free each (TP 1 or 2), picked by free memory unless GPUS is set. serve.sh's knobs (KT_CPU_THREADS,
# SGLANG_MAX_RUNNING_REQUESTS, ...) pass through the environment.
# Env: LABEL (results row name, default kt), KEEP=1 leaves the server running (its process group id in
# OUT/server-LABEL.pgid), ATTACH=1 measures against the server already on PORT, WARMUP=1 sends one unrecorded request
# first (the first request after a launch is slower), PARALLEL=1 sends the requests at once, REPEAT=1 sends each one a
# second time without flushing the prefix cache (row <r>-again), EVICT=1 drops the checkpoint's page cache before each
# request. The prefix cache is flushed before every other request. A rerun skips the rows already in results.tsv.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_global

KT=$LLM_ROOT/engines/alt/kt-wrapper
FP8=$LLM_ROOT/models/deepseek-v4.1-flash-1017-fp8/08c8657f02291e11b6f6b63e0e16014f8e748518
REQ_DIR=$LLM_ROOT/results/moe-cache-2026-11-19/check
GPUS=${GPUS:-}
PORT=${PORT:-8160}
CTX=${CTX:-65536}
REQS=(${REQS:-2 3})
LABEL=${LABEL:-kt}
NAME=deepseek-v4.1-flash-kt
OUT=$(realpath -m "${OUT:-$RESULTS_DIR/kt-$(date +%F)}")
BASE=http://127.0.0.1:$PORT
KT_CUDA_HOME=${KT_CUDA_HOME:-${CONDA_PREFIX:-}}
ATTACH=${ATTACH:-0}

info "step 1: check prerequisites"
require_cmd curl jq nvidia-smi python3
for r in "${REQS[@]}"; do [[ -f $REQ_DIR/req-$r.json ]] || die "no $REQ_DIR/req-$r.json"; done
mkdir -p "$OUT"
RESULT=$OUT/results.tsv
[[ -s $RESULT ]] || printf 'config\trequest\tprompt_tokens\tprompt_tok_s\toutput_tokens\toutput_tok_s\n' >"$RESULT"
has_row() { awk -F'\t' -v l="$LABEL" -v r="$1" '$1 == l && $2 == r { f = 1 } END { exit !f }' "$RESULT"; }
todo=()
for r in "${REQS[@]}"; do
    { has_row "$r" && { [[ ${REPEAT:-0} != 1 ]] || has_row "$r-again"; }; } || todo+=("$r")
done
# KEEP=1 without ATTACH still starts the server when every row is there, for callers that use it afterwards
((${#todo[@]})) || [[ ${KEEP:-0} == 1 && $ATTACH == 0 ]] || { info "$LABEL: all requests in $RESULT"; exit 0; }

SRV_PID=""
log_file=$OUT/server-$LABEL.log
if ((ATTACH)); then
    curl -sf -m 5 "$BASE/v1/models" >/dev/null || die "ATTACH=1: no server on $BASE"
else
    [[ -x $KT/.venv/bin/python && -f $KT/engram-adapter/librow_store.so ]] || die "run $KT/setup.sh first"
    [[ -f $FP8/config.json ]] || die "no $FP8"
    [[ -e $KT_CUDA_HOME/targets/x86_64-linux/lib/libcudart.so ]] || die "no CUDA runtime under KT_CUDA_HOME=$KT_CUDA_HOME"
    part=$(find "$FP8" -maxdepth 1 -name '*.aria2' | wc -l)
    have=$(find "$FP8" -maxdepth 1 -name 'model-*.safetensors' | wc -l)
    ((part == 0 && have == 48)) || die "FP8 download incomplete: $have/48 shards, $part partial"
    ! curl -s -m 3 -o /dev/null "$BASE/health" || die "something already serves on $BASE"
    avail=$(awk '/MemAvailable/ {print int($2 / 1048576)}' /proc/meminfo)
    ((avail >= 430)) || die "only $avail GiB RAM available, KT needs ~420: stop the other model servers"
    if [[ -z $GPUS ]]; then
        GPUS=$(nvidia-smi --query-gpu=index,memory.free,name --format=csv,noheader,nounits |
            awk -F', ' '$3 ~ /4090/ && $2 > 16000 {print $2, $1}' | sort -rn | head -2 | cut -d' ' -f2 | sort -n | paste -sd,)
    fi
    [[ -n $GPUS ]] || die "no 4090 with 16 GB free"
    for g in ${GPUS//,/ }; do
        free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i "$g")
        ((free > 16000)) || die "GPU $g has only $free MiB free"
    done
    info "using GPUs $GPUS, $avail GiB RAM available"
fi

stop_server() {
    [[ -n $SRV_PID ]] || return 0
    # setsid made serve.sh a process group leader: the group holds SGLang's scheduler and worker processes too
    kill -TERM -- "-$SRV_PID" 2>/dev/null || true
    for _ in $(seq 120); do kill -0 -- "-$SRV_PID" 2>/dev/null || break; sleep 1; done
    kill -KILL -- "-$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
    SRV_PID=""
}
trap '[[ ${KEEP:-0} == 1 ]] || stop_server' EXIT

if ((!ATTACH)); then
    info "step 2: start KT on GPUs $GPUS, port $PORT, context $CTX (log $log_file; the first launch calibrates the prefill chunk)"
    # the container's CUDA toolkit is the conda env (no /usr/local/cuda): engram-adapter loads libcudart from CUDA_HOME
    (cd "$KT" && MODEL=$FP8 CUDA_HOME=$KT_CUDA_HOME CUDA_VISIBLE_DEVICES=$GPUS SGLANG_PORT=$PORT SGLANG_SERVED_NAME=$NAME \
        SGLANG_CONTEXT_LENGTH=$CTX exec setsid ./serve.sh --foreground) >"$log_file" 2>&1 &
    SRV_PID=$!
    [[ ${KEEP:-0} != 1 ]] || echo "$SRV_PID" >"$OUT/server-$LABEL.pgid"

    info "step 3: wait for the model to load"
    for _ in $(seq 1800); do
        kill -0 "$SRV_PID" 2>/dev/null || die "server exited, see $log_file"
        # the calibration launch serves on the same port; serve.sh prints "Run directory:" only for the real one
        grep -q '^Run directory: ' "$log_file" && curl -sf -m 5 "$BASE/v1/models" | jq -e --arg n "$NAME" '.data[] | select(.id == $n)' >/dev/null 2>&1 && break
        sleep 4
    done
    curl -sf -m 5 "$BASE/v1/models" >/dev/null || die "server not up after 2 h, see $log_file"
    # where the CPU expert pools' memory landed (per NUMA node), to see whether their binding works in the container
    numastat -p "$(pgrep -d, -f 'sglang' || echo 0)" >"$OUT/numastat-$LABEL.txt" 2>&1 || true
fi

# SGLang has no llama.cpp-style timings: prompt speed = prompt tokens / time to the first streamed token,
# output speed = (output tokens - 1) / time from the first to the last token
measure() {
    python3 -I - "$1" "$BASE/v1/chat/completions" "$NAME" "$2" <<'EOF'
import json, sys, time, urllib.request
req, url, name, out = sys.argv[1:]
body = json.load(open(req))
body.update(model=name, stream=True, stream_options={"include_usage": True})
t0 = time.time(); first = last = None; usage = None; text = []
r = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
with urllib.request.urlopen(r, timeout=3600) as resp:
    for line in resp:
        line = line.strip()
        if not line.startswith(b"data:") or line == b"data: [DONE]":
            continue
        ev = json.loads(line[5:])
        usage = ev.get("usage") or usage
        for c in ev.get("choices", []):
            d = c.get("delta", {})
            piece = (d.get("reasoning_content") or "") + (d.get("content") or "")
            if piece:
                last = time.time(); first = first or last; text.append(piece)
pt, ct = usage["prompt_tokens"], usage["completion_tokens"]
json.dump({"usage": usage, "ttft_s": first - t0, "decode_s": last - first, "text": "".join(text)}, open(out, "w"))
print(f"{pt}\t{pt / (first - t0):.2f}\t{ct}\t{(ct - 1) / (last - first):.2f}")
EOF
}
# right after a request the scheduler still reports it pending for a moment: timeout= waits until it is idle
flush_cache() { curl -sf -m 200 -X POST "$BASE/flush_cache?timeout=180" >/dev/null || die "flush_cache failed"; }
evict_checkpoint() {
    find "$FP8" -type f -print0 | while IFS= read -r -d '' f; do dd if="$f" iflag=nocache count=0 status=none; done
}
record() { # <request id> <req file>
    local row
    row=$(measure "$2" "$OUT/resp-$LABEL-$1.json") || die "request $1 failed, see $log_file"
    printf '%s\t%s\t%s\n' "$LABEL" "$1" "$row" | tee -a "$RESULT"
}

if [[ ${WARMUP:-0} == 1 ]]; then
    info "step 4: warm-up request (not recorded)"
    measure "$REQ_DIR/req-2.json" "$OUT/resp-$LABEL-warmup.json" >/dev/null || die "warm-up failed, see $log_file"
fi
info "step 5: $LABEL requests ${todo[*]}"
flush_cache
if [[ ${PARALLEL:-0} == 1 ]]; then
    [[ ${EVICT:-0} != 1 ]] || evict_checkpoint
    pids=()
    for r in "${todo[@]}"; do record "$r" "$REQ_DIR/req-$r.json" & pids+=($!); done
    for p in "${pids[@]}"; do wait "$p" || die "a parallel request failed"; done
else
    for r in "${todo[@]}"; do
        flush_cache
        [[ ${EVICT:-0} != 1 ]] || evict_checkpoint
        if ! has_row "$r"; then
            record "$r" "$REQ_DIR/req-$r.json"
        elif [[ ${REPEAT:-0} == 1 ]]; then
            # resumed after the first send: fill the prefix cache again before the repeat
            measure "$REQ_DIR/req-$r.json" "$OUT/resp-$LABEL-$r-fill.json" >/dev/null || die "request $r failed, see $log_file"
        fi
        [[ ${REPEAT:-0} != 1 ]] || has_row "$r-again" || record "$r-again" "$REQ_DIR/req-$r.json"
    done
fi
info "done: $RESULT"
column -t "$RESULT"
