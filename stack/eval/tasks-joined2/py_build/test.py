from solution import CycleError, match, parse_rules, plan, toposort


def raises(fn, *args, exc=ValueError):
    try:
        fn(*args)
    except exc as e:
        return e
    raise AssertionError(f"no {exc.__name__} for {fn.__name__}{args!r}")


# --- rules
def test_rules_basic():
    text = "app: main.o util.o\nmain.o: main.c util.h\n\nutil.o: util.c util.h\n"
    assert parse_rules(text) == {"app": ["main.o", "util.o"], "main.o": ["main.c", "util.h"],
                                 "util.o": ["util.c", "util.h"]}
    assert list(parse_rules(text)) == ["app", "main.o", "util.o"]


def test_rules_multi_target_merge_dedupe():
    text = "a b:\tx y x\n# comment line\nb: z y   # trailing comment\nclean:\n"
    assert parse_rules(text) == {"a": ["x", "y"], "b": ["x", "y", "z"], "clean": []}


def test_rules_continuation():
    text = "all: one \\\n  two\\\nthree # c \\\nfour: x\n"
    # the comment swallows the joined rest of its line
    assert parse_rules(text) == {"all": ["one", "two", "three"]}
    assert parse_rules("x: a\\\r\nb\r\ny: c\r\n") == {"x": ["a", "b"], "y": ["c"]}


def test_rules_errors():
    for text in ["just words\n", "a: b: c\n", ": b\n", "a: a\n", "a: b\na: c a\n", "x:y:\n"]:
        raises(parse_rules, text)
    assert parse_rules("  \n# only\n") == {}


# --- glob
def test_glob_simple():
    assert match("*.c", "main.c") and not match("*.c", "src/main.c")
    assert match("src/*.c", "src/main.c") and match("src/*", "src/") is True
    assert match("?.h", "a.h") and not match("?.h", "ab.h") and not match("a?b", "a/b")
    assert match("*", "") is True and not match("*", "a/b")
    assert match("a.c", "a.c") and not match("a.c", "abc")


def test_glob_classes():
    assert match("[abc].o", "b.o") and not match("[abc].o", "d.o")
    assert match("x[0-9][0-9]", "x42") and not match("x[0-9]", "xa")
    assert match("[!a-c]*", "dog") and not match("[!a-c]*", "cat")
    assert match("[]x]", "]") and match("[!]]", "a") and not match("[!]]", "]")
    assert match("a[b", "a[b") and not match("a[b", "ab")
    assert match("[.+(]", "+") and match("f(x)[)]", "f(x))")


def test_glob_double_star():
    assert match("a/**/b", "a/b") and match("a/**/b", "a/x/y/b") and not match("a/**/b", "a/x/c")
    assert match("**/c", "c") and match("**/c", "x/y/c") and not match("**/c", "xc")
    assert match("a/**", "a/x") and match("a/**", "a/x/y") and not match("a/**", "a")
    assert match("**", "a/b") and match("**", "x")
    assert match("src/**/*.c", "src/main.c") and match("src/**/*.c", "src/lib/x/y.c")
    assert match("a**b", "axxb") and not match("a**b", "ax/xb")
    assert match("**/**/z", "z") and match("a/**/**/b", "a/q/b")


# --- toposort
def test_topo_order():
    g = {"app": ["main.o", "util.o"], "main.o": ["main.c"], "util.o": ["util.c"]}
    assert toposort(g) == ["main.c", "main.o", "util.c", "util.o", "app"]
    assert toposort({"b": [], "a": [], "c": ["b"]}) == ["a", "b", "c"]
    assert toposort({}) == []


def test_topo_smallest_ready():
    g = {"z": [], "y": ["z"], "a": ["y"], "m": []}
    assert toposort(g) == ["m", "z", "y", "a"]


def test_topo_cycle_simple():
    e = raises(toposort, {"a": ["b"], "b": ["c"], "c": ["a"], "d": []}, exc=CycleError)
    assert isinstance(e, ValueError) and e.cycle == ["a", "b", "c", "a"]
    assert raises(toposort, {"x": ["x"]}, exc=CycleError).cycle == ["x", "x"]


def test_topo_cycle_choice():
    # 'a' is not on a cycle; 'b' is the smallest node on one. From b: c leads back, d too -> c (smaller).
    g = {"a": ["b"], "b": ["d", "c"], "c": ["e"], "d": ["b"], "e": ["b"]}
    assert raises(toposort, g, exc=CycleError).cycle == ["b", "c", "e", "b"]
    # a <-> b is a cycle and 'a' is smaller than 's'
    g = {"s": ["a"], "a": ["b"], "b": ["a", "s"]}
    assert raises(toposort, g, exc=CycleError).cycle == ["a", "b", "a"]
    g = {"s": ["t"], "t": ["u", "s"], "u": ["t"]}
    assert raises(toposort, g, exc=CycleError).cycle == ["s", "t", "s"]
    # 'p' -> 'q' -> 'r' -> 'q': q, not p, is the smallest node on a cycle
    g = {"p": ["q"], "q": ["r"], "r": ["q", "z"], "z": ["r"]}
    assert raises(toposort, g, exc=CycleError).cycle == ["q", "r", "q"]


def test_topo_cycle_path_blocked():
    # b -> c -> d -> b and b -> c -> e -> c: from c the smallest dep 'd' leads back to b; e only via c
    g = {"b": ["c"], "c": ["e", "d"], "d": ["b"], "e": ["c"]}
    assert raises(toposort, g, exc=CycleError).cycle == ["b", "c", "d", "b"]
    # a -> c -> a: 'a' is the smallest node on a cycle
    g = {"b": ["c"], "c": ["a", "d"], "a": ["c"], "d": ["b"]}
    assert raises(toposort, g, exc=CycleError).cycle == ["a", "c", "a"]
    # from c, dep 'b' reaches a only through c itself (already on the path): skip it
    g = {"a": ["c"], "c": ["b", "d"], "b": ["c"], "d": ["a"]}
    assert raises(toposort, g, exc=CycleError).cycle == ["a", "c", "d", "a"]
    g = {"m": ["n"], "n": ["k", "o"], "k": ["n", "m"], "o": ["m"]}
    assert raises(toposort, g, exc=CycleError).cycle == ["k", "m", "n", "k"]


# --- integration
RULES = """\
app: main.o util.o
main.o: main.c util.h
util.o: util.c util.h
docs: docs/**/*.md
test: app tests/*.py
"""


def test_plan_fresh_build():
    files = {"main.c": 1, "util.c": 1, "util.h": 1}
    assert plan(RULES, files, []) == ["main.o", "util.o", "app"]


def test_plan_up_to_date_and_partial():
    files = {"main.c": 1, "util.c": 1, "util.h": 1, "main.o": 5, "util.o": 5, "app": 6}
    assert plan(RULES, files, []) == []
    assert plan(RULES, dict(files, **{"main.c": 7}), ["app"]) == ["main.o", "app"]
    assert plan(RULES, dict(files, **{"util.h": 7}), ["app"]) == ["main.o", "util.o", "app"]
    # equal times are not newer
    assert plan(RULES, dict(files, **{"util.o": 6}), ["app"]) == []
    assert plan(RULES, dict(files, **{"util.o": 7}), ["app"]) == ["app"]
    assert plan(RULES, dict(files, **{"app": 4}), ["main.o"]) == []


def test_plan_globs():
    files = {"main.c": 1, "util.c": 1, "util.h": 1, "main.o": 5, "util.o": 5, "app": 6, "tests/t_a.py": 3,
             "tests/sub/t_b.py": 9, "docs": 4, "docs/x.md": 3, "docs/a/b/y.md": 5, "docs/readme.txt": 9}
    assert plan(RULES, files, ["docs"]) == ["docs"]
    assert plan(RULES, dict(files, **{"docs/a/b/y.md": 4}), ["docs"]) == []
    # tests/sub/t_b.py does not match tests/*.py; test is not a file -> out of date
    assert plan(RULES, files, ["test"]) == ["test"]
    assert plan(RULES, dict(files, test=8, **{"tests/t_a.py": 9}), ["test"]) == ["test"]
    assert plan(RULES, dict(files, test=8), ["test"]) == []
    assert plan("x: *.none\n", {"x": 1}, []) == []


def test_plan_pattern_goals_and_order():
    rules = "lib/a.o: a.c\nlib/b.o: b.c\nbin: lib/a.o lib/b.o\n"
    files = {"a.c": 2, "b.c": 2, "lib/a.o": 1}
    assert plan(rules, files, ["lib/*.o"]) == ["lib/a.o", "lib/b.o"]
    assert plan(rules, files, ["bin"]) == ["lib/a.o", "lib/b.o", "bin"]
    assert plan(rules, files, ["lib/b.o", "lib/a.o"]) == ["lib/a.o", "lib/b.o"]
    # an existing file without a rule is a valid goal with nothing to do
    assert plan(rules, files, ["a.c"]) == []


def test_plan_only_reachable():
    rules = "a: b\nb: c\nz: missing\n"
    assert plan(rules, {"c": 1}, ["a"]) == ["b", "a"]
    raises(plan, rules, {"c": 1}, ["z"])


def test_plan_errors():
    raises(plan, RULES, {"main.c": 1, "util.c": 1}, ["app"])  # util.h has no rule and is missing
    raises(plan, RULES, {}, ["nothing"])
    raises(plan, RULES, {}, ["no/*.match"])
    raises(plan, "", {}, [])
    e = raises(plan, "a: b\nb: c\nc: a\n", {}, [], exc=CycleError)
    assert e.cycle == ["a", "b", "c", "a"]
    e = raises(plan, "x: src/*\nsrc/gen: x\n", {"src/gen": 1}, ["x"], exc=CycleError)
    assert e.cycle == ["src/gen", "x", "src/gen"]


from _runner import main
main(globals())
