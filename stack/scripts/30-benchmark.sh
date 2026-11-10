#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: $0 [--dry-run] [--phases fit,numa,spec] [--reps N] [--no-write] <model-id>

Tunes and benchmarks <model-id> with its own llama-server on BENCH_PORT (the service must be stopped).
  fit   binary-search the smallest N_CPU_MOE (most routed-expert layers on GPU) that keeps
        VRAM_MARGIN_MIB free on every GPU at CTX, starting from a TENSOR_SPLIT weighted by
        GPU_SHARE_FACTORS, then shift the split toward GPUs with slack
  numa  for each TUNE_NUMA_MODES: prompt processing 4096 and 32768 tokens, generation 512 tokens
  spec  the same with the SPEC_DRAFT_GGUF drafter (SPEC_ARGS), re-fitted for the drafter's VRAM
Winner = highest sqrt(pp32768 * tg512). Writes LLM_ROOT/results/<model>/<date>.md, updates
N_CPU_MOE, TENSOR_SPLIT, NUMA_MODE, SPEC_ENABLED in the model .env and commits it (unless --no-write).
Expect 1-3 hours for a 300 GB model: every probe reloads it.
EOF
}

MODEL=""
PHASES=fit,numa,spec
WRITE=1
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    --phases) PHASES=$2; shift ;;
    --reps) BENCH_REPS=$2; shift ;;
    --no-write) WRITE=0 ;;
    -*) die "unknown option $1" ;;
    *) MODEL=$1 ;;
    esac
    shift
done
[[ -n $MODEL ]] || { usage; exit 2; }
has_phase() { [[ ,$PHASES, == *",$1,"* ]]; }

load_global
load_model "$MODEL"
require_llm_user "$@"
init_logging "$MODEL_ID"
require_cmd curl jq nvidia-smi awk
require_engine_ref "${MIN_ENGINE_REF:-}"
require_model_verified
service_active "$SERVICE" && die "$SERVICE is running and holds the GPUs; stop it first: sudo systemctl stop $SERVICE"
port_in_use "$BENCH_PORT" && die "BENCH_PORT $BENCH_PORT is in use"

mapfile -t GPU_ROWS < <(gpu_query)
NGPU=${#GPU_ROWS[@]}
((NGPU > 0)) || die "no GPUs visible"
declare -a GPU_NAME GPU_TOTAL GPU_FREE0
for row in "${GPU_ROWS[@]}"; do
    IFS=, read -r idx name total free _ <<<"$row"
    GPU_NAME[idx]=$name
    GPU_TOTAL[idx]=$total
    GPU_FREE0[idx]=$free
done

if has_phase numa || has_phase spec; then
    for mode in $TUNE_NUMA_MODES $NUMA_MODE; do
        if [[ $mode == interleave || $mode == node* ]]; then require_cmd numactl; fi
    done
fi

if ((DRY_RUN)); then
    info "[dry-run] phases=$PHASES reps=$BENCH_REPS GPUs=$NGPU margin=${VRAM_MARGIN_MIB}MiB numa modes: $TUNE_NUMA_MODES"
    SRV_PORT=$BENCH_PORT SRV_HOST=127.0.0.1 build_server_cmd
    info "[dry-run] base server command: $(printf '%q ' "${SERVER_CMD[@]}")"
    exit 0
fi

ensure_key
API_KEY=$(api_key)
STAMP=$(date +%Y-%m-%d)
OUT_DIR=$RESULTS_DIR/$MODEL_ID
REPORT=$OUT_DIR/$STAMP.md
[[ -e $REPORT ]] && REPORT=$OUT_DIR/$STAMP-$(date +%H%M).md
WORK=$OUT_DIR/work-$(date +%Y%m%d-%H%M%S)
mkdir -p "$WORK"
BASE=http://127.0.0.1:$BENCH_PORT
SRV_PID=""
SERVER_LOG=""

stop_server() {
    [[ -n $SRV_PID ]] || return 0
    kill "$SRV_PID" 2>/dev/null || true
    for _ in $(seq 90); do kill -0 "$SRV_PID" 2>/dev/null || break; sleep 1; done
    kill -9 "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
    SRV_PID=""
}
trap stop_server EXIT

CACHE_NOTE="page cache dropped before each NUMA mode"
drop_caches() {
    if sudo -n /usr/local/sbin/llm-drop-caches 2>/dev/null; then
        info "dropped page cache"
    else
        CACHE_NOTE="page cache NOT dropped (05-bootstrap-host.sh --allow-drop-caches not set up): pages stay where the first run placed them, so NUMA results are biased"
        warn "$CACHE_NOTE"
    fi
}

LOAD_SECONDS=0
start_server() { # <label>; uses SRV_NCMOE SRV_TS SRV_NUMA SRV_SPEC
    local label=$1 start=$SECONDS
    SRV_PORT=$BENCH_PORT SRV_HOST=127.0.0.1 build_server_cmd
    # -lv 4 makes the loader print model info (n_layer) that the fit search needs.
    SERVER_CMD+=(-lv 4)
    SERVER_LOG=$WORK/server-$label.log
    info "starting server [$label]: ncmoe=$SRV_NCMOE ts=${SRV_TS:-auto} numa=$SRV_NUMA spec=$SRV_SPEC"
    printf '%q ' "${SERVER_CMD[@]}" >"$SERVER_LOG"
    echo >>"$SERVER_LOG"
    "${SERVER_CMD[@]}" >>"$SERVER_LOG" 2>&1 &
    SRV_PID=$!
    if wait_ready "$BASE" "$SERVER_READY_TIMEOUT" "$SRV_PID"; then
        LOAD_SECONDS=$((SECONDS - start))
        info "server ready after ${LOAD_SECONDS}s"
        return 0
    fi
    warn "server [$label] did not start; last log lines:"
    tail -n 5 "$SERVER_LOG" >&2
    stop_server
    return 1
}

# Token-exact prompts, built once with the model's tokenizer.
pp_payload() { # <tokens> -> file path
    local n=$1 f=$WORK/pp-$1.json per_line lines
    if [[ ! -s $f ]]; then
        gen_filler 400 3 | jq -Rs '{content: .}' >"$WORK/tok.json"
        per_line=$(api POST "$BASE" /tokenize "$WORK/tok.json" | jq '.tokens | length / 400')
        lines=$(awk -v n="$n" -v p="$per_line" 'BEGIN { printf "%d", n / p * 1.1 + 10 }')
        gen_filler "$lines" 5 | jq -Rs '{content: .}' >"$WORK/tok.json"
        api POST "$BASE" /tokenize "$WORK/tok.json" |
            jq -c --argjson n "$n" '{prompt: .tokens[:$n], n_predict: 1, cache_prompt: false, temperature: 0}' >"$f"
        [[ $(jq '.prompt | length' "$f") -eq $n ]] || die "could not build a $n-token prompt"
    fi
    echo "$f"
}

TG_PAYLOAD=$WORK/tg.json
jq -n --arg m "$ALIAS" '{model: $m, max_tokens: 512, ignore_eos: true, temperature: 0,
    messages: [{role: "user", content: "Write a Python module implementing a thread-safe LRU cache with TTL support, type hints, docstrings and pytest unit tests."}]}' >"$TG_PAYLOAD"

measure_pp() { # <tokens> -> tokens/s
    local f
    f=$(pp_payload "$1")
    api POST "$BASE" /completion "$f" | jq -er '.timings.prompt_per_second'
}
measure_tg() { # -> "tokens/s acceptance"
    api POST "$BASE" /v1/chat/completions "$TG_PAYLOAD" |
        jq -er '.timings | "\(.predicted_per_second) \(if (.draft_n // 0) > 0 then (.draft_n_accepted / .draft_n * 100 | floor | tostring) + "%" else "-" end)"'
}
mean() { awk '{ s += $1; n++ } END { if (n) printf "%.1f", s / n; else print "nan" }'; }

gpu_free_now() { nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | paste -sd, -; }

initial_ts() {
    local i f factor pat out=()
    local -a rules
    read -ra rules <<<"${GPU_SHARE_FACTORS:-}"
    for ((i = 0; i < NGPU; i++)); do
        factor=1
        for f in "${rules[@]}"; do
            pat=${f%%=*}
            [[ ${GPU_NAME[i]} == *"$pat"* ]] && factor=${f#*=}
        done
        out+=("$(awk -v t="${GPU_TOTAL[i]}" -v m="$VRAM_MARGIN_MIB" -v f="$factor" 'BEGIN { printf "%.1f", (t - m) * f / 1024 }')")
    done
    (IFS=,; echo "${out[*]}")
}

# Scale each GPU's weight by (allowed use) / (actual use) measured at a fitting configuration.
rebalance_ts() { # <ts> <free list>
    awk -v ts="$1" -v free="$2" -v base="$(IFS=,; echo "${GPU_FREE0[*]}")" -v m="$VRAM_MARGIN_MIB" 'BEGIN {
        n = split(ts, w, ","); split(free, f, ","); split(base, b, ",")
        for (i = 1; i <= n; i++) {
            used = b[i] - f[i]; cap = b[i] - m
            nw[i] = (used > 0) ? w[i] * cap / used : w[i]
            s += nw[i]; s0 += w[i]
        }
        for (i = 1; i <= n; i++) printf "%s%.1f", (i > 1 ? "," : ""), nw[i] * s0 / s
        print ""
    }'
}

PROBE_FREE=""
FIT_ROWS=()
probe() { # <ncmoe> <ts> <spec> -> 0 fits with margin, 1 below margin, 2 failed to start
    local ncmoe=$1 ts=$2 spec=$3 rc min
    SRV_NCMOE=$ncmoe SRV_TS=$ts SRV_NUMA=$NUMA_MODE SRV_SPEC=$spec
    if ! start_server "fit-$ncmoe-spec$spec"; then
        FIT_ROWS+=("| $ncmoe | $ts | $spec | failed to load | - |")
        return 2
    fi
    if ! measure_pp 4096 >/dev/null || ! kill -0 "$SRV_PID" 2>/dev/null; then
        stop_server
        FIT_ROWS+=("| $ncmoe | $ts | $spec | failed under load | - |")
        warn "probe ncmoe=$ncmoe: server failed while processing a 4096-token prompt"
        return 2
    fi
    PROBE_FREE=$(gpu_free_now)
    stop_server
    min=$(tr , '\n' <<<"$PROBE_FREE" | sort -n | head -1)
    if ((min >= VRAM_MARGIN_MIB)); then rc=0; else rc=1; fi
    FIT_ROWS+=("| $ncmoe | $ts | $spec | $([[ $rc == 0 ]] && echo fits || echo "below margin") | $PROBE_FREE |")
    info "probe ncmoe=$ncmoe ts=$ts spec=$spec -> free MiB $PROBE_FREE ($([[ $rc == 0 ]] && echo fits || echo 'below margin'))"
    return $rc
}

N_LAYER=""
read_n_layer() { # from the log of the last server start (needs -lv 4)
    N_LAYER=$(grep -oE 'n_layer += [0-9]+' "$SERVER_LOG" | head -1 | grep -oE '[0-9]+$') ||
        die "could not read n_layer from $SERVER_LOG"
    info "model has $N_LAYER layers"
}

# Binary search for the smallest n-cpu-moe in (lo, hi] that fits; hi must already be known to fit.
bisect_ncmoe() { # <spec> <ts> <lo> <hi> <free at hi>; sets FIT_N FIT_FREE
    local spec=$1 ts=$2 lo=$3 hi=$4 mid
    FIT_FREE=$5
    while ((hi - lo > 1)); do
        mid=$(((lo + hi) / 2))
        if probe "$mid" "$ts" "$spec"; then hi=$mid; FIT_FREE=$PROBE_FREE; else lo=$mid; fi
    done
    FIT_N=$hi
}

BEST_NCMOE=$N_CPU_MOE
BEST_TS=$TENSOR_SPLIT
if has_phase fit; then
    ts=${TENSOR_SPLIT:-$(initial_ts)}
    probe 999 "$ts" 0 || die "does not fit even with all routed experts on CPU; lower CTX or -ub/-b in EXTRA_ARGS"
    read_n_layer
    bisect_ncmoe 0 "$ts" -1 "$N_LAYER" "$PROBE_FREE"
    hi=$FIT_N
    hi_free=$FIT_FREE
    for ((r = 1; r <= TUNE_REBALANCE_ROUNDS && hi > 0; r++)); do
        ts2=$(rebalance_ts "$ts" "$hi_free")
        [[ $ts2 == "$ts" ]] && break
        if probe "$((hi - 1))" "$ts2" 0; then
            hi=$((hi - 1)); ts=$ts2; hi_free=$PROBE_FREE
        else
            break
        fi
    done
    BEST_NCMOE=$hi
    BEST_TS=$ts
    info "fit result: N_CPU_MOE=$BEST_NCMOE TENSOR_SPLIT=$BEST_TS (free MiB $hi_free)"
fi

ROWS=()
SCORE_BEST=0
WIN_NUMA=$NUMA_MODE
WIN_SPEC=0
WIN_NCMOE=$BEST_NCMOE

# Records a table row; a server that fails to load is recorded, a failed request aborts the run.
bench_config() { # <label> <ncmoe> <ts> <numa> <spec>
    local label=$1 pp4=() pp32=() tg=() acc="-" r a b c v t out score
    SRV_NCMOE=$2 SRV_TS=$3 SRV_NUMA=$4 SRV_SPEC=$5
    if ! start_server "$label"; then
        ROWS+=("| $label | $2 | ${3:-auto} | $4 | - | $5 | failed to load | | | | | |")
        return 0
    fi
    measure_pp 512 >/dev/null
    for ((r = 1; r <= BENCH_REPS; r++)); do
        v=$(measure_pp 4096)
        pp4+=("$v")
        v=$(measure_pp 32768)
        pp32+=("$v")
        out=$(measure_tg)
        read -r t acc <<<"$out"
        tg+=("$t")
        info "[$label] rep $r: $(printf 'pp4096=%.1f pp32768=%.1f tg512=%.2f' "${pp4[-1]}" "${pp32[-1]}" "$t") draft-accept=$acc"
    done
    stop_server
    a=$(printf '%s\n' "${pp4[@]}" | mean)
    b=$(printf '%s\n' "${pp32[@]}" | mean)
    c=$(printf '%s\n' "${tg[@]}" | mean)
    score=$(awk -v b="$b" -v c="$c" 'BEGIN { printf "%.2f", sqrt(b * c) }')
    ROWS+=("| $label | $2 | ${3:-auto} | $4 | $(numa_settings "$4"; resolve_threads) | $5 | $LOAD_SECONDS | $a | $b | $c | $acc | $score |")
    if awk -v s="$score" -v best="$SCORE_BEST" 'BEGIN { exit !(s > best) }'; then
        SCORE_BEST=$score
        WIN_NUMA=$4
        WIN_SPEC=$5
        WIN_NCMOE=$2
    fi
}

if has_phase numa; then
    read -ra modes <<<"$TUNE_NUMA_MODES"
    for mode in "${modes[@]}"; do
        drop_caches
        bench_config "numa-$mode" "$BEST_NCMOE" "$BEST_TS" "$mode" 0
    done
fi

if has_phase spec; then
    if [[ -z ${SPEC_DRAFT_GGUF:-} || ! -f $MODEL_CURRENT/$SPEC_DRAFT_GGUF ]]; then
        warn "spec phase skipped: SPEC_DRAFT_GGUF not set or not downloaded"
    else
        if ((${#ROWS[@]} == 0)); then
            bench_config "baseline-$NUMA_MODE" "$BEST_NCMOE" "$BEST_TS" "$NUMA_MODE" 0
        fi
        spec_ncmoe=""
        if probe "$BEST_NCMOE" "$BEST_TS" 1; then
            spec_ncmoe=$BEST_NCMOE
        elif probe 999 "$BEST_TS" 1; then
            [[ -n $N_LAYER ]] || read_n_layer
            lo=$((BEST_NCMOE < N_LAYER ? BEST_NCMOE : N_LAYER - 1))
            bisect_ncmoe 1 "$BEST_TS" "$lo" "$N_LAYER" "$PROBE_FREE"
            spec_ncmoe=$FIT_N
        fi
        if [[ -n $spec_ncmoe ]]; then
            info "drafter fits with N_CPU_MOE=$spec_ncmoe"
            bench_config "spec-$WIN_NUMA" "$spec_ncmoe" "$BEST_TS" "$WIN_NUMA" 1
        else
            warn "drafter does not fit even with every routed expert on CPU; spec decoding not benchmarked"
        fi
    fi
fi

{
    echo "# Benchmark: $MODEL_ID ($(date '+%Y-%m-%d %H:%M'))"
    echo
    echo "- engine: $(readlink -f "$ENGINE_CURRENT") ($(engine_build_info "$ENGINE_CURRENT" commit))"
    echo "- model: $HF_REPO @ $HF_REVISION, \`$MAIN_GGUF\`"
    echo "- host: $(lscpu | sed -n 's/^Model name:[[:space:]]*//p') x$(lscpu | sed -n 's/^Socket(s):[[:space:]]*//p'), $(physical_cores "") physical cores, $(lscpu -p=NODE | grep -v '^#' | sort -u | wc -l) NUMA nodes, $(awk '/MemTotal/ { printf "%d", $2 / 1048576 }' /proc/meminfo) GiB RAM"
    for ((i = 0; i < NGPU; i++)); do echo "- GPU$i: ${GPU_NAME[i]}, ${GPU_TOTAL[i]} MiB (${GPU_FREE0[i]} free before start)"; done
    echo "- CTX=$CTX, VRAM margin ${VRAM_MARGIN_MIB} MiB, reps $BENCH_REPS, $CACHE_NOTE"
    echo "- EXTRA_ARGS: \`$EXTRA_ARGS\`"
    echo "- raw logs: $WORK"
    if ((${#FIT_ROWS[@]})); then
        echo
        echo "## Fit probes"
        echo
        echo "| n-cpu-moe | tensor-split | spec | result | free MiB per GPU |"
        echo "|---|---|---|---|---|"
        printf '%s\n' "${FIT_ROWS[@]}"
    fi
    if ((${#ROWS[@]})); then
        echo
        echo "## Throughput (tokens/s, mean of $BENCH_REPS)"
        echo
        echo "| config | n-cpu-moe | tensor-split | NUMA | threads | spec | load s | pp4096 | pp32768 | tg512 | draft accept | score |"
        echo "|---|---|---|---|---|---|---|---|---|---|---|---|"
        printf '%s\n' "${ROWS[@]}"
        echo
        echo "Score = sqrt(pp32768 x tg512). Winner: NUMA_MODE=$WIN_NUMA, SPEC_ENABLED=$WIN_SPEC, N_CPU_MOE=$WIN_NCMOE, TENSOR_SPLIT=$BEST_TS"
    fi
} >"$REPORT"
info "report: $REPORT"
cat "$REPORT"

if ((WRITE)); then
    if has_phase fit || ((${#ROWS[@]})); then
        set_env_kv "$MODEL_ENV" N_CPU_MOE "$WIN_NCMOE"
        set_env_kv "$MODEL_ENV" TENSOR_SPLIT "$BEST_TS"
    fi
    if ((${#ROWS[@]})); then
        set_env_kv "$MODEL_ENV" NUMA_MODE "$WIN_NUMA"
        set_env_kv "$MODEL_ENV" SPEC_ENABLED "$WIN_SPEC"
    fi
    git_commit "bench: $MODEL_ID N_CPU_MOE=$WIN_NCMOE TENSOR_SPLIT=$BEST_TS NUMA_MODE=$WIN_NUMA SPEC_ENABLED=$WIN_SPEC (score $SCORE_BEST, $(basename "$REPORT"))" "config/models/$MODEL_ID.env"
fi
