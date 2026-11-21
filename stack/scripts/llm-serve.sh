#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: $0 [--dry-run] <model-id>

Starts llama-server for <model-id> in the foreground with the numactl prefix and
arguments derived from config/global.env + config/models/<model-id>.env.
It runs in router mode: nothing is loaded at start, the first request spawns the
model instance, which frees its weights after SLEEP_IDLE_SEC idle seconds.
With WARM_CACHE=1 in the model .env it runs 25-warm-cache.sh <model-id> first.
ENGINE=kt in the model .env runs SGLang + KTransformers (LLM_ROOT/engines/alt/kt-wrapper/serve.sh) instead.
This is the ExecStart of systemd/llm@.service; output goes to stdout/journald.
--dry-run prints the command instead of running it.
EOF
}

MODEL=""
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    -*) die "unknown option $1" ;;
    *) MODEL=$1 ;;
    esac
    shift
done
[[ -n $MODEL ]] || { usage; exit 2; }

load_global
load_model "$MODEL"
if [[ ${ENGINE:-llama.cpp} == kt ]]; then
    # SGLang + KTransformers (llm/engines/alt/kt-wrapper) on the safetensors checkpoint in REV_DIR; the KT_*,
    # SGLANG_* and CUDA_HOME keys of the model .env reach serve.sh through the environment
    KT_DIR=$ENGINES_DIR/alt/kt-wrapper
    [[ -x $KT_DIR/.venv/bin/python ]] || die "no KTransformers build at $KT_DIR; run its setup.sh"
    [[ -e $CUDA_HOME/targets/x86_64-linux/lib/libcudart.so ]] || die "no CUDA runtime under CUDA_HOME=$CUDA_HOME"
    index=$REV_DIR/model.safetensors.index.json
    [[ -f $index ]] || die "no $index; download $HF_REPO@$HF_REVISION"
    missing=$(jq -r '.weight_map[]' "$index" | sort -u | while read -r f; do
        [[ -f $REV_DIR/$f && ! -e $REV_DIR/$f.aria2 ]] || echo "$f"; done | wc -l)
    ((missing == 0)) || die "$missing checkpoint shards missing or partial in $REV_DIR"
    [[ -r $KEY_FILE ]] || die "API key $KEY_FILE missing or unreadable (40-install-service.sh creates it)"
    cmd=(env MODEL="$REV_DIR" CUDA_VISIBLE_DEVICES="$KT_GPUS" SGLANG_HOST="$BIND_HOST" SGLANG_PORT="$PORT"
        SGLANG_SERVED_NAME="$ALIAS" SGLANG_CONTEXT_LENGTH="$CTX" ./serve.sh --foreground)
    info "KTransformers $KT_DIR, GPUs $KT_GPUS, model $REV_DIR"
    if ((DRY_RUN)); then
        printf '%q ' "${cmd[@]}"
        echo
        exit 0
    fi
    SGLANG_API_KEY=$(<"$KEY_FILE")
    export SGLANG_API_KEY
    cd "$KT_DIR"
    exec "${cmd[@]}"
fi
require_engine_ref "${MIN_ENGINE_REF:-}"
require_model_verified
[[ -r $KEY_FILE ]] || die "API key $KEY_FILE missing or unreadable (40-install-service.sh creates it)"
[[ ${NUMA_MODE} == interleave || ${NUMA_MODE} == node* ]] && require_cmd numactl

build_server_cmd
# Router mode: the model comes from a preset whose section name is the alias the clients request; every
# other argument given to the router is passed on to the instance it spawns.
PRESET=$STATE_DIR/$MODEL.preset.ini
cmd=()
for ((i = 0; i < ${#SERVER_CMD[@]}; i++)); do
    case ${SERVER_CMD[i]} in
    -m | --alias) i=$((i + 1)) ;;
    *) cmd+=("${SERVER_CMD[i]}") ;;
    esac
done
SERVER_CMD=("${cmd[@]}" --models-preset "$PRESET" --models-max 1 --sleep-idle-seconds "$SLEEP_IDLE_SEC")
preset=$(printf '[%s]\nmodel = %s\n' "$ALIAS" "$MODEL_PATH")
info "engine $(readlink -f "$ENGINE_CURRENT"), model $(readlink -f "$MODEL_CURRENT")"
if ((DRY_RUN)); then
    printf '%s:\n%s\n' "$PRESET" "$preset"
    printf '%q ' "${SERVER_CMD[@]}"
    echo
    exit 0
fi
echo "$preset" >"$PRESET"
[[ ${WARM_CACHE:-0} == 1 ]] && "$STACK_DIR/scripts/25-warm-cache.sh" "$MODEL"
info "exec: ${SERVER_CMD[*]}"
exec "${SERVER_CMD[@]}"
