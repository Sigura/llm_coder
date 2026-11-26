# Pair programming (navigator + driver) vs solo and review setups (2026-11-21)

Eval: burnish's coding tasks, 29 tasks (16 Python, 9 bash, 4 Kotlin), 2 attempts, recommended sampling; the same
tests and scoring as the solo runs (`stack/scripts/eval_pair.py`). pass@1 / pass@2 = tasks solved on the first /
either attempt; tests@2 = test fraction summed over tasks.

Pair flow per task: (1) navigator writes a plan and 3–6 checks, (2) driver writes the file, (3) navigator reviews, and
the driver revises once unless the review says OK, (4) the tests run; on failure the navigator turns the output into a fix
instruction for attempt 2. "Review" setups: the writer works alone, the reviewer only reviews (no plan).

Files: [pair-eval-winners.md](pair-eval-winners.md) (winners + headline, short), [pair-eval-report.md](pair-eval-report.md) (setup, generated tables, literature, gaps), [pair-eval-findings.md](pair-eval-findings.md) (per-run findings).

## What was tested

| setup | writer (driver) | planner / reviewer (navigator) | seeds |
|---|---|---|---|
| DeepSeek alone | DeepSeek V4.1 Flash (llama.cpp) | — | 1 (part file), 2, 3 |
| Qwen3.8 alone | Qwen3.8-27B | — | 1, 2, 3 |
| Qwen3.6 MTP alone | Qwen3.6-35B-A3B MTP | — | 1, 2, 3 |
| Q8+rDS | Qwen3.8 | DeepSeek reviews | 1, 2, 3 |
| Q8+rQ6 | Qwen3.8 | Qwen3.6 MTP reviews | 1, 2, 3 |
| Q6+rQ8 | Qwen3.6 MTP | Qwen3.8 reviews | 1, 2, 3 |
| DS+rQ8 | DeepSeek V4.1 Flash (KT) | Qwen3.8 reviews | 1, 2, 3 |
| DS+rDS | DeepSeek V4.1 Flash (KT) | DeepSeek reviews | 1, 2, 3 |
| Q6+rDS | Qwen3.6 MTP | DeepSeek reviews | 1 |
| PAIR (llama.cpp) | Qwen3.8 | DeepSeek (llama.cpp) plans + reviews | 1, 2 (partial, 15/29) |
| nav DeepSeek (KT) + driver DeepSeek (KT) | DeepSeek (KT) | DeepSeek (KT) plans + reviews | 1, 2, 3 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | DeepSeek (KT) | DeepSeek (KT) plans + reviews | 1, 2, 3 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | DeepSeek (KT) | DeepSeek (KT) plans + reviews | 1, 2, 3 |
| PAIR-KT | Qwen3.8 | DeepSeek (KT) plans + reviews | 1, 2, 3 |
| DS>Q8 tdd | Qwen3.8 | DeepSeek (KT) plans + reviews | 1, 2, 3 |
| nav DeepSeek (KT) + driver Qwen3.6 MTP | Qwen3.6 MTP | DeepSeek (KT) plans + reviews | 1 |
| nav Qwen3.8 + driver DeepSeek (KT) | DeepSeek (KT) | Qwen3.8 plans + reviews | 1, 2, 3 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | DeepSeek (KT) | Qwen3.8 plans + reviews | 1, 2, 3 |
| nav Qwen3.8 + driver Qwen3.8 | Qwen3.8 | Qwen3.8 plans + reviews | 1, 2, 3 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | Qwen3.8 | Qwen3.8 plans + reviews | 1, 2, 3 |
| nav Qwen3.8 + driver Qwen3.6 MTP | Qwen3.6 MTP | Qwen3.8 plans + reviews | 1 |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | DeepSeek (KT) | Qwen3.6 MTP plans + reviews | 1, 2, 3 |
| nav Qwen3.6 MTP + driver Qwen3.8 | Qwen3.8 | Qwen3.6 MTP plans + reviews | 1, 2, 3 |
| nav Qwen3.6 MTP + driver Qwen3.6 MTP | Qwen3.6 MTP | Qwen3.6 MTP plans + reviews | 1 |

Finished pairs so far: DeepSeek → Qwen3.8 (llama.cpp and KT), DeepSeek → DeepSeek (KT), Qwen3.8 → Qwen3.8, Qwen3.6 MTP → Qwen3.6 MTP, Qwen3.6 MTP → Qwen3.8, Qwen3.8 → Qwen3.6 MTP (navigator → driver). The rest of the matrix is running or queued (see Combinations below).

## Headline (sort: quality, then pass@1)

Scoring (user, Nov 26; replaces score = (0.3 pass@1 + 0.7 pass@2) / 29, kept as "old score"). Each task gets two
attempts; the second sees the test failures of the first. pass@2 sits at 25–29 of 29 for every DeepSeek setup and moves
2–4 between seeds of one setup, so it no longer separates setups; the old score inherited that and ignored cost.
- quality: share of the task's hidden tests passed by the better of the two attempts (burnish's tests@2 / 29), mean of
  the complete seeds; a near miss counts partly. Seed noise of one setup is 0.02–0.04.
- pass@1: tasks solved without a retry, mean of complete seeds.
- min per solved task: wall time of all complete seeds / tasks solved by pass@2.
- vs DeepSeek alone: per task, the setup's solve rate over its seeds minus DeepSeek alone's (seeds 2, 3); the positive
  differences summed (+, tasks gained) and the negative ones (−, tasks lost).
- net [95% CI], quality vs best: paired bootstrap over the 29 tasks (10,000 resamples, seeds averaged per task first),
  in tasks: net = solved tasks gained minus lost against DeepSeek alone, quality vs best = hidden-test share summed
  over tasks against the top setup. * = the interval excludes 0, i.e. a real difference at 95%. DeepSeek alone
  has per-task data only for seeds 2 and 3 (23 each, the pieced-together 28 has none), so gains over it are on
  the generous side.
- pass^3 = tasks solved (pass@2) in all three seeds: reliability, not luck (τ-bench); setups with fewer than 3
  complete seeds show —.

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

## Summary per run

| setup | seed | tasks | pass@1 | pass@2 | tests@2 | time s | tokens | nav / driver tokens |
|---|---|---|---|---|---|---|---|---|
| DeepSeek alone | 1 (part file) | 7 | 3 | 7 | 7.0 | 1760 | 20547 | — |
| DeepSeek alone | 2 | 29 | 19 | 23 | 27.1 | 7536 | 89451 | — |
| DeepSeek alone | 3 | 29 | 16 | 23 | 27.291 | 10754 | 69501 | — |
| Qwen3.8 alone | 1 | 29 | 13 | 17 | 23.454 | 2504 | 81919 | — |
| Qwen3.8 alone | 2 | 29 | 9 | 16 | 26.001 | 2366 | 77194 | — |
| Qwen3.8 alone | 3 | 29 | 5 | 14 | 22.363 | 2763 | 92378 | — |
| Qwen3.6 MTP alone | 1 | 29 | 8 | 11 | 20.376 | 812 | 96446 | — |
| Qwen3.6 MTP alone | 2 | 29 | 5 | 8 | 19.175 | 857 | 100434 | — |
| Qwen3.6 MTP alone | 3 | 29 | 7 | 9 | 20.509 | 914 | 106472 | — |
| Qwen3.8 writes, DeepSeek reviews | 1 | 29 | 13 | 21 | 26.318 | 7360 | 76348 | — |
| Qwen3.8 writes, DeepSeek reviews | 2 | 29 | 11 | 21 | 25.94 | 9813 | 73344 | — |
| Qwen3.8 writes, DeepSeek reviews | 3 | 29 | 13 | 19 | 26.183 | 11792 | 84328 | — |
| Qwen3.8 writes, Qwen3.6 MTP reviews | 1 | 29 | 13 | 19 | 26.189 | 4570 | 77764 | — |
| Qwen3.8 writes, Qwen3.6 MTP reviews | 2 | 29 | 11 | 19 | 25.75 | 4600 | 77194 | — |
| Qwen3.8 writes, Qwen3.6 MTP reviews | 3 | 29 | 7 | 12 | 20.328 | 5546 | 91146 | — |
| Qwen3.6 MTP writes, Qwen3.8 reviews | 1 | 29 | 10 | 14 | 23.834 | 2515 | 91906 | — |
| Qwen3.6 MTP writes, Qwen3.8 reviews | 2 | 29 | 9 | 13 | 22.229 | 2069 | 93680 | — |
| Qwen3.6 MTP writes, Qwen3.8 reviews | 3 | 29 | 10 | 15 | 22.078 | 2860 | 107451 | — |
| DeepSeek writes, Qwen3.8 reviews | 1 | 29 | 22 | 29 | 29.0 | 15526 | 57306 | — |
| DeepSeek writes, Qwen3.8 reviews | 2 | 29 | 19 | 26 | 28.61 | 12900 | 51444 | — |
| DeepSeek writes, Qwen3.8 reviews | 3 | 29 | 18 | 26 | 28.389 | 17712 | 74224 | — |
| DeepSeek writes, DeepSeek reviews | 1 | 29 | 20 | 27 | 27.972 | 20491 | 92032 | — |
| DeepSeek writes, DeepSeek reviews | 2 | 29 | 21 | 27 | 28.533 | 13254 | 62077 | — |
| DeepSeek writes, DeepSeek reviews | 3 | 29 | 22 | 25 | 28.171 | 13978 | 61584 | — |
| Qwen3.6 MTP writes, DeepSeek reviews | 1 | 29 | 10 | 16 | 23.553 | 9545 | 92401 | — |
| nav DeepSeek (llama.cpp) + driver Qwen3.8 | 1 | 29 | 14 | 21 | 25.068 | 7598 | 152910 | 28505 / 124405 |
| nav DeepSeek (llama.cpp) + driver Qwen3.8 | 2 (partial) | 15 | 11 | 13 | — | 2914 | — | — |
| nav DeepSeek (KT) + driver DeepSeek (KT) | 1 | 29 | 20 | 26 | 27.986 | 13748 | 150939 | 24397 / 126542 |
| nav DeepSeek (KT) + driver DeepSeek (KT) | 2 | 29 | 19 | 26 | 28.631 | 19648 | 150312 | 25312 / 125000 |
| nav DeepSeek (KT) + driver DeepSeek (KT) | 3 | 29 | 20 | 25 | 27.88 | 13362 | 150821 | 26541 / 124280 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | 1 | 29 | 18 | 25 | 28.108 | 25062 | 165678 | 26873 / 138805 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | 2 | 29 | 20 | 26 | 27.745 | 14162 | 119780 | 24788 / 94992 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | 3 | 29 | 18 | 25 | 28.083 | 18465 | 123121 | 26324 / 96797 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 1 | 29 | 21 | 23 | 27.906 | 34307 | 240306 | 57445 / 182861 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 2 | 29 | 22 | 24 | 27.708 | 28028 | 241745 | 56627 / 185118 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 3 | 29 | 21 | 25 | 28.34 | 33820 | 284791 | 59593 / 225198 |
| nav DeepSeek (KT) + driver Qwen3.8 | 1 | 29 | 13 | 20 | 24.802 | 7819 | 146873 | 27700 / 119173 |
| nav DeepSeek (KT) + driver Qwen3.8 | 2 | 29 | 13 | 22 | 27.138 | 13198 | 164487 | 28460 / 136027 |
| nav DeepSeek (KT) + driver Qwen3.8 | 3 | 29 | 13 | 21 | 26.073 | 9139 | 155426 | 26437 / 128989 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 1 | 29 | 16 | 19 | 24.885 | 16813 | 257938 | 57321 / 200617 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 2 | 29 | 18 | 21 | 26.125 | 17028 | 306383 | 59943 / 246440 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 3 | 29 | 19 | 23 | 26.444 | 16340 | 314629 | 60249 / 254380 |
| nav DeepSeek (KT) + driver Qwen3.6 MTP | 1 | 29 | 7 | 14 | 21.945 | 5954 | 217529 | 29201 / 188328 |
| nav Qwen3.8 + driver DeepSeek (KT) | 1 | 29 | 18 | 25 | 27.702 | 12255 | 123948 | 22946 / 101002 |
| nav Qwen3.8 + driver DeepSeek (KT) | 2 | 29 | 21 | 28 | 28.667 | 11335 | 180588 | 24735 / 155853 |
| nav Qwen3.8 + driver DeepSeek (KT) | 3 | 29 | 20 | 25 | 27.815 | 22266 | 153453 | 25243 / 128210 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 1 | 29 | 19 | 24 | 27.625 | 37269 | 348162 | 64852 / 283310 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 2 | 29 | 23 | 28 | 28.833 | 23587 | 245349 | 60837 / 184512 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 3 | 29 | 22 | 26 | 27.576 | 26047 | 288791 | 65925 / 222866 |
| nav Qwen3.8 + driver Qwen3.8 | 1 | 29 | 10 | 16 | 24.034 | 6698 | 200206 | 31049 / 169157 |
| nav Qwen3.8 + driver Qwen3.8 | 2 | 29 | 12 | 21 | 25.674 | 6010 | 177599 | 30147 / 147452 |
| nav Qwen3.8 + driver Qwen3.8 | 3 | 29 | 13 | 18 | 23.613 | 5962 | 177930 | 24696 / 153234 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 1 | 29 | 13 | 21 | 26.853 | 10692 | 304308 | 63686 / 240622 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 2 | 29 | 16 | 19 | 26.593 | 14201 | 325490 | 69989 / 255501 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 3 | 29 | 22 | 25 | 28.342 | 13234 | 301561 | 64806 / 236755 |
| nav Qwen3.8 + driver Qwen3.6 MTP | 1 | 29 | 6 | 11 | 21.937 | 3000 | 219075 | 29499 / 189576 |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | 1 | 29 | 20 | 26 | 27.655 | 9774 | 143470 | 29530 / 113940 |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | 2 | 29 | 18 | 21 | 27.609 | 15162 | 137333 | 27501 / 109832 |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | 3 | 29 | 16 | 22 | 25.615 | 13560 | 122672 | 26896 / 95776 |
| nav Qwen3.6 MTP + driver Qwen3.8 | 1 | 29 | 11 | 16 | 23.278 | 4743 | 168557 | 41436 / 127121 |
| nav Qwen3.6 MTP + driver Qwen3.8 | 2 | 29 | 12 | 16 | 24.337 | 3602 | 122645 | 25626 / 97019 |
| nav Qwen3.6 MTP + driver Qwen3.8 | 3 | 29 | 8 | 10 | 22.273 | 4109 | 138606 | 28796 / 109810 |
| nav Qwen3.6 MTP + driver Qwen3.6 MTP | 1 | 29 | 4 | 9 | 19.148 | 2704 | 210776 | 45997 / 164779 |

## Per task

Solo columns: seeds solved at pass@2 (DeepSeek: seeds 2,3; its seed 1 lost 23 tasks to a host reset). Other columns, seed 1: 2 = solved on attempt 1, 1 = on attempt 2, 0 = failed.

| task | lang | DS solo | Q8 solo | Q6 solo | Q8+rDS | Q8+rQ6 | Q6+rQ8 | DS+rQ8 | DS+rDS | Q6+rDS | PAIR | DS>DS | DS>DS keep | DS>DS tdd | PAIR-KT | DS>Q8 tdd | DS>Q6 | Q8>DS | Q8>DS tdd | Q8>Q8 | Q8>Q8 tdd | Q8>Q6 | Q6>DS | Q6>Q8 | Q6>Q6 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sh_access_log | bash | 2/2 | 0/3 | 1/3 | 2 | 2 | 2 | 2 | 2 | 1 | 2 | 0 | 0 | 2 | 0 | 2 | 0 | 0 | 2 | 0 | 1 | 1 | 2 | 0 | 0 |
| sh_csv_col | bash | 1/2 | 1/3 | 0/3 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1 | 1 | 1 | 0 | 0 | 2 | 1 | 0 | 0 | 0 | 0 | 2 | 0 | 0 |
| sh_e_ext_count | bash | 2/2 | 3/3 | 3/3 | 1 | 1 | 2 | 2 | 0 | 2 | 2 | 2 | 1 | 2 | 2 | 2 | 1 | 2 | 2 | 2 | 2 | 1 | 2 | 2 | 2 |
| sh_e_lowercase | bash | 2/2 | 2/3 | 1/3 | 0 | 2 | 2 | 2 | 2 | 1 | 2 | 2 | 2 | 0 | 2 | 2 | 1 | 1 | 2 | 1 | 2 | 2 | 2 | 2 | 0 |
| sh_e_replace | bash | 2/2 | 2/3 | 0/3 | 1 | 2 | 0 | 1 | 2 | 0 | 0 | 2 | 1 | 2 | 2 | 0 | 0 | 0 | 2 | 0 | 1 | 0 | 1 | 1 | 0 |
| sh_env_export | bash | 1/2 | 1/3 | 0/3 | 0 | 0 | 0 | 2 | 1 | 0 | 0 | 2 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0 | 2 | 0 | 0 |
| sh_retry | bash | 0/2 | 0/3 | 2/3 | 2 | 1 | 0 | 2 | 0 | 0 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0 | 0 | 0 | 0 |
| sh_rotate | bash | 2/2 | 2/3 | 2/3 | 2 | 2 | 2 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0 | 1 | 2 | 0 | 2 | 1 | 1 | 0 | 0 | 1 |
| sh_wordfreq | bash | 2/2 | 1/3 | 2/3 | 1 | 0 | 2 | 2 | 2 | 2 | 1 | 0 | 2 | 2 | 2 | 2 | 1 | 2 | 2 | 2 | 0 | 0 | 2 | 2 | 0 |
| kt_fix_money | kotlin | 1/2 | 2/3 | 1/3 | 1 | 2 | 2 | 1 | 1 | 1 | 0 | 2 | 2 | 2 | 1 | 1 | 2 | 2 | 2 | 0 | 2 | 1 | 1 | 2 | 0 |
| kt_lru | kotlin | 2/2 | 1/3 | 2/3 | 2 | 0 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 1 | 2 | 2 | 2 | 2 | 0 | 1 | 0 | 2 | 2 | 1 |
| kt_render | kotlin | 2/2 | 3/3 | 1/3 | 1 | 1 | 1 | 2 | 2 | 1 | 1 | 2 | 2 | 2 | 1 | 2 | 0 | 1 | 2 | 1 | 2 | 1 | 2 | 0 | 0 |
| kt_tokens | kotlin | 2/2 | 2/3 | 0/3 | 2 | 2 | 0 | 2 | 2 | 0 | 2 | 1 | 2 | 2 | 1 | 2 | 0 | 2 | 2 | 0 | 2 | 0 | 2 | 0 | 1 |
| py_apply_patch | python | 1/2 | 0/3 | 0/3 | 0 | 0 | 0 | 1 | 2 | 1 | 2 | 1 | 2 | 2 | 1 | 2 | 0 | 2 | 1 | 0 | 0 | 0 | 2 | 0 | 0 |
| py_async_limit | python | 2/2 | 2/3 | 1/3 | 2 | 1 | 0 | 2 | 2 | 0 | 2 | 2 | 2 | 2 | 1 | 2 | 0 | 2 | 2 | 0 | 1 | 0 | 2 | 2 | 2 |
| py_cron_next | python | 2/2 | 2/3 | 2/3 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 1 | 1 | 2 | 0 | 2 | 2 | 2 | 2 | 0 |
| py_e_config_merge | python | 2/2 | 3/3 | 3/3 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 |
| py_e_duration | python | 0/2 | 2/3 | 0/3 | 2 | 0 | 0 | 2 | 1 | 0 | 1 | 1 | 0 | 2 | 2 | 0 | 0 | 1 | 2 | 2 | 0 | 0 | 1 | 0 | 0 |
| py_e_fix_paginate | python | 2/2 | 3/3 | 3/3 | 2 | 2 | 2 | 2 | 2 | 2 | 1 | 2 | 2 | 0 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 |
| py_e_flatten | python | 1/2 | 0/3 | 0/3 | 0 | 0 | 0 | 2 | 2 | 0 | 2 | 2 | 0 | 2 | 0 | 1 | 0 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| py_e_logstats | python | 2/2 | 3/3 | 2/3 | 0 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 |
| py_expr_eval | python | 1/2 | 0/3 | 0/3 | 0 | 0 | 0 | 2 | 1 | 0 | 0 | 1 | 1 | 2 | 0 | 2 | 0 | 1 | 2 | 1 | 1 | 0 | 2 | 1 | 0 |
| py_fix_lru | python | 2/2 | 3/3 | 1/3 | 2 | 2 | 0 | 2 | 2 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 1 |
| py_fix_merge_intervals | python | 2/2 | 2/3 | 0/3 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 2 | 2 | 2 | 0 | 2 | 0 | 2 | 2 | 1 | 1 | 0 | 2 | 1 | 0 |
| py_grid_route | python | 2/2 | 1/3 | 1/3 | 1 | 0 | 1 | 2 | 2 | 2 | 1 | 2 | 2 | 2 | 0 | 0 | 1 | 2 | 1 | 2 | 2 | 2 | 2 | 2 | 1 |
| py_ini_interp | python | 1/2 | 3/3 | 0/3 | 2 | 2 | 1 | 1 | 2 | 2 | 0 | 2 | 2 | 0 | 0 | 0 | 0 | 2 | 0 | 1 | 2 | 0 | 0 | 1 | 0 |
| py_semver_range | python | 2/2 | 1/3 | 0/3 | 0 | 1 | 0 | 2 | 1 | 0 | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 2 | 1 | 1 | 0 | 0 | 2 | 0 | 0 |
| py_shell_split | python | 2/2 | 0/3 | 0/3 | 1 | 1 | 0 | 2 | 1 | 0 | 0 | 2 | 2 | 0 | 1 | 0 | 0 | 2 | 1 | 0 | 2 | 0 | 1 | 1 | 0 |
| py_typed_load | python | 1/2 | 2/3 | 0/3 | 2 | 2 | 0 | 1 | 2 | 0 | 2 | 1 | 1 | 2 | 2 | 1 | 1 | 2 | 2 | 2 | 0 | 0 | 1 | 0 | 0 |

## Tests-first (V4, `--tests-first`)

The navigator writes a test file after the plan; the driver fixes against it (up to 2 turns) before the real
tests. "Pass on ref": the navigator's tests pass on the task's reference solution, so they are correct. The nav-test
columns count attempts that produced a file.

| setup | seed | tasks | nav tests pass on ref | nav tests pass first try | nav tests pass after fixes | tdd fix turns | pass@2 (nav tests valid) | pass@2 (nav tests wrong) |
|---|---|---|---|---|---|---|---|---|
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 1 | 29 | 8/29 | 8/36 | 15/36 | 52 | 7/8 | 16/21 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 2 | 29 | 6/29 | 5/34 | 9/34 | 55 | 5/6 | 19/23 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 3 | 29 | 6/29 | 7/37 | 10/37 | 57 | 6/6 | 19/23 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 1 | 29 | 10/29 | 11/38 | 14/38 | 52 | 9/10 | 10/19 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 2 | 29 | 6/29 | 10/39 | 11/39 | 57 | 4/6 | 17/23 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 3 | 29 | 10/29 | 7/39 | 9/39 | 62 | 8/10 | 15/19 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 1 | 29 | 6/29 | 8/39 | 12/39 | 59 | 5/6 | 19/23 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 2 | 29 | 6/29 | 6/35 | 6/35 | 58 | 6/6 | 22/23 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 3 | 29 | 7/29 | 7/36 | 10/36 | 56 | 7/7 | 19/22 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 1 | 29 | 12/29 | 9/43 | 16/43 | 62 | 8/12 | 13/17 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 2 | 29 | 6/29 | 8/41 | 9/41 | 65 | 5/6 | 14/23 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 3 | 29 | 7/29 | 6/36 | 9/36 | 57 | 7/7 | 18/22 |

## Combinations available in this environment

Hardware limits: one DeepSeek at a time (KTransformers holds ~400 GiB RAM, llama.cpp ~190 GiB of page cache); KT on
GPU 0 serves 2 requests at once; Qwen3.8-27B on GPU 2 (:8086), Qwen3.6-35B-A3B MTP on GPU 3 (:8085), one slot each;
GPU 1 (3090 Ti) is kept idle (host-hang test). Coder-Next is not on disk. So 3 models x 2 roles = 9 navigator:driver pairs, each in
non-thinking mode (thinking variants below).

| navigator \ driver | DeepSeek (KT) | Qwen3.8 | Qwen3.6 MTP |
|---|---|---|---|
| DeepSeek (KT) | s1 26/29 done; s2 26/29 done; s3 25/29 done | s1 20/29 done; s2 22/29 done; s3 21/29 done; s1 llama.cpp 21/29 done; s2 llama.cpp 13/15 paused | s1 14/29 done |
| Qwen3.8 | s1 25/29 running; s2 28/29 done; s3 25/29 done | s1 16/29 done; s2 21/29 done; s3 18/29 done | s1 11/29 done |
| Qwen3.6 MTP | s1 26/29 done; s2 21/29 done; s3 22/29 done | s1 16/29 done; s2 16/29 done; s3 10/29 done | s1 9/29 done |

Stream A (`tmp_pair_queue_ds.sh`): DeepSeek-bound pairs, seed 1 of each first, then seeds 2,3. Stream B
(`tmp_pair_matrix.sh`): Qwen-only pairs, same order. Each model keeps its solo-eval sampling in either role
(DeepSeek temperature 1, top_p 1; Qwens 0.7 / 0.8 / top_k 20 / presence 1.5), thinking off, as in all earlier runs.
Times of runs that overlap are not comparable with solo times (stream A's Qwen turns wait for stream B's);
pass rates are.

## Joined tasks, seed 1 (Nov 26)

6 composite tasks (stack/eval/tasks-joined: each joins 3 burnish tasks into one module or script plus a part that uses
them together, with the parts' own tests plus integration tests; 28-71 hidden tests per task), the four best
DeepSeek-written setups, seed 1 only (user: stop after s1 of all 4, then decide). Launcher stack/scripts/tmp_joined.sh;
results: burnish results/*-joined-s1.json (solo, review), LLM_ROOT/results/pair-eval-joined/ (pairs).

| setup | pass@1 of 6 | pass@2 of 6 | quality | time | min per solved task |
|---|---|---|---|---|---|
| DeepSeek alone | 0 | 1 | 0.857 | 131 min | 131 |
| DeepSeek + Qwen3.8 review | 2 | 3 | 0.937 | 276 min | 92 |
| nav DS + driver DS | 1 | 3 | **0.982** | 329 min | 110 |
| nav Qwen3.8 + driver DS | 1 | 2 | 0.906 | 171 min | 86 |
| DeepSeek + DeepSeek review | running (started Nov 26 23:56; kt_cache_render +, py_patcher --, py_release --) | | | | |

Per task (attempts: + passed, - failed; last attempt's hidden tests):

| task | DeepSeek alone | DS + Qwen3.8 review | nav DS + driver DS | nav Qwen3.8 + driver DS |
|---|---|---|---|---|
| kt_cache_render | -+ | + | + | + |
| py_patcher | -- 25/29 | -+ | -+ | -- 28/29 |
| py_release | -- 26/28 | -- 25/28 | -- 26/28 | -- 27/28 |
| py_scheduler | -- 18/28 | + | -+ | -+ |
| sh_log_report | -- 40/41 | -- 38/41 | -- 40/41 | -- usage error |
| sh_ops | -- usage error | -- fixture parse error | -- 70/71 | -- runtime error |

Readout (one seed, 6 tasks: indicative only; times overlap, since two runs shared KT's slots most of the time):
- The harder tasks separate the second look from solo far more than the 29 small ones: +2 solved of 6 and +0.05-0.125
  quality for review and the DS pair; nobody solves py_release or sh_log_report, and near misses (one test short) are
  common, so quality carries most of the signal here.
- DS + Qwen3.8 review and the DS>DS pair solve the same 3 tasks; review more often on the first attempt (2 vs 1) and at
  lower cost per solved task (92 vs 110 min); the pair comes closer on the failures (quality 0.982 vs 0.937, sh_ops
  70/71 vs an error).
- The Qwen3.8 navigator helps DeepSeek less on joined tasks (2 solved, 0.906), unlike on the small tasks, where it was
  level with the DS navigator.

## Joined tasks 2, seed 1 (Nov 26-27)

6 more composite tasks (stack/eval/tasks-joined2: py_splitter, py_table, py_build, sh_files, sh_net, kt_booking; 18-60
hidden tests per task), built like tasks-joined. Each reference passes its tests, and the tests catch every planted bug
that changes behaviour. Seed 1 of DeepSeek alone, DS + Qwen3.8 review, the DS>DS pair, and (new on joined tasks)
DS + DeepSeek review (reviewer on KT :8080, no thinking, temperature 0.2, 600 tokens, as in matrix #2). Launchers
stack/scripts/tmp_joined2.sh, tmp_joined_rds.sh; results: burnish results/*-joined2-s1.json (solo, review),
LLM_ROOT/results/pair-eval-joined2/ (pairs, queue logs). Joined2 complete 2026-11-27 01:36.

| setup | pass@1 of 6 | pass@2 of 6 | quality | time | min per solved task |
|---|---|---|---|---|---|
| DeepSeek alone | 1 | 3 | 0.947 | 104 min | 35 |
| DeepSeek + Qwen3.8 review | 1 | 4 | **0.983** | 216 min | 54 |
| nav DS + driver DS | 2 | **5** | **0.964** | 209 min | 42 |
| DeepSeek + DeepSeek review | 1 | 3 | 0.939 | 210 min | 70 |

Per task (attempts: + passed, - failed; last attempt's hidden tests):

| task | DeepSeek alone | DS + Qwen3.8 review | nav DS + driver DS | DS + DeepSeek review |
|---|---|---|---|---|
| kt_booking | + | -+ | + | -- 14/19 |
| py_build | -+ | -+ | -+ | -- 17/18 |
| py_splitter | -+ | -- 20/21 | + | -- 20/21 |
| py_table | -- 19/20 | -+ | -+ | -+ |
| sh_files | -- runtime error (52/57) | -- 54/57 | -+ | + |
| sh_net | -- 49/60 | + | -- 47/60 | -+ |

Readout (one seed):
- These tasks are easier than tasks-joined for DeepSeek alone (3 of 6 solved, quality 0.947, vs 1 and 0.857), so the
  gap to a second look is smaller in quality but not in solved tasks: the DS>DS pair solves 5 of 6, +2 over solo
  (py_table, sh_files, both on the 2nd attempt), at 2x the time.
- DS + Qwen3.8 review solves 4 of 6 with the best quality (0.983): the only setup to solve sh_net (60/60, first
  attempt), but it lost py_splitter (20/21), which DeepSeek alone and the pair solved, and needed the retry on
  kt_booking, which both solved first time. Pair and review differ in which tasks they solve, not in how many.
- DS + DeepSeek review solves 3 of 6 (0.939), level with DeepSeek alone in count, but a different 3: it solves
  py_table, sh_files (the only first-attempt solve) and sh_net, and loses kt_booking, py_build and py_splitter, all
  three solved by DeepSeek alone, two of them by a single hidden test. Its reviews on those attempts flag edge cases
  (overflow bounds, trailing empty fields, backslash continuations); burnish does not store the pre-review draft, so
  whether a revision broke a passing draft cannot be checked offline.

Pooled over the 12 joined tasks (tasks-joined + tasks-joined2, seed 1), complete setups only:

| setup | pass@1 of 12 | pass@2 of 12 | quality | time | min per solved task |
|---|---|---|---|---|---|
| DeepSeek alone | 1 | 4 | 0.902 | 235 min | 59 |
| nav DS + driver DS | 3 | **8** | **0.973** | 538 min | 67 |
| DeepSeek + Qwen3.8 review | 3 | 7 | 0.960 | 492 min | 70 |
| DeepSeek + DeepSeek review | old set running (joined2: 1 / 3 of 6, 0.939) | | | | |

## Hidden-test audit (Nov 26)

How strong are burnish's hidden tests (5-25 per task)? `stack/scripts/tmp_audit_hidden_tests.py` re-ran all 1,272
distinct stored solutions that passed them against the navigators' test files that pass the reference solution
(written from the task text alone, as in EvalPlus; kept only if the reference passes them twice in a row, since some
write to fixed /tmp paths). Results: llm/results/thinking-check/hidden-test-audit.json.

- 9 of 28 audited tasks: no passing solution fails any extra test (py_e_config_merge, py_e_fix_paginate,
  py_fix_merge_intervals, py_shell_split, sh_e_ext_count, sh_env_export, sh_wordfreq, kt_render, kt_tokens).
- Real gaps, where the task text states the behaviour the hidden tests skip:
  py_e_flatten 20 of 35 passing solutions (non-string keys must raise), py_e_logstats 20 of 51 (empty message),
  py_typed_load 13 of 52 (error path of an unknown key at the root), kt_lru 10 of 57 (`contains` true for a
  null value, stated in the task).
- Mostly ambiguity, not a gap: sh_e_replace 37 of 47 fail a test of bundled flags (`-nb`), which the usage line
  `[-n] [-b]` does not promise.
- Smaller counts (1-11 solutions) in 14 other tasks are not yet sorted into gap vs ambiguity.

So pass@2 and quality are somewhat optimistic on 4-5 tasks, for every setup alike. Whether it shifts the ranking
needs the per-setup share of such solutions.

Done (user, Nov 26): checks for the 4 gaps added to burnish's hidden tests (py_e_flatten: 4 more conflicts and
`flatten({})`; py_e_logstats: empty message, whitespace-only line, Feb 30; py_typed_load: a union's own error path;
kt_lru: null values on update and eviction), all reference solutions pass. `stack/scripts/tmp_rescore.py` re-ran the
stored code of every matrix run on those tasks into `*-rescored.json` files next to the originals, which
pair_matrix.py and thinking_report.py now prefer. 37 of 62 runs lost 1-3 tasks (pass@2); DeepSeek alone lost none.

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

More (Nov 26 search, by finding, with the eval-method and statistics notes): [pair-eval-literature.md](pair-eval-literature.md).

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

## Practices to test next, in order (Nov 26)

Practices proposed for an agent's daily loop. Evidence: [L] = our eval, [L-thin] = our eval with one seed or a few
cases, [P] = papers.

| practice | evidence |
|---|---|
| One command that checks the work, fast, printing only failures, with a non-zero exit: tests, or a script whose stdout is compared with a committed expected file. The agent runs it before it reports, and the failing output goes into the next attempt | [L] the retry with test output adds +5.7 to +8.3; [P] correction works with reliable external feedback |
| A syntax and compile gate before any test: bash -n, python -m py_compile, kotlinc. It cannot leak hidden tests | [L-thin] one seed had 4 Kotlin compile errors and 2 bash syntax errors among its failed attempts |
| Shell scripts are always executed, never accepted on reading | [L] bash 5-8 of 9 where Python is 13-16 of 16 |
| For a mid-size writer, tests are written from the task text before the code | [L] tests first lifts Qwen3.8's first attempt by +4.3 to +5.3; after two attempts it is level with a strong reviewer, at 5 to 7 times the solo time |
| A review is a reason to look again, never a gate. Only a program decides pass or fail | [L] the reviewer flags 33 of 39 failing drafts and 32 of 39 passing ones |
| At most two attempts, then stop and report the output | [L] only two were measured; [L-thin] a free-running agent looped 100 debug runs |
| A reply without the complete file is asked for once more | [L] 1-2 tasks per run with the weaker writers |
| AGENTS.md holds only: the check command, the two-attempt rule, and what is never touched. Skills only for rare procedures, written by a person, 2-3 parts each | [P] SkillsBench: curated +16.4 points, model-written -1.3 |

### Fast feedback (FF): the writer gets non-leaking feedback before its attempt is scored

Like tests first, but without tests: after each draft the harness runs cheap checks that do not use the hidden tests and
hands any failure back to the writer, up to 2 free fix turns, before the hidden tests score the attempt. Levels, each
one a flag in `eval_pair.py` and the solo runner:
- FF0 gate: bash -n, python -m py_compile, kotlinc (compile only).
- FF1 gate + run: FF0, then run the program once on the task text's own example (no example: run with no input and
  catch crashes, usage errors, non-zero exits on a valid call). Shell scripts are always run.
- FF2 = FF1 + writer-written tests (tests first without a navigator), to compare with V4.

What it should show: pass@1 is the main metric (FF acts before the first scored attempt), then pass@2, quality, min per
solved task, and per attempt: was the draft caught by the gate, and did the fixed draft then pass the hidden tests.
Paired per task against the same setup without FF, bootstrap as in the headline.

Order (cheapest and most decisive first):

| # | step | answers | cost |
|---|---|---|---|
| 1 | Offline replay: run FF0 and FF1 on every stored failing attempt (all matrix and joined runs), no model calls | ceiling: how many failures are compile errors, crashes or usage errors that FF could catch at all | CPU, ~30 min |
| 2 | FF0 and FF1 on Qwen3.8 alone, 29 tasks, 3 seeds | does early feedback lift a mid-size writer, and by how much vs tests first (V4) and vs a DeepSeek reviewer | ~1 h per seed per level |
| 3 | FF1 on DeepSeek alone and on DS + Qwen3.8 review, 29 + 12 joined tasks, seed 1, then seeds 2-3 if the gain is over ~1 task | does FF replace the reviewer, or add to it; does it narrow the gap to the DS>DS pair on joined tasks | ~2-4 h per seed per setup |
| 3b | FF1 + review only when FF fails (the reviewer sees the draft and the FF output; a draft that passes FF goes straight to the hidden tests), DS + Qwen3.8 review, same tasks and seeds as 3 | does review add anything once the program has spoken, and how much reviewer time it saves; V1 does the same after a hidden-test failure | as 3, less review time |
| 4 | complete-file re-ask (once) in both runners; the pair only has --keep-unrevised, which keeps the pre-review file; same runs as 3 | the 1-2 tasks per run lost to format faults | part of 3 |
| 5 | three attempts instead of two on the best FF setup | is the two-attempt cap right once early feedback exists | one seed, ~3 h |
| 6 | AGENTS.md with the check command and the two-attempt rule, in the opencode agent eval (eval_opencode.py), with and without it | does the practice hold in a free-running agent, and does it stop debug loops | one seed per setup |

Step 1 result (offline replay, Nov 26; stack/scripts/tmp_ff_replay.py): 2,054 distinct failing attempts from all
stored solo, review and pair runs (29 tasks and both joined sets, every writer), each run through the gate:
compile (py_compile, bash -n, kotlinc), then `import` of the Python module and shellcheck -S error. Awk programs inside
bash scripts pass bash -n, so their syntax errors (awk prints them on any run) are counted apart, as what a smoke run
adds.

| failing attempts | n | caught by gate | + awk syntax on a run | share |
|---|---|---|---|---|
| Kotlin | 188 | 108 | — | 57% |
| bash | 720 | 116 | 38 | 21% |
| Python | 1,146 | 20 | — | 2% |
| DeepSeek writer | 360 | 15 | 7 | 6% |
| Qwen3.8 writer | 716 | 94 | 10 | 15% |
| Qwen3.6 MTP writer | 547 | 83 | 14 | 18% |
| all | 2,054 | 244 | 38 | 14% |

186 of the 244 gate catches were first attempts. Python failures are 85% wrong answers (the program runs and its
results differ), which only tests can catch (tests first), not a gate. Readout: the gate's ceiling is high for Kotlin
and bash and for the Qwen writers (one failure in six or seven), low for DeepSeek (22 attempts over all its runs, about
one per seed). So step 2 (Qwen3.8) is where FF can show a gain; for DeepSeek, FF0 alone cannot move the joined-task
results, and FF1 (a real run) or tests are the levels to try there.

Already covered by the matrix and not re-run: review as a hint, not a gate (the reviewer's flags do not separate failing
from passing drafts, 33/39 vs 32/39); tests first for a mid-size writer (V4).

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
