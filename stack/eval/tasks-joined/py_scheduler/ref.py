import copy
import datetime
import re


MONTHS = {n: i for i, n in enumerate("JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC".split(), 1)}
DAYS = {n: i for i, n in enumerate("SUN MON TUE WED THU FRI SAT".split())}


def _num(tok, names, lo, hi):
    t = tok.upper()
    if t in names:
        return names[t]
    if not t.isdigit():
        raise ValueError(tok)
    v = int(t)
    if not lo <= v <= hi:
        raise ValueError(tok)
    return v


def _field(text, lo, hi, names=None):
    names = names or {}
    out = set()
    for item in text.split(","):
        step = 1
        if "/" in item:
            item, s = item.split("/", 1)
            if not s.isdigit() or int(s) == 0:
                raise ValueError(text)
            step = int(s)
            has_step = True
        else:
            has_step = False
        if item == "*":
            a, b = lo, hi
        elif "-" in item:
            x, y = item.split("-", 1)
            a, b = _num(x, names, lo, hi), _num(y, names, lo, hi)
            if a > b:
                raise ValueError(text)
        else:
            a = _num(item, names, lo, hi)
            b = hi if has_step else a
        out.update(range(a, b + 1, step))
    return out


def next_fire(expr, after):
    parts = expr.split()
    if len(parts) != 5:
        raise ValueError(expr)
    mins = _field(parts[0], 0, 59)
    hours = _field(parts[1], 0, 23)
    doms = _field(parts[2], 1, 31)
    months = _field(parts[3], 1, 12, MONTHS)
    dows = {d % 7 for d in _field(parts[4], 0, 7, DAYS)}
    dom_star, dow_star = parts[2] == "*", parts[4] == "*"

    def day_ok(d):
        a = d.day in doms
        b = (d.isoweekday() % 7) in dows
        if not dom_star and not dow_star:
            return a or b
        return a and b

    t = after.replace(second=0, microsecond=0) + datetime.timedelta(minutes=1)
    day = t.date()
    end = day + datetime.timedelta(days=366 * 5)
    while day <= end:
        if day.month in months and day_ok(day):
            for h in sorted(hours):
                for m in sorted(mins):
                    cand = datetime.datetime(day.year, day.month, day.day, h, m)
                    if cand >= t:
                        return cand
        day += datetime.timedelta(days=1)
    raise ValueError("no match within 5 years")


UNITS = {"d": 86400, "h": 3600, "m": 60, "s": 1}
PART = re.compile(r"(\d+)([dhms])", re.I)


def parse_duration(s):
    if not s or s != s.strip():
        raise ValueError(s)
    pos, total, last = 0, 0, -1
    order = "dhms"
    while pos < len(s):
        m = PART.match(s, pos)
        if not m:
            raise ValueError(s)
        u = m[2].lower()
        if order.index(u) <= last:
            raise ValueError(s)
        last = order.index(u)
        total += int(m[1]) * UNITS[u]
        pos = m.end()
        if pos < len(s) and s[pos] == " ":
            pos += 1
            if pos == len(s):
                raise ValueError(s)
    return total


def format_duration(seconds):
    if seconds < 0:
        raise ValueError(seconds)
    if seconds == 0:
        return "0s"
    out = []
    for u, n in UNITS.items():
        q, seconds = divmod(seconds, n)
        if q:
            out.append(f"{q}{u}")
    return "".join(out)


def _merge(a, b):
    out = copy.deepcopy(a)
    for k, v in b.items():
        if k.endswith("+"):
            name = k[:-1]
            cur = out.get(name, [])
            if not isinstance(cur, list):
                raise TypeError(f"{name} is not a list")
            out[name] = cur + copy.deepcopy(list(v))
        elif v is None:
            out.pop(k, None)
        elif isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def merge(base, *overrides):
    out = copy.deepcopy(base)
    for o in overrides:
        out = _merge(out, o)
    return out


def plan_runs(after, horizon, base, *overrides):
    cfg = merge(base, *overrides)
    end = after + datetime.timedelta(seconds=parse_duration(horizon))
    out = []
    for name, job in cfg.get("jobs", {}).items():
        if not isinstance(job, dict) or "cron" not in job:
            raise ValueError(f"job {name}: no cron")
        enabled = job.get("enabled", True)
        if not isinstance(enabled, bool):
            raise ValueError(f"job {name}: enabled must be a bool")
        timeout = format_duration(parse_duration(job.get("timeout", "1h")))
        t = next_fire(job["cron"], after)
        while enabled and t <= end:
            out.append((t, name, timeout))
            t = next_fire(job["cron"], t)
    return [f"{t:%Y-%m-%d %H:%M} {n} {to}" for t, n, to in sorted(out)]
