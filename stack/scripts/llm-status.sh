#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: $0 [--log FILE] <model-id>

Shows what a served model is doing: the phase from its service log (warming the page cache, router idle with
the model not loaded, loading weights, prompt processing with progress and speed, generating, sleeping),
how much of the model is in the page cache and how it spreads over the NUMA nodes, and free RAM.
The log defaults to the newest .devbox/logs/*serve*.log that started <model-id>.
EOF
}

MODEL=""
LOG=""
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    --log) LOG=${2:?--log needs a file}; shift ;;
    -*) die "unknown option $1" ;;
    *) MODEL=$1 ;;
    esac
    shift
done
[[ -n $MODEL ]] || { usage; exit 2; }

load_global
load_model "$MODEL"
[[ -z $LOG || -r $LOG ]] || die "cannot read $LOG"
python3 -I "$SCRIPTS_DIR/llm_panel.py" --status "$MODEL_ID" ${LOG:+--log "$LOG"}

mapfile -t files < <(find -L "$MODEL_CURRENT" -type f -name '*.gguf' -exec realpath {} + | sort -u)
((${#files[@]})) || die "no GGUF files under $MODEL_CURRENT"
echo -n "cache: "
python3 -I "$STACK_DIR/scripts/warm_read.py" --check "${files[@]}" && echo "        OK: cached and NUMA-even" ||
    echo "        NOT fully cached or uneven: prompt processing will read from disk"
awk '/MemFree|^Cached/ { printf "%s %.0f GiB  ", $1, $2 / 1048576 } END { print "" }' /proc/meminfo
