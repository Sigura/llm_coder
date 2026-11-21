# Token speed: what we applied, rejected and could not use

Host: 2× EPYC 7601 (Zen1, AVX2, 8 NUMA nodes), 503 GB RAM, one NVMe; GPUs 0,2,3 RTX 4090, GPU 1 RTX 3090 Ti.
Engine llama.cpp b12247 in the devbox container. Each EPYC 7601 has 4 dies, so Linux shows 8 NUMA nodes (8 cores,
~64 GB each), not 2; a single node cannot hold DeepSeek. `30-benchmark.sh` (see `stack/README.md`, "Tuning") picks
`--n-cpu-moe` and the GPU split only; everything below was measured and tuned by hand past it.
Models and their serving setup:

| port | model | where | single-stream decode |
|---|---|---|---|
| 8080 | DeepSeek V4.1 Flash 1017, unsloth UD-Q2_K_XL | GPUs 0,1 + experts in host RAM, 2 slots × 128k | 14.1–14.5 tok/s (prefill 100–126), since the Nov 20 power changes |
| 8086 | Qwen3.8-27B dense, UD-Q6_K | GPU 2 | 35 tok/s |
| 8085 | Qwen3.6-35B-A3B + MTP heads, UD-Q4_K_XL | GPU 3 | 205–219 tok/s |

Unless noted, "tg" is decode speed and "pp" is prompt (prefill) speed, both in tok/s. Numbers measured on real coding
prompts through the server are worth more than llama-bench numbers, because llama-bench feeds random tokens.
Raw data lives in `LLM_ROOT/results/` (`tg-study-2026-11-13/`, `two-model-2026-11-13/report.md`, `moe-cache-2026-11-19/`, `ubatch-2026-11-19/`,
`remeasure-2026-11-20/`, `kt-2026-11-20/`, `kt-review-2026-11-21/`).

## 1. Applied after measurement

### DeepSeek

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
| `-b 4096 -ub 2048` | set in the first bench round (Nov 11); no clean before/after pair was recorded | replaced by `-ub 4096` |
| `-ub 4096` with the MoE cache cut to 17920 MiB (16896 since Nov 20, section 4) | pp 69.2 → 99.8 (8k prompt), 78.6 → 122.1 (44.5k); tg 16.3 → 14.5–14.8. A 14.5k-token OpenCode turn with 1k output: ~257 s → ~195 s | model env |

Why these work: DeepSeek decode is bound by host memory bandwidth. The CPU expert matmuls read weights straight from
the mmapped page cache, and a page lives on the NUMA node that first read it. A fine 8-node interleave uses all
16 memory channels; one reader piles whole tensors onto one or two nodes. The MoE cache keeps the hottest experts
(68% decode hit rate) on the GPUs. Uploading a missing expert from mmapped RAM runs at only ~4 GiB/s, so most
misses (95%) are computed on the CPU instead.

### Qwen models

| change | before → after | where |
|---|---|---|
| Qwen3.6 MTP speculative decoding, `--spec-type draft-mtp --spec-draft-n-max 2` | tg 154 → 205–215 (+39%), 91% draft acceptance, eval within noise | `qwen3.6-35b-a3b-mtp.env` |
| Thinking off (Qwen3.6 small_model, Qwen3.8 coder) | Qwen3.6 with thinking was 12× slower and scored worse (2/17 vs 4/17) | `--reasoning-budget 0` / no-think prompts |
| Each Qwen model alone on one 4090, 8 CPU threads | no CPU contention with DeepSeek; DeepSeek loses nothing when both generate, Qwen3.6 −12% | model envs |

## 2. Rejected by measurement

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
| `-ub 3072` (cache 17920) | pp 65.6 / 75.6, tg 13.8 / 14.6 | under `-b 4096` each batch still splits into two ubatches, so the expert uploads per prompt do not drop |
| `-ub 4096` with cache 12800 instead of 17920 | pp 109.6 / 129.7, tg 14.5 / 14.0 vs 99.8 / 122.1, 14.5 / 14.8 | within noise; the larger cache is kept |
| `-b 6144 -ub 6144` (cache 6144) | pp 110.7 / 160.3, tg 11.9 / 11.9 | faster only on very long prompts; the same ~195 s on a 14.5k turn and slower on every decode-heavy turn |
| `-b 8192 -ub 8192` | does not start | 20.5 GiB compute buffer on CUDA1 (CUDA1 holds the output layer, its buffer grows faster than CUDA0's: 10.2 vs 6.5 GiB at 4096) |
| `kernel.numa_balancing=0` (host sysctl, Nov 19) | pp 78.6 vs 74.0, tg 16.3 vs 16.9 on the 44.5k prompt (downloads running) | no measurable effect; kept off as llama.cpp recommends (`/etc/sysctl.d/90-numa-balancing.conf`) |
| MoE cache CPU share 0.9 / 0.98 / 1 | 15.5 / 16.0–17.1 / 12.7 vs 16.7–17.4 at 0.95 | 1 = all misses uploaded at ~4 GiB/s; lower shares push too much to the CPU |
| old `-ot` layout + MoE cache in the leftover ~3.5 GiB VRAM | peaks at 13.0–13.2 | cache too small; all experts in RAM frees the VRAM for a 23.9 GiB cache |
| Xolotl (Strata fork, `ds41_generate`) with our UD-Q2_K_XL, one 4090, 190 GiB RAM arena, Engram from the FP8 shards 47–48 | exact routing: pp 157.6 / 245.2, tg 4.0 / 3.4; its default route bias 1.0 / file penalty 0.6 (lossy): pp 156.9 / 244.8, tg 7.3 / 4.1; llama.cpp on the same day 99.9 / 126.2, 14.1 / 14.5 (8k / 44.5k prompts) | prefill 1.6–1.9× faster, decode 2–4× slower; decode dominates coding sessions. Its docs' 15.8 tg with this GGUF came from another machine. No quality run at this speed. Unsloth's Q5_K Engram tables are not readable by it, hence the FP8 shards |
| `moe-cache-tune.py` predictions (19–20 tok/s at share 0.98) | not reproduced | its time model fitted a negative constant on this host; measured directly instead |
| MoE cache for two concurrent sessions | +0–4% | hit rate drops to 62% because two streams use more distinct experts |
| 4 GPUs for DeepSeek | 8.2 vs 11.2–12.2 on 2 | the 4-GPU config (64 threads, busy-wait, `--n-cpu-moe`) lost to 2 GPUs with `-ot` placement; the cause per factor was not separated. 2 GPUs also leave 2,3 for the Qwen models |

## 3. Not usable in this environment (nice to have)

| idea | expected gain | why not here |
|---|---|---|
| `mlock` / `--load-mode mmap+mlock` (pin expert pages) | stops page-cache eviction: no NVMe reads during prefill, no 5–8 tok/s drops while other jobs write files | container memlock ulimit 8 MB, no `CAP_IPC_LOCK`; needs devbox flags for the serve container |
| NUMA policies `numactl --membind/--localalloc`, `--numa isolate/numactl` | node-local experts per thread group | seccomp blocks `set_mempolicy` (no `CAP_SYS_NICE`); only `distribute` works |
| Drop caches between benches | clean, unbiased NUMA placement per run | `05-bootstrap-host.sh --allow-drop-caches` not set up; we evict per file with fadvise instead |
| DeepSeek fully on GPUs | GPU-speed decode and prefill | 185.9 GiB without Engram vs 4×24 GB of VRAM |
| MTP with `--parallel > 1` on Qwen3.6 | two sessions on the small model | not supported with MTP yet; we run 1 slot |
| Full GPU power (4090 450 W, 3090 Ti 480 W) | DeepSeek tg 11.5 → 12.8 (Nov 15 vs Nov 16 numbers); faster prefill on GPU 1 (power-capped at 600–900 MHz) | caps (4090 193–232 W, 3090 Ti 201 W) set after two abrupt host resets on Nov 15; cause not found |
| SGLang + KTransformers for DeepSeek (FP8 checkpoint, experts MXFP4 on the CPU, Nov 20–21; `kt-2026-11-20/`, `kt-review-2026-11-21/`) | 8k / 44.5k prompts, tok/s: one 4090, 64 threads: pp 259 / 560, tg 13.8 / 13.8; two 4090s, 48 threads: pp 387 / 734, tg 13.1 / 13.0; two 4090s, 64 threads (its default): pp 396 / 746, tg 10.4 / 10.7; llama.cpp 99.9 / 126.2, 14.1 / 14.5. Two running requests on one 4090 with the prefill chunk capped at 16,384 (`tmp_kt_two.sh`): a lone request pp 268 / 442, tg 13.6 / 13.5; both at once pp 132 / 362, tg 5.1 / 7.3 each (the 8k one decodes while the 44.5k one prefills), ~14.7 together once both decode; two 4090s, 48 threads: lone pp 387 / 779, tg 12.3 / 12.4, both at once pp 169 / 652, tg 5.8 / 6.6, ~13.2 together. Evalpair seed 1 (navigator on KT, one 4090, 48 threads): pass@1 13, pass@2 20, tests@2 24.7 of 29 in 7819 s vs llama.cpp 14 / 21 / 25.1 in 7598 s. Tool calls 4 of 4 ([the wrapper's](https://github.com/donbcd/deepseek-v4.1-flash-1017-ktransformers) check; namespaced tools are its known gap). Evicting the checkpoint's page cache costs nothing (experts live in KT's own memory) | not switched yet, decision open; serve config ready: `stack/config/models/deepseek-v4.1-flash-1017-fp8.env` (`ENGINE=kt`, port 8080, same alias and key, GPU 0, 64 threads, 2 running requests in a 128k-token pool, chunk 16,384; `50-healthcheck.sh` passes). It takes ~400 GiB of RAM for good and replaces llama.cpp DeepSeek; it does not run on the 3090 Ti; on one 4090 a second running request runs out of VRAM on the 44.5k prompt with the default 36,864-token chunks, hence the 16,384 cap (44.5k prefill 560 → 442); the prefix cache reuses whole prefill chunks only (36,864 tokens: a repeated 44.5k prompt prefills at 7151 tok/s, a repeated 8k one gets nothing); fewer threads help only with two GPUs (one GPU, 48 threads: tg 12.8–13.0); a launch takes ~25 min, the first request after it is slower, the very first launch compiles Triton kernels for 10 min; its CPU expert memory spreads over all 8 NUMA nodes (77–101 GB each, `numastat-kt-stack-serve.txt`); explicit binding vs first touch was not separated |
| Builds on the host | — | host has CUDA 11.8 and a too-new gcc; everything builds in the container |

## 4. Other findings

- **Prefill is the bottleneck for agent sessions, not decode.** Prefill copies the CPU experts to the GPU once per
  ubatch from the main thread (op-offload). An OpenCode "ping" is ~14.5k prompt tokens. Real prompts got 62–78 tok/s
  at `-ub 2048` (llama-bench 131–146), 100–130 at `-ub 4096`. The MoE cache does not change prefill; the ubatch size
  is capped by the compute buffer on CUDA1.
- **Page-cache eviction by other work is the biggest slowdown.** With RAM full of other files' page cache
  (~200 GiB outside `/home/sigura`), the experts were evicted even right after warm-up (61.9% cached 3 s later). One
  OpenCode ping then took 41 min (prefill 5.99 tok/s). Big file jobs (quantize, KLD sweeps) did the same: tg 5.8,
  ~18k major faults/s. After such jobs: fadvise-drop their files, then `25-warm-cache.sh`.
- The kernel keeps the last-used model on the active LRU list and evicts the new model's pages first, so warm-up
  evicts the other models first.
- Warm-up hung after a reboot: the NVMe idled at 56 °C and never got below the 55 °C resume threshold. Now the pause
  also ends once the temperature stops falling for 120 s.
- IQ quants are ~5× slower than K-quants when the experts sit in CPU RAM on Zen1; on a GPU they are fine.
- `--cache-ram 0` stays on DeepSeek as a workaround for cached-prefix output corruption (llama.cpp#30944, open; see
  `stack/README.md`, "Troubleshooting"). So there is no host-RAM prompt cache across requests.
- Loading DeepSeek takes ~5 min plus warm-up, so all models unload only after 10 h idle (the global default is 10 min).
- The replaced GPU 1 (3090 Ti) costs DeepSeek nothing in decode; prefill is within ~3% of two 4090s.
- `numa_balancing` came back on after a host reboot (set to 0 on Nov 16 by hand). Since Nov 19 it is 0 in
  `/etc/sysctl.d/90-numa-balancing.conf`; turning it off measured no difference (section 2).
- Host stability limits load tests: four hard hangs on Nov 13 came 10–15 s after llama.cpp started computing with
  64–96 busy-polling threads, two on Nov 15, one on Nov 18 and four on Nov 20, all with DeepSeek serving. The kernel
  journal and the BMC log show nothing at the freeze (no MCE, no lockup; only correctable ECC on DIMMF1/DIMMH1 on
  Nov 15). Telemetry caught the Nov 20 08:49 one 14 s after an idle → 26% CPU load step (DeepSeek decode starting),
  temperatures and power normal. Since `processor.max_cstate=1` (Zen 1 C2 off, Nov 20) evalpair ran 5 h without a
  hang. Keep `telemetry.sh` running during heavy runs.
- The Nov 20 power changes (C2 off, GPU undervolting changed) cost llama.cpp DeepSeek 6–21%: no cache pp 66.6 / 71.4,
  tg 11.9 / 12.0 (Nov 19: 76.9 / 78.3, 12.9 / 12.9); cache 23936 at `-ub 2048` pp 60.6 / 71.1, tg 14.2 / 15.2 (76.7 /
  78.6, 17.4 / 16.3); 8k / 44.5k prompts. The two changes were not separated.
- `-ub 4096` with cache 17920 runs out of CUDA memory on GPU 1 mid-request once another container holds ~350 MB there
  (twice on Nov 20). Cache 16896: pp 99.9 / 126.2, tg 14.1 / 14.5, the same as 17920 measured on Nov 19 within ~3%.
