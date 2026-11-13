#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: $0 [--dry-run] [--keep-others] <model-id>

Loads <model-id>'s files into the page cache before serving or benchmarking it:
  1. drops the page-cache pages of every other configured model (posix_fadvise DONTNEED, no root needed),
     unless --keep-others; the kernel otherwise keeps the last model's pages and evicts the new one's first
  2. drops <model-id>'s own pages, so pages cached earlier on the wrong NUMA nodes are placed again
  3. reads every GGUF with one reader per NUMA node (warm_read.py): pages end up interleaved finely across
     nodes (first-touch), the disk sees one sequential region at queue depth ~nodes, and reading pauses while
     the NVMe is at WARM_TEMP_HI C until it cools to WARM_TEMP_LO C
llama.cpp's own mmap faulting reads the model as millions of random 4K reads; a single sequential reader puts
whole tensors on one node and cuts CPU-expert tg about 2.5x on this host.
EOF
}

MODEL=""
KEEP_OTHERS=0
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    --keep-others) KEEP_OTHERS=1 ;;
    -*) die "unknown option $1" ;;
    *) MODEL=$1 ;;
    esac
    shift
done
[[ -n $MODEL ]] || { usage; exit 2; }

load_global
load_model "$MODEL"
init_logging "$MODEL_ID"
require_cmd python3 dd find realpath
[[ -d $MODEL_CURRENT ]] || die "$MODEL_CURRENT does not exist; run 20-download-model.sh $MODEL_ID first"
WARM_TEMP_HI=${WARM_TEMP_HI:-65}
WARM_TEMP_LO=${WARM_TEMP_LO:-55}

evict() { # <dir>
    info "evicting $1 from the page cache"
    ((DRY_RUN)) && return 0
    find -L "$1" -type f -print0 | while IFS= read -r -d '' f; do dd if="$f" iflag=nocache count=0 status=none; done
}

if ((!KEEP_OTHERS)); then
    for id in $(model_ids); do
        [[ $id == "$MODEL_ID" || ! -d $MODELS_DIR/$id/current ]] || evict "$MODELS_DIR/$id/current"
    done
fi
evict "$MODEL_CURRENT"

mapfile -t files < <(find -L "$MODEL_CURRENT" -type f -name '*.gguf' -exec realpath {} + | sort -u)
((${#files[@]})) || die "no GGUF files under $MODEL_CURRENT"
info "warming ${#files[@]} files of $MODEL_ID (pause at ${WARM_TEMP_HI}C until ${WARM_TEMP_LO}C)"
((DRY_RUN)) && exit 0
TEMP_HI=$WARM_TEMP_HI TEMP_LO=$WARM_TEMP_LO python3 -I "$STACK_DIR/scripts/warm_read.py" "${files[@]}"
info "done"
