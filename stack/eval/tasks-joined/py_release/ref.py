import dataclasses
import functools
import re
import types
import typing


NUM = r"0|[1-9]\d*"
IDENT = r"[0-9A-Za-z-]+"
FULL = re.compile(rf"^[v=]?({NUM})\.({NUM})\.({NUM})(?:-({IDENT}(?:\.{IDENT})*))?(?:\+({IDENT}(?:\.{IDENT})*))?$")
PART = re.compile(rf"^[v=]?(\*|[xX]|{NUM})(?:\.(\*|[xX]|{NUM})(?:\.(\*|[xX]|{NUM})(?:-({IDENT}(?:\.{IDENT})*))?(?:\+{IDENT}(?:\.{IDENT})*)?)?)?$")


@functools.total_ordering
class Version:
    def __init__(self, major, minor, patch, pre=()):
        self.major, self.minor, self.patch, self.pre = major, minor, patch, tuple(pre)

    def _key(self):
        pre = tuple((0, int(p), "") if p.isdigit() else (1, 0, p) for p in self.pre)
        return (self.major, self.minor, self.patch, 0 if self.pre else 1, pre)

    def __eq__(self, other):
        return self._key() == other._key()

    def __lt__(self, other):
        return self._key() < other._key()

    def __hash__(self):
        return hash(self._key())

    def __repr__(self):
        return f"{self.major}.{self.minor}.{self.patch}" + ("-" + ".".join(self.pre) if self.pre else "")


def parse(v):
    m = FULL.match(v.strip())
    if not m:
        raise ValueError(v)
    pre = m[4].split(".") if m[4] else []
    for p in pre:
        if p.isdigit() and len(p) > 1 and p[0] == "0":
            raise ValueError(v)
    return Version(int(m[1]), int(m[2]), int(m[3]), pre)


def _partial(s):
    m = PART.match(s)
    if not m:
        raise ValueError(s)
    parts = []
    for g in m.groups()[:3]:
        if g is None or g in "*xX":
            break
        parts.append(int(g))
    pre = m[4].split(".") if m[4] and len(parts) == 3 else []
    return parts, pre


def _lo(parts, pre=()):
    return Version(*(parts + [0] * (3 - len(parts))), pre)


def _next(parts):
    if len(parts) == 1:
        return Version(parts[0] + 1, 0, 0)
    return Version(parts[0], parts[1] + 1, 0)


def _comparator(tok):
    m = re.match(r"^(<=|>=|<|>|=)?(.*)$", tok)
    op, rest = m[1] or "", m[2]
    if rest[:1] in ("<", ">", "="):
        raise ValueError(tok)
    if rest.startswith(("~", "^")):
        if op:
            raise ValueError(tok)
        parts, pre = _partial(rest[1:])
        if not parts:
            return []
        lo = _lo(parts, pre)
        if rest[0] == "~":
            hi = _next(parts if len(parts) == 1 else parts[:2])
        elif parts[0] != 0 or len(parts) == 1:
            hi = Version(parts[0] + 1, 0, 0)
        elif parts[1] != 0 or len(parts) == 2:
            hi = Version(0, parts[1] + 1, 0)
        else:
            hi = Version(0, 0, parts[2] + 1)
        return [(">=", lo), ("<", hi)]
    parts, pre = _partial(rest)
    if len(parts) == 3:
        return [(op or "=", Version(*parts, pre))]
    if not parts:
        return [("<", Version(0, 0, 0))] if op in ("<", ">") else []
    return {
        "": [(">=", _lo(parts)), ("<", _next(parts))],
        "=": [(">=", _lo(parts)), ("<", _next(parts))],
        ">": [(">=", _next(parts))],
        ">=": [(">=", _lo(parts))],
        "<": [("<", _lo(parts))],
        "<=": [("<", _next(parts))],
    }[op]


def _parse_set(s):
    s = s.strip()
    m = re.match(r"^(\S+)\s+-\s+(\S+)$", s)
    if m:
        lp, lpre = _partial(m[1])
        hp, hpre = _partial(m[2])
        comps = [(">=", _lo(lp, lpre))] if lp else []
        if len(hp) == 3:
            comps.append(("<=", Version(*hp, hpre)))
        elif hp:
            comps.append(("<", _next(hp)))
        return comps
    toks = re.sub(r"(<=|>=|<|>|=)\s+", r"\1", s).split()
    if "-" in toks:
        raise ValueError(s)
    comps = []
    for t in toks:
        comps += _comparator(t)
    return comps


def _test(v, op, c):
    return {"=": v == c, "<": v < c, "<=": v <= c, ">": v > c, ">=": v >= c}[op]


def _sat_set(v, comps):
    if not all(_test(v, op, c) for op, c in comps):
        return False
    if v.pre:
        return any(c.pre and (c.major, c.minor, c.patch) == (v.major, v.minor, v.patch) for _, c in comps)
    return True


def _range(rng):
    return [_parse_set(s) for s in rng.split("||")]


def satisfies(version, rng):
    v = parse(version)
    return any(_sat_set(v, comps) for comps in _range(rng))


def max_satisfying(versions, rng):
    sets = _range(rng)
    best = None
    for s in versions:
        v = parse(s)
        if any(_sat_set(v, c) for c in sets) and (best is None or v > best[0]):
            best = (v, s)
    return best[1] if best else None


class LoadError(ValueError):
    def __init__(self, path, msg):
        super().__init__(f"{path}: {msg}")
        self.path = path


def _load(tp, data, path):
    origin = typing.get_origin(tp)
    args = typing.get_args(tp)
    if tp is type(None) or tp is None:
        if data is not None:
            raise LoadError(path, "expected null")
        return None
    if origin in (typing.Union, types.UnionType):
        rest = [a for a in args if a is not type(None)]
        if data is not None and len(rest) == 1:
            return _load(rest[0], data, path)
        for a in args:
            try:
                return _load(a, data, path)
            except LoadError:
                pass
        raise LoadError(path, f"no union member matched {data!r}")
    if origin is typing.Literal:
        if not any(data == a and type(data) is type(a) for a in args):
            raise LoadError(path, f"expected one of {args}")
        return data
    if tp is bool:
        if not isinstance(data, bool):
            raise LoadError(path, "expected bool")
        return data
    if tp is int:
        if isinstance(data, bool) or not isinstance(data, int):
            raise LoadError(path, "expected int")
        return data
    if tp is float:
        if isinstance(data, bool) or not isinstance(data, (int, float)):
            raise LoadError(path, "expected float")
        return float(data)
    if tp is str:
        if not isinstance(data, str):
            raise LoadError(path, "expected str")
        return data
    if origin is list:
        if not isinstance(data, list):
            raise LoadError(path, "expected list")
        return [_load(args[0], v, f"{path}[{i}]") for i, v in enumerate(data)]
    if origin is tuple:
        if not isinstance(data, list):
            raise LoadError(path, "expected list")
        if len(args) == 2 and args[1] is Ellipsis:
            return tuple(_load(args[0], v, f"{path}[{i}]") for i, v in enumerate(data))
        if len(data) != len(args):
            raise LoadError(path, f"expected {len(args)} items")
        return tuple(_load(a, v, f"{path}[{i}]") for i, (a, v) in enumerate(zip(args, data)))
    if origin is dict:
        if not isinstance(data, dict):
            raise LoadError(path, "expected object")
        return {k: _load(args[1], v, f"{path}.{k}") for k, v in data.items()}
    if dataclasses.is_dataclass(tp):
        if not isinstance(data, dict):
            raise LoadError(path, "expected object")
        hints = typing.get_type_hints(tp)
        fields = {f.name: f for f in dataclasses.fields(tp)}
        for k in data:
            if k not in fields:
                raise LoadError(f"{path}.{k}", "unknown field")
        kwargs = {}
        for name, f in fields.items():
            if name in data:
                kwargs[name] = _load(hints[name], data[name], f"{path}.{name}")
            elif f.default is dataclasses.MISSING and f.default_factory is dataclasses.MISSING:
                raise LoadError(f"{path}.{name}", "missing field")
        return tp(**kwargs)
    raise TypeError(f"unsupported annotation {tp!r}")


def load(cls, data):
    return _load(cls, data, "$")


def flatten(obj, sep="."):
    if not isinstance(obj, dict):
        raise TypeError("top level must be a dict")
    out = {}

    def walk(v, path):
        if isinstance(v, dict) and v:
            for k, x in v.items():
                if not isinstance(k, str) or sep in k:
                    raise ValueError(f"bad key {k!r}")
                walk(x, path + [k])
        elif isinstance(v, list) and v:
            for i, x in enumerate(v):
                walk(x, path + [str(i)])
        else:
            out[sep.join(path)] = v

    for k, v in obj.items():
        if not isinstance(k, str) or sep in k:
            raise ValueError(f"bad key {k!r}")
        walk(v, [k])
    return out




def unflatten(flat, sep="."):
    root = {}
    for key, value in flat.items():
        parts = key.split(sep)
        node = root
        for p in parts[:-1]:
            nxt = node.get(p)
            if nxt is None:
                nxt = node[p] = {}
            elif not isinstance(nxt, dict):
                raise ValueError(f"conflict at {key}")
            node = nxt
        last = parts[-1]
        if last in node:
            raise ValueError(f"conflict at {key}")
        node[last] = ("leaf", value)

    def build(node):
        if isinstance(node, tuple):
            return node[1]
        keys = list(node)
        if keys and all(re.fullmatch(r"0|[1-9]\d*", k) for k in keys):
            idx = sorted(int(k) for k in keys)
            if idx != list(range(len(idx))):
                raise ValueError("sparse list")
            return [build(node[str(i)]) for i in idx]
        return {k: build(v) for k, v in node.items()}

    return build(root)


@dataclasses.dataclass
class Manifest:
    name: str
    version: str
    dependencies: dict[str, str] = dataclasses.field(default_factory=dict)
    dev: dict[str, str] = dataclasses.field(default_factory=dict)
    private: bool = False


def resolve(manifest, available):
    m = load(Manifest, manifest)
    parse(m.version)
    chosen = {}
    for section in ("dependencies", "dev"):
        chosen[section] = {}
        for pkg, rng in getattr(m, section).items():
            v = max_satisfying(available.get(pkg, []), rng)
            if v is None:
                raise ValueError(f"no version of {pkg} satisfies {rng}")
            chosen[section][pkg] = v
    return flatten({"name": m.name, "version": m.version, **chosen}, sep="/")
