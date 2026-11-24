#!/usr/bin/env python3
"""Tables of llm/results/pair-eval/pair-report.md from the solo/review runs (burnish) and the pair runs.

pair_matrix.py            print the generated tables
pair_matrix.py --write    replace the first table under each generated heading in pair-report.md
"""
import glob
import json
import os
import re
import subprocess
import sys
from statistics import mean

BURNISH = os.path.expanduser("~/burnish/eval/coding/results")
GLOBAL_ENV = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config", "global.env")
LLM_ROOT = next(line.split("=", 1)[1].strip().strip("'\"") for line in open(GLOBAL_ENV) if line.startswith("LLM_ROOT="))
PAIR = os.path.join(LLM_ROOT, "results", "pair-eval")
REPORT = os.path.join(PAIR, "pair-report.md")

MODELS = {  # pair label name -> (matrix id, long name, short name)
    "deepseek": ("dsl", "DeepSeek (llama.cpp)", "DSl"),
    "deepseek-kt": ("ds", "DeepSeek (KT)", "DS"),
    "qwen3.8": ("q8", "Qwen3.8", "Q8"),
    "qwen3.6mtp": ("q6", "Qwen3.6 MTP", "Q6"),
}
MATRIX = ["ds", "q8", "q6"]
MATRIX_NAME = {"ds": "DeepSeek (KT)", "q8": "Qwen3.8", "q6": "Qwen3.6 MTP"}

# key, headline/per-task column, "what was tested" row (writer, navigator), long name, files per seed
FIXED = [
    ("ds-solo", "DS solo", ("DeepSeek V4.1 Flash (llama.cpp)", "—"), "DeepSeek alone",
     {"1 (part file)": "20261115-151845-deepseek-v4.1-flash-rec-s1-part.json",
      "2": "20261115-192814-deepseek-v4.1-flash-rec-s2.json", "3": "20261115-234512-deepseek-v4.1-flash-rec-s3.json"}),
    ("q8-solo", "Q8 solo", ("Qwen3.8-27B", "—"), "Qwen3.8 alone",
     {"1": "20261115-182728-qwen3.8-27b-rec-s1.json", "2": "20261115-190753-qwen3.8-27b-rec-s2.json",
      "3": "20261115-204418-qwen3.8-27b-rec-s3.json"}),
    ("q6-solo", "Q6 solo", ("Qwen3.6-35B-A3B MTP", "—"), "Qwen3.6 MTP alone",
     {"1": "20261115-001139-qwen3.6-mtp-rec-s1.json", "2": "20261115-002700-qwen3.6-mtp-rec-s2.json",
      "3": "20261115-004521-qwen3.6-mtp-rec-s3.json"}),
    ("q8-rds", "Q8+rDS", ("Qwen3.8", "DeepSeek reviews"), "Qwen3.8 writes, DeepSeek reviews",
     {"1": "20261115-172203-qwen3.8-27b-review-deepseek-v4.1-flash-s1.json",
      "2": "20261123-140902-qwen3.8-27b-review-deepseek-v4.1-flash-s2.json",
      "3": "20261123-172650-qwen3.8-27b-review-deepseek-v4.1-flash-s3.json"}),
    ("q8-rq6", "Q8+rQ6", ("Qwen3.8", "Qwen3.6 MTP reviews"), "Qwen3.8 writes, Qwen3.6 MTP reviews",
     {"1": "20261115-220245-qwen3.8-27b-review-qwen3.6-35b-a3b-mtp-s1.json",
      "2": "20261123-095050-qwen3.8-27b-review-qwen3.6-35b-a3b-mtp-s2.json",
      "3": "20261123-112424-qwen3.8-27b-review-qwen3.6-35b-a3b-mtp-s3.json"}),
    ("q6-rq8", "Q6+rQ8", ("Qwen3.6 MTP", "Qwen3.8 reviews"), "Qwen3.6 MTP writes, Qwen3.8 reviews",
     {"1": "20261123-203219-qwen3.6-35b-a3b-mtp-review-qwen3.8-27b-s1.json",
      "2": "20261123-210806-qwen3.6-35b-a3b-mtp-review-qwen3.8-27b-s2.json",
      "3": "20261123-215948-qwen3.6-35b-a3b-mtp-review-qwen3.8-27b-s3.json"}),
    ("ds-rq8", "DS+rQ8", ("DeepSeek V4.1 Flash (KT)", "Qwen3.8 reviews"), "DeepSeek writes, Qwen3.8 reviews",
     {"1": "20261123-233357-deepseek-v4.1-flash-review-qwen3.8-27b-s1.json",
      "2": "20261124-031048-deepseek-v4.1-flash-review-qwen3.8-27b-s2.json",
      "3": "20261124-080655-deepseek-v4.1-flash-review-qwen3.8-27b-s3.json"}),
    ("ds-rds", "DS+rDS", ("DeepSeek V4.1 Flash (KT)", "DeepSeek reviews"), "DeepSeek writes, DeepSeek reviews",
     {"1": "20261124-005824-deepseek-v4.1-flash-review-deepseek-v4.1-flash-s1.json",
      "2": "20261124-044014-deepseek-v4.1-flash-review-deepseek-v4.1-flash-s2.json",
      "3": "20261124-083412-deepseek-v4.1-flash-review-deepseek-v4.1-flash-s3.json"}),
    ("q6-rds", "Q6+rDS", ("Qwen3.6 MTP", "DeepSeek reviews"), "Qwen3.6 MTP writes, DeepSeek reviews",
     {"1": "20261123-223223-qwen3.6-35b-a3b-mtp-review-deepseek-v4.1-flash-s1.json"}),
]
SOLO_SEEDS = {"ds-solo": ["2", "3"], "q8-solo": ["1", "2", "3"], "q6-solo": ["1", "2", "3"]}
SHORT = {("deepseek", "qwen3.8"): "PAIR", ("deepseek-kt", "qwen3.8"): "PAIR-KT"}  # (nav, driver), names used in the prose
NOTES = {  # extra text in the headline's time column
    ("qwen3.6mtp", "qwen3.8"): "Qwen3.6 on the 3090 Ti",
}
LABEL_ALIAS = {"pair-deepseek-nav-deepseek-kt": "pair-deepseek-kt-nav-deepseek-kt"}  # tmp_pair_ds_ds.sh: KT in both roles
# DeepSeek seed 1 in the earlier report: 7 tasks from the part file plus a rerun of the rest, pieced together by hand;
# its sources were not kept, so the headline takes the earlier report's numbers.
DS_SOLO_S1 = {"pass@1": 22, "pass@2": 28}
ORDER = ["deepseek", "deepseek-kt", "qwen3.8", "qwen3.6mtp"]
LABEL = re.compile(r"pair-(?P<drv>.+?)-nav-(?P<nav>deepseek-kt|deepseek|qwen3\.8|qwen3\.6mtp)(?:-(?P<tag>[a-z0-9-]+?))?-s(?P<seed>\d+)$")


def load(path):
    with open(path) as f:
        return json.load(f)


def solved(r, n):
    return any(a["passed"] for a in r["attempts"][:n])


def stats(results):
    return {"tasks": len(results), "pass@1": sum(solved(r, 1) for r in results),
            "pass@2": sum(solved(r, 2) for r in results),
            "seconds": round(sum(a["seconds"] for r in results for a in r["attempts"]), 1)}


def running_labels():
    out = subprocess.run(["pgrep", "-af", "eval_pair.py"], capture_output=True, text=True).stdout
    return set(re.findall(r"--label (\S+)", out))


def pair_runs():
    """{(nav, drv, tag): {seed: run}}; a run has results, summary (final only), partial flag."""
    runs = {}
    files = sorted(glob.glob(os.path.join(PAIR, "*-pair-*.json"))) + sorted(glob.glob(os.path.join(PAIR, "pair-*.partial.json")))
    for path in files:
        base = os.path.basename(path)
        partial = base.endswith(".partial.json")
        label = base[:-len(".partial.json")] if partial else re.sub(r"^\d{8}-\d{6}-", "", base[:-len(".json")])
        m = LABEL.match(LABEL_ALIAS.get(label[:-3], label[:-3]) + label[-3:])
        if not m:
            continue
        key = (m["nav"], m["drv"], m["tag"] or "")
        seeds = runs.setdefault(key, {})
        if partial and m["seed"] in seeds:
            continue  # a finished file wins over a stale partial
        d = load(path)
        seeds[m["seed"]] = {"label": label, "results": d["results"], "summary": d.get("summary", {}).get("all"),
                            "partial": partial}
    return runs


def setups():
    """All setups in display order: (key, column, (writer, navigator), long name, {seed label: run})."""
    out = []
    for key, col, tested, name, files in FIXED:
        seeds = {}
        for seed, f in files.items():
            d = load(os.path.join(BURNISH, f))
            seeds[seed] = {"label": f, "results": d["results"], "summary": d["summary"]["all"], "partial": False}
        out.append((key, col, tested, name, seeds))
    for (nav, drv, tag), seeds in sorted(pair_runs().items(), key=lambda kv: (ORDER.index(kv[0][0]), ORDER.index(kv[0][1]), kv[0][2])):
        n, d = MODELS[nav], MODELS[drv]
        col = SHORT.get((nav, drv)) if not tag else None
        col = col or f"{n[2]}>{d[2]}" + (f" {tag}" if tag else "")
        name = f"nav {n[1]} + driver {d[1]}" + (f" ({tag})" if tag else "")
        out.append(((nav, drv, tag), col, (d[1], f"{n[1]} plans + reviews"), name, dict(sorted(seeds.items()))))
    return out


def table(header, rows):
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    lines += ["| " + " | ".join(str(c) for c in row) + " |" for row in rows]
    return "\n".join(lines)


def complete(run):
    return not run["partial"] and len(run["results"]) == 29


def seed_desc(seed, run):
    return seed if complete(run) or "part" in seed else f"{seed} (partial, {len(run['results'])}/29)"


def display_name(key, col, name):
    label = name if key in SOLO_SEEDS or (isinstance(key, tuple) and not SHORT.get(key[:2])) else col
    return label + (" (llama.cpp)" if col == "PAIR" else "")


def what_was_tested(all_setups):
    rows = [(display_name(key, col, name), w, nv, ", ".join(seed_desc(s, r) for s, r in seeds.items()))
            for key, col, (w, nv), name, seeds in all_setups]
    return table(["setup", "writer (driver)", "planner / reviewer (navigator)", "seeds"], rows)


def score(p1, p2):
    return (0.3 * p1 + 0.7 * p2) / 29


def headline(all_setups):
    rows = []
    for key, col, _, name, seeds in all_setups:
        full = {s: r for s, r in seeds.items() if complete(r)}
        parts = [str(r["summary"]["pass@2"]) for r in full.values()]
        parts += [f"seed {s}: {stats(r['results'])['pass@2']} of the first {len(r['results'])}"
                  for s, r in seeds.items() if not complete(r) and "part" not in s]
        if not parts:
            continue
        p2 = [r["summary"]["pass@2"] for r in full.values()]
        p1 = [r["summary"]["pass@1"] for r in full.values()]
        if key == "ds-solo":
            parts.insert(0, f"{DS_SOLO_S1['pass@2']} (pieced together)")
            p2.insert(0, DS_SOLO_S1["pass@2"])
            p1.insert(0, DS_SOLO_S1["pass@1"])
        secs = [r["summary"]["seconds"] for r in full.values()]
        t = "—" if not secs else (f"{secs[0]:,.0f} s" if len(secs) == 1 else f"{min(secs):,.0f}–{max(secs):,.0f} s")
        if key in NOTES or (isinstance(key, tuple) and key[:2] in NOTES):
            t += f" ({NOTES.get(key) or NOTES[key[:2]]})"
        sc = score(mean(p1), mean(p2)) if p2 else -1
        rows.append(((sc, mean(p2) if p2 else -1), (display_name(key, col, name), f"{sc:.2f}" if p2 else "—", ", ".join(parts),
                     f"{mean(p2):.1f}" if len(p2) > 1 else (p2[0] if p2 else "—"), f"{mean(p1):.1f}" if len(p1) > 1 else (p1[0] if p1 else "—"), t)))
    rows.sort(key=lambda r: (-r[0][0], -r[0][1]))
    return table(["setup", "score", "pass@2 per seed", "mean", "pass@1 mean", "time per seed"], [r for _, r in rows])


def summary(all_setups):
    rows = []
    for key, _, _, name, seeds in all_setups:
        for seed, run in seeds.items():
            s = run["summary"]
            if s and not run["partial"]:
                tok = f"{s['navigator_tokens']} / {s['driver_tokens']}" if "navigator_tokens" in s else "—"
                rows.append((name, seed, s["tasks"], s["pass@1"], s["pass@2"], s["tests@2"], round(s["seconds"]),
                             s["completion_tokens"], tok))
            else:
                st = stats(run["results"])
                label = seed if "part" in seed else f"{seed} (partial)"
                rows.append((name, label, st["tasks"], st["pass@1"], st["pass@2"], "—", round(st["seconds"]), "—", "—"))
    return table(["setup", "seed", "tasks", "pass@1", "pass@2", "tests@2", "time s", "tokens", "nav / driver tokens"], rows)


def per_task(all_setups):
    tasks = {}
    for _, _, _, _, seeds in all_setups:
        for run in seeds.values():
            for r in run["results"]:
                tasks.setdefault(r["id"], r["lang"])
    order = {"bash": 0, "kotlin": 1, "python": 2}
    ids = sorted(tasks, key=lambda t: (order.get(tasks[t], 9), t))
    cols, header = [], ["task", "lang"]
    for key, col, _, _, seeds in all_setups:
        if key in SOLO_SEEDS:
            want = SOLO_SEEDS[key]
            idx = [{r["id"]: r for r in seeds[s]["results"]} for s in want]
            cols.append(lambda t, idx=idx: f"{sum(solved(i[t], 2) for i in idx if t in i)}/{len(idx)}")
        else:
            if "1" not in seeds:
                continue
            idx = {r["id"]: r for r in seeds["1"]["results"]}

            def cell(t, idx=idx):
                if t not in idx:
                    return "·"
                a = idx[t]["attempts"]
                return 2 if a[0]["passed"] else 1 if len(a) > 1 and a[1]["passed"] else 0
            cols.append(cell)
            col += "" if complete(seeds["1"]) else f" ({len(idx)}/29)"
        header.append(col)
    rows = [[t, tasks[t]] + [c(t) for c in cols] for t in ids]
    return table(header, rows)


def tests_first(all_setups):
    rows = []
    for _, _, _, name, seeds in all_setups:
        for seed, run in seeds.items():
            rs = [r for r in run["results"] if "nav_tests_on_ref" in r]
            if not rs:
                continue
            checks = [a["nav_checks"] for r in rs for a in r["attempts"] if a.get("nav_checks")]
            valid = [r for r in rs if r["nav_tests_on_ref"]]
            rows.append((name, seed_desc(seed, run), len(rs), f"{len(valid)}/{len(rs)}",
                         f"{sum(c[0] for c in checks)}/{len(checks)}", f"{sum(c[-1] for c in checks)}/{len(checks)}",
                         f"{sum(len(c) - 1 for c in checks)}", f"{sum(solved(r, 2) for r in valid)}/{len(valid)}",
                         f"{sum(solved(r, 2) for r in rs if not r['nav_tests_on_ref'])}/{len(rs) - len(valid)}"))
    return table(["setup", "seed", "tasks", "nav tests pass on ref", "nav tests pass first try",
                  "nav tests pass after fixes", "tdd fix turns", "pass@2 (nav tests valid)",
                  "pass@2 (nav tests wrong)"], rows)


def combinations(all_setups):
    running = running_labels()
    runs = {k: v for k, v in pair_runs().items() if not k[2]}
    ident = {v[0]: k for k, v in MODELS.items()}

    def cell(nav, drv):
        parts = []
        keys = [(ident[nav], ident[drv], "")] + ([("deepseek", ident[drv], "")] if nav == "ds" else [])
        for key in keys:
            eng = " llama.cpp" if key[0] == "deepseek" else ""
            for seed, run in runs.get(key, {}).items():
                st = stats(run["results"])
                state = "running" if run["label"] in running else ("done" if complete(run) else "paused")
                parts.append(f"s{seed}{eng} {st['pass@2']}/{st['tasks']} {state}")
        return "; ".join(parts) or "queued"
    rows = [[MATRIX_NAME[n]] + [cell(n, d) for d in MATRIX] for n in MATRIX]
    return table(["navigator \\ driver"] + [MATRIX_NAME[d] for d in MATRIX], rows)


def replace_table(text, heading, new):
    start = text.index(heading)
    m = re.compile(r"(^\|.*\n)+", re.M).search(text, start)
    return text[:m.start()] + new + "\n" + text[m.end():]


def main():
    all_setups = setups()
    sections = [("## What was tested", what_was_tested(all_setups)), ("## Headline", headline(all_setups)),
                ("## Summary per run", summary(all_setups)), ("## Per task", per_task(all_setups)), ("## Tests-first", tests_first(all_setups)),
                ("## Combinations available", combinations(all_setups))]
    if "--write" in sys.argv:
        with open(REPORT) as f:
            text = f.read()
        for heading, tab in sections:
            text = replace_table(text, heading, tab)
        with open(REPORT, "w") as f:
            f.write(text)
        print(f"updated {REPORT}")
    else:
        for heading, tab in sections:
            print(heading + "\n\n" + tab + "\n")


if __name__ == "__main__":
    main()
