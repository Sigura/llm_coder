#!/usr/bin/env bash
# One-off: pair-programming eval with DeepSeek as both navigator and driver, against the KTransformers server on
# :8080 (stack config deepseek-v4.1-flash-1017-fp8). The driver uses DeepSeek's solo-eval sampling (temperature 1,
# top_p 1, nothing else), not eval_pair.py's Qwen defaults. Seeds run one after another (default 1 2 3); a finished
# seed is skipped and an interrupted one resumes from eval_pair.py's partial file.
set -euo pipefail
cd "$(dirname "$0")"
source ./lib.sh
load_global
SEEDS=${SEEDS:-1 2 3}
URL=http://127.0.0.1:8080/v1
KEY=$SECRETS_DIR/deepseek-v4.1-flash-1017.key
OUT=$RESULTS_DIR/pair-eval

echo "== step 1: check prerequisites"
for tool in python3 bash kotlinc curl; do command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }; done
[[ -r $KEY ]] || { echo "no key file $KEY" >&2; exit 1; }
curl -sf -m 60 -o /dev/null "${URL%/v1}/health" || { echo "no server on $URL" >&2; exit 1; }

for seed in $SEEDS; do
    label=pair-deepseek-nav-deepseek-kt-s$seed
    if ls "$OUT"/*-"$label".json >/dev/null 2>&1; then
        echo "== seed $seed already done"
        continue
    fi
    echo "== $(date +%T) seed $seed ($label)"
    python3 eval_pair.py --nav-url "$URL" --nav-model deepseek-v4.1-flash --nav-key-file "$KEY" \
        --driver-url "$URL" --driver-model deepseek-v4.1-flash --driver-key-file "$KEY" \
        --driver-temperature 1.0 --driver-top-p 1.0 --driver-top-k -1 --driver-min-p 0 --driver-presence-penalty 0 \
        --seed "$seed" --label "$label"
done
echo "== $(date +%T) done"
