#!/usr/bin/env bash
# One-off: a second Qwen3.8-27B on GPU 3, port 8087, with thinking allowed (--reasoning-budget -1 instead of 0), for
# the thinking-check replays (2026-11-25). The :8086 server forces thinking off whatever the request asks.
# Otherwise the same command as llm-serve.sh, sampling included.
set -euo pipefail
cd "$(dirname "$0")"
echo "== step 1: build the server command"
cmd=$(./llm-serve.sh --dry-run qwen3.8-27b 2>/dev/null | tail -n 1)
[[ $cmd == *" -dev CUDA2 "* && $cmd == *" --port 8086 "* && $cmd == *" --reasoning-budget 0 "* ]] ||
    { echo "unexpected command: $cmd" >&2; exit 1; }
cmd=${cmd/ -dev CUDA2 / -dev CUDA3 }
cmd=${cmd/ --port 8086 / --port 8087 }
cmd=${cmd/ --reasoning-budget 0 / --reasoning-budget -1 }
echo "== step 2: start on GPU 3, port 8087, thinking allowed"
export CUDA_DEVICE_ORDER=PCI_BUS_ID
eval "exec $cmd"
