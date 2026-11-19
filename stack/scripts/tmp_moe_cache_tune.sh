#!/usr/bin/env bash
# One-off: run llama.cpp's scripts/moe-cache-tune.py (pinned engine) on DeepSeek with the serving arguments.
# Usage: tmp_moe_cache_tune.sh [ot|cpu]...   (default: both)
#   ot  = current layout: experts of layers 18,19 / 38,39 on the GPUs, cache in the VRAM left over
#   cpu = all experts in host RAM, the freed VRAM goes to the cache
# Needs GPUs 0,1 free (DeepSeek service stopped). Results: LLM_ROOT/results/moe-cache-<date>/<variant>/
set -euo pipefail
source "$(dirname "$0")/lib.sh"

MODEL=deepseek-v4.1-flash-1017
VARIANTS=("$@")
((${#VARIANTS[@]})) || VARIANTS=(cpu ot)

load_global
load_model "$MODEL"
require_cmd python3 nvidia-smi git

commit=$(lock_get engine llama.cpp | cut -f3)
[[ -n $commit ]] || die "no engine pinned in versions.lock"
OUT=$RESULTS_DIR/moe-cache-$(date +%F)
mkdir -p "$OUT"
TUNE=$OUT/moe-cache-tune.py
info "step 1: extract moe-cache-tune.py at engine commit $commit"
git -C "$ENGINE_SRC" show "$commit:scripts/moe-cache-tune.py" >"$TUNE"

info "step 2: check GPUs 0,1 are free"
while IFS=, read -r idx used; do
    ((used < 2000)) || die "GPU $idx has $used MiB in use: stop the DeepSeek service first"
done < <(nvidia-smi --query-gpu=index,memory.used --format=csv,noheader,nounits -i 0,1)

info "step 3: warm the page cache (even over the NUMA nodes)"
"$STACK_DIR/scripts/25-warm-cache.sh" "$MODEL"

build_server_cmd
base=()
for ((i = 0; i < ${#SERVER_CMD[@]}; i++)); do
    case ${SERVER_CMD[i]} in
    --host | --port | --api-key-file) i=$((i + 1)) ;;
    *) base+=("${SERVER_CMD[i]}") ;;
    esac
done

for v in "${VARIANTS[@]}"; do
    cmd=()
    for ((i = 0; i < ${#base[@]}; i++)); do
        if [[ $v == cpu && ${base[i]} == -ot ]]; then
            cmd+=(-ot "per_layer_token_embd.weight=CPU,ffn_(up|gate|down)_exps=CPU")
            i=$((i + 1))
        else
            cmd+=("${base[i]}")
        fi
    done
    [[ $v == ot || $v == cpu ]] || die "unknown variant $v (ot or cpu)"
    # the tuner's first cache size is 10% of the host experts (~18 GiB), more than the VRAM left in the ot layout
    small=0.10
    [[ $v == ot ]] && small=0.02
    # the tuner measures the room on the first cache device only, the cache is split over both GPUs
    sed -e "s/small = rnd(0.10 \* expert_mib(model))/small = rnd($small * expert_mib(model))/" \
        -e "s/room = int(free - used - 512)$/room = 2 * int(free - used - 512)/" "$TUNE" >"$OUT/tune-$v.py"
    grep -q "small = rnd($small \*" "$OUT/tune-$v.py" || die "could not set the small cache size in $OUT/tune-$v.py"
    grep -q "room = 2 \* int" "$OUT/tune-$v.py" || die "could not set the cache room in $OUT/tune-$v.py"
    info "step 4/$v: tune (first cache size ${small} of the host experts), runs in $OUT/$v"
    info "command: ${cmd[*]}"
    python3 "$OUT/tune-$v.py" --out "$OUT/$v" --markdown -- "${cmd[@]}" | tee "$OUT/$v.md"
done
info "done: $OUT/*.md"
