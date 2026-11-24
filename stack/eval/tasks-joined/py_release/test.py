from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal, Optional

from solution import LoadError, Manifest, flatten, load, max_satisfying, parse, resolve, satisfies, unflatten


# --- py_semver_range
def test_parse_and_order():
    order = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11",
             "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0", "2.0.0"]
    vs = [parse(v) for v in order]
    for a, b in zip(vs, vs[1:]):
        assert a < b and b > a and not a == b
    assert sorted(reversed(vs)) == vs
    assert parse("v1.2.3+build.5") == parse("=1.2.3")
    assert parse("1.0.0-1") < parse("1.0.0-a")
    assert parse("1.0.0-a.b") > parse("1.0.0-a")


def test_parse_invalid():
    for bad in ["1.2", "01.2.3", "1.02.3", "1.2.3-01", "1.2.3-", "1.2.3+", "1.2.3-a..b", "a.b.c", "1.2.3.4", ""]:
        try:
            parse(bad)
        except ValueError:
            continue
        raise AssertionError(f"accepted {bad!r}")
    parse("1.2.3-0a")


CASES = [
    ("1.2.3", "1.2.3", True), ("1.2.4", "1.2.3", False), ("1.2.3", "=v1.2.3", True),
    ("1.9.9", "1.x", True), ("2.0.0", "1", False), ("1.2.9", "1.2.*", True), ("1.3.0", "1.2.x", False),
    ("5.0.0", "*", True), ("5.0.0", "", True), ("5.0.0-a", "*", False),
    ("1.3.0", ">1.2", True), ("1.2.9", ">1.2", False), ("1.2.9", "<=1.2", True), ("1.3.0", "<=1.2", False),
    ("1.1.9", "<1.2", True), ("1.2.0", "<1.2", False), ("1.2.0", ">=1.2", True),
    ("1.2.9", "~1.2.3", True), ("1.3.0", "~1.2.3", False), ("1.2.2", "~1.2.3", False), ("1.9.0", "~1", True),
    ("1.9.9", "^1.2.3", True), ("2.0.0", "^1.2.3", False), ("0.2.9", "^0.2.3", True), ("0.3.0", "^0.2.3", False),
    ("0.0.3", "^0.0.3", True), ("0.0.4", "^0.0.3", False), ("1.9.0", "^1.2.x", True), ("0.0.9", "^0.0.x", True),
    ("0.1.0", "^0.0.x", False), ("0.9.0", "^0.x", True), ("1.0.0", "^0.x", False),
    ("2.3.4", "1.2.3 - 2.3.4", True), ("2.3.5", "1.2.3 - 2.3.4", False), ("2.3.9", "1.2.3 - 2.3", True),
    ("2.4.0", "1.2.3 - 2.3", False), ("1.2.0", "1.2 - 2", True), ("2.9.9", "1.2 - 2", True), ("3.0.0", "1.2 - 2", False),
    ("1.5.0", ">=1.2.3 <1.5.0 || >=2", False), ("2.1.0", ">=1.2.3 <1.5.0 || >=2", True),
    ("1.2.3-alpha.7", ">1.2.3-alpha.3", True), ("3.4.5-alpha.9", ">1.2.3-alpha.3", False),
    ("1.2.3-alpha.2", ">1.2.3-alpha.3", False), ("1.2.3-beta", "^1.2.3-alpha", True), ("1.2.4-beta", "^1.2.3-alpha", False),
    ("1.2.3-alpha.7", ">=1.0.0 <2.0.0", False), ("1.2.3-rc.1", "1.2.3-rc.1 || 9", True),
]


def test_satisfies_table():
    bad = [(v, r, exp) for v, r, exp in CASES if satisfies(v, r) != exp]
    assert not bad, bad


def test_max_satisfying():
    vs = ["1.2.3", "v1.2.4", "1.3.0-beta", "1.3.0", "2.0.0-rc.1", "0.9.0"]
    assert max_satisfying(vs, "~1.2") == "v1.2.4"
    assert max_satisfying(vs, "^1.0.0") == "1.3.0"
    assert max_satisfying(vs, ">=2.0.0-rc.0") == "2.0.0-rc.1"
    assert max_satisfying(vs, ">3") is None


def test_invalid_ranges():
    for bad in [">>1.2.3", "~>1", "1.2.3 -", "^", "1.2.3 - 2 - 3", "<a"]:
        try:
            satisfies("1.0.0", bad)
        except ValueError:
            continue
        raise AssertionError(f"accepted range {bad!r}")


# --- py_typed_load
@dataclass
class Port:
    number: int
    proto: Literal["tcp", "udp"] = "tcp"


@dataclass
class Server:
    host: str
    ports: list[Port] = field(default_factory=list)
    weight: float = 1.0
    tags: dict[str, str | int] = field(default_factory=dict)
    backup: Optional[Server] = None


@dataclass
class Config:
    name: str
    servers: list[Server]
    version: tuple[int, int, int] = (1, 0, 0)
    flags: tuple[bool, ...] = ()
    enabled: bool = True
    note: str | None = None


def err(cls, data, path):
    try:
        load(cls, data)
    except LoadError as e:
        assert isinstance(e, ValueError)
        assert e.path == path, (e.path, path)
        assert str(e).startswith(path + ": "), str(e)
        return
    raise AssertionError(f"no LoadError, expected at {path}")


GOOD = {
    "name": "web",
    "servers": [
        {"host": "a", "ports": [{"number": 80}, {"number": 53, "proto": "udp"}], "weight": 2},
        {"host": "b", "tags": {"zone": "eu", "rack": 4}, "backup": {"host": "c"}},
    ],
    "version": [2, 1, 0],
    "flags": [True, False],
}


def test_good():
    c = load(Config, GOOD)
    assert c == Config(
        name="web",
        servers=[
            Server("a", [Port(80), Port(53, "udp")], 2.0),
            Server("b", tags={"zone": "eu", "rack": 4}, backup=Server("c")),
        ],
        version=(2, 1, 0),
        flags=(True, False),
    )
    assert isinstance(c.servers[0].weight, float)
    assert isinstance(c.version, tuple) and isinstance(c.flags, tuple)
    assert isinstance(c.servers[1].backup, Server)


def test_defaults_not_shared():
    a = load(Config, {"name": "x", "servers": [{"host": "h"}]})
    b = load(Config, {"name": "y", "servers": [{"host": "h"}]})
    a.servers[0].ports.append(Port(1))
    assert b.servers[0].ports == []


def test_none_optional():
    c = load(Config, {"name": "x", "servers": [], "note": None})
    assert c.note is None


def test_missing_field():
    err(Config, {"name": "x", "servers": [{}, {"host": 1}]}, "$.servers[0].host")


def test_wrong_scalar():
    err(Config, {"name": "x", "servers": [{"host": "a"}, {"host": 1}]}, "$.servers[1].host")
    err(Config, {"name": "x", "servers": [{"host": "a", "ports": [{"number": 1}, {"number": "2"}]}]},
        "$.servers[0].ports[1].number")


def test_bool_not_int():
    err(Config, {"name": "x", "servers": [{"host": "a", "ports": [{"number": True}]}]}, "$.servers[0].ports[0].number")
    err(Config, {"name": "x", "servers": [{"host": "a", "weight": False}]}, "$.servers[0].weight")
    err(Config, {"name": "x", "servers": [], "enabled": 1}, "$.enabled")


def test_literal():
    err(Config, {"name": "x", "servers": [{"host": "a", "ports": [{"number": 1, "proto": "sctp"}]}]},
        "$.servers[0].ports[0].proto")


def test_union_and_dict_key_path():
    err(Config, {"name": "x", "servers": [{"host": "a", "tags": {"ok": 1, "bad": 1.5}}]}, "$.servers[0].tags.bad")


def test_union_order():
    @dataclass
    class U:
        v: int | str
        w: float | int

    u = load(U, {"v": "s", "w": 3})
    assert u.v == "s" and u.w == 3.0 and isinstance(u.w, float)


def test_unknown_key():
    err(Config, {"name": "x", "servers": [], "zzz": 1, "aaa": 2}, "$.zzz")


def test_tuple_fixed_length():
    err(Config, {"name": "x", "servers": [], "version": [1, 2]}, "$.version")
    err(Config, {"name": "x", "servers": [], "version": [1, 2, "3"]}, "$.version[2]")
    err(Config, {"name": "x", "servers": [], "flags": [True, 0]}, "$.flags[1]")


def test_container_types():
    err(Config, {"name": "x", "servers": {"host": "a"}}, "$.servers")
    err(Config, ["x"], "$")
    err(Config, {"name": "x", "servers": [{"host": "a", "backup": {"host": "b", "backup": {"host": 5}}}]},
        "$.servers[0].backup.backup.host")


# --- py_e_flatten
NESTED = {"a": {"b": 1, "c": [10, {"d": None}, []]}, "e": {}, "f": "x"}
FLAT = {"a.b": 1, "a.c.0": 10, "a.c.1.d": None, "a.c.2": [], "e": {}, "f": "x"}


def raises(exc, fn, *args):
    try:
        fn(*args)
    except exc:
        return
    raise AssertionError(f"{fn.__name__}{args} did not raise {exc.__name__}")


def test_flatten():
    assert flatten(NESTED) == FLAT
    assert list(flatten(NESTED)) == list(FLAT)


def test_sep():
    assert flatten({"a": {"b": [1]}}, sep="/") == {"a/b/0": 1}


def test_unflatten():
    assert unflatten(FLAT) == NESTED
    assert unflatten({"x.1": "b", "x.0": "a"}) == {"x": ["a", "b"]}
    assert unflatten({"x.01": 1}) == {"x": {"01": 1}}


def test_roundtrip():
    obj = {"k": [[1, 2], [{"z": [3]}]], "m": {"n": {"o": True}}}
    assert unflatten(flatten(obj)) == obj


def test_errors():
    raises(TypeError, flatten, [1, 2])
    raises(ValueError, flatten, {"a.b": 1})
    raises(ValueError, unflatten, {"x.0": 1, "x.2": 2})
    raises(ValueError, unflatten, {"a": 1, "a.b": 2})
    raises(ValueError, unflatten, {"a.b": 2, "a": 1})


# --- integration
AVAIL = {"left-pad": ["1.0.0", "1.1.2", "1.3.0", "2.0.0-beta.1", "2.0.0"], "chalk": ["4.1.0", "5.0.0", "5.3.0"],
         "jest": ["29.0.0", "29.7.0", "30.0.0-rc.1"]}


def test_resolve_basic():
    r = resolve({"name": "app", "version": "1.0.0", "dependencies": {"left-pad": "^1.1.0", "chalk": "<5"},
                 "dev": {"jest": "~29"}}, AVAIL)
    assert r == {"name": "app", "version": "1.0.0", "dependencies/left-pad": "1.3.0", "dependencies/chalk": "4.1.0",
                 "dev/jest": "29.7.0"}
    assert list(r) == ["name", "version", "dependencies/left-pad", "dependencies/chalk", "dev/jest"]


def test_resolve_empty_sections():
    r = resolve({"name": "lib", "version": "v0.1.0-rc.1+build.5"}, AVAIL)
    assert r == {"name": "lib", "version": "v0.1.0-rc.1+build.5", "dependencies": {}, "dev": {}}


def test_resolve_prerelease_rules():
    r = resolve({"name": "a", "version": "1.0.0", "dependencies": {"left-pad": ">=2.0.0-beta.0 <2.0.0"}}, AVAIL)
    assert r["dependencies/left-pad"] == "2.0.0-beta.1"
    r = resolve({"name": "a", "version": "1.0.0", "dependencies": {"jest": "*"}}, AVAIL)
    assert r["dependencies/jest"] == "29.7.0"


def test_resolve_load_errors():
    for data, path in [({"name": "a"}, "$.version"), ({"name": "a", "version": "1.0.0", "private": 1}, "$.private"),
                       ({"name": "a", "version": "1.0.0", "dev": {"jest": 29}}, "$.dev.jest"),
                       ({"name": "a", "version": "1.0.0", "license": "MIT"}, "$.license")]:
        try:
            resolve(data, AVAIL)
        except LoadError as e:
            assert e.path == path, (e.path, path)
            continue
        raise AssertionError(f"no LoadError for {data}")


def test_resolve_value_errors():
    cases = [({"name": "a", "version": "1.0"}, None), ({"name": "a", "version": "1.0.0", "dependencies": {"chalk": "^6"}}, "chalk"),
             ({"name": "a", "version": "1.0.0", "dev": {"nope": "*"}}, "nope"),
             ({"name": "a", "version": "1.0.0", "dependencies": {"chalk": "^^5"}}, None),
             ({"name": "a", "version": "1.0.0", "dependencies": {"@x/y": "*"}}, None)]
    for data, word in cases:
        try:
            resolve(data, {**AVAIL, "@x/y": ["1.0.0"]})
        except LoadError:
            raise AssertionError(f"LoadError for {data}")
        except ValueError as e:
            assert word is None or word in str(e), (word, str(e))
            continue
        raise AssertionError(f"no ValueError for {data}")


def test_manifest_dataclass():
    m = load(Manifest, {"name": "a", "version": "1.0.0"})
    assert (m.dependencies, m.dev, m.private) == ({}, {}, False)
    assert load(Manifest, {"name": "b", "version": "1.0.0"}).dev is not m.dev


from _runner import main
main(globals())
