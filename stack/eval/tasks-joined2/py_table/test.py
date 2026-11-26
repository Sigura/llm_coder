from solution import display_width, parse_table, render, wrap


def raises(fn, *args):
    try:
        fn(*args)
    except ValueError:
        return
    raise AssertionError(f"no ValueError for {fn.__name__}{args!r}")


# --- width
def test_width_basic():
    assert display_width("") == 0
    assert display_width("abc") == 3
    assert display_width("日本") == 4
    assert display_width("ｈｉ") == 4  # fullwidth
    assert display_width("ﾊ") == 1  # halfwidth katakana


def test_width_zero():
    assert display_width("e\u0301") == 1
    assert display_width("a\u200bb") == 2
    assert display_width("\u2764\ufe0f") == 1
    assert display_width("\u200d\u200c") == 0


def test_width_control():
    for s in ["a\tb", "\n", "x\x7f", "\x00"]:
        raises(display_width, s)


# --- wrap
def test_wrap_greedy():
    assert wrap("the quick brown fox", 10) == ["the quick", "brown fox"]
    assert wrap("  a   b  ", 5) == ["a b"]
    assert wrap("one two", 7) == ["one two"]
    assert wrap("one two", 6) == ["one", "two"]
    assert wrap("", 3) == [] and wrap("   ", 3) == []


def test_wrap_long_word():
    assert wrap("abcdefghij", 4) == ["abcd", "efgh", "ij"]
    assert wrap("ab cdefghij", 5) == ["ab cd", "efghi", "j"]
    assert wrap("ab cdefghij xy", 5) == ["ab cd", "efghi", "j xy"]
    # no room for the space plus one character: the long word starts a new line
    assert wrap("abcd efghijk", 5) == ["abcd", "efghi", "jk"]
    assert wrap("abc efghijk", 5) == ["abc e", "fghij", "k"]


def test_wrap_wide():
    assert wrap("日本語テキスト", 5) == ["日本", "語テ", "キス", "ト"]
    assert wrap("a 日本語", 4) == ["a 日", "本語"]
    assert wrap("ab 日本語", 4) == ["ab", "日本", "語"]
    assert wrap("日本", 1) == ["日", "本"]
    assert wrap("a日b", 1) == ["a", "日", "b"]


def test_wrap_zero_width_attached():
    assert wrap("cafe\u0301s", 4) == ["cafe\u0301", "s"]
    assert wrap("ab\u200bcd", 2) == ["ab\u200b", "cd"]


def test_wrap_errors():
    raises(wrap, "abc", 0)
    raises(wrap, "a\tb", 5)


# --- parse
def test_parse_basic():
    text = "| Name | Qty |\n|:-----|----:|\n| apple | 3 |\n|pear|10|\n"
    assert parse_table(text) == (["Name", "Qty"], ["left", "right"], [["apple", "3"], ["pear", "10"]])


def test_parse_aligns_and_padding():
    text = "\n  | a | b | c | d |  \n|---|:-:|-:|:--|\n\n| 1 |\n| | x | | |\n"
    assert parse_table(text) == (["a", "b", "c", "d"], ["left", "center", "right", "left"],
                                 [["1", "", "", ""], ["", "x", "", ""]])


def test_parse_escapes():
    text = r"| expr | note |" + "\n|-|-|\n" + r"| a \| b | back\slash |" + "\n" + r"| \\| x |"
    assert parse_table(text) == (["expr", "note"], ["left", "left"], [["a | b", "back\\slash"], ["\\| x", ""]])


def test_parse_header_only():
    assert parse_table("|x|\n|-|") == (["x"], ["left"], [])


def test_parse_errors():
    for text in ["", "| a |", "| a |\n| - | - |", "| a | b |\n| - |", "a | b\n|-|-|", "| a | b\n|-|-|",
                 "| a |\n| x |", "| a |\n| : |", "| a |\n| -:- |", "| a |\n|-|\n| 1 | 2 |",
                 "| a |\n|-|\nrow", "| a \\|\n|-|"]:
        raises(parse_table, text)


# --- integration
def test_render_natural():
    text = "| Name | Qty |\n|:-----|----:|\n| apple | 3 |\n| fig | 10 |"
    assert render(text, 80) == ("| Name  | Qty |\n"
                                "|-------+-----|\n"
                                "| apple |   3 |\n"
                                "| fig   |  10 |")


def test_render_center_and_empty():
    text = "| a | b |\n|:-:|:-:|\n| x |  |\n| wide | yy |"
    assert render(text, 80) == ("|  a   | b  |\n"
                                "|------+----|\n"
                                "|  x   |    |\n"
                                "| wide | yy |")


def test_render_shrinks_widest_rightmost():
    text = "| k | description |\n|---|---|\n| id | the unique key of a row |"
    # natural widths 2 and 23 (32 cols): shrink only the description column down to 14 -> 2+14+7 = 23
    assert render(text, 23) == ("| k  | description    |\n"
                                "|----+----------------|\n"
                                "| id | the unique key |\n"
                                "|    | of a row       |")
    # ties: two columns of width 4 -> the rightmost shrinks first
    text = "| aaaa | bbbb |\n|-|-|"
    assert render(text, 14) == ("| aaaa | bbb |\n"
                                "|      | b   |\n"
                                "|------+-----|")


def test_render_multiline_header_alignment():
    text = "| unit price | n |\n|--:|:-:|\n| 5 | 12 |"
    # natural 10 and 2 -> 19 cols; at 15 the price column shrinks to 6
    assert render(text, 15) == ("|   unit | n  |\n"
                                "|  price |    |\n"
                                "|--------+----|\n"
                                "|      5 | 12 |")


def test_render_wide_chars():
    text = "| 名前 | x |\n|-|-|\n| 日本語 | 1 |"
    assert render(text, 80) == ("| 名前   | x |\n"
                                "|--------+---|\n"
                                "| 日本語 | 1 |")
    # minimum of the CJK column is 2, of x is 1: 2 + 1 + 7 = 10
    assert render(text, 10) == ("| 名 | x |\n"
                                "| 前 |   |\n"
                                "|----+---|\n"
                                "| 日 | 1 |\n"
                                "| 本 |   |\n"
                                "| 語 |   |")
    raises(render, text, 9)


def test_render_escaped_pipe_and_padding_row():
    text = "| a | b |\n|-|-|\n| x\\|y |"
    assert render(text, 80) == ("| a   | b |\n"
                                "|-----+---|\n"
                                "| x|y |   |")


def test_render_errors():
    raises(render, "| a |\n| x |", 80)
    raises(render, "| a | b |\n|-|-|", 8)
    raises(render, "| a\tb |\n|-|", 80)


from _runner import main
main(globals())
