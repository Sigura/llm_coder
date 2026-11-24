import re


NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
WS = " \t\n"


def split_command(line, env):
    words = []
    cur = []          # list of (text, splittable)
    has_word = False  # current word has a quoted part or literal chars

    def flush():
        nonlocal cur, has_word
        fields = [""]
        started = False
        for text, splittable in cur:
            if not splittable:
                fields[-1] += text
                started = True
                continue
            for j, piece in enumerate(re.split(r"[ \t\n]+", text)):
                if j > 0:
                    if started or fields[-1]:
                        fields.append("")
                fields[-1] += piece
                if piece:
                    started = True
        if not started and fields == [""]:
            if has_word:
                words.append("")
        else:
            if fields[-1] == "" and len(fields) > 1:
                fields.pop()
            words.extend(f for f in fields if f != "" or has_word and len(fields) == 1)
        cur, has_word = [], False

    def expand(i, quoted):
        # line[i] == '$'; returns (value, new_i) or None if literal
        if i + 1 < len(line) and line[i + 1] == "{":
            j = i + 2
            m = NAME.match(line, j)
            if not m:
                raise ValueError("bad ${")
            name, j = m[0], m.end()
            if j < len(line) and line[j] == "}":
                return env.get(name, ""), j + 1
            if line.startswith(":-", j) or line.startswith("-", j):
                colon = line[j] == ":"
                j += 2 if colon else 1
                depth, k = 1, j
                while k < len(line):
                    if line[k] == "{":
                        depth += 1
                    elif line[k] == "}":
                        depth -= 1
                        if depth == 0:
                            break
                    k += 1
                if k >= len(line):
                    raise ValueError("unterminated ${")
                val = env.get(name)
                if val is None or (colon and val == ""):
                    val = expand_text(line[j:k])
                return val, k + 1
            raise ValueError("bad ${")
        m = NAME.match(line, i + 1)
        if m:
            return env.get(m[0], ""), m.end()
        return None

    def expand_text(text):
        out, k = [], 0
        while k < len(text):
            if text[k] == "$":
                r = split_command_expand(text, k)
                if r:
                    out.append(r[0])
                    k = r[1]
                    continue
            out.append(text[k])
            k += 1
        return "".join(out)

    def split_command_expand(text, k):
        return _expand_in(text, k, env)

    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c in WS:
            if cur or has_word:
                flush()
            i += 1
        elif c == "'":
            j = line.find("'", i + 1)
            if j < 0:
                raise ValueError("unterminated '")
            cur.append((line[i + 1:j], False))
            has_word = True
            i = j + 1
        elif c == '"':
            has_word = True
            i += 1
            buf = []
            while True:
                if i >= n:
                    raise ValueError('unterminated "')
                c = line[i]
                if c == '"':
                    i += 1
                    break
                if c == "\\" and i + 1 < n and line[i + 1] in '$"\\\n':
                    if line[i + 1] != "\n":
                        buf.append(line[i + 1])
                    i += 2
                elif c == "$":
                    r = expand(i, True)
                    if r:
                        buf.append(r[0])
                        i = r[1]
                    else:
                        buf.append("$")
                        i += 1
                else:
                    buf.append(c)
                    i += 1
            cur.append(("".join(buf), False))
        elif c == "\\":
            if i + 1 >= n:
                raise ValueError("trailing backslash")
            if line[i + 1] != "\n":
                cur.append((line[i + 1], False))
                has_word = True
            i += 2
        elif c == "$":
            r = expand(i, False)
            if r:
                cur.append((r[0], True))
                i = r[1]
            else:
                cur.append(("$", False))
                has_word = True
                i += 1
        else:
            cur.append((c, False))
            has_word = True
            i += 1
    if cur or has_word:
        flush()
    return words


def _expand_in(text, k, env):
    m = NAME.match(text, k + 1)
    if m:
        return env.get(m[0], ""), m.end()
    if text.startswith("{", k + 1):
        end = text.find("}", k)
        if end < 0:
            raise ValueError("unterminated ${")
        return env.get(text[k + 2:end], ""), end + 1
    return None


HDR = re.compile(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def apply_patch(original, diff):
    src = original.splitlines(True)
    dl = diff.splitlines(True)
    i = 0
    while i < len(dl) and not dl[i].startswith("@@"):
        i += 1
    out = []
    pos = 0
    while i < len(dl):
        m = HDR.match(dl[i])
        if not m:
            raise ValueError(f"bad header {dl[i]!r}")
        ostart, ocount = int(m[1]), int(m[2]) if m[2] is not None else 1
        ncount = int(m[4]) if m[4] is not None else 1
        i += 1
        body = []
        while i < len(dl) and not dl[i].startswith("@@"):
            line = dl[i]
            if line.startswith("\\"):
                if not body:
                    raise ValueError("stray no-newline marker")
                kind, text = body[-1]
                body[-1] = (kind, text.removesuffix("\n"))
            elif line[:1] in (" ", "-", "+"):
                body.append((line[0], line[1:]))
            elif line in ("\n", "\r\n"):
                body.append((" ", line))
            else:
                raise ValueError(f"bad body line {line!r}")
            i += 1
        olines = [t for k, t in body if k != "+"]
        nlines = [t for k, t in body if k != "-"]
        if len(olines) != ocount or len(nlines) != ncount:
            raise ValueError("hunk counts disagree with body")
        start = ostart if ocount == 0 else ostart - 1
        if start < pos or start + ocount > len(src):
            raise ValueError("hunk out of range")
        if src[start:start + ocount] != olines:
            raise ValueError("hunk does not match")
        out += src[pos:start]
        out += nlines
        pos = start + ocount
    out += src[pos:]
    return "".join(out)


REF = re.compile(r"\$\$|\$\{([^}:]+)(?::([^}]+))?\}")


def _strip_comment(v, lineno):
    if v.startswith('"'):
        out, i = [], 1
        while i < len(v):
            if v.startswith('\\"', i):
                out.append('"')
                i += 2
            elif v[i] == '"':
                rest = v[i + 1:].strip()
                if rest and not rest.startswith(("#", ";")):
                    raise ValueError(f"line {lineno}: junk after quote")
                return "".join(out), True
            else:
                out.append(v[i])
                i += 1
        raise ValueError(f"line {lineno}: unterminated quote")
    m = re.search(r"\s[;#]", v)
    if m:
        v = v[:m.start()]
    return v.strip(), False


def load_ini(text):
    data = {"": {}}
    sec = ""
    last = None
    for n, raw in enumerate(text.splitlines(), 1):
        if not raw.strip():
            last = None
            continue
        s = raw.strip()
        if s[0] in "#;":
            continue
        if raw[0] in " \t":
            if last is None:
                raise ValueError(f"line {n}: continuation without entry")
            data[sec][last] += "\n" + s
            continue
        if s.startswith("["):
            if not s.endswith("]"):
                raise ValueError(f"line {n}: unclosed section")
            sec = s[1:-1].strip()
            data.setdefault(sec, {})
            last = None
            continue
        m = re.search(r"[=:]", s)
        if not m:
            raise ValueError(f"line {n}: missing separator")
        key = s[:m.start()].strip().lower()
        val, _ = _strip_comment(s[m.end():].strip(), n)
        data[sec][key] = val
        last = key
    if not data[""]:
        del data[""]

    resolved = {}

    def get(section, key, stack):
        if (section, key) in resolved:
            return resolved[(section, key)]
        if (section, key) in stack:
            raise ValueError(f"reference cycle at {section}:{key}")
        if section not in data or key not in data[section]:
            raise ValueError(f"undefined reference {section}:{key}")
        stack = stack | {(section, key)}

        def sub(m):
            if m[0] == "$$":
                return "$"
            if m[2] is not None:
                return get(m[1], m[2].lower(), stack)
            return get(section, m[1].lower(), stack)

        v = REF.sub(sub, data[section][key])
        resolved[(section, key)] = v
        return v

    return {s: {k: get(s, k, frozenset()) for k in d} for s, d in data.items()}


def apply_recipe(recipe, files, patches, env):
    out = dict(files)
    for name, step in load_ini(recipe).items():
        if name == "":
            continue
        for key in ("file", "patch"):
            if key not in step:
                raise ValueError(f"[{name}]: missing {key}")
        enabled = step.get("enabled", "true").lower()
        if enabled not in ("true", "false"):
            raise ValueError(f"[{name}]: enabled must be true or false")
        if enabled == "false":
            continue
        words = split_command(step["file"], env)
        if len(words) != 1:
            raise ValueError(f"[{name}]: file must be one word, got {words}")
        if step["patch"] not in patches:
            raise ValueError(f"[{name}]: unknown patch {step['patch']}")
        out[words[0]] = apply_patch(out.get(words[0], ""), patches[step["patch"]])
    return out
