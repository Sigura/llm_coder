# Pair programming eval: winners and headline

Files: [pair-eval-winners.md](pair-eval-winners.md) (winners + headline, short), [pair-eval-report.md](pair-eval-report.md) (setup, generated tables, literature, gaps), [pair-eval-findings.md](pair-eval-findings.md) (per-run findings).

## Winners (hand-written, refreshed on each finished seed; state 2026-11-25 16:40)

Sort key: quality, ties by pass@1. The old score (0.3 pass@1 + 0.7 pass@2) / 29 is kept in the last column; it was
replaced (user, Nov 26) because pass@2 sits at 25–29 of 29 for every DeepSeek setup, so seed noise (2–4 tasks) was
larger than the gaps it ranked, and it ignored cost.
- quality = share of the task's hidden tests passed by the better of the two attempts, averaged over the 29 tasks and
  the complete seeds (burnish's tests@2 / 29): a near miss (6/7) counts 0.86, not 0. One setup moves by 0.02–0.04
  between seeds, so gaps under ~0.03 are noise.
- pass@1 = solved on the first attempt (no retry), pass@2 = solved within two (the second sees the first one's test
  failures); of 29, mean of the complete seeds (n), or the single seed.
- min per solved task = eval wall time of all complete seeds / tasks solved (pass@2). DeepSeek runs shared KT's two
  slots with another run most of the time, so their times are pessimistic and noisy.
- vs DeepSeek alone = paired per task: each task's solve rate (share of seeds solved by pass@2) against DeepSeek
  alone's (seeds 2 and 3, 23 each: the pieced-together seed 1 has no per-task data), summed separately over the tasks
  it solves more often (+) and less often (−). +5.0 / −1.0 = five tasks' worth gained, one lost.
- tg = single-stream decode of the writer, tok/s. Init = server launch to ready, cold after a reboot, measured on the Nov 22
23:25 restart (all servers start in parallel, so a setup waits for its slowest model).

| # | setup | practice | writer | quality | pass@2 | n | pass@1 | min per solved task | vs DeepSeek alone (tasks + / −) | writer tg | init | hardware | old score |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | DeepSeek + Qwen3.8 review | solo + reviewer | DeepSeek KT | 0.990 | **27.3** (29, 27, 26) | 3 | 20.0 | 9.4 | +4.7 / −0.3 | 18–20 | 8.3 min | + 1× 4090 | 0.87 |
| 2 | DeepSeek + DeepSeek review | solo + reviewer | DeepSeek KT | 0.977 | **27.0** (27, 28, 26) | 3 | 21.0 | 9.8 | +5.0 / −1.0 | 18–20 | 8.3 min | 1× 4090 + ~330 GB RAM | 0.87 |
| 3 | nav DS + driver DS | pair | DeepSeek KT | 0.975 | **26.7** (26, 29, 25) | 3 | 20.0 | 9.7 | +5.3 / −1.7 | 18–20 | 8.3 min | 1× 4090 + ~330 GB RAM | 0.85 |
| 4 | nav Qwen3.8 + driver DS | pair | DeepSeek KT | 0.973 | **26.7** (26, 28, 26) | 3 | 19.7 | 9.6 | +4.8 / −1.2 | 18–20 | 8.3 min | + 1× 4090 | 0.85 |
| 5 | nav Qwen3.8 + driver DS (tdd) | pair, tests first | DeepSeek KT | 0.972 | **26.3** (24, 29, 26) | 3 | 21.3 | 18.3 | +4.5 / −1.2 | 18–20 | 8.3 min | + 1× 4090 | 0.86 |
| 6 | nav DS + driver DS (keep-unrevised) | pair, keep the pre-review file | DeepSeek KT | 0.971 | **26.7** (27, 27, 26) | 3 | 19.3 | 12.0 | +5.0 / −1.3 | 18–20 | 8.3 min | 1× 4090 + ~330 GB RAM | 0.84 |
| 7 | nav DS + driver DS (tdd) | pair, tests first | DeepSeek KT | 0.970 | **25.0** (24, 26, 25) | 3 | **22.3** | 21.4 | +4.8 / −2.8 | 18–20 | 8.3 min | 1× 4090 + RAM | 0.83 |
| 8 | nav Qwen3.8 + driver Qwen3.8 (tdd) | pair, tests first | Qwen3.8 | 0.946 | 22.3 (22, 20, 25) | 3 | 17.3 | 9.5 | +3.8 / −4.5 | 31–35 | 53 s | 1× 4090 | 0.72 |
| 9 | DeepSeek alone | solo | DeepSeek | 0.940 | **24.7** | 3 | 19.0 | 6.6 | ref | 14.1–14.5 (llama.cpp) | ~5 min + warm-up | 2 GPUs + RAM | 0.79 |
| 10 | nav Qwen3.6 MTP + driver DS | pair | DeepSeek KT | 0.935 | 23.7 (26, 23, 22) | 3 | 18.7 | 9.0 | +2.7 / −2.0 | 18–20 | 8.3 min | + 1× 4090 | 0.77 |
| 11 | Qwen3.8 + DeepSeek review | solo + reviewer | Qwen3.8 | 0.909 | 22.0 (22, 22, 22) | 3 | 13.7 | 7.3 | +3.3 / −4.3 | 31–35 | 53 s (+ DS) | 3 GPUs + RAM | 0.67 |
| 12 | nav DS (KT) + driver Qwen3.8 | pair | Qwen3.8 | 0.901 | 22.0 (20, 23, 23) | 3 | 14.0 | 7.6 | +2.7 / −3.7 | 31–35 | 8.3 min | 2× 4090 + RAM | 0.68 |
| 13 | nav DS (KT) + driver Qwen3.8 (tdd) | pair, tests first | Qwen3.8 | 0.894 | 21.7 (20, 22, 23) | 3 | 18.3 | 12.9 | +3.2 / −4.5 | 31–35 | 8.3 min | 2× 4090 + RAM | 0.71 |
| 14 | nav Qwen3.8 + driver Qwen3.8 | pair | Qwen3.8 | 0.848 | 19.0 (16, 22, 19) | 3 | 12.0 | 5.5 | +3.0 / −7.0 | 31–35 | 53 s | 1× 4090 | 0.58 |
| 15 | Qwen3.8 + Qwen3.6 MTP review | solo + reviewer | Qwen3.8 | 0.838 | 17.7 (21, 20, 12) | 3 | 11.0 | 4.6 | +1.8 / −7.2 | 31–35 | 53 s | 2× 4090 | 0.54 |
| 16 | Qwen3.8 alone | solo | Qwen3.8 | 0.830 | 16.7 | 3 | 10.0 | 2.5 | +1.5 / −7.8 | 31–35 | 53 s | 1× 4090 | 0.51 |
| 17 | Qwen3.6 MTP + DeepSeek review | solo + reviewer | Qwen3.6 MTP | 0.821 | 18 | 1 | 11 | 8.8 | +2.5 / −7.5 | 205–215 | 8.3 min | 2× 4090 + RAM | 0.55 |
| 18 | nav Qwen3.6 MTP + driver Qwen3.8 | pair | Qwen3.8 | 0.809 | 14.7 | 3 | 10.7 | 4.7 | +0.8 / −9.2 | 31–35 | 53 s | 2× 4090 | 0.47 |
| 19 | Qwen3.6 MTP + Qwen3.8 review | solo + reviewer | Qwen3.6 MTP | 0.791 | 15.7 (16, 15, 16) | 3 | 10.7 | 2.6 | +1.2 / −8.5 | 205–215 | 53 s | 2× 4090 | 0.49 |
| 20 | nav DS + driver Qwen3.6 MTP | pair | Qwen3.6 MTP | 0.762 | 14 | 1 | 7 | 7.1 | +2.5 / −11.5 | 205–215 | 8.3 min | 2× 4090 + RAM | 0.41 |
| 21 | Qwen3.6 MTP alone | solo | Qwen3.6 MTP | 0.696 | 9.7 | 3 | 7.0 | 1.5 | +0.7 / −14.0 | 205–215 | 38 s | 1× 4090 | 0.31 |

Practice effect per writer (pass@2; n > 1 marked):

| writer \ practice | solo | + reviewer | nav DeepSeek | nav Qwen3.8 | nav Qwen3.6 MTP | tests first |
|---|---|---|---|---|---|---|
| DeepSeek | 24.7 (n 3) | rQ8 27.3 (n 3), rDS 27.0 (n 3) | 26.7 (n 3); keep 26.7 (n 3) | 26.7 (n 3) | 23.7 (n 3) | 26.3 (nav Q8, n 3), 25.0 (nav DS, n 3) |
| Qwen3.8 | 16.7 (n 3) | rDS 22.0 (n 3), rQ6 17.7 (n 3) | 22.0 (KT, n 3), 21 (llama.cpp) | 19.0 (n 3) | 14.7 (n 3) | 22.3 (nav Q8, n 3), 21.7 (nav DS, n 3) |
| Qwen3.6 MTP | 9.7 (n 3) | rDS 18 (s1; s2, s3 last), rQ8 15.7 (n 3) | 14 | 13 | 9 | — |

Readout:
- New: DeepSeek + Qwen3.8 review 27.3 over 3 seeds (29, 27, 26; pass@1 20.0), the best n=3 setup, +0.6 over the
  DS+DS pair and +2.6 over DeepSeek alone. DeepSeek + DeepSeek review 27.0 over 3 seeds (27, 28, 26;
  pass@1 21.0, the best n=3 pass@1). The four best DeepSeek setups (rQ8, rDS, DS+DS pair, Q8>DS pair) sit within 0.6:
  any second look adds 2–2.6 over DeepSeek alone; who looks and in what form is within a seed's noise.
  Tests first (DS+DS, 25.0 over 3 seeds: 24, 26, 25) gives the best pass@1 of all (22.3) but a lower pass@2 at 2x the time.
  With Qwen3.8 writing the tests: 26.3 / 21.3 over 3 seeds (24, 29, 26; s2 the first 29/29 tdd seed; quality 0.972, #5),
  level with the plain Q8>DS pair (26.7 / 19.7) at pass@2, +1.6 pass@1, at 2–3x the time. Only 6–7 of 29 Qwen3.8 test
  files pass the reference per seed, so the gain is not better tests: DeepSeek solves 19–23 of the 22–23 tasks with
  wrong tests anyway.
  New scoring (Nov 26): the seven DeepSeek-written setups with a second look are level on quality (0.970–0.990, within
  seed noise), each gains about 5 tasks over DeepSeek alone and loses 0.3–2.8. They differ in cost: review and the
  plain pairs take 9.4–9.8 min per solved task (keep-unrevised 12.0), tests first 18.3–21.4. DeepSeek + Qwen3.8 review
  is the best trade: top quality, fewest losses (−0.3), cheapest of the seven. tdd buys pass@1 (21.3–22.3) at 2x the cost.
- Best quality (n 3): three DeepSeek-driven pairs, level: DeepSeek navigating DeepSeek 26.7 over 3 seeds (26, 29, 25, pass@1
  20 every seed), Qwen3.8 navigating DeepSeek 26.7 over 3 seeds (26, 28, 26, pass@1 19.7; 11–12k s per seed when KT
  is not shared three ways, the fastest DeepSeek pair), and keep-unrevised DS+DS 26.7 over 3 seeds (27, 27, 26, pass@1
  19.3; its fenced-block rescue never triggered, so it is plain DS+DS).
  All beat DeepSeek alone (24.7) by about 2; the gain is the review turn. Qwen3.6 navigating DeepSeek: 23.7 over 3
  seeds, no gain.
- Order now (user, Nov 23 21:27: DeepSeek-written headline setups on the other practices to n=3 first; ETAs rough):
  KT slot A: DeepSeek + Qwen3.8 review s1-s3 done 08:07; tdd DS+DS s1-s3 done 23:43 (s3: 25),
  nav DS + driver Qwen3.8 (KT) s3 done 01:43 (23), tdd nav DS + driver Qwen3.8 s2 done 06:37 (22), s3 done 11:24 (23); slot B: DeepSeek + DeepSeek review s1-s3 done 08:34; tdd nav Qwen3.8 + driver DS s1 done 20:27 (24), s2 done 03:03 (29), s3 done
  10:23 (26). Qwen3.6 + Qwen3.8 review done (15.7, n 3, +6.0 over Qwen3.6 alone); Qwen3.6 + DeepSeek review s1: 18 (+8.3 over
  Qwen3.6 alone, above the Qwen3.8 reviewer), s2/s3 at the end. Not remeasured:
  Qwen3.6 MTP-written pairs (no potential, cut Nov 21) and nav DS on llama.cpp (engine retired; the KT run replaces it).
- Best for Qwen3.8: tests first with a Qwen3.8 navigator (+5.6, 22.3 over 3 seeds
  (22, 20, 25), pass@1 17.3, at 5x Qwen3.8 alone's time; no other GPU needed) or a DeepSeek reviewer (+5.3, 22.0 over 3 seeds,
  22 every seed, pass@1 13.7; 3.5x Qwen3.8's time plus KT) or a DeepSeek navigator (+5.3, 22.0 over 3 seeds (20, 23, 23), pass@1 14.0; all three within a seed of each other). Tests first with a DeepSeek navigator: 21.7 over 3 seeds (20, 22, 23), the best
  Qwen3.8 pass@1 (18.3) but 0.3–0.6 lower pass@2 than those three (within noise), at 6–7x Qwen3.8 alone's time. The Qwen3.6 reviewer's +3.8 did not hold: 17.7 over 3 seeds (21, 20, 12), +1.0. Qwen3.8 navigating itself: 19.0
  over 3 seeds (16, 22, 19), a small real +2.3. A weak navigator (Qwen3.6) makes Qwen3.8 worse (14.7 vs 16.7 over 3 seeds).
- Best throughput: Qwen3.6 MTP alone (1.5 min per solved task but 9.7 of 29), then Qwen3.8 alone (2.5 min, 16.7) and Qwen3.8 + Qwen3.6
  review (4.6 min, 17.7 over 3 seeds: seed 3 fell to 12, so its gain over Qwen3.8 alone is only +1.0).
- Cold start: DeepSeek KT needs 8.3 min after a reboot, the Qwen models under a minute.

## Headline (sort: quality, then pass@1; generated)

| setup | quality | pass@1 mean | min per solved task | vs DeepSeek alone (tasks + / −) | pass@2 per seed | pass@2 mean | time per seed | old score |
|---|---|---|---|---|---|---|---|---|
| DS+rQ8 | 0.990 | 20.0 | 9.4 | +4.7 / −0.3 | 29, 27, 26 | 27.3 | 12,900–17,712 s | 0.87 |
| DS+rDS | 0.977 | 21.0 | 9.8 | +5.0 / −1.0 | 27, 28, 26 | 27.0 | 13,254–20,491 s | 0.87 |
| nav DeepSeek (KT) + driver DeepSeek (KT) | 0.975 | 20.0 | 9.7 | +5.3 / −1.7 | 26, 29, 25 | 26.7 | 13,362–19,648 s | 0.85 |
| nav Qwen3.8 + driver DeepSeek (KT) | 0.973 | 19.7 | 9.6 | +4.8 / −1.2 | 26, 28, 26 | 26.7 | 11,335–22,266 s | 0.85 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 0.972 | 21.3 | 18.3 | +4.5 / −1.2 | 24, 29, 26 | 26.3 | 23,587–37,269 s | 0.86 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | 0.971 | 19.3 | 12.0 | +5.0 / −1.3 | 27, 27, 26 | 26.7 | 14,162–25,062 s | 0.84 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 0.970 | 22.3 | 21.4 | +4.8 / −2.8 | 24, 26, 25 | 25.0 | 28,028–34,307 s | 0.83 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 0.946 | 17.3 | 9.5 | +3.8 / −4.5 | 22, 20, 25 | 22.3 | 10,692–14,201 s | 0.72 |
| DeepSeek alone | 0.940 | 19.0 | 6.6 | ref | 28 (pieced together), 23, 23 | 24.7 | 7,536–10,754 s | 0.79 |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | 0.935 | 18.7 | 9.0 | +2.7 / −2.0 | 26, 23, 22 | 23.7 | 9,774–15,162 s | 0.76 |
| Q8+rDS | 0.909 | 13.7 | 7.3 | +3.3 / −4.3 | 22, 22, 22 | 22.0 | 7,360–11,792 s | 0.67 |
| PAIR-KT | 0.901 | 14.0 | 7.6 | +2.7 / −3.7 | 20, 23, 23 | 22.0 | 7,819–13,198 s | 0.68 |
| DS>Q8 tdd | 0.894 | 18.3 | 12.9 | +3.2 / −4.5 | 20, 22, 23 | 21.7 | 16,340–17,028 s | 0.71 |
| PAIR (llama.cpp) | 0.864 | 14 | 6.0 | +3.5 / −5.5 | 21, seed 2: 13 of the first 15 | 21 | 7,598 s | 0.65 |
| nav Qwen3.8 + driver Qwen3.8 | 0.848 | 12.0 | 5.5 | +3.0 / −7.0 | 16, 22, 19 | 19.0 | 5,962–6,698 s | 0.58 |
| Q8+rQ6 | 0.838 | 11.0 | 4.6 | +1.8 / −7.2 | 21, 20, 12 | 17.7 | 4,570–5,546 s | 0.54 |
| Qwen3.8 alone | 0.830 | 10.0 | 2.5 | +1.5 / −7.8 | 18, 17, 15 | 16.7 | 2,366–2,763 s | 0.51 |
| Q6+rDS | 0.821 | 11 | 8.8 | +2.5 / −7.5 | 18 | 18 | 9,545 s | 0.55 |
| nav Qwen3.6 MTP + driver Qwen3.8 | 0.809 | 10.7 | 4.7 | +0.8 / −9.2 | 16, 17, 11 | 14.7 | 3,602–4,743 s (Qwen3.6 on the 3090 Ti) | 0.46 |
| Q6+rQ8 | 0.791 | 10.7 | 2.6 | +1.2 / −8.5 | 16, 15, 16 | 15.7 | 2,069–2,860 s | 0.49 |
| nav Qwen3.8 + driver Qwen3.6 MTP | 0.768 | 8 | 3.8 | +1.0 / −11.0 | 13 | 13 | 3,000 s | 0.40 |
| nav DeepSeek (KT) + driver Qwen3.6 MTP | 0.762 | 7 | 7.1 | +2.5 / −11.5 | 14 | 14 | 5,954 s | 0.41 |
| Qwen3.6 MTP alone | 0.696 | 7.0 | 1.5 | +0.7 / −14.0 | 12, 8, 9 | 9.7 | 812–914 s | 0.31 |
| nav Qwen3.6 MTP + driver Qwen3.6 MTP | 0.667 | 4 | 5.0 | +0.0 / −14.0 | 9 | 9 | 2,704 s | 0.26 |
