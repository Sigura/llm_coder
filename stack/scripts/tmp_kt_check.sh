#!/usr/bin/env bash
# One-off: DeepSeek V4.1-1017 FP8 on SGLang + KTransformers (llm/engines/alt/kt-wrapper) with the coding requests of
# the 2026-11-19 MoE cache check (req-2: 8k tokens, req-3: 35k tokens), for a speed comparison with llama.cpp.
# Needs ~420 GiB of RAM: stop deepseek/qwen/evalpair first. Two 4090s (KT's attention needs SM89; the 3090 Ti does
# not run), picked by free memory unless GPUS is set. KEEP=1 leaves the server running on PORT.
# A rerun skips the requests already in results.tsv.
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
NAME=deepseek-v4.1-flash-kt
OUT=$(realpath -m "${OUT:-$RESULTS_DIR/kt-$(date +%F)}")
BASE=http://127.0.0.1:$PORT

info "step 1: check prerequisites"
require_cmd curl jq nvidia-smi python3
[[ -x $KT/.venv/bin/python && -f $KT/engram-adapter/librow_store.so ]] || die "run $KT/setup.sh first"
[[ -f $FP8/config.json ]] || die "no $FP8"
part=$(find "$FP8" -maxdepth 1 -name '*.aria2' | wc -l)
have=$(find "$FP8" -maxdepth 1 -name 'model-*.safetensors' | wc -l)
((part == 0 && have == 48)) || die "FP8 download incomplete: $have/48 shards, $part partial"
for r in "${REQS[@]}"; do [[ -f $REQ_DIR/req-$r.json ]] || die "no $REQ_DIR/req-$r.json"; done
avail=$(awk '/MemAvailable/ {print int($2 / 1048576)}' /proc/meminfo)
((avail >= 430)) || die "only $avail GiB RAM available, KT needs ~420: stop the other model servers"
if [[ -z $GPUS ]]; then
    GPUS=$(nvidia-smi --query-gpu=index,memory.free,name --format=csv,noheader,nounits |
        awk -F', ' '$3 ~ /4090/ {print $2, $1}' | sort -rn | head -2 | cut -d' ' -f2 | sort -n | paste -sd,)
fi
for g in ${GPUS//,/ }; do
    free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i "$g")
    ((free > 20000)) || die "GPU $g has only $free MiB free"
done
info "using GPUs $GPUS, $avail GiB RAM available"
mkdir -p "$OUT"

SRV_PID=""
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

RESULT=$OUT/results.tsv
[[ -s $RESULT ]] || printf 'config\trequest\tprompt_tokens\tprompt_tok_s\toutput_tokens\toutput_tok_s\n' >"$RESULT"
todo=()
for r in "${REQS[@]}"; do
    awk -F'\t' -v r="$r" '$1 == "kt" && $2 == r { f = 1 } END { exit !f }' "$RESULT" || todo+=("$r")
done
((${#todo[@]})) || { info "all requests in $RESULT"; column -t "$RESULT"; exit 0; }

log_file=$OUT/server.log
info "step 2: start KT on GPUs $GPUS, port $PORT, context $CTX (log $log_file; the first launch calibrates the prefill chunk)"
(cd "$KT" && MODEL=$FP8 CUDA_VISIBLE_DEVICES=$GPUS SGLANG_PORT=$PORT SGLANG_SERVED_NAME=$NAME \
    SGLANG_CONTEXT_LENGTH=$CTX exec setsid ./serve.sh --foreground) >"$log_file" 2>&1 &
SRV_PID=$!

info "step 3: wait for the model to load"
for _ in $(seq 1800); do
    kill -0 "$SRV_PID" 2>/dev/null || die "server exited, see $log_file"
    curl -sf -m 5 "$BASE/v1/models" | jq -e --arg n "$NAME" '.data[] | select(.id == $n)' >/dev/null 2>&1 && break
    sleep 4
done
curl -sf -m 5 "$BASE/v1/models" >/dev/null || die "server not up after 2 h, see $log_file"

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

info "step 4: requests ${todo[*]}"
for r in "${todo[@]}"; do
    row=$(measure "$REQ_DIR/req-$r.json" "$OUT/resp-kt-$r.json") || die "request $r failed, see $log_file"
    printf 'kt\t%s\t%s\n' "$r" "$row" | tee -a "$RESULT"
done
info "done: $RESULT"
column -t "$RESULT"
