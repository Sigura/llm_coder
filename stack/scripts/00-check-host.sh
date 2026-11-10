#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: $0 [--dry-run] [model-id]

Pre-flight checks: tools, driver/CUDA, GPU count and compute capability, CPU/NUMA,
RAM, layout under LLM_ROOT, disk space. With a model id also checks the port and
the free space needed for its download. Exits 1 if any check FAILs.
--dry-run is accepted for consistency; this script never changes anything.
EOF
}

MODEL=""
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    -*) die "unknown option $1" ;;
    *) MODEL=$1 ;;
    esac
    shift
done

load_global
[[ -n $MODEL ]] && load_model "$MODEL"
init_logging "$MODEL"

FAILS=0
WARNS=0
pass() { info "PASS  $*"; }
fail() { log FAIL "FAIL  $*"; FAILS=$((FAILS + 1)); }
warnc() { warn "WARN  $*"; WARNS=$((WARNS + 1)); }

version_ge() { [[ $(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1) == "$2" ]]; }

# tools
read -ra tools <<<"$REQUIRED_TOOLS"
missing=()
for t in "${tools[@]}"; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
if ((${#missing[@]})); then fail "missing tools: ${missing[*]} (see 05-bootstrap-host.sh)"; else pass "tools: ${tools[*]}"; fi
if [[ -x $HF_CLI ]]; then pass "hf CLI: $HF_CLI ($("$HF_CLI" version 2>/dev/null | head -1))"; else fail "hf CLI not executable: $HF_CLI"; fi

# driver + GPUs
if command -v nvidia-smi >/dev/null 2>&1; then
    drv=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    if version_ge "$drv" "$MIN_DRIVER_VERSION"; then pass "driver $drv >= $MIN_DRIVER_VERSION"; else fail "driver $drv < $MIN_DRIVER_VERSION"; fi
    mapfile -t gpus < <(gpu_query)
    if ((${#gpus[@]} == EXPECTED_GPUS)); then pass "GPU count ${#gpus[@]}"; else fail "GPU count ${#gpus[@]}, expected $EXPECTED_GPUS"; fi
    archs=";$CUDA_ARCHS;"
    for g in "${gpus[@]}"; do
        IFS=, read -r idx name total free cc <<<"$g"
        sm=${cc/./}
        if [[ $archs == *";$sm;"* ]]; then
            pass "GPU$idx $name sm_$sm, ${free}/${total} MiB free"
        else
            fail "GPU$idx $name sm_$sm not in CUDA_ARCHS=$CUDA_ARCHS"
        fi
    done
else
    fail "nvidia-smi not found"
fi

# CUDA toolkit
nvcc=$CUDA_HOME/bin/nvcc
[[ -x $nvcc ]] || nvcc=$(command -v nvcc || true)
if [[ -n $nvcc && -x $nvcc ]]; then
    cver=$("$nvcc" --version | sed -n 's/.*release \([0-9.]*\).*/\1/p')
    if version_ge "$cver" "$MIN_CUDA_VERSION"; then pass "nvcc $cver ($nvcc)"; else fail "nvcc $cver < $MIN_CUDA_VERSION"; fi
else
    fail "nvcc not found in $CUDA_HOME/bin or PATH (CUDA toolkit needed for 10-build-engine.sh)"
fi

# CPU / NUMA / RAM
cores=$(physical_cores "")
n_nodes=$(lscpu -p=NODE | grep -v '^#' | sort -u | wc -l)
pass "CPU: $(lscpu | sed -n 's/^Model name:[[:space:]]*//p'), $cores physical cores, $n_nodes NUMA nodes"
for n in $(lscpu -p=NODE | grep -v '^#' | sort -nu); do
    info "      node$n: $(physical_cores "$n") cores, CPUs $(lscpu | sed -n "s/^NUMA node$n CPU(s):[[:space:]]*//p")"
done
if grep -qw avx2 /proc/cpuinfo; then pass "AVX2 present"; else fail "no AVX2"; fi
grep -qw avx512f /proc/cpuinfo || info "      no AVX-512 (expected on Zen 1/2)"
ram_gb=$(awk '/MemTotal/ { printf "%d", $2 / 1048576 }' /proc/meminfo)
pass "RAM ${ram_gb} GiB"
if command -v nvidia-smi >/dev/null 2>&1 && command -v numactl >/dev/null 2>&1; then
    nvidia-smi topo -m 2>/dev/null | awk '/^GPU[0-9]/ { print "      " $1 " NUMA affinity: " $(NF-1) }' | while IFS= read -r l; do info "$l"; done
fi

# layout
if [[ -d $LLM_ROOT ]]; then
    owner=$(stat -c %U "$LLM_ROOT")
    if [[ $owner == "$LLM_USER" ]]; then pass "$LLM_ROOT owned by $owner"; else fail "$LLM_ROOT owned by $owner, expected $LLM_USER"; fi
    for d in engines models secrets results logs state; do
        [[ -d $LLM_ROOT/$d ]] || fail "missing $LLM_ROOT/$d (run 05-bootstrap-host.sh)"
    done
    [[ -d $LLM_ROOT/secrets && $(stat -c %a "$LLM_ROOT/secrets") != 700 ]] && fail "$LLM_ROOT/secrets mode is not 700"
else
    fail "$LLM_ROOT does not exist (run 05-bootstrap-host.sh)"
fi
if id "$LLM_USER" >/dev/null 2>&1; then pass "user $LLM_USER exists"; else fail "user $LLM_USER missing"; fi
if git -C "$STACK_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then pass "stack is a git repo ($STACK_DIR)"; else warnc "stack $STACK_DIR is not a git repo"; fi
if command -v systemctl >/dev/null 2>&1; then pass "systemd available"; else warnc "systemctl not found (service install will not work here)"; fi

# disk
probe=$LLM_ROOT/models
while [[ ! -e $probe ]]; do probe=$(dirname "$probe"); done
read -r dev avail_kb mnt < <(df -Pk "$probe" | awk 'NR == 2 { print $1, $4, $6 }')
pass "models dir on $dev ($mnt), $((avail_kb / 1048576)) GiB free"
largest=$(lsblk -dbno NAME,SIZE,TYPE 2>/dev/null | awk '$3 == "disk" && $1 ~ /^nvme/' | sort -k2 -n | tail -1 | awk '{print $1}')
if [[ -n $largest ]]; then
    if ! pk=$(lsblk -no PKNAME "$dev" 2>/dev/null); then
        warnc "cannot resolve the disk behind $dev; largest NVMe is $largest"
    elif [[ ${pk:-${dev##*/}} == "$largest"* ]]; then
        pass "models dir is on the largest NVMe ($largest)"
    else
        warnc "models dir is on ${pk:-$dev}, largest NVMe is $largest"
    fi
fi

# model-specific
if [[ -n $MODEL ]]; then
    if port_in_use "$PORT"; then
        if service_active "$SERVICE"; then pass "port $PORT held by $SERVICE"; else fail "port $PORT already in use"; fi
    else
        pass "port $PORT free"
    fi
    meta=$MODEL_DIR/.meta-$HF_REVISION.json
    if [[ -f $meta ]]; then
        need=$(jq '[.siblings[].size // 0] | add' "$meta")
        info "      repo revision total: $((need / 1000000000)) GB (selected files are checked by 20-download-model.sh)"
    fi
    numa_settings "$NUMA_MODE"
    pass "NUMA_MODE=$NUMA_MODE -> ${NUMA_PREFIX[*]:-no prefix} ${NUMA_FLAG[*]:-}, threads $(resolve_threads)"
fi

info "summary: $FAILS failed, $WARNS warnings"
((FAILS == 0))
