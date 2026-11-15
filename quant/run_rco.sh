#!/usr/bin/env bash
# Runs the Coder-Next RCO pipeline end to end on GPUs 2,3 (+ CPU for the bf16 steps). Every step skips work it
# already finished, so it can be re-run after an interruption.
# Usage: quant/run_rco.sh            Env: BUDGETS="33 35 37" (GiB targets), RCO_THREADS (default 48)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LLM_ROOT="${LLM_ROOT:-$HOME/llm_coder/llm}"
WORK="$LLM_ROOT/quant-work"
BIN="$LLM_ROOT/engines/llama.cpp-current/bin"
BF16="$LLM_ROOT/models/qwen3-coder-next-bf16/current/BF16/Qwen3-Coder-Next-BF16-00001-of-00004.gguf"
BUDGETS="${BUDGETS:-33 35 37}"
export LLM_ROOT CUDA_DEVICE_ORDER=PCI_BUS_ID CUDA_VISIBLE_DEVICES=2,3

echo "== checking prerequisites"
for b in llama-imatrix llama-perplexity llama-quantize llama-gguf-split; do
    [[ -x "$BIN/$b" ]] || { echo "missing $BIN/$b" >&2; exit 1; }
done
[[ -f "$BF16" ]] || { echo "missing $BF16: run stack/scripts/20-download-model.sh qwen3-coder-next-bf16" >&2; exit 1; }
[[ -d "$WORK/gguf-py/gguf" ]] || { echo "missing $WORK/gguf-py (git archive it from the engine source)" >&2; exit 1; }
python3 -c "import numpy" || { echo "numpy missing in the conda env (environment.yaml)" >&2; exit 1; }

step() { echo; echo "== $*"; python3 -I "$HERE/coder_next_rco.py" "$@"; }

[[ -f "$WORK/data/test.txt" ]] || { echo "== calibration data"; python3 -I "$HERE/make_calib.py" "$WORK/data"; }
[[ -f "$WORK/imatrix.gguf" ]] || step imatrix
[[ -f "$WORK/kld/bf16.kld" ]] || step kld-base
step quantize
step sweep
for b in $BUDGETS; do
    step allocate --budget-gib "$b"
    step build --budget-gib "$b"
done
