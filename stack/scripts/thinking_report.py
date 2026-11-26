"""docs/thinking-check.md from the thinking-check replays in LLM_ROOT/results/thinking-check (finished and partial).

Usage: thinking_report.py [--results DIR] [--out FILE]
"""
import argparse
import glob
import json
import os
from datetime import datetime
from pathlib import Path

HEAD = """# Thinking check: thinking on only for the checking role

Thinking is switched on only for the role that checks the work, and only in the best setup of each practice;
everything else is the eval's. Thinking runs use the model card's thinking sampling (user, Nov 25): Qwen3.8 temperature
0.6, top-p 0.95, top-k 20, presence 0; DeepSeek temperature 1.0 (the reviewer otherwise runs at burnish's 0.2).
DeepSeek V4.1 on KT turns thinking on only with `chat_template_kwargs.thinking`, so a first reviewer run that sent only
`enable_thinking` never thought and was discarded.

Replays, not full seeds: each check runs on fixed inputs, so a gain shows up in hours instead of ~10 h per seed.

Decision (user, Nov 26): pair and review thinking stopped after the 20-draft replays, no full seeds. Their setups
already reach 0.975–0.977 quality (ceiling 1.0, seed noise 0.02–0.04), so thinking cannot show an end-to-end gain,
while each check takes ~10x longer (about +10 h per seed). The 17 empty verdicts are not re-run. tdd thinking
stopped after seed 2 (user, Nov 26): 6, 6, 6 valid test files without vs 15 and 17 with is clear without seed 3.
Most no-thinking failures were harness mistakes the test prompt invited (Kotlin helpers redefined, pytest imported,
bash script called after a `cd`), so the prompt was fixed (`eval_pair.py` HARNESS) and re-run without thinking.
- Pair (nav DS + driver DS, Winners #3) and review (DS + DS review, #2): the DeepSeek navigator / reviewer looks at 78
  stored DeepSeek drafts (DeepSeek alone, seeds 1-3), labelled by the current tests: 39 fail, 39 pass. A flag (any
  verdict but OK) on failing code is a catch, on passing code a false alarm. The navigator first writes its plan, as in
  the pair eval. Thinking runs take 5-35 min per draft, so they use a fixed random subset of 10 failing + 10 passing
  drafts; the no-thinking numbers are shown on the same 20 and on all 78. Empty verdicts (thinking ran out of tokens)
  are counted apart, not as flags; in the eval an empty verdict is not OK, so it acts like a flag (the driver revises).
- tdd (nav Qwen3.8 + driver DS, #5): only the navigator's plan and test-writing turns (`eval_pair.py --tests-only`) on
  all 29 tasks; score = test files that pass the task's reference solution.
"""


PAIR_EVAL = Path(os.path.expanduser("~/llm_coder/llm/results/pair-eval"))
BURNISH = Path(os.path.expanduser("~/burnish/eval/coding/results"))
BASELINE = [  # the eval's best setup per practice, thinking off (Winners, Nov 25)
    ("pair", "nav DS + driver DS (#3)", [PAIR_EVAL / f for f in (
        "20261121-192145-pair-deepseek-nav-deepseek-kt-s1.json", "20261123-005504-pair-deepseek-nav-deepseek-kt-s2.json",
        "20261123-044041-pair-deepseek-nav-deepseek-kt-s3.json")]),
    ("review", "DS + DS review (#2)", [BURNISH / f for f in (
        "20261124-005824-deepseek-v4.1-flash-review-deepseek-v4.1-flash-s1.json",
        "20261124-044014-deepseek-v4.1-flash-review-deepseek-v4.1-flash-s2.json",
        "20261124-083412-deepseek-v4.1-flash-review-deepseek-v4.1-flash-s3.json")]),
    ("tdd", "nav Qwen3.8 + driver DS, tests first (#5)", [PAIR_EVAL / f for f in (
        "20261124-202704-pair-deepseek-kt-nav-qwen3.8-tdd-s1.json",
        "20261125-030337-pair-deepseek-kt-nav-qwen3.8-tdd-s2.json",
        "20261125-102324-pair-deepseek-kt-nav-qwen3.8-tdd-s3.json")]),
]


def baseline_rows() -> list[str]:
    rows = []
    for practice, setup, files in BASELINE:
        runs = [json.loads(f.read_text()) for f in files]
        p1 = [r["summary"]["all"]["pass@1"] for r in runs]
        p2 = [r["summary"]["all"]["pass@2"] for r in runs]
        secs = [r["summary"]["all"]["seconds"] for r in runs]
        q = [r["summary"]["all"]["tests@2"] / 29 for r in runs]
        m1, m2, mq = sum(p1) / len(p1), sum(p2) / len(p2), sum(q) / len(q)
        valid = ([sum(x.get("nav_tests_on_ref") is True for x in r["results"]) for r in runs]
                 if practice == "tdd" else None)
        rows.append(f"| {practice} | {setup} | **{mq:.3f}** ({', '.join(f'{x:.3f}' for x in q)}) | "
                    f"{m1:.1f} ({', '.join(map(str, p1))}) | {m2:.1f} ({', '.join(map(str, p2))}) | "
                    f"{sum(secs) / sum(p2) / 60:.1f} | "
                    f"{'—' if valid is None else ', '.join(map(str, valid))} |")
    return rows


def latest(results: Path, pattern: str):
    fs = [f for f in sorted(glob.glob(str(results / pattern))) if not Path(f).name.startswith(("invalid", "capped"))]
    finals = [f for f in fs if not f.endswith(".partial.json")]
    return (finals or fs or [None])[-1]


def check_rows(results: Path, kind: str, keys: set) -> list[str]:
    rows = []
    for mode in ("off", "think"):
        f = latest(results, f"*replay-{kind}-ds-{mode}*.json")
        if not f:
            rows.append(f"| {'with thinking' if mode == 'think' else 'without'} | not started | | | | | |")
            continue
        rs = json.loads(Path(f).read_text())["results"]
        state = "partial" if f.endswith(".partial.json") else "done"
        for name, sel in (("all 78", rs), ("subset 20", [r for r in rs if r["key"] in keys])):
            if mode == "think" and name == "all 78":
                continue
            fail = [r for r in sel if not r["passed"]]
            ok = [r for r in sel if r["passed"]]
            secs = sum(r["seconds"] for r in sel) / len(sel) if sel else 0
            toks = sum(r.get("tokens", 0) for r in sel) / len(sel) if sel and kind == "nav" else None
            rows.append(f"| {'with thinking' if mode == 'think' else 'without'} | {name}: {len(sel)} done ({state}) | "
                        f"{sum(r['flagged'] and bool(r['verdict']) for r in fail)}/{len(fail)} | "
                        f"{sum(r['flagged'] and bool(r['verdict']) for r in ok)}/{len(ok)} | "
                        f"{sum(not r['verdict'] for r in sel)} | {secs / 60:.1f} min | "
                        f"{'' if toks is None else f'{toks:,.0f}'} |")
    return rows


TEST_MODES = {"off": "without", "think": "with thinking",
              "off-h2": "without, fixed test prompt (Nov 26)"}


def tests_rows(results: Path) -> list[str]:
    rows = []
    for mode in TEST_MODES:
        fs = sorted(glob.glob(str(results / f"*testsonly-{mode}-s*.json")))
        if not fs:
            rows.append(f"| {TEST_MODES[mode]} | not started | | | | |")
        finals = [json.loads(Path(f).read_text())["summary"]["all"] for f in fs if not f.endswith(".partial.json")]
        if finals:
            rows.append(f"| {TEST_MODES[mode]} | mean of {len(finals)} finished "
                        f"seed(s) | **{sum(x['tests_on_ref'] for x in finals) / len(finals):.1f}** | | | |")
        for f in fs:
            rs = json.loads(Path(f).read_text())["results"]
            seed = f.split("-s")[-1].split(".")[0]
            state = "partial" if f.endswith(".partial.json") else "done"
            rows.append(f"| {TEST_MODES[mode]} | s{seed}: {len(rs)}/29 ({state}) | "
                        f"**{sum(r['nav_tests_on_ref'] is True for r in rs)}** | "
                        f"{sum(r['tests_capped'] for r in rs)} | "
                        f"{sum(r['navigator_tokens'] for r in rs) / max(len(rs), 1):,.0f} | "
                        f"{sum(r['seconds'] for r in rs) / max(len(rs), 1) / 60:.1f} min |")
    return rows


def checker_score(rs) -> str:
    """Balanced accuracy, 0-1: (share of broken drafts flagged + share of correct drafts passed as OK) / 2. An empty
    verdict counts as a flag, as in the eval (not OK -> the driver revises). 0.5 = no better than always flagging."""
    fail = [r for r in rs if not r["passed"]]
    ok = [r for r in rs if r["passed"]]
    if not fail or not ok:
        return "—"
    return f"{(sum(r['flagged'] for r in fail) / len(fail) + sum(not r['flagged'] for r in ok) / len(ok)) / 2:.2f}"


def summary_rows(results: Path, keys: set) -> list[str]:
    rows = []
    for kind, practice, setup in (("nav", "pair", "DS navigator"), ("review", "review", "DS reviewer")):
        cells = []
        for mode in ("off", "think"):
            f = latest(results, f"*replay-{kind}-ds-{mode}*.json")
            rs = [r for r in json.loads(Path(f).read_text())["results"] if r["key"] in keys] if f else []
            done = "" if len(rs) == len(keys) else f" ({len(rs)}/{len(keys)} done)"
            cells.append(f"{checker_score(rs)}{done}" if rs else "not started")
        rows.append(f"| {practice} | {setup}: balanced accuracy on the 20 drafts | {cells[0]} | {cells[1]} |")
    cells = []
    for mode in ("off", "think"):
        fs = [f for f in sorted(glob.glob(str(results / f"*testsonly-{mode}-s*.json")))
              if not f.endswith(".partial.json")]
        vals = [json.loads(Path(f).read_text())["summary"]["all"]["tests_on_ref"] / 29 for f in fs]
        cells.append(f"{sum(vals) / len(vals):.2f} (n {len(vals)})" if vals else "no finished seed")
    rows.append(f"| tdd | Qwen3.8 test writer: share of test files valid on the reference | {cells[0]} | {cells[1]} |")
    fs = [f for f in sorted(glob.glob(str(results / "*testsonly-off-h2-s*.json"))) if not f.endswith(".partial.json")]
    vals = [json.loads(Path(f).read_text())["summary"]["all"]["tests_on_ref"] / 29 for f in fs]
    if vals:
        rows.append(f"| tdd | same, fixed test prompt (Nov 26) | {sum(vals) / len(vals):.2f} (n {len(vals)}) | — |")
    return rows


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--results", default=os.path.expanduser("~/llm_coder/llm/results/thinking-check"))
    p.add_argument("--out", default=str(Path(__file__).resolve().parents[2] / "docs" / "thinking-check.md"))
    args = p.parse_args()
    results = Path(args.results)
    keys = set(json.loads((results / "subset-per-class-10-seed1.json").read_text()))
    head = ("| run | drafts | catches (flagged failing) | false alarms (flagged passing) | empty verdicts | "
            "time per draft | tokens per draft |\n|---|---|---|---|---|---|---|")
    out = [HEAD, f"State {datetime.now():%Y-%m-%d %H:%M} (regenerated by stack/scripts/thinking_report.py).", "",
           "## Summary: the checking role alone, without vs with thinking", "",
           "Same scale in both columns, higher is better. Pair / review: balanced accuracy = (share of broken drafts "
           "flagged + share of correct drafts passed as OK) / 2, an empty verdict counting as a flag as in the eval; "
           "0.50 = no better than flagging everything. tdd: valid test files / 29. These measure the checking role "
           "alone, on a different scale from the Baseline below (whole practice, end to end): a checker at 0.50 still "
           "reaches 0.97 quality there, since a wrong flag only costs a revision. Whether thinking moves the end-to-end "
           "numbers needs full seeds.", "",
           "| practice | measure | without thinking | with thinking |\n|---|---|---|---|", *summary_rows(results, keys), "",
           "## Baseline: the eval's full seeds, thinking off (mean of 3 seeds)", "",
           "What a full seed with thinking has to beat, scored as in [pair-eval-winners.md](pair-eval-winners.md) "
           "(Nov 26): quality = share of hidden tests passed (better of two attempts), mean over tasks, seed noise "
           "0.02–0.04; pass@1 / pass@2 of 29; min per solved task = wall time / tasks solved.", "",
           "| practice | setup | quality (seeds) | pass@1 of 29 (seeds) | pass@2 of 29 (seeds) | min per solved task | "
           "navigator tests valid on the reference (seeds) |\n|---|---|---|---|---|---|---|", *baseline_rows(), "",
           "## Pair: DeepSeek navigator (plan + review)", "", head, *check_rows(results, "nav", keys), "",
           "## Review: DeepSeek reviewer", "", head, *check_rows(results, "review", keys), "",
           "## tdd: Qwen3.8 test writer (plan + tests)", "",
           "| run | tasks | test files valid on the reference | tests capped | navigator tokens per task | "
           "time per task |\n|---|---|---|---|---|---|", *tests_rows(results), ""]
    Path(args.out).write_text("\n".join(out))
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
