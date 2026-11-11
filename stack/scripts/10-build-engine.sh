#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: $0 [--dry-run] [--ref <tag|commit>] [--no-switch] [--rebuild]

Builds llama.cpp (CUDA, archs from CUDA_ARCHS) into LLM_ROOT/engines/llama.cpp-<tag>,
smoke-tests it on a tiny pinned model, then atomically points engines/llama.cpp-current
at it (the old target becomes engines/llama.cpp-previous) and records the commit in
versions.lock. Default --ref is the engine pinned in versions.lock.
  --no-switch   build and smoke-test only
  --rebuild     rebuild even if this ref was already built and smoke-tested
EOF
}

REF=""
SWITCH=1
REBUILD=0
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    --ref) REF=$2; shift ;;
    --no-switch) SWITCH=0 ;;
    --rebuild) REBUILD=1 ;;
    *) die "unknown argument $1" ;;
    esac
    shift
done

load_global
require_llm_user "$@"
init_logging "${REF:-locked}"
single_instance engine-build
require_cmd git cmake curl sha256sum "$HF_CLI"

if [[ -z $REF ]]; then
    REF=$(lock_get engine llama.cpp | cut -f3)
    [[ -n $REF ]] || die "no --ref given and no engine pinned in versions.lock"
    info "using pinned ref $REF from versions.lock"
fi

NVCC=$CUDA_HOME/bin/nvcc
[[ -x $NVCC ]] || NVCC=$(command -v nvcc) || die "nvcc not found in $CUDA_HOME/bin or PATH"
info "nvcc: $NVCC ($("$NVCC" --version | sed -n 's/.*release \([0-9.]*\).*/\1/p'))"

fetch_src() {
    local i
    if [[ ! -d $ENGINE_SRC/.git ]]; then
        run mkdir -p "$(dirname "$ENGINE_SRC")"
        run git clone --filter=blob:none --no-checkout "$LLAMA_CPP_REPO" "$ENGINE_SRC"
    fi
    for i in 1 2 3; do
        run git -C "$ENGINE_SRC" fetch --tags --force origin && return 0
        warn "git fetch failed (attempt $i), retrying"
        sleep $((i * 15))
    done
    die "git fetch from $LLAMA_CPP_REPO failed"
}

if ((DRY_RUN)) && [[ ! -d $ENGINE_SRC/.git ]]; then
    info "[dry-run] would clone $LLAMA_CPP_REPO into $ENGINE_SRC and build $REF"
    exit 0
fi
# Tags and commit shas are immutable, so only fetch when the ref is not known locally yet.
if ! COMMIT=$(git -C "$ENGINE_SRC" rev-parse --verify -q "$REF^{commit}" 2>/dev/null); then
    fetch_src
    COMMIT=$(git -C "$ENGINE_SRC" rev-parse --verify -q "$REF^{commit}") || die "unknown ref '$REF'"
fi
if git -C "$ENGINE_SRC" show-ref --verify -q "refs/tags/$REF"; then NAME=$REF; else NAME=${COMMIT:0:12}; fi
DEST=$ENGINES_DIR/llama.cpp-$NAME
info "ref $REF -> commit $COMMIT -> $DEST"

already_built() {
    [[ -f $DEST/.smoke-ok && $(engine_build_info "$DEST" commit) == "$COMMIT" ]]
}

smoke_test() { # <engine dir>
    local dir=$1 smoke_dir=$CACHE_DIR/smoke model pid ok=0 body out
    model=$smoke_dir/$SMOKE_MODEL_FILE
    if [[ ! -f $model ]] || [[ $(sha256sum "$model" | cut -d' ' -f1) != "$SMOKE_MODEL_SHA256" ]]; then
        run "$HF_CLI" download "$SMOKE_MODEL_REPO" "$SMOKE_MODEL_FILE" --revision "$SMOKE_MODEL_REVISION" --local-dir "$smoke_dir"
        [[ $(sha256sum "$model" | cut -d' ' -f1) == "$SMOKE_MODEL_SHA256" ]] || die "smoke model checksum mismatch"
    fi
    run "$dir/bin/llama-server" --version
    out=$("$dir/bin/llama-server" --list-devices 2>&1) || die "llama-server --list-devices failed: $out"
    printf '%s\n' "$out" | while IFS= read -r l; do info "  $l"; done
    grep -q CUDA0 <<<"$out" || die "smoke: no CUDA device visible to the new build"
    port_in_use "$SMOKE_PORT" && die "SMOKE_PORT $SMOKE_PORT is in use"
    # -dev CUDA0 makes the server fail at load instead of silently running on CPU.
    "$dir/bin/llama-server" -m "$model" -dev CUDA0 -ngl 99 -c 256 --host 127.0.0.1 --port "$SMOKE_PORT" \
        >"$smoke_dir/server.log" 2>&1 &
    pid=$!
    if wait_ready "http://127.0.0.1:$SMOKE_PORT" 120 "$pid"; then
        body=$(curl -sS --max-time 60 -H 'Content-Type: application/json' \
            -d '{"prompt":"Once upon a time","n_predict":16,"temperature":0}' \
            "http://127.0.0.1:$SMOKE_PORT/completion" || true)
        if [[ $(jq -r '.tokens_predicted // 0' <<<"$body" 2>/dev/null) -gt 0 ]]; then
            info "smoke: generated '$(jq -r .content <<<"$body" | tr '\n' ' ')'"
            ok=1
        fi
    fi
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    ((ok)) || {
        tail -n 30 "$smoke_dir/server.log" >&2
        die "smoke test failed for $dir (log: $smoke_dir/server.log)"
    }
    info "smoke test passed"
}

if already_built && ((!REBUILD)); then
    info "$DEST already built and smoke-tested; skipping build"
else
    WORK=$ENGINES_DIR/.build/$NAME
    TMP_DEST=$DEST.partial
    jobs=$BUILD_JOBS
    [[ $jobs == auto ]] && jobs=$(nproc)
    read -ra extra_cmake <<<"${CMAKE_EXTRA_ARGS:-}"
    gen=()
    command -v ninja >/dev/null 2>&1 && gen=(-G Ninja)
    run rm -rf "$WORK" "$TMP_DEST"
    run git -C "$ENGINE_SRC" worktree prune
    run git -C "$ENGINE_SRC" worktree add --force --detach "$WORK/src" "$COMMIT"
    run cmake -S "$WORK/src" -B "$WORK/build" "${gen[@]}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_CUDA=ON \
        "-DCMAKE_CUDA_ARCHITECTURES=$CUDA_ARCHS" \
        "-DCMAKE_CUDA_COMPILER=$NVCC" \
        -DGGML_NATIVE=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
        "-DCMAKE_INSTALL_PREFIX=$TMP_DEST" \
        "${extra_cmake[@]}"
    run cmake --build "$WORK/build" -j "$jobs"
    run cmake --install "$WORK/build"
    if ((!DRY_RUN)); then
        cat >"$TMP_DEST/BUILD_INFO" <<EOF
ref=$REF
commit=$COMMIT
version=$("$TMP_DEST/bin/llama-server" --version 2>&1 | grep -m1 version || true)
built_at=$(date -Is)
built_by=$(id -un)@$(hostname)
nvcc=$("$NVCC" --version | sed -n 's/.*release \([0-9.]*\).*/\1/p')
cuda_archs=$CUDA_ARCHS
cmake_extra=${CMAKE_EXTRA_ARGS:-}
EOF
        smoke_test "$TMP_DEST"
        touch "$TMP_DEST/.smoke-ok"
        rm -rf "$DEST"
        mv -T "$TMP_DEST" "$DEST"
    fi
    run git -C "$ENGINE_SRC" worktree remove --force "$WORK/src"
    run rm -rf "$WORK"
    info "built $DEST"
fi

if ((SWITCH)); then
    switch_symlink "$ENGINE_CURRENT" "$DEST" "$ENGINE_PREVIOUS"
    lock_replace engine llama.cpp "$(printf 'engine\tllama.cpp\t%s\t%s' "$REF" "$COMMIT")"
    git_commit "engine: llama.cpp $REF ($COMMIT)" versions.lock
else
    info "--no-switch: $ENGINE_CURRENT unchanged"
fi
