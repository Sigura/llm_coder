import heapq
import re
from functools import lru_cache


def parse_rules(text):
    text = re.sub(r"\\\r?\n", " ", text)
    rules = {}
    for raw in text.splitlines():
        line = raw.split("#", 1)[0]
        if not line.strip():
            continue
        if line.count(":") != 1:
            raise ValueError(f"bad rule line {raw!r}")
        left, right = line.split(":")
        targets, deps = left.split(), right.split()
        if not targets:
            raise ValueError(f"no target in {raw!r}")
        for t in targets:
            if t in deps:
                raise ValueError(f"{t} depends on itself")
            lst = rules.setdefault(t, [])
            for d in deps:
                if d not in lst:
                    lst.append(d)
    return rules


def _seg_regex(seg):
    out, i, n = [], 0, len(seg)
    while i < n:
        c = seg[i]
        if c == "*":
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        elif c == "[":
            j = i + 1
            neg = j < n and seg[j] == "!"
            if neg:
                j += 1
            k = j + 1 if j < n and seg[j] == "]" else j
            end = seg.find("]", k)
            if end < 0:
                out.append(re.escape("["))
                i += 1
                continue
            body, members, m = seg[j:end], [], 0
            while m < len(body):
                if m + 2 < len(body) and body[m + 1] == "-":
                    members.append(re.escape(body[m]) + "-" + re.escape(body[m + 2]))
                    m += 3
                else:
                    members.append(re.escape(body[m]))
                    m += 1
            out.append(("[^/" if neg else "[") + "".join(members) + "]")
            i = end + 1
            continue
        else:
            out.append(re.escape(c))
        i += 1
    return re.compile("".join(out))


def match(pattern, path):
    pat, segs = pattern.split("/"), path.split("/")

    @lru_cache(maxsize=None)
    def go(i, j):
        if i == len(pat):
            return j == len(segs)
        if pat[i] == "**":
            if i == len(pat) - 1:
                return j < len(segs)
            return any(go(i + 1, k) for k in range(j, len(segs) + 1))
        return j < len(segs) and bool(_seg_regex(pat[i]).fullmatch(segs[j])) and go(i + 1, j + 1)

    return go(0, 0)


class CycleError(ValueError):
    def __init__(self, cycle):
        super().__init__("cycle: " + " -> ".join(cycle))
        self.cycle = cycle


def _nodes(graph):
    nodes = set(graph)
    for deps in graph.values():
        nodes.update(deps)
    return nodes


def _reaches(graph, src, dst, blocked):
    seen, stack = set(), [src]
    while stack:
        u = stack.pop()
        if u == dst:
            return True
        if u in seen or u in blocked:
            continue
        seen.add(u)
        stack.extend(graph.get(u, []))
    return False


def _find_cycle(graph, left):
    on_cycle = sorted(n for n in left if any(_reaches(graph, d, n, set()) for d in graph.get(n, [])))
    start = on_cycle[0]
    path = [start]
    while True:
        u = path[-1]
        for d in sorted(set(graph.get(u, []))):
            if d == start:
                return path + [start]
            if d not in path and _reaches(graph, d, start, set(path[1:]) | {u}):
                path.append(d)
                break


def toposort(graph):
    nodes = _nodes(graph)
    deps = {n: set(graph.get(n, [])) for n in nodes}
    users = {n: [] for n in nodes}
    for n, ds in deps.items():
        for d in ds:
            users[d].append(n)
    ready = [n for n in nodes if not deps[n]]
    heapq.heapify(ready)
    out = []
    while ready:
        n = heapq.heappop(ready)
        out.append(n)
        for u in users[n]:
            deps[u].discard(n)
            if not deps[u]:
                heapq.heappush(ready, u)
    if len(out) != len(nodes):
        raise CycleError(_find_cycle(graph, nodes - set(out)))
    return out


def _is_pattern(name):
    return any(c in name for c in "*?[")


def plan(rules_text, files, goals):
    rules = parse_rules(rules_text)
    if not goals:
        if not rules:
            raise ValueError("no targets")
        goals = [next(iter(rules))]
    roots = []
    for g in goals:
        if _is_pattern(g):
            hits = sorted(t for t in rules if match(g, t))
            if not hits:
                raise ValueError(f"no target matches {g}")
            roots += hits
        elif g in rules or g in files:
            roots.append(g)
        else:
            raise ValueError(f"no rule to make {g}")
    graph, stack = {}, list(roots)
    while stack:
        n = stack.pop()
        if n in graph:
            continue
        deps = []
        for d in rules.get(n, []):
            for e in (sorted(f for f in files if match(d, f)) if _is_pattern(d) else [d]):
                if e not in deps:
                    deps.append(e)
        graph[n] = deps
        stack.extend(deps)
    order = toposort(graph)
    stale = set()
    for n in order:
        if n not in rules:
            if n not in files:
                raise ValueError(f"no rule to make {n}")
            continue
        if n not in files or any(d in stale or files[d] > files[n] for d in graph[n]):
            stale.add(n)
    return [n for n in order if n in stale]
