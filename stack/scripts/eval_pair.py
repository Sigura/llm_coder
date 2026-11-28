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
--tests-only: only the navigator's plan and test turns, no driver: a cheap replay that scores the test writer alone
(how many of its test files pass the reference), e.g. with and without --nav-think.
--batch N: N consecutive tasks share one navigator and one driver conversation, like a PR with N changes: one plan
turn, one driver turn writing all N files, one review turn over all of them, one revision turn for the files the
review flagged; after the tests, one advice turn and one fix turn for the failed tasks. Scored per task; each turn's
time and tokens are split evenly over the tasks in it.
--task-dir: task folders in burnish's format from elsewhere (e.g. stack/eval/tasks-joined), still run with burnish's
harness.
Keys: --nav-key-file / --driver-key-file (a path; the key is read from it, never printed).
"""
import argparse
import http.client
import importlib.util
import json
import os
import re
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
STREAM_IDLE_SEC = 1800
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
              "and ending with exactly these two lines:\nfrom _runner import main\nmain(globals())\n"
              "Only the standard library is installed (no pytest): check exceptions with try/except.",
    "bash": "`test.sh`: it starts with `source ./assert.sh`, runs the script as `bash {file} ...` in a temporary "
            "directory that holds only `{file}`, `assert.sh` and the fixture files the task names (it may create files there; after a `cd` elsewhere, "
            "call the script by the absolute path saved before it), compares with `check NAME EXPECTED ACTUAL` "
            "(string equality) and ends with `finish`.",
    "kotlin": "`Test.kt`, compiled together with `{file}`: `fun main() {{ ... finish() }}` holding `check(\"name\") "
              "{{ ... }}` blocks that use `eq(expected, actual)` and `throws<SomeException> {{ ... }}`. These four "
              "come from the harness's TestKit.kt, compiled with it: do not define them, or anything else named "
              "`check`, `eq`, `throws`, `finish`, `passed` or `failed`.",
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
BATCH_SYSTEM = (
    "You are an expert software engineer. You get several tasks at once. For every file you are asked for, reply "
    "with a line `### <task id>` followed by the complete contents of that task's file in a single fenced code block. "
    "Do not omit any part of a file."
)
BATCH_PLAN_ASK = (
    "Write the driver's plan for each task: the approach, the edge cases, the pitfalls, and 3-6 concrete checks "
    "(input -> expected result). For each task a line `### <task id>`, then at most 15 lines, no code blocks."
)
BATCH_REVIEW_ASK = (
    "The driver wrote these files:\n\n{files}\n\nCheck each against its task and your plan. For each task a line "
    "`### <task id>`, then at most 10 lines and nothing else: the single word OK, or one line per real defect in the "
    "form `line: problem -> fix`. Ignore style."
)
BATCH_FAIL_ASK = (
    "The tests failed on these files:\n\n{outputs}\n\nTell the driver what to change: for each task a line "
    "`### <task id>`, then at most 10 lines, no code blocks."
)
HEADER = re.compile(r"^#{1,6}[ \t]*`?([A-Za-z0-9_.-]+)`?[ \t:]*$", re.M)


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
                "chat_template_kwargs": {"enable_thinking": self.think, "thinking": self.think}, "stream": True,
                "stream_options": {"include_usage": True}, **self.sampling}
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
                return self._read_stream(req, start)
            except (urllib.error.URLError, ConnectionError, http.client.IncompleteRead) as e:
                if isinstance(e, urllib.error.HTTPError) and e.code < 500 or attempt == LOAD_RETRIES:
                    raise
                print(f"  {self.url}: {e}; retry {attempt}/{LOAD_RETRIES} in {LOAD_RETRY_SEC} s", flush=True)
                time.sleep(LOAD_RETRY_SEC)

    @staticmethod
    def _read_stream(req, start) -> tuple[str, bool, dict, float]:
        # streamed, the timeout limits the silence between tokens rather than the whole reply: a 32k-token reply
        # takes over an hour on KT decoding two streams; the first token waits for the prefill
        parts, finish, usage = [], None, None
        with urllib.request.urlopen(req, timeout=STREAM_IDLE_SEC) as resp:
            for line in resp:
                line = line.strip()
                if not line.startswith(b"data:"):
                    continue
                payload = line[5:].strip()
                if payload == b"[DONE]":
                    break
                chunk = json.loads(payload)
                usage = chunk.get("usage") or usage
                for choice in chunk.get("choices") or []:
                    parts.append((choice.get("delta") or {}).get("content") or "")
                    finish = choice.get("finish_reason") or finish
        if finish is None:
            raise ConnectionError("stream ended without a finish_reason")
        if usage is None:
            raise RuntimeError(f"{req.full_url}: no usage in the stream (stream_options.include_usage unsupported?)")
        return "".join(parts).strip(), finish == "length", usage, time.monotonic() - start


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


def fast_feedback(rce, task, code: str, drv: Model, args, plan_state: dict, stats: dict) -> tuple[bool, str, str]:
    """burnish's --feedback checks; the smoke example is planned by the driver (the writer) in a separate call."""
    ok, out = rce.compile_gate(task, code)
    if not ok or args.feedback == "compile" or task["lang"] == "kotlin":
        return ok, "compile", out
    if "plan" not in plan_state:
        reply, _, usage, secs = drv.chat([{"role": "system", "content": rce.SMOKE_SYSTEM},
                                          {"role": "user", "content": rce.smoke_ask(task, code)}])
        stats["seconds"] += secs
        stats["drv_tokens"] += usage.get("completion_tokens") or 0
        plan_state["plan"] = rce.parse_smoke_plan(reply)
    if plan_state["plan"] is None:
        return True, "smoke", "no usable example plan"
    ok, out = rce.smoke_run(task, code, plan_state["plan"])
    if not ok and args.feedback == "smoke-judged":
        reply, _, usage, secs = drv.chat([{"role": "system", "content": rce.SMOKE_JUDGE_SYSTEM},
                                          {"role": "user", "content": f"Task: {task['prompt'].strip()}\n\nRun:\n"
                                                                      f"```\n{out}\n```"}])
        stats["seconds"] += secs
        stats["drv_tokens"] += usage.get("completion_tokens") or 0
        if "EXPECTATION" in re.sub(r"<think>.*?</think>", "", reply or "", flags=re.S).upper():
            return True, "smoke", f"judge: expectation wrong\n{out}"
    return ok, "smoke", out


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
        reply, tests_capped, usage, secs = nav.chat(nav_msgs, args.tests_max_tokens)
        nav_msgs.append({"role": "assistant", "content": reply})
        pending["seconds"] += secs
        pending["nav_tokens"] += usage.get("completion_tokens") or 0
        tests = rce.extract_code(reply)
        if tests is not None:
            drv_task += f"\n\nThe navigator's tests, `{TEST_FILE[task['lang']]}`; your file must pass them:\n```\n{tests}```"
            ref = task["dir"] / f"ref{Path(task['file']).suffix}"
            tests_on_ref = run_nav_tests(rce, task, ref.read_text(), tests)[0]
        if args.tests_only:
            return {"id": task["id"], "lang": task["lang"], "plan": plan, "nav_tests": tests,
                    "nav_tests_on_ref": tests_on_ref, "tests_capped": tests_capped,
                    "seconds": round(pending["seconds"], 1), "navigator_tokens": pending["nav_tokens"]}
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
        checks = []
        if args.feedback != "off" and code is not None:
            plan_state = {}
            for r in range(args.feedback_rounds + 1):
                ok, stage, out = fast_feedback(rce, task, code, drv, args, plan_state, stats)
                checks.append({"stage": stage, "ok": ok, "output": out[-500:]})
                if ok or r == args.feedback_rounds:
                    break
                drv_msgs += [{"role": "assistant", "content": reply},
                             {"role": "user", "content": rce.FF_FIX.format(output=out[-rce.FEEDBACK_CHARS:], note="",
                                                                           file=task["file"])}]
                reply, capped, usage, secs = drv.chat(drv_msgs)
                stats["seconds"] += secs
                stats["drv_tokens"] += usage.get("completion_tokens") or 0
                code = rce.extract_code(reply)
                if code is None:
                    break
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
                         **({"nav_checks": nav_checks} if tests is not None else {}),
                         **({"feedback": checks} if checks else {})})
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


def sections(reply: str, ids) -> dict:
    """{task id: text under its `### <id>` header} for the ids that have a header in the reply."""
    reply = re.sub(r"<think>.*?</think>", "", reply, flags=re.S)
    heads = [m for m in HEADER.finditer(reply) if m[1] in ids]
    out = {}
    for m, nxt in zip(heads, heads[1:] + [None]):
        out.setdefault(m[1], reply[m.end():nxt.start() if nxt else len(reply)].strip())
    return out


def solve_batch(tasks, nav: Model, drv: Model, rce, args) -> list[dict]:
    by_id = {t["id"]: t for t in tasks}
    listing = "\n\n".join(f"### {t['id']}\n{t['prompt'].strip()}\n\nWrite the file `{t['file']}`." for t in tasks)
    nav_msgs = [{"role": "system", "content": NAV_SYSTEM}, {"role": "user", "content": f"{listing}\n\n{BATCH_PLAN_ASK}"}]
    stats = {t["id"]: {"seconds": 0.0, "nav_tokens": 0, "drv_tokens": 0} for t in tasks}

    def turn(model, msgs, ids, role, max_tokens=None):
        reply, capped, usage, secs = model.chat(msgs, max_tokens)
        for i in ids:
            stats[i]["seconds"] += secs / len(ids)
            stats[i][f"{role}_tokens"] += (usage.get("completion_tokens") or 0) / len(ids)
        return reply, capped

    plan, _ = turn(nav, nav_msgs, list(by_id), "nav", args.nav_max_tokens)
    nav_msgs.append({"role": "assistant", "content": plan})
    plans = sections(plan, by_id)
    drv_msgs = [{"role": "system", "content": BATCH_SYSTEM},
                {"role": "user", "content": f"{listing}\n\nThe navigator's plan:\n{plan}"}]
    results = {t["id"]: {"id": t["id"], "lang": t["lang"], "batch": list(by_id), "attempts": []} for t in tasks}
    active = list(by_id)
    for _ in range(args.attempts):
        reply, capped = turn(drv, drv_msgs, active, "drv")
        files = sections(reply, active)
        codes = {i: rce.extract_code(files.get(i, "")) for i in active}
        verdicts = {}
        written = [i for i in active if codes[i] is not None]
        if written and args.review == "always":
            shown = "\n\n".join(f"### {i}\n`{by_id[i]['file']}`:\n{numbered(codes[i])}" for i in written)
            nav_msgs.append({"role": "user", "content": BATCH_REVIEW_ASK.format(files=shown)})
            review, _ = turn(nav, nav_msgs, written, "nav", args.nav_max_tokens * len(written))
            nav_msgs.append({"role": "assistant", "content": review})
            verdicts = sections(review, written)
            flagged = [i for i in written if verdicts.get(i, "OK").rstrip(".").upper() != "OK"]
            if flagged:
                found = "\n\n".join(f"### {i}\n{verdicts[i]}" for i in flagged)
                drv_msgs += [{"role": "assistant", "content": reply},
                             {"role": "user", "content": f"The navigator reported:\n```\n{found}\n```\nFix the real "
                                                         f"defects (ignore findings that are wrong) and reply with the "
                                                         f"corrected complete files of these tasks only: "
                                                         f"{', '.join(flagged)}."}]
                reply, capped = turn(drv, drv_msgs, flagged, "drv")
                revised = sections(reply, flagged)
                for i in flagged:
                    new = rce.extract_code(revised.get(i, ""))
                    # without --keep-unrevised a revision without a code block fails the attempt (the original protocol)
                    codes[i] = new if new is not None or not args.keep_unrevised else codes[i]
        failed = {}
        for i in active:
            if codes[i] is None:
                passed = False
                output = (f"reply cut off at --max-tokens {args.max_tokens}" if capped else
                          "no fenced code block under its header in the reply")
            else:
                passed, output = rce.run_tests(by_id[i], codes[i])
            output = output[-rce.FEEDBACK_CHARS:]
            s = stats[i]
            results[i]["attempts"].append({
                "passed": passed, "capped": capped, "output": output, "seconds": round(s["seconds"], 1),
                "completion_tokens": round(s["drv_tokens"] + s["nav_tokens"]), "driver_tokens": round(s["drv_tokens"]),
                "navigator_tokens": round(s["nav_tokens"]), "code": codes[i], "review": verdicts.get(i),
                **({"plan": plans.get(i)} if len(results[i]["attempts"]) == 0 else {})})
            stats[i] = {"seconds": 0.0, "nav_tokens": 0, "drv_tokens": 0}
            if not passed:
                failed[i] = output
        active = list(failed)
        if not active or len(results[active[0]]["attempts"]) == args.attempts:
            break
        outputs = "\n\n".join(f"### {i}\n```\n{o}\n```" for i, o in failed.items())
        nav_msgs.append({"role": "user", "content": BATCH_FAIL_ASK.format(outputs=outputs)})
        advice, _ = turn(nav, nav_msgs, active, "nav", args.nav_max_tokens * len(active))
        nav_msgs.append({"role": "assistant", "content": advice})
        drv_msgs += [{"role": "assistant", "content": reply},
                     {"role": "user", "content": f"The tests failed:\n\n{outputs}\n\nThe navigator says:\n{advice}\n"
                                                 f"Reply with the corrected complete files of these tasks only: "
                                                 f"{', '.join(active)}."}]
    return [results[t["id"]] for t in tasks]


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
    p.add_argument("--driver-url", help="required unless --tests-only")
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
    p.add_argument("--tests-only", action="store_true", help="navigator plan + tests turns only, no driver")
    p.add_argument("--tests-max-tokens", type=int, default=6000, help="navigator tokens for the test file")
    p.add_argument("--feedback", choices=("off", "compile", "smoke", "smoke-judged"), default="off",
                   help="burnish's checks before the real tests (after review and --tests-first), failures go back "
                        "to the driver; smoke-judged: the driver first decides whether a smoke mismatch is the code's fault")
    p.add_argument("--feedback-rounds", type=int, default=2, help="driver fix turns per attempt for --feedback")
    p.add_argument("--batch", type=int, default=1, help="tasks per shared session (see the module doc)")
    p.add_argument("--task-dir", help="task folders to run instead of burnish's eval/coding/tasks")
    p.add_argument("--out-dir", default=os.path.expanduser("~/llm_coder/llm/results/pair-eval"))
    args = p.parse_args()
    if args.batch < 1:
        p.error("--batch must be >= 1")
    if args.tests_only:
        args.tests_first = True
    elif not args.driver_url:
        p.error("--driver-url is required unless --tests-only")
    if args.batch > 1 and (args.tests_first or args.architect or args.answer_review or args.review != "always"
                           or args.feedback != "off"):
        p.error("--batch supports only the original protocol, optionally with --keep-unrevised and --nav-think")

    root = Path(args.burnish)
    rce = load_runner(root / "run_coding_eval.py")
    tasks = rce.load_tasks(Path(args.task_dir) if args.task_dir else root / "tasks", args.tasks,
                           set(args.langs.split(",")))
    if not tasks:
        p.error("no tasks matched")
    nav = Model(args.nav_url, args.nav_model, args.nav_key_file, sampling(args, "nav"), args.nav_max_tokens, args.seed,
                args.nav_think)
    drv = None if args.tests_only else Model(args.driver_url, args.driver_model, args.driver_key_file,
                                             sampling(args, "driver"), args.max_tokens, args.seed)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    # after each task, so a host hang loses one task, not the seed; a rerun with the same label resumes from it
    partial = out_dir / f"{args.label}.partial.json"
    results = json.loads(partial.read_text())["results"] if partial.exists() else []
    done = {r["id"] for r in results}
    if done:
        print(f"resuming {partial}: {len(done)} tasks done", flush=True)
    for b in range(0, len(tasks), args.batch):
        group = [t for t in tasks[b:b + args.batch] if t["id"] not in done]
        if not group:
            continue
        rs = solve_batch(group, nav, drv, rce, args) if args.batch > 1 else [solve(group[0], nav, drv, rce, args)]
        results += rs
        tmp = partial.with_suffix(".tmp")
        tmp.write_text(json.dumps({"results": results}, indent=1))
        os.replace(tmp, partial)
        for r in rs:
            if args.tests_only:
                mark = {True: "ref+", False: "ref-", None: "none"}[r["nav_tests_on_ref"]]
                print(f"{r['id']:<28} {mark:<4} {r['seconds']:7.1f} s", flush=True)
                continue
            marks = "".join("+" if a["passed"] else "-" for a in r["attempts"])
            print(f"{r['id']:<28} {marks:<3} {sum(a['seconds'] for a in r['attempts']):7.1f} s", flush=True)
    if args.tests_only:
        summary = {}
        for lang in ("all", *sorted({r["lang"] for r in results})):
            rs = [r for r in results if lang in ("all", r["lang"])]
            summary[lang] = {"tasks": len(rs), "tests_on_ref": sum(r["nav_tests_on_ref"] is True for r in rs),
                             "no_tests": sum(r["nav_tests"] is None for r in rs),
                             "tests_capped": sum(r["tests_capped"] for r in rs),
                             "seconds": round(sum(r["seconds"] for r in rs), 1),
                             "navigator_tokens": sum(r["navigator_tokens"] for r in rs)}
        out = out_dir / f"{datetime.now():%Y%m%d-%H%M%S}-{args.label}.json"
        out.write_text(json.dumps({"args": {k: v for k, v in vars(args).items() if not k.endswith("key_file")},
                                   "summary": summary, "results": results}, indent=1))
        partial.unlink()
        print(json.dumps(summary["all"]), out, flush=True)
        return
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
