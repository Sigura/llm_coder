#!/usr/bin/env python3
"""Build a KTransformers expert placement (--init-expert-location) from a KT_ROUTING_DUMP histogram.

The dump counts routed physical expert ids under the placement the server ran with; this maps them back to logical
ids through that placement and orders each layer's experts by count, hottest first, which is the order serve.sh's
resident rows and hot-lend slots take them in. Run with the kt-wrapper venv's python (needs torch).
"""
import argparse
import json
from pathlib import Path

import torch


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("dump", type=Path, help="<KT_ROUTING_DUMP prefix>-rank0.pt")
    p.add_argument("current", type=Path, help="placement JSON the server ran with while dumping")
    p.add_argument("out", type=Path)
    args = p.parse_args()

    cur = json.loads(args.current.read_text())["physical_to_logical_map"]
    layers, experts = len(cur), len(cur[0])
    counts = torch.load(args.dump, map_location="cpu")["logical_count"].to(torch.int64)
    used = counts.sum(1).nonzero().flatten().tolist()
    if used != list(range(layers)):
        raise SystemExit(f"dump has counts in layers {used}, placement has {layers} layers")
    if counts[:, experts:].any():
        raise SystemExit(f"dump has counts past expert {experts - 1}")

    new = []
    for layer in range(layers):
        logical = torch.zeros(experts, dtype=torch.int64)
        logical[torch.tensor(cur[layer])] = counts[layer, :experts]
        order = sorted(range(experts), key=lambda e: (-int(logical[e]), e))
        new.append(order)
        top = logical[order]
        total = int(top.sum())
        print(f"layer {layer:2}: {total} routes, top 16 take {int(top[:16].sum()) / total:.1%}, "
              f"top 64 {int(top[:64].sum()) / total:.1%}; hot64 overlap of top 16: "
              f"{len(set(order[:16]) & set(cur[layer][:16]))}")
    args.out.write_text(json.dumps({"physical_to_logical_map": new}))
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
