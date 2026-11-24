source ./assert.sh

# --- access
gzip -c fixture_b.log > b.log.gz
check two_files "requests: 7
malformed: 2
status:
  200 4
  201 1
  304 1
  404 1
top_ips:
  203.0.113.9 5120
  10.0.0.1 1000
  198.51.100.2 300
top_paths:
  /api/v1/items 3
  /health 2
  /api/v1/items/7 1" "$(bash solution.sh access fixture_a.log b.log.gz)"
check stdin_and_ties "requests: 3
malformed: 0
status:
  200 2
  404 1
top_ips:
  10.0.0.3 122
  10.0.0.2 2
top_paths:
  /health 2
  /api/v1/items/7 1" "$(bash solution.sh access - < fixture_b.log)"
check only_malformed "requests: 0
malformed: 1
status:
top_ips:
top_paths:" "$(echo 'nope' | bash solution.sh access -)"
check missing_rc 1 "$(bash solution.sh access nope.log >/dev/null 2>&1; echo $?)"
check missing_out "" "$(bash solution.sh access fixture_a.log nope.log 2>/dev/null)"

# --- words
run() { bash solution.sh words "$@"; }

check basic "3 the
2 cat
1 a
1 sat" "$(printf 'the cat sat\nthe cat, a the\n' | run -n 4)"
check default_n "$(seq 1 12 | awk '{print 13-$1}' | sort -n | sed 's/^/1 /' | LC_ALL=C sort -k2,2 | head -10)" "$(seq 1 12 | run)"
check case "2 Foo
1 foo" "$(printf 'Foo foo Foo' | run)"
check case_i "3 foo" "$(printf 'Foo foo FOO' | run -i)"
check apostrophes "2 don't
1 rock
1 rock'n'roll" "$(printf "'don't' don't ''' rock'n'roll 'rock'" | run)"
check tie_order "1 B
1 a
1 b" "$(printf 'b a B' | run)"
check fewer "1 x" "$(printf 'x' | run -n 5)"
check empty "" "$(printf '' | run)"
check empty_rc 0 "$(printf '' | run >/dev/null; echo $?)"
check digits "2 42
1 x2" "$(printf '42 x2 42' | run)"
check bad_n 2 "$(echo a | run -n 0 >/dev/null 2>&1; echo $?)"
check bad_n2 2 "$(echo a | run -n abc >/dev/null 2>&1; echo $?)"
check bad_opt 2 "$(echo a | run -z >/dev/null 2>&1; echo $?)"
check bad_stderr 1 "$(echo a | run -z 2>&1 >/dev/null | grep -c .)"

# --- csv
check names "alice
bob \"b\" smith
carol
dave
eve
x" "$(bash solution.sh csv name fixture.csv)"
check by_index_quoted_header "10
2.50

-3
abc
.5" "$(bash solution.sh csv '#3' fixture.csv)"
check sum "count=4 sum=10 min=-3 max=10" "$(bash solution.sh csv -s 'amount, EUR' fixture.csv)"
check newline_value 'plain
multi\nline
a,b


z' "$(bash solution.sh csv note < fixture.csv)"
check none_numeric "count=0" "$(bash solution.sh csv -s name fixture.csv)"
printf 'a;b\n1;"x;y"\n2.5;z\n' > semi.csv
check delim "x;y
z" "$(bash solution.sh csv -d ';' b semi.csv)"
check delim_sum "count=2 sum=3.5 min=1 max=2.5" "$(bash solution.sh csv -d ';' -s a semi.csv)"
check unknown 3 "$(bash solution.sh csv nope fixture.csv >/dev/null 2>&1; echo $?)"
printf 'a\n"open\n' > bad.csv
check unterminated_rc 4 "$(bash solution.sh csv a bad.csv >/dev/null 2>&1; echo $?)"
check unterminated_out "" "$(bash solution.sh csv a bad.csv 2>/dev/null)"

# --- report
printf 'log,enabled\nfixture_a.log,yes\nb.log.gz,yes\nnope.log,no\n,yes\n' > m1.csv
check report "requests: 7
malformed: 2
status:
  200 4
  201 1
  304 1
  404 1
top_ips:
  203.0.113.9 5120
  10.0.0.1 1000
  198.51.100.2 300
top_paths:
  /api/v1/items 3
  /health 2
  /api/v1/items/7 1
top_words:
  4 api
  4 items
  4 v1" "$(bash solution.sh report m1.csv)"
printf 'name,log\nx,"fixture_b.log"\r\n' > m2.csv
check report_n_no_enabled_crlf "requests: 3
malformed: 0
status:
  200 2
  404 1
top_ips:
  10.0.0.3 122
  10.0.0.2 2
top_paths:
  /health 2
  /api/v1/items/7 1
top_words:
  2 health
  1 7
  1 api
  1 items
  1 v1" "$(bash solution.sh report -n 5 m2.csv)"
printf 'log,enabled\nfixture_b.log,no\n' > m3.csv
check report_none_used "requests: 0
malformed: 0
status:
top_ips:
top_paths:
top_words:" "$(bash solution.sh report m3.csv)"
printf 'file\nx\n' > m4.csv
check report_no_log_col 3 "$(bash solution.sh report m4.csv >/dev/null 2>&1; echo $?)"
printf 'log\n"x\n' > m5.csv
check report_unterminated 4 "$(bash solution.sh report m5.csv >/dev/null 2>&1; echo $?)"
printf 'log\nfixture_a.log\nmissing.log\n' > m6.csv
check report_missing_log 1 "$(bash solution.sh report m6.csv >/dev/null 2>&1; echo $?)"
check report_missing_log_out "" "$(bash solution.sh report m6.csv 2>/dev/null)"
check report_missing_manifest 1 "$(bash solution.sh report nope.csv >/dev/null 2>&1; echo $?)"
check report_bad_n 2 "$(bash solution.sh report -n 0 m1.csv >/dev/null 2>&1; echo $?)"
check report_bad_opt 2 "$(bash solution.sh report -z m1.csv >/dev/null 2>&1; echo $?)"
check bad_subcommand 2 "$(bash solution.sh bogus >/dev/null 2>&1; echo $?)"
check no_subcommand 2 "$(bash solution.sh >/dev/null 2>&1; echo $?)"
finish
