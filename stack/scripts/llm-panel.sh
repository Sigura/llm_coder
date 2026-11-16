#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: $0 [--once] [--interval SEC] [--residency-every SEC] [model-id...]

Console status panel (q quits): per model the serve phase with progress and speed, last request speed and page-cache
residency; for the host RAM per NUMA node, major faults and reclaim, NVMe temperature, CPU per node and the GPUs.
Models default to every configured model that is downloaded (\$MODELS_DIR/<id>/current exists).
--once prints one frame to stdout without the residency scan.
EOF
}

opts=()
ids=()
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    --once) opts+=("$1") ;;
    --interval | --residency-every) opts+=("$1" "${2:?$1 needs a value}"); shift ;;
    -*) die "unknown option $1" ;;
    *) ids+=("$1") ;;
    esac
    shift
done

load_global
if ((${#ids[@]} == 0)); then
    for id in $(model_ids); do
        [[ -e $MODELS_DIR/$id/current ]] && ids+=("$id")
    done
    ((${#ids[@]})) || die "no downloaded model under $MODELS_DIR"
fi
for id in "${ids[@]}"; do
    # GPUs come from '-dev CUDA0,CUDA1' in EXTRA_ARGS; CUDA_DEVICE_ORDER=PCI_BUS_ID makes them nvidia-smi indices.
    spec=$(
        load_model "$id"
        gpus=""
        [[ " ${EXTRA_ARGS:-} " =~ [[:space:]](-dev|--device)[[:space:]]+([^[:space:]]+) ]] && gpus=${BASH_REMATCH[2]//CUDA/}
        echo "$MODEL_ID|$PORT|$MODEL_CURRENT|$gpus"
    )
    opts+=(--model "$spec")
done
exec python3 -I "$SCRIPTS_DIR/llm_panel.py" "${opts[@]}"
