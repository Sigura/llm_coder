# llm_coder

Local coding models on one host (2x EPYC 7601, 503 GB RAM, 3x RTX 4090 + RTX 3090 Ti): build and serve them,
point OpenCode at them, and measure which model or pipeline writes the best code. The default setup is DeepSeek
V4.1 Flash on SGLang + KTransformers (port 8080) as the main model, Qwen3.8-27B (8086) as the fast one, and
Qwen3.6-35B-A3B MTP (8085) as the small model and reviewer.

| path | what |
|---|---|
| `stack/` | scripts and per-model config to build llama.cpp, download pinned weights, tune, serve and health-check ([stack/README.md](stack/README.md)) |
| `stack/config/models/<id>.env` | everything model-specific; `ENGINE=kt` serves it with KTransformers instead of llama.cpp |
| `stack/scripts/eval_*.py`, `pair_matrix.py` | coding evals on burnish's tasks (below) |
| `quant/` | Qwen3-Coder-Next RCO quantisation pipeline (`quant/run_rco.sh`) |
| `docs/` | measurements and study reports (below) |

Runtime data (engines, weights, keys, logs, results) lives outside the repo in `LLM_ROOT` (`llm/` next to
`stack/` in the devbox, `/srv/llm` on a systemd host). Every script has `--help`, and the ones that change
something have `--dry-run`.

## Serving

```bash
cd stack
make check M=qwen3.8-27b                         # pre-flight: tools, GPUs, RAM, disk, port
make build                                       # llama.cpp pinned in versions.lock
make download M=qwen3.8-27b                      # resumable, sha256-verified
make bench M=qwen3.8-27b                         # tunes the .env for this machine
sudo make install M=qwen3.8-27b                  # systemd unit + health check

scripts/llm-serve.sh --dry-run deepseek-v4.1-flash-1017-fp8   # print the command: KTransformers on GPU 0, port 8080
scripts/llm-serve.sh deepseek-v4.1-flash-1017-fp8             # run it in the foreground (~8 min to load)
scripts/llm-status.sh qwen3.8-27b                # what a served model is doing now
scripts/llm-panel.sh                             # console panel: models, RAM per NUMA node, GPUs
scripts/telemetry.sh "$LLM_ROOT/logs/telemetry-$(date +%Y%m%d).log"   # one line a second, survives a host hang
```

## Using the models

```bash
stack/scripts/opencode-local.sh                  # OpenCode here: DeepSeek default, Tab switches to Qwen3.8
stack/scripts/opencode-local.sh --auto           # through the router: Qwen3.8 up to 48k prompt tokens, then DeepSeek
stack/scripts/llm-router.sh                      # the router alone on :8090 (model "auto")
stack/scripts/llm-review.sh --task "parse INI with interpolation" src/ini.py   # independent review: OK or path:line: problem -> fix
stack/scripts/llm-review.sh --diff --task "fix the off-by-one in paging"       # review the uncommitted diff
```

## Measuring

The evals use burnish's coding tasks (`~/burnish/eval/coding`: 29 single-file tasks in Python, bash and
Kotlin with hidden tests), so pass@k and tests@k compare directly with burnish's own solo and review runs.

```bash
# pair programming: DeepSeek (KT) plans and reviews, Qwen3.8 writes the code, seed 1
python3 stack/scripts/eval_pair.py \
    --nav-url http://127.0.0.1:8080/v1 --nav-model deepseek-v4.1-flash \
    --nav-key-file "$LLM_ROOT/secrets/deepseek-v4.1-flash-1017.key" \
    --driver-url http://127.0.0.1:8086/v1 --driver-model qwen3.8-27b \
    --driver-key-file "$LLM_ROOT/secrets/qwen3.8-27b.key" \
    --seed 1 --label pair-qwen3.8-nav-deepseek-kt-s1
# same, but the navigator writes tests first and the driver fixes against them
python3 stack/scripts/eval_pair.py ... --tests-first --label pair-qwen3.8-nav-deepseek-kt-tdd-s1

python3 stack/scripts/pair_matrix.py             # print the report tables from all result files
python3 stack/scripts/pair_matrix.py --write     # update them in $LLM_ROOT/results/pair-eval/pair-report.md

python3 stack/scripts/eval_opencode.py --help    # OpenCode as an agent on the same tasks: build, review, one fix turn
```

A run writes `<label>.partial.json` as it goes and resumes from it, so it can be restarted after a hang.
Inside devbox, `stack/scripts/run-eval-pair.sh` runs the seeds as a `devbox serve` service.

KTransformers expert placement from a routing histogram (the server ran with `KT_ROUTING_DUMP=<prefix>`):

```bash
llm/engines/alt/kt-wrapper/.venv/bin/python stack/scripts/kt_placement_from_dump.py \
    <prefix>-rank0.pt llm/engines/alt/kt-wrapper/placements/dsv41-expert-placement-hot64.json <out.json>
```

## Docs

- [stack/README.md](stack/README.md): the serving stack in detail: layout, scripts, adding a model, upgrades and
  rollback, tuning, troubleshooting.
- [docs/token-speed.md](docs/token-speed.md): what decode and prefill speed each model and engine reaches on this
  host, and why.
- Study reports, copied from `LLM_ROOT/results`:
  [pair programming vs solo and review](docs/pair-eval-report.md),
  [DeepSeek token-generation study](docs/deepseek-tg-study-2026-11-13.md),
  [two-model setup](docs/two-model-2026-11-13.md),
  [speed comparison of models and engines](docs/speed-comparison-2026-11-21.md).
- `stack/config/opencode-plan.md`, `stack/config/opencode-review.md`: the plan and review prompts OpenCode gets.
