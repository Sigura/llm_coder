# Pair programming eval: winners and headline

Copy of `LLM_ROOT/results/pair-eval/pair-winners.md` as of 2026-11-24 09:50; the live file there may be newer (tests-first
and remeasure runs still running). Here `pair-winners.md`, `pair-report.md`, `pair-findings.md` are
[pair-eval-winners.md](pair-eval-winners.md), [pair-eval-report.md](pair-eval-report.md),
[pair-eval-findings.md](pair-eval-findings.md).

Files: `pair-winners.md` (winners + headline, short), `pair-report.md` (setup, generated tables, literature, gaps), `pair-findings.md` (per-run findings).

## Winners (hand-written, refreshed on each finished seed; state 2026-11-24 08:55)

pass@2 of 29 is the mean when a setup has 2+ complete seeds, otherwise its single seed (n = complete seeds). Solved/h
= pass@2 per hour of eval wall time; DeepSeek runs shared KT's two slots with another run most of the time, so their
times (and solved/h) are pessimistic and noisy. tg = single-stream decode of the writer, tok/s. Init = server launch
to ready, cold after a reboot, measured on the Nov 22 23:25 restart (all servers start in parallel, so a setup waits
for its slowest model).

| # | setup | practice | writer | pass@2 | n | pass@1 | time per seed | solved/h | writer tg | init | hardware |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | DeepSeek + Qwen3.8 review | solo + reviewer | DeepSeek KT | **27.3** (29, 27, 26) | 3 | 20.0 | 12,900–17,712 s | 6.4 | 18–20 | 8.3 min | + 1× 4090 |
| 2 | DeepSeek + DeepSeek review | solo + reviewer | DeepSeek KT | **27.0** (27, 28, 26) | 3 | 21.0 | 13,254–20,491 s | 6.1 | 18–20 | 8.3 min | 1× 4090 + ~330 GB RAM |
| 3 | nav DS + driver DS | pair | DeepSeek KT | **26.7** (26, 29, 25) | 3 | 20.0 | 13,362–19,648 s | 6.2 | 18–20 | 8.3 min | 1× 4090 + ~330 GB RAM |
| 4 | nav Qwen3.8 + driver DS | pair | DeepSeek KT | **26.7** (26, 28, 26) | 3 | 19.7 | 11,335–22,267 s | 6.3 | 18–20 | 8.3 min | + 1× 4090 |
| 5 | nav DS + driver DS (keep-unrevised) | pair, keep the pre-review file | DeepSeek KT | **26.7** (27, 27, 26) | 3 | 19.3 | 14,162–25,062 s | 5.0 | 18–20 | 8.3 min | 1× 4090 + ~330 GB RAM |
| 6 | DeepSeek alone | solo | DeepSeek | **24.7** | 3 | 19.0 | 7,536–10,754 s | 9.7 | 14.1–14.5 (llama.cpp) | ~5 min + warm-up | 2 GPUs + RAM |
| 7 | nav DS + driver DS (tdd) | pair, tests first | DeepSeek KT | 24 | 1 | 22 | 34,307 s | 2.5 | 18–20 | 8.3 min | 1× 4090 + RAM |
| 8 | nav Qwen3.6 MTP + driver DS | pair | DeepSeek KT | 23.7 (26, 23, 22) | 3 | 18.7 | 9,774–15,162 s | 6.6 | 18–20 | 8.3 min | + 1× 4090 |
| 9 | nav Qwen3.8 + driver Qwen3.8 (tdd) | pair, tests first | Qwen3.8 | 22.3 (22, 20, 25) | 3 | 17.3 | 10,692–14,201 s | 6.3 | 31–35 | 53 s | 1× 4090 |
| 10 | Qwen3.8 + DeepSeek review | solo + reviewer | Qwen3.8 | 22.0 (22, 22, 22) | 3 | 13.7 | 7,360–11,792 s | 8.2 | 31–35 | 53 s (+ DS) | 3 GPUs + RAM |
| 11 | nav DS (KT) + driver Qwen3.8 | pair | Qwen3.8 | 21.5 (20, 23) | 2 | 13.5 | 7,819–13,198 s | 7.4 | 31–35 | 8.3 min | 2× 4090 + RAM |
| 12 | nav Qwen3.8 + driver Qwen3.8 | pair | Qwen3.8 | 19.0 (16, 22, 19) | 3 | 12.0 | 5,962–6,698 s | 11.0 | 31–35 | 53 s | 1× 4090 |
| 13 | Qwen3.6 MTP + DeepSeek review | solo + reviewer | Qwen3.6 MTP | 18 | 1 | 11 | 9,545 s | 6.8 | 205–215 | 8.3 min | 2× 4090 + RAM |
| 14 | Qwen3.8 + Qwen3.6 MTP review | solo + reviewer | Qwen3.8 | 17.7 (21, 20, 12) | 3 | 11.0 | 4,570–5,546 s | 13.0 | 31–35 | 53 s | 2× 4090 |
| 15 | Qwen3.8 alone | solo | Qwen3.8 | 16.7 | 3 | 10.0 | 2,366–2,763 s | **23.6** | 31–35 | 53 s | 1× 4090 |
| 16 | Qwen3.6 MTP + Qwen3.8 review | solo + reviewer | Qwen3.6 MTP | 15.7 (16, 15, 16) | 3 | 10.7 | 2,069–2,860 s | 22.7 | 205–215 | 53 s | 2× 4090 |
| 17 | nav Qwen3.6 MTP + driver Qwen3.8 | pair | Qwen3.8 | 14.7 | 3 | 10.7 | 3,602–4,743 s | 12.7 | 31–35 | 53 s | 2× 4090 |
| 18 | nav DS + driver Qwen3.6 MTP | pair | Qwen3.6 MTP | 14 | 1 | 7 | 5,954 s | 8.5 | 205–215 | 8.3 min | 2× 4090 + RAM |
| 19 | Qwen3.6 MTP alone | solo | Qwen3.6 MTP | 9.7 | 3 | 7.0 | 812–914 s | **40.5** | 205–215 | 38 s | 1× 4090 |

Practice effect per writer (pass@2; n > 1 marked):

| writer \ practice | solo | + reviewer | nav DeepSeek | nav Qwen3.8 | nav Qwen3.6 MTP | tests first |
|---|---|---|---|---|---|---|
| DeepSeek | 24.7 (n 3) | rQ8 27.3 (n 3), rDS 27.0 (n 3) | 26.7 (n 3); keep 26.7 (n 3) | 26.7 (n 3) | 23.7 (n 3) | 24 (nav DS) |
| Qwen3.8 | 16.7 (n 3) | rDS 22.0 (n 3), rQ6 17.7 (n 3) | 21.5 (KT, n 2), 21 (llama.cpp) | 19.0 (n 3) | 14.7 (n 3) | 22.3 (nav Q8, n 3), 20 (nav DS) |
| Qwen3.6 MTP | 9.7 (n 3) | rDS 18 (s1; s2, s3 last), rQ8 15.7 (n 3) | 14 | 13 | 9 | — |

Readout:
- New: DeepSeek + Qwen3.8 review 27.3 over 3 seeds (29, 27, 26; pass@1 20.0), the best n=3 setup, +0.6 over the
  DS+DS pair and +2.6 over DeepSeek alone. DeepSeek + DeepSeek review 27.0 over 3 seeds (27, 28, 26;
  pass@1 21.0, the best n=3 pass@1). The four best DeepSeek setups (rQ8, rDS, DS+DS pair, Q8>DS pair) sit within 0.6:
  any second look adds 2–2.6 over DeepSeek alone; who looks and in what form is within a seed's noise.
- Best quality (n 3): three DeepSeek-driven pairs, level: DeepSeek navigating DeepSeek 26.7 over 3 seeds (26, 29, 25, pass@1
  20 every seed), Qwen3.8 navigating DeepSeek 26.7 over 3 seeds (26, 28, 26, pass@1 19.7; 11–12k s per seed when KT
  is not shared three ways, the fastest DeepSeek pair), and keep-unrevised DS+DS 26.7 over 3 seeds (27, 27, 26, pass@1
  19.3; its fenced-block rescue never triggered, so it is plain DS+DS).
  All beat DeepSeek alone (24.7) by about 2; the gain is the review turn. Qwen3.6 navigating DeepSeek: 23.7 over 3
  seeds, no gain.
- Order now (user, Nov 23 21:27: DeepSeek-written headline setups on the other practices to n=3 first; ETAs rough):
  KT slot A: DeepSeek + Qwen3.8 review s1-s3 done 08:07; tdd DS+DS s2 (running since 08:08), s3
  (~Nov 25 morning); slot B: DeepSeek + DeepSeek review s1-s3 done 08:34; tdd nav Qwen3.8 + driver DS s1-s3 (running since 08:38,
  ~Nov 25 midday). Remeasure in progress after that: nav DS + driver Qwen3.8 (KT) s3 (8 tasks done), tdd nav DS + driver
  Qwen3.8 s2, s3. Qwen3.6 + Qwen3.8 review done (15.7, n 3, +6.0 over Qwen3.6 alone); Qwen3.6 + DeepSeek review s1: 18 (+8.3 over
  Qwen3.6 alone, above the Qwen3.8 reviewer), s2/s3 at the end. Not remeasured:
  Qwen3.6 MTP-written pairs (no potential, cut Nov 21) and nav DS on llama.cpp (engine retired; the KT run replaces it).
- Best for Qwen3.8: tests first with a Qwen3.8 navigator (+5.6, 22.3 over 3 seeds
  (22, 20, 25), pass@1 17.3, at 5x Qwen3.8 alone's time; no other GPU needed) or a DeepSeek reviewer (+5.3, 22.0 over 3 seeds,
  22 every seed, pass@1 13.7; 3.5x Qwen3.8's time plus KT) or a DeepSeek navigator (+4.8, 21.5 over 2 seeds; s3 runs). The Qwen3.6 reviewer's +3.8 did not hold: 17.7 over 3 seeds (21, 20, 12), +1.0. Qwen3.8 navigating itself: 19.0
  over 3 seeds (16, 22, 19), a small real +2.3. A weak navigator (Qwen3.6) makes Qwen3.8 worse (14.7 vs 16.7 over 3 seeds).
- Best throughput: Qwen3.6 MTP alone (40 solved/h but 9.7 of 29), then Qwen3.8 alone (24/h, 16.7) and Qwen3.8 + Qwen3.6
  review (13.0/h, 17.7 over 3 seeds: seed 3 fell to 12, so its gain over Qwen3.8 alone is only +1.0).
- Cold start: DeepSeek KT needs 8.3 min after a reboot, the Qwen models under a minute.

## Headline (pass@2 of 29)

| setup | pass@2 per seed | mean | pass@1 mean | time per seed |
|---|---|---|---|---|
| DS+rQ8 | 29, 27, 26 | 27.3 | 20.0 | 12,900–17,712 s |
| DS+rDS | 27, 28, 26 | 27.0 | 21.0 | 13,254–20,491 s |
| nav DeepSeek (KT) + driver DeepSeek (KT) | 26, 29, 25 | 26.7 | 20.0 | 13,362–19,648 s |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | 27, 27, 26 | 26.7 | 19.3 | 14,162–25,062 s |
| nav Qwen3.8 + driver DeepSeek (KT) | 26, 28, 26 | 26.7 | 19.7 | 11,335–22,266 s |
| DeepSeek alone | 28 (pieced together), 23, 23 | 24.7 | 19.0 | 7,536–10,754 s |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 24, seed 2: 12 of the first 13 | 24 | 22 | 34,307 s |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | 26, 23, 22 | 23.7 | 18.7 | 9,774–15,162 s |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 22, 20, 25 | 22.3 | 17.3 | 10,692–14,201 s |
| Q8+rDS | 22, 22, 22 | 22.0 | 13.7 | 7,360–11,792 s |
| PAIR-KT | 20, 23, seed 3: 6 of the first 8 | 21.5 | 13.5 | 7,819–13,198 s |
| PAIR (llama.cpp) | 21, seed 2: 13 of the first 15 | 21 | 14 | 7,598 s |
| DS>Q8 tdd | 20 | 20 | 17 | 16,813 s |
| nav Qwen3.8 + driver Qwen3.8 | 16, 22, 19 | 19.0 | 12.0 | 5,962–6,698 s |
| Q6+rDS | 18 | 18 | 11 | 9,545 s |
| Q8+rQ6 | 21, 20, 12 | 17.7 | 11.0 | 4,570–5,546 s |
| Qwen3.8 alone | 18, 17, 15 | 16.7 | 10.0 | 2,366–2,763 s |
| Q6+rQ8 | 16, 15, 16 | 15.7 | 10.7 | 2,069–2,860 s |
| nav Qwen3.6 MTP + driver Qwen3.8 | 16, 17, 11 | 14.7 | 10.7 | 3,602–4,743 s (Qwen3.6 on the 3090 Ti) |
| nav DeepSeek (KT) + driver Qwen3.6 MTP | 14 | 14 | 7 | 5,954 s |
| nav Qwen3.8 + driver Qwen3.6 MTP | 13 | 13 | 8 | 3,000 s |
| Qwen3.6 MTP alone | 12, 8, 9 | 9.7 | 7.0 | 812–914 s |
| nav Qwen3.6 MTP + driver Qwen3.6 MTP | 9 | 9 | 4 | 2,704 s |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | seed 1: 2 of the first 2 | — | — | — |
