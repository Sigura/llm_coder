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
| Qwen3.8 writes, DeepSeek reviews | 2 | 29 | 12 | 22 | 25.984 | 9813 | 73344 | — |
| Qwen3.8 writes, DeepSeek reviews | 3 | 29 | 15 | 22 | 26.586 | 11792 | 84328 | — |
| Qwen3.8 writes, Qwen3.6 MTP reviews | 1 | 29 | 14 | 21 | 26.467 | 4570 | 77764 | — |
| Qwen3.8 writes, Qwen3.6 MTP reviews | 2 | 29 | 12 | 20 | 26.05 | 4600 | 77194 | — |
| Qwen3.8 writes, Qwen3.6 MTP reviews | 3 | 29 | 7 | 12 | 20.35 | 5546 | 91146 | — |
| Qwen3.6 MTP writes, Qwen3.8 reviews | 1 | 29 | 11 | 16 | 24.078 | 2515 | 91906 | — |
| Qwen3.6 MTP writes, Qwen3.8 reviews | 2 | 29 | 11 | 15 | 22.517 | 2069 | 93680 | — |
| Qwen3.6 MTP writes, Qwen3.8 reviews | 3 | 29 | 10 | 16 | 22.245 | 2860 | 107451 | — |
| DeepSeek writes, Qwen3.8 reviews | 1 | 29 | 22 | 29 | 29.0 | 15526 | 57306 | — |
| DeepSeek writes, Qwen3.8 reviews | 2 | 29 | 20 | 27 | 28.777 | 12900 | 51444 | — |
| DeepSeek writes, Qwen3.8 reviews | 3 | 29 | 18 | 26 | 28.389 | 17712 | 74224 | — |
| DeepSeek writes, DeepSeek reviews | 1 | 29 | 20 | 27 | 27.972 | 20491 | 92032 | — |
| DeepSeek writes, DeepSeek reviews | 2 | 29 | 21 | 28 | 28.7 | 13254 | 62077 | — |
| DeepSeek writes, DeepSeek reviews | 3 | 29 | 22 | 26 | 28.338 | 13978 | 61584 | — |
| Qwen3.6 MTP writes, DeepSeek reviews | 1 | 29 | 11 | 18 | 23.797 | 9545 | 92401 | — |
| nav DeepSeek (llama.cpp) + driver Qwen3.8 | 1 | 29 | 14 | 21 | 25.068 | 7598 | 152910 | 28505 / 124405 |
| nav DeepSeek (llama.cpp) + driver Qwen3.8 | 2 (partial) | 15 | 11 | 13 | — | 2914 | — | — |
| nav DeepSeek (KT) + driver DeepSeek (KT) | 1 | 29 | 20 | 26 | 27.986 | 13748 | 150939 | 24397 / 126542 |
| nav DeepSeek (KT) + driver DeepSeek (KT) | 2 | 29 | 20 | 29 | 29.0 | 19648 | 150312 | 25312 / 125000 |
| nav DeepSeek (KT) + driver DeepSeek (KT) | 3 | 29 | 20 | 25 | 27.88 | 13362 | 150821 | 26541 / 124280 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | 1 | 29 | 19 | 27 | 28.4 | 25062 | 165678 | 26873 / 138805 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | 2 | 29 | 21 | 27 | 27.87 | 14162 | 119780 | 24788 / 94992 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (keep) | 3 | 29 | 18 | 26 | 28.25 | 18465 | 123121 | 26324 / 96797 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 1 | 29 | 22 | 24 | 28.031 | 34307 | 240306 | 57445 / 182861 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 2 | 29 | 24 | 26 | 28.0 | 28028 | 241745 | 56627 / 185118 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 3 | 29 | 21 | 25 | 28.34 | 33820 | 284791 | 59593 / 225198 |
| nav DeepSeek (KT) + driver Qwen3.8 | 1 | 29 | 13 | 20 | 24.735 | 7819 | 146873 | 27700 / 119173 |
| nav DeepSeek (KT) + driver Qwen3.8 | 2 | 29 | 14 | 23 | 27.263 | 13198 | 164487 | 28460 / 136027 |
| nav DeepSeek (KT) + driver Qwen3.8 | 3 | 29 | 15 | 23 | 26.351 | 9139 | 155426 | 26437 / 128989 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 1 | 29 | 17 | 20 | 25.01 | 16813 | 257938 | 57321 / 200617 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 2 | 29 | 19 | 22 | 26.286 | 17028 | 306383 | 59943 / 246440 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 3 | 29 | 19 | 23 | 26.444 | 16340 | 314629 | 60249 / 254380 |
| nav DeepSeek (KT) + driver Qwen3.6 MTP | 1 | 29 | 7 | 14 | 22.101 | 5954 | 217529 | 29201 / 188328 |
| nav Qwen3.8 + driver DeepSeek (KT) | 1 | 29 | 18 | 26 | 27.827 | 12255 | 123948 | 22946 / 101002 |
| nav Qwen3.8 + driver DeepSeek (KT) | 2 | 29 | 21 | 28 | 28.8 | 11335 | 180588 | 24735 / 155853 |
| nav Qwen3.8 + driver DeepSeek (KT) | 3 | 29 | 20 | 26 | 27.982 | 22266 | 153453 | 25243 / 128210 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 1 | 29 | 19 | 24 | 27.847 | 37269 | 348162 | 64852 / 283310 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 2 | 29 | 23 | 29 | 29.0 | 23587 | 245349 | 60837 / 184512 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 3 | 29 | 22 | 26 | 27.709 | 26047 | 288791 | 65925 / 222866 |
| nav Qwen3.8 + driver Qwen3.8 | 1 | 29 | 10 | 16 | 24.185 | 6698 | 200206 | 31049 / 169157 |
| nav Qwen3.8 + driver Qwen3.8 | 2 | 29 | 13 | 22 | 25.841 | 6010 | 177599 | 30147 / 147452 |
| nav Qwen3.8 + driver Qwen3.8 | 3 | 29 | 13 | 19 | 23.78 | 5962 | 177930 | 24696 / 153234 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 1 | 29 | 14 | 22 | 27.152 | 10692 | 304308 | 63686 / 240622 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 2 | 29 | 16 | 20 | 26.803 | 14201 | 325490 | 69989 / 255501 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 3 | 29 | 22 | 25 | 28.309 | 13234 | 301561 | 64806 / 236755 |
| nav Qwen3.8 + driver Qwen3.6 MTP | 1 | 29 | 8 | 13 | 22.263 | 3000 | 219075 | 29499 / 189576 |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | 1 | 29 | 20 | 26 | 27.655 | 9774 | 143470 | 29530 / 113940 |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | 2 | 29 | 20 | 23 | 27.901 | 15162 | 137333 | 27501 / 109832 |
| nav Qwen3.6 MTP + driver DeepSeek (KT) | 3 | 29 | 16 | 22 | 25.748 | 13560 | 122672 | 26896 / 95776 |
| nav Qwen3.6 MTP + driver Qwen3.8 | 1 | 29 | 11 | 16 | 23.461 | 4743 | 168557 | 41436 / 127121 |
| nav Qwen3.6 MTP + driver Qwen3.8 | 2 | 29 | 12 | 17 | 24.637 | 3602 | 122645 | 25626 / 97019 |
| nav Qwen3.6 MTP + driver Qwen3.8 | 3 | 29 | 9 | 11 | 22.325 | 4109 | 138606 | 28796 / 109810 |
| nav Qwen3.6 MTP + driver Qwen3.6 MTP | 1 | 29 | 4 | 9 | 19.331 | 2704 | 210776 | 45997 / 164779 |

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
| kt_lru | kotlin | 2/2 | 3/3 | 2/3 | 2 | 2 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 1 | 2 | 2 | 2 | 2 | 0 | 1 | 2 | 2 | 2 | 1 |
| kt_render | kotlin | 2/2 | 3/3 | 1/3 | 1 | 1 | 1 | 2 | 2 | 1 | 1 | 2 | 2 | 2 | 1 | 2 | 0 | 1 | 2 | 1 | 2 | 1 | 2 | 0 | 0 |
| kt_tokens | kotlin | 2/2 | 2/3 | 0/3 | 2 | 2 | 0 | 2 | 2 | 0 | 2 | 1 | 2 | 2 | 1 | 2 | 0 | 2 | 2 | 0 | 2 | 0 | 2 | 0 | 1 |
| py_apply_patch | python | 1/2 | 0/3 | 0/3 | 0 | 0 | 0 | 1 | 2 | 1 | 2 | 1 | 2 | 2 | 1 | 2 | 0 | 2 | 1 | 0 | 0 | 0 | 2 | 0 | 0 |
| py_async_limit | python | 2/2 | 2/3 | 1/3 | 2 | 1 | 0 | 2 | 2 | 0 | 2 | 2 | 2 | 2 | 1 | 2 | 0 | 2 | 2 | 0 | 1 | 0 | 2 | 2 | 2 |
| py_cron_next | python | 2/2 | 2/3 | 2/3 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 1 | 1 | 2 | 0 | 2 | 2 | 2 | 2 | 0 |
| py_e_config_merge | python | 2/2 | 3/3 | 3/3 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 |
| py_e_duration | python | 0/2 | 2/3 | 0/3 | 2 | 0 | 0 | 2 | 1 | 0 | 1 | 1 | 0 | 2 | 2 | 0 | 0 | 1 | 2 | 2 | 0 | 0 | 1 | 0 | 0 |
| py_e_fix_paginate | python | 2/2 | 3/3 | 3/3 | 2 | 2 | 2 | 2 | 2 | 2 | 1 | 2 | 2 | 0 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 |
| py_e_flatten | python | 1/2 | 1/3 | 0/3 | 0 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 1 | 2 | 0 | 1 | 0 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| py_e_logstats | python | 2/2 | 3/3 | 3/3 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 0 | 1 | 0 | 0 | 0 | 0 | 2 | 0 | 0 |
| py_expr_eval | python | 1/2 | 0/3 | 0/3 | 0 | 0 | 0 | 2 | 1 | 0 | 0 | 1 | 1 | 2 | 0 | 2 | 0 | 1 | 2 | 1 | 1 | 0 | 2 | 1 | 0 |
| py_fix_lru | python | 2/2 | 3/3 | 1/3 | 2 | 2 | 0 | 2 | 2 | 1 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 1 |
| py_fix_merge_intervals | python | 2/2 | 2/3 | 0/3 | 1 | 0 | 0 | 2 | 2 | 0 | 0 | 2 | 2 | 2 | 0 | 2 | 0 | 2 | 2 | 1 | 1 | 0 | 2 | 1 | 0 |
| py_grid_route | python | 2/2 | 1/3 | 1/3 | 1 | 0 | 1 | 2 | 2 | 2 | 1 | 2 | 2 | 2 | 0 | 0 | 1 | 2 | 1 | 2 | 2 | 2 | 2 | 2 | 1 |
| py_ini_interp | python | 1/2 | 3/3 | 0/3 | 2 | 2 | 1 | 1 | 2 | 2 | 0 | 2 | 2 | 0 | 0 | 0 | 0 | 2 | 0 | 1 | 2 | 0 | 0 | 1 | 0 |
| py_semver_range | python | 2/2 | 1/3 | 0/3 | 0 | 1 | 0 | 2 | 1 | 0 | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 2 | 1 | 1 | 0 | 0 | 2 | 0 | 0 |
| py_shell_split | python | 2/2 | 0/3 | 0/3 | 1 | 1 | 0 | 2 | 1 | 0 | 0 | 2 | 2 | 0 | 1 | 0 | 0 | 2 | 1 | 0 | 2 | 0 | 1 | 1 | 0 |
| py_typed_load | python | 1/2 | 2/3 | 0/3 | 2 | 2 | 1 | 1 | 2 | 1 | 2 | 1 | 1 | 2 | 2 | 1 | 1 | 2 | 2 | 2 | 2 | 2 | 1 | 0 | 0 |

## Tests-first (V4, `--tests-first`)

The navigator writes a test file after the plan; the driver fixes against it (up to 2 turns) before the real
tests. "Pass on ref": the navigator's tests pass on the task's reference solution, so they are correct. The nav-test
columns count attempts that produced a file.

| setup | seed | tasks | nav tests pass on ref | nav tests pass first try | nav tests pass after fixes | tdd fix turns | pass@2 (nav tests valid) | pass@2 (nav tests wrong) |
|---|---|---|---|---|---|---|---|---|
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 1 | 29 | 8/29 | 8/36 | 15/36 | 52 | 8/8 | 16/21 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 2 | 29 | 6/29 | 5/34 | 9/34 | 55 | 6/6 | 20/23 |
| nav DeepSeek (KT) + driver DeepSeek (KT) (tdd) | 3 | 29 | 6/29 | 7/37 | 10/37 | 57 | 6/6 | 19/23 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 1 | 29 | 10/29 | 11/38 | 14/38 | 52 | 10/10 | 10/19 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 2 | 29 | 6/29 | 10/39 | 11/39 | 57 | 5/6 | 17/23 |
| nav DeepSeek (KT) + driver Qwen3.8 (tdd) | 3 | 29 | 10/29 | 7/39 | 9/39 | 62 | 8/10 | 15/19 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 1 | 29 | 6/29 | 8/39 | 12/39 | 59 | 5/6 | 19/23 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 2 | 29 | 6/29 | 6/35 | 6/35 | 58 | 6/6 | 23/23 |
| nav Qwen3.8 + driver DeepSeek (KT) (tdd) | 3 | 29 | 7/29 | 7/36 | 10/36 | 56 | 7/7 | 19/22 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 1 | 29 | 12/29 | 9/43 | 16/43 | 62 | 9/12 | 13/17 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 2 | 29 | 6/29 | 8/41 | 9/41 | 65 | 6/6 | 14/23 |
| nav Qwen3.8 + driver Qwen3.8 (tdd) | 3 | 29 | 7/29 | 6/36 | 9/36 | 57 | 7/7 | 18/22 |

## Combinations available in this environment

Hardware limits: one DeepSeek at a time (KTransformers holds ~400 GiB RAM, llama.cpp ~190 GiB of page cache); KT on
GPU 0 serves 2 requests at once; Qwen3.8-27B on GPU 2 (:8086), Qwen3.6-35B-A3B MTP on GPU 3 (:8085), one slot each;
GPU 1 (3090 Ti) is kept idle (host-hang test). Coder-Next is not on disk. So 3 models x 2 roles = 9 navigator:driver pairs, each in
non-thinking mode (thinking variants below).

| navigator \ driver | DeepSeek (KT) | Qwen3.8 | Qwen3.6 MTP |
|---|---|---|---|
| DeepSeek (KT) | s1 26/29 done; s2 29/29 done; s3 25/29 done | s1 20/29 done; s2 23/29 done; s3 23/29 done; s1 llama.cpp 21/29 done; s2 llama.cpp 13/15 paused | s1 14/29 done |
| Qwen3.8 | s1 26/29 done; s2 28/29 done; s3 26/29 done | s1 16/29 done; s2 22/29 done; s3 19/29 done | s1 13/29 done |
| Qwen3.6 MTP | s1 26/29 done; s2 23/29 done; s3 22/29 done | s1 16/29 done; s2 17/29 done; s3 11/29 done | s1 9/29 done |

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
