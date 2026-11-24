from datetime import datetime as D

from solution import format_duration, merge, next_fire, parse_duration, plan_runs
import copy


# --- py_cron_next
def raises(expr, after=D(2026, 1, 1)):
    try:
        next_fire(expr, after)
    except ValueError:
        return
    raise AssertionError(f"no ValueError for {expr!r}")


def test_every_minute():
    assert next_fire("* * * * *", D(2026, 3, 1, 10, 5, 30)) == D(2026, 3, 1, 10, 6)
    assert next_fire("* * * * *", D(2026, 3, 1, 10, 5)) == D(2026, 3, 1, 10, 6)


def test_rollover_year():
    assert next_fire("0 0 1 1 *", D(2026, 12, 31, 23, 59)) == D(2027, 1, 1)


def test_steps_and_lists():
    assert next_fire("*/15 9-17 * * *", D(2026, 5, 4, 17, 46)) == D(2026, 5, 5, 9, 0)
    assert next_fire("5,35 */6 * * *", D(2026, 5, 4, 6, 35)) == D(2026, 5, 4, 12, 5)
    assert next_fire("10/20 * * * *", D(2026, 5, 4, 6, 51)) == D(2026, 5, 4, 7, 10)
    assert next_fire("0 1-10/3 * * *", D(2026, 5, 4, 7, 0)) == D(2026, 5, 4, 10, 0)


def test_names():
    assert next_fire("0 12 * feb MON", D(2026, 1, 1)) == D(2026, 2, 2, 12)
    assert next_fire("0 0 * * mon-WED", D(2026, 5, 7)) == D(2026, 5, 11)
    assert next_fire("0 0 1 JUN-aug *", D(2026, 8, 2)) == D(2027, 6, 1)


def test_sunday_7():
    assert next_fire("30 8 * * 7", D(2026, 5, 4)) == D(2026, 5, 10, 8, 30)
    assert next_fire("30 8 * * 0", D(2026, 5, 4)) == D(2026, 5, 10, 8, 30)
    assert next_fire("0 0 * * 5-7", D(2026, 5, 4)) == D(2026, 5, 8)


def test_dom_dow_or():
    # 2026-05-04 is a Monday; the 13th or any Friday
    assert next_fire("0 0 13 * 5", D(2026, 5, 4)) == D(2026, 5, 8)
    assert next_fire("0 0 13 * 5", D(2026, 5, 9)) == D(2026, 5, 13)


def test_dom_restricted_dow_star():
    assert next_fire("0 0 31 * *", D(2026, 4, 1)) == D(2026, 5, 31)


def test_dow_step_restricts():
    # */2 on day-of-week is a restriction, so OR semantics with dom apply
    assert next_fire("0 0 1 * */2", D(2026, 5, 4, 1)) == D(2026, 5, 5)


def test_leap_day():
    assert next_fire("0 0 29 2 *", D(2026, 3, 1)) == D(2028, 2, 29)


def test_impossible():
    raises("0 0 30 2 *")


def test_errors():
    for e in ["* * * *", "60 * * * *", "* 24 * * *", "* * 0 * *", "* * * 13 *", "* * * * 8",
              "5-1 * * * *", "*/0 * * * *", "* * * FOO *", "a * * * *", "1,,2 * * * *"]:
        raises(e)


# --- py_e_duration
def raises_duration(s):
    try:
        parse_duration(s)
    except ValueError:
        return
    raise AssertionError(f"accepted {s!r}")


def test_parse():
    assert parse_duration("1h30m") == 5400
    assert parse_duration("2d 4h") == 187200
    assert parse_duration("90s") == 90
    assert parse_duration("0s") == 0
    assert parse_duration("90m") == 5400
    assert parse_duration("1D2H3M4S") == 93784


def test_parse_errors():
    for s in ["", "1x", "30m1h", "1h1h", "h", "1.5h", "1h  2m", " 1h", "1h-2m", "10"]:
        raises_duration(s)


def test_format():
    assert format_duration(5400) == "1h30m"
    assert format_duration(0) == "0s"
    assert format_duration(86461) == "1d1m1s"
    assert format_duration(59) == "59s"
    assert format_duration(172800) == "2d"


def test_roundtrip():
    for n in [0, 1, 59, 60, 61, 3599, 3600, 86399, 86400, 1234567]:
        assert parse_duration(format_duration(n)) == n


def test_format_negative():
    try:
        format_duration(-1)
    except ValueError:
        return
    raise AssertionError("negative accepted")


# --- py_e_config_merge
BASE = {"db": {"host": "localhost", "port": 5432, "opts": {"ssl": False}}, "plugins": ["a"], "debug": True}


def test_deep_merge():
    r = merge(BASE, {"db": {"port": 6543, "opts": {"ssl": True}}})
    assert r == {"db": {"host": "localhost", "port": 6543, "opts": {"ssl": True}}, "plugins": ["a"], "debug": True}


def test_replace_list_and_scalar_with_dict():
    r = merge(BASE, {"plugins": ["b"], "debug": {"level": 2}})
    assert r["plugins"] == ["b"] and r["debug"] == {"level": 2}


def test_delete():
    r = merge(BASE, {"debug": None, "db": {"opts": None}})
    assert "debug" not in r and r["db"] == {"host": "localhost", "port": 5432}


def test_append():
    r = merge(BASE, {"plugins+": ["b"]}, {"plugins+": ["c"], "extra+": [1]})
    assert r["plugins"] == ["a", "b", "c"] and r["extra"] == [1]
    assert "plugins+" not in r and "extra+" not in r


def test_append_type_error():
    try:
        merge(BASE, {"debug+": [1]})
    except TypeError:
        return
    raise AssertionError("expected TypeError")


def test_no_mutation_no_sharing():
    snap = copy.deepcopy(BASE)
    over = {"db": {"opts": {"x": [1]}}}
    r = merge(BASE, over)
    assert BASE == snap
    r["db"]["opts"]["x"].append(2)
    r["plugins"].append("z")
    assert over == {"db": {"opts": {"x": [1]}}} and BASE == snap


def test_no_overrides():
    r = merge(BASE)
    assert r == BASE and r is not BASE and r["db"] is not BASE["db"]


# --- integration
JOBS = {"jobs": {"backup": {"cron": "0 2 * * *", "timeout": "90m"}, "ping": {"cron": "*/30 * * * *"}}}


def test_plan_basic():
    assert plan_runs(D(2026, 5, 4, 1, 10), "1h", JOBS) == [
        "2026-05-04 01:30 ping 1h", "2026-05-04 02:00 backup 1h30m", "2026-05-04 02:00 ping 1h"]


def test_plan_horizon_inclusive_after_exclusive():
    assert plan_runs(D(2026, 5, 4, 1, 30), "30m", JOBS) == ["2026-05-04 02:00 backup 1h30m", "2026-05-04 02:00 ping 1h"]
    assert plan_runs(D(2026, 5, 4, 1, 30), "29m", JOBS) == []


def test_plan_overrides():
    over = {"jobs": {"ping": {"enabled": False}, "report": {"cron": "15 2 * * MON", "timeout": "1d 30s"}}}
    assert plan_runs(D(2026, 5, 4, 1, 59), "20m", JOBS, over) == [
        "2026-05-04 02:00 backup 1h30m", "2026-05-04 02:15 report 1d30s"]
    over2 = {"jobs": {"backup": None}}
    assert plan_runs(D(2026, 5, 4, 1, 59), "2m", JOBS, over2) == ["2026-05-04 02:00 ping 1h"]
    assert JOBS["jobs"]["ping"] == {"cron": "*/30 * * * *"}


def test_plan_long_horizon():
    r = plan_runs(D(2026, 5, 4), "2d", {"jobs": {"a": {"cron": "0 0 * * *"}}})
    assert r == ["2026-05-05 00:00 a 1h", "2026-05-06 00:00 a 1h"]
    assert plan_runs(D(2026, 5, 4), "0s", JOBS) == []
    assert plan_runs(D(2026, 5, 4), "1d", {}) == []


def test_plan_errors():
    for cfg, horizon in [({"jobs": {"x": {"timeout": "1h"}}}, "1h"), ({"jobs": {"x": "0 * * * *"}}, "1h"),
                         ({"jobs": {"x": {"cron": "0 * * *"}}}, "1h"), (JOBS, "1 h"),
                         ({"jobs": {"x": {"cron": "0 * * * *", "timeout": "5x"}}}, "1h"),
                         ({"jobs": {"x": {"cron": "0 * * * *", "enabled": "no"}}}, "1h"),
                         ({"jobs": {"x": {"cron": "61 * * * *", "enabled": False}}}, "1h")]:
        try:
            plan_runs(D(2026, 5, 4), horizon, cfg)
        except ValueError:
            continue
        raise AssertionError(f"no ValueError for {cfg} {horizon}")


from _runner import main
main(globals())
