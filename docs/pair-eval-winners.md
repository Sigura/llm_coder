# Pair programming eval: winners and headline

Files: [pair-eval-winners.md](pair-eval-winners.md) (winners + headline, short), [pair-eval-report.md](pair-eval-report.md) (setup, generated tables, literature, gaps), [pair-eval-findings.md](pair-eval-findings.md) (per-run findings).

## Winners (hand-written, refreshed on each finished seed; state 2026-11-25 04:25)

score = (0.3 pass@1 + 0.7 pass@2) / 29, 0–1, the sort key (ties by pass@2): pass@2 = solved within two attempts (the
second sees the first one's test failures), pass@1 = solved on the first; pass@2 weighs more since it is what the
setup solves at all, pass@1 rewards needing no retry. 0.01 of score ≈ 1 task of pass@1, 0.024 ≈ 1 task of pass@2; gaps
under ~0.02 are seed noise (details: [pair-eval-report.md](pair-eval-report.md), Headline). pass@2 of 29 is the mean when a setup has 2+ complete
seeds, otherwise its single seed (n = complete seeds). Solved/h = pass@2 per hour of eval wall time; DeepSeek runs
shared KT's two slots with another run most of the time, so their times (and solved/h) are pessimistic and noisy. tg =
single-stream decode of the writer, tok/s. Init = server launch to ready, cold after a reboot, measured on the Nov 22
23:25 restart (all servers start in parallel, so a setup waits for its slowest model).

| # | setup | practice | writer | score | pass@2 | n | pass@1 | time per seed | solved/h | writer tg | init | hardware |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | DeepSeek + DeepSeek review | solo + reviewer | DeepSeek KT | 0.87 | **27.0** (27, 28, 26) | 3 | 21.0 | 13,254–20,491 s | 6.1 | 18–20 | 8.3 min | 1× 4090 + ~330 GB RAM |
| 2 | DeepSeek + Qwen3.8 review | solo + reviewer | DeepSeek KT | 0.87 | **27.3** (29, 27, 26) | 3 | 20.0 | 12,900–17,712 s | 6.4 | 18–20 | 8.3 min | + 1× 4090 |
| 3 | nav Qwen3.8 + driver DS (tdd) | pair, tests first | DeepSeek KT | 0.86 | **26.5** (24, 29) | 2 | 21.0 | 23,587–37,269 s | 3.1 | 18–20 | 8.3 min | + 1× 4090 |
| 4 | nav DS + driver DS | pair | DeepSeek KT | 0.85 | **26.7** (26, 29, 25) | 3 | 20.0 | 13,362–19,648 s | 6.2 | 18–20 | 8.3 min | 1× 4090 + ~330 GB RAM |
| 5 | nav Qwen3.8 + driver DS | pair | DeepSeek KT | 0.85 | **26.7** (26, 28, 26) | 3 | 19.7 | 11,335–22,267 s | 6.3 | 18–20 | 8.3 min | + 1× 4090 |
| 6 | nav DS + driver DS (keep-unrevised) | pair, keep the pre-review file | DeepSeek KT | 0.84 | **26.7** (27, 27, 26) | 3 | 19.3 | 14,162–25,062 s | 5.0 | 18–20 | 8.3 min | 1× 4090 + ~330 GB RAM |
| 7 | nav DS + driver DS (tdd) | pair, tests first | DeepSeek KT | 0.83 | **25.0** (24, 26, 25) | 3 | **22.3** | 28,028–34,307 s | 2.8 | 18–20 | 8.3 min | 1× 4090 + RAM |
| 8 | DeepSeek alone | solo | DeepSeek | 0.79 | **24.7** | 3 | 19.0 | 7,536–10,754 s | 9.7 | 14.1–14.5 (llama.cpp) | ~5 min + warm-up | 2 GPUs + RAM |
| 9 | nav Qwen3.6 MTP + driver DS | pair | DeepSeek KT | 0.77 | 23.7 (26, 23, 22) | 3 | 18.7 | 9,774–15,162 s | 6.6 | 18–20 | 8.3 min | + 1× 4090 |
| 10 | nav Qwen3.8 + driver Qwen3.8 (tdd) | pair, tests first | Qwen3.8 | 0.72 | 22.3 (22, 20, 25) | 3 | 17.3 | 10,692–14,201 s | 6.3 | 31–35 | 53 s | 1× 4090 |
| 11 | nav DS (KT) + driver Qwen3.8 | pair | Qwen3.8 | 0.68 | 22.0 (20, 23, 23) | 3 | 14.0 | 7,819–13,198 s | 7.9 | 31–35 | 8.3 min | 2× 4090 + RAM |
| 12 | Qwen3.8 + DeepSeek review | solo + reviewer | Qwen3.8 | 0.67 | 22.0 (22, 22, 22) | 3 | 13.7 | 7,360–11,792 s | 8.2 | 31–35 | 53 s (+ DS) | 3 GPUs + RAM |
| 13 | nav Qwen3.8 + driver Qwen3.8 | pair | Qwen3.8 | 0.58 | 19.0 (16, 22, 19) | 3 | 12.0 | 5,962–6,698 s | 11.0 | 31–35 | 53 s | 1× 4090 |
| 14 | Qwen3.6 MTP + DeepSeek review | solo + reviewer | Qwen3.6 MTP | 0.55 | 18 | 1 | 11 | 9,545 s | 6.8 | 205–215 | 8.3 min | 2× 4090 + RAM |
| 15 | Qwen3.8 + Qwen3.6 MTP review | solo + reviewer | Qwen3.8 | 0.54 | 17.7 (21, 20, 12) | 3 | 11.0 | 4,570–5,546 s | 13.0 | 31–35 | 53 s | 2× 4090 |
| 16 | Qwen3.8 alone | solo | Qwen3.8 | 0.51 | 16.7 | 3 | 10.0 | 2,366–2,763 s | **23.6** | 31–35 | 53 s | 1× 4090 |
| 17 | Qwen3.6 MTP + Qwen3.8 review | solo + reviewer | Qwen3.6 MTP | 0.49 | 15.7 (16, 15, 16) | 3 | 10.7 | 2,069–2,860 s | 22.7 | 205–215 | 53 s | 2× 4090 |
| 18 | nav Qwen3.6 MTP + driver Qwen3.8 | pair | Qwen3.8 | 0.47 | 14.7 | 3 | 10.7 | 3,602–4,743 s | 12.7 | 31–35 | 53 s | 2× 4090 |
| 19 | nav DS + driver Qwen3.6 MTP | pair | Qwen3.6 MTP | 0.41 | 14 | 1 | 7 | 5,954 s | 8.5 | 205–215 | 8.3 min | 2× 4090 + RAM |
| 20 | Qwen3.6 MTP alone | solo | Qwen3.6 MTP | 0.31 | 9.7 | 3 | 7.0 | 812–914 s | **40.5** | 205–215 | 38 s | 1× 4090 |

Practice effect per writer (pass@2; n > 1 marked):

| writer \ practice | solo | + reviewer | nav DeepSeek | nav Qwen3.8 | nav Qwen3.6 MTP | tests first |
|---|---|---|---|---|---|---|
| DeepSeek | 24.7 (n 3) | rQ8 27.3 (n 3), rDS 27.0 (n 3) | 26.7 (n 3); keep 26.7 (n 3) | 26.7 (n 3) | 23.7 (n 3) | 26.5 (nav Q8, n 2), 25.0 (nav DS, n 3) |
| Qwen3.8 | 16.7 (n 3) | rDS 22.0 (n 3), rQ6 17.7 (n 3) | 22.0 (KT, n 3), 21 (llama.cpp) | 19.0 (n 3) | 14.7 (n 3) | 22.3 (nav Q8, n 3), 20 (nav DS) |
| Qwen3.6 MTP | 9.7 (n 3) | rDS 18 (s1; s2, s3 last), rQ8 15.7 (n 3) | 14 | 13 | 9 | — |

Readout:
- New: DeepSeek + Qwen3.8 review 27.3 over 3 seeds (29, 27, 26; pass@1 20.0), the best n=3 setup, +0.6 over the
  DS+DS pair and +2.6 over DeepSeek alone. DeepSeek + DeepSeek review 27.0 over 3 seeds (27, 28, 26;
  pass@1 21.0, the best n=3 pass@1). The four best DeepSeek setups (rQ8, rDS, DS+DS pair, Q8>DS pair) sit within 0.6:
  any second look adds 2–2.6 over DeepSeek alone; who looks and in what form is within a seed's noise.
  Tests first (DS+DS, 25.0 over 3 seeds: 24, 26, 25) gives the best pass@1 of all (22.3) but a lower pass@2 at 2x the time.
  With Qwen3.8 writing the tests: s2 solved **all 29** (pass@1 23, 23,587 s), the first 29/29 tdd seed; with s1 (24 / 19)
  26.5 / 21.0 over 2 seeds (score 0.86, #3), level with the plain Q8>DS pair (26.7 / 19.7) at pass@2, +1.3 pass@1, at
  2–3x the time. Only 6 of 29 Qwen3.8 test files pass the reference in either seed, so the gain is not better tests
  (s1: DeepSeek chased the wrong ones; s2: it solved all 23 tasks with wrong tests anyway). s3 decides.
  By score the two DeepSeek reviewer setups lead (0.87 each; rDS ahead on pass@1), the DeepSeek pairs and tests first
  follow at 0.83–0.86, DeepSeek alone 0.79.
- Best quality (n 3): three DeepSeek-driven pairs, level: DeepSeek navigating DeepSeek 26.7 over 3 seeds (26, 29, 25, pass@1
  20 every seed), Qwen3.8 navigating DeepSeek 26.7 over 3 seeds (26, 28, 26, pass@1 19.7; 11–12k s per seed when KT
  is not shared three ways, the fastest DeepSeek pair), and keep-unrevised DS+DS 26.7 over 3 seeds (27, 27, 26, pass@1
  19.3; its fenced-block rescue never triggered, so it is plain DS+DS).
  All beat DeepSeek alone (24.7) by about 2; the gain is the review turn. Qwen3.6 navigating DeepSeek: 23.7 over 3
  seeds, no gain.
- Order now (user, Nov 23 21:27: DeepSeek-written headline setups on the other practices to n=3 first; ETAs rough):
  KT slot A: DeepSeek + Qwen3.8 review s1-s3 done 08:07; tdd DS+DS s1-s3 done 23:43 (s3: 25),
  nav DS + driver Qwen3.8 (KT) s3 done 01:43 (23), now tdd nav DS + driver Qwen3.8 s2 (since 01:44); slot B: DeepSeek + DeepSeek review s1-s3 done 08:34; tdd nav Qwen3.8 + driver DS s1 done 20:27 (24), s2 done 03:03 (29), s3 running
  since 03:03 (~Nov 25 noon). Then on slot A: tdd nav DS + driver Qwen3.8 s3. Qwen3.6 + Qwen3.8 review done (15.7, n 3, +6.0 over Qwen3.6 alone); Qwen3.6 + DeepSeek review s1: 18 (+8.3 over
  Qwen3.6 alone, above the Qwen3.8 reviewer), s2/s3 at the end. Not remeasured:
  Qwen3.6 MTP-written pairs (no potential, cut Nov 21) and nav DS on llama.cpp (engine retired; the KT run replaces it).
- Best for Qwen3.8: tests first with a Qwen3.8 navigator (+5.6, 22.3 over 3 seeds
  (22, 20, 25), pass@1 17.3, at 5x Qwen3.8 alone's time; no other GPU needed) or a DeepSeek reviewer (+5.3, 22.0 over 3 seeds,
  22 every seed, pass@1 13.7; 3.5x Qwen3.8's time plus KT) or a DeepSeek navigator (+5.3, 22.0 over 3 seeds (20, 23, 23), pass@1 14.0; all three within a seed of each other). The Qwen3.6 reviewer's +3.8 did not hold: 17.7 over 3 seeds (21, 20, 12), +1.0. Qwen3.8 navigating itself: 19.0
  over 3 seeds (16, 22, 19), a small real +2.3. A weak navigator (Qwen3.6) makes Qwen3.8 worse (14.7 vs 16.7 over 3 seeds).
- Best throughput: Qwen3.6 MTP alone (40 solved/h but 9.7 of 29), then Qwen3.8 alone (24/h, 16.7) and Qwen3.8 + Qwen3.6
  review (13.0/h, 17.7 over 3 seeds: seed 3 fell to 12, so its gain over Qwen3.8 alone is only +1.0).
- Cold start: DeepSeek KT needs 8.3 min after a reboot, the Qwen models under a minute.

## Headline (score = (0.3 pass@1 + 0.7 pass@2) / 29; pass@2 of 29)

| setup | score | pass@2 per seed | mean | pass@1 mean | time per seed |
|---|---|---|---|---|---|
| DS+rDS | 0.87 | 27, 28, 26 | 27.0 | 21.0 | 13,254–20,491 s |
| DS+rQ8 | 0.87 | 29, 27, 26 | 27.3 | 20.0 | 12,900–17,712 s |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 0.86 | 24, 29, seed 3: 3 of the first 5 | 26.5 | 21.0 | 23,587–37,269 s |
| nav DeepSeek (KT) + driver DeepSeek (KT) | 0.85 | 26, 29, 25 | 26.7 | 20.0 | 13,362–19,648 s |
| nav Qwen3.8 + driver DeepSeek (KT) | 0.85 | 26, 28, 26 | 26.7 | 19.7 | 11,335–22,266 s |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | 0.84 | 27, 27, 26 | 26.7 | 19.3 | 14,162–25,062 s |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 0.83 | 24, 26, 25 | 25.0 | 22.3 | 28,028–34,307 s |
| DeepSeek alone | 0.79 | 28 (pieced together), 23, 23 | 24.7 | 19.0 | 7,536–10,754 s |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | 0.76 | 26, 23, 22 | 23.7 | 18.7 | 9,774–15,162 s |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 0.72 | 22, 20, 25 | 22.3 | 17.3 | 10,692–14,201 s |
| PAIR-KT | 0.68 | 20, 23, 23 | 22.0 | 14.0 | 7,819–13,198 s |
| Q8+rDS | 0.67 | 22, 22, 22 | 22.0 | 13.7 | 7,360–11,792 s |
| DS>Q8 tdd | 0.66 | 20, seed 2: 15 of the first 17 | 20 | 17 | 16,813 s |
| PAIR (llama.cpp) | 0.65 | 21, seed 2: 13 of the first 15 | 21 | 14 | 7,598 s |
| nav Qwen3.8 + driver Qwen3.8 | 0.58 | 16, 22, 19 | 19.0 | 12.0 | 5,962–6,698 s |
| Q6+rDS | 0.55 | 18 | 18 | 11 | 9,545 s |
| Q8+rQ6 | 0.54 | 21, 20, 12 | 17.7 | 11.0 | 4,570–5,546 s |
| Qwen3.8 alone | 0.51 | 18, 17, 15 | 16.7 | 10.0 | 2,366–2,763 s |
| Q6+rQ8 | 0.49 | 16, 15, 16 | 15.7 | 10.7 | 2,069–2,860 s |
| nav Qwen3.6 MTP + driver Qwen3.8 | 0.46 | 16, 17, 11 | 14.7 | 10.7 | 3,602–4,743 s (Qwen3.6 on the 3090 Ti) |
| nav DeepSeek (KT) + driver Qwen3.6 MTP | 0.41 | 14 | 14 | 7 | 5,954 s |
| nav Qwen3.8 + driver Qwen3.6 MTP | 0.40 | 13 | 13 | 8 | 3,000 s |
| Qwen3.6 MTP alone | 0.31 | 12, 8, 9 | 9.7 | 7.0 | 812–914 s |
| nav Qwen3.6 MTP + driver Qwen3.6 MTP | 0.26 | 9 | 9 | 4 | 2,704 s |
