#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: sudo $0 [--dry-run] [--skip-long] <model-id>

Installs/updates the systemd template unit llm@.service (rendered from systemd/llm@.service),
creates the model's API key if missing, enables and (re)starts llm@<model-id>, then runs
50-healthcheck.sh. The install only counts as done (state fingerprint written) when the
health check passes. Re-running with nothing changed and a healthy service does nothing.
  --skip-long   pass --skip-long to the health check (install is then NOT marked done)
EOF
}

MODEL=""
SKIP_LONG=0
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    --skip-long) SKIP_LONG=1 ;;
    -*) die "unknown option $1" ;;
    *) MODEL=$1 ;;
    esac
    shift
done
[[ -n $MODEL ]] || { usage; exit 2; }

load_global
load_model "$MODEL"
require_root "$@"
init_logging "$MODEL_ID"
require_cmd systemctl sha256sum curl jq
require_engine_ref "${MIN_ENGINE_REF:-}"
require_model_verified
if [[ $NUMA_MODE == interleave || $NUMA_MODE == node* ]]; then require_cmd numactl; fi
[[ $N_CPU_MOE == 999 ]] && warn "N_CPU_MOE=999 (untuned, all experts on CPU); run: make bench M=$MODEL_ID"

UNIT=/etc/systemd/system/llm@.service
rendered=$(sed -e "s|@LLM_ROOT@|$LLM_ROOT|g" -e "s|@STACK_DIR@|$STACK_DIR|g" -e "s|@LLM_USER@|$LLM_USER|g" "$STACK_DIR/systemd/llm@.service")
if [[ -f $UNIT && $(<"$UNIT") == "$rendered" ]]; then
    info "$UNIT unchanged"
elif ((DRY_RUN)); then
    info "[dry-run] would install $UNIT and run systemctl daemon-reload"
else
    printf '%s\n' "$rendered" >"$UNIT.tmp"
    mv -f "$UNIT.tmp" "$UNIT"
    run systemctl daemon-reload
    info "installed $UNIT"
fi

ensure_key

if port_in_use "$PORT" && ! service_active "$SERVICE"; then
    die "port $PORT is in use by something other than $SERVICE"
fi

fingerprint() {
    {
        cat "$GLOBAL_ENV" "$MODEL_ENV" "$SCRIPTS_DIR/llm-serve.sh" "$SCRIPTS_DIR/lib.sh"
        printf '%s\n' "$rendered"
        readlink -f "$ENGINE_CURRENT"
        readlink -f "$MODEL_CURRENT"
    } | sha256sum | cut -d' ' -f1
}
FP=$(fingerprint)
FP_FILE=$STATE_DIR/$MODEL_ID.installed

if [[ -f $FP_FILE && $(<"$FP_FILE") == "$FP" ]] && service_active "$SERVICE" && ((!DRY_RUN)) &&
    "$SCRIPTS_DIR/50-healthcheck.sh" --skip-long "$MODEL_ID"; then
    info "$SERVICE already installed with this configuration and healthy; nothing to do"
    exit 0
fi

systemctl is-enabled --quiet "$SERVICE" 2>/dev/null || run systemctl enable "$SERVICE"
run systemctl restart "$SERVICE"
if ((DRY_RUN)); then
    info "[dry-run] would wait for $SERVICE, run 50-healthcheck.sh and record $FP_FILE"
    exit 0
fi

info "waiting up to ${SERVER_READY_TIMEOUT}s for $SERVICE to load the model"
if ! wait_ready "http://127.0.0.1:$PORT" "$SERVER_READY_TIMEOUT"; then
    journalctl -u "$SERVICE" -n 40 --no-pager >&2 || true
    die "$SERVICE did not become ready; see: journalctl -u $SERVICE"
fi
service_active "$SERVICE" || die "$SERVICE is not active"

hc_args=()
((SKIP_LONG)) && hc_args+=(--skip-long)
"$SCRIPTS_DIR/50-healthcheck.sh" "${hc_args[@]}" "$MODEL_ID" || die "health check failed; service left running for debugging (rollback: make rollback M=$MODEL_ID or E=1)"

if ((SKIP_LONG)); then
    warn "long-context check skipped: not recording the install as done"
else
    install -d -o "$LLM_USER" -g "$LLM_USER" "$STATE_DIR"
    echo "$FP" >"$FP_FILE"
    info "$SERVICE installed and healthy"
fi
