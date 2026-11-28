import re
import unicodedata

ZERO = {"​", "‌", "‍", "️"}


def _cw(c):
    if c < " " or c == "\x7f":
        raise ValueError(f"control character {c!r}")
    if unicodedata.combining(c) or c in ZERO:
        return 0
    return 2 if unicodedata.east_asian_width(c) in ("W", "F") else 1


def display_width(s):
    return sum(_cw(c) for c in s)


def _clusters(word):
    out = []
    for c in word:
        if _cw(c) == 0 and out:
            out[-1] += c
        else:
            out.append(c)
    return out


def wrap(text, width):
    if width < 1:
        raise ValueError("width < 1")
    lines, cur, curw = [], "", 0
    for word in text.split(" "):
        if not word:
            continue
        ww = display_width(word)
        if not cur and ww <= width:
            cur, curw = word, ww
            continue
        if cur and curw + 1 + ww <= width:
            cur, curw = cur + " " + word, curw + 1 + ww
            continue
        if ww <= width:
            lines.append(cur)
            cur, curw = word, ww
            continue
        clusters = _clusters(word)
        if cur and curw + 1 + display_width(clusters[0]) <= width:
            cur, curw = cur + " ", curw + 1
        elif cur:
            lines.append(cur)
            cur, curw = "", 0
        for cl in clusters:
            w = display_width(cl)
            if cur and curw + w > width:
                lines.append(cur)
                cur, curw = "", 0
            cur, curw = cur + cl, curw + w
    if cur:
        lines.append(cur)
    return lines


def _cells(line):
    s = line.strip()
    if len(s) < 2 or s[0] != "|":
        raise ValueError(f"not a table line: {line!r}")
    cells, buf, i, closed = [], [], 1, False
    while i < len(s):
        if s.startswith("\\|", i):
            buf.append("|")
            i += 2
            closed = False
        elif s[i] == "|":
            cells.append("".join(buf).strip())
            buf = []
            i += 1
            closed = True
        else:
            buf.append(s[i])
            i += 1
            closed = False
    if not closed:
        raise ValueError(f"line does not end with |: {line!r}")
    return cells


def parse_table(text):
    lines = [l for l in text.splitlines() if l.strip()]
    if len(lines) < 2:
        raise ValueError("need a header and a delimiter line")
    header, delim = _cells(lines[0]), _cells(lines[1])
    if len(delim) != len(header):
        raise ValueError("delimiter cell count")
    aligns = []
    for d in delim:
        if not re.fullmatch(r":?-+:?", d):
            raise ValueError(f"bad delimiter {d!r}")
        if d.endswith(":"):
            aligns.append("center" if d.startswith(":") and len(d) > 1 else "right")
        else:
            aligns.append("left")
    rows = []
    for line in lines[2:]:
        cells = _cells(line)
        if len(cells) > len(header):
            raise ValueError("too many cells")
        rows.append(cells + [""] * (len(header) - len(cells)))
    return header, aligns, rows


def _pad(s, w, align):
    gap = w - display_width(s)
    if align == "right":
        return " " * gap + s
    if align == "center":
        return " " * (gap // 2) + s + " " * (gap - gap // 2)
    return s + " " * gap


def render(text, max_width):
    header, aligns, rows = parse_table(text)
    table = [header] + rows
    n = len(header)
    widths = [max([display_width(r[i]) for r in table] + [1]) for i in range(n)]
    mins = [max([_cw(c) for r in table for c in r[i]] + [1]) for i in range(n)]
    while sum(widths) + 3 * n + 1 > max_width:
        can = [i for i in range(n) if widths[i] > mins[i]]
        if not can:
            raise ValueError("table does not fit")
        i = max(can, key=lambda i: (widths[i], i))
        widths[i] -= 1

    def draw(row):
        cols = [wrap(c, widths[i]) or [""] for i, c in enumerate(row)]
        height = max(len(c) for c in cols)
        out = []
        for k in range(height):
            parts = [_pad(c[k] if k < len(c) else "", widths[i], aligns[i]) for i, c in enumerate(cols)]
            out.append("| " + " | ".join(parts) + " |")
        return out

    rule = "|" + "+".join("-" * (w + 2) for w in widths) + "|"
    lines = draw(header) + [rule]
    for r in rows:
        lines += draw(r)
    return "\n".join(lines)
