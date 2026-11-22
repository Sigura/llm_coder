# Pair programming (navigator + driver) vs solo and review setups (2026-11-21)

Copy of `LLM_ROOT/results/pair-eval/pair-report.md` as of 2026-11-22; the live file there may be newer.

Eval: burnish's coding tasks, 29 tasks (16 Python, 9 bash, 4 Kotlin), 2 attempts, recommended sampling; the same
tests and scoring as the solo runs (`stack/scripts/eval_pair.py`). pass@1 / pass@2 = tasks solved on the first /
either attempt; tests@2 = test fraction summed over tasks.

Pair flow per task: (1) navigator writes a plan and 3–6 checks, (2) driver writes the file, (3) navigator reviews, and
the driver revises once unless the review says OK, (4) the tests run; on failure the navigator turns the output into a fix
instruction for attempt 2. "Review" setups: the writer works alone, the reviewer only reviews (no plan).

## What was tested

| setup | writer (driver) | planner / reviewer (navigator) | seeds |
|---|---|---|---|
| DeepSeek alone | DeepSeek V4.1 Flash (llama.cpp) | — | 1 (part file), 2, 3 |
| Qwen3.8 alone | Qwen3.8-27B | — | 1, 2, 3 |
| Qwen3.6 MTP alone | Qwen3.6-35B-A3B MTP | — | 1, 2, 3 |
| Q8+rDS | Qwen3.8 | DeepSeek reviews | 1 |
| Q8+rQ6 | Qwen3.8 | Qwen3.6 MTP reviews | 1 |
| PAIR (llama.cpp) | Qwen3.8 | DeepSeek (llama.cpp) plans + reviews | 1, 2 (partial, 15/29) |
| nav DeepSeek (KT) + driver DeepSeek (KT) | DeepSeek (KT) | DeepSeek (KT) plans + reviews | 1 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | DeepSeek (KT) | DeepSeek (KT) plans + reviews | 1 (partial, 20/29) |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | DeepSeek (KT) | DeepSeek (KT) plans + reviews | 1 (partial, 18/29) |
| PAIR-KT | Qwen3.8 | DeepSeek (KT) plans + reviews | 1 |
| DS>Q8 tdd | Qwen3.8 | DeepSeek (KT) plans + reviews | 1 |
| nav DeepSeek (KT) + driver Qwen3.6 MTP | Qwen3.6 MTP | DeepSeek (KT) plans + reviews | 1 |
| nav Qwen3.8 + driver DeepSeek (KT) | DeepSeek (KT) | Qwen3.8 plans + reviews | 1 |
| nav Qwen3.8 + driver Qwen3.8 | Qwen3.8 | Qwen3.8 plans + reviews | 1 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | Qwen3.8 | Qwen3.8 plans + reviews | 1 |
| nav Qwen3.8 + driver Qwen3.6 MTP | Qwen3.6 MTP | Qwen3.8 plans + reviews | 1 |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | DeepSeek (KT) | Qwen3.6 MTP plans + reviews | 1 |
| nav Qwen3.6 MTP + driver Qwen3.8 | Qwen3.8 | Qwen3.6 MTP plans + reviews | 1, 2, 3 (partial, 28/29) |
| nav Qwen3.6 MTP + driver Qwen3.6 MTP | Qwen3.6 MTP | Qwen3.6 MTP plans + reviews | 1 |

Finished pairs so far: DeepSeek → Qwen3.8 (llama.cpp and KT), DeepSeek → DeepSeek (KT), Qwen3.8 → Qwen3.8, Qwen3.6 MTP → Qwen3.6 MTP, Qwen3.6 MTP → Qwen3.8, Qwen3.8 → Qwen3.6 MTP (navigator → driver). The rest of the matrix is running or queued (see Combinations below).

## Headline (pass@2 of 29)

| setup | pass@2 per seed | mean | pass@1 mean | time per seed |
|---|---|---|---|---|
| nav DeepSeek (KT) + driver DeepSeek (KT) | 26 | — | 20 | 13,748 s |
| nav Qwen3.8 + driver DeepSeek (KT) | 26 | — | 18 | 12,255 s |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | 26 | — | 20 | 9,774 s |
| DeepSeek alone | 28 (pieced together), 23, 23 | 24.7 | 19.0 | 7,536–10,754 s |
| Q8+rDS | 22 | — | 14 | 7,360 s |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 22 | — | 14 | 10,692 s |
| Q8+rQ6 | 21 | — | 14 | 4,570 s |
| PAIR (llama.cpp) | 21, seed 2: 13 of the first 15 | — | 14 | 7,598 s |
| PAIR-KT | 20 | — | 13 | 7,819 s |
| DS>Q8 tdd | 20 | — | 17 | 16,813 s |
| Qwen3.8 alone | 18, 17, 15 | 16.7 | 10.0 | 2,366–2,763 s |
| nav Qwen3.6 MTP + driver Qwen3.8 | 16, 17, seed 3: 11 of the first 28 | 16.5 | 11.5 | 3,602–4,743 s (Qwen3.6 on the 3090 Ti) |
| nav Qwen3.8 + driver Qwen3.8 | 16 | — | 10 | 6,698 s |
| nav DeepSeek (KT) + driver Qwen3.6 MTP | 14 | — | 7 | 5,954 s |
| nav Qwen3.8 + driver Qwen3.6 MTP | 13 | — | 8 | 3,000 s |
| Qwen3.6 MTP alone | 12, 8, 9 | 9.7 | 7.0 | 812–914 s |
| nav Qwen3.6 MTP + driver Qwen3.6 MTP | 9 | — | 4 | 2,704 s |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | seed 1: 19 of the first 20 | — | — | — |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | seed 1: 16 of the first 18 | — | — | — |

## Summary per run

| setup | seed | tasks | pass@1 | pass@2 | tests@2 | time s | tokens | nav / driver tokens |
|---|---|---|---|---|---|---|---|---|
| DeepSeek alone | 1 (part file) | 7 | 3 | 7 | 7.0 | 1760 | 20547 | — |
| DeepSeek alone | 2 | 29 | 19 | 23 | 27.233 | 7536 | 89451 | — |
| DeepSeek alone | 3 | 29 | 16 | 23 | 27.285 | 10754 | 69501 | — |
| Qwen3.8 alone | 1 | 29 | 14 | 18 | 23.465 | 2504 | 81919 | — |
| Qwen3.8 alone | 2 | 29 | 10 | 17 | 26.212 | 2366 | 77194 | — |
| Qwen3.8 alone | 3 | 29 | 6 | 15 | 22.524 | 2763 | 92378 | — |
| Qwen3.6 MTP alone | 1 | 29 | 9 | 12 | 20.557 | 812 | 96446 | — |
| Qwen3.6 MTP alone | 2 | 29 | 5 | 8 | 19.39 | 857 | 100434 | — |
| Qwen3.6 MTP alone | 3 | 29 | 7 | 9 | 20.596 | 914 | 106472 | — |
| Qwen3.8 writes, DeepSeek reviews | 1 | 29 | 14 | 22 | 26.51 | 7360 | 76348 | — |
| Qwen3.8 writes, Qwen3.6 MTP reviews | 1 | 29 | 14 | 21 | 26.467 | 4570 | 77764 | — |
| nav DeepSeek (llama.cpp) + driver Qwen3.8 | 1 | 29 | 14 | 21 | 25.068 | 7598 | 152910 | 28505 / 124405 |
| nav DeepSeek (llama.cpp) + driver Qwen3.8 | 2 (partial) | 15 | 11 | 13 | — | 2914 | — | — |
| nav DeepSeek (KT) + driver DeepSeek (KT) | 1 | 29 | 20 | 26 | 27.986 | 13748 | 150939 | 24397 / 126542 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | 1 (partial) | 20 | 15 | 19 | — | 16330 | — | — |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 1 (partial) | 18 | 15 | 16 | — | 19977 | — | — |
| nav DeepSeek (KT) + driver Qwen3.8 | 1 | 29 | 13 | 20 | 24.735 | 7819 | 146873 | 27700 / 119173 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 1 | 29 | 17 | 20 | 25.01 | 16813 | 257938 | 57321 / 200617 |
| nav DeepSeek (KT) + driver Qwen3.6 MTP | 1 | 29 | 7 | 14 | 22.101 | 5954 | 217529 | 29201 / 188328 |
| nav Qwen3.8 + driver DeepSeek (KT) | 1 | 29 | 18 | 26 | 27.827 | 12255 | 123948 | 22946 / 101002 |
| nav Qwen3.8 + driver Qwen3.8 | 1 | 29 | 10 | 16 | 24.185 | 6698 | 200206 | 31049 / 169157 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 1 | 29 | 14 | 22 | 27.152 | 10692 | 304308 | 63686 / 240622 |
| nav Qwen3.8 + driver Qwen3.6 MTP | 1 | 29 | 8 | 13 | 22.263 | 3000 | 219075 | 29499 / 189576 |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | 1 | 29 | 20 | 26 | 27.655 | 9774 | 143470 | 29530 / 113940 |
| nav Qwen3.6 MTP + driver Qwen3.8 | 1 | 29 | 11 | 16 | 23.461 | 4743 | 168557 | 41436 / 127121 |
| nav Qwen3.6 MTP + driver Qwen3.8 | 2 | 29 | 12 | 17 | 24.637 | 3602 | 122645 | 25626 / 97019 |
| nav Qwen3.6 MTP + driver Qwen3.8 | 3 (partial) | 28 | 9 | 11 | — | 3902 | — | — |
| nav Qwen3.6 MTP + driver Qwen3.6 MTP | 1 | 29 | 4 | 9 | 19.331 | 2704 | 210776 | 45997 / 164779 |

## Per task

Solo columns: seeds solved at pass@2 (DeepSeek: seeds 2,3; its seed 1 lost 23 tasks to a host reset). Other columns, seed 1: 2 = solved on attempt 1, 1 = on attempt 2, 0 = failed.

| task | lang | DS solo | Q8 solo | Q6 solo | Q8+rDS | Q8+rQ6 | PAIR | DS>DS | DS>DS keep (20/29) | DS>DS tdd (18/29) | PAIR-KT | DS>Q8 tdd | DS>Q6 | Q8>DS | Q8>Q8 | Q8>Q8 tdd | Q8>Q6 | Q6>DS | Q6>Q8 | Q6>Q6 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sh_access_log | bash | 2/2 | 0/3 | 1/3 | 2 | 2 | 2 | 0 | · | · | 0 | 2 | 0 | 0 | 0 | 1 | 1 | 2 | 0 | 0 |
| sh_csv_col | bash | 1/2 | 1/3 | 0/3 | 0 | 0 | 0 | 1 | · | · | 0 | 0 | 2 | 1 | 0 | 0 | 0 | 2 | 0 | 0 |
| sh_e_ext_count | bash | 2/2 | 3/3 | 3/3 | 1 | 1 | 2 | 2 | · | · | 2 | 2 | 1 | 2 | 2 | 2 | 1 | 2 | 2 | 2 |
| sh_e_lowercase | bash | 2/2 | 2/3 | 1/3 | 0 | 2 | 2 | 2 | · | · | 2 | 2 | 1 | 1 | 1 | 2 | 2 | 2 | 2 | 0 |
| sh_e_replace | bash | 2/2 | 2/3 | 0/3 | 1 | 2 | 0 | 2 | · | · | 2 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 1 | 0 |
| sh_env_export | bash | 1/2 | 1/3 | 0/3 | 0 | 0 | 0 | 2 | · | · | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 2 | 0 | 0 |
| sh_retry | bash | 0/2 | 0/3 | 2/3 | 2 | 1 | 1 | 2 | · | · | 2 | 2 | 2 | 2 | 2 | 2 | 0 | 0 | 0 | 0 |
| sh_rotate | bash | 2/2 | 2/3 | 2/3 | 2 | 2 | 2 | 2 | · | · | 2 | 0 | 1 | 2 | 2 | 1 | 1 | 0 | 0 | 1 |
| sh_wordfreq | bash | 2/2 | 1/3 | 2/3 | 1 | 0 | 1 | 0 | · | · | 2 | 2 | 1 | 2 | 2 | 0 | 0 | 2 | 2 | 0 |
| kt_fix_money | kotlin | 1/2 | 2/3 | 1/3 | 1 | 2 | 0 | 2 | 2 | 2 | 1 | 1 | 2 | 2 | 0 | 2 | 1 | 1 | 2 | 0 |
| kt_lru | kotlin | 2/2 | 3/3 | 2/3 | 2 | 2 | 2 | 2 | 2 | 2 | 1 | 2 | 2 | 2 | 0 | 1 | 2 | 2 | 2 | 1 |
| kt_render | kotlin | 2/2 | 3/3 | 1/3 | 1 | 1 | 1 | 2 | 2 | 2 | 1 | 2 | 0 | 1 | 1 | 2 | 1 | 2 | 0 | 0 |
| kt_tokens | kotlin | 2/2 | 2/3 | 0/3 | 2 | 2 | 2 | 1 | 2 | 2 | 1 | 2 | 0 | 2 | 0 | 2 | 0 | 2 | 0 | 1 |
| py_apply_patch | python | 1/2 | 0/3 | 0/3 | 0 | 0 | 2 | 1 | 2 | 2 | 1 | 2 | 0 | 2 | 0 | 0 | 0 | 2 | 0 | 0 |
| py_async_limit | python | 2/2 | 2/3 | 1/3 | 2 | 1 | 2 | 2 | 2 | 2 | 1 | 2 | 0 | 2 | 0 | 1 | 0 | 2 | 2 | 2 |
| py_cron_next | python | 2/2 | 2/3 | 2/3 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 1 | 1 | 0 | 2 | 2 | 2 | 2 | 0 |
| py_e_config_merge | python | 2/2 | 3/3 | 3/3 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 |
| py_e_duration | python | 0/2 | 2/3 | 0/3 | 2 | 0 | 1 | 1 | 0 | 2 | 2 | 0 | 0 | 1 | 2 | 0 | 0 | 1 | 0 | 0 |
| py_e_fix_paginate | python | 2/2 | 3/3 | 3/3 | 2 | 2 | 1 | 2 | 2 | 0 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 |
| py_e_flatten | python | 1/2 | 1/3 | 0/3 | 0 | 1 | 2 | 2 | 1 | 2 | 0 | 1 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 0 |
| py_e_logstats | python | 2/2 | 3/3 | 3/3 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0 | 1 | 0 | 0 | 0 | 2 | 0 | 0 |
| py_expr_eval | python | 1/2 | 0/3 | 0/3 | 0 | 0 | 0 | 1 | 1 | 2 | 0 | 2 | 0 | 1 | 1 | 1 | 0 | 2 | 1 | 0 |
| py_fix_lru | python | 2/2 | 3/3 | 1/3 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 1 |
| py_fix_merge_intervals | python | 2/2 | 2/3 | 0/3 | 1 | 0 | 0 | 2 | 2 | 2 | 0 | 2 | 0 | 2 | 1 | 1 | 0 | 2 | 1 | 0 |
| py_grid_route | python | 2/2 | 1/3 | 1/3 | 1 | 0 | 1 | 2 | 2 | 2 | 0 | 0 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 1 |
| py_ini_interp | python | 1/2 | 3/3 | 0/3 | 2 | 2 | 0 | 2 | 2 | 0 | 0 | 0 | 0 | 2 | 1 | 2 | 0 | 0 | 1 | 0 |
| py_semver_range | python | 2/2 | 1/3 | 0/3 | 0 | 1 | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 2 | 1 | 0 | 0 | 2 | 0 | 0 |
| py_shell_split | python | 2/2 | 0/3 | 0/3 | 1 | 1 | 0 | 2 | 2 | · | 1 | 0 | 0 | 2 | 0 | 2 | 0 | 1 | 1 | 0 |
| py_typed_load | python | 1/2 | 2/3 | 0/3 | 2 | 2 | 2 | 1 | 1 | · | 2 | 1 | 1 | 2 | 2 | 2 | 2 | 1 | 0 | 0 |

## Findings

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
- In progress (2026-11-22 13:00), DeepSeek (KT) in both roles, seed 1, against plain DS+DS on the same tasks:
  `--tests-first` 16 of 18 (plain 17; failed `py_e_fix_paginate`, `py_ini_interp`; DeepSeek's tests pass the
  reference on 6 of 18), `--keep-unrevised` 19 of 20 (plain 19; failed `py_e_duration`). Both fixed
  `py_semver_range` on the second attempt, which plain DS+DS failed. Times are not comparable: KT's GPU expert
  cache (hot lend) stopped at 02:42 and decode ran at ~15-16 tok/s instead of 18-20 until the restart at 12:57.

## Tests-first (V4, `--tests-first`)

The navigator writes a test file after the plan; the driver fixes against it (up to 2 turns) before the real
tests. "Pass on ref": the navigator's tests pass on the task's reference solution, so they are correct. The nav-test
columns count attempts that produced a file.

| setup | seed | tasks | nav tests pass on ref | nav tests pass first try | nav tests pass after fixes | tdd fix turns | pass@2 (nav tests valid) | pass@2 (nav tests wrong) |
|---|---|---|---|---|---|---|---|---|
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 1 (partial, 18/29) | 18 | 6/18 | 5/21 | 10/21 | 29 | 6/6 | 10/12 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 1 | 29 | 10/29 | 11/38 | 14/38 | 52 | 10/10 | 10/19 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 1 | 29 | 12/29 | 9/43 | 16/43 | 62 | 9/12 | 13/17 |

## Combinations available in this environment

Hardware limits: one DeepSeek at a time (KTransformers holds ~400 GiB RAM, llama.cpp ~190 GiB of page cache); KT on
GPU 0 serves 2 requests at once; Qwen3.8-27B on GPU 2 (:8086), Qwen3.6-35B-A3B MTP on GPU 3 (:8085), one slot each;
GPU 1 (3090 Ti) is kept idle (host-hang test). Coder-Next is not on disk. So 3 models x 2 roles = 9 navigator:driver pairs, each in
non-thinking mode (thinking variants below).

| navigator \ driver | DeepSeek (KT) | Qwen3.8 | Qwen3.6 MTP |
|---|---|---|---|
| DeepSeek (KT) | s1 26/29 done | s1 20/29 done; s1 llama.cpp 21/29 done; s2 llama.cpp 13/15 paused | s1 14/29 done |
| Qwen3.8 | s1 26/29 done | s1 16/29 done | s1 13/29 done |
| Qwen3.6 MTP | s1 26/29 done | s1 16/29 done; s2 17/29 done; s3 11/28 paused | s1 9/29 done |

Stream A (`tmp_pair_queue_ds.sh`): DeepSeek-bound pairs, seed 1 of each first, then seeds 2,3. Stream B
(`tmp_pair_matrix.sh`): Qwen-only pairs, same order. Each model keeps its solo-eval sampling in either role
(DeepSeek temperature 1, top_p 1; Qwens 0.7 / 0.8 / top_k 20 / presence 1.5), thinking off, as in all earlier runs.
Times of runs that overlap are not comparable with solo times (stream A's Qwen turns wait for stream B's);
pass rates are.

## Literature (summary)

| work | split | result | takeaway |
|---|---|---|---|
| [Aider architect mode](https://aider.chat/2024/09/26/architect.html) (2024) | planner + editor | o1-preview alone 79.7, + DeepSeek/o1-mini editor 85.0; Sonnet+Sonnet 80.5 vs 77.4 alone | the best evidence for navigator/driver: a reasoning planner, an editor that only applies the plan, whole-file format |
| [Self-Repair, Olausson et al.](https://arxiv.org/abs/2306.09896) (ICLR 2024) | coder + feedback model | modest gains; often no better than resampling at equal cost; a stronger feedback model helps | the strong model should critique, the weak one fix; sampling is a strong baseline |
| [Planner-coder gap](https://arxiv.org/abs/2510.10460) (2025) | planner -> coder | the gap causes 75.3% of failures; a monitor + rephrased plans recover 40-89% | matches our pair losses on tasks Qwen solves alone |
| [MAST taxonomy](https://arxiv.org/pdf/2503.13657.pdf) (2025) | failure modes | multi-agent gains over one agent are often small; incomplete verification, ignoring the partner | force point-by-point replies to review items, always run the tests |
| [Capable models outgrow collaboration](https://ubicomplab.cs.washington.edu/publications/Zhihan_NatureMI2026/) (Nat. Mach. Intell. 2026) | 260 configs, 6 benchmarks | the solo model's capability predicted whether coordination helps in 94% of validation configs | DeepSeek (24.7) is likely past the point where a partner helps; Qwen3.8 (16.7) is not |
| [AgentCoder](https://arxiv.org/abs/2312.13010), [MapCoder](https://arxiv.org/pdf/2405.11403.pdf), [Self-Collaboration](https://arxiv.org/abs/2304.07590) | test writer / multi-stage | high self-reported HumanEval numbers; an independent study reports poor transfer to open models (not verified) | test-first is worth one trial, not more |
| [Reflexion](https://arxiv.org/abs/2303.11366), [Self-Debug](https://arxiv.org/abs/2304.05128) | one model + execution feedback | gains come from test feedback, not from self-critique alone | our attempt 2 already uses test feedback |

## Protocol variants to test after the base matrix

Flags to add to `eval_pair.py` (opt-in, the default protocol stays as above so running seeds stay comparable):

| # | variant | hypothesis | literature |
|---|---|---|---|
| V1 | review only after a test failure (no review before the first test run) | removes false-positive reviews and the "no code block" faults; saves navigator time | Self-Repair, MAST |
| V2 | thinking navigator (DeepSeek plans/reviews with thinking on), driver non-thinking | a reasoning planner is the setup that won in Aider | Aider architect |
| V3 | architect/editor: navigator writes the full solution in prose, driver only turns it into the file | narrows the planner-coder gap | Aider, planner-coder gap |
| V4 | tests first: navigator writes the checks as runnable asserts the driver must pass | better first attempts if the tests are right | AgentCoder |
| V5 | best-of-n with Qwen3.6 MTP (n=4, tests pick), DeepSeek fixes what still fails | cheap samples + strong fixer at equal time | Self-Repair (sampling baseline) |
| V6 | driver must answer each review line (fix or reject with a reason) | fewer ignored or blindly applied reviews | MAST |

## Gaps and proposed runs

| # | run | answers | time per seed (est.) |
|---|---|---|---|
| 1 | PAIR seeds 2, 3 (nav DeepSeek, driver Qwen3.8) | is the +3–4 real or seed noise | ~2.1 h |
| 2 | fix the "no code block" case in `eval_pair.py` (re-ask the driver once), rerun PAIR seed 1 | how much the format faults cost | ~2.1 h |
| 3 | reversed: nav Qwen3.8, driver DeepSeek | does a fast navigator lift DeepSeek above 24.7 | ~3 h |
| 4 | nav DeepSeek, driver Qwen3.6 MTP | strongest planner + fastest writer | ~1–1.5 h |
| 5 | nav Qwen3.6 MTP, driver Qwen3.8 (no DeepSeek) | cheap pair vs Q8+rQ6 (21 in 4,570 s) | ~1 h |
| 6 | DeepSeek alone seed 1 complete | clean baseline (seed 1 lost 23 tasks to a host reset) | ~2.1 h |

Extra metrics to record: review verdicts (OK vs defects) and whether a revision turned a failing file into a passing
one, plan-only vs review-only ablation, time to first passing attempt.
Runs 1, 3, 4 and 6 need DeepSeek (KT on :8080 now), 1–5 need the Qwen servers on 8085/8086 (stopped now).
