"""RCO for Qwen3-Coder-Next 80B-A3B: budget-constrained per-layer-group expert quant types with stock llama.cpp tools.

Port of burnish quant/rco_lite.py (gemma4:26b-a4b). Differences:
- calibration and KL divergence run on coding-agent text (make_calib.py), 4096-token chunks;
- candidates are K-quants plus IQ3_S (Coder-Next expert rows are 512/2048 wide, so 256-blocks fit);
- variants are not written out: every candidate type is split once into per-group GGUF shards, and a variant is a
  directory of symlinks to the shards it needs (llama.cpp loads it as an ordinary split model).

Steps (subcommands, in order): imatrix, kld-base, quantize, sweep, allocate, build.
The bf16 steps run on GPUs 2,3 plus CPU; set CUDA_VISIBLE_DEVICES before calling them (run_rco.sh does).
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(os.environ.get("LLM_ROOT", Path.home() / "llm_coder/llm"))
WORK = ROOT / "quant-work"
BIN = ROOT / "engines/llama.cpp-current/bin"
BF16 = ROOT / "models/qwen3-coder-next-bf16/current/BF16/Qwen3-Coder-Next-BF16-00001-of-00004.gguf"
DATA = WORK / "data"
IMATRIX = WORK / "imatrix.gguf"
KLD_BASE = WORK / "kld/bf16.kld"
DB = WORK / "db"
SHARDS = WORK / "shards"
VARIANTS = WORK / "variants"
OUT = WORK / "out"

sys.path.insert(0, str(WORK / "gguf-py"))
os.environ.setdefault("CUDA_DEVICE_ORDER", "PCI_BUS_ID")

N_LAYERS = 48
GROUP = 4  # one full-attention layer per group (full_attention_interval = 4)
GROUPS = [list(range(i, i + GROUP)) for i in range(0, N_LAYERS, GROUP)]
KINDS = {"gu": r"ffn_(gate|up)_exps", "dn": r"ffn_down_exps"}
OPTIONS = {"gu": ["q2_k", "iq3_s", "q3_k", "q4_k"], "dn": ["q3_k", "q4_k", "q5_k"]}
BASE = {"gu": "q3_k", "dn": "q4_k"}
# Non-expert tensors (attention, linear attention, shared experts, embeddings): 3% of the weights, kept at Q6_K.
REST_FTYPE = "Q6_K"
CTX = 4096
KLD_CHUNKS = 24
THREADS = int(os.environ.get("RCO_THREADS", "48"))
N_SPLIT = 1 + len(KINDS) * len(GROUPS)


def run(cmd, log=None):
    print("$", " ".join(map(str, cmd)), flush=True)
    if log is None:
        subprocess.run(list(map(str, cmd)), check=True)
        return ""
    with open(log, "w") as f:
        subprocess.run(list(map(str, cmd)), check=True, stdout=f, stderr=subprocess.STDOUT)
    return Path(log).read_text(errors="replace")


def need(*paths):
    for p in paths:
        if not Path(p).exists():
            raise SystemExit(f"missing {p}: run the earlier step first")


def kind_of(name):
    for kind, pat in KINDS.items():
        m = re.fullmatch(rf"blk\.(\d+)\.{pat}\.weight", name)
        if m:
            return kind, int(m.group(1))
    return None, None


def shard_index(kind, gi):
    return 1 + list(KINDS).index(kind) * len(GROUPS) + gi


def shard_path(kind, qtype, gi):
    return SHARDS / f"{kind}-{qtype}" / f"g{gi:02d}.gguf"


def cmd_imatrix(args):
    need(BF16, DATA / "calib.txt")
    run([BIN / "llama-imatrix", "-m", BF16, "-f", DATA / "calib.txt", "-o", IMATRIX, "-c", CTX, "--parse-special",
         "-t", THREADS, "--chunks", args.chunks], log=WORK / "imatrix.log")


def cmd_kld_base(_):
    need(BF16, DATA / "test.txt")
    KLD_BASE.parent.mkdir(parents=True, exist_ok=True)
    run([BIN / "llama-perplexity", "-m", BF16, "-f", DATA / "test.txt", "-c", CTX, "--chunks", KLD_CHUNKS,
         "-t", THREADS, "--kl-divergence-base", KLD_BASE], log=WORK / "kld-base.log")


def write_shard(out, idx, tensors, arch, kv_from=None):
    """Writes one split shard holding `tensors` (GGUFReader tensors). Shard 0 also carries every KV of `kv_from`."""
    import gguf

    tmp = out.with_suffix(".part")
    writer = gguf.GGUFWriter(tmp, arch=arch)
    if kv_from is not None:
        for field in kv_from.fields.values():
            if field.name in ("general.architecture",) or field.name.startswith(("GGUF.", "split.")):
                continue
            sub = field.types[-1] if field.types[0] == gguf.GGUFValueType.ARRAY else None
            writer.add_key_value(field.name, field.contents(), field.types[0], sub_type=sub)
        writer.add_key_value("split.tensors.count", sum(1 for _ in kv_from.tensors), gguf.GGUFValueType.INT32)
    writer.add_key_value("split.no", idx, gguf.GGUFValueType.UINT16)
    writer.add_key_value("split.count", N_SPLIT, gguf.GGUFValueType.UINT16)
    for t in tensors:
        writer.add_tensor_info(t.name, t.data.shape, t.data.dtype, t.data.nbytes, t.tensor_type)
    writer.write_header_to_file()
    writer.write_kv_data_to_file()
    writer.write_ti_data_to_file()
    for t in tensors:
        writer.write_tensor_data(t.data)
    writer.close()
    tmp.rename(out)


def split_db(path, gu, dn, with_rest):
    """Cuts one fully quantized model into the per-group expert shards (and, for the base mix, the rest shard)."""
    import gguf

    reader = gguf.GGUFReader(path)
    arch = reader.fields["general.architecture"].contents()
    by_shard = {}
    rest = []
    for t in reader.tensors:
        kind, layer = kind_of(t.name)
        if kind is None:
            rest.append(t)
        else:
            by_shard.setdefault((kind, layer // GROUP), []).append(t)
    for (kind, gi), tensors in sorted(by_shard.items()):
        out = shard_path(kind, gu if kind == "gu" else dn, gi)
        if out.exists():
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        write_shard(out, shard_index(kind, gi), tensors, arch)
    if with_rest and not (SHARDS / "rest.gguf").exists():
        write_shard(SHARDS / "rest.gguf", 0, rest, arch, kv_from=reader)


def cmd_quantize(_):
    need(BF16, IMATRIX)
    DB.mkdir(parents=True, exist_ok=True)
    mixes = [(BASE["gu"], BASE["dn"])]
    mixes += [(q, BASE["dn"]) for q in OPTIONS["gu"] if q != BASE["gu"]]
    mixes += [(BASE["gu"], q) for q in OPTIONS["dn"] if q != BASE["dn"]]
    for gu, dn in mixes:
        kinds_needed = [("gu", gu), ("dn", dn)]
        is_base = (gu, dn) == (BASE["gu"], BASE["dn"])
        if all(shard_path(k, q, gi).exists() for k, q in kinds_needed for gi in range(len(GROUPS))) and \
                (not is_base or (SHARDS / "rest.gguf").exists()):
            print(f"have shards for gu={gu} dn={dn}")
            continue
        db = DB / f"gu-{gu}_dn-{dn}.gguf"
        if not db.exists():
            tmp = db.with_suffix(".part")
            run([BIN / "llama-quantize", "--imatrix", IMATRIX,
                 "--tensor-type", f"{KINDS['gu']}={gu}", "--tensor-type", f"{KINDS['dn']}={dn}",
                 BF16, tmp, REST_FTYPE, THREADS], log=DB / f"{db.stem}.log")
            tmp.rename(db)
        split_db(db, gu, dn, is_base)
        db.unlink()


def make_variant(name, choice):
    """choice maps (kind, group) -> qtype; anything missing uses BASE. Returns the first shard's path."""
    d = VARIANTS / name
    d.mkdir(parents=True, exist_ok=True)
    first = d / f"m-00001-of-{N_SPLIT:05d}.gguf"
    for p in d.iterdir():
        p.unlink()
    first.symlink_to(SHARDS / "rest.gguf")
    for kind in KINDS:
        for gi in range(len(GROUPS)):
            q = choice.get((kind, gi), BASE[kind])
            (d / f"m-{shard_index(kind, gi) + 1:05d}-of-{N_SPLIT:05d}.gguf").symlink_to(shard_path(kind, q, gi))
    return first


def variant_bytes(first):
    return sum(p.resolve().stat().st_size for p in first.parent.iterdir())


def kld(model, log):
    text = run([BIN / "llama-perplexity", "-m", model, "-f", DATA / "test.txt", "-c", CTX, "--chunks", KLD_CHUNKS,
                "-ngl", 99, "-t", 8, "--kl-divergence-base", KLD_BASE, "--kl-divergence"], log=log)
    mean = re.search(r"Mean\s+KLD:\s+([\d.]+)", text)
    top = re.search(r"Same top p:\s+([\d.]+)", text)
    if not mean:
        raise RuntimeError(f"no KLD in {log}")
    return {"kld": float(mean.group(1)), "same_top_p": float(top.group(1)) if top else None}


def sweep_path(args):
    return WORK / f"sweep{args.tag}.json"


def base_choice(args):
    """The mix every swap is measured against: BASE everywhere, or a plan's assignment (re-sweep rounds)."""
    choice = {(kind, gi): BASE[kind] for kind in KINDS for gi in range(len(GROUPS))}
    if args.base_plan:
        choice.update({(x["kind"], x["group"]): x["type"] for x in json.loads(Path(args.base_plan).read_text())["assignment"]})
    return choice


def cmd_sweep(args):
    need(KLD_BASE, SHARDS / "rest.gguf")
    path = sweep_path(args)
    base = base_choice(args)
    done = json.loads(path.read_text()) if path.exists() else {"group": GROUP, "base_plan": args.base_plan, "runs": {}}
    jobs = [("base", {})]
    for gi in range(len(GROUPS)):
        for kind, qs in OPTIONS.items():
            jobs += [(f"g{gi:02d}-{kind}-{q}", {(kind, gi): q}) for q in qs if q != base[(kind, gi)]]
    jobs = [j for j in jobs if j[0] not in done["runs"]]
    print(f"{len(jobs)} variants to measure", flush=True)
    logs = WORK / f"sweep{args.tag}-logs"
    logs.mkdir(parents=True, exist_ok=True)
    for key, choice in jobs:
        first = make_variant(f"sweep{args.tag}", {**base, **choice})
        r = kld(first, logs / f"{key}.log")
        r["bytes"] = variant_bytes(first)
        print(f"{key:24} kld {r['kld']:.6f}  top {r['same_top_p']}%  {r['bytes'] / 2**30:.3f} GiB", flush=True)
        done["runs"][key] = r
        path.write_text(json.dumps(done, indent=1))


def cmd_allocate(args):
    path = sweep_path(args)
    need(path)
    sweep = json.loads(path.read_text())
    runs = sweep["runs"]
    base = runs["base"]
    args.base_plan = sweep.get("base_plan")
    base_q = base_choice(args)
    sizes = {(k, q, gi): shard_path(k, q, gi).stat().st_size
             for k, qs in OPTIONS.items() for q in qs for gi in range(len(GROUPS))}
    fixed = (SHARDS / "rest.gguf").stat().st_size
    budget = int(args.budget_gib * 2**30)

    # One knapsack item per (group, kind); each option costs its shard bytes and adds its measured KLD delta.
    items = []
    for gi in range(len(GROUPS)):
        for kind, qs in OPTIONS.items():
            opts = [(q, sizes[(kind, q, gi)],
                     0.0 if q == base_q[(kind, gi)] else runs[f"g{gi:02d}-{kind}-{q}"]["kld"] - base["kld"])
                    for q in qs]
            items.append((gi, kind, opts))

    unit = 2**20
    cap = (budget - fixed) // unit
    if cap < 0:
        raise SystemExit(f"budget below the fixed tensors ({fixed / 2**30:.2f} GiB)")
    inf = float("inf")
    best = [0.0] + [inf] * cap
    picks = []
    for _, _, opts in items:
        nxt = [inf] * (cap + 1)
        pick = [None] * (cap + 1)
        for c in range(cap + 1):
            if best[c] == inf:
                continue
            for oi, (_, b, d) in enumerate(opts):
                nc = c + -(-b // unit)
                if nc <= cap and best[c] + d < nxt[nc]:
                    nxt[nc], pick[nc] = best[c] + d, (oi, c)
        best = nxt
        picks.append(pick)
    end = min(range(cap + 1), key=lambda c: best[c])
    if best[end] == inf:
        raise SystemExit("no assignment fits the budget")
    chosen, c = [], end
    for (gi, kind, opts), pick in zip(reversed(items), reversed(picks)):
        oi, c = pick[c]
        chosen.append({"group": gi, "kind": kind, "type": opts[oi][0]})
    chosen.reverse()
    total = fixed + sum(sizes[(x["kind"], x["type"], x["group"])] for x in chosen)
    plan = {"budget_gib": args.budget_gib, "bytes": total, "predicted_kld": base["kld"] + best[end], "assignment": chosen}
    path = WORK / f"plan-{args.budget_gib:g}g{args.tag}.json"
    path.write_text(json.dumps(plan, indent=1))
    for x in chosen:
        layers = GROUPS[x["group"]]
        print(f"  layers {layers[0]:>2}-{layers[-1]:<2} {x['kind']} {x['type']}")
    print(f"{total / 2**30:.3f} GiB, predicted KLD {plan['predicted_kld']:.6f} -> {path}")


def cmd_build(args):
    path = WORK / f"plan-{args.budget_gib:g}g{args.tag}.json"
    need(path)
    plan = json.loads(path.read_text())
    name = f"rco-{args.budget_gib:g}g{args.tag}"
    first = make_variant(name, {(x["kind"], x["group"]): x["type"] for x in plan["assignment"]})
    OUT.mkdir(parents=True, exist_ok=True)
    r = kld(first, OUT / f"{name}.kld.log")
    print(f"{name}: {variant_bytes(first) / 2**30:.3f} GiB, KLD {r['kld']:.6f} "
          f"(predicted {plan['predicted_kld']:.6f}), same top {r['same_top_p']}%")
    out = OUT / f"Qwen3-Coder-Next-{name}.gguf"
    if not out.exists():
        run([BIN / "llama-gguf-split", "--merge", first, out], log=OUT / f"{name}.merge.log")
    print(f"merged: {out}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("imatrix")
    s.add_argument("--chunks", type=int, default=150)
    s.set_defaults(fn=cmd_imatrix)
    sub.add_parser("kld-base").set_defaults(fn=cmd_kld_base)
    sub.add_parser("quantize").set_defaults(fn=cmd_quantize)
    s = sub.add_parser("sweep")
    # Re-sweep round: measure one-group swaps around a plan's mix instead of BASE (group interactions shift the
    # deltas, so the first additive allocation is only a starting point).
    s.add_argument("--base-plan", help="plan-*.json whose assignment is the mix to swap around")
    s.add_argument("--tag", default="", help="suffix for this round's sweep, plan and build files, e.g. --tag=-r2")
    s.set_defaults(fn=cmd_sweep)
    for name, fn in [("allocate", cmd_allocate), ("build", cmd_build)]:
        s = sub.add_parser(name)
        s.add_argument("--budget-gib", type=float, required=True)
        s.add_argument("--tag", default="")
        s.set_defaults(fn=fn)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
