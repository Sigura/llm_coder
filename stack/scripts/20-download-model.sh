#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: $0 [--dry-run] [--rehash] <model-id>
       $0 --latest <model-id>

Downloads the files selected by HF_INCLUDE and EXTRA_FILES at the pinned HF_REVISION into
LLM_ROOT/models/<model-id>/<revision>/, verifies size and sha256 against the Hugging Face
metadata, records them in versions.lock and points models/<model-id>/current at that revision
(the old one becomes models/<model-id>/previous). Already verified files are skipped.
  --rehash   re-hash every file even if its size/mtime match the last verification
  --latest   print the newest commit sha of HF_REPO (to pin a new HF_REVISION) and exit
EOF
}

MODEL=""
REHASH=0
LATEST=0
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    --rehash) REHASH=1 ;;
    --latest) LATEST=1 ;;
    -*) die "unknown option $1" ;;
    *) MODEL=$1 ;;
    esac
    shift
done
[[ -n $MODEL ]] || { usage; exit 2; }

load_global
load_model "$MODEL"
require_cmd curl jq sha256sum df "$HF_CLI"

hf_api() { # <path> -> stdout, with retries
    local i delay=$DOWNLOAD_BACKOFF_SEC out
    for ((i = 1; i <= DOWNLOAD_RETRIES; i++)); do
        if out=$(curl -sSf --max-time 120 "https://huggingface.co/api/$1"); then
            printf '%s' "$out"
            return 0
        fi
        warn "HF API request failed (attempt $i/$DOWNLOAD_RETRIES), retrying in ${delay}s"
        sleep "$delay"
        delay=$((delay * 2))
    done
    die "HF API unreachable: $1"
}

if ((LATEST)); then
    hf_api "models/$HF_REPO" | jq -r '"\(.sha)  lastModified=\(.lastModified)"'
    exit 0
fi

require_llm_user "$@"
init_logging "$MODEL_ID"
single_instance "download-$MODEL_ID"
info "model $MODEL_ID: $HF_REPO @ $HF_REVISION"

# A revision is immutable, so its metadata is fetched once and cached.
META=$MODEL_DIR/.meta-$HF_REVISION.json
if [[ ! -s $META ]]; then
    meta_json=$(hf_api "models/$HF_REPO/revision/$HF_REVISION?blobs=true")
    [[ $(jq -r .sha <<<"$meta_json") == "$HF_REVISION" ]] || die "HF returned a different revision than pinned"
    if ((!DRY_RUN)); then
        mkdir -p "$MODEL_DIR"
        printf '%s\n' "$meta_json" >"$META"
    fi
else
    meta_json=$(<"$META")
    info "using cached metadata $META"
fi

read -ra patterns <<<"$HF_INCLUDE ${EXTRA_FILES:-}"
mapfile -t all_files < <(jq -r '.siblings[] | [.rfilename, (.size // -1), (.lfs.sha256 // "")] | @tsv' <<<"$meta_json")
declare -A SIZE SHA PATTERN_RE
for p in "${patterns[@]}"; do PATTERN_RE[$p]=$(glob_to_regex "$p"); done
FILES=()
for row in "${all_files[@]}"; do
    IFS=$'\t' read -r f size sha <<<"$row"
    for p in "${patterns[@]}"; do
        if [[ $f =~ ${PATTERN_RE[$p]} ]]; then
            [[ -n $sha ]] || die "$f has no LFS sha256 in the HF metadata; cannot verify it"
            FILES+=("$f")
            SIZE[$f]=$size
            SHA[$f]=$sha
            break
        fi
    done
done
((${#FILES[@]})) || die "no files in $HF_REPO@$HF_REVISION match: ${patterns[*]}"
[[ -n ${SIZE[$MAIN_GGUF]:-} ]] || die "MAIN_GGUF=$MAIN_GGUF is not among the selected files"
if [[ -n ${SPEC_DRAFT_GGUF:-} && -z ${SIZE[$SPEC_DRAFT_GGUF]:-} ]]; then
    warn "SPEC_DRAFT_GGUF=$SPEC_DRAFT_GGUF is not selected by HF_INCLUDE/EXTRA_FILES"
fi

total=0
for f in "${FILES[@]}"; do total=$((total + SIZE[$f])); done
info "${#FILES[@]} files selected, $((total / 1000000000)) GB"

STAMP_DIR=$REV_DIR/.verified
stamp_ok() { # file verified earlier and unchanged since
    local f=$1 stamp=$STAMP_DIR/$1.sha256 path=$REV_DIR/$1
    ((!REHASH)) && [[ -f $stamp && -f $path ]] &&
        [[ $(<"$stamp") == "${SHA[$f]} ${SIZE[$f]} $(stat -c %Y "$path")" ]]
}

TODO=()
need=0
for f in "${FILES[@]}"; do
    stamp_ok "$f" && continue
    TODO+=("$f")
    have=0
    if [[ -f $REV_DIR/$f ]]; then
        have=$(stat -c %s "$REV_DIR/$f")
    elif [[ -f $REV_DIR/$f.part ]]; then
        have=$(stat -c %s "$REV_DIR/$f.part")
    fi
    ((have < SIZE[$f])) && need=$((need + SIZE[$f] - have))
done

if ((${#TODO[@]} == 0)); then
    info "all ${#FILES[@]} files already verified; nothing to download"
else
    info "${#TODO[@]} files to fetch/verify, $((need / 1000000000)) GB still to download"
    probe=$MODEL_DIR
    while [[ ! -e $probe ]]; do probe=$(dirname "$probe"); done
    avail=$(($(df -Pk "$probe" | awk 'NR == 2 { print $4 }') * 1024))
    required=$((need + need * FREE_SPACE_MARGIN_PCT / 100))
    ((avail >= required)) || die "not enough space on $(df -P "$probe" | awk 'NR == 2 { print $6 }'): need $((required / 1000000000)) GB (incl. ${FREE_SPACE_MARGIN_PCT}%), have $((avail / 1000000000)) GB"
    info "free space ok: $((avail / 1000000000)) GB available, $((required / 1000000000)) GB required"

    # curl instead of `hf download`: huggingface_hub writes each file to a per-process temp file and
    # deletes it on failure, so an interrupted multi-GB download restarts from zero. curl -C - continues
    # <file>.part with an HTTP range request; the sha256 check below catches anything a resume got wrong.
    fetch_one() {
        local f=$1 out=$REV_DIR/$1
        mkdir -p "$(dirname "$out")"
        info "fetch $f (have $(stat -c %s "$out.part" 2>/dev/null || echo 0) of ${SIZE[$f]} bytes)"
        curl -fsSL --retry 5 --retry-all-errors --retry-delay 10 --speed-limit 1024 --speed-time 120 \
            -C - -o "$out.part" "https://huggingface.co/$HF_REPO/resolve/$HF_REVISION/$f" || return 1
        mv -f "$out.part" "$out"
        info "fetched $f"
    }
    delay=$DOWNLOAD_BACKOFF_SEC
    for ((i = 1; ; i++)); do
        to_download=()
        for f in "${TODO[@]}"; do
            [[ -f $REV_DIR/$f && $(stat -c %s "$REV_DIR/$f") -eq ${SIZE[$f]} ]] || to_download+=("$f")
        done
        ((${#to_download[@]})) || break
        if ((DRY_RUN)); then
            info "[dry-run] would fetch ${#to_download[@]} files with curl -C - ($DOWNLOAD_WORKERS in parallel)"
            break
        fi
        mkdir -p "$REV_DIR"
        failed=0
        running=0
        for f in "${to_download[@]}"; do
            if ((running >= DOWNLOAD_WORKERS)); then
                wait -n || failed=1
                running=$((running - 1))
            fi
            fetch_one "$f" &
            running=$((running + 1))
        done
        while ((running > 0)); do
            wait -n || failed=1
            running=$((running - 1))
        done
        ((failed)) || continue
        ((i < DOWNLOAD_RETRIES)) || die "download failed $i times; re-run to resume (partial files are kept as *.part)"
        warn "download failed (attempt $i/$DOWNLOAD_RETRIES); resuming in ${delay}s"
        sleep "$delay"
        delay=$((delay * 2))
    done

    if ((DRY_RUN)); then
        info "[dry-run] would verify sha256 of ${#TODO[@]} files"
    else
        info "verifying sha256 of ${#TODO[@]} files ($HASH_JOBS in parallel)"
        mapfile -t hashes < <(cd "$REV_DIR" && printf '%s\0' "${TODO[@]}" | xargs -0 -n1 -P "$HASH_JOBS" sha256sum)
        bad=()
        for line in "${hashes[@]}"; do
            got=${line%% *}
            f=${line#*  }
            if [[ $got == "${SHA[$f]}" && $(stat -c %s "$REV_DIR/$f") -eq ${SIZE[$f]} ]]; then
                mkdir -p "$(dirname "$STAMP_DIR/$f")"
                echo "${SHA[$f]} ${SIZE[$f]} $(stat -c %Y "$REV_DIR/$f")" >"$STAMP_DIR/$f.sha256"
                info "ok  $f"
            else
                bad+=("$f")
                log FAIL "sha256 mismatch: $f (got $got, want ${SHA[$f]})"
            fi
        done
        ((${#hashes[@]} == ${#TODO[@]})) || die "hashed ${#hashes[@]} of ${#TODO[@]} files"
        if ((${#bad[@]})); then
            mkdir -p "$REV_DIR/.corrupt"
            for f in "${bad[@]}"; do mv -f "$REV_DIR/$f" "$REV_DIR/.corrupt/${f//\//__}"; done
            die "${#bad[@]} files failed verification and were moved to $REV_DIR/.corrupt/ (delete them yourself); re-run to download them again"
        fi
    fi
fi

# SPLIT_LINKS="<link>:<target> ...": e.g. a shared Engram file that must also appear as shard N of a split GGUF.
read -ra split_links <<<"${SPLIT_LINKS:-}"
for pair in "${split_links[@]}"; do
    link=${pair%%:*}
    target=${pair#*:}
    [[ $pair == *:* && -n $link && -n $target ]] || die "SPLIT_LINKS entry '$pair' is not <link>:<target>"
    [[ -n ${SIZE[$target]:-} ]] || die "SPLIT_LINKS target $target is not among the selected files"
    [[ $(dirname "$link") == "$(dirname "$target")" ]] || die "SPLIT_LINKS $link and $target must be in the same directory"
    [[ $(readlink "$REV_DIR/$link" 2>/dev/null) == "$(basename "$target")" ]] && continue
    run ln -sfn "$(basename "$target")" "$REV_DIR/$link"
done

if ((!DRY_RUN)); then
    touch "$REV_DIR/.complete"
fi
lines=("$(printf 'model\t%s\t%s\t%s' "$MODEL_ID" "$HF_REPO" "$HF_REVISION")")
for f in "${FILES[@]}"; do lines+=("$(printf 'model-file\t%s\t%s\t%s\t%s' "$MODEL_ID" "$f" "${SIZE[$f]}" "${SHA[$f]}")"); done
lock_replace model "$MODEL_ID" "${lines[0]}"
lock_replace model-file "$MODEL_ID" "${lines[@]:1}"
switch_symlink "$MODEL_CURRENT" "$REV_DIR" "$MODEL_PREVIOUS"
git_commit "model: $MODEL_ID $HF_REPO@${HF_REVISION:0:12} (${#FILES[@]} files verified)" versions.lock
info "done: $MODEL_PATH"
