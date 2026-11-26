from solution import allocate, format_amount, parse_amount, read_csv, settle


def raises(fn, *args):
    try:
        fn(*args)
    except ValueError:
        return
    raise AssertionError(f"no ValueError for {fn.__name__}{args!r}")


# --- amounts
def test_parse_plain():
    assert parse_amount("12") == 1200
    assert parse_amount("12.5") == 1250
    assert parse_amount("12.05") == 1205
    assert parse_amount(" 0.99 ") == 99
    assert parse_amount("007") == 700


def test_parse_grouped_and_negative():
    assert parse_amount("1,234") == 123400
    assert parse_amount("1,234,567.89") == 123456789
    assert parse_amount("-1,000.1") == -100010
    assert parse_amount("-0") == 0
    assert parse_amount("-0.00") == 0


def test_parse_invalid():
    for s in ["", " ", "12.", ".5", "1.234", "12,34", "1234,567", ",123", "1,2345", "+5", "- 5", "1 000", "1e3",
              "12.5.0", "abc", "--1", "1,234."]:
        raises(parse_amount, s)


def test_format():
    assert format_amount(0) == "0.00"
    assert format_amount(5) == "0.05"
    assert format_amount(-5) == "-0.05"
    assert format_amount(123456) == "1,234.56"
    assert format_amount(-123456789) == "-1,234,567.89"
    assert format_amount(100000) == "1,000.00"
    assert format_amount(99999) == "999.99"


def test_roundtrip():
    for c in [0, 1, -1, 99, 100, 101, 999999, 1000000, -987654321]:
        assert parse_amount(format_amount(c)) == c


# --- csv
def test_csv_basic():
    assert read_csv("a,b\n1,2\n3,4\n") == [{"a": "1", "b": "2"}, {"a": "3", "b": "4"}]
    assert read_csv("a,b\r\n1,2\r\n3,4") == [{"a": "1", "b": "2"}, {"a": "3", "b": "4"}]
    assert read_csv("a\n") == []
    assert read_csv("a, b\n x ,\n") == [{"a": " x ", " b": ""}]


def test_csv_quotes():
    text = 'name,note\n"Smith, J","said ""hi""\nthen left"\n"",x\n'
    assert read_csv(text) == [{"name": "Smith, J", "note": 'said "hi"\nthen left'}, {"name": "", "note": "x"}]
    assert read_csv('a,b\n"x\r\ny",2\r\n') == [{"a": "x\r\ny", "b": "2"}]


def test_csv_empty_lines():
    assert read_csv("\n\na,b\n\n1,2\n\n\n3,4\n\n") == [{"a": "1", "b": "2"}, {"a": "3", "b": "4"}]
    assert read_csv('a\n""\n') == [{"a": ""}]


def test_csv_errors():
    for text in ["", "\n\n", "a,b\n1\n", "a,b\n1,2,3\n", "a,a\n1,2\n", "a,,b\n1,2,3\n", 'a\n"open\n',
                 'a\nx"y\n', 'a,b\n"x"y,2\n', 'a,b\n"x" ,2\n', ',\n1,2\n']:
        raises(read_csv, text)


# --- allocate
def test_allocate_even_and_remainders():
    assert allocate(100, [1, 1, 1]) == [34, 33, 33]
    assert allocate(101, [1, 1, 1]) == [34, 34, 33]
    assert allocate(10, [1, 2, 3]) == [2, 3, 5]
    assert allocate(7, [5, 5]) == [4, 3]
    assert allocate(0, [3, 1]) == [0, 0]


def test_allocate_largest_remainder_not_first():
    # 100 * [1, 3, 3] / 7 -> 14.28, 42.86, 42.86: the two larger remainders get the units
    assert allocate(100, [1, 3, 3]) == [14, 43, 43]
    assert allocate(5, [2, 1, 1, 1]) == [2, 1, 1, 1]
    assert allocate(3, [1, 1, 1, 1, 1]) == [1, 1, 1, 0, 0]


def test_allocate_negative_and_zero_weights():
    assert allocate(-100, [1, 1, 1]) == [-34, -33, -33]
    assert allocate(-10, [1, 2, 3]) == [-2, -3, -5]
    assert allocate(10, [0, 1, 0, 1]) == [0, 5, 0, 5]
    assert allocate(11, [0, 1, 0, 1]) == [0, 6, 0, 5]


def test_allocate_errors():
    for w in [[], [0], [0, 0], [1, -1], [-1, 2]]:
        raises(allocate, 10, w)


def test_allocate_sums():
    for total in [-1001, -7, 0, 1, 99, 1000003]:
        for w in [[1], [1, 2], [7, 0, 3], [1] * 9, [13, 17, 19, 23]]:
            parts = allocate(total, w)
            assert sum(parts) == total and len(parts) == len(w)


# --- integration
def test_settle_simple():
    text = "payer,amount,split\nann,30,ann;bob;cy\n"
    assert settle(text) == ["bob -> ann: 10.00", "cy -> ann: 10.00"]


def test_settle_greedy_order():
    text = ("date,payer,amount,split,memo\n"
            "d1,ann,90.00,ann;bob;cy,dinner\n"
            "d2,bob,1,200.5,bob*2;dan,\"hotel, 2 nights\"\n")
    try:
        settle(text)
    except ValueError:
        pass
    else:
        raise AssertionError("record with too many fields was accepted")
    text = ('date,payer,amount,split,memo\n'
            'd1,ann,90.00,ann;bob;cy,dinner\n'
            'd2,bob,"1,200.5",bob*2;dan,"hotel, 2 nights"\n')
    # ann +60, bob -30 + 1200.50 - 800.33 = 370.17, cy -30, dan -400.17
    assert settle(text) == ["dan -> bob: 370.17", "cy -> ann: 30.00", "dan -> ann: 30.00"]


def test_settle_ties_and_names():
    text = "payer,amount,split\n zed ,10, amy ; zed \nbea,10,amy;bea\n"
    # zed +5, amy -10, bea +5: ties between creditors go to the alphabetically first name
    assert settle(text) == ["amy -> bea: 5.00", "amy -> zed: 5.00"]


def test_settle_rounding_cents():
    text = "payer,amount,split\nann,0.10,ann;bob;cy\nbob,0.10,bob;cy;ann\n"
    # first: ann,bob,cy get 4,3,3; second: bob,cy,ann get 4,3,3 -> ann +10-4-3=3, bob +10-3-4=3, cy -6
    assert settle(text) == ["cy -> ann: 0.03", "cy -> bob: 0.03"]


def test_settle_weights_and_refund():
    text = "payer,amount,split\nann,100,ann*1;bob*3\nbob,-20,ann;bob\n"
    # ann +100-25+10 = 85, bob -75-20+10 = -85
    assert settle(text) == ["bob -> ann: 85.00"]


def test_settle_already_even():
    assert settle("payer,amount,split\nann,10,ann\nbob,5,ann;bob\nann,5,ann;bob\n") == []
    assert settle("payer,amount,split\n") == []


def test_settle_errors():
    for text in ["payer,amount\nann,1\n", "payer,amount,split\n,1,ann\n", "payer,amount,split\nann,1.234,ann\n",
                 "payer,amount,split\nann,1,ann;;bob\n", "payer,amount,split\nann,1,ann;ann\n",
                 "payer,amount,split\nann,1,ann*0\n", "payer,amount,split\nann,1,ann*-1\n",
                 "payer,amount,split\nann,1,ann*x\n", "payer,amount,split\nann,1,ann*+2\n",
                 "payer,amount\n", "payer,amount,split\nann,1,\n"]:
        raises(settle, text)


from _runner import main
main(globals())
