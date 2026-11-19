"""Pair-programming coding eval: a navigator model plans and reviews, a driver model writes the code.

Runs burnish's coding eval tasks (eval/coding in the burnish repo) with its own task loading, tests and scoring,
so pass@k / tests@k compare directly with plain run_coding_eval.py results. Per task and attempt:
  1. navigator: short plan and checks (first attempt only)
  2. driver: writes the file from the task and the plan
  3. navigator reviews the code in the same conversation; unless OK, the driver revises once
  4. the tests run; on failure the navigator turns the test output into a fix instruction for the next attempt
The navigator keeps one conversation per task, so llama-server reuses its prompt prefix between turns.
Keys: --nav-key-file / --driver-key-file (a path; the key is read from it, never printed).
"""
import argparse
import importlib.util
import json
import os
import time
import urllib.request
from datetime import datetime
from pathlib import Path

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
FAIL_ASK = (
    "The tests failed on the driver's code:\n```\n{output}\n```\nTell the driver what to change, at most 10 lines, "
    "no code blocks."
)


def load_runner(path: Path):
    spec = importlib.util.spec_from_file_location("run_coding_eval", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Model:
    def __init__(self, url, model, key_file, sampling, max_tokens, seed):
        # devbox provider URLs end in /v1, burnish's --url does not
        self.url = url.rstrip("/").removesuffix("/v1")
        self.model, self.sampling, self.max_tokens, self.seed = model, sampling, max_tokens, seed
        self.key = Path(key_file).read_text().strip() if key_file else None

    def chat(self, messages, max_tokens=None) -> tuple[str, bool, dict, float]:
        body = {"messages": messages, "seed": self.seed, "max_tokens": max_tokens or self.max_tokens,
                "chat_template_kwargs": {"enable_thinking": False}, **self.sampling}
        if self.model:
            body["model"] = self.model
        headers = {"Content-Type": "application/json"}
        if self.key:
            headers["Authorization"] = f"Bearer {self.key}"
        req = urllib.request.Request(f"{self.url}/v1/chat/completions", json.dumps(body).encode(), headers)
        start = time.monotonic()
        with urllib.request.urlopen(req, timeout=3600) as resp:
            data = json.load(resp)
        choice = data["choices"][0]
        return ((choice["message"].get("content") or "").strip(), choice.get("finish_reason") == "length",
                data.get("usage", {}), time.monotonic() - start)


def numbered(code: str) -> str:
    return "\n".join(f"{i:4} {line}" for i, line in enumerate(code.splitlines(), 1))


def solve(task, nav: Model, drv: Model, rce, args) -> dict:
    task_text = f"{task['prompt'].strip()}\n\nWrite the file `{task['file']}`."
    nav_msgs = [{"role": "system", "content": NAV_SYSTEM}, {"role": "user", "content": f"{task_text}\n\n{PLAN_ASK}"}]
    plan, _, usage, secs = nav.chat(nav_msgs, args.nav_max_tokens)
    nav_msgs.append({"role": "assistant", "content": plan})
    pending = {"seconds": secs, "nav_tokens": usage.get("completion_tokens") or 0}
    drv_msgs = [{"role": "system", "content": rce.SYSTEM},
                {"role": "user", "content": f"{task_text}\n\nThe navigator's plan:\n{plan}"}]
    attempts = []
    for _ in range(args.attempts):
        stats = {"seconds": pending["seconds"], "nav_tokens": pending["nav_tokens"], "drv_tokens": 0}
        reply, capped, usage, secs = drv.chat(drv_msgs)
        stats["seconds"] += secs
        stats["drv_tokens"] += usage.get("completion_tokens") or 0
        code = rce.extract_code(reply)
        verdict = None
        if code is not None:
            nav_msgs.append({"role": "user", "content": REVIEW_ASK.format(file=task["file"], code=numbered(code))})
            verdict, _, usage, secs = nav.chat(nav_msgs, args.nav_max_tokens)
            nav_msgs.append({"role": "assistant", "content": verdict})
            stats["seconds"] += secs
            stats["nav_tokens"] += usage.get("completion_tokens") or 0
            if verdict.rstrip(".").upper() != "OK":
                drv_msgs += [{"role": "assistant", "content": reply},
                             {"role": "user", "content": f"The navigator reported:\n```\n{verdict}\n```\nFix the real "
                                                         f"defects (ignore findings that are wrong) and reply with the "
                                                         f"corrected complete `{task['file']}`."}]
                reply, capped, usage, secs = drv.chat(drv_msgs)
                stats["seconds"] += secs
                stats["drv_tokens"] += usage.get("completion_tokens") or 0
                code = rce.extract_code(reply)
        if code is None:
            passed = False
            output = f"reply cut off at --max-tokens {args.max_tokens}" if capped else "no fenced code block in the reply"
        else:
            passed, output = rce.run_tests(task, code)
        output = output[-rce.FEEDBACK_CHARS:]
        attempts.append({"passed": passed, "capped": capped, "output": output, "seconds": round(stats["seconds"], 1),
                         "completion_tokens": stats["drv_tokens"] + stats["nav_tokens"],
                         "driver_tokens": stats["drv_tokens"], "navigator_tokens": stats["nav_tokens"],
                         "reply": reply, "review": verdict, **({"plan": plan} if not attempts else {})})
        if passed:
            break
        nav_msgs.append({"role": "user", "content": FAIL_ASK.format(output=output)})
        advice, _, usage, secs = nav.chat(nav_msgs, args.nav_max_tokens)
        nav_msgs.append({"role": "assistant", "content": advice})
        pending = {"seconds": secs, "nav_tokens": usage.get("completion_tokens") or 0}
        drv_msgs += [{"role": "assistant", "content": reply},
                     {"role": "user", "content": f"The tests failed:\n```\n{output}\n```\nThe navigator says:\n{advice}\n"
                                                 f"Reply with the corrected complete `{task['file']}`."}]
    return {"id": task["id"], "lang": task["lang"], "attempts": attempts}


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
    p.add_argument("--out-dir", default=os.path.expanduser("~/llm_coder/llm/results/pair-eval"))
    args = p.parse_args()

    root = Path(args.burnish)
    rce = load_runner(root / "run_coding_eval.py")
    tasks = rce.load_tasks(root / "tasks", args.tasks, set(args.langs.split(",")))
    if not tasks:
        p.error("no tasks matched")
    nav = Model(args.nav_url, args.nav_model, args.nav_key_file, sampling(args, "nav"), args.nav_max_tokens, args.seed)
    drv = Model(args.driver_url, args.driver_model, args.driver_key_file, sampling(args, "driver"), args.max_tokens,
                args.seed)
    results = []
    for task in tasks:
        r = solve(task, nav, drv, rce, args)
        results.append(r)
        marks = "".join("+" if a["passed"] else "-" for a in r["attempts"])
        print(f"{task['id']:<28} {marks:<3} {sum(a['seconds'] for a in r['attempts']):7.1f} s", flush=True)
    summary = rce.summarize(results, args.attempts)
    for lang, s in summary.items():
        rs = [r for r in results if lang in ("all", r["lang"])]
        s["navigator_tokens"] = sum(a["navigator_tokens"] for r in rs for a in r["attempts"])
        s["driver_tokens"] = sum(a["driver_tokens"] for r in rs for a in r["attempts"])
    out = Path(args.out_dir) / f"{datetime.now():%Y%m%d-%H%M%S}-{args.label}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"args": {k: v for k, v in vars(args).items() if not k.endswith("key_file")},
                               "summary": summary, "results": results}, indent=1))
    rce.print_summary(summary, out)


if __name__ == "__main__":
    main()
