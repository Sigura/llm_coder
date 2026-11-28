# Pair programming eval: findings per run

Files: [pair-eval-winners.md](pair-eval-winners.md) (winners + headline, short), [pair-eval-report.md](pair-eval-report.md) (setup, generated tables, literature, gaps), [pair-eval-findings.md](pair-eval-findings.md) (per-run findings).

- Pairing lifts Qwen3.8 by ~3–4 tasks at pass@2 (21 vs 18 on seed 1; 16.7 mean alone), the same as a reviewer alone
  (21–22). The plan step adds nothing measurable on top of the review in this one seed.
- The pair does not reach DeepSeek alone (24.7 mean, 23 at worst) and takes the same time (~7,600 s). On this eval,
  DeepSeek writing the code itself is better than DeepSeek navigating.
- The Qwen3.6 MTP reviewer gives the same gain as DeepSeek in 60% of the time (4,570 s vs 7,360–7,600 s).
- The pair solved tasks Qwen3.8 never solved alone: `py_apply_patch` (0/3 solo; pair 2 and 1), `py_e_flatten` (pair on
  llama.cpp). It lost tasks Qwen3.8 solves alone: `py_ini_interp` (3/3 solo, 0 in both pairs), `py_fix_merge_intervals`
  (2/3 solo, 0 in both pairs), `kt_fix_money` (pair on llama.cpp).
- 3–4 pair attempts per run failed as "no fenced code block": the driver's reply after a review turn had no code.
  llama.cpp: `kt_fix_money` #1, `py_expr_eval` #1, `py_shell_split` #2; KT: `py_ini_interp` #1, `py_semver_range` #1 and #2,
  `sh_csv_col` #2. That looks like a protocol fault in the review/revise turn, not a model limit, and costs ~1–2 tasks.
- PAIR vs PAIR-KT (same pair, navigator engine swapped): 21 vs 20, 25.1 vs 24.7 tests@2, within seed noise; per-task
  scores differ on 15 tasks and pass/fail flips on 7, so a single seed cannot rank them.
- Navigator tokens are ~19% of the total (28k of 153k); the driver writes ~124k tokens, 1.5× Qwen3.8 alone
  (~82k), because of revisions.

- Qwen3.6 MTP navigating Qwen3.8 (seed 1): 16 of 29, no better than Qwen3.8 alone (16.7 mean) at ~2x its time,
  while Qwen3.6 MTP as a reviewer only lifted Qwen3.8 to 21. A weak planner's plan seems to hurt more than its review
  helps (one seed).
- Qwen3.8 navigating Qwen3.6 MTP (seed 1): 13 of 29, pass@1 8, in 3,000 s, against 9.7 mean (12 at best) for Qwen3.6 MTP
  alone. A stronger navigator lifts the weak driver a little, but stays below Qwen3.8 alone (16.7) at ~1.2x its time. The
  driver wrote 190k tokens, 2x Qwen3.6 alone (~100k).
- DeepSeek navigating DeepSeek (KT, seed 1): 26 of 29, pass@1 20, tests@2 27.99. That's the best single seed apart from the
  pieced-together DeepSeek seed 1 (28), and above DeepSeek alone on seeds 2 and 3 (23 each, tests@2 27.2–27.3). It solved
  `sh_retry` and `py_e_duration` (0/2 alone) but lost `sh_access_log`, `sh_wordfreq` and `py_semver_range` (2/2 alone). No
  "no fenced code block" failures. Time 13,748 s (1.3–1.8x alone), while sharing the CPU with the Qwen stream and resuming
  across two host hangs. Seeds 2 and 3 decide whether +3 over DeepSeek alone holds.
- Qwen3.8 navigating Qwen3.8 (seed 1): 16 of 29, pass@1 10, tests@2 24.19, in 6,698 s. Same pass@2 as Qwen3.8 alone (16.7
  mean, seed 1: 18) at ~2.7x the time and 2.4x the tokens (200k). Self-pairing a weak model adds nothing; one "no fenced
  code block" fault (`kt_tokens` #1). Gains for Qwen3.8 so far come only from a different reviewer (Q8+rDS 22, Q8+rQ6 21).
- Qwen3.6 MTP navigating Qwen3.6 MTP (seed 1): 9 of 29, pass@1 4, tests@2 19.33, in 2,704 s. Same as Qwen3.6 MTP alone
  (9.7 mean) at ~3x the time and 2x the tokens (211k). 4 of 58 attempts failed as "no fenced code block" (`py_cron_next`
  #1 #2, `py_ini_interp` #1 #2), so `--keep-unrevised` could recover up to 2 tasks. As with Qwen3.8, self-pairing adds nothing.
- DeepSeek navigating Qwen3.6 MTP (KT, seed 1): 14 of 29, pass@1 7, tests@2 22.10, in 5,954 s. The best Qwen3.6 MTP
  driver so far: +4.3 over Qwen3.6 alone (9.7 mean) and +1 over Qwen3.8 navigating it (13), at ~2.2x the time of the
  Qwen3.8 navigator. Still below Qwen3.8 alone (16.7). 6 of 58 attempts failed as "no fenced code block", 5 of them on bash
  first attempts (`sh_access_log`, `sh_e_ext_count`, `sh_e_lowercase`, `sh_e_replace`, `sh_env_export` #1 #2), so
  `--keep-unrevised` matters most for this driver. The driver wrote 188k tokens.
- Qwen3.6 MTP navigating Qwen3.8, seed 2: 17 of 29, pass@1 12, tests@2 24.64, in 3,603 s (seed 1: 16, 23.46, 4,743 s).
  Mean 16.5 over two seeds, the same as Qwen3.8 alone (16.7). 3 "no fenced code block" faults (`kt_tokens`,
  `py_expr_eval`, `py_shell_split`, all #1). The Q6 navigator still adds nothing to Q8.
- Qwen3.6 MTP navigating DeepSeek (KT, seed 1): 26 of 29, pass@1 20, tests@2 27.66, in 9,774 s. It ties DeepSeek
  navigating DeepSeek (26, pass@1 20, tests@2 27.99) at 71% of its time (13,748 s): the fast MoE navigator costs no tasks
  when DeepSeek drives. Failed `py_ini_interp`, `sh_retry`, `sh_rotate` (DS+DS failed `py_semver_range`,
  `sh_access_log`, `sh_wordfreq`). No "no fenced code block" faults. Navigator 29.5k tokens, driver 114k. The driver is
  what matters: every DeepSeek-driven pair so far is at 26, every Qwen-driven one at 9–20. Seeds 2, 3 re-queued.
- Qwen3.8 navigating Qwen3.8 with `--tests-first` (seed 1): 22 of 29, pass@1 14, tests@2 27.15, in 10,692 s, against
  16, pass@1 10, tests@2 24.19 in 6,698 s without it (Qwen3.8 alone 16.7 mean). It matches Qwen3.8 writing with
  DeepSeek reviewing (22) without DeepSeek, at 1.6x the plain pair's time. The navigator's tests pass the reference on
  12 of 29 tasks only, and the gain does not come from them: pass@2 is 9/12 with valid tests and 13/17 with wrong
  ones, so writing and running any tests first seems to be what helps. Failed `py_apply_patch`, `py_e_duration`,
  `py_e_flatten`, `py_e_logstats`, `py_semver_range`, `sh_csv_col`, `sh_wordfreq`. Restarts after hang 10 and two GPU
  moves (01:59, 02:16) redid the tasks in progress, which adds a little to the time. One seed.
- Qwen3.8 navigating DeepSeek (KT, seed 1): 26 of 29, pass@1 18, tests@2 27.83, in 12,255 s. The third DeepSeek-driven
  pair at 26 (DS+DS 26 in 13,748 s, Q6→DS 26 in 9,774 s): any navigator works when DeepSeek drives, and the Qwen3.6
  MTP navigator is the fastest. Failed `sh_access_log`, `sh_e_replace`, `sh_env_export` (bash 6/9, Python 16/16,
  Kotlin 4/4). 1 "no fenced code block" fault. Navigator 22.9k tokens, driver 101k. Its time includes sharing KT's two
  slots with the b2 queue's DeepSeek runs and the restart after hang 10.
- OpenCode sh domain (`eval_opencode.py`, one headless DeepSeek KT session building every sh task in turn; results in
  `LLM_ROOT/results/opencode-eval/opencode-sh-ds-s1`): stopped by the user after 4 of 9 builds, none passing.
  `sh_access_log` 0.80 of its tests in 1,481 s (41 steps), `sh_csv_col` and `sh_e_ext_count` hit the 2,700 s timeout
  (36 and 102 steps, 100 of them bash debug runs; context up to 84k tokens), `sh_e_lowercase` 0.71 in 379 s, which
  passed fully in a fresh session during the 1-task check. In one long session DeepSeek loops on debugging and gets
  worse from task to task; the review step never ran.
- DeepSeek (KT) navigating Qwen3.8 with `--tests-first` (seed 1): 20 of 29, pass@1 17, tests@2 25.01, in 16,813 s,
  against 20 (KT, 7,819 s) and 21 (llama.cpp) without it. With DeepSeek navigating, tests-first adds nothing for
  Qwen3.8 and doubles the time, unlike Qwen3.8 navigating itself (16 to 22). DeepSeek's tests pass the reference on only
  10 of 29 tasks; with valid tests pass@2 is 10/10, with wrong ones 10/19, so wrong navigator tests may cost tasks here
  (or valid ones mark easier tasks). Failed `py_e_duration`, `py_grid_route`, `py_ini_interp`, `py_semver_range`, `py_shell_split`, `sh_csv_col`,
  `sh_e_replace`, `sh_env_export`, `sh_rotate` (bash 5/9, Python 11/16, Kotlin 4/4). Navigator 57.3k tokens, driver
  201k. Its time includes sharing KT's two slots with the ds2 queue. One seed.
- DeepSeek navigating DeepSeek (KT) with `--keep-unrevised`, seed 1: 27 of 29, pass@1 19, tests@2 28.4, against
  plain DS+DS seed 1 26, pass@1 20, tests@2 27.99. Gained `py_semver_range` and `sh_wordfreq`, lost `py_e_duration`;
  failed `py_e_duration`, `sh_access_log` (bash 8/9, Python 15/16, Kotlin 4/4). Neither run had a "no fenced code
  block" fault, so keeping the unrevised file had nothing to recover here: +1 is within seed noise. 25,062 s (1.8x
  plain), not comparable: KT's hot lend was stopped from 02:42 to 12:57 and again 13:25-14:03 (restarts at 12:57 and
  14:03), and it shared KT's two slots with the tdd run. One seed.
- DeepSeek (KT) navigating DeepSeek (KT) with `--tests-first` (seed 1): 24 of 29, pass@1 22, tests@2 28.03, against
  plain DS+DS seed 1 26, pass@1 20, tests@2 27.99. Tests-first lifts pass@1 by 2 but loses 2 at pass@2: gained
  `py_semver_range`, `sh_access_log`, `sh_wordfreq`, lost `py_e_fix_paginate`, `py_ini_interp`, `py_shell_split`,
  `sh_e_lowercase`, `sh_env_export` (bash 7/9, Python 13/16, Kotlin 4/4). DeepSeek's tests pass the reference on only
  8 of 29 tasks (first try 8/36 files, after fixes 15/36, 52 fix turns); with valid tests pass@2 is 8/8, with wrong ones
  16/21, so as with the Qwen3.8 driver the wrong tests probably cost tasks. No "no fenced code block" fault. Navigator
  57.4k tokens, driver 183k (plain 24.4k / 127k). 34,307 s (2.5x plain), not comparable: it shared KT's two slots
  with the keep and b3 runs, KT's hot lend was stopped 02:42-12:57 and 13:25-14:03, and it was paused 17:05-17:29
  for the placement-B restart. One seed.
- Qwen3.6 MTP navigating DeepSeek (KT), seed 2: 23 of 29, pass@1 20, tests@2 27.90 (seed 1: 26, pass@1 20, tests@2
  27.66). Mean of 2 seeds 24.5 pass@2, 20.0 pass@1, level with DeepSeek alone (24.7 / 19.0 over 3 seeds): the seed-1
  lead over solo was seed noise. Failed `py_fix_merge_intervals`, `py_semver_range`, `py_shell_split`,
  `sh_access_log`, `sh_csv_col`, `sh_retry` (bash 6/9, Python 13/16, Kotlin 4/4); only `sh_retry` failed in both seeds.
  No "no fenced code block" fault. Navigator 27.5k tokens, driver 110k. 15,162 s, not comparable with seed 1's 9,774 s:
  it shared KT's two slots with the tdd and DS+DS s2 runs and was paused 17:05-17:29 and 19:34-19:43 for the
  placement A/B restarts.
- Qwen3.6 MTP navigating Qwen3.8, seed 3: 11 of 29, pass@1 9, tests@2 22.33, in 4,109 s (seeds 1, 2: 16 and 17).
  Mean of 3 seeds 14.7 pass@2, 10.7 pass@1, below Qwen3.8 alone (16.7): the Q6 navigator does not help Q8 and may
  hurt it. Six "no fenced code block" faults, all on attempt #1 (`kt_tokens`, `py_e_flatten`, `py_expr_eval`,
  `py_ini_interp`, `py_semver_range`, `sh_csv_col`), twice seed 2's count; Python 5/16 (seeds 1, 2 solved
  `py_async_limit` and `py_cron_next`, lost here). Driver on the second Qwen3.8 (:8087, GPU 1), resumed at 28/29
  after the 22:30 power drop.
- DeepSeek navigating DeepSeek (KT), seed 2: **29 of 29**, pass@1 20, tests@2 29.0, in 19,648 s (seed 1: 26, pass@1 20,
  tests@2 27.99, 13,748 s). Mean of 2 seeds 27.5 pass@2, 20.0 pass@1, against DeepSeek alone 24.7 / 19.0 (3 seeds,
  23–28): the first pair clearly above DeepSeek solo; the gain is all on attempt 2 (pass@1 equal), i.e. the review /
  revise turn. Seed 1's failures `py_semver_range`, `sh_access_log`, `sh_wordfreq` all passed here. No "no fenced code
  block" fault. Tokens the same as seed 1 (nav 25.3k, driver 125k); the longer time is KT slot sharing with b3 and q runs
  plus the 22:30 power drop resume.
- Qwen3.8 navigating Qwen3.8, seed 2: 22 of 29, pass@1 13, tests@2 25.84, in 6,010 s (seed 1: 16, pass@1 10, 24.19,
  6,698 s). Mean of 2 seeds 19.0 pass@2, 11.5 pass@1, vs Qwen3.8 alone 16.7 / 10.0: +2.3, but the seeds differ by 6
  and pass/fail flips on 12 tasks (seed 2 gained `kt_fix_money`, `kt_lru`, `kt_tokens`, `py_async_limit`,
  `py_cron_next`, `py_e_flatten`, `py_e_logstats`, `sh_access_log`, `sh_e_replace`; lost `kt_render`, `py_expr_eval`,
  `py_fix_merge_intervals`). Seed 3 decides; for now self-pairing Qwen3.8 is at best
  a small gain at 2.4x the time. One "no fenced code block" fault (`py_ini_interp` #1, still passed on #2).
- Qwen3.6 MTP navigating DeepSeek (KT), seed 3: 22 of 29, pass@1 16, tests@2 25.75, in 13,560 s (seeds 1, 2: 26 and
  23). Mean of 3 seeds 23.7 pass@2, 18.7 pass@1, against DeepSeek alone 24.7 / 19.0 and DeepSeek navigating DeepSeek
  27.5 / 20.0: a Qwen3.6 navigator gives DeepSeek nothing. Failed `py_apply_patch`, `py_e_duration`, `py_e_flatten`,
  `py_ini_interp`, `sh_csv_col`, `sh_env_export`, `sh_retry` (Python 12/16, bash 6/9, Kotlin 4/4); `sh_retry` failed in
  all 3 seeds. One "no fenced code block" fault (`sh_access_log` #1, passed on #2). Driver tokens 96k (110–114k before).
  Qwen3.6 MTP (:8085, GPU 3) stopped after this run; nothing queued uses it.
- Qwen3.8 navigating Qwen3.8, seed 3: 19 of 29, pass@1 13, tests@2 23.78, in 5,962 s (seeds 1, 2: 16 and 22). Mean of
  3 seeds 19.0 pass@2, 12.0 pass@1, against Qwen3.8 alone 16.7 / 10.0 (15–18): +2.3 / +2.0, every pair seed at or above
  the solo low. A small real gain for self-pairing, below a different reviewer (Q8+rDS 22, Q8+rQ6 21, one seed each)
  at ~2.3x Qwen3.8's time. 4 "no fenced code block" faults (`kt_render` #1, `py_grid_route` #1, `py_ini_interp` #1
  and #2); `py_apply_patch`, `py_shell_split`, `sh_env_export` failed in all 3 seeds.
- DeepSeek navigating DeepSeek (KT), seed 3: 25 of 29, pass@1 20, tests@2 27.88, in 13,362 s (seeds 1, 2: 26 and 29).
  Mean of 3 seeds **26.7 pass@2**, 20.0 pass@1 (20 in every seed), against DeepSeek alone 24.7 / 19.0 (23, 23, 28
  pieced together): +2.0 / +1.0, and the pair's worst seed (25) beats both complete solo seeds (23). The best setup with
  3 seeds; the gain comes from the review turn. Failed `py_e_duration`, `py_semver_range`, `sh_access_log`,
  `sh_env_export` (Python 14/16, bash 7/9, Kotlin 4/4); no task failed in all 3 seeds. No "no fenced code block" fault.
  Tokens steady across seeds (nav ~25k, driver ~125k).

- Qwen3.8 navigating DeepSeek (KT), seed 2: **28 of 29**, pass@1 21, tests@2 28.8, in 11,335 s (seed 1: 26, pass@1 18,
  12,255 s). Mean of 2 seeds **27.0 pass@2**, 19.5 pass@1, level with DeepSeek navigating DeepSeek (26.7 / 20.0, 3 seeds)
  and above DeepSeek alone (24.7 / 19.0). Only `py_e_flatten` failed; seed 1's failures `sh_access_log`, `sh_e_replace`,
  `sh_env_export` all passed (bash 9/9, Python 15/16, Kotlin 4/4). No "no fenced code block" fault. Navigator 24.7k
  tokens, driver 156k (seed 1: 101k). Faster than DS+DS per seed (11–12k s vs 13–20k s) because the navigator turns run
  on Qwen3.8 and leave KT's second slot to another run. Seed 3 decides whether it beats DS+DS.
- Qwen3.8 + Qwen3.6 MTP review, seed 2: 20 of 29, pass@1 12, tests@2 26.05, in 4,601 s (seed 1, Nov 15: 21, pass@1 14,
  26.47, 4,570 s). Mean of 2 seeds **20.5 pass@2**, 13.0 pass@1, vs Qwen3.8 alone 16.7 / 10.0: a stable +3.8 at 1.8x
  Qwen3.8's time, the best Qwen-only quality per hour so far. Failed `py_apply_patch`, `py_e_duration`, `py_e_flatten`,
  `py_e_logstats`, `py_expr_eval`, `py_shell_split`, `sh_csv_col`, `sh_env_export`, `sh_wordfreq`; 7 of seed 1's 8
  failures repeat (`py_fix_merge_intervals`, `py_grid_route` passed here). Writer on :8086 shared with the q8:ds
  navigator, reviewer Qwen3.6 MTP on GPU 1 (3090 Ti; seed 1 had GPU 3), user-started (tmp_review_seeds.sh).
- DeepSeek navigating DeepSeek (KT), keep-unrevised, seed 2: 27 of 29, pass@1 21, tests@2 27.87, in 14,162 s (seed 1:
  27, pass@1 19, 25,062 s). Mean of 2 seeds **27.0 pass@2**, 20.0 pass@1: level with plain DS+DS (26.7 / 20.0, 3
  seeds) and Qwen3.8 navigating DeepSeek (27.0 / 19.5, 2 seeds). Failed `sh_e_ext_count`, `sh_env_export` (Python
  16/16, bash 7/9, Kotlin 4/4); no "no fenced code block" fault in either seed, so the variant's fix has had nothing
  to rescue yet. Driver 95k tokens (seed 1: 139k); the shorter time is less KT slot sharing.
- Qwen3.8 + Qwen3.6 MTP review, seed 3: **12 of 29**, pass@1 7, tests@2 20.35, in 5,546 s (seeds 1, 2: 21 and 20).
  Mean of 3 seeds 17.7 pass@2, 11.0 pass@1, against Qwen3.8 alone 16.7 / 10.0: only +1.0, the seed-1/2 gain of +3.8
  does not hold. Seed 3 is the hard seed for the Qwen3.8 writer in both setups (alone: 15, pass@1 6): the drop is in
  the writer's first drafts (pass@1 7), and the review/revise turn added 5 where it added 6–8 on seeds 1, 2. Failures
  are wrong code, not infrastructure: 4 Kotlin compile errors, 2 bash syntax errors, 3 "no fenced code block" replies;
  the reviewer said OK on 4 failing files (`kt_fix_money`, `kt_render`, `py_e_duration`, `py_semver_range`). Writer
  on :8086 shared with the q8:ds navigator, reviewer on GPU 1 (3090 Ti). Qwen3.6 MTP (:8085) stopped after this run.
- Qwen3.8 navigating Qwen3.8, tests first, seed 2: 20 of 29, pass@1 16, tests@2 26.80, in 14,201 s (seed 1: 22, pass@1
  14, 10,692 s). Mean of 2 seeds **21.0 pass@2**, 15.0 pass@1, against Qwen3.8 alone 16.7 / 10.0: +4.3 / +5.0, the best
  Qwen3.8-written setup with 2+ seeds, and the gain shows already on attempt 1 (tests-first fix rounds count inside
  it). The navigator's tests were valid on the reference for only 6 of 29 tasks (seed 1: 12), so the driver often
  fixes against wrong tests and still gains. Failed `kt_render`, `py_apply_patch`, `py_e_flatten`, `py_ini_interp`,
  `py_semver_range`, `py_shell_split`, `sh_csv_col`, `sh_e_lowercase`, `sh_rotate`. One "no fenced code block" fault.
  Ran on the second Qwen3.8 (GPU 3, :8087), alone on it; the longer time is the tests-first turns (nav 70k, driver
  256k tokens).
- Qwen3.8 navigating DeepSeek (KT), seed 3: 26 of 29, pass@1 20, tests@2 27.98, in 22,267 s (seeds 1, 2: 26 and 28).
  Mean of 3 seeds **26.7 pass@2**, 19.7 pass@1: exactly level with DeepSeek navigating DeepSeek (26.7 / 20.0) and +2.0
  over DeepSeek alone. Failed `py_semver_range`, `sh_env_export`, `sh_retry`; `sh_env_export` failed in 2 of 3 seeds,
  as in DS+DS. No "no fenced code block" fault. The long time is KT serving 3 requests at once (keep ds:ds, Q8+rDS
  reviewer, this run) plus a 3,945 s `py_grid_route`; seeds 1, 2 took 11–12k s, the fastest DeepSeek pair per seed.
- Qwen3.8 + DeepSeek review (KT reviewer), seed 2: 22 of 29, pass@1 12, tests@2 25.98, in 9,813 s (seed 1, llama.cpp
  reviewer: 22, pass@1 14, 7,360 s). Mean of 2 seeds **22.0 pass@2**, 13.0 pass@1, +5.3 over Qwen3.8 alone: the review
  adds 10 tasks on attempt 2 (12 -> 22). Failed `py_e_flatten`, `py_expr_eval`, `py_semver_range`, `py_shell_split`,
  `sh_csv_col`, `sh_env_export`, `sh_wordfreq`; 5 of seed 1's 7 failures repeat. 3 "no fenced code block" faults, as
  in seed 1. User-started (tmp_review_seeds.sh); writer on :8086 shared with the q8:ds navigator, then with ds:q8.
- Qwen3.8 navigating Qwen3.8, tests first, seed 3: **25 of 29**, pass@1 22, tests@2 28.31, in 13,234 s (seeds 1, 2: 22
  and 20). Mean of 3 seeds **22.3 pass@2**, 17.3 pass@1, against Qwen3.8 alone 16.7 / 10.0: +5.6 / +7.3, the best
  Qwen3.8-written setup and the only one where seed 3 (Qwen3.8's hard seed: alone 15, with the Qwen3.6 reviewer 12) is
  its best. pass@1 rises most (14, 16, 22) because the navigator-test fix rounds run before the first real test. The
  navigator's tests were valid on the reference for only 7 of 29 tasks (seeds 1, 2: 12, 6). Failed `py_apply_patch`,
  `py_e_flatten`, `py_semver_range`, `sh_access_log`; `py_apply_patch`, `py_e_flatten`, `py_semver_range` failed in all
  3 seeds. No "no fenced code block" fault. Time per seed 13k s vs 2.5k s for Qwen3.8 alone (5x), from the tests-first
  turns (nav 65k, driver 237k tokens). Second Qwen3.8 (:8087, GPU 3) stopped after this run.
- DeepSeek navigating DeepSeek (KT), keep-unrevised, seed 3: 26 of 29, pass@1 18, tests@2 28.25, in 18,465 s (seeds
  1, 2: 27 and 27). Mean of 3 seeds **26.7 pass@2**, 19.3 pass@1: level with plain DS+DS (26.7 / 20.0) and Qwen3.8
  navigating DeepSeek (26.7 / 19.7), so keep-unrevised adds nothing measurable. Failed `sh_access_log`, `sh_csv_col`,
  `sh_e_ext_count` (Python 16/16, Kotlin 4/4, bash 6/9); `sh_access_log` and `sh_e_ext_count` failed in 2 of 3
  seeds. No "no fenced code block" fault in any of the 3 seeds: the variant's rescue never triggered. KT shared with
  ds:q8 and the Q8+rDS reviewer most of the run.
- Qwen3.8 + DeepSeek review (KT reviewer), seed 3: 22 of 29, pass@1 15, tests@2 26.59, in 11,792 s (seeds 1, 2: 22
  and 22). Mean of 3 seeds **22.0 pass@2**, 13.7 pass@1, against Qwen3.8 alone 16.7 / 10.0: a steady +5.3, every seed
  22, so the reviewer's gain holds (unlike the Qwen3.6 reviewer's). Failed `py_async_limit`, `py_grid_route`,
  `py_shell_split`, `sh_access_log`, `sh_env_export`, `sh_retry`, `sh_wordfreq`; `sh_env_export` failed in all 3 seeds,
  `py_shell_split`, `sh_wordfreq` in 2. Bash is the weak spot (5/9; Python 13/16, Kotlin 4/4). 1 "no fenced code
  block" fault (seeds 1, 2: 3 each). Writer on :8086 shared with ds:q8; reviewer on KT shared with keep ds:ds, then tdd
  ds:ds. User-started (tmp_review_seeds.sh).
- DeepSeek (KT) navigating Qwen3.8, seed 2: 23 of 29, pass@1 14, tests@2 27.26, in 13,198 s (seed 1: 20, pass@1 13,
  7,819 s). Mean of 2 seeds **21.5 pass@2**, 13.5 pass@1, +4.8 over Qwen3.8 alone: close to the DeepSeek reviewer
  (22.0, n 3) and Qwen3.8 tests-first self-pair (22.3, n 3), all three within a seed's noise. Failed `kt_fix_money`,
  `py_expr_eval`, `py_ini_interp`, `py_shell_split`, `sh_csv_col`, `sh_env_export`; `py_expr_eval`, `py_ini_interp`,
  `sh_csv_col`, `sh_env_export` failed in both seeds. 2 "no fenced code block" faults (seed 1: 4). Driver 136k tokens;
  the longer time is :8086 shared with the Q8+rDS writer and KT shared with two other runs.
- Qwen3.6 MTP + Qwen3.8 review, seed 1 (new cell, user asked to fill "+ reviewer" for DeepSeek and Qwen3.6): 16 of 29,
  pass@1 11, tests@2 24.08, in 2,515 s, against Qwen3.6 alone 9.7 / 7.0 (3 seeds): +6.3 on one seed, the largest
  review gain so far, and level with Qwen3.8 alone (16.7) at a similar time. Kotlin 3/4, Python 8/16, bash 5/9. Failed
  `kt_tokens`, `py_apply_patch`, `py_async_limit`, `py_e_duration`, `py_expr_eval`, `py_fix_lru`,
  `py_fix_merge_intervals`, `py_semver_range`, `py_shell_split`, `sh_csv_col`, `sh_e_replace`, `sh_env_export`,
  `sh_retry`. 1 capped reply, no "no fenced code block" fault. Qwen3.6 on GPU 3 (:8085, user's GPU, lent for these
  runs), Qwen3.8 reviewer on :8086 (idle otherwise: r3/r4 paused 18:25 for the review runs).
- Qwen3.6 MTP + Qwen3.8 review, seed 2: 15 of 29, pass@1 11, tests@2 22.52, in 2,069 s (seed 1: 16). Mean of 2 seeds
  **15.5 pass@2**, 11.0 pass@1, against Qwen3.6 alone 9.7 / 7.0: +5.8 / +4.0, the gain holds on seed 2. Kotlin 3/4,
  Python 6/16, bash 6/9. Failed `kt_fix_money`, `py_apply_patch`, `py_async_limit`, `py_e_duration`, `py_e_flatten`,
  `py_expr_eval`, `py_fix_lru`, `py_fix_merge_intervals`, `py_ini_interp`, `py_semver_range`, `py_shell_split`,
  `sh_access_log`, `sh_e_lowercase`, `sh_retry`; 9 of seed 1's 13 failures repeat, mostly Python. No "no fenced code
  block" fault.
- Qwen3.6 MTP + Qwen3.8 review, seed 3: 16 of 29, pass@1 10, tests@2 22.25, in 2,860 s (seeds 1, 2: 16 and 15). Mean of
  3 seeds **15.7 pass@2**, 10.7 pass@1, against Qwen3.6 alone 9.7 / 7.0: +6.0 / +3.7, steady across seeds (the
  opposite of the Qwen3.6 reviewer on Qwen3.8, whose gain fell apart on seed 3). A Qwen3.8 reviewer lifts Qwen3.6 to
  about Qwen3.8 alone (16.7) at a similar time per seed (2.1–2.9k s vs 2.4–2.8k s), but needs both GPUs. Kotlin 3/4,
  Python 8/16, bash 5/9; `py_apply_patch`, `py_async_limit`, `py_e_duration`, `py_expr_eval`,
  `py_fix_merge_intervals`, `py_semver_range`, `py_shell_split` failed in all 3 seeds. No "no fenced code block" fault.
- Qwen3.6 MTP + DeepSeek (KT) review, seed 1: 18 of 29, pass@1 11, tests@2 23.80, in 9,545 s (KT shared with two
  DeepSeek review runs). Against Qwen3.6 alone 9.7 / 7.0: +8.3 / +4.0, and above the Qwen3.8 reviewer (15.7 over 3
  seeds); one seed only, s2/s3 run at the end. Kotlin 3/4, Python 10/16, bash 5/9. Failed `kt_tokens`,
  `py_async_limit`, `py_e_duration`, `py_expr_eval`, `py_fix_merge_intervals`, `py_semver_range`, `py_shell_split`,
  `sh_csv_col`, `sh_e_replace`, `sh_env_export`, `sh_retry`; 5 of the 7 Python tasks that failed every Q6+rQ8 seed
  fail again. One "no fenced code block" fault (`py_expr_eval`, attempt 1). Seconds per seed are 3–4x Q6+rQ8's: the
  DeepSeek review turns dominate.
- DeepSeek (KT) + Qwen3.8 review, seed 1: **29 of 29**, pass@1 22, tests@2 29.0, in 15,526 s (KT shared with the
  DS+DS review run and, until 22:32, Q6+rDS). The first perfect pass@2 of any setup and seed; pass@1 22 also the best
  (DS+DS pair 20.0 mean, DeepSeek alone 19.0). Kotlin 4/4, Python 16/16, bash 9/9. Second-attempt fixes:
  `kt_fix_money`, `py_apply_patch`, `py_ini_interp`, `py_typed_load`, `sh_csv_col`, `sh_e_replace`, `sh_rotate`. No
  "no fenced code block" fault. One seed only: DS+DS pair seed 2 also reached 29, then 25 on seed 3; s2, s3 running.
- DeepSeek (KT) + DeepSeek review, seed 1: 27 of 29, pass@1 20, tests@2 27.97, in 20,491 s (KT shared with the DS+rQ8
  run all along). Level with the DS+DS pair's mean (26.7, pass@1 20.0) and below DS+rQ8 seed 1 (29, pass@1 22).
  Kotlin 4/4, Python 16/16, bash 7/9: both failures are bash, `sh_e_ext_count` and `sh_retry` (DS+rQ8 s1 solved both;
  `sh_retry` also failed Q6+rDS s1). Second-attempt fixes: `kt_fix_money`, `py_e_duration`, `py_expr_eval`,
  `py_semver_range`, `py_shell_split`, `sh_csv_col`, `sh_env_export`. No "no fenced code block" fault. Slowest
  DeepSeek seed so far: bash review rounds alone took 9.3k s.
- DeepSeek (KT) + Qwen3.8 review, seed 2: 27 of 29, pass@1 20, tests@2 28.78, in 12,900 s (seed 1: 29). Mean of 2
  seeds **28.0 pass@2**, 21.0 pass@1: above every n=3 setup (DS+DS pair 26.7 / 20.0) and DeepSeek alone (24.7 / 19.0).
  Kotlin 4/4 (all first try), Python 15/16, bash 8/9. Failed `py_ini_interp` and `sh_retry` (`sh_retry` also failed
  DS+rDS s1). Second-attempt fixes: `py_apply_patch`, `py_e_duration`, `py_expr_eval`, `py_semver_range`,
  `sh_access_log`, `sh_env_export`, `sh_wordfreq`. No "no fenced code block" fault.
- DeepSeek (KT) + DeepSeek review, seed 2: 28 of 29, pass@1 21, tests@2 28.70, in 13,254 s (seed 1: 27). Mean of 2
  seeds **27.5 pass@2**, 20.5 pass@1, just under DS+rQ8 (28.0 / 21.0) and above the DS+DS pair (26.7 / 20.0). Kotlin
  4/4, Python 16/16 (Python 32/32 over both seeds), bash 8/9; only `sh_rotate` failed (solved in seed 1), `sh_retry`
  passed first try this time. Second-attempt fixes: `kt_fix_money`, `py_e_duration`, `py_e_fix_paginate`,
  `py_e_flatten`, `py_semver_range`, `sh_e_lowercase`, `sh_wordfreq`. No "no fenced code block" fault.
- DeepSeek (KT) + Qwen3.8 review, seed 3: 26 of 29, pass@1 18, tests@2 28.39, in 17,712 s (seeds 1, 2: 29, 27). Mean of
  3 seeds **27.3 pass@2**, 20.0 pass@1: the best n=3 setup, +0.6 over the DS+DS pair (26.7 / 20.0) at the same
  pass@1, +2.6 over DeepSeek alone (24.7 / 19.0). The 29 on seed 1 was a high draw, as for the DS+DS pair. Kotlin 4/4,
  Python 15/16, bash 7/9. Failed `py_expr_eval`, `sh_access_log`, `sh_csv_col`; nothing failed in all 3 seeds
  (`sh_retry` 2 of 3 solved). No "no fenced code block" fault. Slot A moved on to tdd DS+DS s2 at 08:08.
- DeepSeek (KT) + DeepSeek review, seed 3: 26 of 29, pass@1 22, tests@2 28.34, in 13,978 s (seeds 1, 2: 27, 28). Mean
  of 3 seeds **27.0 pass@2**, 21.0 pass@1: between DS+rQ8 (27.3 / 20.0) and the DS+DS pair (26.7 / 20.0), the highest
  n=3 pass@1. Kotlin 4/4, Python 15/16, bash 7/9. Failed `py_expr_eval`, `sh_env_export`, `sh_rotate` (`sh_rotate`
  also seed 2). No "no fenced code block" fault. With both reviewer setups at n=3, the four best DeepSeek setups
  (rQ8, rDS, DS+DS pair, Q8>DS pair) sit within 0.6 pass@2 of each other, all +2.0 to +2.6 over DeepSeek alone: any
  second look helps, who looks and in what form barely matters. Slot B moved on to tdd nav Qwen3.8 + driver DS s1 at
  08:38.
- nav DeepSeek (KT) + driver DeepSeek (KT), tests first, seed 2: 26 of 29, pass@1 24, tests@2 28.0, in 28,028 s
  (resumed from 9 tasks done; seed 1: 24 / 22). Mean of 2 seeds **25.0 pass@2**, **23.0 pass@1**: the highest pass@1 of
  any setup (DS+DS pair 20.0, DS+rDS 21.0), but pass@2 below the plain pair (26.7) and both reviewer setups (27.0–27.3),
  at about 2x their time per seed (28–34k s vs 13–20k s). The navigator's tests make the first attempt right more often
  and leave less for the second. Kotlin 4/4, Python 14/16, bash 8/9. Failed `py_e_duration`, `py_semver_range` (57 min,
  both attempts), `sh_rotate`; `py_semver_range` also failed seed 1. No "no fenced code block" fault. s3 started 14:14.
- nav Qwen3.8 + driver DeepSeek (KT), tests first, seed 1: 24 of 29, pass@1 19, tests@2 27.85, in 37,269 s (crashed
  12:03 on a 1 h request timeout, resumed from 15 tasks done). Plain Q8>DS seed 1: 26 / 18 (mean 26.7 / 19.7), so tests
  first costs 2.7 pass@2 here and adds nothing to pass@1, at 2–3x the time (37k s vs 11–22k s) and 2.3x the tokens
  (348k vs ~150k). Score 0.78 vs 0.85 plain. Qwen3.8's tests are mostly wrong: only 6 of 29 test files pass the
  reference (DeepSeek's: 8 and 6). When the tests were valid, 5 of 6 tasks were solved; when they were wrong, 19 of 23.
  DeepSeek then spends 59 fix turns chasing them. It lost tasks the plain pair solves: `py_ini_interp`, `py_e_flatten`,
  `py_e_logstats`, `sh_rotate`, `sh_csv_col`; it gained `sh_access_log`, `sh_e_replace`, `sh_env_export`. Kotlin 4/4,
  Python 13/16, bash 7/9. No attempt capped, no "no fenced code block" fault. Slow tasks: `py_grid_route` (one
  ~31k-token driver reply hit the 1 h timeout), `sh_env_export` 71 min. s2 started 20:27, the first seed with streamed
  requests (eval_pair.py 5592cc1).
- nav DeepSeek (KT) + driver DeepSeek (KT), tests first, seed 3: 25 of 29, pass@1 21, tests@2 28.34, in 33,820 s
  (seeds 1, 2: 24 / 22, 26 / 24). Mean of 3 seeds **25.0 pass@2**, **22.3 pass@1** (score 0.83): still the best pass@1
  of any setup (DS+rDS 21.0, DS+DS pair 20.0), and still ~1.7 below the plain DS+DS pair and 2.0–2.3 below the
  reviewer setups at pass@2, at about 2x their time (28–34k s vs 13–20k s). Kotlin 4/4, Python 14/16, bash 7/9.
  Failed `py_ini_interp`, `py_shell_split`, `sh_e_ext_count`, `sh_rotate` (`sh_rotate` fails every tdd DS+DS seed).
  Only 6 of 29 navigator test files pass the reference (seeds 1, 2: 8, 6). With valid tests it solved 6 of 6, with
  wrong ones 19 of 23. `sh_csv_col` took 65 min (21k driver tokens chasing wrong tests in attempt 1, passed attempt 2).
  No attempt capped, no "no fenced code block" fault. Slot A moved on to nav DS + driver Qwen3.8 (KT) s3 at 23:43.
- DeepSeek (KT) navigating Qwen3.8, seed 3: 23 of 29, pass@1 15, tests@2 26.35, in 9,139 s (seeds 1, 2: 20 / 13,
  23 / 14). Mean of 3 seeds **22.0 pass@2**, **14.0 pass@1** (score 0.68), +5.3 over Qwen3.8 alone: level with the
  DeepSeek reviewer (22.0, pass@1 13.7, n 3) and the Qwen3.8 tests-first self-pair (22.3, n 3), which needs no DeepSeek.
  Kotlin 4/4, Python 11/16, bash 8/9. Failed `py_apply_patch`, `py_e_config_merge`, `py_e_duration`, `py_expr_eval`,
  `py_shell_split`, `sh_e_ext_count`; `py_expr_eval` failed all 3 seeds, but `py_ini_interp`, `sh_csv_col` and
  `sh_env_export` (failed seeds 1 and 2) passed. 4 "no fenced code block" faults (`py_apply_patch` #1, `py_ini_interp`
  #1, `sh_e_ext_count` #1 and #2), so the revise-turn fault still costs ~1 task per seed. Slot A moved on to tdd nav DS
  + driver Qwen3.8 s2 at 01:44.
- Qwen3.8 navigating DeepSeek (KT), tests first, seed 2: **29 of 29**, pass@1 23, tests@2 29.0, in 23,587 s (seed 1:
  24 / 19, 37,269 s), the first complete seed with streamed requests and the first tdd seed to solve everything. Mean of
  2 seeds **26.5 pass@2**, **21.0 pass@1** (score 0.86, Winners #3 at n 2): level with the plain Q8>DS pair (26.7 /
  19.7) at pass@2, +1.3 pass@1, at 2–3x its time. Still only 6 of 29 Qwen3.8 test files pass the reference (seed 1: 6);
  with wrong tests DeepSeek solved 23 of 23 this time (seed 1: 19 of 23), so the seed-to-seed gap is the driver, not the
  tests. No attempt capped, no "no fenced code block" fault; driver 185k tokens (seed 1: 283k). Slowest tasks 30–37 min
  (`py_apply_patch`, `py_shell_split`, `py_grid_route`; seed 1's `py_grid_route` took 101 min). s3 started 03:03.
- DeepSeek (KT) navigating Qwen3.8, tests first, seed 2: 22 of 29, pass@1 19, tests@2 26.29, in 17,028 s (seed 1, Nov 22:
  20 / 17, 16,813 s). Mean of 2 seeds **21.0 pass@2**, **18.0 pass@1** (score 0.69, Winners #11): the best Qwen3.8
  pass@1 of any setup, but 1–1.3 below the Qwen3.8 tests-first self-pair (22.3), the DeepSeek navigator pair and the
  DeepSeek reviewer (22.0 each) at pass@2. Kotlin 4/4, Python 11/16, bash 7/9. Failed `py_expr_eval`, `py_ini_interp`,
  `py_semver_range`, `py_shell_split`, `py_typed_load`, `sh_csv_col`, `sh_rotate` (5 of them also failed seed 1). DeepSeek's
  test files pass the reference on only 6 of 29 tasks (seed 1: 10); Qwen3.8 solved 5 of those 6 and 17 of the 23 with wrong
  tests (seed 1: 10 of 10, 10 of 19). No "no fenced code block" fault (seed 1: 3), none capped. Driver 246k tokens
  (seed 1: 201k). s3 started 06:37.
- Qwen3.8 navigating DeepSeek (KT), tests first, seed 3: 26 of 29, pass@1 22, tests@2 27.71, in 26,047 s (seeds 1, 2:
  24 / 19, 29 / 23). Mean of 3 seeds **26.3 pass@2**, **21.3 pass@1** (score 0.86, Winners #3): level with the plain
  Q8>DS pair (26.7 / 19.7) and the DS+DS pair (26.7 / 20.0) at pass@2, +1.3–1.6 pass@1, at 2–3x their time; only the
  two reviewer setups (0.87) score higher. Kotlin 3/4, Python 14/16, bash 9/9. Failed `kt_render`, `py_apply_patch`,
  `py_e_flatten` (`py_e_flatten` also failed seed 1). 7 of 29 navigator test files pass the reference (seeds 1, 2: 6, 6);
  DeepSeek solved 7 of 7 with valid tests and 19 of 22 with wrong ones. No attempt capped, no "no fenced code block"
  fault in any of the 3 seeds. Slowest `py_grid_route` 55 min.
- DeepSeek (KT) navigating Qwen3.8, tests first, seed 3: 23 of 29, pass@1 19, tests@2 26.44, in 16,340 s (seeds 1, 2:
  20 / 17, 22 / 19). Mean of 3 seeds **21.7 pass@2**, **18.3 pass@1** (score 0.71, Winners #11): the best Qwen3.8
  pass@1, and within a seed of the other Qwen3.8 setups at pass@2 (tdd self-pair 22.3, DeepSeek navigator 22.0,
  DeepSeek reviewer 22.0), at 6–7x Qwen3.8 alone's time. Kotlin 4/4, Python 12/16, bash 7/9. Failed `py_apply_patch`,
  `py_expr_eval`, `py_ini_interp`, `py_shell_split`, `sh_csv_col`, `sh_rotate`; `py_ini_interp`, `py_shell_split`,
  `sh_csv_col`, `sh_rotate` failed all 3 seeds. 10 of 29 DeepSeek test files pass the reference (seeds 1, 2: 10, 6);
  Qwen3.8 solved 8 of 10 with valid tests and 15 of 19 with wrong ones. No "no fenced code block" fault, none capped.
  Both queues finished at 11:24; the DeepSeek-written cells are complete at n 3, only Qwen3.6 + DeepSeek review s2, s3
  remain.
