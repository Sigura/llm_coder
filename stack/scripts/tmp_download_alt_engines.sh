#!/usr/bin/env bash
# Downloads the weights for the alternative-engine trials, one repo after the other, resuming after failures:
#   1. the two Engram shards of deepseek-ai/DeepSeek-V4.1-Flash-1017 (203 GB): Xolotl reads its Engram tables from
#      them and runs our unsloth UD-Q2_K_XL GGUF otherwise (docs/DEEPSEEK_V41.md in Xolotl)
#   2. the rest of that FP8 repo (510 GB in all) for SGLang + KTransformers
#   3. IndrasMirror/DeepSeek-V4.1-Flash-1017-XQ-Uncensored v4 (163 GB), Xolotl's own build
# Downloaded pages are dropped from the page cache every minute so the running DeepSeek keeps its experts cached.
set -euo pipefail

LLM_ROOT=${LLM_ROOT:-/home/sigura/llm_coder/llm}
# aria2c, not hf: over this link hf's xet client piled out-of-order chunks up in RAM and restarted whole files after
# failed reconstructions (15 GB received, nothing kept, Nov 19), and without xet hf refuses files over 50 GB. The
# resolve URLs redirect to a CDN that serves ranges, so aria2c resumes each file from its .aria2 control file.
CONNS=${CONNS:-16}
OUT=$LLM_ROOT/models
RETRY_SEC=${RETRY_SEC:-60}

FP8_REPO=deepseek-ai/DeepSeek-V4.1-Flash-1017
FP8_REV=08c8657f02291e11b6f6b63e0e16014f8e748518
FP8_DIR=$OUT/deepseek-v4.1-flash-1017-fp8/$FP8_REV
XQ_REPO=IndrasMirror/DeepSeek-V4.1-Flash-1017-XQ-Uncensored
XQ_REV=ed44acec8175a06485c55f0f8915fb57eea9d7ee
XQ_DIR=$OUT/deepseek-v4.1-flash-1017-xq/$XQ_REV

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

command -v aria2c >/dev/null || { log "missing aria2c (conda env)"; exit 1; }
command -v jq >/dev/null || { log "missing jq"; exit 1; }
avail_gb=$(df -BG --output=avail "$OUT" | tail -1 | tr -dc 0-9)
((avail_gb > 750)) || { log "only ${avail_gb} GB free under $OUT, need ~700"; exit 1; }

evict_loop() { # <dir>
    while sleep 60; do
        # aria2 removes its .aria2 control files when a file finishes, so a listed file can be gone by the time dd opens it
        find "$1" -type f -print0 2>/dev/null | while IFS= read -r -d '' f; do
            dd if="$f" iflag=nocache count=0 status=none 2>/dev/null || true
        done
    done
}

check_sizes() { # <repo> <rev> <dir> <include regex>
    local bad=0 name size have
    while IFS=$'\t' read -r name size; do
        have=$(stat -c %s "$3/$name" 2>/dev/null || echo missing)
        [[ $have == "$size" ]] || { log "size mismatch $name: have $have, want $size"; bad=1; }
    done < <(curl -sSf "https://huggingface.co/api/models/$1/revision/$2?blobs=true" |
        jq -r --arg re "$4" '.siblings[] | select(.rfilename | test($re)) | [.rfilename, .size] | @tsv')
    return $bad
}

fetch() { # <repo> <rev> <dir> <include regex>
    local repo=$1 rev=$2 dir=$3 re=$4 attempt=0 list
    mkdir -p "$dir"
    list=$dir/.aria2-input
    # one entry per file: URL, out=, and the LFS sha256 that aria2c checks when the file completes
    curl -sSf "https://huggingface.co/api/models/$repo/revision/$rev?blobs=true" |
        jq -r --arg re "$re" --arg base "https://huggingface.co/$repo/resolve/$rev/" '.siblings[]
            | select(.rfilename | test($re))
            | "\($base)\(.rfilename)\n  out=\(.rfilename)" + (if .lfs.sha256 then "\n  checksum=sha-256=\(.lfs.sha256)" else "" end)' >"$list"
    evict_loop "$dir" &
    local ev=$!
    until aria2c -i "$list" -d "$dir" -j 1 -x "$CONNS" -s "$CONNS" -k 64M -c --file-allocation=falloc --auto-file-renaming=false \
        --allow-overwrite=false --max-tries=0 --retry-wait=30 --timeout=30 --lowest-speed-limit=20K --check-integrity=true --summary-interval=600 \
        --console-log-level=warn; do
        attempt=$((attempt + 1))
        log "download of $repo failed (attempt $attempt), retrying in ${RETRY_SEC}s"
        sleep "$RETRY_SEC"
    done
    kill "$ev" 2>/dev/null || true
    find "$dir" -type f -print0 | while IFS= read -r -d '' f; do dd if="$f" iflag=nocache count=0 status=none; done
    check_sizes "$repo" "$rev" "$dir" "$re" || { log "$repo: size check failed"; return 1; }
    log "$repo done: $(du -sh "$dir" | cut -f1)"
}

log "1/3 $FP8_REPO Engram shards -> $FP8_DIR"
fetch "$FP8_REPO" "$FP8_REV" "$FP8_DIR" '^(model-0004[78]-of-00048[.]safetensors|model[.]safetensors[.]index[.]json|config[.]json)$'

log "2/3 $FP8_REPO -> $FP8_DIR"
fetch "$FP8_REPO" "$FP8_REV" "$FP8_DIR" '.*'

log "3/3 $XQ_REPO (v4) -> $XQ_DIR"
fetch "$XQ_REPO" "$XQ_REV" "$XQ_DIR" '^(v4/|tokenizer/|README)'

log "all downloads done"
