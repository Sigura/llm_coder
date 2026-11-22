"""OpenCode domain eval: OpenCode builds every task of one domain in a single session, then an independent review.

Uses burnish's coding eval tasks and tests (eval/coding in the burnish repo), never shown to the agent. Stages:
  1. build: one OpenCode session (opencode-local.sh, without its review-after-each-change instruction) gets the
     tasks one by one, each in its own directory of a fresh project; each file is scored after its turn
  2. review: llm-review.sh (another model, task text and file only) reviews every file
  3. fix: the findings go back to the same session in one message; the files are scored again
Resumes from <label>/state.json after an interruption (a turn cut off by a hang reruns).
"""
import argparse
import json
import os
import subprocess
import time
from datetime import datetime
from pathlib import Path

from eval_pair import load_runner

SCRIPTS = Path(__file__).resolve().parent
INTRO = (
    "We will implement a series of small, independent {lang} tasks in this project, one per directory, one at a "
    "time. Work on your own: write the file, check it yourself if you like, and do not ask questions.\n\n"
)
BUILD_ASK = (
    "Task {k}/{n}: create `{path}`. Work only in `{dir}/`. When the file is finished, reply with the single word "
    "done.\n\n{prompt}"
)
FIX_ASK = (
    "An independent reviewer (another model; it saw only each task's text and the file) reviewed your files. For "
    "each finding, fix the code if you agree and leave it if you don't; keep every task's required behaviour. "
    "Then reply with one line per file: `path: fixed N, rejected M (why)`.\n\n{reviews}"
)


def score(rce, task, work: Path) -> dict:
    f = work / task["id"] / task["file"]
    if not f.is_file():
        return {"passed": False, "tests": 0.0, "output": "no file", "code": None}
    code = f.read_text()
    passed, output = rce.run_tests(task, code)
    return {"passed": passed, "tests": rce.test_fraction({"passed": passed, "output": output}),
            "output": output[-rce.FEEDBACK_CHARS:], "code": code}


def opencode_turn(args, run_dir: Path, session: str | None, message: str, timeout: int) -> dict:
    env = {**os.environ, "OPENCODE_STATE": str(run_dir / "opencode"), "OPENCODE_MAIN": args.main,
           "OPENCODE_REVIEW": "0"}
    cmd = [str(SCRIPTS / "opencode-local.sh"), "run", "--auto", "--format", "json"]
    if session:
        cmd += ["--session", session]
    start = time.monotonic()
    timed_out = False
    try:
        proc = subprocess.run(cmd + [message], cwd=run_dir / "work", env=env, capture_output=True, text=True,
                              timeout=timeout)
        out, rc = proc.stdout, proc.returncode
    except subprocess.TimeoutExpired as e:
        out, rc, timed_out = (e.stdout or b"").decode(errors="replace"), None, True
    with open(run_dir / "events.jsonl", "a") as log:
        log.write(out)
    events = [json.loads(line) for line in out.splitlines() if line.startswith("{")]
    steps = [e["part"] for e in events if e.get("type") == "step_finish"]
    tools: dict[str, int] = {}
    for e in events:
        if e.get("type") == "tool_use":
            tools[e["part"]["tool"]] = tools.get(e["part"]["tool"], 0) + 1
    return {"session": next((e["sessionID"] for e in events if e.get("sessionID")), session),
            "seconds": round(time.monotonic() - start, 1), "rc": rc, "timed_out": timed_out,
            "steps": len(steps), "output_tokens": sum(s["tokens"]["output"] for s in steps),
            "max_input_tokens": max((s["tokens"]["input"] for s in steps), default=0), "tools": tools,
            "touched_burnish": "burnish" in out,
            "reply": " ".join(e["part"]["text"] for e in events if e.get("type") == "text")[-2000:]}


def review(args, run_dir: Path, task) -> dict:
    path = f"{task['id']}/{task['file']}"
    if not (run_dir / "work" / path).is_file():
        return {"verdict": None, "findings": 0, "seconds": 0.0}
    start = time.monotonic()
    proc = subprocess.run([str(SCRIPTS / "llm-review.sh"), "--model", args.reviewer, "--task", task["prompt"].strip(),
                           path], cwd=run_dir / "work", capture_output=True, text=True, check=True)
    verdict = proc.stdout.strip()
    return {"verdict": verdict, "findings": 0 if verdict == "OK" else len(verdict.splitlines()),
            "seconds": round(time.monotonic() - start, 1)}


def summarize(tasks, st) -> dict:
    s = {"tasks": len(tasks)}
    for stage in ("build", "fixed"):
        rs = [st["tasks"][t["id"]].get(stage) for t in tasks]
        s[f"{stage}_pass"] = sum(bool(r and r["passed"]) for r in rs)
        s[f"{stage}_tests"] = round(sum(r["tests"] for r in rs if r), 3)
    pairs = [(st["tasks"][t["id"]]["build"]["passed"], st["tasks"][t["id"]].get("fixed", {}).get("passed"),
              st["tasks"][t["id"]].get("review", {})) for t in tasks]
    s["review_ok"] = sum(r.get("verdict") == "OK" for _, _, r in pairs)
    # review lines, not defects: the reviewer also lists checks it found correct
    s["review_lines"] = sum(r.get("findings", 0) for _, _, r in pairs)
    changed = [st["tasks"][t["id"]]["build"]["passed"] for t in tasks
               if st["tasks"][t["id"]].get("fixed", {}).get("code") != st["tasks"][t["id"]]["build"]["code"]]
    s["changed_by_fix_on_passing"] = sum(changed)
    s["changed_by_fix_on_failing"] = len(changed) - sum(changed)
    s["fail_to_pass"] = sum(not b and bool(f) for b, f, _ in pairs)
    s["pass_to_fail"] = sum(b and f is False for b, f, _ in pairs)
    s["build_seconds"] = round(sum(st["tasks"][t["id"]]["turn"]["seconds"] for t in tasks), 1)
    s["review_seconds"] = round(sum(r.get("seconds", 0) for _, _, r in pairs), 1)
    s["fix_seconds"] = st.get("fix_turn", {}).get("seconds")
    s["output_tokens"] = sum(st["tasks"][t["id"]]["turn"]["output_tokens"] for t in tasks) + \
        st.get("fix_turn", {}).get("output_tokens", 0)
    s["touched_burnish"] = any(st["tasks"][t["id"]]["turn"]["touched_burnish"] for t in tasks) or \
        st.get("fix_turn", {}).get("touched_burnish", False)
    return s


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--burnish", default=os.path.expanduser("~/burnish/eval/coding"), help="burnish's eval/coding dir")
    p.add_argument("--tasks", default="sh_*")
    p.add_argument("--langs", default="bash")
    p.add_argument("--label", default="opencode-sh")
    p.add_argument("--main", default="deepseek-v4.1-flash-1017-fp8", help="OPENCODE_MAIN: the build model's config")
    p.add_argument("--reviewer", default="qwen3.6-35b-a3b-mtp", help="llm-review.sh --model")
    p.add_argument("--turn-timeout", type=int, default=2700, help="seconds per build turn; the fix turn gets 3x")
    p.add_argument("--out-dir", default=os.path.expanduser("~/llm_coder/llm/results/opencode-eval"))
    args = p.parse_args()

    root = Path(args.burnish)
    rce = load_runner(root / "run_coding_eval.py")
    tasks = rce.load_tasks(root / "tasks", args.tasks, set(args.langs.split(",")))
    if not tasks:
        p.error("no tasks matched")
    run_dir = Path(args.out_dir) / args.label
    (run_dir / "work").mkdir(parents=True, exist_ok=True)
    state_file = run_dir / "state.json"
    st = json.loads(state_file.read_text()) if state_file.exists() else {"session": None, "tasks": {}}

    def save():
        tmp = state_file.with_suffix(".tmp")
        tmp.write_text(json.dumps(st, indent=1))
        os.replace(tmp, state_file)

    for k, task in enumerate(tasks, 1):
        if "build" in st["tasks"].get(task["id"], {}):
            continue
        (run_dir / "work" / task["id"]).mkdir(exist_ok=True)
        msg = BUILD_ASK.format(k=k, n=len(tasks), path=f"{task['id']}/{task['file']}", dir=task["id"],
                               prompt=task["prompt"].strip())
        if not st["session"]:
            msg = INTRO.format(lang=task["lang"]) + msg
        turn = opencode_turn(args, run_dir, st["session"], msg, args.turn_timeout)
        st["session"] = turn["session"]
        st["tasks"][task["id"]] = {"turn": turn, "build": score(rce, task, run_dir / "work")}
        save()
        b = st["tasks"][task["id"]]["build"]
        print(f"build  {task['id']:<24} {'+' if b['passed'] else '-'} tests {b['tests']:.2f} "
              f"{turn['seconds']:7.1f} s{' TIMEOUT' if turn['timed_out'] else ''}", flush=True)

    for task in tasks:
        t = st["tasks"][task["id"]]
        if "review" not in t:
            t["review"] = review(args, run_dir, task)
            save()
            print(f"review {task['id']:<24} {t['review']['findings']} findings {t['review']['seconds']:6.1f} s",
                  flush=True)

    if "fix_turn" not in st:
        reviews = "\n\n".join(f"### {t['id']}/{t['file']}\n{st['tasks'][t['id']]['review']['verdict']}"
                              for t in tasks if st["tasks"][t["id"]]["review"]["findings"])
        if reviews:
            st["fix_turn"] = opencode_turn(args, run_dir, st["session"], FIX_ASK.format(reviews=reviews),
                                           3 * args.turn_timeout)
        else:
            st["fix_turn"] = {"seconds": 0.0, "output_tokens": 0, "skipped": "no findings"}
        for task in tasks:
            st["tasks"][task["id"]]["fixed"] = score(rce, task, run_dir / "work")
        save()

    summary = summarize(tasks, st)
    out = Path(args.out_dir) / f"{datetime.now():%Y%m%d-%H%M%S}-{args.label}.json"
    out.write_text(json.dumps({"args": vars(args), "summary": summary, **st}, indent=1))
    state_file.unlink()
    print(json.dumps(summary, indent=1))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
