# DeepSeek V4.1 Flash 1017: warm token-generation study (2026-11-13)

Copy of `LLM_ROOT/results/tg-study-2026-11-13/report.md` as of 2026-11-22; the live file there may be newer.

Host: 2× EPYC 7601 (Zen1, AVX2, 8 NUMA nodes, 503 GB), 3× RTX 4090 + RTX 3090 Ti, root and models on one NVMe
(XPG S70 Blade). Engine llama.cpp b12247. All numbers are **warm**: model fully in the page cache, ~0 disk reads
during generation (the disk column shows it where it was not 0).

## Result

**Serve unsloth UD-Q2_K_XL on GPUs 0,1 only, no DSpark, 48 threads, `--poll 0`:**
routed experts of layers 18,19 on CUDA0 and 38,39 on CUDA1, all others on CPU.

| | old 8080 config | new 8080 config |
|---|---|---|
| GPUs | 4 | 2 (GPUs 2,3 free) |
| server tg, real code prompt | 8.2 (10.7 with DSpark) | **11.2–12.2** |
| server pp, 56k-token prompt | 165–172 | 155 |
| threads / poll | 64 / busy-wait | 48 / `--poll 0` |

Applied in `stack/config/models/deepseek-v4.1-flash-1017.env` (commit f0de20a). Healthcheck passes: models,
chat, tool calls, long context (96,558-token prompt, needle found, 842 s, 115 tok/s prefill). The OpenCode
end-to-end test passes (262 s, correct answer, no files changed).

**GSQ-RCO IQ2_XXS is not competitive:** best warm tg 2.4–2.5 tok/s on 2 GPUs (4.2–4.3 on 4 GPUs), about 5× slower.
Its smaller backbone does not help because its expert matmuls are CPU-compute-bound (see below).

## The three things that mattered

### 1. Where the page cache puts the weights (NUMA)
The CPU expert matmuls read weights straight from the page cache (mmap). A page lives on the NUMA node of the CPU
that first read it. Same config, same warm cache, different warm-up:

| how the model got into the page cache | unsloth tg (llama-bench, ncmoe 37, 4 GPUs) |
|---|---|
| one sequential `dd` stream | 2.9 |
| 8 node-pinned readers, 256 MiB pieces | 5.1 |
| 8 node-pinned readers, every 8th 256 KiB piece | **9.3** |
| llama.cpp's own mmap faulting (64 threads, random 4K reads) | 7.8–9.0 |

One stream piles whole tensors onto one or two nodes, so all threads share 2 memory channels instead of 16.
`stack/scripts/25-warm-cache.sh` does the last variant: fine interleave, one sequential disk region, pause when the
NVMe is hot. It also evicts the other model first: the kernel keeps the last-used model's pages on the active LRU
list and evicts the new model's pages first, which made earlier runs thrash (50–80 GB re-read per run).

### 2. Expert placement per GPU (`-ot`) instead of `--n-cpu-moe`
`--n-cpu-moe 37` leaves only 3 expert layers on GPU and lets the tensor split spread dense layers oddly. Explicit
`-ot blk[.]N[.]ffn_(up|gate|down)_exps=CUDAk` per GPU, on the last layers of the GPU's own dense range:

| unsloth, expert layers on GPU | llama-bench tg | VRAM weights |
|---|---|---|
| 4 GPUs: none | 6.6 | 1.6–2.1 GB each |
| 4 GPUs: 3,3,3,3 | 10.1 | 13.7–17.1 GB |
| 4 GPUs: 4,3,3,3 | 11.75 | 16.3–17.2 GB |
| 2 GPUs: 2,2 | 8.0* | 13.8 / 13.0 GB |
| 2 GPUs: 3,3 | 9.7* / 11.9–13.5 (`--poll 0`) | 18.7 / 17.9 GB |

\* measured while another job was evicting the cache (1–7 GB disk reads).
The server needs ~5 GB compute buffer per GPU at 131k context, so 3,3 does not fit there; 2,2 does.

### 3. Threads and polling
unsloth, 2 GPUs 3,3, warm: 96 → 8.3, 80 → 8.8, 64 → 9.2, **48 → 9.6** tok/s (`--poll 50`); `--poll 0` at 48 threads:
12.9 → **13.5** in a clean run. The CPU expert path of unsloth saturates memory at ~32 threads; more threads only
add contention, and busy-polling threads add power without work.

## Why GSQ is slower despite a smaller backbone

GSQ experts are IQ1_M (60 tensors), IQ2_XXS (42) and IQ2_XS (18); unsloth's are IQ3_XXS (50), IQ2_XXS (29),
IQ2_S (20), IQ3_S (10), IQ2_XS (4), MXFP4 (7). Neither uses Q2_K. All experts on CPU, warm:

| threads | 8 | 16 | 32 | 48 | 64 |
|---|---|---|---|---|---|
| unsloth tg | 4.27 | 5.84 | 6.58 | 6.61 | 6.85 |
| GSQ tg | 0.58 | 1.05 | 1.60 | 2.07 | 2.34 |

unsloth saturates at 32 threads (memory-bound); GSQ scales almost linearly (compute-bound) and per thread is ~7×
slower while reading ~⅓ fewer bytes per token. So the theory holds: the IQ1_M/IQ2_XXS dot products (codebook
lookups and sign tables on AVX2) are the bottleneck on Zen1, not memory. Not measured per kernel; inferred from
the scaling. GSQ's higher pp is the other side of the same coin: pp streams experts to the GPU, so fewer bytes win.

Other GSQ results: DSpark makes it slower (2.5 vs 4.3 tok/s, 48% acceptance; verifying 4 draft tokens multiplies
the CPU work). 5,5,5,5 on 4 GPUs fits for tg but OOMs on a long prompt.

## What did not help

| change | effect (unsloth unless noted) |
|---|---|
| `--load-mode none` | 7.1 → 4.9 (weights land in pinned memory on one or two nodes) |
| mlock | untestable: container memlock limit 8 MB |
| DSpark on 4 GPUs | +0.2 (7.1 → 7.3) at the cost of 2 expert layers of VRAM |
| DSpark on 2 GPUs | 11.2–12.2 → 9.1–10.1 (45% acceptance) |
| smaller context (8k vs 131k) | no change in tg |
| 80–96 threads | slower than 48 |

## Host hangs during the study (separate issue, open)

Four hard hangs (11:05, ~12:10, 15:25, ~18:16): no kernel log, no pstore, reset needed. Telemetry
(`stack/scripts/telemetry.sh`, fsync every second) caught the last two:

| | 15:25 | 18:16 |
|---|---|---|
| last bench line | `set_n_threads = 64`, +13 s | `set_n_threads = 96`, +11 s |
| disk | idle | 1.3 GB/s writes (other job) |
| CPU temp / NVMe temp | – / 54 °C | 59 °C / 62 °C |
| GPU power total | 486 W | 379 W, another GPU ramping |
| free RAM | 66 GB | 5 GB |

EDAC memory errors 0. Not the NVMe, not temperature, not memory pressure. Every logged hang came ~10–15 s after
llama.cpp switched from loading to compute with 64–96 busy-polling threads while GPUs were active, and the same
step had passed minutes before. Best fit: a power-delivery transient (PSU or VRM). Unconfirmed. Needs the BMC event
log (`ipmitool sel elist`), PSU rating check, panic sysctls + netconsole. The new config (48 threads, `--poll 0`,
2 GPUs) lowers the load step.

## Caveats

- llama-bench feeds random tokens; server numbers on a real code prompt are the ones to trust for serving.
- Results before the first host restart (unsloth 4-GPU server 7.1/7.3) were with mmap-fault placement; after it,
  with the warm-up script. Physical GPU order: tests before 18:40 that said "CUDA0,CUDA1" ran on physical GPUs 0 and 2.
- Other jobs on the host (GPU and disk) disturbed some runs; the disk column shows where.
- Raw data: `results.md`, `all.log`, `*.jsonl`, `srv-*.log` and `telemetry.log` in this folder.

## Operating notes

- After a host restart: `stack/scripts/25-warm-cache.sh deepseek-v4.1-flash-1017` (5 min), then start 8080.
- While another job writes large files to the NVMe, model pages get evicted and tg drops (5–8 tok/s observed).
