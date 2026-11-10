#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: sudo $0 [--dry-run] [--no-restart] <model-id | engine>

engine      swap engines/llama.cpp-current and llama.cpp-previous, update versions.lock,
            restart every active llm@*.service and health-check it
<model-id>  swap models/<id>/current and previous (weights of the previous revision must still
            be on disk), restore config/models/<id>.env from the commit that pinned that revision,
            update versions.lock, restart llm@<id> if active and health-check it
Nothing is deleted. Running it twice rolls forward again. Without root, files are switched
and the restart commands are printed instead (--no-restart implies the same).
EOF
}

TARGET=""
RESTART=1
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    --no-restart) RESTART=0 ;;
    -*) die "unknown option $1" ;;
    *) TARGET=$1 ;;
    esac
    shift
done
[[ -n $TARGET ]] || { usage; exit 2; }

load_global
init_logging "$TARGET"
((EUID == 0)) || [[ $(id -un) == "$LLM_USER" ]] || die "run as root or $LLM_USER"
((EUID == 0)) || RESTART=0

restart_and_check() { # <model-id>...
    local id
    for id in "$@"; do
        if ((!RESTART)); then
            info "to apply: sudo systemctl restart llm@$id && $SCRIPTS_DIR/50-healthcheck.sh $id"
            continue
        fi
        run systemctl restart "llm@$id.service"
        ((DRY_RUN)) && continue
        (load_model "$id" && wait_ready "http://127.0.0.1:$PORT" "$SERVER_READY_TIMEOUT") || die "llm@$id did not become ready after rollback"
        "$SCRIPTS_DIR/50-healthcheck.sh" "$id" || die "health check failed after rollback of llm@$id"
    done
}

swap_links() { # <current link> <previous link>
    local cur=$1 prev=$2 a b
    [[ -L $prev ]] || die "no previous version recorded ($prev missing); nothing to roll back to"
    a=$(readlink -f "$cur")
    b=$(readlink -f "$prev")
    [[ -d $b ]] || die "previous target $b no longer exists"
    info "rolling back: $a -> $b"
    if ((DRY_RUN)); then
        info "[dry-run] would swap $cur and $prev"
        return 0
    fi
    as_llm ln -sfn "$b" "$cur.tmp.$$"
    as_llm mv -fT "$cur.tmp.$$" "$cur"
    as_llm ln -sfn "$a" "$prev.tmp.$$"
    as_llm mv -fT "$prev.tmp.$$" "$prev"
}

if [[ $TARGET == engine ]]; then
    swap_links "$ENGINE_CURRENT" "$ENGINE_PREVIOUS"
    if ((!DRY_RUN)); then
        ref=$(engine_build_info "$ENGINE_CURRENT" ref)
        commit=$(engine_build_info "$ENGINE_CURRENT" commit)
        lock_replace engine llama.cpp "$(printf 'engine\tllama.cpp\t%s\t%s' "$ref" "$commit")"
        git_commit "rollback: engine -> llama.cpp $ref ($commit)" versions.lock
    fi
    active=()
    if command -v systemctl >/dev/null 2>&1; then
        mapfile -t active < <(systemctl list-units --state=active --plain --no-legend 'llm@*.service' | awk '{ print $1 }' | sed 's/^llm@//; s/\.service$//')
    fi
    restart_and_check "${active[@]}"
    exit 0
fi

load_model "$TARGET"
swap_links "$MODEL_CURRENT" "$MODEL_PREVIOUS"
((DRY_RUN)) && exit 0
rev=$(basename "$(readlink -f "$MODEL_CURRENT")")
rel=config/models/$MODEL_ID.env
commit=""
while read -r c; do
    if as_llm git -C "$STACK_DIR" show "$c:$rel" 2>/dev/null | grep -qx "HF_REVISION=$rev"; then
        commit=$c
        break
    fi
done < <(as_llm git -C "$STACK_DIR" log --format=%H -- "$rel")
[[ -n $commit ]] || die "no commit of $rel pins HF_REVISION=$rev; edit HF_REVISION by hand and re-run make download M=$MODEL_ID"
info "restoring $rel from ${commit:0:12}"
as_llm git -C "$STACK_DIR" show "$commit:$rel" | as_llm tee "$STACK_DIR/$rel" >/dev/null
load_model "$MODEL_ID"

meta=$MODEL_DIR/.meta-$rev.json
[[ -f $meta ]] || die "missing $meta; run: make download M=$MODEL_ID (it will only verify)"
lines=()
while IFS= read -r stamp; do
    f=${stamp#"$REV_DIR/.verified/"}
    f=${f%.sha256}
    read -r sha size _ <"$stamp"
    lines+=("$(printf 'model-file\t%s\t%s\t%s\t%s' "$MODEL_ID" "$f" "$size" "$sha")")
done < <(find "$REV_DIR/.verified" -name '*.sha256' -type f | sort)
lock_replace model "$MODEL_ID" "$(printf 'model\t%s\t%s\t%s' "$MODEL_ID" "$HF_REPO" "$HF_REVISION")"
lock_replace model-file "$MODEL_ID" "${lines[@]}"
git_commit "rollback: $MODEL_ID -> $HF_REPO@${rev:0:12}" "$rel" versions.lock
if service_active "$SERVICE"; then restart_and_check "$MODEL_ID"; else info "$SERVICE not active; not restarting"; fi
