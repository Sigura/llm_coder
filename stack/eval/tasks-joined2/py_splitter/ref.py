import re

AMOUNT = re.compile(r"(-)?([0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.([0-9]{1,2}))?")


def parse_amount(s):
    m = AMOUNT.fullmatch(s.strip())
    if not m:
        raise ValueError(f"bad amount {s!r}")
    cents = int(m.group(2).replace(",", "")) * 100 + int((m.group(3) or "0").ljust(2, "0"))
    return -cents if m.group(1) else cents


def format_amount(cents):
    sign = "-" if cents < 0 else ""
    whole, frac = divmod(abs(cents), 100)
    return f"{sign}{whole:,}.{frac:02d}"


def _records(text):
    records, fields, field, i, n = [], [], [], 0, len(text)
    quoted = False
    while i <= n:
        c = text[i] if i < n else None
        if c == '"' and not field and not quoted:
            i += 1
            while True:
                if i >= n:
                    raise ValueError("unterminated quoted field")
                if text[i] == '"':
                    if i + 1 < n and text[i + 1] == '"':
                        field.append('"')
                        i += 2
                        continue
                    i += 1
                    break
                field.append(text[i])
                i += 1
            quoted = True
            if i < n and text[i] not in ",\r\n":
                raise ValueError("text after closing quote")
            if text.startswith("\r", i) and not text.startswith("\r\n", i):
                raise ValueError("text after closing quote")
            continue
        if c == ",":
            fields.append("".join(field))
            field, quoted = [], False
            i += 1
        elif c is None or c == "\n" or (c == "\r" and text.startswith("\r\n", i)):
            if fields or field or quoted:
                fields.append("".join(field))
                records.append(fields)
            fields, field, quoted = [], [], False
            i += 2 if c == "\r" else 1
        elif c == '"':
            raise ValueError("quote inside unquoted field")
        else:
            field.append(c)
            i += 1
    return records


def read_csv(text):
    records = _records(text)
    if not records:
        raise ValueError("no header")
    header = records[0]
    if any(not h for h in header) or len(set(header)) != len(header):
        raise ValueError("bad header")
    out = []
    for r in records[1:]:
        if len(r) != len(header):
            raise ValueError("wrong field count")
        out.append(dict(zip(header, r)))
    return out


def allocate(total, weights):
    if not weights or any(w < 0 for w in weights) or sum(weights) == 0:
        raise ValueError("bad weights")
    W, t = sum(weights), abs(total)
    parts = [t * w // W for w in weights]
    order = sorted(range(len(weights)), key=lambda i: (-(t * weights[i] % W), i))
    for i in order[:t - sum(parts)]:
        parts[i] += 1
    return [-p for p in parts] if total < 0 else parts


def _split(spec):
    names, weights = [], []
    for item in spec.split(";"):
        name, star, w = item.partition("*")
        name = name.strip()
        if star:
            if not re.fullmatch(r"[0-9]+", w) or int(w) == 0:
                raise ValueError(f"bad weight {item!r}")
            weight = int(w)
        else:
            weight = 1
        if not name or name in names:
            raise ValueError(f"bad name {item!r}")
        names.append(name)
        weights.append(weight)
    return names, weights


def settle(csv_text):
    rows = read_csv(csv_text)
    balance = {}
    for row in rows:
        if not {"payer", "amount", "split"} <= row.keys():
            raise ValueError("missing column")
        payer = row["payer"].strip()
        if not payer:
            raise ValueError("empty payer")
        amount = parse_amount(row["amount"])
        names, weights = _split(row["split"])
        balance[payer] = balance.get(payer, 0) + amount
        for name, share in zip(names, allocate(amount, weights)):
            balance[name] = balance.get(name, 0) - share
    if not rows:
        header = _records(csv_text)[0]
        if not {"payer", "amount", "split"} <= set(header):
            raise ValueError("missing column")
    lines = []
    while any(balance.values()):
        debtor = min(balance, key=lambda k: (balance[k], k))
        creditor = min(balance, key=lambda k: (-balance[k], k))
        moved = min(-balance[debtor], balance[creditor])
        balance[debtor] += moved
        balance[creditor] -= moved
        lines.append(f"{debtor} -> {creditor}: {format_amount(moved)}")
    return lines
