# Fast feedback (FF) study: results and findings (Nov 26-28)

Files: [pair-eval-winners.md](pair-eval-winners.md) (winners), [pair-eval-report.md](pair-eval-report.md) (matrix,
joined tasks, practices), this file (FF). State 2026-11-28 15:40; step 3 still running (see the end).

## Summary

- **Turn the compile gate on for every writer.** bash -n (+ shellcheck -S error), python -m py_compile (+ import),
  kotlinc; on failure the writer gets the error and up to 2 fix turns before the tests. Qwen3.8 alone: +2.7 tasks of
  29 on every seed (net [95% CI] +2.7 [+1.0, +4.3]), never loses a task, +4% time. No false alarms: every reference
  solution passes it.
- **The smoke run is not worth its time.** A run of one example the writer plans itself adds +0.3 tasks over the gate
  on Qwen3.8 at 1.6x the gate's time, and on DeepSeek setups +0 to +1 task at 1.4-2.2x the time. The writer's own
  expected output is unreliable: most smoke catches end in a "fix" toward a wrong expectation or are false alarms.
- **Prevent the two big error classes in the prompt, check in the harness.** An apostrophe inside a single-quoted awk
  program causes 43% of Qwen's bash syntax errors; Kotlin fails on `\f`, missing imports and nullability. Two rules in
  the system prompt give the best first-attempt score (13.3 vs 11.0 of 29) at the gate's cost, but the seeds disagree.
- **Never tell a tool-less model to check its work.** "Before replying, check the file as bash -n / py_compile /
  kotlinc would" made Qwen3.8 answer with made-up tool calls instead of the file (pass@2 18 → 8).
- **FF does not change the winner.** DeepSeek + Qwen3.8 review stays the default; with smoke FF it reached quality
  0.997 on the 29 tasks (28 solved, no-FF mean 27.0), at 1.4x the time; with the plain gate the time cost should be
  near zero (DeepSeek's gate-catchable share is 6%).
- **Single-seed joined-task results are noise-bound.** DS + DeepSeek review solved 5 of 12 joined tasks without FF and
  10 with FF, although FF changed only 2 attempts: run-to-run variation of ±several tasks on 6-task sets.

## What FF is

After each draft (and after review, if the setup has one) the harness runs checks that cannot leak the hidden tests and
hands a failure back to the writer, up to `--feedback-rounds` (2) fix turns, before the hidden tests score the attempt.

| level | flag | checks |
|---|---|---|
| off | `--feedback off` | none (the original protocol) |
| compile (FF0) | `--feedback compile` | Python: py_compile, then `import` of the module; bash: bash -n, then shellcheck -S error; Kotlin: kotlinc |
| smoke (FF1) | `--feedback smoke` | compile, then one example run: in a separate call the writer is shown the task and its file and answers with one shell command, the expected stdout and exit code; the harness runs it in an empty dir and compares stdout ignoring whitespace (Kotlin: compile only) |
| review on FF fail | `--review-when ff-fail` | no review up front; the reviewer runs only when a check fails and also sees the failure |
| rules | `--system-extra FILE` | text appended to the writer's system prompt (stack/eval/writer-rules2.txt) |

Code: burnish eval/coding/run_coding_eval.py (branch feat/coding-eval-review: 4138da0, ddc4a7d, ad09d39, b2581de),
stack/scripts/eval_pair.py `--feedback` (the driver plans the smoke example and gets the failures). Records: each
attempt's `feedback` list (stage, ok, output). Launchers: stack/scripts/tmp_ff_replay.py, tmp_ff_q8.sh,
tmp_ff_q8_rules2.sh, tmp_ff_ds.sh, tmp_ff_combo.sh. Results: burnish results/*-ff-*.json, LLM_ROOT/results/ff-study/.

## Step 1: offline replay (ceiling)

2,054 distinct failing attempts from all stored runs (29 tasks and both joined sets, every writer) run through the gate,
no model calls. Awk syntax errors pass bash -n but show on any run, so they are counted apart.

| failing attempts | n | caught by gate | + awk syntax on a run | share |
|---|---|---|---|---|
| Kotlin | 188 | 108 | — | 57% |
| bash | 720 | 116 | 38 | 21% |
| Python | 1,146 | 20 | — | 2% |
| DeepSeek writer | 360 | 15 | 7 | 6% |
| Qwen3.8 writer | 716 | 94 | 10 | 15% |
| Qwen3.6 MTP writer | 547 | 83 | 14 | 18% |
| all | 2,054 | 244 | 38 | 14% |

186 of the 244 catches were first attempts. Python failures are 85% wrong answers, which no gate can catch.

## Step 2: Qwen3.8 alone, 29 tasks, 3 seeds

Fresh no-FF baseline in the same session. pass@1 / pass@2 / quality (hidden-test share of the better attempt).

| setup | seed 1 | seed 2 | seed 3 | mean pass@1 | mean pass@2 | mean quality | min per run |
|---|---|---|---|---|---|---|---|
| off | 13 / 15 / 0.803 | 9 / 16 / 0.903 | 5 / 13 / 0.758 | 9.0 | 14.7 | 0.821 | 46 |
| compile | 15 / 18 / 0.862 | 10 / 18 / 0.919 | 8 / 16 / 0.813 | 11.0 | 17.3 | 0.864 | 48 |
| smoke | 14 / 20 / 0.900 | 12 / 18 / 0.916 | 8 / 15 / 0.857 | 11.3 | **17.7** | **0.891** | 75 |
| compile + rules2 | 10 / 15 / 0.860 | 15 / 19 / 0.897 | 15 / 19 / 0.902 | **13.3** | **17.7** | 0.886 | 44 |
| compile + rules v1 (stopped) | 4 / 8 / 0.609 | — | — | | | | 46 |

Paired per task against off (solve rate over 3 seeds, summed; net [95% bootstrap CI over tasks]):

| setup | tasks gained / lost | net |
|---|---|---|
| compile | +2.7 / −0.0 | +2.7 [+1.0, +4.3] |
| smoke | +3.7 / −0.7 | +3.0 [+0.3, +6.0] |
| compile + rules2 | +4.7 / −1.7 | +3.0 [+0.0, +6.0] |

What the checks did (3 seeds; attempts whose first check failed → fixed → then passed the hidden tests):

| setup | caught | fixed | then passed |
|---|---|---|---|
| compile | 12 | 12 | 7 |
| smoke | 56 | 29 | 11 |
| compile + rules2 | 12 | 12 | 5 |

## Step 3: FF smoke on the DeepSeek setups, seed 1

No-FF baselines: the 29-task 3-seed means of the matrix and the seed-1 joined runs (report, "Joined tasks"). pass@1 /
pass@2 / quality, time. "FF changed" = attempts where a check failed and a fix turn followed.

| setup | 29 tasks, FF | 29 tasks, no FF (mean) | 12 joined, FF | 12 joined, no FF | FF changed (29 / joined) |
|---|---|---|---|---|---|
| DeepSeek alone | 21 / 25 / 0.973, 367 min | 19.0 / 24.7 / 0.938, ~160 min | 1 / 5 / 0.925, 437 min | 1 / 4 / 0.902, 235 min | 12 / 9 |
| DS + DeepSeek review | 18 / 28 / 0.983, 468 min | 21.0 / 26.3 / 0.973, ~266 min | 3 / **10** / **0.976**, 539 min | 3 / 5 / 0.958, 387 min | 8 / 2 |
| DS + Qwen3.8 review | 20 / **28** / **0.997**, 357 min | 19.7 / 27.0 / 0.988, ~256 min | 4 / **11** / **0.995**, 558 min | 3 / 7 / 0.960, 492 min | 8 / 5 |
| nav DS + driver DS (pair) | 20 / 26 / 0.979, 567 min | 19.7 / 25.7 / 0.971, ~260 min | 5 / 9 / 0.985, 669 min | 3 / 8 / 0.973, 538 min | 8 / 7 |
| DS + Qwen3.8 review only on FF fail | queued | | queued | | |
| Qwen3.8 + DeepSeek review | queued (29 only) | 12.3 / 20.3 / 0.902 | — | | |

- On DeepSeek the checks change about 8-12 attempts per 29-task run and turn 1-3 of them into passes; the rest are
  false alarms (4-5 per run) or "fixes" that still fail. Gains are +0 to +1.3 tasks at 1.4-2.2x the time.
- The joined numbers move far more than FF can explain (DS + DeepSeek review: 10 vs 5 with 2 changed attempts), so
  joined-task rankings need more seeds before they mean anything.
- DS + Qwen3.8 review + FF on joined: 6 of 6 vs 3 of 6 without FF; FF changed 4 attempts and 2 of them then
  passed (sh_log_report attempt 2, sh_ops attempt 1; without FF sh_ops failed on a fixture parse error). py_release
  passed on attempt 2 with no FF change, so that gain is run-to-run variation. 1.23x the time.
- DS + Qwen3.8 review + FF on joined2: 5 of 6 vs 4 of 6 without FF, quality 0.991 vs 0.983, same time (218 vs 216
  min). FF changed 1 attempt (py_table attempt 1, still failed; passed on attempt 2 as without FF). Gains py_splitter
  and sh_files and the loss py_build (17/18) had no FF change: run-to-run variation. Pooled over the 12 joined tasks:
  11 vs 7, quality 0.995 vs 0.960, 1.13x the time; 2 of the 4 extra solves come from FF fixes (sh_log_report, sh_ops),
  the rest is noise.
- DS>DS pair + FF on joined: 4 of 6 vs 3 of 6 without FF; FF changed 2 attempts and neither then passed. The gain
  (py_release on attempt 2) is run-to-run variation; both bash tasks failed with and without FF. 1.19x the time.
- DS>DS pair + FF on joined2: 5 of 6 vs 5 of 6 without FF, pass@1 4 vs 2, quality 0.992 vs 0.964, 1.33x the time
  (278 vs 209 min). FF changed 5 attempts and 3 then passed: sh_net attempt 1 (failed both attempts without FF), sh_files
  attempt 1 (passed only on attempt 2 without FF) and kt_booking attempt 1 (passed first try without FF too). py_table
  failed both attempts (19/20) after passing on attempt 2 without FF, with no FF change on attempt 2: noise. Pooled over
  the 12 joined tasks: 9 vs 8, pass@1 5 vs 3, quality 0.985 vs 0.973, 1.24x the time; one solve (sh_net) comes from FF.
- First solves by any setup: py_release and sh_ops (DS + DeepSeek review + FF, old joined set).

## Findings

1. **Compile errors are cheap to catch and the writer fixes them.** Kotlin: 6 of 6 caught attempts fixed and passed.
   Bash syntax errors are fixed less reliably (about half), because the writer often re-breaks the quoting.
2. **The awk apostrophe.** 74 of 102 bash syntax errors (all writers) are awk code parsed as shell because the
   single-quoted program closed early; in 48 of 111 Qwen bash -n failures an apostrophe in an awk comment
   ("doesn't") is the cause. Rule: no `'` anywhere inside a single-quoted awk/sed program; use `\047` or a quoted
   heredoc.
3. **Kotlin compile errors:** unresolved references (missing imports) 29, `'\f'` and other escapes Kotlin lacks 21,
   nullable class literals 13, type mismatches (V? vs V) 13, of 108.
4. **Model-predicted expected output is not a check.** Of 56 smoke catches on Qwen3.8 only 11 ended in a passing
   file. Checks must compare against tests or committed expected files, never against what the model thinks the
   output should be.
5. **"Check your work" without tools backfires.** The rule made Qwen3.8 switch into agent mode
   (`<tool_call><function=Bash>cat /app/solution.py`) with no tools available: 11 attempts without a code block.
   Prompts and CLAUDE.md/AGENTS.md files should name the check command only where the agent can run it; otherwise
   the harness (a gate, a Claude Code hook) runs it.
6. **Python failures are logic errors.** 85% of failing Python attempts run and return wrong answers; py_apply_patch,
   py_expr_eval and py_shell_split fail for Qwen3.8 in every seed and mode. Only tests catch these (tests first gave
   Qwen3.8 +4-5 first-attempt solves in the matrix).
7. **Seed noise is large.** Qwen3.8 off moved 13 → 16 → 13 pass@2 and 13 → 9 → 5 pass@1 between seeds; single-seed
   comparisons of 1-3 tasks are not evidence.

## Recommendations

- Harness / agent setup: one check command per repo that runs the compile gate (and the tests when they exist), prints
  only failures and exits non-zero; run it after every edit (hook or gate), feed failures back, at most two fix rounds.
- Writer prompt / CLAUDE.md: the awk-apostrophe rule and the Kotlin rule (escapes, imports, nullability); no "check
  before replying" unless the agent has the tool.
- Default coder: DeepSeek + Qwen3.8 review plus the compile gate. Skip the smoke run.

## Still running (Nov 28)

- DS + Qwen3.8 review only on FF fail (29, joined, joined2); then
  Qwen3.8 + DeepSeek review + FF (29).
- Then (tmp_ff_next.sh, one KT slot each): DS + Qwen3.8 review + compile gate only (29, joined, joined2); seed 2 on
  the 12 joined tasks for DS + Qwen3.8 review (compile and off).
- Seed 2 on the 12 joined tasks for DeepSeek alone (started 19:17), DS + DeepSeek review, DS>DS pair.
