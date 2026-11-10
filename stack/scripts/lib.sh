# shellcheck shell=bash
# Shared helpers, sourced by every script in this directory.

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPTS_DIR="$STACK_DIR/scripts"
SCRIPT_NAME="$(basename "$0" .sh)"
DRY_RUN=0
LOG_FILE=""

set -E
trap 'log ERROR "command failed (exit $?) at ${BASH_SOURCE[0]##*/}:$LINENO: $BASH_COMMAND"' ERR

ts() { printf '%(%Y-%m-%dT%H:%M:%S%z)T' -1; }
log() {
    local lvl=$1
    shift
    printf '%s [%s] %s: %s\n' "$(ts)" "$lvl" "$SCRIPT_NAME" "$*" >&2
}
info() { log INFO "$@"; }
warn() { log WARN "$@"; }
die() {
    log ERROR "$@"
    exit 1
}

# Mirror stdout/stderr into $LOGS_DIR/<script>[-<tag>]-<date>.log.
init_logging() {
    local tag=${1:-}
    [[ -n ${LOGS_DIR:-} ]] || die "init_logging called before load_global"
    if ! mkdir -p "$LOGS_DIR" 2>/dev/null || [[ ! -w $LOGS_DIR ]]; then
        warn "cannot write to $LOGS_DIR; logging to the terminal only"
        return 0
    fi
    LOG_FILE="$LOGS_DIR/${SCRIPT_NAME}${tag:+-$tag}-$(date +%Y%m%d).log"
    exec > >(tee -a "$LOG_FILE") 2>&1
    info "---- start: $0 $* (pid $$, user $(id -un), dry-run=$DRY_RUN)"
}

# Run a command with timestamped output, or only print it in dry-run mode.
run() {
    if ((DRY_RUN)); then
        info "[dry-run] $(printf '%q ' "$@")"
        return 0
    fi
    info "+ $(printf '%q ' "$@")"
    "$@" 2>&1 | while IFS= read -r line; do printf '%s   %s\n' "$(ts)" "$line"; done
    return "${PIPESTATUS[0]}"
}

# Run as $LLM_USER (files under $LLM_ROOT must stay owned by it).
as_llm() {
    if [[ $(id -un) == "$LLM_USER" ]]; then
        "$@"
    elif ((EUID == 0)); then
        runuser -u "$LLM_USER" -- "$@"
    else
        die "need to run as $LLM_USER or root: $*"
    fi
}

require_cmd() {
    local c missing=()
    for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
    ((${#missing[@]} == 0)) || die "missing required tools: ${missing[*]}"
}

require_root() {
    ((EUID == 0)) || die "must run as root (try: sudo $0 $*)"
}

require_llm_user() {
    [[ $(id -un) == "$LLM_USER" ]] || die "must run as user '$LLM_USER' (try: sudo -u $LLM_USER $0 $*)"
}

# Config files are shared with systemd's EnvironmentFile=, so only allow syntax both parse identically.
check_env_file() {
    local f=$1 n=0 line
    [[ -r $f ]] || die "config file not readable: $f"
    while IFS= read -r line || [[ -n $line ]]; do
        n=$((n + 1))
        [[ $line =~ ^[[:space:]]*(#.*)?$ ]] && continue
        if [[ ! $line =~ ^[A-Z][A-Z0-9_]*=(\"[^\"\$\`\\]*\"|\'[^\'\$\`\\]*\'|[^[:space:]\"\'\$\`\\]*)$ ]]; then
            die "$f:$n: unsupported syntax (use KEY=value, KEY=\"value\" or KEY='value'; no \$, backticks, backslashes): $line"
        fi
    done <"$f"
}

source_env_file() {
    check_env_file "$1"
    set -a
    # shellcheck source=/dev/null
    source "$1"
    set +a
}

require_vars() {
    local v
    for v in "$@"; do [[ -n ${!v:-} ]] || die "required setting $v is empty (check config files)"; done
}

load_global() {
    GLOBAL_ENV=${LLM_GLOBAL_ENV:-$STACK_DIR/config/global.env}
    source_env_file "$GLOBAL_ENV"
    require_vars LLM_ROOT LLM_USER HF_HOME HF_CLI EXPECTED_GPUS LLAMA_CPP_REPO CUDA_ARCHS \
        BENCH_PORT VRAM_MARGIN_MIB SERVER_READY_TIMEOUT REQUEST_TIMEOUT GIT_USER_NAME GIT_USER_EMAIL
    ENGINES_DIR=$LLM_ROOT/engines
    ENGINE_SRC=$ENGINES_DIR/.src/llama.cpp
    ENGINE_CURRENT=$ENGINES_DIR/llama.cpp-current
    ENGINE_PREVIOUS=$ENGINES_DIR/llama.cpp-previous
    MODELS_DIR=$LLM_ROOT/models
    SECRETS_DIR=$LLM_ROOT/secrets
    RESULTS_DIR=$LLM_ROOT/results
    LOGS_DIR=$LLM_ROOT/logs
    STATE_DIR=$LLM_ROOT/state
    CACHE_DIR=$LLM_ROOT/cache
    LOCK_FILE=$STACK_DIR/versions.lock
    export HF_HOME CUDA_DEVICE_ORDER ENGINES_DIR ENGINE_SRC ENGINE_CURRENT ENGINE_PREVIOUS \
        MODELS_DIR SECRETS_DIR RESULTS_DIR LOGS_DIR STATE_DIR CACHE_DIR LOCK_FILE
}

model_ids() {
    local f
    for f in "$STACK_DIR"/config/models/*.env; do
        [[ -e $f ]] && basename "$f" .env
    done
}

load_model() {
    local id=$1
    [[ $id =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "invalid model id '$id'"
    MODEL_ENV=$STACK_DIR/config/models/$id.env
    [[ -f $MODEL_ENV ]] || die "no config for model '$id' (expected $MODEL_ENV). Known: $(model_ids | tr '\n' ' ')"
    source_env_file "$MODEL_ENV"
    require_vars MODEL_ID HF_REPO HF_REVISION HF_INCLUDE MAIN_GGUF ALIAS PORT CTX N_CPU_MOE NUMA_MODE
    [[ ${MODEL_ID:-} == "$id" ]] || die "$MODEL_ENV: MODEL_ID=${MODEL_ID:-} does not match file name"
    [[ $HF_REVISION =~ ^[0-9a-f]{40}$ ]] || die "$MODEL_ENV: HF_REVISION must be a full 40-char commit sha (got '$HF_REVISION'); see 20-download-model.sh --latest"
    MODEL_DIR=$MODELS_DIR/$MODEL_ID
    MODEL_CURRENT=$MODEL_DIR/current
    MODEL_PREVIOUS=$MODEL_DIR/previous
    REV_DIR=$MODEL_DIR/$HF_REVISION
    MODEL_PATH=$MODEL_CURRENT/$MAIN_GGUF
    KEY_FILE=$SECRETS_DIR/$MODEL_ID.key
    SERVICE=llm@$MODEL_ID.service
    export MODEL_DIR MODEL_CURRENT MODEL_PREVIOUS REV_DIR MODEL_PATH KEY_FILE SERVICE
}

# fnmatch-style glob (as used by hf --include: * and ? also match "/") -> anchored ERE
glob_to_regex() {
    local g=$1 re="" c i
    for ((i = 0; i < ${#g}; i++)); do
        c=${g:i:1}
        case $c in
        '*') re+='.*' ;;
        '?') re+='.' ;;
        '.' | '[' | ']' | '^' | '$' | '(' | ')' | '{' | '}' | '|' | '+' | "\\") re+="\\$c" ;;
        *) re+=$c ;;
        esac
    done
    printf '^%s$' "$re"
}

# Rewrite KEY=... in an env file in place (keeps comments and order).
set_env_kv() {
    local file=$1 key=$2 value=$3 tmp
    [[ $value =~ [[:space:]] ]] && value="\"$value\""
    if ((DRY_RUN)); then
        info "[dry-run] would set $key=$value in $file"
        return 0
    fi
    local content
    if grep -q "^$key=" "$file"; then
        content=$(awk -v k="$key" -v v="$value" 'index($0, k "=") == 1 { print k "=" v; next } { print }' "$file")
    else
        content=$(cat "$file") && content+=$'\n'"$key=$value"
    fi
    write_file_as_llm "$file" "$content"
    check_env_file "$file"
}

# versions.lock: tab-separated "kind id fields...". Replace every line of <kind> <id> with the given lines.
lock_replace() {
    local kind=$1 id=$2 content
    shift 2
    if ((DRY_RUN)); then
        info "[dry-run] would update versions.lock ($kind $id, $# lines)"
        return 0
    fi
    [[ -f $LOCK_FILE ]] || write_file_as_llm "$LOCK_FILE" $'# kind\tid\tfields (written by scripts; do not edit by hand)'
    content=$(
        grep '^#' "$LOCK_FILE"
        {
            awk -F'\t' -v k="$kind" -v i="$id" '!/^#/ && !($1 == k && $2 == i)' "$LOCK_FILE"
            if (($#)); then printf '%s\n' "$@"; fi
        } | sort
    )
    write_file_as_llm "$LOCK_FILE" "$content"
}

# Atomic replace that leaves the file owned by $LLM_USER even when called as root.
write_file_as_llm() { # <path> <content>
    local tmp
    tmp=$(as_llm mktemp "$1.XXXXXX")
    printf '%s\n' "$2" | as_llm tee "$tmp" >/dev/null
    [[ -f $1 ]] && chmod --reference="$1" "$tmp"
    as_llm mv -f "$tmp" "$1"
}

lock_get() {
    local kind=$1 id=$2
    [[ -f $LOCK_FILE ]] || return 0
    awk -F'\t' -v k="$kind" -v i="$id" '$1 == k && $2 == i' "$LOCK_FILE"
}

git_stack() {
    as_llm git -C "$STACK_DIR" -c user.name="$GIT_USER_NAME" -c user.email="$GIT_USER_EMAIL" "$@"
}

# Commit the given paths if they changed. No-op outside a git checkout.
git_commit() {
    local msg=$1
    shift
    if ! as_llm git -C "$STACK_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        warn "$STACK_DIR is not a git checkout; not committing: $msg"
        return 0
    fi
    if [[ -z $(as_llm git -C "$STACK_DIR" status --porcelain -- "$@") ]]; then
        info "git: nothing changed in $*"
        return 0
    fi
    if ((DRY_RUN)); then
        info "[dry-run] would commit $*: $msg"
        return 0
    fi
    git_stack add -- "$@"
    git_stack commit -q -m "$msg" -- "$@"
    info "git: committed '$msg'"
}

# Atomically point <link> at <target>; the old target becomes <prev_link>.
switch_symlink() {
    local link=$1 target=$2 prev_link=$3 old=""
    [[ -L $link ]] && old=$(readlink -f "$link")
    if [[ $old == "$(readlink -f "$target")" ]]; then
        info "$link already points to $target"
        return 0
    fi
    if ((DRY_RUN)); then
        info "[dry-run] would switch $link -> $target (previous: ${old:-none})"
        return 0
    fi
    ln -sfn "$target" "$link.tmp.$$"
    mv -fT "$link.tmp.$$" "$link"
    if [[ -n $old ]]; then
        ln -sfn "$old" "$prev_link.tmp.$$"
        mv -fT "$prev_link.tmp.$$" "$prev_link"
    fi
    info "switched $link -> $target (previous: ${old:-none})"
}

# ---------- engine ----------

engine_build_info() { # <engine dir> <key>
    local f=$1/BUILD_INFO
    [[ -f $f ]] || return 1
    awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' "$f"
}

# Fail unless the current engine contains commit/tag $1.
require_engine_ref() {
    local min=$1 commit min_commit
    [[ -x $ENGINE_CURRENT/bin/llama-server ]] || die "no engine at $ENGINE_CURRENT; run: make build"
    [[ -n $min ]] || return 0
    commit=$(engine_build_info "$ENGINE_CURRENT" commit) || die "missing $ENGINE_CURRENT/BUILD_INFO"
    min_commit=$(as_llm git -C "$ENGINE_SRC" rev-parse --verify -q "$min^{commit}") ||
        die "cannot resolve MIN_ENGINE_REF=$min in $ENGINE_SRC"
    as_llm git -C "$ENGINE_SRC" merge-base --is-ancestor "$min_commit" "$commit" ||
        die "engine $(readlink -f "$ENGINE_CURRENT") ($commit) is older than MIN_ENGINE_REF=$min; run: make build REF=<newer tag>"
}

# ---------- model files ----------

require_model_verified() {
    [[ -f $MODEL_CURRENT/.complete ]] || die "model $MODEL_ID not downloaded/verified; run: make download M=$MODEL_ID"
    [[ $(readlink -f "$MODEL_CURRENT") == "$(readlink -f "$REV_DIR")" ]] ||
        die "models/$MODEL_ID/current is $(readlink -f "$MODEL_CURRENT"), but config pins $HF_REVISION; run: make download M=$MODEL_ID"
    [[ -f $MODEL_PATH ]] || die "MAIN_GGUF not found: $MODEL_PATH"
}

ensure_key() {
    if [[ -s $KEY_FILE ]]; then
        return 0
    fi
    if ((DRY_RUN)); then
        info "[dry-run] would create API key $KEY_FILE"
        return 0
    fi
    as_llm mkdir -p "$SECRETS_DIR"
    as_llm chmod 700 "$SECRETS_DIR"
    (umask 077 && od -An -tx1 -N32 /dev/urandom | tr -d ' \n' | as_llm tee "$KEY_FILE" >/dev/null)
    as_llm chmod 600 "$KEY_FILE"
    info "created API key $KEY_FILE"
}

# ---------- NUMA / threads ----------

expand_nodes() { # "0-3,6" -> "0 1 2 3 6"
    local part i
    local -a parts nodes=()
    IFS=, read -ra parts <<<"$1"
    for part in "${parts[@]}"; do
        if [[ $part =~ ^([0-9]+)-([0-9]+)$ ]]; then
            for ((i = BASH_REMATCH[1]; i <= BASH_REMATCH[2]; i++)); do nodes+=("$i"); done
        elif [[ $part =~ ^[0-9]+$ ]]; then
            nodes+=("$part")
        else
            die "bad NUMA node list '$1'"
        fi
    done
    echo "${nodes[*]}"
}

physical_cores() { # [node list] -> count of physical cores
    local node_list=${1:-}
    lscpu -p=CORE,NODE | awk -F, -v nodes=" $node_list " '
        /^#/ { next }
        nodes == "  " || index(nodes, " " $2 " ") { seen[$1] = 1 }
        END { n = 0; for (c in seen) n++; print n }'
}

# Sets NUMA_PREFIX (command prefix), NUMA_FLAG (llama.cpp args) and NUMA_NODES (for core counting).
# Modes: distribute | interleave | node<list> (e.g. node0, node0-3) | none
numa_settings() {
    local mode=$1
    NUMA_PREFIX=()
    NUMA_FLAG=()
    NUMA_NODES=""
    case $mode in
    none) ;;
    distribute) NUMA_FLAG=(--numa distribute) ;;
    interleave)
        NUMA_PREFIX=(numactl --interleave=all)
        NUMA_FLAG=(--numa numactl)
        ;;
    node*)
        local spec=${mode#node}
        NUMA_NODES=$(expand_nodes "$spec")
        NUMA_PREFIX=(numactl "--cpunodebind=$spec" --localalloc)
        NUMA_FLAG=(--numa numactl)
        ;;
    *) die "unknown NUMA_MODE '$mode' (distribute | interleave | node<list> | none)" ;;
    esac
}

resolve_threads() { # uses THREADS and NUMA_NODES
    if [[ ${THREADS:-auto} == auto ]]; then
        physical_cores "$NUMA_NODES"
    else
        echo "$THREADS"
    fi
}

# Build SERVER_CMD from the loaded config. Optional overrides: SRV_PORT SRV_HOST SRV_NCMOE SRV_TS SRV_NUMA SRV_SPEC
build_server_cmd() {
    local port=${SRV_PORT:-$PORT} host=${SRV_HOST:-$BIND_HOST}
    local ncmoe=${SRV_NCMOE:-$N_CPU_MOE} ts=${SRV_TS-$TENSOR_SPLIT}
    local numa=${SRV_NUMA:-$NUMA_MODE} spec=${SRV_SPEC:-${SPEC_ENABLED:-0}}
    local threads
    local -a extra=() draft_args=()
    numa_settings "$numa"
    threads=$(resolve_threads)
    read -ra extra <<<"${EXTRA_ARGS:-}"
    SERVER_CMD=("${NUMA_PREFIX[@]}" "$ENGINE_CURRENT/bin/llama-server"
        -m "$MODEL_PATH" --alias "$ALIAS" --host "$host" --port "$port"
        -c "$CTX" -ngl 999 --n-cpu-moe "$ncmoe" -t "$threads" -tb "$threads"
        "${NUMA_FLAG[@]}" --api-key-file "$KEY_FILE" --fit off)
    [[ -n $ts ]] && SERVER_CMD+=(--tensor-split "$ts")
    SERVER_CMD+=("${extra[@]}")
    if [[ $spec == 1 ]]; then
        require_vars SPEC_DRAFT_GGUF SPEC_ARGS
        read -ra draft_args <<<"$SPEC_ARGS"
        SERVER_CMD+=(-md "$MODEL_CURRENT/$SPEC_DRAFT_GGUF" "${draft_args[@]}")
    fi
}

# ---------- server / API ----------

port_in_use() {
    [[ -n $(ss -Hltn "sport = :$1" 2>/dev/null) ]]
}

service_active() {
    command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$1"
}

api_key() { as_llm cat "$KEY_FILE"; }

api() { # <method> <base url> <path> [json body file]
    local method=$1 base=$2 path=$3 body=${4:-}
    local -a args=(-sS --fail-with-body --max-time "$REQUEST_TIMEOUT" -X "$method"
        -H "Authorization: Bearer $API_KEY" -H 'Content-Type: application/json')
    [[ -n $body ]] && args+=(--data-binary "@$body")
    curl "${args[@]}" "$base$path"
}

# Wait until GET <base>/health returns 200. Optional pid: fail early if that process dies.
wait_ready() {
    local base=$1 timeout=$2 pid=${3:-} start=$SECONDS
    while ((SECONDS - start < timeout)); do
        if [[ -n $pid ]] && ! kill -0 "$pid" 2>/dev/null; then
            return 1
        fi
        if curl -sf -o /dev/null --max-time 5 "$base/health"; then
            return 0
        fi
        sleep 5
    done
    return 1
}

gpu_query() { # prints "index,name,total MiB,free MiB,compute cap" per GPU
    nvidia-smi --query-gpu=index,name,memory.total,memory.free,compute_cap --format=csv,noheader,nounits |
        sed 's/, /,/g'
}

# Deterministic filler text, one numbered record per line.
gen_filler() { # <lines> <seed>
    awk -v n="$1" -v seed="$2" 'BEGIN {
        split("amber basalt cedar delta ember fjord granite harbor iris juniper kelp lantern meadow nickel orchard pebble quartz river saffron timber umber valley willow xenon yarrow zephyr anchor bramble canyon dune", w, " ")
        srand(seed)
        for (i = 1; i <= n; i++) {
            line = sprintf("Record %06d:", i)
            for (j = 0; j < 12; j++) line = line " " w[int(rand() * 30) + 1]
            print line "."
        }
    }'
}
