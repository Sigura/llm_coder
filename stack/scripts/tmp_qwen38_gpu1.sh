#!/usr/bin/env bash
# One-off: a second Qwen3.8-27B on GPU 1 (3090 Ti), port 8087, for tmp_pair_queue_b2.sh's Qwen runs (Q8_URL), so they
# stop sharing GPU 2 with the DeepSeek stream's Qwen3.8 navigator, 2026-11-22. Same command as llm-serve.sh.
set -euo pipefail
cd "$(dirname "$0")"
echo "== step 1: build the server command"
cmd=$(./llm-serve.sh --dry-run qwen3.8-27b 2>/dev/null | tail -n 1)
[[ $cmd == *" -dev CUDA2 "* && $cmd == *" --port 8086 "* ]] || { echo "unexpected command: $cmd" >&2; exit 1; }
cmd=${cmd/ -dev CUDA2 / -dev CUDA1 }
cmd=${cmd/ --port 8086 / --port 8087 }
echo "== step 2: start on GPU 1, port 8087"
# The dry run prints the command without global.env's device order; CUDA would otherwise number the 4090s first.
export CUDA_DEVICE_ORDER=PCI_BUS_ID
eval "exec $cmd"
