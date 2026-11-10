# llm stack

Scripts and config to build llama.cpp, fetch pinned GGUF weights, tune, serve them with systemd and
point OpenCode at them. Everything model-specific lives in `config/models/<model-id>.env`.

```
/srv/llm/
├── stack/              this repo
├── engines/            llama.cpp-<tag>/ builds, llama.cpp-current / -previous symlinks, .src/ git mirror
├── models/<id>/        <revision>/ weights, current / previous symlinks, .meta-<revision>.json
├── secrets/<id>.key    API keys (mode 600, owner llm)
├── results/<id>/       benchmark reports (<date>.md) and raw server logs
├── logs/               one log per script run
├── state/              install fingerprints
└── venv/               pinned huggingface_hub (hf CLI)
```

## Quick start

```bash
# one-time, as root (installs apt packages, creates user llm and the layout, clones the repo, venv)
sudo ./scripts/05-bootstrap-host.sh --source /path/to/this/repo --allow-drop-caches

cd /srv/llm/stack
sudo -u llm make check M=deepseek-v4.1-flash-1017     # pre-flight
sudo -u llm make build                                 # engine pinned in versions.lock (or REF=b12xxx)
sudo -u llm make download M=deepseek-v4.1-flash-1017   # ~345 GB, resumable, sha256-verified
sudo -u llm make bench M=deepseek-v4.1-flash-1017      # 1-3 h; writes tuned values into the .env
sudo make install M=deepseek-v4.1-flash-1017           # systemd + full health check
make client M=deepseek-v4.1-flash-1017                 # as the OpenCode user
export LOCAL_DEEPSEEK_KEY="$(sudo cat /srv/llm/secrets/deepseek-v4.1-flash-1017.key)"
opencode run -m local-deepseek-v4.1-flash-1017/deepseek-v4.1-flash "Summarise README.md"
```

Every script has `--help` and `--dry-run` (`make <target> DRY=1`), logs to `/srv/llm/logs/`, and is
safe to re-run: finished work is detected and skipped (verified files, existing builds, an unchanged
and healthy service).

| Script | Runs as | Does |
|---|---|---|
| `00-check-host.sh [id]` | anyone | tools, driver, nvcc, GPU count and sm, NUMA, RAM, layout, disk, port |
| `05-bootstrap-host.sh` | root | apt packages, user, layout, venv, optional drop-caches helper |
| `10-build-engine.sh --ref` | llm | CUDA build into `engines/llama.cpp-<tag>`, smoke test, switch `-current` |
| `20-download-model.sh <id>` | llm | `hf download --revision`, space check, retries, sha256, `versions.lock` |
| `30-benchmark.sh <id>` | llm | fit search, NUMA modes, speculative decoding; updates the `.env` |
| `40-install-service.sh <id>` | root | unit file, API key, enable/restart, health check |
| `50-healthcheck.sh <id>` | llm/root | `/v1/models`, chat, tool calls, ~100K-token needle |
| `60-client-config.sh <id>` | client user | merge provider into `opencode.json` |
| `90-rollback.sh <id\|engine>` | root | swap current/previous, restore config, restart, health check |
| `llm-serve.sh <id>` | llm (systemd) | builds the `llama-server` command line and `exec`s it |

The scripts commit their own changes (`versions.lock`, tuned `.env` values) to this repo.

## Adding a model

1. Copy an existing file to `config/models/<new-id>.env` and edit it. Pin `HF_REVISION` to a full commit sha
   (`scripts/20-download-model.sh --latest <new-id>` prints the newest one). `HF_INCLUDE`/`EXTRA_FILES` are
   `hf --include` style globs; `MAIN_GGUF` is the first shard. Leave `N_CPU_MOE=999` and `TENSOR_SPLIT=`
   empty for a MoE model, or set `N_CPU_MOE=0` for a dense one that fits in VRAM. Use a free `PORT`.
2. `make download M=<new-id>`, `make bench M=<new-id>`, `sudo make install M=<new-id>`, `make client M=<new-id>`.

No script changes are needed. Any key from `global.env` (for example `TUNE_NUMA_MODES`, `VRAM_MARGIN_MIB`,
`HEALTH_LONG_CTX_TOKENS`) can be overridden in the model file. Config files are read by both bash and
systemd, so values may not contain `$`, backticks or backslashes; `lib.sh` rejects anything else.

Several models can run at the same time only if their `TENSOR_SPLIT`/`N_CPU_MOE` leave room for each other;
the benchmark tunes each model for the whole machine.

## Upgrading and rolling back

Engine:
```bash
sudo -u llm make build REF=b12xxx      # builds, smoke-tests, switches -current, pins it in versions.lock
sudo systemctl restart llm@<id> && make health M=<id>
sudo make rollback E=1                 # back to engines/llama.cpp-previous, restarts active services
```
Old builds stay in `engines/` until you delete them.

Model (new upload or revision):
```bash
scripts/20-download-model.sh --latest <id>   # new sha
# edit HF_REVISION in config/models/<id>.env, commit
sudo -u llm make download M=<id>             # new revision dir; current -> new, previous -> old
sudo -u llm make bench M=<id>                # if the quant changed
sudo make install M=<id>
sudo make rollback M=<id>                    # swaps back and restores the .env pinned to the old revision
```
Old revisions stay in `models/<id>/` (delete them yourself when you no longer need a rollback).

Switching quant (for example to the UD-IQ2_XXS fallback): change `HF_INCLUDE` and `MAIN_GGUF`, keep or
change `HF_REVISION`, then download, bench, install. Files of the same revision are kept side by side.

## Tuning (30-benchmark.sh)

1. **fit**: starts `llama-server` with `-ngl 999 --n-cpu-moe N` at the real `CTX`, sends a 4096-token prompt
   and reads free VRAM per GPU. It binary-searches the smallest `N` that leaves `VRAM_MARGIN_MIB` free on every
   GPU. The first `TENSOR_SPLIT` weights each GPU by `(total - margin) x factor`, with `GPU_SHARE_FACTORS`
   (`3090=0.85` gives the 3090 Ti a smaller share). It is then nudged toward GPUs with slack for up to
   `TUNE_REBALANCE_ROUNDS` more layers.
2. **numa**: for each `TUNE_NUMA_MODES` entry, measures pp4096, pp32768 and tg512 (`BENCH_REPS` times).
   Modes: `distribute` (llama.cpp `--numa distribute`), `interleave` (`numactl --interleave=all`),
   `node<list>` (`numactl --cpunodebind=<list> --localalloc`, for example `node0-3` = socket 0).
   Threads = physical cores of the selected nodes. With `--allow-drop-caches` from bootstrap, the page
   cache is dropped before each mode. Without it, NUMA results are biased by where the first run put the pages.
3. **spec**: adds the DSpark drafter (`SPEC_DRAFT_GGUF`, `SPEC_ARGS`), re-fits for its VRAM and measures again.

Winner = highest `sqrt(pp32768 x tg512)`. It is written to the `.env` and committed. The report goes to
`/srv/llm/results/<id>/<date>.md`. Use `PHASES=numa,spec` to skip the fit search.

Note on this host: each EPYC 7601 has 4 dies, so Linux shows **8 NUMA nodes** (8 cores, ~64 GB each),
not 2. A single node cannot hold the model, so the per-socket mode is `node0-3` / `node4-7`.

## Troubleshooting

- `journalctl -u llm@<id> -f`: server output. `make serve M=<id> DRY=1` prints the exact command line.
- Script logs: `/srv/llm/logs/<script>-<id>-<date>.log`. Benchmark server logs: `/srv/llm/results/<id>/work-*/`.
- Won't load, `invalid ggml type` or `array key not found`: engine too old for the GGUF, or a broken upload.
  Check `MIN_ENGINE_REF`, build a newer tag, check the HF repo history and pin a fixed revision.
- `invalid split file idx`: an Engram file was swapped in without `engram/set_split.py` (see the HF repo's
  `engram/README.md`).
- CUDA OOM at start or under load: raise `N_CPU_MOE` or `VRAM_MARGIN_MIB` and re-run `make bench PHASES=fit`.
  Lowering `-ub`/`-b` in `EXTRA_ARGS` also shrinks compute buffers.
- Garbled output after a few turns (same prefix reused): llama.cpp#30944, prompt-cache restore with the
  Engram. The DeepSeek config uses `--cache-ram 0` as the workaround. Remove it once the issue is fixed.
- Broken tool calls: run `make health M=<id>` to see the raw reply. Check that `--jinja` is set and that the
  engine has the model's chat-template support. Then try a newer engine or the fallback quant.
- `hf download` stalls or fails: just re-run `make download`. Files that fail sha256 are moved to
  `models/<id>/<rev>/.corrupt/` and downloaded again on the next run.
- Port in use: `ss -ltnp 'sport = :<port>'`.
- The NVIDIA driver and the CUDA toolkit are not managed here. `00-check-host.sh` only reports on them.

## Known upstream state (2026-11-10)

- DeepSeek-V4.1-Flash support: llama.cpp PR #31086, merged as tag b11870. PR #30817 was closed unmerged; do not use it.
- unsloth GGUFs were re-uploaded on 2026-11-02 after #31385 (FP8 Engram type / gibberish). Revision
  `2688c0c3c2c3` is pinned.
- `UD-Q2_K_XL` is 335 GB: 200 GB backbone in shards 1-6, plus the 135 GB Q5_K Engram table as shard 7.
  Lighter Engram tables (IQ4_NL 111 GB) can be swapped in per the repo's `engram/README.md`.
- Fallbacks: `UD-IQ2_XXS` (301 GB incl. Engram) or `ISTA-DASLab/DeepSeek-V4.1-Flash-1017-GSQ-RCO-GGUF`
  (needs its revision from 2026-10-28 or later, see #31263).
- OpenCode now uses `providers` (the old `provider` key is deprecated) and the package
  `@opencode/ai/providers/openai-compatible`. `60-client-config.sh` writes that format.
