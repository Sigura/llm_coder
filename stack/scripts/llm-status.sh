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
if [[ -z $LOG ]]; then
    LOG=$(grep -l "models/$MODEL_ID/" "$(realpath "$STACK_DIR/..")"/.devbox/logs/*serve*.log 2>/dev/null | xargs -r ls -t | head -1)
    [[ -n $LOG ]] || die "no serve log mentions $MODEL_ID under $STACK_DIR/../.devbox/logs; pass --log FILE"
fi
[[ -r $LOG ]] || die "cannot read $LOG"

echo "== $MODEL_ID  ($LOG, last write $(date -r "$LOG" +%T), now $(date +%T))"
# Only the part after the last service start counts; devbox serve marks each start with '--- <time> started'.
awk '
    /^--- .* started$/ { start = $2; phase = "starting"; detail = ""; last_prompt = last_gen = warn = ""; next }
    /25-warm-cache: checking/ { phase = "warm-up: checking the page cache" }
    /25-warm-cache: warming/ { phase = "warm-up: reading the model"; detail = "" }
    /^   warming: / { sub(/^   warming: /, ""); detail = $0 }
    /^   read [0-9]+ GiB/ { sub(/^   /, ""); detail = $0 }
    /25-warm-cache: residency after warming/ { phase = "warm-up: checking residency" }
    /already warm and even/ { phase = "warm-up: skipped, already cached" }
    /is not fully cached or not NUMA-even/ { warn = "warm-up ended with the model partly evicted" }
    /llm-serve: exec:/ { phase = "router up, model not loaded (loads on the first request)"; detail = "" }
    /spawning server instance with name/ { phase = "loading weights"; detail = "" }
    /model loaded/ { phase = "loaded, idle"; detail = "" }
    /launch_slot_: .*processing task/ { phase = "request started"; detail = "" }
    /prompt processing, n_tokens/ {
        match($0, /n_tokens = +[0-9]+/); n = substr($0, RSTART, RLENGTH); sub(/n_tokens = +/, "", n)
        match($0, /progress = [0-9.]+/); p = substr($0, RSTART + 11, RLENGTH - 11)
        match($0, /t = +[0-9.]+ s \/ +[0-9.]+ tokens per second/); t = substr($0, RSTART, RLENGTH)
        phase = sprintf("prompt processing %d%%", p * 100); detail = n " tokens, " t
    }
    /n_gen = / { match($0, /n_gen = +[0-9]+, tg = +[0-9.]+ t\/s/); phase = "generating"; detail = substr($0, RSTART, RLENGTH) }
    /prompt eval time/ { sub(/.*prompt eval time = +/, "prompt "); last_prompt = $0 }
    /        eval time/ { sub(/.*eval time = +/, "gen "); last_gen = $0 }
    /stop processing/ { phase = "loaded, idle" }
    /entering sleeping state/ { phase = "sleeping (weights unloaded after idle)" }
    /exiting sleeping state/ { phase = "waking up" }
    /exited with status/ { phase = "model instance exited"; detail = $0 }
    END {
        print "phase:  " phase (detail != "" ? "  (" detail ")" : "")
        if (start != "") print "started: " start
        if (last_prompt != "") print "last:   " last_prompt
        if (last_gen != "") print "        " last_gen
        if (warn != "") print "WARN:   " warn
    }
' "$LOG"

mapfile -t files < <(find -L "$MODEL_CURRENT" -type f -name '*.gguf' -exec realpath {} + | sort -u)
((${#files[@]})) || die "no GGUF files under $MODEL_CURRENT"
echo -n "cache: "
python3 -I "$STACK_DIR/scripts/warm_read.py" --check "${files[@]}" && echo "        OK: cached and NUMA-even" ||
    echo "        NOT fully cached or uneven: prompt processing will read from disk"
awk '/MemFree|^Cached/ { printf "%s %.0f GiB  ", $1, $2 / 1048576 } END { print "" }' /proc/meminfo
