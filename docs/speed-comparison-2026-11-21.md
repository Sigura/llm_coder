# Speed comparison: models, engines and combinations (2026-11-21)

Copy of `LLM_ROOT/results/kt-review-2026-11-21/speed-comparison.md` as of 2026-11-22; the live file there may be newer.

Host: 2× EPYC 7601 (8 NUMA nodes), 503 GB RAM, GPUs 0,2,3 RTX 4090, GPU 1 RTX 3090 Ti (power-capped).
pp = prompt (prefill) tok/s, tg = decode tok/s. Unless noted: real coding requests through the server,
req-2 = 8,041 prompt tokens, req-3 = 44,484 prompt tokens, 1,024 output tokens.
Sources: `results.tsv` in this directory, `remeasure-2026-11-20/`, `two-model-2026-11-13/report.md`, `docs/token-speed.md`.

## 1. Serving lineup

| port | model | engine | GPUs | context | pp | tg (one stream) |
|---|---|---|---|---|---|---|
| 8080 | DeepSeek V4.1 Flash 1017 UD-Q2_K_XL | llama.cpp, MoE cache 16896, `-ub 4096`, 48 threads | 0,1 | 2 slots × 128k | 100 / 126 | 14.1 / 14.5 |
| 8080 (alt) | DeepSeek V4.1 Flash 1017 FP8 (experts MXFP4 on the CPU) | SGLang + KTransformers, 64 threads, 2 running requests, chunk 16,384 | 0 | 128k-token pool shared by both requests | 268 / 442 | 13.6 / 13.5 |
| 8086 | Qwen3.8-27B dense UD-Q6_K | llama.cpp | 2 | 64k | 1,576 (54k prompt) | 34.9 |
| 8085 | Qwen3.6-35B-A3B + MTP UD-Q4_K_XL | llama.cpp, MTP draft 2 | 3 | 64k | 4,314 (54k prompt) | 205–219 |

Qwen numbers: Nov 15, before the Nov 20 power changes (DeepSeek lost 6–21% from those; the Qwens were not remeasured).

## 2. DeepSeek: llama.cpp vs KTransformers, one session

| engine / setup | GPUs | pp 8k | pp 44.5k | tg 8k | tg 44.5k | time to first token, 44.5k |
|---|---|---|---|---|---|---|
| llama.cpp (current) | 0,1 | 99.9 | 126.2 | 14.1 | 14.5 | ~352 s |
| KT, 64 threads, 1 request, chunk 36,864 | 0 | 259 | 560 | 13.8 | 13.8 | ~79 s |
| **KT, 64 threads, 2 requests, chunk 16,384 (stack config)** | 0 | 268 | 442 | 13.6 | 13.5 | ~101 s |
| KT, 48 threads, 1 request | 0,3 | 387 | 734 | 13.1 | 13.0 | ~61 s |
| KT, 48 threads, 2 requests | 0,3 | 387 | 779 | 12.3 | 12.4 | ~57 s |
| KT, 64 threads (wrapper default) | 0,3 | 396 | 746 | 10.4 | 10.7 | ~60 s |
| KT, 48 threads, 1 request | 0 | — | — | 12.8–13.0 | — | — |
| Xolotl, exact routing (rejected) | 0 | 158 | 245 | 4.0 | 3.4 | ~182 s |
| Xolotl, lossy default routing (rejected) | 0 | 157 | 245 | 7.3 | 4.1 | ~182 s |

Estimated OpenCode turn (14.5k-token prompt, 1k output): llama.cpp ~195 s (measured), KT stack config ~125 s
(estimate: 14.5k at ~300 pp + 1k at 13.5 tg).

## 3. DeepSeek: two sessions at once

| engine / setup | GPUs | one alone, tg | both at once, tg each | both at once, total tg | pp at once (8k / 44.5k) |
|---|---|---|---|---|---|
| llama.cpp, 1 slot | 0,1 | 11.5 | second waits | 11.5 | — |
| llama.cpp, 2 slots (Nov 16, before the MoE cache) | 0,1 | 11.4–11.5 | 6.8–7.4 | 14.3 | — |
| llama.cpp, 2 servers | 0,1 + 2,3 | 11.4–11.5 | 7.8–7.9 | 15.6 | — |
| llama.cpp, 2 slots + MoE cache | 0,1 | 14.1–14.5 | — | +0–4% over 2 slots without cache | — |
| KT, 1 request (`kt-par`) | 0 | 13.8 | second waits | ~13 | 262 / 251 (44.5k queued behind 8k) |
| **KT, 2 requests, chunk 16,384** | 0 | 13.5 | 5.1 / 7.3 * | ~14.7 | 132 / 362 |
| KT, 2 requests, 48 threads | 0,3 | 12.3 | 5.8 / 6.6 * | ~13.2 | 169 / 652 |

\* Per-request average over its whole decode, which overlaps the other request's prefill; "total tg" is the server's
decode rate while both decode.

## 4. KT prefix cache (repeat of the same prompt, no flush)

| prompt | first | repeat |
|---|---|---|
| 8k | 266 pp | 265 pp (shorter than one chunk: no reuse) |
| 44.5k | 560 pp | 7,151 pp (whole 36,864-token chunks reused) |

llama.cpp runs with `--cache-ram 0` (output corruption workaround), so it has no host-RAM prompt cache across requests.

## 5. Quality next to speed

| setup | eval | pass@1 | pass@2 | tests@2 | time |
|---|---|---|---|---|---|
| DeepSeek llama.cpp alone | coding eval, 29 tasks, mean of 3 seeds | 19.0 | 24.7 | — | 7,500–10,750 s |
| Qwen3.8 alone | same | 10.0 | 16.7 | — | 2,370–2,760 s |
| Qwen3.8 + DeepSeek review | same, seed 1 | 14 | 22 | — | 7,360 s |
| Qwen3.8 + Qwen3.6 MTP review | same, seed 1 | 14 | 21 | — | 4,570 s |
| Qwen3.6 MTP | same, mean of 3 seeds | 7.0 | 9.7 | — | — |
| Pair eval, navigator DeepSeek llama.cpp | evalpair, seed 1 | 14 | 21 | 25.1 | 7,598 s |
| Pair eval, navigator DeepSeek KT | evalpair, seed 1 | 13 | 20 | 24.7 | 7,819 s |

## 6. Resource cost

| setup | GPUs | host RAM | launch |
|---|---|---|---|
| llama.cpp DeepSeek | 0,1 (3090 Ti usable) | ~190 GiB page cache (mmapped, evictable) | ~5 min + warm-up |
| KT DeepSeek, stack config | 0 (4090 only, SM89) | ~400 GiB, held for good | ~8 min; +23 min calibration once per new setup; +10 min Triton compile on the very first launch |
| Qwen3.8 + Qwen3.6 MTP | 2 and 3 | small | ~1 min |

With KT on GPU 0, GPUs 2,3 stay with the Qwens and GPU 1 is free. llama.cpp DeepSeek and KT cannot run together (RAM).
