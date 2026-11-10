#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: $0 [--dry-run] <model-id>

Starts llama-server for <model-id> in the foreground with the numactl prefix and
arguments derived from config/global.env + config/models/<model-id>.env.
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
require_engine_ref "${MIN_ENGINE_REF:-}"
require_model_verified
[[ -r $KEY_FILE ]] || die "API key $KEY_FILE missing or unreadable (40-install-service.sh creates it)"
[[ ${NUMA_MODE} == interleave || ${NUMA_MODE} == node* ]] && require_cmd numactl

build_server_cmd
info "engine $(readlink -f "$ENGINE_CURRENT"), model $(readlink -f "$MODEL_CURRENT")"
if ((DRY_RUN)); then
    printf '%q ' "${SERVER_CMD[@]}"
    echo
    exit 0
fi
info "exec: ${SERVER_CMD[*]}"
exec "${SERVER_CMD[@]}"
