"""Replay of the checking role on stored code with a known test outcome: does a reviewer flag the code that fails?

Items are the drafts of stored solo runs (burnish result files; every attempt with a code block), relabelled by
re-running the current tests. All failing drafts are kept plus as many passing ones (fixed random sample), so a run
measures both false alarms (non-OK verdict on passing code) and catches (non-OK verdict on failing code).
--mode review: burnish's independent reviewer (run_coding_eval.review, the DS+rDS setup's reviewer).
--mode nav: the pair navigator (eval_pair.py prompts): a plan turn, then the review turn on the draft.
Run once with and once without --think; everything else stays as in the eval. Resumes from its partial file.
"""
import argparse
import json
import os
import random
import types
from datetime import datetime
from pathlib import Path

import eval_pair as ep


def load_items(rce, tasks, files, seed):
    by_id = {t["id"]: t for t in tasks}
    items = []
    for f in files:
        for r in json.loads(Path(f).read_text())["results"]:
            if r["id"] not in by_id:
                continue
            for i, a in enumerate(r["attempts"]):
                code = rce.extract_code(a.get("reply") or "")
                if code is not None:
                    items.append({"key": f"{Path(f).stem}:{r['id']}:{i + 1}", "id": r["id"], "code": code})
    for it in items:
        it["passed"] = rce.run_tests(by_id[it["id"]], it["code"])[0]
    fails = [it for it in items if not it["passed"]]
    passes = [it for it in items if it["passed"]]
    random.Random(seed).shuffle(passes)
    return fails + passes[:len(fails)]


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--burnish", default=os.path.expanduser("~/burnish/eval/coding"))
    p.add_argument("--mode", choices=("review", "nav"), required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--model")
    p.add_argument("--key-file")
    p.add_argument("--think", action="store_true")
    p.add_argument("--max-tokens", type=int, help="default: 600 (review) / 1500 (nav), as in the eval")
    p.add_argument("--temperature", type=float, help="default: burnish's 0.2 (review) / DeepSeek's 1.0 (nav)")
    p.add_argument("--top-p", type=float, default=1.0)
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--per-class", type=int, help="random subset: this many failing and as many passing items")
    p.add_argument("--files", nargs="+", required=True, help="stored solo result files (the drafts)")
    p.add_argument("--label", required=True)
    p.add_argument("--out-dir", default=os.path.expanduser("~/llm_coder/llm/results/thinking-check"))
    args = p.parse_args()
    max_tokens = args.max_tokens or (600 if args.mode == "review" else 1500)
    temperature = args.temperature if args.temperature is not None else (0.2 if args.mode == "review" else 1.0)

    rce = ep.load_runner(Path(args.burnish) / "run_coding_eval.py")
    tasks = rce.load_tasks(Path(args.burnish) / "tasks", "*", {"python", "bash", "kotlin"})
    by_id = {t["id"]: t for t in tasks}
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    partial = out_dir / f"{args.label}.partial.json"
    state = json.loads(partial.read_text()) if partial.exists() else {"items": None, "results": []}
    if state["items"] is None:
        print("== labelling the stored drafts (current tests)", flush=True)
        state["items"] = load_items(rce, tasks, args.files, args.seed)
        if args.per_class:
            rng = random.Random(args.seed)
            fails = [i for i in state["items"] if not i["passed"]]
            passes = [i for i in state["items"] if i["passed"]]
            state["items"] = rng.sample(fails, args.per_class) + rng.sample(passes, args.per_class)
    done = {r["key"] for r in state["results"]}
    print(f"{len(state['items'])} items ({sum(not i['passed'] for i in state['items'])} failing), {len(done)} done",
          flush=True)

    if args.mode == "review":
        if args.key_file:
            os.environ["CODING_EVAL_REVIEW_KEY"] = Path(args.key_file).read_text().strip()
        rargs = types.SimpleNamespace(seed=args.seed, review_model=args.model, review_url=args.url.removesuffix("/v1"),
                                      review_max_tokens=max_tokens, review_think=args.think,
                                      review_temperature=temperature)
    else:
        nav = ep.Model(args.url, args.model, args.key_file, {"temperature": temperature, "top_p": args.top_p},
                       max_tokens, args.seed, args.think)

    for it in state["items"]:
        if it["key"] in done:
            continue
        task = by_id[it["id"]]
        rec = {"key": it["key"], "id": it["id"], "passed": it["passed"]}
        if args.mode == "review":
            verdict, secs = rce.review(task["prompt"].strip(), it["code"], rargs)
            rec.update(verdict=verdict, seconds=round(secs, 1))
        else:
            task_text = f"{task['prompt'].strip()}\n\nWrite the file `{task['file']}`."
            msgs = [{"role": "system", "content": ep.NAV_SYSTEM},
                    {"role": "user", "content": f"{task_text}\n\n{ep.PLAN_ASK}"}]
            plan, plan_capped, u1, s1 = nav.chat(msgs)
            msgs += [{"role": "assistant", "content": plan},
                     {"role": "user", "content": ep.REVIEW_ASK.format(file=task["file"], code=ep.numbered(it["code"]))}]
            verdict, capped, u2, s2 = nav.chat(msgs)
            rec.update(plan=plan, verdict=verdict, capped=plan_capped or capped, seconds=round(s1 + s2, 1),
                       tokens=(u1.get("completion_tokens") or 0) + (u2.get("completion_tokens") or 0))
        rec["flagged"] = verdict.rstrip(".").upper() != "OK"
        state["results"].append(rec)
        tmp = partial.with_suffix(".tmp")
        tmp.write_text(json.dumps(state, indent=1))
        os.replace(tmp, partial)
        print(f"{it['key']:<70} {'pass' if it['passed'] else 'FAIL'} {'flag' if rec['flagged'] else 'ok  '} "
              f"{rec['seconds']:7.1f} s", flush=True)

    rs = state["results"]
    on_pass = [r for r in rs if r["passed"]]
    on_fail = [r for r in rs if not r["passed"]]
    summary = {"items": len(rs), "passing": len(on_pass), "failing": len(on_fail),
               "false_alarms": sum(r["flagged"] for r in on_pass), "catches": sum(r["flagged"] for r in on_fail),
               "empty_verdicts": sum(not r["verdict"] for r in rs),
               "seconds": round(sum(r["seconds"] for r in rs), 1)}
    if args.mode == "nav":
        summary.update(capped=sum(r["capped"] for r in rs), tokens=sum(r["tokens"] for r in rs))
    out = out_dir / f"{datetime.now():%Y%m%d-%H%M%S}-{args.label}.json"
    out.write_text(json.dumps({"args": {k: v for k, v in vars(args).items() if k != "key_file"},
                               "summary": summary, "results": rs}, indent=1))
    partial.unlink()
    print(json.dumps(summary), out, flush=True)


if __name__ == "__main__":
    main()
