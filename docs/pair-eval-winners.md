# Pair programming eval: winners and headline

Files: [pair-eval-winners.md](pair-eval-winners.md) (winners + headline, short), [pair-eval-report.md](pair-eval-report.md) (setup, generated tables, literature, gaps), [pair-eval-findings.md](pair-eval-findings.md) (per-run findings), [pair-eval-literature.md](pair-eval-literature.md) (literature against our findings).

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
- net [95% CI], quality vs best: paired bootstrap over the 29 tasks (10,000 resamples, seeds averaged per task first),
  in tasks: net = solved tasks gained minus lost against DeepSeek alone, quality vs best = hidden-test share summed
  over tasks against the top setup. * = the interval excludes 0, i.e. a real difference at 95%. DeepSeek alone
  has per-task data only for seeds 2 and 3 (23 each, the pieced-together 28 has none), so gains over it are on
  the generous side.
- Rescored (Nov 26): all numbers use the hidden tests with the 4 checks added after the audit (each stored solution
  re-run; a task that now fails at attempt 1 stays failed, as the run never made attempt 2). The pre-audit table is in
  git history (commit 6efa5f1).
- pass^3 = tasks solved (pass@2) in all three seeds: reliability, not luck (τ-bench); setups with fewer than 3
  complete seeds show —.
- tg = single-stream decode of the writer, tok/s. Init = server launch to ready, cold after a reboot, measured on the Nov 22
23:25 restart (all servers start in parallel, so a setup waits for its slowest model).

| # | setup | practice | writer | quality | pass@2 | n | pass@1 | min per solved task | vs DeepSeek alone: tasks + / −; net [95% CI] | pass^3 | quality vs best, tasks [95% CI] | writer tg | init | hardware | old score |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | DeepSeek + Qwen3.8 review | solo + reviewer | DeepSeek KT | 0.988 | 27.0 (29, 26, 26) | 3 | 19.7 | 9.5 | +4.3 / −0.3; net +4.0 [+1.3, +7.0] * | 23 | best | 18–20 | 8.3 min | + 1× 4090 | 0.86 |
| 2 | DeepSeek + DeepSeek review | solo + reviewer | DeepSeek KT | 0.973 | 26.3 (27, 27, 25) | 3 | 21.0 | 10.1 | +4.5 / −1.2; net +3.3 [-0.0, +6.8] | 23 | -0.4 [-1.2, +0.2] | 18–20 | 8.3 min | 1× 4090 + ~330 GB RAM | 0.85 |
| 3 | nav DS + driver DS | pair | DeepSeek KT | 0.971 | 25.7 (26, 26, 25) | 3 | 19.7 | 10.1 | +4.7 / −2.0; net +2.7 [-1.2, +6.5] | 21 | -0.5 [-1.1, -0.0] * | 18–20 | 8.3 min | 1× 4090 + ~330 GB RAM | 0.82 |
| 4 | nav Qwen3.8 + driver DS | pair | DeepSeek KT | 0.968 | 26.0 (25, 28, 25) | 3 | 19.7 | 9.8 | +4.7 / −1.7; net +3.0 [-0.3, +6.5] | 22 | -0.6 [-1.3, -0.0] * | 18–20 | 8.3 min | + 1× 4090 | 0.83 |
| 5 | nav Qwen3.8 + driver DS (tdd) | pair, tests first | DeepSeek KT | 0.966 | 26.0 (24, 28, 26) | 3 | 21.3 | 18.6 | +4.5 / −1.5; net +3.0 [-0.3, +6.7] | 22 | -0.7 [-1.6, +0.1] | 18–20 | 8.3 min | + 1× 4090 | 0.85 |
| 6 | nav DS + driver DS (tdd) | pair, tests first | DeepSeek KT | 0.965 | 24.0 (23, 24, 25) | 3 | 21.3 | 22.3 | +4.5 / −3.5; net +1.0 [-3.2, +5.2] | 18 | -0.7 [-1.3, -0.1] * | 18–20 | 8.3 min | 1× 4090 + RAM | 0.80 |
| 7 | nav DS + driver DS (keep-unrevised) | pair, keep the pre-review file | DeepSeek KT | 0.965 | 25.3 (25, 26, 25) | 3 | 18.7 | 12.7 | +4.5 / −2.2; net +2.3 [-1.5, +6.2] | 22 | -0.7 [-1.5, -0.1] * | 18–20 | 8.3 min | 1× 4090 + ~330 GB RAM | 0.80 |
| 8 | nav Qwen3.8 + driver Qwen3.8 (tdd) | pair, tests first | Qwen3.8 | 0.940 | 21.7 (21, 19, 25) | 3 | 17.0 | 9.8 | +3.3 / −4.7; net -1.3 [-5.5, +3.0] | 15 | -1.4 [-2.3, -0.6] * | 31–35 | 53 s | 1× 4090 | 0.70 |
| 9 | DeepSeek alone | solo | DeepSeek | 0.938 | 24.7 (28, 23, 23) | 3 | 19.0 | 6.6 | ref | — | -1.5 [-3.4, -0.1] * | 14.1–14.5 (llama.cpp) | ~5 min + warm-up | 2 GPUs + RAM | 0.79 |
| 10 | nav Qwen3.6 MTP + driver DS | pair | DeepSeek KT | 0.930 | 23.0 (26, 21, 22) | 3 | 18.0 | 9.3 | +2.5 / −2.5; net -0.0 [-2.7, +2.8] | 16 | -1.7 [-3.1, -0.6] * | 18–20 | 8.3 min | + 1× 4090 | 0.74 |
| 11 | Qwen3.8 + DeepSeek review | solo + reviewer | Qwen3.8 | 0.902 | 20.3 (21, 21, 19) | 3 | 12.3 | 7.9 | +3.3 / −6.0; net -2.7 [-7.2, +1.8] | 14 | -2.5 [-4.0, -1.2] * | 31–35 | 53 s (+ DS) | 3 GPUs + RAM | 0.62 |
| 12 | nav DS (KT) + driver Qwen3.8 | pair | Qwen3.8 | 0.897 | 21.0 (20, 22, 21) | 3 | 13.0 | 8.0 | +2.5 / −4.5; net -2.0 [-5.3, +1.7] | 12 | -2.7 [-3.9, -1.5] * | 31–35 | 8.3 min | 2× 4090 + RAM | 0.64 |
| 13 | nav DS (KT) + driver Qwen3.8 (tdd) | pair, tests first | Qwen3.8 | 0.890 | 21.0 (19, 21, 23) | 3 | 17.7 | 13.3 | +2.8 / −4.8; net -2.0 [-6.5, +2.5] | 15 | -2.8 [-4.6, -1.3] * | 31–35 | 8.3 min | 2× 4090 + RAM | 0.69 |
| 14 | nav Qwen3.8 + driver Qwen3.8 | pair | Qwen3.8 | 0.843 | 18.3 (16, 21, 18) | 3 | 11.7 | 5.7 | +2.8 / −7.5; net -4.7 [-9.0, +0.2] | 10 | -4.2 [-6.0, -2.6] * | 31–35 | 53 s | 1× 4090 | 0.56 |
| 15 | Qwen3.8 + Qwen3.6 MTP review | solo + reviewer | Qwen3.8 | 0.831 | 16.7 (19, 19, 12) | 3 | 10.3 | 4.9 | +1.8 / −8.2; net -6.3 [-10.2, -2.3] * | 7 | -4.6 [-6.2, -3.0] * | 31–35 | 53 s | 2× 4090 | 0.51 |
| 16 | Qwen3.8 alone | solo | Qwen3.8 | 0.825 | 15.7 (17, 16, 14) | 3 | 9.0 | 2.7 | +1.5 / −8.8; net -7.3 [-11.3, -3.2] * | 7 | -4.7 [-6.8, -2.9] * | 31–35 | 53 s | 1× 4090 | 0.47 |
| 17 | Qwen3.6 MTP + DeepSeek review | solo + reviewer | Qwen3.6 MTP | 0.812 | 16 | 1 | 10 | 9.9 | +1.5 / −8.5; net -7.0 [-12.0, -2.0] * | — | -5.1 [-8.2, -2.4] * | 205–215 | 8.3 min | 2× 4090 + RAM | 0.49 |
| 18 | nav Qwen3.6 MTP + driver Qwen3.8 | pair | Qwen3.8 | 0.803 | 14.0 (16, 16, 10) | 3 | 10.3 | 4.9 | +0.8 / −9.8; net -9.0 [-12.5, -5.3] * | 7 | -5.4 [-7.5, -3.4] * | 31–35 | 53 s | 2× 4090 | 0.44 |
| 19 | Qwen3.6 MTP + Qwen3.8 review | solo + reviewer | Qwen3.6 MTP | 0.783 | 14.0 (14, 13, 15) | 3 | 9.7 | 3.0 | +0.5 / −9.5; net -9.0 [-13.0, -5.2] * | 8 | -6.0 [-8.1, -3.9] * | 205–215 | 53 s | 2× 4090 | 0.44 |
| 20 | nav DS + driver Qwen3.6 MTP | pair | Qwen3.6 MTP | 0.757 | 14 | 1 | 7 | 7.1 | +2.5 / −11.5; net -9.0 [-15.0, -3.0] * | — | -6.7 [-10.5, -3.5] * | 205–215 | 8.3 min | 2× 4090 + RAM | 0.41 |
| 21 | Qwen3.6 MTP alone | solo | Qwen3.6 MTP | 0.690 | 9.3 (11, 8, 9) | 3 | 6.7 | 1.5 | +0.7 / −14.3; net -13.7 [-17.3, -9.5] * | 3 | -8.6 [-11.0, -6.3] * | 205–215 | 38 s | 1× 4090 | 0.29 |

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
  Rescored (Nov 26, hidden tests strengthened on 4 tasks after the audit, see pair-eval-report.md): every setup
  except DeepSeek alone loses 0-3 tasks per seed. With intervals, only DS + Qwen3.8 review is clearly ahead of
  DeepSeek alone on solved tasks (net +4.0 [+1.3, +7.0]); DS + DS review is borderline (+3.3, lower end -0.0), the
  pairs and tdd are not (lower ends -0.3 to -3.2). On quality DS + Qwen3.8 review now also separates from the DeepSeek
  pairs, tdd DS>DS and keep-unrevised (vs best intervals below 0), only DS + DS review and Q8>DS tdd stay level with it.
  DeepSeek alone's seed 1 (28, pieced together) could not be rescored, so its mean stays slightly high.
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

## Joined tasks (12 composite tasks, seed 1; interim, state 2026-11-27 00:30)

Details: [pair-eval-report.md](pair-eval-report.md), sections "Joined tasks, seed 1" and "Joined tasks 2, seed 1".
DS + DeepSeek review still runs on both sets (joined2: 0 solved of the 3 done).

| setup | pass@1 of 12 | pass@2 of 12 | quality | min per solved task |
|---|---|---|---|---|
| nav DS + driver DS | 3 | **8** | **0.973** | 67 |
| DeepSeek + Qwen3.8 review | 3 | 7 | 0.960 | 70 |
| DeepSeek alone | 1 | 4 | 0.902 | 59 |

- On the 29 small tasks any second look adds the same 2–2.6 tasks and DS + Qwen3.8 review ranks first. On the 12
  joined tasks both second looks again nearly double DeepSeek alone (7–8 vs 4 solved, quality +0.06–0.07); the DS>DS
  pair is one task ahead of review (8 vs 7), within one seed's noise, and they solve different tasks (review alone
  solved sh_net, the pair alone py_splitter and sh_files; on the old set both solve the same 3).
- Default coder stays DS + Qwen3.8 review (user decision A): level with the pair on joined tasks within noise, best on
  the small ones, and its reviewer runs on its own GPU, while the pair takes both KT slots.

## Headline (sort: quality, then pass@1; generated)

| setup | quality | pass@1 mean | min per solved task | vs DeepSeek alone (tasks + / −) | pass^3 | quality vs DeepSeek alone, tasks [95% CI] | quality vs best, tasks [95% CI] | pass@2 per seed | pass@2 mean | time per seed | old score |
|---|---|---|---|---|---|---|---|---|---|---|---|
| DS+rQ8 | 0.988 | 19.7 | 9.5 | +4.3 / −0.3; net +4.0 [+1.3, +7.0] * | 23 | +1.5 [+0.1, +3.4] * | best | 29, 26, 26 | 27.0 | 12,900–17,712 s | 0.86 |
| DS+rDS | 0.973 | 21.0 | 10.1 | +4.5 / −1.2; net +3.3 [-0.0, +6.8] | 23 | +1.0 [-0.2, +2.5] | -0.4 [-1.2, +0.2] | 27, 27, 25 | 26.3 | 13,254–20,491 s | 0.85 |
| nav DeepSeek (KT) + driver DeepSeek (KT) | 0.971 | 19.7 | 10.1 | +4.7 / −2.0; net +2.7 [-1.2, +6.5] | 21 | +1.0 [-0.6, +2.9] | -0.5 [-1.1, -0.0] * | 26, 26, 25 | 25.7 | 13,362–19,648 s | 0.82 |
| nav Qwen3.8 + driver DeepSeek (KT) | 0.968 | 19.7 | 9.8 | +4.7 / −1.7; net +3.0 [-0.3, +6.5] | 22 | +0.9 [-0.5, +2.4] | -0.6 [-1.3, -0.0] * | 25, 28, 25 | 26.0 | 11,335–22,266 s | 0.83 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 0.966 | 21.3 | 18.6 | +4.5 / −1.5; net +3.0 [-0.3, +6.7] | 22 | +0.8 [-0.8, +2.9] | -0.7 [-1.6, +0.1] | 24, 28, 26 | 26.0 | 23,587–37,269 s | 0.85 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 0.965 | 21.3 | 22.3 | +4.5 / −3.5; net +1.0 [-3.2, +5.2] | 18 | +0.8 [-0.6, +2.7] | -0.7 [-1.3, -0.1] * | 23, 24, 25 | 24.0 | 28,028–34,307 s | 0.80 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | 0.965 | 18.7 | 12.7 | +4.5 / −2.2; net +2.3 [-1.5, +6.2] | 22 | +0.8 [-0.7, +2.8] | -0.7 [-1.5, -0.1] * | 25, 26, 25 | 25.3 | 14,162–25,062 s | 0.80 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 0.940 | 17.0 | 9.8 | +3.3 / −4.7; net -1.3 [-5.5, +3.0] | 15 | +0.1 [-1.5, +2.1] | -1.4 [-2.3, -0.6] * | 21, 19, 25 | 21.7 | 10,692–14,201 s | 0.70 |
| DeepSeek alone | 0.938 | 19.0 | 6.6 | ref | — | ref | -1.5 [-3.4, -0.1] * | 28 (pieced together), 23, 23 | 24.7 | 7,536–10,754 s | 0.79 |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | 0.930 | 18.0 | 9.3 | +2.5 / −2.5; net -0.0 [-2.7, +2.8] | 16 | -0.2 [-1.2, +0.8] | -1.7 [-3.1, -0.6] * | 26, 21, 22 | 23.0 | 9,774–15,162 s | 0.74 |
| Q8+rDS | 0.902 | 12.3 | 7.9 | +3.3 / −6.0; net -2.7 [-7.2, +1.8] | 14 | -1.0 [-3.1, +1.4] | -2.5 [-4.0, -1.2] * | 21, 21, 19 | 20.3 | 7,360–11,792 s | 0.62 |
| PAIR-KT | 0.897 | 13.0 | 8.0 | +2.5 / −4.5; net -2.0 [-5.3, +1.7] | 12 | -1.2 [-3.0, +1.1] | -2.7 [-3.9, -1.5] * | 20, 22, 21 | 21.0 | 7,819–13,198 s | 0.64 |
| DS>Q8 tdd | 0.890 | 17.7 | 13.3 | +2.8 / −4.8; net -2.0 [-6.5, +2.5] | 15 | -1.4 [-3.6, +1.2] | -2.8 [-4.6, -1.3] * | 19, 21, 23 | 21.0 | 16,340–17,028 s | 0.69 |
| PAIR (llama.cpp) | 0.864 | 14 | 6.0 | +3.5 / −5.5; net -2.0 [-7.0, +3.0] | — | -2.1 [-5.7, +1.2] | -3.6 [-6.8, -0.9] * | 21, seed 2: 13 of the first 15 | 21 | 7,598 s | 0.65 |
| nav Qwen3.8 + driver Qwen3.8 | 0.843 | 11.7 | 5.7 | +2.8 / −7.5; net -4.7 [-9.0, +0.2] | 10 | -2.8 [-5.2, +0.0] | -4.2 [-6.0, -2.6] * | 16, 21, 18 | 18.3 | 5,962–6,698 s | 0.56 |
| Q8+rQ6 | 0.831 | 10.3 | 4.9 | +1.8 / −8.2; net -6.3 [-10.2, -2.3] * | 7 | -3.1 [-5.2, -0.6] * | -4.6 [-6.2, -3.0] * | 19, 19, 12 | 16.7 | 4,570–5,546 s | 0.51 |
| Qwen3.8 alone | 0.825 | 9.0 | 2.7 | +1.5 / −8.8; net -7.3 [-11.3, -3.2] * | 7 | -3.3 [-5.4, -1.2] * | -4.7 [-6.8, -2.9] * | 17, 16, 14 | 15.7 | 2,366–2,763 s | 0.47 |
| Q6+rDS | 0.812 | 10 | 9.9 | +1.5 / −8.5; net -7.0 [-12.0, -2.0] * | — | -3.6 [-7.1, -0.4] * | -5.1 [-8.2, -2.4] * | 16 | 16 | 9,545 s | 0.49 |
| nav Qwen3.6 MTP + driver Qwen3.8 | 0.803 | 10.3 | 4.9 | +0.8 / −9.8; net -9.0 [-12.5, -5.3] * | 7 | -3.9 [-6.1, -1.8] * | -5.4 [-7.5, -3.4] * | 16, 16, 10 | 14.0 | 3,602–4,743 s (Qwen3.6 on the 3090 Ti) | 0.44 |
| Q6+rQ8 | 0.783 | 9.7 | 3.0 | +0.5 / −9.5; net -9.0 [-13.0, -5.2] * | 8 | -4.5 [-7.0, -1.6] * | -6.0 [-8.1, -3.9] * | 14, 13, 15 | 14.0 | 2,069–2,860 s | 0.44 |
| nav DeepSeek (KT) + driver Qwen3.6 MTP | 0.757 | 7 | 7.1 | +2.5 / −11.5; net -9.0 [-15.0, -3.0] * | — | -5.3 [-9.5, -1.3] * | -6.7 [-10.5, -3.5] * | 14 | 14 | 5,954 s | 0.41 |
| nav Qwen3.8 + driver Qwen3.6 MTP | 0.756 | 6 | 4.5 | +0.5 / −12.5; net -12.0 [-17.0, -7.5] * | — | -5.3 [-8.6, -2.1] * | -6.7 [-9.8, -4.0] * | 11 | 11 | 3,000 s | 0.33 |
| Qwen3.6 MTP alone | 0.690 | 6.7 | 1.5 | +0.7 / −14.3; net -13.7 [-17.3, -9.5] * | 3 | -7.2 [-10.1, -4.0] * | -8.6 [-11.0, -6.3] * | 11, 8, 9 | 9.3 | 812–914 s | 0.29 |
| nav Qwen3.6 MTP + driver Qwen3.6 MTP | 0.660 | 4 | 5.0 | +0.0 / −14.0; net -14.0 [-18.5, -9.5] * | — | -8.0 [-11.7, -4.7] * | -9.5 [-13.0, -6.3] * | 9 | 9 | 2,704 s | 0.26 |
