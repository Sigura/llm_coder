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

The bench picks `--n-cpu-moe` and the split only. The serving DeepSeek config was tuned by hand past it (expert
placement, threads, MoE cache), see the next section.

## Token speed: what we applied, rejected and could not use

Host: 2× EPYC 7601 (Zen1, AVX2, 8 NUMA nodes), 503 GB RAM, one NVMe; GPUs 0,2,3 RTX 4090, GPU 1 RTX 3090 Ti.
Engine llama.cpp b12247 in the devbox container. Models and their serving setup:

| port | model | where | single-stream decode |
|---|---|---|---|
| 8080 | DeepSeek V4.1 Flash 1017, unsloth UD-Q2_K_XL | GPUs 0,1 + experts in host RAM, 2 slots × 128k | 16.3–17.4 tok/s |
| 8086 | Qwen3.8-27B dense, UD-Q6_K | GPU 2 | 35 tok/s |
| 8085 | Qwen3.6-35B-A3B + MTP heads, UD-Q4_K_XL | GPU 3 | 205–219 tok/s |

Unless noted, "tg" is decode speed and "pp" is prompt (prefill) speed, both in tok/s. Numbers measured on real coding
prompts through the server are worth more than llama-bench numbers, because llama-bench feeds random tokens.
Raw data lives in `LLM_ROOT/results/` (`tg-study-2026-11-13/`, `two-model-2026-11-13/report.md`, `moe-cache-2026-11-19/`).

### 1. Applied after measurement

#### DeepSeek

| change | before → after | where |
|---|---|---|
| NUMA-interleaved page-cache warm-up before the server starts | tg 2.9 (one `dd` stream) / 7.8–9.0 (llama.cpp mmap faults) → 9.3 on llama-bench; on the server 5.9 → 12.8–13.0 | `25-warm-cache.sh`, `WARM_CACHE=1` |
| Evict the other models' pages before warming | stops the thrash of 50–80 GB re-read per run | `25-warm-cache.sh` |
| `--numa distribute` | bench winner over the other modes | model env |
| Explicit expert placement per GPU (`-ot ...=CUDAk`) instead of `--n-cpu-moe` | 4 GPUs: tg 6.6 (no expert layers on GPU) → 11.75 (4,3,3,3) | Nov 13–19 layout, replaced by the MoE cache |
| DeepSeek on GPUs 0,1 only (GPUs 2,3 freed for the Qwen models) | server tg 8.2 (old 4-GPU config) → 11.2–12.2 | model env |
| 48 threads | 96 → 8.3, 80 → 8.8, 64 → 9.2, **48 → 9.6** | `THREADS=48` |
| `--poll 0` (no busy-wait between ops) | tg 12.9 → 13.5; less power per load step | model env |
| All routed experts in RAM + llama.cpp's MoE expert cache, `--moe-cache-mib 23936 --moe-cache-cpu-share 0.95` | tg 12.9 → 16.7–17.4 (5–8k prompts), 12.85 → 16.88 (44.5k prompt); in production 16.3 over 1867 tokens; pp unchanged (−5% on the long prompt) | PR #4 |
| `--parallel 2`, 128k context per slot | one session unchanged; two at once 7.1 each = +24% total throughput | PR #2 |
| `-b 4096 -ub 2048` | set in the first bench round (Nov 11); no clean before/after pair was recorded | model env |

Why these work: DeepSeek decode is bound by host memory bandwidth. The CPU expert matmuls read weights straight from
the mmapped page cache, and a page lives on the NUMA node that first read it. A fine 8-node interleave uses all
16 memory channels; one reader piles whole tensors onto one or two nodes. The MoE cache keeps the hottest experts
(68% decode hit rate) on the GPUs. Uploading a missing expert from mmapped RAM runs at only ~4 GiB/s, so most
misses (95%) are computed on the CPU instead.

#### Qwen models

| change | before → after | where |
|---|---|---|
| Qwen3.6 MTP speculative decoding, `--spec-type draft-mtp --spec-draft-n-max 2` | tg 154 → 205–215 (+39%), 91% draft acceptance, eval within noise | `qwen3.6-35b-a3b-mtp.env` |
| Thinking off (Qwen3.6 small_model, Qwen3.8 coder) | Qwen3.6 with thinking was 12× slower and scored worse (2/17 vs 4/17) | `--reasoning-budget 0` / no-think prompts |
| Each Qwen model alone on one 4090, 8 CPU threads | no CPU contention with DeepSeek; DeepSeek loses nothing when both generate, Qwen3.6 −12% | model envs |

### 2. Rejected by measurement

| tried | result | reason |
|---|---|---|
| GSQ-RCO IQ2_XXS DeepSeek (smaller file) | tg 2.4–2.5 on 2 GPUs vs ~12 for unsloth | its IQ1_M/IQ2_XXS expert dot products are CPU-compute-bound on Zen1 AVX2: scales linearly with threads, ~7× slower per thread. Deleted. |
| DSpark draft model for DeepSeek | 4 GPUs: +0.2 (7.1 → 7.3); 2 GPUs: 11.2–12.2 → 9.1–10.1 (45% acceptance); GSQ: 4.3 → 2.5 | verifying draft tokens multiplies the CPU expert work, and the drafter takes VRAM from expert layers |
| `--n-cpu-moe` with an auto tensor split | 3 expert layers on GPU, dense layers spread oddly | explicit `-ot` per GPU was faster (see above) |
| 64–96 threads | slower than 48 | memory saturates at ~32 threads; more only add contention (and preceded the host hangs) |
| `--load-mode none` | tg 7.1 → 4.9 | weights land in pinned memory on one or two NUMA nodes |
| smaller context (8k vs 131k) | no tg change | KV is tiny (~1.7 GB for 2×128k); nothing to gain by moving context either |
| two DeepSeek servers instead of 2 slots | +8% total over 2 slots | costs GPUs 2,3 and twice the VRAM; decode bandwidth is shared anyway |
| one CPU socket per server (`numactl --cpunodebind`) | single stream 11.5 → 9.7–10.9 | halves the memory channels per stream |
| MoE cache CPU share 0.9 / 0.98 / 1 | 15.5 / 16.0–17.1 / 12.7 vs 16.7–17.4 at 0.95 | 1 = all misses uploaded at ~4 GiB/s; lower shares push too much to the CPU |
| old `-ot` layout + MoE cache in the leftover ~3.5 GiB VRAM | peaks at 13.0–13.2 | cache too small; all experts in RAM frees the VRAM for a 23.9 GiB cache |
| `moe-cache-tune.py` predictions (19–20 tok/s at share 0.98) | not reproduced | its time model fitted a negative constant on this host; measured directly instead |
| MoE cache for two concurrent sessions | +0–4% | hit rate drops to 62% because two streams use more distinct experts |
| 4 GPUs for DeepSeek | 8.2 vs 11.2–12.2 on 2 | the 4-GPU config (64 threads, busy-wait, `--n-cpu-moe`) lost to 2 GPUs with `-ot` placement; the cause per factor was not separated. 2 GPUs also leave 2,3 for the Qwen models |

### 3. Not usable in this environment (nice to have)

| idea | expected gain | why not here |
|---|---|---|
| `mlock` / `--load-mode mmap+mlock` (pin expert pages) | stops page-cache eviction: no NVMe reads during prefill, no 5–8 tok/s drops while other jobs write files | container memlock ulimit 8 MB, no `CAP_IPC_LOCK`; needs devbox flags for the serve container |
| NUMA policies `numactl --membind/--localalloc`, `--numa isolate/numactl` | node-local experts per thread group | seccomp blocks `set_mempolicy` (no `CAP_SYS_NICE`); only `distribute` works |
| Drop caches between benches | clean, unbiased NUMA placement per run | `05-bootstrap-host.sh --allow-drop-caches` not set up; we evict per file with fadvise instead |
| DeepSeek fully on GPUs | GPU-speed decode and prefill | 185.9 GiB without Engram vs 4×24 GB of VRAM |
| MTP with `--parallel > 1` on Qwen3.6 | two sessions on the small model | not supported with MTP yet; we run 1 slot |
| Full GPU power (4090 450 W, 3090 Ti 480 W) | DeepSeek tg 11.5 → 12.8 (Nov 15 vs Nov 16 numbers); faster prefill on GPU 1 (power-capped at 600–900 MHz) | caps (4090 193–232 W, 3090 Ti 201 W) set after two abrupt host resets on Nov 15; cause not found |
| SGLang + KTransformers for DeepSeek | prefill ~1700 tok/s claimed (we get 62–78 on real prompts) | needs two 4090s, and GPUs 2,3 run the Qwen models; not tried, claim not verified here |
| Xolotl / Strata fork on GPU 3 | faster prefill/decode (claimed) | GPU 3 serves the Qwen3.6 MTP small_model; not tried |
| Builds on the host | — | host has CUDA 11.8 and a too-new gcc; everything builds in the container |

### 4. Other findings

- **Prefill is the bottleneck for agent sessions, not decode.** Prefill copies the CPU experts to the GPU once per
  2048-token ubatch from the main thread (op-offload). An OpenCode "ping" is ~14.5k prompt tokens. Real prompts get
  62–78 tok/s (llama-bench 131–146). The MoE cache does not change prefill.
- **Page-cache eviction by other work is the biggest slowdown.** With RAM full of other files' page cache
  (~200 GiB outside `/home/sigura`), the experts were evicted even right after warm-up (61.9% cached 3 s later). One
  OpenCode ping then took 41 min (prefill 5.99 tok/s). Big file jobs (quantize, KLD sweeps) did the same: tg 5.8,
  ~18k major faults/s. After such jobs: fadvise-drop their files, then `25-warm-cache.sh`.
- The kernel keeps the last-used model on the active LRU list and evicts the new model's pages first, so warm-up
  evicts the other models first.
- Warm-up hung after a reboot: the NVMe idled at 56 °C and never got below the 55 °C resume threshold. Now the pause
  also ends once the temperature stops falling for 120 s.
- IQ quants are ~5× slower than K-quants when the experts sit in CPU RAM on Zen1; on a GPU they are fine.
- `--cache-ram 0` (see Troubleshooting) means there is no host-RAM prompt cache across requests.
- Loading DeepSeek takes ~5 min plus warm-up, so all models unload only after 10 h idle (the global default is 10 min).
- The replaced GPU 1 (3090 Ti) costs DeepSeek nothing in decode; prefill is within ~3% of two 4090s.
- The DeepSeek log at the 2026-11-19 restart warns that `/proc/sys/kernel/numa_balancing` is enabled again (it was
  set to 0 on Nov 16; a host reboot probably reset it). Its effect on speed has not been measured.
- Host stability limits load tests: four hard hangs on Nov 13 came 10–15 s after llama.cpp started computing with
  64–96 busy-polling threads, and two resets on Nov 15. Best guess is a power-delivery transient, unconfirmed.
  `--poll 0` and 48 threads lower the load step. Keep `telemetry.sh` running during heavy runs.

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
- OpenCode: the stable release (1.19.5) reads `provider` + `npm: "@ai-sdk/openai-compatible"`, which is what
  `60-client-config.sh` writes. It silently ignores the `providers` format described on opencode.ai/docs
  (dev branch). Check this again when OpenCode 2.x ships.
