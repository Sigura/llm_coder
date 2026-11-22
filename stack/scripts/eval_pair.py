"""Pair-programming coding eval: a navigator model plans and reviews, a driver model writes the code.

Runs burnish's coding eval tasks (eval/coding in the burnish repo) with its own task loading, tests and scoring,
so pass@k / tests@k compare directly with plain run_coding_eval.py results. Per task and attempt:
  1. navigator: short plan and checks (first attempt only)
  2. driver: writes the file from the task and the plan
  3. navigator reviews the code in the same conversation; unless OK, the driver revises once
  4. the tests run; on failure the navigator turns the test output into a fix instruction for the next attempt
The navigator keeps one conversation per task, so llama-server reuses its prompt prefix between turns.
--tests-first: after the plan the navigator writes its own test file from the task text (burnish's harness format);
the driver sees it, and before the real tests the driver's file runs against it, with up to --tdd-rounds fix turns.
Whether the navigator's tests pass on the task's reference solution is recorded, never shown to the models.
Keys: --nav-key-file / --driver-key-file (a path; the key is read from it, never printed).
"""
import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

LOAD_RETRIES = 30
LOAD_RETRY_SEC = 30
NAV_SYSTEM = (
    "You are the navigator in a pair-programming session. Another model, the driver, writes the code; you plan, "
    "set the checks it must pass, and review. Be brief and concrete. Never write the whole file yourself."
)
PLAN_ASK = (
    "Write the driver's plan for this task: the approach, the edge cases the task implies, the pitfalls, and 3-6 "
    "concrete checks (input -> expected result) the file must pass. At most 15 lines, no code blocks."
)
REVIEW_ASK = (
    "The driver wrote this `{file}`:\n\n{code}\n\nCheck it against the task and your plan. Answer in at most 10 lines "
    "and nothing else: the single word OK, or one line per real defect in the form `line: problem -> fix`. "
    "Ignore style."
)
ARCHITECT_ASK = (
    "Write the complete solution for the driver as precise prose and pseudocode: every function with its exact "
    "behaviour, the data structures, each edge case and how it is handled, the exact output formats. The driver "
    "only translates it into the file, so leave nothing to guess. No code blocks."
)
ANSWER_REVIEW = (
    "First answer every line of the review: `line: fixed` or `line: rejected - <reason>`. Then reply with the "
    "complete `{file}`, even if you rejected everything."
)
FAIL_ASK = (
    "The tests failed on the driver's code:\n```\n{output}\n```\nTell the driver what to change, at most 10 lines, "
    "no code blocks."
)
TEST_FILE = {"python": "test.py", "bash": "test.sh", "kotlin": "Test.kt"}
HARNESS = {
    "python": "`test.py`: `def test_*():` functions with plain `assert`, importing what they test from `{module}`, "
              "and ending with exactly these two lines:\nfrom _runner import main\nmain(globals())\n",
    "bash": "`test.sh`: it starts with `source ./assert.sh`, runs the script as `bash {file} ...` in an empty "
            "temporary directory (it may create files there), compares with `check NAME EXPECTED ACTUAL` (string "
            "equality) and ends with `finish`.",
    "kotlin": "`Test.kt`, compiled together with `{file}`: `fun main() {{ ... finish() }}` holding `check(\"name\") "
              "{{ ... }}` blocks that use `eq(expected, actual)` and `throws<SomeException> {{ ... }}`.",
}
TESTS_ASK = (
    "Now write the tests the driver's file must pass, as {harness} Cover your checks and the edge cases the task "
    "states, 8-20 tests, every expected value derived from the task text alone. Reply with the complete "
    "`{test_file}` in a single fenced code block."
)
TDD_FIX = (
    "Your file fails the navigator's tests:\n```\n{output}\n```\nFix the code. If a failing test contradicts the task, "
    "name it and say why in one line, and keep the behaviour the task requires. Reply with the complete `{file}`."
)


def load_runner(path: Path):
    spec = importlib.util.spec_from_file_location("run_coding_eval", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Model:
    def __init__(self, url, model, key_file, sampling, max_tokens, seed, think=False):
        # devbox provider URLs end in /v1, burnish's --url does not
        self.url = url.rstrip("/").removesuffix("/v1")
        self.model, self.sampling, self.max_tokens, self.seed, self.think = model, sampling, max_tokens, seed, think
        self.key = Path(key_file).read_text().strip() if key_file else None

    def chat(self, messages, max_tokens=None) -> tuple[str, bool, dict, float]:
        body = {"messages": messages, "seed": self.seed, "max_tokens": max_tokens or self.max_tokens,
                "chat_template_kwargs": {"enable_thinking": self.think}, **self.sampling}
        if self.model:
            body["model"] = self.model
        headers = {"Content-Type": "application/json"}
        if self.key:
            headers["Authorization"] = f"Bearer {self.key}"
        req = urllib.request.Request(f"{self.url}/v1/chat/completions", json.dumps(body).encode(), headers)
        # router-mode servers load the model on the first request and drop connections or answer 5xx meanwhile
        for attempt in range(1, LOAD_RETRIES + 1):
            start = time.monotonic()
            try:
                with urllib.request.urlopen(req, timeout=3600) as resp:
                    data = json.load(resp)
                break
            except (urllib.error.URLError, ConnectionError) as e:
                if isinstance(e, urllib.error.HTTPError) and e.code < 500 or attempt == LOAD_RETRIES:
                    raise
                print(f"  {self.url}: {e}; retry {attempt}/{LOAD_RETRIES} in {LOAD_RETRY_SEC} s", flush=True)
                time.sleep(LOAD_RETRY_SEC)
        choice = data["choices"][0]
        return ((choice["message"].get("content") or "").strip(), choice.get("finish_reason") == "length",
                data.get("usage", {}), time.monotonic() - start)


def numbered(code: str) -> str:
    return "\n".join(f"{i:4} {line}" for i, line in enumerate(code.splitlines(), 1))


def run_nav_tests(rce, task, code: str, tests: str) -> tuple[bool, str]:
    """rce.run_tests with the navigator's test file in place of the task's own tests (fixtures are task inputs)."""
    cmd, helper, _ = rce.RUNNERS[task["lang"]]
    with tempfile.TemporaryDirectory(prefix=f"nav-{task['id']}-") as tmp:
        work = Path(tmp)
        shutil.copy(rce.ROOT / "lib" / helper, work / helper)
        for f in task["dir"].iterdir():
            # kotlin's test.sh is the same compile-and-run script in every task, not test content
            if f.name.lower().startswith("fixture") or (task["lang"] == "kotlin" and f.name == "test.sh"):
                shutil.copy(f, work / f.name)
        (work / TEST_FILE[task["lang"]]).write_text(tests)
        (work / task["file"]).write_text(code)
        try:
            proc = rce.run_test_cmd(cmd, work)
        except subprocess.TimeoutExpired:
            return False, f"tests timed out after {rce.TEST_TIMEOUT} s"
        return proc.returncode == 0, (proc.stdout + proc.stderr).strip()


def solve(task, nav: Model, drv: Model, rce, args) -> dict:
    task_text = f"{task['prompt'].strip()}\n\nWrite the file `{task['file']}`."
    ask = ARCHITECT_ASK if args.architect else PLAN_ASK
    nav_msgs = [{"role": "system", "content": NAV_SYSTEM}, {"role": "user", "content": f"{task_text}\n\n{ask}"}]
    plan, _, usage, secs = nav.chat(nav_msgs, args.nav_max_tokens)
    nav_msgs.append({"role": "assistant", "content": plan})
    pending = {"seconds": secs, "nav_tokens": usage.get("completion_tokens") or 0}
    drv_task = f"{task_text}\n\nThe navigator's plan:\n{plan}"
    tests = tests_on_ref = None
    if args.tests_first:
        harness = HARNESS[task["lang"]].format(file=task["file"], module=Path(task["file"]).stem)
        nav_msgs.append({"role": "user", "content": TESTS_ASK.format(harness=harness,
                                                                     test_file=TEST_FILE[task["lang"]])})
        reply, _, usage, secs = nav.chat(nav_msgs, args.tests_max_tokens)
        nav_msgs.append({"role": "assistant", "content": reply})
        pending["seconds"] += secs
        pending["nav_tokens"] += usage.get("completion_tokens") or 0
        tests = rce.extract_code(reply)
        if tests is not None:
            drv_task += f"\n\nThe navigator's tests, `{TEST_FILE[task['lang']]}`; your file must pass them:\n```\n{tests}```"
            ref = task["dir"] / f"ref{Path(task['file']).suffix}"
            tests_on_ref = run_nav_tests(rce, task, ref.read_text(), tests)[0]
    drv_msgs = [{"role": "system", "content": rce.SYSTEM}, {"role": "user", "content": drv_task}]
    attempts = []
    for _ in range(args.attempts):
        stats = {"seconds": pending["seconds"], "nav_tokens": pending["nav_tokens"], "drv_tokens": 0}
        reply, capped, usage, secs = drv.chat(drv_msgs)
        stats["seconds"] += secs
        stats["drv_tokens"] += usage.get("completion_tokens") or 0
        code = rce.extract_code(reply)
        verdict = None
        if code is not None and args.review == "always":
            nav_msgs.append({"role": "user", "content": REVIEW_ASK.format(file=task["file"], code=numbered(code))})
            verdict, _, usage, secs = nav.chat(nav_msgs, args.nav_max_tokens)
            nav_msgs.append({"role": "assistant", "content": verdict})
            stats["seconds"] += secs
            stats["nav_tokens"] += usage.get("completion_tokens") or 0
            if verdict.rstrip(".").upper() != "OK":
                ask = (ANSWER_REVIEW.format(file=task["file"]) if args.answer_review else
                       f"Fix the real defects (ignore findings that are wrong) and reply with the corrected complete "
                       f"`{task['file']}`.")
                drv_msgs += [{"role": "assistant", "content": reply},
                             {"role": "user", "content": f"The navigator reported:\n```\n{verdict}\n```\n{ask}"}]
                reply, capped, usage, secs = drv.chat(drv_msgs)
                stats["seconds"] += secs
                stats["drv_tokens"] += usage.get("completion_tokens") or 0
                revised = rce.extract_code(reply)
                # without --keep-unrevised a revision without a code block fails the attempt (the original protocol)
                code = revised if revised is not None or not args.keep_unrevised else code
        nav_checks = []
        if tests is not None and code is not None:
            for r in range(args.tdd_rounds + 1):
                ok, nav_out = run_nav_tests(rce, task, code, tests)
                nav_checks.append(ok)
                if ok or r == args.tdd_rounds:
                    break
                drv_msgs += [{"role": "assistant", "content": reply},
                             {"role": "user", "content": TDD_FIX.format(output=nav_out[-rce.FEEDBACK_CHARS:],
                                                                        file=task["file"])}]
                reply, capped, usage, secs = drv.chat(drv_msgs)
                stats["seconds"] += secs
                stats["drv_tokens"] += usage.get("completion_tokens") or 0
                fixed = rce.extract_code(reply)
                code = fixed if fixed is not None else code
        if code is None:
            passed = False
            output = f"reply cut off at --max-tokens {args.max_tokens}" if capped else "no fenced code block in the reply"
        else:
            passed, output = rce.run_tests(task, code)
        output = output[-rce.FEEDBACK_CHARS:]
        attempts.append({"passed": passed, "capped": capped, "output": output, "seconds": round(stats["seconds"], 1),
                         "completion_tokens": stats["drv_tokens"] + stats["nav_tokens"],
                         "driver_tokens": stats["drv_tokens"], "navigator_tokens": stats["nav_tokens"],
                         "reply": reply, "review": verdict, **({"plan": plan} if not attempts else {}),
                         **({"nav_checks": nav_checks} if tests is not None else {})})
        if passed:
            break
        nav_msgs.append({"role": "user", "content": FAIL_ASK.format(output=output)})
        advice, _, usage, secs = nav.chat(nav_msgs, args.nav_max_tokens)
        nav_msgs.append({"role": "assistant", "content": advice})
        pending = {"seconds": secs, "nav_tokens": usage.get("completion_tokens") or 0}
        drv_msgs += [{"role": "assistant", "content": reply},
                     {"role": "user", "content": f"The tests failed:\n```\n{output}\n```\nThe navigator says:\n{advice}\n"
                                                 f"Reply with the corrected complete `{task['file']}`."}]
    out = {"id": task["id"], "lang": task["lang"], "attempts": attempts}
    if args.tests_first:
        out.update(nav_tests=tests, nav_tests_on_ref=tests_on_ref)
    return out


def sampling(args, prefix) -> dict:
    out = {"temperature": getattr(args, f"{prefix}_temperature")}
    for key in ("top_p", "top_k", "min_p", "presence_penalty"):
        v = getattr(args, f"{prefix}_{key}")
        if v is not None:
            out[key] = v
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--burnish", default=os.path.expanduser("~/burnish/eval/coding"), help="burnish's eval/coding dir")
    p.add_argument("--nav-url", required=True)
    p.add_argument("--nav-model")
    p.add_argument("--nav-key-file")
    p.add_argument("--driver-url", required=True)
    p.add_argument("--driver-model")
    p.add_argument("--driver-key-file")
    p.add_argument("--label", default="pair")
    p.add_argument("--tasks", default="*")
    p.add_argument("--langs", default="python,bash,kotlin")
    p.add_argument("--attempts", type=int, default=2)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--max-tokens", type=int, default=32768)
    p.add_argument("--nav-max-tokens", type=int, default=1500)
    # defaults: the model cards' non-thinking sampling, as in the Nov 15 runs
    p.add_argument("--nav-temperature", type=float, default=1.0)
    p.add_argument("--nav-top-p", type=float, default=1.0)
    p.add_argument("--nav-top-k", type=int)
    p.add_argument("--nav-min-p", type=float)
    p.add_argument("--nav-presence-penalty", type=float)
    p.add_argument("--driver-temperature", type=float, default=0.7)
    p.add_argument("--driver-top-p", type=float, default=0.8)
    p.add_argument("--driver-top-k", type=int, default=20)
    p.add_argument("--driver-min-p", type=float, default=0.0)
    p.add_argument("--driver-presence-penalty", type=float, default=1.5)
    # protocol variants, all off by default (the original protocol)
    p.add_argument("--review", choices=("always", "on-fail"), default="always",
                   help="on-fail: no navigator review before the first test run, only advice after a failure")
    p.add_argument("--nav-think", action="store_true", help="navigator in thinking mode (raise --nav-max-tokens)")
    p.add_argument("--architect", action="store_true", help="navigator writes the full solution in prose")
    p.add_argument("--answer-review", action="store_true", help="driver answers each review line before the file")
    p.add_argument("--keep-unrevised", action="store_true",
                   help="keep the reviewed code when the driver's revision has no code block")
    p.add_argument("--tests-first", action="store_true",
                   help="navigator writes a test file after the plan; the driver's file must pass it first")
    p.add_argument("--tdd-rounds", type=int, default=2, help="driver fix turns against the navigator's tests")
    p.add_argument("--tests-max-tokens", type=int, default=6000, help="navigator tokens for the test file")
    p.add_argument("--out-dir", default=os.path.expanduser("~/llm_coder/llm/results/pair-eval"))
    args = p.parse_args()

    root = Path(args.burnish)
    rce = load_runner(root / "run_coding_eval.py")
    tasks = rce.load_tasks(root / "tasks", args.tasks, set(args.langs.split(",")))
    if not tasks:
        p.error("no tasks matched")
    nav = Model(args.nav_url, args.nav_model, args.nav_key_file, sampling(args, "nav"), args.nav_max_tokens, args.seed,
                args.nav_think)
    drv = Model(args.driver_url, args.driver_model, args.driver_key_file, sampling(args, "driver"), args.max_tokens,
                args.seed)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    # after each task, so a host hang loses one task, not the seed; a rerun with the same label resumes from it
    partial = out_dir / f"{args.label}.partial.json"
    results = json.loads(partial.read_text())["results"] if partial.exists() else []
    done = {r["id"] for r in results}
    if done:
        print(f"resuming {partial}: {len(done)} tasks done", flush=True)
    for task in tasks:
        if task["id"] in done:
            continue
        r = solve(task, nav, drv, rce, args)
        results.append(r)
        tmp = partial.with_suffix(".tmp")
        tmp.write_text(json.dumps({"results": results}, indent=1))
        os.replace(tmp, partial)
        marks = "".join("+" if a["passed"] else "-" for a in r["attempts"])
        print(f"{task['id']:<28} {marks:<3} {sum(a['seconds'] for a in r['attempts']):7.1f} s", flush=True)
    summary = rce.summarize(results, args.attempts)
    for lang, s in summary.items():
        rs = [r for r in results if lang in ("all", r["lang"])]
        s["navigator_tokens"] = sum(a["navigator_tokens"] for r in rs for a in r["attempts"])
        s["driver_tokens"] = sum(a["driver_tokens"] for r in rs for a in r["attempts"])
    out = out_dir / f"{datetime.now():%Y%m%d-%H%M%S}-{args.label}.json"
    out.write_text(json.dumps({"args": {k: v for k, v in vars(args).items() if not k.endswith("key_file")},
                               "summary": summary, "results": results}, indent=1))
    partial.unlink()
    rce.print_summary(summary, out)


if __name__ == "__main__":
    main()
