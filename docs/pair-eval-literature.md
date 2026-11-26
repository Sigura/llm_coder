# Pair programming eval: literature against our findings

Files: [pair-eval-winners.md](pair-eval-winners.md) (winners), [pair-eval-report.md](pair-eval-report.md) (setup,
tables), [pair-eval-findings.md](pair-eval-findings.md) (per run), [thinking-check.md](thinking-check.md) (thinking
on the checking role).

Our findings these are checked against (details in the files above):
- A second look (reviewer or navigator) adds 2-3 of 29 tasks to DeepSeek alone; the seven best DeepSeek setups are
  level on quality (0.970-0.990) and differ in cost (9.4-21 min per solved task). Weaker writers (Qwen3.8) gain more.
- Without thinking the DeepSeek checker flags nearly every draft (balanced accuracy 0.50); with thinking false alarms
  drop (0.60) at ~10x the time, and many verdicts run out of tokens at 16k.
- The Qwen3.8 test writer: 6 of 29 test files valid on the reference without thinking, 15-17 with; most no-thinking
  failures were harness/format mistakes the prompt invited, so the prompt was fixed (Nov 26).
- Tests first gives the best pass@1 but not a better pass@2, at 2x the cost; the driver solves most tasks even with
  wrong navigator tests.
- Gains come from the test feedback of attempt 2 more than from critique.
- Eval method: pass@2 saturates at 25-29 of 29, seed noise (2-4 tasks) exceeds the gaps, hence quality (hidden-test
  share), pass@1, cost and paired per-task comparison (Nov 26); joined tasks and --batch N to separate setups.

## Earlier search: pair and multi-agent coding (from pair-eval-report.md)

| work | split | result | takeaway |
|---|---|---|---|
| [Aider architect mode](https://aider.chat/2024/09/26/architect.html) (2024) | planner + editor | o1-preview alone 79.7, + DeepSeek/o1-mini editor 85.0; Sonnet+Sonnet 80.5 vs 77.4 alone | the best evidence for navigator/driver: a reasoning planner, an editor that only applies the plan, whole-file format |
| [Self-Repair, Olausson et al.](https://arxiv.org/abs/2306.09896) (ICLR 2024) | coder + feedback model | modest gains; often no better than resampling at equal cost; a stronger feedback model helps | the strong model should critique, the weak one fix; sampling is a strong baseline |
| [Planner-coder gap](https://arxiv.org/abs/2510.10460) (2025) | planner -> coder | the gap causes 75.3% of failures; a monitor + rephrased plans recover 40-89% | matches our pair losses on tasks Qwen solves alone |
| [MAST taxonomy](https://arxiv.org/pdf/2503.13657.pdf) (2025) | failure modes | multi-agent gains over one agent are often small; incomplete verification, ignoring the partner | force point-by-point replies to review items, always run the tests |
| [Capable models outgrow collaboration](https://ubicomplab.cs.washington.edu/publications/Zhihan_NatureMI2026/) (Nat. Mach. Intell. 2026) | 260 configs, 6 benchmarks | the solo model's capability predicted whether coordination helps in 94% of validation configs | DeepSeek (24.7) is likely past the point where a partner helps; Qwen3.8 (16.7) is not |
| [AgentCoder](https://arxiv.org/abs/2312.13010), [MapCoder](https://arxiv.org/pdf/2405.11403.pdf), [Self-Collaboration](https://arxiv.org/abs/2304.07590) | test writer / multi-stage | high self-reported HumanEval numbers; an independent study reports poor transfer to open models (not verified) | test-first is worth one trial, not more |
| [Reflexion](https://arxiv.org/abs/2303.11366), [Self-Debug](https://arxiv.org/abs/2304.05128) | one model + execution feedback | gains come from test feedback, not from self-critique alone | our attempt 2 already uses test feedback |

## Nov 26 search

Abstract pages only (full papers not read), so numbers beyond those quoted are unverified. "Ours" = our finding it
bears on.

### Checkers and thinking

| work | verified result | ours |
|---|---|---|
| [Huang et al. 2023](https://arxiv.org/abs/2310.01798), [Kamoi et al. 2024](https://arxiv.org/abs/2406.01297) | LLMs fail to self-correct without external feedback; self-correction works when reliable external feedback exists | agrees: the checker alone is near chance (0.50), tests drive the gains |
| [Tyen et al. 2023](https://arxiv.org/abs/2311.08516) | models fail mainly at locating errors; given the location they fix them | agrees: detection is the weak step, test failures give the location |
| [CriticGPT 2024](https://arxiv.org/abs/2407.00215) | a trained critic's code critiques preferred over humans' 63%; critics hallucinate bugs | partly against: a trained critic is useful; agrees that invented bugs are the known failure |
| [CodeJudgeBench 2025](https://arxiv.org/abs/2507.10535) | thinking judges significantly beat non-thinking ones on judging code, repairs and unit tests; judges stay order-sensitive | agrees with fewer false alarms with thinking (10/10 -> 1-2/10) |
| [Generative Verifiers 2024](https://arxiv.org/abs/2408.15240), [JudgeLRM 2025](https://arxiv.org/abs/2504.00050) | reasoning before the verdict and voting over verdicts beat plain judges (GSM8K best-of-N 73% -> 93.4%) | agrees; suggests voting over short verdicts instead of one 16k-token thought |
| [Snell et al. 2024](https://arxiv.org/abs/2408.03314), [Chen et al. 2024, overthinking](https://arxiv.org/abs/2412.21187) | spend test-time compute per prompt by difficulty (>4x more efficient than best-of-N); long reasoning on easy items wastes compute | agrees with ~10x cost for a small gain: think only on uncertain or failing drafts |

### LLM-written tests and tests first

| work | verified result | ours |
|---|---|---|
| [UTGen 2025](https://arxiv.org/abs/2502.01619), [CodeRM 2025](https://arxiv.org/abs/2501.01054) | generated tests are noisy (wrong expected outputs); more tests and validating edits across tests helps | agrees: 6-17 of 29 test files valid; the driver must tolerate wrong tests, as ours does |
| [Class-level test suites 2026](https://arxiv.org/abs/2609.24341) | whether generated tests run at all varies strongly by setup; gate on that first | agrees: most no-thinking failures were harness/format errors, not logic |
| [WebApp1K, tests as prompt 2025](https://arxiv.org/abs/2505.09027) | instruction following matters more than coding skill; instructions get lost in long prompts | agrees with the prompt fix (harness instructions) |
| [TDD for code generation 2024](https://arxiv.org/abs/2402.13521), [SWT-bench 2024](https://arxiv.org/abs/2406.12952) | correct tests in the prompt raise success; generated tests as a filter double the precision of fixes | partly: our navigator tests are mostly wrong, so tests first buys pass@1 only, at 2x the cost |
| [TestGenEval 2024](https://arxiv.org/abs/2410.00752) | best model 35.2% coverage on real repos | agrees that test writing is hard |

Not found: a controlled thinking vs no-thinking study of test-file validity, the cost of tests-first pairs, or
strong vs weak partners in a pair: these remain our own findings.

### Eval method

| work | verified result | ours |
|---|---|---|
| [Miller 2024, error bars](https://arxiv.org/abs/2411.00640) | treat questions as a sample; formulas for comparing two models and planning evals | supports paired per-task comparison and intervals |
| [Kapoor et al. 2024, AI agents that matter](https://arxiv.org/abs/2407.01502) | accuracy-only benchmarks reward needlessly costly agents; optimise cost and accuracy jointly | supports min per solved task |
| [EvalPlus 2023](https://arxiv.org/abs/2305.01210), [SWE-Bench+ 2024](https://arxiv.org/abs/2410.06992) | more hidden tests cut pass@k 19-29% and change rankings; weak tests and leakage inflated SWE-Agent 12.5% -> 4.0% | supports partial credit; warns that our hidden tests could be weak too |
| [Non-determinism 2024](https://arxiv.org/abs/2408.04667) | up to 15% accuracy spread across runs with "deterministic" settings | agrees with our seed noise (2-4 tasks) |
| [τ-bench 2024](https://arxiv.org/abs/2406.12045) | pass^k (success in all k trials) drops fast (gpt-4o retail pass^8 < 25%) | suggests adding pass^3 (solved in all 3 seeds) |
| [LiveCodeBench](https://arxiv.org/abs/2403.07974), [BigCodeBench](https://arxiv.org/abs/2406.15877), [ClassEval](https://arxiv.org/abs/2308.01861) (2023-2024) | small function benchmarks saturate; compositional / class-level tasks score far lower (BigCodeBench best ~60% vs humans ~97%) | supports the joined tasks |
| [Multi-task inference 2024](https://arxiv.org/abs/2402.11597) vs [Lost in multi-turn 2025](https://arxiv.org/abs/2505.06120) | 2-3 tasks in one prompt: up to +12% and 1.46x faster (NLP tasks); multi-turn context: -39% on average | mixed for --batch N: measure batch 1 vs N on the same setup |

### Statistics for our eval

Power (our arithmetic, not from the papers): at ~90% solved, 29 tasks give a standard error of ~1.6 tasks (95%
interval ±3); a sign test needs at least 6 of 6 discordant tasks going one way (p 0.031). So differences of 1-2 tasks
cannot be ranked; more tasks (not more seeds) give power: ~100 tasks to resolve ~3 points. Seeds should be averaged
per task and tasks resampled (paired bootstrap), not seed-task cells. No work was found on replays (stored drafts)
as a stand-in for full seeds; check a few replay verdicts against end-to-end runs before relying on them.

## What it means for us

- Keep test feedback as the core; a prompted checker adds little on its own. If a checker is wanted cheaper or
  better: vote over 3 short verdicts, think only on failing or uncertain drafts, or a trained judge (not tested).
- Tests first: gate the navigator's tests on "does it run on the reference / a stub" before the driver sees them, and
  keep harness instructions explicit (done for the prompt, Nov 26).
- Scoring: keep quality, pass@1, cost and the paired comparison; add pass^3 (solved in all 3 seeds) and a paired
  bootstrap interval over tasks; do not rank setups 1-2 tasks apart.
- Power comes from more tasks, not more seeds: the joined tasks help; --batch N needs a batch 1 vs N check on the
  same setup before its numbers are compared.
- Audit our hidden tests for weakness (EvalPlus, SWE-Bench+): a weak test suite inflates every setup.
