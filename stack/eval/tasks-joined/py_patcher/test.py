import difflib

from solution import apply_patch, apply_recipe, load_ini, split_command
from solution import split_command as sp


# --- py_shell_split
ENV = {"HOME": "/home/u", "EMPTY": "", "MANY": "a  b\tc", "SP": " x ", "N": "1"}


def raises(line):
    try:
        sp(line, ENV)
    except ValueError:
        return
    raise AssertionError(f"no ValueError for {line!r}")


def test_basic():
    assert sp("ls  -la\t/tmp\n", ENV) == ["ls", "-la", "/tmp"]
    assert sp("", ENV) == []
    assert sp("   ", ENV) == []


def test_quotes():
    assert sp("echo 'a b' \"c d\"", ENV) == ["echo", "a b", "c d"]
    assert sp("a\"b c\"'d'", ENV) == ["ab cd"]
    assert sp("'' \"\" x", ENV) == ["", "", "x"]
    assert sp("'$HOME' \"$HOME\"", ENV) == ["$HOME", "/home/u"]


def test_backslashes():
    assert sp(r"a\ b c", ENV) == ["a b", "c"]
    assert sp(r'"a\"b" "\n" "\$x" "\\"', ENV) == ['a"b', r"\n", "$x", "\\"]
    assert sp(r"'a\b'", ENV) == [r"a\b"]
    assert sp("ab\\\ncd", ENV) == ["abcd"]
    assert sp('"ab\\\ncd"', ENV) == ["abcd"]
    assert sp(r"\$HOME", ENV) == ["$HOME"]


def test_expansion():
    assert sp("$HOME/x ${HOME}y $HOMEy", ENV) == ["/home/u/x", "/home/uy"]
    assert sp("${NOPE:-$HOME} ${EMPTY:-d} ${EMPTY-d} ${NOPE-d}", ENV) == ["/home/u", "d", "d"]
    assert sp("\"${EMPTY-d}\"", ENV) == [""]
    assert sp("${NOPE:-a b}", ENV) == ["a", "b"]
    assert sp("\"${NOPE:-a b}\"", ENV) == ["a b"]


def test_literal_dollar():
    assert sp("$ a$ $1x \"$\"", ENV) == ["$", "a$", "$1x", "$"]


def test_field_splitting():
    assert sp("x $MANY y", ENV) == ["x", "a", "b", "c", "y"]
    assert sp("x \"$MANY\" y", ENV) == ["x", "a  b\tc", "y"]
    assert sp("pre${SP}post", ENV) == ["pre", "x", "post"]
    assert sp("$EMPTY $NOPE z", ENV) == ["z"]
    assert sp("\"$EMPTY\" z", ENV) == ["", "z"]
    assert sp("a$EMPTY", ENV) == ["a"]
    assert sp("$SP", ENV) == ["x"]


def test_errors():
    for bad in ["'abc", "\"abc", "${HOME", "abc\\", "\"a\\\""]:
        raises(bad)


# --- py_apply_patch
def mkdiff(a, b, n=3):
    lines = list(difflib.unified_diff(a.splitlines(True), b.splitlines(True), "a/f", "b/f", n=n))
    out = []
    for l in lines:
        if l.endswith("\n"):
            out.append(l)
        else:
            out.append(l + "\n\\ No newline at end of file\n")
    return "".join(out)


A = "".join(f"line {i}\n" for i in range(1, 31))


def roundtrip(a, b, n=3):
    assert apply_patch(a, mkdiff(a, b, n)) == b


def test_single_change():
    roundtrip(A, A.replace("line 10\n", "LINE TEN\n"))


def test_multiple_hunks_shift():
    b = A.replace("line 3\n", "x\ny\nz\n").replace("line 20\n", "").replace("line 28\n", "28a\n28b\n")
    roundtrip(A, b)
    roundtrip(A, b, n=1)
    roundtrip(A, b, n=0)


def test_insert_at_start_and_end():
    roundtrip(A, "new first\n" + A + "new last\n")
    roundtrip(A, "new first\n" + A + "new last\n", n=0)


def test_delete_everything():
    roundtrip("a\nb\n", "")
    roundtrip("", "a\nb\n")


def test_no_newline_at_eof():
    roundtrip("a\nb\nc", "a\nb\nc\n")
    roundtrip("a\nb\nc\n", "a\nb\nc")
    roundtrip("a\nb\nc", "a\nB\nc")
    roundtrip("a\nb\nc", "a\nb\nd")


def test_headers_and_section_text():
    diff = (
        "diff --git a/f b/f\nindex 123..456 100644\n--- a/f\n+++ b/f\n"
        "@@ -2,3 +2,3 @@ def foo():\n line 2\n-line 3\n+LINE 3\n line 4\n"
    )
    assert apply_patch(A, diff) == A.replace("line 3\n", "LINE 3\n")


def test_count_omitted():
    diff = "@@ -1 +1 @@\n-a\n+b\n"
    assert apply_patch("a\nc\n", diff) == "b\nc\n"


def test_context_mismatch():
    diff = mkdiff(A, A.replace("line 10\n", "X\n"))
    try:
        apply_patch(A.replace("line 9\n", "line nine\n"), diff)
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError on context mismatch")


def test_wrong_position():
    diff = "@@ -5,1 +5,1 @@\n-line 4\n+X\n"
    try:
        apply_patch(A, diff)
    except ValueError:
        pass
    else:
        raise AssertionError("must not fuzz to another line")


def test_bad_counts():
    diff = "@@ -1,3 +1,3 @@\n line 1\n-line 2\n+X\n"
    try:
        apply_patch(A, diff)
    except ValueError:
        pass
    else:
        raise AssertionError("header counts disagree with body")


def test_crlf_preserved():
    a = "a\r\nb\r\nc\r\n"
    b = "a\r\nB\r\nc\r\n"
    roundtrip(a, b)


# --- py_ini_interp
TEXT = r"""
top = 1
[paths]
Root = /srv/app   ; inline comment
logs: ${root}/logs
cache = ${root}/cache#notacomment
price = $$5
# full comment
  ; indented comment
[db]
host = db.local
url = postgres://${host}/${paths:root}
desc = "  spaced ; not comment  "  # comment
quote = "say \"hi\""
multi = first
  second line
	third
after = x

[paths]
extra = ${logs}/extra
"""


def err(text, needle):
    try:
        load_ini(text)
    except ValueError as e:
        assert needle in str(e), (str(e), needle)
        return
    raise AssertionError(f"no ValueError ({needle})")


def test_full():
    d = load_ini(TEXT)
    assert d[""] == {"top": "1"}
    assert d["paths"] == {"root": "/srv/app", "logs": "/srv/app/logs", "cache": "/srv/app/cache#notacomment",
                          "price": "$5", "extra": "/srv/app/logs/extra"}
    assert d["db"]["url"] == "postgres://db.local//srv/app"
    assert d["db"]["desc"] == "  spaced ; not comment  "
    assert d["db"]["quote"] == 'say "hi"'
    assert d["db"]["multi"] == "first\nsecond line\nthird"
    assert d["db"]["after"] == "x"


def test_last_wins_and_case():
    d = load_ini("[S]\nA=1\na=2\n[s]\na=3\n")
    assert d == {"S": {"a": "2"}, "s": {"a": "3"}}


def test_separators():
    d = load_ini("[x]\nurl = http://h:80/a=b\nk: v=w\n")
    assert d["x"] == {"url": "http://h:80/a=b", "k": "v=w"}


def test_empty_value():
    assert load_ini("[x]\nk =\n")["x"] == {"k": ""}


def test_ini_errors():
    err("[x]\nnovalue\n", "line 2")
    err("[x\n", "line 1")
    err("  indented = 1\n", "line 1")
    err("[x]\nk = \"open\n", "line 2")
    err("[x]\na = ${b}\n", "")
    err("[x]\na = ${y:a}\n", "")
    err("[x]\na = ${b}\nb = ${c}\nc = ${a}\n", "cycle")
    err("[x]\na = ${a}\n", "cycle")


def test_blank_ends_continuation():
    err("[x]\na = 1\n\n  b\n", "line 4")


# --- integration
APP = "import os\n\n\ndef main():\n    print('hi')\n"
APP2 = "import os\n\n\ndef main():\n    print('hello')\n"
APP3 = "import os\nimport sys\n\n\ndef main():\n    print('hello')\n"
PATCHES = {"greet": mkdiff(APP, APP2), "sys": mkdiff(APP2, APP3), "readme": mkdiff("", "# App\n"),
           "bad": mkdiff("x\n", "y\n")}


def test_recipe_in_order():
    recipe = "[greet]\nfile = $${SRC:-src}/app.py\npatch = greet\n\n[imports]\nfile = src/app.py\npatch = sys\n"
    files = {"src/app.py": APP}
    assert apply_recipe(recipe, files, PATCHES, {}) == {"src/app.py": APP3}
    assert files == {"src/app.py": APP}


def test_recipe_env_quotes_and_new_file():
    # fully double-quoted INI values lose their quotes, so the shell quoting is single quotes here
    recipe = "[r]\nfile = $$ROOT/'READ ME.md'\npatch = readme\n"
    assert apply_recipe(recipe, {}, PATCHES, {"ROOT": "docs"}) == {"docs/READ ME.md": "# App\n"}


def test_recipe_interpolation_and_disabled():
    recipe = ("[one]\nname = app.py\nfile = lib/${name}\npatch = greet\n"
              "[two]\nfile = ${one:file}\npatch = sys\nenabled = FALSE\n"
              "[three]\nfile = a b\npatch = missing\nenabled = false\n")
    assert apply_recipe(recipe, {"lib/app.py": APP}, PATCHES, {}) == {"lib/app.py": APP2}
    assert apply_recipe(recipe.replace("FALSE", "True"), {"lib/app.py": APP}, PATCHES, {}) == {"lib/app.py": APP3}


def test_recipe_order_of_first_appearance():
    recipe = "[b]\nfile = f\npatch = sys\n[a]\nfile = f\npatch = greet\n[b]\nenabled = true\n"
    try:
        apply_recipe(recipe, {"f": APP}, PATCHES, {})
    except ValueError:
        pass
    else:
        raise AssertionError("step b runs first, its context does not match APP")
    recipe = "[a]\nfile = f\npatch = greet\n[b]\nfile = f\npatch = sys\n[a]\nenabled = true\n"
    assert apply_recipe(recipe, {"f": APP}, PATCHES, {}) == {"f": APP3}


def test_recipe_errors():
    for recipe in ["[s]\npatch = greet\n", "[s]\nfile = f\n", "[s]\nfile = a b\npatch = greet\n",
                   "[s]\nfile = $$NONE\npatch = greet\n", "[s]\nfile = f\npatch = nope\n",
                   "[s]\nfile = f\npatch = greet\nenabled = yes\n", "[s]\nfile = f\npatch = bad\n",
                   "[s\nfile = f\n"]:
        try:
            apply_recipe(recipe, {"f": APP}, PATCHES, {})
        except ValueError:
            continue
        raise AssertionError(f"no ValueError for {recipe!r}")


from _runner import main
main(globals())
